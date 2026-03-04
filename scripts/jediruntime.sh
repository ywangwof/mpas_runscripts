#!/bin/bash

function integration_time {
   # show integration time from a MPAS log file
   token=${2-"Timing for integration step:"}

   tmpfile=$(mktemp -t timestep_XXX)
   grep -E "${token}|Begin timestep" "$1" > "${tmpfile}"
   paste -d " " - - < "${tmpfile}"
   rm -rf "${tmpfile}"
}

#-----------------------------------------------------------------------

function usage {
    echo " "
    echo "    USAGE: $0 [options] rundir [taskname]"
    echo " "
    echo "    PURPOSE: Check JEDI task run time."
    echo " "
    echo "    rundir       - Working directory for the task."
    echo "    taskname     - Task name, one of [observer,solver,post,mpas], default total"
    echo "                   mpas: timing for integration in a file, \"rundir\" should be a file name"
    echo " "
    echo "    OPTIONS:"
    echo "              -h                  Display this message"
    echo "              -n                  Show command to be run and generate job scripts only"
    echo "              -v                  Verbose mode"
    echo "              -m   36             Number of ensemble members, default 36"
    echo "              -t   Timing         Token to be retrieved from the log file"
    echo "                                  one of [Timing, 'max w', 'max u', 'max scalar [1-16]']"
    echo " "
    echo "                                     -- By Y. Wang (2026.03.02)"
    echo " "
    exit "$1"
}

#-----------------------------------------------------------------------
function get_mpas_average {

    local fcstime=$1
    local total_sec=0

    for((n=1;n<=NENS;n++));  do
        nm=$(printf "%02d" $n)
        IFS=':' read -r -d '' -a words < <( grep "Job run time" "$rundir"/"${fcstime}"/"fcst_${n}_mpas"_*.log && printf '\0')
        hour=${words[-3]}
        min=${words[-2]}
        sec=${words[-1]}
        # remove leading whitespace from a string
        #hour=${hour##+([[:space:]])}
        hour=${hour//[$'\t\r\n ']}
        # remove trailing whitespace from a string
        #sec=${sec%%+([[:space:]])}
        sec=${sec//[$'\t\r\n. ']}

        #echo "memeber $nm: ${taskname} run time: ${hour}:${min}:${sec}"

        runtimes_mins["${nm}"]="${hour}:${min}:${sec}"
        runtimes_secs["${nm}"]="$((10#$hour*3600+10#$min*60+10#$sec))"

        (( total_sec+=${runtimes_secs[$nm]} ))

        if [[ ${min_sec} -gt ${runtimes_secs[$nm]} ]]; then
            min_sec=${runtimes_secs[$nm]}
            min_m=$nm
        fi

        if [[ $max_sec -lt ${runtimes_secs[$nm]} ]]; then
            max_sec=${runtimes_secs[$nm]}
            max_m=$nm
        fi

    done

    #echo "Total   = ${total_sec} seconds"
    average_secs=$(bc <<< "$total_sec/$NENS" )
    #echo "Average = ${average_secs} seconds"

    (( hour = average_secs/3600 ))
    (( diff = average_secs%3600 ))
    (( min  = diff/60 ))
    (( sec  = diff%60 ))
    average_mins=$(printf '%02d:%02d:%02d' $hour $min $sec )

    #echo "Minimum ${taskname} run time: ${min_sec} seconds = ${runtimes_mins[${min_m}]} (${min_m})."
    #echo "Maximum ${taskname} run time: ${max_sec} seconds = ${runtimes_mins[${max_m}]} (${max_m})."
    #echo "Average ${taskname} run time: ${average_secs} seconds, as ${average_mins} ."

    echo "${average_secs}"
}

#-----------------------------------------------------------------------
function get_task_time {

    local taskname=$1
    local fcstime=$2

    if [[ $taskname == "mpas" ]]; then
        mpas_avg=$(get_mpas_average "${fcstime}")
        echo "$mpas_avg"
        return
    fi

    logtask="jedi_${taskname}/jedi_${taskname}"

    IFS=':' read -r -d '' -a words < <( grep "Job run time" "$rundir"/"${fcstime}"/"${logtask}"_*.log && printf '\0')
    hour=${words[-3]}
    min=${words[-2]}
    sec=${words[-1]}
    # remove leading whitespace from a string
    #hour=${hour##+([[:space:]])}
    hour=${hour//[$'\t\r\n ']}
    # remove trailing whitespace from a string
    #sec=${sec%%+([[:space:]])}
    sec=${sec//[$'\t\r\n. ']}

    #echo "memeber $nm: ${taskname} run time: ${hour}:${min}:${sec}"

    #local tasktimes_mins="${hour}:${min}:${sec}"
    local tasktimes_secs="$((10#$hour*3600+10#$min*60+10#$sec))"

    echo "${tasktimes_secs}"
}

########################################################################

show=""
verb=false

rundir="."
taskname="fcst"
NENS=36
token="Timing for integration step:"
timeavg=true
indexval=6

#-----------------------------------------------------------------------
#
# Handle command line arguments (override default settings)
#
#-----------------------------------------------------------------------
#% ARGS

while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
        -h)
            usage 0
            ;;
        -n)
            # shellcheck disable=SC2034
            show="echo"
            ;;
        -v)
            # shellcheck disable=SC2034
            verb=true
            ;;
        -m)
            if [[ $2 =~ ^[0-9]{1,2}$ ]]; then
                NENS=$2
            else
                echo "ERROR: should be a number for ensemble members, got: $2"
                usage 1
            fi
            shift
            ;;
        -t)
            if [[ "$2" =~ "Timing" ]]; then
                token="Timing for integration step:"
                timeavg=true; indexval=6
            elif [[ "$2" =~ "max u" ]]; then
                token="global min, max u"
                timeavg=false; indexval=6
            elif [[ "$2" =~ "max w" ]]; then
                token="global min, max w"
                timeavg=false; indexval=6
            elif [[ "$2" =~ "max scalar "([0-9]+) ]]; then
                token="global min, max scalar ${BASH_REMATCH[1]} "
                timeavg=false; indexval=7
            else
                echo "ERROR: should be words in the MPAS log file, got: $2"
                usage 1
            fi
            shift
            ;;
        -*)
            echo "Unknown option: $key"
            usage 2
            ;;
        observer | solver | post | mpas | total )
            taskname="$key"
            ;;
        *)
            if [[ -d $key ]]; then
                rundir="${key}"
            elif [[ -f $key ]]; then
                rundir="${key}"
            else
                echo ""
                echo "ERROR: unknown argument, get [$key]."
                usage 3
            fi
            ;;
    esac
    shift # past argument or value
done

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

declare -A runtimes_mins
declare -A runtimes_secs

min_m=0; min_sec=9999999
max_m=0; max_sec=0

total_m=0; count=0

if [[ "${taskname}" == "total" ]]; then
    for dir in [0-9][0-9][0-9][0-9]/; do
        fcstime=${dir%/}
        total_sec=0
        for task in "observer" "solver" "mpas"; do
            task_time=$(get_task_time "${task}" "${fcstime}")
            (( total_sec+=task_time ))
        done
        (( hour = total_sec/3600 ))
        (( diff = total_sec%3600 ))
        (( min  = diff/60 ))
        (( sec  = diff%60 ))
        total_str=$(printf '%02d:%02d:%02d' $hour $min $sec )
        echo "${fcstime} observer+solver+mpas = ${total_sec} second = ${total_str}"

        if [[ ${min_sec} -gt ${total_sec} ]]; then
            min_sec=${total_sec}
            min_m="$fcstime"
        fi

        if [[ $max_sec -lt ${total_sec} ]]; then
            max_sec=${total_sec}
            max_m="$fcstime"
        fi
        (( total_m += total_sec ))
        (( count+=1))
    done

    average_secs=$(bc <<< "$total_m/$count" )

    echo "Minimum cycle time: ${min_sec} seconds at ${min_m}."
    echo "Maximum cycle time: ${max_sec} seconds at ${max_m}."
    echo "Average cycle time: ${average_secs} seconds."

else
    for dir in [0-9][0-9][0-9][0-9]/; do
        fcstime=${dir%/}
        task_time=$(get_task_time "${taskname}" "${fcstime}")
        echo "${fcstime}: ${taskname} took ${task_time} second"
    done
fi

exit 0
