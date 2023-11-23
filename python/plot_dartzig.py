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
from matplotlib.ticker import IndexLocator

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

def parse_args():
    parser = argparse.ArgumentParser(description='Plot DART obs_seq.fial sequences',
                                     epilog='''        ---- Yunheng Wang (2023-11-10).
                                            ''')
                                     #formatter_class=CustomFormatter)

    parser.add_argument('date',    help='MPAS-WoFS event date')
    parser.add_argument('obstype', help='A number denotes the observation type',type=str, default=None)

    parser.add_argument('-v','--verbose',   help='Verbose output',                              action="store_true", default=False)
    parser.add_argument('-r','--rundir',    help='MPAS-WoFS run directory (no date)',                type=str,       efault=os.getcwd())
    parser.add_argument('-t','--time',      help='4-digit time string for listing the file content', type=str,       default='1700')
    parser.add_argument('-p','--parms',     help='Parameter to limit selections, [dataqc,dartqc]',   type=str,       default='10,0')
    parser.add_argument('-d','--threshold', help='Threshold for reflectivity',                       type=float,     default=None)
    parser.add_argument('-s','--spreadtype', help='1: ensemble standard deviation, 2: ensemble standard deviation + ob error ("total spread")',
                                                                                                     type=int,       default=2)
    parser.add_argument('-o','--outfile',   help='Name of output image or output directory',         type=str,       default=None)

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

    parsed_args['threshold'] = args.threshold

    if args.parms is not None:
        strlist = args.parms.split(',')
        parsed_args['dataqc'] = int(strlist[0])
        parsed_args['dartqc'] = int(strlist[1])
    else:
        parsed_args['dataqc'] = None
        parsed_args['dartqc'] = None

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

    unitLabels = {'DOPPLER_RADIAL_VELOCITY': 'm/s',
                  'RADAR_REFLECTIVITY': 'dBZ',
                  }
    var_obj = {'times':      [],
               'rms_prior':  [],
               'rms_post':   [],
               'sprd_prior':  [],
               'sprd_post':   [],
               'bias_prior':  [],
               'bias_post':   [],
               'ratio':       [],
               'obs_std':     [],
               'qc_numbers':  {},
               'type_label': None,
               'unit_label': None
            }

    beg_dt = datetime.strptime(f"{wargs.eventdate} {begtime}",'%Y%m%d %H%M')
    end_dt = datetime.strptime(f"{wargs.eventdate} {endtime}",'%Y%m%d %H%M')
    if int(endtime) < 1200:
        end_dt = end_dt + timedelta(days=1)

    numf = 0
    for run_dt in daterange(beg_dt,end_dt,minutes=15):

        timestr   = run_dt.strftime("%H%M")
        timedtstr = run_dt.strftime("%Y%m%d%H%M")
        obsfile = os.path.join(wargs.run_dir,f'obs_seq.final.{timedtstr}.nc')

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

            with Dataset(obsfile, 'r') as fh:
                varobs  = fh.variables['observations'][:,:]   # (ObsIndex, copy)
                varqc   = fh.variables['qc'][:,:]             # (ObsIndex, qc_copy)

                obstype = fh.variables['obs_type'][:]
                typesMeta = fh.variables['ObsTypesMetaData'][:,:]

            nobs      = varobs.shape[0]
            typeLabel = typesMeta[int(wargs.obstype)-1,:].tobytes().decode('utf-8').strip()
            unitLabel = unitLabels.get(typeLabel,'Undefined')
        else:
            print(f"ERROR: file {obsfile} not found")
            sys.exit(1)

        #
        # Select by observation type
        #
        obs_index = np.where( obstype == int(wargs.obstype) )[0]

        if cargs.verbose:
            print(f"Obs length after type selection: {len(obs_index)}")

        #
        # Select by threshold for reflectivity
        #
        if typeLabel == "RADAR_REFLECTIVITY" and wargs.threshold is not None:
            newindex=[]
            for index in obs_index:
                if varobs[index,0] >= wargs.threshold:
                    newindex.append(index)
            obs_index = newindex.copy()

            if cargs.verbose:
                print(f"Obs length after threshold >= {wargs.threshold} selection: {len(obs_index)}")

        nobs_type = len(obs_index)
        if nobs_type > 0:
            #
            # Check observation numbers based on qc flags, which excludes the dataqc & dartqc narrowers
            #
            typeqcs = np.unique(varqc[obs_index,1])
            uniqqcs = []
            for qval in typeqcs:
                obs_index1 = np.where(varqc[obs_index,1] == qval)[0]
                qckey = str(qval)
                if qckey in var_obj["qc_numbers"].keys():
                    var_obj["qc_numbers"][qckey].append(len(obs_index1))
                else:
                    var_obj["qc_numbers"][qckey] = [0]*numf+[len(obs_index1)]
                uniqqcs.append(qckey)

            # if some qc value not appear in this cycle
            for qckey in var_obj["qc_numbers"].keys()-uniqqcs:
               var_obj["qc_numbers"][qckey].append(0)

            numf += 1

        #
        # Select by dataqc & dartqc
        #
        if wargs.dataqc is not None:
            newindex=[]
            for index in obs_index:
                if varqc[index,0] < wargs.dataqc:
                    newindex.append(index)
            obs_index = newindex.copy()

            if cargs.verbose:
                print(f"Obs length after dataqc < {wargs.dataqc} selection: {len(obs_index)}")

        if wargs.dartqc is not None:
            newindex=[]
            for index in obs_index:
                if varqc[index,1] == wargs.dartqc:
                    newindex.append(index)
            obs_index = newindex.copy()

            if cargs.verbose:
                print(f"Obs length after dartqc == {wargs.dartqc} selection: {len(obs_index)}")

        #
        # Now, fill the ploting arrays
        #
        nobs_type = len(obs_index)
        if nobs_type > 0:
            obs  = varobs[obs_index,0]
            prio = varobs[obs_index,1]
            post = varobs[obs_index,2]
            sprd_pri = varobs[obs_index,3]
            sprd_pst = varobs[obs_index,4]
            variance = varobs[obs_index,11]

            if cargs.verbose:
                print(f"time = {timestr}, number of obs = {nobs_type} for {typeLabel}")

            # rms error
            n1 = prio.count()
            rms_prior = np.sqrt(np.sum((prio-obs)**2)/n1)
            n2 = post.count()
            rms_post = np.sqrt(np.sum((post-obs)**2)/n2)
            if cargs.verbose:
                print(f"       prior = {n1} - {rms_prior}; post = {n2} - {rms_post}")

            var_obj['rms_prior'].append( rms_prior )
            var_obj['rms_post'].append( rms_post )

            # rms ensemble spread
            n3 = sprd_pri.count()
            n4 = sprd_pst.count()
            if cargs.spreadtype == 2:
                sprd_prior = np.sqrt( variance[0] + np.sum( sprd_pri*sprd_pri )/n3 )
                sprd_post  = np.sqrt( variance[0] + np.sum( sprd_pst*sprd_pst )/n4 )
            elif cargs.spreadtype == 1:
                sprd_prior = np.sqrt( np.sum( sprd_pri*sprd_pri )/n3 )
                sprd_post  = np.sqrt( np.sum( sprd_pst*sprd_pst )/n4 )

            var_obj['sprd_prior'].append( sprd_prior )
            var_obj['sprd_post'].append(  sprd_post )

            # mean bias
            var_obj['bias_prior'].append( np.sum(obs-prio)/n1 )
            var_obj['bias_post'].append(  np.sum(obs-post)/n2 )

            # consistency ratio
            var_obj['ratio'].append( (variance[0] + (np.sum(sprd_pri*sprd_pri)/n3))/(np.sum((obs-prio)**2)/n1) )

            var_obj['obs_std'].append( np.sqrt(variance[0]) )

            var_obj['times'].append( timestr )

    var_obj['type_label'] = typeLabel
    var_obj['unit_label'] = unitLabel

    return make_namespace(var_obj,level=1)

########################################################################

#QCValMeta = { '0' : 'assim',
#              '1' : 'eval only',
#              '2' : 'assim, post forward fail',
#              '3' : 'eval, post forward fail',
#              '4' : 'prior forward fail',
#              '5' : 'N/A',
#              '6' : 'prior QC rejected',
#              '7' : 'outlier rejected' }

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

def print_meta(wargs,time4str):
    ''' Output variable information in the file
    '''

    global QCValMeta

    obs_dt = datetime.strptime(f"{wargs.eventdate} {time4str}", "%Y%m%d %H%M")
    if int(time4str) < 1200:
        obs_dt = obs_dt + timedelta(days=1)

    obs_timestr = obs_dt.strftime("%Y%m%d%H%M")

    obsfile = os.path.join(wargs.run_dir,f'obs_seq.final.{obs_timestr}.nc')

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
            CopyMetaData  = fh.variables['CopyMetaData'][:,:]

        #nobs           = varqc.shape[0]

        # go through each observations
        validqcstr     = {}
        for j in range(0,nqc_copy):
            validqcstr[f"{qccopy[j]}"] = QCMeta[j,:].tobytes().decode('utf-8')

        validtypes     = {}
        validtypevals = np.unique(obstype)
        for type in validtypevals:
            validtypes[f'{type}'] = TypesMeta[type-1,:].tobytes().decode('utf-8')

        validqcval = np.unique(varqc)

        validverts = np.unique(varvert)

        obs_pres = np.where(varvert == 2)[0]     # ISPRESSURE
        obs_hgts = np.where(varvert == 3)[0]     # ISHEIGHT
        if len(obs_pres) > 0:
            validpres = varloc[obs_pres,2]
        else:
            validpres = None

        if len(obs_hgts) > 0:
            validhgts = varloc[obs_hgts,2]
        else:
            validhgts = None

        copyMeta = {}
        for k in range(0,ncopy):
            copyMeta[str(k+1)] = CopyMetaData[k,:].tobytes().decode('utf-8')

    else:
        print(f"ERROR: file {obsfile} not found")
        sys.exit(1)

    var_obj = {}
    var_obj['validqcstr'] = validqcstr   # QCMetaData
    var_obj['validtypes'] = validtypes   # ObsTypesMetaData
    var_obj['validqcval'] = validqcval   # qc, distinguis values
    var_obj['validverts'] = validverts   # which_vert, distinguis values
    var_obj['validpres']  = validpres    # location, distinguis values in 3rd dimension of location
    var_obj['validhgts']  = validhgts    # location, distinguis values in 3rd dimension of location
    var_obj['copyMeta']   = copyMeta     # CopyMetaData

    varobj = make_namespace(var_obj,level=1)

    #-------------------------------------------------------------------
    # Retrieve QC numbers for each type

    validtypeqccount = {}
    for key in varobj.validtypes.keys():

        typeqcvals = {}
        #
        # Select obs_index by type
        #
        obs_index0 = np.where(obstype == int(key))[0]

        #
        # Select obs_index by qc flag
        #
        typeqcs = np.unique(varqc[obs_index0,1])
        for qval in typeqcs:
            obs_index1 = np.where(varqc[obs_index0,1] == qval)[0]

            typeqcvals[str(qval)] = len(obs_index1)

        validtypeqccount[key] = typeqcvals

    #-------------------------------------------------------------------
    # Print output messages

    print(f"\nobs_seq.final file: {obsfile}\n")

    print("Valid qc_copy MetaData:")
    for j in varobj.validqcstr.keys():
        print(f"    {j}: {varobj.validqcstr[j]}")
    print("")

    print("Valid Observation Types {qc: number, [qc: number]}:")
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

def plot_rms(cargs,wargs,wobj):
    ''' cargs: Command line arguments
        wargs: Decoded working arguments
        wobj:  Working object
    '''
    #-----------------------------------------------------------------------
    #
    # Plot RMS
    #
    #-----------------------------------------------------------------------

    figure = plt.figure(figsize = (12,12) )

    ax = figure.add_axes([0.1, 0.35, 0.8, 0.45])      # main axes

    # plot rmsi

    x = []
    y_rms  = []
    y_sprd = []
    y_bias = []
    i = 0
    for y1,y2 in zip(wobj.rms_prior,wobj.rms_post):
        x.extend([i,i])
        y_rms.extend([y1,y2])
        i += 1

    for y1,y2 in zip(wobj.sprd_prior,wobj.sprd_post):
        y_sprd.extend([y1,y2])

    if cargs.spreadtype == 2:
        spread_label = "total spread"
    elif cargs.spreadtype == 1:
        spread_label = "ens spread"

    for y1,y2 in zip(wobj.bias_prior,wobj.bias_post):
        y_bias.extend([y1,y2])

    ax.plot(x,y_rms,color='r',label="rmsi")
    ax.plot(x,y_sprd,color='g',label=spread_label)
    ax.plot(x,y_bias,color='b',label="Innov/Residue <obs-guess/analysis>")
    ax.plot(wobj.times,wobj.obs_std,color='k',label="Obs standard deviation")
    #ax.scatter(x[::2],y_rms[::2],color='b', marker='*',label="prior")
    #ax.scatter(x[1::2],y_rms[1::2],color='g', marker='+',label="posterior")
    ax.set_title(f'RMS of {wobj.type_label} for {wargs.eventdate} ')
    ax.set_xticks(x[0::2])
    ax.set_xticklabels(wobj.times, rotation = 50)
    ax.xaxis.set_minor_locator(IndexLocator(1,0))
    ax.xaxis.set_major_locator(IndexLocator(2,1))
    ax.set_ylabel(wobj.unit_label)
    ax.set_xlabel("Data Assimilation Cycles")
    ax.legend(loc="upper right")
    ax.xaxis.grid(True)


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
        outpng = f"rms_{wobj.type_label}_{wargs.eventdate}.png"
    else:
        root,ext=os.path.splitext(wargs.outfile)
        if ext != ".png":
            outpng = f"rms_{wobj.type_label}.png"
        else:
            outpng = wargs.outfile

    figname = os.path.join(wargs.outdir,outpng)
    print(f"Saving figure to {figname} ...")
    figure.savefig(figname, format='png', dpi=100)
    plt.close(figure)

    #plt.show()

########################################################################

def plot_qcnumbers(cargs,wargs,wobj):
    ''' cargs: Command line arguments
        wargs: Decoded working arguments
        wobj:  Working object
    '''
    #-----------------------------------------------------------------------
    #
    # Plot Numbers
    #
    #-----------------------------------------------------------------------

    figure = plt.figure(figsize = (12,12) )

    ax = figure.add_axes([0.1, 0.2, 0.8, 0.6]) # main axes

    mks = ['o', 'D', '+', '*', 's', 'x', '^', '1']
    cls = ['r', 'g', 'b', 'c', 'k', 'y', 'm', 'k']

    for j,qcval in enumerate(wobj.qc_numbers.keys()):
        ax.plot(wobj.times,wobj.qc_numbers[qcval],color=cls[j],label=QCValMeta[qcval])
        x=np.array(wobj.times)
        y=np.array(wobj.qc_numbers[qcval])
        xgt0=x[y>0]
        ygt0=y[y>0]
        ax.scatter(xgt0,ygt0,marker=mks[j],color='k')

    ax.set_title(f'Numbers of {wobj.type_label} for {wargs.eventdate} ')
    ax.set_xticks(wobj.times)
    ax.set_xticklabels(wobj.times, rotation = 50)
    ax.xaxis.set_minor_locator(IndexLocator(1,0))
    ax.xaxis.set_major_locator(IndexLocator(2,1))
    ax.set_ylabel("Number of Observations")
    ax.set_xlabel("Data Assimilation Cycles")
    ax.legend(loc="upper left")
    ax.xaxis.grid(True)

    if wargs.defaultoutfile:
        outpng = f"number_{wobj.type_label}_{wargs.eventdate}.png"
    else:
        root,ext=os.path.splitext(wargs.outfile)
        if ext != ".png":
            outpng = f"number_{wobj.type_label}.png"
        else:
            outpng = wargs.outfile

    figname = os.path.join(wargs.outdir,outpng)
    print(f"Saving figure to {figname} ...")
    figure.savefig(figname, format='png', dpi=100)
    plt.close(figure)

    #plt.show()

########################################################################

def plot_ratio(cargs,wargs,wobj):
    ''' cargs: Command line arguments
        wargs: Decoded working arguments
        wobj:  Working object
    '''
    #-----------------------------------------------------------------------
    #
    # Plot ratio
    #
    #-----------------------------------------------------------------------


    figure = plt.figure(figsize = (12,12) )

    ax = figure.add_axes([0.1, 0.3, 0.8, 0.4]) # main axes

    x = []
    y = []
    i = 0
    for y1 in wobj.ratio:
        x.extend([i])
        y.extend([y1])
        i += 1

    ax.plot(x,y,color='r')
    ax.set_title(f'Consistency Ratio of {wobj.type_label} for {wargs.eventdate} ')
    ax.set_xticks(x)
    ax.set_xticklabels(wobj.times, rotation = 50)
    ax.xaxis.set_minor_locator(IndexLocator(1,0))
    ax.xaxis.set_major_locator(IndexLocator(2,1))
    ax.set_ylabel("Consistency Ratio")
    ax.set_xlabel("Data Assimilation Cycles")
    #ax.legend(loc="upper right")
    ax.xaxis.grid(True)

    if wargs.defaultoutfile:
        outpng = f"ratio_{wobj.type_label}_{wargs.eventdate}.png"
    else:
        root,ext=os.path.splitext(wargs.outfile)
        if ext != ".png":
            outpng = f"ratio_{wobj.type_label}.png"
        else:
            outpng = wargs.outfile

    figname = os.path.join(wargs.outdir,outpng)
    print(f"Saving figure to {figname} ...")
    figure.savefig(figname, format='png', dpi=100)
    plt.close(figure)

    #plt.show()

########################################################################

def make_plot(cargs,wargs,wobj):
    ''' cargs: Command line arguments
        wargs: Decoded working arguments
        wobj:  Working object
    '''
    #-----------------------------------------------------------------------
    #
    # Plot RMS
    #
    #-----------------------------------------------------------------------

    plot_rms(cargs,wargs,wobj)

    plot_qcnumbers(cargs,wargs,wobj)

    plot_ratio(cargs,wargs,wobj)


#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#
# Main function defined to return correct sys.exit() calls
#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

if __name__ == "__main__":

    time0 = timeit.time()

    cargs, wargs = parse_args()

    if cargs.verbose: print("\n Elapsed time of parse_args is:  %f seconds" % (timeit.time() - time0))

    if wargs.obstype == "list":
        time1 = timeit.time()

        print_meta(wargs,cargs.time)

        if cargs.verbose: print("\n Elapsed time of print_meta is:  %f seconds" % (timeit.time() - time1))

        sys.exit(0)
    else:
        #
        # Load variable
        #
        time2 = timeit.time()

        obs_obj = load_variables(cargs,wargs, '1515','0300')

        if cargs.verbose: print("\n Elapsed time of load_variables is:  %f seconds" % (timeit.time() - time2))

        time3 = timeit.time()

        make_plot(cargs, wargs,obs_obj)

        if cargs.verbose: print("\n Elapsed time of make_plot is:  %f seconds" % (timeit.time() - time3))