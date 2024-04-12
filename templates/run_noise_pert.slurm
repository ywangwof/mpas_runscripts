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
    # >>> mamba initialize >>>
    # !! Contents within this block are managed by 'mamba init' !!
    export MAMBA_EXE='/home/yunheng.wang/tools/micromamba/bin/micromamba';
    export MAMBA_ROOT_PREFIX='/home/yunheng.wang/tools/micromamba';
    __mamba_setup="$("$MAMBA_EXE" shell hook --shell zsh --root-prefix "$MAMBA_ROOT_PREFIX" 2> /dev/null)"
    if [ $? -eq 0 ]; then
        eval "$__mamba_setup"
    else
        alias micromamba="$MAMBA_EXE"  # Fallback on help from mamba activate
    fi
    unset __mamba_setup
    # <<< mamba initialize <<<
    micromamba activate wofs_an

    mem_arr=("${SLURM_ARRAY_TASK_ID}")
elif [[ "MACHINE" == wof-epyc* ]]; then
    # >>> mamba initialize >>>
    # !! Contents within this block are managed by 'mamba init' !!
    export MAMBA_EXE='/home/yunheng.wang/y/micromamba';
    export MAMBA_ROOT_PREFIX='/home/yunheng.wang/y';
    __mamba_setup="$("$MAMBA_EXE" shell hook --shell zsh --root-prefix "$MAMBA_ROOT_PREFIX" 2> /dev/null)"
    if [ $? -eq 0 ]; then
        eval "$__mamba_setup"
    else
        alias micromamba="$MAMBA_EXE"  # Fallback on help from mamba activate
    fi
    unset __mamba_setup
    # <<< mamba initialize <<<
    micromamba activate /home/brian.matilla/micromamba/envs/wofs-func

    mem_arr=( MEMARRAY )
else
    echo "Please set python environment for MACHINE"
    exit 1
fi

# Retrieve command line parameters
inv_file="INVFILE"
eventdays="EVENTDAYS"
eventsecs="EVENTSECS"
time_str="MPASTIME"

export PYTHONPATH="WAN_PATH"

for mem in "${mem_arr[@]}"; do
    memstr=$(printf "%02d" $mem)

    cd WRKDIR/fcst_${memstr}

    #touch running.add_noise_${memstr}
    #rm -rf error.add_noise_${memstr} queue.add_noise_${memstr}

    # Run the python programs

    bkg_file="wofs_mpas_${memstr}.restart.${time_str}.nc"
    RUNCMD python WAN_PATH/add_pert_where_high_refl.py ${inv_file} ${bkg_file} 9000.0 3000.0 0.50 0.50 0.0 0.50 0.50 0.0 ${eventsecs} ${eventdays} ${mem} mpas &

    #if [[ $? -eq 0 ]]; then
    #    touch done.add_noise_${memstr}
    #else
    #    touch error.add_noise_${memstr}
    #fi
    #
    #rm -rf running.add_noise_${memstr}
done

wait

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
