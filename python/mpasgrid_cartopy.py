#!/usr/bin/env python

import os, sys
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

import argparse

#import strmrpt

########################################################################

def read_radar_location(radar_filename):

    radar_locations_dict = {}
    with open(radar_filename, 'r') as f:
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
    parser.add_argument('-radarfile'     ,help='NEXRAD radar file name',                type=str, default=None)
    parser.add_argument('-outgrid'       ,help='Plot an output grid, "True" get grid from arguments, or filename',type=str, default=False)
    parser.add_argument('-latlon'        ,help='Base map latlon or lambert',action='store_true', default=False)
    parser.add_argument('-name'          ,help='Name of the WoF grid',type=str, default="wofs_poly")

    args = parser.parse_args()

    basmap = "lambert"
    if args.latlon:
        basmap = "latlon"

    figname = f"{args.name}.{basmap}.png"

    if os.path.lexists(args.pts_file):

        with open(args.pts_file, 'r') as csvfile:
            reader = csv.reader(csvfile)
            next(reader);next(reader);next(reader);
            lonlats=[]
            for row in reader:
                lonlats.append((float(row[1]),float(row[0])))

        filename = f"{os.path.splitext(os.path.basename(args.pts_file))[0]}.png"

        figname = filename.replace("custom",basmap)
    else:
        print("ERROR: need a WoF grid file.")
        sys.exit(0)

    # Note that MPAS requires the order to be clockwise
    # Python polygon requires anti-clockwise
    lonlats.reverse()
    lonlats.append(lonlats[0])
    #print(lonlats)

    plt_hrrr = False
    if args.range == 'hrrr':
        plt_hrrr = True
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
        lats = [ l[1] for l in lonlats]
        lons = [ l[0] for l in lonlats]
        ranges = [ min(lons)-2.0, max(lons)+2.0, min(lats)-2.0, max(lats)+2.0]

    print(f"ranges = {ranges}")

    plt_outgrid = False
    if args.outgrid == "True":
        plt_outgrid = True
        nx1 = args.nx
        ny1 = args.ny
        dx1 = args.dx
        dy1 = args.dy
        ctrlon1 = args.ctrlon
        ctrlat1 = args.ctrlat
        stdlat1_1 = args.stdlat1
        stdlat1_2 = args.stdlat2
    elif os.path.lexists(args.outgrid):
        data = []
        with open(args.outgrid,'r') as f:
            for line in f:
                if line.lstrip().startswith('#'):
                    continue
                data.append(line.lstrip().rstrip())

        # reconstructing the data as a dictionary
        ogrid = ast.literal_eval(' '.join(data))

        plt_outgrid = True
        nx1       = ogrid["nx"]
        ny1       = ogrid["ny"]
        dx1       = ogrid["dx"]
        dy1       = ogrid["dy"]
        ctrlon1   = ogrid["ctrlon"]
        ctrlat1   = ogrid["ctrlat"]
        stdlat1_1 = ogrid["stdlat1"]
        stdlat1_2 = ogrid["stdlat2"]
    elif not args.outgrid:
        plt_outgrid = False
    else:
        print("ERROR: need an output grid file or command line arguments.")
        sys.exit(0)

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
    # Lambert conformal map projection for the HRRR domain
    #
    #-----------------------------------------------------------------------

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

    carr= ccrs.PlateCarree()

    proj_hrrr=ccrs.LambertConformal(central_longitude=ctrlon, central_latitude=ctrlat,
                 false_easting=xctr, false_northing= yctr,
                 standard_parallels=(stdlat1, stdlat2), globe=None)

    lonlat_sw = carr.transform_point(0.0,0.0,proj_hrrr)

    #-----------------------------------------------------------------------
    #
    # Lambert Conformal Map projection for the output domain
    #
    #-----------------------------------------------------------------------

    if plt_outgrid:

        xsize1=(nx1-1)*dx1
        ysize1=(ny1-1)*dy1

        x1d = np.linspace(0.0,xsize1,num=nx1)
        y1d = np.linspace(0.0,ysize1,num=ny1)

        #x2d1, y2d1 = np.meshgrid(x1d,y1d)

        xctr1 = (nx1-1)/2*dx1
        yctr1 = (ny1-1)/2*dy1

        proj1=ccrs.LambertConformal(central_longitude=ctrlon1, central_latitude=ctrlat1,
                     false_easting=xctr1, false_northing=yctr1,
                     standard_parallels=(args.stdlat1, args.stdlat2), globe=None)

        lonlat1 = carr.transform_point(0.0,0.0,proj1)

        if args.verbose:
          print("Write component output grid Parameters:")
          print(f"    cen_lat = {ctrlat1}, cen_lon = {ctrlon1}, stdlat1 = {stdlat1_1}, stdlat2 = {stdlat1_2}")
          print(f"    nx = {nx1}, ny = {ny1}, dx = {dx1}, dy = {dy1}")

        print('Output grid: lat1 = %f, lon1 = %f' %(lonlat1[1],lonlat1[0]))


    #-----------------------------------------------------------------------
    #
    # Main Plotting code here
    #
    #-----------------------------------------------------------------------

    figure = plt.figure(figsize = (12,12) )

    if args.latlon:
        carr._threshold = carr._threshold/10.
        ax = plt.axes(projection=carr)
        ax.set_extent(ranges,crs=carr)
    else:
        if plt_hrrr:
            ax = plt.axes(projection=proj_hrrr)
        else:
            ax = plt.axes(projection=proj1)

        ax.set_extent(ranges,crs=carr)

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
    gl.right_labels = True
    gl.bottom_labels = True


    plt.text(ctrlon,ctrlat,'o',color='r',horizontalalignment='center',
                                        verticalalignment='center',transform=carr)

    plt.title("WoF-MPAS domain")

    #-----------------------------------------------------------------------
    #
    # Plot HRRR grid outlines
    #
    #-----------------------------------------------------------------------
    if plt_hrrr:
        ax.add_patch(mpatches.Rectangle(xy=[0, 0], width=xsize, height=ysize,
                    facecolor='none',edgecolor='r',linewidth=1.0,
                    transform=proj_hrrr))

        transform2 = proj_hrrr._as_mpl_transform(ax)
        plt.annotate('HRRR Center', xy=(xctr,yctr), xycoords=transform2,
                    xytext=(-48, 24), textcoords='offset points',
                    color='r',
                    arrowprops=dict(arrowstyle="->")
                    )

        plt.text(lonlat_sw[0]+0.2,lonlat_sw[1]+0.4,'HRRR grid', color='r', transform=carr)

    #-----------------------------------------------------------------------
    #
    # Plot the WoFS domain
    #
    #-----------------------------------------------------------------------

    polygon1 = Polygon( lonlats )
    ax.add_geometries([polygon1], crs=ccrs.Geodetic(), facecolor='blue',
                      edgecolor='navy', linewidth=1.5, alpha=0.2,zorder=1)

    for lon,lat in lonlats:
        plt.text(lon, lat, '*', color='r', horizontalalignment='center',
                                           verticalalignment='center',transform=carr)

    #-----------------------------------------------------------------------
    #
    # Plot the output grid outlines
    #
    #-----------------------------------------------------------------------

    if plt_outgrid:

        ax.add_patch(mpatches.Rectangle(xy=[0, 0], width=xsize1, height=ysize1,
                                    facecolor='none',edgecolor='green',linewidth=2.0,
                                    transform=proj1))

        plt.text(ctrlon1,ctrlat1,'o',color='g',horizontalalignment='center',
                                            verticalalignment='center',transform=carr)

        transform1 = proj1._as_mpl_transform(ax)

        plt.annotate('Output Center', xy=(xctr1,yctr1), xycoords=transform1,
                        xytext=(5, 12), textcoords='offset points',
                        color='green',
                        arrowprops=dict(arrowstyle="fancy")
                        )
    #
    #-----------------------------------------------------------------------
    #
    # Plot radar rings as possible
    #
    #-----------------------------------------------------------------------
    if plt_radar and plt_outgrid:

        xextradar = 100000.0    # extend range for radar searching 140 km
        yextradar = 100000.0

        xrad1 = x1d[0]  - xextradar
        xrad2 = x1d[-1] + xextradar
        yrad1 = y1d[0]  - yextradar
        yrad2 = y1d[-1] + yextradar

        (nothing,     rad_grd_lat1) = carr.transform_point(xrad1,yrad1, src_crs=proj1)
        (rad_grd_lon1,rad_grd_lat2) = carr.transform_point(xrad1,yrad2, src_crs=proj1)
        #(rad_grd_lon3,rad_grd_lat3) = carr.transform_point(xrad2,yrad1, src_crs=proj1)
        (rad_grd_lon2,nothing     ) = carr.transform_point(xrad2,yrad2, src_crs=proj1)

        print (f'Lat/lon at the SW corner of base grid= {rad_grd_lat1}, {rad_grd_lon1}.' )
        print (f'Lat/lon at the NE corner of base grid= {rad_grd_lat2}, {rad_grd_lon2}.' )

        radars = find_radars(radar_locations,[rad_grd_lat1, rad_grd_lat2],[rad_grd_lon1,rad_grd_lon2])

        for radar, radloc in radars.items():
            circle_points = geodesic.Geodesic().circle(lon=radloc[1], lat=radloc[0], radius=150000,
                                                       n_samples=300, endpoint=False)
            geom = Polygon(circle_points)
            ax.add_geometries((geom,), crs=carr, facecolor='none', edgecolor='darkgrey', linewidth=1.0)

            plt.text(radloc[1],radloc[0],radar,horizontalalignment='center',
                     verticalalignment='center',color='purple', transform=carr)
    #
    #-------------------------------------------------------------------
    #
    # Finally, save the images to a file and show it as well
    #
    #-------------------------------------------------------------------

    print(f"Saving figure to {figname} ...")
    figure.savefig(figname, format='png')

    #plt.show()
