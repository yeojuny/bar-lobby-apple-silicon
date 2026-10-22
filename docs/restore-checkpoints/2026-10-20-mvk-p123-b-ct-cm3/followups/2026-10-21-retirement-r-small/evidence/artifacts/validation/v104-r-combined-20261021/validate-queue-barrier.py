from pathlib import Path
import subprocess,json,os
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent;B=R/'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK';V=O/'queue-barrier';V.mkdir(exist_ok=False)
def extract(text,sig):
 a=text.index(sig);p=text.index('{',a);d=1;e=p+1
 while d:d+=(text[e]=='{')-(text[e]=='}');e+=1
 return text[a:e]
s=(B/'Commands/MVKCommandBuffer.mm').read_text();emission=extract(s,'void MVKCommandEncoder::encodeMetal4PendingDependencies(');barrier=extract(s,'void MVKCommandEncoder::setMetal4Barrier(');local=extract(barrier,'if (_mtl4ComputeEncoder) {')
body=emission+'\n\nvoid MVKCommandEncoder::computeBarrier(MTLStages sourceStages, MTLStages destinationStages, bool memoryDependency) {\nconst MTL4VisibilityOptions visibility = memoryDependency ? MTL4VisibilityOptionDevice | MTL4VisibilityOptionResourceAlias : MTL4VisibilityOptionNone;\n_metal4Dependencies.add(sourceStages,destinationStages,memoryDependency);\n'+local+'\n}\n'
inc=V/'queue-barrier-body.inc';inc.write_text(body);exe=V/'queue-barrier-cpu';args=['/usr/bin/xcrun','clang++','-std=c++17','-O1','-g','-fno-objc-arc','-fblocks','-mmacosx-version-min=27.0','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','Metal','-I'+str(B/'Commands'),f'-DMVK_QUEUE_BARRIER_BODY="{inc}"',str(R/'tools/tests/metal4-queue-barrier-reuse-cpu.mm'),'-o',str(exe)]
for label,cmd in [('build',args),('run',[str(exe)])]:
 p=subprocess.run(cmd,capture_output=True,text=True,env=dict(os.environ,ASAN_OPTIONS='detect_leaks=0:halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1'),timeout=120);(V/(label+'.log')).write_text(p.stdout+p.stderr);(V/(label+'.json')).write_text(json.dumps(dict(arguments=cmd,exitCode=p.returncode),indent=2)+'\n');print(label,p.returncode,p.stdout,flush=True);assert p.returncode==0,p.stderr[-1500:]
(V/'completion.json').write_text(json.dumps(dict(status='passed',actualProductionEmissionAndComputeBlock=True,GPUExecuted=False),indent=2)+'\n')
