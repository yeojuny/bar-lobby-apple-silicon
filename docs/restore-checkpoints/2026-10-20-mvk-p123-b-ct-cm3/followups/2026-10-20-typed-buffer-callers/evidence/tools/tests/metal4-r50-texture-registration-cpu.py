#!/usr/bin/env python3
"""Exact r50 registration methods and submission code; no Metal device or GPU.

The encoder shell counts calls into the real production submission. It does not
replace retention, residency, drawable lookup, or recording-token behavior.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK"
OUT = ROOT / "artifacts/validation/metal4-r50-binding-reuse-20261004/cpu-registration"
if len(sys.argv) > 1:
    OUT = Path(sys.argv[1]).resolve()
OUT.mkdir(parents=True, exist_ok=False)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

state = (CORE / "Commands/MVKCommandEncoderState.mm").read_text()
header = (CORE / "Commands/MVKCommandEncoderState.h").read_text()
descriptor = (CORE / "GPUObjects/MVKDescriptorSet.h").read_text()

def block(text, anchor):
    start = text.index(anchor)
    index = text.index("{", start) + 1
    depth = 1
    while depth:
        depth += (text[index] == "{") - (text[index] == "}")
        index += 1
    return text[start:index]

fields_start = header.index("\tid<MTLRenderPipelineState> _metal4GraphicsPipeline")
fields = header[fields_start:header.index("\n#endif", fields_start)]
# The unrelated stage-preparation cache is only reset by these methods. Keep an
# opaque resettable slot in this registration shell, without emulating its binder.
fields = fields.replace("MVKMetal4StagePreparation _metal4StagePreparation[kMVKShaderStageCount]",
                        "std::array<unsigned, 1> _metal4StagePreparation")
helper_start = descriptor.index("struct MVKMetal4DescriptorPreparationStamp {")
helpers = descriptor[helper_start:descriptor.index("\n#endif", helper_start)]
flags = block(descriptor, "enum MVKDescriptorBindingFlagBits {") + ";"
methods = "\n\n".join(block(state, "bool MVKCommandEncoderState::" + name + "(")
                       for name in ("prepareMetal4ResourceRegistration", "registerMetal4Buffer",
                                    "registerMetal4Texture", "retainMetal4Object"))
sink = block(state, "struct Metal4BindingSink {") + ";"
failure = block(state, "static bool metal4Failure(")
# This fixture executes registration, not the indirect binder. The old R50
# binder baseline predates the separately accepted R71/R4/R5 changes.
assert "if (!resource(value))" in sink and "registerMetal4Texture(encoder, value)" in sink

preamble = r'''
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <vulkan/vulkan.h>
#include "MVKMetal4TextureRegistrationCache.h"
#include "MVKMetal4PreparedResource.h"
#include <unordered_set>
'''
# Reuse only the exact NSObject test doubles; that older fixture's unrelated
# private-state retirement tests predate the current shared allocator storage.
mock_source = (ROOT / "tools/tests/metal4-r47-retirement-cpu.mm").read_text()
preamble += mock_source[:mock_source.index("\nnamespace {")]
shell = r'''
class MVKCommandEncoder;
class MVKCommandEncoderState {
public:
''' + fields + r'''
    bool prepareMetal4ResourceRegistration(MVKCommandEncoder&);
    bool registerMetal4Buffer(MVKCommandEncoder&, id<MTLBuffer>);
    bool registerMetal4Texture(MVKCommandEncoder&, id<MTLTexture>);
    bool retainMetal4Object(MVKCommandEncoder&, id);
};
struct Recording {
    std::shared_ptr<MVKMetal4Submission> batch;
    unsigned calls = 0;
    std::function<void()> afterRegistration;
    id<MTL4CommandBuffer> commandBuffer() const { return batch->commandBuffer(); }
    auto recordingToken() const { return batch->recordingToken(); }
    bool matchesRecordingToken(const std::weak_ptr<void>& token) const { return batch->matchesRecordingToken(token); }
    bool retainObject(id object, NSError** error) { return batch->retainObject(object, error); }
    bool addResource(id<MTLResource> object, NSError** error) {
        ++calls;
        bool okay = batch->addResource(object, error);
        if (okay && afterRegistration) { auto hook = std::move(afterRegistration); hook(); }
        return okay;
    }
    bool addBufferResource(id<MTLBuffer> object, NSError** error) {
        ++calls;
        bool okay = batch->addBufferResource(object, error);
        if (okay && afterRegistration) { auto hook = std::move(afterRegistration); hook(); }
        return okay;
    }
    bool addTextureResource(id<MTLTexture> object, NSError** error) {
        ++calls;
        bool okay = batch->addTextureResource(object, error);
        if (okay && afterRegistration) { auto hook = std::move(afterRegistration); hook(); }
        return okay;
    }
};
class MVKCommandEncoder {
public:
    MVKCommandEncoderState state;
    Recording recording;
    bool failed = false;
    Recording* getMetal4Submission() { return recording.batch ? &recording : nullptr; }
    MVKCommandEncoderState& getState() { return state; }
    MVKMetal4ArgumentTables* getMetal4ArgumentTables() { return nullptr; }
    void failMetal4Encoding(const char*) { failed = true; }
};
using Metal4Stage = MVKMetal4ArgumentTables::Stage;
'''
# The unused byte-binding sink requires the exact submission reference, whereas
# this fixture's wrapper counts only resource calls. Extract the exercised sink
# methods without changing their bodies.
sink = "struct Metal4BindingSink { MVKCommandEncoder& encoder; Metal4Stage stage;\n" + block(sink, "bool resource(") + "\n};"

fixture = r'''
@interface R50Texture : R47Allocation {
@public R50Texture* parent; unsigned* deaths; unsigned* protocolChecks;
}
@end
@implementation R50Texture
- (BOOL)conformsToProtocol:(Protocol*)protocol {
    if (protocol == @protocol(MTLTexture) && protocolChecks) { ++*protocolChecks; }
    return protocol == @protocol(MTLTexture) || protocol == @protocol(MTLResource) || [super conformsToProtocol:protocol];
}
- (id<MTLHeap>)heap { return nil; }
- (id<MTLTexture>)parentTexture { return (id<MTLTexture>)parent; }
- (void)dealloc { if (deaths) { ++*deaths; } [parent release]; [super dealloc]; }
@end

@interface R50Buffer : R47Allocation {
@public unsigned* protocolChecks; unsigned* deaths;
}
@end
@implementation R50Buffer
- (BOOL)conformsToProtocol:(Protocol*)protocol {
    if (protocol == @protocol(MTLTexture) && protocolChecks) { ++*protocolChecks; }
    return protocol == @protocol(MTLBuffer) || protocol == @protocol(MTLResource) || [super conformsToProtocol:protocol];
}
- (id<MTLHeap>)heap { return nil; }
- (void)dealloc { if (deaths) { ++*deaths; } [super dealloc]; }
@end

static R50Texture* texture(R47Device* device, R50Texture* parent = nil) {
    auto* value = [R50Texture new]; value->device = (id<MTLDevice>)device;
    value->parent = [parent retain]; return value;
}
static void start(MVKCommandEncoder& encoder, MVKMetal4Queue& queue) {
    NSError* error = nil; encoder.recording.batch = queue.begin(&error); encoder.failed = false;
    require(encoder.recording.batch && encoder.state.prepareMetal4ResourceRegistration(encoder), "fresh recording prepared");
}
static void cancel(MVKCommandEncoder& encoder) {
    NSError* error = nil; require(encoder.recording.batch->end(&error), "end before cancellation");
    encoder.recording.batch.reset();
}
static void cacheBounds() {
    using Cache = MVKMetal4TextureRegistrationCache;
    static_assert(sizeof(Cache) == 4096, "fixed storage has no node allocation");
    Cache cache; const void* a = reinterpret_cast<void*>(16);
    require(!cache.matches(a, 1) && !cache.matches(nullptr, 1), "empty and nil miss");
    cache.remember(a, 0); cache.remember(a, UINT64_MAX);
    require(!cache.matches(a, 0) && !cache.matches(a, UINT64_MAX), "zero and saturated generations never admit");
    cache.remember(a, 1); require(cache.matches(a, 1) && !cache.matches(a, 2), "exact generation only");
    cache.clear(); require(!cache.matches(a, 1), "recording reset clears memo");
    for (uintptr_t i = 1; i <= 257; ++i) {
        const void* value = reinterpret_cast<void*>(i << 4);
        cache.remember(value, 3); require(cache.matches(value, 3), "exact object admitted after collision replacement");
    }
    unsigned hits = 0;
    for (uintptr_t i = 1; i <= 257; ++i) { hits += cache.matches(reinterpret_cast<void*>(i << 4), 3); }
    require(hits <= 256 && hits > 0, "bounded collisions only cause misses");
}
static void typedRegistrationEquivalence() {
    for (bool typed : {false, true}) {
        auto* device = [R47Device new]; auto* foreign = [R47Device new]; NSError* error = nil;
        auto residency = MVKMetal4DeviceResidency::create((id<MTLDevice>)device, &error);
        auto pool = MVKMetal4RecordingPool::create((id<MTLDevice>)device, &error, residency);
        require(bool(pool), "recording pool with actual residency implementation");
        auto batch = pool->begin(&error);
        unsigned bufferChecks = 0, textureChecks = 0, bufferDeaths = 0, textureDeaths = 0;
        auto* buffer = [R50Buffer new]; buffer->device = (id<MTLDevice>)device;
        buffer->protocolChecks = &bufferChecks; buffer->deaths = &bufferDeaths;
        auto* value = texture(device); value->protocolChecks = &textureChecks; value->deaths = &textureDeaths;
        auto addBuffer = [&](R50Buffer* b) { return typed ? batch->addBufferResource((id<MTLBuffer>)b, &error) : batch->addResource((id<MTLResource>)b, &error); };
        auto addTexture = [&](R50Texture* t) { return typed ? batch->addTextureResource((id<MTLTexture>)t, &error) : batch->addResource((id<MTLResource>)t, &error); };
        require(!addBuffer(nil) && error.code == 3 && !addTexture(nil) && error.code == 3, "nil rejects identically");
        auto* wrongBuffer = [R50Buffer new]; wrongBuffer->device = (id<MTLDevice>)foreign;
        auto* wrongTexture = texture(foreign);
        require(!addBuffer(wrongBuffer) && error.code == 3 && !addTexture(wrongTexture) && error.code == 3, "foreign device rejects identically");
        [wrongBuffer release]; [wrongTexture release];
        require(batch->retainObject(buffer, &error) && batch->retainObject(value, &error), "retain before registering");
        require(addBuffer(buffer) && !error && addTexture(value) && !error, "unregistered resources retain dynamic fallback");
        require(bufferChecks == unsigned(!typed) && textureChecks == unsigned(!typed), "generic classifies once through residency fallback; typed classifies zero times");
        require(addBuffer(buffer) && addTexture(value), "repeat registration succeeds");
        auto stats = batch->resourceRegistrationStats();
        require(stats.retainedObjects == 2 && stats.residentResources == 2 && stats.deviceResidencyLeases == 0, "types imply neither ownership nor residency");
        require(bufferChecks == unsigned(!typed) && textureChecks == unsigned(!typed), "resident hit does not classify again");
        auto second = pool->begin(&error);
        require(second->addBufferResource((id<MTLBuffer>)buffer, &error) && second->addTextureResource((id<MTLTexture>)value, &error), "second recording independently registers");
        require(second->resourceRegistrationStats().residentResources == 2, "recording resource ownership remains separate");
        require(batch->end(&error), "end registration batch");
        require(!addBuffer(buffer) && error.code == 3 && !addTexture(value) && error.code == 3, "ended recording rejects previously resident objects");
        [buffer release]; [value release]; batch.reset();
        require(bufferDeaths == 0 && textureDeaths == 0, "second recording retains after first cancellation");
        second.reset();
        require(bufferDeaths == 1 && textureDeaths == 1, "recording cancellation releases both resource kinds");
        // Unknown views must still acquire the registered parent's lease.
        auto* base = texture(device); auto* view = texture(device, base); unsigned viewChecks = 0; view->protocolChecks = &viewChecks;
        require(residency->registerAllocation((id<MTLAllocation>)base, &error), "register parent allocation");
        std::weak_ptr<void> lease = residency->lease((id<MTLResource>)view);
        require(!lease.expired() && viewChecks == 1, "public generic lease retains texture ancestry discovery");
        viewChecks = 0; batch = pool->begin(&error);
        require(addTexture(view) && viewChecks == unsigned(!typed), "known type reaches parent lookup without second classification");
        require(batch->resourceRegistrationStats().deviceResidencyLeases == 1, "view registration acquires parent lease");
        residency->unregisterAllocation((id<MTLAllocation>)base); [view release]; [base release];
        require(!lease.expired(), "parent lease survives allocation-owner release");
        batch.reset(); require(lease.expired(), "parent lease retires at cancellation");
        pool.reset(); residency.reset(); [foreign release]; [device release];
    }
}
static void reuseAndRecording() {
    auto* device = [R47Device new]; NSError* error = nil; auto queue = MVKMetal4Queue::create((id<MTLDevice>)device, &error);
    require(bool(queue), "CPU mock queue");
    MVKCommandEncoder encoder; start(encoder, *queue);
    Metal4BindingSink sink{encoder, Metal4Stage::Fragment};
    auto* value = texture(device); unsigned deaths = 0; value->deaths = &deaths;
    require(sink.resource(nil) && encoder.recording.calls == 0, "nil adds no registration");
    for (unsigned i = 0; i < 32; ++i) { require(sink.resource((id<MTLTexture>)value), "unchanged texture usable"); }
    require(encoder.recording.calls == 1 && encoder.recording.batch->resourceRegistrationStats().residentResources == 1,
            "32 unchanged binding fallbacks enter actual addResource once");
    require(encoder.state.prepareMetal4ResourceRegistration(encoder) && sink.resource((id<MTLTexture>)value) && encoder.recording.calls == 1,
            "same recording preparation preserves reuse");
    auto old = encoder.recording.batch; cancel(encoder); start(encoder, *queue);
    require(sink.resource((id<MTLTexture>)value) && encoder.recording.calls == 2, "new token re-registers even while old token survives");
    [value release]; require(deaths == 0, "actual submissions pin texture");
    cancel(encoder); require(deaths == 0, "older submission retains its own lifetime");
    old.reset(); require(deaths == 1, "memo does not own or prolong texture");
    require(!encoder.state.prepareMetal4ResourceRegistration(encoder) && encoder.failed, "missing recording rejects before reuse");
    start(encoder, *queue); require(encoder.recording.batch->end(&error), "end recording");
    require(!encoder.state.prepareMetal4ResourceRegistration(encoder) && encoder.failed, "ended recording cannot hit stale memo");
    encoder.recording.batch.reset(); queue.reset(); [device release];
}
static void drawableAndConcurrentMutation() {
    auto* device = [R47Device new]; NSError* error = nil; auto queue = MVKMetal4Queue::create((id<MTLDevice>)device, &error);
    MVKCommandEncoder encoder; start(encoder, *queue); Metal4BindingSink sink{encoder, Metal4Stage::Vertex};
    auto* base = texture(device); auto* view = texture(device, base);
    auto* first = [NSObject new]; auto* second = [NSObject new];
    require(sink.resource((id<MTLTexture>)view), "unregistered view first use");
    require(mvkRegisterMetal4Drawable((id<MTLTexture>)base, (id<MTLDrawable>)first, &error), "register base drawable");
    require(sink.resource((id<MTLTexture>)view) && encoder.recording.calls == 2 &&
            encoder.recording.batch->resourceRegistrationStats().retainedObjects == 2, "generation change finds and retains view parent drawable");
    mvkUnregisterMetal4Drawable((id<MTLTexture>)base, (id<MTLDrawable>)first);
    require(mvkRegisterMetal4Drawable((id<MTLTexture>)base, (id<MTLDrawable>)second, &error), "replace drawable snapshot");
    require(sink.resource((id<MTLTexture>)view) && encoder.recording.calls == 3 &&
            encoder.recording.batch->resourceRegistrationStats().retainedObjects == 3, "same texture now retains second drawable");
    mvkUnregisterMetal4Drawable((id<MTLTexture>)base, (id<MTLDrawable>)second);
    require(sink.resource((id<MTLTexture>)view) && encoder.recording.calls == 4, "drawable removal invalidates memo");
    auto* raced = texture(device);
    encoder.recording.afterRegistration = [&] { require(mvkRegisterMetal4Drawable((id<MTLTexture>)raced, (id<MTLDrawable>)first, &error), "mutation after registration"); };
    require(sink.resource((id<MTLTexture>)raced) && encoder.recording.calls == 5, "first registration with mutation hook");
    require(sink.resource((id<MTLTexture>)raced) && encoder.recording.calls == 6 &&
            encoder.recording.batch->resourceRegistrationStats().retainedObjects == 4, "pre-call generation cannot hide concurrent drawable addition");
    require(sink.resource((id<MTLTexture>)raced) && encoder.recording.calls == 6, "revalidated generation reuses safely");
    mvkUnregisterMetal4Drawable((id<MTLTexture>)raced, (id<MTLDrawable>)first);
    [first release]; [second release]; [base release]; [view release]; [raced release];
    cancel(encoder); queue.reset(); [device release];
}
static void failuresAndSaturation() {
    auto* device = [R47Device new]; auto* foreign = [R47Device new]; NSError* error = nil;
    auto queue = MVKMetal4Queue::create((id<MTLDevice>)device, &error);
    MVKCommandEncoder encoder; start(encoder, *queue); Metal4BindingSink sink{encoder, Metal4Stage::Fragment};
    auto* value = texture(foreign);
    require(!sink.resource((id<MTLTexture>)value) && encoder.failed && encoder.recording.calls == 1,
            "wrong device rejects with original failure");
    require(!sink.resource((id<MTLTexture>)value) && encoder.recording.calls == 2 &&
            encoder.recording.batch->resourceRegistrationStats().retainedObjects == 0, "failed registration never admits a cache hit");
    [value release]; value = texture(device);
    auto before = drawableRegistryGeneration.load();
    drawableRegistryGeneration.store(UINT64_MAX, std::memory_order_release);
    require(sink.resource((id<MTLTexture>)value) && sink.resource((id<MTLTexture>)value) && encoder.recording.calls == 4,
            "saturated generation keeps original registration on every use");
    require(encoder.recording.batch->resourceRegistrationStats().drawableRegistryLookups == 2, "saturation still rechecks drawable ancestry");
    [value release]; cancel(encoder); queue.reset(); [device release]; [foreign release];
    drawableRegistryGeneration.store(before, std::memory_order_release); // Isolated test fixture only.
}
int main() {
    @autoreleasepool {
        try {
            cacheBounds(); typedRegistrationEquivalence(); reuseAndRecording(); drawableAndConcurrentMutation(); failuresAndSaturation();
            require(drawableRegistry.empty(), "fixture leaves no registered drawables");
            std::printf("{\"passed\":true,\"assertions\":%u,\"unchangedBindingUses\":32,\"actualRegistrationCalls\":1}\n", assertions);
            return 0;
        } catch (const std::exception& error) {
            std::fprintf(stderr, "r50 CPU registration assertion failed: %s\n", error.what()); return 1;
        }
    }
}
'''
cpp = OUT / "registration-exact.mm"
cpp.write_text(preamble + flags + helpers + shell + failure + methods + sink + fixture)
files = [Path(__file__), CORE / "Commands/MVKCommandEncoderState.h", CORE / "Commands/MVKCommandEncoderState.mm",
         CORE / "Commands/MVKMetal4TextureRegistrationCache.h", CORE / "GPUObjects/MVKDescriptorSet.h",
         CORE / "GPUObjects/MVKMetal4PreparedResource.h", CORE / "GPUObjects/MVKMetal4Submission.h",
         CORE / "GPUObjects/MVKMetal4Submission.mm", ROOT / "tools/tests/metal4-r47-retirement-cpu.mm",
         CORE / "Commands/MVKMetal4ArgumentTable.h", CORE / "Commands/MVKMetal4ArgumentTable.mm",
         CORE / "GPUObjects/MVKBackendTimeline.cpp", CORE / "GPUObjects/MVKBackendTimeline.h"]
pins = {str(p.relative_to(ROOT)): sha(p) for p in files}
exe = OUT / "registration-exact"
command = ["/usr/bin/xcrun", "clang++", "-std=c++17", "-fno-objc-arc", "-fblocks", "-mmacosx-version-min=27.0",
           "-Wall", "-Wextra", "-Werror", "-O1", "-g", "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
           "-framework", "Foundation", "-framework", "Metal", "-I" + str(ROOT / "tools/tests"),
           "-I" + str(ROOT / "build/run66-vulkan-headers-src-20260903/include"), "-I" + str(CORE / "GPUObjects"),
           "-I" + str(CORE / "Commands"), str(cpp), str(CORE / "Commands/MVKMetal4ArgumentTable.mm"),
           str(CORE / "GPUObjects/MVKBackendTimeline.cpp"), "-o", str(exe)]
compiled = subprocess.run(command, capture_output=True, text=True, timeout=60)
(OUT / "compile.log").write_text(compiled.stdout + compiled.stderr)
receipt = dict(compileCommand=command, inputs=pins, compileExitCode=compiled.returncode, gpuExecuted=False,
               gameExecuted=False, nativeDeviceCreated=False, sharedMoltenVKLinked=False,
               exactMethodsSha256=hashlib.sha256(methods.encode()).hexdigest(),
               indirectBinderExecuted=False, productionRegistrationMethodsExtracted=True, generatedFixtureSha256=sha(cpp))
code = compiled.returncode
if code == 0:
    env = os.environ.copy()
    env.update(MVK_CONFIG_BACKEND_TIMELINE="0", MVK_CONFIG_BACKEND_COST_STATS="0", MVK_CONFIG_METAL4_STATS="0",
               MVK_CONFIG_METAL4_QUEUE_STATS="0", ASAN_OPTIONS="detect_leaks=0:halt_on_error=1", UBSAN_OPTIONS="halt_on_error=1")
    ran = subprocess.run([str(exe)], capture_output=True, text=True, env=env, timeout=30)
    (OUT / "execution.log").write_text(ran.stdout + ran.stderr)
    code = ran.returncode; receipt.update(runExitCode=code, executableSha256=sha(exe))
    if code == 0: receipt["result"] = json.loads(ran.stdout)
    else: print(ran.stdout + ran.stderr)
else: print(compiled.stdout + compiled.stderr)
receipt["inputsUnchanged"] = pins == {str(p.relative_to(ROOT)): sha(p) for p in files}
(OUT / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(json.dumps({k: v for k, v in receipt.items() if k not in ("inputs", "compileCommand")}))
raise SystemExit(code if code else (0 if receipt["inputsUnchanged"] else 2))
