#!/bin/bash

src_dir=/mnt/lfs5/NAGAPE/hpc-wof1/ywang/NCAR_JEDI/mpas_bundle_SP_jban_4july2025/
des_dir=/lfs5/NAGAPE/hpc-wof1/ywang/MPAS-WoFS/mpas_scripts.jedi

#
# exec
#
wrkdir="$des_dir/exec.NCAR"

src_names=(mpas_atmosphere  mpas_init_atmosphere)
des_names=(atmosphere_model init_atmosphere_model)

cd $wrkdir || exit $?
for i in "${!src_names[@]}"; do
    ln -sf ${src_dir}/build/bin/${src_names[$i]} ${des_names[$i]}
done

ln -sf /lfs5/NAGAPE/hpc-wof1/ywang/NCAR_JEDI/concatenate_netcdf/concatenate_netcdf_files.x .
ln -sf /lfs5/NAGAPE/hpc-wof1/ywang/NCAR_JEDI/average_netcdf_files/average_netcdf_files_parallel_mpas_efficient.x .

#
# fix files
#
wrkdir="$des_dir/fix_files.NCAR"

src_names=(CAM_ABS_DATA.DBL   CAM_AEROPT_DATA.DBL   GENPARM.TBL LANDUSE.TBL
            OZONE_DAT.TBL     OZONE_LAT.TBL OZONE_PLEV.TBL    RRTMG_LW_DATA
            RRTMG_LW_DATA.DBL RRTMG_SW_DATA RRTMG_SW_DATA.DBL SOILPARM.TBL
            VEGPARM.TBL)
des_names=(CAM_ABS_DATA.DBL   CAM_AEROPT_DATA.DBL   GENPARM.TBL LANDUSE.TBL
            OZONE_DAT.TBL     OZONE_LAT.TBL OZONE_PLEV.TBL    RRTMG_LW_DATA
            RRTMG_LW_DATA.DBL RRTMG_SW_DATA RRTMG_SW_DATA.DBL SOILPARM.TBL
            VEGPARM.TBL)

cd $wrkdir || exit $?

for i in "${!src_names[@]}"; do
    ln -sf ${src_dir}/build/MPAS/core_atmosphere/${src_names[$i]} ${des_names[$i]}
done

exit 0
