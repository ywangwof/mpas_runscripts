#!/bin/bash

fcst_root="/scratch/ywang/MPAS/gnu/mpas_scripts/run_dirs"
dest_root="/scratch/ywang/MPAS/gnu/mpas_scripts/run_dirs/FCST"

eventdate="${1-20230331}"
eventimes=(1700 1800 1900 2000 2100 2200 2300 0000 0100 0200 0300)

fcstlength=$((6*3600))
fcstintvl=300
fcstmems=18

for evtime in ${eventimes[@]}; do
    if [[ $evtime -lt 1200 ]]; then
        nextday="1 day"
    else
        nextday=""
    fi

    evttime_dir="${fcst_root}/${eventdate}/fcst/${evtime}/mpassit"
    for mem in $(seq 1 $fcstmems); do
        memstr=$(printf "%02d" $mem)
        memdir="${evttime_dir}/mem$memstr"

        desdir="${dest_root}/${eventdate}/${evtime}/ENS_MEM_${memstr}"
        if [[ ! -d $desdir ]]; then
            mkdir -p $desdir
        fi
        cd $desdir

        for ((i=$fcstintvl;i<=$fcstlength;i+=$fcstintvl)); do
            fcsttimestr=$(date -u -d "${eventdate} ${evtime} $nextday $i seconds" +%Y-%m-%d_%H.%M.%S)
            wrftimestr=$(date -u -d "${eventdate} ${evtime} $nextday $i seconds" +%Y-%m-%d_%H:%M:%S)
            memfile="MPASSIT_${memstr}.${fcsttimestr}.nc"
            desfile="wrfwof_d01_${wrftimestr}"
            if [[ ! -e ${memdir}/${memfile} ]]; then
                echo "File: ${memdir}/${memfile} not exist."
                exit 1
            fi
            ln -sf ${memdir}/${memfile} ${desfile}
        done

        wrftimestr0=$(date -u -d "${eventdate} ${evtime} $nextday" +%Y-%m-%d_%H:%M:%S)
        wrftimestr1=$(date -u -d "${eventdate} ${evtime} $nextday ${fcstintvl} seconds" +%Y-%m-%d_%H:%M:%S)
        ln -sf wrfwof_d01_${wrftimestr1} wrfwof_d01_${wrftimestr0}
    done

    evttime_str=$(date -u -d "${eventdate} ${evtime} ${nextday}" +%Y%m%d%H%M)
    touch ${dest_root}/${eventdate}/fcst_${evttime_str}_start
done
