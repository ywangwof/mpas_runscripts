#!/bin/bash
#SBATCH --partition=PARTION
#SBATCH -J JOBNAME
#SBATCH --ntasks=NOPART CPUSPEC
#SBATCH -t 00:30:00
#SBATCH --output=WRKDIR/LOGNAME_%j.log
ACCTSTR
EXCLSTR

#set -eux

time1=$(date '+%s')
printf "Job Started: %(%a %b %d %H:%M:%S %Z %Y)T. Job Id: %s\n\n" "$time1" "$SLURM_JOBID"

if [[ "MACHINE" == "Jet" || "MACHINE" == "Hercules" || "MACHINE" == "Ursa" ]]; then
    source /etc/profile.d/modules.sh
    module purge
    module use JEDIDIR/modulefiles
    module load MODULE
    export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:JEDIDIR/build/lib64
else
    source ROOTDIR/modules/MODULE
fi

module list

#
#--------------------------------------------
# Get Date information and set obs directory
#--------------------------------------------

datetime=DATETIME

ENS_AVERAGE_EXEC="EXEDIR/average_netcdf_files_parallel_mpas_efficient.x"
NETCDF_CONCATENATE_EXEC=EXEDIR/concatenate_netcdf_files.x # MPI executable to concatenate UFO files from all processors into one file
THINNING_HofX_EXEC="SCPDIR/yamlPlugs/thinning_hofx_serial.py"
jedi_exec="EXEDIR/mpasjedi_enkf.x"

JEDI_ANALYSIS_TYPE=TASKNAME
instruments=(INSTRUMENTS)
ens_size=ENS_SIZE

JEDI_RUN_DIR=WRKDIR

jedi_enkf_num_procs_observer=NOPART
jedi_enkf_num_procs_solver=NOPART

#-------------------------------------------------------
# Don't allow JEDI analysis for first date
#   Force user to only use first date for running
#   MPAS forecasts to move away from GFS/global ICs
#   (or potentially creating initial perturbed ensemble)
#-------------------------------------------------------

#relative_fcst_minutes=(0)
#
## Assume we need obs. If not, change (currently only false for $JEDI_ANALYSIS_TYPE == bump)
#observations_needed="true"
#
## Do we need the prior ensemble?
#need_prior_ensemble="true"
#
## Do we need a deterministic background?
#need_prior_deterministic_background="false"

#------------------------------------------------
# Set some options and working directory depending on JEDI application
#------------------------------------------------

echo "JEDI_ANALYSIS_TYPE = $JEDI_ANALYSIS_TYPE"

jobname="${JEDI_ANALYSIS_TYPE}"

#if [[ "$JEDI_ANALYSIS_TYPE" == "enkf_prior_mean" ]]; then
#    # dir_prefx="ens_mean"
#    jobname="prior_mean"
#    #jobbase="${jobname}"
#elif [[ "$JEDI_ANALYSIS_TYPE" == "enkf_prior_members" ]]; then
#    #dir_prefx="ens" # becomes member-dependent later
#    #member=${SLURM_ARRAY_TASK_ID}     # #PBS with "-J" flag (PBS pro)
#    #memstr=$(printf "%02d" "$member")
#    #JEDI_RUN_DIR=${JEDI_RUN_DIR}/ens_${memstr}
#    #jobname="prior_members_${memstr}"
#    jobname="prior_members"
#    #jobbase="prior_members"
#elif [[ "$JEDI_ANALYSIS_TYPE" == "enkf_all_at_once" ]]; then
#    #dir_prefx="enkf"
#    jobname="enkf_all"
#    #jobbase="${jobname}"
#elif [[ "$JEDI_ANALYSIS_TYPE" == "solver" ]]; then
#    : #dir_prefx="enkf"
#    jobname="solver"
#    #jobbase="${jobname}"
#elif [[ "$JEDI_ANALYSIS_TYPE" == "post" ]]; then
#    : #dir_prefx="enkf"
#    jobname="post"
#    #jobbase="${jobname}"
#else
#    echo "JEDI_ANALYSIS_TYPE = $JEDI_ANALYSIS_TYPE invalid. exit."
#    exit 1
#fi

#mkdir -p "${JEDI_RUN_DIR}"
#rm -f "queue.${jobbase}"

cd "${JEDI_RUN_DIR}"  || exit $?  # The working directory
#rm -f -- *.lock *.err *.abort

nnode=NNODES
#if (( NOPART % nnode == 0 )); then
    ncores=$(( NOPART/nnode ))
#fi

sed -i -e "/config_pio_num_iotasks/s/=.*/= $nnode/g;/config_pio_stride/s/=.*/= $ncores/" namelist.atmosphere_${datetime}

touch "running.${jobname}"
rm -rf "error.${jobname}" "queue.${jobname}"

jedi_output_dir=DBOUTDIR # Many JEDI output files will be put in here.

#------------------------------------------------
# For EnKF, it's helpful to have the ensemble mean background, so compute it. not critical to cycling,
# so don't check for errors
#------------------------------------------------

if [[ "$JEDI_ANALYSIS_TYPE" == "prior_mean" || "$JEDI_ANALYSIS_TYPE" == "enkf_all_at_once" ]]; then
    cp ./mpas_en001.nc ./mpas_prior_ensmean.nc # float variables in ./mpas_prior_ensmean.nc will be overwritten
    cp ./mpas_en001.nc ./mpas_prior_stddev.nc

    #ln -sf $ENS_AVERAGE_EXEC .
    calc_stddev="false"  # too slow for a really big problem, so set to false to bypass
    RUNMPCMD --nodes=$ens_size --ntasks-per-node=1 $ENS_AVERAGE_EXEC ${JEDI_RUN_DIR} mpas_prior_ensmean.nc mpas_prior_stddev.nc mpas_en $ens_size $calc_stddev > ./ensmean.log
    if [[ "$calc_stddev" == "false" ]]; then
       rm -f ./mpas_prior_stddev.nc # just get rid of it so we don't make mistakes
    fi
fi

# For EnKF copy ensemble background to analysis for each member; we'll overwrite the analysis.
if [[ "$JEDI_ANALYSIS_TYPE" == "solver" || "$JEDI_ANALYSIS_TYPE" == "enkf_all_at_once" ]]; then
    mpas_date=$(date -d "${datetime:0:8} ${datetime:8:4}" +%Y-%m-%d_%H.%M.%S)

    echo "JEDI_ANALYSIS_TYPE = $JEDI_ANALYSIS_TYPE, ens_size = $ens_size, Preparing analysis files ....."
    ie=1
    while [[ $ie -le $ens_size ]]; do
        m3=$(printf %03d $ie) # Each member must have three digits (i.e., 001, 010, 100)
        cp "mpas_en${m3}.nc" "analysis.${mpas_date}_en${m3}.nc"
        ((ie++))
    done
    cp mpas_en001.nc "analysis.${mpas_date}_en000.nc"     # ensemble mean
fi

#---------------
# Run MPAS-JEDI
#---------------
export OOPS_TRACE=0
export OOPS_DEBUG=0
export OMP_NUM_THREADS=1
export FI_CXI_RX_MATCH_MODE='hybrid'
export GFORTRAN_CONVERT_UNIT='big_endian:101-200' # needed for gfortran compiler
export F_UFMTENDIAN='big:101-200' # maybe needed for intel compiler

# cd again to $JEDI_RUN_DIR; under some strange conditions, probably a combination
# of job arrays on derecho, and possible use of 'pwd' in $mpas_environment_file
# (if $mpas_environment_file ==> jedi_environment), things can end up in the
# wrong directory. pretty strange, but just do it.
cd "${JEDI_RUN_DIR}"  || exit $?  # The working directory

if [[ "$JEDI_ANALYSIS_TYPE" =~ "prior" ]]; then
    # first run EnKF in "observer" mode

    if [[ "$JEDI_ANALYSIS_TYPE" == "prior_members" ]]; then
       sed -i '/Gaussian Thinning/{N;d;}' ./observer.yaml
       echo "Delete line 'Gaussian Thinning' and the line after it"
    fi

    echo "Running MPAS-JEDI $jedi_exec for $JEDI_ANALYSIS_TYPE as \"RUNMPCMD -n $jedi_enkf_num_procs_observer $jedi_exec ./observer.yaml  ./observer.log\"....."
    RUNMPCMD -n $jedi_enkf_num_procs_observer $jedi_exec ./observer.yaml  ./observer.log
    #pid=$!

    # When running many instances of MPAS-JEDI simultaneously, sometimes it hangs, so check for completion in log file
    # and move on if it's actually done, potentially killing things.
    #echo "$pid" > ./waiting
    #while [[ ! -e ./observer.log ]]; do
    #   sleep 10
    #done

    while true; do
        if grep -q "Finishing oops::LocalEnsembleDA<MPAS, UFO and IODA observations> with status = 0" ./observer.log ; then
           #|| \
           #grep -q "OOPS Ending" ./observer.log  || \
           #grep -q "Timing Statistics" ./observer.log ; then
            #rm -f ./waiting
            #if [[ $(ps | grep $pid | wc -l) == 1 ]]; then
            #   kill -9 $pid
            #fi
            rm -f observer.log.*
            break
        else
            echo "ERROR: Program jedi_exec failed."
            #sleep 5
            exit 5
        fi
    done

    echo "Done $jedi_exec for $JEDI_ANALYSIS_TYPE."
    # Done running MPAS-JEDI
    unset GFORTRAN_CONVERT_UNIT F_UFMTENDIAN OMP_NUM_THREADS

    #Load Python environment for thinning

    if [[ "$JEDI_ANALYSIS_TYPE" == "prior_mean" ]]; then
        for inst in "${instruments[@]}"; do
            fname1=${jedi_output_dir}/obsout_omb_${inst}.h5
            if [[ -e $fname1 ]]; then
                fname=${jedi_output_dir}/obsout_omb_${inst}_1st_pass.h5

                #Either use the next 5 lines...
                #ncks -O --no_abc $fname1 $fname # change the format to make IODA-v3 file netCDF4-compliant
                #ncrename -g "PreQC,PreQC_original"         $fname
                #ncrename -g "EffectiveQC0","PreQC"         $fname
                #ncrename -g "ObsError","ObsError_original" $fname
                #ncrename -g "EffectiveError0","ObsError"   $fname

                # ... or this line, which requires NOT resetting PreQC_maxvalue to 0
                python $THINNING_HofX_EXEC --thinning 1 --rundir $jedi_output_dir --hofxfile obsout_omb_${inst}.h5 --outfile obsout_omb_${inst}_1st_pass.h5

                # Link updated files to working directory for 2nd pass through ensemble mean prior
                mv ./"${inst}_obs_${datetime}.h5" ./"${inst}_obs_${datetime}_orig.h5"
                ln -sf "$fname" ./"${inst}_obs_${datetime}.h5"
            fi
        done
        #deactivate npl

        # Need to run JEDI again, using the files we just produced as our OBSERVATION files
        # The ensemble member files will use these files as observations, so we also need to use them for the ensemble mean
        # to ensure all observations are processed in the same order.
        # We also enforce a stricter quality control for the PreQC filter for this second pass, to mimic the setting for the members
        cp observer.yaml observer.yaml_1st_pass
        #sed -i "/PreQC/{n;s/${PreQC_maxvalue}/0/}" observer.yaml # replaces the line after PreQC; $PreQC_maxvalue -->0 (set PreQC to 0)
        # See https://stackoverflow.com/questions/64842342/bash-sed-replace-line-in-file-at-same-indentation-level
        #   this is to replace the line after Background Check at the same indentation level with threshold: 999999
        sed -i '/Background Check/{n;s/^\( *\).*/\1threshold: 999999/}' observer.yaml
        sed -i '/Gaussian Thinning/{N;d;}' observer.yaml

        # Run MPAS-JEDI again
        #source $jedi_environment_file
        #limit stacksize unlimited
        export OOPS_TRACE=0
        export OOPS_DEBUG=0
        export OMP_NUM_THREADS=1
        export GFORTRAN_CONVERT_UNIT='big_endian:101-200' # needed for gfortran compiler
        export F_UFMTENDIAN='big:101-200' # maybe needed for intel compiler

        RUNMPCMD -n $jedi_enkf_num_procs_observer $jedi_exec ./observer.yaml ./observer.log_again
        status=$?
        # we need to change the format of the obsout_omb files so we can use ncks on them later
        #source $default_environment_file # From driver
        unset GFORTRAN_CONVERT_UNIT F_UFMTENDIAN OMP_NUM_THREADS
        for inst in "${instruments[@]}"; do
            fname1=${jedi_output_dir}/obsout_omb_${inst}.h5
            if [[ -e $fname1 ]]; then
               fname=./tmp.h5
               ncks -O --no_abc "$fname1" $fname # change the format to make IODA-v3 file netCDF4-compliant
               status=$?
               mv "$fname" "$fname1"
            fi
        done
    fi # endif JEDI_ANALYSIS_TYPE == prior_mean

    if [[ "$JEDI_ANALYSIS_TYPE" == "prior_members" ]]; then
        for inst in "${instruments[@]}"; do
            fname1=${jedi_output_dir}/obsout_omb_${inst}.h5
            if [[ -e $fname1 ]]; then
                fname=./tmp.h5
                ncks -O --no_abc "$fname1" "$fname" # change the format to make IODA-v3 file netCDF4-compliant
                #groups=($(ncdump -h $fname | grep group: | grep -E 'hofxm|hofx0' | cut -d " " -f2)) # returns hofxm0* hofx0* as array
                #ncks_str=$(echo ${groups[@]} | sed -e "s/ /,/g") # replaces all the spaces with a comma (e.g., hofx0_1,hofxm0_10_1)
                mapfile -t groups < <(ncdump -h $fname | grep group: | grep -E 'hofxm|hofx0' | cut -d " " -f2) # returns hofxm0* hofx0* as array
                original_ifs="$IFS"
                IFS=","; ncks_str="${groups[*]}"
                IFS="$original_ifs" # Restore IFS
                ncks -O --no_abc -C -g "${ncks_str}" $fname "${jedi_output_dir}/obsout_omb_${inst}_processed.h5"
            fi
        done
    fi

elif [[ "$JEDI_ANALYSIS_TYPE" == "solver" ]]; then

    RUNMPCMD -n $jedi_enkf_num_procs_solver $jedi_exec ./solver.yaml ./solver.log
    status=$?

    if [[ $status -ne 0 ]]; then
       echo "EnKF solver failed with status = ${status}"
       exit 13
    fi

    calc_mean=false
    if [[ "${calc_mean}" == true ]]; then
        datetime_string="${datetime:0:4}-${datetime:4:2}-${datetime:6:2}_${datetime:8:2}:${datetime:10:2}.00"
        cp "./analysis.${datetime_string}_en001.nc" ./mpas_post_ensmean.nc # float variables in ./mpas_prior_ensmean.nc will be overwritten
        cp "./analysis.${datetime_string}_en001.nc" ./mpas_post_stddev.nc

        #ln -sf $ENS_AVERAGE_EXEC .
        calc_stddev="false"  # too slow for a really big problem, so set to false to bypass
        srun --nodes=$ens_size --ntasks-per-node=1 $ENS_AVERAGE_EXEC ${JEDI_RUN_DIR} mpas_post_ensmean.nc mpas_post_stddev.nc "analysis.${datetime_string}_en" $ens_size $calc_stddev > ./ens_post_mean.log
        status=$?
        if [[ "$calc_stddev" == "false" ]]; then
           rm -f ./mpas_post_stddev.nc # just get rid of it so we don't make mistakes
        fi
    fi

elif [[ "$JEDI_ANALYSIS_TYPE" == "enkf_all_at_once" ]]; then
       # first run EnKF in "observer" mode

       RUNMPCMD -n $jedi_enkf_num_procs_observer $jedi_exec ./observer.yaml ./observer.log
       status=$?
       if [[ $status -ne 0 ]]; then
          echo "EnKF observer failed with status = ${status}" >> FAIL
          exit 12
       fi

       # now run EnKF in "solver" mode
       # we need to change some YAML variables. Easiest way is to just change what we
       # already have (./observer.yaml) usings sed, since changes are minimal
       cp ./observer.yaml ./solver.yaml
       sed -i "s/*asObserver/*asSolver/g"  ./solver.yaml
       sed -i "s/*RoundRobinDistribution/*HaloDistribution/g" ./solver.yaml
       sed -i "s/*ObsDataIn/*ObsDataOut/g" ./solver.yaml
       sed -i '/ obsdataout/d' ./solver.yaml # note the space in front of obsdata out; this deletes the whole line

       RUNMPCMD -n $jedi_enkf_num_procs_solver $jedi_exec ./solver.yaml ./solver.log
       status=$?
       if [[ $status -ne 0 ]]; then
          echo "EnKF solver failed with status = ${status}" >> FAIL
          exit 13
       fi

       # now run EnKF to get OMA statbash istics
       # all we need to do is run LETKF again in observer mode, but point to the analysis files
       # also need to put the output in a unique directory

elif [[ "$JEDI_ANALYSIS_TYPE" == "post" ]]; then

    RUNMPCMD -n $jedi_enkf_num_procs_solver $jedi_exec ./post.yaml ./post.log
    status=$?

    if [[ $status -ne 0 ]]; then
       echo "EnKF post failed with status = ${status}"
       exit 13
    fi

    # rename ombg to oman for posterior observer jdiag files
    for inst in "${instruments[@]}"; do
        outfile="${jedi_output_dir}/obsout_oma_${inst}.h5"
        echo "Renaming ombg -> oman in ${outfile} ..."
        if [[ -s ${outfile} ]]; then
            outfile_tmp="${outfile%.h5}_tmp.nc"
            nccopy -k 3 "${outfile}" "${outfile_tmp}"
            ncrename -g ombg,oman    "${outfile_tmp}"
            mv "${outfile_tmp}" "${outfile}"
        else
            echo "File ${outfile} is empty or not exist?"
        fi
    done

else # envar, bump
    echo "ERROR: unsupported JEDI_ANALYSIS_TYPE = $JEDI_ANALYSIS_TYPE. exiting ..."
    exit 1
fi

# Done running MPAS-JEDI

unset GFORTRAN_CONVERT_UNIT F_UFMTENDIAN OMP_NUM_THREADS

#-------------------------------
# JEDI has run. Deal with output
#-------------------------------

# Run concatenation program.  Output is obsout_omb_${platform}_all.nc4/h5 (e.g., obsout_omb_sondes_all.nc4/h5)
#  Can also use "./netcdf-concat" program through jedi rapids  (possibly in /glade/u/home/schwartz/.local/bin/netcdf-concat)
#if [[ $(grep -i "create_multiple_files_" ./da.log | wc -l) > 0 ]]; then # possible that just one file was made...if so, no need to concatenate
# touch -f ./JEDI_INTERNAL_CONCATENATION
#if [[ 1 == 2 ]]; then # strange things happening, and not correct; number of procs should depend on JEDI application
#if [[ "$JEDI_ANALYSIS_TYPE" =~ "enkf_prior" ]]; then
#radiance_str    for prefx in geovals ydiag; do
#radiance_str        if [[ -s ./input_${prefx}.nml ]]; then
#radiance_str            ln -sf ./input_${prefx}.nml ./input.nml # program looks for ./input.nml
#radiance_str            RUNMPCMD -n $jedi_enkf_num_procs_observer $NETCDF_CONCATENATE_EXEC > ./concatenate_netcdf_${prefx}.log
#radiance_str            if grep -qi "All done" ./concatenate_netcdf_${prefx}.log ; then
#radiance_str               rm -f ${jedi_output_dir}/${prefx}*_????.nc4
#radiance_str            else
#radiance_str               #touch -f ./CONCATENATE_FAILED_${prefx}
#radiance_str               # exit 14
#radiance_str               echo "${NETCDF_CONCATENATE_EXEC} failed."
#radiance_str               status=14
#radiance_str            fi
#radiance_str        fi
#radiance_str    done
#fi

#---------
# clean up
#---------

if [[ $status -eq 0 ]]; then
    touch "done.${jobname}"
    rm -f ./observer.log*.* ./oma.log*.* ./solver.log*.* post.log*
    rm -f ./core*
    rm -f ./*.lock
    rm -f ./fort.* # BUMP files that might be there
else
   echo "JEDI FAILED with status = ${status}" >> FAIL
   touch "error.${jobname}"
   exit 13
fi

rm -rf "running.${jobname}"

time2=$(date '+%s')

diff=$((time2-time1))

printf "\nJob   Ended: %(%a %b %d %H:%M:%S %Z %Y)T. Job run time: %s.\n" "$time2" "$(date -d@$diff -u +%H:%M:%S)"
