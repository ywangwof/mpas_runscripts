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
                let bakno++
                bakdir="$basedir/${namedir}.bak$bakno"
            done

            for ((i=$bakno;i>0;i--)); do
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
        echo "No enough argument in \"submit_a_jobscript\", get: $@"
        exit 0
    fi

    local mywrkdir=$1
    local myjobname=$2
    local sedscript=$3
    local myjobtemp=$4
    local myjobscript=$5
    local myjoboption=$6

    cd $mywrkdir

    sed -f $sedscript $myjobtemp > $myjobscript
    if [[ $verb -eq 1 ]]; then
        echo "Generated job file \"$myjobscript\" from \"$myjobtemp\" with sed file \"$sedscript\""
    else
        rm -f $sedscript
    fi

    if [[ $dorun == true ]]; then echo -n "Submitting $myjobscript .... "; fi
    $runcmd $myjoboption $myjobscript
    if [[ $dorun == true && $? -eq 0 ]]; then touch $mywrkdir/queue.$myjobname; fi
    echo " "
}
########################################################################

function check_and_resubmit {
    local jobname=$1
    local mywrkdir=$2
    local donenum=$3                    # total number of jobs
    local myjobscript=${4-}             # empty no resubmissions
    local numtries=${5-0}               # number of resubmissions

    # global variables:
    # $runcmd, $verb

    local numtry done memdir runjobs jobarrays mem memstr
    local donefile errorfile

    cd $mywrkdir

    numtry=0; done=0

    runjobs=$(seq 1 $donenum)
    while [[ $done -lt $donenum && $numtry -lt $numtries ]]; do
        jobarrays=()
        for mem in ${runjobs}; do
            memstr=$(printf "%02d" $mem)
            memdir="$mywrkdir/${jobname}_$memstr"
            donefile="$memdir/done.${jobname}_$memstr"
            errorfile="$memdir/error.${jobname}_$memstr"

            echo "$$: Checking: $donefile"
            while [[ ! -e $donefile ]]; do
                if [[ $verb -eq 1 ]]; then
                    echo "Waiting for $donefile"
                fi

                if [[ -e $errorfile ]]; then
                    jobarrays+=($mem)
                    let done-=-1
                    break
                fi
                sleep 10
            done
            let done+=1
        done

        if [[ $done -eq $donenum ]]; then
            touch $mywrkdir/done.${jobname}
            rm -f $mywrkdir/queue.${jobname}
            break
        elif [[ $myjobscript && ${#jobarrays[@]} -gt 0 ]]; then
            runjobs=( "${jobarrays[@]} ")
            echo "Try these failed jobs again: ${runjobs[@]}"
            $runcmd "--array=$(join_by_comma ${runjobs[@]})" $myjobscript
        fi
        let numtry+=1
    done

}

########################################################################

function join_by_comma {
    local IFS=","
    echo "$*"
}

########################################################################

function upnlevels {
    local newndir=$1
    local n=$2

    for ((i=1; i<=$n; i++)); do
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

    for f in ${*}; do
       ln -sf ${f} GRIBFILE.${alpha[$i3]}${alpha[$i2]}${alpha[$i1]}
       let i1++

       if [[ $i1 -ge 26 ]]; then
          let i1=0
          let i2++
         if [[ $i2 -ge 26 ]]; then
            let i2=0
            let i3++
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

    cd $mywrkdir

    for mem in $(seq 1 $nummem); do
        memstr=$(printf "%02d" $mem)
        memdir="${jobname}_$memstr"
        donefile="$memdir/done.${jobname}_$memstr"

        if [[ -e $donefile ]]; then
            rm -rf $memdir
            rm -f  ${jobname}_${mem}_*.log
        fi
    done
}

########################################################################

