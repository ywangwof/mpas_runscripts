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

case_ids = ['20240506', '20240507', '20240508','20240516', '20240520', '20240521']

mrms_ids = ['20240506', '20240507', '20240508','20240516', '20240520', '20240521']

init_times = ['1900', '2000', '2100', '2200', '2300', '0000', '0100', '0200', '0300']

wofs_base = '/scratch/ywang/MPAS/intel/run_dirs/summary_files/'
out_dir = '/scratch/ywang/MPAS/intel/run_dirs/VERIF/mpas_hist/'

for c, case in enumerate(mrms_ids):
   temp_dir = os.path.join(wofs_base, case)
   case_times = os.listdir(temp_dir)
   times = []
   for t, time_dir in enumerate(case_times):
      print(time_dir, time_dir[-4:])
      if (time_dir[-4:] in init_times):
         temp_summary_dir = os.path.join(temp_dir, time_dir)

         temp_list = os.listdir(temp_summary_dir)

         cmd = 'python histogram_dz_wofs_2024.py -d %s -o %s' % (temp_summary_dir, out_dir)
         pool.apply_async(run_script, (cmd,))

#time.sleep(2)

pool.close()
pool.join()


