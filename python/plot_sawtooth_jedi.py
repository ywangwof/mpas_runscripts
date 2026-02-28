#!/usr/bin/env python3
import numpy as np
import os
import argparse
from netCDF4 import Dataset
from datetime import datetime, timedelta
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
from concurrent.futures import ProcessPoolExecutor

################################################################################
def parse_args():
    """Handle command-line arguments for JEDI diagnostics."""
    parser = argparse.ArgumentParser(description="Plot JEDI Sawtooth DA Diagnostics (Optimized)")
    parser.add_argument("eventdate", type=str, help="Event date in YYYYmmdd")
    parser.add_argument("-s", "--start", type=str, required=True, help="Start time YYYYmmddHHMM")
    parser.add_argument("-e", "--end", type=str, required=True, help="End time YYYYmmddHHMM")
    parser.add_argument("-d", "--dir", type=str, required=True, help="Base run directory")
    parser.add_argument("-o", "--obs", nargs='+', default=['radar_rw'], help="List of observation types (without .nc)")
    parser.add_argument("-m", "--mems", type=int, default=36, help="Number of ensemble members")
    parser.add_argument("-c", "--cycle_min", type=int, default=15, help="Cycle interval in minutes")
    parser.add_argument("-x", "--affix", type=str, default="", help="Affix for dacycles directory")
    parser.add_argument("--thresh", type=float, default=15.0, help="Threshold for 'thresh' over_type")
    parser.add_argument("--type", choices=['all', 'thresh'], default='all', help="Verification type")
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose path debugging")
    parser.add_argument("-p", "--nprocs", type=int, default=8, help="Number of processes for parallel reading")

    return parser.parse_args()

################################################################################
def get_sawtooth_metadata(args):
    """Generates the directory list and timeline metadata for the sawtooth plot."""
    first_dt = datetime.strptime(args.start, '%Y%m%d%H%M')
    final_dt = datetime.strptime(args.end, '%Y%m%d%H%M')

    cycle_meta = []
    curr_dt = first_dt

    while curr_dt <= final_dt:
        hm_str = curr_dt.strftime('%H%M')
        cycle_base = os.path.join(args.dir, args.eventdate, f'dacycles{args.affix}', hm_str)

        elapsed = int((curr_dt - first_dt).total_seconds() / 60)

        cycle_meta.append({
            'dt': curr_dt,
            'dir_b': os.path.join(cycle_base, 'jedi_observer'),
            'dir_a': os.path.join(cycle_base, 'jedi_post'),
            'elapsed': elapsed,
            'hm_str': hm_str
        })
        curr_dt += timedelta(minutes=args.cycle_min)

    return cycle_meta

################################################################################
def process_single_cycle(meta, obname, args):
    """Worker function to process a single cycle's data for a specific observation."""
    path_b = os.path.join(meta['dir_b'], f'jdiag_{obname}.nc')
    path_a = os.path.join(meta['dir_a'], f'jdiag_{obname}.nc')

    # Return NaNs if files are missing
    if not (os.path.exists(path_b) and os.path.exists(path_a)):
        return [np.nan]*2, [np.nan]*2, [np.nan]*2, None

    try:
        with Dataset(path_b, 'r') as nc_b, Dataset(path_a, 'r') as nc_a:
            vartype = list(nc_b.groups['ombg'].variables.keys())[0]

            # Read basic diagnostic variables
            ombg = nc_b.groups['ombg'].variables[vartype][:]
            oman = nc_a.groups['oman'].variables[vartype][:]
            obs_val_b = nc_b.groups['ObsValue'].variables[vartype][:]
            err_b = nc_b.groups['ObsError'].variables[vartype][:]
            err_a = nc_a.groups['ObsError'].variables[vartype][:]

            # Apply masking
            valid_mask = (~err_b.mask) & (~err_a.mask)
            if args.type == 'thresh':
                valid_mask = valid_mask & (obs_val_b > args.thresh)

            if not np.any(valid_mask):
                return [np.nan]*2, [np.nan]*2, [np.nan]*2, vartype

            # Stats calculations
            rmsd = [np.sqrt(np.mean(ombg[valid_mask]**2)), np.sqrt(np.mean(oman[valid_mask]**2))]
            innov = [np.mean(ombg[valid_mask]), np.mean(oman[valid_mask])]

            # Optimized spread: Read all members
            h_b = np.stack([nc_b.groups[f'hofx0_{m}'].variables[vartype][valid_mask] for m in range(1, args.mems+1)])
            h_a = np.stack([nc_a.groups[f'hofx0_{m}'].variables[vartype][valid_mask] for m in range(1, args.mems+1)])

            spread = [
                np.sqrt(np.mean(err_b[valid_mask]**2 + np.var(h_b, axis=0))),
                np.sqrt(np.mean(err_a[valid_mask]**2 + np.var(h_a, axis=0)))
            ]

            return rmsd, innov, spread, vartype
    except Exception as e:
        if args.verbose: print(f"Error processing {meta['hm_str']}: {e}")
        return [np.nan]*2, [np.nan]*2, [np.nan]*2, None

################################################################################
def plot_ob_type(obname, cycle_meta, args):
    """Aggregates parallel results and generates the sawtooth plot."""

    # Parallelize cycle processing
    with ProcessPoolExecutor(max_workers=args.nprocs) as executor:
        futures = [executor.submit(process_single_cycle, meta, obname, args) for meta in cycle_meta]
        results = [f.result() for f in futures]

    # Unpack results
    rmsd_all, innov_all, spread_all, vartypes = zip(*results)

    # Flatten lists for sawtooth (Prior/Post)
    minutes = []
    timestrings = []
    rmsd = []
    innov = []
    spread = []

    for i, res in enumerate(results):
        m = cycle_meta[i]
        minutes.extend([m['elapsed'], m['elapsed']])
        timestrings.extend([m['hm_str'], m['hm_str']])
        rmsd.extend(res[0])
        innov.extend(res[1])
        spread.extend(res[2])

    # Use the first valid vartype found for metadata
    valid_vartypes = [v for v in vartypes if v is not None]
    vartype = valid_vartypes[0] if valid_vartypes else 'unknown'

    meta_dict = {
        'airTemperature': ('K', 2.0),
        'specificHumidity': ('g/kg', 4.0),
        'windNorthward': ('m/s', 6.0),
        'windEastward': ('m/s', 6.0),
        'equivalentReflectivityFactor': ('dBZ', 6.0 if args.type == 'all' else 20.0),
        'radialVelocity': ('m/s', 10.0)
    }
    unit, ymax = meta_dict.get(vartype, ('units', 5.0))

    fig, ax = plt.subplots(figsize=(10, 5))
    ax.plot(minutes, rmsd, color='tab:red', label='RMSD (O-F/A)', lw=2)
    ax.plot(minutes, innov, color='tab:blue', label='Bias', lw=2)
    ax.plot(minutes, spread, color='tab:green', linestyle='--', label='Total Spread', lw=2)

    ax.set_title(f"JEDI Sawtooth: {obname}", fontsize=14)
    ax.set_xlabel("Time [HHMM]", fontsize=12)
    ax.set_ylabel(f"[{unit}]", fontsize=12)
    ax.set_ylim([-2 if unit != 'dBZ' else -5, ymax])
    ax.set_xlim([min(minutes), max(minutes)])

    # Custom x-axis formatting
    unique_minutes = minutes[::2]
    unique_labels = timestrings[::2]

    def format_func(value, tick_number):
        try:
            idx = unique_minutes.index(int(value))
            label = unique_labels[idx]
            return label if label.endswith('00') or label.endswith('30') else ""
        except (ValueError, IndexError):
            return ""

    ax.xaxis.set_major_locator(ticker.FixedLocator(unique_minutes))
    ax.xaxis.set_major_formatter(ticker.FuncFormatter(format_func))
    plt.setp(ax.get_xticklabels(), rotation=45)

    ax.legend(loc='upper right')
    ax.grid(True, alpha=0.3)

    out_name = f"sawtooth_{obname}.png"
    plt.savefig(out_name, bbox_inches='tight', dpi=200)
    plt.close()

################################################################################
if __name__ == "__main__":
    cli_args = parse_args()
    meta_list = get_sawtooth_metadata(cli_args)

    for ob in cli_args.obs:
        if cli_args.verbose: print(f"INFO: Processing {ob}...")
        plot_ob_type(ob, meta_list, cli_args)