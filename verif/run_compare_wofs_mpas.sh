#!/bin/bash

micromamba activate myenv

umask 002
date

# MRMS Percentile  cb-WoFS mpas-WoFS
# ----- ---------- -------- ---------
# 37.00      91.65    42.00    40.80
# 40.00      94.78    45.40    44.60
# 42.00      96.19    47.80    47.00
# 43.00      96.74    49.00    48.20
# 45.00      97.66    51.40    50.20
# 47.00      98.41    53.80    52.20
# 48.00      98.73    55.00    53.40

script_dir=/scratch/ywang/MPAS/intel/mpas_scripts/verif
work_dir=/scratch/ywang/MPAS/intel/run_dirs/VERIF

cd ${script_dir} || exit 0

####################

echo "Run cb-WoFS object generation ..."

wofs_obj_match_wrapper_MPAS.py /scratch/derek.stratman/wofs_verif/SummaryFiles/2024 -o ${work_dir}/cb-wofs -a 45.40 -b 51.40

#echo "Run cb-WoFS verification plotting ..."
#wofs_obj_verif_plotter_MPAS.py /scratch/ywang/MPAS/intel/run_dirs/VERIF/cb-wofs -o /scratch/ywang/MPAS/intel/run_dirs/VERIF/cb-wofs -p cb-wofs

####################

echo "Run MPAS-WoFS object generation ..."

wofs_obj_match_wrapper_MPAS.py /scratch/ywang/MPAS/intel/run_dirs/summary_files -o ${work_dir}/mpas-wofs -a 44.60 -b 50.20

#echo "Run MPAS-WoFS verification plotting ..."
#wofs_obj_verif_plotter_MPAS.py /scratch/ywang/MPAS/intel/run_dirs/VERIF/mpas-wofs -o /scratch/ywang/MPAS/intel/run_dirs/VERIF/mpas-wofs -p mpas-wofs

####################

echo "Run MPAS-WoFS verification plotting ..."
plot_compare_obj.py -p wofs_mpas_2024_40-45 ${work_dir}/cb-wofs  ${work_dir}/mpas-wofs -o ${work_dir}

date
exit 0
