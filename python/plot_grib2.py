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
import matplotlib.colors as mcolors
from metpy.plots import ctables

#import scipy.interpolate as interpolate
from shapely.geometry.polygon import Polygon


import cartopy.crs as ccrs
import cartopy.feature as cfeature

import csv
import xarray as xr

#import strmrpt

########################################################################

def fnormalize(fmin,fmax):
    min_e = int(math.floor(math.log10(abs(fmin)))) if fmin != 0 else 0
    max_e = int(math.floor(math.log10(abs(fmax)))) if fmax != 0 else 0
    fexp = min(min_e, max_e)-2
    min_m = fmin/10**fexp
    max_m = fmax/10**fexp

    return min_m, max_m, fexp

def get_var_contours(varname,var2d,cntlevels):
    '''set contour specifications'''

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

    #
    # set color map to be used
    #

    if varname.startswith('refl'):
        # Use reflectivity color map and range
        mycolors = ctables.colortables['NWSReflectivity']
        mycolors.insert(0,(1,1,1))
        color_map = mcolors.ListedColormap(mycolors)
    elif varname.startswith('tp'):
        #clevs = [0, 1, 2.5, 5, 7.5, 10, 15, 20, 30, 40,
        #         50, 70, 100, 150, 200, 250, 300, 400, 500, 600, 750]
        # In future MetPy
        # norm, cmap = ctables.registry.get_with_boundaries('precipitation', clevs)
        cmap_data = [(1.0, 1.0, 1.0),
                     (0.3137255012989044, 0.8156862854957581, 0.8156862854957581),
                     (0.0, 1.0, 1.0),
                     (0.0, 0.8784313797950745, 0.501960813999176),
                     (0.0, 0.7529411911964417, 0.0),
                     (0.501960813999176, 0.8784313797950745, 0.0),
                     (1.0, 1.0, 0.0),
                     (1.0, 0.6274510025978088, 0.0),
                     (1.0, 0.0, 0.0),
                     (1.0, 0.125490203499794, 0.501960813999176),
                     (0.9411764740943909, 0.250980406999588, 1.0),
                     (0.501960813999176, 0.125490203499794, 1.0),
                     (0.250980406999588, 0.250980406999588, 1.0),
                     (0.125490203499794, 0.125490203499794, 0.501960813999176),
                     (0.125490203499794, 0.125490203499794, 0.125490203499794),
                     (0.501960813999176, 0.501960813999176, 0.501960813999176),
                     (0.8784313797950745, 0.8784313797950745, 0.8784313797950745),
                     (0.9333333373069763, 0.8313725590705872, 0.7372549176216125),
                     (0.8549019694328308, 0.6509804129600525, 0.47058823704719543),
                     (0.6274510025978088, 0.42352941632270813, 0.23529411852359772),
                     (0.4000000059604645, 0.20000000298023224, 0.0)]

        color_map = mcolors.ListedColormap(cmap_data, 'precipitation')

    else:
        color_map = cm.gist_ncar

    #
    # set contour levels
    #
    if cntlevels is not None:
        if len(cntlevels) > 3:
            cmin = cntlevels[0]
            cmax = cntlevels[-1]
            normc = mcolors.BoundaryNorm(cntlevels, len(cntlevels))
            ticks_list = cntlevels[0::2]
        else:
            cmin,cmax,cinc = cntlevels
            cntlevels = np.arange(cmin,cmax+0.01*cinc,cinc)
            normc = mcolors.Normalize(cmin,cmax)
            ticks_list = [lvl for lvl in np.arange(cmin,cmax+cinc,2*cinc)]
    else:
        ticks_list = None
        pmin = var2d.min()
        pmax = var2d.max()
        if varname.startswith('refl'):    # Use reflectivity color map and range
            cmin = 0.0
            cmax = 5*pmax//5
            cntlevels = list(np.arange(cmin,cmax,5.0))
            normc = mcolors.Normalize(0.0,80.0)
        elif varname.startswith('tp'):    # Use precipitation color map and range
            #cntlevels = [0.0,0.01,0.10,0.25,0.50,0.75,1.00,1.25,1.50,1.75,2.00,2.50,3,4,5,7,10,15,20]  # inch
            cntlevels = [0, 1, 2.5, 5, 7.5, 10, 15, 20, 30, 40, 50, 70, 100, 150, 200, 250, 300, 400, 500, 600, 750] # mm
            normc = mcolors.BoundaryNorm(cntlevels, len(cntlevels))
            ticks_list = cntlevels
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
            normc = mcolors.Normalize(minc,maxc)

    #print(cntlevels)

    return color_map, normc, cntlevels, ticks_list

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
    defaultoutfile = False
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
        #if len(cntlevel) != 3:
        #    print(f"Option -c must be [cmin,cmax,cinc]. Got \"{cntlevel}\"")
        #    sys.exit(0)

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

        color_map, normc, cntlevels, ticks_list = get_var_contours(varname,varplt,cntlevel)

        figure = plt.figure(figsize = (12,12) )

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
        cbar = plt.colorbar(cntr, cax=cax, ticks=ticks_list)
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
        figure.savefig(figname, format='png', dpi=100)
        plt.close(figure)

        #plt.show()
