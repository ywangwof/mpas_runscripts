#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Tue Jan  2 15:08:32 2024

@author: asdf
"""

import matplotlib
from scipy import signal
from scipy import *
from scipy import ndimage
from scipy.stats.kde import gaussian_kde
import math
from math import radians, tan, sin, cos, pi, atan, sqrt, pow, asin, acos
import pylab as plt
import numpy as np
from numpy import NAN
import sys, glob
import netCDF4
from optparse import OptionParser
import os
import time as timeit
import seaborn as sns
from optparse import OptionParser
from multiprocessing import Pool
#import verif_plotting_cbook
#from verif_plotting_cbook import *

####################################### File Variables: ######################################################

# parser = OptionParser()
# parser.add_option("-d", dest="in_dir", type="string", default= None, help="Input directory 1")
# parser.add_option("-e", dest="in_dir2", type="string", default= None, help="Input directory 2")
# parser.add_option("-f", dest="in_dir3", type="string", default= None, help="Input directory 3")
# parser.add_option("-o", dest="out_dir", type="string", help = "Output Directory")
# parser.add_option("-p", dest="prefix", type="string", help = "Prefix for image names")

# (options, args) = parser.parse_args()

# if ((options.in_dir == None) or (options.in_dir2 == None) or (options.in_dir3 == None) or (options.out_dir == None) or (options.prefix == None)):
#    print
#    parser.print_help()
#    print
#    sys.exit(1)
# else:
#    in_dir = options.in_dir
#    in_dir2 = options.in_dir2
#    in_dir3 = options.in_dir3
#    out_dir = options.out_dir
#    prefix = options.prefix

in_dir = '/scratch/ywang/MPAS/intel/run_dirs/VERIF/wofs_hist/'
in_dir2 = '/scratch/ywang/MPAS/intel/run_dirs/VERIF/mpas_hist/'
in_dir3 = '/scratch/ywang/MPAS/intel/run_dirs/VERIF/mrms_hist/'

out_dir = '/scratch/ywang/MPAS/intel/run_dirs/VERIF/'
prefix = 'dz_climo_2024'

############################ User Defined Variables: #################################

#var_bins = np.arange(0., 81., 1.)
#plot_bins = np.arange(0.5, 80.5, 1.)
var_bins = np.arange(-0.1, 80.1, 0.2)
plot_bins = np.arange(0., 80., 0.2)

dummy = np.arange(1) * 0. #used to initialize histograms of 0's

var_hist = np.arange(len(var_bins)-1) * 0.
var_hist2 = np.arange(len(var_bins)-1) * 0.
var_hist3 = np.arange(len(var_bins)-1) * 0.

deep = sns.color_palette('deep')

colors = [ deep[0],       deep[1], deep[7]]
labels = [ "cb-WoFS", "mpas-WoFS", "MRMS"]

#np.histogram(dummy, var_bins)
#var_smooth = np.histogram(dummy, var_bins)
#var_difference = np.histogram(dummy, var_bins)

############################ Find WRFOUT files to process: #################################

### Hist #1 ###

var_files = os.listdir(in_dir)

for f, var_file in enumerate(var_files):
   infile = os.path.join(in_dir, var_file)

   try:                                                 #open WRFOUT file
      fin = netCDF4.Dataset(infile, "r")
      print ("Opening %s \n" % infile)
   except:
      print ("%s does not exist! \n" %infile)
      sys.exit(1)

   var_hist_temp = fin.variables['var_hist'][:]

   var_hist = var_hist + var_hist_temp

   fin.close()
   del fin

var_hist[0] = 0. #set 0 dBZ count to 0 to ignore

### Hist #2 ###

var_files2 = os.listdir(in_dir2)

for f, var_file in enumerate(var_files2):
   infile = os.path.join(in_dir2, var_file)

   try:                                                 #open WRFOUT file
      fin = netCDF4.Dataset(infile, "r")
      print ("Opening %s \n" % infile)
   except:
      print ("%s does not exist! \n" %infile)
      sys.exit(1)

   var_hist_temp = fin.variables['var_hist'][:]

   var_hist2 = var_hist2 + var_hist_temp

   fin.close()
   del fin

var_hist2[0] = 0. #set 0 dBZ count to 0 to ignore

### Hist #3 ###

var_files3 = os.listdir(in_dir3)

for f, var_file in enumerate(var_files3):
   infile = os.path.join(in_dir3, var_file)

   try:                                                 #open WRFOUT file
      fin = netCDF4.Dataset(infile, "r")
      print ("Opening %s \n" % infile)
   except:
      print ("%s does not exist! \n" %infile)
      sys.exit(1)

   var_hist_temp = fin.variables['var_hist'][:]

   var_hist3 = var_hist3 + var_hist_temp

   fin.close()
   del fin

var_hist3[0] = 0. #set 0 dBZ count to 0 to ignore

normal_var_hist = var_hist / var_hist.sum()
cdf_hist = np.cumsum(normal_var_hist)

normal_var_hist2 = var_hist2 / var_hist2.sum()
cdf_hist2 = np.cumsum(normal_var_hist2)

normal_var_hist3 = var_hist3 / var_hist3.sum()
cdf_hist3 = np.cumsum(normal_var_hist3)

normal_var_hist[0] = np.nan
normal_var_hist2[0] = np.nan
normal_var_hist3[0] = np.nan

################# PDF plot. #####################

fig1 = plt.figure(figsize=(8.,5.))
ax1 = fig1.add_axes([0.12, 0.14, 0.84, 0.82])
ax1.spines["top"].set_alpha(0.7)
ax1.spines["top"].set_linewidth(0.5)
ax1.spines["bottom"].set_alpha(0.7)
ax1.spines["left"].set_alpha(0.7)
ax1.spines["bottom"].set_linewidth(0.5)
ax1.spines["left"].set_linewidth(0.5)

ax1.spines["right"].set_linewidth(0.5)
ax1.spines["right"].set_alpha(0.7)

xmin = 0.
xmax = 80.
x_axis = np.arange(xmin,(xmax+1))

ymin = 0.
ymax = 0.03

plt.xlim(xmin,xmax)
plt.ylim(ymin,ymax)

#y_ticks = [0., 0.01, 0.02, 0.03, 0.04, 0.05, 0.06, 0.07, 0.08, 0.09, 0.1]
#y_labels = ['', '0.01', '', '0.03', '', '0.05', '', '0.07', '', '0.09', '']

y_ticks = [0., 0.01, 0.015, 0.02, 0.025, 0.03]
y_labels = ['', '0.010', '0.015','0.020', '0.025','0.030']

x_ticks = [0, 10, 20, 30, 40, 50, 60, 70, 80]
x_labels = ['', '10', '20', '30', '40', '50', '60', '70', '80']

plt.xticks(x_ticks, x_labels, fontsize=14, alpha=0.7)
plt.yticks(y_ticks, y_labels, fontsize=14, alpha=0.7)

#P.tick_params(axis="both", which="both", bottom="on", top="off", labelbottom="on", left="on", right="off", labelleft="on")

ax1.set_xlabel('Composite Reflectivity (dBZ))', fontsize=14, alpha=.8)
ax1.set_ylabel('Frequency', fontsize=14, alpha=.8)

#ax1.set_yscale('log')

for y in y_ticks:
   plt.plot(x_axis, (x_axis * 0. + y), linewidth=0.5, color='k', alpha=0.15)
for x in x_ticks:
   plt.plot([x,x], [0., 1], linewidth=0.5, color='k', alpha=0.15)

#ax1.hist(var_instant, var_bins, color=cb_colors.orange6, alpha = 0.5)
#ax1.hist(var_smooth, var_bins, color=cb_colors.blue6, alpha = 0.5)

ax1.plot(plot_bins, normal_var_hist,  linewidth=2., color=colors[0], alpha = 0.8, label=labels[0])
ax1.plot(plot_bins, normal_var_hist2, linewidth=2., color=colors[1], alpha = 0.8, label=labels[1])
ax1.plot(plot_bins, normal_var_hist3, linewidth=2., color=colors[2], alpha = 0.7, label=labels[2])

ax1.legend()

temp_path = out_dir + prefix + '_comp_dz_pdf.png'
plt.savefig(temp_path, format="png", dpi=300)
plt.close(fig1)

################# CDF plot. #####################

fig1 = plt.figure(figsize=(8.,5.))
ax1 = fig1.add_axes([0.16, 0.14, 0.8, 0.82])
ax1.spines["top"].set_alpha(0.7)
ax1.spines["top"].set_linewidth(0.5)
ax1.spines["bottom"].set_alpha(0.7)
ax1.spines["left"].set_alpha(0.7)
ax1.spines["bottom"].set_linewidth(0.5)
ax1.spines["left"].set_linewidth(0.5)

ax1.spines["right"].set_linewidth(0.5)
ax1.spines["right"].set_alpha(0.7)

xmin = 0.
xmax = 80.
x_axis = np.arange(xmin,(xmax+1))

ymin = 0.
ymax = 0.03

plt.xlim(xmin,xmax)
plt.ylim(ymin,ymax)

y_ticks = [0., 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
y_labels = ['0.', '10', '20', '30', '40', '50', '60', '70', '80', '90', '100']

x_ticks = [0, 10, 20, 30, 40, 50, 60, 70, 80]
x_labels = ['0', '10', '20', '30', '40', '50', '60', '70', '80']

plt.xticks(x_ticks, x_labels, fontsize=14, alpha=0.7)
plt.yticks(y_ticks, y_labels, fontsize=14, alpha=0.7)

#P.tick_params(axis="both", which="both", bottom="on", top="off", labelbottom="on", left="on", right="off", labelleft="on")

ax1.set_xlabel('Composite Reflectivity (dBZ))', fontsize=14, alpha=.8)
ax1.set_ylabel('Percentile', fontsize=14, alpha=.8)

#ax1.set_yscale('log')

for y in y_ticks:
   plt.plot(x_axis, (x_axis * 0. + y), linewidth=0.5, color='k', alpha=0.15)
for x in x_ticks[1:-1]:
   plt.plot([x,x], [0., 101], linewidth=0.5, color='k', alpha=0.15)

#ax1.hist(var_instant, var_bins, color=cb_colors.orange6, alpha = 0.5)
#ax1.hist(var_smooth, var_bins, color=cb_colors.blue6, alpha = 0.5)

ax1.plot(plot_bins, cdf_hist,  linewidth=2., color=colors[0], alpha = 0.8, label=labels[0])
ax1.plot(plot_bins, cdf_hist2, linewidth=2., color=colors[1], alpha = 0.8, label=labels[1])
ax1.plot(plot_bins, cdf_hist3, linewidth=2., color=colors[2], alpha = 0.7, label=labels[2])

ax1.legend()

temp_path = out_dir + prefix + '_comp_dz_cdf.png'
plt.savefig(temp_path, format="png", dpi=300)
plt.close(fig1)

################# CDF right tail plot. #####################

fig1 = plt.figure(figsize=(8.,5.))
ax1 = fig1.add_axes([0.16, 0.14, 0.8, 0.82])
ax1.spines["top"].set_alpha(0.7)
ax1.spines["top"].set_linewidth(0.5)
ax1.spines["bottom"].set_alpha(0.7)
ax1.spines["left"].set_alpha(0.7)
ax1.spines["bottom"].set_linewidth(0.5)
ax1.spines["left"].set_linewidth(0.5)

ax1.spines["right"].set_linewidth(0.5)
ax1.spines["right"].set_alpha(0.7)

xmin = 30.
xmax = 70.
x_axis = np.arange(xmin,(xmax+1))

ymin = 0.78
ymax = 1.01

plt.xlim(xmin,xmax)
plt.ylim(ymin,ymax)

y_ticks = [0.78, 0.8, 0.82, 0.84, 0.86, 0.88, 0.9, 0.92, 0.94, 0.96, 0.98, 1.0]
y_labels = ['78', '80', '82', '84', '86', '88', '90', '92', '94', '96', '98', '100']

x_ticks = [30, 40, 50, 60, 70]
x_labels = ['30', '40', '50', '60', '70']

plt.xticks(x_ticks, x_labels, fontsize=14, alpha=0.7)
plt.yticks(y_ticks, y_labels, fontsize=14, alpha=0.7)

#P.tick_params(axis="both", which="both", bottom="on", top="off", labelbottom="on", left="on", right="off", labelleft="on")

ax1.set_xlabel('Composite Reflectivity (dBZ))', fontsize=14, alpha=.8)
ax1.set_ylabel('Percentile', fontsize=14, alpha=.8)

#ax1.set_yscale('log')

for y in y_ticks:
   plt.plot(x_axis, (x_axis * 0. + y), linewidth=0.5, color='k', alpha=0.15)
for x in x_ticks[1:-1]:
   plt.plot([x,x], [0., 101], linewidth=0.5, color='k', alpha=0.15)

#ax1.hist(var_instant, var_bins, color=cb_colors.orange6, alpha = 0.5)
#ax1.hist(var_smooth, var_bins, color=cb_colors.blue6, alpha = 0.5)

ax1.plot(plot_bins, cdf_hist,  linewidth=2., color=colors[0], alpha = 0.8, label=labels[0])
ax1.plot(plot_bins, cdf_hist2, linewidth=2., color=colors[1], alpha = 0.8, label=labels[1])
ax1.plot(plot_bins, cdf_hist3, linewidth=2., color=colors[2], alpha = 0.7, label=labels[2])

ax1.legend()

temp_path = out_dir + prefix + '_comp_dz_cdf_righttail.png'
plt.savefig(temp_path, format="png", dpi=300)
plt.close(fig1)

dz_thresh = [37., 40., 42., 43., 45., 47., 48.]

print(f"  {labels[2]} Percentile  {labels[0]} {labels[1]}")
print( " ----- ---------- -------- ---------")
for temp_thresh in dz_thresh:
   temp_thresh_ind = np.argmin(np.abs(plot_bins - temp_thresh))
   temp_mrms_perc = cdf_hist3[temp_thresh_ind]
   temp_wofs_ind = np.argmin(np.abs(cdf_hist - temp_mrms_perc))
   temp_hrrr_ind = np.argmin(np.abs(cdf_hist2 - temp_mrms_perc))
   temp_wofs_thresh = plot_bins[temp_wofs_ind]
   temp_hrrr_thresh = plot_bins[temp_hrrr_ind]
   print(f"{temp_thresh:6.2f} {temp_mrms_perc*100.:10.2f} {temp_wofs_thresh:8.2f} {temp_hrrr_thresh:8.2f}")
print("")

#for i in range(0, len(cdf_hist)):
#   print(plot_bins[i], cdf_hist[i], cdf_hist2[i], cdf_hist3[i])


