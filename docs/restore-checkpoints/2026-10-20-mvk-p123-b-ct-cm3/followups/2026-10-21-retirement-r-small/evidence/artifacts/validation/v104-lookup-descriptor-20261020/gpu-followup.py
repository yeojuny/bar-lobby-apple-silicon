from pathlib import Path
import json,subprocess,os,re,shlex
R=Path(__file__).resolve().parents[3];V=Path(__file__).resolve().parent/'gpu-validation';n=(R/'build/metal4-mvk-20261002/build.ninja').read_text();block=n[n.index('build MoltenVK/CMakeFiles/MoltenVK.dir/MoltenVK/Commands/MVKCmdDraw.mm.o:'):];extra=shlex.split(re.search(r'  INCLUDES = (.*)',block).group(1))+shlex.split(re.search(r'  DEFINES = (.*)',block).group(1));d=json.loads((V/'prepared-build.json').read_text());args=d['arguments']+extra
p=subprocess.run(args,capture_output=True,text=True,timeout=60);(V/'prepared-build-fixed.stderr').write_text(p.stderr);(V/'prepared-build-fixed.json').write_text(json.dumps(dict(arguments=args,exitCode=p.returncode),indent=2));assert p.returncode==0,p.stderr[-2000:]
env=dict(os.environ,MTL_DEBUG_LAYER='1',MVK_CONFIG_METAL4_STATS='0',MVK_CONFIG_METAL4_QUEUE_STATS='0',MVK_CONFIG_BACKEND_COST_STATS='1',MVK_CONFIG_BACKEND_TIMELINE='0',MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS='1',MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS='0',MVK_CONFIG_LOG_LEVEL='3')
exe=V/'prepared-selected'
for label,cmd in [('prepared-m4',[str(exe)]),('template-m4',[str(exe),'m4']),('template-m3',[str(exe),'m3'])]:
 p=subprocess.run(cmd,capture_output=True,text=True,env=env,timeout=60);(V/(label+'.stdout')).write_text(p.stdout);(V/(label+'.stderr')).write_text(p.stderr);(V/(label+'.json')).write_text(json.dumps(dict(arguments=cmd,exitCode=p.returncode),indent=2));print(label,p.returncode,p.stdout[:1000],flush=True);assert p.returncode==0,p.stderr[-2000:]
