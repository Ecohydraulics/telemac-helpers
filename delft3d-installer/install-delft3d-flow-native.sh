#!/usr/bin/env bash
# install-delft3d-flow-native.sh
#
# Native, non-Docker Delft3D-FLOW / Delft3D 4 build attempt for Ubuntu or Linux Mint.
#
# This is intentionally an "attempt" script, not a guaranteed vendor-supported installer.
# Deltares documents Linux builds primarily through their AlmaLinux/oneAPI container setup.
# This script tries to reproduce enough of that environment on an apt-based host:
#   - Intel oneAPI compilers, MPI, and MKL pinned to the versions used by the
#     Deltares build container and Conan profile (oneAPI 2024.2, Intel MPI 2021.13)
#   - CMake >= 3.30 and Conan ~= 2.29 in a project-local Python virtual environment
#   - the compiler environment exported by the Deltares container:
#     CC=mpiicx, CXX=mpicxx, FC=mpiifx
#
# Default target:
#   CONFIG=d3d4-suite  -> Delft3D 4 suite, including d_hydro / flow2d3d for Delft3D-FLOW
#
# Usage:
#   chmod +x install-delft3d-flow-native.sh
#   ./install-delft3d-flow-native.sh
#
# Common variants:
#   ./install-delft3d-flow-native.sh --config flow2d3d
#   ./install-delft3d-flow-native.sh --src-dir "$HOME/src/delft3d" --prefix "$HOME/opt/delft3d-flow"
#   ./install-delft3d-flow-native.sh --tag <branch-tag-or-commit>
#   ./install-delft3d-flow-native.sh --skip-oneapi-install
#   ./install-delft3d-flow-native.sh --no-apt

set -Eeuo pipefail

REPO_URL="https://github.com/Deltares/Delft3D.git"
SRC_DIR="${HOME}/src/delft3d"
PREFIX="${HOME}/opt/delft3d-flow"
CONFIG="d3d4-suite"
BUILD_TYPE="Release"
GIT_REF=""
KEEP_BUILD=0
DO_APT=1
INSTALL_ONEAPI=1
RUN_TEST=1
JOBS="$(nproc 2>/dev/null || echo 2)"
LOG_DIR="${HOME}/.cache/delft3d-native-build"
LOG_FILE=""

# The version baseline used by the Deltares buildtools container and by the
# Conan profile delft3d_alma8_intel_2024 (conan/config/settings_user.yml only
# whitelists intel-cc 2024.2). Keep these in sync with upstream.
PROFILE_COMPILER_VERSION="2024.2"
ONEAPI_PINNED_PKGS=(
  intel-oneapi-compiler-dpcpp-cpp-2024.2
  intel-oneapi-compiler-fortran-2024.2
  intel-oneapi-mkl-devel-2024.2
  intel-oneapi-mpi-devel-2021.13
)
ONEAPI_FALLBACK_PKGS=(
  intel-oneapi-compiler-dpcpp-cpp
  intel-oneapi-compiler-fortran
  intel-oneapi-mkl-devel
  intel-oneapi-mpi-devel
)

msg()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Native Delft3D-FLOW / Delft3D 4 build attempt for Ubuntu or Linux Mint.

Options:
  --src-dir PATH             Delft3D source directory [default: ${SRC_DIR}]
  --prefix PATH              Install/copy target [default: ${PREFIX}]
  --config NAME              d3d4-suite or flow2d3d [default: ${CONFIG}]
  --build-type TYPE          Release, Debug, or RelWithDebInfo [default: ${BUILD_TYPE}]
  --tag REF                  Git branch/tag/commit to checkout after clone/fetch
  --jobs N                   Parallel build jobs [default: ${JOBS}]
  --keep-build               Do not delete existing build directory
  --skip-oneapi-install      Do not add Intel APT repo or install oneAPI packages
  --no-apt                   Do not install any apt packages
  --no-test                  Skip example test run
  -h, --help                 Show this help

Examples:
  ./install-delft3d-flow-native.sh
  ./install-delft3d-flow-native.sh --config flow2d3d
  ./install-delft3d-flow-native.sh --tag <branch-tag-or-commit>
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --src-dir) SRC_DIR="$2"; shift 2 ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --config) CONFIG="$2"; shift 2 ;;
    --build-type) BUILD_TYPE="$2"; shift 2 ;;
    --tag|--ref) GIT_REF="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --keep-build) KEEP_BUILD=1; shift ;;
    --skip-oneapi-install) INSTALL_ONEAPI=0; shift ;;
    --no-apt) DO_APT=0; INSTALL_ONEAPI=0; shift ;;
    --no-test) RUN_TEST=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

case "$CONFIG" in
  d3d4-suite|flow2d3d) ;;
  *) die "--config must be d3d4-suite or flow2d3d for Delft3D-FLOW-oriented builds." ;;
esac

case "$BUILD_TYPE" in
  Release|Debug|RelWithDebInfo) ;;
  *) die "--build-type must be Release, Debug, or RelWithDebInfo." ;;
esac

mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/build-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

msg "Logging to ${LOG_FILE}"

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || die "sudo is required unless you run as root."
  SUDO="sudo"
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

apt_install_if_enabled() {
  [[ "$DO_APT" -eq 1 ]] || return 0
  msg "Installing apt packages: $*"
  $SUDO apt-get update
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y --no-install-recommends "$@"
}

detect_os() {
  [[ -r /etc/os-release ]] || die "/etc/os-release not found."
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_LIKE="${ID_LIKE:-}"
  OS_NAME="${PRETTY_NAME:-unknown}"

  msg "Detected OS: ${OS_NAME}"

  if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "linuxmint" && "$OS_LIKE" != *"ubuntu"* && "$OS_LIKE" != *"debian"* ]]; then
    warn "This script is written for apt-based Ubuntu/Linux Mint hosts. Continuing anyway."
  fi
}

setup_base_packages() {
  # Mirrors the tooling of the Deltares buildtools container (gcc toolchain,
  # make, m4, patchelf, ninja) plus what the Conan recipes need to build the
  # third-party dependencies from source. rsync is used to copy the install tree.
  apt_install_if_enabled \
    ca-certificates curl wget gnupg git \
    build-essential cmake ninja-build pkg-config \
    python3 python3-venv python3-pip \
    flex bison m4 file patch patchelf \
    autoconf automake libtool \
    unzip xz-utils tar rsync \
    lsb-release
}

setup_intel_repo_and_packages() {
  [[ "$INSTALL_ONEAPI" -eq 1 ]] || {
    msg "Skipping Intel oneAPI installation by request."
    return 0
  }

  msg "Configuring Intel oneAPI APT repository"
  apt_install_if_enabled ca-certificates wget gnupg

  wget -O- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB \
    | gpg --dearmor \
    | $SUDO tee /usr/share/keyrings/oneapi-archive-keyring.gpg >/dev/null

  echo "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" \
    | $SUDO tee /etc/apt/sources.list.d/oneAPI.list >/dev/null

  $SUDO apt-get update

  # Prefer the pinned versions that match the Deltares Conan profile
  # (delft3d_alma8_intel_2024: intel-cc 2024.2, Intel MPI 2021.13).
  # A newer oneAPI usually works too, but then the Conan profile and the
  # allowed compiler versions must be patched (this script does that below).
  local missing=0
  for p in "${ONEAPI_PINNED_PKGS[@]}"; do
    if ! apt-cache show "$p" >/dev/null 2>&1; then
      warn "Pinned APT package not found in Intel repo: $p"
      missing=1
    fi
  done

  if [[ "$missing" -eq 0 ]]; then
    msg "Installing pinned Intel oneAPI packages: ${ONEAPI_PINNED_PKGS[*]}"
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y --no-install-recommends "${ONEAPI_PINNED_PKGS[@]}"
  else
    warn "Falling back to the latest Intel oneAPI compiler/MPI/MKL packages."
    warn "The Conan profile will be patched to accept the detected compiler version."
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y --no-install-recommends "${ONEAPI_FALLBACK_PKGS[@]}"
  fi
}

load_oneapi() {
  if [[ ! -f /opt/intel/oneapi/setvars.sh ]]; then
    die "Intel oneAPI setvars.sh not found at /opt/intel/oneapi/setvars.sh. Install oneAPI or rerun without --skip-oneapi-install."
  fi

  # setvars.sh can complain if sourced repeatedly. Suppress the shellcheck warning intentionally.
  # shellcheck disable=SC1091
  source /opt/intel/oneapi/setvars.sh --force

  require_cmd icx
  require_cmd icpx
  require_cmd ifx
  # MPI compiler wrappers: the Deltares container builds with CC=mpiicx,
  # CXX=mpicxx (g++ wrapper), FC=mpiifx. Without intel-oneapi-mpi-devel these
  # do not exist and the CMake configure of Delft3D itself will misdetect.
  require_cmd mpiicx
  require_cmd mpiifx
  require_cmd mpicxx

  msg "Intel compiler versions"
  icx --version | head -n 1 || true
  icpx --version | head -n 1 || true
  ifx --version | head -n 1 || true
}

find_oneapi_compiler_dir() {
  local ifx_path
  ifx_path="$(command -v ifx || true)"
  [[ -n "$ifx_path" ]] || die "ifx not found after sourcing oneAPI."

  # Usually /opt/intel/oneapi/compiler/<VERSION>/bin/ifx.
  local dir
  dir="$(cd "$(dirname "$ifx_path")/.." && pwd -P)"
  if [[ "$(basename "$dir")" == "bin" ]]; then
    dir="$(cd "$dir/.." && pwd -P)"
  fi

  # Normalize if command -v points to /opt/intel/oneapi/compiler/latest/bin/ifx.
  if [[ "$dir" == *"/compiler/latest" && -L /opt/intel/oneapi/compiler/latest ]]; then
    dir="$(readlink -f /opt/intel/oneapi/compiler/latest)"
  fi

  echo "$dir"
}

detect_compiler_version() {
  # Reported like: "ifx (IFX) 2024.2.1 20240711". Conan wants major.minor.
  local raw
  raw="$(ifx --version | head -n 1 | grep -Eo '[0-9]{4}\.[0-9]+' | head -n 1 || true)"
  echo "${raw:-${PROFILE_COMPILER_VERSION}}"
}

setup_python_venv() {
  msg "Creating Python virtual environment"
  python3 -m venv "${SRC_DIR}/.venv"
  # shellcheck disable=SC1091
  source "${SRC_DIR}/.venv/bin/activate"
  python -m pip install --upgrade pip wheel setuptools
  # Delft3D's src/cmake/CMakeLists.txt requires CMake >= 3.30, which is newer
  # than what Ubuntu 24.04 / Mint 22 ship. The pip wheel provides a current
  # CMake inside the venv. Conan is pinned close to the Deltares buildtools
  # container (conan ~= 2.29).
  python -m pip install "conan~=2.29" "cmake>=3.30"
  msg "Build tool versions in venv"
  conan --version
  cmake --version | head -n 1
}

clone_or_update_repo() {
  mkdir -p "$(dirname "$SRC_DIR")"

  if [[ ! -d "${SRC_DIR}/.git" ]]; then
    msg "Cloning Delft3D repository"
    git clone "$REPO_URL" "$SRC_DIR"
  else
    msg "Updating existing Delft3D repository"
    git -C "$SRC_DIR" fetch --all --tags --prune
  fi

  if [[ -n "$GIT_REF" ]]; then
    msg "Checking out ${GIT_REF}"
    git -C "$SRC_DIR" checkout "$GIT_REF"
  fi

  msg "Delft3D revision"
  git -C "$SRC_DIR" --no-pager log -1 --oneline
}

patch_conan_profile_for_native_oneapi() {
  local profile="${SRC_DIR}/conan/config/profiles/delft3d_alma8_intel_2024"
  local settings_user="${SRC_DIR}/conan/config/settings_user.yml"
  [[ -f "$profile" ]] || die "Expected Conan profile not found: $profile"

  local compiler_dir
  compiler_dir="$(find_oneapi_compiler_dir)"
  local icx_path="${compiler_dir}/bin/icx"
  local icpx_path="${compiler_dir}/bin/icpx"
  local ifx_path="${compiler_dir}/bin/ifx"

  [[ -x "$icx_path" && -x "$icpx_path" && -x "$ifx_path" ]] || {
    warn "Could not infer compiler paths under ${compiler_dir}; using command -v paths."
    icx_path="$(command -v icx)"
    icpx_path="$(command -v icpx)"
    ifx_path="$(command -v ifx)"
  }

  local major_minor
  major_minor="$(detect_compiler_version)"

  msg "Patching Conan profile for native compiler paths"
  msg "Compiler version detected as: ${major_minor}"
  msg "icx:  ${icx_path}"
  msg "icpx: ${icpx_path}"
  msg "ifx:  ${ifx_path}"

  cp "$profile" "${profile}.bak.$(date +%Y%m%d-%H%M%S)"

  python3 - "$profile" "$major_minor" "$icx_path" "$icpx_path" "$ifx_path" <<'PY'
import json
import re
import sys
from pathlib import Path

profile = Path(sys.argv[1])
version, icx, icpx, ifx = sys.argv[2:6]
text = profile.read_text()

text = re.sub(r"compiler\.version=[^\s]+", f"compiler.version={version}", text)

replacement = 'tools.build:compiler_executables=' + json.dumps({
    "c": icx,
    "cpp": icpx,
    "fortran": ifx,
})
text = re.sub(r'tools\.build:compiler_executables=\{[^}]+\}', replacement, text)

profile.write_text(text)
PY

  # conan/config/settings_user.yml only whitelists intel-cc 2024.2. If the
  # host has a different oneAPI version, add it to the allowed versions,
  # otherwise 'conan install' fails with "Invalid setting".
  if [[ "$major_minor" != "$PROFILE_COMPILER_VERSION" && -f "$settings_user" ]]; then
    msg "Allowing intel-cc version ${major_minor} in settings_user.yml"
    python3 - "$settings_user" "$major_minor" <<'PY'
import re
import sys
from pathlib import Path

settings = Path(sys.argv[1])
version = sys.argv[2]
text = settings.read_text()

def add_version(match):
    versions = [v.strip().strip('"') for v in match.group(1).split(",")]
    if version not in versions:
        versions.append(version)
    return 'version: [' + ", ".join(f'"{v}"' for v in versions) + ']'

text = re.sub(r'version: \[([^\]]*)\]', add_version, text, count=1)
settings.write_text(text)
PY
  fi

  grep -E 'compiler.version|tools.build:compiler_executables|os.distro' "$profile" || true
  warn "The profile still says os.distro=Alma8. That is deliberate: changing it can alter Conan package IDs and make the Deltares lockfile less useful."
}

initialize_conan_external() {
  msg "Initializing Conan configuration for external/open-source developer mode"
  cd "$SRC_DIR"
  # Installs the (patched) profiles and settings into the Conan home, removes
  # the Deltares Nexus remotes, and registers conan/recipes as local remote.
  python run_conan.py initialize external
}

export_container_build_env() {
  # The Deltares build container exports these in /etc/bashrc. build.py runs
  # CMake directly, and without them CMake would pick the GNU toolchain for
  # Delft3D itself while the Conan dependencies are built with Intel oneAPI.
  # CXX=mpicxx (the g++ wrapper) is deliberate and mirrors the container.
  msg "Exporting container-equivalent compiler environment"
  export CC=mpiicx
  export CXX=mpicxx
  export FC=mpiifx
  export CMAKE_BUILD_PARALLEL_LEVEL="$JOBS"
  export MAKEFLAGS="-j${JOBS}"
}

build_delft3d() {
  msg "Building Delft3D config=${CONFIG}, build_type=${BUILD_TYPE}"

  cd "$SRC_DIR"

  local keep_arg=()
  if [[ "$KEEP_BUILD" -eq 1 ]]; then
    keep_arg=(--keep-build)
  fi

  python build.py \
    --config "$CONFIG" \
    --build \
    --build-type "$BUILD_TYPE" \
    --build-dependencies \
    "${keep_arg[@]}"
}

copy_install_tree() {
  # build.py on Linux installs into build_<config>_<build_type>/install.
  local build_dir="${SRC_DIR}/build_${CONFIG}_$(printf '%s' "$BUILD_TYPE" | tr '[:upper:]' '[:lower:]')"
  local install_dir="${build_dir}/install"

  [[ -d "$install_dir" ]] || die "Install directory not found after build: $install_dir"

  msg "Copying install tree to ${PREFIX}"
  mkdir -p "$PREFIX"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "${install_dir}/" "${PREFIX}/"
  else
    warn "rsync not found; using cp -a (stale files in ${PREFIX} are not removed)."
    cp -a "${install_dir}/." "${PREFIX}/"
  fi

  cat > "${PREFIX}/env.sh" <<EOF
# Source this before running Delft3D binaries:
#   source "${PREFIX}/env.sh"
source /opt/intel/oneapi/setvars.sh --force >/dev/null 2>&1 || true
export DELFT3D_HOME="${PREFIX}"
export PATH="${PREFIX}/bin:\${PATH}"
export LD_LIBRARY_PATH="${PREFIX}/lib:${PREFIX}/lib64:\${LD_LIBRARY_PATH:-}"
EOF

  msg "Installed/copied Delft3D tree:"
  find "$PREFIX" -maxdepth 2 -type f \( -name 'run_dflow2d3d.sh' -o -name 'flow2d3d*' -o -name 'd_hydro*' \) -print || true
}

run_smoke_test() {
  [[ "$RUN_TEST" -eq 1 ]] || {
    msg "Skipping smoke test by request."
    return 0
  }

  local run_script="${PREFIX}/bin/run_dflow2d3d.sh"
  [[ -x "$run_script" ]] || {
    warn "Smoke test skipped: ${run_script} not found or not executable."
    return 0
  }

  local example="${SRC_DIR}/examples/delft3d4/01_standard"
  [[ -d "$example" ]] || {
    warn "Smoke test skipped: example directory not found: ${example}"
    return 0
  }

  msg "Running Delft3D 4 smoke test in ${example}"
  (
    cd "$example"
    rm -f trih-f34.* trim-f34.* tri-diag.f34
    # shellcheck disable=SC1091
    source "${PREFIX}/env.sh"
    "$run_script"
  )

  # The f34 example writes history (trih) and map (trim) result files.
  if compgen -G "${example}/trih-f34.*" >/dev/null && compgen -G "${example}/trim-f34.*" >/dev/null; then
    if grep -qi 'ERROR' "${example}/tri-diag.f34" 2>/dev/null; then
      warn "Smoke test produced result files, but tri-diag.f34 contains errors. Inspect ${example}/tri-diag.f34."
    else
      msg "Smoke test passed: trih-f34.* and trim-f34.* result files were written."
    fi
  else
    warn "Smoke test did not produce the expected trih-f34.*/trim-f34.* result files. Inspect ${example} and ${LOG_FILE}."
  fi
}

main() {
  detect_os
  setup_base_packages
  setup_intel_repo_and_packages
  clone_or_update_repo
  setup_python_venv
  load_oneapi
  patch_conan_profile_for_native_oneapi
  initialize_conan_external
  export_container_build_env
  build_delft3d
  copy_install_tree
  run_smoke_test

  cat <<EOF

Native Delft3D-FLOW build attempt finished.

Install/copy prefix:
  ${PREFIX}

To use it in a new shell:
  source "${PREFIX}/env.sh"

Try:
  cd "${SRC_DIR}/examples/delft3d4/01_standard"
  run_dflow2d3d.sh

Build log:
  ${LOG_FILE}

If this failed, inspect the last ~100 lines:
  tail -n 100 "${LOG_FILE}"
EOF
}

main "$@"
