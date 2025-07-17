#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/static_%j.log
ACCTSTR
EXCLSTR

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

if [[ "MACHINE" == "Jet" ]]; then
    module purge
    module use ROOTDIR/modules
    module load MODULE
else
    source ROOTDIR/modules/MODULE
fi

ulimit -s unlimited

cd WRKDIR

rm -f queue.static error.static

touch running.static

RUNMPCMD -n NOPART EXEDIR/init_atmosphere_model

if [[ $? -eq 0 ]]; then
    module load nco
    mv DOMNAME.static.nc static_badLAI.nc
    ncap2 -O -s 'lai12m = 0.1f*lai12m' static_badLAI.nc DOMNAME.static.nc
    touch done.static
else
    touch error.static
fi

rm -f running.static

time2=$(date '+%s')

diff=$((time2-time1))
printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" $time2 $(date -d@$diff -u +%H:%M:%S)

exit 0
