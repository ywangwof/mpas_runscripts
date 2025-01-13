#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import re
import matplotlib
import numpy as np
import os
import sys
import statistics
from datetime import datetime, timedelta
import netCDF4 
import warnings
import itertools
import pyproj
from scipy import signal
from scipy import *
from scipy import ndimage
from scipy.spatial import distance
import skimage
from skimage.morphology import label
from skimage.measure import regionprops
from optparse import OptionParser

###########################

def get_mrms_timestamp_old(filename): 

# Parse filename from 2017 - 2018 interpolated MRMS filenames and convert to datetime obj: 

   yyyymmdd = filename[-18:-10]   
   HHMM = filename[-9:-5]
   temp_date = yyyymmdd + HHMM

   dt = datetime.strptime(temp_date, '%Y%m%d%H%M') 

   return dt

###########################

def get_mrms_timestamp_new(filename):

# Parse filename from 2019 - current (2023) interpolated MRMS filenames and convert to datetime obj: 

   yyyymmdd = filename[-16:-8]
   HHMM = filename[-7:-3]
   temp_date = yyyymmdd + HHMM
   dt = datetime.strptime(temp_date, '%Y%m%d%H%M')

   return dt

###########################

def get_wofs_timestamp(filename):

# Parse filename from WoFS summary file name and convert to datetime obj: 

   yyyymmdd = filename[-21:-13]
   HHMM = filename[-7:-3]
   temp_date = yyyymmdd + HHMM

   init_HH = filename[-12:-10] 

   dt = datetime.strptime(temp_date, '%Y%m%d%H%M')

#correct bug where forecasts initialized before 00 UTC retain original date for lead times past 00 UTC:  
   if (int(init_HH) > 12 and int(HHMM[0:2]) < 12):
      dt = dt + timedelta(days=1) 
 
   return dt

###########################

def get_hrrr_timestamp(filename): #2023 only

# Parse filename from WoFS summary file name and convert to datetime obj:

   yyyymmdd = filename[-24:-16]
   HHMM = filename[-7:-3]
   temp_date = yyyymmdd + HHMM

   init_HH = filename[-12:-10]

   dt = datetime.strptime(temp_date, '%Y%m%d%H%M')

#correct bug where forecasts initialized before 00 UTC retain original date for lead times past 00 UTC:
   if (int(init_HH) > 12 and int(HHMM[0:2]) < 12):
      dt = dt + timedelta(days=1)

   return dt

#############################

def load_mrms_old(filename, varname, edge): 

# Load variable (varname), lat, and lon from a 2017 - 2018 interpolated MRMS file: 

   try:                                                 #open WRFOUT file
      fin = netCDF4.Dataset(filename, "r")
   except:
      print("%s does not exist! \n" %filename)
#      sys.exit(1)

   lat = fin.variables['XLAT'][edge:-edge,edge:-edge]
   lon = fin.variables['XLON'][edge:-edge,edge:-edge]

   var = fin.variables[varname][edge:-edge,edge:-edge]

   fin.close()
   del fin

   return lat, lon, var

#############################

def load_mrms_new(filename, varname, edge):

# Load variable (varname), lat, and lon from a 2019 - current (2023) interpolated MRMS file: 
   try:                                                 #open WRFOUT file
      fin = netCDF4.Dataset(filename, "r")
   except:
      print("%s does not exist! \n" %filename)
#      sys.exit(1)

   lat = fin.variables['lat'][edge:-edge,edge:-edge]
   lon = fin.variables['lon'][edge:-edge,edge:-edge]

   var = fin.variables[varname][edge:-edge,edge:-edge]

   fin.close()
   del fin

   return lat, lon, var

#############################

def load_wofs(filename, varname, edge):

# Load variable (varname), lat, and lon from a 2017 - 2018 interpolated MRMS file: 

   try:                                                 #open WRFOUT file
      fin = netCDF4.Dataset(filename, "r")
   except:
      print("%s does not exist! \n" %filename)
#      sys.exit(1)

   lat = fin.variables['xlat'][edge:-edge,edge:-edge]
   lon = fin.variables['xlon'][edge:-edge,edge:-edge]

   var = fin.variables[varname][:,edge:-edge,edge:-edge]

   fin.close()
   del fin

   return lat, lon, var

#############################

def load_hrrr(filename, varname, edge):

# Load variable (varname), lat, and lon from a 2017 - 2018 interpolated MRMS file: 

   try:                                                 #open WRFOUT file
      fin = netCDF4.Dataset(filename, "r")
   except:
      print("%s does not exist! \n" %filename)
#      sys.exit(1)

   lat = fin.variables['lat'][edge:-edge,edge:-edge]
   lon = fin.variables['lon'][edge:-edge,edge:-edge]

   var = fin.variables[varname][edge:-edge,edge:-edge]

   fin.close()
   del fin

   return lat, lon, var

###############################

def convert_lat_lon(lat, lon, true_lat_1, true_lat_2, cen_lat, stand_lon):

    domain_proj = pyproj.Proj(proj='lcc', # projection type: Lambert Conformal Conic
                       lat_1=true_lat_1, lat_2=true_lat_2, # Cone intersects with the sphere
                       lat_0=cen_lat, lon_0=stand_lon, # Center point
                       a=6370000, b=6370000) # The Earth is a perfect, beautiful, spinning sphere

    x, y = domain_proj(lon, lat)

    return x, y

###############################

def find_initial_objects(var, thresh):

   obj = var * 0.  #initialize output array
   obj_init = np.where(var >= thresh, var, 0.) #threshold swath values

   obj_int = np.where(var >= thresh, 1, 0) #convert thresholded values to binary field
   obj_int = obj_int.astype(int)

   obj_labels = skimage.measure.label(obj_int)  #label objects using skimage.measure.label
   obj_labels = obj_labels.astype(int)

   obj_props = regionprops(obj_labels, obj_init)  #find object diagnostic properties using skimage.measure.regionprops

   return obj_labels, obj_props

###############################

def apply_area_thresh(props, thresh):

   thresh_props = [] 
   for i in range(0, len(props)): 
      if (props[i].area > thresh): 
         thresh_props.append(props[i]) 

   return thresh_props

###############################

def apply_maxint_thresh(props, thresh):

   thresh_props = []
   for i in range(0, len(props)):
      if (props[i].max_intensity > thresh):
         thresh_props.append(props[i])

   return thresh_props

###############################

def apply_area_thresh_labels(props, labels, thresh):

   thresh_props = []
   for i in range(0, len(props)):
      if (props[i].area < thresh):
          labels = np.where(labels==(i+1), 0, labels)
      else:
          thresh_props.append(props[i])
         
   return labels, thresh_props

###############################

def apply_maxint_thresh_labels(props, labels, thresh):

   thresh_props = []
   for i in range(0, len(props)):
      if (props[i].max_intensity < thresh):
          labels = np.where(labels==(i+1), 0, labels)
      else:
          thresh_props.append(props[i])
         
   return labels, thresh_props

###############################

def calc_centroid_dist(cent1, cent2): 

   cent_dist = np.sqrt((cent2[0] - cent1[0])**2 + (cent2[1] - cent1[1])**2) 

   return cent_dist

###############################

def calc_boundary_dist(coords1, coords2): 

   bound_dist = np.min(distance.cdist(coords1, coords2)) #use scipy.spatial.distance.cdist function

   return bound_dist

###############################

def calc_ti(obj1, obj2, max_centroid, max_bound): 

   obj1_cent = obj1['Centroid'] 
   obj1_coords = obj1['Coords'] 
   obj2_cent = obj2.centroid
   obj2_coords = obj2.coords

   bound_dist = calc_boundary_dist(obj1_coords, obj2_coords) 
   cent_dist = calc_centroid_dist(obj1_cent, obj2_cent) 

   cent_ti = (max_centroid - cent_dist) / max_centroid
   bound_ti = (max_bound - bound_dist) / max_bound

   if (cent_ti < 0.): 
      cent_ti = 0. 
   if (bound_ti < 0.): 
      bound_ti = 0. 

   ti = 0.5 * (cent_ti + bound_ti) 

   return ti

###############################

def calc_ti_area_ratio(obj1, obj2, max_centroid, max_bound):

   obj1_cent = obj1['Centroid']
   obj1_coords = obj1['Coords']
   obj1_area = obj1['Area']
   obj2_cent = obj2.centroid
   obj2_coords = obj2.coords
   obj2_area = obj2.area

   bound_dist = calc_boundary_dist(obj1_coords, obj2_coords)
   cent_dist = calc_centroid_dist(obj1_cent, obj2_cent)

   cent_ti = (max_centroid - cent_dist) / max_centroid
   bound_ti = (max_bound - bound_dist) / max_bound

   if (cent_ti < 0.):
      cent_ti = 0.
   if (bound_ti < 0.):
      bound_ti = 0.

   if (obj1_area < obj2_area): 
      area_ratio = obj1_area / obj2_area
   else: 
      area_ratio = obj2_area / obj1_area

   ti = (0.5 * (cent_ti + bound_ti)) * area_ratio

   return ti

###########################################################################################################

def gridpoint_interp(field, x_index, y_index):

   #interpolate 2-d array (field) to a specific point (x_index, y_index)

   #Dependencies:

   #numpy

   #Input:
   #
   #field       - 2d array (e.g. lat, lon)
   #x_index     - x index value of interpolation point (must be within field[:,:])
   #y_index     - y index value of interpolation point (must be within field[:,:])

   #Returns
   #
   #interp      - field interpolated to x_index, y_index

#######################

   interp_x = x_index - floor(x_index)
   interp_y = y_index - floor(y_index)

   lowlow = field[floor(y_index),floor(x_index)]
   lowup = field[floor(y_index),ceil(x_index)]
   upup = field[ceil(y_index),ceil(x_index)]
   uplow = field[ceil(y_index),floor(x_index)]

   low = interp_y * (lowup - lowlow) + lowlow
   up = interp_y * (upup - uplow) + uplow

   interp = interp_x * (up - low) + low

   return interp

###########################################################################################################


##############################################################################################################







