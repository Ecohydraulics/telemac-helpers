#!/usr/bin/env bash
# TELEMAC-MASCARET + SALOME installer for Debian 12
#
# Installs:
#   1. TELEMAC and dependencies
#   2. (Optionally) SALOME into ROOT_DIR/salome, with MED libraries wired into TELEMAC
#
# Usage examples:
#   chmod +x install_telemac_debian12.sh
#   ./install_telemac_debian12.sh
#
#   ./install_telemac_debian12.sh --root "$HOME/opt" --tag v9.1.1
#   ./install_telemac_debian12.sh --salome-tar ~/Downloads/SALOME-9.15.0.tar.gz
#   ./install_telemac_debian12.sh --salome-tar SALOME-9.15.0.tar.gz --salome-md5 SALOME-9.15.0.tar.gz.md5
#
# Do NOT run this script as root. Use a normal user with sudo rights.

set -euo pipefail

log()  { echo "[*] $*"; }
warn() { echo "[WARN] $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

detect_mime() {
  # Best-effort MIME type for a local file (requires 'file').
  # Examples: application/x-gzip, application/x-tar, application/zip, text/html
  local f="$1"
  if ! command -v file >/dev/null 2>&1; then
    echo ""
    return 0
  fi
  file -b --mime-type "$f" 2>/dev/null || echo ""
}

extract_md5_hash() {
  # Extract the first 32-hex MD5 hash from an md5 file.
  # Works for common formats:
  #   <hash>  <filename>
  #   MD5 (<filename>) = <hash>
  local md5file="$1"
  grep -Eo '[0-9a-fA-F]{32}' "$md5file" | head -n 1 || true
}

validate_archive_or_die() {
  # Fail early with a useful message when the SALOME archive is corrupt,
  # truncated, or not actually a compressed tarball.
  local archive="$1"

  if [ ! -s "$archive" ]; then
    die "SALOME archive '$archive' is empty (0 bytes). Re-download it."
  fi

  local mime
  mime="$(detect_mime "$archive")"

  if [ "$mime" = "text/html" ]; then
    die "SALOME archive '$archive' looks like HTML, not a tarball. Your download likely captured a web page instead of the file (follow redirects / use the official download page + md5)."
  fi

  case "$mime" in
    application/x-gzip|application/gzip)
      command -v gzip >/dev/null 2>&1 || die "gzip not found (install 'gzip')."
      if ! gzip -t "$archive" >/dev/null 2>&1; then
        die "SALOME archive '$archive' fails 'gzip -t' (corrupt or truncated). Re-download and verify its md5sum before extracting."
      fi
      ;;
    application/x-xz)
      command -v xz >/dev/null 2>&1 || die "xz not found (install 'xz-utils')."
      if ! xz -t "$archive" >/dev/null 2>&1; then
        die "SALOME archive '$archive' fails 'xz -t' (corrupt or truncated). Re-download and verify its md5sum before extracting."
      fi
      ;;
    application/x-bzip2)
      command -v bzip2 >/dev/null 2>&1 || die "bzip2 not found (install 'bzip2')."
      if ! bzip2 -t "$archive" >/dev/null 2>&1; then
        die "SALOME archive '$archive' fails 'bzip2 -t' (corrupt or truncated). Re-download and verify its md5sum before extracting."
      fi
      ;;
    application/zip)
      command -v unzip >/dev/null 2>&1 || die "unzip not found (install 'unzip')."
      if ! unzip -tq "$archive" >/dev/null 2>&1; then
        die "SALOME archive '$archive' fails 'unzip -t' (corrupt or truncated). Re-download and verify its md5sum before extracting."
      fi
      ;;
    application/x-tar|application/octet-stream|"" )
      # tar / unknown: we let extraction step validate further.
      ;;
    *)
      warn "Unrecognized archive MIME type '$mime' for '$archive'. Will try extraction based on extension."
      ;;
  esac
}

extract_archive_to_dir_or_die() {
  local archive="$1"
  local dest="$2"
  mkdir -p "$dest"

  local mime
  mime="$(detect_mime "$archive")"

  # Prefer extraction based on content, not filename.
  if [ -n "$mime" ]; then
    case "$mime" in
      application/x-gzip|application/gzip)
        tar -xzf "$archive" -C "$dest" --strip-components=1 || die "Failed to extract '$archive' as gzip tar (corrupt/truncated)."
        return 0
        ;;
      application/x-xz)
        tar -xJf "$archive" -C "$dest" --strip-components=1 || die "Failed to extract '$archive' as xz tar (corrupt/truncated)."
        return 0
        ;;
      application/x-bzip2)
        tar -xjf "$archive" -C "$dest" --strip-components=1 || die "Failed to extract '$archive' as bzip2 tar (corrupt/truncated)."
        return 0
        ;;
      application/x-tar)
        tar -xf "$archive" -C "$dest" --strip-components=1 || die "Failed to extract '$archive' as tar (corrupt/truncated)."
        return 0
        ;;
      application/zip)
        # SALOME provides both .zip and .tar.gz distributions.
        # We unzip to a temp dir, then flatten if there is a single top-level directory.
        local tmp
        tmp="$(mktemp -d)"
        unzip -q "$archive" -d "$tmp" || die "Failed to unzip '$archive' (corrupt/truncated)."
        # If there's exactly one directory at top-level, flatten it.
        local top_count
        top_count="$(find "$tmp" -mindepth 1 -maxdepth 1 -print | wc -l)"
        if [ "$top_count" -eq 1 ] && [ -d "$(find "$tmp" -mindepth 1 -maxdepth 1 -type d -print -quit)" ]; then
          local topdir
          topdir="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d -print -quit)"
          cp -a "$topdir"/. "$dest"/
        else
          cp -a "$tmp"/. "$dest"/
        fi
        rm -rf "$tmp"
        return 0
        ;;
    esac
  fi

  # Fallback: extension-based extraction.
  case "$archive" in
    *.tar.gz|*.tgz) tar -xzf "$archive" -C "$dest" --strip-components=1 || die "Failed to extract '$archive' as .tar.gz" ;;
    *.tar.xz)      tar -xJf "$archive" -C "$dest" --strip-components=1 || die "Failed to extract '$archive' as .tar.xz" ;;
    *.tar.bz2)     tar -xjf "$archive" -C "$dest" --strip-components=1 || die "Failed to extract '$archive' as .tar.bz2" ;;
    *.tar)         tar -xf "$archive" -C "$dest" --strip-components=1 || die "Failed to extract '$archive' as .tar" ;;
    *.zip)         unzip -q "$archive" -d "$dest" || die "Failed to extract '$archive' as .zip" ;;
    *)
      die "Unknown SALOME archive format for '$archive'."
      ;;
  esac
}

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --root DIR             Installation root directory (default: \$HOME/opt)
  --tag TAG              TELEMAC git tag or branch to checkout (default: v9.1.1)
  --repo URL             TELEMAC git repository URL
                         (default: https://gitlab.pam-retd.fr/otm/telemac-mascaret.git)

  --salome-tar FILE      Path to SALOME tarball to install into <root>/salome
  --salome-archive FILE  Alias for --salome-tar
  --salome-md5 FILE      Optional: .md5 file to verify SALOME tarball integrity

  --skip-apt             Do not install apt dependencies for TELEMAC or SALOME
  --skip-compile         Do not run compile_telemac.py
  --verbose              Enable verbose output during compilation
  -h, --help             Show this help and exit

Typical flow:
  1. Download SALOME-*.tar.gz and its .md5.
  2. Run this script with --salome-tar (and optionally --salome-md5).
  3. Source pysource.debian12.sh and use TELEMAC with MED support if SALOME is present.
EOF
}

# Defaults
ROOT_DIR="${ROOT_DIR:-$HOME/opt}"
TELEMAC_TAG="${TELEMAC_TAG:-v9.1.1}"
TELEMAC_REPO="${TELEMAC_REPO:-https://gitlab.pam-retd.fr/otm/telemac-mascaret.git}"

SALOME_TAR="${SALOME_TAR:-}"
SALOME_MD5="${SALOME_MD5:-}"

SKIP_APT=0
SKIP_COMPILE=0
VERBOSE=0

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root)
        shift
        [ "$#" -gt 0 ] || die "--root requires a path argument"
        ROOT_DIR="$1"
        ;;
      --tag)
        shift
        [ "$#" -gt 0 ] || die "--tag requires a tag or branch name"
        TELEMAC_TAG="$1"
        ;;
      --repo)
        shift
        [ "$#" -gt 0 ] || die "--repo requires a URL"
        TELEMAC_REPO="$1"
        ;;
      --salome-tar)
        shift
        [ "$#" -gt 0 ] || die "--salome-tar requires a path to the SALOME tarball"
        SALOME_TAR="$1"
        ;;
      --salome-archive)
        shift
        [ "$#" -gt 0 ] || die "--salome-archive requires a path to the SALOME tarball"
        SALOME_TAR="$1"
        ;;
      --salome-md5)
        shift
        [ "$#" -gt 0 ] || die "--salome-md5 requires a path to the SALOME .md5 file"
        SALOME_MD5="$1"
        ;;
      --skip-apt)
        SKIP_APT=1
        ;;
      --skip-compile)
        SKIP_COMPILE=1
        ;;
      --verbose)
        VERBOSE=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
    shift
  done
}

apt_install_deps_telemac() {
  if [ "$SKIP_APT" -eq 1 ]; then
    log "Skipping TELEMAC apt dependency installation (per --skip-apt)."
    return
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    die "'sudo' not found; install sudo or install dependencies manually."
  fi

  log "Installing TELEMAC build dependencies via apt (requires sudo)..."
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    git git-lfs \
    build-essential gfortran g++ make m4 \
    python3 python3-dev python3-venv python3-pip \
    python3-numpy python3-scipy python3-matplotlib python3-mpi4py python3-h5py \
    cmake \
    openmpi-bin libopenmpi-dev \
    libhdf5-dev hdf5-tools \
    libmedc-dev libmed-dev libmedimport-dev libmed-tools \
    libmetis-dev libparmetis-dev \
    libmumps-dev libscalapack-openmpi-dev \
    libblas-dev liblapack-dev \
    wget curl

  log "Running 'git lfs install' for the current user..."
  git lfs install
}

apt_install_deps_salome() {
  if [ "$SKIP_APT" -eq 1 ]; then
    log "Skipping SALOME apt dependency installation (per --skip-apt)."
    return
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    die "'sudo' not found; install SALOME dependencies manually."
  fi

  log "Installing SALOME runtime dependencies (best effort)..."
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    unzip bzip2 xz-utils \
    python3-pytest-cython python3-sphinx python3-alabaster python3-cftime \
    libcminpack1 python3-docutils libfreeimage3 python3-h5py python3-imagesize \
    liblapacke clang python3-netcdf4 libnlopt0 libnlopt-cxx0 python3-nlopt \
    python3-nose python3-numpydoc python3-patsy python3-psutil libtbb12 \
    libxml++2.6-2v5 liblzf1 python3-stemmer python3-sphinx-rtd-theme \
    python3-sphinxcontrib.websupport sphinx-intl python3-statsmodels \
    python3-toml python-is-python3 \
    || warn "SALOME runtime deps: some packages may be missing; check with 'sat config --check_system'."

  log "Installing SALOME compile-time dependencies (best effort)..."
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    pyqt5-dev pyqt5-dev-tools libboost-all-dev libcminpack-dev libcppunit-dev \
    doxygen libeigen3-dev libfreeimage-dev libgraphviz-dev libjsoncpp-dev \
    liblapacke-dev libxml2-dev llvm-dev libnlopt-dev libnlopt-cxx-dev \
    python3-patsy libqwt-qt5-dev libfontconfig1-dev libglu1-mesa-dev \
    libxcb-dri2-0-dev libxkbcommon-dev libxkbcommon-x11-dev libxi-dev \
    libxmu-dev libxpm-dev libxft-dev libicu-dev libsqlite3-dev libxcursor-dev \
    libtbb-dev libqt5svg5-dev libqt5x11extras5-dev qtxmlpatterns5-dev-tools \
    libpng-dev libtiff5-dev libgeotiff-dev libgif-dev libgeos-dev libgdal-dev \
    texlive-latex-base libxml++2.6-dev libfreetype6-dev libgmp-dev libmpfr-dev \
    libxinerama-dev python3-sip-dev python3-statsmodels tcl-dev tk-dev \
    || warn "SALOME compile deps: some packages may be missing; check with 'sat config --check_system'."
}

install_salome_if_requested() {
  if [ -z "$SALOME_TAR" ]; then
    log "No SALOME tarball specified; skipping SALOME installation."
    return
  fi

  if [ ! -f "$SALOME_TAR" ]; then
    die "SALOME tarball '$SALOME_TAR' not found."
  fi

  # Auto-detect md5 file if the user didn't provide one.
  if [ -z "$SALOME_MD5" ] && [ -f "${SALOME_TAR}.md5" ]; then
    SALOME_MD5="${SALOME_TAR}.md5"
    log "Auto-detected SALOME md5 file: '$SALOME_MD5'"
  fi

  if [ -n "$SALOME_MD5" ]; then
    if [ ! -f "$SALOME_MD5" ]; then
      die "SALOME md5 file '$SALOME_MD5' not found."
    fi
    log "Verifying SALOME tarball MD5 against '$SALOME_MD5'..."
    local expected got
    expected="$(extract_md5_hash "$SALOME_MD5")"
    [ -n "$expected" ] || die "Could not parse an MD5 hash from '$SALOME_MD5'."
    got="$(md5sum "$SALOME_TAR" | awk '{print $1}')"
    if [ "$expected" != "$got" ]; then
      die "SALOME MD5 mismatch: expected $expected, got $got"
    fi
    log "SALOME tarball MD5 check passed."
  else
    warn "No --salome-md5 provided; SALOME tarball integrity not verified."
  fi

  # Validate archive before extraction to avoid opaque tar/gzip errors.
  validate_archive_or_die "$SALOME_TAR"

  apt_install_deps_salome

  local SALOME_ROOT="${ROOT_DIR}/salome"
  log "Installing SALOME tarball '$SALOME_TAR' into '$SALOME_ROOT'..."
  mkdir -p "$SALOME_ROOT"

  extract_archive_to_dir_or_die "$SALOME_TAR" "$SALOME_ROOT"

  # Fix ownership to current user and primary group (robust chown as in workflow)
  chown -R "$USER":"$(id -gn "$USER")" "$SALOME_ROOT" || \
    warn "Failed to chown SALOME install; check permissions on '$SALOME_ROOT'."

  log "SALOME extraction completed in '$SALOME_ROOT'."

  local SALOME_SAT_DIR="${SALOME_ROOT}/sat"
  if [ -d "$SALOME_SAT_DIR" ]; then
    log "Recommended SALOME system check (run manually):"
    echo "  cd \"$SALOME_SAT_DIR\""
    echo "  ./sat config --list"
    echo "  ./sat config <APPNAME> --check_system"
    echo "Install any missing packages it reports and rerun until clean."
  else
    warn "SALOME 'sat' directory not found at '$SALOME_SAT_DIR'; layout may differ from the workflow."
  fi
}

detect_salome_med_root() {
  # Try to locate MED libraries from a SALOME install.
  # Supported layouts (common for SALOME native packages):
  #   ${ROOT_DIR}/salome/SALOME-*/BINARIES-*/medfile
  #   ${ROOT_DIR}/salome/BINARIES-*/medfile
  #   $HOME/opt/salome/... (fallback)
  local search_roots=()

  [ -n "${SALOME_DIR:-}" ] && [ -d "${SALOME_DIR}" ] && search_roots+=("${SALOME_DIR}")
  [ -d "${ROOT_DIR}/salome" ] && search_roots+=("${ROOT_DIR}/salome")
  [ -d "$HOME/opt/salome" ] && search_roots+=("$HOME/opt/salome")

  local d
  for base in "${search_roots[@]}"; do
    while IFS= read -r d; do
      [ -d "${d}/lib" ] || continue
      # Check for core MED shared libs to avoid false positives
      if ls "${d}/lib"/libmedC.* "${d}/lib"/libmed.* >/dev/null 2>&1; then
        echo "${d}"
        return 0
      fi
    done < <(find "${base}" -maxdepth 6 -type d -name medfile 2>/dev/null)
  done

  echo ""
}

detect_system_med_root() {
  # Prefer system MED (Debian packages) for TELEMAC to avoid ABI mismatches with SALOME-bundled MED.
  # Returns "/usr" if libmedC + headers are found, else empty.
  local arch
  arch="$(gcc -dumpmachine 2>/dev/null || echo x86_64-linux-gnu)"
  local libdir="/usr/lib/${arch}"

  if [ -e "/usr/include/med.h" ] && { ls "${libdir}/libmedC.so"* >/dev/null 2>&1 || ldconfig -p 2>/dev/null | grep -q "libmedC.so"; }; then
    echo "/usr"
    return 0
  fi

  echo ""
}

detect_med_int_macro() {
  # Pick the right HERMES preprocessor flag for the MED integer width.
  #   32-bit med_int -> HAVE_MED ; 64-bit med_int -> HAVE_MED HAVE_MED64
  # Read from a med.h (defaults to the system header). Note: HERMES only checks
  # HAVE_MED / HAVE_MED64 -- HAVE_MED4 is NOT used by the MED sources, so the
  # earlier '-DHAVE_MED4' was a harmless no-op and has been dropped.
  local medh="${1:-/usr/include/med.h}"
  if grep -qE 'typedef[[:space:]]+(long|long long|med_int64|int64_t)[[:space:]]+med_int[[:space:]]*;' "$medh" 2>/dev/null; then
    echo "-DHAVE_MED -DHAVE_MED64"
  else
    echo "-DHAVE_MED"
  fi
}

clone_telemac() {
  mkdir -p "$ROOT_DIR"
  cd "$ROOT_DIR"

  if [ ! -d "telemac-mascaret" ]; then
    log "Cloning TELEMAC from '${TELEMAC_REPO}' into '${ROOT_DIR}/telemac-mascaret'..."
    git clone "$TELEMAC_REPO" telemac-mascaret
  else
    log "Existing '${ROOT_DIR}/telemac-mascaret' directory found; reusing it."
  fi

  cd telemac-mascaret

  if [ -n "${TELEMAC_TAG}" ]; then
    log "Checking out TELEMAC tag or branch '${TELEMAC_TAG}' if it exists..."
    git fetch --tags
    if git rev-parse --verify --quiet "${TELEMAC_TAG}" >/dev/null; then
      git checkout "${TELEMAC_TAG}"
    else
      warn "Tag or branch '${TELEMAC_TAG}' not found; staying on current branch."
    fi
  fi
}

create_cfg() {
  local HOMETEL="$1"
  local CFG_PATH="${HOMETEL}/configs/systel.debian12.cfg"

  log "Creating TELEMAC configuration '${CFG_PATH}'..."
  mkdir -p "${HOMETEL}/configs"

  local SALOME_MED_ROOT
  SALOME_MED_ROOT="$(detect_salome_med_root)"

  local SYSTEM_MED_ROOT
  SYSTEM_MED_ROOT="$(detect_system_med_root)"

  local MED_ENABLED=0

  local SALOME_INC_BLOCK=""
  local SALOME_LIB_BLOCK=""
  local SALOME_INCS_ALL_MED=""
  local SALOME_LIBS_ALL_MED=""
  local SALOME_RPATH_MED=""
  local MED_OPTIONS=""
  local MED_FFLAGS=""
  local MED_CFLAGS=""

  # IMPORTANT: Always prefer system MED (Debian packages) over SALOME-bundled MED.
  # SALOME bundles its own MED library with a different ABI (MED 4.2.x built with
  # 64-bit med_int vs Debian's MED 4.1.x with 32-bit med_int).
  # Mixing them causes symbol size mismatches like:
  #   "warning: size of symbol `med_' changed from 96 ... to 192"
  # and runtime errors like HERMES_WRONG_MED_FORMAT_ERR.

  if [ -n "$SYSTEM_MED_ROOT" ]; then
    # Use Debian-packaged MED (preferred for ABI consistency).
    local arch
    arch="$(gcc -dumpmachine 2>/dev/null || echo x86_64-linux-gnu)"
    local SYS_MED_LIB="/usr/lib/${arch}"
    local MEDIMPORT_FLAG=""
    if ls "${SYS_MED_LIB}/libmedimport.so"* >/dev/null 2>&1; then
      MEDIMPORT_FLAG=" -lmedimport"
    fi

    log "Using system MED libraries in /usr (libdir: ${SYS_MED_LIB}); enabling MED support in cfg."

    # Check for missing Fortran headers (Debian's libmed-dev is incomplete)
    # med_parameter.hf contains only constant definitions (no ABI-sensitive code)
    # so it's safe to copy from SALOME if missing.
    local MED_INC_DIR="/usr/include"
    if [ ! -f "/usr/include/med_parameter.hf" ]; then
      warn "Debian MED package is missing 'med_parameter.hf' (Fortran header)."

      # Try to find and copy from SALOME
      if [ -n "$SALOME_MED_ROOT" ] && [ -f "${SALOME_MED_ROOT}/include/med_parameter.hf" ]; then
        log "Copying missing MED Fortran headers from SALOME..."

        # Create a local include directory for patched headers
        local MED_PATCH_DIR="${HOMETEL}/configs/med_include"
        mkdir -p "$MED_PATCH_DIR"

        # Copy the missing Fortran header from SALOME (constant definitions only,
        # ABI-neutral). The system already ships med.hf, so only med_parameter.hf
        # is needed; the patched dir is placed first in the include path.
        for hf in med_parameter.hf; do
          if [ -f "${SALOME_MED_ROOT}/include/${hf}" ]; then
            cp "${SALOME_MED_ROOT}/include/${hf}" "$MED_PATCH_DIR/"
            log "  Copied ${hf} to $MED_PATCH_DIR"
          fi
        done

        # Use patched directory first, then system
        MED_INC_DIR="${MED_PATCH_DIR} -I /usr/include"
        log "MED include paths: -I ${MED_INC_DIR}"
      else
        warn "Cannot find med_parameter.hf in SALOME either."
        warn "MED Fortran support may not work. You can try:"
        warn "  1. Install SALOME and rerun this script"
        warn "  2. Download MED source and copy include/*.hf to /usr/include/"
        warn "  3. Disable MED: edit systel.debian12.cfg and remove 'med' from options"
      fi
    fi

    SALOME_INC_BLOCK="inc_med:       -I ${MED_INC_DIR}"
    SALOME_LIB_BLOCK="libs_med:      -L ${SYS_MED_LIB} -lmedC -lmed${MEDIMPORT_FLAG}"
    SALOME_INCS_ALL_MED="[inc_med] "
    SALOME_LIBS_ALL_MED="[libs_med] "
    SALOME_RPATH_MED=""

    # Enable MED option and preprocessor flags for HERMES to load MED support.
    # The HAVE_MED/HAVE_MED64 choice is auto-detected from the system med.h to
    # match the system MED integer width (Debian ships 32-bit -> HAVE_MED).
    MED_OPTIONS=" med"
    MED_FFLAGS=" $(detect_med_int_macro)"
    MED_CFLAGS=" $(detect_med_int_macro)"
    MED_ENABLED=1

    # Warn if SALOME MED is also present (C library will be ignored to avoid ABI mismatch)
    if [ -n "$SALOME_MED_ROOT" ]; then
      log "SALOME MED detected at '$SALOME_MED_ROOT'."
      log "Using system MED C library (/usr) for ABI consistency."
      log "SALOME Fortran headers used to patch incomplete Debian package."
    fi

  elif [ -n "$SALOME_MED_ROOT" ]; then
    # Fallback to SALOME MED only if system MED is not available.
    # WARNING: This may cause issues if SALOME's MED ABI differs from other system libs.
    log "System MED not found. Using SALOME MED at '$SALOME_MED_ROOT' (fallback)."
    warn "Using SALOME-bundled MED may cause ABI issues. Consider installing: sudo apt-get install libmedc-dev libmed-dev libmedimport-dev"
    SALOME_INC_BLOCK="inc_med:       -I ${SALOME_MED_ROOT}/include"
    SALOME_LIB_BLOCK="libs_med:      -L ${SALOME_MED_ROOT}/lib -lmedC -lmed -lmedimport"
    SALOME_INCS_ALL_MED="[inc_med] "
    SALOME_LIBS_ALL_MED="[libs_med] "
    SALOME_RPATH_MED=" -Wl,-rpath,${SALOME_MED_ROOT}/lib"

    # Enable MED option and preprocessor flags for HERMES to load MED support.
    # Detect the integer width from SALOME's own med.h (SALOME MED is typically
    # built with a 64-bit med_int -> HAVE_MED64).
    MED_OPTIONS=" med"
    MED_FFLAGS=" $(detect_med_int_macro "${SALOME_MED_ROOT}/include/med.h")"
    MED_CFLAGS=" $(detect_med_int_macro "${SALOME_MED_ROOT}/include/med.h")"
    MED_ENABLED=1

    # Check for SALOME's bundled HDF5 (MED library may depend on it)
    local SALOME_HDF5_LIB="${SALOME_MED_ROOT}/../hdf5/lib"
    if [ -d "$SALOME_HDF5_LIB" ]; then
      SALOME_HDF5_LIB="$(cd "$SALOME_HDF5_LIB" && pwd)"
      log "Detected SALOME bundled HDF5 at '$SALOME_HDF5_LIB'; adding to rpath."
      SALOME_RPATH_MED="${SALOME_RPATH_MED} -Wl,-rpath,${SALOME_HDF5_LIB}"
    fi

  else
    log "No MED libraries detected (system or SALOME); cfg will be generated without MED support."
  fi

  cat > "$CFG_PATH" <<EOF
# _____                              _______________________________
# ____/ TELEMAC Project Definitions /______________________________/
#
[Configurations]
configs: hyinfompideb12
#
# _____          _________________________________________________
# ____/ General /_________________________________________________/
#
[general]
language: 2
modules:  system stbtel telemac2d telemac3d tomawac artemis gaia nestor khione waqtel postel3d hermes special
version:  9.1
options:  mpi dyn${MED_OPTIONS}
hash_char: #
# Suffixes
sfx_zip:  .tar.gz
sfx_lib:  .a
sfx_obj:  .o
sfx_exe:
sfx_mod:  .mod
# Validation paths
val_root:      <root>/examples
val_rank:      all
# Compilers
cc:      mpicc
cflags:  -fPIC -O3${MED_CFLAGS}
fc:      mpifort
fflags:  -cpp -O3 -fPIC -fconvert=big-endian -frecord-marker=4 -DHAVE_MPI${MED_FFLAGS}
cmd_obj_c: [cc] [cflags] -c <srcName> -o <objName>
cmd_obj:   [fc] [fflags] -c <mods> <incs> <f95name>
cmd_lib:   ar crs <libname> <objs>
cmd_exe:   [fc] [fflags] -o <exename> <objs> <libs>
par_cmdexec:   <config>/partel < <partel.par> >> <partel.log>
mpi_cmdexec:   mpirun -np <ncsize> <exename>

# MPI headers (OpenMPI)
inc_mpi:       -I /usr/lib/x86_64-linux-gnu/openmpi/include

# HDF5 (serial)
inc_hdf5:      -I /usr/include/hdf5/serial
libs_hdf5:     -L /usr/lib/x86_64-linux-gnu/hdf5/serial -lhdf5_fortran -lhdf5hl_fortran -lhdf5_hl -lhdf5

# MED-fichier (optional)
$SALOME_INC_BLOCK
$SALOME_LIB_BLOCK

# METIS
inc_metis:     -I /usr/include
libs_metis:    -L /usr/lib/x86_64-linux-gnu -lmetis

# MUMPS + ScaLAPACK
inc_mumps:     -I /usr/include
libs_mumps:    -L /usr/lib/x86_64-linux-gnu -ldmumps -lmumps_common -lpord -lscalapack-openmpi -lblas -llapack

incs_all: [inc_mpi] [inc_hdf5] ${SALOME_INCS_ALL_MED}[inc_metis] [inc_mumps]
libs_all: ${SALOME_LIBS_ALL_MED}[libs_hdf5] [libs_metis] [libs_mumps]
mods_all: -I <config>

[hyinfompideb12]
brief: Debian 12 gfortran + OpenMPI + HDF5 + METIS + MUMPS/ScaLAPACK$( [ "$MED_ENABLED" -eq 1 ] && printf " + MED" || printf "" )
system: linux
mpi:   openmpi
compiler: gfortran
pyd_fcompiler: gnu95
f2py_name: f2py
bin_dir: <root>/builds/hyinfompideb12/bin
lib_dir: <root>/builds/hyinfompideb12/lib
obj_dir: <root>/builds/hyinfompideb12/obj
options: mpi dyn${MED_OPTIONS}
cmd_obj:   [fc] [fflags] -c <mods> <incs> <f95name>
cmd_lib:   ar crs <libname> <objs>
cmd_exe:   [fc] [fflags] -o <exename> <objs> <libs>
mods_all:  -I <config>
incs_all:  [inc_mpi] [inc_hdf5] ${SALOME_INCS_ALL_MED}[inc_metis] [inc_mumps]
libs_all:  ${SALOME_LIBS_ALL_MED}[libs_hdf5] [libs_metis] [libs_mumps]
ldflags_opt:   -Wl,-rpath,/usr/lib/x86_64-linux-gnu/hdf5/serial${SALOME_RPATH_MED}
ldflags_debug: -Wl,-rpath,/usr/lib/x86_64-linux-gnu/hdf5/serial${SALOME_RPATH_MED}
EOF
}

create_pysource() {
  local HOMETEL="$1"
  local PYSOURCE_PATH="${HOMETEL}/configs/pysource.debian12.sh"

  log "Creating TELEMAC environment script '${PYSOURCE_PATH}'..."
  mkdir -p "${HOMETEL}/configs"

  cat > "$PYSOURCE_PATH" <<'EOF'
#!/usr/bin/env bash
# TELEMAC environment for Debian 12
# TELEMAC under HOMETEL, SALOME under ROOT_DIR/salome

# Resolve script directory and HOMETEL
_THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMETEL="$(cd "${_THIS_DIR}/.." && pwd)"
export SOURCEFILE="${_THIS_DIR}"

# TELEMAC configuration file and config name
export SYSTELCFG="${HOMETEL}/configs/systel.debian12.cfg"
export USETELCFG="hyinfompideb12"

# Ensure these environment variables exist even if they were unset
: "${LD_LIBRARY_PATH:=}"
: "${CPATH:=}"
: "${PYTHONPATH:=}"

# Put TELEMAC helper scripts on PATH
if [ -d "${HOMETEL}/scripts/python3" ]; then
  case ":${PATH}:" in
    *:"${HOMETEL}/scripts/python3":*) ;;
    *) export PATH="${HOMETEL}/scripts/python3:${PATH}";;
  esac
fi
if [ -d "${HOMETEL}/scripts/unix" ]; then
  case ":${PATH}:" in
    *:"${HOMETEL}/scripts/unix":*) ;;
    *) export PATH="${HOMETEL}/scripts/unix:${PATH}";;
  esac
fi

# TELEMAC build bin (partel, gretel, etc.)
_TEL_BIN="${HOMETEL}/builds/${USETELCFG}/bin"
if [ -d "${_TEL_BIN}" ]; then
  case ":${PATH}:" in
    *:"${_TEL_BIN}":*) ;;
    *) export PATH="${_TEL_BIN}:${PATH}";;
  esac
fi

# Detect Debian multiarch lib directory
_arch="$(gcc -dumpmachine 2>/dev/null || echo x86_64-linux-gnu)"
_archlib="/usr/lib/${_arch}"

# Helper: return first existing directory from a list
_first_dir() {
  for _d in "$@"; do
    [ -d "$_d" ] && { printf '%s' "$_d"; return 0; }
  done
  return 1
}

# MPI (OpenMPI)
_MPI_BIN="$(dirname "$(command -v mpif90 2>/dev/null || command -v mpifort 2>/dev/null || command -v mpicc 2>/dev/null || echo /usr/bin/mpif90)")"
_MPI_INC="$(_first_dir \
  "${_archlib}/openmpi/include" \
  "/usr/include/openmpi" \
  "/usr/include/mpi" \
  "${_archlib}/mpi/include")"
_MPI_LIB="$(_first_dir \
  "${_archlib}/openmpi/lib" \
  "${_archlib}" \
  "/usr/lib")"

# HDF5 (serial)
_HDF5_INC="$(_first_dir \
  "/usr/include/hdf5/serial" \
  "/usr/include/hdf5/openmpi")"
_HDF5_LIB="$(_first_dir \
  "${_archlib}/hdf5/serial" \
  "${_archlib}/hdf5/openmpi" \
  "${_archlib}")"

# MED (system)
# TELEMAC is built against Debian-packaged MED by default.
# IMPORTANT: Do NOT use SALOME-bundled MED - it has different ABI (symbol sizes differ).
_MED_INC=""
_MED_LIB=""
if [ -e "/usr/include/med.h" ]; then
  _MED_INC="/usr/include"
fi
if [ -e "${_archlib}/libmedC.so" ] || ls "${_archlib}/libmedC.so"* >/dev/null 2>&1; then
  _MED_LIB="${_archlib}"
fi

# Detect SALOME installation (if present) to warn about potential ABI conflicts
_SALOME_ROOT=""
_SALOME_MED_LIB=""
_ROOT_DIR="$(cd "${HOMETEL}/.." && pwd)"
for _salome_search in "${_ROOT_DIR}/salome" "$HOME/opt/salome"; do
  if [ -d "${_salome_search}" ]; then
    _SALOME_ROOT="${_salome_search}"
    # Find SALOME's bundled MED library path
    _found_med="$(find "${_SALOME_ROOT}" -maxdepth 6 -type d -name medfile 2>/dev/null | head -n 1)"
    if [ -n "${_found_med}" ] && [ -d "${_found_med}/lib" ]; then
      _SALOME_MED_LIB="${_found_med}/lib"
    fi
    break
  fi
done

# METIS, ParMETIS, MUMPS, ScaLAPACK
_METIS_INC="$(_first_dir "/usr/include")"
_METIS_LIB="$(_first_dir "${_archlib}")"
_PARMETIS_INC="$(_first_dir "/usr/include")"
_PARMETIS_LIB="$(_first_dir "${_archlib}")"
_MUMPS_INC="$(_first_dir "/usr/include/mumps" "/usr/include")"
_MUMPS_LIB="$(_first_dir "${_archlib}")"
_SCALAPACK_LIB="$(_first_dir "${_archlib}")"

# PATH
for _bindir in \
  "${_MPI_BIN}" \
  "/usr/bin"
do
  [ -n "${_bindir}" ] || continue
  case ":${PATH}:" in
    *:"${_bindir}":*) ;;
    *) export PATH="${_bindir}:${PATH}";;
  esac
done

# LD_LIBRARY_PATH

for _libdir in \
  "${_MPI_LIB}" \
  "${_HDF5_LIB}" \
  "${_SCALAPACK_LIB}" \
  "${_MUMPS_LIB}" \
  "${_METIS_LIB}" \
  "${_PARMETIS_LIB}" \
  "${_MED_LIB}"
do
  [ -n "${_libdir}" ] || continue
  case ":${LD_LIBRARY_PATH}:" in
    *:"${_libdir}":*) ;;
    *) export LD_LIBRARY_PATH="${_libdir}:${LD_LIBRARY_PATH}";;
  esac
done

# CRITICAL: Remove SALOME MED paths from LD_LIBRARY_PATH to prevent ABI mismatch.
# SALOME bundles MED with different symbol sizes (e.g., med_ is 192 bytes vs system's 96 bytes).
# If SALOME's MED is loaded at runtime while TELEMAC was compiled against system MED,
# you get: "HERMES_WRONG_MED_FORMAT_ERR" or "size of symbol 'med_' changed" warnings.
if [ -n "${_SALOME_MED_LIB}" ] && [ -n "${_MED_LIB}" ]; then
  # Helper function to remove a path from LD_LIBRARY_PATH
  _remove_from_ldpath() {
    local _remove="$1"
    local _new_path=""
    local _IFS_old="$IFS"
    IFS=':'
    for _p in $LD_LIBRARY_PATH; do
      case "${_p}" in
        "${_remove}"|"${_remove}/"*) continue ;;  # Skip SALOME MED and subdirs
      esac
      if [ -z "${_new_path}" ]; then
        _new_path="${_p}"
      else
        _new_path="${_new_path}:${_p}"
      fi
    done
    IFS="$_IFS_old"
    echo "${_new_path}"
  }

  # Also find and remove SALOME's HDF5 if it exists (MED may link to it)
  _SALOME_HDF5_LIB=""
  if [ -d "$(dirname "${_SALOME_MED_LIB}")/hdf5/lib" ]; then
    _SALOME_HDF5_LIB="$(cd "$(dirname "${_SALOME_MED_LIB}")/hdf5/lib" 2>/dev/null && pwd)"
  fi

  # Remove SALOME MED from LD_LIBRARY_PATH
  export LD_LIBRARY_PATH="$(_remove_from_ldpath "${_SALOME_MED_LIB}")"
  if [ -n "${_SALOME_HDF5_LIB}" ]; then
    export LD_LIBRARY_PATH="$(_remove_from_ldpath "${_SALOME_HDF5_LIB}")"
  fi

  echo "[WARN] SALOME detected at '${_SALOME_ROOT}' with bundled MED at '${_SALOME_MED_LIB}'."
  echo "[WARN] Using system MED ('${_MED_LIB}') to avoid ABI mismatch (symbol size differences)."
  echo "[WARN] SALOME MED paths have been removed from LD_LIBRARY_PATH."
fi

# CPATH (for compilers that honor it)
for _incdir in \
  "${_MPI_INC}" \
  "${_HDF5_INC}" \
  "${_MED_INC}" \
  "${_METIS_INC}" \
  "${_PARMETIS_INC}" \
  "${_MUMPS_INC}"
do
  [ -n "${_incdir}" ] || continue
  case ":${CPATH}:" in
    *:"${_incdir}":*) ;;
    *) export CPATH="${_incdir}:${CPATH}";;
  esac
done

# TELEMAC Python API (TelApy) if built
_wrap_api_lib="${HOMETEL}/builds/${USETELCFG}/wrap_api/lib"
if [ -d "${_wrap_api_lib}" ]; then
  case ":${PYTHONPATH}:" in
    *:"${_wrap_api_lib}":*) ;;
    *) export PYTHONPATH="${_wrap_api_lib}:${PYTHONPATH}";;
  esac
  case ":${LD_LIBRARY_PATH}:" in
    *:"${_wrap_api_lib}":*) ;;
    *) export LD_LIBRARY_PATH="${_wrap_api_lib}:${LD_LIBRARY_PATH}";;
  esac
fi

# Ensure TELEMAC python scripts are on PYTHONPATH as well
if [ -d "${HOMETEL}/scripts/python3" ]; then
  case ":${PYTHONPATH}:" in
    *:"${HOMETEL}/scripts/python3":*) ;;
    *) export PYTHONPATH="${HOMETEL}/scripts/python3:${PYTHONPATH}";;
  esac
fi

echo "TELEMAC set: HOMETEL='${HOMETEL}', SYSTELCFG='${SYSTELCFG}', USETELCFG='${USETELCFG}'"
echo "MPI bin='${_MPI_BIN}', MPI inc='${_MPI_INC}', MPI lib='${_MPI_LIB}'"
echo "HDF5 inc='${_HDF5_INC}', HDF5 lib='${_HDF5_LIB}'"
if [ -n "${_MED_LIB}" ]; then
  echo "MED lib='${_MED_LIB}' (system)"
fi

export PYTHONUNBUFFERED="1"
EOF

  chmod +x "$PYSOURCE_PATH"
}

verify_telemac_build() {
  # Verify that key TELEMAC executables were built successfully
  local HOMETEL="$1"
  local USETELCFG="hyinfompideb12"
  local BUILD_BIN="${HOMETEL}/builds/${USETELCFG}/bin"
  local BUILD_LIB="${HOMETEL}/builds/${USETELCFG}/lib"

  log "Verifying TELEMAC build artifacts..."

  if [ ! -d "${BUILD_BIN}" ]; then
    warn "Build bin directory not found: ${BUILD_BIN}"
    warn "This indicates compilation may have failed. Check output above for errors."
    return 1
  fi

  if [ ! -d "${BUILD_LIB}" ]; then
    warn "Build lib directory not found: ${BUILD_LIB}"
    warn "This indicates compilation may have failed. Check output above for errors."
    return 1
  fi

  local missing_exes=()
  local required_exes=("stbtel" "telemac2d" "telemac3d" "tomawac" "artemis" "gaia" "partel" "gretel")

  for exe in "${required_exes[@]}"; do
    if [ ! -f "${BUILD_BIN}/${exe}" ]; then
      missing_exes+=("$exe")
    fi
  done

  if [ ${#missing_exes[@]} -gt 0 ]; then
    warn "The following executables are missing from ${BUILD_BIN}:"
    for exe in "${missing_exes[@]}"; do
      warn "  - ${exe}"
    done
    warn ""
    warn "Possible causes:"
    warn "  1. Compilation errors for specific modules (check compile_telemac.py output above)"
    warn "  2. Missing Fortran HDF5 libraries (ensure libhdf5-fortran-102 (or libhdf5-dev) is installed)"
    warn "  3. Module not enabled in systel.cfg (check 'modules:' line)"
    warn ""
    warn "To debug, run manually:"
    warn "  source ${HOMETEL}/configs/pysource.debian12.sh"
    warn "  compile_telemac.py -v"
    return 1
  fi

  log "Build verification passed. Found all required executables in ${BUILD_BIN}"
  return 0
}

run_compile() {
  local HOMETEL="$1"

  if [ "$SKIP_COMPILE" -eq 1 ]; then
    log "Skipping TELEMAC compilation (per --skip-compile)."
    return
  fi

  log "Running TELEMAC config and compile steps..."
  log "This may take 10-30 minutes depending on your system."

  # Unset DISPLAY to avoid MPI/X11 authorization issues
  unset DISPLAY

  # Determine verbosity flag for compile_telemac.py
  local verbose_flag=""
  if [ "$VERBOSE" -eq 1 ]; then
    verbose_flag="-v"
    log "Verbose mode enabled."
  fi

  # Run compilation in a subshell with explicit error handling
  local compile_status=0
  bash -lc "
    set -euo pipefail
    cd \"$HOMETEL\"
    source \"$HOMETEL/configs/pysource.debian12.sh\"

    echo '[*] Running config.py to validate configuration...'
    config.py

    echo '[*] Running compile_telemac.py (this will take a while)...'
    # Use --clean to ensure a fresh build
    compile_telemac.py --clean $verbose_flag
  " || compile_status=$?

  if [ "$compile_status" -ne 0 ]; then
    die "TELEMAC compilation failed with exit code $compile_status. See errors above."
  fi

  log "TELEMAC compilation command completed."

  # Verify the build produced expected outputs
  if ! verify_telemac_build "$HOMETEL"; then
    warn "Build verification found issues. TELEMAC may not work correctly."
    warn "You can try running 'compile_telemac.py' manually to see detailed errors."
  else
    log "TELEMAC compilation completed successfully."
  fi
}

main() {
  if [ "$(id -u)" -eq 0 ]; then
    die "Do not run this script as root. Use a normal user with sudo."
  fi

  parse_args "$@"

  log "Installation root:     $ROOT_DIR"
  log "TELEMAC repository:    $TELEMAC_REPO"
  log "TELEMAC tag/branch:    $TELEMAC_TAG"
  if [ -n "$SALOME_TAR" ]; then
    log "SALOME tarball:        $SALOME_TAR"
    [ -n "$SALOME_MD5" ] && log "SALOME md5 file:       $SALOME_MD5"
  else
    log "SALOME tarball:        not specified (SALOME optional; system MED still available)."
  fi

  apt_install_deps_telemac
  install_salome_if_requested
  clone_telemac

  local HOMETEL
  HOMETEL="$(cd "${ROOT_DIR}/telemac-mascaret" && pwd)"

  create_cfg "$HOMETEL"
  create_pysource "$HOMETEL"
  run_compile "$HOMETEL"

  local SYSTEM_MED_ROOT SALOME_MED_ROOT
  SYSTEM_MED_ROOT="$(detect_system_med_root)"
  SALOME_MED_ROOT="$(detect_salome_med_root)"

  log "Installation finished."
  echo
  echo "To use TELEMAC in a new shell:"
  echo "  cd \"$HOMETEL/configs\""
  echo "  source pysource.debian12.sh"
  echo "  telemac2d.py --help"
  echo
  if [ -n "$SYSTEM_MED_ROOT" ]; then
    echo "MED support: enabled (system /usr)."
  elif [ -n "$SALOME_MED_ROOT" ]; then
    echo "MED support: enabled (SALOME fallback at '$SALOME_MED_ROOT')."
  else
    echo "MED support: not detected."
    echo "If you want MED I/O, install Debian packages:"
    echo "  sudo apt-get install libmedc-dev libmed-dev libmedimport-dev libmed-tools"
    echo "Then rerun config.py and compile_telemac.py."
  fi
}

main "$@"

