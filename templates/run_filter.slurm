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
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

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

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
