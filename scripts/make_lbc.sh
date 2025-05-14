#!/bin/bash
# shellcheck disable=SC2317,SC1090,SC1091,SC2086,SC2154

#rootdir="/scratch/ywang/MPAS/mpas_runscripts"
scpdir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
rootdir=$(realpath "$(dirname "${scpdir}")")

mpasworkdir="/scratch/wofs_mpas"     # platform dependent, it is set in Site_Runtime.sh

eventdateDF=$(date -u +%Y%m%d)

#-----------------------------------------------------------------------
#
# This is the 3rd step of th WOFS-MPAS workflow. It run program ungrib.exe
# & init_atmosphere_model to generate lateral boundary files for all ensemble members.
#
# Required files from ROOTDIR
#
# 0. module files in modules
#     build_jet_Rocky8_intel_smiol
#     env.mpas_smiol
#
# 1. exec                                   # The executables
#     init_atmosphere_model
#     ungrib.exe
#     gpmetis
#
# 2. templates                              # templates used in this scripts
#    README
#
#    2.1 SLURM scripts on Jet
#        run_lbc_array.slurm                or run_lbc.pbs
#        run_ungrib_array.slurm
#
# 3. fix_files                              # runtime fix files for MPAS model and accompany programs
#
#    3.1 WPS run-time files for program ungrib
#        WRFV4.0/Vtable.HRRRE.2018
#
# 4. scripts                                # this scripts
#    4.1 make_lbc.sh
#
# INSTRUCTIONS:
#
#  Use existing domain (wofs_mpas)
#
#     0. It should be run after "make_ics.sh"
#     1. make_lbc.sh [YYYYmmddHH] [run_dirs] [jobnames]
#
#-----------------------------------------------------------------------

function usage {
    echo " "
    echo "    USAGE: $0 [options] DATETIME [WORKDIR] [JOBS]"
    echo " "
    echo "    PURPOSE: Make ensemble boundary files before the MPAS-WOFS DA cycles"
    echo " "
    echo "    DATETIME - Case date and time in YYYYMMDD, Default: today"
    echo "    WORKDIR  - Run Directory"
    echo "    JOBS     - One or more jobs from [ungrib,lbc,clean,time_intrp]"
    echo "               Default: all jobs in the proper order."
    echo " "
    echo "    OPTIONS:"
    echo "              -h                  Display this message"
    echo "              -n                  Show command to be run and generate job scripts only"
    echo "              -v                  Verbose mode"
    echo "              -k  [0,1,2]         Keep working directory if exist, 0- keep as is; 1- overwrite; 2- make a backup as xxxx.bak?"
    echo "                                  Default is 0 for ungrib, mpassit, upp and 1 for others"
    echo "              -a                  Clean the \"ungrib\" directory completely when JOBS contain \"clean\""
    echo "              -w                  Hold script to wait for all job conditions are satified and submitted (for mpassit & upp)."
    echo "                                  By default, the script will exit after submitting all possible jobs."
    echo "              -s  YYYYmmddHHMM    Start date & time for the LBC preparation"
    echo "                  HHMM            Start time"
    echo "              -e  YYYYmmddHHMM    End date & time for the LBC preparation"
    echo "                  HHMM            End time"
    echo "              -t  HHMM            Stop time for time interpolation"
    echo "              -m  Machine         Machine name to run on, [Jet, Cheyenne, Vecna]."
    echo "              -f conf_file        Configuration file for this case. Default: \${WORKDIR}/config.\${eventdate}"
    echo " "
    echo "   DEFAULTS:"
    echo "              eventdt = $eventdate"
    echo "              rootdir = $rootdir"
    echo "              WORKDIR = $mpasworkdir/run_dirs"
    echo " "
    echo "                                     -- By Y. Wang (2023.05.25)"
    echo " "
    exit $1
}

########################################################################
#
# Handle command line arguments
#
########################################################################

function parse_args {

    declare -Ag args

    #-------------------------------------------------------------------
    # Parse command line arguments
    #-------------------------------------------------------------------

    while [[ $# -gt 0 ]]; do
        key="$1"

        case $key in
            -h)
                usage 0
                ;;
            -n)
                args["dorun"]=false
                ;;
            -v)
                args["verb"]=1
                ;;
            -k)
                if [[ $2 =~ [012] ]]; then
                    args["overwrite"]=$2
                    shift
                else
                    echo -e "${RED}ERROR${NC}: option for ${BLUE}-k${NC} can only be [${YELLOW}0-2${NC}], but got ${PURPLE}$2${NC}."
                    usage 1
                fi
                ;;
            -w)
                args["jobwait"]=1
                ;;
            -a )
                args["cleanall"]=true
                ;;
            -m)
                if [[ ${2^^} == "JET" ]]; then
                    args["machine"]=Jet
                elif [[ ${2^^} == "VECNA" ]]; then
                    args["machine"]=Vecna
                elif [[ ${2^^} == "HERCULES" ]]; then
                    args["machine"]=Hercules
                elif [[ ${2^^} == "CHEYENNE" || ${2^^} == "DERECHO" ]]; then
                    args["machine"]=Cheyenne
                else
                    echo -e "${RED}ERROR${NC}: Unsupported machine name, got ${PURPLE}$2${NC}."
                    usage 1
                fi
                shift
                ;;
            -f)
                args["config_file"]="$2"
                shift
                ;;
            -s )
                if [[ $2 =~ ^[0-9]{12}$ ]]; then
                    args["eventdate"]=${2:0:8}
                    args["eventtime"]=${2:8:4}
                    eventhour=${2:8:2}
                    if ((10#$eventhour < 12)); then
                        args["eventdate"]=$(date -u -d "${2:0:8} 1 day ago" +%Y%m%d)
                    fi
                elif [[ $2 =~ ^[0-9]{4}$ ]]; then
                    args["eventtime"]="${2}"
                else
                    echo -e "${RED}ERROR${NC}: Start time should be in ${GREEN}YYYYmmddHHMM${NC} or ${GREEN}HHMM${NC}, got ${PURPLE}$2${NC}."
                    usage 1
                fi
                shift
                ;;
            -e )
                if [[ $2 =~ ^[0-9]{12}$ ]]; then
                    args["enddatetime"]=$2
                elif [[ $2 =~ ^[0-9]{4}$ ]]; then
                    args["endtime"]=$2
                else
                    echo -e "${RED}ERROR${NC}: End time should be in ${GREEN}YYYYmmddHHMM${NC} or ${GREEN}HHMM${NC}, got ${PURPLE}$2${NC}."
                    usage 1
                fi
                shift
                ;;
            -t )
                if [[ $2 =~ ^[0-9]{4}$ ]]; then
                    args["stoptime"]=$2
                else
                    echo -e "${RED}ERROR${NC}: Stop time should be in ${GREEN}HHMM${NC}, got ${PURPLE}$2${NC}."
                    usage 1
                fi
                shift
                ;;
            -*)
                echo -e "${RED}ERROR${NC}: Unknown option: ${PURPLE}$key${NC}"
                usage 2
                ;;
            ungrib* | lbc* | clean* | time_intrp )
                args["jobs"]="${key//,/ }"
                ;;
            *)
                if [[ $key =~ ^[0-9]{12}$ ]]; then
                    args["eventdate"]=${key:0:8}
                    args["eventtime"]=${key:8:4}
                    args["enddatetime"]=${key}
                    args["endtime"]=${key:8:4}
                elif [[ $key =~ ^[0-9]{8}$ ]]; then
                    args["eventdate"]=${key}
                elif [[ -d $key ]]; then
                    WORKDIR=$key
                    lastdir=$(basename $WORKDIR)
                    if [[ $lastdir =~ ^[0-9]{8}$ ]]; then
                        args["WORKDIR"]=$(dirname ${WORKDIR})
                        args["eventdate"]=${lastdir}
                    else
                        args["WORKDIR"]=$WORKDIR
                    fi
                    #echo $WORKDIR,$eventdate,$eventtime
                elif [[ -f $key ]]; then
                    args["config_file"]="${key}"
                else
                    echo  -e "${RED}ERROR${NC}: unknown argument, get ${PURPLE}$key${NC}."
                    usage 3
                fi
                ;;
        esac
        shift # past argument or value
    done
}

########################################################################

function run_ungrib {
    grib_dir=$1
    gribtime=$2

    wrkdir=$rundir/lbc/ungrib
    mkwrkdir $wrkdir 0
    cd $wrkdir || return

    if [[ -f running.ungrib || -f done.ungrib || -f queue.ungrib ]]; then
        return 0                   # skip
    fi

    jobarrays=()
    # shellcheck disable=SC2154
    for mem in $(seq 1 $nenslbc); do
        memstr=$(printf "%02d" $mem)
        starthr=$(((eventtime-gribtime)/100))

        starts=$(date -u -d "$eventdate $gribtime" +%s)
        ends=$(date   -u -d "${enddatetime:0:8} ${enddatetime:8:4}" +%s)
        endhr=$(( (ends-starts)/3600 ))

        gribstart_str=$(date -u -d "$eventdate $gribtime $starthr hours" +%Y-%m-%d_%H:%M:%S )
        gribendtm_str=$(date -u -d "$eventdate $gribtime $endhr hours"   +%Y-%m-%d_%H:%M:%S )

        mecho0 "GRIB files from ${grib_dir}:"
        gribfiles=()
        for (( h=starthr;h<=endhr;h+=$((EXTINVL/3600)) )); do
            hstr=$(printf "%02d" $h)
            gribfilename="$eventdate/${gribtime}/${hrrr_subdir}${memstr}/wrfnat_pert_hrrr_mem00${memstr}_${hstr}.grib2"
            gribfile="${grib_dir}/${gribfilename}"

            mecho0 "mem $memstr GRIB file $hstr: ${gribfilename}"
            while [[ ! -f $gribfile ]]; do
                if [[ $verb -eq 1 ]]; then
                    mecho0 "Waiting for ${gribfilename} ..."
                fi
                sleep 10
            done

            gribfiles+=("$gribfile")
        done

        mywrkdir="$wrkdir/ungrib_$memstr"
        mkwrkdir $mywrkdir 1
        cd $mywrkdir || return

        link_grib "${gribfiles[@]}"
        # shellcheck disable=SC2154
        ln -sf $FIXDIR/WRFV4.0/${hrrrvtable} Vtable

        cat << EOF > namelist.wps
&share
  wrf_core = 'ARW',
  max_dom = 1,
  start_date = '${gribstart_str}',
  end_date = '${gribendtm_str}',
  interval_seconds = ${EXTINVL}
  io_form_geogrid = 2,
/
&geogrid
/
&ungrib
  out_format = 'WPS',
  prefix = '${EXTHEAD}${memstr}',
/
&metgrid
/
EOF
        jobarrays+=("$mem")
    done

    #
    # Create job script and submit it
    #
    cd $wrkdir || return

    if [[ ${#jobarrays[@]} -gt 0 ]]; then
        jobscript="run_ungrib.pbs"
        # shellcheck disable=SC2154
        jobarraystr=$(get_jobarray_str "${mach}" "${jobarrays[@]}")

        declare -A jobParms=(
            [PARTION]="${partition_lbc}"
            [JOBNAME]="ungrb_${jobname}"
            [CPUSPEC]="${claim_cpu_ungrib}"
            [PREFIX]="${EXTHEAD}"
        )
        # shellcheck disable=SC2154
        submit_a_job "$wrkdir" "ungrib" "jobParms" "$TEMPDIR/run_ungrib_array.${mach}" "$jobscript" "${jobarraystr}"
    fi

    if [[ $dorun == true && $jobwait -eq 1 ]]; then
        #jobname=$1 mywrkdir=$2 donenum=$3 myjobscript=$4 numtries=${5-1}
        check_job_status "ungrib" $wrkdir $nenslbc $jobscript 2
    fi
}

########################################################################

function run_lbc {

    conditions=()
    while [[ $# -gt 0 ]]; do
        case $1 in
        /*)
            conditions+=("$1")
            ;;
        *)
            conditions+=("$rundir/$1")
            ;;
        esac
        shift
    done

    if [[ $dorun == true ]]; then
        for cond in "${conditions[@]}"; do
            mecho0 "Checking: ${CYAN}$cond${NC} ...."
            while [[ ! -e $cond ]]; do
                if [[ $verb -eq 1 ]]; then
                    mecho0 "Waiting for file: ${CYAN}$cond${NC}"
                fi

                # shellcheck disable=SC2154
                check_job_status "${domname}" $rundir/init $nensics
                check_job_status "ungrib" $rundir/lbc/ungrib $nenslbc
                sleep 10
            done
        done
        cd $rundir/init || return
        ln -sf ${domname}_01.init.nc ${domname}.invariant.nc
    fi

    wrkdir=$rundir/lbc

    if [[ -f $wrkdir/done.${domname} ]]; then
        return 0
    fi

    if [[ -f $wrkdir/running.${domname} || -f $wrkdir/queue.${domname} ]]; then
        #jobname=$1 mywrkdir=$2 donenum=$3 myjobscript=$4 numtries=${5-3}
        check_job_status "${domname}" "$wrkdir" "$nenslbc"
        return 0
    fi

    mkwrkdir $wrkdir $overwrite
    cd $wrkdir || return

    jobarrays=()
    for mem in $(seq 1 $nenslbc); do
        memstr=$(printf "%02d" $mem)
        memwrkdir="$wrkdir/${domname}_$memstr"

        mkwrkdir $memwrkdir 1
        cd $memwrkdir || return

        ln -sf ../ungrib/${EXTHEAD}${memstr}:* .
        ln -sf $rundir/init/${domname}_${memstr}.init.nc .
        #ln -sf $rundir/init/${domname}.invariant.nc .

        if [[ ! -f $rundir/$domname/$domname.graph.info.part.${npelbc} ]]; then
            split_graph "${gpmetis}" "${domname}.graph.info" "${npelbc}" "$rundir/$domname" "$dorun" "$verb"
        fi
        ln -sf $rundir/$domname/$domname.graph.info.part.${npelbc} .

        cat << EOF > namelist.init_atmosphere
&nhyd_model
    config_init_case = 9
    config_start_time = '${starttime_str}'
    config_stop_time = '${endtime_str}'
    config_theta_adv_order = 3
    config_coef_3rd_order = 0.25
/
&dimensions
    config_nvertlevels   = ${nvertlevels}
    config_nsoillevels   = ${MPASNFLS}
    config_nfglevels     = ${EXTNFGL}
    config_nfgsoillevels = ${EXTNFLS}
    config_nsoilcat      = 16
/
&data_sources
    config_geog_data_path = '${WPSGEOG_PATH}'
    config_met_prefix = '${EXTHEAD}${memstr}'
    config_sfc_prefix = 'SST'
    config_fg_interval = ${EXTINVL}
    config_landuse_data = 'MODIFIED_IGBP_MODIS_NOAH_15s'
    config_topo_data = 'GMTED2010'
    config_vegfrac_data = 'MODIS'
    config_albedo_data = 'MODIS'
    config_maxsnowalbedo_data = 'MODIS'
    config_supersample_factor = 1
    config_use_spechumd = true
/
&vertical_grid
    config_ztop = 25878.712
    config_nsmterrain = 1
    config_smooth_surfaces = true
    config_dzmin = 0.3
    config_nsm = 30
    config_tc_vertical_grid = true
    config_blend_bdy_terrain = true
    config_specified_zeta_levels = '${vertLevel_file}'
/
&interpolation_control
    config_extrap_airtemp = 'lapse-rate'
/
&preproc_stages
    config_static_interp = false
    config_native_gwd_static = false
    config_vertical_grid = true
    config_met_interp = true
    config_input_sst = false
    config_frac_seaice = true
/
&io
    config_pio_num_iotasks = 0
    config_pio_stride = 1
/
&decomposition
    config_block_decomp_file_prefix = '$domname.graph.info.part.'
/
EOF

        cat << EOF > streams.init_atmosphere
<streams>
<immutable_stream name="input"
                  type="input"
                  filename_template="${domname}_${memstr}.init.nc"
                  input_interval="initial_only" />

<immutable_stream name="output"
                  type="output"
                  filename_template="$domname.none.nc"
                  io_type="netcdf"
                  packages="initial_conds"
                  clobber_mode="replace_files"
                  output_interval="initial_only" />

<immutable_stream name="surface"
                  type="output"
                  filename_template="$domname.sfc_update.nc"
                  filename_interval="none"
                  packages="sfc_update"
                  output_interval="${EXTINVL_STR}" />

<immutable_stream name="lbc"
                  type="output"
                  filename_template="${domname}_${memstr}.lbc.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
                  filename_interval="output_interval"
                  packages="lbcs"
                  io_type="${LBCIOTYPE}"
                  clobber_mode="replace_files"
                  output_interval="${EXTINVL_STR}" />

</streams>
EOF
        jobarrays+=("$mem")
    done
    #
    # Create job script and submit it
    #
    if [[ ${#jobarrays[@]} -gt 0 ]]; then
        jobscript="run_lbc_${domname}.${mach}"
        jobarraystr=$(get_jobarray_str "${mach}" "${jobarrays[@]}")

        declare -A jobParms=(
            [PARTION]="${partition_lbc}"
            [NOPART]="$npelbc"
            [CPUSPEC]="${claim_cpu_lbc}"
            [JOBNAME]="lbc_${jobname}"
            [PREFIX]="${domname}"
        )
        # shellcheck disable=SC2154
        if [[ "${mach}" == "pbs" ]]; then
            jobParms[NNODES]="${nnodes_ics}"
            # shellcheck disable=SC2034
            jobParms[NCORES]="${ncores_lbc}"
        fi

        # shellcheck disable=SC2154
        submit_a_job "$wrkdir" "${domname}" "jobParms" "$TEMPDIR/run_lbc_array.${mach}" "$jobscript" "${jobarraystr}"
    fi

    if [[ $dorun == true && $jobwait -eq 1 ]]; then
        #jobname=$1 mywrkdir=$2 donenum=$3 myjobscript=$4 numtries=${5-1}
        check_job_status "${domname}" $wrkdir $nenslbc $jobscript 2
    fi
}

########################################################################

function run_time_intrp {
    conditions=()
    while [[ $# -gt 0 ]]; do
        case $1 in
        /*)
            conditions+=("$1")
            ;;
        *)
            conditions+=("$rundir/$1")
            ;;
        esac
        shift
    done

    if [[ $dorun == true ]]; then
        for cond in "${conditions[@]}"; do
            mecho0 "Checking: ${CYAN}$cond${NC} ...."
            while [[ ! -e $cond ]]; do
                if [[ $verb -eq 1 ]]; then
                    mecho0 "Waiting for file: ${CYAN}$cond${NC}"
                fi

                # shellcheck disable=SC2154
                check_job_status "${domname}" "$rundir/lbc" "$nenslbc"
                sleep 10
            done
        done
    fi

    wrkdir=$rundir/lbc
    cd "${wrkdir}" || exit $?

    #@@@

    #source ${rootdir}/modules/env.python

    starttime_s=$(date -u -d "${eventdate}        ${eventtime}"        +%s)
    stoptime_s=$(date  -u -d "${stopdatetime:0:8} ${stopdatetime:8:4}" +%s)

    #[[ $verb -eq 1 ]] && mecho0 "Running time intrpolation ...."

    #for((i=starttime_s;i<=stoptime_s;i+=intvl_sec)); do
    #    min=$(date -u -d @$i +%M)
    #    j=$((10#$min*60))
    #    if [[ ${min} != "00" ]]; then
    #        i1=$((i-j))
    #        i2=$((i+3600-j))
    #        time_str=$(date  -u -d @$i  +%Y-%m-%d_%H.%M.%S)
    #        time_str1=$(date -u -d @$i1 +%Y-%m-%d_%H.%M.%S)
    #        time_str2=$(date -u -d @$i2 +%Y-%m-%d_%H.%M.%S)
    #        for mem in $(seq 1 $nenslbc); do
    #            printf -v mem_str "%02d" $mem
    #            lbc_filename="${domname}_${mem_str}.lbc.${time_str}.nc"
    #            lbc_file1="${domname}_${mem_str}.lbc.${time_str1}.nc"
    #            lbc_file2="${domname}_${mem_str}.lbc.${time_str2}.nc"
    #            if [[ ! -f ${lbc_filename} ]]; then
    #                if [[ $verb -eq 1 ]]; then
    #                    mecho0 "Interpolating lbc file: ${lbc_filename} file from"
    #                    mecho0 "                        ${lbc_file1} and"
    #                    mecho0 "                        ${lbc_file2}"
    #                fi
    #                ( ${scpdir}/intrp_time.py -t ${time_str} ${lbc_file1} ${lbc_file2} ${lbc_filename} ) &
    #            fi
    #        done
    #        wait
    #    fi
    #done

    jobarrays=()
    for mem in $(seq 1 $nenslbc); do
        jobarrays+=("$mem")
    done
    #
    # Create job script and submit it
    #
    if [[ ${#jobarrays[@]} -gt 0 ]]; then
        jobscript="run_intrp_${domname}.${mach}"
        jobarraystr=$(get_jobarray_str "${mach}" "${jobarrays[@]}")

        declare -A jobParms=(
            [PARTION]="${partition_lbc}"
            [NOPART]="$npelbc"
            [CPUSPEC]="${claim_cpu_lbc}"
            [JOBNAME]="intrp_${jobname}"
            [PREFIX]="${domname}"
            [STARTSECS]="${starttime_s}"
            [STOPSECS]="${stoptime_s}"
            [INTVL_SECS]=${intvl_sec}
        )
        # shellcheck disable=SC2154
        if [[ "${mach}" == "pbs" ]]; then
            jobParms[NNODES]="${nnodes_ics}"
            # shellcheck disable=SC2034
            jobParms[NCORES]="${ncores_lbc}"
        fi

        # shellcheck disable=SC2154
        submit_a_job "$wrkdir" "${domname}" "jobParms" "$TEMPDIR/run_lbc_intrp_array.${mach}" "$jobscript" "${jobarraystr}"
    fi

    if [[ $dorun == true && $jobwait -eq 1 ]]; then
        #jobname=$1 mywrkdir=$2 donenum=$3 myjobscript=$4 numtries=${5-1}
        check_job_status "${domname}" $wrkdir $nenslbc $jobscript 2
    fi
}

########################################################################

function run_clean {

    for dirname in "$@"; do
        case $dirname in
        ungrib )
            if "${cleanall}"; then
                cd "$rundir/lbc" || return
                rm -rf ungrib
            else
                cd "$rundir/lbc/ungrib" || return
                if [[ -e done.ungrib ]]; then
                    #jobname=$1 mywrkdir=$2 nummem=$3
                    clean_mem_runfiles "ungrib" "$rundir/lbc/ungrib" "$nenslbc"
                fi
            fi
            ;;
        lbc )
            cd "$rundir/lbc" || return
            if [[ -e done.${domname} ]]; then
                #jobname=$1 mywrkdir=$2 nummem=$3
                clean_mem_runfiles "${domname}" "$rundir/lbc" "$nenslbc"
            fi
            ;;
        esac
    done
}

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#
#@ MAIN entry
#
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

source $scpdir/Common_Utilfuncs.sh || exit $?

#-----------------------------------------------------------------------
#
# Handle command line arguments (override default settings)
#
#-----------------------------------------------------------------------
#% ARGS

parse_args "$@"

[[ -v args["verb"] ]]      && verb=${args["verb"]}           || verb=0
[[ -v args["overwrite"] ]] && overwrite=${args["overwrite"]} || overwrite=0

[[ -v args["dorun"] ]]     && dorun=${args["dorun"]}         || dorun=true
[[ -v args["jobwait"] ]]   && jobwait=${args["jobwait"]}     || jobwait=0

[[ -v args["cleanall"] ]]  && cleanall=${args["cleanall"]}   || cleanall=false  # realtime run?

#-----------------------------------------------------------------------
#
# Get jobs to run
#
#-----------------------------------------------------------------------

[[ -v args["jobs"] ]] && read -r -a jobs <<< "${args['jobs']}" || jobs=(ungrib lbc clean)

[[ " ${jobs[*]} " =~ [[:space:]]time_intrp[[:space:]] ]] && usepython=true || usepython=false

#-----------------------------------------------------------------------
#
# Set up working environment
#
#-----------------------------------------------------------------------

source "${scpdir}/Site_Runtime.sh" || exit $?


setup_machine "${args['machine']}" "$rootdir" ${usepython} false

[[ $dorun == false ]] && runcmd="echo $runcmd"

[[ -v args["WORKDIR"] ]] && WORKDIR=${args["WORKDIR"]} || WORKDIR="${workdirDF}"

#-----------------------------------------------------------------------
#
# Set Event Date and Start Time
#
#-----------------------------------------------------------------------
[[ -v args["eventdate"] ]] && eventdate="${args['eventdate']}" || eventdate="$eventdateDF"
[[ -v args["eventtime"] ]] && eventtime="${args['eventtime']}" || eventtime="1500"

#-----------------------------------------------------------------------
#
# read configurations that is not set from command line
#
#-----------------------------------------------------------------------
if [[ -v args["config_file"] ]]; then
    config_file="${args['config_file']}"

    if [[ "$config_file" =~ "/" ]]; then
        WORKDIR=$(realpath "$(dirname ${config_file})")
    else
        config_file="${WORKDIR}/${config_file}"
    fi
    [[ ${config_file} =~ config\.([0-9]{8}) && ! -v args["eventdate"] ]] && eventdate="${BASH_REMATCH[1]}"
else
    config_file="$WORKDIR/config.${eventdate}"
fi

if [[ -r ${config_file} ]]; then
    echo -e "Reading case (${GREEN}${eventdate}${NC}) configuration file: ${CYAN}${config_file}${NC} ...."
else
    echo -e "${RED}ERROR${NC}: Configuration file ${CYAN}${config_file}${NC} is not found."
    echo -e "       Please run ${GREEN}setup_mpas-wofs.sh${NC} first or use ${BLUE}-h${NC} to show help."
    exit 2
fi
readconf ${config_file} COMMON lbc || exit $?
# get ENS_SIZE, EXTINVL, LBCIOTYPE

if [[ -e ${vertLevel_file} ]]; then
    nvertlevels=$(cat ${vertLevel_file} | sed '/^\s*$/d' | wc -l)
    (( nvertlevels -= 1 ))
else
    echo -e "${RED}ERROR${NC}: vertLevel_file=${BLUE}${vertLevel_file}${NC} not exist."
    usage 1
fi
#-----------------------------------------------------------------------
#
# Set Event End Date and Time
#
#-----------------------------------------------------------------------

if [[ -v args["enddatetime"] ]]; then
    enddatetime="${args['enddatetime']}"
elif [[ -v args["endtime"] ]]; then
    endtime="${args['endtime']}"
    endhour=${endtime:0:2}
    if ((10#$endhour < 12)); then
        enddatetime=$(date -u -d "${eventdate} ${endtime} 1 day" +%Y%m%d%H%M)
    else
        enddatetime=$(date -u -d "${eventdate} $endtime" +%Y%m%d%H%M)
    fi
else
    enddatetime=$(date -u -d "${eventdate} 0900 1 day" +%Y%m%d%H%M)
fi

if [[ -v args["stoptime"] ]]; then
    stoptime="${args['stoptime']}"
    stophour=${stoptime:0:2}
    if ((10#$stophour < 12)); then
        stopdatetime=$(date -u -d "${eventdate} ${stoptime} 1 day" +%Y%m%d%H%M)
    else
        stopdatetime=$(date -u -d "${eventdate} ${stoptime}" +%Y%m%d%H%M)
    fi
else
    stopdatetime=$(date -u -d "${eventdate} 0300 1 day" +%Y%m%d%H%M)
fi

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#
# Perform each task
#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#% ENTRY
rundir="$WORKDIR/${eventdate}"
if [[ ! -d $rundir ]]; then
    mkdir -p $rundir
fi

echo    ""
echo -e "---- Jobs (${YELLOW}$$${NC}) started at $(date +'%m-%d %H:%M:%S (%Z)') on host ${LIGHT_RED}$(hostname)${NC} ----\n"
echo -e "  Event  date: ${WHITE}$eventdate${NC} ${YELLOW}${eventtime}${NC} --> ${WHITE}${enddatetime:0:8}${NC} ${YELLOW}${enddatetime:8:4}${NC}"
echo -e "  ROOT    dir: ${rootdir}${BROWN}/scripts${NC}"
echo -e "  TEMP    dir: ${PURPLE}${TEMPDIR}${NC}"
echo -e "  FIXED   dir: ${DARK}${FIXDIR}${NC}"
echo -e "  EXEC    dir: ${GREEN}${EXEDIR}${NC}"
echo -e "  Working dir: ${WHITE}${WORKDIR}${LIGHT_BLUE}/${eventdate}/lbc${NC}"
echo -e "  Domain name: ${RED}$domname${NC}; HRRRE time: ${DARK}${hrrr_time}${NC}; NENSLBC: ${WHITE}${nenslbc}${NC}"
echo    " "

jobname="${eventdate:4:4}"

starttime_str=$(date -u -d "${eventdate}       ${eventtime}"       +%Y-%m-%d_%H:%M:%S)
endtime_str=$(date   -u -d "${enddatetime:0:8} ${enddatetime:8:4}" +%Y-%m-%d_%H:%M:%S)

EXTINVL_STR=$(printf "%02d:00:00" $((EXTINVL/3600)) )

#
# Start to execute each procedue
#

declare -A jobargs=([ungrib]="${hrrr_dir} ${hrrr_time}"                 \
                    [lbc]="lbc/ungrib/done.ungrib init/done.${domname}" \
                    [clean]="ungrib lbc"                                \
                    [cleanungrib]=""                                    \
                    [time_intrp]="lbc/done.${domname}"                  \
                   )

for job in "${jobs[@]}"; do
    if [[ $verb -eq 1 ]]; then
        echo " "
        echo "    run_$job ${jobargs[$job]}"
    fi

    run_$job ${jobargs[$job]}
done

echo " "
echo "==== Jobs done $(date +'%m-%d %H:%M:%S (%Z)') ===="
echo " "

exit 0
