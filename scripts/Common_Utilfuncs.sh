#!/bin/bash

# Export Functions:
#
# o mkwrkdir submit_a_jobscript
# o check_and_resubmit
# o join_by_comma
# o link_grib
# o clean_mem_runfiles
#

########################################################################

function mkwrkdir {
    # make a directory
    # the second argument is the creating mode
    # 0: Keep existing directory as is
    # 1: Remove existing same name directory
    # 2: Back up existing same name directory with appendix ".bakX"
    #    X starts from 0, the less the number, the backup directory is the newer one.
    #
    if [[ $# -ne 2 ]]; then
        echo "ERROR: argument in mkwrkdir, get \"$*\"."
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
            echo "Baking $mydir --> $bakdir ..."
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
        echo "$$-${FUNCNAME[0]}: Generated job file \"$myjobscript\" from "
        echo "                  \"$myjobtemp\" with sed file \"$sedscript\""
    else
        rm -f $sedscript
    fi

    # shellcheck disable=SC2154
    if [[ $dorun == true ]]; then echo -n "Submitting $myjobscript .... "; fi
    # shellcheck disable=SC2154
    $runcmd $myjoboption $myjobscript
    if [[ $dorun == true && $? -eq 0 ]]; then touch $mywrkdir/queue.$myjobname; fi
    echo " "
}

########################################################################

function check_and_resubmit {
    #local jobnames=$1                  # Comment out, read $1 as an array below
    local mywrkdir=$2
    local donenum=$3                    # total number of jobs
    local myjobscript=${4-}             # empty no resubmissions
    local numtries=${5-0}               # number of resubmissions
                                        # >= 0 check and wait for job done or failed to exit the whole program
                                        # <  0 check number of done files only

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

    checkonly=false
    if [[ $numtries -lt 0 ]]; then
        numtries=0
        checkonly=true
    fi

    numtry=0; done=0; running=0

    if [[ -e $mywrkdir/done.${jobname} ]]; then    # do nothing
        done=$donenum
    else                                           # check each member's status
        runjobs=$(seq 1 $donenum)
        #echo ${runjobs[@]}
        while [[ $done -lt $donenum && $numtry -le $numtries ]]; do
            jobarrays=()
            for mem in ${runjobs}; do
                memstr=$(printf "%02d" $mem)
                memdir="$mywrkdir/${memname}$memstr"
                donefile="$memdir/done.${jobname}_$memstr"
                errorfile="$memdir/error.${jobname}_$memstr"

                if [[ $verb -eq 1 ]]; then echo "$$-${FUNCNAME[0]}: Checking $donefile"; fi
                while [[ ! -e $donefile ]]; do
                    if [[ -e $errorfile ]]; then
                        jobarrays+=("$mem")
                        (( done-=-1 ))
                        break
                    elif $checkonly; then
                        (( running+=1 ))
                        continue 2
                    fi

                    #if [[ $verb -eq 1 ]]; then
                    #    echo "Waiting for $donefile"
                    #fi
                    sleep 10
                done
                #if [[ $verb -eq 1 ]]; then echo $donefile; fi
                (( done+=1 ))
            done

            if [[ $done -eq $donenum ]]; then
                touch $mywrkdir/done.${jobname}
                rm -f $mywrkdir/queue.${jobname}
                break
            elif [[ $myjobscript && ${#jobarrays[@]} -gt 0 && $numtry -lt $numtries ]]; then
                runjobs=( "${jobarrays[@]} ")
                echo "Try these failed jobs again: ${runjobs[*]}"
                jobs_str=$(join_by_comma "${runjobs[@]}")
                $runcmd "--array=${jobs_str}" $myjobscript
            fi
            (( numtry+=1 ))
        done
    fi

    #
    # Output a message and then return or exit
    #
    outmessage="Status of $jobname: done: $done"
    if [[ $running -gt 0 ]]; then
        outmessage="$outmessage; queued/running: $running"
    fi

    if [[ ${#jobarrays[@]} -gt 0 ]]; then
        outmessage="$outmessage; failed: ${#jobarrays[@]} - [${jobarrays[*]}]"
    fi

    echo "$$-${FUNCNAME[0]}: $outmessage"
    if [[ $done -lt $donenum ]]; then
        if $checkonly; then
            return
        else
            exit 9
        fi
    fi
}

########################################################################

function join_by_comma {
    local IFS=","
    echo "$*"
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
        echo "ERROR: No enough argument to function \"readconf\"."
        exit 1
    fi
    local configfile=$1
    local sections

    sections=$(join_by \| "${@:2}")
    local debug=0

    if [[ ! -e $configfile ]]; then
        echo "ERROR: Case configuration file: $configfile not exist. Have you run setup_mpas-wofs_grid.sh?"
        exit 1
    fi

    local readmode line

    readmode=false
    while read -r line; do
        #echo -n "<$line>"
        if [[ "$line" =~ \[$sections\] ]]; then
            if [[ $debug -eq 1 ]]; then echo "Found $sections: $line"; fi
            readmode=true
            continue
        elif [[ "$line" == \[*\] ]]; then
            if [[ $debug -eq 1 ]]; then echo "Another section: $line"; fi
            readmode=false
            continue
        elif [[ "$line" =~ ^# ]]; then
            if [[ $debug -eq 1 ]]; then echo "comment: $line"; fi
            continue
        fi

        if $readmode; then
            if [[ "$line" =~ "=" ]]; then
                if [[ $debug -eq 1 ]]; then echo -n "source: $line"; fi
                eval "export $line"
            else
                if [[ $debug -eq 1 ]]; then echo "skip: $line"; fi
            fi
            if [[ $debug -eq 1 ]]; then echo; fi
        fi

    done < $configfile
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

        #echo $donefile
        if [[ -e $donefile ]]; then
            rm -rf $memdir
            rm -f  ${jobname}_${mem}_*.log
            (( done+=1 ))
        fi
    done

    if [[ $done -eq $nummem ]]; then
        rm -f queue.$jobname
        touch done.$jobname
    fi
}

########################################################################

