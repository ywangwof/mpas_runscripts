#-------------------------------------------------------------------------------
#
"""
   Program add_pert_where_high_refl.py

   Written by Lou Wicker Dec 2023
   Adapted from David Dowell's DART code

"""

import numpy as np
import sys, os, glob
import netCDF4 as ncdf
import time as timeit
from scipy.spatial import KDTree
from numpy.random import randn
import argparse

try:
    import cPickle as pickle
except:
    import pickle

from pyproj import Transformer

from dart_utils import write_model_grid

# debug statement turns on a lot of information

debug  = False
writeNewFile = True

#

__missing = -9999.
__gravity = 9.806

__hLength = 9000.
__vLength = 3000.  # default length scales for smoothing noise

__default_sd = 0.0

nflds = 6  # number of fields that could be generated

#-------------------------------------------------------------------------------
# This is just processing sys.argv command line input, but using Argparse
# so later on we can do something else.

parser = argparse.ArgumentParser()

parser.add_argument("modelGrid",type=str)
parser.add_argument("modelFile",type=str)
parser.add_argument("h_length",type=float)
parser.add_argument("v_length",type=float)
parser.add_argument("u_sd",type=float)
parser.add_argument("v_sd",type=float)
parser.add_argument("w_sd",type=float)
parser.add_argument("t_sd",type=float)
parser.add_argument("td_sd",type=float)
parser.add_argument("qv_sd",type=float)
parser.add_argument("gdatetime",type=int)
parser.add_argument("ensNum",type=int)
parser.add_argument("modelType",type=str)
parser.add_argument("pkl_path",type=str)

input = parser.parse_args()
input_dict = vars(input)

print("\n ====================================")
print("\n BEGIN ADD_PERT_WHERE_HIGH_REFL  \n")

if len(list(input_dict.keys())) != 14:


    print("\n Problem, input argument list is not correct - need: 14")
    print(" ---------------------------------------------------\n")

    sys.exit(1)
else:

    print("\n Input argument list:")
    print(" -----------------------------------------------\n")

    for key in input_dict.keys():
         print(" %s:  %s " % (key, input_dict[key]))


    print("\n")

#-------------------------------------------------------------------------------
# gather up the input standard deviations

nflds_sd = np.array([input.u_sd, input.v_sd,  input.w_sd,
                     input.t_sd, input.td_sd, input.qv_sd], dtype='float32')

#-------------------------------------------------------------------------------
# Based on time and ens member number, initiate a random seed

np.random.seed(int(timeit.time()) + input.ensNum)

#-------------------------------------------------------------------------------

kdtree_file   = os.path.join(input.pkl_path, 'wofs_%s_grid_kdtree.pkl' % input.modelType)
reflobs_file  = os.path.join(input.pkl_path, 'refl_valid_obs_%12.12i.pkl' % (input.gdatetime))
modelXYZ_file = os.path.join(input.pkl_path, 'wofs_%s_XYZ.pkl' % input.modelType)

# Check if all required pickle files exist
for file_path in [kdtree_file, reflobs_file, modelXYZ_file]:
    if not os.path.exists(file_path):
        print(f"\nError: Required file not found: {file_path}")
        sys.exit(1)

time0 = timeit.time()

# Read in serialized (pickled) KDTREE created in GRID_REFL_OBS

with open(kdtree_file, 'rb') as handle:
        model_kdtree3D = pickle.load(handle)

print(" Elapsed time to read in KDTree table is:  %f seconds" % (timeit.time() - time0))

time0 = timeit.time()

# Now read in the serialized (pickled) REFL_OBS file which stores the positions

with open(reflobs_file, 'rb') as handle:
    refl_noise_loc = pickle.load(handle)

# Now read in the serialized (pickled) model grid locations

with open(modelXYZ_file, 'rb') as handle:
    hgt3D, yCell3D, xCell3D = pickle.load(handle)

print(" Elapsed time to read in obs locations and model grid:  %f seconds" % (timeit.time() - time0))

#-------------------------------------------------------------------------------
# Create noise array which will then be added into the model state.

noise = np.zeros((*hgt3D.shape,nflds))

if debug:
   print(' NOISE array shape:  ',noise.shape, '\n')

#-------------------------------------------------------------------------------
# Loop through noise list and use model_kdtree3D to find locations.
#      Because kdtree cannot do multiple grid lengths, we simply look for all points
#      within the h_length radius, and then throw out the points farther away than
#      v_length.

rand_num = np.random.normal(0.0, nflds_sd)

for item in refl_noise_loc:

    # Same code for both models here because we set up the searches to work the same on the flattened grid
    # ====================================================================================================

    ijk_ind = model_kdtree3D.query_ball_point(item[4:7], input.h_length)

    rand_num = np.random.normal(0.0, nflds_sd)

    dis_xyz = np.exp( - ( np.abs(item[6] - xCell3D[ijk_ind]) / input.h_length
                        + np.abs(item[5] - yCell3D[ijk_ind]) / input.h_length
                        + np.abs(item[4] -   hgt3D[ijk_ind]) / input.v_length ) )

    # for a reason I dont understand, using the SQRT creates much bigger perts.

    # dis_x = ( (item[6] - xCell3D[ijk_ind]) / h_length )**2
    # dis_y = ( (item[5] - yCell3D[ijk_ind]) / h_length )**2
    # dis_z = ( (item[4] - hgt3D[ijk_ind])   / v_length )**2
    # dis_xyz = np.exp( - np.sqrt(dis_x*dis_y*dis_z) )

    noise[ijk_ind,:] +=  np.where(dis_xyz <= 1.0, dis_xyz, 0.0)[:,np.newaxis] * rand_num[np.newaxis,:]

# this code should go back out into the "writer for the model"

ret = write_model_grid(input.modelGrid,input.modelFile, noise, rand_num, model_type=input.modelType, write_new_file=writeNewFile)


print("\n Elapsed time to update model grid with %d locations is:  %f seconds" \
      % (len(refl_noise_loc), timeit.time() - time0))

print("\n ------------------------------------")
print("\n    END ADD_PERT_WHERE_REFL_HIGH")
print("\n ====================================")

#from pathlib import Path
#
#Path(f'done.add_noise_{input.ensNum:02d}').touch()
