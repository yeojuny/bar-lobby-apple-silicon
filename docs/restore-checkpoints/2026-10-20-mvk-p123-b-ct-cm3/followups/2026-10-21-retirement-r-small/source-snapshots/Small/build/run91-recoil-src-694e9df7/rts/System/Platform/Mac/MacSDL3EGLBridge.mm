/* This file is part of the Spring engine (GPL v2 or later), see LICENSE.html */

#include "System/Platform/Mac/MacSDL3EGLBridge.h"

#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CGDirectDisplay.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include <SDL.h>
#include <SDL3/SDL_properties.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>

#include <algorithm>
#include <cmath>
#include <charconv>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "System/Config/ConfigHandler.h"
#include "System/Log/ILog.h"

namespace {

static constexpr uint32_t BAR_ON_MVK_COCOA_EGL_SURFACE_MAGIC = 0x434f4341u;
static constexpr uint32_t BAR_ON_MVK_COCOA_EGL_SURFACE_VERSION = 1u;

struct BarOnMVKPrivateCocoaSurface {
	uint32_t magic = BAR_ON_MVK_COCOA_EGL_SURFACE_MAGIC;
	uint32_t version = BAR_ON_MVK_COCOA_EGL_SURFACE_VERSION;
	void* metalLayer = nullptr;
	uint32_t width = 0;
	uint32_t height = 0;
};

using PFNGLGETSTRINGPROC_LOCAL = const unsigned char* (*)(unsigned int name);

static constexpr unsigned int GL_VENDOR_LOCAL = 0x1F00;
static constexpr unsigned int GL_RENDERER_LOCAL = 0x1F01;
static constexpr unsigned int GL_VERSION_LOCAL = 0x1F02;
static constexpr unsigned int GL_SHADING_LANGUAGE_VERSION_LOCAL = 0x8B8C;

static const char* EnvValue(const char* name)
{
	const char* value = std::getenv(name);
	return value != nullptr ? value : "<unset>";
}

static float CocoaBackingScale(NSWindow* window)
{
	if (window != nil && window.backingScaleFactor > 0.0)
		return static_cast<float>(window.backingScaleFactor);

	if (NSScreen.mainScreen != nil && NSScreen.mainScreen.backingScaleFactor > 0.0)
		return static_cast<float>(NSScreen.mainScreen.backingScaleFactor);

	return 1.0f;
}

static NSWindow* GetNSWindow(SDL_Window* window)
{
	if (window == nullptr)
		return nil;

	SDL_PropertiesID props = SDL_GetWindowProperties(window);
	return (__bridge NSWindow*)SDL_GetPointerProperty(props, SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, nullptr);
}

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

static CGSize CurrentLayerDrawableSize(NSWindow* nsWindow)
{
	if (nsWindow == nil || nsWindow.contentView == nil || nsWindow.contentView.layer == nil)
		return CGSizeMake(0.0, 0.0);

	CALayer* layer = nsWindow.contentView.layer;
	if (![layer isKindOfClass:[CAMetalLayer class]])
		return CGSizeMake(0.0, 0.0);

	return ((CAMetalLayer*)layer).drawableSize;
}

static CGSize UpdateLayerDrawableSize(NSWindow* nsWindow, NSView* view, CAMetalLayer* layer, const char* reason)
{
	const CGFloat drawableScale = NativeCocoaDrawableScale(nsWindow);
	const NSRect bounds = view != nil ? view.bounds : NSMakeRect(0, 0, 0, 0);
	const CGSize drawableSize = CGSizeMake(bounds.size.width * drawableScale, bounds.size.height * drawableScale);
	const CGSize previousDrawableSize = layer.drawableSize;
	const CGFloat previousScale = layer.contentsScale;
	const bool sizeChanged =
		std::abs(static_cast<double>(previousDrawableSize.width - drawableSize.width)) > 0.5 ||
		std::abs(static_cast<double>(previousDrawableSize.height - drawableSize.height)) > 0.5 ||
		std::abs(static_cast<double>(previousScale - drawableScale)) > 0.001;
	const bool quietPreSwap = (reason != nullptr && std::strcmp(reason, "pre-swap") == 0);

	layer.contentsScale = drawableScale;
	if (sizeChanged)
		layer.drawableSize = drawableSize;

	if ((sizeChanged || !quietPreSwap) && LOG_IS_ENABLED(L_DEBUG)) {
		const CGFloat cocoaScale = CocoaBackingScale(nsWindow);
		LOG_L(L_DEBUG, "[MacSDL3EGL::%s] reason=%s logicalView=%.1fx%.1f drawable=%.1fx%.1f cocoaScale=%.3f drawableScale=%.3f changed=%d",
			__func__, reason,
			static_cast<double>(bounds.size.width),
			static_cast<double>(bounds.size.height),
			static_cast<double>(drawableSize.width),
			static_cast<double>(drawableSize.height),
			static_cast<double>(cocoaScale),
			static_cast<double>(drawableScale),
			static_cast<int>(sizeChanged)
		);
	}

	return drawableSize;
}

static const char* PixelFormatName(MTLPixelFormat pixelFormat)
{
	switch (pixelFormat) {
		case MTLPixelFormatBGRA8Unorm: return "MTLPixelFormatBGRA8Unorm";
		case MTLPixelFormatBGRA8Unorm_sRGB: return "MTLPixelFormatBGRA8Unorm_sRGB";
		default: return "unknown";
	}
}

static EGLContext CreateContext(EGLDisplay display, EGLConfig config, int major, int minor, bool coreProfile)
{
	const EGLint contextAttribs[] = {
		EGL_CONTEXT_MAJOR_VERSION, major,
		EGL_CONTEXT_MINOR_VERSION, minor,
		EGL_NONE
	};

	EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT, contextAttribs);
	if (context != EGL_NO_CONTEXT) {
		LOG("[MacSDL3EGL::%s] eglCreateContext requested=%d.%d core=%d result=success",
			__func__, major, minor, int(coreProfile));
		return context;
	}

	LOG_L(L_WARNING, "[MacSDL3EGL::%s] eglCreateContext requested=%d.%d core=%d failed eglGetError=0x%04x; trying default context",
		__func__, major, minor, int(coreProfile), eglGetError());

	const EGLint fallbackAttribs[] = {EGL_NONE};
	context = eglCreateContext(display, config, EGL_NO_CONTEXT, fallbackAttribs);
	if (context != EGL_NO_CONTEXT)
		LOG("[MacSDL3EGL::%s] eglCreateContext requested=fallback result=success", __func__);
	else
		LOG_L(L_ERROR, "[MacSDL3EGL::%s] eglCreateContext requested=fallback failed eglGetError=0x%04x", __func__, eglGetError());

	return context;
}

static bool TryChooseExactConfig(
	EGLDisplay display,
	EGLConfig* outConfig,
	int samples,
	int depthSize,
	int stencilSize,
	int configuredSamples,
	int requestedSamples
) {
	const EGLint attributes[] = {
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
		EGL_RED_SIZE, 8,
		EGL_GREEN_SIZE, 8,
		EGL_BLUE_SIZE, 8,
		EGL_ALPHA_SIZE, 8,
		EGL_SAMPLE_BUFFERS, samples > 0 ? 1 : 0,
		EGL_SAMPLES, samples,
		EGL_DEPTH_SIZE, depthSize,
		EGL_STENCIL_SIZE, stencilSize,
		EGL_NONE
	};

	EGLint count = 0;
	if (!eglChooseConfig(display, attributes, nullptr, 0, &count) || count <= 0) {
		LOG_L(L_WARNING,
			"[MacSDL3EGL::%s] configured=%d requested=%d candidate=%d depth=%d stencil=%d unavailable count=%d eglGetError=0x%04x",
			__func__, configuredSamples, requestedSamples, samples, depthSize, stencilSize, count, eglGetError());
		return false;
	}

	std::vector<EGLConfig> configs(count);
	if (!eglChooseConfig(display, attributes, configs.data(), count, &count) || count <= 0) {
		LOG_L(L_WARNING,
			"[MacSDL3EGL::%s] configured=%d requested=%d candidate=%d config enumeration failed count=%d eglGetError=0x%04x",
			__func__, configuredSamples, requestedSamples, samples, count, eglGetError());
		return false;
	}

	for (int i = 0; i < count; ++i) {
		EGLint actualSamples = 0;
		EGLint actualSampleBuffers = 0;
		EGLint actualDepth = 0;
		EGLint actualStencil = 0;
		if (!eglGetConfigAttrib(display, configs[i], EGL_SAMPLES, &actualSamples))
			continue;
		if (!eglGetConfigAttrib(display, configs[i], EGL_SAMPLE_BUFFERS, &actualSampleBuffers))
			continue;
		if (!eglGetConfigAttrib(display, configs[i], EGL_DEPTH_SIZE, &actualDepth))
			continue;
		if (!eglGetConfigAttrib(display, configs[i], EGL_STENCIL_SIZE, &actualStencil))
			continue;

		const int expectedSampleBuffers = samples > 0 ? 1 : 0;
		if (actualSamples != samples || actualSampleBuffers != expectedSampleBuffers)
			continue;
		if (actualDepth < depthSize || actualStencil < stencilSize)
			continue;

		*outConfig = configs[i];
		LOG("[MacSDL3EGL::%s] configured=%d requested=%d selected=%d sampleBuffers=%d depth=%d stencil=%d",
			__func__, configuredSamples, requestedSamples, actualSamples, actualSampleBuffers, actualDepth, actualStencil);
		return true;
	}

	LOG_L(L_WARNING,
		"[MacSDL3EGL::%s] configured=%d requested=%d candidate=%d returned no exact sample-count match",
		__func__, configuredSamples, requestedSamples, samples);
	return false;
}

// RUN64_DYNAMIC_MSAA: honor BAR's MSAALevel instead of silently forcing 4x.
static bool ChooseConfig(EGLDisplay display, EGLConfig* outConfig)
{
	const int configuredSamples = configHandler->GetInt("MSAALevel");
	const int requestedSamples = configuredSamples >= 4 ? 4 : (configuredSamples >= 2 ? 2 : 0);

	int candidates[3] = {requestedSamples, 0, 0};
	int candidateCount = 1;
	if (requestedSamples == 4) {
		candidates[1] = 2;
		candidates[2] = 0;
		candidateCount = 3;
	} else if (requestedSamples == 2) {
		candidates[1] = 0;
		candidateCount = 2;
	}

	for (int i = 0; i < candidateCount; ++i) {
		if (TryChooseExactConfig(
				display,
				outConfig,
				candidates[i],
				24,
				8,
				configuredSamples,
				requestedSamples
			)) {
			return true;
		}
	}

	LOG_L(L_WARNING,
		"[MacSDL3EGL::%s] configured=%d requested=%d has no depth/stencil config; trying color-only non-MSAA fallback",
		__func__, configuredSamples, requestedSamples);

	if (TryChooseExactConfig(display, outConfig, 0, 0, 0, configuredSamples, requestedSamples))
		return true;

	LOG_L(L_ERROR,
		"[MacSDL3EGL::%s] configured=%d requested=%d failed to select any exact EGL sample-count config",
		__func__, configuredSamples, requestedSamples);
	return false;
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

} // namespace

namespace MacSDL3EGL {

struct Bridge::Impl {
	SDL_Window* window = nullptr;
	NSWindow* nsWindow = nil;
	NSView* contentView = nil;
	CAMetalLayer* metalLayer = nil;
	id<MTLDevice> metalDevice = nil;

	BarOnMVKPrivateCocoaSurface privateSurface;

	EGLDisplay display = EGL_NO_DISPLAY;
	EGLConfig config = nullptr;
	EGLContext context = EGL_NO_CONTEXT;
	EGLSurface surface = EGL_NO_SURFACE;
	bool initialized = false;
};

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

SDL_Rect GetSafeDisplayBounds(SDL_Window* window)
{
	return QueryDisplayGeometry(window).safeBounds;
}

void LogDisplayGeometry(SDL_Window* window, const char* phase)
{
	if (!LOG_IS_ENABLED(L_DEBUG))
		return;

	const DisplayGeometry g = QueryDisplayGeometry(window);
	LOG_L(L_DEBUG, "[MacSDL3EGL::%s] phase=%s displayIndex=%d displayName=\"%s\" displayBounds=%d,%d %dx%d usableBounds=%d,%d %dx%d safeBounds=%d,%d %dx%d safeAreaInsetsAvailable=%d logicalWindow=%dx%d drawable=%dx%d sdlScale=%.3f cocoaScale=%.3f policy=nativeFullscreen_targetScreenSafeArea_1xDrawable",
		__func__, phase,
		g.displayIndex,
		g.displayName != nullptr ? g.displayName : "unknown",
		g.displayBounds.x, g.displayBounds.y, g.displayBounds.w, g.displayBounds.h,
		g.usableBounds.x, g.usableBounds.y, g.usableBounds.w, g.usableBounds.h,
		g.safeBounds.x, g.safeBounds.y, g.safeBounds.w, g.safeBounds.h,
		int(g.safeAreaInsetsAvailable),
		g.logicalWindowWidth, g.logicalWindowHeight,
		g.drawableWidth, g.drawableHeight,
		g.sdlScale,
		g.cocoaScale
	);
}

void* GetGLProcAddress(const char* name)
{
	return reinterpret_cast<void*>(eglGetProcAddress(name));
}

Bridge::Bridge()
	: impl(new Impl())
{
}

Bridge::~Bridge()
{
	Destroy();
	delete impl;
	impl = nullptr;
}

bool Bridge::Initialize(SDL_Window* window, int requestMajor, int requestMinor, bool requestCoreProfile)
{
	if (impl->initialized)
		return true;

	impl->window = window;
	LogRuntimeEnvironment();

	if (std::getenv("EGL_PLATFORM") == nullptr) {
		setenv("EGL_PLATFORM", "cocoa", 0);
		LOG("[MacSDL3EGL::%s] EGL_PLATFORM was unset; set to cocoa for project-local Mesa bridge", __func__);
	}

	impl->nsWindow = GetNSWindow(window);
	if (impl->nsWindow == nil || impl->nsWindow.contentView == nil) {
		LOG_L(L_ERROR, "[MacSDL3EGL::%s] SDL Cocoa NSWindow/contentView unavailable via %s",
			__func__, SDL_PROP_WINDOW_COCOA_WINDOW_POINTER);
		return false;
	}

	impl->contentView = impl->nsWindow.contentView;
	impl->metalDevice = MTLCreateSystemDefaultDevice();
	if (impl->metalDevice == nil) {
		LOG_L(L_ERROR, "[MacSDL3EGL::%s] MTLCreateSystemDefaultDevice returned nil", __func__);
		return false;
	}

	impl->metalLayer = [[CAMetalLayer layer] retain];
	impl->metalLayer.device = impl->metalDevice;
	impl->metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
	impl->metalLayer.framebufferOnly = YES;
	impl->metalLayer.opaque = YES;
	impl->metalLayer.displaySyncEnabled = YES;
	impl->metalLayer.presentsWithTransaction = NO;
	impl->metalLayer.delegate = static_cast<id<CALayerDelegate>>(impl->contentView);
	impl->contentView.wantsLayer = YES;
	impl->contentView.layer = impl->metalLayer;

	UpdateDrawableSize("initial-owned-layer");
	LOG("[MacSDL3EGL::%s] cocoa nswindow=%p nsview=%p metalDevice=\"%s\" cametallayer=%p pixelFormat=%s(%lu) appOwned=true",
		__func__,
		(__bridge void*)impl->nsWindow,
		(__bridge void*)impl->contentView,
		impl->metalDevice.name.UTF8String,
		(__bridge void*)impl->metalLayer,
		PixelFormatName(impl->metalLayer.pixelFormat),
		static_cast<unsigned long>(impl->metalLayer.pixelFormat)
	);

	impl->display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
	if (impl->display == EGL_NO_DISPLAY) {
		LOG_L(L_ERROR, "[MacSDL3EGL::%s] eglGetDisplay(EGL_DEFAULT_DISPLAY) failed eglGetError=0x%04x", __func__, eglGetError());
		return false;
	}

	EGLint eglMajor = 0;
	EGLint eglMinor = 0;
	if (!eglInitialize(impl->display, &eglMajor, &eglMinor)) {
		LOG_L(L_ERROR, "[MacSDL3EGL::%s] eglInitialize failed eglGetError=0x%04x", __func__, eglGetError());
		return false;
	}

	LOG("[MacSDL3EGL::%s] EGL_VERSION=%d.%d EGL_VENDOR=\"%s\" EGL_VERSION_STRING=\"%s\"",
		__func__, eglMajor, eglMinor,
		eglQueryString(impl->display, EGL_VENDOR),
		eglQueryString(impl->display, EGL_VERSION)
	);

	if (!eglBindAPI(EGL_OPENGL_API)) {
		LOG_L(L_ERROR, "[MacSDL3EGL::%s] eglBindAPI(EGL_OPENGL_API) failed eglGetError=0x%04x", __func__, eglGetError());
		return false;
	}

	if (!ChooseConfig(impl->display, &impl->config))
		return false;

	impl->context = CreateContext(impl->display, impl->config, requestMajor, requestMinor, requestCoreProfile);
	if (impl->context == EGL_NO_CONTEXT)
		return false;

	impl->surface = eglCreateWindowSurface(
		impl->display,
		impl->config,
		reinterpret_cast<EGLNativeWindowType>(&impl->privateSurface),
		nullptr
	);

	if (impl->surface == EGL_NO_SURFACE) {
		LOG_L(L_ERROR, "[MacSDL3EGL::%s] eglCreateWindowSurface target=BarOnMVKPrivateCocoaSurface failed eglGetError=0x%04x",
			__func__, eglGetError());
		return false;
	}

	LOG("[MacSDL3EGL::%s] eglCreateWindowSurface target=BarOnMVKPrivateCocoaSurface surface=%p privateSurface=%p magic=0x%08x version=%u layer=%p size=%ux%u",
		__func__,
		impl->surface,
		&impl->privateSurface,
		impl->privateSurface.magic,
		impl->privateSurface.version,
		impl->privateSurface.metalLayer,
		impl->privateSurface.width,
		impl->privateSurface.height
	);

	if (!MakeCurrent(false))
		return false;

	impl->initialized = true;
	LogContextDiagnostics("after-egl-current-before-glad");
	LogGeometry("after-egl-current");
	return true;
}

void Bridge::Destroy()
{
	if (impl == nullptr)
		return;

	if (impl->display != EGL_NO_DISPLAY)
		eglMakeCurrent(impl->display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);

	if (impl->display != EGL_NO_DISPLAY && impl->surface != EGL_NO_SURFACE) {
		eglDestroySurface(impl->display, impl->surface);
		impl->surface = EGL_NO_SURFACE;
	}

	if (impl->display != EGL_NO_DISPLAY && impl->context != EGL_NO_CONTEXT) {
		eglDestroyContext(impl->display, impl->context);
		impl->context = EGL_NO_CONTEXT;
	}

	if (impl->display != EGL_NO_DISPLAY) {
		eglTerminate(impl->display);
		impl->display = EGL_NO_DISPLAY;
	}

	if (impl->contentView != nil && impl->contentView.layer == impl->metalLayer)
		impl->contentView.layer = nil;

	if (impl->metalLayer != nil) {
		[impl->metalLayer release];
		impl->metalLayer = nil;
	}

	if (impl->metalDevice != nil) {
		[impl->metalDevice release];
		impl->metalDevice = nil;
	}

	impl->privateSurface = {};
	impl->window = nullptr;
	impl->nsWindow = nil;
	impl->contentView = nil;
	impl->initialized = false;
}

bool Bridge::MakeCurrent(bool clear) const
{
	if (impl->display == EGL_NO_DISPLAY)
		return false;

	const EGLSurface draw = clear ? EGL_NO_SURFACE : impl->surface;
	const EGLSurface read = clear ? EGL_NO_SURFACE : impl->surface;
	const EGLContext context = clear ? EGL_NO_CONTEXT : impl->context;

	if (eglMakeCurrent(impl->display, draw, read, context))
		return true;

	LOG_L(L_ERROR, "[MacSDL3EGL::%s] eglMakeCurrent(clear=%d) failed eglGetError=0x%04x", __func__, int(clear), eglGetError());
	return false;
}

bool Bridge::SwapBuffers()
{
	UpdateDrawableSize("pre-swap");
	if (eglSwapBuffers(impl->display, impl->surface))
		return true;

	LOG_L(L_ERROR, "[MacSDL3EGL::%s] eglSwapBuffers failed eglGetError=0x%04x", __func__, eglGetError());
	return false;
}

void Bridge::UpdateDrawableSize(const char* reason)
{
	if (impl->metalLayer == nil)
		return;

	const CGSize drawable = UpdateLayerDrawableSize(impl->nsWindow, impl->contentView, impl->metalLayer, reason);
	impl->privateSurface.magic = BAR_ON_MVK_COCOA_EGL_SURFACE_MAGIC;
	impl->privateSurface.version = BAR_ON_MVK_COCOA_EGL_SURFACE_VERSION;
	impl->privateSurface.metalLayer = (__bridge void*)impl->metalLayer;
	impl->privateSurface.width = static_cast<uint32_t>(std::max(0.0, static_cast<double>(drawable.width)));
	impl->privateSurface.height = static_cast<uint32_t>(std::max(0.0, static_cast<double>(drawable.height)));
}

void* Bridge::GetContextOpaque() const
{
	return impl->context;
}

bool Bridge::IsInitialized() const
{
	return impl->initialized;
}

int Bridge::GetSwapInterval() const
{
	return SDL_GL_GetSwapInterval();
}

uint64_t Bridge::GetRecommendedMaxWorkingSetSizeBytes() const
{
	if (impl == nullptr || impl->metalDevice == nil)
		return 0;

	return static_cast<uint64_t>(impl->metalDevice.recommendedMaxWorkingSetSize);
}

void Bridge::LogRuntimeEnvironment() const
{
	if (!LOG_IS_ENABLED(L_DEBUG))
		return;

	LOG_L(L_DEBUG, "[MacSDL3EGL::%s] SDL3 Cocoa + Mesa EGL runtime env VK_DRIVER_FILES=%s MESA_LOADER_DRIVER_OVERRIDE=%s GALLIUM_DRIVER=%s EGL_PLATFORM=%s MESA_GL_VERSION_OVERRIDE=%s MESA_GLSL_VERSION_OVERRIDE=%s VK_ICD_FILENAMES=%s VK_ADD_DRIVER_FILES=%s DYLD_LIBRARY_PATH=%s DYLD_FALLBACK_LIBRARY_PATH=%s",
		__func__,
		EnvValue("VK_DRIVER_FILES"),
		EnvValue("MESA_LOADER_DRIVER_OVERRIDE"),
		EnvValue("GALLIUM_DRIVER"),
		EnvValue("EGL_PLATFORM"),
		EnvValue("MESA_GL_VERSION_OVERRIDE"),
		EnvValue("MESA_GLSL_VERSION_OVERRIDE"),
		EnvValue("VK_ICD_FILENAMES"),
		EnvValue("VK_ADD_DRIVER_FILES"),
		EnvValue("DYLD_LIBRARY_PATH"),
		EnvValue("DYLD_FALLBACK_LIBRARY_PATH")
	);
}

void Bridge::LogContextDiagnostics(const char* phase) const
{
	if (!LOG_IS_ENABLED(L_DEBUG))
		return;

	if (impl->display != EGL_NO_DISPLAY) {
		LOG_L(L_DEBUG, "[MacSDL3EGL::%s] phase=%s EGL_VENDOR=\"%s\" EGL_VERSION=\"%s\" EGL_EXTENSIONS=\"%s\"",
			__func__, phase,
			eglQueryString(impl->display, EGL_VENDOR),
			eglQueryString(impl->display, EGL_VERSION),
			eglQueryString(impl->display, EGL_EXTENSIONS)
		);
	}

	PFNGLGETSTRINGPROC_LOCAL glGetStringLocal =
		reinterpret_cast<PFNGLGETSTRINGPROC_LOCAL>(eglGetProcAddress("glGetString"));
	if (glGetStringLocal == nullptr)
		return;

	LOG_L(L_DEBUG, "[MacSDL3EGL::%s] phase=%s GL_VENDOR=\"%s\" GL_RENDERER=\"%s\" GL_VERSION=\"%s\" GL_SHADING_LANGUAGE_VERSION=\"%s\"",
		__func__, phase,
		reinterpret_cast<const char*>(glGetStringLocal(GL_VENDOR_LOCAL)),
		reinterpret_cast<const char*>(glGetStringLocal(GL_RENDERER_LOCAL)),
		reinterpret_cast<const char*>(glGetStringLocal(GL_VERSION_LOCAL)),
		reinterpret_cast<const char*>(glGetStringLocal(GL_SHADING_LANGUAGE_VERSION_LOCAL))
	);
}

void Bridge::LogGeometry(const char* phase) const
{
	LogDisplayGeometry(impl->window, phase);
}

} // namespace MacSDL3EGL
