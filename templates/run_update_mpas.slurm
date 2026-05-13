#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH --mem=96G
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/fcst_all_update_mpas_%j.log
#SBATCH --exclusive
ACCTSTR


time1=$(date '+%s')
printf "\nJob Started: %(%a %b %d %H:%M:%S %Z %Y)T. Job Id: %s\n\n" "${time1}" "${SLURM_JOBID}"

machine=MACHINE source ROOTDIR/modules/env.python

ulimit -s unlimited


cd WRKDIR || exit $?

rm -f queue.update_mpas
touch running.update_mpas

# __BEGIN_addnoise

# ---------------------------------------------------------------------
# Run the python programs for noise mask if requested
# ---------------------------------------------------------------------

    # Retrieve command line parameters
    echo "Starting \"grid_refl_obs.py\" for add_noise step ..."
    echo "python ROOTDIR/wofs_addnoise/grid_refl_obs.py SEQFILE 35.0 10.0 INVFILE EVENTDATETIME mpas"
    python ROOTDIR/wofs_addnoise/grid_refl_obs.py SEQFILE 35.0 10.0 INVFILE EVENTDATETIME mpas
    estatus="$?"
    echo "Task \"grid_refl_obs.py\" return status = $estatus ..."

    if [[ $estatus -ne 0 ]]; then
        touch error.update_mpas
        rm -rf running.update_mpas
        exit $estatus
    fi

    # ===================================================================
    # Copy pickle files to ramdisk cache for faster parallel I/O
    # ===================================================================
    ramdisk_cache="/dev/shm/mpas_cache_$$"
    mkdir -p "$ramdisk_cache" 2>/dev/null

    # Copy large pickle files to ramdisk if space available
    pkl_files_to_cache=(
        "wofs_mpas_grid_kdtree.pkl"
        "wofs_mpas_XYZ.pkl"
    )

    cache_success=0
    for pkl_file in "${pkl_files_to_cache[@]}"; do
        src_file="WRKDIR/$pkl_file"
        if [[ -f "$src_file" ]]; then
            cp -f "$src_file" "$ramdisk_cache/" 2>/dev/null && ((cache_success++))
        fi
    done

    # Also copy refl observation pickle files (using wildcard pattern)
    for refl_file in WRKDIR/refl_valid_obs_*.pkl; do
        if [[ -f "$refl_file" ]]; then
            cp -f "$refl_file" "$ramdisk_cache/" 2>/dev/null && ((cache_success++))
        fi
    done

    if [[ $cache_success -gt 0 ]]; then
        echo "Cached $cache_success pickle files in ramdisk: $ramdisk_cache"
    else
        echo "Warning: Could not cache pickle files in ramdisk. Using disk cache."
        rm -rf "$ramdisk_cache"
    fi
# __END_addnoise

# ----------------------------------------------------------------------
# run update_member
# ---------------------------------------------------------------------
# Arrays derived from the driver script

MEMMAP
# ----------------------------------------------------------------------
# Pre-copy all 36 init files in parallel background jobs (2.9GB each).
# This separates the heavy I/O from SLURM task scheduling overhead.
# ----------------------------------------------------------------------
echo -e "\nPre-copying all init files in parallel ...\n"
declare -a copy_pids=()
for mem in NENS_MEMBERS; do
    memstr=$(printf "%02d" $mem)

    pushd fcst_${memstr} > /dev/null || return 1

    echo "MEM ${memstr}: Using init file: INITFILENAME"
    echo "              <= INITORIGFILE"
# __BEGIN_addnoise
    cp -f "INITORIGFILE" "INITFILENAME" &
    copy_pids+=($!)
# __END_addnoise

# __BEGIN_noaddnoise
    ln -sf "INITORIGFILE" "INITFILENAME"
# __END_noaddnoise

    popd > /dev/null || exit 1
done

echo "Waiting for all ${#copy_pids[@]} init file copies to complete ..."
for cpid in "${copy_pids[@]}"; do
    wait "$cpid"
done
echo -e "All init file copies completed.\n"

########################################################################
#
# --- Function to process a single member ---
#
########################################################################
run_update_member() {
    local mem=$1
    local memstr=$(printf "%02d" $mem)

    local mlbcstr="${mem_map[$mem]}"

    cd WRKDIR/fcst_${memstr} || return 1

    # Redirect all subsequent commands in this subshell/function
    exec > log.update_mpas_${memstr} 2>&1

    echo "Processing Member: ${memstr} use LBC member - ${mlbcstr}"

    touch running.update_mpas_${memstr}
    rm -rf error.update_mpas_${memstr}


    #
    # lbc files
    #

    lbc_filem="./DOMNAME_${memstr}.lbc.MPASTIME1.nc"
    lbc_filen="./DOMNAME_${memstr}.lbc.MPASTIME2.nc"

    # Cleanup existing files
    [[ -e $lbc_filem ]] && rm -rf "${lbc_filem}"
    [[ -e $lbc_filen ]] && rm -rf "${lbc_filen}"

    # LBC 1 processing
    lbc_file1="LBCPATH/DOMNAME_${mlbcstr}.lbc.MPASTIME1.nc"
    if [[ -f "${lbc_file1}" ]]; then
        echo -e "\nMEM ${memstr}: Using lbc file: ${lbc_file1} directly"
        CPCMD "${lbc_file1}" "${lbc_filem}"
        ((istatus+=$?))
    else
        lbc_origs1="LBCPATH/DOMNAME_${mlbcstr}.lbc.LBCTIME1.nc"
        lbc_origs2="LBCPATH/DOMNAME_${mlbcstr}.lbc.LBCTIME2.nc"
        echo ""
        echo -e "\nMEM ${memstr}: Interpolating lbc ${lbc_filem} file from"
        echo "                     ${lbc_origs1} and"
        echo "                     ${lbc_origs2}"
        #machine=MACHINE source ROOTDIR/modules/env.python
        ROOTDIR/scripts/intrp_time.py -t "MPASTIME1" "${lbc_origs1}" "${lbc_origs2}" "${lbc_filem}"
        ((istatus+=$?))
    fi

    # LBC 2 processing
    lbc_file2="LBCPATH/DOMNAME_${mlbcstr}.lbc.MPASTIME2.nc"
    if [[ -f "${lbc_file2}" ]]; then
        echo -e "\nMEM ${memstr}: Using lbc file: ${lbc_file2} directly"
        ln -sf "${lbc_file2}" "${lbc_filen}"
        ((istatus+=$?))
    else
        lbc_origs1="LBCPATH/DOMNAME_${mlbcstr}.lbc.LBCTIME1.nc"
        lbc_origs2="LBCPATH/DOMNAME_${mlbcstr}.lbc.LBCTIME2.nc"

        echo ""
        echo -e "\nMEM ${memstr}: Interpolating lbc ${lbc_filen} file from"
        echo "                     ${lbc_origs1} and"
        echo "                     ${lbc_origs2}"
        echo ""
        #machine=MACHINE source ROOTDIR/modules/env.python
        ROOTDIR/scripts/intrp_time.py -t "MPASTIME2" "${lbc_origs1}" "${lbc_origs2}" "${lbc_filen}"
        ((istatus+=$?))
    fi

# __BEGIN_addnoise
    #
    # run add_pert_where_high_refl.py if requested
    # This is done after the LBC files are prepared since the script may need to read the LBC files to determine where to add noise

    cat > "config.add_pert_where_high_refl_${memstr}.yaml" << EOF
# Configuration for add_pert_where_high_refl.py

# Model and file paths
modelGrid: INVFILE
modelFile: INITFILENAME
pkl_path:  WRKDIR

# Model type: 'mpas' or other valid model type
modelType: mpas

# Length scales for smoothing (meters)
h_length: 9000.0      # horizontal length scale
v_length: 3000.0      # vertical length scale

# Standard deviations for perturbations (for each field)
u_sd:  0.5             # u wind standard deviation
v_sd:  0.5             # v wind standard deviation
w_sd:  0.0             # w wind standard deviation
t_sd:  0.5             # temperature standard deviation
td_sd: 0.5             # dew point standard deviation
qv_sd: 1.0e-5          # specific humidity standard deviation

# Date and ensemble information
gdatetime: EVENTDATETIME        # Grid date/time (YYYYMMDDHHmm format)
ensNum: ${mem}                  # Ensemble member number
EOF
    #echo "python ROOTDIR/wofs_addnoise/add_pert_where_high_refl.py INVFILE INITFILENAME 9000.0 3000.0 0.50 0.50 0.0 0.50 0.50 0.0 EVENTDATETIME ${mem} mpas WRKDIR"
    echo -e "\npython ROOTDIR/wofs_addnoise/add_pert_where_high_refl.py config.add_pert_where_high_refl_${memstr}.yaml"
    python ROOTDIR/wofs_addnoise/add_pert_where_high_refl.py "config.add_pert_where_high_refl_${memstr}.yaml"
    echo "Tasks of add_pert_where_high_refl.py return status = $?"
    ((istatus+=$?))
# __END_addnoise

    rm -rf running.update_mpas_${memstr}

    # Check exit status
    if [[ ${istatus} -eq 0 ]]; then
        touch done.update_mpas_${memstr}
    else
        touch error.update_mpas_${memstr}
    fi

    return ${istatus}
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#
# Main Execution Logic
# Run all NENS members in background simultaneously
#
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# Capture definitions for subprocesses

array_defs=$(declare -p mem_map)
func_def=$(declare -f run_update_member)

declare -A pids  # Associative array to store PID -> Member mapping
declare -a fail_jobs=()

for mem in NENS_MEMBERS; do
    ( eval "$array_defs"; eval "$func_def"; run_update_member $mem ) &
    pids[$!]=$mem
done

echo -e "All tasks of run_update_member submitted. Waiting for completion ...\n"

overall_status=0
for pid in "${!pids[@]}"; do
    wait "$pid"
    status=$?
    member_idx=${pids[$pid]}

    if [[ $status -eq 0 ]]; then
        echo "Member ${member_idx} (PID $pid) run_update_member finished successfully."
    else
        echo "Member ${member_idx} (PID $pid) run_update_member FAILED with exit code $status."
        fail_jobs+=("${member_idx}")
        overall_status=1
    fi
done

# Status Cleanup
if [[ $overall_status -eq 0 ]]; then
    touch done.update_mpas
else
    echo "One or more members failed run_update_member: ( ${fail_jobs[*]} )."
    touch error.update_mpas
fi
echo "Check log file \"log.update_mpas_??\" in the member directory for details."

rm -rf running.update_mpas

# __BEGIN_addnoise
# Cleanup ramdisk cache
ramdisk_cache="/dev/shm/mpas_cache_$$"
if [[ -d "$ramdisk_cache" ]]; then
    rm -rf "$ramdisk_cache"
    echo "Cleaned up ramdisk cache: $ramdisk_cache"
fi
# __END_addnoise

time2=$(date '+%s')
diff=$((time2-time1))
printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" "${time2}" "$(date -d@$diff -u +%H:%M:%S)"
