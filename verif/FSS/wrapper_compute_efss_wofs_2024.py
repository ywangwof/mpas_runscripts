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

###################################################################################################
# run_script is a function that runs a system command

def run_script(cmd):
    print ("Executing command:  " + cmd)
    os.system(cmd)
    print (cmd + "  is finished....")
    return


#################################### User-Defined Variables:  #####################################################

pool = Pool(processes=(18))              # set up a queue to run

############################ Find WRFOUT files to process: #################################

case_ids = ['20240506', '20240507', '20240508', '20240516', '20240520', '20240521']
times    = ['1700', '1800', '1900', '2000', '2100', '2200', '2300', '0000', '0100', '0200', '0300']

var = 'compdz'

mrms_base = '/work/rt_obs/MRMS/RAD_AZS_MSH/2024'
wofs_base = '/scratch/derek.stratman/wofs_verif/SummaryFiles/2024'
out_dir   = '/scratch/ywang/MPAS/intel/run_dirs/VERIF/FSS/cb-wofs'

for c, case in enumerate(case_ids):
    for t, time in enumerate(times):
        temp_case = case + '/'
        mrmsdir = os.path.join(mrms_base,case)
        indir   = os.path.join(wofs_base,case,time)
        outdir  = os.path.join(out_dir,case,time)

        if os.path.exists(indir):
            print('Ensemble directory: ',indir)
            if os.path.exists(mrmsdir):
                print('MRMS directory: ',mrmsdir)

                if os.path.exists(outdir):
                    print('Output directory: ',outdir)
                else:
                    os.makedirs(outdir)
                    print('Created output directory: ',outdir)

                cmd = 'python compute_efss_wofs_2024.py -d %s -m %s -o %s -v %s -x 7 -y 7' % (indir, mrmsdir, outdir, var)

                pool.apply_async(run_script, (cmd,))

            else:
                print('MRMS directory doesnt exist: ',mrmsdir)
        else:
            print('WoFS directory doesnt exist: ',indir)

pool.close()
pool.join()
