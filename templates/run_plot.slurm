#!/bin/bash
#SBATCH -A hpc-wof1
#SBATCH --partition=sjet,vjet,xjet,kjet
#SBATCH -J plot
#SBATCH --ntasks=1 --cpus-per-task=12
#SBATCH --exclusive
#SBATCH -t 02:30:00
#SBATCH -o /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/mesh_3km/plot_%j.out
#SBATCH -e /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/mesh_3km/plot_%j.err

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

module load ncl

RUNDIR='/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/mesh_3km'

cd $RUNDIR

export FNAME=wofs.grid.nc

srun -n 1 ncl mpas-a_mesh.ncl

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
