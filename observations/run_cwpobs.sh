#!/bin/bash

scpdir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
rootdir=$(realpath "$(dirname "${scpdir}")")
mpasdir="/scratch/wofs_mpas"

srcdir="/work2/wof/realtime/OBSGEN/CLOUD_OBS"
#hard_srcdir="/scratch/yunheng.wang/MPAS/MPAS_PROJECT/OBS_SEQ.3km/CWP.nc"

run_dir="${mpasdir}/run_dirs"
destdir="${mpasdir}/OBS_SEQ/CWP"

eventdateDF=$(date -u +%Y%m%d%H%M)

source ${rootdir}/scripts/Common_Utilfuncs.sh

function usage {
    echo " "
    echo "    USAGE: $0 [options] [DATETIME] [WORKDIR] [COMMAND]"
    echo " "
    echo "    PURPOSE: Preprocessing CWP data in $srcdir to $destdir."
    echo " "
    echo "    DATETIME - Empty: Current UTC date and time"
    echo "               YYYYmmdd:       run this task for this event date."
    echo " "
    echo "    COMMAND  - one of [ls, check, fix]"
    echo "               check    List the observations in the $srcdir"
    echo "               ls       List the observations in the $destdir"
    echo "               fix      Added '.missed' tag to missing file for the MPAS-WoFS workflow keeps going"
    echo " "
    echo "    OPTIONS:"
    echo "              -h                  Display this message"
    echo "              -n                  Show command to be run and generate job scripts only"
    echo "              -v                  Verbose mode"
    echo "              -s  start_time      Run task from start_time, default $starthour"
    echo "              -f  conf_file       Runtime configuration file, make it the last argument (after WORKDIR)."
    echo "              -d  sub_dir         Subdirectory name after the event date. For example \"/d1\""
    echo "              -o                  Data separated at 00 UTC."
    echo " "
    echo " "
    echo "                                     -- By Y. Wang (2024.04.26)"
    echo " "
    exit "$1"
}

########################################################################

#show=""
#verb=false
eventdate=${eventdateDF:0:8}
eventhour=${eventdateDF:8:2}
cmd=""

starthour=1500
endhour=0300

timeend=${eventdateDF}

if [[ $((10#$eventhour)) -lt 12 ]]; then
    eventdate=$(date -u -d "${eventdate} 1 day ago" +%Y%m%d)
    nextday=true
fi

conf_file=""

#subdir="/d1"
subdir=""
dirsp=false

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
        #-n)
        #    show="echo"
        #    ;;
        #-v)
        #    verb=true
        #    ;;
        -s)
            if [[ $2 =~ ^[0-9]{4}$ ]]; then
                starthour="$2"
            else
                echo ""
                echo "ERROR: expecting HHMM, get [$key]."
                usage 3
            fi
            shift
            ;;
        -f)
            if [[ -f ${2} ]]; then
                conf_file=$2
            elif [[ -f ${run_dir}/$2 ]]; then
                conf_file=${run_dir}/$2
            else
                echo "ERROR: Runtime configruation file not found, get [$2]."
                usage 2
            fi
            shift
            ;;
        -d )
            if [[ $2 =~ \/.* ]]; then
                subdir="$2"
            else
                echo "ERROR: Subdir must starts with '/', get [$2]."
                usage 2
            fi
            shift
            ;;
        -o )
            dirsp=true
            ;;
        -*)
            echo "Unknown option: $key"
            usage 2
            ;;
        ls | check | fix )
            cmd="${key}"
            ;;
        *)
            if [[ $key =~ ^[0-9]{8}$ ]]; then
                eventdate=${key}
                nextdate=$(date -d "$eventdate 1 day" +%Y%m%d)
                timeend="${nextdate}${endhour}"
                nextday=true
            elif [[ $key =~ ^[0-9]{12}$ ]]; then
                eventdate=${key:0:8}
                eventhour=${key:8:2}
                if [[ $((10#$eventhour)) -lt 12 ]]; then
                    eventdate=$(date -u -d "${eventdate} 1 day ago" +%Y%m%d)
                    nextday=true
                fi
                timeend="${key}"
            elif [[ -d $key ]]; then
                run_dir="$key"
            else
                echo ""
                echo "ERROR: unknown argument, get [$key]."
                usage 3
            fi
            ;;
    esac
    shift # past argument or value
done

if [[ ${conf_file} == "" ]]; then
    conf_file="${run_dir}/config.${eventdate}"
fi

if [[ -e ${conf_file} ]]; then
    eval "$(sed -n "/OBS_DIR=/p" ${conf_file})"
    destdir="${OBS_DIR}/CWP"
else
    if [[ "$cmd" =~ "check" ]]; then
        :
    else
        echo -e "${RED}ERROR${NC}: ${CYAN}${conf_file}${NC} not exist."
        exit 0
    fi
fi

echo -e "\nUse runtime Configruation file: ${CYAN}${conf_file}${NC}.\n"

nextdate=$(date -u -d "${eventdate} 1 day" +%Y%m%d)

if [[ ! -t 1 && ! "$cmd" == "check" ]]; then # "jobs"
    log_dir="${run_dir}/${eventdate}"

    if [[ ! -d ${log_dir} ]]; then
        echo "ERROR: ${log_dir} not exists."
        exit 1
    fi

    exec 1>> "${log_dir}/log.cwp" 2>&1
fi

echo "=== $(date +%Y%m%d_%H:%M:%S) - $0 ${saved_args} ==="

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

case $cmd in
    ls | fix)
        echo -e "\n${LIGHT_BLUE}${destdir}${NC}:"
        beg_sec=$(date -d "${eventdate} ${starthour}"     +%s)
        end_sec=$(date -d "${timeend:0:8} ${timeend:8:4}" +%s)
        n=0; missedfiles=()
        for ((i=beg_sec;i<=end_sec;i+=900)); do
            datestr=$(date -d @$i +%Y%m%d%H%M)
            filename="obs_seq_cwp.G16_V04.${datestr}"
            if (( n%4 == 0)); then echo ""; fi
            if [[ -e ${destdir}/$filename ]]; then
                echo -ne "    ${GREEN}$filename${NC}"
            else
                if [[ "$cmd" == "fix" ]]; then
                    touch "${destdir}/${filename}.missed"
                    missedfiles+=("${destdir}/${filename}.missed")

                fi
                echo -ne "    ${PURPLE}$filename${NC}"
            fi
            ((n++))
        done
        echo ""
        if [[ "$cmd" == "fix" ]]; then
            echo -e "\nTouched missing files (${#missedfiles[@]}):\n"
            for filename in "${missedfiles[@]}"; do
                echo -e "    ${RED}$filename${NC}"
            done
        fi
        ;;

    check )
        beg_sec=$(date -d "${eventdate} ${starthour}"     +%s)
        end_sec=$(date -d "${timeend:0:8} ${timeend:8:4}" +%s)
        cwpfiles=()
        m=0
        for ((i=beg_sec;i<=end_sec;i+=900)); do
            datestr=$(date -d @$i +%Y%m%d)
            [[ $dirsp == true ]] && dirdate="${datestr}" || dirdate="${eventdate}"
            timestr=$(date -d @$i +%H%M)
            filename="${timestr}-cwpobs.nc"
            if [[ -e ${srcdir}/${dirdate}${subdir}/$filename ]]; then
                cwpfiles+=("${filename}")
                ((m++))
            else
                cwpfiles+=("${timestr}-missing")
            fi
        done
        if [[ -t 1 ]]; then
            echo -e "\n${LIGHT_BLUE}${srcdir}/${eventdate}${subdir}${NC}:"
            n=0; dirdate=${eventdate}; next1=true
            for filename in "${cwpfiles[@]}"; do
                if (( n%4 == 0)); then echo ""; fi
                if [[ "${filename:0:4}" -lt 1200 && "$next1" == true && $dirsp == true ]]; then
                    echo ""
                    echo -e "\n${LIGHT_BLUE}${srcdir}/${nextdate}${subdir}${NC}:"
                    echo ""
                    dirdate=${nextdate}
                    next1=false
                fi
                if [[ -e ${srcdir}/${dirdate}${subdir}/$filename ]]; then
                    echo -ne "    ${GREEN}$filename${NC}"
                else
                    echo -ne "    ${PURPLE}$filename${NC}  "
                fi
                ((n++))
            done
            echo ""
        else
            echo "$m"
            echo "${cwpfiles[*]}"
        fi
        ;;
    * )
        # >>> mamba initialize >>>
        # !! Contents within this block are managed by 'mamba init' !!
        export MAMBA_EXE='/home/yunheng.wang/tools/micromamba/bin/micromamba';
        export MAMBA_ROOT_PREFIX='/home/yunheng.wang/tools/micromamba';
        __mamba_setup="$("$MAMBA_EXE" shell hook --shell zsh --root-prefix "$MAMBA_ROOT_PREFIX" 2> /dev/null)"
        # shellcheck disable=SC2181
        if [ $? -eq 0 ]; then
            eval "$__mamba_setup"
        else
            micromamba() { "$MAMBA_EXE"; }  # Fallback on help from mamba activate
        fi
        unset __mamba_setup
        # <<< mamba initialize <<<
        micromamba activate wofs_an

        cd "${scpdir}" || exit 0

        python cwpobs2dart.py -i "${srcdir}/${eventdate}${subdir}" -o "${destdir}" -d "${eventdate}"
        if [[ $nextday == true && $dirsp == true ]]; then
            python cwpobs2dart.py -i "${srcdir}/${nextdate}${subdir}" -o "${destdir}" -d "${nextdate}"
        fi
        #python cwpobs2dart.py -i "${hard_srcdir}" -o "${destdir}" -d "${eventdate}"
        #if [[ $nextday == true ]]; then
        #    python cwpobs2dart.py -i "${hard_srcdir}" -o "${destdir}" -d "${nextdate}"
        #fi

        ;;
esac

exit 0
