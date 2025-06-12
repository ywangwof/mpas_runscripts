#!/bin/bash

source /home/brian.matilla/miniconda3/etc/profile.d/conda.sh
conda activate /home/brian.matilla/miniconda3/envs/wofs-post-2023

umask 002
date

python histogram_dz_wrapper_mrms.py
python histogram_dz_wrapper_wofs.py
python histogram_dz_wrapper_mpas.py

python histogram_plotter_dz.py -d /scratch/wofs_mpas/run_dirs/VERIF/wofs_hist \
                               -e /scratch/wofs_mpas/run_dirs/VERIF/mpas_hist \
                               -f /scratch/wofs_mpas/run_dirs/VERIF/mrms_hist \
                               -o /scratch/wofs_mpas/run_dirs/VERIF/ -p wofs_mpas

echo "Histogram done."

date

exit 0
