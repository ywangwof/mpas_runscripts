#!/bin/bash

script_dir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
rootdir=$(realpath "$(dirname "${script_dir}")")
#rootdir="/scratch/ywang/MPAS/gnu/mpas_scripts"

run_dir="${rootdir}/run_dirs"

eventdateDF=$(date -u +%Y%m%d)

host="$(hostname)"

#-----------------------------------------------------------------------

function usage {
    echo " "
    echo "    USAGE: $0 [options] DATETIME FILETYPE VARNAMEs"
    echo " "
    echo "    PURPOSE: Plot MPAS forecast to make an animated APNG file."
    echo " "
    echo "    DATETIME - Case date and time in YYYYmmdd."
    echo "               YYYYmmdd:     run the plot for this event date."
    echo "    FILETYPE - \"diag\" or \"history\"."
    echo "    VARNAMES - Variable name string. For example: \"uReconstructMeridional\""
    echo " "
    echo "    OPTIONS:"
    echo "              -h                  Display this message"
    echo "              -n                  Show command to be run and generate job scripts only"
    echo "              -v                  Verbose mode"
    echo "              -x affix            FCST subdirectory name affix, default: empty for \"fcst\""
    echo "              -d domname          Domain name for the run, default: wofs_mpas"
    echo "              -s starttimes       in HHMM. Default: 1700"
    echo "              -m members          Ensemble member string, for example, 01; 01,12; etc."
    echo "              -l levels           Vertical levels"
    echo "              -c cntLevels        Contour levels, [cmin,cmax,cinc]"
    echo " "
    echo "   DEFAULTS:"
    echo "              eventdt    = $eventdateDF"
    echo "              rootdir    = $rootdir"
    echo "              run_dir    = $run_dir"
    echo "              script_dir = $script_dir"
    echo " "
    echo "                                     -- By Y. Wang (2024.08.05)"
    echo " "
    exit "$1"
}

########################################################################

function join_by {
    local IFS="$1"
    echo "${*:2}"
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
runtimes=("1700")
affix=""
domname="wofs_mpas"
machine="wof-epyc"

filetype="history"
memstrs=("01")
varnames=("uReconstructMeridional")
levels=(0)

cntopts=()

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
        -d)
            domname="$2"
            shift
            ;;
        -m)
            IFS="," read -r -a memstrs <<< "$2"
            shift
            ;;
        -s )
            if [[ $2 =~ ^([0-9]{4},?)+$ ]]; then
                #runtime="${2}"
                IFS="," read -r -a runtimes <<< "$2"
            else
                echo "ERROR: Start time should be in HHMM, got \"$2\"."
                usage 1
            fi
            shift
            ;;
        -l )
            IFS="," read -r -a levels <<< "$2"
            shift
            ;;
        -c )
            cntopts=("-c" "\"$2\"")
            shift
            ;;
        -*)
            echo "Unknown option: $key"
            usage 2
            ;;
        diag | history )
            filetype="$key"
            ;;
        *)
            if [[ $key =~ ^[0-9]{8}$ ]]; then
                eventdate=${key}
            else
                IFS="," read -r -a varnames <<< "$key"
                #varname="$key"
                # echo ""
                # echo "ERROR: unknown argument, get [$key]."
                # usage 3
            fi
            ;;
    esac
    shift # past argument or value
done

runname="fcst"
if [[ -n ${affix} ]]; then
    runname="${runname}${affix}"
fi

if [[ ! -d ${run_dir}/${eventdate}/${runname} ]]; then
    echo "ERROR: FCST directory: ${run_dir}/${eventdate}/${runname} not exist."
    exit 1
fi

if [[ ! "${host}" =~ ^${machine}.*$ ]]; then
    echo "ERROR: Please run $0 on ${machine} only".
    exit 1
fi

########################################################################

# First, initialize Python environment

if [[ -z ${MAMBA_EXE} || -t 0 ]]; then   # not set micromamba
    if [[ "$host" =~ ^vecna.*$ ]]; then
        micromamba_dir='/home/yunheng.wang/tools/micromamba'
        myenv="wofs_an"
    else
        micromamba_dir='/home/yunheng.wang/y'
        #myenv="/home/brian.matilla/micromamba/envs/wofs-func"
        myenv="myenv"
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

wrk_dir="$(pwd)"

# 1. Get patches pickle file

patch_file="${run_dir}/${eventdate}/${domname}.135048.patches"

#rm -rf "${patch_file}"
if [[ ! -e ${patch_file} ]]; then
    init_file="${run_dir}/${eventdate}/init/${domname}.invariant.nc"
    cd "${run_dir}/${eventdate}" || exit 0
    echo "Creating ${patch_file} in ${run_dir}/${eventdate} ...."
    my_command=("${rootdir}/python/get_mpaspatches.py" "${init_file}")
    ${show} "${my_command[@]}"
    #mapfile -t my_array < <( "${my_command[@]}" )
    #out1="${my_array[-1]}"
    #maprange=${out1##Domain range:}
    #echo "Get domain range: ${maprange}"
fi

levelstr=$(join_by ',' "${levels[@]}")
cmdarray=("${rootdir}/python/plot_mpaspatch.py" "-p" "${patch_file}" -l "${levelstr}" )
cmdarray+=("${cntopts[@]}")

for runtime in "${runtimes[@]}"; do
    for memstr in "${memstrs[@]}"; do

        wrkdir="${wrk_dir}/${eventdate}/${runname}/${runtime}/fcst_${memstr}"
        if [[ ! -d "${wrkdir}" ]]; then
            echo "Creating ${wrkdir} ...."
            mkdir -p "${wrkdir}"
        fi

        # 2. Plot the variable

        cd "${wrkdir}" || exit 0

        fcst_dir="${run_dir}/${eventdate}/${runname}/${runtime}/fcst_${memstr}"

        begin_sec=$(date -d "${eventdate} ${runtime}"         +%s)
        end_sec=$(date   -d "${eventdate} ${runtime} 6 hours" +%s)

        echo "Current Working Directory: ${wrkdir}"
        for ((i=begin_sec;i<=end_sec;i+=300)); do
            time_str=$(date -d @$i +%Y-%m-%d_%H.%M.%S)
            fcst_file="${fcst_dir}/${domname}_${memstr}.${filetype}.${time_str}.nc"

            for varname in "${varnames[@]}"; do
                my_cmdarray=("${cmdarray[@]}")
                my_cmdarray+=("${fcst_file}")
                my_cmdarray+=("${varname}")
                echo -e "\nPlotting \"${varname}\" from ${fcst_file} ...."
                ${show} "${my_cmdarray[@]}"
            done
        done

        # 3. Make APNG using magick

        if which magick >& /dev/null; then
            time_str="${eventdate}${runtime}"
            for varname in "${varnames[@]}"; do
                for lvl in "${levels[@]}"; do
                    lvlstr=$(printf "%02d" $lvl)
                    echo -e "\nMaking APNG for var = $varname, level = $lvl ...."
                    #magick -delay 50 -loop 0 "${wrkdir}/${varname}."*"_K${lvl}".png APNG:"${wrkdir}/${varname}_${time_str}_K${lvl}.png"
                    #ffmpeg -i "${wrkdir}/${varname}_${time_str}_K${lvl}.png" -movflags faststart -pix_fmt yuv420p -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" "${wrkdir}/${varname}_${time_str}_K${lvl}.mp4"
                    ${show} convert -delay 60 "${wrkdir}/${varname}."*"_K${lvlstr}".png "${wrkdir}/${varname}_${time_str}_K${lvlstr}.mp4"
                done
            done
        else
            echo "ERROR: magick not in the PATH"
        fi

    done
done

# Convert to MP4
#
# movflags – This option optimizes the structure of the MP4 file so the
#            browser can load it as quickly as possible.
#
# pix_fmt – MP4 videos store pixels in different formats. We include this
#           option to specify a specific format which has maximum
#           compatibility across all browsers.
#
# vf –      MP4 videos using H.264 need to have a dimensions that are
#           divisible by 2. This option ensures that’s the case.
#
#ffmpeg -i animated.gif -movflags faststart -pix_fmt yuv420p -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" video.mp4

exit 0
