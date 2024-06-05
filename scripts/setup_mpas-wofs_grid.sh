#!/bin/bash
# shellcheck disable=SC2317,SC1090,SC1091,SC2086

#rootdir="/scratch/ywang/MPAS/mpas_runscripts"
scpdir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
rootdir=$(realpath "$(dirname "$scpdir")")

eventdateDF=$(date -u +%Y%m%d)

#-----------------------------------------------------------------------
#
# This is the 1st step of the WOFS-MPAS workflow. It sets up a WOFS grid
# for the MPAS model based on the grid central lat/lon. The MPAS grid will
# based on a fixed WRF grid generated with program geogrid.exe.
#
# Note that the WRF-WOFS grid is fixed currently with nx=301 & ny=301
#
# Required packages must be linked in ROOTDIR
#
# 1. MPAS-Limited-Area                  https://github.com/MPAS-Dev/MPAS-Limited-Area.git
#
# Required files from ROOTDIR
#
# 0. module files in modules
#     build_jet_Rocky8_intel_smiol
#
# 1. exec                                   # The executables
#     init_atmosphere_model
#     geogrid.exe
#     ungrib.exe
#
# 2. templates                              # templates used with this scripts
#    README
#
#    2.1 SLURM scripts on Jet
#        run_static.slurm
#        run_geogrid.slurm
#        run_createWOFS.slurm
#        run_ungrib.slurm
#
# 3. fix_files                              # static files
#
#    3.1 WPS run-time files for program geogrid
#        WRFV4.0/GEOGRID.TBL.ARW
#        WRFV4.0/Vtable.raphrrr
#        WRFV4.0/Vtable.HRRRE.2018
#
#    3.2 The global 3-km mesh grid
#        *x1.65536002.grid.nc
#        *WOFSdomain.grid.nc
#
# 4. scripts                                # this scripts
#    4.1 setup_mpas-wofs_grid.sh
#
# 5. /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/WPS_GEOG*
#
#    NOTE: It can be anywhere, but should modify "run_geogrid"
#          and "run_static" below whenever the directory is changed.
#
#         * not in the git repository
#
# INSTRUCTIONS:
#
#     1. Copy these directories to rootdir (or clone using git)
#        modules
#        exec
#        scripts
#        templates
#        fix_files
#
#     2. make a run directory under rootdir
#        run_dirs
#
#     3. setup_mpas-wofs_grid.sh [YYYYmmddHHMM] [run_dirs] [jobnames]
#
#-----------------------------------------------------------------------

function usage {
    echo " "
    echo "    USAGE: $0 [options] DATETIME [WORKDIR] [JOBS]"
    echo " "
    echo "    PURPOSE: Set up a MPAS-WOFS grid based on the central lat/lon."
    echo " "
    echo "    DATETIME - Case date and time in YYYYmmddHHMM, Default for today"
    echo "    WORKDIR  - Run Directory"
    echo "    JOBS     - One or more jobs from [geogrid,ungrib_hrrr,rotate,meshplot_py,static,createWOFS,meshplot_ncl,clean] or [check,setup]."
    echo "               setup - just write set up configuration file"
    echo "               check - Check the availability of the HRRRE datasets"
    echo "               Default all jobs in the proper order."
    echo " "
    echo "    OPTIONS:"
    echo "              -h              Display this message"
    echo "              -n              Show command to be run and generate job scripts only"
    echo "              -v              Verbose mode"
    echo "              -k  [0,1,2]     Keep working directory if exist, 0- keep as is; 1- overwrite; 2- make a backup as xxxx.bak?"
    echo "                              Default is 0 for ungrib, mpassit, upp and 1 for others"
    echo "              -t  DIR         Template directory for runtime files"
    echo "              -m  Machine     Machine name to run on, [Jet, Cheyenne, Vecna]."
    echo "              -a  wof         Account name for job submission."
    echo "              -M  restart     DA cycles mode, either init or restart. default: restart"
    echo "              -c  lat,lon     Domain central lat/lon, for example, 43.33296,-84.24593"
    echo "              -d  domname     Domain name, default: wofs_mpas"
    echo "              -x  affix       Affix attached to the run directory \"dacycles\" or \"fcst\". Default: Null"
    echo "              -l  L60.txt     Vertical level file"
    echo "              -o  filename    Ouput file name of the configuration file for this case"
    echo "                              Default: $WORKDIR/config.${eventdate}"
    echo " "
    echo "   DEFAULTS:"
    echo "              eventdt = ${eventdate}"
    echo "              rootdir = $rootdir"
    echo "              WORKDIR = ${WORKDIR}"
    echo "              TEMPDIR = $rootdir/templates"
    echo "              FIXDIR  = $rootdir/fix_files"
    echo " "
    echo "                                     -- By Y. Wang (2023.05.24)"
    echo " "
    exit "$1"
}

########################################################################
#
# Extract WRF domain attributes
#
function ncattget {
  ${nckspath} -x -M "$1" | grep -E "(corner_lats|corner_lons|CEN_LAT|CEN_LON)"
}

########################################################################

function run_geogrid {

    wrkdir=$1
    mkwrkdir "$wrkdir" "$overwrite"
    cd "$wrkdir" || return

    if [[ -f done.geogrid ]]; then
        mecho0 "Found file ${CYAN}done.geogrid${NC}, skipping ${WHITE}run_geogrid${NC} ...."
        return
    fi

    if ! [[ $cen_lat && $cen_lon ]]; then
        mecho0 "${RED}ERROR${NC}: Domain center is required as command line option ${BLUE}-c lat,lon${NC}."
        exit 0
    fi

    local nx ny dx dy trulats geoname sedfile
    nx="301"
    ny="301"
    dx="3000.0"
    dy="3000.0"
    trulats=("30.0" "60.0")

    ln -sf ${FIXDIR}/WRFV4.0/GEOGRID.TBL.ARW GEOGRID.TBL

    cat <<EOF > namelist.wps
&share
  wrf_core = 'ARW',
  max_dom = 1,
  start_date = '${starttime_str}',
  end_date = '${starttime_str}',
  interval_seconds = 3600,
  io_form_geogrid = 2,
  opt_output_from_geogrid_path = './',
/

&geogrid
  parent_id = 1,
  parent_grid_ratio = 1,
  i_parent_start = 1,
  j_parent_start = 1,
  e_we = $nx,
  e_sn = $ny,
  geog_data_res = 'modis_lakes+15s+modis_fpar+modis_lai+30s',
  dx = $dx,
  dy = $dy,
  map_proj = 'lambert',
  ref_lat = ${cen_lat},
  ref_lon = ${cen_lon},
  truelat1 = ${trulats[0]},
  truelat2 = ${trulats[1]},
  stand_lon = ${cen_lon}
  geog_data_path = '${WPSGEOG_PATH}',
  opt_geogrid_tbl_path = './',
/

&ungrib
/

&metgrid
/
EOF

    cat <<EOF > ${domname}_output.json
# ${domname} Output grid specification for \"mpasgrid_cartopy.py\" to plot it
{
    'ctrlat'  : ${cen_lat},
    'ctrlon'  : ${cen_lon},
    'stdlat1' : ${trulats[0]},
    'stdlat2' : ${trulats[1]},
    'nx'      : $nx,
    'ny'      : $ny,
    'dx'      : $dx,
    'dy'      : $dy
}
EOF

    #
    # Create job script and submit it
    #
    geoname="geogrid_${jobname}"
    jobscript="run_geogrid.slurm"

    sedfile=$(mktemp -t ${geoname}.sed_XXXX)
    cat <<EOF > $sedfile
s/PARTION/${partition_wps}/
s/NOPART/$npestatic/
s/ACCTSTR/${job_account_str}/
s/EXCLSTR/${job_exclusive_str}/
s/JOBNAME/${geoname}/
s/MODULE/${modulename}/
s#ROOTDIR#$rootdir#g
s#WRKDIR#$wrkdir#g
s#EXEDIR#${exedir}#
s/RUNMPCMD/${job_runmpexe_str}/
EOF
    submit_a_jobscript $wrkdir "geogrid" $sedfile $TEMPDIR/$jobscript $jobscript ""
}

########################################################################

function run_createWOFS {

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
            mecho0 "Checking: ${CYAN}$cond"${NC}
            while [[ ! -e $cond ]]; do
                if [[ $verb -eq 1 ]]; then
                    mecho0 "Waiting for file: ${CYAN}$cond"${NC}
                fi
                sleep 10
            done
        done
    fi

    wrkdir="$rundir/$domname"
    mkwrkdir $wrkdir $overwrite
    cd $wrkdir || return

    if [[ -f done.create ]]; then
        mecho0 "Found file ${CYAN}done.create${NC}, skipping ${WHITE}run_createWOFS${NC} ...."
        return
    elif [[ -f running.create || -f queue.create ]]; then
        return                   # skip
    fi

    local mrpythondir

    # Check MPAS-Limited-Area
    mrpythondir="$rootdir/MPAS-Limited-Area"
    if [[ ! -r $mrpythondir ]]; then
        mecho0 "MPAS-Limited-Area directory not found in ${BLUE}$mrpythondir${NC}"
        exit 0
    fi

    cp    $mrpythondir/create_region .
    cp -r $mrpythondir/limited_area .

    # Check x1.65536002.grid.nc, global 3 km mesh grid
    if [[ ! -f $FIXDIR/x1.65536002.grid.nc ]]; then
        mecho0 "File ${CYAN}x1.65536002.grid.nc${NC} not found in ${BLUE}$FIXDIR${NC}."
        exit 0
    fi
    ln -sf $FIXDIR/x1.65536002.grid.nc .

    local geofile wrfdomain wrfkey vals val keyval domelements
    # Get lat/lon ranges
    geofile=$(dirname ${conditions[0]})/geo_em.d01.nc
    wrfdomain=$(ncattget $geofile)

    # shellcheck disable=SC2206
    IFS=$'\n' domelements=($wrfdomain)
    # shellcheck disable=SC2206
    for var in "${domelements[@]}"; do
        IFS='= ' keyval=(${var%%;})
        wrfkey=${keyval[0]:1}
        vals=(${keyval[@]:1})

        #echo "${wrfkey} -> ${vals[@]}"

        case $wrfkey in
        CEN_LAT | CEN_LON)
            newval=${vals[0]%%f}
            declare "$wrfkey=$newval"
            ;;
        corner_lats | corner_lons)
            minval=360.0
            maxval=-360.0
            for val in "${vals[@]}"; do
                newval=${val%%f*}
                if (( $(echo "$newval > $maxval" | bc -l) )); then
                    maxval=$newval
                fi

                if (( $(echo "$newval < $minval" | bc -l) )); then
                    minval=$newval
                fi
            done
            declare "${wrfkey}_min=$minval"
            declare "${wrfkey}_max=$maxval"
            ;;
        *)
            continue
            ;;
      esac
    done
    #echo $CEN_LAT
    #echo $CEN_LON
    #echo $corner_lats_min, $corner_lats_max
    #echo $corner_lons_min, $corner_lons_max
    #exit 0

    # shellcheck disable=SC2154
    lat_s=$(echo "$corner_lats_min-0.2" | bc -l)
    # shellcheck disable=SC2154
    lat_n=$(echo "$corner_lats_max+0.2" | bc -l)
    # shellcheck disable=SC2154
    lon_sw=$(echo "$corner_lons_min+0.5" | bc -l)
    lon_nw=$(echo "$corner_lons_min-0.2" | bc -l)
    # shellcheck disable=SC2154
    lon_ne=$(echo "$corner_lons_max+0.2" | bc -l)
    lon_se=$(echo "$corner_lons_max-0.5" | bc -l)

    # shellcheck disable=SC2153
    cat <<EOF > $domname.custom.pts
Name: $domname
Type: custom
Point: $CEN_LAT, $CEN_LON
$lat_n, $lon_nw
$lat_n, $lon_ne
$lat_s, $lon_se
$lat_s, $lon_sw
EOF

    #
    # Create job script and submit it
    #
    jobscript="run_createWOFS.slurm"

    sedfile=$(mktemp -t createWOFS.sed_XXXX)
    cat <<EOF > $sedfile
s/PARTION/${partition_create}/
s/CPUSPEC/${claim_cpu_create}/
s/ACCTSTR/${job_account_str}/
s/EXCLSTR/${job_exclusive_str}/
s/JOBNAME/createWOFS/
s#WRKDIR#$wrkdir#g
s#EXEDIR#${exedir}#
s/RUNMPCMD/${job_runmpexe_str}/
EOF
    submit_a_jobscript $wrkdir "create" $sedfile $TEMPDIR/$jobscript $jobscript ""
}

########################################################################

function run_static {

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
            mecho0 "Checking: ${CYAN}$cond"${NC}
            while [[ ! -e $cond ]]; do
                if [[ $verb -eq 1 ]]; then
                    mecho0 "Waiting for file: ${CYAN}$cond"${NC}
                fi
                sleep 10
            done
        done
    fi

    wrkdir=$rundir/$domname
    mkwrkdir $wrkdir $overwrite
    cd $wrkdir || return

    if [[ -f done.static ]]; then
        mecho0 "Found file ${CYAN}done.static${NC}, skipping ${WHITE}run_static${NC} ...."
        return
    elif [[ -f running.static || -f queue.static ]]; then
        return                   # skip
    fi

    if [[ ! -f $domname.graph.info.part.${npestatic} ]]; then
        if [[ $verb -eq 1 ]]; then
            mecho0 "Generating ${CYAN}${domname}.graph.info.part.${npestatic}${NC} in ${BROWN}${wrkdir##"$WORKDIR"/}${NC} using ${GREEN}${gpmetis}${NC}."
        fi
        ${gpmetis} -minconn -contig -niter=200 ${domname}.graph.info ${npestatic} > gpmetis.out$npestatic
        estatus=$?
        if [[ ${estatus} -ne 0 ]]; then
            mecho0 "${estatus}: ${gpmetis} -minconn -contig -niter=200 ${domname}.graph.info ${npestatic}"
            exit ${estatus}
        fi
    fi

    # The program needs a time string in file $domname.grid.nc
    #
    inittime_str=$(date -u  -d "${eventdate} ${eventtime}" +%Y-%m-%d_%H)
    starttime_str=$(date -u -d "${eventdate} ${eventtime}" +%Y-%m-%d_%H:%M:%S)

    initfile="../ungrib/${EXTHEAD}:$inittime_str"
    if [[ ! -f $initfile ]]; then
        mecho0 "Initial file (for extracting time): $initfile not found"
        exit 0
    fi
    ln -sf $initfile .

    cat <<EOF > namelist.init_atmosphere
&nhyd_model
    config_init_case = 7
    config_start_time = '${starttime_str}'
    config_stop_time = '${starttime_str}'
    config_theta_adv_order = 3
    config_coef_3rd_order = 0.25
/
&dimensions
    config_nvertlevels   = 1
    config_nsoillevels   = 1
    config_nfglevels     = 1
    config_nfgsoillevels = 1
    config_nsoilcat      = 16

/
&data_sources
    config_geog_data_path = '${WPSGEOG_PATH}'
    config_met_prefix = '${EXTHEAD}'
    config_sfc_prefix = 'SST'
    config_fg_interval = ${EXTINVL}
    config_landuse_data = 'MODIFIED_IGBP_MODIS_NOAH_15s'
    config_soilcat_data = 'BNU'
    config_topo_data = 'GMTED2010'
    config_vegfrac_data = 'MODIS'
    config_albedo_data = 'MODIS'
    config_maxsnowalbedo_data = 'MODIS'
    config_lai_data = 'MODIS'
    config_supersample_factor = 1
    config_use_spechumd = false
/
&vertical_grid
    config_ztop = 25878.712
    config_nsmterrain = 1
    config_smooth_surfaces = true
    config_dzmin = 0.3
    config_nsm = 30
    config_tc_vertical_grid = false
    config_blend_bdy_terrain = false
    config_specified_zeta_levels = '${fixed_level}'
/
&interpolation_control
    config_extrap_airtemp = 'linear'
/
&preproc_stages
    config_static_interp = true
    config_native_gwd_static = true
    config_vertical_grid = false
    config_met_interp = false
    config_input_sst = false
    config_frac_seaice = false
/
&io
    config_pio_num_iotasks = 0
    config_pio_stride = 1
/
&decomposition
    config_block_decomp_file_prefix = '${domname}.graph.info.part.'
/
EOF

    cat << EOF >  streams.init_atmosphere
<streams>
<immutable_stream name="input"
                  type="input"
                  io_type="${STATICIOTYPE}"
                  filename_template="${domname}.grid.nc"
                  input_interval="initial_only" />

<immutable_stream name="output"
                  type="output"
                  filename_template="${domname}.static.nc"
                  io_type="${STATICIOTYPE}"
                  packages="initial_conds"
                  clobber_mode="replace_files"
                  output_interval="initial_only" />

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
                  output_interval="${EXTINVL_STR}" />

</streams>
EOF

    #
    # Create job script and submit it
    #
    jobscript="run_static.${mach}"

    sedfile=$(mktemp -t static_${jobname}.sed_XXXX)
    cat <<EOF > $sedfile
s/PARTION/${partition_static}/
s/NOPART/$npestatic/
s/JOBNAME/static_${jobname}/
s/CPUSPEC/${claim_cpu_static}/
s/MODULE/${modulename}/
s/MACHINE/${machine}/g
s#ROOTDIR#$rootdir#g
s#WRKDIR#$wrkdir#g
s#EXEDIR#${exedir}#
s/ACCTSTR/${job_account_str}/
s/EXCLSTR/${job_exclusive_str}/
s/RUNMPCMD/${job_runmpexe_str}/
EOF
    submit_a_jobscript $wrkdir "static" $sedfile $TEMPDIR/$jobscript $jobscript ""
}

########################################################################

function run_rotate {

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
            mecho0 "Checking: ${CYAN}$cond"${NC}
            while [[ ! -e $cond ]]; do
                if [[ $verb -eq 1 ]]; then
                    mecho0 "Waiting for file: ${CYAN}$cond"${NC}
                fi
                sleep 10
            done
        done
    fi

    wrkdir="$rundir/$domname"
    mkwrkdir $wrkdir $overwrite
    cd $wrkdir || return

    if [[ -f done.rotate ]]; then
        mecho0 "Found file ${CYAN}done.rotate${NC}, skipping ${WHITE}run_rotate${NC} ...."
        return
    elif [[ -f running.rotate || -f queue.rotate ]]; then
        return                   # skip
    fi

    local geofile wrfdomain wrfkey vals val keyval domelements
    # Get lat/lon ranges
    geofile=$(dirname ${conditions[0]})/geo_em.d01.nc
    wrfdomain=$(ncattget $geofile)

    # shellcheck disable=SC2206
    IFS=$'\n' domelements=($wrfdomain)
    # shellcheck disable=SC2206
    for var in "${domelements[@]}"; do
        IFS='= ' keyval=(${var%%;})
        wrfkey=${keyval[0]:1}
        vals=(${keyval[@]:1})

        #echo "${wrfkey} -> ${vals[@]}"

        case $wrfkey in
        CEN_LAT | CEN_LON)
            newval=${vals[0]%%f}
            declare "$wrfkey=$newval"
            ;;
        corner_lats | corner_lons)
            minval=360.0
            maxval=-360.0
            for val in "${vals[@]}"; do
                newval=${val%%f*}
                if (( $(echo "$newval > $maxval" | bc -l) )); then
                    maxval=$newval
                fi

                if (( $(echo "$newval < $minval" | bc -l) )); then
                    minval=$newval
                fi
            done
            declare "${wrfkey}_min=$minval"
            declare "${wrfkey}_max=$maxval"
            ;;
        *)
            continue
            ;;
      esac
    done
    #echo $CEN_LAT
    #echo $CEN_LON
    #echo $corner_lats_min, $corner_lats_max
    #echo $corner_lons_min, $corner_lons_max
    #exit 0

    #ang_rotate=$(echo $CEN_LON - -84.24591 | bc -l)
    ang_rotate="0.0"
    ln -sf ${FIXDIR}/WOFSdomain.grid.nc input_filename.nc
    ln -sf ${FIXDIR}/WOFSdomain.graph.info ${domname}.graph.info

    cat <<EOF > namelist.input
&input
   config_original_latitude_degrees =    43.33296
   config_original_longitude_degrees =  -84.24591

   config_new_latitude_degrees =   $CEN_LAT
   config_new_longitude_degrees =  $CEN_LON
   config_birdseye_rotation_counter_clockwise_degrees = ${ang_rotate}
/
EOF

    #
    # Create job script and submit it
    #
    jobscript="run_rotate.slurm"

    sedfile=$(mktemp -t grid_rotate.sed_XXXX)
    cat <<EOF > $sedfile
s/PARTION/${partition_static}/
s/CPUSPEC/${claim_cpu_static}/
s/ACCTSTR/${job_account_str}/
s/EXCLSTR/${job_exclusive_str}/
s/JOBNAME/grid_rotate/
s/DOMNAME/${domname}/
s/MODULE/${modulename}/g
s#ROOTDIR#$rootdir#g
s#WRKDIR#$wrkdir#g
s#EXEDIR#${exedir}#
s/RUNCMD/${job_runexe_str}/
EOF
    submit_a_jobscript $wrkdir "rotate" $sedfile $TEMPDIR/$jobscript $jobscript ""
}

########################################################################

function run_ungrib_hrrr {
    if [[ $# -ne 1 ]]; then
        mecho0 "${RED}ERROR${NC}: ${BROWN}run_ungrib${NC} require ${YELLOW}1${NC} arguments."
        exit 2
    fi
    hrrr_grib_dir=$1

    wrkdir=$rundir/ungrib
    mkwrkdir $wrkdir 0
    cd $wrkdir || return

    if [[ -f done.ungrib ]]; then
        mecho0 "Found file ${CYAN}done.ungrib${NC}, skipping ${WHITE}run_ungrib_hrrr${NC} ...."
        return                   # skip
    elif [[ -f running.ungrib || -f queue.ungrib ]]; then
        return                   # skip
    fi

    h=${eventtime:0:2}
    hstr=$(printf "%02d" ${h#0})
    if [[ -f $hrrr_grib_dir ]]; then
        hrrrfile=$hrrr_grib_dir
    else
        julday=$(date -u -d "${eventdate} ${eventtime}" +%y%j%H)
        hrrrbase="${julday}0000"
        hrrrfile="$hrrr_grib_dir/${hrrrbase}$hstr"
    fi
    basefn=$(basename $hrrrfile)
    basefn="NSSL_$basefn"

    if [[ $verb -eq 1 ]]; then mecho0 "HRRR file: ${BLUE}$hrrrfile${NC}"; fi
    while [[ ! -f $hrrrfile && ! -f $basefn ]]; do
        if [[ $verb -eq 1 ]]; then
            mecho0 "Waiting for $hrrrfile ..."
        fi
        sleep 10
    done

    ln -sf ${hrrrfile} GRIBFILE.AAA
    ln -sf $FIXDIR/WRFV4.0/${hrrrvtable} Vtable

    hrrrtime_str=$(date -u -d "${eventdate} ${eventtime}" +%Y-%m-%d_%H:%M:%S)

    cat << EOF > namelist.wps
&share
  wrf_core = 'ARW',
  max_dom = 1,
  start_date = '${hrrrtime_str}',
  end_date = '${hrrrtime_str}',
  interval_seconds = ${EXTINVL}
  io_form_geogrid = 2,
/
&geogrid
/
&ungrib
  out_format = 'WPS',
  prefix = '${EXTHEAD}',
/
&metgrid
/
EOF

    #
    # Create job script and submit it
    #
    jobscript="run_ungrib.${mach}"

    sedfile=$(mktemp -t ungrib_hrrr_${jobname}.sed_XXXX)
    cat <<EOF > $sedfile
s/PARTION/${partition_wps}/
s/JOBNAME/ungrb_hrrr_${jobname}/
s/MODULE/${modulename}/g
s#ROOTDIR#$rootdir#g
s#WRKDIR#$wrkdir#g
s#EXEDIR#${exedir}#
s/ACCTSTR/${job_account_str}/
s/EXCLSTR/${job_exclusive_str}/
s/RUNCMD/${job_runexe_str}/
EOF
    submit_a_jobscript $wrkdir "ungrib" $sedfile $TEMPDIR/$jobscript $jobscript ""
}

########################################################################

function run_meshplot_ncl {
    # NCL version
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
            mecho0 "Checking: ${CYAN}$cond"${NC}
            while [[ ! -e $cond ]]; do
                if [[ $verb -eq 1 ]]; then
                    mecho0 "Waiting for file: ${CYAN}$cond"${NC}
                fi
                sleep 10
            done
        done
    fi

    wrkdir="$rundir/$domname"
    if [[ ! -f $wrkdir/$domname.grid.nc ]]; then
        mecho0 "Working file: $wrkdir/$domname.grid.nc not exist."
        return
    fi
    cd $wrkdir || return

    ln -sf ../geo_${domname##*_}/geo_em.d01.nc .

    #
    # Create job script and submit it
    #
    jobscript="wofs_mesh.ncl"

    sedfile=$(mktemp -t rotate_ncl.sed_XXXX)
    cat <<EOF > $sedfile
s#INPUTFILENAME#$domname.grid.nc#
s#OUTFILENAME#$domname#
s/DATESTRING/${starttime_str:0:10}/
EOF

    sed -f $sedfile $TEMPDIR/$jobscript > $jobscript
    $nclpath $jobscript

    if [[ -f $domname.png ]]; then
        mecho0 "Domain on ${starttime_str:0:10} is saved as $wrkdir/$domname.png."
    fi
}

########################################################################

function run_meshplot_py {
    # Python version also include code for the radar list within domain

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
            mecho0 "Checking: ${CYAN}$cond"${NC}
            while [[ ! -e $cond ]]; do
                if [[ $verb -eq 1 ]]; then
                    mecho0 "Waiting for file: ${CYAN}$cond"${NC}
                fi
                sleep 10
            done
        done
    fi

    wrkdir="$rundir/$domname"
    if [[ ! -f $wrkdir/$domname.grid.nc ]]; then
        mecho0 "Working file: $wrkdir/$domname.grid.nc not exist."
        return
    fi
    cd $wrkdir  || return

    if [[ -f "${domname}.radars.${eventdate}.sh" ]]; then
        mecho0 "Found file ${CYAN}${domname}.radars.${eventdate}.sh${NC}, skipping ${WHITE}run_run_meshplot_py${NC} ...."
        return
    fi

    output_grid="$(dirname $wrkdir)/geo_${domname##*_}/${domname}_output.json"

    #
    # Run job script and submit it
    #
    jobscript="${rootdir}/python/mpasgrid_cartopy.py"
    # Options:
    #
    #  -g RADAR_FILE, --radar_file RADAR_FILE
    #                        Radar file name for locations
    #  -e EVENT, --event EVENT
    #                        Event date string
    #  -name NAME            Name of the WoF grid
    #  -o OUTFILE, --outfile OUTFILE
    #                        Name of output image or output directory
    #  -latlon               Base map latlon or lambert
    #  -outgrid OUTGRID      Plot an output grid, "True", "False" or a filename.
    #                        When "True", retrieve grid from command line.
    #
    jobcmdstr="$jobscript -o $wrkdir -e ${eventdate} -name ${domname} -outgrid ${output_grid} -g ${FIXDIR}/nexrad_stations.txt ${domname}.grid.nc"
    mecho0 "Running ${BROWN}$jobcmdstr${NC}"
    python $jobcmdstr

    #ls -l ${domname}.radars.${eventdate}.sh
    #echo "Waiting for ${domname}.radars.${eventdate}.sh ...."
    #while [[ ! -e ${domname}.radars.${eventdate}.sh  ]]; do
    #    sleep 10
    #done
}

########################################################################

function run_clean {

    for dirname in "$@"; do
        case $dirname in
        geogrid )
            cd "$rundir/geo_mpas" || return

            donegeo="$rundir/geo_mpas/done.geogrid"
            if [[ -f $donegeo ]]; then
                rm -rf geogrid.log.* geogrid_*.log
                rm -rf error.geogrid queue.geogrid running.geogrid
            fi
            ;;
        createWOFS )
            if [[ -d $rundir/$domname ]]; then
                cd "$rundir/$domname" || return

                donecreate="$rundir/$domname/done.create"
                if [[ -e $donecreate ]]; then
                    rm -rf create_region limited_area create_*.log x1.65536002.grid.nc
                fi
            fi
            ;;
        static )
            if [[ -d $rundir/$domname ]]; then
                cd "$rundir/$domname" || return

                donestatic="$rundir/$domname/done.static"
                if [[ -e $donestatic ]]; then
                    rm -f log.init_atmosphere.* static_*.log  #$EXTHEAD:*
                fi
            fi
            ;;

        esac
    done
}

########################################################################

function write_runtimeconfig {
    if [[ $# -ne 1 ]]; then
        mecho0 "${RED}ERROR${NC}: No enough argument to function ${BROWN}write_runtimeconfig${NC}."
        exit 1
    fi
    local configname=$1

    if [[ -e $configname ]]; then
        mecho0  "Case configuration file: ${CYAN}$configname${NC} exist."
        mecho0n "Overwrite, [${BROWN}yes,no,skip,bak${NC}]? "
        read -r doit
        if [[ ${doit^^} == "YES" ]]; then
            mecho0 "${BROWN}WARNING${NC}: ${CYAN}$configname${NC} will be replaced."
        elif [[ ${doit^^} == "SKIP" ]]; then
            mecho0 "${BROWN}WARNING${NC}: ${CYAN}$configname${NC} will be kept. Skip ${BROWN}setup${NC}."
            return
        elif [[ ${doit^^} == "BAK" ]]; then
            datestr=$(date +%Y%m%d_%H%M%S)
            mecho0 "${BROWN}WARNING${NC}: Orignal ${CYAN}$configname${NC} is backuped as"
            mecho0 "         ${PURPLE}${configname}.bak${datestr}${NC}"
            mv ${configname} ${configname}.bak${datestr}
        else
            mecho0 "Got ${PURPLE}${doit^^}${NC}, exit the program."
            exit 1
        fi
    fi

    #-------------------------------------------------------------------
    # Machine specific setting for init, lbc, dacycles & fcst
    #-------------------------------------------------------------------

    pythonmachine=""
    case $machine in
    "Jet" )
        # ICs
        npeics=24; ncores_ics=2
        partition_ics="ujet,tjet,xjet,vjet,kjet"
        claim_cpu_ics="--cpus-per-task=2"
        claim_cpu_ungrib="--cpus-per-task=12 --mem-per-cpu=10G"

        # LBCs
        npelbc=24;  ncores_lbc=2
        partition_lbc="ujet,tjet,xjet,vjet,kjet"
        claim_cpu_lbc="--cpus-per-task=2"

        # DA cycles
        ncores_dafcst=6;  ncores_filter=6
        partition_dafcst="ujet,tjet,xjet,vjet,kjet"; claim_cpu_dafcst="--cpus-per-task=2"
        partition_filter="ujet,tjet,xjet,vjet,kjet"; claim_cpu_filter="--cpus-per-task=2"
                                                     claim_cpu_update="--cpus-per-task=1 --mem-per-cpu=8G"
        npedafcst=48        #; nnodes_fcst=$(( npefcst/ncores_fcst ))
        npefilter=1536      #; nnodes_filter=$(( npefilter/ncores_filter ))
        nnodes_filter="1"
        nnodes_dafcst="1"

        # FCST cycles
        ncores_fcst=6;  ncores_post=6
        partition_fcst="ujet,tjet,xjet,vjet,kjet";   claim_cpu_fcst="--cpus-per-task=2"
        partition_post="ujet,tjet,xjet,vjet,kjet";   claim_cpu_post="--cpus-per-task=12"

        npefcst=48     ; nnodes_fcst=$(( npefcst/ncores_fcst ))
        npepost=48     ; nnodes_post=$(( npepost/ncores_post ))
        ;;

    "Hercules" )
        # ICs
        npeics=24; ncores_ics=2
        partition_ics="batch"
        claim_cpu_ics="--cpus-per-task=2"
        claim_cpu_ungrib="--cpus-per-task=12 --mem-per-cpu=10G"

        # LBCs
        npelbc=24;  ncores_lbc=2
        partition_lbc="batch"
        claim_cpu_lbc="--cpus-per-task=2"

        # DA cycles
        ncores_dafcst=40;  ncores_filter=40
        partition_dafcst="batch"; claim_cpu_dafcst="--cpus-per-task=2"
        partition_filter="batch"; claim_cpu_filter="--cpus-per-task=2"
                                  claim_cpu_update="--cpus-per-task=1 --mem-per-cpu=8G"
        npedafcst=40       #; nnodes_fcst=$(( npefcst/ncores_fcst ))
        npefilter=160      #; nnodes_filter=$(( npefilter/ncores_filter ))
        nnodes_filter="1"
        nnodes_dafcst="1"

        # FCST cycles
        ncores_fcst=40;  ncores_post=40
        partition_fcst="batch";   claim_cpu_fcst="--cpus-per-task=2"
        partition_post="batch";   claim_cpu_post="--cpus-per-task=12"

        npefcst=40     ; nnodes_fcst=$(( npefcst/ncores_fcst ))
        npepost=40     ; nnodes_post=$(( npepost/ncores_post ))
        ;;

    "Cheyenne" )
        pythonmachine=""
        mpas_wofs_python="/glade/work/ywang/wofs_new_noise"

        # Derecho node has 128 processors
        # ICs
        npeics=32; ncores_ics=32
        partition_ics="preempt"
        claim_cpu_ics="ncpus=${ncores_ics}"
        claim_cpu_ungrib=""

        # LBCs
        npelbc=32;  ncores_lbc=32
        partition_lbc="preempt"
        claim_cpu_lbc="ncpus=${ncores_lbc}"

        # DA cycles
        ncores_filter=128; ncores_dafcst=128
        # main, preempt, regular
        partition_dafcst="preempt" ; claim_cpu_dafcst="ncpus=${ncores_dafcst}"
        partition_filter="preempt" ; claim_cpu_filter="ncpus=${ncores_filter}"
        claim_cpu_update="ncpus=${ncores_filter}"

        npefilter=128     ; nnodes_filter=$(( npefilter/ncores_filter   ))
        npedafcst=128     ; nnodes_dafcst=$(( npefcst/ncores_dafcst ))

        # FCST cycles
        ncores_post=32; ncores_fcst=128
        partition_fcst="preempt"   ; claim_cpu_fcst="ncpus=${ncores_fcst}"
        partition_post="preempt"   ; claim_cpu_post="ncpus=${ncores_post}"

        npepost=32      ; nnodes_post=$(( npepost/ncores_post   ))
        npefcst=128     ; nnodes_fcst=$(( npefcst/ncores_fcst ))
        ;;

    * )    # Vecna at NSSL

        pythonmachine=""
        mpas_wofs_python="/scratch/ywang/MPAS/wofs_new_noise"

        # ICs
        npeics=24;   ncores_ics=96
        partition_ics="batch"
        claim_cpu_ics="--ntasks-per-node=${ncores_ics}"
        claim_cpu_ungrib=""

        # LBCs
        npelbc=24;  ncores_lbc=96
        partition_lbc="batch"
        claim_cpu_lbc="--ntasks-per-node=${ncores_lbc}"
        claim_cpu_ungrib=""

        # DA cycles
        ncores_filter=96; ncores_dafcst=96

        npefilter=768           ; nnodes_filter=1
        npedafcst=56            ; nnodes_dafcst=1

        partition_dafcst="batch"  ; claim_cpu_dafcst="";
        partition_filter="batch"  ; claim_cpu_filter="--ntasks-per-node=\${ncores_filter}"
                                    claim_cpu_update="--ntasks-per-node=1 --mem-per-cpu=120G"   # 4 jobs each node

        # FCST cycles
        ncores_post=24; ncores_fcst=96
        partition_fcst="batch"      ; claim_cpu_fcst="";
        partition_post="batch"      ; claim_cpu_post=""

        npepost=24      ; nnodes_post=1
        npefcst=80      ; nnodes_fcst=1
        ;;
    esac

    #-------------------------------------------------------------------
    # Write out default configuration file
    #-------------------------------------------------------------------

    cat <<EOF > $configname
#!/bin/bash
#
# This file contains settings specifically for case $eventdate
# It does NOT contain anything that is configurable from the command line
# for each task. Use optin "-h" to check command line options.
#
# Except for comments which must start with "# " in this file, the syntax
# will be the same as a Bash shell script.
#
# [COMMON] variables
#
#   daffix:     DA & fcst cycle work directory affix, default: dacycles/fcst
#               if not empty, use dacyles.\${daffix}/fcst.\${daffix}
#   damode:     DA cycles mode, either "restart" or "init"
#
#   mpscheme:   Microphysics scheme, valid values are ('mp_nssl2m', 'Thompson')
#   sfclayer_schemes:   suite,sf_monin_obukhov_rev,sf_monin_obukhov,sf_mynn,off
#   pbl_schemes:        suite,bl_ysu,bl_myj,bl_mynn,off
#
#        Note: Please keep "sfclayer_schemes" & "pbl_schemes" to be 3-element arrays,
#              Otherwise, a script change will be needed
#
#   vertLevel_file:  File name for the vertical coordonates, works with "make_ics.sh" & "make_lbc.sh" only
#

[COMMON]
    nensics=36
    nenslbc=18
    EXTINVL=3600

    domname="${domname}"
    daffix="${affix}"
    damode="${damode}"

    MPASLSM='sf_ruc'
    MPASNFLS=9

    mpscheme='mp_nssl2m'
    sfclayer_schemes=('sf_monin_obukhov_rev' 'sf_monin_obukhov' 'sf_mynn')
    pbl_schemes=('bl_ysu' 'bl_myj' 'bl_mynn')

    vertLevel_file="${fixed_level}"

    WPSGEOG_PATH="${WPSGEOG_PATH}"

    wgrib2path="${wgrib2path}"
    gpmetis="${gpmetis}"

    mach="${mach}"
    job_exclusive_str="${job_exclusive_str}"
    job_account_str="${job_account_str}"
    job_runmpexe_str="${job_runmpexe_str}"
    job_runexe_str="${job_runexe_str}"
    runcmd_str="${runcmd_str}"

[init]
    ICSIOTYPE="pnetcdf,cdf5"
    EXTNFGL=51
    EXTNFLS=9
    EXTHEAD="HRRRE"
    hrrrvtable="${hrrrvtable}"
    hrrr_dir="${hrrr_dir}"
    hrrr_time="${hrrr_time_ics}"

    partition_ics="${partition_ics}"
    claim_cpu_ics="${claim_cpu_ics}"
    npeics="${npeics}";    ncores_ics="${ncores_ics}"
    claim_cpu_ungrib="${claim_cpu_ungrib}"

[lbc]
    LBCIOTYPE="pnetcdf,cdf5"
    EXTNFGL=51
    EXTNFLS=9
    EXTHEAD="HRRRE"
    hrrrvtable="${hrrrvtable}"
    hrrr_dir="${hrrr_dir}"
    hrrr_time="${hrrr_time_lbc}"

    npelbc="${npelbc}"; ncores_lbc="${ncores_lbc}"
    partition_lbc="${partition_lbc}"
    claim_cpu_lbc="${claim_cpu_lbc}"

[dacycles]
    ENS_SIZE=36
    time_step=15
    intvl_sec=900
    ADAPTIVE_INF=true
    update_in_place=false               # update MPAS states in-place or
                                        # making a copy of the restart files
    use_BUFR=true                       # Whether we should wait for PrepBufr data file
    use_MESO=true                       # for a realtime run
    use_CWP=true
    use_RAD=true

    run_updatebc=true                   # run mpas_update_bc
    run_obs2nc=true                     # run obs_seq_to_netcdf after filter
    run_obsdiag=true                    # run obs_diag after filter for each cycle
    run_addnoise=false                  # run WoFS add_noise facility (Python)
    run_trimvr=true                     # Trim NaNs from radial velocity observations (Python)
    python_machine="${pythonmachine}"   # if not empty, you should have set up passwordless access on it and the
                                        # Python environment is properly set in run_noise_mask.slurm & run_noise_pert.slurm
    WOFSAN_PATH="${mpas_wofs_python}"

    OUTIOTYPE="netcdf4"
    outwrf=false                        # Run MPASSIT after each data assimilation
    sampling_error_correction=".true."

    OBS_DIR="${OBS_DIR}"

    partition_fcst="${partition_dafcst}";
    partition_filter="${partition_filter}"
    npefcst="${npedafcst}";   ncores_fcst="${ncores_dafcst}";   nnodes_filter="${nnodes_filter}"
    npefilter="${npefilter}"; ncores_filter="${ncores_filter}"; nnodes_fcst="${nnodes_dafcst}"

    claim_cpu_fcst="${claim_cpu_dafcst}"
    claim_cpu_filter="${claim_cpu_filter}"
    claim_cpu_update="${claim_cpu_update}"
    claim_time_fcst="00:20:00"

    npepost="${npepost}"; claim_cpu_post=""; claim_time_mpassit_alltimes="00:30:00"

    job_exclusive_str=""
[fcst]
    ENS_SIZE=18
    time_step=20
    fcst_launch_intvl=3600
    fcst_length_seconds=(21600 10800)   # 6 hours at :00 and 3 hours at :30
    OUTINVL=300
    OUTIOTYPE="netcdf4"

    outpsfc=false                       # An extra streams for PSFC output"

    partition_fcst="${partition_fcst}"
    partition_post="${partition_post}"
    claim_cpu_fcst="${claim_cpu_fcst}"
    claim_cpu_post="${claim_cpu_post}"
    npefcst="${npefcst}";          ncores_fcst="${ncores_fcst}";  nnodes_fcst="${nnodes_fcst}"
    ncores_post="${ncores_post}";  npepost="${npepost}";          nnodes_post="${nnodes_post}"

    claim_time_fcst="01:20:00"
    claim_time_mpassit_alltimes="03:30:00"
    claim_time_mpassit_onetime="00:50:00"

    job_exclusive_str=""

EOF

}

########################################################################

function check_hrrr_files {
    #
    # Check the external grib2 files availability for providing the system ICS/LBCs
    #

    mecho0n "Checking ${CYAN}$hrrrfile${NC} ... "
    if ls $hrrrfile > /dev/null 2>&1; then
        echo -e "${GREEN}Found${NC}"
    else
        echo -e "${RED}Missing${NC}"
    fi

    mecho0 "Checking ${CYAN}${hrrr_dir}/${eventdate}/${hrrr_time_ics}${NC} .... "
    if ls ${hrrr_dir}/${eventdate}/${hrrr_time_ics} > /dev/null 2>&1; then
        echo -e "${GREEN}Found${NC}"
        for mdir in "${hrrr_dir}/${eventdate}/${hrrr_time_ics}"/postprd_mem00??; do
            if [[ -d $mdir ]]; then
                subdir=$(basename $mdir)
                fcount=("$mdir"/wrfnat_hrrre_newse_mem00??_01.grib2)
                echo -e "\t$subdir .... ${GREEN}${#fcount[@]}${NC}"
            else
                echo -e "\tMember directories ${RED}missing${NC}"
            fi
        done
    else
        echo -e "${RED}Missing${NC}"
    fi

    mecho0n "Checking ${CYAN}${hrrr_dir}/${eventdate}/${hrrr_time_lbc}${NC} .... "

    if ls ${hrrr_dir}/${eventdate}/${hrrr_time_lbc} > /dev/null 2>&1; then
        echo -e "${GREEN}Found${NC}"
        for mdir in "${hrrr_dir}/${eventdate}/${hrrr_time_lbc}"/postprd_mem00??; do
            if [[ -d $mdir ]]; then
                subdir=$(basename $mdir)
                fcount=("$mdir"/wrfnat_pert_hrrr_mem00??_??.grib2)
                echo -e "\t$subdir .... ${GREEN}${#fcount[@]}${NC}"
            else
                echo -e "\tMember directories ${RED}missing${NC}"
            fi
        done
    else
        echo -e "${RED}Missing${NC}"
    fi
}

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#
# Default settings
#
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#@ MAIN

#jobs=(geogrid ungrib_hrrr createWOFS static)
jobs=(geogrid ungrib_hrrr rotate meshplot_py static)

WORKDIR="${rootdir}/run_dirs"
TEMPDIR="${rootdir}/templates"
FIXDIR="${rootdir}/fix_files"

eventdate="$eventdateDF"
eventtime="1500"
domname="wofs_mpas"
affix=""

runcmd="sbatch"
dorun=true
verb=0
overwrite=0
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

fixed_level="${FIXDIR}/L60.txt"
damode="restart"

source "${scpdir}/Common_Utilfuncs.sh" || exit $?

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
        -k)
            if [[ $2 =~ [012] ]]; then
                overwrite=$2
                shift
            else
                echo -e "${RED}ERROR${NC}: option for ${BLUE}-k${NC} can only be [${YELLOW}0-2${NC}], but got ${PURPLE}$2${NC}."
                usage 1
            fi
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
        -M)
            if [[ ${2,,} == "init" || ${2,,} == "restart" ]]; then
                damode="${2,,}"
            else
                echo -e "${RED}ERROR${NC}: unknow argument. Expect: ${YELLOW}init${NC} or ${YELLOW}restart${NC}. Got: ${PURPLE}${2,,}${NC}"
                usage 1
            fi
            shift
            ;;
        -d)
            domname=$2
            shift
            ;;
        -x)
            affix="$2"
            shift
            ;;
        -l)
            fixed_level="${FIXDIR}/$2"
            if [[ ! -e ${fixed_level} ]]; then
                echo -e "${RED}ERROR${NC}: ${BLUE}${fixed_level}${NC} not exist."
                usage 1
            fi
            shift
            ;;
        -c)
            if [[ $2 =~ ^[0-9.]+,[0-9.-]+$ ]]; then
                #latlons=(${2//,/ })
                #mapfile -t latlons <<< "${2//,/ }"
                IFS="," read -r -a latlons <<< "$2"
                cen_lat=${latlons[0]}
                cen_lon=${latlons[1]}
            else
                echo -e "${RED}ERROR${NC}: Domain center is required as ${BLUE}-c lat,lon${NC}, get: ${PURPLE}$2${NC}."
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
            elif [[ ${2^^} == "HERCULES" ]]; then
                machine=Hercules
            else
                echo -e "${RED}ERROR${NC}: Unsupported machine name, got ${PURPLE}$2${NC}."
                usage 1
            fi
            shift
            ;;
        -a)
            hpcaccount=$2
            shift
            ;;
        -o)
            caseconfig=$2
            shift
            ;;
        -*)
            echo -e "${RED}ERROR${NC}: Unknown option: ${PURPLE}$key${NC}"
            usage 2
            ;;
        static* | geogrid* | createWOFS | meshplot* | clean* | setup | check)
            #jobs=(${key//,/ })
            IFS="," read -r -a jobs <<< "$key"
            ;;
        *)
            if [[ $key =~ ^[0-9]{8}$ ]]; then
                eventdate="$key"
            elif [[ $key =~ ^[0-9]{10}$ ]]; then
                eventdate="${key:0:8}"
                eventtime="${key:8:2}"
            elif [[ -d $key ]]; then
                WORKDIR=$key
                lastdir=$(basename $WORKDIR)
                if [[ $lastdir =~ ^[0-9]{8}$ ]]; then
                    eventstr=${lastdir}
                    WORKDIR=$(dirname ${WORKDIR})
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

#-----------------------------------------------------------------------
#
# Platform specific initialization
#
#-----------------------------------------------------------------------
#% PLATFORM

if [[ $machine == "Jet" ]]; then
    partition_wps="ujet,tjet,xjet,vjet,kjet"
    partition_static="ujet,tjet,xjet,vjet,kjet"  ; claim_cpu_static="--cpus-per-task=12"
    partition_create="bigmem"                    ; claim_cpu_create="--mem-per-cpu=128G"

    npestatic=24

    mach="slurm"
    job_exclusive_str="#SBATCH --exclusive"
    job_account_str="#SBATCH -A ${hpcaccount-wof}"
    job_runmpexe_str="srun"
    job_runexe_str="srun"
    runcmd_str=""

    modulename="build_jet_Rocky8_intel_smiol"
    WPSGEOG_PATH="/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/WPS_GEOG/"

    source /etc/profile.d/modules.sh
    module purge
    module use "${rootdir}/modules"
    module load $modulename
    #module load nco
    module load wgrib2/2.0.8
    wgrib2path="/apps/wgrib2/2.0.8/intel/18.0.5.274/bin/wgrib2"
    nckspath="/apps/nco/4.9.3/gnu/9.2.0/bin/ncks"
    gpmetis="/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/bin/gpmetis"

    OBS_DIR="/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/OBSGEN"

    hrrr_dir="/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/MODEL_DATA/HRRRE"

elif [[ $machine == "Hercules" ]]; then
    partition_wps="batch"
    partition_static="batch"  ; claim_cpu_static="--cpus-per-task=12"
    partition_create="batch"  ; claim_cpu_create="--mem-per-cpu=128G"

    npepost=40

    mach="slurm"
    job_exclusive_str="#SBATCH --exclusive"
    job_account_str="#SBATCH -A ${hpcaccount-wof}"
    job_runmpexe_str="srun"
    job_runexe_str="srun"

    modulename="build_hercules_intel"
    WPSGEOG_PATH="/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/WPS_GEOG/"

    module purge
    module use "${rootdir}/modules"
    module load $modulename

    wgrib2path="/work2/noaa/wof/ywang/tools/hpc-stack/intel-oneapi-compilers-2022.2.1/wgrib2/2.0.8/bin/wgrib2"
    nckspath="/work2/noaa/wof/ywang/tools/hpc-stack/intel-oneapi-compilers-2022.2.1/nco/5.0.6/bin/ncks"
    gpmetis="/home/yhwang/local/bin/gpmetis"

    OBS_DIR="/work2/noaa/wof/ywang/MPAS/OBSGEN"

    hrrr_dir="/work2/noaa/wof/ywang/MPAS/MODEL_DATA/HRRRE"

elif [[ $machine == "Cheyenne" ]]; then

    if [[ $dorun == true ]]; then
        runcmd="qsub"
    fi
    ncores_static=32
    partition_wps="main"
    partition_static="main" ; claim_cpu_static="ncpus=${ncores_static}"
    partition_create="main" ; claim_cpu_create="ncpus=${ncores_static}"

    npestatic=72

    mach="pbs"
    job_exclusive_str="#PBS -l job_priority=economy"
    job_account_str="#PBS -A ${hpcaccount-NMMM0021}"
    job_runmpexe_str="mpiexec"
    job_runexe_str="mpiexec"
    runcmd_str=""

    OBS_DIR="/glade/work/ywang/observations"

    modulename="defaults"
    WPSGEOG_PATH="/glade/work/ywang/WPS_GEOG/"
    wgrib2path="wgrib2_not_found"
else    # Vecna at NSSL
    ncores_static=96
    partition_wps="batch"
    partition_static="batch"    ; claim_cpu_static=""
    partition_create="batch"    ; claim_cpu_create="--mem-per-cpu=128G"

    npestatic=24

    mach="slurm"
    #job_exclusive_str="#SBATCH --exclude=cn11,cn14"
    job_exclusive_str="#SBATCH --exclusive"
    job_account_str=""
    job_runmpexe_str="srun"
    job_runexe_str="srun"
    runcmd_str="srun -n 1"

    modulename="env.mpas_smiol"
    #source ${rootdir}/modules/${modulename}
    WPSGEOG_PATH="/scratch/ywang/MPAS/WPS_GEOG/"
    wgrib2path="/scratch/ywang/tools/gnu/bin/wgrib2"
    nckspath="/home/yunheng.wang/tools/micromamba/envs/wofs_an/bin/ncks"
    gpmetis="/scratch/ywang/tools/bin/gpmetis"
    export LD_LIBRARY_PATH=/scratch/ywang/MPAS/tools/lib
    nclpath="/scratch/software/miniconda3/bin/ncl"

    OBS_DIR="/scratch/ywang/MPAS/gnu/mpas_scripts/run_dirs/OBS_SEQ"

    hrrr_dir="/scratch/wofuser/MODEL_DATA/HRRRE"

    # Load Python Enviroment if necessary
    if [[ " ${jobs[*]} " =~ " meshplot_py " ]]; then
        echo    ""
        echo -e "Enabling Python micromamba environment - ${BROWN}wofs_an${NC} ...."
        echo    ""
        source /home/yunheng.wang/.pythonrc  || exit $?
    fi
fi

#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#
# Perform each task
#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#% ENTRY

#
# configurations that is not set from command line
#
#[static]
STATICIOTYPE="pnetcdf,cdf5"
EXTINVL=10800
EXTHEAD="HRRRE"
#hrrrvtable="Vtable.raphrrr"
hrrrvtable="Vtable.HRRRE.2018"
hrrr_time_ics="1400"
hrrr_time_lbc="1200"
hrrrfile="${hrrr_dir}/${eventdate}/${hrrr_time_ics}/postprd_mem0001/wrfnat_hrrre_newse_mem0001_01.grib2"

EXTINVL_STR=$(printf "%02d:00:00" $((EXTINVL/3600)) )

if [[ " ${jobs[*]} " == " check " ]]; then
    check_hrrr_files; exit 0
fi

echo -e "---- Jobs ($$) started $(date +%m-%d_%H:%M:%S) on host $(hostname) ----\n"
echo -e "  Event date : ${GREEN}$eventdate${NC} ${YELLOW}${eventtime}${NC}"
echo -e "  Root    dir: $rootdir${GREEN}/exec${NC}|${PURPLE}/templates${NC}|${DARK}/fix_files${NC}|${BROWN}/scripts${NC}"
echo -e "  Working dir: $WORKDIR${LIGHT_BLUE}/${eventdate}${NC}"
echo -e "  Domain name: ${PURPLE}$domname${NC};  MP scheme: ${BROWN}mp_nssl2m${NC}; Domain Center: ${WHITE}${cen_lat}${NC},${WHITE}${cen_lon}${NC}"

echo    " "

starttime_str=$(date -u -d "${eventdate} ${eventtime}" +%Y-%m-%d_%H:%M:%S)

rundir="$WORKDIR/${eventdate}"

if [[ ! -d $rundir ]]; then
    mkdir -p "$rundir"
fi

jobname="${eventdate:4:4}"

exedir="$rootdir/exec"
#
# write runtime configuration file
#
caseconfig="${WORKDIR}/${caseconfig-config.${eventdate}${affix}}"
write_runtimeconfig "$caseconfig"

if [[ " ${jobs[*]} " == " setup " ]]; then exit 0; fi

#
# Start the forecast driver
#
declare -A jobargs=([geogrid]="${rundir}/geo_${domname##*_}"            \
                    [createWOFS]="geo_${domname##*_}/done.geogrid"      \
                    #[static]="$domname/done.create ungrib/done.ungrib"
                    [rotate]="geo_${domname##*_}/done.geogrid"          \
                    [meshplot_ncl]="$domname/done.rotate"                         \
                    [meshplot_py]="$domname/done.rotate $domname/$domname.grid.nc" \
                    [static]="$domname/done.rotate ungrib/done.ungrib"  \
                    [ungrib_hrrr]="${hrrrfile}"                         \
                    [clean]="geogrid static createWOFS"                 \
                   )

for job in "${jobs[@]}"; do
    if [[ $verb -eq 1 ]]; then
        echo " "
        echo "    run_$job ${jobargs[$job]}"
    fi

    "run_$job" ${jobargs[$job]}
done

echo " "
echo "==== $0 done $(date +%m-%d_%H:%M:%S) ===="
echo " "

exit 0
