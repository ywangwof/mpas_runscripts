#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART --ntasks-per-node=NOPART
#SBATCH --cpus-per-task=CPUSPEC
#SBATCH -t 04:30:00
#SBATCH --output=WRKDIR/JOBNAME_%j.log
#SBATCH --exclusive
ACCTSTR

# ============================================================================
# Parallelism Configuration:
# subshells ( ) & only run on the single head node.
# The script is designed to run on a single node, utilizing multiple CPU cores for parallel processing.
# The parallelism is achieved through background subshells (using &) that allow multiple member directories to be processed simultaneously.
# The script does not use MPI or distributed computing; all parallelism is confined to the single node.
#
# This script uses a two-level parallelism strategy:
#
# 1. TIMEDIR LEVEL (outer loop): Processes time steps in parallel
#    - Controlled by: --ntasks (SLURM_NTASKS)
#    - Each time directory runs as an independent process
#    - Default (if unset): 2 (parallel execution using one node on Ursa)
#
# 2. MEMBER LEVEL (inner loop): Processes ensemble members in parallel
#    - Controlled by: --cpus-per-task (SLURM_CPUS_PER_TASK)
#    - Each member directory runs as an independent process within a timedir
#    - Default (if unset): 36 (the number of WoFS DA ensembles)
#
# CONFIGURATION EXAMPLE:
#   To run 4 time steps in parallel, each with 8 members in parallel:
#     #SBATCH --ntasks=4
#     #SBATCH --cpus-per-task=8
#
# NOTE: The total parallelism is bounded by available resources.
#       Ensure --ntasks * --cpus-per-task ≤ available system resources.
# ============================================================================

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

#machine=MACHINE
module load nco

cd WRKDIR || exit $?

touch running.JOBNAME
rm -rf error.JOBNAME queue.JOBNAME

tasks=TASKLIST
wrkdir=WRKDIR

eventdate=EVENTDATE
affix=AFFIX

begins=BEGINS
ends=ENDS

nens=MEMBERS

cd ${wrkdir}/${eventdate} || exit $?

# Compress a single .nc file using ncks.
# Args: ncfile
compress_single_ncfile() {
    local ncfile="$1"

    ncks -4 -L 5 -O "${ncfile}" "${ncfile%.nc}_compressed.nc"
    if [[ $? -eq 0 ]]; then
        rm -rf "${ncfile}"
        mv "${ncfile%.nc}_compressed.nc" "${ncfile}"
    else
        echo "Error processing ${ncfile}."
        return 1
    fi
}

# Compress all .nc files in a member directory serially, return 1 on first failure.
# Args: memdir  timedir
#   memdir – relative path to member directory (e.g. "fcst_01")
#   timedir – time directory string (used in output messages)
compress_mem() {
    local memdir="$1"
    local timedir="$2"

    cd "${memdir}" || exit 1

    echo "Compressing .nc files in ${timedir}/${memdir} ..."

    local status=0
    while IFS= read -r -d '' ncfile; do
        compress_single_ncfile "${ncfile}" || { status=1; break; }
    done < <(find . -type f -name "*.nc" -print0)

    if [[ ${status} -ne 0 ]]; then
        echo "      Failed ${timedir}/${memdir} compression."
        return 1
    else
        echo "      Done ${timedir}/${memdir} compression."
        return 0
    fi
}

# Compress all .nc files in the current directory in parallel, return 1 on first failure.
# Args: memdir  num_procs
#   memdir    - relative path to member directory (optional, for cd; empty = current dir)
#   num_procs - number of parallel processes (optional, defaults to SLURM_CPUS_PER_TASK)
compress_ncfiles() {
    local memdir="$1"
    local num_procs=${2:-${SLURM_CPUS_PER_TASK:-1}}

    # Change to member directory if specified
    cd "${memdir}" || exit 1

    # Export the function so child shells (spawned by xargs) can access it
    export -f compress_single_ncfile

    echo -n "Compressing .nc files in ${memdir} using ${num_procs} parallel processes ..."

    find . -type f -name "*.nc" -print0 | xargs -0 -I {} -P "${num_procs}" bash -c 'compress_single_ncfile "{}"'

    if [[ $? -ne 0 ]]; then
        echo " Failed."
        return 1
    else
        echo " Done."
        return 0
    fi
}

# Compress a task directory tree between ${begins} and ${ends}.
# Args: basedir  intval  timesubdir  mem_prefix
#   basedir    – directory to enter (absolute or relative to ${wrkdir}/${eventdate})
#   intval     – time step in seconds
#   timesubdir – optional sub-directory under the hhmm step (e.g. "mpassit"; empty = none)
#   mem_prefix – member directory prefix ("fcst_", "mem_")
compress_task() {
    local basedir="$1"
    local intval="$2"
    local timesubdir="$3"
    local mem_prefix="$4"

    pushd "${basedir}" > /dev/null || return 1
    echo "Before compression ($(pwd)): $(du -sh .)"

    local max_timedir_jobs=${SLURM_NTASKS:-2}
    local max_mem_jobs=${SLURM_CPUS_PER_TASK:-36}
    local timedir_pids=()
    local failed=0
    for ((sec=begins; sec<=ends; sec+=intval)); do
        hhmm=$(date -d "@$sec" -u +%H%M)
        local timedir="${hhmm}"
        [[ -n "${timesubdir}" ]] && timedir="${hhmm}/${timesubdir}"

        (
            cd "${timedir}" || exit 1

            local mem_pids=()
            local mem_failed=0
            for mem in $(seq -f "%02g" 1 ${nens}); do
                ( compress_mem "${mem_prefix}${mem}" "${timedir}" || exit 1 ) &
                mem_pids+=("$!")

                # Throttle mem jobs
                if [[ ${#mem_pids[@]} -ge ${max_mem_jobs} ]]; then
                    wait "${mem_pids[0]}" || mem_failed=1
                    mem_pids=("${mem_pids[@]:1}")
                fi
            done

            # Wait for remaining mem jobs
            for pid in "${mem_pids[@]}"; do
                wait "${pid}" || mem_failed=1
            done

            exit ${mem_failed}
        ) &
        timedir_pids+=("$!")

        # Throttle timedir jobs
        if [[ ${#timedir_pids[@]} -ge ${max_timedir_jobs} ]]; then
            wait "${timedir_pids[0]}" || failed=1
            timedir_pids=("${timedir_pids[@]:1}")
        fi

        #   Compress "ana" directories (output) under "jedi_solver" and "jedi_post" if they exist
        (
            cd "${timedir}" || exit 1

            for jedi_dir in "jedi_solver" "jedi_post"; do
                if [[ -d "${jedi_dir}/ana" ]]; then
                    compress_ncfiles "${jedi_dir}/ana" "${max_mem_jobs}" || exit 1
                fi
            done
        ) &
        timedir_pids+=("$!")

        # Throttle timedir jobs
        if [[ ${#timedir_pids[@]} -ge ${max_timedir_jobs} ]]; then
            wait "${timedir_pids[0]}" || failed=1
            timedir_pids=("${timedir_pids[@]:1}")
        fi
    done

    # Wait for remaining timedir jobs
    for pid in "${timedir_pids[@]}"; do
        wait "${pid}" || failed=1
    done

    echo "After compression ($(pwd)): $(du -sh .)"
    popd > /dev/null || exit
    return ${failed}
}

istatus=0
for task in "${tasks[@]}"; do
    echo "Compressing: ${task} for ${eventdate}${affix} from $(date -d "@${begins}" -u +%H%M) to $(date -d "@${ends}" -u +%H%M) with ${nens} members."

    case ${task} in
        dacycles ) compress_task "dacycles${affix}" 900 "" "fcst_" || { istatus=1; break; } ;;
        *        ) echo "Skipping ${task}, not supported."; continue ;;
    esac
done

estatus="${istatus}"
if [[ $estatus -eq 0 ]]; then
    touch done.JOBNAME
else
    touch error.JOBNAME
fi

rm -rf running.JOBNAME

time2=$(date '+%s')

diff=$((time2-time1))

printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" "${time2}" "$(date -d@$diff -u +%H:%M:%S)"
