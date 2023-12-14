#!/bin/sh -l
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=1 --cpus-per-task=12
#SBATCH -t 02:00:00
#SBATCH --output=WRKDIR/ungrib_%j.log
ACCTSTR
EXCLSTR

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

cd WRKDIR

touch running.ungrib
rm -rf error.ungrib queue.ungrib

RUNCMD -n 1 EXEDIR/ungrib.exe

if [[ $? -eq 0 ]]; then
    touch done.ungrib
else
    touch error.ungrib
fi

rm -rf running.ungrib

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
