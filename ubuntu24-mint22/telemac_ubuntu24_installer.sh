#!/usr/bin/env bash
# TELEMAC-MASCARET (+ optional SALOME) installer for Linux Mint 22 / Ubuntu 24.04 (noble)
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
#   1. TELEMAC and dependencies (default tag: v9.1.1)
#   2. (Optionally) SALOME into ROOT_DIR/salome, used for the GUI / mesh tools
#
# MED files (SALOME compatibility):
#   TELEMAC is compiled against the *system* MED libraries (Ubuntu/Mint packages
#   libmedc-dev / libmed-dev / libmedimport-dev), NOT against the MED libraries
#   bundled inside SALOME. SALOME ships its own MED built with a different ABI
#   (64-bit med_int, serial-vs-openmpi HDF5), and mixing it with TELEMAC causes
#   "size of symbol 'med_' changed" link warnings and the runtime error
#   HERMES_WRONG_MED_FORMAT_ERR when reading/writing .med files.
#
#   The only missing piece in Ubuntu's libmed-dev is the Fortran header
#   med_parameter.hf (a packaging gap). If absent, it is copied from a local
#   SALOME install (constants only, ABI-neutral).
#
# Usage examples:
#   chmod +x telemac_ubuntu24_installer.sh
#   ./telemac_ubuntu24_installer.sh
#   ./telemac_ubuntu24_installer.sh --root "$HOME/opt" --tag v9.1.1
#   ./telemac_ubuntu24_installer.sh --salome-tar ~/Downloads/SALOME-9.15.0.tar.gz
#   ./telemac_ubuntu24_installer.sh --salome-tar SALOME-9.15.0.tar.gz --salome-md5 SALOME-9.15.0.tar.gz.md5
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

detect_mime() {
  # Best-effort MIME type for a local file (requires 'file').
  local f="$1"
  if ! command -v file >/dev/null 2>&1; then
    echo ""
    return 0
  fi
  file -b --mime-type "$f" 2>/dev/null || echo ""
}

extract_md5_hash() {
  # Extract the first 32-hex MD5 hash from an md5 file.
  #   <hash>  <filename>   OR   MD5 (<filename>) = <hash>
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
      gzip -t "$archive" >/dev/null 2>&1 || die "SALOME archive '$archive' fails 'gzip -t' (corrupt/truncated). Re-download and verify md5sum."
      ;;
    application/x-xz)
      command -v xz >/dev/null 2>&1 || die "xz not found (install 'xz-utils')."
      xz -t "$archive" >/dev/null 2>&1 || die "SALOME archive '$archive' fails 'xz -t' (corrupt/truncated). Re-download and verify md5sum."
      ;;
    application/x-bzip2)
      command -v bzip2 >/dev/null 2>&1 || die "bzip2 not found (install 'bzip2')."
      bzip2 -t "$archive" >/dev/null 2>&1 || die "SALOME archive '$archive' fails 'bzip2 -t' (corrupt/truncated). Re-download and verify md5sum."
      ;;
    application/zip)
      command -v unzip >/dev/null 2>&1 || die "unzip not found (install 'unzip')."
      unzip -tq "$archive" >/dev/null 2>&1 || die "SALOME archive '$archive' fails 'unzip -t' (corrupt/truncated). Re-download and verify md5sum."
      ;;
    application/x-tar|application/octet-stream|"" )
      : # tar / unknown: extraction step validates further.
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
        local tmp
        tmp="$(mktemp -d)"
        unzip -q "$archive" -d "$tmp" || die "Failed to unzip '$archive' (corrupt/truncated)."
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
    *)             die "Unknown SALOME archive format for '$archive'." ;;
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

MED support:
  TELEMAC links the *system* MED packages (libmedc-dev/libmed-dev/libmedimport-dev),
  which are installed automatically. SALOME is only needed for the GUI / mesh tools;
  its bundled MED is deliberately NOT used (incompatible ABI).
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
        shift; [ "$#" -gt 0 ] || die "--root requires a path argument"; ROOT_DIR="$1" ;;
      --tag)
        shift; [ "$#" -gt 0 ] || die "--tag requires a tag or branch name"; TELEMAC_TAG="$1" ;;
      --repo)
        shift; [ "$#" -gt 0 ] || die "--repo requires a URL"; TELEMAC_REPO="$1" ;;
      --salome-tar)
        shift; [ "$#" -gt 0 ] || die "--salome-tar requires a path to the SALOME tarball"; SALOME_TAR="$1" ;;
      --salome-archive)
        shift; [ "$#" -gt 0 ] || die "--salome-archive requires a path to the SALOME tarball"; SALOME_TAR="$1" ;;
      --salome-md5)
        shift; [ "$#" -gt 0 ] || die "--salome-md5 requires a path to the SALOME .md5 file"; SALOME_MD5="$1" ;;
      --skip-apt)     SKIP_APT=1 ;;
      --skip-compile) SKIP_COMPILE=1 ;;
      --verbose)      VERBOSE=1 ;;
      -h|--help)      usage; exit 0 ;;
      *)              die "Unknown argument: $1" ;;
    esac
    shift
  done
}

apt_install_deps_telemac() {
  if [ "$SKIP_APT" -eq 1 ]; then
    log "Skipping TELEMAC apt dependency installation (per --skip-apt)."
    return
  fi

  command -v sudo >/dev/null 2>&1 || die "'sudo' not found; install sudo or install dependencies manually."

  log "Installing TELEMAC build dependencies via apt (requires sudo)..."
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    git git-lfs \
    build-essential gfortran g++ make m4 \
    python3 python3-dev python3-venv python3-pip \
    python3-numpy python3-scipy python3-matplotlib python3-mpi4py python3-h5py \
    cmake file \
    openmpi-bin libopenmpi-dev \
    libhdf5-openmpi-dev \
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

  command -v sudo >/dev/null 2>&1 || die "'sudo' not found; install SALOME dependencies manually."

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

  [ -f "$SALOME_TAR" ] || die "SALOME tarball '$SALOME_TAR' not found."

  # Auto-detect md5 file if the user didn't provide one.
  if [ -z "$SALOME_MD5" ] && [ -f "${SALOME_TAR}.md5" ]; then
    SALOME_MD5="${SALOME_TAR}.md5"
    log "Auto-detected SALOME md5 file: '$SALOME_MD5'"
  fi

  if [ -n "$SALOME_MD5" ]; then
    [ -f "$SALOME_MD5" ] || die "SALOME md5 file '$SALOME_MD5' not found."
    log "Verifying SALOME tarball MD5 against '$SALOME_MD5'..."
    local expected got
    expected="$(extract_md5_hash "$SALOME_MD5")"
    [ -n "$expected" ] || die "Could not parse an MD5 hash from '$SALOME_MD5'."
    got="$(md5sum "$SALOME_TAR" | awk '{print $1}')"
    [ "$expected" = "$got" ] || die "SALOME MD5 mismatch: expected $expected, got $got"
    log "SALOME tarball MD5 check passed."
  else
    warn "No --salome-md5 provided; SALOME tarball integrity not verified."
  fi

  validate_archive_or_die "$SALOME_TAR"

  apt_install_deps_salome

  local SALOME_ROOT="${ROOT_DIR}/salome"
  log "Installing SALOME tarball '$SALOME_TAR' into '$SALOME_ROOT'..."
  mkdir -p "$SALOME_ROOT"

  extract_archive_to_dir_or_die "$SALOME_TAR" "$SALOME_ROOT"

  chown -R "$USER":"$(id -gn "$USER")" "$SALOME_ROOT" || \
    warn "Failed to chown SALOME install; check permissions on '$SALOME_ROOT'."

  log "SALOME extraction completed in '$SALOME_ROOT'."

  local SALOME_SAT_DIR="${SALOME_ROOT}/sat"
  if [ -d "$SALOME_SAT_DIR" ]; then
    log "Recommended SALOME system check (run manually):"
    echo "  cd \"$SALOME_SAT_DIR\""
    echo "  ./sat config --list"
    echo "  ./sat config <APPNAME> --check_system"
  else
    warn "SALOME 'sat' directory not found at '$SALOME_SAT_DIR'; layout may differ."
  fi
}

multiarch_libdir() {
  local arch
  arch="$(gcc -dumpmachine 2>/dev/null || echo x86_64-linux-gnu)"
  echo "/usr/lib/${arch}"
}

detect_system_med_root() {
  # System MED (Ubuntu/Mint packages) is the ONLY MED we link against, to keep
  # the ABI consistent. Returns "/usr" if libmedC + headers are found, else "".
  local libdir
  libdir="$(multiarch_libdir)"
  if [ -e "/usr/include/med.h" ] && { ls "${libdir}/libmedC.so"* >/dev/null 2>&1 || ldconfig -p 2>/dev/null | grep -q "libmedC.so"; }; then
    echo "/usr"
    return 0
  fi
  echo ""
}

detect_salome_med_include() {
  # Locate a SALOME MED include dir (used only to borrow the missing Fortran
  # header med_parameter.hf; never linked against).
  local search_roots=()
  [ -n "${SALOME_DIR:-}" ] && [ -d "${SALOME_DIR}" ] && search_roots+=("${SALOME_DIR}")
  [ -d "${ROOT_DIR}/salome" ] && search_roots+=("${ROOT_DIR}/salome")
  [ -d "$HOME/opt/salome" ] && search_roots+=("$HOME/opt/salome")

  local d
  for base in "${search_roots[@]}"; do
    while IFS= read -r d; do
      if [ -f "${d}/include/med_parameter.hf" ]; then
        echo "${d}/include"
        return 0
      fi
    done < <(find "${base}" -maxdepth 6 -type d -name medfile 2>/dev/null)
  done
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
    log "Checking out TELEMAC tag or branch '${TELEMAC_TAG}'..."
    git fetch --tags
    if git rev-parse --verify --quiet "${TELEMAC_TAG}^{commit}" >/dev/null; then
      git checkout "${TELEMAC_TAG}"
    else
      warn "Tag or branch '${TELEMAC_TAG}' not found; staying on current branch."
    fi
  fi
}

# TELEMAC v9.1.x build directory name (under <HOMETEL>/builds). The CMake build
# system (build_telemac.py) and the runtime config (config.py) are both pointed
# at this directory via the BUILD_DIR environment variable set by pysource.
BUILD_CFG_NAME="hyinfompiubu"

# Set by setup_med_root(); consumed by run_compile() to toggle the 'med'
# dependency for build_telemac.py.
MED_ENABLED=0

setup_med_root() {
  # TELEMAC v9.1.x builds with CMake. Its FindMED.cmake locates MED through the
  # MED_ROOT prefix (CMake CMP0074) and FATAL-ERRORs unless med.h, med.hf AND
  # med_parameter.hf live in the same include directory. In addition, the HERMES
  # source utils_med.F90 does `INCLUDE 'med.hf90'` (the free-form Fortran
  # interface). Ubuntu/Mint's libmed-dev ships med.h + med.hf but OMITS both
  # med_parameter.hf and med.hf90 (a packaging gap), so a plain MED_ROOT=/usr
  # fails to configure and the hermes module fails to compile.
  #
  # We therefore assemble a private MED prefix under <HOMETEL>/configs/med_root
  # that points back at the SYSTEM MED (symlinked headers + libmed) and adds the
  # missing Fortran includes (med_parameter.hf, med.hf90) borrowed from a local
  # SALOME install. These are interface/constant declarations, and SALOME's MED
  # (4.2) is API-compatible with the system MED (4.1) for the subset TELEMAC
  # uses; the system med.h is kept so FindMED reports the real 4.1 version and
  # CMake links the system libmed (which NEEDs libhdf5_openmpi, so the OpenMPI
  # HDF5 build is pulled in transitively, with no serial-vs-openmpi ABI clash).
  local HOMETEL="$1"
  MED_ENABLED=0

  local SYSTEM_MED_ROOT
  SYSTEM_MED_ROOT="$(detect_system_med_root)"
  if [ -z "$SYSTEM_MED_ROOT" ]; then
    warn "System MED not found; TELEMAC will be built WITHOUT MED support."
    warn "Install it with: sudo apt-get install libmedc-dev libmed-dev libmedimport-dev libmed-tools"
    return 0
  fi

  local libdir
  libdir="$(multiarch_libdir)"

  local med_root="${HOMETEL}/configs/med_root"
  local med_inc="${med_root}/include"
  local med_lib="${med_root}/lib"

  log "Setting up private MED prefix at '${med_root}' (links system MED in /usr)..."
  rm -rf "${med_root}"
  mkdir -p "${med_inc}" "${med_lib}"

  # Symlink the system MED headers (med.h pulls in medfield.h, medparameter.h, …)
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

  # Provide the Fortran includes that Ubuntu's libmed-dev omits but TELEMAC
  # needs: med_parameter.hf (pulled in by med.hf / med.hf90) and med.hf90 (the
  # free-form interface included by hermes' utils_med.F90). Borrow them from a
  # local SALOME install (cached under configs/med_include for reuse).
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
      [ -n "${SALOME_MED_INC}" ] || SALOME_MED_INC="$(detect_salome_med_include)"
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
  local PYSOURCE_PATH="${HOMETEL}/configs/pysource.mint22.sh"

  log "Creating TELEMAC environment script '${PYSOURCE_PATH}'..."
  mkdir -p "${HOMETEL}/configs"

  cat > "$PYSOURCE_PATH" <<'EOF'
#!/usr/bin/env bash
# TELEMAC v9.1.x environment for Linux Mint 22 / Ubuntu 24.04 (noble)
# OpenMPI + HDF5(openmpi) + system MED + METIS + MUMPS/ScaLAPACK.
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
export BUILD_DIR="${HOMETEL}/builds/hyinfompiubu"

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

_arch="$(gcc -dumpmachine 2>/dev/null || echo x86_64-linux-gnu)"
_archlib="/usr/lib/${_arch}"

_first_dir() { for _d in "$@"; do [ -d "$_d" ] && { printf '%s' "$_d"; return 0; }; done; return 1; }

# Compilers / MPI. CMake's find_package(MPI) handles MPI include/link via the
# system gfortran toolchain, so the Fortran compiler stays gfortran.
export MPI_ROOT="/usr"
export MPIRUN="mpirun"
_MPI_INC="$(_first_dir "${_archlib}/openmpi/include" "/usr/include/openmpi")"
_MPI_LIB="$(_first_dir "${_archlib}/openmpi/lib" "${_archlib}")"

# HDF5 (openmpi build, to match the system MED's HDF5 dependency)
_HDF5_INC="$(_first_dir "/usr/include/hdf5/openmpi" "/usr/include/hdf5/serial")"
_HDF5_LIB="$(_first_dir "${_archlib}/hdf5/openmpi" "${_archlib}/hdf5/serial" "${_archlib}")"

# MED: point CMake (FindMED.cmake, CMP0074) at the private MED prefix that the
# installer assembled (system MED headers + libmed + the missing
# med_parameter.hf). Only set it if that prefix exists.
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
    # SALOME's bundled HDF5 (if any) lives next to medfile.
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
  local HOMETEL="$1"
  local BUILD_BIN="${HOMETEL}/builds/${BUILD_CFG_NAME}/bin"

  log "Verifying TELEMAC build artifacts..."
  if [ ! -d "${BUILD_BIN}" ]; then
    warn "Build bin directory not found: ${BUILD_BIN} (compilation likely failed)."
    return 1
  fi

  # In v9.1.x several former modules (gaia, waqtel, khione, nestor, ...) are
  # built as libraries linked into the solvers, not standalone executables.
  local missing_exes=()
  local required_exes=("stbtel" "telemac2d" "telemac3d" "tomawac" "artemis" "postel3d" "partel" "gretel")
  for exe in "${required_exes[@]}"; do
    [ -f "${BUILD_BIN}/${exe}" ] || missing_exes+=("$exe")
  done

  if [ ${#missing_exes[@]} -gt 0 ]; then
    warn "Missing executables in ${BUILD_BIN}: ${missing_exes[*]}"
    warn "Re-run, or: source configs/pysource.mint22.sh && build_telemac.py --rebuild"
    return 1
  fi

  log "Build verification passed; all required executables present in ${BUILD_BIN}."
  return 0
}

run_compile() {
  local HOMETEL="$1"

  if [ "$SKIP_COMPILE" -eq 1 ]; then
    log "Skipping TELEMAC compilation (per --skip-compile)."
    return
  fi

  log "Building TELEMAC v9.1.x with CMake via build_telemac.py (10-30 min)..."

  # Avoid MPI/X11 authorization issues during compilation.
  unset DISPLAY

  # Dependencies enabled for the CMake build. METIS is implicit with MPI.
  # AED2 and GOTM are left off (not installed system-wide; they are REQUIRED by
  # CMake when enabled and would abort configuration).
  local deps="mpi mumps"
  [ "$MED_ENABLED" -eq 1 ] && deps="${deps} med"

  local jobs
  jobs="$(nproc 2>/dev/null || echo 4)"

  local compile_status=0
  bash -lc "
    set -euo pipefail
    cd \"$HOMETEL\"
    source \"$HOMETEL/configs/pysource.mint22.sh\"
    echo '[*] Running build_telemac.py --rebuild --deps ${deps} -j ${jobs} ...'
    build_telemac.py --rebuild --deps ${deps} -j ${jobs}
    echo '[*] Displaying configuration (config.py) ...'
    config.py || true
  " || compile_status=$?

  [ "$compile_status" -eq 0 ] || die "TELEMAC compilation failed (exit $compile_status). See errors above."

  log "TELEMAC build command completed."
  if ! verify_telemac_build "$HOMETEL"; then
    warn "Build verification found issues; TELEMAC may not work correctly."
  else
    log "TELEMAC compilation completed successfully."
  fi
}

main() {
  [ "$(id -u)" -ne 0 ] || die "Do not run this script as root. Use a normal user with sudo."

  parse_args "$@"

  log "Installation root:     $ROOT_DIR"
  log "TELEMAC repository:    $TELEMAC_REPO"
  log "TELEMAC tag/branch:    $TELEMAC_TAG"
  if [ -n "$SALOME_TAR" ]; then
    log "SALOME tarball:        $SALOME_TAR"
    [ -n "$SALOME_MD5" ] && log "SALOME md5 file:       $SALOME_MD5"
  else
    log "SALOME tarball:        not specified (SALOME optional; system MED is used for .med I/O)."
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
  echo "  source pysource.mint22.sh"
  echo "  telemac2d.py --help"
  echo
  if [ "$MED_ENABLED" -eq 1 ]; then
    echo "MED support: enabled (system MED in /usr via the configs/med_root prefix;"
    echo "             SALOME-bundled MED is not used)."
  else
    echo "MED support: NOT enabled. Install MED (and, if needed, SALOME for the"
    echo "             missing med_parameter.hf header) and rebuild:"
    echo "  sudo apt-get install libmedc-dev libmed-dev libmedimport-dev libmed-tools"
    echo "  ./telemac_ubuntu24_installer.sh --skip-apt   # re-runs setup + build"
  fi
}

main "$@"
