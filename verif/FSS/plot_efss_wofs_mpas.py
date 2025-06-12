#!/usr/bin/env python

# System imports

import sys
import os
import datetime as DT
import numpy as np
from optparse import OptionParser
import netCDF4

from efss_plot_functions_wofs_mpas import heatmap_width_inten_diff_mpas, time_series_efss_mpas

# -------------------------------------------------------------------------------
# Read in command line arguments

parser = OptionParser()
parser.add_option("-w", dest="wdir", type="string", default=None,
                        help="wofs input directory of efss files")
parser.add_option("-r", dest="rdir", type="string", default=None,
                        help="hrrr input directory of efss files")
parser.add_option("-o", dest="outdir", type="string",
                        help="output directory of plots")

(options, args) = parser.parse_args()

if ((options.wdir == None) or (options.rdir == None) or (options.outdir == None)):
    print()
    parser.print_help()
    print()
    sys.exit(1)
else:
    wdir = options.wdir
    rdir = options.rdir
    outdir = options.outdir

# -------------------------------------------------------------------------------
# Options for filtering

years = np.array([2024])
exper = "cb-WoFSvsMPAS-WoFS"
year1 = years[0]
year2 = years[-1]

# -------------------------------------------------------------------------------
# Intialize eFSS files to be read

#case_time_dict = {'20240506' : ['1700', '1800', '1900', '2000', '2100', '2200', '2300', '0000', '0100', '0200', '0300'],
#                  '20240507' : ['1700', '1800', '1900', '2000', '2100', '2200', '2300', '0000', '0100', '0200', '0300'],
#                  '20240508' : ['1700', '1800', '1900', '2000', '2100', '2200', '2300', '0000'],
#                  '20240516' : ['1700', '1800', '1900', '2000', '2100', '2200', '2300', '0000', '0100', '0200', '0300'],
#                  '20240520' : ['1700', '1800', '1900', '2000', '2100', '2200', '2300', '0000', '0100', '0200', '0300'],
#                  '20240521' : ['1700', '1800', '1900', '2000', '2100', '2200', '2300', '0000', '0100', '0200', '0300']
#                 }

case_time_dict = {'20240506' : ['1900', '2000', '2100', '2200', '2300', '0000', '0100', '0200', '0300'],
                  '20240507' : ['1900', '2000', '2100', '2200', '2300', '0000', '0100', '0200', '0300'],
                  '20240508' : ['1900', '2000', '2100', '2200', '2300', '0000'],
                  '20240516' : ['1900', '2000', '2100', '2200', '2300', '0000', '0100', '0200', '0300'],
                  '20240521' : ['1900', '2000', '2100', '2200', '2300', '0000', '0100', '0200', '0300']
                 }

file_dates      = []
fcst_files_wofs = []
fcst_files_mpas = []
for case,times in case_time_dict.items():
    for time in times:
        if time < '1200':
            casedatetime = DT.datetime.strptime(case,'%Y%m%d')+DT.timedelta(days=1)
            casedate = casedatetime.strftime('%Y%m%d')
        else:
            casedate = case

        efss_file = f"wofs_{casedate}_{time}_compdz_efss_5min.nc"
        file_dates.append(casedate)
        wfile = os.path.join(wdir, case, time, efss_file)
        if os.path.lexists(wfile):
            fcst_files_wofs.append(wfile)
        else:
            print(f"ERROR: file {wfile} not exist.")
            sys.exit(1)

        rfile = os.path.join(rdir, case, time, efss_file)
        if os.path.lexists(rfile):
            fcst_files_mpas.append(rfile)
        else:
            print(f"ERROR: file {rfile} not exist.")
            sys.exit(1)

#indv_files.sort()
#fcst_files_wofs.sort()
#fcst_files_mpas.sort()

# -------------------------------------------------------------------------------
# Read in eFSS files

ny = len(years)

for yr in range(0, ny):

    ### Read in WoFS Files ###
    # fcst_files = []
    # temp_files = os.listdir(os.path.join(wdir,str(years[yr])))

    # for f, file in enumerate(temp_files):
    #    if (file[0:5] == 'wofs_'):
    #      indv_files.append(file)
    #      fcst_files.append(os.path.join(os.path.join(wdir,str(years[yr])),file))
    # fcst_files.sort()

    nf = len(fcst_files_wofs)
    print(f"Reading {nf} cb-WoFS files ....")
    for ft in range(0, nf):
        try:
            fin = netCDF4.Dataset(fcst_files_wofs[ft], "r")
            print("Opening %s " % fcst_files_wofs[ft])
        except:
            print("%s does not exist! \n" % fcst_files_wofs[ft])
            sys.exit(1)

        if (yr == 0) and (ft == 0):

            ne  = fin.dimensions['NE'].size
            nt  = fin.dimensions['NT'].size
            nw  = fin.dimensions['NW'].size
            nth = fin.dimensions['NTH'].size
            ntt = fin.dimensions['NT'].size
            nf  = 400

            if nt < 6:
                nt = 7
                print("Changed nt from %s to %s \n" % (ntt, nt))

            wfdate       = np.full((ny, nf), np.nan)
            wftime       = np.full((ny, nf, nt), np.nan)
            wfhour       = np.full((ny, nf, nt), np.nan)
            wfmin        = np.full((ny, nf, nt), np.nan)
            wscales      = np.full((ny, nf, nw), np.nan)
            wfcst_thlds  = np.full((ny, nf, nt, nth), np.nan)
            wmrms_thlds  = np.full((ny, nf, nt, nth), np.nan)
            wfssu        = np.full((ny, nf, nt, nth), np.nan)
            wefss        = np.full((ny, nf, nt, nw, nth), np.nan)
            wefbs        = np.full((ny, nf, nt, nw, nth), np.nan)
            wefbsr       = np.full((ny, nf, nt, nw, nth), np.nan)
            waefss       = np.full((ny, nf, nt, nth), np.nan)
            wpo          = np.full((ny, nf, nt, nth), np.nan)
            wpf          = np.full((ny, nf, nt, nth), np.nan)
            wfss         = np.full((ny, nf, ne, nt, nw, nth), np.nan)
            wfbs         = np.full((ny, nf, ne, nt, nw, nth), np.nan)
            wfbsr        = np.full((ny, nf, ne, nt, nw, nth), np.nan)
            wafss        = np.full((ny, nf, ne, nt, nth), np.nan)
            wfcst_max    = np.full((ny, nf, nt), np.nan)
            wmrms_max    = np.full((ny, nf, nt), np.nan)

            wfdate[yr, ft]               = int(file_dates[ft])
            wftime[yr, ft, :ntt]         = fin.variables['TIME'][:]
            wfhour[yr, ft, :ntt]         = fin.variables['HOUR'][:]
            wfmin[yr, ft, :ntt]          = fin.variables['MINUTE'][:]
            wscales[yr, ft, :]           = fin.variables['SCALES'][:]
            wfcst_thlds[yr, ft, :ntt, :] = fin.variables['FCST_THLDS'][:]
            wmrms_thlds[yr, ft, :ntt, :] = fin.variables['MRMS_THLDS'][:]
            wfssu[yr, ft, :ntt, :]       = fin.variables['FSSU'][:]
            wefss[yr, ft, :ntt, :, :]    = fin.variables['EFSS'][:]
            wefbs[yr, ft, :ntt, :, :]    = fin.variables['EFBS'][:]
            wefbsr[yr, ft, :ntt, :, :]   = fin.variables['EFBSR'][:]
            waefss[yr, ft, :ntt, :]      = fin.variables['AEFSS'][:]
            wpo[yr, ft, :ntt, :]         = fin.variables['PO'][:]
            wpf[yr, ft, :ntt, :]         = fin.variables['PF'][:]
            wfss[yr, ft, :, :ntt, :, :]  = fin.variables['FSS'][:]
            wfbs[yr, ft, :, :ntt, :, :]  = fin.variables['FBS'][:]
            wfbsr[yr, ft, :, :ntt, :, :] = fin.variables['FBSR'][:]
            wafss[yr, ft, :, :ntt, :]    = fin.variables['AFSS'][:]
            wfcst_max[yr, ft, :ntt]      = fin.variables['FCST_MAX_VALUE'][:]
            wmrms_max[yr, ft, :ntt]      = fin.variables['MRMS_MAX_VALUE'][:]

        else:

            ntt = fin.dimensions['NT'].size

            wfdate[yr, ft]               = int(file_dates[ft])
            wftime[yr, ft, :ntt]         = fin.variables['TIME'][:]
            wfhour[yr, ft, :ntt]         = fin.variables['HOUR'][:]
            wfmin[yr, ft, :ntt]          = fin.variables['MINUTE'][:]
            wscales[yr, ft, :]           = fin.variables['SCALES'][:]
            wfcst_thlds[yr, ft, :ntt, :] = fin.variables['FCST_THLDS'][:]
            wmrms_thlds[yr, ft, :ntt, :] = fin.variables['MRMS_THLDS'][:]
            wfssu[yr, ft, :ntt, :]       = fin.variables['FSSU'][:]
            wefss[yr, ft, :ntt, :, :]    = fin.variables['EFSS'][:]
            wefbs[yr, ft, :ntt, :, :]    = fin.variables['EFBS'][:]
            wefbsr[yr, ft, :ntt, :, :]   = fin.variables['EFBSR'][:]
            waefss[yr, ft, :ntt, :]      = fin.variables['AEFSS'][:]
            wpo[yr, ft, :ntt, :]         = fin.variables['PO'][:]
            wpf[yr, ft, :ntt, :]         = fin.variables['PF'][:]
            wfss[yr, ft, :, :ntt, :, :]  = fin.variables['FSS'][:]
            wfbs[yr, ft, :, :ntt, :, :]  = fin.variables['FBS'][:]
            wfbsr[yr, ft, :, :ntt, :, :] = fin.variables['FBSR'][:]
            wafss[yr, ft, :, :ntt, :]    = fin.variables['AFSS'][:]
            wfcst_max[yr, ft, :ntt]      = fin.variables['FCST_MAX_VALUE'][:]
            wmrms_max[yr, ft, :ntt]      = fin.variables['MRMS_MAX_VALUE'][:]

        fin.close()
        del fin

    ### Read in WoFS-MPAS Files ###
    #fcst_files = []
    # indv_files = []
    # temp_files = os.listdir(os.path.join(rdir,str(years[yr])))

    # for f, file in enumerate(temp_files):
    #    if (file[0:9] == 'mpas-wofs'):
    #      indv_files.append(file)
    #      fcst_files.append(os.path.join(os.path.join(rdir,str(years[yr])),file))
    # fcst_files.sort()
    # indv_files.sort()


    nf = len(fcst_files_mpas)
    print(f"Reading {nf} mpas-WoFS files ....")
    for ft in range(0, nf):
        try:
            fin = netCDF4.Dataset(fcst_files_mpas[ft], "r")
            print("Opening %s " % fcst_files_mpas[ft])
        except:
            print("%s does not exist! \n" % fcst_files_mpas[ft])
            sys.exit(1)

        if (yr == 0) and (ft == 0):

            mnt = fin.dimensions['NT'].size
            mnw = fin.dimensions['NW'].size
            mnth = fin.dimensions['NTH'].size
            mne = fin.dimensions['NE'].size
            mntt = fin.dimensions['NT'].size
            nf = 400

            if nt < 6:
                nt = 7
                print("Changed nt from %s to %s \n" % (ntt, nt))

            mfdate        = np.full((ny, nf), np.nan)
            mftime        = np.full((ny, nf, mnt), np.nan)
            mfhour        = np.full((ny, nf, mnt), np.nan)
            mfmin         = np.full((ny, nf, mnt), np.nan)
            mscales       = np.full((ny, nf, nw), np.nan)
            mfcst_thlds   = np.full((ny, nf, mnt, mnth),np.nan)
            mmrms_thlds   = np.full((ny, nf, mnt, mnth),np.nan)
            mfssu         = np.full((ny, nf, mnt, mnth),np.nan)
            mefss         = np.full((ny, nf, mnt, nw,mnth),np.nan)
            mefbs         = np.full((ny, nf, mnt, nw,mnth),np.nan)
            mefbsr        = np.full((ny, nf, mnt, nw,mnth),np.nan)
            maefss        = np.full((ny, nf, mnt, mnth),np.nan)
            mpo           = np.full((ny, nf, mnt, mnth),np.nan)
            mpf           = np.full((ny, nf, mnt, mnth),np.nan)
            mfss          = np.full((ny, nf, mne, mnt,nw,mnth),np.nan)
            mfbs          = np.full((ny, nf, mne, mnt,nw,mnth),np.nan)
            mfbsr         = np.full((ny, nf, mne, mnt,nw,mnth),np.nan)
            mafss         = np.full((ny, nf, mne, mnt,mnth),np.nan)
            mfcst_max     = np.full((ny, nf, mnt), np.nan)
            mmrms_max     = np.full((ny, nf, mnt), np.nan)

            mfdate[yr,      ft]                 = int(file_dates[ft])
            mftime[yr,      ft, :ntt]           = fin.variables['TIME'][:]
            mfhour[yr,      ft, :ntt]           = fin.variables['HOUR'][:]
            mfmin[yr,       ft, :ntt]           = fin.variables['MINUTE'][:]
            mscales[yr,     ft, :]              = fin.variables['SCALES'][:]
            mfcst_thlds[yr, ft, :ntt, :]        = fin.variables['FCST_THLDS'][:]
            mmrms_thlds[yr, ft, :ntt, :]        = fin.variables['MRMS_THLDS'][:]
            mfssu[yr,       ft, :ntt, :]        = fin.variables['FSSU'][:]
            mefss[yr,       ft, :ntt, :,:]      = fin.variables['EFSS'][:]
            mefbs[yr,       ft, :ntt, :,:]      = fin.variables['EFBS'][:]
            mefbsr[yr,      ft, :ntt, :,:]      = fin.variables['EFBSR'][:]
            maefss[yr,      ft, :ntt, :]        = fin.variables['AEFSS'][:]
            mpo[yr,         ft, :ntt, :]        = fin.variables['PO'][:]
            mpf[yr,         ft, :ntt, :]        = fin.variables['PF'][:]
            mfss[yr,        ft, :,    :ntt,:,:] = fin.variables['FSS'][:]
            mfbs[yr,        ft, :,    :ntt,:,:] = fin.variables['FBS'][:]
            mfbsr[yr,       ft, :,    :ntt,:,:] = fin.variables['FBSR'][:]
            mafss[yr,       ft, :,    :ntt,:]   = fin.variables['AFSS'][:]
            mfcst_max[yr,   ft, :ntt]           = fin.variables['FCST_MAX_VALUE'][:]
            mmrms_max[yr,   ft, :ntt]           = fin.variables['MRMS_MAX_VALUE'][:]

        else:

            ntt = fin.dimensions['NT'].size

            mfdate[yr,      ft]                 = int(file_dates[ft])
            mftime[yr,      ft, :ntt]           = fin.variables['TIME'][:]
            mfhour[yr,      ft, :ntt]           = fin.variables['HOUR'][:]
            mfmin[yr,       ft, :ntt]           = fin.variables['MINUTE'][:]
            mscales[yr,     ft, :]              = fin.variables['SCALES'][:]
            mfcst_thlds[yr, ft, :ntt, :]        = fin.variables['FCST_THLDS'][:]
            mmrms_thlds[yr, ft, :ntt, :]        = fin.variables['MRMS_THLDS'][:]
            mfssu[yr,       ft, :ntt, :]        = fin.variables['FSSU'][:]
            mefss[yr,       ft, :ntt, :,:]      = fin.variables['EFSS'][:]
            mefbs[yr,       ft, :ntt, :,:]      = fin.variables['EFBS'][:]
            mefbsr[yr,      ft, :ntt, :,:]      = fin.variables['EFBSR'][:]
            maefss[yr,      ft, :ntt, :]        = fin.variables['AEFSS'][:]
            mpo[yr,         ft, :ntt, :]        = fin.variables['PO'][:]
            mpf[yr,         ft, :ntt, :]        = fin.variables['PF'][:]
            mfss[yr,        ft, :,    :ntt,:,:] = fin.variables['FSS'][:]
            mfbs[yr,        ft, :,    :ntt,:,:] = fin.variables['FBS'][:]
            mfbsr[yr,       ft, :,    :ntt,:,:] = fin.variables['FBSR'][:]
            mafss[yr,       ft, :,    :ntt,:]   = fin.variables['AFSS'][:]
            mfcst_max[yr,   ft, :ntt]           = fin.variables['FCST_MAX_VALUE'][:]
            mmrms_max[yr,   ft, :ntt]           = fin.variables['MRMS_MAX_VALUE'][:]

        fin.close()
        del fin

wefss  = np.where(wefss  == -999, np.nan, wefss)
wefbs  = np.where(wefbs  == -999, np.nan, wefbs)
wefbsr = np.where(wefbsr == -999, np.nan, wefbsr)
wfss   = np.where(wfss   == -999, np.nan, wfss)
wfbs   = np.where(wfbs   == -999, np.nan, wfbs)
wfbsr  = np.where(wfbsr  == -999, np.nan, wfbsr)
wftime = np.where(wftime == -999, np.nan, wftime)

mefss  = np.where(mefss  == -999, np.nan, mefss)
mefbs  = np.where(mefbs  == -999, np.nan, mefbs)
mefbsr = np.where(mefbsr == -999, np.nan, mefbsr)
mfss   = np.where(mfss   == -999, np.nan, mfss)
mfbs   = np.where(mfbs   == -999, np.nan, mfbs)
mfbsr  = np.where(mfbsr  == -999, np.nan, mfbsr)
mftime = np.where(mftime == -999, np.nan, mftime)

# -------------------------------------------------------------------------------
# Which plots to create?
# pmthd = 0 --> create all
# pmthd = 1 --> create width vs intensity heatmap for 0-6 hours
# pmthd = 2 --> create times series of eFSS and FSS

pmthd = 0

# -------------------------------------------------------------------------------
#

if ((pmthd == 0) or (pmthd == 1)):

    heatmap_width_inten_diff_mpas(outdir, wefbs, wefbsr, mefbs,mefbsr,wscales[0,0,:],wmrms_thlds[0,0,0,:],exper,year1,year2)

# -------------------------------------------------------------------------------
#

if ((pmthd == 0) or (pmthd == 2)):

    # neighsize = [1., 3., 5., 9., 17., 33., 65., 193., 285.]
    # fcst_thds = [30.,35.,40.,45.,50.,55.]
    wd = 3
    th = 3

    time_series_efss_mpas(outdir, wefbs[:, :, :,wd,th], wefbsr[:,:,:,wd,th], wfbs[:,:,:,:,wd,th], wfbsr[:,:,:,:,wd,th],
            mefbs[:, :, :, wd,th], mefbsr[:,:,:,wd,th], mfbs[:,:,:,:,wd,th], mfbsr[:,:,:,:,wd,th], wscales[0,0,wd], wmrms_thlds[0,0,0,th], exper, year1, year2)
