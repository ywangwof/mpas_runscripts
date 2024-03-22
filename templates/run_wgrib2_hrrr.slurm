#!/bin/sh -l
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
    module load wgrib2/2.0.8
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

cd WRKDIR

wgrib2path="wgrib2"
hrrrbase=GRIBFILE
targetbase=TARGETFILE
verb=VERBOSE

fhr=${SLURM_ARRAY_TASK_ID}
hstr=$(printf "%02d" $fhr)

hrrrfile="$hrrrbase$hstr"
basefn="$targetbase$hstr"

touch running.wgrib2_${hstr}
rm -rf error.wgrib2_${hstr} queue.wgrib2

# drop un-wanted records
if [[ $fhr -eq 0 ]]; then
    valtime="anl"
else
    valtime="$fhr hour fcst"
fi
echo "HRRR file: $hrrrfile ($valtime)"

rm -f keep_$hstr.txt
cat << EOF > keep_$hstr.txt
:PRES:[0-9]{1,2} hybrid level:${valtime}:
:CLMR:[0-9]{1,2} hybrid level:${valtime}:
:CIMIXR:[0-9]{1,2} hybrid level:${valtime}:
:RWMR:[0-9]{1,2} hybrid level:${valtime}:
:SNMR:[0-9]{1,2} hybrid level:${valtime}:
:GRLE:[0-9]{1,2} hybrid level:${valtime}:
:HGT:[0-9]{1,2} hybrid level:${valtime}:
:TMP:[0-9]{1,2} hybrid level:${valtime}:
:SPFH:[0-9]{1,2} hybrid level:${valtime}:
:UGRD:[0-9]{1,2} hybrid level:${valtime}:
:VGRD:[0-9]{1,2} hybrid level:${valtime}:
:SPNCR:[0-9]{1,2} hybrid level:${valtime}:
:NCONCD:[0-9]{1,2} hybrid level:${valtime}:
:NCCICE:[0-9]{1,2} hybrid level:${valtime}:
:PMTF:[0-9]{1,2} hybrid level:${valtime}:
:PMTC:[0-9]{1,2} hybrid level:${valtime}:
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
:MSLMA:mean sea level:${valtime}:
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
#grib2cmdstr="${wgrib2path} $hrrrfile | grep -Ef keep_$hstr.txt | ${wgrib2path} -i $hrrrfile -GRIB tmp_${basefn}"
grib2cmdstr="${wgrib2path} $hrrrfile | grep -Ef keep_$hstr.txt | ${wgrib2path} -i $hrrrfile -GRIB ${basefn}"
if [[ $verb -eq 1 ]]; then echo "$grib2cmdstr"; fi
eval $grib2cmdstr >& /dev/null
sleep 2

#
# convert to Earth-relative winds
#
#griddefn=$(grid_defn tmp_${basefn})
#echo "grid defn = \"$griddefn\" "
#${wgrib2path} tmp_${basefn} -set_grib_type same -new_grid_winds earth -new_grid $(grid_defn tmp_${basefn}) ${basefn}

#
# Clean working files
#
if [[ $verb -ne 1 ]]; then
    rm -rf tmp_${basefn}
    rm -rf keep_$hstr.txt
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

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
