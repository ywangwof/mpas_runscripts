#!/bin/bash
# shellcheck disable=SC2034,SC1091

script_dir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
rootdir=$(realpath "$(dirname "${script_dir}")")

eventdateDF=$(date -u +%Y%m%d%H%M)

#
# To run MPAS-WoFS tasks interactively or using at/cron at background
#

script_dir=${rootdir}/scripts

host="$(hostname)"

default_endtime="0300"
default_datime="1500"
default_fcsttime="1700"

#-----------------------------------------------------------------------

source "${script_dir}/Common_Colors.sh" || exit $?
source "${script_dir}/Site_Runtime.sh" || exit $?
source "${script_dir}/Common_Utilfuncs.sh" || exit $?

########################################################################

function usage {
    echo    " "
    echo    "    USAGE: $0 [options] [EVENTDATE] [WORKDIR] [CONFIG] [TASK]"
    echo    " "
    echo    "    PURPOSE: Run MPAS-WOFS tasks interactively or using Linux at/cron facility."
    # shellcheck disable=SC2154
    echo -e "             It will log the outputs to a file as ${LIGHT_BLUE}\${WORKDIR}${NC}/${DIR_CLR}\${EVENTDATE}${NC}/log${DIRa_CLR}\${affix}${NC}.${YELLOW}\${task}${NC} automatically."
    echo    " "
    echo -e "    CONFIG   - MPAS-WoFS runtime configuration file with full path. Default: ${LIGHT_BLUE}\${WORKDIR}${NC}/config.${DIR_CLR}\${EVENTDATE}${NC}"
    echo -e "    TASK     - One of [${YELLOW}dacycles${NC},${YELLOW}fcst${NC},${YELLOW}post${NC},${YELLOW}plot${NC},${YELLOW}diag${NC},${YELLOW}verif${NC},${YELLOW}snd${NC},${BROWN}atpost${NC}, ${YELLOW}nccompress${NC}]"
    echo    ""
    echo -e "    ${DARK}WORKDIR & EVENTDATE may be extracted from the CONFIG name unless they are given explicitly.${NC}"
    echo    ""
    echo -e "    EVENTDATE - Event date as YYYYmmdd."
    echo -e "    WORKDIR   - Top level ${LIGHT_BLUE}run_dir${NC} for all tasks. It should contain these folders:"
    echo -e "                       ${DIR_CLR}\${EVENTDATE}${NC}/{dacycles,fcst}${DIRa_CLR}\${affix}${NC}"
    echo -e "                       {FCST,summary_files,image_files}/${DIR_CLR}\${EVENTDATE}${DIRa_CLR}\${affix}${NC}"
    echo    " "
    echo    "    OPTIONS:"
    echo    "              -h                  Display this message"
    echo    "              -n                  Show command to be run, but not run it"
    echo    "              -nn                 Show command to be run (one level deeper), but not run it"
    echo    "              -v                  Verbose mode"
    echo    "              -s  HHMM            Start time in HHMM format or YYYYmmddHHMM."
    echo    "              -e  HHMM            Last time in HHMM format or YYYYmmddHHMM."
    echo -e "              -t  launchtime      Date and time to launch the first task for task ${BROWN}atpost${NC}, as ${LIGHT_BLUE}HH:MM${NC} or ${LIGHT_BLUE}HH:MM mmddyy${NC}"
    echo -e "              --wrkdirs  dir_list Comma-separated list of work directories for ${BROWN}nccompress${NC}, e.g., ${YELLOW}dacycles,fcst,mpassit,post${NC}."
    echo -e "              -p  machine         Post-processing machine, default: ${PURPLE}wof-epyc8${NC}."
    echo    " "
    echo    "   DEFAULTS:"
    echo -e "              EVENTDATE  = ${DIR_CLR}${eventdateDF:0:8}$NC"
    echo -e "              WORKDIR    = ${LIGHT_BLUE}\${site_workdir}${NC}      # from scripts/Site_Runtime.sh"
    echo    "              rootdir    = ${rootdir}"
    echo    "              script_dir = ${script_dir}"
    echo -e "              post_dir   = ${LIGHT_BLUE}\${site_postdir}${NC}      # from scripts/Site_Runtime.sh"
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
            --wrkdirs )
                IFS=',' read -r -a wrkdirs <<< "$2"
                args["wrkdirs"]="${wrkdirs[*]}"
                shift
                ;;
            -* )
                echo -e "${RED}ERROR${NC}: Unknown option: ${YELLOW}$key${NC}"
                usage 2
                ;;
            dacycles | fcst | post | plot | diag | verif | snd | atpost | nccompress )
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

[[ -v args["verb"] ]]  && verb=${args["verb"]}   || verb=false
[[ -v args["show"] ]]  && show=${args["show"]}   || show=""

[[ -v args["post_machine"] ]] && post_machine=${args["post_machine"]^} || post_machine="Ursa"
setup_machine "${post_machine}" "$rootdir" false false false

if [[ -n $show ]]; then
    runcmd="echo ${site_runcmd}"
    dorun=false
else
    runcmd="${site_runcmd}"
    dorun=true
fi
export runcmd dorun

support_interactive_job=true
if [[ ${post_machine} =~ ^(Ursa|Jet)$ ]]; then
    support_interactive_job=false
fi

[[ -v args["taskopt"] ]]  && taskopt=${args["taskopt"]}   || taskopt=""
[[ -v args["task"] ]]     && task=${args["task"]}         || task=""

[[ -v args["noscript"] ]] && noscript=${args["noscript"]} || noscript=false

[[ -v args["launchtime"] ]]   && launchtime=${args["launchtime"]}     || launchtime="18:00"


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
# shellcheck disable=SC2154
[[ -v args["run_dir"] ]]   && run_dir=${args["run_dir"]}     || run_dir="${site_workdir}"

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
    if [[ ${noscript} == false ]]; then
        echo -e "Reading case configuration file: ${CYAN}${config_file}${NC} ...."
    fi
    readconf "${config_file}" COMMON fcst compression || exit $?
else
    echo " "
    echo -e "${RED}ERROR${NC}: Config file ${CYAN}${config_file}${NC} not exist."
    usage 1
fi

if [[ -z ${task} ]]; then
    declare -a options
    declare selected result

    options=(
             "dacycles:     Run ${YELLOW}run_dacycles.sh${NC} from ${CYAN}${default_datime}${NC} to ${CYAN}${default_endtime}${NC}"
             "fcst:         Run ${YELLOW}run_fcst.sh${NC} from ${CYAN}${default_fcsttime}${NC} to ${CYAN}${default_endtime}${NC}"
             "post:         Generate summary files from ${CYAN}${default_fcsttime}${NC} to ${CYAN}${default_endtime}${NC}"
             "plot:         Generate images for the summary files from ${CYAN}${default_fcsttime}${NC} to ${CYAN}${default_endtime}${NC}"
             "verif:        Generate verification images from ${CYAN}${default_fcsttime}${NC} to ${CYAN}${default_endtime}${NC}"
             "snd:          Generate sounding files from ${CYAN}${default_fcsttime}${NC} to ${CYAN}${default_endtime}${NC}"
             "diag:         Do diagnostic plots from ${CYAN}${default_datime}${NC} to ${CYAN}${default_endtime}${NC}"
             "nccompress:   Compress the existing forecast files and clean up the original ones"
             "abort:        Exit without doing anything"
            )

    echo ""
    select_option "Select a task to get started: " "${options[@]}"
    echo ""

    selected=$?; result="${options[${selected}]}"; task="${result%%:*}"

    if [[ "${task}" == "abort" ]]; then
        echo -e "${YELLOW}INFO${NC}: Aborting as requested."
        exit 0
    fi
    saved_args+=" ${task}"
fi

if [[ -z ${starttime} ]]; then
    if [[ "${task}" == "dacycles" || "${task}" == "diag" ]]; then
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

fbeg_s=$(date -u -d "${startdatetime:0:8} ${startdatetime:8:4}" +%s)
fend_s=$(date -u -d "${enddatetime:0:8}   ${enddatetime:8:4}"   +%s)

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

case $task in
post | plot | diag | verif | snd )
    #if [[ ! "${host}" == ${post_machine}* ]]; then
    #    echo -e "${RED}ERROR${NC}: Please run ${BROWN}$task${NC} on ${post_machine} only".
    #    exit 1
    #fi

    # Load Python environment as needed
    setup_machine "${post_machine}" "$rootdir" true false false

    : "${config_OUTINVL:?"ERROR: config_file not read?"}"
    : "${config_fcst_length_seconds:?"ERROR: config_file not read"}"
    : "${site_postdir:?"ERROR: setup_machine not return correctly?"}"

    post_dir="${site_postdir}"

    donepost="${run_dir}/summary_files/${eventdate}${affix}/${endtime}/wofs_postswt_${endtime}_finished"
    doneplot="${run_dir}/image_files/flags/${eventdate}${affix}/${endtime}/wofs_plotpbl_${endtime}_finished"
    doneverif="${run_dir}/image_files/flags/${eventdate}${affix}/wofs_plotwwa_${endtime}_finished"
    donesnd="${run_dir}/image_files/flags/${eventdate}${affix}/wofs_postsnd_${endtime}_finished"

    post_script_dir="${post_dir}/wofs/scripts"
    post_config_orig="${post_dir}/conf/WOFS_MPAS_config.yaml"

    dt=$(( config_OUTINVL/60 ))
    nt=$(( config_fcst_length_seconds/config_OUTINVL ))
    case ${config_fcst_length_seconds} in
    21600 )
        qpe_mode_string="['qpe_15m', 'qpe_1hr', 'qpe_3hr', 'qpe_6hr']"
        ;;
    10800 )
        qpe_mode_string="['qpe_15m', 'qpe_1hr', 'qpe_3hr']"
        ;;
    * )
        echo -e "${RED}ERROR${NC}: fcstlength = ${PURPLE}${config_fcst_length_seconds}${NC} is not supported."
        exit 1
        ;;
    esac

    post_config="${run_dir}/summary_files/WOFS_MPAS_config_${eventdate}${affix}.yaml"
    #rm -f "${post_config}"

    # shellcheck disable=SC2154
    wof_domain_name="geo_${config_domname##*_}"

    if [[ ! -f "${post_config}" ]]; then
        fcst_times=""
        for ((ftime=fbeg_s;ftime<=fend_s;ftime+=3600)); do
            fcst_time=$(date -u -d @$ftime +%H%M)
            fcst_times+=" '${fcst_time}',"
        done

        # shellcheck disable=SC2154
        if [[ ! -f "${config_vertLevel_file}" ]]; then
            echo -e "${RED}ERROR${NC}: Vertical level file - ${CYAN}${config_vertLevel_file}${NC} not exist."
            exit 1
        fi

        num_levels=$(wc -l "${config_vertLevel_file}"| cut -d' ' -f1)
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
/^mrmspath: /s#: .*#: ${RT_OBSDIR}/MRMS/#
/^asospath: /s#: .*#: ${RT_OBSDIR}/ASOS/#
/^lsrwwapath: /s#: .*#: ${RT_OBSDIR}/LSR_WWA/2026#
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
    myname="$(realpath "$0")"
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
    cmds+=("-w")  # "-r"
    ;;

#3. post
post )

    if [[ ! -e ${donepost} ]]; then

        fcstbegs="0"
        if [[ ${config_fcstmode} == "restart" ]]; then
            fcstbegs="$dt"
        fi

        if [[ ! -e ${run_dir}/FCST/${eventdate}${affix}/fcst_${enddatetime}_start ]]; then
            # To make sure the correct FCST files are used, "-c"
            cmds=("${script_dir}/lnmpasfcst.sh" -c -b "$fcstbegs" -s "${startdatetime}" -e "${enddatetime}" "${config_file}")
            if [[ -z ${show} ]]; then echo -e "${GREEN}${cmds[*]}${NC}"; fi
            ${show} "${cmds[@]}"
        fi

        wrkdir="${run_dir}/summary_files"
        cd "${wrkdir}" || exit 1

        if [[ ${support_interactive_job} == true ]]; then               # run interactively
            cmds=(time "${post_script_dir}/wofs_${task}_summary_files_MPAS.py" "${post_config}")
        else                                                            # submit a job to the compute nodes
            jobscript="${run_dir}/summary_files/run_${task}_${eventdate}${affix}.slurm"

            # shellcheck disable=SC2154
            declare -A jobParms=(
                [PARTION]="${config_partition_post}"
                [NOPART]="1"
                [JOBNAME]="${task}_${eventdate}${affix}"
                [CPUSPEC]="${config_claim_cpu_python}"
                [MACHINE]="${machine}"
                [PYTHONSCRIPT]="${post_script_dir}/wofs_${task}_summary_files_MPAS.py"
                [CONFIGFILE]="${post_config}"
            )
            cmds=(submit_a_job "${wrkdir}" "${task}_${eventdate}${affix}" "jobParms" "${rootdir}/templates/run_python.slurm" "$jobscript" "")
        fi
    else
        echo -e "${DARK}File ${CYAN}$donepost${NC} exist"
        echo -e "${DARK}Please clean them using ${GREEN}${script_dir}/cleanmpas.sh ${config_file} ${eventdate} ${task}${NC} before reprocessing."
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

        wrkdir="${run_dir}/summary_files"
        cd "${wrkdir}" || exit 1

        if [[ ${support_interactive_job} == true ]]; then               # run interactively
            cmds=(time "${post_script_dir}/wofs_${task}_summary_files_MPAS.py" "${post_config}")
        else                                                            # submit a job to the compute nodes
            jobscript="${run_dir}/summary_files/run_${task}_${eventdate}${affix}.slurm"

            declare -A jobParms=(
                [PARTION]="${config_partition_post}"
                [NOPART]="1"
                [JOBNAME]="${task}_${eventdate}${affix}"
                [CPUSPEC]="${config_claim_cpu_python}"
                [MACHINE]="${machine}"
                [PYTHONSCRIPT]="${post_script_dir}/wofs_${task}_summary_files_MPAS.py"
                [CONFIGFILE]="${post_config}"
            )
            cmds=(submit_a_job "$wrkdir" "${task}_${eventdate}${affix}" "jobParms" "${rootdir}/templates/run_python.slurm" "$jobscript" "")
        fi

    else
        echo -e "${DARK}File ${CYAN}$doneplot${NC} exist"
        echo -e "${DARK}Please clean them using ${GREEN}${script_dir}/cleanmpas.sh ${eventdate} ${task}${NC} before reprocessing."
        exit 2
    fi
    ;;
#5. verif
verif )
    if [[ ! -e ${doneverif} ]]; then
        echo -e "Waiting for ${DARK}${donepost}${NC} ...."
        while [[ ! -e "${donepost}" ]]; do
            sleep 10
        done

        wrkdir="${run_dir}/summary_files"
        cd "${wrkdir}" || exit 1

        if [[ ${support_interactive_job} == true ]]; then               # run interactively
            cmds=(time "${post_script_dir}/wofs_plot_verification_MPAS.py" "${post_config}")
        else                                                            # submit a job to the compute nodes
            jobscript="${run_dir}/summary_files/run_${task}_${eventdate}${affix}.slurm"

            declare -A jobParms=(
                [PARTION]="${config_partition_post}"
                [NOPART]="1"
                [JOBNAME]="${task}_${eventdate}${affix}"
                [CPUSPEC]="${config_claim_cpu_python}"
                [MACHINE]="${machine}"
                [PYTHONSCRIPT]="${post_script_dir}/wofs_plot_verification_MPAS.py"
                [CONFIGFILE]="${post_config}"
            )
            cmds=(submit_a_job "$wrkdir" "${task}_${eventdate}${affix}" "jobParms" "${rootdir}/templates/run_python.slurm" "$jobscript" "")
        fi

    else
        echo -e "${DARK}File ${CYAN}$doneverif${NC} exist"
        echo -e "${DARK}Please clean them using ${GREEN}${script_dir}/cleanmpas.sh ${eventdate} ${task}${NC} before reprocessing."
        exit 2
    fi
    ;;
#6. snd
snd )
    if [[ ! -e ${donesnd} ]]; then
        echo -e "Waiting for ${DARK}${donepost}${NC} ...."
        while [[ ! -e "${donepost}" ]]; do
            sleep 10
        done

        wrkdir="${run_dir}/summary_files"
        cd "${wrkdir}" || exit 1

        if [[ ${support_interactive_job} == true ]]; then               # run interactively
            cmds=(time "${post_script_dir}/wofs_plot_sounding_MPAS.py" "${post_config}")
        else                                                            # submit a job to the compute nodes
            jobscript="${run_dir}/summary_files/run_${task}_${eventdate}${affix}.slurm"

            declare -A jobParms=(
                [PARTION]="${config_partition_post}"
                [NOPART]="1"
                [JOBNAME]="${task}_${eventdate}${affix}"
                [CPUSPEC]="${config_claim_cpu_python}"
                [MACHINE]="${machine}"
                [PYTHONSCRIPT]="${post_script_dir}/wofs_plot_sounding_MPAS.py"
                [CONFIGFILE]="${post_config}"
            )
            cmds=(submit_a_job "${wrkdir}" "${task}_${eventdate}${affix}" "jobParms" "${rootdir}/templates/run_python.slurm" "$jobscript" "")
        fi

    else
        echo -e "${DARK}File ${CYAN}$donesnd${NC} exist"
        echo -e "${DARK}Please clean them using ${GREEN}${script_dir}/cleanmpas.sh ${eventdate} ${task}${NC} before reprocessing."
        exit 2
    fi
    ;;

#7. diag
diag )
    cd "${script_dir}" || exit 1
    cmds=("${script_dir}/plot_allobs.sh" "${config_file}" "${eventdate}")
    [[ "${starttime}" != "${default_datime}" ]]    && cmds+=(-s "${startdatetime}")
    [[ "${endtime}"   != "${default_endtime}"   ]] && cmds+=(-e "${enddatetime}")
    if [[ -n "${taskopt}" ]]; then cmds+=("${taskopt}");  fi

    if [[ ${support_interactive_job} == false ]]; then               # run interactively
        wrkdir="${run_dir}/${eventdate}/dacycles${affix}/obs_diag"
        mkdir -p "${wrkdir}"

        cmds+=(-m "${post_machine}")

        jobscript="${wrkdir}/run_${task}.slurm"
        declare -A jobParms=(
            [PARTION]="${config_partition_post}"
            [NOPART]="1"
            [JOBNAME]="${task}_${eventdate}${affix}"
            [CPUSPEC]="${config_claim_cpu_python}"
            [MACHINE]="${machine}"
            [PYTHONSCRIPT]="${cmds[*]}"
            [CONFIGFILE]=""
        )
        cmds=(submit_a_job "${wrkdir}" "${task}_${eventdate}${affix}" "jobParms" "${rootdir}/templates/run_python.slurm" "$jobscript" "")
    fi
    ;;

#8. atpost
atpost )
    #echo "$host, $post_machine"
    if [[ $support_interactive_job == true ]]; then
        if [[ "${host}" == ${post_machine}* ]]; then
            #cd "${script_dir}" || exit $?
            ${show} eval "${atjobstr}"
        else
            ${show} ssh "${post_machine}" -t "${atjobstr}"
        fi
    else
        mecho0 "${YELLOW}INFO${NC}: Cannot run ${BROWN}atpost${NC} on ${PURPLE}${post_machine}${NC}.\n"
    fi
    exit 0
   ;;
#9. nccompress
nccompress )
    cd "${run_dir}" || exit 1

    if [[ -v args["wrkdirs"] ]]; then
        read -r -a wrkdirs <<< "${args["wrkdirs"]}"
    else
        wrkdirs=(fcst mpassit post)
    fi

    if [[ ${support_interactive_job} == false ]]; then
        # shellcheck disable=SC2154
        if [[ "${wrkdirs[*]}" == "dacycles" ]]; then
            jobtemplate="run_compress_da.slurm"
            jobscript="run_compress_da_${eventdate}${affix}.slurm"
            jobname="${task}_da_${eventdate}${affix}"
            ens_size="${config_ens_size_da}"
            cpuspec="${config_ncpus_da}"
            ntasks="${config_ntasks_da}"
        else
            jobtemplate="run_compress_post.slurm"
            jobscript="run_compress_post_${eventdate}${affix}.slurm"
            jobname="${task}_post_${eventdate}${affix}"
            ens_size="${config_ens_size_post}"
            cpuspec="${config_ncpus_post}"
            ntasks="${config_ntasks_post}"
        fi

        declare -A jobParms=(
            [PARTION]="${config_partition_post}"
            [NOPART]="${ntasks}"
            [JOBNAME]="${jobname}"
            [CPUSPEC]="${cpuspec}"
            [MACHINE]="${machine}"
            [TASKLIST]="(${wrkdirs[*]})"
            [EVENTDATE]="${eventdate}"
            [AFFIX]="${affix}"
            [MEMBERS]="${ens_size}"
            [BEGINS]="${fbeg_s}"
            [ENDS]="${fend_s}"
        )
        cmds=(submit_a_job "${run_dir}" "${jobname}" "jobParms" "${rootdir}/templates/${jobtemplate}" "$jobscript" "")
    fi
    ;;
* )
    echo -e "${RED}ERROR${NC}: Unknown task - ${PURPLE}$task${NC}\n"
    exit 3
    ;;
esac

if [ -t 1 ]; then # "interactive"
    : #echo -e "\n${PURPLE}$(date +'%Y%m%d_%H:%M:%S (%Z)')${NC} - ${DARK}Interactivly running: ${BROWN}${task}${NC} from ${YELLOW}$(pwd)${NC}\n"
else
    echo -e "\n${PURPLE}$(date +'%Y%m%d %H:%M:%S (%Z)')${NC} - ${DARK}Background running: ${BROWN}${task}${NC} from ${BLYELLOWUE}$(pwd)${NC}\n"
fi

if [[ ${#cmds[@]} -gt 0 ]]; then
    if [[ -z ${show} ]]; then echo -e "${GREEN}${cmds[*]}${NC}"; fi
    ${show} "${cmds[@]}"
    echo " "
fi

exit 0
