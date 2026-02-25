#!/usr/bin/env python3
import os
import sys
import argparse
import ssl
import numpy as np
import warnings
import logging

# 1. Silence background library warnings
logging.getLogger('param').setLevel(logging.ERROR)
warnings.filterwarnings("ignore")

# 2. Configure headless backend
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.collections as mcoll
import cartopy.crs as ccrs
import cartopy.feature as cfeature
import uxarray as ux

# SSL fix for map data downloads
ssl._create_default_https_context = ssl._create_unverified_context

def parse_args():
    parser = argparse.ArgumentParser(description="Adaptive MPAS/UXarray Visualization with Full Statistics.")
    parser.add_argument("grid_file", help="Path to the NetCDF grid file.")
    parser.add_argument("-o", "--output", help="Output PNG name.")
    parser.add_argument("--stride", type=int, default=4, help="Subsampling stride (default: 4).")
    return parser.parse_args()

def main(gridfilename, outfilename, stride):
    # Load dataset
    uxds = ux.open_dataset(gridfilename, gridfilename)
    R_EARTH_KM = 6371.229

    if "areaCell" in uxds:
        raw_areas = uxds["areaCell"].values
        total_raw_sum = np.sum(raw_areas)

        # --- ADAPTIVE SCALING LOGIC ---
        # If sum is near 4*pi (12.56) or less, it's a unit sphere (e.g., mpas.grid.nc).
        # If sum is huge (> 1e10), it's already scaled to meters (e.g., mpas.static.nc).
        if total_raw_sum < 100:
            detection_msg = "Unit Sphere (R=1)"
            area_scale = (R_EARTH_KM**2)
            spacing_scale = R_EARTH_KM
        elif total_raw_sum > 1e10:
            detection_msg = "Scaled (Meters)"
            area_scale = 1e-6    # m^2 to km^2
            spacing_scale = 1e-3 # m to km
        else:
            detection_msg = "Scaled (Kilometers)"
            area_scale = 1.0
            spacing_scale = 1.0

        # Convert data to km^2
        areas_km2 = raw_areas * area_scale
        avg_area = areas_km2.mean()

        # --- GEOGRAPHIC CALCULATIONS ---
        nodes_lon = uxds.uxgrid.node_lon.values
        nodes_lat = uxds.uxgrid.node_lat.values
        lon_norm = (nodes_lon + 180) % 360 - 180

        lon_min, lon_max = lon_norm.min(), lon_norm.max()
        lat_min, lat_max = nodes_lat.min(), nodes_lat.max()

        domain_length_km = R_EARTH_KM * np.radians(lat_max - lat_min)
        center_lat = np.radians((lat_min + lat_max) / 2.0)
        domain_width_km = R_EARTH_KM * np.radians(lon_max - lon_min) * np.cos(center_lat)

        # --- FULL GRID STATISTICS ---
        print("-" * 55)
        print(f"GRID FILE:          {os.path.basename(gridfilename)}")
        print(f"DETECTION:          {detection_msg}")
        print(f"Total Cells:        {len(raw_areas):,}")
        print(f"Total Domain Area:  {np.sum(areas_km2):,.2f} km^2")
        print(f"Latitude Range:     {lat_min:.2f}° to {lat_max:.2f}°")
        print(f"Longitude Range:    {lon_min:.2f}° to {lon_max:.2f}°")
        print(f"Domain Length (NS): {domain_length_km:.2f} km")
        print(f"Domain Width (EW):  {domain_width_km:.2f} km")
        print(f"Min Cell Area:      {areas_km2.min():.4f} km^2")
        print(f"Max Cell Area:      {areas_km2.max():.4f} km^2")
        print(f"Avg Cell Area:      {avg_area:.4f} km^2")
        print(f"Nominal Res (Area): ~{np.sqrt(avg_area):.2f} km")

        if "dcEdge" in uxds:
            spacing_km = uxds["dcEdge"].values * spacing_scale
            print(f"Min Nodal Spacing:  {spacing_km.min():.4f} km")
            print(f"Max Nodal Spacing:  {spacing_km.max():.4f} km")
        print("-" * 55)

        # --- PLOTTING ---
        data_plot = areas_km2[::stride]
        face_vertices = uxds.uxgrid.face_node_connectivity.values[::stride]
        polys = [np.column_stack((nodes_lon[f[f>=0]], nodes_lat[f[f>=0]])) for f in face_vertices]

        fig, ax = plt.subplots(figsize=(12, 8), subplot_kw={'projection': ccrs.PlateCarree()})

        # Polygons (Alpha 0.6)
        collection = mcoll.PolyCollection(polys, array=data_plot, cmap='turbo',
                                          edgecolors='none', zorder=1,
                                          alpha=0.6, transform=ccrs.PlateCarree())
        ax.add_collection(collection)
        fig.colorbar(collection, ax=ax, label='Cell Area ($km^{2}$)')

        # Mesh Lines (Alpha 0.4)
        edges = uxds.uxgrid.edge_node_connectivity.values[::stride]
        p0 = np.column_stack((nodes_lon[edges[:,0]], nodes_lat[edges[:,0]]))
        p1 = np.column_stack((nodes_lon[edges[:,1]], nodes_lat[edges[:,1]]))
        mask = np.abs(p0[:,0] - p1[:,0]) < 180
        segments = np.stack([p0[mask], p1[mask]], axis=1)

        ax.add_collection(mcoll.LineCollection(segments, linewidths=0.2, colors='black',
                                               zorder=2, alpha=0.4, transform=ccrs.PlateCarree()))

        # Geography
        ax.coastlines(resolution='50m', linewidth=1.0, zorder=4, color='#222222')
        ax.add_feature(cfeature.STATES, edgecolor='#333333', linewidth=0.8, zorder=5)

        ax.set_extent([nodes_lon.min()-0.5, nodes_lon.max()+0.5,
                      nodes_lat.min()-0.5, nodes_lat.max()+0.5], crs=ccrs.PlateCarree())

        ax.set_title(f"Regional Mesh: {os.path.basename(gridfilename)}")
        plt.savefig(outfilename, dpi=300, bbox_inches='tight')
        plt.close(fig)
        print(f"SUCCESS: Visualization saved to {outfilename}")
    else:
        print("Error: 'areaCell' variable not found in the dataset.")

if __name__ == "__main__":
    args = parse_args()
    if not os.path.exists(args.grid_file):
        sys.exit(f"Error: {args.grid_file} not found.")

    output_name = args.output or f"{os.path.splitext(os.path.basename(args.grid_file))[0]}.png"
    main(args.grid_file, output_name, args.stride)