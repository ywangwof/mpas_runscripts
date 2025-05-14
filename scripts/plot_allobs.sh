#!/bin/bash
# shellcheck disable=SC2034

script_dir="$( cd "$( dirname "$0" )" && pwd )"                         # dir of script
rootdir=$(realpath "$(dirname "${script_dir}")")

MPASdir=$(dirname $(dirname "$rootdir"))                                # no compiler specific stuffs

mpasworkdir="/scratch/wofs_mpas"

eventdateDF=$(date -u +%Y%m%d)

host="$(hostname)"

outdir1="obs_diag.new"
outdir2="1600"

#-----------------------------------------------------------------------

source "$script_dir/Common_Colors.sh"

########################################################################

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
    echo "              -f conf_file        Configuration file for this case. Default: \${WORKDIR}/config.\${eventdate}"
    echo "              -m machine          Default: wof-epyc"
    echo "              -obs value          Plot observation value or variance. Default: none"
    echo "                                  This option can repeat multiple times for plot several variables"
    echo "              -s starttime        in HHMM. Default: 1500"
    echo "              -e endtime          in HHMM. Default: 0300"
    echo " "
    echo "   DEFAULTS:"
    echo "              eventdate  = $eventdateDF"
    echo "              WORKDIR    = $mpasworkdir/run_dirs"
    echo "              rootdir    = $rootdir"
    echo "              script_dir = $script_dir"
    echo " "
    echo "                                     -- By Y. Wang (2024.04.17)"
    echo " "
    exit "$1"
}

########################################################################
#
# Handle command line arguments
#
########################################################################

function parse_args {

    declare -gA args

    while [[ $# -gt 0 ]]; do
        key="$1"

        case $key in
            -h)
                usage 0
                ;;
            -n)
                args["show"]="echo"
                ;;
            -v)
                args["verb"]=true
                ;;
            -f)
                args["config_file"]="$2"
                shift
                ;;
            -m)
                args["machine"]="$2"
                shift
                ;;
            -obs)
                if [[ "${2,,}" =~ ^(value|variance)$  ]]; then
                    args["obsvalues"]+=" ${2,,}"
                else
                    echo "ERROR: unknown obsvalue: $2."
                    usage 1
                fi
                shift
                ;;
            -s )
                if [[ $2 =~ ^[0-9]{4}$ ]]; then
                    args["starttime"]="${2}"
                else
                    echo "ERROR: Start time should be in HHMM, got \"$2\"."
                    usage 1
                fi
                shift
                ;;
            -e )
                if [[ $2 =~ ^[0-9]{4}$ ]]; then
                    args["endtime"]=$2
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
                    args["eventdate"]=${key}
                elif [[ -d $key ]]; then
                    args["run_dir"]=$key
                elif [[ -f $key ]]; then
                    args["config_file"]="${key}"
                else
                    echo ""
                    echo "ERROR: unknown argument, get [$key]."
                    usage 3
                fi
                ;;
        esac
        shift # past argument or value
    done
}

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#
#@ MAIN entry
#
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#% ARGS

parse_args "$@"

[[ -v args["verb"] ]]     && verb=${args["verb"]}         || verb=false
[[ -v args["show"] ]]     && show=${args["show"]}         || show=""

[[ -v args["eventdate"] ]]   && eventdate=${args["eventdate"]}     || eventdate=${eventdateDF}
[[ -v args["run_dir"] ]]     && run_dir=${args["run_dir"]}         || run_dir="${mpasworkdir}/run_dirs"
[[ -v args["machine"] ]]     && machine=${args["machine"]}         || machine="wof-epyc"
[[ -v args["starttime"] ]]   && starttime=${args["starttime"]}     || starttime="1500"
[[ -v args["endtime"] ]]     && endtime=${args["endtime"]}         || endtime="0300"

[[ -v args["obsvalues"] ]]   && read -r -a obsvalues <<< "${args['obsvalues']}" || obsvalues=()

if [[ -v args["config_file"] ]]; then
    config_file=${args["config_file"]}

    if [[ "$config_file" =~ "/" ]]; then
        run_dir=$(realpath "$(dirname "${config_file}")")
    else
        config_file="${run_dir}/${config_file}"
    fi

    if [[ ${config_file} =~ config\.([0-9]{8})(.*) ]]; then
        [[ -v args["eventdate"] ]] || eventdate="${BASH_REMATCH[1]}"
        affix="${BASH_REMATCH[2]}"
    elif [[ ${config_file} =~ config\.(.*)$ ]]; then
        affix="_${BASH_REMATCH[1]}"
    else
        echo -e "${RED}ERROR${NC}: Config file ${CYAN}${config_file}${NC} not the right format config.YYYYmmdd[_*]."
        exit 1
    fi
else
    config_file="${run_dir}/config.${eventdate}"
    affix=""
fi

if [[ ! -f ${config_file} ]]; then
    echo " "
    echo -e "${RED}ERROR${NC}: Config file ${CYAN}${config_file}${NC} not exist."
    usage 1
fi

dadir="dacycles${affix}"

if [[ ! -d ${run_dir}/${eventdate}/${dadir} ]]; then
    echo " "
    echo -e "${RED}ERROR${NC}: DA cycles directory: ${CYAN}${run_dir}/${eventdate}/${dadir}${NC} not exist."
    echo " "
    exit 1
fi

if [[ ! "$host" =~ ^${machine}.*$ ]]; then
    echo " "
    echo -e "${RED}ERROR${NC}: Please run $0 on ${machine} only".
    echo " "
    exit 1
fi

########################################################################
# Load Python environment

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

declare -rA obstypes=(["value"]="1" ["variance"]="78")

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#% ENTRY

#log_dir="${run_dir}/${eventdate}"
#
#if [[ ! -d ${log_dir} ]]; then
#    echo "ERROR: ${log_dir} not exists."
#    exit 1
#fi

if [[ ! -d ${run_dir}/${eventdate}/${dadir}/${outdir1} ]]; then
    mkdir -p "${run_dir}/${eventdate}/${dadir}/${outdir1}"
fi
cd "${run_dir}/${eventdate}/${dadir}/${outdir1}" || exit

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

grid_file="${run_dir}/${eventdate}/wofs_mpas/wofs_mpas.grid.nc"

for ((s=start_s;s<=end_s;s+=900)); do
    timestr=$(date -u -d @$s +%H%M)
    datestr=$(date -u -d @$s +%Y%m%d%H%M)

    seq_file="${run_dir}/${eventdate}/${dadir}/${timestr}/obs_seq.final.${datestr}.nc"
    donefile="${run_dir}/${eventdate}/${dadir}/${timestr}/done.filter"

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
            ${show} "${rootdir}/python/plot_dartobs.py" -p "${xtype}"  -g "${grid_file}" -r 300 -latlon "${seq_file}" 2>/dev/null
            # shellcheck disable=SC2181
            if [[ $? -eq 0 ]]; then
                ${show} touch "done.${timestr}"
            fi
        done

    else
        echo "done.${timestr} exist. Skipped."
    fi
done

if [[ ! -e done.zigzag ]]; then
    ${show} "${rootdir}/python/plot_dartzig.py" "${eventdate}" -e "${endtime}" -d "${run_dir}/${eventdate}/${dadir}" -r 300 -u -v 2>/dev/null

    imagedir="${run_dir}/image_files"

    if [[ -z ${show} ]]; then
        cd "${run_dir}/${eventdate}/${dadir}/${outdir1}" || exit 1

        image_destdir="${imagedir}/${eventdate}${affix}/${outdir2}"
        if [[ ! -d ${image_destdir} ]]; then
            mkdir -p "${image_destdir}"
        fi

        if [[ $verb -eq 1 ]]; then
            echo "Convert to 1100x1100 and Trim for the web visualization."
        fi

        estatus=0
        for fn in rms_*.png ratio_*.png number_*.png; do
            destfn="${fn%_*}_f360.png"
            convert "$fn" -resize 1100x1100 -trim "${image_destdir}/${destfn}"
            (( estatus+=$? ))
        done

        if [[ ${estatus} -eq 0 ]]; then
            #cp "${MPASdir}/frdd-wofs-post/json/wofs_run_metadata_obsdiag.json" "${image_destdir}/wofs_run_metadata.json"
            "${script_dir}/process_da_json.py" "${MPASdir}/frdd-wofs-post/json/wofs_run_metadata_obsdiag.json" \
                                            "${image_destdir}/wofs_run_metadata.json"
            ${show} touch "done.zigzag"
        fi
    fi
else
    echo "Found $(pwd)/done.zigzag. Skipping ...."
fi

exit 0
