#!/bin/sh -l
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/mpassitHHMINSTR_%a_%j.log
ACCTSTR
EXCLSTR

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

if [[ "MACHINE" == "Jet" ]]; then
    module use ROOTDIR/modules
    module load build_jet_intel

else
    source /scratch/ywang/MPAS/env.mpas
fi

ulimit -s unlimited

mem=${SLURM_ARRAY_TASK_ID}
memstr=$(printf "%02d" $mem)

cd WRKDIR/mem${memstr}

rm -rf error.mpassitHHMINSTR_${memstr} queue.mpassitHHMINSTR_${memstr}

touch running.mpassitHHMINSTR_${memstr}

RUNMPCMD -n NOPART EXEDIR/mpassit namelist.fcst_HHMINSTR

if [[ $? -eq 0 ]]; then
    touch done.mpassitHHMINSTR_${memstr}
else
    touch error.mpassitHHMINSTR_${memstr}
fi

rm -rf running.mpassitHHMINSTR_${memstr}

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
