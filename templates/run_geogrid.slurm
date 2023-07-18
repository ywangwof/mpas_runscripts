#!/bin/sh -l
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/geogrid_%j.log
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
rm -f queue.geogrid error.geogrid

touch running.geogrid

RUNMPCMD -n NOPART EXEDIR/geogrid.exe

if [[ $? -eq 0 ]]; then
    touch done.geogrid
else
    touch error.geogrid
fi

rm -f running.geogrid

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
