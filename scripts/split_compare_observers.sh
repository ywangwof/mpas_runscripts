#!/usr/bin/env bash
scpdir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
#rootdir=$(realpath "$(dirname "${scpdir}")")

# shellcheck source=/dev/null
source "${scpdir}"/Common_Utilfuncs.sh || exit $?

######################################################################

function usage {
    echo " "
    echo "    USAGE: $0 [options] <file1.yaml> [file2.yaml] [dirnames]"
    echo " "
    echo "    PURPOSE: To split the 'observations.observers' list into separate files "
    echo "             based on the name tag within the 'obs space' section."
    echo ""
    echo "    REQUIRED: yq - v4 or above;       "
    echo "              meld, xdiff or yamldiff "
    echo " "
    echo "    OPTIONS:"
    echo "              -h                  Display this message"
    echo "              -n                  Show command to be run and generate job scripts only"
    echo "              -v                  Verbose mode"
    echo "              -s                  Split the passing in yaml file <file1.yaml> into the output directory <dirname>."
    echo "              -j                  Join the split yaml files in <dirname>  into a new file <file2.yaml> "
    echo "                                  by referring the heads and the order of observers in <file1.yaml>."
    echo "              -c                  Compare the split yaml files from two files <file1.yaml> and <file2.yaml>."
    echo "              -d                  Compare the split yaml files in two directory names <dirnames>,"
    echo "                                  the first one is the reference and the second one is the target."
    echo " "
    echo "                                     -- By Y. Wang (2026.04.13)"
    echo " "
    exit "$1"
}

########################################################################

function parse_args {

    declare -Ag args

    #-------------------------------------------------------------------
    # Parse command line arguments
    #-------------------------------------------------------------------

    while [[ $# -gt 0 ]]; do
        key="$1"

        case "${key}" in
            -h)
                usage 0
                ;;
            -n)
                args["dorun"]=false
                ;;
            -v)
                args["verbose"]=true
                ;;
            -s)
                args["task"]="split"
                ;;
            -j)
                args["task"]="join"
                ;;
            -c)
                args["task"]="split_compare"
                ;;
            -d)
                args["task"]="compare"
                ;;
            -*)
                mecho0 "${RED}ERROR${NC}: Unknown option: ${PURPLE}${key}${NC}"
                usage 2
                ;;
            *)
                if [[ -f "${key}" ]]; then
                    args["files"]="${args["files"]} ${key}"
                elif [[ "${key}" =~ ^.*\.yaml$ ]]; then        # yaml file but not exist
                    args["files"]="${args["files"]} ${key}"    # assume you want to create the file
                    args["task"]="join"
                else
                    args["dirnames"]="${args["dirnames"]} ${key}"
                fi
                ;;
        esac
        shift # past argument or value
    done
}

######################################################################

split_observers() {
    local INPUT_FILE="$1"
    local OUTPUT_DIR="${2:-.}"

    if [[ -z "${INPUT_FILE}" ]] || [[ ! -f "${INPUT_FILE}" ]]; then
        echo "Error: Invalid input file."
        return 1
    fi

    mkdir -p "${OUTPUT_DIR}"
    export S="obs space"

    local num_observers
    num_observers=$(yq '.observations.observers | length' "${INPUT_FILE}")

    echo "Found ${num_observers} observers in ${INPUT_FILE}. Splitting into ${OUTPUT_DIR} ..."

    for ((i=0; i < num_observers; i++)); do
        export i

        local obs_name
        obs_name=$(yq '.observations.observers.[env(i)].[env(S)].name' "${INPUT_FILE}")

        if [[ "${obs_name}" == "null" || -z "${obs_name}" ]]; then
            obs_name=$(yq ".observations.observers.[env(i)].[env(S)]" "${INPUT_FILE}" | head -n 1 | tr -d ' :')
        fi

        if [[ -z "${obs_name}" || "${obs_name}" == "null" ]]; then
            obs_name="observer_${i}"
        fi

        local start_line end_line
        start_line=$(yq ".observations.observers.[env(i)] | line" "${INPUT_FILE}")

        if (( i + 1 < num_observers )); then
            export next_i=$((i + 1))
            local next_start
            next_start=$(yq ".observations.observers.[env(next_i)] | line" "${INPUT_FILE}")
            end_line=$((next_start - 1))
        else
            end_line=$(wc -l < "${INPUT_FILE}")
        fi

        local output_file="${OUTPUT_DIR}/${obs_name}.yaml"

        if [[ "${start_line}" =~ ^[0-9]+$ ]]; then
            sed -n "${start_line},${end_line}p" "${INPUT_FILE}" > "${output_file}"

            # FIX: Only replace the first occurrence of '- ' with '  '
            # This keeps the horizontal position of the text identical.
            if [[ "${OSTYPE}" == "darwin"* ]]; then
                sed -i '' '1s/    - /      /' "${output_file}"
            else
                sed -i '1s/    - /       /' "${output_file}"
            fi

            if [[ ${args["verbose"]} == true ]]; then
                echo "Created: $output_file (Lines $start_line-$end_line)"
            fi
        else
            echo "Error: Failed to find lines for index $i: ${obs_name}"
        fi
    done
}

# Example usage:
# split_observers "getkf_solver.yaml" "./parts"

########################################################################

join_observers() {
    local INPUT_DIR="$1"
    local OUTPUT_FILE="$2"
    local REFERENCE_FILE="$3"

    if [[ -z "${INPUT_DIR}" || -z "${OUTPUT_FILE}" || -z "${REFERENCE_FILE}" ]]; then
        echo "Usage: join_observers <split_dir> <output_file> <reference_file>"
        return 1
    fi

    local first_obs_line
    first_obs_line=$(yq '.observations.observers[0] | line' "${REFERENCE_FILE}")

    if [[ -z "${first_obs_line}" ]]; then
        echo "Error: Could not find observers list in ${REFERENCE_FILE}"
        return 1
    fi

    local header_end=$((first_obs_line - 1))
    sed -n "1,${header_end}p" "${REFERENCE_FILE}" > "${OUTPUT_FILE}"

    local num_observers
    num_observers=$(yq '.observations.observers | length' "${REFERENCE_FILE}")
    export S="obs space"

    echo -e "Incorporating ${PURPLE}${num_observers}${NC} observers in ${LIGHT_BLUE}${INPUT_DIR}${NC} to ${CYAN}${OUTPUT_FILE}${NC} ..."

    for ((i=0; i < num_observers; i++)); do
        export i
        local obs_name
        obs_name=$(yq '.observations.observers.[env(i)].[env(S)].name' "${REFERENCE_FILE}")

        if [[ "${obs_name}" == "null" || -z "${obs_name}" ]]; then
            obs_name=$(yq ".observations.observers.[env(i)].[env(S)]" "${REFERENCE_FILE}" | head -n 1 | tr -d ' :')
        fi

        if [[ -z "${obs_name}" || "${obs_name}" == "null" ]]; then
            obs_name="observer_${i}"
        fi

        local file_path="${INPUT_DIR}/${obs_name}.yaml"

        if [[ -f "${file_path}" ]]; then
            # FIX: Find the first occurrence of two spaces and turn them back into '- '
            # This perfectly restores the indentation level of the list marker.
            if [[ ${args["verbose"]} == true ]]; then
                echo "Appending ${i}: ${file_path} to ${OUTPUT_FILE}"
            fi
            sed '1s/      /    - /' "${file_path}" >> "${OUTPUT_FILE}"
        else
            echo "Warning: ${obs_name} missing from ${INPUT_DIR}"
        fi
    done

    echo "Created: ${OUTPUT_FILE}"
}

# Example usage:
# join_observers "./tmp_split_1" "reconstructed.yaml" "getkf_solver.yaml"

########################################################################

compare_observers() {

    # Compare yaml files from two directories

    local TEMP_DIR1="$1"       # Reference
    local TEMP_DIR2="$2"       # Target

    local ALL_FILES PATH1 PATH2

    local cmp_abort cmp_command
    cmp_abort=false

    local compare_options=(
         "code:        Use ${BROWN}code --diff${NC} to compare the files"
         "meld:        Use ${BROWN}meld${NC} to compare the files"
         "xxdiff:      Use ${BROWN}xxdiff${NC} to compare the files"
         "yamldiff:    Use ${BROWN}yamldiff${NC} to compare the files"
         "delete:      Remove the file in ${LIGHT_BLUE}${TEMP_DIR2}${NC}"
         "skip:        Skip this file and continue"
         "abort:       Exit the comparison"
    )

    # Get a unique list of all split filenames from both directories
    ALL_FILES=$(find "$TEMP_DIR1" "$TEMP_DIR2" -name "*.yaml" -exec basename {} \; | sort -u)

    for filename in $ALL_FILES; do
        PATH1="$TEMP_DIR1/$filename"
        PATH2="$TEMP_DIR2/$filename"

        cmp_command=()
        if [[ -f "${PATH1}" && -f "${PATH2}" ]]; then

            if diff -q "${PATH1}" "${PATH2}" >& /dev/null; then
                echo -e "${GREEN}INFO${NC}: File '${filename}' in ${LIGHT_BLUE}${TEMP_DIR2}${NC} is the same as that in ${PURPLE}${TEMP_DIR1}${NC}."
                continue
            else

                if [[ -f "${TEMP_DIR2}/.done.${filename}.merged" ]]; then
                    echo -e "${DARK}INFO${NC}: difference of file '${filename}' in ${LIGHT_BLUE}${TEMP_DIR2}${NC} is already resolved."
                    continue
                fi

                if [[ ${cmp_abort} == true ]]; then
                    echo -e "${BROWN}INFO${NC}: File '${filename}' is different between ${LIGHT_BLUE}${TEMP_DIR2}${NC} and ${PURPLE}${TEMP_DIR1}${NC}."
                    continue
                fi


                select_option "Comparing: ${CYAN}${filename}${NC}? " "${compare_options[@]}"
                selected=$?; result="${compare_options[${selected}]}"; result="${result%%:*}"
                case "${result}" in
                    meld)
                        cmp_command=("meld")
                        ;;
                    code)
                        cmp_command=("/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" "--diff" "--wait")
                        ;;
                    xxdiff)
                        cmp_command=("xxdiff")
                        ;;
                    yamldiff)
                        cmp_command=("yamldiff")
                        ;;
                    delete)
                        rm -i "${PATH2}"
                        continue
                        ;;
                    skip)
                        continue
                        ;;
                    abort)
                        cmp_abort=true
                        continue
                        ;;
                    * )
                        echo -e "${RED}ERROR${NC}: result = ${result}"
                        usage 1
                        ;;
                esac
            fi

        elif [[ -f "${PATH1}" ]]; then
            echo -e "${YELLOW}WARN${NC}: '${filename}' exists in ${PURPLE}${TEMP_DIR1}${NC} but NOT in ${DARK}${TEMP_DIR2}${NC}"
        else
            echo -e "${YELLOW}WARN${NC}: '${filename}' not exists in ${DARK}${TEMP_DIR1}${NC} but exist in ${GREEN}${TEMP_DIR2}${NC}"
        fi

        if [[ "${#cmp_command[@]}" -gt 0 ]]; then
            if "${cmp_command[@]}" "${PATH1}" "${PATH2}"; then
                touch "${TEMP_DIR2}/.done.${filename}.merged"
            fi
        fi
    done
}

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

# To test the funcstions

## Split the file
#split_observers "getkf_solver.yaml" "./parts"
#
## Join it back
#join_observers "./parts" "new_getkf.yaml" "getkf_solver.yaml"
#
## Verify exact match
#diff getkf_solver.yaml new_getkf.yaml
#if [[ $? -eq 0 ]]; then
#    echo "SUCCESS: Reassembled file is identical to the original."
#else
#    echo "FAILURE: Differences detected."
#fi

## --- Main Logic ---
#
parse_args "$@"

[[ -v args["verbose"] ]] && verbose=${args["verbose"]} || verbose=false
[[ -v args["dorun"] ]]   && dorun=${args["dorun"]}     || dorun=true

[[ -v args["task"] ]]    && task=${args["task"]}

read -r -a files <<< "${args['files']}"
read -r -a dirs <<< "${args['dirnames']}"

if [[ -v args["task"] ]]; then
    task=${args["task"]}
else
    if [[ ${#files[@]} -eq 2 || ${#dirs[@]} -eq 2 ]]; then
        task="compare"
    elif [[ ${#files[@]} -eq 1 && ${#dirs[@]} -eq 1 ]]; then
        task="split"
    else
        echo -e "${RED}ERROR${NC}: No valid number of arguments."
        usage 1
    fi
fi

#wof_observers=(
#    refl10cm.yaml
#    rw.yaml
#    cwp.yaml
#    cwp_night.yaml
#    lwp.yaml
#    iwp.yaml
#    adpsfc_t181.yaml
#    adpsfc_t183.yaml
#    adpsfc_t187.yaml
#    adpsfc_q181.yaml
#    adpsfc_q183.yaml
#    adpsfc_q187.yaml
#    adpsfc_ps181.yaml
#    adpsfc_ps187.yaml
#    adpsfc_uv281.yaml
#    adpsfc_uv284.yaml
#    adpsfc_uv287.yaml
#    adpupa_t120.yaml
#    adpupa_t132.yaml
#    adpupa_q120.yaml
#    adpupa_q132.yaml
#    adpupa_ps120.yaml
#    adpupa_uv220.yaml
#    adpupa_uv232.yaml
#    aircar_t133.yaml
#    aircar_q133.yaml
#    aircar_uv233.yaml
#    aircft_t130.yaml
#    aircft_t131.yaml
#    aircft_t134.yaml
#    aircft_t135.yaml
#    aircft_q134.yaml
#    aircft_uv230.yaml
#    aircft_uv231.yaml
#    aircft_uv234.yaml
#    aircft_uv235.yaml
#    msonet_t188.yaml
#    msonet_q188.yaml
#    msonet_ps188.yaml
#    msonet_uv288.yaml
#    proflr_uv227.yaml
#    rassda_t126.yaml
#    sfcshp_t180.yaml
#    sfcshp_t182.yaml
#    sfcshp_t183.yaml
#    sfcshp_q180.yaml
#    sfcshp_q182.yaml
#    sfcshp_q183.yaml
#    sfcshp_ps180.yaml
#    sfcshp_uv280.yaml
#    sfcshp_uv282.yaml
#    sfcshp_uv284.yaml
#    vadwnd_uv224.yaml
#)

case "${task}" in
    split)
        if [[ ${#dirs[@]} -lt 1 ]]; then
            echo -e "${RED}ERROR${NC}: output directory is not specified."
            usage 1
        fi

        if [[ ${#files} -lt 1 ]]; then
            echo -e "${RED}ERROR${NC}: input file is not specified."
            usage 1
        fi

        split_observers "${files[0]}" "${dirs[0]}"
        ;;
    join)
        if [[ ${#dirs[@]} -lt 1 ]]; then
            echo -e "${RED}ERROR${NC}: input directory is not specified."
            usage 1
        fi

        if [[ ${#files[@]} -lt 2 ]]; then
            echo -e "${RED}ERROR${NC}: Will need two yaml files for task=${task}."
            usage 1
        fi

        join_observers "${dirs[0]}" "${files[1]}" "${files[0]}"
        ;;
    split_compare)
        if [[ ${#files[@]} -lt 2 ]]; then
            echo -e "${RED}ERROR${NC}: Will need two yaml file for task=${task}."
            usage 1
        fi

        FILE1="${files[0]}"
        FILE2="${files[1]}"
        #
        ## Create unique temporary directories in CWD
        [[ -v dirs[0] ]] && TEMP_DIR1="${dirs[0]}" || TEMP_DIR1=$(mktemp -d -t split1_XXXX)
        [[ -v dirs[1] ]] && TEMP_DIR2="${dirs[1]}" || TEMP_DIR2=$(mktemp -d -t split2_XXXX)

        # Set a trap to remove the directory on exit (success or failure)
        [[ ! -v dirs[0] ]] && trap 'rm -rf "${TEMP_DIR1}"' EXIT
        [[ ! -v dirs[1] ]] && trap 'rm -rf "${TEMP_DIR2}"' EXIT


        echo "Splitting ${FILE1}..."
        split_observers "${FILE1}" "${TEMP_DIR1}"

        echo "Splitting ${FILE2}..."
        split_observers "${FILE2}" "${TEMP_DIR2}"

        compare_observers "${TEMP_DIR1}" "${TEMP_DIR2}"
        ;;
    compare )
        if [[ ${#dirs[@]} -lt 2 ]]; then
            echo -e "${RED}ERROR${NC}: Need two input directory names to compare."
            usage 1
        fi
        ## Create unique temporary directories in CWD
        TEMP_DIR1="${dirs[0]}"
        TEMP_DIR2="${dirs[1]}"

        compare_observers "${TEMP_DIR1}" "${TEMP_DIR2}"
        ;;
    *)
        echo -e "${RED}ERROR${NC}: Unknown task: ${PURPLE}${task}${NC}"
        usage 1
        ;;
esac
