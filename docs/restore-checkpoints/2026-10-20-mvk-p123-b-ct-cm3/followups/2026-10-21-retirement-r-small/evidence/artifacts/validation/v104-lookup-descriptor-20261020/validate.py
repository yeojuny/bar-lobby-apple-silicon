from pathlib import Path
import json,hashlib,subprocess,shlex,re,os,time
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent;B=R/'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK';V=O/'validation';V.mkdir(exist_ok=False)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def run(label,args,env=None,timeout=60):
 t=time.monotonic();p=subprocess.run(args,capture_output=True,text=True,env=env,timeout=timeout);(V/(label+'.log')).write_text(p.stdout+p.stderr);d=dict(arguments=args,exitCode=p.returncode,seconds=time.monotonic()-t,stdout=p.stdout[:4000]);(V/(label+'.json')).write_text(json.dumps(d,indent=2));print(label,p.returncode,p.stdout[:600],flush=True);assert p.returncode==0,(label,p.stderr[-2500:]);return p
n=(R/'build/metal4-mvk-20261002/build.ninja').read_text();block=n[n.index('build MoltenVK/CMakeFiles/MoltenVK.dir/MoltenVK/Commands/MVKCmdDraw.mm.o:'):];incs=shlex.split(re.search(r'  INCLUDES = (.*)',block).group(1));defs=shlex.split(re.search(r'  DEFINES = (.*)',block).group(1));base=['/usr/bin/xcrun','clang++','-std=c++17','-mmacosx-version-min=27.0']+incs
for diag in [0,1]:
 for foundation in [0,1]:
  for rel in ['GPUObjects/MVKMetal4Submission.mm','Commands/MVKCommandEncoderState.mm']:
   args=base+[d for d in defs if not d.startswith('-DMVK_BUILD_METAL4_FOUNDATION=')]+[f'-DMVK_ENABLE_CUSTOM_DIAGNOSTICS={diag}',f'-DMVK_BUILD_METAL4_FOUNDATION={foundation}','-Wno-deprecated-declarations','-Wno-vla-cxx-extension','-fsyntax-only',str(B/rel)]
   run(f'syntax-{diag}-{foundation}-'+Path(rel).stem,args)
exe=V/'allocation-cpu';run('allocation-build',['/usr/bin/xcrun','clang++','-std=c++17','-O1','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer',str(R/'tools/tests/metal4-allocation-lifetime-cpu.cpp'),'-o',str(exe)])
env=dict(os.environ,ASAN_OPTIONS='detect_leaks=0:halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1');run('allocation-run',[str(exe)],env)
# Retained prior fixture uses exact unchanged encoder registration methods and
# executes the current submission source; no fake indirect binder is claimed.
old=R/'artifacts/validation/v104-typed-buffer-callers-20261020/cpu-registration';dst=V/'registration-exact.mm';dst.write_bytes((old/dst.name).read_bytes());receipt=json.loads((old/'receipt.json').read_text());cmd=[x.replace(str(old),str(V)) for x in receipt['compileCommand']];run('registration-build',cmd);run('registration-run',[str(V/'registration-exact')],env)
# Existing production collector/serializer with ON and OFF compile modes.
for diag in [0,1]:
 exe=V/f'cost-cpu-{diag}'
 args=['/usr/bin/xcrun','clang++','-std=c++17','-O1','-g','-fno-objc-arc','-fblocks','-mmacosx-version-min=27.0',f'-DMVK_ENABLE_CUSTOM_DIAGNOSTICS={diag}','-framework','Foundation','-framework','Metal','-I'+str(B/'GPUObjects'),'-I'+str(B/'Commands'),str(R/'tools/tests/metal4-r44-backend-cost-cpu.mm'),str(B/'GPUObjects/MVKMetal4Submission.mm'),str(B/'Commands/MVKMetal4ArgumentTable.mm'),str(B/'GPUObjects/MVKBackendTimeline.cpp'),'-o',str(exe)]
 run(f'cost-build-{diag}',args)
 env=dict(os.environ,MVK_CONFIG_METAL4_STATS='0',MVK_CONFIG_METAL4_QUEUE_STATS='0',MVK_CONFIG_BACKEND_TIMELINE='0',MVK_CONFIG_BACKEND_COST_STATS='0');run(f'cost-off-{diag}',[str(exe),'--off-flags-only'],env)
 if diag:
  env['MVK_CONFIG_BACKEND_COST_STATS']='1';run('cost-on',[str(exe)],env)
run('release-incremental-build',['/opt/homebrew/bin/ninja','-C',str(R/'build/metal4-mvk-20261002'),'-j','4','MoltenVK'],timeout=300)
(O/'validation-complete.json').write_text(json.dumps(dict(rawSHA256=sha(R/'build/metal4-mvk-20261002/MoltenVK/libMoltenVK.1.4.3.dylib'),diagnostics=False),indent=2))
