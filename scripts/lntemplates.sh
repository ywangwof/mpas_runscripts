#!/bin/bash

desdir=/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/runscriptv2.0/templates

if [[ $1 == "MPASSIT" ]]; then
    srcmpassit=/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/MPASSIT

    cd $desdir/MPASSIT

    parmfiles=(diaglist histlist_2d histlist_3d histlist_soil)
    for fn in ${parmfiles[@]}; do
        if [[ ! -e $fn ]]; then
            if [[ $verb -eq 1 ]]; then echo "Linking $fn ..."; fi
            ln -sf $srcmpassit/parm/$fn .
        fi
    done
#elif [[ $1 == "WRF" ]]; then
#    srcwps=/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/WPS_SRC
#    srcwrf=/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/WRFV4.0
#
#    cd $destdir/WRFV4.0
#
#    cp $srcwps/geogrid/GEOGRID.TBL.ARW .
#    cp $srcwps/ungrib/Variable_Tables/Vtable.GFS     Vtable.GFS_full
#    cp $srcwps/ungrib/Variable_Tables/Vtable.raphrrr Vtable.raphrrr
#
#
#    parmfiles=(ETAMPNEW_DATA ETAMPNEW_DATA.expanded_rain)
#    for fn in ${parmfiles[@]}; do
#        if [[ ! -e $fn ]]; then
#            if [[ $verb -eq 1 ]]; then echo "Linking $fn ..."; fi
#            cp $srcwrf/test/em_real/$fn .
#        fi
#    done

elif [[ $1 == "UPP" ]]; then
    srcupp=/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/UPP_KATE_kjet

    cd $desdir/UPP

    ln -sf $srcupp/src/lib/crtm2/src/fix crtm2_fix

elif [[ $1 == "mpas" ]]; then

    srcdir=/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/MPAS-Model.ted

    cd $desdir

    staticfiles=( CAM_ABS_DATA.DBL  CAM_AEROPT_DATA.DBL GENPARM.TBL       LANDUSE.TBL    \
            OZONE_DAT.TBL     OZONE_LAT.TBL       OZONE_PLEV.TBL    RRTMG_LW_DATA  \
            RRTMG_LW_DATA.DBL RRTMG_SW_DATA       RRTMG_SW_DATA.DBL SOILPARM.TBL   \
            VEGPARM.TBL )


    for fn in ${staticfiles[@]}; do
        echo "Linking $fn ...."
        ln -sf $srcdir/src/core_atmosphere/physics/physics_wrf/files/$fn .
    done

    streamfiles=( stream_list.atmosphere.diagnostics stream_list.atmosphere.output  \
        stream_list.atmosphere.surface streams.atmosphere streams.init_atmosphere   \
        namelist.atmosphere namelist.init_atmosphere )

    for fn in ${streamfiles[@]}; do
        echo "Linking $fn ...."
        ln -sf $srcdir/$fn .
    done
else
    echo "Argument should be one of [mpas, MPASSIT, WRF, UPP]. get \"$1\"."
fi

exit 0
