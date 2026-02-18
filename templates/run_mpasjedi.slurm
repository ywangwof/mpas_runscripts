#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/jedi_TASKNAME_%j.log
ACCTSTR
EXCLSTR

#set -eux

time1=$(date '+%s')
printf "Job Started: %(%a %b %d %H:%M:%S %Z %Y)T. Job Id: %s\n\n" $time1 $SLURM_JOBID

if [[ "MACHINE" == "Jet" || "MACHINE" == "Hercules" || "MACHINE" == "Ursa" ]]; then
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
rm -rf error.${task} queue.jedi_${task}

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
        # Take background file, look for every variable except those listed in ${var_list},
        # and append them into the analysis file.
        # -A	Append	Instead of overwriting the output file, this tells NCO to add the variables to the existing file.
        # -C	No Clobber (Don't Copy)	This tells ncks to not copy the associated coordinate variables (like latitude, longitude, time)
        #       if they already exist in the destination file. This prevents errors when appending variables to a file
        #       that already has the same grid dimensions.
        # -x	Exclude	This inverts the selection. Instead of saying "select these variables," it says "select everything except these variables."
        # -v	Variable	Specifies the variables to operate on.
        #
        if [[ CYCLENO -eq 0 ]]; then
            echo "Running ncks for cycle = CYCLENO to combine increments to the original background file ..."
            var_list="VARLIST"
            declare -a pids=()
            for mem in $(seq -w 001 ENS_SIZE); do
                srun --ntasks=1 --exclusive ncks -A -C -x -v ${var_list} "ens/mem${mem}.nc" "ana/mem${mem}.nc" &
                pids+=($!)
            done

            icount=0; ierr=0
            # Wait for all and check status
            for pid in "${pids[@]}"; do
                wait "$pid";
                if [ $? -eq 0 ]; then
                    #echo "PID $pid exited successfully"
                    ((icount+=1))
                else
                    #echo "PID $pid failed"
                    ((ierr+=1))
                fi
            done

            if [ "$icount" -eq ENS_SIZE ]; then
                sleep 10   # file system may be slower than the job status in memory
                istatus=0
            else
                istatus=1
            fi
        else
            echo "Skip ncks for cycle = CYCLENO to use mpasout files ..."
        fi
        ;;
    esac

    if [[ $istatus -eq 0 ]]; then
        touch done.${task}
    else
        touch error.${task}
    fi
else
    touch error.${task}
fi

rm -rf running.${task}

time2=$(date '+%s')

diff=$((time2-time1))

printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" $time2 $(date -d@$diff -u +%H:%M:%S)
