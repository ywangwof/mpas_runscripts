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
    echo "    PURPOSE: Check MPAS task run time."
    echo " "
    echo "    rundir       - Working directory for the task."
    echo "    taskname     - Task name, one of [fcst,update_states,update_bc,mpassit???,mpas], default fcst"
    echo "                   mpas: timing for integration in a file, \"rundir\" should be a file name"
    echo " "
    echo "    OPTIONS:"
    echo "              -h                  Display this message"
    echo "              -n                  Show command to be run and generate job scripts only"
    echo "              -v                  Verbose mode"
    echo "              -m   18             Number of ensemble members, default 18"
    echo "              -t   Timing         Token to be retrieved from the log file"
    echo "                                  one of [Timing, 'max w', 'max u', 'max scalar [1-16]']"
    echo " "
    echo "                                     -- By Y. Wang (2024.04.17)"
    echo " "
    exit "$1"
}

########################################################################

show=""
verb=false

rundir="."
taskname="fcst"
NENS=18
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
        mpas | fcst | update_states | update_bc | mpassit??? )
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

if [[ "${taskname}" == "mpas" ]]; then

    if [[ ! -f $rundir ]]; then
        if [[ ! -f $rundir/log.atmosphere.0000.out ]]; then
            echo "ERROR: a MPAS log file is required."
            usage 2
        else
            rundir="$rundir/log.atmosphere.0000.out"
        fi
    fi

    total_min=0.0; total_max=0.0; nsteps=0

    while IFS= read -r line; do
        echo "${line}"
        read -r -a my_array <<< "$line"
        #echo "${my_array[2]} -> ${my_array[7]}, ${my_array[8]}"
        timestr="${my_array[2]}"
        myindex=$((indexval+1))
        minval="${my_array[$myindex]}"
        minval=${minval//[$'\t\r\n ']}  # remove whitespace from a string
        if ! ${timeavg}; then
            myindex=$((indexval+2))
            maxval="${my_array[$myindex]}"
            maxval=${maxval//[$'\t\r\n ']}  # remove whitespace from a string
            if [[ $maxval =~ "E" ]]; then
                maxval=$(sed -E 's/([+-]?[0-9.]+)[eE]\+?(-?)([0-9]+)/\1*10^\2\3/g' <<<"$maxval")
            fi
        else
            maxval=${minval}
        fi

        runtimes_secs[$timestr]=${minval}

        total_min=$(bc -l <<< "$total_min + $minval")
        total_max=$(bc -l <<< "$total_max + $maxval")
        (( nsteps += 1 ))

        if (( $(bc -l <<< "${min_sec} > ${minval}") )); then
            min_sec=${minval}
            min_m=$timestr
        fi

        if (( $(bc -l <<< "${max_sec} < ${maxval}") )); then
            max_sec=${maxval}
            max_m=$timestr
        fi
    done < <( integration_time "$rundir" "$token" )

    if ${timeavg}; then
        echo ""
        echo "Total = ${total_min} seconds in ${nsteps} integration steps."

        average_secs=$(bc -l <<< "scale=5; $total_min/$nsteps" )

        echo "Minimum ${taskname} integration time: ${min_sec} seconds = ${runtimes_secs[${min_m}]} (at ${min_m})."
        echo "Maximum ${taskname} integration time: ${max_sec} seconds = ${runtimes_secs[${max_m}]} (at ${max_m})."
        echo "Average ${taskname} integration time: ${average_secs} seconds."
    else
        echo ""
        echo "Minimum ${token}: ${min_sec} at ${min_m}."
        echo "Maximum ${token}: ${max_sec} at ${max_m}."
    fi
else               # ensemble tasks

    total_sec=0

    for((n=1;n<=NENS;n++)); do
        nm=$(printf "%02d" $n)
        IFS=':' read -r -d '' -a words < <( grep "Job run time" "$rundir"/"${taskname}_${n}"_*.log && printf '\0')
        hour=${words[-3]}
        min=${words[-2]}
        sec=${words[-1]}
        # remove leading whitespace from a string
        #hour=${hour##+([[:space:]])}
        hour=${hour//[$'\t\r\n ']}
        # remove trailing whitespace from a string
        #sec=${sec%%+([[:space:]])}
        sec=${sec//[$'\t\r\n ']}

        echo "memeber $nm: ${taskname} run time: ${hour}:${min}:${sec}"

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

    echo "Total   = ${total_sec} seconds"
    average_secs=$(bc <<< "$total_sec/$NENS" )
    echo "Average = ${average_secs} seconds"

    (( hour = average_secs/3600 ))
    (( diff = average_secs%3600 ))
    (( min  = diff/60 ))
    (( sec  = diff%60 ))
    average_mins=$(printf '%02d:%02d:%02d' $hour $min $sec )

    echo "Minimum ${taskname} run time: ${min_sec} seconds = ${runtimes_mins[${min_m}]} (${min_m})."
    echo "Maximum ${taskname} run time: ${max_sec} seconds = ${runtimes_mins[${max_m}]} (${max_m})."
    echo "Average ${taskname} run time: ${average_secs} seconds, as ${average_mins} ."
fi

exit 0