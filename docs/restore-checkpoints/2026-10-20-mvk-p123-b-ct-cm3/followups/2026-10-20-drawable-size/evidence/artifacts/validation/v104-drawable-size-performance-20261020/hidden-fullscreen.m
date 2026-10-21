#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <SDL3/SDL.h>
#include <libproc.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdatomic.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

// Private capture sidecar only. No NSWindow method rewriting, file patching,
// simulation callbacks or GPU operations. A visible fallback is never used.
static IMP policyOriginal,finishOriginal;
static int auditFD=-1;
static _Atomic unsigned records=0;
__attribute__((noreturn)) static void hiddenFailure(const char *reason){
 char line[256];int n=snprintf(line,sizeof(line),"{\"pid\":%d,\"event\":\"hidden-window-failure\",\"reason\":\"%s\"}\n",getpid(),reason);
 if(n>0&&(size_t)n<sizeof(line)){if(auditFD>=0)(void)write(auditFD,line,(size_t)n);(void)write(STDERR_FILENO,line,(size_t)n);}
 _exit(86);
}
static void windowAudit(const char *event,unsigned long long flags){
 if(atomic_fetch_add(&records,1)>80)return;
 char line[256];int n=snprintf(line,sizeof(line),"{\"pid\":%d,\"event\":\"%s\",\"flags\":%llu}\n",getpid(),event,flags);
 if(auditFD<0||n<=0||write(auditFD,line,(size_t)n)!=n)hiddenFailure("audit-write");
}
static BOOL prohibitPolicy(id app,SEL selector,NSApplicationActivationPolicy requested){
 (void)requested;
 return ((BOOL(*)(id,SEL,NSApplicationActivationPolicy))policyOriginal)(app,selector,NSApplicationActivationPolicyProhibited);
}
static void finishHidden(id app,SEL selector){
 BOOL changed=((BOOL(*)(id,SEL,NSApplicationActivationPolicy))policyOriginal)(app,@selector(setActivationPolicy:),NSApplicationActivationPolicyProhibited);
 NSApplicationActivationPolicy actual=[(NSApplication *)app activationPolicy];
 // flags encode actual+1 so -1 remains representable without unsigned overflow.
 windowAudit(changed?"hidden-policy-switch-accepted":"hidden-policy-switch-rejected",(unsigned long long)(actual+1));
 if(actual!=NSApplicationActivationPolicyProhibited)hiddenFailure("finish-policy-not-prohibited");
 ((void(*)(id,SEL))finishOriginal)(app,selector);
 actual=[(NSApplication *)app activationPolicy];
 windowAudit("hidden-policy-after-finish",(unsigned long long)(actual+1));
 if(actual!=NSApplicationActivationPolicyProhibited)hiddenFailure("finished-policy-not-prohibited");
}
static void noActivate(id app,SEL selector,BOOL flag){(void)app;(void)selector;(void)flag;}
static void noActivateNew(id app,SEL selector){(void)app;(void)selector;}
static IMP replace(Class cls,SEL selector,IMP replacement,const char *returnType,unsigned args){
 Method method=class_getInstanceMethod(cls,selector);
 if(!method||method_getNumberOfArguments(method)!=args)hiddenFailure("method-arity");
 char *actual=method_copyReturnType(method);BOOL good=actual&&!strcmp(actual,returnType);free(actual);
 if(!good)hiddenFailure("method-return-type");
 return method_setImplementation(method,replacement);
}
__attribute__((constructor)) static void installHidden(){
 const char *expected=getenv("BAR_BG_ENGINE_PATH"),*log=getenv("BAR_BG_WINDOW_LOG");
 char executable[PROC_PIDPATHINFO_MAXSIZE]={0};
 if(!expected||!log||proc_pidpath(getpid(),executable,sizeof(executable))<=0||strcmp(expected,executable))hiddenFailure("engine-identity");
 if(strcmp(getenv("SDL_MAC_BACKGROUND_APP")?:"","1"))hiddenFailure("background-hint");
 auditFD=open(log,O_WRONLY|O_APPEND|O_NOFOLLOW);
 if(auditFD<0)hiddenFailure("audit-open");
 policyOriginal=replace(NSApplication.class,@selector(setActivationPolicy:),(IMP)prohibitPolicy,@encode(BOOL),3);
 finishOriginal=replace(NSApplication.class,@selector(finishLaunching),(IMP)finishHidden,"v",2);
 replace(NSApplication.class,@selector(activateIgnoringOtherApps:),(IMP)noActivate,"v",3);
 if(class_getInstanceMethod(NSApplication.class,NSSelectorFromString(@"activate")))
   replace(NSApplication.class,NSSelectorFromString(@"activate"),(IMP)noActivateNew,"v",2);
 windowAudit("hidden-window-guard-loaded",0);
}
static SDL_Window *hiddenCreate(const char *title,int width,int height,SDL_WindowFlags flags){
 if(width<1||height<1)hiddenFailure("window-size");
 SDL_WindowFlags safe=flags|SDL_WINDOW_HIDDEN|SDL_WINDOW_NOT_FOCUSABLE;
 windowAudit("create-forced-hidden",safe);
 SDL_Window *window=SDL_CreateWindow(title,width,height,safe);
 if(window){
   SDL_WindowFlags actual=SDL_GetWindowFlags(window);
   if(!(actual&SDL_WINDOW_HIDDEN)||((actual&SDL_WINDOW_FULLSCREEN)!=(flags&SDL_WINDOW_FULLSCREEN)))hiddenFailure("created-window-flags");
   windowAudit("created-hidden-verified",actual);
 }
 return window;
}
static bool blockedShow(SDL_Window *window){(void)window;windowAudit("show-blocked",0);return true;}
static bool blockedRaise(SDL_Window *window){(void)window;windowAudit("raise-blocked",0);return true;}
static bool blockedRestore(SDL_Window *window){(void)window;windowAudit("restore-blocked",0);return true;}
static bool hiddenFullscreen(SDL_Window *window,bool enabled){
 if(!(SDL_GetWindowFlags(window)&SDL_WINDOW_HIDDEN))hiddenFailure("fullscreen-requires-hidden");
 bool accepted=SDL_SetWindowFullscreen(window,enabled);
 SDL_WindowFlags actual=SDL_GetWindowFlags(window);
 if(!accepted||!(actual&SDL_WINDOW_HIDDEN)||!!(actual&SDL_WINDOW_FULLSCREEN)!=enabled)hiddenFailure("fullscreen-hidden-flags");
 NSWindow *native=(NSWindow *)SDL_GetPointerProperty(SDL_GetWindowProperties(window),SDL_PROP_WINDOW_COCOA_WINDOW_POINTER,NULL);
 if(native!=nil&&[native isVisible])hiddenFailure("fullscreen-native-window-visible");
 windowAudit(enabled?"fullscreen-enabled-hidden":"fullscreen-disabled-hidden",actual);
 return accepted;
}
#define INTERPOSE(replacement,original) \
 __attribute__((used)) static struct {const void *replace;const void *original;} \
 binding_##original __attribute__((section("__DATA,__interpose")))={(const void *)&replacement,(const void *)&original}
INTERPOSE(hiddenCreate,SDL_CreateWindow);
INTERPOSE(blockedShow,SDL_ShowWindow);
INTERPOSE(blockedRaise,SDL_RaiseWindow);
INTERPOSE(blockedRestore,SDL_RestoreWindow);
INTERPOSE(hiddenFullscreen,SDL_SetWindowFullscreen);
