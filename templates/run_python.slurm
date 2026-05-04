#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 04:30:00
#SBATCH --output=WRKDIR/JOBNAME_%j.log
ACCTSTR
EXCLSTR

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

machine=MACHINE
source ROOTDIR/modules/env.python

cd WRKDIR

touch running.JOBNAME
rm -rf error.JOBNAME queue.JOBNAME

export OMP_MAX_ACTIVE_LEVELS=1
export OMP_NUM_THREADS=1
export KMP_WARNINGS=0

# Better for multi-process/multi-threading jobs
export PYTHONUNBUFFERED=1

# Run the python programs
time PYTHONSCRIPT CONFIGFILE

estatus="$?"
if [[ $estatus -eq 0 ]]; then
    touch done.JOBNAME
elif [[ $estatus -eq 99 ]]; then
    touch missed.JOBNAME
else
    touch error.JOBNAME
fi

rm -rf running.JOBNAME

time2=$(date '+%s')

diff=$((time2-time1))

printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" "${time2}" "$(date -d@$diff -u +%H:%M:%S)"
