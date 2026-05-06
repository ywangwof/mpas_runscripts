#-------------------------------------------------------------------------------
#
"""
   Program grid_refl_obs.py

     written by Lou Wicker Dec 2023
     Adapted from David Dowell's DART code

"""

import numpy as np
import sys, os, glob
#import xarray as xr
import time as timeit
from scipy.spatial import KDTree
import argparse
from dart_utils import *

try:
    import cPickle as pickle
except:
    import pickle

#from pyproj import Transformer

# debug statement turns on a lot of information

debug = True

Fortran = 1
#-------------------------------------------------------------------------------

__missing = -9999.
__gravity = 9.806

#-------------------------------------------------------------------------------
# This is just processing sys.argv command line input, but using Argparse
# so later on we can do something else.
# Trying to test drive the namedtuple thing here to reduce the use of dictionarys

parser = argparse.ArgumentParser()

parser.add_argument("obsFile",type=str)
parser.add_argument("reflMin",type=float)
parser.add_argument("innovThresh",type=float)
parser.add_argument("modelFile",type=str)
parser.add_argument("gdatetime",type=int)
parser.add_argument("modelType",type=str)

input = parser.parse_args()
input_dict = vars(input)

print("\n ====================================")
print("\n BEGIN GRID_REFL_OBS \n")

if len(list(input_dict.keys())) != 7:
    print("\n Problem, input argument list is not correct - need:")
    print(" ---------------------------------------------------\n")
    for key in input_dict.keys():
        print(" Need argument: %s" % key)
    print("\n In that order, exiting...")

    sys.exit(1)

else:

    print("\n Input argument list:")
    print(" -----------------------------------------------\n")


    for key in input_dict.keys():
         print(" %s:  %s " % (key, input_dict[key]))

    print("\n")

#-------------------------------------------------------------------------------

ioda = True

if ioda:
    yobs, Hxmean, refl = ioda_get_refl(input.obsFile, refl_thresh=None, debug=debug)
else:
    yobs, Hxmean, refl = seq_get_refl(input.obsFile, refl_thresh=None, debug=debug)

#-------------------------------------------------------------------------------

# ===> READ MODEL GRIDS and CREATE LOCATION ARRAYS

xCell3D, yCell3D, hgt3D, mapper, latCell, lonCell, nx, ny, nz = read_model_grid(input.modelFile,
                                                                model_type=input.modelType)

#-------------------------------------------------------------------------------
# create x, y coordinates for radar data based on model transformer

x, y = mapper.transform(refl['location'][:,0],refl['location'][:,1])

refl['xyz'] = np.asarray([refl['location'][:,2], y, x]).transpose()   # vector for kdtree query is [N,3]

#-------------------------------------------------------------------------------
# Debug statements

if debug:
    print(" REFL  GRID:  Max LON: {:>10.4f}  Min LON: {:>10.4f}".format(refl['location'][:,0].max()-360., refl['location'][:,0].min()-360.))
    print(" REFL  GRID:  Max LAT: {:>10.4f}  Min LAT: {:>10.4f}".format(refl['location'][:,1].max(), refl['location'][:,1].min()))
    print(" REFL  GRID:  Max HGT: {:>10.4f}  Min HGT: {:>10.4f} (MSL)\n".format(refl['location'][:,2].max(), refl['location'][:,2].min()))

    print(" MODEL GRID:  Max LON: {:>10.4f}  Min LON: {:>10.4f}".format(lonCell.max()-360., lonCell.min()-360.))
    print(" MODEL GRID:  Max LAT: {:>10.4f}  Min LAT: {:>10.4f}".format(latCell.max(), latCell.min()))
    print(" MODEL GRID:  Max HGT: {:>10.4f}  Min HGT: {:>10.4f} (MSL)\n".format(hgt3D.max(), hgt3D.min()))


if debug:
    print(" REFL  TRANSFORM:  Max x-coordinate:  {:>10.2f}  Min x-coordinate: {:>10.2f}".format(refl['xyz'][:,2].max(), refl['xyz'][:,2].min()))
    print(" REFL  TRANSFORM:  Max y-coordinate:  {:>10.2f}  Min y-coordinate: {:>10.2f}".format(refl['xyz'][:,1].max(), refl['xyz'][:,1].min()))
    print(" REFL  TRANSFORM:  Max HGT:           {:>10.2f}  Min HGT:          {:>10.2f} (MSL)\n".format(refl['location'][:,2].max(), refl['location'][:,2].min()))

    print(" MODEL TRANSFORM:  Max x-coordinate:  {:>10.2f}  Min x-coordinate: {:>10.2f}".format(xCell3D.max(), xCell3D.min()))
    print(" MODEL TRANSFORM:  Max y-coordinate:  {:>10.2f}  Min y-coordinate: {:>10.2f}".format(yCell3D.max(), yCell3D.min()))
    print(" MODEL TRANSFORM:  Max HGT:           {:>10.2f}  Min HGT:          {:>10.2f} (MSL)\n".format(hgt3D.max(), hgt3D.min()))

    print(' Dimensions of flattened coordinate arrays (lat,lon,hgt):  ', xCell3D.shape, xCell3D.shape, hgt3D.shape)

# ===> END: READ MODEL GRID and CREATE LOCATION ARRAYS

#-------------------------------------------------------------------------------

# ===> BEGIN:  CREATE A KDTREE FROM MODEL COORDINATES TO SEARCH FROM

time0 = timeit.time()

model_kdtree3D = KDTree(np.stack((hgt3D, yCell3D, xCell3D), axis=1))

print("\n Elapsed time create KDTree table is:  %f seconds" % (timeit.time() - time0))

# now serialize it and write it out - this section of the code could be precomputed.

time0 = timeit.time()

with open('wofs_%s_grid_kdtree.pkl' % input.modelType, 'wb') as handle:
        pickle.dump(model_kdtree3D, handle)

# Need to store out X, Y, Z!

with open('%s_XYZ.pkl' % input.modelType, 'wb') as handle:
        pickle.dump((hgt3D, yCell3D, xCell3D), handle)

print(" Elapsed time to write out kdtree and grids are:  %f seconds" % (timeit.time() - time0))

# Now use the kdtree to find nearest points in the domain from the list of reflectivity observations.

dist, ind_xyz = model_kdtree3D.query(refl['xyz'],1)

print("\n Elapsed time for kdtree query for %d radar observations is:  %f seconds" % (refl['xyz'].shape[0],timeit.time() - time0))

if debug:   # check to see if this all makes sense

    print("\n Writing out a few observation/model locations")
    print(" ------------------------------------------------")

    for n in [refl['xyz'].shape[0]//4, refl['xyz'].shape[0]//3, refl['xyz'].shape[0]//2]:
        l = ind_xyz[n]
        print(' Location of reflectivity observation: {:>10.2f}  {:>10.2f}   {:>10.2f} (meters)'
                  .format(refl['xyz'][n][0], refl['xyz'][n][1], refl['xyz'][n][2]))
        print(' Location of closest in MODEL grid:    {:>10.2f}  {:>10.2f}   {:>10.2f} (meters) Distance: {:>8.2f}\n'
                  .format( hgt3D[l], yCell3D[l], xCell3D[l],  dist[n]))


# ===> END:  CREATE A KDTREE FROM MODEL COORDINATES TO SEARCH FROM

#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# ===> BEGIN:  CHECK FOR INNOVATION THRESHOLD AND OUTPUT DATA

num_refl_obs        = refl['xyz'].shape[0]
num_refl_obs_domain = 0
refl_noise_loc      = []
refl_no_noise_loc   = []

# This logic is a bit weird, and not sure how to fix things.
#
# Basically, need to find the largest observed reflectivity that is nearest
# to the model grid point.  So the refl_ob array is created with __missing,
# then if there is a "hit" at that grid point, we check the innovation to see
# if it meets the threshold and.  If those two conditions are met,
# we store that obs reflectivity.  However, if later on in the observed list,
# the same model grid point  is accessed with a LARGER observed value of
# of reflectivity than the one we already have, we replace the point with the new values.
#
# At the end, the refl_noise_loc is the list that has the locations needed for the additive noise.

# Grab the radar obs from the file, reference in 2D [ij,k] for both WRF and MPAS

if input.modelType == 'mpas':
    iarray, karray = np.unravel_index(ind_xyz, (nx,nz))
    jarray = np.zeros_like(iarray)
    refl_ob        = __missing * np.ones((nx*nz))
else:
    iarray, jarray, karray = np.unravel_index(ind_xyz, (nx, ny, nz))
    refl_ob        = __missing * np.ones((nx*ny*nz))

for n in np.arange(num_refl_obs):

    i = iarray[n]
    j = jarray[n]
    k = karray[n]

    l = ind_xyz[n]

    num_refl_obs_domain += 1

    if (refl_ob[l] == __missing or refl['obs'][n,yobs] > refl_ob[l]):

        ob_value_prior = refl['obs'][n,Hxmean]

        innov = refl['obs'][n,yobs] - ob_value_prior

        if (innov > input.innovThresh and refl['obs'][n,yobs] > input.reflMin):
            refl_ob[l] = refl['obs'][n,yobs]
            refl_noise_loc.append((i, j, k, l, hgt3D[l], yCell3D[l], xCell3D[l], refl_ob[l]) )
        else:
            refl_no_noise_loc.append([i, j, k, l, hgt3D[l], yCell3D[l], xCell3D[l], refl_ob[l]] )

# Create outputfiles for additive noise, both text-based and pickled

output = []

txt_file = open('refl_obs_%12.12i.txt' % (input.gdatetime), 'w')

for item in refl_noise_loc:

    i          = item[0]
    j          = item[1]
    k          = item[2]
    l          = item[3]
    refl_value = item[7]

    if input.modelType == 'mpas':
        output.append([i, j, k, l, hgt3D[l], yCell3D[l], xCell3D[l], refl_ob[l]])
        txt_file.write("{:>14d} {:>10d} {:>10.2f}\n".format(i, k, refl_value))
    else:
        if ((ny - j) > 9 and (j > 9)) and ((nx - i) > 9 and (i > 9)):
            output.append([i, j, k, l, hgt3D[l], yCell3D[l], xCell3D[l], refl_ob[l]])
            txt_file.write("{:>14d} {:>14d} {:>10d} {:>10.2f}\n".format(i+Fortran, j+Fortran, k+Fortran, refl_value))

txt_file.close()

with open('refl_obs_%12.12i.pkl' % (input.gdatetime), 'wb') as handle:
    pickle.dump(output, handle)

if debug:
    with open('refl_other_obs_%12.12i.pkl' % (input.gdatetime), 'wb') as handle:
        pickle.dump(refl_no_noise_loc, handle)

print("\n Number of reflectivity obs in time period:           {:>10d}".format(num_refl_obs))
print(" Number of reflectivity obs in time period and domain:  {:>10d}".format(num_refl_obs_domain))
print(" Number of points for additive noise:                   {:>10d}".format(len(output)))

print("\n ------------------------------------")
print("\n     END GRID_REFL_OBS.py")
print("\n ====================================")

