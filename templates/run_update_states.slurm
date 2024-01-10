#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 00:10:00
#SBATCH --output=WRKDIR/update_states_%a_%j.log
ACCTSTR
EXCLSTR


#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

if [[ "MACHINE" == "Jet" || "MACHINE" == "Hercules"  ]]; then
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

touch running.update_states_$memstr
rm -rf error.update_states_$memstr queue.update_states_$memstr

#-----------------------------------------------------------------------
# Copy working file
#-----------------------------------------------------------------------

((iensidx = mem-1))

state_file_names=(STATEFILESSTR)

state_file_name="${state_file_names[$iensidx]}"

fnbase=$(basename ${state_file_name})
if [[ ! -e $fnbase ]]; then
    echo "    CPCMD ${state_file_name} ."
    echo ""
    CPCMD ${state_file_name} .

    # for diagnostics and add some delays
    for idx in "${!state_file_names[@]}"; do
        (( indx = idx+1 ))
        echo "MEM ${indx}: ${state_file_names[$idx]}"
    done
else
    echo "    $fnbase exists"
fi

#-----------------------------------------------------------------------
# Run the job itself
#-----------------------------------------------------------------------

RUNMPCMD -n NOPART EXEDIR/update_mpas_states

if [[ $? -eq 0 ]]; then
    touch done.update_states_${memstr}
else
    touch error.update_states_${memstr}
fi

rm -rf running.update_states_${memstr}

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
