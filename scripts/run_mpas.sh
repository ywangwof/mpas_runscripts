#!/bin/bash

#rootdir="/scratch/ywang/MPAS/mpas_runscripts"
scpdir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
rootdir=$(realpath $(dirname $scpdir))

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
#    2.1 SLURM scripts on Jet
#        run_init.slurm
#        run_lbc.slurm
#        run_mpas.slurm
#        run_mpassit.slurm
#        run_static.slurm
#        run_ungrib.slurm
#        run_geogrid.slurm
#        run_upp.slurm
#
#    2.2 Limited-area SCVT meshes
#        wofs_conus.graph.info
#        wofs_conus.graph.info.part.1200
#        wofs_conus.graph.info.part.800
#        wofs_conus.grid.nc
#
#    2.3 tables for Thompson cloud microphysics scheme [optional, lntemplates]
#        MP_THOMPSON_QIautQS_DATA.DBL
#        MP_THOMPSON_QRacrQG_DATA.DBL
#        MP_THOMPSON_QRacrQS_DATA.DBL
#        MP_THOMPSON_freezeH2O_DATA.DBL
#
#    2.4 MPASS run-time static files [lntemplates]
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
#    2.5 WPS run-time files for program ungrib, geogrid & UPP
#        WRFV4.0/Vtable.GFS_full            # for GFS initialized run only
#        WRFV4.0/Vtable.GFS
#        WRFV4.0/Vtable.raphrrr
#        WRFV4.0/Vtable.RRFS
#        WRFV4.0/Vtable.RRFSP
#        WRFV4.0/GEOGRID.TBL.ARW
#        WRFV4.0/ETAMPNEW_DATA
#        WRFV4.0/ETAMPNEW_DATA.expanded_rain
#
#    2.6 Parameters for program MPASSIT [lntemplates]
#        MPASSIT/diaglist
#        MPASSIT/histlist_2d
#        MPASSIT/histlist_3d
#        MPASSIT/histlist_soil
#
#    2.7 UPP parameters (copied from "/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/UPP_KATE_kjet")
#                    originally from "/lfs4/NAGAPE/wof/wrfout_3km-1km/UPP_KATE_kjet"
#
#        hrrr_params_grib2_tbl_new
#        hrrr_post_avblflds.xml
#        hrrr_postcntrl.xml
#        hrrr_postxconfig-NT.txt
#        crtm2_fix   [lntemplates]
#
# 3. scripts                                # this scripts
#    3.1 run_mpas.sh
#    3.2 lntemplates.sh
#    3.3 cron.txt
#
# 4. /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/WPS_GEOG
#
#    NOTE: It can be anywhere, but should modify "run_geogrid"
#          and "run_static" below whenever the directory is changed.
#
# INSTRUCTIONS:
#
#  Use existing domain (wofs_conus)
#     1. Copy these directories to rootdir (or clone using git)
#        modules
#        exec
#        scripts
#        templates (link needed files use script lntemplates.sh, see README in that directory)
#
#     2. make a run directory under rootdir
#        run_dirs
#
#     3. Copy existing domain directories $rootdir/run_dirs/wofs_conus & geo_conus to
#        your run_dirs
#
#     4. run_mpas.sh [YYYYmmddHH] [run_dirs] [jobnames]
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
    echo "              -k  [0,1,2]     Keep working directory if exist, 0- keep as is; 1- overwrite; 2- make a backup as xxxx.bak?"
    echo "                              Default is 0 for ungrib, mpassit, upp and 1 for others"
    echo "              -t  DIR         Template directory for runtime files"
    echo "              -m  Machine     Machine name to run on, [Jet, Odin]."
    echo "              -a  wof         Account name for job submission."
    echo "              -d  wofs_mpas   Domain name to be used"
    echo "              -i  hrrr        Initialization model, [hrrr, gfs, rrfs, rrfsp], default: hrrr"
    echo "              -s  init_dir    Directory name from which init & lbc subdirectories are used to initialize this run"
    echo "                              which avoids runing duplicated preprocessing jobs (ungrib, init/lbc) again. default: false"
    echo "              -p  nssl        MP scheme, [nssl, thompson], default: nssl"
    echo " "
    echo "   DEFAULTS:"
    echo "              eventdt = $eventdateDF"
    echo "              rootdir = $rootdir"
    echo "              WORKDIR = $rootdir/run_dirs"
    echo "              TEMPDIR = $rootdir/templates"
    echo " "
    echo "                                     -- By Y. Wang (2023.01.25)"
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

    ln -sf ${TEMPDIR}/WRFV4.0/GEOGRID.TBL.ARW GEOGRID.TBL

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
  e_we = 1601,
  e_sn = 961,
  geog_data_res = '30s',
  dx = 3000.0,
  dy = 3000.0,
  map_proj = 'lambert',
  ref_lat = 38.5,
  ref_lon = -97.5,
  truelat1 = 38.5,
  truelat2 = 38.5,
  stand_lon = -97.5
  geog_data_path = '${WPSGEOG_PATH}',
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
    sed -i "s#ROOTDIR#$rootdir#g;s#WRKDIR#$wrkdir#g;s#EXEDIR#${exedir}#" $jobscript
    if [[ $dorun == true ]]; then echo -n "Submitting $jobscript .... "; fi
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
    config_nvertlevels   = 1
    config_nsoillevels   = 1
    config_nfglevels     = 1
    config_nfgsoillevels = 1
    config_nsoilcat      = 16

/
&data_sources
    config_geog_data_path = '${WPSGEOG_PATH}'
    config_met_prefix = 'CFSR'
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
    config_specified_zeta_levels = '${TEMPDIR}/L60.txt'
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
    jobscript="run_static.slurm"
    sed "s/ACCOUNT/$account/g;s/PARTION/${partition_static}/;" $TEMPDIR/$jobscript > $jobscript
    sed -i "s/JOBNAME/static_${jobname}/;s/CPUSPEC/${claim_cpu}/;s/MODULE/${modulename}/;s/MACHINE/${machine}/g" $jobscript
    #sed -i "s#ROOTDIR#$rootdir#g;s#WRKDIR#$wrkdir#g;s#EXEDIR#${rootdir}/MPAS-Model#" $jobscript
    sed -i "s#ROOTDIR#$rootdir#g;s#WRKDIR#$wrkdir#g;s#EXEDIR#${exedir}#" $jobscript
    if [[ $dorun == true ]]; then echo -n "Submitting $jobscript .... "; fi
    $runcmd $jobscript
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

    julday=$(date -d "$eventdate ${eventtime}:00" +%y%j%H)

    if [[ -f ungrib.running || -f done.ungrib || -f queue.ungrib ]]; then
        :                   # skip
    else
        hrrrfiles=()
        for ((h=0;h<=fcst_hours;h+=EXTINVL)); do
            hstr=$(printf "%02d" $h)
            hrrrfiles+=($hrrr_grib_dir/${julday}0000$hstr)
        done

        for fn in ${hrrrfiles[@]}; do
            echo "HRRR file: $fn"
            while [[ ! -f $fn ]]; do
                if [[ $verb -eq 1 ]]; then
                    echo "Waiting for $fn ..."
                fi
                sleep 10
            done
        done

        link_grib ${hrrrfiles[@]}

        ln -sf $TEMPDIR/WRFV4.0/Vtable.raphrrr Vtable

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
        sed "s/ACCOUNT/$account/g;s/PARTION/${partition}/;s/JOBNAME/ungrb_hrrr_${jobname}/" $TEMPDIR/$jobscript > $jobscript
        sed -i "s#ROOTDIR#$rootdir#g;s#WRKDIR#$wrkdir#g;s#EXEDIR#${exedir}#" $jobscript
        if [[ $dorun == true ]]; then echo -n "Submitting $jobscript .... "; fi
        $runcmd $jobscript
        if [[ $dorun == true ]]; then touch queue.ungrib; fi
    fi

    if [[ $dorun == true ]]; then
        secdtime_str=$(date -d "$eventdate ${eventtime}:00 $EXTINVL hours" +%Y-%m-%d_%H)
        secdfile=$wrkdir/${EXTHEAD}:${secdtime_str}

        echo "$$: Checking: $secdfile"
        while [[ ! -e $secdfile ]]; do
            if [[ $verb -eq 1 ]]; then
                echo "Waiting for $secdfile ......"
            fi
            sleep 10
        done
    fi

    touch $wrkdir/done.ungrib_ics

    if [[ $dorun == true ]]; then
        echo "$$: Checking: $wrkdir/done.ungrib"
        while [[ ! -e $wrkdir/done.ungrib ]]; do
            if [[ $verb -eq 1 ]]; then
                echo "Waiting for $wrkdir/done.ungrib"
            fi
            sleep 10
        done

    fi

    touch $wrkdir/done.ungrib_lbc
}

########################################################################

function run_ungrib_gfs {
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

        ln -sf $TEMPDIR/WRFV4.0/Vtable.GFS_full Vtable

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
        sed -i "s#ROOTDIR#$rootdir#g;s#WRKDIR#$wrkdir#g;s#EXEDIR#${exedir}#" $jobscript
        if [[ $dorun == true ]]; then echo -n "Submitting $jobscript .... "; fi
        $runcmd $jobscript
        if [[ $dorun == true ]]; then touch queue.ungrib; fi
    fi

    if [[ $dorun == true ]]; then
        echo "$$: Checking: $wrkdir/done.ungrib"
        while [[ ! -e $wrkdir/done.ungrib ]]; do
            if [[ $verb -eq 1 ]]; then
                echo "Waiting for $wrkdir/done.ungrib"
            fi
            sleep 10
        done
        touch $wrkdir/done.ungrib_ics
        touch $wrkdir/done.ungrib_lbc
    fi
}

########################################################################

function run_ungrib_rrfs {
    if [[ $# -ne 1 ]]; then
        echo "ERROR: run_ungrib require 1 arguments."
        exit 2
    fi
    rrfs_grib_dir=$1

    wrkdir=$rundir/ungrib
    mkwrkdir $wrkdir 0
    cd $wrkdir

    julday=$(date -d "$eventdate ${eventtime}:00" +%y%j%H)

    if [[ -f ungrib.running || -f done.ungrib || -f queue.ungrib ]]; then
        :                   # skip
    else
        currdate=$(date -d "$eventdate ${eventtime}:00" +%Y%m%d)
        currtime=$(date -d "$eventdate ${eventtime}:00" +%H)
        if [[ "$rrfs_grib_dir" =~ "https://noaa-rrfs-pds.s3.amazonaws.com" ]]; then
            rrfs_url="$rrfs_grib_dir/rrfs_a/rrfs_a.${currdate}/${currtime}"
            download_aws=1
        else
            rrfs_grib_dir="$rrfs_grib_dir/rrfs_a.${currdate}/${currtime}"
            download_aws=0
        fi


        rrfsfiles=()
        for ((h=0;h<=fcst_hours;h+=EXTINVL)); do
            hstr=$(printf "%03d" $h)
            if [[ $download_aws -eq 1 ]]; then
                rrfsfile="rrfs.t${currtime}z.natlev.f${hstr}.conus_3km.grib2"
                if [[ ! -f $rrfsfile ]]; then
                    rrfsfidx="${rrfsfile}.idx"
                    wget -c -q --connect-timeout=120 --read-timeout=180 $rrfs_url/$rrfsfidx
                    while [[ $? -ne 0 ]]; do
                        sleep 10
                        echo "wget -c $rrfs_url/$rrfsfidx"
                        wget -c -q --connect-timeout=120 --read-timeout=180 $rrfs_url/$rrfsfidx
                    done
                    rm -f ${rrfsfidx}

                    wget -c -q --connect-timeout=120 --read-timeout=180 $rrfs_url/$rrfsfile
                    while [[ $? -ne 0 ]]; do
                        sleep 10
                        echo "wget -c $rrfs_url/$rrfsfile"
                        wget -c -q --connect-timeout=120 --read-timeout=180 $rrfs_url/$rrfsfile
                    done
                fi
            else
                rrfsfile=$rrfs_grib_dir/RRFS_CONUS.t${currtime}z.bgrd3df${hstr}.tm00.grib2
                while [[ ! -f $rrfsfile ]]; do
                    if [[ $verb -eq 1 ]]; then
                        echo "Waiting for $rrfsfile ..."
                    fi
                    sleep 10
                done
            fi
            rrfsfiles+=(${rrfsfile})
        done

        myrrfsfiles=()
        for i in ${!rrfsfiles[@]}; do
            fn=${rrfsfiles[$i]}

            # drop un-wanted records
            basefn=$(basename $fn)
            basefn="NSSL_$basefn"
            rm -f $basefn

            fhrstr=$(echo $fn | grep -o -E 'f[0-9]{3}')
            fhr=${fhrstr//[!0-9]/}
            fhr=$((10#$fhr))

            if [[ $fhr -eq 0 ]]; then
                valtime="anl"
            else
                valtime="$fhr hour fcst"
            fi
            echo "RRFS file: $fn ($valtime)"

            rm -f keep.txt
            cat << EOF > keep.txt
:PRES:[0-9]{1,2} hybrid level:${valtime}:
:CLWMR:[0-9]{1,2} hybrid level:${valtime}:
:ICMR:[0-9]{1,2} hybrid level:${valtime}:
:RWMR:[0-9]{1,2} hybrid level:${valtime}:
:SNMR:[0-9]{1,2} hybrid level:${valtime}:
:GRLE:[0-9]{1,2} hybrid level:${valtime}:
:HGT:[0-9]{1,2} hybrid level:${valtime}:
:TMP:[0-9]{1,2} hybrid level:${valtime}:
:SPFH:[0-9]{1,2} hybrid level:${valtime}:
:UGRD:[0-9]{1,2} hybrid level:${valtime}:
:VGRD:[0-9]{1,2} hybrid level:${valtime}:
:TMP:2 m above ground:${valtime}:
:SPFH:2 m above ground:${valtime}:
:RH:2 m above ground:${valtime}:
:UGRD:10 m above ground:${valtime}:
:VGRD:10 m above ground:${valtime}:
:PRES:surface:${valtime}:
:SNOD:surface:${valtime}:
:WEASD:surface:${valtime}:
:TMP:surface:${valtime}:
:CNWAT:surface:${valtime}:
:HGT:surface:${valtime}:
:MSLET:mean sea level:${valtime}:
:TSOIL:0-0 m below ground:${valtime}:
:TSOIL:0.01-0.01 m below ground:${valtime}:
:TSOIL:0.04-0.04 m below ground:${valtime}:
:TSOIL:0.1-0.1 m below ground:${valtime}:
:TSOIL:0.3-0.3 m below ground:${valtime}:
:TSOIL:0.6-0.6 m below ground:${valtime}:
:TSOIL:1-1 m below ground:${valtime}:
:TSOIL:1.6-1.6 m below ground:${valtime}:
:TSOIL:3-3 m below ground:${valtime}:
:SOILW:0-0 m below ground:${valtime}:
:SOILW:0.01-0.01 m below ground:${valtime}:
:SOILW:0.04-0.04 m below ground:${valtime}:
:SOILW:0.1-0.1 m below ground:${valtime}:
:SOILW:0.3-0.3 m below ground:${valtime}:
:SOILW:0.6-0.6 m below ground:${valtime}:
:SOILW:1-1 m below ground:${valtime}:
:SOILW:1.6-1.6 m below ground:${valtime}:
:SOILW:3-3 m below ground:${valtime}:
:LAND:surface:${valtime}:
:ICEC:surface:${valtime}:
EOF

            echo "Generating working copy of $basefn ..."
            ${wgrib2path} $fn | grep -Ef keep.txt | wgrib2 -i $fn -GRIB $basefn >& /dev/null
            myrrfsfiles+=($basefn)
        done

        link_grib ${myrrfsfiles[@]}

        ln -sf $TEMPDIR/WRFV4.0/Vtable.RRFS Vtable

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
        sed "s/ACCOUNT/$account/g;s/PARTION/${partition}/;s/JOBNAME/ungrb_rrfs_${jobname}/" $TEMPDIR/$jobscript > $jobscript
        sed -i "s#ROOTDIR#$rootdir#g;s#WRKDIR#$wrkdir#g;s#EXEDIR#${exedir}#" $jobscript
        if [[ $dorun == true ]]; then echo -n "Submitting $jobscript .... "; fi
        $runcmd $jobscript
        if [[ $dorun == true ]]; then touch queue.ungrib; fi
    fi


    if [[ $dorun == true ]]; then
        secdtime_str=$(date -d "$eventdate ${eventtime}:00 $EXTINVL hours" +%Y-%m-%d_%H)
        secdfile=$wrkdir/${EXTHEAD}:${secdtime_str}

        echo "$$: Checking: $secdfile"
        while [[ ! -e $secdfile ]]; do
            if [[ $verb -eq 1 ]]; then
                echo "Waiting for $secdfile ......"
            fi
            sleep 10
        done
    fi

    touch $wrkdir/done.ungrib_ics

    if [[ $dorun == true ]]; then
        echo "$$: Checking: $wrkdir/done.ungrib"
        while [[ ! -e $wrkdir/done.ungrib ]]; do
            if [[ $verb -eq 1 ]]; then
                echo "Waiting for $wrkdir/done.ungrib"
            fi
            sleep 10
        done
    fi

    touch $wrkdir/done.ungrib_lbc
}

########################################################################

function run_ungrib_rrfsp {
    if [[ $# -ne 1 ]]; then
        echo "ERROR: run_ungrib require 1 arguments."
        exit 2
    fi
    rrfs_grib_dir=$1

    wrkdir=$rundir/ungrib_rrfs
    mkwrkdir $wrkdir 0
    cd $wrkdir

    julday=$(date -d "$eventdate ${eventtime}:00" +%y%j%H)

    if [[ -f ungrib.running || -f done.ungrib || -f queue.ungrib ]]; then
        :                   # skip
    else
        currdate=$(date -d "$eventdate ${eventtime}:00" +%Y%m%d)
        currtime=$(date -d "$eventdate ${eventtime}:00" +%H)
        if [[ "$rrfs_grib_dir" =~ "https://noaa-rrfs-pds.s3.amazonaws.com" ]]; then
            rrfs_url="${rrfs_grib_dir}/rrfs_a/rrfs_a.${currdate}/${currtime}"
            download_aws=1
        else
            rrfs_grib_dir="$rrfs_grib_dir/rrfs_a.${currdate}/${currtime}"
            download_aws=0
        fi

        rrfsfiles=()
        for ((h=0;h<=fcst_hours;h+=EXTINVL)); do
            hstr=$(printf "%03d" $h)
            if [[ $download_aws -eq 1 ]]; then
                rrfsfile="rrfs.t${currtime}z.prslev.f${hstr}.conus_3km.grib2"
                if [[ ! -f $rrfsfile ]]; then
                    rrfsfidx="${rrfsfile}.idx"
                    wget -c -q --connect-timeout=120 --read-timeout=180 $rrfs_url/$rrfsfidx
                    while [[ $? -ne 0 ]]; do
                        sleep 10
                        echo "wget -c $rrfs_url/$rrfsfidx"
                        wget -c -q --connect-timeout=120 --read-timeout=180 $rrfs_url/$rrfsfidx
                    done
                    rm -f ${rrfsfidx}

                    wget -c -q --connect-timeout=120 --read-timeout=180 $rrfs_url/$rrfsfile
                    while [[ $? -ne 0 ]]; do
                        sleep 10
                        echo "wget -c $rrfs_url/$rrfsfile"
                        wget -c -q --connect-timeout=120 --read-timeout=180 $rrfs_url/$rrfsfile
                    done
                fi
            else
                rrfsfile=$rrfs_grib_dir/RRFS_CONUS.t${currtime}z.bgdawpf${hstr}.tm00.grib2
                echo "RRFS file: $rrfsfile"
                while [[ ! -f $rrfsfile ]]; do
                    if [[ $verb -eq 1 ]]; then
                        echo "Waiting for $rrfsfile ..."
                    fi
                    sleep 10
                done
            fi
            rrfsfiles+=(${rrfsfile})
        done

        link_grib ${rrfsfiles[@]}

        ln -sf $TEMPDIR/WRFV4.0/Vtable.RRFSP Vtable

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
        sed "s/ACCOUNT/$account/g;s/PARTION/${partition}/;s/JOBNAME/ungrb_rrfs_${jobname}/" $TEMPDIR/$jobscript > $jobscript
        sed -i "s#ROOTDIR#$rootdir#g;s#WRKDIR#$wrkdir#g;s#EXEDIR#${exedir}#" $jobscript
        if [[ $dorun == true ]]; then echo -n "Submitting $jobscript .... "; fi
        $runcmd $jobscript
        if [[ $dorun == true ]]; then touch queue.ungrib; fi
    fi

    if [[ $dorun == true ]]; then
        secdtime_str=$(date -d "$eventdate ${eventtime}:00 $EXTINVL hours" +%Y-%m-%d_%H)
        secdfile=$wrkdir/${EXTHEAD}:${secdtime_str}

        echo "$$: Checking: $secdfile"
        while [[ ! -e $secdfile ]]; do
            if [[ $verb -eq 1 ]]; then
                echo "Waiting for $secdfile ......"
            fi
            sleep 10
        done
    fi

    touch $wrkdir/done.ungrib_ics

    if [[ $dorun == true ]]; then
        echo "$$: Checking: $wrkdir/done.ungrib"
        while [[ ! -e $wrkdir/done.ungrib ]]; do
            if [[ $verb -eq 1 ]]; then
                echo "Waiting for $wrkdir/done.ungrib"
            fi
            sleep 10
        done
    fi

    touch $wrkdir/done.ungrib_lbc
}

########################################################################

function run_init {

    if [[ -d $init_dir ]]; then  # link it from somewhere

        if [[ $dorun == true ]]; then
            donefile="$init_dir/init/done.ics"
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
                if [[ $verb -eq 1 ]]; then
                    echo "Waiting for file: $cond"
                fi
                sleep 10
            done
        done
    fi

    wrkdir=$rundir/init
    if [[ -f $wrkdir/ics.running || -f $wrkdir/done.ics || -f $wrkdir/queue.ics ]]; then
        :                   # skip
    else
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
    config_nvertlevels   = 59
    config_nsoillevels   = ${MPASNFLS}
    config_nfglevels     = ${EXTNFGL}
    config_nfgsoillevels = ${EXTNFLS}
    config_nsoilcat      = 16
/
&data_sources
    config_geog_data_path = '/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/WPS_GEOG/'
    config_met_prefix = '${EXTHEAD}'
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
    config_specified_zeta_levels = '${TEMPDIR}/L60.txt'
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
                  filename_template="$domname.init.nc"
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
        #
        # Create job script and submit it
        #
        jobscript="run_init.slurm"
        sed    "s/ACCOUNT/$account/g;s/PARTION/${partition}/;s/NOPART/$npeics/;s/MACHINE/${machine}/g" $TEMPDIR/$jobscript > $jobscript
        sed -i "s/JOBNAME/init_${jobname}/;s/CPUSPEC/${claim_cpu}/;s/MODULE/${modulename}/g" $jobscript
        sed -i "s#ROOTDIR#$rootdir#g;s#WRKDIR#$wrkdir#g;s#EXEDIR#${exedir}#" $jobscript
        if [[ $dorun == true ]]; then echo -n "Submitting $jobscript .... "; fi
        $runcmd $jobscript
        if [[ $dorun == true ]]; then touch queue.ics; fi
    fi
}

########################################################################

function run_lbc {

    if [[ -d $init_dir ]]; then  # link it from somewhere

        if [[ $dorun == true ]]; then
            donefile="$init_dir/lbc/done.lbc"
            echo "$$: Checking: $donefile"
            while [[ ! -e $donefile ]]; do
                if [[ $verb -eq 1 ]]; then
                    echo "Waiting for file: $donefile"
                fi
                sleep 10
            done
        fi

        cd $rundir
        ln -sf $init_dir/lbc .
        return
    fi

    # otherwise, run lbc normally

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

    wrkdir=$rundir/lbc
    if [[ -f $wrkdir/lbc.running || -f $wrkdir/done.lbc || -f $wrkdir/queue.lbc ]]; then
        :                   # skip
    else
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
    config_nvertlevels   = 59
    config_nsoillevels   = ${MPASNFLS}
    config_nfglevels     = ${EXTNFGL}
    config_nfgsoillevels = ${EXTNFLS}
    config_nsoilcat      = 16
/
&data_sources
    config_geog_data_path = '/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/WPS_GEOG/'
    config_met_prefix = '${EXTHEAD}'
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
    config_specified_zeta_levels = '${TEMPDIR}/L60.txt'
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
                  clobber_mode="replace_files"
                  output_interval="${EXTINVL_STR}" />

</streams>
EOF
        #
        # Create job script and submit it
        #
        jobscript="run_lbc.slurm"
        sed "s/ACCOUNT/$account/g;s/PARTION/${partition}/;s/NOPART/$npeics/;s/MACHINE/${machine}/g" $TEMPDIR/$jobscript > $jobscript
        sed -i "s/JOBNAME/lbc_${jobname}/;s/CPUSPEC/${claim_cpu}/;s/MODULE/${modulename}/g" $jobscript
        sed -i "s#ROOTDIR#$rootdir#g;s#WRKDIR#$wrkdir#g;s#EXEDIR#${exedir}#" $jobscript
        if [[ $dorun == true ]]; then echo -n "Submitting $jobscript .... "; fi
        $runcmd $jobscript
        if [[ $dorun == true ]]; then touch queue.lbc; fi
    fi
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

    #
    # Build working directory
    #
    wrkdir=$rundir/fcst
    if [[ -f $wrkdir/fcst.running || -f $wrkdir/done.fcst || -f $wrkdir/queue.fcst ]]; then
        :                   # skip
    else
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

        if [[ "${mpscheme}" == "Thompson" ]]; then
            thompson_tables=( MP_THOMPSON_QRacrQG_DATA.DBL   MP_THOMPSON_QRacrQS_DATA.DBL   \
                              MP_THOMPSON_freezeH2O_DATA.DBL MP_THOMPSON_QIautQS_DATA.DBL )

            for fn in ${thompson_tables[@]}; do
                ln -sf ${TEMPDIR}/$fn .
            done
        fi

        fcsthour_str=$(printf "%02d" $fcst_hours)

        cat << EOF > namelist.atmosphere
&nhyd_model
    config_time_integration_order   = 2
    config_dt                       = 25
    config_start_time               = '${starttime_str}'
    config_run_duration             = '${fcsthour_str}:00:00'
    config_split_dynamics_transport = true
    config_number_of_sub_steps      = 4
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
    config_mpas_cam_coef            = 2.0
    config_rayleigh_damp_u          = true
    config_zd                       = 16000.0
    config_xnutr                    = 0.2
    config_nlevels_cam_damp         = 8
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
    config_print_global_minmax_sca   = true
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
    config_radtlw_interval           = '00:30:00'
    config_radtsw_interval           = '00:30:00'
    config_bucket_update             = 'none'
    config_lsm_scheme                = '${MPASLSM}'
    num_soil_layers                  = ${MPASNFLS}
    config_physics_suite             = 'convection_permitting'
EOF

        if [[ ${mpscheme} == "mp_nssl2m" ]]; then

            cat << EOF >> namelist.atmosphere
    config_microp_scheme             = '${mpscheme}'
/
&nssl_mp_params
    ehw0                             = 0.9
    ehlw0                            = 0.9
    icefallfac                       = 1.5
    snowfallfac                      = 1.25
    iusewetsnow                      = 0
EOF

        fi

        cat << EOF >> namelist.atmosphere
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
                  clobber_mode="replace_files"
                  output_interval="61:00:00" />

<stream name="output"
                  type="output"
                  filename_template="${domname}.history.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
                  io_type="${OUTIOTYPE}"
                  clobber_mode="replace_files"
                  output_interval="${OUTINVL_STR}" >

    <file name="stream_list.atmosphere.output"/>
</stream>

<stream name="diagnostics"
                  type="output"
                  filename_template="${domname}.diag.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
                  io_type="${OUTIOTYPE}"
                  clobber_mode="replace_files"
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
        jobscript="run_mpas.${mach}"
        sed "s/ACCOUNT/$account/g;s/PARTION/${partition}/" $TEMPDIR/$jobscript > $jobscript
        sed -i "s/NOPART/$npefcst/;s/NNODES/${nnodes_fcst}/;s/NCORES/${ncores_fcst}/" $jobscript
        sed -i "s/JOBNAME/mpas_${jobname}/;s/CPUSPEC/${claim_cpu}/g;s/MODULE/${modulename}/g" $jobscript
        sed -i "s#ROOTDIR#$rootdir#g;s#WRKDIR#$wrkdir#g;s#EXEDIR#${exedir}#;s/MACHINE/${machine}/g" $jobscript
        if [[ $dorun == true ]]; then echo -n "Submitting $jobscript .... "; fi
        $runcmd $jobscript
        if [[ $dorun == true ]]; then touch queue.fcst; fi
    fi
}

########################################################################

function run_mpassit {
    #
    # Build working directory
    #
    wrkdir=$rundir/mpassit
    mkwrkdir $wrkdir 0
    cd $wrkdir

    if [[ "${mpscheme}" == "Thompson" ]]; then
        fileappend="THOM"
    else
        fileappend="NSSL"
    fi

    parmfiles=(diaglist histlist_2d histlist_3d histlist_soil)
    for fn in ${parmfiles[@]}; do
        if [[ ! -e $fn ]]; then
            if [[ $verb -eq 1 ]]; then echo "Linking $fn ..."; fi
            if [[ -e $TEMPDIR/MPASSIT/${fn}.${fileappend} ]]; then
                ln -sf $TEMPDIR/MPASSIT/${fn}.${fileappend} $fn
            elif [[ -e $TEMPDIR/MPASSIT/${fn} ]]; then
                ln -sf $TEMPDIR/MPASSIT/$fn .
            else
                echo "ERROR: file \"$TEMPDIR/MPASSIT/${fn}\" not exist."
                return
            fi
        fi
    done

    for ((h=0;h<=$fcst_hours;h+=$OUTINVL)); do
        hstr=$(printf "%02d" $h)
        fcst_time_str=$(date -d "$eventdate ${eventtime}:00 $h hours" +%Y-%m-%d_%H.%M.%S)

        histfile="$rundir/fcst/${domname}.history.${fcst_time_str}.nc"
        diagfile="$rundir/fcst/${domname}.diag.${fcst_time_str}.nc"

        if [[ -f done.mpassit$hstr || -f running.mpassit$hstr || -f queue.mpassit$hstr || -f error.mpassit$hstr ]]; then
            continue               # already done, is running or is in queue, skip this hour
        fi

        if [[ -f error.mpassit$hstr ]]; then
            rm -f core.*           # Maybe core-dumped, resubmission will solves the problem if the machine is unstable.
        fi

        if [[ $dorun == true ]]; then
            for fn in $histfile $diagfile; do
                echo "$$: Checking: $fn ..."
                while [[ ! -f $fn ]]; do
                    if [[ $jobsfromcmd -eq 1 ]]; then    # do not wait for it
                        continue 3                       # go ahead to process next hour
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
        fi

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
        sed "s/ACCOUNT/$account/g;s/PARTION/${partition}/;s/NOPART/$npepost/;" $TEMPDIR/run_mpassit.slurm > $jobscript
        sed -i "s/JOBNAME/intrp_${jobname}_$hstr/;s/HHHSTR/$hstr/g;s/CPUSPEC/${claim_cpu}/;" $jobscript
        sed -i "s#ROOTDIR#$rootdir#g;s#WRKDIR#$wrkdir#g;s#EXEDIR#${exedir}#;s/MACHINE/${machine}/g" $jobscript
        if [[ $dorun == true ]]; then echo -n "Submitting $jobscript .... "; fi
        $runcmd $jobscript
        echo " "
        if [[ $dorun == true ]]; then touch $wrkdir/queue.mpassit$hstr; fi
    done
}

########################################################################

function run_upp {
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

    declare -A fixdirs
    #declare -A fixfiles fixdirs
    #fixfiles[AerosolCoeff]=fixfiles_AerosolCoeff[@]
    #fixfiles[CloudCoeff]=fixfiles_CloudCoeff[@]
    #fixfiles[EmisCoeff]=fixfiles_EmisCoeff[@]
    #fixfiles[SpcCoeff]=fixfiles_SpcCoeff[@]
    #fixfiles[TauCoeff]=fixfiles_TauCoeff[@]
    fixfiles=( AerosolCoeff CloudCoeff EmisCoeff SpcCoeff TauCoeff )

    fixdirs[AerosolCoeff]="$TEMPDIR/UPP/crtm2_fix/AerosolCoeff/Big_Endian"
    fixdirs[CloudCoeff]="$TEMPDIR/UPP/crtm2_fix/CloudCoeff/Big_Endian"
    fixdirs[EmisCoeff]="$TEMPDIR/UPP/crtm2_fix/EmisCoeff/Big_Endian"
    fixdirs[SpcCoeff]="$TEMPDIR/UPP/crtm2_fix/SpcCoeff/Big_Endian"
    fixdirs[TauCoeff]="$TEMPDIR/UPP/crtm2_fix/TauCoeff/ODPS/Big_Endian"

    for ((h=0;h<=$fcst_hours;h+=$OUTINVL)); do
        hstr=$(printf "%02d" $h)
        fcst_time_str=$(date -d "$eventdate ${eventtime}:00 $h hours" +%Y-%m-%d_%H.%M.%S)

        if [[  -f $wrkdir/done.upp_$hstr || -f $wrkdir/queue.upp_$hstr ]]; then
            continue      # already done, or is in queue, skip this hour
        fi

        if [[  -f $wrkdir/running.upp_$hstr ]]; then
            fileage=$(( $(date +%s) - $(stat -c %Y -- "$wrkdir/running.upp_$hstr") ))
            if [[ $fileage -lt 300 ]]; then
                continue                        # Job is running, skip
            else                                # > 5 minutes, May be a time out issue
                rm $wrkdir/running.upp_$hstr
            fi
        fi

        #if [[  -f $wrkdir/error.upp_$hstr ]]; then
            # resubmission may solve the problem
        #fi

        mpasfile="$rundir/mpassit/MPAS-A_out.${fcst_time_str}.nc"
        donefile="$rundir/mpassit/done.mpassit$hstr"

        if [[ $dorun == true ]]; then
            echo "$$: Checking: $donefile ...."
            while [[ ! -f $donefile ]]; do
                if [[ $jobsfromcmd -eq 1 ]]; then     # do not wait
                    continue 2                        # go ahread to process next forecast hour
                fi

                if [[ $verb -eq 1 ]]; then
                    echo "Waiting for $donefile ..."
                fi
                sleep 10
            done
        fi

        mkwrkdir $wrkdir/post_$hstr 1
        cd $wrkdir/post_$hstr

        #for coeff in ${!fixfiles[@]}; do
        #    echo "$coeff"
        #    for fn in ${!fixfiles[$coeff][@]}; do
        for coeff in ${fixfiles[@]}; do
            eval filearray=\( \${fixfiles_${coeff}[@]} \)
            for fn in ${filearray[@]}; do
                #echo "$coeff -> ${fixdirs[$coeff]}/$fn"
                ln -sf ${fixdirs[$coeff]}/$fn .
            done
        done

        #
        #...Link microphysic's tables - code will use based on mp_physics option
        #   found in data
        #
        ln -sf $TEMPDIR/WRFV4.0/ETAMPNEW_DATA               nam_micro_lookup.dat
        ln -sf $TEMPDIR/WRFV4.0/ETAMPNEW_DATA.expanded_rain hires_micro_lookup.dat

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
            ln -sf $TEMPDIR/UPP/hrrr_$fn $fn
        done

        nmlfile="itag"
        cat << EOF > $nmlfile
$mpasfile
netcdf
grib2
${fcst_time_str//./:}
RAPR
EOF
        #
        # Create job script and submit it
        #
        jobscript="run_upp_$hstr.slurm"
        sed "s/ACCOUNT/$account/g;s/PARTION/${partition_upp}/;s/NOPART/$npepost/;s/CPUSPEC/${claim_cpu}/" $TEMPDIR/run_upp.slurm > $jobscript
        sed -i "s/JOBNAME/upp_${jobname}_$hstr/;s/HHHSTR/$hstr/g;s/MODULE/${modulename}/g" $jobscript
        sed -i "s#ROOTDIR#$rootdir#g;s#WRKDIR#$wrkdir/post_$hstr#g;s#EXEDIR#${exedir}#;s/MACHINE/${machine}/g" $jobscript
        if [[ $dorun == true ]]; then echo -n "Submitting $jobscript .... "; fi
        $runcmd $jobscript
        echo " "
        if [[ $dorun == true ]]; then touch $wrkdir/queue.upp_$hstr; fi
    done
}

########################################################################

function run_pcp {
    #
    # Check working directory
    #
    wrkdir=$rundir/upp
    if [[ ! -d $wrkdir ]]; then
        echo "Directory: $wrkdir not exist."
        return
    fi
    cd $wrkdir

    expectednum=$(( fcst_hours +1))

    donefiles=($(ls done.upp_??))
    pcpfiles=($(ls  MPAS-A_PCP_*))

    if [[ ${#donefiles[@]} -lt $expectednum ]]; then
        echo "WARNING: UPPs are still not all done. Skip run_pcp."
    elif [[ ${#pcpfiles[@]} -ge $expectednum ]]; then
        echo "run_pcp already done."
    elif [[  -f $wrkdir/done.pcp || -f $wrkdir/queue.pcp || -f $wrkdir/running.pcp ]]; then
        echo "Founding working file for run_pcp. Skip"
    else
        #
        # Create job script and submit it
        #
        jobscript="run_pcp.slurm"
        sed "s/ACCOUNT/$account/g;s/PARTION/${partition_upp}/;s/CPUSPEC/${claim_cpu}/" $TEMPDIR/run_pcp.slurm > $jobscript
        sed -i "s/JOBNAME/pcp_${jobname}/;s/HHHSTR/${fcst_hours}/g;s/MODULE/${modulename}/g" $jobscript
        sed -i "s#ROOTDIR#$rootdir#g;s#WRKDIR#$wrkdir#g;s/MACHINE/${machine}/g" $jobscript
        if [[ $dorun == true ]]; then echo -n "Submitting $jobscript .... "; fi
        $runcmd $jobscript
        if [[ $dorun == true ]]; then touch $wrkdir/queue.pcp; fi
    fi
}

########################################################################

function run_clean {

    for dirname in $@; do
        case $dirname in
        ungrib )
            donelbc="$rundir/lbc/done.lbc"
            for dirsn in ungrib_gfs ungrib_hrrr ungrib_rrfs ungrib; do
                if [[ -d $rundir/$dirsn && -e $donelbc ]]; then
                    cd $rundir/$dirsn
                    rm -rf GFS:* HRRR:* RRFS:* PFILE:* RRFSGFS:* HRRRGFS:*
                    rm -rf RRFS_CONUS.*
                fi
            done
            ;;
        mpssit )
            wrkdir="$rundir/mpassit"
            for ((h=0;h<=$fcst_hours;h+=$EXTINVL)); do
                hstr=$(printf "%02d" $h)
                fcst_time_str=$(date -d "$eventdate ${eventtime}:00 $h hours" +%Y-%m-%d_%H.%M.%S)
                rm -rf $wrkdir/MPAS-A_out.${fcst_time_str}.nc
                #rm -rf $wrkdir/done.mpassit$hstr $wrkdir/error.mpassit$hstr
            done
            ;;
        upp )
            #
            # Clean UPP directory
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

            if [[ -f $wrkdir/done.pcp ]]; then
               rm -rf $wrkdir/MPAS-A_${runname}f??.grib2
            fi
            ;;
        post )
            #
            # Clean MPASSIT & UPP as the post-processing is done for the forecast hour
            #
            mpassit_dir="$rundir/mpassit"
            upp_dir="$rundir/upp"
            for ((h=0;h<=$fcst_hours;h+=$EXTINVL)); do
                hstr=$(printf "%02d" $h)
                fcst_time_str=$(date -d "$eventdate ${eventtime}:00 $h hours" +%Y-%m-%d_%H.%M.%S)
                if [[ -f $upp_dir/done.upp_$hstr ]]; then
                    if [[ $verb -eq 1 ]]; then
                        echo "Cleaning $upp_dir/post_$hstr & $mpassit_dir ......"
                    fi
                    rm -rf $upp_dir/post_$hstr
                    rm -f  $mpassit_dir/MPAS-A_out.${fcst_time_str}.nc
                    #rm -f  $mpassit_dir/done.mpassit$hstr $mpassit_dir/error.mpassit$hstr
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
#@ MAIN

jobs=(ungrib init lbc mpas mpassit upp clean)

WORKDIR="${rootdir}/run_dirs"
TEMPDIR="${rootdir}/templates"
eventdate="$eventdateDF"
eventtime="00"

domname="wofs_mpas"
mpscheme="mp_nssl2m"
extdm="hrrr"
init_dir=false
runcmd="sbatch"
dorun=true
verb=0
overwrite=1
jobsfromcmd=0
machine="Jet"
if [[ "$(hostname)" == odin* ]]; then
    machine="Odin"
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
            elif [[ ${2^^} == "ODIN" ]]; then
                machine=Odin
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
            case $2 in
            wofs_big | wofs_small | wofs_conus | wofs_mpas | wofs_mpas_small )
                domname=$2
                ;;
            * )
                echo "ERROR: domain name \"$2\" not supported."
                usage 1
            esac
            shift
            ;;
        -i)
            case ${2,,} in
            hrrr | gfs | rrfs | rrfsp )
                extdm=${2,,}
                ;;
            * )
                echo "ERROR: initialization model name \"$2\" not supported."
                usage 1
            esac
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
            if [[ ${2^^} == "NSSL" ]]; then
                mpscheme="mp_nssl2m"
            elif [[ ${2^^} == "THOMPSON" ]]; then
                mpscheme="Thompson"
            else
                echo "ERROR: Unsupported MP scheme name, got \"$2\"."
                usage 1
            fi
            shift
            ;;
        -*)
            echo "Unknown option: $key"
            usage 2
            ;;
        static* | geogrid* | ungrib* | init* | lbc* | mpas* | upp* | clean* | pcp* )
            jobs=(${key//,/ })
            jobsfromcmd=1
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

if [[ $init_dir != false ]]; then
    jobs=( "${jobs[@]/ungrib}" )
fi

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#
# Perform each task
#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#% ENTRY

mach="slurm"

if [[ $machine == "Jet" ]]; then
    account="${hpcaccount-wof}"
    ncores_ics=6; ncores_fcst=6; ncores_post=6
    partition="ujet,tjet,xjet,vjet,kjet"; claim_cpu="--ntasks-per-node=${ncores_fcst}"
    partition_static="bigmem"           ; static_cpu="--cpus-per-task=12"
    partition_upp="kjet,xjet,vjet"

    modulename="build_jet_intel18_1.6_smiol"
    WPSGEOG_PATH="/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/WPS_GEOG/"
    wgrib2path="/apps/wgrib2/0.1.9.6a/bin/wgrib2"
elif [[ $machine == "Cheyenne" ]]; then
    if [[ $dorun == true ]]; then
        runcmd="qsub"
    fi
    account="${hpcaccount-NMMM0013}"
    ncores_ics=30; ncores_fcst=30; ncores_post=30
    partition="regular"        ; claim_cpu="ncpus=${ncores_fcst}"
    partition_static="regular" ; static_cpu="30"
    partition_upp="regular"
    mach="pbs"

    modulename="build_jet_intel18_1.6_smiol"
    WPSGEOG_PATH="/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/WPS_GEOG/"
    wgrib2path="/apps/wgrib2/0.1.9.6a/bin/wgrib2"
else
    account="${hpcaccount-smallqueue}"
    ncores_ics=24; ncores_fcst=24; ncores_post=24
    partition="wofq"                    ; claim_cpu="--ntasks-per-node=${ncores_fcst}"
    partition_static="smallqueue"       ; static_cpu=""
    partition_upp="smallqueue"

    modulename="env.mpas_smiol"
    WPSGEOG_PATH="/scratch/wof/realtime/geog/"
    wgrib2path=""
fi
npeics=800;   nnodes_ics=$((  npeics/ncores_ics   ))
npefcst=1200; nnodes_fcst=$(( npefcst/ncores_fcst ))
npepost=72;   nnodes_post=$(( npepost/ncores_post ))

fcst_hours=48
MPASLSM='ruc'
MPASNFLS=9


EXTINVL=3
EXTINVL_STR="${EXTINVL}:00:00"

OUTINVL=1
OUTINVL_STR="${OUTINVL}:00:00"
OUTIOTYPE="netcdf4"
ICSIOTYPE="pnetcdf,cdf5"

echo "---- Jobs ($$) started $(date +%m-%d_%H:%M:%S) on host $(hostname) ----"
echo "     Event date : $eventdate ${eventtime}:00"
echo "     Root    dir: $rootdir"
echo "     Working dir: $WORKDIR"
echo "     Domain name: $domname;  MP scheme: ${mpscheme};  IC/LBCs model: ${extdm^^}"
echo " "

starttime_str=$(date -d "$eventdate ${eventtime}:00"                     +%Y-%m-%d_%H:%M:%S)
stoptime_str=$(date -d "$eventdate  ${eventtime}:00 ${fcst_hours} hours" +%Y-%m-%d_%H:%M:%S)

case $extdm in
    gfs)
        EXTHEAD="GFS0p25"
        EXTNFGL=57
        EXTNFLS=4
        initname="GFS"
        ;;
    hrrr)
        EXTHEAD="HRRR"
        EXTNFGL=51
        EXTNFLS=9
        initname="H"
        ;;
    rrfsp)
        EXTHEAD="RRFSP"
        EXTNFGL=46
        EXTNFLS=9
        initname="RP"
        ;;
    rrfs)
        EXTHEAD="RRFS"
        EXTNFGL=66
        EXTNFLS=9
        initname="R"
        ;;
    *)
        echo "ERROR: unsupported initializaiton model name \"$extdm\"."
        usage 5
        ;;
esac

if [[ "${mpscheme}" == "Thompson" ]]; then
    mpname="T"
else
    mpname="N"
fi

runname="${eventdate}${eventtime}_${initname}${mpname}"
rundir="$WORKDIR/${runname}"

if [[ ! -d $rundir ]]; then
    mkdir -p $rundir
fi

jobname="${eventdate:4:4}"

#MPASModel="MPAS-Model.hrrr"
#exedir="${rootdir}/${MPASModel}"
#staticdir="${rootdir}/${MPASModel}"

exedir="$rootdir/exec"

staticdir="$TEMPDIR"

declare -A jobargs=([static]=$WORKDIR/$domname                          \
                    [geogrid]=$WORKDIR/${domname/*_/geo_}               \
                    [ungrib_hrrr]="/public/data/grids/hrrr/conus/wrfnat/grib2" \
                    [ungrib_rrfs]="https://noaa-rrfs-pds.s3.amazonaws.com"  \
                    [ungrib_rrfsp]="https://noaa-rrfs-pds.s3.amazonaws.com" \
                    [ungrib_gfs]="/public/data/grids/gfs/0p25deg/grib2"           \
                    [init]="ungrib/done.ungrib_ics $WORKDIR/$domname/done.static" \
                    [lbc]="init/done.ics ungrib/done.ungrib_lbc"                  \
                    [mpas]="lbc/done.lbc"                               \
                    [upp]=""                                            \
                    [pcp]=""                                            \
                    [clean]="post ungrib"                               \
                   )

#[ungrib_rrfs]="/mnt/lfs4/BMC/rtwbl/mhu/wcoss/emc/rrfs /public/data/grids/gfs/0p25deg/grib2  rrfs_a" \
#[ungrib_rrfsp]="/mnt/lfs4/BMC/rtwbl/mhu/wcoss/emc/rrfs /public/data/grids/gfs/0p25deg/grib2 rrfs_a" \
#[ungrib_rrfs]="/mnt/lfs4/BMC/nrtrr/NCO_dirs/ptmp/com/RRFS_CONUS/para /public/data/grids/gfs/0p25deg/grib2 RRFS_conus_3km"  \

for job in ${jobs[@]}; do
    if [[ $verb -eq 1 ]]; then
        echo " "
        echo "run_$job ${jobargs[$job]}"
    fi

    if [[ "$job" == "ungrib" ]]; then
        jobfull="${job}_${extdm}"
        run_${jobfull} ${jobargs[${jobfull}]}
    else
        run_$job ${jobargs[$job]}
    fi
done

echo " "
echo "==== Jobs done $(date +%m-%d_%H:%M:%S) ===="
echo " "

exit 0
