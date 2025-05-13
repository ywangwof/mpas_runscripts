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
#import math
import argparse

import numpy as np

import matplotlib.pyplot as plt

from netCDF4 import Dataset
from datetime import datetime, timedelta
from matplotlib.ticker import IndexLocator, AutoLocator, MultipleLocator # AutoMinorLocator, LinearLocator

import time as timeit
import copy

#
# By default matplotlib will try to open a display windows of the plot, even
# though sometimes we just want to save a plot. Somtimes this can cause the
# program to crash if the display can't open. The two commands below makes it so
# matplotlib doesn't try to open a window
#
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

def parse_args():
    parser = argparse.ArgumentParser(description='Plot DART obs_seq.fial sequences from the WoFS data assimilation cycles',
                                     epilog="        ---- Yunheng Wang (2023-11-10).\n ",
                                     formatter_class=argparse.RawTextHelpFormatter)

    parser.add_argument('date',
                        help='MPAS-WoFS event date.',
                        type=str, nargs='?',default=None)

    parser.add_argument('obstype',
                        help='An integer number that denotes the observation type or a list of comma-separated numbers,\n'
                             'or None to plot all observation types in the file.\n'
                             'Use "list" to display the contents of the sequence file.',
                        type=str, nargs='?',default=None)

    parser.add_argument('-v','--verbose',   help='Verbose output.\n ',
                        action="store_true",    default=False)

    parser.add_argument('-d','--rundir',
                        help='Directory contains obs_seq.final files in netCDF format.\n'
                             '{run_dirs} or {run_dirs}/YYYYMMDD (default: dacycles/)\n'
                             'or {run_dirs}/YYYYMMDD/dacycles_{xxx} or {run_dirs}/YYYYMMDD/dacycles_{xxx}/obs_diag.\n'
                             'Default: ./',
                        type=str,   default=os.getcwd())

    parser.add_argument('-f','--filename',
                        help='File name (obs_seq.final) to list its content',
                        type=str,   default=None)

    parser.add_argument('-e','--endtime',   help='End time string as HHMM.\n ',
                        type=str,   default="0300")

    parser.add_argument('-p','--parms',
                        help='Filter observations by QC flags, [dataqc,dartqc]\n'
                             'observations QC[:,0] < dataqc and QC[:,1] == dartqc',
                        type=str,   default='10,0')

    parser.add_argument('-t','--threshold', help='Filter reflectivity by threshold (>= threshold)',
                        type=float, default=None)

    parser.add_argument('-s','--spreadtype',
                        help='1: ensemble standard deviation, \n'
                             '2: ensemble standard deviation + ob error ("total spread")\n'
                             #3: ensemble standard deviation + ob error (use average value)'''
                             'Default: 2.\n ',
                        type=int,   default=2)

    parser.add_argument('-u','--variance',
                        help='Filter observations by variance (default: False).',
                        action="store_true",    default=False)

    parser.add_argument('-o','--outfile',
                        help='Specify the name of output image or an output directory (default: ./).',
                        type=str,   default=None)

    parser.add_argument('-r','--resolution',
                        help='Set the resolution of the output image (default: 100).',
                        type=int,   default=100)

    args = parser.parse_args()

    parsed_args = {}

    date_re     = re.compile(r'[1-2][0-9][0-9][0-9][0-1][0-9][0-3][0-9]')
    type_re     = re.compile(r'[0-9]+')

    eventdates  = []
    obstypes    = []
    if args.date is None:
        pass
    elif  date_re.match(args.date):
        eventdates.append(args.date)
    elif type_re.match(args.date):
        obstypes.append(args.date)
    elif args.date == "list":
        obstypes.append(args.date)
    else:
        print(f"ERROR: Command line argument \"{args.date}\" is not support")
        sys.exit(1)

    if args.obstype is None:
        pass
    elif type_re.match(args.obstype) or args.obstype == "list":  # if the two arguments are out-of-order
        obstypes.append(args.obstype)
    elif date_re.match(args.obstype):
        eventdates.append(args.obstype)
    else:
        print(f"ERROR: Command line argument \"{args.obstype}\" is not support")
        sys.exit(2)

    if len(eventdates) == 1:
        parsed_args['eventdate'] = eventdates[0]
    elif len(eventdates) == 0:
        mobj = date_re.search(args.rundir)
        if mobj:
            parsed_args['eventdate'] = mobj.group(0)
        else:
            print(f"ERROR: Need one event date string as parameter. Got \"{eventdates}\"")
            sys.exit(0)

    if len(obstypes) == 1:
        parsed_args['obstype'] = obstypes[0].split(',')
    elif len(obstypes) == 0:
        parsed_args['obstype'] = None
    else:
        print(f"ERROR: Can only handle one observation type at at time. Got \"{obstypes}\"")
        sys.exit(0)

    if args.variance is not None:
        parsed_args['variance'] = args.variance

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
    parsed_args['outresolution']  = args.resolution

    return args, make_namespace(parsed_args)

########################################################################

def daterange(start_date, end_date, minutes=15):
    delminutes = int((end_date - start_date).seconds)//60+minutes
    for m in range(0,delminutes,minutes):
        yield start_date + timedelta(minutes=m)

########################################################################

def obsObj_init(numfile,timelist):

    var_objtmp = { 'times':    [],
                'rms_prior':   [],
                'rms_post':    [],
                'sprd_prior':  [],
                'sprd_post':   [],
                'bias_prior':  [],
                'bias_post':   [],
                'ratio':       [],
                'obs_std':     [],
                'obs_numbers': [],
                'qc_numbers':  {},
                'type_label':  None,
                'unit_label':  None,
                'numfile':     0
    }

    for i in range(numfile):
        var_objtmp['times'].append(timelist[i])
        var_objtmp['rms_prior'].append(0)
        var_objtmp['rms_post'].append(0)
        var_objtmp['sprd_prior'].append(0)
        var_objtmp['sprd_post'].append(0)
        var_objtmp['bias_prior'].append(0)
        var_objtmp['bias_post'].append(0)
        var_objtmp['ratio'].append(0)
        var_objtmp['obs_std'].append(0)
        var_objtmp['obs_numbers'].append(0)

    return var_objtmp

########################################################################

def load_variables(cargs,wargs, filelist):
    """ Load obs_seq.final sequence files """

    #begtime = timestrlist[0]
    #endtime = timestrlist[-1]

    #intvlmin = int(timestrlist[1])-int(begtime)

    unitLabels = {'DOPPLER_RADIAL_VELOCITY'    : 'm/s',
                  'RADAR_REFLECTIVITY'         : 'dBZ',
                  'AIRCRAFT_U_WIND_COMPONENT'  : 'm/s',
                  'AIRCRAFT_V_WIND_COMPONENT'  : 'm/s',
                  'AIRCRAFT_TEMPERATURE'       : 'K',
                  'ACARS_U_WIND_COMPONENT'     : 'm/s',
                  'ACARS_V_WIND_COMPONENT'     : 'm/s',
                  'ACARS_TEMPERATURE'          : 'K',
                  'MARINE_SFC_U_WIND_COMPONENT': 'm/s',
                  'MARINE_SFC_V_WIND_COMPONENT': 'm/s',
                  'MARINE_SFC_TEMPERATURE'     : 'K',
                  'MARINE_SFC_ALTIMETER'       : 'Pascal',
                  'METAR_ALTIMETER'            : 'Pascal',
                  'METAR_U_10_METER_WIND'      : 'm/s',
                  'METAR_V_10_METER_WIND'      : 'm/s',
                  'METAR_TEMPERATURE_2_METER'  : 'K',
                  'METAR_DEWPOINT_2_METER'     : 'K',
                  'RADAR_CLEARAIR_REFLECTIVITY': 'dBZ',
                  #'GOES_LWP_PATH'              :
                  #'GOES_IWP_PATH'              :
                  #'GOES_CWP_ZERO'              :
                  }

    types15mins = { 119: 'DOPPLER_RADIAL_VELOCITY',
                    120: 'RADAR_REFLECTIVITY',
                    121: 'RADAR_CLEARAIR_REFLECTIVITY',
                    124: 'GOES_LWP_PATH',
                    125: 'GOES_IWP_PATH',
                    126: 'GOES_CWP_ZERO',
                    127: 'GOES_LWP_NIGHT',
                    128: 'GOES_IWP_NIGHT',
                    130: 'GOES_CWP_ZERO_NIGHT',
                     25: 'LAND_SFC_U_WIND_COMPONENT',
                     26: 'LAND_SFC_V_WIND_COMPONENT',
                     27: 'LAND_SFC_TEMPERATURE',
                     28: 'LAND_SFC_SPECIFIC_HUMIDITY',
                     43: 'LAND_SFC_ALTIMETER',
                     98: 'LAND_SFC_RELATIVE_HUMIDITY',
                    118: 'LAND_SFC_DEWPOINT',
                    229: 'GOES_16_ABI_TB'    }

    #beg_dt = datetime.strptime(f"{wargs.eventdate} {begtime}",'%Y%m%d %H%M')
    #end_dt = datetime.strptime(f"{wargs.eventdate} {endtime}",'%Y%m%d %H%M')
    #if int(endtime) < 1200:
    #    end_dt = end_dt + timedelta(days=1)

    if wargs.obstype is not None:
        obstypes = [int(t) for t in wargs.obstype]
    else:
        obstypes = []

    var_objs = {}; num15min = 0; num1hr = 0
    times_15min = []; times_1hour = []; type_Labels = {}; unit_Labels = {}
    for obsfile in filelist:

        #timestr   = run_dt.strftime("%H%M")
        #timedtstr = run_dt.strftime("%Y%m%d%H%M")
        #obsfile = os.path.join(wargs.run_dir,f'obs_seq.final.{timedtstr}.nc')
        rematch = re.search('[12][0-9][0-9][0-9][01][0-9][0-3][0-9]([0-2][0-9])([0-5][05])',obsfile)
        timestr   = f"{rematch.group(1)}:{rematch.group(2)}"

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

            if cargs.verbose: print(f"\ntime = {timestr}, Reading file: {obsfile} .....")

            with Dataset(obsfile, 'r') as fh:
                varobs  = fh.variables['observations'][:,:]   # (ObsIndex, copy)
                varqc   = fh.variables['qc'][:,:]             # (ObsIndex, qc_copy)

                varobstypes  = fh.variables['obs_type'][:]
                vartypesMeta = fh.variables['ObsTypesMetaData'][:,:]
                copyMetaData = fh.variables['CopyMetaData'][:,:]
                ncopy        = fh.dimensions['copy'].size

        else:
            print(f"ERROR: file {obsfile} not found")
            sys.exit(1)

        #nobs      = varobs.shape[0]

        #
        # find the variance index from CopyMetaData
        #
        variance_str = "observation error variance"
        #copystrs     = []
        ivariance    = None
        for k in range(ncopy):
            copy_str = copyMetaData[k,:].tobytes().decode('utf-8')
            #copystrs.append(copy_str)
            if  copy_str.strip() == variance_str:
                ivariance = k
                break

        if ivariance is None:
            print(f"ERROR: Cannot find copy for variance.")
            sys.exit(1)

        if cargs.verbose: print(f"              observation error variance is the {ivariance}th copy")

        #
        # remember newly appear observation type for its label & unit
        #
        for otype in np.unique(varobstypes).astype(int):
            if otype not in type_Labels.keys():
                t_label = vartypesMeta[otype-1,:].tobytes().decode('utf-8').strip()
                type_Labels[otype] = t_label
                unit_Labels[otype] = unitLabels.get(t_label,'Undefined')

        #
        # Remember the file number for 150-min interval and 1 hour interval individually
        #
        num15min += 1
        times_15min.append(timestr)
        if int(timestr[3:5]) == 0 :
            num1hr += 1
            times_1hour.append(timestr)

        #
        # Set go through observation types in the file if it is not set from the command line
        #
        if wargs.obstype is None:
            obstypes = np.append(obstypes,varobstypes)
            obstypes = np.unique(obstypes).astype(int)
            #print(f"obstypes={obstypes}")

        numvar=0
        for otype in obstypes:

            if otype not in np.unique(varobstypes):    # This obs type not in this file
                if int(timestr[3:5]) > 0:              # not at exact hour
                    if otype not in types15mins.keys():
                        continue

            if otype in types15mins:
                numfile = num15min-1
                time_Labels = times_15min
            else:
                numfile = num1hr-1
                time_Labels = times_1hour

            print(f"\n          {numvar:2d}: Processing {type_Labels[otype]} ....")

            #
            # Select by observation type and skip unused observation types
            #
            obs_index = np.where( varobstypes == otype )[0]

            if cargs.verbose: print(f"              Obs length after type selection: {len(obs_index)}")

            i=0
            for ind in obs_index:
                if varqc[ind,1] == 0:  i+=1        # This observation is used

            #
            # Initialize return object for this type of osbervation
            #
            if str(otype) in var_objs.keys():
                var_obj = var_objs[str(otype)]
            else:
                var_obj = obsObj_init(numfile,time_Labels)
                var_objs[str(otype)] = var_obj

            var_obj['type_label'] = type_Labels[otype]
            var_obj['unit_label'] = unit_Labels[otype]
            var_obj['numfile']    = numfile + 1

            #
            # Select by threshold for reflectivity only
            #
            if var_obj['type_label'] == "RADAR_REFLECTIVITY" and wargs.threshold is not None:
                newindex=[]
                for index in obs_index:
                    if varobs[index,0] >= wargs.threshold:
                        newindex.append(index)
                obs_index = newindex.copy()

                if cargs.verbose: print(f"              Obs length after threshold >= {wargs.threshold} selection: {len(obs_index)}")

            #
            # Check observation numbers based on qc flags, which should be done before the dataqc & dartqc narrowers
            #
            nobs_type = len(obs_index)

            if nobs_type > 0:
                typeqcs = np.unique(varqc[obs_index,1])
                uniqqcs = []
                for qval in typeqcs:
                    obs_index1 = np.where(varqc[obs_index,1] == qval)[0]
                    qckey = str(qval)
                    if qckey in var_obj["qc_numbers"].keys():
                        var_obj["qc_numbers"][qckey].append(len(obs_index1))
                    else:
                        var_obj["qc_numbers"][qckey] = [0]*numfile+[len(obs_index1)]
                    uniqqcs.append(qckey)

                # if some qc value not appear in this cycle
                for qckey in var_obj["qc_numbers"].keys()-uniqqcs:
                   var_obj["qc_numbers"][qckey].append(0)

            else:
                for qckey in var_obj["qc_numbers"].keys():
                    var_obj["qc_numbers"][qckey].append(0)

            #
            # Select by dataqc & dartqc
            #
            if wargs.dataqc is not None:
                newindex=[]
                for index in obs_index:
                    if varqc[index,0] < wargs.dataqc:
                        newindex.append(index)
                obs_index = newindex.copy()

                if cargs.verbose: print(f"              Obs length after dataqc < {wargs.dataqc} selection: {len(obs_index)}")

            if wargs.dartqc is not None:
                newindex=[]
                for index in obs_index:
                    if varqc[index,1] == wargs.dartqc:
                        newindex.append(index)
                obs_index = newindex.copy()

                if cargs.verbose: print(f"              Obs length after dartqc == {wargs.dartqc} selection: {len(obs_index)}")
            #
            # Select by variance
            #
            if wargs.variance and len(obs_index) > 0:
                variance = varobs[obs_index,ivariance]
                min_var = variance.min()
                max_var = variance.max()
                if "DEWPOINT" in var_obj['type_label']:
                    var_threshold = 4.0*min_var
                else:
                    var_threshold = min_var

                if cargs.verbose: print(f"              index variance: {ivariance}, min value = {min_var}, max values = {max_var}, threshold = {var_threshold}")

                newindex=[]
                for index in obs_index:
                    mvariance = varobs[index,ivariance]
                    if mvariance <= var_threshold:
                        newindex.append(index)
                obs_index = newindex.copy()

                if cargs.verbose: print(f"              Obs length after selecting minimum variance {min_var}/{var_threshold}: {len(obs_index)}")

            #
            # Now, fill the derived arrays
            #
            nobs_type = len(obs_index)
            if nobs_type > 0:
                obs      = varobs[obs_index,0]
                prio     = varobs[obs_index,1]
                post     = varobs[obs_index,2]
                sprd_pri = varobs[obs_index,3]
                sprd_pst = varobs[obs_index,4]
                variance = varobs[obs_index,ivariance]

                #if cargs.verbose: print(f"              index variance: {ivariance}, value: {variance[0:3]}")

                variance = np.mean(variance)   # use minimum to exclude the boundary effects

                var_obj['obs_numbers'].append( nobs_type )
                # rms error
                n1 = prio.count()
                rms_prior = np.sqrt(np.sum((prio-obs)**2)/n1)
                n2 = post.count()
                rms_post = np.sqrt(np.sum((post-obs)**2)/n2)
                if cargs.verbose: print(f"              prior = {n1} - {rms_prior}; post = {n2} - {rms_post}")

                var_obj['rms_prior'].append( rms_prior )
                var_obj['rms_post'].append( rms_post )

                # rms ensemble spread
                n3 = sprd_pri.count()
                n4 = sprd_pst.count()
                if cargs.spreadtype in (2,3):
                    #total spread: (modified to account for non-constant obs error)
                    #sprd_prior = np.sqrt( variance[0] + np.sum( sprd_pri*sprd_pri )/n3 )
                    #sprd_post  = np.sqrt( variance[0] + np.sum( sprd_pst*sprd_pst )/n4 )

                    sprd_prior = np.sqrt( np.sum( variance+(sprd_pri*sprd_pri) )/n3)
                    sprd_post  = np.sqrt( np.sum( variance+(sprd_pst*sprd_pst) )/n4)

                elif cargs.spreadtype == 1:
                    sprd_prior = np.sqrt( np.sum( sprd_pri*sprd_pri )/n3 )
                    sprd_post  = np.sqrt( np.sum( sprd_pst*sprd_pst )/n4 )

                var_obj['sprd_prior'].append( sprd_prior )
                var_obj['sprd_post'].append(  sprd_post )

                # mean bias
                var_obj['bias_prior'].append( np.sum(obs-prio)/n1 )
                var_obj['bias_post'].append(  np.sum(obs-post)/n2 )

                # consistency ratio (modified to account for non-constant obs error)
                var_obj['ratio'].append(  (np.sum( variance+(sprd_pri*sprd_pri) )/ n3 ) /(np.sum((obs-prio)**2)/n1) )

                #var_obj['obs_std'].append( np.sqrt(variance[0]) )
                #if cargs.spreadtype in (1, 2) :
                #Output minimum value
                var_obj['obs_std'].append( np.sqrt(variance) )
                #elif cargs.spreadtype == 3 :
                #    #Output mean value
                #    var_obj['obs_std'].append( np.sqrt(np.mean(variance)) )

            else:
                var_obj['rms_prior'].append( 0 )
                var_obj['rms_post'].append( 0 )
                var_obj['sprd_prior'].append( 0 )
                var_obj['sprd_post'].append(  0 )
                var_obj['bias_prior'].append( 0 )
                var_obj['bias_post'].append(  0 )
                var_obj['ratio'].append( 0 )
                var_obj['obs_std'].append( 0 )
                var_obj['obs_numbers'].append( 0 )

            print(f"              Processed {nobs_type} observations.")
            var_obj['times'].append( timestr )
            numvar+=1


    #print(f"qc_numbers: {var_obj['qc_numbers']}")

    # finally, make the return objects a set of namespaces
    for otype in var_objs.keys():
        var_objs[otype] = make_namespace(var_objs[otype],level=1)

    return var_objs

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
              '8' : 'vertical location conversion failed',
              '10': 'Inlier threshold test failed',
              '14': 'Unknown'
            }

def print_meta(wargs,obsfile):
    """ Output variable information in the file
    """

    global QCValMeta

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

    print(f"Valid QC values: {sorted(varobj.validqcval, key=int)} and meanings")
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

    print(f"Valid vertical coordinates are: {sorted(varobj.validverts, key=int)} and meanings")
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
    """ cargs: Command line arguments
        wargs: Decoded working arguments
        wobj:  Working object
    """
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

    #print(y_sprd)
    #print(y_bias)
    #print(wobj.obs_std)

    ax.plot(x,y_rms,color='r',label="rmsi")
    ax.plot(x,y_sprd,color='g',label=spread_label)
    ax.plot(x,y_bias,color='b',label="Innov/Residue <obs-guess/analysis>")
    ax.plot(wobj.times,wobj.obs_std,color='k',label="Obs standard deviation")
    #ax.scatter(x[::2],y_rms[::2],color='b', marker='*',label="prior")
    #ax.scatter(x[1::2],y_rms[1::2],color='g', marker='+',label="posterior")
    ax.set_title(f'RMS of {wobj.type_label} for {wargs.eventdate} ')
    ax.set_xticks(x[0::2])
    ax.set_xticklabels(wobj.times, rotation = 50)
    if len(wobj.times) > 40:
        ax.xaxis.set_minor_locator(IndexLocator(1,1))
        ax.xaxis.set_major_locator(IndexLocator(4,0))
    ax.yaxis.set_minor_locator(MultipleLocator(1))
    ax.yaxis.set_major_locator(AutoLocator())
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
    print(f"    Saving figure to {figname} ...")
    figure.savefig(figname, format='png', dpi=wargs.outresolution)
    plt.close(figure)

    #plt.show()

########################################################################

def plot_qcnumbers(cargs,wargs,wobj):
    """ cargs: Command line arguments
        wargs: Decoded working arguments
        wobj:  Working object
    """
    #-----------------------------------------------------------------------
    #
    # Plot Numbers
    #
    #-----------------------------------------------------------------------

    figure = plt.figure(figsize = (12,12) )

    ax = figure.add_axes([0.1, 0.2, 0.8, 0.6])       # main axes

    mks = ['o', 'D', '+', '*', 's', 'x', '^', '1']
    cls = ['g', 'r', 'b', 'c', 'k', 'y', 'm', 'k']

    qc_vals = sorted(wobj.qc_numbers.keys(), key=int)
    #print(f"qc_vals = {qc_vals}")

    for j,qcval in enumerate(qc_vals):
        ax.plot(wobj.times,wobj.qc_numbers[qcval],color=cls[j],label=QCValMeta[qcval])
        x=np.array(wobj.times)
        y=np.array(wobj.qc_numbers[qcval])
        xgt0=x[y>0]
        ygt0=y[y>0]
        ax.scatter(xgt0,ygt0,marker=mks[j],color='k')

    #print(f"Ploting {wobj.type_label} - {wobj.times} -> {wobj.obs_numbers}")
    ax.plot(wobj.times,wobj.obs_numbers,color='k',label="observations within domain")

    ax.set_title(f'Numbers of {wobj.type_label} for {wargs.eventdate} ')
    ax.set_xticks(wobj.times)
    ax.set_xticklabels(wobj.times, rotation = 50)
    if len(wobj.times) > 40:
        ax.xaxis.set_minor_locator(IndexLocator(1,1))
        ax.xaxis.set_major_locator(IndexLocator(4,0))
    ax.set_ylabel("Number of Observations")
    ax.set_xlabel("Data Assimilation Cycles")
    #ax.legend(loc="upper left")
    ax.legend()
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
    print(f"    Saving figure to {figname} ...")
    figure.savefig(figname, format='png', dpi=wargs.outresolution)
    plt.close(figure)

    #plt.show()

########################################################################

def plot_ratio(cargs,wargs,wobj):
    """ cargs: Command line arguments
        wargs: Decoded working arguments
        wobj:  Working object
    """
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

    #print(f"wobj.type_label: x={wobj.times}, y={y}")
    ax.plot(x,y,color='r')
    ax.set_title(f'Consistency Ratio of {wobj.type_label} for {wargs.eventdate} ')
    ax.set_xticks(x)
    ax.set_xticklabels(wobj.times, rotation = 50)
    if len(wobj.times) > 40:
        ax.xaxis.set_minor_locator(IndexLocator(1,1))
        ax.xaxis.set_major_locator(IndexLocator(4,0))
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
    print(f"    Saving figure to {figname} ...")
    figure.savefig(figname, format='png', dpi=wargs.outresolution)
    plt.close(figure)

    #plt.show()

########################################################################

def make_plot(cargs,wargs,wobj):
    """ cargs: Command line arguments
        wargs: Decoded working arguments
        wobj:  Working object
    """
    #-----------------------------------------------------------------------
    #
    # Plot RMS
    #
    #-----------------------------------------------------------------------

    print(f"    Ploting RMS for {wobj.type_label} ....")
    plot_rms(cargs,wargs,wobj)

    print(f"    Ploting Observation Numbers for {wobj.type_label} ....")
    plot_qcnumbers(cargs,wargs,wobj)

    print(f"    Ploting Consistent Ratio of {wobj.type_label} ....")
    plot_ratio(cargs,wargs,wobj)


#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#
# Main function defined to return correct sys.exit() calls
#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

if __name__ == "__main__":

    date_re     = re.compile(r'[1-2][0-9][0-9][0-9][0-1][0-9][0-3][0-9]')

    time0 = timeit.time()

    cargs, wargs = parse_args()

    # Retreive a flexible Data Assimilation runtime directory based on
    # the argument run_dir

    #dadir = os.path.join(wargs.run_dir,f"{wargs.eventdate}","dacycles")
    lastname = os.path.basename(os.path.normpath(wargs.run_dir))
    #print(f"lastname = {lastname}")
    if lastname == "obs_diag":
        dadir = os.path.dirname(wargs.run_dir)
    elif 'dacycles' in lastname:
        dadir = wargs.run_dir
    else:
        mobj = date_re.search(wargs.run_dir)
        if mobj:
            dadir = os.path.join(wargs.run_dir,"dacycles")
        else:
            dadir = os.path.join(wargs.run_dir,f"{wargs.eventdate}","dacycles")

    #if cargs.verbose: print("\n Elapsed time of parse_args is:  %f seconds" % (timeit.time() - time0))

    if wargs.obstype is not None and wargs.obstype[0] == "list":
        time1 = timeit.time()

        if cargs.filename is None:
            filename = os.path.join(dadir, '1700', f"obs_seq.final.{wargs.eventdate}1700.nc")
        else:
            filename = cargs.filename

        print(f"Filename: {filename}")

        print_meta(wargs,filename)

        if cargs.verbose: print("\n Elapsed time of print_meta is:  %f seconds" % (timeit.time() - time1))

        sys.exit(0)
    else:
        #
        # Load variable
        #
        time2 = timeit.time()

        dt1 = datetime.strptime(f"{wargs.eventdate}",'%Y%m%d')
        dt2 = dt1 + timedelta(days=1)
        nextdatestr = dt2.strftime('%Y%m%d')

        #filelist1 = []; filelist2 = []
        #filelist  = []
        #print(f"Reading obs_seq files from {dadir} ...")
        #for item in os.listdir(dadir):
        #    dirmatch = re.match('^\d{4,4}$',item)
        #    dirtime = os.path.join(dadir,item)
        #    if dirmatch and os.path.isdir(dirtime):
        #        for myf in os.listdir(dirtime):
        #            rematch1 = re.match(f'obs_seq.final.{wargs.eventdate}([12][0-9][0-5][05]).nc',myf)
        #            rematch2 = re.match(f'obs_seq.final.{nextdatestr}(0[0-9][0-5][05]).nc',myf)
        #            if rematch1:
        #                filelist1.append(os.path.join(dirtime,rematch1.group(0)))
        #            elif rematch2:
        #                filelist2.append(os.path.join(dirtime,rematch2.group(0)))
        #filelist1.sort()
        #filelist2.sort()
        #filelist = filelist1+filelist2

        starttime = "1500"
        endtime   = cargs.endtime

        dt1 = datetime.strptime(f"{wargs.eventdate} {starttime}",'%Y%m%d %H%M')
        dt2 = datetime.strptime(f"{wargs.eventdate} {endtime}",  '%Y%m%d %H%M')
        if endtime < "1200":
            dt2 +=  timedelta(days=1)

        filelist  = []
        print(f"Reading obs_seq files from {dadir} ...")
        dt = dt1
        while dt <= dt2:
            dirhmin = dt.strftime("%H%M")
            filedate = dt.strftime("%Y%m%d%H%M")
            filepath= os.path.join(dadir,dirhmin,f"obs_seq.final.{filedate}.nc")
            if os.path.lexists(filepath):
                filelist.append(filepath)
            else:
                print(f"ERROR: {dirhmin}: {filepath} not exist.")

            dt = dt + timedelta(minutes=15)

        if len(filelist) <= 5:
            print(f"ERROR: found no enough obs_seq.final files in {dadir}: {filelist}.")
            sys.exit(0)

        obs_objs = load_variables(cargs,wargs, filelist)

        if cargs.verbose: print("\n Elapsed time of load_variables is:  %f seconds" % (timeit.time() - time2))

        time3 = timeit.time()

        for otype,obsobj in obs_objs.items():
            print(f"Ploting {otype} - {obsobj.type_label} for {wargs.eventdate} ....")
            make_plot(cargs, wargs,obsobj)

        if cargs.verbose: print("\n Elapsed time of make_plot is:  %f seconds" % (timeit.time() - time3))
