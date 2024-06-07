#!/bin/bash

fcst_root="/scratch/ywang/MPAS/gnu/mpas_scripts/run_dirs"

eventdateDF=$(date -u +%Y%m%d)

eventdate=${1-"${eventdateDF}"}

fcstlength=$((6*3600))
fcstintvl=300
fcstmems=18

#-----------------------------------------------------------------------

function usage {
    echo " "
    echo "    USAGE: $0 [options] DATETIME"
    echo " "
    echo "    PURPOSE: Link the MPASSIT processed MPAS forecast files for WoFS post-processing."
    echo " "
    echo "    DATETIME - Case date in YYYYmmdd."
    echo " "
    echo "    OPTIONS:"
    echo "              -h                  Display this message"
    echo "              -n                  Show command to be run and generate job scripts only"
    echo "              -v                  Verbose mode"
    echo "              -x                  FCST Directory affix. Defaut: empty"
    echo "              -src  fcst_root     FCST cycles directory. Default: ${fcst_root}"
    echo "              -dest dest_root     WRF FCST directory name. Default: \${fcst_root}/FCST"
    echo "              -s starttime        in HHMM. Default: 1700"
    echo "              -e endtime          in HHMM. Default: 0300"
    echo "              -b 5                Forecast first available time in minutes. Default: 5 minutes"
    echo "              -c                  Overwritten existing files, otherwise, keep existing files"
    echo " "
    echo "   DEFAULTS:"
    echo "              eventdt    = $eventdate"
    echo "              fcst_root  = $fcst_root"
    echo "              dest_root  = $fcst_root/FCST"
    echo " "
    echo "                                     -- By Y. Wang (2024.04.17)"
    echo " "
    exit "$1"
}

#-----------------------------------------------------------------------
#
# Handle command line arguments (override default settings)
#
#-----------------------------------------------------------------------
#% ARGS
show=""
verb=false
force_clean=false

eventdate=${eventdateDF}
starttime="1700"
endtime="0300"
affix=""
fcstbeg="5"

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
        -c)
            force_clean=true
            ;;
        -x)
            affix="$2"
            shift
            ;;
        -src)
            if [[ ! -d ${2} ]]; then
                echo "ERROR: directory ${2} not exist"
            else
                fcst_root="$2"
            fi
            shift
            ;;
       -dest)
            if [[ ! -d ${2} ]]; then
                echo "ERROR: directory ${2} not exist"
            else
                dest_root="$2"
            fi
            shift
            ;;
        -b)
            fcstbeg="$2"
            if [[ ! ${fcstbeg} =~ ^[0-9]+$ ]]; then
                echo "ERROR: ${fcstbeg} is not digits."
                usage 1
            fi
            shift
            ;;
        -s )
            if [[ $2 =~ ^[0-9]{4}$ ]]; then
                starttime="${2}"
            else
                echo "ERROR: Start time should be in HHMM, got \"$2\"."
                usage 1
            fi
            shift
            ;;
        -e )
            if [[ $2 =~ ^[0-9]{4}$ ]]; then
                endtime=$2
            else
                echo "ERROR: End time should be in HHMM, got \"$2\"."
                usage 1
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
            else
                echo ""
                echo "ERROR: unknown argument, get [$key]."
                usage 3
            fi
            ;;
    esac
    shift # past argument or value
done

fcstdir="fcst${affix}"

if [[ ! -d ${fcst_root}/${eventdate}/${fcstdir} ]]; then
    echo "ERROR: ${fcst_root}/${eventdate}/${fcstdir} not exist."
    usage 1
fi

if [[ -z ${dest_root} ]]; then
    dest_root="${fcst_root}/FCST"
fi

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

starthour=${starttime:0:2}
if [[ $((10#$starthour)) -lt 12 ]]; then
    startdatetime=$(date -u -d "$eventdate $starttime 1 day" "+%Y%m%d %H%M")
else
    startdatetime=$(date -u -d "$eventdate $starttime" "+%Y%m%d %H%M")
fi

endhour=${endtime:0:2}
if [[ $((10#$endhour)) -lt 12 ]]; then
    enddatetime=$(date -u -d "$eventdate $endtime 1 day" "+%Y%m%d %H%M")
else
    enddatetime=$(date -u -d "$eventdate $endtime" "+%Y%m%d %H%M")
fi

start_s=$(date -u -d "${startdatetime}" +%s)
end_s=$(date -u -d "${enddatetime}" +%s)

for ((s=start_s;s<=end_s;s+=3600)); do
    evtime=$(date -u -d @$s +%H%M)
    evttime_str=$(date -u -d @$s +%Y%m%d%H%M)

    evttime_dir="${fcst_root}/${eventdate}/${fcstdir}/${evtime}/mpassit"
    for mem in $(seq 1 $fcstmems); do
        memstr=$(printf "%02d" "$mem")
        memdir="${evttime_dir}/mem$memstr"

        desdir="${dest_root}/${eventdate}${affix}/${evtime}/ENS_MEM_${memstr}"
        if [[ ! -d $desdir ]]; then
            mkdir -p "${desdir}"
        fi
        cd "${desdir}" || exit 0

        #echo "Linking member $memstr from $memdir to $desdir ...."
        for ((i=fcstbeg*60;i<=fcstlength;i+=fcstintvl)); do
            (( fcsttime = s+i ))
            fcsttimestr=$(date -u -d @$fcsttime +%Y-%m-%d_%H.%M.%S)
            wrftimestr=$(date -u -d @$fcsttime  +%Y-%m-%d_%H:%M:%S)
            memfile="MPASSIT_${memstr}.${fcsttimestr}.nc"
            desfile="wrfwof_d01_${wrftimestr}"
            if [[ ! -f ${desfile} || ${force_clean} == true ]]; then
                if [[ ! -e ${memdir}/${memfile} ]]; then
                    echo "Waiting for ${memdir}/${memfile} ...."
                    while [[ ! -e ${memdir}/${memfile} ]]; do
                        sleep 10
                    done
                fi
                ln -sf "${memdir}/${memfile}" "${desfile}"
            else
                :
                #echo "${desfile} exists"
            fi
        done

        if [[ ${fcstbeg} -gt 0 ]]; then
            (( begs = s + fcstbeg*60 ))
            wrftimestr0=$(date -u -d @$s    +%Y-%m-%d_%H:%M:%S)
            wrftimestr1=$(date -u -d @$begs +%Y-%m-%d_%H:%M:%S)
            ln -sf "wrfwof_d01_${wrftimestr1}" "wrfwof_d01_${wrftimestr0}"
        fi
    done

    touch "${dest_root}/${eventdate}${affix}/fcst_${evttime_str}_start"
done

exit 0
