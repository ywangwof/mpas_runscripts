#!/bin/bash

srcroot="/lfs4/NAGAPE/hpc-wof1/ywang/MPAS"

scpdir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
rootdir=$(realpath "$(dirname "${scpdir}")")

desdir=${rootdir}/fix_files

myhost=$(hostname)
if [[ "${myhost}" == "ln"* ]]; then
    srcmpassitdir=${srcroot}/MPASSIT
    srcuppdir=${srcroot}/UPP_KATE_kjet
    srcmodeldir=${srcroot}/MPAS-Model
    srcwpsdir=/oldscratch/ywang/NEWSVAR/news3dvar.2021/WPS
    srcwrfdir=/oldscratch/ywang/NEWSVAR/news3dvar.2021/WRFV3.9_WOFS_2021
elif [[ "${myhost}" == "cheyenne"* || ${myhost} == "derecho"* ]]; then
    rootdir="/glade/work/ywang/mpas_runscripts"
    scpdir="/glade/work/ywang/mpas_runscripts/scripts"
    srcroot="/glade/work/ywang"
    srcmpassitdir=${srcroot}/MPASSIT
    srcuppdir=${srcroot}/UPP_KATE_kjet
    srcmodeldir=${srcroot}/MPAS-Model
    srcwpsdir=${srcroot}/WPS_SRC
    srcwrfdir=${srcroot}/WRFV4.0
    srcdartdir=${srcroot}/DART
else
    srcmpassitdir=${srcroot}/MPASSIT
    srcuppdir=${srcroot}/UPP_KATE_kjet
    srcmodeldir=${srcroot}/MPAS-Model
    srcwpsdir=${srcroot}/WPS_SRC
    srcwrfdir=${srcroot}/WRFV4.0
    srcdartdir=${srcroot}/DART
    srcmpasregion=${srcroot}/MPAS-Limited-Area
fi

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

#-----------------------------------------------------------------------
#
# Handle command line arguments
#
#-----------------------------------------------------------------------
#% ARGS

cmds=(mpas MPASSIT UPP WRF DART)

verb=0
#machine="Jet"
runcmd="ln -sf"
run=0

while [[ $# -gt 0 ]]
    do
    key="$1"

    case $key in
        -h )
            usage 0
            ;;
        -n )
            runcmd="echo $runcmd"
            ;;
        -v )
            verb=1
            ;;
        -r )
            run=1
            cmds=(mpas)
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
        #-m )
        #    if [[ ${2^^} == "JET" ]]; then
        #        machine=Jet
        #    elif [[ ${2^^} == "ODIN" ]]; then
        #        machine=Odin
        #    else
        #        echo "ERROR: Unsupported machine name, got \"$2\"."
        #        usage 1
        #    fi
        #    shift
        #    ;;
        -cmd )
            if [[ $2 == "copy" ]]; then
                runcmd="cp -rf"
            elif [[ $2 == "link" ]]; then
                runcmd="ln -sf"
            elif [[ $2 == "clean" ]]; then
                runcmd="clean"
            else
                echo "Unknown copy command: $2"
                usage 2
            fi
            shift
            ;;
        mpas* | MPASSIT* | UPP* | WRF* | DART* | dart* )
            #cmds=(${key//,/ })
            IFS="," read -r -a cmds <<< "$key"
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

for cmd in "${cmds[@]}"; do
    case ${cmd^^} in

    "MPASSIT" )
        srcmpassit=${srcdir-$srcmpassitdir}

        cd "${desdir}/MPASSIT" || exit 1
        echo "===  MPASSIT"
        echo "     SRC: $srcmpassit"
        echo "     CWD: $desdir"

        # They are now managed through Git
        #
        #parmfiles=(diaglist histlist_2d histlist_3d histlist_soil)
        #for fn in ${parmfiles[@]}; do
        #    #if [[ ! -e $fn ]]; then
        #        if [[ $verb -eq 1 ]]; then
        #            echo "Linking $fn ...";
        #        fi
        #        if [[ ${runcmd} == "clean" ]]; then
        #            rm -f $fn
        #        else
        #            ${runcmd} $srcmpassit/parm/$fn .
        #        fi
        #    #fi
        #done

        cd "$exedir" || exit 1
        echo "  --  Executable"
        echo "     CWD: $exedir"
        if [[ ${runcmd} == "clean" ]]; then
            rm -f mpassit
        else
            ${runcmd} "$srcmpassit/build/mpassit" .
        fi
        ;;

    "WRF" )
        srcwps=${srcdir-$srcwpsdir}
        srcwrf=${srcdir-$srcwrfdir}

        #cd $destdir/WRFV4.0
        #
        #cp $srcwps/geogrid/GEOGRID.TBL.ARW .
        #cp $srcwps/ungrib/Variable_Tables/Vtable.GFS     Vtable.GFS_full
        #cp $srcwps/ungrib/Variable_Tables/Vtable.raphrrr Vtable.raphrrr
        #
        #
        #parmfiles=(ETAMPNEW_DATA ETAMPNEW_DATA.expanded_rain)
        #for fn in ${parmfiles[@]}; do
        #    if [[ ! -e $fn ]]; then
        #        if [[ $verb -eq 1 ]]; then echo "Linking $fn ..."; fi
        #        cp $srcwrf/test/em_real/$fn .
        #    fi
        #done

        cd "$exedir" || exit 1

        echo ""
        echo "===  WRF "
        echo "     SRC: $srcwrf;    $srcwps"
        echo "     CWD: $exedir"
        if [[ ${runcmd} == "clean" ]]; then
            rm -f ungrib.exe
        else
            ${runcmd} "$srcwps/ungrib/src/ungrib.exe" .
        fi

        #${runcmd} $srcwps/geogrid/src/geogrid.exe .
        ;;

    "UPP" )
        srcupp=${srcdir-$srcuppdir}

        cd "$desdir/UPP" || exit 1

        echo ""
        echo "===  UPP"
        echo "     SRC: $srcupp"
        echo "     CWD: $desdir"

        if [[ ${runcmd} == "clean" ]]; then
            rm -f crtm2_fix
        else
            ${runcmd} "$srcupp/src/lib/crtm2/src/fix" crtm2_fix
        fi

        cd "$exedir" || exit 1
        echo "  --  Executable"
        echo "     CWD: $exedir"
        if [[ ${runcmd} == "clean" ]]; then
            rm -f unipost.exe
        else
            ${runcmd} "${srcupp}/bin/unipost.exe" .
        fi
        ;;

    "DART" )
        srcdart=${srcdir-$srcdartdir}

        if [[ $run -ne 1 ]]; then
            if [[ ! -e $exedir/dart ]]; then
                mkdir -p "$exedir/dart"
            fi
            cd "$exedir/dart" || exit 1
            echo ""
            echo "===  DART"
            echo "     SRC: ${srcdart}"
            echo "     CWD: ${exedir}"
            dartprograms=( filter  mpas_dart_obs_preprocess  obs_sequence_tool  update_mpas_states update_bc advance_time obs_seq_to_netcdf obs_diag)
            if [[ ${runcmd} == "clean" ]]; then
                #echo "    Deleting ${dartprograms[*]}"
                rm -f "${dartprograms[@]}"
            else
                echo ""
                echo "  -- Copying DART programs to $(pwd) ...."
                for prog in "${dartprograms[@]}"; do
                    echo "        $srcdart/models/mpas_atm/work/$prog"
                    ${runcmd} "$srcdart/models/mpas_atm/work/$prog" .
                done
                echo "        $srcdart/models/wrf/work/convertdate"
                ${runcmd} "$srcdart/models/wrf/work/convertdate" .
            fi
        fi
        ;;
    "mpasregion" )
        if [[ $run -ne 1 ]]; then
            cd "$(dirname" ${desdir}")" || exit 1
            echo "---  Linking ${srcmpasregion}/MPAS-Limited-Area"
            echo "     CWD: $(dirname "$desdir")"
            if [[ ${runcmd} == "clean" ]]; then
                rm -f MPAS-Limited-Area
            else
                ${runcmd} "${srcmpasregion}/MPAS-Limited-Area" .
            fi
        fi
        ;;
    "mpas" )

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
        echo "  -- Linking runtime static files to ${desdir} ...."
        for fn in "${staticfiles[@]}"; do
            if [[ $verb -eq 1 ]]; then
                echo "        $srcmodel/src/core_atmosphere/physics/physics_wrf/files/$fn";
            fi
            if [[ ${runcmd} == "clean" ]]; then
                rm -f "$fn"
            else
                ${runcmd} "${srcmodel}/src/core_atmosphere/physics/physics_wrf/files/$fn" .
            fi
        done

        if [[ $run -ne 1 ]]; then
            cd "$desdir" || exit 1

            ln -sf /lfs4/NAGAPE/hpc-wof1/ywang/MPAS/mesh_3km/x1.65536002.grid.nc .

            # These files are not managed by Git
            #
            #streamfiles=( stream_list.atmosphere.diagnostics stream_list.atmosphere.output  \
            #    stream_list.atmosphere.surface streams.atmosphere streams.init_atmosphere   \
            #    namelist.atmosphere namelist.init_atmosphere )

            #for fn in ${streamfiles[@]}; do
            #    if [[ $verb -eq 1 ]]; then
            #        echo "Linking $fn ....";
            #    fi
            #    if [[ ${runcmd} == "clean" ]]; then
            #        rm -f $fn
            #    else
            #        ${runcmd} $srcmodel/$fn .
            #    fi
            #done

            #domgridfiles=(wofs_mpas.grid.nc)
            #for domfile in ${domgridfiles[@]}; do
            #    if [[ ${runcmd} == "clean" ]]; then
            #        rm -f $fn
            #    else
            #        ${runcmd} $srcroot/$domfile .
            #    fi
            #done

            cd "$exedir" || exit 1
            echo ""
            echo "  -- Executables to $exedir"
            if [[ ${runcmd} == "clean" ]]; then
                rm -f init_atmosphere_model atmosphere_model.single grid_rotate
            else
                echo "        $srcmodel/init_atmosphere_model --> init_atmosphere_model"
                ${runcmd} "$srcmodel/init_atmosphere_model" .
                echo "        $srcmodel/atmosphere_model      --> atmosphere_model.single"
                ${runcmd} "$srcmodel/atmosphere_model" atmosphere_model.single

                srcdir=$(dirname "$srcmodel")
                if [[ -e $srcdir/MPAS-Tools/mesh_tools/grid_rotate/grid_rotate  ]]; then
                    echo "        $srcdir/MPAS-Tools/mesh_tools/grid_rotate/grid_rotate --> grid_rotate"
                    ${runcmd} "$srcdir/MPAS-Tools/mesh_tools/grid_rotate/grid_rotate" .
                else
                    echo "ERROR: not exist: $srcdir/MPAS-Tools/mesh_tools/grid_rotate/grid_rotate"
                    #exit 0
                fi
            fi
        else
            thompsonfiles=(MP_THOMPSON_freezeH2O_DATA.DBL MP_THOMPSON_QIautQS_DATA.DBL \
                           MP_THOMPSON_QRacrQG_DATA.DBL MP_THOMPSON_QRacrQS_DATA.DBL)

            cd "${desdir}" || exit 1

            for fn in "${thompsonfiles[@]}"; do
                if [[ $verb -eq 1 ]]; then
                    echo "Linking $fn ....";
                fi
                if [[ ${runcmd} == "clean" ]]; then
                    rm -f "$fn"
                else
                    ${runcmd} "${rootdir}/fix_files/$fn" .
                fi
            done
        fi

        ;;
    * )
        echo "Argument should be one of [${cmds[*]}]. get \"${cmd}\"."
        ;;
    esac
done

echo ""
exit 0
