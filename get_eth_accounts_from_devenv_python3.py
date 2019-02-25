#!/usr/local/bin/python3
import subprocess, os, re, os.path, json

localDataDir = '.lpdata'
rHN = re.compile('.*HostName (.*)')
rPort = re.compile('.*Port (.*)')
rIF = re.compile('.*IdentityFile (.*)')
def getaddr(dirname):
    fdn = '.lpdata/'+dirname+'/keystore'
    for fn in os.listdir(fdn):
        f = open(fdn + '/' + fn, 'r')
        ko = json.loads(f.read())
        return ko['address']
def get_contract(sshcmds):
    cmd = "cd /home/vagrant/src/protocol && truffle networks | awk '/54321/{f=1;next} /TokenPools/{f=0} f' | grep Controller | cut -d':' -f2 | tr -cd '[:alnum:]'"
    contr = subprocess.check_output(sshcmds + [cmd])
    return contr

def mkdir(d):
    try:
        os.mkdir(d)
    except:
        pass

def main():
    cfg = subprocess.check_output(['vagrant', 'ssh-config'])
    cfg = cfg.decode("utf-8") 
    cfg = cfg.split('\n')
    host = ''
    port = ''
    key = ''
    for l in cfg:
        mr = rHN.match(l)
        if mr:
            host = mr.group(1)
        mr = rPort.match(l)
        if mr:
            port = mr.group(1)
        mr = rIF.match(l)
        if mr:
            key = mr.group(1)
    print('got from config: host: ' + host + 'port: ' + port + 'key: ' + key)
    sshcmds = ['ssh', '-p', port, '-i', key, 'vagrant@'+host]
    contr = get_contract(sshcmds)
    contr = str(contr)
    print('contract address: ' + contr)
    dirs = subprocess.check_output(sshcmds + ['ls /home/vagrant/.lpdata'])
    dirs = dirs.decode("utf-8") 
    dirs = dirs.split('\n')
    mkdir(localDataDir)
    for dirname in dirs:
        isTrans = 'trans' in dirname
        ksdn = '.lpdata/' + dirname + ''
        mkdir(ksdn)
        if 'broad' in dirname or isTrans:
            try:
                args = ['scp', '-r', '-P', port, '-i', key,
                    'vagrant@'+host+':/home/vagrant/.lpdata/' + dirname + '/keystore',
                    ksdn]
                print('running:')
                print(' '.join(args))
                subprocess.check_call(args)
            except Exception as e:
                print(e)
            addr = getaddr(dirname)

            rf = '#!/bin/bash\n' + \
                '$HOME/go/src/github.com/livepeer/go-livepeer/livepeer -v 99 -controllerAddr ' + contr + ' -datadir ./' + localDataDir + '/' + \
                dirname + ' -ethAcctAddr ' + addr + \
                ' -ethUrl ws://localhost:8546 -ethPassword pass -monitor=false -currentManifest=true '
            if not isTrans:
                rf += ' '
            else:
                rf += ' -initializeRound=true -serviceAddr 127.0.0.1:8936 -httpAddr 127.0.0.1:8936 ' +\
                    ' -cliAddr 127.0.0.1:7936 -ipfsPath ./' + localDataDir + '/' + dirname + '/trans ' +\
                    ' -transcoder'

            print(rf)
            rfn = 'run_' + dirname + '.sh'
            f = open(rfn, 'w')
            f.write(rf)
            f.close()
            os.chmod(rfn, 755)


if __name__ == '__main__':
    print('''
    This script copies eth keys for broadcaster and for transcoder from inside vagrant VM to host machine and creates shell scripts to
    run broadcaster and transcoder on host machine using this keys (and connection to private eth tests net inside VM).
''')
    main()
