import re
import matplotlib
import matplotlib.pyplot as plt
import numpy as np
import os
import statistics
import datetime
import netCDF4
import warnings
import itertools
import shelve
import pyproj
from scipy import signal
from scipy import *
from scipy import ndimage
from scipy.spatial import distance
import skimage
from skimage.morphology import label
from skimage.measure import regionprops
import sklearn
from sklearn.utils import resample
from optparse import OptionParser
import obj_cbook
from obj_cbook import *

####################################### File Variables: ######################################################

parser = OptionParser()
parser.add_option("-d", dest="in_dir", type="string", default= None, help="Input directory of summary files")
parser.add_option("-o", dest="out_dir", type="string", help = "Output Directory")

(options, args) = parser.parse_args()

if ((options.in_dir == None) or (options.out_dir == None)):
   print
   parser.print_help()
   print
   sys.exit(1)
else:
   in_dir = options.in_dir
   out_dir = options.out_dir

#################################### User-Defined Variables:  #####################################################

edge = 7

#varname = 'dz_cress'
#varname = 'refl_cress'
varname = 'refl_consv'  #2023
#varname = 'dz_consv'  #2019 - 2022

#var_bins = np.arange(0., 81., 1.)
var_bins = np.arange(-0.1, 80.1, 0.2)

dummy = np.arange(1) * 0. #used to initialize histograms of 0's
var_hist = np.histogram(dummy, var_bins)

############################ Process WRFOUT: #################################

temp_files = os.listdir(in_dir)
mrms_files = []

for f, temp_file in enumerate(temp_files):
   if (temp_file[-20:-17] == 'RAD'):
       if ((int(temp_file[-7:-5]) >= 19) or (int(temp_file[-7:-5]) <= 8) or (temp_file[-7:-3] == '0900')):
         mrms_files.append(temp_file)

mrms_files.sort()

for f, temp_file in enumerate(mrms_files):
   infile = os.path.join(in_dir, temp_file)

#   print(f, infile)
   if (f == 0):
      outname = temp_file[-16:-8] + '_' + 'd01' + '_' + varname + '.nc' #2023
      outfile = os.path.join(out_dir, outname)
      print('asdf', outfile)

#   print(f, infile)
   temp_lat, temp_lon, temp_var = load_mrms_new(infile, varname, edge)

   temp_var_ravel = temp_var[:,:].ravel()
#   print(len(temp_var_ravel), np.max(temp_var_ravel))
   temp_hist = np.histogram(temp_var_ravel, var_bins)

   var_hist[0][:] = var_hist[0][:] + temp_hist[0][:]

################################# Write to rot_qc file: ###################################################

print(var_hist[0][0:10])

try:
   fout = netCDF4.Dataset(outfile, "w")
except:
   print ("Could not create %s!\n" % outfile)

fout.createDimension('NB', len(var_hist[1]))
fout.createDimension('NX', len(var_hist[0]))

fout.createVariable('bins', 'f4', ('NB',))
fout.createVariable('var_hist', 'f4', ('NX',))

fout.variables['bins'][:] = var_bins
fout.variables['var_hist'][:] = var_hist[0][:]

fout.close()
del fout


