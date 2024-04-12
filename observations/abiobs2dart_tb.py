######## CONVERT Pre-Processed CWP Observation Files to DART obs_seq ######
#    Thomas Jones		May 26 2023
#    Version:	1.0
#	 Inputs:	Directory where GSI format ABI Radiance Files  netcdf files are located
#               Date to process (yyyymodd), channel num
#               [1:3.9, 2:6.2, 3:6.9, 4:7.2, ect]
# Output:	Directory where new DART obs_seq files will be located
#
# To Do:  Add night-time features to DART forward operator.
##############

import sys
import os
from datetime import *
from netCDF4 import Dataset
import numpy as np
from optparse import OptionParser
import time

parser = OptionParser()
parser.add_option("-i", dest="abidir", type="string", default= None, help="Input ABI netcdf directory")
parser.add_option("-o", dest="outdir", type="string", default= None, help="Output ABI obs_seq directory")
parser.add_option("-d", dest="indate", type="string", default= None, help="Date to process")
parser.add_option("-c", dest="inchan", type="int", default= None, help="In channel")
(options, args) = parser.parse_args()

abidir = options.abidir
outdir = options.outdir
indate = options.indate
inchan = options.inchan

### CLEAR-SKY OR ALL-SKY FLAG, 0=clear, 1=allsky
cloud = 0
sensor_id   = 44  # ABI
platform_id = 4

### FIND GSI .nc FILES
infiles = []
temp_files = os.listdir(abidir)
for f, file in enumerate(temp_files):
  # 2015-goes.nc
  if (file[5:12] == "goes.nc"):
    infiles.append(file)

infiles.sort()
#print(infiles)

for ff, file in enumerate(infiles):
    abifile = os.path.join(abidir,file)
    print(abifile)

    fdate = file[0:12]

    ### READ IN ABI OBSERVATIONS FROM FILE
    abiin = Dataset(abifile, "r")

    sat = abiin.getncattr('satellite')
    year = abiin.getncattr('year')
    month = abiin.getncattr('month')
    day = abiin.getncattr('day')
    hour = abiin.getncattr('hour')
    minute = abiin.getncattr('minute')
    #jday = abiin.getncattr('jday')

    numobs = abiin.variables['numobs'][:]
    channel = abiin.variables['channel'][:]
    t_time = abiin.variables['time'][:] #seconds since 1970-01-01 00:00:00
    lats = abiin.variables['lat'][:]
    lons = abiin.variables['lon'][:]
    solaz = abiin.variables['solaz'][:]
    sataz = abiin.variables['sataz'][:]
    sza = abiin.variables['sza'][:]
    vza = abiin.variables['vza'][:]

    #pressure = abiin.variables['pressure'][:]*100.0  #convert to PA
    value = abiin.variables['value'][:]
    #rad_value = abiin.variables['rad_value'][:]
    cmask = abiin.variables['cloud_mask'][:]
    #abi_err = abiin.variables['cwp_err'][:]

    abiin.close()

    sdate = year+month+day+hour+minute
    mdate = indate+file[0:4]

    numobs=int(numobs[0])
    t_time=t_time[0]

    outrad = value[inchan-1,:]
    print(f"channel = {channel}")
    outch = str(channel[inchan-1])
    ccc = channel[inchan-1]
    print(f"sat={sat}, outch={outch}, inchan={inchan}")
    abirad_err = 0.25

    if outch[0] == '8':
       pvert = 34000.0
       vert_coord  = 2
       abitb_err = 1.25
    elif outch[0] == '9':
       pvert = 45000.0
       vert_coord  = 2
       abitb_err = 1.35
    elif outch[0:2] == '10':
       pvert = 60000.
       vert_coord  = 2
       abitb_err = 1.45
    else:
       pvert = -1.0
       vert_coord  = -2

### SET UP DART STURCTURE
#
# vert_coord  = -2 :undefiend for some radiances, otherwise  = 2
# One obs-seq file for each channel

# Create local dictionary for observation kind definition - these can include user abbreviations
#                      user's observation type            kind   DART official name

    dartfile = os.path.join(outdir,'obs_seq_abi.'+sat+'_C'+outch+'.'+mdate)
    print(f"dartfile={dartfile}")

    Look_Up_Table={ "GOES_16_ABI_TB":  [98,   "GOES_16_ABI_TB"] ,
                    "GOES_17_ABI_TB":  [99,   "GOES_17_ABI_TB"] ,
                    "GOES_18_ABI_TB":  [100,   "GOES_18_ABI_TB"] ,
                    "GOES_19_ABI_TB":  [101,   "GOES_19_ABI_TB"] }


    kinds = ['GOES_16_ABI_TB','GOES_17_ABI_TB','GOES_18_ABI_TB','GOES_19_ABI_TB']
    kind_nums = [98,99,100,101]
    sat_nums = [16,17,18,19]
    truth      = 1.0  # dummy variable
    truth0     = 0.0
    missing = -888888.0
    specularity = missing

    if sat == 'G16':
        nkind = 0
    elif sat == 'G17':
        nkind = 1
    elif sat == 'G18':
        nkind = 2
    elif sat == 'G19':
        nkind = 3


    #DEFINE TIME INFO (Constant for Sat data)
    obs_time = datetime.strptime('2000-01-01 12:00:00', '%Y-%m-%d %H:%M:%S') + timedelta(seconds=t_time)
    dt_time  = obs_time - datetime(1601,1,1,0,0,0)

    days    = dt_time.days
    seconds = dt_time.seconds

    # Open ASCII file for DART obs to be written into.  We will add header info afterward
    fi = open(dartfile, "w")

    #LOOP THROUGH OBS
    nobs=1
    for i in range(1, numobs):
        #print(i, nobs, numobs)
        #if cmask[i] == cloud:

        fi.write(" OBS            %d\n" % (nobs) )

        if cmask[i] == cloud:
           fi.write("   %20.14f\n" % outrad[i]  )
        else:
           fi.write("   %20.14f\n" % missing  )
        fi.write("   %20.14f\n" % truth )

        if nobs == 1:
          fi.write(" %d %d %d\n" % (-1, nobs+1, -1) ) # First obs.
          print("first ob")
        elif i == (numobs-1):
          fi.write(" %d %d %d\n" % (nobs-1, -1, -1) ) # Last obs.
          print("last ob")
        else:
          fi.write(" %d %d %d\n" % (nobs-1, nobs+1, -1) )

        fi.write("obdef\n")
        fi.write("loc3d\n")

        rlat = np.radians(lats[i])
        tlon = lons[i]
        if tlon < 0:
          tlon = tlon + 360.0
        rlon = np.radians(tlon)

        fi.write("    %20.14f          %20.14f          %20.14f     %d\n" %
                    (rlon, rlat, pvert, vert_coord))

        fi.write("kind\n")
        fi.write("     %d     \n" % kind_nums[nkind] )

        # SAT INFO
        fi.write(" visir\n")
        fi.write("    %20.14f          %20.14f          %20.14f  \n" % (sataz[i], vza[i], missing ) )
        #fi.write("    %20.14f          %20.14f          %20.14f  \n" % (sataz[i], vza[i], solaz[i] ) )
        fi.write("    %20.14f  \n" % sza[i] )
        fi.write("       %d    %d    %d    %d \n" % ( platform_id, sat_nums[nkind], sensor_id, ccc) )
        fi.write("    %20.14f  \n" % specularity )
        fi.write("    %d  \n" % nobs )

        #TIME
        fi.write("    %d          %d     \n" % (seconds, days) )

        #OBS ERROR
        fi.write("    %20.14f  \n" % abitb_err**2 )

        if nobs % 1000 == 0: print(" write_DART_ABI:  Processed observation # %d" % nobs)
        nobs=nobs+1

    fi.close()

    # write header info
    with open(dartfile, 'r') as f: f_obs_seq = f.read()

    fi = open(dartfile, "w")

    fi.write(" obs_sequence\n")
    fi.write("obs_kind_definitions\n")
    fi.write("    %d  \n" % 1 )
    fi.write("    %d          %s   \n" % (kind_nums[nkind], kinds[nkind]) )

    fi.write("  num_copies:            %d  num_qc:            %d\n" % (1, 1))
    fi.write(" num_obs:       %d  max_num_obs:       %d\n" % (nobs-1, nobs-1) )

    fi.write("observation\n")
    fi.write("GOES QC \n")

    fi.write("  first:            %d  last:       %d\n" % (1, nobs-1) )

    # Now write back in all the actual DART obs data
    fi.write(f_obs_seq)
    fi.close()

    print(f"\n write_DART_ascii:  Created ascii DART file: {dartfile}, N = {nobs} written")
    time.sleep(2)
