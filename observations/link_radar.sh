#!/bin/bash

show=""

timebeg="${1-2024041515}"
timeend="${2-2024041603}"

eventhr=${timebeg:8:2}
if [[ $((10#$eventhr)) -lt 12 ]]; then
    eventdate=$(date -d "${timebeg:0:8} $eventhr 1 day ago" +%Y%m%d)
else
    eventdate=${timebeg:0:8}
fi

srcdir="/work2/wof/realtime/OBSGEN/CLOUD_OBS"
destdir="/scratch/ywang/MPAS/gnu/mpas_scripts/run_dirs/OBS_SEQ"

timebeg_s=$(date -d "${timebeg:0:8} ${timebeg:8:2}" +%s)
timeend_s=$(date -d "${timeend:0:8} ${timeend:8:2}" +%s)

#-----------------------------------------------------------------------
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

#-----------------------------------------------------------------------
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

exit 0
