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
import re,math
import argparse

from datetime import datetime, timedelta

import numpy as np

#''' By default matplotlib will try to open a display windows of the plot, even
#though sometimes we just want to save a plot. Somtimes this can cause the
#program to crash if the display can't open. The two commands below makes it so
#matplotlib doesn't try to open a window
#'''
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

import cartopy.crs as ccrs
import cartopy.feature as cfeature

from netCDF4 import Dataset

from pyproj import Transformer
#from scipy.spatial import KDTree
from scipy.interpolate import griddata

import time as timeit

########################################################################
#
# Load the dictionary into a Namespace data structure.
# This step is not necessary, but cuts down the syntax needed to reference each item in the dict.
#
# Example: Retrieve the 0 hr forecast Dataset from GFS Dynamics
#            dict: ds_dict['GFS']['dynf'][0]
#       Namespace: datasets.GFS.dynf[0]

def make_namespace(d: dict,l=0,level=None):
    ''' l    : level of this call
        level: level to stop, None is infinity
    '''
    assert(isinstance(d, dict))
    ns =  argparse.Namespace()
    for k, v in d.items():
        l += 1
        if isinstance(v, dict):
            if level is None or (level is not None and l < level):
                leaf_ns = make_namespace(v,l,level)
                ns.__dict__[k] = leaf_ns
            else:
                ns.__dict__[k] = v
        else:
            ns.__dict__[k] = v

    return ns

########################################################################

def dumpobj(obj, level=0, maxlevel=10):
    ''' Print object members nicely'''

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
    '''set contour specifications'''
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

    return color_map, normc, cmin, cmax, ticks_list

########################################################################

def setup_hrrr_projection(carr):
    '''Lambert conformal map projection for the HRRR domain'''

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

def parse_args():
    ''' Parse command line arguments
    '''
    parser = argparse.ArgumentParser(description='Plot DART obs_seq.fial in netCDF format',
                                     epilog='''        ---- Yunheng Wang (2023-07-24).
                                            ''')
                                     #formatter_class=CustomFormatter)

    parser.add_argument('obsfiles',help='DART obs_seq.fial in netCDF format')
    parser.add_argument('type',    help='Number to denote observation type or "list"', type=str,default=None)

    parser.add_argument('-v','--verbose',   help='Verbose output',                              action="store_true", default=False)
    parser.add_argument('-p','--parms',     help='Specify observations copy and quality, [copy,qc_flag]',  type=str, default=None)
    parser.add_argument('-l','--vertLevels',help='Vertical levels to be plotted [level,value,tolerance]',  type=str, default=None)
    parser.add_argument('-c','--cntLevels', help='Contour levels [cmin,cmax,cinc]',                        type=str, default=None)
    parser.add_argument('--scatter'      ,  help='Scatter plot of assimilated observations',               type=str, default=None)
    parser.add_argument('--fill'         ,  help='Value to fill masked values, apply to the scatter plot only',  type=float, default=None)
    parser.add_argument('-latlon'        ,  help='Base map latlon or lambert',                   action='store_true',default=False)
    parser.add_argument('-range'         ,  help='Map range in degrees [lat1,lon1,lat2,lon2]',             type=str, default=None)
    #parser.add_argument('--grid'         ,  help='Model file that provide grids',                type=str, default=None)
    parser.add_argument('-o','--outfile' ,  help='Name of output image or output directory',               type=str, default=None)

    args = parser.parse_args()

    parsed_args = {}
    parsed_args['basmap'] = "lambert"
    if args.latlon:
        parsed_args['basmap'] = "latlon"

    if args.vertLevels is not None:
        rlist = [float(item) for item in args.vertLevels.split(',')]
        parsed_args['t_level'] = f"{rlist[1]:8.2f}"
        parsed_args['t_level_type'] = str(rlist[0])
        parsed_args['t_level_tolr'] = rlist[2]
    else:
        parsed_args['t_level'] = 'ALL'

    parsed_args['t_copy'] = None
    parsed_args['t_qc']   = 'ALL'
    if args.parms is not None:
        rlist = [int(item) for item in args.parms.split(',')]
        parsed_args['t_copy'] = str(rlist[0])
        if len(rlist) > 1:
            parsed_args['t_qc']   = str(rlist[1])

    obsfiles  = []
    types     = []
    obsfile = args.obsfiles
    if  os.path.lexists(obsfile):
        obsfiles.append(obsfile)
    else:
        types.append(obsfile)

    if os.path.lexists(args.type):  # if the two arguments are out-of-order
        obsfiles.append(args.type)
    else:
        types.append(args.type)

    if len(obsfiles) == 1:
        parsed_args['obsfile'] = obsfiles[0]
    else:
        print(f"file name can only be one. Got \"{obsfiles}\"")
        sys.exit(0)

    if len(types) == 1:
        type = types[0]
    else:
        print(f"Variable type can only be one. Got \"{types}\"")
        sys.exit(0)

    parsed_args['type']  = type

    parsed_args['ranges'] = None     #[-135.0,-60.0,20.0,55.0]
    if args.range == 'hrrr':
        if args.latlon:
            parsed_args['ranges'] = [-135.0,-60.0,20.0,55.0]
        else:
            parsed_args['ranges'] = [-125.0,-70.0,22.0,52.0]
    elif args.range is not None:
        rlist = [float(item) for item in args.range.split(',')]
        if len(rlist) < 4:
            print("-range expects 4 or more degrees as [lat1,lon1,lat2,lon2, ...].")
            sys.exit(0)
        rlist = [float(item) for item in args.range.split(',')]

        lats=rlist[0::2]
        lons=rlist[1::2]
        parsed_args['ranges'] = [min(lons)-2.0,max(lons)+2.0,min(lats)-2.0,max(lats)+2.0]


    # Require t_copy parameter for slice plotting

    if args.scatter is None and parsed_args['type'] != "list":
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

    #
    # decode contour specifications
    #
    parsed_args['cntlevel'] = None
    if args.cntLevels is not None:
        parsed_args['cntlevel'] = [float(item) for item in args.cntLevels.split(',')]
        if len(parsed_args['cntlevel']) != 3:
            print(f"Option -c must be [cmin,cmax,cinc]. Got \"{args.cntLevels}\"")
            sys.exit(0)

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
                '12': 'obserrVar',
        }

        qclabels = { '0' : 'assim', '1' : 'eval', '2' : 'APFfail',
              '3' : 'EPFfail',  '4' : 'PFfail',
              '5' : 'NA',   '6' : 'QCrejected', '7' : 'outlier' }

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
    var_obj['varlabels']  = varlabels     # CopyMetaData
    var_obj['qclabels']   = qclabels     # CopyMetaData

    var_obj['nobs']    = nobs
    var_obj['varqc']   = varqc      # int qc(ObsIndex, qc_copy)
    var_obj['obstype'] = obstype    # int obs_type(ObsIndex)
    var_obj['varloc']  = varloc     # double location(ObsIndex, locdim)
    var_obj['varvert'] = varvert    # int which_vert(ObsIndex)
    var_obj['varobs']  = varobs     # double observations(ObsIndex, copy)
    var_obj['vartime'] = vartime     # double observations(ObsIndex, copy)

    return make_namespace(var_obj,level=1)

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

def print_meta(varobj):
    ''' Output variable information in the file
    '''

    global QCValMeta

    #-------------------------------------------------------------------
    # Retrieve QC numbers for each type

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
        typeqcs = np.unique(varobj.varqc[obs_index0,1])
        for qval in typeqcs:
            obs_index1 = np.where(varobj.varqc[obs_index0,1] == qval)[0]

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
        print(f"    {key:>3}: {varobj.validtypes[key]} {validtypeqccount[key]}")
    print("")

    print(f"Valid QC values: {sorted(varobj.validqcval)} and meanings")
    for key,val in QCValMeta.items():
        if int(key) in varobj.validqcval:
            print(f"    {key}: {val}")
    print()

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

def retrieve_plotvar(varargs,varobj):
    ''' Select observation index based on command line arguments'''

    plot_meta = {}
    #
    # Select obs_index by type
    #
    obs_index0 = np.where( varobj.obstype == int(varargs.type) )[0]
    plot_meta['type_label'] = varobj.validtypes[varargs.type].strip()

    #
    # Select obs_index by qc flag
    #
    if varargs.t_qc == 'ALL':
        obs_index1 = obs_index0
        plot_meta['qc_label'] = 'ALLQC'
    else:
        obs_index1 = np.where( varobj.varqc[:,1] == int(varargs.t_qc) )[0]
        plot_meta['qc_label'] = varobj.qclabels[varargs.t_qc]

    #
    # Select obs_index by vertical levels
    #
    if varargs.t_level == 'ALL':
        plot_meta['level_label'] = 'ALLlevels'
    else:
        t_level_min = varargs.t_level - varargs.t_level_tolr
        t_level_max = varargs.t_level + varargs.t_level_tolr
        plot_meta['level_label'] = str(varargs.t_level)

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
        plot_meta['varlabel'] = "QC"
        vardat  = varobj.varqc[obs_index,1]
        validqcs = np.unique(vardat)
        plot_meta['validqcs'] = validqcs
    else:
        ivar = int(varargs.t_copy)
        plot_meta['varlabel'] = varobj.varlabels[str(ivar)]

        for i in obs_index:
            vardata = varobj.varobs[i,ivar-1]
            obsdta.append(vardata)

        vardat = np.array(obsdta)

    otime = varobj.vartime[obs_index]
    obstime = datetime.strptime('1601-01-01','%Y-%m-%d')+timedelta(days=otime[0])
    plot_meta['time']  = obstime.strftime('%Y%m%d_%H%M%S')

    glons = np.array(obslons)
    glats = np.array(obslats)

    return make_namespace(plot_meta), obs_index, glons,glats,vardat

########################################################################

def retrieve_scattervar(cmdargs,varargs,varobj):
    ''' Select observation index based on command line arguments'''

    global QCValMeta

    plot_meta = {}

    #
    # Select obs_index by type
    #
    obs_index = np.where( varobj.obstype == int(varargs.type) )[0]

    plot_meta['type_label'] = varobj.validtypes[varargs.type].strip()

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

def make_plot(cargs,wargs,wobj):
    ''' cargs: Command line arguments
        wargs: Decoded working arguments
        wobj:  Working object
    '''

    global QCValMeta

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

    style = 'ggplot'

    figure = plt.figure(figsize = (12,12) )

    #-----------------------------------------------------------------------
    #
    # Process the plot variables
    #
    #-----------------------------------------------------------------------

    plot_meta, obs_index, glons,glats,vardat = retrieve_plotvar(wargs,wobj)

    if wargs.ranges is None:
        ranges = [glons.min()-2.0,glons.max()+2.0,glats.min()-2.0,glats.max()+2.0]
    else:
        ranges = wargs.ranges

    if wargs.type == '120':
        varname = 'refl'
    else:
        varname = plot_meta.varlabel

    color_map, normc,cmin, cmax, ticks_list = get_var_contours(varname,vardat,wargs.cntlevel)
    cntlevels = list(np.linspace(cmin,cmax,9))

    if wargs.basmap == "latlon":
        #carr._threshold = carr._threshold/10.
        ax = plt.axes(projection=carr)
        ax.set_extent(ranges,crs=carr)
    else:
        ax = plt.axes(projection=proj_hrrr)
        ax.set_extent(ranges,crs=carr)        #[-125.0,-70.0,22.0,52.0],crs=carr)

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
        cls = ['r', 'g', 'm', 'c', 'k', 'y', 'b', 'k']
        j = 0
        for qc in plot_meta.validqcs:
            lons = glons[vardat == qc]
            lats = glats[vardat == qc]
            ax.scatter(lons,lats,marker=mks[j], color=cls[j], s=0.4,  alpha=0.6, transform=ccrs.Geodetic(),label=QCValMeta[str(qc)])
            j += 1

        plt.legend(loc="upper left")

        #for j,mk in enumerate(mks):
        #    y = 0.9-j*0.02
        #    plt.plot(0.10,  y, marker=mk, color=cls[j], markersize=8,transform=plt.gcf().transFigure)
        #    plt.text(0.11,  y-0.006, f": {QCValMeta[str(j)]}", color=cls[j], fontsize=14,transform=plt.gcf().transFigure)

    else:
        cntr = ax.scatter(glons,glats,marker='.', c=vardat, alpha=1.0, s=4, cmap=color_map, norm=normc, transform=carr)

        #mod_obj = read_modgrid(cargs.grid)
        #mod_obs = interpolation2D({'lon': glons, 'lat': glats, 'value': vardat}, mod_obj)

        #ny = mod_obj['ny']
        #nx = mod_obj['nx']
        ##cntr = ax.contourf(mod_obj['lonCell'].reshape(ny,nx), mod_obj['latCell'].reshape(ny,nx), mod_obs.reshape(ny,nx),    cntlevels, cmap=color_map, norm=normc, transform=carr)
        #cntr = ax.contourf(mod_obj['lonCell'].reshape(ny,nx), mod_obj['latCell'].reshape(ny,nx), mod_obs, cntlevels, cmap=color_map, norm=normc, transform=carr)
        ##cntr = ax.contourf(mod_x.reshape(ny,nx), mod_y.reshape(ny,nx), mod_obs.reshape(ny,nx), cntlevels, cmap=color_map, norm=normc, transform=proj_hrrr)

        ##cntr = ax.tricontourf(glons, glats, vardat, cntlevels, antialiased=False, cmap=color_map, norm=normc, transform=carr)

        # https://matplotlib.org/api/colorbar_api.html
        #
        cax = figure.add_axes([ax.get_position().x1+0.01,ax.get_position().y0,0.02,ax.get_position().height])
        cbar = plt.colorbar(cntr, cax=cax)
        cbar.set_label(plot_meta.type_label)

    ax.coastlines(resolution='50m')
    #ax.stock_img()
    #ax.add_feature(cfeature.OCEAN)
    #ax.add_feature(cfeature.LAND, edgecolor='black')
    #ax.add_feature(cfeature.LAKES, edgecolor='black',facecolor='white')
    #ax.add_feature(cfeature.RIVERS)
    ax.add_feature(cfeature.BORDERS)
    ax.add_feature(cfeature.STATES,linewidth=0.1)
    if wargs.basmap == "latlon":
        gl = ax.gridlines(draw_labels=True,linewidth=0.2, color='gray', alpha=0.7, linestyle='--')
        gl.xlocator = mticker.FixedLocator([-140,-120, -100, -80, -60])
        gl.ylocator = mticker.FixedLocator([10,20,30,40,50,60])
        gl.top_labels = False
        gl.left_labels = True       #default already
        gl.right_labels = False
        gl.bottom_labels = True
        #gl.ylabel_style = {'rotation': 45}


    # Create the title as you see fit
    ax.set_title(f'{plot_meta.varlabel} for {plot_meta.type_label} with QC flag {plot_meta.qc_label} on {plot_meta.level_label}')
    plt.style.use(style) # Set the style that we choose above

    #

    if wargs.defaultoutfile:
        outpng = f"{plot_meta.varlabel}.{plot_meta.type_label}_{plot_meta.level_label}_{plot_meta.qc_label}_{plot_meta.time}.png"
    else:
        root,ext=os.path.splitext(wargs.outfile)
        if ext != ".png":
            outpng = f"{wargs.outfile}_{plot_meta.type_label}_{plot_meta.level_label}_{plot_meta.qc_label}.png"
        else:
            outpng = wargs.outfile

    figname = os.path.join(wargs.outdir,outpng)
    print(f"Saving figure to {figname} ...")
    figure.savefig(figname, format='png', dpi=100)
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

def make_scatter(cargs,wargs,wobj):
    ''' cargs: Command line arguments
        wargs: Decoded working arguments
        wobj:  Working object
    '''

    figure = plt.figure(figsize = (12,12) )

    #fig,ax = plt.subplots()

    colors  = ['g','b','m','c','r','y','k']
    markers = ['o','^','d','H','+','X','-']

    #
    # Get prior & posterior
    #
    plot_meta, dta_s = retrieve_scattervar(cargs,wargs,wobj)

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

    if wargs.type == '119' and cargs.scatter == "mean":
        plt.ylim(-60, 60)

    plt.legend(loc='upper left')
    plt.xlabel(xlabel)
    plt.ylabel(ylabel)
    plt.title(f"Scatter Plot of {plot_meta.type_label} at {dta_s[qc]['time']}")

    #
    # Save figure to a file
    #
    if wargs.defaultoutfile:
        outpng = f"Obs{cargs.scatter.capitalize()}_{plot_meta.type_label}_{dta_s[qc]['time']}.png"
    else:
        root,ext=os.path.splitext(wargs.outfile)
        if ext != ".png":
            outpng = f"{wargs.outfile}_{plot_meta.type_label}.png"
        else:
            outpng = wargs.outfile

    figname = os.path.join(wargs.outdir,outpng)
    print(f"Saving figure to {figname} ...")
    figure.savefig(figname, format='png', dpi=100)
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

    obs_obj = load_variables(args)

    if cmd_args.verbose: print("\n Elapsed time of load_variables is:  %f seconds" % (timeit.time() - time1))

    if args.type == "list":
        time2 = timeit.time()

        print_meta(obs_obj)

        if cmd_args.verbose: print("\n Elapsed time of print_meta is:  %f seconds" % (timeit.time() - time2))

        sys.exit(0)
    else:
        time3 = timeit.time()

        if cmd_args.scatter is not None:
            make_scatter(cmd_args,args,obs_obj)
        else:
            make_plot(cmd_args, args,obs_obj)

        if cmd_args.verbose: print("\n Elapsed time of make_plot is:  %f seconds" % (timeit.time() - time3))

