#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 02:30:00
#SBATCH --output=WRKDIR/intrp_PREFIX_%a_%j.log
ACCTSTR
EXCLSTR


#set -eux

time1=$(date '+%s')
printf "Job Started: %(%a %b %d %H:%M:%S %Z %Y)T. Job Id: %s\n\n" $time1 $SLURM_JOBID

if [[ "MACHINE" == "Jet" ]]; then
    source /etc/profile.d/modules.sh
    module purge
    module use ROOTDIR/modules
    module load MODULE
else
    source ROOTDIR/modules/MODULE
    source ROOTDIR/modules/env.python
fi

ulimit -s unlimited

mem=${SLURM_ARRAY_TASK_ID}
printf -v memstr "%02d" $mem

cd WRKDIR/PREFIX_$memstr || exit $?

touch running.intrp_PREFIX_$memstr
rm -rf error.intrp_PREFIX_$memstr queue.intrp_PREFIX_$memstr

#-----------------------------------------------------------------------
# Interpolate working file
#-----------------------------------------------------------------------

starttime_s=STARTSECS
stoptime_s=STOPSECS
intvl_sec=INTVL_SECS
domname=PREFIX

echo "Running time intrpolation ...."

for((i=starttime_s;i<=stoptime_s;i+=intvl_sec)); do
    min=$(date -u -d @$i +%M)
    j=$((10#$min*60))
    if [[ ${min} != "00" ]]; then
        i1=$((i-j))
        i2=$((i+3600-j))
        time_str=$(date  -u -d @$i  +%Y-%m-%d_%H.%M.%S)
        time_str1=$(date -u -d @$i1 +%Y-%m-%d_%H.%M.%S)
        time_str2=$(date -u -d @$i2 +%Y-%m-%d_%H.%M.%S)
        lbc_filename="${domname}_${memstr}.lbc.${time_str}.nc"
        lbc_file1="${domname}_${memstr}.lbc.${time_str1}.nc"
        lbc_file2="${domname}_${memstr}.lbc.${time_str2}.nc"
        if [[ ! -f ${lbc_filename} ]]; then
            echo "Interpolating lbc file: ${lbc_filename} file from"
            echo "                        ${lbc_file1} and"
            echo "                        ${lbc_file2}"
            ROOTDIR/scripts/intrp_time.py -t ${time_str} ../${lbc_file1} ../${lbc_file2} ../${lbc_filename}
        fi
    fi
done

if [[ $? -eq 0 ]]; then
    touch done.intrp_PREFIX_$memstr
else
    touch error.intrp_PREFIX_$memstr
fi

rm -rf running.intrp_PREFIX_$memstr

time2=$(date '+%s')

diff=$((time2-time1))

printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" $time2 $(date -d@$diff -u +%H:%M:%S)

