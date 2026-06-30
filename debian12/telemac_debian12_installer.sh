#!/usr/bin/env bash
# TELEMAC-MASCARET + SALOME installer for Debian 12
#
# Copyright (C) 2026 Sebastian Schwindt
#
# This script is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or, at your
# option, any later version.
#
# This script is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
# for more details.
#
# WARNING:
# This script may install system packages, download third-party source code,
# compile software, create symbolic links, and modify user-level desktop/menu
# entries. Review the script before running it. Use it at your own risk.
# Do not run it on production, shared, institutional, or safety-critical
# systems unless you have authorization, backups, and a tested recovery plan.
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

cat <<'EOF'
This installer is provided without warranty.

It may install packages, download third-party code, compile software,
create symlinks, and modify user-level desktop/menu entries. Review the
script before continuing. Use at your own risk.

EOF

set -euo pipefail

log()  { echo "[*] $*"; }
warn() { echo "[WARN] $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

# Avoid foreign Python setups during TELEMAC CMake configuration/runtime.
unset PYTHONHOME
unset CONDA_PREFIX
unset CONDA_DEFAULT_ENV
unset VIRTUAL_ENV
unset MAMBA_ROOT_PREFIX

export Python_ROOT_DIR="/usr"
export Python_EXECUTABLE="/usr/bin/python3"

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
  --skip-compile         Do not run the CMake build (build_telemac.py)
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
  local arch libdir

  arch="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || gcc -dumpmachine 2>/dev/null || echo x86_64-linux-gnu)"
  libdir="/usr/lib/${arch}"

  if [ -f "/usr/include/med.h" ] && [ -e "${libdir}/libmedC.so" ]; then
    echo "/usr"
    return 0
  fi

  echo "[DEBUG] MED probe failed:" >&2
  echo "[DEBUG]   arch=${arch}" >&2
  echo "[DEBUG]   /usr/include/med.h: $(test -f /usr/include/med.h && echo yes || echo no)" >&2
  echo "[DEBUG]   ${libdir}/libmedC.so: $(test -e "${libdir}/libmedC.so" && echo yes || echo no)" >&2
  echo ""
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

# TELEMAC v9.1.x build directory name (under <HOMETEL>/builds). build_telemac.py
# (the CMake wrapper) and config.py are both pointed here via BUILD_DIR.
BUILD_CFG_NAME="hyinfompideb12"

# Set by setup_med_root(); consumed by run_compile() to toggle the 'med'
# dependency for build_telemac.py.
MED_ENABLED=0

setup_med_root() {
  # TELEMAC v9.1.x builds with CMake. Its FindMED.cmake locates MED through the
  # MED_ROOT prefix (CMake CMP0074) and FATAL-ERRORs unless med.h, med.hf AND
  # med_parameter.hf live in the same include directory. In addition, the HERMES
  # source utils_med.F90 does `INCLUDE 'med.hf90'` (the free-form Fortran
  # interface). Debian's libmed-dev ships med.h + med.hf but OMITS both
  # med_parameter.hf and med.hf90 (a packaging gap), so a plain MED_ROOT=/usr
  # fails to configure and the hermes module fails to compile.
  #
  # We therefore assemble a private MED prefix under <HOMETEL>/configs/med_root
  # that points back at the SYSTEM MED (symlinked headers + libmed) and adds the
  # missing Fortran includes (med_parameter.hf, med.hf90) borrowed from a local
  # SALOME install. These are interface/constant declarations, and SALOME's MED
  # is API-compatible with the system MED for the subset TELEMAC uses; the
  # system med.h is kept so FindMED reports the real version and CMake links the
  # system libmed (which NEEDs the system HDF5, pulled in transitively).
  local HOMETEL="$1"
  MED_ENABLED=0

  local SYSTEM_MED_ROOT
  SYSTEM_MED_ROOT="$(detect_system_med_root)"
  if [ -z "$SYSTEM_MED_ROOT" ]; then
    warn "System MED not found; TELEMAC will be built WITHOUT MED support."
    warn "Install it with: sudo apt-get install libmedc-dev libmed-dev libmedimport-dev libmed-tools"
    return 0
  fi

  local arch
  arch="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || gcc -dumpmachine 2>/dev/null || echo x86_64-linux-gnu)"
  local libdir="/usr/lib/${arch}"

  local med_root="${HOMETEL}/configs/med_root"
  local med_inc="${med_root}/include"
  local med_lib="${med_root}/lib"

  log "Setting up private MED prefix at '${med_root}' (links system MED in /usr)..."
  rm -rf "${med_root}"
  mkdir -p "${med_inc}" "${med_lib}"

  # Symlink the system MED headers (med.h pulls in medfield.h, medparameter.h, ...)
  local got_header=0
  shopt -s nullglob
  local f
  for f in /usr/include/med*.h /usr/include/med*.hf; do
    ln -sf "$f" "${med_inc}/"
    got_header=1
  done
  shopt -u nullglob
  if [ "$got_header" -eq 0 ]; then
    warn "No MED headers found in /usr/include despite libmed present; building WITHOUT MED."
    rm -rf "${med_root}"
    return 0
  fi

  # Provide the Fortran includes that Debian's libmed-dev omits but TELEMAC
  # needs: med_parameter.hf (pulled in by med.hf / med.hf90) and med.hf90 (the
  # free-form interface included by hermes' utils_med.F90). Borrow them from a
  # local SALOME install (cached under configs/med_include for reuse).
  local SALOME_MED_ROOT=""
  local SALOME_MED_INC=""
  local MED_CACHE="${HOMETEL}/configs/med_include"
  local hf
  for hf in med_parameter.hf med.hf90; do
    [ -e "${med_inc}/${hf}" ] && continue
    warn "System MED is missing the Fortran header '${hf}' (packaging gap)."
    local src=""
    if [ -f "${MED_CACHE}/${hf}" ]; then
      src="${MED_CACHE}/${hf}"
    else
      if [ -z "${SALOME_MED_ROOT}" ]; then
        SALOME_MED_ROOT="$(detect_salome_med_root)"
        [ -n "${SALOME_MED_ROOT}" ] && SALOME_MED_INC="${SALOME_MED_ROOT}/include"
      fi
      [ -n "${SALOME_MED_INC}" ] && [ -f "${SALOME_MED_INC}/${hf}" ] && \
        src="${SALOME_MED_INC}/${hf}"
    fi
    if [ -n "$src" ]; then
      mkdir -p "${MED_CACHE}"
      # Cache for future runs (skip if the source already IS the cached copy).
      [ "$src" -ef "${MED_CACHE}/${hf}" ] || cp "$src" "${MED_CACHE}/${hf}"
      cp "$src" "${med_inc}/${hf}"
      log "  Provided ${hf} from '${src}'."
    else
      warn "Could not find ${hf} (system gap, no SALOME copy)."
      warn "MED cannot be built. Options:"
      warn "  1. Install SALOME (--salome-tar ...) and rerun, OR"
      warn "  2. Continue without MED (no .med I/O)."
      rm -rf "${med_root}"
      return 0
    fi
  done

  # Symlink the MED libraries. CMake links 'med'; medC/medimport are provided
  # for completeness and runtime resolution.
  local base
  for base in libmed libmedC libmedimport; do
    [ -e "${libdir}/${base}.so" ] && ln -sf "${libdir}/${base}.so" "${med_lib}/"
  done
  if [ ! -e "${med_lib}/libmed.so" ]; then
    warn "libmed.so not found in ${libdir}; building WITHOUT MED."
    rm -rf "${med_root}"
    return 0
  fi

  MED_ENABLED=1
  log "MED prefix ready (include + lib populated); MED support enabled."
}

create_pysource() {
  local HOMETEL="$1"
  local PYSOURCE_PATH="${HOMETEL}/configs/pysource.debian12.sh"

  log "Creating TELEMAC environment script '${PYSOURCE_PATH}'..."
  mkdir -p "${HOMETEL}/configs"

  cat > "$PYSOURCE_PATH" <<'EOF'
#!/usr/bin/env bash
# TELEMAC v9.1.x environment for Debian 12
# OpenMPI + HDF5 + system MED + METIS + MUMPS/ScaLAPACK.
#
# v9.1 builds with CMake (build_telemac.py), not the legacy systel.cfg +
# compile_telemac.py flow. The build and runtime are tied together by BUILD_DIR;
# the runtime config (config.py / telemac2d.py ...) reads the systel.cfg that
# CMake generates inside BUILD_DIR. MED is located by CMake through MED_ROOT.
#
# MED note: TELEMAC links the SYSTEM MED (via the MED_ROOT prefix below, which
# points back at /usr). If SALOME is installed, its bundled MED has a different
# ABI and MUST NOT be on LD_LIBRARY_PATH at runtime, or you get
# HERMES_WRONG_MED_FORMAT_ERR. This script strips SALOME MED/HDF5 from the path.

_THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMETEL="$(cd "${_THIS_DIR}/.." && pwd)"
export SOURCEFILE="${_THIS_DIR}"

# CMake build settings used by build_telemac.py and config.py.
export BUILD_TYPE="Release"
export BUILD_DIR="${HOMETEL}/builds/hyinfompideb12"

: "${LD_LIBRARY_PATH:=}"
: "${CPATH:=}"
: "${PYTHONPATH:=}"

# TELEMAC helper scripts and built executables on PATH
for _d in "${HOMETEL}/scripts/python3" "${HOMETEL}/scripts/unix" "${BUILD_DIR}/bin"; do
  if [ -d "${_d}" ]; then
    case ":${PATH}:" in
      *:"${_d}":*) ;;
      *) export PATH="${_d}:${PATH}";;
    esac
  fi
done

_arch="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || gcc -dumpmachine 2>/dev/null || echo x86_64-linux-gnu)"
_archlib="/usr/lib/${_arch}"

_first_dir() { for _d in "$@"; do [ -d "$_d" ] && { printf '%s' "$_d"; return 0; }; done; return 1; }

# Compilers / MPI. CMake's find_package(MPI) handles MPI include/link via the
# system gfortran toolchain, so the Fortran compiler stays gfortran.
export MPI_ROOT="/usr"
export MPIRUN="mpirun"
_MPI_BIN="$(dirname "$(command -v mpif90 2>/dev/null || command -v mpifort 2>/dev/null || command -v mpicc 2>/dev/null || echo /usr/bin/mpif90)")"
_MPI_INC="$(_first_dir "${_archlib}/openmpi/include" "/usr/include/openmpi" "/usr/include/mpi")"
_MPI_LIB="$(_first_dir "${_archlib}/openmpi/lib" "${_archlib}" "/usr/lib")"

# HDF5 (pulled in transitively by libmed; these are runtime hints only)
_HDF5_INC="$(_first_dir "/usr/include/hdf5/openmpi" "/usr/include/hdf5/serial")"
_HDF5_LIB="$(_first_dir "${_archlib}/hdf5/openmpi" "${_archlib}/hdf5/serial" "${_archlib}")"

# MED: point CMake (FindMED.cmake, CMP0074) at the private MED prefix that the
# installer assembled (system MED headers + libmed + the missing
# med_parameter.hf / med.hf90). Only set it if that prefix exists.
if [ -d "${HOMETEL}/configs/med_root/include" ]; then
  export MED_ROOT="${HOMETEL}/configs/med_root"
fi
_MED_LIB=""
if [ -e "${_archlib}/libmedC.so" ] || ls "${_archlib}/libmedC.so"* >/dev/null 2>&1; then
  _MED_LIB="${_archlib}"
fi

# METIS / MUMPS / ScaLAPACK (system)
export METIS_ROOT="/usr"; export MUMPS_ROOT="/usr"
_METIS_LIB="$(_first_dir "${_archlib}")"
_MUMPS_LIB="$(_first_dir "${_archlib}")"
_SCALAPACK_LIB="$(_first_dir "${_archlib}")"

# LD_LIBRARY_PATH: built TELEMAC shared libs first, then MED prefix, then system.
for _libdir in "${BUILD_DIR}/lib" "${MED_ROOT:+${MED_ROOT}/lib}" "${_MPI_LIB}" "${_HDF5_LIB}" "${_SCALAPACK_LIB}" "${_MUMPS_LIB}" "${_METIS_LIB}" "${_MED_LIB}" "${_archlib}"; do
  [ -n "${_libdir}" ] || continue
  case ":${LD_LIBRARY_PATH}:" in
    *:"${_libdir}":*) ;;
    *) export LD_LIBRARY_PATH="${_libdir}:${LD_LIBRARY_PATH}";;
  esac
done

# Detect a SALOME install and SCRUB its MED/HDF5 from LD_LIBRARY_PATH to avoid
# ABI clashes with the system MED that TELEMAC was compiled against.
_ROOT_DIR="$(cd "${HOMETEL}/.." && pwd)"
for _salome_search in "${_ROOT_DIR}/salome" "$HOME/opt/salome"; do
  [ -d "${_salome_search}" ] || continue
  _salome_med="$(find "${_salome_search}" -maxdepth 6 -type d -name medfile 2>/dev/null | head -n 1)"
  if [ -n "${_salome_med}" ]; then
    _remove_prefixes=("${_salome_med}/lib")
    _salome_hdf5="$(dirname "${_salome_med}")/hdf5/lib"
    [ -d "${_salome_hdf5}" ] && _remove_prefixes+=("${_salome_hdf5}")

    _new=""
    _IFS_old="$IFS"; IFS=':'
    for _p in $LD_LIBRARY_PATH; do
      _skip=0
      for _bad in "${_remove_prefixes[@]}"; do
        case "${_p}" in "${_bad}"|"${_bad}/"*) _skip=1; break;; esac
      done
      [ "${_skip}" -eq 1 ] && continue
      [ -z "${_new}" ] && _new="${_p}" || _new="${_new}:${_p}"
    done
    IFS="${_IFS_old}"
    export LD_LIBRARY_PATH="${_new}"
    echo "[WARN] SALOME at '${_salome_search}': removed its MED/HDF5 from LD_LIBRARY_PATH (using system MED)."
  fi
  break
done

# CPATH
for _incdir in "${_MPI_INC}" "${_HDF5_INC}" "${MED_ROOT:+${MED_ROOT}/include}"; do
  [ -n "${_incdir}" ] || continue
  case ":${CPATH}:" in
    *:"${_incdir}":*) ;;
    *) export CPATH="${_incdir}:${CPATH}";;
  esac
done

# Python: TELEMAC scripts + the compiled extensions (TelApy '_api', '_hermes')
# that CMake places in BUILD_DIR/lib.
for _pydir in "${HOMETEL}/scripts/python3" "${BUILD_DIR}/lib"; do
  [ -d "${_pydir}" ] || continue
  case ":${PYTHONPATH}:" in
    *:"${_pydir}":*) ;;
    *) export PYTHONPATH="${_pydir}:${PYTHONPATH}";;
  esac
done

echo "TELEMAC set: HOMETEL='${HOMETEL}', BUILD_DIR='${BUILD_DIR}', BUILD_TYPE='${BUILD_TYPE}'"
echo "HDF5 inc='${_HDF5_INC}', HDF5 lib='${_HDF5_LIB}'"
[ -n "${MED_ROOT:-}" ] && echo "MED_ROOT='${MED_ROOT}' (system MED via private prefix)"

export PYTHONUNBUFFERED="1"
EOF

  chmod +x "$PYSOURCE_PATH"
}

verify_telemac_build() {
  # Verify that key TELEMAC executables were built successfully
  local HOMETEL="$1"
  local BUILD_BIN="${HOMETEL}/builds/${BUILD_CFG_NAME}/bin"
  local BUILD_LIB="${HOMETEL}/builds/${BUILD_CFG_NAME}/lib"

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

  # In v9.1.x several former modules (gaia, waqtel, khione, nestor, ...) are
  # built as libraries linked into the solvers, not standalone executables.
  local missing_exes=()
  local required_exes=("stbtel" "telemac2d" "telemac3d" "tomawac" "artemis" "postel3d" "partel" "gretel")

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
    warn "To debug, run manually:"
    warn "  source ${HOMETEL}/configs/pysource.debian12.sh"
    warn "  build_telemac.py --rebuild --deps mpi mumps med -j \"$(nproc)\""
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

  log "Building TELEMAC v9.1.x with CMake (direct configure/build, forced system Python)..."

  # Avoid MPI/X11 authorization issues.
  unset DISPLAY

  local jobs
  jobs="$(nproc 2>/dev/null || echo 4)"

  local compile_status=0

  (
    set -euo pipefail
    cd "$HOMETEL"
    source "$HOMETEL/configs/pysource.debian12.sh"

    # Force Debian's system Python and avoid SALOME/conda/pyenv Python leakage.
    unset PYTHONHOME CONDA_PREFIX CONDA_DEFAULT_ENV VIRTUAL_ENV MAMBA_ROOT_PREFIX
    export Python_ROOT_DIR="/usr"
    export Python_EXECUTABLE="/usr/bin/python3"

    local pyexe="/usr/bin/python3"
    local numpy_inc
    local python_inc
    local med_bool="OFF"
    local med_root="${MED_ROOT:-$HOMETEL/configs/med_root}"

    [ "$MED_ENABLED" -eq 1 ] && med_bool="ON"

    numpy_inc="$($pyexe -c 'import numpy; print(numpy.get_include())')"
    python_inc="$($pyexe -c 'import sysconfig; print(sysconfig.get_path("include"))')"

    echo "[*] Python executable: $pyexe"
    echo "[*] Python include:    $python_inc"
    echo "[*] NumPy include:     $numpy_inc"
    echo "[*] MED enabled:       $med_bool"

    rm -rf "$BUILD_DIR"

    cmake -S "$HOMETEL" -B "$BUILD_DIR" \
      -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
      -G "Unix Makefiles" \
      -DUSE_MED:BOOL="$med_bool" \
      -DUSE_MPI:BOOL=ON \
      -DUSE_MUMPS:BOOL=ON \
      -DUSE_AED2:BOOL=OFF \
      -DUSE_GOTM:BOOL=OFF \
      -DBUILD_TELAPY:BOOL=ON \
      -DBUILD_HERMES_WRAPPER:BOOL=ON \
      -DMETIS_ROOT=/usr \
      -DMUMPS_ROOT=/usr \
      -DMPI_ROOT=/usr \
      -DMED_ROOT="$med_root" \
      -DPython_EXECUTABLE="$pyexe" \
      -DPython_ROOT_DIR=/usr \
      -DPython_FIND_STRATEGY=LOCATION \
      -DPython_FIND_VIRTUALENV=STANDARD \
      -DPython_INCLUDE_DIR="$python_inc" \
      -DPython_NumPy_INCLUDE_DIR="$numpy_inc"

    cmake --build "$BUILD_DIR" --parallel "$jobs"

    echo '[*] Displaying configuration (config.py) ...'
    config.py || true
  ) 2>&1 | tee "$HOMETEL/build_telemac_debian12.log" || compile_status=${PIPESTATUS[0]}

  if [ "$compile_status" -ne 0 ]; then
    die "TELEMAC compilation failed with exit code $compile_status. See $HOMETEL/build_telemac_debian12.log."
  fi

  log "TELEMAC build command completed. Full log: $HOMETEL/build_telemac_debian12.log"

  if ! verify_telemac_build "$HOMETEL"; then
    warn "Build verification found issues. TELEMAC may not work correctly."
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

  # Assemble the private MED prefix (sets MED_ENABLED) BEFORE generating the
  # environment script and building, so build_telemac.py can find MED via
  # MED_ROOT.
  setup_med_root "$HOMETEL"
  create_pysource "$HOMETEL"
  run_compile "$HOMETEL"

  log "Installation finished."
  echo
  echo "To use TELEMAC in a new shell:"
  echo "  cd \"$HOMETEL/configs\""
  echo "  source pysource.debian12.sh"
  echo "  telemac2d.py --help"
  echo
  if [ "$MED_ENABLED" -eq 1 ]; then
    echo "MED support: enabled (system MED in /usr via the configs/med_root prefix;"
    echo "             SALOME-bundled MED is not used)."
  else
    echo "MED support: NOT enabled. Install MED (and, if needed, SALOME for the"
    echo "             missing med_parameter.hf / med.hf90 headers) and rebuild:"
    echo "  sudo apt-get install libmedc-dev libmed-dev libmedimport-dev libmed-tools"
    echo "  ./telemac_debian12_installer.sh --skip-apt   # re-runs setup + build"
  fi
}

main "$@"

