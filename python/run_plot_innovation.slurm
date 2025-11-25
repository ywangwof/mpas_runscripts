#!/bin/bash
#SBATCH --partition=xjet,kjet
#SBATCH -J plot_innovation
#SBATCH --ntasks=1
#SBATCH -t 02:10:00
#SBATCH --output=./plot_innov_1800_%j.log
#SBATCH -A hpc-wof1

#set -eux

time1=$(date +%s)
printf "Job Started: %(%a %b %d %H:%M:%S %Z %Y)T. Job Id: %s\n\n" "$time1" "$SLURM_JOBID"

machine="Jet"
source /mnt/lfs5/NAGAPE/hpc-wof1/ywang/MPAS-WoFS/mpas_scripts.jedi/modules/env.python

run_dir="/lfs5/NAGAPE/hpc-wof1/ywang/MPAS-WoFS/run_dirs/"
eventdate="20220622"
run_case="dacycles_NCAR_gefs"
eventtime="0000"

python_file="/lfs5/NAGAPE/hpc-wof1/ywang/MPAS-WoFS/mpas_scripts.jedi/python/plot_mpaspatch.py"
patch_file="/lfs5/NAGAPE/hpc-wof1/ywang/MPAS-WoFS/run_dirs/20220622/gefs_taiwan.115133.patches"
fields=("theta" "qv" "refl10cm")

mem="020"
ana_file="${run_dir}/${eventdate}/${run_case}/${eventtime}/enkf/analysis.2022-06-23_00.00.00_en${mem}.nc"
ens_file="${run_dir}/${eventdate}/${run_case}/${eventtime}/enkf/mpas_en${mem}.nc"

for field in "${fields[@]}"; do
    python ${python_file} \
        -p ${patch_file} \
        -k 0-3 \
        --head "${run_case}_${field}" \
        ${ana_file} ${ens_file} "${field}"

    python ${python_file} \
        -p ${patch_file} \
        -k 0-3 \
        --head "${run_case}_ana_${field}" \
        ${ana_file} "${field}"

    python ${python_file} \
        -p ${patch_file} \
        -k 0-3 \
        --head "${run_case}_ens_${field}" \
        ${ens_file} "${field}"
done

time2=$(date '+%s')

diff=$((time2-time1))

printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" "$time2" "$(date -d@$diff -u +%H:%M:%S)"
