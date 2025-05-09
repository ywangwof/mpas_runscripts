#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/filter_%j.log
ACCTSTR
EXCLSTR


#set -eux

time1=$(date '+%s')
printf "Job Started: %(%a %b %d %H:%M:%S %Z %Y)T. Job Id: %s\n\n" $time1 $SLURM_JOBID

if [[ "MACHINE" == "Jet" || "MACHINE" == "Hercules"  ]]; then
    source /etc/profile.d/modules.sh
    module purge
    module use ROOTDIR/modules
    module load MODULE
else
    source ROOTDIR/modules/MODULE
fi

ulimit -s unlimited

cd WRKDIR

touch running.filter
rm -rf error.filter queue.filter

RUNMPCMD -n NOPART EXEDIR/filter

if [[ $? -eq 0 ]]; then
    touch done.filter
else
    touch error.filter
fi

rm -rf running.filter

#------------------------------------------------------
# Run obs_seq_to_netcdf and/or obs_diag
#------------------------------------------------------
if [[ -e done.filter ]]; then
    iseconds=ISECONDS
    run_obs2nc=RUNOBS2NC
    run_obsdiag=RUNOBSDIAG
    run_addnoise=RUNADDNOISE

    timestr_cur=$(date -u -d @$iseconds    +%Y%m%d%H%M)

    if [[ ${run_obs2nc} == true || ${run_addnoise} == true ]]; then
        echo "    Run EXEDIR/obs_seq_to_netcdf at ${timestr_cur} > obs_seq_to_netcdf.log"
        RUNCMD -n 1 EXEDIR/obs_seq_to_netcdf >& obs_seq_to_netcdf.log
        mv obs_epoch_001.nc obs_seq.final.${timestr_cur}.nc
    fi

    if [[ ${run_obsdiag} == true ]]; then
        echo "    Run EXEDIR/obs_diag at ${timestr_cur} > obs_diag.log"
        RUNCMD -n 1 EXEDIR/obs_diag >& obs_diag.log
    fi
fi

time2=$(date '+%s')

diff=$((time2-time1))

printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" $time2 $(date -d@$diff -u +%H:%M:%S)
