#!/bin/bash
# shellcheck disable=SC2059

script_dir="$( cd "$( dirname "$0" )" && pwd )"
root_dir=$(dirname ${script_dir})

# shellcheck disable=SC1091
source "${root_dir}/scripts/Common_Colors.sh"

seq_tool="${root_dir}/scripts/seq_filter.py"

eventdate="${1-20240507}"
nextdate=$(date -d "${eventdate} 1 day" +%Y%m%d)

src_dir="/scratch/wofs_mpas/OBS_SEQ"
des_dir="/scratch/wofs_mpas/OBS_SEQ.reduced"

dir1s=(Bufr  Mesonet )
dir2s=(REF  VEL)

declare -A var_str
#METAR Ps (2.0 -> 1.2), T2 (2.0 -> 1.2), DPT (reduced to 60% level), UV10 (2.0 -> 1.5)
#ACARS/AIRCFT T (2.0 -> 1.0; superobbed as well)

#          12 AIRCRAFT_U_WIND_COMPONENT
#          13 AIRCRAFT_V_WIND_COMPONENT
#          14 AIRCRAFT_TEMPERATURE
#          16 ACARS_U_WIND_COMPONENT
#          17 ACARS_V_WIND_COMPONENT
#          18 ACARS_TEMPERATURE
#          20 MARINE_SFC_U_WIND_COMPONENT
#          21 MARINE_SFC_V_WIND_COMPONENT
#          22 MARINE_SFC_TEMPERATURE
#          42 MARINE_SFC_ALTIMETER
#          44 METAR_ALTIMETER
#          50 METAR_U_10_METER_WIND
#          51 METAR_V_10_METER_WIND
#          52 METAR_TEMPERATURE_2_METER
#          66 METAR_DEWPOINT_2_METER
#          71 MARINE_SFC_DEWPOINT

declare -A variances1
variances1=([14]=1.0 [18]=1.0 [42]=1.44 [52]=1.44 [66]=60% [50]=2.25 [51]=2.25)
var_str["Bufr"]=""
for t in "${!variances1[@]}"; do
    var_str["Bufr"]+="$t,variance,${variances1[$t]};"
done

#Mesonet Ps (1.0), T2 (2.5), Q2 (1.7-2.1), UV10 (3.5) -> not adjusted

#          25 LAND_SFC_U_WIND_COMPONENT
#          26 LAND_SFC_V_WIND_COMPONENT
#          27 LAND_SFC_TEMPERATURE
#          28 LAND_SFC_SPECIFIC_HUMIDITY
#          43 LAND_SFC_ALTIMETER
#          98 LAND_SFC_RELATIVE_HUMIDITY
#         118 LAND_SFC_DEWPOINT

declare -A variances2
variances2=([43]=1.0 [27]=6.25 [28]=60% [118]=60%)
var_str["Mesonet"]=""
for t in "${!variances2[@]}"; do
    var_str["Mesonet"]+="$t,variance,${variances2[$t]};"
done

#Radar reflectivity (7), clear-air reflectivity (5 -> 1)
#       12          RADAR_REFLECTIVITY
#       13          RADAR_CLEARAIR_REFLECTIVITY
declare -A variances3
variances3=([13]=4.0 [12]=25.0)
for t in "${!variances3[@]}"; do
    var_str["REF"]+="$t,variance,${variances3[$t]};"
done

#radial velocity (3 -> 2.5)
#       11          DOPPLER_RADIAL_VELOCITY
declare -A variances4
variances4=([11]=6.25)
for t in "${!variances4[@]}"; do
    var_str["VEL"]+="$t,variance,${variances4[$t]};"
done

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#% MAIN
source ~/.pythonrc

log_file="${des_dir}/reduce.log"
exec > >(tee -ia ${log_file}) 2>&1

echo -e "src_dir=${CYAN}${src_dir}${NC}"
echo -e "des_dir=${CYAN}${des_dir}${NC}"
echo ""

echo -e "dir1s=[${WHITE}${dir1s[*]}${NC}]"
echo -e "dir2s=[${WHITE}${dir2s[*]}${NC}]"
echo ""
printf -v fmtStr "[${PURPLE}%s${NC}]=${YELLOW}%%q${NC} " "${!variances1[@]}"; printf "variances1=(${fmtStr})\n" "${variances1[@]}"
printf -v fmtStr "[${PURPLE}%s${NC}]=${YELLOW}%%q${NC} " "${!variances2[@]}"; printf "variances2=(${fmtStr})\n" "${variances2[@]}"
echo ""

# Group 1 observations
for dir in "${dir1s[@]}"; do
    [[ ! -d $des_dir/$dir ]] && mkdir -p $des_dir/$dir
    #cd $des_dir/$dir || exit $?
    if compgen -G "${src_dir}/$dir"/*.{"${eventdate}","${nextdate}"}* > /dev/null; then
        for fn in "${src_dir}/$dir"/*.{"${eventdate}","${nextdate}"}*; do
            filename=$(basename $fn)
            ${seq_tool} -k -N -s "${var_str[$dir]}" $fn -o $des_dir/$dir/$filename
        done
    fi
done

echo ""
#echo -e "var_str=(REF=${YELLOW}${var_str[REF]}${NC} VEL=${YELLOW}${var_str[VEL]}${NC})"
printf -v fmtStr "[${PURPLE}%s${NC}]=${YELLOW}%%q${NC} " "${!variances3[@]}"; printf "variances3=(${fmtStr})\n" "${variances3[@]}"
printf -v fmtStr "[${PURPLE}%s${NC}]=${YELLOW}%%q${NC} " "${!variances4[@]}"; printf "variances4=(${fmtStr})\n" "${variances4[@]}"
echo ""

# Group 2 observations
for dir in "${dir2s[@]}"; do
    [[ ! -d $des_dir/$dir/${eventdate} ]] && mkdir -p $des_dir/$dir/${eventdate}
    #cd $des_dir/$dir || exit $?
    for fn in "${src_dir}/$dir/${eventdate}"/*; do
        filename=$(basename $fn)
        ${seq_tool} -k -N -s "${var_str[$dir]}" $fn -o $des_dir/$dir/${eventdate}/$filename
    done
done

#
# Link not changed files
#
dirs=("${dir1s[@]}" "${dir2s[@]}")
for fdir in "${src_dir}"/*; do
    dir=$(basename $fdir)
    if [[ " ${dirs[*]} " ==  *" $dir "* ]]; then
        :
    else
        echo "Creating $des_dir/$dir "
        [[ ! -d $des_dir/$dir ]] && mkdir -p $des_dir/$dir
        cd $des_dir/$dir || exit $?
        ln -sf ${src_dir}/$dir/*.{"${eventdate}","${nextdate}"}* .
    fi
done

exit 0