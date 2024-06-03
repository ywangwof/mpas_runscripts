#!/bin/bash
# shellcheck disable=SC2317,SC1090,SC1091,SC2086,SC2154

#rootdir="/scratch/ywang/MPAS/mpas_runscripts"
scpdir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
rootdir=$(realpath "$(dirname "${scpdir}")")

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
    echo "    DATETIME - Case date and time in YYYYMMDD, Default for today"
    echo "    WORKDIR  - Run Directory"
    echo "    JOBS     - One or more jobs from [ungrib,init,clean]"
    echo "               Default all jobs in sequence"
    echo " "
    echo "    OPTIONS:"
    echo "              -h                  Display this message"
    echo "              -n                  Show command to be run and generate job scripts only"
    echo "              -v                  Verbose mode"
    echo "              -k  [0,1,2]         Keep working directory if exist, 0- keep as is; 1- overwrite; 2- make a backup as xxxx.bak?"
    echo "                                  Default is 0 for ungrib, mpassit, upp and 1 for others"
    echo "              -a                  Clean the \"ungrib\" directory completely when JOBS contain \"clean\""
    echo "              -t  DIR             Template directory for runtime files"
    echo "              -w                  Hold script to wait for all job conditions are satified and submitted (for mpassit & upp)."
    echo "                                  By default, the script will exit after submitting all possible jobs."
    echo "              -m  Machine         Machine name to run on, [Jet, Cheyenne, Vecna]."
    echo "              -s  init_dir        Directory name from which init & lbc subdirectories are used to initialize this run"
    echo "                                  which avoids runing duplicated preprocessing jobs (ungrib, init/lbc) again. default: false"
    echo "              -f conf_file        Configuration file for this case. Default: ${WORKDIR}/config.${eventdate}"
    echo " "
    echo "   DEFAULTS:"
    echo "              eventdt = $eventdate"
    echo "              rootdir = $rootdir"
    echo "              WORKDIR = $WORKDIR"
    echo "              TEMPDIR = $rootdir/templates"
    echo "              FIXDIR  = $rootdir/fix_files"
    echo " "
    echo "                                     -- By Y. Wang (2023.05.25)"
    echo " "
    exit $1
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
        ends=$(date -u -d "$eventdate $eventend 1 day" +%s)
        endhr=$(( (ends-starts)/3600 ))

        gribstart_str=$(date -u -d "$eventdate $gribtime $starthr hours" +%Y-%m-%d_%H:%M:%S )
        gribendtm_str=$(date -u -d "$eventdate $gribtime $endhr hours"   +%Y-%m-%d_%H:%M:%S )

        mecho0 "GRIB files from ${grib_dir}:"
        gribfiles=()
        for (( h=starthr;h<=endhr;h+=$((EXTINVL/3600)) )); do
            hstr=$(printf "%02d" $h)
            #gribfile=$grib_dir/$eventdate/${gribtime}/mem${memstr}/wrfnat_pert_hrrr_mem00${memstr}_${hstr}.grib2
            gribfilename="$eventdate/${gribtime}/postprd_mem00${memstr}/wrfnat_pert_hrrr_mem00${memstr}_${hstr}.grib2"
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
        jobscript="run_ungrib.slurm"
        # shellcheck disable=SC2154
        jobarraystr=$(get_jobarray_str "${mach}" "${jobarrays[@]}")

        sedfile=$(mktemp -t ungrib_${jobname}.sed_XXXX)
        # shellcheck disable=SC2154
        cat <<EOF > $sedfile
s/PARTION/${partition_lbc}/
s/JOBNAME/ungrb_${jobname}/
s/CPUSPEC/${claim_cpu_ungrib}/
s/MODULE/${modulename}/g
s#ROOTDIR#$rootdir#g
s#WRKDIR#$wrkdir#g
s#EXEDIR#${exedir}#
s#PREFIX#${EXTHEAD}#g
s/ACCTSTR/${job_account_str}/
s/EXCLSTR/${job_exclusive_str}/
s/RUNCMD/${job_runexe_str}/
EOF
        # shellcheck disable=SC2154
        submit_a_jobscript $wrkdir "ungrib" $sedfile $TEMPDIR/run_ungrib_array.${mach} $jobscript ${jobarraystr}
    fi

    if [[ $dorun == true && $jobwait -eq 1 ]]; then
        #jobname=$1 mywrkdir=$2 donenum=$3 myjobscript=$4 numtries=${5-3}
        check_job_status "ungrib" $wrkdir $nenslbc $jobscript 2
    fi
}

########################################################################

function run_lbc {

    if [[ -d $init_dir ]]; then  # link it from somewhere

        if [[ $dorun == true ]]; then
            donefile="$init_dir/lbc/done.${domname}"
            mecho0 "Checking: ${CYAN}$donefile${NC} ...."
            while [[ ! -e $donefile ]]; do
                if [[ $verb -eq 1 ]]; then
                    mecho0 "Waiting for file: ${CYAN}$donefile${NC}"
                fi
                sleep 10
            done
        fi

        cd $rundir || return
        ln -sf $init_dir/lbc .
        return
    fi

    # otherwise, run lbc normally

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
    if [[ -f $wrkdir/running.${domname} || -f $wrkdir/done.${domname} || -f $wrkdir/queue.${domname} ]]; then
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
            cd $rundir/$domname || return
            # shellcheck disable=SC2154
            if [[ $verb -eq 1 ]]; then
                mecho0 "Generating ${CYAN}${domname}.graph.info.part.${npelbc}${NC} in ${BLUE}${rundir##"${WORKDIR}"/}/$domname${NC} using ${GREEN}${gpmetis}${NC}"
            fi
            ${gpmetis} -minconn -contig -niter=200 ${domname}.graph.info ${npelbc} > gpmetis.out$npelbc
            estatus=$?
            if [[ ${estatus} -ne 0 ]]; then
                mecho0 "${estatus}: ${gpmetis} -minconn -contig -niter=200 ${domname}.graph.info ${npelbc}"
                exit ${estatus}
            fi
            cd $mywrkdir || return
        fi
        ln -sf $rundir/$domname/$domname.graph.info.part.${npelbc} .

        cat << EOF > namelist.init_atmosphere
&nhyd_model
    config_init_case = 9
    config_start_time = '${starttime_str}'
    config_stop_time = '${stoptime_str}'
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
    config_use_spechumd = false
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

        sedfile=$(mktemp -t lbc_${jobname}.sed_XXXX)

        # shellcheck disable=SC2154
        cat <<EOF > $sedfile
s/PARTION/${partition_lbc}/
s/MACHINE/${machine}/g
s/NOPART/$npelbc/
s/CPUSPEC/${claim_cpu_lbc}/
s/JOBNAME/lbc_${jobname}/
s/MODULE/${modulename}/g
s#ROOTDIR#$rootdir#g
s#WRKDIR#$wrkdir#g
s#EXEDIR#${exedir}#
s#PREFIX#${domname}#g
s/ACCTSTR/${job_account_str}/
s/EXCLSTR/${job_exclusive_str}/
s/RUNMPCMD/${job_runmpexe_str}/
EOF

        # shellcheck disable=SC2154
        if [[ "${mach}" == "pbs" ]]; then
            echo "s/NNODES/${nnodes_ics}/;s/NCORES/${ncores_lbc}/" >> $sedfile
        fi

        # shellcheck disable=SC2154
        submit_a_jobscript $wrkdir "${domname}" $sedfile $TEMPDIR/run_lbc_array.${mach} $jobscript ${jobarraystr}
    fi

    if [[ $dorun == true && $jobwait -eq 1 ]]; then

        #jobname=$1 mywrkdir=$2 donenum=$3 myjobscript=$4 numtries=${5-3}
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
# Default values
#
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#@ MAIN

jobs=(ungrib lbc clean)

WORKDIR="${rootdir}/run_dirs"
TEMPDIR="${rootdir}/templates"
FIXDIR="${rootdir}/fix_files"
eventdate="$eventdateDF"
eventtime="1500"
eventend="0900"

init_dir=false
runcmd="sbatch"
dorun=true
verb=0
overwrite=0
jobwait=0

cleanall=false

machine="Jet"

myhostname=$(hostname)
if [[ "${myhostname}" == ln? ]]; then
    machine="Vecna"
elif [[ "${myhostname}" == hercules* ]]; then
    machine="Hercules"
elif [[ "${myhostname}" == cheyenne* || "${myhostname}" == derecho* ]]; then
    machine="Cheyenne"
else
    machine="Jet"
fi

source $scpdir/Common_Utilfuncs.sh || exit $?

#-----------------------------------------------------------------------
#
# Handle command line arguments
#
#-----------------------------------------------------------------------
#% ARGS

while [[ $# -gt 0 ]]
    do
    key="$1"

    case $key in
        -h)
            usage 0
            ;;
        -n)
            runcmd="echo $runcmd"
            dorun=false
            ;;
        -v)
            verb=1
            ;;
        -a)
            cleanall=true
            ;;
        -k)
            if [[ $2 =~ [012] ]]; then
                overwrite=$2
                shift
            else
                echo -e "${RED}ERROR${NC}: option for ${BLUE}-k${NC} can only be [${YELLOW}0-2${NC}], but got ${PURPLE}$2${NC}."
                usage 1
            fi
            ;;
        -w)
            jobwait=1
            ;;
        -t)
            if [[ -d $2 ]]; then
                TEMPDIR=$2
            else
                echo -e "${RED}ERROR${NC}: Template directory ${BLUE}$2${NC} does not exist."
                usage 1
            fi
            shift
            ;;
        -m)
            if [[ ${2^^} == "JET" ]]; then
                machine=Jet
            elif [[ ${2^^} == "VECNA" ]]; then
                machine=Vecna
            elif [[ ${2^^} == "HERCULES" ]]; then
                machine=Hercules
            elif [[ ${2^^} == "CHEYENNE" ]]; then
                machine=Cheyenne
            else
                echo -e "${RED}ERROR${NC}: Unsupported machine name, got ${PURPLE}$2${NC}."
                usage 1
            fi
            shift
            ;;
        -f)
            config_file="$2"
            shift
            ;;
        -s )
            if [[ -d ${2} ]]; then        # use init & lbc from another run directory
                init_dir=$2
                while [[ ! -d $init_dir/init ]]; do
                    echo -e "Waiting for ${CYAN}$init_dir/init${NC} ...."
                    sleep 10
                done

                while [[ ! -d $init_dir/lbc ]]; do
                    echo -e "Waiting for ${CYAN}$init_dir/lbc${NC} ...."
                    sleep 10
                done
            else
                echo -e "${RED}ERROR${NC}: initialization directory ${PURPLE}$2${NC} not exists."
                usage 1
            fi
            shift
            ;;
         -*)
            echo -e "${RED}ERROR${NC}: Unknown option: ${PURPLE}$key${NC}"
            usage 2
            ;;
        ungrib* | lbc* | clean* )
            #jobs=(${key//,/ })
            IFS="," read -r -a jobs <<< "$key"
            ;;
        *)
            if [[ $key =~ ^[0-9]{8}$ ]]; then
                eventdate="$key"
            elif [[ -d $key ]]; then
                WORKDIR=$key
                lastdir=$(basename $WORKDIR)
                if [[ $lastdir =~ ^[0-9]{8}$ ]]; then
                    eventstr=${lastdir}
                    WORKDIR=${WORKDIR%%/"$lastdir"}
                    eventdate=${eventstr:0:8}
                fi

                #echo $WORKDIR,${jobs[*]},$eventdate,$eventtime
            else
                echo  -e "${RED}ERROR${NC}: unknown argument, get ${PURPLE}$key${NC}."
                usage 3
            fi
            ;;
    esac
    shift # past argument or value
done

if [[ $init_dir != false ]]; then
    jobs=( "${jobs[@]/ungrib}" )          # drop ungrib from the jobs list
fi

#
# read configurations that is not set from command line
#
if [[ -z $config_file ]]; then
    config_file="$WORKDIR/config.${eventdate}"
else
    if [[ -e ${WORKDIR}/${config_file} ]]; then
        config_file="${WORKDIR}/${config_file}"
    else
        echo -e "${RED}ERROR${NC}: file ${CYAN}${config_file}${NC} not exist."
        usage 1
    fi
fi

if [[ ! -r ${config_file} ]]; then
    echo -e "${RED}ERROR${NC}: Configuration file ${CYAN}${config_file}${NC} is not found."
    echo -e "       Please run ${GREEN}setup_mpas-wofs_grid.sh${NC} first."
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
# Platform specific initialization
#
#-----------------------------------------------------------------------
#% PLATFORM

if [[ $machine == "Jet" ]]; then
    modulename="build_jet_Rocky8_intel_smiol"

    source /etc/profile.d/modules.sh
    module purge
    module use ${rootdir}/modules
    module load $modulename
    module load wgrib2/2.0.8
elif [[ $machine == "Hercules" ]]; then
    modulename="build_hercules_intel"

    module purge
    module use ${rootdir}/modules
    module load $modulename
elif [[ $machine == "Cheyenne" ]]; then
    if [[ $dorun == true ]]; then
        runcmd="qsub"
    fi
    modulename="defaults"
else    # Vecna at NSSL
    modulename="env.mpas_smiol"
    source ${rootdir}/modules/${modulename}
fi

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#
# Perform each task
#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#% ENTRY

echo    "---- Jobs ($$) started $(date +%m-%d_%H:%M:%S) on host $(hostname) ----"
echo -e "     Event date : ${GREEN}$eventdate${NC} ${LIGHT_BLUE}${eventtime}${NC}"
echo    "     Root    dir: $rootdir"
echo    "     Working dir: $WORKDIR"
echo -e "     Domain name: ${PURPLE}$domname${NC};  MP scheme: ${BROWN}${mpscheme}${NC}"
echo    " "

starttime_str=$(date -u -d "$eventdate ${eventtime}"      +%Y-%m-%d_%H:%M:%S)
stoptime_str=$(date -u -d "$eventdate  ${eventend} 1 day" +%Y-%m-%d_%H:%M:%S)

rundir="$WORKDIR/${eventdate}"

if [[ ! -d $rundir ]]; then
    mkdir -p $rundir
fi

jobname="${eventdate:4:4}"

exedir="$rootdir/exec"

EXTINVL_STR=$(printf "%02d:00:00" $((EXTINVL/3600)) )

#
# Start to execute each procedue
#

declare -A jobargs=([ungrib]="${hrrr_dir} ${hrrr_time}"                 \
                    [lbc]="lbc/ungrib/done.ungrib init/done.${domname}" \
                    [clean]="ungrib lbc"                                \
                    [cleanungrib]=""                                    \
                   )

for job in "${jobs[@]}"; do
    if [[ $verb -eq 1 ]]; then
        echo " "
        echo "    run_$job ${jobargs[$job]}"
    fi

    run_$job ${jobargs[$job]}
done

echo " "
echo "==== Jobs done $(date +%m-%d_%H:%M:%S) ===="
echo " "

exit 0
