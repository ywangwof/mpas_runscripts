#!/bin/bash
script_dir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
rootdir=$(realpath "$(dirname "${script_dir}")")
#rootdir="/scratch/ywang/MPAS/gnu/mpas_scripts"

rundir="${rootdir}/run_dirs"
imagedir="${rundir}/image_files"

eventdateDF=$(date -u +%Y%m%d)

host="$(hostname)"

#-----------------------------------------------------------------------

function usage {
    echo " "
    echo "    USAGE: $0 [options] DATETIME"
    echo " "
    echo "    PURPOSE: Plot data assimilation diagnostics."
    echo " "
    echo "    DATETIME - Case date and time in YYYYmmdd."
    echo "               YYYYmmdd:     run the plot for this event date."
    echo " "
    echo "    OPTIONS:"
    echo "              -h                  Display this message"
    echo "              -n                  Show command to be run and generate job scripts only"
    echo "              -v                  Verbose mode"
    echo "              -d dacycles         DA cycles subdirectory name"
    echo "              -m machine          Default: wof-epyc"
    echo "              -obs value          Plot observation value or variance. Default: none"
    echo "                                  This option can repeat multiple times for plot several variables"
    echo "              -s starttime        in HHMM. Default: 1500"
    echo "              -e endtime          in HHMM. Default: 0300"
    echo " "
    echo "   DEFAULTS:"
    echo "              eventdt    = $eventdateDF"
    echo "              rootdir    = $rootdir"
    echo "              run_dir    = $rundir"
    echo "              script_dir = $script_dir"
    echo " "
    echo "                                     -- By Y. Wang (2024.04.17)"
    echo " "
    exit $1
}

#-----------------------------------------------------------------------
#
# Handle command line arguments (override default settings)
#
#-----------------------------------------------------------------------
#% ARGS
show=""
verb=false

eventdate=${eventdateDF}
starttime="1500"
endtime="0300"
dadir="dacycles"
machine="wof-epyc"
obsvalues=()

declare -rA obstypes=(["value"]="1" ["variance"]="78")

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
        -d)
            dadir="$2"
            shift
            ;;
        -m)
            machine="$2"
            shift
            ;;
        -obs)
            if [[ "${2,,}" == "value" || "${2,,}" == "variance" ]]; then
                obsvalues+=("${2,,}")
            else
                echo "ERROR: unknown obsvalue: $2."
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

if [[ ! -d ${rundir}/${eventdate}/${dadir} ]]; then
    echo "ERROR: DA cycles directory: ${rundir}/${eventdate}/${dadir} not exist."
    exit 1
fi

if [[ ! "$host" =~ ^${machine}.*$ ]]; then
    echo "ERROR: Please run $0 on ${machine} only".
    exit 1
fi

if [[ -z ${MAMBA_EXE} || -t 0 ]]; then   # not set micromamba
    if [[ "$host" =~ ^vecna.*$ ]]; then
        micromamba_dir='/home/yunheng.wang/tools/micromamba'
        myenv="wofs_an"
    else
        micromamba_dir='/home/yunheng.wang/y'
        myenv="/home/brian.matilla/micromamba/envs/wofs-func"
    fi

    # >>> mamba initialize >>>
    # !! Contents within this block are managed by 'mamba init' !!
    export MAMBA_EXE="${micromamba_dir}/bin/micromamba"
    export MAMBA_ROOT_PREFIX="${micromamba_dir}"
    #__mamba_setup="$("$MAMBA_EXE" shell hook --shell bash --root-prefix "$MAMBA_ROOT_PREFIX" 2> /dev/null)"
    #if [ $? -eq 0 ]; then
    if __mamba_setup="$("$MAMBA_EXE" shell hook --shell bash --root-prefix "$MAMBA_ROOT_PREFIX" 2> /dev/null)"; then
        eval "$__mamba_setup"
    else
        micromamba() { "$MAMBA_EXE"; }  # Fallback on help from mamba activate
    fi
    unset __mamba_setup

    # <<< mamba initialize <<<
    micromamba activate "${myenv}"

    echo "Activated Python environment \"${myenv}\" on ${machine} ..."
fi

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

#log_dir="${rundir}/${eventdate}"
#
#if [[ ! -d ${log_dir} ]]; then
#    echo "ERROR: ${log_dir} not exists."
#    exit 1
#fi

if [[ ! -d ${rundir}/${eventdate}/${dadir}/obs_diag ]]; then
    mkdir -p "${rundir}/${eventdate}/${dadir}/obs_diag"
fi
cd "${rundir}/${eventdate}/${dadir}/obs_diag" || exit

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

grid_file="${rundir}/${eventdate}/wofs_mpas/wofs_mpas.grid.nc"

for ((s=start_s;s<=end_s;s+=900)); do
    timestr=$(date -u -d @$s +%H%M)
    datestr=$(date -u -d @$s +%Y%m%d%H%M)

    seq_file="${rundir}/${eventdate}/${dadir}/${timestr}/obs_seq.final.${datestr}.nc"
    donefile="${rundir}/${eventdate}/${dadir}/${timestr}/done.filter"

    if [[ ! -f ${donefile} ]]; then
        echo "Waiting for ${donefile} ...."
        while [[ ! -e ${donefile} ]]; do
            sleep 10
        done
    fi

    if [[ ! -e "done.${timestr}" ]]; then

        for ovalue in "${obsvalues[@]}"; do
            echo -e "\nPlotting ${ovalue} at ${timestr} ..."
            xtype="${obstypes[$ovalue]},0"
            ${show} ${rootdir}/python/plot_dartobs.py -p ${xtype}  -g ${grid_file} -r 300 -latlon "${seq_file}" 2>/dev/null
            if [[ $? -eq 0 ]]; then
                ${show} touch "done.${timestr}"
            fi
        done

    else
        echo "done.${timestr} exist. Skipped."
    fi
done

if [[ ! -e done.zigzag ]]; then
    ${show} ${rootdir}/python/plot_dartzig.py ${eventdate} -d ${rundir}/${eventdate}/${dadir} -r 300 2>/dev/null

    cd ${rundir}/${eventdate}/${dadir}/obs_diag || exit 1

    image_destdir="${imagedir}/20240410_mpasV8.0/1500"
    if [[ ! -d ${image_destdir} ]]; then
        mkdir -p ${image_destdir}
    fi

    for fn in rms_*.png ratio_*.png number_*.png; do
        destfn="${fn%_*}_f360.png"
        convert $fn -resize 1100x1100 -trim ${image_destdir}/${destfn}
    done

    if [[ $? -eq 0 ]]; then
        ${show} touch "done.zigzag"
    fi
fi

exit 0
