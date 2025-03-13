#!/bin/bash

script_dir="$( cd "$( dirname "$0" )" && pwd )"              # dir of script

#-----------------------------------------------------------------------

source "$script_dir/Common_Colors.sh"

########################################################################

function usage {
    echo    " "
    echo    "    USAGE: $0 [options] SRCDIR [DESTDIR] [MEMBER_NO]"
    echo    " "
    echo    "    PURPOSE:    Link/Copy a MPAS case with its runtime files from SRCDIR to DESTIDR."
    echo    "                If it is one of the ensemble members, MEMBER_NO specifies the member number"
    echo    "                and SRCDIR/DESTDIR should be the parent directory for the corresponding member."
    echo    " "
    echo    "    SRCDIR    - MPAS case directory name. The parent directory for a ensemble member."
    echo    "    DESTDIR   - Target directory name. The target parent directory for a ensemble member"
    echo    "    MEMBER_NO - Member number No."
    echo    " "
    echo    "    OPTIONS:"
    echo    "              -h                  Display this message"
    echo    "              -n                  Show command to be run and generate job scripts only"
    echo    "              -v                  Verbose mode"
    echo    "              -s  fix_dir         Static file directory to replace the original static files"
    echo    " "
    echo    "   DEFAULTS:"
    echo    "              SRCDIR    = NULL (required)"
    echo -e "              DESTDIR   = ${LIGHT_BLUE}$(pwd)${NC}"
    echo    "              MEMBER_NO = None"
    echo    " "
    echo    "                                     -- By Y. Wang (2023.05.31)"
    echo    " "
    exit    "$1"
}

########################################################################
#
# Handle command line arguments
#
########################################################################

function parse_args {

    declare -Ag args

    #-------------------------------------------------------------------
    # Parse command line arguments
    #-------------------------------------------------------------------

    while [[ $# -gt 0 ]]; do
        key="$1"

        case $key in
            -h)
                usage 0
                ;;
            -n)
                args["dorun"]=false
                ;;
            -v)
                args["verb"]=true
                ;;
            -s)
                if [[ -d $2 ]]; then
                    args["fix_dir"]="$2"
                else
                    echo -e "${RED}ERROR${NC}: Fixed file directory - ${PURPLE}$2${NC} not exists."
                    usage 2
                fi
                shift
                ;;
            -*)
                echo -e "${RED}ERROR${NC}: Unknown option: ${PURPLE}$key${NC}"
                usage 2
                ;;
            *)
                if [[ -v args["srcrundir"] ]]; then
                    if [[ $key =~ ^[0-9]{1,2}$ ]]; then
                        args["memno"]="$key"
                    else
                        args["destdir"]="$key"
                    fi
                else
                    if [[ ! -d ${key} ]]; then
                        echo  -e "${RED}ERROR${NC}: MPAS runtime directory - ${key} not exists."
                        usage 3
                    fi
                    args["srcrundir"]="${key}"
                fi
                ;;
        esac
        shift # past argument or value
    done

    if [[ ! -v args["srcrundir"] ]]; then
        echo ""
        echo  -e "${RED}ERROR${NC}: A MPAS runtime directory is required."
        usage 4
    fi
}

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#
# Entry
#
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#% ARGS

parse_args "$@"

srcabsdir=$(realpath ${args["srcrundir"]})
[[ -v args["destdir"] ]] && destabsdir=$(realpath ${args["destdir"]}) || destabsdir=$(realpath .)
[[ -v args["memno"] ]]   && memno=${args["memno"]} || memno=""

[[ -v args["fix_dir"] ]] && fix_dir=${args["fix_dir"]}

[[ -v args["dorun"] ]]   && show="echo" || show=""
[[ -v args["verb"] ]]    && verb=true   || verb=false

#@ MAIN

srcabsdir=${srcabsdir##/mnt};   destabsdir=${destabsdir##/mnt}

echo ""
echo "SRCDIR: $srcabsdir"
echo "DESDIR: $destabsdir"
echo ""

if [[ -n $memno ]]; then
    memstr=$(printf "%02d" $memno)
    wrkdir="${destabsdir}/fcst_$memstr"
    srcdir="${srcabsdir}/fcst_$memstr"
else
    wrkdir="${destabsdir}"
    srcdir="${srcabsdir}"
fi

if [[ ! -r ${wrkdir} ]]; then
    mkdir -p ${wrkdir}
fi

cd ${wrkdir} || exit $?

#
# find symbolic files
#
#linkfiles=()
#while IFS='' read -r line; do linkfiles+=("$line"); done < <(find "${srcdir}" -type l)
##linkfiles=($(find $srcabsdir -type l))
#
#echo "Linking symbolic files ..."
#for fn in "${linkfiles[@]}"; do
#    #echo "$fn -> $(readlink $fn)"
#    echo "Linking $(basename $fn) ..."
#    ${show} ln -sf $(realpath $fn) $(basename $fn)
#done
static_files=(  CAM_ABS_DATA.DBL     RRTMG_LW_DATA      CAM_AEROPT_DATA.DBL  RRTMG_LW_DATA.DBL   \
                GENPARM.TBL          RRTMG_SW_DATA      LANDUSE.TBL          RRTMG_SW_DATA.DBL   \
                OZONE_DAT.TBL        SOILPARM.TBL       OZONE_LAT.TBL        VEGPARM.TBL         \
                OZONE_PLEV.TBL                                                                   \
                MP_THOMPSON_freezeH2O_DATA.DBL MP_THOMPSON_QIautQS_DATA.DBL                      \
                MP_THOMPSON_QRacrQG_DATA.DBL MP_THOMPSON_QRacrQS_DATA.DBL CCN_ACTIVATE.BIN)

echo "Linking static files ..."
for fn in "${static_files[@]}"; do
    if compgen -G $srcdir/$fn > /dev/null; then
        [[ $verb == true ]] && echo "$fn -> $(readlink $fn)"
        [[ -v fix_dir ]]    && src_file="${fix_dir}/$fn" || src_file=$(realpath "${srcdir}/$fn")
        echo "Linking $fn ..."
        ${show} ln -sf ${src_file} $fn
    fi
done

#
# Hard copy some files
#

cpfiles=(namelist.atmosphere streams.atmosphere          \
         stream_list.atmosphere.output stream_list.atmosphere.surface)

for fn in "${cpfiles[@]}"; do
    echo "Copying $fn ..."
    ${show} cp "$srcdir/$fn" .
done

cpanyone=(stream_list.atmosphere.diagnostics stream_list.atmosphere.diagnostics_fcst stream_list.atmosphere.diagnostics_da )
for fn in "${cpanyone[@]}"; do
   if [[ -e "$srcdir/$fn" ]]; then
       echo "Copying $fn ..."
       ${show} cp "$srcdir/$fn" .
   fi
done

#
# for ICs/LBCs
#
if compgen -G ./*.invariant.nc > /dev/null; then
    :                                                  # skip if the file already exists
else
    if compgen -G $srcdir/*.invariant.nc > /dev/null; then
        ${show} ln -sf $srcdir/*.invariant.nc .
    fi
fi

if compgen -G ./*.init*.nc > /dev/null; then
    :
else
    if compgen -G $srcdir/*.init*.nc > /dev/null; then
        ${show} ln -sf $srcdir/*.init*.nc .
    fi
fi

if compgen -G ./*.lbc*.nc > /dev/null; then
    :
else
    ${show} ln -sf $srcdir/*.lbc.*.nc .
fi

if compgen -G ./*.graph.info.part.* > /dev/null; then
    :
else
    ${show} ln -sf $srcdir/*.graph.info.part.* .
fi

#
# Modify job script
#
jobfile=""
if [[ -f ${srcabsdir}/run_mpas.slurm ]]; then
    jobfile="run_mpas.slurm"
elif [[ -f $srcabsdir/run_mpas.pbs ]]; then
    jobfile="$srcabsdir/run_mpas.pbs"
fi

if [[ -n "${jobfile}" ]]; then
    cd "${destabsdir}"  || exit $?
    echo "Copying ${jobfile} ..."
    ${show} cp $srcabsdir/${jobfile} .

    echo "Modify dirname in \"$jobfile\" ..."
    ${show} sed -i "s#$srcabsdir#$destabsdir#g" "${jobfile}"
fi

exit 0
