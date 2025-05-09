#!/usr/bin/env python3

import json
import os
import sys
import copy

if __name__ == "__main__":
    infile  = sys.argv[1]
    outfile = sys.argv[2]
    if len(sys.argv) == 4:
        dirname = sys.argv[3]
    else:
        dirname = os.path.dirname(outfile)
        if dirname == "":
            dirname = os.getcwd()

    print(f"infile={infile}")
    print(f"outfile={outfile}")
    print(f"Image directory = {dirname}")

    with open(infile, 'r') as openfile:
        # Reading from json file
        json_object = json.load(openfile)

    #print (json_object["fields"]["Obs-Space"]["Diagnostics"].keys())
    #rms_dicts = json_object["fields"]["Obs-Space"]["Diagnostics"]["RMS plots"]
    #csr_dicts = json_object["fields"]["Obs-Space"]["Diagnostics"]['Consistency Ratio']
    #num_dicts = json_object["fields"]["Obs-Space"]["Diagnostics"]['Number of Obs.']
    #print(rms_dicts["Doppler Rad. Vel"])

    obj_names = { "rms"   : "RMS plots",
                  "ratio" : 'Consistency Ratio',
                  "number": 'Number of Obs.'
                }

    template_obj = {
        "productFile": "TEMPLATE",
        "units": "minutes",
        "productType": "diag",
        "times_available": "times_6h"
    }

    for prefix in ["rms","ratio", "number"]:
        json_object["fields"]["Obs-Space"]["Diagnostics"][obj_names[prefix]] = {}

    directory = os.fsencode(dirname)

    for file in sorted(os.listdir(directory)):
        filename = os.fsdecode(file)
        for prefix in ["rms","ratio", "number"]:
            header = f"{prefix}_"
            if filename.startswith(header) and filename.endswith("_f360.png"):
                # print(os.path.join(directory, filename))
                obs_type = filename[len(header):-len("_f360.png")]
                obs_name = obs_type.replace('_',' ')
                print(f"Adding {prefix}_{obs_type} ....")
                myobj = json_object["fields"]["Obs-Space"]["Diagnostics"][obj_names[prefix]]
                myobj[obs_name] = copy.deepcopy(template_obj)
                myobj[obs_name]["productFile"] = f"{header}{obs_type}"

    #print(json_object["fields"]["Obs-Space"]["Diagnostics"]["RMS plots"].keys())

    # Writing to sample.json
    print(f"\nWriting to {outfile} ...\n")
    with open(outfile, "w") as openfile:
        json.dump(json_object, openfile, indent=4)
