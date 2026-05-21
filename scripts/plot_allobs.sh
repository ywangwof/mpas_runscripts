#!/bin/bash
# shellcheck disable=SC2034

script_dir="$( cd "$( dirname "$0" )" && pwd )"                         # dir of script
rootdir=$(realpath "$(dirname "${script_dir}")")

eventdateDF=$(date -u +%Y%m%d)

host="$(hostname)"

outdir1="obs_diag"
outdir2="1500"

#-----------------------------------------------------------------------

source "${script_dir}/Common_Colors.sh"
source "${script_dir}/Site_Runtime.sh" || exit $?

########################################################################

function usage {
    echo    " "
    echo    "    USAGE: $0 [options] DATETIME [WORKDIR]"
    echo    " "
    echo    "    PURPOSE: Plot data assimilation diagnostics."
    echo    " "
    echo    "    DATETIME - Case date and time in YYYYmmdd."
    echo    "               YYYYmmdd:     run the plot for this event date."
    echo    " "
    echo -e "    WORKDIR  - Top level ${LIGHT_BLUE}run_dir${NC} for all tasks"
    echo -e "               Normally, it will contain ${DIR_CLR}YYYYmmdd/dacycles${DIRa_CLR}{x}${NC} & ${DIR_CLR}image_files${NC}."
    echo    " "
    echo    "    OPTIONS:"
    echo    "              -h                  Display this message"
    echo    "              -n                  Show command to be run and generate job scripts only"
    echo    "              -v                  Verbose mode"
    echo    "              -f conf_file        Configuration file for this case. Default: \${WORKDIR}/config.\${eventdate}"
    echo    "              -m machine          Default: wof-epyc"
    echo    "              -obs value          Plot observation value or variance. Default: none"
    echo    "                                  This option can repeat multiple times for plot several variables"
    echo    "              -s starttime        as HHMM or YYYYmmddHHMM. Default: 1500"
    echo    "              -e endtime          as HHMM or YYYYmmddHHMM. Default: 0300"
    echo    " "
    echo    "   DEFAULTS:"
    echo    "              eventdate  = $eventdateDF"
    echo    "              WORKDIR    = \$site_workdir/run_dirs"
    echo    "              rootdir    = $rootdir"
    echo    "              script_dir = $script_dir"
    echo    " "
    echo    "                                     -- By Y. Wang (2024.04.17)"
    echo    " "
    exit    "$1"
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
                if [[ $2 =~ ^[0-9]{4}$ || $2 =~ ^[0-9]{12}$ ]]; then
                    args["starttime"]="${2}"
                else
                    echo "ERROR: Start time should be in HHMM, got \"$2\"."
                    usage 1
                fi
                shift
                ;;
            -e )
                if [[ $2 =~ ^[0-9]{4}$ || $2 =~ ^[0-9]{12}$ ]]; then
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

[[ -v args["machine"] ]]  && machine=${args["machine"]}   || machine="Ursa"
#if [[ ! "$host" =~ ^${machine}.*$ ]]; then
#    echo " "
#    echo -e "${RED}ERROR${NC}: Please run $0 on ${machine} only".
#    echo " "
#    exit 1
#fi

setup_machine "${machine}" "$rootdir" true false false

[[ -v args["eventdate"] ]]   && eventdate=${args["eventdate"]}     || eventdate=${eventdateDF}
[[ -v args["run_dir"] ]]     && run_dir=${args["run_dir"]}         || run_dir="${site_workdir}"
[[ -v args["starttime"] ]]   && starttime=${args["starttime"]}     || starttime="1500"
[[ -v args["endtime"] ]]     && endtime=${args["endtime"]}         || endtime="0300"

[[ -v args["obsvalues"] ]]   && read -r -a obsvalues <<< "${args['obsvalues']}" || obsvalues=('refl')

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

########################################################################

declare -rA obstypes=(["value"]="1" ["variance"]="78")

#-----------------------------------------------------------------------
# Set Event End Date and Time
#-----------------------------------------------------------------------

startday=""
if [[ ${#starttime} -eq 12 ]]; then
    startdatetime=${starttime}
else
    (( 10#$starttime < 1500 )) && startday="1 day"
    startdatetime="${eventdate}${starttime}"
fi

endday=""
if [[ ${#endtime} -eq 12 ]]; then
    enddatetime=${endtime}
else
    (( 10#$endtime < 1500 )) && endday="1 day"
    enddatetime="${eventdate}${endtime}"
fi

start_s=$(date -u -d "${startdatetime:0:8} ${startdatetime:8:4} $startday" +%s)
end_s=$(date   -u -d "${enddatetime:0:8}   ${enddatetime:8:4}   $endday"   +%s)

startdatetime=$(date -u -d @$start_s +%Y%m%d%H%M)
enddatetime=$(date   -u -d @$end_s +%Y%m%d%H%M)

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

grid_file="${run_dir}/${eventdate}/wofs_mpas/wofs_mpas.grid.nc"

for ((s=start_s;s<=end_s;s+=900)); do
    timestr=$(date -u -d @$s +%H%M)
    datestr=$(date -u -d @$s +%Y%m%d)

    donefile="${run_dir}/${eventdate}/${dadir}/${timestr}/jedi_solver/done.solver"

    if [[ ! -f ${donefile} ]]; then
        echo "Waiting for ${donefile} ...."
        while [[ ! -e ${donefile} ]]; do
            sleep 10
        done
    fi

    ioda_file="${run_dir}/${eventdate}/${dadir}/${timestr}/ioda_mrms_refl/ioda_mrms_${datestr}_${timestr}.nc4"

    if [[ ! -e "done.${timestr}" ]]; then

        for ovalue in "${obsvalues[@]}"; do
            echo -e "\nPlotting ${ovalue} at ${timestr} ..."
            ${show} "${rootdir}/python/plot_ioda.py" -g "${grid_file}" -r 300 -m latlon "${ioda_file}" 2>/dev/null
            # shellcheck disable=SC2181
            if [[ $? -eq 0 ]]; then
                ${show} touch "done.${timestr}"
            fi
        done

    else
        echo "done.${timestr} exist. Skipped."
    fi
done

# Locate the block that previously ran plot_dartzig.py
if [[ ! -e done.zigzag ]]; then
    echo -e "${CYAN}Generating JEDI Sawtooth plots...${NC}"

    # Call the improved script with shell variables
    # The affix variable is derived automatically earlier in your shell script
    # "adpupa_t120" "adpupa_q120" "adpupa_uv220"
    cmds=("${rootdir}/python/plot_sawtooth_jedi.py"
        "${eventdate}"
        -s "${startdatetime}"
        -e "${enddatetime}"
        -d "${run_dir}"
        -o "radar_rw, mrms_refl,cwp,cwp_night,adpsfc_ps187,adpsfc_q181,adpsfc_q183,adpsfc_q187,adpsfc_t187,adpsfc_uv287"
        -m 36
        -c 15
        --type "all" --cr -n)

    [[ -n ${affix} ]] && cmds+=(-x "${affix}")
    [[ ${verb} == true ]] && cmds+=(-v)

    ${show} "${cmds[@]}"

    if [[ $machine == Ursa ]]; then
        module load imagemagick
    fi
    imagedir="${run_dir}/image_files"

    if [[ -z ${show} ]]; then
        cd "${run_dir}/${eventdate}/${dadir}/${outdir1}" || exit 1
        image_destdir="${imagedir}/${eventdate}${affix}/${outdir2}"
        [[ ! -d ${image_destdir} ]] && mkdir -p "${image_destdir}"

        # Standard post-processing (resize/trim)
        if [[ $verb == true ]]; then
            echo "Convert to 1100x1100 and Trim for the web visualization."
        fi

        estatus=0
        for fn in sawtooth_${eventdate}_*.png; do
            destfn="${fn}_f360.png"
            convert "$fn" -resize 1100x1100 -trim "${image_destdir}/${destfn}"
            (( estatus+=$? ))
        done

        post_dir="${site_postdir}"

        if [[ ${estatus} -eq 0 ]]; then
            "${script_dir}/process_da_json.py" "${post_dir}/json/wofs_run_metadata_obsdiag.json" \
                                            "${image_destdir}/wofs_run_metadata.json"
            touch "done.zigzag"
        fi
    fi
else
    echo "Found $(pwd)/done.zigzag. Skipping sawtooth generation."
fi

exit 0
