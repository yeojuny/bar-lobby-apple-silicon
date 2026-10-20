from pathlib import Path
import subprocess, json, re, shlex, os, hashlib
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent
O=O/'common-validation'; O.mkdir(exist_ok=False)
B=R/'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK'
ninja=(R/'build/metal4-mvk-20261002/build.ninja').read_text();block=ninja[ninja.index('build MoltenVK/CMakeFiles/MoltenVK.dir/MoltenVK/Commands/MVKCmdDraw.mm.o:'):]
incs=shlex.split(re.search(r'  INCLUDES = (.*)',block).group(1));defs=shlex.split(re.search(r'  DEFINES = (.*)',block).group(1))
base=['/usr/bin/xcrun','clang++','-std=c++17','-mmacosx-version-min=27.0','-DMVK_ENABLE_CUSTOM_DIAGNOSTICS=0']+incs
rows=[]
for foundation in (0,1):
 for rel in ('GPUObjects/MVKDescriptorSet.mm','Commands/MVKCmdPipeline.mm'):
  args=base+[x for x in defs if not x.startswith('-DMVK_BUILD_METAL4_FOUNDATION=')]+['-DMVK_BUILD_METAL4_FOUNDATION='+str(foundation),'-Wno-deprecated-declarations','-Wno-vla-cxx-extension','-fsyntax-only',str(B/rel)]
  r=subprocess.run(args,capture_output=True,text=True);name=rel.replace('/','-')+'-'+str(foundation)+'.log';(O/name).write_text(r.stdout+r.stderr);rows.append({'file':rel,'foundation':foundation,'arguments':args,'exitCode':r.returncode,'log':name})
  if r.returncode:raise SystemExit(r.returncode)
(O/'syntax.json').write_text(json.dumps(rows,indent=2)+'\n')
probe=O/'layout.mm';probe.write_text('#include "MVKDescriptorSet.h"\nextern "C" { unsigned long long templateSize=sizeof(MVKDescriptorUpdateTemplate); }\n')
before=O.parent/'before/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKDescriptorSet.h'
overlay=O/'header-before-vfs.json';overlay.write_text(json.dumps({'version':0,'roots':[{'type':'file','name':str(B/'GPUObjects/MVKDescriptorSet.h'),'external-contents':str(before)}]}))
sizes={}
for foundation in (0,1):
 sizes[str(foundation)]={}
 for stage in ('before','after'):
  target=O/('layout-'+str(foundation)+'-'+stage+'.ll')
  args=base+[x for x in defs if not x.startswith('-DMVK_BUILD_METAL4_FOUNDATION=')]+['-DMVK_BUILD_METAL4_FOUNDATION='+str(foundation),'-S','-emit-llvm',str(probe),'-o',str(target)]
  if stage=='before':args+=['-ivfsoverlay',str(overlay)]
  r=subprocess.run(args,capture_output=True,text=True);(O/(target.stem+'.log')).write_text(r.stdout+r.stderr)
  if r.returncode:raise SystemExit(r.returncode)
  sizes[str(foundation)][stage]=int(re.search(r'@templateSize = .*?global i64 (\d+)',target.read_text()).group(1))
(O/'object-sizes.json').write_text(json.dumps(sizes,indent=2)+'\n')
source=R/'tools/tests/metal4-prepared-recording-vulkan.mm';lib=R/'build/metal4-mvk-20261002/MoltenVK/libMoltenVK.1.4.3.dylib';exe=O/'prepared-recording-vulkan'
args=base+defs+['-fno-objc-arc','-fblocks','-O2','-g','-Wno-deprecated-declarations','-I'+str(R/'build/run66-moltenvk-src-20260903/External/SPIRV-Headers/include'),'-framework','Foundation',str(source),str(lib),'-Wl,-rpath,'+str(lib.parent),'-o',str(exe)]
r=subprocess.run(args,capture_output=True,text=True);(O/'native-compile.log').write_text(r.stdout+r.stderr)
receipt={'compileArguments':args,'compileExitCode':r.returncode,'librarySHA256':hashlib.sha256(lib.read_bytes()).hexdigest(),'fixtureSHA256':hashlib.sha256(source.read_bytes()).hexdigest(),'backend':'original native suite plus explicitly selected common M3/M4 cases','windowCreated':False,'gameExecuted':False}
if not r.returncode:
 env=os.environ.copy();settings={'MTL_DEBUG_LAYER':'1','MVK_CONFIG_USE_METAL4':'1','MVK_CONFIG_LOG_LEVEL':'2','MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS':'1','MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS':'0'};env.update(settings)
 try:r=subprocess.run([str(exe)],env=env,capture_output=True,text=True,timeout=60)
 except subprocess.TimeoutExpired:raise SystemExit('Native check exceeded existing bounded timeout')
 (O/'native-stdout.json').write_text(r.stdout);(O/'native-stderr.log').write_text(r.stderr);receipt.update(runExitCode=r.returncode,environment=settings)
 if not r.returncode:receipt['result']=json.loads(r.stdout)
if not r.returncode:
 receipt['commonBackends']=[]
 for backend in ('m3','m4'):
  actual=subprocess.run([str(exe),'--template-common-'+backend],env=env,capture_output=True,text=True,timeout=60)
  (O/('template-'+backend+'-stdout.json')).write_text(actual.stdout);(O/('template-'+backend+'-stderr.log')).write_text(actual.stderr)
  row={'backend':backend,'exitCode':actual.returncode}
  if not actual.returncode: row['result']=json.loads(actual.stdout)
  receipt['commonBackends'].append(row)
  if actual.returncode: r=actual;break
(O/'native-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({'syntaxCases':len(rows),'objectSizes':sizes,'nativeCompile':receipt['compileExitCode'],'nativeRun':receipt.get('runExitCode'),'result':receipt.get('result',{}).get('passed')}))
raise SystemExit(r.returncode)
