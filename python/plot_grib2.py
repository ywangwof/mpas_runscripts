#!/usr/bin/env python
#
# This module plots GRIB2 2D/3D fields on a horizontal slice
# using xarray enginee or cfgrib.
#
#-----------------------------------------------------------------------
#
# By Yunheng Wang (NOAA/NSSL, 2023.04.26)
# Based on Larissa Reams's original script of plot_conus.py
#
#-----------------------------------------------------------------------

import os
import sys
import re
import math
import argparse

import numpy as np

''' By default matplotlib will try to open a display windows of the plot, even
though sometimes we just want to save a plot. Somtimes this can cause the
program to crash if the display can't open. The two commands below makes it so
matplotlib doesn't try to open a window
'''
import matplotlib
matplotlib.use('Agg')

import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
# '''
# cm = Color Map. Within the matplotlib.cm module will contain access to a number
# of colormaps for a plot. A reference to colormaps can be found at:
#
#     - https://matplotlib.org/examples/color/colormaps_reference.html
# '''
import matplotlib.cm as cm
import matplotlib.colors as colors
from metpy.plots import ctables

#import scipy.interpolate as interpolate
from shapely.geometry.polygon import Polygon


import cartopy.crs as ccrs
import cartopy.feature as cfeature

import csv
import xarray as xr

#import strmrpt

########################################################################

def dumpobj(obj, level=0, maxlevel=10):
    for a in dir(obj):
        val = getattr(obj, a)
        if  a.startswith("__") and a.endswith("__") or a.startswith("_"):
            continue
        elif isinstance(val, (int, float, str, list, dict, set)):
            print(f"{level*'    '} {a} -> {val}")
        else:
            print(f"{level*'    '} {a} -> {val}")
            if level >= maxlevel:
                return
            dumpobj(val, level=level+1,maxlevel=maxlevel)

def fnormalize(fmin,fmax):
    min_e = int(math.floor(math.log10(abs(fmin)))) if fmin != 0 else 0
    max_e = int(math.floor(math.log10(abs(fmax)))) if fmax != 0 else 0
    fexp = min(min_e, max_e)-2
    min_m = fmin/10**fexp
    max_m = fmax/10**fexp

    return min_m, max_m, fexp

def get_var_contours(varname,var2d,colormaps,cntlevels):
    '''set contour specifications'''

    #
    # set color map to be used
    #
    color_map = colormaps[0]
    if varname.startswith('refl'):    # Use reflectivity color map and range
        color_map = colormaps[1]

    #
    # set contour levels
    #
    if cntlevels is not None:
        cmin,cmax,cinc = cntlevels
        cntlevels = np.arange(cmin,cmax+0.01*cinc,cinc)
        normc = colors.Normalize(cmin,cmax)
    else:
        pmin = var2d.min()
        pmax = var2d.max()
        if varname.startswith('refl'):    # Use reflectivity color map and range
            cmin = 0.0
            cmax = 5*pmax//5
            cntlevels = list(np.arange(cmin,cmax,5.0))
            normc = colors.Normalize(0.0,80.0)
        else:
            cmin, cmax, cexp = fnormalize(pmin,pmax)
            minc = np.floor(cmin)
            maxc = np.ceil(cmax)

            for n in range(16,7,-1):
                if (maxc-minc)%n == 0:
                    break
            if n == 8: n = 16
            minc = minc*10**cexp
            maxc = maxc*10**cexp
            cntlevels = list(np.linspace(minc,maxc,n+1))
            maxc = minc + 16* (maxc-minc)/n
            normc = colors.Normalize(minc,maxc)

    #print(cntlevels)

    return color_map, normc, cntlevels

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#
# Main function defined to return correct sys.exit() calls
#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

if __name__ == "__main__":

    parser = argparse.ArgumentParser(description='Plot grib2 variables using Cartopy',
                                     epilog='''        ---- Yunheng Wang (2023-04-26).
                                            ''')
                                     #formatter_class=CustomFormatter)

    typeoflevels = [
    'hybrid',     'depthBelowLandLayer',    'atmosphere',      'cloudTop',
    'surface',    'heightAboveGround',      'isothermal',      'pressureFromGroundLayer',
    'sigmaLayer', 'meanSea',                'isobaricInhPa',   'heightAboveGroundLayer',
    'sigma',      'atmosphereSingleLayer',  'depthBelowLand',  'isobaricLayer',
    'lowCloudLayer', 'middleCloudLayer',    'highCloudLayer',  'cloudCeiling',
    'cloudBase',   'nominalTop',            'isothermZero',    'highestTroposphericFreezing',
    'adiabaticCondensation',                'equilibrium',     'unknown']
    parser.add_argument('fcstfiles',nargs='+', help='GRIB2 files')
    parser.add_argument('varname', help='Name of variable to be plotted',type=str, default=None)

    parser.add_argument('-v','--verbose',   help='Verbose output',                 action="store_true", default=False)
    #parser.add_argument('-latlon'       ,   help='Base map latlon or lambert',action='store_true', default=True)
    parser.add_argument('--latlon',         help='Base map latlon',                action='store_true')
    parser.add_argument('--no-latlon',      help='Base map lambert',dest='latlon', action='store_false')
    parser.set_defaults(latlon=True)
    parser.add_argument('-t','--typeOfLevel',help=f'Vertical level type, one of {typeoflevels}',  type=str, default=None)
    parser.add_argument('-f','--filter',     help=f'grib2 field filter',  type=str, default=None)
    parser.add_argument('-l','--vertLevels',help='Vertical levels to be plotted [l1,l2,l3,...]',  type=str, default=None)
    parser.add_argument('-c','--cntLevels', help='Contour levels [cmin,cmin,cinc]',               type=str, default=None)
    parser.add_argument('-o','--outfile',   help='Name of output image or output directory',      type=str, default=None)

    args = parser.parse_args()

    basmap = "latlon"
    if not args.latlon:
        basmap = "lambert"

    fcstfiles = []
    varnames  = []
    for fcstfile in args.fcstfiles:
        if  os.path.lexists(fcstfile):
            fcstfiles.append(fcstfile)
        else:
            varnames.append(fcstfile)

    if os.path.lexists(args.varname):  # if the two arguments are out-of-order
        fcstfiles.append(args.varname)
    else:
        varnames.append(args.varname)

    if len(varnames) > 1:
        print(f"variable name can only be one. Got \"{varnames}\"")
        sys.exit(0)

    varname = varnames[0]

    caldiff = False
    diffstr = ""
    if len(fcstfiles) == 2:
        caldiff = True
        fcstfile = fcstfiles[0]
        diffstr = "_diff"
    elif len(fcstfiles) == 1:
        fcstfile = fcstfiles[0]
    else:
        print(f"Found too many files. Got \"{fcstfiles}\"")
        sys.exit(0)

    if args.filter is not None:
        filters = eval(args.filter)
    else:
        filters = {}

    typeoflevel = 'hybrid'  # isobaricInhPa, surface, hybrid
    if args.typeOfLevel in typeoflevels:
        typeoflevel = args.typeOfLevel
    filters['typeOfLevel'] = typeoflevel

    if os.path.lexists(fcstfile):

        with xr.open_dataset(fcstfile, engine='cfgrib', filter_by_keys=filters) as mesh:
            #
            # decode gridfile for latitudes/longitudes
            #
            glats = np.array(mesh.latitude)
            glons = np.array(mesh.longitude)

            nx   = mesh.sizes["x"]
            ny   = mesh.sizes["y"]

            if varname == "list":
                varlist = []
                for varname in list(mesh.keys()):
                    var = mesh[varname]
                    vndim   = len(var.shape)
                    vshapes = var.shape

                    varstr = f"{var.name:24s}: {vndim}D {var.long_name} ({var.units})"
                    varlist.append(varstr)

                print("\n---- All Variables ----")
                for varstr in sorted(varlist):
                    print(varstr)

                sys.exit(0)
            elif varname not in list(mesh.keys()):
                # Check to see the variable is in the mesh
                print(f"This variable \"{varname}\" was not found in this grib2 file!")
                sys.exit(-1)

            # Pull the variable out of the mesh. Now we can manipulate it any way we choose
            # do some 'post-processing' or other meteorological stuff
            variable = mesh[varname]
            varunits = variable.units
            varndim  = len(variable.shape)
            varshapes = variable.shape
            vardata   = variable.values
            vartime   = variable.valid_time
            if varndim == 3:
                varlevels = variable[typeoflevel]
            else:
                varlevels = [0]

        if caldiff:
            with xr.open_dataset(fcstfiles[1], engine='cfgrib', filter_by_keys=filters) as mesh:
                vardata = vardata - mesh[varname].values
    else:
        print("ERROR: need a GRIB2 file.")
        sys.exit(0)

    fcsttime  = np.datetime_as_string(variable.valid_time, unit='m')
    fcstfname = fcsttime

    if varndim == 2:
        levels=[0]
    elif varndim == 3:
        levels=range(0,len(varlevels))

        if args.vertLevels is not None:
            pattern = re.compile("^([0-9]+)-([0-9]+)$")
            pmatched = pattern.match(args.vertLevels)
            if pmatched:
                levels=range(int(pmatched[1]),int(pmatched[2]))
            elif args.vertLevels in ["max",]:
                levels=["max",]
            else:
                levels = [int(item) for item in args.vertLevels.split(',')]
    else:
        print(f"Do not supported {varndim} dimensions array.")
        sys.exit(0)

    #
    # Output file dir / file name
    #
    if args.outfile is None:
        outdir  = './'
        outfile = None
        defaultoutfile = True
    elif os.path.isdir(args.outfile):
        outdir  = args.outfile
        outfile = None
        defaultoutfile = True
    else:
        outdir  = os.path.dirname(args.outfile)
        outfile = os.path.basename(args.outfile)

    #
    # decode contour specifications
    #
    if args.cntLevels is None:
        cntlevel = None
    else:
        cntlevel = [float(item) for item in args.cntLevels.split(',')]
        if len(cntlevel) != 3:
            print(f"Option -c must be [cmin,cmax,cinc]. Got \"{cntlevel}\"")
            sys.exit(0)

    #-----------------------------------------------------------------------
    #
    # Lambert grid for HRRR
    #
    #-----------------------------------------------------------------------

    carr= ccrs.PlateCarree()

    if basmap == "lambert":
        ctrlat = 38.5
        ctrlon = -97.5    # -97.5  # 262.5
        stdlat1 = 38.5
        stdlat2 = 38.5

        nxhr = 1799
        nyhr = 1059
        dxhr = 3000.0
        dyhr = 3000.0

        xsize=(nxhr-1)*dxhr
        ysize=(nyhr-1)*dyhr

        x1hr = np.linspace(0.0,xsize,num=nxhr)
        y1hr = np.linspace(0.0,ysize,num=nyhr)

        x2hr, y2hr = np.meshgrid(x1hr,y1hr)

        xctr = (nxhr-1)/2*dxhr
        yctr = (nyhr-1)/2*dyhr

        proj_hrrr=ccrs.LambertConformal(central_longitude=ctrlon, central_latitude=ctrlat,
                     false_easting=xctr, false_northing= yctr, secant_latitudes=None,
                     standard_parallels=(stdlat1, stdlat2), globe=None)

    else:
        proj_hrrr = None

    #-----------------------------------------------------------------------
    #
    # Plot field
    #
    #-----------------------------------------------------------------------

    # Colormaps can be choosen using MatPlotLib's colormaps collection. A
    # reference of the colormaps can be found below.:
    #
    # - https://matplotlib.org/examples/color/colormaps_reference.html
    #
    # We can also alter the styles of the plots we produce if we desire:
    #
    # - https://matplotlib.org/gallery/style_sheets/style_sheets_reference.html
    #
    #
    general_colormap = cm.gist_ncar

    mycolors = ctables.colortables['NWSReflectivity']
    mycolors.insert(0,(1,1,1))
    ref_colormap = colors.ListedColormap(mycolors)
    style = 'ggplot'

    for l in levels:

        if varndim == 3:
            if l == "max":
                varplt = np.max(vardata,axis=0)
                outlvl = f"_{l}"
                outtlt = f"colum maximum {varname}{diffstr} ({varunits}) valid at {fcsttime}"
            else:
                varplt = vardata[l,:,:]
                outlvl = f"_K{l:02d}"
                outtlt = f"{varname}{diffstr} ({varunits}) valid at {fcsttime} on level {l:02d}"
        elif varndim == 2:
            varplt = vardata[:,:]
            outlvl = ""
            outtlt = f"{varname}{diffstr} ({varunits}) valid at {fcsttime}"
        else:
            print(f"Variable {varname} is in wrong shape: {varshapes}.")
            sys.exit(0)

        color_map, normc, cntlevels = get_var_contours(varname,varplt,(general_colormap,ref_colormap),cntlevel)

        figure = plt.figure(figsize = (10,8.5) )

        if basmap == "latlon":
            carr._threshold = carr._threshold/10.
            ax = plt.axes(projection=carr)
            ax.set_extent([-135.0,-60.0,20.0,55.0],crs=carr)
        else:
            ax = plt.axes(projection=proj_hrrr)
            ax.set_extent([-125.0,-70.0,22.0,52.0],crs=carr)

        #
        # Use tricontourf
        #
        #cntr = ax.tricontourf(glons, glats, varplt, levels=24, antialiased=True, cmap=color_map, transform=carr)
        #cntr = ax.tricontourf(glons, glats, varplt, cntlevels, antialiased=False, cmap=color_map, norm=normc, transform=carr)

        cntr = ax.contourf(glons, glats, varplt, cntlevels, antialiased=False, cmap=color_map, norm=normc, transform=carr )

        # https://matplotlib.org/api/colorbar_api.html
        #
        cax = figure.add_axes([ax.get_position().x1+0.01,ax.get_position().y0,0.02,ax.get_position().height])
        cbar = plt.colorbar(cntr, cax=cax)
        cbar.set_label(f'{varname} ({varunits})')

        ax.coastlines(resolution='50m')
        #ax.stock_img()
        #ax.add_feature(cfeature.OCEAN)
        #ax.add_feature(cfeature.LAND, edgecolor='black')
        #ax.add_feature(cfeature.LAKES, edgecolor='black',facecolor='white')
        #ax.add_feature(cfeature.RIVERS)
        ax.add_feature(cfeature.BORDERS)
        ax.add_feature(cfeature.STATES,linewidth=0.1)
        gl = ax.gridlines(draw_labels=True,linewidth=0.2, color='gray', alpha=0.7, linestyle='--')
        gl.xlocator = mticker.FixedLocator([-140,-120, -100, -80, -60])
        gl.ylocator = mticker.FixedLocator([10,20,30,40,50,60])
        gl.top_labels = False
        gl.left_labels = True  #default already
        gl.right_labels = False
        gl.bottom_labels = True

        # Create the title as you see fit
        ax.set_title(outtlt)
        plt.style.use(style) # Set the style that we choose above

        #
        if defaultoutfile:
            outfile = f"{varname}{diffstr}.{fcstfname}{outlvl}_{basmap}.png"

        figname = os.path.join(outdir,outfile)
        print(f"Saving figure to {figname} ...")
        figure.savefig(figname, format='png', dpi=300)
        plt.close(figure)

        #plt.show()
