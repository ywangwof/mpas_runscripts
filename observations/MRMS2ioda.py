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

from scipy.spatial import cKDTree, ConvexHull, Delaunay
from matplotlib.path import Path

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
obserrlist = [5.0]
#obserrvalue = 5.0

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


def read_namelist_mosaic(namelist_file):
    """Parse a Fortran namelist file and return clear-air threshold values."""
    import re
    result = {'clear_air_dbz_thresh': 0.0, 'clear_air_dbz_value': 0.0}
    try:
        with open(namelist_file, 'r') as f:
            content = f.read()
        for key in result:
            m = re.search(rf'\b{key}\s*=\s*([+-]?\d+\.?\d*)', content, re.IGNORECASE)
            if m:
                result[key] = float(m.group(1))
        logging.info(f"Read from {namelist_file}: clear_air_dbz_thresh={result['clear_air_dbz_thresh']}, "
                     f"clear_air_dbz_value={result['clear_air_dbz_value']}")
    except FileNotFoundError:
        logging.warning(f"Namelist file '{namelist_file}' not found, using defaults: {result}")
    return result['clear_air_dbz_thresh'], result['clear_air_dbz_value']


def main(file_names, output_file, obstime, clear_air_dbz_thresh=0.0, clear_air_dbz_value=0.0, output_clear_file=None):

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

    ##
    ## Keep only observations within the MPAS domain - WYH
    ##
    ## Observations within the MPAS domain
    #keep_idx = find_indices_kdtree(data['latitude'], data['longitude'], latvs, lonvs, tolerance=2e-2)

    ##
    ## Remove observations over the boundary zone - WYH
    ##
    #for bdymask in bdyMasks:
    #    #print(bdyMask,': ',bdyLons[bdyMask].size,bdyLats[bdyMask].size)
    #    idx = find_indices_kdtree(data['latitude'], data['longitude'], bdyLats[bdymask], bdyLons[bdymask], tolerance=1.6e-2)
    #    remove_set = set(idx)
    #    keep_idx = [i for i in keep_idx if i not in remove_set]

    keep_idx = check_obs_within_domain(bdyLons[1],bdyLats[1],data['longitude'], data['latitude'], )
    logging.info(f"Number of points inside MPAS domain: {len(keep_idx)}")

    # Split into precipitation and clear-air observations based on clear_air_dbz_thresh
    refl_vals = np.array([data['equivalentReflectivityFactor'][i] for i in keep_idx])
    precip_mask   = refl_vals > clear_air_dbz_thresh
    clear_mask    = refl_vals <= clear_air_dbz_thresh
    precip_idx    = np.array(keep_idx)[precip_mask]
    clear_air_idx = np.array(keep_idx)[clear_mask]
    logging.info(f"Precipitation obs: {len(precip_idx)}, clear-air obs: {len(clear_air_idx)}")

    # --- Write precipitation observations to main output file ---
    nlocs = len(precip_idx)

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
        obs_data[(key, metaDataName)] = np.array([data[key][i] for i in precip_idx], dtype=dtypes[dtypestr])

    obserr = np.full(nlocs, obserrlist[0], dtype=np.float32)

    # Transfer from the 1-D data vectors and ensure output data (obs_data) types using numpy.
    for n, iodavar in enumerate(obsvars):
        obs_data[(iodavar, obsValName)] = np.array([data[iodavar][i] for i in precip_idx], dtype=np.float32)
        obs_data[(iodavar, obsErrName)] = obserr                        #np.full(nlocs, obserrlist[n], dtype=np.float32)
        obs_data[(iodavar, qcName)] = np.full(nlocs, 2, dtype=np.int32)
        #varAttrs[(iodavar, obsValName)]['_FillValue'] = float_missing_value

    VarDims = {}
    for vname in obsvars:
        VarDims[vname] = ['Location']

    logging.debug(f"Writing precipitation output file: {output_file}")

    # setup the IODA writer
    writer = iconv.IodaWriter(output_file, locationKeyList, DimDict)

    # write everything out
    writer.BuildIoda(obs_data, VarDims, varAttrs, AttrData)

    # --- Write clear-air observations to a separate output file ---
    if output_clear_file and len(clear_air_idx) > 0:
        clear_vname = 'equivalentReflectivityFactor_clear'
        clear_obs_data = {}
        clear_varDict = defaultdict(lambda: DefaultOrderedDict(dict))
        clear_varAttrs = DefaultOrderedDict(lambda: DefaultOrderedDict(dict))
        nlocs_clear = len(clear_air_idx)
        clear_DimDict = {'Location': nlocs_clear}

        clear_varDict[clear_vname]['valKey'] = clear_vname, obsValName
        clear_varDict[clear_vname]['errKey'] = clear_vname, obsErrName
        clear_varDict[clear_vname]['qcKey'] = clear_vname, qcName
        clear_varAttrs[clear_vname, obsValName]['coordinates'] = 'longitude latitude'
        clear_varAttrs[clear_vname, obsErrName]['coordinates'] = 'longitude latitude'
        clear_varAttrs[clear_vname, qcName]['coordinates'] = 'longitude latitude'
        clear_varAttrs[clear_vname, obsValName]['units'] = obsvars_units[0]
        clear_varAttrs[clear_vname, obsErrName]['units'] = obsvars_units[0]

        for key in meta_keys:
            dtypestr = locationKeyList[meta_keys.index(key)][1]
            if locationKeyList[meta_keys.index(key)][2]:
                clear_varAttrs[(key, metaDataName)]['units'] = locationKeyList[meta_keys.index(key)][2]
            clear_obs_data[(key, metaDataName)] = np.array([data[key][i] for i in clear_air_idx], dtype=dtypes[dtypestr])

        clear_obserr = np.full(nlocs_clear, obserrlist[0], dtype=np.float32)
        clear_obs_data[(clear_vname, obsValName)] = np.full(nlocs_clear, clear_air_dbz_value, dtype=np.float32)
        clear_obs_data[(clear_vname, obsErrName)] = clear_obserr
        clear_obs_data[(clear_vname, qcName)] = np.full(nlocs_clear, 2, dtype=np.int32)

        clear_VarDims = {clear_vname: ['Location']}
        clear_AttrData = dict(AttrData)
        clear_AttrData['description'] = 'Clear-air MRMS radar reflectivity'

        logging.debug(f"Writing clear-air output file: {output_clear_file}")
        clear_writer = iconv.IodaWriter(output_clear_file, locationKeyList, clear_DimDict)
        clear_writer.BuildIoda(clear_obs_data, clear_VarDims, clear_varAttrs, clear_AttrData)
        logging.info(f"Wrote {nlocs_clear} clear-air obs to {output_clear_file}")


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

def define_mpas_inner_boundary_Path(domain_lons,domain_lats):
    """Suppose the domain is roughly circular or rectangular and has no large indentations.
    use Rubber Band method (Convex Hull)
    domain_lons/domain_lats in 1D
    """

    #import numpy as np

    # 1. Stack your arrays into (N, 2)
    # format: [[lon, lat], [lon, lat], ...]
    points = np.column_stack((domain_lons, domain_lats))

    # 2. Compute the Convex Hull
    hull = ConvexHull(points)

    # 3. Get the boundary vertices in order
    # hull.vertices gives indices of points that form the boundary
    boundary_points = points[hull.vertices]

    # 4. Create a Path for checking
    polygon_path = Path(boundary_points)

    return polygon_path

########################################################################

def check_obs_within_domain(boundary_lons, boundary_lats, obs_lons,obs_lats):
    """Ray Casting Algorithm"""

    # --- 1. Define the Polygon Boundary (The Domain) ---

    # Create the Path object
    polygon_path = define_mpas_inner_boundary_Path(boundary_lons,boundary_lats)


    # --- 2. Define the Grid Points to Check ---
    # Flatten the grid arrays to create a list of points (N, 2)
    # We flatten because 'contains_points' expects a simple list of (x, y) pairs
    points = np.column_stack((obs_lons, obs_lats))

    # --- 3. Perform the Check ---
    # returns a boolean array (True if inside, False if outside)
    mask_points = polygon_path.contains_points(points)

    print(f"Number of points inside MPAS domain: {np.sum(mask_points)}/{len(obs_lons)}")

    # --- 4. Extract Indices ---
    # You can now use the boolean mask to get the Indices

    return np.where(mask_points)[0]


#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

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
    optional.add_argument('-n', '--namelist', dest='namelist_file',
                          action='store', default='namelist.mosaic',
                          help='Fortran namelist file for clear-air thresholds (default: namelist.mosaic)')
    optional.add_argument('--output-clear-file', dest='output_clear_file',
                          action='store', default=None,
                          help='output file for clear-air reflectivity observations')

    args = parser.parse_args()

    if args.debug:
        logging.basicConfig(level=logging.INFO)
    elif args.verbose:
        logging.basicConfig(level=logging.DEBUG)
    else:
        logging.basicConfig(level=logging.ERROR)

    bdyMasks=(1,)
    bdyLons, bdyLats, lonvs, latvs = get_mpas_boundaries(args.grid_file,bdyMasks)  # boundaries and boundary spec

    for file_name in args.file_names:
        if not os.path.isfile(file_name):
            parser.error('Input (-i option) file: ', file_name, ' does not exist')

    clear_air_dbz_thresh, clear_air_dbz_value = read_namelist_mosaic(args.namelist_file)

    main(args.file_names, args.output_file, args.radartime,
         clear_air_dbz_thresh=clear_air_dbz_thresh,
         clear_air_dbz_value=clear_air_dbz_value,
         output_clear_file=args.output_clear_file)
