#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 00:10:00
#SBATCH --output=WRKDIR/fcst_%a_update_bc_%j.log
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
fi

ulimit -s unlimited

mem=${SLURM_ARRAY_TASK_ID}
memstr=$(printf "%02d" $mem)

cd WRKDIR/fcst_${memstr} || exit $?

touch running.update_bc_${memstr}
rm -rf error.update_bc_${memstr} queue.update_bc_${memstr}

#-----------------------------------------------------------------------
# Copy working file
#-----------------------------------------------------------------------

((iensidx = mem-1))

lbcfile_orgs1=(LBCFILEORGSTR1)         # What external model provided
lbcfile_orgs2=(LBCFILEORGSTR2)

lbcfile_mems=(LBCFILEMEMSSTR)          # What are required to run MPAS-Model
lbcfile_next=(LBCFILENEXTSTR)

lbcfile_mem1=(LBCFILEMEMS1)            # Interpolated orginal LBC files
lbcfile_mem2=(LBCFILEMEMS2)

#
# Copy the lbc file for this member
# Doing copy here because it will take too much time if it is done in the driver script.
#
lbc_origs1="${lbcfile_orgs1[$iensidx]}"
lbc_origs2="${lbcfile_orgs2[$iensidx]}"

lbc_filem="${lbcfile_mems[$iensidx]}"
lbc_filen="${lbcfile_next[$iensidx]}"

lbc_file1="${lbcfile_mem1[$iensidx]}"
lbc_file2="${lbcfile_mem2[$iensidx]}"

if [[ -e $lbc_filem ]]; then
    echo "    $lbc_filem exists, deleting ..."
    rm -rf "${lbc_filem}"
fi

if [[ -e $lbc_filen ]]; then
    echo "    $lbc_filen exists, deleting ..."
    rm -rf "${lbc_filen}"
fi

if [[ -f "${lbc_file1}" ]]; then
    echo "MEM ${memstr}: Using lbc file: ${lbc_file1} directly"
    CPCMD "${lbc_file1}" "${lbc_filem}"
else
    [[ "${lbc_filem}"  =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}.[0-9]{2}.[0-9]{2}) ]] && \
    time_mems=${BASH_REMATCH[1]}
    echo ""
    echo "MEM ${memstr}: Interpolating lbc ${lbc_filem} file from"
    echo "                     ${lbc_origs1} and"
    echo "                     ${lbc_origs2}"
    source ROOTDIR/modules/env.python
    ROOTDIR/scripts/intrp_time.py -t "${time_mems}" "${lbc_origs1}" "${lbc_origs2}" "${lbc_filem}"
fi

if [[ -f "${lbc_file2}" ]]; then
    echo "MEM ${memstr}: Using lbc file: ${lbc_file2} directly"
    ln -sf "${lbc_file2}" "${lbc_filen}"
else
    [[ "${lbc_filen}"  =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}.[0-9]{2}.[0-9]{2}) ]] && \
    time_next=${BASH_REMATCH[1]}
    echo ""
    echo "MEM ${memstr}: Interpolating lbc ${lbc_filen} file from"
    echo "                     ${lbc_origs1} and"
    echo "                     ${lbc_origs2}"
    echo ""
    source ROOTDIR/modules/env.python
    ROOTDIR/scripts/intrp_time.py -t "${time_next}" "${lbc_origs1}" "${lbc_origs2}" "${lbc_filen}"
fi

#if [[ "${lbc_file0}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}.[0-9]{2}.[0-9]{2}) ]]; then
#    lbctime1=${BASH_REMATCH[1]}
#fi
#
#if [[ "${lbc_filem}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}.[0-9]{2}.[0-9]{2}) ]]; then
#    lbctimeo=${BASH_REMATCH[1]}
#fi
#
#if [[ "$lbctimeo" == "$lbctime1" ]]; then
#    echo "MEM ${memstr}: Using lbc file: ${lbc_file0}"
#    echo "                     as ${lbc_filem} ..."
#    echo ""
#    CPCMD $lbc_file0 $lbc_filem
#else    # time interpolation from time1,time2 -> timeo
#    echo "MEM ${memstr}: Interpolating lbc ${lbc_filem} file from"
#    echo "                     ${lbc_file0} and"
#    echo "                     ${lbc_filen}"
#    echo ""
#    source ROOTDIR/modules/env.python
#    ROOTDIR/scripts/intrp_time.py -t ${lbctimeo} ${lbc_file0} ${lbc_filen} ${lbc_filem}
#fi

# for diagnostics and add some delays
sleep 10
#for idx in "${!lbcfile_orgs1[@]}"; do
#    (( indx = idx+1 ))
#    echo "$indx: ${lbcfile_orgs1[$idx]} --> ${lbcfile_mems[$idx]}"
#    echo "$indx: ${lbcfile_orgs2[$idx]} --> ${lbcfile_next[$idx]}"
#done

#-----------------------------------------------------------------------
# Run the job itself
#-----------------------------------------------------------------------

if [[ "UPDATEBC" == "true" ]]; then
    RUNMPCMD -n NOPART EXEDIR/update_bc
else
    echo "Program update_bc skipped."
fi

if [[ $? -eq 0 ]]; then
    touch done.update_bc_${memstr}
else
    touch error.update_bc_${memstr}
fi

rm -rf running.update_bc_${memstr}

time2=$(date '+%s')

diff=$((time2-time1))

printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" $time2 $(date -d@$diff -u +%H:%M:%S)
