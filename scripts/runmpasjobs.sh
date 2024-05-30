#!/bin/bash

script_dir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
top_dir=$(realpath "$(dirname "${script_dir}")")
#top_dir="/scratch/ywang/MPAS/gnu/mpas_scripts"

eventdateDF=$(date -u +%Y%m%d%H%M)

#
# To run MPAS-WoFS tasks interactively or using at/cron at background
#

run_dir=${top_dir}/run_dirs
script_dir=${top_dir}/scripts
#post_dir=${top_dir}/wofs_post/wofs/scripts
post_dir="/scratch/ywang/MPAS/gnu/frdd-wofs-post/wofs/scripts"

host="$(hostname)"

#-----------------------------------------------------------------------

function usage {
    echo " "
    echo "    USAGE: $0 [options] DATETIME [TASK]"
    echo " "
    echo "    PURPOSE: Run MPAS-WOFS tasks interactively or using Linux at/cron facility."
    echo "             It will always log the outputs to a file."
    echo " "
    echo "    DATETIME - Case date and time in YYYYmmdd/YYYYmmddHHMM."
    echo "               YYYYmmdd:     run the task for this event date."
    echo "               YYYYmmddHHMM: run task DA/FCST for one cycle only."
    echo "    TASK     - One of [dacycles,fcst,post,plot,diag]"
    echo " "
    echo "    OPTIONS:"
    echo "              -h                  Display this message"
    echo "              -n                  Show command to be run, but not run it"
    echo "              -v                  Verbose mode"
    echo "              -e                  Last time in HHMM format"
    echo "              -x                  Directory affix"
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
    exit "$1"
}

########################################################################

show=""
verb=false
eventdate=${eventdateDF:0:8}
eventhour=${eventdateDF:8:2}
task=""

if [[ $((10#$eventhour)) -lt 12 ]]; then
    eventdate=$(date -u -d "${eventdate} 1 day ago" +%Y%m%d)
fi

runtime="$eventdate"

affix=""
endtime="0300"

noscript=false

#-----------------------------------------------------------------------
#
# Handle command line arguments (override default settings)
#
#-----------------------------------------------------------------------
#% ARGS

saved_args="$*"

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
        -x)
            affix="$2"
            shift
            ;;
        -e)
            endtime="$2"
            shift
            ;;
        -*)
            echo "Unknown option: $key"
            usage 2
            ;;
        dacycles | fcst | post | plot | diag )
            task=$key
            ;;
        noscript )
            noscript=true
            ;;
        *)
            if [[ $key =~ ^[0-9]{12}$ ]]; then
                eventhour=${key:8:2}
                if [[ $((10#$eventhour)) -lt 12 ]]; then
                    eventdate=$(date -u -d "${key:0:8} 1 day ago" +%Y%m%d)
                else
                    eventdate=${key:0:8}
                fi
                runtime="$key"
            elif [[ $key =~ ^[0-9]{8}$ ]]; then
                eventdate=${key}
                runtime=${eventdate}
            else
                echo ""
                echo "ERROR: unknown argument, get [$key]."
                usage 3
            fi
            ;;
    esac
    shift # past argument or value
done

# Load Python environment as needed
case $task in
post | plot | diag )
    if [[ ! "$host" =~ ^wof-epyc.*$ ]]; then
        echo "ERROR: Please run $task on wof-epyc8 only".
        exit 1
    fi

    if [[ -z ${MAMBA_EXE} || ! -t 0 ]]; then   # not set micromamba, load Python environment
        # >>> mamba initialize >>>
        # !! Contents within this block are managed by 'mamba init' !!
        export MAMBA_EXE='/home/yunheng.wang/y/bin/micromamba';
        export MAMBA_ROOT_PREFIX='/home/yunheng.wang/y';
        __mamba_setup="$("$MAMBA_EXE" shell hook --shell bash --root-prefix "$MAMBA_ROOT_PREFIX" 2> /dev/null)"
        # shellcheck disable=SC2181
        if [ $? -eq 0 ]; then
            eval "$__mamba_setup"
        else
            micromamba() { "$MAMBA_EXE"; }  # Fallback on help from mamba activate
        fi
        unset __mamba_setup
        # <<< mamba initialize <<<
        micromamba activate "/home/brian.matilla/micromamba/envs/wofs-func"
    fi
    #echo "Activated Python environment on ${host} ..."

    donepost="${run_dir}/summary_files/${eventdate}/${endtime}/wofs_postswt_${endtime}_finished"
    doneplot="${run_dir}/image_files/${eventdate}_mpasV8.0/${endtime}/wofs_plotpbl_${endtime}_finished"
    ;;
esac

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

log_dir="${run_dir}/${eventdate}"
if [[ ! -d ${log_dir} ]]; then
    echo "ERROR: ${log_dir} not exists."
    exit 1
fi

log_file="${log_dir}/log${affix}.${task}"

if [[ -z $show ]]; then                 # Actually run the task
    if [[ ! -t 1 ]]; then                       # at, batch or cron job
        exec 1>> "${log_file}" 2>&1
    elif [[ ${noscript} == false ]]; then       # interactive
        #exec > >(tee -ia ${log_file} 2>&1
        ## execute self with the noscript special arg so that the second execution DOES NOT start script again.
        script -aefq "${log_file}" -c "$0 noscript ${saved_args}"
        exit $?
    else                                        # interactive
        echo -e "\nLogging to file: ${log_file} ....\n"
    fi
fi

echo "=== $(date +%Y%m%d_%H:%M:%S) - $0 ${saved_args} ==="

case $task in
dacycles )
    cd "${script_dir}" || exit 1
    cmds=("${script_dir}/run_dacycles.sh" -f "config.${eventdate}${affix}" -e "${endtime}" "${runtime}" -r)
    ;;
fcst )
    cd "${script_dir}" || exit 1
    cmds=("${script_dir}/run_fcst.sh" -f "config.${eventdate}${affix}" -e "${endtime}" "${runtime}" -r -w)
    ;;

post )

    if [[ ! -e ${donepost} ]]; then
        # To make sure the correct FCST files are used, "-c"
        "${script_dir}/lnmpasfcst.sh" -fcst "fcst${affix}" -c -e "${endtime}" "${eventdate}"

        cd "${post_dir}" || exit 1
        cmds=(time "./wofs_${task}_summary_files_MPAS.py" "${eventdate}")
    else
        echo "File $donepost exist"
        echo "Please clean them using \"${script_dir}/cleanmpas.sh ${eventdate} post\" before reprocessing."
        exit 1
    fi
    ;;

plot )
    if [[ ! -e ${doneplot} ]]; then
        echo "Waiting for ${run_dir}/summary_files/${eventdate}/${endtime}/wofs_postswt_${endtime}_finished ..."
        while [[ ! -e "${run_dir}/summary_files/${eventdate}/${endtime}/wofs_postswt_${endtime}_finished" ]]; do
            sleep 10
        done

        cd "${post_dir}" || exit 1
        cmds=(time "./wofs_${task}_summary_files_MPAS.py" "${eventdate}")
    else
        echo "File $doneplot exist"
        echo "Please clean them using \"${script_dir}/cleanmpas.sh ${eventdate} post\" before reprocessing."
        exit 2
    fi
    ;;
diag )
    cd "${script_dir}" || exit 1
    cmds=("${script_dir}/plot_allobs.sh" -d "dacycles${affix}" -e "${endtime}" "${eventdate}")
    ;;
* )
    echo "ERROR: Unknown task: $task"
    ;;
esac

if [ -t 1 ]; then # "interactive"
    echo -e "\nInteractivly running: ${task} ${runtime} from $(pwd)\n"
else
    echo -e "\nBackground   running: ${task} ${runtime} from $(pwd)\n"
fi

if [[ $verb == true && -z ${show} ]]; then echo "${cmds[*]}"; fi
${show} "${cmds[@]}"

exit 0
