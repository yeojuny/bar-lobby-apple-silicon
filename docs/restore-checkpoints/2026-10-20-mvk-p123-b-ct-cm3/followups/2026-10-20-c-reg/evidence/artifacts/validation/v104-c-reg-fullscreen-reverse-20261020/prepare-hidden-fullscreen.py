from pathlib import Path
import json,hashlib,subprocess,os,difflib
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent
source=R/'tools/lib/run94-hidden-window-state.m';original=source.read_text();s=original
s=s.replace('(flags&~SDL_WINDOW_FULLSCREEN)|SDL_WINDOW_HIDDEN|SDL_WINDOW_NOT_FOCUSABLE','flags|SDL_WINDOW_HIDDEN|SDL_WINDOW_NOT_FOCUSABLE')
s=s.replace('if(!(actual&SDL_WINDOW_HIDDEN)||(actual&SDL_WINDOW_FULLSCREEN))hiddenFailure("created-window-flags");','if(!(actual&SDL_WINDOW_HIDDEN)||((actual&SDL_WINDOW_FULLSCREEN)!=(flags&SDL_WINDOW_FULLSCREEN)))hiddenFailure("created-window-flags");')
s=s.replace('static bool blockedFullscreen(SDL_Window *window,bool enabled){\n (void)window;windowAudit("fullscreen-blocked",enabled);return !enabled;\n}', '''static bool hiddenFullscreen(SDL_Window *window,bool enabled){
 if(!(SDL_GetWindowFlags(window)&SDL_WINDOW_HIDDEN))hiddenFailure("fullscreen-requires-hidden");
 bool accepted=SDL_SetWindowFullscreen(window,enabled);
 SDL_WindowFlags actual=SDL_GetWindowFlags(window);
 if(!accepted||!(actual&SDL_WINDOW_HIDDEN)||!!(actual&SDL_WINDOW_FULLSCREEN)!=enabled)hiddenFailure("fullscreen-hidden-flags");
 NSWindow *native=(NSWindow *)SDL_GetPointerProperty(SDL_GetWindowProperties(window),SDL_PROP_WINDOW_COCOA_WINDOW_POINTER,NULL);
 if(native!=nil&&[native isVisible])hiddenFailure("fullscreen-native-window-visible");
 windowAudit(enabled?"fullscreen-enabled-hidden":"fullscreen-disabled-hidden",actual);
 return accepted;
}''').replace('INTERPOSE(blockedFullscreen,SDL_SetWindowFullscreen);','INTERPOSE(hiddenFullscreen,SDL_SetWindowFullscreen);')
assert s!=original and 'fullscreen-blocked' not in s
src=O/'hidden-fullscreen.m';src.write_text(s);(O/'hidden-fullscreen.patch').write_text(''.join(difflib.unified_diff(original.splitlines(True),s.splitlines(True),fromfile=str(source),tofile=str(src))))
app=R/'artifacts/runtime/v104-c-reg-candidate-20261020/BAR.app';runtime=app/'Contents/Resources/bundled-assets/runtime/sdl3';lib=runtime/'lib/libSDL3.0.dylib';inc=runtime/'include'
assert inc.is_dir()
guard=O/'libhidden-fullscreen.dylib'
cmd=['/usr/bin/xcrun','clang','-dynamiclib','-fno-objc-arc','-std=gnu11','-Wall','-Wextra','-Werror','-I'+str(inc),str(src),str(lib),'-framework','AppKit','-o',str(guard)]
r=subprocess.run(cmd,capture_output=True,text=True);(O/'hidden-compile.log').write_text(r.stdout+r.stderr);assert r.returncode==0,r.stderr
subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(guard)],capture_output=True,check=True)
probeSource=R/'tools/tests/run94-hidden-window-probe.c';p=probeSource.read_text().replace('1512,950,SDL_WINDOW_RESIZABLE','1512,982,SDL_WINDOW_RESIZABLE|SDL_WINDOW_FULLSCREEN').replace('assert(!SDL_SetWindowFullscreen(window,true));','assert(SDL_SetWindowFullscreen(window,true));').replace('assert(!(SDL_GetWindowFlags(window)&SDL_WINDOW_FULLSCREEN));','assert(SDL_GetWindowFlags(window)&SDL_WINDOW_FULLSCREEN);').replace('PASS actual SDL dummy window remains hidden after create/show/raise/restore/fullscreen requests','PASS actual SDL accepts fullscreen flag and request while remaining hidden; show/raise/restore blocked')
probe=O/'sdl-hidden-fullscreen-probe.c';probe.write_text(p);exe=O/'sdl-hidden-fullscreen-probe'
cmd2=['/usr/bin/xcrun','clang','-std=c11','-Wall','-Wextra','-Werror','-I'+str(inc),str(probe),str(lib),'-o',str(exe)]
r=subprocess.run(cmd2,capture_output=True,text=True);(O/'probe-compile.log').write_text(r.stdout+r.stderr);assert r.returncode==0,r.stderr
log=O/'sdl-hidden-fullscreen-events.jsonl';log.write_text('');env=os.environ.copy();env.update(SDL_VIDEODRIVER='dummy',SDL_MAC_BACKGROUND_APP='1',BAR_BG_ENGINE_PATH=str(exe),BAR_BG_WINDOW_LOG=str(log),DYLD_INSERT_LIBRARIES=str(guard),DYLD_LIBRARY_PATH=str(lib.parent))
r=subprocess.run([str(exe)],env=env,capture_output=True,text=True,timeout=15);(O/'probe-execution.log').write_text(r.stdout+r.stderr);assert r.returncode==0,r.stderr
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();pin=lambda p:{'path':str(p),'sha256':sha(p)}
receipt={'schema':'c-reg-hidden-fullscreen-preflight-v1','status':'actual-sdl-dummy-hidden-fullscreen-contract-passed','sdlLibrarySha256':sha(lib),'guardSha256':sha(guard),'guardLibrary':str(guard),'originalGuardSource':pin(source),'guardSource':pin(src),'probeSource':pin(probe),'probeBinary':pin(exe),'compileArguments':[cmd,cmd2],'events':pin(log),'stdout':r.stdout,'gameOrGPUExecuted':False,'cocoaGpuRenderingQualified':False,'fullscreenSemantics':'Actual SDL retains fullscreen intent/flags on hidden windows; native display/Space switch is deferred by SDL until shown. Game Fullscreen=1 and safe viewport must be verified separately in real run.'}
(O/'sdl-hidden-preflight.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt))
