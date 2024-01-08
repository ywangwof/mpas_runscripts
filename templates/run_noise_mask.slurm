#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 00:20:00
#SBATCH --output=WRKDIR/noise_mask_%j.log
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
else
    echo "Please set python environment for MACHINE"
    exit 1
fi

# Retrieve command line parameters
ncseq_file="SEQFILE"
bkg_file="BKGFILE"
eventdays="EVENTDAYS"
eventsecs="EVENTSECS"

export PYTHONPATH="WAN_PATH"

cd WRKDIR

touch running.noise_mask
rm -rf error.noise_mask queue.noise_mask

# Run the python programs
RUNMPCMD python WAN_PATH/grid_refl_obs.py ${ncseq_file} 35.0 10.0 ${bkg_file} ${eventsecs} ${eventdays} mpas

if [[ $? -eq 0 ]]; then
    touch done.noise_mask
else
    touch error.noise_mask
fi

rm -rf running.noise_mask

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
