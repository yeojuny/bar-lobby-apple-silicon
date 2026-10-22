from pathlib import Path
import hashlib, json, os, re, subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
before = json.loads((OUT / 'before.json').read_text())
basis = ROOT / 'artifacts/validation/fullscreen-transition-fix-20261016/native-cpu/source-extracted-check.txt'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()

def extract(text, signature):
    start = text.index(signature)
    brace = text.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        if text[end] == '{': depth += 1
        if text[end] == '}': depth -= 1
        end += 1
    return text[start:end]

extra = r'''
 // Each new hot-path result is checked against the unchanged full production query.
 auto sameSizes = [](const char* name, SDL_Window* window) {
  auto full=QueryDisplayGeometry(window);unsigned saved=displayQueries;
  auto small=QueryWindowDrawableSize(window);
  checkRect(name,{small.logicalWindowWidth,small.logicalWindowHeight,small.drawableWidth,small.drawableHeight},
                 {full.logicalWindowWidth,full.logicalWindowHeight,full.drawableWidth,full.drawableHeight});
  checkValue((std::string(name)+"-no-display-query").c_str(),displayQueries,saved);
 };
 unsetenv("BAR_NATIVE_COCOA_DRAWABLE_SCALE");
 SDL_Window live={1,1512,982,nativeWindow(notched)};
 layerDrawable={3024,1964};sameSizes("live-layer-size",&live);
 layerDrawable={1890.75,1227.5};sameSizes("fractional-layer-truncation",&live);
 layerDrawable={0,982};sameSizes("incomplete-layer-falls-back",&live);
 layerDrawable={0,0};
 const char* policies[]={"1","2","1.25","native","retina","bad","nan","0","-1","2junk"};
 for(auto policy:policies){setenv("BAR_NATIVE_COCOA_DRAWABLE_SCALE",policy,1);sameSizes((std::string("scale-policy-")+policy).c_str(),&live);}
 unsetenv("BAR_NATIVE_COCOA_DRAWABLE_SCALE");
 checkRect("nil-window-empty-size",[](){auto s=QueryWindowDrawableSize(nullptr);return SDL_Rect{s.logicalWindowWidth,s.logicalWindowHeight,s.drawableWidth,s.drawableHeight};}(),{0,0,0,0});
 live.nativeWindow=nil;sameSizes("missing-native-window-fallback",&live);live.nativeWindow=nativeWindow(notched);
 live.w=0;live.h=0;sameSizes("zero-logical-size",&live);
 live.w=2240;live.h=1260;live.displayIndex=0;sameSizes("resize-and-display-move-live",&live);
 live.w=1512;live.h=982;live.displayIndex=1;layerDrawable={1512,982};sameSizes("fullscreen-size-live",&live);
 live.w=900;live.h=600;layerDrawable={1800,1200};sameSizes("subsequent-resize-live",&live);
 layerDrawable={2700,900};sameSizes("independent-axis-scale",&live);
 CGlobalRendering renderer;renderer.sdlWindow=&live;boundFBO=0;
 unsigned queriesBefore=displayQueries;
 renderer.LoadDefaultFramebufferViewport(-3,5,101,33);
 checkRect("production-viewport-axis-rounding",lastGLRect,{-9,8,303,50});
 renderer.LoadDefaultFramebufferScissor(-3,5,101,33);
 checkRect("production-scissor-axis-rounding",lastGLRect,{-9,8,303,50});
 checkValue("viewport-scissor-no-display-query",displayQueries,queriesBefore);
 live.w=1000;live.h=800;layerDrawable={0,0};setenv("BAR_NATIVE_COCOA_DRAWABLE_SCALE","1.25",1);
 renderer.LoadDefaultFramebufferViewport(-3,-5,101,33);
 checkRect("fractional-fallback-coordinate-rounding",lastGLRect,{-4,-6,126,41});
 boundFBO=9;queriesBefore=displayQueries;
 renderer.LoadDefaultFramebufferViewport(-3,5,101,33);checkRect("offscreen-viewport-unscaled",lastGLRect,{-3,5,101,33});
 renderer.LoadDefaultFramebufferScissor(-3,5,101,33);checkRect("offscreen-scissor-unscaled",lastGLRect,{-3,5,101,33});
 checkValue("offscreen-no-size-query",displayQueries,queriesBefore);
 boundFBO=0;renderer.sdlWindow=nullptr;
 renderer.LoadDefaultFramebufferViewport(-3,5,101,33);checkRect("no-window-viewport-unscaled",lastGLRect,{-3,5,101,33});
 renderer.LoadDefaultFramebufferScissor(-3,5,101,33);checkRect("no-window-scissor-unscaled",lastGLRect,{-3,5,101,33});
 renderer.sdlWindow=&live;live.w=0;live.h=0;
 renderer.LoadDefaultFramebufferViewport(-3,5,101,33);checkRect("zero-size-default-scale",lastGLRect,{-3,5,101,33});
 unsetenv("BAR_NATIVE_COCOA_DRAWABLE_SCALE");
'''

rows = []
for name, lane in before['lanes'].items():
    out = OUT / ('cpu-' + name); out.mkdir(exist_ok=False)
    source = ROOT / lane['source']
    bridge = (source / 'rts/System/Platform/Mac/MacSDL3EGLBridge.mm').read_text()
    header = (source / 'rts/System/Platform/Mac/MacSDL3EGLBridge.h').read_text()
    render = (source / 'rts/Rendering/GlobalRendering.cpp').read_text()
    oldbridge = (OUT / 'before' / lane['source'] / 'rts/System/Platform/Mac/MacSDL3EGLBridge.mm').read_text()
    oldrender = (OUT / 'before' / lane['source'] / 'rts/Rendering/GlobalRendering.cpp').read_text()
    # Placement, safe-area and existing scale helper implementations are unchanged.
    signatures = ['static int DetectInitialDisplayIndex()', 'static bool ScreenMatchesBounds(',
                  'static NSScreen* FindScreenForDisplay(', 'static SDL_Rect MakeSafeDisplayBounds(',
                  'DisplayGeometry QueryDisplayGeometry(SDL_Window* window)']
    for sig in signatures: assert extract(bridge,sig)==extract(oldbridge,sig),sig
    text = basis.read_text()
    for sig in signatures:
        text = text.replace(extract(text,sig),extract(bridge,sig))
    old_struct = extract(text,'struct DisplayGeometry')
    text = text.replace(old_struct,extract(header,'struct DisplayGeometry'))
    # Retain the existing single-screen fixture slice, explicitly bound to source.
    sig='void CGlobalRendering::UpdateViewPortGeometry()'
    full=extract(render,sig)
    assert full==extract(oldrender,sig)
    prefix=full[:full.index('\n\tdualViewPosY =')]+'\n}'
    text=text.replace(extract(text,sig),prefix)
    text=text.replace('static CGFloat drawableScale=1.0;','static unsigned displayQueries=0;')
    for sig in ['static int SDL_GetWindowDisplayIndex(', 'static const char* SDL_GetDisplayName(',
                'static int SDL_GetDisplayBounds(', 'static int SDL_GetDisplayUsableBounds(',
                'static float SDL_GetWindowDisplayScale(']:
        old=extract(text,sig);text=text.replace(old,old.replace('{','{++displayQueries;',1))
    text=text.replace(extract(text,'static CGFloat NativeCocoaDrawableScale('),extract(bridge,'static CGFloat NativeCocoaDrawableScale('))
    text=text.replace('drawableScale=2.0;', 'setenv("BAR_NATIVE_COCOA_DRAWABLE_SCALE","2",1);')
    text=text.replace('drawableScale=1.0;', 'unsetenv("BAR_NATIVE_COCOA_DRAWABLE_SCALE");')
    anchor='namespace MacSDL3EGL {\nstruct DisplayGeometry'
    assert anchor in text
    text=text.replace(anchor,'namespace MacSDL3EGL {\n'+extract(header,'struct WindowDrawableSize')+';\nstruct DisplayGeometry')
    anchor='namespace MacSDL3EGL {\nDisplayGeometry QueryDisplayGeometry'
    assert anchor in text
    helper=extract(bridge,'WindowDrawableSize QueryWindowDrawableSize(')
    text=text.replace(anchor,'namespace MacSDL3EGL {\n'+helper+'\nDisplayGeometry QueryDisplayGeometry')
    gl='''using GLint=int;using GLsizei=int;
static constexpr unsigned GL_DRAW_FRAMEBUFFER_BINDING=0x8ca6;
static GLint boundFBO=0;
static SDL_Rect lastGLRect={};
static void glGetIntegerv(unsigned,GLint* value){*value=boundFBO;}
static void glViewport(GLint x,GLint y,GLsizei w,GLsizei h){lastGLRect={x,y,w,h};}
static void glScissor(GLint x,GLint y,GLsizei w,GLsizei h){lastGLRect={x,y,w,h};}
'''
    text=text.replace('using GLint=int;using GLsizei=int;', '')
    text=text.replace('class CGlobalRendering{',gl+'\nclass CGlobalRendering{')
    text=text.replace(' void UpdateViewPortGeometry();',' void UpdateViewPortGeometry();\n void LoadDefaultFramebufferViewport(int,int,int,int) const;\n void LoadDefaultFramebufferScissor(int,int,int,int) const;')
    methods='\n'.join(extract(render,sig) for sig in ['void CGlobalRendering::LoadDefaultFramebufferViewport(', 'void CGlobalRendering::LoadDefaultFramebufferScissor('])
    text=text.replace('static unsigned checks=0;',methods+'\nstatic unsigned checks=0;')
    text=text.replace(' fprintf(stderr,"%u checks passed;',extra+'\n fprintf(stderr,"%u checks passed;')
    assert helper in text and methods in text and 'scale-policy-' in text
    fixture=out/'source-extracted-check.mm';fixture.write_text(text)
    exe=out/'display-cpu'
    args=['/usr/bin/clang++','-std=c++23','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation',str(fixture),'-o',str(exe)]
    result=subprocess.run(args,capture_output=True,text=True)
    (out/'compile.log').write_text(result.stdout+result.stderr)
    row={'lane':name,'compileArguments':args,'compileExitCode':result.returncode,'sourceSHA256':sha(fixture),'helperSHA256':hashlib.sha256(helper.encode()).hexdigest(),'sourcePins':{str(p.relative_to(ROOT)):sha(p) for p in [source/'rts/System/Platform/Mac/MacSDL3EGLBridge.h',source/'rts/System/Platform/Mac/MacSDL3EGLBridge.mm',source/'rts/Rendering/GlobalRendering.cpp']},'basis':str(basis),'scope':'Existing 53-case mocked display fixture rebound to current production source plus exact new helper and viewport/scissor methods. Screen/SDL/GL are doubles; single-screen UpdateViewPortGeometry prefix only, no native monitor/Space acceptance.'}
    if result.returncode==0:
        env=os.environ.copy();env.update(ASAN_OPTIONS='detect_leaks=0:halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1');env.pop('BAR_NATIVE_COCOA_DRAWABLE_SCALE',None)
        result=subprocess.run([str(exe)],env=env,capture_output=True,text=True)
        (out/'checks.jsonl').write_text(result.stdout);(out/'runtime.stderr').write_text(result.stderr)
        row.update(runExitCode=result.returncode,checks=len(result.stdout.splitlines()))
    (out/'receipt.json').write_text(json.dumps(row,indent=2)+'\n');rows.append(row)
    if result.returncode: raise SystemExit('Display CPU validation failed; see '+str(out))
(OUT/'cpu-summary.json').write_text(json.dumps(rows,indent=2)+'\n')
print(json.dumps([{'lane':r['lane'],'checks':r['checks'],'status':'passed'} for r in rows]))
