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
import re
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

import cartopy.crs as ccrs
import cartopy.feature as cfeature

from netCDF4 import Dataset
import pickle as pkle

import matplotlib.collections as mplcollections
import matplotlib.patches as patches
import matplotlib.path as path

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
            patch_collection = pkle.load(pickled_patches)
            pickled_patches.close()
            print("Pickle file (", pickle_fname, ") loaded succsfully")

            #serialized = jsonpickle.encode(patch_collection)
            #print(json.dumps(json.loads(serialized), indent=2))
            #print(yaml.dump(yaml.load(serialized), indent=2))
            #dump(patch_collection,0,2)

            return patch_collection
        except Exception as ex:
            print(ex)
            print("ERROR: Error while trying to read the pickled patches")
            print("ERROR: The pickle file may be corrupted or was not created")
            print("ERROR: succesfully!")
            sys.exit(-1)

    print("\nNo pickle file found, creating patches...")
    print("If this is a large mesh, then this proccess will take a while...")

    with Dataset(meshfile, 'r') as mesh:
        nCells         = len(mesh.dimensions['nCells'])
        nEdgesOnCell   = mesh.variables['nEdgesOnCell']
        verticesOnCell = mesh.variables['verticesOnCell']
        latVertex      = mesh.variables['latVertex']
        lonVertex      = mesh.variables['lonVertex']


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

    print(f"Using pickle file: {pickle_fname}")

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
        print(f"A valid pickle file for MPAS patches is required.")
        sys.exit(-1)
        #return None

def get_var_contours(varname,var2d,colormaps,cntlevels):
    '''set contour specifications'''

    #
    # set color map to be used
    #
    color_map = colormaps[0]
    if varname.startswith('refl') or varname.startswith('rain') :    # Use reflectivity color map and range
        color_map = colormaps[1]

    #
    # set contour levels
    #
    if cntlevels is not None:
        cmin,cmax,cinc = cntlevels
    else:
        cmin = var2d.min()
        cmax = var2d.max()
        if varname.startswith('refl'):    # Use reflectivity color map and range
            cmin = 0.0
            cmax = 80.0

    return color_map, cmin, cmax

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

    parser.add_argument('-v','--verbose',   help='Verbose output',                             action="store_true", default=False)
    #parser.add_argument('-g','--gridfile',  help='Name of the MPAS file that contains cell grid',         type=str, default=None)
    parser.add_argument('-p','--patchfile', help='Name of the MPAS patch file that contains cell patches',type=str, default=None)
    parser.add_argument('-l','--vertLevels',help='Vertical levels to be plotted [l1,l2,l3,...]',  type=str, default=None)
    parser.add_argument('-c','--cntLevels', help='Contour levels [cmin,cmax,cinc]',               type=str, default=None)
    parser.add_argument('-o','--outfile',   help='Name of output image or output directory',              type=str, default=None)

    args = parser.parse_args()

    basmap = "latlon"

    fcstfile = args.fcstfile
    varname  = args.varname
    if not os.path.lexists(fcstfile) and os.path.lexists(varname):  # if the two arguments are out-of-order
        fcstfile = varname
        varname  = args.fcstfile

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

    if varshapes[0] != 1 or varshapes[1] != nCells:
        print(f"Do not supported variable shape ({varshapes}).")
        sys.exit(0)

    #
    # Get patch file name
    #
    gridfile = fcstfile
    #if args.gridfile is not None:
    #    gridfile = args.gridfile

    if args.patchfile is not None:
        picklefile = args.patchfile
    else:
        picklefile = os.path.basename(gridfile).split('.')[0]
        picklefile = picklefile+'.'+str(nCells)+'.'+'patches'
        picklefile = os.path.join(os.path.dirname(gridfile),picklefile)

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
    patch_collection = load_mpas_patches(picklefile)

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
                    outtlt = f"{varname} ({varunits}) valid at {fcsttime} on level {l:02d}"
            elif varndim == 2:
                varplt = vardata[t,:]
                outlvl = ""
                outtlt = f"{varname} ({varunits}) valid at {fcsttime}"
            else:
                print(f"Variable {varname} is in wrong shape: {varshapes}.")
                sys.exit(0)

            color_map, cmin, cmax = get_var_contours(varname,varplt,(general_colormap,ref_colormap),cntlevel)

            figure = plt.figure(figsize = (12,12) )

            if basmap == "latlon":
                #carr._threshold = carr._threshold/10.
                ax = plt.axes(projection=carr)
                ax.set_extent([-135.0,-60.0,20.0,55.0],crs=carr)
            else:
                ax = plt.axes(projection=proj_hrrr)
                ax.set_extent([-125.0,-70.0,22.0,52.0],crs=carr)

            patch_collection.set_array(varplt)
            #patch_collection.set_edgecolors('w')       # No Edge Colors
            patch_collection.set_antialiaseds(False)    # Blends things a little
            patch_collection.set_cmap(color_map)        # Select our color_map
            patch_collection.set_clim(cmin,cmax)

            # Now apply the patch_collection to our axis '''
            ax.add_collection(patch_collection)

            #
            # Add a colorbar (if desired), and add a label to it. In this example the
            # color bar will automatically be generated. See ll-plotting for a more
            # advance colorbar example.

            # https://matplotlib.org/api/colorbar_api.html
            #
            cax = figure.add_axes([ax.get_position().x1+0.01,ax.get_position().y0,0.02,ax.get_position().height])
            cbar = plt.colorbar(patch_collection, cax=cax)
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
            gl.ylabel_style = {'rotation': 45}


            # Create the title as you see fit
            ax.set_title(outtlt)
            plt.style.use(style) # Set the style that we choose above

            #
            if defaultoutfile:
                outfile = f"{varname}.{fcstfname}{outlvl}.png"

            figname = os.path.join(outdir,outfile)
            print(f"Saving figure to {figname} ...")
            figure.savefig(figname, format='png', dpi=600)
            patch_collection.remove()
            plt.close(figure)

            #plt.show()
