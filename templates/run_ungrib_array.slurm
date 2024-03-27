#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=1 CPUSPEC
#SBATCH -t 02:00:00
#SBATCH --output=WRKDIR/ungrib_%a_%j.log
ACCTSTR
EXCLSTR

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

if [[ "MACHINE" == "Jet" || "MACHINE" == "Hercules"  ]]; then
    module use ROOTDIR/modules
    module load MODULE
else
    source ROOTDIR/modules/MODULE
fi

mem=${SLURM_ARRAY_TASK_ID}
memstr=$(printf "%02d" $mem)

cd WRKDIR/ungrib_$memstr

touch running.ungrib_$memstr
rm -rf error.ungrib_$memstr 

RUNCMD -n 1 EXEDIR/ungrib.exe

if [[ $? -eq 0 ]]; then
    mv PREFIX${memstr}:* ..
    touch done.ungrib_$memstr
else
    touch error.ungrib_$memstr
fi

rm -rf running.ungrib_$memstr

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
