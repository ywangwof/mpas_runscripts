#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=1 CPUSPEC
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/rotate_%j.log
ACCTSTR
EXCLSTR

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

#source $HOME/.python
if [[ "MACHINE" == "Jet" || "MACHINE" == "Hercules"  ]]; then
    module purge
    module use ROOTDIR/modules
    module load MODULE
else
    source ROOTDIR/modules/MODULE
fi

cd WRKDIR

rm -f queue.rotate error.rotate

touch running.rotate

RUNCMD -n 1 EXEDIR/grid_rotate input_filename.nc DOMNAME.grid.nc

if [[ $? -eq 0 ]]; then
    touch done.rotate
else
    touch error.rotate
fi

rm -f running.rotate

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "

exit

