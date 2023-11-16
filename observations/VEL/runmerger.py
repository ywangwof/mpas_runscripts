import sys
import subprocess as sp
import os
import time
import glob

def run_makeindex(outloc):

    '''Runs makeindex input: output locations. Returns process code '''

    cmd = 'makeIndex.pl '+ outloc +' '+ 'code_index.xml'
    p = sp.Popen(cmd,shell=True)
    p.wait()
    return p.returncode

def run_replaceindex(outloc,codefiles,startdate):

    '''Runs makeindex input: output locations. Returns process code '''
    xmlfiles = ' '.join(codefiles)
    #cmd = 'replaceIndex -i "'+ str(xmlfiles) +' /localdata/newsereprocessed/20151223/processed/fake/code_index.xml /localdata/newsereprocessed/20151223/NSE/code_index.xml" -o ' + outloc+'/biginput.xml'
#    cmd = 'replaceIndex -i "'+ str(xmlfiles) +' /localdata/newsereprocessed/20160509/NSE/code_index.xml" -o ' + outloc+'/biginput.xml'
    #cmd = 'replaceIndex -i "'+ str(xmlfiles) +' /localdata/newsereprocessed/20160508/NSE/code_index.xml" -o ' + outloc+'/biginput.xml'
    #cmd = 'replaceIndex -i "'+ str(xmlfiles) +' /localdata/newsereprocessed/20160516/NSE/code_index.xml" -o ' + outloc+'/biginput.xml'
    #cmd = 'replaceIndex -i "'+ str(xmlfiles) +' /localdata/newsereprocessed/20160524/NSE/code_index.xml" -o ' + outloc+'/biginput.xml'
    #cmd = 'replaceIndex -i "/localdata/newsereprocessed/20170415/processed/FAKE/code_index.xml '+ str(xmlfiles) +'" -o ' + outloc+'/biginput.xml'
    cmd = 'replaceIndex -i "/localdata/newsereprocessed/'+startdate+'/NSE/code_index.xml /localdata/newsereprocessed/'+startdate+'/FAKE/code_index.xml '+ str(xmlfiles) +'" -o ' + outloc+'/biginput.xml'
    print(cmd)
    p = sp.Popen(cmd,shell=True)
    p.wait()
    return p.returncode


def readradarfile(finpath):
    '''Reads csh file for newse'''
    radarlist = []
    fin = open(finpath,'r')
    lines = fin.readlines()
    #lines 7 radar lnie 10-13 corners
    radars = lines[6].strip('\n').split(' ')

    lat_ul = lines[10].strip('\n').split(' ')[-1]

    lat_lr = lines[9].strip('\n').split(' ')[-1]

    lon_ul = lines[11].strip('\n').split(' ')[-1]

    lon_lr = lines[12].strip('\n').split(' ')[-1]

    for i in radars:
        if i[0] == "K":
            radarlist.append(i)
        else:
            continue

    return radarlist, str(round(float(lat_ul)+0.2,2)), str(round(float(lat_lr)-0.2,2)), str(round(float(lon_ul)-0.2,2)), str(round(float(lon_lr)+0.2,2))


def run_w2merger03(outloc,startdate,topgridlatlon,bottomgridlatlon):
    logfile = open('w2merger03'+startdate+'.log','w')
    cmd = 'w2merger -i '+outloc+'/biginput.xml -o '+outloc+'/merged -C 7 -e 300 -t "'+topgridlatlon+' 1" -b "'+bottomgridlatlon+' 0" -s "0.005 0.005 1" -I AzShear_0-2kmAGL -g 10 -R 300 -S "5 10"'   #05012018REPROCESSED
    print(cmd)
    p = sp.Popen(cmd,shell=True, stdout=logfile,stderr=sp.STDOUT)
    p.wait()
    logfile.flush()

    cmd = 'w2merger -i '+outloc+'/biginput.xml -o '+outloc+'/merged -C 7 -e 300 -t "'+topgridlatlon+' 1" -b "'+bottomgridlatlon+' 0" -s "0.005 0.005 1" -I Velocity_Gradient_0-2kmAGL -g 10 -R 300 -S "5 10"'   #05012018REPROCESSED
    print(cmd)
    p = sp.Popen(cmd,shell=True, stdout=logfile,stderr=sp.STDOUT)
    p.wait()
    logfile.flush()
    logfile.close()

    return p.returncode

def run_w2merger36(outloc,startdate,topgridlatlon,bottomgridlatlon):
    logfile = open('w2merger36'+startdate+'.log','w')

    cmd = 'w2merger -i '+outloc+'/biginput.xml -o '+outloc+'/merged -C 7 -e 300 -t "'+topgridlatlon+' 1" -b "'+bottomgridlatlon+' 0" -s "0.005 0.005 1" -I AzShear_2-5kmAGL -g 10 -R 300 -S "5 10"'   #20180501
    print(cmd)
    p = sp.Popen(cmd,shell=True, stdout=logfile,stderr=sp.STDOUT)
    p.wait()
    logfile.flush()

    cmd = 'w2merger -i '+outloc+'/biginput.xml -o '+outloc+'/merged -C 7 -e 300 -t "'+topgridlatlon+' 1" -b "'+bottomgridlatlon+' 0" -s "0.005 0.005 1" -I Velocity_Gradient_2-5kmAGL -g 10 -R 300 -S "5 10"'   #05012018REPROCESSED
    print(cmd)
    p = sp.Popen(cmd,shell=True, stdout=logfile,stderr=sp.STDOUT)
    p.wait()
    logfile.flush()
    logfile.close()

    return p.returncode

def run_w2mergerrefl(outloc,startdate,topgridlatlon,bottomgridlatlon):
    logfile = open(os.path.join(outloc,'w2mergerrefl'+startdate+'.log'),'w')

    # 3 KM REFLECTIVITY
    cmd = 'w2merger -i '+outloc+'/biginput.xml -o '+outloc+'/merged3km -C 7 -e 300 -t "'+topgridlatlon+' 22" -b "'+bottomgridlatlon+' 0.25" -s "0.03 0.03 NMQWD" -I ReflectivityQC -g 8 -R 300 -p 0.05 -T 15 -3'
    print(cmd)
    p = sp.Popen(cmd,shell=True, stdout=logfile,stderr=sp.STDOUT)
    p.wait()
    logfile.flush()

    # 1 KM REFLECTIVITY NOQC
    #cmd = 'w2merger -i '+outloc+'/biginput.xml -o '+outloc+'/merged -C 7 -e 300 -t "'+topgridlatlon+' 22" -b "'+bottomgridlatlon+' 0.25" -s "0.01 0.01 NMQWD" -I Reflectivity -g 8 -R 300 -p 0.05 -T 15 -3'
    #print(cmd)
    #p = sp.Popen(cmd,shell=True, stdout=logfile,stderr=sp.STDOUT)
    #p.wait()

    # 5 KM REFFLECTIVITY
    cmd = 'w2merger -i '+outloc+'/biginput.xml -o '+outloc+'/merged5km -C 7 -e 300 -t "'+topgridlatlon+' 22" -b "'+bottomgridlatlon+' 0.25" -s "0.05 0.05 NMQWD" -I ReflectivityQC -a "Composite HDA Isotherms" -g 8 -R 300 -p 0.05 -T 15'   #0517
    print(cmd)
    p = sp.Popen(cmd,shell=True, stdout=logfile,stderr=sp.STDOUT)
    p.wait()

    # 1 KM ZDR
#    cmd = 'w2merger -i '+outloc+'/biginput.xml -o '+outloc+'/merged -C 7 -e 300 -t "'+topgridlatlon+' 22" -b "'+bottomgridlatlon+' 0.25" -s "0.01 0.01 NMQWD" -I Zdr -g 8 -R 300 -p 0.05 -T 15 -3'   #0517
#    print(cmd)
#    p = sp.Popen(cmd,shell=True, stdout=logfile,stderr=sp.STDOUT)
#    p.wait()

    # 1 KM rhHV
#    cmd = 'w2merger -i '+outloc+'/biginput.xml -o '+outloc+'/merged -C 7 -e 300 -t "'+topgridlatlon+' 22" -b "'+bottomgridlatlon+' 0.25" -s "0.01 0.01 NMQWD" -I RhoHV -g 8 -R 300 -p 0.01 -T 15 -3'   #0517
#    print(cmd)
#    p = sp.Popen(cmd,shell=True, stdout=logfile,stderr=sp.STDOUT)
#    p.wait()

    # 1 KM Spectrum Width
    #cmd = 'w2merger -i '+outloc+'/biginput.xml -o '+outloc+'/merged -C 7 -e 300 -t "'+topgridlatlon+' 22" -b "'+bottomgridlatlon+' 0.25" -s "0.01 0.01 NMQWD" -I SpectrumWidth -g 8 -R 300 -p 0.01 -T 15 -3'   #0517
    #print(cmd)
    #p = sp.Popen(cmd,shell=True, stdout=logfile,stderr=sp.STDOUT)
    #p.wait()

    logfile.close()

    return p.returncode

def run_w2mergervel(outloc,startdate):
    logfile = open('w2mergervel'+startdate+'.log','w')

    cmd = 'w2merger -i '+outloc+'/biginput.xml -o '+outloc+'/mergedTest -C 16 -e 300 -t "39.3 -103.85 11" -b "32.36 -95.30 0.25" -s "0.05 0.05 0.1" -I Velocity_Threshold_cut -3 -0 -g 8 -R 150 -p 0.5 -T 12'  #05162017
    print(cmd)
    p = sp.Popen(cmd,shell=True, stdout=logfile,stderr=sp.STDOUT)
    p.wait()
    logfile.flush()

    logfile.close()
    return p.returncode



def main():

    args = sys.argv
    startdate = args[1]

    #outloc = '/work/christopher.kerr/VR_processed/WDSS/'+startdate
    outloc = args[3]

    #infileloc = '/home/Thomas.Jones/WOFS_grid_radar/'
    #infileloc = '/work/christopher.kerr/Radar/'
    infileloc = args[2]

    radars, lat_ul, lat_lr, lon_ul, lon_lr = readradarfile(os.path.join(infileloc,'radars.'+startdate+'.csh'))
    topgridlatlon = lat_ul+' '+lon_ul
    bottomgridlatlon = lat_lr+' '+lon_lr

    #codefiles = [ '/work/christopher.kerr/VR_processed/WDSS/'+startdate+'/'+i+'/code_index.xml' for i in radars]
    codefiles = [ os.path.join(outloc,radar,'code_index.xml') for radar in radars]

    largecodereturn = run_replaceindex(outloc,codefiles, startdate)

    #w2mergercode = run_w2merger03(outloc,startdate,topgridlatlon,bottomgridlatlon)
    #if not(w2mergercode == 0 or w2mergercode == 255):
    #    print('ERROR   '+str(w2mergercode))
    #    sys.exit('1 merger 0-3 failed')

    #w2mergercode = run_w2merger36(outloc,startdate,topgridlatlon,bottomgridlatlon)
    #if not(w2mergercode == 0 or w2mergercode == 255):
    #    print('ERROR   '+str(w2mergercode))
    #    sys.exit('1 merger 3-6 failed')

    #accfinish =time.time()
    w2mergercode = run_w2mergerrefl(outloc,startdate,topgridlatlon,bottomgridlatlon)
    if not(w2mergercode == 0 or w2mergercode == 255):
        print('ERROR   '+str(w2mergercode))
        sys.exit('1 merger 3-6 failed')

    updatecode = run_makeindex(outloc)

    sys.exit(0)
    return 0

if __name__ == '__main__':
    main()


