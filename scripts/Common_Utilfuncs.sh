#!/bin/bash
# shellcheck disable=SC2317,SC1090,SC1091,SC2086

# Export Functions:
#
# o mkwrkdir
# o submit_a_jobscript
# o check_job_status
# o get_jobarray_str         # Retrieve job array option string based on job scheduler
# o group_numbers_by_steps   # Group job numbers for PBS job array option "-J X-Y[:Z]%num"
# o join_by                  # Join array into a string by a separator
# o readconf                 # Read config file, written from "setup_mpas-wofs_grid.sh"
# o convert2days             # Convert date/time strings to days/seconds since 1601-01-01
# o convertS2days            # Convert epoch seconds to days/seconds since 1601-01-01
# o convert2date             # Convert days/seconds since 1601-01-01 to date/time strings
# o upnlevels                # get n level parent directory path
# o link_grib                # Link grib files for ungrib.exe
# o clean_mem_runfiles       # Clean the runtime files of an ensemble task
# o wait_for_file_size       # Hold the task until the file size exceeds the give number of bytes
# o wait_for_file_age        # Hold the task until the file age is older than the give number of seconds
#

########################################################################

function mkwrkdir {
    # make a directory
    # the second argument is the creating mode
    # 0: Keep existing directory as is
    # 1: Remove existing directory
    # 2: Back up existing same name directory with appendix ".bakX"
    #    X starts from 0, the less the number, the backup directory is newer.
    #
    if [[ $# -ne 2 ]]; then
        echo -e "${RED}ERROR${NC}: argument in mkwrkdir, get \"$*\"."
        exit 0
    fi

    mydir=$1
    backup=$2

    if [[ -d $mydir ]]; then
        if [[ $backup -eq 1 ]]; then
            rm -rf $mydir
        elif [[ $backup -eq 2 ]]; then
            basedir=$(dirname $mydir)
            namedir=$(basename $mydir)
            bakno=0
            bakdir="$basedir/${namedir}.bak$bakno"
            while [[ -d $bakdir ]]; do
                (( bakno++ ))
                bakdir="$basedir/${namedir}.bak$bakno"
            done

            for ((i=bakno;i>0;i--)); do
                j=$((i-1))
                olddir="$basedir/${namedir}.bak$j"
                bakdir="$basedir/${namedir}.bak$i"
                echo "Moving $olddir --> $bakdir ..."
                mv $olddir $bakdir
            done
            bakdir="$basedir/${namedir}.bak0"
            echo "Backing $mydir --> $bakdir ..."
            mv $mydir $bakdir
        fi
    fi
    mkdir -p $mydir
}

########################################################################

function submit_a_jobscript {
    # Arguments
    #   1      2       3       4       5        6
    # wrkdir jobname sedfile jobtemp jobscript joboption
    #
    # Use global variables: $verb, $dorun, $runcmd
    #
    # Purpose:
    #
    # 1. Create $myjobscript from $myjobtemp using SED based on scripts in $sedfile
    # 2. Submit $myjobscript using global command $runcmd
    # 3. Generate a queue file based on $myjobname in current working directory $mywrkdir
    #    if the job script is submitted correctly
    #
    if [[ $# -ne 6 ]]; then
        echo "No enough argument in \"submit_a_jobscript\", get: $*"
        exit 0
    fi

    local mywrkdir=$1
    local myjobname=$2
    local sedscript=$3
    local myjobtemp=$4
    local myjobscript=$5
    local myjoboption=$6

    cd $mywrkdir  || return

    sed -f $sedscript $myjobtemp > $myjobscript
    # shellcheck disable=SC2154
    if [[ ${verb} -eq 1 ]]; then
        echo -e "${DARK}${FUNCNAME[1]}:${NC} Generated job script: \"$myjobscript\" "
        echo "                   from template: \"$myjobtemp\" "
        echo "                   with sed file: \"$sedscript\"  "
    else
        rm -f $sedscript
    fi

    # shellcheck disable=SC2154
    if [[ $dorun == true ]]; then echo -en "${DARK}${FUNCNAME[1]}:${NC} Submitting $myjobscript .... "; fi
    # shellcheck disable=SC2154
    $runcmd ${myjoboption} "$myjobscript"
    if [[ $dorun == true && $? -eq 0 ]]; then touch $mywrkdir/queue.$myjobname; fi
    echo " "
}

########################################################################

function check_job_status {
    #local jobnames=$1                  # Comment out, read $1 as an array below
    local mywrkdir=$2
    local donenum=$3                    # total number of jobs
    local myjobscript=${4-}             # empty no resubmissions
    local numtries=${5-0}               # number of resubmissions
                                        # >= 0 Wait for job done or resubmit failed jobs before exiting
                                        # < 0 check number of done jobs only

    read -r -a jobnames <<< "$1"
    local jobname=${jobnames[0]}
    if [[ ${#jobnames[@]} -eq 2 ]]; then     # if it is an array, the 2nd element denotes the member dirname
        local memname=${jobnames[1]}
    else
        local memname="${jobname}_"
    fi

    # global variables:
    # $runcmd, $verb

    local numtry "done" memdir runjobs jobarrays mem memstr
    local donefile errorfile

    cd $mywrkdir  || return

    if [[ -e $mywrkdir/done.${jobname} ]]; then    # do nothing
        done=$donenum
        return
    fi

    checkonly=false
    if [[ $numtries -lt 0 ]]; then
        numtries=1
        checkonly=true
    fi
    # check each member's status
    while IFS='' read -r line; do
        runjobs+=("$line");
    done < <(seq 1 $donenum)

    echo -e "${DARK}${FUNCNAME[1]}:${NC} Waiting for ensemble jobs of ${WHITE}${jobname}${NC} in ${mywrkdir}"
    numtry=0
    done=0; error=0; running=0
    while [[ $numtry -le $numtries ]]; do
        jobarrays=()
        for mem in "${runjobs[@]}"; do
            memstr=$(printf "%02d" $mem)
            memdir="$mywrkdir/${memname}$memstr"
            donefile="$memdir/done.${jobname}_$memstr"
            errorfile="$memdir/error.${jobname}_$memstr"

            if [[ $verb -eq 1 ]]; then echo -e "${DARK}${FUNCNAME[0]}:${NC} Checking $donefile"; fi
            while [[ ! -e $donefile ]]; do
                if [[ -e $errorfile ]]; then
                    jobarrays+=("$mem")
                    (( error+=1 ))
                    break
                elif $checkonly; then
                    (( running+=1 ))
                    break
                fi

                #if [[ $verb -eq 1 ]]; then echo "Waiting for $donefile"; fi
                sleep 10
            done
            if [[ -e $donefile ]]; then (( done+=1 )); fi
        done

        (( numtry+=1 ))

        if [[ $done -eq $donenum ]]; then
            touch $mywrkdir/done.${jobname}
            rm -f $mywrkdir/queue.${jobname}
            break                                  # No further check needed
        elif $checkonly; then
            break                                  # Stop further try
        elif [[ ${#jobarrays[@]} -gt 0 && $numtry -lt $numtries ]]; then    # failed jobs found
            if [[ $myjobscript == *.slurm ]]; then
                runjobs=( "${jobarrays[@]}" )
                echo -e "${DARK}${FUNCNAME[1]}:${NC} ${numtry}/${numtries} - Try these failed jobs again: ${runjobs[*]}"
                jobs_str=$(get_jobarray_str 'slurm' "${runjobs[@]}")
                $runcmd ${jobs_str} $myjobscript
                error=0                            # Perform another try
            else
                jobgroupstr=$(group_numbers_by_steps "${runjobs[@]}")
                IFS=";" read -r -a jobgroups <<< "${jobgroupstr}"; unset IFS  # convert string to array
                #while IFS=';' read -r line; do jobgroups+=("$line"); done < <(group_numbers_by_steps "${runjobs[*]}")
                for jobg in "${jobgroups[@]}"; do
                    IFS=" " read -r -a jobgar <<< "${jobg}"; unset IFS        # convert string to array
                    jobgstr=$(get_jobarray_str 'pbs' "${jobgar[@]}")
                    $runcmd ${jobgstr} $myjobscript
                done
                error=0                             # Perform another try
                #break                              # Stop further try for PBS jobs scheduler
            fi

            for mem in "${runjobs[@]}"; do
                memstr=$(printf "%02d" $mem)
                memdir="$mywrkdir/${memname}$memstr"
                rm -rf "$memdir/error.${jobname}_$memstr"
            done
        fi

    done

    #
    # Output a message and then return or exit
    #
    outmessage="Status of $jobname: done: ${GREEN}$done${NC}"
    if [[ $running -gt 0 ]]; then
        outmessage="$outmessage; queued/running: ${BROWN}$running${NC}"
    fi

    if [[ ${#jobarrays[@]} -gt 0 ]]; then
        outmessage="$outmessage; failed: ${#jobarrays[@]} - [${LIGHT_RED}${jobarrays[*]}${NC}]"
    fi

    echo -e "${DARK}${FUNCNAME[1]}:${NC} $outmessage"
    if [[ $done -lt $donenum ]]; then
        if $checkonly; then
            return
        else
            exit 9
        fi
    fi
}

########################################################################

function group_numbers_by_steps {
    local orgnumbers=("${@}")

    # Sort the original number array
    IFS=$'\n' orgnumberstr="${orgnumbers[*]}"; unset IFS
    #mapfile -t sortednumbers < <(sort -g <<<"${orgnumberstr}")
    local sortednumbers=()
    while IFS='' read -r line; do
        sortednumbers+=("$line")
    done < <(sort -g <<<"${orgnumberstr}")

    # Find continous job nos
    local retarray=()
    local workarray=("${sortednumbers[@]}")

    local ar2=("${workarray[@]}")
    for step in $(seq 1 10); do

        if [[ ${#workarray[@]} -lt 3 ]]; then break; fi

        #echo "step=${step}: ${workarray[*]}"
        for idx in "${!workarray[@]}"; do

            local prev=${workarray[$idx]}

            #echo "    prev=$prev: ${ar2[*]}"

            if [[ " ${ar2[*]} " =~ \ ${prev}\  ]]; then   # the number is still in the remain set

                local ar1=("$prev")
                local dropset=()

                for nidx in "${!ar2[@]}"; do
                    local next=${ar2[$nidx]}
                    #echo "        next=${next}, ar1=${ar1[*]}"
                    if (( 10#$next == (10#$prev+step) )); then
                        ar1+=("$next")
                        dropset+=("$nidx")
                        prev=${next}
                    elif [[ $next -eq $prev ]]; then
                        dropset+=("$nidx")
                    fi
                done

                if [[ ${#ar1[@]} -ge 3 ]]; then
                    retarray+=("${ar1[*]}")
                    for didx in "${dropset[@]}"; do
                        unset -v "ar2[$didx]"
                    done
                    ar2=("${ar2[@]}")
                    #echo "        new ar2=${ar2[*]}"
                fi
            fi
        done
        workarray=("${ar2[@]}")
    done

    # every element contains at least two jobs numbers even they are not continous
    for ((i=0;i<${#workarray[@]};i+=2)); do
        (( j=i+1 ))
        retarray+=("${workarray[$i]} ${workarray[$j]}")
    done

    IFS=$';' retnumberstr="${retarray[*]}"; unset IFS
    echo "${retnumberstr}"
}

########################################################################

function get_jobarray_str {
    local jobschdler=$1
    local subjobs=("${@:2}")
    if [[ "${jobschdler,,}" == "slurm" ]]; then  # SLURM
        local IFS=","
        echo "--array=${subjobs[*]}"
    else                                         # PBS
        if [[ ${#subjobs[@]} -eq 1 ]]; then
            (( nextno = subjobs[0]+1 ))
            echo "-J ${subjobs[0]}-${nextno}:2"
        elif [[ ${#subjobs[@]} -eq 2 ]]; then
            (( stepno = subjobs[1]-subjobs[0] ))
            echo "-J ${subjobs[0]}-${subjobs[1]}:${stepno}"
        else
            local minno=${subjobs[0]}
            local maxno=${subjobs[-1]}

            for i in "${subjobs[@]}"; do
                (( i > maxno )) && maxno=$i
                (( i < minno )) && minno=$i
            done
            (( stepno = (maxno-minno)/(${#subjobs[@]}-1) ))
            echo "-J ${minno}-${maxno}:${stepno}"
        fi
    fi
}

########################################################################

function join_by {
    local IFS="$1"
    echo "${*:2}"
}

########################################################################

#verb=false
#readconf config.ini COMMON SECTION1

function readconf {
    if [[ $# -lt 2 ]]; then
        echo -e "${RED}ERROR${NC}: No enough argument to function \"readconf\"."
        exit 1
    fi
    local configfile=$1
    local sections

    sections=$(join_by \| "${@:2}")
    local debug=0

    if [[ ! -e $configfile ]]; then
        echo -e "${RED}ERROR${NC}: Case configuration file: $configfile not exist. Have you run setup_mpas-wofs_grid.sh?"
        exit 1
    fi

    local readmode line

    readmode=false
    while read -r line; do
        if [[ $debug -eq 1 ]]; then
            if [[ "$line" == "" ]]; then
                echo "$line"
                continue
            else
                echo -ne "$line \t\t\t ### \t"
            fi
        fi

        # remove leading whitespace from a string
        line=${line##+([[:space:]])}
        # remove trailing whitespace from a string
        line=${line%%+([[:space:]])}

        if [[ "$line" =~ \[$sections\] ]]; then
            if [[ $debug -eq 1 ]]; then echo "Found $sections"; fi
            readmode=true
            continue
        elif [[ "$line" == \[*\] ]]; then
            if [[ $debug -eq 1 ]]; then echo "Another Section"; fi
            readmode=false
            continue
        elif [[ "$line" =~ ^#.* ]]; then
            if [[ $debug -eq 1 ]]; then echo "Comment"; fi
            continue
        fi

        if $readmode; then
            # remove comment starting with "# "
            line=${line%%# *}

            if [[ "$line" =~ "=" ]]; then
                if [[ $debug -eq 1 ]]; then echo "source: $line"; fi
                eval "$line"
            else
                if [[ $debug -eq 1 ]]; then echo "skip: $line"; fi
            fi
        else
            if [[ $debug -eq 1 ]]; then echo "ignored"; fi
        fi

    done < $configfile
}

########################################################################

function convert2days {
    # Usage:
    #   read -r -a g_date < <(convert2days "${anlys_date}" "${anlys_time}")
    #   echo "${g_date[0]}, ${g_date[1]}"
    #         days          seconds since 1601-01-01 00:00:00

    local datestr=$1
    local timestr=$2

    if [[ $# -ne 2 ]]; then
        echo "No enough argument for \"${FUNCNAME[0]}:\", get: $*"
        exit 0
    fi

    # epoch: 1970-01-01 00:00:00 is 134774 days since '1601-01-01'
    # one day is 86400 seconds

    local g_sec g_days g_secs
    g_sec=$(date -u -d "${datestr} ${timestr}" +%s)
    (( g_days=g_sec/86400 + 134774 ))
    (( g_secs=g_sec-86400*(g_sec/86400) ))

    echo "$g_days $g_secs"
}

########################################################################

function convertS2days {
    # Usage:
    #   read -r -a g_date < <(convertS2days "${seconds}")
    #   echo "${g_date[0]}, ${g_date[1]}"
    #         days          seconds since 1601-01-01 00:00:00

    local g_sec=$1

    if [[ $# -ne 1 ]]; then
        echo "No enough argument for \"${FUNCNAME[0]}:\", get: $*"
        exit 0
    fi

    # epoch: 1970-01-01 00:00:00 is 134774 days since '1601-01-01'
    # one day is 86400 seconds

    local g_days g_secs
    (( g_days=g_sec/86400 + 134774 ))
    (( g_secs=g_sec-86400*(g_sec/86400) ))

    echo "$g_days $g_secs"
}

########################################################################

function convert2date {
    # Usage:
    #   read -r -a e_date < <(convert2date "${days}" "${seconds}")
    #   echo "${e_date[0]}, ${e_date[1]}"
    #         %Y%m%d        %H%M

    local days=$1
    local secs=$2

    if [[ $# -ne 2 ]]; then
        echo "No enough argument for \"${FUNCNAME[0]}:\", get: $*"
        exit 0
    fi

    # epoch: 1970-01-01 00:00:00 is 134774 days since '1601-01-01'
    # one day is 86400 seconds

    local epoch_sec datestr
    (( epoch_sec= (days-134774)*86400 + secs ))
    datestr=$(date -u -d @"${epoch_sec}" +%Y%m%d%H%M)

    echo "${datestr:0:8} ${datestr:8:4}"
}

########################################################################

function upnlevels {
    local newndir=$1
    local n=$2

    for ((i=1; i<=n; i++)); do
        newndir=$(dirname $newndir)
    done

    echo "$newndir"
}

########################################################################

function wait_for_file_age {
    local file_name=$1
    local min_age=$2   # in seconds

    local file_path
    file_path=$(realpath ${file_name})

    if [[ ! -f ${file_path} ]]; then
        echo "File: $file_path not exists."
        return 1
    fi

    fileage=$(( $(date +%s) - $(stat -c %Y "${file_path}") ))
    while [[ $fileage -lt ${min_age} ]]; do
        #echo "Waiting for ${file_path} (age: $fileage seconds) ...."
        sleep 10
        fileage=$(( $(date +%s) - $(stat -c %Y "${file_path}") ))
    done

    return 0
}

########################################################################

function wait_for_file_size {
    local file_name=$1
    local min_size=$2    # in bytes

    local file_path
    file_path=$(realpath ${file_name})

    if [[ ! -f ${file_path} ]]; then
        echo "File: $file_path not exists."
        return 1
    fi

    filesize=$(stat -c %s ${file_path})
    while [[ $filesize -lt ${min_size} ]]; do
        #echo "Waiting for ${file_path} (size: $filesize bytes) ...."
        sleep 10
        filesize=$(stat -c %s ${file_path})
    done

    return 0
}

########################################################################

function link_grib {
    alpha=( A B C D E F G H I J K L M N O P Q R S T U V W X Y Z )
    i1=0
    i2=0
    i3=0

    rm -f GRIBFILE.??? >& /dev/null

    for f in "$@"; do
       ln -sf ${f} GRIBFILE.${alpha[$i3]}${alpha[$i2]}${alpha[$i1]}
       (( i1++ ))

       if [[ $i1 -ge 26 ]]; then
          (( i1=0 ))
          (( i2++ ))
         if [[ $i2 -ge 26 ]]; then
            (( i2=0 ))
            (( i3++ ))
            if [[ $i3 -ge 26 ]]; then
               echo "RAN OUT OF GRIB FILE SUFFIXES!"
            fi
         fi
       fi
    done
}

########################################################################

function clean_mem_runfiles {

    local jobname=$1
    local mywrkdir=$2
    local nummem=$3                    # total number of jobs

    local mem memstr memdir donefile

    cd $mywrkdir  || return

    done=0
    for mem in $(seq 1 $nummem); do
        memstr=$(printf "%02d" $mem)
        memdir="${jobname}_$memstr"
        donefile="$memdir/done.${jobname}_$memstr"

        #echo $donefile, $memdir
        if [[ -e $donefile ]]; then
            if [[ $verb -eq 1 ]]; then
                echo "$donefile exist, delete \"$memdir\" & \"${jobname}_${mem}_*.log\" ...."
            fi
            rm -rf $memdir
            rm -f  ${jobname}_${mem}_*.log
            (( done+=1 ))
        else
            if [[ $verb -eq 1 ]]; then
                echo "$donefile not found. Skip deleting \"$memdir\" & \"${jobname}_${mem}_*.log\"."
            fi
        fi
    done

    if [[ $done -eq $nummem ]]; then
        rm -f queue.$jobname
        touch done.$jobname
    fi
}

########################################################################

# Black        0;30     Dark Gray     1;30
# Red          0;31     Light Red     1;31
# Green        0;32     Light Green   1;32
# Brown/Orange 0;33     Yellow        1;33
# Blue         0;34     Light Blue    1;34
# Purple       0;35     Light Purple  1;35
# Cyan         0;36     Light Cyan    1;36
# Light Gray   0;37     White         1;37
# ---------- constant part!

# shellcheck disable=SC2034
if [ -t 1 ]; then
    NC='\033[0m'            # No Color
    BLACK='\033[0;30m';     DARK='\033[1;30m'
    RED='\033[0;31m';       LIGHT_RED='\033[1;31m'
    GREEN='\033[0;32m';     LIGHT_GREEN='\033[1;32m'
    BROWN='\033[0;33m';     YELLOW='\033[1;33m'
    BLUE='\033[0;34m';      LIGHT_BLUE='\033[1;34m'
    PURPLE='\033[0;35m';    LIGHT_PURPLE='\033[1;35m'
    CYAN='\033[0;36m';      LIGHT_CYAN='\033[1;36m'
    LIGHT='\033[0;37m';     WHITE='\033[1;37m'
else
    NC=''
    BLACK='';     DARK=''
    RED='';       LIGHT_RED=''
    GREEN='';     LIGHT_GREEN=''
    BROWN='';     YELLOW=''
    BLUE='';      LIGHT_BLUE=''
    PURPLE='';    LIGHT_PURPLE=''
    CYAN='';      LIGHT_CYAN=''
    LIGHT='';     WHITE=''
fi
#    vvvv vvvv -- EXAMPLES -- vvvv vvvv
# echo -e "I ${RED}love${NC} Stack Overflow"
# printf "I ${RED}love${NC} Stack Overflow\n"
#