#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/JOBNAME_%j.log
ACCTSTR
EXCLSTR

#set -eux

time1=$(date '+%s')
echo -e "Job Started: $(date). Job Id:  $SLURM_JOBID\n"

# shellcheck disable=SC2050
if [[ "MACHINE" == "Jet" || "MACHINE" == "Hercules"  ]]; then
    module purge
    HOMErrfs="RRFSDIR"
    module use ${HOMErrfs}/sorc/RDASApp/modulefiles
    module load RDAS/jet.intel
    module load py-matplotlib
    export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${HOMErrfs}/sorc/RDASApp/build/lib64
else
    # shellcheck source=/dev/null
    source ROOTDIR/modules/MODULE
fi

ulimit -s unlimited

    cd "WRKDIR" || exit $?

    echo "Getting into working directory for radar reflectivity process ..."

    touch running.ioda_mrms_refl
    rm -rf error.ioda_mrms_refl queue.ioda_refl

    #
    #-----------------------------------------------------------------------
    #
    # Extract from CDATE the starting year, month, day, and hour of the
    # forecast.  These are needed below for various operations.
    #
    #-----------------------------------------------------------------------
    #
    CDATE=CURRDATE

    YYYY=${CDATE:0:4}
    MM=${CDATE:4:2}
    DD=${CDATE:6:2}
    HH=${CDATE:8:2}
    min=${CDATE:10:2}
    YYYYMMDD=${CDATE:0:8}

        #
        #-----------------------------------------------------------------------
        #
        # Run the radar refl process.
        #
        #-----------------------------------------------------------------------
        #

        RUNMPCMD "EXEDIR/process_NSSL_mosaic.exe"
        istatus=$?                    # check the status
        #err_chk

        #cp RefInGSI3D.dat  "${COMOUT}/ioda_mrms_refl/${WGF}/rrfs.t${HH}z.RefInGSI3D.bin.${bigmin}"

        if [[ $istatus -eq 0 ]]; then
        #
        #-----------------------------------------------------------------------
        #
        # Run ioda converter to generate radar reflectivity ioda file
        #
        #-----------------------------------------------------------------------
            # pyioda libraries
            PYIODALIB=$(echo "${HOMErrfs}"/sorc/RDASApp/build/lib/python3.*)
            export PYTHONPATH=${PYIODALIB}:${PYTHONPATH}
            "ROOTDIR/scripts/MRMS2ioda.py" -i ./Gridded_ref.nc -c "${YYYY}-${MM}-${DD}T${HH}:${min}:00" -o "ioda_mrms_${YYYYMMDD}_${HH}${min}.nc4" -g grid.nc
        fi

        # file count sanity check and copy to COMOUT
        if [[ -s "ioda_mrms_${YYYYMMDD}_${HH}${min}.nc4" ]]; then
            #${cpreq} "ioda_mrms_${YYYYMMDD}${HH}_${bigmin}.nc4" "${COMOUT}/ioda_mrms_refl/${WGF}"
            touch done.ioda_mrms_refl
        else
            echo "FATAL ERROR: no ioda MRMS file generated."
            touch error.ioda_mrms_refl
            #err_exit # err_exit if no ioda files generated at the development stage
        fi

rm -rf running.ioda_mrms_refl

time2=$(date '+%s')

diff=$((time2-time1))

printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" "$time2" "$(date -d@$diff -u +%H:%M:%S)"
