#!/bin/sh -l
#SBATCH -A wof
#SBATCH --partition=ujet,xjet,vjet,kjet
#SBATCH -J plot_grib2
#SBATCH --ntasks=1 --ntasks-per-node=1 --mem=6G
#SBATCH --exclusive
#SBATCH -t 02:30:00
#SBATCH --output=./plot_grib2_%j.log

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

files=(tp hp)
times=$(seq 0 60 2880)
cases=(upp upp.realtime)
fields=(tp)
levels=("0" "0" )  # "max"  # column maximum values
cntlvls=("none")

#### END of USER Section #######################

#for case in ${cases[@]}; do
    for nt in ${times[@]}; do
        fhr=$((nt/60))
        fhrstr=$(printf "%02d" $fhr)
        for fn in ${files[@]}; do
            infile1=$fcst_dir/${cases[0]}/${fn}_${fhrstr}.grib2
            infile2=$fcst_dir/${cases[1]}/${fn}_${fhrstr}.grib2
            outdir=$fcst_dir/${case}/${fn}_${fhrstr}.png

        for i in ${!fields[@]}; do
            field=${fields[$i]}
            level=${levels[$i]}

           if [[ "${cntlvls[$i]}" == "none" ]]; then
               cntlvlstr=""
           else
               cntlvlstr="-c ${cntlvls[$i]}"
           fi

            echo ""
            echo "--- $infile $field ---"
            echo "plot_grib2.py -o ${outdir} ${infile1} ${infile2} ${field} -l ${level} $cntlvlstr -t surface"
            plot_grib2.py -o ${outdir} ${infile1} ${infile2} ${field} -l ${level} $cntlvlstr -t surface
            done
        done
    done
#done

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
