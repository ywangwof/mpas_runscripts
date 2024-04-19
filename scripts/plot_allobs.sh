#!/bin/bash
script_dir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
rootdir=$(realpath "$(dirname "${script_dir}")")
#rootdir="/scratch/ywang/MPAS/gnu/mpas_scripts"

rundir="${rootdir}/run_dirs"

eventdateDF=$(date -u +%Y%m%d)

host="$(hostname)"

#-----------------------------------------------------------------------

function usage {
    echo " "
    echo "    USAGE: $0 [options] DATETIME"
    echo " "
    echo "    PURPOSE: Plot data assimilation diagnostics."
    echo " "
    echo "    DATETIME - Case date and time in YYYYmmdd."
    echo "               YYYYmmdd:     run the plot for this event date."
    echo " "
    echo "    OPTIONS:"
    echo "              -h                  Display this message"
    echo "              -n                  Show command to be run and generate job scripts only"
    echo "              -v                  Verbose mode"
    echo "              -d dacycles         DA cycles subdirectory name"
    echo " "
    echo "   DEFAULTS:"
    echo "              eventdt    = $eventdateDF"
    echo "              rootdir    = $rootdir"
    echo "              run_dir    = $rundir"
    echo "              script_dir = $script_dir"
    echo " "
    echo "                                     -- By Y. Wang (2024.04.17)"
    echo " "
    exit $1
}

#-----------------------------------------------------------------------
#
# Handle command line arguments (override default settings)
#
#-----------------------------------------------------------------------
#% ARGS
show=""
verb=false

eventdate=${eventdateDF}
dadir="dacycles"

while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
        -h)
            usage 0
            ;;
        -n)
            show="echo"
            ;;
        -v)
            verb=true
            ;;
        -d)
            dadir="$2"
            shift
            ;;
        -*)
            echo "Unknown option: $key"
            usage 2
            ;;
        *)
            if [[ $key =~ ^[0-9]{8}$ ]]; then
                eventdate=${key}
            else
                echo ""
                echo "ERROR: unknown argument, get [$key]."
                usage 3
            fi
            ;;
    esac
    shift # past argument or value
done

if [[ ! "$host" =~ ^wof-epyc.*$ ]]; then
    echo "ERROR: Please run $0 on wof-epyc8 only".
    exit 1
fi

if [[ ! -d ${rundir}/${eventdate}/${dadir} ]]; then
    echo "ERROR: DA cycles directory: ${rundir}/${eventdate}/${dadir} not exist."
    exit 1
fi

#if [[ $- != *i* ]]; then
if [ -t 1 ]; then # "interactive"
    echo "$0 $eventdate in $(pwd)"
else              # "at job", load Python environment
    # >>> mamba initialize >>>
    # !! Contents within this block are managed by 'mamba init' !!
    export MAMBA_EXE='/home/yunheng.wang/y/micromamba';
    export MAMBA_ROOT_PREFIX='/home/yunheng.wang/y';
    __mamba_setup="$("$MAMBA_EXE" shell hook --shell bash --root-prefix "$MAMBA_ROOT_PREFIX" 2> /dev/null)"
    if [ $? -eq 0 ]; then
        eval "$__mamba_setup"
    else
        micromamba() { "$MAMBA_EXE"; }  # Fallback on help from mamba activate
    fi
    unset __mamba_setup
    # <<< mamba initialize <<<
    micromamba activate "/home/brian.matilla/micromamba/envs/wofs-func"
fi

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

if [[ ! -d ${rundir}/${eventdate}/${dadir}/obs_diag ]]; then
    mkdir -p "${rundir}/${eventdate}/${dadir}/obs_diag"
fi
cd "${rundir}/${eventdate}/${dadir}/obs_diag" || exit

start_s=$(date -d "${eventdate} 1515" +%s)
end_s=$(date -d "${eventdate} 0300 1 day" +%s)

for ((s=start_s;s<=end_s;s+=900)); do
    timestr=$(date -d @$s +%H%M)
    datestr=$(date -d @$s +%Y%m%d%H%M)

    echo ""
    echo "Plotting Observation at ${timestr} ..."
    ${show} ${rootdir}/python/plot_dartobs.py -p 1,0 -g ${rundir}/${eventdate}/wofs_mpas/wofs_mpas.grid.nc -r 300 -latlon \
                                     "${rundir}/${eventdate}/${dadir}/${timestr}/obs_seq.final.${datestr}.nc" 2>/dev/null | tee -a "${rundir}/diag.${eventdate}"
    ${show} ${rootdir}/python/plot_dartobs.py -p 78,0 -g ${rundir}/${eventdate}/wofs_mpas/wofs_mpas.grid.nc -r 300 -latlon \
                                     "${rundir}/${eventdate}/${dadir}/${timestr}/obs_seq.final.${datestr}.nc" 2>/dev/null | tee -a "${rundir}/diag.${eventdate}"
done

${show} ${rootdir}/python/plot_dartzig.py ${eventdate} -d ${rundir} -r 300 2>/dev/null | tee -a "${rundir}/diag.${eventdate}"

exit 0
