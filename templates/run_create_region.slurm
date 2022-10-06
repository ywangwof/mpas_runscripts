#!/bin/sh -l
#SBATCH -A hpc-wof1
#SBATCH --partition=bigmem
#SBATCH -J create_region
#SBATCH --ntasks=1  --cpus-per-task=12
#SBATCH --exclusive
#SBATCH -t 02:30:00
#SBATCH -o /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/run_dirs/wofs_mpas/create_%j.out
#SBATCH -e /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/run_dirs/wofs_mpas/create_%j.err

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

source $HOME/.python

if [[ ! -d /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/run_dirs/wofs_mpas ]]; then
    mkdir -p /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/run_dirs/wofs_mpas
fi

RUNDIR='/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/MPAS-Limited-Area'

cd $RUNDIR

srun -n 1 create_region -v 2 /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/runscriptv2.0/templates/wofs_mpas.custom.pts /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/mesh_3km/x1.65536002.grid.nc

if [[ $? -eq 0 ]]; then
    mv wofs_mpas* /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/runscriptv2.0/templates/

    cd /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/runscriptv2.0/templates/
    /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/bin/gpmetis -minconn -contig -niter=200 wofs_mpas.graph.info 1200
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

exit

