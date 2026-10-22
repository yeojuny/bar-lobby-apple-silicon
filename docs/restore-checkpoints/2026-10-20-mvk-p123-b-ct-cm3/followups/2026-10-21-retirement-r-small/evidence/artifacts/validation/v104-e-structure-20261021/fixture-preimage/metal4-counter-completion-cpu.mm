// CPU-only tests of the actual submission implementation. Every receiver that
// could allocate GPU resources or submit work is an NSObject double. This tests
// host ordering/lifetime, not native Metal execution or timestamp accuracy.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <cstdio>
#include <functional>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

@interface R77Options : MTL4CommitOptions {
@public std::vector<MTL4CommitFeedbackHandler> handlers;
}
@end
@implementation R77Options
- (void)addFeedbackHandler:(MTL4CommitFeedbackHandler)handler { handlers.push_back([handler copy]); }
- (void)dealloc { for (auto h : handlers) { [h release]; } [super dealloc]; }
@end
#include "MVKMetal4DependencyScopes.h"
#define private public
#include "MVKMetal4Submission.h"
#undef private
#define MTL4CommitOptions R77Options
#include "MVKMetal4Submission.mm"
#undef MTL4CommitOptions

static std::atomic<unsigned> checks{0};
static void check(bool value, const char* message) {
    ++checks;
    if (!value) { throw std::runtime_error(message); }
}
static unsigned liveEvents = 0;
@interface R77Event : NSObject { @public id<MTLDevice> ownerDevice; } @end
@implementation R77Event
- (id<MTLDevice>)device { return ownerDevice; }
- (id)init { if ((self = [super init])) { ++liveEvents; } return self; }
- (void)dealloc { --liveEvents; [super dealloc]; }
@end

// Reuse the established r48 CPU shared-event pattern. Its real submission
// notification owner exposes the group; no production inspection hook is added.
@interface R77DiagnosticEvent : R77Event <MTLSharedEvent> {
@public
    uint64_t counter, target;
    NSString* eventLabel;
    NSMutableArray* notifications;
}
- (void)deliver;
@end
@implementation R77DiagnosticEvent
- (id)init { if ((self = [super init])) { notifications = [NSMutableArray new]; } return self; }
- (id<MTLDevice>)device { return ownerDevice; }
- (NSString*)label { return eventLabel; }
- (void)setLabel:(NSString*)value { [eventLabel release]; eventLabel = [value copy]; }
- (uint64_t)signaledValue { return counter; }
- (void)setSignaledValue:(uint64_t)value { counter = value; }
- (MTLSharedEventHandle*)newSharedEventHandle { return nil; }
- (BOOL)waitUntilSignaledValue:(uint64_t)value timeoutMS:(uint64_t)milliseconds {
    (void)milliseconds; return counter >= value;
}
- (void)notifyListener:(MTLSharedEventListener*)listener atValue:(uint64_t)value block:(MTLSharedEventNotificationBlock)block {
    check(listener != nil && value > counter, "diagnostic fixture observes the pending actual event value");
    target = value;
    id copied = [block copy]; [notifications addObject:copied]; [copied release];
}
- (void)deliver {
    counter = target;
    for (MTLSharedEventNotificationBlock block in notifications) { block((id<MTLSharedEvent>)self, counter); }
}
- (void)dealloc { [notifications release]; [eventLabel release]; [super dealloc]; }
@end
@interface R77Feedback : NSObject <MTL4CommitFeedback> { @public NSError* failure; } @end
@implementation R77Feedback
- (NSError*)error { return failure; }
- (CFTimeInterval)GPUStartTime { return 0; }
- (CFTimeInterval)GPUEndTime { return 0; }
@end
@interface R77Allocator : NSObject {
@public
    unsigned begins, ends, resets, sizeQueries;
    bool recording;
    uint64_t bytes;
}
- (void)reset;
- (NSUInteger)allocatedSize;
@end
@implementation R77Allocator
- (id)init { if ((self = [super init])) { bytes = 4096; } return self; }
- (void)reset {
    check(!recording, "reset cannot overlap an unfinished recording");
    ++resets;
}
- (NSUInteger)allocatedSize { ++sizeQueries; return bytes; }
@end

@interface R77Residency : NSObject {
@public
    unsigned adds, removes, commits, sizeQueries;
    uint64_t bytes;
}
- (void)addAllocation:(id)allocation;
- (void)removeAllocation:(id)allocation;
- (void)removeAllAllocations;
- (void)commit;
- (NSUInteger)allocatedSize;
@end
@implementation R77Residency
- (id)init { if ((self = [super init])) { bytes = 128; } return self; }
- (void)addAllocation:(id)allocation { (void)allocation; ++adds; }
- (void)removeAllocation:(id)allocation { (void)allocation; ++removes; }
- (void)removeAllAllocations { ++removes; }
- (void)commit { ++commits; }
- (NSUInteger)allocatedSize { ++sizeQueries; return bytes; }
@end

@interface R77Allocation : NSObject {
@public id<MTLDevice> device;
}
- (id<MTLDevice>)device;
- (NSUInteger)allocatedSize;
@end
@implementation R77Allocation
- (id<MTLDevice>)device { return device; }
- (NSUInteger)allocatedSize { return 4; }
@end

@interface R77Encoder : NSObject {
@public unsigned fills, ends, barriers;
    std::vector<char>* commands;
}
- (void)barrierAfterQueueStages:(MTLStages)after beforeStages:(MTLStages)before
            visibilityOptions:(MTL4VisibilityOptions)visibility;
- (void)fillBuffer:(id<MTLBuffer>)buffer range:(NSRange)range value:(uint8_t)value;
- (void)endEncoding;
@end
@implementation R77Encoder
- (void)barrierAfterQueueStages:(MTLStages)after beforeStages:(MTLStages)before
            visibilityOptions:(MTL4VisibilityOptions)visibility {
    check(after == MTLStageAll && before == MTLStageBlit && visibility == MTL4VisibilityOptionNone,
          "entry bridge covers all queue stages without inventing a timestamp stage");
    ++barriers; commands->push_back('B');
}
- (void)fillBuffer:(id<MTLBuffer>)buffer range:(NSRange)range value:(uint8_t)value {
    check(buffer != nil && range.location == 0 && range.length == 4 && value == 0,
            "tail retains its four-byte completion fill");
    ++fills; commands->push_back('M');
}
- (void)endEncoding { ++ends; }
@end

@interface R77Buffer : NSObject {
@public
    R77Allocator* allocator; // Borrowed, as in an ended Metal recording.
    R77Encoder* encoder;
    unsigned begins, ends, uses;
    bool recording, failEncoder;
    NSMutableArray* associations;
    std::vector<char> commands;
}
- (void)beginCommandBufferWithAllocator:(id<MTL4CommandAllocator>)value;
- (void)endCommandBuffer;
- (void)useResidencySet:(id<MTLResidencySet>)value;
- (id<MTL4ComputeCommandEncoder>)computeCommandEncoder;
@end
@implementation R77Buffer
- (id)init {
    if ((self = [super init])) {
        encoder = [R77Encoder new]; encoder->commands = &commands; associations = [NSMutableArray new];
    }
    return self;
}
- (void)beginCommandBufferWithAllocator:(id<MTL4CommandAllocator>)value {
    allocator = (R77Allocator*)value;
    check(allocator != nil && !allocator->recording && !recording,
            "one allocator services only one recording at a time");
    ++begins; ++allocator->begins; recording = true; allocator->recording = true;
    commands.clear();
    [associations removeAllObjects];
}
- (void)endCommandBuffer {
    check(recording && allocator->recording, "end closes the current allocator attachment");
    ++ends; ++allocator->ends; recording = false; allocator->recording = false;
}
- (void)useResidencySet:(id<MTLResidencySet>)value {
    check(recording && value != nil, "a used set is reattached during this recording");
    ++uses; [associations addObject:value];
}
- (id<MTL4ComputeCommandEncoder>)computeCommandEncoder {
    return failEncoder ? nil : (id<MTL4ComputeCommandEncoder>)encoder;
}
- (void)writeTimestampIntoHeap:(id)heap atIndex:(NSUInteger)index {
    (void)index; check(recording && heap, "timestamp in a recording"); commands.push_back('T');
}
- (void)resolveCounterHeap:(id)heap withRange:(NSRange)range intoBuffer:(MTL4BufferRange)destination
                 waitFence:(id)wait updateFence:(id)update {
    (void)range; (void)destination;
    check(recording && heap && !wait && !update, "resolve uses queue completion, no synthetic fence");
    commands.push_back('R');
}
- (void)dealloc {
    if (recording) { allocator->recording = false; }
    [encoder release]; [associations release]; [super dealloc];
}
@end


struct QueueOp { char kind; uint64_t value; id event; std::vector<R77Buffer*> buffers; };
@interface R77Drawable : NSObject
- (void)present;
- (void)presentAtTime:(CFTimeInterval)time;
@end
@implementation R77Drawable
- (void)present {}
- (void)presentAtTime:(CFTimeInterval)time { (void)time; }
@end
@interface R77Queue : NSObject {
@public
    std::vector<QueueOp> operations;
    std::vector<R77Options*> commits;
    bool inlineFeedback;
    std::function<void()> duringCommit;
}
- (void)finish:(NSUInteger)index error:(NSError*)error;
- (void)clearFeedback;
@end
@implementation R77Queue
- (void)commit:(id<MTL4CommandBuffer> const*)buffers count:(NSUInteger)count options:(MTL4CommitOptions*)options {
    QueueOp op{'C', 0, nil, {}};
    for (NSUInteger i = 0; i < count; ++i) {
        auto b = (R77Buffer*)buffers[i]; check(!b->recording, "submit only ended segments");
        op.buffers.push_back(b);
    }
    operations.push_back(std::move(op)); commits.push_back([(R77Options*)options retain]);
    if (inlineFeedback) { [self finish:commits.size() - 1 error:nil]; }
    if (duringCommit) { duringCommit(); }
}
- (void)signalEvent:(id)event value:(uint64_t)value { operations.push_back({'S', value, event, {}}); }
- (void)waitForEvent:(id)event value:(uint64_t)value { operations.push_back({'W', value, event, {}}); }
- (void)waitForDrawable:(id)drawable { operations.push_back({'D', 0, drawable, {}}); }
- (void)signalDrawable:(id)drawable { operations.push_back({'P', 0, drawable, {}}); }
- (void)finish:(NSUInteger)index error:(NSError*)error {
    check(index < commits.size(), "feedback index");
    auto feedback = [R77Feedback new]; feedback->failure = error;
    for (auto handler : commits[index]->handlers) { handler(feedback); }
    [feedback release];
}
- (void)clearFeedback { for (auto c : commits) { [c release]; } commits.clear(); }
- (void)dealloc { [self clearFeedback]; [super dealloc]; }
@end
@interface R77Device : NSObject {
@public
    unsigned allocators, buffers, residencies, events;
    bool failNextEncoder, failNextBuffer, failNextEvent;
    R77Allocator* lastAllocator;
    R77Buffer* lastBuffer;
    R77Queue* nativeQueue;
}
@end
@implementation R77Device
- (id<MTL4CommandAllocator>)newCommandAllocator {
    ++allocators; lastAllocator = [R77Allocator new]; return (id<MTL4CommandAllocator>)lastAllocator;
}
- (id<MTL4CommandBuffer>)newCommandBuffer {
    if (failNextBuffer) { failNextBuffer = false; return nil; }
    ++buffers; lastBuffer = [R77Buffer new];
    lastBuffer->failEncoder = failNextEncoder; failNextEncoder = false;
    return (id<MTL4CommandBuffer>)lastBuffer;
}
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options {
    check(length == 4 && options == MTLResourceStorageModeShared, "only CPU-mocked markers allocated");
    auto allocation = [R77Allocation new]; allocation->device = (id<MTLDevice>)self;
    return (id<MTLBuffer>)allocation;
}
- (id<MTLResidencySet>)newResidencySetWithDescriptor:(MTLResidencySetDescriptor*)desc error:(NSError**)error {
    (void)desc; if (error) { *error = nil; } ++residencies;
    return (id<MTLResidencySet>)[R77Residency new];
}
- (BOOL)supportsFamily:(MTLGPUFamily)family { return family == MTLGPUFamilyMetal4; }
- (id<MTL4CommandQueue>)newMTL4CommandQueueWithDescriptor:(MTL4CommandQueueDescriptor*)desc error:(NSError**)error {
    (void)desc; if (error) { *error = nil; } nativeQueue = [R77Queue new];
    return (id<MTL4CommandQueue>)nativeQueue;
}
- (id<MTLEvent>)newEvent {
    if (failNextEvent) { failNextEvent = false; return nil; }
    ++events; auto event = [R77Event new]; event->ownerDevice = (id<MTLDevice>)self;
    return (id<MTLEvent>)event;
}
@end

struct Fixture {
    R77Device* device = [R77Device new];
    std::unique_ptr<MVKMetal4Queue> queue = MVKMetal4Queue::create((id<MTLDevice>)device);
    id<MTL4CounterHeap> heap = (id<MTL4CounterHeap>)[NSObject new];
    Fixture() { check(bool(queue), "mock queue created"); }
    ~Fixture() { [device->nativeQueue clearFeedback]; queue.reset(); [heap release]; [device release]; }
    std::shared_ptr<MVKMetal4Submission> begin() { auto b = queue->begin(); check(bool(b), "recording acquired"); return b; }
    R77Queue* native() { return device->nativeQueue; }
    void finishAll() {
        for (size_t i = 0; i < native()->commits.size(); ++i) { [native() finish:i error:nil]; }
    }
    void stamp(const std::shared_ptr<MVKMetal4Submission>& b, unsigned index = 0) {
        check(b->writeTimestamp(heap, index), "timestamp encoded");
    }
    void resolve(const std::shared_ptr<MVKMetal4Submission>& b) {
        check(b->resolveCounterHeap(heap, NSMakeRange(0, 1), MTL4BufferRangeMake(4096, 8)), "resolve encoded");
    }
};
static void ordinaryAndCancellation() {
    Fixture f;
    auto b = f.begin(); auto original = b->commandBuffer(); auto epoch = b->_state->allocatorUse.epoch;
    check(b->end() && f.queue->submit(b), "ordinary submit");
    check(f.device->events == 0 && f.native()->commits.size() == 1 &&
          f.native()->operations[0].buffers[0] == (R77Buffer*)original, "ordinary path remains one commit without counter allocations");
    [f.native() finish:0 error:nil]; check(b->completed(), "ordinary complete");
    [f.native() clearFeedback];
    b = f.begin(); f.stamp(b); epoch = b->_state->allocatorUse.epoch;
    check(epoch->writer && epoch->liveUses == 1 && b->_state->counterPrefixes.size() == 1, "internal split retains single exclusive writer");
    auto other = f.begin();
    check(other->_state->allocatorUse.epoch != epoch, "another recording cannot borrow the still-open writer");
    b.reset();
    check(epoch->state == MVKMetal4AllocatorState::DiscardOnly && !epoch->liveUses, "cancelled open split discards its epoch");
    check(f.queue->_state->counterProof == MVKMetal4CounterProof::Closed, "recording and cancellation never publish queue proof");
    check(other->end(), "independent record remains valid");
}
// Partial-order oracle: opaque heap accesses have no Dispatch/Blit stage.
// All-to-Blit barriers order only stage nodes; they cannot complete an unknown
// opaque write. Timestamp predecessor completion must consume the real marker.
// Disabling any required edge exposes a hazard independently of queue metadata.
static bool orderedCounters(const std::vector<QueueOp>& operations, bool events, bool timestampOrder,
                            bool unknownWrite = true, bool markerBridge = true) {
    uint64_t submitted = unknownWrite ? 1 : 0, completedPrefix = 0, signalled = 0, stageNodes = 0;
    unsigned next = 1;
    std::vector<std::pair<unsigned, bool>> accesses;
    if (unknownWrite) { accesses.emplace_back(0, true); }
    for (const auto& op : operations) {
        if (op.kind == 'S') { if (events) { signalled = submitted; } continue; }
        if (op.kind == 'W') { if (events) { completedPrefix |= signalled; } continue; }
        for (auto buffer : op.buffers) {
            uint64_t priorInBuffer = 0, markerPredecessors = 0;
            for (char command : buffer->commands) {
                if (command == 'B') { markerPredecessors = markerBridge ? stageNodes : 0; continue; }
                check(next < 64, "bounded oracle graph");
                const bool write = command == 'T';
                const bool counter = write || command == 'R';
                const uint64_t predecessors = completedPrefix | (write && timestampOrder ? priorInBuffer : 0) |
                    (command == 'M' ? markerPredecessors : 0);
                if (write && (stageNodes & ~predecessors)) { return false; }
                if (counter) {
                    for (const auto& access : accesses) {
                        if ((write || access.second) && !(predecessors & (uint64_t{1} << access.first))) { return false; }
                    }
                    accesses.emplace_back(next, write);
                }
                if (!write) { stageNodes |= (uint64_t{1} << next) | predecessors; }
                priorInBuffer |= (uint64_t{1} << next) | predecessors;
                submitted |= uint64_t{1} << next++;
            }
        }
    }
    return true;
}
static void boundariesAndFeedback() {
    std::array<unsigned, 4> order{0,1,2,3};
    do {
        Fixture f;
        f.queue->_state->counterProof = MVKMetal4CounterProof::Unknown;
        auto b = f.begin(); auto epoch = b->_state->allocatorUse.epoch;
        auto a = (R77Allocator*)epoch->allocator; unsigned done = 0, cleanup = 0;
        b->addCompletedHandler([&](NSError* e) { check(!e, "successful completion"); ++done; });
        b->_state->cleanup.emplace_back([&] { ++cleanup; });
        ((R77Buffer*)b->commandBuffer())->commands.push_back('G'); // Keep the nonempty four-range retirement oracle.
        f.stamp(b); auto timestampBuffer = b->commandBuffer(); f.stamp(b, 1);
        check(b->commandBuffer() == timestampBuffer, "adjacent writes share command-buffer ordering");
        f.resolve(b); auto resolveBuffer = b->commandBuffer(); f.resolve(b);
        check(b->commandBuffer() == resolveBuffer, "adjacent resolves share completion proof");
        // Reuse after a reset needs the actual new timestamp to wait for earlier
        // native counter reads/writes, not a pretend stage for the CPU reset.
        f.stamp(b); check(b->commandBuffer() == resolveBuffer, "reuse waits for prior current-buffer work via timestamp API");
        f.resolve(b);
        check(b->_state->counterPrefixes.size() == 3 && a->begins == 4 && a->ends == 3,
              "only entry and writes-before-resolve boundaries split");
        check(b->end() && f.queue->submit(b), "counter ranges adopted");
        check(f.device->events == 1 && f.native()->commits.size() == 4, "one event serves four ranges");
        const auto& ops = f.native()->operations;
        check(ops.size() == 10 && ops[0].kind == 'C', "range operation count");
        for (unsigned i = 1; i < 4; ++i) {
            const auto& signal = ops[3*i-2]; const auto& wait = ops[3*i-1];
            check(signal.kind == 'S' && wait.kind == 'W' && signal.event == wait.event &&
                  signal.value == i + 1 && wait.value == i + 1 && ops[3*i].kind == 'C', "signal/wait stays between successive commits");
        }
        check(orderedCounters(ops, true, true), "opaque writes, resolves and slot reuse have completion predecessors");
        check(!orderedCounters(ops, false, true), "negative control: stage-only path misses opaque queue writes");
        check(!orderedCounters(ops, true, false), "negative control: unordered same-buffer timestamps miss slot reuse");
        for (const auto& op : ops) for (auto buffer : op.buffers) {
            check([buffer->associations containsObject:b->_state->pack->stableResidency], "every segment uses shared stable residency");
        }
        // A later open writer may append to the same epoch; no completed prefix
        // may reset it or recycle the original logical record early.
        auto later = f.begin(); check(later->_state->allocatorUse.epoch == epoch, "ended group shares allocator with later recording");
        const auto resets = a->resets;
        for (unsigned i = 0; i < 4; ++i) {
            [f.native() finish:order[i] error:nil]; [f.native() finish:order[i] error:nil];
            check(done == (i == 3) && cleanup == (i == 3), "all distinct feedbacks required exactly once");
            check(a->resets == resets && epoch->writer, "feedback never resets concurrent writer memory");
        }
        check(b->completed() && later->end(), "completion preserves following record");
    } while (std::next_permutation(order.begin(), order.end()));
}
static unsigned counterPairs(const std::vector<QueueOp>& operations) {
    unsigned pairs = 0;
    for (size_t i = 1; i < operations.size(); ++i) {
        if (operations[i-1].kind == 'S' && operations[i].kind == 'W' &&
            operations[i-1].event == operations[i].event && operations[i-1].value == operations[i].value) { ++pairs; }
    }
    return pairs;
}
static void firstTimestampEntry() {
    {
        Fixture f; auto b = f.begin();
        ((R77Buffer*)b->commandBuffer())->commands.push_back('G'); // Earlier stage work in the first prefix.
        f.stamp(b); auto suffix = (R77Buffer*)b->commandBuffer();
        suffix->commands.push_back('G'); // Later work is not made a timestamp predecessor.
        check(suffix->commands == std::vector<char>({'B','M','T','G'}), "barrier precedes real marker and same-buffer timestamp");
        check(f.queue->_state->counterProof == MVKMetal4CounterProof::Closed, "encoding does not change queue order proof");
        check(b->end() && f.queue->submit(b), "empty owned queue first timestamp submitted");
        check(counterPairs(f.native()->operations) == 0 && f.native()->commits.size() == 1 &&
              f.native()->operations[0].buffers.size() == 2,
              "closed entry merges both native buffers into one commit and feedback");
        check(f.queue->_state->counterProof == MVKMetal4CounterProof::Open, "actual timestamp segment reopens submitted prefix");
        check(orderedCounters(f.native()->operations, true, true, false), "marker and timestamp connect earlier stages");
        check(!orderedCounters(f.native()->operations, true, true, false, false), "negative control: missing bridge leaves prior prefix stages unordered");
        check(!orderedCounters(f.native()->operations, true, false, false), "negative control: marker alone does not order timestamp");
        [f.native() finish:0 error:nil]; check(b->completed(), "merged commit feedback covers prefix and suffix together");
        [f.native() finish:0 error:nil]; check(b->completed(), "duplicate merged feedback cannot retire twice");
        check(f.queue->_state->counterProof == MVKMetal4CounterProof::Open, "host completion callback is not a closing proof");
    }
    {
        Fixture f;
        auto a = f.begin(); f.stamp(a); check(a->end(), "write-only record ended");
        auto b = f.begin(); f.stamp(b); check(b->end(), "second record pre-encoded while queue still closed");
        check(f.queue->submit(a) && f.queue->submit(b), "actual submit order decides second entry");
        check(counterPairs(f.native()->operations) == 1, "unresolved prior native timestamp retains next entry pair");
        auto r = f.begin(); f.resolve(r); check(r->end() && f.queue->submit(r), "first-access resolve keeps full pair");
        check(counterPairs(f.native()->operations) == 2 && f.queue->_state->counterProof == MVKMetal4CounterProof::Closed,
              "retained resolve pair closes preceding opaque writes");
        auto c = f.begin(); ((R77Buffer*)c->commandBuffer())->commands.push_back('G'); f.stamp(c);
        check(c->end() && f.queue->submit(c), "same heap first timestamp after resolve submitted");
        check(counterPairs(f.native()->operations) == 2, "submitted resolve proof reused by next first timestamp");
        check(orderedCounters(f.native()->operations, true, true, false), "write-only, resolve and later marker preserve counter order");
        f.finishAll();
    }
    {
        Fixture f;
        auto a = f.begin(); f.stamp(a); check(a->end(), "early recorded timestamp ended");
        auto b = f.begin(); f.stamp(b); f.resolve(b); check(b->end(), "later recorded closing record ended");
        check(f.queue->submit(b) && f.queue->submit(a), "reverse recording order uses actual submit order");
        check(counterPairs(f.native()->operations) == 1 && orderedCounters(f.native()->operations, true, true, false),
              "closing record before pre-recorded entry needs only resolve pair");
        f.finishAll();
    }
    {
        Fixture f;
        auto a = f.begin(); f.stamp(a); f.resolve(a); check(a->end(), "first grouped record ended");
        auto ordinary = f.begin(); ((R77Buffer*)ordinary->commandBuffer())->commands.push_back('G'); check(ordinary->end(), "grouped stage record ended");
        auto b = f.begin(); f.stamp(b); check(b->end(), "last grouped entry ended");
        check(f.queue->submit({a, ordinary, b}), "counter metadata scanned across ordered children and prefixes");
        check(counterPairs(f.native()->operations) == 1 && f.native()->commits.size() == 2 &&
              orderedCounters(f.native()->operations, true, true, false), "group resolve closure survives ordinary child before next entry");
        check(f.queue->_state->counterProof == MVKMetal4CounterProof::Open, "last child actual write reopens group proof");
        f.finishAll();
    }
    {
        Fixture f; auto b = f.begin(); f.stamp(b);
        b->_state->counterPrefixes.front().timestampBridge = false;
        check(b->end() && f.queue->submit(b), "missing bridge metadata submitted conservatively");
        check(counterPairs(f.native()->operations) == 1, "closed proof without verified bridge cannot omit event");
        f.finishAll();
    }
    {
        Fixture f; auto b = f.begin(); f.resolve(b); f.stamp(b);
        check(b->end() && f.queue->submit(b), "entry resolve followed by timestamp submitted");
        check(counterPairs(f.native()->operations) == 1 && f.queue->_state->counterProof == MVKMetal4CounterProof::Open,
              "actual write after entry resolve reopens proof");
        f.finishAll();
    }
    {
        Fixture f; auto b = f.begin(); f.stamp(b);
        auto event = (id<MTLEvent>)[R77Event new]; ((R77Event*)event)->ownerDevice = (id<MTLDevice>)f.device;
        check(b->addSignalEvent(event, 1) && b->end() && f.queue->submit(b), "timestamp with outer signal and retirement tail");
        [event release]; f.finishAll();
        check(f.queue->_state->counterProof == MVKMetal4CounterProof::Open,
              "outer signal, tail and host completion are not credited as counter proof");
        auto c = f.begin(); f.stamp(c); check(c->end() && f.queue->submit(c), "timestamp after outer signal");
        check(counterPairs(f.native()->operations) == 2, "next entry keeps its own pair in addition to existing retirement pair");
        f.finishAll();
    }
    {
        Fixture f, other;
        auto b = f.begin(); f.stamp(b); check(b->end() && f.queue->submit(b), "first queue has open opaque prefix");
        auto c = other.begin(); other.stamp(c); check(c->end() && other.queue->submit(c), "separate owned queue starts empty");
        check(counterPairs(other.native()->operations) == 0 && f.queue->_state->counterProof == MVKMetal4CounterProof::Open,
              "native queue proofs are independent");
        f.finishAll(); other.finishAll();
    }
}
static void readOnlyResolveEntry() {
    {
        Fixture f;
        auto writer = f.begin(); f.stamp(writer); f.resolve(writer);
        check(writer->end() && f.queue->submit(writer), "writer and first result resolve submitted");
        const auto pairs = counterPairs(f.native()->operations);
        const auto commits = f.native()->commits.size();
        auto reader = f.begin(); unsigned done = 0;
        check(reader->addCompletedHandler([&](NSError* e) { check(!e, "read-only completion succeeds"); ++done; }),
              "read-only completion registered");
        ((R77Buffer*)reader->commandBuffer())->commands.push_back('G');
        f.resolve(reader); f.resolve(reader);
        check(((R77Buffer*)reader->commandBuffer())->commands == std::vector<char>({'M','R','R'}),
              "read-only reuse introduces no new barrier or GPU command");
        check(reader->end() && f.queue->submit(reader), "read-only results after closed writer submitted");
        check(counterPairs(f.native()->operations) == pairs && f.native()->commits.size() == commits + 1,
              "closed read-only results reuse completion and merge the existing buffers");
        check(f.queue->_state->counterProof == MVKMetal4CounterProof::Closed &&
              orderedCounters(f.native()->operations, true, true, false),
              "every result read remains after the original opaque writer completion");
        check(!orderedCounters(f.native()->operations, false, true, false),
              "negative control: removing the original write-to-resolve wait is unsafe");
        [f.native() finish:commits error:nil]; [f.native() finish:commits error:nil];
        check(done == 1 && reader->completed() && !writer->completed(),
              "merged reader retires once without pretending earlier feedback arrived");
        f.finishAll();
    }
    {
        Fixture f;
        auto reader = f.begin(); f.resolve(reader); check(reader->end(), "reader recorded before writer submission");
        auto writer = f.begin(); f.stamp(writer); check(writer->end() && f.queue->submit(writer), "unresolved writer submitted first");
        check(f.queue->submit(reader) && counterPairs(f.native()->operations) == 1 &&
              orderedCounters(f.native()->operations, true, true, false),
              "actual open submit prefix forces the read-only result wait");
        auto next = f.begin(); f.resolve(next); check(next->end() && f.queue->submit(next), "second reader submitted");
        check(counterPairs(f.native()->operations) == 1, "only the first reader must close the writer");
        f.finishAll();
    }
    {
        Fixture f; auto mixed = f.begin();
        ((R77Buffer*)mixed->commandBuffer())->commands.push_back('G');
        f.resolve(mixed); f.stamp(mixed);
        check(mixed->end() && f.queue->submit(mixed), "resolve followed by timestamp in one recording submitted");
        check(counterPairs(f.native()->operations) == 1 && orderedCounters(f.native()->operations, true, true, false),
              "mixed recording keeps the entry wait needed by its later timestamp");
        check(!orderedCounters(f.native()->operations, false, true, false),
              "negative control: later timestamp otherwise misses earlier-buffer stage work");
        f.finishAll();
    }
    {
        Fixture f; auto reader = f.begin();
        ((R77Buffer*)reader->commandBuffer())->commands.push_back('G'); f.resolve(reader); check(reader->end(), "read-only child ended");
        auto writer = f.begin(); f.stamp(writer); check(writer->end(), "later timestamp child ended");
        check(f.queue->submit({reader, writer}) && counterPairs(f.native()->operations) == 0 &&
              f.native()->commits.size() == 1 && orderedCounters(f.native()->operations, true, true, false),
              "separate timestamp child retains its own stage bridge after read-only reuse");
        check(!orderedCounters(f.native()->operations, true, true, false, false),
              "negative control: following timestamp still requires its actual bridge");
        f.finishAll();
    }
    for (bool known : {false, true}) {
        Fixture f; auto reader = f.begin(); f.resolve(reader); check(reader->end(), "reader before late wait ended");
        auto wait = f.begin(); auto event = (id<MTLEvent>)[R77Event new];
        ((R77Event*)event)->ownerDevice = (id<MTLDevice>)f.device;
        check(wait->addWaitEvent(event, 1, nullptr, known) && wait->end() && f.queue->submit({reader, wait}),
              "wait provenance on a different child included in planning");
        check(counterPairs(f.native()->operations) == (known ? 0u : 1u),
              "external wait forces resolve fallback while internal wait never strengthens proof");
        f.finishAll(); [event release];
    }
    {
        Fixture f; auto reader = f.begin(); f.resolve(reader);
        check(reader->deferUntilSubmit([&] { f.queue->_state->storage->poisoned.store(true); }) &&
              reader->end() && f.queue->submit(reader), "read-only proof poisoned after planning");
        check(counterPairs(f.native()->operations) == 1 && f.native()->operations[0].kind == 'S' &&
              orderedCounters(f.native()->operations, true, true),
              "late poison restores a full wait ahead of the merged read-only range");
        check(f.queue->_state->counterProof == MVKMetal4CounterProof::Unknown, "read-only path cannot overwrite poison");
        f.finishAll(); check(reader->completed() && !f.queue->begin(), "poisoned reader retires without reuse");
    }
}
static void ownedWaitsAndPresentation() {
    {
        Fixture f;
        auto event = (id<MTLEvent>)[R77Event new]; ((R77Event*)event)->ownerDevice = (id<MTLDevice>)f.device;
        auto drawable = (id<MTLDrawable>)[R77Drawable new];
        auto present = f.begin();
        check(present->addWaitEvent(event, 1, nullptr, true) &&
              present->addPresentation(drawable, 0, []{}) && present->end() && f.queue->submit(present),
              "owned present wait and drawable submitted");
        check(f.queue->_state->counterProof == MVKMetal4CounterProof::Closed,
              "known present/acquire cannot invent an opaque counter writer");
        auto b = f.begin(); check(b->addWaitEvent(event, 2, nullptr, true), "owned acquire registered");
        f.stamp(b); f.resolve(b); check(b->end() && f.queue->submit(b), "frame query after known presentation");
        check(counterPairs(f.native()->operations) == 1 &&
              orderedCounters(f.native()->operations, true, true, false),
              "normal frame keeps only the write-to-resolve counter pair");
        check(f.queue->_state->counterProof == MVKMetal4CounterProof::Closed, "frame resolve closes opaque writes");
        f.finishAll(); [drawable release]; [event release];
    }
    for (bool known : {false, true}) {
        Fixture f; auto b = f.begin();
        auto event = (id<MTLEvent>)[R77Event new]; ((R77Event*)event)->ownerDevice = (id<MTLDevice>)f.device;
        check(b->addWaitEvent(event, 1, nullptr, known), "wait provenance registered before recording");
        ((R77Buffer*)b->commandBuffer())->commands.push_back('G'); f.stamp(b);
        const auto commands = ((R77Buffer*)b->commandBuffer())->commands;
        check((std::find(commands.begin(), commands.end(), 'B') != commands.end()) == known,
              "known fallback omits the redundant stage bridge; eligible entry retains it");
        check(b->end() && f.queue->submit(b), "wait provenance submission");
        check(counterPairs(f.native()->operations) == (known ? 0u : 1u),
              "generic/imported event cannot inherit a local closed proof");
        check(orderedCounters(f.native()->operations, true, true, !known), "both provenance paths order opaque accesses");
        f.finishAll(); [event release];
    }
    {
        Fixture f; f.queue->_state->counterProof = MVKMetal4CounterProof::Open;
        auto event = (id<MTLEvent>)[R77Event new]; ((R77Event*)event)->ownerDevice = (id<MTLDevice>)f.device;
        auto b = f.begin(); check(b->addWaitEvent(event, 1, nullptr, true), "owned wait over open prefix");
        f.stamp(b); check(b->end() && f.queue->submit(b), "open prefix with owned wait submitted");
        check(counterPairs(f.native()->operations) == 1 && orderedCounters(f.native()->operations, true, true),
              "owned wait preserves open proof rather than falsely closing it");
        f.finishAll(); [event release];
    }
    {
        Fixture f; auto b = f.begin(); f.stamp(b);
        auto event = (id<MTLEvent>)[R77Event new]; ((R77Event*)event)->ownerDevice = (id<MTLDevice>)f.device;
        check(b->addWaitEvent(event, 1) && b->end() && f.queue->submit(b), "late external wait after bridge recording");
        check(counterPairs(f.native()->operations) == 1, "late external wait still forces conservative full pair");
        f.finishAll(); [event release];
    }
}
static void concurrentFeedback() {
    Fixture f; auto b = f.begin(); std::atomic<unsigned> done{0};
    check(b->addCompletedHandler([&](NSError*) { ++done; }), "concurrent callback registered");
    f.stamp(b); f.resolve(b); f.stamp(b); f.resolve(b);
    check(b->end() && f.queue->submit(b), "concurrent feedback fixture submitted");
    std::atomic<unsigned> ready{0}; std::vector<std::thread> workers;
    const unsigned commitCount = f.native()->commits.size();
    check(commitCount == 3, "two resolves retain their boundaries after first entry coalescing");
    for (unsigned i = 0; i < commitCount; ++i) {
        workers.emplace_back([&, i] {
            @autoreleasepool {
                ++ready; while (ready != commitCount) { std::this_thread::yield(); }
                [f.native() finish:i error:nil]; [f.native() finish:i error:nil];
            }
        });
    }
    for (auto& worker : workers) { worker.join(); }
    check(done == 1 && b->completed(), "concurrent duplicate feedback retires once");
}
static void outerOperationsAndInlineFeedback() {
    Fixture f; auto first = f.begin(); check(first->end(), "ordinary first child end");
    unsigned done = 0;
    auto middle = f.begin(); ((R77Buffer*)middle->commandBuffer())->commands.push_back('G'); check(middle->addCompletedHandler([&](NSError*) { ++done; }), "middle callback registered"); f.stamp(middle); f.resolve(middle); check(middle->end(), "counter child end");
    auto last = f.begin(); check(last->end(), "ordinary last child end");
    // Register operations while recording on another child, deliberately force
    // the existing non-notification tail path with a non-shared event.
    auto signaller = f.begin(); auto event = (id<MTLEvent>)[R77Event new];
    ((R77Event*)event)->ownerDevice = (id<MTLDevice>)f.device;
    check(signaller->addWaitEvent(event, 8) && signaller->addSignalEvent(event, 9), "outer events registered");
    [event release]; check(signaller->end(), "signal child end");
    f.native()->inlineFeedback = true;
    f.native()->duringCommit = [&] { check(!done && !middle->completed(), "inline feedback cannot retire during submit scheduling"); };
    check(f.queue->submit({first, middle, last, signaller}), "group with outer events");
    f.native()->duringCommit = {};
    check(done == 1 && middle->completed(), "inline ranges and tail complete after submit-finished gate");
    const auto& ops = f.native()->operations;
    check(ops.front().kind == 'W' && ops.front().value == 8, "external wait remains ahead of every range");
    check(ops[1].kind == 'C' && ops[1].buffers.size() == 2, "first ordinary child joins the first prefix range");
    check(ops[7].kind == 'C' && ops[7].buffers.size() == 3, "following ordinary children join final range");
    check(ops[8].kind == 'S' && ops[8].value == 9 && ops[9].kind == 'W' && ops[10].kind == 'C',
          "outer signal and retirement tail remain after all ranges");
}
static void emptyEntryAndCompletedRange() {
    {
        Fixture f; auto b = f.begin(); auto epoch = b->_state->allocatorUse.epoch;
        ((R77Buffer*)b->_state->buffer)->failEncoder = true;
        check(!b->writeTimestamp(f.heap, 0) && !b->commandBuffer() && !b->end(), "empty-entry marker failure remains closed");
        b.reset(); check(epoch->state == MVKMetal4AllocatorState::DiscardOnly && !epoch->liveUses,
                         "cancelled empty-entry failure releases writer without publishing");
    }
    for (auto proof : {MVKMetal4CounterProof::Closed, MVKMetal4CounterProof::Open, MVKMetal4CounterProof::Unknown}) {
        Fixture f; f.queue->_state->counterProof = proof;
        auto b = f.begin(); auto a = (R77Allocator*)b->_state->allocatorUse.epoch->allocator;
        check(f.queue->counterEntryNeedsFullWait() == (proof != MVKMetal4CounterProof::Closed), "early hint remains conservative");
        if (f.queue->counterEntryNeedsFullWait()) { b->requireFullCounterEntry(); }
        f.stamp(b);
        check(a->begins == 1 && a->ends == 0 && b->_state->counterPrefixes.size() == 1 &&
              !b->_state->counterPrefixes.front().buffer, "empty first prefix becomes metadata without native allocation");
        auto commands = ((R77Buffer*)b->_state->buffer)->commands;
        check(commands == (proof == MVKMetal4CounterProof::Closed ? std::vector<char>{'B','M','T'} : std::vector<char>{'M','T'}),
              "known full entry omits bridge but keeps real marker");
        check(b->end() && f.queue->submit(b), "metadata entry submitted");
        check(f.native()->commits.size() == 1 && counterPairs(f.native()->operations) == unsigned(proof != MVKMetal4CounterProof::Closed),
              "single nonempty commit with required pre-commit completion");
        for (const auto& op : f.native()->operations) if (op.kind == 'C') check(op.buffers.size() == 1, "no empty native commit");
        check(orderedCounters(f.native()->operations, true, true, proof != MVKMetal4CounterProof::Closed), "empty removal preserves opaque ordering");
        f.finishAll(); check(b->completed(), "single feedback retires empty-entry recording");
    }
    {
        Fixture f; f.queue->_state->counterProof = MVKMetal4CounterProof::Open;
        auto b = f.begin();
        check(b->resolveCounterHeap(f.heap, NSMakeRange(0, 1), MTL4BufferRangeMake(4096, 8), nullptr, true), "host-completed range resolves directly");
        check(b->_state->counterPrefixes.empty() && !b->_state->counterPrefixComplete, "range fact does not create queue closure");
        f.stamp(b); f.resolve(b);
        check(b->_state->counterPrefixes.size() == 2 && b->_state->counterPrefixes.front().buffer,
              "completed read still precedes later timestamp and mandatory fresh-write resolve");
        check(b->end() && f.queue->submit(b), "completed range followed by fresh write submitted");
        check(counterPairs(f.native()->operations) == 2, "range reuse cannot remove later entry or write-to-resolve wait");
        f.finishAll();
    }
    {
        Fixture f; auto b = f.begin(); f.stamp(b);
        auto other = (id<MTL4CounterHeap>)[NSObject new];
        check(b->resolveCounterHeap(other, NSMakeRange(3, 1), MTL4BufferRangeMake(4096, 8), nullptr, true), "unrelated completed heap read");
        [other release];
        check(b->_state->counterWritesPending && b->_state->counterBufferWrites, "unrelated completed range cannot clear pending writes");
        f.resolve(b);
        check(b->_state->counterPrefixes.size() == 2, "pending writer still receives mandatory completion");
        check(b->end() && f.queue->submit(b) && counterPairs(f.native()->operations) == 1, "only required fresh-write pair retained");
        f.finishAll();
    }
}
static void failuresAndQuarantine() {
    {
        Fixture f; auto b = f.begin(); auto original = b->commandBuffer();
        f.device->failNextBuffer = true;
        check(!b->writeTimestamp(f.heap, 0) && b->commandBuffer() == original, "allocation failure leaves prefix untouched");
        f.stamp(b); f.resolve(b); check(b->end(), "retry after pre-split allocation failure");
        f.device->failNextEvent = true;
        check(!f.queue->submit(b) && !b->_state->owner && b->_state->phase == Phase::Ended &&
              f.native()->operations.empty(), "event allocation failure rolls back adoption before queue mutation");
        check(f.queue->_state->counterProof == MVKMetal4CounterProof::Closed, "failed prepare cannot publish planned resolve closure or writes");
        check(f.queue->submit(b), "ended record retry");
        for (size_t i = 0; i < f.native()->commits.size(); ++i) { [f.native() finish:i error:nil]; }
        check(b->completed(), "retried record completed");
    }
    {
        Fixture f; auto b = f.begin(); auto epoch = b->_state->allocatorUse.epoch;
        (void)b->commandBuffer(); // Preserve the nonempty split allocation fault injection.
        f.device->failNextEncoder = true;
        check(!b->writeTimestamp(f.heap, 0) && !b->commandBuffer() && !b->end(), "partial split fails closed");
        b.reset(); check(epoch->state == MVKMetal4AllocatorState::DiscardOnly && !epoch->liveUses,
                          "failed suffix cancellation never reoffers open allocator");
    }
    const auto eventCount = liveEvents;
    {
        Fixture f; auto b = f.begin();
        unsigned done = 0; check(b->addCompletedHandler([&](NSError* e) { check(bool(e), "completion reports failure"); ++done; }), "failure callback registered");
        f.stamp(b); f.resolve(b); check(b->end() && f.queue->submit(b), "error fixture submitted");
        auto error = [NSError errorWithDomain:@"R77CPU" code:1 userInfo:nil];
        [f.native() finish:1 error:error];
        check(!done && !b->completed() && !f.queue->begin(), "error poisons new work but cannot retire outstanding segments");
        check(f.queue->_state->counterProof == MVKMetal4CounterProof::Unknown, "error invalidates submitted completion proof");
        [f.native() finish:0 error:nil];
        check(done == 1 && b->completed(), "error waits for all feedback before cleanup");
        [f.native() clearFeedback]; b.reset();
        check(liveEvents == eventCount + 1 && f.queue->_state->failedEvents.count == 1, "failed internal event quarantined through queue teardown");
    }
    check(liveEvents == eventCount, "queue teardown releases quarantined event");
    {
        Fixture f; auto b = f.begin(); f.stamp(b); f.resolve(b); check(b->end(), "inline error record ended");
        auto error = [NSError errorWithDomain:@"R77CPU" code:2 userInfo:nil];
        f.native()->duringCommit = [&] {
            if (f.native()->commits.size() == 1) { [f.native() finish:0 error:error]; }
        };
        check(f.queue->submit(b), "inline error preserves scheduling and retirement of published ranges");
        f.native()->duringCommit = {};
        check(counterPairs(f.native()->operations) == 1, "inline error retains the remaining resolve pair after the merged commit");
        check(f.queue->_state->counterProof == MVKMetal4CounterProof::Unknown,
              "planned closed state cannot overwrite inline feedback poison");
        [f.native() finish:1 error:nil];
        check(b->completed() && !f.queue->begin(), "all range feedbacks retire inline error but queue stays poisoned");
    }
    {
        Fixture f; auto b = f.begin(); f.stamp(b);
        check(b->deferUntilSubmit([&] { f.queue->_state->storage->poisoned.store(true); }),
              "shared-pool error arrives after planning but before first commit");
        check(b->end() && f.queue->submit(b), "published merged range still scheduled for retirement");
        check(counterPairs(f.native()->operations) == 1 && f.native()->operations[0].kind == 'S' &&
              orderedCounters(f.native()->operations, true, true),
              "late poison restores completion before the whole merged range");
        check(f.queue->_state->counterProof == MVKMetal4CounterProof::Unknown, "late poison cannot be overwritten");
        f.finishAll(); check(b->completed() && !f.queue->begin(), "poisoned merged storage retires without reuse");
    }
}
static bool childMutexAvailable(MVKMetal4SubmissionState* child) {
    bool available = false;
    std::thread probe([&] {
        available = child->mutex.try_lock();
        if (available) { child->mutex.unlock(); }
    });
    probe.join();
    return available;
}
static void childMutexAcquire(MVKMetal4SubmissionState* child) {
    // A blocking probe joins while the state is still alive. Wrong destruction
    // order stalls the bounded CPU process instead of probing a dead mutex.
    std::thread probe([&] { std::lock_guard<std::mutex> lock(child->mutex); });
    probe.join();
}
static unsigned singleChildLocks() {
    unsigned cases = 0;
    {
        std::vector<std::shared_ptr<MVKMetal4SubmissionState>> children;
        SubmissionChildLocks locks(children);
        check(!locks.single && !locks.singleHeld.owns_lock() &&
              locks.ordered.empty() && locks.ordered.capacity() == 0 &&
              locks.held.empty() && locks.held.capacity() == 0 && !locks.hasDuplicates(),
              "empty child locks retain no owners or vector storage");
        for (unsigned i = 0; i < 3; ++i) { locks.lock(); locks.unlock(); }
        ++cases;
    }
    {
        auto child = std::make_shared<MVKMetal4SubmissionState>();
        std::vector<std::shared_ptr<MVKMetal4SubmissionState>> children{child};
        SubmissionChildLocks locks(children);
        check(locks.single == child && child.use_count() == 3 && !locks.hasDuplicates(),
              "singleton copies exactly one strong child owner");
        check(locks.ordered.empty() && locks.ordered.capacity() == 0 &&
              locks.held.empty() && locks.held.capacity() == 0 && !locks.singleHeld.owns_lock(),
              "singleton allocates no owner or lock vector storage before claim");
        for (unsigned i = 0; i < 3; ++i) {
            locks.lock();
            check(locks.singleHeld.owns_lock() && locks.singleHeld.mutex() == &child->mutex &&
                  !childMutexAvailable(child.get()), "singleton lock excludes another thread on every claim");
            locks.unlock();
            childMutexAcquire(child.get());
            check(!locks.singleHeld.owns_lock() && locks.single == child && child.use_count() == 3,
                  "singleton rollback unlock preserves the strong owner for relocking");
        }
        ++cases;
    }
    for (bool heldAtDestruction : {false, true}) {
        unsigned destroyed = 0;
        bool unlockedBeforeCleanup = false;
        std::weak_ptr<MVKMetal4SubmissionState> weak;
        {
            auto child = std::make_shared<MVKMetal4SubmissionState>();
            auto* raw = child.get();
            weak = child;
            child->cleanup.emplace_back([&, raw] {
                childMutexAcquire(raw);
                unlockedBeforeCleanup = true;
                ++destroyed;
            });
            std::vector<std::shared_ptr<MVKMetal4SubmissionState>> children{child};
            SubmissionChildLocks locks(children);
            child.reset(); children.clear();
            check(!weak.expired() && locks.single.use_count() == 1 && destroyed == 0,
                  "singleton guard alone keeps the state alive after all input owners drop");
            locks.lock();
            if (!heldAtDestruction) { locks.unlock(); }
            check(!weak.expired() && destroyed == 0 && locks.single.use_count() == 1,
                  "unlock never releases the singleton owner before guard destruction");
        }
        check(weak.expired() && destroyed == 1 && unlockedBeforeCleanup,
              "singleton guard unlocks before its last strong owner runs state cleanup");
        ++cases;
    }
    {
        std::array<std::shared_ptr<MVKMetal4SubmissionState>, 3> states{
            std::make_shared<MVKMetal4SubmissionState>(), std::make_shared<MVKMetal4SubmissionState>(),
            std::make_shared<MVKMetal4SubmissionState>()};
        std::vector<std::shared_ptr<MVKMetal4SubmissionState>> children{states[2], states[0], states[1]};
        SubmissionChildLocks locks(children);
        check(!locks.single && !locks.singleHeld.owns_lock() && locks.ordered.size() == 3 &&
              locks.held.size() == 3 && !locks.hasDuplicates(), "multi-child path retains its existing sized vectors");
        check(children[0] == states[2] && children[1] == states[0] && children[2] == states[1] &&
              std::all_of(states.begin(), states.end(), [](const auto& child) { return child.use_count() == 3; }),
              "multi-child sorting preserves caller work order and copies each owner once");
        for (size_t i = 1; i < locks.ordered.size(); ++i) {
            check(std::less<MVKMetal4SubmissionState*>{}(locks.ordered[i - 1].get(), locks.ordered[i].get()),
                  "multi-child lock order remains strictly ascending by state address");
        }
        for (unsigned attempt = 0; attempt < 3; ++attempt) {
            locks.lock();
            for (size_t i = 0; i < locks.held.size(); ++i) {
                check(locks.held[i].owns_lock() && locks.held[i].mutex() == &locks.ordered[i]->mutex &&
                      !childMutexAvailable(locks.ordered[i].get()), "multi-child claim excludes another thread for every child");
            }
            locks.unlock();
            for (auto& child : locks.ordered) { childMutexAcquire(child.get()); }
            check(std::none_of(locks.held.begin(), locks.held.end(), [](const auto& lock) { return lock.owns_lock(); }),
                  "multi-child rollback releases every lock and permits repeated acquisition");
        }
        ++cases;
    }
    {
        unsigned destroyed = 0;
        std::array<std::weak_ptr<MVKMetal4SubmissionState>, 2> weak;
        {
            std::vector<std::shared_ptr<MVKMetal4SubmissionState>> children;
            for (size_t i = 0; i < weak.size(); ++i) {
                auto child = std::make_shared<MVKMetal4SubmissionState>();
                auto* raw = child.get(); weak[i] = child;
                child->cleanup.emplace_back([&, raw] { childMutexAcquire(raw); ++destroyed; });
                children.push_back(std::move(child));
            }
            SubmissionChildLocks locks(children);
            children.clear(); locks.lock();
            check(std::none_of(weak.begin(), weak.end(), [](const auto& child) { return child.expired(); }) && destroyed == 0,
                  "multi-child guard retains dropped input owners while locks are held");
        }
        check(std::all_of(weak.begin(), weak.end(), [](const auto& child) { return child.expired(); }) && destroyed == 2,
              "multi-child lock destruction still precedes state cleanup");
        ++cases;
    }
    {
        auto a = std::make_shared<MVKMetal4SubmissionState>(), b = std::make_shared<MVKMetal4SubmissionState>();
        for (const auto& children : std::vector<std::vector<std::shared_ptr<MVKMetal4SubmissionState>>>{
                 {a, a}, {a, b, a}, {b, a, b}, {a, a, a}}) {
            SubmissionChildLocks locks(children);
            check(locks.hasDuplicates() && !locks.single &&
                  std::none_of(locks.held.begin(), locks.held.end(), [](const auto& lock) { return lock.owns_lock(); }),
                  "sorted duplicate scan rejects repeated states before any lock claim");
            ++cases;
        }
    }
    {
        Fixture f; auto b = f.begin(); check(b->end(), "duplicate and null rejection recording ended");
        NSError* error = nil;
        check(!f.queue->submit(std::vector<std::shared_ptr<MVKMetal4Submission>>{b, b}, &error) && error &&
              !b->_state->owner && b->_state->phase == Phase::Ended && f.native()->operations.empty(),
              "actual duplicate caller rejects before queue mutation or child adoption");
        childMutexAcquire(b->_state.get());
        check(!f.queue->submit(std::shared_ptr<MVKMetal4Submission>{}, &error) && error &&
              !f.queue->submit(std::vector<std::shared_ptr<MVKMetal4Submission>>{}, &error) && error &&
              f.queue->_state->pending == 0 && f.native()->operations.empty(),
              "actual caller rejects null and empty submissions before child helper");
        ++cases;
    }
    {
        Fixture f; auto b = f.begin(); f.stamp(b); f.resolve(b); check(b->end(), "repeated rollback recording ended");
        for (unsigned attempt = 0; attempt < 3; ++attempt) {
            f.device->failNextEvent = true;
            check(!f.queue->submit(b) && !b->_state->owner && b->_state->phase == Phase::Ended &&
                  f.native()->operations.empty() && f.queue->_state->pending == 0,
                  "actual singleton adoption rolls back repeatedly after counter-event preparation failure");
            childMutexAcquire(b->_state.get());
        }
        check(f.queue->submit(b), "same singleton successfully relocks and publishes after bounded rollback cases");
        f.finishAll(); check(b->completed(), "singleton completes after publish and adoption-claim relocking");
        ++cases;
    }
    return cases;
}

static unsigned diagnosticRangeStorage(const char* mode) {
    const bool legacy = std::strcmp(mode, "legacy") == 0;
    const bool cost = std::strcmp(mode, "stats") == 0;
    const bool c1 = std::strcmp(mode, "c1") == 0;
    check(legacy || cost || c1 || std::strcmp(mode, "off") == 0, "known diagnostic fixture mode");
    check(bool(mvkBackendTimeline()) == legacy, "actual legacy timeline profile matches the fresh-process request");
    check(bool(mvkBackendCostTimeline()) == c1, "actual C1 profile remains independent of legacy timing");
    check(mvkBackendCostStatsEnabled() == cost, "actual costStats profile matches the fresh-process request");
#if MVK_ENABLE_CUSTOM_DIAGNOSTICS
    const bool expectHosts = legacy || cost;
#endif
    unsigned cases = 0;
    for (bool inlineFeedback : {false, true}) for (bool eventFirst : {false, true}) {
        Fixture f;
#if MVK_ENABLE_CUSTOM_DIAGNOSTICS
        check(bool(f.queue->_state->costStats) == cost, "queue inherits actual costStats configuration");
#endif
        auto b = f.begin();
        unsigned done = 0, cleanup = 0;
        check(b->addCompletedHandler([&](NSError* error) { check(!error, "diagnostic fixture completion succeeds"); ++done; }),
              "diagnostic fixture completion registered");
        check(b->deferRelease([&] { ++cleanup; }), "diagnostic fixture mandatory cleanup registered");
        ((R77Buffer*)b->commandBuffer())->commands.push_back('G');
        f.stamp(b); f.resolve(b);
        auto event = [R77DiagnosticEvent new]; event->ownerDevice = (id<MTLDevice>)f.device;
        check(b->addSignalEvent((id<MTLEvent>)event, 1, nullptr, true), "internal timeline signal admitted");
        check(b->end(), "diagnostic fixture recording ended");
        std::shared_ptr<MVKMetal4SubmissionGroup> submitted;
        f.native()->inlineFeedback = inlineFeedback;
        f.native()->duringCommit = [&] {
            {
                std::lock_guard<std::mutex> lock(f.queue->_state->stateMutex);
                for (auto& owner : f.queue->_state->notificationOwners) {
                    if (!owner) { continue; }
                    check(!submitted || submitted == owner, "all commits retain the same actual submission group");
                    submitted = owner;
                }
            }
            check(bool(submitted), "production notification slot exposes the actual published group");
            std::lock_guard<std::mutex> lock(submitted->mutex);
            check(submitted->workRanges.size() == 2 && submitted->rangeFeedback.size() == 2,
                  "critical range and feedback storage remains intact");
#if MVK_ENABLE_CUSTOM_DIAGNOSTICS
            if (expectHosts) {
                check(submitted->rangeCommitHosts.size() == submitted->workRanges.size(),
                      "legacy or costStats timing retains one host timestamp per range");
                check(submitted->rangeCommitHosts[f.native()->commits.size() - 1] > 0,
                      "guarded timing writer has its populated current slot");
            } else {
                check(submitted->rangeCommitHosts.empty() && submitted->rangeCommitHosts.capacity() == 0,
                      "OFF and C1-only allocate no legacy host timestamp array");
            }
#endif
            check(!submitted->submitFinished && done == 0 && cleanup == 0,
                  "inline feedback cannot retire before submit scheduling finishes");
        };
        check(f.queue->submit(b), "production diagnostic fixture submission succeeds");
        f.native()->duringCommit = {};
        check(submitted && f.native()->commits.size() == 2 && counterPairs(f.native()->operations) == 1,
              "actual range commits and mandatory counter event boundary are preserved");
        check(done == 0 && !b->completed(), "work feedback alone cannot publish unobserved signal completion");
        if (eventFirst) {
            [event deliver];
            check(done == (inlineFeedback ? 1u : 0u), "early event observation still waits for all range feedback");
        }
        [f.native() finish:1 error:nil];
        check(done == ((inlineFeedback && eventFirst) ? 1u : 0u), "later range feedback cannot skip the earlier range");
        [f.native() finish:1 error:nil];
        [f.native() finish:0 error:nil];
        check(cleanup == 1 && done == (eventFirst ? 1u : 0u),
              "all range feedback reclaims GPU storage once and preserves signal retirement");
        if (!eventFirst) { [event deliver]; }
        check(done == 1 && b->completed() && submitted->remainingRangeFeedback == 0,
              "both completion gates retire the actual submission exactly once");
        [event deliver]; [f.native() finish:0 error:nil];
        check(done == 1 && cleanup == 1 && submitted->rangeFeedback[0] && submitted->rangeFeedback[1],
              "duplicate event and range feedback cannot repeat completion or cleanup");
        {
            std::lock_guard<std::mutex> lock(f.queue->_state->stateMutex);
            check(f.queue->_state->pending == 0 && f.queue->_state->completed == 1 &&
                  std::none_of(f.queue->_state->notificationOwners.begin(), f.queue->_state->notificationOwners.end(),
                               [](const auto& owner) { return bool(owner); }),
                  "retirement clears pending bookkeeping and notification ownership");
        }
        [event release];
        ++cases;
    }
    return cases;
}

int main(int argc, char** argv) {
    @autoreleasepool {
        try {
            if (argc == 2 && std::strcmp(argv[1], "single-child-locks") == 0) {
                unsigned cases = singleChildLocks();
                check(liveEvents == 0, "single-child locks fixture retains no events");
                std::printf("{\"passed\":true,\"checks\":%u,\"singleChildLockCases\":%u,\"mode\":\"single-child-locks\",\"gpuExecuted\":false}\n",
                            checks.load(), cases);
                return 0;
            }
            if (argc == 2) {
                unsigned cases = diagnosticRangeStorage(argv[1]);
                check(liveEvents == 0, "diagnostic storage fixture retains no events");
                std::printf("{\"passed\":true,\"checks\":%u,\"diagnosticStorageCases\":%u,\"mode\":\"%s\",\"gpuExecuted\":false}\n",
                            checks.load(), cases, argv[1]);
                return 0;
            }
            check(argc == 1, "original regression or one targeted mode only");
            ordinaryAndCancellation(); boundariesAndFeedback(); firstTimestampEntry(); readOnlyResolveEntry(); ownedWaitsAndPresentation(); concurrentFeedback(); outerOperationsAndInlineFeedback(); emptyEntryAndCompletedRange(); failuresAndQuarantine();
            check(liveEvents == 0, "no retained event leak");
            std::printf("{\"passed\":true,\"checks\":%u,\"feedbackPermutations\":24,\"gpuExecuted\":false}\n", checks.load());
        } catch (const std::exception& e) {
            std::fprintf(stderr, "counter completion CPU failure: %s (check %u)\n", e.what(), checks.load()); return 1;
        }
    }
}
