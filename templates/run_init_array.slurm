#!/bin/sh -l
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/init_%a_%j.log
ACCTSTR
EXCLSTR

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

if [[ "MACHINE" == "Jet" || "MACHINE" == "Hercules"  ]]; then
    source /etc/profile.d/modules.sh
    module purge
    module use ROOTDIR/modules
    module load MODULE
#else
#    source ROOTDIR/modules/MODULE
fi

ulimit -s unlimited

mem=${SLURM_ARRAY_TASK_ID}
memstr=$(printf "%02d" $mem)

cd WRKDIR/init_$memstr

touch init.running_$memstr
rm -rf error.init_$memstr queue.init_$memstr 

RUNMPCMD -n NOPART EXEDIR/init_atmosphere_model

if [[ $? -eq 0 ]]; then
    mv PREFIX_${memstr}.init.nc ..
    touch done.init_$memstr
else
    touch error.init_$memstr
fi

rm -rf init.running_$memstr

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
