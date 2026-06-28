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
