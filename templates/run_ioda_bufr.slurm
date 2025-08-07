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

if [[ "MACHINE" == "Jet" || "MACHINE" == "Hercules"  ]]; then
    module purge
    HOMErrfs="/lfs5/NAGAPE/hpc-wof1/ywang/GSL_JEDI/rrfs-workflow"
    module use ${HOMErrfs}/sorc/RDASApp/modulefiles
    module load RDAS/jet.intel
    module load py-jinja2 py-matplotlib py-cartopy py-netcdf4
    export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${HOMErrfs}/sorc/RDASApp/build/lib64
else
    source ROOTDIR/modules/MODULE
fi

ulimit -s unlimited

    CDATE=CURRDATE
    export PDY=${CDATE:0:8}
    export cyc=CYCHR

    cd WRKDIR || exit $?

    touch running.ioda_bufr
    rm -rf error.ioda_bufr queue.ioda_bufr

    cpreq="CPCMD"

    #-------------------------------------------------------------------
    OBSPATH=OBSDIR
    # link the prepbufr file
    ${cpreq} "${OBSPATH}/${CDATE}.rap.t${cyc}z.prepbufr.tm00"       prepbufr
    ${cpreq} "${OBSPATH}/${CDATE}.rap.t${cyc}z.gpsipw.tm00.bufr_d"  ztdbufr
    ${cpreq} "${OBSPATH}/${CDATE}.rap.t${cyc}z.satwnd.tm00.bufr_d"  satwndbufr
    ${cpreq} "${OBSPATH}/${CDATE}.rap.t${cyc}z.gsrcsr.tm00.bufr_d"  abibufr
    ${cpreq} "${OBSPATH}/${CDATE}.rap.t${cyc}z.atms.tm00.bufr_d"    atmsbufr
    ${cpreq} "${OBSPATH}/${CDATE}.rap.t${cyc}z.crisf4.tm00.bufr_d"  crisfsbufr
    #${cpreq} "EXEDIR/bufr2ioda.x" .
    #${cpreq} "EXEDIR/bufr2netcdf.x" .

    #-------------------------------------------------------------------
    # generate the namelist on the fly
    REFERENCE_TIME="${CDATE:0:4}-${CDATE:4:2}-${CDATE:6:2}T${CDATE:8:2}:00:00Z"

    yaml_list=(
        "prepbufr_adpsfc.yaml"
        #"prepbufr_adpupa.yaml"
        "prepbufr_aircar.yaml"
        "prepbufr_aircft.yaml"
        "prepbufr_ascatw.yaml"
        "prepbufr_msonet.yaml"
        "prepbufr_proflr.yaml"
        "prepbufr_rassda.yaml"
        "prepbufr_sfcshp.yaml"
        "prepbufr_vadwnd.yaml"
        "bufr2ioda_cris.yaml"
    )

    FIXrrfs=FIXDIR

    YAML_GEN_METHOD=1

    if (( YAML_GEN_METHOD == 2 )); then
        # Copy empty ioda file to data/obs.
        # Use these as the default when bufr2ioda doesn't create a ioda.
        # Otherwise JEDI will crash due to missing ioda file
        ${cpreq} "${FIXrrfs}"/jedi/ioda_empty.nc ioda_adpsfc.nc
        ${cpreq} "${FIXrrfs}"/jedi/ioda_empty.nc ioda_adpupa.nc
        ${cpreq} "${FIXrrfs}"/jedi/ioda_empty.nc ioda_aircar.nc
        ${cpreq} "${FIXrrfs}"/jedi/ioda_empty.nc ioda_aircft.nc
        ${cpreq} "${FIXrrfs}"/jedi/ioda_empty.nc ioda_ascatw.nc
        ${cpreq} "${FIXrrfs}"/jedi/ioda_empty.nc ioda_gpsipw.nc
        ${cpreq} "${FIXrrfs}"/jedi/ioda_empty.nc ioda_msonet.nc
        ${cpreq} "${FIXrrfs}"/jedi/ioda_empty.nc ioda_proflr.nc
        ${cpreq} "${FIXrrfs}"/jedi/ioda_empty.nc ioda_rassda.nc
        ${cpreq} "${FIXrrfs}"/jedi/ioda_empty.nc ioda_satwnd.nc
        ${cpreq} "${FIXrrfs}"/jedi/ioda_empty.nc ioda_sfcshp.nc
        ${cpreq} "${FIXrrfs}"/jedi/ioda_empty.nc ioda_vadwnd.nc
    fi

    # run bufr2ioda.x
    for yaml in "${yaml_list[@]}"; do
        sed -e "s/@referenceTime@/${REFERENCE_TIME}/" "${FIXrrfs}/jedi/${yaml}" > "${yaml}"
        #source prep_step
        RUNMPCMD EXEDIR/bufr2ioda.x "${yaml}"
         # some data may not be available at all cycles, so we don't check whether bufr2ioda.x runs successfully
    done

    # --------------------------------------------------
    # run  bufr2netcdf tool for atms bufr obs
    # --------------------------------------------------
    ${cpreq} "${FIXrrfs}/jedi/atms_beamwidth.txt" .
    ${cpreq} "${FIXrrfs}/jedi/bufr_atms_mapping.yaml" .
    input_file="atmsbufr"
    output_file="ioda.atms_{splits/satId}.nc"
    yaml="bufr_atms_mapping.yaml"
    if [[ -f "$input_file" ]]; then
        RUNMPCMD EXEDIR/bufr2netcdf.x "$input_file" "$yaml" "$output_file"
    else
        echo "Input file $input_file does not exist."
    fi

    # --------------------------------------------------
    # run python bufr2ioda tool for ZTD and AMV bufr obs
    HOMErdasapp=ROOTDIR/RDASApp/
    ${cpreq} "${HOMErdasapp}"/rrfs-test/IODA/python/bufr2ioda_adpupa_prepbufr.json .
    ${cpreq} "${HOMErdasapp}"/rrfs-test/IODA/python/bufr2ioda_adpupa_prepbufr.py .
    ${cpreq} "${HOMErdasapp}"/rrfs-test/IODA/python/bufr2ioda_ztd.py .
    #${cpreq} "${HOMErdasapp}"/rrfs-test/IODA/python/bufr2ioda_satwnd.py .
    ${cpreq} "${HOMErdasapp}"/rrfs-test/IODA/python/bufr2ioda.json .
    ${cpreq} "${HOMErdasapp}"/rrfs-test/IODA/python/bufr2ioda_gsrcsr.json .
    ${cpreq} "${HOMErdasapp}"/rrfs-test/IODA/python/bufr2ioda_gsrcsr.py .
    USHrrfs="ROOTDIR/RRFS_USH"
    ${cpreq} "${USHrrfs}/run_bufr2ioda_gsrcsr.sh" .

    # pyioda libraries
    PYIODALIB=$(echo "${HOMErdasapp}"/build/lib/python3.*)
    WXFLOWLIB=${USHrrfs}/wxflow/src
    export PYTHONPATH="${WXFLOWLIB}:${PYIODALIB}:${PYTHONPATH}"

    # generate a JSON w CDATE from the template and convert to IODA
    ${cpreq} "${HOMErdasapp}"/rrfs-test/IODA/python/gen_bufr2ioda_json.py .
    # ADPUPA
    ./gen_bufr2ioda_json.py -t bufr2ioda_adpupa_prepbufr.json -o bufr2ioda_adpupa_prepbufr_0.json
    ./bufr2ioda_adpupa_prepbufr.py -c bufr2ioda_adpupa_prepbufr_0.json

    # ZTD
    ./gen_bufr2ioda_json.py -t bufr2ioda.json -o bufr2ioda_0.json
    ./bufr2ioda_ztd.py -c bufr2ioda_0.json

    # SATWND
    #./bufr2ioda_satwnd.py -c bufr2ioda_0.json

    # GSRCSR
    DATA=WRKDIR
    ln -sf abibufr "rap.t${cyc}z.gsrcsr.tm00.bufr_d"
    ./run_bufr2ioda_gsrcsr.sh "${CDATE}" rap "${DATA}" "${DATA}" "${DATA}" "${HOMErdasapp}"
    cp "rap.t${cyc}z.abi_g16.tm00.nc" "ioda_abi_g16.nc"
    cp "rap.t${cyc}z.abi_g18.tm00.nc" "ioda_abi_g18.nc"

    # run offline IODA tools
    ${cpreq} "${USHrrfs}"/offline_domain_check.py .
    ${cpreq} "${USHrrfs}"/offline_domain_check_satrad.py .
    ${cpreq} "${USHrrfs}"/offline_ioda_tweak.py .
    ${cpreq} "${USHrrfs}"/offline_vad_thinning.py .

    for ioda_file in ioda*nc; do
        grid_file="GRIDFILE"
        #if [[ "${ioda_file}" == *abi* || "${ioda_file}" == *atms* || "${ioda_file}" == *cris* ]]; then
        if [[ "${ioda_file}" == *abi* ]]; then
            echo " ${ioda_file} ioda file detected: running offline_domain_check_satrad.py"
            ./offline_domain_check_satrad.py -o "${ioda_file}" -g "${grid_file}" -f -s 0.005
            base_name=$(basename "$ioda_file" .nc)
            mv  "${base_name}_dc.nc" "${base_name}.nc"
        elif [[ "${ioda_file}" == *atms* || "${ioda_file}" == *cris* ]]; then
            echo " ${ioda_file} ioda file detected: temporarily skipping offline domain check"
        else
            ./offline_domain_check.py -o "${ioda_file}" -g "${grid_file}" -s 0.005
            base_name=$(basename "$ioda_file" .nc)
            mv  "${base_name}_dc.nc" "${base_name}.nc"
            ./offline_ioda_tweak.py -o "${ioda_file}"
            base_name=$(basename "$ioda_file" .nc)
            mv  "${base_name}_llp.nc" "${base_name}.nc"
        fi
    done

    # Run vadwnd superobbing and thinning offline tool.
    ./offline_vad_thinning.py -i ioda_vadwnd.nc -o ioda_vadwnd_thinned.nc
    mv ioda_vadwnd_thinned.nc ioda_vadwnd.nc

    # file count sanity check and copy to COMOUT
    if ls ./ioda*nc; then
        #${cpreq} "$wrkdir/iods_bufr"/ioda*.nc "${COMOUT}/ioda_bufr/${WGF}"
        touch done.ioda_bufr
    else
        echo "FATAL ERROR: no ioda files generated."
        touch error.ioda_bufr
    fi

    rm -rf running.ioda_bufr

time2=$(date '+%s')

diff=$((time2-time1))

printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" $time2 $(date -d@$diff -u +%H:%M:%S)
