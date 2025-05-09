#!/bin/bash -l
#SBATCH --partition=batch
#SBATCH -J plot_increment
#SBATCH --ntasks=1 --ntasks-per-node=1 --mem=6G
#SBATCH --exclusive
#SBATCH -t 02:30:00
#SBATCH --output=./plot_increment_%j.log

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

source $HOME/.pythonrc
#conda activate wofs_post

ulimit -s unlimited

fcst_dir=$(pwd)

cd "/home/yunheng.wang/MPAS/intel/mpas_scripts.develop/python" || exit $?

domain="wofs_gsl"
patch_file="/scratch/wofs_mpas/run_dirs/20240507/dacycles_snglMYNN/1800/${domain}.115133.patches"

#### USER Modify and Check this block only ####
members=(33)
ftype="ana"   # "diag" "history" "init" "lbc"
cases=(increment)

datestr="2024-05-07 18:00:00"
times=(0)

fields=("theta" "qv"    "u10" "v10" "t2m" "q2" "surface_pressure" "refl10cm")
levels=("0,1,2" "0,1,2" 0     0     0     0    0                  "0,1,2")
cntlvls=(none   none    none  none  none  none none               none)

#### END of USER Section #######################

n=0
for nt in "${times[@]}"; do
    ntstr=$(date -d "${datestr} $nt minutes" +%Y-%m-%d_%H.%M.%S)
    #echo "$nt - $ntstr"

    #for case in "${cases[@]}"; do
        #outdir=${fcst_dir}/$case
        outdir=${fcst_dir}/${cases[0]}

    for mem in "${members[@]}"; do
        member=$(printf "%02d" $mem)

        for i in "${!fields[@]}"; do
            field=${fields[$i]}
            level=${levels[$i]}
            (( n++ ))

            case $ftype in
            diag | history | lbc )
                infile1=${fcst_dir}/${cases[0]}/wofs_mpas.${ftype}.${ntstr}.nc
                infile2=${fcst_dir}/${cases[1]}/wofs_mpas.${ftype}.${ntstr}.nc
                headstr="${domain}_${member}.${ftype}_${field}"
                ;;
            init)
                # init, case0 - case1
                infile1=${fcst_dir}/${cases[0]}/wofs_mpas.${ftype}.nc
                infile2=${fcst_dir}/${cases[1]}/wofs_mpas.${ftype}.nc
                headstr="${domain}_${member}.init_${field}"
                ;;
            ana )
                # analysis, Analysis - prior
                infile1=${fcst_dir}/${domain}_${member}.analysis
                infile2=${fcst_dir}/${domain}_${member}.prior.${ntstr}.nc
                headstr="${domain}_${member}.increment_${field}"
                ;;
            *)
                echo "Unsupported file type: $ftype."
                exit 1
                ;;
            esac

            cmdargs=(plot_mpaspatch.py -p "${patch_file}" -o "${outdir}" -k "${level}")

            if [[ "${cntlvls[$i]}" != "none" ]]; then
                cmdargs+=(-c "${cntlvls[$i]}")
            fi

            cmdargs+=(--head "${headstr}")
            cmdargs+=("${infile1}" "${infile2}" "${field}")

            echo ""
            echo "--- $n: $headstr $ntstr $field ---"
            echo "${cmdargs[*]}"
            python "${cmdargs[@]}"
            #echo  "plot_mpaspatch.py -p ${patch_file} -o ${outdir} ${infile1} ${infile2} ${field} -k \"${level}\" ${cntlvlstr} --head ${headstr}"
            #python plot_mpaspatch.py -p ${patch_file} -o ${outdir} ${infile1} ${infile2} ${field} -k "${level}" ${cntlvlstr} --head ${headstr}
        done
    done
    #done
done

time2=$(date '+%s')

diff=$(( time2-time1 ))
hour=$(( diff/3600  )); diff=$(( diff%3600 ))
min=$((  diff/60 ))
sec=$((  diff%60 ))

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
