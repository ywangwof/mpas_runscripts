#!/usr/bin/env python3
"""
NetCDF NaN and Format Checker
Usage: ./check_nans.py data.nc --format-only
"""

import sys
import argparse
import logging
import xarray as xr
import numpy as np
from netCDF4 import Dataset
from colorama import Fore, Style, init

# Initialize colorama
init(autoreset=True)

################################################################################
class ColoredFormatter(logging.Formatter):
    """Custom formatter to color-code log levels."""
    COLORS = {
        logging.DEBUG: Fore.CYAN,
        logging.INFO: Fore.GREEN,
        logging.WARNING: Fore.YELLOW,
        logging.ERROR: Fore.RED,
        logging.CRITICAL: Fore.RED + Style.BRIGHT,
    }

    def format(self, record):
        color = self.COLORS.get(record.levelno, Fore.WHITE)
        log_fmt = f"{Style.DIM}%(asctime)s{Style.RESET_ALL} {color}%(levelname)-8s{Style.RESET_ALL} %(message)s"
        return logging.Formatter(log_fmt, datefmt="%H:%M:%S").format(record)


################################################################################
def get_args():
    """Defines and parses command line arguments."""
    parser = argparse.ArgumentParser(
        description="Check NetCDF file type and NaN values."
    )
    parser.add_argument("file", help="Path to the netCDF (.nc) file")
    parser.add_argument(
        "-v", "--variable",
        help="Variable to check. If omitted, checks all variables."
    )
    parser.add_argument(
        "--format-only", action="store_true",
        help="Only check the file format and exit."
    )
    parser.add_argument(
        "--limit", type=int, default=5,
        help="Max number of NaN coordinates to print (default: 5)"
    )
    parser.add_argument(
        "--verbose", action="store_true",
        help="Show detailed debug information"
    )
    return parser.parse_args()


################################################################################
def setup_logger(verbose):
    """Initializes the logger."""
    logger = logging.getLogger("NC-Tool")
    logger.setLevel(logging.DEBUG if verbose else logging.INFO)
    if not logger.handlers:
        ch = logging.StreamHandler()
        ch.setFormatter(ColoredFormatter())
        logger.addHandler(ch)
    return logger


################################################################################
def get_nc_format(file_path):
    """Detects the underlying NetCDF storage format."""
    try:
        with Dataset(file_path, 'r') as nc:
            return nc.data_model
    except Exception as e:
        return f"Unknown (Error: {e})"


################################################################################
def run_nan_check(ds, var_name, log, limit):
    """Scans for NaNs and prints coordinate info."""
    da = ds[var_name]
    # Check for NaNs
    mask = da.isnull().values
    nan_indices = np.argwhere(mask)
    nan_count = len(nan_indices)

    if nan_count > 0:
        log.warning(f"VAR [{var_name}]: Found {nan_count} NaNs.")
        log.info(f"Locations (Indices for {list(da.dims)}):")

        for i in range(min(nan_count, limit)):
            idx_vals = nan_indices[i]
            # Build a string showing the position in the multidimensional grid
            pos_desc = [f"{dim}: {idx_vals[j]}" for j, dim in enumerate(da.dims)]
            print(f"   {Fore.CYAN}→ {', '.join(pos_desc)}")

        if nan_count > limit:
            print(f"   {Style.DIM}... and {nan_count - limit} more instances.")
        return True

    log.info(f"VAR [{var_name}]: Clean.")
    return False


################################################################################
def main():
    """Main logic flow."""
    args = get_args()
    log = setup_logger(args.verbose)

    # 1. Check Format
    nc_format = get_nc_format(args.file)
    print(f"{Style.BRIGHT}File Format: {Fore.MAGENTA}{nc_format}{Style.RESET_ALL}")

    if args.format_only:
        sys.exit(0)

    # 2. Run NaN Scan
    try:
        ds = xr.open_dataset(args.file, mask_and_scale=True)

        vars_to_check = [args.variable] if args.variable else list(ds.data_vars)
        if args.variable and args.variable not in ds.data_vars:
            log.error(f"Variable '{args.variable}' not found in {list(ds.data_vars)}")
            sys.exit(1)

        any_nans = False
        for var in vars_to_check:
            if run_nan_check(ds, var, log, args.limit):
                any_nans = True

        print("################################################################################")
        if not any_nans:
            log.info(f"{Fore.GREEN}SUCCESS: Dataset is NaN-free.")
        else:
            log.warning(f"{Fore.YELLOW}COMPLETED: Missing values detected.")

    except Exception as e:
        log.critical(f"Failed to process dataset: {e}")
        sys.exit(1)


################################################################################
if __name__ == "__main__":
    main()