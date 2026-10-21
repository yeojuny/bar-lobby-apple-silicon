#!/usr/bin/env python3
"""Scoped benchmark guard: saver idleTime=0, owned awake assertion, exact restore.

No game launch, synthetic input, foreground activation or permanent preference.
Only --smoke performs a two-second reversible OS check. Later hosts must own the
context across their entire authorized run and call check() periodically.
"""
import contextlib,json,os,plistlib,signal,subprocess,time
from pathlib import Path

DOMAIN='com.apple.screensaver'
def command(args):return subprocess.run(args,text=True,capture_output=True,timeout=3)
def idle():
    r=command(['/usr/bin/defaults','-currentHost','read',DOMAIN,'idleTime'])
    if r.returncode:
        if 'does not exist' not in r.stderr:raise RuntimeError('Cannot read saver idle preference')
        return None
    return int(r.stdout.strip())
def set_idle(value):
    args=['/usr/bin/defaults','-currentHost']+(['delete',DOMAIN,'idleTime'] if value is None else ['write',DOMAIN,'idleTime','-int',str(value)])
    r=command(args)
    if r.returncode:raise RuntimeError('Cannot update saver idle preference')
    if idle()!=value:raise RuntimeError('Saver idle preference readback mismatch')
def power():
    r=command(['/usr/bin/osascript','-l','JavaScript','-e','ObjC.import("Foundation");const p=$.NSProcessInfo.processInfo;JSON.stringify({lowPower:Boolean(p.isLowPowerModeEnabled),thermal:Number(p.thermalState)});'])
    if r.returncode:raise RuntimeError('Power mode unavailable')
    return json.loads(r.stdout)
def desktop():
    # Human explicitly permits hidden rendering while the console is locked.
    # Observe the actual state without unlocking or activating any application.
    r=command(['/usr/sbin/ioreg','-a','-n','Root','-d1'])
    if r.returncode:raise RuntimeError('Console observation unavailable')
    roots=plistlib.loads(r.stdout.encode())
    root=roots if isinstance(roots,dict) else roots[0] if isinstance(roots,list) and len(roots)==1 else None
    if not isinstance(root,dict):raise RuntimeError('Console observation format unavailable')
    return {'consoleLocked':root.get('IOConsoleLocked'),'lockAllowedByHuman':True,'unlockAttempted':False}

def check():
    if idle()!=0:raise RuntimeError('Automatic saver suppression changed')
    rows=command(['/bin/ps','-axo','comm=']).stdout.splitlines()
    return {'idleTime':0,'screenSaverEngineObserved':any(Path(v.strip()).name=='ScreenSaverEngine' for v in rows),'power':power(),'desktop':desktop()}
@contextlib.contextmanager
def guard(journal):
    journal=Path(journal);assert journal.is_absolute() and not journal.exists()
    original=idle();before=power();initialDesktop=desktop();owner=None;record={'ownerPID':os.getpid(),'beforeIdleTime':original,'powerBefore':before,'desktopBefore':initialDesktop,'newGame':False}
    # Journal first: recover only the recorded key if this helper is interrupted.
    journal.write_text(json.dumps(record,indent=2)+'\n')
    previous={}
    def interrupt(signum,frame):raise KeyboardInterrupt('guard interrupted')
    try:
        for sig in [signal.SIGTERM,signal.SIGINT]:previous[sig]=signal.signal(sig,interrupt)
        set_idle(0)
        owner=subprocess.Popen(['/usr/bin/caffeinate','-d','-i','-u','-t','3600','-w',str(os.getpid())],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        time.sleep(.2)
        assertions=command(['/usr/bin/pmset','-g','assertions']).stdout
        if f'pid {owner.pid}(caffeinate)' not in assertions:raise RuntimeError('Owned awake assertion missing')
        record.update(caffeinatePID=owner.pid,assertionsVerified=True,observations=[check()])
        yield record
    finally:
        for sig in previous:signal.signal(sig,signal.SIG_IGN)
        try:
            if owner:
                owner.terminate()
                try:owner.wait(timeout=2)
                except subprocess.TimeoutExpired:owner.kill();owner.wait(timeout=2)
            # Preserve a concurrent human preference change instead of overwriting it.
            current=idle()
            if current==0:set_idle(original)
            elif current!=original:record['concurrentPreferenceChangePreserved']=current
            record.update(afterIdleTime=idle(),powerAfter=power(),restored=idle()==original,
                awakeReleased=owner is None or f'pid {owner.pid}(caffeinate)' not in command(['/usr/bin/pmset','-g','assertions']).stdout)
            if record['powerAfter']['lowPower']!=before['lowPower']:record['powerModeChangedExternally']=True
            journal.write_text(json.dumps(record,indent=2)+'\n')
        finally:
            for sig,handler in previous.items():signal.signal(sig,handler)
if __name__=='__main__':
    import sys
    assert len(sys.argv)==3 and sys.argv[1]=='--smoke'
    with guard(sys.argv[2]) as receipt:time.sleep(1);receipt['observations'].append(check())
    print(json.dumps({'restored':receipt['restored'],'awakeReleased':receipt['awakeReleased'],'lowPowerPreserved':receipt['powerBefore']['lowPower']==receipt['powerAfter']['lowPower'],'GPU':False,'game':False}))
