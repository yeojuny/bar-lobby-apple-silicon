// Native Metal 4 regression harness. No window, drawable, legacy command queue,
// Vulkan facade, or game process is created. Compile the production helpers
// directly; executing this binary is a separate, explicitly authorized GPU step.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "MVKMetal4Submission.h"
#include "MVKMetal4ArgumentTable.h"
#include "MVKMetal4PreparedResource.h"
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <functional>
#include <future>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

static std::atomic<unsigned> sentinelDeaths{0};
@interface MVKFoundationLifetimeSentinel : NSObject
@end
@implementation MVKFoundationLifetimeSentinel
- (void)dealloc { ++sentinelDeaths; [super dealloc]; }
@end

namespace {
constexpr uint64_t kTimeoutMS = 10000;
using Stage = MVKMetal4ArgumentTables::Stage;

template<class T> class Owned {
public:
    explicit Owned(T value = nil) : value(value) {}
    ~Owned() { [value release]; }
    Owned(const Owned&) = delete;
    Owned& operator=(const Owned&) = delete;
    T get() const { return value; }
    void reset() { [value release]; value = nil; }
private:
    T value;
};

void require(bool condition, const std::string& message, NSError* error = nil) {
    if (!condition) {
        std::string detail = error ? std::string([[error localizedDescription] UTF8String]) : "";
        throw std::runtime_error(message + (detail.empty() ? "" : ": " + detail));
    }
}
#define CHECK_API(expression) do { bool result = (expression); require(result, #expression, error); } while (0)

std::unique_ptr<MVKMetal4Queue> makeQueue(id<MTLDevice> device) {
    NSError* error = nil;
    auto queue = MVKMetal4Queue::create(device, &error);
    require(bool(queue), "create native queue", error);
    return queue;
}
std::shared_ptr<MVKMetal4Submission> begin(MVKMetal4Queue& queue) {
    NSError* error = nil;
    auto batch = queue.begin(&error);
    require(bool(batch), "begin native submission", error);
    require(batch->commandBuffer() != nil, "recording command buffer is present");
    return batch;
}
void finish(MVKMetal4Queue& queue, const std::shared_ptr<MVKMetal4Submission>& batch) {
    NSError* error = nil;
    CHECK_API(batch->end(&error));
    require(batch->commandBuffer() == nil, "ended batch does not expose a recording handle");
    CHECK_API(queue.submit(batch, &error));
    CHECK_API(batch->wait(kTimeoutMS, &error));
    CHECK_API(queue.waitIdle(kTimeoutMS, &error));
    require(batch->completed(), "completion was recorded");
}
void intra(id<MTL4ComputeCommandEncoder> encoder, MTLStages source, MTLStages target) {
    [encoder barrierAfterEncoderStages:source beforeEncoderStages:target
                     visibilityOptions:MTL4VisibilityOptionDevice];
}
void reject(const std::function<bool(NSError**)>& operation, const char* label) {
    NSError* error = nil;
    bool accepted = operation(&error);
    require(!accepted && error != nil, std::string("reject with error: ") + label);
}

void stateAndEmptyBatch(id<MTLDevice> device) {
    auto queue = makeQueue(device);
    auto wrong = makeQueue(device);
    auto batch = begin(*queue);
    reject([&](NSError** e) { return batch->wait(0, e); }, "wait recording batch");
    reject([&](NSError** e) { return queue->submit(batch, e); }, "submit recording batch");
    reject([&](NSError** e) { return batch->addResource(nil, e); }, "nil resource");
    reject([&](NSError** e) { return batch->addBufferResource(nil, e); }, "nil typed buffer");
    reject([&](NSError** e) { return batch->addTextureResource(nil, e); }, "nil typed texture");
    reject([&](NSError** e) { return batch->retainObject(nil, e); }, "nil retained object");
    reject([&](NSError** e) { return batch->uploadBytes(nullptr, 4, e) != nil; }, "nil upload");
    NSError* error = nil;
    CHECK_API(batch->end(&error));
    reject([&](NSError** e) { return batch->wait(0, e); }, "wait ended unsubmitted batch");
    reject([&](NSError** e) { return batch->end(e); }, "end twice");
    reject([&](NSError** e) { return wrong->submit(batch, e); }, "wrong queue");
    CHECK_API(queue->submit(batch, &error));
    reject([&](NSError** e) { return queue->submit(batch, e); }, "double submit");
    CHECK_API(batch->wait(kTimeoutMS, &error));
    CHECK_API(queue->waitIdle(kTimeoutMS, &error));
    CHECK_API(wrong->waitIdle(kTimeoutMS, &error));
    require(queue->completedSubmissionCount() == 1, "empty batch completed exactly once");
    require(wrong->completedSubmissionCount() == 0, "wrong queue remained empty");
}

void transferRoundTrip(id<MTLDevice> device) {
    constexpr NSUInteger guard = 64, payload = 4096, size = payload + guard * 2;
    auto queue = makeQueue(device);
    auto batch = begin(*queue);
    std::vector<uint8_t> source(size, 0xB7);
    for (NSUInteger i = 0; i < payload; ++i) source[guard + i] = uint8_t(i * 29 + (i >> 4));
    Owned<id<MTLBuffer>> input([device newBufferWithBytes:source.data() length:size options:MTLResourceStorageModeShared]);
    Owned<id<MTLBuffer>> middle([device newBufferWithLength:size options:MTLResourceStorageModePrivate]);
    Owned<id<MTLBuffer>> output([device newBufferWithLength:size options:MTLResourceStorageModeShared]);
    require(input.get() && middle.get() && output.get(), "transfer buffers allocated");
    std::memset([output.get() contents], 0xE3, size);
    NSError* error = nil;
    CHECK_API(batch->addResource(input.get(), &error));
    CHECK_API(batch->addResource(middle.get(), &error));
    CHECK_API(batch->addResource(output.get(), &error));
    id<MTL4ComputeCommandEncoder> encoder = [batch->commandBuffer() computeCommandEncoder];
    require(encoder != nil, "native transfer encoder");
    [encoder fillBuffer:middle.get() range:NSMakeRange(0, size) value:0x3C];
    intra(encoder, MTLStageBlit, MTLStageBlit);
    [encoder copyFromBuffer:input.get() sourceOffset:guard toBuffer:middle.get() destinationOffset:guard size:payload];
    intra(encoder, MTLStageBlit, MTLStageBlit);
    [encoder copyFromBuffer:middle.get() sourceOffset:0 toBuffer:output.get() destinationOffset:0 size:size];
    [encoder endEncoding];
    input.reset(); middle.reset(); // Only production submission retains these GPU inputs.
    finish(*queue, batch);
    const auto* actual = static_cast<const uint8_t*>([output.get() contents]);
    for (NSUInteger i = 0; i < size; ++i) {
        uint8_t expected = (i >= guard && i < guard + payload) ? source[i] : 0x3C;
        require(actual[i] == expected, "transfer byte mismatch at " + std::to_string(i));
    }
}

void immutableUploadArena(id<MTLDevice> device) {
    constexpr NSUInteger count = 513, payload = 32, guard = 64;
    auto queue = makeQueue(device);
    auto batch = begin(*queue);
    NSError* error = nil;
    reject([&](NSError** e) { return batch->uploadBytesRange(nullptr, 4, e).buffer != nil; }, "nil slice");
    uint32_t zero = 0;
    reject([&](NSError** e) { return batch->uploadBytesRange(&zero, 0, e).buffer != nil; }, "empty slice");
    reject([&](NSError** e) { return batch->uploadBytesRange(&zero, NSUInteger(-1), e).buffer != nil; }, "overflow slice");
    std::vector<MVKMetal4Upload> slices;
    std::vector<uint8_t> expected(guard, 0xA5);
    id<MTLBuffer> previous = nil;
    NSUInteger slabs = 0;
    for (NSUInteger i = 0; i < count; ++i) {
        uint8_t data[payload];
        for (NSUInteger j = 0; j < payload; ++j) data[j] = uint8_t(i * 29 + (i >> 8) + j * 7);
        auto slice = batch->uploadBytesRange(data, payload, &error);
        require(slice.buffer && slice.offset % 256 == 0 && slice.offset + payload <= slice.buffer.length,
                "aligned slice in its buffer", error);
        if (slice.buffer != previous) { ++slabs; previous = slice.buffer; }
        slices.push_back(slice);
        expected.insert(expected.end(), data, data + payload);
        std::memset(data, 0xCC, payload); // Caller memory no longer contains the upload.
    }
    require(slabs == 3, "513 tiny uploads occupy three bounded slabs, not 513 buffers");
    for (NSUInteger i = 0; i < count; ++i) {
        auto slice = slices[i];
        require(std::memcmp(static_cast<uint8_t*>(slice.buffer.contents) + slice.offset,
                            expected.data() + guard + i * payload, payload) == 0,
                "later adjacent uploads and slab rollover preserve each earlier payload");
    }
    std::vector<uint8_t> large(64 * 1024 + 16);
    for (NSUInteger i = 0; i < large.size(); ++i) large[i] = uint8_t(i * 11 + 3);
    auto dedicated = batch->uploadBytesRange(large.data(), large.size(), &error);
    require(dedicated.buffer && dedicated.offset == 0 && dedicated.buffer != previous, "oversized dedicated upload", error);
    expected.insert(expected.end(), large.begin(), large.end());
    std::memset(large.data(), 0xDD, large.size());
    uint32_t tailData[] = {0x10203040, 0xFFEEDDCC};
    auto tail = batch->uploadBytesRange(tailData, sizeof(tailData), &error);
    require(tail.buffer == previous && tail.offset == 256, "large upload does not grow or replace current slab", error);
    expected.insert(expected.end(), reinterpret_cast<uint8_t*>(tailData), reinterpret_cast<uint8_t*>(tailData) + sizeof(tailData));
    expected.insert(expected.end(), guard, 0xA5);

    // The old API intentionally returns distinct writable buffers. Arena data
    // must not alias marker uploads with otherwise identical initial bytes.
    auto marker1 = batch->uploadBytes(&zero, sizeof(zero), &error);
    auto marker2 = batch->uploadBytes(&zero, sizeof(zero), &error);
    require(marker1 && marker2 && marker1 != marker2 && marker1 != previous && marker2 != previous,
            "legacy upload API preserves distinct writable storage", error);
    *static_cast<uint32_t*>(marker1.contents) = 0x12345678;
    require(*static_cast<uint32_t*>(marker2.contents) == 0, "writable uploads do not alias");

    Owned<id<MTLBuffer>> output([device newBufferWithLength:expected.size() options:MTLResourceStorageModeShared]);
    require(output.get() != nil, "slice readback storage");
    std::memset(output.get().contents, 0xA5, expected.size());
    // Retain first, register residency second, then repeat both. Independent
    // deduplication must still make this output resident for GPU writes.
    CHECK_API(batch->retainObject(output.get(), &error));
    CHECK_API(batch->addResource(output.get(), &error));
    CHECK_API(batch->retainObject(output.get(), &error));
    CHECK_API(batch->addResource(output.get(), &error));
    auto encoder = [batch->commandBuffer() computeCommandEncoder];
    require(encoder != nil, "slice GPU copy encoder");
    NSUInteger offset = guard;
    for (const auto& slice : slices) {
        [encoder copyFromBuffer:slice.buffer sourceOffset:slice.offset toBuffer:output.get() destinationOffset:offset size:payload];
        offset += payload;
    }
    [encoder copyFromBuffer:dedicated.buffer sourceOffset:dedicated.offset toBuffer:output.get() destinationOffset:offset size:large.size()];
    offset += large.size();
    [encoder copyFromBuffer:tail.buffer sourceOffset:tail.offset toBuffer:output.get() destinationOffset:offset size:sizeof(tailData)];
    [encoder endEncoding];
    CHECK_API(batch->end(&error));
    reject([&](NSError** e) { return batch->uploadBytesRange(&zero, sizeof(zero), e).buffer != nil; }, "slice after end");
    CHECK_API(queue->submit(batch, &error));
    batch.reset(); // Feedback, not this wrapper or test, owns all source slices.
    CHECK_API(queue->waitIdle(kTimeoutMS, &error));
    require(std::memcmp(output.get().contents, expected.data(), expected.size()) == 0,
            "GPU slice-offset readback preserves all payload bytes and guards");
}

void objectRetirement(id<MTLDevice> device) {
    auto queue = makeQueue(device);
    auto batch = begin(*queue);
    unsigned before = sentinelDeaths.load();
    MVKFoundationLifetimeSentinel* sentinel = [MVKFoundationLifetimeSentinel new];
    NSError* error = nil;
    CHECK_API(batch->retainObject(sentinel, &error));
    [sentinel release];
    require(sentinelDeaths.load() == before, "recording submission retains caller-released object");
    CHECK_API(batch->end(&error));
    require(sentinelDeaths.load() == before, "ended submission still retains object");
    CHECK_API(queue->submit(batch, &error));
    // Dropping the public wrapper must not drop GPU ownership. The queue's
    // feedback ledger remains observable even when this wrapper is gone.
    batch.reset();
    CHECK_API(queue->waitIdle(kTimeoutMS, &error));
    require(sentinelDeaths.load() == before + 1, "completion releases retained object exactly once");
    require(queue->completedSubmissionCount() == 1, "released wrapper completed exactly once");
}

void bulkPrimitiveInputs(id<MTLDevice> device) {
    auto queue = makeQueue(device);
    auto batch = begin(*queue);
    NSError* error = nil;
    const uint32_t first[] = {7, 11, 13, 17}, second[] = {19, 23, 29, 31}, third[] = {37, 41, 43, 47};
    Owned<id<MTLBuffer>> input([device newBufferWithBytes:first length:sizeof(first) options:MTLResourceStorageModeShared]);
    Owned<id<MTLBuffer>> output([device newBufferWithLength:128 options:MTLResourceStorageModeShared]);
    auto descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:1 height:1 mipmapped:NO];
    Owned<id<MTLTexture>> texture([device newTextureWithDescriptor:descriptor]);
    require(input.get() && output.get() && texture.get(), "bulk input test resources");
    std::memset(output.get().contents, 0xA5, 128);
    const unsigned deathsBefore = sentinelDeaths.load();
    Owned<MVKFoundationLifetimeSentinel*> helperObject([MVKFoundationLifetimeSentinel new]);
    auto rejected = [&](const void* bytes, NSUInteger size, id object, id<MTLBuffer> arguments, id<MTLBuffer> indices) {
        error = nil;
        auto upload = batch->uploadBytesRangeWithPrimitiveInputs(bytes, size, object, arguments, indices, &error);
        require(!upload.buffer && error != nil, "invalid bulk operation rejects before publishing an upload");
        auto stats = batch->resourceRegistrationStats();
        require(stats.retainedObjects == 0 && stats.residentResources == 0 && stats.drawableRegistryLookups == 0,
                "invalid bulk operation does not partially register helper inputs");
    };
    rejected(nullptr, sizeof(first), helperObject.get(), input.get(), output.get());
    rejected(first, 0, helperObject.get(), input.get(), output.get());
    rejected(first, sizeof(first), nil, input.get(), output.get());
    rejected(first, sizeof(first), helperObject.get(), nil, output.get());
    rejected(first, sizeof(first), helperObject.get(), input.get(), (id<MTLBuffer>)texture.get());
    rejected(first, sizeof(first), helperObject.get(), (id<MTLBuffer>)texture.get(), nil);
    rejected(first, NSUIntegerMax, helperObject.get(), input.get(), output.get());
    auto firstUpload = batch->uploadBytesRangeWithPrimitiveInputs(first, sizeof(first), helperObject.get(), input.get(), output.get(), &error);
    require(firstUpload.buffer && firstUpload.offset == 0, "first valid bulk upload starts at zero after rejected calls", error);
    auto secondUpload = batch->uploadBytesRangeWithPrimitiveInputs(second, sizeof(second), helperObject.get(), input.get(), input.get(), &error);
    auto thirdUpload = batch->uploadBytesRangeWithPrimitiveInputs(third, sizeof(third), helperObject.get(), input.get(), nil, &error);
    require(secondUpload.buffer == firstUpload.buffer && secondUpload.offset == 256 &&
            thirdUpload.buffer == firstUpload.buffer && thirdUpload.offset == 512,
            "bulk uploads share aligned immutable slabs with duplicate and absent index inputs");
    auto stats = batch->resourceRegistrationStats();
    require(stats.retainedObjects == 4 && stats.residentResources == 3 && stats.drawableRegistryLookups == 0,
            "bulk operation deduplicates pipeline object and buffers while keeping residency distinct");
    id<MTL4ComputeCommandEncoder> encoder = [batch->commandBuffer() computeCommandEncoder];
    require(encoder != nil, "bulk input native copy encoder");
    [encoder copyFromBuffer:input.get() sourceOffset:0 toBuffer:output.get() destinationOffset:0 size:sizeof(first)];
    [encoder copyFromBuffer:firstUpload.buffer sourceOffset:firstUpload.offset toBuffer:output.get() destinationOffset:32 size:sizeof(first)];
    [encoder copyFromBuffer:secondUpload.buffer sourceOffset:secondUpload.offset toBuffer:output.get() destinationOffset:64 size:sizeof(second)];
    [encoder copyFromBuffer:thirdUpload.buffer sourceOffset:thirdUpload.offset toBuffer:output.get() destinationOffset:96 size:sizeof(third)];
    [encoder endEncoding];
    helperObject.reset(); input.reset(); texture.reset();
    require(sentinelDeaths.load() == deathsBefore, "bulk operation retains caller-released helper object");
    CHECK_API(batch->end(&error));
    auto afterEnd = batch->uploadBytesRangeWithPrimitiveInputs(first, sizeof(first), device, output.get(), output.get(), &error);
    require(!afterEnd.buffer && error.code == 3, "ended bulk upload rejects without changing the batch");
    CHECK_API(queue->submit(batch, &error));
    CHECK_API(batch->wait(kTimeoutMS, &error));
    CHECK_API(queue->waitIdle(kTimeoutMS, &error));
    require(sentinelDeaths.load() == deathsBefore + 1, "bulk helper object releases exactly once after GPU retirement");
    const auto* actual = static_cast<const uint8_t*>(output.get().contents);
    uint8_t expected[128]; std::memset(expected, 0xA5, sizeof(expected));
    std::memcpy(expected, first, sizeof(first)); std::memcpy(expected + 32, first, sizeof(first));
    std::memcpy(expected + 64, second, sizeof(second)); std::memcpy(expected + 96, third, sizeof(third));
    require(std::memcmp(actual, expected, sizeof(expected)) == 0,
            "bulk direct inputs and immutable parameter generations survive caller release, including guards");
    auto afterCompletion = batch->uploadBytesRangeWithPrimitiveInputs(first, sizeof(first), device, output.get(), output.get(), &error);
    require(!afterCompletion.buffer && error.code == 3, "completed bulk upload rejects despite retained public wrapper");
    auto cancelled = begin(*queue);
    auto cancelledObject = [MVKFoundationLifetimeSentinel new];
    auto cancelledUpload = cancelled->uploadBytesRangeWithPrimitiveInputs(first, sizeof(first), cancelledObject, output.get(), nil, &error);
    require(cancelledUpload.buffer != nil, "bulk cancellation creates a fresh recording upload", error);
    [cancelledObject release];
    CHECK_API(cancelled->end(&error));
    cancelled.reset();
    require(sentinelDeaths.load() == deathsBefore + 2, "ended cancellation releases bulk retained object without GPU submission");
}

void multipleSubmissions(id<MTLDevice> device) {
    constexpr unsigned count = 12;
    auto queue = makeQueue(device);
    std::vector<std::shared_ptr<MVKMetal4Submission>> batches;
    std::vector<id<MTLBuffer>> outputs;
    // Collection owns one reference per output independently of the GPU lifetime.
    Owned<NSMutableArray*> outputOwners([NSMutableArray new]);
    NSError* error = nil;
    for (unsigned i = 0; i < count; ++i) {
        auto batch = begin(*queue);
        id<MTLBuffer> output = [device newBufferWithLength:256 options:MTLResourceStorageModeShared];
        require(output != nil, "parallel batch output");
        [outputOwners.get() addObject:output]; [output release];
        outputs.push_back(output);
        std::memset(output.contents, 0, 256);
        CHECK_API(batch->addResource(output, &error));
        id<MTL4ComputeCommandEncoder> encoder = [batch->commandBuffer() computeCommandEncoder];
        require(encoder != nil, "native independent encoder");
        [encoder fillBuffer:output range:NSMakeRange(0, 256) value:uint8_t(i + 1)];
        [encoder endEncoding];
        CHECK_API(batch->end(&error));
        CHECK_API(queue->submit(batch, &error));
        batches.push_back(batch);
    }
    CHECK_API(queue->waitIdle(kTimeoutMS, &error));
    require(queue->completedSubmissionCount() == count, "all independent allocator submissions completed once");
    for (unsigned i = 0; i < count; ++i) {
        CHECK_API(batches[i]->wait(0, &error));
        const uint8_t* bytes = static_cast<const uint8_t*>(outputs[i].contents);
        for (unsigned j = 0; j < 256; ++j) require(bytes[j] == i + 1, "independent submission output");
    }
}

// Always unblock a submitted wait if an assertion throws. This owns the event
// independently of the test's other references and never waits in its destructor.
class HostEventGate {
public:
    explicit HostEventGate(id<MTLSharedEvent> value) : event([value retain]) {}
    ~HostEventGate() { open(); [event release]; }
    void open() { if (event.signaledValue < 1) event.signaledValue = 1; }
private:
    id<MTLSharedEvent> event;
};

void concurrentIdleDeadline(id<MTLDevice> device) {
    auto queue = makeQueue(device);
    Owned<id<MTLSharedEvent>> event([device newSharedEvent]);
    require(event.get() != nil, "concurrent idle gate allocated");
    HostEventGate gate(event.get());
    auto batch = begin(*queue);
    NSError* error = nil;
    CHECK_API(batch->addWaitEvent(event.get(), 1, &error));
    CHECK_API(batch->end(&error));
    CHECK_API(queue->submit(batch, &error));

    std::promise<void> enteringLongWait;
    auto entered = enteringLongWait.get_future();
    std::atomic<bool> longFinished{false}, longSucceeded{false}, workerFailed{false};
    std::thread waiter([&] {
        // NSError and autoreleased Foundation objects never cross thread bounds.
        @autoreleasepool {
            try {
                NSError* threadError = nil;
                enteringLongWait.set_value();
                longSucceeded.store(queue->waitIdle(300, &threadError));
            } catch (...) {
                workerFailed.store(true);
            }
            longFinished.store(true);
        }
    });
    struct UnblockAndJoin {
        HostEventGate& gate;
        std::thread& waiter;
        ~UnblockAndJoin() {
            gate.open();
            if (waiter.joinable()) waiter.join();
        }
    } cleanup{gate, waiter};

    require(entered.wait_for(std::chrono::seconds(1)) == std::future_status::ready,
            "long idle waiter started within bound");
    // Give the announced worker time to enter waitIdle and hold the submit lock.
    // The old implementation then blocks the short call for roughly 270 ms.
    std::this_thread::sleep_for(std::chrono::milliseconds(30));
    require(!longFinished.load(), "long idle waiter is still blocked on the GPU gate");
    auto started = std::chrono::steady_clock::now();
    bool shortSucceeded = queue->waitIdle(20, &error);
    auto elapsed = std::chrono::steady_clock::now() - started;
    require(!shortSucceeded && error && error.code == 4, "contending short idle wait reports timeout");
    require(elapsed < std::chrono::milliseconds(150), "idle timeout includes acquisition of the submit lock");
    require(!longFinished.load(), "short timeout returns before the longer blocked waiter");
    gate.open();
    waiter.join();
    require(!workerFailed.load() && longSucceeded.load(), "long idle wait succeeds once the host releases the gate");
    CHECK_API(batch->wait(kTimeoutMS, &error));
    CHECK_API(queue->waitIdle(kTimeoutMS, &error));
    require(queue->completedSubmissionCount() == 1, "contended waits preserve one submission completion");
}

void blockedEventLifetime(id<MTLDevice> device) {
    auto queue = makeQueue(device);
    Owned<id<MTLSharedEvent>> event([device newSharedEvent]);
    require(event.get() != nil, "host-signaled gate allocated");
    HostEventGate gate(event.get());
    auto batch = begin(*queue);
    constexpr NSUInteger size = 512;
    std::vector<uint8_t> source(size);
    for (NSUInteger i = 0; i < size; ++i) source[i] = uint8_t(i * 13 + 7);
    Owned<id<MTLBuffer>> input([device newBufferWithBytes:source.data() length:size options:MTLResourceStorageModeShared]);
    Owned<id<MTLBuffer>> output([device newBufferWithLength:size options:MTLResourceStorageModeShared]);
    require(input.get() && output.get(), "gated transfer buffers");
    std::memset([output.get() contents], 0, size);
    NSError* error = nil;
    CHECK_API(batch->addResource(input.get(), &error));
    CHECK_API(batch->addResource(output.get(), &error));
    CHECK_API(batch->addWaitEvent(event.get(), 1, &error));
    const unsigned deathsBefore = sentinelDeaths.load();
    MVKFoundationLifetimeSentinel* sentinel = [MVKFoundationLifetimeSentinel new];
    CHECK_API(batch->retainObject(sentinel, &error));
    [sentinel release];
    auto cleanups = std::make_shared<std::atomic<unsigned>>(0);
    auto cleanupObservedLiveObject = std::make_shared<std::atomic<bool>>(false);
    auto completions = std::make_shared<std::atomic<unsigned>>(0);
    auto errors = std::make_shared<std::atomic<unsigned>>(0);
    auto completionAfterRetirement = std::make_shared<std::atomic<bool>>(false);
    CHECK_API(batch->deferRelease([cleanups, cleanupObservedLiveObject, deathsBefore] {
        cleanupObservedLiveObject->store(sentinelDeaths.load() == deathsBefore);
        ++*cleanups;
    }, &error));
    CHECK_API(batch->addErrorHandler([errors](NSError*) { ++*errors; }, &error));
    CHECK_API(batch->addCompletedHandler([completions, cleanups, completionAfterRetirement, deathsBefore](NSError* error) {
        completionAfterRetirement->store(!error && cleanups->load() == 1 && sentinelDeaths.load() == deathsBefore + 1);
        ++*completions;
    }, &error));
    id<MTL4ComputeCommandEncoder> encoder = [batch->commandBuffer() computeCommandEncoder];
    require(encoder != nil, "gated copy encoder");
    [encoder copyFromBuffer:input.get() sourceOffset:0 toBuffer:output.get() destinationOffset:0 size:size];
    [encoder endEncoding];
    input.reset();
    CHECK_API(batch->end(&error));
    CHECK_API(queue->submit(batch, &error));
    auto started = std::chrono::steady_clock::now();
    bool completedEarly = batch->wait(20, &error);
    require(!completedEarly && error && error.code == 4, "blocked submission wait reports timeout");
    bool idleEarly = queue->waitIdle(20, &error);
    require(!idleEarly && error && error.code == 4, "blocked queue idle reports timeout");
    auto elapsed = std::chrono::steady_clock::now() - started;
    require(elapsed < std::chrono::seconds(2), "short waits remain bounded");
    require(!batch->completed() && queue->completedSubmissionCount() == 0, "blocked batch remains in flight");
    require(cleanups->load() == 0 && sentinelDeaths.load() == deathsBefore,
            "timeouts preserve callbacks and caller-released objects");
    require(completions->load() == 0 && errors->load() == 0, "blocked submission cannot invoke fence-style completion early");
    gate.open();
    CHECK_API(batch->wait(kTimeoutMS, &error));
    CHECK_API(queue->waitIdle(kTimeoutMS, &error));
    require(std::memcmp([output.get() contents], source.data(), size) == 0, "unblocked retained resource result");
    require(cleanups->load() == 1 && cleanupObservedLiveObject->load(), "cleanup runs once while retained objects live");
    require(sentinelDeaths.load() == deathsBefore + 1, "host completion includes retained object release");
    require(completions->load() == 1 && errors->load() == 0 && completionAfterRetirement->load(),
            "successful completion callback runs once after resource retirement");
    batch.reset();
    require(cleanups->load() == 1, "completed batch destruction does not repeat cleanup");
    require(completions->load() == 1, "completed batch destruction does not repeat its completion callback");
}

void twoQueueEventTransfer(id<MTLDevice> device) {
    constexpr NSUInteger guard = 64, payload = 2048, size = guard * 2 + payload;
    auto producer = makeQueue(device);
    auto consumer = makeQueue(device);
    Owned<id<MTLSharedEvent>> event([device newSharedEvent]);
    require(event.get() != nil, "cross-queue event allocated");
    HostEventGate exceptionUnblock(event.get());
    auto producerBatch = begin(*producer);
    auto consumerBatch = begin(*consumer);
    std::vector<uint8_t> source(size, 0x3D);
    for (NSUInteger i = 0; i < payload; ++i) source[guard + i] = uint8_t(i * 37 + (i >> 3));
    Owned<id<MTLBuffer>> input([device newBufferWithBytes:source.data() length:size options:MTLResourceStorageModeShared]);
    Owned<id<MTLBuffer>> middle([device newBufferWithLength:size options:MTLResourceStorageModePrivate]);
    Owned<id<MTLBuffer>> output([device newBufferWithLength:size options:MTLResourceStorageModeShared]);
    require(input.get() && middle.get() && output.get(), "cross-queue buffers allocated");
    std::memset([output.get() contents], 0xA5, size);
    NSError* error = nil;
    CHECK_API(producerBatch->addResource(input.get(), &error));
    CHECK_API(producerBatch->addResource(middle.get(), &error));
    CHECK_API(consumerBatch->addResource(middle.get(), &error));
    CHECK_API(consumerBatch->addResource(output.get(), &error));
    CHECK_API(producerBatch->addSignalEvent(event.get(), 1, &error));
    CHECK_API(consumerBatch->addWaitEvent(event.get(), 1, &error));
    id<MTL4ComputeCommandEncoder> writer = [producerBatch->commandBuffer() computeCommandEncoder];
    require(writer != nil, "producer native encoder");
    [writer copyFromBuffer:input.get() sourceOffset:0 toBuffer:middle.get() destinationOffset:0 size:size];
    [writer endEncoding];
    id<MTL4ComputeCommandEncoder> reader = [consumerBatch->commandBuffer() computeCommandEncoder];
    require(reader != nil, "consumer native encoder");
    [reader copyFromBuffer:middle.get() sourceOffset:guard toBuffer:output.get() destinationOffset:guard size:payload];
    [reader endEncoding];
    CHECK_API(producerBatch->end(&error));
    CHECK_API(consumerBatch->end(&error));
    // Submit the consumer first so success cannot depend on host submission order.
    CHECK_API(consumer->submit(consumerBatch, &error));
    CHECK_API(producer->submit(producerBatch, &error));
    input.reset(); middle.reset();
    CHECK_API(consumerBatch->wait(kTimeoutMS, &error));
    CHECK_API(producerBatch->wait(kTimeoutMS, &error));
    CHECK_API(consumer->waitIdle(kTimeoutMS, &error));
    CHECK_API(producer->waitIdle(kTimeoutMS, &error));
    require(event.get().signaledValue >= 1, "producer signal is visible at host completion");
    const uint8_t* actual = static_cast<const uint8_t*>([output.get() contents]);
    for (NSUInteger i = 0; i < size; ++i) {
        uint8_t expected = i >= guard && i < guard + payload ? source[i] : 0xA5;
        require(actual[i] == expected, "cross-queue data/guard mismatch at " + std::to_string(i));
    }
    require(producer->completedSubmissionCount() == 1 && consumer->completedSubmissionCount() == 1,
            "both native queue completion ledgers advanced once");
}

void deferredCleanupStates(id<MTLDevice> device) {
    auto queue = makeQueue(device);
    NSError* error = nil;
    for (bool ended : {false, true}) {
        auto cleanups = std::make_shared<std::atomic<unsigned>>(0);
        auto callbacks = std::make_shared<std::atomic<unsigned>>(0);
        auto batch = begin(*queue);
        CHECK_API(batch->deferRelease([cleanups] { ++*cleanups; }, &error));
        CHECK_API(batch->addErrorHandler([callbacks](NSError*) { ++*callbacks; }, &error));
        CHECK_API(batch->addCompletedHandler([callbacks](NSError*) { ++*callbacks; }, &error));
        if (ended) CHECK_API(batch->end(&error));
        auto alias = batch;
        batch.reset();
        require(cleanups->load() == 0, "live unsubmitted wrapper preserves cleanup obligation");
        alias.reset();
        require(cleanups->load() == 1, ended ? "ended cancellation cleanup once" : "recording cancellation cleanup once");
        require(callbacks->load() == 0, "unsubmitted cancellation does not invoke GPU error/completion handlers");
    }
    require(queue->completedSubmissionCount() == 0, "cancelled batches were never submitted");
    auto cleanups = std::make_shared<std::atomic<unsigned>>(0);
    auto batch = begin(*queue);
    reject([&](NSError** e) { return batch->deferRelease({}, e); }, "empty cleanup callback");
    CHECK_API(batch->deferRelease([cleanups] { ++*cleanups; }, &error));
    CHECK_API(batch->end(&error));
    reject([&](NSError** e) { return batch->deferRelease([cleanups] { ++*cleanups; }, e); }, "late cleanup callback");
    CHECK_API(queue->submit(batch, &error));
    CHECK_API(batch->wait(kTimeoutMS, &error));
    require(cleanups->load() == 1, "successful batch wait includes exactly one cleanup");
    CHECK_API(queue->waitIdle(kTimeoutMS, &error));
    batch.reset();
    require(cleanups->load() == 1 && queue->completedSubmissionCount() == 1,
            "completed wrapper destruction does not run cleanup twice");
}

NSString* shaderSource() {
    return [NSString stringWithUTF8String:R"MSL(
#include <metal_stdlib>
using namespace metal;
kernel void transform(const device uint* src [[buffer(0)]], device uint* dst [[buffer(1)]],
                      constant uint& delta [[buffer(2)]], uint index [[thread_position_in_grid]]) {
    dst[index] = src[index] * 3u + delta;
}
struct RasterData { float4 position [[position]]; };
vertex RasterData fullscreen(uint index [[vertex_id]]) {
    const float2 positions[3] = {float2(-1, -1), float2(3, -1), float2(-1, 3)};
    return {float4(positions[index], 0, 1)};
}
fragment float4 shade(constant float4& color [[buffer(0)]]) { return color; }
struct PackedStageIn {
    float brightness [[attribute(0)]];
    float2 position [[attribute(1)]];
};
struct PackedRasterData { float4 position [[position]]; float brightness; };
vertex PackedRasterData packed_vertex(PackedStageIn in [[stage_in]]) {
    return {float4(in.position, 0, 1), in.brightness};
}
fragment float4 packed_shade(PackedRasterData in [[stage_in]], constant float4& color [[buffer(0)]]) {
    return float4(color.rgb * in.brightness, color.a);
}
fragment float4 sampled_shade(constant float4& color [[buffer(0)]],
                             texture2d<float, access::sample> image [[texture(0)]],
                             sampler filtering [[sampler(0)]]) {
    // Repeat addressing must select the first texel. Clamp-to-edge would select
    // the deliberately different second texel and fail the pixel comparison.
    return color * image.sample(filtering, float2(1.25f, 0.25f));
}
)MSL"];
}

void computeWithTable(id<MTLDevice> device) {
    constexpr NSUInteger count = 257, guardWords = 16, byteSize = (count + 2 * guardWords) * sizeof(uint32_t);
    NSError* error = nil;
    Owned<id<MTLLibrary>> library([device newLibraryWithSource:shaderSource() options:nil error:&error]);
    require(library.get() != nil, "shared shader compiler library", error);
    Owned<id<MTLFunction>> function([library.get() newFunctionWithName:@"transform"]);
    Owned<id<MTLComputePipelineState>> pipeline([device newComputePipelineStateWithFunction:function.get() error:&error]);
    require(pipeline.get() != nil, "shared compute pipeline on native encoder", error);
    auto queue = makeQueue(device);
    auto batch = begin(*queue);
    std::vector<uint32_t> data(count + 2 * guardWords, 0xDEADBEEF);
    for (NSUInteger i = 0; i < count; ++i) data[guardWords + i] = uint32_t(i * 17 + 3);
    Owned<id<MTLBuffer>> input([device newBufferWithBytes:data.data() length:byteSize options:MTLResourceStorageModeShared]);
    Owned<id<MTLBuffer>> output([device newBufferWithLength:byteSize options:MTLResourceStorageModeShared]);
    require(input.get() && output.get(), "compute buffers");
    std::memset([output.get() contents], 0xA5, byteSize);
    CHECK_API(batch->addResource(input.get(), &error));
    CHECK_API(batch->addResource(output.get(), &error));
    CHECK_API(batch->retainObject(pipeline.get(), &error));
    uint32_t delta = 41;
    id<MTLBuffer> constant = batch->uploadBytes(&delta, sizeof(delta), &error);
    require(constant != nil, "submission inline upload", error);
    delta = 9999; // The upload owns a copy, not the caller's stack storage.
    {
        MVKMetal4ArgumentTables tables;
        CHECK_API(tables.initialize(device, {3, 0, 0}, &error));
        CHECK_API(tables.setBuffer(Stage::Compute, input.get(), guardWords * 4, 0, &error));
        CHECK_API(tables.setBuffer(Stage::Compute, output.get(), guardWords * 4, 1, &error));
        CHECK_API(tables.setBuffer(Stage::Compute, constant, 0, 2, &error));
        CHECK_API(batch->retainObject(tables.getTable(Stage::Compute, &error), &error));
        id<MTL4ComputeCommandEncoder> encoder = [batch->commandBuffer() computeCommandEncoder];
        require(encoder != nil, "native compute encoder");
        [encoder setComputePipelineState:pipeline.get()];
        CHECK_API(tables.bindCompute(encoder, &error));
        [encoder dispatchThreads:MTLSizeMake(count, 1, 1) threadsPerThreadgroup:MTLSizeMake(64, 1, 1)];
        [encoder endEncoding];
    } // Table wrapper dies before submission; production batch owns native table.
    input.reset(); pipeline.reset(); function.reset(); library.reset();
    finish(*queue, batch);
    const uint32_t* actual = static_cast<const uint32_t*>([output.get() contents]);
    for (NSUInteger i = 0; i < count + 2 * guardWords; ++i) {
        uint32_t expected = (i >= guardWords && i < count + guardWords) ? data[i] * 3 + 41 : 0xA5A5A5A5;
        require(actual[i] == expected, "compute data/guard mismatch at " + std::to_string(i));
    }
}

void offscreenRender(id<MTLDevice> device, NSUInteger samples, bool mixedVBO = false, bool sampled = false) {
    constexpr NSUInteger width = 16, height = 16, rowBytes = 256, guard = 256;
    constexpr NSUInteger readbackSize = guard * 2 + rowBytes * height;
    require([device supportsTextureSampleCount:samples], "requested sample count supported");
    NSError* error = nil;
    Owned<id<MTLLibrary>> library([device newLibraryWithSource:shaderSource() options:nil error:&error]);
    require(library.get() != nil, "render shader library", error);
    Owned<id<MTLFunction>> vertex([library.get() newFunctionWithName:(mixedVBO ? @"packed_vertex" : @"fullscreen")]);
    Owned<id<MTLFunction>> fragment([library.get() newFunctionWithName:(sampled ? @"sampled_shade" : mixedVBO ? @"packed_shade" : @"shade")]);
    struct PackedVertex { uint8_t brightness; uint8_t padding[3]; float position[2]; };
    static_assert(sizeof(PackedVertex) == 12 && offsetof(PackedVertex, position) == 4,
                  "CPU VBO fixture must preserve byte/padding/float2 layout");
    constexpr NSUInteger vertexPrefix = 32;
    const PackedVertex vertices[] = {
        {128, {0xE1, 0xE2, 0xE3}, {-1, -1}},
        {128, {0xE4, 0xE5, 0xE6}, { 3, -1}},
        {128, {0xE7, 0xE8, 0xE9}, {-1,  3}},
    };
    std::vector<uint8_t> vertexBytes(vertexPrefix + sizeof(vertices) + 16, 0xCE);
    std::memcpy(vertexBytes.data() + vertexPrefix, vertices, sizeof(vertices));
    Owned<id<MTLBuffer>> vertexBuffer(mixedVBO
        ? [device newBufferWithBytes:vertexBytes.data() length:vertexBytes.size() options:MTLResourceStorageModeShared]
        : nil);
    require(!mixedVBO || vertexBuffer.get() != nil, "mixed layout vertex buffer");
    Owned<MTLVertexDescriptor*> vertexDescriptor([MTLVertexDescriptor new]);
    if (mixedVBO) {
        vertexDescriptor.get().attributes[0].format = MTLVertexFormatUCharNormalized;
        vertexDescriptor.get().attributes[0].offset = 0;
        vertexDescriptor.get().attributes[0].bufferIndex = 0;
        vertexDescriptor.get().attributes[1].format = MTLVertexFormatFloat2;
        vertexDescriptor.get().attributes[1].offset = 4;
        vertexDescriptor.get().attributes[1].bufferIndex = 0;
        vertexDescriptor.get().layouts[0].stride = MTLBufferLayoutStrideDynamic;
        vertexDescriptor.get().layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    }
    Owned<MTLRenderPipelineDescriptor*> pipelineDesc([MTLRenderPipelineDescriptor new]);
    pipelineDesc.get().vertexFunction = vertex.get();
    pipelineDesc.get().fragmentFunction = fragment.get();
    pipelineDesc.get().rasterSampleCount = samples;
    pipelineDesc.get().colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
    if (mixedVBO) pipelineDesc.get().vertexDescriptor = vertexDescriptor.get();
    Owned<id<MTLRenderPipelineState>> pipeline([device newRenderPipelineStateWithDescriptor:pipelineDesc.get() error:&error]);
    require(pipeline.get() != nil, "shared render pipeline on native encoder", error);
    Owned<MTLTextureDescriptor*> descriptor([MTLTextureDescriptor new]);
    descriptor.get().pixelFormat = MTLPixelFormatRGBA8Unorm;
    descriptor.get().width = width; descriptor.get().height = height;
    descriptor.get().textureType = MTLTextureType2D;
    descriptor.get().storageMode = MTLStorageModePrivate;
    descriptor.get().usage = MTLTextureUsageRenderTarget;
    Owned<id<MTLTexture>> resolved([device newTextureWithDescriptor:descriptor.get()]);
    descriptor.get().textureType = samples > 1 ? MTLTextureType2DMultisample : MTLTextureType2D;
    descriptor.get().sampleCount = samples;
    Owned<id<MTLTexture>> target([device newTextureWithDescriptor:descriptor.get()]);
    Owned<id<MTLBuffer>> readback([device newBufferWithLength:readbackSize options:MTLResourceStorageModeShared]);
    require(resolved.get() && target.get() && readback.get(), "offscreen render targets and readback");
    Owned<MTLTextureDescriptor*> sampledDescriptor([MTLTextureDescriptor new]);
    sampledDescriptor.get().textureType = MTLTextureType2D;
    sampledDescriptor.get().pixelFormat = MTLPixelFormatRGBA8Unorm;
    sampledDescriptor.get().width = 2; sampledDescriptor.get().height = 2;
    sampledDescriptor.get().storageMode = MTLStorageModeShared;
    sampledDescriptor.get().usage = MTLTextureUsageShaderRead;
    Owned<id<MTLTexture>> sampledTexture(sampled ? [device newTextureWithDescriptor:sampledDescriptor.get()] : nil);
    Owned<MTLSamplerDescriptor*> samplerDescriptor([MTLSamplerDescriptor new]);
    samplerDescriptor.get().supportArgumentBuffers = YES;
    samplerDescriptor.get().minFilter = MTLSamplerMinMagFilterNearest;
    samplerDescriptor.get().magFilter = MTLSamplerMinMagFilterNearest;
    samplerDescriptor.get().mipFilter = MTLSamplerMipFilterNotMipmapped;
    samplerDescriptor.get().sAddressMode = MTLSamplerAddressModeRepeat;
    samplerDescriptor.get().tAddressMode = MTLSamplerAddressModeRepeat;
    Owned<id<MTLSamplerState>> sampler(sampled ? [device newSamplerStateWithDescriptor:samplerDescriptor.get()] : nil);
    if (sampled) {
        require(sampledTexture.get() && sampler.get(), "sampled texture and argument-compatible sampler");
        const uint8_t texels[16] = {96,160,224,255, 244,8,4,255, 8,244,4,255, 4,8,244,255};
        [sampledTexture.get() replaceRegion:MTLRegionMake2D(0, 0, 2, 2) mipmapLevel:0 withBytes:texels bytesPerRow:8];
    }
    std::memset([readback.get() contents], 0xA5, readbackSize);
    auto queue = makeQueue(device);
    auto batch = begin(*queue);
    CHECK_API(batch->addResource(target.get(), &error));
    CHECK_API(batch->addResource(resolved.get(), &error));
    CHECK_API(batch->addResource(readback.get(), &error));
    if (mixedVBO) CHECK_API(batch->addResource(vertexBuffer.get(), &error));
    if (sampled) {
        CHECK_API(batch->addResource(sampledTexture.get(), &error));
        // Samplers are objects, not MTLResource allocations: retain them while
        // making the referenced texture resident through addResource().
        CHECK_API(batch->retainObject(sampler.get(), &error));
    }
    CHECK_API(batch->retainObject(pipeline.get(), &error));
    const float color[4] = {0.25f, 0.5f, 0.75f, 1.0f};
    id<MTLBuffer> colorBuffer = batch->uploadBytes(color, sizeof(color), &error);
    require(colorBuffer != nil, "fragment color upload", error);
    Owned<MTL4RenderPassDescriptor*> pass([MTL4RenderPassDescriptor new]);
    pass.get().colorAttachments[0].texture = target.get();
    pass.get().colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.get().colorAttachments[0].clearColor = MTLClearColorMake(1, 0, 1, 1);
    pass.get().colorAttachments[0].storeAction = samples > 1 ? MTLStoreActionMultisampleResolve : MTLStoreActionStore;
    if (samples > 1) pass.get().colorAttachments[0].resolveTexture = resolved.get();
    {
        MVKMetal4ArgumentTables tables;
        CHECK_API(tables.initialize(device, {1, sampled ? 1u : 0u, sampled ? 1u : 0u}, &error));
        CHECK_API(tables.setBuffer(Stage::Fragment, colorBuffer, 0, 0, &error));
        CHECK_API(batch->retainObject(tables.getTable(Stage::Fragment, &error), &error));
        if (sampled) {
            CHECK_API(tables.setTexture(Stage::Fragment, sampledTexture.get(), 0, &error));
            CHECK_API(tables.setSampler(Stage::Fragment, sampler.get(), 0, &error));
        }
        if (mixedVBO) {
            CHECK_API(tables.setBufferWithStride(Stage::Vertex, vertexBuffer.get(), vertexPrefix, sizeof(PackedVertex), 0, &error));
            CHECK_API(batch->retainObject(tables.getTable(Stage::Vertex, &error), &error));
        }
        id<MTL4RenderCommandEncoder> encoder = [batch->commandBuffer() renderCommandEncoderWithDescriptor:pass.get()];
        require(encoder != nil, "native render encoder");
        [encoder setRenderPipelineState:pipeline.get()];
        [encoder setViewport:MTLViewport{0, 0, double(width), double(height), 0, 1}];
        CHECK_API(tables.bindRender(encoder, mixedVBO ? MTLRenderStageVertex | MTLRenderStageFragment : MTLRenderStageFragment, &error));
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [encoder endEncoding];
    }
    id<MTL4ComputeCommandEncoder> copy = [batch->commandBuffer() computeCommandEncoder];
    require(copy != nil, "native render readback encoder");
    [copy barrierAfterQueueStages:MTLStageFragment beforeStages:MTLStageBlit visibilityOptions:MTL4VisibilityOptionDevice];
    [copy copyFromTexture:(samples > 1 ? resolved.get() : target.get()) sourceSlice:0 sourceLevel:0
            sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(width, height, 1)
                toBuffer:readback.get() destinationOffset:guard destinationBytesPerRow:rowBytes destinationBytesPerImage:0];
    [copy endEncoding];
    // Destroy every caller-side rendering object while the batch remains owner.
    target.reset(); resolved.reset(); pipeline.reset(); pass.reset(); vertexBuffer.reset();
    sampledTexture.reset(); sampler.reset();
    finish(*queue, batch);
    const auto* bytes = static_cast<const uint8_t*>([readback.get() contents]);
    const uint8_t standardExpected[4] = {64, 128, 191, 255};
    const uint8_t mixedExpected[4] = {32, 64, 96, 255};
    const uint8_t sampledExpected[4] = {24, 80, 168, 255};
    const uint8_t* expected = sampled ? sampledExpected : mixedVBO ? mixedExpected : standardExpected;
    for (NSUInteger i = 0; i < readbackSize; ++i) {
        bool pixel = i >= guard && i < guard + rowBytes * height && (i - guard) % rowBytes < width * 4;
        if (pixel) {
            int difference = int(bytes[i]) - int(expected[(i - guard) % 4]);
            require(difference >= -1 && difference <= 1, "render pixel mismatch at " + std::to_string(i));
        } else {
            require(bytes[i] == 0xA5, "render readback guard/padding mismatch at " + std::to_string(i));
        }
    }
}
void callbackRetirementOrder(id<MTLDevice> device) {
    auto queue = makeQueue(device);
    std::atomic<unsigned> cleaned{0}, completed{0}, errors{0}, orderingErrors{0};
    NSError* error = nil;
    for (bool ended : {false, true}) {
        auto cancelled = begin(*queue);
        CHECK_API(cancelled->deferRelease([&] { ++cleaned; }, &error));
        CHECK_API(cancelled->addCompletedHandler([&](NSError*) { ++completed; }, &error));
        CHECK_API(cancelled->addErrorHandler([&](NSError*) { ++errors; }, &error));
        if (ended) { CHECK_API(cancelled->end(&error)); }
    }
    require(cleaned == 2 && completed == 0 && errors == 0, "cancelled batches clean up without publishing Vulkan completion");
    Owned<id<MTLSharedEvent>> gate([device newSharedEvent]);
    auto batch = begin(*queue);
    id<MTL4CommandBuffer> retiringBuffer = batch->commandBuffer();
    auto retiringToken = batch->recordingToken();
    std::shared_ptr<MVKMetal4Submission> callbackRecording;
    const unsigned deathsBefore = sentinelDeaths.load();
    auto sentinel = [MVKFoundationLifetimeSentinel new];
    CHECK_API(batch->retainObject(sentinel, &error));
    [sentinel release];
    CHECK_API(batch->addWaitEvent(gate.get(), 1, &error));
    CHECK_API(batch->addSignalEvent(gate.get(), 2, &error)); // Exercise both real-work and tail retirement.
    CHECK_API(batch->deferRelease([&] { ++cleaned; }, &error));
    CHECK_API(batch->addCompletedHandler([&](NSError* value) {
        auto pool = queue->resourcePoolStats();
        if (value || cleaned != 3 || sentinelDeaths.load() != deathsBefore + 1 ||
            gate.get().signaledValue < 2 || pool.primaryIdle || pool.tailIdle ||
            queue->completedSubmissionCount() != 0) { ++orderingErrors; }
        // A callback-side begin must not acquire the retiring pack. Do not submit
        // or synchronously wait inside this handler; waitIdle still counts it.
        NSError* callbackError = nil;
        callbackRecording = queue->begin(&callbackError);
        if (!callbackRecording || callbackError || callbackRecording->commandBuffer() == retiringBuffer ||
            callbackRecording->matchesRecordingToken(retiringToken)) { ++orderingErrors; }
        ++completed;
    }, &error));
    CHECK_API(batch->addErrorHandler([&](NSError*) { ++errors; }, &error));
    CHECK_API(batch->end(&error));
    CHECK_API(queue->submit(batch, &error));
    batch.reset();
    require(!queue->waitIdle(20, &error), "blocked callback batch timeout");
    require(cleaned == 2 && completed == 0 && errors == 0, "blocked batch does not publish completion or retire resources");
    gate.get().signaledValue = 1;
    error = nil;
    CHECK_API(queue->waitIdle(kTimeoutMS, &error));
    require(cleaned == 3 && completed == 1 && errors == 0 && orderingErrors == 0,
            "cleanup and tail precede completion; old packs stay private during callback begin");
    auto pool = queue->resourcePoolStats();
    require(pool.primaryIdle == 1 && pool.tailIdle == 1 && pool.primaryCreated == 3,
            "old primary/tail publish after callback; callback recording owns a different primary");
    require(bool(callbackRecording), "callback recording created successfully");
    finish(*queue, callbackRecording);
    require(queue->completedSubmissionCount() == 2, "callback-created work completes after original retirement");

    // Feedback must keep independent state/queue ownership after a completed
    // handler destroys both public wrappers. Gate the GPU so submit has returned
    // before the callback mutates the holder; the caller only waits on a future.
    struct PublicOwners {
        std::unique_ptr<MVKMetal4Queue> queue;
        std::shared_ptr<MVKMetal4Submission> batch;
        std::atomic<unsigned> cleaned{0};
        std::promise<bool> callbackDone;
    };
    auto owners = std::make_shared<PublicOwners>();
    owners->queue = makeQueue(device);
    owners->batch = begin(*owners->queue);
    Owned<id<MTLSharedEvent>> destroyGate([device newSharedEvent]);
    HostEventGate unblock(destroyGate.get());
    auto destroyed = owners->callbackDone.get_future();
    CHECK_API(owners->batch->addWaitEvent(destroyGate.get(), 1, &error));
    CHECK_API(owners->batch->addSignalEvent(destroyGate.get(), 2, &error));
    CHECK_API(owners->batch->deferRelease([owners] { ++owners->cleaned; }, &error));
    CHECK_API(owners->batch->addCompletedHandler([owners](NSError* value) {
        bool okay = !value && owners->cleaned == 1 && owners->queue->resourcePoolStats().primaryIdle == 0;
        owners->batch.reset();
        owners->queue.reset();
        owners->callbackDone.set_value(okay);
    }, &error));
    CHECK_API(owners->batch->end(&error));
    CHECK_API(owners->queue->submit(owners->batch, &error));
    unblock.open();
    require(destroyed.wait_for(std::chrono::milliseconds(kTimeoutMS)) == std::future_status::ready,
            "public-wrapper destruction callback arrived");
    require(destroyed.get(), "mandatory cleanup precedes callback that destroys public queue/submission");
}
} // namespace

// Exact creation/reuse evidence is emitted with the suite result.
MVKMetal4ResourcePoolStats poolReuseEvidence;
uint64_t poolReuseCompleted = 0;

void resourcePackReuse(id<MTLDevice> device) {
    auto queue = makeQueue(device);
    Owned<id<MTLSharedEvent>> signal([device newSharedEvent]);
    Owned<id<MTLBuffer>> output([device newBufferWithLength:64 options:MTLResourceStorageModeShared]);
    require(signal.get() && output.get(), "pool proof resources");
    id<MTL4CommandBuffer> firstBuffer = nil;
    id<MTLBuffer> firstMarker = nil;
    std::shared_ptr<MVKMetal4Submission> previous;
    unsigned beforeDeaths = sentinelDeaths;
    NSError* error = nil;
    for (unsigned iteration = 0; iteration < 4; ++iteration) {
        auto batch = begin(*queue);
        auto registration = batch->resourceRegistrationStats();
        require(registration.retainedObjects == 0 && registration.residentResources == 0 &&
                registration.drawableRegistryLookups == 0, "new state has no old resource or drawable identities");
        auto buffer = batch->commandBuffer();
        auto marker = batch->completionMarker(&error);
        require(marker != nil, "pooled completion marker", error);
        require(batch->completionMarker(&error) == marker, "same batch marker is stable");
        if (!iteration) { firstBuffer = buffer; firstMarker = marker; }
        else {
            require(buffer == firstBuffer && marker == firstMarker, "actual buffer and marker objects were reused");
            // A completed wrapper outlives the returned pack. Destroy it while
            // the next recording owns the same Metal objects.
            require(previous->completed() && previous->commandBuffer() == nil, "old wrapper stays terminal after reuse");
            require(!batch->matchesRecordingToken(previous->recordingToken()), "reused host storage has a fresh weak control-block identity");
            previous.reset();
        }
        Owned<MVKFoundationLifetimeSentinel*> sentinel([MVKFoundationLifetimeSentinel new]);
        CHECK_API(batch->retainObject(sentinel.get(), &error));
        sentinel.reset();
        uint32_t value = 99;
        auto separate = batch->uploadBytes(&value, sizeof(value), &error);
        require(separate && separate != marker, "ordinary writable upload cannot alias the pooled marker");
        std::memset(output.get().contents, 0xA5, 64);
        CHECK_API(batch->addResource(output.get(), &error));
        CHECK_API(batch->addSignalEvent(signal.get(), iteration + 1, &error));
        auto encoder = [buffer computeCommandEncoder];
        require(encoder != nil, "pool proof encoder");
        [encoder fillBuffer:marker range:NSMakeRange(0, 4) value:uint8_t(0x31 + iteration)];
        intra(encoder, MTLStageBlit, MTLStageBlit);
        [encoder copyFromBuffer:marker sourceOffset:0 toBuffer:output.get() destinationOffset:16 size:4];
        [encoder endEncoding];
        finish(*queue, batch);
        ++poolReuseCompleted;
        require(sentinelDeaths == beforeDeaths + iteration + 1, "empty reused retained array releases old objects at retirement");
        reject([&](NSError** e) { return batch->completionMarker(e) != nil; }, "marker after retirement");
        require(signal.get().signaledValue >= iteration + 1, "tail completed after requested signal");
        auto bytes = static_cast<const uint8_t*>(output.get().contents);
        for (NSUInteger i = 0; i < 64; ++i) {
            require(bytes[i] == (i >= 16 && i < 20 ? uint8_t(0x31 + iteration) : 0xA5), "reused marker content and guards");
        }
        auto stats = queue->resourcePoolStats();
        require(stats.primaryCreated == 1 && stats.tailCreated == 1 &&
                stats.primaryReused == iteration && stats.tailReused == iteration,
                "four executions reuse one primary and one tail resource pack");
        require(stats.primaryIdle == 1 && stats.tailIdle == 1 &&
                stats.idleBytes <= MVKMetal4ResourcePoolStats::maxIdleBytes, "retired packs bounded and available");
        require(stats.hostStorageReused == iteration && stats.hostStorageIdleBytes > 0 &&
                stats.hostStorageIdleBytes <= MVKMetal4ResourcePoolStats::maxHostStoragePayloadBytes &&
                stats.retainedObjectSlotsIdle <= MVKMetal4ResourcePoolStats::maxRetainedHostObjects,
                "bounded empty host capacity reused with each retired primary pack");
        previous = batch;
    }
    poolReuseEvidence = queue->resourcePoolStats();
}

void resourcePackBlockedAndCancel(id<MTLDevice> device) {
    auto queue = makeQueue(device);
    Owned<id<MTLSharedEvent>> wait([device newSharedEvent]), signal([device newSharedEvent]);
    require(wait.get() && signal.get(), "pool lifetime event allocation");
    HostEventGate gate(wait.get());
    NSError* error = nil;
    auto blocked = begin(*queue);
    auto blockedBuffer = blocked->commandBuffer();
    auto blockedMarker = blocked->completionMarker(&error);
    require(blockedMarker != nil, "blocked pool marker", error);
    std::memset(blockedMarker.contents, 0x1A, 4);
    CHECK_API(blocked->addWaitEvent(wait.get(), 1, &error));
    CHECK_API(blocked->addSignalEvent(signal.get(), 1, &error));
    auto encoder = [blockedBuffer computeCommandEncoder];
    require(encoder != nil, "blocked pool encoder");
    [encoder fillBuffer:blockedMarker range:NSMakeRange(0, 4) value:0x71];
    [encoder endEncoding];
    CHECK_API(blocked->end(&error));
    CHECK_API(queue->submit(blocked, &error));
    require(!blocked->wait(20, &error) && error.code == 4, "blocked pack cannot retire on timeout");
    auto stats = queue->resourcePoolStats();
    require(stats.primaryCreated == 1 && stats.tailCreated == 1 && !stats.primaryIdle && !stats.tailIdle,
            "work and tail packs remain unavailable while GPU waits");
    auto cancelled = begin(*queue);
    auto cancelledToken = cancelled->recordingToken();
    auto cancelledBuffer = cancelled->commandBuffer();
    auto cancelledMarker = cancelled->completionMarker(&error);
    require(cancelledBuffer != blockedBuffer && cancelledMarker != blockedMarker, "in-flight objects were not borrowed");
    CHECK_API(cancelled->end(&error));
    cancelled.reset();
    require(cancelledToken.expired(), "ended cancellation does not pool its state or weak identity");
    require(queue->resourcePoolStats().primaryIdle == 1, "ended cancellation returns a safe pack");
    auto recording = begin(*queue);
    auto recordingToken = recording->recordingToken();
    require(recording->commandBuffer() == cancelledBuffer && recording->completionMarker(&error) == cancelledMarker,
            "ended cancellation pack is reused");
    recording.reset();
    require(recordingToken.expired(), "recording cancellation destroys state and host storage");
    require(queue->resourcePoolStats().primaryIdle == 0, "recording cancellation destroys its open pack");
    require(!blocked->completed() && signal.get().signaledValue == 0, "cancellation did not publish blocked completion");
    require(*static_cast<uint32_t*>(blockedMarker.contents) == 0x1A1A1A1A, "blocked GPU storage was not overwritten by another recording");
    gate.open();
    CHECK_API(blocked->wait(kTimeoutMS, &error));
    CHECK_API(queue->waitIdle(kTimeoutMS, &error));
    require(queue->resourcePoolStats().primaryIdle == 1 && queue->resourcePoolStats().tailIdle == 1,
            "host-unblocked GPU work returns both packs only after retirement");
    require(*static_cast<uint32_t*>(blockedMarker.contents) == 0x71717171, "original gated command stream survives other pack cancellation/reuse");
    // Keep all ended batches alive at once, then cancel them. Idle retention is
    // bounded even if recording temporarily needs more than the pool limit.
    std::vector<std::shared_ptr<MVKMetal4Submission>> ended;
    for (uint64_t i = 0; i < MVKMetal4ResourcePoolStats::maxIdlePacksPerKind + 3; ++i) {
        auto batch = begin(*queue); CHECK_API(batch->end(&error)); ended.push_back(std::move(batch));
    }
    ended.clear();
    stats = queue->resourcePoolStats();
    require(stats.primaryIdle > 0 && stats.primaryIdle <= MVKMetal4ResourcePoolStats::maxIdlePacksPerKind &&
            stats.tailIdle <= MVKMetal4ResourcePoolStats::maxIdlePacksPerKind &&
            stats.idleBytes <= MVKMetal4ResourcePoolStats::maxIdleBytes, "idle pack count and reported storage stay bounded");
    // Ended cancellation with oversized host state releases every object and
    // drops the opaque Foundation array; excessive wait-vector capacity drops.
    auto bounded = makeQueue(device);
    auto oversized = begin(*bounded);
    unsigned oversizedDeaths = sentinelDeaths;
    for (size_t i = 0; i <= MVKMetal4ResourcePoolStats::maxRetainedHostObjects; ++i) {
        Owned<MVKFoundationLifetimeSentinel*> value([MVKFoundationLifetimeSentinel new]);
        CHECK_API(oversized->retainObject(value.get(), &error));
    }
    for (size_t i = 0; i <= MVKMetal4ResourcePoolStats::maxHostVectorEntries; ++i) {
        CHECK_API(oversized->addWaitEvent(wait.get(), 1, &error));
    }
    CHECK_API(oversized->end(&error));
    auto oversizedToken = oversized->recordingToken();
    oversized.reset();
    auto boundedStats = bounded->resourcePoolStats();
    require(oversizedToken.expired() && sentinelDeaths == oversizedDeaths + MVKMetal4ResourcePoolStats::maxRetainedHostObjects + 1,
            "oversized ended cancellation releases all objects and state");
    // r49 keeps the empty queue-operation array separately. Its one unique
    // wait event contributes one high-water slot, while the oversized GPU
    // retained array must still be discarded (hostStorageReused below stays 0).
    require(boundedStats.primaryIdle == 1 && boundedStats.retainedObjectSlotsIdle == 1 &&
            boundedStats.hostStorageIdleBytes <= MVKMetal4ResourcePoolStats::maxHostStoragePayloadBytes,
            "oversized GPU array dropped; one bounded empty operation slot cached");
    auto next = begin(*bounded);
    require(!next->matchesRecordingToken(oversizedToken), "oversized cancellation storage reuse preserves fresh weak identity");
    require(bounded->resourcePoolStats().hostStorageReused == 0,
            "discarded oversized array is not counted as reused");
}

void resourcePackPoisoned(id<MTLDevice> device) {
    auto queue = makeQueue(device);
    Owned<id<MTLSharedEvent>> event([device newSharedEvent]);
    require(event.get() != nil, "poisoned pool gate");
    HostEventGate gate(event.get());
    auto batch = begin(*queue);
    NSError* error = nil;
    auto marker = batch->completionMarker(&error);
    require(marker != nil, "poisoned pool marker", error);
    CHECK_API(batch->addWaitEvent(event.get(), 1, &error));
    auto encoder = [batch->commandBuffer() computeCommandEncoder];
    require(encoder != nil, "poisoned pool encoder");
    [encoder fillBuffer:marker range:NSMakeRange(0, 4) value:0x42]; [encoder endEncoding];
    CHECK_API(batch->end(&error)); CHECK_API(queue->submit(batch, &error));
    queue->notifyDeviceLost(); // CPU error publication, never a fabricated GPU signal.
    require(!queue->waitIdle(20, &error) && error.code == 5, "poison wakes idle without GPU retirement");
    require(!batch->completed() && queue->resourcePoolStats().primaryIdle == 0, "poison cannot return in-flight pack");
    require(!queue->begin(&error) && error.code == 5, "poison rejects future encoding");
    gate.open();
    CHECK_API(batch->wait(kTimeoutMS, &error));
    require(queue->resourcePoolStats().primaryIdle == 0, "poisoned queue discards packs after actual retirement");
    require(queue->resourcePoolStats().hostStorageIdleBytes == 0 && queue->resourcePoolStats().retainedObjectSlotsIdle == 0,
            "device loss cannot retain idle host bookkeeping");
}

void computeOnlyTableSnapshots(id<MTLDevice> device) {
    constexpr NSUInteger count = 64, bytes = (count + 2) * sizeof(uint32_t);
    NSError* error = nil;
    NSString* source = @"#include <metal_stdlib>\nusing namespace metal;\n"
        "kernel void snapshot(const device uint* src [[buffer(0)]], device uint* dst [[buffer(1)]], "
        "constant uint* extra [[buffer(2)]], uint i [[thread_position_in_grid]]) { "
        "dst[i] = src[i] * 3u + *extra; }";
    Owned<id<MTLLibrary>> library([device newLibraryWithSource:source options:nil error:&error]);
    require(library.get() != nil, "snapshot library", error);
    Owned<id<MTLFunction>> function([library.get() newFunctionWithName:@"snapshot"]);
    Owned<id<MTLComputePipelineState>> pipeline([device newComputePipelineStateWithFunction:function.get() error:&error]);
    require(pipeline.get() != nil, "snapshot pipeline", error);
    auto queue = makeQueue(device); auto batch = begin(*queue);
    Owned<id<MTLBuffer>> inputA([device newBufferWithLength:bytes options:MTLResourceStorageModeShared]);
    Owned<id<MTLBuffer>> inputB([device newBufferWithLength:bytes options:MTLResourceStorageModeShared]);
    Owned<id<MTLBuffer>> outputA([device newBufferWithLength:bytes options:MTLResourceStorageModeShared]);
    Owned<id<MTLBuffer>> outputB([device newBufferWithLength:bytes options:MTLResourceStorageModeShared]);
    require(inputA.get() && inputB.get() && outputA.get() && outputB.get(), "snapshot buffers");
    for (NSUInteger i = 0; i < count + 2; ++i) {
        static_cast<uint32_t*>(inputA.get().contents)[i] = uint32_t(i + 7);
        static_cast<uint32_t*>(inputB.get().contents)[i] = uint32_t(i + 103);
    }
    std::memset(outputA.get().contents, 0xA5, bytes); std::memset(outputB.get().contents, 0xA5, bytes);
    for (auto buffer : {inputA.get(), inputB.get(), outputA.get(), outputB.get()}) { CHECK_API(batch->addResource(buffer, &error)); }
    CHECK_API(batch->retainObject(pipeline.get(), &error));
    uint32_t extra = 47;
    auto constant = batch->uploadBytesRange(&extra, sizeof(extra), &error);
    require(constant.buffer != nil, "snapshot constant", error);
    uint32_t zero = 0;
    auto zeroConstant = batch->uploadBytesRange(&zero, sizeof(zero), &error);
    require(zeroConstant.buffer != nil, "second snapshot zero constant", error);
    MVKMetal4ArgumentTables tables;
    CHECK_API(tables.initializeCompute(device, {3, 1, 1}, &error));
    require(tables.getTable(Stage::Compute, &error) != nil, "compute-only table exists");
    reject([&](NSError** e) { return tables.getTable(Stage::Vertex, e) != nil; }, "absent vertex table");
    reject([&](NSError** e) { return tables.getTable(Stage::Fragment, e) != nil; }, "absent fragment table");
    reject([&](NSError** e) { return tables.setBuffer(Stage::Vertex, inputA.get(), 0, 0, e); }, "vertex setter on compute-only table");
    reject([&](NSError** e) { return tables.setBuffer(Stage::Compute, inputA.get(), 0, 3, e); }, "compute buffer slot bound");
    reject([&](NSError** e) { return tables.setTexture(Stage::Compute, nil, 1, e); }, "compute texture slot bound");
    reject([&](NSError** e) { return tables.setSampler(Stage::Compute, nil, 1, e); }, "compute sampler slot bound");
    reject([&](NSError** e) { return tables.setBufferWithStride(Stage::Compute, inputA.get(), 0, 4, 0, e); }, "compute-only dynamic stride");
    reject([&](NSError** e) { return tables.clearBindings(Stage::Vertex, e); }, "clear absent vertex table");
    CHECK_API(batch->retainObject(tables.getTable(Stage::Compute), &error));
    auto encoder = [batch->commandBuffer() computeCommandEncoder];
    require(encoder != nil, "snapshot encoder");
    [encoder setComputePipelineState:pipeline.get()];
    CHECK_API(tables.setBuffer(Stage::Compute, inputA.get(), 4, 0, &error));
    CHECK_API(tables.setBuffer(Stage::Compute, outputA.get(), 4, 1, &error));
    CHECK_API(tables.setBuffer(Stage::Compute, constant.buffer, constant.offset, 2, &error));
    CHECK_API(tables.bindCompute(encoder, &error));
    [encoder dispatchThreads:MTLSizeMake(count, 1, 1) threadsPerThreadgroup:MTLSizeMake(32, 1, 1)];
    CHECK_API(tables.clearBindings(Stage::Compute, &error));
    CHECK_API(tables.setBuffer(Stage::Compute, inputB.get(), 4, 0, &error));
    CHECK_API(tables.setBuffer(Stage::Compute, outputB.get(), 4, 1, &error));
    CHECK_API(tables.setBuffer(Stage::Compute, zeroConstant.buffer, zeroConstant.offset, 2, &error));
    // No second setArgumentTable: this same table remains assigned. All shader
    // inputs are valid; the first dispatch must retain its distinct snapshot.
    [encoder dispatchThreads:MTLSizeMake(count, 1, 1) threadsPerThreadgroup:MTLSizeMake(32, 1, 1)];
    [encoder endEncoding];
    finish(*queue, batch);
    for (NSUInteger i = 0; i < count + 2; ++i) {
        bool payload = i > 0 && i <= count;
        uint32_t a = payload ? uint32_t(i + 7) * 3 + 47 : 0xA5A5A5A5;
        uint32_t b = payload ? uint32_t(i + 103) * 3 : 0xA5A5A5A5;
        require(static_cast<uint32_t*>(outputA.get().contents)[i] == a &&
                static_cast<uint32_t*>(outputB.get().contents)[i] == b, "argument table snapshots after clear/rebind and guards");
    }
}


// High mask bits, untouched nil initialization and direct-edit invalidation are
// tested without dispatching a shader with intentionally cleared inputs.
void sparseTableMetadata(id<MTLDevice> device) {
    NSError* error = nil;
    MVKMetal4ArgumentTables tables;
    CHECK_API(tables.initialize(device, {31, 128, 16}, &error));
    for (auto stage : {Stage::Vertex, Stage::Fragment, Stage::Compute}) {
        CHECK_API(tables.clearBindings(stage, &error));
        CHECK_API(tables.setBuffer(stage, nil, 0, 30, &error));
        CHECK_API(tables.setTexture(stage, nil, 127, &error));
        CHECK_API(tables.setSampler(stage, nil, 15, &error));
    }
    require(tables.getBindingWriteCount() == 0, "initialized nil metadata avoids clean-stage Metal writes");
    Owned<id<MTLBuffer>> buffer([device newBufferWithLength:64 options:MTLResourceStorageModeShared]);
    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:1 height:1 mipmapped:NO];
    Owned<id<MTLTexture>> texture([device newTextureWithDescriptor:descriptor]);
    Owned<MTLSamplerDescriptor*> samplerDescriptor([[MTLSamplerDescriptor alloc] init]);
    Owned<id<MTLSamplerState>> sampler([device newSamplerStateWithDescriptor:samplerDescriptor.get()]);
    require(buffer.get() && texture.get() && sampler.get(), "sparse table objects");
    CHECK_API(tables.setBufferWithStride(Stage::Vertex, buffer.get(), 4, 16, 30, &error));
    auto revision = tables.bufferBindingRevision(Stage::Vertex, 30);
    require(revision != 0 && tables.bufferBindingRevision(Stage::Vertex, 31) == 0,
            "buffer revision accepts only initialized configured slots");
    CHECK_API(tables.setBufferWithStride(Stage::Vertex, buffer.get(), 4, 16, 30, &error));
    require(tables.bufferBindingRevision(Stage::Vertex, 30) == revision, "same physical stride binding keeps revision");
    for (NSUInteger slot : {0u, 63u, 64u, 127u}) { CHECK_API(tables.setTexture(Stage::Vertex, texture.get(), slot, &error)); }
    CHECK_API(tables.setSampler(Stage::Vertex, sampler.get(), 15, &error));
    require(tables.getBindingWriteCount() == 6, "sparse highest-slot writes counted");
    CHECK_API(tables.clearBindings(Stage::Vertex, &error));
    require(tables.bufferBindingRevision(Stage::Vertex, 30) != revision, "explicit clear invalidates slot revision");
    require(tables.getBindingWriteCount() == 12, "clear only six dirty slots including stride and both texture mask words");
    CHECK_API(tables.resetForReuse(&error));
    require(tables.getBindingWriteCount() == 12, "second reset of clean table performs no writes");
    // Unknown metadata must restore even an address equal to the previous nil.
    [tables.getTable(Stage::Compute) setAddress:buffer.get().gpuAddress atIndex:30];
    [tables.getTable(Stage::Compute) setTexture:texture.get().gpuResourceID atIndex:127];
    [tables.getTable(Stage::Compute) setSamplerState:sampler.get().gpuResourceID atIndex:15];
    CHECK_API(tables.invalidateCachedBindings(Stage::Compute, &error));
    require(tables.bufferBindingRevision(Stage::Compute, 30) != 0, "direct invalidation retains cacheable fresh generation");
    CHECK_API(tables.clearBindings(Stage::Compute, &error));
    require(tables.getBindingWriteCount() == 12 + 31 + 128 + 16, "direct mutations invalidate and clear every configured slot");
    CHECK_API(tables.resetForReuse(&error));
    require(tables.getBindingWriteCount() == 187, "invalidated reset returns to clean metadata");
    // Preserve the SDK's distinct address-only / address+stride setter semantics.
    CHECK_API(tables.setBuffer(Stage::Vertex, buffer.get(), 0, 30, &error));
    CHECK_API(tables.setBufferWithStride(Stage::Vertex, buffer.get(), 0, 16, 30, &error));
    CHECK_API(tables.setBuffer(Stage::Vertex, buffer.get(), 0, 30, &error));
    CHECK_API(tables.clearBindings(Stage::Vertex, &error));
    require(tables.getBindingWriteCount() == 191, "setter-mode transitions and stride retirement remain explicit");
}

void deferredTableLeaseBindings(id<MTLDevice> device) {
    NSError* error = nil;
    MVKMetal4ArgumentTables tables;
    CHECK_API(tables.initialize(device, {31, 128, 16}, &error));
    Owned<id<MTLBuffer>> buffer([device newBufferWithLength:64 options:MTLResourceStorageModeShared]);
    auto* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:1 height:1 mipmapped:NO];
    Owned<id<MTLTexture>> texture([device newTextureWithDescriptor:descriptor]);
    Owned<MTLSamplerDescriptor*> samplerDescriptor([[MTLSamplerDescriptor alloc] init]);
    Owned<id<MTLSamplerState>> sampler([device newSamplerStateWithDescriptor:samplerDescriptor.get()]);
    require(buffer.get() && texture.get() && sampler.get(), "deferred table objects");
    for (auto stage : {Stage::Vertex, Stage::Fragment, Stage::Compute}) {
        CHECK_API(tables.setBufferWithStride(stage, buffer.get(), 4, 16, 30, &error));
        for (NSUInteger slot : {0u, 63u, 64u, 127u}) { CHECK_API(tables.setTexture(stage, texture.get(), slot, &error)); }
        CHECK_API(tables.setSampler(stage, sampler.get(), 15, &error));
    }
    auto writes = tables.getBindingWriteCount();
    auto revision = tables.bufferBindingRevision(Stage::Compute, 30);
    CHECK_API(tables.resetBindingsForNextEncoder(&error));
    require(tables.getBindingWriteCount() == writes && tables.bufferBindingRevision(Stage::Compute, 30) != revision,
            "logical reset invalidates memo without zeroing physical slots");
    revision = tables.bufferBindingRevision(Stage::Compute, 30);
    CHECK_API(tables.setBufferWithStride(Stage::Compute, buffer.get(), 4, 16, 30, &error));
    CHECK_API(tables.setTexture(Stage::Compute, texture.get(), 127, &error));
    CHECK_API(tables.setSampler(Stage::Compute, sampler.get(), 15, &error));
    require(tables.getBindingWriteCount() == writes && tables.bufferBindingRevision(Stage::Compute, 30) == revision,
            "same-value setters claim pending slots without native writes or generation changes");
    // Raw access must also resolve old unclaimed entries before external edits.
    auto raw = tables.getTable(Stage::Compute, &error);
    require(raw != nil && tables.getBindingWriteCount() == writes + 3,
            "only three unclaimed compute textures clear across both mask words");
    writes = tables.getBindingWriteCount();
    for (NSUInteger slot : {0u, 63u, 64u}) { CHECK_API(tables.setTexture(Stage::Compute, nil, slot, &error)); }
    require(tables.getBindingWriteCount() == writes, "resolved unclaimed textures are physically nil");
    require(tables.getTable(Stage::Vertex, &error) != nil && tables.getBindingWriteCount() == writes + 6,
            "later activation clears all six unclaimed inactive-stage entries");
    writes = tables.getBindingWriteCount();
    [raw setAddress:buffer.get().gpuAddress + 8 atIndex:30];
    CHECK_API(tables.invalidateCachedBindings(Stage::Compute, &error));
    require(tables.bufferBindingRevision(Stage::Compute, 30) != revision,
            "direct native mutation invalidates saved slot proof");
    CHECK_API(tables.setBufferWithStride(Stage::Compute, buffer.get(), 4, 16, 30, &error));
    require(tables.getBindingWriteCount() == writes + 1, "wrapper restores directly edited slot");
    CHECK_API(tables.resetForReuse(&error));
    writes = tables.getBindingWriteCount();
    for (auto stage : {Stage::Vertex, Stage::Fragment, Stage::Compute}) {
        CHECK_API(tables.setBufferWithStride(stage, nil, 0, 0, 30, &error));
        CHECK_API(tables.setTexture(stage, nil, 127, &error));
        CHECK_API(tables.setSampler(stage, nil, 15, &error));
    }
    require(tables.getBindingWriteCount() == writes, "full retirement clears claimed, unclaimed and invalidated stages");
}

void sequentialPrimaryTableSnapshots(id<MTLDevice> device) {
    NSError* error = nil;
    NSString* source = @"#include <metal_stdlib>\nusing namespace metal;\n"
        "kernel void sequential(constant uint2& value [[buffer(0)]], device uint* out [[buffer(1)]]) {"
        "out[0] = value.x + value.y * 3u; }";
    Owned<id<MTLLibrary>> library([device newLibraryWithSource:source options:nil error:&error]);
    require(library.get() != nil, "sequential primary library", error);
    Owned<id<MTLFunction>> function([library.get() newFunctionWithName:@"sequential"]);
    Owned<id<MTLComputePipelineState>> pipeline([device newComputePipelineStateWithFunction:function.get() error:&error]);
    Owned<id<MTLBuffer>> output([device newBufferWithLength:6 * sizeof(uint32_t) options:MTLResourceStorageModeShared]);
    require(pipeline.get() && output.get(), "sequential primary objects", error);
    std::memset(output.get().contents, 0xA5, output.get().length);
    auto queue = makeQueue(device); auto batch = begin(*queue);
    CHECK_API(batch->addResource(output.get(), &error));
    CHECK_API(batch->retainObject(pipeline.get(), &error));
    MVKMetal4PreparedGroupStamp prepared;
    prepared.script = 41; prepared.stage = 2; prepared.setMask = 1;
    prepared.sets[0] = {73, 5}; prepared.epochs = {2, 3, 4, 5, 6};
    auto preparedGroupHit = [&](MVKMetal4Submission& submission) {
        return submission.preparedGroupCache().lookup(prepared,
            [](uint32_t, uint32_t) -> uint64_t { return 5; }, [&] { return prepared; }).complete;
    };
    require(!preparedGroupHit(*batch), "new recording starts without prepared groups");
    // CPU metadata lifetime only: this synthetic token is not a resource
    // provenance claim. Native output ownership was acquired above.
    auto preparationOwner = std::make_shared<uint8_t>(0);
    std::weak_ptr<const MVKMetal4PreparedGroupSnapshot::RecordingProof> weakPrepared;
    {
        MVKMetal4PreparedResourceProof proof;
        proof.owners[0] = preparationOwner; proof.count = 1;
        MVKMetal4PreparedGroupSnapshot snapshot;
        auto retained = snapshot.remember(prepared, prepared,
            {{(const void*)output.get(), MVKMetal4PreparedBindingSnapshots::Kind::Buffer, proof}},
            {{0, 0, 0, 1, 5}}, {}, 1);
        require(bool(retained), "complete CPU preparation metadata admitted");
        weakPrepared = retained;
        batch->preparedGroupCache().remember(prepared, prepared, std::move(retained));
    }
    require(!weakPrepared.expired() && preparationOwner.use_count() == 1,
            "recording holds replaced CPU metadata without holding its resource proof owner");
    MVKMetal4ArgumentTables* identity = nullptr;
    uint32_t values[][2] = {{17, 31}, {17, 31}, {19, 37}, {17, 31}};
    uint64_t uploads[] = {1, 1, 2, 3};
    for (NSUInteger i = 0; i < 4; ++i) {
        auto* tables = batch->acquireArgumentTables(3, 1, 1, false, &error);
        require(tables != nullptr, "sequential primary lease", error);
        if (!identity) { identity = tables; }
        require(tables == identity, "one owned primary wrapper reused within the recording");
        require(preparedGroupHit(*batch), "prepared group survives sequential primary encoder leases");
        auto writes = tables->getBindingWriteCount();
        for (auto stage : {Stage::Vertex, Stage::Fragment, Stage::Compute}) {
            if (i == 2 && stage == Stage::Compute) { continue; }
            CHECK_API(tables->setBufferWithStride(stage, output.get(), 0, 4, 2, &error));
        }
        if (i == 1 || i == 2) {
            require(tables->getBindingWriteCount() == writes, "same-recording primary lease retains stable physical roots");
        }
        writes = tables->getBindingWriteCount();
        CHECK_API(tables->setBytes(Stage::Compute, values[i], sizeof(values[i]), 0, *batch, &error));
        if (i == 1) { require(tables->getBindingWriteCount() == writes, "byte-identical root avoids zero/restore writes across leases"); }
        require(tables->getByteUploadCount() == uploads[i], "identical values reuse same-recording upload; changed values allocate new immutable slice");
        CHECK_API(tables->setBuffer(Stage::Compute, output.get(), (i + 1) * sizeof(uint32_t), 1, &error));
        auto encoder = [batch->commandBuffer() computeCommandEncoder];
        require(encoder != nil, "sequential primary compute encoder");
        [encoder setComputePipelineState:pipeline.get()];
        CHECK_API(tables->bindCompute(encoder, &error));
        if (i == 2) {
            writes = tables->getBindingWriteCount();
            CHECK_API(tables->setBufferWithStride(Stage::Compute, nil, 0, 0, 2, &error));
            require(tables->getBindingWriteCount() == writes, "first stage bind clears an omitted old root before dispatch");
        }
        [encoder dispatchThreads:MTLSizeMake(1, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
        [encoder endEncoding];
        writes = tables->getBindingWriteCount();
        auto revision = tables->bufferBindingRevision(Stage::Compute, 0);
        CHECK_API(batch->releaseArgumentTables(tables, &error));
        require(tables->getBindingWriteCount() == writes && tables->bufferBindingRevision(Stage::Compute, 0) != revision,
                "lease return starts a fresh logical binding generation without physical zero writes");
        require(tables->getByteUploadCount() == uploads[i], "lease return preserves immutable upload cache");
    }
    CHECK_API(batch->end(&error));
    require(!preparedGroupHit(*batch) && weakPrepared.expired(),
            "native end drops CPU preparation metadata before GPU submission/completion");
    require(batch->commandBuffer() == nil, "ended batch does not expose a recording handle");
    CHECK_API(queue->submit(batch, &error));
    CHECK_API(batch->wait(kTimeoutMS, &error));
    CHECK_API(queue->waitIdle(kTimeoutMS, &error));
    require(batch->completed(), "completion was recorded");
    require(!preparedGroupHit(*batch), "GPU retirement preserves the cleared preparation state");
    auto next = begin(*queue);
    require(!preparedGroupHit(*next), "recycled pack does not carry proof into a new recording while old wrapper lives");
    finish(*queue, next);
    const auto* actual = static_cast<const uint32_t*>(output.get().contents);
    require(actual[0] == 0xA5A5A5A5 && actual[5] == 0xA5A5A5A5, "sequential primary output guards");
    uint32_t expected[] = {110, 110, 130, 110};
    for (NSUInteger i = 0; i < 4; ++i) {
        require(actual[i + 1] == expected[i], "earlier encoded dispatches preserve table and immutable byte snapshots after lease reuse");
    }
    MVKMetal4ArgumentTables uninitialized;
    reject([&](NSError** e) { return uninitialized.resetBindingsForNextEncoder(e); }, "uninitialized sequential reset");
}

void cachedTableUploads(id<MTLDevice> device) {
    NSError* error = nil;
    NSString* source = @"#include <metal_stdlib>\nusing namespace metal;\n"
        "kernel void cached(constant uint2& value [[buffer(0)]], device uint* out [[buffer(1)]]) {"
        "out[0] = value.x + value.y * 3u; }";
    Owned<id<MTLLibrary>> library([device newLibraryWithSource:source options:nil error:&error]);
    require(library.get() != nil, "cached upload shader library", error);
    Owned<id<MTLFunction>> function([library.get() newFunctionWithName:@"cached"]);
    Owned<id<MTLComputePipelineState>> pipeline([device newComputePipelineStateWithFunction:function.get() error:&error]);
    require(pipeline.get() != nil, "cached upload pipeline", error);
    Owned<id<MTLBuffer>> output([device newBufferWithLength:9 * sizeof(uint32_t) options:MTLResourceStorageModeShared]);
    require(output.get() != nil, "cached upload output", error);
    std::memset(output.get().contents, 0xA5, output.get().length);
    auto queue = makeQueue(device);
    MVKMetal4ArgumentTables tables;
    CHECK_API(tables.initializeCompute(device, {2, 0, 0}, &error));
    auto tableIdentity = tables.getTable(Stage::Compute);
    require(tables.getStageMask() == (NSUInteger(1) << static_cast<NSUInteger>(Stage::Compute)), "compute lease exact stage mask");
    uint32_t value[] = {17, 31, 0xDEADBEEF};
    uint32_t replacement[] = {100, 200};
    uint32_t expected[] = {110, 110, 110, 130, 130, 130, 130};
    {
        auto batch = begin(*queue);
        CHECK_API(batch->addResource(output.get(), &error));
        CHECK_API(batch->retainObject(pipeline.get(), &error));
        CHECK_API(batch->retainObject(tables.getTable(Stage::Compute), &error));
        auto encoder = [batch->commandBuffer() computeCommandEncoder];
        require(encoder != nil, "cached upload encoder");
        [encoder setComputePipelineState:pipeline.get()];
        CHECK_API(tables.bindCompute(encoder, &error));
        auto manual = batch->uploadBytesRange(replacement, sizeof(replacement), &error);
        require(manual.buffer != nil, "helper replacement upload", error);
        reject([&](NSError** e) { return tables.setBytes(Stage::Compute, nullptr, 8, 0, *batch, e); }, "nonempty null bytes");
        reject([&](NSError** e) { return tables.setBytes(Stage::Compute, value, 8, 2, *batch, e); }, "cached byte slot bounds");
        reject([&](NSError** e) { return tables.setBytes(Stage::Vertex, value, 8, 0, *batch, e); }, "cached bytes absent stage");
        for (NSUInteger i = 0; i < 6; ++i) {
            NSUInteger length = i >= 4 ? sizeof(value) : 2 * sizeof(uint32_t);
            if (i == 1) { CHECK_API(tables.setBuffer(Stage::Compute, manual.buffer, manual.offset, 0, &error)); }
            if (i == 2) { CHECK_API(tables.clearBindings(Stage::Compute, &error)); }
            if (i == 3) { value[0] = 19; value[1] = 37; }
            if (i == 5) {
                [tables.getTable(Stage::Compute) setAddress:manual.buffer.gpuAddress + manual.offset atIndex:0];
                CHECK_API(tables.invalidateCachedBindings(Stage::Compute, &error));
            }
            CHECK_API(tables.setBytes(Stage::Compute, value, length, 0, *batch, &error));
            uint64_t writes = tables.getBindingWriteCount(), uploads = tables.getByteUploadCount();
            uint32_t identical[] = {value[0], value[1], value[2]};
            CHECK_API(tables.setBytes(Stage::Compute, identical, length, 0, *batch, &error));
            require(tables.getBindingWriteCount() == writes && tables.getByteUploadCount() == uploads,
                    "byte-identical different host storage skips upload and slot write");
            CHECK_API(tables.setBuffer(Stage::Compute, output.get(), (i + 1) * sizeof(uint32_t), 1, &error));
            writes = tables.getBindingWriteCount();
            CHECK_API(tables.setBuffer(Stage::Compute, output.get(), (i + 1) * sizeof(uint32_t), 1, &error));
            require(tables.getBindingWriteCount() == writes, "identical address skips slot write");
            [encoder dispatchThreads:MTLSizeMake(1, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
        }
        require(tables.getByteUploadCount() == 3, "only initial, changed bytes and changed length upload");
        [encoder endEncoding];
        finish(*queue, batch);
    }
    // The old batch is retired and its arena can be overwritten by the pool.
    // Even byte-identical values must upload again in the new recording token.
    {
        auto batch = begin(*queue);
        CHECK_API(batch->addResource(output.get(), &error));
        CHECK_API(batch->retainObject(pipeline.get(), &error));
        CHECK_API(batch->retainObject(tables.getTable(Stage::Compute), &error));
        auto encoder = [batch->commandBuffer() computeCommandEncoder];
        require(encoder != nil, "cached upload second encoder");
        [encoder setComputePipelineState:pipeline.get()];
        CHECK_API(tables.resetForReuse(&error));
        require(tables.getTable(Stage::Compute) == tableIdentity, "retired reset preserves native table allocation");
        require(tables.retainedHostByteCapacity() <= 64 * 1024, "retired reset bounds retained host bytes");
        CHECK_API(tables.setBytes(Stage::Compute, value, sizeof(value), 0, *batch, &error));
        require(tables.getByteUploadCount() == 4, "new recording token forces fresh upload after prior batch retirement");
        CHECK_API(tables.setBuffer(Stage::Compute, output.get(), 7 * sizeof(uint32_t), 1, &error));
        CHECK_API(tables.bindCompute(encoder, &error));
        [encoder dispatchThreads:MTLSizeMake(1, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
        [encoder endEncoding];
        finish(*queue, batch);
    }
    const auto* actual = static_cast<const uint32_t*>(output.get().contents);
    require(actual[0] == 0xA5A5A5A5 && actual[8] == 0xA5A5A5A5, "cached upload output guards");
    for (NSUInteger i = 0; i < 7; ++i) { require(actual[i + 1] == expected[i], "cached immutable snapshots and helper restoration"); }

    MVKMetal4ArgumentTables vertexTables;
    CHECK_API(vertexTables.initialize(device, {1, 1, 1}, &error));
    CHECK_API(vertexTables.setBufferWithStride(Stage::Vertex, output.get(), 0, 4, 0, &error));
    auto writes = vertexTables.getBindingWriteCount();
    CHECK_API(vertexTables.setBufferWithStride(Stage::Vertex, output.get(), 0, 4, 0, &error));
    require(vertexTables.getBindingWriteCount() == writes, "identical dynamic stride skips write");
    CHECK_API(vertexTables.setBufferWithStride(Stage::Vertex, output.get(), 0, 8, 0, &error));
    require(vertexTables.getBindingWriteCount() == writes + 1, "changed dynamic stride writes slot");
    CHECK_API(vertexTables.setBuffer(Stage::Vertex, output.get(), 0, 0, &error));
    CHECK_API(vertexTables.setBufferWithStride(Stage::Vertex, output.get(), 0, 8, 0, &error));
    require(vertexTables.getBindingWriteCount() == writes + 3, "plain and strided setters conservatively differ");
    CHECK_API(vertexTables.setTexture(Stage::Fragment, nil, 0, &error));
    CHECK_API(vertexTables.setSampler(Stage::Fragment, nil, 0, &error));
    writes = vertexTables.getBindingWriteCount();
    CHECK_API(vertexTables.setTexture(Stage::Fragment, nil, 0, &error));
    CHECK_API(vertexTables.setSampler(Stage::Fragment, nil, 0, &error));
    require(vertexTables.getBindingWriteCount() == writes, "identical cleared resource IDs skip writes");
    reject([&](NSError** e) { return vertexTables.setBufferWithStride(Stage::Vertex, nil, 0, 4, 0, e); }, "cache does not bypass invalid nil stride");
    reject([&](NSError** e) { return vertexTables.setBuffer(Stage::Vertex, output.get(), output.get().length + 1, 0, e); }, "cache does not bypass range validation");
    CHECK_API(vertexTables.resetForReuse(&error));
    require(vertexTables.getStageMask() == 7, "primary lease exact stage mask");
    writes = vertexTables.getBindingWriteCount();
    CHECK_API(vertexTables.setBufferWithStride(Stage::Vertex, nil, 0, 0, 0, &error));
    CHECK_API(vertexTables.setTexture(Stage::Fragment, nil, 0, &error));
    CHECK_API(vertexTables.setSampler(Stage::Fragment, nil, 0, &error));
    require(vertexTables.getBindingWriteCount() == writes, "retired reset leaves known cleared actual slots");
    // Retired uploads can have arbitrary inline-data length. A pooled wrapper
    // must not retain unbounded host capacity after releasing the GPU uploads.
    {
        auto batch = begin(*queue);
        std::vector<uint8_t> largeBytes(64 * 1024 + 1, 0x37);
        CHECK_API(tables.setBytes(Stage::Compute, largeBytes.data(), largeBytes.size(), 0, *batch, &error));
        require(tables.retainedHostByteCapacity() > 64 * 1024, "oversized cache exists before retirement reset");
        finish(*queue, batch);
    }
    CHECK_API(tables.resetForReuse(&error));
    require(tables.retainedHostByteCapacity() <= 64 * 1024, "oversized retired host cache is released");
    MVKMetal4ArgumentTables uninitialized;
    require(uninitialized.getStageMask() == 0 && uninitialized.retainedHostByteCapacity() == 0, "uninitialized lease metadata is empty");
    reject([&](NSError** e) { return uninitialized.resetForReuse(e); }, "uninitialized reset fails");
}

void completeOverwriteHelperBindings(id<MTLDevice> device) {
    NSError* error = nil;
    NSString* source = @"#include <metal_stdlib>\nusing namespace metal;\n"
        "kernel void overwriteHelper(const device uint* input [[buffer(0)]], const device uint* arguments [[buffer(1)]], "
        "device uint* output [[buffer(2)]], device uint* result [[buffer(3)]], constant uint& value [[buffer(4)]]) { "
        "output[0] = input[0] + arguments[0] + value; result[0] = input[1] + arguments[1] + value; }";
    Owned<id<MTLLibrary>> library([device newLibraryWithSource:source options:nil error:&error]);
    require(library.get() != nil, "complete-overwrite helper library", error);
    Owned<id<MTLFunction>> function([library.get() newFunctionWithName:@"overwriteHelper"]);
    Owned<id<MTLComputePipelineState>> pipeline([device newComputePipelineStateWithFunction:function.get() error:&error]);
    require(pipeline.get() != nil, "complete-overwrite helper pipeline", error);
    const uint32_t values[] = {5, 7, 11, 13, 17, 19, 23};
    Owned<id<MTLBuffer>> input([device newBufferWithBytes:values length:sizeof(values) options:MTLResourceStorageModeShared]);
    Owned<id<MTLBuffer>> output([device newBufferWithLength:12 * sizeof(uint32_t) options:MTLResourceStorageModeShared]);
    require(input.get() && output.get(), "complete-overwrite helper buffers");
    std::memset(output.get().contents, 0xA5, output.get().length);
    auto queue = makeQueue(device);
    auto batch = begin(*queue);
    CHECK_API(batch->addResource(input.get(), &error));
    CHECK_API(batch->addResource(output.get(), &error));
    CHECK_API(batch->retainObject(pipeline.get(), &error));
    auto* primary = batch->acquireArgumentTables(5, 0, 0, false, &error);
    auto* helper = batch->acquireArgumentTables(5, 0, 0, true, &error);
    auto* clearedReference = batch->acquireArgumentTables(5, 0, 0, true, &error);
    require(primary && helper && clearedReference && helper != clearedReference, "distinct primary/helper leases", error);
    auto bindAll = [&](MVKMetal4ArgumentTables* table, NSUInteger firstOutput, NSUInteger parameterOffset) {
        return table->setBuffer(Stage::Compute, input.get(), 0, 0, &error) &&
            table->setBuffer(Stage::Compute, input.get(), 2 * sizeof(uint32_t), 1, &error) &&
            table->setBuffer(Stage::Compute, output.get(), firstOutput * sizeof(uint32_t), 2, &error) &&
            table->setBuffer(Stage::Compute, output.get(), (firstOutput + 1) * sizeof(uint32_t), 3, &error) &&
            table->setBuffer(Stage::Compute, input.get(), parameterOffset, 4, &error);
    };
    auto encoder = [batch->commandBuffer() computeCommandEncoder];
    require(encoder != nil, "complete-overwrite compute encoder");
    [encoder setComputePipelineState:pipeline.get()];
    unsigned dispatches = 0;
    auto dispatch = [&](MVKMetal4ArgumentTables* table) {
        CHECK_API(table->bindCompute(encoder, &error));
        [encoder dispatchThreads:MTLSizeMake(1, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
        ++dispatches;
    };
    CHECK_API(bindAll(primary, 7, 6 * sizeof(uint32_t)));
    dispatch(primary);
    CHECK_API(bindAll(helper, 1, 4 * sizeof(uint32_t)));
    dispatch(helper);
    const auto beforeReuse = helper->getBindingWriteCount();
    CHECK_API(bindAll(helper, 3, 5 * sizeof(uint32_t)));
    require(helper->getBindingWriteCount() - beforeReuse == 3,
            "complete overwrite preserves two unchanged slots and writes only three changed slots");
    dispatch(helper);
    CHECK_API(bindAll(clearedReference, 1, 4 * sizeof(uint32_t)));
    const auto beforeClear = clearedReference->getBindingWriteCount();
    CHECK_API(clearedReference->clearBindings(Stage::Compute, &error));
    CHECK_API(bindAll(clearedReference, 3, 5 * sizeof(uint32_t)));
    require(clearedReference->getBindingWriteCount() - beforeClear == 10,
            "ordinary cleared helper still zeroes and rewrites all five slots");
    bool valid = bindAll(helper, 9, input.get().length + sizeof(uint32_t));
    require(!valid && error != nil, "partial overwrite failure remains checked");
    if (valid) { dispatch(helper); }
    require(dispatches == 3, "failed complete overwrite cannot dispatch stale bindings");
    // The real command-encoder acquisition separately invalidates application
    // Compute bindings. Exercise the required primary table rebind/snapshot here.
    CHECK_API(bindAll(primary, 5, 6 * sizeof(uint32_t)));
    dispatch(primary);
    [encoder endEncoding];
    finish(*queue, batch);
    const uint32_t expected[] = {0xA5A5A5A5, 33, 37, 35, 39, 39, 43, 39, 43, 0xA5A5A5A5, 0xA5A5A5A5, 0xA5A5A5A5};
    const auto* actual = static_cast<const uint32_t*>(output.get().contents);
    for (NSUInteger i = 0; i < 12; ++i) {
        require(actual[i] == expected[i], "complete-overwrite snapshots, restored primary and failure guards");
    }
}

MVKMetal4ResourcePoolStats internalSignalPoolEvidence;
uint64_t internalSignalCompleted = 0;

void internalTimelinePackReuse(id<MTLDevice> device) {
    auto queue = makeQueue(device);
    Owned<id<MTLSharedEvent>> signal([device newSharedEvent]);
    Owned<id<MTLBuffer>> output([device newBufferWithLength:64 options:MTLResourceStorageModeShared]);
    require(signal.get() && output.get(), "pool proof resources");
    id<MTL4CommandBuffer> firstBuffer = nil;
    id<MTLBuffer> firstMarker = nil;
    std::shared_ptr<MVKMetal4Submission> previous;
    unsigned beforeDeaths = sentinelDeaths;
    NSError* error = nil;
    for (unsigned iteration = 0; iteration < 16; ++iteration) {
        auto batch = begin(*queue);
        auto registration = batch->resourceRegistrationStats();
        require(registration.retainedObjects == 0 && registration.residentResources == 0 &&
                registration.drawableRegistryLookups == 0, "new state has no old resource or drawable identities");
        auto buffer = batch->commandBuffer();
        auto marker = batch->completionMarker(&error);
        require(marker != nil, "pooled completion marker", error);
        require(batch->completionMarker(&error) == marker, "same batch marker is stable");
        if (!iteration) { firstBuffer = buffer; firstMarker = marker; }
        else {
            require(buffer == firstBuffer && marker == firstMarker, "actual buffer and marker objects were reused");
            // A completed wrapper outlives the returned pack. Destroy it while
            // the next recording owns the same Metal objects.
            require(previous->completed() && previous->commandBuffer() == nil, "old wrapper stays terminal after reuse");
            require(!batch->matchesRecordingToken(previous->recordingToken()), "reused host storage has a fresh weak control-block identity");
            previous.reset();
        }
        Owned<MVKFoundationLifetimeSentinel*> sentinel([MVKFoundationLifetimeSentinel new]);
        CHECK_API(batch->retainObject(sentinel.get(), &error));
        sentinel.reset();
        uint32_t value = 99;
        auto separate = batch->uploadBytes(&value, sizeof(value), &error);
        require(separate && separate != marker, "ordinary writable upload cannot alias the pooled marker");
        std::memset(output.get().contents, 0xA5, 64);
        CHECK_API(batch->addResource(output.get(), &error));
        CHECK_API(batch->addSignalEvent(signal.get(), iteration + 1, &error, true));
        auto encoder = [buffer computeCommandEncoder];
        require(encoder != nil, "pool proof encoder");
        [encoder fillBuffer:marker range:NSMakeRange(0, 4) value:uint8_t(0x31 + iteration)];
        intra(encoder, MTLStageBlit, MTLStageBlit);
        [encoder copyFromBuffer:marker sourceOffset:0 toBuffer:output.get() destinationOffset:16 size:4];
        [encoder endEncoding];
        finish(*queue, batch);
        ++internalSignalCompleted;
        require(sentinelDeaths == beforeDeaths + iteration + 1, "empty reused retained array releases old objects at retirement");
        reject([&](NSError** e) { return batch->completionMarker(e) != nil; }, "marker after retirement");
        require(signal.get().signaledValue >= iteration + 1, "notification retirement follows the actual requested signal");
        auto bytes = static_cast<const uint8_t*>(output.get().contents);
        for (NSUInteger i = 0; i < 64; ++i) {
            require(bytes[i] == (i >= 16 && i < 20 ? uint8_t(0x31 + iteration) : 0xA5), "reused marker content and guards");
        }
        auto stats = queue->resourcePoolStats();
        require(stats.primaryCreated == 1 && stats.tailCreated == 0 &&
                stats.primaryReused == iteration && stats.tailReused == 0,
                "sixteen actual-event completions reuse one primary and create zero tails");
        require(stats.primaryIdle == 1 && stats.tailIdle == 0 &&
                stats.idleBytes <= MVKMetal4ResourcePoolStats::maxIdleBytes, "retired packs bounded and available");
        require(stats.hostStorageReused == iteration && stats.hostStorageIdleBytes > 0 &&
                stats.hostStorageIdleBytes <= MVKMetal4ResourcePoolStats::maxHostStoragePayloadBytes &&
                stats.retainedObjectSlotsIdle <= MVKMetal4ResourcePoolStats::maxRetainedHostObjects,
                "bounded empty host capacity reused with each retired primary pack");
        previous = batch;
    }
    internalSignalPoolEvidence = queue->resourcePoolStats();
}


void emptyInternalTimelineWrapperDestruction(id<MTLDevice> device) {
    struct Owners {
        std::unique_ptr<MVKMetal4Queue> queue;
        std::shared_ptr<MVKMetal4Submission> batch;
        std::promise<bool> done;
        bool cleaned = false;
    };
    auto owners = std::make_shared<Owners>();
    owners->queue = makeQueue(device);
    owners->batch = begin(*owners->queue);
    Owned<id<MTLSharedEvent>> signal([device newSharedEvent]);
    require(signal.get() != nil, "empty internal signal allocation");
    NSError* error = nil;
    CHECK_API(owners->batch->addSignalEvent(signal.get(), 1, &error, true));
    CHECK_API(owners->batch->deferRelease([owners] { owners->cleaned = true; }, &error));
    CHECK_API(owners->batch->addCompletedHandler([owners, event=signal.get()](NSError* failure) {
        const auto stats = owners->queue->resourcePoolStats();
        bool okay = !failure && owners->cleaned && event.signaledValue >= 1 && stats.tailCreated == 0;
        owners->batch.reset(); owners->queue.reset();
        owners->done.set_value(okay);
    }, &error));
    CHECK_API(owners->batch->end(&error));
    auto future = owners->done.get_future();
    auto* queue = owners->queue.get();
    auto batch = owners->batch;
    bool submitted = queue->submit(batch, &error);
    require(submitted, "empty internal signal submitted", error);
    batch.reset();
    require(future.wait_for(std::chrono::milliseconds(kTimeoutMS)) == std::future_status::ready,
            "signal-only batch completes without a later submission");
    require(future.get(), "actual signal, mandatory cleanup and callback wrapper destruction");
}

void deviceResidencyBlockedRetirement(id<MTLDevice> device, bool typed = false) {
    NSError* error = nil;
    auto residency = MVKMetal4DeviceResidency::create(device, &error);
    require(bool(residency), "device-owned residency created", error);
    auto queue = MVKMetal4Queue::create(device, &error, residency);
    require(bool(queue), "queue attaches device-owned residency", error);
    constexpr NSUInteger size = 512;
    std::vector<uint8_t> expected(size);
    for (NSUInteger i = 0; i < size; ++i) { expected[i] = uint8_t(i * 17 + 3); }
    Owned<id<MTLBuffer>> input([device newBufferWithBytes:expected.data() length:size options:MTLResourceStorageModeShared]);
    Owned<id<MTLBuffer>> output([device newBufferWithLength:size options:MTLResourceStorageModeShared]);
    Owned<id<MTLSharedEvent>> event([device newSharedEvent]);
    require(input.get() && output.get() && event.get(), "residency gated transfer storage");
    HostEventGate gate(event.get());
    id<MTLBuffer> raw = input.get();
    CHECK_API(residency->registerAllocation(raw, &error));
    CHECK_API(residency->registerAllocation(raw, &error));
    std::weak_ptr<void> oldEntry = residency->lease(raw);
    require(!oldEntry.expired() && residency->residencySet().allocationCount == 1, "multiple wrappers register one allocation");
    auto batch = begin(*queue);
    CHECK_API(typed ? batch->addBufferResource(raw, &error) : batch->addResource(raw, &error));
    CHECK_API(typed ? batch->addBufferResource(output.get(), &error) : batch->addResource(output.get(), &error));
    CHECK_API(batch->addWaitEvent(event.get(), 1, &error));
    require(batch->resourceRegistrationStats().deviceResidencyLeases == 1, "owned resource uses queue set; unknown resource uses batch fallback");
    require(!residency->lease(output.get()), "unknown allocation is not promoted to an owned one");
    auto encoder = [batch->commandBuffer() computeCommandEncoder];
    require(encoder != nil, "residency copy encoder");
    [encoder copyFromBuffer:raw sourceOffset:0 toBuffer:output.get() destinationOffset:0 size:size];
    [encoder endEncoding];
    CHECK_API(batch->end(&error));
    CHECK_API(queue->submit(batch, &error));
    input.reset();
    residency->unregisterAllocation(raw);
    require(bool(residency->lease(raw)), "other wrapper owner remains registered");
    residency->unregisterAllocation(raw);
    require(!residency->lease(raw) && !oldEntry.expired(), "GPU lease outlives last Vulkan allocation owner");
    require(!batch->wait(0, &error), "GPU submission remains blocked");
    CHECK_API(residency->registerAllocation(raw, &error));
    std::weak_ptr<void> newEntry = residency->lease(raw);
    residency->unregisterAllocation(raw);
    require(newEntry.expired() && !oldEntry.expired() && residency->residencySet().allocationCount == 1,
            "new entry retirement cannot remove old in-flight allocation residency");
    gate.open();
    CHECK_API(batch->wait(kTimeoutMS, &error));
    CHECK_API(queue->waitIdle(kTimeoutMS, &error));
    require(oldEntry.expired() && residency->residencySet().allocationCount == 0, "GPU completion releases final residency lease");
    require(std::memcmp(output.get().contents, expected.data(), size) == 0, "gated native copy survives caller and allocation-owner release");
}

void deviceResidencyHeapAndView(id<MTLDevice> device, bool typed = false) {
    NSError* error = nil;
    auto residency = MVKMetal4DeviceResidency::create(device, &error);
    require(bool(residency), "heap/view residency created", error);
    auto queue = MVKMetal4Queue::create(device, &error, residency);
    require(bool(queue), "heap/view residency queue", error);
    Owned<MTLHeapDescriptor*> descriptor([MTLHeapDescriptor new]);
    descriptor.get().type = MTLHeapTypePlacement;
    descriptor.get().size = 4096;
    descriptor.get().storageMode = MTLStorageModePrivate;
    Owned<id<MTLHeap>> heap([device newHeapWithDescriptor:descriptor.get()]);
    require(heap.get() != nil, "owned placement heap");
    Owned<id<MTLBuffer>> buffer([heap.get() newBufferWithLength:256 options:MTLResourceStorageModePrivate offset:0]);
    Owned<id<MTLBuffer>> output([device newBufferWithLength:256 options:MTLResourceStorageModeShared]);
    auto* textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO];
    textureDescriptor.storageMode = MTLStorageModeShared;
    textureDescriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsagePixelFormatView;
    Owned<id<MTLTexture>> texture([device newTextureWithDescriptor:textureDescriptor]);
    Owned<id<MTLTexture>> view([texture.get() newTextureViewWithPixelFormat:MTLPixelFormatRGBA8Unorm]);
    require(buffer.get() && output.get() && texture.get() && view.get(), "heap buffer and owned texture view");
    CHECK_API(residency->registerAllocation(heap.get(), &error));
    CHECK_API(residency->registerAllocation(texture.get(), &error));
    std::weak_ptr<void> heapEntry = residency->lease(buffer.get());
    std::weak_ptr<void> textureEntry = residency->lease(view.get());
    require(!heapEntry.expired() && !textureEntry.expired(), "resources acquire actual heap/base allocation leases");
    auto batch = begin(*queue);
    CHECK_API(typed ? batch->addBufferResource(buffer.get(), &error) : batch->addResource(buffer.get(), &error));
    CHECK_API(typed ? batch->addTextureResource(view.get(), &error) : batch->addResource(view.get(), &error));
    CHECK_API(typed ? batch->addBufferResource(output.get(), &error) : batch->addResource(output.get(), &error));
    require(batch->resourceRegistrationStats().deviceResidencyLeases == 2, "heap and texture view use queue residency");
    auto encoder = [batch->commandBuffer() computeCommandEncoder];
    [encoder fillBuffer:buffer.get() range:NSMakeRange(0, 256) value:0x65];
    intra(encoder, MTLStageBlit, MTLStageBlit);
    [encoder copyFromBuffer:buffer.get() sourceOffset:0 toBuffer:output.get() destinationOffset:0 size:256];
    [encoder endEncoding];
    residency->unregisterAllocation(heap.get());
    residency->unregisterAllocation(texture.get());
    buffer.reset(); view.reset(); texture.reset(); heap.reset();
    require(!heapEntry.expired() && !textureEntry.expired(), "recording preserves base/heap after all caller owners release");
    finish(*queue, batch);
    require(heapEntry.expired() && textureEntry.expired() && residency->residencySet().allocationCount == 0,
            "heap/base registration retires after GPU work");
    auto* bytes = static_cast<const uint8_t*>(output.get().contents);
    for (unsigned i = 0; i < 256; ++i) { require(bytes[i] == 0x65, "owned heap remains resident through native blit"); }
}

void deviceResidencyIndependentOwner(id<MTLDevice> device) {
    NSError* error = nil;
    auto residency = MVKMetal4DeviceResidency::create(device, &error);
    require(bool(residency), "independent residency owner", error);
    Owned<id<MTLBuffer>> buffer([device newBufferWithLength:256 options:MTLResourceStorageModeShared]);
    CHECK_API(residency->registerAllocation(buffer.get(), &error));
    Owned<id<MTLResidencySet>> set([residency->residencySet() retain]);
    auto lease = residency->lease(buffer.get());
    std::weak_ptr<void> proof = lease;
    residency.reset(); buffer.reset();
    require(!proof.expired() && set.get().allocationCount == 1, "GPU lease owns set state independently of registry wrapper");
    lease.reset();
    require(proof.expired() && set.get().allocationCount == 0, "final independent lease safely removes native membership");
}

MVKMetal4ResourcePoolStats allocatorEpochEvidence;
uint64_t allocatorEpochCompleted = 0;
void allocatorEpochGPUReplay(id<MTLDevice> device) {
    auto queue = makeQueue(device);
    Owned<id<MTLBuffer>> output([device newBufferWithLength:512 options:MTLResourceStorageModeShared]);
    Owned<id<MTLSharedEvent>> signal([device newSharedEvent]);
    require(output.get() && signal.get(), "allocator epoch output and event");
    std::shared_ptr<MVKMetal4Submission> previous;
    static_assert(MVKMetal4ResourcePoolStats::maxAllocatorEpochRecordings >= 2 && MVKMetal4ResourcePoolStats::maxAllocatorEpochRecordings % 2 == 0, "native ending policy permits paired primary/tail records");
    // One primary and its one existing retirement tail end per execution.
    constexpr unsigned endingsPerExecution = 2;
    constexpr unsigned iterations = (MVKMetal4ResourcePoolStats::maxAllocatorEpochRecordings / endingsPerExecution) * 5;
    for (unsigned iteration = 0; iteration < iterations; ++iteration) {
        NSError* error = nil;
        auto batch = begin(*queue);
        if (previous) {
            require(previous->completed() && previous->commandBuffer() == nil,
                    "retired wrapper remains terminal across allocator epoch reuse");
            previous.reset();
        }
        std::memset(output.get().contents, 0xA5, 512);
        CHECK_API(batch->addResource(output.get(), &error));
        CHECK_API(batch->addSignalEvent(signal.get(), iteration + 1, &error));
        auto encoder = [batch->commandBuffer() computeCommandEncoder];
        require(encoder != nil, "allocator epoch native encoder");
        [encoder fillBuffer:output.get() range:NSMakeRange(64, 256) value:uint8_t(iteration + 1)];
        [encoder endEncoding];
        finish(*queue, batch);
        require(signal.get().signaledValue >= iteration + 1, "epoch signal and retirement tail completed");
        const auto bytes = static_cast<const uint8_t*>(output.get().contents);
        for (unsigned index = 0; index < 512; ++index) {
            require(bytes[index] == (index >= 64 && index < 320 ? uint8_t(iteration + 1) : 0xA5),
                    "allocator epoch fill and guard bytes");
        }
        const auto stats = queue->resourcePoolStats();
        require(stats.primaryCreated == 1 && stats.tailCreated == 1 &&
                stats.primaryReused == iteration && stats.tailReused == iteration,
                "native primary and tail packs reused across five bounded allocator epochs");
        const unsigned nativeEndings = (iteration + 1) * endingsPerExecution;
        require(stats.allocatorCreated == 1 && stats.allocatorReused == nativeEndings - 1 &&
                stats.allocatorResets == nativeEndings / MVKMetal4ResourcePoolStats::maxAllocatorEpochRecordings,
                "one shared allocator counts primary and tail native endings and resets at the configured bound after all users retire");
        require(stats.allocatorAvailable == 1, "retired small allocator remains a separately charged available epoch");
        require(stats.idleBytes <= MVKMetal4ResourcePoolStats::maxIdleBytes,
                "allocator epochs retain the existing idle memory bound");
        previous = batch;
    }
    require(queue->completedSubmissionCount() == iterations, "epoch records complete individually");
    allocatorEpochEvidence = queue->resourcePoolStats(); allocatorEpochCompleted = iterations;
}

int main(int argc, const char* argv[]) {
    if (argc > 2 || (argc == 2 && std::strcmp(argv[1], "--resource-registration") != 0)) { return 2; }
    @autoreleasepool {
        Owned<id<MTLDevice>> device(MTLCreateSystemDefaultDevice());
        NSMutableArray* results = [NSMutableArray array];
        unsigned failed = 0;
        auto test = [&](NSString* name, const std::function<void()>& body) {
            @autoreleasepool {
                try {
                    require(device.get() != nil, "Metal device available");
                    require([device.get() supportsFamily:MTLGPUFamilyMetal4], "native Metal 4 device support");
                    body();
                    [results addObject:@{@"name": name, @"passed": @YES}];
                } catch (const std::exception& error) {
                    ++failed;
                    [results addObject:@{@"name": name, @"passed": @NO,
                                         @"error": [NSString stringWithUTF8String:error.what()]}];
                }
            }
        };
        if (argc == 2) {
            test(@"state_rejections_and_empty_batch", [&] { stateAndEmptyBatch(device.get()); });
            test(@"generic_device_residency_gpu_retirement", [&] { deviceResidencyBlockedRetirement(device.get()); });
            test(@"typed_device_residency_gpu_retirement", [&] { deviceResidencyBlockedRetirement(device.get(), true); });
            test(@"generic_device_residency_heap_and_texture_view", [&] { deviceResidencyHeapAndView(device.get()); });
            test(@"typed_device_residency_heap_and_texture_view", [&] { deviceResidencyHeapAndView(device.get(), true); });
            test(@"device_residency_independent_owner", [&] { deviceResidencyIndependentOwner(device.get()); });
            NSDictionary* report = @{@"suite": @"metal4_resource_registration", @"native_command_backend": @YES,
                @"device": device.get() ? device.get().name : @"unavailable", @"test_count": @(results.count),
                @"passed": @(results.count - failed), @"failed": @(failed), @"tests": results};
            NSData* json = [NSJSONSerialization dataWithJSONObject:report options:0 error:nil];
            std::fwrite(json.bytes, 1, json.length, stdout); std::fputc('\n', stdout);
            return failed ? 1 : 0;
        }
        test(@"resource_pack_creation_reuse_and_old_wrapper_detach", [&] { resourcePackReuse(device.get()); });
        test(@"allocator_epochs_repeated_fill_signal_tail_and_guards", [&] { allocatorEpochGPUReplay(device.get()); });
        test(@"resource_pack_timeout_cancel_and_idle_bounds", [&] { resourcePackBlockedAndCancel(device.get()); });
        test(@"resource_pack_device_loss_does_not_recycle_inflight", [&] { resourcePackPoisoned(device.get()); });
        test(@"compute_only_table_clear_and_encoding_snapshots", [&] { computeOnlyTableSnapshots(device.get()); });
        test(@"sparse_table_metadata_nil_initialization_dirty_reset_and_invalidation", [&] { sparseTableMetadata(device.get()); });
        test(@"logical_lease_pending_slots_same_value_claim_direct_access_and_full_retirement", [&] { deferredTableLeaseBindings(device.get()); });
        test(@"sequential_primary_leases_immutable_upload_and_inactive_stage_snapshots", [&] { sequentialPrimaryTableSnapshots(device.get()); });
        test(@"cached_slots_immutable_bytes_helper_restore_and_cross_batch", [&] { cachedTableUploads(device.get()); });
        test(@"complete_overwrite_five_buffer_writes_snapshots_and_restore", [&] { completeOverwriteHelperBindings(device.get()); });
        test(@"state_rejections_and_empty_batch", [&] { stateAndEmptyBatch(device.get()); });
        test(@"fill_copy_private_roundtrip_and_guards", [&] { transferRoundTrip(device.get()); });
        test(@"immutable_upload_arena_alignment_rollover_gpu_offsets", [&] { immutableUploadArena(device.get()); });
        test(@"caller_release_and_completion_retirement", [&] { objectRetirement(device.get()); });
        test(@"bulk_primitive_input_validation_retention_and_immutable_upload", [&] { bulkPrimitiveInputs(device.get()); });
        test(@"independent_submissions_with_shared_allocator_storage", [&] { multipleSubmissions(device.get()); });
        test(@"compute_native_table_inline_upload", [&] { computeWithTable(device.get()); });
        test(@"offscreen_native_render_1x", [&] { offscreenRender(device.get(), 1); });
        test(@"offscreen_native_render_msaa4_resolve", [&] { offscreenRender(device.get(), 4); });
        test(@"blocked_event_timeout_preserves_lifetime", [&] { blockedEventLifetime(device.get()); });
        test(@"two_native_queues_event_transfer", [&] { twoQueueEventTransfer(device.get()); });
        test(@"deferred_cleanup_cancel_and_complete", [&] { deferredCleanupStates(device.get()); });
        test(@"mixed_vbo_offsets_dynamic_stride_render", [&] { offscreenRender(device.get(), 1, true); });
        test(@"fragment_texture_sampler_root_bindings", [&] { offscreenRender(device.get(), 1, false, true); });
        test(@"concurrent_idle_wait_deadline_includes_lock", [&] { concurrentIdleDeadline(device.get()); });
        test(@"completion_callbacks_after_retirement_and_not_cancel", [&] { callbackRetirementOrder(device.get()); });
        test(@"internal_timeline_sixteen_reuses_without_tail", [&] { internalTimelinePackReuse(device.get()); });
        test(@"empty_internal_timeline_actual_signal_and_wrapper_destruction", [&] { emptyInternalTimelineWrapperDestruction(device.get()); });
        test(@"device_residency_gpu_retirement_and_registration_incarnations", [&] { deviceResidencyBlockedRetirement(device.get()); });
        test(@"device_residency_owned_heap_and_texture_view", [&] { deviceResidencyHeapAndView(device.get()); });
        test(@"device_residency_independent_state_and_final_lease", [&] { deviceResidencyIndependentOwner(device.get()); });
        NSDictionary* report = @{@"suite": @"metal4_r49_native_lifetime_foundation", @"native_command_backend": @YES,
                                  @"shared_allocator_native_ending_proof": @{
                                      @"completed_batches": @(allocatorEpochCompleted),
                                      @"native_endings": @(allocatorEpochCompleted * 2),
                                      @"allocator_created": @(allocatorEpochEvidence.allocatorCreated),
                                      @"allocator_reused": @(allocatorEpochEvidence.allocatorReused),
                                      @"allocator_resets": @(allocatorEpochEvidence.allocatorResets),
                                      @"allocator_available": @(allocatorEpochEvidence.allocatorAvailable),
                                      @"primary_created": @(allocatorEpochEvidence.primaryCreated),
                                      @"tail_created": @(allocatorEpochEvidence.tailCreated)},
                                  @"resource_pool_creation_reuse_proof": @{
                                      @"completed_batches": @(poolReuseCompleted),
                                      @"primary_created": @(poolReuseEvidence.primaryCreated),
                                      @"primary_reused": @(poolReuseEvidence.primaryReused),
                                      @"tail_created": @(poolReuseEvidence.tailCreated),
                                      @"tail_reused": @(poolReuseEvidence.tailReused),
                                      @"host_storage_reused": @(poolReuseEvidence.hostStorageReused),
                                      @"host_storage_idle_payload_bytes": @(poolReuseEvidence.hostStorageIdleBytes),
                                      @"retained_object_high_water_slots": @(poolReuseEvidence.retainedObjectSlotsIdle),
                                      @"idle_reported_bytes": @(poolReuseEvidence.idleBytes)},
                                  @"internal_timeline_notification_proof": @{
                                      @"completed_batches": @(internalSignalCompleted),
                                      @"primary_created": @(internalSignalPoolEvidence.primaryCreated),
                                      @"primary_reused": @(internalSignalPoolEvidence.primaryReused),
                                      @"tail_created": @(internalSignalPoolEvidence.tailCreated),
                                      @"tail_reused": @(internalSignalPoolEvidence.tailReused)},
                                  @"bar_acceptance": @NO, @"device": device.get() ? device.get().name : @"unavailable",
                                  @"test_count": @(results.count), @"passed": @(results.count - failed),
                                  @"failed": @(failed), @"tests": results};
        NSData* json = [NSJSONSerialization dataWithJSONObject:report options:0 error:nil];
        std::fwrite(json.bytes, 1, json.length, stdout);
        std::fputc('\n', stdout);
        return failed ? 1 : 0;
    }
}
