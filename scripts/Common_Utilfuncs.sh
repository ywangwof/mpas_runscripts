#!/bin/bash
# shellcheck disable=SC2317,SC1090,SC1091,SC2086

# Export Functions:
#
# o mkwrkdir
# o submit_a_jobscript
# o check_and_resubmit
# o get_jobarray_str         # Retrieve job array option string based on job scheduler
# o group_jobs_for_pbs       # Group job numbers for PBS job array option "-J X-Y[:Z]%num"
# o join_by                  # Join array into a string by a separator
# o readconf                 # Read config file, written from "setup_mpas-wofs_grid.sh"
# o upnlevels                # get n level parent directory path
# o link_grib                # Link grib files for ungrib.exe
# o clean_mem_runfiles
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
        echo "$$-${FUNCNAME[0]}: Generated job script: \"$myjobscript\" "
        echo "                   from template: \"$myjobtemp\" "
        echo "                   with sed file: \"$sedscript\"  "
    else
        rm -f $sedscript
    fi

    # shellcheck disable=SC2154
    if [[ $dorun == true ]]; then echo -n "Submitting $myjobscript .... "; fi
    # shellcheck disable=SC2154
    $runcmd ${myjoboption} "$myjobscript"
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
                                        # > 0 Wait for job done or resubmit failed jobs before exiting
                                        # = 0 check number of done jobs only

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
    if [[ $numtries -eq 0 ]]; then
        numtries=1
        checkonly=true
    fi

    # check each member's status
    while IFS='' read -r line; do
        runjobs+=("$line");
    done < <(seq 1 $donenum)

    numtry=0
    done=0; error=0; running=0
    while [[ $numtry -lt $numtries ]]; do
        jobarrays=()
        for mem in "${runjobs[@]}"; do
            memstr=$(printf "%02d" $mem)
            memdir="$mywrkdir/${memname}$memstr"
            donefile="$memdir/done.${jobname}_$memstr"
            errorfile="$memdir/error.${jobname}_$memstr"

            if [[ $verb -eq 1 ]]; then echo "$$-${FUNCNAME[0]}: Checking $donefile"; fi
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

        if $checkonly; then break; fi

        (( numtry+=1 ))

        if [[ $done -eq $donenum ]]; then
            touch $mywrkdir/done.${jobname}
            rm -f $mywrkdir/queue.${jobname}
            break                                  # No further check needed
        elif $checkonly; then
            break                                  # Stop further try
        elif [[ ${#jobarrays[@]} -gt 0 ]]; then    # failed jobs found
            if [[ $myjobscript == *.slurm ]]; then
                runjobs=( "${jobarrays[@]}" )
                echo "$$-${FUNCNAME[0]}: ${numtry}/${numtries} - Try these failed jobs again: ${runjobs[*]}"
                jobs_str=$(get_jobarray_str 'slurm' "${runjobs[@]}")
                $runcmd ${jobs_str} $myjobscript
                error=0                            # Perform another try
            else
                jobgroupstr=$(group_jobs_for_pbs "${runjobs[@]}")
                IFS=";" read -r -a jobgroups <<< "${jobgroupstr}"; unset IFS  # convert string to array
                #while IFS=';' read -r line; do jobgroups+=("$line"); done < <(group_jobs_for_pbs "${runjobs[*]}")
                for jobg in "${jobgroups[@]}"; do
                    IFS=" " read -r -a jobgar <<< "${jobg}"; unset IFS        # convert string to array
                    jobgstr=$(get_jobarray_str 'pbs' "${jobgar[@]}")
                    $runcmd ${jobgstr} $myjobscript
                done
                error=0                             # Perform another try
                #break                              # Stop further try for PBS jobs scheduler
            fi
        fi

    done

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

function group_jobs_for_pbs {
    local jobnos=("${@}")

    # Sort job nos
    IFS=$'\n' origjobstr="${jobnos[*]}"; unset IFS
    #mapfile -t sortedjobno < <(sort -g <<<"${origjobstr}")
    local sortedjobno=()
    while IFS='' read -r line; do
        sortedjobno+=("$line")
    done < <(sort -g <<<"${origjobstr}")

    # Find continous job nos
    local ars=()
    local sortedar=("${sortedjobno[@]}")

    local ar2=("${sortedar[@]}")
    for step in $(seq 1 10); do

        if [[ ${#sortedar[@]} -lt 3 ]]; then break; fi

        #echo "step=${step}: ${sortedar[*]}"
        for cidx in "${!sortedar[@]}"; do

            local prev=${sortedar[$cidx]}

            #echo "    prev=$prev: ${ar2[*]}"

            if [[ " ${ar2[*]} " =~ \ ${prev}\  ]]; then   # the number is still in the left set

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
                    ars+=("${ar1[*]}")
                    for didx in "${dropset[@]}"; do
                        unset -v "ar2[$didx]"
                    done
                    ar2=("${ar2[@]}")
                    #echo "        new ar2=${ar2[*]}"
                fi
            fi
        done
        sortedar=("${ar2[@]}")
    done

    # every element contains at least two jobs numbers even they are not continous
    for ((i=0;i<${#ar2[@]};i+=2)); do
        (( j=i+1 ))
        ars+=("${ar2[$i]} ${ar2[$j]}")
    done

    IFS=$';' retjobstr="${ars[*]}"; unset IFS    # convert array to string
    echo "${retjobstr}"
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

