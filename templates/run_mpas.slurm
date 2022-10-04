#!/bin/sh -l
#SBATCH -A ACCOUNT
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART --ntasks-per-node=6
#SBATCH --exclusive
#SBATCH -t 06:30:00
#SBATCH --output=WRKDIR/mpas_%j.log

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

module use ROOTDIR/modules
module load build_jet_intelTed

ulimit -s unlimited

cd WRKDIR

ncores=6
#nnode=$(( NOPART/$SLURM_CPUS_ON_NODE ))
#nnode=$SLURM_JOB_NUM_NODES
nnode=$(( NOPART/ncores ))

sed -i "s/NNNODE/$nnode/;s/NNCORE/$ncores/;" namelist.atmosphere

srun -n NOPART EXEDIR/atmosphere_model.single

#if [[ $? -eq 0 ]]; then
#    touch done.mpas
#else
#    touch error.mpas
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
