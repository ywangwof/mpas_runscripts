#!/usr/bin/env python
#
# This module plots MPAS forecast 2D/3D fields on a horizontal slice by
# retriving a collection of MPL Path Patches for the MPAS unstructured mesh.
#
# The MPAS cell patches must be created beforehand with program "get_mpaspatches.py".
#
# This module was based on the following repository:
#
# * https://github.com/MiCurry/MPAS-Plotting
#
#-----------------------------------------------------------------------
#
# By Yunheng Wang (NOAA/NSSL, 2022.10.10)
#
#-----------------------------------------------------------------------

import os
import sys
import re, math
import argparse
import copy

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
import pickle as pkle

import matplotlib.collections as mplcollections
import matplotlib.patches as patches
import matplotlib.path as path

########################################################################
#
# Load the dictionary into a Namespace data structure.
# This step is not necessary, but cuts down the syntax needed to reference each item in the dict.
#
# Example: Retrieve the 0 hr forecast Dataset from GFS Dynamics
#            dict: ds_dict['GFS']['dynf'][0]
#       Namespace: datasets.GFS.dynf[0]

def make_namespace(d: dict):
    assert(isinstance(d, dict))
    ns =  argparse.Namespace()
    for k, v in d.items():
        if isinstance(v, dict):
            leaf_ns = make_namespace(v)
            ns.__dict__[k] = leaf_ns
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

def update_progress(job_title, progress):
    length = 40
    block = int(round(length*progress))
    msg = "\r{0}: [{1}] {2}%".format(job_title, "#"*block + "-"*(length-block), round(progress*100, 2))
    if progress >= 1: msg += " DONE\r\n"
    sys.stdout.write(msg)
    sys.stdout.flush()

########################################################################

def get_mpas_patches(meshfile, pickle_fname=None):

    print(f"Using pickle file: {pickle_fname}.")

    if(pickle_fname is not None and os.path.isfile(pickle_fname)):
        pickled_patches = open(pickle_fname,'rb')
        try:
            mypatch_collection = pkle.load(pickled_patches)
            pickled_patches.close()
            print("Pickle file (", pickle_fname, ") loaded succsfully")

            #serialized = jsonpickle.encode(patch_collection)
            #print(json.dumps(json.loads(serialized), indent=2))
            #print(yaml.dump(yaml.load(serialized), indent=2))
            #dump(patch_collection,0,2)

            return mypatch_collection
        except Exception as ex:
            print(ex)
            print("ERROR: Error while trying to read the pickled patches")
            print("ERROR: The pickle file may be corrupted or was not created")
            print("ERROR: succesfully!")
            sys.exit(-1)

    print("\nNo pickle file found, creating patches...")
    print("If this is a large mesh, then this proccess will take a while...")

    with Dataset(meshfile, 'r') as mymesh:
        nCells         = len(mymesh.dimensions['nCells'])
        nEdgesOnCell   = mymesh.variables['nEdgesOnCell']
        verticesOnCell = mymesh.variables['verticesOnCell']
        latVertex      = mymesh.variables['latVertex']
        lonVertex      = mymesh.variables['lonVertex']


        mesh_patches = [None] * nCells

        for cell in range(nCells):
            # For each cell, get the latitude and longitude points of its vertices
            # and make a patch of that point vertices
            vertices = verticesOnCell[cell,:nEdgesOnCell[cell]]
            vertices = np.append(vertices, vertices[0:1])

            vertices -= 1

            vert_lats = np.array([])
            vert_lons = np.array([])

            for lat in latVertex[vertices]:
                vert_lats = np.append(vert_lats, lat * (180 / np.pi))

            for lon in lonVertex[vertices]:
                dlon = ( (lon * (180 / np.pi))%360 + 540)%360 -180.
                vert_lons = np.append(vert_lons, dlon)

            # Normalize latitude and longitude
            diff = np.subtract(vert_lons, vert_lons[0])
            vert_lons[diff > 180.0] = vert_lons[diff > 180.] - 360.
            vert_lons[diff < -180.0] = vert_lons[diff < -180.] + 360.

            coords = np.vstack((vert_lons, vert_lats))

            cell_path = np.ones(vertices.shape) * path.Path.LINETO
            cell_path[0] = path.Path.MOVETO
            cell_path[-1] = path.Path.CLOSEPOLY
            cell_patch = path.Path(coords.T,
                                   codes=cell_path,
                                   closed=True,
                                   readonly=True)

            mesh_patches[cell] = patches.PathPatch(cell_patch)

            update_progress("Creating Patch file: "+pickle_fname, cell/nCells)

    print("\n")

    # Create patch collection
    patch_collection = mplcollections.PatchCollection(mesh_patches)

    # Pickle the patch collection
    pickle_file = open(pickle_fname, 'wb')
    pkle.dump(patch_collection, pickle_file)
    pickle_file.close()

    print("\nCreated a patch file for mesh: ", pickle_file)
    return patch_collection

########################################################################

def load_mpas_patches(pickle_fname):

    print(f"Using pickle file: \"{pickle_fname}\"")

    if(os.path.isfile(pickle_fname)):
        pickled_patches = open(pickle_fname,'rb')
        try:
            patch_collection = pkle.load(pickled_patches)
            pickled_patches.close()
            print("Pickle file (", pickle_fname, ") loaded succsfully")

            #serialized = jsonpickle.encode(patch_collection)
            #print(json.dumps(json.loads(serialized), indent=2))
            #print(yaml.dump(yaml.load(serialized), indent=2))
            #dump(patch_collection,0,2)

        except Exception as ex:
            print(ex)
            print("ERROR: Error while trying to read the pickled patches")
            print("ERROR: The pickle file may be corrupted or was not created")
            print("ERROR: succesfully!")
            sys.exit(-1)

        return patch_collection
    else:
        print("A valid pickle file for MPAS patches is required.")
        sys.exit(-1)
        #return None

########################################################################

def get_var_contours(varname,var2d,cargs):
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
        mycolors = copy.deepcopy(ctables.colortables['NWSReflectivity'])
        mycolors.insert(0,(1,1,1))
        #print("len mycolors = ",len(mycolors))
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
    cntlevels = cargs.cntlevel
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
        if varname.startswith('refl') and cargs.diffstr == "":    # Use reflectivity color map and range
            cmin = 0.0
            cmax = 80.0
            cinc = 5.0
            cntlevels = list(np.arange(cmin,cmax,5.0))
            normc = mcolors.Normalize(cmin,cmax)
            #ticks_list = [lvl for lvl in np.arange(cmin,cmax+cinc,2*cinc)]
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

def setup_hrrr_projection():
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
    parser = argparse.ArgumentParser(description='Plot MPAS grid variables using Cartopy',
                                     epilog='''        ---- Yunheng Wang (2022-10-08).
                                            ''')
                                     #formatter_class=CustomFormatter)

    parser.add_argument('fcstfiles', nargs='+',help='MPAS forecast files, two files to computer the difference')
    parser.add_argument('varname', help='Name of variable to be plotted',type=str, default=None)

    parser.add_argument('-v','--verbose',   help='Verbose output',                             action="store_true", default=False)
    #parser.add_argument('-g','--gridfile',  help='Name of the MPAS file that contains cell grid',         type=str, default=None)
    parser.add_argument('-p','--patchfile', help='Name of the MPAS patch file that contains cell patches',type=str, default=None)
    parser.add_argument('-l','--vertLevels',help='Vertical levels to be plotted [l1,l2,l3,...]',  type=str, default=None)
    parser.add_argument('-c','--cntLevels', help='Contour levels [cmin,cmax,cinc]',               type=str, default=None)
    parser.add_argument('-o','--outfile',   help='Name of output image or output directory',              type=str, default=None)
    parser.add_argument('-range'         ,  help='Map range in degrees [lat1,lat2,lon1,lon2]',type=str, default=None)

    args = parser.parse_args()

    out_args = {}

    basmap = "latlon"
    out_args['basmap'] = basmap

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
    varname = varnames[0]
    operator= None
    opmatch = re.match(r'([\w_]+)([+\-\*\/])([\w_]+)',varname)
    if opmatch:
        varnames=[opmatch.group(1),opmatch.group(3)]
        operator=opmatch.group(2)
    else:
        varnames=[varname]

    out_args['fcstfiles'] = fcstfiles
    out_args['varnames']  = varnames
    out_args['operator']  = operator

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

    out_args['caldiff'] = caldiff
    out_args['diffstr'] = diffstr

    ranges = [-135.0,-60.0,20.0,55.0]
    if args.range == 'hrrr':
        if args.latlon:
            ranges = [-135.0,-60.0,20.0,55.0]
        else:
            ranges = [-125.0,-70.0,22.0,52.0]
    elif args.range is not None:
        rlist = [float(item) for item in args.range.split(',')]
        if len(rlist) < 4:
            print("-range expects 4 or more degrees as [lat1,lon1,lat2,lon2, ...].")
            sys.exit(0)
        rlist = [float(item) for item in args.range.split(',')]

        lats=rlist[0:2]
        lons=rlist[2:4]
        ranges = [min(lons),max(lons),min(lats),max(lats)]

        #print(f"Name: {args.name}")
        #print("Type: custom")
        #print(f"Point: {args.ctrlon}, {args.ctrlat}")
        #for lon,lat in ranges:
        #    print(f"{lat}, {lon}")
        #print(" ")
    out_args['ranges']     = ranges
    out_args['vertLevels'] = args.vertLevels
    out_args['patchfile']  = args.patchfile

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

    out_args['defaultoutfile']  = defaultoutfile
    out_args['outdir']          = outdir
    out_args['outfile']         = outfile

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

    out_args['cntlevel']         = cntlevel

    return make_namespace(out_args)

########################################################################

def load_variables(cargs):

    fcstfile=cargs.fcstfiles[0]

    #
    # Load variable
    #
    if os.path.lexists(fcstfile):

        with Dataset(fcstfile, 'r') as mesh:
            nCells   = mesh.dimensions["nCells"].size
            try:
                nlevels = mesh.dimensions["nVertLevels"].size
            except:
                nlevels = 0

            try:
                nslevels = mesh.dimensions["nSoilLevels"].size
            except:
                nslevels = 0

            if cargs.varnames[0] == "list":
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
            else:
                for varname in cargs.varnames:
                    if varname not in mesh.variables.keys():
                        # Check to see the variable is in the mesh
                        print(f"This variable ({varname}) was not found in this mpas mesh!")
                        sys.exit(-1)

            # Pull the variable out of the mesh. Now we can manipulate it any way we choose
            # do some 'post-processing' or other meteorological stuff
            variable = mesh.variables[cargs.varnames[0]]
            varunits = variable.getncattr('units')
            varndim  = variable.ndim
            varshapes = variable.shape
            vardata   = variable[:]
            validtimestring = mesh.variables['xtime'][0].tobytes().decode('utf-8')
            if cargs.operator is not None:
                vardata1 = mesh.variables[cargs.varnames[1]][:]
                vardata = eval(f"x {cargs.operator} y",{"x":vardata,"y":vardata1})
                varname = f"{cargs.varnames[0]}{cargs.operator}{cargs.varnames[1]}"
            else:
                varname = cargs.varnames[0]

        if cargs.caldiff:
            with Dataset(cargs.fcstfiles[1], 'r') as mesh:
                vardata = vardata - mesh.variables[varname][:]
    else:
        print("ERROR: need a MPAS history/diag file.")
        sys.exit(0)

    out_variable = { 'varunits':  varunits,
                     'varndim':   varndim,
                     'varshapes': varshapes,
                     'vardata':   vardata,
                     'vartime':   validtimestring,
                     'varname':   varname,
                     'nlevels':   nlevels,
                     'nslevels':  nslevels,
                     'nCells':    nCells
                    }

    return make_namespace(out_variable)

########################################################################

def variable_validation(cargs, varobj):

    fcstfile = cargs.fcstfiles[0]

    fnamelist = os.path.basename(fcstfile).split('.')[2:-1]
    if len(fnamelist) > 0:
        fcstfname = '.'.join(fnamelist)
        fcsttime  = ':'.join(fnamelist).replace('_',' ')
    else:
        fcstfname = 'init'
    fcsttime  = varobj.vartime.strip().replace(':','.')
    #print(f"validtimestring={fcsttime}, {varobj.vartime}")

    need_levels = False
    if varobj.varndim == 1:
        levels=[0]
        if varobj.varshapes[0] != varobj.nCells:
            print(f"Do not supported variable shape ({varobj.varshapes}).")
            sys.exit(0)

    elif varobj.varndim == 2:
        levels=[0]

        if varobj.varshapes[0] == varobj.nCells and (varobj.varshapes[1] in (varobj.nlevels, varobj.nslevels,12)):
            varobj.varndim = 230           # static file
            need_levels = True
            vertshape = varobj.varshapes[1]
        elif varobj.varshapes[0] != 1 or varobj.varshapes[1] not in (varobj.nCells,varobj.nCells+1):
            print(f"Do not supported variable shape ({varobj.varshapes}).")
            sys.exit(0)
    elif varobj.varndim == 3:
        need_levels = True
        vertshape = varobj.varshapes[2]

        if varobj.varshapes[0] != 1 or varobj.varshapes[1] not in (varobj.nCells,varobj.nCells+1):
            print(f"Do not supported variable shape ({varobj.varshapes}).")
            sys.exit(0)
    else:
        print(f"Do not supported {varobj.varndim} dimensions array.")
        sys.exit(0)

    # Determine levels to be plotted
    if need_levels:
        if vertshape == varobj.nslevels:
            levels = range(varobj.nslevels)
        elif vertshape == varobj.nlevels:
            levels = range(varobj.nlevels)
        elif vertshape == varobj.nlevels+1:
            levels = range(varobj.nlevels+1)
        elif vertshape == 12:
            levels = range(vertshape)
        else:
            print(f"The 3rd dimension size ({vertshape}) is not in ({varobj.nlevels} or {varobj.nslevels}).")
            sys.exit(0)

        if cargs.vertLevels is not None:
            pattern = re.compile("^([0-9]+)-([0-9]+)$")
            pmatched = pattern.match(cargs.vertLevels)
            if pmatched:
                levels=range(int(pmatched[1]),int(pmatched[2]))
            elif cargs.vertLevels in ["max",]:
                levels=["max",]
            else:
                levels = [int(item) for item in cargs.vertLevels.split(',')]

    out_attrs = { 'fcstfname': fcstfname,
                  'fcsttime':  fcsttime,
                  'levels':    levels
                 }

    return make_namespace(out_attrs)

########################################################################

def make_plot(cargs,varobj,attrobj,var2d,pcollection,oattribs):

    #style = 'ggplot'

    figure = plt.figure(figsize = (12,12) )

    if cargs.basmap == "latlon":
        #carr._threshold = carr._threshold/10.
        ax = plt.axes(projection=carr)
        ax.set_extent(cargs.ranges,crs=carr)
    else:
        ax = plt.axes(projection=proj_hrrr)
        ax.set_extent([-125.0,-70.0,22.0,52.0],crs=carr)

    pcollection.set_array(var2d)
    #patch_collection.set_edgecolors('w')       # No Edge Colors
    pcollection.set_antialiaseds(False)    # Blends things a little
    pcollection.set_cmap(oattribs['color_map'])        # Select our color_map
    pcollection.set_norm(oattribs['plot_norm'])            # Select our normalization
    pcollection.set_clim(oattribs['cntr_cmin'],oattribs['cntr_cmax'])

    # Now apply the patch_collection to our axis
    ax.add_collection(pcollection)

    #
    # Add a colorbar (if desired), and add a label to it. In this example the
    # color bar will automatically be generated. See ll-plotting for a more
    # advance colorbar example.

    # https://matplotlib.org/api/colorbar_api.html
    #
    cax = figure.add_axes([ax.get_position().x1+0.01,ax.get_position().y0,0.02,ax.get_position().height])
    cbar = plt.colorbar(pcollection, cax=cax,ticks=oattribs['ticks_list'])
    cbar.set_label(f'{varobj.varname} ({varobj.varunits})')

    ax.coastlines(resolution='50m')
    #ax.stock_img()
    #ax.add_feature(cfeature.OCEAN)
    #ax.add_feature(cfeature.LAND, edgecolor='black')
    #ax.add_feature(cfeature.LAKES, edgecolor='black',facecolor='white')
    #ax.add_feature(cfeature.RIVERS)
    ax.add_feature(cfeature.BORDERS)
    ax.add_feature(cfeature.STATES,linewidth=0.1)
    if cargs.basmap == "latlon":
        gl = ax.gridlines(draw_labels=True,linewidth=0.2, color='gray', alpha=0.7, linestyle='--')
        gl.xlocator = mticker.FixedLocator([-140,-120, -100, -80, -60])
        gl.ylocator = mticker.FixedLocator([10,20,30,40,50,60])
        gl.top_labels = False
        gl.left_labels = True  #default already
        gl.right_labels = False
        gl.bottom_labels = True
        #gl.ylabel_style = {'rotation': 45}


    # Create the title as you see fit
    ax.set_title(oattribs['out_title'])
    #plt.style.use(style) # Set the style that we choose above

    #
    if cargs.defaultoutfile:
        outpng = f"{varobj.varname}{cargs.diffstr}.{attrobj.fcstfname}{oattribs['out_level']}.png"
    else:
        root,ext=os.path.splitext(cargs.outfile)
        if ext != ".png":
            outpng = f"{cargs.outfile}{oattribs['out_level']}.png"
        else:
            outpng = cargs.outfile


    figname = os.path.join(cargs.outdir,outpng)
    print(f"Saving figure to {figname} ...")
    figure.savefig(figname, format='png', dpi=200)
    plt.close(figure)

    #plt.show()

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#
# Main function defined to return correct sys.exit() calls
#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

if __name__ == "__main__":

    args = parse_args()

    variable = load_variables(args)

    attributes = variable_validation(args,variable)

    #
    # Get patch file name
    #
    gridfile = args.fcstfiles[0]
    #if args.gridfile is not None:
    #    gridfile = args.gridfile

    if args.patchfile is not None:
        picklefile = args.patchfile
    else:
        picklefile = os.path.basename(gridfile).split('.')[0]
        picklefile = picklefile+'.'+str(variable.nCells)+'.'+'patches'
        picklefile = os.path.join(os.path.dirname(gridfile),picklefile)

    #-----------------------------------------------------------------------
    #
    # Lambert grid for HRRR
    #
    #-----------------------------------------------------------------------

    carr= ccrs.PlateCarree()

    if args.basmap == "lambert":
        proj_hrrr = setup_hrrr_projection().proj
    else:
        proj_hrrr = None

    #-----------------------------------------------------------------------
    #
    # Plot field
    #
    #-----------------------------------------------------------------------

    #  we will be plotting actual MPAS polygons. The
    # `get_mpas_patches` function will create a collection of patches for the current
    # mesh for us AND it will save it, so that later we do not need to create it
    # again (Because often time creation is very slow).
    #
    # If you have a PickleFile someone where can supply it as the pickleFile argument
    # to the `get_mpas_patches` function.
    #
    # Doing things this way is slower, as we will have to not only loop through
    # nCells, but also nEdges of all nCells.
    #
    #patch_collection = get_mpas_patches(gridfile, picklefile)
    #patch_collection = load_mpas_patches(picklefile)

    t = 0
    for l in attributes.levels:

        if variable.varndim == 3:
            if l == "max":
                varplt = np.max(variable.vardata,axis=2)[t,:]
                outlvl = f"_{l}"
                outtlt = f"colum maximum {variable.varname}{args.diffstr} ({variable.varunits}) valid at {attributes.fcsttime}"
            else:
                varplt = variable.vardata[t,:,l]
                outlvl = f"_K{l:02d}"
                outtlt = f"{variable.varname}{args.diffstr} ({variable.varunits}) valid at {attributes.fcsttime} on level {l:02d}"
        elif variable.varndim == 230:
            varplt = variable.vardata[:,l]
            outlvl = f"_K{l:02d}"
            outtlt = f"{variable.varname}{args.diffstr} ({variable.varunits}) on level {l:02d}"
        elif variable.varndim == 2:
            varplt = variable.vardata[t,:]
            outlvl = ""
            outtlt = f"{variable.varname}{args.diffstr} ({variable.varunits}) valid at {attributes.fcsttime}"
        elif variable.varndim == 1:
            varplt = variable.vardata[:]
            outlvl = ""
            outtlt = f"{variable.varname}{args.diffstr} ({variable.varunits})"
        else:
            print(f"Variable {variable.varname} is in wrong shape: {variable.varshapes}.")
            sys.exit(0)

        color_map, normc,cmin, cmax, ticks_list = get_var_contours(variable.varname,varplt,args)

        plt_attribs = { 'out_title':  outtlt,
                        'out_level':  outlvl,
                        'color_map':  color_map,
                        'plot_norm':  normc,
                        'cntr_cmin':  cmin,
                        'cntr_cmax':  cmax,
                        'ticks_list': ticks_list
                      }

        patch_collection = load_mpas_patches(picklefile)
        make_plot(args,variable,attributes,varplt,patch_collection,plt_attribs)
        patch_collection.remove()
