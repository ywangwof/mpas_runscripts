#!/bin/sh -l
#SBATCH -A wof
#SBATCH --partition=ujet,tjet,xjet,vjet,kjet
#SBATCH -J get_patches
#SBATCH --ntasks=12 --ntasks-per-node=6
#SBATCH --exclusive
#SBATCH -t 00:30:00
#SBATCH --output=/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/runscriptv2.0/python/get_patches_%j.log

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

source $HOME/.python
conda activate wofs_post

ulimit -s unlimited

cd /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/runscriptv2.0/python

get_mpaspatches.py -n 12 /lfs1/NAGAPE/wof/MPAS/run_dirs/2022101400_hrrr/fcst/wofs_mpas.history.2022-10-14_01.00.00.nc

#if [[ $? -eq 0 ]]; then
#    touch done.get_patches
#else
#    touch error.get_patches
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
