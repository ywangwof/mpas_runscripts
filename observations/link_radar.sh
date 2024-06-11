#!/bin/bash

srcdir="/work2/wof/realtime/OBSGEN/CLOUD_OBS"

run_dir="/scratch/ywang/MPAS/gnu/mpas_scripts/run_dirs"
destdir="${run_dir}/OBS_SEQ"

eventdateDF=$(date -u +%Y%m%d%H%M)

starthour=1500
endhour=0300

function usage {
    echo " "
    echo "    USAGE: $0 [options] [DATETIME]"
    echo " "
    echo "    PURPOSE: Link radar observation from $srcdir to $destdir."
    echo " "
    echo "    DATETIME - Empty: Current UTC date and time"
    echo "               YYYYmmdd:       run this task for this event date."
    echo "               YYYYmmddHHMM:   run the task from event date $starthour Z up to YYYYmmddHHMM."
    echo " "
    echo "    OPTIONS:"
    echo "              -h                  Display this message"
    echo "              -n                  Show command to be run and generate job scripts only"
    echo "              -v                  Verbose mode"
    echo "              -check              List the observations in the $srcdir"
    echo "              -ls                 List the observations in the $destdir"
    echo "              -s  start_time      Run task from start_time, default $starthour"
    echo " "
    echo " "
    echo "                                     -- By Y. Wang (2024.04.26)"
    echo " "
    exit $1
}

########################################################################

function join_by {
    local IFS="$1"
    echo "${*:2}"
}

########################################################################

show=""
verb=false
eventdate=${eventdateDF:0:8}
eventhour=${eventdateDF:8:2}
cmd=""

if [[ $((10#$eventhour)) -lt 12 ]]; then
    eventdate=$(date -u -d "${eventdate} 1 day ago" +%Y%m%d)
fi
nextdate=$(date -d "$eventdate 1 day" +%Y%m%d)

start_time=$starthour
timeend=${eventdateDF}

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
        -ls)
            cmd="ls"
            ;;
        -check)
            cmd="check"
            ;;
        -s)
            if [[ $2 =~ ^[0-9]{4}$ ]]; then
                start_time="$2"
            else
                echo ""
                echo "ERROR: expecting HHMM, get [$key]."
                usage 3
            fi
            shift
            ;;
        -*)
            echo "Unknown option: $key"
            usage 2
            ;;
        *)
            if [[ $key =~ ^[0-9]{8}$ ]]; then
                eventdate=${key}
                nextdate=$(date -d "$eventdate 1 day" +%Y%m%d)
                timeend="${nextdate}${endhour}"
            elif [[ $key =~ ^[0-9]{12}$ ]]; then
                eventdate=${key:0:8}
                eventhour=${key:8:2}
                if [[ $((10#$eventhour)) -lt 12 ]]; then
                    eventdate=$(date -u -d "${eventdate} 1 day ago" +%Y%m%d)
                fi
                nextdate=$(date -d "$eventdate 1 day" +%Y%m%d)

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

conf_file="${run_dir}/config.${eventdate}"
if [[ -e ${conf_file} ]]; then
    eval "$(sed -n "/OBS_DIR=/p" ${conf_file})"
    destdir=${OBS_DIR}
else
    echo "${RED}ERROR${NC}: ${CYAN}${conf_file}${NC} not exist."
    exit 0
fi

if [[ $((10#$start_time)) -gt 1200 ]]; then
    timebeg="${eventdate}${start_time}"
else
    timebeg="${nextdate}${start_time}"
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

case $cmd in
    ls )
        echo "ls ${destdir}/REF/${eventdate}"
        $show ls ${destdir}/REF/${eventdate}
        echo "ls ${destdir}/VEL/${eventdate}"
        $show ls ${destdir}/VEL/${eventdate}
        ;;

    check )
        if [[ -t 1 ]]; then
            for((i=timebeg_s;i<=timeend_s;i+=900)); do
                timestr=$(date -d @$i +%Y%m%d%H%M)
                file_name="obs_seq_RF_${timestr:0:8}_${timestr:8:4}.out"
                #echo ""
                #echo "ls ${srcdir}/${timestr:0:8}/d1/DART/${file_name}"
                ls ${srcdir}/${timestr:0:8}/d1/DART/${file_name}
            done

            echo ""

            for((i=timebeg_s;i<=timeend_s;i+=900)); do
                timestr=$(date -d @$i +%Y%m%d%H%M)
                file_name="obs_seq_????_VR_${timestr:0:8}_${timestr:8:4}.out"
                #echo ""
                #echo "ls ${srcdir}/${timestr:0:8}/d1/DART/${file_name}"
                ls ${srcdir}/${timestr:0:8}/d1/DART/${file_name}
            done
        else              # run as a script
            reffiles=();n=0
            for((i=timebeg_s;i<=timeend_s;i+=900)); do
                timestr=$(date -d @$i +%Y%m%d%H%M)
                file_name="obs_seq_RF_${timestr:0:8}_${timestr:8:4}.out"
                if [[ -e ${srcdir}/${timestr:0:8}/d1/DART/${file_name} ]]; then
                    reffiles+=("${file_name}")
                    ((n++))
                else
                    reffiles+=("missing:...${timestr:0:8}_${timestr:8:4}.out")
                fi
            done
            echo "$n"
            echo "${reffiles[*]}"

            declare -A velfiles=()
            n=0
            for((i=timebeg_s;i<=timeend_s;i+=900)); do
                timestr=$(date -d @$i +%Y%m%d%H%M)
                file_name="obs_seq_????_VR_${timestr:0:8}_${timestr:8:4}.out"
                fhead="${srcdir}/${timestr:0:8}/d1/DART/obs_seq_"
                ftail="_VR_${timestr:0:8}_${timestr:8:4}.out"
                fkey="obs_seq${ftail}"
                radnames=()
                for fn in "${srcdir}/${timestr:0:8}"/d1/DART/${file_name}; do
                    radname=${fn##"${fhead}"}
                    radname=${radname%%"${ftail}"}
                    radnames+=("${radname}")
                done
                if [[ "${radnames[*]}" == "????" ]]; then
                    velfiles["${fkey}"]=""
                elif [[ ${#radnames[@]} -gt 0 ]]; then
                    velfiles["${fkey}"]=$(join_by _ ${radnames[@]})
                    ((n++))
                fi
            done
            echo "$n"
            typeset -p velfiles
        fi
        ;;
    * )

    #-------------------------------------------------------------------
    # REF
    cd $destdir/REF || exit 1

    if [[ ! -r $eventdate ]]; then
        mkdir -p "${destdir}/REF/${eventdate}"
    fi

    cd "${destdir}/REF/${eventdate}" || exit 1


    for((i=timebeg_s;i<=timeend_s;i+=900)); do
        timestr=$(date -d @$i +%Y%m%d%H%M)
        file_name="obs_seq_RF_${timestr:0:8}_${timestr:8:4}.out"
        if [[ ! -e ${file_name} && -e "${srcdir}/${timestr:0:8}/d1/DART/${file_name}" ]]; then
            $show ln -sf "${srcdir}/${timestr:0:8}/d1/DART/${file_name}" .
        fi
    done

    #-------------------------------------------------------------------
    # VEL
    cd $destdir/VEL || exit 1

    if [[ ! -r $eventdate ]]; then
        mkdir -p "${destdir}/VEL/${eventdate}"
    fi

    cd "${destdir}/VEL/${eventdate}" || exit 1

    for((i=timebeg_s;i<=timeend_s;i+=900)); do
        timestr=$(date -d @$i +%Y%m%d%H%M)

        file_name="obs_seq_????_VR_${timestr:0:8}_${timestr:8:4}.out"
        numsrc=$(find "${srcdir}/${timestr:0:8}/d1/DART" -name "${file_name}" | wc -l)
        numdes=$(find .                                  -name "${file_name}" | wc -l)
        if [[ $numdes -lt $numsrc ]]; then
            $show ln -sf ${srcdir}/${timestr:0:8}/d1/DART/${file_name} .
        fi
    done
    ;;
esac

exit 0
