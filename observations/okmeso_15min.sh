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

timebeg=${1-2023033115}
timeend=${2-2023033115}

MESO_DIR=/work/rt_obs/Mesonet
WORK_dir=/scratch/ywang/MPAS/mpas_scripts/run_dirs/OBS_SEQ/Mesonet
TEMPLATE_FILE=/scratch/ywang/MPAS/mpas_scripts/observations/input.nml.mesonet
MESOINFO_FILE=/scratch/ywang/MPAS/mpas_scripts/observations/geoinfo.csv
MPASWoFS_DIR=/scratch/ywang/MPAS/mpas_scripts/run_dirs
convert_okmeso=/scratch/ywang/MPAS/DART/observations/obs_converters/ok_mesonet/work/convert_ok_mesonet
obs_preprocess=/scratch/ywang/MPAS/DART/models/mpas_atm/work/mpas_dart_obs_preprocess
convert_date=/scratch/ywang/MPAS/DART/models/wrf/work/convertdate

if [[ ! -d ${WORK_dir}/work ]]; then
    mkdir -p ${WORK_dir}/work
fi
cd ${WORK_dir}/work

cp ${MESOINFO_FILE} .
cp ${TEMPLATE_FILE} ./input.nml

source /scratch/ywang/MPAS/mpas_scripts/modules/env.mpas_smiol_impi

########################################################################
#######   PROCESS OKMESO DATA ##########################################
########################################################################

timebeg_s=$(date -d "${timebeg:0:8} ${timebeg:8:2}:00:00" +%s)
timeend_s=$(date -d "${timeend:0:8} ${timeend:8:2}:00:00" +%s)

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

    #j=$((i-900))
    #timepre=$(date -d@j +%Y%m%d%H%M%S)
    #%timepre="${yyyy}${mm}${dd}1500"
    #pyyyy=${timepre:0:4}
    #pmm=${timepre:4:2}
    #pdd=${timepre:6:2}
    phh="15"  #${timepre:8:2}
    pmin="00" #${timepre:10:2}

    #mpas_timestr="${yyyy}-${mm}-${dd}_${hh}.${anl_min}.00"
    mpas_timestr="${evty}-${evtm}-${evtd}_15.15.00"

    MPAS_INITFILE=${MPASWoFS_DIR}/${evty}${evtm}${evtd}/dacycles/${phh}${pmin}/wofs_mpas_01.restart.${mpas_timestr}.nc
    if [[ ! -e ${MPAS_INITFILE} ]]; then
        echo "MPAS restart file: ${MPAS_INITFILE} not exist"
        exit 0
    fi
    echo ${MPAS_INITFILE}
    ln -sf ${MPAS_INITFILE} init.nc

    mesonet_obs_file="${MESO_DIR}/${yyyy}/${mm}/${dd}/mesonet.realtime.${yyyy}${mm}${dd}${hh}${anl_min}.mdf"

    cp ${mesonet_obs_file} okmeso_mdf.in

    # run convert_okmeso
    echo "=== Processing ${mesonet_obs_file}"
    echo "Running srun -n 1 ${convert_okmeso} ..."
    srun ${convert_okmeso}

    # run mpas_dart_obs_preprocess
    g_datestr=($(${convert_date} << EOF
1
$yyyy $mm $dd $hh ${anl_min} 00
EOF
))
    g_date=${g_datestr[-2]}
    g_sec=${g_datestr[-1]}

    mv obs_seq.okmeso obs_seq.old

    echo "${g_date} ${g_sec}" | srun ${obs_preprocess}

    # Check and Save the result file
    num_obs_kind=$(head -3 obs_seq.new | tail -1)

    if [[ ${num_obs_kind} -gt 0 ]]; then
        echo "Saving ${WORK_dir}/obs_seq_okmeso.${yyyy}${mm}${dd}${hh}${anl_min}"
        mv obs_seq.new ${WORK_dir}/obs_seq_okmeso.${yyyy}${mm}${dd}${hh}${anl_min}
    else
        rm obs_seq.new
    fi

    # clear old intermediate (text) files
    rm obs_seq.old okmeso_mdf.in dart_log.out dart_log.nml
    echo ""
done

exit 0
