// CPU shell for exact capsule/production bodies in compact-production.inc.
// Native buffer/layout objects, command pools and the GPU encoder are mocked.
#import <Foundation/Foundation.h>
#include <vulkan/vulkan_core.h>
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <new>
#include <unordered_set>
#include <vector>
static unsigned checks = 0;
#define CHECK(x) do { ++checks; if (!(x)) { std::fprintf(stderr,"FAIL %s:%d %s\n",__FILE__,__LINE__,#x); std::abort(); } } while(0)
static bool nativeM4 = true;
static bool mvkUseMetal4() { return nativeM4; }
static void mvkCopy(void* dst,const void* src,size_t size){std::memcpy(dst,src,size);}
struct MVKVulkanAPIObject {
    unsigned refs=1, retains=0, releases=0;
    void retain() { CHECK(refs); ++refs; ++retains; }
    void release() { CHECK(refs); --refs; ++releases; }
};
struct NativeBuffer { std::vector<uint8_t> bytes=std::vector<uint8_t>(128); };
struct MVKBuffer {
    NativeBuffer* native; uint64_t base=0, extent=128; unsigned resolutions=0;
    NativeBuffer* getMTLBuffer() { ++resolutions; return native; }
    uint64_t getMTLBufferOffset() { return base; }
    uint64_t getByteCount() { return extent; }
};
struct MVKCPUDescriptorOneID2Meta { NativeBuffer* a; uint64_t offset; union { uint32_t buffer; } meta; };
enum class MVKArgumentBufferMode { Off };
enum class MVKDescriptorCPULayout { OneID2Meta };
enum class MVKDescriptorUpdateSourceType { Buffer };
struct MVKDescriptorBinding {
    uint32_t binding=0; VkDescriptorType descriptorType=VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    uint32_t descriptorCount=1, cpuOffset=0;
    MVKDescriptorCPULayout cpuLayout=MVKDescriptorCPULayout::OneID2Meta;
};
struct MVKDescriptorSetLayout {
    std::vector<MVKDescriptorBinding> bindings;
    const MVKDescriptorBinding* getBinding(uint32_t number) const {
        for (const auto& b:bindings) { if(b.binding==number)return &b; } std::abort();
    }
    uint32_t cpuSize() const { uint32_t size=0; for(auto& b:bindings)size=std::max(size,b.cpuOffset+b.descriptorCount*uint32_t(sizeof(MVKCPUDescriptorOneID2Meta)));return size; }
    MVKArgumentBufferMode argBufMode() const { return MVKArgumentBufferMode::Off; }
};
struct MVKPipelineLayout : MVKVulkanAPIObject {
    MVKDescriptorSetLayout dsl; bool push=true; uint32_t set=1;
    bool hasPushDescriptor() const { return push; }
    uint32_t pushDescriptor() const { return set; }
    MVKDescriptorSetLayout* getDescriptorSetLayout(uint32_t index) { CHECK(index==set); return &dsl; }
};
struct MVKDescriptorUpdateTemplate {
    std::vector<VkDescriptorUpdateTemplateEntry> entries;
    VkPipelineBindPoint point=VK_PIPELINE_BIND_POINT_COMPUTE;
    VkDescriptorUpdateTemplateType type=VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_PUSH_DESCRIPTORS_KHR;
    size_t extent=0; bool overflow=false;
    size_t getNumberOfEntries() const { return entries.size(); }
    VkPipelineBindPoint getBindPoint() const { return point; }
    VkDescriptorUpdateTemplateType getType() const { return type; }
    const VkDescriptorUpdateTemplateEntry* getEntry(size_t i) const { return &entries[i]; }
    bool hasSingletonUniformEntries() const { for(auto& e:entries)if(e.descriptorType!=VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER||e.descriptorCount!=1)return false;return true; }
    bool uniformCaptureRangeOverflows() const { return overflow; }
    size_t getUniformCaptureReadEnd() const { size_t v=0;for(auto& e:entries)v=std::max(v,e.offset+sizeof(VkDescriptorBufferInfo));return v; }
    size_t getSize() const { return extent; }
};
struct MVKVulkanCommonEncoderState {
    std::vector<uint8_t> _pushDescData;
    struct { char* cpuBuffer=nullptr; } _pushDescriptor;
    void ensurePushDescriptorSize(uint32_t size);
};
struct MVKCommandEncoderState {
    MVKVulkanCommonEncoderState graphics,compute;
    MVKVulkanCommonEncoderState* getVkEncoderState(VkPipelineBindPoint point) {
        return point==VK_PIPELINE_BIND_POINT_GRAPHICS?&graphics:point==VK_PIPELINE_BIND_POINT_COMPUTE?&compute:nullptr;
    }
    void pushDescriptorSet(VkPipelineBindPoint,MVKPipelineLayout*,uint32_t,uint32_t,const VkWriteDescriptorSet*);
    void pushDescriptorSet(MVKDescriptorUpdateTemplate* t,MVKPipelineLayout* l,uint32_t s,const void* data);
};
static MVKDescriptorUpdateSourceType getDescriptorUpdateSourceType(VkDescriptorType type) { CHECK(type==VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);return MVKDescriptorUpdateSourceType::Buffer; }
static uint32_t getDescriptorUpdateStride(MVKDescriptorUpdateSourceType) { return sizeof(VkDescriptorBufferInfo); }
static const void* getDescriptorWriteSource(const VkWriteDescriptorSet& write,MVKDescriptorUpdateSourceType) { return write.pBufferInfo; }
// The generated implementation preserves the exact OneID2Meta conversion case;
// this loop/dispatch is the explicit CPU-layout mock boundary (UBO only).
static void convertOneElement(char*,const void*);
static void writeDescriptorSetCPUBufferDispatch(const MVKDescriptorSetLayout*,const MVKDescriptorBinding& binding,
    char* dst,const void* src,size_t stride,MVKDescriptorUpdateSourceType,uint32_t start,uint32_t count) {
    CHECK(start<=binding.descriptorCount&&count<=binding.descriptorCount-start);
    for(uint32_t i=0;i<count;++i)convertOneElement(dst+(start+i)*sizeof(MVKCPUDescriptorOneID2Meta),static_cast<const char*>(src)+i*stride);
}
static void mvkPushDescriptorSet(void*,MVKDescriptorSetLayout*,uint32_t,const VkWriteDescriptorSet*);
void MVKCommandEncoderState::pushDescriptorSet(MVKDescriptorUpdateTemplate* t,MVKPipelineLayout* l,uint32_t set,const void* data) {
    // Generic fallback shell: construct its original write ordering. This is not
    // used to claim source equivalence for image/array/non-push templates.
    std::vector<VkWriteDescriptorSet> writes;
    for(auto& e:t->entries){ VkWriteDescriptorSet w{};w.dstBinding=e.dstBinding;w.dstArrayElement=e.dstArrayElement;
        w.descriptorCount=e.descriptorCount;w.descriptorType=e.descriptorType;
        w.pBufferInfo=reinterpret_cast<const VkDescriptorBufferInfo*>(static_cast<const char*>(data)+e.offset);writes.push_back(w); }
    pushDescriptorSet(t->point,l,set,uint32_t(writes.size()),writes.data());
}
struct MVKCommand;
struct MVKCommandEncoder;
struct MVKCommandBuffer;
struct MVKCommandPool {};
template<class T> struct MVKCommandTypePool { unsigned returned=0;void returnObject(T*){++returned;}void returnObjectAsync(T*){++returned;} };
static MVKCommandTypePool<MVKCommand> commandPool;
enum class MVKMetal4RecordPolicy { Deferred,State,LeadingTimestamp,Draw,BeginRenderPass,EndRenderPass,Immediate };
struct MVKMetal4DrawPlanState {};
struct MVKCommand {
    MVKCommand* _next=nullptr;
    virtual ~MVKCommand()=default;
    virtual void encode(MVKCommandEncoder*)=0;
    virtual MVKMetal4RecordPolicy getMetal4RecordPolicy() const { return MVKMetal4RecordPolicy::Deferred; }
    virtual bool planMetal4Draws(MVKMetal4DrawPlanState&)const{return false;}
    virtual MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool*){return &commandPool;}
};
struct MVKCommandEncoder {
    MVKCommandEncoderState state;
    bool _metal4PreparedRecording=true;
    std::unordered_set<MVKVulkanAPIObject*> _metal4VulkanStateOwners;
    unsigned work=0,timestamps=0;
    bool isUsingMetal4()const{return nativeM4;}
    MVKCommandEncoderState& getState(){return state;}
    void retainMetal4VulkanState(MVKVulkanAPIObject*);
    void encodeCommands(MVKCommand* command){while(command){command->encode(this);command=command->_next;}}
    void pauseMetal4Recording(){}
    void setPreparingMetal4Timestamp(bool){}
    ~MVKCommandEncoder(){for(auto* object:_metal4VulkanStateOwners)object->release();}
};
struct MVKCmdWriteTimestamp : MVKCommand {
    MVKMetal4RecordPolicy getMetal4RecordPolicy()const override{return MVKMetal4RecordPolicy::LeadingTimestamp;}
    void encode(MVKCommandEncoder* encoder)override{++encoder->timestamps;}
};
struct MVKCommandBuffer {
    bool _canAcceptCommands=true,_metal4EarlyRecording=true,_metal4StagingPass=false,_isReusable=false;
    bool _metal4RetainPreparedReplay=false,failBegin=false;
    unsigned _commandCount=0;int result=VK_SUCCESS;
    MVKCommand* _head=nullptr;MVKCommand* _tail=nullptr;
    MVKCmdWriteTimestamp* _metal4PreparedTimestamp=nullptr;
    MVKCommandEncoder* _metal4PreparedEncoder=nullptr;
    MVKCommandEncoder* _immediateCmdEncoder=nullptr;
    std::vector<MVKCommand*> _metal4PreparedReplay;
    MVKCommandPool pool;
    MVKCommandPool* getCommandPool(){return &pool;}
    void setConfigurationResult(int r){result=r;}
    bool wasConfigurationSuccessful()const{return result==VK_SUCCESS;}
    int reportError(int error,const char*){return error;}
    void addCommand(MVKCommand*);
    void releaseCommands(MVKCommand*,bool=false);
    void releaseRecordedCommands(bool=false);
    void releaseMetal4PreparedReplay(bool=false);
    void restoreMetal4PreparedReplay();
    bool beginMetal4PreparedRecording();
    void pauseMetal4PreparedRecording(){if(_metal4PreparedEncoder)_metal4PreparedEncoder->pauseMetal4Recording();}
    void clearMetal4PreparedRecording(){delete _metal4PreparedEncoder;_metal4PreparedEncoder=nullptr;_metal4EarlyRecording=_metal4StagingPass=false;releaseMetal4PreparedReplay();}
    ~MVKCommandBuffer(){clearMetal4PreparedRecording();releaseRecordedCommands();}
};
// Defines both exact postimage and reference-before command classes/methods,
// CPU conversion, state push, encoder retain and command transfer/control bodies.
#include "compact-production.inc"

struct Inspect : MVKCmdPushDescriptorSetWithTemplate {
    uint32_t count()const{return _compactUniformWriteCount;}
    size_t bytes()const{return _dataSize;}
    size_t capacity()const{return _dataCapacity;}
    void overwrite(){if(_pData)std::memset(_pData,0,_dataSize);}
};
struct Work : MVKCommand {
    MVKMetal4RecordPolicy getMetal4RecordPolicy()const override{return MVKMetal4RecordPolicy::Immediate;}
    void encode(MVKCommandEncoder* encoder)override{++encoder->work;}
};
struct Unknown : MVKCommand { void encode(MVKCommandEncoder*)override{} };
static MVKDescriptorUpdateTemplate makeTemplate(size_t count,size_t spacing,size_t stride=0){
    MVKDescriptorUpdateTemplate t;
    for(size_t i=0;i<count;++i)t.entries.push_back({i%2?3u:1u,i%2?1u:0u,1,VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,8193+i*spacing,stride});
    t.extent=count?8193+(count-1)*spacing+sizeof(VkDescriptorBufferInfo):0;return t;
}
static std::vector<uint8_t> inputs(const MVKDescriptorUpdateTemplate& t,MVKBuffer& buffer,uint64_t offset=4,uint64_t range=8){
    std::vector<uint8_t> data(t.extent,0xcd);
    for(size_t i=0;i<t.entries.size();++i){VkDescriptorBufferInfo info{reinterpret_cast<VkBuffer>(&buffer),offset+i,range};std::memcpy(data.data()+t.entries[i].offset,&info,sizeof(info));}return data;
}
template<class Command>static VkResult set(Command& command,MVKPipelineLayout& layout,MVKDescriptorUpdateTemplate& t,const void* data){
    return command.setContent(nullptr,reinterpret_cast<VkDescriptorUpdateTemplate>(&t),reinterpret_cast<VkPipelineLayout>(&layout),layout.set,data);
}
static MVKCPUDescriptorOneID2Meta descriptor(MVKCommandEncoder& encoder,MVKPipelineLayout& layout,uint32_t binding,uint32_t element=0){
    auto* state=encoder.state.getVkEncoderState(VK_PIPELINE_BIND_POINT_COMPUTE);MVKCPUDescriptorOneID2Meta result{};
    auto start=layout.dsl.getBinding(binding)->cpuOffset+element*sizeof(result);
    CHECK(start+sizeof(result)<=state->_pushDescData.size());std::memcpy(&result,state->_pushDescData.data()+start,sizeof(result));return result;
}
static void init(MVKPipelineLayout& l){l.dsl.bindings={{1,VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,1,0},{3,VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,3,uint32_t(sizeof(MVKCPUDescriptorOneID2Meta))}};}

static void payloadAndLatest(){
    for(size_t count:{size_t(1),size_t(2),size_t(3),size_t(8)})for(size_t stride:{size_t(0),size_t(8),sizeof(VkDescriptorBufferInfo),size_t(4096)}){
        MVKPipelineLayout layout;init(layout);NativeBuffer native;MVKBuffer buffer{&native,7,96};
        auto t=makeTemplate(count,8192,stride);auto data=inputs(t,buffer);
        {
            Inspect after;ReferenceCompact before;CHECK(set(after,layout,t,data.data())==VK_SUCCESS);CHECK(set(before,layout,t,data.data())==VK_SUCCESS);
            CHECK(after.count()==count);CHECK(after.bytes()==count*(sizeof(VkDescriptorBufferInfo)+sizeof(VkWriteDescriptorSet)));
            CHECK(after.getMetal4RecordPolicy()==(MVK_BUILD_METAL4_FOUNDATION?MVKMetal4RecordPolicy::State:MVKMetal4RecordPolicy::Deferred));
            std::fill(data.begin(),data.end(),0);MVKCommandEncoder late,early;late._metal4PreparedRecording=false;
            before.encode(&late);after.encode(&early);
            CHECK(early.state.compute._pushDescData==late.state.compute._pushDescData);
            CHECK(layout.refs==(MVK_BUILD_METAL4_FOUNDATION?4u:3u));
            auto desc=descriptor(early,layout,1);CHECK(desc.a==&native&&desc.offset==buffer.base+4+(count>2?((count-1)&~size_t(1)):0));
            // No buffer contents read at capture/CPU conversion. Both descriptor
            // addresses still point into live storage after simulated Ended.
            uint32_t latest=0x54abcdef;std::memcpy(native.bytes.data()+desc.offset,&latest,4);
            uint32_t observed=0;std::memcpy(&observed,desc.a->bytes.data()+desc.offset,4);CHECK(observed==latest);
            after.overwrite();CHECK(descriptor(early,layout,1).a==desc.a);
            auto capacity=after.capacity();auto one=makeTemplate(1,8192);auto oneData=inputs(one,buffer,0,VK_WHOLE_SIZE);
            CHECK(set(after,layout,one,oneData.data())==VK_SUCCESS);CHECK(after.capacity()==capacity);
            after.encode(&early);CHECK(layout.retains==(MVK_BUILD_METAL4_FOUNDATION?4u:3u));
            auto whole=descriptor(early,layout,1);CHECK(whole.offset==buffer.base&&whole.meta.buffer==buffer.extent);
        }
        CHECK(layout.refs==1&&layout.retains==layout.releases);
    }
}
static void fallbackAndModes(){
    MVKPipelineLayout layout;init(layout);NativeBuffer native;MVKBuffer buffer{&native};
    auto good=makeTemplate(1,128);auto bytes=inputs(good,buffer);Inspect command;
    CHECK(set(command,layout,good,bytes.data())==VK_SUCCESS);CHECK(command.count()==1);
    auto empty=makeTemplate(0,128);CHECK(set(command,layout,empty,nullptr)==VK_SUCCESS);CHECK(!command.count());
    CHECK(command.getMetal4RecordPolicy()==MVKMetal4RecordPolicy::Deferred);
    for(unsigned mode=0;mode<6;++mode){auto t=good;
        if(mode==0)t.type=VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_DESCRIPTOR_SET;
        if(mode==1)t.point=VK_PIPELINE_BIND_POINT_MAX_ENUM;
        if(mode==2)t.entries[0].descriptorType=VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        if(mode==3)t.entries[0].descriptorCount=2;
        if(mode==4)t.overflow=true;
        if(mode==5)layout.push=false;
        auto result=set(command,layout,t,bytes.data());CHECK(!command.count());CHECK(command.getMetal4RecordPolicy()==MVKMetal4RecordPolicy::Deferred);
        CHECK(result==(mode==4?VK_ERROR_OUT_OF_HOST_MEMORY:VK_SUCCESS));layout.push=true;
    }
    // Foundation ON plus M3 and non-prepared encoders do not independently own
    // a layout. The command itself retains it until node reuse/destruction.
    CHECK(set(command,layout,good,bytes.data())==VK_SUCCESS);auto refs=layout.refs;
    {nativeM4=false;MVKCommandEncoder encoder;command.encode(&encoder);CHECK(layout.refs==refs);nativeM4=true;}
    {MVKCommandEncoder encoder;encoder._metal4PreparedRecording=false;command.encode(&encoder);CHECK(layout.refs==refs);}
}
#if MVK_BUILD_METAL4_FOUNDATION
static void transferAndRestore(){
    for(bool timestamp:{false,true})for(bool restore:{false,true}){
        MVKPipelineLayout layout,another;init(layout);init(another);NativeBuffer native;MVKBuffer buffer{&native};
        auto t=makeTemplate(1,128);auto data=inputs(t,buffer);
        Inspect node;CHECK(set(node,layout,t,data.data())==VK_SUCCESS);Work work;Unknown suffix;MVKCmdWriteTimestamp leading;
        {
            MVKCommandBuffer command;
            if(timestamp)command.addCommand(&leading);
            command.addCommand(&node);CHECK(!command._metal4PreparedEncoder);CHECK(command._head);
            command.addCommand(&work);CHECK(command._metal4PreparedEncoder&&command._metal4PreparedEncoder->work==1);
            CHECK(layout.refs==3); // caller + command + encoder independent owner
            command.addCommand(&suffix);CHECK(!command._metal4EarlyRecording&&command._head==&suffix);
            if(restore&&timestamp){
                command.restoreMetal4PreparedReplay();CHECK(!command._metal4PreparedEncoder);
                CHECK(command._head==&leading&&leading._next==&node&&node._next==&work&&work._next==&suffix);
                CHECK(layout.refs==2);
            }else if(timestamp){
                CHECK(!command._metal4PreparedReplay.empty());
                command.clearMetal4PreparedRecording();CHECK(layout.refs==2);
            }else{
                // Emulate immediate node-pool reuse after early encode: its old
                // layout owner disappears while the encoder still needs state.
                auto next=inputs(t,buffer);
                CHECK(set(node,another,t,next.data())==VK_SUCCESS);CHECK(layout.refs==2);
                command.clearMetal4PreparedRecording();CHECK(layout.refs==1);
            }
        }
    }
    // State alone and a later unknown/query-like Deferred never create native
    // storage. A begin failure preserves original nodes and their replay order.
    for(bool fail:{false,true}){
        MVKPipelineLayout layout;init(layout);NativeBuffer native;MVKBuffer buffer{&native};auto t=makeTemplate(1,128);auto data=inputs(t,buffer);
        Inspect node;CHECK(set(node,layout,t,data.data())==VK_SUCCESS);Work work;Unknown query;MVKCommandBuffer command;
        command.addCommand(&node);CHECK(!command._metal4PreparedEncoder&&layout.refs==2);
        if(fail){command.failBegin=true;command.addCommand(&work);CHECK(!command._metal4PreparedEncoder&&command._head==&node&&node._next==&work);}
        command.addCommand(&query);CHECK(!command._metal4EarlyRecording&&command._head==&node);
    }
}
#endif
int main(){@autoreleasepool{payloadAndLatest();fallbackAndModes();
#if MVK_BUILD_METAL4_FOUNDATION
    transferAndRestore();
#endif
    std::printf("PASS compact CPU checks=%u foundation=%d; no GPU/native queue/query execution\n",checks,MVK_BUILD_METAL4_FOUNDATION);
}return 0;}
