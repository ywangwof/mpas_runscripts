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

def get_memory_usage():
    """Returns current memory usage in MB."""
    if psutil:
        # Corrected: os.getpid() instead of get_pid()
        process = psutil.Process(os.getpid())
        return process.memory_info().rss / (1024 * 1024)
    return 0

def get_args():
    """Handles command line argument parsing."""
    parser = argparse.ArgumentParser(
        description="Plot MPAS data using native Matplotlib collections to avoid aliasing."
    )
    parser.add_argument("filename", help="Path to the MPAS netCDF file")
    parser.add_argument("fieldname", help="Field name (e.g., 'ter')")
    parser.add_argument("-l", "--level", type=int, default=0, help="Vertical level index")
    parser.add_argument("--min", type=float, help="Contour minimum")
    parser.add_argument("--max", type=float, help="Contour maximum")
    parser.add_argument("--inc", type=float, help="Contour increment")
    parser.add_argument("-o", "--output", type=str, help="Output filename")
    parser.add_argument("--global_view", action="store_true", help="Force global view")
    return parser.parse_args()

def plot_mpas_field(uxds, fieldname, level=0, cmin=None, cmax=None, cinc=None, output_file=None, global_view=False):
    """Manual rendering using Matplotlib PolyCollection with anti-aliasing fixes."""
    start_time = time.time()
    mem_start = get_memory_usage()

    if fieldname not in uxds.data_vars:
        raise ValueError(f"Field '{fieldname}' not found.")

    # 1. Extract Data and Mesh Geometry
    data_var = uxds[fieldname]
    if "nVertLevels" in data_var.dims:
        plot_data = data_var.isel(nVertLevels=level).values
    elif data_var.ndim > 1:
        plot_data = data_var.isel({data_var.dims[0]: level}).values
    else:
        plot_data = data_var.values

    faces = uxds.uxgrid.face_node_connectivity.values
    nodes_lon = uxds.uxgrid.node_lon.values
    nodes_lat = uxds.uxgrid.node_lat.values

    # Convert radians to degrees if necessary
    if np.abs(nodes_lat).max() <= (np.pi + 0.1):
        nodes_lon, nodes_lat = np.rad2deg(nodes_lon), np.rad2deg(nodes_lat)

    nodes_lon = (nodes_lon + 180) % 360 - 180

    # 2. Build Polygons (List of Nx2 arrays)
    polygon_vertices = [np.column_stack((nodes_lon[f[f >= 0]], nodes_lat[f[f >= 0]])) for f in faces]

    # 3. Setup Figure
    fig = plt.figure(figsize=(14, 10))
    ax = plt.axes(projection=ccrs.PlateCarree())
    ax.add_feature(cfeature.COASTLINE, linewidth=0.8)
    ax.add_feature(cfeature.STATES.with_scale('50m'), linewidth=0.5, edgecolor='black', alpha=0.3)

    # 4. Create PolyCollection with Anti-Aliasing Fixes
    # edgecolors='none' and antialiaseds=True solve the diamond/Moiré artifacts
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

    # Set framing
    if not global_view:
        ax.set_extent([np.min(nodes_lon)-0.5, np.max(nodes_lon)+0.5,
                       np.min(nodes_lat)-0.5, np.max(nodes_lat)+0.5], crs=ccrs.PlateCarree())

    cb = plt.colorbar(coll, ax=ax, shrink=0.7, pad=0.03)
    cb.set_label(getattr(data_var, 'units', ''))

    ax.set_title(f"MPAS: {fieldname} (Level {level})")
    ax.gridlines(draw_labels=True, alpha=0.1)

    # 5. Save with high resolution to ensure pixel-to-cell clarity
    plt.savefig(output_file, dpi=600, bbox_inches='tight')
    plt.close(fig)

    # 6. Performance and Success Reporting
    end_time = time.time()
    mem_end = get_memory_usage()

    print("-" * 40)
    print(f"SUCCESS: Image saved to {output_file}")
    print(f"Run Time:       {end_time - start_time:.2f} seconds")
    if psutil:
        print(f"Peak Memory:    {mem_end:.2f} MB")
    print("-" * 40)

def main():
    args = get_args()
    if not args.output:
        args.output = f"{Path(args.filename).stem}_{args.fieldname}_L{args.level}.png"

    try:
        # Load dataset
        uxds = ux.open_dataset(args.filename, args.filename)
        plot_mpas_field(uxds, args.fieldname, args.level, args.min, args.max, args.inc, args.output, args.global_view)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()