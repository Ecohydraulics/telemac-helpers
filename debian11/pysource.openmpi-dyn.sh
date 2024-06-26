# This file is a template for a Linux environment file
# running "source pysource.openmpi.sh" will position all
# the necessary environment variables for telemac
# To adapt to your installation replace word <word> by their local value
###
### TELEMAC settings -----------------------------------------------------------
###
# Path to telemac root dir
export HOMETEL=/home/USER-NAME/telemac/v8p5
# Adding python scripts to PATH
export PATH=$HOMETEL/scripts/python3:.:$PATH
# Configuration file
export SYSTELCFG=$HOMETEL/configs/systel.cis-debian-dyn.cfg
# Name of the configuration to use
export USETELCFG=debgfopenmpidyn
# Path to this file
export SOURCEFILE=$HOMETEL/configs/pysource.openmpi-dyn.sh
### Python
# To force python to flush its output
export PYTHONUNBUFFERED='true'
### API
export PYTHONPATH=$HOMETEL/scripts/python3:$PYTHONPATH
export LD_LIBRARY_PATH=$HOMETEL/builds/$USETELCFG/wrap_api/lib:$LD_LIBRARY_PATH
export PYTHONPATH=$HOMETEL/builds/$USETELCFG/wrap_api/lib:$PYTHONPATH
###
### COMPILERS -----------------------------------------------------------
###
# Here are a few examples for external libraries
export SYSTEL=$HOMETEL/optionals
### MPI -----------------------------------------------------------
export MPIHOME=/usr/bin/mpif90.openmpi
export PATH=/usr/lib/x86_64-linux-gnu/openmpi:$PATH
export LD_LIBRARY_PATH=$PATH/lib:$LD_LIBRARY_PATH
###
### EXTERNAL LIBRARIES -----------------------------------------------------------
###
### Note: better use Q4TS QGIS plugin for MED file handling
### HDF5 -----------------------------------------------------------
# export HDF5HOME=$SYSTEL/hdf5
# export LD_LIBRARY_PATH=$HDF5HOME/lib:$LD_LIBRARY_PATH
# export LD_RUN_PATH=$HDF5HOME/lib:$MEDHOME/lib:$LD_RUN_PATH
### MED  -----------------------------------------------------------
# export MEDHOME=$SYSTEL/med-4.0.0
# export LD_LIBRARY_PATH=$MEDHOME/lib:$LD_LIBRARY_PATH
# export PATH=$MEDHOME/bin:$PATH
### MUMPS -------------------------------------------------------------
# export MUMPSHOME=$SYSTEL/Mumps-4100
# export SCALAPACKHOME=$SYSTEL/Scalapack-202
# export BLACSHOME=$SYSTEL/LIBRARY/blacs/gnu
###
### METIS -------------------------------------------------------------
export METISHOME=$SYSTEL/metis-5.1.1/build/
export LD_LIBRARY_PATH=$METISHOME/lib:$LD_LIBRARY_PATH
### AED ---------------------------------------------------------------
# export AEDHOME=$SYSTEL/Aed2-12
# export LD_LIBRARY_PATH=$AEDHOME/lib$LD_LIBRARY_PATH
#
