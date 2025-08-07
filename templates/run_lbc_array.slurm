#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/PREFIX_%a_%j.log
ACCTSTR
EXCLSTR


#set -eux

time1=$(date '+%s')
printf "Job Started: %(%a %b %d %H:%M:%S %Z %Y)T. Job Id: %s\n\n" $time1 $SLURM_JOBID

if [[ "MACHINE" == "Jet" || "MACHINE" == "Hercules"  ]]; then
    source /etc/profile.d/modules.sh
    module purge
    HOMErrfs="/lfs5/NAGAPE/hpc-wof1/ywang/GSL_JEDI/rrfs-workflow"
    module use ${HOMErrfs}/modulefiles
    module load "rrfs/jet.intel"

    #module use ROOTDIR/modules
    #module load MODULE
else
    source ROOTDIR/modules/MODULE
fi

ulimit -s unlimited

mem=${SLURM_ARRAY_TASK_ID}
memstr=$(printf "%02d" $mem)

cd WRKDIR/PREFIX_$memstr || exit $?

touch running.PREFIX_$memstr
rm -rf error.PREFIX_$memstr queue.PREFIX_$memstr

RUNMPCMD -n NOPART EXEDIR/init_atmosphere_model

if [[ $? -eq 0 ]]; then
    mv PREFIX_${memstr}.lbc.* ..
    touch done.PREFIX_$memstr
else
    touch error.PREFIX_$memstr
fi

rm -rf running.PREFIX_$memstr

time2=$(date '+%s')

diff=$((time2-time1))

printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" $time2 $(date -d@$diff -u +%H:%M:%S)
