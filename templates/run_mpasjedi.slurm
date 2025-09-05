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
    HOMErrfs="JEDIDIR"
    source /etc/profile.d/modules.sh
    module purge
    module use ${HOMErrfs}/modulefiles
    module load MODULE
    export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${HOMErrfs}/build/lib64
else
    source ROOTDIR/modules/MODULE
fi

nnode=NNODES
if (( NOPART % nnode == 0 )); then
    ncores=$(( NOPART/nnode ))
fi

task=TASKNAME
export OOPS_TRACE=0
export OMP_NUM_THREADS=1

ulimit -s unlimited

cd WRKDIR || exit $?

touch running.${task}
rm -rf error.${task} queue.getkf_${task}

sed -i -e "/config_pio_num_iotasks/s/=.*/= $nnode/g;/config_pio_stride/s/=.*/= $ncores/" namelist.atmosphere

RUNMPCMD -n NOPART EXEDIR/mpasjedi_enkf.x getkf.yaml log.out

istatus=$?
if [[ $istatus -eq 0 ]]; then

    case "${task}" in
    post )
        # rename ombg to oman for posterior observer jdiag files
        for jdiag in ./jdiag*; do
            jdiag_tmp="${jdiag%.nc}_tmp.nc"
            nccopy -k 3 "${jdiag}" "${jdiag_tmp}"
            ncrename -g ombg,oman "${jdiag_tmp}"
            mv "${jdiag_tmp}" "${jdiag}"
        done
        ;;
    solver )
        # ncks increments to cold_start IC
        var_list="VARLIST"
        for mem in $(seq -w 001 ENS_SIZE); do
            srun --ntasks=1 --cpus-per-task=1 -N 1 ncks -A -C -x -v ${var_list} "data/ens/mem${mem}.nc" "data/ana/mem${mem}.nc" &
            #istatus=$?
            #ncks -A -v ${var_list} "data/ana/mem${mem}.nc" "data/ens/tmp${mem}.nc"
            #[[ $istatus -ne 0 ]] && break
        done
        wait
        ;;
    esac

    if [[ $istatus -eq 0 ]]; then touch done.${task}; else touch error.${task}; fi
else
    touch error.${task}
fi

rm -rf running.${task}

time2=$(date '+%s')

diff=$((time2-time1))

printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" $time2 $(date -d@$diff -u +%H:%M:%S)
