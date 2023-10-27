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

source /scratch/ywang/MPAS/mpas_scripts/modules/env.mpas_smiol_impi

daily=no

# if daily is 'no' and zeroZ is 'yes', input files at 0Z will be translated
# into output files also marked 0Z.  otherwise, they will be named with the
# previous day number and 24Z (chose here based on what script will be
# processing these files next.  the 'create_real_obs' script assumes
# filenames with the pattern 6Z,12Z,18Z,24Z, so 'no' is right for it.)
# this variable is ignored completely if

timebeg=${1-2023033115}
timeend=${2-2023040103}

DART_DIR=/scratch/ywang/MPAS/DART
WORK_dir=/scratch/ywang/MPAS/mpas_scripts/run_dirs/OBS_SEQ/Bufr
DART_exec_dir=${DART_DIR}/observations/obs_converters/NCEP/prep_bufr/exe
NML_TEMPLATE=/scratch/ywang/MPAS/mpas_scripts/observations/input.nml.bufrobs.template
convert=yes

timebeg_s=$(date -d "${timebeg:0:8} ${timebeg:8:2}:00:00" +%s)
timeend_s=$(date -d "${timeend:0:8} ${timeend:8:2}:00:00" +%s)

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

    BUFR_dir=/work/rt_obs/SBUFR/${inyear}/${inmonth}/${inday}

    cd ${WORK_dir}/work

    # clear any old intermediate (text) files
    #rm -f temp_obs prepqm.in prepqm.out
    #rm -f dart_log*
    rm -rf *

    ## MODIFY input.nml with correct date
    sedfile=$(mktemp -t sbufr_${timestr}.sed_XXXX)
    cat <<EOF > $sedfile
s/YEAR/${inyear}/
s/MON/${inmonth}/
s/DAY/${inday}/
s/HOUR/${inhour}/g
s/ENDYR/${endyear}/g
s/ENDMON/${endmonth}/
s/ENDDAY/${endday}/
s/ENDHOUR/${endhour}/g
EOF
    sed -f $sedfile ${NML_TEMPLATE} > ./input.nml
    rm -f $sedfile

    mm=$inmonth
    dd=$inday
    hh=$inhour

    # fix the BUFR_in line below to match what you have.  if the file is
    # gzipped, you can leave it and this program will unzip it
    BUFR_in=${BUFR_dir}/rap.${inyear}${mm}${dd}${hh}.prepbufr.tm00

    if [[ -e ${BUFR_in} ]]; then
       echo "copying ${BUFR_in} into prepqm.in"
       rm -f prepqm.in
       cp -f ${BUFR_in} prepqm.in
    elif [[ -e ${BUFR_in}.gz ]]; then
       echo "unzipping ${BUFR_in}.gz into prepqm.in"
       rm -f prepqm.in
       gunzip -c -f ${BUFR_in}.gz >! prepqm.in
    else
       echo "MISSING INPUT FILE: ${BUFR_in} or ${BUFR_in}.gz"
       echo "Script will abort now."
       exit -1
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
done

exit 0
