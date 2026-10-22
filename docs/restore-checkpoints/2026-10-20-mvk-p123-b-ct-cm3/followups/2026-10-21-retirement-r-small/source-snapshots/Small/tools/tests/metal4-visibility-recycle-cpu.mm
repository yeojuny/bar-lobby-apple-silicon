// CPU-only: verbatim buffer/helper bodies and the accumulation kernel with only
// MSL address-space/entry-point syntax removed. No Metal device is created.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <vulkan/vulkan.h>
#include <algorithm>
#include <atomic>
#include <functional>
#include <memory>
#include <stdexcept>
#include <utility>
#include <vector>
#include <cstdio>
#include <cstring>
#include "MVKMetal4QueryDependencies.h"
using namespace std;
using uint = unsigned;
static unsigned checks=0, liveBuffers=0;
static void check(bool value,const char* message) { ++checks; if(!value)throw runtime_error(message); }
static VkResult reportError(VkResult result,const char*) { return result; }
static constexpr uint32_t kMVKQuerySlotSizeInBytes=8;

@interface VisibilityCPUBuffer : NSObject
@property(nonatomic,retain) NSMutableData* bytes;
@property(nonatomic,copy) NSString* label;
@property(nonatomic,readonly) NSUInteger length;
- (id)initWithLength:(NSUInteger)length;
@end
@implementation VisibilityCPUBuffer
- (id)initWithLength:(NSUInteger)length { if((self=[super init])){++liveBuffers;_bytes=[[NSMutableData alloc]initWithLength:length];memset(_bytes.mutableBytes,0xA5,length);}return self; }
- (NSUInteger)length { return _bytes.length; }
- (void)dealloc { --liveBuffers;[_bytes release];[_label release];[super dealloc]; }
@end
@interface VisibilityCPUFence : NSObject
@property(nonatomic,copy) NSString* label;
@end
@implementation VisibilityCPUFence
- (void)dealloc { [_label release];[super dealloc]; }
@end
@interface VisibilityCPUDevice : NSObject
@property(nonatomic) BOOL failBuffer;
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options;
- (id<MTLFence>)newFence;
@end
@implementation VisibilityCPUDevice
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)n options:(MTLResourceOptions)options {
    check((options&MTLResourceStorageModePrivate)!=0,"keep private storage");
    return _failBuffer?nil:(id<MTLBuffer>)[[VisibilityCPUBuffer alloc]initWithLength:n];
}
- (id<MTLFence>)newFence { return (id<MTLFence>)[VisibilityCPUFence new]; }
@end
#include MVK_VISIBILITY_CLASS
#include MVK_VISIBILITY_BUFFER_BODY

struct Recorder { vector<function<void()>> pending;vector<id> fences;unsigned fills=0,ends=0;
    void execute(){for(auto& f:pending)f();pending.clear();} };
@interface VisibilityCPUEncoder : NSObject
@property(nonatomic) Recorder* recorder;
- (void)fillBuffer:(id<MTLBuffer>)buffer range:(NSRange)range value:(uint8_t)value;
- (void)updateFence:(id<MTLFence>)fence;
@end
@implementation VisibilityCPUEncoder
- (void)fillBuffer:(id<MTLBuffer>)buffer range:(NSRange)range value:(uint8_t)value {
    check(range.location+range.length<=buffer.length,"initialization bounds");++_recorder->fills;
    auto keep=shared_ptr<VisibilityCPUBuffer>((VisibilityCPUBuffer*)[buffer retain],[](VisibilityCPUBuffer* b){[b release];});
    _recorder->pending.emplace_back([keep,range,value]{memset((char*)keep.get().bytes.mutableBytes+range.location,value,range.length);});
}
- (void)updateFence:(id<MTLFence>)fence { check(fence!=nil,"valid initialization fence");_recorder->fences.push_back(fence); }
@end
struct Device {
    VisibilityCPUDevice* native=[VisibilityCPUDevice new];vector<MVKVisibilityBuffer> pool;unsigned allocations=0;
    MVKVisibilityBuffer getVisibilityBuffer(){if(pool.empty()){++allocations;return MVKVisibilityBuffer((id<MTLDevice>)native,64,allocations);}auto b=std::move(pool.back());pool.pop_back();return b;}
    ~Device(){[native release];}
};
struct Context { MVKVisibilityBuffer visibilityResultBuffer; };
struct CommandBuffer { VkResult result=VK_SUCCESS;void setConfigurationResult(VkResult r){result=r;} };
struct Submission { bool reject=false;unsigned retained=0;bool addResource(id b){if(reject)return false;check(b!=nil,"retain real buffer");++retained;return true;} };
enum MVKCommandUse { kMVKCommandUseResetQueryPool };
class MVKCommandEncoder {
public:
    Device* _device;Context context;Context* _pEncodingContext=&context;CommandBuffer cb;CommandBuffer* _cmdBuffer=&cb;
    Submission submission;Submission* _metal4Submission=&submission;
    bool metal4=false,failEncoder=false,_visibilityResultBufferFailed=false;unsigned failures=0;
    Recorder recorder;VisibilityCPUEncoder* native=[VisibilityCPUEncoder new];
    MVKMetal4QueryOperation operation=MVKMetal4QueryOperation::None;
    MVKCommandEncoder(Device* d,bool m):_device(d),metal4(m){native.recorder=&recorder;}
    ~MVKCommandEncoder(){recorder.pending.clear();[native release];}
    bool isUsingMetal4(){return metal4;}
    void failMetal4Encoding(const char*){++failures;}
    id<MTLBlitCommandEncoder> getMTLBlitEncoder(MVKCommandUse){return failEncoder?nil:(id<MTLBlitCommandEncoder>)native;}
    id<MTL4ComputeCommandEncoder> getMetal4ComputeEncoder(MVKCommandUse,bool,bool,MTLStages,MVKMetal4QueryOperation op){operation=op;return failEncoder?nil:(id<MTL4ComputeCommandEncoder>)native;}
    void endCurrentMetalEncoding(){++recorder.ends;}
    template<class Descriptor> bool prepareVisibilityResultBuffer(Descriptor* descriptor);
};
#include MVK_VISIBILITY_PREPARE_BODY
#include MVK_VISIBILITY_KERNEL_BODY

template<class Descriptor> static void initialization(bool metal4) {
    Device device;
    {
        MVKCommandEncoder a(&device,metal4);auto* desc=[[[Descriptor alloc] init] autorelease];
        check(a.prepareVisibilityResultBuffer(desc),"admit initial visibility storage");
        auto& b=a.context.visibilityResultBuffer;
        check(desc.visibilityResultBuffer==b.buffer(),"descriptor uses owned buffer");
#if MVK_XCODE_26
        check(desc.visibilityResultType==MTLVisibilityResultTypeAccumulate,"explicit accumulate mode");
        check(!b.needsInitialClear()&&a.recorder.fills==1&&a.recorder.ends==1,"one initial clear recorded");
        check(((const uint8_t*)((VisibilityCPUBuffer*)b.buffer()).bytes.bytes)[0]==0xA5,"recording is not GPU completion");
        if(metal4){check(a.operation==MVKMetal4QueryOperation::VisibilityInitialize&&a.submission.retained==1,"native M4 initialization scope and ownership");}
        else {check(a.recorder.fences.size()==2&&a.recorder.fences[0]==b.currentFence().prevRead,"initial low fence");
              auto high=b.initialClearFence(1);check(a.recorder.fences[1]==high&&high!=b.initialClearFence(0),"initial high fence");}
        a.recorder.execute();
        for(unsigned i=0;i<64;++i)check(((const uint8_t*)((VisibilityCPUBuffer*)b.buffer()).bytes.bytes)[i]==0,"first contents zero");
#else
        check(a.recorder.fills==0&&desc.visibilityResultType==MTLVisibilityResultTypeReset,"old SDK keeps native reset path");
#endif
        b.advanceOffset();b.advanceOffset();
        check(a.prepareVisibilityResultBuffer(desc)&&a.context.visibilityResultBuffer.offset()==16,"partial start offset retained");
        unsigned fills=a.recorder.fills;
        device.pool.emplace_back(std::move(b));
        check(!b.buffer()&&!b.needsInitialClear(),"moved-from lease cannot initialize another buffer");
        MVKCommandEncoder next(&device,metal4);
        check(next.prepareVisibilityResultBuffer(desc)&&next.context.visibilityResultBuffer.offset()==16,"pool move keeps offset");
        check(next.recorder.fills==0&&a.recorder.fills==fills&&device.allocations==1,"no pool-checkout full clear");
        desc.visibilityResultBuffer=nil;
    }
    check(liveBuffers==0,"completed lease release");
    { // A local unsubmitted recording is dropped, including its initialization state.
        MVKCommandEncoder cancelled(&device,metal4);auto* d=[[[Descriptor alloc] init] autorelease];
        check(cancelled.prepareVisibilityResultBuffer(d),"cancelled record can be encoded");d.visibilityResultBuffer=nil;
    }
    check(liveBuffers==0,"cancel releases buffer rather than publishing initialized state");
    {
        MVKCommandEncoder fresh(&device,metal4);auto* d=[[[Descriptor alloc] init] autorelease];
        check(fresh.prepareVisibilityResultBuffer(d),"record after cancellation");
        check(fresh.recorder.fills==(MVK_XCODE_26?1u:0u),"new lease gets own initialization");d.visibilityResultBuffer=nil;
    }
}

template<class Descriptor> static void failures(bool metal4) {
    for(unsigned kind=0;kind<(MVK_XCODE_26?(metal4?3u:2u):1u);++kind){
        Device device;device.native.failBuffer=kind==0;
        MVKCommandEncoder c(&device,metal4);c.failEncoder=kind==1;c.submission.reject=kind==2;
        auto* d=[[[Descriptor alloc] init] autorelease];
        check(!c.prepareVisibilityResultBuffer(d)&&c._visibilityResultBufferFailed&&c.cb.result==VK_ERROR_OUT_OF_DEVICE_MEMORY,"failed initialization is observable");
        check(c.recorder.fills==0,"failure cannot publish or clear");
        if(kind)check(c.context.visibilityResultBuffer.needsInitialClear(),"failed preparation keeps initialization pending");
        d.visibilityResultBuffer=nil;
    }
}

static void fenceRotation() {
    auto* device=[VisibilityCPUDevice new];
    { MVKVisibilityBuffer b((id<MTLDevice>)device,64,0);
      auto initialLow=b.currentFence();
      for(unsigned cycle=0;cycle<4;++cycle){
        auto low=b.currentFence();id<MTLFence> highRead=nil;
        for(unsigned slot=0;slot<8;++slot){
          check(b.offset()==slot*8,"ring offset");auto f=b.currentFence();
          check((f.read==low.read)==(slot<4),"half selection includes first high slot");
          check(b.isFirstWithCurrentFence()==(slot==0||slot==4),"half boundary metadata");
          if(slot==4)highRead=f.read;
          if(slot>=4)check(f.read==highRead,"same high-half fence");
          b.advanceOffset();
        }
        check(b.currentFence().prevRead==low.read,"wrap waits for previous low consumer");
        for(unsigned i=0;i<4;++i)b.advanceOffset();
        check(b.currentFence().prevRead==highRead,"wrap waits for previous high consumer");
        // Finish this second generation before the next iteration.
        for(unsigned i=0;i<4;++i)b.advanceOffset();
      }
      check(initialLow.read!=nil,"initial fences live"); }
    [device release];
}

static void accumulation() {
    vector<VisibilityBuffer> native(32768);AtomicVisibilityBuffer totals[3]{};uint64_t expected[3]={0,0,0};
    for(uint32_t i=0;i<65540;++i){uint32_t slot=i%native.size(),dst=i%3;
        check(native[slot].count==0&&native[slot].countHigh==0,"slot zero before reuse");
        uint64_t value=(i%11==0)?UINT64_C(0x1fffffffef):uint64_t(i%7+512);
        native[slot]={uint32_t(value),uint32_t(value>>32)};QueryResultOffsets where={dst,slot};
        accumulateOcclusionQueryResults(0,&where,totals,native.data());expected[dst]+=value;
        check((uint64_t(totals[dst].countHigh.load())<<32|totals[dst].count.load())==expected[dst],"64-bit accumulation and carry");
        check(native[slot].count==0&&native[slot].countHigh==0,"consumed slot cleared");
    }
}
int main(){@autoreleasepool{try{
    fenceRotation();accumulation();
    for(bool m:{false,true}){
#if !MVK_BUILD_METAL4_FOUNDATION
        if(m)continue;
#endif
        @autoreleasepool{
#if MVK_BUILD_METAL4_FOUNDATION
            if(m){initialization<MTL4RenderPassDescriptor>(true);failures<MTL4RenderPassDescriptor>(true);}
            else
#endif
            {initialization<MTLRenderPassDescriptor>(false);failures<MTLRenderPassDescriptor>(false);}
        }
    }
    check(liveBuffers==0,"no CPU mock buffer leaked");
    printf("PASS: %u CPU assertions; actual visibility bodies; no GPU execution\n",checks);return 0;
}catch(const exception& e){fprintf(stderr,"FAIL: %s\n",e.what());return 1;}}}
