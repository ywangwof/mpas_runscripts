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

# parallel_copy_verify DEST MAX_THREADS FILE1 FILE2 ...
# Copies files to DEST in parallel, verifies via metadata, retries failures, then exits on mismatch.
parallel_copy_verify() {
    local DEST="$1"
    local MAX_THREADS="$2"
    shift 2
    local FILES=("$@")
    local FILE_COUNT=${#FILES[@]}
    local VERBOSE=true

    log_msg() { [[ "$VERBOSE" == true ]] && echo -e "$1"; }

    # --- Pre-check: Detect Filename Collisions ---
    local DUPLICATES
    DUPLICATES=$(printf "%s\n" "${FILES[@]}" | xargs -n 1 basename | sort | uniq -d)
    if [[ -n "$DUPLICATES" ]]; then
        echo -e "❌ ERROR: Duplicate filenames detected! Flattening will cause overwrites:"
        echo -e "$DUPLICATES"
        exit 1
    fi

    # --- Phase 1: Parallel Copy (Bash Backgrounding) ---
    log_msg "--- Phase 1: Parallel Copy (Backgrounding) ---"

    local job_count=0
    local FILE
    for FILE in "${FILES[@]}"; do
        cp -Lp "$FILE" "$DEST/" &
        ((job_count++))
        if (( job_count % MAX_THREADS == 0 )); then
            wait
        fi
    done
    wait # Ensure all remaining background copies finish before Phase 2

    # --- Phase 2: Metadata Verification (Size + MTime) ---
    log_msg "--- Phase 2: Metadata Verification (Size + MTime) ---"

    local FAILED_FILES=()
    local SUCCESS_COUNT=0
    local FILENAME DST_PATH SRC_META DST_META

    for FILE in "${FILES[@]}"; do
        FILENAME=$(basename "$FILE")
        DST_PATH="$DEST/$FILENAME"

        if [[ ! -e "$DST_PATH" ]]; then
            log_msg "❌ Missing File: $FILENAME"
            FAILED_FILES+=("$FILE")
            continue
        fi

        SRC_META=$(stat -L -c "%s %Y" "$FILE" 2>/dev/null)
        DST_META=$(stat -c "%s %Y" "$DST_PATH" 2>/dev/null)

        if [[ "$SRC_META" != "$DST_META" ]]; then
            log_msg "❌ Mismatch: $FILENAME"
            FAILED_FILES+=("$FILE")
        else
            ((SUCCESS_COUNT++))
        fi
    done

    # --- Phase 3: Retry (Bash Backgrounding) ---
    if [ ${#FAILED_FILES[@]} -gt 0 ]; then
        log_msg "⚠️  ${#FAILED_FILES[@]} issues detected. Retrying..."

        local retry_count=0
        for FILE in "${FAILED_FILES[@]}"; do
            cp -Lp "$FILE" "$DEST/" &
            ((retry_count++))
            if (( retry_count % MAX_THREADS == 0 )); then
                wait
            fi
        done
        wait

        # Recalculate final success count
        SUCCESS_COUNT=0
        for FILE in "${FILES[@]}"; do
            FILENAME=$(basename "$FILE")
            [[ -e "$DEST/$FILENAME" ]] && ((SUCCESS_COUNT++))
        done
    fi

    # --- Final Summary ---
    log_msg "--- Final Summary ---"
    log_msg "Expected Files: $FILE_COUNT"
    log_msg "Verified Files: $SUCCESS_COUNT"

    if [[ "$SUCCESS_COUNT" -eq "$FILE_COUNT" ]]; then
        log_msg "✅ ALL MATCHED: Copying session successful."
    else
        echo "❌ ERROR: Count mismatch! Only $SUCCESS_COUNT of $FILE_COUNT files are present in $DEST."
        exit 1
    fi
}

case "${task}" in
solver )
    # For the first cycle, we need to copy the ensemble members from ens to ana before running ncks to combine increments to the original background file.
    if [[ CYCLENO -gt 0 ]]; then
        echo "Copying ensemble members from ens to ana for cycle = CYCLENO ..."

        declare -a mem_filelist
        for mem in $(seq -w 001 ENS_SIZE); do
            mem_filelist+=("ens/mem${mem}.nc")
        done

        parallel_copy_verify "ana" ENS_SIZE "${mem_filelist[@]}"
    else
        echo "Should not run ncks for cycle = CYCLENO because we are using the mpasout files ..."
    fi
    ;;

post )
    # Copy ensemble members from Solver to ana and replace "refl10cm" from the forward forecasts
    # for the post-processing task.
    echo "Copying ensemble members from Solver to ana for the post-processing task ..."

    declare -a mem_filelist
    for mem in $(seq -w 001 ENS_SIZE); do
        mem_filelist+=("../jedi_solver/ana/mem${mem}.nc")
    done

    if parallel_copy_verify "ana" ENS_SIZE "${mem_filelist[@]}"; then
        echo "Copying ensemble members from Solver to ana for the post-processing task is successful. Now replacing \"refl10cm\" from the forward forecasts ..."
        declare -a pids=()
        for mem in $(seq -w 01 ENS_SIZE); do
            mem_file="ana/mem0${mem}.nc"
            mpas_file="../fcst_${mem}/DOMNAME_${mem}.diag.CURRTIMEFIL.nc"  # wofs_mpas_01.diag.2026-04-23_18.00.00.nc
            srun --ntasks=1 --exclusive --nodes=${SLURM_NNODES} ncks -A -C -v "refl10cm" "${mpas_file}" "${mem_file}" &
            pids+=($!)
        done

        # Wait for all parallel ncks commands to complete
        icount=0
        ierr=0
        for pid in "${pids[@]}"; do
            wait "${pid}"
            if [ $? -eq 0 ]; then
                ((icount+=1))
            else
                ((ierr+=1))
            fi
        done

        if [ "${icount}" -eq ENS_SIZE ]; then
            echo "✅ Successfully replaced refl10cm in all ensemble members."
        else
            echo "❌ ERROR: refl10cm replacement failed for ${ierr} ensemble members."
            exit 1
        fi
    else
        echo "Failed to copy ensemble members from Solver to ana for the post-processing task."
        exit 1
    fi
    ;;
* )
    ;;
esac

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
                srun --ntasks=1 --exclusive --nodes=${SLURM_NNODES} ncks -A -C -x -v ${var_list} "ens/mem${mem}.nc" "ana/mem${mem}.nc" &
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
