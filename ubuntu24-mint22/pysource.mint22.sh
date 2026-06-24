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
