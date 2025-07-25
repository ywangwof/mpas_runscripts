#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Tue Jan  2 15:08:32 2024

@author: asdf
"""
#import re
import matplotlib
import matplotlib.pyplot as plt
#from matplotlib.patches import Rectangle
import numpy as np
import os, sys
#import statistics
#import datetime
#import netCDF4
#import warnings
#import itertools
import shelve
#import pyproj
#from scipy import signal
#from scipy import *
#from scipy import ndimage
#from scipy.spatial import distance
#import skimage
#from skimage.morphology import label
#from skimage.measure import regionprops
#import sklearn
from sklearn.utils import resample
#from optparse import OptionParser
import seaborn as sns
#import cmocean
#import obj_cbook
from obj_cbook import *
#import wofs_colortables
from wofs_colortables import cb_colors

import argparse

########################################################################

def parse_args():
    """ Parse command line arguments
    """
    parser = argparse.ArgumentParser(description='Plot WoFS objects',
                                     epilog="""        ---- Yunheng Wang & Patrick Skinner (2024-10-16).
                                            """)
                                     #formatter_class=CustomFormatter)

    parser.add_argument('obj_base1',        help='Directory for cb-WoFS object files')
    parser.add_argument('obj_base2',        help='Directory for mpas-WoFS object files')
    parser.add_argument('obj_base3',        help='Directory for mpas-WoFS object files', default = None)

    parser.add_argument('-v','--verbose',   help='Verbose output',                action="store_true", default=False)
    parser.add_argument('-o','--outdir' ,   help='Image file output directory',              type=str, default='./')
    parser.add_argument('-p','--prefix' ,   help='Image file name prefix',                   type=str, default='wofs_mpas_2024_40_45')

    parser.add_argument('-m','--images' ,   help='Plot images, [time,age,area,ratio,interest,centroid,bound,performance]', type=str, default='all')

    args = parser.parse_args()

    return args

########################################################################

#bootstrap CI and return a bunch of things, calculated using resampling method of Hamill 1999

def bootstrap_ci(hit, miss, fa, samples, interval):
    hit_vector = np.ones(len(hit))
    miss_vector = np.zeros(len(miss))
    fa_vector = np.zeros(len(fa)) + 2.
    full_vector = np.concatenate([hit_vector, miss_vector, fa_vector])
    pod = np.zeros(samples)
    far = np.zeros(samples)
    bias = np.zeros(samples)
    csi = np.zeros(samples)
    for i in range(0, samples):
        temp_sample = resample(full_vector, n_samples=len(full_vector))
        temp_ci_hits = len(np.argwhere(temp_sample == 1))
        temp_ci_misses = len(np.argwhere(temp_sample == 0))
        temp_ci_fas = len(np.argwhere(temp_sample == 2))
        if ((temp_ci_hits + temp_ci_misses) == 0.):
           pod[i] = 0.
           bias[i] = 0.
           csi[i] = 0.
        elif ((temp_ci_hits + temp_ci_fas) == 0.):
           far[i] = 0.
        else:
           pod[i] = temp_ci_hits / (temp_ci_hits+temp_ci_misses)
           far[i] = temp_ci_fas / (temp_ci_hits+temp_ci_fas)
           bias[i] = (temp_ci_hits+temp_ci_fas) / (temp_ci_hits+temp_ci_misses)
           csi[i] = temp_ci_hits / (temp_ci_hits+temp_ci_misses+temp_ci_fas)

    ci_pod = np.percentile(pod, ((100-interval) / 2. + interval)) - np.percentile(pod, ((100-interval) / 2.))
    ci_far = np.percentile(far, ((100-interval) / 2. + interval)) - np.percentile(far, ((100-interval) / 2.))
    ci_bias = np.percentile(bias, ((100-interval) / 2. + interval)) - np.percentile(bias, ((100-interval) / 2.))
    ci_csi = np.percentile(csi, ((100-interval) / 2. + interval)) - np.percentile(csi, ((100-interval) / 2.))

    return ci_pod, ci_far, ci_bias, ci_csi

########################################################################

#same as above, but CI for distributions with "extra" objects

#bootstrap CI and return a bunch of things
def bootstrap_ci_extra(hit, miss, fa, extra, mrms_extra, samples, interval):
    hit_vector = np.ones(len(hit))
    miss_vector = np.zeros(len(miss))
    fa_vector = np.zeros(len(fa)) + 2.
    extra_vector = np.zeros(len(extra)) + 3.
    mrms_extra_vector = np.zeros(len(mrms_extra)) + 4.

    full_vector = np.concatenate([hit_vector, miss_vector, fa_vector, extra_vector, mrms_extra_vector])

    bias = np.zeros(samples)
    for i in range(0, samples):
        temp_sample = resample(full_vector, n_samples=len(full_vector))
        temp_ci_hits = len(np.argwhere(temp_sample == 1))
        temp_ci_misses = len(np.argwhere(temp_sample == 0))
        temp_ci_fas = len(np.argwhere(temp_sample == 2))
        temp_ci_extras = len(np.argwhere(temp_sample == 3))
        temp_ci_mrms_extras = len(np.argwhere(temp_sample == 4))

        if ((temp_ci_hits + temp_ci_misses) == 0.):
            bias[i] = 0.
        else:
            bias[i] = (temp_ci_hits+temp_ci_fas+temp_ci_extras) / (temp_ci_hits+temp_ci_misses+temp_ci_mrms_extras)

    ci_bias = np.percentile(bias, ((100-interval) / 2. + interval)) - np.percentile(bias, ((100-interval) / 2.))

    return ci_bias

########################################################################
def add_legend(ax, x, y, colors, lines, labels):

    k = 0
    for color,line,label in zip(colors,lines,labels):
        ax.text(x,      y-k*0.04, line,        color=color, horizontalalignment='left', verticalalignment='center', transform = ax.transAxes)
        ax.text(x+0.01, y-k*0.04, " : "+label, color=color, horizontalalignment='left', verticalalignment='center', transform = ax.transAxes)
        k += 1

########################################################################

def time_series_fig(vars, ci_vars, y_ticks, y_labels, ylimits,y_title,colors,lines, labels, out_name):

    #fig1 = plt.figure(figsize=(10,5))
    fig1 = plt.figure(figsize=(20,5.5))
    ax1 = fig1.add_axes([0.08, 0.14, .88, .82])
    ax1.spines['top'].set_alpha(0.7)
    ax1.spines['bottom'].set_alpha(0.7)
    ax1.spines['left'].set_alpha(0.7)
    ax1.spines['right'].set_alpha(0.7)
    ax1.spines['top'].set_linewidth(0.5)
    ax1.spines['bottom'].set_linewidth(0.5)
    ax1.spines['left'].set_linewidth(0.5)
    ax1.spines['right'].set_linewidth(0.5)

    #member indices for different PBL schemes:
    ysu_mem = [0, 1, 6, 7, 12, 13]
    myj_mem = [2, 3, 8, 9, 14, 15]
    mynn_mem = [4, 5, 10, 11, 16, 17]

    plt.xlim(*xlimits)
    #plt.xlim(-3, 75)
    plt.ylim(*ylimits)

    x_ticks  = [ 0,   12,    24,    36,    48,    60,    72]
    x_labels = ['0', '60', '120', '180', '240', '300', '360']
    #x_ticks  = [ 0,     6,   12,   18,    24,    30,    36,    42,    48,    54,   60,    66,    72]
    #x_labels = ['0', '30', '60', '90', '120', '150', '180', '210', '240', '270', '300', '330', '360']
    #   y_ticks = [0, .1, .2, .3, .4, .5, .6, .7, .8, .9, 1.]
    #   y_labels = ['0', '0.1', '0.2', '0.3', '0.4', '0.5', '0.6', '0.7', '0.8', '0.9', '1.0']

    ax1.set_xlabel('Forecast Lead Time (min)', fontsize=22)
    ax1.set_ylabel(y_title, fontsize=22)

    plt.xticks(x_ticks, x_labels, fontsize=22, alpha=0.7)
    plt.yticks(y_ticks, y_labels, fontsize=22, alpha=0.7)

    for j in y_ticks:
        plt.plot([-1000, 1000], [j, j], c='k', linewidth=0.75, alpha=0.2)

    for i in x_ticks:
        plt.plot([i, i], [-1000, 1000], c='k', linewidth=0.75, alpha=0.2)

    k = 0
    for var,ci_var in zip(vars,ci_vars):
        temp_indices = np.arange(0, var.shape[1])
        #var2_indices = temp_indices[::12]  #assumes hourly output

        ax1.fill_between(temp_indices, (np.mean(var, axis=0)-np.mean(ci_var, axis=0)), \
            (np.mean(var, axis=0)+np.mean(ci_var, axis=0)), color = colors[k], linewidth=0.3, alpha=0.12)

        for n in range(0, var.shape[0]):
            if (n in ysu_mem):
                temp_color = cb_colors.orange5
            if (n in myj_mem):
                temp_color = cb_colors.green5
            if (n in mynn_mem):
                temp_color = cb_colors.blue5
            ax1.plot(var[n,:], color=temp_color, linestyle=lines[k], linewidth=1.25, alpha=0.6)

        ax1.plot(np.mean(var, axis=0), color=colors[k], linestyle=lines[k],linewidth=2.25, alpha=0.8)
        k += 1

    add_legend(ax1, 0.85,0.88, colors, lines, labels)
    #ax1.legend()
    #ax1.plot(var2_indices, var2+ci_var2, color=cb_colors.gray6, linestyle='--', linewidth=0.75, alpha=0.7)
    #ax1.plot(var2_indices, var2-ci_var2, color=cb_colors.gray6, linestyle='--', linewidth=0.75, alpha=0.7)
    #ax1.plot(var2_indices, var2, color=cb_colors.gray6, linestyle='--', linewidth=2., alpha=0.8)
    #ax1.errorbar(var2_indices,
    #      var2,
    #      ci_var2,
    #      fmt='.',
    #      capsize=7,
    #      elinewidth=2.5,
    #      markersize=8.,
    #      markeredgewidth=1.5,
    #      color='tab:purple',
    #      alpha=0.8)

    print(f"Saving {out_name} ....")
    plt.savefig(out_name, format='png', dpi=150)

########################################################################

def time_series_init(y_min, y_max, y_ticks, y_labels, y_title):
    fig1 = plt.figure(figsize=(10,5))
    ax1 = fig1.add_axes([0.08, 0.1, .88, .86])
    ax1.spines['top'].set_alpha(0.7)
    ax1.spines['bottom'].set_alpha(0.7)
    ax1.spines['left'].set_alpha(0.7)
    ax1.spines['right'].set_alpha(0.7)
    ax1.spines['top'].set_linewidth(0.5)
    ax1.spines['bottom'].set_linewidth(0.5)
    ax1.spines['left'].set_linewidth(0.5)
    ax1.spines['right'].set_linewidth(0.5)

    plt.xlim(*xlimits)
    #plt.xlim(-3, 75)
    plt.ylim(y_min, y_max)

    x_ticks = [0, 12, 24, 36, 48, 60, 72]
    x_labels = ['0', '60', '120', '180', '240', '300', '360']
    ##   x_ticks = [0, 6, 12, 18, 24, 30, 36, 42, 48, 54, 60, 66, 72]
    ##   x_labels = ['0', '30', '60', '90', '120', '150', '180', '210', '240', '270', '300', '330', '360']
    #   y_ticks = [0, .1, .2, .3, .4, .5, .6, .7, .8, .9, 1.]
    #   y_labels = ['0', '0.1', '0.2', '0.3', '0.4', '0.5', '0.6', '0.7', '0.8', '0.9', '1.0']

    ax1.set_xlabel('Forecast Lead Time (min)')
    ax1.set_ylabel(y_title)

    plt.xticks(x_ticks, x_labels, fontsize=14, alpha=0.7)
    plt.yticks(y_ticks, y_labels, fontsize=14, alpha=0.7)

    for j in y_ticks:
        ax1.plot([-1000000, 1000000], [j, j], c='k', linewidth=0.5, alpha=0.2)

    for i in x_ticks:
        ax1.plot([i, i], [-1000000, 1000000], c='k', linewidth=0.5, alpha=0.2)

    return fig1, ax1

########################################################################

def pod_time_series(hit_lead_time, miss_lead_time, lead_times):

    pod = lead_times * 0.
    ci_pod = lead_times * 0.
    counts = lead_times * 0.
    for i, temp_lead in enumerate(lead_times):
        temp_hit_ind = np.argwhere(hit_lead_time == temp_lead)
        temp_miss_ind = np.argwhere(miss_lead_time == temp_lead)
        if ((len(temp_hit_ind) + len(temp_miss_ind)) > 0):
            pod[i] = len(temp_hit_ind) / (len(temp_hit_ind) + len(temp_miss_ind))
            ci_pod[i] = bootstrap_ci_pod(temp_hit_ind, temp_miss_ind, 1000, 95) #hard coded to be 99% CI with 1000 samples
            counts[i] = len(temp_hit_ind) + len(temp_miss_ind)
        else:
            pod[i] = 0.
            ci_pod[i] = 0.
            counts[i] = 0.

    return pod, ci_pod, counts

########################################################################

#bootstrap CI and return a bunch of things
def bootstrap_ci_pod(hit, miss, samples, interval):
    hit_vector = np.ones(len(hit))
    miss_vector = np.zeros(len(miss))
    full_vector = np.concatenate([hit_vector, miss_vector])
    pod = np.zeros(samples)
    for i in range(0, samples):
       temp_sample = resample(full_vector, n_samples=len(full_vector))
       temp_ci_hits = len(np.argwhere(temp_sample == 1))
       temp_ci_misses = len(np.argwhere(temp_sample == 0))
       pod[i] = temp_ci_hits / (temp_ci_hits+temp_ci_misses)
    ci_pod = np.percentile(pod, ((100-interval) / 2. + interval)) - np.percentile(pod, ((100-interval) / 2.))

    return ci_pod

########################################################################
#
# Load the dictionary into a Namespace data structure.
# This step is not necessary, but cuts down the syntax needed to reference each item in the dict.
#
# Example: Retrieve the 0 hr forecast Dataset from GFS Dynamics
#            dict: ds_dict['GFS']['dynf'][0]
#       Namespace: datasets.GFS.dynf[0]

def make_namespace(d: dict,lvl=0,level=None):
    """ lvl  : level of this call
        level: level to stop, None is infinity
    """
    assert(isinstance(d, dict))
    ns =  argparse.Namespace()
    for k, v in d.items():
        lvl += 1
        if level is None or (level is not None and lvl < level):
            if v and isinstance(v, dict):
                leaf_ns = make_namespace(v,lvl,level)
                ns.__dict__[k] = leaf_ns
            else:
                ns.__dict__[k] = v
        else:
            ns.__dict__[k] = v

    return ns

########################################################################

def read_objs(obj_dir,ne,lead_times,age_bins,area_bins,
              obj_time=True,obj_age=True,obj_area=True, obj_area_ratio=True,obj_interest=True,obj_centroid=True,obj_bound=True):

    ci_samples = 1000   #number of samples for resampled confidence interval
    ci_interval = 95    #confidence interval

    #### Aggregate Object Properties across all forecasts: #################

    ret_obj = {}

    #find .dat object files at WoFS init times in fcst_init_times:
    obj_files_temp = os.listdir(obj_dir)

    obj_files = []

    for f, temp_file in enumerate(obj_files_temp):
       if ((temp_file[14:18] in fcst_init_times) and (temp_file[-3::] == 'dat')):
    #       if (temp_file[-15:-11] in fcst_init_times):
           obj_files.append(temp_file)

    #for f, temp_file in enumerate(obj_files_temp):
    #   if (temp_file[-3:] == 'dat'):
    #       if (temp_file[-15:-11] in fcst_init_times):
    #           obj_files.append(temp_file)

    obj_files.sort()

    #aggregate objects from all files:

    #initialize arrays:

    hit_member = np.array([])
    hit_valid_time = np.array([])
    hit_lead_time = np.array([])
    hit_init_time = np.array([])
    hit_area = np.array([])
    hit_maxint = np.array([])
    hit_meanint = np.array([])
    hit_centroid = []   #use list to get list of tuples
    hit_ti = np.array([])

    hit_mrms_age = np.array([])
    hit_mrms_area = np.array([])
    hit_mrms_maxint = np.array([])
    hit_mrms_meanint = np.array([])
    hit_mrms_centroid = []    #use list to get list of tuples

    extra_member = np.array([])
    extra_valid_time = np.array([])
    extra_lead_time = np.array([])
    extra_init_time = np.array([])
    extra_area = np.array([])
    extra_maxint = np.array([])
    extra_ti = np.array([])
    extra_centroid = []

    fa_member = np.array([])
    fa_valid_time = np.array([])
    fa_lead_time = np.array([])
    fa_init_time = np.array([])
    fa_area = np.array([])
    fa_maxint = np.array([])
    fa_centroid = []

    miss_member = np.array([])
    miss_valid_time = np.array([])
    miss_lead_time = np.array([])
    miss_init_time = np.array([])
    miss_age = np.array([])
    miss_area = np.array([])
    miss_maxint = np.array([])
    miss_centroid = []    #use list to get list of tuples

    mrms_extra_member = np.array([])
    mrms_extra_valid_time = np.array([])
    mrms_extra_lead_time = np.array([])
    mrms_extra_init_time = np.array([])
    mrms_extra_age = np.array([])
    mrms_extra_area = np.array([])
    mrms_extra_maxint = np.array([])
    mrms_extra_ti = np.array([])
    mrms_extra_centroid = []

    #initialize forecast by forecast stat arrays for qc:

    #fcst_hits = np.zeros(len(obj_files))
    #fcst_misses = np.zeros(len(obj_files))
    #fcst_fas = np.zeros(len(obj_files))
    #fcst_extras = np.zeros(len(obj_files))
    #fcst_mrms_extras = np.zeros(len(obj_files))

    #fcst_pod = np.zeros(len(obj_files))
    #fcst_far = np.zeros(len(obj_files))
    #fcst_bias = np.zeros(len(obj_files))
    #fcst_extra_bias = np.zeros(len(obj_files))
    #fcst_csi = np.zeros(len(obj_files))

    #read every object file/object from input directory:

    for f, temp_file in enumerate(obj_files):
        temp_path = os.path.join(obj_dir, temp_file[:-4])
        temp_fcst = shelve.open(temp_path, flag='r')
        print('    reading ', temp_path)
        temp_hits = temp_fcst['HITS']
        if (len(temp_hits) == 0):
            print('no hits: ', temp_file)
        temp_extras = temp_fcst['EXTRAS']
        temp_fas = temp_fcst['FAS']
        temp_misses = temp_fcst['MISSES']
        temp_mrms_extras = temp_fcst['MRMS_EXTRAS']
        hit_member = np.concatenate([hit_member, [x['Member'] for x in temp_hits]])
        hit_valid_time = np.concatenate([hit_valid_time, [x['Valid_Time'] for x in temp_hits]])
        hit_lead_time = np.concatenate([hit_lead_time, [x['Lead_Time'] for x in temp_hits]])
        hit_init_time = np.concatenate([hit_init_time, [x['Init_Time'] for x in temp_hits]])
        hit_area = np.concatenate([hit_area, [x['WoFS_Area'] for x in temp_hits]])
        hit_maxint = np.concatenate([hit_maxint, [x['WoFS_MaxInt'] for x in temp_hits]])
        hit_meanint = np.concatenate([hit_meanint, [x['WoFS_MeanInt'] for x in temp_hits]])
        hit_centroid = hit_centroid + [x['WoFS_Centroid'] for x in temp_hits]
        #hit_centroid.append([x['WoFS_Centroid'] for x in temp_hits])
        hit_ti = np.concatenate([hit_ti, [x['Total_Interest'] for x in temp_hits]])
        hit_mrms_age = np.concatenate([hit_mrms_age, [x['MRMS_Age'] for x in temp_hits]])
        hit_mrms_area = np.concatenate([hit_mrms_area, [x['MRMS_Area'] for x in temp_hits]])
        hit_mrms_maxint = np.concatenate([hit_mrms_maxint, [x['MRMS_MaxInt'] for x in temp_hits]])
        hit_mrms_meanint = np.concatenate([hit_mrms_meanint, [x['MRMS_MeanInt'] for x in temp_hits]])
        hit_mrms_centroid = hit_mrms_centroid + [x['MRMS_Centroid'] for x in temp_hits]
        #hit_mrms_centroid.append([x['MRMS_Centroid'] for x in temp_hits])
        extra_member = np.concatenate([extra_member, [x['Member'] for x in temp_extras]])
        extra_valid_time = np.concatenate([extra_valid_time, [x['Valid_Time'] for x in temp_extras]])
        extra_lead_time = np.concatenate([extra_lead_time, [x['Lead_Time'] for x in temp_extras]])
        extra_init_time = np.concatenate([extra_init_time, [x['Init_Time'] for x in temp_extras]])
        extra_area = np.concatenate([extra_area, [x['WoFS_Area'] for x in temp_extras]])
        extra_maxint = np.concatenate([extra_maxint, [x['WoFS_MaxInt'] for x in temp_extras]])
        extra_ti = np.concatenate([extra_ti, [x['Total_Interest'] for x in temp_extras]])
        extra_centroid = extra_centroid + [x['WoFS_Centroid'] for x in temp_extras]
        fa_member = np.concatenate([fa_member, [x['Member'] for x in temp_fas]])
        fa_valid_time = np.concatenate([fa_valid_time, [x['Valid_Time'] for x in temp_fas]])
        fa_lead_time = np.concatenate([fa_lead_time, [x['Lead_Time'] for x in temp_fas]])
        fa_init_time = np.concatenate([fa_init_time, [x['Init_Time'] for x in temp_fas]])
        fa_area = np.concatenate([fa_area, [x['WoFS_Area'] for x in temp_fas]])
        fa_maxint = np.concatenate([fa_maxint, [x['WoFS_MaxInt'] for x in temp_fas]])
        fa_centroid = fa_centroid + [x['WoFS_Centroid'] for x in temp_fas]
        miss_member = np.concatenate([miss_member, [x['Member'] for x in temp_misses]])
        miss_valid_time = np.concatenate([miss_valid_time, [x['Valid_Time'] for x in temp_misses]])
        miss_lead_time = np.concatenate([miss_lead_time, [x['Lead_Time'] for x in temp_misses]])
        miss_init_time = np.concatenate([miss_init_time, [x['Init_Time'] for x in temp_misses]])
        miss_age = np.concatenate([miss_age, [x['MRMS_Age'] for x in temp_misses]])
        miss_area = np.concatenate([miss_area, [x['MRMS_Area'] for x in temp_misses]])
        miss_maxint = np.concatenate([miss_maxint, [x['MRMS_MaxInt'] for x in temp_misses]])
        miss_centroid = miss_centroid + [x['MRMS_Centroid'] for x in temp_misses]
        mrms_extra_member = np.concatenate([mrms_extra_member, [x['Member'] for x in temp_mrms_extras]])
        mrms_extra_valid_time = np.concatenate([mrms_extra_valid_time, [x['Valid_Time'] for x in temp_mrms_extras]])
        mrms_extra_lead_time = np.concatenate([mrms_extra_lead_time, [x['Lead_Time'] for x in temp_mrms_extras]])
        mrms_extra_init_time = np.concatenate([mrms_extra_init_time, [x['Init_Time'] for x in temp_mrms_extras]])
        mrms_extra_age = np.concatenate([mrms_extra_age, [x['MRMS_Age'] for x in temp_mrms_extras]])
        mrms_extra_area = np.concatenate([mrms_extra_area, [x['MRMS_Area'] for x in temp_mrms_extras]])
        mrms_extra_maxint = np.concatenate([mrms_extra_maxint, [x['MRMS_MaxInt'] for x in temp_mrms_extras]])
        mrms_extra_ti = np.concatenate([mrms_extra_ti, [x['Total_Interest'] for x in temp_mrms_extras]])
        mrms_extra_centroid = mrms_extra_centroid + [x['MRMS_Centroid'] for x in temp_mrms_extras]
        #fcst_hits[f] = len(temp_hits)
        #fcst_misses[f] = len(temp_misses)
        #fcst_fas[f] = len(temp_fas)
        #fcst_extras[f] = len(temp_extras)
        #fcst_mrms_extras[f] = len(temp_mrms_extras)
        ### QC check:  print stats for each forecast
        #if ((len(temp_hits) + len(temp_misses)) > 0.):
        #    fcst_pod[f] = len(temp_hits) / (len(temp_hits) + len(temp_misses))
        #else:
        #    fcst_pod[f] = -999.
        #if ((len(temp_hits) + len(temp_fas)) > 0. ):
        #    fcst_far[f] = len(temp_fas) / (len(temp_hits) + len(temp_fas))
        #else:
        #    fcst_far[f] = -999.
        #if ((len(temp_hits) + len(temp_misses)) > 0. ):
        #    fcst_bias[f] = (len(temp_hits) + len(temp_fas)) / (len(temp_hits) + len(temp_misses))
        #else:
        #    fcst_bias[f] = -999.
        #if ((len(temp_hits) + len(temp_fas) + len(temp_misses)) > 0.):
        #    fcst_csi[f] = len(temp_hits) / (len(temp_hits) + len(temp_fas) + len(temp_misses))
        #else:
        #    fcst_csi[f] = -999.
        #if ((len(temp_hits) + len(temp_misses) + len(temp_mrms_extras)) > 0.):
        #    fcst_extra_bias[f] = (len(temp_hits) + len(temp_fas) + len(temp_extras)) / (len(temp_hits) + len(temp_misses) + len(temp_mrms_extras))
        #else:
        #    fcst_extra_bias[f] = -999.

        temp_fcst.close()

    #Contingency table stats by lead time:

    if obj_time or obj_perf:
        #cb-WoFS:

        pod_lead_time = np.zeros((ne, len(lead_times)))
        far_lead_time = np.zeros((ne, len(lead_times)))
        bias_lead_time = np.zeros((ne, len(lead_times)))
        extra_bias_lead_time = np.zeros((ne, len(lead_times)))
        #area_bias_lead_time = np.zeros((ne, len(lead_times)))
        #area_extra_bias_lead_time = np.zeros((ne, len(lead_times)))
        csi_lead_time = np.zeros((ne, len(lead_times)))

        ci_pod_lead_time = np.zeros((ne, len(lead_times)))
        ci_far_lead_time = np.zeros((ne, len(lead_times)))
        ci_bias_lead_time = np.zeros((ne, len(lead_times)))
        ci_extra_bias_lead_time = np.zeros((ne, len(lead_times)))
        ci_csi_lead_time = np.zeros((ne, len(lead_times)))

        total_area = np.zeros((ne, len(lead_times)))
        mrms_total_area = np.zeros(len(lead_times))

        total_count = np.zeros((ne, len(lead_times)))
        mrms_total_count = np.zeros(len(lead_times))

        for n in range(0, ne):
            #print('asdf: ', n)
            for i, temp_lead in enumerate(lead_times):
               temp_hit_ind = np.argwhere((hit_lead_time == temp_lead) & (hit_member == n+1))
               temp_miss_ind = np.argwhere((miss_lead_time == temp_lead) & (miss_member == n+1))
               temp_fa_ind = np.argwhere((fa_lead_time == temp_lead) & (fa_member == n+1))
               temp_extra_ind = np.argwhere((extra_lead_time == temp_lead) & (extra_member == n+1))
               temp_mrms_extra_ind = np.argwhere((mrms_extra_lead_time == temp_lead) & (mrms_extra_member == n+1))
               #print(n, i, len(temp_hit_ind), len(temp_miss_ind), len(temp_fa_ind), len(temp_extra_ind), len(temp_mrms_extra_ind))
               if ((len(temp_hit_ind) + len(temp_miss_ind)) == 0):
                    #print('asdfasdf')
                    pod_lead_time[n,i] = 0.
                    csi_lead_time[n,i] = 0.
                    bias_lead_time[n,i] = 0.
                    extra_bias_lead_time[n,i] = 0.
                    #area_bias_lead_time[n,i] = 0.
                    #area_extra_bias_lead_time[n,i] = 0.
                    ci_pod_lead_time[n,i] = 0.
                    ci_bias_lead_time[n,i] = 0.
                    ci_csi_lead_time[n,i] = 0.
                    total_area = 0.
                    mrms_total_area = 0.
                    total_count = 0.
                    mrms_total_count = 0.
               elif ((len(temp_hit_ind) + len(temp_fa_ind)) == 0):
                    far_lead_time[n,i] = 0.
                    ci_far_lead_time[n,i] = 0.
               else:
                    pod_lead_time[n,i] = len(temp_hit_ind) / (len(temp_hit_ind) + len(temp_miss_ind))
                    far_lead_time[n,i] = len(temp_fa_ind) / (len(temp_hit_ind) + len(temp_fa_ind))
                    bias_lead_time[n,i] = (len(temp_hit_ind) + len(temp_fa_ind)) / (len(temp_hit_ind) + len(temp_miss_ind))
                    extra_bias_lead_time[n,i] = (len(temp_hit_ind) + len(temp_fa_ind) + len(temp_extra_ind)) / (len(temp_hit_ind) + len(temp_miss_ind) + len(temp_mrms_extra_ind))
                    #area_bias_lead_time[n,i] = (np.sum(hit_area[temp_hit_ind]) + np.sum(fa_area[temp_fa_ind])) / (np.sum(hit_mrms_area[temp_hit_ind]) + np.sum(miss_area[temp_miss_ind]))
                    #area_extra_bias_lead_time[n,i] = (np.sum(hit_area[temp_hit_ind]) + np.sum(fa_area[temp_fa_ind]) + np.sum(extra_area[temp_extra_ind])) / (np.sum(hit_mrms_area[temp_hit_ind]) + np.sum(miss_area[temp_miss_ind]) + np.sum(mrms_extra_area[temp_mrms_extra_ind]))
                    csi_lead_time[n,i] = len(temp_hit_ind) / (len(temp_hit_ind) + len(temp_fa_ind) + len(temp_miss_ind))

                    ci_pod_lead_time[n,i], ci_far_lead_time[n,i], ci_bias_lead_time[n,i], ci_csi_lead_time[n,i] = bootstrap_ci(temp_hit_ind, temp_miss_ind, temp_fa_ind, ci_samples, ci_interval) #hard coded to be 99% CI with 1000 samples
                    ci_extra_bias_lead_time[n,i] = bootstrap_ci_extra(temp_hit_ind, temp_miss_ind, temp_fa_ind, temp_extra_ind, temp_mrms_extra_ind, ci_samples, ci_interval) #hard coded to be 99% CI with 1000 samples

                    total_area[n,i] = np.sum(hit_area[temp_hit_ind]) + np.sum(fa_area[temp_fa_ind]) + np.sum(extra_area[temp_extra_ind])
                    mrms_total_area[i] = np.sum(hit_mrms_area[temp_hit_ind]) + np.sum(miss_area[temp_miss_ind]) + np.sum(mrms_extra_area[temp_mrms_extra_ind])

                    total_count[n,i] = len(temp_hit_ind) + len(temp_fa_ind) + len(temp_extra_ind)
                    mrms_total_count[i] = len(temp_hit_ind) + len(temp_miss_ind) + len(temp_mrms_extra_ind)

        ret_obj["pod_lead_time"]        = pod_lead_time
        ret_obj["far_lead_time"]        = far_lead_time
        ret_obj["bias_lead_time"]       = bias_lead_time
        ret_obj["extra_bias_lead_time"] = extra_bias_lead_time
        ret_obj["csi_lead_time"]        = csi_lead_time

        ret_obj["ci_pod_lead_time"]     = ci_pod_lead_time
        ret_obj["ci_far_lead_time"]     = ci_far_lead_time
        ret_obj["ci_bias_lead_time"]    = ci_bias_lead_time
        ret_obj["ci_csi_lead_time"]     = ci_csi_lead_time

        ret_obj["total_count"]          = total_count
        ret_obj["mrms_total_count"]     = mrms_total_count

        ret_obj["total_area"]           = total_area
        ret_obj["mrms_total_area"]      = mrms_total_area

    ######### OBJECT AGE SECTION #########

    if obj_age:
        #calculate object age relative to initialization time:

        relative_hit_age  = hit_mrms_age - (hit_lead_time * 60.)
        relative_miss_age = miss_age - (miss_lead_time * 60.)
        #relative_mrms_extra_age = mrms_extra_age - (mrms_extra_lead_time * 60.)

        age_pod = np.zeros(((len(age_bins)+1), len(lead_times)))
        age_pod_ci = np.zeros(((len(age_bins)+1), len(lead_times)))
        age_pod_counts = np.zeros(((len(age_bins)+1), len(lead_times)))

        for b in range(0, (len(age_bins)+1)):
            #print(b, age_bins[b])
            if (b == 0):
                temp_hit_ind = np.argwhere(relative_hit_age < age_bins[0])
                temp_miss_ind = np.argwhere(relative_miss_age < age_bins[0])
                temp_hits = hit_lead_time[temp_hit_ind]
                temp_misses = miss_lead_time[temp_miss_ind]
                #print('asdf: ', len(temp_hits), len(temp_misses))
                age_pod[b,:], age_pod_ci[b,:], age_pod_counts[b,:] = pod_time_series(temp_hits, temp_misses, lead_times)
            elif (b == len(age_bins)):
                temp_hit_ind = np.argwhere(relative_hit_age >= age_bins[-1])
                temp_miss_ind = np.argwhere(relative_miss_age >= age_bins[-1])
                temp_hits = hit_lead_time[temp_hit_ind]
                temp_misses = miss_lead_time[temp_miss_ind]
                age_pod[b,:], age_pod_ci[b,:], age_pod_counts[b,:] = pod_time_series(temp_hits, temp_misses, lead_times)
            else:
                temp_hit_ind = np.argwhere((relative_hit_age >= age_bins[b-1]) & (relative_hit_age < age_bins[b]))
                temp_miss_ind = np.argwhere((relative_miss_age >= age_bins[b-1]) & (relative_miss_age < age_bins[b]))
                temp_hits = hit_lead_time[temp_hit_ind]
                temp_misses = miss_lead_time[temp_miss_ind]
                age_pod[b,:], age_pod_ci[b,:], age_pod_counts[b,:] = pod_time_series(temp_hits, temp_misses, lead_times)

        age_pod = np.where(age_pod == 0, np.nan, age_pod)
        ret_obj["age_pod"]       = age_pod

    ######### MRMS OBJECT AREA SECTION #########

    if obj_area:
        mrms_area_pod = np.zeros(((len(area_bins)+1), len(lead_times)))
        mrms_area_pod_ci = np.zeros(((len(area_bins)+1), len(lead_times)))
        mrms_area_pod_counts = np.zeros(((len(area_bins)+1), len(lead_times)))

        for b in range(0, (len(area_bins)+1)):
            #print(b, age_bins[b])
            if (b == 0):
                temp_hit_ind = np.argwhere(hit_mrms_area < area_bins[0])
                temp_miss_ind = np.argwhere(miss_area < area_bins[0])
                temp_hits = hit_lead_time[temp_hit_ind]
                temp_misses = miss_lead_time[temp_miss_ind]
                #print('asdf: ', len(temp_hits), len(temp_misses))
                mrms_area_pod[b,:], mrms_area_pod_ci[b,:], mrms_area_pod_counts[b,:] = pod_time_series(temp_hits, temp_misses, lead_times)
            elif (b == len(area_bins)):
                temp_hit_ind = np.argwhere(hit_mrms_area >= area_bins[-1])
                temp_miss_ind = np.argwhere(miss_area >= area_bins[-1])
                temp_hits = hit_lead_time[temp_hit_ind]
                temp_misses = miss_lead_time[temp_miss_ind]
                mrms_area_pod[b,:], mrms_area_pod_ci[b,:], mrms_area_pod_counts[b,:] = pod_time_series(temp_hits, temp_misses, lead_times)
            else:
                temp_hit_ind = np.argwhere((hit_mrms_area >= area_bins[b-1]) & (hit_mrms_area < area_bins[b]))
                temp_miss_ind = np.argwhere((miss_area >= area_bins[b-1]) & (miss_area < area_bins[b]))
                temp_hits = hit_lead_time[temp_hit_ind]
                temp_misses = miss_lead_time[temp_miss_ind]
                mrms_area_pod[b,:], mrms_area_pod_ci[b,:], mrms_area_pod_counts[b,:] = pod_time_series(temp_hits, temp_misses, lead_times)

        mrms_area_pod = np.where(mrms_area_pod == 0, np.nan, mrms_area_pod)

        ret_obj["mrms_area_pod"]       = mrms_area_pod

   ######### AREA RATIOS:  ###########

    if obj_area_ratio:
        perc_area_ratio_mean = np.zeros(len(lead_times))
        perc_area_ratio_25 = np.zeros(len(lead_times))
        perc_area_ratio_75 = np.zeros(len(lead_times))

        member_perc_area_ratio_mean = np.zeros((ne, len(lead_times)))

        for i, temp_lead in enumerate(lead_times):
            temp_hit_ind = np.argwhere(hit_lead_time == temp_lead)

            temp_hit_area = hit_area[temp_hit_ind]
            temp_hit_mrms_area = hit_mrms_area[temp_hit_ind]
            temp_hit_member = hit_member[temp_hit_ind]

            temp_area_ratio = temp_hit_area / temp_hit_mrms_area
            temp_area_ratio_percent = np.log2(temp_area_ratio)

            perc_area_ratio_mean[i] = np.mean(temp_area_ratio_percent)
            perc_area_ratio_25[i] = np.percentile(temp_area_ratio_percent, 25)
            perc_area_ratio_75[i] = np.percentile(temp_area_ratio_percent, 75)

            for m in range(0, ne):
                temp_member_ind = np.argwhere(temp_hit_member == (m+1))
                temp_member_ind = temp_member_ind[:,0]
                temp_member_area = temp_hit_area[temp_member_ind]
                temp_member_mrms_area = temp_hit_mrms_area[temp_member_ind]

                temp_member_area_ratio = temp_member_area / temp_member_mrms_area
                temp_member_perc_area_ratio = np.log2(temp_member_area_ratio)

                member_perc_area_ratio_mean[m,i] = np.mean(temp_member_perc_area_ratio)

        ret_obj["perc_area_ratio_25"]          = perc_area_ratio_25
        ret_obj["perc_area_ratio_75"]          = perc_area_ratio_75
        ret_obj["perc_area_ratio_mean"]        = perc_area_ratio_mean
        ret_obj["member_perc_area_ratio_mean"] = member_perc_area_ratio_mean

    ######### TOTAL INTEREST DIFFERENCE:  ###########

    if obj_interest:
        ti_mean = np.zeros(len(lead_times))
        ti_25 = np.zeros(len(lead_times))
        ti_75 = np.zeros(len(lead_times))

        member_ti_mean = np.zeros((ne, len(lead_times)))

        for i, temp_lead in enumerate(lead_times):
            temp_hit_ind = np.argwhere(hit_lead_time == temp_lead)

            temp_hit_ti = hit_ti[temp_hit_ind]

            temp_hit_member = hit_member[temp_hit_ind]

            ti_mean[i] = np.mean(temp_hit_ti)
            ti_25[i] = np.percentile(temp_hit_ti, 25)
            ti_75[i] = np.percentile(temp_hit_ti, 75)

            for m in range(0, ne):
                temp_member_ind = np.argwhere(temp_hit_member == (m+1))
                temp_member_ind = temp_member_ind[:,0]
                temp_member_ti = temp_hit_ti[temp_member_ind]

                member_ti_mean[m,i] = np.mean(temp_member_ti)

        ret_obj["ti_25"]          = ti_25
        ret_obj["ti_75"]          = ti_75

        ret_obj["ti_mean"]        = ti_mean
        ret_obj["member_ti_mean"] = member_ti_mean

    ######### CENTROID / BOUNDARY DIFFERENCE:  ###########

    if obj_centroid or obj_bound:
        cent_dist_mean = np.zeros(len(lead_times))
        cent_dist_25 = np.zeros(len(lead_times))
        cent_dist_75 = np.zeros(len(lead_times))

        bound_dist_mean = np.zeros(len(lead_times))
        bound_dist_25 = np.zeros(len(lead_times))
        bound_dist_75 = np.zeros(len(lead_times))

        member_cent_dist_mean = np.zeros((ne, len(lead_times)))
        member_bound_dist_mean = np.zeros((ne, len(lead_times)))

        for i, temp_lead in enumerate(lead_times):
            temp_hit_ind = np.argwhere(hit_lead_time == temp_lead)

            #centroid distance
            temp_hit_cent = []
            for j in range(0, len(temp_hit_ind)):
                temp_hit_cent.append(hit_centroid[temp_hit_ind[j][0]])

            temp_hit_mrms_cent = []
            for j in range(0, len(temp_hit_ind)):
                temp_hit_mrms_cent.append(hit_mrms_centroid[temp_hit_ind[j][0]])

            temp_hit_member = hit_member[temp_hit_ind]

            temp_cent_dist = []
            for j in range(0, len(temp_hit_ind)):
                temp_cent_dist.append(np.sqrt((temp_hit_cent[j][0] - temp_hit_mrms_cent[j][0])**2 + \
                                         (temp_hit_cent[j][1] - temp_hit_mrms_cent[j][1])**2))

            #ti
            temp_hit_ti = []
            for j in range(0, len(temp_hit_ind)):
                temp_hit_ti.append(hit_ti[temp_hit_ind[j][0]])

            #area ratio
            temp_hit_area = []
            temp_hit_mrms_area = []
            temp_area_ratio = []
            for j in range(0, len(temp_hit_ind)):
                temp_hit_area.append(hit_area[temp_hit_ind[j][0]])
                temp_hit_mrms_area.append(hit_mrms_area[temp_hit_ind[j][0]])
                temp_area_ratio.append(hit_area[temp_hit_ind[j][0]] / hit_mrms_area[temp_hit_ind[j][0]])

            #cent dist stats

            cent_dist_mean[i] = np.mean(temp_cent_dist) * 3.
            cent_dist_25[i] = np.percentile(temp_cent_dist, 25) * 3.
            cent_dist_75[i] = np.percentile(temp_cent_dist, 75) * 3.

            #back out boundary displacement in km: (assuming max distance thresholds of 40 km)
            #convert to np arrays:
            temp_area_ratio = np.array(temp_area_ratio)
            temp_hit_ti = np.array(temp_hit_ti)
            temp_cent_dist_km = np.array(temp_cent_dist) * 3.
            temp_cent_dist_km = np.where(temp_cent_dist_km > 40., 40., temp_cent_dist_km)

            temp_area_ratio_low = np.where(temp_area_ratio > 1., (1/temp_area_ratio), temp_area_ratio)
            temp_bound_dist = -40. * (2 * temp_hit_ti / temp_area_ratio_low - ((40. - temp_cent_dist_km) / 40.) \
                                      ) + 40.

            #bound dist stats

            bound_dist_mean[i] = np.mean(temp_bound_dist)
            bound_dist_25[i] = np.percentile(temp_bound_dist, 25)
            bound_dist_75[i] = np.percentile(temp_bound_dist, 75)

            for m in range(0, ne):
                temp_member_ind = np.argwhere(temp_hit_member == (m+1))
                temp_member_ind = temp_member_ind[:,0]

                temp_member_cent = []

                for j in range(0, len(temp_member_ind)):
                    temp_member_cent.append(temp_hit_cent[temp_member_ind[j]])

                temp_member_mrms_cent = []
                for j in range(0, len(temp_member_ind)):
                    temp_member_mrms_cent.append(temp_hit_mrms_cent[temp_member_ind[j]])

                temp_member_cent_dist = []
                for j in range(0, len(temp_member_ind)):
                    temp_member_cent_dist.append(np.sqrt((temp_member_cent[j][0] - temp_member_mrms_cent[j][0])**2 + \
                                             (temp_member_cent[j][1] - temp_member_mrms_cent[j][1])**2))

                temp_member_bound_dist = []
                for j in range(0, len(temp_member_ind)):
                    temp_member_bound_dist.append(temp_bound_dist[temp_member_ind[j]])

                member_cent_dist_mean[m,i] = np.mean(temp_member_cent_dist) * 3.
                member_bound_dist_mean[m,i] = np.mean(temp_member_bound_dist)  #already converted to km

        ret_obj["cent_dist_mean"]         = cent_dist_mean
        ret_obj["cent_dist_25"]           = cent_dist_25
        ret_obj["cent_dist_75"]           = cent_dist_75

        ret_obj["bound_dist_mean"]        = bound_dist_mean
        ret_obj["bound_dist_25"]          = bound_dist_25
        ret_obj["bound_dist_75"]          = bound_dist_75

        ret_obj["member_cent_dist_mean"]  = member_cent_dist_mean
        ret_obj["member_bound_dist_mean"] = member_bound_dist_mean

    return make_namespace(ret_obj, level=1)

########################################################################

def plot_time_series(obj1,obj2,colors,lines,labels):

    pod_y_ticks = [0, .1, .2, .3, .4, .5, .6, .7, .8, .9, 1.]
    pod_y_labels = ['', '0.1', '0.2', '0.3', '0.4', '0.5', '0.6', '0.7', '0.8', '0.9', '1.0']

    bias_y_ticks = [0, 0.25, 0.5, .75, 1., 1.25, 1.5, 1.75, 2.]
    bias_y_labels = ['', '0.25', '0.5', '0.75', '1.0', '1.25', '1.5', '1.75', '2.0']

    pod_title  = 'Probability of Detection'
    far_title  = 'False Alarm Ratio'
    bias_title = 'Frequency Bias'
    csi_title  = 'Critical Success Index'

    pod_outname        = os.path.join(out_dir, (out_prefix + '_time_series_pod.png'))
    far_outname        = os.path.join(out_dir, (out_prefix + '_time_series_far.png'))
    bias_outname       = os.path.join(out_dir, (out_prefix + '_time_series_bias.png'))
    extra_bias_outname = os.path.join(out_dir, (out_prefix + '_time_series_extra_bias.png'))
    csi_outname        = os.path.join(out_dir, (out_prefix + '_time_series_csi.png'))

    time_series_fig([obj1.pod_lead_time,        obj2.pod_lead_time],        [obj1.ci_pod_lead_time,  obj2.ci_pod_lead_time],  pod_y_ticks,  pod_y_labels,  [0.05,0.8],  pod_title,  colors,lines,labels,pod_outname)
    time_series_fig([obj1.far_lead_time,        obj2.far_lead_time],        [obj1.ci_far_lead_time,  obj2.ci_far_lead_time],  pod_y_ticks,  pod_y_labels,  [0,1],       far_title,  colors,lines,labels,far_outname)
    time_series_fig([obj1.bias_lead_time,       obj2.bias_lead_time],       [obj1.ci_bias_lead_time, obj2.ci_bias_lead_time], bias_y_ticks, bias_y_labels, [0.25,2.25], bias_title, colors,lines,labels,bias_outname)
    time_series_fig([obj1.extra_bias_lead_time, obj2.extra_bias_lead_time], [obj1.ci_bias_lead_time, obj2.ci_bias_lead_time], bias_y_ticks, bias_y_labels, [0.25,2.25], bias_title, colors,lines,labels,extra_bias_outname)
    time_series_fig([obj1.csi_lead_time,        obj2.csi_lead_time],        [obj1.ci_csi_lead_time,  obj2.ci_csi_lead_time],  pod_y_ticks,  pod_y_labels,  [0,1],       csi_title,  colors,lines,labels,csi_outname)

    #plot time series of total object areas:

    #area_y_ticks = [0, 100000, 200000, 300000, 400000, 500000, 600000, 700000, 800000, 900000, 1000000]
    #area_y_labels = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10']
    area_y_ticks = [0, 20000, 40000, 60000, 80000, 100000]
    area_y_labels = ['0', '0.2','0.4','0.6','0.8','1']
    area_y_title = 'Total Object Area x 10^5 (grid boxes)'
    area_y_min = 0.
    area_y_max = 100000.

    fig1, ax1 = time_series_init(area_y_min, area_y_max, area_y_ticks, area_y_labels, area_y_title)

    ysu_mem  = [0, 1,  6,  7, 12, 13]
    myj_mem  = [2, 3,  8,  9, 14, 15]
    mynn_mem = [4, 5, 10, 11, 16, 17]

    k = 0
    for runcase in [obj1,obj2]:
        for n in range(0, runcase.total_area.shape[0]):
            if (n in ysu_mem):
               temp_color = cb_colors.orange5
            if (n in myj_mem):
               temp_color = cb_colors.green5
            if (n in mynn_mem):
               temp_color = cb_colors.blue5
            ax1.plot(runcase.total_area[n,:], color=temp_color, linestyle=lines[k], linewidth=1., alpha=0.8)
        k += 1

    ax1.plot(obj1.mrms_total_area, color='k', linestyle='-', linewidth=1.25, alpha=0.8)

    add_legend(ax1,0.85,0.88,['k','g','r'], ['-', '-','--'],["MRMS","cb-WoFS","mpas-WoFS"])

    total_area_outname = os.path.join(out_dir, (out_prefix + '_time_series_total_area.png'))
    print(f"Saving {total_area_outname} ....")
    plt.savefig(total_area_outname, format='png', dpi=150)

    #Tme series plot of total object counts:

    #area_y_ticks = [0, 2000, 4000, 6000, 8000, 10000, 12000, 14000, 16000]
    #area_y_labels = ['0', '2', '4', '6', '8', '10', '12', '14', '16']
    area_y_ticks = [0, 500,1000, 1500, 2000]
    area_y_labels = ['0','0.5', '1.0', '1.5','2']
    area_y_title = 'Total Object Count x 10^3'
    area_y_min = 0.
    area_y_max = 2000.

    fig1, ax1 = time_series_init(area_y_min, area_y_max, area_y_ticks, area_y_labels, area_y_title)

    ysu_mem  = [0, 1,  6,  7, 12, 13]
    myj_mem  = [2, 3,  8,  9, 14, 15]
    mynn_mem = [4, 5, 10, 11, 16, 17]

    k = 0
    for runcase in [obj1,obj2]:
        for n in range(0, runcase.total_area.shape[0]):
            if (n in ysu_mem):
               temp_color = cb_colors.orange5
            if (n in myj_mem):
               temp_color = cb_colors.green5
            if (n in mynn_mem):
               temp_color = cb_colors.blue5
            ax1.plot(runcase.total_count[n,:], color=temp_color, linestyle=lines[k], linewidth=1., alpha=0.8)

        k += 1

    ax1.plot(obj1.mrms_total_count, color='k', linestyle='-',linewidth=1.25, alpha=0.8)

    add_legend(ax1,0.85,0.88,['k','g','r'], ['-', '-','--'],["MRMS","cb-WoFS","mpas-WoFS"])

    total_area_outname = os.path.join(out_dir, (out_prefix + '_time_series_total_obj_count.png'))
    print(f"Saving {total_area_outname} ....")
    plt.savefig(total_area_outname, format='png', dpi=150)

########################################################################

def plot_object_age(objs,labels):
    k = 0
    for obj in objs:

        fig1 = plt.figure(figsize=(12,7))
        ax1 = fig1.add_axes([0.1, 0.11, .88, .86])
        ax1.spines['top'].set_alpha(0.7)
        ax1.spines['bottom'].set_alpha(0.7)
        ax1.spines['right'].set_alpha(0.7)
        ax1.spines['left'].set_alpha(0.7)
        ax1.spines['top'].set_linewidth(0.5)
        ax1.spines['bottom'].set_linewidth(0.5)
        ax1.spines['right'].set_linewidth(0.5)
        ax1.spines['left'].set_linewidth(0.5)

        #plt.xlim(0,len(lead_times))
        plt.xlim(-2.5,362.5)
        #plt.ylim(np.min(age_bins),np.max(age_bins))

        age_cmap = plt.get_cmap('Reds')
        #age_cmap = cmocean.cm.deep
        pod_levels = np.arange(0.,1.05,0.05)

        age_norm = matplotlib.colors.BoundaryNorm(pod_levels, age_cmap.N)

        #plt.imshow(age_pod, interpolation='nearest', cmap=age_cmap, norm=age_norm, alpha=0.7)
        plt.pcolor(lead_times, age_bins_plot, obj.age_pod, cmap=age_cmap, norm=age_norm)
        cb = plt.colorbar(cmap=age_cmap, norm=age_norm, orientation = 'vertical', spacing='uniform')

        #y_text = age_bins_plot[1:-1]
        #x_text = lead_times[3:-25:3]

        for y in range(0, (obj.age_pod.shape[0])):
            for x in range(2, (obj.age_pod.shape[1]-2), 4):
                if ~np.isnan(obj.age_pod[y,x]):
                    plt.text(lead_times[x], age_bins_plot[y], '%.2f' % obj.age_pod[y, x],
                         horizontalalignment='center',
                         verticalalignment='center')

        cb.ax.tick_params(labelsize=14)
        cb.set_label(label=f'Probability of Detection ({labels[k]})', fontsize=16, alpha=0.7)

        #x_ticks = lead_times[::6]
        x_ticks = [0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330, 360]

        y_ticks = age_ticks
        y_labels = ['-270', '', '-210', '', '-150', '', '-90', '', '-30', '', '30', '', \
                    '90', '', '150', '', '210', '', '270']

        ax1.set_xlabel('Forecast Lead Time (min)', fontsize=18, alpha=0.7)
        ax1.set_ylabel('Object Age Relative to WoFS Initialization (min)', fontsize=18, alpha=0.7)

        plt.xticks(x_ticks, fontsize=16, alpha=0.7)
        plt.yticks(y_ticks, y_labels, fontsize=16, alpha=0.7)

        age_pod_outname = os.path.join(out_dir, f"{out_prefix}_{labels[k]}_object_age_pod.png")
        print(f"Saving {age_pod_outname} ....")
        plt.savefig(age_pod_outname, format='png', dpi=150)
        k += 1

    #---------------------------------------------------------------
    # Plot object age difference
    #---------------------------------------------------------------

    fig1 = plt.figure(figsize=(12,7))
    ax1 = fig1.add_axes([0.1, 0.11, .88, .86])
    ax1.spines['top'].set_alpha(0.7)
    ax1.spines['bottom'].set_alpha(0.7)
    ax1.spines['right'].set_alpha(0.7)
    ax1.spines['left'].set_alpha(0.7)
    ax1.spines['top'].set_linewidth(0.5)
    ax1.spines['bottom'].set_linewidth(0.5)
    ax1.spines['right'].set_linewidth(0.5)
    ax1.spines['left'].set_linewidth(0.5)

    #plt.xlim(0,len(lead_times))
    plt.xlim(-2.5,362.5)
    #plt.ylim(np.min(age_bins),np.max(age_bins))

    age_cmap = plt.get_cmap('bwr',100)
    #age_cmap = cmocean.cm.deep
    pod_levels = np.arange(-0.5,0.5,0.05)

    age_norm = matplotlib.colors.BoundaryNorm(pod_levels, age_cmap.N)

    age_pod = objs[1].age_pod - objs[0].age_pod

    #plt.imshow(age_pod, interpolation='nearest', cmap=age_cmap, norm=age_norm, alpha=0.7)
    plt.pcolor(lead_times, age_bins_plot, age_pod, cmap=age_cmap, norm=age_norm)
    cb = plt.colorbar(cmap=age_cmap, norm=age_norm, orientation = 'vertical', spacing='uniform')

    #y_text = age_bins_plot[1:-1]
    #x_text = lead_times[3:-25:3]

    for y in range(0, (age_pod.shape[0])):
        for x in range(2, (age_pod.shape[1]-2), 4):
            if ~np.isnan(age_pod[y,x]):
                plt.text(lead_times[x], age_bins_plot[y], '%.2f' % age_pod[y, x],
                     horizontalalignment='center',
                     verticalalignment='center')

    cb.ax.tick_params(labelsize=14)
    cb.set_label(label=f'Probability of Detection ({labels[1]} - {labels[0]})', fontsize=16, alpha=0.7)

    #x_ticks = lead_times[::6]
    x_ticks = [0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330, 360]

    y_ticks = age_ticks
    y_labels = ['-270', '', '-210', '', '-150', '', '-90', '', '-30', '', '30', '', \
                '90', '', '150', '', '210', '', '270']

    ax1.set_xlabel('Forecast Lead Time (min)', fontsize=18, alpha=0.7)
    ax1.set_ylabel('Object Age Relative to WoFS Initialization (min)', fontsize=18, alpha=0.7)

    plt.xticks(x_ticks, fontsize=16, alpha=0.7)
    plt.yticks(y_ticks, y_labels, fontsize=16, alpha=0.7)

    age_pod_outname = os.path.join(out_dir, (out_prefix + '_diff_object_age_pod.png'))
    print(f"Saving {age_pod_outname} ....")
    plt.savefig(age_pod_outname, format='png', dpi=150)

########################################################################

def plot_object_area(objs,labels):
    k = 0
    for obj in objs:
        fig1 = plt.figure(figsize=(12,7))
        ax1 = fig1.add_axes([0.1, 0.11, .88, .86])
        ax1.spines['top'].set_alpha(0.7)
        ax1.spines['bottom'].set_alpha(0.7)
        ax1.spines['right'].set_alpha(0.7)
        ax1.spines['left'].set_alpha(0.7)
        ax1.spines['top'].set_linewidth(0.5)
        ax1.spines['bottom'].set_linewidth(0.5)
        ax1.spines['right'].set_linewidth(0.5)
        ax1.spines['left'].set_linewidth(0.5)

        #plt.xlim(0,len(lead_times))
        plt.xlim(-2.5,362.5)
        #plt.ylim(np.min(area_bins),np.max(area_bins))

        area_cmap = plt.get_cmap('Reds')
        #age_cmap = cmocean.cm.deep
        pod_levels = np.arange(0.,1.05,0.05)

        area_norm = matplotlib.colors.BoundaryNorm(pod_levels, area_cmap.N)

        #plt.imshow(age_pod, interpolation='nearest', cmap=age_cmap, norm=age_norm, alpha=0.7)
        plt.pcolor(lead_times, area_bins_plot, obj.mrms_area_pod, cmap=area_cmap, norm=area_norm)
        cb = plt.colorbar(cmap=area_cmap, norm=area_norm, orientation = 'vertical', spacing='uniform')

        #y_text = age_bins_plot[1:-1]
        #x_text = lead_times[3:-25:3]

        for y in range(0, (obj.mrms_area_pod.shape[0])):
            for x in range(2, (obj.mrms_area_pod.shape[1]-2), 4):
                if ~np.isnan(obj.mrms_area_pod[y,x]):
                    plt.text(lead_times[x], area_bins_plot[y], '%.2f' % obj.mrms_area_pod[y, x],
                         horizontalalignment='center', verticalalignment='center')

        cb.ax.tick_params(labelsize=14)
        cb.set_label(label=f'Probability of Detection ({labels[k]})', fontsize=16, alpha=0.7)

        #x_ticks = lead_times[::6]
        x_ticks = [0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330, 360]

        y_ticks = area_ticks
        y_labels = ['0', '', '24', '', '48', '', '72', '', '96', '', '120', '', '144', \
                    '', '168', '', '192', '', '216', '', '240']

        ax1.set_xlabel('Forecast Lead Time (min)', fontsize=18, alpha=0.7)
        ax1.set_ylabel('MRMS Object Area (grid boxes)', fontsize=18, alpha=0.7)

        plt.xticks(x_ticks, fontsize=16, alpha=0.7)
        plt.yticks(y_ticks, y_labels, fontsize=16, alpha=0.7)

        age_pod_outname = os.path.join(out_dir, f'{out_prefix}_{labels[k]}_mrms_object_area_pod.png')
        print(f"Saving {age_pod_outname} ....")
        plt.savefig(age_pod_outname, format='png', dpi=150)

        k += 1

    #---------------------------------------------------------------
    # Plot object area difference
    #---------------------------------------------------------------

    fig1 = plt.figure(figsize=(12,7))
    ax1 = fig1.add_axes([0.1, 0.11, .88, .86])
    ax1.spines['top'].set_alpha(0.7)
    ax1.spines['bottom'].set_alpha(0.7)
    ax1.spines['right'].set_alpha(0.7)
    ax1.spines['left'].set_alpha(0.7)
    ax1.spines['top'].set_linewidth(0.5)
    ax1.spines['bottom'].set_linewidth(0.5)
    ax1.spines['right'].set_linewidth(0.5)
    ax1.spines['left'].set_linewidth(0.5)

    #plt.xlim(0,len(lead_times))
    plt.xlim(-2.5,362.5)
    #plt.ylim(np.min(area_bins),np.max(area_bins))

    area_cmap = plt.get_cmap('bwr',100)
    #age_cmap = cmocean.cm.deep
    pod_levels = np.arange(-0.5,0.5,0.05)

    area_norm = matplotlib.colors.BoundaryNorm(pod_levels, area_cmap.N)
    mrms_area_pod = objs[1].mrms_area_pod - objs[0].mrms_area_pod

    #plt.imshow(age_pod, interpolation='nearest', cmap=age_cmap, norm=age_norm, alpha=0.7)
    plt.pcolor(lead_times, area_bins_plot, mrms_area_pod, cmap=area_cmap, norm=area_norm)
    cb = plt.colorbar(cmap=area_cmap, norm=area_norm, orientation = 'vertical', spacing='uniform')

    #y_text = age_bins_plot[1:-1]
    #x_text = lead_times[3:-25:3]

    for y in range(0, (mrms_area_pod.shape[0])):
        for x in range(2, (mrms_area_pod.shape[1]-2), 4):
            if ~np.isnan(mrms_area_pod[y,x]):
                plt.text(lead_times[x], area_bins_plot[y], '%.2f' % mrms_area_pod[y, x],
                     horizontalalignment='center', verticalalignment='center')

    cb.ax.tick_params(labelsize=14)
    cb.set_label(label=f'Probability of Detection ({labels[1]} - {labels[0]})', fontsize=16, alpha=0.7)

    #x_ticks = lead_times[::6]
    x_ticks = [0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330, 360]

    y_ticks = area_ticks
    y_labels = ['0', '', '24', '', '48', '', '72', '', '96', '', '120', '', '144', \
                '', '168', '', '192', '', '216', '', '240']

    ax1.set_xlabel('Forecast Lead Time (min)', fontsize=18, alpha=0.7)
    ax1.set_ylabel('MRMS Object Area (grid boxes)', fontsize=18, alpha=0.7)

    plt.xticks(x_ticks, fontsize=16, alpha=0.7)
    plt.yticks(y_ticks, y_labels, fontsize=16, alpha=0.7)

    age_pod_outname = os.path.join(out_dir, f'{out_prefix}_diff_mrms_object_area_pod.png')
    print(f"Saving {age_pod_outname} ....")
    plt.savefig(age_pod_outname, format='png', dpi=150)

########################################################################

def plot_area_ratio(objs,colors,lines,labels):
    fig1 = plt.figure(figsize=(20,5.5))
    ax1 = fig1.add_axes([0.08, 0.14, .88, .82])
    #fig1 = plt.figure(figsize=(10,5))
    #ax1 = fig1.add_axes([0.08, 0.1, .88, .86])
    ax1.spines['top'].set_alpha(0.7)
    ax1.spines['bottom'].set_alpha(0.7)
    ax1.spines['left'].set_alpha(0.7)
    ax1.spines['right'].set_alpha(0.7)
    ax1.spines['top'].set_linewidth(0.5)
    ax1.spines['bottom'].set_linewidth(0.5)
    ax1.spines['left'].set_linewidth(0.5)
    ax1.spines['right'].set_linewidth(0.5)

    #member indices for different PBL schemes:
    ysu_mem = [0, 1, 6, 7, 12, 13]
    myj_mem = [2, 3, 8, 9, 14, 15]
    mynn_mem = [4, 5, 10, 11, 16, 17]

    temp_indices = np.arange(len(lead_times))

    plt.xlim(*xlimits)
    plt.ylim(-2., 2.)

    x_ticks  = [0, 12, 24, 36, 48, 60, 72]
    x_labels = ['0', '60', '120', '180', '240', '300', '360']
    y_ticks  = [-2, -1.5, -1, -0.5, 0, .5, 1, 1.5, 2]
    #y_labels = ['$2^{-2}$', '', '$2^{-1}$', '', '$2^0$', '', '$2^1$', '', '$2^2$']
    y_labels = ['0.25', '', '0.5', '', '1.0', '', '2.0', '', '4.0']

    ax1.set_xlabel('Forecast Lead Time (min)', fontsize=22)
    ax1.set_ylabel('Area Ratio', fontsize=22)

    plt.xticks(x_ticks, x_labels, fontsize=22, alpha=0.7)
    plt.yticks(y_ticks, y_labels, fontsize=22, alpha=0.7)

    for j in y_ticks:
       plt.plot([-1000, 1000], [j, j], c='k', linewidth=0.75, alpha=0.2)

    for i in x_ticks:
       plt.plot([i, i], [-1000, 1000], c='k', linewidth=0.75, alpha=0.2)

    k = 0
    for obj in objs:
        ax1.fill_between(temp_indices, obj.perc_area_ratio_25, obj.perc_area_ratio_75, color = colors[k], linestyle=lines[k], linewidth=0.3, alpha=0.12)

        for n in range(0, obj.member_perc_area_ratio_mean.shape[0]):
           if (n in ysu_mem):
              temp_color = cb_colors.orange5
           if (n in myj_mem):
              temp_color = cb_colors.green5
           if (n in mynn_mem):
              temp_color = cb_colors.blue5
           ax1.plot(obj.member_perc_area_ratio_mean[n,:], color=temp_color, linestyle=lines[k], linewidth=1., alpha=0.7)

        ax1.plot(obj.perc_area_ratio_mean, color=colors[k], linestyle=lines[k], linewidth=2., alpha=0.8)
        #ax1.plot(var2_indices, var2, color=cb_colors.gray6, linestyle='--', linewidth=2., alpha=0.8)
        k += 1

    add_legend(ax1,0.85,0.88,colors,lines,labels)

    area_ratio_outname = os.path.join(out_dir, out_prefix + '_hit_perc_area_ratio.png')
    print(f"Saving {area_ratio_outname} ....")
    plt.savefig(area_ratio_outname, format='png', dpi=150)

########################################################################

def plot_total_interest(objs,colors,lines,labels):

    fig1 = plt.figure(figsize=(20,5.5))
    ax1 = fig1.add_axes([0.08, 0.14, .88, .82])
    #fig1 = plt.figure(figsize=(10,5))
    #ax1 = fig1.add_axes([0.08, 0.1, .88, .86])
    ax1.spines['top'].set_alpha(0.7)
    ax1.spines['bottom'].set_alpha(0.7)
    ax1.spines['left'].set_alpha(0.7)
    ax1.spines['right'].set_alpha(0.7)
    ax1.spines['top'].set_linewidth(0.5)
    ax1.spines['bottom'].set_linewidth(0.5)
    ax1.spines['left'].set_linewidth(0.5)
    ax1.spines['right'].set_linewidth(0.5)

    #member indices for different PBL schemes:
    ysu_mem = [0, 1, 6, 7, 12, 13]
    myj_mem = [2, 3, 8, 9, 14, 15]
    mynn_mem = [4, 5, 10, 11, 16, 17]

    temp_indices = np.arange(len(lead_times))

    plt.xlim(*xlimits)
    plt.ylim(0, 1)

    x_ticks = [0, 12, 24, 36, 48, 60, 72]
    x_labels = ['0', '60', '120', '180', '240', '300', '360']
    y_ticks = [0, .1, .2, .3, .4, .5, .6, .7, .8, .9, 1.]
    y_labels = ['0', '0.1', '0.2', '0.3', '0.4', '0.5', '0.6', '0.7', '0.8', '0.9', '1.0']

    ax1.set_xlabel('Forecast Lead Time (min)', fontsize=22)
    ax1.set_ylabel('Area Weighted Total Interest', fontsize=22)

    plt.xticks(x_ticks, x_labels, fontsize=22, alpha=0.7)
    plt.yticks(y_ticks, y_labels, fontsize=22, alpha=0.7)

    for j in y_ticks:
       plt.plot([-1000, 1000], [j, j], c='k', linewidth=0.75, alpha=0.2)

    for i in x_ticks:
       plt.plot([i, i], [-1000, 1000], c='k', linewidth=0.75, alpha=0.2)

    k = 0
    for obj in objs:
        ax1.fill_between(temp_indices, obj.ti_25, obj.ti_75, color = colors[k], linewidth=0.3, alpha=0.12)

        for n in range(0, obj.member_ti_mean.shape[0]):
           if (n in ysu_mem):
              temp_color = cb_colors.orange5
           if (n in myj_mem):
              temp_color = cb_colors.green5
           if (n in mynn_mem):
              temp_color = cb_colors.blue5
           ax1.plot(obj.member_ti_mean[n,:], color=temp_color, linestyle=lines[k], linewidth=1., alpha=0.7)

        ax1.plot(obj.ti_mean, color=colors[k], linestyle=lines[k], linewidth=2., alpha=0.8)

        k += 1

    add_legend(ax1,0.85,0.88,colors,lines,labels)

    area_ratio_outname = os.path.join(out_dir, out_prefix + '_hit_ti.png')
    print(f"Saving {area_ratio_outname} ....")
    plt.savefig(area_ratio_outname, format='png', dpi=150)

########################################################################

def plot_object_centroid(objs,colors,lines,labels):

    fig1 = plt.figure(figsize=(20,5.5))
    ax1 = fig1.add_axes([0.08, 0.14, .88, .82])
    #fig1 = plt.figure(figsize=(10,5))
    #ax1 = fig1.add_axes([0.08, 0.1, .88, .86])
    ax1.spines['top'].set_alpha(0.7)
    ax1.spines['bottom'].set_alpha(0.7)
    ax1.spines['left'].set_alpha(0.7)
    ax1.spines['right'].set_alpha(0.7)
    ax1.spines['top'].set_linewidth(0.5)
    ax1.spines['bottom'].set_linewidth(0.5)
    ax1.spines['left'].set_linewidth(0.5)
    ax1.spines['right'].set_linewidth(0.5)

    #member indices for different PBL schemes:
    ysu_mem = [0, 1, 6, 7, 12, 13]
    myj_mem = [2, 3, 8, 9, 14, 15]
    mynn_mem = [4, 5, 10, 11, 16, 17]

    temp_indices = np.arange(len(lead_times))

    plt.xlim(*xlimits)
    plt.ylim(0., 60.)

    x_ticks = [0, 12, 24, 36, 48, 60, 72]
    x_labels = ['0', '60', '120', '180', '240', '300', '360']
    y_ticks = [0, 10, 20, 30, 40, 50, 60]
    y_labels = ['0', '10', '20', '30', '40', '50', '60']

    ax1.set_xlabel('Forecast Lead Time (min)', fontsize=22)
    ax1.set_ylabel('Centroid Displacement (km)', fontsize=22)

    plt.xticks(x_ticks, x_labels, fontsize=22, alpha=0.7)
    plt.yticks(y_ticks, y_labels, fontsize=22, alpha=0.7)

    for j in y_ticks:
       plt.plot([-1000, 1000], [j, j], c='k', linewidth=0.75, alpha=0.2)

    for i in x_ticks:
       plt.plot([i, i], [-1000, 1000], c='k', linewidth=0.75, alpha=0.2)

    k = 0
    for obj in objs:
        ax1.fill_between(temp_indices, obj.cent_dist_25, obj.cent_dist_75, color = colors[k], linestyle=lines[k], linewidth=0.3, alpha=0.12)

        for n in range(0, obj.member_cent_dist_mean.shape[0]):
           if (n in ysu_mem):
              temp_color = cb_colors.orange5
           if (n in myj_mem):
              temp_color = cb_colors.green5
           if (n in mynn_mem):
              temp_color = cb_colors.blue5
           ax1.plot(obj.member_cent_dist_mean[n,:], color=temp_color, linestyle=lines[k], linewidth=1., alpha=0.7)

        ax1.plot(obj.cent_dist_mean, color=colors[k], linestyle=lines[k], linewidth=2., alpha=0.8)

        k += 1

    add_legend(ax1,0.15,0.88,colors,lines,labels)

    area_ratio_outname = os.path.join(out_dir, (out_prefix + '_hit_cent_dist.png'))
    print(f"Saving {area_ratio_outname} ....")
    plt.savefig(area_ratio_outname, format='png', dpi=150)

########################################################################

def plot_object_displacement(objs,colors,lines,labels):
    fig1 = plt.figure(figsize=(20,5.5))
    ax1 = fig1.add_axes([0.08, 0.14, .88, .82])
    #fig1 = plt.figure(figsize=(10,5))
    #ax1 = fig1.add_axes([0.08, 0.1, .88, .86])
    ax1.spines['top'].set_alpha(0.7)
    ax1.spines['bottom'].set_alpha(0.7)
    ax1.spines['left'].set_alpha(0.7)
    ax1.spines['right'].set_alpha(0.7)
    ax1.spines['top'].set_linewidth(0.5)
    ax1.spines['bottom'].set_linewidth(0.5)
    ax1.spines['left'].set_linewidth(0.5)
    ax1.spines['right'].set_linewidth(0.5)

    #member indices for different PBL schemes:
    ysu_mem = [0, 1, 6, 7, 12, 13]
    myj_mem = [2, 3, 8, 9, 14, 15]
    mynn_mem = [4, 5, 10, 11, 16, 17]

    temp_indices = np.arange(len(lead_times))

    plt.xlim(*xlimits)
    plt.ylim(0., 20.)

    x_ticks = [0, 12, 24, 36, 48, 60, 72]
    x_labels = ['0', '60', '120', '180', '240', '300', '360']
    y_ticks = [0, 4, 8, 12, 16, 20]
    y_labels = ['0', '4', '8', '12', '16', '20']

    ax1.set_xlabel('Forecast Lead Time (min)', fontsize=22)
    ax1.set_ylabel('Boundary Displacement (km)', fontsize=22)

    plt.xticks(x_ticks, x_labels, fontsize=22, alpha=0.7)
    plt.yticks(y_ticks, y_labels, fontsize=22, alpha=0.7)

    for j in y_ticks:
       plt.plot([-1000, 1000], [j, j], c='k', linewidth=0.75, alpha=0.2)

    for i in x_ticks:
       plt.plot([i, i], [-1000, 1000], c='k', linewidth=0.75, alpha=0.2)

    k = 0
    for obj in objs:

        ax1.fill_between(temp_indices, obj.bound_dist_25, obj.bound_dist_75, color = colors[k], linestyle=lines[k], linewidth=0.3, alpha=0.12)

        for n in range(0, obj.member_bound_dist_mean.shape[0]):
           if (n in ysu_mem):
              temp_color = cb_colors.orange5
           if (n in myj_mem):
              temp_color = cb_colors.green5
           if (n in mynn_mem):
              temp_color = cb_colors.blue5
           ax1.plot(obj.member_bound_dist_mean[n,:], color=temp_color, linestyle=lines[k], linewidth=1., alpha=0.7)

        ax1.plot(obj.bound_dist_mean, color = colors[k], linestyle=lines[k], linewidth=2., alpha=0.8)
        k += 1

    add_legend(ax1,0.85,0.88,colors,lines,labels)

    area_ratio_outname = os.path.join(out_dir, (out_prefix + '_hit_bound_dist.png'))
    print(f"Saving {area_ratio_outname} ....")
    plt.savefig(area_ratio_outname, format='png', dpi=150)

########################################################################

def plot_object_performance(objs,colors,labels):
    #    x_ticks = [0, 12, 24, 36, 48, 60, 72]
    #   x_labels = ['0', '60', '120', '180', '240', '300', '360']

    pods = []
    fars = []
    times = [0,  36,  72]

    for obj in objs:
        pod=np.mean(obj.pod_lead_time, axis=0)
        pods.append(pod)
        far=np.mean(obj.far_lead_time, axis=0)
        fars.append(far)

    legendonly = False

    purple5 = (188/255., 184/255., 210/255.)
    gray5   = (180/255., 180/255., 180/255.)

    grid = np.arange(0.0,1.005,0.005)

    sr_grid, pod_grid = np.meshgrid(grid,grid)

    sr_grid[sr_grid == 0]   = 0.0001    # To avoid dividing by zero
    pod_grid[pod_grid == 0] = 0.0001

    bias_grid = pod_grid / sr_grid
    csi_grid = 1. / (1. / sr_grid + 1. / pod_grid - 1)

    csi_levels = np.arange(0.1,1.1,0.1)
    csi_colors = [purple5] * 10

    bias_levels = [0.25, 0.5, 1., 1.5, 2., 3., 5.]
    bias_colors = [gray5] * 7

    fig1 = plt.figure(figsize=(4.,4.))
    ax1 = fig1.add_axes([0.13, 0.1, 0.83, 0.8])

    plt.xlim(0.,1.)
    plt.ylim(0.,1.)

    if not legendonly:
        plt.title("MPAS-WoFS Performance", fontsize=8)

        ax1.spines["top"].set_alpha(0.7)
        ax1.spines["bottom"].set_alpha(0.7)
        ax1.spines["left"].set_alpha(0.7)
        ax1.spines["right"].set_alpha(0.7)

        ax1.spines["top"].set_linewidth(0.5)
        ax1.spines["bottom"].set_linewidth(0.5)
        ax1.spines["left"].set_linewidth(0.5)
        ax1.spines["right"].set_linewidth(0.5)

        x_ticks = np.arange(0.,1.1,0.1)
        y_ticks = np.arange(0.,1.1,0.1)

        x_labels = ['0.0', '0.1', '0.2', '0.3', '0.4', '0.5', '0.6', '0.7', '0.8', '0.9', '1.0']
        y_labels = ['0.0', '0.1', '0.2', '0.3', '0.4', '0.5', '0.6', '0.7', '0.8', '0.9', '1.0']


        plt.xticks(x_ticks, x_labels, fontsize=6, alpha=0.7)
        plt.yticks(y_ticks, y_labels, fontsize=6, alpha=0.7)

        plt.tick_params(axis="both", which="both", bottom=True, top=False, labelbottom=True, left=True, right=False, labelleft=True)

        ax1.set_xlabel('Success Ratio (1 - FAR)', fontsize=8, alpha=0.7)
        ax1.set_ylabel('Probability of Detection', fontsize=8, alpha=0.7)

        csi_con  = plt.contour(sr_grid, pod_grid, csi_grid,  levels=csi_levels,  colors=csi_colors,  linewidths=0.30, alpha=0.35)
        bias_con = plt.contour(sr_grid, pod_grid, bias_grid, levels=bias_levels, colors=bias_colors, linewidths=0.30, alpha=0.25)
        plt.clabel(bias_con, fmt='%1.1f', fontsize=6, manual=[(.2, 0.95), (.3, .95), (.47, .95), (.57, .95), (.8, .8), (.8, .42), (.8, .2)])
        plt.clabel(csi_con,  fmt='%1.1f', fontsize=6, manual=[(.92, 0.1), (.92, .2), (.92, 0.3), (.92, .4), (.92, 0.5), (.92, .6),
                                                  (.92, 0.7), (.95, .85), (.95, 0.95)])

    for c,label in enumerate(labels):
        color = colors[c]

        sr = 1 - fars[c]
        for t in times:
           no    = f"{t*5//60:1d}"     # forecast hour
           if legendonly:
               ax1.scatter(0.04,  0.98-c*0.05,       s=120,  color=color,   lw=0.0,     alpha=.75)
               ax1.text(   0.04,  0.98-c*0.05-0.001, no,     color="white", fontsize=8, alpha=1.0, va='center', ha='center')
               ax1.text(   0.09,  0.97-c*0.05,label,  color='black',   fontsize=8, alpha=1.0)    # legend
           else:
               ax1.scatter(sr[t], pods[c][t], s=40,            color=color,   alpha=.65, lw=0.0,)
               ax1.text(   sr[t], pods[c][t], no,  fontsize=3, color="white", alpha=1.0, va='center', ha='center')

        # Members

        #sr = 1 - objs[c].far_lead_time
        #print(f"sr shape = {sr.shape}, len={len(sr)}")
        #for t in times:
        #    no    = f"{t*5//60:1d}"     # forecast hour

        #    for n in range(len(sr)):
        #        ax1.scatter(sr[n,t], objs[c].pod_lead_time[n,t], s=30,            color=color,  alpha=.35, lw=0.0,)
        #        ax1.text(   sr[n,t], objs[c].pod_lead_time[n,t], no,  fontsize=3, color="gray", alpha=.80, va='center', ha='center')

    if legendonly:
        ax1.text(0.04,  0.02, '* case number within circles',fontsize=8, color='black', alpha=0.5)   # legend
        plt.grid(False)
        plt.axis('off')

    if legendonly is not None:
        for c,label in enumerate(labels):
            color=colors[c]
            ax1.scatter(0.04,  0.98-c*0.03,        s=40,  color=color,   lw=0.0,     alpha=.75)
            ax1.text(   0.06,  0.97-c*0.03, label, color='black',   fontsize=4, alpha=1.0)    # legend

        #c=len(labels)+2
        #for key,label in enumerate(labels):
        #    offset = 3*0.02
        #    ax1.text(   0.04,  0.98-c*0.02, f"{key}:", color="black", fontsize=4, alpha=1.0, ha='center')
        #    ax1.text(   0.06,  0.98-c*0.02, key,       color='black', fontsize=4, alpha=1.0)    # legend
        #    c += 1

        ax1.text(0.04,  0.02, '* forecast hour within circles',fontsize=4, color='black', alpha=0.5)   # legend

    pngfile = os.path.join(out_dir, (out_prefix + '_performance.png'))
    print(f"Saving {pngfile} ....")
    plt.savefig(pngfile, format='png', dpi=300)
    plt.close()

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#
# Main function defined to return correct sys.exit() calls
#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

if __name__ == "__main__":

    cargs = parse_args()

    obj_dir1   = cargs.obj_base1
    obj_dir2   = cargs.obj_base2
    out_dir    = cargs.outdir
    out_prefix = cargs.prefix

    obj_time     = False
    obj_age      = False
    obj_area     = False
    obj_area_ratio = False
    obj_interest = False
    obj_centroid = False
    obj_bound = False
    obj_perf  = False

    #time,age,area,interest,centroid
    if "time" in cargs.images:
        obj_time = True
    if "age" in cargs.images:
        obj_age = True
    if "area" in cargs.images:
        obj_area = True
    if "ratio" in cargs.images:
        obj_area_ratio = True
    if "interest" in cargs.images:
        obj_interest = True
    if "centroid" in cargs.images:
        obj_centroid = True
    if "bound" in cargs.images:
        obj_bound = True
    if "performance" in cargs.images:
        obj_perf = True

    if cargs.images == "all":
        obj_time       = True
        obj_age        = True
        obj_area       = True
        obj_area_ratio = True
        obj_interest   = True
        obj_centroid   = True
        obj_bound      = True

    #Static variables:

    fcst_init_times = ['1700', '1800', '1900', '2000', '2100', '2200', '2300', '0000', '0100', '0200', '0300'] #WoFS initialization times to consider

    ne = 18 #number of ensemble members

    lead_times = np.array([  0.,   5.,  10.,  15.,  20.,  25.,  30.,  35.,  40.,  45.,  50.,
            55.,  60.,  65.,  70.,  75.,  80.,  85.,  90.,  95., 100., 105.,
           110., 115., 120., 125., 130., 135., 140., 145., 150., 155., 160.,
           165., 170., 175., 180., 185., 190., 195., 200., 205., 210., 215.,
           220., 225., 230., 235., 240., 245., 250., 255., 260., 265., 270.,
           275., 280., 285., 290., 295., 300., 305., 310., 315., 320., 325.,
           330., 335., 340., 345., 350., 355., 360.])

    #lead_times_3hr = np.array([  0.,   5.,  10.,  15.,  20.,  25.,  30.,  35.,  40.,  45.,  50.,
    #        55.,  60.,  65.,  70.,  75.,  80.,  85.,  90.,  95., 100., 105.,
    #       110., 115., 120., 125., 130., 135., 140., 145., 150., 155., 160.,
    #       165., 170., 175., 180.])

    xlimits  = [0,72]
    #xlimits = [-3, 75]

    lead_time_indices = np.arange(len(lead_times))
    #lead_time_3hr_indices = np.arange(len(lead_times_3hr))

    #area_bins = np.array([18., 36., 72., 120.])
    area_bins = np.arange(12,240,12)
    area_bins_plot = np.arange(6,246,12)
    area_ticks = np.arange(0, 252, 12)

    #age_bins = np.arange(0.,5400.,1800.)
    age_bins = np.arange(-14400.,15300.,1800.)
    age_bins_plot = np.arange(-15300.,16200.,1800.)
    age_ticks = np.arange(-16200, 18000, 1800)

    deep = sns.color_palette('deep')

    #### Aggregate Object Properties across all forecasts: #################

    print(f"\nReading cb-WoFS   objects from {obj_dir1}:")
    wofs_obj = read_objs(obj_dir1,ne,lead_times,age_bins,area_bins,
                         obj_time,obj_age,obj_area, obj_area_ratio,obj_interest,obj_centroid,obj_bound)

    print(f"\nReading mpas-WoFS objects from {obj_dir2}:")
    mpas_obj = read_objs(obj_dir2,ne,lead_times,age_bins,area_bins,
                         obj_time,obj_age,obj_area, obj_area_ratio,obj_interest,obj_centroid,obj_bound)

    if cargs.obj_base3 is not None:
        print(f"\nReading mpas-WoFS objects from {obj_dir2}:")
        mpas3_obj = read_objs(cargs.obj_base3,ne,lead_times,age_bins,area_bins,
                         obj_time,obj_age,obj_area, obj_area_ratio,obj_interest,obj_centroid,obj_bound)

    ####################### plot time series of contingency table stats

    obj_names = ['cb-WoFS','mpas-WoFS']
    colors = ['k','r']; lines = ['-', '--']

    if obj_time:
        plot_time_series(wofs_obj,mpas_obj,colors,lines,obj_names)

    ######### OBJECT AGE SECTION #########

    if obj_age:
        plot_object_age([wofs_obj,mpas_obj],obj_names)

    ######### MRMS OBJECT AREA SECTION #########

    if obj_area:
        plot_object_area([wofs_obj,mpas_obj],obj_names)

    ######### AREA RATIOS:  ###########

    if obj_area_ratio:
        plot_area_ratio([wofs_obj,mpas_obj],colors,lines,obj_names)

    ######### TOTAL INTEREST DIFFERENCE:  ###########

    if obj_interest:
        plot_total_interest([wofs_obj,mpas_obj],colors,lines,obj_names)

    ######### CENTROID / BOUNDARY DIFFERENCE:  ###########

    if obj_centroid:
        plot_object_centroid([wofs_obj,mpas_obj],colors,lines,obj_names)
    #

    if obj_bound:
        plot_object_displacement([wofs_obj,mpas_obj],colors,lines,obj_names)


    if obj_perf:
        obj_names = ['cb-WoFS','mpas-WoFS','mpas_2024']
        colors = ['g','b','r']
        plot_object_performance([wofs_obj,mpas_obj,mpas3_obj],colors,obj_names)