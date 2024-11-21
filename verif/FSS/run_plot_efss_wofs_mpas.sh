#!/bin/bash

source /home/derek.stratman/miniconda3/etc/profile.d/conda.sh
conda activate verif_py
umask 002
date

script_dir=$(pwd)

#
# Copy files to year directory
#
#cd /scratch/ywang/MPAS/intel/run_dirs/VERIF/FSS/cb-wofs || exit 0
#mkdir -p 2024
#cd 2024 || exit 0
#ln -sf ../20240*/*/wofs*5min*nc .
#
#cd /scratch/ywang/MPAS/intel/run_dirs/VERIF/FSS/mpas-wofs || exit 0
#mkdir -p 2024
#cd 2024 || exit 0
#ln -sf ../20240*/*/wofs*5min*nc .


cd ${script_dir}  || exit 0

python plot_efss_wofs_mpas.py -w /scratch/ywang/MPAS/intel/run_dirs/VERIF/FSS/cb-wofs/ -r /scratch/ywang/MPAS/intel/run_dirs/VERIF/FSS/mpas-wofs/ -o /scratch/ywang/MPAS/intel/run_dirs/VERIF/FSS/

exit 0
