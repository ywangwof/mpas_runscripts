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

#-----------------------------------------------------------------------

source "$script_dir/Common_Colors.sh"

########################################################################

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
    echo    "              -f conf_file        Configuration file for this case. Default: \${WORKDIR}/config.\${eventdate}"
    echo    " "
    echo    "   DEFAULTS:"
    echo    "              eventdate  = $eventdateDF"
    echo    "              WORKDIR    = ${mpasworkdir}/run_dir"
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
            -h)
                usage 0
                ;;
            -n)
                args["show"]="echo"
                ;;
            -nn)
                args["taskopt"]="-n"
                ;;
            -v)
                args["verb"]=true
                ;;
            -f)
                args["config_file"]="$2"
                shift
                ;;
            -e)
                args["endtime"]="$2"
                shift
                ;;
            -*)
                echo -e "${RED}ERROR${NC}: Unknown option: ${YELLOW}$key${NC}"
                usage 2
                ;;
            dacycles | fcst | post | plot | diag | verif | snd )
                args["task"]=$key
                ;;
            noscript )
                args["noscript"]=true
                ;;
            *)
                if [[ $key =~ ^[0-9]{12}$ ]]; then
                    eventhour=${key:8:2}
                    if ((10#$eventhour < 12)); then
                        args["eventdate"]=$(date -u -d "${key:0:8} 1 day ago" +%Y%m%d)
                    else
                        args["eventdate"]=${key:0:8}
                    fi
                elif [[ $key =~ ^[0-9]{8}$ ]]; then
                    args["eventdate"]=${key}
                elif [[ -d $key ]]; then
                    args["run_dir"]=$key
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

if [[ -v args["eventdate"] ]]; then
    eventdate=${args["eventdate"]}
else
    eventdate=${eventdateDF:0:8}
    eventhour=${eventdateDF:8:2}

    if ((10#$eventhour < 12)); then
        eventdate=$(date -u -d "${eventdate} 1 day ago" +%Y%m%d)
    fi
fi

[[ -v args["endtime"] ]] && endtime=${args["endtime"]} || endtime="0300"
[[ -v args["run_dir"] ]] && run_dir=${args["run_dir"]} || run_dir="${mpasworkdir}/run_dirs"

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
    fcstlength=$(grep '^ *fcst_length_seconds=' "${config_file}" | cut -d'=' -f2 | cut -d' ' -f1 | tr -d '(')
    level_file=$(grep '^ *vertLevel_file='      "${config_file}" | cut -d'=' -f2 | cut -d' ' -f1 | tr -d '"')
else
    echo " "
    echo -e "${RED}ERROR${NC}: Config file ${CYAN}${config_file}${NC} not exist."
    usage 1
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
        #exec > >(tee -ia ${log_file} 2>&1
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
    donesnd="${run_dir}/image_files/flags/${eventdate}${affix}/wofs_postsnd_${endtime}_finished"

    post_script_dir="${MPASdir}/frdd-wofs-post/wofs/scripts"
    post_config_orig="${MPASdir}/frdd-wofs-post/conf/WOFS_MPAS_config.yaml"

    case ${fcstlength} in
    21600 )
        nt=72
        qpe_mode_string="['qpe_15m', 'qpe_1hr', 'qpe_3hr', 'qpe_6hr']"
        ;;
    10800 )
        nt=36
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
        ((10#$endtime < 1200)) && oneday="1 day" || oneday=""

        fbeg_s=$(date -u -d "${eventdate} 1700" +%s)
        fbeg_e=$(date -u -d "${eventdate} ${endtime} ${oneday}" +%s)

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
/^nt :/s/: .*/: $nt/
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
    cmds=("${script_dir}/run_dacycles.sh" -e "${endtime}" "${config_file}" -r)
    if [[ -n "${taskopt}" ]]; then cmds+=("${taskopt}"); fi
    ;;
#2. fcst
fcst )
    cd "${script_dir}" || exit 1
    cmds=("${script_dir}/run_fcst.sh" -e "${endtime}" "${config_file}" -r -w)
    if [[ -n "${taskopt}" ]]; then cmds+=("${taskopt}"); fi
    ;;

#3. post
post )

    if [[ ! -e ${donepost} ]]; then

        #damode=$(grep '^ *damode=' "${config_file}" | cut -d'=' -f2 | tr -d '"')
        #if [[ ${damode} == "restart" ]]; then
            fcstbegs="5"
        #else
        #    fcstbegs="0"
        #fi

        if ((10#$endtime < 1200)); then
            enddate=$(date -u -d "$eventdate 1 day" +%Y%m%d)
        else
            enddate=${eventdate}
        fi
        if [[ ! -e ${run_dir}/FCST/${eventdate}${affix}/fcst_${enddate}${endtime}_start ]]; then
            # To make sure the correct FCST files are used, "-c"
            cmds=("${script_dir}/lnmpasfcst.sh" -c -b "$fcstbegs" -e "${endtime}" "${config_file}" )
            cmds+=("${eventdate}")
            ${show} "${cmds[@]}"
        fi

        cd "${post_script_dir}" || exit 1
        cmds=(time "./wofs_${task}_summary_files_MPAS.py" "${post_config}")
    else
        echo -e "${DARK}File ${CYAN}$donepost${NC} exist"
        echo -e "${DARK}Please clean them using ${GREEN}${script_dir}/cleanmpas.sh ${config_file} post${NC} before reprocessing."
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
    cmds=("${script_dir}/plot_allobs.sh" -e "${endtime}" "${config_file}")
    if [[ -n "${taskopt}" ]]; then cmds+=("${taskopt}");  fi
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
