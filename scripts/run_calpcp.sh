#!/bin/bash

module load wgrib2/2.0.8

function usage {
    echo " "
    echo "    USAGE: $0 [options] [ENDHOUR] [WORKDIR] "
    echo " "
    echo "    PURPOSE: Calculate hourly PCP from accumulated PCP in MPAS grib2 files using wgrib2."
    echo "             Assume MPAS grib2 file pattern: MPAS-A_yyyymmddHH_XXfHY.grib2"
    echo "             Output grib2 file pattern     : MPAS-A_PCP_yyyymmddHH_XXfHY.grib2"
    echo " "
    echo "    ENDHOUR  - Forecast length in hours. Default: 36"
    echo "    WORKDIR  - Work Directory. Default: ./"
    echo " "
    echo "    OPTIONS:"
    echo "              -h              Display this message"
    echo "              -s  [0-36]      Forecast starting hour. Default: 0"
    echo "              -e  [0-36]      Forecast end hour. Default: 48"
    echo " "
    echo "                                     -- By Y. Wang (2023.03.08)"
    echo " "

    exit $1
}

#-----------------------------------------------------------------------
#
# Handle command line arguments
#
#-----------------------------------------------------------------------
#% ARGS

wrkdir='./'

starthour=0
endhour=48

while [[ $# > 0 ]]; do
    key="$1"

    case $key in
        -h)
            usage 0
            ;;
        -s )
            if [[ $2 =~ ^[0-9]{1,2}$ ]]; then
                starthour="$2"
            else
                 echo ""
                 echo "ERROR: unknown option, get [$2]."
                 usage 3
            fi
            shift
            ;;
        -e )
            if [[ $2 =~ ^[0-9]{1,2}$ ]]; then
                endhour="$2"
            else
                 echo ""
                 echo "ERROR: unknown option, get [$2]."
                 usage 3
            fi
            shift
            ;;
        *)
            if [[ $key =~ ^[0-9]{1,2}$ ]]; then
                endhour="$key"
            elif [[ -d $key ]]; then
                wrkdir=$key
            else
                 echo ""
                 echo "ERROR: unknown option, get [$key]."
                 usage 3
            fi
            ;;
    esac
    shift # past argument or value
done

lenghours=$((endhour-starthour+1))

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#@ MAIN

cd $wrkdir

#
# hourly accumulated precipitation
#
infiles=($(ls MPAS-A_[0-2][0-9][0-9][0-9][0-1][0-9][0-3][0-9][0-2][0-9]_HTf??.grib2))
if [[ ${#infiles[@]} -lt $lenghours ]]; then
    echo "ERROR: not enough files for forecast from $starthour to $endhour ($lenghours), get ${#infiles[@]}."
    echo "${infiles[@]}"
    exit 0
else
    fdcstr=${infiles[0]##MPAS-A_}
    fdcstr=${fdcstr%%f??.grib2}

    dtstr=${fdcstr%%_*}
    castr=${fdcstr##[0-9]*_}

    echo "Work directory   : $wrkdir"
    echo "Date time string : $dtstr"
    echo "Case name        : $castr"
fi

for hr2 in $(seq $starthour $endhour); do

    hr2str=$(printf "%02d" $hr2)
    infile2="MPAS-A_${dtstr}_${castr}f$hr2str.grib2"

    final_file="HR_PCP_${dtstr}_${castr}f$hr2str.grib2"

    if [[ -e $final_file ]]; then
        echo "File: $final_file exists. Skiping hour: $hr2str."
        continue
    fi

    #while [[ ! -e done.upp_${hr2str} ]]; do
    #    echo "Waiting for done.upp_${hr2str}"
    #    sleep 10
    #done

    if [[ $hr2 -lt 2 ]]; then
        cp $infile2 $final_file
    else
        echo $hr2
        hr1=$((10#$hr2-1))
        hr1str=$(printf "%02d" $hr1)

        infile1="MPAS-A_${dtstr}_${castr}f${hr1str}.grib2"

        tmpfile1="pcp1.grib2"
        tmpfile2="pcp2.grib2"
        tmpfile3="pcp3.grib2"

        #while [[ ! -e done.upp_${hr1str} ]]; do
        #    echo "Waiting for done.upp_${hr1str}"
        #    sleep 10
        #done

        #wgrib2 $infile1 -match_fs "APCP" -grib_out $tmpfile1
        #wgrib2 $infile2 -match_fs "APCP" -grib_out $tmpfile2
        wgrib2 $infile1 -for 98:98 -grib_out $tmpfile1
        wgrib2 $infile2 -for 98:98 -grib_out $tmpfile2

        wgrib2 $tmpfile1 -rpn sto_1 -import_grib $tmpfile2 -rpn sto_2 -set_grib_type same \
            -if_reg "1:2" -rpn "rcl_2:rcl_1:-:clr_1:clr_2" -set_scaling same same \
            -set_ftime "${hr1}-${hr2} hour acc fcst" -grib_out ${tmpfile3}

        #echo "$infile2 -> $final_file ...."
        #cat ${infile2} ${tmpfile3} > ${final_file}
        mv ${tmpfile3} ${final_file}

        #tmpfile="nopcp.grib2"
        #wgrib2 ${outfile} -not APCP -grib ${tmpfile}
        #cat ${tmpfile3} >> ${tmpfile}
        #wgrib2 ${tmpfile} -new_grid_vectors "UGRD:VGRD:USTM:VSTM:VUCSH:VVCSH" -submsg_uv ${final_file}

        rm -rf ${tmpfile} ${tmpfile1} ${tmpfile2} ${tmpfile3}
    fi

done

exit 0
