#!/bin/bash

fcst_root="/scratch/ywang/MPAS/mpas_scripts/run_dirs"
dest_root="/scratch/ywang/MPAS/mpas_scripts/run_dirs/FCST"

eventdate="${1-20230331}"
eventimes=(1700 1800 1900 2000 2100 2200 2300 0000 0100 0200 0300)

fcstlength=$((6*3600))
fcstintvl=300
fcstmems=18

for evtime in ${eventimes[@]}; do
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
            fcsttimestr=$(date -d "${eventdate} ${evtime} $i seconds" +%Y-%m-%d_%H.%M.%S)
            wrftimestr=$(date -d "${eventdate} ${evtime} $i seconds" +%Y-%m-%d_%H:%M:%S)
            memfile="MPASSIT_${memstr}.${fcsttimestr}.nc"
            desfile="wrfwof_d01_${wrftimestr}"
            if [[ ! -e ${memdir}/${memfile} ]]; then
                echo "File: ${memdir}/${memfile} not exist."
                exit 1
            fi
            ln -sf ${memdir}/${memfile} ${desfile}
        done

        wrftimestr0=$(date -d "${eventdate} ${evtime}" +%Y-%m-%d_%H:%M:%S)
        wrftimestr1=$(date -d "${eventdate} ${evtime} ${fcstintvl} seconds" +%Y-%m-%d_%H:%M:%S)
        ln -sf wrfwof_d01_${wrftimestr1} wrfwof_d01_${wrftimestr0}
    done
    touch ${dest_root}/${eventdate}/fcst_${eventdate}${evtime}_start
done
