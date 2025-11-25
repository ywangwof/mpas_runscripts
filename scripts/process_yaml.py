#!/usr/bin/env python
import os
import sys
import re
import argparse

import yaml

from deepdiff import DeepDiff
from pprint import pprint

from typing import Callable

RED:    Callable[[str], str] = lambda text: f"\u001b[31m{text}\033\u001b[0m"
GREEN:  Callable[[str], str] = lambda text: f"\u001b[32m{text}\033\u001b[0m"
BROWN:  Callable[[str], str] = lambda text: f"\u001b[33m{text}\033\u001b[0m"
BLUE:   Callable[[str], str] = lambda text: f"\u001b[34m{text}\033\u001b[0m"
PURPLE: Callable[[str], str] = lambda text: f"\u001b[35m{text}\033\u001b[0m"
CYAN:   Callable[[str], str] = lambda text: f"\u001b[36m{text}\033\u001b[0m"

DARK:   Callable[[str], str] = lambda text: f"\u001b[1;30m{text}\033\u001b[0m"
YELLOW: Callable[[str], str] = lambda text: f"\u001b[1;33m{text}\033\u001b[0m"
WHITE:  Callable[[str], str] = lambda text: f"\u001b[1;37m{text}\033\u001b[0m"

########################################################################
#
# Load the dictionary into a Namespace data structure.
# This step is not necessary, but cuts down the syntax needed to reference each item in the dict.
#
# Example: Retrieve the 0 hr forecast Dataset from GFS Dynamics
#            dict: ds_dict['GFS']['dynf'][0]
#       Namespace: datasets.GFS.dynf[0]

def make_namespace(d: dict):
    assert(isinstance(d, dict))
    ns =  argparse.Namespace()
    for k, v in d.items():
        if isinstance(v, dict):
            leaf_ns = make_namespace(v)
            ns.__dict__[k] = leaf_ns
        else:
            ns.__dict__[k] = v

    return ns

########################################################################

def parse_args():
    parser = argparse.ArgumentParser(description='Processing YAML file',
                                     epilog='''        ---- Yunheng Wang (2025-08-29).
                                            ''')
                                     #formatter_class=CustomFormatter)

    parser.add_argument('yamlfiles', nargs='+', help='YAML file for input and output, the original file will be saved with ".orig" extension')

    parser.add_argument('-v','--verbose',      help='Verbose output',               action="store_true", default=False)
    parser.add_argument('-f','--favor',        help='Favor, either CADRE or RRFS',  type=str, default="RRFS")
    parser.add_argument('-o','--observations', help='Observations to be ketp',      type=str, default="t120,t133,q120,q133,uv220,uv233,refl10cm")
    parser.add_argument('-m','--members',      help='Number of background members', type=int, default=36)
    parser.add_argument('-k','--keys',         help='Key of the yaml structure',    type=str, default=None)
    parser.add_argument('-l','--list',         help='List the keys for this level, default: observations to List number of observation observers', type=str, default=None)
    parser.add_argument('-r','--rewrite',      help='Rewrite the YAML file',        action="store_true", default=False)

    args = parser.parse_args()

    for yamlfl in args.yamlfiles:
        if  not os.path.lexists(yamlfl):
            print(f"ERROR: Input file {yamlfl} not exist.")
            sys.exit(1)

    #
    # GETKF favor
    # RRFS: "Deterministic GETKF"
    # CADRE: "GETKF"
    #
    if args.favor in ("CADRE", "RRFS"):
        setattr(args, 'favor', args.favor)
    else:
        print(f"ERROR: Unknown favor = {args.favor}")
        sys.exit(1)

    #
    # Observation space to be kept
    #
    args.obs_spaces = args.observations.split(',')

    return args

########################################################################

def rewrite_obs(in_filename):
    #
    # find an available file name and backup the old yaml file
    #
    bak_filename=f'{in_filename}.orig'
    if os.path.exists(bak_filename):
        knt = 1
        yfile2 = f'{in_filename}_orig{knt:03}'
        while os.path.exists(yfile2):
            knt += 1
            yfile2 = f'{in_filename}_orig{knt:03}'

        for i in range(knt,1,-1):
            os.rename(f'{in_filename}_orig{i-1:03}',f'{in_filename}_orig{i:03}')
            if args.verbose:
                print(f"file {in_filename}_orig{i-1:03} saved as {in_filename}_orig{i:03}")

        os.rename(bak_filename,f'{in_filename}_orig001')
        if args.verbose:
            print(f"file {bak_filename}    saved as {in_filename}_orig001")

    if os.path.lexists(bak_filename):
        print(f"ERROR: {bak_filename} exist.")
        sys.exit(1)
    else:
        if args.verbose:
            print(f"Original file {in_filename} saved as {DARK(bak_filename)}")
        os.rename(in_filename, bak_filename)

    output_filename = in_filename
    if  os.path.lexists(output_filename):
        print(f"ERROR: Output file {output_filename} exist.")
        sys.exit(1)

    #print(args)

    obs_re="(.*)_(.*)"

    try:
        new_observers = []
        with open(bak_filename, 'r') as infile, open(output_filename,'w') as outfile:

            data = yaml.safe_load(infile)

            #
            # Keep assimilated observations only
            #
            if args.verbose:
                print(f"Observer number: {len(data['observations']['observers'])}",end=", ")

            #new_observations = data['observations']
            for obs in data['observations']['observers']:
                #print(obs['obs space']['name'],obs.keys())
                obsname  = obs['obs space']['name']
                rematched = re.match(obs_re,obsname)
                if rematched: obsname = rematched.group(2)

                if obsname in args.obs_spaces:
                    new_observers.append(obs)

            #new_observations['observers'] = new_observers
            data['observations']['observers'] = new_observers
            if args.verbose:
                print(f"kept: {len(data['observations']['observers'])}")

            #
            # Change data['local ensemble DA']['solver']
            #
            if args.favor == "RRFS":
                data['local ensemble DA']['solver'] = 'Deterministic GETKF'
            else:
                data['local ensemble DA']['solver'] = 'GETKF'

            if args.verbose:
                print(f"Set local ensemble DA -> solver to {CYAN(data['local ensemble DA']['solver'])} as favor = {PURPLE(args.favor)}")

            #
            # Set number of ensemble members
            #
            data['background']['members from template']['nmembers'] = args.members

            #
            # Dump the new YAML file
            #
            if args.verbose:
                print(f"Dumping to {output_filename} ...")
            yaml.dump(data, outfile, default_flow_style=False)         # default_flow_style=False for block style

    except FileNotFoundError:
        print(f"Error: {bak_filename} not found.")
    except yaml.YAMLError as exc:
        print(f"Error parsing YAML: {exc}")

########################################################################

def get_nested_value(data, keys, matched = False):
        """
        Retrieves a value from a nested dictionary using a list of keys.

        Args:
            data (dict): The nested dictionary.
            keys (list): A list of keys representing the path to the desired value.

        Returns:
            The value if found, None otherwise.
        """
        current_level = data

        if matched:
            found = False
            next_level = current_level
            for key in keys:
                keymatch = re.match(r'(.*)=(.*)',key)
                if keymatch:
                    newkey = keymatch.group(1)
                    newval = keymatch.group(2)
                    if args.verbose:
                        print(f"Searching {newkey} = {newval} from {next_level.keys()}")
                        print(f"{newkey}, {newval}, next_level = {next_level[newkey]}")
                    if isinstance(next_level, dict) and newkey in next_level and newval == next_level[newkey]:
                        found = True

                elif isinstance(next_level, dict) and key in next_level:
                    if args.verbose:
                        print(f"Searching {keys} from current_level[{key}] ....")
                    next_level = current_level[key]
                    #found = True

            if found:
                return current_level
            else:
                return None  # Key not found at this level or not a dictionary

        else:

            for key in keys:
                if isinstance(current_level, dict) and key in current_level:
                    current_level = current_level[key]
                elif isinstance(current_level, list):
                    kindex = keys.index(key)
                    newkeys = keys[kindex:]
                    if args.verbose:
                        print(f"Searching for {newkeys} from ROOT{keys[0:kindex]} ...")

                    for item in current_level:
                        newcurr = get_nested_value(item,newkeys,matched=True)
                        if newcurr is not None:
                            return newcurr
                        else:
                            continue
                else:
                    return None  # Key not found at this level or not a dictionary

        return current_level

########################################################################

def print_yaml(filename,**options):
    #
    # Load the contens separately from the input files
    #
    yamltop  = 'ROOT'
    yamlkeys = '[root]'

    try:
        with open(filename, 'r') as infile:
            data = yaml.safe_load(infile)

            if 'keys' in options.keys():
                data = get_nested_value(data,options['keys'])

                if data is None:
                    print(f"{options['keys']} is not in {filename}.")
                    return

                yamlkeys = "".join(map('["{}"]'.format, options['keys']))

    except FileNotFoundError:
        print(f"Error: {filename} not found.")
    except yaml.YAMLError as exc:
        print(f"Error parsing YAML: {exc}")

    #
    # Print the contents
    #
    print(f"\n{yamltop}{CYAN(yamlkeys)} in {PURPLE(filename)} \n")
    yaml.dump(data, sys.stdout, default_flow_style=False)
    print()
    #pprint(data,indent=2)

    #for key,item in data.items():
    #    print(f'{WHITE(key)}:')
    #    print(f'    {item}')

########################################################################

def compare_yaml(*files,**options):

    #
    # Load the contens separately from the input files
    #
    yamltop  = 'ROOT'
    yamlkeys = '[root]'
    try:
        with open(files[0], 'r') as infile1, open(files[1],'r') as infile2:
            data1 = yaml.safe_load(infile1)
            data2 = yaml.safe_load(infile2)

            if 'keys' in options.keys():
                data1 = get_nested_value(data1,options['keys'])

                if data1 is None:
                    print(f"{options['keys']} is not in {files[0]}.")
                    return

                data2 = get_nested_value(data2,options['keys'])

                if data2 is None:
                    print(f"{options['keys']} is not in {files[1]}.")
                    return
                yamlkeys = "".join(map('["{}"]'.format, options['keys']))

    except FileNotFoundError:
        print(f"Error: {files[0]} not found.")
    except yaml.YAMLError as exc:
        print(f"Error parsing YAML: {exc}")

    #
    # Do comparison
    #
    ddiff = DeepDiff(data1, data2)
    #print(type(ddiff))
    #pprint(ddiff,indent=2)

    print(f"\nDiff for: {yamltop}{CYAN(yamlkeys)}\n")
    for key,item in ddiff.items():
        print(f'{WHITE(key)}:', end=' ')
        if key.endswith('item_added'):
            print('[',end=' ')
            i=0
            for item1 in item:
                i += 1
                if i == len(item):
                    print(f'{GREEN(item1)}',end=' ')
                else:
                    print(f'{GREEN(item1)}',end=', ')
            print(']')
        elif key.endswith('item_removed'):
            print('[',end=' ')
            i=0
            for item1 in item:
                i+=1
                if i == len(item):
                    print(f'{RED(item1)}',end=' ')
                else:
                    print(f'{RED(item1)}',end=', ')
            print(']')
        elif key == 'values_changed':
            print('{', end='')
            for k1, item1 in item.items():
                print(f"                 {k1}", end=': ')
                print(f"{BROWN(item1['old_value'])} -> {YELLOW(item1['new_value'])}")
            print('                }\n')
        elif key == 'type_changes':
            print('{', end='')
            for k1, item1 in item.items():
                print(f"                 {k1}", end=': ')
                print(f"{BROWN(item1['old_type'])} -> {YELLOW(item1['new_type'])}, {BROWN(item1['old_value'])} -> {YELLOW(item1['new_value'])}")
            print('                }\n')
        else:
            print(f'{item}')

########################################################################

def list_observations(filename):

    #
    # Load the contens separately from the input files
    #
    try:
        with open(filename, 'r') as infile:
            data = yaml.safe_load(infile)

    except FileNotFoundError:
        print(f"Error: {infile} not found.")
    except yaml.YAMLError as exc:
        print(f"Error parsing YAML: {exc}")

    print(f"This file {CYAN(filename)} contains {len(data['observations']['observers'])} observers:")
    i = 0
    for obs in data['observations']['observers']:
        i += 1
        print(f"{i}: {obs['obs space']['name']}")


########################################################################

def key_list(filename,keynames):

    #
    # Load the contens separately from the input files
    #
    try:
        with open(filename, 'r') as infile:
            data = yaml.safe_load(infile)

    except FileNotFoundError:
        print(f"Error: {infile} not found.")
    except yaml.YAMLError as exc:
        print(f"Error parsing YAML: {exc}")

    if len(keynames) == 0 or keynames[0] == "0":
        print(f"This file {CYAN(filename)} contains {YELLOW(len(data))} keys")
        i = 0
        for key in data.keys():
            i += 1
            print(f"    {i}: {DARK(key)}")
    else:
        keydata = data
        for keyname in keynames:
            if keyname in keydata.keys():
                keydata = keydata[keyname]
                print(f"{PURPLE(keyname)}: contains {YELLOW(len(keydata))} members")
            else:
                print(f"This file {CYAN(filename)} does not contains {keyname}.")
                return
        for key in keydata.keys():
            print(f"    {DARK(key)}")


#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

if __name__ == "__main__":

    args = parse_args()

    kwargs = {}
    if args.keys is not None:
        kwargs['keys'] = args.keys.split(',')

    if args.list == "observations":
        list_observations(args.yamlfiles[0])
    elif args.list:
        key_list(args.yamlfiles[0],args.list.split(','))
    elif args.rewrite and len(args.yamlfiles) == 1:
        rewrite_obs(args.yamlfiles[0])
    elif len(args.yamlfiles) == 2:
        compare_yaml(*args.yamlfiles,**kwargs)
    else:
        print_yaml(args.yamlfiles[0],**kwargs)
