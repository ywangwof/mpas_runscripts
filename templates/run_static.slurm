#!/bin/sh -l
#SBATCH -A ACCOUNT
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=1 --cpus-per-task=12
#SBATCH --exclusive
#SBATCH -t 02:30:00
#SBATCH --output=WRKDIR/static_%j.log

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

module use /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/modules
module load build_jet_intel

ulimit -s unlimited

cd WRKDIR

srun -n 1 EXEDIR/init_atmosphere_model

if [[ $? -eq 0 ]]; then
    touch done.static
else
    touch error.static
fi

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
