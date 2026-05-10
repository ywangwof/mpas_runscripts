#!/usr/bin/env python3
#-------------------------------------------------------------------------------
#
"""
   Program add_pert_where_high_refl.py

   Written by Lou Wicker Dec 2023
   Adapted from David Dowell's DART code

"""

import numpy as np
import sys, os  #, glob
#import netCDF4 as ncdf
import time as timeit
#from scipy.spatial import KDTree
#from numpy.random import randn
import yaml
import psutil
import gc

try:
    import cPickle as pickle
except:
    import pickle

#from pyproj import Transformer

from dart_utils import write_model_grid

# debug statement turns on a lot of information

debug  = False
writeNewFile = True

#

#__missing = -9999.
#__gravity = 9.806
#
#__hLength = 9000.
#__vLength = 3000.  # default length scales for smoothing noise
#
#__default_sd = 0.0

nflds = 6  # number of fields that could be generated

#-------------------------------------------------------------------------------
# Load configuration from YAML file

if len(sys.argv) != 2:
    print("\n ====================================")
    print("\n Usage: python add_pert_where_high_refl.py <config_file.yaml>\n")
    print(" ====================================\n")
    sys.exit(1)

config_file = sys.argv[1]

if not os.path.exists(config_file):
    print(f"\n Error: Configuration file not found: {config_file}\n")
    sys.exit(1)

# Load configuration from YAML file
with open(config_file, 'r') as f:
    config = yaml.safe_load(f)

print("\n ====================================")
print("\n BEGIN ADD_PERT_WHERE_HIGH_REFL  \n")

# Validate required configuration keys
required_keys = ['modelGrid', 'modelFile', 'h_length', 'v_length', 'u_sd', 'v_sd', 'w_sd',
                 't_sd', 'td_sd', 'qv_sd', 'gdatetime', 'ensNum', 'modelType', 'pkl_path']

missing_keys = [key for key in required_keys if key not in config]
if missing_keys:
    print(f"\n Problem, configuration is missing keys: {missing_keys}")
    print(" ---------------------------------------------------\n")
    sys.exit(1)

# Create a simple object to access config like input.key
class Config:
    def __init__(self, config_dict):
        for key, value in config_dict.items():
            setattr(self, key, value)

input = Config(config)

print("\n Configuration parameters:")
print(" -----------------------------------------------\n")

for key in config.keys():
    print(f" {key}:  {config[key]} ")

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

# Try to use ramdisk cache if available (for faster I/O in parallel runs)
ramdisk_cache = f"/dev/shm/mpas_cache_{os.getppid()}"
if os.path.isdir(ramdisk_cache):
    # Check if all pickle files exist in ramdisk cache
    kdtree_cache = os.path.join(ramdisk_cache,   'wofs_%s_grid_kdtree.pkl' % input.modelType)
    reflobs_cache = os.path.join(ramdisk_cache,  'refl_valid_obs_%12.12i.pkl' % (input.gdatetime))
    modelXYZ_cache = os.path.join(ramdisk_cache, 'wofs_%s_XYZ.pkl' % input.modelType)

    if os.path.exists(kdtree_cache) and os.path.exists(reflobs_cache) and os.path.exists(modelXYZ_cache):
        kdtree_file = kdtree_cache
        reflobs_file = reflobs_cache
        modelXYZ_file = modelXYZ_cache
        print(f"\n Using cached pickle files from ramdisk: {ramdisk_cache}\n")

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

# Convert to float32 to save ~50% memory
hgt3D = hgt3D.astype('float32')
yCell3D = yCell3D.astype('float32')
xCell3D = xCell3D.astype('float32')

print(" Elapsed time to read in obs locations and model grid:  %f seconds" % (timeit.time() - time0))

# Log memory usage
process = psutil.Process(os.getpid())
mem_info = process.memory_info()
print(f"\n Memory usage after loading pickle files:")
print(f"  RSS (Resident Set Size): {mem_info.rss / 1e9:.2f} GB")
print(f"  VMS (Virtual Memory Size): {mem_info.vms / 1e9:.2f} GB")
print(f"  Available system memory: {psutil.virtual_memory().available / 1e9:.2f} GB\n")

#-------------------------------------------------------------------------------
# Create noise array which will then be added into the model state.
# Use float32 to reduce memory footprint by 50% compared to float64

noise = np.zeros((*hgt3D.shape, nflds), dtype='float32')

if debug:
   print(' NOISE array shape:  ',noise.shape, '\n')
   import sys
   print(f' NOISE array memory size:  {noise.nbytes / 1e6:.1f} MB\n')

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

    rand_num = np.random.normal(0.0, nflds_sd).astype('float32')

    dis_xyz = np.exp( - ( np.abs(item[6] - xCell3D[ijk_ind]) / input.h_length
                        + np.abs(item[5] - yCell3D[ijk_ind]) / input.h_length
                        + np.abs(item[4] -   hgt3D[ijk_ind]) / input.v_length ) ).astype('float32')

    # for a reason I dont understand, using the SQRT creates much bigger perts.

    # dis_x = ( (item[6] - xCell3D[ijk_ind]) / h_length )**2
    # dis_y = ( (item[5] - yCell3D[ijk_ind]) / h_length )**2
    # dis_z = ( (item[4] - hgt3D[ijk_ind])   / v_length )**2
    # dis_xyz = np.exp( - np.sqrt(dis_x*dis_y*dis_z) )

    noise[ijk_ind,:] +=  np.where(dis_xyz <= 1.0, dis_xyz, 0.0)[:,np.newaxis].astype('float32') * rand_num[np.newaxis,:]

    # Clean up temporary arrays to help garbage collection
    del ijk_ind, dis_xyz

# Clean up large temporary objects and force garbage collection
del model_kdtree3D, yCell3D, xCell3D
gc.collect()

mem_info = process.memory_info()
print(f"\n Memory usage after processing loop and cleanup:")
print(f"  RSS (Resident Set Size): {mem_info.rss / 1e9:.2f} GB")
print(f"  VMS (Virtual Memory Size): {mem_info.vms / 1e9:.2f} GB\n")

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
