#!/bin/bash

srcroot="/lfs4/NAGAPE/hpc-wof1/ywang/MPAS"

scpdir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script
rootdir=$(realpath $(dirname $scpdir))

if [[ "$(hostname)" == "odin"* ]]; then
    desdir=${rootdir}/templates
    srcmpassitdir=${srcroot}/MPASSIT
    srcuppdir=${srcroot}/UPP_KATE_kjet
    srcmodeldir=${srcroot}/MPAS-Model.smiol
    srcwpsdir=/oldscratch/ywang/NEWSVAR/news3dvar.2021/WPS
    srcwrfdir=/oldscratch/ywang/NEWSVAR/news3dvar.2021/WRFV3.9_WOFS_2021
else
    desdir=${rootdir}/templates
    srcmpassitdir=${srcroot}/MPASSIT
    srcuppdir=${srcroot}/UPP_KATE_kjet
    srcmodeldir=${srcroot}/MPAS-Model.smiol
    srcwpsdir=${srcroot}/WPS_SRC
    srcwrfdir=${srcroot}/WRFV4.0
fi

function usage {
    echo " "
    echo "    USAGE: $0 [options] CMD [DESTDIR] [clean]"
    echo " "
    echo "    PURPOSE: Link MPAS runtime static files and executables."
    echo " "
    echo "    DESTDIR  - Destination Directory"
    echo "    CMD      - One or more jobs from [mpas,MPASSIT,UPP,WRF]"
    echo "               Default: all in \"[mpas, MPASSIT, UPP, WRF]\""
    echo "    clean    - Clean the linked or copied files (for relink with a system version change etc.)"
    echo " "
    echo "    OPTIONS:"
    echo "              -h              Display this message"
    echo "              -n              Show command to be run only"
    echo "              -v              Verbose mode"
    echo "              -r              For a run or for templates"
    echo "                              Default is for templates"
    echo "              -s  DIR         Source directory"
    echo "              -m  Machine     Machine name to be run, [Jet or Odin]"
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
    exit $1
}

#-----------------------------------------------------------------------
#
# Handle command line arguments
#
#-----------------------------------------------------------------------
cmds=(mpas MPASSIT UPP WRF)

verb=0
machine="Jet"
runcmd="ln -sf"
run=0

while [[ $# > 0 ]]
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
        -m )
            if [[ ${2^^} == "JET" ]]; then
                machine=Jet
            elif [[ ${2^^} == "ODIN" ]]; then
                machine=Odin
            else
                echo "ERROR: Unsupported machine name, got \"$2\"."
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
                runcmd="clean"
            else
                echo "Unknown copy command: $2"
                usage 2
            fi
            shift
            ;;
        mpas* | MPASSIT* | UPP* | WRF* )
            cmds=(${key//,/ })
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

exedir="$(dirname $desdir)/exec"

for cmd in ${cmds[@]}; do
    case $cmd in

    "MPASSIT" )
        srcmpassit=${srcdir-$srcmpassitdir}

        cd $desdir/MPASSIT
        echo " "
        echo "CWD: $desdir"

        parmfiles=(diaglist histlist_2d histlist_3d histlist_soil)
        for fn in ${parmfiles[@]}; do
            #if [[ ! -e $fn ]]; then
                if [[ $verb -eq 1 ]]; then
                    echo "Linking $fn ...";
                fi
                if [[ ${runcmd} == "clean" ]]; then
                    rm $fn
                else
                    ${runcmd} $srcmpassit/parm/$fn .
                fi
            #fi
        done

        cd $exedir
        echo " "
        echo "CWD: $exedir"
        if [[ ${runcmd} == "clean" ]]; then
            rm mpassit
        else
            ${runcmd} $srcmpassit/build/mpassit .
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

        cd $exedir
        echo " "
        echo "CWD: $exedir"
        if [[ ${runcmd} == "clean" ]]; then
            rm ungrib.exe
        else
            ${runcmd} $srcwps/ungrib/src/ungrib.exe .
        fi

        #${runcmd} $srcwps/geogrid/src/geogrid.exe .
        ;;

    "UPP" )
        srcupp=${srcdir-$srcuppdir}

        cd $desdir/UPP
        echo " "
        echo "CWD: $desdir"

        if [[ ${runcmd} == "clean" ]]; then
            rm crtm2_fix
        else
            ${runcmd} $srcupp/src/lib/crtm2/src/fix crtm2_fix
        fi

        cd $exedir
        echo " "
        echo "CWD: $exedir"
        if [[ ${runcmd} == "clean" ]]; then
            rm unipost.exe
        else
            ${runcmd} $srcupp/bin/unipost.exe .
        fi
        ;;

    "mpas" )

        srcmodel=${srcdir-$srcmodeldir}

        cd $desdir
        echo " "
        echo "CWD: $desdir"

        staticfiles=(CAM_ABS_DATA.DBL  CAM_AEROPT_DATA.DBL GENPARM.TBL       LANDUSE.TBL    \
                OZONE_DAT.TBL     OZONE_LAT.TBL       OZONE_PLEV.TBL    RRTMG_LW_DATA  \
                RRTMG_LW_DATA.DBL RRTMG_SW_DATA       RRTMG_SW_DATA.DBL SOILPARM.TBL   \
                VEGPARM.TBL)

        for fn in ${staticfiles[@]}; do
            if [[ $verb -eq 1 ]]; then
                echo "Linking $fn ....";
            fi
            if [[ ${runcmd} == "clean" ]]; then
                rm $fn
            else
                ${runcmd} $srcmodel/src/core_atmosphere/physics/physics_wrf/files/$fn .
            fi
        done

        if [[ $run -ne 1 ]]; then
            cd $desdir

            streamfiles=( stream_list.atmosphere.diagnostics stream_list.atmosphere.output  \
                stream_list.atmosphere.surface streams.atmosphere streams.init_atmosphere   \
                namelist.atmosphere namelist.init_atmosphere )

            for fn in ${streamfiles[@]}; do
                if [[ $verb -eq 1 ]]; then
                    echo "Linking $fn ....";
                fi
                if [[ ${runcmd} == "clean" ]]; then
                    rm $fn
                else
                    ${runcmd} $srcmodel/$fn .
                fi
            done

            #domgridfiles=(wofs_mpas.grid.nc)
            #for domfile in ${domgridfiles[@]}; do
            #    if [[ ${runcmd} == "clean" ]]; then
            #        rm $fn
            #    else
            #        ${runcmd} $srcroot/$domfile .
            #    fi
            #done

            cd $exedir
            echo " "
            echo "CWD: $exedir"
            if [[ ${runcmd} == "clean" ]]; then
                rm init_atmosphere_model atmosphere_model.single
            else
                ${runcmd} $srcmodel/init_atmosphere_model .
                ${runcmd} $srcmodel/atmosphere_model atmosphere_model.single
            fi
        fi

        ;;
    * )
        echo "Argument should be one of [mpas, MPASSIT, WRF, UPP, exec]. get \"${cmd}\"."
        ;;
    esac
done

exit 0