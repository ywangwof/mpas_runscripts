#!/bin/bash
#SBATCH -A ACCOUNT
#SBATCH --partition=PARTION
#SBATCH -q batch
#SBATCH -J JOBNAME
#SBATCH -n NOPART
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/upp_HHHSTR_%j.log
#SBATCH -D .
#...Automatically change the directory to where
#   the job was launched
#

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

module purge
module use ROOTDIR/modules
module load build_jet_intel22

module list

ulimit -s unlimited

wrkdir=WRKDIR
cd $wrkdir

rm -rf ../error.upp_HHHSTR ../queue.upp_HHHSTR

touch ../running.upp_HHHSTR

rm -rf fort.*

srun EXEDIR/unipost.exe

if [[ $? -eq 0 ]]; then
    touch ../done.upp_HHHSTR
    dtstr=(${wrkdir//\// })
    mv WRFPRS.GrbFHHHSTR ../MPAS-A_${dtstr[-3]}fHHHSTR.grib2
else
    touch ../error.upp_HHHSTR
fi

rm -rf ../running.upp_HHHSTR

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "

