// Verbatim native-descriptor and software-resolve production methods; all native
// resources/encoders below are CPU mocks. No device or GPU queue is created.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <vulkan/vulkan.h>
#include <array>
#include <vector>
#include <stdexcept>
#include <cstdio>
using namespace std;
static unsigned checks=0;
static void check(bool b,const char* text){++checks;if(!b)throw runtime_error(text);}
template<class A,class B>static bool mvkIsAnyFlagEnabled(A a,B b){return(a&b)!=0;}
template<class A,class B>static bool mvkAreAllFlagsEnabled(A a,B b){return(a&b)==b;}
template<class T>struct MVKArrayRef{T* values;size_t count;T& operator[](size_t i)const{return values[i];}};
enum{ kMVKMTLFmtCapsResolve=1,kMVKCommandUseResolveSubpassAttachment=1 };
using MVKFormatType=unsigned;
static NSUInteger mvkSampleCountFromVkSampleCountFlagBits(VkSampleCountFlagBits v){return v;}
static MTLSize mvkMTLSizeFromVkExtent3D(VkExtent3D v){return MTLSizeMake(v.width,v.height,v.depth);}
static MTLMultisampleDepthResolveFilter mvkMTLMultisampleDepthResolveFilterFromVkResolveModeFlagBits(VkResolveModeFlagBits){return MTLMultisampleDepthResolveFilterMin;}
static MTLMultisampleStencilResolveFilter mvkMTLMultisampleStencilResolveFilterFromVkResolveModeFlagBits(VkResolveModeFlagBits){return MTLMultisampleStencilResolveFilterSample0;}
@interface ResolveCPUTexture:NSObject
@property(nonatomic)MTLTextureType textureType;
@end
@implementation ResolveCPUTexture
@end
@interface ResolveCPUPipeline:NSObject
@property(nonatomic,readonly)NSUInteger threadExecutionWidth;
@end
@implementation ResolveCPUPipeline
- (NSUInteger)threadExecutionWidth{return 8;}
@end
@interface ResolveCPUEncoder:NSObject
@property(nonatomic)unsigned calls;
- (void)dispatchThreads:(MTLSize)grid threadsPerThreadgroup:(MTLSize)size;
- (void)dispatchThreadgroups:(MTLSize)grid threadsPerThreadgroup:(MTLSize)size;
@end
@implementation ResolveCPUEncoder
- (void)dispatchThreads:(MTLSize)grid threadsPerThreadgroup:(MTLSize)size{++_calls;}
- (void)dispatchThreadgroups:(MTLSize)grid threadsPerThreadgroup:(MTLSize)size{++_calls;}
@end
struct Image{unsigned getLayerCount(){return 8;}};
struct MVKImageView{
    Image image;ResolveCPUTexture* texture=[ResolveCPUTexture new];
    MVKImageView(){texture.textureType=MTLTextureType2DMultisampleArray;}
    ~MVKImageView(){[texture release];}
    Image* getImage(){return &image;}
    MTLPixelFormat getMTLPixelFormat(){return MTLPixelFormatRGBA8Unorm;}
    VkExtent3D getExtent3D(){return{16,16,1};}
    void populateMTLRenderPassAttachmentDescriptorResolve(MTLRenderPassAttachmentDescriptor* d,id<MTLTexture> t){d.resolveTexture=t;d.resolveSlice=2;d.resolveLevel=0;}
};
struct MVKPixelFormats{
    bool nativeResolve=true;
    unsigned getCapabilities(MTLPixelFormat){return nativeResolve?kMVKMTLFmtCapsResolve:0;}
    MTLClearColor getMTLClearColor(const VkClearColorValue& c,VkFormat){return MTLClearColorMake(c.float32[0],c.float32[1],c.float32[2],c.float32[3]);}
    double getMTLClearDepthValue(VkClearDepthStencilValue c){return c.depth;}
    uint32_t getMTLClearStencilValue(VkClearDepthStencilValue c){return c.stencil;}
    MVKFormatType getFormatType(MTLPixelFormat){return 0;}
};
struct Features{bool nonUniformThreadgroups=true;};
class MVKCommandEncoder;
class MVKRenderSubpass;
struct MVKAttachmentDescription{
    vector<bool> logicalResolve;
    VkFormat getFormat(){return VK_FORMAT_R8G8B8A8_UNORM;}
    bool populateMTLRenderPassAttachmentDescriptor(MVKCommandEncoder*,MTLRenderPassAttachmentDescriptor* d,MVKRenderSubpass*,MVKImageView* v,bool,bool hasResolve,bool,bool,bool){
        logicalResolve.push_back(hasResolve);d.texture=(id<MTLTexture>)v->texture;d.slice=2;d.storeAction=MTLStoreActionUnknown;return true;
    }
};
struct RenderPass{VkRenderingFlags flags=0;array<MVKAttachmentDescription,6> _attachments;MVKPixelFormats formats;
    VkRenderingFlags getRenderingFlags(){return flags;}MVKPixelFormats* getPixelFormats(){return &formats;}};
struct MVKFramebuffer{};
struct MVKMetalComputeCommandEncoderState{
    vector<id<MTLTexture>> textures;
    void bindPipeline(id<MTLComputeCommandEncoder>,id<MTLComputePipelineState>){}
    void bindTexture(id<MTLComputeCommandEncoder>,id<MTLTexture> t,unsigned){textures.push_back(t);}
};
struct Pool{
    ResolveCPUPipeline* pipeline=[ResolveCPUPipeline new];~Pool(){[pipeline release];}
    id<MTLComputePipelineState> getCmdResolveColorImageMTLComputePipelineState(MVKFormatType,bool){return(id<MTLComputePipelineState>)pipeline;}
};
class MVKCommandEncoder{
public:
    RenderPass* pass;Features features;Pool pool;MVKMetalComputeCommandEncoderState state;
    ResolveCPUEncoder* encoder=[ResolveCPUEncoder new];
    MVKCommandEncoder(RenderPass* p):pass(p){}~MVKCommandEncoder(){[encoder release];}
    MVKPixelFormats* getPixelFormats(){return &pass->formats;}
    Features& getMetalFeatures(){return features;}
    Pool* getCommandEncodingPool(){return &pool;}
    id<MTLComputeCommandEncoder> getMTLComputeEncoder(unsigned){return(id<MTLComputeCommandEncoder>)encoder;}
    MVKMetalComputeCommandEncoderState& getMtlCompute(){return state;}
    id<MTLTexture> getRenderPassAttachmentTexture(MVKImageView* v){return(id<MTLTexture>)v->texture;}
};
class MVKRenderSubpass{
public:
    RenderPass* _renderPass;bool multiview=false;
    vector<VkAttachmentReference> _colorAttachments={{0,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL}},_resolveAttachments={{1,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL}};
    VkAttachmentReference _depthAttachment={2,VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL},_stencilAttachment={4,VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL};
    VkAttachmentReference _depthResolveAttachment={3,VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL},_stencilResolveAttachment={5,VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL};
    VkResolveModeFlagBits _depthResolveMode=VK_RESOLVE_MODE_MIN_BIT,_stencilResolveMode=VK_RESOLVE_MODE_SAMPLE_ZERO_BIT;
    VkSampleCountFlagBits _defaultSampleCount=VK_SAMPLE_COUNT_4_BIT;
    MVKRenderSubpass(RenderPass* p):_renderPass(p){}
    uint32_t getColorAttachmentCount(){return _colorAttachments.size();}
    bool isMultiview(){return multiview;}
    uint32_t getFirstViewIndexInMetalPass(uint32_t){return 3;}
    void populateMTLRenderPassDescriptor(MVKCommandEncoder*,MTLRenderPassDescriptor*,uint32_t,MVKFramebuffer*,MVKArrayRef<MVKImageView*const>,MVKArrayRef<const VkClearValue>,bool,bool);
    void resolveUnresolvableAttachments(MVKCommandEncoder*,MVKArrayRef<MVKImageView*const>);
};
#include MVK_SUSPEND_RESOLVE_BODY

static void descriptors(){
    for(auto flags:{VkRenderingFlags(0),VkRenderingFlags(VK_RENDERING_SUSPENDING_BIT),VkRenderingFlags(VK_RENDERING_RESUMING_BIT),VkRenderingFlags(VK_RENDERING_SUSPENDING_BIT|VK_RENDERING_RESUMING_BIT)})
    for(bool multiview:{false,true})for(bool native:{false,true}){@autoreleasepool{
        RenderPass rp;rp.flags=flags;rp.formats.nativeResolve=native;MVKCommandEncoder encoder(&rp);MVKRenderSubpass subpass(&rp);subpass.multiview=multiview;
        MVKFramebuffer framebuffer;MVKImageView v[6];MVKImageView* views[6];VkClearValue clears[6]{};
        for(unsigned i=0;i<6;++i)views[i]=&v[i];
        auto* d=[MTLRenderPassDescriptor renderPassDescriptor];
        subpass.populateMTLRenderPassDescriptor(&encoder,d,0,&framebuffer,{views,6},{clears,6},true,false);
        bool suspended=(flags&VK_RENDERING_SUSPENDING_BIT)!=0;
        check(bool(d.colorAttachments[0].resolveTexture)==(!suspended&&native),"native color resolve belongs only to final/ordinary pass");
        check(bool(d.depthAttachment.resolveTexture)==!suspended,"native depth resolve deferred");
        check(bool(d.stencilAttachment.resolveTexture)==!suspended,"native stencil resolve deferred");
        for(unsigned i:{0u,2u,4u})check(rp._attachments[i].logicalResolve.size()==1&&rp._attachments[i].logicalResolve[0],"logical resolve metadata retained");
        check(subpass._resolveAttachments[0].attachment==1&&subpass._depthResolveAttachment.attachment==3&&subpass._stencilResolveAttachment.attachment==5,"suspend cannot mutate future resolve metadata");
        check(d.colorAttachments[0].texture==(id<MTLTexture>)v[0].texture&&d.depthAttachment.texture==(id<MTLTexture>)v[2].texture&&d.stencilAttachment.texture==(id<MTLTexture>)v[4].texture,"original attachment selection unchanged");
        if(!suspended){
            check(d.depthAttachment.resolveSlice==NSUInteger(multiview?5:2)&&d.stencilAttachment.resolveSlice==NSUInteger(multiview?5:2),"resolve layers preserved");
            check(d.depthAttachment.depthResolveFilter==MTLMultisampleDepthResolveFilterMin&&d.stencilAttachment.stencilResolveFilter==MTLMultisampleStencilResolveFilterSample0,"resolve filters preserved");
            if(native)check(d.colorAttachments[0].resolveTexture==(id<MTLTexture>)v[1].texture&&d.colorAttachments[0].resolveSlice==NSUInteger(multiview?5:2),"color resolve target and layer retained");
        }
        subpass.resolveUnresolvableAttachments(&encoder,{views,6});
        check(encoder.encoder.calls==unsigned(!suspended&&!native),"software resolve follows same suspension contract");
        if(!suspended&&!native)check(encoder.state.textures.size()==2&&encoder.state.textures[0]==(id<MTLTexture>)v[1].texture&&encoder.state.textures[1]==(id<MTLTexture>)v[0].texture,"helper uses final source and destination");
        subpass._depthResolveMode=subpass._stencilResolveMode=VK_RESOLVE_MODE_NONE;subpass._resolveAttachments[0].attachment=VK_ATTACHMENT_UNUSED;
        auto* none=[MTLRenderPassDescriptor renderPassDescriptor];
        subpass.populateMTLRenderPassDescriptor(&encoder,none,0,&framebuffer,{views,6},{clears,6},true,false);
        check(!none.colorAttachments[0].resolveTexture&&!none.depthAttachment.resolveTexture&&!none.stencilAttachment.resolveTexture,"no-resolve path unchanged");
    }}
}
int main(){@autoreleasepool{try{descriptors();printf("PASS: %u CPU assertions; actual descriptor and software-resolve bodies; no GPU execution\n",checks);return 0;}
catch(const exception& e){fprintf(stderr,"FAIL: %s\n",e.what());return 1;}}}
