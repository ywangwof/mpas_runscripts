#!/bin/bash

srcdir=/work2/wof/realtime/OBSGEN/CLOUD_OBS
destdir=/scratch/ywang/MPAS/gnu/mpas_scripts/run_dirs/OBS_SEQ/CWP
run_dir="/scratch/ywang/MPAS/gnu/mpas_scripts/run_dirs"

eventdateDF=$(date -u +%Y%m%d%H%M)

function usage {
    echo " "
    echo "    USAGE: $0 [options] [DATETIME]"
    echo " "
    echo "    PURPOSE: Preprocessing CWP data in $srcdir to $destdir."
    echo " "
    echo "    DATETIME - Empty: Current UTC date and time"
    echo "               YYYYmmdd:       run this task for this event date."
    echo " "
    echo "    OPTIONS:"
    echo "              -h                  Display this message"
    echo "              -n                  Show command to be run and generate job scripts only"
    echo "              -v                  Verbose mode"
    echo "              -check              List the observations in the $srcdir"
    echo "              -ls                 List the observations in the $destdir"
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
    nextday=true
fi

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
        -*)
            echo "Unknown option: $key"
            usage 2
            ;;
        *)
            if [[ $key =~ ^[0-9]{8}$ ]]; then
                eventdate=${key}
                nextday=true
            else
                echo ""
                echo "ERROR: unknown argument, get [$key]."
                usage 3
            fi
            ;;
    esac
    shift # past argument or value
done

nextdate=$(date -u -d "${eventdate} 1 day" +%Y%m%d)

if [[ ! -t 1 && ! "$cmd" == "check" ]]; then # "jobs"
    log_dir="${run_dir}/${eventdate}"

    if [[ ! -d ${log_dir} ]]; then
        echo "ERROR: ${log_dir} not exists."
        exit 1
    fi

    exec 1>> "${log_dir}/log.cwp" 2>&1
fi

echo "=== $(date +%Y%m%d_%H:%M:%S) - $0 ${saved_args} ==="

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

case $cmd in
    ls )
        echo "ls -l ${destdir}"
        $show ls ${destdir}/obs_seq_cwp.G16_V04.${eventdate}*
        if [[ $nextday == true ]]; then
            $show ls ${destdir}/obs_seq_cwp.G16_V04.${nextdate}*
        fi
        ;;

    check )
        if [[ -t 1 ]]; then
            echo "ls -l ${srcdir}/${eventdate}/d1"
            $show ls -l ${srcdir}/${eventdate}/d1/????-cwpobs.nc
            if [[ $nextday == true ]]; then
                $show ls -l ${srcdir}/${nextdate}/d1/????-cwpobs.nc
            fi
        else
            cwpfiles=()
            for fn in "${srcdir}/${eventdate}"/d1/????-cwpobs.nc; do
                cwpfiles+=("$(basename $fn)")
            done
            echo "${cwpfiles[*]}"
        fi
        ;;
    * )
        # >>> mamba initialize >>>
        # !! Contents within this block are managed by 'mamba init' !!
        export MAMBA_EXE='/home/yunheng.wang/tools/micromamba/bin/micromamba';
        export MAMBA_ROOT_PREFIX='/home/yunheng.wang/tools/micromamba';
        __mamba_setup="$("$MAMBA_EXE" shell hook --shell zsh --root-prefix "$MAMBA_ROOT_PREFIX" 2> /dev/null)"
        if [ $? -eq 0 ]; then
            eval "$__mamba_setup"
        else
            alias micromamba="$MAMBA_EXE"  # Fallback on help from mamba activate
        fi
        unset __mamba_setup
        # <<< mamba initialize <<<
        micromamba activate wofs_an

        cd /scratch/ywang/MPAS/gnu/mpas_scripts/observations || exit 0

        python cwpobs2dart.py -i "${srcdir}/${eventdate}/d1" -o ${destdir} -d "${eventdate}"
        if [[ $nextday == true ]]; then
            python cwpobs2dart.py -i "${srcdir}/${nextdate}/d1" -o ${destdir} -d "${nextdate}"
        fi

        ;;
esac

exit 0
