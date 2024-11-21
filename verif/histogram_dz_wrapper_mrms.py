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

pool = Pool(processes=(24))              # set up a queue to run

############################ Find WRFOUT files to process: #################################

### Find ENS Summary files ###

mrms_ids = ['20240506', '20240507', '20240508','20240516', '20240520', '20240521']

mrms_base = '/work/rt_obs/MRMS/RAD_AZS_MSH/2024/'
out_dir = '/scratch/ywang/MPAS/intel/run_dirs/VERIF/mrms_hist/'

for c, case in enumerate(mrms_ids):
   case_dir = os.path.join(mrms_base, case)

   cmd = 'python histogram_dz_mrms_2024.py -d %s -o %s' % (case_dir, out_dir)
   pool.apply_async(run_script, (cmd,))

#time.sleep(2)

pool.close()
pool.join()


