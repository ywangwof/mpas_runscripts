## Version History

03/21/2024 Version 4.1

    1. Upgraded to MPAS V8.0.1
    2. Upgraded to Rocky linux OS on Jet
    3. Note that "atmosphere_model.single" is renamed as "atmosphere_model" in exec

05/12/2023 Version 4.0

    a. Added DA cycles scripts for MPAS-WoFS.
	1. scripts/setup_mpas-wofs_grid.sh
	2. scripts/make_ics.sh
	3. scripts/make_lbc.sh
	4. scripts/run_dacycles.sh
	5. scripts/run_fcst.sh
    b. Separated subdirectories templates from fix_files
    c. Started to use scripts/Common_Utilfuncs.sh

11/14/2023 Version 3.5

    1. Added support for reservation rtwrfruc on Jet.
    2. Upgraded fix file SOILPARM.TBL with latest WRF pacakge, especially for RUC LSM
       with soil type 9.

11/01/2023 Version 3.4

    1. Incorporated fixes for diagnostic outputs when convection_scheme is turned off
       from the latest MPAS package within branch atmosphere/nssl_v7.3_smiol_lcc.
    2. Fixed a divide-by-zero float problem when computing 1-km hourly max reflectivity.
    3. Trimmed the docstring in scripts/run_mpas.sh.

08/24/2023 Version 3.3

    1. Added support for the RRFS-A North American datasets by converting
       the rotated lat/lon grid to the HRRR grid using wgrib2

    A new option "-i rrfsna" is added and it will depend the download
       RRFS-A NA data files from /lfs4/NAGAPE/wof/grib_files/RRFS-A.

06/20/2023 Version 3.2

    1. Added option config_microp_re following Ted's suggestion
    2. Updated static processing with new BNU soil type and parallel
       processing capability
    3. Separated subdirectory fix_files from templates.

05/12/2023 Version 3.1

    1. Fixed bug with hourly precipitation in convective_diagnostics.F.
    2. Improved resource usage on Jet.
    3. Used 768 core for jobs of ICs and LBCs instead of 800.
    4. Improved python scripts of plotting, especially for plotting precipitation fields.

    new executables:
       atmosphere_model.single
       init_atmosphere_model

04/28/2023 Version 3.0

    1. Bill implemented the analysis fields wind rotation in the MPAS init_atmosphere core
    2. Fix output of various UH values and 1-km max reflectivity
    3. Fix for RUC LSM soil moisture issues

    new executables:
       atmosphere_model.single
       init_atmosphere_model

04/26/2023 Version 2.0

    Here are the main updates:

    1. Upgrade the PNETCDF library because MPAS uses a feature that is not available with version 1.6;
    2. Add a wgrib2 step to rotate winds for the HRRR datasets;
    3. Process wgrib2 & ungrib in parallel mode for speedup;
    4. RRFS-initialized MPAS runs up to 60 hours

    new executables:
       atmosphere_model.single
       init_atmosphere_model
       ungrib.exe

## Steps to run the workflow on Vecna

    0. Download/Clone the workflow **mpas_scripts** and you will get

        * README.md                  * exec/
        * fix_files/                 * modules/
        * observations/              * python/
        * scripts/                   * templates/

    1. Use an existing program environment or build your own program environment
       based on the ones in _modules/_

        * env.mpas_smiol_gnu         **GNU** compiler suite
        * env.mpas_smiol_nvidia      **NVidia** compiler suite
        * env.mpas_smiol_intel       **Intel** compiler suite

      And link the program environment file to *modules/env.mpas*.

    2. Build the following programs from their corresponding source package
       using the program environment in *modules/env.mpas*.

        * frdd-MPAS-Model
        * frdd-DART
        * MPASSIT
        * MPAS-Tools/mesh_tools/grid_rotate
        * WPS_SRC (ungrib/geogrid only, will depend on the WRF package)
        * gpmetis (can use __/scratch/ywang/tools/bin/gpmetis__ directly)

    3. Link/Copy the built programs to _exec_ using _scripts/lnwrkfiles.sh_.

    4. Copy/Link static files to _fix_files_.

        * WOFSdomain.grid.nc
        * MP_THOMPSON_*_DATA.DBL (or generate them using program **build_tables**)

    5. Modify the default run-time configuration in file _scripts/setup_mpas-wofs_grid.sh_
       (Search for function *write_config*).

    6. Set up the domain and create the run-time configuration file in a working directory, __RUNDIR__, as

       $> scripts/setup_mpas-wofs_grid.sh -c ctrlat,ctrlon YYYYmmdd RUNDIR

    7. Edit the generated configuration file, __RUNDIR/config.YYYYmmdd__ for any specific
       runtime settings.

    8. Prepare ICs/LBCs for this case as

       $> scripts/make_ics.sh YYYYmmdd RUNDIR
       $> scripts/make_lbc.sh YYYYmmdd RUNDIR

    9. Run the Data Assimilation (DA) cycles as

       $> scripts/run_dacycles.sh YYYYmmdd RUNDIR

    10. Run the free forecasts starting from the correponding DA cycles

       $> scripts/run_fcst.sh YYYYmmdd RUNDIR

    11. On *WoF-epyc8*, run post-processing for this case.

        11.1. Downloaded the Python package, **frdd-wofs-post**.
        11.2. Prepare a simulated WRF forecast directory using __scripts/lnmpasfcst.sh__
        11.3. Edit the configuration file in __frdd-wofs-post/config/WOFS_MPAS_config.yaml__
        11.4. Run the following scripts in sequence
              * frdd-wofs-post/wofs/scripts/wofs_post_summary_files_MPAS.py
              * frdd-wofs-post/wofs/scripts/wofs_plot_summary_files_MPAS.py
              * frdd-wofs-post/wofs/scripts/wofs_plot_verification_MPAS.py

    12. For DA diagnostic plots, run __scripts/plot_allobs.sh__.

    13. To run the jobs in background (`cron`/`at`/`batch`), a simple script,
        __scripts/runmpasjobs.sh__, is provided to simplify the above steps from 9 to 12.

        13.1. Modify the hard-coded directory names in __scripts/runmpasjobs.sh__.
        13.2. Run the jobs as:

            On Vecna:
            * scripts/runmpasjobs.sh YYYYmmdd dacycles
            * scripts/runmpasjobs.sh YYYYmmdd fcst

            On WoF-epyc8:
            * scripts/runmpasjobs.sh YYYYmmdd post
            * scripts/runmpasjobs.sh YYYYmmdd diag
            * scripts/runmpasjobs.sh YYYYmmdd verif
            * scripts/runmpasjobs.sh YYYYmmdd plot

        13.2. Run-time log files will be generated automaticlly as __RUNDIR/log.TASKNAME__.
              where TASKNAME is one of [dacycles, fcst, post, plot, diag, verif].

Notes:

    *1 All the workflow scripts have an option "-h" to show a brief usage of
       the command line options.

    *2 All job scripts can be terminated using Ctrl+c. And resume from where stopped.

    *3 The log files from Step 13 can be visulized using **less**/**cat** or
       **~yunheng.wang/bin/viewlog** commands.
