This directory contains the workflow to run a CONUS domain 3-km MPAS forecast
based on HRRR, RRFS and GFS datasets, and the workflow for MPAS-based WoFS system.

README.md

1. CONUS MPAS workflow

    run_mpas.sh
    cron.txt

2. MPAS-base WoFS workflow

            Common_Utilfuncs.sh
    Step 1: setup_mpas-wofs_grid.sh
            edit file `$WORKDIR/config.${eventdate}` for runtime configurations as needed
    Step 2: make_ics.sh
    Step 3: make_lbc.sh
    Step 4: run_dacycles.sh
    Step 5: run_fcst.sh

3. Other scripts for users' convenience

    lnwrkfiles.sh    # Link necessary programs, runtime files and fixed files

    cleanmpas.sh     # Clean run-time output from a MPAS run, a set of ensemble MPAS runs or the post-processing files
    lnmpasrun        # Link MPAS run-time time for users to run the program manually
    lnmpasfcst.sh    # Link MPASSIT processed MPAS forecasts to a directory that simulates
                     # the WRF-WoFS forecasts, the purpose is to use WoFS-post directly
                     # without modification
    mpasruntime.sh   # Check MPAS-WoFS program runtime for all ensemble members or the time step for a single MPAS forecast
    tarmpas          # tar a MPAS CONUS run directory for seeking support from NCAR,
                     # not ncessary now since we got an account on Cheyenne.

    plot_allobs.sh   # Plot Data assimilation diagnostic pictures
    runmpasjobs.sh   # Higher level script to run the MPAS-WoFS workflow interactively
                     # or using Linux at/cronb facility for 2024 NSSL near-realtime experiments
                     # 1. DA;   2. FCST;            on Vecna
                     # 3. post; 4. plot; 5. diag    on wof-epyc8
    seq_filter.py    # DART obs_seq file filter or examiner
