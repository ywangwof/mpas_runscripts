#!/bin/bash

#source /home/derek.stratman/miniconda3/etc/profile.d/conda.sh
#conda activate verif_py

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


umask 002
date

script_dir=$(pwd)

#
# Copy files to year directory
#
#cd /scratch/ywang/MPAS/intel/run_dirs/VERIF/FSS/cb-wofs || exit 0
#mkdir -p 2024
#cd 2024 || exit 0
#ln -sf ../20240*/*/wofs*5min*nc .
#
#cd /scratch/ywang/MPAS/intel/run_dirs/VERIF/FSS/mpas-wofs || exit 0
#mkdir -p 2024
#cd 2024 || exit 0
#ln -sf ../20240*/*/wofs*5min*nc .


cd ${script_dir}  || exit 0

python plot_efss_wofs_mpas.py -w /scratch/wofs_mpas/run_dirs/VERIF/FSS/cb-wofs/   \
                              -r /scratch/wofs_mpas/run_dirs/VERIF/FSS/mpas-wofs/ \
                              -o /scratch/wofs_mpas/run_dirs/VERIF/FSS/

exit 0
