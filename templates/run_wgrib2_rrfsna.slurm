#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=1 --cpus-per-task=12
#SBATCH -t 0:30:00
#SBATCH --output=WRKDIR/wgrib2_%j_%a.log
ACCTSTR
EXCLSTR

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
    module load gnu/13.2.0 wgrib2/3.1.1_wmo
    wgrib2path="/apps/wgrib2/3.1.1/gnu_13.2.0/wmo/bin/wgrib2"
else
    # shellcheck source=/dev/null # to ignore source path error
    source /scratch/ywang/MPAS/MODULE
fi
module list

ulimit -s unlimited

########################################################################

function grid_defn {
    # 04/25/2023: based on grid_defn.pl by 10/2012 Wesley Ebisuzaki
    #
    #   finds the grid definition of the 1st record of a grib2 file
    #   grid defintion is compatible with wgrib2's -new_grid
    #
    #   uses: you want to interpolate to a grid as determined by a grib2 file
    #
    #   ex. wgrib2 IN.grib -new_grid_winds earth -new_grid `grid_defn.pl output_grid.grb` OUT.grib
    #
    #   usage: grid_defn.pl [grib file]
    #
    #   limitations: only supports lambert conformal currently
    #    #, lat-lon, (global) gaussian, polar stereographic
    #    # will come later as need is arised.
    #

    if [[ $# -ne 1 ]]; then
       echo "grid_defn.sh "
       echo "argument:  grib2 file"
       echo "output:    grid definiton that is compatible with wgrib2 -new_grid"
       exit 8
    fi

    grid=$(${wgrib2path} -d 1 -grid $1)
    #echo $grid
    gridstr=${grid// /_}
    grids=(${gridstr//:/ })
    #echo ${grids[@]}
    if [[ ${grids[4]} == "Lambert_Conformal" ]]; then
        if [[ ${grids[5]} =~ _\(([0-9]*)_x_([0-9]*)\)_input_([A-Z]{2}) ]]; then
            nx=${BASH_REMATCH[1]}
            ny=${BASH_REMATCH[2]}
            scan=${BASH_REMATCH[3]}

            if [[ ! $scan =~ WE|SN ]]; then
               echo "grid scan is $scan, unsupported by -new_grid"
               exit 1
            fi
        else
            echo "5th element is not right, got: ${grids[5]}"
            exit 1
        fi
        #echo $nx, $ny, $scan


        if [[ ${grids[8]} =~ Lat1_([0-9.]*)_Lon1_([0-9.]*)_LoV_([0-9.]*) ]]; then
            lat1=${BASH_REMATCH[1]}
            lon1=${BASH_REMATCH[2]}
            lov=${BASH_REMATCH[3]}
        else
            echo "8th element is not right, got: ${grids[8]}"
            exit 2
        fi
        #echo $lat1, $lon1, $lov


        if [[ ${grids[9]} =~ LatD_([0-9.]*)_Latin1_([0-9.]*)_Latin2_([0-9.]*) ]]; then
            latd=${BASH_REMATCH[1]}
            latin1=${BASH_REMATCH[2]}
            latin2=${BASH_REMATCH[3]}
        else
            echo "11th element is not right. got: ${grids[9]}"
            exit 3
        fi
        #echo $latd, $latin1, $latin2


        if [[ ${grids[11]} =~ .*_Dx_([0-9.]*)_m_Dy_([0-9.]*)_m_mode_. ]]; then
            dx=${BASH_REMATCH[1]}
            dy=${BASH_REMATCH[2]}
        else
            echo "11th element is not right. got: ${grids[11]}"
            exit 4
        fi
        #echo $dx, $dy

        echo "lambert:$lov:$latin1:$latin2:$latd $lon1:$nx:$dx $lat1:$ny:$dy"
    else
        echo "unknown grid sorry";
        exit 5
    fi
    exit 0
}

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

cd WRKDIR || exit $?

wgrib2path="wgrib2"
verb=VERBOSE

fhr=${SLURM_ARRAY_TASK_ID}
hstr=$(printf "%02d" $fhr)

touch running.wgrib2_${hstr}
rm -rf error.wgrib2_${hstr} queue.wgrib2_${hstr}

rrfsfile="GRIBFILE$hstr.na.grib2"
basefn="TARGETFILE$hstr.na.grib2"

#
# Trim out un-wanted records
#
if [[ $fhr -eq 0 ]]; then
    valtime="anl"
else
    valtime="$fhr hour fcst"
fi
echo "RRFSNA file: $rrfsfile ($valtime)"

rm -f keep_$hstr.txt
cat << EOF > keep_$hstr.txt
:PRES:[0-9]{1,2} hybrid level:${valtime}:
:CLMR:[0-9]{1,2} hybrid level:${valtime}:
:ICMR:[0-9]{1,2} hybrid level:${valtime}:
:RWMR:[0-9]{1,2} hybrid level:${valtime}:
:SNMR:[0-9]{1,2} hybrid level:${valtime}:
:GRLE:[0-9]{1,2} hybrid level:${valtime}:
:HGT:[0-9]{1,2} hybrid level:${valtime}:
:TMP:[0-9]{1,2} hybrid level:${valtime}:
:SPFH:[0-9]{1,2} hybrid level:${valtime}:
:UGRD:[0-9]{1,2} hybrid level:${valtime}:
:VGRD:[0-9]{1,2} hybrid level:${valtime}:
:TMP:2 m above ground:${valtime}:
:SPFH:2 m above ground:${valtime}:
:RH:2 m above ground:${valtime}:
:UGRD:10 m above ground:${valtime}:
:VGRD:10 m above ground:${valtime}:
:PRES:surface:${valtime}:
:SNOD:surface:${valtime}:
:WEASD:surface:${valtime}:
:TMP:surface:${valtime}:
:CNWAT:surface:${valtime}:
:HGT:surface:${valtime}:
:MSLET:mean sea level:${valtime}:
:TSOIL:0-0 m below ground:${valtime}:
:TSOIL:0.01-0.01 m below ground:${valtime}:
:TSOIL:0.04-0.04 m below ground:${valtime}:
:TSOIL:0.1-0.1 m below ground:${valtime}:
:TSOIL:0.3-0.3 m below ground:${valtime}:
:TSOIL:0.6-0.6 m below ground:${valtime}:
:TSOIL:1-1 m below ground:${valtime}:
:TSOIL:1.6-1.6 m below ground:${valtime}:
:TSOIL:3-3 m below ground:${valtime}:
:SOILW:0-0 m below ground:${valtime}:
:SOILW:0.01-0.01 m below ground:${valtime}:
:SOILW:0.04-0.04 m below ground:${valtime}:
:SOILW:0.1-0.1 m below ground:${valtime}:
:SOILW:0.3-0.3 m below ground:${valtime}:
:SOILW:0.6-0.6 m below ground:${valtime}:
:SOILW:1-1 m below ground:${valtime}:
:SOILW:1.6-1.6 m below ground:${valtime}:
:SOILW:3-3 m below ground:${valtime}:
:LAND:surface:${valtime}:
:ICEC:surface:${valtime}:
EOF

echo "Generating working copy: $basefn ...."
grib2cmdstr="${wgrib2path} $rrfsfile | grep -Ef keep_$hstr.txt | ${wgrib2path} -i $rrfsfile -GRIB tmp_${basefn}"
if [[ $verb -eq 1 ]]; then echo "$grib2cmdstr"; fi
eval $grib2cmdstr >& /dev/null

#
# convert to Earth-relative winds
# NOT needed since MPAS can handle the rotation itself.
#
#griddefn=$(grid_defn tmp_${basefn})
#echo "grid defn = \"$griddefn\" "
#${wgrib2path} tmp_${basefn} -set_grib_type same -new_grid_winds earth -new_grid $(grid_defn tmp_${basefn}) ${basefn}

#
# Interpolate the records to the HRRR grid with lambert map projection
#
if [[ $? -eq 0 ]]; then
    grid_specs_hrrr="lambert:-97.5:38.5 -122.719528:1799:3000.0 21.138123:1059:3000.0"

    infile=tmp_${basefn}
    tmpfile=tmp_$hstr.grib2
    outfile=${basefn}

    wgrib2 ${infile} -set_bitmap 1 -set_grib_type c3 -new_grid_winds grid \
           -new_grid_vectors "UGRD:VGRD:USTM:VSTM:VUCSH:VVCSH"            \
           -new_grid_interpolation neighbor                               \
           -new_grid ${grid_specs_hrrr} ${tmpfile}

    # Merge vector field records
    wgrib2 ${tmpfile} -new_grid_vectors "UGRD:VGRD:USTM:VSTM:VUCSH:VVCSH" -submsg_uv ${outfile}
fi

#
# Set job status
#
if [[ $? -eq 0 ]]; then
    touch done.wgrib2_${hstr}
else
    touch error.wgrib2_${hstr}
fi

rm -rf running.wgrib2_${hstr}

#
# Clean working files
#
if [[ $verb -ne 1 ]]; then
    rm -rf tmp_${basefn}
    rm -rf keep_$hstr.txt
    rm -rf ${tmpfile}
fi

time2=$(date '+%s')

diff=$((time2-time1))
printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" $time2 $(date -d@$diff -u +%H:%M:%S)
