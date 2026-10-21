
#import <Foundation/Foundation.h>
#import <CoreGraphics/CGGeometry.h>
#include <algorithm>
#include <cmath>
#include <charconv>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <map>
#include <vector>
#include <string>
#include <stdexcept>
#include <limits>
#define RECOIL_MACOS_SDL3_EGL 1
#define LOG(...) ((void)0)
struct SDL_Rect {int x,y,w,h;};
static bool SDL_IntersectRect(const SDL_Rect* a,const SDL_Rect* b,SDL_Rect* result) {
 int x=std::max(a->x,b->x),y=std::max(a->y,b->y);
 int right=std::min(a->x+a->w,b->x+b->w),bottom=std::min(a->y+a->h,b->y+b->h);
 *result={x,y,std::max(0,right-x),std::max(0,bottom-y)};return result->w>0&&result->h>0;
}
static std::map<unsigned,CGRect> cgBounds;
static CGRect CGDisplayBounds(unsigned number){return cgBounds.at(number);}
static NSArray* screenFixtures;
@interface NSScreen:NSObject {@public unsigned number;NSRect frameValue;NSEdgeInsets insetValue;}
+(NSArray*)screens;
-(NSDictionary*)deviceDescription;
-(NSRect)frame;
-(NSEdgeInsets)safeAreaInsets;
@end
@implementation NSScreen
+(NSArray*)screens{return screenFixtures;}
-(NSDictionary*)deviceDescription{return number?@{@"NSScreenNumber":@(number)}:@{};}
-(NSRect)frame{return frameValue;}
-(NSEdgeInsets)safeAreaInsets{return insetValue;}
@end
@interface NSWindow:NSObject {@public NSScreen* screenValue;}
-(NSScreen*)screen;
@end
@implementation NSWindow
-(NSScreen*)screen{return screenValue;}
@end
struct SDL_Window{int displayIndex,w,h;NSWindow* nativeWindow;};
struct DisplayFixture{const char* name;SDL_Rect bounds,usable;};
static std::vector<DisplayFixture> displayFixtures;
static int mouseDisplay=0;
static unsigned displayQueries=0;
static CGSize layerDrawable={0,0};

static int SDL_GetWindowDisplayIndex(SDL_Window* window){++displayQueries;return window->displayIndex;}
static const char* SDL_GetDisplayName(int index){++displayQueries;return displayFixtures.at(index).name;}
static int SDL_GetDisplayBounds(int index,SDL_Rect* bounds){++displayQueries;*bounds=displayFixtures.at(index).bounds;return 0;}
static int SDL_GetDisplayUsableBounds(int index,SDL_Rect* bounds){++displayQueries;*bounds=displayFixtures.at(index).usable;return 0;}
static void SDL_GetWindowSize(SDL_Window* window,int* w,int* h){*w=window->w;*h=window->h;}
static void SDL_GetWindowSizeInPixels(SDL_Window* window,int* w,int* h){*w=window->w*2;*h=window->h*2;}
static float SDL_GetWindowDisplayScale(SDL_Window*){++displayQueries;return 2.0f;}
static NSWindow* GetNSWindow(SDL_Window* window){return window?window->nativeWindow:nil;}
static float CocoaBackingScale(NSWindow*){return 2.0f;}
static CGSize CurrentLayerDrawableSize(NSWindow*){return layerDrawable;}
static CGFloat NativeCocoaDrawableScale(NSWindow* nsWindow)
{
	const char* scaleEnv = std::getenv("BAR_NATIVE_COCOA_DRAWABLE_SCALE");
	if (scaleEnv != nullptr && scaleEnv[0] != '\0') {
		if (std::strcmp(scaleEnv, "native") == 0 || std::strcmp(scaleEnv, "retina") == 0)
			return CocoaBackingScale(nsWindow);

		char* endPtr = nullptr;
		const float requestedScale = std::strtof(scaleEnv, &endPtr);
		if (endPtr != scaleEnv && std::isfinite(requestedScale) && requestedScale > 0.0f)
			return static_cast<CGFloat>(requestedScale);
	}

	return 1.0;
}

struct SDL_Point {int x,y;};
static int SDL_GetNumVideoDisplays(){return displayFixtures.size();}
static unsigned SDL_GetGlobalMouseState(float* x,float* y){auto b=displayFixtures.at(mouseDisplay).bounds;*x=b.x+1;*y=b.y+1;return 0;}
static bool SDL_PointInRect(const SDL_Point* p,const SDL_Rect* b){return p->x>=b->x&&p->y>=b->y&&p->x<b->x+b->w&&p->y<b->y+b->h;}
static int DetectInitialDisplayIndex()
{
	const int numDisplays = SDL_GetNumVideoDisplays();
	if (numDisplays <= 1)
		return 0;

	// The launcher passes the display containing its actual window in desktop
	// logical coordinates. Resolve it against current SDL bounds, never indices
	// or a laptop model. A removed/reconfigured display falls back to the mouse.
	if (const char* intent = std::getenv("BAR_MACOS_TARGET_DISPLAY")) {
		const size_t length = strnlen(intent, 128);
		SDL_Rect wanted = {};
		int* components[] = {&wanted.x, &wanted.y, &wanted.w, &wanted.h};
		const char* cursor = intent;
		const char* end = intent + length;
		bool valid = length > 0 && length < 128;
		for (int i = 0; valid && i < 4; ++i) {
			const auto parsed = std::from_chars(cursor, end, *components[i]);
			valid = parsed.ec == std::errc() && parsed.ptr != cursor;
			cursor = parsed.ptr;
			if (i < 3) {
				valid = valid && cursor < end && *cursor == ',';
				if (valid) ++cursor;
			} else {
				valid = valid && cursor == end;
			}
		}
		if (valid && wanted.w > 0 && wanted.h > 0) {
			for (int displayIndex = 0; displayIndex < numDisplays; ++displayIndex) {
				SDL_Rect actual = {};
				if (SDL_GetDisplayBounds(displayIndex, &actual) == 0 &&
					actual.x == wanted.x && actual.y == wanted.y && actual.w == wanted.w && actual.h == wanted.h)
					return displayIndex;
			}
		}
	}

	float mouseX = 0.0f;
	float mouseY = 0.0f;
	SDL_GetGlobalMouseState(&mouseX, &mouseY);

	const SDL_Point mousePoint{static_cast<int>(mouseX), static_cast<int>(mouseY)};
	SDL_Rect bounds;

	for (int displayIndex = 0; displayIndex < numDisplays; ++displayIndex) {
		if (SDL_GetDisplayBounds(displayIndex, &bounds) != 0)
			continue;
		if (SDL_PointInRect(&mousePoint, &bounds))
			return displayIndex;
	}

	return 0;
}

namespace MacSDL3EGL {
struct WindowDrawableSize {
	int logicalWindowWidth = 0;
	int logicalWindowHeight = 0;
	int drawableWidth = 0;
	int drawableHeight = 0;
};
struct DisplayGeometry {
	int displayIndex = 0;
	const char* displayName = "unknown";

	// SDL desktop logical coordinates. Workarea and fullscreen cutout are distinct.
	SDL_Rect displayBounds = {0, 0, 0, 0};
	SDL_Rect usableBounds = {0, 0, 0, 0};
	SDL_Rect safeBounds = {0, 0, 0, 0};

	int logicalWindowWidth = 0;
	int logicalWindowHeight = 0;
	int drawableWidth = 0;
	int drawableHeight = 0;
	float sdlScale = 1.0f;
	float cocoaScale = 1.0f;

	bool safeAreaInsetsAvailable = false;
}
;
}
static bool ScreenMatchesBounds(NSScreen* screen, const SDL_Rect& bounds)
{
	if (screen == nil || bounds.w <= 0 || bounds.h <= 0)
		return false;

	// SDL Cocoa uses CGDisplayBounds too; NSScreen order is not an SDL display index.
	NSNumber* screenNumber = [[screen deviceDescription] objectForKey:@"NSScreenNumber"];
	if (screenNumber == nil)
		return false;
	const CGRect nativeBounds = CGDisplayBounds([screenNumber unsignedIntValue]);
	return std::abs(nativeBounds.origin.x - bounds.x) < 0.5 &&
		std::abs(nativeBounds.origin.y - bounds.y) < 0.5 &&
		std::abs(nativeBounds.size.width - bounds.w) < 0.5 &&
		std::abs(nativeBounds.size.height - bounds.h) < 0.5;
}
static NSScreen* FindScreenForDisplay(NSWindow* window, const SDL_Rect& bounds)
{
	NSScreen* windowScreen = window != nil ? [window screen] : nil;
	if (ScreenMatchesBounds(windowScreen, bounds))
		return windowScreen;

	for (NSScreen* screen in [NSScreen screens]) {
		if (ScreenMatchesBounds(screen, bounds))
			return screen;
	}
	return nil;
}
static SDL_Rect MakeSafeDisplayBounds(const SDL_Rect& bounds, NSSize screenSize, NSEdgeInsets insets)
{
	if (bounds.w <= 0 || bounds.h <= 0 ||
		!std::isfinite(screenSize.width) || !std::isfinite(screenSize.height) ||
		screenSize.width <= 0.0 || screenSize.height <= 0.0)
		return bounds;

	// NSScreen reports points, not backing pixels. Convert once to SDL logical units.
	const auto scaleInset = [](CGFloat inset, int extent, CGFloat screenExtent) {
		if (!std::isfinite(inset) || inset <= 0.0)
			return 0;
		return static_cast<int>(std::ceil(std::min<double>(inset / screenExtent, 1.0) * extent));
	};
	const int left = scaleInset(insets.left, bounds.w, screenSize.width);
	const int right = scaleInset(insets.right, bounds.w, screenSize.width);
	const int top = scaleInset(insets.top, bounds.h, screenSize.height);
	const int bottom = scaleInset(insets.bottom, bounds.h, screenSize.height);
	if (left + right >= bounds.w || top + bottom >= bounds.h)
		return bounds;

	return {bounds.x + left, bounds.y + top, bounds.w - left - right, bounds.h - top - bottom};
}

namespace MacSDL3EGL {
WindowDrawableSize QueryWindowDrawableSize(SDL_Window* window)
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
DisplayGeometry QueryDisplayGeometry(SDL_Window* window)
{
	DisplayGeometry geometry;

	geometry.displayIndex = window != nullptr ? SDL_GetWindowDisplayIndex(window) : DetectInitialDisplayIndex();
	geometry.displayName = SDL_GetDisplayName(geometry.displayIndex);
	SDL_GetDisplayBounds(geometry.displayIndex, &geometry.displayBounds);
	SDL_GetDisplayUsableBounds(geometry.displayIndex, &geometry.usableBounds);
	if (geometry.usableBounds.w <= 0 || geometry.usableBounds.h <= 0)
		geometry.usableBounds = geometry.displayBounds;
	geometry.safeBounds = geometry.displayBounds;
	NSWindow* nsWindow = GetNSWindow(window);
	NSScreen* screen = FindScreenForDisplay(nsWindow, geometry.displayBounds);
	if (@available(macOS 12.0, *)) {
		if (screen != nil) {
			geometry.safeAreaInsetsAvailable = true;
			geometry.safeBounds = MakeSafeDisplayBounds(geometry.displayBounds, [screen frame].size, [screen safeAreaInsets]);
		}
	}

	if (window != nullptr) {
		SDL_GetWindowSize(window, &geometry.logicalWindowWidth, &geometry.logicalWindowHeight);
		SDL_GetWindowSizeInPixels(window, &geometry.drawableWidth, &geometry.drawableHeight);
		geometry.sdlScale = SDL_GetWindowDisplayScale(window);
		geometry.cocoaScale = CocoaBackingScale(nsWindow);

		const CGSize layerDrawable = CurrentLayerDrawableSize(nsWindow);
		if (layerDrawable.width > 0.0 && layerDrawable.height > 0.0) {
			geometry.drawableWidth = static_cast<int>(std::max(0.0, static_cast<double>(layerDrawable.width)));
			geometry.drawableHeight = static_cast<int>(std::max(0.0, static_cast<double>(layerDrawable.height)));
		} else {
			const CGFloat drawableScale = NativeCocoaDrawableScale(nsWindow);
			geometry.drawableWidth = static_cast<int>(std::max(0.0, static_cast<double>(geometry.logicalWindowWidth * drawableScale)));
			geometry.drawableHeight = static_cast<int>(std::max(0.0, static_cast<double>(geometry.logicalWindowHeight * drawableScale)));
		}
	}

	return geometry;
}
}

using GLint=int;using GLsizei=int;
static constexpr unsigned GL_DRAW_FRAMEBUFFER_BINDING=0x8ca6;
static GLint boundFBO=0;
static SDL_Rect lastGLRect={};
static void glGetIntegerv(unsigned,GLint* value){*value=boundFBO;}
static void glViewport(GLint x,GLint y,GLsizei w,GLsizei h){lastGLRect={x,y,w,h};}
static void glScissor(GLint x,GLint y,GLsizei w,GLsizei h){lastGLRect={x,y,w,h};}

class CGlobalRendering{
public:
 int winPosX=0,winPosY=0,winSizeX=1,winSizeY=1;
 int viewPosX=0,viewPosY=0,viewSizeX=1,viewSizeY=1,viewWindowOffsetY=0;
 bool fullScreen=true,dualScreenMode=false;
 void* macSDL3EGLBridge=reinterpret_cast<void*>(1);
 SDL_Window* sdlWindow=nullptr;
 void UpdateViewPortGeometry();
 void LoadDefaultFramebufferViewport(int,int,int,int) const;
 void LoadDefaultFramebufferScissor(int,int,int,int) const;
};

static GLint ScaleDefaultFramebufferCoord(int value, float scale)
{
	return static_cast<GLint>((static_cast<float>(value) * scale) + (value >= 0 ? 0.5f : -0.5f));
}
static GLsizei ScaleDefaultFramebufferSize(int value, float scale)
{
	return static_cast<GLsizei>((static_cast<float>(value) * scale) + 0.5f);
}
void CGlobalRendering::UpdateViewPortGeometry()
{
	viewPosY = 0;
	viewSizeY = winSizeY;
	viewWindowOffsetY = 0;

#if defined(__APPLE__) && defined(RECOIL_MACOS_SDL3_EGL)
	if (fullScreen && !dualScreenMode && macSDL3EGLBridge != nullptr) {
		const MacSDL3EGL::DisplayGeometry geometry = MacSDL3EGL::QueryDisplayGeometry(sdlWindow);
		const SDL_Rect windowBounds = {winPosX, winPosY, winSizeX, winSizeY};
		SDL_Rect displayIntersection = {};
		SDL_Rect safeIntersection = {};

		// During a screen transition, wait until the window is on its target display.
		// Intersect actual logical window coordinates so a Cocoa-safe content area
		// does not receive a second cutout inset. Framebuffer scaling happens later.
		if (SDL_IntersectRect(&windowBounds, &geometry.displayBounds, &displayIntersection) &&
			displayIntersection.w == winSizeX && displayIntersection.h == winSizeY &&
			SDL_IntersectRect(&windowBounds, &geometry.safeBounds, &safeIntersection)) {
			viewPosX = safeIntersection.x - windowBounds.x;
			viewWindowOffsetY = safeIntersection.y - windowBounds.y;
			viewPosY = winSizeY - (viewWindowOffsetY + safeIntersection.h);
			viewSizeX = safeIntersection.w;
			viewSizeY = safeIntersection.h;
			LOG("[GR::%s][macOS safe viewport] window=%dx%d view=<%d,%d %dx%d> mouseTopOffset=%d",
				__func__, winSizeX, winSizeY, viewPosX, viewPosY, viewSizeX, viewSizeY, viewWindowOffsetY);
			return;
		}
	}
#endif

	if (!dualScreenMode) {
		viewPosX = 0;
		viewSizeX = winSizeX;

		return;
	}

}

void CGlobalRendering::LoadDefaultFramebufferViewport(int px, int py, int sx, int sy) const
{
#if defined(__APPLE__) && defined(RECOIL_MACOS_SDL3_EGL)
	if (sdlWindow != nullptr) {
		GLint drawFramebuffer = 0;
		glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &drawFramebuffer);
		if (drawFramebuffer != 0) {
			glViewport(px, py, sx, sy);
			return;
		}

		const MacSDL3EGL::WindowDrawableSize drawableSize = MacSDL3EGL::QueryWindowDrawableSize(sdlWindow);
		const float scaleX =
			(drawableSize.logicalWindowWidth > 0 && drawableSize.drawableWidth > 0)?
				(static_cast<float>(drawableSize.drawableWidth) / static_cast<float>(drawableSize.logicalWindowWidth)): 1.0f;
		const float scaleY =
			(drawableSize.logicalWindowHeight > 0 && drawableSize.drawableHeight > 0)?
				(static_cast<float>(drawableSize.drawableHeight) / static_cast<float>(drawableSize.logicalWindowHeight)): 1.0f;

		glViewport(
			ScaleDefaultFramebufferCoord(px, scaleX),
			ScaleDefaultFramebufferCoord(py, scaleY),
			ScaleDefaultFramebufferSize(sx, scaleX),
			ScaleDefaultFramebufferSize(sy, scaleY)
		);
		return;
	}
#endif
	glViewport(px, py, sx, sy);
}
void CGlobalRendering::LoadDefaultFramebufferScissor(int px, int py, int sx, int sy) const
{
#if defined(__APPLE__) && defined(RECOIL_MACOS_SDL3_EGL)
	if (sdlWindow != nullptr) {
		GLint drawFramebuffer = 0;
		glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &drawFramebuffer);
		if (drawFramebuffer != 0) {
			glScissor(px, py, sx, sy);
			return;
		}

		const MacSDL3EGL::WindowDrawableSize drawableSize = MacSDL3EGL::QueryWindowDrawableSize(sdlWindow);
		const float scaleX =
			(drawableSize.logicalWindowWidth > 0 && drawableSize.drawableWidth > 0)?
				(static_cast<float>(drawableSize.drawableWidth) / static_cast<float>(drawableSize.logicalWindowWidth)): 1.0f;
		const float scaleY =
			(drawableSize.logicalWindowHeight > 0 && drawableSize.drawableHeight > 0)?
				(static_cast<float>(drawableSize.drawableHeight) / static_cast<float>(drawableSize.logicalWindowHeight)): 1.0f;

		glScissor(
			ScaleDefaultFramebufferCoord(px, scaleX),
			ScaleDefaultFramebufferCoord(py, scaleY),
			ScaleDefaultFramebufferSize(sx, scaleX),
			ScaleDefaultFramebufferSize(sy, scaleY)
		);
		return;
	}
#endif
	glScissor(px, py, sx, sy);
}
static unsigned checks=0;
static void checkRect(const char* name,SDL_Rect actual,SDL_Rect expected){
 if(actual.x!=expected.x||actual.y!=expected.y||actual.w!=expected.w||actual.h!=expected.h){
  fprintf(stderr,"%s actual=%d,%d %dx%d expected=%d,%d %dx%d\n",name,actual.x,actual.y,actual.w,actual.h,expected.x,expected.y,expected.w,expected.h);throw std::runtime_error(name);
 }
 printf("{\"name\":\"%s\",\"rect\":[%d,%d,%d,%d],\"status\":\"passed\"}\n",name,actual.x,actual.y,actual.w,actual.h);checks++;
}
static void checkValue(const char* name,int actual,int expected){
 if(actual!=expected)throw std::runtime_error(name);
 printf("{\"name\":\"%s\",\"value\":%d,\"status\":\"passed\"}\n",name,actual);checks++;
}
static NSScreen* screen(unsigned number,SDL_Rect bounds,NSSize frame,NSEdgeInsets insets){
 NSScreen* result=[NSScreen new];result->number=number;result->frameValue=NSMakeRect(0,0,frame.width,frame.height);result->insetValue=insets;cgBounds[number]=CGRectMake(bounds.x,bounds.y,bounds.w,bounds.h);return result;
}
static NSWindow* nativeWindow(NSScreen* screen){NSWindow* result=[NSWindow new];result->screenValue=screen;return result;}
static void viewport(const char* name,SDL_Window* window,SDL_Rect bounds,SDL_Rect expected,int expectedTop){
 CGlobalRendering renderer;renderer.sdlWindow=window;renderer.winPosX=bounds.x;renderer.winPosY=bounds.y;renderer.winSizeX=bounds.w;renderer.winSizeY=bounds.h;renderer.UpdateViewPortGeometry();
 checkRect(name,{renderer.viewPosX,renderer.viewPosY,renderer.viewSizeX,renderer.viewSizeY},expected);checkValue((std::string(name)+"-mouse-top").c_str(),renderer.viewWindowOffsetY,expectedTop);
}
int main(){@autoreleasepool{
 using namespace MacSDL3EGL;
 const SDL_Rect iMacBounds={0,0,2240,1260},notchBounds={-1512,0,1512,982},largeBounds={2240,-600,1728,1117};
 NSScreen* iMac=screen(11,iMacBounds,NSMakeSize(2240,1260),NSEdgeInsetsMake(0,0,0,0));
 NSScreen* notched=screen(22,notchBounds,NSMakeSize(1512,982),NSEdgeInsetsMake(32,0,0,0));
 NSScreen* large=screen(33,largeBounds,NSMakeSize(1728,1117),NSEdgeInsetsMake(38,0,0,0));
 screenFixtures=@[large,notched,iMac];displayFixtures={{"iMac",iMacBounds,{0,30,2240,1142}},{"Built-in Retina",notchBounds,{-1512,32,1512,860}},{"Different cutout panel",largeBounds,{2240,-562,1728,1000}}};
 SDL_Window iMacWindow={0,2240,1260,nativeWindow(iMac)},notchWindow={1,1512,982,nativeWindow(notched)},largeWindow={2,1728,1117,nativeWindow(large)};

 mouseDisplay=1;
 setenv("BAR_MACOS_TARGET_DISPLAY","0,0,2240,1260",1);checkValue("launcher-display-beats-mouse",DetectInitialDisplayIndex(),0);
 checkValue("existing-window-beats-launch-intent",QueryDisplayGeometry(&notchWindow).displayIndex,1);
 setenv("BAR_MACOS_TARGET_DISPLAY","-1512,0,1512,982",1);checkValue("launcher-negative-X-display",DetectInitialDisplayIndex(),1);
 setenv("BAR_MACOS_TARGET_DISPLAY","2240,-600,1728,1117",1);checkValue("launcher-negative-Y-display",DetectInitialDisplayIndex(),2);
 const char* invalid[]={"","0,0,2240","0,0,2240,1260,1","0,0,2240,1260x","0,0,0,1260","0,0,-1,1260","2147483648,0,2240,1260","-2147483649,0,2240,1260","0,0,2240,9999","0,0,2240,1260\n"," 0,0,2240,1260"};
 for(unsigned i=0;i<sizeof(invalid)/sizeof(invalid[0]);++i){setenv("BAR_MACOS_TARGET_DISPLAY",invalid[i],1);checkValue(("bad-launch-intent-fallback-"+std::to_string(i)).c_str(),DetectInitialDisplayIndex(),1);}
 setenv("BAR_MACOS_TARGET_DISPLAY",std::string(200,'9').c_str(),1);checkValue("bounded-launch-intent-parser",DetectInitialDisplayIndex(),1);
 setenv("BAR_MACOS_TARGET_DISPLAY","0,0,2240,1260",1);auto saved=displayFixtures;displayFixtures[0].bounds.w=2200;checkValue("changed-display-falls-back",DetectInitialDisplayIndex(),1);displayFixtures=saved;
 displayFixtures.resize(1);checkValue("single-display-is-zero",DetectInitialDisplayIndex(),0);displayFixtures=saved;
 unsetenv("BAR_MACOS_TARGET_DISPLAY");mouseDisplay=0;
 auto actual=QueryDisplayGeometry(&iMacWindow);
 checkRect("iMac-nonnotched-fullscreen",actual.safeBounds,iMacBounds);checkRect("iMac-desktop-workarea-separate",actual.usableBounds,{0,30,2240,1142});checkValue("iMac-safe-area-API-available",actual.safeAreaInsetsAvailable,1);
 viewport("iMac-full-viewport",&iMacWindow,iMacBounds,{0,0,2240,1260},0);
 actual=QueryDisplayGeometry(&notchWindow);checkRect("notched-actual-inset-negative-origin",actual.safeBounds,{-1512,32,1512,950});viewport("notched-full-container",&notchWindow,notchBounds,{0,0,1512,950},32);
 setenv("BAR_NATIVE_COCOA_DRAWABLE_SCALE","2",1);actual=QueryDisplayGeometry(&notchWindow);checkRect("retina-keeps-safe-area-logical",actual.safeBounds,{-1512,32,1512,950});checkRect("retina-drawable-only",{0,0,actual.drawableWidth,actual.drawableHeight},{0,0,3024,1964});
 checkRect("existing-framebuffer-conversion-once",{ScaleDefaultFramebufferCoord(0,2),ScaleDefaultFramebufferCoord(0,2),ScaleDefaultFramebufferSize(1512,2),ScaleDefaultFramebufferSize(950,2)},{0,0,3024,1900});unsetenv("BAR_NATIVE_COCOA_DRAWABLE_SCALE");
 SDL_Window safeWindow={1,1512,950,nativeWindow(notched)};viewport("Cocoa-already-safe-no-double-inset",&safeWindow,{-1512,32,1512,950},{0,0,1512,950},0);
 SDL_Window smaller={1,1000,700,nativeWindow(notched)};viewport("contained-safe-window-keeps-content",&smaller,{-1400,70,1000,700},{0,0,1000,700},0);
 viewport("straddling-transition-defers-crop",&notchWindow,{-200,0,1512,982},{0,0,1512,982},0);
 iMacWindow.nativeWindow=nativeWindow(notched);checkRect("stale-window-screen-uses-target-bounds",QueryDisplayGeometry(&iMacWindow).safeBounds,iMacBounds);
 mouseDisplay=1;checkRect("pre-window-target-is-mouse-display",QueryDisplayGeometry(nullptr).safeBounds,{-1512,32,1512,950});
 screenFixtures=@[large];checkRect("matching-window-screen-beats-array-order",QueryDisplayGeometry(&notchWindow).safeBounds,{-1512,32,1512,950});
 SDL_Window missing={1,1512,982,nativeWindow(iMac)};actual=QueryDisplayGeometry(&missing);checkRect("missing-native-screen-fallback-full",actual.safeBounds,notchBounds);checkValue("missing-native-screen-no-inset-claim",actual.safeAreaInsetsAvailable,0);
 screenFixtures=@[large,notched,iMac];actual=QueryDisplayGeometry(&largeWindow);checkRect("other-panel-actual-38-point-inset",actual.safeBounds,{2240,-562,1728,1079});viewport("other-display-negative-Y",&largeWindow,largeBounds,{0,0,1728,1079},38);
 NSScreen* mirror=screen(44,notchBounds,NSMakeSize(1512,982),NSEdgeInsetsMake(60,0,0,0));screenFixtures=@[mirror,notched,iMac];checkRect("window-screen-wins-mirrored-bounds",QueryDisplayGeometry(&notchWindow).safeBounds,{-1512,32,1512,950});
 checkRect("fractional-cutout-rounds-inward",MakeSafeDisplayBounds({0,0,1000,800},NSMakeSize(1000,800),NSEdgeInsetsMake(20.25,0,0,0)),{0,21,1000,779});
 checkRect("points-to-logical-ratio",MakeSafeDisplayBounds({100,-200,2000,1600},NSMakeSize(1000,800),NSEdgeInsetsMake(20,10,15,12)),{120,-160,1956,1530});
 checkRect("invalid-screen-extent-fallback",MakeSafeDisplayBounds({0,0,1000,800},NSMakeSize(0,800),NSEdgeInsetsMake(20,0,0,0)),{0,0,1000,800});
 checkRect("insets-cannot-collapse-content",MakeSafeDisplayBounds({0,0,1000,800},NSMakeSize(1000,800),NSEdgeInsetsMake(800,0,0,0)),{0,0,1000,800});
 checkRect("nonfinite-inset-is-not-guessed",MakeSafeDisplayBounds({0,0,1000,800},NSMakeSize(1000,800),NSEdgeInsetsMake(std::numeric_limits<double>::quiet_NaN(),0,0,0)),{0,0,1000,800});
 NSScreen* four=screen(55,{0,0,1000,800},NSMakeSize(1000,800),NSEdgeInsetsMake(20,10,15,12));screenFixtures=@[four];displayFixtures[0]={"Generic display",{0,0,1000,800},{0,30,1000,700}};
 SDL_Window fourWindow={0,1000,800,nativeWindow(four)};viewport("four-actual-insets",&fourWindow,{0,0,1000,800},{10,15,978,765},20);four->insetValue=NSEdgeInsetsMake(0,0,0,0);viewport("live-inset-change-not-cached",&fourWindow,{0,0,1000,800},{0,0,1000,800},0);

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

 fprintf(stderr,"%u checks passed; mocked screen/SDL CPU path, no native screen/GPU/runtime.\n",checks);
}return 0;}
