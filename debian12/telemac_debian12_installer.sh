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
#   ./install_telemac_debian12.sh --root "$HOME/opt" --tag v9.0.0
#   ./install_telemac_debian12.sh --salome-tar ~/Downloads/SALOME-9.15.0.tar.gz
#   ./install_telemac_debian12.sh --salome-tar SALOME-9.15.0.tar.gz --salome-md5 SALOME-9.15.0.tar.gz.md5
#
# Do NOT run this script as root. Use a normal user with sudo rights.

set -euo pipefail

log()  { echo "[*] $*"; }
warn() { echo "[WARN] $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --root DIR             Installation root directory (default: \$HOME/opt)
  --tag TAG              TELEMAC git tag or branch to checkout (default: v9.0.0)
  --repo URL             TELEMAC git repository URL
                         (default: https://gitlab.pam-retd.fr/otm/telemac-mascaret.git)

  --salome-tar FILE      Path to SALOME tarball to install into <root>/salome
  --salome-archive FILE  Alias for --salome-tar
  --salome-md5 FILE      Optional: .md5 file to verify SALOME tarball integrity

  --skip-apt             Do not install apt dependencies for TELEMAC or SALOME
  --skip-compile         Do not run compile_telemac.py
  -h, --help             Show this help and exit

Typical flow:
  1. Download SALOME-*.tar.gz and its .md5.
  2. Run this script with --salome-tar (and optionally --salome-md5).
  3. Source pysource.debian12.sh and use TELEMAC with MED support if SALOME is present.
EOF
}

# Defaults
ROOT_DIR="${ROOT_DIR:-$HOME/opt}"
TELEMAC_TAG="${TELEMAC_TAG:-v9.0.0}"
TELEMAC_REPO="${TELEMAC_REPO:-https://gitlab.pam-retd.fr/otm/telemac-mascaret.git}"

SALOME_TAR="${SALOME_TAR:-}"
SALOME_MD5="${SALOME_MD5:-}"

SKIP_APT=0
SKIP_COMPILE=0

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
    libhdf5-openmpi-dev \
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

  if [ -n "$SALOME_MD5" ]; then
    if [ ! -f "$SALOME_MD5" ]; then
      die "SALOME md5 file '$SALOME_MD5' not found."
    fi
    log "Verifying SALOME tarball MD5 against '$SALOME_MD5'..."
    local expected got
    expected="$(awk 'NR==1 {print $1}' "$SALOME_MD5")"
    got="$(md5sum "$SALOME_TAR" | awk '{print $1}')"
    if [ "$expected" != "$got" ]; then
      die "SALOME MD5 mismatch: expected $expected, got $got"
    fi
    log "SALOME tarball MD5 check passed."
  else
    warn "No --salome-md5 provided; SALOME tarball integrity not verified."
  fi

  apt_install_deps_salome

  local SALOME_ROOT="${ROOT_DIR}/salome"
  log "Installing SALOME tarball '$SALOME_TAR' into '$SALOME_ROOT'..."
  mkdir -p "$SALOME_ROOT"

  case "$SALOME_TAR" in
    *.tar.gz|*.tgz)
      tar -xzf "$SALOME_TAR" -C "$SALOME_ROOT" --strip-components=1
      ;;
    *.tar.xz)
      tar -xJf "$SALOME_TAR" -C "$SALOME_ROOT" --strip-components=1
      ;;
    *.tar.bz2)
      tar -xjf "$SALOME_TAR" -C "$SALOME_ROOT" --strip-components=1
      ;;
    *.tar)
      tar -xf "$SALOME_TAR" -C "$SALOME_ROOT" --strip-components=1
      ;;
    *)
      die "Unknown SALOME archive extension for '$SALOME_TAR'"
      ;;
  esac

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
  # Try to locate MED libraries from a SALOME install under ROOT_DIR or $HOME/opt
  local SALOME_MED_ROOT=""
  local candidate1="${ROOT_DIR}/salome/BINARIES-DB12/medfile"
  local candidate2="$HOME/opt/salome/BINARIES-DB12/medfile"

  if [ -d "${candidate1}/lib" ]; then
    SALOME_MED_ROOT="$candidate1"
  elif [ -d "${candidate2}/lib" ]; then
    SALOME_MED_ROOT="$candidate2"
  fi

  echo "$SALOME_MED_ROOT"
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

  local SALOME_INC_BLOCK=""
  local SALOME_LIB_BLOCK=""
  local SALOME_INCS_ALL_MED=""
  local SALOME_LIBS_ALL_MED=""

  if [ -n "$SALOME_MED_ROOT" ]; then
    log "Detected SALOME MED libraries at '$SALOME_MED_ROOT'; enabling MED support in cfg."
    SALOME_INC_BLOCK="inc_med:       -I ${SALOME_MED_ROOT}/include"
    SALOME_LIB_BLOCK="libs_med:      -L ${SALOME_MED_ROOT}/lib -lmedC -lmed -lmedimport"
    SALOME_INCS_ALL_MED="[inc_med] "
    SALOME_LIBS_ALL_MED="[libs_med] "
  else
    log "No SALOME MED libraries detected; cfg will be generated without MED support."
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
version:  9.0
options:  mpi dyn
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
cflags:  -fPIC -O3
fc:      mpifort
fflags:  -cpp -O3 -fPIC -fconvert=big-endian -frecord-marker=4 -DHAVE_MPI
cmd_obj_c: [cc] [cflags] -c <srcName> -o <objName>
cmd_obj:   [fc] [fflags] -c <mods> <incs> <f95name>
cmd_lib:   ar cru <libname> <objs>
cmd_exe:   [fc] [fflags] -o <exename> <objs> <libs>
par_cmdexec:   <config>/partel < <partel.par> >> <partel.log>
mpi_cmdexec:   mpirun -np <ncsize> <exename>

# MPI headers (OpenMPI)
inc_mpi:       -I /usr/lib/x86_64-linux-gnu/openmpi/include

# HDF5 parallel
inc_hdf5:      -I /usr/include/hdf5/openmpi
libs_hdf5:     -L /usr/lib/x86_64-linux-gnu/hdf5/openmpi -lhdf5_fortran -lhdf5hl_fortran -lhdf5_hl -lhdf5

# MED-fichier (optional, via SALOME)
$SALOME_INC_BLOCK
$SALOME_LIB_BLOCK

# METIS
inc_metis:     -I /usr/include
libs_metis:    -L /usr/lib/x86_64-linux-gnu -lmetis

# MUMPS + ScaLAPACK
inc_mumps:     -I /usr/include
libs_mumps:    -L /usr/lib/x86_64-linux-gnu -ldmumps -lmumps_common -lpord -lscalapack-openmpi -lblas -llapack

incs_all: [inc_mpi] [inc_hdf5] ${SALOME_INCS_ALL_MED}[inc_metis] [inc_mumps]
libs_all: [libs_hdf5] ${SALOME_LIBS_ALL_MED}[libs_metis] [libs_mumps]

[hyinfompideb12]
brief: Debian 12 gfortran + OpenMPI + HDF5 + METIS + MUMPS/ScaLAPACK$( [ -n "$SALOME_MED_ROOT" ] && printf " + MED" || printf "" )
system: linux
mpi:   openmpi
compiler: gfortran
pyd_fcompiler: gnu95
f2py_name: f2py
bin_dir: <root>/builds/hyinfompideb12/bin
lib_dir: <root>/builds/hyinfompideb12/lib
obj_dir: <root>/builds/hyinfompideb12/obj
options: mpi dyn
cmd_obj:   [fc] [fflags] -c <mods> <incs> <f95name>
cmd_lib:   ar cru <libname> <objs>
cmd_exe:   [fc] [fflags] -o <exename> <objs> <libs>
mods_all:  -I <config>
incs_all:  [inc_mpi] [inc_hdf5] ${SALOME_INCS_ALL_MED}[inc_metis] [inc_mumps]
libs_all:  [libs_hdf5] ${SALOME_LIBS_ALL_MED}[libs_metis] [libs_mumps]
ldflags_opt:   -Wl,-rpath,/usr/lib/x86_64-linux-gnu/hdf5/openmpi
ldflags_debug: -Wl,-rpath,/usr/lib/x86_64-linux-gnu/hdf5/openmpi
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

# HDF5 (parallel)
_HDF5_INC="$(_first_dir \
  "/usr/include/hdf5/openmpi" \
  "/usr/include/hdf5/serial")"
_HDF5_LIB="$(_first_dir \
  "${_archlib}/hdf5/openmpi" \
  "${_archlib}/hdf5/serial" \
  "${_archlib}")"

# SALOME / MED
# Default SALOME root: sibling to HOMETEL, i.e. ROOT_DIR/salome
: "${SALOME_ROOT:=$(cd "${HOMETEL}/.." && pwd)/salome}"
_MED_ROOT="$(_first_dir \
  "${SALOME_ROOT}/BINARIES-DB12/medfile" \
  "${SALOME_ROOT}/medfile")"
if [ -n "${_MED_ROOT}" ]; then
  export _MED_ROOT
  export _MED_INC="${_MED_ROOT}/include"
  export _MED_LIB="${_MED_ROOT}/lib"
fi

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
[ -n "${_MED_ROOT}" ] && echo "MED root='${_MED_ROOT}' (SALOME_ROOT='${SALOME_ROOT}')"

export PYTHONUNBUFFERED="1"
EOF

  chmod +x "$PYSOURCE_PATH"
}

run_compile() {
  local HOMETEL="$1"

  if [ "$SKIP_COMPILE" -eq 1 ]; then
    log "Skipping TELEMAC compilation (per --skip-compile)."
    return
  fi

  log "Running TELEMAC config and compile steps."
  bash -lc "
    set -euo pipefail
    cd \"$HOMETEL\"
    source \"$HOMETEL/configs/pysource.debian12.sh\"
    config.py
    compile_telemac.py --clean
  "
  log "TELEMAC compilation completed successfully."
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
    log "SALOME tarball:        not specified (MED via SALOME will be disabled)."
  fi

  apt_install_deps_telemac
  install_salome_if_requested
  clone_telemac

  local HOMETEL
  HOMETEL="$(cd "${ROOT_DIR}/telemac-mascaret" && pwd)"

  create_cfg "$HOMETEL"
  create_pysource "$HOMETEL"
  run_compile "$HOMETEL"

  local MED_ROOT
  MED_ROOT="$(detect_salome_med_root)"

  log "Installation finished."
  echo
  echo "To use TELEMAC in a new shell:"
  echo "  cd \"$HOMETEL/configs\""
  echo "  source pysource.debian12.sh"
  echo "  telemac2d.py --help"
  echo
  if [ -n "$MED_ROOT" ]; then
    echo "MED / SALOME support: enabled (MED root detected at '$MED_ROOT')."
  else
    echo "MED / SALOME support: not detected."
    echo "If you want MED I/O:"
    echo "  1. Download a SALOME tarball and its .md5."
    echo "  2. Rerun this installer with --salome-tar and optionally --salome-md5."
    echo "  3. After that, rerun config.py and compile_telemac.py."
  fi
}

main "$@"

