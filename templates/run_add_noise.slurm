#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/fcst_all_add_noise_%j.log
ACCTSTR
EXCLSTR

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

machine=MACHINE source ROOTDIR/modules/env.python

# Retrieve command line parameters
ncseq_file="SEQFILE"
inv_file="INVFILE"
eventdatetime="EVENTDATETIME"

cd WRKDIR

touch running.add_noise
rm -rf error.add_noise queue.add_noise

# Run the python programs for noise mask

RUNCMD "python ROOTDIR/wofs_addnoise/grid_refl_obs.py ${ncseq_file} 35.0 10.0 ${inv_file} ${eventdatetime} mpas"
estatus="$?"
if [[ $estatus -ne 0 ]]; then
    touch error.add_noise
    rm -rf running.add_noise
    exit $estatus
fi

#------------------------------------------------------
# Run add_pert_where_high_refl.py for all members
#------------------------------------------------------

declare -A pids  # Associative array to store PID -> Member mapping
declare -a fail_jobs=()

#LAUNCH_CMD="srun --ntasks=1 --nodes=1 --exclusive --relative=0 bash -c"

for mem in $(seq 1 ENSSIZE); do
    memstr=$(printf "%02d" $mem)

    cd WRKDIR/fcst_${memstr} || exit $?

    #ln -sf ../refl_obs_${eventdatetime}.pkl ../wofs_mpas_grid_kdtree.pkl ../mpas_XYZ.pkl .

    # Run the python programs
    RUNCMD "python ROOTDIR/wofs_addnoise/add_pert_where_high_refl.py ${inv_file} INITFILE 9000.0 3000.0 0.50 0.50 0.0 0.50 0.50 0.0 ${eventdatetime} ${mem} mpas WRKDIR > log.add_noise_${memstr} 2>&1" &

    # Python program will touch done.add_noise_${memstr}

    pids[$!]=${mem}

    cd ..
done

overall_status=0
for pid in "${!pids[@]}"; do
    wait "$pid"
    status=$?
    member_idx=${pids[$pid]}

    if [[ $status -eq 0 ]]; then
        echo "Member ${member_idx} (PID $pid) finished successfully."
    else
        echo "Member ${member_idx} (PID $pid) FAILED with exit code $status."
        fail_jobs+=("${member_idx}")
        overall_status=1
    fi
done

if [[ $overall_status -eq 0 ]]; then
    touch done.add_noise
else
    echo "One or more members failed: ( ${fail_jobs[*]} )"
    touch error.add_noise
fi

rm -rf running.add_noise

time2=$(date '+%s')
diff=$((time2-time1))
printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" "${time2}" "$(date -d@$diff -u +%H:%M:%S)"
