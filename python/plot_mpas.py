#!/usr/bin/env python3

import uxarray as ux
import matplotlib.pyplot as plt
import matplotlib.collections as mcoll
import argparse
import numpy as np
import cartopy.crs as ccrs
import cartopy.feature as cfeature
from pathlib import Path
import sys
import time
import os

# Try to import psutil for memory tracking
try:
    import psutil
except ImportError:
    psutil = None

################################################################################
def get_memory_usage():
    """Returns current memory usage in MB."""
    if psutil:
        process = psutil.Process(os.getpid())
        return process.memory_info().rss / (1024 * 1024)
    return 0

################################################################################
def get_args():
    """Handles command line argument parsing with Time and Level options."""
    parser = argparse.ArgumentParser(
        description="Plot MPAS data using native Matplotlib collections with high DPI."
    )
    # Required positional arguments
    parser.add_argument("data_file", help="Path to the MPAS netCDF file containing field data")
    parser.add_argument("fieldname", help="Field name to plot (e.g., 'ter')")

    # Optional arguments
    parser.add_argument("-g", "--grid_file", help="Optional separate MPAS grid/static file")
    parser.add_argument("-l", "--level", type=int, default=0, help="Vertical level index (default: 0)")
    parser.add_argument("-t", "--time", type=int, default=0, help="Time index (default: 0)")
    parser.add_argument("--min", type=float, help="Contour minimum")
    parser.add_argument("--max", type=float, help="Contour maximum")
    parser.add_argument("--inc", type=float, help="Contour increment")
    parser.add_argument("-o", "--output", type=str, help="Output filename")
    parser.add_argument("--global_view", action="store_true", help="Force global view")

    return parser.parse_args()

################################################################################
def plot_mpas_field(uxds, fieldname, level=0, time_idx=0, cmin=None, cmax=None, cinc=None, output_file=None, global_view=False):
    """Manual rendering using Matplotlib PolyCollection with strict rank-1 enforcement and 600 DPI."""
    start_time_proc = time.time()
    mem_start = get_memory_usage()

    if fieldname not in uxds.data_vars:
        raise ValueError(f"Field '{fieldname}' not found in the dataset.")

    # 1. Extract and Slice Data to ensure Rank 1
    data_var = uxds[fieldname]

    selectors = {}
    if "Time" in data_var.dims:
        selectors["Time"] = time_idx
    if "nVertLevels" in data_var.dims:
        selectors["nVertLevels"] = level

    data_subset = data_var.isel(selectors)
    plot_data = data_subset.values.squeeze()

    if plot_data.ndim != 1:
        raise ValueError(f"Data for '{fieldname}' is rank {plot_data.ndim}, but Rank 1 is required.")

    # 2. Extract Mesh Geometry
    # MPAS uses Voronoi cells where each face is a polygon defined by nodes

    faces = uxds.uxgrid.face_node_connectivity.values
    nodes_lon = uxds.uxgrid.node_lon.values
    nodes_lat = uxds.uxgrid.node_lat.values

    # Coordinate conversion
    if np.abs(nodes_lat).max() <= (np.pi + 0.1):
        nodes_lon, nodes_lat = np.rad2deg(nodes_lon), np.rad2deg(nodes_lat)

    nodes_lon = (nodes_lon + 180) % 360 - 180

    # 3. Build Polygon Vertices
    polygon_vertices = [np.column_stack((nodes_lon[f[f >= 0]], nodes_lat[f[f >= 0]])) for f in faces]

    # 4. Setup Figure and Cartopy
    fig = plt.figure(figsize=(14, 10))
    ax = plt.axes(projection=ccrs.PlateCarree())
    ax.add_feature(cfeature.COASTLINE, linewidth=0.8)
    ax.add_feature(cfeature.STATES.with_scale('50m'), linewidth=0.5, edgecolor='black', alpha=0.3)

    # 5. Create PolyCollection
    # edgecolors='none' and antialiaseds=True are crucial for suppressing artifacts
    coll = mcoll.PolyCollection(
        polygon_vertices,
        array=plot_data,
        cmap='turbo',
        edgecolors='none',
        antialiaseds=True,
        snap=True
    )

    if cmin is not None and cmax is not None:
        coll.set_clim(cmin, cmax)

    ax.add_collection(coll)

    if not global_view:
        ax.set_extent([np.min(nodes_lon)-0.5, np.max(nodes_lon)+0.5,
                       np.min(nodes_lat)-0.5, np.max(nodes_lat)+0.5], crs=ccrs.PlateCarree())

    cb = plt.colorbar(coll, ax=ax, shrink=0.7, pad=0.03)
    cb.set_label(getattr(data_var, 'units', ''))

    ax.set_title(f"MPAS: {fieldname} (Time index: {time_idx}, Level index: {level})")
    ax.gridlines(draw_labels=True, alpha=0.1)

    # 6. Save Plot with high DPI to eliminate artifacts
    plt.savefig(output_file, dpi=600, bbox_inches='tight')
    plt.close(fig)

    # 7. Metrics Reporting
    end_time = time.time()
    mem_end = get_memory_usage()

    print("#" * 80)
    print(f"SUCCESS: Image saved to {output_file}")
    print(f"Run Time:       {end_time - start_time_proc:.2f} seconds")
    if psutil:
        print(f"Peak Memory:    {mem_end:.2f} MB")
    print("#" * 80)

################################################################################
def main():
    args = get_args()

    if not args.output:
        base_name = Path(args.data_file).stem
        args.output = f"{base_name}_{args.fieldname}_T{args.time}_L{args.level}.png"

    try:
        grid_source = args.grid_file if args.grid_file else args.data_file
        uxds = ux.open_dataset(grid_source, args.data_file)

        plot_mpas_field(
            uxds, args.fieldname,
            level=args.level,
            time_idx=args.time,
            cmin=args.min,
            cmax=args.max,
            cinc=args.inc,
            output_file=args.output,
            global_view=args.global_view
        )
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

################################################################################
if __name__ == "__main__":
    main()