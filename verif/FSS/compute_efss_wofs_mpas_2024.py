#!/usr/bin/env python

from optparse import OptionParser
import sys
import netCDF4
import os
import numpy as np
from scipy import signal

#-------------------------------------------------------------------------------
# Function for FFT convolution filter.

def fft_filter(binfld, winsize):

    n = int(winsize)
    conv = np.ones((n,n))

    fract = np.absolute(np.round(signal.fftconvolve(binfld, conv, mode='same'), 0)) / winsize**2.

    return fract

#-------------------------------------------------------------------------------
# Function for FFT convolution filter.

def fft_filter_ens(binfld, ne, winsize):

    n = int(winsize)
    conv = np.ones((2*ne,n,n))

    fract = np.amax(np.absolute(np.round(signal.fftconvolve(binfld, conv, mode='same'), 0)) / (ne*winsize**2.), axis=0)

    return fract

#-------------------------------------------------------------------------------
# Function to compute FSS using convolution via fast fourier transform (FFT).

def fourier_fss(fcst, obs, fthld, othld, winsize):

    pf = fft_filter(fcst >= fthld, winsize)
    po = fft_filter(obs >= othld, winsize)

    fbs = np.nanmean(np.power(pf - po, 2))
    fbsw = np.nanmean(np.power(pf, 2) + np.power(po, 2))

    fss = 1. - fbs/fbsw

    return fss, fbs, fbsw

#-------------------------------------------------------------------------------
# Function to compute eFSS using convolution via fast fourier transform (FFT).

def fourier_efss(fcst, obs, fthld, othld, ne, winsize):

    pf = fft_filter_ens(fcst >= fthld, ne, winsize)
    po = fft_filter(obs >= othld, winsize)

    fbs = np.nanmean(np.power(pf - po, 2))
    fbsw = np.nanmean(np.power(pf, 2) + np.power(po, 2))

    fss = 1. - fbs/fbsw

    return fss, fbs, fbsw


####################################### File Variables: ######################################################

parser = OptionParser()
parser.add_option("-d", dest="indir", type="string", default= None, help="input directory of summary files")
parser.add_option("-m", dest="mrmsdir", type="string", default= None, help="input directory of mrms files")
parser.add_option("-o", dest="outdir", type="string", help = "output directory")
parser.add_option("-v", dest="var", type="string", help = "variable to process (e.g. uh2to5)")
parser.add_option("-x", dest="xw", type="int", help = "x-dir starting point")
parser.add_option("-y", dest="ys", type="int", help = "y-dir starting point")

(options, args) = parser.parse_args()

if ((options.indir == None) or (options.outdir == None) or (options.var == None) or (options.mrmsdir == None)):
   print()
   parser.print_help()
   print()
   sys.exit(1)
else:
   indir = options.indir
   mrmsdir = options.mrmsdir
   outdir = options.outdir
   var = options.var

#################################### User-Defined Variables:  #####################################################

# Use subdomain?
usesub = 1    # 1 for yes, 0 for no

# Use percentile thresholds instead?
usepct = 0    # 1 for yes, 0 for no

# Bounds for subdomain if used
if ((options.xw == None) or (options.ys == None)):
   xw = 50
   xe = xw+134
   ys = 50
   yn = ys+134
else:
   xw = options.xw
   xe = 300-xw
   ys = options.ys
   yn = 300-ys

neighsize = [1., 3., 5., 9., 17., 33., 65., 193., 285.] #[1.,3.,5.,9.,17.,33.,65.,129.,257.]                 # neighborhood sizes

# Use neighborhoods that extend beyond domain boundaries?
usebdy = 1    # 1 for yes, 0 for no, currently not used

#################################### Set variable specific values:  #####################################################

if (var == 'compdz'):
   mrms_var = 'refl_consv'
   fcst_var = 'comp_dz'
   mrms_prct = [90.,95.,99.]
   fcst_prct = [90.,95.,99.]
   mrms_thds = [30.,35.,40.,45.,50.,55.]
   fcst_thds = [30.,35.,40.,45.,50.,55.]
   #mrms_thds = [26.2,33.6,45.]
   #fcst_thds = [30.8,39.0,51.9]
elif (var == 'uh0to2'):
   mrms_var = 'azlo_cress'
   fcst_var = 'uh_0to2'
   mrms_prct = [99.5, 99.9, 99.95]
   fcst_prct = [99.5, 99.9, 99.95]
elif (var == 'uh2to5'):
   mrms_var = 'azmd_cress'
   fcst_var = 'uh_2to5'
   mrms_prct = [99.0, 99.9, 99.95]
   fcst_prct = [99.0, 99.9, 99.95]
   mrms_thds = [0.001,0.0033,0.0041]
   fcst_thds = [8.58,83.7,115.7]
else:
   print("%s is an unsupported variable, please use 'compdz', 'uh0to2', or 'uh2to5'" %var)
   sys.exit(1)

#################################### Read forecast output #####################################################

fcst_files = []
indv_files = []
temp_files = os.listdir(indir)

for f, file in enumerate(temp_files):
    if (file[0:8] == 'wofs_ALL' and file[-3:] == ".nc"):
      indv_files.append(file)
      fcst_files.append(os.path.join(indir,file))
fcst_files.sort()
print(indv_files[0])
date = indv_files[1][12:20]
year = indv_files[0][12:16]
mon  = indv_files[0][16:18]
day  = indv_files[0][18:20]
frun = indv_files[0][21:25]
num_date = int(date)
num_year = int(year)
num_mon  = int(mon)
num_day  = int(day)
num_frun = int(frun)

init_fcst = indv_files[0][22:26]
#dom = indir[-8:-6]
print(num_date,num_year,num_mon,num_day,num_frun)

###################################### Read Forecast Files #######################################################

nt = len(fcst_files)

for ts in range(0,nt):
   if ts == 0:
      try:
         fin = netCDF4.Dataset(fcst_files[ts], "r")
         print("Opening %s \n" % fcst_files[ts])
      except:
         print("%s does not exist! \n" % fcst_files[ts])
         sys.exit(1)

      xlat = fin.variables['xlat'][:]
      xlon = fin.variables['xlon'][:]

      sw_lat = xlat[0,0]
      sw_lon = xlon[0,0]
      ne_lat = xlat[-1,-1]
      ne_lon = xlon[-1,-1]

      ne = fin.dimensions['ne'].size
      nx = fin.dimensions['NX'].size
      ny = fin.dimensions['NY'].size
      dx = fin.DX
      cen_lat = fin.CEN_LAT
      cen_lon = fin.CEN_LON
      stand_lon = fin.STAND_LON
      true_lat1 = fin.TRUELAT1
      true_lat2 = fin.TRUELAT2
      #init_time = fin.INIT_TIME_SECONDS
      start_date = fin.START_DATE
      shour = start_date[11:13]
      smin = start_date[14:16]

      fcst = np.zeros((nt,ne,ny,nx))
      time = np.zeros(nt)
      fcst_time = np.zeros(nt)
      fcst_hr = np.zeros(nt)
      fcst_min = np.zeros(nt)

      init_time = 3600.*float(shour) + 60.*float(smin)
      time = init_time + 300.*np.arange(0,nt)
      fcst_time = 300.*np.arange(0,nt)

      fcst[ts,:,:,:] = fin.variables[fcst_var][:]
      #time[ts] = fin.VALID_TIME_SECONDS
      #fcst_time[ts] = time[ts] - init_time

      fcst_min[ts], fcst_sec = divmod(time[ts], 60)
      fcst_hr[ts], fcst_min[ts] = divmod(fcst_min[ts], 60)

      fin.close()
      del fin
   else:
      try:
         fin = netCDF4.Dataset(fcst_files[ts], "r")
         print("Opening %s \n" % fcst_files[ts])
      except:
         print("%s does not exist! \n" % fcst_files[ts])
         sys.exit(1)

      fcst[ts,:,:,:] = fin.variables[fcst_var][:]
      #time[ts] = fin.VALID_TIME_SECONDS
      #fcst_time[ts] = time[ts] - init_time

      fcst_min[ts], fcst_sec = divmod(time[ts], 60)
      fcst_hr[ts], fcst_min[ts] = divmod(fcst_min[ts], 60)

      if fcst_hr[ts] >= 24:
         fcst_hr[ts] = fcst_hr[ts] - 24

      fin.close()
      del fin


###################################### Read MRMS Files #######################################################

st_sec = int(time[0])
en_sec = int(time[nt-1])
cnt = 0

for ts in range(st_sec,en_sec+1,300):
   obs_min, obs_sec = divmod(ts, 60)
   obs_hr, obs_min = divmod(obs_min, 60)

   obs_year = num_year
   obs_mon = num_mon
   obs_day = num_day

   if obs_hr >= 24:
     obs_hr = obs_hr - 24
     obs_day = obs_day + 1
     if obs_day == 32:
        obs_day = 1
        obs_mon = obs_mon + 1

   obs_file = os.path.join(mrmsdir,"wofs_MRMS_RAD_%04d%02d%02d_%02d%02d.nc"%(obs_year,obs_mon,obs_day,obs_hr,obs_min))

   if ts == st_sec:
      mrms = np.zeros((nt,ny,nx))
      mrms_time = np.zeros(nt)

   try:
      fin = netCDF4.Dataset(obs_file, "r")
      print("Opening %s \n" % obs_file)
      mrms[cnt,:,:] = fin.variables[mrms_var][:]
   except:
      print("%s does not exist! \n" % obs_file)
      mrms[cnt,:,:] = np.zeros((ny,nx))
      fcst[cnt,:,:,:] = np.zeros((ne,ny,nx))
      print(cnt)
#      sys.exit(1)
#   mrms[cnt,:,:] = fin.variables[mrms_var][:]
   mrms_time[cnt] = ts

   if np.amax(mrms[cnt,:,:]) == 0.:
       print("Max MRMS value = 0... setting FCST field to 0")
       mrms[cnt,:,:] = 0.
       fcst[cnt,:,:,:] = 0.

   cnt = cnt + 1


###################################### Computing eFSS #######################################################

print("Computing eFSS")

if len(neighsize) == 0:
   minxy = min(nx, ny)
   for ii in range(1,minxy):
      ns = ii**2
      if ns % 2 == 0:
         ns = ns - 1
      if ns < minxy:
         neighsize.append(ns)

if nx == 300:
    print("\nUsing subdomain for 3KM.")
    usesub = 1


#neighsize = np.asarray(neighsize)

if usepct == 1:
   nft = len(fcst_prct)
   nmt = len(mrms_prct)
else:
   nft = len(fcst_thds)
   nmt = len(mrms_thds)

nnw = len(neighsize)

fcst_thld = np.zeros((nt,nft))
mrms_thld = np.zeros((nt,nmt))
fcst_max = np.zeros((nt))
mrms_max = np.zeros((nt))

efbs = np.full((nt,nnw,nft),-999.)
efbsr = np.full((nt,nnw,nft),-999.)
efss = np.full((nt,nnw,nft),-999.)
fssu = np.full((nt,nft),-999.)
aefss = np.full((nt,nft),-999.)
scales = np.zeros((nnw))
po = np.full((nt,nft),0.0)
pf = np.full((nt,nft),0.0)

fbs = np.full((ne,nt,nnw,nft),-999.)
fss = np.full((ne,nt,nnw,nft),-999.)
fbsr = np.full((ne,nt,nnw,nft),-999.)
afss = np.full((ne,nt,nft),-999.)

for ii in range(0,nnw):
   print("\nWorking on neighborhood size of %s gridpoints..." %(neighsize[ii]))
   scales[ii] = (neighsize[ii] - 1.0)*dx/1000.

   for jj in range(0,nft):
      if usepct == 1:
         print("Threshold: %s" %(fcst_prct[jj]))
      else:
         print("MRMS Threshold: %s" %(mrms_thds[jj]))
         print("FCST Threshold: %s" %(fcst_thds[jj]))

      # Full domain
      if usesub == 0:

         for ts in range(0,nt):
            if usepct == 1:
               fcst_thld[ts,jj] = np.percentile(fcst[ts,:,:,:],fcst_prct[jj])
               mrms_thld[ts,jj] = np.percentile(mrms[ts,:,:],mrms_prct[jj])
            else:
               fcst_thld[ts,jj] = fcst_thds[jj]
               mrms_thld[ts,jj] = mrms_thds[jj]

            if ii == 0:
               po[ts,jj] = 1.*np.count_nonzero(mrms[ts,:,:] >= mrms_thld[ts,jj])/np.count_nonzero(mrms[ts,:,:] >= 0.0)
               pf[ts,jj] = 1.*np.count_nonzero(fcst[ts,:,:,:] >= fcst_thld[ts,jj])/np.count_nonzero(fcst[ts,:,:,:] >= 0.0)
               fssu[ts,jj] = 0.5 + po[ts,jj]/2.
               aefss[ts,jj] = (2.*po[ts,jj]*pf[ts,jj])/(np.power(po[ts,jj],2)+np.power(pf[ts,jj],2))

            if ((np.amax(fcst[ts,:,:,:]) >= fcst_thld[ts,jj]) or (np.amax(mrms[ts,:,:]) >= mrms_thld[ts,jj])):
               efss[ts,ii,jj], efbs[ts,ii,jj], efbsr[ts,ii,jj] = fourier_efss(fcst[ts,:,:,:], mrms[ts,:,:], fcst_thld[ts,jj], mrms_thld[ts,jj], ne, neighsize[ii])

            if ii == 0 and jj == 0:
               fcst_max[ts] = np.amax(fcst[ts,:,:,:])
               mrms_max[ts] = np.amax(mrms[ts,:,:])

            # Compute FSS for each member
            for em in range(0,ne):
               if ii == 0:
                  ipo = 1.*np.count_nonzero(mrms[ts,:,:] >= mrms_thld[ts,jj])/np.count_nonzero(mrms[ts,:,:] >= 0.0)
                  ipf = 1.*np.count_nonzero(fcst[ts,em,:,:] >= fcst_thld[ts,jj])/np.count_nonzero(fcst[ts,em,:,:] >= 0.0)
                  afss[em,ts,jj] = (2.*ipo*ipf)/(np.power(ipo,2)+np.power(ipf,2))

               if ((np.amax(fcst[ts,em,:,:]) >= fcst_thld[ts,jj]) or (np.amax(mrms[ts,:,:]) >= mrms_thld[ts,jj])):
                  fss[em,ts,ii,jj], fbs[em,ts,ii,jj], fbsr[em,ts,ii,jj] = fourier_fss(fcst[ts,em,:,:], mrms[ts,:,:], fcst_thld[ts,jj], mrms_thld[ts,jj], neighsize[ii])


      # Subdomain
      if usesub == 1:

         for ts in range(0,nt):
            if usepct == 1:
               fcst_thld[ts,jj] = np.percentile(fcst[ts,:,ys:yn,xw:xe],fcst_prct[jj])
               mrms_thld[ts,jj] = np.percentile(mrms[ts,ys:yn,xw:xe],mrms_prct[jj])
            else:
               fcst_thld[ts,jj] = fcst_thds[jj]
               mrms_thld[ts,jj] = mrms_thds[jj]

            if ii == 0:
               po[ts,jj] = 1.*np.count_nonzero(mrms[ts,ys:yn,xw:xe] >= mrms_thld[ts,jj])/np.count_nonzero(mrms[ts,ys:yn,xw:xe] >= 0.0)
               pf[ts,jj] = 1.*np.count_nonzero(fcst[ts,:,ys:yn,xw:xe] >= fcst_thld[ts,jj])/np.count_nonzero(fcst[ts,:,ys:yn,xw:xe] >= 0.0)
               fssu[ts,jj] = 0.5 + po[ts,jj]/2.
               aefss[ts,jj] = (2.*po[ts,jj]*pf[ts,jj])/(np.power(po[ts,jj],2)+np.power(pf[ts,jj],2))

            if ((np.amax(fcst[ts,:,ys:yn,xw:xe]) >= fcst_thld[ts,jj]) or (np.amax(mrms[ts,ys:yn,xw:xe])  >= mrms_thld[ts,jj])):
               efss[ts,ii,jj], efbs[ts,ii,jj], efbsr[ts,ii,jj] = fourier_efss(fcst[ts,:,ys:yn,xw:xe], mrms[ts,ys:yn,xw:xe], fcst_thld[ts,jj], mrms_thld[ts,jj], ne, neighsize[ii])

            if ii == 0 and jj == 0:
               fcst_max[ts] = np.amax(fcst[ts,:,ys:yn,xw:xe])
               mrms_max[ts] = np.amax(mrms[ts,ys:yn,xw:xe])

            # Compute FSS for each member
            for em in range(0,ne):
               if ii == 0:
                  ipo = 1.*np.count_nonzero(mrms[ts,ys:yn,xw:xe] >= mrms_thld[ts,jj])/np.count_nonzero(mrms[ts,ys:yn,xw:xe] >= 0.0)
                  ipf = 1.*np.count_nonzero(fcst[ts,em,ys:yn,xw:xe] >= fcst_thld[ts,jj])/np.count_nonzero(fcst[ts,em,ys:yn,xw:xe] >= 0.0)
                  afss[em,ts,jj] = (2.*ipo*ipf)/(np.power(ipo,2)+np.power(ipf,2))
                  #if jj == 2:
                  #   print(em,ipo,ipf,afss[em,ts,jj])

               if ((np.amax(fcst[ts,em,ys:yn,xw:xe]) >= fcst_thld[ts,jj]) or (np.amax(mrms[ts,ys:yn,xw:xe]) >= mrms_thld[ts,jj])):
                  fss[em,ts,ii,jj], fbs[em,ts,ii,jj], fbsr[em,ts,ii,jj] = fourier_fss(fcst[ts,em,ys:yn,xw:xe], mrms[ts,ys:yn,xw:xe], fcst_thld[ts,jj], mrms_thld[ts,jj], neighsize[ii])


###################################### Output FSS: #######################################################

if usesub == 0:
   tempname = 'wofs_%s_%04d_%s_efss_5min.nc' %(num_date,num_frun,var)
else:
   tempname = 'wofs_%s_%04d_%s_efss_5min.nc' %(num_date,num_frun,var)

out_file = os.path.join(outdir, tempname)

try:
   fout = netCDF4.Dataset(out_file, "w")
except:
   print("Could not create %s!\n" % out_file)

fout.createDimension('NE', ne)
fout.createDimension('NT', nt)
fout.createDimension('NW', nnw)
fout.createDimension('NTH', nft)

fout.createVariable('FCST_MAX_VALUE', 'f4', ('NT',))
fout.createVariable('MRMS_MAX_VALUE', 'f4', ('NT',))
fout.createVariable('TIME', 'f4', ('NT',))
fout.createVariable('HOUR', 'f4', ('NT',))
fout.createVariable('MINUTE', 'f4', ('NT',))

fout.createVariable('SCALES', 'f4', ('NW',))
fout.createVariable('FCST_THLDS', 'f4', ('NT','NTH',))
fout.createVariable('MRMS_THLDS', 'f4', ('NT','NTH',))
fout.createVariable('FSSU', 'f4', ('NT','NTH',))
fout.createVariable('EFSS', 'f4', ('NT','NW','NTH',))
fout.createVariable('EFBS', 'f4', ('NT','NW','NTH',))
fout.createVariable('EFBSR', 'f4', ('NT','NW','NTH',))
fout.createVariable('AEFSS', 'f4', ('NT','NTH',))
fout.createVariable('PO', 'f4', ('NT','NTH',))
fout.createVariable('PF', 'f4', ('NT','NTH',))
fout.createVariable('FSS', 'f4', ('NE','NT','NW','NTH',))
fout.createVariable('FBS', 'f4', ('NE','NT','NW','NTH',))
fout.createVariable('FBSR', 'f4', ('NE','NT','NW','NTH',))
fout.createVariable('AFSS', 'f4', ('NE','NT','NTH',))

fout.variables['TIME'][:] = time[:]
fout.variables['HOUR'][:] = fcst_hr[:]
fout.variables['MINUTE'][:] = fcst_min[:]
fout.variables['SCALES'][:] = scales
fout.variables['FCST_THLDS'][:,:] = fcst_thld
fout.variables['MRMS_THLDS'][:,:] = mrms_thld
fout.variables['FCST_MAX_VALUE'][:] = fcst_max
fout.variables['MRMS_MAX_VALUE'][:] = mrms_max
fout.variables['FSSU'][:,:] = fssu
fout.variables['EFSS'][:,:,:] = efss
fout.variables['EFBS'][:,:,:] = efbs
fout.variables['EFBSR'][:,:,:] = efbsr
fout.variables['AEFSS'][:,:] = aefss
fout.variables['PO'][:,:] = po
fout.variables['PF'][:,:] = pf
fout.variables['FSS'][:,:,:,:] = fss
fout.variables['FBS'][:,:,:,:] = fbs
fout.variables['FBSR'][:,:,:,:] = fbsr
fout.variables['AFSS'][:,:,:] = afss

fout.close()
del fout
