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
    parser = argparse.ArgumentParser(description="Plot JEDI Sawtooth DA Diagnostics (Dynamic Scaling)")
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
    parser.add_argument("-n", "--number", action="store_true", help="Plot gross error check counts")

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

    if not (os.path.exists(path_b) and os.path.exists(path_a)):
        return [np.nan]*2, [np.nan]*2, [np.nan]*2, None

    try:
        with Dataset(path_b, 'r') as nc_b, Dataset(path_a, 'r') as nc_a:
            required_groups = ['ombg', 'ObsValue', 'ObsError']
            if not all(g in nc_b.groups for g in required_groups):
                return [np.nan]*2, [np.nan]*2, [np.nan]*2, None

            vartype = list(nc_b.groups['ombg'].variables.keys())[0]
            if vartype not in nc_b.groups['ObsValue'].variables:
                return [np.nan]*2, [np.nan]*2, [np.nan]*2, None

            ombg = nc_b.groups['ombg'].variables[vartype][:]
            oman = nc_a.groups['oman'].variables[vartype][:]
            obs_val_b = nc_b.groups['ObsValue'].variables[vartype][:]
            err_b = nc_b.groups['ObsError'].variables[vartype][:]
            err_a = nc_a.groups['ObsError'].variables[vartype][:]

            valid_mask = (~err_b.mask) & (~err_a.mask)
            if args.type == 'thresh':
                valid_mask = valid_mask & (obs_val_b > args.thresh)

            if not np.any(valid_mask):
                return [np.nan]*2, [np.nan]*2, [np.nan]*2, vartype

            rmsd = [np.sqrt(np.mean(ombg[valid_mask]**2)), np.sqrt(np.mean(oman[valid_mask]**2))]
            innov = [np.mean(ombg[valid_mask]), np.mean(oman[valid_mask])]

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
def process_gross_error_cycle(meta, obname, args):
    """Worker function to process gross error check data for a single cycle."""
    path_b = os.path.join(meta['dir_b'], f'jdiag_{obname}.nc')

    if not os.path.exists(path_b):
        return np.nan, np.nan, np.nan

    try:
        with Dataset(path_b, 'r') as nc_b:
            if 'DiagnosticFlags' not in nc_b.groups or 'gross_error_check' not in nc_b.groups['DiagnosticFlags'].groups:
                return np.nan, np.nan, np.nan

            vartype = list(nc_b.groups['DiagnosticFlags'].groups['gross_error_check'].variables.keys())[0]
            if vartype not in nc_b.groups['DiagnosticFlags'].groups['gross_error_check'].variables:
                return np.nan, np.nan, np.nan

            var = nc_b.groups['DiagnosticFlags'].groups['gross_error_check'].variables[vartype]
            var.set_auto_mask(False)
            gec = var[:]
            total = len(gec)
            assimilated = np.sum(gec != 1)
            rejected = np.sum(gec == 1)

            return total, assimilated, rejected
    except Exception as e:
        if args.verbose: print(f"Error processing gross error {meta['hm_str']}: {e}")
        return np.nan, np.nan, np.nan

################################################################################
def plot_ob_type(obname, cycle_meta, args):
    """Aggregates parallel results and generates the sawtooth plot with dynamic y-limits."""

    with ProcessPoolExecutor(max_workers=args.nprocs) as executor:
        futures = [executor.submit(process_single_cycle, meta, obname, args) for meta in cycle_meta]
        results = [f.result() for f in futures]

    raw_minutes, raw_labels = [], []
    raw_rmsd, raw_innov, raw_spread = [], [], []
    found_vartypes = []

    for i, res in enumerate(results):
        m = cycle_meta[i]
        raw_minutes.extend([m['elapsed'], m['elapsed']])
        raw_labels.extend([m['hm_str'], m['hm_str']])
        raw_rmsd.extend(res[0])
        raw_innov.extend(res[1])
        raw_spread.extend(res[2])
        if res[3]: found_vartypes.append(res[3])

    valid_mask = [not np.isnan(v) for v in raw_rmsd]
    if not any(valid_mask):
        if args.verbose: print(f"INFO: No valid data for {obname}. Skipping.")
        return

    minutes = [raw_minutes[i] for i, v in enumerate(valid_mask) if v]
    labels = [raw_labels[i] for i, v in enumerate(valid_mask) if v]
    rmsd = [raw_rmsd[i] for i, v in enumerate(valid_mask) if v]
    innov = [raw_innov[i] for i, v in enumerate(valid_mask) if v]
    spread = [raw_spread[i] for i, v in enumerate(valid_mask) if v]

    is_hourly = all(l.endswith('00') for l in labels)
    vartype = found_vartypes[0] if found_vartypes else 'unknown'

    unit_map = {
        'airTemperature': 'K', 'specificHumidity': 'g/kg', 'radialVelocity': 'm/s',
        'windNorthward': 'm/s', 'windEastward': 'm/s', 'equivalentReflectivityFactor': 'dBZ'
    }
    unit = unit_map.get(vartype, 'units')

    fig, ax = plt.subplots(figsize=(10, 5))
    ax.plot(minutes, rmsd, color='tab:red', label='RMSD (O-F/A)', lw=2)
    ax.plot(minutes, innov, color='tab:blue', label='Bias', lw=2)
    ax.plot(minutes, spread, color='tab:green', linestyle='--', label='Total Spread', lw=2)

    # --- Dynamic Y-Axis Scaling ---
    all_values = np.array(rmsd + innov + spread)
    all_values = all_values[~np.isnan(all_values)]

    if len(all_values) > 0:
        v_min, v_max = np.min(all_values), np.max(all_values)
        padding = (v_max - v_min) * 0.15 if v_max != v_min else 1.0
        ax.set_ylim([v_min - padding, v_max + padding])

    ax.set_title(f"JEDI Sawtooth: {args.eventdate} {obname}", fontsize=14)
    ax.set_xlabel("Time [HHMM]", fontsize=12)
    ax.set_ylabel(f"[{unit}]", fontsize=12)
    ax.set_xlim([min(raw_minutes), max(raw_minutes)])

    all_cycle_minutes = sorted(list(set(raw_minutes)))
    label_map = {m['elapsed']: m['hm_str'] for m in cycle_meta}

    def formatter(x, p):
        m_val = int(round(x))
        lbl = label_map.get(m_val, "")
        if len(lbl) == 4:
            lbl = lbl[:2] + ':' + lbl[2:]
        if is_hourly:
            return lbl if lbl.endswith(':00') or lbl.endswith('00') else ""
        return lbl if lbl.endswith(':00') or lbl.endswith(':30') or lbl.endswith('00') or lbl.endswith('30') else ""

    if is_hourly:
        hourly_ticks = [m for m in all_cycle_minutes if label_map[m].endswith('00')]
        ax.xaxis.set_major_locator(ticker.FixedLocator(hourly_ticks))
    else:
        ax.xaxis.set_major_locator(ticker.FixedLocator(all_cycle_minutes))

    ax.xaxis.set_major_formatter(ticker.FuncFormatter(formatter))
    plt.setp(ax.get_xticklabels(), rotation=45)
    ax.legend(loc='upper right', frameon=True, shadow=True)
    ax.grid(True, alpha=0.3)

    out_name = f"{obname}_sawtooth_{args.eventdate}.png"
    print(f"Saving plot to {out_name} ...")
    plt.savefig(out_name, bbox_inches='tight', dpi=200)
    plt.close()

################################################################################
def plot_gross_error(obname, cycle_meta, args):
    """Aggregates parallel results and generates the gross error check plot."""

    with ProcessPoolExecutor(max_workers=args.nprocs) as executor:
        futures = [executor.submit(process_gross_error_cycle, meta, obname, args) for meta in cycle_meta]
        results = [f.result() for f in futures]

    raw_minutes, raw_labels = [], []
    raw_total, raw_assim, raw_rej = [], [], []

    for i, res in enumerate(results):
        m = cycle_meta[i]
        raw_minutes.append(m['elapsed'])
        raw_labels.append(m['hm_str'])
        raw_total.append(res[0])
        raw_assim.append(res[1])
        raw_rej.append(res[2])

    valid_mask = [not np.isnan(v) for v in raw_total]
    if not any(valid_mask):
        if args.verbose: print(f"INFO: No valid gross error data for {obname}. Skipping.")
        return

    minutes = [raw_minutes[i] for i, v in enumerate(valid_mask) if v]
    labels = [raw_labels[i] for i, v in enumerate(valid_mask) if v]
    total = [raw_total[i] for i, v in enumerate(valid_mask) if v]
    assim = [raw_assim[i] for i, v in enumerate(valid_mask) if v]
    rej = [raw_rej[i] for i, v in enumerate(valid_mask) if v]

    fig, ax = plt.subplots(figsize=(10, 5))
    ax.plot(minutes, total, color='tab:blue', label='Total Observations', lw=2)
    ax.plot(minutes, assim, color='tab:green', label='Assimilated', lw=2)
    ax.plot(minutes, rej, color='tab:red', label='Rejected', lw=2)

    # --- Dynamic Y-Axis Scaling ---
    all_values = np.array(total + assim + rej)
    all_values = all_values[~np.isnan(all_values)]

    if len(all_values) > 0:
        v_min, v_max = np.min(all_values), np.max(all_values)
        padding = (v_max - v_min) * 0.15 if v_max != v_min else 1.0
        ax.set_ylim([max(0, v_min - padding), v_max + padding])

    ax.set_title(f"Gross Error Check: {args.eventdate} {obname}", fontsize=14)
    ax.set_xlabel("Time [HHMM]", fontsize=12)
    ax.set_ylabel("Count", fontsize=12)
    ax.set_xlim([min(raw_minutes), max(raw_minutes)])

    all_cycle_minutes = sorted(list(set(raw_minutes)))
    label_map = {m['elapsed']: m['hm_str'] for m in cycle_meta}

    def formatter(x, p):
        m_val = int(round(x))
        lbl = label_map.get(m_val, "")
        if len(lbl) == 4:
            lbl = lbl[:2] + ':' + lbl[2:]
        return lbl

    ax.xaxis.set_major_locator(ticker.FixedLocator(all_cycle_minutes))
    ax.xaxis.set_major_formatter(ticker.FuncFormatter(formatter))
    plt.setp(ax.get_xticklabels(), rotation=45)
    ax.legend(loc='upper right', frameon=True, shadow=True)
    ax.grid(True, alpha=0.3)

    out_name = f"{obname}_count_{args.eventdate}.png"
    print(f"Saving plot to {out_name} ...")
    plt.savefig(out_name, bbox_inches='tight', dpi=200)
    plt.close()

################################################################################
if __name__ == "__main__":
    cli_args = parse_args()
    meta_list = get_sawtooth_metadata(cli_args)

    for ob in cli_args.obs:
        plot_ob_type(ob, meta_list, cli_args)
        if cli_args.number:
            plot_gross_error(ob, meta_list, cli_args)