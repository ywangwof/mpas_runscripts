#!/bin/bash
# shellcheck disable=SC2034

script_dir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
rootdir=$(realpath "$(dirname "${script_dir}")")

MPASdir=$(dirname $(dirname "$rootdir"))

mpasworkdir="/scratch/wofs_mpas"
eventdateDF=$(date -u +%Y%m%d%H%M)

#
# To run MPAS-WoFS tasks interactively or using at/cron at background
#

post_dir=${MPASdir}/frdd-wofs-post
script_dir=${rootdir}/scripts

host="$(hostname)"

default_endtime="0300"
default_datime="1500"
default_fcsttime="1700"

#-----------------------------------------------------------------------

source "$script_dir/Common_Colors.sh"

########################################################################

function usage {
    echo    " "
    echo    "    USAGE: $0 [options] [DATETIME] [WORKDIR] [CONFIG] [TASK]"
    echo    " "
    echo    "    PURPOSE: Run MPAS-WOFS tasks interactively or using Linux at/cron facility."
    # shellcheck disable=SC2154
    echo -e "             It will log the outputs to a file as ${LIGHT_BLUE}\${WORKDIR}${NC}/${DIR_CLR}\${EVENTDATE}${NC}/log${DIRa_CLR}\${affix}${NC}.${YELLOW}\${task}${NC} automatically."
    echo    " "
    echo    "    DATETIME - Event date as YYYYmmdd."
    echo    " "
    echo -e "    WORKDIR  - Top level ${LIGHT_BLUE}run_dir${NC} for all tasks. Generally, it should contain these folders:"
    echo -e "                   ${DIR_CLR}\${EVENTDATE}${NC}/{${WHITE}dacycles${NC},${WHITE}fcst${NC}}${DIRa_CLR}\${affix}${NC}"
    echo -e "                   {${WHITE}FCST${NC},${WHITE}summary_files${NC},${WHITE}image_files${NC}}/${DIR_CLR}\${EVENTDATE}${DIRa_CLR}\${affix}${NC}"
    echo    ""
    echo    "    CONFIG   - MPAS-WoFS runtime configuration file with full path."
    echo    "               WORKDIR & DATETIME will be extracted from the CONFIG name unless they are given explicitly."
    echo -e "    TASK     - One of [${YELLOW}dacycles${NC},${YELLOW}fcst${NC},${YELLOW}post${NC},${YELLOW}plot${NC},${YELLOW}diag${NC},${YELLOW}verif${NC},${YELLOW}snd${NC},${BROWN}atpost${NC}]"
    echo    " "
    echo    "    OPTIONS:"
    echo    "              -h                  Display this message"
    echo    "              -n                  Show command to be run, but not run it"
    echo    "              -nn                 Show command to be run (one level deeper), but not run it"
    echo    "              -v                  Verbose mode"
    echo    "              -s  HHMM            Start time in HHMM format or YYYYmmddHHMM."
    echo    "              -e  HHMM            Last time in HHMM format or YYYYmmddHHMM."
    echo    "              -f  conf_file       Configuration file for this case. Default: \${WORKDIR}/config.\${eventdate}"
    echo -e "              -t  launchtime      Date and time to launch the first task for task ${BROWN}atpost${NC}, as ${LIGHT_BLUE}HH:MM${NC} or ${LIGHT_BLUE}HH:MM mmddyy${NC}"
    echo -e "              -p  machine         Post-processing machine, default: ${PURPLE}wof-epyc8${NC}."
    echo    " "
    echo    "   DEFAULTS:"
    echo -e "              EVENTDATE  = ${DIR_CLR}${eventdateDF:0:8}$NC"
    echo -e "              WORKDIR    = ${LIGHT_BLUE}${mpasworkdir}/run_dir${NC}"
    echo    "              rootdir    = $rootdir"
    echo    "              script_dir = $script_dir"
    echo    "              post_dir   = $post_dir"
    echo    " "
    echo    "                                     -- By Y. Wang (2024.04.17)"
    echo    " "
    exit    "$1"
}

########################################################################
#
# Handle command line arguments
#
########################################################################

function parse_args {

    declare -gA args

    while [[ $# -gt 0 ]]; do
        key="$1"

        case $key in
            -h )
                usage 0
                ;;
            -n )
                args["show"]="echo"
                ;;
            -nn )
                args["taskopt"]="-n"
                ;;
            -v )
                args["verb"]=true
                ;;
            -f )
                args["config_file"]="$2"
                shift
                ;;
            -s )
                args["starttime"]="$2"
                shift
                ;;
            -e )
                args["endtime"]="$2"
                shift
                ;;
            -t )
                if [[ $2 =~ ^[0-9:]+$ || "$2" == "now" ]]; then
                    args["launchtime"]+="${2}"
                else
                    echo ""
                    echo -e "${RED}ERROR${NC}: unknown argument, get ${YELLOW}$2${NC}."
                    usage 3
                fi
                shift
                ;;
            -p )
                args["post_machine"]="$2"
                shift
                ;;
            -* )
                echo -e "${RED}ERROR${NC}: Unknown option: ${YELLOW}$key${NC}"
                usage 2
                ;;
            dacycles | fcst | post | plot | diag | verif | snd | atpost )
                args["task"]=$key
                ;;
            noscript )
                args["noscript"]=true
                ;;
            * )
                if [[ $key =~ ^[0-9]{8}$ ]]; then
                    args["eventdate"]="${key}"
                elif [[ -d $key ]]; then
                    args["run_dir"]="${key}"
                elif [[ -f $key ]]; then
                    args["config_file"]="${key}"
                else
                    echo ""
                    echo -e "${RED}ERROR${NC}: unknown argument, get [${YELLOW}$key${NC}]."
                    usage 3
                fi
                ;;
        esac
        shift # past argument or value
    done
}

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#
#@ MAIN entry
#
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#% ARGS

saved_args="$*"

parse_args "$@"

[[ -v args["verb"] ]]     && verb=${args["verb"]}         || verb=false
[[ -v args["show"] ]]     && show=${args["show"]}         || show=""

[[ -v args["taskopt"] ]]  && taskopt=${args["taskopt"]}   || taskopt=""
[[ -v args["task"] ]]     && task=${args["task"]}         || task=""

[[ -v args["noscript"] ]] && noscript=${args["noscript"]} || noscript=false

[[ -v args["launchtime"] ]]   && launchtime=${args["launchtime"]}     || launchtime="18:00"
[[ -v args["post_machine"] ]] && post_machine=${args["post_machine"]} || post_machine="wof-epyc8"


if [[ -v args["eventdate"] ]]; then
    eventdate=${args["eventdate"]}
else
    eventdate=${eventdateDF:0:8}
    eventhour=${eventdateDF:8:2}

    if ((10#$eventhour < 12)); then
        eventdate=$(date -u -d "${eventdate} 1 day ago" +%Y%m%d)
    fi
fi

[[ -v args["endtime"] ]]   && endtime=${args["endtime"]}     || endtime="${default_endtime}"
[[ -v args["starttime"] ]] && starttime=${args["starttime"]}
[[ -v args["run_dir"] ]]   && run_dir=${args["run_dir"]}     || run_dir="${mpasworkdir}/run_dirs"

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
    elif [[ ${config_file} =~ config\.(.*)$ ]]; then
        affix="_${BASH_REMATCH[1]}"
    else
        echo -e "${RED}ERROR${NC}: Config file ${CYAN}${config_file}${NC} not the right format config.YYYYmmdd[_*]."
        exit 1
    fi
else
    config_file="${run_dir}/config.${eventdate}"
    affix=""
fi

if [[ -f ${config_file} ]]; then
    fcstlength=$(grep '^ *fcst_length_seconds=' "${config_file}" | cut -d'=' -f2 | cut -d' ' -f1 | tr -d '(')
    fcstoutinvl=$(grep '^ *OUTINVL=' "${config_file}" | cut -d'=' -f2)
    level_file=$(grep '^ *vertLevel_file='      "${config_file}" | cut -d'=' -f2 | tr -d '"')
    domain_name=$(grep '^ *domname='      "${config_file}" | cut -d'=' -f2 | tr -d '"')
    wof_domain_name="geo_${domain_name##*_}"
else
    echo " "
    echo -e "${RED}ERROR${NC}: Config file ${CYAN}${config_file}${NC} not exist."
    usage 1
fi

if [[ -z ${starttime} ]]; then
    if [[ "${task}" == "dacycles" ]]; then
        starttime="${default_datime}"
    else
        starttime="${default_fcsttime}"
    fi
fi

#-----------------------------------------------------------------------
# Set Event End Date and Time
#-----------------------------------------------------------------------

nextdate=$(date -u -d "${eventdate} 1 day" +%Y%m%d)

if [[ ${#starttime} -eq 12 ]]; then
    startdatetime=${starttime}
    starttime=${starttime:8:4}
else
    (( 10#$starttime < default_datime )) && startdatetime="${nextdate}${starttime}" || startdatetime="${eventdate}${starttime}"
fi

if [[ ${#endtime} -eq 12 ]]; then
    enddatetime=${endtime}
    endtime=${endtime:8:4}
else
    (( 10#$endtime < default_datime )) && enddatetime="${nextdate}${endtime}" || enddatetime="${eventdate}${endtime}"
fi

#-----------------------------------------------------------------------
#
# Handle the logging mechanism, after we get these variables:
#        ${run_dir},${eventdate}, ${affix}, ${task} etc.
#
#-----------------------------------------------------------------------
#% LOG

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
        #exec > >(tee -ia ${log_file}) 2>&1
        ## execute self with the noscript special arg so that the second execution DOES NOT start script again.
        script -aefq "${log_file}" -c "$0 noscript ${saved_args}"
        exit $?
    else                                        # interactive
        echo -e "\n${DARK}Logging to file: ${CYAN}${log_file}${NC} ....\n"
    fi
fi

########################################################################

# Load Python environment as needed
case $task in
post | plot | diag | verif | snd )
    if [[ ! "${host}" == ${post_machine}* ]]; then
        echo -e "${RED}ERROR${NC}: Please run ${BROWN}$task${NC} on ${post_machine} only".
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
    donesnd="${run_dir}/image_files/flags/${eventdate}${affix}/wofs_postsnd_${endtime}_finished"

    post_script_dir="${MPASdir}/frdd-wofs-post/wofs/scripts"
    post_config_orig="${MPASdir}/frdd-wofs-post/conf/WOFS_MPAS_config.yaml"

    dt=$(( fcstoutinvl/60 ))
    nt=$(( fcstlength/fcstoutinvl ))
    case ${fcstlength} in
    21600 )
        qpe_mode_string="['qpe_15m', 'qpe_1hr', 'qpe_3hr', 'qpe_6hr']"
        ;;
    10800 )
        qpe_mode_string="['qpe_15m', 'qpe_1hr', 'qpe_3hr']"
        ;;
    * )
        echo -e "${RED}ERROR${NC}: fcstlength = ${PURPLE}${fcstlength}${NC} is not supported."
        exit 1
        ;;
    esac

    post_config="${run_dir}/summary_files/WOFS_MPAS_config_${eventdate}${affix}.yaml"
    #rm -f "${post_config}"

    if [[ ! -f "${post_config}" ]]; then
        fbeg_s=$(date -u -d "${startdatetime:0:8} ${startdatetime:8:4}" +%s)
        fbeg_e=$(date -u -d "${enddatetime:0:8}   ${enddatetime:8:4}"   +%s)

        fcst_times=""
        for ((ftime=fbeg_s;ftime<=fbeg_e;ftime+=3600)); do
            fcst_time=$(date -u -d @$ftime +%H%M)
            fcst_times+=" '${fcst_time}',"
        done

        if [[ ! -f "${level_file}" ]]; then
            level_file="/scratch/${level_file}"
        fi
        if [[ ! -f "${level_file}" ]]; then
            echo -e "${RED}ERROR${NC}: Vertical level file - ${CYAN}${level_file}${NC} not exist."
            exit 1
        fi

        num_levels=$(wc -l "${level_file}"| cut -d' ' -f1)
        (( num_levels -= 1 ))

        # modify the configuration file
        sedfile=$(mktemp -t post.sed_XXXX)
        cat << EOF > "${sedfile}"
/^rundate :/s/: .*/: '${eventdate}'/
/^date_ext :/s/: .*/: '${affix}'/
/^process_times :/s/: .*/: [${fcst_times%,} ]/
/^domain_name :/s/: .*/: '${wof_domain_name}'/
/^nt :/s/: .*/: $nt/
/^dt :/s/: .*/: $dt/
/^fcstinterval :/s/: .*/: $dt/
/^vert_levels :/s/: .*/: ${num_levels}/
/^fcstpath: /s#: .*#: ${run_dir}/FCST/#
/^sumpath: /s#: .*#: ${run_dir}/summary_files/#
/^flagpath: /s#: .*#: ${run_dir}/image_files/flags/#
/^wrfinputpath: /s#: .*#: ${run_dir}/#
/^imagepath: /s#: .*#: ${run_dir}/image_files/#
/^jsonpath: /s#: .*#: ${post_dir}/json/#
EOF
        if [[ ! -f "${post_config_orig}" ]]; then
            echo " "
            echo -e "${RED}ERROR${NC}: Config template file - ${CYAN}${post_config_orig}${NC} not exist."
            echo " "
            exit 1
        fi

        sed -f "${sedfile}" "${post_config_orig}" > "${post_config}"
        rm  -f "${sedfile}"
    fi

    if [[ "$task" == "verif" ]]; then
        # modify the verif script
        verif_script="${post_script_dir}/wofs_plot_verification_MPAS.py"
        sed -i "/plot_modes_qpe =/s/\[.*\]/${qpe_mode_string}/" "${verif_script}"
    fi
    ;;

atpost )
    myname="$(realpath $0)"
    if [[ "${host}" != ${post_machine}* ]]; then
        myname="/scratch${myname}"
    fi

    cmds=("${myname}" "${config_file}" "${eventdate}")
    [[ "${starttime}" != "${default_datime}"  ]] && cmds+=(-s "${startdatetime}")
    [[ "${endtime}"   != "${default_endtime}" ]] && cmds+=(-e "${enddatetime}")

    atjobstr=$(cat <<EOF
if [[ $verb == true ]]; then
    echo "at ${launchtime}        <<< \"${cmds[*]} post\""
    echo "at ${launchtime}+1hours <<< \"${cmds[*]} diag\""
    echo "at ${launchtime}+2hours <<< \"${cmds[*]} snd\""
    echo "at ${launchtime}+3hours <<< \"${cmds[*]} verif\""
    echo "at ${launchtime}+4hours <<< \"${cmds[*]} plot\""
fi

if [[ -z "$show" ]]; then
    at ${launchtime}        <<< "${cmds[*]} post"
    at ${launchtime}+1hours <<< "${cmds[*]} diag"
    at ${launchtime}+2hours <<< "${cmds[*]} snd"
    at ${launchtime}+3hours <<< "${cmds[*]} verif"
    at ${launchtime}+4hours <<< "${cmds[*]} plot"
fi
EOF
)
    ;;
esac

#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#% ENTRY

echo -e "=== AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA ===\n"
echo -e "${PURPLE}$(date +'%Y%m%d %H:%M:%S (%Z)')${NC} - ${BROWN}$0 ${saved_args}${NC}"

case $task in
#1. dacycles
dacycles )
    cd "${script_dir}" || exit 1
    cmds=("${script_dir}/run_dacycles.sh" "${config_file}" "${eventdate}")
    [[ "${starttime}" != "${default_datime}"  ]] && cmds+=(-s "${startdatetime}")
    [[ "${endtime}"   != "${default_endtime}" ]] && cmds+=(-e "${enddatetime}")
    [[ -n "${taskopt}" ]] && cmds+=("${taskopt}")
    cmds+=("-r")
    ;;
#2. fcst
fcst )
    cd "${script_dir}" || exit 1
    cmds=("${script_dir}/run_fcst.sh" "${config_file}" "${eventdate}")
    [[ "${starttime}" != "${default_fcsttime}" ]] && cmds+=(-s "${startdatetime}")
    [[ "${endtime}"   != "${default_endtime}"  ]] && cmds+=(-e "${enddatetime}")
    [[ -n "${taskopt}" ]] && cmds+=("${taskopt}")
    cmds+=("-r" "-w")
    ;;

#3. post
post )

    if [[ ! -e ${donepost} ]]; then

        #damode=$(grep '^ *damode=' "${config_file}" | cut -d'=' -f2 | tr -d '"')
        #if [[ ${damode} == "restart" ]]; then
            fcstbegs="$dt"
        #else
        #    fcstbegs="0"
        #fi

        if [[ ! -e ${run_dir}/FCST/${eventdate}${affix}/fcst_${enddatetime}_start ]]; then
            # To make sure the correct FCST files are used, "-c"
            cmds=("${script_dir}/lnmpasfcst.sh" -c -b "$fcstbegs" -s "${startdatetime}" -e "${enddatetime}" "${config_file}" "${eventdate}")
            cmds+=("${eventdate}")
            ${show} "${cmds[@]}"
        fi

        cd "${post_script_dir}" || exit 1
        cmds=(time "./wofs_${task}_summary_files_MPAS.py" "${post_config}")
    else
        echo -e "${DARK}File ${CYAN}$donepost${NC} exist"
        echo -e "${DARK}Please clean them using ${GREEN}${script_dir}/cleanmpas.sh ${config_file} ${eventdate} post${NC} before reprocessing."
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

        cd "${post_script_dir}" || exit 1
        cmds=(time "./wofs_${task}_summary_files_MPAS.py" "${post_config}")
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

        cd "${post_script_dir}" || exit 1
        cmds=(time "./wofs_plot_verification_MPAS.py" "${post_config}")
    else
        echo -e "${DARK}File ${CYAN}$doneverif${NC} exist"
        echo -e "${DARK}Please clean them using ${GREEN}${script_dir}/cleanmpas.sh ${eventdate} post${NC} before reprocessing."
        exit 2
    fi
    ;;
#6. snd
snd )
    if [[ ! -e ${donesnd} ]]; then
        echo -e "${DARK}Waiting for ${donepost} ...."
        while [[ ! -e "${donepost}" ]]; do
            sleep 10
        done

        cd "${post_script_dir}" || exit 1
        cmds=(time "./wofs_plot_sounding_MPAS.py" "${post_config}")
    else
        echo -e "${DARK}File ${CYAN}$donesnd${NC} exist"
        echo -e "${DARK}Please clean them using ${GREEN}${script_dir}/cleanmpas.sh ${eventdate} post${NC} before reprocessing."
        exit 2
    fi
    ;;

#7. diag
diag )
    cd "${script_dir}" || exit 1
    cmds=("${script_dir}/plot_allobs.sh" "${config_file}" "${eventdate}")
    [[ "${starttime}" != "${default_fcsttime}" ]] && cmds+=(-s "${startdatetime}")
    [[ "${endtime}"   != "${default_endtime}"  ]] && cmds+=(-e "${enddatetime}")
    if [[ -n "${taskopt}" ]]; then cmds+=("${taskopt}");  fi
    ;;

#8. atpost
atpost )
    #echo "$host, $post_machine"
    if [[ "${host}" == ${post_machine}* ]]; then
        #cd "${script_dir}" || exit $?
        ${show} eval "${atjobstr}"
    else
        ${show} ssh ${post_machine} -t "${atjobstr}"
    fi
    exit 0
   ;;
* )
    echo -e "${RED}ERROR${NC}: Unknown task - ${PURPLE}$task${NC}\n"
    exit 3
    ;;
esac

if [ -t 1 ]; then # "interactive"
    echo -e "\n${PURPLE}$(date +'%Y%m%d_%H:%M:%S (%Z)')${NC} - ${DARK}Interactivly running: ${BROWN}${task}${NC} from ${YELLOW}$(pwd)${NC}\n"
else
    echo -e "\n${PURPLE}$(date +'%Y%m%d %H:%M:%S (%Z)')${NC} - ${DARK}Background running: ${BROWN}${task}${NC} from ${BLYELLOWUE}$(pwd)${NC}\n"
fi

if [[ -z ${show} ]]; then echo -e "${GREEN}${cmds[*]}${NC}"; fi
${show} "${cmds[@]}"
echo " "

exit 0
