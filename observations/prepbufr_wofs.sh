#!/bin/bash
#
# Based on /home/Thomas.Jones/WOFS_DART/obs_scripts/prepbufr_wofs.csh.
#
# 08/28/2023 (Y. Wang)
# Changed to BASH for handling the environment sourcing consistently and
# better handling of the time loop.
# It will use these two executable from the DART package
#    ${DART_exec_dir}/prepbufr.x
#    ${DART_exec_dir}/create_real_obs
#
#--------------------------------------------------------------
# DESCRIPTION:
#
#  This script is used to generate daily (3:01Z to 3:00Z of next day) decoded
#  NCEP reanalysis PREPBUFR text/ascii data.
#
# there are two ways to run this script - either submit it to a batch
# system (LSF job commands are included), or this script can be called
# as a command line executable.  see the sections below for what options
# to set at the top of the script before it is run.
#
# LSF batch system settings, which will certainly need to be customized
# for your system, e.g. -P project charge code, different queue name, etc.
#BSUB -o prepbufr_%j.out
#BSUB -e prepbufr_%j.err
#BSUB -J prepbufr
#BSUB -q regular
#BSUB -W 00:30
#BSUB -P batch
#BSUB -n 1
#
# to run this from the command line, see below for a choice of whether
# to invoke this script with 4 args: year, month, start/end day,
# or hardcode the dates into the script and run it by name with no args.
#
#--------------------------------------------------------------
# daily=no
# if daily is 'no' and zeroZ is 'yes', input files at 0Z will be translated
# into output files also marked 0Z.  otherwise, they will be named with the
# previous day number and 24Z (chose here based on what script will be
# processing these files next.  the 'create_real_obs' script assumes
# filenames with the pattern 6Z,12Z,18Z,24Z, so 'no' is right for it.)
# this variable is ignored completely if


DART_DIR=/scratch/ywang/MPAS/gnu/frdd-DART
WORK_dir=/scratch/ywang/MPAS/gnu/mpas_scripts/run_dirs/OBS_SEQ/Bufr
DART_exec_dir=${DART_DIR}/observations/obs_converters/NCEP/prep_bufr/exe
NML_TEMPLATE=/scratch/ywang/MPAS/gnu/mpas_scripts/observations/input.nml.bufrobs.template
BUFR_DIR=/work/rt_obs/SBUFR
run_dir="/scratch/ywang/MPAS/gnu/mpas_scripts/run_dirs"
convert=yes

eventdateDF=$(date -u +%Y%m%d%H%M)

starthour=1500
endhour=0300

function usage {
    echo " "
    echo "    USAGE: $0 [options] [DATETIME]"
    echo " "
    echo "    PURPOSE: Preprocessing PrepBufr data in $BUFR_DIR to $WORK_dir."
    echo " "
    echo "    DATETIME - Empty: Current UTC date and time"
    echo "               YYYYmmdd:       run this task for this event date."
    echo "               YYYYmmddHHMM:   run the task from event date $starthour Z up to YYYYmmddHHMM."
    echo " "
    echo "    OPTIONS:"
    echo "              -h                  Display this message"
    echo "              -n                  Show command to be run and generate job scripts only"
    echo "              -v                  Verbose mode"
    echo "              -check              Check observation availability in $BUFR_DIR"
    echo "              -ls                 List the processed observations in $WORK_dir"
    echo "              -s  start_time      Run task from start_time, default $starthour"
    echo " "
    echo " "
    echo "                                     -- By Y. Wang (2024.04.26)"
    echo " "
    exit $1
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
            else
                echo ""
                echo "ERROR: unknown argument, get [$key]."
                usage 3
            fi
            ;;
    esac
    shift # past argument or value
done

if [[ $((10#$start_time)) -gt 1200 ]]; then
    timebeg="${eventdate}${start_time}"
else
    timebeg="${nextdate}${start_time}"
fi

if [ ! -t 1 ]; then # "jobs"
    log_dir="${run_dir}/${eventdate}"

    if [[ ! -d ${log_dir} ]]; then
        echo "ERROR: ${log_dir} not exists."
        exit 1
    fi

    exec 1>> "${log_dir}/log.prepbufr" 2>&1
fi

echo "=== $(date +%Y%m%d_%H:%M:%S) - $0 ${saved_args} ==="

source /scratch/ywang/MPAS/gnu/mpas_scripts/modules/env.mpas_smiol

source /scratch/ywang/MPAS/gnu/mpas_scripts/scripts/Common_Utilfuncs.sh

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

timebeg_s=$(date -d "${timebeg:0:8} ${timebeg:8:4}" +%s)
timeend_s=$(date -d "${timeend:0:8} ${timeend:8:4}" +%s)

for((i=timebeg_s;i<=timeend_s;i+=3600)); do

    timestr=$(date -d @$i +%Y%m%d%H)

    inyear=${timestr:0:4}
    inmonth=${timestr:4:2}
    inday=${timestr:6:2}
    inhour=${timestr:8:2}

    endyear=${inyear}              # each file contain one valid hour only
    endmonth=${inmonth}
    endday=${inday}
    endhour=${inhour}

    BUFR_dir="${BUFR_DIR}/${inyear}/${inmonth}/${inday}"

    # fix the BUFR_in line below to match what you have.  if the file is
    # gzipped, you can leave it and this program will unzip it
    BUFR_in=${BUFR_dir}/rap.${inyear}${inmonth}${inday}${inhour}.prepbufr.tm00

    if [[ "$cmd" == "check" ]]; then
        ls -l ${BUFR_in}
        continue
    fi

    if [[ "$cmd" == "ls" ]]; then
        ls -l ${WORK_dir}/obs_seq_bufr.${inyear}${inmonth}${inday}${inhour}
        continue
    fi

    if [[ ! -e ${WORK_dir}/obs_seq_bufr.${inyear}${inmonth}${inday}${inhour} ]]; then

        cd ${WORK_dir}/work || exit 0

        # clear any old intermediate (text) files
        #rm -f temp_obs prepqm.in prepqm.out
        #rm -f dart_log*
        rm -rf *

        ## MODIFY input.nml with correct date
        sedfile=$(mktemp -t sbufr_${timestr}.sed_XXXX)
        cat <<EOF > $sedfile
s/ENDYR/${endyear}/g
s/ENDMON/${endmonth}/g
s/ENDDAY/${endday}/g
s/ENDHOUR/${endhour}/g
s/YEAR/${inyear}/g
s/MON/${inmonth}/g
s/DAY/${inday}/g
s/HOUR/${inhour}/g
EOF
        sed -f $sedfile ${NML_TEMPLATE} > ./input.nml
        rm -f $sedfile

        if [[ -e ${BUFR_in} ]]; then
            wait_for_file_age "${BUFR_in}" 120
            echo "copying ${BUFR_in} into prepqm.in"
            rm -f prepqm.in
            cp -f ${BUFR_in} prepqm.in
        elif [[ -e ${BUFR_in}.gz ]]; then
            wait_for_file_age "${BUFR_in}.gz" 120
            echo "unzipping ${BUFR_in}.gz into prepqm.in"
            rm -f prepqm.in
            gunzip -c -f ${BUFR_in}.gz >! prepqm.in
        else
            echo "INPUT FILE: ${BUFR_in} or ${BUFR_in}.gz not found"
            #echo "Script will abort now."
            exit 1
        fi

        # byte swapping
        if [[ $convert == 'yes' ]]; then
           echo "byteswapping bigendian to littleendian prepqm.in"
           mv -f prepqm.in prepqm.bigendian
           ${DART_exec_dir}/grabbufr.x prepqm.bigendian prepqm.littleendian
           mv -f prepqm.littleendian prepqm.in
           rm -f prepqm.bigendian
        fi

        ${DART_exec_dir}/prepbufr.x
        mv prepqm.out temp_obs

        #### NOW DO CONVERSION TO obs_seq file
        ${DART_exec_dir}/create_real_obs
        mv obs_seq.bufr  ${WORK_dir}/obs_seq_bufr.${inyear}${inmonth}${inday}${inhour}
    fi
done

exit 0
