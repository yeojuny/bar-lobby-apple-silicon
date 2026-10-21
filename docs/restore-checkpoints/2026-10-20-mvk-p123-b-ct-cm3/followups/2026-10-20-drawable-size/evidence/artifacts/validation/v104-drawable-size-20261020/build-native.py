from pathlib import Path
import hashlib, json, os, subprocess, time

ROOT=Path(__file__).resolve().parents[3]
OUT=Path(__file__).resolve().parent
before=json.loads((OUT/'before.json').read_text())
pins=json.loads((OUT/'review-pins.json').read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for relative,digest in pins.items(): assert sha(ROOT/relative)==digest,relative
results=[]
for lane,info in before['lanes'].items():
    build=ROOT/info['build']
    inputs=subprocess.check_output(['/opt/homebrew/bin/ninja','-C',str(build),'-t','inputs','engine-legacy'],text=True)
    source_pins={}
    for relative in inputs.splitlines():
        path=Path(relative)
        if not path.is_absolute():path=build/path
        if path.is_file() and path.suffix in {'.h','.hpp','.cpp','.cc','.c','.mm','.m','.S'} and path.resolve().is_relative_to(ROOT):
            source_pins[str(path.resolve().relative_to(ROOT))]=sha(path)
    (OUT/(lane+'-build-input-pins.json')).write_text(json.dumps(source_pins,indent=2)+'\n')
    args=['/opt/homebrew/bin/ninja','-C',str(build),'-j','4','engine-legacy']
    start=time.monotonic()
    with (OUT/(lane+'-incremental-build.log')).open('x') as log:
        result=subprocess.run(args,stdout=log,stderr=subprocess.STDOUT)
    row={'lane':lane,'arguments':args,'exitCode':result.returncode,'seconds':round(time.monotonic()-start,3),'sourceInputPins':len(source_pins)}
    for relative,digest in source_pins.items():assert sha(ROOT/relative)==digest,relative
    if result.returncode==0:
        raw=build/'spring';row['rawPath']=str(raw);row['rawSHA256']=sha(raw)
        row['priorRawBackup']=info['rawBackup'];assert sha(ROOT/info['rawBackup'])==info['rawBeforeSHA256']
        for name in ['CMakeCache.txt','build.ninja']:
            relative=info['build']+'/'+name
            assert sha(ROOT/relative)==before['selectedFiles'][relative],relative
        private=OUT/('version-'+lane);private.mkdir()
        env=os.environ.copy();env.update(HOME=str(private),SPRING_WRITEDIR=str(private))
        for flag in ['--version','--sync-version']:
            check=subprocess.run([str(raw),flag],env=env,cwd=private,capture_output=True,text=True,timeout=15)
            (private/(flag[2:]+'.log')).write_text(check.stdout+check.stderr)
            assert check.returncode==0,(lane,flag,check.stderr)
            row[flag[2:]]=check.stdout.strip()
    results.append(row)
    (OUT/'native-build.json').write_text(json.dumps(results,indent=2)+'\n')
    print(json.dumps(row),flush=True)
    if result.returncode:raise SystemExit(result.returncode)
for relative,digest in pins.items(): assert sha(ROOT/relative)==digest,relative
