#include <SDL3/SDL.h>
#include <assert.h>
#include <stdio.h>
int main(void){
 assert(SDL_Init(SDL_INIT_VIDEO));
 SDL_Window *window=SDL_CreateWindow("private dummy test",1512,982,SDL_WINDOW_RESIZABLE|SDL_WINDOW_FULLSCREEN);
 assert(window&&(SDL_GetWindowFlags(window)&SDL_WINDOW_HIDDEN));
 assert(SDL_ShowWindow(window));assert(SDL_RaiseWindow(window));assert(SDL_RestoreWindow(window));
 assert(SDL_SetWindowFullscreen(window,true));
 assert(SDL_GetWindowFlags(window)&SDL_WINDOW_HIDDEN);
 assert(SDL_GetWindowFlags(window)&SDL_WINDOW_FULLSCREEN);
 SDL_DestroyWindow(window);SDL_Quit();puts("PASS actual SDL accepts fullscreen flag and request while remaining hidden; show/raise/restore blocked");
 return 0;
}
