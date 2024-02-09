#!/home/yunheng.wang/tools/micromamba/envs/wofs_an/bin/python
"""convert prepbufr file to netCDF"""
from __future__ import print_function
import ncepbufr
import numpy as np
import netCDF4
import sys

########################################################################

def bufr2nc(bufr,nc,skiptypes):
    '''
    Read bufr message from PrepBufr file handler 'bufr' and
    write messages to netCDF file handler 'nc', skip obs type in 'skiptypes'
    if requested.
    '''
    bufr_obj = {}
    # find total number of messages, analysis date
    nmessages = 0
    while bufr.advance() == 0: # loop over messages.
        if bufr.msg_type in skiptypes: continue
        nmessages += 1
    bufr.rewind()

    bufr_obj['nmessages'] = nmessages
    bufr_obj['msgtypes']  = {}

    # mnemonics to extract data from prepbufr file.
    hdstr='SID XOB YOB DHR TYP ELV SAID T29'
    obstr='POB QOB TOB ZOB UOB VOB PWO CAT PRSS TDO PMO XDR YDR HRDR'
    qcstr='PQM QQM TQM ZQM WQM PWQ PMQ'
    oestr='POE QOE TOE ZOE WOE PWE'

    # create netcdf dimensions
    hd = nc.createDimension('hdrinfo',len(hdstr.split())); nhdd = len(hd)
    ob = nc.createDimension('obinfo',len(obstr.split()));  nobd = len(ob)
    oe = nc.createDimension('oeinfo',len(oestr.split()));  noed = len(oe)
    qc = nc.createDimension('qcinfo',len(qcstr.split()));  nqcd = len(qc)
    nobsd = nc.createDimension('nobs',None)
    nmsgs = nc.createDimension('nmsgs',nmessages)
    str1len = nc.createDimension('nchar_id',256)
    str2len = nc.createDimension('nchar_type',20)

    # create netcdf variables.
    hdrdata = nc.createVariable('header',np.float64,('nobs','hdrinfo'), fill_value=bufr.missing_value,zlib=True,chunksizes=(nobs_chunk,nhdd))
    hdrdata.desc = 'observation header data'
    for key in hdstr.split():
        hdrdata.setncattr(key,ncepbufr.prepbufr_mnemonics_dict[key])
    hdrdata.hdrinfo = hdstr

    obid = nc.createVariable('obid','S1',('nobs','nchar_id',),zlib=True)
    obid.desc = 'observation id (station id/type code/lon/lat/time/elevation/pressure)'

    obdata = nc.createVariable('obdata',np.float32,('nobs','obinfo'), fill_value=bufr.missing_value,zlib=True,chunksizes=(nobs_chunk,nobd))
    # mnemonic descriptions as variable attributes.
    for key in obstr.split():
        obdata.setncattr(key,ncepbufr.prepbufr_mnemonics_dict[key])
    obdata.obinfo = obstr
    obdata.desc = 'observation data'

    oedata = nc.createVariable('oberr',np.float32,('nobs','oeinfo'), fill_value=bufr.missing_value,zlib=True,chunksizes=(nobs_chunk,noed))
    for key in oestr.split():
        oedata.setncattr(key,ncepbufr.prepbufr_mnemonics_dict[key])
    oedata.oeinfo = oestr
    oedata.desc = 'observation error data'

    qc_fillval = 255
    qcdata = nc.createVariable('qcdata',np.uint8,('nobs','qcinfo'), fill_value=qc_fillval,zlib=True,chunksizes=(nobs_chunk,nqcd))
    for key in qcstr.split():
        qcdata.setncattr(key,ncepbufr.prepbufr_mnemonics_dict[key])
    qcdata.qcinfo = qcstr
    qcdata.desc = 'observation QC data'

    msgnum = nc.createVariable('msgnum',np.uint32,('nobs'), zlib=True,chunksizes=(nobs_chunk,))
    msgnum.desc = 'bufr message number'

    subsetnum = nc.createVariable('subsetnum',np.uint16,('nobs'), zlib=True,chunksizes=(nobs_chunk,))
    subsetnum.desc='subset number within bufr message'

    msgtype = nc.createVariable('msgtype','S1',('nmsgs','nchar_type'),zlib=True)
    msgtype.desc='bufr message type'

    msgdate = nc.createVariable('msgdate',np.uint32,('nmsgs'),zlib=True)
    msgdate.desc='bufr message date'

    # read prepbufr data, write to netcdf.
    nob = 0
    obid_set = set()
    nmsg = 0
    while bufr.advance() == 0:                      # loop over messages.
        if bufr.msg_type in skiptypes: continue

        # lists to hold data from each subset in message.
        hdrarr = []; obsarr = []; qcarr = []; errarr = []; obidarr = []
        msgnumarr = []; subsetnumarr = []
        nobs_message = 0
        nsubset = 0
        #print(netCDF4.stringtochar(np.array([bufr.msg_type], 'S20')))
        if bufr.msg_type not in bufr_obj['msgtypes'].keys():
            bufr_obj['msgtypes'][bufr.msg_type] = 0

        nc['msgtype'][nmsg,:] = netCDF4.stringtochar(np.array([bufr.msg_type], 'S20'))
        nc['msgdate'][nmsg] = bufr.msg_date
        nmsg += 1
        while bufr.load_subset() == 0:    # loop over subsets in message.
            nsubset += 1
            hdr = bufr.read_subset(hdstr).squeeze()
            obs = bufr.read_subset(obstr)
            qc  = bufr.read_subset(qcstr)
            err = bufr.read_subset(oestr)

            nlevs_use = 0
            for nlev in range(obs.shape[-1]):
                lon = hdr[1]; lat = hdr[2]; time = hdr[3]
                press = obs[0,nlev]; z = hdr[5]
                # use balloon drift lat/lon/time for sondes, pibals in obid string.
                if hdr[4] in [120,220,221]:
                    lon = obs[11,nlev]; lat = obs[12,nlev]
                    # only use drift corrected time if it is within assimilation window.
                    if obs[13,nlev] >= time_min and obs[13,nlev] < time_max:
                        time = obs[13,nlev]
                elif hdr[4] >= 223 and hdr[4] <= 228:
                    z = obs[3,nlev] # use zob, not station elev
                obidstr = "%s %3i %6.2f %6.2f %9.5f %5i %6.1f" % (hdr[0].tobytes(), hdr[4], lon, lat, time, z, press)
                # skip ob if there is already a matching obid string
                # (do we need more checking here to make sure obs are really duplicates?)
                if obidstr not in obid_set:
                    obid_set.add(obidstr)
                else:
                    print('skipping duplicate ob %s' % obidstr)
                    continue
                hdrarr.append(hdr.squeeze())
                obidarr.append(obidstr)
                obsarr.append(obs[:,nlev])
                errarr.append(err[:,nlev])
                qcarr.append(qc[:,nlev])
                msgnumarr.append(nmsg)
                subsetnumarr.append(nsubset)
                nob += 1; nlevs_use += 1
            nobs_message += nlevs_use # obs for this message

        bufr_obj['msgtypes'][bufr.msg_type] += nobs_message

        # make lists into arrays.
        hdrarr = np.array(hdrarr); obsarr = np.array(obsarr)
        errarr = np.array(errarr); qcarr = np.array(qcarr)
        obidarr = np.array(obidarr); msgnumarr = np.array(msgnumarr)
        subsetnumarr = np.array(subsetnumarr)
        qcarr = np.where(qcarr == bufr.missing_value,qc_fillval,qcarr).astype(np.uint8)

        # write all the data for this message
        nob1 = nob-nobs_message
        print('writing message %s out of %s, type %s with %s obs' % (nmsg,nmessages,bufr.msg_type,nobs_message))
        nc['header'][nob1:nob] = hdrarr
        nc['obdata'][nob1:nob] = obsarr
        nc['oberr'][nob1:nob]  = errarr
        nc['qcdata'][nob1:nob] = qcarr
        for i in range(0,len(obidarr)):
            obid_str = netCDF4.stringtochar(np.array([obidarr[i]],'S256'))
            nc['obid'][nob1+i,:] = obid_str
        nc['msgnum'][nob1:nob] = msgnumarr
        nc['subsetnum'][nob1:nob] = subsetnumarr
        nc.sync() # dump data to disk.

    return bufr_obj

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

if __name__ == "__main__":
    # write obs in nobs_chunk chunks for better compression.
    # nobs_chunk should not be less than the total number of obs in the bufr file.
    nobs_chunk = 200

    # min/max times in assim window
    time_min = -3.0; time_max = 3.0

    if len(sys.argv) < 3:
        raise SystemExit('prepbufr2nc <input prepbufr> <output netcdf>')

    # input and output file names from command line args.
    prepbufr_filename = sys.argv[1]
    netcdf_filename = sys.argv[2]
    if prepbufr_filename == netcdf_filename:
        raise IOError('cannot overwrite input prepbufr file')

    # skip these report types
    #skiptypes = []
    skiptypes = ['SATWND'] # sat winds in a separate bufr file.

    # open prepbufr file.
    bufr = ncepbufr.open(prepbufr_filename)

    # open netcdf file
    nc = netCDF4.Dataset(netcdf_filename,'w',format='NETCDF4')

    bufrobj = bufr2nc(bufr,nc,skiptypes)

    print(f"Total number message in the PrepBufr file: {bufrobj['nmessages']}")
    for k,v in bufrobj['msgtypes'].items():
        print(f"    {k} ({v})")

    # close files.
    bufr.close(); nc.close()
