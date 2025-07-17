#!/bin/bash
#SBATCH -A hpc-wof1
#SBATCH --partition=bigmem
#SBATCH -J create_region
#SBATCH --ntasks=1  --cpus-per-task=12
#SBATCH --exclusive
#SBATCH -t 02:30:00
#SBATCH -o /lfs5/NAGAPE/hpc-wof1/ywang/MPAS/run_dirs/wofs_mpas/create_%j.out
#SBATCH -e /lfs5/NAGAPE/hpc-wof1/ywang/MPAS/run_dirs/wofs_mpas/create_%j.err

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

source $HOME/.pythonrc

if [[ ! -d /lfs5/NAGAPE/hpc-wof1/ywang/MPAS/run_dirs/wofs_mpas ]]; then
    mkdir -p /lfs5/NAGAPE/hpc-wof1/ywang/MPAS/run_dirs/wofs_mpas
fi

RUNDIR='/lfs5/NAGAPE/hpc-wof1/ywang/MPAS/MPAS-Limited-Area'

cd $RUNDIR

srun -n 1 create_region -v 2 /lfs5/NAGAPE/hpc-wof1/ywang/MPAS/mpas_scripts/templates/wofs_mpas.custom.pts /lfs5/NAGAPE/hpc-wof1/ywang/MPAS/mesh_3km/x1.65536002.grid.nc

if [[ $? -eq 0 ]]; then
    mv wofs_mpas* /lfs5/NAGAPE/hpc-wof1/ywang/MPAS/mpas_scripts/fix_files

    cd /lfs5/NAGAPE/hpc-wof1/ywang/MPAS/mpas_scripts/fix_files
    /lfs5/NAGAPE/hpc-wof1/ywang/bin/gpmetis -minconn -contig -niter=200 wofs_mpas.graph.info 1200
fi

time2=$(date '+%s')

diff=$((time2-time1))
printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" $time2 $(date -d@$diff -u +%H:%M:%S)

exit
