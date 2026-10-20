// Native primitive prepass regressions. Reuses the production-linked Vulkan
// fixture; integer flat shaders/oracles derive from metal4-primitive-conversion.mm.
#define VK_ENABLE_BETA_EXTENSIONS
#define main metal4IntegrationSuiteEntry
#include "metal4-vulkan-integration.mm"
#undef main

namespace {
std::vector<uint32_t> prepassVertexShader(bool writer, bool reads=false, bool readWritten=false) {
    // Flat interface BLOCK/member tests reflection as well as real flat data.
    // payload = {packedColor, VertexIndex,
    //            InstanceIndex*65536 + BaseInstance*4096 + DrawIndex*256 + BaseVertex, 255}.
    Spirv s;
    s.op(spv::OpCapability, {spv::CapabilityShader});
    s.op(spv::OpCapability, {spv::CapabilityDrawParameters});
    s.op(spv::OpMemoryModel, {spv::AddressingModelLogical, spv::MemoryModelGLSL450});
    s.entry(spv::ExecutionModelVertex, 70, {30,31,32,33,34,35,36,37,38});
    s.op(spv::OpDecorate, {30, spv::DecorationLocation, 0}); s.op(spv::OpDecorate, {31, spv::DecorationLocation, 1});
    s.op(spv::OpDecorate, {11, spv::DecorationBlock});
    s.op(spv::OpMemberDecorate, {11, 0, spv::DecorationBuiltIn, spv::BuiltInPosition});
    s.op(spv::OpDecorate, {14, spv::DecorationBlock});
    s.op(spv::OpMemberDecorate, {14, 0, spv::DecorationLocation, 0}); s.op(spv::OpMemberDecorate, {14, 0, spv::DecorationFlat});
    const uint32_t builtins[] = {spv::BuiltInVertexIndex,spv::BuiltInInstanceIndex,spv::BuiltInDrawIndex,spv::BuiltInBaseVertex,spv::BuiltInBaseInstance};
    for (uint32_t i=0;i<5;++i) s.op(spv::OpDecorate, {34+i, spv::DecorationBuiltIn, builtins[i]});
    if (writer || reads || readWritten) {
        s.op(spv::OpDecorate,{100,spv::DecorationArrayStride,4}); s.op(spv::OpDecorate,{101,spv::DecorationBlock});
        s.op(spv::OpMemberDecorate,{101,0,spv::DecorationOffset,0});
        s.op(spv::OpDecorate,{104,spv::DecorationDescriptorSet,0}); s.op(spv::OpDecorate,{104,spv::DecorationBinding,reads?1u:0u});
        if (reads) {
            s.op(spv::OpDecorate,{104,spv::DecorationNonWritable});
            s.op(spv::OpDecorate,{110,spv::DecorationBlock});s.op(spv::OpMemberDecorate,{110,0,spv::DecorationOffset,0});
            s.op(spv::OpDecorate,{113,spv::DecorationDescriptorSet,0});s.op(spv::OpDecorate,{113,spv::DecorationBinding,0});
        }
    }
    s.op(spv::OpTypeVoid,{1}); s.op(spv::OpTypeFunction,{2,1}); s.op(spv::OpTypeFloat,{3,32});
    s.op(spv::OpTypeVector,{4,3,2}); s.op(spv::OpTypeVector,{5,3,4});
    s.op(spv::OpTypeInt,{6,32,0}); s.op(spv::OpTypeVector,{7,6,4}); s.op(spv::OpTypeInt,{8,32,1});
    s.op(spv::OpTypePointer,{9,spv::StorageClassInput,4}); s.op(spv::OpTypePointer,{10,spv::StorageClassInput,6});
    s.op(spv::OpTypeStruct,{11,5}); s.op(spv::OpTypePointer,{12,spv::StorageClassOutput,11}); s.op(spv::OpTypePointer,{13,spv::StorageClassOutput,5});
    s.op(spv::OpTypeStruct,{14,7}); s.op(spv::OpTypePointer,{15,spv::StorageClassOutput,14}); s.op(spv::OpTypePointer,{16,spv::StorageClassOutput,7});
    s.op(spv::OpTypePointer,{17,spv::StorageClassInput,8});
    s.op(spv::OpConstant,{6,18,0}); s.op(spv::OpConstant,{3,19,0}); s.op(spv::OpConstant,{3,21,0x3F800000});
    s.op(spv::OpConstant,{6,23,65536}); s.op(spv::OpConstant,{6,24,255}); s.op(spv::OpConstant,{6,25,4096}); s.op(spv::OpConstant,{6,26,256});
    s.op(spv::OpVariable,{9,30,spv::StorageClassInput}); s.op(spv::OpVariable,{10,31,spv::StorageClassInput});
    s.op(spv::OpVariable,{12,32,spv::StorageClassOutput}); s.op(spv::OpVariable,{15,33,spv::StorageClassOutput});
    for (uint32_t i=0;i<5;++i) s.op(spv::OpVariable,{17,34+i,spv::StorageClassInput});
    if (writer || reads || readWritten) {
        s.op(spv::OpTypeRuntimeArray,{100,6}); s.op(spv::OpTypeStruct,{101,100});
        s.op(spv::OpTypePointer,{102,spv::StorageClassStorageBuffer,101}); s.op(spv::OpTypePointer,{103,spv::StorageClassStorageBuffer,6});
        s.op(spv::OpVariable,{102,104,spv::StorageClassStorageBuffer}); s.op(spv::OpConstant,{6,105,0xA1100000});
        if (reads) {
            s.op(spv::OpTypeStruct,{110,6});s.op(spv::OpTypePointer,{111,spv::StorageClassUniform,110});
            s.op(spv::OpTypePointer,{112,spv::StorageClassUniform,6});s.op(spv::OpVariable,{111,113,spv::StorageClassUniform});
        }
    }
    if (readWritten) s.op(spv::OpConstant,{6,120,1});
    s.op(spv::OpFunction,{1,70,spv::FunctionControlMaskNone,2}); s.op(spv::OpLabel,{71});
    s.op(spv::OpLoad,{4,72,30}); s.op(spv::OpCompositeExtract,{3,73,72,0}); s.op(spv::OpCompositeExtract,{3,74,72,1});
    s.op(spv::OpCompositeConstruct,{5,75,73,74,19,21}); s.op(spv::OpAccessChain,{13,76,32,18}); s.op(spv::OpStore,{76,75});
    s.op(spv::OpLoad,{6,77,31});
    for (uint32_t i=0;i<5;++i) { s.op(spv::OpLoad,{8,78+i*2,34+i}); s.op(spv::OpBitcast,{6,79+i*2,78+i*2}); }
    if (writer) {
        s.op(spv::OpAccessChain,{103,106,104,18,79}); s.op(spv::OpIAdd,{6,107,105,79}); s.op(spv::OpStore,{106,107});
    }
    if (reads) {
        s.op(spv::OpAccessChain,{112,114,113,18});s.op(spv::OpLoad,{6,115,114});
        s.op(spv::OpAccessChain,{103,116,104,18,79});s.op(spv::OpLoad,{6,117,116});
        s.op(spv::OpIAdd,{6,118,77,115});s.op(spv::OpIAdd,{6,119,118,117});
    }
    if (readWritten) {
        s.op(spv::OpAccessChain,{103,121,104,18,120});s.op(spv::OpLoad,{6,122,121});
        s.op(spv::OpIAdd,{6,123,77,122});
    }
    s.op(spv::OpIMul,{6,90,81,23}); s.op(spv::OpIMul,{6,91,87,25}); s.op(spv::OpIMul,{6,92,83,26});
    s.op(spv::OpIAdd,{6,93,90,91}); s.op(spv::OpIAdd,{6,94,93,92}); s.op(spv::OpIAdd,{6,95,94,85});
    s.op(spv::OpCompositeConstruct,{7,96,readWritten?123u:(reads?119u:77u),79,95,24}); s.op(spv::OpAccessChain,{16,97,33,18}); s.op(spv::OpStore,{97,96});
    s.op(spv::OpReturn,{}); s.op(spv::OpFunctionEnd,{}); return s.words;
}

std::vector<uint32_t> prepassFragmentShader() {
    Spirv s; s.header(); s.entry(spv::ExecutionModelFragment,30,{20,21,22});
    s.op(spv::OpExecutionMode,{30,spv::ExecutionModeOriginUpperLeft});
    s.op(spv::OpDecorate,{5,spv::DecorationBlock}); s.op(spv::OpMemberDecorate,{5,0,spv::DecorationLocation,0});
    s.op(spv::OpMemberDecorate,{5,0,spv::DecorationFlat}); s.op(spv::OpDecorate,{21,spv::DecorationLocation,0});
    s.op(spv::OpDecorate,{22,spv::DecorationBuiltIn,spv::BuiltInFrontFacing});
    s.op(spv::OpTypeVoid,{1}); s.op(spv::OpTypeFunction,{2,1}); s.op(spv::OpTypeInt,{3,32,0}); s.op(spv::OpTypeVector,{4,3,4});
    s.op(spv::OpTypeStruct,{5,4}); s.op(spv::OpTypePointer,{6,spv::StorageClassInput,5}); s.op(spv::OpTypePointer,{7,spv::StorageClassInput,4});
    s.op(spv::OpTypePointer,{8,spv::StorageClassOutput,4}); s.op(spv::OpConstant,{3,9,0});
    s.op(spv::OpTypeBool,{10}); s.op(spv::OpTypePointer,{11,spv::StorageClassInput,10});
    s.op(spv::OpConstant,{3,12,255}); s.op(spv::OpConstant,{3,13,127});
    s.op(spv::OpVariable,{6,20,spv::StorageClassInput}); s.op(spv::OpVariable,{8,21,spv::StorageClassOutput}); s.op(spv::OpVariable,{11,22,spv::StorageClassInput});
    s.op(spv::OpFunction,{1,30,spv::FunctionControlMaskNone,2}); s.op(spv::OpLabel,{31});
    s.op(spv::OpAccessChain,{7,32,20,9}); s.op(spv::OpLoad,{4,33,32}); s.op(spv::OpLoad,{10,34,22});
    s.op(spv::OpSelect,{3,35,34,12,13});
    s.op(spv::OpCompositeExtract,{3,36,33,0}); s.op(spv::OpCompositeExtract,{3,37,33,1}); s.op(spv::OpCompositeExtract,{3,38,33,2});
    s.op(spv::OpCompositeConstruct,{4,39,36,37,38,35}); s.op(spv::OpStore,{21,39});
    s.op(spv::OpReturn,{}); s.op(spv::OpFunctionEnd,{}); return s.words;
}

// Resolve-friendly output for the 4x sample-location case. Flat identity is
// retained in exact byte multiples; edge coverage is compared with static PSOs.
std::vector<uint32_t> prepassSampleFragmentShader() {
    Spirv s;s.header();s.entry(spv::ExecutionModelFragment,50,{20,21});s.op(spv::OpExecutionMode,{50,spv::ExecutionModeOriginUpperLeft});
    s.op(spv::OpDecorate,{5,spv::DecorationBlock});s.op(spv::OpMemberDecorate,{5,0,spv::DecorationLocation,0});s.op(spv::OpMemberDecorate,{5,0,spv::DecorationFlat});s.op(spv::OpDecorate,{21,spv::DecorationLocation,0});
    s.op(spv::OpTypeVoid,{1});s.op(spv::OpTypeFunction,{2,1});s.op(spv::OpTypeInt,{3,32,0});s.op(spv::OpTypeVector,{4,3,4});
    s.op(spv::OpTypeStruct,{5,4});s.op(spv::OpTypePointer,{6,spv::StorageClassInput,5});s.op(spv::OpTypePointer,{7,spv::StorageClassInput,4});
    s.op(spv::OpTypeFloat,{8,32});s.op(spv::OpTypeVector,{9,8,4});s.op(spv::OpTypePointer,{10,spv::StorageClassOutput,9});
    s.op(spv::OpConstant,{3,11,0});s.op(spv::OpConstant,{3,12,15});s.op(spv::OpConstant,{3,13,16});s.op(spv::OpConstant,{8,14,0x3B808081});s.op(spv::OpConstant,{8,15,0x3F800000});
    s.op(spv::OpVariable,{6,20,spv::StorageClassInput});s.op(spv::OpVariable,{10,21,spv::StorageClassOutput});
    s.op(spv::OpFunction,{1,50,spv::FunctionControlMaskNone,2});s.op(spv::OpLabel,{51});s.op(spv::OpAccessChain,{7,52,20,11});s.op(spv::OpLoad,{4,53,52});
    s.op(spv::OpCompositeExtract,{3,54,53,0});s.op(spv::OpBitwiseAnd,{3,55,54,12});s.op(spv::OpIMul,{3,56,55,13});
    s.op(spv::OpCompositeExtract,{3,57,53,1});s.op(spv::OpIMul,{3,58,57,13});
    s.op(spv::OpCompositeExtract,{3,59,53,2});s.op(spv::OpBitwiseAnd,{3,60,59,12});s.op(spv::OpIMul,{3,61,60,13});
    s.op(spv::OpConvertUToF,{8,62,56});s.op(spv::OpConvertUToF,{8,63,58});s.op(spv::OpConvertUToF,{8,64,61});
    s.op(spv::OpFMul,{8,65,62,14});s.op(spv::OpFMul,{8,66,63,14});s.op(spv::OpFMul,{8,67,64,14});
    s.op(spv::OpCompositeConstruct,{9,68,65,66,67,15});s.op(spv::OpStore,{21,68});s.op(spv::OpReturn,{});s.op(spv::OpFunctionEnd,{});return s.words;
}

struct PrimitiveVertex { float x,y; uint32_t color; };

void initializePrepassContext(Context& c) {
    c.initialize();
    if (c.secondPool) vkDestroyCommandPool(c.device,c.secondPool,nullptr);
    vkDestroyCommandPool(c.device,c.pool,nullptr); vkDestroyDevice(c.device,nullptr);
    c.secondPool=c.pool=VK_NULL_HANDLE; c.device=VK_NULL_HANDLE;
    c.secondQueue=c.queue=VK_NULL_HANDLE; c.secondFamily=c.family;
    VkPhysicalDeviceProvokingVertexFeaturesEXT provoking{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROVOKING_VERTEX_FEATURES_EXT};
    VkPhysicalDeviceVulkan11Features v11{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES};
    VkPhysicalDevicePortabilitySubsetFeaturesKHR portability{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_FEATURES_KHR};
    VkPhysicalDevicePrimitiveTopologyListRestartFeaturesEXT restart{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PRIMITIVE_TOPOLOGY_LIST_RESTART_FEATURES_EXT};
    VkPhysicalDeviceExtendedDynamicState2FeaturesEXT dynamic{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_2_FEATURES_EXT};
    VkPhysicalDeviceExtendedDynamicState3FeaturesEXT dynamic3{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_3_FEATURES_EXT};dynamic.pNext=&dynamic3;
    provoking.pNext=&v11; v11.pNext=&portability; portability.pNext=&restart; restart.pNext=&dynamic;
    VkPhysicalDeviceFeatures2 supported{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2}; supported.pNext=&provoking;
    vkGetPhysicalDeviceFeatures2(c.physical,&supported);
    require(provoking.provokingVertexLast && v11.shaderDrawParameters && portability.triangleFans &&
            restart.primitiveTopologyListRestart && dynamic.extendedDynamicState2 && dynamic3.extendedDynamicState3SampleLocationsEnable && supported.features.vertexPipelineStoresAndAtomics && supported.features.multiDrawIndirect && supported.features.drawIndirectFirstInstance,
            "prepass fixture requires LAST, draw parameters, fans, list restart, dynamic restart and vertex writes");
    std::vector<const char*> extensions{VK_EXT_PROVOKING_VERTEX_EXTENSION_NAME,VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME,
        VK_EXT_PRIMITIVE_TOPOLOGY_LIST_RESTART_EXTENSION_NAME,VK_EXT_EXTENDED_DYNAMIC_STATE_2_EXTENSION_NAME,VK_KHR_PUSH_DESCRIPTOR_EXTENSION_NAME,VK_EXT_SAMPLE_LOCATIONS_EXTENSION_NAME,VK_EXT_EXTENDED_DYNAMIC_STATE_3_EXTENSION_NAME};
    uint32_t count=0; VK_CHECK(vkEnumerateDeviceExtensionProperties(c.physical,nullptr,&count,nullptr));
    std::vector<VkExtensionProperties> available(count); VK_CHECK(vkEnumerateDeviceExtensionProperties(c.physical,nullptr,&count,available.data()));
    for(auto* name:extensions) require(std::any_of(available.begin(),available.end(),[&](auto& e){return std::strcmp(name,e.extensionName)==0;}),std::string("required extension: ")+name);
    provoking.provokingVertexLast=VK_TRUE; provoking.transformFeedbackPreservesProvokingVertex=VK_FALSE;
    v11={VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES}; v11.pNext=&portability; v11.shaderDrawParameters=VK_TRUE;
    portability={VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_FEATURES_KHR}; portability.pNext=&restart; portability.triangleFans=VK_TRUE;
    restart={VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PRIMITIVE_TOPOLOGY_LIST_RESTART_FEATURES_EXT}; restart.pNext=&dynamic; restart.primitiveTopologyListRestart=VK_TRUE;
    dynamic={VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_2_FEATURES_EXT}; dynamic.extendedDynamicState2=VK_TRUE;dynamic.pNext=&dynamic3;
    dynamic3={VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_3_FEATURES_EXT};dynamic3.extendedDynamicState3SampleLocationsEnable=VK_TRUE;
    VkPhysicalDeviceFeatures features{}; features.vertexPipelineStoresAndAtomics=VK_TRUE; features.multiDrawIndirect=VK_TRUE; features.drawIndirectFirstInstance=VK_TRUE;
    features.occlusionQueryPrecise=supported.features.occlusionQueryPrecise; c.preciseOcclusionSupported=features.occlusionQueryPrecise;
    float priority=1; VkDeviceQueueCreateInfo q{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO}; q.queueFamilyIndex=c.family; q.queueCount=1; q.pQueuePriorities=&priority;
    VkDeviceCreateInfo d{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO}; d.pNext=&provoking; d.queueCreateInfoCount=1; d.pQueueCreateInfos=&q;
    d.enabledExtensionCount=uint32_t(extensions.size()); d.ppEnabledExtensionNames=extensions.data(); d.pEnabledFeatures=&features;
    VK_CHECK(vkCreateDevice(c.physical,&d,nullptr,&c.device)); vkGetDeviceQueue(c.device,c.family,0,&c.queue);
    require(c.isNative(c.queue),"prepass fixture requires actual native queue");
    const char* mab=std::getenv("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS");
    require(mab && c.usesArgumentBuffers(c.queue)==(mab[0]=='1'),"actual argument buffer mode matches explicit configuration");
    VkCommandPoolCreateInfo p{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO}; p.queueFamilyIndex=c.family;
    VK_CHECK(vkCreateCommandPool(c.device,&p,nullptr,&c.pool)); c.nativeBefore=c.counter(c.queue); c.nativeAfter=0;
}

struct PrepassCase { const char* name; bool resubmit=false, queryStop=false, barrierStop=false, writerStop=false, sameAllocation=false, dedicatedAlias=false; uint32_t pushKind=0; bool sampleLocations=false, indirectBatch=false, indirectArgumentAlias=false; bool leadingOrdinary=false, priorProducer=false, handoffMSAA=false, zeroOrdinary=false, vertexDependency=false; uint32_t batchRestart=0; };

Image dedicatedAliasImage(Context& c, uint32_t width, uint32_t height) {
    Image image{};VkImageCreateInfo info{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};info.flags=VK_IMAGE_CREATE_ALIAS_BIT;
    info.imageType=VK_IMAGE_TYPE_2D;info.format=VK_FORMAT_R32G32B32A32_UINT;info.extent={width,height,1};info.mipLevels=info.arrayLayers=1;
    info.samples=VK_SAMPLE_COUNT_1_BIT;info.tiling=VK_IMAGE_TILING_OPTIMAL;info.usage=VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT|VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    VK_CHECK(vkCreateImage(c.device,&info,nullptr,&image.image));VkMemoryRequirements requirements{};vkGetImageMemoryRequirements(c.device,image.image,&requirements);
    VkMemoryDedicatedAllocateInfo dedicated{VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO};dedicated.image=image.image;
    VkMemoryAllocateInfo allocation{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};allocation.pNext=&dedicated;allocation.allocationSize=requirements.size;
    allocation.memoryTypeIndex=c.memoryType(requirements.memoryTypeBits,VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    VkDeviceMemory memory;VK_CHECK(vkAllocateMemory(c.device,&allocation,nullptr,&memory));VK_CHECK(vkBindImageMemory(c.device,image.image,memory,0));
    auto vkImage=image.image;c.cleanup.push_back([&,vkImage,memory]{vkDestroyImage(c.device,vkImage,nullptr);vkFreeMemory(c.device,memory,nullptr);});
    VkImageViewCreateInfo view{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};view.image=image.image;view.viewType=VK_IMAGE_VIEW_TYPE_2D;view.format=info.format;
    view.subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1};VK_CHECK(vkCreateImageView(c.device,&view,nullptr,&image.view));
    auto vkView=image.view;c.cleanup.push_back([&,vkView]{vkDestroyImageView(c.device,vkView,nullptr);});return image;
}

// Deliberately share the Vulkan allocation while respecting buffer/image
// granularity and nonoverlap. The planner must still reject this weaker proof.
void sameAllocationResources(Context& c, uint32_t width, uint32_t height, Image& image, Buffer& indices, VkBufferUsageFlags usage=VK_BUFFER_USAGE_INDEX_BUFFER_BIT, VkDeviceSize bufferSize=256) {
    VkImageCreateInfo im{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO}; im.imageType=VK_IMAGE_TYPE_2D;
    im.format=VK_FORMAT_R32G32B32A32_UINT; im.extent={width,height,1}; im.mipLevels=im.arrayLayers=1;
    im.samples=VK_SAMPLE_COUNT_1_BIT; im.tiling=VK_IMAGE_TILING_OPTIMAL;
    im.usage=VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT|VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    VK_CHECK(vkCreateImage(c.device,&im,nullptr,&image.image));
    VkBufferCreateInfo b{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO}; b.size=bufferSize; b.usage=usage;
    VK_CHECK(vkCreateBuffer(c.device,&b,nullptr,&indices.buffer)); indices.size=b.size;
    VkMemoryRequirements ir{},br{}; vkGetImageMemoryRequirements(c.device,image.image,&ir); vkGetBufferMemoryRequirements(c.device,indices.buffer,&br);
    VkDeviceSize alignment=std::max({ir.alignment,br.alignment,c.properties.limits.bufferImageGranularity});
    VkDeviceSize offset=((ir.size+alignment-1)/alignment)*alignment;
    VkMemoryAllocateInfo alloc{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO}; alloc.allocationSize=offset+br.size;
    alloc.memoryTypeIndex=c.memoryType(ir.memoryTypeBits&br.memoryTypeBits,VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    VK_CHECK(vkAllocateMemory(c.device,&alloc,nullptr,&indices.memory));
    VK_CHECK(vkBindImageMemory(c.device,image.image,indices.memory,0)); VK_CHECK(vkBindBufferMemory(c.device,indices.buffer,indices.memory,offset));
    void* mapped=nullptr; VK_CHECK(vkMapMemory(c.device,indices.memory,0,VK_WHOLE_SIZE,0,&mapped)); indices.bytes=static_cast<uint8_t*>(mapped)+offset;
    auto vkImage=image.image; auto vkBuffer=indices.buffer; auto memory=indices.memory;
    c.cleanup.push_back([&,vkImage,vkBuffer,memory]{vkUnmapMemory(c.device,memory);vkDestroyBuffer(c.device,vkBuffer,nullptr);vkDestroyImage(c.device,vkImage,nullptr);vkFreeMemory(c.device,memory,nullptr);});
    VkImageViewCreateInfo view{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO}; view.image=image.image; view.viewType=VK_IMAGE_VIEW_TYPE_2D;
    view.format=im.format; view.subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1}; VK_CHECK(vkCreateImageView(c.device,&view,nullptr,&image.view));
    auto vkView=image.view; c.cleanup.push_back([&,vkView]{vkDestroyImageView(c.device,vkView,nullptr);});
}

void submitRecorded(Context& c, VkCommandBuffer command, VkCommandBuffer producer=VK_NULL_HANDLE) {
    VkFenceCreateInfo info{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO}; VkFence fence; VK_CHECK(vkCreateFence(c.device,&info,nullptr,&fence));
    VkCommandBuffer commands[2]={producer,command};
    VkSubmitInfo submit{VK_STRUCTURE_TYPE_SUBMIT_INFO}; submit.commandBufferCount=producer?2:1; submit.pCommandBuffers=producer?commands:&command;
    c.inFlight=true; VK_CHECK(vkQueueSubmit(c.queue,1,&submit,fence));
    VK_CHECK(vkWaitForFences(c.device,1,&fence,VK_TRUE,10000000000ull)); VK_CHECK(vkQueueWaitIdle(c.queue));
    c.inFlight=false; vkDestroyFence(c.device,fence,nullptr); c.nativeAfter=c.counter(c.queue);
    require(c.nativeAfter>c.nativeBefore,"native completion counter advances");
}

void prepassCase(Context& c, const PrepassCase& test) {
    c.oneTime = !test.resubmit; // Single-use lifetime coverage; repeated tests retain reusable flags.
    constexpr uint32_t width=64,height=64,rowBytes=1280,guard=64;
    const bool usePush=test.pushKind!=0;
    const bool multisample=test.sampleLocations||test.handoffMSAA;
    const VkFormat format=multisample?VK_FORMAT_R8G8B8A8_UNORM:VK_FORMAT_R32G32B32A32_UINT;
    const VkSampleCountFlagBits samples=multisample?VK_SAMPLE_COUNT_4_BIT:VK_SAMPLE_COUNT_1_BIT;
    const uint32_t pixelBytes=multisample?4:16;
    const VkBufferUsageFlags producerUsage=test.priorProducer?VK_BUFFER_USAGE_TRANSFER_DST_BIT:0;
    const VkSampleLocationEXT samplePatterns[2][4]={{{.25f,.25f},{.75f,.25f},{.25f,.75f},{.75f,.75f}},
        {{.0625f,.0625f},{.1875f,.0625f},{.0625f,.1875f},{.1875f,.1875f}}};
    auto setLocations=reinterpret_cast<PFN_vkCmdSetSampleLocationsEXT>(vkGetDeviceProcAddr(c.device,"vkCmdSetSampleLocationsEXT"));
    auto enableLocations=reinterpret_cast<PFN_vkCmdSetSampleLocationsEnableEXT>(vkGetDeviceProcAddr(c.device,"vkCmdSetSampleLocationsEnableEXT"));
    if(test.sampleLocations) {
        VkPhysicalDeviceSampleLocationsPropertiesEXT properties{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SAMPLE_LOCATIONS_PROPERTIES_EXT};
        VkPhysicalDeviceProperties2 p{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2};p.pNext=&properties;vkGetPhysicalDeviceProperties2(c.physical,&p);
        require(setLocations&&enableLocations&&properties.variableSampleLocations&&(properties.sampleLocationSampleCounts&VK_SAMPLE_COUNT_4_BIT),"dynamic 4x sample locations advertised");
    }
    auto setRestart=reinterpret_cast<PFN_vkCmdSetPrimitiveRestartEnableEXT>(vkGetDeviceProcAddr(c.device,"vkCmdSetPrimitiveRestartEnableEXT"));
    require(setRestart!=nullptr,"dynamic restart command available");
    std::vector<PrimitiveVertex> vertexData(13,{2,2,0});
    for(uint32_t i=0;i<4;++i) {
        float x=i%2?.5f:-.5f,y=i/2?.5f:-.5f;
        vertexData[1+i*3]={x-.35f,y-.35f,0x100+i*3};
        vertexData[2+i*3]={x+.35f,y-.35f,0x101+i*3};
        vertexData[3+i*3]={x,y+.35f,0x102+i*3};
    }
    auto vertices=c.buffer(32+vertexData.size()*sizeof(PrimitiveVertex),VK_BUFFER_USAGE_VERTEX_BUFFER_BIT|producerUsage);
    std::memset(vertices.bytes,0,vertices.size); std::memcpy(static_cast<uint8_t*>(vertices.bytes)+32,vertexData.data(),vertexData.size()*sizeof(PrimitiveVertex));
    Image candidate{}; Buffer indices{}, indirect{}, oracleIndirect{};
    if(test.indirectArgumentAlias) {
        sameAllocationResources(c,width,height,candidate,indirect,VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT|VK_BUFFER_USAGE_TRANSFER_DST_BIT);
        indices=c.buffer(256,VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
    }
    else
    if(test.sameAllocation) sameAllocationResources(c,width,height,candidate,indices,VK_BUFFER_USAGE_INDEX_BUFFER_BIT,test.batchRestart?8192:256);
    else {candidate=test.dedicatedAlias?dedicatedAliasImage(c,width,height):c.image(width,height,format,VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT|VK_IMAGE_USAGE_TRANSFER_SRC_BIT);indices=c.buffer(test.batchRestart?8192:256,VK_BUFFER_USAGE_INDEX_BUFFER_BIT|producerUsage);}
    auto reference=c.image(width,height,format,VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT|VK_IMAGE_USAGE_TRANSFER_SRC_BIT);
    auto oracleIndices=c.buffer(128,VK_BUFFER_USAGE_INDEX_BUFFER_BIT|producerUsage);
    std::memset(indices.bytes,0,indices.size); auto* ix=static_cast<uint16_t*>(indices.bytes);
    ix[9]=0;ix[10]=1;ix[11]=2; ix[18]=0xFFFF;ix[19]=3;ix[20]=4;ix[21]=5;
    ix[33]=0xFFFF;ix[34]=9;ix[35]=10;ix[36]=11;
    uint32_t originalOracle[12]={2,0,1,5,3,4,2,0,1,11,9,10}; std::memcpy(oracleIndices.bytes,originalOracle,sizeof(originalOracle));
    auto batchCount=[&](uint32_t draw) {return test.batchRestart==2?31u:test.batchRestart==3?(draw<2?7u:4u):256u+draw;};
    auto batchStart=[&](uint32_t draw) {return test.batchRestart==3?1u:1u+draw*(test.batchRestart==2?3u:13u);};
    auto batchOffset=[](uint32_t draw) {return 64u+draw*1536u;};
    auto batchWrite=[&](uint32_t draw,uint32_t element,uint32_t value) {
        auto* p=static_cast<uint8_t*>(indices.bytes)+batchOffset(draw);
        if(draw%2)reinterpret_cast<uint32_t*>(p)[element]=value;
        else reinterpret_cast<uint16_t*>(p)[element]=uint16_t(value);
    };
    if(test.batchRestart) {
        std::memset(indices.bytes,0xFF,indices.size);
        for(uint32_t draw=0;draw<4;++draw)for(uint32_t j=0;j<3;++j)
            batchWrite(draw,2+batchStart(draw)+j,(draw==2?0:draw*3)+j);
    }
    if(test.indirectBatch) {
        for(uint32_t draw=0;draw<4;++draw) {
            ix[draw*4]=0xFFFF;ix[draw*4+1]=draw*3;ix[draw*4+2]=draw*3+1;ix[draw*4+3]=draw*3+2;
            auto* ref=static_cast<uint32_t*>(oracleIndices.bytes);ref[draw*3]=draw*3+2;ref[draw*3+1]=draw*3;ref[draw*3+2]=draw*3+1;
        }
        if(!indirect.buffer)indirect=c.buffer(256,VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT|VK_BUFFER_USAGE_TRANSFER_DST_BIT,false);
        oracleIndirect=c.buffer(256,VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT|VK_BUFFER_USAGE_TRANSFER_DST_BIT,false);
    }
    auto output=c.buffer(guard*2+rowBytes*height*2,VK_BUFFER_USAGE_TRANSFER_DST_BIT); std::memset(output.bytes,0xA5,output.size);
    auto written=c.buffer(64,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT); std::memset(written.bytes,0,written.size);
    Buffer uniforms{}, readStorage{};
    VkDeviceSize bankStride=std::max<VkDeviceSize>(256,std::max(c.properties.limits.minUniformBufferOffsetAlignment,c.properties.limits.minStorageBufferOffsetAlignment));
    if(usePush) {
        uniforms=c.buffer(bankStride*2,VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT|producerUsage);readStorage=c.buffer(bankStride*2,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT|producerUsage);
        std::memset(uniforms.bytes,0,uniforms.size);std::memset(readStorage.bytes,0,readStorage.size);
        for(uint32_t bank=0;bank<2;++bank) {
            *reinterpret_cast<uint32_t*>(static_cast<uint8_t*>(uniforms.bytes)+bank*bankStride)=bank?0x2000:0x1000;
            auto* words=reinterpret_cast<uint32_t*>(static_cast<uint8_t*>(readStorage.bytes)+bank*bankStride);
            for(uint32_t i=0;i<16;++i)words[i]=bank?200+19*i:100+17*i;
        }
    }
    VkDescriptorSetLayoutBinding descriptors[2]={{0,usePush?VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,1,VK_SHADER_STAGE_VERTEX_BIT,nullptr},
        {1,VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,1,VK_SHADER_STAGE_VERTEX_BIT,nullptr}};
    VkDescriptorSetLayoutCreateInfo setInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};setInfo.bindingCount=usePush?2:1;setInfo.pBindings=descriptors;
    setInfo.flags=usePush?VK_DESCRIPTOR_SET_LAYOUT_CREATE_PUSH_DESCRIPTOR_BIT_KHR:0;
    VkDescriptorSetLayout setLayout;VK_CHECK(vkCreateDescriptorSetLayout(c.device,&setInfo,nullptr,&setLayout));c.cleanup.push_back([&,setLayout]{vkDestroyDescriptorSetLayout(c.device,setLayout,nullptr);});
    VkDescriptorSet descriptorSet=VK_NULL_HANDLE;
    if(!usePush) {
        VkDescriptorPoolSize poolSize{VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,1};VkDescriptorPoolCreateInfo poolInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};poolInfo.maxSets=1;poolInfo.poolSizeCount=1;poolInfo.pPoolSizes=&poolSize;
        VkDescriptorPool pool;VK_CHECK(vkCreateDescriptorPool(c.device,&poolInfo,nullptr,&pool));c.cleanup.push_back([&,pool]{vkDestroyDescriptorPool(c.device,pool,nullptr);});
        VkDescriptorSetAllocateInfo allocate{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};allocate.descriptorPool=pool;allocate.descriptorSetCount=1;allocate.pSetLayouts=&setLayout;
        VK_CHECK(vkAllocateDescriptorSets(c.device,&allocate,&descriptorSet));
        VkDescriptorBufferInfo bufferInfo{written.buffer,0,written.size};VkWriteDescriptorSet write{VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET};write.dstSet=descriptorSet;write.dstBinding=0;write.descriptorCount=1;write.descriptorType=VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;write.pBufferInfo=&bufferInfo;
        vkUpdateDescriptorSets(c.device,1,&write,0,nullptr);
    }
    VkPipelineLayoutCreateInfo layoutInfo{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};layoutInfo.setLayoutCount=1;layoutInfo.pSetLayouts=&setLayout;
    VkPipelineLayout layout;VK_CHECK(vkCreatePipelineLayout(c.device,&layoutInfo,nullptr,&layout));c.cleanup.push_back([&,layout]{vkDestroyPipelineLayout(c.device,layout,nullptr);});
    auto pushDescriptors=reinterpret_cast<PFN_vkCmdPushDescriptorSetKHR>(vkGetDeviceProcAddr(c.device,"vkCmdPushDescriptorSetKHR"));
    auto pushTemplate=reinterpret_cast<PFN_vkCmdPushDescriptorSetWithTemplateKHR>(vkGetDeviceProcAddr(c.device,"vkCmdPushDescriptorSetWithTemplateKHR"));
    VkDescriptorUpdateTemplate updateTemplate=VK_NULL_HANDLE;
    if(usePush)require(pushDescriptors&&pushTemplate,"both actual push descriptor entry points available");
    if(test.pushKind==2) {
        VkDescriptorUpdateTemplateEntry entries[2]={{0,0,1,VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,0,sizeof(VkDescriptorBufferInfo)},
            {1,0,1,VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,sizeof(VkDescriptorBufferInfo),sizeof(VkDescriptorBufferInfo)}};
        VkDescriptorUpdateTemplateCreateInfo t{VK_STRUCTURE_TYPE_DESCRIPTOR_UPDATE_TEMPLATE_CREATE_INFO};t.descriptorUpdateEntryCount=2;t.pDescriptorUpdateEntries=entries;
        t.templateType=VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_PUSH_DESCRIPTORS_KHR;t.descriptorSetLayout=setLayout;t.pipelineBindPoint=VK_PIPELINE_BIND_POINT_GRAPHICS;t.pipelineLayout=layout;t.set=0;
        VK_CHECK(vkCreateDescriptorUpdateTemplate(c.device,&t,nullptr,&updateTemplate));c.cleanup.push_back([&,updateTemplate]{vkDestroyDescriptorUpdateTemplate(c.device,updateTemplate,nullptr);});
    }
    auto pushReadBuffers=[&](VkCommandBuffer cmd,uint32_t bank) {
        VkDescriptorBufferInfo infos[2]={{uniforms.buffer,bank*bankStride,16},{readStorage.buffer,bank*bankStride,64}};
        if(test.pushKind==2)pushTemplate(cmd,updateTemplate,layout,0,infos);
        else {
            VkWriteDescriptorSet writes[2]{};
            for(uint32_t i=0;i<2;++i){writes[i].sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;writes[i].dstBinding=i;writes[i].descriptorCount=1;writes[i].descriptorType=i?VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;writes[i].pBufferInfo=&infos[i];}
            pushDescriptors(cmd,VK_PIPELINE_BIND_POINT_GRAPHICS,layout,0,2,writes);
        }
    };
    VkAttachmentDescription attachment{};attachment.format=format;attachment.samples=samples;
    attachment.loadOp=VK_ATTACHMENT_LOAD_OP_CLEAR;attachment.storeOp=VK_ATTACHMENT_STORE_OP_STORE;
    attachment.initialLayout=VK_IMAGE_LAYOUT_UNDEFINED;attachment.finalLayout=VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    VkAttachmentReference color{0,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};VkSubpassDescription subpass{};subpass.pipelineBindPoint=VK_PIPELINE_BIND_POINT_GRAPHICS;subpass.colorAttachmentCount=1;subpass.pColorAttachments=&color;
    VkSubpassDependency dependencies[2]={{0,VK_SUBPASS_EXTERNAL,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,VK_ACCESS_TRANSFER_READ_BIT,0},
        {0,0,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,VK_ACCESS_COLOR_ATTACHMENT_READ_BIT|VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,VK_DEPENDENCY_BY_REGION_BIT}};
    if(test.vertexDependency) dependencies[1]={0,0,VK_PIPELINE_STAGE_VERTEX_SHADER_BIT,VK_PIPELINE_STAGE_VERTEX_SHADER_BIT,VK_ACCESS_SHADER_WRITE_BIT,VK_ACCESS_SHADER_READ_BIT,0};
    VkAttachmentDescription attachments[3]={attachment,attachment,{}};
    VkAttachmentReference resolve{1,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};
    if(multisample){attachments[0].finalLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;attachments[1].samples=VK_SAMPLE_COUNT_1_BIT;attachments[1].loadOp=VK_ATTACHMENT_LOAD_OP_DONT_CARE;subpass.pResolveAttachments=&resolve;}
    if(test.priorProducer){attachments[0].loadOp=VK_ATTACHMENT_LOAD_OP_LOAD;attachments[0].initialLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;}
    const uint32_t depthIndex=multisample?2:1;
    VkAttachmentReference depth{depthIndex,VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL};
    uint32_t attachmentCount=multisample?2:1;
    if(test.handoffMSAA) {
        require(test.priorProducer,"depth LOAD fixture requires the earlier producer");
        auto& a=attachments[depthIndex];a.format=VK_FORMAT_D32_SFLOAT;a.samples=samples;
        a.loadOp=VK_ATTACHMENT_LOAD_OP_LOAD;a.storeOp=VK_ATTACHMENT_STORE_OP_STORE;
        a.stencilLoadOp=VK_ATTACHMENT_LOAD_OP_DONT_CARE;a.stencilStoreOp=VK_ATTACHMENT_STORE_OP_DONT_CARE;
        a.initialLayout=a.finalLayout=VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
        subpass.pDepthStencilAttachment=&depth;++attachmentCount;
    }
    VkRenderPassCreateInfo passInfo{VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO};passInfo.attachmentCount=attachmentCount;passInfo.pAttachments=attachments;passInfo.subpassCount=1;passInfo.pSubpasses=&subpass;passInfo.dependencyCount=2;passInfo.pDependencies=dependencies;
    VkRenderPass pass;VK_CHECK(vkCreateRenderPass(c.device,&passInfo,nullptr,&pass));c.cleanup.push_back([&,pass]{vkDestroyRenderPass(c.device,pass,nullptr);});
    VkRenderPass producerPass=VK_NULL_HANDLE;
    if(test.priorProducer) {
        // Compatible with the consumer framebuffers: only load/store/layouts
        // differ. The consumer must LOAD actual preceding GPU attachment data.
        VkAttachmentDescription producerAttachments[3];std::memcpy(producerAttachments,attachments,sizeof(attachments));
        for(uint32_t i=0;i<attachmentCount;++i)producerAttachments[i].initialLayout=VK_IMAGE_LAYOUT_UNDEFINED;
        producerAttachments[0].loadOp=VK_ATTACHMENT_LOAD_OP_CLEAR;
        producerAttachments[0].finalLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
        if(test.handoffMSAA)producerAttachments[depthIndex].loadOp=VK_ATTACHMENT_LOAD_OP_CLEAR;
        VkRenderPassCreateInfo producerInfo=passInfo;producerInfo.pAttachments=producerAttachments;
        VK_CHECK(vkCreateRenderPass(c.device,&producerInfo,nullptr,&producerPass));c.cleanup.push_back([&,producerPass]{vkDestroyRenderPass(c.device,producerPass,nullptr);});
    }
    VkFramebuffer framebuffers[2];Image images[2]={candidate,reference};
    Image multisampled[2]{},depthImages[2]{};
    if(multisample)for(auto& im:multisampled)im=c.image(width,height,format,VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,VK_SAMPLE_COUNT_4_BIT);
    if(test.handoffMSAA)for(auto& im:depthImages)im=c.image(width,height,VK_FORMAT_D32_SFLOAT,VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,samples,VK_IMAGE_ASPECT_DEPTH_BIT);
    for(uint32_t i=0;i<2;++i) {
        VkImageView views[3]={multisample?multisampled[i].view:images[i].view,images[i].view,VK_NULL_HANDLE};
        if(test.handoffMSAA)views[depthIndex]=depthImages[i].view;
        VkFramebufferCreateInfo f{VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO};f.renderPass=pass;f.attachmentCount=attachmentCount;f.pAttachments=views;f.width=width;f.height=height;f.layers=1;
        VK_CHECK(vkCreateFramebuffer(c.device,&f,nullptr,&framebuffers[i]));auto fb=framebuffers[i];c.cleanup.push_back([&,fb]{vkDestroyFramebuffer(c.device,fb,nullptr);});
    }
    VkShaderModule vertex=c.shader(prepassVertexShader(false,usePush,test.vertexDependency)),writer=(test.writerStop||test.vertexDependency)?c.shader(prepassVertexShader(true)):vertex,fragment=c.shader(multisample?prepassSampleFragmentShader():prepassFragmentShader());
    auto pipeline=[&](VkPrimitiveTopology topology,bool oracle,bool writes,uint32_t sampleDraw=0) {
        VkPipelineShaderStageCreateInfo stages[2]={{VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,nullptr,0,VK_SHADER_STAGE_VERTEX_BIT,writes?writer:vertex,"main",nullptr},{VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,nullptr,0,VK_SHADER_STAGE_FRAGMENT_BIT,fragment,"main",nullptr}};
        VkVertexInputBindingDescription binding{0,sizeof(PrimitiveVertex),VK_VERTEX_INPUT_RATE_VERTEX};VkVertexInputAttributeDescription attrs[2]={{0,0,VK_FORMAT_R32G32_SFLOAT,0},{1,0,VK_FORMAT_R32_UINT,8}};
        VkPipelineVertexInputStateCreateInfo vi{VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};vi.vertexBindingDescriptionCount=1;vi.pVertexBindingDescriptions=&binding;vi.vertexAttributeDescriptionCount=2;vi.pVertexAttributeDescriptions=attrs;
        VkPipelineInputAssemblyStateCreateInfo ia{VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO};ia.topology=topology;
        VkViewport viewport{0,0,float(width),float(height),0,1};VkRect2D scissor{{0,0},{width,height}};
        VkPipelineViewportStateCreateInfo vp{VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO};vp.viewportCount=vp.scissorCount=1;vp.pViewports=&viewport;vp.pScissors=&scissor;
        VkPipelineRasterizationProvokingVertexStateCreateInfoEXT pv{VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_PROVOKING_VERTEX_STATE_CREATE_INFO_EXT};pv.provokingVertexMode=oracle?VK_PROVOKING_VERTEX_MODE_FIRST_VERTEX_EXT:VK_PROVOKING_VERTEX_MODE_LAST_VERTEX_EXT;
        VkPipelineRasterizationStateCreateInfo rs{VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO};rs.pNext=&pv;rs.polygonMode=VK_POLYGON_MODE_FILL;rs.cullMode=VK_CULL_MODE_NONE;rs.frontFace=VK_FRONT_FACE_COUNTER_CLOCKWISE;rs.lineWidth=1;
        VkPipelineMultisampleStateCreateInfo ms{VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO};ms.rasterizationSamples=samples;
        VkPipelineSampleLocationsStateCreateInfoEXT locations{VK_STRUCTURE_TYPE_PIPELINE_SAMPLE_LOCATIONS_STATE_CREATE_INFO_EXT};
        locations.sampleLocationsEnable=sampleDraw!=1;locations.sampleLocationsInfo={VK_STRUCTURE_TYPE_SAMPLE_LOCATIONS_INFO_EXT,nullptr,VK_SAMPLE_COUNT_4_BIT,{1,1},4,samplePatterns[sampleDraw>=2]};
        if(test.sampleLocations)ms.pNext=&locations;
        VkPipelineColorBlendAttachmentState blend{};blend.colorWriteMask=15;VkPipelineColorBlendStateCreateInfo cb{VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO};cb.attachmentCount=1;cb.pAttachments=&blend;
        VkDynamicState dyn[3]={VK_DYNAMIC_STATE_PRIMITIVE_RESTART_ENABLE_EXT,VK_DYNAMIC_STATE_SAMPLE_LOCATIONS_EXT,VK_DYNAMIC_STATE_SAMPLE_LOCATIONS_ENABLE_EXT};VkPipelineDynamicStateCreateInfo ds{VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO};ds.dynamicStateCount=test.sampleLocations&&!oracle?3:1;ds.pDynamicStates=dyn;
        VkPipelineDepthStencilStateCreateInfo depthState{VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO};depthState.depthTestEnable=depthState.depthWriteEnable=test.handoffMSAA;depthState.depthCompareOp=VK_COMPARE_OP_LESS;
        VkGraphicsPipelineCreateInfo info{VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO};info.pDepthStencilState=test.handoffMSAA?&depthState:nullptr;info.stageCount=2;info.pStages=stages;info.pVertexInputState=&vi;info.pInputAssemblyState=&ia;info.pViewportState=&vp;info.pRasterizationState=&rs;info.pMultisampleState=&ms;info.pColorBlendState=&cb;info.pDynamicState=&ds;info.layout=layout;info.renderPass=pass;
        VkPipeline result;VK_CHECK(vkCreateGraphicsPipelines(c.device,VK_NULL_HANDLE,1,&info,nullptr,&result));c.cleanup.push_back([&,result]{vkDestroyPipeline(c.device,result,nullptr);});return result;
    };
    VkPipeline list=pipeline(VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,false,false),strip=pipeline(VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP,false,false),fan=pipeline(VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN,false,false),oracle=pipeline(VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,true,false);
    VkPipeline sampleOracle[4]={oracle,oracle,oracle,oracle};
    if(test.sampleLocations)for(uint32_t i=1;i<4;++i)sampleOracle[i]=pipeline(VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,true,false,i);
    VkPipeline writerPipeline=test.writerStop?pipeline(VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,false,true):list;
    VkPipeline dependencyWriter=test.vertexDependency?pipeline(VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,true,true):VK_NULL_HANDLE;
    VkQueryPool queries=VK_NULL_HANDLE;
    if(test.queryStop) {VkQueryPoolCreateInfo query{VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO};query.queryType=VK_QUERY_TYPE_OCCLUSION;query.queryCount=2;VK_CHECK(vkCreateQueryPool(c.device,&query,nullptr,&queries));c.cleanup.push_back([&,queries]{vkDestroyQueryPool(c.device,queries,nullptr);});}
    VkCommandBuffer producer=VK_NULL_HANDLE;
    if(test.priorProducer) {
        producer=c.begin();
        auto produce=[&](const Buffer& buffer) {
            require(buffer.size<=65536&&buffer.size%4==0,"bounded vkCmdUpdateBuffer producer");
            vkCmdUpdateBuffer(producer,buffer.buffer,0,buffer.size,buffer.bytes);
            // vkCmdUpdateBuffer copies at recording time. Initial host contents
            // cannot accidentally satisfy either the ordinary or prepared draw.
            std::memset(buffer.bytes,0,buffer.size);
        };
        produce(vertices);produce(indices);produce(oracleIndices);
        if(usePush){produce(uniforms);produce(readStorage);}
        for(uint32_t i=0;i<2;++i) {
            VkClearValue clear[3]{};
            if(multisample){clear[0].color.float32[0]=.25f;clear[0].color.float32[1]=.5f;clear[0].color.float32[2]=.75f;}
            else {clear[0].color.uint32[0]=11;clear[0].color.uint32[1]=22;clear[0].color.uint32[2]=33;}
            if(test.handoffMSAA)clear[depthIndex].depthStencil.depth=.5f;
            VkRenderPassBeginInfo begin{VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO};begin.renderPass=producerPass;begin.framebuffer=framebuffers[i];begin.renderArea={{0,0},{width,height}};begin.clearValueCount=attachmentCount;begin.pClearValues=clear;
            vkCmdBeginRenderPass(producer,&begin,VK_SUBPASS_CONTENTS_INLINE);vkCmdEndRenderPass(producer);
        }
        barrier(producer,VK_PIPELINE_STAGE_TRANSFER_BIT|VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT|VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT|VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
            VK_ACCESS_TRANSFER_WRITE_BIT|VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT|VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
            VK_PIPELINE_STAGE_VERTEX_INPUT_BIT|VK_PIPELINE_STAGE_VERTEX_SHADER_BIT|VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT|VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT|VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
            VK_ACCESS_INDEX_READ_BIT|VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT|VK_ACCESS_UNIFORM_READ_BIT|VK_ACCESS_SHADER_READ_BIT|VK_ACCESS_COLOR_ATTACHMENT_READ_BIT|VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT|VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT|VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT);
        VK_CHECK(vkEndCommandBuffer(producer));
    }
    VkCommandBuffer command=c.begin();if(queries)vkCmdResetQueryPool(command,queries,0,2);
    if(test.indirectBatch) {
        uint32_t records[48]={}, referenceRecords[48]={};
        for(uint32_t draw=0;draw<(test.writerStop?4u:5u);++draw) {
            // The final record overwrites quadrant zero with DrawID=4. This
            // checks render order as well as independent conversion correctness.
            uint32_t quadrant=draw%4;
            VkDrawIndexedIndirectCommand a{4,1,quadrant*4,1,2},b{3,1,quadrant*3,1,2};
            std::memcpy(records+8+draw*8,&a,sizeof(a));std::memcpy(referenceRecords+8+draw*8,&b,sizeof(b));
        }
        // Actual argument bytes are GPU produced after encoding; there is no CPU argument snapshot.
        vkCmdUpdateBuffer(command,indirect.buffer,0,sizeof(records),records);
        vkCmdUpdateBuffer(command,oracleIndirect.buffer,0,sizeof(referenceRecords),referenceRecords);
        barrier(command,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_TRANSFER_WRITE_BIT,VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT,VK_ACCESS_INDIRECT_COMMAND_READ_BIT);
    }
    for(uint32_t imageIndex=0;imageIndex<2;++imageIndex) {
        if(test.vertexDependency && imageIndex) {
            barrier(command,VK_PIPELINE_STAGE_VERTEX_SHADER_BIT,VK_ACCESS_SHADER_READ_BIT|VK_ACCESS_SHADER_WRITE_BIT,
                VK_PIPELINE_STAGE_VERTEX_SHADER_BIT,VK_ACCESS_SHADER_READ_BIT|VK_ACCESS_SHADER_WRITE_BIT);
        }
        bool isOracle=imageIndex!=0;VkClearValue clear{};VkRenderPassBeginInfo begin{VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO};begin.renderPass=pass;begin.framebuffer=framebuffers[imageIndex];begin.renderArea={{0,0},{width,height}};begin.clearValueCount=1;begin.pClearValues=&clear;
        vkCmdBeginRenderPass(command,&begin,VK_SUBPASS_CONTENTS_INLINE);VkDeviceSize vertexOffset=32;vkCmdBindVertexBuffers(command,0,1,&vertices.buffer,&vertexOffset);
        if(usePush)pushReadBuffers(command,0);else vkCmdBindDescriptorSets(command,VK_PIPELINE_BIND_POINT_GRAPHICS,layout,0,1,&descriptorSet,0,nullptr);
        if(test.zeroOrdinary&&!isOracle) {
            vkCmdBindPipeline(command,VK_PIPELINE_BIND_POINT_GRAPHICS,oracle);setRestart(command,VK_FALSE);
            vkCmdBindIndexBuffer(command,oracleIndices.buffer,0,VK_INDEX_TYPE_UINT32);
            vkCmdDrawIndexed(command,0,1,0,1,2);vkCmdDrawIndexed(command,3,0,0,1,2);
        }
        if(test.indirectBatch) {
            if(queries)vkCmdBeginQuery(command,queries,imageIndex,c.preciseOcclusionSupported?VK_QUERY_CONTROL_PRECISE_BIT:0);
            vkCmdBindPipeline(command,VK_PIPELINE_BIND_POINT_GRAPHICS,isOracle?oracle:writerPipeline);
            setRestart(command,!isOracle);
            vkCmdBindIndexBuffer(command,isOracle?oracleIndices.buffer:indices.buffer,0,isOracle?VK_INDEX_TYPE_UINT32:VK_INDEX_TYPE_UINT16);
            vkCmdDrawIndexedIndirect(command,isOracle?oracleIndirect.buffer:indirect.buffer,32,test.writerStop?4:5,32);
        } else for(uint32_t draw=0;draw<4;++draw) {
            if(usePush&&draw==2)pushReadBuffers(command,1);
            if(test.sampleLocations&&!isOracle) {
                VkSampleLocationsInfoEXT locations{VK_STRUCTURE_TYPE_SAMPLE_LOCATIONS_INFO_EXT,nullptr,VK_SAMPLE_COUNT_4_BIT,{1,1},4,samplePatterns[draw>=2]};
                setLocations(command,&locations);enableLocations(command,draw!=1);
            }
            if(draw==1 && queries)vkCmdBeginQuery(command,queries,imageIndex,c.preciseOcclusionSupported?VK_QUERY_CONTROL_PRECISE_BIT:0);
            if(draw==1 && test.vertexDependency) {
                VkMemoryBarrier dependency{VK_STRUCTURE_TYPE_MEMORY_BARRIER};dependency.srcAccessMask=VK_ACCESS_SHADER_WRITE_BIT;dependency.dstAccessMask=VK_ACCESS_SHADER_READ_BIT;
                vkCmdPipelineBarrier(command,VK_PIPELINE_STAGE_VERTEX_SHADER_BIT,VK_PIPELINE_STAGE_VERTEX_SHADER_BIT,0,1,&dependency,0,nullptr,0,nullptr);
            }
            if(draw==1 && test.barrierStop) {
                VkMemoryBarrier m{VK_STRUCTURE_TYPE_MEMORY_BARRIER};m.srcAccessMask=VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;m.dstAccessMask=VK_ACCESS_COLOR_ATTACHMENT_READ_BIT|VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
                vkCmdPipelineBarrier(command,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,VK_DEPENDENCY_BY_REGION_BIT,1,&m,0,nullptr,0,nullptr);
            }
            VkPipeline selected=(isOracle||(test.leadingOrdinary&&draw==0))?sampleOracle[draw]:(draw==0?writerPipeline:draw==1?strip:draw==2?fan:list);
            if(test.batchRestart&&!isOracle&&!(test.leadingOrdinary&&draw==0))selected=draw==0?writerPipeline:list;
            if(test.vertexDependency) selected=draw==0?dependencyWriter:oracle;
            vkCmdBindPipeline(command,VK_PIPELINE_BIND_POINT_GRAPHICS,selected);setRestart(command,!test.vertexDependency&&!isOracle&&!(test.leadingOrdinary&&draw==0)&&(test.batchRestart||draw==1||draw==3));
            if(isOracle||test.vertexDependency||(test.leadingOrdinary&&draw==0)) {vkCmdBindIndexBuffer(command,oracleIndices.buffer,draw*12,VK_INDEX_TYPE_UINT32);vkCmdDrawIndexed(command,3,1,0,draw==2?7:1,2);}
            else if(test.batchRestart) {vkCmdBindIndexBuffer(command,indices.buffer,batchOffset(draw),draw%2?VK_INDEX_TYPE_UINT32:VK_INDEX_TYPE_UINT16);vkCmdDrawIndexed(command,batchCount(draw),1,2,draw==2?7:1,2);}
            else if(draw==2) vkCmdDraw(command,3,1,7,2);
            else {vkCmdBindIndexBuffer(command,indices.buffer,draw==0?16:draw==1?32:64,VK_INDEX_TYPE_UINT16);vkCmdDrawIndexed(command,draw?4:3,1,draw==1?2:1,1,2);}
        }
        if(queries)vkCmdEndQuery(command,queries,imageIndex);vkCmdEndRenderPass(command);
        VkBufferImageCopy copy{};copy.bufferOffset=guard+imageIndex*rowBytes*height;copy.bufferRowLength=rowBytes/pixelBytes;copy.imageSubresource={VK_IMAGE_ASPECT_COLOR_BIT,0,0,1};copy.imageExtent={width,height,1};
        vkCmdCopyImageToBuffer(command,images[imageIndex].image,VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,output.buffer,1,&copy);
    }
    barrier(command,VK_PIPELINE_STAGE_TRANSFER_BIT|VK_PIPELINE_STAGE_VERTEX_SHADER_BIT,VK_ACCESS_TRANSFER_WRITE_BIT|VK_ACCESS_SHADER_WRITE_BIT,VK_PIPELINE_STAGE_HOST_BIT,VK_ACCESS_HOST_READ_BIT);
    VK_CHECK(vkEndCommandBuffer(command));
    auto verify=[&](bool rewritten) {
        const auto* bytes=static_cast<const uint8_t*>(output.bytes);uint32_t coverage[4]={};
        for(uint32_t y=0;y<height;++y)for(uint32_t x=0;x<width;++x) {
            auto* actualBytes=bytes+guard+y*rowBytes+x*pixelBytes;
            auto* expectedBytes=bytes+guard+rowBytes*height+y*rowBytes+x*pixelBytes;
            if(multisample) {
                for(uint32_t channel=0;channel<4;++channel)require(std::abs(int(actualBytes[channel])-int(expectedBytes[channel]))<=1,"dynamic sample positions/enable/resolve equal static per-draw PSO at "+std::to_string(x)+","+std::to_string(y));
                if(actualBytes[3]==255) {
                    uint32_t vertex=(actualBytes[1]+8)/16;require(vertex==3||vertex==6||vertex==9||vertex==12,"sample case LAST vertex ID");
                    uint32_t descriptorAdd=usePush?(vertex<=6?0x1000+100+17*vertex:0x2000+200+19*vertex):0;
                    require(std::abs(int(actualBytes[0])-int(((vertexData[vertex].color+descriptorAdd)&15)*16))<=1,"sample case LAST color and readonly descriptors");
                    require(std::abs(int(actualBytes[2])-int(vertex==9?112:16))<=1,"sample case base vertex");
                    ++coverage[(y>=height/2?2:0)+(x>=width/2?1:0)];
                }
                continue;
            }
            auto* actual=reinterpret_cast<const uint32_t*>(actualBytes);auto* expected=reinterpret_cast<const uint32_t*>(expectedBytes);
            require(std::memcmp(actual,expected,16)==0,std::string(test.name)+" integer pixel/ID mismatch at "+std::to_string(x)+","+std::to_string(y));
            if(actual[3]) {
                require(actual[1]>0&&actual[1]<vertexData.size(),"flat VertexIndex in source bounds");
                uint32_t draw=(actual[1]-1)/3;
                uint32_t descriptorAdd=usePush?(draw<2?0x1000+100+17*actual[1]:0x2000+200+19*actual[1]):0;
                if(test.vertexDependency&&draw>0) descriptorAdd+=0xA1100001;
                require(actual[0]==vertexData[actual[1]].color+descriptorAdd,"flat color consumes the current pushed UBO and readonly SSBO");
                require(actual[1]==(draw==0&&rewritten?1:3*(draw+1)),"explicit LAST vertex oracle reflects coherent index rewrite");
                require(actual[2]==2*65536+2*4096+(test.indirectBatch?((draw==0&&!test.writerStop?4:draw)*256+1):draw==2?7:1),"firstVertex/baseVertex/baseInstance retain shader-visible meaning");
                ++coverage[(y>=height/2?2:0)+(x>=width/2?1:0)];
            }
        }
        for(auto n:coverage)require(n>32,"every draw must produce visible oracle pixels");
        if(test.priorProducer) {
            const auto* corner=bytes+guard;
            if(multisample) {const uint8_t marker[4]={64,128,191,0};for(uint32_t i=0;i<4;++i)require(std::abs(int(corner[i])-int(marker[i]))<=1,"MSAA attachment LOAD preserves preceding command buffer clear");}
            else {const uint32_t marker[4]={11,22,33,0};require(std::memcmp(corner,marker,sizeof(marker))==0,"attachment LOAD preserves preceding command buffer clear");}
        }
        for(uint32_t i=0;i<output.size;++i) {bool pixel=i>=guard&&i<guard+2*rowBytes*height&&(i-guard)%rowBytes<width*pixelBytes;if(!pixel)require(bytes[i]==0xA5,"readback guards and row padding preserved");}
        if(test.writerStop) {auto* values=static_cast<const uint32_t*>(written.bytes);for(uint32_t i=0;i<16;++i)require(values[i]==(i>=1&&i<=(test.indirectBatch?12u:3u)?0xA1100000+i:0),"prior shader stores execute and preserve other slots");}
        if(queries) {uint64_t q[4]={};VK_CHECK(vkGetQueryPoolResults(c.device,queries,0,2,sizeof(q),q,16,VK_QUERY_RESULT_64_BIT|VK_QUERY_RESULT_WITH_AVAILABILITY_BIT));require(q[1]&&q[3]&&q[0]>0&&q[2]>0,"query-boundary draws produce available samples");if(c.preciseOcclusionSupported)require(q[0]==q[2],"query count equals explicit primitive oracle across conversions");}
    };
    submitRecorded(c,command,producer);verify(false);
    if(test.resubmit) {
        // Same recorded command buffer and same buffer identity, different
        // coherent input contents after fence completion: no cross-submit cache.
        if(!test.priorProducer){if(test.batchRestart){batchWrite(0,2+batchStart(0),1);batchWrite(0,3+batchStart(0),2);batchWrite(0,4+batchStart(0),0);}else{ix[9]=1;ix[10]=2;ix[11]=0;}auto* ref=static_cast<uint32_t*>(oracleIndices.bytes);ref[0]=0;ref[1]=1;ref[2]=2;}
        else {std::memset(vertices.bytes,0,vertices.size);std::memset(indices.bytes,0,indices.size);std::memset(oracleIndices.bytes,0,oracleIndices.size);if(usePush){std::memset(uniforms.bytes,0,uniforms.size);std::memset(readStorage.bytes,0,readStorage.size);}}
        std::memset(output.bytes,0xA5,output.size);submitRecorded(c,command,producer);verify(!test.priorProducer);
    }
}
} // namespace

int main(int argc,char** argv) {
    setenv("MVK_CONFIG_USE_METAL4","1",1);setenv("MVK_CONFIG_USE_METAL_PRIVATE_API","1",1);setenv("MVK_CONFIG_METAL4_STATS","1",1);
    @autoreleasepool {
        std::vector<PrepassCase> cases={{"independent_draw_state_snapshots"},{"coherent_index_rewrite_same_command_buffer",true},
            {"occlusion_query_boundary",false,true},{"render_self_dependency_barrier_boundary",false,false,true},
            {"prior_shader_write_stops_lookahead",false,false,false,true},{"same_memory_image_index_nonoverlap_excluded",false,false,false,false,true},
            {"dedicated_aliasable_image_excluded",false,false,false,false,false,true},
            {"push_descriptor_readonly_buffers",false,false,false,false,false,false,1},
            {"push_template_readonly_buffers",false,false,false,false,false,false,2},
            {"dynamic_sample_locations_4x_enable_disable_resolve",false,false,false,false,false,false,0,true},
            {"indirect_batch_gpu_records_restart_drawid_query",false,true,false,false,false,false,0,false,true},
            {"indirect_batch_shader_write_rejected",false,true,false,true,false,false,0,false,true},
            {"indirect_batch_index_attachment_allocation_rejected",false,true,false,false,true,false,0,false,true},
            {"indirect_batch_argument_attachment_allocation_rejected",false,true,false,false,false,false,0,false,true,true},
            {"indirect_batch_dedicated_alias_attachment_rejected",false,true,false,false,false,true,0,false,true}};
        auto leading=[&](const char* name,bool producer,bool msaa,bool query,bool selfBarrier,bool locations,bool repeat) {
            PrepassCase t{name};t.leadingOrdinary=true;t.priorProducer=producer;t.handoffMSAA=msaa;t.pushKind=producer?1:0;
            t.queryStop=query;t.barrierStop=selfBarrier;t.sampleLocations=locations;t.resubmit=repeat;cases.push_back(t);
        };
        leading("leading_ordinary_prior_command_buffer_resources",true,false,false,false,false,true);
        leading("leading_ordinary_msaa4_depth_load_resolve",true,true,false,false,false,false);
        leading("leading_ordinary_sample_location_restart",false,false,false,false,true,false);
        leading("leading_ordinary_query_boundary",false,false,true,false,false,false);
        leading("leading_ordinary_barrier_boundary",false,false,false,true,false,false);
        PrepassCase zero{"zero_count_ordinary_prefix_not_handoff"};zero.zeroOrdinary=true;cases.push_back(zero);
        PrepassCase vertexBarrier{"vertex_store_to_vertex_read_same_render_pass"};vertexBarrier.vertexDependency=true;cases.push_back(vertexBarrier);
        auto batched=[&](const char* name,uint32_t kind,bool repeat,bool producer,bool query,bool writer,bool alias) {
            PrepassCase t{name};t.batchRestart=kind;t.resubmit=repeat;t.priorProducer=producer;t.leadingOrdinary=producer;
            t.pushKind=producer?1:0;t.queryStop=query;t.writerStop=writer;t.sameAllocation=alias;cases.push_back(t);
        };
        batched("batched_restart_mixed_u16_u32_sentinels_offset_snapshot_rewrite",1,true,false,false,false,false);
        batched("batched_restart_partial_simd_width31",2,false,false,false,false,false);
        batched("batched_restart_width_changes_split_groups",3,false,false,false,false,false);
        batched("batched_restart_prior_producer_ordinary_prefix_handoff",1,true,true,false,false,false);
        batched("batched_restart_query_boundary",1,false,false,true,false,false);
        batched("batched_restart_shader_write_exclusion",1,false,false,false,true,false);
        batched("batched_restart_shared_attachment_allocation_exclusion",1,false,false,false,false,true);
        NSMutableArray* results=[NSMutableArray array];unsigned failures=0;const char* prepass=std::getenv("MVK_CONFIG_METAL4_PREPASS");
        for(const auto& test:cases) {
            if(argc>1 && std::strcmp(argv[1],test.name))continue;
            std::fprintf(stderr,"[prepass-case] BEGIN %s prepass=%s\n",test.name,prepass?prepass:"default");
            Context c;
            try {initializePrepassContext(c);prepassCase(c,test);
                [results addObject:@{@"name":[NSString stringWithUTF8String:test.name],@"passed":@YES,@"native_queue":@(c.isNative(c.queue)),@"uses_argument_buffers":@(c.usesArgumentBuffers(c.queue)),@"completed_before":@(c.nativeBefore),@"completed_after":@(c.nativeAfter)}];
            } catch(const std::exception& e) {++failures;[results addObject:@{@"name":[NSString stringWithUTF8String:test.name],@"passed":@NO,@"error":[NSString stringWithUTF8String:e.what()]}];}
            std::fprintf(stderr,"[prepass-case] END %s\n",test.name);if(failures)break;
        }
        if(!results.count)++failures;
        NSDictionary* report=@{@"suite":@"metal4_vulkan_prepass",@"bar_acceptance":@NO,@"test_count":@(results.count),@"passed":@(results.count-(failures&&results.count?1:0)),@"failed":@(failures),@"tests":results};
        NSData* json=[NSJSONSerialization dataWithJSONObject:report options:0 error:nil];std::fwrite(json.bytes,1,json.length,stdout);std::fputc('\n',stdout);return failures?1:0;
    }
}
