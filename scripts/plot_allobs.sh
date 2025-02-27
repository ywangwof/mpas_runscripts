#!/bin/bash
script_dir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
rootdir=$(realpath "$(dirname "${script_dir}")")

up_dir=$(dirname $rootdir)
mpasdir="/scratch/yunheng.wang/MPAS/MPAS_PROJECT"

rundir="${mpasdir}/run_dirs"

eventdateDF=$(date -u +%Y%m%d)

host="$(hostname)"

NC='\033[0m'            # No Color
BLACK='\033[0;30m';     DARK='\033[1;30m'
RED='\033[0;31m';       LIGHT_RED='\033[1;31m'
GREEN='\033[0;32m';     LIGHT_GREEN='\033[1;32m'
BROWN='\033[0;33m';     YELLOW='\033[1;33m'
BLUE='\033[0;34m';      LIGHT_BLUE='\033[1;34m'
PURPLE='\033[0;35m';    LIGHT_PURPLE='\033[1;35m'
CYAN='\033[0;36m';      LIGHT_CYAN='\033[1;36m'
LIGHT='\033[0;37m';     WHITE='\033[1;37m'

DIR_CLR='\033[0;97;44m'; DIRa_CLR='\033[0;95;44m';

#-----------------------------------------------------------------------

function usage {
    echo " "
    echo "    USAGE: $0 [options] DATETIME [WORKDIR]"
    echo " "
    echo "    PURPOSE: Plot data assimilation diagnostics."
    echo " "
    echo "    DATETIME - Case date and time in YYYYmmdd."
    echo "               YYYYmmdd:     run the plot for this event date."
    echo " "
    echo -e "    WORKDIR  - Top level ${LIGHT_BLUE}run_dir${NC} for all tasks"
    echo -e "               Normally, it will contain ${DIR_CLR}YYYYmmdd/dacycles${DIRa_CLR}{x}${NC} & ${DIR_CLR}image_files${NC}."
    echo " "
    echo "    OPTIONS:"
    echo "              -h                  Display this message"
    echo "              -n                  Show command to be run and generate job scripts only"
    echo "              -v                  Verbose mode"
    echo "              -x affix            DA cycles subdirectory name affix, default: empty for \"dacycles\""
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
affix=""
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
        -x)
            affix="$2"
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
            elif [[ -d $key ]]; then
                rundir=$key
            else
                echo ""
                echo "ERROR: unknown argument, get [$key]."
                usage 3
            fi
            ;;
    esac
    shift # past argument or value
done

dadir="dacycles${affix}"

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
    ${show} ${rootdir}/python/plot_dartzig.py ${eventdate} -e ${endtime} -d ${rundir}/${eventdate}/${dadir} -r 300 2>/dev/null

    imagedir="${rundir}/image_files"

    if [[ -z ${show} ]]; then
        cd ${rundir}/${eventdate}/${dadir}/obs_diag || exit 1

        image_destdir="${imagedir}/${eventdate}${affix}/1500"
        if [[ ! -d ${image_destdir} ]]; then
            mkdir -p ${image_destdir}
        fi

        if [[ $verb -eq 1 ]]; then
            echo "Convert to 1100x1100 and Trim for the web visualization."
        fi

        estatus=0
        for fn in rms_*.png ratio_*.png number_*.png; do
            destfn="${fn%_*}_f360.png"
            convert $fn -resize 1100x1100 -trim ${image_destdir}/${destfn}
            (( estatus+=$? ))
        done

        if [[ ${estatus} -eq 0 ]]; then
            cp ${up_dir}/frdd-wofs-post/json/wofs_run_metadata_obsdiag.json ${image_destdir}/wofs_run_metadata.json
            ${show} touch "done.zigzag"
        fi
    fi
else
    echo "Found $(pwd)/done.zigzag. Skipping ...."
fi

exit 0
