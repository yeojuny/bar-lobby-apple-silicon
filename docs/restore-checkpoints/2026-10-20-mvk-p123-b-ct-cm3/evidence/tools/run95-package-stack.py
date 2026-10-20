#!/usr/bin/env python3
"""Package the reviewed Run95 build into a separate APFS clone. Never launch/promote."""
import importlib.util,json,os,re,shutil,struct,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('run95_builder',ROOT/'tools/run95-build-stack.py')
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
manifest,digest,sha,write=builder.manifest,builder.digest,builder.sha,builder.write
STAGE=builder.STAGE;PARENT=builder.PARENT;PREFIX=builder.PREFIX
APP=STAGE/'BAR-run95-stack-candidate.app';TEMP=STAGE/'.BAR-run95-packaging.app'
REL=Path('Contents/Resources/bundled-assets/runtime')
COMPONENTS={'mesa':'mesa-zink','loader':'vulkan-loader','sdl':'sdl3','mvk':'moltenvk-pr2746'}
SYSTEM=('/usr/lib/','/System/Library/')

def run(*args):
 p=subprocess.run(list(map(str,args)),capture_output=True,text=True)
 if p.returncode:raise RuntimeError(str(args)+'\n'+p.stdout+p.stderr)
 return p.stdout

def inside(path,root):
 return path.resolve().is_relative_to(root.resolve())

def macho(p):
 if not p.is_file():return False
 with p.open('rb') as f:return f.read(4) in [b'\xcf\xfa\xed\xfe',b'\xfe\xed\xfa\xcf',b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca']

def signature_prefix(p):
 b=p.read_bytes();assert b[:4]==b'\xcf\xfa\xed\xfe','Expected existing arm64 Mach-O main executable'
 count=struct.unpack_from('<I',b,16)[0];off=32
 for _ in range(count):
  cmd,size=struct.unpack_from('<II',b,off);assert size>=8 and off+size<=len(b)
  if cmd==0x1d:
   dataoff,datasize=struct.unpack_from('<II',b,off+8);assert dataoff+datasize<=len(b)
   return b[:dataoff]
  off+=size
 raise AssertionError('Missing existing code signature')

def dylib_id(p):
 lines=run('/usr/bin/otool','-D',p).splitlines()
 return lines[1].strip() if len(lines)>1 else None

def loads(p):
 ident=dylib_id(p)
 return [s.strip().split(' (',1)[0] for s in run('/usr/bin/otool','-L',p).splitlines()[1:] if s.startswith('\t') and s.strip().split(' (',1)[0]!=ident]

def rpaths(p):
 return re.findall(r'\n\s*cmd LC_RPATH\n\s*cmdsize \d+\n\s*path (.*?) \(offset',run('/usr/bin/otool','-l',p))

def expand(path,loader,executable):
 if path.startswith('@loader_path'):return Path(str(loader.parent)+path[len('@loader_path'):])
 if path.startswith('@executable_path'):return Path(str(executable.parent)+path[len('@executable_path'):])
 if path.startswith('/'):return Path(path)
 raise RuntimeError('Unsupported relative loader path '+path)

def resolve_dependency(dep,loader,exe,search,app):
 if dep.startswith(SYSTEM):return None
 if dep.startswith('@rpath/'):
  suffix=dep[len('@rpath/'):]; candidates=[d/suffix for d in search]
 elif dep.startswith(('@loader_path/','@executable_path/')):candidates=[expand(dep,loader,exe)]
 else:raise RuntimeError('Unrelocated/non-system dependency '+dep+' in '+str(loader))
 for p in candidates:
  if p.is_file():
   if not inside(p,app):raise RuntimeError('Dependency escapes candidate '+str(p))
   if not macho(p):raise RuntimeError('Dependency is not Mach-O '+str(p))
   return p.resolve()
 raise RuntimeError('Unresolved dependency '+dep+' in '+str(loader))

def closure(roots,app):
 edges=[];seen=set()
 def visit(lib,exe,inherited):
  local=[]
  for rp in rpaths(lib):
   d=expand(rp,lib,exe)
   if not inside(d,app):raise RuntimeError('Non-app LC_RPATH '+rp+' in '+str(lib))
   local.append(d)
  search=local+inherited;key=(str(lib.resolve()),str(exe),tuple(map(str,search)))
  if key in seen:return
  # Cycles terminate per executable after each image's first resolved runpath stack.
  imagekey=(str(lib.resolve()),str(exe))
  if imagekey in seen:return
  seen.add(key);seen.add(imagekey)
  for dep in loads(lib):
   target=resolve_dependency(dep,lib,exe,search,app)
   edges.append({'from':str(lib.relative_to(app)),'load':dep,'target':str(target.relative_to(app)) if target else 'system','root':str(exe.relative_to(app))})
   if target:visit(target,exe,search)
 for p in roots:visit(p.resolve(),p.resolve(),[])
 return edges

def check_inputs():
 lock=json.loads((STAGE/'build-lock.json').read_text());built=json.loads((STAGE/'build-receipt.json').read_text())
 assert lock['schema']=='run95-stack-build-v1'
 assert built['schema']=='run95-stack-built-v1' and built['status']=='built-not-packaged'
 assert built['buildDigest']==lock['buildDigest']
 raw={k:v for k,v in lock.items() if k not in ['buildDigest','mvkGitRev','mesaGitSha1']}
 assert digest(raw)==lock['buildDigest'] and lock['mvkGitRev']==lock['buildDigest'][:8] and lock['mesaGitSha1']==lock['buildDigest']
 assert Path(lock['parent']['app'])==PARENT
 assert digest(manifest(PARENT))==lock['parent']['inventorySha256'],'Parent drift'
 assert digest(manifest(ROOT/'BAR.app'))==lock['ordinaryApp']['inventorySha256'],'Ordinary app drift'
 for n,folder in COMPONENTS.items():
  r=built['components'][n]
  assert Path(r['prefix'])==PREFIX/folder
  assert r['sourceDigest']==lock['sourceTrees'][n]['treeDigest']
  assert digest(manifest(PREFIX/folder))==r['installedManifestDigest'],n+' installed drift'
  assert digest(manifest(Path(lock['sourceTrees'][n]['path'])))==r['sourceDigest'],n+' source drift'
 assert sha(lock['recipe']['path'])==lock['recipe']['sha256'],'Build recipe drift'
 return lock,built

def package():
 assert not APP.exists() and not TEMP.exists() and not (STAGE/'package-receipt.json').exists(),'Existing or partial candidate: inspect before retry'
 lock,built=check_inputs();before=manifest(PARENT);ordinary=manifest(ROOT/'BAR.app')
 assert PARENT.stat().st_dev==STAGE.stat().st_dev,'APFS clone must remain on same filesystem'
 run('/bin/cp','-cR',PARENT,TEMP)
 assert manifest(TEMP)==before,'Initial clone changed files'
 rt=TEMP/REL;updated=[];omitted=[]
 for folder in COMPONENTS.values():
  target=rt/folder
  assert inside(target,TEMP) and not target.is_symlink()
  shutil.rmtree(target);run('/bin/cp','-cR',PREFIX/folder,target)
  # The active engine/ICD route loads lib/libvulkan*.dylib. CMake also installs
  # a duplicate SDK framework, which is not part of that route.
  if folder=='vulkan-loader':
   framework=target/'loader/vulkan.framework'
   if framework.is_dir():
    omitted.append({'path':str(framework.relative_to(TEMP)),'reason':'Unused duplicate SDK framework; active dylib route retained','manifestDigest':digest(manifest(framework))})
    shutil.rmtree(framework)
  for p in target.rglob('*'):
   if p.is_symlink():assert inside(p,TEMP) and p.exists(),'Unsafe/broken installed symlink '+str(p)
   elif p.is_file() and macho(p):
    assert p.name.endswith('.dylib'),'Unexpected installed executable '+str(p)
    assert 'arm64' in run('/usr/bin/lipo','-archs',p)
    updated.append(p)
 assert updated
 # Keep the launcher's two known ICD entry paths; use the compiled installation's
 # ICD metadata if available, otherwise retain API metadata and relative route.
 mvk=rt/'moltenvk-pr2746'; assert (mvk/'lib/libMoltenVK.dylib').is_file()
 choices=list(mvk.rglob('*icd*.json'))
 template=json.loads(choices[0].read_text()) if choices else json.loads((PARENT/REL/'moltenvk-pr2746/MoltenVK_icd.json').read_text())
 for p in set(choices+[mvk/'MoltenVK_icd.json',mvk/'etc/vulkan/icd.d/MoltenVK_icd.json']):
  v=json.loads(json.dumps(template));v['ICD']['library_path']=os.path.relpath(mvk/'lib/libMoltenVK.dylib',p.parent)
  assert not v['ICD']['library_path'].startswith('/')
  write(p,v)
 search=[rt/n/'lib' for n in ['sdl3','mesa-zink','vulkan-loader','moltenvk-pr2746','deps','fontconfig','audio'] if (rt/n/'lib').is_dir()]
 relocations=[]
 for p in updated:
  args=['/usr/bin/install_name_tool','-id','@rpath/'+p.name]
  for dep in loads(p):
   if dep.startswith(SYSTEM):continue
   if dep.startswith('/'):
    found={str((d/Path(dep).name).resolve()) for d in search if (d/Path(dep).name).is_file()}
    assert len(found)==1,'Missing/ambiguous bundled dependency '+dep
    replacement='@rpath/'+Path(dep).name;args+=['-change',dep,replacement]
    relocations.append({'library':str(p.relative_to(TEMP)),'old':dep,'new':replacement})
   elif not dep.startswith(('@rpath/','@loader_path/','@executable_path/')):raise RuntimeError('Unsupported dependency '+dep)
  existing=rpaths(p)
  desired=['@loader_path/'+os.path.relpath(d,p.parent) for d in search]
  for rp in existing:
   if rp not in desired:args+=['-delete_rpath',rp]
  for rp in desired:
   if rp not in existing:args+=['-add_rpath',rp]
  run(*args,p)
  run('/usr/bin/codesign','--force','--sign','-',p)
 # A recursive static walk checks actual resolutions, not just basename presence.
 engines=[p for p in (TEMP/'Contents/Resources/bundled-assets/engine').rglob('spring') if p.is_file()]
 assert len(engines)>=2,'Both lane engines required'
 edges=closure(updated+engines,TEMP)
 prov=rt/'provenance/run95';prov.mkdir(parents=True,exist_ok=False)
 for name in ['build-lock.json','build-receipt.json','base-source-ready.json','sdl-audit-ready.json','build-environment-audit.json']:shutil.copy2(STAGE/name,prov/name)
 sdl=prov/'sdl';sdl.mkdir()
 for name in ['proposed-properties.patch','public-built-receipt.json','upstream-properties-receipt.json']:
  shutil.copy2(STAGE/'sdl-audit'/name,sdl/name)
 for name in ['mesa','mvk']:
  dest=prov/name;dest.mkdir()
  shutil.copy2(STAGE/name/'source-integration.json',dest/'source-integration.json')
  for p in (STAGE/name).rglob('*.patch'):
   target=dest/p.relative_to(STAGE/name);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)
 for n in COMPONENTS:
  src=Path(lock['sourceTrees'][n]['path']);dest=prov/'licenses'/n;dest.mkdir(parents=True)
  for filename in ['LICENSE','LICENSE.txt','LICENSE.md','COPYING','LICENSE.Apache-2.0.txt','LICENSE.BSD-3-Clause.txt']:
   if (src/filename).is_file():shutil.copy2(src/filename,dest/filename)
 write(prov/'candidate-status.json',{'status':'signed-isolated-candidate-not-game-validated','buildDigest':lock['buildDigest'],'gameExecuted':False,'promoted':False})
 write(prov/'package-recipe.json',{'path':str(Path(__file__).resolve()),'sha256':sha(__file__)})
 prefix=signature_prefix(PARENT/'Contents/MacOS/BAR')
 run('/usr/bin/codesign','--force','--sign','-','--preserve-metadata=identifier,entitlements,requirements,flags,runtime',TEMP)
 run('/usr/bin/codesign','--verify','--deep','--strict',TEMP)
 assert signature_prefix(TEMP/'Contents/MacOS/BAR')==prefix,'Main executable pre-signature bytes changed'
 after=manifest(TEMP);changes=sorted(k for k in before.keys()|after.keys() if before.get(k)!=after.get(k))
 allowed=[str(REL/n)+'/' for n in COMPONENTS.values()]+[str(REL/'provenance/run95')+'/']
 envelope={'Contents/MacOS/BAR','Contents/_CodeSignature/CodeResources'}
 assert all(k in envelope or any(k.startswith(p) for p in allowed) for k in changes),'Unexpected candidate changes'
 assert before['Contents/Info.plist']==after['Contents/Info.plist']
 engine_hashes={str(p.relative_to(TEMP)):sha(p) for p in engines}
 assert all(before[k]['sha256']==v for k,v in engine_hashes.items())
 assert manifest(PARENT)==before and manifest(ROOT/'BAR.app')==ordinary,'Protected app changed'
 libraries={str(p.relative_to(TEMP)):sha(p) for folder in COMPONENTS.values() for p in (rt/folder).rglob('*.dylib') if p.is_file()}
 assert str(REL/'sdl3/lib/libSDL3.0.dylib') in libraries
 write(STAGE/'candidate-manifest.json',after)
 write(STAGE/'dependency-closure.json',{'schema':'run95-recursive-dyld-static-closure-v1','edges':edges,'limits':['Static dependency resolution, not runtime dyld or GPU acceptance'],'relocations':relocations})
 TEMP.rename(APP)
 receipt={'schema':'run95-stack-package-v1','status':'signed-isolated-candidate-not-game-validated','app':str(APP),'parent':str(PARENT),'buildDigest':lock['buildDigest'],'mvkGitRev':lock['mvkGitRev'],'mesaGitSha1':lock['mesaGitSha1'],'packagedLibraries':libraries,'packagedFiles':{k:v for k,v in after.items() if any(k.startswith(str(REL/folder)+'/') for folder in COMPONENTS.values())},'changes':changes,'mainExecutablePrefixIdentical':True,'engineHashes':engine_hashes,'candidateInventorySha256':digest(after),'parentInventorySha256':digest(before),'protectedOrdinaryAppUnchanged':True,'codesignDeepStrictVerified':True,'recursiveStaticClosureVerified':True,'closureReceiptSha256':sha(STAGE/'dependency-closure.json'),'packageRecipeSha256':sha(__file__),'gameExecuted':False,'promoted':False}
 receipt['omittedInstalledArtifacts']=omitted
 write(STAGE/'package-receipt.json',receipt)
 print(json.dumps({'status':receipt['status'],'app':str(APP),'libraries':len(libraries),'changes':len(changes),'inventory':receipt['candidateInventorySha256']}))

if __name__=='__main__':
 assert sys.argv[1:]==['--package'],'Only explicit --package executes; never launches'
 package()
