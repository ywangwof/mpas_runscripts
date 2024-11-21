#!/usr/bin/env python

import os, sys, math
import datetime
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

# Default values
_station_file         = 'conus2015.tbl'
_radar_file           = 'nexrad_stations.txt'
_default_WOFS_size    = 900.   # width of domain in km
_radar_buf_dis        = 100000.

# CONSTANTS
__r_earth              = 6367000.0

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

def color_text(field, color = 'white', darkness='dark', length=None, ):
    """Return the 'field' in collored terminal form"""

    Term_colors = {
      'black'  : 30,
      'red'    : 31,
      'green'  : 32,
      'yellow' : 33,
      'blue'   : 34,
      'magenta': 35,
      'cyan'   : 36,
      'white'  : 37,
    }

    bgcolor="00"
    if darkness == "light":
        bgcolor="01"

    outfield = field
    if length :
        if len(field) > length :
            outfield = field[:length-4]+' ...'
        else:
            outfield = field.ljust(length)

    if sys.stdout.isatty():    # You're running in a real terminal
        outfield = f'\x1B[{bgcolor};{Term_colors[color]}m{outfield}\x1B[00m'
    #else:                     # You're being piped or redirected

    return outfield

#enddef color_text

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

def read_sfc_station_file(station_file):

    sfc_stations_dict = {}
    with open(station_file, 'r') as f:
        for line in f:
            col = line.split()
            sfc_stations_dict[col[0]] = (0.01*float(col[5]), 0.01*float(col[6]))

    return sfc_stations_dict

########################################################################

def boundary_vertices(lonVertex, latVertex, bdyMaskVertex, edgesOnVertex, verticesOnEdge, bdyMask):
    bdyLats = []
    bdyLons = []

    for startVertex in range(bdyMaskVertex.size):
        if bdyMaskVertex[startVertex] == bdyMask:
            break

    for edge in edgesOnVertex[startVertex][:]:
        if edge == -1:
            continue

        if verticesOnEdge[edge][0] != startVertex:
            neighbor = verticesOnEdge[edge][0]
        else:
            neighbor = verticesOnEdge[edge][1]

        if bdyMaskVertex[neighbor] == bdyMask:
            nextVertex = neighbor
            bdyLons.append(lonVertex[nextVertex])
            bdyLats.append(latVertex[nextVertex])
            break

    prevVertex = startVertex

    while nextVertex != startVertex:
        for edge in edgesOnVertex[nextVertex][:]:
            if edge == -1:
                continue

            if verticesOnEdge[edge][0] != nextVertex:
                neighbor = verticesOnEdge[edge][0]
            else:
                neighbor = verticesOnEdge[edge][1]

            if bdyMaskVertex[neighbor] == bdyMask and neighbor != prevVertex:
                prevVertex = nextVertex
                nextVertex = neighbor
                bdyLons.append(lonVertex[nextVertex])
                bdyLats.append(latVertex[nextVertex])
                break

    return np.asarray(bdyLons), np.asarray(bdyLats)

def load_wofs_grid(filename):

    fileroot,filext = os.path.splitext(filename)
    #print(fileroot, filext)

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

        wofs_gridtype = "pts"

    elif filext == ".nc":                       # netcdf grid file

        r2d = 57.2957795             # radians to degrees

        with Dataset(args.pts_file,'r') as mesh:
            #xVertex = mesh.variables['xVertex'][:]
            #yVertex = mesh.variables['yVertex'][:]
            #zVertex = mesh.variables['zVertex'][:]

            #verticesOnCell = mesh.variables['verticesOnCell'][:,:]
            #nEdgesOnCell   = mesh.variables['nEdgesOnCell'][:]
            verticesOnEdge = mesh.variables['verticesOnEdge'][:,:]-1
            #lonCell = mesh.variables['lonCell'][:] * r2d
            #latCell = mesh.variables['latCell'][:] * r2d
            lonVertex = mesh.variables['lonVertex'][:] * r2d
            latVertex = mesh.variables['latVertex'][:] * r2d
            #lonEdge = mesh.variables['lonEdge'][:] * r2d
            #latEdge = mesh.variables['latEdge'][:] * r2d
            #hvar     = mesh.variables['areaCell'][:]
            bdyMaskVertex = np.ma.getdata(mesh.variables['bdyMaskVertex'][:])
            edgesOnVertex = np.ma.getdata(mesh.variables['edgesOnVertex'][:]) - 1

            nedges    = mesh.dimensions['nEdges'].size

        lonlats = [ (lon,lat) for lon,lat in zip(lonVertex,latVertex)]

        earthRadius = 6371229.0
        cenLat = np.sum(latVertex) / latVertex.size
        cenLon = np.sum(lonVertex) / lonVertex.size
        extentY = math.radians(max(latVertex) - min(latVertex)) * earthRadius
        extentX = math.radians(max(lonVertex) - min(lonVertex)) * math.cos(math.radians(cenLat)) * earthRadius
        print(f"    Domain Center = {cenLat:8.2f},{cenLon:8.2f}")
        print(f"    Domain Extent = {extentX/1000.:8.2f} km X {extentY/1000.:8.2f} km")

        bdyLons, bdyLats = boundary_vertices(lonVertex, latVertex, bdyMaskVertex, edgesOnVertex, verticesOnEdge, 1)
        bdyLonsSpec, bdyLatsSpec = boundary_vertices(lonVertex, latVertex, bdyMaskVertex, edgesOnVertex, verticesOnEdge, 7)

        mpas_grid = {"nedges"         : nedges,
                     "verticesOnEdge" : verticesOnEdge,
                     "lonVertex"      : lonVertex,
                     "latVertex"      : latVertex,
                     "bdyLons"        : bdyLons,
                     "bdyLats"        : bdyLats,
                     "bdyLonsSpec"    : bdyLonsSpec,
                     "bdyLatsSpec"    : bdyLatsSpec,
                    }

        #wofs_gridtype = "grid"
        wofs_gridtype = "hex"
    else:
        print("ERROR: need a MPAS grid file or custom pts file.")
        sys.exit(0)

    return wofs_gridtype,lonlats,make_namespace(mpas_grid)

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

    if hasattr(gridparms, "sizeinm"):
        # Get the domain corners based on the domain width

        lat_cr, lon_cr = np.deg2rad(gridparms.ctrlat), np.deg2rad(gridparms.ctrlon)

        glat = np.zeros(5)
        glon = np.zeros(5)

        glat[0] = lat_cr - 0.5*(gridparms.sizeinm) / __r_earth
        glat[1] = lat_cr + 0.5*(gridparms.sizeinm) / __r_earth
        glat[2] = lat_cr + 0.5*(gridparms.sizeinm) / __r_earth
        glat[3] = lat_cr - 0.5*(gridparms.sizeinm) / __r_earth
        glat[4] = lat_cr - 0.5*(gridparms.sizeinm) / __r_earth

        glon[0] = lon_cr - 0.5*(gridparms.sizeinm) / (__r_earth * np.cos(glat[0]))
        glon[1] = lon_cr - 0.5*(gridparms.sizeinm) / (__r_earth * np.cos(glat[1]))
        glon[2] = lon_cr + 0.5*(gridparms.sizeinm) / (__r_earth * np.cos(glat[2]))
        glon[3] = lon_cr + 0.5*(gridparms.sizeinm) / (__r_earth * np.cos(glat[3]))
        glon[4] = lon_cr - 0.5*(gridparms.sizeinm) / (__r_earth * np.cos(glat[4]))

        glon = np.rad2deg(glon)
        glat = np.rad2deg(glat)

        xygs = proj.transform_points(carr,glon,glat)

        grid_out['glons_corners'] = glon
        grid_out['glats_corners'] = glat
        grid_out['x_corners']     = list(xygs[:,0])
        grid_out['y_corners']     = list(xygs[:,1])

    return make_namespace(grid_out)

########################################################################

def attach_out_grid(grid,axo):
    '''Plot the output grid outlines'''

    #axo.add_patch(mpatches.Rectangle(xy=[0, 0], width=grid.xsize, height=grid.ysize,
    #                            facecolor='none',edgecolor='green',linewidth=2.0,
    #                            transform=grid.proj))

    plt.fill(grid.x_corners, grid.y_corners, linewidth=2.0, alpha=1.0,
             facecolor='none',edgecolor='green',  transform=grid.proj)

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

def attach_wofs_grid(wofsgridtype, axo, lonlats,skipedges,mpas_grid):
    ''' Plot the WoFS domain
    skipedges:  We do not want to plot all points of MPAS domain for time saving purpose
    '''

    if wofsgridtype == "pts":
        polygon1 = Polygon( lonlats )
        axo.add_geometries([polygon1], crs=ccrs.Geodetic(), facecolor='blue',
                          edgecolor='navy', linewidth=1.5, alpha=0.2,zorder=1)

        for lon,lat in lonlats:
            plt.text(lon, lat, '*', color='r', horizontalalignment='center',
                    verticalalignment='center',transform=carr)

    elif wofsgridtype == "grid":
        nedges = mpas_grid.nedges
        ecx = np.zeros((nedges,2),dtype=np.double)
        ecy = np.zeros((nedges,2),dtype=np.double)

        looprange=list(range(0,nedges,skipedges))

        ecy[:,0] = mpas_grid.latVertex[mpas_grid.verticesOnEdge[:,0]]
        ecx[:,0] = mpas_grid.lonVertex[mpas_grid.verticesOnEdge[:,0]]
        ecy[:,1] = mpas_grid.latVertex[mpas_grid.verticesOnEdge[:,1]]
        ecx[:,1] = mpas_grid.lonVertex[mpas_grid.verticesOnEdge[:,1]]

        for j in looprange:
            if abs(ecx[j,0] - ecx[j,1]) > 180.0:
              if ecx[j,0] > ecx[j,1]:
                 ecx[j,0] = ecx[j,0] - 360.0
              else:
                 ecx[j,1] = ecx[j,1] - 360.0

            plt.plot(ecx[j,:], ecy[j,:],
                    color='blue', linewidth=0.1, marker='o', markersize=0.2,alpha=0.4,
                    transform=carr) # Be explicit about which transform you want

    elif wofsgridtype == "hex":

        poly_corners = np.zeros((len(mpas_grid.bdyLons), 2), np.float64)
        poly_corners[:,0] = np.asarray(mpas_grid.bdyLons)
        poly_corners[:,1] = np.asarray(mpas_grid.bdyLats)

        poly = mpatches.Polygon(poly_corners, closed=True, ec='black', fill=True, lw=0.1, fc='black', alpha=0.3, transform=ccrs.Geodetic())
        ax.add_patch(poly)

        poly_corners = np.zeros((len(mpas_grid.bdyLonsSpec), 2), np.float64)
        poly_corners[:,0] = np.asarray(mpas_grid.bdyLonsSpec)
        poly_corners[:,1] = np.asarray(mpas_grid.bdyLatsSpec)

        poly = mpatches.Polygon(poly_corners, closed=True, ec='black', fill=True, lw=0.1, fc='black', alpha=0.3, transform=ccrs.Geodetic())
        axo.add_patch(poly)

    else:
        print(f"ERROR: unsupported wofs_gridtype = {wofsgridtype}")
        return

########################################################################

def search_radars(radars,grid):
    # search for radars inside the grid

    radar_within_domain = {}

    xmin = min(grid.x_corners)
    xmax = max(grid.x_corners)
    ymin = min(grid.y_corners)
    ymax = max(grid.y_corners)
    for key in radars:
        x, y = grid.proj.transform_point(radars[key][1], radars[key][0],carr)
        if x-_radar_buf_dis <= xmax and x+_radar_buf_dis >= xmin and \
           y-_radar_buf_dis <= ymax and y+_radar_buf_dis >= ymin:
            #radcords = radars[key]
            #radcords.append(x)
            #radcords.append(y)
            radar_within_domain[key] = radars[key]

    print(f"\n    Found {color_text(len(radar_within_domain),'green')} radars within domain\n")

    return radar_within_domain

########################################################################

def attach_radar_rings(grid,radars,axo):
    '''Plot radar rings as possible'''

    for radar, radloc in radars.items():
        circle_points = geodesic.Geodesic().circle(lon=radloc[1], lat=radloc[0], radius=150000,
                                                   n_samples=300, endpoint=False)
        geom = Polygon(circle_points)
        axo.add_geometries((geom,), crs=carr, facecolor='none', edgecolor='darkgrey', linewidth=1.0)

        plt.text(radloc[1],radloc[0],radar,horizontalalignment='center',
                 verticalalignment='center',color='purple', transform=carr)

########################################################################

def cal_grid_stat(mpas_grid, out_grid):
    '''
        mpas_grid = {"nedges"         : nedges,
                     "verticesOnEdge" : verticesOnEdge,
                     "lonVertex"      : lonVertex,
                     "latVertex"      : latVertex,
                    }
        grid_out['glons_corners']     # 0-4, from ll, ul, ur, lr, ll
        grid_out['glats_corners']
    '''

    delta = 0.05
    # distance to west to east
    mpas_lons = np.where(mpas_grid.lonVertex> 180.,mpas_grid.lonVertex-360.0,mpas_grid.lonVertex)
    mpas_lats = mpas_grid.latVertex

    wlon_edges = mpas_lons[(mpas_lats < out_grid.ctrlat+delta) & (mpas_lats > out_grid.ctrlat-delta)]
    wlat_edges = mpas_lats[(mpas_lats < out_grid.ctrlat+delta) & (mpas_lats > out_grid.ctrlat-delta)]

    print(wlat_edges.shape, wlat_edges.min(), wlat_edges.max(), wlon_edges.min(), wlon_edges.max(),wlat_edges.mean())
    wofdomsize = np.deg2rad(wlon_edges.max()-wlon_edges.min())*np.cos(np.deg2rad(wlat_edges.mean()))*__r_earth*0.001
    print(f"West to East: {wofdomsize} km")

    # distance to south to north
    slon_edges = mpas_lons[(mpas_lons < out_grid.ctrlon+delta) & (mpas_lons > out_grid.ctrlon-delta)]
    slat_edges = mpas_lats[(mpas_lons < out_grid.ctrlon+delta) & (mpas_lons > out_grid.ctrlon-delta)]

    print(slat_edges.shape, slat_edges.min(), slat_edges.max(), slon_edges.min(), slon_edges.max(),slat_edges.mean())
    wofdomsize = np.deg2rad(slat_edges.max()-slat_edges.min())*__r_earth*0.001
    print(f"South to North: {wofdomsize} km")

########################################################################

def write_envfile(outfilename,outradars,grid):

    rad_names = []
    rad_lats  = []
    rad_lons  = []
    rad_alts  = []
    for key,x in outradars.items():
        rad_names.append(key)
        rad_lats.append(str(x[0]))
        rad_lons.append(str(x[1]))
        rad_alts.append(str(round(x[2],7)))

    radnames = ' '.join(rad_names)
    radlats  = ' '.join(rad_lats)
    radlons  = ' '.join(rad_lons)
    radalts  = ' '.join(rad_alts)

    # Write out bash file.....

    with open(outfilename, 'w') as outfile:
        outfile.write("#!/bin/bash\n\n")

        nradars = len(outradars)

        outfile.write(f"export num_rad={nradars}\n"      )
        outfile.write(f"export rad_lon=( {radlons}  )\n" )
        outfile.write(f"export rad_lat=( {radlats}  )\n" )
        outfile.write(f"export rad_alt=( {radalts}  )\n" )
        outfile.write(f"export rad_name=({radnames} )\n" )
        outfile.write(f"export cen_lat={grid.ctrlat}\n"  )
        outfile.write(f"export cen_lon={grid.ctrlon}\n"  )

        outfile.write(f"export lat_ll={grid.glats_corners[0]}\n")
        outfile.write(f"export lat_ur={grid.glats_corners[1]}\n")
        outfile.write(f"export lon_ll={grid.glons_corners[0]}\n")
        outfile.write(f"export lon_ur={grid.glons_corners[2]}\n")

    return

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#
# Main function defined to return correct sys.exit() calls
#

if __name__ == "__main__":

    script_path = os.path.realpath(__file__)

    parser = argparse.ArgumentParser(description='Plot MPAS grid outlines using Cartopy',
                                     epilog='''        ---- Yunheng Wang (2020-11-25).
                                            ''')
                                     #formatter_class=CustomFormatter)

    parser.add_argument('pts_file',help='MPAS domain file in ASCII or netCDF',nargs='?',default="xxxx")

    parser.add_argument('-v','--verbose', help='Verbose output',                        action="store_true")

    parser.add_argument('-c','--center',  help='Central latitude/longitude of the WoFS domain',    type=float, default=None,    nargs = 2)
    parser.add_argument('-l','--stdlats', help='Lambert Conformal standard latitudes',      type=float, default=(30.0,60.0),    nargs = 2)
    parser.add_argument('-n','--nxy',     help='number of grid in X/Y direction',           type=int,   default=(301,301),      nargs = 2)
    parser.add_argument('-d','--dxy',     help='grid resolution in X/Y direction (meter)',  type=float, default=(3000.0,3000.0),nargs = 2)

    parser.add_argument('-s','--station',     help='Station name to center the WOFS grid on',         type=str,   default=None              )
    parser.add_argument('-w','--width',       help='Size of WOFS domain in km',                       type=float, default=_default_WOFS_size)
    parser.add_argument('-nudge',             help='Nudge the box X/Y km from station point: DX DY',  type=int,   default=(0,0), nargs = 2  )
    parser.add_argument('-f','--station_file',help='Station file name to read station locations',     type=str,   default=_station_file     )
    parser.add_argument('-g','--radar_file',  help='Radar file name for locations',                   type=str,   default=_radar_file       )

    parser.add_argument('-e','--event',    help='Event date string',    type=str, default=datetime.datetime.now().strftime('%Y%m%d') )
    parser.add_argument('-name',           help='Name of the WoF grid', type=str, default="WoFS_mpas"                                )
    parser.add_argument('-o','--outfile',  help='Name of output image or output directory',           type=str, default=None)

    parser.add_argument('-p','--plot',    help="Boolean flag to interactively plot domain",                     default=False, action="store_true")
    parser.add_argument('-m','--map' ,    help='Base map projection, latlon, stereo or lambert',type=str,default='lambert')
    parser.add_argument('-range'         ,help='Map range in degrees [lat1,lat2,lon1,lon2] or hrrr',   type=str,default=None)
    parser.add_argument('-outgrid'       ,help='Plot an output grid, "True", "False" or a filename. When "True", retrieve grid from command line.',type=str, default="False")

    args = parser.parse_args()

    #-----------------------------------------------------------------------
    #
    # Parse command line arguments
    #
    #-----------------------------------------------------------------------

    basmap = args.map

    #
    # Get MPAS grid
    #
    lats = None; lons = None; fileroot = None
    if os.path.lexists(args.pts_file):
        wofs_gridtype,lonlats,mpas_edges = load_wofs_grid(args.pts_file)

        lats = [ l[1] for l in lonlats]; cenLat = sum(lats) / len(lats)
        lons = [ l[0] for l in lonlats]; cenLon = sum(lons) / len(lons)
        plt_wofs = True
    else:
        plt_wofs = False

    #
    # Set up basemap range or use HRRR grid
    #
    plt_hrrr = False
    skipedges = 4
    if args.range == 'hrrr':
        plt_hrrr = True
        if basmap == "lambert":
            ranges = [-125.0,-70.0,22.0,52.0]
        else:
            ranges = [-135.0,-60.0,20.0,55.0]

        skipedges = 5

    elif args.range is not None:
        rlist = [float(item) for item in args.range.split(',')]
        if len(rlist) < 4:
            print("-range expects 4 or more degrees as [lat1,lon1,lat2,lon2, ...].")
            sys.exit(0)
        rlist = [float(item) for item in args.range.split(',')]

        lats=rlist[0::2]
        lons=rlist[1::2]
        ranges = [min(lons)-2.0,max(lons)+2.0,min(lats)-2.0,max(lats)+2.0]

        print(" ")
    else:
        if lats is None or lons is None:
            print("ERROR: Map range is required as \"[lat1,lon1,lat2,lon2]\" or the default 'hrrr' option." )
            parser.print_help()
            sys.exit(1)
        else:
            ranges = [ min(lons)-2.0, max(lons)+2.0, min(lats)-2.0, max(lats)+2.0]

    print(f"    ranges = {color_text(ranges,'cyan')}")

    earthRadius = 6371229.0
    extentY = math.radians(ranges[3] - ranges[2]) * earthRadius
    extentX = math.radians(ranges[1] - ranges[0]) * math.cos(math.radians(cenLat)) * earthRadius
    print(f"    extent = {extentX/1000.:8.2f} km X {extentY/1000.:8.2f} km")

    #
    # Decode output grid parameters
    #
    plt_outgrid = False
    lat_c = None
    lon_c = None
    if args.outgrid == "True":
        plt_outgrid = True
        ogrid = {
                "nx"       : args.nxy[0],
                "ny"       : args.nxy[1],
                "dx"       : args.dxy[0],
                "dy"       : args.dxy[1],
                "ctrlon"   : args.center[1],       # to be nudging later with lon_c/lat_c
                "ctrlat"   : args.center[0],
                "stdlats"  : args.stdlats,
                }
    elif args.outgrid == "False":
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
        ogrid["stdlats"] = [ogrid["stdlat1"],ogrid["stdlat2"]]
        lat_c = ogrid['ctrlat']
        lon_c = ogrid['ctrlon']
    else:
        print("ERROR: need an output grid file or command line arguments.")
        sys.exit(0)

    if plt_outgrid:
        #
        # Decode radar station file
        #
        plt_radar = False
        if args.radar_file is not None:
            if not os.path.lexists(args.radar_file):
                print(f"INFO: Radar station file {args.radar_file} not exist.")
                #parser.print_help()
                #sys.exit(1)
            else:
                radar_locations = read_radar_location(args.radar_file)
                print(f"    Read in radar file {color_text(args.radar_file,'blue')} successfully\n")

                if len(radar_locations) > 0:
                    plt_radar = True

        #
        # Decode surface station file
        #
        if lat_c is None or lon_c is None:
            if args.center is not None:
                print(f"WOFS grid center location supplied, using central lat/lon: {args.center}.")
                lat_c,lon_c = args.center
            elif args.station is not None:
                station_c = None
                print(f"WOFS grid center location supplied, using station: {args.station}.")
                station_c = args.station

                if os.path.lexists(args.station_file):
                    stations = read_sfc_station_file(args.station_file)
                    print(f"  Read in sfc station file {args.station_file} successfully")
                else:
                    print(f"\nERROR: surface station file: {args.station_file} not exist.\n")
                    parser.print_help()
                    sys.exit(1)

                print(f"  Input station: {args.station} is located at {stations[station_c][0]},  {stations[station_c][1]}\n")
                lat_c, lon_c = stations[station_c]
            else:
                print("ERROR:  Need either the 3-letter identifier for the WOFS grid center location or the central lat/lon on command line \n")
                parser.print_help()
                sys.exit(1)

            ogrid['ctrlat']  = lat_c
            ogrid['ctrlon']  = lon_c

        #
        # Decode nudging option
        #
        x_nudge   = 0.0
        y_nudge   = 0.0
        if args.nudge[0] != 0 or args.nudge[1] != 0:
            x_nudge = 1000.*float(args.nudge[0])
            y_nudge = 1000.*float(args.nudge[1])
            print(f"Set WOFS grid nudge from original center {lon_c,lat_c}, moving the grid DX = {x_nudge} meters,  DY = {y_nudge} meters")

        #
        # WoFS domain size
        #
        print(f"    Set WOFS grid width {color_text(args.width,'cyan')} km.")
        WOFS_size = 1000. * args.width
        ogrid['sizeinm'] = WOFS_size

    #
    # Output file dir / file name
    #
    if args.outfile is None:
        outdir  = './'
        outfile = None
    elif os.path.isdir(args.outfile):
        outdir  = args.outfile
        outfile = None
    else:
        outdir  = os.path.dirname(args.outfile)
        outfile = os.path.basename(args.outfile)

    if outfile is None:
        if fileroot is not None:
            filename = f"{os.path.basename(fileroot)}.png"
            outfile = filename.replace("custom",basmap)
            outfile = filename.replace("grid",basmap)
        else:
            outfile = f"{args.name}.{args.event}.{basmap}.png"

    figname = os.path.join(outdir,outfile)
    envfilename=os.path.join(outdir,f'{args.name}.radars.{args.event}.sh')

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

        #print(lon_c,lat_c)
        #print(x_c,y_c)
        #print(lon_c,lat_c)
        if x_nudge != 0 or y_nudge != 0:
            lon_o = lon_c
            lat_o = lat_c
            x_c, y_c    = grid_hrrr.proj.transform_point(lon_o,lat_o,carr)
            lon_c,lat_c = carr.transform_point(x_c+x_nudge,y_c+y_nudge,grid_hrrr.proj)
            print(f"  Grid center moved, from ({lat_o},{lon_o}) to ({lat_c},{lon_c}).")

        # Create Lambert conformal map based on width and height of domain and center point
        grid_out = setup_out_projection(make_namespace(ogrid))

    #cal_grid_stat(mpas_edges, grid_out)

    #-----------------------------------------------------------------------
    #
    # Plot background map
    #
    #-----------------------------------------------------------------------

    figure = plt.figure(figsize = (12,12) )

    if basmap == "latlon":
        carr._threshold = carr._threshold/10.
        ax = plt.axes(projection=carr)
        ax.set_extent(ranges,crs=carr)
    elif basmap == "stereo":
        scaling = 0.5
        proj = ccrs.Stereographic(cenLat, cenLon)
        ax = plt.axes(projection=proj)
        ax.set_extent([-scaling * extentX, scaling * extentX, -scaling * extentY, scaling * extentY], crs=proj)
    else:
        if plt_outgrid and args.range != 'hrrr':
            ax = plt.axes(projection=grid_out.proj)
        else:
            ax = plt.axes(projection=grid_hrrr.proj)

        ax.set_extent(ranges,crs=carr)

    #ax.coastlines(resolution='50m')

    #ax.stock_img()
    #ax.add_feature(cfeature.OCEAN,facecolor='skyblue')
    #ax.add_feature(cfeature.LAND, facecolor='#666666')
    #ax.add_feature(cfeature.LAKES, facecolor='skyblue')
    #ax.add_feature(cfeature.RIVERS,facecolor='skyblue')
    #ax.add_feature(cfeature.BORDERS,linewidth=0.1)
    #ax.add_feature(cfeature.STATES,linewidth=0.2)
    ax.add_feature(cfeature.LAND)
    ax.add_feature(cfeature.OCEAN)
    ax.add_feature(cfeature.COASTLINE, linewidth=0.1)
    ax.add_feature(cfeature.BORDERS,   linewidth=0.1)
    ax.add_feature(cfeature.LAKES,     linewidth=0.1)
    ax.add_feature(cfeature.RIVERS,    linewidth=0.1)
    ax.add_feature(cfeature.STATES,    linewidth=0.1)

    if basmap == "latlon" or basmap == "stereo":
        if plt_hrrr:
            lonsticks = [-140, -120, -100, -80, -60]
            latsticks = [10,20,30,40,50,60]
        else:
            lonsticks = np.arange(math.floor(ranges[0]),math.ceil(ranges[1]), 2)
            latsticks = np.arange(math.floor(ranges[2]),math.ceil(ranges[3]), 4)
        gl = ax.gridlines(draw_labels=True,linewidth=0.1, color='brown', alpha=1.0, linestyle='--')
        gl.xlocator      = mticker.FixedLocator(lonsticks)
        gl.ylocator      = mticker.FixedLocator(latsticks)
        gl.top_labels    = False
        gl.left_labels   = True
        gl.right_labels  = True
        gl.bottom_labels = True

    plt.title(f"{args.name} Domain on {args.event}")

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

    if plt_wofs:
        attach_wofs_grid(wofs_gridtype,ax, lonlats,skipedges,mpas_edges)

    #-----------------------------------------------------------------------
    #
    # 3. Plot the output grid outlines
    #
    #-----------------------------------------------------------------------

    if plt_outgrid:
        attach_out_grid(grid_out,ax)

    #-----------------------------------------------------------------------
    #
    # 4. Plot radar rings as possible
    #
    #-----------------------------------------------------------------------
        if plt_radar:
            radars = search_radars(radar_locations,grid_out)
            attach_radar_rings(grid_out,radars,ax)

            commonprefix = os.path.commonprefix([script_path,envfilename])
            short_envfilename = envfilename[len(commonprefix):]

            write_envfile(envfilename,radars,grid_out)
            print(f"    Wrote out environment file for radars: {color_text(short_envfilename,'cyan')}")
    #
    #-------------------------------------------------------------------
    #
    # Finally, save the images to a file and show it as well
    #
    #-------------------------------------------------------------------

    commonprefix  =  os.path.commonprefix([script_path,figname])
    short_figname = figname[len(commonprefix):]
    print(f"    Saving figure to {color_text(short_figname,'magenta')} ...")
    figure.savefig(figname, format='png')


    if args.plot:
        plt.show()
