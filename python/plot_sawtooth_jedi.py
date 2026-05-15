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
    parser.add_argument("-o", "--obs", type=str, default="radar_rw", help="Comma-separated observation types (without .nc)")
    parser.add_argument("-m", "--mems", type=int, default=36, help="Number of ensemble members")
    parser.add_argument("-c", "--cycle_min", type=int, default=15, help="Cycle interval in minutes")
    parser.add_argument("-x", "--affix", type=str, default="", help="Affix for dacycles directory")
    parser.add_argument("--thresh", type=float, default=15.0, help="Threshold for 'thresh' over_type")
    parser.add_argument("--type", choices=['all', 'thresh'], default='all', help="Verification type")
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose path debugging")
    parser.add_argument("-p", "--nprocs", type=int, default=8, help="Number of processes for parallel reading")
    parser.add_argument("-n", "--number", action="store_true", help="Plot gross error check counts")
    parser.add_argument("--cr", action="store_true", help="Plot Consistency Ratio (RMSD / Total Spread)") # Added

    args = parser.parse_args()
    args.obs = [ob.strip() for ob in args.obs.split(",") if ob.strip()]
    return args

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
    """Worker function with robust dimension checking for ensemble members."""
    path_b = os.path.join(meta['dir_b'], f'jdiag_{obname}.nc')
    path_a = os.path.join(meta['dir_a'], f'jdiag_{obname}.nc')

    if not (os.path.exists(path_b) and os.path.exists(path_a)):
        return [np.nan]*2, [np.nan]*2, [np.nan]*2, None, [np.nan]*2

    try:
        with Dataset(path_b, 'r') as nc_b, Dataset(path_a, 'r') as nc_a:
            # Identify the variable name (e.g., equivalentReflectivityFactor) [cite: 4, 30]
            vartype = list(nc_b.groups['ombg'].variables.keys())[0]

            # Load primary arrays
            ombg = nc_b.groups['ombg'].variables[vartype][:]
            oman = nc_a.groups['oman'].variables[vartype][:]
            obs_val_b = nc_b.groups['ObsValue'].variables[vartype][:]
            err_b = nc_b.groups['ObsError'].variables[vartype][:]
            err_a = nc_a.groups['ObsError'].variables[vartype][:]

            # Create the mask based on the main observation group [cite: 303]
            valid_mask = (~err_b.mask) & (~err_a.mask)
            if args.type == 'thresh':
                valid_mask = valid_mask & (obs_val_b > args.thresh)

            if not np.any(valid_mask):
                return [np.nan]*2, [np.nan]*2, [np.nan]*2, vartype, [np.nan]*2

            # Calculate RMSD and Bias
            rmsd = [np.sqrt(np.mean(ombg[valid_mask]**2)), np.sqrt(np.mean(oman[valid_mask]**2))]
            innov = [np.mean(ombg[valid_mask]), np.mean(oman[valid_mask])]

            # --- ROBUST ENSEMBLE PROCESSING ---
            ens_groups_b = sorted([g for g in nc_b.groups.keys() if g.startswith('hofx0_')])[:args.mems]
            ens_groups_a = sorted([g for g in nc_a.groups.keys() if g.startswith('hofx0_')])[:args.mems]

            def get_valid_hofx(nc_obj, groups, mask):
                member_data = []
                for g in groups:
                    data = nc_obj.groups[g].variables[vartype][:]
                    # CRITICAL: Check if this member's size matches the mask size [cite: 284, 321]
                    if data.shape == mask.shape:
                        member_data.append(data[mask])
                    else:
                        if args.verbose:
                            print(f"Warning: Member {g} shape {data.shape} mismatch with mask {mask.shape}. Skipping member.")
                return np.stack(member_data) if member_data else None

            h_b = get_valid_hofx(nc_b, ens_groups_b, valid_mask)
            h_a = get_valid_hofx(nc_a, ens_groups_a, valid_mask)

            if h_b is None or h_a is None:
                return rmsd, innov, [np.nan]*2, vartype, [np.nan]*2

            # Total Spread calculation [cite: 303]
            spread = [
                np.sqrt(np.mean(err_b[valid_mask]**2 + np.var(h_b, axis=0))),
                np.sqrt(np.mean(err_a[valid_mask]**2 + np.var(h_a, axis=0)))
            ]

            # --- NEW: Consistency Ratio calculation ---
            # Avoid division by zero
            cr = [
                rmsd[0] / spread[0] if spread[0] > 0 else np.nan,
                rmsd[1] / spread[1] if spread[1] > 0 else np.nan
            ]

            return rmsd, innov, spread, vartype, cr

    except Exception as e:
        if args.verbose:
            print(f"Error processing {meta['hm_str']}: {e}")
        return [np.nan]*2, [np.nan]*2, [np.nan]*2, None, [np.nan]*2

################################################################################

def process_gross_error_cycle(meta, obname, args):
    """
    Worker function to process gross error check data.
    Now includes verbose path logging and flexible variable detection.
    """
    path_b = os.path.join(meta['dir_b'], f'jdiag_{obname}.nc')

    # Verbose message before reading the file
    if args.verbose:
        print(f"DEBUG: Attempting to read diagnostic file: {path_b}")

    if not os.path.exists(path_b):
        if args.verbose:
            print(f"DEBUG: File not found: {path_b}")
        return np.nan, np.nan, np.nan

    try:
        with Dataset(path_b, 'r') as nc_b:
            # Navigate to the DiagnosticFlags group [cite: 1, 4]
            if 'DiagnosticFlags' not in nc_b.groups:
                return np.nan, np.nan, np.nan

            diag_group = nc_b.groups['DiagnosticFlags']
            if 'gross_error_check' not in diag_group.groups:
                return np.nan, np.nan, np.nan

            gec_group = diag_group.groups['gross_error_check']

            # Flexible Variable Detection:
            # This looks for any variable name present in the group
            avail_vars = list(gec_group.variables.keys())
            if not avail_vars:
                if args.verbose:
                    print(f"DEBUG: No variables found in gross_error_check group for {path_b}")
                return np.nan, np.nan, np.nan

            # Select the first available variable (e.g., equivalentReflectivityFactor)
            vartype = avail_vars[0]
            var = gec_group.variables[vartype]

            # Disable auto-masking to read raw integer flags [cite: 2]
            var.set_auto_mask(False)
            gec_data = var[:]

            total = len(gec_data)

            # JEDI Logic: 0 is Passed, non-zero is Rejected
            rejected = int(np.sum(gec_data != 0))
            assimilated = int(total - rejected)

            if args.verbose:
                print(f"DEBUG {meta['hm_str']}: Variable '{vartype}' | Total: {total} | Rej: {rejected}")

            return total, assimilated, rejected

    except Exception as e:
        if args.verbose:
            print(f"ERROR: Failed to process {path_b}: {e}")
        return np.nan, np.nan, np.nan
################################################################################
def plot_ob_type(obname, cycle_meta, args):
    """Aggregates parallel results and generates the sawtooth plot with dynamic y-limits."""

    with ProcessPoolExecutor(max_workers=args.nprocs) as executor:
        futures = [executor.submit(process_single_cycle, meta, obname, args) for meta in cycle_meta]
        results = [f.result() for f in futures]

    raw_minutes, raw_labels = [], []
    raw_rmsd, raw_innov, raw_spread, raw_cr = [], [], [], []
    found_vartypes = []

    for i, res in enumerate(results):
        m = cycle_meta[i]
        raw_minutes.extend([m['elapsed'], m['elapsed']])
        raw_labels.extend([m['hm_str'], m['hm_str']])
        raw_rmsd.extend(res[0])
        raw_innov.extend(res[1])
        raw_spread.extend(res[2])
        raw_cr.extend(res[4]) # Added
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

    cr = [raw_cr[i] for i, v in enumerate(valid_mask) if v]

    fig, ax = plt.subplots(figsize=(10, 5))
    ln1 = ax.plot(minutes, rmsd, color='tab:red', label='RMSD (O-F/A)', lw=2)
    ln2 = ax.plot(minutes, innov, color='tab:blue', label='Bias', lw=2)
    ln3 = ax.plot(minutes, spread, color='tab:green', linestyle='--', label='Total Spread', lw=2)

    lines = ln1 + ln2 +ln3

    # --- ADDED: Consistency Ratio Secondary Axis ---
    if args.cr:
        ax_cr = ax.twinx()
        ln4 = ax_cr.plot(minutes, cr, color='black', linestyle=':', label='Consistency Ratio', lw=1.5)
        ax_cr.set_ylabel("Consistency Ratio [RMSD / Spread]", fontsize=12)
        ax_cr.axhline(1.0, color='gray', lw=1, alpha=0.5, linestyle='-')
        ax_cr.set_ylim([0, 2.5]) # CR usually hovers around 1.0
        lines += ln4

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
    # Consolidated Legend for both axes
    labs = [l.get_label() for l in lines]
    ax.legend(lines, labs, loc='upper right', frameon=True, shadow=True)
    #ax.legend(loc='upper right', frameon=True, shadow=True)
    ax.grid(True, alpha=0.3)

    out_name = f"sawtooth_{args.eventdate}_{obname}.png"
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
        if cli_args.number:
            plot_gross_error(ob, meta_list, cli_args)
        else:
            plot_ob_type(ob, meta_list, cli_args)
