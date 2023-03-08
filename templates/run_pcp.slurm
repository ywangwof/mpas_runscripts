#!/bin/bash
#SBATCH -A ACCOUNT
#SBATCH --partition=PARTION
#SBATCH -q batch
#SBATCH -J JOBNAME
#SBATCH --ntasks=1 CPUSPEC
#SBATCH -t 00:35:00
#SBATCH --output=WRKDIR/pcp_%j.log
#SBATCH -D .
#...Automatically change the directory to where
#   the job was launched
#

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

module load wgrib2/2.0.8

#-----------------------------------------------------------------------
#
# Handle command line arguments
#
#-----------------------------------------------------------------------
#% ARGS

wrkdir=WRKDIR

starthour=0
endhour=HHHSTR

lenghours=$((10#$endhour-starthour+1))

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#@ MAIN

cd $wrkdir

rm -rf error.pcp queue.pcp
touch running.pcp

#
# hourly accumulated precipitation
#
#                      y    y    y    y    m    m    d    d    H    H
infiles=($(ls MPAS-A_[0-2][0-9][0-9][0-9][0-1][0-9][0-3][0-9][0-2][0-9]_*f??.grib2))
if [[ ${#infiles[@]} -lt $lenghours ]]; then
    echo "ERROR: not enough files for forecast from $starthour to $endhour ($lenghours), get ${#infiles[@]}."
    echo "${infiles[@]}"
else
    fdcstr=${infiles[0]##MPAS-A_}
    fdcstr=${fdcstr%%f??.grib2}

    dtstr=${fdcstr%%_*}
    castr=${fdcstr##[0-9]*_}

    echo "Work directory   : $wrkdir"
    echo "Date time string : $dtstr"
    echo "Case name        : $castr"

    for hr2 in $(seq $starthour $endhour); do

        hr2str=$(printf "%02d" $hr2)
        infile2="MPAS-A_${dtstr}_${castr}f$hr2str.grib2"

        final_file="MPAS-A_PCP_${dtstr}_${castr}f$hr2str.grib2"

        if [[ -e $final_file ]]; then
            echo "File: $final_file exists. Skiping hour: $hr2str."
            continue
        fi

        while [[ ! -e done.upp_${hr2str} ]]; do
            echo "Waiting for done.upp_${hr2str}"
            sleep 10
        done

        if [[ $hr2 -lt 2 ]]; then
            cp $infile2 $final_file
        else
            echo "current hour = $hr2"
            hr1=$((10#$hr2-1))
            hr1str=$(printf "%02d" $hr1)

            infile1="MPAS-A_${dtstr}_${castr}f${hr1str}.grib2"

            tmpfile1="pcp1_${hr2str}.grib2"
            tmpfile2="pcp2_${hr2str}.grib2"
            tmpfile3="pcp3_${hr2str}.grib2"

            while [[ ! -e done.upp_${hr1str} ]]; do
                echo "Waiting for done.upp_${hr1str}"
                sleep 10
            done

            wgrib2 $infile1 -match_fs "APCP" -grib_out $tmpfile1
            wgrib2 $infile2 -match_fs "APCP" -grib_out $tmpfile2

            wgrib2 $tmpfile1 -rpn sto_1 -import_grib $tmpfile2 -rpn sto_2 -set_grib_type same \
                -if_reg "1:2" -rpn "rcl_2:rcl_1:-:clr_1:clr_2" -set_scaling same same \
                -set_ftime "${hr1}-${hr2} hour acc fcst" -grib_out ${tmpfile3}

            echo ""
            echo "$infile2 -> $final_file ...."
            cat ${infile2} ${tmpfile3} > ${final_file}

            #tmpfile="nopcp.grib2"
            #wgrib2 ${outfile} -not APCP -grib ${tmpfile}
            #cat ${tmpfile3} >> ${tmpfile}
            #wgrib2 ${tmpfile} -new_grid_vectors "UGRD:VGRD:USTM:VSTM:VUCSH:VVCSH" -submsg_uv ${final_file}

            rm -rf ${tmpfile} ${tmpfile1} ${tmpfile2} ${tmpfile3}
        fi

    done

    if [[ $? -eq 0 ]]; then
        touch done.pcp
    else
        touch error.pcp
    fi
fi

rm -rf running.pcp

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
