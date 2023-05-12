#!/bin/sh -l
#SBATCH -A wof
#SBATCH --partition=ujet,xjet,vjet,kjet
#SBATCH -J plot_mpas
#SBATCH --ntasks=1 --ntasks-per-node=1 --mem=6G
#SBATCH --exclusive
#SBATCH -t 02:30:00
#SBATCH --output=./plot_mpas_diff_%j.log

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
ftype="diag"   # "diag" "history" "init" "lbc"
datestr="2023-04-14"
times=$(seq 0 60 600)
cases=(fcst fcst.wgrib2rotated)
fields=(height_500hPa)
levels=(0 0 0 0 0 0 0 0 "0,1,2" "0,1,2" ) #1d 2d 2d 0 0 0 2d "0,1,2,3")   # "max"  # column maximum values
cntlvls=("5340,5880,60" none none none none )

#### END of USER Section #######################

n=0
for nt in ${times[@]}; do
    ntstr=$(date -d "${datestr} $nt minutes" +%Y-%m-%d_%H.%M.%S)
    #echo "$nt - $ntstr"

    #for case in ${cases[@]}; do
        for i in ${!fields[@]}; do
            field=${fields[$i]}
            level=${levels[$i]}
            let n++

            outdir=${fcst_dir}

            case $ftype in
            diag | history | lbc )
                infile1=${fcst_dir}/${cases[0]}/wofs_mpas.${ftype}.${ntstr}.nc
                infile2=${fcst_dir}/${cases[1]}/wofs_mpas.${ftype}.${ntstr}.nc
                ;;
            init)  # init
                infile1=${fcst_dir}/${cases[0]}/wofs_mpas.${ftype}.nc
                infile2=${fcst_dir}/${cases[1]}/wofs_mpas.${ftype}.nc
                ;;
            *)
                echo "Unsupported file type: $ftype."
                exit 1
                ;;
            esac

            if [[ "${cntlvls[$i]}" == "none" ]]; then
                cntlvlstr=""
            else
                cntlvlstr="-c ${cntlvls[$i]}"
            fi

            echo ""
            echo "--- $n: $case $ntstr $field ---"
            echo  "plot_mpaspatch.py -p wofs_mpas.1894063.patches -o ${outdir} ${infile1} ${infile2} ${field} -l ${level} ${cntlvlstr}"
            python plot_mpaspatch.py -p wofs_mpas.1894063.patches -o ${outdir} ${infile1} ${infile2} ${field} -l ${level} ${cntlvlstr}
    done
    #done
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
