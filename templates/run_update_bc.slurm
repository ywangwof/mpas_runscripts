#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 00:20:00
ACCTSTR
EXCLSTR

# --- Terminal/Manual Run Support ---
# If not running under SLURM, provide a dummy Job ID and check for arguments
if [[ -z "$SLURM_JOBID" ]]; then
    export SLURM_JOBID="manual_$(date +%Y%m%d_%H%M)"
    echo "-- Running in Terminal Mode (Job ID: $SLURM_JOBID) --"
    # If a number is passed as the first argument, treat it as the Array Task ID
    if [[ -n "$1" && "$1" =~ ^[0-9]+$ ]]; then
        export SLURM_ARRAY_TASK_ID=$1
        echo "Targeting Member: $SLURM_ARRAY_TASK_ID"
    fi
else
    ulimit -s unlimited
fi

time1=$(date '+%s')
printf "\nJob Started: %(%a %b %d %H:%M:%S %Z %Y)T. Job Id: %s\n\n" "${time1}" "${SLURM_JOBID}"

# Arrays derived from the driver script
MEMMAP

cd WRKDIR || exit $?

rm -f queue.update_bc
touch running.update_bc

# --- Function to process a single member ---
run_member() {
    local mem=$1
    local memstr=$(printf "%02d" $mem)

    local mlbcstr="${mem_map[$mem]}"

    echo "Processing Member: ${memstr} use LBC member - ${mlbcstr}"

    cd WRKDIR/fcst_${memstr} || return 1

    touch running.update_bc_${memstr}
    rm -rf error.update_bc_${memstr} queue.update_bc_${memstr}

    #
    # init files
    #

    echo "MEM ${memstr}: Using init file: INITORIGFILE => INITFILENAME"
    CPINITCMD "INITORIGFILE" "INITFILENAME"

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
        echo "MEM ${memstr}: Using lbc file: ${lbc_file1} directly"
        CPCMD "${lbc_file1}" "${lbc_filem}"
        istatus=$?
    else
        lbc_origs1="LBCPATH/DOMNAME_${mlbcstr}.lbc.LBCTIME1.nc"
        lbc_origs2="LBCPATH/DOMNAME_${mlbcstr}.lbc.LBCTIME2.nc"
        echo ""
        echo "MEM ${memstr}: Interpolating lbc ${lbc_filem} file from"
        echo "                     ${lbc_origs1} and"
        echo "                     ${lbc_origs2}"
        machine=MACHINE source ROOTDIR/modules/env.python
        ROOTDIR/scripts/intrp_time.py -t "MPASTIME1" "${lbc_origs1}" "${lbc_origs2}" "${lbc_filem}"
        istatus=$?
    fi

    # LBC 2 processing
    lbc_file2="LBCPATH/DOMNAME_${mlbcstr}.lbc.MPASTIME2.nc"
    if [[ -f "${lbc_file2}" ]]; then
        echo "MEM ${memstr}: Using lbc file: ${lbc_file2} directly"
        ln -sf "${lbc_file2}" "${lbc_filen}"
        istatus=$?
    else
        lbc_origs1="LBCPATH/DOMNAME_${mlbcstr}.lbc.LBCTIME1.nc"
        lbc_origs2="LBCPATH/DOMNAME_${mlbcstr}.lbc.LBCTIME2.nc"

        echo ""
        echo "MEM ${memstr}: Interpolating lbc ${lbc_filen} file from"
        echo "                     ${lbc_origs1} and"
        echo "                     ${lbc_origs2}"
        echo ""
        machine=MACHINE source ROOTDIR/modules/env.python
        ROOTDIR/scripts/intrp_time.py -t "MPASTIME2" "${lbc_origs1}" "${lbc_origs2}" "${lbc_filen}"
        istatus=$?
    fi

    rm -rf running.update_bc_${memstr}

    # Check exit status
    if [[ ${istatus} -eq 0 ]]; then
        touch done.update_bc_${memstr}
    else
        touch error.update_bc_${memstr}
    fi

    return ${istatus}
}

# @@@ Main Execution Logic @@@
if [[ -n "$SLURM_ARRAY_TASK_ID" ]]; then
    # Mode 1: Run as a standard SLURM Array
    # SLURM automatically isolates this task's resources.
    run_member "$SLURM_ARRAY_TASK_ID"
else
    # Mode 2: Run all NENS members in background simultaneously
    # Ensure NENS is replaced by your actual ensemble count
    # Use srun to give each member its own dedicated CPUs/Resource step

    # Capture definitions for subprocesses

    array_defs=$(declare -p mem_map)
    func_def=$(declare -f run_member)

    # Use srun if in a real SLURM job, otherwise use standard bash
    if [[ "$SLURM_JOBID" == manual* ]]; then
        LAUNCH_CMD="bash -c"
        echo "Launching all members in background (Local Terminal Mode)..."
    else
        # --ntasks=1 ensures this specific member gets 1 task's worth of resources
        # --exclusive: Ensures no two srun steps share the same CPU core
        # --relative=0: Starts looking for free slots from the first node in the allocation
        # --nodes=1, you are telling SLURM: "Execute this member's logic on exactly one node;
        #            do not attempt to split its resources across the network fabric
        # Since srun starts a new shell context, bash -c "$(declare -f run_member); ..."
        # exports the function logic into that new sub-process so it can be executed.
        # srun to execute a command, it launches that task in a separate sub-process
        #         each member is running in its own isolated environment
        LAUNCH_CMD="srun --ntasks=1 --nodes=1 --exclusive --relative=0 bash -c"
    fi

    declare -A pids  # Associative array to store PID -> Member mapping
    for m in NENS_MEMBERS; do
        $LAUNCH_CMD "$array_defs; $func_def; run_member $m" &
        pids[$!]=$m
    done

    echo "All tasks submitted. Waiting for completion..."

    declare -a fail_jobs=()

    overall_status=0
    for pid in "${!pids[@]}"; do
        wait "$pid"
        status=$?
        member_idx=${pids[$pid]}

        if [[ $status -eq 0 ]]; then
            echo "Member ${member_idx} (PID $pid) finished successfully."
        else
            echo "Member ${member_idx} (PID $pid) FAILED with exit code $status."
            fail_jobs+=("${member_idx}")
            overall_status=1
        fi
    done

    # Status Cleanup
    if [[ $overall_status -ne 0 ]]; then
        echo "One or more members failed: ( ${fail_jobs[*]} )"
        touch error.update_bc
    else
        touch done.update_bc
    fi
    rm -f running.update_bc
fi

time2=$(date '+%s')
diff=$((time2-time1))
printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" "${time2}" "$(date -d@$diff -u +%H:%M:%S)"
