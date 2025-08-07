#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/getkf_TASKNAME_%j.log
ACCTSTR
EXCLSTR


#set -eux

time1=$(date '+%s')
printf "Job Started: %(%a %b %d %H:%M:%S %Z %Y)T. Job Id: %s\n\n" $time1 $SLURM_JOBID

if [[ "MACHINE" == "Jet" || "MACHINE" == "Hercules"  ]]; then
    HOMErrfs="/lfs5/NAGAPE/hpc-wof1/ywang/GSL_JEDI/rrfs-workflow"
    source /etc/profile.d/modules.sh
    module purge
    module use ${HOMErrfs}/sorc/RDASApp/modulefiles
    module load RDAS/jet.intel
    export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${HOMErrfs}/sorc/RDASApp/build/lib64
else
    source ROOTDIR/modules/MODULE
fi

task=TASKNAME
export OOPS_TRACE=1
export OMP_NUM_THREADS=1

ulimit -s unlimited

cd WRKDIR || exit $?

touch running.${task}
rm -rf error.${task} queue.${task}

RUNMPCMD -n NOPART EXEDIR/mpasjedi_enkf.x getkf.yaml log.out

if [[ $? -eq 0 ]]; then
    # rename ombg to oman for posterior observer jdiag files
    if [[ "${task}" == "post" ]]; then
        for jdiag in ./jdiag*; do
            jdiag_tmp="${jdiag%.nc}_tmp.nc"
            nccopy -k 3 "${jdiag}" "${jdiag_tmp}"
            ncrename -g ombg,oman "${jdiag_tmp}"
            mv "${jdiag_tmp}" "${jdiag}"
        done
    fi

    touch done.${task}
else
    touch error.${task}
fi

rm -rf running.${task}

time2=$(date '+%s')

diff=$((time2-time1))

printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" $time2 $(date -d@$diff -u +%H:%M:%S)
