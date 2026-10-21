from pathlib import Path
import difflib, hashlib, json

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
before = json.loads((OUT / 'before.json').read_text())
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()

declaration = '''// Live window/layer sizes for default-framebuffer coordinate conversion.
// Display placement and safe-area queries remain in QueryDisplayGeometry.
struct WindowDrawableSize {
	int logicalWindowWidth = 0;
	int logicalWindowHeight = 0;
	int drawableWidth = 0;
	int drawableHeight = 0;
};

WindowDrawableSize QueryWindowDrawableSize(SDL_Window* window);

'''
implementation = '''WindowDrawableSize QueryWindowDrawableSize(SDL_Window* window)
{
	WindowDrawableSize size;
	if (window == nullptr)
		return size;

	NSWindow* nsWindow = GetNSWindow(window);
	SDL_GetWindowSize(window, &size.logicalWindowWidth, &size.logicalWindowHeight);
	const CGSize layerDrawable = CurrentLayerDrawableSize(nsWindow);
	if (layerDrawable.width > 0.0 && layerDrawable.height > 0.0) {
		size.drawableWidth = static_cast<int>(std::max<double>(0.0, static_cast<double>(layerDrawable.width)));
		size.drawableHeight = static_cast<int>(std::max<double>(0.0, static_cast<double>(layerDrawable.height)));
	} else {
		const CGFloat drawableScale = NativeCocoaDrawableScale(nsWindow);
		size.drawableWidth = static_cast<int>(std::max<double>(0.0, static_cast<double>(size.logicalWindowWidth * drawableScale)));
		size.drawableHeight = static_cast<int>(std::max<double>(0.0, static_cast<double>(size.logicalWindowHeight * drawableScale)));
	}
	return size;
}

'''

pins = {}
patch = []
for lane in before['lanes'].values():
    for suffix in ['rts/System/Platform/Mac/MacSDL3EGLBridge.h',
                   'rts/System/Platform/Mac/MacSDL3EGLBridge.mm',
                   'rts/Rendering/GlobalRendering.cpp']:
        relative = lane['source'] + '/' + suffix
        path = ROOT / relative
        assert sha(path) == before['selectedFiles'][relative], relative
        old = path.read_text()
        new = old
        if suffix.endswith('.h'):
            anchor = 'DisplayGeometry QueryDisplayGeometry(SDL_Window* window);'
            assert new.count(anchor) == 1
            new = new.replace(anchor, declaration + anchor)
        elif suffix.endswith('.mm'):
            anchor = 'DisplayGeometry QueryDisplayGeometry(SDL_Window* window)\n'
            assert new.count(anchor) == 1
            new = new.replace(anchor, implementation + anchor)
        else:
            start = new.index('void CGlobalRendering::LoadDefaultFramebufferViewport(')
            end = new.index('void CGlobalRendering::LoadViewport()', start)
            old_part = new[start:end]
            anchor = 'const MacSDL3EGL::DisplayGeometry displayGeometry = MacSDL3EGL::QueryDisplayGeometry(sdlWindow);'
            assert old_part.count(anchor) == 2
            part = old_part.replace(anchor, 'const MacSDL3EGL::WindowDrawableSize drawableSize = MacSDL3EGL::QueryWindowDrawableSize(sdlWindow);')
            part = part.replace('displayGeometry.', 'drawableSize.')
            new = new[:start] + part + new[end:]
        assert new != old
        path.write_text(new)
        pins[relative] = sha(path)
        patch.append(''.join(difflib.unified_diff(old.splitlines(True), new.splitlines(True),
                                                fromfile='before/' + relative, tofile='after/' + relative)))

(OUT / 'applied-source.patch').write_text(''.join(patch))
(OUT / 'review-pins.json').write_text(json.dumps(pins, indent=2) + '\n')
print(json.dumps({'productFiles': len(pins), 'policy': 'No caching; old full geometry query unchanged; existing layer and scale fallback preserved.'}))
