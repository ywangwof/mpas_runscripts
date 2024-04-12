#!/bin/bash

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


cd /scratch/ywang/MPAS/gnu/mpas_scripts/observations || exit 0
#python cwpobs2dart.py -i /work/rt_obs/Satellite/CWP/2023/CONUS     \
#                -o /scratch/ywang/MPAS/mpas_scripts/run_dirs/OBS_SEQ/CWP \
#                -d ${1-20230401}

python cwpobs2dart.py -i /work2/wof/realtime/OBSGEN/CLOUD_OBS/${1-20240410} \
                -o /scratch/ywang/MPAS/gnu/mpas_scripts/run_dirs/OBS_SEQ/CWP \
                -d ${1-20240410}

exit 0
