#!/bin/bash
#
# Based on /home/Thomas.Jones/WOFS_DART/obs_scripts/Process_rto_OKMeso_15min.csh
#
# 08/28/2023 (Y. Wang)
# Changed to BASH for handling the environment sourcing consistently and
# better handling of the time loop.
# It will use these three executables from the DART package
#    ${DART_exec_dir}/convertdate
#    ${DART_exec_dir}/convert_okmeso
#    ${DART_exec_dir}/mpas_dart_obs_preprocess
#
#--------------------------------------------------------------

scpdir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
rootdir=$(realpath "$(dirname "${scpdir}")")
mpasdir="/scratch/yunheng.wang/MPAS/MPAS_PROJECT"

MESO_DIR=/work/rt_obs/Mesonet
DART_DIR=/scratch/yunheng.wang/MPAS/intel/frdd-DART

TEMPLATE_FILE=${scpdir}/input.nml.mesonet
MESOINFO_FILE=${scpdir}/geoinfo.csv
convert_okmeso=${DART_DIR}/observations/obs_converters/ok_mesonet/work/convert_ok_mesonet
obs_preprocess=${DART_DIR}/models/mpas_atm/work/mpas_dart_obs_preprocess

run_dir="${mpasdir}/run_dirs"
WORK_dir=${mpasdir}/OBS_SEQ/Mesonet

eventdateDF=$(date -u +%Y%m%d%H%M)

starthour=1500
endhour=0300

source ${rootdir}/modules/env.mpas_smiol
source ${rootdir}/scripts/Common_Utilfuncs.sh

function usage {
    echo " "
    echo "    USAGE: $0 [options] [DATETIME] [WORKDIR] [COMMAND]"
    echo " "
    echo "    PURPOSE: Preprocessing OK MESONET data in $MESO_DIR to $WORK_dir."
    echo " "
    echo "    DATETIME - Empty: Current UTC date and time"
    echo "               YYYYmmdd:       run this task for this event date."
    echo "               YYYYmmddHHMM:   run the task from event date $starthour Z up to YYYYmmddHHMM."
    echo " "
    echo "    COMMAND  - one of [ls, check, fix]"
    echo "               check    List the observations in the $MESO_DIR"
    echo "               ls       List the observations in the $WORK_dir"
    echo "               fix      Added '.missed' tag to missing file for the MPAS-WoFS workflow keeps going"
    echo " "
    echo "    OPTIONS:"
    echo "              -h                  Display this message"
    echo "              -n                  Show command to be run and generate job scripts only"
    echo "              -v                  Verbose mode"
    echo "              -s  start_time      Run task from start_time, default $starthour"
    echo "              -f  conf_file       Runtime configuration file, make it the last argument (after WORKDIR)."
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
conf_file=""

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
        #-n)
        #    show="echo"
        #    ;;
        #-v)
        #    verb=true
        #    ;;
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

if [[ ${conf_file} == "" ]]; then
    conf_file="${run_dir}/config.${eventdate}"
fi

if [[ -e ${conf_file} ]]; then
    eval "$(sed -n "/OBS_DIR=/p" ${conf_file})"
    WORK_dir=${OBS_DIR}/Mesonet
else
    if [[ "$cmd" =~ "check" ]]; then
        :
    else
        echo -e "${RED}ERROR${NC}: ${CYAN}${conf_file}${NC} not exist."
        exit 0
    fi
fi

echo -e "\nUse runtime Configruation file: ${CYAN}${conf_file}${NC}.\n"

if [[ $((10#$start_time)) -gt 1200 ]]; then
    timebeg="${eventdate}${start_time}"
else
    timebeg="${nextdate}${start_time}"
fi

if [[ ! -t 1  && ! "$cmd" == "check" ]]; then # "jobs"
    log_dir="${run_dir}/${eventdate}"

    if [[ ! -d ${log_dir} ]]; then
        echo "ERROR: ${log_dir} not exists."
        exit 1
    fi

    exec 1>> "${log_dir}/log.okmeso" 2>&1
fi

echo "=== $(date +%Y%m%d_%H:%M:%S) - $0 ${saved_args} ==="

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

if [[ ! -d ${WORK_dir}/work ]]; then
    mkdir -p ${WORK_dir}/work
fi
cd ${WORK_dir}/work || exit 1

cp ${MESOINFO_FILE} .
cp ${TEMPLATE_FILE} ./input.nml

########################################################################
#######   PROCESS OKMESO DATA ##########################################
########################################################################

timebeg_s=$(date -d "${timebeg:0:8} ${timebeg:8:4}" +%s)
timeend_s=$(date -d "${timeend:0:8} ${timeend:8:4}" +%s)

mesofiles=(); n=0; missedfiles=()
for((i=timebeg_s;i<=timeend_s;i+=900)); do

    timestr=$(date -d @$i +%Y%m%d%H%M%S)

    yyyy=${timestr:0:4}
    mm=${timestr:4:2}
    dd=${timestr:6:2}
    hh=${timestr:8:2}
    anl_min=${timestr:10:2}

    if [[ $hh -lt 15 ]]; then
        evtdate=$(date -d "$yyyy$mm$dd 1 day ago" +%Y%m%d)
        evty=${evtdate:0:4}
        evtm=${evtdate:4:2}
        evtd=${evtdate:6:2}
    else
        evty=$yyyy
        evtm=$mm
        evtd=$dd
    fi

    seq_filename="obs_seq_okmeso.${yyyy}${mm}${dd}${hh}${anl_min}"
    if [[ "$cmd" =~ ls|fix ]]; then
        if [[ -e ${WORK_dir}/${seq_filename} ]]; then
            echo -e "    ${GREEN}${WORK_dir}/${seq_filename}${NC}"
        else
            echo -e "    ${RED}${WORK_dir}/${seq_filename}${NC}"
            if [[ "$cmd" == "fix" ]]; then
                touch "${WORK_dir}/${seq_filename}.missed"
                missedfiles+=("${WORK_dir}/${seq_filename}.missed")
            fi
        fi
        ((n++))
        continue
    fi

    mesonet_obs_file="${MESO_DIR}/${yyyy}/${mm}/${dd}/mesonet.realtime.${yyyy}${mm}${dd}${hh}${anl_min}.mdf"

    if [[ "$cmd" == "check" ]]; then
        if [[ -e ${mesonet_obs_file} ]]; then
            mesofiles+=("${mesonet_obs_file}")
            ((n++))
        else
            mesofiles+=("missing.realtime.${yyyy}${mm}${dd}${hh}${anl_min}.mdf")
        fi
        continue
    fi

    if [[ ! -e ${mesonet_obs_file} ]]; then
        echo "File: ${mesonet_obs_file} not found."
        exit 1
    fi

    if [[ ! -e ${WORK_dir}/${seq_filename} ]]; then

        #MPAS_INITFILE=${MPASWoFS_DIR}/${evty}${evtm}${evtd}/dacycles/${phh}${pmin}/wofs_mpas_01.restart.${mpas_timestr}.nc
        MPAS_INITFILE=${run_dir}/${evty}${evtm}${evtd}/init/wofs_mpas.invariant.nc
        if [[ ! -e ${MPAS_INITFILE} ]]; then
            echo "MPAS restart file: ${MPAS_INITFILE} not exist"
            exit 0
        fi
        echo "Using ${MPAS_INITFILE} as init.nc ...."
        ln -sf ${MPAS_INITFILE} init.nc

        wait_for_file_age "${mesonet_obs_file}" 60

        cp "${mesonet_obs_file}" okmeso_mdf.in

        # run convert_okmeso
        echo "=== Processing ${mesonet_obs_file}"
        echo "Running srun -n 1 ${convert_okmeso} ..."
        srun ${convert_okmeso}

        # run mpas_dart_obs_preprocess
#        g_datestr=($(${convert_date} << EOF
#1
#$yyyy $mm $dd $hh ${anl_min} 00
#EOF
#))
#        g_date=${g_datestr[-2]}
#        g_sec=${g_datestr[-1]}

        read -r -a g_dates < <(convert2days "$yyyy$mm$dd" "$hh:${anl_min}:00")
        g_date=${g_dates[0]}
        g_sec=${g_dates[1]}

        mv obs_seq.okmeso obs_seq.old

        echo "${g_date} ${g_sec}" | srun ${obs_preprocess}

        # Check and Save the result file
        num_obs_kind=$(head -3 obs_seq.new | tail -1)

        if [[ ${num_obs_kind} -gt 0 ]]; then
            echo "Saving ${WORK_dir}/${seq_filename}"
            mv obs_seq.new ${WORK_dir}/${seq_filename}
        else
            echo "O observations in ${WORK_dir}"
            rm obs_seq.new
        fi

        # clear old intermediate (text) files
        rm obs_seq.old okmeso_mdf.in dart_log.out dart_log.nml
        echo ""
    else
        echo "${WORK_dir}/${seq_filename} exists"
    fi
done

if [[ "$cmd" == "check" ]]; then
    if [[ -t 1 ]]; then
        for obsfile in "${mesofiles[@]}"; do
            if [[ -e ${obsfile} ]]; then
                echo -e "    ${GREEN}${obsfile}${NC}"
            else
                echo -ne "    ${RED}${obsfile}${NC}"
            fi
        done
    else
        echo "$n"
        return_str=""
        for obsfile in "${mesofiles[@]}"; do
            return_str="$return_str $(basename $obsfile)"
        done
        echo "${return_str}"
    fi
elif [[ "$cmd" == "fix" ]]; then
    echo -e "\nTouched missing files (${#missedfiles[@]}):\n"
    for filename in "${missedfiles[@]}"; do
        echo -e "    ${RED}$filename${NC}"
    done
fi

cd ${WORK_dir} || exit $?
rm -rf ${WORK_dir}/work

exit 0
