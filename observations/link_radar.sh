#!/bin/bash

scpdir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
rootdir=$(realpath "$(dirname "${scpdir}")")
mpasdir="/scratch/wofs_mpas"

srcdir="/work2/wof/realtime/OBSGEN/CLOUD_OBS"

run_dir="${mpasdir}/run_dirs"
destdir="${mpasdir}/OBS_SEQ"

eventdateDF=$(date -u +%Y%m%d%H%M)

starthour=1500
endhour=0300

# shellcheck disable=SC1091
source "${rootdir}/scripts/Common_Utilfuncs.sh"

function usage {
    echo " "
    echo "    USAGE: $0 [options] [DATETIME] [WORKDIR] [COMMAND]"
    echo " "
    echo "    PURPOSE: Link radar observation from $srcdir to $destdir."
    echo " "
    echo "    DATETIME - Empty: Current UTC date and time"
    echo "               YYYYmmdd:       run this task for this event date."
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
    echo "              -e  end_time        Run task up to end_time as HHMM or YYYYmmddHHMM, default: $endhour"
    echo "              -f  conf_file       Runtime configuration file, make it the last argument (after WORKDIR)."
    echo "              -d  sub_dir         Subdirectory name after the event date. For example \"/d1/DART\""
    echo "              -o                  Data separated at 00 UTC."
    echo " "
    echo "                                     -- By Y. Wang (2024.04.26)"
    echo " "
    exit "$1"
}

########################################################################

function join_by {
    local IFS="$1"
    echo "${*:2}"
}

########################################################################

show=""
#verb=false
eventdate=${eventdateDF:0:8}
eventhour=${eventdateDF:8:2}
cmd=""
conf_file=""

if ((10#$eventhour < 12)); then
    eventdate=$(date -u -d "${eventdate} 1 day ago" +%Y%m%d)
fi
nextdate=$(date -d "$eventdate 1 day" +%Y%m%d)
default_date=true

start_time=$starthour
end_time=${eventdateDF}

#subdir="/d1/DART"
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
        -n)
            show="echo"
            ;;
        -v)
            verb=true
            ;;
        -s)
            if [[ $2 =~ ^[0-9]{12}$ || $2 =~ ^[0-9]{4}$ ]]; then
                start_time="$2"
            else
                echo ""
                echo "ERROR: expecting HHMM, get [$key]."
                usage 3
            fi
            shift
            ;;
        -e)
            if [[ $2 =~ ^[0-9]{4}$ || $2 =~ ^[0-9]{12}$ ]]; then
                end_time="$2"
            else
                echo ""
                echo "ERROR: expecting HHMM or YYYYmmddHHMM, get [$key]."
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
                eventdate="${key}"
            elif [[ -d $key ]]; then
                run_dir="$key"
            elif [[ -f $key ]]; then
                conf_file="${key}"
            else
                echo ""
                echo "ERROR: unknown argument, get [$key]."
                usage 3
            fi
            ;;
    esac
    shift # past argument or value
done

if [[ -z ${conf_file} ]]; then
    conf_file="${run_dir}/config.${eventdate}"
else
    if [[ "$conf_file" =~ "/" ]]; then
        run_dir=$(realpath "$(dirname "${conf_file}")")
    else
        config_file="${run_dir}/${conf_file}"
    fi

    if [[ ${conf_file} =~ config\.([0-9]{8})(.*) ]]; then
        if [[ "${default_date}" == true ]]; then
            eventdate="${BASH_REMATCH[1]}"
            nextdate=$(date -d "$eventdate 1 day" +%Y%m%d)
            timeend=$(date -d "$eventdate ${endhour} 1 day" +%Y%m%d%H%M)
        fi
    else
        echo -e "${RED}ERROR${NC}: Config file ${CYAN}${config_file}${NC} not the right format config.YYYYmmdd[_*]."
        exit 1
    fi
fi

if [[ -e ${conf_file} ]]; then
    destdir=$(grep '^ *OBS_DIR=' "${conf_file}" | cut -d'=' -f2 | tr -d '"')
else
    if [[ "$cmd" =~ "check" ]]; then
        :
    else
        echo -e "${RED}ERROR${NC}: ${CYAN}${conf_file}${NC} not exist."
        exit 0
    fi
fi

echo -e "\nUse runtime Configruation file: ${CYAN}${conf_file}${NC}. Event Date: ${PURPLE}${eventdate}${NC}. Start time: ${YELLOW}${start_time}${NC}.\n"

nextdate=$(date -u -d "${eventdate} 1 day" +%Y%m%d)

if [[ ${#start_time} -eq 12 ]]; then
    timebeg="${start_time}"
elif ((10#$start_time > starthour )); then
    timebeg="${eventdate}${start_time}"
else
    timebeg="${nextdate}${start_time}"
fi

if [[ ${#end_time} -eq 12 ]]; then
    timeend=${end_time}
elif ((10#$end_time > starthour )); then
    timeend="${eventdate}${end_time}"
else
    timeend="${nextdate}${end_time}"
fi

if [[ ! -t 1 && ! "$cmd" == "check" ]]; then # "jobs"
    log_dir="${run_dir}/${eventdate}"

    if [[ ! -d ${log_dir} ]]; then
        echo "ERROR: ${log_dir} not exists."
        exit 1
    fi

    exec 1>> "${log_dir}/log.radar" 2>&1
fi

echo "=== $(date +%Y%m%d_%H:%M:%S) - $0 ${saved_args} ==="

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

timebeg_s=$(date -d "${timebeg:0:8} ${timebeg:8:4}" +%s)
timeend_s=$(date -d "${timeend:0:8} ${timeend:8:4}" +%s)

[[ $verb == true ]] && echo "From ${timebeg} to ${timeend}, src_dir = ${srcdir}"

case $cmd in

    check | ls | fix )

        #
        # REF
        #
        reffiles=();n=0; missedfiles=()
        for((i=timebeg_s;i<=timeend_s;i+=900)); do
            timestr=$(date -d @$i +%Y%m%d%H%M)
            [[ $dirsp == true ]] && dirdate="${timestr:0:8}" || dirdate="${eventdate}"
            if [[ "$cmd" == "check" ]]; then
                wrkdir="${srcdir}/${dirdate}${subdir}"
                #echo "timestr=$timestr, checking ${wrkdir}"
            else
                wrkdir="${destdir}/REF/${eventdate}"
            fi
            file_name="obs_seq_RF_${timestr:0:8}_${timestr:8:4}.out"
            [[ $verb == true ]] && echo "Checking ${wrkdir}/${file_name} ...."
            if [[ -e ${wrkdir}/${file_name} ]]; then
                reffiles+=("${wrkdir}/${file_name}")
                ((n++))
            else
                reffiles+=("missing:...${timestr:0:8}_${timestr:8:4}.out")
                if [[ "$cmd" == "fix" ]]; then
                    touch "${wrkdir}/${file_name}.missed"
                    missedfiles+=("${wrkdir}/${file_name}.missed")
                fi
            fi
        done
        if [[ -t 1 ]]; then
            [[ $verb == true ]] && echo -e "\n${LIGHT_BLUE}${wrkdir}${NC}:"
            n=0; prevwrkdir=""
            for filename in "${reffiles[@]}";do
                if (( n%4 == 0)); then echo ""; fi
                if [[ $filename =~ "missing:" ]]; then
                    echo -ne "    ${PURPLE}$filename${NC}"
                else
                    wrkdir=$(dirname "$filename")
                    fn=$(basename "$filename")
                    if [[ ! "$prevwrkdir" == "$wrkdir" ]]; then
                        echo -e "\n${LIGHT_BLUE}${wrkdir}${NC}:\n"
                        prevwrkdir="$wrkdir"
                    fi
                    echo -ne "    ${GREEN}$fn${NC}"
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
        else
            echo "$n"
            echo "${reffiles[*]}"
        fi

        #
        # VEL
        #
        declare -A velfiles=()
        n=0; missedfiles=()
        for((i=timebeg_s;i<=timeend_s;i+=900)); do
            timestr=$(date -d @$i +%Y%m%d%H%M)
            [[ $dirsp == true ]] && dirdate="${timestr:0:8}" || dirdate="${eventdate}"
            if [[ "$cmd" == "check" ]]; then
                wrkdir="${srcdir}/${dirdate}${subdir}"
            else
                wrkdir="${destdir}/VEL/${eventdate}"
            fi
            file_name="obs_seq_????_VR_${timestr:0:8}_${timestr:8:4}.out"
            fhead="${wrkdir}/obs_seq_"
            ftail="_VR_${timestr:0:8}_${timestr:8:4}.out"
            fkey="obs_seq${ftail}"
            radnames=()
            for fn in ${wrkdir}/${file_name}; do
                radname=${fn##"${fhead}"}
                radname=${radname%%"${ftail}"}
                radnames+=("${radname}")
            done
            if [[ "${radnames[*]}" == "????" ]]; then
                velfiles["${fkey}"]=""
                if [[ "$cmd" == "fix" ]]; then
                    touch "${wrkdir}/${fkey}.missed"
                    missedfiles+=("${wrkdir}/${fkey}.missed")
                fi
            elif [[ ${#radnames[@]} -gt 0 ]]; then
                velfiles["${fkey}"]=$(join_by _ "${radnames[@]}")
                ((n++))
            fi
        done
        if [[ -t 1 ]]; then
            if [[ "$cmd" == "check" ]]; then
                [[ $dirsp == true ]] && wrkdir="${srcdir}/{${eventdate},${nextdate}}${subdir}" || wrkdir="${srcdir}/${eventdate}${subdir}"
            else
                wrkdir="${destdir}/VEL/${eventdate}"
            fi

            echo -e "\n${LIGHT_BLUE}${wrkdir}${NC}:"
            echo ""

            declare -a radnames
            for fn in "${!velfiles[@]}"; do
                string2array "${velfiles[$fn]}" "radnames"
                if [[ ${#radnames[@]} -ne 0 ]]; then
                    if [[ -z $common ]]; then
                        common=("${radnames[@]}")
                    else
                        mapfile -t common < <( intersection "${common[*]}" "${radnames[*]}" )
                    fi
                fi
            done

            echo -e "    Common Radars: ${CYAN}${common[*]}${NC} (${GREEN}${#common[@]}${NC})"
            echo ""

            for fn in "${!velfiles[@]}"; do
                string2array "${velfiles[$fn]}" "radnames"

                if [[ ${#radnames[@]} -eq 0 ]]; then
                    echo -e "    $fn: ${RED}Missing${NC}"
                else
                    mapfile -t radunique < <(setsubtract "${radnames[*]}" "${common[*]}" )
                    echo -e "    $fn: ${radunique[*]} (${GREEN}${#radnames[@]}${NC})"
                fi
            done | sort -n -k3

            if [[ "$cmd" == "fix" ]]; then
                echo -e "\nTouched missing files (${#missedfiles[@]}):\n"
                for filename in "${missedfiles[@]}"; do
                    echo -e "    ${RED}$filename${NC}"
                done
            fi

        else
            echo "$n"
            typeset -p velfiles
        fi
        ;;
    * )

    #-------------------------------------------------------------------
    # REF
    cd "$destdir/REF" || exit 1

    if [[ ! -r $eventdate ]]; then
        mkdir -p "${destdir}/REF/${eventdate}"
    fi

    cd "${destdir}/REF/${eventdate}" || exit 1


    for((i=timebeg_s;i<=timeend_s;i+=900)); do
        timestr=$(date -d @$i +%Y%m%d%H%M)
        [[ $dirsp == true ]] && dirdate="${timestr:0:8}" || dirdate="${eventdate}"
        file_name="obs_seq_RF_${timestr:0:8}_${timestr:8:4}.out"
        [[ $verb == true ]] && echo "Linking ${srcdir}/${dirdate}${subdir}/${file_name} to $(pwd) ...."
        if [[ ! -e ${file_name} && -e "${srcdir}/${dirdate}${subdir}/${file_name}" ]]; then
            $show ln -sf "${srcdir}/${dirdate}${subdir}/${file_name}" .
        fi
    done

    #-------------------------------------------------------------------
    # VEL
    cd "${destdir}/VEL" || exit 1

    if [[ ! -r $eventdate ]]; then
        mkdir -p "${destdir}/VEL/${eventdate}"
    fi

    cd "${destdir}/VEL/${eventdate}" || exit 1

    for((i=timebeg_s;i<=timeend_s;i+=900)); do
        timestr=$(date -d @$i +%Y%m%d%H%M)
        [[ $dirsp == true ]] && dirdate="${timestr:0:8}" || dirdate="${eventdate}"

        file_name="obs_seq_????_VR_${timestr:0:8}_${timestr:8:4}.out"
        numsrc=$(find "${srcdir}/${dirdate}${subdir}" -name "${file_name}" | wc -l)
        numdes=$(find .                                   -name "${file_name}" | wc -l)
        [[ $verb == true ]] && echo "Linking ${srcdir}/${dirdate}${subdir}/${file_name} to $(pwd) ...."
        if [[ $numdes -lt $numsrc ]]; then
            # shellcheck disable=SC2086
            $show ln -sf "${srcdir}/${dirdate}${subdir}"/${file_name} .
        fi
    done
    ;;
esac

exit 0
