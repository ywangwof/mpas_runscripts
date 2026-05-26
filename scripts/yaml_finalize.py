#!/usr/bin/env python3
import os
import sys

# Append file directory to sys.path
from pathlib import Path

script_dir = str(Path(__file__).parent)
if script_dir not in sys.path:
    sys.path.append(script_dir)

import yamlfromrrfs as yf

import argparse

#########################################################################

def parse_arguments():
    """Parse command-line arguments."""

    parser = argparse.ArgumentParser(
        description="Finalize YAML configuration for JEDI"
    )

    parser.add_argument(
        "yfile",
        help="YAML file to process (getkf.yaml|hofx.yaml|test.yaml)"
    )
    parser.add_argument(
        "output",
        nargs="?",
        default=None,
        help="Output file name. If omitted, output is written to input file."
    )
    parser.add_argument(
        "-d", "--backup",
        action="store_true",
        help="Backup original YAML automatically. default: True (unless output file is specified)",
        default=None
    )
    parser.add_argument(
        "-t", "--getkf-type",
        default="observer",
        help="GETKF type (observer, solver, post, etc.). default: 'observer'."
    )
    parser.add_argument(
        "--use-conv-info",
        metavar="CONVINFO_FILE_OR_FALSE",
        default='./convinfo',
        help="Path to conventional observation info file, or 'False' to disable."
    )
    parser.add_argument(
        "--empty-obs-space-action",
        help="Action to take when observation space is empty. default: 'skip output'",
        default="skip output"
    )
    parser.add_argument(
        "--cwp-hail",
        help="Whether to add hail mixing ratio. default: 'false'",
        default='false'
    )

    parser.add_argument(
        "--analysis-date",
        required=True,
        help="Analysis date (e.g. 2024-05-14T00:00:00Z)."
    )
    parser.add_argument(
        "--begin-date",
        required=True,
        help="Begin date of the assimilation window."
    )
    parser.add_argument(
        "--len-win",
        required=True,
        help="Length of the assimilation window."
    )
    parser.add_argument(
        "--ensemble-number",
        type=int,
        default=36,
        help="Number of ensemble members. default: 36."
    )
    parser.add_argument(
        "--mp-state-vars",
        required=True,
        default="",
        help="Comma-separated list of MPAS microphysics state variables to replace #@MP_STATE_VARS@ & \"@MP_INCREMENT_VARS@\"."
    )

    args = parser.parse_args()

    # If output file is specified, don't backup by default
    if args.backup is None:
        args.backup = args.output is None

    # find an available file name to backup the old yaml file
    if args.backup or args.output is None:
        yfile_base= args.yfile.rsplit('.', 1)[0]

        knt = 1
        yfile2 = f'{yfile_base}_old{knt:03}.yaml'
        while os.path.exists(yfile2):
           knt += 1
           yfile2 = f'{yfile_base}_old{knt:03}.yaml'

        args.bakfile = yfile2

    # Check convinfo file for existence
    _conv_arg = args.use_conv_info
    if _conv_arg is None or _conv_arg.lower() in ("true", "1", "yes"):
        args.use_conv_info = True
        args.convinfo_file = './convinfo'
    elif _conv_arg.lower() in ("false", "0", "no"):
        args.use_conv_info = False
        args.convinfo_file = None
    else:
        args.convinfo_file = _conv_arg
        args.use_conv_info = True

    if args.use_conv_info:
        if not os.path.isfile(args.convinfo_file):
            sys.stderr.write(f"ERROR: convinfo file not found: {args.convinfo_file}\n")
            sys.exit(1)

    return args

########################################################################
def set_driver_per_task(data, task):

    driver_blocks = {
        "observer": '''
driver:
  run as observer only: true
  update obs config with geometry info: false

''',
        "solver": '''
driver:
  read HX from disk: true
  save posterior ensemble: true
  save prior mean: true
  save posterior mean: true
  do posterior observer: false

''',
        "post": '''
driver:
  run as observer only: true
  update obs config with geometry info: false
  read HX from disk: false
  do posterior observer: true

''',
    }

    block = yf.text_to_yblock(driver_blocks[task])
    yf.modify(data, "driver", block)

########################################################################

def set_yaml_value_in_group(data, group_key, var_key, value, search_window=20):
    """
    Set a variable's value within a named group in a YAML line list.

    Searches for a line containing var_key and verifies it belongs to the
    group identified by group_key (by looking backwards within search_window lines).

    Args:
        data:          List of YAML lines.
        group_key:     String identifying the parent group (e.g. "members from template:").
        var_key:       Variable key to update (e.g. "nmembers:").
        value:         New value to assign.
        search_window: How many lines to look back for the group_key.

    Returns:
        True if the value was updated, False if not found.
    """
    for i, line in enumerate(data):
        if var_key in line and i > 0:
            for j in range(i - 1, max(0, i - search_window), -1):
                if group_key in data[j]:
                    indent = len(line) - len(line.lstrip())
                    data[i] = " " * indent + f"{var_key} {value}"
                    return True
    return False

########################################################################

def replace_mp_placeholders(data, mp_state_vars):
    """
    Replace @MP_STATE_VARS@ and @MP_INCREMENT_VARS@ placeholders in YAML data.

    Args:
        data:                List of YAML lines.
        mp_state_vars:       Comma-separated string of state variables (or empty).
    """
    # Format state variables as YAML list items (one per line, with leading "  - ")
    if mp_state_vars:
        state_vars_list = mp_state_vars.split(",")
        state_vars_formatted = "\n".join([f"  - {var.strip()}" for var in state_vars_list])
    else:
        state_vars_formatted = ""

    # Replace #@MP_STATE_VARS@ with formatted state variables
    for i, line in enumerate(data):
        if "#@MP_STATE_VARS@" in line:
            if state_vars_formatted:
                data[i] = state_vars_formatted
            else:
                data[i] = ""

    # Replace "@MP_INCREMENT_VARS@" with increment variables (preserving surrounding context)
    for i, line in enumerate(data):
        if "@MP_INCREMENT_VARS@" in line:
            if mp_state_vars:
                # Replace only the placeholder, preserving quotes and surrounding text
                data[i] = line.replace("\"@MP_INCREMENT_VARS@\"", mp_state_vars)
            else:
                # Remove the placeholder if no variables provided
                data[i] = line.replace("\"@MP_INCREMENT_VARS@\", ", "")

########################################################################

def remove_variable_lines(data, keyword):
    """
    Remove all lines containing the specified keyword from YAML data.

    Args:
        data: List of YAML configuration lines
    """
    indices_to_remove = []
    for i, line in enumerate(data):
        if keyword in line:
            indices_to_remove.append(i)

    # Remove in reverse order to maintain correct indices
    for i in reversed(indices_to_remove):
        data.pop(i)

########################################################################

def add_diagnostic_filters_to_obs_spaces(data, dcObs):
    """
    Add 'Create Diagnostic Flags' and update Background Check filters to new format in all obs spaces.

    This function:
    - Adds Create Diagnostic Flags filter if not present
    - Updates Background Check filters from old format (action:) to new format (actions:)
    - Adds udescriptor: gross_error_check to Background Check filters

    Args:
        data: List of YAML configuration lines
        dcObs: Dictionary of observations from yt.get_all_obs()
    """
    import re

    for name, observer in dcObs.items():
        sname = observer["sname"]
        pos1, pos2 = observer["pos1"], observer["pos2"]

        # Search for the actual "name: <sname>" line starting from pos1
        # Try exact match first, then substring match
        actual_obs_start = -1
        for i in range(pos1, pos2):
            if i < len(data) and f"name: {sname}" in data[i]:
                actual_obs_start = i
                break

        # If not found, try substring match (sname might be part of a longer name)
        if actual_obs_start == -1:
            for i in range(pos1, pos2):
                if i < len(data) and "name:" in data[i] and sname in data[i]:
                    actual_obs_start = i
                    break

        # If still not found in expected range, search backwards and forwards
        if actual_obs_start == -1:
            for i in range(pos1 - 1, max(0, pos1 - 50), -1):
                if f"name: {sname}" in data[i]:
                    actual_obs_start = i
                    break

        if actual_obs_start == -1:
            for i in range(pos1 - 1, max(0, pos1 - 50), -1):
                if "name:" in data[i] and sname in data[i]:
                    actual_obs_start = i
                    break

        if actual_obs_start == -1:
            for i in range(pos2, min(len(data), pos2 + 50)):
                if f"name: {sname}" in data[i]:
                    actual_obs_start = i
                    break

        if actual_obs_start == -1:
            for i in range(pos2, min(len(data), pos2 + 50)):
                if "name:" in data[i] and sname in data[i]:
                    actual_obs_start = i
                    break

        if actual_obs_start == -1:
            sys.stderr.write(f"ERROR: Could not find obs space '{sname}' in data\n")
            sys.exit(1)

        # Find the actual end of this obs space dynamically (stale pos2 is unreliable
        # because previous iterations may have inserted lines into data)
        actual_obs_end = len(data)
        for i in range(actual_obs_start + 1, len(data)):
            if ("- obs space:" in data[i] or "obs space:" in data[i]) and i > actual_obs_start + 5:
                # Make sure this is really a new obs space (not just "obs space:" as a field name)
                if data[i].strip().startswith("- obs space:") or (data[i].strip().startswith("obs space:") and data[i-1].strip().startswith("-")):
                    actual_obs_end = i
                    break

        # Extract obs space block using dynamic boundaries
        obs_block = data[actual_obs_start:actual_obs_end]

        # Check if "obs filters:" exists in this obs space
        filters_idx = -1
        for i, line in enumerate(obs_block):
            if "obs filters:" in line:
                filters_idx = i
                break

        if filters_idx >= 0:
            # Check if diagnostic flags already exist
            has_diagnostic_flags = any(
                "Create Diagnostic Flags" in line
                for line in obs_block[filters_idx:]
            )

            # Add diagnostic flags if not present
            if not has_diagnostic_flags:
                # Extract simulated variables from this obs space
                simulated_vars = []

                for i in range(filters_idx):
                    if "simulated variables:" in obs_block[i]:
                        line = obs_block[i]

                        # Handle inline format: simulated variables: [var1, var2]
                        if "[" in line and "]" in line:
                            match = re.search(r'\[(.*?)\]', line)
                            if match:
                                vars_str = match.group(1)
                                simulated_vars = [v.strip() for v in vars_str.split(",")]
                        else:
                            # Handle multi-line format
                            j = i + 1
                            while j < len(obs_block) and obs_block[j].strip().startswith("-"):
                                var = obs_block[j].strip()[1:].strip()
                                simulated_vars.append(var)
                                j += 1
                        break

                # Build the filter variables section
                if simulated_vars:
                    filter_vars_str = "          filter variables:\n"
                    for var in simulated_vars:
                        filter_vars_str += f"          - name: {var}\n"
                else:
                    sys.stderr.write(f"WARNING: No simulated variables found for obs space '{sname}'.\n")
                    sys.exit(1)

                # Define the complete diagnostic filters to add
                diagnostic_filters_str = f'''        # Step 1: define diagnostic flags
        - filter: Create Diagnostic Flags
          flags:
          - name: gross_error_check
            initial value: false
'''

                # Insert diagnostic filters after the "obs filters:" line
                diag_block = yf.text_to_yblock(diagnostic_filters_str)
                insertion_point = actual_obs_start + filters_idx + 1
                data[insertion_point:insertion_point] = diag_block

                # Recalculate actual_obs_end after insertion
                actual_obs_end += len(diag_block)

            # Now handle Background Check filters - update old format to new format
            # and add udescriptor if not present
            for i in range(actual_obs_start, actual_obs_end):
                if i >= len(data):
                    break
                if "- filter: Background Check" in data[i]:
                    abs_bg_check_idx = i

                    # Check if udescriptor exists
                    has_udescriptor = False
                    for j in range(abs_bg_check_idx, min(abs_bg_check_idx + 15, len(data))):
                        if "udescriptor:" in data[j]:
                            has_udescriptor = True
                            break

                    # Add udescriptor if missing
                    if not has_udescriptor:
                        # Find where to insert it (after "filter: Background Check" line)
                        insert_pos = abs_bg_check_idx + 1
                        data.insert(insert_pos, "          udescriptor: gross_error_check")

                    # Check if old format "action:" exists (without plural "actions:")
                    action_idx = -1
                    for j in range(abs_bg_check_idx, min(abs_bg_check_idx + 20, len(data))):
                        line = data[j]
                        # Look for "action:" but not "actions:"
                        if re.search(r'^\s+action:\s*$', line):
                            # Verify next line has "name: reject"
                            if j + 1 < len(data) and "name: reject" in data[j + 1]:
                                action_idx = j
                                break

                    # Update old format to new format
                    if action_idx >= 0:
                        action_lines = [
                            "          actions:",
                            "          - name: set",
                            "            flag: gross_error_check",
                            "            ignore: rejected observations",
                            "          - name: reject"
                        ]

                        # Remove old "action:" and "- name: reject" lines
                        del data[action_idx:action_idx + 2]

                        # Insert new actions block
                        for idx, line in enumerate(action_lines):
                            data.insert(action_idx + idx, line)

########################################################################

def strim_convinfo(data, convinfo_file, task):
    """
    Remove obs spaces from YAML data that are not listed in the convinfo file.

    Args:
        data: List of YAML lines.
        convinfo_file: Path to convinfo file containing valid obs space names.

    Returns:
        List of YAML lines with only the obs spaces listed in the convinfo file.
    """

    dcConvInfo = yf.load_convinfo(convinfo_file)
    head_end, _ = yf.get_start_pos(data, "observations/observers")
    output = data[0:head_end + 1]

    dcObs = yf.get_all_obs(data, shallow=True)
    for name, observer in dcObs.items():
        # skip sfcshp temporarily since they are not in convinfo and not used in solver
        if name.startswith("sfcshp"): continue

        sname = observer["sname"]
        tmp = data[observer["pos1"]:observer["pos2"]]

        # tweak observers for solver or post:
        #  1. if solver, change the distribution from RoundRobin to Halo
        #  2. transfer the obsdataout obsfile to obsdatain
        #  3. if post, remove the "reduce obs space" actions and "temporal thinning" filters
        if task == "solver" or task == "post":
            yf.getkf_observer_tweak(tmp, task)

        # Check against convinfo
        for iname, info in dcConvInfo.items():
            if iname == sname:
                if info['iuse'] != "0": # Only include if not suppressed
                    if info['iuse'] == "-1": # Passivate if monitor-only
                        for i in range(len(tmp)):
                            if "obs filters:" in tmp[i]:
                                spaces = " " * (yf.strip_indentations(tmp[i])[0] + 2)
                                passivate = [f"{spaces}- filter: Perform Action",
                                             f"{spaces}  action:",
                                             f"{spaces}    name: passivate", ""]
                                tmp[i+1:i+1] = passivate
                                break
                    output.extend(tmp)
                break

    return output

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

if __name__ == "__main__":
    # 1. Argument Parsing
    parsed_args = parse_arguments()

    task_type = parsed_args.getkf_type

    # 1.2 Get Environmental Variables
    replacements = {
        "analysisDate":         parsed_args.analysis_date,
        "beginDate":            parsed_args.begin_date,
        "lenWin":               parsed_args.len_win,
        "emptyObsSpaceAction":  parsed_args.empty_obs_space_action,
    }

    # 2. Load and Replace Patterns
    data = yf.load(parsed_args.yfile, replacements)
    replace_mp_placeholders(data, parsed_args.mp_state_vars)

    # 3. Specific driver section modifications based on task_type
    set_driver_per_task(data, task_type)

    if task_type == "solver" or task_type == "post":
        set_yaml_value_in_group(data, "output:", "filename:", "./ana/mem%{member}%.nc")
        set_yaml_value_in_group(data, "geometry:", "iterator dimension:", 3)
    else:
        set_yaml_value_in_group(data, "geometry:", "iterator dimension:", 2)

    if task_type == "post":
        background_filename = "./ana/mem%iMember%.nc"
    else:
        background_filename = "./ens/mem%iMember%.nc"

    # Set ensemble number (only modify nmembers, keep other variables intact)
    #set_yaml_value_in_group(data, "local ensemble DA:", "solver:", "Deterministic LETKF")
    set_yaml_value_in_group(data, "members from template:", "nmembers:", parsed_args.ensemble_number)
    set_yaml_value_in_group(data, "members from template:", "filename:", background_filename)
    set_yaml_value_in_group(data, "obs operator:", "add hail mixing ratio:", parsed_args.cwp_hail.lower(),search_window=5)

    # 4.1 Conventional Observation Processing
    if parsed_args.use_conv_info:
        output = strim_convinfo(data, parsed_args.convinfo_file, task_type)
    else:
        output = data

    # 4.2 Add Diagnostic Filters to all obs spaces (observer only)
    if task_type == "observer":
        dcObs_all = yf.get_all_obs(output, shallow=True)
        add_diagnostic_filters_to_obs_spaces(output, dcObs_all)

    if task_type == "observer" or task_type == "post":
        remove_variable_lines(output, "halo size:")

    # Remove lines containing "apply at iterations:"
    # the standard LETKF (Local Ensemble Kalman Filter) is typically a single-step solver
    remove_variable_lines(output, "apply at iterations:")

    # 5. Output Management
    output_path = parsed_args.output if parsed_args.output else parsed_args.yfile

    if parsed_args.backup:
        os.replace(parsed_args.yfile, parsed_args.bakfile)
        print(f"INFO: Original YAML backed up as {parsed_args.bakfile}")

    yf.dump(output, fpath=output_path)
    print(f"written YAML to file: {output_path}")

    sys.exit(0)
