from pathlib import Path
import json,hashlib,shutil,subprocess,time,struct
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent;B=R/'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK';BUILD=R/'build/metal4-mvk-20261002';before=json.loads((O/'before.json').read_text());sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();raw=BUILD/'MoltenVK/libMoltenVK.1.4.3.dylib'
def write(name,d):(O/name).write_text(json.dumps(d,indent=2)+'\n')
def activate(label):
 for rel in before['productFiles']:
  src=O/'source-states'/label/rel;dst=B/rel
  if src.read_bytes()!=dst.read_bytes():shutil.copy2(src,dst)
 # Source mtimes from generated states must trigger the incremental rules.
 for rel in before['productFiles']:(B/rel).touch()
def compile(label):
 start=time.monotonic();args=['/opt/homebrew/bin/ninja','-C',str(BUILD),'-j','4','MoltenVK']
 with (O/(label+'-build.log')).open('x') as log:p=subprocess.run(args,stdout=log,stderr=subprocess.STDOUT)
 result=dict(label=label,arguments=args,exitCode=p.returncode,seconds=time.monotonic()-start,sourcePins={rel:sha(B/rel) for rel in before['productFiles']},diagnostics=False)
 if p.returncode==0:shutil.copy2(raw,O/(label+'-raw-MoltenVK.dylib'));result.update(rawSHA256=sha(raw),rawBytes=raw.stat().st_size)
 write(label+'-build.json',result);assert p.returncode==0,(label,'build failed; inspect bounded log');print(label,'build passed',result['rawSHA256'],flush=True);return result
results=[];error=None
try:
 cache=(BUILD/'CMakeCache.txt').read_text()
 for lang in ['C','CXX','OBJC','OBJCXX']:assert f'CMAKE_{lang}_FLAGS:STRING=-DMVK_ENABLE_CUSTOM_DIAGNOSTICS=0' in cache
 for label in ['C','L','S']:activate(label);results.append(compile(label))
except BaseException as e:error=repr(e)
finally:
 activate('D');restore=compile('D-restored')
 for rel,h in before['sourcePins'].items():assert sha(R/rel)==h,rel
 assert sha(BUILD/'CMakeCache.txt')==before['CMakeCacheSHA256']
 write('restore-D.json',dict(sourcePinsExact=True,cacheExact=True,rawByteExact=sha(raw)==before['rawSHA256'],rawSHA256=sha(raw),build=restore))
if error:raise RuntimeError(error)
def sections(path):
 data=path.read_bytes();assert struct.unpack_from('<I',data)[0]==0xfeedfacf;ncmds=struct.unpack_from('<I',data,16)[0];pos=32;out={}
 for _ in range(ncmds):
  cmd,size=struct.unpack_from('<II',data,pos)
  if cmd==0x19:
   count=struct.unpack_from('<I',data,pos+64)[0]
   for j in range(count):
    p=pos+72+80*j;sect=data[p:p+16].split(b'\0')[0].decode();seg=data[p+16:p+32].split(b'\0')[0].decode();n,offset=struct.unpack_from('<QI',data,p+40);flags=struct.unpack_from('<I',data,p+64)[0]
    if offset and n and (flags&0xff) not in (1,12,18):out[seg+','+sect]=dict(bytes=n,sha256=hashlib.sha256(data[offset:offset+n]).hexdigest())
  pos+=size
 return out
paths={label:O/(label+'-raw-MoltenVK.dylib') for label in ['C','L','S']};paths['D']=O/'D-original-raw-MoltenVK.dylib';paths['priorC']=Path(json.loads((R/'artifacts/validation/v104-lookup-descriptor-20261020/before.json').read_text())['backup']);sec={k:sections(v) for k,v in paths.items()};write('mach-o-sections.json',sec)
eq=[]
for a,b in [('C','priorC'),('S','C'),('L','D')]:
 eq.append(dict(left=a,right=b,rawByteExact=sha(paths[a])==sha(paths[b]),fileBackedSectionsExact=sec[a]==sec[b],differentSections=[k for k in set(sec[a])|set(sec[b]) if sec[a].get(k)!=sec[b].get(k)]))
write('build-comparison.json',dict(status='completed-four-source-state-builds',builds=results,comparisons=eq,restoredD=restore,sourceAndConfigRestored=True));print(json.dumps(eq),flush=True)
