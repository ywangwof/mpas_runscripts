#!/usr/bin/env python
#
# This module plots DART output obs_seq.final in netCDF format
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
        mycolors = ctables.colortables['NWSReflectivity']
        mycolors.insert(0,(1,1,1))
        color_map = mcolors.ListedColormap(mycolors)
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
            cntlevels = list(np.arange(cmin,cmax,5.0))
            normc = mcolors.Normalize(cmin,cmax)
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
    parser = argparse.ArgumentParser(description='Plot DART obs_seq.fial in netCDF format',
                                     epilog="""        ---- Yunheng Wang (2023-07-24).
                                            """)
                                     #formatter_class=CustomFormatter)

    parser.add_argument('obsfiles',help='DART obs_seq.fial in netCDF format')
    parser.add_argument('obstypes',help='Interger number that denotes observation type or a list of "," seperated numbers, or None to plot all observation in this file',
                        type=str,nargs='?',default=None)

    parser.add_argument('-v','--verbose',   help='Verbose output',                                        action="store_true", default=False)
    parser.add_argument('-p','--parms',     help='Specify variable copy and quality, [copy,qc_flag] or [copy] only', type=str, default=None)
    parser.add_argument('-l','--vertLevels',help='Vertical levels to be plotted [level,value,tolerance]',            type=str, default=None)
    parser.add_argument('-e','--filter_by_obs_error',help='Select observations by minimum observation error',      type=float, default=None)
    parser.add_argument('-s','--filter_by_rms',      help='Select observations by minimum observation rms',        type=float, default=None)
    parser.add_argument('-c','--cntLevels', help='Contour levels [cmin,cmax,cinc]',                                type=str,   default=None)
    parser.add_argument('--scatter'      ,  help='Scatter plot [mean,spread] of assimilated observations',         type=str,   default=None)
    parser.add_argument('--fill'         ,  help='Value to fill masked values, apply to the scatter plot only',    type=float, default=None)
    parser.add_argument('-latlon'        ,  help='Base map latlon or lambert',                             action='store_true',default=False)
    parser.add_argument('-range'         ,  help='Map range in degrees [lat1,lon1,lat2,lon2]',                     type=str,   default=None)
    parser.add_argument('-g','--gridfile',  help='Model file that provide grids',                                  type=str,   default=None)
    parser.add_argument('-o','--outfile' ,  help='Name of the output image file or an output directory',           type=str,   default=None)
    parser.add_argument('-r','--resolution',help='Resolution of the output image',                                 type=int,   default=100)

    args = parser.parse_args()

    parsed_args = {}
    parsed_args['basmap'] = "lambert"
    if args.latlon:
        parsed_args['basmap'] = "latlon"

    if args.vertLevels is not None:
        rlist = [item for item in args.vertLevels.split(',')]
        parsed_args['t_level_type'] = rlist[0]
        parsed_args['t_level']      = float(rlist[1])
        parsed_args['t_level_tolr'] = float(rlist[2])
    else:
        parsed_args['t_level'] = 'ALL'

    parsed_args['t_copy'] = None
    parsed_args['t_qc']   = 'ALL'
    if args.parms is not None:
        rlist = [item for item in args.parms.split(',')]
        parsed_args['t_copy'] = rlist[0]
        if len(rlist) > 1:
            parsed_args['t_qc'] = rlist[1]

    #-------------------------------------------------------------------
    # Set observation file name
    #-------------------------------------------------------------------
    obsfiles  = []
    types     = []
    obsfile = args.obsfiles
    if  os.path.lexists(obsfile):
        obsfiles.append(obsfile)
    else:
        types.append(obsfile)

    if args.obstypes is not None:
        if os.path.lexists(args.obstypes):  # if the two arguments are out-of-order
            obsfiles.append(args.obstypes)
        else:
            types.append(args.obstypes)

    if len(obsfiles) == 1:
        parsed_args['obsfile'] = obsfiles[0]
    else:
        print(f"file name can only be one. Got \"{obsfiles}\"")
        sys.exit(0)

    parsed_args['ncfmt'] = False
    if parsed_args['obsfile'].endswith('.nc'):
        parsed_args['ncfmt'] = True

    #
    # Set observation type
    #
    if len(types) == 0:
        type = None
    elif len(types) == 1:
        type = types[0].split(',')
    else:
        print(f"Variable type can only be one. Got \"{types}\"")
        sys.exit(0)

    parsed_args['type']  = type

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
            print("-range expects 4 or more degrees as [lat1,lat2,lon1,lon2, ...].")
            sys.exit(0)
        rlist = [float(item) for item in args.range.split(',')]

        lats=rlist[0:2]
        lons=rlist[2:4]
        parsed_args['ranges'] = [min(lons),max(lons),min(lats),max(lats)]

    # Require t_copy parameter for slice plotting
    if args.scatter is None:
        if parsed_args['type'] is not None and parsed_args['type'][0] == "list":
            pass
        else:
            if parsed_args['t_copy'] is None:
                print('ERROR: need option "-p" to know which observation copy to be plotted.')
                sys.exit(1)

    #if args.scatter is None and parsed_args['varnames'][0] != "list":
    #    if args.grid is None:
    #        print("ERROR: a WRF file is required to interpolate the field to the grid.")
    #        sys.exit(1)
    #    else:
    #        if not os.path.lexists(args.grid):
    #            print(f"ERROR: The grid file {args.grid} not exists.")
    #            sys.exit(1)

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

    parsed_args['rms_min'] = None
    if args.filter_by_rms is not None:
        parsed_args['rms_min'] = args.filter_by_rms

    parsed_args['obs_error_min'] = None
    if args.filter_by_rms is not None:
        parsed_args['obs_error_min'] = args.filter_by_rms

    parsed_args['plt_wofs'] = args.gridfile
    if args.gridfile is not None:
        if not os.path.lexists(args.gridfile):
            print(f"ERROR: The grid file {args.gridfile} not exists.")
            sys.exit(1)

    return args, make_namespace(parsed_args)

########################################################################

def load_variables(args):

    var_obj = {}

    if os.path.lexists(args.obsfile):

        # int obs_type(ObsIndex) ;
        #         obs_type:long_name = "DART observation type" ;
        #         obs_type:explanation = "see ObsTypesMetaData" ;
        # double observations(ObsIndex, copy) ;
        #         observations:long_name = "org observation, estimates, etc." ;
        #         observations:explanation = "see CopyMetaData" ;
        #         observations:missing_value = 9.96920996838687e+36 ;
        # int qc(ObsIndex, qc_copy) ;
        #         qc:long_name = "QC values" ;
        #         qc:explanation = "see QCMetaData" ;
        # double location(ObsIndex, locdim) ;
        #         location:description = "location coordinates" ;
        #         location:location_type = "loc3Dsphere" ;
        #         location:long_name = "threed sphere locations: lon, lat, vertical" ;
        #         location:storage_order = "Lon Lat Vertical" ;
        #         location:units = "degrees degrees which_vert" ;
        # int which_vert(ObsIndex) ;
        #         which_vert:long_name = "vertical coordinate system code" ;
        #         which_vert:VERTISUNDEF = -2 ;
        #         which_vert:VERTISSURFACE = -1 ;
        #         which_vert:VERTISLEVEL = 1 ;
        #         which_vert:VERTISPRESSURE = 2 ;
        #         which_vert:VERTISHEIGHT = 3 ;
        #         which_vert:VERTISSCALEHEIGHT = 4 ;

        with Dataset(args.obsfile, 'r') as fh:
            varobs  = fh.variables['observations'][:,:]   # (ObsIndex, copy)
            varqc   = fh.variables['qc'][:,:]             # (ObsIndex, qc_copy)
            varloc  = fh.variables['location'][:,:]
            varvert = fh.variables['which_vert'][:]

            obstype = fh.variables['obs_type'][:]
            TypesMeta = fh.variables['ObsTypesMetaData'][:,:]

            nqc_copy  = fh.dimensions['qc_copy'].size
            qccopy    = fh.variables['qc_copy'][:]
            QCMeta    = fh.variables['QCMetaData'][:,:]

            ncopy     = fh.dimensions['copy'].size
            CopyMetaData = fh.variables['CopyMetaData'][:,:]

            vartime   = fh.variables['time'][:]

        nobs           = varqc.shape[0]
        validqc        = {}
        validtypes     = {}
        validqcval     = []

        validverts      = []
        validpres       = []
        validhgts       = []

        # go through each observations
        for j in range(0,nqc_copy):
            validqc[f"{qccopy[j]}"] = QCMeta[j,:].tobytes().decode('utf-8')

        validtypevals = np.unique(obstype)
        for type in validtypevals:
            validtypes[f'{type}'] = TypesMeta[type-1,:].tobytes().decode('utf-8')

        validqcval = np.unique(varqc)

        validverts = np.unique(varvert)

        obs_pres = np.where(varvert == 2)[0]     # ISPRESSURE
        obs_hgts = np.where(varvert == 3)[0]     # ISHEIGHT
        if len(obs_pres) > 0:
            validpres = varloc[obs_pres,2]

        if len(obs_hgts) > 0:
            validhgts = varloc[obs_hgts,2]

        copyMeta = {}
        for k in range(0,ncopy):
            copyMeta[str(k+1)] = CopyMetaData[k,:].tobytes().decode('utf-8')

        varlabels={
                '1' : 'ObsValue',            # 1: NCEP BUFR observation
                '2' : 'priorMean',           # 2: prior ensemble mean
                '3' : 'postMean',            # 3: posterior ensemble mean
                '4' : 'priosSpread',         # 4: prior ensemble spread
                '5' : 'postSpread'           # 5: posterior ensemble spread
                 }

        for k,sv in copyMeta.items():
            if k not in ('1','2','3','4','5'):
                s = sv.strip()
                if s.startswith("prior ensemble member"):
                    varlabels[k] = f'priorMem{s.split()[-1]}'
                elif s.startswith("posterior ensemble member"):
                    varlabels[k] = f'postMem{s.split()[-1]}'
                elif s == "observation error variance":
                    varlabels[k] = 'ObsErrVar'
                else:
                    print(f"ERROR: unknow variable copy {k} -> {s}.")
                    sys.exit(0)

        qclabels = {'0' : 'assim',         # 0: assimilated successfully
                    '1' : 'eval',          # 1: evaluated only, not used in the assimilation
                    '2' : 'APFfail',       # 2: posterior forward failed
                    '3' : 'EPFfail',
                    '4' : 'PFfail',        # 4: prior forward failed, not used
                    '5' : 'NA',            # 5: not used because not selected in namelist
                    '6' : 'QCrejected',    # 6: incoming qc value was larger than threshold
                    '7' : 'outlier'        # 7: Outlier threshold test failed
                    }
    else:
        print(f"ERROR: file {args.obsfile} not found")
        sys.exit(1)

    var_obj['validqc']    = validqc      # QCMetaData
    var_obj['validtypes'] = validtypes   # ObsTypesMetaData
    var_obj['validqcval'] = validqcval   # qc, distinguis values
    var_obj['validverts'] = validverts   # which_vert, distinguis values
    var_obj['validpres']  = validpres    # location, distinguis values in 3rd dimension of location
    var_obj['validhgts']  = validhgts    # location, distinguis values in 3rd dimension of location
    var_obj['copyMeta']   = copyMeta     # CopyMetaData
    var_obj['varlabels']  = varlabels    # CopyMetaData
    var_obj['qclabels']   = qclabels     # CopyMetaData

    var_obj['distypes']   = validtypevals    # distinguished type integer values

    var_obj['nobs']     = nobs
    var_obj['nvarcopy'] = ncopy
    var_obj['nqccopy']  = nqc_copy
    var_obj['varqc']    = varqc      # int qc(ObsIndex, qc_copy)
    var_obj['obstype']  = obstype    # int obs_type(ObsIndex)
    var_obj['varloc']   = varloc     # double location(ObsIndex, locdim)
    var_obj['varvert']  = varvert    # int which_vert(ObsIndex)
    var_obj['varobs']   = varobs     # double observations(ObsIndex, copy)
    var_obj['vartime']  = vartime     # double observations(ObsIndex, copy)

    return make_namespace(var_obj,level=1)

########################################################################

def load_obs_seq(varargs):

    var_obj = {}

    vardat = []
    varloc = []
    vartim = []
    vartyp = []
    varqc_ = []
    varver = []

    validtypevals = []

    type_re = re.compile('\d+ [A-Z_]+')
    type_labels = {}
    var_labels  = {}
    qc_labels   = {}

    #expect_time = varargs.time.timestamp()
    #expt1 = expect_time - 300
    #expt2 = expect_time + 300

    nobs = 0
    if os.path.lexists(varargs.obsfile):

        with open(args.obsfile,'r') as fh:
            while True:
                line = fh.readline().strip()
                if not line: break
                #print(line)
                if type_re.match(line):
                    type,label = line.split()
                    type_labels[type] = label
                    if type not in validtypevals:
                        validtypevals.append(type)

                elif line.startswith('num_copies:'):
                    ncopy,nqc = line.split()[1:4:2]
                    ncopy = int(ncopy)
                    nqc   = int(nqc)
                    #nobslines = 8+ncopy+nqc
                elif line.startswith('num_obs:'):
                    nobs = line.split()[1]
                    label_gen = islice(fh, ncopy)
                    for i,label in enumerate(label_gen):
                        var_labels[str(i+1)] = label.strip()

                    label_gen = islice(fh, nqc)
                    for i,label in enumerate(label_gen):
                        qc_labels[str(i)] = label.strip()

                elif line.startswith("OBS"):
                    #obs_gen = islice(fh, nobslines)
                    obs = decode_obs_seq_OBS(fh,ncopy,nqc)
                    vardat.append(obs.value)
                    varloc.append((obs.lon,obs.lat,obs.level))
                    vartim.append(obs.time)
                    vartyp.append(obs.type)
                    varqc_.append(obs.qc)
                    varver.append(obs.level_type)

    #print(f"nobs = {nobs}")

    var_obj['nobs']     = nobs
    var_obj['nvarcopy'] = ncopy
    var_obj['nqccopy']  = nqc
    var_obj['varobs']   = np.array(vardat)
    var_obj['varloc']   = np.array(varloc)
    var_obj['vartime']  = np.array(vartim)
    var_obj['obstype']  = np.array(vartyp)
    var_obj['varqc']    = np.array(varqc_)
    var_obj['varvert']  = np.array(varver)

    var_obj['distypes']   = validtypevals    # distinguished type integer values

    #print(var_obj['varqc'])
    # Meta data

    qclabels = { '0' : 'assim', '1' : 'eval', '2' : 'APFfail',
                 '3' : 'EPFfail',  '4' : 'PFfail',
                 '5' : 'NA',   '6' : 'QCrejected', '7' : 'outlier' }

    varlabels={
                '1' : 'ObsValue',
                '2' : 'priorMean',
                '3' : 'postMean',
                '4' : 'priosSpread',
                '5' : 'postSpread',
                '6' : 'priorMem1',
                '7' : 'postMem1',
                '8' : 'priorMem2',
                '9' : 'postMem2',
                '10': 'priorMem3',
                '11': 'postMeme3',
                '12': 'obserrVar'
            }

    varlabels1={
                '1' : 'Observation',
        }

    validqcval = np.unique(var_obj['varqc'])

    validverts = np.unique(var_obj['varvert'])

    obs_pres = np.where(var_obj['varvert'] == 2)[0]     # ISPRESSURE
    obs_hgts = np.where(var_obj['varvert'] == 3)[0]     # ISHEIGHT

    validpres = None
    validhgts = None
    if len(obs_pres) > 0:
        validpres = var_obj['varloc'][obs_pres,2]

    if len(obs_hgts) > 0:
        validhgts = var_obj['varloc'][obs_hgts,2]

    var_obj['validqc']    = qc_labels      # QCMetaData
    var_obj['validtypes'] = type_labels    # ObsTypesMetaData
    var_obj['validqcval'] = validqcval     # qc, distinguis values
    var_obj['validverts'] = validverts     # which_vert, distinguis values
    var_obj['validpres']  = validpres      # location, distinguis values in 3rd dimension of location
    var_obj['validhgts']  = validhgts      # location, distinguis values in 3rd dimension of location
    var_obj['copyMeta']   = var_labels     # CopyMetaData
    if ncopy == 1:
        var_obj['varlabels']  = varlabels1
    else:
        var_obj['varlabels']  = varlabels      # CopyMetaData
    var_obj['qclabels']   = qclabels       # CopyMetaData

    return make_namespace(var_obj,level=1)

########################################################################

def decode_obs_seq_OBS(fhandle,ncopy,nqc):

    nobslines = 8+ncopy+nqc

    inqc = ncopy+nqc
    iloc = inqc + 3
    itype = iloc + 2
    itime = itype + 1
    ivar = itime + 1

    values = []
    qcs    = []

    i = 0
    while True:
        line = fhandle.readline()
        sline = line.strip()

        if sline == "platform":
            itime = itype + 8
            ivar  = itime + 1
            nobslines = 15+ncopy+nqc
            #print(i,nobslines,itime,sline)

        if i < ncopy:
            values.append(float(sline))

        elif i < inqc:
            qc = float(sline)
            qcs.append(math.floor(qc))
        elif i == iloc:
            lon,lat,alt,vert = sline.split()

        elif i == itype:
            otype = int(sline)
            if otype >= 124 and otype <= 130:  # GOES observation contains an extra line for cloud base and cloud top heights
              itime = itype + 3                # and an integer line (?)
              ivar  = itime + 1
              nobslines = 10+ncopy+nqc

        elif i == itime:
            secs,days = sline.split()
        elif i == ivar:
            var=float(line)

        i+=1
        if i >= nobslines: break

    # 1970 01 01 00:00:00 is 134774 days 00 seconds
    # one day is 86400 seconds

    obsobj = {'value': values,
              'qc':    qcs,
              'lon':   math.degrees(float(lon)),
              'lat':   math.degrees(float(lat)),
              'level': float(alt),
              'level_type': int(vert),
              'type':  otype,
              'days':  int(days),
              'secs':  int(secs),
              'time':  float(days)+float(secs)/86400,
              'variance': var
              }

    return make_namespace(obsobj)

########################################################################

#QCValMeta = { '0' : 'assim',
#              '1' : 'eval only',
#              '2' : 'assim, post forward fail',
#              '3' : 'eval, post forward fail',
#              '4' : 'prior forward fail',
#              '5' : 'not used because not in the namelist',
#              '6' : 'prior QC rejected',
#              '7' : 'outlier rejected',
#              '8' : 'Vertical location conversion failed' }
QCValMeta = { '0' : 'assimilated successfully',
              '1' : 'evaluated only, not used in the assimilation',
              '2' : 'posterior forward failed',
              '3' : 'evaluated only, posterior forward failed',
              '4' : 'prior forward failed, not used',
              '5' : 'not used because not selected in namelist',
              '6' : 'incoming qc value was larger than threshold',
              '7' : 'Outlier threshold test failed',
              '8' : 'vertical location conversion failed'
            }

########################################################################

def print_meta(varobj):
    """ Output variable information in the file
    """

    global QCValMeta

    #-------------------------------------------------------------------
    # Retrieve QC numbers for each type

    if varobj.nqccopy > 1:
        iqc = 1
    else:
        iqc = 0

    validtypeqccount = {}
    for key in varobj.validtypes.keys():

        typeqcvals = {}
        #
        # Select obs_index by type
        #
        obs_index0 = np.where(varobj.obstype == int(key))[0]

        #
        # Select obs_index by qc flag
        #
        typeqcs = np.unique(varobj.varqc[obs_index0,iqc])
        for qval in typeqcs:
            obs_index1 = np.where(varobj.varqc[obs_index0,iqc] == qval)[0]

            typeqcvals[str(qval)] = len(obs_index1)

        validtypeqccount[key] = typeqcvals

    #-------------------------------------------------------------------
    # Print output messages

    print("\nValid QC_copy MetaData:")
    for j in varobj.validqc.keys():
        print(f"    {j}: {varobj.validqc[j]}")
    print("")

    print("Valid Observation Types:")
    for key in sorted(varobj.validtypes.keys(), key=int):
        print(f"    {key:>3}: {varobj.validtypes[key]}\t {validtypeqccount[key]}")
    print("")

    if len(varobj.validqc) == 1:
        print(f"Valid QC values: {sorted(varobj.validqcval)}")
    else:
        print(f"Valid QC values: {sorted(varobj.validqcval)} and meanings")
        for key,val in QCValMeta.items():
            if int(key) in varobj.validqcval:
                print(f"    {key}: {val}")
    print("")

    VertMeta = { '-2' : 'ISUNDEF      ' ,
                 '-1' : 'ISSURFACE    ' ,
                 ' 1' : 'ISLEVEL      ' ,
                 ' 2' : 'ISPRESSURE   ' ,
                 ' 3' : 'ISHEIGHT     ' ,
                 ' 4' : 'ISSCALEHEIGHT'
                }

    print(f"Valid vertical coordinates are: {sorted(varobj.validverts)} and meanings")
    for key,val in VertMeta.items():
        if int(key) in varobj.validverts:
            if key == ' 2':     # ISPRESSURE
                print(f"    {key}: {val}, {min(varobj.validpres)} -- {max(varobj.validpres)} / {len(varobj.validpres)}")
            elif key == ' 3':   # ISHEIGHT
                print(f"    {key}: {val}, {min(varobj.validhgts)} -- {max(varobj.validhgts)} / {len(varobj.validhgts)}")
            else:
                print(f"    {key}: {val}")
    print()

    print("CopyMeta for variables")
    for key,val in varobj.copyMeta.items():
        print(f"    {key}: {val}")
    print()

    return

########################################################################

def retrieve_plotvar(varargs,vtype,varobj):
    """ Select observation index based on command line arguments"""

    varmeta = {}
    #
    # Select obs_index by type
    #
    print(f"Select observations of type = {vtype} ....", end="")
    obs_index0 = np.where( varobj.obstype == int(vtype) )[0]
    print(f"    Got {len(obs_index0)} observations")
    if len(obs_index0) <= 0:  sys.exit(0)
    varmeta['type_number'] = vtype
    varmeta['type_label']  = varobj.validtypes[vtype].strip()

    #obs_index = obs_index0
    #varmeta['qc_label'] = 'all'
    #varmeta['level_label'] = 'all'

    #
    # Select obs_index by qc flag
    #
    if varobj.nqccopy > 1:
        iqc = 1
    else:
        iqc = 0

    print(f"Select observations of (qccopy = {iqc}) qc value = {varargs.t_qc} ....", end="")
    if varargs.t_qc.upper() == 'All':
        obs_index1 = obs_index0
        varmeta['qc_label'] = 'AllQC'
    else:
        obs_index1 = np.where( varobj.varqc[obs_index0,iqc] == int(varargs.t_qc) )[0]
        obs_index1 = obs_index0[obs_index1]    # To keep the original whole observation indices
        varmeta['qc_label'] = varobj.qclabels[varargs.t_qc]
    print(f"    Got {len(obs_index1)} observations")

    #
    # Select obs_index by vertical levels
    #
    if varargs.t_level == 'ALL':
        varmeta['level_label'] = 'AllLevels'
        print(f"Select observations of levels = {varargs.t_level} ....",end="")
    else:
        print(varargs.t_level, varargs.t_level_tolr)
        t_level_min = varargs.t_level - varargs.t_level_tolr
        t_level_max = varargs.t_level + varargs.t_level_tolr
        varmeta['level_label'] = str(varargs.t_level)
        print(f"Select observations of levels = {t_level_min} - {t_level_max} ....", end="")

    obs_index = []
    for n in obs_index1:
        if varargs.t_level == 'ALL':
            obs_index.append(n)
        else:
            l_flag = varobj.varvert[n]
            l_val  = varobj.varloc[n,2]
            if l_flag == int(varargs.t_level_type):
                if l_val >= t_level_min and l_val <= t_level_max:
                    obs_index.append(n)
    print(f"    Got {len(obs_index)} observations")

    #
    # Selection obs_index by varargs.obs_error_min
    #
    if varargs.obs_error_min is not None:
        obs_index2 = obs_index
        obs_index  = []

        print(f"Select observations of obs error >= {varargs.obs_error_min}", end="")

        for n in obs_index2:
            obs_error      = varobj.varobs[n,-1]           # last one is obs error variance
            if obs_error >= varargs.obs_error_min:
                obs_index.append(n)
        print(f"    Got {len(obs_index)} observations")
    #
    # Selection obs_index by varargs.rms_min
    #
    if varargs.rms_min is not None:
        obs_index3 = obs_index
        obs_index  = []

        print(f"Select observations of obs RMS >= {varargs.rms_min}", end="")

        for i in obs_index3:
            obs_value      = varobj.varobs[i,0]           # Obs values
            obs_prior_mean = varobj.varobs[i,1]           # prior_mean
            rms = (obs_value-obs_prior_mean)**2
            if rms >= varargs.rms_min:
                obs_index.append(n)
        print(f"    Got {len(obs_index)} observations")

    varmeta['number'] = len(obs_index)

    if len(obs_index) <= 0:
        print(f"ERROR: Number of observations for {vtype} - {varmeta['type_label']} is 0.")
        return make_namespace(varmeta), None,None,None

    #
    # Get plotting arrays
    #
    obslons = []
    obslats = []
    for i in obs_index:
        obslon = varobj.varloc[i,0]-360.0 if varobj.varloc[i,0] > 180.0 else varobj.varloc[i,0]
        obslat = varobj.varloc[i,1]
        obslons.append(obslon)
        obslats.append(obslat)

    obsdta  = []
    if varargs.t_copy == "0":
        varmeta['varlabel'] = "QC"
        vardat  = varobj.varqc[obs_index,1]
        validqcs = np.unique(vardat)
        varmeta['validqcs'] = validqcs
    else:
        ivar = int(varargs.t_copy)
        varmeta['varlabel'] = varobj.varlabels[str(ivar)]

        for i in obs_index:
            vardata = varobj.varobs[i,ivar-1]
            obsdta.append(vardata)

        vardat = np.array(obsdta)

    otime = varobj.vartime[obs_index][0]
    otime = int(otime * 3600*24)//300*300
    obstime = datetime.strptime('1601-01-01','%Y-%m-%d')+timedelta(seconds=otime)
    varmeta['time']  = obstime.strftime('%Y%m%d_%H:%M:%S')

    glons = np.array(obslons)
    glats = np.array(obslats)

    #
    # Sort the return arrays by data values
    #arrinds = vardat.argsort()
    #nvardata = vardat[arrinds[::-1]]
    #nglons   = glons[arrinds[::-1]]
    #nglats   = glats[arrinds[::-1]]

    #return make_namespace(varmeta), nglons,nglats,nvardata

    return make_namespace(varmeta), glons,glats,vardat

########################################################################

def retrieve_scattervar(cmdargs,vtype,varobj):
    """ Select observation index based on command line arguments"""

    global QCValMeta

    plot_meta = {}

    #
    # Select obs_index by type
    #
    print(f"Select observations of type = {vtype} ....",end="")
    obs_index = np.where( varobj.obstype == int(vtype) )[0]
    print(f"    Got {len(obs_index)} observations")

    plot_meta['type_label'] = varobj.validtypes[vtype].strip()

    #
    # Get plotting arrays
    #
    qcdta    = varobj.varqc[obs_index,1]
    if cmdargs.scatter == "mean":
        obsdta   = varobj.varobs[obs_index,0]
        priordta = varobj.varobs[obs_index,1]
        postdta  = varobj.varobs[obs_index,2]
    elif cmdargs.scatter == "spread":
        priordta = varobj.varobs[obs_index,3]
        postdta  = varobj.varobs[obs_index,4]

    timedta  = varobj.vartime[obs_index]

    if cmdargs.fill is not None:
        priordta = priordta.filled(fill_value=cmdargs.fill)
        postdta  = postdta.filled(fill_value=cmdargs.fill)

    validqcs = np.unique(qcdta)

    sdata = {}
    plot_meta['qc_label']={}
    for qc in validqcs:
        qcstr=str(qc)
        sdata[qcstr] = {}
        qindex = np.where(qcdta == qc)[0]
        if cmdargs.scatter == "mean":
            sdata[qcstr]['obs']   = obsdta[qindex]
        sdata[qcstr]['prior'] = priordta[qindex]
        sdata[qcstr]['post']  = postdta[qindex]
        #sdata[qcstr]['count'] = postdta[qindex].count()

        otime = timedta[qindex]
        obstime = datetime.strptime('1601-01-01','%Y-%m-%d')+timedelta(days=otime[0])
        sdata[qcstr]['time']  = obstime.strftime('%Y%m%d_%H:%M:%S')

        plot_meta['qc_label'][qcstr] = QCValMeta[qcstr]

    return make_namespace(plot_meta,level=1), sdata

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

def make_plot(wargs,obstype,wobj):
    """ wargs: Decoded working arguments
        obstype: Observation integer type value
        wobj:  Working object
    """

    global QCValMeta

    #-----------------------------------------------------------------------
    #
    # Process the plot variables
    #
    #-----------------------------------------------------------------------

    plot_meta, glons,glats,vardata = retrieve_plotvar(wargs,obstype,wobj)
    if plot_meta.number <= 0: return       # no valid observation selected

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

    #-----------------------------------------------------------------------
    #
    # Lambert grid for HRRR
    #
    #-----------------------------------------------------------------------

    carr= ccrs.PlateCarree()

    if wargs.basmap == "lambert":
        proj_hrrr = setup_hrrr_projection(carr).proj
    else:
        proj_hrrr = None

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
        y_position = 0.75
    else:
        ax = plt.axes(projection=proj_hrrr)
        #ax.set_extent(ranges,crs=carr)        #[-125.0,-70.0,22.0,52.0],crs=carr)
        y_position = 0.85

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
    lonrange=list(range(-140,-50,10))
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
    #ax.set_title(f'{plot_meta.varlabel} for {plot_meta.type_label} on {plot_meta.time} with QC "{plot_meta.qc_label}" on "{plot_meta.level_label}"')
    plt.title(f'{plot_meta.varlabel} for {plot_meta.type_label} on {plot_meta.time} with QC "{plot_meta.qc_label}" on "{plot_meta.level_label}"')
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

    # int qc(ObsIndex, qc_copy) ;
    # ;FIRST PART OF ARRAY is 0/1, SECOND CONTAINS 2-7 INF
    # 0 = assim, 1 = eval only,
    # 2 = assim, post forward fail,
    # 3 = eval, post forward fail,
    # 4 = prior forward fail, $
    # 5 = N/A,
    # 6 = prior QC rejected,
    # 7 = outlier rejected

    # double observations(ObsIndex, copy) ;
    # data=         REFORM(outdata[0,*])
    # prior_mean=   REFORM(outdata[1,*])
    # post_mean=    REFORM(outdata[2,*])
    # prior_spread= REFORM(outdata[3,*])
    # post_spread=  REFORM(outdata[4,*])
    # obsvar=       REFORM(outdata[5,*])

    if wargs.t_copy == "0":
        mks = ['o', 'x', '+', '*', 's', 'D', '^', '1']
        cls = ['g', 'r', 'm', 'c', 'k', 'y', 'b', 'k']
        j = 0
        for qc in plot_meta.validqcs:
            lons = glons[vardata == qc]
            lats = glats[vardata == qc]
            ax.scatter(lons,lats,marker=mks[j], color=cls[j], s=0.6,  alpha=0.6, transform=ccrs.Geodetic(),label=QCValMeta[str(qc)])
            j += 1

        plt.legend(loc="upper left")

        #for j,mk in enumerate(mks):
        #    y = 0.9-j*0.02
        #    plt.plot(0.10,  y, marker=mk, color=cls[j], markersize=8,transform=plt.gcf().transFigure)
        #    plt.text(0.11,  y-0.006, f": {QCValMeta[str(j)]}", color=cls[j], fontsize=14,transform=plt.gcf().transFigure)

    else:
        #print(f"Writing to vr_{plot_meta.time}.txt ....")
        #with open(f'vr_{plot_meta.time}.txt','w') as vout:
        #    for i, v in enumerate(vardata):
        #        vout.write(f"{i}: ({glons[i]},{glats[i]}); {v}\n")

        alphaval = 1.0
        if 'RADIAL_VELOCITY' in plot_meta.varlabel.upper():             # obstype == '119':
            alphaval = 0.2

        varname = plot_meta.varlabel
        if 'REFLECTIVITY' in plot_meta.varlabel.upper():                # obstype == '120':
            varname = 'refl'

        color_map, normc = get_var_contours(varname,vardata,wargs.cntlevel)
        #cntlevels = list(np.linspace(cmin,cmax,9))

        cntr = ax.scatter(glons,glats,marker='.', c=vardata, alpha=alphaval, s=8.0, cmap=color_map, norm=normc, transform=carr)

        plt.text(0.15,y_position, f'Number of observations: {plot_meta.number}', color='r', horizontalalignment='left', verticalalignment='center',fontsize=14,transform=plt.gcf().transFigure)

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
        cbar.set_label(plot_meta.type_label)

    #-------------------------------------------------------------------
    # Write out the image file
    #-------------------------------------------------------------------
    if wargs.defaultoutfile:
        outpng = f"{plot_meta.varlabel}.{plot_meta.type_label}_{plot_meta.level_label}_{plot_meta.qc_label}_{plot_meta.time.replace(':','')}_{wargs.basmap}.png"
    else:
        root,ext=os.path.splitext(wargs.outfile)
        if ext != ".png":
            outpng = f"{wargs.outfile}_{plot_meta.type_label}_{plot_meta.level_label}_{plot_meta.qc_label}.png"
        else:
            outpng = wargs.outfile

    figname = os.path.join(wargs.outdir,outpng)
    print(f"Saving figure to {figname} ...")
    figure.savefig(figname, format='png', dpi=wargs.outresolution)
    plt.close(figure)

    #plt.show()

########################################################################

def get_array_lenstr(arr):

    if isinstance(arr, np.ma.MaskedArray):
        countstr = f"{arr.count()}+{np.ma.count_masked(arr)}"
    else:
        countstr = f"{len(arr)}"

    return countstr

########################################################################

def make_scatter(cargs,wargs,obstype,wobj):
    """ cargs: Command line arguments
        wargs: Decoded working arguments
        wobj:  Working object
    """

    figure = plt.figure(figsize = (12,12) )

    #fig,ax = plt.subplots()

    colors  = ['g','b','m','c','r','y','k']
    markers = ['o','^','d','H','+','X','-']

    #
    # Get prior & posterior
    #
    plot_meta, dta_s = retrieve_scattervar(cargs,obstype,wobj)

    if cargs.scatter == "mean":
        # Plot prior points
        dats = dta_s['0']
        countstr = get_array_lenstr(dats['prior'])
        priorlabel = f"Prior ensembe mean ({countstr})"
        plt.scatter(dats['obs'], dats['prior'], c='k', marker='*', label=priorlabel,alpha=0.6)
        xlabel = 'Observed Values'
        ylabel = 'Posterior/Prior Ensemble Mean'
        xobs_ax = 'obs'
    elif cargs.scatter == "spread":
        xlabel = 'Prior Spread'
        ylabel = 'Posterior Spread'
        xobs_ax = 'prior'

    # Plot post points
    i = 0
    for qc,dats in dta_s.items():
        countstr = get_array_lenstr(dats['post'])
        qclable = f"{plot_meta.qc_label[qc]} ({countstr})"

        plt.scatter(dats[xobs_ax], dats['post'], c=colors[i], marker=markers[i], alpha=0.1, label=qclable)
        i += 1

    if obstype == '119' and cargs.scatter == "mean":
        plt.ylim(-60, 60)

    plt.legend(loc='upper left')
    plt.xlabel(xlabel)
    plt.ylabel(ylabel)
    plt.title(f"Scatter Plot of {plot_meta.type_label} at {dta_s[qc]['time']}")

    #
    # Save figure to a file
    #
    if wargs.defaultoutfile:
        outpng = f"Obs{cargs.scatter.capitalize()}_{plot_meta.type_label}_{dta_s[qc]['time'].replace(':','')}.png"
    else:
        root,ext=os.path.splitext(wargs.outfile)
        if ext != ".png":
            outpng = f"{wargs.outfile}_{plot_meta.type_label}.png"
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

    if args.ncfmt:
        obs_obj = load_variables(args)
    else:
        obs_obj = load_obs_seq(args)

    if args.type is None:
        args.type = [str(t) for t in obs_obj.distypes]

    if cmd_args.verbose: print("\n Elapsed time of load_variables is:  %f seconds" % (timeit.time() - time1))

    if args.type[0] == "list":
        time2 = timeit.time()

        print_meta(obs_obj)

        if cmd_args.verbose: print("\n Elapsed time of print_meta is:  %f seconds" % (timeit.time() - time2))

        sys.exit(0)
    else:
        time3 = timeit.time()

        for obstype in args.type:
            #print(obstype)
            print("")
            if cmd_args.scatter is None:
                make_plot(args, obstype, obs_obj)
            else:
                if obs_obj.nvarcopy > 1:
                    make_scatter(cmd_args,args,obstype,obs_obj)
                else:
                    print(f"ERROR: there is no enough ncopy ({obs_obj.nvarcopy}) for scatter plots.")

        if cmd_args.verbose: print("\n Elapsed time of make_plot is:  %f seconds" % (timeit.time() - time3))

