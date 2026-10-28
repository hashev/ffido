#!/usr/bin/env python3
"""Build isolated image QA receiver and exercise a selected Android emulator."""
import argparse, hashlib, json, os, pathlib, re, subprocess, time, zipfile
import xml.etree.ElementTree as ET
ROOT=pathlib.Path(__file__).resolve().parents[2]

def run(*args, **kwargs):
    return subprocess.check_output(list(map(str,args)),text=True,**kwargs).strip()

def build_receiver(sdk, java, directory):
    tools=max((sdk/'build-tools').glob('[0-9]*'),key=lambda p:tuple(int(v) for v in p.name.split('.') if v.isdigit()))
    jar=sdk/'platforms/android-35/android.jar'
    source=ROOT/'scripts/media/qa_receiver'
    classes=directory/'classes';classes.mkdir(parents=True,exist_ok=True)
    dex=directory/'dex';dex.mkdir(exist_ok=True)
    run(java/'javac','--release','17','-classpath',jar,'-d',classes,source/'ReceiverActivity.java')
    env={**os.environ,'JAVA_HOME':str(java.parent)}
    run(tools/'d8','--lib',jar,'--min-api','24','--output',dex,*classes.rglob('*.class'),env=env)
    unsigned=directory/'receiver-unsigned.apk'
    run(tools/'aapt','package','-f','-M',source/'AndroidManifest.xml','-I',jar,'-F',unsigned)
    with zipfile.ZipFile(unsigned,'a') as archive:archive.write(dex/'classes.dex','classes.dex')
    key=directory/'qa.jks'
    if not key.exists():run(java/'keytool','-genkeypair','-keystore',key,'-alias','qa','-keyalg','RSA','-validity','2','-dname','CN=FFIDO image QA','-storepass','image-qa-only','-keypass','image-qa-only',stderr=subprocess.DEVNULL)
    apk=directory/'receiver.apk'
    run(tools/'apksigner','sign','--ks',key,'--ks-pass','pass:image-qa-only','--out',apk,unsigned,env=env)
    return apk

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk',type=pathlib.Path,default=pathlib.Path.home()/'Library/Android/sdk')
    parser.add_argument('--java',type=pathlib.Path,default=pathlib.Path('/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home/bin'))
    parser.add_argument('--directory',type=pathlib.Path,default=ROOT/'build/image-qa')
    parser.add_argument('--receiver',type=pathlib.Path)
    parser.add_argument('--serial');parser.add_argument('--apk',type=pathlib.Path)
    args=parser.parse_args();args.directory.mkdir(parents=True,exist_ok=True)
    receiver=args.receiver or build_receiver(args.sdk,args.java,args.directory)
    if not args.serial:print(receiver);return
    adb=args.sdk/'platform-tools/adb'
    def device(*words):return run(adb,'-s',args.serial,*words)
    def shell(*words):return device('shell',*words)
    density=int(re.findall(r'\d+',shell('wm','density'))[-1])/160
    def ui():
        path='/data/local/tmp/ffido-image-qa.xml'
        shell('rm','-f',path)
        shell('uiautomator','dump',path)
        return shell('cat',path)
    def tap(label):
        for _ in range(15):
            xml=ui()
            for node in ET.fromstring(xml).iter('node'):
                if label in [node.get('text','').strip(),node.get('content-desc','').strip()]:
                    x1,y1,x2,y2=map(int,re.findall(r'\d+',node.attrib['bounds']))
                    shell('input','tap',str(x1+round(10*density) if label.startswith('https://') else (x1+x2)//2),str(y1+round(10*density) if label.startswith('https://') else (y1+y2)//2));time.sleep(1);return
            time.sleep(.5)
        raise RuntimeError('UI not found: '+label+'\n'+xml)
    device('install','-r',receiver)
    if args.apk:device('install','-r',args.apk)
    shell('pm','clear','org.ffido.imageqa')
    shell('am','force-stop','io.github.hashev.ffido')
    api=int(shell('getprop','ro.build.version.sdk'))
    # Old API 24/25 toybox touch rejects fixture timestamps with EOVERFLOW.
    # The same production cleanup is exercised with real files on API 35.
    ttl=api>=26
    if ttl:
        shell('run-as','io.github.hashev.ffido','mkdir','-p','cache/image-share/expired')
        shell('run-as','io.github.hashev.ffido','touch','cache/image-share/expired/old.png')
        shell('run-as','io.github.hashev.ffido','touch','-d','2000-01-01T00:00:00','cache/image-share/expired')
    if api>=31:
        shell('pm','set-app-links','--package','org.ffido.imageqa','2','all')
        shell('pm','set-app-links-user-selection','--user','0','--package','org.ffido.imageqa','true','ffido-media-qa.invalid')
    else:shell('pm','set-app-link','org.ffido.imageqa','always')
    association=shell('cmd','package','resolve-activity','--brief','-a','android.intent.action.VIEW','-c','android.intent.category.DEFAULT','-c','android.intent.category.BROWSABLE','-d','https://ffido-media-qa.invalid/image.png')
    assert 'org.ffido.imageqa' in association,association
    shell('am','start','-f','0x14000000','-n','io.github.hashev.ffido/.MainActivity');time.sleep(3)
    if ttl:
        remaining=device('exec-out','run-as','io.github.hashev.ffido','ls','cache/image-share')
        assert 'expired' not in remaining.splitlines(),'TTL cleanup did not remove the expired directory'
    # Browser launch must not hit the receiver's host-specific VIEW handler.
    tap('https://ffido-media-qa.invalid/image.png');time.sleep(2)
    foreground=shell('dumpsys','activity','activities')
    resumed='\n'.join(line for line in foreground.splitlines() if 'ResumedActivity' in line or 'mFocusedActivity' in line)
    if 'imageqa' in resumed or 'ffido/.MainActivity' in resumed:raise RuntimeError('Expected external browser: '+resumed)
    shell('am','start','-f','0x14000000','-n','io.github.hashev.ffido/.MainActivity');time.sleep(1)
    import base64
    expected=hashlib.sha256(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==')).hexdigest()
    reports=[]
    for i in range(2):
        if i==0:tap('Открыть изображение на весь экран')
        tap('Поделиться изображением');tap('FFIDO image QA receiver');time.sleep(1)
        report=json.loads(device('exec-out','run-as','org.ffido.imageqa','cat','files/result.json'))
        assert report['sha256']==expected and report['mime']=='image/png' and report['intentMime']=='image/png',report
        assert report['uri'].startswith('content://io.github.hashev.ffido.images/') and not report['writable'] and not report['writeGrant'],report
        if i==1:
            assert report.get('previousSha256')==expected,report
            old_path=reports[0]['uri'].split('/images/',1)[1]
            assert device('exec-out','run-as','io.github.hashev.ffido','ls','cache/image-share/'+old_path).endswith(old_path.split('/')[-1])
        reports.append(report)
        shell('am','start','-f','0x14000000','-n','io.github.hashev.ffido/.MainActivity');time.sleep(1)
    tap('Поделиться изображением');shell('input','keyevent','4');time.sleep(1)
    assert 'Файл передан системному диалогу' not in ui(),'Cancel reported as success'
    tap('Закрыть изображение');assert 'https://ffido-media-qa.invalid/image.png' in ui()
    result={'serial':args.serial,'api':shell('getprop','ro.build.version.sdk'),'browser':resumed,'association':association,'receiver':reports,'cancel':True,'back':True,'ttlCleanup':ttl,'previousSourceExists':True}
    path=args.directory/(args.serial+'.json');path.write_text(json.dumps(result,indent=2)+'\n');print('PASS '+str(path))
if __name__=='__main__':main()
