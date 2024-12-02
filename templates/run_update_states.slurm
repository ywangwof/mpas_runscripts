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
# Do copy here instead of the driver script for parallelism
#-----------------------------------------------------------------------

((iensidx = mem-1))

state_infile_names=(STATEINFILESSTR)
state_outfile_names=(STATEOUTFILESSTR)

state_infile_name="${state_infile_names[$iensidx]}"
state_outfile_name="${state_outfile_names[$iensidx]}"

if [[ ! -e ${state_outfile_name} ]]; then
    echo "    CPCMD ${state_infile_name} ${state_outfile_name}"
    echo ""
    CPCMD "${state_infile_name}" "${state_outfile_name}"

    # for diagnostics and add some delays
    for idx in "${!state_infile_names[@]}"; do
        (( indx = idx+1 ))
        echo "MEM ${indx}: ${state_infile_names[$idx]} -> ${state_outfile_names[$idx]}"
    done
else
    echo "    ${state_outfile_name} exists"
fi

#-----------------------------------------------------------------------
# Run the job itself
#-----------------------------------------------------------------------

RUNCMD -n NOPART EXEDIR/update_mpas_states

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
