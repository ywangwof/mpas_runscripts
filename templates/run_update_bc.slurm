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
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

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

cd WRKDIR/fcst_${memstr}

touch running.update_bc_${memstr}
rm -rf error.update_bc_${memstr} queue.update_bc_${memstr}

#-----------------------------------------------------------------------
# Copy working file
#-----------------------------------------------------------------------

((iensidx = mem-1))

lbcfile_orgs=(LBCFILEORGSTR)
lbcfile_mems=(LBCFILEMEMSTR)
lbcfile_next=(LBCFILENEXTSTR)

#
# Copy the lbc file for this member
# Doing copy here because it will take too much time if it is done in the driver script.
#
lbc_file0="${lbcfile_orgs[$iensidx]}"
lbc_filem="${lbcfile_mems[$iensidx]}"
lbc_filen="${lbcfile_next[$iensidx]}"

if [[ -e $lbc_filem ]]; then
    echo "    $lbc_filem exists, deleting ..."
    rm -rf $lbc_filem
fi

if [[ "${lbc_file0}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}.[0-9]{2}.[0-9]{2}) ]]; then
    lbctime1=${BASH_REMATCH[1]}
fi

if [[ "${lbc_filem}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}.[0-9]{2}.[0-9]{2}) ]]; then
    lbctimeo=${BASH_REMATCH[1]}
fi

if [[ "$lbctimeo" == "$lbctime1" ]]; then
    echo "MEM ${memstr}: Using lbc file: ${lbc_file0}"
    echo "                     as ${lbc_filem} ..."
    echo ""
    CPCMD $lbc_file0 $lbc_filem
else    # time interpolation from time1,time2 -> timeo
    echo "MEM ${memstr}: Interpolating lbc ${lbc_filem} file from"
    echo "                     ${lbc_file0} and"
    echo "                     ${lbc_filen}"
    echo ""
    source ROOTDIR/modules/env.python
    ROOTDIR/scripts/intrp_time.py -t ${lbctimeo} ${lbc_file0} ${lbc_filen} ${lbc_filem}
fi

# for diagnostics and add some delays
for idx in "${!lbcfile_orgs[@]}"; do
    (( indx = idx+1 ))
    echo "$indx: ${lbcfile_orgs[$idx]} --> ${lbcfile_mems[$idx]}"
done

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

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
