#!/usr/bin/env python

######## CONVERT Pre-Processed CWP Observation Files to DART obs_seq ######
#    Thomas Jones		May 26 2023
#    Version:	1.0
#	 Inputs:	Directory where GSI format CWP netcdf files are located
#               Date to process (yyyymodd)
#	 Output:	Directory where new DART obs_seq files will be located
#
#	 To Do:  Add night-time features to DART forward operator.
##############

import sys
import os
from datetime import *
from netCDF4 import Dataset
import numpy as np
from optparse import OptionParser


parser = OptionParser()
parser.add_option("-i", dest="cwpdir", type="string", default= None, help="Input CWP netcdf directory")
parser.add_option("-o", dest="outdir", type="string", default= None, help="Output CWP obs_seq directory")
parser.add_option("-d", dest="indate", type="string", default= None, help="Date to process")
(options, args) = parser.parse_args()

cwpdir = options.cwpdir
outdir = options.outdir
indate = options.indate

### FIND GSI .nc FILES
infiles = []
temp_files = os.listdir(cwpdir)
for f, file in enumerate(temp_files):
    if (file[0:8] == indate):
        infiles.append(file)

infiles.sort()
print(infiles)

for ff, file in enumerate(infiles):
    cwpfile = os.path.join(cwpdir,file)
    print(cwpfile)

    fdate = file[0:12]

    ### READ IN CWP OBSERVATIONS FROM FILE
    cwpin = Dataset(cwpfile, "r")

    sat = cwpin.getncattr('satellite')
    year = cwpin.getncattr('year')
    month = cwpin.getncattr('month')
    day = cwpin.getncattr('day')
    hour = cwpin.getncattr('hour')
    minute = cwpin.getncattr('minute')
    jday = cwpin.getncattr('jday')

    numobs = cwpin.variables['numobs'][:]
    t_time = cwpin.variables['time'][:] #seconds since 1970-01-01 00:00:00
    lats = cwpin.variables['lat'][:]
    lons = cwpin.variables['lon'][:]
    pressure = cwpin.variables['pressure'][:]*100.0  #convert to PA
    cwp = cwpin.variables['cwp'][:]
    ctp = cwpin.variables['ctp'][:]*100.0
    cbp = cwpin.variables['cbp'][:]*100.0
    phase = cwpin.variables['phase'][:]
    cwp_err = cwpin.variables['cwp_err'][:]

    cwpin.close()

    sdate = year+month+day+hour+minute
    numobs=int(numobs[0])
    t_time=t_time[0]

### SET UP DART STURCTURE
#
# vert_coord  = -2 :undefiend for CWP = 0)
#             =  2 :pressure (Pa) for CWP > 0)
# Observation types (phase): #0=CWP0, 1=LWP, 2=IWP, 3=CWP0_NGT, 4=LWP_NGT, 5=IWP_NGT
								#6=LWP0, 7=LWP_NGT0

# Create local dictionary for observation kind definition - these can include user abbreviations
#                      user's observation type            kind   DART official name

    dartfile = os.path.join(outdir,'obs_seq_cwp.'+sat+'_V04.'+fdate)

    Look_Up_Table={ "GOES_CWP_PATH":    [80,   "GOES_CWP_PATH"] ,
                    "GOES_LWP_PATH":    [81,   "GOES_LWP_PATH"] ,
                    "GOES_IWP_PATH":    [82,   "GOES_IWP_PATH"] ,
                    "GOES_CWP_ZERO":    [83,   "GOES_IWP_ZERO"],
                    "GOES_CWP_NIGHT":   [84,   "GOES_CWP_NIGHT"]  }


    kinds = ['GOES_CWP_PATH','GOES_LWP_PATH','GOES_IWP_PATH','GOES_CWP_ZERO','GOES_CWP_NIGHT']
    kind_nums = [80,81,82,83,84]
    truth      = 1.0  # dummy variable

    #DEFINE TIME INFO (Constant for Sat data)
    obs_time = datetime.strptime('1970-01-01 00:00:00', '%Y-%m-%d %H:%M:%S') + timedelta(seconds=t_time)
    dt_time  = obs_time - datetime(1601,1,1,0,0,0)

    days    = dt_time.days
    seconds = dt_time.seconds

    # Open ASCII file for DART obs to be written into.  We will add header info afterward
    fi = open(dartfile, "w")

    #LOOP THROUGH OBS
    ngt_ct = 0
    for i in range(1, numobs):

      nobs=i

      fi.write(" OBS            %d\n" % (nobs) )

      fi.write("   %20.14f\n" % cwp[i]  )
      fi.write("   %20.14f\n" % truth )

      if nobs == 1:
        fi.write(" %d %d %d\n" % (-1, nobs+1, -1) ) # First obs.
        print("first ob")
      elif nobs == (numobs-1):
        fi.write(" %d %d %d\n" % (nobs-1, -1, -1) ) # Last obs.
        print("last ob")
      else:
        fi.write(" %d %d %d\n" % (nobs-1, nobs+1, -1) )

      fi.write("obdef\n")
      fi.write("loc3d\n")

      if phase[i] == 0:		#CLEAR
        vert_coord = -2
        nkind = kind_nums[3]
      elif phase[i] == 1:		#LWP DAY
        vert_coord = 2
        nkind = kind_nums[1]
      elif phase[i] == 2:		#IWP DAY
        vert_coord = 2
        nkind = kind_nums[2]
      elif phase[i] == 3:		#CLEAR NGT
        vert_coord = -2
        nkind = kind_nums[3]
      else:
        vert_coord = 2                 #SET POSTIVE NIGHT TO "GOES_CWP_NIGHT", DO NOT ASSIMIATE AT THIS TIME
        nkind = kind_nums[4]
        ngt_ct = ngt_ct+1

      rlat = np.radians(lats[i])
      tlon = lons[i]
      if tlon < 0:
        tlon = tlon + 360.0
      rlon = np.radians(tlon)

      fi.write("    %20.14f          %20.14f          %20.14f     %d\n" %
                  (rlon, rlat, pressure[i], vert_coord))

      fi.write("kind\n")
      fi.write("     %d     \n" % nkind )

      # CTP / CBP / Phase info
      fi.write("    %20.14f          %20.14f  \n" % (cbp[i], ctp[i]) )
      fi.write("    %20.14f  \n" % (phase[i]) )

      fi.write("    %d          %d     \n" % (seconds, days) )

      if phase[i] < 4:
        fi.write("    %20.14f  \n" % cwp_err[i]**2 )
      else:
        fi.write("    %20.14f  \n" % -99.9 )

      if nobs % 1000 == 0: print(" write_DART_CWP:  Processed observation # %d" % nobs)

    fi.close()

    # write header info
    with open(dartfile, 'r') as f: f_obs_seq = f.read()

    fi = open(dartfile, "w")

    fi.write(" obs_sequence\n")
    fi.write("obs_kind_definitions\n")

    if ngt_ct > 0:  fi.write("       %d\n" % 4)
    if ngt_ct == 0: fi.write("       %d\n" % 3)

    if ngt_ct > 0: fi.write("    %d          %s   \n" % (kind_nums[4], kinds[4]) )
    fi.write("    %d          %s   \n" % (kind_nums[1], kinds[1]) )
    fi.write("    %d          %s   \n" % (kind_nums[2], kinds[2]) )
    fi.write("    %d          %s   \n" % (kind_nums[3], kinds[3]) )

    fi.write("  num_copies:            %d  num_qc:            %d\n" % (1, 1))
    fi.write(" num_obs:       %d  max_num_obs:       %d\n" % (nobs, nobs) )

    fi.write("observations\n")
    fi.write("QC CWP\n")

    fi.write("  first:            %d  last:       %d\n" % (1, nobs) )

    # Now write back in all the actual DART obs data
    fi.write(f_obs_seq)
    fi.close()

    print("\n write_DART_ascii:  Created ascii DART file, N = %d written" % nobs)


