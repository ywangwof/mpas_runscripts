#!/usr/bin/env python3

import os
from contextlib import redirect_stderr

# geoviews may print a deprecation message during uxarray import on some systems.
# Keep output clean by muting stderr only for this import.

with open(os.devnull, "w") as _devnull, redirect_stderr(_devnull):
    import uxarray as ux

import matplotlib
matplotlib.use('Agg') # Force non-interactive backend

import xarray as xr
import matplotlib.pyplot as plt
import matplotlib.collections as mcoll
import matplotlib.colors as mcolors
import argparse
import numpy as np
import cartopy.crs as ccrs
import cartopy.feature as cfeature
from metpy.plots import ctables
from pathlib import Path
import time
import re
import traceback
import multiprocessing
from concurrent.futures import ProcessPoolExecutor
from netCDF4 import Dataset

# UI Libraries
try:
    from tqdm import tqdm
except ImportError:
    tqdm = None

try:
    from rich.console import Console
    from rich.table import Table
except ImportError:
    Console = None

# Memory tracking
try:
    import psutil
except ImportError:
    psutil = None

########################################################################
def get_memory_usage():
    if psutil:
        process = psutil.Process(os.getpid())
        return process.memory_info().rss / (1024 * 1024)
    return 0.0

########################################################################
# Decode filename time
def decode_filename_time(filename):
    pattern = r"(\d{4}-\d{2}-\d{2}_\d{2}[\.:]\d{2}[\.:]\d{2})"
    match = re.search(pattern, filename)
    if match:
        return match.group(1).replace('.', ':')
    return None

########################################################################
# Log error
def log_error(msg):
    with open("error_log.txt", "a") as f:
        f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - {msg}\n")
        
################################################################################
#
# Created with help from claude ai

def mpas_reconstruct_1d(mesh_grid, data_grid, timeIndex = 0, addTimeAxis=True):

    """

    Fully vectorized version of mpas_reconstruct_1d from MPAS fortran code 
    
    Source code location:  MPAS/src/operators/mpas_vector_reconstruction.F
    Subroutine routine mpas_reconstruct_1d

    Notes
    -----
    1. Assumes that raw MPAS u-array winds for reconstruction has dimensions (nCells, nz).
    2. Requires that the coeffs_reconstruct array not be zero for proper reconstruction.
    3. For fields that have more than one time level, user needs to pass in timeIndex


    Required Inputs  
    ---------------
    MPAS mesh grid netCDF file
    MPAS data grid information
    

    Optional Input
    --------------
    
    indexTime = int():  Default is 0, but user can ask for any valid time level if u is truely 3D   
    addTimeAxis==True : expands U_Zonal and U_Meridonal to add a leading time dimension

    Output
    ------
    Returns two arrays having the zonal and meridional winds


    ToDo
    ----
    Make it so time dimension can be != 1, so U and V can be recreated from multiple time steps


    """

    with Dataset(data_grid, 'r') as nc:
        u = np.asarray(nc.variables['u'][timeIndex,:].squeeze(), dtype=np.float64)
        
    with Dataset(mesh_grid, 'r') as nc:

        nEdgesOnCell = nc.variables["nEdgesOnCell"][:].astype(np.int32)
 
        # MPAS stores 1-based Fortran indices — convert to 0-based

        edgesOnCell = nc.variables["edgesOnCell"][:].astype(np.int32) - 1
 
        # RBF reconstruction weight vectors, shape (nCells, maxEdges, R3)

        coeffs_reconstruct = np.asarray(nc.variables["coeffs_reconstruct"][:], dtype=np.float64)
        
        latCell = np.asarray(nc.variables["latCell"][:], dtype=np.float64)
        lonCell = np.asarray(nc.variables["lonCell"][:], dtype=np.float64)
 
    is_zero = np.allclose(coeffs_reconstruct, 0)
    if is_zero:
        print(f" \n MPAS_RECONSTRUCT_1D:  coeffs_reconstruct array is uninitialized!!")
        print(f" \n Cannot reconstruct winds - trying using MPAS init file")
        print(f" \n Return zero arrays for U_Zonal and U_Merid")

        u_zonal = np.zeros_like(u)
        u_merid = np.zeros_like(u)
        
    else:
        
        # start calculations
        
        uReconstructX = np.zeros((latCell.shape[0], u.shape[1]))  # (nCells, nVertLevels,)
        uReconstructY = np.zeros((latCell.shape[0], u.shape[1]))
        uReconstructZ = np.zeros((latCell.shape[0], u.shape[1]))
    
        nCells = latCell.shape[0]
    
        # This algorithm is converted from fortran using MPAS source code
        # Location:  MPAS/src/operators/mpas_vector_reconstruction.F
        # Subroutine routine mpas_reconstruct_1d

        for iCell in range(nCells):
    
            n       = nEdgesOnCell[iCell]
            edges   = edgesOnCell[iCell, :n]            # (n,)
            coeffs  = coeffs_reconstruct[iCell, :n, :]  # (n, 3)
            u_edges = u[edges, :]                       # (n, nVertLevels)
        
            uReconstructX[iCell, :] = coeffs[:, 0] @ u_edges  # (nVertLevels,)
            uReconstructY[iCell, :] = coeffs[:, 1] @ u_edges 
            uReconstructZ[iCell, :] = coeffs[:, 2] @ u_edges

        clat = np.cos(latCell)   # (nCells,)
        slat = np.sin(latCell)   # (nCells,)
        clon = np.cos(lonCell)   # (nCells,)
        slon = np.sin(lonCell)   # (nCells,)

        u_zonal = (- uReconstructX * slon[:, None]
                   + uReconstructY * clon[:, None])

        u_merid = (-(uReconstructX * clon[:, None]
                   + uReconstructY * slon[:, None]) * slat[:, None]
                   + uReconstructZ * clat[:, None])

    if addTimeAxis:
        return xr.DataArray(u_zonal[np.newaxis,:,:], dims=['Time','nCells','nVertLevels'],
                            name='U_Zonal', attrs={'units': 'm s^-1'}), \
               xr.DataArray(u_merid[np.newaxis,:,:], dims=['Time','nCells','nVertLevels'],
                            name='U_Merid', attrs={'units': 'm s^-1'})
    else:
        return xr.DataArray(u_zonal, dims=['nCells','nVertLevels'],
                            name='U_Zonal', attrs={'units': 'm s^-1'}), \
               xr.DataArray(u_merid, dims=['nCells','nVertLevels'],
                            name='U_Merid', attrs={'units': 'm s^-1'})
        

########################################################################
# Get command line arguments
def get_args():
    parser = argparse.ArgumentParser(description="Parallel MPAS Plotter (Multi-Grid Support)")
    parser.add_argument("data_file", help="Path to the MPAS netCDF file")
    parser.add_argument("fieldnames", help="Comma-separated fields")
    parser.add_argument("-g", "--grid_file", help="Optional grid file")
    parser.add_argument("-l", "--levels", default="0", help="Comma-separated levels (e.g. '0,5,10')")
    parser.add_argument("-t", "--time", type=int, default=0, help="Time index")
    parser.add_argument("--min", type=float, help="Min override")
    parser.add_argument("--max", type=float, help="Max override")
    parser.add_argument("--inc", type=float, help="Inc override")
    parser.add_argument("-o", "--output", type=str, help="Output prefix")
    parser.add_argument("--dpi", type=int, default=600, help="DPI")
    parser.add_argument("-n", "--nproc", type=int, help="Processors")
    return parser.parse_args()

#######################################################################
def get_plot_settings(fieldname, cmin=None, cmax=None, cinc=None):
    cmap = "turbo"
    norm = None
    if fieldname.startswith("refl"):
        cmap = ctables.registry.get_colortable("NWSReflectivity")
        if all(v is None for v in [cmin, cmax, cinc]):
            levels = np.arange(0, 80, 5.0)
            norm = mcolors.BoundaryNorm(levels, cmap.N)
        elif cmin is not None and cmax is not None:
            step = cinc if cinc is not None else (cmax - cmin) / 10
            levels = np.arange(cmin, cmax + step, step)
            norm = mcolors.BoundaryNorm(levels, cmap.resampled(int(len(levels)-1)).N if len(levels)-1 > cmap.N else cmap.N)
    elif fieldname.startswith(("rain", "prec_")):
        cmap = plt.get_cmap("YlGnBu")
        if all(v is None for v in [cmin, cmax, cinc]):
            prec_levels = [0, 1, 2.5, 5, 7.5, 10, 15, 20, 30, 40, 50, 70, 100, 150, 200, 250, 300, 400, 500, 600, 750]
            norm = mcolors.BoundaryNorm(prec_levels, cmap.N)
        elif cmin is not None and cmax is not None:
            step = cinc if cinc is not None else (cmax - cmin) / 10
            levels = np.arange(cmin, cmax + step, step)
            norm = mcolors.BoundaryNorm(levels, cmap.N)
    elif "soil" in fieldname.lower() or "t_so" in fieldname.lower():
        cmap = plt.get_cmap("terrain")

    if norm is None and cmin is not None and cmax is not None:
        if cinc is not None:
            levels = np.arange(cmin, cmax + cinc, cinc)
            norm = mcolors.BoundaryNorm(levels, 256)
        else:
            norm = mcolors.Normalize(vmin=cmin, vmax=cmax)
    return cmap, norm

#######################################################################
def plot_mpas_worker(task_info):

    fieldname, level, grid_source, data_file, args_dict, file_timestamp = task_info

    t_start = time.time()

    try:
        uxds = ux.open_dataset(grid_source, data_file)

        if fieldname == 'u_zonal' or fieldname == 'u_merid':   # this allows us to plot v-wind
            data_var = uxds['u']
        else:
            data_var = uxds[fieldname]

        units = getattr(data_var, 'units', '') # Extract units metadata

        # --- Flexible Dimension Selection ---
        known_v_dims = ["nVertLevels", "nVertLevelsP1", "nSoilLevels", "nLevels"]
        v_dim = next((d for d in known_v_dims if d in data_var.dims), None)
        dim_to_axis = {dim: i for i, dim in enumerate(data_var.dims)}

        if fieldname == 'u_zonal' or fieldname == 'u_merid':  # if u or v are requested, compute nodal recontructed winds

            print(f"\n ---> Reconstructing U & V from raw MPAS u \n")
            u, v = mpas_reconstruct_1d(grid_source, data_file) 

            is_zero = np.allclose(u, 0) and np.allclose(v, 0)
            if is_zero:
                print(f" \n Reconstruct_Winds_Vectorized returned all zeros, probaby something wrong")
                sys.exit(1)

            if fieldname == 'u_zonal':
                data_var  = u
                plot_data = u.values
            else:
                data_var  = v
                plot_data = v.values

        else:
            plot_data = data_var.values

        if "Time" in dim_to_axis:
            t_axis = dim_to_axis["Time"]
            plot_data = np.take(plot_data, args_dict['time'], axis=t_axis)
            dim_to_axis = {d: i for i, d in enumerate([d for d in data_var.dims if d != "Time"])}

        if v_dim and v_dim in dim_to_axis:
            v_axis = dim_to_axis[v_dim]
            plot_data = np.take(plot_data, level, axis=v_axis)

        plot_data = plot_data.squeeze()

        # Statistics for Title (5 significant digits)
        data_min = float(f"{np.nanmin(plot_data):.5g}")
        data_max = float(f"{np.nanmax(plot_data):.5g}")

        horiz_dim_aliases = {
            "nCells": ["nCells", "n_face"],
            "nEdges": ["nEdges", "n_edge"],
            "nVertices": ["nVertices", "n_node"],
        }
        horiz_dim = None
        horiz_dim_key = None
        for key, aliases in horiz_dim_aliases.items():
            match = next((d for d in aliases if d in data_var.dims), None)
            if match is not None:
                horiz_dim = match
                horiz_dim_key = key
                break

        if horiz_dim is None:
            raise ValueError(f"Unsupported horizontal dimension for {fieldname}: {data_var.dims}")

        if fieldname == 'u_zonal' or fieldname == 'u_merid':

            n_horiz_expected = int(data_var.sizes[horiz_dim])

        else:

            n_horiz_expected = int(data_var.sizes[horiz_dim])
            if plot_data.size != n_horiz_expected:
                raise ValueError(
                    f"Unexpected flattened size for {fieldname}: got {plot_data.size}, "
                    f"expected {n_horiz_expected} from '{horiz_dim}'"
                )

        faces = np.asarray(uxds.uxgrid.face_node_connectivity.values, dtype=np.int64)
        nodes_lon, nodes_lat = uxds.uxgrid.node_lon.values, uxds.uxgrid.node_lat.values
        if np.abs(nodes_lat).max() <= (np.pi + 0.1):
            nodes_lon, nodes_lat = np.rad2deg(nodes_lon), np.rad2deg(nodes_lat)
        nodes_lon = (nodes_lon + 180) % 360 - 180

        cmap, norm = get_plot_settings(fieldname, args_dict['min'], args_dict['max'], args_dict['inc'])
        fig = plt.figure(figsize=(14, 10))
        ax = plt.axes(projection=ccrs.PlateCarree())
        ax.add_feature(cfeature.COASTLINE, linewidth=0.8); ax.add_feature(cfeature.STATES.with_scale('50m'), alpha=0.3)

        if horiz_dim_key == "nCells":
            lon_sent = np.append(nodes_lon, np.nan); lat_sent = np.append(nodes_lat, np.nan)
            faces[faces < 0] = len(nodes_lon)
            f_lons = np.take(lon_sent, faces); f_lats = np.take(lat_sent, faces)
            verts = [np.column_stack((l[~np.isnan(l)], t[~np.isnan(t)])) for l, t in zip(f_lons, f_lats)]
            mappable = mcoll.PolyCollection(verts, array=plot_data, cmap=cmap, norm=norm, edgecolors='none', antialiaseds=True)
            ax.add_collection(mappable)
        elif horiz_dim_key == "nEdges":
            edges = np.asarray(uxds.uxgrid.edge_node_connectivity.values, dtype=np.int64)
            if edges.shape[0] != plot_data.size:
                raise ValueError(
                    f"Edge connectivity/data size mismatch for {fieldname}: "
                    f"{edges.shape[0]} edges vs {plot_data.size} values"
                )
            seg_lon = np.take(nodes_lon, edges)
            seg_lat = np.take(nodes_lat, edges)
            segments = np.stack((seg_lon, seg_lat), axis=2)
            mappable = mcoll.LineCollection(segments, array=plot_data, cmap=cmap, norm=norm, linewidths=0.7)
            ax.add_collection(mappable)
        else:
            if "lonVertex" in uxds and "latVertex" in uxds:
                vertices_lon = uxds["lonVertex"].values
                vertices_lat = uxds["latVertex"].values
                if np.abs(vertices_lat).max() <= (np.pi + 0.1):
                    vertices_lon = np.rad2deg(vertices_lon)
                    vertices_lat = np.rad2deg(vertices_lat)
                vertices_lon = (vertices_lon + 180) % 360 - 180
            else:
                vertices_lon = nodes_lon
                vertices_lat = nodes_lat

            if vertices_lon.size != plot_data.size:
                raise ValueError(
                    f"Vertex coordinate/data size mismatch for {fieldname}: "
                    f"{vertices_lon.size} vertices vs {plot_data.size} values"
                )
            mappable = ax.scatter(vertices_lon, vertices_lat, c=plot_data, cmap=cmap, norm=norm, s=4, linewidths=0, transform=ccrs.PlateCarree())

        ax.set_extent([np.min(nodes_lon)-0.5, np.max(nodes_lon)+0.5, np.min(nodes_lat)-0.5, np.max(nodes_lat)+0.5], crs=ccrs.PlateCarree())
        plt.colorbar(mappable, ax=ax, shrink=0.7, pad=0.03, label=units)

        display_time = file_timestamp if file_timestamp else f"T{args_dict['time']}"

        # Updated Title with Units and Statistics
        unit_str = f" [{units}]" if units else ""
        title_str = f"MPAS  {display_time}   {fieldname}{unit_str} ({horiz_dim_key}; Min: {data_min}, Max: {data_max})"
        if v_dim:
            title_str += f"   |   Level: {level}"
        ax.set_title(title_str)

        out_name = f"{Path(data_file).stem}_{fieldname}" + (f"_T{args_dict['time']}" if "Time" in data_var.dims else "") + (f"_L{level}" if v_dim else "")
        output_file = f"{args_dict['output']}_{fieldname}_L{level}.png" if args_dict['output'] else f"{out_name}.png"
        plt.savefig(output_file, dpi=args_dict['dpi'], bbox_inches='tight')
        plt.close(fig)

        return {"field": fieldname, "level": level, "status": "Success", "time": time.time()-t_start, "memory": get_memory_usage(), "file": output_file}

    except Exception as e:
        err_msg = f"Error plotting {fieldname} L{level}:\n{traceback.format_exc()}"
        log_error(err_msg)
        return {"field": fieldname, "level": level, "status": "Failed (see log)", "time": time.time()-t_start, "memory": get_memory_usage(), "file": "N/A"}

########################################################################

def main():
    args = get_args()
    grid_source = args.grid_file if args.grid_file else args.data_file
    file_timestamp = decode_filename_time(Path(args.data_file).name)
    fields = [f.strip() for f in args.fieldnames.split(',')]
    levels = [int(l.strip()) for l in args.levels.split(',')]

    tasks = [(f, l, grid_source, args.data_file, vars(args), file_timestamp) for f in fields for l in levels]
    n_cores = args.nproc if args.nproc else multiprocessing.cpu_count()
    n_workers = min(n_cores, len(tasks))

    if os.path.exists("error_log.txt"): os.remove("error_log.txt")
    print(f"Submitting {len(tasks)} tasks to {n_workers} processors...")

    results = []
    if n_workers > 1:
        with ProcessPoolExecutor(max_workers=n_workers) as executor:
            if tqdm:
                results = list(tqdm(executor.map(plot_mpas_worker, tasks), total=len(tasks), desc="Plotting MPAS"))
            else:
                results = list(executor.map(plot_mpas_worker, tasks))
    else:
        for t in tasks:
            results.append(plot_mpas_worker(t))

    if Console:
        console = Console()
        table = Table(title="MPAS Plotting Job Summary", header_style="bold magenta")
        table.add_column("Field"); table.add_column("Level"); table.add_column("Status");
        table.add_column("Time (s)"); table.add_column("Mem (MB)"); table.add_column("Output File")
        for r in results:
            color = "green" if "Success" in r['status'] else "red"
            table.add_row(r['field'], str(r['level']), f"[{color}]{r['status']}[/{color}]", f"{r['time']:.2f}", f"{r['memory']:.1f}", r['file'])
        console.print(table)
    if os.path.exists("error_log.txt"):
        print("\n[!] Some tasks failed. Detailed errors saved to: error_log.txt")

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

if __name__ == "__main__":
    main()
