#!/bin/bash
# shellcheck disable=SC2317,SC1091,SC1090,SC2086,SC2154,SC2329

#rootdir="/scratch/ywang/MPAS/mpas_runscripts"
scpdir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
rootdir=$(realpath "$(dirname "${scpdir}")")

mpasworkdir="/scratch/wofs_mpas"     # platform dependent, it is set in Site_Runtime.sh

eventdateDF=$(date -u +%Y%m%d)

#-----------------------------------------------------------------------
#
# This is the 2nd step of th WOFS-MPAS workflow. It run program ungrib.exe
# & init_atmosphere_model to generate initial condition for all ensemble members.
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
#  Use an existing domain (wofs_mpas)
#
#     0. It should be run after "setup_mpas-wofs.sh"
#     1. make_ics.sh [YYYYmmddHH] [run_dirs] [jobnames]
#
#-----------------------------------------------------------------------

function usage {
    echo " "
    echo "    USAGE: $0 [options] DATETIME [WORKDIR] [JOBS]"
    echo " "
    echo "    PURPOSE: Make initial ensemble files before the MPAS-WOFS DA cycles"
    echo " "
    echo "    DATETIME - Case date and time as YYYYmmdd, Default for today use default intialization time 1500."
    echo "               Or use YYYYmmddHHMM as the intialization date and time."
    echo "    WORKDIR  - Run Directory"
    echo "    JOBS     - One or more jobs from [ungrib,init,clean,cleanungrib]"
    echo "               Default all jobs in sequence"
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
    echo "              -m  Machine         Machine name to run on, [Jet, Cheyenne, Vecna]."
    echo "              -a                  Clean \"ungrib\" subdirectory"
    echo "              -f conf_file        Configuration file for this case. Default: \${WORKDIR}/config.\${eventdate}"
    echo " "
    echo "   DEFAULTS:"
    echo "              eventdt = ${eventdateDF}"
    echo "              rootdir = ${rootdir}"
    echo "              WORKDIR = ${mpasworkdir}/run_dirs"
    echo " "
    echo "                                     -- By Y. Wang (2023.05.25)"
    echo " "
    exit "$1"
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

        case ${key} in
            -h)
                usage 0
                ;;
            -n)
                args["dorun"]=false
                ;;
            -v)
                args["verbose"]=true
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
                if [[ ${2^^} == "URSA" ]]; then
                    args["machine"]=Ursa
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
            -*)
                echo -e "${RED}ERROR${NC}: Unknown option: ${PURPLE}${key}${NC}"
                usage 2
                ;;
            ungrib* | init* | clean* )
                args["jobs"]="${key//,/ }"
                ;;
            *)
                if [[ ${key} =~ ^[0-9]{12}$ ]]; then
                    args["eventdate"]=${key:0:8}
                    args["eventtime"]=${key:8:4}
                elif [[ ${key} =~ ^[0-9]{8}$ ]]; then
                    args["eventdate"]="${key}"
                elif [[ -d ${key} ]]; then
                    args["WORKDIR"]="${key}"
                elif [[ -f ${key} ]]; then
                    args["config_file"]="${key}"
                else
                    echo  -e "${RED}ERROR${NC}: unknown argument, get ${PURPLE}${key}${NC}."
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

    wrkdir=${rundir}/init/ungrib
    mkwrkdir "${wrkdir}" 0
    cd "${wrkdir}" || return

    if [[ -f running.ungrib || -f done.ungrib || -f queue.ungrib ]]; then
        return 0                   # skip
    else
        [[ ${#gribtime} -eq 2 ]] && gribinit=$((gribtime*100)) || gribinit=${gribtime}
        starthr=$(((eventtime-gribinit)/100))
        hstr=$(printf "%02d" "${starthr}")

        jobarrays=()
        # shellcheck disable=SC2154
        mecho0 "GRIB files from ${grib_dir}:"
        for mem in $(seq 1 "${config_nensics}"); do
            memstr=$(printf "%02d" "${mem}")
            if [[ ${config_hrrr_subdir} == "pgrb2ap5" ]]; then
                gribfilename="gefs.${eventdate}/${gribtime}/${config_hrrr_subdir}/gep${memstr}.t${gribtime}z.pgrb2a.0p50.f0${hstr}"
                gribfilename2="gefs.${eventdate}/${gribtime}/${config_hrrr_subdir/pgrb2ap5/pgrb2bp5}/gep${memstr}.t${gribtime}z.pgrb2b.0p50.f0${hstr}"
            else
                gribfilename="${eventdate}/${gribtime}/${config_hrrr_subdir}${memstr}/wrfnat_hrrre_newse_mem00${memstr}_${hstr}.grib2"
                #gribfilename="${eventdate}${gribtime}/${config_hrrr_subdir}${mem}/gep${memstr}.t${gribtime}z.pgrb2.0p50.f0${hstr}"
            fi
            gribfile="${grib_dir}/${gribfilename}"

            mecho0 "mem ${memstr} GRIB file: ${gribfilename}"
            while [[ ! -f ${gribfile} ]]; do
                if [[ ${verbose} == true ]]; then
                    mecho0 "Waiting for ${gribfilename} ..."
                fi
                sleep 10
            done

            mywrkdir="${wrkdir}/ungrib_${memstr}"
            mkwrkdir "${mywrkdir}" 1
            cd "${mywrkdir}" || return

            if [[ -n ${gribfilename2} ]]; then
                cp "${gribfile}" GRIBFILE.AAA
                cat "${grib_dir}/${gribfilename2}" >> GRIBFILE.AAA
            else
                ln -sf "${gribfile}" GRIBFILE.AAA
            fi
             # shellcheck disable=SC2154
            ln -sf "${config_FIXDIR}/WRFV4.0/${config_hrrrvtable}" Vtable

            cat << EOF > namelist.wps
&share
  wrf_core = 'ARW',
  max_dom = 1,
  start_date = '${starttime_str}',
  end_date = '${starttime_str}',
  interval_seconds = ${config_EXTINVL}
  io_form_geogrid = 2,
/
&geogrid
/
&ungrib
  out_format = 'WPS',
  prefix = '${config_EXTHEAD}${memstr}',
/
&metgrid
/
EOF
            jobarrays+=("${mem}")
        done

        #
        # Create job script and submit it
        #
        cd ${wrkdir} || return

        # shellcheck disable=SC2154
        if [[ ${#jobarrays[@]} -gt 0 ]]; then
            jobscript="run_ungrib.${mach}"
            jobarraystr=$(get_jobarray_str "${mach}" "${jobarrays[@]}")

            declare -A jobParms=(
                [PARTION]="${config_partition_ics}"
                [JOBNAME]="ungrb_${jobname}"
                [CPUSPEC]="${config_claim_cpu_ungrib}"
                [PREFIX]="${config_EXTHEAD}"
            )
            submit_a_job "${wrkdir}" "ungrib" "jobParms" "${config_TEMPDIR}/run_ungrib_array.${mach}" "${jobscript}" "${jobarraystr}"
        fi
    fi

    if [[ ${dorun} == true && ${jobwait} -eq 1 ]]; then
        #jobname=$1 mywrkdir=$2 donenum=$3 myjobscript=$4 numtries=${5-1}
        check_job_status "ungrib" "${wrkdir}" "${config_nensics}" "${jobscript}" 2
    fi
}

########################################################################

function create_namelist {
    local scheme=$1
    local filename=$2

    if [[ "${scheme}" == "GSL" ]]; then
        cat << EOF_GSL > "${filename}"
&nhyd_model
    config_init_case = 7
    config_start_time = '${starttime_str}'
    config_stop_time = '${stoptime_str}'
    config_theta_adv_order = 3
    config_coef_3rd_order = 0.25
/
&dimensions
    config_nvertlevels   = ${nvertlevels}
    config_nsoillevels   = ${config_MPASNFLS}
    config_nfglevels     = ${config_EXTNFGL}
    config_nfgsoillevels = ${config_EXTNFLS}
    config_nsoilcat      = 16
    config_nvegopt       = 2
/
&data_sources
    config_geog_data_path = '${config_WPSGEOG_PATH}'
    config_met_prefix = '${config_EXTHEAD}${memstr}'
    config_sfc_prefix = 'SST'
    config_fg_interval = ${config_EXTINVL}
    config_landuse_data = 'MODIFIED_IGBP_MODIS_NOAH_15s'
    config_topo_data = 'GMTED2010'
    config_vegfrac_data = 'MODIS'
    config_albedo_data = 'MODIS'
    config_maxsnowalbedo_data = 'MODIS'
    config_supersample_factor     = 3
    config_30s_supersample_factor = 1
    config_use_spechumd = true
    config_soilcat_data = 'BNU'
/
&vertical_grid
    config_ztop = 25878.712
    config_nsmterrain = 1
    config_smooth_surfaces = true
    config_dzmin = 0.3
    config_nsm = 30
    config_tc_vertical_grid = true
    config_blend_bdy_terrain = true
    config_specified_zeta_levels = '${config_vertLevel_file}'
/
&interpolation_control
    config_extrap_airtemp = 'lapse-rate'
/
&preproc_stages
    config_static_interp         = false
    config_native_gwd_static     = false
    config_native_gwd_gsl_static = false
    config_vertical_grid = true
    config_met_interp    = true
    config_input_sst     = false
    config_frac_seaice   = true
    config_tempo_rap     = false
/
&physics
    config_tsk_seaice_threshold = 271.4
/
&io
    config_pio_num_iotasks = 0
    config_pio_stride = 1
/
&decomposition
    config_block_decomp_file_prefix = '${domname}.graph.info.part.'
/
EOF_GSL

    elif [[ "${scheme}" == "NCAR" ]]; then
        cat << EOF_NCAR > "${filename}"
&nhyd_model
    config_init_case = 7
    config_start_time = '${starttime_str}'
    config_stop_time = '${stoptime_str}'
    config_theta_adv_order = 3
    config_coef_3rd_order = 0.25
    config_interface_projection = 'layer_integral'
/
&dimensions
    config_nvertlevels   = ${nvertlevels}
    config_nsoillevels   = ${config_MPASNFLS}
    config_nfglevels     = ${config_EXTNFGL}
    config_nfgsoillevels = ${config_EXTNFLS}
/
&data_sources
    config_geog_data_path = '${config_WPSGEOG_PATH}'
    config_met_prefix = '${config_EXTHEAD}${memstr}'
    config_sfc_prefix = 'SST'
    config_fg_interval = ${config_EXTINVL}
    config_landuse_data = 'MODIFIED_IGBP_MODIS_NOAH'
    config_topo_data = 'GMTED2010'
    config_vegfrac_data = 'MODIS'
    config_albedo_data = 'MODIS'
    config_maxsnowalbedo_data = 'MODIS'
    config_supersample_factor     = 3
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
    config_specified_zeta_levels = '${config_vertLevel_file}'
/
&interpolation_control
    config_extrap_airtemp = 'linear'
/
&preproc_stages
    config_static_interp         = false
    config_vertical_grid = true
    config_met_interp    = true
    config_input_sst     = false
    config_frac_seaice   = true
/
&io
    config_pio_num_iotasks = 0
    config_pio_stride = 1
/
&decomposition
    config_block_decomp_file_prefix = '${domname}.graph.info.part.'
/
EOF_NCAR
    else
        echo -e "${RED}ERROR${NC}: Unsupported interpolation scheme, got ${PURPLE}${scheme}${NC}."
        usage 4
    fi
}

########################################################################

function create_streams {
    local scheme=$1
    local filename=$2

    if [[ "${scheme}" == "GSL" ]]; then

       cat << EOF_GSL > "${filename}"
<streams>
<immutable_stream name="input"
                  type="input"
                  filename_template="${domname}.static.nc"
                  input_interval="initial_only" />

<immutable_stream name="output"
                  type="output"
                  filename_template="none.nc"
                  packages="initial_conds"
                  output_interval="none" />

<stream name="jedi_ics"
                  type="output"
                  clobber_mode="truncate"
                  filename_template="${domname}_${memstr}.init.nc"
                  io_type="${config_ICSIOTYPE}"
                  output_interval="initial_only" >

        <stream name="output" />
        <var name="pressure" />
        <var name="pressure_p" />
        <var name="pressure_base" />
        <var name="uReconstructZonal" />
        <var name="uReconstructMeridional" />
</stream>

<immutable_stream name="surface"
                  type="output"
                  filename_template="${domname}.sfc_update.nc"
                  filename_interval="none"
                  packages="sfc_update"
                  output_interval="${EXTINVL_STR}" />

<immutable_stream name="lbc"
                  type="output"
                  filename_template="${domname}.lbc.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
                  filename_interval="output_interval"
                  packages="lbcs"
                  clobber_mode="replace_files"
                  output_interval="${EXTINVL_STR}" />

</streams>
EOF_GSL
    elif [[ "${scheme}" == "NCAR" ]]; then

       cat << EOF_NCAR > "${filename}"
<streams>
<immutable_stream name="input"
                  type="input"
                  filename_template="${domname}.static.nc"
                  input_interval="initial_only" />

<immutable_stream name="output"
                  type="output"
                  io_type="${config_ICSIOTYPE}"
                  filename_template="${domname}_${memstr}.init.nc"
                  clobber_mode="replace_files"
                  precision="single"
                  packages="initial_conds"
                  output_interval="initial_only" />

<immutable_stream name="surface"
                  type="output"
                  io_type="${config_ICSIOTYPE}"
                  filename_template="${domname}_${memstr}.sfc_update.nc"
                  clobber_mode="replace_files"
                  precision="single"
                  packages="sfc_update"
                  filename_interval="none"
                  output_interval="24:00:00"/>

<immutable_stream name="lbc"
                  type="output"
                  precision="single"
                  io_type="${config_ICSIOTYPE}"
                  filename_template="${domname}.lbc.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
                  clobber_mode="replace_files"
                  packages="lbcs"
                  filename_interval="none"
                  output_interval="none" />
</streams>
EOF_NCAR
    else
        echo -e "${RED}ERROR${NC}: Unsupported initialization scheme, got ${PURPLE}${scheme}${NC}."
        usage 4
    fi
}

########################################################################

function run_init4invariant {

    # Otherwise, run init normally for invariant stream
    conditions=()
    while [[ $# -gt 0 ]]; do
        case $1 in
        /*)
            conditions+=("$1")
            ;;
        *)
            conditions+=("${rundir}/$1")
            ;;
        esac
        shift
    done

    if [[ ${dorun} == true ]]; then
        for cond in "${conditions[@]}"; do
            rcond=$(realpath -m --relative-to "${WORKDIR}" "${cond}")
            mecho0 "Checking: ${CYAN}${rcond}${NC} ...."
            while [[ ! -e ${cond} ]]; do
                check_job_status "ungrib" "${rundir}/init/ungrib" "${config_nensics}"
                if [[ ${verbose} == true ]]; then
                    mecho0 "Waiting for file: ${CYAN}${cond}${NC}"
                fi
                sleep 10
            done
        done
    fi

    wrkdir=${rundir}/init
    if [[ -f ${wrkdir}/running.invariant || -f ${wrkdir}/done.invariant || -f ${wrkdir}/queue.invariant ]]; then
        return 0
    fi

    mkwrkdir "${wrkdir}" "${overwrite}"
    cd "${wrkdir}" || return

    mem=1      # use member 1, run once for all members
    memstr=$(printf "%02d" "${mem}")
    mywrkdir="${wrkdir}/invariant"

    mkwrkdir "${mywrkdir}" 1
    cd "${mywrkdir}" || return

    ln -sf ../ungrib/"${config_EXTHEAD}${memstr}:${starttime_str:0:13}" .
    ln -sf "${rundir}/${domname}/${domname}.static.nc" .

    if [[ ! -f ${rundir}/${domname}/${domname}.graph.info.part.${config_npeics} ]]; then
        split_graph "${config_gpmetis}" "${domname}.graph.info" "${config_npeics}" "${rundir}/${domname}" "${dorun}" "${verbose}"
    fi
    ln -sf ${rundir}/${domname}/${domname}.graph.info.part.${config_npeics} .

    cat << EOF > namelist.init_atmosphere
&nhyd_model
    config_init_case = 7
    config_start_time = '${starttime_str}'
    config_stop_time = '${stoptime_str}'
    config_theta_adv_order = 3
    config_coef_3rd_order = 0.25
/
&dimensions
    config_nvertlevels   = ${nvertlevels}
    config_nsoillevels   = ${config_MPASNFLS}
    config_nfglevels     = ${config_EXTNFGL}
    config_nfgsoillevels = ${config_EXTNFLS}
    config_nsoilcat      = 16
    config_nvegopt       = 2
/
&data_sources
    config_geog_data_path         = '${config_WPSGEOG_PATH}'
    config_met_prefix             = '${config_EXTHEAD}${memstr}'
    config_sfc_prefix             = 'SST'
    config_fg_interval            = ${config_EXTINVL}
    config_landuse_data           = 'MODIFIED_IGBP_MODIS_NOAH_15s'
    config_topo_data              = 'GMTED2010'
    config_vegfrac_data           = 'MODIS'
    config_albedo_data            = 'MODIS'
    config_maxsnowalbedo_data     = 'MODIS'
    config_supersample_factor     = 3
    config_30s_supersample_factor = 1
    config_use_spechumd           = true
    config_soilcat_data           = 'BNU'
/
&vertical_grid
    config_ztop = 25878.712
    config_nsmterrain = 1
    config_smooth_surfaces = true
    config_dzmin = 0.3
    config_nsm = 30
    config_tc_vertical_grid = true
    config_blend_bdy_terrain = true
    config_specified_zeta_levels = '${config_vertLevel_file}'
/
&interpolation_control
    config_extrap_airtemp = 'lapse-rate'
/
&preproc_stages
    config_static_interp         = false
    config_native_gwd_static     = false
    config_native_gwd_gsl_static = false
    config_vertical_grid         = true
    config_met_interp            = true
    config_input_sst             = false
    config_frac_seaice           = true
    config_tempo_rap             = false
/
&physics
    config_tsk_seaice_threshold  = 271.4
/
&io
    config_pio_num_iotasks = 0
    config_pio_stride = 1
/
&decomposition
    config_block_decomp_file_prefix = '${domname}.graph.info.part.'
/
EOF

    cat << EOF > streams.init_atmosphere
<streams>
<immutable_stream name="input"
                  type="input"
                  filename_template="${domname}.static.nc"
                  input_interval="initial_only" />

<immutable_stream name="output"
                  type="output"
                  filename_template="none.nc"
                  packages="initial_conds"
                  output_interval="none" />

<stream name="jedi_ics"
                  type="output"
                  clobber_mode="truncate"
                  filename_template="${domname}_${memstr}.init.nc"
                  io_type="${config_ICSIOTYPE}"
                  output_interval="initial_only" >

        <stream name="output" />
        <var name="pressure" />
        <var name="pressure_p" />
        <var name="pressure_base" />
        <var name="uReconstructZonal" />
        <var name="uReconstructMeridional" />
</stream>

<immutable_stream name="surface"
                  type="output"
                  filename_template="${domname}.sfc_update.nc"
                  filename_interval="none"
                  packages="sfc_update"
                  output_interval="${EXTINVL_STR}" />

<immutable_stream name="lbc"
                  type="output"
                  filename_template="${domname}.lbc.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
                  filename_interval="output_interval"
                  packages="lbcs"
                  clobber_mode="replace_files"
                  output_interval="${EXTINVL_STR}" />

</streams>
EOF
    #
    # Create job script and submit it
    #
    jobscript="run_invariant.${mach}"

    declare -A jobParms=(
        [PARTION]="${config_partition_ics}"
        [NOPART]="${config_npeics}"
        [CPUSPEC]="${config_claim_cpu_ics}"
        [JOBNAME]="invariant_${jobname}"
        [PREFIX]="${domname}"
        [RRFSDIR]="${rrfs_dir}"
    )
    # shellcheck disable=SC2154
    if [[ "${mach}" == "pbs" ]]; then
        jobParms[NNODES]="${config_nnodes_ics}"
        jobParms[NCORES]="${config_ncores_ics}"
    fi

    submit_a_job "${mywrkdir}" "invariant" "jobParms" "${config_TEMPDIR}/run_init.${mach}" "${jobscript}" ""
}

########################################################################

function run_init {
    wrkdir=${rundir}/init
    if [[ -f ${wrkdir}/done.${domname} ]]; then
        mecho0 "Job init is already done"
        ln -sf ${domname}_01.init.nc ${domname}.invariant.nc
        return 0
    fi

    if [[ -f ${wrkdir}/running.${domname} || -f ${wrkdir}/queue.${domname} ]]; then
        mecho0 "Job init is running or is already queued."
        check_job_status "${domname}" "${wrkdir}" "${config_nensics}"
        return 0
    fi

    # Otherwise, run init normally
    conditions=()
    while [[ $# -gt 0 ]]; do
        case $1 in
        /*)
            conditions+=("$1")
            ;;
        *)
            conditions+=("${rundir}/$1")
            ;;
        esac
        shift
    done

    if [[ ${dorun} == true ]]; then
        for cond in "${conditions[@]}"; do
            rcond=$(realpath -m --relative-to "${WORKDIR}" "${cond}")
            mecho0 "Checking: ${CYAN}${rcond}${NC} ...."
            while [[ ! -e ${cond} ]]; do
                check_job_status "ungrib" "${rundir}/init/ungrib" "${config_nensics}"
                if [[ ${verbose} == true ]]; then
                    mecho0 "Waiting for file: ${CYAN}${cond}${NC}"
                fi
                sleep 10
            done
        done
    fi

    mkwrkdir "${wrkdir}" "${overwrite}"
    cd "${wrkdir}" || return

    jobarrays=()
    for mem in $(seq 1 "${config_nensics}"); do
        memstr=$(printf "%02d" "${mem}")
        mywrkdir="${wrkdir}/${domname}_${memstr}"

        mkwrkdir "${mywrkdir}" 1
        cd "${mywrkdir}" || return

        ln -sf ../ungrib/"${config_EXTHEAD}${memstr}:${starttime_str:0:13}" .
        ln -sf "${rundir}/${domname}/${domname}.static.nc" .
        #ln -sf ../${domname}.invariant.nc .

        if [[ ! -f ${rundir}/${domname}/${domname}.graph.info.part.${config_npeics} ]]; then
            split_graph "${config_gpmetis}" "${domname}.graph.info" "${config_npeics}" "${rundir}/${domname}" "${dorun}" "${verbose}"
        fi
        ln -sf ${rundir}/${domname}/${domname}.graph.info.part.${config_npeics} .

        create_namelist "${config_initscheme}" namelist.init_atmosphere

        create_streams "${config_initscheme}" streams.init_atmosphere

        jobarrays+=("${mem}")
    done
    #
    # Create job script and submit it
    #
    if [[ ${#jobarrays[@]} -gt 0 ]]; then
        jobscript="run_init_${domname}.${mach}"
        jobarraystr=$(get_jobarray_str "${mach}" "${jobarrays[@]}")

        declare -A jobParms=(
            [PARTION]="${config_partition_ics}"
            [NOPART]="${config_npeics}"
            [CPUSPEC]="${config_claim_cpu_ics}"
            [JOBNAME]="init_${jobname}"
            [PREFIX]="${domname}"
            [MPASDIR]="${MPAS_DIR}"
            [MODULE]="${mpas_modulename}"
        )
        # shellcheck disable=SC2154
        if [[ "${mach}" == "pbs" ]]; then
            jobParms[NNODES]="${config_nnodes_ics}"
            # shellcheck disable=SC2034
            jobParms[NCORES]="${config_ncores_ics}"
        fi

        submit_a_job "${wrkdir}" "${domname}" "jobParms" "${config_TEMPDIR}/run_init_array.${mach}" "${jobscript}" "${jobarraystr}"
    fi

    if [[ ${dorun} == true && ${jobwait} -eq 1 ]]; then
        #jobname=$1 mywrkdir=$2 donenum=$3 myjobscript=$4 numtries=${5-1}
        check_job_status "${domname}" ${wrkdir} ${config_nensics} ${jobscript} 2
    fi
}

########################################################################

function run_clean {

    for dirname in "$@"; do
        case ${dirname} in
        ungrib )
            if "${cleanall}"; then
                cd "${rundir}/init"  || return
                rm -rf ungrib
            else
                cd "${rundir}/init/ungrib"  || return
                if [[ -e done.ungrib ]]; then
                    #jobname=$1 mywrkdir=$2 nummem=$3
                    clean_mem_runfiles "ungrib" "${rundir}/init/ungrib" "${config_nensics}"
                fi
            fi
            ;;
        init )
            cd "${rundir}/init"  || return
            #jobname=$1 mywrkdir=$2 nummem=$3
            if [[ -e done.${domname} ]]; then
                clean_mem_runfiles "${domname}" "${rundir}/init" "${config_nensics}"
            fi
            ;;
        * )
            mecho1 "ERROR: unsupported dirname = ${dirname}."
            ;;
        esac
    done
}

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#
#@ MAIN entry
#
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

source ${scpdir}/Common_Utilfuncs.sh || exit $?

#-----------------------------------------------------------------------
#
# Handle command line arguments (override default settings)
#
#-----------------------------------------------------------------------
#% ARGS

parse_args "$@"

verbose=${args["verbose"]:-false}
overwrite=${args["overwrite"]:-0}
dorun=${args["dorun"]:-true}
jobwait=${args["jobwait"]:-0}
cleanall=${args["cleanall"]:-false}

#-----------------------------------------------------------------------
#
# Get jobs to run
#
#-----------------------------------------------------------------------

[[ -v args["jobs"] ]] && read -r -a jobs <<< "${args['jobs']}" || jobs=(ungrib init clean)

#-----------------------------------------------------------------------
#
# Set up working environment
#
#-----------------------------------------------------------------------

source "${scpdir}/Site_Runtime.sh" || exit $?

setup_machine "${args['machine']}" "${rootdir}" false false

[[ ${dorun} == false ]] && runcmd="echo ${site_runcmd}" || runcmd="${site_runcmd}"
export runcmd

[[ -v args["WORKDIR"] ]] && WORKDIR=${args["WORKDIR"]} || WORKDIR="${site_workdir}"

#-----------------------------------------------------------------------
#
# Set Event Date and Time
#
#-----------------------------------------------------------------------
[[ -v args["eventdate"] ]] && eventdate="${args['eventdate']}" || eventdate="${eventdateDF}"
[[ -v args["eventtime"] ]] && eventtime="${args['eventtime']}" || eventtime="1500"

#-----------------------------------------------------------------------
#
# read configurations that is not set from command line
#
#-----------------------------------------------------------------------
if [[ -v args["config_file"] ]]; then
    config_file="${args['config_file']}"

    if [[ "${config_file}" =~ "/" ]]; then
        WORKDIR=$(realpath "$(dirname ${config_file})")
    else
        config_file="${WORKDIR}/${config_file}"
    fi
    [[ ${config_file} =~ config\.([0-9]{8}) && ! -v args["eventdate"] ]] && eventdate="${BASH_REMATCH[1]}"
else
    config_file="${WORKDIR}/config.${eventdate}"
fi

if [[ -r ${config_file} ]]; then
    echo -e "Reading case (${GREEN}${eventdate}${NC}) configuration file: ${CYAN}${config_file}${NC} ...."
else
    echo -e "${RED}ERROR${NC}: Configuration file ${CYAN}${config_file}${NC} is not found."
    echo -e "       Please run ${GREEN}setup_mpas-wofs.sh${NC} first or use ${BLUE}-h${NC} to show help."
    exit 2
fi
readconf ${config_file} COMMON init || exit $?
# get config_EXTINVL, config_domname

domname="${config_domname}"
mach="${config_mach}"

if [[ -e ${config_vertLevel_file} ]]; then
    nvertlevels=$(grep -cve '^\s*$' ${config_vertLevel_file})
    (( nvertlevels -= 1 ))
else
    echo -e "${RED}ERROR${NC}: vertLevel_file=${BLUE}${config_vertLevel_file}${NC} not exist."
    usage 1
fi

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#
# Perform each task
#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#% ENTRY

rundir="${WORKDIR}/${eventdate}"
if [[ ! -d ${rundir} ]]; then
    mkdir -p ${rundir}
fi

echo    ""
echo -e "---- Jobs (${YELLOW}$$${NC}) started at ${DARK}$(date +'%m-%d %H:%M:%S (%Z)')${NC} on host ${LIGHT_RED}$(hostname)${NC} ----\n"
echo -e "  Event  date: ${WHITE}${eventdate}${NC} ${YELLOW}${eventtime}${NC}"
echo -e "  ROOT    dir: ${rootdir}/${BROWN}scripts${NC}"
echo -e "  TEMP    dir: ${config_TEMPDIR}"
echo -e "  FIXED   dir: ${config_FIXDIR}"
echo -e "  EXEC    dir: ${config_EXEDIR}"
echo -e "  Working dir: ${WORKDIR}/${WHITE}${eventdate}/init${NC}"
echo -e "  Domain name: ${RED}${domname}${NC}; HRRRE time: ${DARK}${config_hrrr_time}${NC}; NENSIC: ${WHITE}${config_nensics}${NC}"
echo    " "

jobname="${eventdate:4:4}"

starttime_str=$(date -u -d "${eventdate} ${eventtime}" +%Y-%m-%d_%H:%M:%S)
stoptime_str=$(date  -u -d "${eventdate} ${eventtime}" +%Y-%m-%d_%H:%M:%S)

EXTINVL_STR=$(printf "%02d:00:00" $((config_EXTINVL/3600)) )

#
# Start to execute each procedue
#
declare -A jobargs=([ungrib]="${config_hrrr_dir} ${config_hrrr_time}"               \
                    [ungrib_gefs]="${config_hrrr_dir} ${config_hrrr_time}"          \
                    [init4invariant]="init/ungrib/done.ungrib ${domname}/done.static" \
                    [init]="init/ungrib/done.ungrib ${domname}/done.static"           \
                    [clean]="ungrib init"                               \
                    [cleanungrib]=""
                   )

for job in "${jobs[@]}"; do
    if [[ ${verbose} == true ]]; then
        echo " "
        echo "    run_${job} ${jobargs[${job}]}"
    fi

    run_${job} ${jobargs[${job}]}
done

echo -e "\n==== Jobs done ${DARK}$(date +'%m-%d %H:%M:%S (%Z)')${NC} ====\n"

exit 0
