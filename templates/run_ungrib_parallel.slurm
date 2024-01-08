#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=1 --cpus-per-task=12
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/ungrib_%j_%a.log
ACCTSTR
EXCLSTR

#set -eux

time1=$(date '+%s')
echo "Job Started: $(date). Job Id:  $SLURM_JOBID"
echo " "

fhr=${SLURM_ARRAY_TASK_ID}
hstr=$(printf "%02d" $fhr)
time_str=$(date -u -d "EVENTDATE EVENTTIME:00 $fhr hours" +%Y-%m-%d_%H)
fulltime_str=$(date -u -d "EVENTDATE EVENTTIME:00 $fhr hours" +%Y-%m-%d_%H:%M:%S)

cd WRKDIR/ungrib_$hstr

touch running.ungrib_$hstr
rm -rf error.ungrib_$hstr

cat << EOF > namelist.wps
&share
 wrf_core = 'ARW',
 max_dom = 1,
 start_date = '${fulltime_str}',
 end_date = '${fulltime_str}',
 interval_seconds = $((EXTINVL*3600))
 io_form_geogrid = 2,
/
&geogrid
/
&ungrib
 out_format = 'WPS',
 prefix = 'PREFIX',
/
&metgrid
/
EOF

RUNCMD -n 1 EXEDIR/ungrib.exe

if [[ $? -eq 0 ]]; then
    mv PREFIX:${time_str} ../
    touch ../done.ungrib_$hstr
else
    touch error.ungrib_$hstr
fi

#rm -rf running.ungrib_$hstr

time2=$(date '+%s')

let diff=time2-time1
let hour=diff/3600
let diff=diff%3600
let min=diff/60
let sec=diff%60

echo -n "Job   Ended: $(date). "
printf 'Job run time:  %02d:%02d:%02d' $hour $min $sec
echo " "
