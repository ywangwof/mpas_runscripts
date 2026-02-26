#!/usr/bin/env python3

import uxarray as ux
import matplotlib.pyplot as plt
import matplotlib.collections as mcoll
import matplotlib.colors as mcolors
import argparse
import numpy as np
import cartopy.crs as ccrs
import cartopy.feature as cfeature
from metpy.plots import ctables  # Required for NWS Reflectivity tables
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
    """Handles command line argument parsing."""
    parser = argparse.ArgumentParser(
        description="Plot MPAS data with specialized MetPy colormaps and high DPI."
    )
    # Changed fieldname to reflect it can be a comma-separated list
    parser.add_argument("data_file", help="Path to the MPAS netCDF file")
    parser.add_argument("fieldnames", help="Comma-separated list of fields (e.g., 'refl,rain_tot,ter')")

    # Optional arguments
    parser.add_argument("-g", "--grid_file", help="Optional separate MPAS grid/static file")
    parser.add_argument("-l", "--level", type=int, default=0, help="Vertical level index (default: 0)")
    parser.add_argument("-t", "--time", type=int, default=0, help="Time index (default: 0)")
    parser.add_argument("--min", type=float, help="Contour minimum override")
    parser.add_argument("--max", type=float, help="Contour maximum override")
    parser.add_argument("--inc", type=float, help="Contour increment override")
    parser.add_argument("-o", "--output", type=str, help="Custom output prefix (optional)")
    parser.add_argument("--global_view", action="store_true", help="Force global view")

    return parser.parse_args()

################################################################################
def get_plot_settings(fieldname, cmin=None, cmax=None, cinc=None):
    """Determines colormap and normalization based on field name."""
    cmap = "turbo"
    norm = None

    # 1. Reflectivity Logic (starts with 'refl')
    if fieldname.startswith("refl"):
        cmap = ctables.registry.get_colortable("NWSReflectivity")
        # Standard NWS bins: 0 to 75 with step 5 (16 levels = 15 bins)
        if all(v is None for v in [cmin, cmax, cinc]):
            levels = np.arange(0, 80, 5.0)
            norm = mcolors.BoundaryNorm(levels, cmap.N)
        elif cmin is not None and cmax is not None:
            # Respect user override if provided
            step = cinc if cinc is not None else (cmax - cmin) / 10
            levels = np.arange(cmin, cmax + step, step)
            if len(levels) - 1 > cmap.N:
                cmap = cmap.resampled(len(levels) - 1)
            norm = mcolors.BoundaryNorm(levels, cmap.N)

    # 2. Precipitation Logic (starts with 'rain' or 'prec_')
    elif fieldname.startswith("rain") or fieldname.startswith("prec_"):
        cmap = plt.get_cmap("YlGnBu") # Distinctive precip-style map
        precip_levels = [0, 1, 2.5, 5, 7.5, 10, 15, 20, 30, 40, 50, 70, 100, 150, 200, 250, 300, 400, 500, 600, 750]

        if all(v is None for v in [cmin, cmax, cinc]):
            norm = mcolors.BoundaryNorm(precip_levels, cmap.N)
        elif cmin is not None and cmax is not None:
            step = cinc if cinc is not None else (cmax - cmin) / 10
            levels = np.arange(cmin, cmax + step, step)
            norm = mcolors.BoundaryNorm(levels, cmap.N)

    # 3. All other fields
    else:
        if cmin is not None and cmax is not None:
            norm = mcolors.Normalize(vmin=cmin, vmax=cmax)

    return cmap, norm

################################################################################
def plot_mpas_field(uxds, fieldname, level=0, time_idx=0, cmin=None, cmax=None, cinc=None, output_file=None, global_view=False):
    """Renders a single MPAS field with high DPI and artifact suppression."""
    start_time_proc = time.time()
    mem_start = get_memory_usage()

    if fieldname not in uxds.data_vars:
        print(f"Warning: Field '{fieldname}' not found in dataset. Skipping.")
        return

    # 1. Extract and Slice Data
    data_var = uxds[fieldname]

    # 2. Determine if T/L tags are needed based on actual dimensions
    has_multiple_times = "Time" in data_var.dims and data_var.sizes["Time"] > 1
    is_3d_field = "nVertLevels" in data_var.dims

    # 3. Slice the Data
    selectors = {}
    if "Time" in data_var.dims:
        selectors["Time"] = time_idx
    if "nVertLevels" in data_var.dims:
        selectors["nVertLevels"] = level

    plot_data = data_var.isel(selectors).values.squeeze()

    # 4. Extract Mesh Geometry
    # MPAS uses Voronoi cells where each face is a polygon defined by nodes

    faces = uxds.uxgrid.face_node_connectivity.values
    nodes_lon = uxds.uxgrid.node_lon.values
    nodes_lat = uxds.uxgrid.node_lat.values

    # Coordinate conversion
    if np.abs(nodes_lat).max() <= (np.pi + 0.1):
        nodes_lon, nodes_lat = np.rad2deg(nodes_lon), np.rad2deg(nodes_lat)

    nodes_lon = (nodes_lon + 180) % 360 - 180

    # 5. Build Polygon Vertices
    polygon_vertices = [np.column_stack((nodes_lon[f[f >= 0]], nodes_lat[f[f >= 0]])) for f in faces]

    # 6. Setup Plot and Colormapping
    cmap, norm = get_plot_settings(fieldname, cmin, cmax, cinc)

    fig = plt.figure(figsize=(14, 10))
    ax = plt.axes(projection=ccrs.PlateCarree())
    ax.add_feature(cfeature.COASTLINE, linewidth=0.8)
    ax.add_feature(cfeature.STATES.with_scale('50m'), linewidth=0.5, edgecolor='black', alpha=0.3)

    # 7. Create Collection
    coll = mcoll.PolyCollection(
        polygon_vertices,
        array=plot_data,
        cmap=cmap,
        norm=norm,
        edgecolors='none',
        antialiaseds=True,
        snap=True
    )
    ax.add_collection(coll)

    if not global_view:
        ax.set_extent([np.min(nodes_lon)-0.5, np.max(nodes_lon)+0.5,
                       np.min(nodes_lat)-0.5, np.max(nodes_lat)+0.5], crs=ccrs.PlateCarree())

    cb = plt.colorbar(coll, ax=ax, shrink=0.7, pad=0.03)
    cb.set_label(getattr(data_var, 'units', ''))

    # 8. Dynamic Title
    title_str = f"MPAS: {fieldname}"
    if has_multiple_times: title_str += f" (T{time_idx})"
    if is_3d_field: title_str += f" (L{level})"
    ax.set_title(title_str)

    ax.gridlines(draw_labels=True, alpha=0.1)

    # 9. Save with 600 DPI to eliminate artifacts
    plt.savefig(output_file, dpi=600, bbox_inches='tight')
    plt.close(fig)

    # 10. Metrics Reporting
    end_time = time.time()
    mem_end = get_memory_usage()

    print("#" * 80)
    print(f"SUCCESS: Image saved to {output_file}")
    print(f"Run Time:       {end_time - start_time_proc:.2f} seconds")
    if psutil: print(f"Peak Memory:    {mem_end:.2f} MB")
    print("#" * 80)

################################################################################
def main():
    args = get_args()

    grid_source = args.grid_file if args.grid_file else args.data_file
    try:
        uxds = ux.open_dataset(grid_source, args.data_file)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

    # Split the comma-separated string into a list of fields
    fields_to_plot = [f.strip() for f in args.fieldnames.split(',')]

    for field in fields_to_plot:
        # Generate individual output name for each field in the loop
        data_var = uxds[field]
        base_name = Path(args.data_file).stem
        out_name = f"{base_name}_{field}"

        # Only add T tag if more than 1 time level exists in the file
        if "Time" in data_var.dims and data_var.sizes["Time"] > 1:
            out_name += f"_T{args.time}"
        if "nVertLevels" in data_var.dims:
            out_name += f"_L{args.level}"

        final_output_path = out_name + ".png" if not args.output else f"{args.output}_{field}.png"

        try:
            plot_mpas_field(
                uxds, field,
                level=args.level,
                time_idx=args.time,
                cmin=args.min,
                cmax=args.max,
                cinc=args.inc,
                output_file=final_output_path,
                global_view=args.global_view
            )
        except Exception as e:
            print(f"Error: {e}")
            sys.exit(1)

################################################################################
if __name__ == "__main__":
    main()
