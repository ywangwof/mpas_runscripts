#!/usr/bin/env python

#-------------------------------------------------------------------------------

import sys
import os
import datetime as DT
import numpy as np
import numpy.ma as ma
import math
from optparse import OptionParser
import netCDF4
#import xarray as xr
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import matplotlib as mpl
import pandas as pd
from scipy.stats import iqr
import scipy.stats as st
from matplotlib.colors import BoundaryNorm
from wofs_colortables import cb_colors


#-------------------------------------------------------------------------------
# Plotting functions
def bin_efss_data(efbs,efbsr,scales,thlds):

    nth = len(thlds)
    ns = len(scales)

    efss = np.zeros((nth,ns))

    for row in range(nth):
        for col in range(ns):
            efss[row,col] = 1. - np.nanmean(efbs[:,:,:,col,row])/np.nanmean(efbsr[:,:,:,col,row])

    return efss


def bin_fss_data(fbs,fbsr,scales,thlds):

    nth = len(thlds)
    ns = len(scales)

    fss = np.zeros((nth,ns))

    for row in range(nth):
        for col in range(ns):
            fss[row,col] = 1. - np.nanmean(fbs[:,:,:,:,col,row])/np.nanmean(fbsr[:,:,:,:,col,row])

    return fss


def bin_efss_data_hour(efbs,efbsr,scales,thlds):

    nth = len(thlds)
    ns = len(scales)

    efss = np.zeros((nth,ns))

    for row in range(nth):
        for col in range(ns):
            efss[row,col] = 1. - np.nanmean(efbs[:,:,col,row])/np.nanmean(efbsr[:,:,col,row])

    return efss


def aggr_efss(efbs,efbsr):

    nt = len(efbs[0,0,:])

    efss = np.zeros(nt)

    for row in range(nt):
        efss[row] = 1. - np.nanmean(efbs[:,:,row])/np.nanmean(efbsr[:,:,row])

    return efss


def aggr_fss(fbs,fbsr):

    nt = len(fbs[0,0,0,:])
    ne = len(fbs[0,0,:,0])

    fss = np.zeros((ne,nt))
    #fss = np.zeros((nt))

    for row in range(ne):
        for col in range(nt):
            fss[row,col] = 1. - np.nanmean(fbs[:,:,row,col])/np.nanmean(fbsr[:,:,row,col])
    #for col in range(nt):
    #    fss[col] = 1. - np.nanmean(fbs[:,:,:,col])/np.nanmean(fbsr[:,:,:,col])

    return fss


def heatmap_width_inten_diff_mpas(outdir,efbs,efbsr,mefbs,mefbsr,scales,thlds,exper,year1,year2):

    wofsefss = bin_efss_data(efbs,efbsr,scales,thlds)
    mpasefss = bin_efss_data(mefbs,mefbsr,scales,thlds)

    diffefss = wofsefss - mpasefss
    figsize = (10,12)
    xname = "width"
    xti = "Neighborhood Width"
    xunit = "km"
    yname = "intensity"
    yti = "Reflectivity Threshold"
    yunit = "dBZ"
    xticks = np.arange(len(scales))
    xticklabels = np.array(scales)
    yticks = np.arange(len(thlds))
    yticklabels = np.array(thlds)

    cbx = 0.85
    cbwidth = 0.02

    fig, ax = plt.subplots(figsize=figsize)
    cmap = plt.get_cmap('bwr', 100)
    norm = BoundaryNorm(np.linspace(-0.2,0.2,17), cmap.N)

    cs1 = plt.imshow(diffefss, cmap=cmap, norm=norm, origin='lower')

    for xpt in range(len(diffefss[:,0])):
       for ypt in range(len(diffefss[0,:])):
          text = ax.text(ypt, xpt, '{:.2f}'.format(diffefss[xpt,ypt]), ha="center", va="center", color="k",fontsize=10)

    plt.xlabel('{} ({})'.format(xti,xunit),fontsize=15)
    plt.ylabel('{} ({})'.format(yti,yunit),fontsize=15)

    ax.set_xticks(xticks)
    ax.set_xticklabels(xticklabels,fontsize=15)
    ax.set_yticks(yticks)
    ax.set_yticklabels(yticklabels,fontsize=15)
    ax.set_title('eFSS Difference (cb-WoFS - MPAS-WoFS)', fontsize=20)

    ax.set_aspect(1.0, adjustable='box')

    cbar1 = plt.colorbar(cs1,shrink=0.5,ticks=np.linspace(-0.3,0.3,13))
    cbar1.set_label('eFSS Difference', fontsize=15)
    outfile=os.path.join(outdir,'efss_heatmap_{}_vs_{}_{}-{}_{}.png'.format(xname,yname,year1,year2,exper))
    print(f"Saving {outfile} ....")
    plt.savefig(outfile, dpi=300, bbox_inches='tight')


def time_series_efss_mpas(outdir,wefbs, wefbsr, wfbs, wfbsr, mefbs, mefbsr, mfbs, mfbsr, nsize, thld, exper, year1, year2):

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

    wefss = aggr_efss(wefbs,wefbsr)
    wfss = aggr_fss(wfbs,wfbsr)
    mefss = aggr_efss(mefbs,mefbsr)
    mfss = aggr_fss(mfbs,mfbsr)

    ysu_mem = [0, 1, 6, 7, 12, 13]
    myj_mem = [2, 3, 8, 9, 14, 15]
    mynn_mem = [4, 5, 10, 11, 16, 17]

    plt.xlim(0, 72)
    plt.ylim(0, 1.)

    x_ticks = [0, 12, 24, 36, 48, 60, 72]
    x_labels = ['0', '60', '120', '180', '240', '300', '360']
    y_ticks = [0, .1, .2, .3, .4, .5, .6, .7, .8, .9, 1.]
    y_labels = ['0', '0.1', '0.2', '0.3', '0.4', '0.5', '0.6', '0.7', '0.8', '0.9', '1.0']

    ax1.set_xlabel('Forecast Lead Time (min)', fontsize=14)
    ax1.set_ylabel('eFSS and FSS', fontsize=14)
    ax1.set_title('{} eFSS and FSS: {} dBZ, {} km'.format(year1,thld,nsize), fontsize=20)

    plt.xticks(x_ticks, x_labels, fontsize=14, alpha=1.0)
    plt.yticks(y_ticks, y_labels, fontsize=14, alpha=1.0)

    for j in y_ticks:
       plt.plot([-1000, 1000], [j, j], c='k', linewidth=0.5, alpha=0.2)

    for i in x_ticks:
       plt.plot([i, i], [-1000, 1000], c='k', linewidth=0.5, alpha=0.2)

    for n in range(0, wfss.shape[0]):
       if (n in ysu_mem):
          temp_color = cb_colors.green4
       if (n in myj_mem):
          temp_color = cb_colors.green6
       if (n in mynn_mem):
          temp_color = cb_colors.green8
       ax1.plot(wfss[n,:], color=temp_color, linewidth=1., alpha=0.5)

    for n in range(0, mfss.shape[0]):
       if (n in ysu_mem):
          temp_color = cb_colors.purple4
       if (n in myj_mem):
          temp_color = cb_colors.purple6
       if (n in mynn_mem):
          temp_color = cb_colors.purple8
       ax1.plot(mfss[n,:], color=temp_color, linestyle='--', linewidth=1., alpha=0.5)

    ax1.plot(wefss, color=cb_colors.green9, linewidth=2., alpha=0.8, label="cb-WoFS")
    ax1.plot(mefss, color=cb_colors.purple9, linestyle='--', linewidth=2., alpha=0.8, label="MPAS-WoFS")

    ax1.legend(loc='upper right', fontsize=14)
    outfile = os.path.join(outdir,'efss_timeseries_{}_{}-{}_{}_{}.png'.format(exper,year1,year2,nsize,thld))
    print(f"Saving {outfile} ....")
    plt.savefig(outfile, format='png', dpi=300, bbox_inches='tight')
