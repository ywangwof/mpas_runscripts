#!/bin/bash

umask 002
date

script_dir=$(pwd)

# Host name
case $(hostname) in

wof-epyc* )
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

    cd "${script_dir}"  || exit 0

    python plot_efss_wofs_mpas.py -w /scratch/wofs_mpas/run_dirs/VERIF/FSS/cb-wofs/   \
                              -r /scratch/wofs_mpas/run_dirs/VERIF/FSS/mpas-wofs/ \
                              -o /scratch/wofs_mpas/run_dirs/VERIF/FSS/

    ;;
ufe* )
    rootdir="/scratch3/NAGAPE/wof/ywang/MPAS-WoFS/mpas_scripts.jedi"
    jobscript="/scratch3/NAGAPE/wof/ywang/MPAS-WoFS/run_dirs/VERIF/FSS/run_plot_fss.slurm"

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
    pythonopts=(-w /scratch3/NAGAPE/wof/ywang/MPAS-WoFS/run_dirs/VERIF/FSS/mpas-wofs/
                -r /scratch3/NAGAPE/wof/ywang/MPAS-WoFS/run_dirs/VERIF/FSS/Z_tempo/
                -o /scratch3/NAGAPE/wof/ywang/MPAS-WoFS/run_dirs/VERIF/FSS/ )

    # shellcheck disable=SC2034
    declare -A jobParms=(
        [PARTION]="u1-compute"
        [NOPART]="1"
        [JOBNAME]="plot_fss"
        [CPUSPEC]="--cpus-per-task=40"
        [MACHINE]="Ursa"
        [LOGDIR]="/scratch3/NAGAPE/wof/ywang/MPAS-WoFS/run_dirs/VERIF/FSS"
        [PYTHONSCRIPT]="plot_efss_wofs_mpas.py"
        [CONFIGFILE]="${pythonopts[*]}"
    )
    submit_a_job "$wrkdir" "plot_fss" "jobParms" "${rootdir}/templates/run_python.slurm" "$jobscript" ""
    ;;
* )
    echo "Unsupport machine."
    exit 1
    ;;
esac

exit 0
