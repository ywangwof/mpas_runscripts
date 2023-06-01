#!/bin/sh -l
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 06:30:00
#SBATCH --output=WRKDIR/mpas_%a_%j.log
ACCTSTR
EXCLSTR

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

if [[ "MACHINE" == "Jet" ]]; then
    module purge
    module use ROOTDIR/modules
    module load MODULE

    #ncores=NCORES

    #nnode=$(( NOPART/$SLURM_CPUS_ON_NODE ))
    #nnode=$SLURM_JOB_NUM_NODES
else
    source ROOTDIR/modules/MODULE
    #ncores=NCORES
fi
#nnode=$(( NOPART/ncores ))

nnode=$SLURM_JOB_NUM_NODES
if (( NOPART % nnode == 0 )); then
    ncores=$(( NOPART/nnode ))
#else
#    echo "Number of tasks (NOPART) is not divisible by number of nodes ($nnode) allocated."
#    echo "Job cannot be run becasue the setting for \"pio_num_iotasks\""
#    exit 0
fi

ulimit -s unlimited

mem=${SLURM_ARRAY_TASK_ID}
memstr=$(printf "%02d" $mem)

cd WRKDIR/mem${memstr}

touch fcst.running_$memstr
rm -rf error.fcst_$memstr queue.fcst_$memstr

# first recover namelist parameters for possibly an old run.
sed -i -e "/config_pio_num_iotasks/s/[0-9]\+/NNNODE/;/config_pio_stride/s/[0-9]\+/NNCORE/" namelist.atmosphere

sed -i "s/NNNODE/$nnode/;s/NNCORE/$ncores/;" namelist.atmosphere

RUNMPCMD -n NOPART EXEDIR/atmosphere_model.single

if [[ $? -eq 0 ]]; then
    touch done.fcst_$memstr
    mv *.restart.*.nc ..
    mv *.history.*.nc ..
    mv *.diag.*.nc ..
else
    touch error.fcst_$memstr
fi

rm -rf fcst.running_$memstr

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
