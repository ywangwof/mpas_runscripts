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
import decimal

from datetime import datetime, timedelta, timezone
from copy import copy, deepcopy

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
    sys.stderr.write(msg)            # without an implicit newline
    sys.stderr.flush()               # printing buffer immediately

########################################################################

def load_obs_seq(filename,cargs,rargs):
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

                elif line.startswith('first:'):
                    first = int(line.split()[1])
                    last  = int(line.split()[3])

                elif line.startswith("OBS "):
                    iobs = int(line.split()[1])      # number of this obs
                    obs = decode_one_obs(fh,iobs,ncopy,nqc,cargs,rargs)
                    obs_list.append(obs)
    else:
        print(f"ERROR: file {filename} not found")
        return None

    #print(f"nobs = {nobs}")

    obs_obj['nobs']     = nobs
    obs_obj['nvarcopy'] = ncopy; obs_obj['copy_labels'] = var_labels
    obs_obj['nqccopy']  = nqc;   obs_obj['qc_labels']   = qc_labels
    obs_obj['types']    = type_labels
    obs_obj['first']    = first; obs_obj['last']    = last
    obs_obj['obs']      = obs_list

    #print(obs_obj['obs'][42])
    #print(type_labels)

    return make_namespace(obs_obj,level=1)

########################################################################

def decode_one_obs(fhandle,iobs,ncopy,nqc,cargs,rargs):

    nobslines = 8+ncopy+nqc

    inqc = ncopy+nqc
    iloc = inqc + 3
    itype = iloc + 2
    itime = itype + 1
    ivar = itime + 1

    values = []
    qcs    = []
    platform = {}
    visirs  = []
    mask     = False

    cloud_GOES  = False
    cloud_base  = None
    cloud_top   = None
    cloud_index = None
    visir       = False

    i = 0
    while True:
        line = fhandle.readline()
        sline = line.strip()

        if i < ncopy:                 # get obs value
            values.append(decimal.Decimal(sline))

        elif i < inqc:                # get qc flag
            qc = decimal.Decimal(sline)
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
            if otype in rargs.clouds:     # or (otype >= 80 and otype <= 87):
                cloud_GOES = True

                line = fhandle.readline()
                sline = line.strip()
                cloud_base,cloud_top = [decimal.Decimal(x) for x in sline.split()]

                line = fhandle.readline()
                sline = line.strip()
                cloud_index = decimal.Decimal(sline)

                # GOES observation contains an extra line for cloud base and cloud top heights
                itime = itype + 3             # and an integer line (?)
                ivar  = itime + 1
                nobslines = 10+ncopy+nqc
                i = i+2

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
                    plon,plat,palt,pvert = [decimal.Decimal(x) for x in sline.split()]
                elif j == 3:        # dir3d
                    x1,x2,x3 = [decimal.Decimal(x) for x in sline.split()]
                elif j == 4:
                    y1 = decimal.Decimal(sline)
                elif j == 5:
                    jlink = int(sline)
                j += 1

            platform = { 'loc3d'  : [decimal.Decimal(plon),decimal.Decimal(plat),decimal.Decimal(palt),int(pvert)],
                         'dir3d'  : [x1,x2,x3],
                         'nyquist':  y1,
                         'key'    :  jlink
                        }
            i += j
        elif sline == "visir":
            itime = itype + 7        # skip 6 more lines
            ivar  = itime + 1
            nobslines += 6

# visir
#    17.08586741569378         40.85687083986613        -888888.0000000000
#    41.82816763132313
#            4           16           44            8
#   -888888.0000000000
#          132

            visir = True

            j = 0
            while j < 5:
                line = fhandle.readline()
                sline = line.strip()
                #print(i,j,sline)
                if j in (0,1,3):
                    visirs.extend([decimal.Decimal(x) for x in sline.split()])
                elif j in (2,4):
                    visirs.extend([int(x) for x in sline.split()])
                j += 1
            i += j

        elif i == itime:             # get seconds, days
            if cargs.verbose: print(f"time: {i}/{nobslines},{itime} - {sline}")
            secs,days = sline.split()
        elif i == ivar:              # get error variance
            #print(f"var: {i}/{nobslines},{ivar} - {sline}")
            var=decimal.Decimal(line)

        i += 1
        if i >= nobslines: break

    # 1970 01 01 00:00:00 is 134774 days 00 seconds
    # one day is 86400 seconds

    obsobj = {'iobs'      : iobs,
              'values'    : values,
              'qcs'       : qcs,
              'lon'       : decimal.Decimal(lon),
              'lat'       : decimal.Decimal(lat),
              'level'     : decimal.Decimal(alt),
              'level_type': int(vert),
              'links'     : links,
              'kind'      : otype,
              'platform'  : platform,
              'days'      : int(days),
              'seconds'   : int(secs),
              'time'      : decimal.Decimal(days)+decimal.Decimal(secs)/86400,
              'variance'  : var,
              'mask'      : mask,
              'GOES'      : cloud_GOES,
              'clouds'    : (cloud_base, cloud_top, cloud_index),
              'visir'     : visir,
              'visir_a'   : visirs
              }

    return make_namespace(obsobj,level=1)

########################################################################

def write_obs_seq(obs, filename, number=0 ):
    '''
     write_DART_ascii is a program to dump radar data to DART ascii files.
    '''

    # Open ASCII file for DART obs to be written into.

    with open(filename, "w") as fi:

        fi.write(" obs_sequence\n")
        #fi.write("obs_type_definitions\n")
        fi.write("obs_kind_definitions\n")

        # Deal with case that for reflectivity, 2 types of observations might have been created

        fi.write(f"          {len(obs.types)}\n")
        for type,label in obs.types.items():
            fi.write(f"          {type} {label:31s}\n")

        fi.write(f"  num_copies:            {obs.nvarcopy}  num_qc:            {obs.nqccopy}\n")
        fi.write(f"  num_obs:        {obs.nobs}  max_num_obs:        {obs.nobs}\n" )

        for ivar,label in obs.copy_labels.items():
            fi.write(f"{label:65s}\n")

        for qc,qc_label in obs.qc_labels.items():
            fi.write(f"{qc_label:65s}\n")

        fi.write(f"  first:            {max(obs.first,1):d}  last:        {min(obs.last,obs.nobs):d}\n")

        iobs = 0
        n = 0
        for it in obs.obs:

            if it.mask == True:   # bad values
                pass
            else:
                iobs += 1

                if number > 0 and iobs > number:   break

# From Craig on Jan 19, 2024
#
# I'm a bit more concerned about your surface observation types having a
# "which_vert" of -1 (obs_seq.bufr), which is VERTISSURFACE.  When computing
# distances between two locations defined as "VERTISSURFACE", the vertical
# difference between these two locations is ignored.  That's arguably not
# a good thing.  I wonder what would happen if you used VERTISHEIGHT (value is 3)
# for the prebufr obs.
#
# It would be in the fortran code--probably in ascii_to_obs/prepbufr_to_obs.f90.
#
                if it.kind == 29 and it.level_type == -1:
                    level_type = 3
                    n += 1
                    print(f"iobs = {it.iobs}: which_vert changed from -1 to 3")
                else:
                    level_type = it.level_type

                fi.write(f" OBS   {it.iobs:12d}\n")

                for value in it.values:
                    fi.write(f" {value:f}     \n"  )

                # Special QC flag processing so we can use low-reflectivity for additive noise

                for qc in it.qcs:
                    fi.write(f" {qc}     \n" )

                fi.write(f" {it.links[0]} {it.links[1]} {it.links[2]}\n" )

                fi.write("obdef\n")
                fi.write("loc3d\n")
                fi.write(f"  {it.lon}      {it.lat}      {it.level}      {level_type:d}\n")

                fi.write("kind\n")
                fi.write(f"          {it.kind}\n")

                # GOES CWP etc. add cloud base/top and an index number
                if it.GOES:
                    fi.write(f"    {it.clouds[0]:f}          {it.clouds[1]:f}\n" )
                    fi.write(f"    {it.clouds[2]:d}                      \n" )

                # Check to see if its radial velocity and add platform informationp...need BETTER CHECK HERE!
                if it.platform:
                    fi.write("platform\n")
                    fi.write("loc3d\n")
                    fi.write(f"""    {it.platform["loc3d"][0]:f}          {it.platform["loc3d"][1]:f}        {it.platform["loc3d"][2]:f}    {it.platform["loc3d"][3]:d}\n""" )

                    fi.write("dir3d\n")
                    #fi.write("    %20.14f          %20.14f        %20.14f\n" % (it.platform["dir3d"][0],it.platform["dir3d"][1],it.platform["dir3d"][2]) )
                    fi.write(f"""    {it.platform["dir3d"][0]:f}          {it.platform["dir3d"][1]:f}        {it.platform["dir3d"][2]:f}\n""" )

                    #fi.write("    %20.14f     \n" % it.platform["nyquist"] )
                    fi.write(f"""    {it.platform["nyquist"]:f}     \n""" )
                    fi.write(f"""    {it.platform["key"]}           \n""" )

# visir
#    17.08586741569378         40.85687083986613        -888888.0000000000
#    41.82816763132313
#            4           16           44            8
#   -888888.0000000000
#          132
                if it.visir:
                    fi.write("visir\n")
                    fi.write(f"""    {it.visir_a[0:3]} \n""" )
                    fi.write(f"""    {it.visir_a[3]}   \n""" )
                    fi.write(f"""    {it.visir_a[4:8]} \n""" )
                    fi.write(f"""    {it.visir_a[8]}   \n""" )
                    fi.write(f"""    {it.visir_a[9]}   \n""" )


                # Done with special radial velocity obs back to dumping out time, day, error variance info
                fi.write(f"{it.seconds}     {it.days}\n" )

                # Logic for command line override of observational error variances

                #fi.write(" %18.14f     \n" % it.variance )
                fi.write(f" {it.variance:f}\n"  )

                #if iobs % 10000 == 0: print(" write_DART_ascii:  Processed observation # %d" % iobs)

                if cargs.verbose: update_progress(" write_DART_ascii:  Processed observation ",iobs/obs.nobs)
    return

########################################################################

def print_obs(obs_in,rargs):

    for it in obs_in.obs:
        # print(f"Available attributes: {vars(it)}")
        # 'values', 'qcs', 'lon', 'lat', 'level', 'level_type', 'links', 'kind', 'platform', 'days', 'seconds', 'time', 'variance', 'mask', 'GOES', 'clouds'
        if it.kind == int(rargs.t_type):
            print(f"iobs = {it.iobs:6d}, ", end="")
            for varname in rargs.t_var:
                value = getattr(it,varname)
                if isinstance(value,list):
                    valuestr=','.join([str(x) for x in value])
                    print(f"{varname} - {valuestr}, ", end="")
                else:
                    #variances.append(value)
                    print(f"{varname} - {value:f}, ", end="")
            print("")
    #variance = np.array(variances)
    #print(f"{variance.mean()}, {variance.min()}, {variance.max()}, {np.sqrt(variance.mean())}")

########################################################################

def process_obs(obs_in, obs_out, cargs,rargs):

    #
    # Mask observations for NaN
    #
    if not cargs.notrim:
        # default, trim all observation contain any NaN
        for it in obs_out.obs:
            if it.platform:
                if it.platform["dir3d"][0].is_nan() or it.platform["dir3d"][1].is_nan():
                    it.mask = True

    #
    # Mask observations for unwanted types
    #
    if len(rargs.xtypes) > 0:
        obs_out.types = {}
        for type,label in obs_in.types.items():
            if int(type) not in rargs.xtypes:
                obs_out.types[type] = label

        for it in obs_out.obs:
            if it.kind in rargs.xtypes:
                it.mask = True

    #
    # Filter out unwanted observations
    #
    obs_records = []
    masked_obs  = []
    #  mask_check = data.mask && numpy.isnan().any()
    for it in obs_out.obs:
        if it.mask == False:   # good values
            obs_records.append(it)
        else:
            masked_obs.append(it.iobs)

    if cargs.verbose: print(f"INFO: Dropped observations: {masked_obs}")

    if cargs.keep:
        # modify the linked list
        for it in obs_records:
            for mi in masked_obs:
                i = sum(j<mi for j in masked_obs)

                if it.iobs >= mi-i:
                    it.iobs -= 1

                if it.links[0] >= mi-i:
                    it.links[0] -= 1

                if it.links[1] > mi-i:
                    it.links[1] -= 1
    else:       # natural order for the links
        n = 0
        for it in obs_records:
            n += 1
            it.iobs = n
            if it.iobs == 1:
                i = -1
            else:
                i = it.iobs-1

            if it.iobs >= len(obs_records):
                j = -1
            else:
                j = it.iobs+1

            it.links = [i,j,-1]

    if len(obs_records) == 1:       # fix the link for next obs
        for it in obs_records:
            it.links[1] = -1

    return obs_records

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
    parser.add_argument('-o','--outdir' , help='Name of the output file or an output directory',  default='./',        type=str)
    parser.add_argument('-x','--xtypes' , help='Type Numbers of observation to be removed',       default=None,        type=str)
    parser.add_argument('-c','--clouds' , help='Type Numbers of observation that contains cloud lines', default="124,125,126", type=str)
    parser.add_argument('-t','--type'   , help='''Type Numbers of observation to be print, for examples,
                        44                 : Show observaiton value of observation type 44;
                        44,variance        : Show variance;
                        44,values,variance : Show value and variance''',                               default=None,        type=str)
    parser.add_argument('-k','--keep' ,   help='After drop observations, keep it links as possible',   action="store_true", default=False)
    parser.add_argument('-n','--number' , help='Fist N number of observations to be written',          default=0,           type=int)
    parser.add_argument('-N','--notrim' , help='Do not trim NaN in observations (default: Trim obs_seq for NaNs)', action="store_true", default=False)

    args = parser.parse_args()

    rargs = {'outfile': None, 'xtypes' : [], 't_type': None }

    if args.xtypes is not None:
        rargs['xtypes'] = [int(x) for x in args.xtypes.split(',')]

    if args.clouds is not None:
        rargs['clouds'] = [int(x) for x in args.clouds.split(',')]

    if args.type is not None:
        rlist = [item for item in args.type.split(',')]
        rargs['t_type'] = rlist[0]
        if len(rlist) > 1:
            rargs['t_var'] = rlist[1:]              # [value, variance]
        else:                                       # by default, print the obervation value only
            rargs['t_var'] = ['values']
    else:
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

    for filename in cargs.files:
        if cargs.verbose: print(f" load_obs_seq: Reading {filename}\n")
        obs_in = load_obs_seq(filename,cargs,rargs)

        if rargs.t_type is not None:  # Show its values
            #variances = []
            print(f" {rargs.t_type}: {obs_in.types[rargs.t_type]}")

            print_obs(obs_in,rargs)

        else:  # processs the sequence file to get a new one
            obs_out = copy(obs_in)
            #obs_out = deepcopy(obs_in)

            obs_out.obs = process_obs(obs_in,obs_out,cargs,rargs)

            obs_out.nobs = len(obs_out.obs)

            if cargs.verbose: print(" Number of good observations:  %d\n" % obs_out.nobs)

            if obs_out.nobs < 1:
                print(f"        Number of good observations: {obs_out.nobs}, skip {filename}")
                sys.exit(1)

            #
            # Write out the processed sequence file
            #
            if rargs.outfile is not None:
                outfilename = rargs.outfile
            else:
                basefilename = os.path.basename(filename)
                outfilename  = os.path.join(cargs.outdir,basefilename)

                if os.path.lexists(outfilename):
                    print(f"        write_obs_seq: file {outfilename} exists. Aborting ...\n")
                    sys.exit(2)


            #print(f" write_obs_seq: Writing to {outfilename+'_in'}\n")
            #write_obs_seq(obs_in, outfilename+"_in")

            if cargs.verbose:
                print(f" write_obs_seq: Writing to {outfilename}\n")
            else:
                print(f"        {filename} -> {outfilename}\n        Number of good observations: {obs_out.nobs}")

            write_obs_seq(obs_out, outfilename)
