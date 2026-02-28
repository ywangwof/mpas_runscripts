#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/fcst_%a_intrp_bc_%j.log
ACCTSTR
EXCLSTR

#set -eux

time1=$(date '+%s')
printf "Job Started: %(%a %b %d %H:%M:%S %Z %Y)T. Job Id: %s\n\n" $time1 $SLURM_JOBID

if [[ "MACHINE" == "Jet" || "MACHINE" == "Hercules" || "MACHINE" == "Ursa" ]]; then
    source /etc/profile.d/modules.sh
    module purge
    module use ROOTDIR/modules
    module load MODULE
else
    source ROOTDIR/modules/MODULE
fi

machine=MACHINE
source ROOTDIR/modules/env.python

ulimit -s unlimited

mem=${SLURM_ARRAY_TASK_ID}
memstr=$(printf "%02d" "${mem}")

domname=DOMNAME
casedir=CASEDIR

cd "WRKDIR/fcst_${memstr}" || exit $?

touch "running.intrp_bc_${memstr}"
rm -rf "error.intrp_bc_${memstr}" "queue.intrp_bc_${memstr}"

#-----------------------------------------------------------------------
# Copy working file
#-----------------------------------------------------------------------

lbctime_orgs1=(LBCTIMESTR1)         # What external model provided
lbctime_orgs2=(LBCTIMESTR2)

lbctime_exp=(LBCTIMESTR)           # What are required to run MPAS-Model

#
# Interpolate lbc files
#
istatus=0
for i in "${!lbctime_exp[@]}"; do

    lbctime="${lbctime_exp[$i]}"
    lbc_filem="${domname}_${memstr}.lbc.${lbctime}.nc"

    if [[ -e $lbc_filem ]]; then
        echo "    $lbc_filem exists, deleting ..."
        rm -rf "${lbc_filem}"
    fi

    lbc_origs1="${casedir}/lbc/${domname}_${memstr}.lbc.${lbctime_orgs1[$i]}.nc"
    lbc_origs2="${casedir}/lbc/${domname}_${memstr}.lbc.${lbctime_orgs2[$i]}.nc"

    echo ""
    echo "MEM ${memstr}: Interpolating lbc ${lbc_filem} file from"
    echo "                     ${lbc_origs1} and"
    echo "                     ${lbc_origs2}"

    srun --ntasks=1 --cpus-per-task=1 -N 1 ROOTDIR/scripts/intrp_time.py -t "${lbctime}" "${lbc_origs1}" "${lbc_origs2}" "${lbc_filem}" &

    (( istatus+=$? ))
done
wait

if [[ $istatus -eq 0 ]]; then
    touch "done.intrp_bc_${memstr}"
else
    touch "error.intrp_bc_${memstr}"
fi

rm -rf "running.intrp_bc_${memstr}"

time2=$(date '+%s')

diff=$((time2-time1))

printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" "$time2" "$(date -d@$diff -u +%H:%M:%S)"
