#!/bin/bash

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

cd /scratch/ywang/MPAS/mpas_scripts/observations

for channel in 5 7; do
    python abiobs2dart_tb.py -i /work/rt_obs/Satellite/RADIANCE/2022     \
                -o /scratch/ywang/MPAS/mpas_scripts/run_dirs/OBS_SEQ/Radiance \
                -c $channel                                                   \
                -d ${1-20220527}
done

exit 0
