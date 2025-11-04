#!/usr/bin/env bash
# TELEMAC environment for Linux Mint 22 (Ubuntu 24.04 base) with MPI/HDF5/METIS/MED/MUMPS/ScaLAPACK

# Resolve this script's directory and HOMETEL from it so it works no matter where you cloned TELEMAC
# Expected layout: ~/opt/telemac/{configs, scripts, sources, ...}
_THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMETEL="$(cd "${_THIS_DIR}/.." && pwd)"
export SOURCEFILE="${_THIS_DIR}"

# Configuration file and config name used by telemac.py
# Adjust USETELCFG to match a section present in your systel.mint22.cfg
export SYSTELCFG="${HOMETEL}/configs/systel.mint22.cfg"
export USETELCFG="hyinfompiubu"

# Make TELEMAC Python utilities available
# (Both python3 helpers and legacy unix scripts are often useful)
if [ -d "${HOMETEL}/scripts/python3" ]; then
  export PATH="${HOMETEL}/scripts/python3:${PATH}"
fi
if [ -d "${HOMETEL}/scripts/unix" ]; then
  export PATH="${HOMETEL}/scripts/unix:${PATH}"
fi

# Compilers and MPI (OpenMPI from APT)
export MPI_ROOT="/usr"
export CC="mpicc"
export FC="mpifort"
export MPIRUN="mpirun"

# Library/include roots from Ubuntu 24.04 packages
# OpenMPI libraries
_OMPI_LIB="/usr/lib/x86_64-linux-gnu/openmpi/lib"
_OMPI_INC="/usr/lib/x86_64-linux-gnu/openmpi/include"

# HDF5 (serial headers via libhdf5-dev; libs in the multiarch lib dir)
# If you later install parallel HDF5 (libhdf5-openmpi-dev), set _HDF5_INC="$_OMPI_INC"
_HDF5_INC="/usr/include/hdf5/openmpi/"
_HDF5_LIB="/usr/lib/x86_64-linux-gnu/hdf5/openmpi"

# MED (optional - not actively used in the corrent setup)
_MED_INC="/usr/include/med"
_MED_LIB="/usr/lib/x86_64-linux-gnu"

# METIS
_METIS_INC="/usr/include"
_METIS_LIB="/usr/lib/x86_64-linux-gnu"

# MUMPS (both seq and mpi dev packages provide headers+libs under multiarch dir)
_MUMPS_INC="/usr/include"
_MUMPS_LIB="/usr/lib/x86_64-linux-gnu"

# ScaLAPACK (OpenMPI build)
_SCALAPACK_LIB="/usr/lib/x86_64-linux-gnu"

# Expose common hints some TELEMAC configs look for (non-fatal if unused)
export MPI_INCLUDE="${_OMPI_INC}"
export MPI_LIBDIR="${_OMPI_LIB}"

export HDF5_ROOT="/usr"
export HDF5_INCLUDE_PATH="${_HDF5_INC}"
export HDF5_LIBDIR="${_HDF5_LIB}"

export MED_ROOT="$HOME/opt/salome/BINARIES-UB24.04/medfile/"
export MED_INCLUDE_PATH="$HOME/opt/salome/BINARIES-UB24.04/medfile/include"
export MED_LIBDIR="$HOME/opt/salome/BINARIES-UB24.04/medfile/lib"

export METIS_ROOT="/usr"
export METIS_INCLUDE_PATH="${_METIS_INC}"
export METIS_LIBDIR="${_METIS_LIB}"

export MUMPS_ROOT="/usr"
export MUMPS_INCLUDE_PATH="${_MUMPS_INC}"
export MUMPS_LIBDIR="${_MUMPS_LIB}"

export SCALAPACK_LIBDIR="${_SCALAPACK_LIB}"

# Build and wrapped API locations (created after you compile)
# Keep these early in the path so Python can import the TELEMAC modules and extensions
if [ -d "${HOMETEL}/builds/${USETELCFG}/wrap_api/lib" ]; then
  export PYTHONPATH="${HOMETEL}/builds/${USETELCFG}/wrap_api/lib:${PYTHONPATH}"
fi

# TELEMAC Python helpers
if [ -d "${HOMETEL}/scripts/python3" ]; then
  export PYTHONPATH="${HOMETEL}/scripts/python3:${PYTHONPATH}"
fi

# Runtime search paths
# Put OpenMPI first to avoid picking up non-MPI BLAS/LAPACK accidentally
# The standard multiarch directory is added as a safety net
for _libdir in \
  "${_OMPI_LIB}" \
  "${_MED_LIB}" \
  "${_METIS_LIB}" \
  "${_MUMPS_LIB}" \
  "${_SCALAPACK_LIB}" \
  "/usr/lib/x86_64-linux-gnu"
do
  case ":${LD_LIBRARY_PATH}:" in
    *:"${_libdir}":*) ;;
    *) export LD_LIBRARY_PATH="${_libdir}:${LD_LIBRARY_PATH}";;
  esac
done

# Add include directories to CPATH so builds find headers without extra flags
for _incdir in \
  "${_OMPI_INC}" \
  "${_HDF5_INC}" \
  "${_MED_INC}" \
  "${_METIS_INC}" \
  "${_MUMPS_INC}"
do
  case ":${CPATH}:" in
    *:"${_incdir}":*) ;;
    *) export CPATH="${_incdir}:${CPATH}";;
  esac
done

# Convenience: print a one-line summary so you know which config is active
echo "TELEMAC set: HOMETEL='${HOMETEL}', SYSTELCFG='${SYSTELCFG}', USETELCFG='${USETELCFG}'"

# Make Python unbuffered for clearer build logs
export PYTHONUNBUFFERED="1"
