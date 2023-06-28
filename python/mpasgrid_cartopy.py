#!/usr/bin/env python

import os, sys, math
import numpy as np

import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import matplotlib.patches as mpatches

from shapely.geometry.polygon import Polygon

import cartopy.crs as ccrs
import cartopy.feature as cfeature
import cartopy.geodesic as geodesic

import csv
import ast

from netCDF4 import Dataset
import argparse

#import strmrpt

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

def read_radar_location(radar_filename):

    radar_locations_dict = {}
    with open(radar_filename, 'r', encoding='ascii') as f:
        f.readline()
        for line in f:
            col = line.split()
            lat = float(col[-5])
            lon = float(col[-4])
            alt = 0.0003048 * float(col[-3])
            radar_locations_dict[col[1]] = (lat, lon, alt)

    return radar_locations_dict

########################################################################

def find_radars(radar_dict,rad_grd_lats, rad_grd_lons):
    #
    # Match radar name and table name
    #
    radars_inside = {}
    radars_outside = []
    for radar,radar_loc in radar_dict.items():
        if radar_loc[0]>rad_grd_lats[0] and radar_loc[0]<rad_grd_lats[1] and    \
           radar_loc[1]>rad_grd_lons[0] and radar_loc[1]<rad_grd_lons[1] :

            #radar.distance = (radar.lat-rlat)**2+(radar.lon-rlon)**2

            radars_inside[radar] = radar_dict[radar]
        else:
            radars_outside.append( radar )

    return radars_inside

########################################################################

def load_wofs_grid(filename,filext):

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

        plot_wofs = "pts"
    elif filext == ".nc":                       # netcdf grid file

        r2d = 57.2957795             # radians to degrees

        with Dataset(args.pts_file,'r') as mesh:
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

        plot_wofs = "grid"
    else:
        print("ERROR: need a MPAS grid file or custom pts file.")
        sys.exit(0)

    return plot_wofs,lonlats,make_namespace(mpas_grid)

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

def setup_out_projection(gridparms):
    ''' Lambert Conformal Map projection for the output domain'''

    xsize=(gridparms.nx-1)*gridparms.dx
    ysize=(gridparms.ny-1)*gridparms.dy

    x1d = np.linspace(0.0,xsize,num=gridparms.nx)
    y1d = np.linspace(0.0,ysize,num=gridparms.ny)

    #x2d1, y2d1 = np.meshgrid(x1d,y1d)

    xctr = (gridparms.nx-1)/2*gridparms.dx
    yctr = (gridparms.ny-1)/2*gridparms.dy

    proj=ccrs.LambertConformal(central_longitude=gridparms.ctrlon, central_latitude=gridparms.ctrlat,
                 false_easting=xctr, false_northing=yctr,
                 standard_parallels=gridparms.stdlats, globe=None)

    lonlat_sw = carr.transform_point(0.0,0.0,proj)

    if args.verbose:
      print("Write component output grid Parameters:")
      print(f"    cen_lat = {gridparms.ctrlat}, cen_lon = {gridparms.ctrlon}, stdlat1 = {gridparms.stdlats[0]}, stdlat2 = {gridparms.stdlats[1]}")
      print(f"    nx = {gridparms.nx}, ny = {gridparms.ny}, dx = {gridparms.dx}, dy = {gridparms.dy}")

    print(f'Output grid: lat1 = {lonlat_sw[1]}, lon1 = {lonlat_sw[0]}')

    grid_out  = {'proj'     : proj,
                 'xsize'    : xsize,
                 'ysize'    : ysize,
                 'ctrlat'   : gridparms.ctrlat,
                 'ctrlon'   : gridparms.ctrlon,
                 'xctr'     : xctr,
                 'yctr'     : yctr,
                 'x1d'      : x1d,
                 'y1d'      : y1d,
                 'lonlat_sw': lonlat_sw }

    return make_namespace(grid_out)

########################################################################

def attach_out_grid(grid,axo):
    '''Plot the output grid outlines'''

    axo.add_patch(mpatches.Rectangle(xy=[0, 0], width=grid.xsize, height=grid.ysize,
                                facecolor='none',edgecolor='green',linewidth=2.0,
                                transform=grid.proj))

    plt.text(grid.ctrlon,grid.ctrlat,'o',color='g',horizontalalignment='center',
                                        verticalalignment='center',transform=carr)

    transform1 = grid.proj._as_mpl_transform(axo)

    plt.annotate(f'({grid.ctrlat}, {grid.ctrlon})', xy=(grid.xctr,grid.yctr), xycoords=transform1,
                    xytext=(2, 12), textcoords='offset points',
                    color='green',
                    arrowprops=dict(arrowstyle="fancy")
                    )

########################################################################

def attach_hrrr_grid(grid, axo):
    '''Plot HRRR grid outlines'''

    axo.add_patch(mpatches.Rectangle(xy=[0, 0], width=grid.xsize, height=grid.ysize,
                facecolor='none',edgecolor='r',linewidth=1.0,
                transform=grid.proj))

    transform2 = grid.proj._as_mpl_transform(axo)
    plt.annotate('HRRR Center', xy=(grid.xctr,grid.yctr), xycoords=transform2,
                xytext=(-48, 24), textcoords='offset points',
                color='r',
                arrowprops=dict(arrowstyle="->")
                )

    plt.text(grid.ctrlon,grid.ctrlat,'o',color='r',horizontalalignment='center',
             verticalalignment='center',transform=carr)

    plt.text(grid.lonlat_sw[0]+0.2,grid.lonlat_sw[1]+0.4,'HRRR grid', color='r', transform=carr)

########################################################################

def attach_wofs_grid(plt_wofs,axo, lonlats,skipedges,mpas_grid):
    ''' Plot the WoFS domain '''

    if plt_wofs == "pts":
        polygon1 = Polygon( lonlats )
        axo.add_geometries([polygon1], crs=ccrs.Geodetic(), facecolor='blue',
                          edgecolor='navy', linewidth=1.5, alpha=0.2,zorder=1)

        for lon,lat in lonlats:
            plt.text(lon, lat, '*', color='r', horizontalalignment='center',
                    verticalalignment='center',transform=carr)

    elif plt_wofs == "grid":
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
                    color='blue', linewidth=0.1, marker='o', markersize=0.2,alpha=.2,
                    transform=carr) # Be explicit about which transform you want
    else:
        print(f"ERROR: unsupported plt_wofs = {plt_wofs}")
        return

########################################################################

def attach_radar_rings(grid,axo):
    '''Plot radar rings as possible'''

    xextradar = 100000.0    # extend range for radar searching 140 km
    yextradar = 100000.0

    xrad1 = grid.x1d[0]  - xextradar
    xrad2 = grid.x1d[-1] + xextradar
    yrad1 = grid.y1d[0]  - yextradar
    yrad2 = grid.y1d[-1] + yextradar

    (nothing,     rad_grd_lat1) = carr.transform_point(xrad1,yrad1, src_crs=grid.proj)
    (rad_grd_lon1,rad_grd_lat2) = carr.transform_point(xrad1,yrad2, src_crs=grid.proj)
    #(rad_grd_lon3,rad_grd_lat3) = carr.transform_point(xrad2,yrad1, src_crs=grid.proj)
    (rad_grd_lon2,nothing     ) = carr.transform_point(xrad2,yrad2, src_crs=grid.proj)

    print (f'Lat/lon at the SW corner of base grid= {rad_grd_lat1}, {rad_grd_lon1}.' )
    print (f'Lat/lon at the NE corner of base grid= {rad_grd_lat2}, {rad_grd_lon2}.' )

    radars = find_radars(radar_locations,[rad_grd_lat1, rad_grd_lat2],[rad_grd_lon1,rad_grd_lon2])

    for radar, radloc in radars.items():
        circle_points = geodesic.Geodesic().circle(lon=radloc[1], lat=radloc[0], radius=150000,
                                                   n_samples=300, endpoint=False)
        geom = Polygon(circle_points)
        axo.add_geometries((geom,), crs=carr, facecolor='none', edgecolor='darkgrey', linewidth=1.0)

        plt.text(radloc[1],radloc[0],radar,horizontalalignment='center',
                 verticalalignment='center',color='purple', transform=carr)

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#
# Main function defined to return correct sys.exit() calls
#

if __name__ == "__main__":

    parser = argparse.ArgumentParser(description='Plot MPAS grid outlines using Cartopy',
                                     epilog='''        ---- Yunheng Wang (2020-11-25).
                                            ''')
                                     #formatter_class=CustomFormatter)

    parser.add_argument('pts_file',help='MPAS domain file',nargs='?',default="xxxx")

    parser.add_argument('-v','--verbose', help='Verbose output',                        action="store_true")
    parser.add_argument('-ca','--ctrlat', help='Lambert Conformal central latitude',    type=float, default=38.5  )
    parser.add_argument('-co','--ctrlon', help='Lambert Conformal central longitude',   type=float, default=-97.5 )
    parser.add_argument('-s1','--stdlat1',help='Lambert Conformal standard latitude1',  type=float, default=38.5  )
    parser.add_argument('-s2','--stdlat2',help='Lambert Conformal standard latitude2',  type=float, default=38.5  )
    parser.add_argument('-nx',            help='number of grid in X direction',         type=int,   default=1601  )
    parser.add_argument('-ny'            ,help='number of grid in Y direction',         type=int,   default=961  )
    parser.add_argument('-dx'            ,help='grid resolution in X direction (meter)',type=float, default=3000.0)
    parser.add_argument('-dy'            ,help='grid resolution in Y direction (meter)',type=float, default=3000.0)
    parser.add_argument('-range'         ,help='Map range in degrees [lat1,lat2,lon1,lon2]',type=str, default=None)
    parser.add_argument('-outgrid'       ,help='Plot an output grid, "True" get grid from arguments, or filename',type=str, default=False)
    parser.add_argument('-radarfile'     ,help='NEXRAD radar file name',                type=str, default=None)
    parser.add_argument('-latlon'        ,help='Base map latlon or lambert',action='store_true', default=False)
    parser.add_argument('-name'          ,help='Name of the WoF grid',type=str, default="WoFS_mpas")

    args = parser.parse_args()

    #-----------------------------------------------------------------------
    #
    # Parse command line arguments
    #
    #-----------------------------------------------------------------------

    basmap = "lambert"
    if args.latlon:
        basmap = "latlon"

    figname = f"{args.name}.{basmap}.png"

    if os.path.lexists(args.pts_file):

        fileroot,filext = os.path.splitext(args.pts_file)
        #print(fileroot, filext)
        filename = f"{os.path.basename(fileroot)}.png"

        figname = filename.replace("custom",basmap)
        figname = filename.replace("grid",basmap)

        if filext in (".pts",".nc"):
            plt_wofs,lonlats,mpas_edges = load_wofs_grid(args.pts_file,filext)
        else:
            print("ERROR: need a MPAS grid file or custom pts file.")
            sys.exit(0)

        lats = [ l[1] for l in lonlats]
        lons = [ l[0] for l in lonlats]
    else:
        print("ERROR: need a WoF grid file.")
        sys.exit(0)

    plt_hrrr = False
    skipedges = 4
    if args.range == 'hrrr':
        plt_hrrr = True
        if args.latlon:
            ranges = [-135.0,-60.0,20.0,55.0]
        else:
            ranges = [-125.0,-70.0,22.0,52.0]

        skipedges = 10
    elif args.range is not None:
        rlist = [float(item) for item in args.range.split(',')]
        if len(rlist) < 4:
            print("-range expects 4 or more degrees as [lat1,lon1,lat2,lon2, ...].")
            sys.exit(0)
        rlist = [float(item) for item in args.range.split(',')]

        lats=rlist[0::2]
        lons=rlist[1::2]
        ranges = [min(lons)-2.0,max(lons)+2.0,min(lats)-2.0,max(lats)+2.0]

        #print(f"Name: {args.name}")
        #print("Type: custom")
        #print(f"Point: {args.ctrlon}, {args.ctrlat}")
        #for lon,lat in ranges:
        #    print(f"{lat}, {lon}")
        print(" ")
    else:
        ranges = [ min(lons)-2.0, max(lons)+2.0, min(lats)-2.0, max(lats)+2.0]

    print(f"ranges = {ranges}")

    plt_outgrid = False
    if args.outgrid == "True":
        plt_outgrid = True
        ogrid = {
                "nx"       : args.nx,
                "ny"       : args.ny,
                "dx"       : args.dx,
                "dy"       : args.dy,
                "ctrlon"   : args.ctrlon,
                "ctrlat"   : args.ctrlat,
                "stdlats"  : [args.stdlat1,args.stdlat2],
                }

    elif not args.outgrid:
        plt_outgrid = False
        ogrid = {}
    elif os.path.lexists(args.outgrid):
        data = []
        with open(args.outgrid,'r', encoding='ascii') as f:
            for line in f:
                if line.lstrip().startswith('#'):
                    continue
                data.append(line.lstrip().rstrip())

        # reconstructing the data as a dictionary
        ogrid = ast.literal_eval(' '.join(data))

        plt_outgrid = True
        #nx1         = ogrid["nx"]
        #ny1         = ogrid["ny"]
        #dx1         = ogrid["dx"]
        #dy1         = ogrid["dy"]
        #ctrlon1     = ogrid["ctrlon"]
        #ctrlat1     = ogrid["ctrlat"]
        #stdlat1_1   = ogrid["stdlat1"]
        #stdlat1_2   = ogrid["stdlat2"]
        ogrid["stdlats"] = [ogrid["stdlat1"],ogrid["stdlat2"]]
    else:
        print("ERROR: need an output grid file or command line arguments.")
        sys.exit(0)
    out_grid = make_namespace(ogrid)

    plt_radar = False
    if args.radarfile is not None:
        if not os.path.lexists(args.radarfile):
            print(f"Radar file {args.radarfile} not exist.")
        else:
            radar_locations = read_radar_location(args.radarfile)

        if len(radar_locations) > 0:
            plt_radar = True

    #-----------------------------------------------------------------------
    #
    # Set up Map projection
    #
    #-----------------------------------------------------------------------

    carr      = ccrs.PlateCarree()
    grid_hrrr = setup_hrrr_projection()

    #
    # Lambert Conformal Map projection for the output domain
    #
    if plt_outgrid:
        grid_out = setup_out_projection(out_grid)

    #-----------------------------------------------------------------------
    #
    # Plot background map
    #
    #-----------------------------------------------------------------------

    figure = plt.figure(figsize = (12,12) )

    if args.latlon:
        carr._threshold = carr._threshold/10.
        ax = plt.axes(projection=carr)
        ax.set_extent(ranges,crs=carr)
    else:
        if plt_outgrid:
            ax = plt.axes(projection=grid_out.proj)
        else:
            ax = plt.axes(projection=grid_hrrr.proj)

        ax.set_extent(ranges,crs=carr)

    if plt_hrrr:
        lonsticks = [-140,-120, -100, -80, -60]
        latsticks = [10,20,30,40,50,60]
    else:
        lonsticks = np.arange(math.floor(ranges[0]),math.ceil(ranges[1]), 2)
        latsticks = np.arange(math.floor(ranges[2]),math.ceil(ranges[3]), 4)

    ax.coastlines(resolution='50m')
    #ax.stock_img()
    ax.add_feature(cfeature.OCEAN,facecolor='skyblue')
    ax.add_feature(cfeature.LAND, facecolor='#666666')
    ax.add_feature(cfeature.LAKES, facecolor='skyblue')
    #ax.add_feature(cfeature.RIVERS,facecolor='skyblue')
    ax.add_feature(cfeature.BORDERS,linewidth=0.1)
    ax.add_feature(cfeature.STATES,linewidth=0.2)
    gl = ax.gridlines(draw_labels=True,linewidth=0.2, color='brown', alpha=1.0, linestyle='--')
    gl.xlocator      = mticker.FixedLocator(lonsticks)
    gl.ylocator      = mticker.FixedLocator(latsticks)
    gl.top_labels    = False
    gl.left_labels   = True
    gl.right_labels  = True
    gl.bottom_labels = True

    plt.title(f"{args.name} Domain")

    #-----------------------------------------------------------------------
    #
    # 1. Plot HRRR grid outlines
    #
    #-----------------------------------------------------------------------
    if plt_hrrr:
        attach_hrrr_grid(grid_hrrr,ax)

    #-----------------------------------------------------------------------
    #
    # 2. Plot the WoFS domain
    #
    #-----------------------------------------------------------------------

    attach_wofs_grid(plt_wofs,ax, lonlats,skipedges,mpas_edges)

    #-----------------------------------------------------------------------
    #
    # 3. Plot the output grid outlines
    #
    #-----------------------------------------------------------------------

    if plt_outgrid:
        attach_out_grid(grid_out,ax)
    #
    #-----------------------------------------------------------------------
    #
    # 4. Plot radar rings as possible
    #
    #-----------------------------------------------------------------------
        if plt_radar:
            attach_radar_rings(grid_out,ax)
    #
    #-------------------------------------------------------------------
    #
    # Finally, save the images to a file and show it as well
    #
    #-------------------------------------------------------------------

    print(f"Saving figure to {figname} ...")
    figure.savefig(figname, format='png')

    #plt.show()
