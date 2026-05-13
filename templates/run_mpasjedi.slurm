#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/jedi_TASKNAME_%j.log
ACCTSTR
EXCLSTR

#set -eux
DEBUG=WRKFLOWDEBUG   # set to true to enable debug messages

time1=$(date '+%s')
printf "Job Started: %(%a %b %d %H:%M:%S %Z %Y)T. Job Id: %s\n\n" "${time1}" "${SLURM_JOBID}"

# shellcheck disable=SC2050,SC1091
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

nnode=CONFIGNNODES
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

# __BEGIN_funcdef
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
# __END_funcdef

# __BEGIN_solver_pre
# For the cycles other than the first one, we need to copy the ensemble members from ens to ana before running ncks to combine increments to the original background file.
#if [[ CYCLENO -gt 0 ]]; then
    echo "Copying ensemble members from ens to ana for cycle = CYCLENO ..."

    declare -a mem_filelist
    for mem in $(seq -w 001 ENS_SIZE); do
        mem_filelist+=("ens/mem${mem}.nc")
    done

    t_start=$(date '+%s')
    parallel_copy_verify "ana" ENS_SIZE "${mem_filelist[@]}"
    [[ "$DEBUG" == true ]] && printf "Elapsed time for copying ens to ana: %s\n" "$(date -d@$(( $(date '+%s') - t_start )) -u +%H:%M:%S)"
#fi
# __END_solver_pre

# __BEGIN_post
# Copy ensemble members from Solver to ana and replace "refl10cm" from the forward forecasts
# for the post-processing task.
echo "Copying ensemble members from Solver to ana for the post-processing task ..."

declare -a mem_filelist
for mem in $(seq -w 001 ENS_SIZE); do
    mem_filelist+=("../jedi_solver/ana/mem${mem}.nc")
done

# shellcheck disable=SC2050
if [[ USE_REFL10CM_DIAG == true ]]; then
    echo "Will replace \"refl10cm\" from the forward forecasts for the post-processing task ..."

    t_start=$(date '+%s')
    if parallel_copy_verify "ana" ENS_SIZE "${mem_filelist[@]}"; then
        [[ "$DEBUG" == true ]] && printf "Elapsed time for copying solver ana to post ana: %s\n" "$(date -d@$(( $(date '+%s') - t_start )) -u +%H:%M:%S)"
        echo "Copying ensemble members from Solver to ana for the post-processing task is successful."
        echo "Now replacing \"refl10cm\" from the forward forecasts ..."

        mapfile -t nodelist < <(scontrol show hostnames "$SLURM_NODELIST")
        nnodes=${#nodelist[@]}
        declare -a pids=()
        t_start=$(date '+%s')
        for mem in $(seq -w 01 ENS_SIZE); do
            mem_idx=$(( 10#${mem} - 1 ))
            node=${nodelist[$((mem_idx % nnodes))]}

            mem_file="ana/mem0${mem}.nc"
            mpas_file="../fcst_${mem}/DOMNAME_${mem}.diag.CURRTIMEFIL.nc"  # wofs_mpas_01.diag.2026-04-23_18.00.00.nc
            echo "Replacing refl10cm,refl10cm_max in ${mem_file} with ${mpas_file} on node ${node} ..."
            srun --ntasks=1 --exact --cpus-per-task=1 --mem-per-cpu=10G --nodes=1 --nodelist="${node}"  \
                ncks -A -C -v "refl10cm,refl10cm_max" "${mpas_file}" "${mem_file}" &
            pids+=($!)
        done

        # Wait for all parallel ncks commands to complete
        icount=0
        ierr=0
        for pid in "${pids[@]}"; do
            wait "${pid}"
            # shellcheck disable=SC2181
            if [ $? -eq 0 ]; then
                ((icount+=1))
            else
                ((ierr+=1))
            fi
        done

        # shellcheck disable=SC2170
        if [ "${icount}" -eq ENS_SIZE ]; then
            [[ "$DEBUG" == true ]] && printf "Elapsed time for ncks refl10cm replacement: %s\n" "$(date -d@$(( $(date '+%s') - t_start )) -u +%H:%M:%S)"
            echo "✅ Successfully replaced refl10cm in all ensemble members."
        else
            echo "❌ ERROR: refl10cm replacement failed for ${ierr} ensemble members."
            exit 1
        fi
    else
        echo "Failed to copy ensemble members from Solver to ana for the post-processing task."
        exit 1
    fi
else
    echo "No need to replace \"refl10cm\" from the forward forecasts for the post-processing task because use_refl10cm_diag is set to false."
    echo "Just linking ensemble members from Solver to ana for the post-processing task."
    wrkdir_base=$(dirname WRKDIR)
    for mem in $(seq -w 001 ENS_SIZE); do
        mem_file="${wrkdir_base}/jedi_solver/ana/mem${mem}.nc"
        ln -sf "${mem_file}" "ana/mem${mem}.nc"
    done
fi
# __END_post

sed -i -e "/config_pio_num_iotasks/s/=.*/= $nnode/g;/config_pio_stride/s/=.*/= $ncores/" namelist.atmosphere

t_start=$(date '+%s')
RUNMPCMD -n NOPART EXEDIR/mpasjedi_enkf.x getkf.yaml log.out
istatus=$?
[[ "$DEBUG" == true ]] && printf "Elapsed time for mpasjedi_enkf.x: %s\n" "$(date -d@$(( $(date '+%s') - t_start )) -u +%H:%M:%S)"

if [[ $istatus -eq 0 ]]; then

    # __BEGIN_post
    # rename ombg to oman for posterior observer jdiag files
    t_start=$(date '+%s')
    #[[ $DEBUG == true ]] && echo "DEBUG: Working directory is $(pwd). Renaming ombg to oman for posterior observer jdiag files ..."
    for jdiag in ./jdiag_*.nc; do
        echo -e "\nRenaming ombg to oman for ${jdiag} ..."
        jdiag_tmp="${jdiag%.nc}_tmp.nc"
        [[ "$DEBUG" == true ]] && echo "DEBUG: nccopy -k 3 ${jdiag} ${jdiag_tmp}"
        nccopy -k 3 "${jdiag}" "${jdiag_tmp}"
        iret=$?
        (( istatus += iret ))
        [[ "$DEBUG" == true ]] && echo "DEBUG: nccopy returned ${iret} (istatus=${istatus})"
        [[ "$DEBUG" == true ]] && echo "DEBUG: ncrename -g ombg,oman ${jdiag_tmp}"
        ncrename -g ombg,oman "${jdiag_tmp}"
        iret=$?
        (( istatus += iret ))
        [[ "$DEBUG" == true ]] && echo "DEBUG: ncrename returned ${iret} (istatus=${istatus})"
        [[ "$DEBUG" == true ]] && echo "DEBUG: mv ${jdiag_tmp} ${jdiag}"
        mv "${jdiag_tmp}" "${jdiag}"
        iret=$?
        (( istatus += iret ))
        [[ "$DEBUG" == true ]] && echo "DEBUG: mv returned ${iret} (istatus=${istatus})"
    done
    [[ "$DEBUG" == true ]] && printf "Elapsed time for nccopy/ncrename jdiag loop: %s\n" "$(date -d@$(( $(date '+%s') - t_start )) -u +%H:%M:%S)"
    # __END_post

    # __BEGIN_solver_after
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
    echo "Should run ncks for cycle = CYCLENO only because we are using the mpasout files ..."

    #if [[ CYCLENO -eq 0 ]]; then
        t_start=$(date '+%s')
        echo "Running ncks for cycle = CYCLENO to combine increments to the original background file ..."
        var_list="VARLIST"
        mapfile -t nodelist < <(scontrol show hostnames "$SLURM_NODELIST")
        nnodes=${#nodelist[@]}

        declare -a pids=()
        for mem in $(seq -w 001 ENS_SIZE); do
            mem_idx=$(( 10#${mem} - 1 ))
            node=${nodelist[$((mem_idx % nnodes))]}
            srun --ntasks=1 --exact --cpus-per-task=1 --nodes=1 --nodelist="${node}" --mem-per-cpu=10G \
                ncks -A -C -x -v ${var_list} "ens/mem${mem}.nc" "ana/mem${mem}.nc" &
            pids+=($!)
        done

        icount=0; ierr=0
        # Wait for all and check status
        for pid in "${pids[@]}"; do
            wait "$pid";
            # shellcheck disable=SC2181
            if [ $? -eq 0 ]; then
                #echo "PID $pid exited successfully"
                ((icount+=1))
            else
                #echo "PID $pid failed"
                ((ierr+=1))
            fi
        done

        # shellcheck disable=SC2170
        if [ "$icount" -eq ENS_SIZE ]; then
            [[ "$DEBUG" == true ]] && printf "Elapsed time for ncks -A append loop: %s\n" "$(date -d@$(( $(date '+%s') - t_start )) -u +%H:%M:%S)"
            sleep 10   # file system may be slower than the job status in memory
            istatus=0
        else
            istatus=1
        fi
    #else
    #    echo "Skip ncks for cycle > 0 to use mpasout files ..."
    #fi
    # __END_solver_after

    # __BEGIN_jobcheck
    if [[ $istatus -eq 0 ]]; then
    # __END_jobcheck
        touch done.${task}
    # __BEGIN_jobcheck
    else
        touch error.${task}
    fi
    # __END_jobcheck
else
    touch error.${task}
fi

rm -rf running.${task}

time2=$(date '+%s')

diff=$((time2-time1))

printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" "${time2}" "$(date -d@$diff -u +%H:%M:%S)"
