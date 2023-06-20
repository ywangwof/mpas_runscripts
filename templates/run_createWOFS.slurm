#!/bin/sh -l
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=1 CPUSPEC
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/create_%j.log
ACCTSTR
EXCLSTR

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

source $HOME/.python

cd WRKDIR

rm -f queue.create error.create

touch running.create

RUNMPCMD -n 1 create_region -v 2 wofs_mpas.custom.pts x1.65536002.grid.nc

if [[ $? -eq 0 ]]; then
    #EXEDIR/gpmetis -minconn -contig -niter=200 wofs_mpas.graph.info NPEICS
    #if [[ NPEICS -ne NPEFCST ]]; then
    #    EXEDIR/gpmetis -minconn -contig -niter=200 wofs_mpas.graph.info NPEFCST
    #fi
    touch done.create
else
    touch error.create
fi

rm -f running.create

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

