#!/usr/bin/env python
#
# This module creates a collection of MPL Path Patches using multiprocesses for an MPAS unstructured mesh.
#
# Given an MPAS mesh file, `get_mpas_patches` will create a Path Patch for each MPAS grid, by looping
# over a Cell's vertices. Because this operation is a nCell * nEdge operation, it will take some
# quite some time. Using multiprocessing will speed up the process significantly.
#
# However, once a patch collection is created it is saved (using Python's Pickle module) as a 'patch'
# file. This patch file can be loaded for furture plots on that mesh, which will speed up future
# plots creation.
#
# This module was created based on "mpas_patches.py" from the following repository:
#
# * https://github.com/MiCurry/MPAS-Plotting
#
#  Note that the generated Pickle file is Matplotlib version dependent.
#  You may have to recreate this file after the Python environment is changed.
#
#-----------------------------------------------------------------------
#
# By Yunheng Wang (NOAA/NSSL, 2022.10.10)
#
#-----------------------------------------------------------------------
import os
import sys
import time
import pickle as pkle
import math

import numpy as np
import matplotlib.collections as mplcollections
import matplotlib.patches as patches
import matplotlib.path as path

import multiprocessing as mp

from netCDF4 import Dataset
import argparse

########################################################################

def dump(obj, level=0, maxlevel=10):
    for a in dir(obj):
        val = getattr(obj, a)
        if  a.startswith("__") and a.endswith("__") or a.startswith("_"):
            continue
        elif isinstance(val, (int, float, str, list, dict, set)):
            print(f"{level*'    '} {a} -> {val}")
        else:
            print(f"{level*'    '} {a} -> {val}")
            if level >= maxlevel:
                return
            dump(val, level=level+1,maxlevel=maxlevel)

########################################################################

def update_progress(job_title, progress):
    length = 40
    block = int(round(length*progress))
    msg = "\r{0}: [{1}] {2}%".format(job_title, "#"*block + "-"*(length-block),
                                     round(progress*100, 2))
    if progress >= 1: msg += " DONE\r\n"
    sys.stdout.write(msg)
    sys.stdout.flush()

########################################################################

def get_mpas_patches(istart, isize, connect, patch_queue):

    nEdgesOnCell   = connect.recv()
    verticesOnCell = connect.recv()
    latVertex      = connect.recv()
    lonVertex      = connect.recv()

    mesh_patches = [None] * isize

    myproc = mp.current_process()
    print(f"Process {myproc.name} processing {isize} cells starting from {istart}", flush=True)

    for cell in range(istart,istart+isize):
        # For each cell, get the latitude and longitude points of its vertices
        # and make a patch of that point vertices
        vertices = verticesOnCell[cell,:nEdgesOnCell[cell]]
        vertices = np.append(vertices, vertices[0:1])

        vertices -= 1         # 1-based to 0-based indices

        vert_lats = np.array([])
        vert_lons = np.array([])

        for lat in latVertex[vertices]:
            vert_lats = np.append(vert_lats, lat * (180 / np.pi))

        for lon in lonVertex[vertices]:
            dlon = ( (lon * (180 / np.pi))%360 + 540)%360 -180.
            vert_lons = np.append(vert_lons, dlon)

        # Normalize latitude and longitude
        diff = np.subtract(vert_lons, vert_lons[0])
        vert_lons[diff > 180.0] = vert_lons[diff > 180.] - 360.
        vert_lons[diff < -180.0] = vert_lons[diff < -180.] + 360.

        coords = np.vstack((vert_lons, vert_lats))

        cell_path = np.ones(vertices.shape) * path.Path.LINETO
        cell_path[0] = path.Path.MOVETO
        cell_path[-1] = path.Path.CLOSEPOLY
        cell_patch = path.Path(coords.T,
                               codes=cell_path,
                               closed=True,
                               readonly=True)

        mesh_patches[cell-istart] = patches.PathPatch(cell_patch)

    patch_queue.put((istart,isize,mesh_patches))

    return

if __name__ == "__main__":

    parser = argparse.ArgumentParser(description='Create MPAS patch file for plot_mpaspatch.py',
                                     epilog='''        ---- Yunheng Wang (2022-10-10).
                                            ''')
                                     #formatter_class=CustomFormatter)

    parser.add_argument('gridfile',help='MPAS forecast file')

    parser.add_argument('-v','--verbose',   help='Verbose output',                             action="store_true", default=False)
    parser.add_argument('-n','--nprocess',  help='Number of processes',                        type=int,            default=None)
    parser.add_argument('-o','--outfile',   help='Name of output file or output directory',    type=str,            default=None)

    args = parser.parse_args()

    if args.nprocess is None:
        #print(mp.cpu_count())
        #print(os.cpu_count())
        nprocess = mp.cpu_count()//2
    else:
        nprocess = args.nprocess

    if args.outfile is None:
        outdir       = './'
        pickle_fname = None
    elif os.path.isdir(args.outfile):
        outdir       = args.outfile
        pickle_fname = None
    else:
        outdir       = os.path.dirname(args.outfile)
        pickle_fname = os.path.basename(args.outfile)

    if not os.path.lexists(args.gridfile):
        print("ERROR: need a MPAS history/diag file.")
        sys.exit(1)

    #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

    time0 = time.time()

    with Dataset(args.gridfile,'r') as mesh:
        nCells         = len(mesh.dimensions['nCells'])
        nEdgesOnCell   = mesh.variables['nEdgesOnCell'][:]
        verticesOnCell = mesh.variables['verticesOnCell'][:]
        latVertex      = mesh.variables['latVertex'][:]
        lonVertex      = mesh.variables['lonVertex'][:]

    if pickle_fname is None:
        pickle_fname = os.path.basename(args.gridfile).split('.')[0]
        pickle_fname = pickle_fname+'.'+str(nCells)+'.'+'patches'
        pickle_fname = os.path.join(outdir,pickle_fname)

    lat_min = math.degrees(latVertex.min())
    lat_max = math.degrees(latVertex.max())
    lon_min = math.degrees(lonVertex.min())
    lon_max = math.degrees(lonVertex.max())

    if os.path.isfile(pickle_fname):
        print("Pickle file (", pickle_fname, ") exists. Skipping")
    else:

        print(f"\nNo pickle file found, creating patches \"{pickle_fname}\" using ({nprocess}) processes ...")
        print("If this is a large mesh, then this proccess will take a while...")

        baches_queue = mp.Queue(nprocess)                # queue to return processed cell patches
        connects =[mp.Pipe() for i in range(nprocess)]   # pipe for passing initial arrays

        nsize,nreminder = divmod(nCells,nprocess)

        arg_tuples = []
        istart = 0
        for i in range(nprocess):
            isize = nsize
            if i < nreminder:
                isize += 1
            arg_tuples.append((istart,isize,connects[i][0],baches_queue))
            istart += isize

        #print(arg_tuples)

        processes = [mp.Process(target=get_mpas_patches,args=arg_tuple) for arg_tuple in arg_tuples]

        for process in processes:
            process.start()

        for p in range(nprocess):
            connects[p][1].send(nEdgesOnCell   )
            connects[p][1].send(verticesOnCell )
            connects[p][1].send(latVertex      )
            connects[p][1].send(lonVertex      )

        mesh_patches = [None] * nCells
        nsize = 0
        for p in range(nprocess):
            i,isize,proc_patches    = baches_queue.get()
            mesh_patches[i:i+isize] = proc_patches

            nsize += isize
            update_progress("Creating Patch file: "+pickle_fname, nsize/nCells)

        for process in processes:
            process.join()

        # Create patch collection
        patch_collection = mplcollections.PatchCollection(mesh_patches)

        #
        # Write out a MPAS patch file
        #
        print(f"Writting to pickle file ({pickle_fname}) .... ")

        out_pkle = { "patches": patch_collection, "range": [lon_min-0.2,lon_max+0.2,lat_min-0.2,lat_max+0.2] }
        # Pickle the patch collection
        pickle_file = open(pickle_fname, 'wb')
        pkle.dump(out_pkle, pickle_file)
        pickle_file.close()

        time2 = time.time()
        print(f"\nCreated a patch file for mesh: {pickle_fname}. Used ({time2-time0}) seconds.")

    print(f"\nDomain range: {lat_min:0.2f},{lat_max:0.2f},{lon_min:0.2f},{lon_max:0.2f}")
