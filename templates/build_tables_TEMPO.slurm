#!/bin/bash
#SBATCH --partition=u1-compute
#SBATCH -J build_tables
#SBATCH --ntasks=1 --cpus-per-task=96
#SBATCH -t 03:30:00
#SBATCH --output=build_tables_%j.log
#SBATCH -A wof
#SBATCH --exclusive

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

if [[ "Ursa" == "Jet" || "Ursa" == "Hercules" || "Ursa" == "Ursa" ]]; then
    source /etc/profile.d/modules.sh
    module purge
    module use /scratch3/NAGAPE/wof/ywang/GSL_JEDI/rrfs-workflow/modulefiles
    module load rrfs/ursa.intel
else
    source /scratch3/NAGAPE/wof/ywang/MPAS-WoFS/mpas_scripts.jedi/modules/rrfs/ursa.intel
fi

ulimit -s unlimited

wrkdir=$(pwd)

tempo_dir=/scratch3/NAGAPE/wof/ywang/MPAS-WoFS/frdd-MPAS-Model/src/core_atmosphere/physics/physics_noaa/TEMPO
cd "${tempo_dir}" || exit $?
make -f Makefile.intel build_tables

cd "${wrkdir}" || exit $?

rm -f *_data_tempo_v3
cp ${tempo_dir}/tables/ccn_activate.bin .

rm -f queue.build error.build

touch running.build

srun -n 1 ${tempo_dir}/run_build_tables

if [[ $? -eq 0 ]]; then
    touch done.build
else
    touch error.build
fi

rm -f running.build

time2=$(date '+%s')

diff=$((time2-time1))

printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" "${time2}" "$(date -d@$diff -u +%H:%M:%S)"
