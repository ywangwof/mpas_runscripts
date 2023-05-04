#!/bin/sh -l
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/mpassit_HHHSTR_%j.log
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

cd WRKDIR

rm -rf error.mpassitHHHSTR queue.mpassitHHHSTR

touch running.mpassitHHHSTR

RUNMPCMD -n NOPART EXEDIR/mpassit namelist.fcst_HHHSTR

if [[ $? -eq 0 ]]; then
    touch done.mpassitHHHSTR
else
    touch error.mpassitHHHSTR
fi

rm -rf running.mpassitHHHSTR

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
