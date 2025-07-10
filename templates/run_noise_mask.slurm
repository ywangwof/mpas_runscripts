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

if [[ "MACHINE" == "Jet" ]]; then
    python_root="/lfs5/NAGAPE/hpc-wof1/ywang/tools/micromamba"
    micenv="wofs_an"
elif [[ "MACHINE" == "Vecna" ]]; then
    python_root="/home/yunheng.wang/tools/micromamba"
    micenv="wofs_an"
elif [[ "MACHINE" == wof-epyc* ]]; then
    python_root="/home/yunheng.wang/y"
    micenv="/home/brian.matilla/micromamba/envs/wofs-func"
else
    echo "Please set python environment for MACHINE"
    exit 1
fi

# >>> mamba initialize >>>
# !! Contents within this block are managed by 'mamba init' !!
export MAMBA_EXE="${python_root}/bin/micromamba";
export MAMBA_ROOT_PREFIX="${python_root}";

__mamba_setup="$("$MAMBA_EXE" shell hook --shell zsh --root-prefix "$MAMBA_ROOT_PREFIX" 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__mamba_setup"
else
    alias micromamba="$MAMBA_EXE"  # Fallback on help from mamba activate
fi
unset __mamba_setup
# <<< mamba initialize <<<
micromamba activate "${micenv}"

# Retrieve command line parameters
ncseq_file="SEQFILE"
inv_file="INVFILE"
eventdays="EVENTDAYS"
eventsecs="EVENTSECS"

export PYTHONPATH="WAN_PATH"

cd WRKDIR

touch running.noise_mask
rm -rf error.noise_mask queue.noise_mask

# Run the python programs
RUNCMD python WAN_PATH/grid_refl_obs.py ${ncseq_file} 35.0 10.0 ${inv_file} ${eventsecs} ${eventdays} mpas

estatus="$?"
if [[ $estatus -eq 0 ]]; then
    touch done.noise_mask
elif [[ $estatus -eq 99 ]]; then
    touch missed.noise_mask
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
