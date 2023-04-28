#!/bin/sh -l
#SBATCH -A wof
#SBATCH --partition=ujet,xjet,vjet,kjet
#SBATCH -J plot_mpas
#SBATCH --ntasks=1 --ntasks-per-node=1 --mem=64000
#SBATCH --exclusive
#SBATCH -t 02:30:00
#SBATCH --output=./plot_mpas_grib2_%j.log

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

source $HOME/.python
conda activate main

ulimit -s unlimited

fcst_dir=$(pwd)

cd /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/mpas_scripts/python

#### USER Modify and Check this block only ####

files=(NSSL_2310400000000)
cases=(2023041400_HT/ungrib 2023041400_HT.wgrib2rotated/ungrib)
fields=(u v)
levels=("0,1,2" "0,1,2" ) #1d 2d 2d 0 0 0 2d "0,1,2,3")   # "max"  # column maximum values
cntlvls=(none none "5340,5880,60" none none none none )

#### END of USER Section #######################

infile1=$fcst_dir/2023041400_HT/ungrib/NSSL_2310400000000
infile2=$fcst_dir/2023041400_HT.wgrib2rotated/ungrib/NSSL_2310400000000

outdir=$fcst_dir

for fn in ${files[@]}; do
    infile1=$fcst_dir/${cases[0]}/$fn
    infile2=$fcst_dir/${cases[1]}/$fn

    for i in ${!fields[@]}; do
        field=${fields[$i]}
        level=${levels[$i]}

       if [[ "${cntlvls[$i]}" == "none" ]]; then
           cntlvlstr=""
       else
           cntlvlstr="-c ${cntlvls[$i]}"
       fi

        echo ""
        echo "--- $field ---"
        echo "plot_grib2.py -o ${outdir} ${infile1} ${infile2} ${field} -l ${level}"
        plot_grib2.py -o ${outdir} ${infile1} ${infile2} ${field} -l ${level} $cntlvlstr
    done
done

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
