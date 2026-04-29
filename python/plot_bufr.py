#!/usr/bin/env python3
import os
import sys
import struct
import argparse
from datetime import datetime, timedelta
import numpy as np
import ncepbufr
import netCDF4
import matplotlib.pyplot as plt
import metpy.calc as mpcalc
from metpy.plots import SkewT
from metpy.units import units

################################################################################
# Global Constants and Default Config
################################################################################

TIME_MIN = -3.0
TIME_MAX = 3.0
NOBS_CHUNK = 200
QC_FILLVAL = 255

################################################################################
def print_inventory(filename, show_vars=False):
    """
    Scans the BUFR file and prints a summary.
    If show_vars is False, the Variable List column is hidden entirely.
    """
    if not os.path.exists(filename):
        print(f"Error: The file '{filename}' does not exist.")
        sys.exit(1)

    try:
        bufr = ncepbufr.open(filename)
    except Exception as e:
        print(f"Error: Could not open BUFR file. {e}")
        sys.exit(1)

    # Shorthand     Official BUFR Mnemonic  Descriptionps
    # ps            POB                     Pressure Observation (Surface or Station Pressure)
    # t             TOB                     Temperature Observation
    # q             QOB                     Specific Humidity Observation
    # pw            PWO                     Precipitable Water Observation
    # sst           SSTH                    Sea Surface Temperature (High Resolution)
    # uv            UOB, VOB                U and V Wind Components
    # spd           WSPD                    Wind Speed
    # dw            TDO                     Dew Point Observation (TDO is standard in PrepBUFR)
    # srw           SOLR                    Solar Radiation (Standard NCEP mnemonic)

    # Variables to probe (only used if show_vars is True)
    # Probes list updated with official NCEP mnemonics
    probe_vars = [
        'POB', 'TOB', 'QOB', 'PWO', 'SSTH', 'UOB', 'VOB', 'WSPD', 'TDO', 'SOLR', # Your specific list
        'ZOB', 'TDO', 'WDIR', 'PRSS', 'PMO', 'HOVI', 'PCLV', 'TOV', 'QOV', 'UOV',
        'VOV', 'TQM', 'QQM', 'WQM', 'ZQM', 'PQM', 'DDO', 'STNP', 'SALN', 'DBSS'
    ]

    inventory = {}
    nmessages = 0

    while bufr.advance() == 0:
        nmessages += 1
        mtype = bufr.msg_type
        mdate_dt = datetime.strptime(str(bufr.msg_date), '%Y%m%d%H')

        key = (mtype, bufr.msg_date)
        if key not in inventory:
            inventory[key] = {'count': 0, 'types': set(), 'obs_times': [], 'vars': set()}

        inventory[key]['count'] += 1

        while bufr.load_subset() == 0:
            if show_vars:
                for p in probe_vars:
                    try:
                        val = bufr.read_subset(p).squeeze()
                        if not np.ma.is_masked(val):
                            inventory[key]['vars'].add(p)
                    except:
                        continue

            try:
                data = bufr.read_subset('TYP DHR').squeeze()
                t_val = data[0, 0] if data.ndim > 1 else data[0]
                d_val = data[1, 0] if data.ndim > 1 else data[1]

                if not np.ma.is_masked(t_val):
                    inventory[key]['types'].add(int(t_val))
                if not np.ma.is_masked(d_val):
                    obs_time = mdate_dt + timedelta(hours=float(d_val))
                    inventory[key]['obs_times'].append(obs_time)
            except:
                pass

    bufr.close()

    # Define base column widths
    type_w, cycle_w, count_w, typlist_w, varlist_w, timerange_w = 10, 10, 6, 45, 45, 15

    # Construct header based on show_vars
    header_parts = [
        f"{'Type':<{type_w}}",
        f"{'Cycle':<{cycle_w}}",
        f"{'Count':<{count_w}}",
        f"{'Type List':<{typlist_w}}"
    ]

    if show_vars:
        header_parts.append(f"{'Variable List':<{varlist_w}}")

    header_parts.append(f"{'Time Range':<{timerange_w}}")
    header = " | ".join(header_parts)

    line_length = len(header)
    print(f"\nReading file: {filename}")
    print(f"Total messages: {nmessages}")
    print(header)
    print("-" * line_length)

    for (mtype, mdate) in sorted(inventory.keys()):
        data = inventory[(mtype, mdate)]

        # Format Type List
        typs = sorted(list(data['types']))
        typ_str = ", ".join(map(str, typs)) if typs else "N/A"
        if len(typ_str) > typlist_w:
            typ_str = typ_str[:typlist_w-3] + "..."

        # Build row parts
        row_parts = [
            f"{mtype:<{type_w}}",
            f"{mdate:<{cycle_w}}",
            f"{data['count']:<{count_w}}",
            f"{typ_str:<{typlist_w}}"
        ]

        if show_vars:
            v_list = sorted(list(data['vars']))
            var_str = " ".join(v_list) if v_list else "N/A"
            if len(var_str) > varlist_w:
                var_str = var_str[:varlist_w-3] + "..."
            row_parts.append(f"{var_str:<{varlist_w}}")

        # Format Time Range
        times = data['obs_times']
        time_str = f"{min(times):%H:%M}-{max(times):%H:%M}" if times else "N/A"
        row_parts.append(f"{time_str:<{timerange_w}}")

        print(" | ".join(row_parts))

    print("-" * line_length)
    return inventory

################################################################################
def bufr2nc(bufr, nc, skiptypes):
    """
    Read bufr message from PrepBufr file and write to NetCDF.
    """
    bufr_obj = {}
    nmessages = 0
    while bufr.advance() == 0:
        if bufr.msg_type in skiptypes:
            continue
        nmessages += 1
    bufr.rewind()

    bufr_obj['nmessages'] = nmessages
    bufr_obj['msgtypes'] = {}

    hdstr = 'SID XOB YOB DHR TYP ELV SAID T29'
    obstr = 'POB QOB TOB ZOB UOB VOB PWO CAT PRSS TDO PMO XDR YDR HRDR'
    qcstr = 'PQM QQM TQM ZQM WQM PWQ PMQ'
    oestr = 'POE QOE TOE ZOE WOE PWE'

    # Create Dimensions
    nc.createDimension('hdrinfo', len(hdstr.split()))
    nc.createDimension('obinfo', len(obstr.split()))
    nc.createDimension('oeinfo', len(oestr.split()))
    nc.createDimension('qcinfo', len(qcstr.split()))
    nc.createDimension('nobs', None)
    nc.createDimension('nmsgs', nmessages)
    nc.createDimension('nchar_id', 256)
    nc.createDimension('nchar_type', 20)

    # Create Core Variables
    hdrdata = nc.createVariable('header', np.float64, ('nobs', 'hdrinfo'), fill_value=bufr.missing_value, zlib=True)
    obdata = nc.createVariable('obdata', np.float32, ('nobs', 'obinfo'), fill_value=bufr.missing_value, zlib=True)
    obid = nc.createVariable('obid', 'S1', ('nobs', 'nchar_id',), zlib=True)

    nob = 0
    obid_set = set()
    nmsg = 0

    while bufr.advance() == 0:
        if bufr.msg_type in skiptypes:
            continue

        hdrarr, obsarr, qcarr, errarr, obidarr = [], [], [], [], []
        nobs_message = 0
        nmsg += 1

        while bufr.load_subset() == 0:
            hdr = bufr.read_subset(hdstr).squeeze()
            obs = bufr.read_subset(obstr)
            qc = bufr.read_subset(qcstr)
            err = bufr.read_subset(oestr)

            for nlev in range(obs.shape[-1]):
                lon, lat, time, z = hdr[1], hdr[2], hdr[3], hdr[5]
                press = obs[0, nlev]

                # Special handling for balloon drift
                if hdr[4] in [120, 220, 221]:
                    lon, lat = obs[11, nlev], obs[12, nlev]
                    if TIME_MIN <= obs[13, nlev] < TIME_MAX:
                        time = obs[13, nlev]

                obidstr = "%s %3i %6.2f %6.2f %9.5f %5i %6.1f" % (hdr[0].tobytes(), hdr[4], lon, lat, time, z, press)
                if obidstr in obid_set:
                    continue
                obid_set.add(obidstr)

                hdrarr.append(hdr.squeeze())
                obidarr.append(obidstr)
                obsarr.append(obs[:, nlev])
                errarr.append(err[:, nlev])
                qcarr.append(qc[:, nlev])
                nob += 1
                nobs_message += 1

        if nobs_message > 0:
            nob1 = nob - nobs_message
            nc['header'][nob1:nob] = np.array(hdrarr)
            nc['obdata'][nob1:nob] = np.array(obsarr)
            nc.sync()

    return bufr_obj

################################################################################
def read_snd(filename, outtable=None):
    """Extract sounding data specifically for ADPUPA messages."""
    bufr = ncepbufr.open(filename)
    if outtable:
        bufr.dump_table(outtable)

    stations = {}
    while bufr.advance() == 0:
        if bufr.msg_type == "ADPUPA":
            msgtime = datetime.strptime(str(bufr.msg_date), '%Y%m%d%H')
            while bufr.load_subset() == 0:
                sco = bufr.read_subset('SID').squeeze()
                typ = bufr.read_subset('TYP').squeeze()
                xob = bufr.read_subset('XOB').squeeze()
                yob = bufr.read_subset('YOB').squeeze()
                dhr = bufr.read_subset('DHR').squeeze()
                tob = bufr.read_subset('TOB').squeeze()
                tdo = bufr.read_subset('TDO').squeeze()
                pob = bufr.read_subset('POB').squeeze()
                uob = bufr.read_subset('UOB').squeeze()
                vob = bufr.read_subset('VOB').squeeze()

                sid = struct.pack('d', sco).decode("utf-8").strip()
                obt = msgtime + timedelta(hours=dhr.compressed()[0])

                if sid not in stations:
                    stations[sid] = {'lat': yob, 'lon': xob if xob < 180 else xob-360., 'time': obt}

                if typ < 200:
                    mask = np.any([tob.mask, tdo.mask], axis=0)
                    pob.mask, tob.mask, tdo.mask = mask, mask, mask
                    stations[sid]['ps'] = pob.compressed() * units.hPa
                    stations[sid]['T'] = tob.compressed() * units.degC
                    stations[sid]['Td'] = tdo.compressed() * units.degC
                else:
                    mask = np.any([uob.mask, vob.mask], axis=0)
                    pob.mask, uob.mask, vob.mask = mask, mask, mask
                    stations[sid]['pv'] = pob.compressed() * units.hPa
                    stations[sid]['u'] = uob.compressed() * units.meter/units.second
                    stations[sid]['v'] = vob.compressed() * units.meter/units.second
    bufr.close()
    return stations

################################################################################
def plot_skewt(p, t, td, puv=None, u=None, v=None, title=None, outfile=None):
    """Generate a Skew-T Log-P diagram using MetPy."""
    fig = plt.figure(figsize=(9, 9))
    skew = SkewT(fig, rotation=30)

    skew.plot(p, t, 'r', linewidth=2)
    skew.plot(p, td, 'g', linewidth=2)
    if u is not None and v is not None:
        skew.plot_barbs(puv, u, v)

    skew.ax.set_ylim(1000, 100)
    skew.ax.set_xlim(-40, 60)

    lcl_pressure, lcl_temperature = mpcalc.lcl(p[0], t[0], td[0])
    parcel_prof = mpcalc.parcel_profile(p, t[0], td[0]).to('degC')

    skew.plot(lcl_pressure, lcl_temperature, 'ko', markerfacecolor='black')
    skew.plot(p, parcel_prof, 'k--', linewidth=1)
    skew.shade_cin(p, t, parcel_prof)
    skew.shade_cape(p, t, parcel_prof)
    skew.plot_dry_adiabats()
    skew.plot_moist_adiabats()
    skew.plot_mixing_lines()

    if title:
        plt.title(title)

    if outfile is None:
        outfile = 'skewt.png'
    fig.savefig(outfile, format='png')
    plt.close(fig)

################################################################################
def main():
    parser = argparse.ArgumentParser(description="Process NCEP PrepBUFR files")
    parser.add_argument("input", help="Input PrepBUFR file")
    parser.add_argument("--nc", help="Output NetCDF file path")
    parser.add_argument("--plot", action="store_true", help="Generate Skew-T plots for ADPUPA messages")
    parser.add_argument("--table", help="Output BUFR table file")
    parser.add_argument("--vars", action="store_true", help="Show possible variable list", default=False)

    args = parser.parse_args()

    # Default action: Print comprehensive inventory
    print_inventory(args.input, args.vars)

    if args.nc:
        print(f"Converting to NetCDF: {args.nc}")
        bufr_in = ncepbufr.open(args.input)
        nc_out = netCDF4.Dataset(args.nc, 'w', format='NETCDF4')
        bufr2nc(bufr_in, nc_out, ['SATWND'])
        bufr_in.close()
        nc_out.close()
        print("NetCDF conversion complete")

    if args.plot:
        print("Generating sounding plots...")
        stations = read_snd(args.input, args.table)
        for sid, stn in stations.items():
            if 'ps' in stn and len(stn['ps']) > 10:
                outfile = f"skewt_{sid}_{stn['time']:%Y%m%d%H}.png"
                print(f"Plotting {sid}")
                plot_skewt(stn['ps'], stn['T'], stn['Td'], stn.get('pv'), stn.get('u'), stn.get('v'), sid, outfile)

################################################################################
if __name__ == "__main__":
    main()