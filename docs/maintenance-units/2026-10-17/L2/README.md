# L2: device callback lock ownership

Move device creation/destruction locking together from public Vulkan trampolines into the shared Loader callbacks. Public entry points and direct layer callbacks now acquire the same recursive loader lock; failure paths release through common cleanup. Earlier L5 pNext restoration and L1 surface locking remain intact.

The complete [patch](change.patch) includes the exact official five-file change from KhronosGroup/Vulkan-Loader commit `6b45d76280a9525740c38c1796060eadb9267488` plus82 test-only added lines in the existing threading target. The official new case enables a GetQueue hook without calling GetQueue; the supplement explicitly exercises it for success, initialization failure and device-memory failure. Each case records32 callback create attempts, one successful retry from a fresh worker, and zero live devices after owner cleanup.

HQ and the applied-code audit accept13 final production cases:8 unit-specific and5 cumulative L1 WSI cases, all on raw SHA256 `90f8a48234bd14d5eb19154a1104a27b555dd9c6b2750e4568636b108c0b8920`. The cumulative five used the same binary and executables without another build or rerunning the first eight. Product flags/link, cache values/types,1015 exported names, dependencies and install name are preserved; cache bytes are not claimed identical.

[Manifest](manifest.json), [recipe](recipe.md), [validation](validation.json), and [applied audit](applied-audit.json) bind the reconstructible public port base and exact input hashes. Public receipt paths are rebased to `$WORKSPACE`.

Ordinary mock checks do not establish sanitizer-backed race freedom, all interleavings or exhaustive allocation failures. No GPU/window/app/game/FPS/MP/endurance acceptance or app/Release/Homebrew update is included.
