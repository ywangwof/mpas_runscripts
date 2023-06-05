#!/bin/bash

#rootdir="/scratch/ywang/MPAS/mpas_runscripts"
scpdir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
rootdir=$(realpath $(dirname $scpdir))

eventdateDF=$(date +%Y%m%d)

#-----------------------------------------------------------------------
#
# This is the 2nd step of th WOFS-MPAS workflow. It run program ungrib.exe
# & init_atmosphere_model to generate initial condition for all ensemble members.
#
# Required files from ROOTDIR
#
# 0. module files in modules
#     build_jet_intel18_1.11_smiol
#     build_jet_intel18_1.11                # PIO version
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
#        run_init_array.slurm                or run_init.pbs
#        run_ungrib_array.slurm
#
# 3. fix_files                              # runtime fix files for MPAS model and accompany programs
#
#    3.1 WPS run-time files for program ungrib
#        WRFV4.0/Vtable.HRRRE.2018
#
# 4. scripts                                # this scripts
#    4.1 make_ics.sh
#
# INSTRUCTIONS:
#
#  Use existing domain (wofs_mpas)
#
#     0. It should be run after "setup_mpas-wofs_grid.sh"
#     1. make_ics.sh [YYYYmmddHH] [run_dirs] [jobnames]
#
#-----------------------------------------------------------------------

function usage {
    echo " "
    echo "    USAGE: $0 [options] DATETIME [WORKDIR] [JOBS]"
    echo " "
    echo "    PURPOSE: Make initial ensemble files before the MPAS-WOFS DA cycles"
    echo " "
    echo "    DATETIME - Case date and time in YYYYMMDD, Default for today"
    echo "    WORKDIR  - Run Directory"
    echo "    JOBS     - One or more jobs from [ungrib,init,clean]"
    echo "               Default all jobs in sequence"
    echo " "
    echo "    OPTIONS:"
    echo "              -h              Display this message"
    echo "              -n              Show command to be run and generate job scripts only"
    echo "              -v              Verbose mode"
    echo "              -k  [0,1,2]     Keep working directory if exist, 0- keep as is; 1- overwrite; 2- make a backup as xxxx.bak?"
    echo "                              Default is 0 for ungrib, mpassit, upp and 1 for others"
    echo "              -t  DIR         Template directory for runtime files"
    echo "              -w              Hold script to wait for all job conditions are satified and submitted (for mpassit & upp)."
    echo "                              By default, the script will exit after submitting all possible jobs."
    echo "              -m  Machine     Machine name to run on, [Jet, Cheyenne, Vecna]."
    echo "              -a  wof         Account name for job submission."
    echo "              -d  wofs_mpas   Domain name, default: wofs_mpas"
    echo "              -s  init_dir    Directory name from which init & lbc subdirectories are used to initialize this run"
    echo "                              which avoids runing duplicated preprocessing jobs (ungrib, init/lbc) again. default: false"
    echo "              -p  npeics      Number of MPI parts for ICs/LBCs, default: 24"
    echo " "
    echo "   DEFAULTS:"
    echo "              eventdt = $eventdateDF"
    echo "              rootdir = $rootdir"
    echo "              WORKDIR = $rootdir/run_dirs"
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

    wrkdir=$rundir/init/ungrib
    mkwrkdir $wrkdir 0
    cd $wrkdir

    if [[ -f ungrib.running || -f done.ungrib || -f queue.ungrib ]]; then
        return 0                   # skip
    else
        starthr=$((eventtime-gribtime))
        hstr=$(printf "%02d" $starthr)

        jobarrays=()
        for mem in $(seq 1 $nensics); do
            memstr=$(printf "%02d" $mem)
            gribfile=$grib_dir/$eventdate/${gribtime}00/postprd_mem00${memstr}/wrfnat_hrrre_newse_mem00${memstr}_${hstr}.grib2

            echo "GRIB file: $gribfile"
            while [[ ! -f $gribfile ]]; do
                if [[ $verb -eq 1 ]]; then
                    echo "Waiting for $gribfile ..."
                fi
                sleep 10
            done

            mywrkdir="$wrkdir/ungrib_$memstr"
            mkwrkdir $mywrkdir 1
            cd $mywrkdir

            ln -sf $gribfile GRIBFILE.AAA
            ln -sf $FIXDIR/WRFV4.0/Vtable.HRRRE.2018 Vtable

            cat << EOF > namelist.wps
&share
 wrf_core = 'ARW',
 max_dom = 1,
 start_date = '${starttime_str}',
 end_date = '${starttime_str}',
 interval_seconds = $((EXTINVL*3600))
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
            jobarrays+=($mem)
        done

        #
        # Create job script and submit it
        #
        cd $wrkdir

        if [[ ${#jobarrays[@]} -gt 0 ]]; then
            jobscript="run_ungrib.slurm"
            jobarraystr="--array=$(join_by_comma ${jobarrays[@]})"

            sedfile=$(mktemp -t ungrib_${jobname}.sed_XXXX)
            cat <<EOF > $sedfile
s/PARTION/${partition}/
s/JOBNAME/ungrb_${jobname}/
s#WRKDIR#$wrkdir#g
s#EXEDIR#${exedir}#
s#PREFIX#${EXTHEAD}#g
s/ACCTSTR/${job_account_str}/
s/EXCLSTR/${job_exclusive_str}/
s/RUNCMD/${job_runexe_str}/
EOF
            submit_a_jobscript $wrkdir "ungrib" $sedfile $TEMPDIR/run_ungrib_array.${mach} $jobscript ${jobarraystr}
        fi
    fi

    if [[ $dorun == true && $jobwait -eq 1 ]]; then
        #jobname=$1 mywrkdir=$2 donenum=$3 myjobscript=$4 numtries=${5-3}
        check_and_resubmit "ungrib" $wrkdir $nensics $jobscript 2
    fi
}

########################################################################

function run_init {

    if [[ -d $init_dir ]]; then  # link it from somewhere

        if [[ $dorun == true ]]; then
            donefile="$init_dir/init/done.init"
            echo "$$: Checking: $donefile"
            while [[ ! -e $donefile ]]; do
                if [[ $verb -eq 1 ]]; then
                    echo "Waiting for file: $donefile"
                fi

                sleep 10
            done
        fi

        cd $rundir
        ln -sf $init_dir/init .
        return
    fi

    # Otherwise, run init normally
    conditions=()
    while [[ $# > 0 ]]; do
        case $1 in
        /*)
            conditions+=($1)
            ;;
        *)
            conditions+=($rundir/$1)
            ;;
        esac
        shift
    done

    if [[ $dorun == true ]]; then
        for cond in ${conditions[@]}; do
            echo "$$: Checking: $cond"
            while [[ ! -e $cond ]]; do
                check_and_resubmit "ungrib" $rundir/init/ungrib $nensics
                if [[ $verb -eq 1 ]]; then
                    echo "Waiting for file: $cond"
                fi
                sleep 10
            done
        done
    fi

    wrkdir=$rundir/init
    if [[ -f $wrkdir/init.running || -f $wrkdir/done.init || -f $wrkdir/queue.init ]]; then
        return 0
    fi

    mkwrkdir $wrkdir $overwrite
    cd $wrkdir

    jobarrays=()
    for mem in $(seq 1 $nensics); do
        memstr=$(printf "%02d" $mem)
        mywrkdir="$wrkdir/init_$memstr"

        mkwrkdir $mywrkdir 1
        cd $mywrkdir

        ln -sf ../ungrib/${EXTHEAD}${memstr}:${starttime_str:0:13} .
        ln -sf $rundir/$domname/$domname.static.nc .

        if [[ ! -f $rundir/$domname/$domname.graph.info.part.${npeics} ]]; then
            cd $rundir/$domname
            if [[ $verb -eq 1 ]]; then
                echo "Generating ${domname}.graph.info.part.${npeics} in $rundir/$domname using $exedir/gpmetis"
            fi
            $exedir/gpmetis -minconn -contig -niter=200 ${domname}.graph.info ${npeics} > $exedir/gpmetis.out$npeics
            if [[ $? -ne 0 ]]; then
                echo "$?: $exedir/gpmetis -minconn -contig -niter=200 ${domname}.graph.info ${npeics}"
                exit $?
            fi
            cd $mywrkdir
        fi
        ln -sf $rundir/$domname/$domname.graph.info.part.${npeics} .

        cat << EOF > namelist.init_atmosphere
&nhyd_model
    config_init_case = 7
    config_start_time = '${starttime_str}'
    config_stop_time = '${stoptime_str}'
    config_theta_adv_order = 3
    config_coef_3rd_order = 0.25
/
&dimensions
    config_nvertlevels   = 59
    config_nsoillevels   = ${MPASNFLS}
    config_nfglevels     = ${EXTNFGL}
    config_nfgsoillevels = ${EXTNFLS}
    config_nsoilcat      = 16
/
&data_sources
    config_geog_data_path = '${WPSGEOG_PATH}'
    config_met_prefix = '${EXTHEAD}${memstr}'
    config_sfc_prefix = 'SST'
    config_fg_interval = $((EXTINVL*3600))
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
    config_specified_zeta_levels = '${FIXDIR}/L60.txt'
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
                  filename_template="$domname.static.nc"
                  input_interval="initial_only" />

<immutable_stream name="output"
                  type="output"
                  filename_template="${domname}_${memstr}.init.nc"
                  io_type="${ICSIOTYPE}"
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
                  filename_template="$domname.lbc.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
                  filename_interval="output_interval"
                  packages="lbcs"
                  clobber_mode="replace_files"
                  output_interval="${EXTINVL_STR}" />

</streams>
EOF
        jobarrays+=($mem)
    done
    #
    # Create job script and submit it
    #
    if [[ ${#jobarrays[@]} -gt 0 ]]; then
        jobscript="run_init.${mach}"
        jobarraystr="--array=$(join_by_comma ${jobarrays[@]})"

        sedfile=$(mktemp -t init_${jobname}.sed_XXXX)
        cat <<EOF > $sedfile
s/PARTION/${partition}/
s/MACHINE/${machine}/g
s/NOPART/$npeics/
s/CPUSPEC/${claim_cpu_ics}/
s/JOBNAME/init_${jobname}/
s/MODULE/${modulename}/g
s#ROOTDIR#$rootdir#g
s#WRKDIR#$wrkdir#g
s#EXEDIR#${exedir}#
s#PREFIX#${domname}#
s/ACCTSTR/${job_account_str}/
s/EXCLSTR/${job_exclusive_str}/
s/RUNMPCMD/${job_runmpexe_str}/
EOF
        if [[ "${mach}" == "pbs" ]]; then
            echo "s/NNODES/${nnodes_ics}/;s/NCORES/${ncores_ics}/" >> $sedfile
        fi

        submit_a_jobscript $wrkdir "init" $sedfile $TEMPDIR/run_init_array.${mach} $jobscript ${jobarraystr}
    fi

    if [[ $dorun == true && $jobwait -eq 1 ]]; then

        #jobname=$1 mywrkdir=$2 donenum=$3 myjobscript=$4 numtries=${5-3}
        check_and_resubmit "init" $wrkdir $nensics $jobscript 2
    fi
}

########################################################################

function run_clean {

    for dirname in $@; do
        case $dirname in
        ungrib )
            cd $rundir/init/ungrib
            #jobname=$1 mywrkdir=$2 nummem=$3
            clean_mem_runfiles "ungrib" $rundir/init/ungrib $nensics
            ;;
        init )
            cd $rundir/init
            #jobname=$1 mywrkdir=$2 nummem=$3
            clean_mem_runfiles "init" $rundir/init $nensics
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

jobs=(ungrib init clean)

WORKDIR="${rootdir}/run_dirs"
TEMPDIR="${rootdir}/templates"
FIXDIR="${rootdir}/fix_files"
eventdate="$eventdateDF"
eventtime="15"
nensics=36
hrrr_dir="/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/MODEL_DATA/HRRRE"
hrrr_time="14"
EXTHEAD="HRRRE"
EXTNFGL=51
EXTNFLS=9

domname="wofs_mpas"
npeics=24
init_dir=false
runcmd="sbatch"
dorun=true
verb=0
overwrite=0
jobwait=0
machine="Jet"
if [[ "$(hostname)" == ln? ]]; then
    machine="Vecna"
elif [[ "$(hostname)" == cheyenne* ]]; then
    machine="Cheyenne"
fi

#-----------------------------------------------------------------------
#
# Handle command line arguments
#
#-----------------------------------------------------------------------
#% ARGS

while [[ $# > 0 ]]
    do
    key="$1"

    case $key in
        -h)
            usage 0
            ;;
        -n)
            runcmd="echo"
            dorun=false
            ;;
        -v)
            verb=1
            ;;
        -k)
            if [[ $2 =~ [012] ]]; then
                overwrite=$2
                shift
            else
                echo "ERROR: option for '-k' can only be [0-2], but got \"$2\"."
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
                echo "ERROR: Template directory \"$2\" does not exist."
                usage 1
            fi
            shift
            ;;
        -m)
            if [[ ${2^^} == "JET" ]]; then
                machine=Jet
            elif [[ ${2^^} == "VECNA" ]]; then
                machine=Vecna
            elif [[ ${2^^} == "CHEYENNE" ]]; then
                machine=Cheyenne
            else
                echo "ERROR: Unsupported machine name, got \"$2\"."
                usage 1
            fi
            shift
            ;;
        -a)
            hpcaccount=$2
            shift
            ;;
        -d)
            domname=$2
            shift
            ;;
        -s )
            if [[ -d ${2} ]]; then        # use init & lbc from another run directory
                init_dir=$2
                while [[ ! -d $init_dir/init ]]; do
                    echo "Waiting for $init_dir/init"
                    sleep 10
                done

                while [[ ! -d $init_dir/lbc ]]; do
                    echo "Waiting for $init_dir/lbc"
                    sleep 10
                done
            else
                echo "ERROR: initialization directory  \"$2\" not exists."
                usage 1
            fi
            shift
            ;;
        -p)
            if [[ $2 =~ ^[0-9]+$ ]]; then
                npeics=$2
            else
                echo "ERROR: npes is required as \"npeics\", get: $2."
                usage 1
            fi
            shift
            ;;
         -*)
            echo "Unknown option: $key"
            usage 2
            ;;
        ungrib* | init* | clean* )
            jobs=(${key//,/ })
            ;;
        *)
            if [[ $key =~ ^[0-9]{8}$ ]]; then
                eventdate="$key"
            elif [[ -d $key ]]; then
                WORKDIR=$key
                lastdir=$(basename $WORKDIR)
                if [[ $lastdir =~ ^[0-9]{8}$ ]]; then
                    eventstr=${lastdir}
                    WORKDIR=${WORKDIR%%/$lastdir}
                    eventdate=${eventstr:0:8}
                fi

                #echo $WORKDIR,${jobs[*]},$eventdate,$eventtime
            else
                 echo ""
                 echo "ERROR: unknown argument, get [$key]."
                 usage 3
            fi
            ;;
    esac
    shift # past argument or value
done

if [[ $init_dir != false ]]; then
    jobs=( "${jobs[@]/ungrib}" )          # drop ungrib from the jobs list
fi

#-----------------------------------------------------------------------
#
# Platform specific initialization
#
#-----------------------------------------------------------------------
#% PLATFORM

mach="slurm"

if [[ $machine == "Jet" ]]; then
    partition="ujet,tjet,xjet,vjet,kjet"
    claim_cpu_ics="--cpus-per-task=2"

    mach="slurm"
    job_exclusive_str="#SBATCH --exclusive"
    job_account_str="#SBATCH -A ${hpcaccount-wof}"
    job_runmpexe_str="srun"
    job_runexe_str="srun"

    modulename="build_jet_intel18_1.11_smiol"
    WPSGEOG_PATH="/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/WPS_GEOG/"

    source /etc/profile.d/modules.sh
    module purge
    module use ${rootdir}/modules
    module load $modulename
    module load wgrib2/2.0.8
    wgrib2path="/apps/wgrib2/2.0.8/intel/18.0.5.274/bin/wgrib2"

elif [[ $machine == "Cheyenne" ]]; then

    if [[ $dorun == true ]]; then
        runcmd="qsub"
    fi
    ncores_ics=32; ncores_fcst=32; ncores_post=32
    partition="regular"        ; claim_cpu_ics="ncpus=${ncores_ics}"

    mach="pbs"
    job_exclusive_str=""
    job_account_str="#PBS -A ${hpcaccount-NMMM0013}"
    job_runmpexe_str="mpiexec_mpt"
    job_runexe_str="mpiexec_mpt"

    modulename="defaults"
    WPSGEOG_PATH="/glade/work/ywang/WPS_GEOG/"
    wgrib2path="wgrib2_not_found"

else    # Vecna at NSSL

    account="${hpcaccount-batch}"
    ncores_ics=96; ncores_fcst=96; ncores_post=24
    partition="batch"
    claim_cpu_ics="--ntasks-per-node=${ncores_ics} --mem-per-cpu=4G"

    mach="slurm"
    job_exclusive_str=""
    job_account_str=""
    job_runmpexe_str="srun --mpi=pmi2"
    job_runexe_str="srun"

    modulename="env.mpas_smiol"
    source ${modulename}
    WPSGEOG_PATH="/scratch/ywang/MPAS/WPS_GEOG/"
    wgrib2path="/scratch/ywang/tools/hpc-stack/intel-2021.8.0/wgrib2/2.0.8/bin/wgrib2"
fi

MPASLSM='ruc'
MPASNFLS=9

EXTINVL=3
EXTINVL_STR="${EXTINVL}:00:00"

ICSIOTYPE="pnetcdf,cdf5"

source $scpdir/Common_Utilfuncs.sh

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#
# Perform each task
#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#% ENTRY

echo "---- Jobs ($$) started $(date +%m-%d_%H:%M:%S) on host $(hostname) ----"
echo "     Event date : $eventdate ${eventtime}:00"
echo "     Root    dir: $rootdir"
echo "     Working dir: $WORKDIR"
echo "     Domain name: $domname"
echo " "

starttime_str=$(date -d "$eventdate ${eventtime}:00" +%Y-%m-%d_%H:%M:%S)
stoptime_str=$(date -d "$eventdate  ${eventtime}:00" +%Y-%m-%d_%H:%M:%S)

rundir="$WORKDIR/${eventdate}"

if [[ ! -d $rundir ]]; then
    mkdir -p $rundir
fi

jobname="${eventdate:4:4}"

exedir="$rootdir/exec"

declare -A jobargs=([ungrib]="$hrrr_dir $hrrr_time"                     \
                    [init]="init/ungrib/done.ungrib $domname/done.static" \
                    [clean]="ungrib init"                               \
                   )

for job in ${jobs[@]}; do
    if [[ $verb -eq 1 ]]; then
        echo " "
        echo "run_$job ${jobargs[$job]}"
    fi

    run_$job ${jobargs[$job]}
done

echo " "
echo "==== Jobs done $(date +%m-%d_%H:%M:%S) ===="
echo " "

exit 0