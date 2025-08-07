#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=1 CPUSPEC
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/projectHexes_%j.log
ACCTSTR
EXCLSTR

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

if [[ "MACHINE" == "Jet" || "MACHINE" == "Hercules"  ]]; then
    module purge
    module use ROOTDIR/modules
    module load MODULE
else
    source ROOTDIR/modules/MODULE
fi

ulimit -s unlimited

cd WRKDIR

rm -f queue.projectHexes error.projectHexes

touch running.project

RUNMPCMD -n 1 EXEDIR/project_hexes

if [[ $? -eq 0 ]]; then
    mv mpas_hex_mesh.nc DOMNAME.grid.nc
    mv graph.info DOMNAME.graph.info
    touch done.project
else
    touch error.project
fi

rm -f running.project

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

