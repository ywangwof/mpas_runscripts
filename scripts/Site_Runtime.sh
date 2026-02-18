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
        machine="Jet"

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

    runcmd="sbatch"

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

        workdirDF="/scratch3/NAGAPE/wof/ywang/MPAS-WoFS/run_dirs"
        post_dir="/scratch3/NAGAPE/wof/ywang/MPAS-WoFS/frdd-wofs-post"

        if [[ ${set_up} == true ]]; then
            source /etc/profile.d/modules.sh
            module purge
            module use "${root_dir}/modules"
            module load ${modulename}
            #module load wgrib2/2.0.8
        fi
        export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:/home/Yunheng.Wang/local/lib

        if [[ ${initialize} == true ]]; then
            partition_wps="u1-compute"
            partition_static="u1-compute"  ; claim_cpu_static="--cpus-per-task=12"
            partition_create="u1-service"  ; claim_cpu_create="--mem-per-cpu=128G"

            npestatic=96

            mach="slurm"
            job_exclusive_str="#SBATCH --exclusive"
            job_account_str="#SBATCH -A ${hpcaccount-wof}"
            job_runmpexe_str="srun"
            job_runexe_str="srun"
            runcmd_str=""

            WPSGEOG_PATH="/scratch3/NAGAPE/wof/ywang/MPAS-WoFS/WPS_GEOG/"
            wgrib2path="/apps/wgrib2/3.1.3/gnu_11.4.1/wmo/bin/wgrib2"
            nckspath="/apps/spack-2024-12/linux-rocky9-x86_64/gcc-11.4.1/nco-5.2.4-h2xd52tl4efe2ga4ayd6rjr3t5elfe6v/bin/ncks"
            gpmetis="/scratch3/NAGAPE/wof/ywang/tools/bin/gpmetis"

            OBS_DIR="/scratch4/BMC/rtrr/RRFS2_RETRO_DATA/May2024"
            OBS_DIR_REF="/scratch3/NAGAPE/wof/kknopfmeier/MRMS"
            OBS_DIR_VEL="/scratch3/NAGAPE/wof/kknopfmeier/MRMS"

            hrrr_dir="/scratch3/NAGAPE/wof/ywang/HRRRE"
        fi
        ;;
    Jet )
        modulename="build_jet_Rocky8_intel_smiol"
        #modulename="RDAS/jet.intel"

        MPAS_DIR="/lfs5/NAGAPE/hpc-wof1/ywang/GSL_JEDI/rrfs-workflow.new"
        mpas_modulename="rrfs/jet.intel"

        rrfs_dir="/lfs5/NAGAPE/hpc-wof1/ywang/GSL_JEDI/rrfs-workflow.new"
        rrfs_modulename="rrfs/jet.intel"

        #JEDI_DIR="/lfs5/NAGAPE/hpc-wof1/ywang/GSL_JEDI/rrfs-workflow.new/sorc/RDASApp"
        JEDI_DIR="/lfs5/NAGAPE/hpc-wof1/ywang/CADRE2/CADRE_JEDI_MODEL"
        #JEDI_DIR="/lfs5/NAGAPE/hpc-wof1/ywang/NCAR_JEDI"
        jedi_modulename="jet.intel"            # CADRE
        #jedi_modulename="RDAS/jet.intel"      # RRFS

        workdirDF="/lfs5/NAGAPE/hpc-wof1/ywang/MPAS-WoFS/run_dirs"
        post_dir="/lfs5/NAGAPE/hpc-wof1/ywang/MPAS-WoFS/frdd-wofs-post"

        if [[ ${set_up} == true ]]; then
            source /etc/profile.d/modules.sh
            module purge
            module use ${MPAS_DIR}/modulefiles
            module load ${mpas_modulename}
            #module load wgrib2/2.0.8
        fi
        export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:/home/Yunheng.Wang/local/lib

        if [[ ${initialize} == true ]]; then
            partition_wps="xjet,kjet"
            partition_static="xjet,kjet"  ; claim_cpu_static="--cpus-per-task=12"
            partition_create="bigmem"     ; claim_cpu_create="--mem-per-cpu=128G"

            npestatic=24

            mach="slurm"
            job_exclusive_str="#SBATCH --exclusive"
            job_account_str="#SBATCH -A ${hpcaccount-hpc-wof1}"
            job_runmpexe_str="srun"
            job_runexe_str="srun"
            runcmd_str=""

            WPSGEOG_PATH="/lfs5/NAGAPE/hpc-wof1/ywang/MPAS/WPS_GEOG/"
            wgrib2path="/apps/wgrib2/3.1.1/gnu_13.2.0/wmo/bin/wgrib2"
            nckspath="/apps/nco/5.1.6/gcc-13.2.0/bin/ncks"
            gpmetis="/home/Yunheng.Wang/local/bin/gpmetis"

            OBS_DIR="/lfs5/NAGAPE/hpc-wof1/ywang/MPAS-WoFS/run_dirs/OBS_SEQ.Reduced"
            OBS_DIR_REF="/scratch4/BMC/rtrr/RRFS2_RETRO_DATA/May2024"
            OBS_DIR_VEL="/scratch4/BMC/rtrr/RRFS2_RETRO_DATA/May2024"

            hrrr_dir="/lfs5/NAGAPE/hpc-wof1/ywang/HRRRE"
        fi
        ;;
    Hercules )
        modulename="build_hercules_intel"

        if [[ ${set_up} == true ]]; then
            module purge
            module use ${root_dir}/modules
            module load ${modulename}
        fi

        workdirDF="/work2/noaa/wof/ywang/MPAS/MPAS_PROJECT/run_dirs"

        if [[ ${initialize} == true ]]; then
            partition_wps="batch"
            partition_static="batch"  ; claim_cpu_static="--cpus-per-task=12"
            partition_create="batch"  ; claim_cpu_create="--mem-per-cpu=128G"

            npestatic=40

            mach="slurm"
            job_exclusive_str="#SBATCH --exclusive"
            job_account_str="#SBATCH -A ${hpcaccount-wof}"
            job_runmpexe_str="srun"
            job_runexe_str="srun"

            WPSGEOG_PATH="/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/WPS_GEOG/"
            wgrib2path="/work2/noaa/wof/ywang/tools/hpc-stack/intel-oneapi-compilers-2022.2.1/wgrib2/2.0.8/bin/wgrib2"
            nckspath="/work2/noaa/wof/ywang/tools/hpc-stack/intel-oneapi-compilers-2022.2.1/nco/5.0.6/bin/ncks"
            gpmetis="/home/yhwang/local/bin/gpmetis"

            OBS_DIR="/work2/noaa/wof/ywang/MPAS/OBSGEN"

            hrrr_dir="/work2/noaa/wof/ywang/MPAS/MODEL_DATA/HRRRE"
        fi

        ;;
    Cheyenne )
        runcmd="qsub"
        modulename="defaults"

        workdirDF="/glade/scratch/wofs_mpas/run_dirs"

        if [[ ${initialize} == true ]]; then
            ncores_static=32
            partition_wps="main"
            partition_static="main" ; claim_cpu_static="ncpus=${ncores_static}"
            partition_create="main" ; claim_cpu_create="ncpus=${ncores_static}"

            npestatic=72

            mach="pbs"
            job_exclusive_str="#PBS -l job_priority=economy"
            job_account_str="#PBS -A ${hpcaccount-NMMM0021}"
            job_runmpexe_str="mpiexec"
            job_runexe_str="mpiexec"
            runcmd_str=""

            WPSGEOG_PATH="/glade/work/ywang/WPS_GEOG/"
            wgrib2path="/glade/u/apps/derecho/23.09/spack/opt/spack/wgrib2/3.1.1/gcc/7.5.0/i5h5/bin/wgrib2"
            nckspath="/glade/u/apps/derecho/23.09/spack/opt/spack/nco/5.2.4/gcc/12.2.0/c2uf/bin/ncks"
            gpmetis="/glade/work/ywang/tools/bin/gpmetis"

            OBS_DIR="/glade/work/ywang/observations"

            hrrr_dir="/glade/derecho/scratch/ywang/tmp"
        fi

        ;;
    wof-epyc* )
        # wof-epyc8 at NSSL
        modulename="env.mpas_smiol"
        workdirDF="/scratch/wofs_mpas/run_dirs"
        post_dir="/scratch/home/yunheng.wang/MPAS/frdd-wofs-post"
        ;;
    * )
        # Vecna at NSSL
        modulename="env.mpas_smiol"
        if [[ ${set_up} == true ]]; then
            source /usr/share/Modules/init/bash
            source ${root_dir}/modules/${modulename} > /dev/null || exit $?
        fi
        workdirDF="/scratch/wofs_mpas/run_dirs"
        post_dir="/home/yunheng.wang/MPAS/frdd-wofs-post"

        if [[ ${initialize} == true ]]; then
            ncores_static=96
            partition_wps="batch"
            partition_static="batch"    ; claim_cpu_static=""
            partition_create="batch"    ; claim_cpu_create="--mem-per-cpu=128G"

            npestatic=24

            mach="slurm"
            #job_exclusive_str="#SBATCH --exclude=cn11,cn14"
            job_exclusive_str="#SBATCH --exclusive"
            job_account_str=""
            job_runmpexe_str="srun"
            job_runexe_str="srun"
            runcmd_str="srun -n 1"

            WPSGEOG_PATH="/scratch/wofs_mpas/WPS_GEOG/"   # Should keep last /
            wgrib2path="/home/yunheng.wang/tools/gnu/bin/wgrib2"
            nckspath="/home/yunheng.wang/tools/micromamba/envs/wofs_an/bin/ncks"
            gpmetis="/home/yunheng.wang/tools/bin/gpmetis"
            export LD_LIBRARY_PATH="/home/yunheng.wang/tools/lib"
            nclpath="/scratch/software/miniconda3/bin/ncl"

            OBS_DIR="/scratch/wofs_mpas/OBS_SEQ.reduced"

            #hrrr_dir="/scratch2/wofuser/MODEL_DATA/HRRRE"
            hrrr_dir="/scratch/wofs/wofuser/MODEL_DATA/HRRRE"
        fi
        ;;
    esac

    # Load Python Enviroment if necessary
    if [[ ${use_python} == true ]]; then
        source ${root_dir}/modules/env.python  || exit $?
        echo -e "Activated Python environment ${YELLOW}${python_env}${NC} on ${LIGHT_RED}${machine}${NC} ..."
    fi

    export machine runcmd workdirDF post_dir
    export MPAS_DIR mpas_modulename rrfs_dir rrfs_modulename JEDI_DIR jedi_modulename

    if [[ ${initialize} == true ]]; then
        # Will be used by 'setup_mpas-wofs.sh' for static processing.
        # For other programs, the information is in the runtime configuration file and
        # users can modify 'default_site_settings' below for the default settings
        # before running 'setup_mpas-wofs.sh', after that just modify
        # the runtime configuration file.
        #
        export mach runcmd_str
        export job_exclusive_str job_account_str job_runmpexe_str job_runexe_str
        export partition_wps partition_static partition_create npestatic claim_cpu_static claim_cpu_create ncores_static
        export WPSGEOG_PATH wgrib2path nckspath gpmetis nclpath
        export OBS_DIR OBS_DIR_REF OBS_DIR_VEL hrrr_dir
    fi
}

########################################################################

function default_site_settings {
    #-------------------------------------------------------------------
    # Machine specific setting for init, lbc, dacycles & fcst
    #-------------------------------------------------------------------

    case $machine in
    "Jet" )
        mpas_wofs_python="/lfs5/NAGAPE/hpc-wof1/ywang/MPAS-WoFS/wofs_new_noise"

        # ICs
        npeics=24; ncores_ics=2
        partition_ics="xjet,kjet"
        claim_cpu_ics="--cpus-per-task=2"
        claim_cpu_ungrib="--cpus-per-task=12"   # --mem-per-cpu=10G"

        # LBCs
        npelbc=24;  ncores_lbc=2
        partition_lbc="xjet,kjet"
        claim_cpu_lbc="--cpus-per-task=2"

        # DA cycles
        ncores_dafcst=24;  ncores_filter=24
        partition_dafcst="xjet,kjet"; claim_cpu_dafcst="--cpus-per-task=1"
        partition_filter="xjet,kjet"; claim_cpu_filter="--cpus-per-task=2"
                                      claim_cpu_ioda="--cpus-per-task=1 --mem-per-cpu=8G"
                                      claim_cpu_ioda_refl="--cpus-per-task=2"
        npedafcst=96         #; nnodes_fcst=$(( npefcst/ncores_fcst ))
        npefilter=120        #; nnodes_filter=$(( npefilter/ncores_filter ))
        nnodes_filter=$(( npefilter/ncores_filter ))
        nnodes_dafcst=$(( npedafcst/ncores_dafcst ))

        # FCST cycles
        ncores_fcst=24;  ncores_post=24
        partition_fcst="xjet,kjet";   claim_cpu_fcst="--cpus-per-task=2"
        partition_post="xjet,kjet";   claim_cpu_post="--cpus-per-task=12"

        npefcst=96     ; nnodes_fcst=$(( npefcst/ncores_fcst ))
        npepost=48     ; nnodes_post=$(( npepost/ncores_post ))
        ;;

    "Ursa" )
        mpas_wofs_python="/scratch3/NAGAPE/wof/ywang/MPAS-WoFS/wofs_new_noise"

        # ICs
        npeics=96; ncores_ics=2
        partition_ics="u1-compute"
        claim_cpu_ics="--cpus-per-task=2"
        claim_cpu_ungrib="--cpus-per-task=96"   # --mem-per-cpu=10G"

        # LBCs
        npelbc=96;  ncores_lbc=2
        partition_lbc="u1-compute"
        claim_cpu_lbc="--cpus-per-task=2"

        # DA cycles
        ncores_dafcst=160;  ncores_filter=96
        partition_dafcst="u1-compute"; claim_cpu_dafcst="--cpus-per-task=1"
        partition_filter="u1-compute"; claim_cpu_filter="--cpus-per-task=1"
                                       claim_cpu_ioda="--cpus-per-task=1 --mem-per-cpu=8G"
                                       claim_cpu_ioda_refl="--cpus-per-task=2"
        npedafcst=96         #; nnodes_fcst=$(( npefcst/ncores_fcst ))
        npefilter=160        #; nnodes_filter=$(( npefilter/ncores_filter ))
        nnodes_filter=$(( npefilter/ncores_filter ))
        nnodes_dafcst=$(( npedafcst/ncores_dafcst ))

        # FCST cycles
        ncores_fcst=96;  ncores_post=96
        partition_fcst="u1-compute";   claim_cpu_fcst="--cpus-per-task=2"
        partition_post="u1-compute";   claim_cpu_post="--cpus-per-task=12"

        npefcst=96     ; nnodes_fcst=$(( npefcst/ncores_fcst ))
        npepost=96     ; nnodes_post=$(( npepost/ncores_post ))
        ;;

    "Hercules" )
        # ICs
        npeics=24; ncores_ics=2
        partition_ics="batch"
        claim_cpu_ics="--cpus-per-task=2"
        claim_cpu_ungrib="--cpus-per-task=12 --mem-per-cpu=10G"

        # LBCs
        npelbc=24;  ncores_lbc=2
        partition_lbc="batch"
        claim_cpu_lbc="--cpus-per-task=2"

        # DA cycles
        ncores_dafcst=40;  ncores_filter=40
        partition_dafcst="batch"; claim_cpu_dafcst="--cpus-per-task=2"
        partition_filter="batch"; claim_cpu_filter="--cpus-per-task=2"
                                  claim_cpu_update="--cpus-per-task=1 --mem-per-cpu=8G"
        npedafcst=40       #; nnodes_fcst=$(( npefcst/ncores_fcst ))
        npefilter=160      #; nnodes_filter=$(( npefilter/ncores_filter ))
        nnodes_filter="1"
        nnodes_dafcst="1"

        # FCST cycles
        ncores_fcst=40;  ncores_post=40
        partition_fcst="batch";   claim_cpu_fcst="--cpus-per-task=2"
        partition_post="batch";   claim_cpu_post="--cpus-per-task=12"

        npefcst=40     ; nnodes_fcst=$(( npefcst/ncores_fcst ))
        npepost=40     ; nnodes_post=$(( npepost/ncores_post ))
        ;;

    "Cheyenne" )
        mpas_wofs_python="/glade/work/ywang/wofs_new_noise"

        # Derecho node has 128 processors
        # ICs
        npeics=32; ncores_ics=32
        partition_ics="preempt"
        claim_cpu_ics="ncpus=${ncores_ics}"
        claim_cpu_ungrib=""

        # LBCs
        npelbc=32;  ncores_lbc=32
        partition_lbc="preempt"
        claim_cpu_lbc="ncpus=${ncores_lbc}"

        # DA cycles
        ncores_filter=128; ncores_dafcst=128
        # main, preempt, regular
        partition_dafcst="preempt" ; claim_cpu_dafcst="ncpus=${ncores_dafcst}"
        partition_filter="preempt" ; claim_cpu_filter="ncpus=${ncores_filter}"
        claim_cpu_update="ncpus=${ncores_filter}"

        npefilter=128     ; nnodes_filter=$(( npefilter/ncores_filter   ))
        npedafcst=128     ; nnodes_dafcst=$(( npefcst/ncores_dafcst ))

        # FCST cycles
        ncores_post=32; ncores_fcst=128
        partition_fcst="preempt"   ; claim_cpu_fcst="ncpus=${ncores_fcst}"
        partition_post="preempt"   ; claim_cpu_post="ncpus=${ncores_post}"

        npepost=32      ; nnodes_post=$(( npepost/ncores_post   ))
        npefcst=128     ; nnodes_fcst=$(( npefcst/ncores_fcst ))
        ;;

    * )
        # Vecna at NSSL

        mpas_wofs_python="/home/yunheng.wang/MPAS/wofs_new_noise"

        # ICs
        npeics=24;   ncores_ics=96
        partition_ics="batch"
        claim_cpu_ics="--ntasks-per-node=${ncores_ics}"
        claim_cpu_ungrib=""

        # LBCs
        npelbc=24;  ncores_lbc=96
        partition_lbc="batch"
        claim_cpu_lbc="--ntasks-per-node=${ncores_lbc}"
        claim_cpu_ungrib=""

        # DA cycles
        ncores_filter=96; ncores_dafcst=96

        npefilter=768           ; nnodes_filter=1
        npedafcst=56            ; nnodes_dafcst=1

        partition_dafcst="batch"  ; claim_cpu_dafcst="";
        partition_filter="batch"  ; claim_cpu_filter="--ntasks-per-node=\${ncores_filter}"
                                    claim_cpu_update="--ntasks-per-node=1 --mem-per-cpu=120G"   # 4 jobs each node

        # FCST cycles
        ncores_post=24; ncores_fcst=96
        partition_fcst="batch"      ; claim_cpu_fcst="";
        partition_post="batch"      ; claim_cpu_post=""

        npepost=24      ; nnodes_post=1
        npefcst=80      ; nnodes_fcst=1
        ;;
    esac

    export mpas_wofs_python
    export claim_cpu_ungrib
    export partition_ics    claim_cpu_ics    npeics        ncores_ics
    export partition_lbc    claim_cpu_lbc    npelbc        ncores_lbc
    export partition_dafcst claim_cpu_dafcst npedafcst     ncores_dafcst  nnodes_dafcst
    export partition_filter claim_cpu_filter nnodes_filter ncores_filter  nnodes_filter
    export claim_cpu_ioda   claim_cpu_ioda_refl  npepost
    export partition_fcst   claim_cpu_fcst   npefcst       ncores_fcst    nnodes_fcst
    export partition_post   claim_cpu_post   npepost       ncores_post    nnodes_post
}
