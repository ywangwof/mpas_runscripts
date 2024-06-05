#!/bin/bash

scpdir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
rootdir=$(realpath "$(dirname "${scpdir}")")

desdir=${rootdir}/fix_files

myhost=$(hostname)
if [[ "${myhost}" == "ln"* ]]; then
    srcroot="/scratch/ywang/MPAS"
    tool_dir="/scratch/ywang/tools"

    srcmpassitdir=${srcroot}/gnu/MPASSIT
    srcuppdir=${srcroot}/gnu/UPP_KATE_kjet
    srcmodeldir=${srcroot}/gnu/frdd-MPAS-Model
    srcwpsdir=${srcroot}/gnu/WPS_SRC
    srcwrfdir=${srcroot}/gnu/WRFV4.0
    srcdartdir=${srcroot}/gnu/frdd-DART
elif [[ "${myhost}" == "cheyenne"* || ${myhost} == "derecho"* ]]; then
    rootdir="/glade/work/ywang/mpas_runscripts"
    scpdir="/glade/work/ywang/mpas_runscripts/scripts"
    srcroot="/glade/work/ywang"
    tool_dir="/lfs4/NAGAPE/hpc-wof1/ywang/MPAS"

    srcmpassitdir=${srcroot}/MPASSIT
    srcuppdir=${srcroot}/UPP_KATE_kjet
    srcmodeldir=${srcroot}/MPAS-Model
    srcwpsdir=${srcroot}/WPS_SRC
    srcwrfdir=${srcroot}/WRFV4.0
    srcdartdir=${srcroot}/DART
else
    srcroot="/lfs4/NAGAPE/hpc-wof1/ywang/MPAS"
    tool_dir="/lfs4/NAGAPE/hpc-wof1/ywang/MPAS"

    srcmpassitdir=${srcroot}/MPASSIT
    srcuppdir=${srcroot}/UPP_KATE_kjet
    srcmodeldir=${srcroot}/MPAS-Model.smiol2
    srcwpsdir=${srcroot}/WPS_SRC
    srcwrfdir=${srcroot}/WRFV4.0
    srcdartdir=${srcroot}/DART
    srcmpasregion=${srcroot}/MPAS-Limited-Area
fi

default_packages=(mpas MPASSIT UPP WRF DART mpasregion)

########################################################################

function usage {
    echo " "
    echo "    USAGE: $0 [options] CMD [DESTDIR] [clean]"
    echo " "
    echo "    PURPOSE: Link MPAS runtime static files and executables."
    echo " "
    echo "    DESTDIR  - Destination Directory"
    echo "    CMD      - One or more jobs from [mpas,MPASSIT,UPP,WRF,DART,mpasregion]"
    echo "               Default: all in \"[mpas, MPASSIT, UPP, WRF,DART,mpasregion]\""
    echo "    clean    - Clean the linked or copied files (for relink with a system version change etc.)"
    echo " "
    echo "    OPTIONS:"
    echo "              -h              Display this message"
    echo "              -n              Show command to be run only"
    echo "              -v              Verbose mode"
    echo "              -r              For a run or for fix_files"
    echo "                              Default is for fix_files"
    echo "              -s  DIR         Source directory"
    echo "              -m  Machine     Machine name to be run, [Jet or Vecna]"
    echo "              -cmd copy       Command for linking or copying [copy, link, clean] (default: link)"
    echo " "
    echo "   DEFAULTS:"
    echo "              desdir     = $desdir"
    echo "              srcwps     = $srcwpsdir"
    echo "              srcwrf     = $srcwrfdir"
    echo "              srcmpassit = $srcmpassitdir"
    echo "              srcupp     = $srcuppdir"
    echo "              srcmodel   = $srcmodeldir"
    echo " "
    echo "                                     -- By Y. Wang (2022.10.12)"
    echo " "
    exit "$1"
}

########################################################################

function run_cmd {
    # use global variable doclean, dorun, verb

    local src_dir=$2
    local cmds cmdfns
    local target='./'

    IFS=" " read -r -a cmds   <<< "$1"
    IFS=" " read -r -a cmdfns <<< "$3"

    if [[ ${doclean} == true ]]; then
        if [[ $verb -eq 1 ]]; then
            echo "${cmds[@]}" "${cmdfns[@]}"
        fi
        $dorun "${cmds[@]}" "${cmdfns[@]}"
    else
        for arg in "${cmdfns[@]}"; do
            if [[ $verb -eq 1 ]]; then
                echo "${cmds[@]}" "${src_dir}/$arg" "${target}"
            fi
            $dorun "${cmds[@]}" "${src_dir}/$arg" "${target}"
        done
    fi
}

#-----------------------------------------------------------------------
#
# Handle command line arguments
#
#-----------------------------------------------------------------------
#% ARGS

packages=(mpas MPASSIT UPP WRF DART)

verb=0
realrun=false
dorun=""

doclean=false
cmdnote=""
runcmd="ln -sf"

while [[ $# -gt 0 ]]
    do
    key="$1"

    case $key in
        -h )
            usage 0
            ;;
        -n )
            #runcmd="echo $runcmd"
            dorun="echo"
            ;;
        -v )
            verb=1
            ;;
        -r )
            realrun=true
            packages=(mpas)
            desdir="./"
            ;;
        -s )
            if [[ -d $2 ]]; then
                srcdir=$2
            else
                echo "ERROR: Source directory \"$2\" does not exist."
                usage 1
            fi
            shift
            ;;
        -cmd )
            if [[ $2 == "copy" ]]; then
                runcmd="cp -rf"
            elif [[ $2 == "link" ]]; then
                runcmd="ln -sf"
            elif [[ $2 == "clean" ]]; then
                doclean=true
                runcmd="rm -rf"
            else
                echo "Unknown copy command: $2"
                usage 2
            fi
            cmdnote="${2^}"
            shift
            ;;
        mpas* | MPASSIT* | UPP* | WRF* | DART* | dart* )
            #packages=(${key//,/ })
            IFS="," read -r -a packages <<< "$key"
            ;;
        -* )
            echo "Unknown option: $key"
            usage 2
            ;;
        * )
            if [[ -d $key ]]; then
                desdir=$key
            elif [[ "$key" == "clean" ]]; then
                runcmd="clean"
            else
                 echo ""
                 echo "ERROR: unknown option, get [$key]."
                 usage 3
            fi
            ;;
    esac
    shift # past argument or value
done

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#
# Perform each task
#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\
#@ MAIN

exedir="$(dirname "${desdir}")/exec"
cd "$exedir" || exit 1
ln -sf ${tool_dir}/bin/gpmetis  .

for pkg in "${packages[@]}"; do
    case ${pkg^^} in

    #1. MPASSIT
    "MPASSIT" )
        srcmpassit=${srcdir-$srcmpassitdir}

        cd "$exedir" || exit 1

        echo "===  MPASSIT"
        echo "     SRC: $srcmpassit"
        echo "     CWD: $exedir"

        echo "  -- ${cmdnote} mpassit to $(pwd) ...."
        run_cmd "${runcmd}" "$srcmpassit/build" mpassit
        ;;

    #2. WRF
    "WRF" )
        srcwps=${srcdir-$srcwpsdir}
        srcwrf=${srcdir-$srcwrfdir}

        cd "$exedir" || exit 1

        echo ""
        echo "===  WRF "
        echo "     SRC: $srcwrf;    $srcwps"
        echo "     CWD: $exedir"

        echo "  -- ${cmdnote} ungrib.exe to $(pwd) ...."
        run_cmd "${runcmd}" "$srcwps/ungrib/src" ungrib.exe

        echo "  -- ${cmdnote} geogrid.exe to $(pwd) ...."
        run_cmd "${runcmd}" "$srcwps/geogrid/src" geogrid.exe
        ;;

    #3. UPP
    "UPP" )
        srcupp=${srcdir-$srcuppdir}

        cd "$desdir/UPP" || exit 1

        echo ""
        echo "===  UPP"
        echo "     SRC: $srcupp"
        echo "     CWD: $desdir"

        echo "  -- ${cmdnote} crtm2_fix to $(pwd) ...."

        run_cmd "${runcmd}" "$srcupp/src/lib/crtm2/src/fix" crtm2_fix

        cd "$exedir" || exit 1
        echo "  --  Executable"
        echo "     CWD: $exedir"

        echo "  -- ${cmdnote} unipost.exe to $(pwd) ...."
        run_cmd "${runcmd}" "${srcupp}/bin" unipost.exe
        ;;

    #4. DART
    "DART" )
        srcdart=${srcdir-$srcdartdir}

        if [[ $realrun == false ]]; then
            if [[ ! -e $exedir/dart ]]; then
                mkdir -p "$exedir/dart"
            fi
            cd "$exedir/dart" || exit 1

            echo ""
            echo "===  DART"
            echo "     SRC: ${srcdart}"
            echo "     CWD: ${exedir}"

            dartprograms=( filter  mpas_dart_obs_preprocess  obs_sequence_tool  update_mpas_states update_bc obs_seq_to_netcdf obs_diag)

            echo "  -- ${cmdnote} DART programs to $(pwd) ...."
            run_cmd "${runcmd}" "$srcdart/models/mpas_atm/work" "${dartprograms[*]}"

            cd "${desdir}" || exit 1
            echo "  -- ${cmdnote} DART static to $(pwd) ...."
            run_cmd "${runcmd}" "$srcdart/assimilation_code/programs/gen_sampling_err_table/work" "sampling_error_correction_table.nc"
        fi
        ;;
    #5. MPASREGION
    "MPASREGION" )
        if [[ $realrun == false ]]; then
            cd "$(dirname" ${desdir}")" || exit 1
            echo "---  ${cmdnote} ${srcmpasregion}/MPAS-Limited-Area"
            echo "     CWD: $(dirname "$desdir")"

            run_cmd "${runcmd}" "${srcmpasregion}" MPAS-Limited-Area
        fi
        ;;

    #6. MPAS
    "MPAS" )

        srcmodel=${srcdir-$srcmodeldir}

        cd "$desdir" || exit 1
        echo ""
        echo "===  MPAS Model"
        echo "     SRC: $srcmodel"
        echo "     CWD: $desdir"

        staticfiles=(CAM_ABS_DATA.DBL  CAM_AEROPT_DATA.DBL GENPARM.TBL       LANDUSE.TBL    \
                OZONE_DAT.TBL     OZONE_LAT.TBL       OZONE_PLEV.TBL    RRTMG_LW_DATA  \
                RRTMG_LW_DATA.DBL RRTMG_SW_DATA       RRTMG_SW_DATA.DBL VEGPARM.TBL )

        echo ""
        echo "  -- ${cmdnote} runtime static files to ${desdir} ...."

        run_cmd "${runcmd}" "${srcmodel}/src/core_atmosphere/physics/physics_wrf/files" "${staticfiles[*]}"

        if [[ ${realrun} == true ]]; then
            thompsonfiles=(MP_THOMPSON_freezeH2O_DATA.DBL MP_THOMPSON_QIautQS_DATA.DBL \
                           MP_THOMPSON_QRacrQG_DATA.DBL MP_THOMPSON_QRacrQS_DATA.DBL)

            cd "${desdir}" || exit 1

            run_cmd "${runcmd}" "${rootdir}/fix_files" "${thompsonfiles[*]}"
        else
            cd "$desdir" || exit 1

            #ln -sf /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/mesh_3km/x1.65536002.grid.nc .

            cd "$exedir" || exit 1
            echo ""
            echo "  -- Executables to $exedir"

            run_cmd "${runcmd}" "$srcmodel" "init_atmosphere_model atmosphere_model"

            src_dir=$(dirname "$srcmodel")
            run_cmd "${runcmd}" "$src_dir/MPAS-Tools/mesh_tools/grid_rotate" grid_rotate

        fi

        ;;
    * )
        echo "Argument should be one of [${default_packages[*]}]. get \"${pkg}\"."
        ;;
    esac
done

echo ""
exit 0
