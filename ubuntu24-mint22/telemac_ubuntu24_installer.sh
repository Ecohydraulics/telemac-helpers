#!/usr/bin/env bash
# TELEMAC-MASCARET (+ optional SALOME) installer for Linux Mint 22 / Ubuntu 24.04 (noble)
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
  --skip-compile         Do not run compile_telemac.py
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

detect_med_int_macro() {
  # Pick the right HERMES preprocessor flag for the *system* MED integer width.
  #   32-bit med_int (Ubuntu/Mint default) -> HAVE_MED
  #   64-bit med_int                       -> HAVE_MED HAVE_MED64
  # Determined from the C typedef in /usr/include/med.h.
  if grep -qE 'typedef[[:space:]]+(long|long long|med_int64|int64_t)[[:space:]]+med_int[[:space:]]*;' /usr/include/med.h 2>/dev/null; then
    echo "-DHAVE_MED -DHAVE_MED64"
  else
    echo "-DHAVE_MED"
  fi
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

create_cfg() {
  local HOMETEL="$1"
  local CFG_PATH="${HOMETEL}/configs/systel.mint22.cfg"

  log "Creating TELEMAC configuration '${CFG_PATH}'..."
  mkdir -p "${HOMETEL}/configs"

  local SYSTEM_MED_ROOT
  SYSTEM_MED_ROOT="$(detect_system_med_root)"

  local SYS_MED_LIB
  SYS_MED_LIB="$(multiarch_libdir)"

  local MED_ENABLED=0
  local MED_INC_BLOCK=""
  local MED_LIB_BLOCK=""
  local MED_INCS_ALL=""
  local MED_LIBS_ALL=""
  local MED_OPTIONS=""
  local MED_FFLAGS=""
  local MED_CFLAGS=""

  if [ -n "$SYSTEM_MED_ROOT" ]; then
    log "Using system MED libraries in /usr (libdir: ${SYS_MED_LIB}); enabling MED support."

    local MEDIMPORT_FLAG=""
    if ls "${SYS_MED_LIB}/libmedimport.so"* >/dev/null 2>&1; then
      MEDIMPORT_FLAG=" -lmedimport"
    fi

    # Ubuntu's libmed-dev ships med.hf but NOT med_parameter.hf (packaging gap).
    # med.hf does `include "med_parameter.hf"`, so without it the HERMES MED
    # sources will not preprocess. med_parameter.hf is constants only (no ABI),
    # so borrowing it from a local SALOME install is safe.
    local MED_INC_DIR="/usr/include"
    if [ ! -f "/usr/include/med_parameter.hf" ]; then
      warn "System MED package is missing the Fortran header 'med_parameter.hf'."
      local SALOME_MED_INC
      SALOME_MED_INC="$(detect_salome_med_include)"
      if [ -n "$SALOME_MED_INC" ]; then
        local MED_PATCH_DIR="${HOMETEL}/configs/med_include"
        mkdir -p "$MED_PATCH_DIR"
        log "Borrowing missing MED Fortran header from SALOME ('$SALOME_MED_INC')..."
        for hf in med_parameter.hf; do
          if [ -f "${SALOME_MED_INC}/${hf}" ]; then
            cp "${SALOME_MED_INC}/${hf}" "$MED_PATCH_DIR/"
            log "  Copied ${hf} -> ${MED_PATCH_DIR}"
          fi
        done
        # Patched dir first so its med_parameter.hf is found; system /usr/include
        # still provides med.hf and the C headers.
        MED_INC_DIR="${MED_PATCH_DIR} -I /usr/include"
      else
        warn "Could not find med_parameter.hf in any SALOME install."
        warn "MED Fortran support will likely fail to compile. Options:"
        warn "  1. Install SALOME (--salome-tar ...) and rerun, OR"
        warn "  2. Drop 'med' from the 'options:' line in ${CFG_PATH}."
      fi
    fi

    MED_INC_BLOCK="inc_med:       -I ${MED_INC_DIR}"
    MED_LIB_BLOCK="libs_med:      -L ${SYS_MED_LIB} -lmedC -lmed${MEDIMPORT_FLAG}"
    MED_INCS_ALL="[inc_med] "
    MED_LIBS_ALL="[libs_med] "
    MED_OPTIONS=" med"
    MED_FFLAGS=" $(detect_med_int_macro)"
    MED_CFLAGS=" $(detect_med_int_macro)"
    MED_ENABLED=1
    log "MED preprocessor flags:${MED_FFLAGS}"
  else
    warn "System MED not found; cfg will be generated WITHOUT MED support."
    warn "Install it with: sudo apt-get install libmedc-dev libmed-dev libmedimport-dev libmed-tools"
  fi

  cat > "$CFG_PATH" <<EOF
# _____                              _______________________________
# ____/ TELEMAC Project Definitions /______________________________/
#
[Configurations]
configs: hyinfompiubu
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

# HDF5 (OpenMPI build via libhdf5-openmpi-dev).
# IMPORTANT: the Ubuntu/Mint system MED (libmedC) links libhdf5_openmpi, so
# TELEMAC must use the SAME (openmpi) HDF5 to avoid loading two HDF5 builds.
inc_hdf5:  -I /usr/include/hdf5/openmpi
libs_hdf5: -L /usr/lib/x86_64-linux-gnu/hdf5/openmpi -lhdf5_fortran -lhdf5hl_fortran -lhdf5_hl -lhdf5

# MED-fichier (system packages, optional)
$MED_INC_BLOCK
$MED_LIB_BLOCK

# METIS
inc_metis:     -I /usr/include
libs_metis:    -L /usr/lib/x86_64-linux-gnu -lmetis

# MUMPS + ScaLAPACK
inc_mumps:     -I /usr/include
libs_mumps:    -L /usr/lib/x86_64-linux-gnu -ldmumps -lmumps_common -lpord -lscalapack-openmpi -lblas -llapack

incs_all: [inc_mpi] [inc_hdf5] ${MED_INCS_ALL}[inc_metis] [inc_mumps]
libs_all: ${MED_LIBS_ALL}[libs_hdf5] [libs_metis] [libs_mumps]
mods_all: -I <config>

[hyinfompiubu]
brief: Linux Mint 22 / Ubuntu 24.04 gfortran + OpenMPI + HDF5 + METIS + MUMPS/ScaLAPACK$( [ "$MED_ENABLED" -eq 1 ] && printf " + MED" || printf "" )
system: linux
mpi:   openmpi
compiler: gfortran
pyd_fcompiler: gnu95
f2py_name: f2py
bin_dir: <root>/builds/hyinfompiubu/bin
lib_dir: <root>/builds/hyinfompiubu/lib
obj_dir: <root>/builds/hyinfompiubu/obj
options: mpi dyn${MED_OPTIONS}
cmd_obj:   [fc] [fflags] -c <mods> <incs> <f95name>
cmd_lib:   ar crs <libname> <objs>
cmd_exe:   [fc] [fflags] -o <exename> <objs> <libs>
mods_all:  -I <config>
incs_all:  [inc_mpi] [inc_hdf5] ${MED_INCS_ALL}[inc_metis] [inc_mumps]
libs_all:  ${MED_LIBS_ALL}[libs_hdf5] [libs_metis] [libs_mumps]
ldflags_opt:   -Wl,-rpath,/usr/lib/x86_64-linux-gnu/hdf5/openmpi
ldflags_debug: -Wl,-rpath,/usr/lib/x86_64-linux-gnu/hdf5/openmpi
EOF
}

create_pysource() {
  local HOMETEL="$1"
  local PYSOURCE_PATH="${HOMETEL}/configs/pysource.mint22.sh"

  log "Creating TELEMAC environment script '${PYSOURCE_PATH}'..."
  mkdir -p "${HOMETEL}/configs"

  cat > "$PYSOURCE_PATH" <<'EOF'
#!/usr/bin/env bash
# TELEMAC environment for Linux Mint 22 / Ubuntu 24.04 (noble)
# OpenMPI + HDF5(openmpi) + system MED + METIS + MUMPS/ScaLAPACK.
#
# MED note: TELEMAC is built against the SYSTEM MED (/usr). If SALOME is
# installed, its bundled MED has a different ABI (64-bit med_int, possibly a
# different HDF5) and MUST NOT be on LD_LIBRARY_PATH at runtime, or you get
# HERMES_WRONG_MED_FORMAT_ERR. This script strips SALOME MED/HDF5 from the
# runtime path defensively.

_THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMETEL="$(cd "${_THIS_DIR}/.." && pwd)"
export SOURCEFILE="${_THIS_DIR}"

export SYSTELCFG="${HOMETEL}/configs/systel.mint22.cfg"
export USETELCFG="hyinfompiubu"

: "${LD_LIBRARY_PATH:=}"
: "${CPATH:=}"
: "${PYTHONPATH:=}"

# TELEMAC helper scripts on PATH
for _d in "${HOMETEL}/scripts/python3" "${HOMETEL}/scripts/unix" "${HOMETEL}/builds/${USETELCFG}/bin"; do
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

# Compilers / MPI
export MPI_ROOT="/usr"
export CC="mpicc"
export FC="mpifort"
export MPIRUN="mpirun"
_MPI_BIN="$(dirname "$(command -v mpif90 2>/dev/null || command -v mpifort 2>/dev/null || command -v mpicc 2>/dev/null || echo /usr/bin/mpif90)")"
_MPI_INC="$(_first_dir "${_archlib}/openmpi/include" "/usr/include/openmpi")"
_MPI_LIB="$(_first_dir "${_archlib}/openmpi/lib" "${_archlib}")"

# HDF5 (openmpi build, to match system MED's HDF5 dependency)
_HDF5_INC="$(_first_dir "/usr/include/hdf5/openmpi" "/usr/include/hdf5/serial")"
_HDF5_LIB="$(_first_dir "${_archlib}/hdf5/openmpi" "${_archlib}/hdf5/serial" "${_archlib}")"

# MED (system only)
_MED_INC=""
_MED_LIB=""
[ -e "/usr/include/med.h" ] && _MED_INC="/usr/include"
if [ -e "${_archlib}/libmedC.so" ] || ls "${_archlib}/libmedC.so"* >/dev/null 2>&1; then
  _MED_LIB="${_archlib}"
fi

# METIS / MUMPS / ScaLAPACK
_METIS_INC="$(_first_dir "/usr/include")"
_METIS_LIB="$(_first_dir "${_archlib}")"
_MUMPS_INC="$(_first_dir "/usr/include")"
_MUMPS_LIB="$(_first_dir "${_archlib}")"
_SCALAPACK_LIB="$(_first_dir "${_archlib}")"

# Convenience env hints (non-fatal if unused)
export MPI_INCLUDE="${_MPI_INC}"; export MPI_LIBDIR="${_MPI_LIB}"
export HDF5_ROOT="/usr"; export HDF5_INCLUDE_PATH="${_HDF5_INC}"; export HDF5_LIBDIR="${_HDF5_LIB}"
[ -n "${_MED_INC}" ] && export MED_INCLUDE_PATH="${_MED_INC}"
[ -n "${_MED_LIB}" ] && export MED_LIBDIR="${_MED_LIB}"
export METIS_ROOT="/usr"; export MUMPS_ROOT="/usr"

# LD_LIBRARY_PATH (system dirs)
for _libdir in "${_MPI_LIB}" "${_HDF5_LIB}" "${_SCALAPACK_LIB}" "${_MUMPS_LIB}" "${_METIS_LIB}" "${_MED_LIB}" "${_archlib}"; do
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
for _incdir in "${_MPI_INC}" "${_HDF5_INC}" "${_MED_INC}" "${_METIS_INC}" "${_MUMPS_INC}"; do
  [ -n "${_incdir}" ] || continue
  case ":${CPATH}:" in
    *:"${_incdir}":*) ;;
    *) export CPATH="${_incdir}:${CPATH}";;
  esac
done

# TELEMAC Python API (TelApy) if built
_wrap_api_lib="${HOMETEL}/builds/${USETELCFG}/wrap_api/lib"
if [ -d "${_wrap_api_lib}" ]; then
  case ":${PYTHONPATH}:" in *:"${_wrap_api_lib}":*) ;; *) export PYTHONPATH="${_wrap_api_lib}:${PYTHONPATH}";; esac
  case ":${LD_LIBRARY_PATH}:" in *:"${_wrap_api_lib}":*) ;; *) export LD_LIBRARY_PATH="${_wrap_api_lib}:${LD_LIBRARY_PATH}";; esac
fi
if [ -d "${HOMETEL}/scripts/python3" ]; then
  case ":${PYTHONPATH}:" in *:"${HOMETEL}/scripts/python3":*) ;; *) export PYTHONPATH="${HOMETEL}/scripts/python3:${PYTHONPATH}";; esac
fi

echo "TELEMAC set: HOMETEL='${HOMETEL}', SYSTELCFG='${SYSTELCFG}', USETELCFG='${USETELCFG}'"
echo "HDF5 inc='${_HDF5_INC}', HDF5 lib='${_HDF5_LIB}'"
[ -n "${_MED_LIB}" ] && echo "MED lib='${_MED_LIB}' (system)"

export PYTHONUNBUFFERED="1"
EOF

  chmod +x "$PYSOURCE_PATH"
}

verify_telemac_build() {
  local HOMETEL="$1"
  local BUILD_BIN="${HOMETEL}/builds/hyinfompiubu/bin"

  log "Verifying TELEMAC build artifacts..."
  if [ ! -d "${BUILD_BIN}" ]; then
    warn "Build bin directory not found: ${BUILD_BIN} (compilation likely failed)."
    return 1
  fi

  local missing_exes=()
  local required_exes=("stbtel" "telemac2d" "telemac3d" "tomawac" "artemis" "gaia" "partel" "gretel")
  for exe in "${required_exes[@]}"; do
    [ -f "${BUILD_BIN}/${exe}" ] || missing_exes+=("$exe")
  done

  if [ ${#missing_exes[@]} -gt 0 ]; then
    warn "Missing executables in ${BUILD_BIN}: ${missing_exes[*]}"
    warn "Re-run with --verbose, or: source configs/pysource.mint22.sh && compile_telemac.py -v"
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

  log "Running TELEMAC config and compile steps (10-30 min)..."

  # Avoid MPI/X11 authorization issues during compilation.
  unset DISPLAY

  local verbose_flag=""
  [ "$VERBOSE" -eq 1 ] && verbose_flag="-v"

  local compile_status=0
  bash -lc "
    set -euo pipefail
    cd \"$HOMETEL\"
    source \"$HOMETEL/configs/pysource.mint22.sh\"
    echo '[*] Running config.py ...'
    config.py
    echo '[*] Running compile_telemac.py --clean ...'
    compile_telemac.py --clean $verbose_flag
  " || compile_status=$?

  [ "$compile_status" -eq 0 ] || die "TELEMAC compilation failed (exit $compile_status). See errors above."

  log "TELEMAC compilation command completed."
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

  create_cfg "$HOMETEL"
  create_pysource "$HOMETEL"
  run_compile "$HOMETEL"

  local SYSTEM_MED_ROOT
  SYSTEM_MED_ROOT="$(detect_system_med_root)"

  log "Installation finished."
  echo
  echo "To use TELEMAC in a new shell:"
  echo "  cd \"$HOMETEL/configs\""
  echo "  source pysource.mint22.sh"
  echo "  telemac2d.py --help"
  echo
  if [ -n "$SYSTEM_MED_ROOT" ]; then
    echo "MED support: enabled (system MED in /usr; SALOME-bundled MED is not used)."
  else
    echo "MED support: NOT detected. Install and recompile:"
    echo "  sudo apt-get install libmedc-dev libmed-dev libmedimport-dev libmed-tools"
    echo "  source pysource.mint22.sh && config.py && compile_telemac.py --clean"
  fi
}

main "$@"
