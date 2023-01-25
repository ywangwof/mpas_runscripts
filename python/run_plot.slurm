#!/bin/sh -l
#SBATCH -A wof
#SBATCH --partition=ujet,xjet,vjet,kjet
#SBATCH -J plot_mpas
#SBATCH --ntasks=1 --ntasks-per-node=1 --mem=64000
#SBATCH --exclusive
#SBATCH -t 02:30:00
#SBATCH --output=/lfs1/NAGAPE/wof/MPAS/run_dirs/2022110400_hrrr/plot_mpas_%j.log

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

source $HOME/.python
conda activate wofs_post

ulimit -s unlimited

cd /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/mpas_scripts/python

file="diag"
datestr="2022-11-04"
times=(00 01 02 03)
cases=(fcst fcst.nohyb)
fields=(refl10cm_max refl10cm_1km)
fcst_dir="/lfs1/NAGAPE/wof/MPAS/run_dirs/2022110400_hrrr"

for nt in ${times[@]}; do
    for case in ${cases[@]}; do
        for field in ${fields[@]}; do
            # 2D
            plot_mpaspatch.py -p wofs_mpas.1894063.patches -o ${fcst_dir}/${case}/${field}_${nt}.png ${fcst_dir}/${case}/wofs_mpas.${file}.${datestr}_${nt}.00.00.nc ${field}         # 2D
            # 3D
            #plot_mpaspatch.py -p wofs_mpas.1894063.patches -o ${fcst_dir}/${case}/${field}Max_${nt}.png ${fcst_dir}/${case}/wofs_mpas.${file}.${datestr}_${nt}.00.00.nc ${field} -l max   # 3D
            # init
            #plot_mpaspatch.py -p wofs_mpas.1894063.patches -o ${fcst_dir}/${case}/init_${field}Max_${nt}.png ${fcst_dir}/${case}/wofs_mpas.${file}.nc ${field} -l max   # 3D
        done
    done
done

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
