#!/bin/bash

rootdir="/lfs4/NAGAPE/hpc-wof1/ywang/MPAS"
eventdateDF=$(date +%Y%m%d)

#-----------------------------------------------------------------------
#
# Required files from ROOTDIR
#
# 0. module file in /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/modules
#     build_jet_intel
#
#   NOTE: If users make a change or copy this file, they should modify all
#         *.slurm file in templates for directory and/or name.
#
# 1. exec                                   # The executables
#     init_atmosphere_model
#     atmosphere_model.single
#     mpassit
#     ungrib.exe
#     geogrid.exe
#     unipost.exe
#
# 2. templates                              # templates for this scripts
#    README
#
#    2.1 WPS run-time files for program ungrib & geogrid
#        Vtable.GFS
#        Vtable.raphrrr
#        GEOGRID.TBL.ARW
#
#    2.2 tables for Thompson cloud microphysics scheme [optional]
#        MP_THOMPSON_QIautQS_DATA.DBL
#        MP_THOMPSON_QRacrQG_DATA.DBL
#        MP_THOMPSON_QRacrQS_DATA.DBL
#        MP_THOMPSON_freezeH2O_DATA.DBL
#
#    2.3 MPASS run-time static files
#        stream_list.atmosphere.diagnostics
#        stream_list.atmosphere.output
#        stream_list.atmosphere.surface
#
#        CAM_ABS_DATA.DBL
#        CAM_AEROPT_DATA.DBL
#        GENPARM.TBL
#        LANDUSE.TBL
#        OZONE_DAT.TBL
#        OZONE_LAT.TBL
#        OZONE_PLEV.TBL
#        RRTMG_LW_DATA
#        RRTMG_LW_DATA.DBL
#        RRTMG_SW_DATA
#        RRTMG_SW_DATA.DBL SOILPARM.TBL
#        VEGPARM.TBL
#
#    2.4 SLURM scripts on Jet
#        run_init.slurm
#        run_lbc.slurm
#        run_mpas.slurm
#        run_mpassit.slurm
#        run_static.slurm
#        run_ungrib.slurm
#        run_geogrid.slurm
#        run_upp.slurm
#
#    2.5 Limited-area SCVT meshes
#        wofs_conus.graph.info
#        wofs_conus.graph.info.part.1200
#        wofs_conus.graph.info.part.800
#        wofs_conus.grid.nc
#
#    2.6 Parameters for program MPASSIT
#        parm/diaglist
#        parm/histlist_2d
#        parm/histlist_3d
#        parm/histlist_soil
#
# 3. scripts                                # this scripts
#    3.1 run_MPAS_hrrr.sh
#    3.1 run_MPAS_gfs.sh
#
# 4. UPP_KATE_kjet (copied and rebuild from /lfs4/NAGAPE/wof/wrfout_3km-1km/UPP_KATE_kjet)
#
#    NOTE: Due to a library issue, I cannot use the original executable directly.
#          You can change variable "jobargs[upp]" below and modify file
#          templates/run_upp.slurm accordingly to use whatever UPP directory
#          and its environment settings.
#
# 5. Parameters for program unipost.exe
#        WRFV4.0/ETAMPNEW_DATA
#        WRFV4.0/ETAMPNEW_DATA.expanded_rain
#
# 6. /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/WPS_GEOG
#
#    NOTE: It can be anywhere, but should modify "run_geogrid"
#          and "run_static" below whenever the directory is changed.
#
# INSTRUCTIONS:
#
#  Use existing domain (wofs_conus)
#     1. Copy these directories to rootdir
#        modules
#        exec
#        UPP_KATE_kjet [optional, see above]
#        scripts
#        templates (change all *.slurm for the module file, see above)
#
#     2. make a run directory under rootdir
#        run_dirs
#
#     3. Copy existing domain directories $rootdir/run_dirs/wofs_conus & geo_conus to
#        your run_dirs
#
#     4. run_MPAS_hrrr.sh [YYYYmmddHH] [run_dirs] [jobnames]
#
#-----------------------------------------------------------------------

function usage {
    echo " "
    echo "    USAGE: $0 [options] DATETIME [WORKDIR] [JOBS]"
    echo " "
    echo "    PURPOSE: Run MPAS on Jet."
    echo " "
    echo "    DATETIME - Case date and time in YYYYMMDD"
    echo "               Default for today"
    echo "    WORKDIR  - Run Directory on Jet"
    echo "    JOBS     - One or more jobs from [static,ungrib,init,lbc,mpas]"
    echo "               Default all jobs in sequence"
    echo " "
    echo "    OPTIONS:"
    echo "              -h              Display this message"
    echo "              -n              Show command to be run only"
    echo "              -v              Verbose mode"
    echo "              -k  [0,1,2]     Keep working directory if exist, 0- as is; 1- overwrite; 2- make a backup as xxxx.bak?"
    echo "                              Default is 0 for ungrib, mpassit, upp and 1 for others"
    echo "              -t  DIR         Template directory for runtime files"
    echo "              -d  wofs_conus  Domain name to be used"
    echo " "
    echo "   DEFAULTS:"
    echo "              eventdt = $eventdateDF"
    echo "              rootdir = $rootdir"
    echo "              WORKDIR = $rootdir/run_dirs"
    echo "              TEMPDIR = $rootdir/templates"
    echo " "
    echo "                                     -- By Y. Wang (2022.09.27)"
    echo " "
    exit $1
}
########################################################################

function mkwrkdir {

    if [[ $# -ne 2 ]]; then
        echo "ERROR: argument in mkwrkdir, get \"$*\"."
        exit 0
    fi

    mydir=$1
    backup=$2

    if [[ -d $mydir ]]; then
        if [[ $backup -eq 1 ]]; then
            rm -rf $mydir
        elif [[ $backup -eq 2 ]]; then
            basedir=$(dirname $mydir)
            namedir=$(basename $mydir)
            bakno=0
            bakdir="$basedir/${namedir}.bak$bakno"
            while [[ -d $bakdir ]]; do
                let bakno++
                bakdir="$basedir/${namedir}.bak$bakno"
            done

            for ((i=$bakno;i>0;i--)); do
                j=$((i-1))
                olddir="$basedir/${namedir}.bak$j"
                bakdir="$basedir/${namedir}.bak$i"
                echo "Moving $olddir --> $bakdir ..."
                mv $olddir $bakdir
            done
            bakdir="$basedir/${namedir}.bak0"
            echo "Baking $mydir --> $bakdir ..."
            mv $mydir $bakdir
        fi
    fi
    mkdir -p $mydir
}

########################################################################

function link_grib {
    alpha=( A B C D E F G H I J K L M N O P Q R S T U V W X Y Z )
    i1=0
    i2=0
    i3=0

    rm -f GRIBFILE.??? >& /dev/null

    for f in ${*}; do
       ln -sf ${f} GRIBFILE.${alpha[$i3]}${alpha[$i2]}${alpha[$i1]}
       let i1++

       if [[ $i1 -ge 26 ]]; then
          let i1=0
          let i2++
         if [[ $i2 -ge 26 ]]; then
            let i2=0
            let i3++
            if [[ $i3 -ge 26 ]]; then
               echo "RAN OUT OF GRIB FILE SUFFIXES!"
            fi
         fi
       fi
    done
}
########################################################################

function run_geogrid {

    wrkdir=$1
    mkwrkdir $wrkdir $overwrite
    cd $wrkdir

    ln -sf ${TEMPDIR}/GEOGRID.TBL.ARW GEOGRID.TBL

    cat <<EOF > namelist.wps
&share
  wrf_core = 'ARW',
  max_dom = 1,
  start_date = '2021-04-28_15:00:00',
  end_date = '2021-04-28_16:00:00',
  interval_seconds = 3600,
  io_form_geogrid = 2,
  opt_output_from_geogrid_path = './',
/

&geogrid
  parent_id = 1,
  parent_grid_ratio = 1,
  i_parent_start = 1,
  j_parent_start = 1,
  e_we = 1651,
  e_sn = 921,
  geog_data_res = '30s',
  dx = 3000.0,
  dy = 3000.0,
  map_proj = 'lambert',
  ref_lat = 38.5,
  ref_lon = -97.5,
  truelat1 = 38.5,
  truelat2 = 38.5,
  stand_lon = -97.5
  geog_data_path = '/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/WPS_GEOG/',
  opt_geogrid_tbl_path = './',
/

&ungrib
/

&metgrid
/
EOF

    #
    # Create job script and submit it
    #
    geoname=${domname/*_/geo_}
    jobscript="run_geogrid.slurm"
    sed "s/ACCOUNT/$account/g;s/PARTION/${partition}/;s/JOBNAME/geogrid_${geoname}/;s/NOPART/$npepost/" $TEMPDIR/$jobscript > $jobscript
    sed -i "s#WRKDIR#$wrkdir#g;s#EXEDIR#${exedir}#" $jobscript
    echo -n "Submitting $jobscript .... "
    $runcmd $jobscript
}

########################################################################

function run_static {
    wrkdir=$1
    mkwrkdir $wrkdir $overwrite
    cd $wrkdir

    cp $TEMPDIR/$domname.graph.info      .
    cp $TEMPDIR/$domname.grid.nc         .

    cat <<EOF > namelist.init_atmosphere
&nhyd_model
    config_init_case = 7
    config_start_time = '${starttime_str}'
    config_stop_time = '${starttime_str}'
    config_theta_adv_order = 3
    config_coef_3rd_order = 0.25
/
&dimensions
    config_nvertlevels = 1
    config_nsoillevels = 1
    config_nfglevels = 1
    config_nfgsoillevels = 1
/
&data_sources
    config_geog_data_path = '/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/WPS_GEOG/'
    config_met_prefix = 'CFSR'
    config_sfc_prefix = 'SST'
    config_fg_interval = $((EXTINVL*3600))
    config_landuse_data = 'MODIFIED_IGBP_MODIS_NOAH'
    config_topo_data = 'GMTED2010'
    config_vegfrac_data = 'MODIS'
    config_albedo_data = 'MODIS'
    config_maxsnowalbedo_data = 'MODIS'
    config_supersample_factor = 1
    config_use_spechumd = false
/
&vertical_grid
    config_ztop = 30000.0
    config_nsmterrain = 1
    config_smooth_surfaces = true
    config_dzmin = 0.3
    config_nsm = 30
    config_tc_vertical_grid = true
    config_blend_bdy_terrain = false
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
                  filename_template="${domname}.grid.nc"
                  input_interval="initial_only" />

<immutable_stream name="output"
                  type="output"
                  filename_template="${domname}.static.nc"
                  io_type="netcdf"
                  packages="initial_conds"
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
    jobscript="run_static.slurm"
    sed "s/ACCOUNT/$account/g;s/PARTION/${partition_static}/;s/JOBNAME/static_${domname}/" $TEMPDIR/$jobscript > $jobscript
    #sed -i "s#WRKDIR#$wrkdir#g;s#EXEDIR#${rootdir}/MPAS-Model#" $jobscript
    sed -i "s#WRKDIR#$wrkdir#g;s#EXEDIR#${exedir}#" $jobscript
    echo -n "Submitting $jobscript .... "
    $runcmd $jobscript
}

########################################################################

function run_ungrib {
    grib_dir=$1

    wrkdir=$rundir/ungrib
    mkwrkdir $wrkdir 0
    cd $wrkdir

    julday=$(date -d "$eventdate ${eventtime}:00" +%y%j%H)

    if [[ -f ungrib.running || -f done.ungrib || -f queue.ungrib ]]; then
        return 0                   # skip
    else
        gfsfiles=()
        for ((h=0;h<=fcst_hours;h+=EXTINVL)); do
            hstr=$(printf "%02d" $h)
            gfsfiles+=($grib_dir/${julday}0000$hstr)
        done

        for fn in ${gfsfiles[@]}; do
            echo "GFS file: $fn"
            while [[ ! -f $fn ]]; do
                if [[ $verb -eq 1 ]]; then
                    echo "Waiting for $fn ..."
                fi
                sleep 10
            done
        done

        link_grib ${gfsfiles[@]}

        ln -sf $rootdir/WPS_SRC/ungrib/Variable_Tables/Vtable.GFS Vtable

        cat << EOF > namelist.wps
&share
 wrf_core = 'ARW',
 max_dom = 1,
 start_date = '${starttime_str}',
 end_date = '${stoptime_str}',
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
        jobscript="run_ungrib.slurm"
        sed "s/ACCOUNT/$account/g;s/PARTION/${partition}/;s/JOBNAME/ungrib_${jobname}/" $TEMPDIR/$jobscript > $jobscript
        sed -i "s#WRKDIR#$wrkdir#g;s#EXEDIR#${exedir}#" $jobscript
        echo -n "Submitting $jobscript .... "
        $runcmd $jobscript
        if [[ $runcmd == "sbatch" ]]; then
            touch queue.ungrib
        fi
    fi
}

########################################################################

function run_init {

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

    for cond in ${conditions[@]}; do
        echo "Checking: $cond"
        while [[ ! -e $cond ]]; do
            if [[ $verb -eq 1 ]]; then
                echo "Waiting for file: $cond"
            fi
            sleep 10
        done
    done

    wrkdir=$rundir/init
    mkwrkdir $wrkdir $overwrite
    cd $wrkdir

    ln -sf $rundir/ungrib/${EXTHEAD}:${starttime_str:0:13} .
    ln -sf $WORKDIR/$domname/$domname.static.nc .
    ln -sf $TEMPDIR/$domname.graph.info.part.${npeics} .

    cat << EOF > namelist.init_atmosphere
&nhyd_model
    config_init_case = 7
    config_start_time = '${starttime_str}'
    config_stop_time = '${stoptime_str}'
    config_theta_adv_order = 3
    config_coef_3rd_order = 0.25
/
&dimensions
    config_nvertlevels = 55
    config_nsoillevels = 4
    config_nfglevels = ${EXTNFGL}
    config_nfgsoillevels = ${EXTNFLS}
/
&data_sources
    config_geog_data_path = '/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/WPS_GEOG/'
    config_met_prefix = '${EXTHEAD}'
    config_sfc_prefix = 'SST'
    config_fg_interval = $((EXTINVL*3600))
    config_landuse_data = 'MODIFIED_IGBP_MODIS_NOAH'
    config_topo_data = 'GMTED2010'
    config_vegfrac_data = 'MODIS'
    config_albedo_data = 'MODIS'
    config_maxsnowalbedo_data = 'MODIS'
    config_supersample_factor = 1
    config_use_spechumd = false
/
&vertical_grid
    config_ztop = 30000.0
    config_nsmterrain = 1
    config_smooth_surfaces = true
    config_dzmin = 0.3
    config_nsm = 30
    config_tc_vertical_grid = true
    config_blend_bdy_terrain = true
/
&interpolation_control
    config_extrap_airtemp = 'linear'
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
                  filename_template="$domname.init.nc"
                  io_type="${ICSIOTYPE}"
                  packages="initial_conds"
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
                  output_interval="${EXTINVL_STR}" />

</streams>
EOF
    #
    # Create job script and submit it
    #
    jobscript="run_init.slurm"
    sed "s/ACCOUNT/$account/g;s/PARTION/${partition}/;s/NOPART/$npeics/;s/JOBNAME/init_${jobname}/" $TEMPDIR/$jobscript > $jobscript
    sed -i "s#WRKDIR#$wrkdir#g;s#EXEDIR#${exedir}#" $jobscript
    echo -n "Submitting $jobscript .... "
    $runcmd $jobscript
}

########################################################################

function run_lbc {

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

    for cond in ${conditions[@]}; do
        echo "Checking: $cond"
        while [[ ! -e $cond ]]; do
            if [[ $verb -eq 1 ]]; then
                echo "Waiting for file: $cond"
            fi
            sleep 10
        done
    done

    wrkdir=$rundir/lbc
    mkwrkdir $wrkdir $overwrite
    cd $wrkdir

    ln -sf $rundir/ungrib/${EXTHEAD}* .
    ln -sf $rundir/init/$domname.init.nc .
    ln -sf $TEMPDIR/$domname.graph.info.part.${npeics} .

    cat << EOF > namelist.init_atmosphere
&nhyd_model
    config_init_case = 9
    config_start_time = '${starttime_str}'
    config_stop_time = '${stoptime_str}'
    config_theta_adv_order = 3
    config_coef_3rd_order = 0.25
/
&dimensions
    config_nvertlevels = 55
    config_nsoillevels = 4
    config_nfglevels = ${EXTNFGL}
    config_nfgsoillevels = ${EXTNFLS}
/
&data_sources
    config_geog_data_path = '/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/WPS_GEOG/'
    config_met_prefix = '${EXTHEAD}'
    config_sfc_prefix = 'SST'
    config_fg_interval = $((EXTINVL*3600))
    config_landuse_data = 'MODIFIED_IGBP_MODIS_NOAH'
    config_topo_data = 'GMTED2010'
    config_vegfrac_data = 'MODIS'
    config_albedo_data = 'MODIS'
    config_maxsnowalbedo_data = 'MODIS'
    config_supersample_factor = 1
    config_use_spechumd = false
/
&vertical_grid
    config_ztop = 30000.0
    config_nsmterrain = 1
    config_smooth_surfaces = true
    config_dzmin = 0.3
    config_nsm = 30
    config_tc_vertical_grid = true
    config_blend_bdy_terrain = true
/
&interpolation_control
    config_extrap_airtemp = 'linear'
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
                  filename_template="$domname.init.nc"
                  input_interval="initial_only" />

<immutable_stream name="output"
                  type="output"
                  filename_template="$domname.none.nc"
                  io_type="netcdf"
                  packages="initial_conds"
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
                  io_type="${ICSIOTYPE}"
                  output_interval="${EXTINVL_STR}" />

</streams>
EOF
    #
    # Create job script and submit it
    #
    jobscript="run_lbc.slurm"
    sed "s/ACCOUNT/$account/g;s/PARTION/${partition}/;s/NOPART/$npeics/;s/JOBNAME/lbc_${jobname}/" $TEMPDIR/$jobscript > $jobscript
    sed -i "s#WRKDIR#$wrkdir#g;s#EXEDIR#${exedir}#" $jobscript
    echo -n "Submitting $jobscript .... "
    $runcmd $jobscript
}

########################################################################

function run_mpas {
    #
    # Waiting for job conditions
    #
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

    for cond in ${conditions[@]}; do
        echo "Checking: $cond"
        while [[ ! -e $cond ]]; do
            if [[ $verb -eq 1 ]]; then
                echo "Waiting for file: $cond"
            fi
            sleep 10
        done
    done

    #
    # Build working directory
    #
    wrkdir=$rundir/fcst
    mkwrkdir $wrkdir $overwrite
    cd $wrkdir

    ln -sf $rundir/lbc/${domname}.lbc.* .
    ln -sf $rundir/init/$domname.init.nc .
    ln -sf $TEMPDIR/$domname.graph.info.part.${npefcst} .

    streamlists=(stream_list.atmosphere.diagnostics stream_list.atmosphere.output stream_list.atmosphere.surface)
    for fn in ${streamlists[@]}; do
        cp -f ${staticdir}/$fn .
    done

    datafiles=(  CAM_ABS_DATA.DBL  CAM_AEROPT_DATA.DBL GENPARM.TBL       LANDUSE.TBL    \
                 OZONE_DAT.TBL     OZONE_LAT.TBL       OZONE_PLEV.TBL    RRTMG_LW_DATA  \
                 RRTMG_LW_DATA.DBL RRTMG_SW_DATA       RRTMG_SW_DATA.DBL SOILPARM.TBL   \
                 VEGPARM.TBL )

    for fn in ${datafiles[@]}; do
        ln -sf ${staticdir}/$fn .
    done

    thompson_tables=( MP_THOMPSON_QRacrQG_DATA.DBL   MP_THOMPSON_QRacrQS_DATA.DBL   \
                      MP_THOMPSON_freezeH2O_DATA.DBL MP_THOMPSON_QIautQS_DATA.DBL )

    for fn in ${thompson_tables[@]}; do
        ln -sf ${TEMPDIR}/$fn .
    done

    fcsthour_str=$(printf "%02d" $fcst_hours)

    cat << EOF > namelist.atmosphere
&nhyd_model
    config_time_integration_order   = 2
    config_dt                       = 15
    config_start_time               = '${starttime_str}'
    config_run_duration             = '${fcsthour_str}: 00: 00'
    config_split_dynamics_transport = true
    config_number_of_sub_steps      = 2
    config_dynamics_split_steps     = 3
    config_h_mom_eddy_visc2         = 0.0
    config_h_mom_eddy_visc4         = 0.0
    config_v_mom_eddy_visc2         = 0.0
    config_h_theta_eddy_visc2       = 0.0
    config_h_theta_eddy_visc4       = 0.0
    config_v_theta_eddy_visc2       = 0.0
    config_horiz_mixing             = '2d_smagorinsky'
    config_len_disp                 = 3000.0
    config_visc4_2dsmag             = 0.05
    config_w_adv_order              = 3
    config_theta_adv_order          = 3
    config_scalar_adv_order         = 3
    config_u_vadv_order             = 3
    config_w_vadv_order             = 3
    config_theta_vadv_order         = 3
    config_scalar_vadv_order        = 3
    config_scalar_advection         = true
    config_positive_definite        = false
    config_monotonic                = true
    config_coef_3rd_order           = 0.25
    config_epssm                    = 0.1
    config_smdiv                    = 0.1
/
&damping
    config_zd                        = 22000.0
    config_xnutr                     = 0.2
/
&limited_area
    config_apply_lbcs                = true
/
&io
    config_pio_num_iotasks           = NNNODE
    config_pio_stride                = NNCORE
/
&decomposition
    config_block_decomp_file_prefix  = '${domname}.graph.info.part.'
/
&restart
    config_do_restart                = false
/
&printout
    config_print_global_minmax_vel   = true
    config_print_detailed_minmax_vel = false
/
&IAU
    config_IAU_option                = 'off'
    config_IAU_window_length_s       = 21600.
/
&physics
    config_sst_update                = false
    config_sstdiurn_update           = false
    config_deepsoiltemp_update       = false
    config_radtlw_interval           = '00: 30: 00'
    config_radtsw_interval           = '00: 30: 00'
    config_bucket_update             = 'none'
    config_physics_suite             = 'convection_permitting'
    config_microp_scheme             = 'mp_nssl2m'
/
&soundings
    config_sounding_interval         = 'none'
/
EOF

    cat << EOF > streams.atmosphere
<streams>
<immutable_stream name="input"
                  type="input"
                  filename_template="${domname}.init.nc"
                  input_interval="initial_only" />

<immutable_stream name="restart"
                  type="input;output"
                  filename_template="${domname}.restart.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
                  io_type="${OUTIOTYPE}"
                  input_interval="initial_only"
                  output_interval="61:00:00" />

<stream name="output"
        type="output"
        filename_template="${domname}.history.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
        io_type="${OUTIOTYPE}"
        output_interval="${OUTINVL_STR}" >

	<file name="stream_list.atmosphere.output"/>
</stream>

<stream name="diagnostics"
        type="output"
        filename_template="${domname}.diag.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
        io_type="${OUTIOTYPE}"
        output_interval="${OUTINVL_STR}" >

	<file name="stream_list.atmosphere.diagnostics"/>
</stream>

<stream name="surface"
        type="input"
        filename_template="${domname}.sfc_update.nc"
        filename_interval="none"
        input_interval="none" >

	<file name="stream_list.atmosphere.surface"/>
</stream>

<immutable_stream name="iau"
                  type="input"
                  filename_template="${domname}.AmB.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
                  filename_interval="none"
                  packages="iau"
                  input_interval="initial_only" />

<immutable_stream name="lbc_in"
                  type="input"
                  filename_template="${domname}.lbc.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
                  filename_interval="input_interval"
                  packages="limited_area"
                  input_interval="${EXTINVL_STR}" />

</streams>
EOF
    #
    # Create job script and submit it
    #
    jobscript="run_mpas.slurm"
    sed "s/ACCOUNT/$account/g;s/PARTION/${partition}/;s/NOPART/$npefcst/;s/JOBNAME/mpas_${jobname}/" $TEMPDIR/$jobscript > $jobscript
    sed -i "s#WRKDIR#$wrkdir#g;s#EXEDIR#${exedir}#" $jobscript
    echo -n "Submitting $jobscript .... "
    $runcmd $jobscript
}

########################################################################

function run_mpassit {
    #
    # Build working directory
    #
    wrkdir=$rundir/mpassit
    mkwrkdir $wrkdir 0
    cd $wrkdir

    ln -sf $TEMPDIR/parm/* .

    for ((h=0;h<=$fcst_hours;h+=$EXTINVL)); do
        hstr=$(printf "%02d" $h)
        fcst_time_str=$(date -d "$eventdate ${eventtime}:00 $h hours" +%Y-%m-%d_%H.%M.%S)

        histfile="$rundir/fcst/${domname}.history.${fcst_time_str}.nc"
        diagfile="$rundir/fcst/${domname}.diag.${fcst_time_str}.nc"

        if [[ -f done.mpassit$hstr || -f running.mpassit$hstr || -f queue.mpassit$hstr ]]; then
            continue               # already done, is running or is in queue, skip this hour
        fi

        for fn in $histfile $diagfile; do
            echo "Checking: $fn ..."
            while [[ ! -f $fn ]]; do
                if [[ $jobsfromcmd -eq 1 ]]; then
                    #return 0
                    continue 3
                fi

                if [[ $verb -eq 1 ]]; then
                    echo "Waiting for $fn ..."
                fi
                sleep 10
            done
            fileage=$(( $(date +%s) - $(stat -c %Y -- "$fn") ))
            if [[ $fileage -lt 30 ]]; then
                sleep 30
            fi
        done

        nmlfile="namelist.fcst_$hstr"
        cat << EOF > $nmlfile
&config
    grid_file_input_grid = "$rundir/init/${domname}.init.nc"
    hist_file_input_grid = "$histfile"
    diag_file_input_grid = "$diagfile"
    file_target_grid     = "$WORKDIR/${domname/*_/geo_}/geo_em.d01.nc"
    output_file          = "$wrkdir/MPAS-A_out.${fcst_time_str}.nc"
    interp_diag          = .true.
    interp_hist          = .true.
    wrf_mod_vars         = .true.
    esmf_log             = .false.
/
EOF
        #
        # Create job script and submit it
        #
        jobscript="run_mpassit_$hstr.slurm"
        sed "s/ACCOUNT/$account/g;s/PARTION/${partition}/;s/NOPART/$npepost/;s/JOBNAME/intrp_${jobname}_$hstr/;s/HHHSTR/$hstr/" $TEMPDIR/run_mpassit.slurm > $jobscript
        sed -i "s#WRKDIR#$wrkdir#g;s#EXEDIR#${exedir}#" $jobscript
        echo -n "Submitting $jobscript .... "
        $runcmd $jobscript
        echo " "
        if [[ $runcmd == "sbatch" ]]; then
            touch $wrkdir/queue.mpassit$hstr
        fi
    done
}

########################################################################

function run_upp {
    upproot_dir="$1"
    #
    # Build working directory
    #
    wrkdir=$rundir/upp
    mkwrkdir $wrkdir 0
    cd $wrkdir

    fixfiles_AerosolCoeff=( AerosolCoeff.bin )
    fixfiles_CloudCoeff=( CloudCoeff.bin )
    fixfiles_EmisCoeff=( EmisCoeff.bin )

    fixfiles_SpcCoeff=( amsre_aqua.SpcCoeff.bin       imgr_g11.SpcCoeff.bin    \
        imgr_g12.SpcCoeff.bin     imgr_g13.SpcCoeff.bin  imgr_g15.SpcCoeff.bin  \
        imgr_insat3d.SpcCoeff.bin imgr_mt1r.SpcCoeff.bin imgr_mt2.SpcCoeff.bin  \
        seviri_m10.SpcCoeff.bin   ssmi_f13.SpcCoeff.bin  ssmi_f14.SpcCoeff.bin  \
        ssmi_f15.SpcCoeff.bin     ssmis_f16.SpcCoeff.bin ssmis_f17.SpcCoeff.bin \
        ssmis_f18.SpcCoeff.bin    ssmis_f19.SpcCoeff.bin ssmis_f20.SpcCoeff.bin \
        tmi_trmm.SpcCoeff.bin     v.seviri_m10.SpcCoeff.bin)

    fixfiles_TauCoeff=( amsre_aqua.TauCoeff.bin       imgr_g11.TauCoeff.bin    \
        imgr_g12.TauCoeff.bin     imgr_g13.TauCoeff.bin  imgr_g15.TauCoeff.bin  \
        imgr_insat3d.TauCoeff.bin imgr_mt1r.TauCoeff.bin imgr_mt2.TauCoeff.bin  \
        seviri_m10.TauCoeff.bin   ssmi_f13.TauCoeff.bin  ssmi_f14.TauCoeff.bin  \
        ssmi_f15.TauCoeff.bin     ssmis_f16.TauCoeff.bin ssmis_f17.TauCoeff.bin \
        ssmis_f18.TauCoeff.bin    ssmis_f19.TauCoeff.bin ssmis_f20.TauCoeff.bin \
        tmi_trmm.TauCoeff.bin )

    declare -A fixfiles fixdirs
    fixfiles[AerosolCoeff]=fixfiles_AerosolCoeff[@]
    fixfiles[CloudCoeff]=fixfiles_CloudCoeff[@]
    fixfiles[EmisCoeff]=fixfiles_EmisCoeff[@]
    fixfiles[SpcCoeff]=fixfiles_SpcCoeff[@]
    fixfiles[TauCoeff]=fixfiles_TauCoeff[@]

    fixdirs[AerosolCoeff]="$upproot_dir/src/lib/crtm2/src/fix/AerosolCoeff/Big_Endian"
    fixdirs[CloudCoeff]="$upproot_dir/src/lib/crtm2/src/fix/CloudCoeff/Big_Endian"
    fixdirs[EmisCoeff]="$upproot_dir/src/lib/crtm2/src/fix/EmisCoeff/Big_Endian"
    fixdirs[SpcCoeff]="$upproot_dir/src/lib/crtm2/src/fix/SpcCoeff/Big_Endian"
    fixdirs[TauCoeff]="$upproot_dir/src/lib/crtm2/src/fix/TauCoeff/ODPS/Big_Endian"

    for ((h=0;h<=$fcst_hours;h+=$EXTINVL)); do
        hstr=$(printf "%02d" $h)
        fcst_time_str=$(date -d "$eventdate ${eventtime}:00 $h hours" +%Y-%m-%d_%H.%M.%S)

        if [[  -f $wrkdir/done.upp_$hstr || -f $wrkdir/running.upp_$hstr || -f $wrkdir/queue.upp_$hstr ]]; then
            continue      # already done, is running or is in queue, skip this hour
        fi

        mpasfile="$rundir/mpassit/MPAS-A_out.${fcst_time_str}.nc"
        donefile="$rundir/mpassit/done.mpassit$hstr"

        echo "Checking: $donefile ...."
        while [[ ! -f $donefile ]]; do
            if [[ $jobsfromcmd -eq 1 ]]; then
                #return 0
                continue 2
            fi

            if [[ $verb -eq 1 ]]; then
                echo "Waiting for $donefile ..."
            fi
            sleep 10
        done

        mkwrkdir $wrkdir/post_$hstr 1
        cd $wrkdir/post_$hstr

        for coeff in ${!fixfiles[@]}; do
            for fn in ${!fixfiles[$coeff][@]}; do
                #echo "$coeff -> ${fixdirs[$coeff]}/$fn"
                ln -sf ${fixdirs[$coeff]}/$fn .
            done
        done

        #
        #...Link microphysic's tables - code will use based on mp_physics option
        #   found in data
        #
        wrfroot_dir=$rootdir/WRFV4.0
        ln -sf $wrfroot_dir/test/em_real/ETAMPNEW_DATA               nam_micro_lookup.dat
        ln -sf $wrfroot_dir/test/em_real/ETAMPNEW_DATA.expanded_rain hires_micro_lookup.dat

        #
        #...For GRIB2 the code uses postcntrl.xml to select variables for output
        #   the available fields are defined in post_avlbflds.xml -- while we
        #   set a link to this file for reading during runtime it is not typical
        #   for one to update this file, therefore the link goes back to the
        #   program directory - this is true for params_grib2_tbl_new also - a
        #   file which defines the GRIB2 table values
        #
        parmfiles=(params_grib2_tbl_new post_avblflds.xml postcntrl.xml postxconfig-NT.txt )
        for fn in ${parmfiles[@]}; do
            ln -sf $upproot_dir/parm/hrrr_$fn $fn
        done

        nmlfile="itag"
        cat << EOF > $nmlfile
$mpasfile
netcdf
grib2
${fcst_time_str//./:}
NCAR
EOF
        #
        # Create job script and submit it
        #
        jobscript="run_upp_$hstr.slurm"
        sed "s/ACCOUNT/$account/g;s/PARTION/${partition}/;s/NOPART/$npepost/;s/JOBNAME/upp_${jobname}_$hstr/;s/HHHSTR/$hstr/g" $TEMPDIR/run_upp.slurm > $jobscript
        sed -i "s#WRKDIR#$wrkdir/post_$hstr#g;s#EXEDIR#${exedir}#" $jobscript
        echo -n "Submitting $jobscript .... "
        $runcmd $jobscript
        echo " "
        if [[ $runcmd == "sbatch" ]]; then
            touch $wrkdir/queue.upp_$hstr
        fi
    done
}

########################################################################

function run_clean {

    for dirname in $@; do
        case $dirname in
        mpssit )
            wrkdir="$rundir/mpassit"
            for ((h=0;h<=$fcst_hours;h+=$EXTINVL)); do
                hstr=$(printf "%02d" $h)
                fcst_time_str=$(date -d "$eventdate ${eventtime}:00 $h hours" +%Y-%m-%d_%H.%M.%S)
                rm -rf $wrkdir/MPAS-A_out.${fcst_time_str}.nc
                rm -rf $wrkdir/done.mpassit$hstr $wrkdir/error.mpassit$hstr
            done
            ;;
        upp )
            #
            # clean UPP directory
            #
            wrkdir="$rundir/upp"
            for ((h=0;h<=$fcst_hours;h+=$EXTINVL)); do
                hstr=$(printf "%02d" $h)
                if [[ -f $wrkdir/done.upp_$hstr ]]; then
                    if [[ $verb -eq 1 ]]; then
                        echo "Cleaning $wrkdir/post_$hstr ......"
                    fi
                    rm -rf $wrkdir/post_$hstr
                fi
            done
            ;;
        esac
    done
}

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#
# Default values
#
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

jobs=(ungrib init lbc mpas mpassit upp clean)

WORKDIR="${rootdir}/run_dirs"
TEMPDIR="${rootdir}/templates"
eventdate="$eventdateDF"
eventtime="00"

domname="wofs_conus"
runcmd="sbatch"
verb=0
overwrite=1
jobsfromcmd=0

#-----------------------------------------------------------------------
#
# Handle command line arguments
#
#-----------------------------------------------------------------------

while [[ $# > 0 ]]
    do
    key="$1"

    case $key in
        -h)
            usage 0
            ;;
        -n)
            runcmd="echo"
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
            case $2 in
            wofs_big | wofs_small | wofs_poly | wofs_conus | wofs_wrf )
                domname=$2
                ;;
            * )
                echo "ERROR: domain name \"$2\" not supported."
                usage 1
            esac
            shift
            ;;
         static* | geogrid* | ungrib* | init* | lbc* | mpas* | upp* | clean* )
            jobs=(${key//,/ })
            jobsfromcmd=1
            ;;
        -*)
            echo "Unknown option: $key"
            usage 2
            ;;
        *)
            if [[ $key =~ ^[0-9]{8}$ ]]; then
                eventdate="$key"
            elif [[ $key =~ ^[0-9]{10}$ ]]; then
                eventdate="${key:0:8}"
                eventtime="${key:8:2}"
            elif [[ -d $key ]]; then
                WORKDIR=$key
            else
                 echo ""
                 echo "ERROR: unknown option, get [$key]."
                 usage 3
            fi
            ;;
    esac
    shift # past argument or value
done

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#
# Perform each task
#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

account="hpc-wof1"
partition="xjet,ujet,vjet,tjet,kjet"
partition_static="bigmem"
npeics=800
npefcst=1200
npepost=72

fcst_hours=36

EXTHEAD="GFS0p25"
EXTINVL=1
EXTINVL_STR="${EXTINVL}:00:00"
EXTNFGL=57
EXTNFLS=4

OUTINVL_STR="1:00:00"
OUTIOTYPE="netcdf4"
ICSIOTYPE="pnetcdf,cdf5"

echo "---- Jobs started $(date +%m-%d_%H:%M:%S)  ----"
echo "     Event date : $eventdate ${eventtime}:00"
echo "     Working dir: $WORKDIR"
echo "     Domain file: $TEMPDIR/$domname.grid.nc"
echo " "

starttime_str=$(date -d "$eventdate ${eventtime}:00"                     +%Y-%m-%d_%H:%M:%S)
stoptime_str=$(date -d "$eventdate  ${eventtime}:00 ${fcst_hours} hours" +%Y-%m-%d_%H:%M:%S)
#rundir="$WORKDIR/$eventdate${eventtime}"
rundir="$WORKDIR/$eventdate"

if [[ ! -d $rundir ]]; then
    mkdir -p $rundir
fi

jobname="${eventdate:4:4}"

#MPASModel="MPAS-Model.hrrr"
#exedir="${rootdir}/${MPASModel}"
#staticdir="${rootdir}/${MPASModel}"

exedir="/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/MPAS-Model.smiol"

staticdir="$TEMPDIR"

declare -A jobargs=([static]=$WORKDIR/$domname                          \
                    [geogrid]=$WORKDIR/${domname/*_/geo_}               \
                    [ungrib]=/public/data/grids/gfs/0p25deg/grib2       \
                    [init]="ungrib/done.ungrib $WORKDIR/$domname/done.static" \
                    [lbc]="init/done.ics"                                 \
                    [mpas]="lbc/done.lbc"                                 \
                    #[upp]="/lfs4/NAGAPE/wof/wrfout_3km-1km/UPP_KATE_kjet" \
                    [upp]="$rootdir/UPP_KATE_kjet"                        \
                    [clean]="upp"                                         \
                   )

for job in ${jobs[@]}; do
    if [[ $verb -eq 1 ]]; then
        echo "run_$job ${jobargs[$job]}"
    fi
    run_$job ${jobargs[$job]}
done

echo "==== Jobs done $(date +%m-%d_%H:%M:%S) ===="
echo " "
exit 0
