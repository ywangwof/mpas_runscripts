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
post_dir=${top_dir}/wofs_post/wofs/scripts
#post_dir="/scratch/ywang/MPAS/gnu/frdd-wofs-post/wofs/scripts"

host="$(hostname)"

#-----------------------------------------------------------------------

# Black        0;30     Dark Gray     1;30
# Red          0;31     Light Red     1;31
# Green        0;32     Light Green   1;32
# Brown/Orange 0;33     Yellow        1;33
# Blue         0;34     Light Blue    1;34
# Purple       0;35     Light Purple  1;35
# Cyan         0;36     Light Cyan    1;36
# Light Gray   0;37     White         1;37
# ---------- constant part!

# shellcheck disable=SC2034
#if [ -t 1 ]; then
    NC='\033[0m'            # No Color
    BLACK='\033[0;30m';     DARK='\033[1;30m'
    RED='\033[0;31m';       LIGHT_RED='\033[1;31m'
    GREEN='\033[0;32m';     LIGHT_GREEN='\033[1;32m'
    BROWN='\033[0;33m';     YELLOW='\033[1;33m'
    BLUE='\033[0;34m';      LIGHT_BLUE='\033[1;34m'
    PURPLE='\033[0;35m';    LIGHT_PURPLE='\033[1;35m'
    CYAN='\033[0;36m';      LIGHT_CYAN='\033[1;36m'
    LIGHT='\033[0;37m';     WHITE='\033[1;37m'

    DIR_CLR='\033[0;97;44m'; DIRa_CLR='\033[0;95;44m';
#else
#    NC=''
#    BLACK='';     DARK=''
#    RED='';       LIGHT_RED=''
#    GREEN='';     LIGHT_GREEN=''
#    BROWN='';     YELLOW=''
#    BLUE='';      LIGHT_BLUE=''
#    PURPLE='';    LIGHT_PURPLE=''
#    CYAN='';      LIGHT_CYAN=''
#    LIGHT='';     WHITE=''
#fi
#    vvvv vvvv -- EXAMPLES -- vvvv vvvv
# echo -e "I ${RED}love${NC} Stack Overflow"
# printf "I ${RED}love${NC} Stack Overflow\n"
#

#-----------------------------------------------------------------------

function usage {
    echo    " "
    echo    "    USAGE: $0 [options] [DATETIME] [WORKDIR] [TASK]"
    echo    " "
    echo    "    PURPOSE: Run MPAS-WOFS tasks interactively or using Linux at/cron facility."
    echo    "             It will always log the outputs to a file."
    echo    " "
    echo    "    DATETIME - Case date and time in YYYYmmdd/YYYYmmddHHMM."
    echo    "               YYYYmmdd:     run the task for this event date."
    echo    "               YYYYmmddHHMM: run task DA/FCST for one cycle only."
    echo -e "    WORKDIR  - Top level ${LIGHT_BLUE}run_dir${NC} for all tasks"
    echo -e "               Normally, it has ${DIR_CLR}YYYYmmdd/dacycles${DIRa_CLR}{x}${NC}; ${DIR_CLR}YYYYmmdd/fcst${DIRa_CLR}{x}${NC}; "
    echo -e "               ${DIR_CLR}FCST/YYYYmmdd${DIRa_CLR}{x}${NC}; ${DIR_CLR}summary_files/YYYYmmdd${DIRa_CLR}{x}${NC}; ${DIR_CLR}image_files/YYYYmmdd${DIRa_CLR}{x}${NC} etc."
    echo -e "    TASK     - One of [${YELLOW}dacycles${NC},${YELLOW}fcst${NC},${YELLOW}post${NC},${YELLOW}plot${NC},${YELLOW}diag${NC},${YELLOW}verif${NC}]"
    echo    " "
    echo    "    OPTIONS:"
    echo    "              -h                  Display this message"
    echo    "              -n                  Show command to be run, but not run it"
    echo    "              -nn                 Show command to be run (one level deeper), but not run it"
    echo    "              -v                  Verbose mode"
    echo    "              -e                  Last time in HHMM format"
    echo    "              -x                  Directory affix"
    echo    " "
    echo    "   DEFAULTS:"
    echo    "              eventdt    = $eventdateDF"
    echo    "              rootdir    = $top_dir"
    echo    "              run_dir    = $run_dir"
    echo    "              script_dir = $script_dir"
    echo    "              post_dir   = $post_dir"
    echo    " "
    echo    "                                     -- By Y. Wang (2024.04.17)"
    echo    " "
    exit    "$1"
}

########################################################################

show=""
verb=false
eventdate=${eventdateDF:0:8}
eventhour=${eventdateDF:8:2}
task=""
taskopt=""

if ((10#$eventhour < 12)); then
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
        -nn)
            taskopt="-n"
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
            echo -e "${RED}ERROR${NC}: Unknown option: ${YELLOW}$key${NC}"
            usage 2
            ;;
        dacycles | fcst | post | plot | diag | verif)
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
            elif [[ -d $key ]]; then
                run_dir=$key
            else
                echo ""
                echo -e "${RED}ERROR${NC}: unknown argument, get [${YELLOW}$key${NC}]."
                usage 3
            fi
            ;;
    esac
    shift # past argument or value
done

# Load Python environment as needed
case $task in
post | plot | diag | verif)
    if [[ ! "$host" =~ ^wof-epyc.*$ ]]; then
        echo -e "${RED}ERROR${NC}: Please run ${BROWN}$task${NC} on wof-epyc8 only".
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

    donepost="${run_dir}/summary_files/${eventdate}${affix}/${endtime}/wofs_postswt_${endtime}_finished"
    doneplot="${run_dir}/image_files/flags/${eventdate}${affix}/${endtime}/wofs_plotpbl_${endtime}_finished"
    doneverif="${run_dir}/image_files/flags/${eventdate}${affix}/wofs_plotwwa_${endtime}_finished"
    ;;
esac

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

log_dir="${run_dir}/${eventdate}"
if [[ ! -d ${log_dir} ]]; then
    echo -e "${RED}ERROR${NC}: ${PURPLE}${log_dir}${NC} not exists."
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
        echo -e "\n${DARK}Logging to file: ${CYAN}${log_file}${NC} ....\n"
    fi
fi

echo -e "${YELLOW}===${NC} ${PURPLE}$(date +%Y%m%d_%H:%M:%S)${NC} - ${BROWN}$0 ${saved_args}${NC} ${YELLOW}===${NC}"

case $task in
#1. dacycles
dacycles )
    cd "${script_dir}" || exit 1
    cmds=("${script_dir}/run_dacycles.sh" -f "config.${eventdate}${affix}" -e "${endtime}" "${runtime}" -r)
    if [[ -n "${taskopt}" ]]; then cmds+=("${taskopt}"); fi
    ;;
#2. fcst
fcst )
    cd "${script_dir}" || exit 1
    cmds=("${script_dir}/run_fcst.sh" -f "config.${eventdate}${affix}" -e "${endtime}" "${runtime}" -r -w)
    if [[ -n "${taskopt}" ]]; then cmds+=("${taskopt}"); fi
    ;;

#3. post
post )

    if [[ ! -e ${donepost} ]]; then
        if ((10#$endtime < 1200)); then
            enddate=$(date -d "$eventdate 1 day" +%Y%m%d)
        else
            enddate=${eventdate}
        fi
        if [[ ! -e ${run_dir}/FCST/${eventdate}${affix}/fcst_${enddate}${endtime}_start ]]; then
            # To make sure the correct FCST files are used, "-c"
            cmds=("${script_dir}/lnmpasfcst.sh" -c -e "${endtime}")
            if [[ -n ${affix} ]]; then
                cmds+=(-x "${affix}")
            fi
            cmds+=("${eventdate}")
            ${show} "${cmds[@]}"
        fi

        cd "${post_dir}" || exit 1
        cmds=(time "./wofs_${task}_summary_files_MPAS.py" "${eventdate}")
        if [[ -n ${affix} ]]; then
            cmds+=("${affix}")
        fi
    else
        echo -e "${DARK}File ${CYAN}$donepost${NC} exist"
        echo -e "${DARK}Please clean them using ${GREEN}${script_dir}/cleanmpas.sh ${eventdate} post${NC} before reprocessing."
        exit 1
    fi
    ;;

#4. plot
plot )
    if [[ ! -e ${doneplot} ]]; then
        echo -e "${DARK}Waiting for ${CYAN}${donepost}${NC} ...."
        while [[ ! -e "${donepost}" ]]; do
            sleep 10
        done

        cd "${post_dir}" || exit 1
        cmds=(time "./wofs_${task}_summary_files_MPAS.py" "${eventdate}")
        if [[ -n ${affix} ]]; then
            cmds+=("${affix}")
        fi
    else
        echo -e "${DARK}File ${CYAN}$doneplot${NC} exist"
        echo -e "${DARK}Please clean them using ${GREEN}${script_dir}/cleanmpas.sh ${eventdate} post${NC} before reprocessing."
        exit 2
    fi
    ;;
#5. verif
verif )
    if [[ ! -e ${doneverif} ]]; then
        echo -e "${DARK}Waiting for ${donepost} ...."
        while [[ ! -e "${donepost}" ]]; do
            sleep 10
        done

        cd "${post_dir}" || exit 1
        cmds=(time "./wofs_plot_verification_MPAS.py" "${eventdate}")
        if [[ -n ${affix} ]]; then
            cmds+=("${affix}")
        fi
    else
        echo -e "${DARK}File ${CYAN}$doneverif${NC} exist"
        echo -e "${DARK}Please clean them using ${GREEN}${script_dir}/cleanmpas.sh ${eventdate} post${NC} before reprocessing."
        exit 2
    fi
    ;;
#6. diag
diag )
    cd "${script_dir}" || exit 1
    cmds=("${script_dir}/plot_allobs.sh" -e "${endtime}" "${eventdate}")
    if [[ -n "${affix}" ]];   then cmds+=(-x "${affix}"); fi
    if [[ -n "${taskopt}" ]]; then cmds+=("${taskopt}");  fi

    ;;
* )
    echo -e "${RED}ERROR${NC}: Unknown task - ${PURPLE}$task${NC}"
    exit 3
    ;;
esac

if [ -t 1 ]; then # "interactive"
    echo -e "\n${DARK}Interactivly running: ${BROWN}${task}${NC} ${LIGHT_BLUE}${runtime}${NC} from ${YELLOW}$(pwd)${NC} at ${PURPLE}$(date '+%Y%m%d_%H:%M:%S(%Z)')${NC}\n"
else
    echo -e "\n${DARK}Background   running: ${BROWN}${task}${NC} ${LIGHT_BLUE}${runtime}${NC} from ${BLYELLOWUE}$(pwd)${NC} at ${PURPLE}$(date '+%Y%m%d_%H:%M:%S(%Z)')${NC}\n"
fi

if [[ -z ${show} ]]; then echo -e "${GREEN}${cmds[*]}${NC}"; fi
${show} "${cmds[@]}"

exit 0
