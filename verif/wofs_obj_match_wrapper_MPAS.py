#!/usr/bin/env python
import matplotlib
matplotlib.use('Agg')
from scipy import signal
from scipy import *
from scipy import ndimage
import math
from math import radians, tan, sin, cos, pi, atan, sqrt, pow, asin, acos
import pylab as P
import numpy as np
from numpy import NAN
import sys, glob
import netCDF4
from optparse import OptionParser
import os
import time as timeit
from optparse import OptionParser
from multiprocessing import Pool

import argparse

###################################################################################################
# run_script is a function that runs a system command

def run_script(cmd):
    print ("Executing command:  " + cmd)
    os.system(cmd)
    print (cmd + "  is finished....")
    return


########################################################################

def parse_args():
    """ Parse command line arguments
    """
    parser = argparse.ArgumentParser(description='Generate WoFS objects',
                                     epilog="""        ---- Yunheng Wang & Patrick Skinner (2024-10-16).
                                            """)
                                     #formatter_class=CustomFormatter)

    parser.add_argument('wofs_base',        help='Directory for WoFS summary files')

    parser.add_argument('-v','--verbose',   help='Verbose output',                action="store_true", default=False)
    parser.add_argument('-o','--outdir' ,   help='Object file output directory',             type=str, default=None)
    parser.add_argument("-a","--thresh1",   type=float, default='47.4',
                                            help="Initial WoFS threshold for object ID")
    parser.add_argument("-b","--thresh2",   type=float, default='52.6',
                                            help="second threshold for WoFS object ID (obj max must exceed this)")

    args = parser.parse_args()

    if not os.path.lexists(args.outdir) and os.path.lexists(os.path.dirname(args.outdir)):
        os.mkdir(args.outdir)

    return args

#################################### User-Defined Variables:  #####################################################

pool = Pool(processes=(40))              # set up a queue to run

old_mrms   = 'False'
out_netcdf = 'True'

############################ Find WRFOUT files to process: #################################

case_ids = ['20240506', '20240507', '20240508','20240516', '20240520', '20240521']

mrms_dir = '/work/rt_obs/MRMS/RAD_AZS_MSH/2024/'

cargs = parse_args()

wofs_dir = cargs.wofs_base
out_dir  = cargs.outdir

for c, case in enumerate(case_ids):

    cmd = f'python object_matcher_2024.py -w {wofs_dir} -m {mrms_dir} -c {case} -o {out_dir} -t {old_mrms} -n {out_netcdf} -a {cargs.thresh1} -b {cargs.thresh2}'
    pool.apply_async(run_script, (cmd,))

#time.sleep(2)

pool.close()
pool.join()
