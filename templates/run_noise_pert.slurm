#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/noise_pert_%a_%j.log
ACCTSTR
EXCLSTR

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

if [[ "MACHINE" == "Vecna" ]]; then
    # >>> conda initialize >>>
    # !! Contents within this block are managed by 'conda init' !!
    __conda_setup="$('/scratch/software/miniconda3/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
    if [ $? -eq 0 ]; then
        eval "$__conda_setup"
    else
        if [ -f "/scratch/software/miniconda3/etc/profile.d/conda.sh" ]; then
            . "/scratch/software/miniconda3/etc/profile.d/conda.sh"
        else
            export PATH="/scratch/software/miniconda3/bin:$PATH"
        fi
    fi
    unset __conda_setup
    # <<< conda initialize <<<

    conda activate wofs_post
else
    echo "Please set python environment for MACHINE"
    exit 1
fi

# Retrieve command line parameters
eventdays="EVENTDAYS"
eventsecs="EVENTSECS"
time_str="MPASTIME"

export PYTHONPATH="WAN_PATH"

mem=${SLURM_ARRAY_TASK_ID}
memstr=$(printf "%02d" $mem)

cd WRKDIR/fcst_${memstr}

touch add_noise.running_${memstr}
rm -rf error.add_noise_${memstr} queue.add_noise_${memstr}

# Run the python programs

bkg_file="wofs_mpas_${memstr}.restart.${time_str}.nc"
python WAN_PATH/add_pert_where_high_refl.py ${bkg_file} 9000.0 3000.0 0.50 0.50 0.0 0.50 0.50 0.0 ${eventsecs} ${eventdays} ${mem} mpas

if [[ $? -eq 0 ]]; then
    touch done.add_noise_${memstr}
else
    touch error.add_noise_${memstr}
fi

rm -rf add_noise.running_${memstr}

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
