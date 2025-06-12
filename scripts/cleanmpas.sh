#!/bin/bash

script_dir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
rootdir=$(realpath "$(dirname "${script_dir}")")

mpasworkdir="/scratch/wofs_mpas"
eventdateDF=$(date -u +%Y%m%d%H%M)

# shellcheck disable=SC1091
source "${script_dir}/Common_Utilfuncs.sh"

#-----------------------------------------------------------------------

function usage {
    echo " "
    echo "    USAGE: $0 [options] DATETIME [WORKDIR] [TASK]"
    echo " "
    echo "    PURPOSE: Clean run-time of a MPAS run."
    echo " "
    echo "    DATETIME - Case date and time in YYYYmmdd/YYYYmmddHHMM."
    echo "               YYYYmmdd:     run the task for this event date."
    echo "               YYYYmmddHHMM: run task DA/FCST for one cycle only."
    echo " "
    echo "    WORKDIR  - Top level run_dir for all tasks"
    echo "               Normally, it should contain YYYYmmdd/dacycles{x}; YYYYmmdd/fcst{x}; "
    echo "               FCST/YYYYmmdd{x}; summary_files/YYYYmmdd{x}; image_files/YYYYmmdd{x} etc."
    echo " "
    echo "    TASK     - One or more from [dacycles,fcst,post,mpas,mpasm]"
    echo "               mpas:     Delete run-time file in a MPAS run direcotry"
    echo "               mpasm:    Delete MPAS run-time files for all ensemble members in \"fcst_??\""
    echo "               dacycles: Delete wofs_mpas_??.restart.* at all DA cycles except for the top hour (00)"
    echo "               post:     Delete all summary files for this time"
    echo " "
    echo "    OPTIONS:"
    echo "              -h                  Display this message"
    echo "              -c                  To do the task, otherwise show the command to be run only"
    echo "              -v                  Verbose mode"
    echo "              -f conf_file        Configuration file for this case. Default: \${run_dir}/config.\${eventdate}"
    echo " "
    echo "   DEFAULTS:"
    echo "              eventdate  = $eventdateDF"
    echo "              rootdir    = $rootdir"
    echo "              script_dir = $script_dir"
    echo "              run_dir    = ${mpasworkdir}/run_dirs"
    echo "              post_dir   = ${mpasworkdir}/run_dirs/summary_files"
    echo " "
    echo "                                     -- By Y. Wang (2024.04.19)"
    echo " "
    exit "$1"
}

########################################################################
#
# Handle command line arguments
#
########################################################################

function parse_args {

    declare -Ag args

    #echo "in parse_args: $*"

    while [[ $# -gt 0 ]]; do
        key="$1"

        #echo "in parse_args - key = $key, $*"

        case $key in
            -h)
                usage 0
                ;;
            -c)
                args["show"]=""
                args["askconfirm"]=false
                ;;
            -v)
                args["verb"]=true
                args["pass_args"]+=" $key"
                ;;
            -f)
                args["config_file"]="$2"
                shift
                ;;
            -* )
                echo "Unknown option: $key"
                usage 2
                ;;
            dacycles* | fcst | post | mpas | mpasm )
                args["tasknames"]="${key//,/ }"
                ;;
            * )
                if [[ $key =~ ^[0-9]{12}$ ]]; then
                    eventhour=${key:8:2}
                    if ((10#$eventhour < 12 )); then
                        args["eventdate"]=$(date -u -d "${key:0:8} 1 day ago" +%Y%m%d)
                    else
                        args["eventdate"]=${key:0:8}
                    fi
                    args["runtime"]="${key:8:4}"
                elif [[ $key =~ ^[0-9]{8}$ ]]; then
                    args["eventdate"]=${key}
                elif [[ -d $key ]]; then
                    args["run_dir"]=$(realpath "$key")
                elif [[ -f $key ]]; then
                    args["config_file"]="${key}"
                else
                    echo ""
                    echo "ERROR: unknown argument, get [$key]."
                    usage 3
                fi
                ;;
        esac
        shift # past argument or value
    done
    #echo "in parse_args: ${args['askconfirm']}"
}

########################################################################
#% ARGS

parse_args "$@"

[[ -v args["verb"] ]] && verb=${args["verb"]} || verb=true
[[ -v args["show"] ]] && show=${args["show"]} || show="echo"

[[ -v args["askconfirm"] ]] && askconfirm=${args["askconfirm"]} || askconfirm=true

[[ -v args["run_dir"] ]] && run_dir=${args["run_dir"]} || run_dir="${mpasworkdir}/run_dirs"


if [[ -v args["eventdate"] ]]; then
    eventdate=${args["eventdate"]}
else
    eventdate="${eventdateDF:0:8}"
    eventhour=${eventdateDF:8:2}
    if ((10#$eventhour < 12)); then
        eventdate=$(date -u -d "${eventdate} 1 day ago" +%Y%m%d)
    fi
fi

[[ -v args["tasknames"] ]] && read -r -a tasknames <<< "${args['tasknames']}"  || tasknames=()
[[ -v args["pass_args"] ]] && read -r -a pass_args <<< "${args['pass_args']}"  || pass_args=()    # Pass after confirmation for deleting

if [[ " ${tasknames[*]} " =~ [[:space:]](fcst|dacycles|post)[[:space:]] ]]; then
    if [[ -v args["config_file"] ]]; then
        config_file="${args['config_file']}"

        if [[ "$config_file" =~ "/" ]]; then
            run_dir=$(realpath "$(dirname "${config_file}")")
        else
            config_file="${run_dir}/${config_file}"
        fi

        if [[ ${config_file} =~ config\.([0-9]{8})(.*) ]]; then
            [[ -v args["eventdate"] ]] || eventdate="${BASH_REMATCH[1]}"
            affix="${BASH_REMATCH[2]}"
        else
            echo -e "${RED}ERROR${NC}: Config file ${CYAN}${config_file}${NC} not the right format config.YYYYmmdd[_*]."
            exit 1
        fi
    else
        config_file="${run_dir}/config.${eventdate}"
        affix=""
    fi

    if [[ -f ${config_file} ]]; then
        domname=$(grep '^ *domname=' "${config_file}" | cut -d'=' -f2 | tr -d '"')
        pass_args+=("-f" "${config_file}")
    else
        echo " "
        echo "ERROR: config file - ${config_file} not exist."
        usage 1
    fi
fi

if [[ " ${tasknames[*]} " =~ [[:space:]](fcst|dacycles)[[:space:]] ]]; then
    if [[ -v args["runtime"] ]]; then             # only one time cycle
        runtime=${args["runtime"]}
        jobsubstr=""
        if [[ "$taskname" == "dacycles" ]]; then
            jobsubstr="$jobsubstr except for the top hour"
        fi
        wrksubdir="${args['runtime']}"
        pass_args+=("${eventdate}${runtime}")
    else                                         # All time cycles
        jobsubstr="for all ${taskname} cycles"
        wrksubdir=""
    fi
fi

post_dir=${run_dir}/summary_files
image_dir=${run_dir}/image_files
FCST_dir=${run_dir}/FCST

launch_script=$(realpath $0)

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#% ENTRY

for taskname in "${tasknames[@]}"; do
    echo -e "\n*** Cleaning $taskname in ${run_dir} for ${eventdate} ***\n"

    case $taskname in
    #1. mpas
    mpas )
        [[ ! -v args["run_dir"] ]] && run_dir="$(pwd)"
        [[ ! -v domname ]]         && domname="*"

        if [[ $verb == true ]]; then
            echo "Remove MPAS run-time files in ${run_dir} ..."
        fi

        cd "${run_dir}" || exit 1
        ${show} rm -rf log.{atmosphere,init_atmosphere}.*.{err,out} namelist.output core*
        ${show} rm -rf ./${domname}_??.{diag,history}.*.nc  # *.restart.*
        ${show} rm -rf error.* done.fcst_?? dart_log.{nml,out}
        ${show} rm -rf restart_timestamp ./${domname}_??.restart.*.nc
        echo ""
        ;;

    #2. mpasm
    mpasm )
        [[ ! -v args["run_dir"] ]] && run_dir="$(pwd)"

        if [[ $verb == true ]]; then
            echo "Remove all MPAS ensemble run-time files in ${run_dir} ..."
        fi

        if compgen -G "${run_dir}/fcst_??" > /dev/null; then
            cd "${run_dir}" || exit 1

            for mdir in fcst_??; do
                pass_args+=("-c" "${run_dir}/${mdir}")
                ${launch_script} "${pass_args[@]}" mpas
            done
        else
            echo "ERROR: fcst_?? directories not exist in ${run_dir}."
            echo ""
            exit 1
        fi
        ;;

    #3. dacycles
    dacycles )
        if [[ $verb == true ]]; then
            echo "Remove MPAS restart files in ${run_dir}/${eventdate}/dacycles${affix}/${wrksubdir} ${jobsubstr} ..."
        fi

        echo -e "${LIGHT_RED}INFO${NC}: ${BROWN}${script_dir}/run_dacycles.sh${NC} -f ${config_file} ${LIGHT_BLUE}${eventdate}${runtime}${NC} ${GREEN}clean${NC}" "-c"
        ${show} "${script_dir}/run_dacycles.sh" -f "${config_file}" "${eventdate}${runtime}" clean "-c"

        ;;
    #4. fcst
    fcst )
        if [[ $verb == true ]]; then
            echo "Remove MPAS history/diag files in ${run_dir}/${eventdate}/fcst${affix}/${wrksubdir} ${jobsubstr} ..."
        fi
        echo -e "${LIGHT_RED}INFO${NC}: ${BROWN}${script_dir}/run_fcst.sh${NC} -f ${config_file} ${LIGHT_BLUE}${eventdate}${runtime}${NC} ${GREEN}clean${NC}" "-c"
        ${show} "${script_dir}/run_fcst.sh" -f "${config_file}" "${eventdate}${runtime}" clean "-c"

        ;;
    #5. post
    post )
        #-------------------------------------------------------------------
        cd "${FCST_dir}" || exit 1

        notasks=0
        if [[ -d ${eventdate}${affix} ]]; then
            if [[ $verb == true ]]; then
                echo "Deleting ${eventdate}${affix} FCST files from ${FCST_dir} ..."
            fi
            ((notasks++))

            $show rm -rf "${eventdate}${affix}"
        fi

        #-------------------------------------------------------------------
        cd "${post_dir}" || exit 1

        if [[ -d ${eventdate}${affix} ]]; then
            if [[ $verb == true ]]; then
                echo "Deleting ${eventdate}${affix} Summary files from ${post_dir} ..."
            fi
            ((notasks++))

            $show rm -rf "${eventdate}${affix}"
            $show rm -rf "WOFS_MPAS_config_${eventdate}${affix}.yaml"
        fi

        #-------------------------------------------------------------------
        cd "${image_dir}" || exit 1

        if [[ -d ${eventdate}${affix} ]]; then
            if [[ $verb == true ]]; then
                echo "Deleting Image files ${eventdate}${affix} from ${image_dir} ..."
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
            pass_args+=("-c")
            ${launch_script} "${pass_args[@]}" "${taskname}"
        else
            echo -e "Get ${PURPLE}${doit^^}${NC}, do nothing."
        fi
    fi
done

exit 0
