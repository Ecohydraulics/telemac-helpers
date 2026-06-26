#!/usr/bin/env bash
# install_reef3d.sh
# Auto-installer for REEF3D and DIVEMesh on Debian-family Linux systems.
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

cat <<'EOF'
This installer is provided without warranty.

It may install packages, download third-party code, compile software,
create symlinks, and modify user-level desktop/menu entries. Review the
script before continuing. Use at your own risk.

EOF

set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
PREFIX="${REEF3D_PREFIX:-$HOME/opt/reef3d}"
BUILD_ROOT="${REEF3D_BUILD_DIR:-$HOME/.cache/reef3d-build}"
JOBS="${REEF3D_JOBS:-$(nproc 2>/dev/null || echo 2)}"
CREATE_DESKTOP_ENV="${REEF3D_CREATE_DESKTOP:-}"
FORCE_REBUILD="${REEF3D_FORCE_REBUILD:-0}"

REEF3D_REPO="REEF3D/REEF3D"
DIVEMESH_REPO="REEF3D/DIVEMesh"

log()  { printf '\033[1;32m[reef3d-installer]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warning]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; }

on_error() {
  local exit_code=$?
  err "Installation failed at line ${BASH_LINENO[0]} with exit code ${exit_code}."
  err "Build directory kept at: ${BUILD_ROOT}"
  exit "$exit_code"
}
trap on_error ERR

usage() {
  cat <<USAGE
${SCRIPT_NAME} — install REEF3D + DIVEMesh from the latest GitHub releases

Usage:
  bash ${SCRIPT_NAME} [options]

Options:
  --prefix DIR       Install binaries and source snapshots under DIR
                     Default: ${PREFIX}
  --build-dir DIR    Build/download work directory
                     Default: ${BUILD_ROOT}
  -j, --jobs N       Parallel make jobs
                     Default: ${JOBS}
  --force            Remove old build directories before rebuilding
  -h, --help         Show this help

Environment overrides:
  REEF3D_PREFIX=/path/to/install
  REEF3D_BUILD_DIR=/path/to/build-cache
  REEF3D_JOBS=8
  REEF3D_CREATE_DESKTOP=1       Create desktop launcher without prompting
  REEF3D_CREATE_DESKTOP=0       Do not create desktop launcher
  REEF3D_FORCE_REBUILD=1        Equivalent to --force

Notes:
  - This installer intentionally supports apt-based Debian-family systems only.
  - It uses Debian/Ubuntu/Mint system packages for OpenMPI, HYPRE and Eigen.
  - REEF3D's Makefile is patched from /usr/local/hypre assumptions to distro paths.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      PREFIX="${2:?Missing value for --prefix}"
      shift 2
      ;;
    --build-dir)
      BUILD_ROOT="${2:?Missing value for --build-dir}"
      shift 2
      ;;
    -j|--jobs)
      JOBS="${2:?Missing value for --jobs}"
      shift 2
      ;;
    --force)
      FORCE_REBUILD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "Unknown argument: $1"
      usage
      exit 2
      ;;
  esac
done

if ! [[ "$JOBS" =~ ^[0-9]+$ ]] || [[ "$JOBS" -lt 1 ]]; then
  err "Invalid jobs value: ${JOBS}"
  exit 2
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1
}

as_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  elif require_cmd sudo; then
    sudo "$@"
  else
    err "Need root privileges for: $*"
    err "Install sudo or run this script as root."
    exit 1
  fi
}

detect_platform() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    err "Unsupported OS: $(uname -s). This installer targets Linux only."
    exit 1
  fi

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_LIKE="${ID_LIKE:-}"
    OS_PRETTY="${PRETTY_NAME:-Linux}"
  else
    OS_ID="unknown"
    OS_LIKE=""
    OS_PRETTY="Linux"
  fi

  log "Detected platform: ${OS_PRETTY}"

  if require_cmd apt-get && { [[ "${OS_ID}" =~ ^(debian|ubuntu|linuxmint|lmde|pop|kali)$ ]] || [[ " ${OS_LIKE} " == *" debian "* ]] || [[ " ${OS_LIKE} " == *" ubuntu "* ]]; }; then
    PKG_MANAGER="apt"
  else
    err "Unsupported Linux distribution for this installer."
    err "Detected ID='${OS_ID}', ID_LIKE='${OS_LIKE}'."
    err "Use Debian, Ubuntu, Linux Mint, LMDE, or adapt the dependency-install section manually."
    exit 1
  fi
}

install_dependencies_apt() {
  local packages=(
    build-essential
    g++
    gcc
    gfortran
    make
    git
    curl
    ca-certificates
    tar
    gzip
    python3
    dpkg-dev
    pkg-config
    cmake
    libopenmpi-dev
    openmpi-bin
    mpi-default-dev
    mpi-default-bin
    libhypre-dev
    libeigen3-dev
    desktop-file-utils
    xdg-utils
  )

  log "Updating apt package index..."
  as_root apt-get update

  log "Installing build/runtime dependencies..."
  as_root apt-get install -y "${packages[@]}"
}

ensure_dependencies() {
  case "${PKG_MANAGER}" in
    apt) install_dependencies_apt ;;
    *) err "Internal error: unknown package manager '${PKG_MANAGER}'"; exit 1 ;;
  esac

  local required_commands=(git curl tar make g++ mpicxx python3 dpkg-architecture)
  for cmd in "${required_commands[@]}"; do
    if ! require_cmd "$cmd"; then
      err "Required command not found after dependency installation: ${cmd}"
      exit 1
    fi
  done
}

latest_release_json() {
  local repo="$1"
  curl -fsSL --retry 3 --connect-timeout 20 "https://api.github.com/repos/${repo}/releases/latest"
}

json_field() {
  local field="$1"
  python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get(sys.argv[1], ""))' "$field"
}

download_latest_release() {
  local repo="$1"
  local name="$2"
  local dest="$3"

  mkdir -p "${dest}"

  local json tag tarball archive
  log "Resolving latest ${name} release from GitHub (${repo})..."

  json="$(latest_release_json "$repo" || true)"
  tag="$(printf '%s' "$json" | json_field tag_name 2>/dev/null || true)"
  tarball="$(printf '%s' "$json" | json_field tarball_url 2>/dev/null || true)"

  if [[ -z "${tag}" || -z "${tarball}" ]]; then
    warn "Could not resolve GitHub latest-release metadata for ${repo}; falling back to current master branch."
    tag="master"
    tarball="https://github.com/${repo}/archive/refs/heads/master.tar.gz"
  fi

  archive="${BUILD_ROOT}/${name}-${tag}.tar.gz"
  log "Downloading ${name} ${tag}..."
  curl -fL --retry 3 --connect-timeout 20 -o "${archive}" "${tarball}"

  if [[ "${FORCE_REBUILD}" == "1" && -d "${dest}" ]]; then
    rm -rf "${dest}"
    mkdir -p "${dest}"
  fi

  rm -rf "${dest:?}/"*
  tar -xzf "${archive}" --strip-components=1 -C "${dest}"
  printf '%s\n' "${tag}" > "${dest}/.installed_from_release"
}

patch_divemesh_makefile() {
  local src_dir="$1"
  local mf="${src_dir}/Makefile"
  [[ -f "${mf}" ]] || { err "DIVEMesh Makefile not found: ${mf}"; exit 1; }

  # Some upstream DIVEMesh snapshots currently contain 'CXX := -g++', which normal shells interpret as a command named '-g++'.
  if grep -qE '^CXX[[:space:]]*:=.*-g\+\+' "${mf}"; then
    log "Patching DIVEMesh Makefile compiler from '-g++' to 'g++'..."
    sed -i -E 's|^CXX[[:space:]]*:=.*$|CXX := g++|' "${mf}"
  fi

  sed -i -E 's|-std=c\+\+(11|14)|-std=c++17|g' "${mf}"
}

find_hypre_include_dir() {
  local candidate
  for candidate in /usr/include/hypre /usr/local/hypre/include; do
    if [[ -d "${candidate}" ]] && compgen -G "${candidate}/*.h" >/dev/null; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  candidate="$(dpkg -L libhypre-dev 2>/dev/null | grep -E '/include(/hypre)?$' | head -n 1 || true)"
  [[ -n "${candidate}" ]] && { printf '%s\n' "${candidate}"; return 0; }

  return 1
}

find_hypre_lib_dir() {
  local lib_path multiarch candidate

  lib_path="$(ldconfig -p 2>/dev/null | awk '/libHYPRE\.so/ {print $NF; exit}' || true)"
  if [[ -n "${lib_path}" && -f "${lib_path}" ]]; then
    dirname "${lib_path}"
    return 0
  fi

  multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || true)"
  for candidate in "/usr/lib/${multiarch}" /usr/lib/x86_64-linux-gnu /usr/lib /usr/local/hypre/lib; do
    if [[ -f "${candidate}/libHYPRE.so" || -f "${candidate}/libHYPRE.a" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

patch_reef3d_makefile() {
  local src_dir="$1"
  local mf="${src_dir}/Makefile"
  [[ -f "${mf}" ]] || { err "REEF3D Makefile not found: ${mf}"; exit 1; }

  local hypre_include hypre_lib eigen_include
  hypre_include="$(find_hypre_include_dir)" || { err "Could not locate HYPRE include directory."; exit 1; }
  hypre_lib="$(find_hypre_lib_dir)" || { err "Could not locate HYPRE library directory."; exit 1; }

  if [[ -d /usr/include/eigen3 ]]; then
    eigen_include="/usr/include/eigen3"
  elif [[ -d "${src_dir}/ThirdParty/eigen-3.3.8" ]]; then
    eigen_include="ThirdParty/eigen-3.3.8"
  else
    err "Could not locate Eigen include directory."
    exit 1
  fi

  log "Patching REEF3D Makefile for distro HYPRE/Eigen paths..."
  sed -i -E "s|^HYPRE_DIR[[:space:]]*:=.*$|HYPRE_DIR := /usr|" "${mf}"
  sed -i -E "s|^EIGEN_DIR[[:space:]]*:=.*$|EIGEN_DIR := ${eigen_include}|" "${mf}"
  sed -i -E 's|-std=c\+\+(11|14)|-std=c++17|g' "${mf}"
  sed -i -E "s|^LDFLAGS[[:space:]]*:=.*$|LDFLAGS := -L ${hypre_lib} -lHYPRE|" "${mf}"
  sed -i -E "s|^INCLUDE[[:space:]]*:=.*$|INCLUDE := -I ${hypre_include} -I ${eigen_include} -DEIGEN_MPL2_ONLY|" "${mf}"

  log "Using HYPRE include: ${hypre_include}"
  log "Using HYPRE library: ${hypre_lib}"
  log "Using Eigen include: ${eigen_include}"
}

build_divemesh() {
  local src_dir="$1"
  log "Building DIVEMesh with ${JOBS} parallel job(s)..."
  patch_divemesh_makefile "${src_dir}"
  make -C "${src_dir}" clean >/dev/null 2>&1 || true
  make -C "${src_dir}" -j "${JOBS}"

  if [[ ! -x "${src_dir}/bin/DiveMESH" ]]; then
    err "DIVEMesh build finished but binary is missing: ${src_dir}/bin/DiveMESH"
    exit 1
  fi
}

build_reef3d() {
  local src_dir="$1"
  log "Building REEF3D with ${JOBS} parallel job(s)..."
  patch_reef3d_makefile "${src_dir}"
  make -C "${src_dir}" clean >/dev/null 2>&1 || true

  # Default upstream target is release and uses LTO/march=native. If that fails, retry the non-LTO all target.
  if ! make -C "${src_dir}" -j "${JOBS}"; then
    warn "REEF3D release build failed. Retrying 'make all' without release LTO flags..."
    make -C "${src_dir}" clean >/dev/null 2>&1 || true
    make -C "${src_dir}" -j "${JOBS}" all
  fi

  if [[ ! -x "${src_dir}/bin/REEF3D" ]]; then
    err "REEF3D build finished but binary is missing: ${src_dir}/bin/REEF3D"
    exit 1
  fi
}

install_binaries() {
  local divemesh_src="$1"
  local reef3d_src="$2"

  log "Installing under ${PREFIX}..."
  mkdir -p "${PREFIX}/bin" "${PREFIX}/src" "$HOME/.local/bin"

  rsync_or_cp_dir "${divemesh_src}" "${PREFIX}/src/DIVEMesh"
  rsync_or_cp_dir "${reef3d_src}" "${PREFIX}/src/REEF3D"

  install -m 0755 "${divemesh_src}/bin/DiveMESH" "${PREFIX}/bin/DiveMESH"
  install -m 0755 "${reef3d_src}/bin/REEF3D" "${PREFIX}/bin/REEF3D"

  ln -sfn "${PREFIX}/bin/DiveMESH" "$HOME/.local/bin/DiveMESH"
  ln -sfn "${PREFIX}/bin/REEF3D" "$HOME/.local/bin/REEF3D"

  if [[ ":${PATH}:" != *":${HOME}/.local/bin:"* ]]; then
    warn "$HOME/.local/bin is not currently on PATH. Add this to ~/.bashrc or ~/.zshrc:"
    warn "export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
}

rsync_or_cp_dir() {
  local src="$1"
  local dst="$2"
  rm -rf "${dst}"
  mkdir -p "$(dirname "${dst}")"
  if require_cmd rsync; then
    rsync -a --delete "${src}/" "${dst}/"
  else
    cp -a "${src}" "${dst}"
  fi
}

smoke_test() {
  log "Running minimal binary checks..."
  "${PREFIX}/bin/DiveMESH" >/dev/null 2>&1 || true
  "${PREFIX}/bin/REEF3D" >/dev/null 2>&1 || true

  if require_cmd ldd; then
    if ldd "${PREFIX}/bin/REEF3D" | grep -q 'not found'; then
      err "REEF3D has unresolved shared-library dependencies:"
      ldd "${PREFIX}/bin/REEF3D" | grep 'not found' >&2 || true
      exit 1
    fi
    if ldd "${PREFIX}/bin/DiveMESH" | grep -q 'not found'; then
      err "DIVEMesh has unresolved shared-library dependencies:"
      ldd "${PREFIX}/bin/DiveMESH" | grep 'not found' >&2 || true
      exit 1
    fi
  fi
}

create_desktop_launcher() {
  local app_dir desktop_dir desktop_file desktop_copy cases_dir
  app_dir="$HOME/.local/share/applications"
  desktop_dir="$HOME/Desktop"
  desktop_file="${app_dir}/reef3d.desktop"
  desktop_copy="${desktop_dir}/reef3d.desktop"
  cases_dir="$HOME/reef3d-cases"

  mkdir -p "${app_dir}" "${cases_dir}"

  cat > "${desktop_file}" <<DESKTOP
[Desktop Entry]
Type=Application
Name=REEF3D Terminal
Comment=Open a terminal with REEF3D and DIVEMesh available on PATH
Exec=/bin/bash -lc 'export PATH="\$HOME/.local/bin:\$PATH"; mkdir -p "\$HOME/reef3d-cases"; cd "\$HOME/reef3d-cases"; echo "REEF3D: $(printf '%q' "${PREFIX}/bin/REEF3D")"; echo "DIVEMesh: $(printf '%q' "${PREFIX}/bin/DiveMESH")"; echo "Working directory: \$PWD"; echo; exec bash'
Terminal=true
Categories=Science;Education;Utility;
Keywords=REEF3D;DIVEMesh;CFD;Hydraulics;
DESKTOP

  chmod +x "${desktop_file}"

  if [[ -d "${desktop_dir}" ]]; then
    cp "${desktop_file}" "${desktop_copy}"
    chmod +x "${desktop_copy}"
  fi

  if require_cmd desktop-file-validate; then
    desktop-file-validate "${desktop_file}" || warn "desktop-file-validate reported issues; launcher may still work depending on desktop environment."
  fi

  if require_cmd update-desktop-database; then
    update-desktop-database "${app_dir}" >/dev/null 2>&1 || true
  fi

  log "Desktop launcher created: ${desktop_file}"
  [[ -f "${desktop_copy}" ]] && log "Desktop copy created: ${desktop_copy}"
}

prompt_desktop_launcher() {
  case "${CREATE_DESKTOP_ENV}" in
    1|yes|YES|y|Y|true|TRUE)
      create_desktop_launcher
      return
      ;;
    0|no|NO|n|N|false|FALSE)
      log "Skipping desktop launcher because REEF3D_CREATE_DESKTOP=${CREATE_DESKTOP_ENV}."
      return
      ;;
  esac

  if [[ -t 0 ]]; then
    local answer
    read -r -p "Create a desktop/menu launcher for REEF3D? [Y/n] " answer
    answer="${answer:-Y}"
    case "${answer}" in
      y|Y|yes|YES) create_desktop_launcher ;;
      *) log "Skipping desktop launcher." ;;
    esac
  else
    log "Non-interactive shell detected; skipping desktop launcher. Set REEF3D_CREATE_DESKTOP=1 to force creation."
  fi
}

print_summary() {
  local reef_tag divemesh_tag
  reef_tag="$(cat "${PREFIX}/src/REEF3D/.installed_from_release" 2>/dev/null || echo unknown)"
  divemesh_tag="$(cat "${PREFIX}/src/DIVEMesh/.installed_from_release" 2>/dev/null || echo unknown)"

  cat <<SUMMARY

Installation complete.

Installed versions/snapshots:
  REEF3D:   ${reef_tag}
  DIVEMesh: ${divemesh_tag}

Binaries:
  ${PREFIX}/bin/REEF3D
  ${PREFIX}/bin/DiveMESH

Convenience symlinks:
  $HOME/.local/bin/REEF3D
  $HOME/.local/bin/DiveMESH

Smoke check:
  ldd ${PREFIX}/bin/REEF3D
  ldd ${PREFIX}/bin/DiveMESH

For shell use, make sure this is in your ~/.bashrc or ~/.zshrc:
  export PATH="\$HOME/.local/bin:\$PATH"

SUMMARY
}

main() {
  detect_platform
  mkdir -p "${BUILD_ROOT}" "${PREFIX}"

  if [[ "${FORCE_REBUILD}" == "1" ]]; then
    log "Force rebuild enabled; clearing build directories."
    rm -rf "${BUILD_ROOT}/REEF3D" "${BUILD_ROOT}/DIVEMesh"
  fi

  ensure_dependencies

  local divemesh_src reef3d_src
  divemesh_src="${BUILD_ROOT}/DIVEMesh"
  reef3d_src="${BUILD_ROOT}/REEF3D"

  download_latest_release "${DIVEMESH_REPO}" "DIVEMesh" "${divemesh_src}"
  download_latest_release "${REEF3D_REPO}" "REEF3D" "${reef3d_src}"

  build_divemesh "${divemesh_src}"
  build_reef3d "${reef3d_src}"
  install_binaries "${divemesh_src}" "${reef3d_src}"
  smoke_test
  prompt_desktop_launcher
  print_summary
}

main "$@"
