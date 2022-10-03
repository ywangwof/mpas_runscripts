#!/bin/sh -l
#SBATCH -A ACCOUNT
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=1 --cpus-per-task=12
#SBATCH --exclusive
#SBATCH -t 00:40:00
#SBATCH --output=WRKDIR/ungrib_%j.log

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

cd WRKDIR

touch ungrib.running
rm -rf error.ungrib queue.ungrib

srun -n 1 EXEDIR/ungrib.exe

if [[ $? -eq 0 ]]; then
    touch done.ungrib
else
    touch error.ungrib
fi

rm -rf ungrib.running

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
