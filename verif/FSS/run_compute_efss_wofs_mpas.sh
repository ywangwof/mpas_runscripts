#!/bin/bash

source /home/brian.matilla/miniconda3/etc/profile.d/conda.sh
conda activate /home/brian.matilla/miniconda3/envs/wofs-post-2023

umask 002
date

python wrapper_compute_efss_wofs_mpas_2024.py
python wrapper_compute_efss_wofs_2024.py

echo "Compute eFSS is complete."
date
exit 0
