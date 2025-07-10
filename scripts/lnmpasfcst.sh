#!/bin/bash

mpasworkdir="/scratch/wofs_mpas/run_dirs"

eventdateDF=$(date -u +%Y%m%d)

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
    echo "    DATETIME - Case date as YYYYmmdd."
    echo " "
    echo "    OPTIONS:"
    echo "              -h                  Display this message"
    echo "              -n                  Show command to be run and generate job scripts only"
    echo "              -v                  Verbose mode"
    echo "              -src  fcst_root     FCST cycles directory. Default: ${mpasworkdir}"
    echo "              -dest dest_root     WRF FCST directory name. Default: \${fcst_root}/FCST"
    echo "              -s    starttime     in HHMM or YYYYmmddHHMM. Default: 1700"
    echo "              -e    endtime       in HHMM or YYYYmmddHHMM. Default: 0300"
    echo "              -b    5             Forecast first available time in minutes. Default: 5 minutes"
    echo "              -c                  Overwritten existing files, otherwise, keep existing files"
    echo "              -f conf_file        Configuration file for this case. Default: \${WORKDIR}/config.\${eventdate}"
    echo " "
    echo "   DEFAULTS:"
    echo "              eventdt    = $eventdateDF"
    echo "              fcst_root  = $mpasworkdir"
    echo "              dest_root  = $mpasworkdir/FCST"
    echo " "
    echo "                                     -- By Y. Wang (2024.04.17)"
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

    #-------------------------------------------------------------------
    # Parse command line arguments
    #-------------------------------------------------------------------

    while [[ $# -gt 0 ]]; do
        key="$1"

        case $key in
            -h)
                usage 0
                ;;
            -n)
                args["show"]="echo"
                ;;
            -v)
                args["verb"]=true
                ;;
            -c)
                args["force_clean"]=true
                ;;
            -src)
                if [[ ! -d ${2} ]]; then
                    echo "ERROR: directory ${2} not exist"
                else
                    args["fcst_root"]="$2"
                fi
                shift
                ;;
           -dest)
                if [[ ! -d ${2} ]]; then
                    echo "ERROR: directory ${2} not exist"
                else
                    args["dest_root"]="$2"
                fi
                shift
                ;;
            -f)
                args["config_file"]="$2"
                shift
                ;;
            -b)
                args["fcstbeg"]="$2"
                if [[ ! ${2} =~ ^[0-9]+$ ]]; then
                    echo "ERROR: ${2} is not digits."
                    usage 1
                fi
                shift
                ;;
            -s )
                if [[ $2 =~ ^[0-9]{4}$ || $2 =~ ^[0-9]{12}$ ]]; then
                    args["starttime"]="${2}"
                else
                    echo "ERROR: Start time should be in HHMM, got \"$2\"."
                    usage 1
                fi
                shift
                ;;
            -e )
                if [[ $2 =~ ^[0-9]{4}$ || $2 =~ ^[0-9]{12}$ ]]; then
                    args["endtime"]=$2
                else
                    echo "ERROR: End time should be in HHMM, got \"$2\"."
                    usage 1
                fi
                shift
                ;;

            -* )
                echo "Unknown option: $key"
                usage 2
                ;;
            * )
                if [[ $key =~ ^[0-9]{8}$ ]]; then
                    args["eventdate"]=${key}
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
}

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#
#@ MAIN entry
#
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#% ARGS

parse_args "$@"

[[ -v args["verb"] ]] && verb=${args["verb"]} || verb=false
[[ -v args["show"] ]] && show=${args["show"]} || show=""

[[ -v args["force_clean"] ]] && force_clean=${args["force_clean"]} || force_clean=false
[[ -v args["fcstbeg"] ]]     && fcstbeg=${args["fcstbeg"]}         || fcstbeg=5

[[ -v args["fcst_root"] ]] && fcst_root=${args["fcst_root"]} || fcst_root="${mpasworkdir}"
[[ -v args["dest_root"] ]] && dest_root=${args["fcst_root"]} || dest_root="${fcst_root}/FCST"

[[ -v args["eventdate"] ]] && eventdate=${args["eventdate"]} || eventdate=${eventdateDF}
[[ -v args["starttime"] ]] && starttime=${args["starttime"]} || starttime="1700"
[[ -v args["endtime"] ]]   && endtime=${args["endtime"]}     || endtime="0300"

[[ -v args["config_file"] ]] && config_file=${args["config_file"]} || config_file="${fcst_root}/config.${eventdate}"

if [[ -v args["config_file"] ]]; then
    config_file=${args["config_file"]}

    if [[ "$config_file" =~ "/" ]]; then
        fcst_root=$(realpath "$(dirname "${config_file}")")
    else
        config_file="${fcst_root}/${config_file}"
    fi

    if [[ ${config_file} =~ config\.([0-9]{8})(.*) ]]; then
        [[ -v args["eventdate"] ]] || eventdate="${BASH_REMATCH[1]}"
        affix="${BASH_REMATCH[2]}"
    else
        echo -e "${RED}ERROR${NC}: Config file ${CYAN}${config_file}${NC} not the right format config.YYYYmmdd[_*]."
        exit 1
    fi
else
    config_file="${fcst_root}/config.${eventdate}"
    affix=""
fi

if [[ -f ${config_file} ]]; then
    fcstlength=$(grep '^ *fcst_length_seconds=' "${config_file}" | cut -d'=' -f2 | cut -d' ' -f1 | tr -d '(')
    fcstintvl=$(grep '^ *OUTINVL='              "${config_file}" | cut -d'=' -f2)
    readarray -t members < <(grep '^ *ENS_SIZE=' "${config_file}" | cut -d'=' -f2)
    fcstmems=${members[-1]}
else
    echo " "
    echo "ERROR: Config file - ${config_file} not exist."
    usage 1
fi

fcstdir="fcst${affix}"

if [[ ! -d ${fcst_root}/${eventdate}/${fcstdir} ]]; then
    echo " "
    echo "ERROR: Forecast directory - ${fcst_root}/${eventdate}/${fcstdir} not exist."
    usage 1
fi

#-----------------------------------------------------------------------
# Set Event End Date and Time
#-----------------------------------------------------------------------

startday=""
if [[ ${#starttime} -eq 12 ]]; then
    startdatetime=${starttime}
else
    (( 10#$starttime < 1500 )) && startday="1 day"
    startdatetime="${eventdate}${starttime}"
fi

endday=""
if [[ ${#endtime} -eq 12 ]]; then
    enddatetime=${endtime}
else
    (( 10#$endtime < 1500 )) && endday="1 day"
    enddatetime="${eventdate}${endtime}"
fi

start_s=$(date -u -d "${startdatetime:0:8} ${startdatetime:8:4} $startday" +%s)
end_s=$(date   -u -d "${enddatetime:0:8}   ${enddatetime:8:4}   $endday"   +%s)

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#% ENTRY

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
