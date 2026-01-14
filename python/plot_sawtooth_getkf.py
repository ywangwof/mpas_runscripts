import numpy as np
import sys, os, glob
from netCDF4 import Dataset
from datetime import datetime, timedelta
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

################
### Settings ###
################

# Experiment configuration and paths
com_dir = '/mnt/lfs5/NAGAPE/hpc-wof1/ywang/MPAS-WoFS/run_dirs'
#com_dir = '/mnt/lfs6/BMC/wrfruc/ddowell/MPAS_south_3.5km/radar_only_loc50_obs0.03_heavy_thinning/com'

first_cycle = '202405081500'
final_cycle = '202405082100'
cycletime = 15 # min
nmems = 36
version = 'v2.1.1'

# Also compute total spread? sqrt(bkg spd + obserr)
do_spread = True

# If do_qc = True, remove all obs from verification with bad obs error.
# If using ReduceObsSpace (default), this will have minimal to no impact
do_qc = True

# List of obs to verify over
# Currently works for t, q, uv, and dbz obs

oblist = ['CWB_rw.nc']
#oblist = ['mrms_refl.nc']
#oblist = ['adpupa_t120.nc']

# If over_type == 'thresh', then only verify over obs where obs val > obs_thresh
# This is useful for dbz verification where we do not want to verify over all clear air pts
#over_type = 'thresh'
over_type = 'all'
#obs_thresh = 15.0

#############################
### Begin executable code ###
#############################

# Build list of cycle times and run directories
cyclelist = []; dirlist = []; minutes = []; stmplist = []
first_cycle_dt = datetime.strptime(first_cycle, '%Y%m%d%H%M')
this_cycle_dt = datetime.strptime(first_cycle, '%Y%m%d%H%M')
final_cycle_dt = datetime.strptime(final_cycle, '%Y%m%d%H%M')
while this_cycle_dt <= final_cycle_dt:
    date = this_cycle_dt.strftime('%Y%m%d')
    hour = this_cycle_dt.strftime('%H')
    minute = this_cycle_dt.strftime('%M')
    cyclelist.append(this_cycle_dt)
    dirlist.append(f'{com_dir}/{date}/dacycles_CADRE2_RUC_20251215/{hour}{minute}/getkf_observer/')
    stmplist.append(f'{com_dir}/{date}/dacycles_CADRE2_RUC_20251215/{hour}{minute}/getkf_post/')

    #dirlist.append(f'{com_dir}/rrfs/{version}/rrfs.{date}/{hour}/getkf_observer/enkf')
    #stmplist.append(f'{com_dir}/../stmp/{date}/rrfs_getkf_post_{hour}_{version}/enkf')

    minute = int((this_cycle_dt - first_cycle_dt).total_seconds()/60)
    minutes.append(minute); minutes.append(minute)
    this_cycle_dt = this_cycle_dt + timedelta(minutes = cycletime)


# Go through each cycle and read the jdiag file for each ob type
for iob, obfile in enumerate(oblist):
    innov_all = []; rmsd_all = []; spread_all = []; num_all = []
    for icycle, cycle in enumerate(cyclelist):

        # Read obs space diagnostics
        rundir = dirlist[icycle]
        obpath = f'{rundir}/jdiag_{obfile}'
        obpath_stmp = f'{stmplist[icycle]}/jdiag_{obfile}'

        print(f'obpath: {obpath}')
        if not os.path.exists(obpath):
            print(f'File does not exist, assigning nans: {obpath}')
            rmsd_all.append(np.nan)
            rmsd_all.append(np.nan)
            spread_all.append(np.nan)
            continue

        # Read BG file for o-b
        nc = Dataset(obpath, 'r')
        vartype = list(nc.groups['ombg'].variables.keys())[0]
        ombg = nc.groups['ombg'].variables[vartype][:]
        obs_bg = nc.groups['ObsValue'].variables[vartype][:]
        pre_qcb = nc.groups['PreQC'].variables[vartype][:]
        obs_errb = nc.groups['ObsError'].variables[vartype][:]
        allobs_ct = ombg.shape[0]     #Number of observations in input file

        # Read AN file for o-a
        nc2 = Dataset(obpath_stmp, 'r')
        oman = nc2.groups['oman'].variables[vartype][:]
        obs_an = nc2.groups['ObsValue'].variables[vartype][:]
        pre_qca = nc2.groups['PreQC'].variables[vartype][:]
        obs_erra = nc2.groups['ObsError'].variables[vartype][:]
        #obs_eqc = nc2.groups['EffectiveQC0'].variables[vartype][:]
        #obs_error = nc2.groups['EffectiveError0'].variables[vartype][:]

        obs_bg0 = obs_bg
        obs_an0 = obs_an

        #### REMOVE OUTLIERS FROM CALCULATION AND COUNT
        # OUTLIERS AND OBSERVATIONS WHERE THE FO FAILED TO OPERARE HAVE obserr set to NaN
        #qc_maskb = np.isnan(obs_errb)
        #qc_maska = np.isnan(obs_erra)

        qc_maskb = obs_errb[~obs_errb.mask]
        qc_maska = obs_erra[~obs_erra.mask]

        print(ombg.shape[0], qc_maskb.shape[0],qc_maska.shape[0])

        ombg = ombg[~obs_errb.mask]
        oman = oman[~obs_erra.mask]
        obs_bg = obs_bg[~obs_errb.mask]
        obs_an = obs_an[~obs_erra.mask]

        obsb_num0 = qc_maskb.shape[0]   #Number of observations where foreward operator worked and priors calculated 
        obsa_num0 = qc_maska.shape[0]   #As above, but with outliers now also removed. obsa should always be <= to obsb
 
        obsb_num = obsb_num0
        obsa_num = obsa_num0

        # Remove any obs if not doing all (for reflectivity when only wanting to look at non-zero obs)
        if over_type == 'thresh':

            ombg[obs_bg < obs_thresh] = np.nan
            oman[obs_an < obs_thresh] = np.nan

            obsb_num = np.sum(obs_bg > obs_thresh )
            oman_num = np.sum(obs_an > obs_thresh )


        # Also read all members to get spread
        if do_spread:
            hofxa_all = []
            hofx_all = []
            for imem in range(1, nmems+1):
                hofx = nc.groups[f'hofx0_{imem}'].variables[vartype][:].astype(np.float64)
                hofxa = nc2.groups[f'hofx0_{imem}'].variables[vartype][:].astype(np.float64)

                #OUTLIER/QC CHECK
                #hofx[~obs_errb.mask] = np.nan
                #hofxa[~obs_erra.mask] = np.nan

                hofx = hofx[~obs_errb.mask]
                hofxa = hofxa[~obs_erra.mask]
            
                if over_type == 'thresh':
                    hofx[obs_bg < obs_thresh] = np.nan
                    hofxa[obs_an < obs_thresh] = np.nan

                hofx_all.append(hofx)
                hofxa_all.append(hofxa)
            hofx_all = np.asarray(hofx_all)
            hofxa_all = np.asarray(hofxa_all)

            #spread = np.nanmean(np.nanstd(hofx_all, axis=0))
            #spreada = np.nanmean(np.nanstd(hofxa_all, axis=0))

            sprdb = np.nanstd(hofx_all, axis=0)
            sprda = np.nanstd(hofxa_all, axis=0)

            is_nan_maskb = np.isnan(sprdb)
            is_nan_maska = np.isnan(sprda)
            
            #TOTAL SPREAD
            sprd_prior = np.sqrt( np.sum( np.nanmean(obs_errb)**2.0+(sprdb[~is_nan_maskb]*sprdb[~is_nan_maskb]) )/sprdb[~is_nan_maskb].shape[0])
            sprd_post =  np.sqrt( np.sum( np.nanmean(obs_erra)**2.0+(sprda[~is_nan_maska]*sprda[~is_nan_maska]) )/sprda[~is_nan_maska].shape[0])

            spread_all.append(sprd_prior)
            spread_all.append(sprd_post)

        nc.close()
        nc2.close()


        # Compute RMSD
        rmsd_bg = np.nanmean(ombg**2.0)**0.5
        rmsd_an = np.nanmean(oman**2.0)**0.5

        # Copmute Innovation (O-F/A)
        innov_bg = np.nanmean(ombg)
        innov_an = np.nanmean(oman)

        rmsd_all.append(rmsd_bg)
        rmsd_all.append(rmsd_an)
        num_all.append(obsb_num)
        num_all.append(obsa_num)
        #num_all.append(allobs_ct)
        innov_all.append(innov_bg)
        innov_all.append(innov_an)

    rmsd_all = np.asarray(rmsd_all)
    num_all = np.asarray(num_all)
    innov_all = np.asarray(innov_all)
    if do_spread: spread_all = np.asarray(spread_all)

    print(num_all)
    print(innov_all)
    print(rmsd_all)
    print(spread_all)

    ######################################
    ### Plot for each observation type ###
    ######################################

    if vartype == 'airTemperature':
        unit = 'K'
        ymax = 2.0
    elif vartype == 'specificHumidity':
        unit = 'g/kg'
        ymax = 4.0
    elif vartype in ['windNorthward', 'windEastward']:
        unit = 'm/s'
        ymax = 6.0
    elif vartype == 'equivalentReflectivityFactor':
        unit = 'dBZ'
        if over_type == 'all':
            ymax = 6
        elif over_type == 'thresh':
            ymax = 20
    elif vartype == 'radialVelocity':
        unit = 'm/s'
        ymax = 10

    # Sawtooth
    ax1 = plt.subplot(1,1,1)

    #RMSD
    plt.plot(minutes,rmsd_all,'tab:red',linewidth=2.0)

    #SPREAD
    if do_spread:
        #plt.plot(minutes[::2],spread_all,'tab:green',linestyle='--',linewidth=2.0)
        plt.plot(minutes,spread_all,'tab:green',linestyle='--',linewidth=2.0)

    #BIAS
    plt.plot(minutes,innov_all,'tab:blue',linewidth=2.0)

    plt.tick_params(axis='both', which='major', labelsize=10)

    plt.xticks(np.arange(0, np.amax(minutes) + cycletime, 60))
    plt.xlim([0,np.amax(minutes) + cycletime])
    plt.xlabel('Minutes into cycle period', fontsize=14)
    plt.ylim([-5,ymax])
    plt.grid(True)
    plt.ylabel('RMSD [%s]' % unit, fontsize=14)

    #plt.legend(loc='upper right',  prop={'size':9.0})
    x0,x1 = ax1.get_xlim()
    y0,y1 = ax1.get_ylim()
    #ax1.set_aspect((x1-x0)/(y1-y0))
    ax1.set_aspect(6.)
    plt.tight_layout()
    obtype = obfile[0:-3]
    plt.title(obtype)
    filename = f'sawtooth_{obtype}.png'
    plt.savefig(filename,bbox_inches='tight',dpi=200,format='png') # Saves the figure with small margins
    plt.close()
