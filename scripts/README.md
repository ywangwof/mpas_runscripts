This directory contains the workflow to run a CONUS domain 3-km MPAS forecast
based on HRRR, RRFS and GFS datasets, and the workflow for MPAS-based WoFS system.

README.md

1. CONUS MPAS workflow

    run_mpas.sh
    cron.txt

2. MPAS-base WoFS workflow

            Common_Utilfuncs.sh Common_Colors.sh Site_Runtime.sh
    Step 1: setup_mpas-wofs.sh
            edit file `$WORKDIR/config.${eventdate}` for runtime configurations as needed
    Step 2: make_ics.sh
    Step 3: make_lbc.sh
    Step 4: run_dacycles.sh
    Step 5: run_fcst.sh

3. Other scripts for users' convenience

    lnwrkfiles.sh    # Link necessary programs, runtime files and fixed files

    cleanmpas.sh     # Clean run-time output from a MPAS run, a set of ensemble MPAS runs or the post-processing files
    lnmpasrun.sh     # Link MPAS run-time time for users to run the program manually
    lnmpasfcst.sh    # Link MPASSIT processed MPAS forecasts to a directory that simulates
                     # the WRF-WoFS forecasts, the purpose is to use WoFS-post directly
                     # without modification
    mpasruntime.sh   # Check MPAS-WoFS program runtime for all ensemble members or the time step for a single MPAS forecast
    tarmpas          # tar a MPAS CONUS run directory for seeking support from NCAR,
                     # not ncessary now since we got an account on Cheyenne.

    plot_allobs.sh   # Plot Data assimilation diagnostic pictures
    runmpasjobs.sh   # Higher level script to run the MPAS-WoFS workflow interactively
                     # or using Linux at/cronb facility for 2024 NSSL near-realtime experiments
                     # 1. DA;   2. FCST;                    on Vecna
                     # 3. post; 4. plot; 5. diag; 6. snd    on wof-epyc8
    seq_filter.py    # DART obs_seq file filter or examiner

## Get started at NSSL with a existing case.

        Git repository is https://github.com/ywangwof/mpas_runscripts.git, and the branch name *WoFS_develop*.

        A quick way to get started is to copy the whole directory /home/yunheng.wang/MPAS/intel/mpas_scripts.develop
        to avoid the initial setting up. (remember to change the directory names in config.YYYYmmdd_EXPNAME for
        vertLevel_file, WPSGEOG_PATH, FIXDIR, TEMPDIR, EXEDIR and OBS_DIR etc.).

        You can also use the above directory directly without copying, but my occasional modifications may
        interfere with your runs (a consistence concern).

    Since we have set up a few cases in /scratch/wofs_mpas/run_dirs, you do not have to run steps 1-3,
    but just run steps 4 & 5 for any of those existing cases.

    You had better create a new directory to do your exercises to avoid overwriting my works accidentally.

    1. Copy any case configuration file to your exercise directory, for example config.20250702_V822Reduced.
       The extension "_V822Reduced" denotes the experiment name and it can be empty.

       In section [dacycles], add filter_option="bnrhf_qceff_table_wofs.csv" will use the Rank Histogram filter.
       Otherwise, it will use the EAKF filter.

       Please compare file config.20250703_V822RHF with config.20250703_V822Reduced for the difference.

       The case configuration file will be generated automatically with 'scripts/setup_mpas-wofs.sh'.

    2. Link the initialization and boundary files to avoid regenerating them. For examples,

       YYYYmmdd/init     -> your_working_directory/YYYYmmdd/init       (can be generated using scripts/make_ics.sh)
       YYYYmmdd/lbc      -> your_working_directory/YYYYmmdd/lbc        (can be generated using scripts/make_lbc.sh)
       YYYYmmdd/geo_d1   -> your_working_directory/YYYYmmdd/geo_d1     (can be generated using scripts/setup_mpas-wofs.sh
       YYYYmmdd/mpas_d1  -> your_working_directory/YYYYmmdd/mpas_d1    (can be generated using scripts/setup_mpas-wofs.sh

    3. Run the following tasks:

       a. scripts/runmpasjobs.sh /your_working_directory/config.YYYYmmdd_EXPNAME dacycles
       b. scripts/runmpasjobs.sh /your_working_directory/config.YYYYmmdd_EXPNAME fcst
       c. scripts/runmpasjobs.sh /your_working_directory/config.YYYYmmdd_EXPNAME post
       d. scripts/runmpasjobs.sh /your_working_directory/config.YYYYmmdd_EXPNAME plot
       e. scripts/runmpasjobs.sh /your_working_directory/config.YYYYmmdd_EXPNAME verif
       f. scripts/runmpasjobs.sh /your_working_directory/config.YYYYmmdd_EXPNAME snd
       g. scripts/runmpasjobs.sh /your_working_directory/config.YYYYmmdd_EXPNAME diag

       Where 'scripts/runmpasjobs.sh' is provided for convenience, you can also run the low-level scripts,
       run_dacycles.sh, run_fcst.sh etc. directly (see the log files in your_working_directory/YYYYmmdd).
       All command have a '-h' option for instructions.

       'EXPNAME' is an experiment name of your choice. if '_EXPNAME' is empty, the DA cycles and FCST runs will be
       in subdirectory /your_working_directory/YYYYmmdd/dacycles and /your_working_directory/YYYYmmdd/fcst, respectively.
       Otherwise, the subdirectory names will be 'dacycles_EXPNAME' and 'fcst_EXPNAME'.

       I run tasks a-b on Vecna, and tasks c-g on WoF-epyc8.

       Tasks a & b can be run simultaneously.

       Tasks d, e, f depend on task c, and tasks c and g depend on task b.

