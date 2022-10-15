#!/usr/bin/env python
#
# This module plots MPAS forecast 2D/3D fields on a horizontal slice
# using the MPAS unstructured cell latitude/longitude stored in the MPAS history file.
#
#-----------------------------------------------------------------------
#
# By Yunheng Wang (NOAA/NSSL, 2022.10.10)
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
from netCDF4 import Dataset

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

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#
# Main function defined to return correct sys.exit() calls
#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

if __name__ == "__main__":

    parser = argparse.ArgumentParser(description='Plot MPAS grid variables using Cartopy',
                                     epilog='''        ---- Yunheng Wang (2022-10-08).
                                            ''')
                                     #formatter_class=CustomFormatter)

    parser.add_argument('fcstfile',help='MPAS forecast file')
    parser.add_argument('varname', help='Name of variable to be plotted',type=str, default=None)

    parser.add_argument('-v','--verbose',   help='Verbose output',                 action="store_true", default=False)
    #parser.add_argument('-latlon'       ,   help='Base map latlon or lambert',action='store_true', default=True)
    parser.add_argument('--latlon',         help='Base map latlon',                action='store_true')
    parser.add_argument('--no-latlon',      help='Base map lambert',dest='latlon', action='store_false')
    parser.set_defaults(latlon=True)
    parser.add_argument('-d','--domain',    help='Name of the MPAS grid definition file', type=str, default=None)
    parser.add_argument('-g','--gridfile',  help='Name of the MPAS file that contains cell grid', type=str, default=None)
    parser.add_argument('-l','--levels' ,   help='Vertical levels to be plotted [l1,l2,l3,...]',  type=str, default=None)
    parser.add_argument('-o','--outfile',   help='Name of output image or output directory',      type=str, default=None)

    args = parser.parse_args()

    basmap = "latlon"
    if not args.latlon:
        basmap = "lambert"

    fcstfile = args.fcstfile
    varname  = args.varname
    if not os.path.lexists(fcstfile) and os.path.lexists(varname):  # if the two arguments are out-of-order
        fcstfile = varname
        varname  = args.fcstfile

    if os.path.lexists(fcstfile):

        with Dataset(fcstfile, 'r') as mesh:
            nCells   = mesh.dimensions["nCells"].size
            nlevels  = mesh.dimensions["nVertLevels"].size
            try:
                nslevels = mesh.dimensions["nSoilLevels"].size
            except:
                nslevels = 0

            if varname == "list":
                var2dlist = []
                var3dlist = []
                varODlist = []
                for var in mesh.variables.values():
                    vndim   = var.ndim
                    vshapes = var.shape

                    varstr = f"{var.name:24s}: {vndim}D {var.long_name} ({var.units})"
                    if vndim == 2 and vshapes[0] == 1 and vshapes[1] == nCells:
                        var2dlist.append(varstr)
                    elif vndim == 3 and vshapes[0] == 1 and vshapes[1] == nCells and (vshapes[2] == nlevels or vshapes[2] == nlevels):
                        var3dlist.append(varstr)
                    elif vndim == 0:
                        varstr = f"{var.name:20s}: (={var.getValue()}) {var.long_name} ({var.units})"
                        varODlist.append(varstr)
                    else:
                        varstr = f"{var.name:20s}: {vndim}D ({vshapes}) {var.long_name} ({var.units})"
                        varODlist.append(varstr)


                print("\n---- Other Variables ----")
                for varstr in sorted(varODlist):
                    print(varstr)

                print("\n---- 3D Variables ----")
                for varstr in sorted(var3dlist):
                    print(varstr)

                print("\n---- 2D Variables ----")
                for varstr in sorted(var2dlist):
                    print(varstr)

                sys.exit(0)
            elif varname not in mesh.variables.keys():
                # Check to see the variable is in the mesh
                print(f"This variable ({varname}) was not found in this mpas mesh!")
                sys.exit(-1)

            # Pull the variable out of the mesh. Now we can manipulate it any way we choose
            # do some 'post-processing' or other meteorological stuff
            variable = mesh.variables[varname]
            varunits = variable.getncattr('units')
            varndim  = variable.ndim
            varshapes = variable.shape
            vardata  = variable[:]

    else:
        print("ERROR: need a MPAS history/diag file.")
        sys.exit(0)

    fnamelist = os.path.basename(fcstfile).split('.')[2:-1]
    fcstfname = '.'.join(fnamelist)
    fcsttime  = ':'.join(fnamelist).replace('_',' ')

    if varndim == 2:
        levels=[0]
    elif varndim == 3:
        if varshapes[2] == nslevels:
            levels = range(nslevels)
        elif varshapes[2] == nlevels:
            levels = range(nlevels)
        else:
            print(f"The 3rd dimension size ({varshapes[2]}) is not in ({nlevels}, {nslevels}).")
            sys.exit(0)

        if args.levels is not None:
            pattern = re.compile("^([0-9]+)-([0-9]+)$")
            pmatched = pattern.match(args.levels)
            if pmatched:
                levels=range(int(pmatched[1]),int(pmatched[2]))
            elif args.levels in ["max",]:
                levels=["max",]
            else:
                levels = [int(item) for item in args.levels.split(',')]
    else:
        print(f"Do not supported {varndim} dimensions array.")
        sys.exit(0)

    if varshapes[0] != 1 or varshapes[1] != nCells:
        print(f"Do not supported variable shape ({varshapes}).")
        sys.exit(0)

    #
    # decode gridfile for latitudes/longitudes
    #
    gridfile = fcstfile
    if args.gridfile is not None:
        gridfile = args.gridfile

    with Dataset(gridfile, 'r') as grid:
        lats = grid.variables['latCell'][:]
        lons = grid.variables['lonCell'][:]

        glats = lats * (180 / np.pi)
        glons = ((lons * (180 / np.pi) )%360 + 540)%360 -180.

    #
    # decode gridfile for latitudes/longitudes
    #
    out_masked = False
    if args.domain is not None and os.path.lexists(args.domain):

        with open(args.domain, 'r') as csvfile:
            reader = csv.reader(csvfile)
            next(reader);next(reader);next(reader);
            lonlats=[]
            for row in reader:
                lonlats.append((float(row[1]),float(row[0])))
        out_masked = True
        lonlats.append(lonlats[0])
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

    times = [0]
    for t in times:
        for l in levels:

            if varndim == 3:
                if l == "max":
                    varplt = np.max(vardata,axis=2)[t,:]
                    outlvl = f"_{l}"
                    outtlt = f"colum maximum {varname} ({varunits}) valid at {fcsttime}"
                else:
                    varplt = vardata[t,:,l]
                    outlvl = f"_K{l:02d}"
                    outtlt = f"{varname} ({varunits}) valid at {fcsttime} and on level {l:02d}"
            elif varndim == 2:
                varplt = vardata[t,:]
                outlvl = ""
                outtlt = f"{varname} ({varunits}) valid at {fcsttime}"
            else:
                print(f"Variable {varname} is in wrong shape: {varshapes}.")
                sys.exit(0)

            color_map = general_colormap
            pmin = varplt.min()
            pmax = varplt.max()
            #print(pmin, pmax)
            if varname.startswith('refl'):    # Use reflectivity color map and range
                color_map = ref_colormap
                cmin = 0.0
                cmax = 5*pmax//5
                cntlevels = list(np.arange(cmin,cmax,5.0))
                normc = colors.Normalize(0.0,80.0)
            else:
                cmin, cmax, cexp = fnormalize(pmin,pmax)
                minc = np.floor(cmin)
                maxc = np.ceil(cmax)

                for n in range(16,7,-1):
                    #print(maxc, minc, n, (maxc-minc)%n)
                    if (maxc-minc)%n == 0:
                        break
                if n == 8: n = 16
                #print(n, minc, maxc, (maxc-minc)/n)
                minc = minc*10**cexp
                maxc = maxc*10**cexp
                cntlevels = list(np.linspace(minc,maxc,n+1))
                maxc = minc + 16* (maxc-minc)/n
                normc = colors.Normalize(minc,maxc)
                #print(cntlevels)
                #sys.exit(0)

            #print(cntlevels)

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
            cntr = ax.tricontourf(glons, glats, varplt, cntlevels, antialiased=False, cmap=color_map, norm=normc, transform=carr)

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

            #
            # mask out interpolation parts
            #
            if out_masked:
                polygon1 = Polygon( lonlats )
                ax.add_geometries([polygon1], crs=ccrs.Geodetic(), facecolor='w', edgecolor='none')

            # Create the title as you see fit
            ax.set_title(outtlt)
            plt.style.use(style) # Set the style that we choose above

            #
            if defaultoutfile:
                outfile = f"{varname}.{fcstfname}{outlvl}_{basmap}.png"

            figname = os.path.join(outdir,outfile)
            print(f"Saving figure to {figname} ...")
            figure.savefig(figname, format='png', dpi=600)
            plt.close(figure)

            #plt.show()
