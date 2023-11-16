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
import re, math
import argparse

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
from datetime import datetime, timedelta

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

def parse_args():
    parser = argparse.ArgumentParser(description='Plot DART obs_seq.fial sequences',
                                     epilog='''        ---- Yunheng Wang (2023-11-10).
                                            ''')
                                     #formatter_class=CustomFormatter)

    parser.add_argument('date',    help='MPAS-WoFS event date')
    parser.add_argument('obstype', help='A number denotes the observation type',type=str, default=None)

    parser.add_argument('-v','--verbose',   help='Verbose output',                              action="store_true", default=False)
    parser.add_argument('-r','--rundir',    help='MPAS-WoFS run directory',                     type=str,            default=os.getcwd())
    parser.add_argument('-o','--outfile',   help='Name of output image or output directory',    type=str,            default=None)

    args = parser.parse_args()

    parsed_args = {}

    date_re     = re.compile(r'[1-2][0-9][0-9][0-9][0-1][0-9][0-3][0-9]')
    type_re     = re.compile(r'[0-9]+')

    eventdates  = []
    obstypes    = []
    if  date_re.match(args.date):
        eventdates.append(args.date)
    elif type_re.match(args.date) or args.obstype == "list":
        obstypes.append(args.date)
    else:
        print(f"ERROR: Command line argument \"{args.date}\" is not support")
        sys.exit(1)


    if type_re.match(args.obstype) or args.obstype == "list":  # if the two arguments are out-of-order
        obstypes.append(args.obstype)
    elif date_re.match(args.obstype):
        eventdates.append(args.obstype)
    else:
        print(f"ERROR: Command line argument \"{args.obstype}\" is not support")
        sys.exit(2)

    if len(eventdates) == 1:
        parsed_args['eventdate'] = eventdates[0]
    else:
        print(f"ERROR: Can handle one event at a time. Got \"{eventdates}\"")
        sys.exit(0)

    if len(obstypes) == 1:
        parsed_args['obstype'] = obstypes[0]
    else:
        print(f"ERROR: Can only handle one observation type at at time. Got \"{obstypes}\"")
        sys.exit(0)

    if os.path.lexists(args.rundir):
         parsed_args['run_dir'] = args.rundir
    else:
        print(f"ERROR: Directory \"{args.rundir}\" does not exist.")
        sys.exit(0)

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

    return args, make_namespace(parsed_args)

########################################################################

def daterange(start_date, end_date, minutes=15):
    delminutes = int((end_date - start_date).seconds)//60+minutes
    for m in range(0,delminutes,minutes):
        yield start_date + timedelta(minutes=m)

########################################################################

def load_variables(cargs,wargs, begtime, endtime):
    ''' Load obs_seq.final sequence files'''

    var_obj = {'times':      [],
               'rms_prior':  [],
               'rms_post':   [],
               'type_label': None}

    beg_dt = datetime.strptime(f"{wargs.eventdate} {begtime}",'%Y%m%d %H%M')
    end_dt = datetime.strptime(f"{wargs.eventdate} {endtime}",'%Y%m%d %H%M')
    if int(endtime) < 1200:
        end_dt = end_dt + timedelta(days=1)

    for run_dt in daterange(beg_dt,end_dt,minutes=15):

        timestr   = run_dt.strftime("%H%M")
        timedtstr = run_dt.strftime("%Y%m%d%H%M")
        obsfile = os.path.join(wargs.run_dir,wargs.eventdate,'dacycles',timestr,f'obs_seq.{timedtstr}.nc')

        if os.path.lexists(obsfile):

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

            with Dataset(obsfile, 'r') as fh:
                varobs  = fh.variables['observations'][:,:]   # (ObsIndex, copy)

                obstype = fh.variables['obs_type'][:]
                typesMeta = fh.variables['ObsTypesMetaData'][:,:]

            nobs  = varobs.shape[0]
            typeLabel = typesMeta[int(wargs.obstype)-1,:].tobytes().decode('utf-8').strip()
        else:
            print(f"ERROR: file {obsfile} not found")
            sys.exit(1)

        # select by observation type
        #
        obs_index    = []
        for n in range(0,nobs):
            if obstype[n] == int(wargs.obstype):
                obs_index.append(n)

        nobs_type = len(obs_index)
        obs  = varobs[obs_index,0]
        prio = varobs[obs_index,1]
        post = varobs[obs_index,2]

        if cargs.verbose:
            print(f"time = {timestr}, number of obs = {nobs_type} for {typeLabel}")

        n1 = prio.count()
        rms_prior = np.sqrt(np.sum((prio-obs)**2)/n1)
        n2 = post.count()
        rms_post = np.sqrt(np.sum((post-obs)**2)/n2)
        if cargs.verbose:
            print(f"       prior = {n1} - {rms_prior}; post = {n2} - {rms_post}")

        var_obj['rms_prior'].append(rms_prior)
        var_obj['rms_post'].append(rms_post)
        var_obj['times'].append(timestr)

    var_obj['type_label'] = typeLabel

    return make_namespace(var_obj,level=1)

########################################################################

QCValMeta = { '0' : 'assim',
              '1' : 'eval only',
              '2' : 'assim, post forward fail',
              '3' : 'eval, post forward fail',
              '4' : 'prior forward fail',
              '5' : 'N/A',
              '6' : 'prior QC rejected',
              '7' : 'outlier rejected' }

def print_meta(wargs,time4str):
    ''' Output variable information in the file
    '''

    global QCValMeta

    obs_dt = datetime.strptime(f"{wargs.eventdate} {time4str}", "%Y%m%d %H%M")
    if int(time4str) < 1200:
        obs_dt = obs_dt + timedelta(days=1)

    obs_timestr = obs_dt.strftime("%Y%m%d%H%M")

    obsfile = os.path.join(wargs.run_dir,wargs.eventdate,'dacycles',time4str,f'obs_seq.{obs_timestr}.nc')

    if os.path.lexists(obsfile):

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

        with Dataset(obsfile, 'r') as fh:
            varqc   = fh.variables['qc'][:,:]             # (ObsIndex, qc_copy)
            varloc  = fh.variables['location'][:,:]
            varvert = fh.variables['which_vert'][:]

            obstype = fh.variables['obs_type'][:]
            TypesMeta = fh.variables['ObsTypesMetaData'][:,:]

            nqc_copy  = fh.dimensions['qc_copy'].size
            qccopy    = fh.variables['qc_copy'][:]
            QCMeta    = fh.variables['QCMetaData'][:,:]

            ncopy     = fh.dimensions['copy'].size
            CopyMeta  = fh.variables['CopyMetaData'][:,:]

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

        for i in range(0,nobs):
            type             = obstype[i]
            validtypes[f'{type}'] = TypesMeta[type-1,:].tobytes().decode('utf-8')

        for i in range(0,nobs):
            for j in range(0,nqc_copy):
                if varqc[i,j] not in validqcval:
                    validqcval.append(varqc[i,j])

        for i in range(0,nobs):
            if varvert[i] not in validverts:
                validverts.append(varvert[i])

        for i in range(0,nobs):
            if  varvert[i] == 2:    # ISPRESSURE
                if varloc[i,2] not in validpres:
                    validpres.append(varloc[i,2])
            elif  varvert[i] == 3:  # ISHEIGHT
                if varloc[i,2] not in validhgts:
                    validhgts.append(varloc[i,2])

        copyMeta = {}
        for k in range(0,ncopy):
            copyMeta[k+1] = CopyMeta[k,:].tobytes().decode('utf-8')

    else:
        print(f"ERROR: file {obsfile} not found")
        sys.exit(1)

    var_obj = {}
    var_obj['validqc']    = validqc      # QCMetaData
    var_obj['validtypes'] = validtypes   # ObsTypesMetaData
    var_obj['validqcval'] = validqcval   # qc, distinguis values
    var_obj['validverts'] = validverts   # which_vert, distinguis values
    var_obj['validpres']  = validpres    # location, distinguis values in 3rd dimension of location
    var_obj['validhgts']  = validhgts    # location, distinguis values in 3rd dimension of location
    var_obj['copyMeta']   = copyMeta     # CopyMetaData

    varobj = make_namespace(var_obj,level=1)

    print("Valid QCMetaData:")
    for j in varobj.validqc.keys():
        print(f"    {j}: {varobj.validqc[j]}")
    print("")

    print("Valid Observation Types:")
    for key in sorted(varobj.validtypes.keys(), key=int):
        print(f"    {key}: {varobj.validtypes[key]}")
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

def make_plot(cargs,wargs,wobj):
    ''' cargs: Command line arguments
        wargs: Decoded working arguments
        wobj:  Working object
    '''
    #-----------------------------------------------------------------------
    #
    # Plot field
    #
    #-----------------------------------------------------------------------

    figure = plt.figure(figsize = (12,12) )

    ax = figure.add_axes([0.1, 0.2, 0.8, 0.6]) # main axes

    x = []
    y = []
    i = 0
    for y1,y2 in zip(wobj.rms_prior,wobj.rms_post):
        x.extend([i,i])
        y.extend([y1,y2])
        i += 1

    ax.plot(x,y,color='r',marker='*')
    #plt.scatter(x,y,color=c, linewidth=2)
    ax.set_title(f'RMS of {wobj.type_label}')
    ax.set_xticks(x[2::4])
    ax.set_xticklabels(wobj.times[1::2], rotation = 50)
    ax.set_ylabel(wobj.type_label)


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

    if wargs.defaultoutfile:
        outpng = f"zig_{wobj.type_label}.png"
    else:
        root,ext=os.path.splitext(wargs.outfile)
        if ext != ".png":
            outpng = f"zig_{wobj.type_label}.png"
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

    cargs, wargs = parse_args()

    if wargs.obstype == "list":
        print_meta(wargs,'1530')
        sys.exit(0)
    else:
        #
        # Load variable
        #
        obs_obj = load_variables(cargs,wargs, '1515','0300')

        make_plot(cargs, wargs,obs_obj)
