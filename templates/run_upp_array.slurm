#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -q batch
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 00:05:00
#SBATCH --output=WRKDIR/uppHHMINSTR_%a_%j.log
ACCTSTR
#SBATCH -D .
#...Automatically change the directory to where
#   the job was launched
#

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

if [[ "MACHINE" == "Jet" || "MACHINE" == "Hercules"  ]]; then
    # shellcheck source=/dev/null # to ignore source path error
    source /etc/profile.d/modules.sh
    module purge
    module use ROOTDIR/modules
    module load MODULE
    module load wgrib2/2.0.8
else
    # shellcheck source=/dev/null # to ignore source path error
    source ROOTDIR/modules/MODULE
fi
module list

ulimit -s unlimited

mem=${SLURM_ARRAY_TASK_ID}
memstr=$(printf "%02d" $mem)

wrkdir=WRKDIR/mem$memstr/post_HHMINSTR
cd $wrkdir

rm -rf ../error.uppHHMINSTR_${memstr} ../queue.uppHHMINSTR_${memstr}

touch ../running.uppHHMINSTR_${memstr}

rm -rf fort.* core.*

RUNMPCMD EXEDIR/unipost.exe

if [[ $? -eq 0 ]]; then

    mv WRFPRS.GrbFUPPDATE ../MPAS-A_EVENTDATEfHHMINSTR.grib2

    touch ../done.uppHHMINSTR_${memstr}
else
    touch ../error.uppHHMINSTR_${memstr}
fi

rm -rf ../running.uppHHMINSTR_${memstr}

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "

