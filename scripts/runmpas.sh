#!/bin/bash

script_dir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
top_dir=$(realpath "$(dirname "${script_dir}")")
#top_dir="/scratch/ywang/MPAS/gnu/mpas_scripts"

eventdateDF=$(date -u +%Y%m%d)

#
# To run MPAS-WoFS tasks interactively or using at/cron scheduler
#

run_dir=${top_dir}/run_dirs
script_dir=${top_dir}/scripts
post_dir=${top_dir}/wofs_post/wofs/scripts

host="$(hostname)"

#-----------------------------------------------------------------------

function usage {
    echo " "
    echo "    USAGE: $0 [options] DATETIME [TASK]"
    echo " "
    echo "    PURPOSE: Run MPAS-WOFS tasks interactively or using Linux at/cron facility."
    echo " "
    echo "    DATETIME - Case date and time in YYYYmmdd/YYYYmmddHHMM."
    echo "               YYYYmmdd:     run the task for this event date."
    echo "               YYYYmmddHHMM: run task DA/FCST for one cycle only."
    echo "    TASK     - One of [da,fcst,post,plot]"
    echo " "
    echo "    OPTIONS:"
    echo "              -h                  Display this message"
    echo "              -n                  Show command to be run and generate job scripts only"
    echo "              -v                  Verbose mode"
    echo " "
    echo "   DEFAULTS:"
    echo "              eventdt    = $eventdateDF"
    echo "              rootdir    = $top_dir"
    echo "              run_dir    = $run_dir"
    echo "              script_dir = $script_dir"
    echo "              post_dir   = $post_dir"
    echo " "
    echo "                                     -- By Y. Wang (2024.04.17)"
    echo " "
    exit $1
}

########################################################################

show=""
verb=false
eventdate=${eventdateDF}
eventtime=""
cmd=""

#-----------------------------------------------------------------------
#
# Handle command line arguments (override default settings)
#
#-----------------------------------------------------------------------
#% ARGS

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
        -*)
            echo "Unknown option: $key"
            usage 2
            ;;
        da | fcst | post | plot )
            cmd=$key
            ;;
        *)
            if [[ $key =~ ^[0-9]{12}$ ]]; then
                eventtime=${key:8:4}
                eventhour=${key:8:2}
                if [[ $((10#$eventhour)) -lt 12 ]]; then
                    eventdate=$(date -u -d "${key:0:8} 1 day ago" +%Y%m%d)
                else
                    eventdate=${key:0:8}
                fi
            elif [[ $key =~ ^[0-9]{8}$ ]]; then
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

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

case $cmd in
da )
    cd "${script_dir}" || exit 1
    echo "$cmd $eventdate$eventtime in $(pwd)"
    ${show} run_dacycles.sh "${eventdate}${eventtime}" -r |& tee -a "${run_dir}/da.${eventdate}${eventtime}"
    ;;
fcst )
    cd "${script_dir}" || exit 1
    echo "$cmd $eventdate in $(pwd)"
    ${show} run_fcst.sh "${eventdate}${eventtime}" -r -w |& tee -a "${run_dir}/fcst.${eventdate}${eventtime}"
    ;;
post | plot )
    if [[ ! "$host" =~ ^wof-epyc.*$ ]]; then
        echo "ERROR: Please run $cmd on wof-epyc8 only".
        exit 1
    fi

    #if [[ $- != *i* ]]; then
    if [ -t 1 ]; then # "interactive"
        echo "$cmd $eventdate in $(pwd)"
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

    nextdate=$(date -d "${eventdate} 1 day" +%Y%m%d)
    if [[ ! -e "${run_dir}/FCST/${eventdate}/fcst_${nextdate}0300_start" ]]; then
        "${script_dir}/lnmpasfcst.sh" "${eventdate}"
    fi

    cd "${post_dir}" || exit 1
    ${show} time "wofs_${cmd}_summary_files_MPAS.py" "${eventdate}" |& tee -a "${run_dir}/${cmd}.${eventdate}"
    ;;
* )
    echo "Unknown command: $cmd"
    ;;
esac

exit 0

