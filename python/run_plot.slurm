#!/bin/sh -l
#SBATCH -A wof
#SBATCH --partition=ujet,xjet,vjet,kjet
#SBATCH -J plot_mpas
#SBATCH --ntasks=1 --ntasks-per-node=1 --mem=64000
#SBATCH --exclusive
#SBATCH -t 02:30:00
#SBATCH --output=./plot_mpas_%j.log

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

source $HOME/.python
conda activate wofs_post

ulimit -s unlimited

fcst_dir=$(pwd)

cd /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/mpas_scripts/python

#### USER Modify and Check this block only ####
ftype="init" # "diag" "history"
datestr="2023-02-27"
times=(00)
cases=(init initp)
fields=(zz )        #ter surface_pressure skintemp theta relhum theta_base t2m w )
levels=("0,1,2,3" ) #1d 2d 2d 0 0 0 2d "0,1,2,3")   # "max"  # column maximum values
#### END of USER Section #######################

n=0
for nt in ${times[@]}; do
    for case in ${cases[@]}; do
        for i in ${!fields[@]}; do
            field=${fields[$i]}
            level=${levels[$i]}
            let n++

            outdir=${fcst_dir}/${case}

            case $ftype in
            diag | history )
                infile=${fcst_dir}/${case}/wofs_mpas.${ftype}.${datestr}_${nt}.00.00.nc
                ;;
            init)  # init
                infile=${fcst_dir}/${case}/wofs_mpas.${ftype}.nc
                ;;
            *)
                echo "Unsupported field type: $ftype."
                exit 1
                ;;
            esac

            echo ""
            echo "--- $n ---"
            echo "plot_mpaspatch.py -p wofs_mpas.1894063.patches -o ${outdir} ${infile} ${field} -l ${level}"
            plot_mpaspatch.py -p wofs_mpas.1894063.patches -o ${outdir} ${infile} ${field} -l ${level}
        done
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
