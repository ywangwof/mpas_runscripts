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
    echo "    TASK     - One or more from [dacycles,fcst,post,mpas,mpasm]"
    echo "               mpas:     Delete run-time file in a MPAS run direcotry"
    echo "               mpasm:    Delete MPAS run-time files for all ensemble members in \"fcst_??\""
    echo "               dacycles: Delete wofs_mpas_??.restart.* at all DA cycles except for the top hour (00)"
    echo "               post:     Delate all summary files for this time"
    echo " "
    echo "    OPTIONS:"
    echo "              -h                  Display this message"
    echo "              -c                  To do the task, otherwise show the command to be run only"
    echo "              -v                  Verbose mode"
    echo "              -x                  Directory affix. Defaut: empty"
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
    askconfirm=false
    exit "$1"
}

########################################################################

askconfirm=true
show="echo"
verb=true
eventdate=${eventdateDF:0:8}
eventhour=${eventdateDF:8:2}

if [[ $((10#$eventhour)) -lt 12 ]]; then
    eventdate=$(date -u -d "${eventdate} 1 day ago" +%Y%m%d)
fi

runtime=""
domname="wofs_mpas"
tasknames=()
affix=""

#-----------------------------------------------------------------------
#
# Handle command line arguments (override default settings)
#
#-----------------------------------------------------------------------
#% ARGS

saved_args=()          # Pass after confirmation for deleting
pass_args=()           # Pass to each member for \"mpasm\"

while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
        -h)
            usage 0
            ;;
        -c)
            show=""
            pass_args+=("$key")
            ;;
        -v)
            verb=true
            pass_args+=("$key")
            ;;
        -noask)
            askconfirm=false
            ;;
        -d)
            domname=$2
            pass_args+=("$key" "$2")
            shift
            ;;
        -r)
            run_dir=$(realpath "$2")
            saved_args+=("$key" "${run_dir}")
            shift
            ;;
        -x)
            affix="$2"
            saved_args+=("$key" "${affix}")
            shift
            ;;
        -*)
            echo "Unknown option: $key"
            usage 2
            ;;
        dacycles* | fcst* | post* | mpas | mpasm )
            IFS="," read -r -a tasknames <<< "$key"
            #saved_args+=("${key}")
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
            pass_args+=("$key")
            ;;
    esac
    shift # past argument or value
done

saved_args+=("${pass_args[@]}")
if [[ -z $show ]]; then
    askconfirm=false
fi

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#% ENTRY

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

for taskname in "${tasknames[@]}"; do
    echo -e "\n*** Cleaning $taskname in ${run_dir} for ${eventdate} ***\n"

    case $taskname in
    #1. mpas
    mpas )
        if [[ $verb == true ]]; then
            echo "Remove MPAS run-time files in ${run_dir} ..."
        fi

        cd "${run_dir}" || exit 1
        ${show} rm -rf log.{atmosphere,init_atmosphere}.*.{err,out} namelist.output core*
        ${show} rm -rf ./"${domname}"_??.{diag,history}.*.nc  # *.restart.*
        ${show} rm -rf error.* done.fcst_?? dart_log.{nml,out}
        ${show} rm -rf restart_timestamp ./"${domname}"_??.restart.*.nc
        echo ""
        ;;
    #2. mpasm
    mpasm )
        if [[ $verb == true ]]; then
            echo "Remove all MPAS ensemble run-time files in ${run_dir} ..."
        fi

        cd "${run_dir}" || exit 1
        for mdir in fcst_??; do
            mpas_args=("${pass_args[@]}")
            mpas_args+=("-noask" "-r" "${run_dir}/${mdir}" "mpas")
            $0 "${mpas_args[@]}"
        done
        ;;

    #3. dacycles
    dacycles )
        if [[ $verb == true ]]; then
            echo "Remove MPAS restart files in ${run_dir}/${eventdate}/dacycles${affix}/${wrksubdir} ${jobsubstr} ..."
        fi

        show="echo"
        askconfirm=false
        echo -e "${LIGHT_RED}INFO${NC}: ${BROWN}${script_dir}/run_dacycles.sh${NC} ${LIGHT_BLUE}${eventdate}${runtime}${NC} ${run_dir} ${GREEN}clean${NC} -c "

        ${script_dir}/run_dacycles.sh -f config.${eventdate}${affix} ${eventdate} ${run_dir} clean -c

        #cd "${run_dir}/${eventdate}/dacycles${affix}/${wrksubdir}" || exit 1
        #if [[ -z ${runtime} ]]; then             # All time cycles
        #    $show find ./??[134]? -name "${domname}_??.{restart,diag,history}.*" -exec rm {} \;
        #    $show find ./??[134]? -name "${domname}_??.analysis" -exec rm {} \;
        #    $show find ./??[134]? -name "preassim_*.nc" -exec rm {} \;
        #    $show find ./??[134]? -name "output_*.nc" -exec rm {} \;
        #else
        #    $show find . -name "${domname}_??.{restart,diag,history}.*" -exec rm {} \;
        #    $show find . -name "${domname}_??.analysis" -exec rm {} \;
        #    $show find . -name "preassim_*.nc" -exec rm {} \;
        #    $show find . -name "output_*.nc" -exec rm {} \;
        #fi
        ;;
    #4. fcst
    fcst )
        if [[ $verb == true ]]; then
            echo "Remove MPAS history/diag files in ${run_dir}/${eventdate}/fcst${affix}/${wrksubdir} ${jobsubstr} ..."
        fi
        show="echo"
        askconfirm=false
        echo -e "${LIGHT_RED}INFO${NC}: ${BROWN}${script_dir}/run_fcst.sh${NC} ${LIGHT_BLUE}${eventdate}${runtime}${NC} ${run_dir} ${GREEN}clean${NC} -c"

        ${script_dir}/run_fcst.sh -f config.${eventdate}${affix} ${eventdate} ${run_dir} clean -c

        #cd "${run_dir}/${eventdate}/fcst${affix}/${wrksubdir}" || exit 1
        #$show find . -name "wofs_mpas_??.{history,diag}.*" -exec rm {} \;
        ;;
    #5. post
    post )
        #-------------------------------------------------------------------
        cd "${FCST_dir}" || exit 1

        notasks=0
        if [[ -d ${eventdate}${affix} ]]; then
            if [[ $verb == true ]]; then
                echo "Delete ${eventdate}${affix} FCST files from ${FCST_dir} ..."
            fi
            ((notasks++))

            $show rm -rf "${eventdate}${affix}"
        fi

        #-------------------------------------------------------------------
        cd "${post_dir}" || exit 1

        if [[ -d ${eventdate}${affix} ]]; then
            if [[ $verb == true ]]; then
                echo "Delete ${eventdate}${affix} Summary files from ${post_dir} ..."
            fi
            ((notasks++))

            $show rm -rf "${eventdate}${affix}"
        fi

        #-------------------------------------------------------------------
        cd "${image_dir}" || exit 1

        if [[ -d ${eventdate}${affix} ]]; then
            if [[ $verb == true ]]; then
                echo "Delete Image files ${eventdate}${affix} from ${image_dir} ..."
            fi
            ((notasks++))

            $show rm -rf "${eventdate}${affix}"
            $show rm -rf "flags/${eventdate}${affix}"
        fi

        if [[ $notasks -eq 0 && $askconfirm == true ]]; then
            askconfirm=false
        fi
        ;;
    * )
        echo "ERROR: unsuported task: \"${taskname}\"."
        usage 2
        ;;
    esac

    #6. confirm
    if [[ $askconfirm == true ]]; then
        echo -ne  "\n${BROWN}WARNING${NC}: Do you want to execute the tasks. [${YELLOW}YES,NO${NC}]? "
        read -r doit
        if [[ ${doit^^} == "YES" ]]; then
            echo -e "${BROWN}WARNING${NC}: Cleaning in process ...\n"
            saved_args+=("-c" "-noask")
            $0 "${saved_args[@]}" taskname
        else
            echo -e "Get ${PURPLE}${doit^^}${NC}, do nothing."
        fi
    fi
done

exit 0
