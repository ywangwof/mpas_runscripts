#!/bin/bash

script_dir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
top_dir=$(realpath "$(dirname "${script_dir}")")

eventdateDF=$(date -u +%Y%m%d%H%M)

run_dir=${top_dir}/run_dirs
script_dir=${top_dir}/scripts
post_dir=${run_dir}/summary_files
image_dir=${run_dir}/image_files
FCST_dir=${run_dir}/FCST

# shellcheck disable=SC1091
source "${script_dir}/Common_Utilfuncs.sh"
#-----------------------------------------------------------------------

function usage {
    echo " "
    echo "    USAGE: $0 [options] DATETIME [TASK]"
    echo " "
    echo "    PURPOSE: Clean run-time of a MPAS run."
    echo " "
    echo "    DATETIME - Case date and time in YYYYmmdd/YYYYmmddHHMM."
    echo "               YYYYmmdd:     run the task for this event date."
    echo "               YYYYmmddHHMM: run task DA/FCST for one cycle only."
    echo "    TASK     - One of [dacycles,fcst,post,mpas,mpasm]"
    echo "               mpas:     Delete run-time file in a MPAS run direcotry"
    echo "               mpasm:    Delete MPAS run-time files for all ensemble members in \"fcst_??\""
    echo "               dacycles: Delete wofs_mpas_??.restart.* at all DA cycles except for the top hour (00)"
    echo "               post:     Delate all summary files for this time"
    echo " "
    echo "    OPTIONS:"
    echo "              -h                  Display this message"
    echo "              -c                  To do the task, otherwise show the command to be run only"
    echo "              -v                  Verbose mode"
    echo "              -r  run_dir         Working directory"
    echo "              -d  wofs_mpas       Domain name to be used"
    echo " "
    echo "   DEFAULTS:"
    echo "              eventdt    = $eventdateDF"
    echo "              rootdir    = $top_dir"
    echo "              run_dir    = $run_dir"
    echo "              script_dir = $script_dir"
    echo "              post_dir   = $post_dir"
    echo " "
    echo "                                     -- By Y. Wang (2024.04.19)"
    echo " "
    exit "$1"
}

########################################################################

show="echo"
verb=true
eventdate=${eventdateDF:0:8}
eventhour=${eventdateDF:8:2}

if [[ $((10#$eventhour)) -lt 12 ]]; then
    eventdate=$(date -u -d "${eventdate} 1 day ago" +%Y%m%d)
fi

runtime=""
domname="wofs_mpas"
taskname=""

#-----------------------------------------------------------------------
#
# Handle command line arguments (override default settings)
#
#-----------------------------------------------------------------------
#% ARGS

#saved_args="$*"

while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
        -h)
            usage 0
            ;;
        -c)
            show=""
            ;;
        -v)
            verb=true
            ;;
        -d)
            domname=$2
            shift
            ;;
        -r)
            run_dir=$2
            shift
            ;;
        -*)
            echo "Unknown option: $key"
            usage 2
            ;;
        dacycles | fcst | post | mpas | mpasm )
            taskname=$key
            ;;
        *)
            if [[ $key =~ ^[0-9]{12}$ ]]; then
                eventhour=${key:8:2}
                if [[ $((10#$eventhour)) -lt 12 ]]; then
                    eventdate=$(date -u -d "${key:0:8} 1 day ago" +%Y%m%d)
                else
                    eventdate=${key:0:8}
                fi
                runtime="${key:8:4}"
            elif [[ $key =~ ^[0-9]{8}$ ]]; then
                eventdate=${key}
                runtime=""
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

if [[ -z ${runtime} ]]; then             # All time cycles
    jobsubstr="for all ${taskname} cycles"
    if [[ "$taskname" == "dacycles" ]]; then
        jobsubstr="$jobsubstr except for the top hour"
    fi
    wrksubdir=""
else                                     # only one time cycle
    jobsubstr=""
    wrksubdir="${runtime}"
fi

case $taskname in
mpas )
    if [[ $verb == true ]]; then
        echo "Remove MPAS run-time files in ${run_dir} ..."
    fi

    cd "${run_dir}" || usage 1
    ${show} rm -rf log.{atmosphere,init_atmosphere}.*.{err,out} namelist.output core*
    ${show} rm -rf ./"${domname}"_??.{diag,history}.*.nc  # *.restart.*
    ${show} rm -rf error.* done.fcst_?? dart_log.{nml,out}
    echo ""
    ;;
mpasm )
    if [[ $verb == true ]]; then
        echo "Remove all MPAS ensemble run-time files in ${run_dir} ..."
    fi

    cd "${run_dir}" || usage 1
    for mdir in fcst_??; do
        $0 -r "${run_dir}/${mdir}" mpas
    done
    ;;

dacycles )
    if [[ $verb == true ]]; then
        echo "Remove MPAS restart files in ${run_dir}/${eventdate}/dacycles/${wrksubdir} ${jobsubstr} ..."
    fi

    show="echo"
    echo -e "${LIGHT_RED}WARNING${NC}: Please use ${BROWN}${script_dir}/run_dacycles.sh${NC} ${LIGHT_BLUE}${eventdate}${runtime}${NC} ${GREEN}clean${NC} for this task"

    cd "${run_dir}/${eventdate}/dacycles/${wrksubdir}" || usage 1
    if [[ -z ${runtime} ]]; then             # All time cycles
        $show find ./??[134]? -name "${domname}_??.{restart,diag,history}.*" -exec rm {} \;
        $show find ./??[134]? -name "${domname}_??.analysis" -exec rm {} \;
        $show find ./??[134]? -name "preassim_*.nc" -exec rm {} \;
        $show find ./??[134]? -name "output_*.nc" -exec rm {} \;
    else
        $show find . -name "${domname}_??.{restart,diag,history}.*" -exec rm {} \;
        $show find . -name "${domname}_??.analysis" -exec rm {} \;
        $show find . -name "preassim_*.nc" -exec rm {} \;
        $show find . -name "output_*.nc" -exec rm {} \;
    fi
    ;;
fcst )
    if [[ $verb == true ]]; then
        echo "Remove MPAS history/diag files in ${run_dir}/${eventdate}fcst/${wrksubdir} ${jobsubstr} ..."
    fi
    show="echo"
    echo -e "${LIGHT_RED}WARNING${NC}: Please use ${BROWN}${script_dir}/run_fcst.sh${NC} ${LIGHT_BLUE}${eventdate}${runtime}${NC} ${GREEN}clean${NC} for this task"

    cd "${run_dir}/${eventdate}/fcst/${wrksubdir}" || usage 1
    $show find . -name "wofs_mpas_??.{history,diag}.*" -exec rm {} \;
    ;;
post )
    #-------------------------------------------------------------------
    if [[ $verb == true ]]; then
        echo "Delete FCST ${eventdate} files from ${FCST_dir} ..."
    fi

    cd "${FCST_dir}" || usage 1
    $show rm -rf "${eventdate}"

    #-------------------------------------------------------------------
    if [[ $verb == true ]]; then
        echo "Delete Summary files ${eventdate} from ${post_dir} ..."
    fi

    cd "${post_dir}" || usage 1
    $show rm -rf "${eventdate}"

    #-------------------------------------------------------------------
    if [[ $verb == true ]]; then
        echo "Delete Image files ${eventdate}_mpasV8.0 from ${image_dir} ..."
    fi

    cd "${image_dir}" || usage 1
    $show rm -rf "${eventdate}_mpasV8.0"

    ;;
* )
    echo "ERROR: unsuported task: \"${taskname}\"."
    usage 2
    ;;
esac

exit 0
