#!/usr/bin/env python
#
# This module reads in obs_seq file and trims any observation that contains
# a NaN value
#
#-----------------------------------------------------------------------
#
# By Yunheng Wang (NOAA/NSSL, 2023.11.10)
#
#-----------------------------------------------------------------------

import os
import sys
import re
import math
import argparse

from datetime import datetime, timedelta, timezone
from copy import copy

import numpy as np
import netCDF4 as ncdf

from itertools import islice
# Make an iterator that returns selected elements from the iterable

########################################################################
#
# Load the dictionary into a Namespace data structure.
# This step is not necessary, but cuts down the syntax needed to reference each item in the dict.
#
# Example: Retrieve the 0 hr forecast Dataset from GFS Dynamics
#            dict: ds_dict['GFS']['dynf'][0]
#       Namespace: datasets.GFS.dynf[0]

def make_namespace(d: dict,lvl=0,level=None):
    """ lvl  : level of this call
        level: level to stop, None is infinity
    """
    assert(isinstance(d, dict))
    ns =  argparse.Namespace()
    for k, v in d.items():
        lvl += 1
        if isinstance(v, dict):
            if level is None or (level is not None and lvl < level):
                leaf_ns = make_namespace(v,lvl,level)
                ns.__dict__[k] = leaf_ns
            else:
                ns.__dict__[k] = v
        else:
            ns.__dict__[k] = v

    return ns

########################################################################

def update_progress(job_title, progress):
    length = 40
    block = int(round(length*progress))
    # \r moves the cursor to the beginning of the line and then keeps outputting characters as normal.
    msg = "\r{0}: [{1}] {2}%".format(job_title, "#"*block + "-"*(length-block),
                                     round(progress*100, 2))
    if progress >= 1: msg += " DONE\r\n"
    sys.stdout.write(msg)            # without an implicit newline
    sys.stdout.flush()               # printing buffer immediately

########################################################################

def load_obs_seq(filename):
    ''' Read obs_seq text file '''

    obs_obj = {}

    type_re = re.compile('\d+ +[A-Z_]+')
    type_labels = {}
    var_labels  = {}
    qc_labels   = {}

    obs_list = []
    #expect_time = varargs.time.timestamp()
    #expt1 = expect_time - 300
    #expt2 = expect_time + 300

    nobs = 0
    if os.path.lexists(filename):
        with open(filename,'r') as fh:
            while True:
                line = fh.readline().strip()
                if not line: break
                if type_re.match(line):
                    type,label = line.split()
                    type_labels[type] = label

                elif line.startswith('num_copies:'):
                    ncopy,nqc = line.split()[1:4:2]
                    ncopy = int(ncopy)
                    nqc   = int(nqc)
                    #nobslines = 8+ncopy+nqc
                elif line.startswith('num_obs:'):
                    nobs = int(line.split()[1])
                    label_gen = islice(fh, ncopy)
                    for i,label in enumerate(label_gen):
                        var_labels[str(i+1)] = label.strip()

                    label_gen = islice(fh, nqc)
                    for i,label in enumerate(label_gen):
                        qc_labels[str(i)] = label.strip()

                elif line.startswith("OBS"):
                    obs = decode_one_obs(fh,ncopy,nqc)
                    obs_list.append(obs)
    else:
        print(f"ERROR: file {filename} not found")
        return None

    #print(f"nobs = {nobs}")

    obs_obj['nobs']     = nobs
    obs_obj['nvarcopy'] = ncopy; obs_obj['copy_labels'] = var_labels
    obs_obj['nqccopy']  = nqc;   obs_obj['qc_labels']   = qc_labels
    obs_obj['types']    = type_labels
    obs_obj['obs']      = obs_list

    #print(obs_obj['obs'][42])
    #print(type_labels)

    return make_namespace(obs_obj,level=1)

########################################################################

def decode_one_obs(fhandle,ncopy,nqc):

    nobslines = 8+ncopy+nqc

    inqc = ncopy+nqc
    iloc = inqc + 3
    itype = iloc + 2
    itime = itype + 1
    ivar = itime + 1

    values = []
    qcs    = []
    platform = {}
    mask   = False

    i = 0
    while True:
        line = fhandle.readline()
        sline = line.strip()

        if i < ncopy:                 # get obs value
            values.append(float(sline))

        elif i < inqc:                # get qc flag
            qc = float(sline)
            #qcs.append(math.floor(qc))
            qcs.append(qc)
        elif i == inqc:
            #print(i,inqc,sline)
            links = [int(l) for l in sline.split()]
        elif i == iloc:               # get loc3d
            lon,lat,alt,vert = sline.split()
        elif i == itype:              # get kind
            #print(i,itype,sline)
            otype = int(sline)
            if otype >= 124 and otype <= 126:
                itime = itype + 3
                ivar  = itime + 1
                nobslines = 10+ncopy+nqc
        elif sline == "platform":
            itime = itype + 8
            ivar  = itime + 1
            nobslines = 15+ncopy+nqc
            #print(i,nobslines,itime,sline)
            platform = {}
            j = 0
            while j < 6:
                line = fhandle.readline()
                sline = line.strip()
                #print(i,j,sline)
                if j == 1:          # loc3d
                    plon,plat,palt,pvert = [float(x) for x in sline.split()]
                elif j == 3:        # dir3d
                    x1,x2,x3 = [float(x) for x in sline.split()]
                    if math.isnan(x1) or math.isnan(x2):
                        mask = True
                elif j == 4:
                    y1 = float(sline)
                elif j == 5:
                    jlink = int(sline)
                j += 1

            platform = { 'loc3d'  : [float(plon),float(plat),float(palt),int(pvert)],
                         'dir3d'  : [x1,x2,x3],
                         'nyquist':  y1,
                         'key'    :  jlink
                        }
            i += j
        elif i == itime:             # get seconds, days
            #print(f"time: {i}/{nobslines},{itime} - {sline}")
            secs,days = sline.split()
        elif i == ivar:              # get error variance
            #print(f"var: {i}/{nobslines},{ivar} - {sline}")
            var=float(line)

        i += 1
        if i >= nobslines: break

    # 1970 01 01 00:00:00 is 134774 days 00 seconds
    # one day is 86400 seconds

    obsobj = {'values'    : values,
              'qcs'       : qcs,
              'lon'       : float(lon),
              'lat'       : float(lat),
              'level'     : float(alt),
              'level_type': int(vert),
              'links'     : links,
              'kind'      : otype,
              'platform'  : platform,
              'days'      : int(days),
              'seconds'   : int(secs),
              'time'      : float(days)+float(secs)/86400,
              'variance'  : var,
              'mask'      : mask
              }

    return make_namespace(obsobj,level=1)

########################################################################

def write_obs_seq(obs, filename ):
    '''
     write_DART_ascii is a program to dump radar data to DART ascii files.
    '''

    # Open ASCII file for DART obs to be written into.

    with open(filename, "w") as fi:

        fi.write(" obs_sequence\n")
        fi.write("obs_kind_definitions\n")

        # Deal with case that for reflectivity, 2 types of observations might have been created

        fi.write("       %d\n" % 1)
        for type,label in obs.types.items():
            fi.write("    %d          %s   \n" % (int(type), label) )

        fi.write("  num_copies:            %d  num_qc:            %d\n" % (obs.nvarcopy, obs.nqccopy))
        fi.write(" num_obs:       %d  max_num_obs:       %d\n" % (obs.nobs, obs.nobs) )

        for ivar,label in obs.copy_labels.items():
            fi.write(f"{label}\n")

        for qc,qc_label in obs.qc_labels.items():
            fi.write(f"{qc_label}\n")

        fi.write("  first:            %d  last:       %d\n" % (1, obs.nobs) )

        iobs = 0
        for it in obs.obs:

            if it.mask == True:   # bad values
                pass
            else:
                iobs += 1

                fi.write(" OBS            %d\n" % (iobs) )

                for value in it.values:
                    fi.write("   %20.14f\n" % value  )

                # Special QC flag processing so we can use low-reflectivity for additive noise

                for qc in it.qcs:
                    fi.write("   %20.14f\n" % qc )

                if iobs == 1:
                    fi.write(" %d %d %d\n" % (-1, iobs+1, -1) ) # First obs.
                elif iobs == obs.nobs:
                    fi.write(" %d %d %d\n" % (iobs-1, -1, -1) ) # Last obs.
                else:
                    fi.write(" %d %d %d\n" % (iobs-1, iobs+1, -1) )

                fi.write("obdef\n")
                fi.write("loc3d\n")
                fi.write("    %20.14f          %20.14f          %20.14f     %d\n" %
                            (it.lon, it.lat, it.level, it.level_type))

                fi.write("kind\n")
                fi.write("     %d     \n" % it.kind )

                # Check to see if its radial velocity and add platform informationp...need BETTER CHECK HERE!
                if it.platform:
                    fi.write("platform\n")
                    fi.write("loc3d\n")
                    fi.write("    %20.14f          %20.14f        %20.14f    %d\n" % (it.platform["loc3d"][0],it.platform["loc3d"][1],it.platform["loc3d"][2],it.platform["loc3d"][3]) )

                    fi.write("dir3d\n")
                    fi.write("    %20.14f          %20.14f        %20.14f\n" % (it.platform["dir3d"][0],it.platform["dir3d"][1],it.platform["dir3d"][2]) )

                    fi.write("    %20.14f     \n" % it.platform["nyquist"] )
                    fi.write("    %d          \n" % it.platform["key"] )

                # Done with special radial velocity obs back to dumping out time, day, error variance info
                fi.write("    %d          %d     \n" % (it.seconds, it.days) )

                # Logic for command line override of observational error variances

                fi.write("    %20.14f  \n" % it.variance )

                #if iobs % 10000 == 0: print(" write_DART_ascii:  Processed observation # %d" % iobs)

                update_progress(" write_DART_ascii:  Processed observation ",iobs/obs.nobs)
    return


########################################################################

def parse_args():
    """ Parse command line arguments
    """
    parser = argparse.ArgumentParser(description='Trim DART obs_seq file with nan values',
                                     epilog="""        ---- Yunheng Wang (2024-01-24).
                                            """)
                                     #formatter_class=CustomFormatter)

    parser.add_argument('files',nargs='+',help='DART obs_seq files')

    parser.add_argument('-v','--verbose', help='Verbose output',                                  action="store_true", default=False)
    parser.add_argument('-o','--outdir' , help='Name of the output file or an output directory',  required=True,       type=str)

    args = parser.parse_args()

    rargs = {'outfile': None }
    if not os.path.isdir(args.outdir):
        outdir_par = os.path.dirname(args.outdir)
        if os.path.isdir(outdir_par) or outdir_par == "":
            rargs['outfile'] = args.outdir
        else:
            print(f"ERROR: output directory {args.outdir} not exist.")
            sys.exit(1)

    return args,make_namespace(rargs)

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#
# Main function defined to return correct sys.exit() calls
#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

if __name__ == "__main__":

    cargs,rargs = parse_args()

    print("")
    for filename in cargs.files:
        print(f" load_obs_seq: Reading {filename}\n")
        obs_in = load_obs_seq(filename)

        #
        # Filter out bad observations
        #
        obs_out = copy(obs_in)

        obs_out.obs = []
        #  mask_check = data.mask && numpy.isnan().any()
        for it in obs_in.obs:
            if it.mask == False:   # good values
                obs_out.obs.append(it)

        obs_out.nobs = len(obs_out.obs)

        print(" Number of good observations:  %d\n" % obs_out.nobs)

        #
        # Write out the sequence file again
        #
        if rargs.outfile is not None:
            outfilename = rargs.outfile
        else:
            basefilename = os.path.basename(filename)
            outfilename  = os.path.join(cargs.outdir,basefilename)

        print(f" write_obs_seq: Writing to {outfilename}\n")
        write_obs_seq(obs_out, outfilename)
