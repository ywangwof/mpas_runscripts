#!/bin/bash
srcdir=/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/MPAS-Model.ted
desdir=/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/runscriptv2.0/templates

staticfiles=( CAM_ABS_DATA.DBL  CAM_AEROPT_DATA.DBL GENPARM.TBL       LANDUSE.TBL    \
        OZONE_DAT.TBL     OZONE_LAT.TBL       OZONE_PLEV.TBL    RRTMG_LW_DATA  \
        RRTMG_LW_DATA.DBL RRTMG_SW_DATA       RRTMG_SW_DATA.DBL SOILPARM.TBL   \
        VEGPARM.TBL )

streamfiles=( stream_list.atmosphere.diagnostics stream_list.atmosphere.output  \
    stream_list.atmosphere.surface streams.atmosphere streams.init_atmosphere   \
    namelist.atmosphere namelist.init_atmosphere )


cd $desdir
for fn in ${staticfiles[@]}; do
    echo "Linking $fn ...."
    ln -sf $srcdir/src/core_atmosphere/physics/physics_wrf/files/$fn .
done

for fn in ${streamfiles[@]}; do
    echo "Linking $fn ...."
    ln -sf $srcdir/$fn .
done

exit 0
