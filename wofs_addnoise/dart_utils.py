import numpy as np
import sys  #, os, glob
#import datetime as dtime
#import xarray as xr      #netcdf4 is faster, and we dont need xarray features
import netCDF4 as ncdf
from netCDF4 import chartostring
import time as timeit
#from scipy.spatial import KDTree
from pyproj import Transformer

#try:
#    import _pickle as pickle
#except:
#    import pickle

debug = True

#__missing = -9999.
__gravity = 9.806

#-------------------------------------------------------------------------------
# WRF File variable dictionary

wrf_var_dict = { 'u': 'U', 'v': 'V', 'w': 'W', 'pb': 'P_HYD', 'pp': 'P',
                 'ph': 'ph', 'phb': 'phb', 'th': 'T', 'qv': 'QV',
                 'refl': 'REF_10CM', 'lat': 'XLAT', 'lon': 'XLONG' }

#-------------------------------------------------------------------------------
# MPAS File variable dictionary

mpas_var_dict = { 'w': 'w', 'z': 'zgrid', 'th': 'theta', 'qv': 'qv',
                 'pb': 'pressure_base', 'pp': 'pressure_p',
                'refl': 'ref10cm', 'lat': 'latcell', 'lon': 'loncell' }

#-------------------------------------------------------------------------------
#
def read_model_grid(model_file, model_type='wrf', model_attrib=None, write_new_file=True):

    #-------------------------------------------------------------------------------
    # ===> BEGIN: MODEL FIELDS and CREATE LOCATION ARRAYS

    if model_type == 'mpas':

        print(f"  model_file = {model_file}")
        file, var, _, = read_netcdf(model_file)

        nz    = file.dimensions['nVertLevels'].size
        nCell = file.dimensions['nCells'].size

        latCell     = np.rad2deg(np.squeeze(var['latCell'][...]))
        lonCell     = np.rad2deg(np.squeeze(var['lonCell'][...]))
        zgrid       = np.squeeze(var['zgrid'][...])
        #mod_refl    = np.squeeze(var['refl10cm'][...]).flatten()

        # create zone-centered vertical grid values and flatten array

        hgt3D = (0.5*(zgrid[:,1:] + zgrid[:,:-1])).flatten()

        # make sure that lons are between 0 and 360 degress

        lonCell = np.where( lonCell < 0.0,   lonCell+360., lonCell)
        lonCell = np.where( lonCell > 360.0, lonCell-360., lonCell)

        # map model lat/lon into physical distance in meters

        model_transformer = mapping_transform(latCell.mean(), lonCell.mean())

        xCell, yCell = model_transformer.transform(lonCell, latCell)

        # close mpas file

        file.close()

        nx = nCell
        ny = 0

    else: # wrf model

        file, ds, attrib = read_netcdf(model_file)

        nz = file.dimensions['bottom_top'].size
        nx = file.dimensions['west_east'].size
        ny = file.dimensions['south_north'].size

        latCell  = np.squeeze(ds['XLAT'][...]).transpose().flatten()
        lonCell  = np.squeeze(ds['XLONG'][...]).transpose().flatten()
        phb      = np.squeeze(ds['PHB'][...])
        #mod_refl = np.squeeze(ds['REFL_10CM'][...]).transpose().flatten()

        # create zone-centered vertical grid locations

        hgt3D = (0.5*(phb[1:] + phb[:-1]) / __gravity).transpose().flatten()

        if debug:  print('\n WRF MODEL GRID: NZ = %d  NY = %d  NX = %d' % (phb.shape[:]))

        # make sure that lons are between 0 and 360 degress

        lonCell = np.where( lonCell < 0.0,   lonCell+360., lonCell)
        lonCell = np.where( lonCell > 360.0, lonCell-360., lonCell)

        # map model lat/lon into physical distance in meters

        model_transformer = mapping_transform(attrib('CEN_LAT'), attrib('CEN_LON'), debug=False)

        xCell, yCell = model_transformer.transform(lonCell, latCell)

        # close wrf file

        file.close()

    xCell3D = np.dstack([xCell]*nz).flatten()
    yCell3D = np.dstack([yCell]*nz).flatten()

    return xCell3D, yCell3D, hgt3D, model_transformer, latCell, lonCell, nx, ny, nz

#-------------------------------------------------------------------------------
#
def write_model_grid(model_grid_file, model_file, noise, sd, model_type='wrf', write_new_file=True):

    ts0      = 300.
    ps0      = 1.0e5
    Cp       = 1004.
    Cv       = 787.
    Rd       = 257.
    Rv       = 461.
    kappa    = 2.0 / 7.0
    t_kelvin = 273.16
    rd_o_rv  = Rd / Rv
    cp_o_cv  = Cp / Cv


#     val = np.log(vapor_pressure / mpconsts.nounit.sat_pressure_0c)
#     return mpconsts.nounit.zero_degc + 243.5 * val / (17.67 - val)
    #-------------------------------------------------------------------------------
    def compute_td(p, qv):

        e = qv * p / (0.622 + qv)                         # vapor pressure
        e = np.where(e > 0.001, e, 0.001)
        val = np.log(e / 6.112)              # avoid problems near zero
        return t_kelvin + (243.5 * val / (17.67 - val) )  # Bolton's approximation

    #-------------------------------------------------------------------------------
    def compute_qv(p, td):
        tdc = td - t_kelvin
        e = 6.112 * np.exp( 17.67 * tdc / (tdc + 243.5) )       # Bolton's approximation
        return (0.622 * e / (p-e))

    nflds = sd.size

    if debug:
        print(" ADD_NOISE - NFLDS: ", nflds)

    #-------------------------------------------------------------------------------
    # ===> BEGIN: MODEL FIELDS and CREATE LOCATION ARRAYS

    if model_type == 'mpas':

        time0 = timeit.time()

        mpas_vars = ['u', 'v', 'w', 'theta', 'td', 'qv']

        print(f"\n Model_grid_file = {model_grid_file},\n Model_file = {model_file}")

        ds = ncdf.Dataset(model_file, 'r+')
        ds.set_auto_mask(False)

        nz    = ds.dimensions['nVertLevels'].size
        nCell = ds.dimensions['nCells'].size
        nEdge = ds.dimensions['nEdges'].size

        noise = noise.reshape(nCell, nz, nflds)

        with ncdf.Dataset(model_grid_file, "r") as dg:   # need to use this to mask lateral boundaries

            bdyMaskCell = dg.variables['bdyMaskCell'][...]
            ic          = np.where(bdyMaskCell == 0)[0]    # this is the lists of non-boundary zones

        noise[ic,:,:] = 0.0  # set noise == 0 in boundary zones

        for n, var in enumerate(mpas_vars):

            if np.abs(sd[n]) > 0.0:

                if var == 'u':

                    time1 = timeit.time()

                    u = noise[:,:,n]
                    v = noise[:,:,n+1]  # now have cell centered 2D noise arrays

                    with ncdf.Dataset(model_grid_file, "r") as nc:

                        # 1-based -> 0-based; MPAS uses 0 as the sentinel for a missing cell
                        # on a boundary edge, so subtract 1 only for valid (> 0) entries.

                        coe_raw = nc.variables["cellsOnEdge"][:].astype(np.int32)   # (nEdges, 2)
                        cells_on_edge = coe_raw - 1                                  # now -1 = boundary

                        tangent_plane = np.asarray( nc.variables["cellTangentPlane"][:], dtype=np.float64)   # (nCells, 2, 3)
                        edge_normals = np.asarray(nc.variables["edgeNormalVectors"][:], dtype=np.float64)  # (nEdges, 3)

                    is_zero = np.allclose(tangent_plane, 0)
                    if is_zero:
                        print(f" \n ERROR:  Add_Noise_High_Refl:  cellTangentPlane array is uninitialized!!")
                        print(f" \n Cannot reconstruct winds - trying using MPAS init file")
                        print(f" \n Skippng u additive noise\n")
                        continue


                    n_edges = cells_on_edge.shape[0]
                    n_bdy   = int(np.sum(np.any(cells_on_edge < 0, axis=1)))

                    n_cells, n_levels = u.shape[0:2]
                    n_edges           = cells_on_edge.shape[0]

                    east  = tangent_plane[:, 0, :]   # (nCells, 3)
                    north = tangent_plane[:, 1, :]   # (nCells, 3)

                    # ------------------------------------------------------------------
                    # Step 1: Cartesian velocity at every cell center
                    #   U[i,k] * east[i,j]  +  V[i,k] * north[i,j]
                    #   = einsum 'ik,ij->ikj' + 'ik,ij->ikj'
                    # Result: (nCells, nVertLevels, 3)

                    vec_cell = ( u[:, :, None] * east[:, None, :]    # (nCells, nLevels, 3)
                             +   v[:, :, None] * north[:, None, :] )

                    # Append a zero-vector row so that index -1 (boundary sentinel) maps to
                    # a zero contribution rather than wrapping to the last real cell.
                    # Shape after pad: (nCells+1, nVertLevels, 3), last row = 0

                    zero_row = np.zeros((1, n_levels, 3), dtype=np.float64)
                    vec_padded = np.concatenate([vec_cell, zero_row], axis=0)  # (nCells+1, nLev, 3)

                    # ------------------------------------------------------------------
                    # Step 2: Average cell vectors across the two neighbors of each edge
                    #
                    # cells_on_edge has values in [-1, nCells-1].
                    # After padding, index nCells (the appended row) = zero vector,
                    # so we remap -1 -> nCells.

                    c = cells_on_edge.copy()                      # (nEdges, 2)
                    c[c < 0] = n_cells                            # boundary sentinel -> zero row

                    # Gather: (nEdges, 2, nVertLevels, 3)

                    vec_neighbors = vec_padded[c]                 # fancy index on first axis

                    # Count valid neighbors per edge: interior=2, boundary=1
                    # valid mask: True where the original index was >= 0

                    valid = (cells_on_edge >= 0).astype(np.float64)   # (nEdges, 2)

                    # Weighted average: sum / n_valid
                    # Expand valid to (nEdges, 2, 1, 1) for broadcasting

                    n_valid = valid.sum(axis=1, keepdims=True)                       # (nEdges, 1)
                    w       = (valid / n_valid)[:, :, None, None]                    # (nEdges, 2, 1, 1)

                    # vec_edge: (nEdges, nVertLevels, 3)

                    vec_edge = (w * vec_neighbors).sum(axis=1)

                    # ------------------------------------------------------------------
                    # Step 3: Project onto edge unit normal
                    #   u[e, k] = dot( vec_edge[e, k, :], edge_normals[e, :] )
                    #           = einsum 'ekj,ej->ek'

                    ds.variables['u'][0] += np.einsum("ekj,ej->ek", vec_edge, edge_normals)   # (nEdges, nVertLevels)

                    print("\n Elapsed time to add noise to the MPAS U-field is:  %f seconds\n" % (timeit.time() - time1))

                elif var == 'v':
                    pass

                elif var == 'w':
                    ds.variables[var][0, ic, 1:-1] += 0.5*(noise[ic,1:,n] + noise[ic,:-1,n])

                elif var == 'td':  # lots of work here....
                    th   = ds.variables['theta'][0]
                    qv   = ds.variables['qv'][0]
                    pres = 0.01 * ds.variables['pressure_base'][0]
                    temp = th * ds.variables['exner'][0]

                    td   = compute_td(pres, qv)
                    td  += noise[:,:,n]
                    td   = np.where(temp+4.0 > td, td, temp+4.0)  # limit td supersaturation to T+4 deg.

                    ds.variables['qv'][0,ic] += (compute_qv(pres, td) - qv)[ic]

                else:
                    ds.variables[var][0,ic] += noise[ic,:,n]

                if debug:  print(" Added noise to %s " % var)

            else:

                if debug:  print(" Did NOT ADD noise to %s " % var)

        ds.close()

        print("\n Elapsed time to add noise to the MPAS state is:  %f seconds" % (timeit.time() - time0))

    else:

        time0 = timeit.time()

        wrf_vars = ['U', 'V', 'W', 'T', 'TD', 'QV']

        ds = ncdf.Dataset(model_file, 'r+')

        nz = ds.dimensions['bottom_top'].size
        nx = ds.dimensions['west_east'].size
        ny = ds.dimensions['south_north'].size

        noise = noise.reshape(nx, ny, nz, nflds).transpose()

        for n, var in enumerate(wrf_vars):

            if np.abs(sd[n]) > 0.0:

                if var == 'U':
                    ds.variables[var][0, :, :, 1:-1] += 0.5*(noise[n,:,:,1:] + noise[n,:,:,:-1])

                elif var == 'V':
                    ds.variables[var][0, :, 1:-1, :] += 0.5*(noise[n,:,1:,:] + noise[n,:,:-1,:])

                elif var == 'W':
                    ds.variables[var][0, 1:-1, :, :] += 0.5*(noise[n,1:,:,:] + noise[n,:-1,:,:])

                elif var == 'TD':  # lots of work here....
                    th   = np.squeeze(ds.variables['T'][...]) + ts0
                    qv   = np.squeeze(ds.variables['QVAPOR'][...])
                    pres = 0.01 * np.squeeze(ds.variables['P_HYD'][...])
                    temp = (ts0 + th) * (100.0*pres/ps0)**kappa

                    td   = compute_td(pres, qv)
                    td  += noise[n]

                    td   = np.where(temp+4.0 > td, td, temp+4.0)  # limit td supersaturation to T+4 deg.

                    ds.variables['QVAPOR'][0] += (compute_qv(pres, td) - qv)

                else:
                    ds.variables[var][0] += noise[n]

                if debug:  print(" Added noise to %s " % var)

            else:

                if debug:  print(" Did NOT ADD noise to %s " % var)

        # close wrf file

        ds.close()

        print(" Elapsed time to add noise to the WRF state is:  %f seconds" % (timeit.time() - time0))

    return

#-------------------------------------------------------------------------------
#
def mapping_transform(meanlat, meanlon, debug=False):

    # map projection for converting lat,lon to meters

    proj_daymet = "+proj=lcc +lat_0=%f +lon_0=%f +lat_1=30 +lat_2=60 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs" \
                % (meanlat, meanlon)

    if debug:  print("\n String passed to map projection: "+proj_daymet+"\n")
    return  Transformer.from_crs("EPSG:4326", proj_daymet, always_xy=True)

#-------------------------------------------------------------------------------
#
def read_netcdf(filename, debug=False):

    file = ncdf.Dataset(filename, 'r')

    return file, file.variables, file.getncattr

#-------------------------------------------------------------------------------
#
def obs_seq_get_obtype(ds, list_obs_types=False, kind=None, name=None, refl_thresh=None, debug=False):

    """ obs_seq_get_obtype reads observations from the obs_seq netCDF4 file created
        during cycling data assimilation
    """

    routine_name = 'obs_seq_get_obtype'.upper()
    print('\n ------------------ %s has been called -----------------------\n' % routine_name)


    if list_obs_types:
        list_set = set(ds['obs_type'][...].tolist())
        unique_list = (list(list_set))

        for item in unique_list:
            idx = ds['ObsTypes'].to_numpy()[item]
            print(" OBS TYPE INDEX: %3.3d  OBS_TYPE: %s" % (idx, ds['ObsTypesMetaData'][...][item].decode()))

        return None

    if name:
        idx  = np.where(chartostring(ds['ObsTypesMetaData'][...])== name)[0]
        kind = np.array(ds['ObsTypes'])[idx]
        meta = name

    if kind == None:
        print(" OBS_SEQ_GET_OBTYPE:  no kind or name specified, exiting \n")
        sys.exit(-1)

    else:
        index_type = np.where(ds['obs_type'][...] == kind)

        print(" FOUND %d OBS FOR VARIABLE: %s\n" % (np.sum(ds['obs_type'][...] == kind), meta))

        if refl_thresh != None:

            refl = ds['observations'][...][index_type]
            index_thresh = np.where(refl[:,0] >= refl_thresh)

            print(" FOUND %d OBS FOR REFL_THRES >=  %f for VARIABLE: %s\n" % (len(index_thresh[0]), refl_thresh, meta.decode()))

            idx = index_thresh[0]

        else:
            idx = index_type[0]


        if len(idx) > 0:

            return {'obs':        ds['observations'][...][idx],
                    'location':   ds['location'][...][idx],
                    'qc':         ds['location'][...][idx],
                    'which_vert': ds['location'][...][idx],
                    'time':       ds['time'][...][idx]}
        else:
            return {'obs':        None,
                    'location':   None,
                    'qc':         None,
                    'which_vert': None,
                    'time':       None}

#-------------------------------------------------------------------------------
#
def obs_seq_get_CopyMetaDataIndex(ds, meta_name=None, list=False, all=False, debug=False):

    if list:
        print(chartostrong(ds['CopyMetaData']))

    if all:
        return chartostring(ds['CopyMetaData'])

    else:
        metalist  = chartostring(ds['CopyMetaData'][...]).tolist()
        ret_index = []

        for n, item in enumerate(metalist):
            try:
                if meta_name.index(item) >= 0:
                    ret_index.append(n)
            except:
                pass
        return ret_index

#-------------------------------------------------------------------------------
# ===> BEGIN: READ OBS SEQUENCE FILE
def seq_get_refl(obsfile, refl_thresh=None, debug=False):

    __obs_radar_reflectivity = 'RADAR_REFLECTIVITY              '
    __ens_prior_mean         = 'prior ensemble mean             '
    __observation            = 'NCEP BUFR observation           '

    _, ds_obs, _, = read_netcdf(obsfile, debug=debug)

    refl = obs_seq_get_obtype(ds_obs, name = __obs_radar_reflectivity, debug=debug)

    if refl['obs'] is None:
        print(f"\n ERROR: Observation type: {__obs_radar_reflectivity} not found.")
        print(" ---------------------------------------------------\n")
        sys.exit(99)

    yobs, Hxmean = obs_seq_get_CopyMetaDataIndex(ds_obs, meta_name = (__observation, __ens_prior_mean), debug=debug)

    if debug:
        print("\n Index of %s = %d" % (__observation, yobs))
        print(" Index of %s = %d\n" % (__ens_prior_mean,Hxmean))

    # close obs file

    return yobs, Hxmean, refl

# ===> END: READ OBS SEQUENCE FILE

#-------------------------------------------------------------------------------
#
def ioda_get_refl(ioda_file, refl_thresh=None, debug=False):
    """
    ioda_get_refl reads radar reflectivity observations from an IODA v2 diagnostic
    netCDF file (e.g. jdiag_mrms_refl.nc) and returns a dict with the same structure
    as obs_seq_get_obtype(), so that it can be used as a drop-in replacement for the
    DART obs-sequence reader in grid_refl_obs.py.

    IODA group mapping
    ------------------
    ObsValue/equivalentReflectivityFactor       -> observed reflectivity        (dBZ)
    hofx_y_mean_xb0/equivalentReflectivityFactor -> prior mean H(xb)           (dBZ)
    ombg/equivalentReflectivityFactor           -> innovation (obs - H(xb))    (dBZ)
    MetaData/latitude                           -> latitude  (degrees_north, -90..90)
    MetaData/longitude                          -> longitude (degrees_east,  -180..180)
    MetaData/height                             -> height above MSL           (metres)

    Returned dict
    -------------
    'obs'        : ndarray (N, 2)  col-0 = observed dBZ  (equiv. to yobs   column)
                                   col-1 = prior mean     (equiv. to Hxmean column)
    'location'   : ndarray (N, 3)  col-0 = longitude 0..360 (DART convention)
                                   col-1 = latitude
                                   col-2 = height (m MSL)
    'qc'         : ndarray (N,)    EffectiveQC0 values (0 = passed)
    'which_vert' : None            (not applicable for IODA)
    'time'       : ndarray (N,)    dateTime (seconds since 1970-01-01)

    Parameters
    ----------
    ioda_file   : str   Path to the IODA diagnostic netCDF file.
    refl_thresh : float Optional lower bound on observed reflectivity (dBZ).
                        Observations below this threshold are excluded.
    debug       : bool  If True, print summary statistics.

    Returns
    -------
    dict with keys 'obs', 'location', 'qc', 'which_vert', 'time', or
    a dict with all values set to None if no observations pass the filters.
    """

    routine_name = 'IODA_GET_REFL'
    print('\n ------------------ %s has been called -----------------------\n' % routine_name)
    print(' Reading IODA file: %s\n' % ioda_file)

    _VARNAME = 'equivalentReflectivityFactor'

    ds = ncdf.Dataset(ioda_file, 'r')

    try:
        obs_var     = ds.groups['ObsValue'].variables[_VARNAME]
        hofx_var    = ds.groups['hofx_y_mean_xb0'].variables[_VARNAME]
        lat_var     = ds.groups['MetaData'].variables['latitude']
        lon_var     = ds.groups['MetaData'].variables['longitude']
        hgt_var     = ds.groups['MetaData'].variables['height']
        dt_var      = ds.groups['MetaData'].variables['dateTime']

        obs_raw  = obs_var[:].filled(np.nan).astype(np.float64)
        hofx_raw = hofx_var[:].filled(np.nan).astype(np.float64)
        lat_raw  = lat_var[:].filled(np.nan).astype(np.float64)
        lon_raw  = lon_var[:].filled(np.nan).astype(np.float64)
        hgt_raw  = hgt_var[:].filled(np.nan).astype(np.float64)
        dt_raw   = dt_var[:].filled(-9999).astype(np.int64)

        # Read QC if available, otherwise default to zero (pass)
        try:
            qc_raw = ds.groups['EffectiveQC0'].variables[_VARNAME][:].filled(999).astype(np.int32)
        except Exception:
            qc_raw = np.zeros(obs_raw.shape, dtype=np.int32)

    finally:
        ds.close()

    # --- mask: require all fields to be finite and QC == 0 ----------------------
    valid = (np.isfinite(obs_raw)  &
             np.isfinite(hofx_raw) &
             np.isfinite(lat_raw)  &
             np.isfinite(lon_raw)  &
             np.isfinite(hgt_raw)  &
             (qc_raw == 0))
    #valid = (np.isfinite(obs_raw)  &
    #         np.isfinite(hofx_raw) &
    #         np.isfinite(lat_raw)  &
    #         np.isfinite(lon_raw)  &
    #         np.isfinite(hgt_raw) )

    # --- optional reflectivity threshold ----------------------------------------
    if refl_thresh is not None:
        valid &= (obs_raw >= refl_thresh)
        print(' Applied refl_thresh >= %.1f dBZ' % refl_thresh)

    idx = np.where(valid)[0]
    n_total = obs_raw.size
    n_valid = idx.size

    print(' Total locations in file  : %d' % n_total)
    print(' Locations passing filters: %d\n' % n_valid)

    if n_valid == 0:
        return {'obs': None, 'location': None, 'qc': None,
                'which_vert': None, 'time': None}

    obs_out  = obs_raw[idx]
    hofx_out = hofx_raw[idx]
    lat_out  = lat_raw[idx]
    lon_out  = lon_raw[idx]
    hgt_out  = hgt_raw[idx]
    qc_out   = qc_raw[idx]
    dt_out   = dt_raw[idx]

    # --- convert longitude from -180..180 to 0..360 (DART/MPAS convention) ------
    lon_out = np.where(lon_out < 0.0, lon_out + 360.0, lon_out)

    # --- build obs array: col-0 = observation, col-1 = prior mean ---------------
    obs_array       = np.empty((n_valid, 2), dtype=np.float64)
    obs_array[:, 0] = obs_out    # yobs   column (observation)
    obs_array[:, 1] = hofx_out   # Hxmean column (prior mean H(xb))

    # --- location array: [lon(0..360), lat, height(m MSL)] ----------------------
    location_array = np.stack([lon_out, lat_out, hgt_out], axis=1)

    if debug:
        print(' OBS    (dBZ):  min=%8.3f  max=%8.3f' % (obs_out.min(),  obs_out.max()))
        print(' H(xb)  (dBZ):  min=%8.3f  max=%8.3f' % (hofx_out.min(), hofx_out.max()))
        print(' LON (0-360) :  min=%8.3f  max=%8.3f' % (lon_out.min(), lon_out.max()))
        print(' LAT         :  min=%8.3f  max=%8.3f' % (lat_out.min(), lat_out.max()))
        print(' HEIGHT (m)  :  min=%8.1f  max=%8.1f\n' % (hgt_out.min(), hgt_out.max()))

    return 0,1, {'obs':        obs_array,
                 'location':   location_array,
                 'qc':         qc_out,
                 'which_vert': None,
                 'time':       dt_out}
