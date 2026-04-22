#!/bin/bash

########################################################################
#
# Set up working environment
#
########################################################################

function setup_machine {

    local machine_name=$1
    local root_dir=$2
    local use_python=$3
    local initialize=$4
    local set_up=$5

    if [[ -n ${machine_name} ]]; then
        machine=${machine_name}
    else
        machine="Ursa"

        myhostname=$(hostname)
        if [[ "${myhostname}" == ln? ]]; then
            machine="Vecna"
        elif [[ "${myhostname}" == hercules* ]]; then
            machine="Hercules"
        elif [[ "${myhostname}" == cheyenne* || "${myhostname}" == derecho* ]]; then
            machine="Cheyenne"
        elif [[ "${myhostname}" == ufe?? ]]; then
            machine="Ursa"
        fi
    fi

    [[ -z $set_up ]] && set_up=true

    #-----------------------------------------------------------------------
    #
    # Handle machine specific configuraitons
    #
    #-----------------------------------------------------------------------

    site_runcmd="sbatch"

    [[ $set_up == true ]] && echo -e "\nLoading working environment on ${LIGHT_RED}${machine}${NC} ...."

    case $machine in
    Ursa )
        modulename="build_ursa_Rocky9_intel_hpxmpi_smiol"

        MPAS_DIR="/scratch3/NAGAPE/wof/ywang/GSL_JEDI/rrfs-workflow"
        mpas_modulename="rrfs/ursa.intel"

        rrfs_dir="/scratch3/NAGAPE/wof/ywang/GSL_JEDI/rrfs-workflow"
        rrfs_modulename="rrfs/ursa.intel"

        #JEDI_DIR="/scratch3/NAGAPE/wof/ywang/CADRE2/CADRE_JEDI_MODEL"
        #jedi_modulename="ursa.intel"            # CADRE
        JEDI_DIR="/scratch3/NAGAPE/wof/ywang/GSL_JEDI/rrfs-workflow/sorc/RDASApp"
        jedi_modulename="RDAS/ursa.intel"      # RRFS

        site_workdir="/scratch3/NAGAPE/wof/ywang/MPAS-WoFS/run_dirs"
        site_postdir="/scratch3/NAGAPE/wof/ywang/MPAS-WoFS/frdd-wofs-post.mpas"
        RT_OBSDIR="/scratch3/NAGAPE/wof/ywang/rt_obs"

        if [[ ${set_up} == true ]]; then
            # shellcheck source=/dev/null
            source /etc/profile.d/modules.sh
            module purge
            module use "${root_dir}/modules"
            module load ${modulename}
            #module load wgrib2/2.0.8
        fi
        export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:/home/Yunheng.Wang/local/lib

        if [[ ${initialize} == true ]]; then
            default_partition_wps="u1-compute"
            default_partition_static="u1-compute"  ; default_claim_cpu_static="--cpus-per-task=12"
            default_partition_create="u1-service"  ; default_claim_cpu_create="--mem-per-cpu=128G"

            default_npestatic=96

            site_mach="slurm"
            site_job_exclusive_str="#SBATCH --exclusive"
            site_job_account_str="#SBATCH -A ${hpcaccount-wof}"
            site_job_runmpexe_str="srun"
            site_job_runexe_str="srun"
            site_runcmd_str=""

            site_WPSGEOG_PATH="/scratch3/NAGAPE/wof/ywang/MPAS-WoFS/WPS_GEOG/"
            #site_wgrib2path="/apps/wgrib2/3.1.3/gnu_11.4.1/wmo/bin/wgrib2"
            site_nckspath="/apps/spack-2024-12/linux-rocky9-x86_64/gcc-11.4.1/nco-5.2.4-h2xd52tl4efe2ga4ayd6rjr3t5elfe6v/bin/ncks"
            site_gpmetis="/scratch3/NAGAPE/wof/ywang/tools/bin/gpmetis"

            site_OBS_DIR_BUFR="/scratch3/NAGAPE/wof/kknopfmeier/PB"
            site_OBS_DIR_REF="/scratch3/NAGAPE/wof/kknopfmeier/MRMS"
            site_OBS_DIR_VEL="/scratch3/NAGAPE/wof/kknopfmeier/MRMS"
            site_OBS_DIR_CWP="/scratch3/NAGAPE/wof/kknopfmeier/CWP"
            site_hrrr_dir="/scratch3/NAGAPE/wof/kknopfmeier/HRRRE"

            #site_OBS_DIR_BUFR="/scratch4/BMC/rtrr/RRFS2_RETRO_DATA/May2024/obs_rap"
            #site_OBS_DIR_REF="/scratch4/BMC/rtrr/RRFS2_RETRO_DATA/May2024/reflectivity"
            #site_OBS_DIR_VEL="/scratch3/NAGAPE/wof/kknopfmeier/MRMS"
            #site_OBS_DIR_CWP="/scratch3/NAGAPE/wof/ywang/rt_obs/CWP"

            #site_hrrr_dir="/scratch3/NAGAPE/wof/ywang/HRRRE"
        fi
        ;;
    Hercules )
        modulename="build_hercules_intel"

        if [[ ${set_up} == true ]]; then
            module purge
            module use "${root_dir}"/modules
            module load ${modulename}
        fi

        site_workdir="/work2/noaa/wof/ywang/MPAS/MPAS_PROJECT/run_dirs"

        if [[ ${initialize} == true ]]; then
            default_partition_wps="batch"
            default_partition_static="batch"  ; default_claim_cpu_static="--cpus-per-task=12"
            default_partition_create="batch"  ; default_claim_cpu_create="--mem-per-cpu=128G"

            default_npestatic=40

            site_mach="slurm"
            site_job_exclusive_str="#SBATCH --exclusive"
            site_job_account_str="#SBATCH -A ${hpcaccount-wof}"
            site_job_runmpexe_str="srun"
            site_job_runexe_str="srun"
            site_runcmd_str=""

            site_WPSGEOG_PATH="/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/WPS_GEOG/"
            #site_wgrib2path="/work2/noaa/wof/ywang/tools/hpc-stack/intel-oneapi-compilers-2022.2.1/wgrib2/2.0.8/bin/wgrib2"
            site_nckspath="/work2/noaa/wof/ywang/tools/hpc-stack/intel-oneapi-compilers-2022.2.1/nco/5.0.6/bin/ncks"
            site_gpmetis="/home/yhwang/local/bin/gpmetis"

            site_OBS_DIR="/work2/noaa/wof/ywang/MPAS/OBSGEN"

            site_hrrr_dir="/work2/noaa/wof/ywang/MPAS/MODEL_DATA/HRRRE"
        fi

        ;;
    Cheyenne )
        site_runcmd="qsub"
        modulename="defaults"

        site_workdir="/glade/scratch/wofs_mpas/run_dirs"

        if [[ ${initialize} == true ]]; then
            ncores_static=32
            default_partition_wps="main"
            default_partition_static="main" ; default_claim_cpu_static="ncpus=${ncores_static}"
            default_partition_create="main" ; default_claim_cpu_create="ncpus=${ncores_static}"

            default_npestatic=72

            site_mach="pbs"
            site_job_exclusive_str="#PBS -l job_priority=economy"
            site_job_account_str="#PBS -A ${hpcaccount-NMMM0021}"
            site_job_runmpexe_str="mpiexec"
            site_job_runexe_str="mpiexec"
            site_runcmd_str=""

            site_WPSGEOG_PATH="/glade/work/ywang/WPS_GEOG/"
            #site_wgrib2path="/glade/u/apps/derecho/23.09/spack/opt/spack/wgrib2/3.1.1/gcc/7.5.0/i5h5/bin/wgrib2"
            site_nckspath="/glade/u/apps/derecho/23.09/spack/opt/spack/nco/5.2.4/gcc/12.2.0/c2uf/bin/ncks"
            site_gpmetis="/glade/work/ywang/tools/bin/gpmetis"

            site_OBS_DIR="/glade/work/ywang/observations"

            site_hrrr_dir="/glade/derecho/scratch/ywang/tmp"
        fi

        ;;
    wof-epyc* )
        # wof-epyc8 at NSSL
        modulename="env.mpas_smiol"
        site_workdir="/scratch/wofs_mpas/run_dirs"
        site_postdir="/scratch/home/yunheng.wang/MPAS/frdd-wofs-post"
        RT_OBSDIR="/work/rt_obs"
        ;;
    * )
        # Vecna at NSSL
        modulename="env.mpas_smiol"
        if [[ ${set_up} == true ]]; then
            # shellcheck source=/dev/null
            source /usr/share/Modules/init/bash
            # shellcheck source=/dev/null
            source "${root_dir}/modules/${modulename}" > /dev/null || exit $?
        fi
        site_workdir="/scratch/wofs_mpas/run_dirs"
        site_postdir="/home/yunheng.wang/MPAS/frdd-wofs-post"
        RT_OBSDIR="/work/rt_obs"

        if [[ ${initialize} == true ]]; then
            default_partition_wps="batch"
            default_partition_static="batch"    ; default_claim_cpu_static=""
            default_partition_create="batch"    ; default_claim_cpu_create="--mem-per-cpu=128G"

            default_npestatic=24

            site_mach="slurm"
            #job_exclusive_str="#SBATCH --exclude=cn11,cn14"
            site_job_exclusive_str="#SBATCH --exclusive"
            site_job_account_str=""
            site_job_runmpexe_str="srun"
            site_job_runexe_str="srun"
            site_runcmd_str="srun -n 1"

            site_WPSGEOG_PATH="/scratch/wofs_mpas/WPS_GEOG/"   # Should keep last /
            #site_wgrib2path="/home/yunheng.wang/tools/gnu/bin/wgrib2"
            site_nckspath="/home/yunheng.wang/tools/micromamba/envs/wofs_an/bin/ncks"
            site_gpmetis="/home/yunheng.wang/tools/bin/gpmetis"
            export LD_LIBRARY_PATH="/home/yunheng.wang/tools/lib"
            site_nclpath="/scratch/software/miniconda3/bin/ncl"

            site_OBS_DIR="/scratch/wofs_mpas/OBS_SEQ.reduced"

            #hrrr_dir="/scratch2/wofuser/MODEL_DATA/HRRRE"
            site_hrrr_dir="/scratch/wofs/wofuser/MODEL_DATA/HRRRE"
        fi
        ;;
    esac

    # Load Python Enviroment if necessary
    if [[ ${use_python} == true ]]; then
        # shellcheck source=/dev/null
        source "${root_dir}/modules/env.python"  || exit $?
        # shellcheck disable=SC2154
        echo -e "Activated Python environment ${YELLOW}${python_env}${NC} on ${LIGHT_RED}${machine}${NC} ..."
        export RT_OBSDIR
    fi

    export machine site_runcmd site_workdir site_postdir
    export MPAS_DIR mpas_modulename rrfs_dir rrfs_modulename JEDI_DIR jedi_modulename

    if [[ ${initialize} == true ]]; then
        # Will be used by 'setup_mpas-wofs.sh' for static processing.
        # For other programs, the information is in the runtime configuration file and
        # users can modify 'default_site_settings' below for the default settings
        # before running 'setup_mpas-wofs.sh', after that just modify
        # the runtime configuration file.
        #
        export site_mach site_runcmd_str
        export site_job_exclusive_str site_job_account_str site_job_runmpexe_str site_job_runexe_str
        export default_partition_wps default_partition_static default_partition_create
        export default_npestatic default_claim_cpu_static default_claim_cpu_create
        export site_WPSGEOG_PATH site_nckspath site_gpmetis site_nclpath
        export site_OBS_DIR_BUFR site_OBS_DIR_REF site_OBS_DIR_VEL site_OBS_DIR_CWP site_hrrr_dir
    fi
}

########################################################################

function default_site_settings {
    #-------------------------------------------------------------------
    # Machine specific setting for init, lbc, dacycles & fcst
    #-------------------------------------------------------------------

    case $machine in
    "Ursa" )
        default_mpas_wofs_python="/scratch3/NAGAPE/wof/ywang/MPAS-WoFS/wofs_new_noise"
        default_claim_cpu_ungrib="--cpus-per-task=96"   # --mem-per-cpu=10G"

        # ICs
        default_npeics=96; default_ncores_ics=2
        default_partition_ics="u1-compute"
        default_claim_cpu_ics="--cpus-per-task=2"

        # LBCs
        default_npelbc=96;  default_ncores_lbc=2
        default_partition_lbc="u1-compute"
        default_claim_cpu_lbc="--cpus-per-task=2"

        # DA cycles
        default_ncores_dafcst=96;  default_ncores_filter=48
        default_partition_dafcst="u1-compute"; default_claim_cpu_dafcst="--cpus-per-task=1"
        default_partition_filter="u1-compute"; default_claim_cpu_filter="--ntasks-per-node=${default_ncores_filter}"

        default_npedafcst=96         #; default_nnodes_fcst=$(( default_npefcst/default_ncores_fcst ))
        default_npefilter=96         #; default_nnodes_filter=$(( npefilter/ncores_filter ))
        default_nnodes_filter=$(( default_npefilter/default_ncores_filter ))
        default_nnodes_dafcst=$(( default_npedafcst/default_ncores_dafcst ))

        default_claim_cpu_ioda="--cpus-per-task=1"
        default_claim_cpu_ioda_refl="--cpus-per-task=2"
        default_claim_cpu_update="--cpus-per-task=1"


        # FCST cycles
        default_ncores_fcst=96;  default_ncores_post=48
        default_partition_fcst="u1-compute";   default_claim_cpu_fcst="--cpus-per-task=2"
        default_partition_post="u1-compute";   default_claim_cpu_post="--ntasks-per-node=${default_ncores_post}"

        default_npefcst=96    ; default_nnodes_fcst=$(( default_npefcst/default_ncores_fcst ))
        default_npepost=96    ; default_nnodes_post=$(( default_npepost/default_ncores_post ))
        ;;

    "Hercules" )
        default_mpas_wofs_python="????"
        default_claim_cpu_ungrib="--cpus-per-task=12 --mem-per-cpu=10G"

        # ICs
        default_npeics=24; default_ncores_ics=2
        default_partition_ics="batch"
        default_claim_cpu_ics="--cpus-per-task=2"

        # LBCs
        default_npelbc=24;  default_ncores_lbc=2
        default_partition_lbc="batch"
        default_claim_cpu_lbc="--cpus-per-task=2"

        # DA cycles
        default_ncores_dafcst=40;  default_ncores_filter=40
        default_partition_dafcst="batch"; default_claim_cpu_dafcst="--cpus-per-task=2"
        default_partition_filter="batch"; default_claim_cpu_filter="--cpus-per-task=2"

        default_npedafcst=40       ; default_nnodes_dafcst=$(( default_npedafcst/default_ncores_dafcst ))
        default_npefilter=160      ; default_nnodes_filter=$(( default_npefilter/default_ncores_filter ))

        default_claim_cpu_ioda="--cpus-per-task=1"
        default_claim_cpu_ioda_refl="--cpus-per-task=2"
        default_claim_cpu_update="--cpus-per-task=1"


        # FCST cycles
        default_ncores_fcst=40;  default_ncores_post=40
        default_partition_fcst="batch";   default_claim_cpu_fcst="--cpus-per-task=2"
        default_partition_post="batch";   default_claim_cpu_post="--cpus-per-task=12"

        default_npefcst=40     ; default_nnodes_fcst=$(( default_npefcst/default_ncores_fcst ))
        default_npepost=40     ; default_nnodes_post=$(( default_npepost/default_ncores_post ))
        ;;

    "Cheyenne" )
        default_mpas_wofs_python="/glade/work/ywang/wofs_new_noise"
        default_claim_cpu_ungrib=""

        # Derecho node has 128 processors
        # ICs
        default_npeics=32; default_ncores_ics=32
        default_partition_ics="preempt"
        default_claim_cpu_ics="ncpus=${default_ncores_ics}"

        # LBCs
        default_npelbc=32;  default_ncores_lbc=32
        default_partition_lbc="preempt"
        default_claim_cpu_lbc="ncpus=${default_ncores_lbc}"

        # DA cycles
        default_ncores_filter=128; default_ncores_dafcst=128
        # main, preempt, regular
        default_partition_dafcst="preempt" ; default_claim_cpu_dafcst="ncpus=${default_ncores_dafcst}"
        default_partition_filter="preempt" ; default_claim_cpu_filter="ncpus=${default_ncores_filter}"

        default_npefilter=128     ; default_nnodes_filter=$(( default_npefilter/default_ncores_filter   ))
        default_npedafcst=128     ; default_nnodes_dafcst=$(( default_npefcst/default_ncores_dafcst ))

        default_claim_cpu_ioda="ncpus=1"
        default_claim_cpu_ioda_refl="ncpus=2"
        default_claim_cpu_update="ncpus=2"

        # FCST cycles
        default_ncores_post=32; default_ncores_fcst=128
        default_partition_fcst="preempt"   ; default_claim_cpu_fcst="ncpus=${default_ncores_fcst}"
        default_partition_post="preempt"   ; default_claim_cpu_post="ncpus=${default_ncores_post}"

        default_npepost=32      ; default_nnodes_post=$(( default_npepost/default_ncores_post   ))
        default_npefcst=128     ; default_nnodes_fcst=$(( default_npefcst/default_ncores_fcst ))
        ;;

    * )
        # Vecna at NSSL

        default_mpas_wofs_python="/home/yunheng.wang/MPAS/wofs_new_noise"
        default_claim_cpu_ungrib=""

        # ICs
        default_npeics=24;   default_ncores_ics=96
        default_partition_ics="batch"
        default_claim_cpu_ics="--ntasks-per-node=${default_ncores_ics}"

        # LBCs
        default_npelbc=24;  default_ncores_lbc=96
        default_partition_lbc="batch"
        default_claim_cpu_lbc="--ntasks-per-node=${default_ncores_lbc}"

        # DA cycles
        default_ncores_filter=96; default_ncores_dafcst=96

        default_npefilter=768           ; default_nnodes_filter=1
        default_npedafcst=56            ; default_nnodes_dafcst=1

        default_partition_dafcst="batch"; default_claim_cpu_dafcst="";
        default_partition_filter="batch"; default_claim_cpu_filter="--ntasks-per-node=\${default_ncores_filter}"

        default_claim_cpu_ioda="--cpus-per-task=1"
        default_claim_cpu_ioda_refl="--cpus-per-task=2"
        default_claim_cpu_update="--cpus-per-task=1"

        # FCST cycles
        default_ncores_post=24         ; default_ncores_fcst=96
        default_partition_fcst="batch" ; default_claim_cpu_fcst="";
        default_partition_post="batch" ; default_claim_cpu_post=""

        default_npepost=24             ; default_nnodes_post=1
        default_npefcst=80             ; default_nnodes_fcst=1
        ;;
    esac

    export default_mpas_wofs_python
    export default_claim_cpu_ungrib
    export default_partition_ics    default_claim_cpu_ics    default_npeics        default_ncores_ics
    export default_partition_lbc    default_claim_cpu_lbc    default_npelbc        default_ncores_lbc
    export default_partition_dafcst default_claim_cpu_dafcst default_npedafcst     default_ncores_dafcst  default_nnodes_dafcst
    export default_partition_filter default_claim_cpu_filter default_npefilter     default_ncores_filter  default_nnodes_filter
    export default_claim_cpu_ioda   default_claim_cpu_ioda_refl  default_claim_cpu_update
    export default_partition_fcst   default_claim_cpu_fcst   default_npefcst       default_ncores_fcst    default_nnodes_fcst
    export default_partition_post   default_claim_cpu_post   default_npepost       default_ncores_post    default_nnodes_post
}
