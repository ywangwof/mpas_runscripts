#!/bin/bash
# shellcheck disable=SC2317,SC1090,SC1091,SC2086,SC2154

# Export Functions:
#
# o mkwrkdir
# o submit_a_job             # Create a job script base on the template and submit the job script
# o check_job_status         # Check ensemble job status
# o get_jobarray_str         # Retrieve job array option string based on job scheduler
# o group_numbers_by_steps   # Group job numbers for PBS job array option "-J X-Y[:Z]%num"
# o join_by                  # Join array into a string by a separator
# o join_arrays              # To join an array while ensuring you only add elements that don't already exist in the target (finding the union of the two sets)
# o intersection             # Intersection of two arrays, pass in as two strings and pass out as one intersected string
# o delete_array             # To remove elements from array1 that are present in array2 (essentially performing a set difference)
# o typeset2array            # Typeset output to an associative array
# o string2array             # '_' separated string to an array
# o is_balanced              # Check whether quote character is balanced  (used in readconf)
# o validate_assignment      # Check whether a string is a valid Bash variable assignment statement (String, Number, Array, Bool, used in readconf)
# o readconf                 # Read config file, written from "setup_mpas-wofs.sh"
# o get_parent_dir           # get n level parent directory path
# o get_3char_order          # Get 3-character letters from 0 for GRIB file processing
# o clean_mem_runfiles       # Clean the runtime files of an ensemble task
# o wait_for_file_size       # Hold the task until the file size exceeds the give number of bytes
# o wait_for_file_age        # Hold the task until the file age is older than the give number of seconds
# o wait_for_conditions      # Hold the process until files (conditions) appear
# o num_pending_jobs_greater_than       # Check number of jobs in the queue before submit a new job to avoid job flooding
# o mecho/mecho0/mecho1/mecho2    # Print text with function name prefix
# o split_graph              # Split graph.info file for the corresponding MPI processes
# o array_contains           # String is an element in the Array
# o array_keys_contains      # String is a key in the associated Array
# o sortnumarray             # Sort a number array and get a string
# o sortnumarrayuniq         # Sort a number array by removing duplicates and get a string
# o nums2range               # Condense a number array into a string with comma separated number and dash denotes range
# o expand_range             # Get a number array string from the condensed number string
# o select_option            # A standard Linux shell implementation of the "look and feel" of a Node.js tool like Enquirer

########################################################################

mydir=$(dirname "${BASH_SOURCE[0]}")
source ${mydir}/Common_Colors.sh

shopt -s extglob

########################################################################

function mecho {
    local i=$(($1-1))
    funstr=$(printf "%-18.18s" "${FUNCNAME[$1]}")
    linestr=$(printf "(%5s)" "${BASH_LINENO[${i}]}")
    echo $2 "${DARK}${funstr} ${linestr}${NC} : ${*:3}"
}

function mecho0 { mecho 2 -e "${*}"; }
function mecho1 { mecho 3 -e "${*}"; }
function mecho2 { mecho 4 -e "${*}"; }

function mecho0n { mecho 2 -ne "${*}"; }
function mecho1n { mecho 3 -ne "${*}"; }
function mecho2n { mecho 4 -ne "${*}"; }

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

    local mydir=$1
    local backup=$2

    local bakno bakdir

    if [[ -d ${mydir} ]]; then
        if [[ ${backup} -eq 1 ]]; then
            rm -rf ${mydir}
        elif [[ ${backup} -eq 2 ]]; then
            basedir=$(dirname ${mydir})
            namedir=$(basename ${mydir})
            bakno=0
            bakdir="${basedir}/${namedir}.bak${bakno}"
            while [[ -d ${bakdir} ]]; do
                (( bakno++ ))
                bakdir="${basedir}/${namedir}.bak${bakno}"
            done

            for ((i=bakno;i>0;i--)); do
                j=$((i-1))
                olddir="${basedir}/${namedir}.bak${j}"
                bakdir="${basedir}/${namedir}.bak${i}"
                echo "Moving ${olddir} --> ${bakdir} ..."
                mv ${olddir} ${bakdir}
            done
            bakdir="${basedir}/${namedir}.bak0"
            echo "Backing ${mydir} --> ${bakdir} ..."
            mv ${mydir} ${bakdir}
        fi
    fi
    mkdir -p ${mydir}
}

########################################################################

function submit_a_job {
    # Arguments
    #   1      2       3       4       5        6
    # wrkdir jobname jobparms jobtemp jobscript joboption
    #
    # Use global variables: $verbose, $dorun, $runcmd, $exedir
    #          $rootdir, $modulename, $machine
    #          $config_job_account_str, $config_job_exclusive_str
    #          $config_job_runexe_str, $config_job_runmpexe_str
    #
    # Purpose:
    #
    # 1. Create $myjobscript from $myjobtemp using SED based on scripts in $sedfile
    # 2. Submit $myjobscript using global command $runcmd
    # 3. Generate a queue file based on $myjobname in current working directory $mywrkdir
    #    if the job script is submitted correctly
    #
    if [[ $# -ne 6 ]]; then
        echo "No enough argument in \"submit_a_job\", get: $*"
        exit 0
    fi

    local mywrkdir=$1
    local myjobname=$2
    local -n jparms_ref=$3     # Bash 4.3 or newer
    local myjobtemp=$4
    local myjobscript=$5
    local myjoboption=$6

    local myverbose=${verbose:-false}
    if [[ ${verb} -eq 1 ]]; then
        myverbose=true
    fi

    cd ${mywrkdir}  || return

    local sedfile
    sedfile=$(mktemp -t ${myjobname}.sed_XXXX)

    jobdir="${mywrkdir}"
    #
    # Common parameters for all jobs
    #
    declare -A commparms=(
        [WRKDIR]="${jobdir}"
        [ROOTDIR]="${rootdir}"
        [MODULE]="${modulename}"
        [ACCTSTR]="${config_job_account_str}"
        [EXCLSTR]="${config_job_exclusive_str}"
        [MACHINE]="${machine}"
        [RUNCMD]="${config_job_runexe_str}"
        [RUNMPCMD]="${config_job_runmpexe_str}"
        [EXEDIR]="${config_EXEDIR}"
    )
    # If the job passes in a specific value for any of the common parameters
    # it will be taken. Merge the two arrays
    for parm in "${!jparms_ref[@]}"; do
        commparms[${parm}]="${jparms_ref[${parm}]}"
    done

    for parm in "${!commparms[@]}"; do
        echo "s^${parm}^${commparms[${parm}]}^g" >> ${sedfile}
    done

    sed -f ${sedfile} ${myjobtemp} > ${myjobscript}

    # Remove task-specific sections that don't match the current task
    local keepsections="${commparms[KEEPSECTIONS]:-}"
    for section in solver_pre solver_after post jobcheck funcdef addnoise noaddnoise; do
        if [[  " ${keepsections} " != *" ${section} "* ]]; then        # drop all sections that are not in the keepsections list
            sed -i "/# __BEGIN_${section}/,/# __END_${section}/d" "${myjobscript}"
        fi
    done
    sed -i "/# __BEGIN_\|# __END_/d" "${myjobscript}"

    # shellcheck disable=SC2154
    if [[ ${myverbose} == true ]]; then
        mecho1 "Generated job script: ${WHITE}${myjobscript}${NC}"
        mecho1 "from template       : ${BLUE}${myjobtemp}${NC} "
        #mecho1 "using sed file      : ${DARK}${sedfile}${NC}  "
    fi
    rm -f ${sedfile}

    # shellcheck disable=SC2206
    local -a commandlist=(${runcmd})

    # Options to the job itself
    if [[ -n ${myjoboption} ]]; then
        if [[ "${myjoboption}" == *" "* ]]; then
            # If it contains a space, split it into the array
            # This uses the default IFS (Internal Field Separator) which includes spaces
            # shellcheck disable=SC2206
            commandlist+=( ${myjoboption} )
        else
            # Otherwise, just append the string as one element
            commandlist+=( "${myjoboption}" )
        fi
    fi
    #[[ -f ${config_EXEDIR}/bad_nodes.txt ]] && commandlist+=("--exclude=$(paste -sd "," ${config_EXEDIR}/bad_nodes.txt)")
    commandlist+=("${myjobscript}")

    if [[ ${myverbose} == true ]]; then mecho0 "${commandlist[*]}"; fi

    if [[ -n ${myruncmd} ]]; then
        if [[ ${dorun} == true ]]; then mecho1n "Running ${BROWN}${myjobscript}${NC} .... "; fi
        if [[ ${myjoboption} =~ --output=(.*) ]]; then
            log_file="${BASH_REMATCH[1]}"
        else
            log_file="${mywrkdir}/${myjobname}.out"
        fi
        ${myruncmd} "${myjobscript}" > "$log_file" 2>&1
    else
        if [[ ${dorun} == true ]]; then mecho1n "Submitting ${BROWN}${myjobscript}${NC} .... "; fi
        "${commandlist[@]}"
        if [[ ${dorun} == true && $? -eq 0 ]]; then touch ${mywrkdir}/queue.${myjobname}; fi
    fi
    echo " "
}

########################################################################

function resubmit_a_jobscript {
    local myjobscript=$1
    local jobarray_str=$2

    read -r -a myjobs <<< "${jobarray_str}"

    if [[ ${myjobscript} == *.slurm ]]; then
        jobs_str=$(get_jobarray_str 'slurm' "${myjobs[@]}")
        ${runcmd} ${jobs_str} ${myjobscript}
    elif [[ ${myjobscript} == *.pbs ]]; then
        jobgroupstr=$(group_numbers_by_steps "${myjobs[@]}")
        IFS=";" read -r -a jobgroups <<< "${jobgroupstr}"; unset IFS  # convert string to array
        #while IFS=';' read -r line; do jobgroups+=("$line"); done < <(group_numbers_by_steps "${abortjobarray[*]}")
        for jobg in "${jobgroups[@]}"; do
            IFS=" " read -r -a jobgar <<< "${jobg}"; unset IFS        # convert string to array
            jobgstr=$(get_jobarray_str 'pbs' "${jobgar[@]}")
            ${runcmd} ${jobgstr} ${myjobscript}
        done
    else
        mecho0 "Do nothing for ${CYAN}${myjobscript}${NC}."
    fi

    # Clean the error.${jobname}_$memstr if needed
    #
    #for mem in "${abortjobarray[@]}"; do
    #    memstr=$(printf "%02d" $mem)
    #    memdir="$mywrkdir/${memname}$memstr"
    #    rm -rf "$memdir/error.${jobname}_$memstr"
    #done
}

########################################################################

function check_job_status {
    #local jobnames=$1                  # Comment out, read $1 as an array below
    local mywrkdir=$2
    local donenum=$3                    # total number of jobs
    local myjobscript=${4-None}         # empty no resubmissions
    local numtries=${5-1}               # number of resubmissions
                                        #  = 1 Wait for job done or error
                                        #  > 1 resubmit failed jobs ($numtries-1 times) before exiting
                                        #  = 0 check number of done jobs only

    read -r -a jobnames <<< "$1"
    local jobname=${jobnames[0]}
    if [[ ${#jobnames[@]} -eq 3 ]]; then     # if it is an array, the 2nd element denotes the member dirname
        local memname=${jobnames[1]}         # The 1st element is just the job name
        local stfile=${jobnames[2]}          # the 3rd element is the done file name to be checked
    elif [[ ${#jobnames[@]} -eq 1 ]]; then
        local memname="${jobname}"
        local stfile=${jobname}
    else
        mecho1 "${RED}FATAL${NC}: The first string to ${YELLOW}check_job_status${NC} can only contains 1 or 3 elements."
        exit
    fi

    # global variables:
    # $runcmd, $verbose

    local myverbose=${verbose:-false}
    if [[ ${verb} -eq 1 ]]; then
        myverbose=true
    fi

    local numtry "done" memdir runjobs mem memstr
    local memdonefile memerrorfile donefile

    cd ${mywrkdir} || { mecho1 "Working directory ${CYAN}${mywrkdir}${NC} not exist.";  exit $?; }

    if [[ -e ${mywrkdir}/done.${jobname} ]]; then    # do nothing
        done=${donenum}
        return
    fi

    checkonly=false
    if [[ ${numtries} -le 0 ]]; then checkonly=true; fi

    # check all member's status
    runjobs=()
    for ((i=1; i<=donenum; i++)); do
        runjobs+=("${i}")
    done
    #while IFS='' read -r line; do runjobs+=("$line"); done < <(seq 1 $donenum)

    local patterns pattern
    local sorted_files latestfile
    #-------------------------------------------------------------------
    # Check and wait for all members job status in ${runjobs} and
    # resubmit if necessary
    #-------------------------------------------------------------------
    mecho1 "Waiting for ensemble jobs of ${WHITE}${jobname}${NC} in ${LIGHT_BLUE}${mywrkdir##"${WORKDIR}"/}${NC}"
    donefile="${mywrkdir}/done.${jobname}"
    numtry=0
    while [[ ${numtry} -le ${numtries} ]]; do
        done=0; error=0; running=0; unknown=0; abort=0
        abortjobarray=(); errorjobarray=()

        for mem in "${runjobs[@]}"; do
            memstr=$(printf "%02d" ${mem})
            memdir="${mywrkdir}/${memname}_${memstr}"
            memdonefile="${memdir}/done.${stfile}_${memstr}"
            memerrorfile="${memdir}/error.${stfile}_${memstr}"

            if [[ ${myverbose} == true ]]; then mecho0 "Checking ${memdonefile}"; fi
            # 4 possiblilites
            #   1. done, do not enter the following loop
            #   2. queued or running, wait for the log file or error/done file
            #   3. abort, may be a machine error
            #   4. error, A program error? resubmitting will not help

            while [[ ! -e ${memdonefile} && ! -e ${donefile} ]]; do
                # Handle occasionally machine errors on Vecna

                # Define patterns in the order of priority
                patterns=(
                    "${mywrkdir}/${jobname}_${mem}_*.log"
                    "${mywrkdir}/*_${mem}_${jobname}_*.log"
                )

                latestfile=""

                for pattern in "${patterns[@]}"; do
                    # Check if the pattern matches any files
                    if compgen -G "${pattern}" > /dev/null; then
                        # Load all matches into an array, sorted numerically
                        readarray -td '' sorted_files < <(printf '%s\0' ${pattern} | sort -zV)

                        # Grab the highest sequence/number
                        latestfile="${sorted_files[-1]}"

                        # Found the target, stop looking through other patterns
                        break
                    fi
                done

                if [[ -f ${latestfile} ]]; then
                    #if grep -q "srun: Job step aborted:" ${latestfile}; then
                    if grep -q "slurmstepd: error:" ${latestfile}; then
                        # abort: Slurm error, resubmission may help
                        abortjobarray+=("${mem}")
                        (( abort+=1 ))
                        #rm ${latestfile}                               # to avoid it will be used for next try again
                        mv ${latestfile} ${latestfile}_try"${numtry}"    # to avoid it will be used for next try again
                        break
                    elif [[ -e ${memerrorfile} ]]; then   # error: program error, resubmission may not help
                        errorjobarray+=("${mem}")
                        (( error+=1 ))
                        break
                    fi
                fi

                if ${checkonly}; then
                    if [[ -e ${mywrkdir}/queue.${jobname} || -e running.${jobname}_${memstr} ]]; then
                        (( running+=1 ))
                    else
                        (( unknown+=1 ))
                    fi
                    break
                else                           # job pending or running
                    #if [[ ${myverbose} == true ]]; then echo "Waiting for $donefile"; fi
                    sleep 10
                fi
            done
            if [[ -e ${donefile} ]]; then
                done=${donenum}
                break
            elif [[ -e ${memdonefile} ]]; then
                (( done+=1 ))
            fi
        done

        (( numtry+=1 ))

        if [[ ${done} -eq ${donenum} ]]; then
            touch ${mywrkdir}/done.${stfile}
            rm -f ${mywrkdir}/queue.${stfile}
            break                                                               # No further check needed
        elif [[ ${#abortjobarray[@]} -gt 0 && ${numtry} -lt ${numtries} ]]; then    # aborted jobs found
            mecho1 "${numtry}/${numtries} - Try these failed jobs again: ${PURPLE}${abortjobarray[*]}${NC}"
            resubmit_a_jobscript "${myjobscript}" "${abortjobarray[*]}"
        else                                                                    # Stop further tries
            break
        fi
    done

    #-------------------------------------------------------------------
    # Output a status message and then return or exit
    #-------------------------------------------------------------------
    outmessage="Status of ${jobname}: done: ${GREEN}${done}${NC}"
    if [[ ${running} -gt 0 ]]; then
        outmessage="${outmessage}; queued/running: ${BROWN}${running}${NC}"
    fi

    if [[ ${unknown} -gt 0 ]]; then
        outmessage="${outmessage}; unknown: ${DARK}${unknown}${NC}"
    fi

    if [[ ${#errorjobarray[@]} -gt 0 ]]; then
        outmessage="${outmessage}; failed: ${#errorjobarray[@]} - [${LIGHT_RED}$(nums2range "${errorjobarray[@]}")${NC}]"
    fi

    if [[ ${#abortjobarray[@]} -gt 0 ]]; then
        outmessage="${outmessage}; SLURM failed: ${#abortjobarray[@]} - [${RED}$(nums2range "${abortjobarray[@]}")${NC}]"
    fi

    mecho1 "${outmessage}"
    if [[ ${done} -lt ${donenum} ]]; then
        if ${checkonly}; then return; else exit 9; fi
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
        sortednumbers+=("${line}")
    done < <(sort -g <<<"${orgnumberstr}")
    unset IFS

    # Find continous job nos
    local retarray=()
    local workarray=("${sortednumbers[@]}")

    local ar2=("${workarray[@]}")
    for step in $(seq 1 10); do

        if [[ ${#workarray[@]} -lt 3 ]]; then break; fi

        #echo "step=${step}: ${workarray[*]}"
        for idx in "${!workarray[@]}"; do

            local prev=${workarray[${idx}]}

            #echo "    prev=$prev: ${ar2[*]}"

            if [[ " ${ar2[*]} " =~ \ ${prev}\  ]]; then   # the number is still in the remain set

                local ar1=("${prev}")
                local dropset=()

                for nidx in "${!ar2[@]}"; do
                    local next=${ar2[${nidx}]}
                    #echo "        next=${next}, ar1=${ar1[*]}"
                    if (( 10#${next} == (10#${prev}+step) )); then
                        ar1+=("${next}")
                        dropset+=("${nidx}")
                        prev=${next}
                    elif [[ ${next} -eq ${prev} ]]; then
                        dropset+=("${nidx}")
                    fi
                done

                if [[ ${#ar1[@]} -ge 3 ]]; then
                    retarray+=("${ar1[*]}")
                    for didx in "${dropset[@]}"; do
                        unset -v "ar2[${didx}]"
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
        retarray+=("${workarray[${i}]} ${workarray[${j}]}")
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
                (( i > maxno )) && maxno=${i}
                (( i < minno )) && minno=${i}
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

function join_arrays {
    local -n array1="$1"
    local -n array2="$2"

    # Initialize arrays
    #array1=("1500" "1515" "1530")
    #array2=("1530" "1545" "1600")

    # 0. Safety Check: If the second array is empty, nothing to do
    if [[ ${#array2[@]} -eq 0 ]]; then
        return 0
    fi

    # 1. Create an associative array to track what's in array1
    declare -A seen
    for item in "${array1[@]}"; do
        seen["$item"]=1
    done

    # 2. Iterate through array2 and append only if not seen
    for item in "${array2[@]}"; do
        if [[ -z "${seen["$item"]}" ]]; then
            array1+=("$item")
            seen["$item"]=1 # Mark as seen so we don't add duplicates from array2 itself
        fi
    done

    # Result: array1 will be ("1500" "1515" "1530" "1545" "1600")
}

########################################################################

function delete_array {
    # To remove elements from array1 that are present in array2
    # (essentially performing a set difference),
    # the most efficient approach in Bash uses an associative array as a lookup table.
    [[ $# -lt 2 ]] && return 1

    # shellcheck disable=SC2178
    local -n array1="$1"
    local -n array2="$2"

    # 0. Safety Check: If target is empty or exclude is empty, nothing to do
    if [[ ${#array1[@]} -eq 0 ]]; then
        return 0
    fi

    if [[ ${#array2[@]} -eq 0 ]]; then
        return 0
    fi

    # Example setup
    #array1=("1500" "1515" "1530" "1545" "1600")
    #array2=("1515" "1545")

    # 1. Declare a lookup table (associative array) for array2
    declare -A to_remove
    for item in "${array2[@]}"; do
        to_remove["$item"]=1
    done

    # 2. Rebuild array1 by only keeping items NOT in the lookup table
    local new_array1=()
    for item in "${array1[@]}"; do
        if [[ -z "${to_remove["$item"]}" ]]; then
            new_array1+=("$item")
        fi
    done

    # 3. Finalize the change
    array1=("${new_array1[@]}")

    # Result: ("1500" "1530" "1600")
}

########################################################################

function intersection {
    read -r -a array_one <<< "$1"
    read -r -a array_two <<< "$2"

    IFS=$'\n'; set -f
    mapfile -t common < <( comm -12 <(
        printf '%s\n' "${array_one[@]}" | sort) <(
            printf '%s\n' "${array_two[@]}" | sort)
        )

    echo "${common[*]}"
}

########################################################################

function typeset2array {
    #
    # Set a string returned from 'typeset -p' to an associative array
    # The associative array name '$2' should have been declared before this call
    # Neither 'key' nor 'value' of associated array should contain any blank space
    #
    local arraystr="$1"
    local -n arrayname="$2"

    arraystr="${arraystr##declare -A *=(}"
    arraystr="${arraystr%% )}"

    #echo "$arraystr"

    while IFS="=" read -r key val; do
        # shellcheck disable=SC2034
        arrayname["${key}"]="${val}"
    done < <(
        echo "${arraystr}" |
            tr ' ' '\n' |
            tr -d '[]'
        )
}

########################################################################

function string2array {
    #
    # '_' separated string to an array
    #
    local arraystr="$1"
    local -n arrname="$2"


    arraystr=${arraystr##\"}
    arraystr=${arraystr%%\"}
    # shellcheck disable=SC2034
    IFS=$'_' read -r -a arrname <<< "${arraystr}"; unset IFS
}

########################################################################

function setsubtract {
    read -r -a array_one <<< "$1"
    read -r -a array_two <<< "$2"

    IFS=$'\n'; set -f
    mapfile -t diffset < <( comm -23 <(
        printf '%s\n' "${array_one[@]}" | sort) <(
            printf '%s\n' "${array_two[@]}" | sort)
        )

    echo "${diffset[*]}"
}

####################################################################
# Function to check if parentheses or quotes are balanced
# Returns 0 (true) if balanced, 1 (false) otherwise
function is_balanced {
    local str="$1"
    # Count double quotes
    local dq_count
    dq_count=$(grep -o '"' <<< "${str}" | wc -l)
    # Count single quotes
    local sq_count
    sq_count=$(grep -o "'" <<< "${str}" | wc -l)
    # Both must be even numbers
    (( dq_count % 2 == 0 )) && (( sq_count % 2 == 0 ))
}
####################################################################

# Function to check if parentheses or quotes are balanced
# Returns 0 (true) if balanced, 1 (false) otherwise

function validate_assignment {
        local line="$1"

        local debug=false
        varname=""; varvalue=""; vartype=""

        # 1. Check basic assignment structure (Key=Value)
        if [[ ! "${line}" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)=(.*)$ ]]; then
            if ${debug}; then echo "❌ Invalid Syntax: Not a valid assignment line."; fi
            return 1
        fi

        varname="${BASH_REMATCH[1]}"
        varvalue="${BASH_REMATCH[2]}"

        # --- CHECK A: Literal Array (Strict) ---
        if [[ "${varvalue}" =~ ^\(.*\)$ ]]; then
            # Strip the outer parentheses to check the inside
            # ${value:1:-1} removes first and last char
            local content="${varvalue:1:-1}"

            # Security Check 1: Reject Danger Characters
            # We reject: $ (variable/command sub), ` (backtick), ; (terminator), & (background), | (pipe)
            if [[ "${content}" =~ [\$\`\;\&\|] ]]; then
                if ${debug}; then echo "❌ Invalid Array: Contains unsafe characters (${varname})"; fi
                return 1
            fi

            # Security Check 2: Reject Unbalanced Quotes
            if ! is_balanced "${content}"; then
                 if ${debug}; then echo "❌ Invalid Array: Unbalanced quotes (${varname})"; fi
                 return 1
            fi

            if ${debug}; then echo "✅ Valid: Safe Literal Array (${varname})"; fi
            vartype="Array"
            return 0
        fi

        # --- CHECK B: Number (Integer or Float) ---
        if [[ "${varvalue}" =~ ^(\'|\")?[-+]?([0-9]*\.[0-9]+|[0-9]+)(\'|\")?$ ]]; then
            if ${debug}; then echo "✅ Valid: Number (${varname})"; fi
            vartype="Number"
            return 0
        fi

        # --- CHECK C: Bool (true or false) ---
        if [[ "${varvalue}" =~ ^(true|false)$ ]]; then
            if ${debug}; then echo "✅ Valid: Bool (${varname})"; fi
            vartype="Bool"
            return 0
        fi

        # --- CHECK D: String ---
        # Case 1: Strictly quoted (Start/End with " or ')
        if [[ "${varvalue}" =~ ^(\".*\"|\'.*\')$ ]]; then
            # Ensure the quotes inside aren't broken/unbalanced
            if ! is_balanced "${varvalue}"; then
                if ${debug}; then echo "❌ Invalid String: Unbalanced quotes (${varname})"; fi
                return 1
            fi
            if ${debug}; then echo "✅ Valid: Quoted String (${varname})"; fi
            vartype="String"
            return 0
        fi

        # Case 2: Safe unquoted string (No spaces, no special chars)
        if [[ "${varvalue}" =~ ^[a-zA-Z0-9_./-]+$ ]]; then
            if ${debug}; then echo "✅ Valid: Simple String (${varname})"; fi
            vartype="String"
            return 0
        fi

        if ${debug}; then echo "❌ Invalid Value: ${varvalue} - Does not match Number, Safe Array, or String."; fi
        return 1
}

# echo "--- VALID EXAMPLES ---"
# validate_assignment 'my_array=( 1 2 "three" )'   # Valid
# validate_assignment 'coords=(10.5 -20.1)'        # Valid
# validate_assignment 'empty_list=()'              # Valid
#
# echo -e "\n--- INVALID EXAMPLES ---"
# validate_assignment 'hack=( $(rm -rf /) )'       # Invalid (Contains $)
# validate_assignment 'bad=( "open quote )'        # Invalid (Unbalanced)
# validate_assignment 'inject=( a; ls )'           # Invalid (Contains ;)
# validate_assignment 'pipe=( a | grep b )'        # Invalid (Contains |)

########################################################################

#verbose=false

function readconf {
    if [[ $# -lt 2 ]]; then
        mecho0 "${RED}ERROR${NC}: Not enough arguments to function \"readconf\"."
        exit 1
    fi

    local configfile="$1"
    local sections
    sections=$(join_by \| "${@:2}")

    local readmode=false
    local line clean_part
    local varname varvalue vartype
    local color_key vartypestr
    local confvarname

    local debug=false       #${verbose:-false}

    declare -a read_sections=()
    declare -A type_colors=(["Number"]="GREEN" ["String"]="PURPLE" ["Array"]="RED" ["Bool"]="LIGHT_BLUE")

    if [[ ! -f "${configfile}" ]]; then
        mecho0 "${RED}ERROR${NC}: Configuration file '${configfile}' not found."
        exit 1
    fi

    # Use a cleaner while loop with parameter expansion instead of heavy regex where possible
    while IFS= read -r line || [[ -n "${line}" ]]; do
        # 1. Strip whitespace and ignore comments/empty lines
        line="${line#"${line%%[![:space:]]*}"}" # Leading trim
        line="${line%"${line##*[![:space:]]}"}" # Trailing trim

        [[ -z "${line}" || "${line}" == "#"* ]] && continue

        # 2. Section Detection
        if [[ "${line}" =~ ^\[(${sections})\]$ ]]; then
            readmode=true
            local sname="${BASH_REMATCH[1]}"
            if [[ ${debug} == true ]]; then
                mecho0 ""
                mecho0 "=== SECTION: ${YELLOW}${sname}${NC}"
            fi
            read_sections+=("${sname}")
            continue
        elif [[ "${line}" == "["*"]" ]]; then
            readmode=false
            continue
        fi

        # 3. Processing Logic
        if [[ "${readmode}" == true ]]; then
            # Remove inline comments
            line="${line%%# *}"

            # Split by semicolon for multi-statement lines
            IFS=';' read -ra STATEMENTS <<< "${line}"

            for part in "${STATEMENTS[@]}"; do
                # Trim the part
                clean_part="${part#"${part%%[![:space:]]*}"}"
                clean_part="${clean_part%"${clean_part##*[![:space:]]}"}"

                [[ -z "${clean_part}" ]] && continue

                if validate_assignment "${clean_part}"; then
                    if [[ ${debug} == true ]]; then
                        color_key=${type_colors[${vartype}]}
                        vartypestr=$(printf "%-6s" "${vartype}")
                        mecho0 "+++ (${!color_key}${vartypestr}${NC}): ${BROWN}${varname}${NC} = ${DARK}${varvalue}${NC}"
                    fi

                    confvarname="config_${varname}"
                    # Safety check for existing variables
                    [[ -v ${confvarname} ]] && mecho0 "*** WARNING *** Variable ${BROWN}${varname}${NC} changed: ${YELLOW}${!confvarname}${NC} -> ${WHITE}${varvalue}${NC}"

                    # Execute the assignment
                    eval "config_${clean_part}"
                else
                    mecho0 "${LIGHT_RED}ERROR${NC}: Invalid assignment in: ${WHITE}${clean_part}${NC}"
                    exit 1
                fi
            done
        fi
    done < "${configfile}"

    if [[ ${debug} == true ]]; then mecho0 ""; fi

    mecho0 "Successfully read sections: ${WHITE}${read_sections[*]}${NC}."
}

########################################################################

function get_parent_dir {
    local newndir=$1
    local n=$2

    for ((i=1; i<=n; i++)); do
        newndir=$(dirname ${newndir})
    done

    echo "${newndir}"
}

########################################################################

function wait_for_file_age {
    local file_name=$1
    local min_age=$2   # in seconds

    local file_path
    file_path=$(realpath ${file_name})

    if [[ ! -f ${file_path} ]]; then
        echo "File: ${file_path} not exists."
        return 1
    fi

    fileage=$(( $(date +%s) - $(stat -c %Y "${file_path}") ))
    while [[ ${fileage} -lt ${min_age} ]]; do
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
        echo "File: ${file_path} not exists."
        return 1
    fi

    filesize=$(stat -c %s ${file_path})
    while [[ ${filesize} -lt ${min_size} ]]; do
        #echo "Waiting for ${file_path} (size: $filesize bytes) ...."
        sleep 10
        filesize=$(stat -c %s ${file_path})
    done

    return 0
}

########################################################################

wait_for_conditions () {
    local conditions cond1 rcond1 cond2 rcond2
    read -r -a conditions <<< "$1"

    local myverbose=${verbose:-false}
    if [[ ${verb} -eq 1 ]]; then
        myverbose=true
    fi

    if [[ ${dorun} == true ]]; then
        for cond in "${conditions[@]}"; do
            if [[ "$cond" =~ (.+)"|"(.+) ]]; then
                cond1=${BASH_REMATCH[1]}; rcond1=$(realpath -m --relative-to "${WORKDIR}" "${cond1}")
                cond2=${BASH_REMATCH[2]}; rcond2=$(realpath -m --relative-to "${WORKDIR}" "${cond1}")
                mecho1n "Checking ${rcond1} or ${rcond2} ...."
                while [[ ! -e "${cond1}" && ! -e "${cond2}" ]]; do
                    [[ ${myverbose} == true ]] && mecho0 "\nWaiting for file: ${LIGHT_BLUE}${rcond1}${NC} or ${LIGHT_BLUE}${rcond2}${NC}"
                    sleep 10
                done
            else
                rcond1=$(realpath -m --relative-to "${WORKDIR}" "${cond}")
                mecho1n "Checking ${rcond1} ...."
                local i=0
                while [[ ! -e ${cond} ]]; do
                    if [[ ${myverbose} == true ]]; then
                        [[ $i -lt 1 ]] && echo ""
                        mecho0 "Waiting for file: ${rcond1}"
                        (( i+=1 ))
                    fi
                    sleep 10
                done
            fi
            echo " FOUND."
        done
    fi
}

########################################################################

function get_3char_order {
    local i=$1

    local alpha=( {A..Z} )

    local num=$((10#${i}))
    local i1=$((10#${num} % 26))
    local leftover=$((num/26))
    local i2=$((leftover % 26 ))
    local i3=$((leftover/26))

    if [[ ${i3} -ge 26 ]]; then
       mecho1 "RAN OUT OF 3-CHARACTER ORDER!"
       exit 1
    fi

    echo "${alpha[${i3}]}${alpha[${i2}]}${alpha[${i1}]}"
}

########################################################################

function num_pending_jobs_greater_than {

    #status_check="PD"       # number of PENDING jobs
    numcond="$1"            # greater than this number, return true

    #cmd=("squeue" "-o" "%.12i %.2t" "-u" "${USER}")
    #status_index=1
    #
    #if [[ ${verbose} == true ]]; then
    #    echo "${cmd[*]}"
    #fi
    #mapfile -t out < <( "${cmd[@]}" 2>&1 )
    #
    #jobnum=$(( ${#out[@]}-1 ))
    #
    #runnum=0
    #if [[ $jobnum -gt 0 ]]; then
    #    for lino in "${!out[@]}"; do
    #        line=${out[$lino]}
    #        #echo "${line}"
    #
    #        read -r -a words <<< "$line"
    #        if [[ ${lino} -gt 0 ]]; then
    #            status="${words[$status_index]}"
    #            if [[ "$status" == "${status_check}" ]]; then
    #                (( runnum+=1 ))
    #            fi
    #        fi
    #    done
    #fi

    runnum=$(squeue -u ${USER} -h -t pending -r | wc -l)

    [[ ${runnum} -gt ${numcond} ]]
}

########################################################################

function clean_mem_runfiles {

    local jobname=$1
    local mywrkdir=$2
    local nummem=$3                    # total number of jobs

    local mem memstr memdir donefile

    local myverbose=${verbose:-false}
    if [[ ${verb} -eq 1 ]]; then
        myverbose=true
    fi

    cd ${mywrkdir}  || return

    done=0
    for mem in $(seq 1 ${nummem}); do
        memstr=$(printf "%02d" ${mem})
        memdir="${jobname}_${memstr}"
        donefile="${memdir}/done.${jobname}_${memstr}"

        #echo $donefile, $memdir
        if [[ -e ${donefile} ]]; then
            if [[ ${myverbose} == true ]]; then
                mecho1 "${CYAN}${donefile}${NC} exist, delete ${BROWN}${memdir}${NC} & ${BROWN}${jobname}_${mem}_*.log${NC}."
            fi
            rm -rf ${memdir}
            rm -f  ${jobname}_${mem}_*.log
            (( done+=1 ))
        else
            if [[ ${myverbose} == true ]]; then
                mecho1 "${CYAN}${donefile}${NC} not found. Skip deleting ${BROWN}${memdir}${NC} & ${BROWN}${jobname}_${mem}_*.log${NC}."
            fi
        fi
    done

    if [[ ${done} -eq ${nummem} ]]; then
        rm -f queue.${jobname}
        touch done.${jobname}
    fi
}

########################################################################

function split_graph {

    local gpmetis=$1
    local graph_file=$2
    local numprocs=$3
    local rundir=$4
    local dorun=$5
    local verb=$6

    local myverbose=${verb:-false}
    if [[ ${verb} -eq 1 ]]; then
        myverbose=true
    fi

    local wrkdir
    wrkdir=$(pwd)

    IFS=$'/' read -r -a outdirs <<< "${rundir}"; unset IFS
    shortdir="${outdirs[-2]}/${outdirs[-1]}"

    cd "${rundir}" || exit $?

    if [[ ${myverbose} == true ]]; then
        mecho0 "Generating ${CYAN}${graph_file}.part.${numprocs}${NC} in ${BLUE}${shortdir}${NC} using ${GREEN}${gpmetis}${NC}"
    fi
    if command -v ${gpmetis} >/dev/null 2>&1; then
        ${gpmetis} -minconn -contig -niter=200 ${graph_file} ${numprocs} > gpmetis.out${numprocs}
        estatus=$?
        if [[ ${estatus} -ne 0 ]]; then
            mecho0 "${estatus}: ${gpmetis} -minconn -contig -niter=200 ${graph_file} ${numprocs}"
            exit "${estatus}"
        fi
    else
        mecho0 "${RED}ERROR${NC}: Command gpmetis=${BLUE}${gpmetis}${NC} not found."
        if [[ ${dorun} == true ]]; then exit 1; fi
    fi

    cd "${wrkdir}" || exit $?
}
########################################################################

function array_contains {
    declare -n array_ref="$1"
    local target="$2"

    local found=1

    for item in "${array_ref[@]}"; do
        if [[ "${item}" == "${target}" ]]; then
            found=0
            break
        fi
    done

    # If the array elements don't contain spaces, users can sometimes do a quick string check,
    # though it is less robust than a loop.
    #if [[ " ${array_ref[*]} " =~ " ${target} " ]]; then
    #    echo "Found using string matching"
    #fi
    return "${found}"
}

########################################################################

function array_keys_contains {
    # Declare and populate an associative array
    declare -m user_data="$1"

    local target_key="$2"

    local found=1
    # Check if the key exists
    if [[ -v user_data["${target_key}"] ]]; then
        #echo "Key '$target_key' exists!"
        found=0
    #else
        #echo "Key not found."
    fi

    return "${found}"
}

########################################################################

function sortnumarray {
    local IFS=$'\n'

    local sorted_numbers
    mapfile -t sorted_numbers < <(sort -n <<<"${*}")

    echo "${sorted_numbers[@]}"
}
#-----------------------------------------------------------------------
function sortnumarrayuniq {
    local unique_array
    readarray -t unique_array < <(printf "%s\n" "$@" | sort -n | uniq)
    echo "${unique_array[@]}"
}
#-----------------------------------------------------------------------
function nums2range {

    # condense a sorted number list into a comma separted string with single numbers or ranges of numbers

    local str
    local num first last inrange
    #echo $numbers, | sed "s/,/\n/g" | while read num; do
    #i=0
    for num in "$@"; do
        #(( i++ ))
        #echo "$i/$#: num = $num, first=$first, last=$last -> $str"
        if [[ -z ${first} ]]; then
            first=${num}
            last=${num}
            continue
        fi

        if [[ ${num} -ne $((last + 1)) ]]; then
            [[ ${first} -eq ${last} ]] && str+="${first}," || str+="${first}-${last},"
            first=${num}; last=${num}
            inrange=false
        else
            inrange=true
            ((last++))
        fi

    done
    # Handle the last item
    [[ ${inrange} == true ]] && str+="${first}-${num}" || str+="${first}"

    echo "${str%%,}"
}
#-----------------------------------------------------------------------
function expand_range {

    # To parse a string containing a list of numbers separated by commas, where ranges are indicated by a dash,
    # and expand it into a full list of numbers.

    local IFS=,         # Set Internal Field Separator to comma for splitting
    local numbers_list=""

    local start end
    for part in $1; do
        if [[ "${part}" =~ ^[0-9]+-[0-9]+$ ]]; then
            # Handle ranges (e.g., 1-5)
            start=$(echo "${part}" | cut -d'-' -f1)
            end=$(echo "${part}" | cut -d'-' -f2)
            for ((i=start; i<=end; i++)); do
                numbers_list+="${i} "
            done
        elif [[ "${part}" =~ ^[0-9]+$ ]]; then
            # Handle single numbers (e.g., 10)
            numbers_list+="${part} "
        fi
    done
    echo "${numbers_list}"
}

## Example usage:
#jobs1=(2 3 5 9 8 10 8 11 12 13 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36)
#jobs2=(2 6 9 12 13 16 18)
#jobs3=(3 7 10 11 14 15 17)
#
#numbers="18,19,62,161,162,163,165"
#
#read -ra sortlist <<<$(sortnumarray "${jobs1[@]}")
#jobs1_str=$(nums2range "${sortlist[@]}")
#expanded_str=$(expand_range "$jobs1_str")
#
#read -ra sortlistuniq <<<$(sortnumarrayuniq "${jobs1[@]}")
#
#echo "original list    : ${jobs1[*]}"
#echo "sorted list      : ${sortlist[*]}, ${#sortlist[@]}"
#echo "sorted list uniq : ${sortlistuniq[*]}, ${#sortlistuniq[@]}"
#echo "range str        : $jobs1_str"
#echo "expanded str     : $expanded_str"
#
##nums2range "${jobs2[@]}"
##nums2range "${jobs3[@]}"
#
##input_string="1-3,5,8-10,12"
##expanded_numbers=$(expand_range "$input_string")
##echo "Expanded numbers: $expanded_numbers"
##
### To store them in an array:
##IFS=" " read -r -a number_array <<< "$expanded_numbers"
##echo "Array elements:"
##for num in "${number_array[@]}"; do
##    echo "$num"
##done
########################################################################

# Arguments:
# $1: The prompt message
# $2...$n: The options
function select_option() {
    local msg="$1"
    shift
    local options=("$@")
    local selected=0

    # shellcheck disable=SC2155
    local ESC=$(printf '\033')
    local CURSOR_OFF="${ESC}[?25l"
    local CURSOR_ON="${ESC}[?25h"
    local CLEAR_LINE="${ESC}[2K"

    echo -ne "${CURSOR_OFF}"

    declare -A keyitems
    declare -a mykeys

    # --- Jump to character logic ---
    for i in "${!options[@]}"; do
        local item="${options[$i]}"
        # Strip the note to get just the value (e.g., "azure" from "azure:cloud")
        local val="${item%%:*}"

        local j=0
        local first_char="${val:$j:1}"          # Get the first character of the value
        local key="${first_char,,}"
        while [[ -v keyitems[${key}] ]]; do
            (( j += 1 ))
            first_char="${val:$j:1}"
            key="${first_char,,}"
        done

        mykeys[i]="$j"
        keyitems["${key}"]="$i"
    done

    function draw_menu() {
        # Move cursor up: (number of options + 1 for the prompt message)
        local num_options=${#options[@]}
        for ((i=0; i<=num_options; i++)); do echo -ne "${ESC}[A${CLEAR_LINE}\r"; done

        # Print the prompt message
        mecho2 "\033[1;37m${msg}\033[0m"

        for i in "${!options[@]}"; do
            local item="${options[${i}]}"
            local dval=""
            local note=""

            local j="${mykeys[$i]}"
            # Check if ":" exists to split into Value and Note
            if [[ "${item}" == *":"* ]]; then
                dval="${item%%:*}" # Everything before first ":"
                note=": ${item#*:}"      # Everything after first ":"
            else
                dval="${item}"
                note=""
            fi

            if [[ "${i}" -eq "${selected}" ]]; then
                # Selected: Green arrow and bright text
                echo -e "  \033[32m❯ ● ${dval:0:$j}${UNDERLINE}${dval:$j:1}${NC}\033[32m${dval:$((j+1))}\033[0m\033[90m${note}\033[0m"
            else
                # Unselected: Plain circle and dimmed note
                echo -e "    ○ ${dval:0:$j}${UNDERLINE}${dval:$j:1}${NC}${dval:$((j+1))}\033[90m${note}\033[0m"
            fi
        done
    }

    # Initial spacing
    for ((i=0; i<=${#options[@]}; i++)); do echo ""; done
    draw_menu

    while true; do
        #read -rsn3 key
        # Read 1 character. -t 0.001 checks if more chars are in the buffer immediately
        read -rsn1 key

        # If the key is the Escape character, try to read the next two
        if [[ "${key}" == "${ESC}" ]]; then
            read -rsn2 -t 0.001 rest
            key+="${rest}"
        fi

        case "${key}" in
            "${ESC}[A" | "${ESC}[D") # Up or Left
                ((selected--))
                [[ "${selected}" -lt 0 ]] && selected=$((${#options[@]} - 1))
                draw_menu
                ;;
            "${ESC}[B" | "${ESC}[C") # Down or Right
                ((selected++))
                [[ "${selected}" -ge ${#options[@]} ]] && selected=0
                draw_menu
                ;;
            "" | " ") # Enter
                break
                ;;
            * )
                # Compare (case-insensitive)
                if [[ -v keyitems[${key,,}] ]]; then
                    selected=${keyitems[${key,,}]}
                    draw_menu
                    break # Jump to the first match and stop searching
                else
                    continue
                fi
                ;;
        esac
    done

    echo -ne "${CURSOR_ON}"

    return "${selected}"
}

## --- Usage Example ---
#
## Mixture of simple strings and "Value:Note" strings
#my_options=(
#    "azure:Microsoft Cloud"
#    "aws:Amazon Web Services"
#    "digitalocean"
#    "local:On-premise runtime"
#)
#
## Use Command Substitution to capture the returned string
#result=$(select_option "Select your deployment target:" "${my_options[@]}")
#
#echo -e "\n\033[1;32mSelected Identifier:\033[0m ${result}"
