#!/usr/bin/env python
#
from asyncore import read
import os, sys
import numpy as np

import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
from shapely.geometry.polygon import Polygon

import cartopy.crs as ccrs
import cartopy.feature as cfeature

import csv
import ast

import argparse

#import strmrpt


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
    parser.add_argument('-range'         ,help='grid rnage in degrees [lat1,lat2,lon1,lon2]',type=str, default=None)
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

    elif args.range is not None:
        rlist = [float(item) for item in args.range.split(',')]
        if len(rlist) < 4:
            print(f"-range expects 4 or more degrees as [lat1,lon1,lat2,lon2, ...].")
            sys.exit(0)
        rlist = [float(item) for item in args.range.split(',')]

        lats=rlist[0::2]
        lons=rlist[1::2]
        lonlats = list(zip(lons, lats))

        print(f"Name: {args.name}")
        print("Type: custom")
        print(f"Point: {args.ctrlon}, {args.ctrlat}")
        for lon,lat in lonlats:
            print(f"{lat}, {lon}")
        print(" ")

    else:
        print("ERROR: need a WoF grid file or range specifications.")
        sys.exit(0)

    lonlats.append(lonlats[0])

    if args.outgrid == "True":
        outgrid = True
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

        outgrid = True
        nx1       = ogrid["nx"]
        ny1       = ogrid["ny"]
        dx1       = ogrid["dx"]
        dy1       = ogrid["dy"]
        ctrlon1   = ogrid["ctrlon"]
        ctrlat1   = ogrid["ctrlat"]
        stdlat1_1 = ogrid["stdlat1"]
        stdlat1_2 = ogrid["stdlat2"]

    else:
        print("ERROR: need an output grid file or command line arguments.")
        sys.exit(0)

    #-----------------------------------------------------------------------
    #
    # Lambert grid for HRRR
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

    x2hr, y2hr = np.meshgrid(x1hr,y1hr)

    xctr = (nxhr-1)/2*dxhr
    yctr = (nyhr-1)/2*dyhr

    carr= ccrs.PlateCarree()

    proj_hrrr=ccrs.LambertConformal(central_longitude=ctrlon, central_latitude=ctrlat,
                 false_easting=xctr, false_northing= yctr, secant_latitudes=None,
                 standard_parallels=(stdlat1, stdlat2), globe=None)


    ##-----------------------------------------------------------------------
    ##
    ## Lambert grid, CLUE map projection
    ##
    ##-----------------------------------------------------------------------
    #
    #nx0 = 1799   #1301
    #ny0 = 1059    #921
    #dx0 = 3000.
    #dy0 = 3000.
    #xsize0=(nx0-1)*dx0
    #ysize0=(ny0-1)*dy0

    #x0_1d = np.linspace(0.0,xsize0,num=nx0)
    #y0_1d = np.linspace(0.0,ysize0,num=ny0)

    #x0_2d, y0_2d = np.meshgrid(x0_1d,y0_1d)

    #xctr = (nx0-1)/2*dx0
    #yctr = (ny0-1)/2*dy0

    #ctrlat0 =  38.5
    #ctrlon0 = -97.5

    #proj0=ccrs.LambertConformal(central_longitude=ctrlon0, central_latitude=ctrlat0,
    #             false_easting=xctr, false_northing= yctr, secant_latitudes=None,
    #             standard_parallels=(38.5, 38.5), globe=None)

    ##lonlat1 = carr.transform_point(0.0,0.0,proj1)
    ##
    ##print('lat1 = %f, lon1 = %f' %(lonlat1[1],lonlat1[0]))

    #-----------------------------------------------------------------------
    #
    # Lambert grid for input domain
    #
    #-----------------------------------------------------------------------

    if outgrid:

        xsize1=(nx1-1)*dx1
        ysize1=(ny1-1)*dy1

        x1d = np.linspace(0.0,xsize1,num=nx1)
        y1d = np.linspace(0.0,ysize1,num=ny1)

        x2d1, y2d1 = np.meshgrid(x1d,y1d)

        xctr1 = (nx1-1)/2*dx1
        yctr1 = (ny1-1)/2*dy1

        proj1=ccrs.LambertConformal(central_longitude=ctrlon1, central_latitude=ctrlat1,
                     false_easting=xctr1, false_northing=yctr1, secant_latitudes=None,
                     standard_parallels=(args.stdlat1, args.stdlat2), globe=None)

        lonlat1 = carr.transform_point(0.0,0.0,proj1)

        if args.verbose:
          print("Write component output grid Parameters:")
          print(f"    cen_lat = {ctrlat1}, cen_lon = {ctrlon1}, stdlat1 = {stdlat1_1}, stdlat2 = {stdlat1_2}")
          print(f"    nx = {nx1}, ny = {ny1}, dx = {dx1}, dy = {dy1}")

        print('Output grid: lat1 = %f, lon1 = %f' %(lonlat1[1],lonlat1[0]))


    #-----------------------------------------------------------------------
    #
    # Plot grids
    #
    #-----------------------------------------------------------------------

    figure = plt.figure(figsize = (12,12) )

    if args.latlon:
        carr._threshold = carr._threshold/10.
        ax = plt.axes(projection=carr)
        ax.set_extent([-135.0,-60.0,20.0,55.0],crs=carr)
    else:
        ax = plt.axes(projection=proj_hrrr)
        ax.set_extent([-125.0,-70.0,22.0,52.0],crs=carr)

    #ax.pcolormesh(glon, glat, aspect,transform=carr)
    #im = ax.contourf(x0[1:,1:], y0[1:,1:], aspect,transform=proj0)
    #plt.colorbar(im, shrink=0.3)

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
    transform2 = proj_hrrr._as_mpl_transform(ax)
    plt.annotate('HRRR Center', xy=(xctr,yctr), xycoords=transform2,
                    xytext=(-48, 24), textcoords='offset points',
                    color='r',
                    arrowprops=dict(arrowstyle="->")
                    )

    plt.title("WoF domain within HRRR grid")



    #-----------------------------------------------------------------------
    #
    # Plot original HRRR grid range
    #
    #-----------------------------------------------------------------------
    if args.latlon:
        nx, ny = x2hr.shape
        for i in range(0,nx):
            plt.text(x2hr[i,    0], y2hr[i,    0], '.', color='r', transform=proj_hrrr)
            plt.text(x2hr[i, ny-1], y2hr[i, ny-1], '.', color='r', transform=proj_hrrr)

        for j in range(0,ny):
            plt.text(x2hr[0,    j], y2hr[0,   j], '.', color='r', transform=proj_hrrr)
            plt.text(x2hr[nx-1, j], y2hr[nx-1,j], '.', color='r', transform=proj_hrrr)
    else:
        plt.plot(x2hr[:,      0], y2hr[:,     0], color='r', linewidth=0.5, transform=proj_hrrr)
        plt.plot(x2hr[:, nxhr-1], y2hr[:,nxhr-1], color='r', linewidth=0.5, transform=proj_hrrr)
        plt.plot(x2hr[0,      :], y2hr[0,     :], color='r', linewidth=0.5, transform=proj_hrrr)
        plt.plot(x2hr[nyhr-1, :], y2hr[nyhr-1,:], color='r', linewidth=0.5, transform=proj_hrrr)

    plt.text(x2hr[30,30],y2hr[30,30],'HRRR grid', color='r', transform=proj_hrrr)

    #-----------------------------------------------------------------------
    #
    # plot CLUE grid
    #
    #-----------------------------------------------------------------------

    #if args.latlon:
    #    nx, ny = x0_2d.shape
    #    for i in range(0,nx):
    #        plt.text(x0_2d[i,    0], y0_2d[i,    0], '.', color='g', transform=proj0)
    #        plt.text(x0_2d[i, ny-1], y0_2d[i, ny-1], '.', color='g', transform=proj0)

    #    for j in range(0,ny):
    #        plt.text(x0_2d[0,    j], y0_2d[0,   j], '.', color='g', transform=proj0)
    #        plt.text(x0_2d[nx-1, j], y0_2d[nx-1,j], '.', color='g', transform=proj0)
    #else:
    #    plt.plot(x0_2d[:,     0], y0_2d[:,    0], color='g', linewidth=1.0, transform=proj0)
    #    plt.plot(x0_2d[:, nx0-1], y0_2d[:,nx0-1], color='g', linewidth=1.0, transform=proj0)
    #    plt.plot(x0_2d[0,     :], y0_2d[0,    :], color='g', linewidth=1.0, transform=proj0)
    #    plt.plot(x0_2d[ny0-1, :], y0_2d[ny0-1,:], color='g', linewidth=1.0, transform=proj0)
    #plt.text(x0_2d[ny0-40,nx0-240],y0_2d[ny0-40,nx0-240],'CLUE grid',color='g', transform=proj0)

    #plt.annotate('CLUE SW corner', xy=(0.0,0.0),  xycoords='data',
    #                xytext=(24, 2), textcoords='offset points',
    #                color='r',
    #                arrowprops=dict(arrowstyle="fancy", color='r')
    #                )

    #-----------------------------------------------------------------------
    #
    # plot WoFS grid
    #
    #-----------------------------------------------------------------------

    if args.latlon:
        polygon1 = Polygon( lonlats )
        ax.add_geometries([polygon1], crs=ccrs.Geodetic(), facecolor='w', edgecolor='b', alpha=0.6,zorder=0)
    else:

        lon0,lat0 = lonlats[0]
        for lon,lat in lonlats[1:]:
            #plt.plot([lon0, lon], [lat0, lat], color='blue',  transform=carr)
            plt.plot([lon0, lon], [lat0, lat], color='blue',  transform=ccrs.Geodetic())
            lon0,lat0 = lon,lat

        #tension = 300
        #px0 = lonlats[0][0]
        #py0 = lonlats[0][1]
        #lat1d = np.zeros(len(lonlats)*tension)
        #lon1d = np.zeros(len(lonlats)*tension)
        #k = 0
        #for px,py in lonlats[1:]:
        #    lat1d[k:tension+k] = np.linspace(py0,py,num=tension)
        #    lon1d[k:tension+k] = np.linspace(px0,px,num=tension)
        #    px0 = px
        #    py0 = py
        #    k += tension

        #for x,y in zip(lon1d,lat1d):
        #    plt.text(x, y, '.', color='blue', horizontalalignment='center',
        #                verticalalignment='bottom',transform=carr)

    for lon,lat in lonlats:
        plt.text(lon, lat, '*', color='r', horizontalalignment='center',
                                           verticalalignment='center',transform=carr)


    #ctrlat1 = (rlist[0]+rlist[1])/2.0
    #ctrlon1 = (rlist[2]+rlist[3])/2.0

    #plt.plot(lon2d[:,   0], lat2d[:,  0], color='blue', linewidth=1.5,transform=carr)
    #plt.plot(lon2d[:, 299], lat2d[:,299], color='blue', linewidth=1.5,transform=carr)
    #plt.plot(lon2d[0,   :], lat2d[0,  :], color='blue', linewidth=1.5,transform=carr)
    #plt.plot(lon2d[299, :], lat2d[299,:], color='blue', linewidth=1.5,transform=carr)
    #plt.text(lon2d[260,20], lat2d[260,20],'WoF grid',color='blue',transform=carr)


    #plt.text(ctrlon1,ctrlat1,'o',color='g',horizontalalignment='center',
    #                                    verticalalignment='center',transform=carr)
    #
    #transform1 = carr._as_mpl_transform(ax)
    #
    #plt.annotate('WoF Center', xy=(ctrlon1,ctrlat1), xycoords=transform1,
    #                xytext=(5, 12), textcoords='offset points',
    #                color='g',
    #                arrowprops=dict(arrowstyle="->")
    #                )
    #

    #-----------------------------------------------------------------------
    #
    # plot new output Lambert grid
    #
    #-----------------------------------------------------------------------

    if outgrid:
        if args.latlon:
            for i in range(0,ny1):
                plt.text(x2d1[i,     0], y2d1[i,     0], '.', color='g', transform=proj1)
                plt.text(x2d1[i, nx1-1], y2d1[i, nx1-1], '.', color='g', transform=proj1)

            for j in range(0,nx1):
                plt.text(x2d1[0,     j], y2d1[0,    j], '.', color='g', transform=proj1)
                plt.text(x2d1[ny1-1, j], y2d1[ny1-1,j], '.', color='g', transform=proj1)
        else:
            plt.plot(x2d1[:,     0], y2d1[:,    0], color='g', linewidth=1.5,transform=proj1)
            plt.plot(x2d1[:, nx1-1], y2d1[:,nx1-1], color='g', linewidth=1.5,transform=proj1)
            plt.plot(x2d1[0,     :], y2d1[0,    :], color='g', linewidth=1.5,transform=proj1)
            plt.plot(x2d1[ny1-1, :], y2d1[ny1-1,:], color='g', linewidth=1.5,transform=proj1)
            plt.text(x2d1[ny1-40,20],y2d1[ny1-40,20],'Output grid',color='g',transform=proj1)

        plt.text(ctrlon1,ctrlat1,'o',color='g',horizontalalignment='center',
                                            verticalalignment='center',transform=carr)

        transform1 = proj1._as_mpl_transform(ax)

        plt.annotate('Output Center', xy=(xctr1,yctr1), xycoords=transform1,
                        xytext=(5, 12), textcoords='offset points',
                        color='green',
                        arrowprops=dict(arrowstyle="fancy")
                        )
        #print('Output grid: ctrlat1 = %f, ctrlon1 = %f' %(ctrlat1,ctrlon1))
    #
    print(f"Saving figure to {figname} ...")
    figure.savefig(figname, format='png')

    plt.show()
