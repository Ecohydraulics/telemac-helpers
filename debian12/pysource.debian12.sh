#!/usr/bin/env bash
# TELEMAC environment for Debian 12 with MPI/HDF5/MED/METIS/MUMPS/ScaLAPACK
# Assumes all optional dependencies are installed from from apt on Debian 12
# Only SALOME is user-installed

# Resolve script directory and HOMETEL from it
_THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMETEL="$(cd "${_THIS_DIR}/.." && pwd)"
export SOURCEFILE="${_THIS_DIR}"

# Configuration file and config name used by telemac.py
# Adjust USETELCFG to match a section present in configs/systel.debian12.cfg
export SYSTELCFG="${HOMETEL}/configs/systel.debian12.cfg"
export USETELCFG="hyinfompideb12"

# Make TELEMAC Python utilities available
if [ -d "${HOMETEL}/scripts/python3" ]; then
    case ":${PATH}:" in *:"${HOMETEL}/scripts/python3":*) ;; *) export PATH="${HOMETEL}/scripts/python3:${PATH}";; esac
fi
if [ -d "${HOMETEL}/scripts/unix" ]; then
  case ":${PATH}:" in *:"${HOMETEL}/scripts/unix":*) ;; *) export PATH="${HOMETEL}/scripts/unix:${PATH}";; esac
fi

# Detect Debian multiarch lib directory and common include roots
_arch="$(gcc -dumpmachine 2>/dev/null || echo x86_64-linux-gnu)"
_archlib="/usr/lib/${_arch}"

# Helper to pick the first existing directory
_first_dir() {
  for _d in "$@"; do
    [ -d "$_d" ] && { printf '%s' "$_d"; return 0; }
  done
  return 1
}

# MPI. Prefer OpenMPI wrappers if present
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

# HDF5 parallel. Debian installs OpenMPI-flavored headers in /usr/include/hdf5/openmpi
_HDF5_INC="$(_first_dir \
  "/usr/include/hdf5/openmpi" \
  "/usr/include/hdf5/serial")"
_HDF5_LIB="$(_first_dir \
  "${_archlib}/hdf5/openmpi" \
  "${_archlib}/hdf5/serial" \
  "${_archlib}")"

# MED-fichier
export _MED_ROOT="$HOME/opt/salome/BINARIES-DB12/medfile/"
export _MED_INC="$HOME/opt/salome/BINARIES-DB12/medfile/include"
export _MED_LIB="$HOME/opt/salome/BINARIES-DB12/medfile/lib"

# METIS and ParMETIS
_METIS_INC="$(_first_dir "/usr/include")"
_METIS_LIB="$(_first_dir "${_archlib}")"
_PARMETIS_INC="$(_first_dir "/usr/include")"
_PARMETIS_LIB="$(_first_dir "${_archlib}")"

# MUMPS and ScaLAPACK
_MUMPS_INC="$(_first_dir "/usr/include/mumps" "/usr/include")"
_MUMPS_LIB="$(_first_dir "${_archlib}")"
_SCALAPACK_LIB="$(_first_dir "${_archlib}")"

# Add useful binaries to PATH
for _bindir in \
  "${_MPI_BIN}" \
  "/usr/bin"
do
  case ":${PATH}:" in *:"${_bindir}":*) ;; *) export PATH="${_bindir}:${PATH}";; esac
done

# Library search path
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
  case ":${LD_LIBRARY_PATH}:" in *:"${_libdir}":*) ;; *) export LD_LIBRARY_PATH="${_libdir}:${LD_LIBRARY_PATH}";; esac
done

# Include search path for some build helpers that honor CPATH
for _incdir in \
  "${_MPI_INC}" \
  "${_HDF5_INC}" \
  "${_MED_INC}" \
  "${_METIS_INC}" \
  "${_PARMETIS_INC}" \
  "${_MUMPS_INC}"
do
  [ -n "${_incdir}" ] || continue
  case ":${CPATH}:" in *:"${_incdir}":*) ;; *) export CPATH="${_incdir}:${CPATH}";; esac
done

# Convenience: print a one-line summary
echo "TELEMAC set: HOMETEL='${HOMETEL}', SYSTELCFG='${SYSTELCFG}', USETELCFG='${USETELCFG}'"
echo "MPI bin='${_MPI_BIN}', MPI inc='${_MPI_INC}', MPI lib='${_MPI_LIB}'"
echo "HDF5 inc='${_HDF5_INC}', HDF5 lib='${_HDF5_LIB}'"
echo "MED inc='${_MED_INC}', MED lib='${_MED_LIB}'"

# Unbuffered Python for clearer build logs
export PYTHONUNBUFFERED="1"
