#!/bin/bash
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
    module purge
    module reset
    module use /lfs5/NAGAPE/hpc-wof1/ywang/MPAS/MPASSIT.vecna/modulefiles
    module load build.jet.intel

else
    source ROOTDIR/modules/MODULE
fi

ulimit -s unlimited

cd WRKDIR || exit $?

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

diff=$((time2-time1))
printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" $time2 $(date -d@$diff -u +%H:%M:%S)

exit 0
