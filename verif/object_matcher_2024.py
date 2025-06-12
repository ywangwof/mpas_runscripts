#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import re
import matplotlib
import numpy as np
import os,sys
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
from optparse import OptionParser
import obj_cbook
from obj_cbook import *

# from PIL import Image, ImageDraw
# from matplotlib.patches import Polygon
# import matplotlib.pyplot as plt
# import matplotlib.patches as mpatches

####################################### File Variables: ######################################################

parser = OptionParser()
parser.add_option("-w", dest="wofs_dir", type="string", default=None,
                  help="Input Directory (of WoFS case summary files)")
parser.add_option("-m", dest="mrms_dir", type="string",
                  help="Input directory (of interpolated MRMS files)")
parser.add_option("-c", dest="case_date", type="string",
                  help="YYYYMMDD of case to process")
parser.add_option("-o", dest="out_dir", type="string",
                  help="Output directory (for object dictionary files)")
parser.add_option("-t", dest="old_mrms", type="string", default='False',
                  help="Boolean for reading old (pre-2019) MRMS files")
parser.add_option("-n", dest="out_netcdf", type="string", default='False',
                  help="Boolean for outputting objects in NetCDF format")
parser.add_option("-a", dest="thresh1", type="float", default='47.4',
                  help="Initial WoFS threshold for object ID")
parser.add_option("-b", dest="thresh2", type="float", default='52.6',
                  help="second threshold for WoFS object ID (obj max must exceed this)")
parser.add_option("-X", dest="appendix", type="string", default='None',
                  help="time appendix string, default: None")

(options, args) = parser.parse_args()

if ((options.wofs_dir == None) or (options.mrms_dir == None) or (options.case_date == None) or (options.out_dir == None)):
    print
    parser.print_help()
    print
    sys.exit(1)
else:
    wofs_dir = options.wofs_dir
    mrms_dir = options.mrms_dir
    case_date = options.case_date
    out_dir = options.out_dir
    old_mrms = options.old_mrms
    out_netcdf = options.out_netcdf

    mrms_dir = os.path.join(mrms_dir, case_date)
    if options.appendix is None or options.appendix == "None":
        wofs_dir = os.path.join(wofs_dir, case_date)
    else:
        wofs_dir = os.path.join(wofs_dir, f"{case_date}_{options.appendix}")

####################################### Object ID and Matching Thresholds: ######################################################

dx = 3.  # horizontal grid spacing in km
max_bound_disp = 40. / dx  # maximum boundary displacement in km
max_cent_disp = 40. / dx  # maximum centroid displacement in km
# area_thresh		= 54. / (dx**2) #area threshold in km**2
area_thresh = 108. / (dx**2)  # area threshold in km**2
track_bound_disp = 9. / dx  # maximum boundary displacement in km for storm tracking

mrms_thresh_1 = 40.  # initial MRMS threshold for object ID
mrms_thresh_2 = 45.  # second threshold for MRMS object ID (obj max must exceed this)

wofs_thresh_1 = options.thresh1  # 47.4  # initial WoFS threshold for object ID
wofs_thresh_2 = options.thresh2  # 52.6  # second threshold for WoFS object ID (obj max must exceed this)

ti_thresh = 0.2  # total interest threshold for matching object pairs

if (old_mrms == 'True'):
    mrms_varname = 'DZ_CRESSMAN'
else:
    mrms_varname = 'refl_consv'

wofs_varname = 'comp_dz'

true_lat_1 = 30.  # for lambert conformal projection
true_lat_2 = 60.  # for lambert conformal projection
edge = 7  # number of gridboxes to trim from domain boundaries
# edge                    = 7 #number of gridboxes to trim from domain boundaries

verif_hours = ['1900', '2000', '2100', '2200', '2300',
               '0000', '0100', '0200', '0300']  # initialization times to process

domain = "d01" # case_date[-2:]  # should be "d1" or "d2" for multiple domains

####################################### MRMS Object ID and Tracking: ######################################################

# Read MRMS Files:

mrms_files_temp = os.listdir(mrms_dir)
mrms_files_temp.sort()

if (old_mrms == 'False'):
    init_mrms_files = mrms_files_temp
    mrms_files_temp = []
    for t, temp_file in enumerate(init_mrms_files):
        if ((len(temp_file) > 15) and (temp_file[-16] == '2') and (temp_file[-20:-17] == 'RAD')):
            mrms_files_temp.append(temp_file)

mrms_times = []  # list of each time MRMS data are found for day

# build list of expected MRMS times (every 5 minutes between start and end times of mrms_files) and find missing times:
for f, temp_file in enumerate(mrms_files_temp):
    if (temp_file[-3:] == '.nc'):
        if (old_mrms == 'True'):
            # get_mrms_timestamp_old function in obj_cbook.py
            temp_timestamp = get_mrms_timestamp_old(temp_file)
        else:
            # get_mrms_timestamp_new function in obj_cbook.py
            temp_timestamp = get_mrms_timestamp_new(temp_file)

        mrms_times.append(temp_timestamp)

start_time_mrms = np.min(mrms_times)
end_time_mrms = np.max(mrms_times)

full_mrms_times = []
for i in range(0, ((end_time_mrms - start_time_mrms).seconds+1), 300):
    full_mrms_times.append(start_time_mrms + timedelta(0, i))

# return elements of full_mrms_times not in mrms_times
missing_mrms_times = np.setdiff1d(full_mrms_times, mrms_times)
zero_mrms_times = []

# print('missing mrms: ', missing_mrms_times)

# process MRMS files to build list of tracked object dictionary entries for entire day:

mrms_obj_dict = []  # inialize list to be filled with dictionary entries for each object
prev_obj_dict = []  # initialize list of prior time object properties

for f, temp_file in enumerate(mrms_files_temp):
    if (temp_file[-3:] == '.nc'):

        temp_obj_dict = []  # initialize list for dictionary entries from this file
        temp_path = os.path.join(mrms_dir, temp_file)

# load mrms:

        if (old_mrms == 'True'):
            # get_mrms_timestamp_old function in obj_cbook.py
            temp_timestamp = get_mrms_timestamp_old(temp_file)
        else:
            # get_mrms_timestamp_new function in obj_cbook.py
            temp_timestamp = get_mrms_timestamp_new(temp_file)

        if (f == 0):  # pull date string from first file (to use with output filename):
            date_str = datetime.strftime(temp_timestamp, '%Y%m%d')

        if (old_mrms == 'True'):
            mrms_lat, mrms_lon, mrms_var = load_mrms_old(
                temp_path, mrms_varname, edge)  # load_mrms_old function in obj_cbook.py
        else:
            mrms_lat, mrms_lon, mrms_var = load_mrms_new(
                temp_path, mrms_varname, edge)  # load_mrms_old function in obj_cbook.py

        if (np.max(mrms_var) < 0.01):  # if empty field skip and add to missing times
            print('0 value reflectivity field: ', temp_file,
                  temp_timestamp, zero_mrms_times)
            zero_mrms_times.append(temp_timestamp)

#         missing_mrms_times.append(temp_timestamp)
#         print ('0 value reflectivity field: ', temp_file, temp_timestamp)
            continue

#      cen_lat = np.min(mrms_lat) + ((np.max(mrms_lat) - np.min(mrms_lat)) / 2.)
#      cen_lon = np.min(mrms_lon) + ((np.max(mrms_lon) - np.min(mrms_lon)) / 2.)

#      mrms_x, mrms_y = convert_lat_lon(mrms_lat, mrms_lon, true_lat_1, true_lat_2, cen_lat, cen_lon) #convert_lat_lon function in obj_cbook.py

# find obj:

        mrms_labels, mrms_props = find_initial_objects(mrms_var, mrms_thresh_1)
        mrms_props = apply_area_thresh(mrms_props, area_thresh)
        mrms_props = apply_maxint_thresh(mrms_props, mrms_thresh_2)

        for i in range(0, len(mrms_props)):
            temp_age = 0.

            # loop through objects from previous timestep
            for j in range(0, len(prev_obj_dict)):
                temp_prev_time = prev_obj_dict[j]['Time']

# if an MRMS file is missing ... don't do anything but print a warning:
#            if (((temp_timestamp - temp_prev_time).seconds != 300) and (i == 0) and (j == 0)): #i, j == 0 so it only prints once
#               print('more than 5 min between MRMS files:  ', temp_file, temp_timestamp, temp_prev_time)

                temp_prev_coords = prev_obj_dict[j]['Coords']
                temp_prev_age = prev_obj_dict[j]['Age']

                temp_bound_dist = calc_boundary_dist(
                    mrms_props[i].coords, temp_prev_coords)

# if current object overlaps with object(s) from previous time, assign oldest object age to current object:
#            print(i, j, temp_bound_dist)
                if (temp_bound_dist == 0.):
                    if ((temp_prev_age+300.) > temp_age):
                        temp_age = temp_prev_age + 300.  # add 5 minutes to storm age
#                  print(temp_age)

# build dictionary of object properties, add to full list of objects and list of obj at this time:
            temp_obj = {'Time': temp_timestamp,
                        'Age': temp_age,
                        'ID': (i+1),
                        'Area': mrms_props[i].area,
                        'MaxInt': mrms_props[i].max_intensity,
                        'MeanInt': mrms_props[i].mean_intensity,
                        'MajAxis': mrms_props[i].major_axis_length,
                        'MinAxis': mrms_props[i].minor_axis_length,
                        'Eccen': mrms_props[i].eccentricity,
                        'Orient': mrms_props[i].orientation,
                        'Solidity': mrms_props[i].solidity,
                        'Centroid': mrms_props[i].centroid,
                        'Coords': mrms_props[i].coords}

            # add object dictionary to list of MRMS objects
            mrms_obj_dict.append(temp_obj)
            temp_obj_dict.append(temp_obj)

    prev_obj_dict = temp_obj_dict  # set previous objects to current time

# save list of tracked MRMS dictionary objects:

temp_outname = 'mrms_' + date_str + '_' + domain + '_obj'
mrms_outname = os.path.join(out_dir, temp_outname)

mrms_out = shelve.open(mrms_outname, flag='n')
mrms_out['MRMS'] = mrms_obj_dict
mrms_out['Missing_MRMS'] = missing_mrms_times
mrms_out['Zero_MRMS'] = zero_mrms_times
mrms_out['MRMS_Times'] = mrms_times
mrms_out.close()

####################################### WoFS Object ID and Matching: ######################################################

# Read WoFS ENS Files:

wofs_init_dirs_temp = os.listdir(wofs_dir)

wofs_init_dirs = []
# strip out non-forecast time directories (assumes format of HHMM)
for temp_dir in wofs_init_dirs_temp:
    if (temp_dir[-4:] in verif_hours):
        wofs_init_dirs.append(temp_dir)

wofs_init_dirs.sort()
#print(f"wofs_dir={wofs_dir},{wofs_init_dirs}")
#sys.exit(0)

# get list of MRMS object times for comparison to WoFS objects:
# need the 1-line for loop because dictionaries are stupid
mrms_times = [d['Time'] for d in mrms_obj_dict]

# process every WoFS forecast from a given day:
for d, init_dir in enumerate(wofs_init_dirs):
    temp_dir = os.path.join(wofs_dir, init_dir)

# initialize list of dictionaries for the given forecast for WoFS and MRMS objects:
    hits_dict = []
    misses_dict = []
    fas_dict = []
    extras_dict = []
    mrms_extras_dict = []

    wofs_files_temp = os.listdir(temp_dir)

# build list of all "ENS" summary files:
    wofs_files = []
    for f in wofs_files_temp:
        if f.startswith('.'): continue
        if f[-28:-25] == 'ALL' and f.endswith('.nc'):
            wofs_files.append(f)
    wofs_files.sort()
    for f, temp_file in enumerate(wofs_files):
        temp_mrms_obj_dict = []

        temp_path = os.path.join(temp_dir, temp_file)

# If first file get initialization time:
        if (f == 0):
            init_timestamp = get_wofs_timestamp(temp_file)
            init_str = temp_file[-12:-8]

# find MRMS objects matching current WoFS valid time:
        temp_timestamp = get_wofs_timestamp(temp_file)
#      print('wofs timestamp: ', temp_timestamp)
        if ((temp_timestamp in missing_mrms_times) or (temp_timestamp in zero_mrms_times)):
            print('Missing MRMS file at:  ', temp_timestamp,
                  temp_file, zero_mrms_times)
            continue

#      if (temp_timestamp in missing_mrms_times):
#          print('Missing MRMS file at:  ', temp_timestamp, temp_file)
#          continue

# if no MRMS obs for current WoFS time, skip to next time:
#      missing_mrms_flag = 0

#      for temp_missing_mrms in missing_mrms_times:
#         if (temp_timestamp == temp_missing_mrms):
#            print('Missing MRMS obs at: ', temp_timestamp, ' time not processed')
#            missing_mrms_flag = 1
#      if (missing_mrms_flag == 1):
#         continue

# get lead time in minutes:
        temp_lead_time = (temp_timestamp - init_timestamp).seconds / 60

        for i in range(0, len(mrms_times)):
            if (mrms_times[i] == temp_timestamp):
                temp_mrms_obj_dict.append(mrms_obj_dict[i])

# load WoFS

        wofs_lat, wofs_lon, wofs_var = load_wofs(temp_path, wofs_varname, edge)

# where the magic happens - for each member at each time categorize objects as hits, extras, false alarms, or misses and append
# dictionaries of object properties to the list for the current forecast:

        for n in range(0, wofs_var.shape[0]):  # for each WoFS member

            # find obj:

            wofs_labels, wofs_props = find_initial_objects(
                wofs_var[n, :, :], wofs_thresh_1)
            wofs_props = apply_area_thresh(wofs_props, area_thresh)
            wofs_props = apply_maxint_thresh(wofs_props, wofs_thresh_2)

            # initialize lists of matched objects and TI for this member at this time
            member_hits_mrms = []
            member_hits_wofs = []
            member_hits_ti = []

# loop to iterate and find best matches (allows for up to 5 "extras" to be reassigned to missed MRMS objects)

            for i in range(0, 5):
                member_hits_mrms_init = []  # 'init' lists that will contain duplicate matches
                member_hits_wofs_init = []
                member_hits_ti_init = []
                if (i == 0):  # in first iteration, get array of max TI for every WoFS obj (for identifying "extra" hits)
                    wofs_max_ti_full = []  # list of the max TI for all WoFS obj
                    wofs_max_ti_ar_full = []  # list of the max TI with area ratio for all WoFS obj
                    wofs_max_ti_mrms_id = []  # index of MRMS obj with max TI
                    for w in range(0, len(wofs_props)):  # for each wofs obj
                        obj_ti = 0.  # TI without area ratio
                        obj_ti_ar = 0.  # TI with area ratio
                        temp_mrms_id = -99.
                        for m in range(0, len(temp_mrms_obj_dict)):  # for each mrms obj

                            # calc total interest using cbook function calc_ti:  expects list of dictionaries for MRMS and list of regionprops for WoFS

                            temp_ti = calc_ti(
                                temp_mrms_obj_dict[m], wofs_props[w], max_cent_disp, max_bound_disp)
                            temp_ti_area_ratio = calc_ti_area_ratio(
                                temp_mrms_obj_dict[m], wofs_props[w], max_cent_disp, max_bound_disp)
                            if ((temp_ti_area_ratio > obj_ti_ar) and (temp_ti > ti_thresh)):
                                obj_ti_ar = temp_ti_area_ratio
                                obj_ti = temp_ti
                                temp_mrms_id = m
                        wofs_max_ti_full.append(obj_ti)
                        wofs_max_ti_ar_full.append(obj_ti_ar)
                        wofs_max_ti_mrms_id.append(temp_mrms_id)

# do the same thing for MRMS objects:
                    mrms_max_ti_full = []  # list of the max TI for all MRMS obj
                    mrms_max_ti_ar_full = []  # list of the max TI with area ratio for all MRMS obj
                    mrms_max_ti_full_wofs_id = []  # list of the WoFS ID associated with max MRMS TI
                    for m in range(0, len(temp_mrms_obj_dict)):  # for each MRMS obj
                        obj_ti = 0.  # TI without area ratio
                        obj_ti_ar = 0.  # TI with area ratio
                        temp_wofs_id = -99.  # placeholder for obj with 0 max TI
                        for w in range(0, len(wofs_props)):  # for each mrms obj

                            # calc total interest using cbook function calc_ti:  expects list of dictionaries for MRMS and list of regionprops for WoFS

                            temp_ti = calc_ti(
                                temp_mrms_obj_dict[m], wofs_props[w], max_cent_disp, max_bound_disp)
                            temp_ti_area_ratio = calc_ti_area_ratio(
                                temp_mrms_obj_dict[m], wofs_props[w], max_cent_disp, max_bound_disp)
                            if ((temp_ti_area_ratio > obj_ti_ar) and (temp_ti > ti_thresh)):
                                obj_ti_ar = temp_ti_area_ratio
                                obj_ti = temp_ti
                                temp_wofs_id = w
                        mrms_max_ti_full.append(obj_ti)
                        mrms_max_ti_ar_full.append(obj_ti_ar)
                        mrms_max_ti_full_wofs_id.append(temp_wofs_id)

# get list of matched WoFS and MRMS objects with duplicates:

                for m in range(0, len(temp_mrms_obj_dict)):  # for each mrms obj
                    already_matched = 0  # flag for objects matched in prior iterations
                    for mm in range(0, len(member_hits_mrms)):
                        # if current index is in list of matched indices
                        if (m == member_hits_mrms[mm]):
                            already_matched = 1
                    if (already_matched == 0):  # if unmatched MRMS object
                        obj_ti_ar = 0.  # total interest with weighting by area ratio
                        obj_ti = 0.  # total interest without weighting by area ratio
                        for w in range(0, len(wofs_props)):
                            already_matched_wofs = 0  # flag for WoFS objects matched in prior iterations
                            for ww in range(0, len(member_hits_wofs)):
                                if (w == member_hits_wofs[ww]):
                                    already_matched_wofs = 1
                            if (already_matched_wofs == 0):  # if unmatched WoFS object
                                temp_ti = calc_ti(
                                    temp_mrms_obj_dict[m], wofs_props[w], max_cent_disp, max_bound_disp)
                                temp_ti_area_ratio = calc_ti_area_ratio(
                                    temp_mrms_obj_dict[m], wofs_props[w], max_cent_disp, max_bound_disp)
                                # if a better match set TI score and match indices
                                if ((temp_ti_area_ratio > obj_ti_ar) and (temp_ti > ti_thresh)):
                                    obj_ti_ar = temp_ti_area_ratio
                                    obj_ti = temp_ti
                                    wofs_match_ind = w
                                    mrms_match_ind = m
                        if (obj_ti > ti_thresh):  # retain matches that exceed the total interest threshold
                            member_hits_mrms_init.append(mrms_match_ind)
                            member_hits_wofs_init.append(wofs_match_ind)
                            member_hits_ti_init.append(obj_ti_ar)

# if matched objects are found get unique indices, otherwise move on
                if (len(member_hits_wofs_init) > 0):
                    # get unique matched WoFS indices and count of each index
                    wofs_indices, wofs_counts = np.unique(
                        member_hits_wofs_init, return_counts=True)
                else:
                    break  # if no matched wofs objects don't look for multiple matches

# find best WoFS match for each MRMS object:

                # for each matched WoFS index
                for w, idx in enumerate(wofs_indices):
                    # if a single WoFS obj is matched to multiple MRMS objects, retain best match
                    if (wofs_counts[w] > 1):
                        temp_ti_max = 0.
                        for ww in range(0, len(member_hits_wofs_init)):
                            if (member_hits_wofs_init[ww] == idx):
                                if (member_hits_ti_init[ww] > temp_ti_max):
                                    temp_ti_max = member_hits_ti_init[ww]
                                    mrms_best_match = member_hits_mrms_init[ww]
                                    wofs_best_match = member_hits_wofs_init[ww]
                        member_hits_wofs.append(wofs_best_match)
                        member_hits_mrms.append(mrms_best_match)
                        member_hits_ti.append(temp_ti_max)
                    else:  # assign matched obj indices for WoFS and MRMS as well as matching TI score
                        hits_init_idx = member_hits_wofs_init.index(idx)
                        member_hits_wofs.append(idx)
                        member_hits_mrms.append(
                            member_hits_mrms_init[hits_init_idx])
                        member_hits_ti.append(
                            member_hits_ti_init[hits_init_idx])
                if (np.max(wofs_counts) == 1):  # if no duplicates found, move on
                    break

# split extras and false alarms:
            member_extras_wofs = []
            member_extras_ti = []
            member_extras_mrms_id = []
            member_fas_wofs = []
            member_fas_ti = []

            wofs_full_indices = np.arange(len(wofs_props))

            # returns elements of array 1 not in array 2
            wofs_not_hits = np.setdiff1d(wofs_full_indices, member_hits_wofs)
            for idx in wofs_not_hits:
                if (wofs_max_ti_full[idx] > ti_thresh):
                    member_extras_wofs.append(idx)
                    member_extras_ti.append(wofs_max_ti_ar_full[idx])
                    member_extras_mrms_id.append(wofs_max_ti_mrms_id[idx])
                else:
                    member_fas_wofs.append(idx)
                    member_fas_ti.append(wofs_max_ti_ar_full[idx])

# build list of mrms extras and misses:
            member_misses_mrms = []
            member_misses_ti = []
            member_extras_mrms = []
            member_extras_mrms_ti = []
            member_extras_mrms_wofs_id = []

            mrms_full_indices = np.arange(len(temp_mrms_obj_dict))

            mrms_not_hits = np.setdiff1d(mrms_full_indices, member_hits_mrms)

            for idx in mrms_not_hits:
                if (mrms_max_ti_full[idx] > ti_thresh):
                    member_extras_mrms.append(idx)
                    member_extras_mrms_ti.append(mrms_max_ti_ar_full[idx])
                    member_extras_mrms_wofs_id.append(
                        mrms_max_ti_full_wofs_id[idx])
                else:
                    member_misses_mrms.append(idx)
                    member_misses_ti.append(mrms_max_ti_ar_full[idx])

            # assumes member_hits_wofs and member_hits_mrms are equal length (something is wrong if they aren't)
            for h, hit in enumerate(member_hits_wofs):

                # build dictionary of WoFS and MRMS matched pair object properties, add to hit list:
                temp_obj = {'Init_Time': init_timestamp,
                            'Valid_Time': temp_timestamp,
                            'Lead_Time': temp_lead_time,
                            'Member': (n+1),
                            'MRMS_ID': temp_mrms_obj_dict[member_hits_mrms[h]]['ID'],
                            'MRMS_Age': temp_mrms_obj_dict[member_hits_mrms[h]]['Age'],
                            'MRMS_Area': temp_mrms_obj_dict[member_hits_mrms[h]]['Area'],
                            'MRMS_MaxInt': temp_mrms_obj_dict[member_hits_mrms[h]]['MaxInt'],
                            'MRMS_MeanInt': temp_mrms_obj_dict[member_hits_mrms[h]]['MeanInt'],
                            'MRMS_MajAxis': temp_mrms_obj_dict[member_hits_mrms[h]]['MajAxis'],
                            'MRMS_MinAxis': temp_mrms_obj_dict[member_hits_mrms[h]]['MinAxis'],
                            'MRMS_Eccen': temp_mrms_obj_dict[member_hits_mrms[h]]['Eccen'],
                            'MRMS_Orient': temp_mrms_obj_dict[member_hits_mrms[h]]['Orient'],
                            'MRMS_Solidity': temp_mrms_obj_dict[member_hits_mrms[h]]['Solidity'],
                            'MRMS_Centroid': temp_mrms_obj_dict[member_hits_mrms[h]]['Centroid'],
                            'MRMS_Coords': temp_mrms_obj_dict[member_hits_mrms[h]]['Coords'],
                            'WoFS_ID': h,
                            'WoFS_Area': wofs_props[hit].area,
                            'WoFS_MaxInt': wofs_props[hit].max_intensity,
                            'WoFS_MeanInt': wofs_props[hit].mean_intensity,
                            'WoFS_MajAxis': wofs_props[hit].major_axis_length,
                            'WoFS_MinAxis': wofs_props[hit].minor_axis_length,
                            'WoFS_Eccen': wofs_props[hit].eccentricity,
                            'WoFS_Orient': wofs_props[hit].orientation,
                            'WoFS_Solidity': wofs_props[hit].solidity,
                            'WoFS_Centroid': wofs_props[hit].centroid,
                            'WoFS_Coords': wofs_props[hit].coords,
                            'Total_Interest': member_hits_ti[h]}

                hits_dict.append(temp_obj)

            for e, extra in enumerate(member_extras_wofs):

                # build dictionary of WoFS extra match object properties, add to extra hit list:

                temp_obj = {'Init_Time': init_timestamp,
                            'Valid_Time': temp_timestamp,
                            'Lead_Time': temp_lead_time,
                            'Member': (n+1),
                            'WoFS_ID': e,
                            'WoFS_Area': wofs_props[extra].area,
                            'WoFS_MaxInt': wofs_props[extra].max_intensity,
                            'WoFS_MeanInt': wofs_props[extra].mean_intensity,
                            'WoFS_MajAxis': wofs_props[extra].major_axis_length,
                            'WoFS_MinAxis': wofs_props[extra].minor_axis_length,
                            'WoFS_Eccen': wofs_props[extra].eccentricity,
                            'WoFS_Orient': wofs_props[extra].orientation,
                            'WoFS_Solidity': wofs_props[extra].solidity,
                            'WoFS_Centroid': wofs_props[extra].centroid,
                            'WoFS_Coords': wofs_props[extra].coords,
                            'MRMS_ID': member_extras_mrms_id[e],
                            'Total_Interest': member_extras_ti[e]}

                extras_dict.append(temp_obj)

            for f, fa in enumerate(member_fas_wofs):

                # build dictionary of WoFS false alarm object properties, add to fa list:

                temp_obj = {'Init_Time': init_timestamp,
                            'Valid_Time': temp_timestamp,
                            'Lead_Time': temp_lead_time,
                            'Member': (n+1),
                            'WoFS_Area': wofs_props[fa].area,
                            'WoFS_MaxInt': wofs_props[fa].max_intensity,
                            'WoFS_MeanInt': wofs_props[fa].mean_intensity,
                            'WoFS_MajAxis': wofs_props[fa].major_axis_length,
                            'WoFS_MinAxis': wofs_props[fa].minor_axis_length,
                            'WoFS_Eccen': wofs_props[fa].eccentricity,
                            'WoFS_Orient': wofs_props[fa].orientation,
                            'WoFS_Solidity': wofs_props[fa].solidity,
                            'WoFS_Centroid': wofs_props[fa].centroid,
                            'WoFS_Coords': wofs_props[fa].coords,
                            'Total_Interest': member_fas_ti[f]}

                fas_dict.append(temp_obj)

            for m, miss in enumerate(member_misses_mrms):

                # build dictionary of WoFS and MRMS matched pair object properties, add to hit list:

                temp_obj = {'Init_Time': init_timestamp,
                            'Valid_Time': temp_timestamp,
                            'Lead_Time': temp_lead_time,
                            'Member': (n+1),
                            'MRMS_ID': temp_mrms_obj_dict[miss]['ID'],
                            'MRMS_Age': temp_mrms_obj_dict[miss]['Age'],
                            'MRMS_Area': temp_mrms_obj_dict[miss]['Area'],
                            'MRMS_MaxInt': temp_mrms_obj_dict[miss]['MaxInt'],
                            'MRMS_MeanInt': temp_mrms_obj_dict[miss]['MeanInt'],
                            'MRMS_MajAxis': temp_mrms_obj_dict[miss]['MajAxis'],
                            'MRMS_MinAxis': temp_mrms_obj_dict[miss]['MinAxis'],
                            'MRMS_Eccen': temp_mrms_obj_dict[miss]['Eccen'],
                            'MRMS_Orient': temp_mrms_obj_dict[miss]['Orient'],
                            'MRMS_Solidity': temp_mrms_obj_dict[miss]['Solidity'],
                            'MRMS_Centroid': temp_mrms_obj_dict[miss]['Centroid'],
                            'MRMS_Coords': temp_mrms_obj_dict[miss]['Coords'],
                            'Total_Interest': member_misses_ti[m]}

                misses_dict.append(temp_obj)

            for me, extra_miss in enumerate(member_extras_mrms):

                # build dictionary of WoFS and MRMS matched pair object properties, add to hit list:

                temp_obj = {'Init_Time': init_timestamp,
                            'Valid_Time': temp_timestamp,
                            'Lead_Time': temp_lead_time,
                            'Member': (n+1),
                            'MRMS_ID': temp_mrms_obj_dict[extra_miss]['ID'],
                            'MRMS_Age': temp_mrms_obj_dict[extra_miss]['Age'],
                            'MRMS_Area': temp_mrms_obj_dict[extra_miss]['Area'],
                            'MRMS_MaxInt': temp_mrms_obj_dict[extra_miss]['MaxInt'],
                            'MRMS_MeanInt': temp_mrms_obj_dict[extra_miss]['MeanInt'],
                            'MRMS_MajAxis': temp_mrms_obj_dict[extra_miss]['MajAxis'],
                            'MRMS_MinAxis': temp_mrms_obj_dict[extra_miss]['MinAxis'],
                            'MRMS_Eccen': temp_mrms_obj_dict[extra_miss]['Eccen'],
                            'MRMS_Orient': temp_mrms_obj_dict[extra_miss]['Orient'],
                            'MRMS_Solidity': temp_mrms_obj_dict[extra_miss]['Solidity'],
                            'MRMS_Centroid': temp_mrms_obj_dict[extra_miss]['Centroid'],
                            'MRMS_Coords': temp_mrms_obj_dict[extra_miss]['Coords'],
                            'WoFS_ID': member_extras_mrms_wofs_id[me],
                            'Total_Interest': member_extras_mrms_ti[me]}

                mrms_extras_dict.append(temp_obj)

# save lists of objects and obj ID/matching criteria:

    temp_outname = 'wofs_' + date_str + '_' + init_str + '_' + domain + '_obj'
    wofs_outname = os.path.join(out_dir, temp_outname)

    wofs_out = shelve.open(wofs_outname, flag='n')
    wofs_out['dx'] = dx
    wofs_out['max_bound_disp'] = max_bound_disp
    wofs_out['max_cent_disp'] = max_cent_disp
    wofs_out['area_thresh'] = area_thresh
    wofs_out['track_bound_disp'] = track_bound_disp
    wofs_out['mrms_thresh_1'] = mrms_thresh_1
    wofs_out['mrms_thresh_2'] = mrms_thresh_2
    wofs_out['wofs_thresh_1'] = wofs_thresh_1
    wofs_out['wofs_thresh_2'] = wofs_thresh_2

    wofs_out['HITS'] = hits_dict
    wofs_out['EXTRAS'] = extras_dict
    wofs_out['FAS'] = fas_dict
    wofs_out['MISSES'] = misses_dict
    wofs_out['MRMS_EXTRAS'] = mrms_extras_dict
    wofs_out.close()

# if NetCDF flag set, output objects in NetCDF:

    if (out_netcdf == 'True'):
        temp_outname = 'wofs_netcdf_' + date_str + \
            '_' + init_str + '_' + domain + '_obj.nc'
        wofs_outname = os.path.join(out_dir, temp_outname)

        epoch = datetime(1970, 1, 1)

        try:
            fout = netCDF4.Dataset(wofs_outname, "w")
        except:
            print("Could not create %s!\n" % wofs_outname)

        fout.createDimension('hit_dim', len(hits_dict))
        fout.createDimension('miss_dim', len(misses_dict))
        fout.createDimension('fas_dim', len(fas_dict))
        fout.createDimension('extras_dim', len(extras_dict))
        fout.createDimension('mrms_extras_dim', len(mrms_extras_dict))
        fout.createDimension('coord_dim', 2)

# write obj ID/matching criteria:

        setattr(fout, 'dx', dx)
        setattr(fout, 'max_bound_disp', max_bound_disp)
        setattr(fout, 'max_cent_disp', max_cent_disp)
        setattr(fout, 'area_thresh', area_thresh)
        setattr(fout, 'track_bound_disp', track_bound_disp)
        setattr(fout, 'mrms_thresh_1', mrms_thresh_1)
        setattr(fout, 'mrms_thresh_2', mrms_thresh_2)
        setattr(fout, 'wofs_thresh_1', wofs_thresh_1)
        setattr(fout, 'wofs_thresh_2', wofs_thresh_2)
        setattr(fout, 'ti_thresh', ti_thresh)

# write matched pair info:

        match_init_time = fout.createVariable(
            'Hit_Init_Time', 'f8', ('hit_dim'))
        match_valid_time = fout.createVariable(
            'Hit_Valid_Time', 'f8', ('hit_dim'))
        match_lead_time = fout.createVariable(
            'Hit_Lead_Time', 'f8', ('hit_dim'))
        match_member = fout.createVariable('Hit_Member', 'f8', ('hit_dim'))
        match_mrms_id = fout.createVariable('Hit_MRMS_ID', 'f8', ('hit_dim'))
        match_mrms_age = fout.createVariable('Hit_MRMS_Age', 'f8', ('hit_dim'))
        match_mrms_area = fout.createVariable(
            'Hit_MRMS_Area', 'f8', ('hit_dim'))
        match_mrms_maxint = fout.createVariable(
            'Hit_MRMS_MaxInt', 'f8', ('hit_dim'))
        match_mrms_meanint = fout.createVariable(
            'Hit_MRMS_MeanInt', 'f8', ('hit_dim'))
        match_mrms_majaxis = fout.createVariable(
            'Hit_MRMS_MajAxis', 'f8', ('hit_dim'))
        match_mrms_minaxis = fout.createVariable(
            'Hit_MRMS_MinAxis', 'f8', ('hit_dim'))
        match_mrms_eccen = fout.createVariable(
            'Hit_MRMS_Eccen', 'f8', ('hit_dim'))
        match_mrms_orient = fout.createVariable(
            'Hit_MRMS_Orient', 'f8', ('hit_dim'))
        match_mrms_solidity = fout.createVariable(
            'Hit_MRMS_Solidity', 'f8', ('hit_dim'))
        match_mrms_centroid = fout.createVariable(
            'Hit_MRMS_Centroid', 'f8', ('hit_dim', 'coord_dim',))
        match_wofs_id = fout.createVariable('Hit_WoFS_ID', 'f8', ('hit_dim'))
        match_wofs_area = fout.createVariable(
            'Hit_WoFS_Area', 'f8', ('hit_dim'))
        match_wofs_maxint = fout.createVariable(
            'Hit_WoFS_MaxInt', 'f8', ('hit_dim'))
        match_wofs_meanint = fout.createVariable(
            'Hit_WoFS_MeanInt', 'f8', ('hit_dim'))
        match_wofs_majaxis = fout.createVariable(
            'Hit_WoFS_MajAxis', 'f8', ('hit_dim'))
        match_wofs_minaxis = fout.createVariable(
            'Hit_WoFS_MinAxis', 'f8', ('hit_dim'))
        match_wofs_eccen = fout.createVariable(
            'Hit_WoFS_Eccen', 'f8', ('hit_dim'))
        match_wofs_orient = fout.createVariable(
            'Hit_WoFS_Orient', 'f8', ('hit_dim'))
        match_wofs_solidity = fout.createVariable(
            'Hit_WoFS_Solidity', 'f8', ('hit_dim'))
        match_wofs_centroid = fout.createVariable(
            'Hit_WoFS_Centroid', 'f8', ('hit_dim', 'coord_dim',))
        match_total_interest = fout.createVariable(
            'Hit_Total_Interest', 'f8', ('hit_dim'))

        fout.variables['Hit_Init_Time'][:] = [
            (temp_obj['Init_Time'] - epoch).total_seconds() for temp_obj in hits_dict]
        fout.variables['Hit_Valid_Time'][:] = [
            (temp_obj['Valid_Time'] - epoch).total_seconds() for temp_obj in hits_dict]
        fout.variables['Hit_Lead_Time'][:] = [
            temp_obj['Lead_Time'] * 60. for temp_obj in hits_dict]
        fout.variables['Hit_Member'][:] = [temp_obj['Member']
                                           for temp_obj in hits_dict]
        fout.variables['Hit_MRMS_ID'][:] = [temp_obj['MRMS_ID']
                                            for temp_obj in hits_dict]
        fout.variables['Hit_MRMS_Age'][:] = [temp_obj['MRMS_Age']
                                             for temp_obj in hits_dict]
        fout.variables['Hit_MRMS_Area'][:] = [temp_obj['MRMS_Area']
                                              for temp_obj in hits_dict]
        fout.variables['Hit_MRMS_MaxInt'][:] = [
            temp_obj['MRMS_MaxInt'] for temp_obj in hits_dict]
        fout.variables['Hit_MRMS_MeanInt'][:] = [
            temp_obj['MRMS_MeanInt'] for temp_obj in hits_dict]
        fout.variables['Hit_MRMS_MajAxis'][:] = [
            temp_obj['MRMS_MajAxis'] for temp_obj in hits_dict]
        fout.variables['Hit_MRMS_MinAxis'][:] = [
            temp_obj['MRMS_MinAxis'] for temp_obj in hits_dict]
        fout.variables['Hit_MRMS_Eccen'][:] = [
            temp_obj['MRMS_Eccen'] for temp_obj in hits_dict]
        fout.variables['Hit_MRMS_Orient'][:] = [
            temp_obj['MRMS_Orient'] for temp_obj in hits_dict]
        fout.variables['Hit_MRMS_Solidity'][:] = [
            temp_obj['MRMS_Solidity'] for temp_obj in hits_dict]
        fout.variables['Hit_MRMS_Centroid'][:] = [
            temp_obj['MRMS_Centroid'] for temp_obj in hits_dict]
        fout.variables['Hit_WoFS_ID'][:] = [temp_obj['WoFS_ID']
                                            for temp_obj in hits_dict]
        fout.variables['Hit_WoFS_Area'][:] = [temp_obj['WoFS_Area']
                                              for temp_obj in hits_dict]
        fout.variables['Hit_WoFS_MaxInt'][:] = [
            temp_obj['WoFS_MaxInt'] for temp_obj in hits_dict]
        fout.variables['Hit_WoFS_MeanInt'][:] = [
            temp_obj['WoFS_MeanInt'] for temp_obj in hits_dict]
        fout.variables['Hit_WoFS_MajAxis'][:] = [
            temp_obj['WoFS_MajAxis'] for temp_obj in hits_dict]
        fout.variables['Hit_WoFS_MinAxis'][:] = [
            temp_obj['WoFS_MinAxis'] for temp_obj in hits_dict]
        fout.variables['Hit_WoFS_Eccen'][:] = [
            temp_obj['WoFS_Eccen'] for temp_obj in hits_dict]
        fout.variables['Hit_WoFS_Orient'][:] = [
            temp_obj['WoFS_Orient'] for temp_obj in hits_dict]
        fout.variables['Hit_WoFS_Solidity'][:] = [
            temp_obj['WoFS_Solidity'] for temp_obj in hits_dict]
        fout.variables['Hit_WoFS_Centroid'][:] = [
            temp_obj['WoFS_Centroid'] for temp_obj in hits_dict]
        fout.variables['Hit_Total_Interest'][:] = [
            temp_obj['Total_Interest'] for temp_obj in hits_dict]

# write extras info:

        extras_init_time = fout.createVariable(
            'Extra_Init_Time', 'f8', ('extras_dim'))
        extras_valid_time = fout.createVariable(
            'Extra_Valid_Time', 'f8', ('extras_dim'))
        extras_lead_time = fout.createVariable(
            'Extra_Lead_Time', 'f8', ('extras_dim'))
        extras_member = fout.createVariable(
            'Extra_Member', 'f8', ('extras_dim'))
        extras_id = fout.createVariable('Extra_WoFS_ID', 'f8', ('extras_dim'))
        extras_area = fout.createVariable(
            'Extra_WoFS_Area', 'f8', ('extras_dim'))
        extras_maxint = fout.createVariable(
            'Extra_WoFS_MaxInt', 'f8', ('extras_dim'))
        extras_meanint = fout.createVariable(
            'Extra_WoFS_MeanInt', 'f8', ('extras_dim'))
        extras_majaxis = fout.createVariable(
            'Extra_WoFS_MajAxis', 'f8', ('extras_dim'))
        extras_minaxis = fout.createVariable(
            'Extra_WoFS_MinAxis', 'f8', ('extras_dim'))
        extras_eccen = fout.createVariable(
            'Extra_WoFS_Eccen', 'f8', ('extras_dim'))
        extras_orient = fout.createVariable(
            'Extra_WoFS_Orient', 'f8', ('extras_dim'))
        extras_solidity = fout.createVariable(
            'Extra_WoFS_Solidity', 'f8', ('extras_dim'))
        extras_centroid = fout.createVariable(
            'Extra_WoFS_Centroid', 'f8', ('extras_dim', 'coord_dim',))
        extras_mrms_id = fout.createVariable(
            'Extra_MRMS_ID', 'f8', ('extras_dim'))
        extras_total_interest = fout.createVariable(
            'Extra_Total_Interest', 'f8', ('extras_dim'))

        fout.variables['Extra_Init_Time'][:] = [
            (temp_obj['Init_Time'] - epoch).total_seconds() for temp_obj in extras_dict]
        fout.variables['Extra_Valid_Time'][:] = [
            (temp_obj['Valid_Time'] - epoch).total_seconds() for temp_obj in extras_dict]
        fout.variables['Extra_Lead_Time'][:] = [
            temp_obj['Lead_Time'] * 60. for temp_obj in extras_dict]
        fout.variables['Extra_Member'][:] = [temp_obj['Member']
                                             for temp_obj in extras_dict]
        fout.variables['Extra_WoFS_ID'][:] = [temp_obj['WoFS_ID']
                                              for temp_obj in extras_dict]
        fout.variables['Extra_WoFS_Area'][:] = [
            temp_obj['WoFS_Area'] for temp_obj in extras_dict]
        fout.variables['Extra_WoFS_MaxInt'][:] = [
            temp_obj['WoFS_MaxInt'] for temp_obj in extras_dict]
        fout.variables['Extra_WoFS_MeanInt'][:] = [
            temp_obj['WoFS_MeanInt'] for temp_obj in extras_dict]
        fout.variables['Extra_WoFS_MajAxis'][:] = [
            temp_obj['WoFS_MajAxis'] for temp_obj in extras_dict]
        fout.variables['Extra_WoFS_MinAxis'][:] = [
            temp_obj['WoFS_MinAxis'] for temp_obj in extras_dict]
        fout.variables['Extra_WoFS_Eccen'][:] = [
            temp_obj['WoFS_Eccen'] for temp_obj in extras_dict]
        fout.variables['Extra_WoFS_Orient'][:] = [
            temp_obj['WoFS_Orient'] for temp_obj in extras_dict]
        fout.variables['Extra_WoFS_Solidity'][:] = [
            temp_obj['WoFS_Solidity'] for temp_obj in extras_dict]
        fout.variables['Extra_WoFS_Centroid'][:] = [
            temp_obj['WoFS_Centroid'] for temp_obj in extras_dict]
        fout.variables['Extra_MRMS_ID'][:] = [temp_obj['MRMS_ID']
                                              for temp_obj in extras_dict]
        fout.variables['Extra_Total_Interest'][:] = [
            temp_obj['Total_Interest'] for temp_obj in extras_dict]

# write false alarm info:

        fas_init_time = fout.createVariable('Fa_Init_Time', 'f8', ('fas_dim'))
        fas_valid_time = fout.createVariable(
            'Fa_Valid_Time', 'f8', ('fas_dim'))
        fas_lead_time = fout.createVariable('Fa_Lead_Time', 'f8', ('fas_dim'))
        fas_member = fout.createVariable('Fa_Member', 'f8', ('fas_dim'))
        fas_area = fout.createVariable('Fa_WoFS_Area', 'f8', ('fas_dim'))
        fas_maxint = fout.createVariable('Fa_WoFS_MaxInt', 'f8', ('fas_dim'))
        fas_meanint = fout.createVariable('Fa_WoFS_MeanInt', 'f8', ('fas_dim'))
        fas_maxaxis = fout.createVariable('Fa_WoFS_MajAxis', 'f8', ('fas_dim'))
        fas_minaxis = fout.createVariable('Fa_WoFS_MinAxis', 'f8', ('fas_dim'))
        fas_eccen = fout.createVariable('Fa_WoFS_Eccen', 'f8', ('fas_dim'))
        fas_orient = fout.createVariable('Fa_WoFS_Orient', 'f8', ('fas_dim'))
        fas_solidity = fout.createVariable(
            'Fa_WoFS_Solidity', 'f8', ('fas_dim'))
        fas_centroid = fout.createVariable(
            'Fa_WoFS_Centroid', 'f8', ('fas_dim', 'coord_dim',))
        fas_total_interest = fout.createVariable(
            'Fa_Total_Interest', 'f8', ('fas_dim'))

        fout.variables['Fa_Init_Time'][:] = [
            (temp_obj['Init_Time'] - epoch).total_seconds() for temp_obj in fas_dict]
        fout.variables['Fa_Valid_Time'][:] = [
            (temp_obj['Valid_Time'] - epoch).total_seconds() for temp_obj in fas_dict]
        fout.variables['Fa_Lead_Time'][:] = [
            temp_obj['Lead_Time'] * 60. for temp_obj in fas_dict]
        fout.variables['Fa_Member'][:] = [temp_obj['Member']
                                          for temp_obj in fas_dict]
        fout.variables['Fa_WoFS_Area'][:] = [temp_obj['WoFS_Area']
                                             for temp_obj in fas_dict]
        fout.variables['Fa_WoFS_MaxInt'][:] = [
            temp_obj['WoFS_MaxInt'] for temp_obj in fas_dict]
        fout.variables['Fa_WoFS_MeanInt'][:] = [
            temp_obj['WoFS_MeanInt'] for temp_obj in fas_dict]
        fout.variables['Fa_WoFS_MajAxis'][:] = [
            temp_obj['WoFS_MajAxis'] for temp_obj in fas_dict]
        fout.variables['Fa_WoFS_MinAxis'][:] = [
            temp_obj['WoFS_MinAxis'] for temp_obj in fas_dict]
        fout.variables['Fa_WoFS_Eccen'][:] = [
            temp_obj['WoFS_Eccen'] for temp_obj in fas_dict]
        fout.variables['Fa_WoFS_Orient'][:] = [
            temp_obj['WoFS_Orient'] for temp_obj in fas_dict]
        fout.variables['Fa_WoFS_Solidity'][:] = [
            temp_obj['WoFS_Solidity'] for temp_obj in fas_dict]
        fout.variables['Fa_WoFS_Centroid'][:] = [
            temp_obj['WoFS_Centroid'] for temp_obj in fas_dict]
        fout.variables['Fa_Total_Interest'][:] = [
            temp_obj['Total_Interest'] for temp_obj in fas_dict]

# write miss info:

        miss_init_time = fout.createVariable(
            'Miss_Init_Time', 'f8', ('miss_dim'))
        miss_valid_time = fout.createVariable(
            'Miss_Valid_Time', 'f8', ('miss_dim'))
        miss_lead_time = fout.createVariable(
            'Miss_Lead_Time', 'f8', ('miss_dim'))
        miss_member = fout.createVariable('Miss_Member', 'f8', ('miss_dim'))
        miss_mrms_id = fout.createVariable('Miss_MRMS_ID', 'f8', ('miss_dim'))
        miss_mrms_age = fout.createVariable(
            'Miss_MRMS_Age', 'f8', ('miss_dim'))
        miss_mrms_area = fout.createVariable(
            'Miss_MRMS_Area', 'f8', ('miss_dim'))
        miss_mrms_maxint = fout.createVariable(
            'Miss_MRMS_MaxInt', 'f8', ('miss_dim'))
        miss_mrms_meanint = fout.createVariable(
            'Miss_MRMS_MeanInt', 'f8', ('miss_dim'))
        miss_mrms_majaxis = fout.createVariable(
            'Miss_MRMS_MajAxis', 'f8', ('miss_dim'))
        miss_mrms_minaxis = fout.createVariable(
            'Miss_MRMS_MinAxis', 'f8', ('miss_dim'))
        miss_mrms_eccen = fout.createVariable(
            'Miss_MRMS_Eccen', 'f8', ('miss_dim'))
        miss_mrms_orient = fout.createVariable(
            'Miss_MRMS_Orient', 'f8', ('miss_dim'))
        miss_mrms_solidity = fout.createVariable(
            'Miss_MRMS_Solidity', 'f8', ('miss_dim'))
        miss_mrms_centroid = fout.createVariable(
            'Miss_MRMS_Centroid', 'f8', ('miss_dim', 'coord_dim',))

        fout.variables['Miss_Init_Time'][:] = [
            (temp_obj['Init_Time'] - epoch).total_seconds() for temp_obj in misses_dict]
        fout.variables['Miss_Valid_Time'][:] = [
            (temp_obj['Valid_Time'] - epoch).total_seconds() for temp_obj in misses_dict]
        fout.variables['Miss_Lead_Time'][:] = [
            temp_obj['Lead_Time'] * 60. for temp_obj in misses_dict]
        fout.variables['Miss_Member'][:] = [temp_obj['Member']
                                            for temp_obj in misses_dict]
        fout.variables['Miss_MRMS_ID'][:] = [temp_obj['MRMS_ID']
                                             for temp_obj in misses_dict]
        fout.variables['Miss_MRMS_Age'][:] = [temp_obj['MRMS_Age']
                                              for temp_obj in misses_dict]
        fout.variables['Miss_MRMS_Area'][:] = [temp_obj['MRMS_Area']
                                               for temp_obj in misses_dict]
        fout.variables['Miss_MRMS_MaxInt'][:] = [
            temp_obj['MRMS_MaxInt'] for temp_obj in misses_dict]
        fout.variables['Miss_MRMS_MeanInt'][:] = [
            temp_obj['MRMS_MeanInt'] for temp_obj in misses_dict]
        fout.variables['Miss_MRMS_MajAxis'][:] = [
            temp_obj['MRMS_MajAxis'] for temp_obj in misses_dict]
        fout.variables['Miss_MRMS_MinAxis'][:] = [
            temp_obj['MRMS_MinAxis'] for temp_obj in misses_dict]
        fout.variables['Miss_MRMS_Eccen'][:] = [
            temp_obj['MRMS_Eccen'] for temp_obj in misses_dict]
        fout.variables['Miss_MRMS_Orient'][:] = [
            temp_obj['MRMS_Orient'] for temp_obj in misses_dict]
        fout.variables['Miss_MRMS_Solidity'][:] = [
            temp_obj['MRMS_Solidity'] for temp_obj in misses_dict]
        fout.variables['Miss_MRMS_Centroid'][:] = [
            temp_obj['MRMS_Centroid'] for temp_obj in misses_dict]

# write mrms_extras info:

        mrms_extras_init_time = fout.createVariable(
            'MRMS_Extras_Init_Time', 'f8', ('mrms_extras_dim'))
        mrms_extras_valid_time = fout.createVariable(
            'MRMS_Extras_Valid_Time', 'f8', ('mrms_extras_dim'))
        mrms_extras_lead_time = fout.createVariable(
            'MRMS_Extras_Lead_Time', 'f8', ('mrms_extras_dim'))
        mrms_extras_member = fout.createVariable(
            'MRMS_Extras_Member', 'f8', ('mrms_extras_dim'))
        mrms_extras_id = fout.createVariable(
            'MRMS_Extras_ID', 'f8', ('mrms_extras_dim'))
        mrms_extras_age = fout.createVariable(
            'MRMS_Extras_Age', 'f8', ('mrms_extras_dim'))
        mrms_extras_area = fout.createVariable(
            'MRMS_Extras_Area', 'f8', ('mrms_extras_dim'))
        mrms_extras_maxint = fout.createVariable(
            'MRMS_Extras_MaxInt', 'f8', ('mrms_extras_dim'))
        mrms_extras_meanint = fout.createVariable(
            'MRMS_Extras_MeanInt', 'f8', ('mrms_extras_dim'))
        mrms_extras_majaxis = fout.createVariable(
            'MRMS_Extras_MajAxis', 'f8', ('mrms_extras_dim'))
        mrms_extras_minaxis = fout.createVariable(
            'MRMS_Extras_MinAxis', 'f8', ('mrms_extras_dim'))
        mrms_extras_eccen = fout.createVariable(
            'MRMS_Extras_Eccen', 'f8', ('mrms_extras_dim'))
        mrms_extras_orient = fout.createVariable(
            'MRMS_Extras_Orient', 'f8', ('mrms_extras_dim'))
        mrms_extras_solidity = fout.createVariable(
            'MRMS_Extras_Solidity', 'f8', ('mrms_extras_dim'))
        mrms_extras_centroid = fout.createVariable(
            'MRMS_Extras_Centroid', 'f8', ('mrms_extras_dim', 'coord_dim',))
        mrms_extras_wofs_id = fout.createVariable(
            'MRMS_Extras_WoFS_ID', 'f8', ('mrms_extras_dim'))
        mrms_extras_total_interest = fout.createVariable(
            'MRMS_Extras_Total_Interest', 'f8', ('mrms_extras_dim'))

        fout.variables['MRMS_Extras_Init_Time'][:] = [
            (temp_obj['Init_Time'] - epoch).total_seconds() for temp_obj in mrms_extras_dict]
        fout.variables['MRMS_Extras_Valid_Time'][:] = [
            (temp_obj['Valid_Time'] - epoch).total_seconds() for temp_obj in mrms_extras_dict]
        fout.variables['MRMS_Extras_Lead_Time'][:] = [
            temp_obj['Lead_Time'] * 60. for temp_obj in mrms_extras_dict]
        fout.variables['MRMS_Extras_Member'][:] = [
            temp_obj['Member'] for temp_obj in mrms_extras_dict]
        fout.variables['MRMS_Extras_ID'][:] = [temp_obj['MRMS_ID']
                                               for temp_obj in mrms_extras_dict]
        fout.variables['MRMS_Extras_Age'][:] = [temp_obj['MRMS_Age']
                                                for temp_obj in mrms_extras_dict]
        fout.variables['MRMS_Extras_Area'][:] = [
            temp_obj['MRMS_Area'] for temp_obj in mrms_extras_dict]
        fout.variables['MRMS_Extras_MaxInt'][:] = [
            temp_obj['MRMS_MaxInt'] for temp_obj in mrms_extras_dict]
        fout.variables['MRMS_Extras_MeanInt'][:] = [
            temp_obj['MRMS_MeanInt'] for temp_obj in mrms_extras_dict]
        fout.variables['MRMS_Extras_MajAxis'][:] = [
            temp_obj['MRMS_MajAxis'] for temp_obj in mrms_extras_dict]
        fout.variables['MRMS_Extras_MinAxis'][:] = [
            temp_obj['MRMS_MinAxis'] for temp_obj in mrms_extras_dict]
        fout.variables['MRMS_Extras_Eccen'][:] = [
            temp_obj['MRMS_Eccen'] for temp_obj in mrms_extras_dict]
        fout.variables['MRMS_Extras_Orient'][:] = [
            temp_obj['MRMS_Orient'] for temp_obj in mrms_extras_dict]
        fout.variables['MRMS_Extras_Solidity'][:] = [
            temp_obj['MRMS_Solidity'] for temp_obj in mrms_extras_dict]
        fout.variables['MRMS_Extras_Centroid'][:] = [
            temp_obj['MRMS_Centroid'] for temp_obj in mrms_extras_dict]
        fout.variables['MRMS_Extras_WoFS_ID'][:] = [
            temp_obj['WoFS_ID'] for temp_obj in mrms_extras_dict]
        fout.variables['MRMS_Extras_Total_Interest'][:] = [
            temp_obj['Total_Interest'] for temp_obj in mrms_extras_dict]

        fout.close()
        del fout
