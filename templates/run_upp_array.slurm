#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -q batch
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 00:05:00
#SBATCH --output=WRKDIR/uppHHMINSTR_%a_%j.log
ACCTSTR
#SBATCH -D .
#...Automatically change the directory to where
#   the job was launched
#

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

if [[ "MACHINE" == "Jet" ]]; then
    # shellcheck source=/dev/null # to ignore source path error
    source /etc/profile.d/modules.sh
    module purge
    module use ROOTDIR/modules
    module load MODULE
    module load wgrib2/2.0.8
else
    # shellcheck source=/dev/null # to ignore source path error
    source /scratch/ywang/MPAS/mpas_runscripts/MODULE
fi
module list

ulimit -s unlimited

mem=${SLURM_ARRAY_TASK_ID}
memstr=$(printf "%02d" $mem)

wrkdir=WRKDIR/mem$memstr/post_HHMINSTR
cd $wrkdir

rm -rf ../error.uppHHMINSTR_${memstr} ../queue.uppHHMINSTR_${memstr}

touch ../running.uppHHMINSTR_${memstr}

rm -rf fort.* core.*

RUNMPCMD EXEDIR/unipost.exe

if [[ $? -eq 0 ]]; then
    dtstr=(${wrkdir//\// })

    grid_specs_hrrr="lambert:-97.5:38.5 -122.719528:1799:3000.0 21.138123:1059:3000.0"

    infile=WRFPRS.GrbFHHMINSTR
    tmpfile=tmpGrbFHHMINSTR.grib2
    outfile=../MPAS_${memstr}_${dtstr[-3]}fHHMINSTR.grib2

    wgrib2 ${infile} -set_bitmap 1 -set_grib_type c3 -new_grid_winds grid \
           -new_grid_vectors "UGRD:VGRD:USTM:VSTM:VUCSH:VVCSH" \
           -new_grid_interpolation neighbor \
           -new_grid ${grid_specs_hrrr} ${tmpfile}

    # Merge vector field records
    wgrib2 ${tmpfile} -new_grid_vectors "UGRD:VGRD:USTM:VSTM:VUCSH:VVCSH" -submsg_uv ${outfile}

    # Remove temporary file
    rm ${tmpfile} ${infile}

    #mv WRFPRS.GrbFHHMINSTR ../MPAS-A_${dtstr[-3]}fHHMINSTR.grib2

    touch ../done.uppHHMINSTR_${memstr}
else
    touch ../error.uppHHMINSTR_${memstr}
fi

rm -rf ../running.uppHHMINSTR_${memstr}

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "

