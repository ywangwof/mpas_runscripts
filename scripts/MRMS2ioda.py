#!/usr/bin/env python3
'''
 This script converts Multi-radar, multi-sensor (MRMS) radar reflectivity from OU-MAP's netCDF format
 into IODA's netCDF format.
 Authors: Yongming Wang & Xuguang Wang @ OUMAP/CADRE, poc: yongming.wang@ou.edu, xuguang.wang@ou.edu
'''

import pyiodaconv.ioda_conv_engines as iconv
from collections import defaultdict
from pyiodaconv.orddicts import DefaultOrderedDict
import netCDF4 as nc
import numpy as np
from datetime import datetime
import os
import logging
import warnings
warnings.simplefilter("ignore")
import sys
import math
from scipy.spatial import cKDTree

# These modules need the path to lib-python modules

os.environ["TZ"] = "UTC"

locationKeyList = [
    ("latitude", "float", "degrees_north"),
    ("longitude", "float", "degrees_east"),
    ("height", "float", "m"),
    ("dateTime", "long", "seconds since 1970-01-01T00:00:00Z"),
]
meta_keys = [m_item[0] for m_item in locationKeyList]

obsvars_units = ['dBZ']
obserrlist = [50.0]
obserrvalue = 5.0

AttrData = {
    'converter': os.path.basename(__file__),
    'ioda_version': 2,
    'description': 'Multi-radar, multi-sensor (MRMS) radar reflectivity',
    'source': 'NOAA',
    'sourceFiles': ''
}

DimDict = {
}

iso8601_string = locationKeyList[meta_keys.index('dateTime')][2]
epoch = datetime.fromisoformat(iso8601_string[14:-1])

metaDataName = iconv.MetaDataName()
obsValName = iconv.OvalName()
obsErrName = iconv.OerrName()
qcName = iconv.OqcName()

float_missing_value = -999.0    # or netCDF value,  nc.default_fillvals['f4']
int_missing_value = nc.default_fillvals['i4']
double_missing_value = nc.default_fillvals['f8']
long_missing_value = nc.default_fillvals['i8']
string_missing_value = '_'

missing_vals = {'string': string_missing_value,
                'integer': int_missing_value,
                'long': long_missing_value,
                'float': float_missing_value,
                'double': double_missing_value}

dtypes = {'string': object,
          'integer': np.int32,
          'long': np.int64,
          'float': np.float32,
          'double': np.float64}


def main(file_names, output_file, obstime):

    # Initialize
    varDict = defaultdict(lambda: DefaultOrderedDict(dict))
    varAttrs = DefaultOrderedDict(lambda: DefaultOrderedDict(dict))

    obs_data = {}          # The final outputs.
    data = {}              # Before assigning the output types into the above.

    obsvars = []
    vname = 'equivalentReflectivityFactor'
    obsvars.append(vname)

    for key in meta_keys:
        data[key] = []

    for key in obsvars:
        data[key] = []

    dt = datetime.fromisoformat(obstime)

    # Loop through input files, reading data.
    nlocs = 0
    for fname in file_names:
        AttrData['sourceFiles'] += ", " + fname

        heights, lat, lon, vars_mrms = read_netcdf(fname, obsvars)

        time_offset = round((dt - epoch).total_seconds())

        nobs = len(lat)
        nlocs = nlocs + nobs
        logging.info(f" adding {nobs} data locations for total of {nlocs}")
        x = np.full(nobs, time_offset)
        data['dateTime'].extend(x.tolist())
        data['height'].extend(heights)
        data['latitude'].extend(lat)
        data['longitude'].extend(lon)
        data['equivalentReflectivityFactor'].extend(vars_mrms)

    AttrData['sourceFiles'] = AttrData['sourceFiles'][2:]
    logging.debug("All source files: " + AttrData['sourceFiles'])

    DimDict = {'Location': nlocs}

    # Set coordinates and units of the ObsValues.
    for n, iodavar in enumerate(obsvars):
        varDict[iodavar]['valKey'] = iodavar, obsValName
        varDict[iodavar]['errKey'] = iodavar, obsErrName
        varDict[iodavar]['qcKey'] = iodavar, qcName
        varAttrs[iodavar, obsValName]['coordinates'] = 'longitude latitude'
        varAttrs[iodavar, obsErrName]['coordinates'] = 'longitude latitude'
        varAttrs[iodavar, qcName]['coordinates'] = 'longitude latitude'
        varAttrs[iodavar, obsValName]['units'] = obsvars_units[n]
        varAttrs[iodavar, obsErrName]['units'] = obsvars_units[n]

    # Set units of the MetaData variables and all _FillValues.
    for key in meta_keys:
        dtypestr = locationKeyList[meta_keys.index(key)][1]
        if locationKeyList[meta_keys.index(key)][2]:
            varAttrs[(key, metaDataName)]['units'] = locationKeyList[meta_keys.index(key)][2]
        #varAttrs[(key, metaDataName)]['_FillValue'] = missing_vals[dtypestr]
        obs_data[(key, metaDataName)] = np.array(data[key], dtype=dtypes[dtypestr])

    obserr = np.full(nlocs, obserrlist[0], dtype=np.float32)
    # Observations within the MPAS domain
    idx = find_indices_kdtree(data['latitude'], data['longitude'], latvs, lonvs, tolerance=2e-2)
    obserr[idx] = obserrvalue

    # Observations over the boundary zone
    for bdymask in bdyMasks:
        #print(bdyMask,': ',bdyLons[bdyMask].size,bdyLats[bdyMask].size)
        idx = find_indices_kdtree(data['latitude'], data['longitude'], bdyLats[bdymask], bdyLons[bdymask], tolerance=1.6e-2)
        obserr[idx] = obserrvalue+bdymask*obserrvalue

    # Transfer from the 1-D data vectors and ensure output data (obs_data) types using numpy.
    for n, iodavar in enumerate(obsvars):
        obs_data[(iodavar, obsValName)] = np.array(data[iodavar], dtype=np.float32)
        obs_data[(iodavar, obsErrName)] = obserr                        #np.full(nlocs, obserrlist[n], dtype=np.float32)
        obs_data[(iodavar, qcName)] = np.full(nlocs, 2, dtype=np.int32)
        #varAttrs[(iodavar, obsValName)]['_FillValue'] = float_missing_value

    VarDims = {}
    for vname in obsvars:
        VarDims[vname] = ['Location']

    logging.debug(f"Writing output file: {output_file}")

    # setup the IODA writer
    writer = iconv.IodaWriter(output_file, locationKeyList, DimDict)

    # write everything out
    writer.BuildIoda(obs_data, VarDims, varAttrs, AttrData)


def read_netcdf(input_file, obsvars):
    logging.debug(f"Reading file: {input_file}")

    mrms_data = {}

    # Open and read Gridded_ref.nc
    file_mrms = input_file
    nc_file = nc.Dataset(file_mrms, 'r')

    # Access dimensions, variables, and attributes
    nlat_mrms = len(nc_file.dimensions['latitude'])
    nlon_mrms = len(nc_file.dimensions['longitude'])
    nlev_mrms = len(nc_file.dimensions['height'])
    print(f"\nDimensions of mrms reflectivity in {file_mrms}:")
    for dim in nc_file.dimensions:
        print(f" - {dim}: {len(nc_file.dimensions[dim])}")

    lat_mrms = nc_file.variables["latitude"][:]
    lon_mrms = nc_file.variables["longitude"][:]
    hgt_mrms = nc_file.variables['height'][:]
    lon_mrms = np.where(lon_mrms > 180.0, lon_mrms - 360.0, lon_mrms)
    print(f"\nlat_mrms range: {np.amin(lat_mrms)}  {np.amax(lat_mrms)}")
    print(f"lon_mrms range: {np.amin(lon_mrms)}  {np.amax(lon_mrms)}")
    print(f"hgt_mrms range: {np.amin(hgt_mrms)}  {np.amax(hgt_mrms)}")

    mrms_refl3d = nc_file.variables['reflectivity'][:]
    print(f"mrms_refl3d range: {np.amin(mrms_refl3d)}  {np.amax(mrms_refl3d)}")
    nc_file.close()

    mrms_refl3d = mrms_refl3d.reshape(nlat_mrms * nlon_mrms * nlev_mrms).astype('float')
    mrms_refl3d = np.where(np.logical_and(mrms_refl3d > -100.0, mrms_refl3d < 0), 0.0, mrms_refl3d)

    mask = np.logical_and(mrms_refl3d > -1.0, mrms_refl3d <= 80.0)
    if mask is not None:
        mrms_data = mrms_refl3d[mask]

    mrms_data = mrms_data.tolist()
    print(f"mrms_data range: {np.amin(mrms_data)}  {np.amax(mrms_data)}")

    heights = np.empty([nlev_mrms, nlat_mrms, nlon_mrms], dtype='float')
    lons = np.empty([nlev_mrms, nlat_mrms, nlon_mrms], dtype='float')
    lats = np.empty([nlev_mrms, nlat_mrms, nlon_mrms], dtype='float')

    for ihgt in range(nlev_mrms):
        heights[ihgt, :, :] = hgt_mrms[ihgt]

    for ilon in range(nlon_mrms):
        lons[:, :, ilon] = lon_mrms[ilon]

    for ilat in range(nlat_mrms):
        lats[:, ilat, :] = lat_mrms[ilat]

    heights = heights.reshape(nlat_mrms * nlon_mrms * nlev_mrms).astype('float')
    lons = lons.reshape(nlat_mrms * nlon_mrms * nlev_mrms).astype('float')
    lats = lats.reshape(nlat_mrms * nlon_mrms * nlev_mrms).astype('float')
    if mask is not None:
        heights = heights[mask]
        lons = lons[mask]
        lats = lats[mask]

    heights = heights.tolist()
    lons = lons.tolist()
    lats = lats.tolist()

    return heights, lats, lons, mrms_data

########################################################################

def get_mpas_boundaries(filename, bdymasks):

    f = nc.Dataset(filename)

    latVertex = np.ma.getdata(f.variables['latVertex'][:]) * 180.0 / math.pi
    lonVertex = np.ma.getdata(f.variables['lonVertex'][:]) * 180.0 / math.pi - 360.0
    bdyMaskVertex = np.ma.getdata(f.variables['bdyMaskVertex'][:])
    #edgesOnVertex = np.ma.getdata(f.variables['edgesOnVertex'][:]) - 1
    #verticesOnEdge = np.ma.getdata(f.variables['verticesOnEdge'][:]) - 1

    f.close()

    bdyLats = {}
    bdyLons = {}
    for bdyMask in bdymasks:
        bdyLats[bdyMask] = []
        bdyLons[bdyMask] = []

    #print(bdyMaskVertex.size,)
    for startVertex in range(bdyMaskVertex.size):
        for bdyMask in bdymasks:
            if bdyMaskVertex[startVertex] == bdyMask:
                bdyLons[bdyMask].append(lonVertex[startVertex])
                bdyLats[bdyMask].append(latVertex[startVertex])

    for bdyMask in bdymasks:
        bdyLons[bdyMask] = np.asarray(bdyLons[bdyMask])
        bdyLats[bdyMask] = np.asarray(bdyLats[bdyMask])

    return bdyLons, bdyLats, lonVertex, latVertex

########################################################################

def find_indices_kdtree(Lats, Lons, bdyLats, bdyLons, tolerance=1e-5):
    """
    Finds indices in (Lats, Lons) that match points in (bdyLats, bdyLons)
    within a tolerance using Euclidean distance.
    """
    # 1. Stack the large arrays into an (N, 2) array of coordinates
    #    Assumption: Lats and Lons are 1D arrays of the same length
    large_points = np.column_stack((Lats, Lons))

    # 2. Stack the boundary arrays into an (M, 2) array
    bdy_points = np.column_stack((bdyLats, bdyLons))

    # 3. Build the KDTree on the LARGE dataset
    tree = cKDTree(large_points)

    # 4. Query the tree for boundary points within the tolerance radius
    #    query_ball_point returns a list of lists (indices neighbors for each bdy point)
    matches = tree.query_ball_point(bdy_points, r=tolerance)

    # 5. Flatten the list of lists into a single array of unique indices
    #    We use unique because multiple boundary points might be close to the same large point
    indices = np.unique(np.concatenate(matches)).astype(int)

    return indices

########################################################################

if __name__ == "__main__":

    import argparse

    parser = argparse.ArgumentParser(
        description=(
            'Read netcdf formatted MRMS file and convert into IODA output file')
    )

    required = parser.add_argument_group(title='required arguments')
    required.add_argument('-i', '--input-files', nargs='+', dest='file_names',
                          action='store', default=None, required=True,
                          help='input files')
    required.add_argument('-o', '--output-file', dest='output_file',
                          action='store', default=None, required=True,
                          help='output file')

    required.add_argument('-c', '--radar-time', dest='radartime',
                          action='store', default=None, required=True,
                          help='radar obs time format: 2020-01-01T00:00:00')

    required.add_argument('-g', '--grid-file', dest='grid_file',
                          action='store', default=None, required=True,
                          help='MPAS grid file name to handle boundary zone')

    parser.set_defaults(debug=False)
    parser.set_defaults(verbose=False)
    optional = parser.add_argument_group(title='optional arguments')
    optional.add_argument('--debug', action='store_true',
                          help='enable debug messages')
    optional.add_argument('--verbose', action='store_true',
                          help='enable verbose debug messages')

    args = parser.parse_args()

    if args.debug:
        logging.basicConfig(level=logging.INFO)
    elif args.verbose:
        logging.basicConfig(level=logging.DEBUG)
    else:
        logging.basicConfig(level=logging.ERROR)

    bdyMasks=(1,2,3,4,5,6,7)
    bdyLons, bdyLats, lonvs, latvs = get_mpas_boundaries(args.grid_file,bdyMasks)  # boundaries and boundary spec

    for file_name in args.file_names:
        if not os.path.isfile(file_name):
            parser.error('Input (-i option) file: ', file_name, ' does not exist')

    main(args.file_names, args.output_file, args.radartime)
