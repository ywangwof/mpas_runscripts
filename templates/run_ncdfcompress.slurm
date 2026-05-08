#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 04:30:00
#SBATCH --output=WRKDIR/JOBNAME_%j.log
ACCTSTR
EXCLSTR

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

# Compress all .nc files in the current directory, return 1 on first failure.
# Args: context_string (used in error messages)
compress_ncfiles() {
    local context="$1"

    echo "Compressing .nc files in ${context} ..."

    # Use xargs with parallel execution based on SLURM_CPUS_PER_TASK
    local num_procs=${SLURM_CPUS_PER_TASK:-1}

    # Export the function so child shells (spawned by xargs) can access it
    export -f compress_single_ncfile

    find . -type f -name "*.nc" -print0 | xargs -0 -I {} -P "${num_procs}" bash -c 'compress_single_ncfile "{}"'

    return $?
}

# Compress a task directory tree between ${begins} and ${ends}.
# Args: basedir  intval  timesubdir  mem_prefix
#   basedir    – directory to enter (absolute or relative to ${wrkdir}/${eventdate})
#   intval     – time step in seconds
#   timesubdir – optional sub-directory under the hhmm step (e.g. "mpassit"; empty = none)
#   mem_prefix – member directory prefix ("fcst_", "mem_"; empty = no member loop)
compress_task() {
    local basedir="$1"
    local intval="$2"
    local timesubdir="$3"
    local mem_prefix="$4"

    pushd "${basedir}" > /dev/null || return 1
    echo "Before compression ($(pwd)): $(du -sh .)"

    for ((sec=begins; sec<=ends; sec+=intval)); do
        hhmm=$(date -d "@$sec" -u +%H%M)
        local timedir="${hhmm}"
        [[ -n "${timesubdir}" ]] && timedir="${hhmm}/${timesubdir}"

        pushd "${timedir}" > /dev/null || { popd > /dev/null || exit; return 1; }

        if [[ -n "${mem_prefix}" ]]; then
            for mem in $(seq -f "%02g" 1 ${nens}); do
                pushd "${mem_prefix}${mem}" > /dev/null || { popd > /dev/null || exit; popd > /dev/null || exit; return 1; }
                compress_ncfiles "${basedir}/${timedir}/${mem_prefix}${mem}" || { popd > /dev/null || exit; popd > /dev/null || exit; popd > /dev/null || exit; return 1; }
                popd > /dev/null || { popd > /dev/null || exit; return 1; }
            done
        else
            compress_ncfiles "${basedir}/${timedir}" || { popd > /dev/null || exit; popd > /dev/null || exit; return 1; }
        fi

        popd > /dev/null || { popd > /dev/null || exit; return 1; }
    done

    echo "After compression ($(pwd)): $(du -sh .)"
    popd > /dev/null || exit
}

istatus=0
for task in "${tasks[@]}"; do
    echo "Compressing: ${task} for ${eventdate}${affix} from $(date -d "@${begins}" -u +%H%M) to $(date -d "@${ends}" -u +%H%M) with ${nens} members."

    case ${task} in
        dacycles ) compress_task "dacycles${affix}"                              900 ""        "fcst_" || { istatus=1; break; } ;;
        fcst     ) compress_task "fcst${affix}"                                 3600 ""        "fcst_" || { istatus=1; break; } ;;
        mpassit  ) compress_task "fcst${affix}"                                 3600 "mpassit" "mem_"  || { istatus=1; break; } ;;
        post     ) compress_task "${wrkdir}/summary_files/${eventdate}${affix}" 3600 ""        ""      || { istatus=1; break; } ;;
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
