#!/bin/sh -l
#SBATCH -A wof
#SBATCH --partition=u1-compute
#SBATCH -J plot_mpas
#SBATCH --ntasks=1 --ntasks-per-node=1 --cpus-per-task=20
#SBATCH --exclusive
#SBATCH -t 02:30:00
#SBATCH --output=./plot_mpas_%j.log

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

source $HOME/.pythonrc
#conda activate wofs_post

ulimit -s unlimited

fcst_dir=$(pwd)

cd /scratch3/NAGAPE/wof/ywang/MPAS-WoFS/mpas_scripts.jedi/python

#### USER Modify and Check this block only ####
ftype="diag"   # "diag" "history" "init" "lbc"
datestr="2023-04-14 00:00:00"
times=$(seq 0 10 360)
cases=(fcst)
fields=(theta pressure qv)
levels=(0 0 0 0 0 0 0 0 "0,1,2" "0,1,2" ) #1d 2d 2d 0 0 0 2d "0,1,2,3")   # "max"  # column maximum values
cntlvls=("5340,5880,60" none none none none )

#### END of USER Section #######################

python plot_mpas.py -g wofs_mpas.invariant.nc -l 0,1,58 theta,pressure,qv wofs_mpas_01.init.2026-04-21_15.00.00.nc 2>/dev/null

time2=$(date '+%s')

diff=$((time2-time1))

printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" "${time2}" "$(date -d@$diff -u +%H:%M:%S)"
