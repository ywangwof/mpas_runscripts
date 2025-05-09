#!/bin/bash
# shellcheck disable=SC2317,SC1090,SC1091,SC2086

#rootdir="/scratch/ywang/MPAS/mpas_runscripts"
scpdir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
rootdir=$(realpath "$(dirname "$scpdir")")

mpasworkdir="/scratch/wofs_mpas"     # platform dependent, it is set in Site_Runtime.sh

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
#        run_projectHexes.slurm
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
#    4.1 setup_mpas-wofs.sh
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
#     3. setup_mpas-wofs.sh [YYYYmmddHHMM] [run_dirs] [jobnames]
#
#-----------------------------------------------------------------------

function usage {
    echo -e " "
    echo -e "    USAGE: $0 [options] DATETIME [WORKDIR] [JOBS]"
    echo -e " "
    echo -e "    PURPOSE: Set up a MPAS-WOFS grid based on the central lat/lon."
    echo -e " "
    echo -e "    DATETIME - Case date and time in YYYYmmddHHMM, Default: ${eventdateDF}"
    echo -e "    WORKDIR  - Run Directory"
    echo -e "    JOBS     - One or more jobs from [geogrid,ungrib_hrrr,rotate,meshplot_{py,ncl},static,createWOFS,projectHexes,clean]"
    echo -e "               or any one from [check,checkbg,checkobs,setup]."
    echo -e "               setup    - just write set up configuration file"
    echo -e "               checkbg  - Check the availability of the HRRRE datasets"
    echo -e "               checkobs - Check the availability of observations"
    echo -e "               Default  - All jobs in sequence order: [geogrid,ungrib_hrrr,projectHexes,meshplot_py,static]."
    echo -e " "
    echo -e "    OPTIONS:"
    echo -e "              -h              Display this message"
    echo -e "              -n              Show command to be run and generate job scripts only"
    echo -e "              -v              Verbose mode"
    echo -e "              -k  [0,1,2]     Keep working directory if exist, 0- keep as is; 1- overwrite; 2- make a backup as xxxx.bak?"
    echo -e "                              Default is 0 for ungrib, mpassit, upp and 1 for others"
    echo -e "              -m  Machine     Machine name to run on, [Jet, Derecho, Vecna]."
    echo -e "              --template/--fix/--exec  DIR"
    echo -e "                              Directory for runtime files, job templates/fixed static files/executable programs respectively."
    echo -e "              -a  wof         Account name for job submission."
    echo -e "              -M  init        DA cycles mode, either init or restart. default: init"
    echo -e "              -F  init        FCST launch mode, either init or restart. default same as ${BROWN}\${damode}${NC}"
    echo -e "              -c  lat,lon     Domain central lat/lon, for example, 43.33296,-84.24593. Program \"geogrid\" requires them."
    echo -e "              -d  domname     Domain name, default: wofs_mpas"
    echo -e "              -x  affix       Affix attached to the run directory \"dacycles\" or \"fcst\". Default: Null"
    echo -e "              -l  L60.txt     Vertical level file"
    echo -e "              -o  filename    Ouput file name of the configuration file for this case"
    echo -e "                              Default: \${WORKDIR}/config.\${eventdate}\${affix}"
    echo -e " "
    echo -e "   DEFAULTS:"
    echo    "              eventdate             = ${eventdateDF}"
    echo    "              WORKDIR               = ${mpasworkdir}/run_dirs"
    echo -e "  ${DARK}(*auto)${NC}     ROOTDIR/SCPDIR        = $rootdir${BROWN}/scripts${NC}"
    echo -e "  ${DARK}(%config)${NC}   TEMPDIR/FIXDIR/EXEDIR = $rootdir${BROWN}${PURPLE}/templates${NC}|${DARK}/fix_files${NC}|${GREEN}/exec${NC}"
    echo " "
    echo "                                     -- By Y. Wang (2025.03.01)"
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
            --template)
                if [[ -d $2 ]]; then
                    args["TEMPDIR"]=$2
                else
                    echo -e "${RED}ERROR${NC}: Template directory ${BLUE}$2${NC} does not exist."
                    usage 1
                fi
                shift
                ;;
            --fix)
                if [[ -d $2 ]]; then
                    args["FIXDIR"]=$2
                else
                    echo -e "${RED}ERROR${NC}: Fixed file directory ${BLUE}$2${NC} does not exist."
                    usage 1
                fi
                shift
                ;;
            --exec)
                if [[ -d $2 ]]; then
                    args["EXEDIR"]=$2
                else
                    echo -e "${RED}ERROR${NC}: Program directory ${BLUE}$2${NC} does not exist."
                    usage 1
                fi
                shift
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

        -M)
            if [[ ${2,,} == "init" || ${2,,} == "restart" ]]; then
                args["damode"]="${2,,}"
            else
                echo -e "${RED}ERROR${NC}: unknow argument. Expect: ${YELLOW}init${NC} or ${YELLOW}restart${NC}. Got: ${PURPLE}${2,,}${NC}"
                usage 1
            fi
            shift
            ;;
        -F)
            if [[ ${2,,} == "init" || ${2,,} == "restart" ]]; then
                args["fcstmode"]="${2,,}"
            else
                echo -e "${RED}ERROR${NC}: unknow argument. Expect: ${YELLOW}init${NC} or ${YELLOW}restart${NC}. Got: ${PURPLE}${2,,}${NC}"
                usage 1
            fi
            shift
            ;;
        -d)
            args["domname"]=$2
            shift
            ;;
        -x)
            args["affix"]="$2"
            shift
            ;;
        -l)
            fixed_level="$2"
            if [[ ! -e ${fixed_level} ]]; then
                echo -e "${RED}ERROR${NC}: ${BLUE}${fixed_level}${NC} not exist."
                usage 1
            fi
            args["level_file"]=${fixed_level}
            shift
            ;;
        -c)
            if [[ $2 =~ ^[0-9.]+,[0-9.-]+$ ]]; then
                #latlons=(${2//,/ })
                #mapfile -t latlons <<< "${2//,/ }"
                IFS="," read -r -a latlons <<< "$2"
                args["cen_lat"]=${latlons[0]}
                args["cen_lon"]=${latlons[1]}
            else
                echo -e "${RED}ERROR${NC}: Domain center is required as ${BLUE}-c lat,lon${NC}, get: ${PURPLE}$2${NC}."
                usage 1
            fi
            shift
            ;;
        -a)
            args["hpcaccount"]=$2
            shift
            ;;
        -o)
            args["caseconfig"]=$2
            shift
            ;;

            -*)
                echo -e "${RED}ERROR${NC}: Unknown option: ${PURPLE}$key${NC}"
                usage 2
                ;;
            static* | geogrid* | createWOFS | projectHexes | meshplot* | ungrib* | rotate* | clean* | setup | check*)
                args["jobs"]="${key//,/ }"
                ;;
            *)
                if [[ $key =~ ^[0-9]{12}$ ]]; then
                    args["eventdate"]=${key:0:8}
                    args["eventtime"]=${key:8:4}
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
#
# Extract WRF domain attributes
#
function ncattget {
    # shellcheck disable=SC2154
    if which ${nckspath} 2> /dev/null ; then
        ${nckspath} -x -M "$1" | grep -E "(corner_lats|corner_lons|CEN_LAT|CEN_LON|TRUELAT[12]|STAND_LON|MOAD_CEN_LAT|DX|DY|[ij]_parent)"
    else
        mecho0 "${RED}ERROR${NC}: Program ${BLUE}${nckspath}${NC} not found."
        exit $?
    fi
}

########################################################################

function run_geogrid {

    wrkdir=$1
    mkwrkdir "$wrkdir" "$overwrite"
    cd "$wrkdir" || return

    if [[ -f done.geogrid ]]; then
        mecho0 "Found file ${CYAN}done.geogrid${NC}, skipping ${WHITE}${FUNCNAME[0]}${NC} ...."
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
    standlon="${cen_lon}"

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
  stand_lon = ${standlon}
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
    'stdlon'  : ${standlon},
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

    # Associative arrays are local by default
    declare -A jobParms=(
        [PARTION]="${partition_wps}"
        [NOPART]="${npestatic}"
        [JOBNAME]="${geoname}"
    )
    submit_a_job "$wrkdir" "geogrid" "jobParms" "$TEMPDIR/$jobscript" "$jobscript" ""
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
        mecho0 "Found file ${CYAN}done.create${NC}, skipping ${WHITE}${FUNCNAME[0]}${NC} ...."
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
        CEN_LAT | CEN_LON )
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

    declare -A jobParms=(
        [PARTION]="${partition_create}"
        [CPUSPEC]="${claim_cpu_create}"
        [JOBNAME]="createWOFS"
    )
    submit_a_job $wrkdir "create" jobParms $TEMPDIR/$jobscript $jobscript ""
}

########################################################################

function run_projectHexes {

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
            mecho0 "Checking: ${CYAN}$cond${NC}"
            while [[ ! -e $cond ]]; do
                if [[ $verb -eq 1 ]]; then
                    mecho0 "Waiting for file: ${CYAN}$cond${NC}"
                fi
                sleep 10
            done
        done
    fi

    wrkdir="$rundir/$domname"
    mkwrkdir $wrkdir $overwrite
    cd $wrkdir || return

    if [[ -f done.project ]]; then
        mecho0 "Found file ${CYAN}done.project${NC}, skipping ${WHITE}${FUNCNAME[0]}${NC} ...."
        return
    elif [[ -f running.project || -f queue.project ]]; then
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
        CEN_LAT | CEN_LON | TRUELAT? | STAND_LON | MOAD_CEN_LAT )
            newval=${vals[0]%%f}
            declare "$wrfkey=$newval"
            ;;
        DX | DY )
            newval=${vals[0]%%.f}
            declare "$wrfkey=$newval"
            ;;
        i_parent_start | i_parent_end | j_parent_start | j_parent_end )
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
    #echo $TRUELAT1, $TRUELAT2
    #echo $corner_lats_min, $corner_lats_max
    #echo $corner_lons_min, $corner_lons_max
    #exit 0

    ## shellcheck disable=SC2154
    #lat_s=$(echo "$corner_lats_min-0.2" | bc -l)
    ## shellcheck disable=SC2154
    #lat_n=$(echo "$corner_lats_max+0.2" | bc -l)
    ## shellcheck disable=SC2154
    #lon_sw=$(echo "$corner_lons_min+0.5" | bc -l)
    #lon_nw=$(echo "$corner_lons_min-0.2" | bc -l)
    ## shellcheck disable=SC2154
    #lon_ne=$(echo "$corner_lons_max+0.2" | bc -l)
    #lon_se=$(echo "$corner_lons_max-0.5" | bc -l)

    # shellcheck disable=SC2153
    cat <<EOF > namelist.projections
&mesh
  cell_spacing_km  =      3.,
  mesh_length_x_km =    910.,
  mesh_length_y_km =    910.,
  earth_radius_km  = 6378.14,
/
&projection
  projection_type = "lambert_conformal",
/
&lambert_conformal
  reference_longitude_degrees = ${CEN_LON},
  reference_latitude_degrees  = ${CEN_LAT},
  standard_parallel_1_degrees = ${TRUELAT1},
  standard_parallel_2_degrees = ${TRUELAT2},
  standard_longitude_degrees  = ${STAND_LON},
/
EOF

    #
    # Create job script and submit it
    #
    jobscript="run_projectHexes.slurm"

    declare -A jobParms=(
        [PARTION]="${partition_static}"
        [CPUSPEC]="${claim_cpu_static}"
        [JOBNAME]="project_${domname}"
        [DOMNAME]="${domname}"
    )
    submit_a_job "$wrkdir" "projectHexes" "jobParms" "$TEMPDIR/$jobscript" "$jobscript" ""
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
        mecho0 "Found file ${CYAN}done.static${NC}, skipping ${WHITE}${FUNCNAME[0]}${NC} ...."
        return
    elif [[ -f running.static || -f queue.static ]]; then
        return                   # skip
    fi

    if [[ ! -f $domname.graph.info.part.${npestatic} ]]; then
        # shellcheck disable=SC2154
        split_graph "${gpmetis}" "${domname}.graph.info" "${npestatic}" "$wrkdir" "$dorun" "$verb"
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
    config_use_spechumd = true
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
    # shellcheck disable=SC2154
    jobscript="run_static.${mach}"

    declare -A jobParms=(
        [PARTION]="${partition_static}"
        [NOPART]="${npestatic}"
        [JOBNAME]="static_${jobname}"
        [CPUSPEC]="${claim_cpu_static}"
    )
    submit_a_job "$wrkdir" "static" "jobParms" "$TEMPDIR/$jobscript" "$jobscript" ""
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
        mecho0 "Found file ${CYAN}done.rotate${NC}, skipping ${WHITE}${FUNCNAME[0]}${NC} ...."
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

    declare -A jobParms=(
        [PARTION]="${partition_static}"
        [CPUSPEC]="${claim_cpu_static}"
        [JOBNAME]="grid_rotate"
        [DOMNAME]="${domname}"
    )
    submit_a_job "$wrkdir" "rotate" "jobParms" "$TEMPDIR/$jobscript" "$jobscript" ""
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
        mecho0 "Found file ${CYAN}done.ungrib${NC}, skipping ${WHITE}${FUNCNAME[0]}${NC} ...."
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

    # shellcheck disable=SC2034
    declare -A jobParms=(
        [PARTION]="${partition_wps}"
        [JOBNAME]="ungrb_hrrr_${jobname}"
    )
    submit_a_job "$wrkdir" "ungrib" "jobParms" "$TEMPDIR/$jobscript" "$jobscript" ""
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
    # shellcheck disable=SC2154
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
    #if [[ ! -f $wrkdir/$domname.grid.nc ]]; then
    #    mecho0 "Working file: $wrkdir/$domname.grid.nc not exist."
    #    return
    #fi
    cd $wrkdir  || return

    if [[ -f "${domname}.${eventdate}.radars.sh" ]]; then
        mecho0 "Found file ${CYAN}${domname}.${eventdate}.radars.sh${NC}, skipping ${WHITE}${FUNCNAME[0]}${NC} ...."
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
    #  --title NAME          Name of the WoF grid
    #  -o OUTFILE, --outfile OUTFILE
    #                        Name of output image or output directory
    #  -m latlon             Base map latlon or lambert
    #  --outgrid OUTGRID     Plot an output grid, "True", "False" or a filename.
    #                        When "True", retrieve grid from command line.
    #
    jobcmdstr="$jobscript -o $wrkdir --title ${domname}.${eventdate} --outgrid ${output_grid} -g ${FIXDIR}/nexrad_stations.txt -m stereo ${conditions[1]}"
    mecho0 "Running ${BROWN}$jobcmdstr${NC}"
    python $jobcmdstr

    #ls -l ${domname}.${eventdate}.radars.sh
    #echo "Waiting for ${domname}.${eventdate}.radars.sh ...."
    #while [[ ! -e ${domname}.${eventdate}.radars.sh  ]]; do
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
        projectHexes )
            if [[ -d $rundir/$domname ]]; then
                cd "$rundir/$domname" || return

                doneproject="$rundir/$domname/done.project"
                if [[ -e $doneproject ]]; then
                    rm -rf queue.projectHexes projectHexes_*.log
                fi
            fi
            ;;
        static )
            if [[ -d $rundir/$domname ]]; then
                cd "$rundir/$domname" || return

                donestatic="$rundir/$domname/done.static"
                if [[ -e $donestatic ]]; then
                    rm -f log.init_atmosphere.* static_*.log  #$EXTHEAD:*
                    rm -f gpmetis.out*
                fi
            fi
            ;;

        esac
    done
}

########################################################################

function write_config {
    if [[ $# -ne 1 ]]; then
        mecho0 "${RED}ERROR${NC}: No enough argument. get:$#."
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
            mecho0 "         ${PURPLE}${configname}.bak_${datestr}${NC}"
            mv ${configname} ${configname}.bak_${datestr}
        else
            mecho0 "Got ${PURPLE}${doit^^}${NC}, exit the program."
            exit 1
        fi
    fi

    # $machine is exported from setup_machine
    # shellcheck disable=SC2154
    default_site_settings "${machine}"

    #-------------------------------------------------------------------
    # Write out default configuration file
    #-------------------------------------------------------------------

    # shellcheck disable=SC2154
    cat <<EOF > $configname
#!/bin/bash
# shellcheck disable=SC1035,SC1020,SC1073,SC1072
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
#   damode:     DA cycles mode, either "restart" or "init", will be used in both run_dacycles.sh & run_fcst.sh
#
#   mpscheme:   Microphysics scheme, valid values are ('mp_nssl2m', 'mp_thompson', 'mp_tempo')
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
    damode="${damode}"

    MPASLSM='sf_ruc'
    MPASNFLS=9

    mpscheme='mp_nssl2m'
    sfclayer_schemes=('sf_monin_obukhov_rev' 'sf_monin_obukhov' 'sf_mynn')
    pbl_schemes=('bl_ysu' 'bl_myj' 'bl_mynn')

    vertLevel_file="${fixed_level}"

    WPSGEOG_PATH="${WPSGEOG_PATH}"

    FIXDIR="${FIXDIR}"
    TEMPDIR="${TEMPDIR}"
    EXEDIR="${EXEDIR}"

    wgrib2path="${wgrib2path}"
    gpmetis="${gpmetis}"

    mach="${mach}"
    job_exclusive_str="${job_exclusive_str}"
    job_account_str="${job_account_str}"
    job_runmpexe_str="${job_runmpexe_str}"
    job_runexe_str="${job_runexe_str}"
    runcmd_str="${runcmd_str}"

    relative_path=${relative_path}
#
# MPAS_OPTIONS apply to both [dacycles] & [fcst]. For debugging the MPAS dynamic core
# and should not be usually changed.
#
#    coef_3rd_order=1.0     # 3rd order advection
#    coef_3rd_order=0.25    # nearly 4th order advection
#
#    h_scalar_eddy_visc4   is a new parameter added at NSSL
#
[MPAS_OPTIONS]
    coef_3rd_order=1.0
    smagorinsky_coef=0.25
    visc4_2dsmag=0.125
    h_mom_eddy_visc4=0.0
    h_theta_eddy_visc4=0.25
    h_scalar_eddy_visc4=0.25
    smdiv=0.1
    physics_suite='convection_permitting'

[init]
    ICSIOTYPE="pnetcdf,cdf5"
    EXTNFGL=51
    EXTNFLS=9
    EXTHEAD="HRRRE"
    hrrrvtable="${hrrrvtable}"
    hrrr_dir="${hrrr_dir}"
    hrrr_subdir="${hrrr_sub_ics}"         # + 2-digit member string
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
    hrrr_subdir="${hrrr_sub_lbc}"         # + 2-digit member string
    hrrr_time="${hrrr_time_lbc}"

    npelbc="${npelbc}"; ncores_lbc="${ncores_lbc}"
    partition_lbc="${partition_lbc}"
    claim_cpu_lbc="${claim_cpu_lbc}"

[dacycles]
    ENS_SIZE=36
    intvl_sec=900
    ADAPTIVE_INF=true
    update_in_place=false               # update MPAS states in-place or
                                        # making a copy of the restart files
    use_BUFR=true                       # Whether we should wait for PrepBufr data file
    use_MESO=true                       # for a realtime run
    use_CWP=true
    use_RAD=true
    use_REF=true
    use_VEL=true

    run_updatebc=true                   # run mpas_update_bc
    run_obs2nc=true                     # run obs_seq_to_netcdf after filter
    run_obsdiag=true                    # run obs_diag after filter for each cycle
    run_addnoise=true                   # run WoFS add_noise facility (Python)
    run_trimvr=true                     # Trim NaNs from radial velocity observations (Python)
    WOFSAN_PATH="${mpas_wofs_python}"

    OUTIOTYPE="netcdf4"
    outwrf=false                        # Run MPASSIT after each data assimilation
    sampling_error_correction=".true."

    OBS_DIR="${OBS_DIR}"

    time_step=15

    partition_fcst="${partition_dafcst}";
    partition_filter="${partition_filter}"
    npefcst="${npedafcst}";   ncores_fcst="${ncores_dafcst}";   nnodes_fcst="${nnodes_dafcst}"
    npefilter="${npefilter}"; ncores_filter="${ncores_filter}"; nnodes_filter="${nnodes_filter}"

    claim_cpu_fcst="${claim_cpu_dafcst}"
    claim_cpu_filter="${claim_cpu_filter}"
    claim_cpu_update="${claim_cpu_update}"
    claim_time_fcst="00:20:00"

    npepost="${npepost}"; claim_cpu_post=""; claim_time_mpassit_alltimes="00:30:00"

    job_exclusive_str=""
[fcst]
    fcstmode="${fcstmode}"
    ENS_SIZE=18
    fcst_launch_intvl=3600
    fcst_length_seconds=(21600 10800)   # 6 hours at :00 and 3 hours at :30
    OUTINVL=300
    OUTIOTYPE="netcdf4"

    outpsfc=false                       # An extra streams for PSFC output"

    time_step=20

    partition_fcst="${partition_fcst}"
    partition_post="${partition_post}"
    claim_cpu_fcst="${claim_cpu_fcst}"
    claim_cpu_post="${claim_cpu_post}"
    npefcst="${npefcst}";    ncores_fcst="${ncores_fcst}";  nnodes_fcst="${nnodes_fcst}"
    npepost="${npepost}";    ncores_post="${ncores_post}";  nnodes_post="${nnodes_post}"

    claim_time_fcst="01:20:00"
    claim_time_mpassit_alltimes="03:30:00"
    claim_time_mpassit_onetime="00:50:00"

    job_exclusive_str=""

EOF

}

########################################################################

function check_hrrr_subdir {

    rstatus=0
    #
    # Check the external grib2 files availability for providing the system ICS/LBCs
    #

    mecho0 "Checking ${CYAN}${hrrrfile0}${NC} ... "
    if [[ -e ${hrrrfile0} ]]; then
        mecho0 "Use hrrr_sub_ics='${YELLOW}${hrrr_sub_ics}${NC}'"
    else
        althrrrfile=${hrrrfile0/postprd_mem00/mem}
        #mecho0n "Checking ${CYAN}${althrrrfile}${NC} ... "
        if [[ -e ${althrrrfile} ]]; then
            mecho0 "Use hrrr_sub_ics='${YELLOW}mem${NC}'"
            hrrr_sub_ics="mem"
            hrrrfile0="${althrrrfile}"
        else
            mecho0 "Missing  ${RED}${hrrrfile0}${NC}"
            (( rstatus++ ))
        fi
    fi

    #
    # Check lbc sub_directory
    #
    mecho0 "Checking ${CYAN}${hrrr_dir}/${eventdate}/${hrrr_time_lbc}${NC} .... "

    if [[ -d ${hrrr_dir}/${eventdate}/${hrrr_time_lbc} ]]; then
        #echo -e "${GREEN}Found${NC}"
        n=0
        pcount=$(find ${hrrr_dir}/${eventdate}/${hrrr_time_lbc}  -maxdepth 1 -name "postprd_mem00??" -type d | wc -l)
        mcount=$(find ${hrrr_dir}/${eventdate}/${hrrr_time_lbc}  -maxdepth 1 -name "mem??" -type d | wc -l)

        if [[ $pcount -eq 18 ]]; then
            hrrr_sub_lbc="postprd_mem00"
        elif [[ $mcount -eq 18 ]]; then
            hrrr_sub_lbc="mem"
        else
            mecho0 "Missing  ${RED}${hrrr_dir}/${eventdate}/${hrrr_time_lbc}/${hrrr_sub_lbc}??${NC}"
            (( rstatus++ ))
        fi
        mecho0 "Use hrrr_sub_lbc='${YELLOW}${hrrr_sub_lbc}${NC}'"
    else
        mecho0 "Missing  ${RED}${hrrr_dir}/${eventdate}/${hrrr_time_lbc}${NC}"
        (( rstatus++ ))
    fi
    echo ""
    return "${rstatus}"
}

########################################################################

function check_hrrr_files {
    #
    # Check the external grib2 files availability for providing the system ICS/LBCs
    #

    mecho0n "Checking ${CYAN}$hrrrfile0${NC} ... "
    if ls $hrrrfile0 > /dev/null 2>&1; then
        echo -e "${GREEN}Found${NC}"
    else
        echo -e "${RED}Missing${NC}"
        althrrrfile=${hrrrfile0/postprd_mem00/mem}
        mecho0n "Checking ${CYAN}${althrrrfile}${NC} ... "
        if ls $althrrrfile > /dev/null 2>&1; then
            echo -e "${GREEN}Found${NC}"
            hrrr_sub_ics="mem"
            hrrrfile0="${althrrrfile}"
        else
            echo -e "${RED}Missing${NC}"
        fi
    fi

    mecho0n "Checking ${CYAN}${hrrr_dir}/${eventdate}/${hrrr_time_ics}${NC} .... "
    if ls ${hrrr_dir}/${eventdate}/${hrrr_time_ics} > /dev/null 2>&1; then
        echo -e "${GREEN}Found${NC}"
        n=0
        for mdir in "${hrrr_dir}/${eventdate}/${hrrr_time_ics}/${hrrr_sub_ics}"??; do
            if (( n%4 == 0)); then echo ""; fi
            if [[ -d $mdir ]]; then
                subdir=$(basename $mdir)
                fcount=("$mdir"/wrfnat_hrrre_newse_mem00??_01.grib2)
                echo -ne "\t$subdir .... ${GREEN}${#fcount[@]}${NC}"
            else
                echo -ne "\t$(basename $mdir) ${RED}missing${NC}"
            fi
            ((n++))
        done
        echo -e "\n"
    else
        echo -e "${RED}Missing${NC}"
    fi

    mecho0n "Checking ${CYAN}${hrrr_dir}/${eventdate}/${hrrr_time_lbc}${NC} .... "

    if ls ${hrrr_dir}/${eventdate}/${hrrr_time_lbc} > /dev/null 2>&1; then
        echo -e "${GREEN}Found${NC}"
        for mdir in "${hrrr_dir}/${eventdate}/${hrrr_time_lbc}/${hrrr_sub_lbc}"??; do
            if (( n%4 == 0)); then echo ""; fi
            if [[ -d $mdir ]]; then
                subdir=$(basename $mdir)
                fcount=("$mdir"/wrfnat_pert_hrrr_mem00??_??.grib2)
                echo -ne "\t$subdir .... ${GREEN}${#fcount[@]}${NC}"
            else
                echo -ne "\t$(basename $mdir) ${RED}missing${NC}"
            fi
            ((n++))
        done
    else
        echo -e "${RED}Missing${NC}"
    fi
    echo -e "\n"
}

########################################################################

function check_obs_files {
    #
    # Check the PrepBufr files availability
    #
    eval "$(sed -n "/BUFR_DIR=/p" ${rootdir}/observations/prepbufr_wofs.sh)"
    mapfile -t my_array < <( ${rootdir}/observations/prepbufr_wofs.sh check ${eventdate} )
    #IFS=$'\n' read -r -d '' -a obsfiles < <(${rootdir}/observations/prepbufr_wofs.sh check ${eventdate} && printf '\0')
    read -r -a obsfiles <<< "${my_array[-1]}"
    echo -e "${DARK}observations/prepbufr_wofs.sh${NC}: Found ${GREEN}${my_array[-2]}${NC} PrepBufr files on ${BROWN}${eventdate}${NC} from ${LIGHT_BLUE}${BUFR_DIR}${NC}."
    n=0
    for fn in "${obsfiles[@]}"; do
        if (( n%4 == 0 )); then echo ""; fi
        if [[ "$fn" =~ "miss" ]]; then
            echo -ne "    ${RED}$fn${NC}"
        else
            echo -n "    $fn"
        fi
        ((n++))
    done
    echo -e "\n"

    #
    # Check the Mesonet files availability
    #
    eval "$(sed -n "/MESO_DIR=/p" ${rootdir}/observations/okmeso_15min.sh)"
    mapfile -t my_array < <( ${rootdir}/observations/okmeso_15min.sh check ${eventdate} )
    #IFS=$'\n' read -r -d '' -a obsfiles < <(${rootdir}/observations/okmeso_15min.sh check ${eventdate} && printf '\0')
    read -r -a obsfiles <<< "${my_array[-1]}"
    echo -e "${DARK}observations/okmeso_15min.sh${NC}: Found ${GREEN}${my_array[-2]}${NC} Mesonet files on ${BROWN}${eventdate}${NC} from ${LIGHT_BLUE}${MESO_DIR}${NC}."
    n=0
    for fn in "${obsfiles[@]}"; do
        if (( n%3 == 0 )); then echo ""; fi
        if [[ "$fn" =~ "miss" ]]; then
            echo -ne "    ${RED}$fn${NC}"
        else
            echo -n "    $fn"
        fi
        ((n++))
    done
    echo -e "\n"

    #
    # Check the CWP files availability
    #
    eval "$(sed -n "/srcdir=/p" ${rootdir}/observations/run_cwpobs.sh)"
    mapfile -t my_array < <( ${rootdir}/observations/run_cwpobs.sh check ${eventdate} )
    #IFS=$'\n' read -r -d '' -a obsfiles < <(${rootdir}/observations/prepbufr_wofs.sh check ${eventdate} && printf '\0')
    read -r -a obsfiles <<< "${my_array[-1]}"
    # shellcheck disable=SC2154
    echo -e "${DARK}observations/run_cwpobs.sh${NC}: Found ${GREEN}${my_array[-2]}${NC} CWP files on ${BROWN}${eventdate}${NC} from ${LIGHT_BLUE}${srcdir}${NC}."
    n=0
    for fn in "${obsfiles[@]}"; do
        if (( n%4 == 0 )); then echo ""; fi
        if [[ "$fn" =~ "-missing" ]]; then
            echo -ne "    ${RED}$fn${NC}  "
        else
            echo -n "    $fn"
        fi
        ((n++))
    done
    echo -e "\n"

    #
    # Check the GOES files availability
    #
    eval "$(sed -n "/srcdir=/p" ${rootdir}/observations/run_radiance.sh)"
    mapfile -t my_array < <( ${rootdir}/observations/run_radiance.sh check ${eventdate} )
    #IFS=$'\n' read -r -d '' -a obsfiles < <(${rootdir}/observations/run_radiance.sh check ${eventdate} && printf '\0')
    read -r -a obsfiles <<< "${my_array[-1]}"
    echo -e "${DARK}observations/run_radiance.sh${NC}: Found ${GREEN}${my_array[-2]}${NC} Radiance files on ${BROWN}${eventdate}${NC} from ${LIGHT_BLUE}${srcdir}${NC}."
    n=0
    for fn in "${obsfiles[@]}"; do
        if (( n%4 == 0 )); then echo ""; fi
        if [[ "$fn" =~ "-missing" ]]; then
            echo -ne "    ${RED}$fn${NC}"
        else
            echo -n "    $fn"
        fi
        ((n++))
    done
    echo -e "\n"

    #
    # Check the radar files availability
    #
    eval "$(sed -n "/srcdir=/p" ${rootdir}/observations/link_radar.sh)"
    mapfile -t my_array < <( ${rootdir}/observations/link_radar.sh check ${eventdate} )
    #IFS=$'\n' read -r -d '' -a obsfiles < <(${rootdir}/observations/link_radar.sh check ${eventdate} && printf '\0')
    read -r -a obsfiles <<< "${my_array[-3]}"
    echo -e "${DARK}observations/link_radar.sh${NC}: Found ${GREEN}${my_array[-4]}${NC} Reflectivity files on ${BROWN}${eventdate}${NC} from ${LIGHT_BLUE}${srcdir}${NC}."
    n=0
    for fn in "${obsfiles[@]}"; do
        if (( n%4 == 0 )); then echo ""; fi
        if [[ "$fn" =~ "missing:" ]]; then
            echo -ne "    ${RED}$fn${NC}"
        else
            echo -n "    $(basename $fn)"
        fi
        ((n++))
    done
    echo -e "\n"

    #
    # Check the radial velocity files availability
    #

    declare -A velfiles=()
    typeset2array "${my_array[-1]}" "velfiles"

    echo -e "${DARK}observations/link_radar.sh${NC}: Found ${GREEN}${my_array[-2]}${NC} Radial Velocity files on ${BROWN}${eventdate}${NC} from ${LIGHT_BLUE}${srcdir}${NC}."
    echo ""

    declare -a radnames
    for fn in "${!velfiles[@]}"; do
        string2array "${velfiles[$fn]}" "radnames"
        if [[ ${#radnames[@]} -ne 0 ]]; then
            if [[ -z $common ]]; then
                common=("${radnames[@]}")
            else
                mapfile -t common < <( intersection "${common[*]}" "${radnames[*]}" )
            fi
        fi
    done

    echo -e "    Common Radars: ${CYAN}${common[*]}${NC} (${GREEN}${#common[@]}${NC})"
    echo ""

    for fn in "${!velfiles[@]}"; do
        string2array "${velfiles[$fn]}" "radnames"

        if [[ ${#radnames[@]} -eq 0 ]]; then
            echo -e "    $fn: ${RED}Missing${NC}"
        else
            mapfile -t radunique < <(setsubtract "${radnames[*]}" "${common[*]}" )
            echo -e "    $fn: ${radunique[*]} (${GREEN}${#radnames[@]}${NC})"
        fi
    done | sort -n -k3
}

#%%%#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#
# Default settings
#
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#@ MAIN

source "${scpdir}/Common_Utilfuncs.sh" || exit $?

relative_path=true

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

[[ -v args["damode"] ]]    && damode="${args['damode']}"     || damode="init"
[[ -v args["fcstmode"] ]]  && fcstmode="${args['fcstmode']}" || fcstmode="${damode}"

[[ -v args["domname"] ]]    && domname="${args['domname']}"   || domname="wofs_mpas"
[[ -v args["affix"] ]]      && affix="${args['affix']}"       || affix=""

[[ -v args["hpcaccount"] ]]   && hpcaccount="${args['hpcaccount']}" || hpcaccount=""
[[ -v args["cen_lat"] ]]      && cen_lat="${args['cen_lat']}"       || cen_lat=""
[[ -v args["cen_lon"] ]]      && cen_lon="${args['cen_lon']}"       || cen_lon=""

#-----------------------------------------------------------------------
#
# Get jobs to run
#
#-----------------------------------------------------------------------

[[ -v args["jobs"] ]] && read -r -a jobs <<< "${args['jobs']}" || jobs=(geogrid ungrib_hrrr projectHexes meshplot_py static)

#-----------------------------------------------------------------------
#
# Set up working environment
#
#-----------------------------------------------------------------------

source "${scpdir}/Site_Runtime.sh" || exit $?

setup_machine "${args['machine']}" "$rootdir" true true

[[ $dorun == false ]]    && runcmd="echo $runcmd"

# shellcheck disable=SC2154
[[ -v args["WORKDIR"] ]] && WORKDIR=${args["WORKDIR"]} || WORKDIR="${workdirDF}"
[[ -v args["TEMPDIR"] ]] && TEMPDIR=${args["TEMPDIR"]} || TEMPDIR="${rootdir}/templates"
[[ -v args["FIXDIR"] ]]  && FIXDIR=${args["FIXDIR"]}   || FIXDIR="${rootdir}/fix_files"
[[ -v args["EXEDIR"] ]]  && EXEDIR=${args["EXEDIR"]}   || EXEDIR="${rootdir}/exec"

[[ -v args["level_file"] ]] && fixed_level="${args['level_file']}"  || fixed_level="${FIXDIR}/L60.txt"

#-----------------------------------------------------------------------
#
# Set Event Date and Time
#
#-----------------------------------------------------------------------
[[ -v args["eventdate"] ]] && eventdate="${args['eventdate']}" || eventdate="$eventdateDF"
[[ -v args["eventtime"] ]] && eventtime="${args['eventtime']}" || eventtime="1500"

[[ -v args["caseconfig"] ]] && caseconfig="${args['caseconfig']}" || caseconfig="${WORKDIR}/config.${eventdate}${affix}"

#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#
# Perform each task
#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#% ENTRY

echo    ""
echo -e "---- Jobs (${YELLOW}$$${NC}) started at $(date +'%m-%d %H:%M:%S (%Z)') on host ${LIGHT_RED}$(hostname)${NC} ----\n"
echo -e "  Event  date: ${WHITE}$eventdate${NC} ${YELLOW}${eventtime}${NC}"
echo -e "  ROOT    dir: ${rootdir}${BROWN}/scripts${NC}"
echo -e "  TEMP    dir: ${PURPLE}${TEMPDIR}${NC}"
echo -e "  FIXED   dir: ${DARK}${FIXDIR}${NC}"
echo -e "  EXEC    dir: ${GREEN}${EXEDIR}${NC}"
echo -e "  Working dir: ${WHITE}${WORKDIR}${LIGHT_BLUE}/${eventdate}${NC}"
echo -ne "  Domain name: ${RED}$domname${NC};  MP scheme: ${CYAN}mp_nssl2m${NC}"

if [[ -n ${cen_lat} || -n ${cen_lon} ]]; then
    echo -e "; Domain Center: ${WHITE}${cen_lat}${NC},${WHITE}${cen_lon}${NC}"
else
    echo " "
fi
echo " "

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
hrrr_sub_ics="postprd_mem00"         # + 2-digit member string
hrrr_sub_lbc="postprd_mem00"         # + 2-digit member string

hrrrfile0="${hrrr_dir}/${eventdate}/${hrrr_time_ics}/${hrrr_sub_ics}01/wrfnat_hrrre_newse_mem0001_01.grib2"

EXTINVL_STR=$(printf "%02d:00:00" $((EXTINVL/3600)) )

if [[ " ${jobs[*]} " =~ [[:space:]]check(bg|obs)*[[:space:]]  ]]; then
    if [[ " ${jobs[*]} " == " check " ]]; then
        checkmodel=true
        checkobs=true
    fi

    if [[ " ${jobs[*]} " == " checkbg " || $checkmodel == true ]]; then
        check_hrrr_files
    fi

    if [[ " ${jobs[*]} " == " checkobs " || $checkobs == true ]]; then
        check_obs_files
    fi
    exit 0
fi

if $dorun && [ " ${jobs[*]} " != " clean " ] && ! check_hrrr_subdir; then
    exit $?
fi

starttime_str=$(date -u -d "${eventdate} ${eventtime}" +%Y-%m-%d_%H:%M:%S)

rundir="$WORKDIR/${eventdate}"

if [[ ! -d $rundir ]]; then
    mkdir -p "$rundir"
fi

jobname="${eventdate:4:4}"

#
# write runtime configuration file
#
if [[ " ${jobs[*]} " != " clean " ]]; then
    write_config "$caseconfig"
fi

if [[ " ${jobs[*]} " == " setup " ]]; then exit 0; fi

#
# Start the forecast driver
#
if [[ " ${jobs[*]} " =~ " rotate " ]]; then
    mesh="rotate"        # mesh generation method, rotate
else
    mesh="project"       # mesh generation method, project, DEFAULT
fi

declare -A jobargs=([geogrid]="${rundir}/geo_${domname##*_}"            \
                    [createWOFS]="geo_${domname##*_}/done.geogrid"      \
                    [projectHexes]="geo_${domname##*_}/done.geogrid"      \
                    [rotate]="geo_${domname##*_}/done.geogrid"          \
                    [meshplot_ncl]="$domname/done.rotate"                         \
                    [meshplot_py]="$domname/done.${mesh} $domname/$domname.grid.nc" \
                    [static]="$domname/done.${mesh} ungrib/done.ungrib" \
                    [ungrib_hrrr]="${hrrrfile0}"                        \
                    [clean]="geogrid static createWOFS projectHexes"    \
                   )

for job in "${jobs[@]}"; do
    if [[ $verb -eq 1 ]]; then
        echo " "
        echo "    run_$job ${jobargs[$job]}"
    fi

    "run_$job" ${jobargs[$job]}
done

echo " "
echo "==== $0 done $(date +'%m-%d %H:%M:%S (%Z)') ===="
echo " "

exit 0
