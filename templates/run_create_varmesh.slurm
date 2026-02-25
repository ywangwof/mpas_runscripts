#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=1 CPUSPEC
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/JOBNAME_%j.log
EXCLSTR
ACCTSTR

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

if [[ "MACHINE" == "Jet" || "MACHINE" == "Hercules"  ]]; then
    module purge
    module use ROOTDIR/modules
    module load MODULE
else
    source ROOTDIR/modules/MODULE
fi

source ROOTDIR/modules/env.python

cd WRKDIR

mesh_radius=MESHRADIUS    # KM
scale_factor=SCALEFACTOR

mesh_orig="mesh${mesh_radius}km"
mesh_scaled="mesh${mesh_radius}km_scaled_${scale_factor}"

rm -f queue.create error.create

touch running.create

istatus=0
while [[ istatus -eq 0 ]]; do

   cat > ${mesh_orig}.pnts << EOF
Name: ${mesh_orig}
Type: circle
Point: 0.0, 0.0
radius: $((mesh_radius*1000))
EOF
    ln -sf EXEDIR/limited_area .
    ln -sf EXEDIR/create_region .

    # 1. cut a limited area mesh from the 60-3 km mesh using the create_region tool

    if RUNMPCMD -n 1 create_region -v 2 ${mesh_orig}.pnts ./x20.835586.grid.nc; then
        echo -e "\n${mesh_orig}.grid.nc and ${mesh_orig}.graph.info created successfully.\n"
    else
        istatus=$?
        echo -e "\nMesh cutout failed."
        break
    fi

    ## 2. rotate the regional mesh to the desired location by using the grid_rotate tool

    #if RUNMPCMD -n 1 EXEDIR/grid_rotate "${mesh_orig}.grid.nc" "${mesh_rotated}.grid.nc"; then
    #    echo -e "\n${mesh_rotated}.grid.nc created successfully.\n"
    #else
    #    istatus=$?
    #    echo -e "\nMesh rotation failed.\n"
    #    break
    #fi

    # 3. Scale the mesh using the mesh scaling
    # positional arguments:
    #   orig_mesh    the original regional mesh netCDF file
    #   scaled_mesh  the scaled regional mesh netCDF file to be created
    #   scale_fac    the scale factor. Values >1.0 increase the mesh resolution.
    #   tan_lat      the latitude of the tangent point, in degrees
    #   tan_lon      the longitude of the tangent point, in degrees

    if RUNMPCMD -n 1 EXEDIR/scale_region.py "${mesh_orig}.grid.nc" "${mesh_scaled}.grid.nc" ${scale_factor} 0. 0.; then
        echo -e "\n${mesh_scaled}.grid.nc created successfully.\n"
        ln -sf "${mesh_orig}.graph.info" "${mesh_scaled}.graph.info"
    else
        istatus=$?
        echo -e "\nMesh scaling failed.\n"
        break
    fi

    ## 4. Plot the final mesh and output statistics
    #RUNMPCMD -n 1 ROOTDIR/python/mpasmesh_plot.py "${mesh_scaled}.grid.nc"
    #istatus=$?

    break
done

if [[ $istatus -eq 0 ]]; then
    touch done.create
else
    touch error.create
fi

rm -f running.create

time2=$(date '+%s')

diff=$((time2-time1))

printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" "$time2" "$(date -d@$diff -u +%H:%M:%S)"

exit 0
