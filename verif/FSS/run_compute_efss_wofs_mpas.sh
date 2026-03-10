#!/bin/bash
# shellcheck disable=SC1091,SC2034

# Job to be run
case $1 in
mpas )
    python_script="wrapper_compute_efss_wofs_mpas_2024.py"
    ;;
wof )
    python_script="wrapper_compute_efss_wofs_2024.py"
    ;;
* )
    echo "Not sure which model to run: $1"
    exit 1
    ;;
esac

umask 002
date

# Host name
case $(hostname) in

wof-epyc* )
    source /home/brian.matilla/miniconda3/etc/profile.d/conda.sh
    conda activate /home/brian.matilla/miniconda3/envs/wofs-post-2023

    python "${python_script}"  -m /work/rt_obs/MRMS//RAD_AZS_MSH/2024   \
                               -w /scratch/wofs_mpas/run_dirs/VERIF/FSS/mpas-wofs/ \
                               -o /scratch/wofs_mpas/run_dirs/VERIF/FSS/
    ;;
ufe* )
    rootdir="/scratch3/NAGAPE/wof/ywang/MPAS-WoFS/mpas_scripts.jedi"
    jobscript="/scratch3/NAGAPE/wof/ywang/MPAS-WoFS/run_dirs/VERIF/FSS/run_compute_fss.slurm"

    wrkdir="${rootdir}/verif/FSS"

    #-------------------------------------------------------------------


    source "${rootdir}/scripts/Common_Colors.sh"    || exit $?
    source "${rootdir}/scripts/Site_Runtime.sh"     || exit $?
    source "${rootdir}/scripts/Common_Utilfuncs.sh" || exit $?

    config_file="/scratch3/NAGAPE/wof/ywang/MPAS-WoFS/run_dirs/config.20240508"

    readconf "${config_file}" COMMON || exit $?
    runcmd="sbatch"

    ####################################################################
    declare -a pythonopts
    pythonopts=(-w /scratch3/NAGAPE/wof/ywang/MPAS-WoFS/run_dirs/summary_files/
                -m /scratch3/NAGAPE/wof/ywang/rt_obs/MRMS/RAD_AZS_MSH/2024
                -o /scratch3/NAGAPE/wof/ywang/MPAS-WoFS/run_dirs/VERIF/FSS/Z_tempo
                -x "_Z_tempo" )

    declare -A jobParms=(
        [PARTION]="u1-compute"
        [NOPART]="1"
        [JOBNAME]="compute_fss"
        [CPUSPEC]="--cpus-per-task=40"
        [MACHINE]="Ursa"
        [LOGDIR]="/scratch3/NAGAPE/wof/ywang/MPAS-WoFS/run_dirs/VERIF/FSS"
        [PYTHONSCRIPT]="${python_script}"
        [CONFIGFILE]="${pythonopts[*]}"
    )
    submit_a_job "$wrkdir" "computer_fss" "jobParms" "${rootdir}/templates/run_python.slurm" "$jobscript" ""
    ;;
* )
    echo "Unsupport machine."
    exit 1
    ;;
esac

date

echo "Compute eFSS is complete."

exit 0
