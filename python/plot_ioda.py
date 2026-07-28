#!/usr/bin/env python
#
# This module plots JEDI reflectivity file
#
#-----------------------------------------------------------------------
#
# By Yunheng Wang (NOAA/NSSL, 2023.11.10)
#
#-----------------------------------------------------------------------

import os
import sys
import re
import math
import argparse

from collections import defaultdict

from datetime import datetime, timedelta, timezone

import numpy as np

import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
# """
# cm = Color Map. Within the matplotlib.cm module will contain access to a number
# of colormaps for a plot. A reference to colormaps can be found at:
#
#     - https://matplotlib.org/examples/color/colormaps_reference.html
# """
import matplotlib.cm as cm
import matplotlib.colors as mcolors
from metpy.plots import ctables

import cartopy.crs as ccrs
import cartopy.feature as cfeature

from netCDF4 import Dataset

from pyproj import Transformer
#from scipy.spatial import KDTree
from scipy.interpolate import griddata
from shapely.geometry.polygon import Polygon
import csv

import time as timeit
from itertools import islice
# Make an iterator that returns selected elements from the iterable

#""" By default matplotlib will try to open a display windows of the plot, even
#though sometimes we just want to save a plot. Somtimes this can cause the
#program to crash if the display can't open. The two commands below makes it so
#matplotlib doesn't try to open a window
#"""
import matplotlib
matplotlib.use('Agg')

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
        if isinstance(v, dict):
            if level is None or (level is not None and lvl < level):
                leaf_ns = make_namespace(v,lvl,level)
                ns.__dict__[k] = leaf_ns
            else:
                ns.__dict__[k] = v
        else:
            ns.__dict__[k] = v

    return ns

########################################################################

def dumpobj(obj, level=0, maxlevel=10):
    """ Print object members nicely"""

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

########################################################################

def fnormalize(fmin,fmax):
    min_e = int(math.floor(math.log10(abs(fmin)))) if fmin != 0 else 0
    max_e = int(math.floor(math.log10(abs(fmax)))) if fmax != 0 else 0
    fexp = min(min_e, max_e)-2
    min_m = fmin/10**fexp
    max_m = fmax/10**fexp

    return min_m, max_m, fexp

########################################################################

def get_var_contours(varname,var2d,cntlevels):
    """set contour specifications"""
    #
    # set color map to be used
    #

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

    # Use reflectivity color map and range
    if varname.startswith('refl'):
        mycolors = list(ctables.colortables['NWSReflectivity'])
        mycolors.insert(0,(1,1,1))
        color_map = mcolors.ListedColormap(mycolors)
    elif varname.startswith('error'):
        cmap_data = [#(255/255, 255/255, 255/255),    # White
                     (224/255, 224/255, 224/255),    # Light Gray   5
                     (128/255, 128/255, 128/255),    # Gray        10
                     ( 64/255,  64/255,  64/255),    # Dark Gray   15
                     (255/255,   0/255,   0/255),    # Red         20
                     (255/255,  96/255, 208/255),    # Pink        25
                     (160/255,  32/255, 255/255),    # Purple      30
                     ( 80/255, 208/255, 255/255),    # Light Blue  35
                     (  0/255,  32/255, 255/255),    # Blue        40
                     ( 96/255, 255/255, 128/255),    # Yellow-Green 45
                     (  0/255, 192/255,   0/255),    # Green        50
                     (255/255, 224/255,  32/255),    # Yellow
                     (255/255, 160/255,  16/255),    # Orange
                     (160/255, 128/255,  96/255),    # Brown
                     (255/255, 208/255, 160/255)]    # Pale Pink

        color_map = mcolors.ListedColormap(cmap_data, 'error')

    elif varname.startswith('rain') or varname.startswith('prec_'):
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
            normc = mcolors.Normalize(cmin,cmax)
            ticks_list = [lvl for lvl in np.arange(cmin,cmax+cinc,2*cinc)]
    else:
        ticks_list = None
        cmin = var2d.min()
        cmax = var2d.max()
        if varname.startswith('refl'):    # Use reflectivity color map and range
            cmin = 0.0
            cmax = 80.0
            cntlevels = list(np.arange(cmin, cmax + 5.0, 5.0))
            normc = mcolors.BoundaryNorm(cntlevels, color_map.N)
        elif varname.startswith('rain') or varname.startswith('prec_'):
            #cntlevels = [0.0,0.01,0.10,0.25,0.50,0.75,1.00,1.25,1.50,1.75,2.00,2.50,3,4,5,7,10,15,20]  # inch
            cntlevels = [0, 1, 2.5, 5, 7.5, 10, 15, 20, 30, 40, 50, 70, 100, 150, 200, 250, 300, 400, 500, 600, 750]  # mm
            normc = mcolors.BoundaryNorm(cntlevels, len(cntlevels))
            ticks_list = cntlevels
            cmin = cntlevels[0]
            cmax = cntlevels[-1]
        else:
            cmin, cmax, cexp = fnormalize(cmin,cmax)
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
            normc = mcolors.Normalize(minc, maxc)
            cmin = minc
            cmax = maxc

    return color_map, normc  #, cmin, cmax, ticks_list

########################################################################

def setup_hrrr_projection(carr):
    """Lambert conformal map projection for the HRRR domain"""

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

    #x2hr, y2hr = np.meshgrid(x1hr,y1hr)

    xctr = (nxhr-1)/2*dxhr
    yctr = (nyhr-1)/2*dyhr

    proj =ccrs.LambertConformal(central_longitude=ctrlon, central_latitude=ctrlat,
                 false_easting=xctr, false_northing= yctr,
                 standard_parallels=(stdlat1, stdlat2), globe=None)

    lonlat_sw = carr.transform_point(0.0,0.0,proj)

    grid_hrrr = {'proj'     : proj,
                 'xsize'    : xsize,
                 'ysize'    : ysize,
                 'ctrlat'   : ctrlat,
                 'ctrlon'   : ctrlon,
                 'xctr'     : xctr,
                 'yctr'     : yctr,
                 'x1d'      : x1hr,
                 'y1d'      : y1hr,
                 'lonlat_sw': lonlat_sw }

    return make_namespace(grid_hrrr)

########################################################################

def load_wofs_grid(filename):

    fileroot,filext = os.path.splitext(filename)

    if filext == ".pts":                       # custom.pts file
        with open(filename, 'r') as csvfile:
            reader = csv.reader(csvfile)
            next(reader);next(reader);next(reader);
            lonlats=[]
            for row in reader:
                lonlats.append((float(row[1]),float(row[0])))

        # Note that MPAS requires the order to be clockwise
        # Python polygon requires anti-clockwise
        lonlats.reverse()
        lonlats.append(lonlats[0])
        #print(lonlats)

        mpas_grid = {}

        wofs_type = "pts"

    elif filext == ".nc":                       # netcdf grid file

        r2d = 57.2957795             # radians to degrees

        with Dataset(filename,'r') as mesh:
            #xVertex = mesh.variables['xVertex'][:]
            #yVertex = mesh.variables['yVertex'][:]
            #zVertex = mesh.variables['zVertex'][:]

            #verticesOnCell = mesh.variables['verticesOnCell'][:,:]
            #nEdgesOnCell   = mesh.variables['nEdgesOnCell'][:]
            verticesOnEdge = mesh.variables['verticesOnEdge'][:,:]
            #lonCell = mesh.variables['lonCell'][:] * r2d
            #latCell = mesh.variables['latCell'][:] * r2d
            lonVertex = mesh.variables['lonVertex'][:] * r2d
            latVertex = mesh.variables['latVertex'][:] * r2d
            #lonEdge = mesh.variables['lonEdge'][:] * r2d
            #latEdge = mesh.variables['latEdge'][:] * r2d
            #hvar     = mesh.variables['areaCell'][:]
            nedges    = mesh.dimensions['nEdges'].size

        lonlats = [ (lon,lat) for lon,lat in zip(lonVertex,latVertex)]

        mpas_grid = {"nedges"         : nedges,
                     "verticesOnEdge" : verticesOnEdge,
                     "lonVertex"      : lonVertex,
                     "latVertex"      : latVertex,
                    }

        wofs_type = "grid"
    else:
        print("ERROR: need a MPAS grid file or custom pts file.")
        sys.exit(0)

    return wofs_type,lonlats,make_namespace(mpas_grid)

########################################################################

def attach_wofs_grid(wofs_gridtype,axo,carr,lonlats,skipedges,mpas_grid):
    ''' Plot the WoFS domain '''

    if wofs_gridtype == "pts":
        polygon1 = Polygon( lonlats )
        axo.add_geometries([polygon1], crs=ccrs.Geodetic(), facecolor='white',
                          edgecolor='navy', linewidth=1.5, alpha=0.2,zorder=1)

        #for lon,lat in lonlats:
        #    plt.text(lon, lat, '*', color='r', horizontalalignment='center',
        #            verticalalignment='center',transform=carr)

    elif wofs_gridtype == "grid":
        nedges = mpas_grid.nedges
        ecx = np.zeros((nedges,2),dtype=np.double)
        ecy = np.zeros((nedges,2),dtype=np.double)

        looprange=list(range(0,nedges,skipedges))

        ecy[:,0] = mpas_grid.latVertex[mpas_grid.verticesOnEdge[:,0]-1]
        ecx[:,0] = mpas_grid.lonVertex[mpas_grid.verticesOnEdge[:,0]-1]
        ecy[:,1] = mpas_grid.latVertex[mpas_grid.verticesOnEdge[:,1]-1]
        ecx[:,1] = mpas_grid.lonVertex[mpas_grid.verticesOnEdge[:,1]-1]

        for j in looprange:
            if abs(ecx[j,0] - ecx[j,1]) > 180.0:
              if ecx[j,0] > ecx[j,1]:
                 ecx[j,0] = ecx[j,0] - 360.0
              else:
                 ecx[j,1] = ecx[j,1] - 360.0

            plt.plot(ecx[j,:], ecy[j,:],
                    color='yellow', linewidth=0.1, marker='o', markersize=0.2,alpha=.4,
                    transform=carr) # Be explicit about which transform you want
    else:
        print(f"ERROR: unsupported plt_wofs = {wofs_gridtype}")
        return

########################################################################

def parse_args():
    """ Parse command line arguments
    """
    parser = argparse.ArgumentParser(description='Plot a DART obs_seq file',
                                     epilog="\n        ---- Yunheng Wang (2025-08-20)\n ",
                                     formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument('inputs', nargs='+',
                        help='Input file and optional ObsValue variable name. Existing path is used as the input file; non-file token is used as obsVar.')

    parser.add_argument('-v', '--verbose',
                        help='Enable verbose output.\n ',
                        action="store_true", default=False)

    parser.add_argument('-l', '--vertLevels',
                        help='Specify vertical levels to be plotted.',
                        type=str, default=None)

    parser.add_argument('--heights',
                        help='Specify comma-separated heights in meters to be plotted, e.g. max,500,1000,2000.',
                        type=str, default=None)

    parser.add_argument('--heightTolerance',
                        help='Set the height matching tolerance in meters for IODA point observations.',
                        type=float, default=1.0)

    parser.add_argument('--clearAirFile',
                        help='Specify a clear-air reflectivity file to overlay as white 0 dBZ points.',
                        type=str, default=None)

    parser.add_argument('--noZeroDbz',
                        help='Do not plot 0 dBZ reflectivity or clear-air overlay points.',
                        action="store_true", default=False)

    parser.add_argument('--markerSize',
                        help='Set the marker size for nonzero reflectivity scatter points.',
                        type=float, default=8.0)

    parser.add_argument('--marker',
                        help='Set the scatter marker style: dot or pixel.',
                        choices=['dot', 'pixel'], default='dot')

    parser.add_argument('--minDbz',
                        help='Do not plot nonzero reflectivity values below this dBZ threshold.',
                        type=float, default=None)

    parser.add_argument('-c', '--cntLevels',
                        help='Define contour levels as [cmin, cmax, cinc].',
                        type=str, default=None)

    parser.add_argument('-g', '--gridfile',
                        help='Specify a model file that provides grid data.',
                        type=str, default=None)

    parser.add_argument('-n', '--varname',
                        help='Specify variable to be plotted, either "value" or "error".',
                        type=str, default='value')

    parser.add_argument('-m', '--map',
                        help='Select a base map projection: latlon, stereo, or lambert.',
                        type=str, default='latlon')

    parser.add_argument('-range',
                        help='Define the map range in degrees as [lat1, lat2, lon1, lon2].\n ',
                        type=str, default=None)

    parser.add_argument('-o', '--outfile',
                        help='Specify the name of the output image file or an output directory.',
                        type=str, default=None)

    parser.add_argument('-r', '--resolution',
                        help='Set the resolution of the output image.',
                        type=int, default=100)


    args = parser.parse_args()

    parsed_args = {'varname': args.varname,
                   'obs_var': 'equivalentReflectivityFactor' }

    if args.map in ['latlon', 'lambert', 'stereo']:
        parsed_args['basmap'] = args.map
    else:
        print(f"ERROR: basemap must be one of ('latlon', 'lambert', 'stereo') Got \"{args.map}\"")
        sys.exit(0)

    if args.vertLevels is not None:
        rlist = [item for item in args.vertLevels.split(',')]
        parsed_args['t_level_type'] = int(rlist[0])
        parsed_args['t_level']      = float(rlist[1])
        parsed_args['t_level_tolr'] = float(rlist[2])
    else:
        parsed_args['t_level'] = 'ALL'

    parsed_args['height_levels'] = None
    parsed_args['height_tolerance'] = args.heightTolerance
    parsed_args['plot_zero_dbz'] = not args.noZeroDbz
    parsed_args['marker_size'] = args.markerSize
    parsed_args['marker'] = ',' if args.marker == 'pixel' else '.'
    parsed_args['min_dbz'] = args.minDbz
    if args.heights is not None:
        parsed_args['height_levels'] = []
        for item in args.heights.split(','):
            height_string = item.strip()
            if height_string.lower() == 'max':
                parsed_args['height_levels'].append(None)
            else:
                try:
                    parsed_args['height_levels'].append(float(height_string))
                except ValueError:
                    print(f"ERROR: --heights must be a comma-separated list of numbers or \"max\". Got \"{args.heights}\"")
                    sys.exit(0)

        if len(parsed_args['height_levels']) < 1:
            print(f"ERROR: --heights must include at least one height. Got \"{args.heights}\"")
            sys.exit(0)

    #-------------------------------------------------------------------
    # Set observation file name
    #-------------------------------------------------------------------
    obsfiles  = []
    obsvars   = []
    for input_arg in args.inputs:
        if os.path.lexists(input_arg):
            obsfiles.append(input_arg)
        else:
            obsvars.append(input_arg)

    if len(obsfiles) == 1:
        parsed_args['obsfile'] = obsfiles[0]
    else:
        print(f"file name must be specified exactly once. Got \"{obsfiles}\"")
        sys.exit(0)

    if len(obsvars) == 1:
        parsed_args['obs_var'] = obsvars[0]
    elif len(obsvars) > 1:
        print(f"obsVar can only be specified once. Got \"{obsvars}\"")
        sys.exit(0)

    parsed_args['ioda_file'] = False
    obs_filename = os.path.basename(parsed_args['obsfile'])
    if obs_filename.startswith('ioda_') or obs_filename.startswith('jdiag_'):
        parsed_args['ioda_file'] = True

    #-------------------------------------------------------------------
    # Map releated parameters
    #-------------------------------------------------------------------
    parsed_args['ranges'] = None     #[-135.0,-60.0,20.0,55.0]
    if args.range == 'hrrr':
        if args.latlon:
            parsed_args['ranges'] = [-135.0,-60.0,20.0,55.0]
        else:
            parsed_args['ranges'] = [-125.0,-70.0,22.0,52.0]
    elif args.range is not None:
        rlist = [float(item) for item in args.range.split(',')]
        if len(rlist) < 4:
            print("-range expects 4 degrees as [lat1,lat2,lon1,lon2].")
            sys.exit(0)
        rlist = [float(item) for item in args.range.split(',')]

        lats=rlist[0:2]
        lons=rlist[2:4]
        parsed_args['ranges'] = [min(lons),max(lons),min(lats),max(lats)]

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

    parsed_args['defaultoutfile'] = defaultoutfile
    parsed_args['outdir']         = outdir
    parsed_args['outfile']        = outfile
    parsed_args['outresolution']  = args.resolution

    #
    # decode contour specifications
    #
    parsed_args['cntlevel'] = None
    if args.cntLevels is not None:
        parsed_args['cntlevel'] = [float(item) for item in args.cntLevels.split(',')]
        if len(parsed_args['cntlevel']) != 3:
            print(f"Option -c must be [cmin,cmax,cinc]. Got \"{args.cntLevels}\"")
            sys.exit(0)

    parsed_args['plt_wofs'] = args.gridfile
    if args.gridfile is not None:
        if not os.path.lexists(args.gridfile):
            print(f"ERROR: The grid file {args.gridfile} not exists.")
            sys.exit(1)

    parsed_args['clear_air_file'] = args.clearAirFile
    if args.clearAirFile is not None:
        if not os.path.lexists(args.clearAirFile):
            print(f"ERROR: The clear-air file {args.clearAirFile} not exists.")
            sys.exit(1)

    return args, make_namespace(parsed_args)

########################################################################

def load_ioda_ref(args,require_error=True,obsvar='equivalentReflectivityFactor'):

    var_obj = {}

    if os.path.lexists(args.obsfile):

        with Dataset(args.obsfile, 'r') as fh:
            meta_group = fh.groups['MetaData']
            obs_group  = fh.groups['ObsValue']
            if obsvar not in obs_group.variables:
                print(f"ERROR: ObsValue variable \"{obsvar}\" not found in {args.obsfile}.")
                print(f"       Available ObsValue variables: {list(obs_group.variables.keys())}")
                sys.exit(1)
            varobs  = obs_group.variables[obsvar][:]
            if require_error:
                err_group = fh.groups['ObsError']
                if obsvar not in err_group.variables:
                    print(f"ERROR: ObsError variable \"{obsvar}\" not found in {args.obsfile}.")
                    print(f"       Available ObsError variables: {list(err_group.variables.keys())}")
                    sys.exit(1)
                varerr = err_group.variables[obsvar][:]
            elif 'ObsError' in fh.groups and obsvar in fh.groups['ObsError'].variables:
                err_group = fh.groups['ObsError']
                varerr = err_group.variables[obsvar][:]
            else:
                varerr = np.zeros_like(varobs)
            varlat  = meta_group.variables['latitude'][:]
            varlon  = meta_group.variables['longitude'][:]
            varhgt  = meta_group.variables['height'][:]
            vartime = meta_group.variables['dateTime'][:]

        nobs  = varobs.size

    else:
        print(f"ERROR: file {args.obsfile} not found")
        sys.exit(1)

    var_obj['nobs']     = nobs
    var_obj['varlat']   = varlat
    var_obj['varlon']   = varlon
    var_obj['varhgt']   = varhgt
    var_obj['varobs']   = varobs
    var_obj['varerr']   = varerr
    var_obj['vartime']  = vartime
    var_obj['obsvar']   = obsvar

    return make_namespace(var_obj,level=1)

########################################################################

def load_gridded_ref(args):

    var_obj = {}

    if os.path.lexists(args.obsfile):

        with Dataset(args.obsfile, 'r') as fh:
            varobs  = fh.variables['reflectivity'][:,:,:]
            varlat  = fh.variables['latitude'][:]
            varlon  = fh.variables['longitude'][:]
            varhgt  = fh.variables['height'][:]

        nobs  = varobs.size

    else:
        print(f"ERROR: file {args.obsfile} not found")
        sys.exit(1)

    var_obj['nobs']     = nobs
    var_obj['varlat']   = varlat
    var_obj['varlon']   = varlon
    var_obj['varhgt']   = varhgt
    var_obj['varobs']   = varobs
    var_obj['vartime']  = None

    return make_namespace(var_obj,level=1)

########################################################################

def height_label(height):
    if float(height).is_integer():
        return f"{int(height)}m"
    return f"{height:g}m"

########################################################################

def is_reflectivity_var(obsvar):
    return obsvar.startswith('equivalentReflectivityFactor')

########################################################################

def retrieve_plotvar(varargs,varobj,target_height=None):
    """ Select observation index based on command line arguments"""

    varmeta = {'level_label': "Max"}
    obsvar = getattr(varobj, 'obsvar', getattr(varargs, 'obs_var', 'equivalentReflectivityFactor'))
    if varargs.varname == "value":
        varmeta['varlabel'] = "Reflectivity" if is_reflectivity_var(obsvar) else obsvar
    else:
        varmeta['varlabel'] = "ObsError" if is_reflectivity_var(obsvar) else f"{obsvar} ObsError"

    varshape = varobj.varobs.shape
    if len(varshape) == 3:
        glons, glats = np.meshgrid(varobj.varlon, varobj.varlat)
        if cmd_args.verbose: print(f"shape of glons: {glons.shape}, shape of glats: {glats.shape}.")

        if target_height is None:
            vardat = np.max(varobj.varobs, axis=0)
        else:
            heights = np.asarray(varobj.varhgt, dtype=float)
            level_index = int(np.argmin(np.abs(heights - target_height)))
            vardat = varobj.varobs[level_index,:,:]
            varmeta['level_label'] = height_label(heights[level_index])

        if cmd_args.verbose: print(f"shape of varobs: {varobj.varobs.shape}, shape of vardat: {vardat.shape}.")
        varmeta['nobs'] = vardat.size
    else:
        horizontal_groups = defaultdict(list)
        if target_height is None:
            height_mask = np.ones(varobj.varobs.shape, dtype=bool)
        else:
            height_mask = np.abs(np.asarray(varobj.varhgt, dtype=float) - target_height) <= varargs.height_tolerance
            varmeta['level_label'] = height_label(target_height)

        if varargs.varname == "value":
            for x, y, val in zip(varobj.varlon[height_mask], varobj.varlat[height_mask], varobj.varobs[height_mask]):
                horizontal_groups[(x,y)].append(val)
        elif varargs.varname == "error":
            for x, y, val in zip(varobj.varlon[height_mask], varobj.varlat[height_mask], varobj.varerr[height_mask]):
                horizontal_groups[(x,y)].append(val)

        ldat   = []
        llons  = []
        llats  = []
        for key, data_list in horizontal_groups.items():
            if varargs.varname == "value":
                ldat.append(np.max(data_list))
            else:
                ldat.append(data_list[0])
            llons.append(key[0])
            llats.append(key[1])

        glons = np.array(llons)
        glats = np.array(llats)
        vardat = np.array(ldat)
        varmeta['nobs'] = int(np.count_nonzero(height_mask))

    if hasattr(varobj, 'vartime') and varobj.vartime is not None:
        varmeta['time']  = datetime.fromtimestamp(varobj.vartime[0]).strftime('%Y%m%d_%H%M')
    else:
        varmeta['time'] = "notime"

    return make_namespace(varmeta), glons,glats,vardat

########################################################################

def read_modgrid(filename):
    """ Read model grid file, Used only when observation needs to be interpolated
        to the model grid. Since we plot observation scatter directly, it will
        be useless.
    """

    with Dataset(filename, 'r') as fh:
        latCell  = fh.variables['CLAT'][0,:,:]
        lonCell  = fh.variables['CLONG'][0,:,:]

        cenlat = fh.getncattr('CEN_LAT')
        cenlon = fh.getncattr('CEN_LON')
        trulats = [fh.getncattr('TRUELAT1'),fh.getncattr('TRUELAT2')]

    ny, nx = latCell.shape

    # Reshape arrays to flatten the x/y dimensions to look like MPAS

    latCell  = latCell.flatten()
    lonCell  = lonCell.flatten()

    # make sure that lons are between 0 and 360 degress

    lonCell = np.where( lonCell < 0.0,   lonCell+360., lonCell)
    lonCell = np.where( lonCell > 360.0, lonCell-360., lonCell)

    # map projection for converting lat,lon to meters

    proj_daymet = f"+proj=lcc +lat_0={cenlat} +lon_0={cenlon} +lat_1={trulats[0]} +lat_2={trulats[1]} +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs"

    model_obj = {'lonCell':     lonCell,
                 'latCell':     latCell,
                 'nx'     :      nx,
                 'ny'     :      ny,
                 'mapping_transform' : Transformer.from_crs("EPSG:4326", proj_daymet, always_xy=True)
                 }

    return model_obj

########################################################################

def interpolation2D(obs_obj,mod_obj):
    """ Interpolate observation to model grid using KDTree or griddata directly.
        Used only when observation needs to be interpolated
        to the model grid. Since we plot observation scatter directly, it will
        be useless.
    """
    #-------------------------------------------------------------------------------
    # remap radar coordinates

    #print(type(obs_obj['lon']),obs_obj['lon'].shape)
    x,y = mod_obj['mapping_transform'].transform(obs_obj['lon'],obs_obj['lat'])
    #print(x.shape, y.shape)

    obs_obj['xy'] = np.asarray([x, y]).transpose()
    #print(obs_obj['xy'].shape)
    #print(obs_obj['xyz'].shape)

    # remap model coodinates

    xCell2D, yCell2D = mod_obj['mapping_transform'].transform(mod_obj['lonCell'], mod_obj['latCell'])

    print('Dimensions of flattened coordinate arrays (lat,lon):  ', xCell2D.shape, yCell2D.shape)

    # #-------------------------------------------------------------------------------

    # #time0 = timeit.time()

    # mod_kdtree = KDTree(np.stack([xCell2D, yCell2D],1))

    # #print("\n Elapsed time create KDTree table is:  %f seconds" % (timeit.time() - time0))

    # ## now serialize it and write it out - this section of the code could be precomputed.
    # ##
    # ##time0 = timeit.time()
    # ##
    # ##with open('wofs_wrf_grid_kdtree.pkl', 'wb') as handle:
    # ##    pickle.dump(mpas_kdtree, handle)
    # ##
    # ##print(" Elapsed time to write out KDTree table is:  %f seconds" % (timeit.time() - time0))

    # # Now use the kdtree to find nearest points in the domain from the list of reflectivity observations.

    # #time0 = timeit.time()

    # dist, points = mod_kdtree.query(obs_obj['xy'],1)

    # #print("\n Elapsed time for kdtree query for %d radar observations is:  %f seconds" % (obs_obj['xyz'].shape[0],timeit.time() - time0))

    # mod_val = np.ones(xCell2D.shape)*-50.

    # for n in range(len(obs_obj['value'])):
    #     mod_val[points[n]] = obs_obj['value'][n]

    # mod_obs = np.ma.masked_where(mod_val <= -50, mod_val)

    # return xCell2D, yCell2D, mod_obs

    # ##-------------------------------------------------------------------------------

    ny = mod_obj['ny']
    nx = mod_obj['nx']

    grid_x = xCell2D.reshape(ny,nx)
    grid_y = yCell2D.reshape(ny,nx)

    grid_z0 = griddata(obs_obj['xy'], obs_obj['value'], (grid_x, grid_y), method='nearest')
    #grid_z1 = griddata(obs_obj['xy'], obs_obj['value'], (grid_x, grid_y), method='linear')
    #grid_z2 = griddata(obs_obj['xy'], obs_obj['value'], (grid_x, grid_y), method='cubic')

    return grid_z0

########################################################################

def make_plot(wargs,wobj,target_height=None,clear_air_obj=None):
    """ wargs: Decoded working arguments
        wobj:  Working object
    """

    global QCValMeta

    #-----------------------------------------------------------------------
    #
    # Set plot ranges
    #
    #-----------------------------------------------------------------------

    plot_meta, glons,glats,vardata = retrieve_plotvar(wargs,wobj,target_height)

    if vardata.size < 1:
        print(f"WARNING: No observations found for {plot_meta.level_label}; skipping plot.")
        return

    if wargs.ranges is None:
        if wargs.plt_wofs is not None:
            wofs_gridtype,lonlats,mpas_edges = load_wofs_grid(wargs.plt_wofs)

            lats = [ l[1] for l in lonlats]
            lons = [ l[0] for l in lonlats]

            ranges = [min(lons)-1.0,max(lons)+1.0,min(lats)-1.0,max(lats)+1.0]
        else:
            ranges = [glons.min()-2.0,glons.max()+2.0,glats.min()-2.0,glats.max()+2.0]
    else:
        ranges = wargs.ranges

    carr= ccrs.PlateCarree()

    #-----------------------------------------------------------------------
    #
    # Plot field
    #
    #-----------------------------------------------------------------------

    #style = 'ggplot'

    figure = plt.figure(figsize = (12,12) )

    if wargs.basmap == "latlon":
        #carr._threshold = carr._threshold/10.
        ax = plt.axes(projection=carr)

        y_position = 0.76
        ax.set_extent(ranges,crs=carr)
    elif wargs.basmap == "stereo":
        earthRadius = 6371229.0
        cenLat = (ranges[3] + ranges[2])/2.0
        cenLon = (ranges[1] + ranges[0])/2.0
        extentY = math.radians(ranges[3] - ranges[2]) * earthRadius
        extentX = math.radians(ranges[1] - ranges[0]) * math.cos(math.radians(cenLat)) * earthRadius
        #print(f"    extent = {extentX/1000.:8.2f} km X {extentY/1000.:8.2f} km")

        scaling = 0.5
        proj = ccrs.Stereographic(cenLat, cenLon)
        ax = plt.axes(projection=proj)
        ax.set_extent([-scaling * extentX, scaling * extentX, -scaling * extentY, scaling * extentY], crs=proj)

        y_position = 0.71
    else:
        proj_hrrr = setup_hrrr_projection(carr).proj
        ax = plt.axes(projection=proj_hrrr)

        y_position = 0.80
        ax.set_extent(ranges,crs=carr)

    ax.coastlines(resolution='50m')
    #ax.stock_img()
    #ax.add_feature(cfeature.OCEAN)
    #ax.add_feature(cfeature.LAND, edgecolor='black')
    #ax.add_feature(cfeature.LAKES, edgecolor='black',facecolor='white')
    #ax.add_feature(cfeature.RIVERS)
    ax.add_feature(cfeature.BORDERS)
    ax.add_feature(cfeature.STATES,linewidth=0.1)
    #if wargs.basmap == "latlon":
    lonrange=list(range(-140,-50,5))
    latrange=list(range(10,60,5))
    gl = ax.gridlines(draw_labels=True,linewidth=0.2, color='gray', alpha=0.7, linestyle='--')
    gl.xlocator = mticker.FixedLocator(lonrange)
    gl.ylocator = mticker.FixedLocator(latrange)
    gl.top_labels = False
    gl.left_labels = True       #default already
    gl.right_labels = False
    gl.bottom_labels = True
    #gl.ylabel_style = {'rotation': 45}

    # Create the title as you see fit
    plt.title(f'{plot_meta.varlabel} for "{plot_meta.level_label}"', fontsize=18)
    #plt.style.use(style) # Set the style that we choose above

    #-------------------------------------------------------------------
    # Plot the WoFS domain
    #-------------------------------------------------------------------
    if wargs.plt_wofs is not None:
        attach_wofs_grid(wofs_gridtype, ax, carr,lonlats, 4, mpas_edges)

    #-------------------------------------------------------------------
    # Plot the field selected
    #-------------------------------------------------------------------

    # Color      Description
    # 'r'        Red               # 'g'        Green
    # 'b'        Blue              # 'c'        Cyan
    # 'm'        Magenta           # 'y'        Yellow
    # 'k'        Black             # 'w'        White

    # Marker     Description
    # 'o'        Circle            # '*'        Star
    # '.'        Point             # ','        Pixel
    # 'x'        X                 # 'X'        X (filled)
    # '+'        Plus              # 'P'        Plus (filled)
    # 's'        Square            # 'D'        Diamond
    # 'd'        Diamond (thin)    # 'p'        Pentagon
    # 'H'        Hexagon           # 'h'        Hexagon
    # 'v'        Triangle Down     # '^'        Triangle Up
    # '<'        Triangle Left     # '>'        Triangle Right
    # '1'        Tri Down          # '2'        Tri Up
    # '3'        Tri Left          # '4'        Tri Right
    # '|'        Vline             # '_'        Hline

    alphaval = 1.0
    varname = "error"
    is_refl = is_reflectivity_var(getattr(wobj, 'obsvar', getattr(wargs, 'obs_var', 'equivalentReflectivityFactor')))
    if wargs.varname == "value":
        varname = 'refl' if is_refl else wobj.obsvar

    color_map, normc = get_var_contours(varname,vardata,wargs.cntlevel)
    #cntlevels = list(np.linspace(cmin,cmax,9))

    clear_air_lons_list = []
    clear_air_lats_list = []
    if is_refl and wargs.plot_zero_dbz and clear_air_obj is not None:
        _, clear_air_lons, clear_air_lats, clear_air_data = retrieve_plotvar(wargs,clear_air_obj,target_height)
        if clear_air_data.size > 0:
            clear_air_lons_list.append(np.asarray(clear_air_lons, dtype=float))
            clear_air_lats_list.append(np.asarray(clear_air_lats, dtype=float))

    if is_refl:
        vardata_np = np.asarray(vardata, dtype=float)
        glons_np   = np.asarray(glons,   dtype=float)
        glats_np   = np.asarray(glats,   dtype=float)
        mask_clear  = (vardata_np == 0.0)
        mask_refl   = ~mask_clear
        if wargs.min_dbz is not None:
            mask_refl = mask_refl & (vardata_np >= wargs.min_dbz)
        if wargs.plot_zero_dbz and mask_clear.sum() > 0:
            clear_air_lons_list.append(glons_np[mask_clear])
            clear_air_lats_list.append(glats_np[mask_clear])
        if wargs.plot_zero_dbz and len(clear_air_lons_list) > 0:
            clear_air_lons = np.concatenate(clear_air_lons_list)
            clear_air_lats = np.concatenate(clear_air_lats_list)
            ax.scatter(clear_air_lons, clear_air_lats, marker=wargs.marker, color='0.6',
                       edgecolors='0.6', linewidths=0.1, alpha=alphaval, s=8.0,
                       zorder=2, transform=carr)
        cntr = ax.scatter(glons_np[mask_refl], glats_np[mask_refl], marker=wargs.marker, c=vardata_np[mask_refl],
                          alpha=alphaval, s=wargs.marker_size, cmap=color_map, norm=normc, zorder=3, transform=carr)
    else:
        cntr = ax.scatter(glons,glats,marker=wargs.marker, c=vardata, alpha=alphaval, s=wargs.marker_size, cmap=color_map, norm=normc, transform=carr)

    obs_string=f'Number of observations: {plot_meta.nobs}, min = {vardata.min()}, max = {vardata.max()}'
    plt.text(0.15,y_position, obs_string, color='black', horizontalalignment='left', verticalalignment='center',fontsize=14,transform=plt.gcf().transFigure)

    #mod_obj = read_modgrid(cargs.grid)
    #mod_obs = interpolation2D({'lon': glons, 'lat': glats, 'value': vardata}, mod_obj)

    #ny = mod_obj['ny']
    #nx = mod_obj['nx']
    ##cntr = ax.contourf(mod_obj['lonCell'].reshape(ny,nx), mod_obj['latCell'].reshape(ny,nx), mod_obs.reshape(ny,nx),    cntlevels, cmap=color_map, norm=normc, transform=carr)
    #cntr = ax.contourf(mod_obj['lonCell'].reshape(ny,nx), mod_obj['latCell'].reshape(ny,nx), mod_obs, cntlevels, cmap=color_map, norm=normc, transform=carr)
    ##cntr = ax.contourf(mod_x.reshape(ny,nx), mod_y.reshape(ny,nx), mod_obs.reshape(ny,nx), cntlevels, cmap=color_map, norm=normc, transform=proj_hrrr)

    ##cntr = ax.tricontourf(glons, glats, vardata, cntlevels, antialiased=False, cmap=color_map, norm=normc, transform=carr)

    # https://matplotlib.org/api/colorbar_api.html
    #
    cax = figure.add_axes([ax.get_position().x1+0.01,ax.get_position().y0,0.02,ax.get_position().height])
    cbar = plt.colorbar(cntr, cax=cax)
    cbar.set_label(plot_meta.varlabel)

    #-------------------------------------------------------------------
    # Write out the image file
    #-------------------------------------------------------------------
    if wargs.defaultoutfile:
        outpng = f"{plot_meta.varlabel}_{plot_meta.time}_{plot_meta.level_label}_{wargs.basmap}.png"
    else:
        root,ext=os.path.splitext(wargs.outfile)
        if ext != ".png":
            outpng = f"{wargs.outfile}_{plot_meta.level_label}.png"
        elif wargs.height_levels is not None and len(wargs.height_levels) > 1:
            outpng = f"{root}_{plot_meta.level_label}.png"
        else:
            outpng = wargs.outfile

    figname = os.path.join(wargs.outdir,outpng)
    print(f"Saving figure to {figname} ...")
    figure.savefig(figname, format='png', dpi=wargs.outresolution)
    plt.close(figure)

    #plt.show()

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#
# Main function defined to return correct sys.exit() calls
#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

if __name__ == "__main__":

    time0 = timeit.time()

    cmd_args, args = parse_args()

    if cmd_args.verbose: print("\n Elapsed time of parse_args is:  %f seconds" % (timeit.time() - time0))

    #
    # Load variable
    #
    time1 = timeit.time()

    #obs_obj = load_variables(args)
    if args.ioda_file:
        obs_obj = load_ioda_ref(args,require_error=(args.varname == "error"),obsvar=args.obs_var)
    else:
        obs_obj = load_gridded_ref(args)

    clear_air_obj = None
    if args.clear_air_file is not None:
        clear_air_args = argparse.Namespace(obsfile=args.clear_air_file)
        clear_air_filename = os.path.basename(args.clear_air_file)
        if clear_air_filename.startswith('ioda_') or clear_air_filename.startswith('jdiag_'):
            clear_air_obj = load_ioda_ref(clear_air_args,require_error=False,obsvar='equivalentReflectivityFactor_clear')
        else:
            clear_air_obj = load_gridded_ref(clear_air_args)

    if cmd_args.verbose: print("\n Elapsed time of load_variables is:  %f seconds" % (timeit.time() - time1))

    time3 = timeit.time()

    print("")
    if args.height_levels is None:
        make_plot(args, obs_obj, clear_air_obj=clear_air_obj)
    else:
        for target_height in args.height_levels:
            make_plot(args, obs_obj, target_height, clear_air_obj)

    if cmd_args.verbose: print("\n Elapsed time of make_plot is:  %f seconds" % (timeit.time() - time3))
