#!/bin/sh -l
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/obs_final2nc_%j.log
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

touch obs_final2nc.running
rm -rf error.obs_final2nc queue.obs_final2nc

for((i=START_S;i<=END_S;i+=INTVL_S)); do
    timestr_cur=$(date -d @$i +%Y%m%d%H%M)

    seqdir=$(date -d @$i +%H%M)
    seqfile=DACYCLEDIR/${seqdir}/obs_seq.final

    if [[ ! -e $seqfile ]]; then
        echo "ERROR: not found $seqfile"
        break
    fi

    sedfile=$(mktemp -t obsfinal2nc_nml.sed_XXXX)
    cat <<EOF > $sedfile
/obs_sequence_list/c   obs_sequence_list  = ''
/obs_sequence_name/c   obs_sequence_name  = '${seqfile}'
EOF
    sed -f $sedfile -i input.nml
    rm -f $sedfile

    RUNMPCMD -n NOPART EXEDIR/obs_seq_to_netcdf

    mv obs_epoch_001.nc obs_seq.final.${timestr_cur}.nc
done

if [[ $? -eq 0 ]]; then
    touch done.obs_final2nc
else
    touch error.obs_final2nc
fi

rm -rf obs_final2nc.running

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
