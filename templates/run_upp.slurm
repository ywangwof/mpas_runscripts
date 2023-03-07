#!/bin/bash
#SBATCH -A ACCOUNT
#SBATCH --partition=PARTION
#SBATCH -q batch
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 00:05:00
#SBATCH --output=WRKDIR/upp_HHHSTR_%j.log
#SBATCH -D .
#...Automatically change the directory to where
#   the job was launched
#

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

if [[ "MACHINE" == "Jet" ]]; then
    source /etc/profile.d/modules.sh
    module purge
    module use ROOTDIR/modules
    module load MODULE
    module load wgrib2/2.0.8
else
    source /scratch/ywang/MPAS/MODULE
fi
module list

ulimit -s unlimited

wrkdir=WRKDIR
cd $wrkdir

rm -rf ../error.upp_HHHSTR ../queue.upp_HHHSTR

touch ../running.upp_HHHSTR

rm -rf fort.* core.*

srun EXEDIR/unipost.exe

if [[ $? -eq 0 ]]; then
    dtstr=(${wrkdir//\// })

    grid_specs_hrrr="lambert:-97.5:38.5 -122.719528:1799:3000.0 21.138123:1059:3000.0"

    infile=WRFPRS.GrbFHHHSTR
    tmpfile=tmpGrbFHHHSTR.grib2
    outfile=../MPAS-A_${dtstr[-3]}fHHHSTR.grib2

    wgrib2 ${infile} -set_bitmap 1 -set_grib_type c3 -new_grid_winds grid \
           -new_grid_vectors "UGRD:VGRD:USTM:VSTM:VUCSH:VVCSH" \
           -new_grid_interpolation neighbor \
           -new_grid ${grid_specs_hrrr} ${tmpfile}

    # Merge vector field records
    wgrib2 ${tmpfile} -new_grid_vectors "UGRD:VGRD:USTM:VSTM:VUCSH:VVCSH" -submsg_uv ${outfile}

    # Remove temporary file
    rm ${tmpfile} ${infile}

    #mv WRFPRS.GrbFHHHSTR ../MPAS-A_${dtstr[-3]}fHHHSTR.grib2

    #
    # hourly accumulated precipitation
    #
    if true; then
        final_file="../MPAS-A_PCP_${dtstr[-3]}fHHHSTR.grib2"
        if [[ HHHSTR -lt 2 ]]; then
            cp $outfile $final_file
        else
            hr2=HHHSTR
            hr1=$((10#HHHSTR-1))
            hr1str=$(printf "%02d" $hr1)

            infile2="$outfile"
            infile1="../MPAS-A_${dtstr[-3]}f${hr1str}.grib2"

            tmpfile1="pcp1.grib2"
            tmpfile2="pcp2.grib2"
            tmpfile3="pcp3.grib2"

            while [[ ! -e ../done.upp_${hr1str} ]]; do
                echo "Waiting for ../done.upp_${hr1str}"
                sleep 10
            done

            wgrib2 $infile1 -match_fs "APCP" -grib_out $tmpfile1
            wgrib2 $infile2 -match_fs "APCP" -grib_out $tmpfile2

            wgrib2 $tmpfile1 -rpn sto_1 -import_grib $tmpfile2 -rpn sto_2 -set_grib_type same \
                -if_reg "1:2" -rpn "rcl_2:rcl_1:-:clr_1:clr_2" -set_scaling same same \
                -set_ftime "${hr1}-${hr2} hour acc fcst" -grib_out ${tmpfile3}

            wgrib2 ${outfile} -not APCP -grib ${tmpfile}
            cat ${tmpfile3} >> ${tmpfile}

            # Merge vector field records
            wgrib2 ${tmpfile} -new_grid_vectors "UGRD:VGRD:USTM:VSTM:VUCSH:VVCSH" -submsg_uv ${final_file}

            rm -rf ${tmpfile} ${tmpfile1} ${tmpfile2} ${tmpfile3}
        fi
    fi

    touch ../done.upp_HHHSTR
else
    touch ../error.upp_HHHSTR
fi

rm -rf ../running.upp_HHHSTR

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "

