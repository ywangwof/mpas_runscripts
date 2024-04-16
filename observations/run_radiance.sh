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

cd /scratch/ywang/MPAS/gnu/mpas_scripts/observations

for channel in 5 7; do
    #python abiobs2dart_tb.py -i /work/rt_obs/Satellite/RADIANCE/2022     \
    #            -o /scratch/ywang/MPAS/mpas_scripts/run_dirs/OBS_SEQ/Radiance \
    #            -c $channel                                                   \
    #            -d ${1-20220527}
    python abiobs2dart_tb.py -i /work2/wof/realtime/OBSGEN/CLOUD_OBS/${1-20240410}/d1 \
                -o /scratch/ywang/MPAS/gnu/mpas_scripts/run_dirs/OBS_SEQ/Radiance \
                -c $channel                                                   \
                -d ${1-20230512}
done

exit 0
