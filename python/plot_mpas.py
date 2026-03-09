#!/usr/bin/env python3

import uxarray as ux
import matplotlib.pyplot as plt
import matplotlib.collections as mcoll
import matplotlib.colors as mcolors
import argparse
import numpy as np
import cartopy.crs as ccrs
import cartopy.feature as cfeature
from metpy.plots import ctables
from pathlib import Path
import sys
import time
import os
import re
import traceback
import multiprocessing
from concurrent.futures import ProcessPoolExecutor

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

################################################################################
def get_memory_usage():
    if psutil:
        process = psutil.Process(os.getpid())
        return process.memory_info().rss / (1024 * 1024)
    return 0.0

def decode_filename_time(filename):
    pattern = r"(\d{4}-\d{2}-\d{2}_\d{2}[\.:]\d{2}[\.:]\d{2})"
    match = re.search(pattern, filename)
    if match:
        return match.group(1).replace('.', ':')
    return None

def log_error(msg):
    with open("error_log.txt", "a") as f:
        f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - {msg}\n")

################################################################################
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

################################################################################
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
        cmap = plt.get_cmap("terrain") # Good for soil fields

    if norm is None and cmin is not None and cmax is not None:
        if cinc is not None:
            levels = np.arange(cmin, cmax + cinc, cinc)
            norm = mcolors.BoundaryNorm(levels, 256)
        else:
            norm = mcolors.Normalize(vmin=cmin, vmax=cmax)
    return cmap, norm

################################################################################
def plot_mpas_worker(task_info):
    fieldname, level, grid_source, data_file, args_dict, file_timestamp = task_info
    t_start = time.time()
    try:
        uxds = ux.open_dataset(grid_source, data_file, engine="netcdf4")
        data_var = uxds[fieldname]

        # --- Robust Vertical Dimension Detection ---
        v_dim = None
        known_v_dims = ["nVertLevels", "nVertLevelsP1", "nSoilLevels"]
        for dim in known_v_dims:
            if dim in data_var.dims:
                v_dim = dim
                break

        selectors = {d: (args_dict['time'] if d == "Time" else level) for d in data_var.dims if d in (["Time"] + known_v_dims)}
        plot_data = data_var.isel(selectors).values.squeeze()

        faces = np.asarray(uxds.uxgrid.face_node_connectivity.values, dtype=np.int64)
        nodes_lon, nodes_lat = uxds.uxgrid.node_lon.values, uxds.uxgrid.node_lat.values
        if np.abs(nodes_lat).max() <= (np.pi + 0.1):
            nodes_lon, nodes_lat = np.rad2deg(nodes_lon), np.rad2deg(nodes_lat)
        nodes_lon = (nodes_lon + 180) % 360 - 180

        lon_sent = np.append(nodes_lon, np.nan); lat_sent = np.append(nodes_lat, np.nan)
        faces[faces < 0] = len(nodes_lon)
        f_lons = np.take(lon_sent, faces); f_lats = np.take(lat_sent, faces)
        verts = [np.column_stack((l[~np.isnan(l)], t[~np.isnan(t)])) for l, t in zip(f_lons, f_lats)]

        cmap, norm = get_plot_settings(fieldname, args_dict['min'], args_dict['max'], args_dict['inc'])
        fig = plt.figure(figsize=(14, 10))
        ax = plt.axes(projection=ccrs.PlateCarree())
        ax.add_feature(cfeature.COASTLINE, linewidth=0.8); ax.add_feature(cfeature.STATES.with_scale('50m'), alpha=0.3)

        coll = mcoll.PolyCollection(verts, array=plot_data, cmap=cmap, norm=norm, edgecolors='none', antialiaseds=True)
        ax.add_collection(coll)
        ax.set_extent([np.min(nodes_lon)-0.5, np.max(nodes_lon)+0.5, np.min(nodes_lat)-0.5, np.max(nodes_lat)+0.5], crs=ccrs.PlateCarree())
        plt.colorbar(coll, ax=ax, shrink=0.7, pad=0.03, label=getattr(data_var, 'units', ''))

        display_time = file_timestamp if file_timestamp else f"T{args_dict['time']}"
        ax.set_title(f"MPAS-{display_time} {fieldname}" + (f" | L{level}" if v_dim else ""))

        out_name = f"{Path(data_file).stem}_{fieldname}" + (f"_T{args_dict['time']}" if "Time" in data_var.dims else "") + (f"_L{level}" if v_dim else "")
        output_file = f"{args_dict['output']}_{fieldname}_L{level}.png" if args_dict['output'] else f"{out_name}.png"
        plt.savefig(output_file, dpi=args_dict['dpi'], bbox_inches='tight')
        plt.close(fig)

        return {"field": fieldname, "level": level, "status": "Success", "time": time.time()-t_start, "memory": get_memory_usage(), "file": output_file}
    except Exception as e:
        err_msg = f"Error plotting {fieldname} L{level}:\n{traceback.format_exc()}"
        log_error(err_msg)
        return {"field": fieldname, "level": level, "status": "Failed (see log)", "time": time.time()-t_start, "memory": get_memory_usage(), "file": "N/A"}

################################################################################
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

if __name__ == "__main__":
    main()