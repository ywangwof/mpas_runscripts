#!/bin/sh -l
#SBATCH -A wof
#SBATCH --partition=ujet,tjet,xjet,vjet,kjet
#SBATCH -J plot_theta
#SBATCH --ntasks=1 --ntasks-per-node=1
#SBATCH --exclusive
#SBATCH -t 00:30:00
#SBATCH --output=/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/runscriptv2.0/python/plot_theta_%j.log

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

source $HOME/.python
conda activate wofs_post

ulimit -s unlimited

cd /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/runscriptv2.0/python

#plot_mpaspatch_basemap.py -p wofs_small.271805.patches /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/run_dirs/2022101000_hrrr_small/fcst/wofs_small.history.2022-10-10_06.00.00.nc qv -l 1
plot_mpaspatch.py -p wofs_small.271805.patches /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/run_dirs/2022101000_hrrr_small/fcst/wofs_small.history.2022-10-10_06.00.00.nc qv -l 2

#if [[ $? -eq 0 ]]; then
#    touch done.plot_theta
#else
#    touch error.plot_theta
#fi

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
