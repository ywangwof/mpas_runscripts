#!/bin/sh -l
#SBATCH -A ACCOUNT
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART
#SBATCH --exclusive
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/init_%j.log

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

module use /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/modules
module load build_jet_intel

ulimit -s unlimited

cd WRKDIR

srun -n NOPART EXEDIR/init_atmosphere_model

if [[ $? -eq 0 ]]; then
    touch done.ics
else
    touch error.ics
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
