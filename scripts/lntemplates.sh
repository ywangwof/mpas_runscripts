#!/bin/bash

if [[ "$(hostname)" == "odin"* ]]; then
    desdir=/scratch/ywang/MPAS/mpas_runscripts/templates
    srcmpassitdir=/scratch/ywang/MPAS/MPASSIT
    srcuppdir=/scratch/ywang/MPAS/UPP_KATE_kjet
    srcmodeldir=/scratch/ywang/MPAS/MPAS-Model.smiol
else
    desdir=/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/runscriptv2.0/templates
    srcmpassitdir=/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/MPASSIT
    srcuppdir=/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/UPP_KATE_kjet
    srcmodeldir=/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/MPAS-Model.smiol
fi

function usage {
    echo " "
    echo "    USAGE: $0 [options] CMD [DESTDIR]"
    echo " "
    echo "    PURPOSE: Link MPAS runtime static files."
    echo " "
    echo "    WORKDIR  - Destination Directory"
    echo "    CMD      - One or more jobs from [mpas,MPASSIT,UPP,WRF]"
    echo "               Default \"mpas\""
    echo " "
    echo "    OPTIONS:"
    echo "              -h              Display this message"
    echo "              -n              Show command to be run only"
    echo "              -v              Verbose mode"
    echo "              -r              For run or for templates"
    echo "                              Default is for templates"
    echo "              -s  DIR         Source directory"
    echo "              -m  Machine     Machine name to run, [Jet or Odin]."
    echo " "
    echo "   DEFAULTS:"
    echo "              desdir     = $desdir"
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
cmd="mpas"

verb=0
machine="Jet"
runcmd=""
run=0

while [[ $# > 0 ]]
    do
    key="$1"

    case $key in
        -h)
            usage 0
            ;;
        -n)
            runcmd="echo"
            ;;
        -v)
            verb=1
            ;;
        -r)
            run=1
            ;;
        -s)
            if [[ -d $2 ]]; then
                srcdir=$2
            else
                echo "ERROR: Source directory \"$2\" does not exist."
                usage 1
            fi
            shift
            ;;
        -m)
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
        mpas | MPASSIT | UPP | WRF)
            cmd=${key}
            ;;
        -*)
            echo "Unknown option: $key"
            usage 2
            ;;
        *)
            if [[ -d $key ]]; then
                desdir=$key
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

if [[ $cmd == "MPASSIT" ]]; then
    srcmpassit=${srcdir-$srcmpassitdir}

    cd $desdir/MPASSIT

    parmfiles=(diaglist histlist_2d histlist_3d histlist_soil)
    for fn in ${parmfiles[@]}; do
        if [[ ! -e $fn ]]; then
            if [[ $verb -eq 1 ]]; then echo "Linking $fn ..."; fi
            ln -sf $srcmpassit/parm/$fn .
        fi
    done
#elif [[ $1 == "WRF" ]]; then
#    srcwps=/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/WPS_SRC
#    srcwrf=/lfs4/NAGAPE/hpc-wof1/ywang/MPAS/WRFV4.0
#
#    cd $destdir/WRFV4.0
#
#    cp $srcwps/geogrid/GEOGRID.TBL.ARW .
#    cp $srcwps/ungrib/Variable_Tables/Vtable.GFS     Vtable.GFS_full
#    cp $srcwps/ungrib/Variable_Tables/Vtable.raphrrr Vtable.raphrrr
#
#
#    parmfiles=(ETAMPNEW_DATA ETAMPNEW_DATA.expanded_rain)
#    for fn in ${parmfiles[@]}; do
#        if [[ ! -e $fn ]]; then
#            if [[ $verb -eq 1 ]]; then echo "Linking $fn ..."; fi
#            cp $srcwrf/test/em_real/$fn .
#        fi
#    done

elif [[ $cmd == "UPP" ]]; then
    srcupp=${srcdir-$srcuppdir}

    cd $desdir/UPP

    ln -sf $srcupp/src/lib/crtm2/src/fix crtm2_fix

elif [[ $cmd == "mpas" ]]; then

    srcmodel=${srcdir-$srcmodeldir}

    cd $desdir

    staticfiles=( CAM_ABS_DATA.DBL  CAM_AEROPT_DATA.DBL GENPARM.TBL       LANDUSE.TBL    \
            OZONE_DAT.TBL     OZONE_LAT.TBL       OZONE_PLEV.TBL    RRTMG_LW_DATA  \
            RRTMG_LW_DATA.DBL RRTMG_SW_DATA       RRTMG_SW_DATA.DBL SOILPARM.TBL   \
            VEGPARM.TBL )


    for fn in ${staticfiles[@]}; do
        echo "Linking $fn ...."
        ln -sf $srcmodel/src/core_atmosphere/physics/physics_wrf/files/$fn .
    done

    if [[ $run -ne 1 ]]; then
        streamfiles=( stream_list.atmosphere.diagnostics stream_list.atmosphere.output  \
            stream_list.atmosphere.surface streams.atmosphere streams.init_atmosphere   \
            namelist.atmosphere namelist.init_atmosphere )

        for fn in ${streamfiles[@]}; do
            echo "Linking $fn ...."
            ln -sf $srcmodel/$fn .
        done
    fi
else
    echo "Argument should be one of [mpas, MPASSIT, WRF, UPP]. get \"${cmd}\"."
fi

exit 0
