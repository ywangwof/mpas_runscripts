#!/bin/csh

#set rad_name = ( KDDC KFSD KVNX KICT KINX KTWX KGLD KOAX KARX KDVN KSGF KDMX KLNX KUEX KEAX )

set start = "2023,5,12,14"
set stop  = "2023,5,13,03"
set newse_radar_file = "radars.20230512.csh"
set outdir  =  "/scratch/ywang/MPAS/mpas_scripts/run_dirs/OBS_SEQ/VEL/radar2"

get_nexrad.py --start $start --end $stop --newse $newse_radar_file -d $outdir
