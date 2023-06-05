This directory contains the workflow to run a CONUS domain 3-km MPAS forecast
based on HRRR, RRFS and GFS datasets, and the workflow for MPAS-based WoFS system.

README.md

1. CONUS MPAS workflow

    run_mpas.sh
    cron.txt

2. MPAS-base WoFS workflow

            Common_Utilfuncs.sh
    Step 1: setup_mpas-wofs_grid.sh
    Step 2: make_ics.sh
    Step 3: make_lbc.sh
    Step 4: run_dacycles.sh
    Step 5: run_fcst.sh

3. Other scripts for users' convenience

    lnwrkfiles.sh    # Link necessary programs, runtime files and fixed files

    cleanmpas        # Clean run-time output from a MPAS run
    lnmpasrun        # Link MPS run-time time for users to run the program by themselves
    tarmpas          # tar a MPAS CONUS run directory for seeking support from NCAR,
                     # not ncessary now since we got an account on Cheyenne.