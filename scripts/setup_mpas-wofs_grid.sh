#!/bin/bash

#rootdir="/scratch/ywang/MPAS/mpas_runscripts"
scpdir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
rootdir=$(realpath $(dirname $scpdir))

eventdateDF=$(date +%Y%m%d)

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
#     build_jet_intel18_1.11_smiol
#     build_jet_intel18_1.11                # PIO version
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
#        x1.65536002.grid.nc
#
# 4. scripts                                # this scripts
#    4.1 setup_mpas-wofs_grid.sh
#
# 5. /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/WPS_GEOG
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
#     3. setup_mpas-wofs_grid.sh[YYYYmmddHHMM] [run_dirs] [jobnames]
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
    echo "    JOBS     - One or more jobs from [geogrid,init,lbc,mpas,mpassit,upp]"
    echo "               Default all jobs in sequence"
    echo " "
    echo "    OPTIONS:"
    echo "              -h              Display this message"
    echo "              -n              Show command to be run and generate job scripts only"
    echo "              -v              Verbose mode"
    echo "              -k  [0,1,2]     Keep working directory if exist, 0- keep as is; 1- overwrite; 2- make a backup as xxxx.bak?"
    echo "                              Default is 0 for ungrib, mpassit, upp and 1 for others"
    echo "              -t  DIR         Template directory for runtime files"
    echo "              -d  domname     Domain name, default: wofs_mpas"
    echo "              -m  Machine     Machine name to run on, [Jet, Cheyenne, Vecna]."
    echo "              -a  wof         Account name for job submission."
    echo "              -c  lat,lon     Domain central lat/lon, for example, 43.33296,-84.24593"
    echo " "
    echo "   DEFAULTS:"
    echo "              eventdt = $eventdateDF"
    echo "              rootdir = $rootdir"
    echo "              WORKDIR = $rootdir/run_dirs"
    echo "              TEMPDIR = $rootdir/templates"
    echo "              FIXDIR  = $rootdir/fix_files"
    echo " "
    echo "                                     -- By Y. Wang (2023.05.24)"
    echo " "
    exit $1
}

########################################################################
#
# Extract WRF domain attributes
#
function ncattget {
  ${nckspath} -x -M $1 | grep -E "(corner_lats|corner_lons|CEN_LAT|CEN_LON)"
}

########################################################################

function run_geogrid {

    wrkdir=$1
    mkwrkdir $wrkdir $overwrite
    cd $wrkdir

    if [[ -f done.geogrid ]]; then
        echo "Found file \"done.geogrid\", skipping run_geogrid ...."
        echo ""
        return
    fi

    if ! [[ $cen_lat && $cen_lon ]]; then
        echo "ERROR: Domain center is required for option \"-c\" as \"lat,lon\"."
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
s/PARTION/${partition}/
s/NOPART/$npepost/
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
                if [[ $verb -eq 1 ]]; then
                    echo "Waiting for file: $cond"
                fi
                sleep 10
            done
        done
    fi

    wrkdir="$rundir/$domname"
    mkwrkdir $wrkdir $overwrite
    cd $wrkdir

    if [[ -f done.create ]]; then
        echo "Found file \"done.create\", skipping run_createWOFS ...."
        echo ""
        return
    elif [[ -f create.running || -f queue.create ]]; then
        return                   # skip
    fi

    local mrpythondir

    # Check MPAS-Limited-Area
    mrpythondir="$rootdir/MPAS-Limited-Area"
    if [[ ! -r $mrpythondir ]]; then
        echo "MPAS-Limited-Area directory not found in $mrpythondir"
        exit 0
    fi

    cp    $mrpythondir/create_region .
    cp -r $mrpythondir/limited_area .

    # Check x1.65536002.grid.nc, global 3 km mesh grid
    if [[ ! -f $FIXDIR/x1.65536002.grid.nc ]]; then
        echo "File x1.65536002.grid.nc not found in $FIXDIR"
        exit 0
    fi
    ln -sf $FIXDIR/x1.65536002.grid.nc .

    local geofile wrfdomain wrfkey vals newsval val keyval domelements
    # Get lat/lon ranges
    geofile=$(dirname ${conditions[0]})/geo_em.d01.nc
    wrfdomain=$(ncattget $geofile)

    IFS=$'\n' domelements=($wrfdomain)
    for var in ${domelements[@]}; do
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
            for val in ${vals[@]}; do
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

    lat_s=$(echo "$corner_lats_min-0.2" | bc -l)
    lat_n=$(echo "$corner_lats_max+0.2" | bc -l)
    lon_sw=$(echo "$corner_lons_min+0.5" | bc -l)
    lon_nw=$(echo "$corner_lons_min-0.2" | bc -l)
    lon_ne=$(echo "$corner_lons_max+0.2" | bc -l)
    lon_se=$(echo "$corner_lons_max-0.5" | bc -l)

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
s/CPUSPEC/${create_cpu}/
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
                if [[ $verb -eq 1 ]]; then
                    echo "Waiting for file: $cond"
                fi
                sleep 10
            done
        done
    fi

    wrkdir=$rundir/$domname
    mkwrkdir $wrkdir $overwrite
    cd $wrkdir

    if [[ ! -f $domname.graph.info.part.${npepost} ]]; then
        if [[ $verb -eq 1 ]]; then
            echo "Generating ${domname}.graph.info.part.${npepost} in $wrkdir using ${gpmetis}"
        fi
        ${gpmetis} -minconn -contig -niter=200 ${domname}.graph.info ${npepost} > gpmetis.out$npepost
        if [[ $? -ne 0 ]]; then
            echo "$?: ${gpmetis} -minconn -contig -niter=200 ${domname}.graph.info ${npepost}"
            exit $?
        fi
    fi

    # The program needs a time string in file $domname.grid.nc
    #
    inittime_str=$(date -d "$hrrrdate ${hrrrtime}" +%Y-%m-%d_%H)
    starttime_str=$(date -d "$hrrrdate ${hrrrtime}" +%Y-%m-%d_%H:%M:%S)

    initfile="../ungrib/${EXTHEAD}:$inittime_str"
    if [[ ! -f $initfile ]]; then
        echo "Initial file (for extracting time): $initfile not found"
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
    config_fg_interval = $((EXTINVL*3600))
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
    config_specified_zeta_levels = '${FIXDIR}/L60.txt'
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
                  io_type="netcdf"
                  filename_template="${domname}.grid.nc"
                  input_interval="initial_only" />

<immutable_stream name="output"
                  type="output"
                  filename_template="${domname}.static.nc"
                  io_type="netcdf"
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
s/NOPART/$npepost/
s/JOBNAME/static_${jobname}/
s/CPUSPEC/${static_cpu}/
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
                if [[ $verb -eq 1 ]]; then
                    echo "Waiting for file: $cond"
                fi
                sleep 10
            done
        done
    fi

    wrkdir="$rundir/$domname"
    mkwrkdir $wrkdir $overwrite
    cd $wrkdir

    if [[ -f done.rotate ]]; then
        echo "Found file \"done.rotate\", skipping run_rotate ...."
        echo ""
        return
    elif [[ -f rotate.running || -f queue.rotate ]]; then
        return                   # skip
    fi

    local geofile wrfdomain wrfkey vals newsval val keyval domelements
    # Get lat/lon ranges
    geofile=$(dirname ${conditions[0]})/geo_em.d01.nc
    wrfdomain=$(ncattget $geofile)

    IFS=$'\n' domelements=($wrfdomain)
    for var in ${domelements[@]}; do
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
            for val in ${vals[@]}; do
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
    ln -sf ${FIXDIR}/WOFSdomain.graph.info wofs_mpas.graph.info

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
s/PARTION/${partition_create}/
s/CPUSPEC/${create_cpu}/
s/ACCTSTR/${job_account_str}/
s/EXCLSTR/${job_exclusive_str}/
s/JOBNAME/grid_rotate/
s/DOMNAME/${domname}/
s#WRKDIR#$wrkdir#g
s#EXEDIR#${exedir}#
s/RUNCMD/${job_runexe_str}/
EOF
    submit_a_jobscript $wrkdir "rotate" $sedfile $TEMPDIR/$jobscript $jobscript ""
}

########################################################################

function run_ungrib_hrrr {
    if [[ $# -ne 1 ]]; then
        echo "ERROR: run_ungrib require 1 arguments."
        exit 2
    fi
    hrrr_grib_dir=$1

    wrkdir=$rundir/ungrib
    mkwrkdir $wrkdir 0
    cd $wrkdir

    if [[ -f done.ungrib ]]; then
        echo "Found file \"done.ungrib\", skipping run_ungrib_hrrr ...."
        echo ""
        return                   # skip
    elif [[ -f ungrib.running || -f queue.ungrib ]]; then
        return                   # skip
    fi

    h=${hrrrtime:0:2}
    hstr=$(printf "%02d" ${h#0})
    if [[ -f $hrrr_grib_dir ]]; then
        hrrrfile=$hrrr_grib_dir
        #vtime=$($wgrib2path $hrrrfile -for 1:1 -vt)
        #gribtime=${vtime##*=}
        #hrrrdate=${gribtime:0:8}
        #hrrrtime=${gribtime:8:2}
        #echo $hrrrtime, $hrrrdate, $vtime, $gribtime
    else
        julday=$(date -d "$hrrrdate ${hrrrtime}" +%y%j%H)
        hrrrbase="${julday}0000"
        hrrrfile="$hrrr_grib_dir/${hrrrbase}$hstr"
    fi
    basefn=$(basename $hrrrfile)
    basefn="NSSL_$basefn"

    if [[ $verb -eq 1 ]]; then echo "HRRR file: $hrrrfile"; fi
    while [[ ! -f $hrrrfile && ! -f $basefn ]]; do
        if [[ $verb -eq 1 ]]; then
            echo "Waiting for $hrrrfile ..."
        fi
        sleep 10
    done

    ln -sf ${hrrrfile} GRIBFILE.AAA
    ln -sf $FIXDIR/WRFV4.0/${hrrrvtable} Vtable

    hrrrtime_str=$(date -d "$hrrrdate ${hrrrtime}" +%Y-%m-%d_%H:%M:%S)
    echo "$hrrrdate ${hrrrtime}"
    cat << EOF > namelist.wps
&share
 wrf_core = 'ARW',
 max_dom = 1,
 start_date = '${hrrrtime_str}',
 end_date = '${hrrrtime_str}',
 interval_seconds = $((EXTINVL*3600))
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
s/PARTION/${partition}/
s/JOBNAME/ungrb_hrrr_${jobname}/
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
                if [[ $verb -eq 1 ]]; then
                    echo "Waiting for file: $cond"
                fi
                sleep 10
            done
        done
    fi

    wrkdir="$rundir/$domname"
    if [[ ! -f $wrkdir/$domname.grid.nc ]]; then
        echo "Working file: $wrkdir/$domname.grid.nc not exist."
        return
    fi
    cd $wrkdir

    ln -sf ../geo_${domname##*_}/geo_em.d01.nc .

    #
    # Create job script and submit it
    #
    datestring=$()
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
        echo "Domain on ${starttime_str:0:10} is saved as $wrkdir/$domame.png."
    fi
}

########################################################################

function run_meshplot_py {
    # Python version also include code for the radar list within domain

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
                if [[ $verb -eq 1 ]]; then
                    echo "Waiting for file: $cond"
                fi
                sleep 10
            done
        done
    fi

    wrkdir="$rundir/$domname"
    if [[ ! -f $wrkdir/$domname.grid.nc ]]; then
        echo "Working file: $wrkdir/$domname.grid.nc not exist."
        return
    fi
    cd $wrkdir

    if [[ -f "radars.${eventdate}.sh" ]]; then
        echo "Found file \"radars.${eventdate}.sh\", skipping run_run_meshplot_py ...."
        echo ""
        return
    fi

    output_grid="../geo_${domname##*_}/wofs_mpas_output.json"

    #
    # Activate Python environment
    #
    source ~/.python wofs_post

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
    echo "Running $jobcmdstr"
    python $jobcmdstr

    ls -l radars.${eventdate}.sh
    #echo "Waiting for radars.${eventdate}.sh ...."
    #while [[ ! -e radars.${eventdate}.sh  ]]; do
    #    sleep 10
    #done
}

########################################################################

function run_clean {

    for dirname in $@; do
        case $dirname in
        geogrid )
            cd $rundir/geo_mpas

            donegeo="$rundir/geo_mpas/done.geogrid"
            if [[ -f $donegeo ]]; then
                rm -rf geogrid.log.* geogrid_*.log
                rm -rf error.geogrid queue.geogrid running.geogrid
            fi
            ;;
        createWOFS )
            if [[ -d $rundir/$domname ]]; then
                cd $rundir/$domname

                donecreate="$rundir/$domname/done.create"
                if [[ -e $donecreate ]]; then
                    rm -rf create_region limited_area create_*.log x1.65536002.grid.nc
                fi
            fi
            ;;
        static )
            if [[ -d $rundir/$domname ]]; then
                cd $rundir/$domname

                donestatic="$rundir/$domname/done.static"
                if [[ -e $donestatic ]]; then
                    rm -f log.init_atmosphere.* static_*.log  #$EXTHEAD:*
                fi
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

#jobs=(geogrid ungrib_hrrr createWOFS static)
jobs=(geogrid ungrib_hrrr rotate meshplot_py static)

WORKDIR="${rootdir}/run_dirs"
TEMPDIR="${rootdir}/templates"
FIXDIR="${rootdir}/fix_files"
eventdate="$eventdateDF"
eventtime="1500"
domname="wofs_mpas"
EXTHEAD="HRRRE"

#hrrrvtable="Vtable.raphrrr"
hrrrvtable="Vtable.HRRRE.2018"

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
        -d)
            domname=$2
            shift
            ;;

        -c)
            if [[ $2 =~ ^[0-9.]+,[0-9.-]+$ ]]; then
                latlons=(${2//,/ })
                cen_lat=${latlons[0]}
                cen_lon=${latlons[1]}
            else
                echo "ERROR: Domain center is required as \"lat,lon\", get: $2."
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
        -*)
            echo "Unknown option: $key"
            usage 2
            ;;
        static* | geogrid* | createWOFS | meshplot | clean* )
            jobs=(${key//,/ })
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
                 echo ""
                 echo "ERROR: unknown argument, get [$key]."
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

mach="slurm"

if [[ $machine == "Jet" ]]; then
    #ncores_ics=5; ncores_static=6; ncores_post=6
    partition="ujet,tjet,xjet,vjet,kjet"         ; claim_cpu="--cpus-per-task=2"
    partition_static="ujet,tjet,xjet,vjet,kjet"  ; static_cpu="--cpus-per-task=12"
    partition_create="bigmem"                    ; create_cpu="--mem-per-cpu=128G"

    npepost=24   #; nnodes_post=$(( npepost/ncores_post ))

    mach="slurm"
    job_exclusive_str="#SBATCH --exclusive"
    job_account_str="#SBATCH -A ${hpcaccount-wof}"
    job_runmpexe_str="srun"
    job_runexe_str="srun"

    modulename="build_jet_intel18_1.11"
    WPSGEOG_PATH="/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/WPS_GEOG/"

    source /etc/profile.d/modules.sh
    module purge
    module use ${rootdir}/modules
    module load $modulename
    #module load nco
    module load wgrib2/2.0.8
    wgrib2path="/apps/wgrib2/2.0.8/intel/18.0.5.274/bin/wgrib2"
    nckspath="/apps/nco/4.9.3/gnu/9.2.0/bin/ncks"
    gpmetis="/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/bin/gpmetis"

    hrrrdir="/public/data/grids/hrrr/conus/wrfnat/grib2"
    hrrrfile="/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/MODEL_DATA/HRRRE/${eventdate}/1400/mem01/wrfnat_hrrre_newse_mem0001_01.grib2"
    hrrrdate="${eventdate}"
    hrrrtime="${eventtime}"

elif [[ $machine == "Cheyenne" ]]; then

    if [[ $dorun == true ]]; then
        runcmd="qsub"
    fi
    ncores_static=32; ncores_post=32
    partition="regular"        ; claim_cpu="ncpus=${ncores_static}"
    partition_static="regular" ; static_cpu="ncpus=${ncores_static}"
    partition_create="regular" ; create_cpu="ncpus=${ncores_post}"

    npepost=72   ; nnodes_post=$(( npepost/ncores_post ))

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
    ncores_static=96; ncores_post=96
    partition="batch"           ; claim_cpu="--ntasks-per-node=${ncores_static} --mem-per-cpu=4G";
    partition_static="batch"    ; static_cpu="--mem-per-cpu=8G"
    partition_create="batch"    ; create_cpu="--mem-per-cpu=128G"

    npepost=24

    mach="slurm"
    job_exclusive_str=""
    job_account_str=""
    job_runmpexe_str="srun --mpi=pmi2"
    job_runexe_str="srun"

    modulename="env.mpas_smiol"
    #source ${rootdir}/modules/${modulename}
    WPSGEOG_PATH="/scratch/ywang/MPAS/WPS_GEOG/"
    wgrib2path="/scratch/ywang/tools/hpc-stack/intel-2021.8.0/wgrib2/2.0.8/bin/wgrib2"
    nckspath="/scratch/software/miniconda3/bin/ncks"
    gpmetis="/scratch/ywang/tools/bin/gpmetis"
    export LD_LIBRARY_PATH=/scratch/ywang/MPAS/tools/lib
    nclpath="/scratch/software/miniconda3/bin/ncl"

    hrrrdir="/scratch/wofuser/MODEL_DATA/HRRRE"
    hrrrfile="/scratch/wofuser/MODEL_DATA/HRRRE/${eventdate}/1400/mem01/wrfnat_hrrre_newse_mem0001_01.grib2"
    hrrrdate="${eventdate}"
    hrrrtime="${eventtime}"
fi

EXTINVL=3
EXTINVL_STR="${EXTINVL}:00:00"

source $scpdir/Common_Utilfuncs.sh


#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#
# Perform each task
#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#% ENTRY

echo "---- Jobs ($$) started $(date +%m-%d_%H:%M:%S) on host $(hostname) ----"
echo "     Event date : ${eventdate} ${eventtime}"
echo "     Root    dir: $rootdir"
echo "     Working dir: $WORKDIR"
echo " "

starttime_str=$(date -d "${eventdate} ${eventtime}" +%Y-%m-%d_%H:%M:%S)

rundir="$WORKDIR/${eventdate}"

if [[ ! -d $rundir ]]; then
    mkdir -p $rundir
fi

jobname="${eventdate:4:4}"

exedir="$rootdir/exec"

declare -A jobargs=([geogrid]="${rundir}/geo_${domname##*_}"            \
                    [createWOFS]="geo_${domname##*_}/done.geogrid"      \
                    #[static]="$domname/done.create ungrib/done.ungrib"  \
                    [rotate]="geo_${domname##*_}/done.geogrid"          \
                    [meshplot_ncl]="$domname/done.rotate"                         \
                    [meshplot_py]="$domname/done.rotate $domname/$domname.grid.nc" \
                    [static]="$domname/done.rotate ungrib/done.ungrib"  \
                    [ungrib_hrrr]="${hrrrfile}"                         \
                    [clean]="geogrid static createWOFS"                 \
                   )

for job in ${jobs[@]}; do
    if [[ $verb -eq 1 ]]; then
        echo " "
        echo "run_$job ${jobargs[$job]}"
    fi

    run_$job ${jobargs[$job]}
done

echo " "
echo "==== $0 done $(date +%m-%d_%H:%M:%S) ===="
echo " "

exit 0
