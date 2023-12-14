#!/bin/bash -l
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/update_bc_%a_%j.log
ACCTSTR
EXCLSTR


#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

if [[ "MACHINE" == "Jet" ]]; then
    source /etc/profile.d/modules.sh
    module purge
    module use ROOTDIR/modules
    module load MODULE
else
    source ROOTDIR/modules/MODULE
fi

ulimit -s unlimited

mem=${SLURM_ARRAY_TASK_ID}
memstr=$(printf "%02d" $mem)

cd WRKDIR/fcst_${memstr}

touch running.update_bc_${memstr}
rm -rf error.update_bc_${memstr} queue.update_bc_${memstr}

RUNMPCMD -n NOPART EXEDIR/update_bc

if [[ $? -eq 0 ]]; then
    touch done.update_bc_${memstr}
else
    touch error.update_bc_${memstr}
fi

rm -rf running.update_bc_${memstr}

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
