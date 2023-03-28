#!/bin/sh -l
#SBATCH -A ACCOUNT
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH --exclusive
#SBATCH -t 01:30:00
#SBATCH --output=WRKDIR/lbc_%j.log


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

cd WRKDIR

touch lbc.running
rm -rf error.lbc queue.lbc

srun -n NOPART EXEDIR/init_atmosphere_model

if [[ $? -eq 0 ]]; then
    touch done.lbc
else
    touch error.lbc
fi

rm -rf lbc.running

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
