import sys
import subprocess as sp
import os
import time
import shutil
import threading


def run_ldm2netcdf(radar, startdate, inloc, outloc, prefix):

    '''Runs ldm2netcdf input: radar site, input and output locations. Returns process code and writes out log file called ldm2netcdf.log'''
    global logdir

    logfile = open(logdir+'/ldm2netcdf'+startdate+'.'+radar+'.log','w')

    cmd = 'ldm2netcdf  -s ' + radar + ' -i '+ inloc+'/'+radar +' -o ' + outloc + ' -addLower  -a -1 -L -p '+ prefix #+' --verbose unanticipated'

    p = sp.Popen(cmd,shell=True,stdout=logfile,stderr=sp.STDOUT)
    p.wait()
    logfile.flush()

    logfile.close()

    return p.returncode


def run_makeindex(outloc):

    '''Runs makeindex input: output locations. Returns process code '''

    cmd = 'makeIndex.pl '+ outloc +' code_index.xml'
#    cmd = 'w2makeindex.py '+ outloc +' -xml'
    p = sp.Popen(cmd,shell=True)
    p.wait()
    return p.returncode

def run_replaceindex(outloc,soundingloc):

    '''Runs replaceindex to get NSE and radar on same xml.'''

    cmd = 'replaceIndex -o '+outloc +'/big_index.xml -i "'+outloc+'/code_index.xml '+soundingloc+'/code_index.xml"'
    p = sp.Popen(cmd,shell=True)
    p.wait()
    return p.returncode


def run_dealias2d(radar, startdate, outloc, soundingloc, prefix):

    '''Runs dealias2d input: radar site, output location, and sounding file location. Returns process code and writes out log file called dealias2d.log'''
    global logdir

    logfile = open(logdir+'/dealias2d'+startdate+'.'+radar+'.log','w')

    #cmd = 'dealias2d -R '+ radar + ' -i ' + outloc+'/big_index.xml ' +' -o '+ outloc +' -S SoundingTable -Z ReflectivityQC'
    cmd = 'dealiasVel -R '+ radar + ' -i ' + outloc+'/big_index.xml ' +' -o '+ outloc +' -S SoundingTable -Z ReflectivityQC'

    p = sp.Popen(cmd,shell=True,stdout=logfile,stderr=sp.STDOUT)
    p.wait()
    logfile.flush()

    logfile.close()


    return p.returncode


def run_w2qcnn(radar, startdate, outloc):

    '''Runs qcnn input: radar site, outlocation. Returns process code and writes out log file named qcnn.log'''
    global logdir


    logfile = open(logdir+'/qcnn'+startdate+'.'+radar+'.log','w')

    cmd = 'w2qcnndp -i ' + outloc +'/code_index.xml -o '+ outloc +' -s '+ radar + ' -R 0.25x0.5x460 --verbose=debug'

    p = sp.Popen(cmd,shell=True, stdout=logfile,stderr=sp.STDOUT)
    p.wait()
    logfile.flush()

    logfile.close()


    return p.returncode


def run_w2qcnn2(radar, startdate, outloc):

    '''Runs qcnn input: radar site, outlocation. Returns process code and writes out log file named qcnn.log'''
    global logdir


    logfile = open(logdir+'/qcnn'+startdate+'.'+radar+'.log','w')

    cmd = 'w2qcnn -i ' + outloc +'/code_index.xml -o '+ outloc +' -s '+ radar + ' -R 0.25x0.5x460 -n --verbose=debug' # -M outloc...

    p = sp.Popen(cmd,shell=True, stdout=logfile,stderr=sp.STDOUT)
    p.wait()
    logfile.flush()

    logfile.close()


    return p.returncode



def run_w2circ(radar, startdate, outloc):

    ''' Runs w2circ input: radar site and outlocation. Returnes process code and writes out log file named w2circ.log. '''
    global logdir


    logfile = open(logdir+'/w2circ'+startdate+'.'+radar+'.log','w')

    #cmd = ['w2circ', '-i', outloc+'code_index.xml', '-o', outloc, '-a', '-w', '-c']
    #cmd = 'w2circ -i '+ outloc +'/code_index.xml -o '+ outloc + ' -az -w -C'
    #cmd = 'w2circ -i '+ outloc +'/code_index.xml -o '+ outloc + ' -sr -z "ReflectivityQC" -S -D -t -az -C -w -vmax -L "0:2:0:7.5:AGL 2:5:0:90:AGL" -g "'+radar+' /localdata/terrain/'+radar+'.nc" -b 5 --verbose'
###THIS was the command before 2019
#    cmd = 'w2circ -i '+ outloc +'/code_index.xml -o '+ outloc + ' -sr -z "ReflectivityQC" -D -t -az -w -vmax -L "0:2:0:7.5:AGL 2:5:0:90:AGL" -g "'+radar+' /localdata/terrain/'+radar+'.nc" -b 5 --verbose'
#Command after 01-2019 to include div and total shear
    cmd = 'w2circ -i '+ outloc +'/code_index.xml -o '+ outloc + ' -sr -z "ReflectivityQC" -D -t -az -div -tot -w -vmax -L "0:2:0:7.5:AGL 2:5:0:90:AGL" -g "'+radar+' /work/Thomas.Jones/MRMS/terrain/'+radar+'.nc" -b 5 --verbose'

    p = sp.Popen(cmd, shell=True, stdout=logfile, stderr=sp.STDOUT)
    p.wait()
    logfile.flush()

    logfile.close()


    return p.returncode

def run_w2thresh(radar, startdate, outloc):

    ''' Runs w2circ input: radar site and outlocation. Returnes process code and writes out log file named w2circ.log. '''
    global logdir


    logfile = open(logdir+'/w2thres'+startdate+'.'+radar+'.log','w')

    cmd = 'w2threshold -i '+ outloc +'/code_index.xml -o '+ outloc + ' -R 1 -v 20 -d "Velocity" -t "ReflectivityQC"'


    p = sp.Popen(cmd, shell=True, stdout=logfile, stderr=sp.STDOUT)
    p.wait()
    logfile.flush()

    logfile.close()


    return p.returncode

def run_w2cutRadial(radar, startdate, outloc):

    ''' Runs w2cutradial input: radar site and outlocation. Returnes process code and writes out log file named w2circ.log. '''
    global logdir


    logfile = open(logdir+'/w2cutradial'+startdate+'.'+radar+'.log','w')

    cmd = 'w2cutRadial -i '+ outloc +'/code_index.xml -o '+ outloc + ' -I "Velocity_Threshold" -n 25 -g 150'


    p = sp.Popen(cmd, shell=True, stdout=logfile, stderr=sp.STDOUT)
    p.wait()
    logfile.flush()

    logfile.close()


def run_w2smooth(radar,startdate, outloc):
    logfile = open('w2smooth'+startdate+'.log','w')

    cmd = 'w2smooth -i '+outloc+'/code_index.xml -o '+outloc+' -T "ReflectivityQC Velocity_Threshold_cut" -k cressman:3:0.33 -R -C 0.05  --verbose'

    p = sp.Popen(cmd,shell=True, stdout=logfile,stderr=sp.STDOUT)
    p.wait()
    logfile.flush()

    logfile.close()

    return p.returncode

def run_w2cropconv(radar,startdate,outloc, spacing):
    logfile = open('w2cropconv'+startdate+'.log','w')

    cmd = 'w2cropconv -i '+outloc+'/code_index.xml -o '+outloc+' -t "39.25 -102.95" -b "32.60 -94.58" -s "'+spacing+' '+spacing+'" -S'+radar+' -g 0.25 -I "ReflectivityQC_smoothed Velocity_Threshold_cut_smoothed" --verbose'

    p = sp.Popen(cmd,shell=True, stdout=logfile,stderr=sp.STDOUT)
    p.wait()
    logfile.flush()

    logfile.close()

    return p.returncode


def run_w2pointcloud(radar,startdate, outloc):
    logfile = open('w2pointcloud'+startdate+'.log','w')

    cmd = 'w2pointcloud -i '+outloc+'/code_index.xml -o '+outloc+'/point3kmAvg -I "Velocity_Threshold_cut" -C 2 -grid "nw(39.3,-103.85) se(32.36,-95.30) s(0.03,0.03)" --verbose'
    p = sp.Popen(cmd,shell=True, stdout=logfile,stderr=sp.STDOUT)
    p.wait()
    logfile.flush()
#    cmd = 'w2pointcloud -i '+outloc+'/code_index.xml -o '+outloc+'/point5kmCres -I "Velocity_Threshold_cut" -C 1 -grid "nw(39.3,-103.85) se(32.36,-95.30) s(0.05,0.05)" --verbose'
#    p = sp.Popen(cmd,shell=True, stdout=logfile,stderr=sp.STDOUT)
#    p.wait()
#    logfile.flush()
#    cmd = 'w2pointcloud -i '+outloc+'/code_index.xml -o '+outloc+'/point1kmCres -I "Velocity_Threshold_cut" -C 1 -grid "nw(39.3,-103.85) se(32.36,-95.30) s(0.01,0.01)" --verbose'
#    p = sp.Popen(cmd,shell=True, stdout=logfile,stderr=sp.STDOUT)
#    p.wait()
#    logfile.flush()

    logfile.close()

    return p.returncode


def run_w2accumulator(radar, startdate, outloc):

    ''' Runs w2accumulator. Input: radar site and outlocation. Returnes process code and write out log file named w2accumulator.log '''
    global logdir


    logfile = open(logdir+'/w2accumulator'+startdate+'.'+radar+'.log','w')

    #cmd = ['w2accumulator', '-i', outloc+'code_index.xml', '-o', outloc, '-g AzShear', '-O RotationTrack', '-m RotationTrack', '-C 1', '-t', '"15 30 60"']
    cmd = 'w2accumulator -i '+ outloc + '/code_index.xml -o '+ outloc + ' -g AzShear -O RotationTrack -m RotationTrack -C 1 -t "15 30 60"'

    p = sp.Popen(cmd, shell=True, stdout=logfile, stderr=sp.STDOUT)
    p.wait()
    logfile.flush()

    logfile.close()


    return p.returncode



def runwdssii(radar,startdate,inloc,outloc,soundingloc,prefix):

#    os.environ["LD_LIBRARY_PATH"] ="/home/ec2-user/WDSS2/lib"
#    os.environ["W2_CONFIG_LOCATION"]="/home/ec2-user/WDSS2/w2config"
#    os.environ["UDUNITS_PATH"] = "/home/ec2-user/WDSS2/etc/udunits.dat"
#    os.environ["PATH"] ="/home/ec2-user/WDSS2/bin:/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin:/opt/aws/bin:/home/ec2-user/.local/bin:/home/ec2-user/bin"
#    os.environ["RMTPORT"] = "50000"


    ## RUN LDM TO NETDCF CONVERSION
    ldmstart = time.time()
    ldm2netcdfCode = run_ldm2netcdf(radar, startdate, inloc, outloc, prefix)
    if ldm2netcdfCode:
        print('ERROR')
        sys.exit('1 ldm2netcdf failed')
    ldmfinish = time.time()
    print("ldm time: " +str(ldmfinish-ldmstart)+" "+str(radar) +" \n")

    ## CREATE code_index.xml FILE
    updatecode = run_makeindex(outloc)
    accstart =time.time()

    ## DO QUALITY CONTROL
    qcnnCode = run_w2qcnn(radar, startdate, outloc)
    #qcnnCode = run_w2qcnn2(radar, startdate, outloc)

    if not(qcnnCode == 0 or qcnnCode == 255):
        print('ERROR   '+str(qcnnCode))
        sys.exit('1 qcnn failed')
#
    accfinish =time.time()
#
    print("qcnn time: "+ str(accfinish-accstart) +" "+str(radar)+"\n")
#
    updatecode = run_makeindex(outloc)
    updatecode = run_replaceindex(outloc,soundingloc)

    ## PERFORM DEALIASING
    dealiasstart = time.time()
    dealias2dCode = run_dealias2d(radar, startdate, outloc, soundingloc, prefix)
    if dealias2dCode:
        print( 'ERROR')
        sys.exit('1 dealias failed')
    dealiasfinish = time.time()
#
    print("dealias time: "+ str(dealiasfinish-dealiasstart)+" "+str(radar)+"\n")
    updatecode = run_makeindex(outloc)

    ### RUN CIRC CODE
    circCode = run_w2circ(radar, startdate, outloc)
    if circCode:
        print('ERROR')
        sys.exit('1 w2circ failed')

    updatecode = run_makeindex(outloc)

    #updatecode = run_makeindex(outloc)

    return 0
def main():
    global logdir

    args = sys.argv

    startdate = args[1]
    inloc = args[2]
    outloc = args[3]
    soundingloc = args[4]
    prefix = args[5]
    radars = os.listdir(inloc+'/')
    #radars = ['KMHX','KJGX']
    maxthreads = 30

    logdir = os.path.join(os.path.dirname(outloc), 'logs')
    #shutil.rmtree(logdir)
    if not os.path.exists(logdir):
        os.mkdir(logdir)

    tjobs=[]
    for radar in radars:
        if threading.active_count() <= maxthreads:

            print("Processing "+radar)
            outloc1 = outloc+'/'+radar
            t = threading.Thread(target=runwdssii,name=threading.active_count(),args=(radar,startdate,inloc,outloc1,soundingloc,prefix))
            tjobs.append(t)
            t.start()
            time.sleep(2)
        else:
            while threading.active_count() > maxthreads:
                time.sleep(300)

    while True:
        if threading.activeCount() <= 1: break

        for t in tjobs:
            if t.isAlive() : t.join(10)

    print("Done runwdssii for all radars")
    sys.exit(0)

if __name__ == '__main__':
    global logdir
    main()


