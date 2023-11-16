#!/bin/bash

export PATH=$PATH:/work/anthony.reinhart/MRMS/MRMS_20220214/bin
export W2_CONFIG_LOCATION=/work/anthony.reinhart/MRMS/MRMS_20220214/WDSS2/w2/w2config
export LD_LIBRARY_PATH=/usr/lib64:/usr/local/lib64

event=${1-20230512}
indir=/scratch/ywang/MPAS/mpas_scripts/run_dirs/OBS_SEQ/VEL/radar2
outdir=/scratch/ywang/MPAS/mpas_scripts/run_dirs/OBS_SEQ/VEL/WDSS2/${event}

#RUN STUFF
python runwdssii.py ${event} ${indir} ${outdir} ${outdir} K

sleep 1

#python runmerger.py ${event} ${indir} ${outdir}

exit 0
