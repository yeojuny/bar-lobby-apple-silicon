// Offscreen Vulkan -> MoltenVK -> native Metal 4 integration. This links the
// candidate MoltenVK dylib directly; no loader selection, window, or game launch.
// Small SPIR-V fixtures below use the checked-in official opcode definitions;
// they require no shader compiler, external executable, or network dependency.
#import <Foundation/Foundation.h>
#include <vulkan/vulkan.h>
#include <spirv/unified1/spirv.hpp>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <functional>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}
void check(VkResult result, const char* operation) {
    require(result == VK_SUCCESS, std::string(operation) + " returned " + std::to_string(result));
}
#define VK_CHECK(call) check((call), #call)

struct Spirv {
    std::vector<uint32_t> words{spv::MagicNumber, 0x00010300, 0, 128, 0};
    void op(spv::Op opcode, std::initializer_list<uint32_t> operands) {
        words.push_back(uint32_t((operands.size() + 1) << 16) | uint32_t(opcode));
        words.insert(words.end(), operands.begin(), operands.end());
    }
    void entry(spv::ExecutionModel model, uint32_t function, std::initializer_list<uint32_t> interfaces) {
        // "main\0" occupies two little-endian SPIR-V words.
        words.push_back(uint32_t((5 + interfaces.size()) << 16) | uint32_t(spv::OpEntryPoint));
        words.push_back(model); words.push_back(function); words.push_back(0x6E69616D); words.push_back(0);
        words.insert(words.end(), interfaces.begin(), interfaces.end());
    }
    void header() {
        op(spv::OpCapability, {spv::CapabilityShader});
        op(spv::OpMemoryModel, {spv::AddressingModelLogical, spv::MemoryModelGLSL450});
    }
};

std::vector<uint32_t> computeShader(unsigned readMode = 0, bool splitParams = false) {
    // GLSL equivalent:
    // layout(local_size_x=1) in;
    // layout(set=0,binding=0,std430) buffer Out { uint value[]; } outData;
    // layout(set=0,binding=1) uniform Params { uint add; } params;
    // layout(push_constant) uniform Push { uint multiply; } push;
    // void main(){uint i=gl_GlobalInvocationID.x; outData.value[i]=i*push.multiply+params.add;}
    Spirv s; s.header();
    s.entry(spv::ExecutionModelGLCompute, 40, {20});
    s.op(spv::OpExecutionMode, {40, spv::ExecutionModeLocalSize, 1, 1, 1});
    s.op(spv::OpDecorate, {20, spv::DecorationBuiltIn, spv::BuiltInGlobalInvocationId});
    s.op(spv::OpDecorate, {6, spv::DecorationArrayStride, 4});
    for (uint32_t block : {7u, 10u, 13u}) {
        s.op(spv::OpDecorate, {block, spv::DecorationBlock});
        s.op(spv::OpMemberDecorate, {block, 0, spv::DecorationOffset, 0});
    }
    s.op(spv::OpDecorate, {21, spv::DecorationDescriptorSet, 0});
    s.op(spv::OpDecorate, {21, spv::DecorationBinding, 0});
    s.op(spv::OpDecorate, {22, spv::DecorationDescriptorSet, splitParams ? 1u : 0u});
    s.op(spv::OpDecorate, {22, spv::DecorationBinding, splitParams ? 0u : 1u});
    if (readMode == 2) {
        s.op(spv::OpDecorate, {24, spv::DecorationDescriptorSet, 0});
        s.op(spv::OpDecorate, {24, spv::DecorationBinding, 2});
    }
    s.op(spv::OpTypeVoid, {1}); s.op(spv::OpTypeFunction, {2, 1});
    s.op(spv::OpTypeInt, {3, 32, 0}); s.op(spv::OpTypeVector, {4, 3, 3});
    s.op(spv::OpTypePointer, {5, spv::StorageClassInput, 4});
    s.op(spv::OpTypeRuntimeArray, {6, 3}); s.op(spv::OpTypeStruct, {7, 6});
    s.op(spv::OpTypePointer, {8, spv::StorageClassStorageBuffer, 7});
    s.op(spv::OpTypePointer, {9, spv::StorageClassStorageBuffer, 3});
    s.op(spv::OpTypeStruct, {10, 3}); s.op(spv::OpTypePointer, {11, spv::StorageClassUniform, 10});
    s.op(spv::OpTypePointer, {12, spv::StorageClassUniform, 3});
    s.op(spv::OpTypeStruct, {13, 3}); s.op(spv::OpTypePointer, {14, spv::StorageClassPushConstant, 13});
    s.op(spv::OpTypePointer, {15, spv::StorageClassPushConstant, 3});
    s.op(spv::OpConstant, {3, 16, 0});
    s.op(spv::OpVariable, {5, 20, spv::StorageClassInput});
    s.op(spv::OpVariable, {8, 21, spv::StorageClassStorageBuffer});
    s.op(spv::OpVariable, {11, 22, spv::StorageClassUniform});
    s.op(spv::OpVariable, {14, 23, spv::StorageClassPushConstant});
    if (readMode == 2) { s.op(spv::OpVariable, {8, 24, spv::StorageClassStorageBuffer}); }
    s.op(spv::OpFunction, {1, 40, spv::FunctionControlMaskNone, 2}); s.op(spv::OpLabel, {41});
    s.op(spv::OpLoad, {4, 42, 20}); s.op(spv::OpCompositeExtract, {3, 43, 42, 0});
    s.op(spv::OpAccessChain, {15, 44, 23, 16}); s.op(spv::OpLoad, {3, 45, 44});
    s.op(spv::OpAccessChain, {12, 46, 22, 16}); s.op(spv::OpLoad, {3, 47, 46});
    s.op(spv::OpIMul, {3, 48, 43, 45}); s.op(spv::OpIAdd, {3, 49, 48, 47});
    s.op(spv::OpAccessChain, {9, 50, 21, 16, 43});
    if (readMode) {
        s.op(spv::OpLoad, {3, 51, 50}); s.op(spv::OpIAdd, {3, 52, 51, 49});
        if (readMode == 2) {
            s.op(spv::OpAccessChain, {9, 53, 24, 16, 43}); s.op(spv::OpStore, {53, 52});
        } else { s.op(spv::OpStore, {50, 52}); }
    } else { s.op(spv::OpStore, {50, 49}); }
    s.op(spv::OpReturn, {}); s.op(spv::OpFunctionEnd, {});
    return s.words;
}

std::vector<uint32_t> vertexShader() {
    // layout(location=0) in vec2 xy; gl_Position=vec4(xy,0,1);
    Spirv s; s.header(); s.entry(spv::ExecutionModelVertex, 30, {20, 21});
    s.op(spv::OpDecorate, {20, spv::DecorationLocation, 0});
    s.op(spv::OpDecorate, {7, spv::DecorationBlock});
    s.op(spv::OpMemberDecorate, {7, 0, spv::DecorationBuiltIn, spv::BuiltInPosition});
    s.op(spv::OpTypeVoid, {1}); s.op(spv::OpTypeFunction, {2, 1});
    s.op(spv::OpTypeFloat, {3, 32}); s.op(spv::OpTypeVector, {4, 3, 2}); s.op(spv::OpTypeVector, {5, 3, 4});
    s.op(spv::OpTypePointer, {6, spv::StorageClassInput, 4}); s.op(spv::OpTypeStruct, {7, 5});
    s.op(spv::OpTypePointer, {8, spv::StorageClassOutput, 7}); s.op(spv::OpTypePointer, {9, spv::StorageClassOutput, 5});
    s.op(spv::OpTypeInt, {10, 32, 0}); s.op(spv::OpConstant, {10, 11, 0});
    s.op(spv::OpConstant, {3, 12, 0}); s.op(spv::OpConstant, {3, 13, 0x3F800000});
    s.op(spv::OpVariable, {6, 20, spv::StorageClassInput}); s.op(spv::OpVariable, {8, 21, spv::StorageClassOutput});
    s.op(spv::OpFunction, {1, 30, spv::FunctionControlMaskNone, 2}); s.op(spv::OpLabel, {31});
    s.op(spv::OpLoad, {4, 32, 20}); s.op(spv::OpCompositeExtract, {3, 33, 32, 0}); s.op(spv::OpCompositeExtract, {3, 34, 32, 1});
    s.op(spv::OpCompositeConstruct, {5, 35, 33, 34, 12, 13}); s.op(spv::OpAccessChain, {9, 36, 21, 11}); s.op(spv::OpStore, {36, 35});
    s.op(spv::OpReturn, {}); s.op(spv::OpFunctionEnd, {}); return s.words;
}

std::vector<uint32_t> fragmentShader(bool uniformColor = false) {
    // layout(location=0) out vec4 color; color=vec4(.25,.5,.75,1);
    Spirv s; s.header(); s.entry(spv::ExecutionModelFragment, 30, {20});
    s.op(spv::OpExecutionMode, {30, spv::ExecutionModeOriginUpperLeft});
    s.op(spv::OpDecorate, {20, spv::DecorationLocation, 0});
    if (uniformColor) {
        s.op(spv::OpDecorate, {14, spv::DecorationBlock});
        s.op(spv::OpMemberDecorate, {14, 0, spv::DecorationOffset, 0});
        s.op(spv::OpDecorate, {21, spv::DecorationDescriptorSet, 0});
        s.op(spv::OpDecorate, {21, spv::DecorationBinding, 0});
    }
    s.op(spv::OpTypeVoid, {1}); s.op(spv::OpTypeFunction, {2, 1}); s.op(spv::OpTypeFloat, {3, 32});
    s.op(spv::OpTypeVector, {4, 3, 4}); s.op(spv::OpTypePointer, {5, spv::StorageClassOutput, 4});
    s.op(spv::OpConstant, {3, 6, 0x3E800000}); s.op(spv::OpConstant, {3, 7, 0x3F000000});
    s.op(spv::OpConstant, {3, 8, 0x3F400000}); s.op(spv::OpConstant, {3, 9, 0x3F800000});
    s.op(spv::OpConstantComposite, {4, 10, 6, 7, 8, 9}); s.op(spv::OpVariable, {5, 20, spv::StorageClassOutput});
    if (uniformColor) {
        s.op(spv::OpTypeInt, {11, 32, 0}); s.op(spv::OpConstant, {11, 12, 0});
        s.op(spv::OpTypePointer, {13, spv::StorageClassUniform, 4});
        s.op(spv::OpTypeStruct, {14, 4}); s.op(spv::OpTypePointer, {15, spv::StorageClassUniform, 14});
        s.op(spv::OpVariable, {15, 21, spv::StorageClassUniform});
    }
    s.op(spv::OpFunction, {1, 30, spv::FunctionControlMaskNone, 2}); s.op(spv::OpLabel, {31});
    if (uniformColor) {
        s.op(spv::OpAccessChain, {13, 32, 21, 12}); s.op(spv::OpLoad, {4, 33, 32});
        s.op(spv::OpStore, {20, 33});
    } else { s.op(spv::OpStore, {20, 10}); }
    s.op(spv::OpReturn, {}); s.op(spv::OpFunctionEnd, {}); return s.words;
}

std::vector<uint32_t> sampledFragmentShader() {
    // layout(set=0,binding=0) uniform sampler2D image;
    // color=textureLod(image,vec2(1.25,.25),0); repeat must select texel(0,0).
    Spirv s; s.header(); s.entry(spv::ExecutionModelFragment, 30, {20});
    s.op(spv::OpExecutionMode, {30, spv::ExecutionModeOriginUpperLeft});
    s.op(spv::OpDecorate, {20, spv::DecorationLocation, 0});
    s.op(spv::OpDecorate, {21, spv::DecorationDescriptorSet, 0}); s.op(spv::OpDecorate, {21, spv::DecorationBinding, 0});
    s.op(spv::OpTypeVoid, {1}); s.op(spv::OpTypeFunction, {2, 1}); s.op(spv::OpTypeFloat, {3, 32});
    s.op(spv::OpTypeVector, {4, 3, 4}); s.op(spv::OpTypePointer, {5, spv::StorageClassOutput, 4});
    s.op(spv::OpTypeVector, {6, 3, 2});
    s.op(spv::OpTypeImage, {7, 3, spv::Dim2D, 0, 0, 0, 1, spv::ImageFormatUnknown});
    s.op(spv::OpTypeSampledImage, {8, 7}); s.op(spv::OpTypePointer, {9, spv::StorageClassUniformConstant, 8});
    s.op(spv::OpConstant, {3, 10, 0x3FA00000}); s.op(spv::OpConstant, {3, 11, 0x3E800000}); s.op(spv::OpConstant, {3, 12, 0});
    s.op(spv::OpConstantComposite, {6, 13, 10, 11});
    s.op(spv::OpVariable, {5, 20, spv::StorageClassOutput}); s.op(spv::OpVariable, {9, 21, spv::StorageClassUniformConstant});
    s.op(spv::OpFunction, {1, 30, spv::FunctionControlMaskNone, 2}); s.op(spv::OpLabel, {31});
    s.op(spv::OpLoad, {8, 32, 21}); s.op(spv::OpImageSampleExplicitLod, {4, 33, 32, 13, spv::ImageOperandsLodMask, 12});
    s.op(spv::OpStore, {20, 33}); s.op(spv::OpReturn, {}); s.op(spv::OpFunctionEnd, {}); return s.words;
}

struct Buffer { VkBuffer buffer; VkDeviceMemory memory; void* bytes; VkDeviceSize size; };
struct Image { VkImage image; VkImageView view; };
struct Context {
    VkInstance instance = VK_NULL_HANDLE;
    VkPhysicalDevice physical = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    VkQueue queue = VK_NULL_HANDLE;
    VkQueue secondQueue = VK_NULL_HANDLE;
    VkCommandPool pool = VK_NULL_HANDLE;
    VkCommandPool secondPool = VK_NULL_HANDLE;
    VkPhysicalDeviceProperties properties{};
    uint32_t family = 0;
    uint32_t secondFamily = 0;
    bool timelineSupported = false;
    bool hostQueryResetSupported = false;
    bool preciseOcclusionSupported = false;
    bool multiDrawIndirectSupported = false;
    uint32_t timestampValidBits = 0;
    PFN_vkGetCalibratedTimestampsEXT calibratedTimestamps = nullptr;
    bool inFlight = false;
    bool oneTime = false;
    std::vector<std::function<void()>> cleanup;
    using IsNative = bool (*)(VkQueue);
    using Counter = uint64_t (*)(VkQueue);
    IsNative isNative = nullptr;
    IsNative usesArgumentBuffers = nullptr;
    Counter counter = nullptr;
    uint64_t nativeBefore = 0, nativeAfter = 0;
    bool nativeExpected = true;

    ~Context() {
        // A failed bounded fence wait must not destroy resources the GPU may
        // still use. The harness reports failure and the process then exits.
        if (inFlight) return;
        for (auto i = cleanup.rbegin(); i != cleanup.rend(); ++i) (*i)();
        if (pool) vkDestroyCommandPool(device, pool, nullptr);
        if (secondPool) vkDestroyCommandPool(device, secondPool, nullptr);
        if (device) vkDestroyDevice(device, nullptr);
        if (instance) vkDestroyInstance(instance, nullptr);
    }
    void initialize(bool requirePushDescriptors = false, bool expectNative = true) {
        nativeExpected = expectNative;
        isNative = reinterpret_cast<IsNative>(dlsym(RTLD_DEFAULT, "mvkIsMetal4Queue"));
        counter = reinterpret_cast<Counter>(dlsym(RTLD_DEFAULT, "mvkGetMetal4QueueCompletedSubmissionCount"));
        usesArgumentBuffers = reinterpret_cast<IsNative>(dlsym(RTLD_DEFAULT, "mvkIsMetal4QueueUsingArgumentBuffers"));
        require(isNative && counter && usesArgumentBuffers, "candidate must export native queue and binding-mode proof functions");
        uint32_t extensionCount = 0;
        VK_CHECK(vkEnumerateInstanceExtensionProperties(nullptr, &extensionCount, nullptr));
        std::vector<VkExtensionProperties> extensions(extensionCount);
        VK_CHECK(vkEnumerateInstanceExtensionProperties(nullptr, &extensionCount, extensions.data()));
        bool portability = std::any_of(extensions.begin(), extensions.end(), [](auto& e) {
            return std::strcmp(e.extensionName, VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME) == 0;
        });
        const char* instanceExtension = VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME;
        VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO};
        app.pApplicationName = "MVK native Metal 4 Vulkan regression"; app.apiVersion = VK_API_VERSION_1_2;
        VkInstanceCreateInfo instanceInfo{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
        instanceInfo.pApplicationInfo = &app;
        if (portability) { instanceInfo.flags = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
            instanceInfo.enabledExtensionCount = 1; instanceInfo.ppEnabledExtensionNames = &instanceExtension; }
        VK_CHECK(vkCreateInstance(&instanceInfo, nullptr, &instance));
        uint32_t count = 0; VK_CHECK(vkEnumeratePhysicalDevices(instance, &count, nullptr));
        require(count != 0, "Vulkan physical device available");
        std::vector<VkPhysicalDevice> devices(count); VK_CHECK(vkEnumeratePhysicalDevices(instance, &count, devices.data()));
        physical = devices[0]; vkGetPhysicalDeviceProperties(physical, &properties);
        vkGetPhysicalDeviceQueueFamilyProperties(physical, &count, nullptr);
        std::vector<VkQueueFamilyProperties> families(count); vkGetPhysicalDeviceQueueFamilyProperties(physical, &count, families.data());
        bool found = false;
        for (uint32_t i = 0; i < count; ++i) if ((families[i].queueFlags & (VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_COMPUTE_BIT)) ==
            (VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_COMPUTE_BIT)) { family = i; found = true; break; }
        require(found, "graphics and compute queue family available");
        timestampValidBits = families[family].timestampValidBits;
        secondFamily = family;
        bool hasSecond = families[family].queueCount >= 2;
        if (!hasSecond) for (uint32_t i = 0; i < families.size(); ++i) {
            if (i != family && families[i].queueCount && (families[i].queueFlags & VK_QUEUE_TRANSFER_BIT)) {
                secondFamily = i; hasSecond = true; break;
            }
        }
        float priorities[2] = {1, 1};
        VkDeviceQueueCreateInfo queueInfos[2]{};
        queueInfos[0].sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        queueInfos[0].queueFamilyIndex = family;
        queueInfos[0].queueCount = hasSecond && secondFamily == family ? 2 : 1;
        queueInfos[0].pQueuePriorities = priorities;
        queueInfos[1] = queueInfos[0]; queueInfos[1].queueFamilyIndex = secondFamily; queueInfos[1].queueCount = 1;
        VkPhysicalDeviceTimelineSemaphoreFeatures timeline{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES};
        VkPhysicalDeviceHostQueryResetFeatures hostQueryReset{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_HOST_QUERY_RESET_FEATURES};
        timeline.pNext = &hostQueryReset;
        VkPhysicalDeviceFeatures2 features{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2}; features.pNext = &timeline;
        vkGetPhysicalDeviceFeatures2(physical, &features); timelineSupported = timeline.timelineSemaphore;
        hostQueryResetSupported = hostQueryReset.hostQueryReset;
        preciseOcclusionSupported = features.features.occlusionQueryPrecise;
        multiDrawIndirectSupported = features.features.multiDrawIndirect;
        VK_CHECK(vkEnumerateDeviceExtensionProperties(physical, nullptr, &count, nullptr));
        extensions.resize(count); VK_CHECK(vkEnumerateDeviceExtensionProperties(physical, nullptr, &count, extensions.data()));
        const char* subset = "VK_KHR_portability_subset";
        bool hasSubset = std::any_of(extensions.begin(), extensions.end(), [&](auto& e) { return std::strcmp(e.extensionName, subset) == 0; });
        VkDeviceCreateInfo deviceInfo{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
        deviceInfo.queueCreateInfoCount = hasSecond && secondFamily != family ? 2 : 1;
        deviceInfo.pQueueCreateInfos = queueInfos; deviceInfo.pNext = &timeline;
        VkPhysicalDeviceFeatures enabledFeatures{};
        enabledFeatures.occlusionQueryPrecise = preciseOcclusionSupported;
        enabledFeatures.multiDrawIndirect = multiDrawIndirectSupported;
        deviceInfo.pEnabledFeatures = &enabledFeatures;
        std::vector<const char*> deviceExtensions;
        if (hasSubset) deviceExtensions.push_back(subset);
        bool hasCalibrated = std::any_of(extensions.begin(), extensions.end(), [](auto& e) {
            return std::strcmp(e.extensionName, VK_EXT_CALIBRATED_TIMESTAMPS_EXTENSION_NAME) == 0;
        });
        if (hasCalibrated) deviceExtensions.push_back(VK_EXT_CALIBRATED_TIMESTAMPS_EXTENSION_NAME);
        if (requirePushDescriptors) {
            require(std::any_of(extensions.begin(), extensions.end(), [](auto& e) {
                return std::strcmp(e.extensionName, VK_KHR_PUSH_DESCRIPTOR_EXTENSION_NAME) == 0;
            }), "push descriptor extension available for template capture regression");
            deviceExtensions.push_back(VK_KHR_PUSH_DESCRIPTOR_EXTENSION_NAME);
        }
        deviceInfo.enabledExtensionCount = uint32_t(deviceExtensions.size());
        deviceInfo.ppEnabledExtensionNames = deviceExtensions.data();
        VK_CHECK(vkCreateDevice(physical, &deviceInfo, nullptr, &device));
        if (hasCalibrated) calibratedTimestamps = reinterpret_cast<PFN_vkGetCalibratedTimestampsEXT>(vkGetDeviceProcAddr(device, "vkGetCalibratedTimestampsEXT"));
        vkGetDeviceQueue(device, family, 0, &queue);
        require(isNative(queue) == nativeExpected, "actual Vulkan backend must match the explicit expectation");
        const char* requestedArgumentBuffers = std::getenv("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS");
        require(requestedArgumentBuffers && (std::strcmp(requestedArgumentBuffers, "0") == 0 || std::strcmp(requestedArgumentBuffers, "1") == 0),
                "set MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS explicitly to 0 or 1 for binding-mode proof");
        if (nativeExpected) require(usesArgumentBuffers(queue) == (requestedArgumentBuffers[0] == '1'), "actual native argument-buffer selection must match the requested mode");
        if (hasSecond) { vkGetDeviceQueue(device, secondFamily, secondFamily == family ? 1 : 0, &secondQueue);
            require(isNative(secondQueue) == nativeExpected, "second Vulkan queue must match the explicit backend"); }
        nativeBefore = counter(queue);
        VkCommandPoolCreateInfo poolInfo{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO}; poolInfo.queueFamilyIndex = family;
        poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
        VK_CHECK(vkCreateCommandPool(device, &poolInfo, nullptr, &pool));
        if (hasSecond) { poolInfo.queueFamilyIndex = secondFamily; VK_CHECK(vkCreateCommandPool(device, &poolInfo, nullptr, &secondPool)); }
    }
    uint32_t memoryType(uint32_t bits, VkMemoryPropertyFlags flags) {
        VkPhysicalDeviceMemoryProperties memory{}; vkGetPhysicalDeviceMemoryProperties(physical, &memory);
        for (uint32_t i = 0; i < memory.memoryTypeCount; ++i)
            if ((bits & (1u << i)) && (memory.memoryTypes[i].propertyFlags & flags) == flags) return i;
        throw std::runtime_error("required memory type unavailable");
    }
    Buffer buffer(VkDeviceSize size, VkBufferUsageFlags usage, bool host = true) {
        Buffer b{}; b.size = size;
        VkBufferCreateInfo info{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO}; info.size = size; info.usage = usage;
        uint32_t sharingFamilies[2] = {family, secondFamily};
        if (secondQueue && secondFamily != family) { info.sharingMode = VK_SHARING_MODE_CONCURRENT;
            info.queueFamilyIndexCount = 2; info.pQueueFamilyIndices = sharingFamilies; }
        VK_CHECK(vkCreateBuffer(device, &info, nullptr, &b.buffer));
        VkMemoryRequirements requirements{}; vkGetBufferMemoryRequirements(device, b.buffer, &requirements);
        VkMemoryAllocateInfo allocation{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO}; allocation.allocationSize = requirements.size;
        allocation.memoryTypeIndex = memoryType(requirements.memoryTypeBits, host ?
            VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT : VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
        VK_CHECK(vkAllocateMemory(device, &allocation, nullptr, &b.memory));
        VK_CHECK(vkBindBufferMemory(device, b.buffer, b.memory, 0));
        if (host) VK_CHECK(vkMapMemory(device, b.memory, 0, VK_WHOLE_SIZE, 0, &b.bytes));
        cleanup.push_back([=] { if (host) vkUnmapMemory(device, b.memory); vkDestroyBuffer(device, b.buffer, nullptr); vkFreeMemory(device, b.memory, nullptr); });
        return b;
    }
    Image image(uint32_t width, uint32_t height, VkFormat format, VkImageUsageFlags usage,
                VkSampleCountFlagBits samples = VK_SAMPLE_COUNT_1_BIT, VkImageAspectFlags aspect = VK_IMAGE_ASPECT_COLOR_BIT,
                uint32_t mipLevels = 1) {
        Image out{};
        VkImageCreateInfo info{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO}; info.imageType = VK_IMAGE_TYPE_2D;
        info.format = format; info.extent = {width, height, 1}; info.mipLevels = mipLevels; info.arrayLayers = 1;
        info.samples = samples; info.tiling = VK_IMAGE_TILING_OPTIMAL; info.usage = usage;
        VK_CHECK(vkCreateImage(device, &info, nullptr, &out.image));
        VkMemoryRequirements requirements{}; vkGetImageMemoryRequirements(device, out.image, &requirements);
        VkMemoryAllocateInfo allocation{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO}; allocation.allocationSize = requirements.size;
        allocation.memoryTypeIndex = memoryType(requirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
        VkDeviceMemory memory; VK_CHECK(vkAllocateMemory(device, &allocation, nullptr, &memory));
        VK_CHECK(vkBindImageMemory(device, out.image, memory, 0));
        VkImage image = out.image;
        cleanup.push_back([=] { vkDestroyImage(device, image, nullptr); vkFreeMemory(device, memory, nullptr); });
        VkImageViewCreateInfo viewInfo{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO}; viewInfo.image = image; viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
        viewInfo.format = format; viewInfo.subresourceRange = {aspect, 0, 1, 0, 1};
        VK_CHECK(vkCreateImageView(device, &viewInfo, nullptr, &out.view));
        VkImageView view = out.view; cleanup.push_back([=] { vkDestroyImageView(device, view, nullptr); });
        return out;
    }
    VkCommandBuffer begin(bool second = false) {
        VkCommandBuffer command;
        VkCommandBufferAllocateInfo info{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO}; info.commandPool = second ? secondPool : pool;
        info.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY; info.commandBufferCount = 1;
        VK_CHECK(vkAllocateCommandBuffers(device, &info, &command));
        VkCommandBufferBeginInfo beginInfo{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
        beginInfo.flags = oneTime ? VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT : 0;
        VK_CHECK(vkBeginCommandBuffer(command, &beginInfo)); return command;
    }
    void submit(VkCommandBuffer command = VK_NULL_HANDLE, bool endRecording = true) {
        if (command && endRecording) VK_CHECK(vkEndCommandBuffer(command));
        VkFenceCreateInfo fenceInfo{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO}; VkFence fence;
        VK_CHECK(vkCreateFence(device, &fenceInfo, nullptr, &fence));
        VkSubmitInfo submitInfo{VK_STRUCTURE_TYPE_SUBMIT_INFO};
        submitInfo.commandBufferCount = command ? 1 : 0; submitInfo.pCommandBuffers = command ? &command : nullptr;
        inFlight = true;
        VK_CHECK(vkQueueSubmit(queue, 1, &submitInfo, fence));
        VK_CHECK(vkWaitForFences(device, 1, &fence, VK_TRUE, 10000000000ull));
        VK_CHECK(vkQueueWaitIdle(queue));
        inFlight = false;
        vkDestroyFence(device, fence, nullptr);
        nativeAfter = counter(queue);
        if (nativeExpected) require(nativeAfter > nativeBefore, "actual native completion counter must advance");
        else require(!isNative(queue), "completed common case must remain on legacy Metal");
    }
    VkShaderModule shader(const std::vector<uint32_t>& code) {
        VkShaderModule module;
        VkShaderModuleCreateInfo info{VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO}; info.codeSize = code.size() * 4; info.pCode = code.data();
        VK_CHECK(vkCreateShaderModule(device, &info, nullptr, &module));
        cleanup.push_back([=] { vkDestroyShaderModule(device, module, nullptr); }); return module;
    }
};

void barrier(VkCommandBuffer command, VkPipelineStageFlags source, VkAccessFlags sourceAccess,
             VkPipelineStageFlags target, VkAccessFlags targetAccess) {
    VkMemoryBarrier memory{VK_STRUCTURE_TYPE_MEMORY_BARRIER}; memory.srcAccessMask = sourceAccess; memory.dstAccessMask = targetAccess;
    vkCmdPipelineBarrier(command, source, target, 0, 1, &memory, 0, nullptr, 0, nullptr);
}

void asyncSingleUseCommandPoolHandoff(Context& c) {
    c.oneTime = true;
    constexpr unsigned n = 192;
    auto output = c.buffer(n * 4, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    std::memset(output.bytes, 0, n * 4);
    for (unsigned i = 0; i < n; ++i) {
        auto command = c.begin();vkCmdFillBuffer(command, output.buffer, i * 4, 4, 0xABCD0000 + i);
        barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
        VK_CHECK(vkEndCommandBuffer(command));
        VkSubmitInfo submit{VK_STRUCTURE_TYPE_SUBMIT_INFO};submit.commandBufferCount = 1;submit.pCommandBuffers = &command;
        c.inFlight = true;VK_CHECK(vkQueueSubmit(c.queue, 1, &submit, VK_NULL_HANDLE));
    }
    VK_CHECK(vkQueueWaitIdle(c.queue));c.inFlight = false;
    for (unsigned i = 0; i < n; ++i) require(static_cast<uint32_t*>(output.bytes)[i] == 0xABCD0000 + i, "async-recorded fills retain independent contents/lifetime");
    c.nativeAfter = c.counter(c.queue);
    require(c.nativeAfter == c.nativeBefore + n, "every async submission retires exactly once");
}

void transfer(Context& c) {
    constexpr uint32_t words = 1024, guard = 16;
    auto middle = c.buffer(words * 4, VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, false);
    auto output = c.buffer(words * 4, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    std::memset(output.bytes, 0xA5, words * 4);
    VkCommandBuffer command = c.begin();
    vkCmdFillBuffer(command, middle.buffer, 0, VK_WHOLE_SIZE, 0x1A2B3C4D);
    barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT);
    uint32_t patch[5] = {9, 0xFFFFFFFF, 0, 0xCAFEBABE, 37};
    vkCmdUpdateBuffer(command, middle.buffer, guard * 4, sizeof(patch), patch);
    barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_READ_BIT);
    VkBufferCopy copy{guard * 4, guard * 4, (words - 2 * guard) * 4};
    vkCmdCopyBuffer(command, middle.buffer, output.buffer, 1, &copy);
    barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
    c.submit(command);
    const auto* actual = static_cast<const uint32_t*>(output.bytes);
    for (uint32_t i = 0; i < words; ++i) {
        uint32_t expected = i < guard || i >= words - guard ? 0xA5A5A5A5 :
            i < guard + 5 ? patch[i - guard] : 0x1A2B3C4D;
        require(actual[i] == expected, "Vulkan transfer data/guard mismatch at " + std::to_string(i));
    }
}

void compute(Context& c, bool helperRestore = false, unsigned dependency = 0) {
    constexpr uint32_t count = 64;
    uint32_t offset = uint32_t(std::max<VkDeviceSize>(256, c.properties.limits.minStorageBufferOffsetAlignment));
    auto output = c.buffer(offset + count * 4 + 64, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    auto params = c.buffer(16, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
    std::memset(output.bytes, 0xA5, output.size); std::memset(params.bytes, 0, params.size);
    *static_cast<uint32_t*>(params.bytes) = 19;
    if (dependency == 2) {
        for (uint32_t i = 0; i < count; ++i) { static_cast<uint32_t*>(output.bytes)[offset / 4 + i] = i * 7 + 19; }
    }
    auto observed = c.buffer(count * 4 + 64, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
    std::memset(observed.bytes, 0xA5, observed.size);
    unsigned bindingCount = dependency == 2 ? 3 : 2;
    VkDescriptorSetLayoutBinding bindings[3] = {
        {0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr},
        {1, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr},
        {2, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr}};
    VkDescriptorSetLayoutCreateInfo setInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO}; setInfo.bindingCount = bindingCount; setInfo.pBindings = bindings;
    VkDescriptorSetLayout setLayout; VK_CHECK(vkCreateDescriptorSetLayout(c.device, &setInfo, nullptr, &setLayout));
    c.cleanup.push_back([&, setLayout] { vkDestroyDescriptorSetLayout(c.device, setLayout, nullptr); });
    VkPushConstantRange push{VK_SHADER_STAGE_COMPUTE_BIT, 0, 4};
    VkPipelineLayoutCreateInfo layoutInfo{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO}; layoutInfo.setLayoutCount = 1; layoutInfo.pSetLayouts = &setLayout;
    layoutInfo.pushConstantRangeCount = 1; layoutInfo.pPushConstantRanges = &push;
    VkPipelineLayout layout; VK_CHECK(vkCreatePipelineLayout(c.device, &layoutInfo, nullptr, &layout));
    c.cleanup.push_back([&, layout] { vkDestroyPipelineLayout(c.device, layout, nullptr); });
    VkComputePipelineCreateInfo pipelineInfo{VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO}; pipelineInfo.layout = layout;
    pipelineInfo.stage = {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, nullptr, 0, VK_SHADER_STAGE_COMPUTE_BIT, c.shader(computeShader()), "main", nullptr};
    VkPipeline pipeline; VK_CHECK(vkCreateComputePipelines(c.device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &pipeline));
    c.cleanup.push_back([&, pipeline] { vkDestroyPipeline(c.device, pipeline, nullptr); });
    VkPipeline reader = VK_NULL_HANDLE;
    if (dependency == 1 || dependency == 2) {
        pipelineInfo.stage.module = c.shader(computeShader(dependency));
        VK_CHECK(vkCreateComputePipelines(c.device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &reader));
        c.cleanup.push_back([&, reader] { vkDestroyPipeline(c.device, reader, nullptr); });
    }
    VkDescriptorPoolSize sizes[3] = {{VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC, 1}, {VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1}, {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1}};
    VkDescriptorPoolCreateInfo poolInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO}; poolInfo.maxSets = 1; poolInfo.poolSizeCount = bindingCount; poolInfo.pPoolSizes = sizes;
    VkDescriptorPool pool; VK_CHECK(vkCreateDescriptorPool(c.device, &poolInfo, nullptr, &pool));
    c.cleanup.push_back([&, pool] { vkDestroyDescriptorPool(c.device, pool, nullptr); });
    VkDescriptorSetAllocateInfo allocate{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO}; allocate.descriptorPool = pool; allocate.descriptorSetCount = 1; allocate.pSetLayouts = &setLayout;
    VkDescriptorSet set; VK_CHECK(vkAllocateDescriptorSets(c.device, &allocate, &set));
    VkDescriptorBufferInfo bufferInfos[3] = {{output.buffer, 0, count * 4}, {params.buffer, 0, 4}, {observed.buffer, 0, count * 4}};
    VkWriteDescriptorSet writes[3]{};
    for (unsigned i = 0; i < bindingCount; ++i) { writes[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET; writes[i].dstSet = set; writes[i].dstBinding = i;
        writes[i].descriptorCount = 1; writes[i].descriptorType = bindings[i].descriptorType; writes[i].pBufferInfo = &bufferInfos[i]; }
    vkUpdateDescriptorSets(c.device, bindingCount, writes, 0, nullptr);
    VkCommandBuffer command = c.begin();
    vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 1, &offset);
    uint32_t multiplier = 7; vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &multiplier);
    if (dependency != 2) { vkCmdDispatch(command, count, 1, 1); }
    if (dependency == 1 || dependency == 2) {
        if (dependency == 1) {
            barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT,
                    VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT);
        }
        vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, reader);
        multiplier = 3; vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &multiplier);
        vkCmdDispatch(command, count, 1, 1);
        if (dependency == 2) {
            // Reader writes a DISTINCT observed buffer. The source output is only
            // read here; its later overwrite needs execution ordering (WAR), not
            // visibility. Retain observed results to make the read observable.
            barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0);
            vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
            multiplier = 11; vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &multiplier);
            vkCmdDispatch(command, count, 1, 1);
        }
    }
    if (dependency == 3) {
        // Same recording repeats exactly owned buffers; updated push data must
        // still upload. Each changed value is followed by an unchanged dispatch,
        // exercising both invalidation and reuse through the actual Vulkan path.
        for (unsigned round = 0; round < 8; ++round) {
            barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT,
                    VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT);
            multiplier = round == 7 ? 3 : 13 + round;
            vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &multiplier);
            vkCmdDispatch(command, count, 1, 1);
            barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT,
                    VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT);
            vkCmdDispatch(command, count, 1, 1);
        }
    }
    if (helperRestore) {
        barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT);
        vkCmdFillBuffer(command, output.buffer, offset, count * 4, 0xDEADBEEF);
        barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT);
        // No vkCmdBindPipeline/DescriptorSets here: the helper must not disturb
        // the Vulkan application's persistent pipeline, descriptors, or constants.
        vkCmdDispatch(command, count, 1, 1);
    }
    barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
    c.submit(command);
    const auto* actual = static_cast<const uint32_t*>(output.bytes);
    for (uint32_t i = 0; i < output.size / 4; ++i) {
        uint32_t x = i - offset / 4;
        uint32_t value = dependency == 1 ? x * 10 + 38 : dependency == 2 ? x * 11 + 19 : dependency == 3 ? x * 3 + 19 : x * 7 + 19;
        uint32_t expected = i >= offset / 4 && i < offset / 4 + count ? value : 0xA5A5A5A5;
        require(actual[i] == expected, "Vulkan descriptor/dynamic-offset/push-constant mismatch at " + std::to_string(i));
    }
    if (dependency == 2) {
        const auto* values = static_cast<const uint32_t*>(observed.bytes);
        for (uint32_t i = 0; i < observed.size / 4; ++i) {
            require(values[i] == (i < count ? i * 10 + 38 : 0xA5A5A5A5), "execution-only WAR preserves earlier observed reads and guards");
        }
    }
    if (dependency == 3) {
        // Keep the exact descriptors across distinct native recordings before
        // replacing their resources. Push/dynamic data and fresh GPU ownership
        // must remain correct when CPU preparation survives recording retirement.
        for (unsigned recording = 0; recording < 4; ++recording) {
            // Churn unrelated native buffer membership between recordings.
            // Used descriptors remain unchanged and must acquire fresh leases.
            auto unrelated = c.buffer(256, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
            std::memset(unrelated.bytes, 0xCD, unrelated.size);
            auto releaseUnrelated = std::move(c.cleanup.back());
            c.cleanup.pop_back();
            releaseUnrelated();
            command = c.begin();
            vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
            vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 1, &offset);
            multiplier = 3; vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &multiplier);
            vkCmdDispatch(command, count, 1, 1);
            barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT,
                    VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
            c.submit(command);
            for (uint32_t i = 0; i < output.size / 4; ++i) {
                uint32_t expected = i >= offset / 4 && i < offset / 4 + count ? (i - offset / 4) * 3 + 19 : 0xA5A5A5A5;
                require(actual[i] == expected, "unchanged descriptors across native recordings preserve output/guards");
            }
        }
        auto revised = c.buffer(output.size, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
        auto revisedParams = c.buffer(16, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
        std::memset(revised.bytes, 0xA5, revised.size); std::memset(revisedParams.bytes, 0, revisedParams.size);
        *static_cast<uint32_t*>(revisedParams.bytes) = 37;
        // The exact same VkDescriptorSet handle now names different live Metal
        // buffers after the first recording completes. No set-pointer cache is valid.
        bufferInfos[0].buffer = revised.buffer; bufferInfos[1].buffer = revisedParams.buffer;
        vkUpdateDescriptorSets(c.device, bindingCount, writes, 0, nullptr);
        command = c.begin();
        vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
        vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 1, &offset);
        multiplier = 5; vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &multiplier);
        vkCmdDispatch(command, count, 1, 1);
        barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT,
                VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT);
        vkCmdDispatch(command, count, 1, 1);
        barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
        c.submit(command);
        const auto* changed = static_cast<const uint32_t*>(revised.bytes);
        for (uint32_t i = 0; i < revised.size / 4; ++i) {
            uint32_t expected = i >= offset / 4 && i < offset / 4 + count ? (i - offset / 4) * 5 + 37 : 0xA5A5A5A5;
            require(changed[i] == expected, "same descriptor handle rereads revised buffer identities and guards");
            require(actual[i] == (i >= offset / 4 && i < offset / 4 + count ? (i - offset / 4) * 3 + 19 : 0xA5A5A5A5), "revised descriptors leave previous owned buffer unchanged");
        }
    }
}

void sequentialPrimaryBindings(Context& c) {
    // More than the 16 cached primary groups formerly available per batch.
    // Every command must preserve its own table/push snapshot until GPU use.
    constexpr uint32_t commandCount = 24, wordCount = 8;
    uint32_t outStride = uint32_t(std::max<VkDeviceSize>(256, c.properties.limits.minStorageBufferOffsetAlignment));
    uint32_t paramStride = uint32_t(std::max<VkDeviceSize>(256, c.properties.limits.minUniformBufferOffsetAlignment));
    auto output = c.buffer((commandCount + 2) * outStride, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
    auto params = c.buffer(commandCount * paramStride, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
    std::memset(output.bytes, 0xA5, output.size);
    std::memset(params.bytes, 0, params.size);
    for (uint32_t i = 0; i < commandCount; ++i) {
        *reinterpret_cast<uint32_t*>(static_cast<char*>(params.bytes) + i * paramStride) = 17 + i;
    }
    VkDescriptorSetLayout layouts[2];
    VkDescriptorType types[2] = {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC};
    for (unsigned i = 0; i < 2; ++i) {
        VkDescriptorSetLayoutBinding binding{0, types[i], 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr};
        VkDescriptorSetLayoutCreateInfo info{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
        info.bindingCount = 1; info.pBindings = &binding;
        VK_CHECK(vkCreateDescriptorSetLayout(c.device, &info, nullptr, &layouts[i]));
        auto saved = layouts[i]; c.cleanup.push_back([&, saved] { vkDestroyDescriptorSetLayout(c.device, saved, nullptr); });
    }
    VkPushConstantRange push{VK_SHADER_STAGE_COMPUTE_BIT, 0, 4};
    VkPipelineLayoutCreateInfo layoutInfo{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    layoutInfo.setLayoutCount = 2; layoutInfo.pSetLayouts = layouts;
    layoutInfo.pushConstantRangeCount = 1; layoutInfo.pPushConstantRanges = &push;
    VkPipelineLayout layout; VK_CHECK(vkCreatePipelineLayout(c.device, &layoutInfo, nullptr, &layout));
    c.cleanup.push_back([&, layout] { vkDestroyPipelineLayout(c.device, layout, nullptr); });
    VkComputePipelineCreateInfo pipelineInfo{VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO}; pipelineInfo.layout = layout;
    pipelineInfo.stage = {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, nullptr, 0, VK_SHADER_STAGE_COMPUTE_BIT,
                          c.shader(computeShader(0, true)), "main", nullptr};
    VkPipeline pipeline; VK_CHECK(vkCreateComputePipelines(c.device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &pipeline));
    c.cleanup.push_back([&, pipeline] { vkDestroyPipeline(c.device, pipeline, nullptr); });
    VkDescriptorPoolSize sizes[2] = {{types[0], 1}, {types[1], 1}};
    VkDescriptorPoolCreateInfo poolInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
    poolInfo.maxSets = 2; poolInfo.poolSizeCount = 2; poolInfo.pPoolSizes = sizes;
    VkDescriptorPool pool; VK_CHECK(vkCreateDescriptorPool(c.device, &poolInfo, nullptr, &pool));
    c.cleanup.push_back([&, pool] { vkDestroyDescriptorPool(c.device, pool, nullptr); });
    VkDescriptorSetAllocateInfo allocate{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
    allocate.descriptorPool = pool; allocate.descriptorSetCount = 2; allocate.pSetLayouts = layouts;
    VkDescriptorSet sets[2]; VK_CHECK(vkAllocateDescriptorSets(c.device, &allocate, sets));
    VkDescriptorBufferInfo infos[2] = {{output.buffer, 0, wordCount * 4}, {params.buffer, 0, 4}};
    VkWriteDescriptorSet writes[2]{};
    for (unsigned i = 0; i < 2; ++i) {
        writes[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET; writes[i].dstSet = sets[i];
        writes[i].descriptorCount = 1; writes[i].descriptorType = types[i]; writes[i].pBufferInfo = &infos[i];
    }
    vkUpdateDescriptorSets(c.device, 2, writes, 0, nullptr);
    for (uint32_t cycle = 0; cycle < 2; ++cycle) {
        std::memset(output.bytes, 0xA5, output.size);
        std::vector<VkCommandBuffer> commands;
        for (uint32_t i = 0; i < commandCount; ++i) {
            auto command = c.begin();
            vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
            uint32_t offsets[2] = {(i + 1) * outStride, i * paramStride};
            vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 2, sets, 2, offsets);
            uint32_t multiply = 2 + i % 3 + cycle * 5;
            vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &multiply);
            vkCmdDispatch(command, wordCount, 1, 1);
            barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT,
                    VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
            VK_CHECK(vkEndCommandBuffer(command)); commands.push_back(command);
        }
        VkFenceCreateInfo fenceInfo{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO}; VkFence fence;
        VK_CHECK(vkCreateFence(c.device, &fenceInfo, nullptr, &fence));
        c.cleanup.push_back([&, fence] { vkDestroyFence(c.device, fence, nullptr); });
        VkSubmitInfo submit{VK_STRUCTURE_TYPE_SUBMIT_INFO}; submit.commandBufferCount = uint32_t(commands.size());
        submit.pCommandBuffers = commands.data(); c.inFlight = true;
        uint64_t before = c.counter(c.queue);
        VK_CHECK(vkQueueSubmit(c.queue, 1, &submit, fence));
        VK_CHECK(vkWaitForFences(c.device, 1, &fence, VK_TRUE, 10000000000ull));
        VK_CHECK(vkQueueWaitIdle(c.queue)); c.inFlight = false;
        c.nativeAfter = c.counter(c.queue);
        require(c.nativeAfter == before + 1, "24 sequential Vulkan command buffers share one native batch");
        auto* words = static_cast<const uint32_t*>(output.bytes);
        for (uint32_t i = 0; i < output.size / 4; ++i) {
            uint32_t block = (i * 4) / outStride, x = i % (outStride / 4);
            uint32_t expected = block >= 1 && block <= commandCount && x < wordCount
                ? x * (2 + (block - 1) % 3 + cycle * 5) + 17 + block - 1 : 0xA5A5A5A5;
            require(words[i] == expected, "sequential primary snapshots preserve two descriptor sets, dynamic offsets, push data and guards");
        }
    }
}

void semaphoreOrdering(Context& c, bool timeline) {
    require(c.secondQueue != VK_NULL_HANDLE, "two native Vulkan queues available");
    require(!timeline || c.timelineSupported, "timelineSemaphore feature was queried and enabled");
    VkSemaphoreTypeCreateInfo type{VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO};
    type.semaphoreType = timeline ? VK_SEMAPHORE_TYPE_TIMELINE : VK_SEMAPHORE_TYPE_BINARY;
    VkSemaphoreCreateInfo semaphoreInfo{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
    if (timeline) semaphoreInfo.pNext = &type;
    VkSemaphore semaphore; VK_CHECK(vkCreateSemaphore(c.device, &semaphoreInfo, nullptr, &semaphore));
    c.cleanup.push_back([&, semaphore] { vkDestroySemaphore(c.device, semaphore, nullptr); });
    auto middle = c.buffer(512, VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, false);
    auto output = c.buffer(512, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    std::memset(output.bytes, 0xA5, output.size);
    uint64_t secondBefore = c.counter(c.secondQueue);
    VkPipelineStageFlags stage = VK_PIPELINE_STAGE_TRANSFER_BIT;
    for (uint64_t cycle = 1; cycle <= 2; ++cycle) {
        VkCommandBuffer writer = c.begin();
        vkCmdFillBuffer(writer, middle.buffer, 0, VK_WHOLE_SIZE, uint32_t(0x11223300 + cycle));
        VK_CHECK(vkEndCommandBuffer(writer));
        VkCommandBuffer reader = c.begin(true);
        VkBufferCopy copy{64, 64, 384}; vkCmdCopyBuffer(reader, middle.buffer, output.buffer, 1, &copy);
        barrier(reader, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
        VK_CHECK(vkEndCommandBuffer(reader));
        VkFenceCreateInfo fenceInfo{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO}; VkFence fence;
        VK_CHECK(vkCreateFence(c.device, &fenceInfo, nullptr, &fence));
        c.cleanup.push_back([&, fence] { vkDestroyFence(c.device, fence, nullptr); });
        VkTimelineSemaphoreSubmitInfo waitTimeline{VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO};
        waitTimeline.waitSemaphoreValueCount = 1; waitTimeline.pWaitSemaphoreValues = &cycle;
        VkSubmitInfo consumer{VK_STRUCTURE_TYPE_SUBMIT_INFO}; consumer.waitSemaphoreCount = 1;
        consumer.pWaitSemaphores = &semaphore; consumer.pWaitDstStageMask = &stage;
        consumer.commandBufferCount = 1; consumer.pCommandBuffers = &reader;
        if (timeline) consumer.pNext = &waitTimeline;
        VkTimelineSemaphoreSubmitInfo signalTimeline{VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO};
        signalTimeline.signalSemaphoreValueCount = 1; signalTimeline.pSignalSemaphoreValues = &cycle;
        VkSubmitInfo producer{VK_STRUCTURE_TYPE_SUBMIT_INFO}; producer.commandBufferCount = 1; producer.pCommandBuffers = &writer;
        producer.signalSemaphoreCount = 1; producer.pSignalSemaphores = &semaphore;
        if (timeline) producer.pNext = &signalTimeline;
        c.inFlight = true;
        if (timeline) {
            VK_CHECK(vkQueueSubmit(c.secondQueue, 1, &consumer, fence));
            VK_CHECK(vkQueueSubmit(c.queue, 1, &producer, VK_NULL_HANDLE));
        } else {
            // Vulkan binary waits require an already submitted signal operation.
            // Timeline semaphores above deliberately exercise wait-before-signal.
            VK_CHECK(vkQueueSubmit(c.queue, 1, &producer, VK_NULL_HANDLE));
            VK_CHECK(vkQueueSubmit(c.secondQueue, 1, &consumer, fence));
        }
        VK_CHECK(vkWaitForFences(c.device, 1, &fence, VK_TRUE, 10000000000ull));
        VK_CHECK(vkQueueWaitIdle(c.queue)); VK_CHECK(vkQueueWaitIdle(c.secondQueue)); c.inFlight = false;
        const auto* actual = static_cast<const uint32_t*>(output.bytes);
        for (uint32_t i = 0; i < output.size / 4; ++i) {
            uint32_t expected = i >= 16 && i < 112 ? uint32_t(0x11223300 + cycle) : 0xA5A5A5A5;
            require(actual[i] == expected, "cross-queue semaphore data/guard mismatch at " + std::to_string(i));
        }
    }
    if (timeline) {
        // An empty submission still has a real semaphore dependency and fence.
        // A host-signal guard releases it on every assertion/exception path.
        struct ReleaseGate {
            VkDevice device; VkSemaphore semaphore;
            ~ReleaseGate() {
                uint64_t value = 0;
                if (vkGetSemaphoreCounterValue(device, semaphore, &value) == VK_SUCCESS && value < 3) {
                    VkSemaphoreSignalInfo signal{VK_STRUCTURE_TYPE_SEMAPHORE_SIGNAL_INFO}; signal.semaphore = semaphore; signal.value = 3;
                    (void)vkSignalSemaphore(device, &signal);
                }
            }
        } gate{c.device, semaphore};
        uint64_t value = 3;
        VkTimelineSemaphoreSubmitInfo timelineInfo{VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO};
        timelineInfo.waitSemaphoreValueCount = 1; timelineInfo.pWaitSemaphoreValues = &value;
        VkSubmitInfo empty{VK_STRUCTURE_TYPE_SUBMIT_INFO}; empty.pNext = &timelineInfo;
        empty.waitSemaphoreCount = 1; empty.pWaitSemaphores = &semaphore; empty.pWaitDstStageMask = &stage;
        VkFenceCreateInfo fenceInfo{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO}; VkFence fence;
        VK_CHECK(vkCreateFence(c.device, &fenceInfo, nullptr, &fence));
        c.cleanup.push_back([&, fence] { vkDestroyFence(c.device, fence, nullptr); });
        c.inFlight = true;
        VK_CHECK(vkQueueSubmit(c.secondQueue, 1, &empty, fence));
        VkResult early = vkWaitForFences(c.device, 1, &fence, VK_TRUE, 20000000);
        require(early == VK_TIMEOUT && vkGetFenceStatus(c.device, fence) == VK_NOT_READY,
                "fence-only timeline wait cannot complete before its semaphore");
        VkSemaphoreSignalInfo signal{VK_STRUCTURE_TYPE_SEMAPHORE_SIGNAL_INFO}; signal.semaphore = semaphore; signal.value = value;
        VK_CHECK(vkSignalSemaphore(c.device, &signal));
        VK_CHECK(vkWaitForFences(c.device, 1, &fence, VK_TRUE, 10000000000ull));
        VK_CHECK(vkQueueWaitIdle(c.secondQueue)); c.inFlight = false;
    }
    c.nativeAfter = c.counter(c.queue);
    require(c.nativeAfter >= c.nativeBefore + 2 && c.counter(c.secondQueue) >= secondBefore + 2,
            "both native queues completed the two semaphore generations");
}

void timestamps(Context& c) {
    require(c.hostQueryResetSupported && c.timestampValidBits != 0, "host query reset and queue timestamps supported");
    require(std::isfinite(c.properties.limits.timestampPeriod) && c.properties.limits.timestampPeriod > 0,
            "Vulkan timestampPeriod is positive and finite");
    require(c.calibratedTimestamps != nullptr, "calibrated timestamp extension available");
    VkCalibratedTimestampInfoEXT calibration{VK_STRUCTURE_TYPE_CALIBRATED_TIMESTAMP_INFO_EXT};
    calibration.timeDomain = VK_TIME_DOMAIN_DEVICE_EXT;
    VkQueryPoolCreateInfo poolInfo{VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO}; poolInfo.queryType = VK_QUERY_TYPE_TIMESTAMP; poolInfo.queryCount = 2;
    VkQueryPool queryPool; VK_CHECK(vkCreateQueryPool(c.device, &poolInfo, nullptr, &queryPool));
    c.cleanup.push_back([&, queryPool] { vkDestroyQueryPool(c.device, queryPool, nullptr); });
    const uint32_t guard = uint32_t(std::max<VkDeviceSize>(64, c.properties.limits.minStorageBufferOffsetAlignment));
    constexpr uint32_t stride = 24, resultBytes = stride * 2;
    constexpr uint64_t sentinel = 0xA5A5A5A5A5A5A5A5ull;
    auto gpuResults = c.buffer(guard * 2 + resultBytes, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    auto packedResults = c.buffer(guard * 2 + 2 * sizeof(uint64_t), VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
    auto packedReadback = c.buffer(packedResults.size, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    auto narrowResults = c.buffer(guard * 2 + 2 * sizeof(uint32_t), VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    auto work = c.buffer(1024, VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, false);
    auto workReadback = c.buffer(1024, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    auto shaderObserved = c.buffer(packedResults.size, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
    auto shaderParams = c.buffer(16, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
    std::memset(shaderParams.bytes, 0, shaderParams.size);
    VkDescriptorSetLayoutBinding copyBindings[3] = {
        {0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr},
        {1, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr},
        {2, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr}};
    VkDescriptorSetLayoutCreateInfo copySetInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
    copySetInfo.bindingCount = 3; copySetInfo.pBindings = copyBindings;
    VkDescriptorSetLayout copySetLayout;
    VK_CHECK(vkCreateDescriptorSetLayout(c.device, &copySetInfo, nullptr, &copySetLayout));
    c.cleanup.push_back([&, copySetLayout] { vkDestroyDescriptorSetLayout(c.device, copySetLayout, nullptr); });
    VkPushConstantRange copyPush{VK_SHADER_STAGE_COMPUTE_BIT, 0, 4};
    VkPipelineLayoutCreateInfo copyLayoutInfo{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    copyLayoutInfo.setLayoutCount = 1; copyLayoutInfo.pSetLayouts = &copySetLayout;
    copyLayoutInfo.pushConstantRangeCount = 1; copyLayoutInfo.pPushConstantRanges = &copyPush;
    VkPipelineLayout copyLayout;
    VK_CHECK(vkCreatePipelineLayout(c.device, &copyLayoutInfo, nullptr, &copyLayout));
    c.cleanup.push_back([&, copyLayout] { vkDestroyPipelineLayout(c.device, copyLayout, nullptr); });
    VkPipeline copyPipelines[2];
    for (unsigned i = 0; i < 2; ++i) {
        VkComputePipelineCreateInfo info{VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO}; info.layout = copyLayout;
        info.stage = {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, nullptr, 0,
                      VK_SHADER_STAGE_COMPUTE_BIT, c.shader(computeShader(i ? 2 : 0)), "main", nullptr};
        VK_CHECK(vkCreateComputePipelines(c.device, VK_NULL_HANDLE, 1, &info, nullptr, &copyPipelines[i]));
        auto pipeline = copyPipelines[i];
        c.cleanup.push_back([&, pipeline] { vkDestroyPipeline(c.device, pipeline, nullptr); });
    }
    VkDescriptorPoolSize copySizes[3] = {{VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC, 1},
        {VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1}, {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1}};
    VkDescriptorPoolCreateInfo copyPoolInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
    copyPoolInfo.maxSets = 1; copyPoolInfo.poolSizeCount = 3; copyPoolInfo.pPoolSizes = copySizes;
    VkDescriptorPool copyPool;
    VK_CHECK(vkCreateDescriptorPool(c.device, &copyPoolInfo, nullptr, &copyPool));
    c.cleanup.push_back([&, copyPool] { vkDestroyDescriptorPool(c.device, copyPool, nullptr); });
    VkDescriptorSetAllocateInfo copyAllocate{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
    copyAllocate.descriptorPool = copyPool; copyAllocate.descriptorSetCount = 1; copyAllocate.pSetLayouts = &copySetLayout;
    VkDescriptorSet copySet; VK_CHECK(vkAllocateDescriptorSets(c.device, &copyAllocate, &copySet));
    VkDescriptorBufferInfo copyInfos[3] = {{packedResults.buffer, 0, 16},
        {shaderParams.buffer, 0, 4}, {shaderObserved.buffer, guard, 16}};
    VkWriteDescriptorSet copyWrites[3]{};
    for (unsigned i = 0; i < 3; ++i) {
        copyWrites[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        copyWrites[i].dstSet = copySet; copyWrites[i].dstBinding = i; copyWrites[i].descriptorCount = 1;
        copyWrites[i].descriptorType = copyBindings[i].descriptorType; copyWrites[i].pBufferInfo = &copyInfos[i];
    }
    vkUpdateDescriptorSets(c.device, 3, copyWrites, 0, nullptr);
    for (uint32_t cycle = 0; cycle < 2; ++cycle) {
        // Initialize availability through the enabled host-reset feature before
        // asking for unsubmitted results; a newly created pool is undefined.
        vkResetQueryPool(c.device, queryPool, 0, 2);
        std::memset(gpuResults.bytes, 0xA5, gpuResults.size);
        std::memset(packedResults.bytes, 0xA5, packedResults.size);
        std::memset(packedReadback.bytes, 0xA5, packedReadback.size);
        std::memset(narrowResults.bytes, 0xA5, narrowResults.size);
        // First cycle retains the deferred reset path; second uses host reset
        // plus one-time leading timestamp preparation in the same existing case.
        if (cycle) { c.oneTime = true; }
        VkCommandBuffer command = c.begin();
        if (!cycle) { vkCmdResetQueryPool(command, queryPool, 0, 2); }
        vkCmdWriteTimestamp(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, queryPool, 0);
        vkCmdFillBuffer(command, work.buffer, 0, VK_WHOLE_SIZE, 0x12345670 + cycle);
        barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_READ_BIT);
        VkBufferCopy copy{0, 0, 1024}; vkCmdCopyBuffer(command, work.buffer, workReadback.buffer, 1, &copy);
        vkCmdWriteTimestamp(command, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, queryPool, 1);
        // Exercise a packed destination after a GPU write, then use the copied
        // query data as a transfer source. The original strided/availability
        // path and the 32-bit shader fallback must still agree with host data.
        vkCmdFillBuffer(command, packedResults.buffer, 0, VK_WHOLE_SIZE, 0xA5A5A5A5);
        barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT,
                VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT);
        vkCmdCopyQueryPoolResults(command, queryPool, 0, 2, packedResults.buffer, guard, sizeof(uint64_t),
                                 VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WAIT_BIT);
        vkCmdCopyQueryPoolResults(command, queryPool, 0, 2, narrowResults.buffer, guard, sizeof(uint32_t),
                                 VK_QUERY_RESULT_WAIT_BIT);
        vkCmdCopyQueryPoolResults(command, queryPool, 0, 2, gpuResults.buffer, guard, stride,
                                 VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WITH_AVAILABILITY_BIT | VK_QUERY_RESULT_WAIT_BIT);
        barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT,
                VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_READ_BIT);
        VkBufferCopy packedCopy{0, 0, packedResults.size};
        vkCmdCopyBuffer(command, packedResults.buffer, packedReadback.buffer, 1, &packedCopy);
        barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
        uint64_t unavailable[6]; std::fill(std::begin(unavailable), std::end(unavailable), sentinel);
        VkResult before = vkGetQueryPoolResults(c.device, queryPool, 0, 2, sizeof(unavailable), unavailable, stride,
                                               VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WITH_AVAILABILITY_BIT);
        require(before == VK_NOT_READY, "reset but unsubmitted timestamp queries are not ready");
        require(unavailable[0] == sentinel && unavailable[3] == sentinel && unavailable[1] == 0 && unavailable[4] == 0 &&
                unavailable[2] == sentinel && unavailable[5] == sentinel, "unavailable query results preserve data/padding and write availability zero");
        uint64_t calibratedBefore = 0, calibratedAfter = 0, beforeDeviation = 0, afterDeviation = 0;
        VK_CHECK(c.calibratedTimestamps(c.device, 1, &calibration, &calibratedBefore, &beforeDeviation));
        c.submit(command);
        VK_CHECK(c.calibratedTimestamps(c.device, 1, &calibration, &calibratedAfter, &afterDeviation));
        uint64_t host[6]; std::fill(std::begin(host), std::end(host), sentinel);
        VK_CHECK(vkGetQueryPoolResults(c.device, queryPool, 0, 2, sizeof(host), host, stride,
                                      VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WITH_AVAILABILITY_BIT | VK_QUERY_RESULT_WAIT_BIT));
        require(host[0] > 0 && host[3] >= host[0] && host[1] != 0 && host[4] != 0, "completed timestamps are positive/nondecreasing and available");
        require(host[2] == sentinel && host[5] == sentinel, "host query copy preserves stride padding");
        uint64_t margin = uint64_t(std::ceil(std::max(beforeDeviation, afterDeviation) / double(c.properties.limits.timestampPeriod))) + 2;
        require(calibratedBefore <= host[0] + margin && host[3] <= calibratedAfter + margin,
                "native query counters and calibrated device timestamps share clock units and origin");
        const auto* gpu = static_cast<const uint8_t*>(gpuResults.bytes);
        for (uint32_t i = 0; i < gpuResults.size; ++i) {
            uint8_t expected = i >= guard && i < guard + resultBytes ? reinterpret_cast<const uint8_t*>(host)[i - guard] : 0xA5;
            require(gpu[i] == expected, "GPU/host timestamp result, availability, or padding mismatch at " + std::to_string(i));
        }
        const uint64_t packedHost[2] = {host[0], host[3]};
        const uint32_t narrowHost[2] = {uint32_t(host[0]), uint32_t(host[3])};
        auto checkPacked = [&](const Buffer& buffer, const void* expectedData, size_t bytes) {
            const auto* actual = static_cast<const uint8_t*>(buffer.bytes);
            const auto* expectedBytes = static_cast<const uint8_t*>(expectedData);
            for (uint32_t i = 0; i < buffer.size; ++i) {
                const uint8_t expected = i >= guard && i < guard + bytes ? expectedBytes[i - guard] : 0xA5;
                require(actual[i] == expected, "packed/narrow query copy or guard mismatch at " + std::to_string(i));
            }
        };
        checkPacked(packedResults, packedHost, sizeof(packedHost));
        checkPacked(packedReadback, packedHost, sizeof(packedHost));
        checkPacked(narrowResults, narrowHost, sizeof(narrowHost));
        const auto* copiedWork = static_cast<const uint32_t*>(workReadback.bytes);
        for (uint32_t i = 0; i < 256; ++i) require(copiedWork[i] == 0x12345670 + cycle, "timestamp-bracketed transfer work completed");

        // The preceding write-to-resolve boundary already covers both opaque
        // timestamps. A new recording that only reads them may reuse that
        // completion proof, but must still produce the same data and padding.
        std::memset(gpuResults.bytes, 0xA5, gpuResults.size);
        std::memset(packedResults.bytes, 0xA5, packedResults.size);
        auto readOnly = c.begin();
        vkCmdFillBuffer(readOnly, workReadback.buffer, 0, VK_WHOLE_SIZE, 0x76543210 + cycle);
        vkCmdCopyQueryPoolResults(readOnly, queryPool, 0, 2, packedResults.buffer, guard, sizeof(uint64_t), VK_QUERY_RESULT_64_BIT);
        vkCmdCopyQueryPoolResults(readOnly, queryPool, 0, 2, gpuResults.buffer, guard, stride,
                                 VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WITH_AVAILABILITY_BIT | VK_QUERY_RESULT_WAIT_BIT);
        barrier(readOnly, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT,
                VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
        c.submit(readOnly);
        checkPacked(packedResults, packedHost, sizeof(packedHost));
        for (uint32_t i = 0; i < gpuResults.size; ++i) {
            uint8_t expected = i >= guard && i < guard + resultBytes ? reinterpret_cast<const uint8_t*>(host)[i - guard] : 0xA5;
            require(gpu[i] == expected, "read-only timestamp result reuse preserves host values, availability and padding");
        }
        for (uint32_t i = 0; i < 256; ++i)
            require(copiedWork[i] == 0x76543210 + cycle, "read-only result submission retains preceding transfer work");

        // A shader first writes the application's destination. The query copy
        // overwrites it, and a shader in the NEXT command buffer reads the exact
        // timestamp bits before a transfer overwrites them. Explicit Vulkan
        // WAW/RAW/WAR scopes must survive without blanket query graphics waits.
        std::memset(packedResults.bytes, 0xA5, packedResults.size);
        std::memset(shaderObserved.bytes, 0xA5, shaderObserved.size);
        VkCommandBuffer chain[2] = {c.begin(), VK_NULL_HANDLE};
        uint32_t zero = 0;
        vkCmdBindPipeline(chain[0], VK_PIPELINE_BIND_POINT_COMPUTE, copyPipelines[0]);
        vkCmdBindDescriptorSets(chain[0], VK_PIPELINE_BIND_POINT_COMPUTE, copyLayout, 0, 1, &copySet, 1, &guard);
        vkCmdPushConstants(chain[0], copyLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &zero);
        vkCmdDispatch(chain[0], 4, 1, 1);
        barrier(chain[0], VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT,
                VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT);
        vkCmdCopyQueryPoolResults(chain[0], queryPool, 0, 2, packedResults.buffer, guard, sizeof(uint64_t), VK_QUERY_RESULT_64_BIT);
        VK_CHECK(vkEndCommandBuffer(chain[0]));
        chain[1] = c.begin();
        barrier(chain[1], VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT,
                VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_READ_BIT);
        vkCmdBindPipeline(chain[1], VK_PIPELINE_BIND_POINT_COMPUTE, copyPipelines[1]);
        vkCmdBindDescriptorSets(chain[1], VK_PIPELINE_BIND_POINT_COMPUTE, copyLayout, 0, 1, &copySet, 1, &guard);
        vkCmdPushConstants(chain[1], copyLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &zero);
        vkCmdDispatch(chain[1], 4, 1, 1);
        barrier(chain[1], VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, VK_PIPELINE_STAGE_TRANSFER_BIT, 0);
        vkCmdFillBuffer(chain[1], packedResults.buffer, guard, 16, 0xBDBDBDBD);
        barrier(chain[1], VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT | VK_PIPELINE_STAGE_TRANSFER_BIT,
                VK_ACCESS_SHADER_WRITE_BIT | VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
        VK_CHECK(vkEndCommandBuffer(chain[1]));
        VkFenceCreateInfo chainFenceInfo{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO}; VkFence chainFence;
        VK_CHECK(vkCreateFence(c.device, &chainFenceInfo, nullptr, &chainFence));
        VkSubmitInfo chainSubmit{VK_STRUCTURE_TYPE_SUBMIT_INFO}; chainSubmit.commandBufferCount = 2; chainSubmit.pCommandBuffers = chain;
        c.inFlight = true;
        VK_CHECK(vkQueueSubmit(c.queue, 1, &chainSubmit, chainFence));
        VK_CHECK(vkWaitForFences(c.device, 1, &chainFence, VK_TRUE, 10000000000ull));
        VK_CHECK(vkQueueWaitIdle(c.queue)); c.inFlight = false;
        vkDestroyFence(c.device, chainFence, nullptr); c.nativeAfter = c.counter(c.queue);
        checkPacked(shaderObserved, packedHost, sizeof(packedHost));
        const uint64_t overwritten[2] = {0xBDBDBDBDBDBDBDBDull, 0xBDBDBDBDBDBDBDBDull};
        checkPacked(packedResults, overwritten, sizeof(overwritten));

        // Host-only reads after the existing queue-idle completion. Check the
        // nonzero firstQuery and narrow strided conversion without new GPU work.
        uint64_t second[3] = {sentinel, sentinel, sentinel};
        VK_CHECK(vkGetQueryPoolResults(c.device, queryPool, 1, 1, sizeof(second), second, stride,
                                      VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WITH_AVAILABILITY_BIT));
        require(second[0] == host[3] && second[1] == 1 && second[2] == sentinel,
                "single completed query1 host read preserves firstQuery and padding");
        uint32_t narrow[6]; std::fill(std::begin(narrow), std::end(narrow), 0xA5A5A5A5);
        VK_CHECK(vkGetQueryPoolResults(c.device, queryPool, 0, 2, sizeof(narrow), narrow, 3 * sizeof(uint32_t),
                                      VK_QUERY_RESULT_WITH_AVAILABILITY_BIT | VK_QUERY_RESULT_WAIT_BIT));
        require(narrow[0] == uint32_t(host[0]) && narrow[3] == uint32_t(host[3]) && narrow[1] == 1 && narrow[4] == 1 &&
                narrow[2] == 0xA5A5A5A5 && narrow[5] == 0xA5A5A5A5, "completed narrow host range preserves availability and padding");

        // All prior GPU uses are idle; resetting only query1 must retain the
        // original mixed-range fallback and leave its unavailable value alone.
        vkResetQueryPool(c.device, queryPool, 1, 1);
        uint64_t mixed[6]; std::fill(std::begin(mixed), std::end(mixed), sentinel);
        require(vkGetQueryPoolResults(c.device, queryPool, 0, 2, sizeof(mixed), mixed, stride,
                                     VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WITH_AVAILABILITY_BIT) == VK_NOT_READY,
                "host reset of query1 leaves mixed range not ready");
        require(mixed[0] == host[0] && mixed[1] == 1 && mixed[2] == sentinel && mixed[3] == sentinel &&
                mixed[4] == 0 && mixed[5] == sentinel, "mixed host read preserves completed query0 and reset query1 data/padding");
    }
    require(c.nativeAfter >= c.nativeBefore + 6, "timestamp reset/reuse, read-only and cross-buffer results completed six submissions");
}

void render(Context& c, bool sampled = false, bool clearRestore = false, uint32_t resolveMode = 0,
            uint32_t indirectMode = 0, bool occlusion = false, bool uniformPush = false) {
    constexpr uint32_t width = 16, height = 16, rowBytes = 256, guard = 256;
    require(!resolveMode || (c.properties.limits.framebufferColorSampleCounts & VK_SAMPLE_COUNT_4_BIT), "4x color MSAA support");
    VkSampleCountFlagBits samples = resolveMode ? VK_SAMPLE_COUNT_4_BIT : VK_SAMPLE_COUNT_1_BIT;
    auto target = c.image(width, height, VK_FORMAT_R8G8B8A8_UNORM,
                          VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT, samples);
    VkImage image = target.image; VkImageView view = target.view;
    Image resolved{}, partialResolved{};
    if (resolveMode) resolved = c.image(width, height, VK_FORMAT_R8G8B8A8_UNORM,
        VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT);
    if (resolveMode == 2) partialResolved = c.image(width, height, VK_FORMAT_R8G8B8A8_UNORM,
        VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT);
    VkAttachmentDescription attachments[2]{};
    auto& attachment = attachments[0]; attachment.format = VK_FORMAT_R8G8B8A8_UNORM; attachment.samples = samples;
    attachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR; attachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    attachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED; attachment.finalLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    if (clearRestore) { attachment.loadOp = VK_ATTACHMENT_LOAD_OP_LOAD; attachment.initialLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL; }
    VkAttachmentReference reference{0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};
    VkAttachmentReference resolveReference{1, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};
    VkSubpassDescription subpass{}; subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS; subpass.colorAttachmentCount = 1; subpass.pColorAttachments = &reference;
    if (resolveMode == 1) {
        attachments[1] = attachment; attachments[1].samples = VK_SAMPLE_COUNT_1_BIT;
        attachments[1].loadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE; attachments[1].initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        subpass.pResolveAttachments = &resolveReference;
    }
    VkSubpassDependency dependency{0, VK_SUBPASS_EXTERNAL, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
                                   VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT, VK_ACCESS_TRANSFER_READ_BIT, 0};
    VkRenderPassCreateInfo passInfo{VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO}; passInfo.attachmentCount = resolveMode == 1 ? 2 : 1; passInfo.pAttachments = attachments;
    passInfo.subpassCount = 1; passInfo.pSubpasses = &subpass; passInfo.dependencyCount = 1; passInfo.pDependencies = &dependency;
    VkRenderPass pass; VK_CHECK(vkCreateRenderPass(c.device, &passInfo, nullptr, &pass)); c.cleanup.push_back([&, pass] { vkDestroyRenderPass(c.device, pass, nullptr); });
    VkFramebufferCreateInfo framebufferInfo{VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO}; framebufferInfo.renderPass = pass;
    const VkImageView framebufferViews[2] = {view, resolved.view};
    framebufferInfo.attachmentCount = passInfo.attachmentCount; framebufferInfo.pAttachments = framebufferViews;
    framebufferInfo.width = width; framebufferInfo.height = height; framebufferInfo.layers = 1;
    VkFramebuffer framebuffer; VK_CHECK(vkCreateFramebuffer(c.device, &framebufferInfo, nullptr, &framebuffer));
    c.cleanup.push_back([&, framebuffer] { vkDestroyFramebuffer(c.device, framebuffer, nullptr); });
    VkPipelineLayoutCreateInfo layoutInfo{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    Image texture{}; Buffer textureUpload{};
    VkDescriptorSet sampledSet = VK_NULL_HANDLE;
    VkDescriptorSetLayout sampledLayout = VK_NULL_HANDLE;
    Buffer uniformParams{}, alternateParams{};
    VkDescriptorUpdateTemplate uniformTemplate = VK_NULL_HANDLE;
    PFN_vkCmdPushDescriptorSetWithTemplateKHR pushTemplate = nullptr;
    if (uniformPush) {
        require(!sampled, "uniform push fixture uses its own descriptor layout");
        uniformParams = c.buffer(16, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
        alternateParams = c.buffer(16, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
        std::memset(uniformParams.bytes, 0, 16); std::memset(alternateParams.bytes, 0, 16);
        VkDescriptorSetLayoutBinding binding{0, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1, VK_SHADER_STAGE_FRAGMENT_BIT, nullptr};
        VkDescriptorSetLayoutCreateInfo info{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
        info.flags = VK_DESCRIPTOR_SET_LAYOUT_CREATE_PUSH_DESCRIPTOR_BIT_KHR;
        info.bindingCount = 1; info.pBindings = &binding;
        VK_CHECK(vkCreateDescriptorSetLayout(c.device, &info, nullptr, &sampledLayout));
        c.cleanup.push_back([&, sampledLayout] { vkDestroyDescriptorSetLayout(c.device, sampledLayout, nullptr); });
        layoutInfo.setLayoutCount = 1; layoutInfo.pSetLayouts = &sampledLayout;
        pushTemplate = reinterpret_cast<PFN_vkCmdPushDescriptorSetWithTemplateKHR>(vkGetDeviceProcAddr(c.device, "vkCmdPushDescriptorSetWithTemplateKHR"));
        require(pushTemplate, "graphics push template entry point");
    }
    if (sampled) {
        texture = c.image(2, 2, VK_FORMAT_R8G8B8A8_UNORM, VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT);
        textureUpload = c.buffer(16, VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
        const uint8_t texels[16] = {64,128,191,255, 244,8,4,255, 8,244,4,255, 4,8,244,255};
        std::memcpy(textureUpload.bytes, texels, sizeof(texels));
        VkSamplerCreateInfo samplerInfo{VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO};
        samplerInfo.magFilter = samplerInfo.minFilter = VK_FILTER_NEAREST; samplerInfo.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST;
        samplerInfo.addressModeU = samplerInfo.addressModeV = samplerInfo.addressModeW = VK_SAMPLER_ADDRESS_MODE_REPEAT;
        VkSampler sampler; VK_CHECK(vkCreateSampler(c.device, &samplerInfo, nullptr, &sampler));
        c.cleanup.push_back([&, sampler] { vkDestroySampler(c.device, sampler, nullptr); });
        VkDescriptorSetLayoutBinding binding{0, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1, VK_SHADER_STAGE_FRAGMENT_BIT, nullptr};
        VkDescriptorSetLayoutCreateInfo setInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO}; setInfo.bindingCount = 1; setInfo.pBindings = &binding;
        VK_CHECK(vkCreateDescriptorSetLayout(c.device, &setInfo, nullptr, &sampledLayout));
        c.cleanup.push_back([&, sampledLayout] { vkDestroyDescriptorSetLayout(c.device, sampledLayout, nullptr); });
        VkDescriptorPoolSize size{VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1};
        VkDescriptorPoolCreateInfo poolInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO}; poolInfo.maxSets = 1; poolInfo.poolSizeCount = 1; poolInfo.pPoolSizes = &size;
        VkDescriptorPool descriptorPool; VK_CHECK(vkCreateDescriptorPool(c.device, &poolInfo, nullptr, &descriptorPool));
        c.cleanup.push_back([&, descriptorPool] { vkDestroyDescriptorPool(c.device, descriptorPool, nullptr); });
        VkDescriptorSetAllocateInfo allocate{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO}; allocate.descriptorPool = descriptorPool;
        allocate.descriptorSetCount = 1; allocate.pSetLayouts = &sampledLayout;
        VK_CHECK(vkAllocateDescriptorSets(c.device, &allocate, &sampledSet));
        VkDescriptorImageInfo imageInfo{sampler, texture.view, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
        VkWriteDescriptorSet write{VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET}; write.dstSet = sampledSet; write.descriptorCount = 1;
        write.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER; write.pImageInfo = &imageInfo;
        vkUpdateDescriptorSets(c.device, 1, &write, 0, nullptr);
        layoutInfo.setLayoutCount = 1; layoutInfo.pSetLayouts = &sampledLayout;
    }
    VkPipelineLayout layout; VK_CHECK(vkCreatePipelineLayout(c.device, &layoutInfo, nullptr, &layout)); c.cleanup.push_back([&, layout] { vkDestroyPipelineLayout(c.device, layout, nullptr); });
    if (uniformPush) {
        VkDescriptorUpdateTemplateEntry entry{0, 0, 1, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 8193, 8};
        VkDescriptorUpdateTemplateCreateInfo info{VK_STRUCTURE_TYPE_DESCRIPTOR_UPDATE_TEMPLATE_CREATE_INFO};
        info.descriptorUpdateEntryCount = 1; info.pDescriptorUpdateEntries = &entry;
        info.templateType = VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_PUSH_DESCRIPTORS_KHR;
        info.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS; info.pipelineLayout = layout;
        VK_CHECK(vkCreateDescriptorUpdateTemplate(c.device, &info, nullptr, &uniformTemplate));
        c.cleanup.push_back([&, uniformTemplate] { vkDestroyDescriptorUpdateTemplate(c.device, uniformTemplate, nullptr); });
    }
    VkPipelineShaderStageCreateInfo stages[2] = {
        {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, nullptr, 0, VK_SHADER_STAGE_VERTEX_BIT, c.shader(vertexShader()), "main", nullptr},
        {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, nullptr, 0, VK_SHADER_STAGE_FRAGMENT_BIT,
            c.shader(sampled ? sampledFragmentShader() : fragmentShader(uniformPush)), "main", nullptr}};
    VkVertexInputBindingDescription binding{0, 8, VK_VERTEX_INPUT_RATE_VERTEX};
    VkVertexInputAttributeDescription attribute{0, 0, VK_FORMAT_R32G32_SFLOAT, 0};
    VkPipelineVertexInputStateCreateInfo vertexInput{VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
    vertexInput.vertexBindingDescriptionCount = 1; vertexInput.pVertexBindingDescriptions = &binding; vertexInput.vertexAttributeDescriptionCount = 1; vertexInput.pVertexAttributeDescriptions = &attribute;
    VkPipelineInputAssemblyStateCreateInfo assembly{VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO}; assembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    VkViewport viewport{0, 0, float(width), float(height), 0, 1}; VkRect2D scissor{{0, 0}, {width, height}};
    VkRect2D drawScissor = scissor; if (clearRestore) drawScissor.extent.width = width / 2;
    VkPipelineViewportStateCreateInfo viewportInfo{VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO}; viewportInfo.viewportCount = viewportInfo.scissorCount = 1;
    viewportInfo.pViewports = &viewport; viewportInfo.pScissors = &drawScissor;
    VkPipelineRasterizationStateCreateInfo raster{VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO}; raster.polygonMode = VK_POLYGON_MODE_FILL;
    raster.cullMode = VK_CULL_MODE_NONE; raster.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE; raster.lineWidth = 1;
    VkPipelineMultisampleStateCreateInfo multisample{VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO}; multisample.rasterizationSamples = samples;
    VkPipelineColorBlendAttachmentState blend{}; blend.colorWriteMask = 15;
    VkPipelineColorBlendStateCreateInfo colorBlend{VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO}; colorBlend.attachmentCount = 1; colorBlend.pAttachments = &blend;
    VkGraphicsPipelineCreateInfo pipelineInfo{VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO}; pipelineInfo.stageCount = 2; pipelineInfo.pStages = stages;
    pipelineInfo.pVertexInputState = &vertexInput; pipelineInfo.pInputAssemblyState = &assembly; pipelineInfo.pViewportState = &viewportInfo;
    pipelineInfo.pRasterizationState = &raster; pipelineInfo.pMultisampleState = &multisample; pipelineInfo.pColorBlendState = &colorBlend;
    pipelineInfo.layout = layout; pipelineInfo.renderPass = pass;
    VkPipeline pipeline; VK_CHECK(vkCreateGraphicsPipelines(c.device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &pipeline));
    c.cleanup.push_back([&, pipeline] { vkDestroyPipeline(c.device, pipeline, nullptr); });
    require(!indirectMode || c.multiDrawIndirectSupported, "multiDrawIndirect feature supported and enabled");
    auto vertices = c.buffer(32 + 32, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    auto indices = c.buffer(8 + 8, VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
    auto readback = c.buffer(guard * 2 + rowBytes * height, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    Buffer partialReadback{};
    if (resolveMode == 2) { partialReadback = c.buffer(readback.size, VK_BUFFER_USAGE_TRANSFER_DST_BIT); std::memset(partialReadback.bytes, 0xA5, partialReadback.size); }
    const float xy[6] = {-1, -1, 3, -1, -1, 3}; const uint16_t index[3] = {0, 1, 2};
    std::memset(vertices.bytes, 0xCD, vertices.size); std::memcpy(static_cast<uint8_t*>(vertices.bytes) + 32 + (indirectMode ? 8 : 0), xy, sizeof(xy));
    std::memset(indices.bytes, 0xEF, indices.size); std::memcpy(static_cast<uint8_t*>(indices.bytes) + 8 + (indirectMode ? 2 : 0), index, sizeof(index));
    if (indirectMode) {
        const float unusedVertex[2] = {0, 0}; const uint16_t unusedIndex = 0;
        std::memcpy(static_cast<uint8_t*>(vertices.bytes) + 32, unusedVertex, sizeof(unusedVertex));
        std::memcpy(static_cast<uint8_t*>(indices.bytes) + 8, &unusedIndex, sizeof(unusedIndex));
    }
    Buffer indirectArguments{};
    if (indirectMode) indirectArguments = c.buffer(128, VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT, false);
    VkQueryPool queryPool = VK_NULL_HANDLE; Buffer queryResults{}, packedQueryResults{};
    constexpr uint32_t queryCount = 3, queryGuard = 64, queryStride = 24, queryBytes = queryCount * queryStride;
    constexpr uint64_t querySentinel = 0xA5A5A5A5A5A5A5A5ull;
    if (occlusion) {
        require(c.hostQueryResetSupported && clearRestore && !sampled && !resolveMode && !indirectMode, "occlusion fixture prerequisites");
        VkQueryPoolCreateInfo queryInfo{VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO}; queryInfo.queryType = VK_QUERY_TYPE_OCCLUSION; queryInfo.queryCount = queryCount;
        VK_CHECK(vkCreateQueryPool(c.device, &queryInfo, nullptr, &queryPool));
        c.cleanup.push_back([&, queryPool] { vkDestroyQueryPool(c.device, queryPool, nullptr); });
        queryResults = c.buffer(queryGuard * 2 + queryBytes, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
        packedQueryResults = c.buffer(queryGuard * 2 + queryCount * sizeof(uint64_t), VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    }
    for (uint32_t cycle = 0; cycle < (occlusion ? 2u : 1u); ++cycle) {
    std::memset(readback.bytes, 0xA5, readback.size);
    VkCommandBuffer command = c.begin();
    if (occlusion) {
        vkResetQueryPool(c.device, queryPool, 0, queryCount);
        std::memset(queryResults.bytes, 0xA5, queryResults.size);
        std::memset(packedQueryResults.bytes, 0xA5, packedQueryResults.size);
        vkCmdResetQueryPool(command, queryPool, 0, queryCount);
    }
    if (indirectMode) {
        // Only the GPU sees these argument records after upload. Padding/header
        // bytes and a zero-length first draw detect offset/stride mistakes.
        uint8_t argumentBytes[128]{};
        if (indirectMode == 1) {
            VkDrawIndirectCommand records[2] = {{0, 1, 0, 0}, {3, 1, 1, 0}};
            std::memcpy(argumentBytes + 32, &records[0], sizeof(records[0]));
            std::memcpy(argumentBytes + 64, &records[1], sizeof(records[1]));
        } else {
            VkDrawIndexedIndirectCommand records[2] = {{0, 1, 0, 0, 0}, {3, 1, 1, 1, 0}};
            std::memcpy(argumentBytes + 32, &records[0], sizeof(records[0]));
            std::memcpy(argumentBytes + 64, &records[1], sizeof(records[1]));
        }
        vkCmdUpdateBuffer(command, indirectArguments.buffer, 0, sizeof(argumentBytes), argumentBytes);
        barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT,
                VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT, VK_ACCESS_INDIRECT_COMMAND_READ_BIT);
    }
    if (clearRestore) {
        VkImageMemoryBarrier transition{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER}; transition.image = image;
        transition.srcQueueFamilyIndex = transition.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        transition.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        transition.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED; transition.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        transition.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &transition);
        VkClearColorValue blue{{0, 0, 1, 1}};
        vkCmdClearColorImage(command, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &blue, 1, &transition.subresourceRange);
        transition.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL; transition.newLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
        transition.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; transition.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, 0, 0, nullptr, 0, nullptr, 1, &transition);
    }
    if (sampled) {
        VkImageMemoryBarrier transition{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER}; transition.image = texture.image;
        transition.srcQueueFamilyIndex = transition.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        transition.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        transition.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED; transition.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        transition.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &transition);
        VkBufferImageCopy upload{}; upload.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1}; upload.imageExtent = {2, 2, 1};
        vkCmdCopyBufferToImage(command, textureUpload.buffer, texture.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &upload);
        transition.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL; transition.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        transition.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; transition.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &transition);
    }
    VkClearValue clear{}; clear.color.float32[0] = clear.color.float32[2] = clear.color.float32[3] = 1;
    VkRenderPassBeginInfo beginInfo{VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO}; beginInfo.renderPass = pass; beginInfo.framebuffer = framebuffer;
    beginInfo.renderArea = scissor; beginInfo.clearValueCount = 1; beginInfo.pClearValues = &clear;
    vkCmdBeginRenderPass(command, &beginInfo, VK_SUBPASS_CONTENTS_INLINE);
    vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
    if (uniformPush) {
        std::vector<uint8_t> data(8193 + sizeof(VkDescriptorBufferInfo), 0xcd);
        VkDescriptorBufferInfo descriptor{uniformParams.buffer, 0, 16};
        std::memcpy(data.data() + 8193, &descriptor, sizeof(descriptor));
        pushTemplate(command, uniformTemplate, layout, 0, data.data());
        descriptor.buffer = alternateParams.buffer;
        std::memcpy(data.data() + 8193, &descriptor, sizeof(descriptor));
        const float color[4] = {.25f, .5f, .75f, 1.f};
        std::memcpy(uniformParams.bytes, color, sizeof(color));
    }
    if (sampled) vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_GRAPHICS, layout, 0, 1, &sampledSet, 0, nullptr);
    VkDeviceSize vertexOffset = 32; vkCmdBindVertexBuffers(command, 0, 1, &vertices.buffer, &vertexOffset);
    vkCmdBindIndexBuffer(command, indices.buffer, 8, VK_INDEX_TYPE_UINT16);
    if (occlusion) {
        VkQueryControlFlags flags = c.preciseOcclusionSupported ? VK_QUERY_CONTROL_PRECISE_BIT : 0;
        vkCmdBeginQuery(command, queryPool, 0, flags); vkCmdEndQuery(command, queryPool, 0);
        vkCmdBeginQuery(command, queryPool, 1, flags);
        VkClearAttachment blue{}; blue.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        blue.clearValue.color.float32[2] = blue.clearValue.color.float32[3] = 1;
        VkClearRect fullRectangle{{{0, 0}, {width, height}}, 0, 1};
        vkCmdClearAttachments(command, 1, &blue, 1, &fullRectangle);
        vkCmdEndQuery(command, queryPool, 1);
        vkCmdBeginQuery(command, queryPool, 2, flags);
    }
    if (indirectMode == 1) vkCmdDrawIndirect(command, indirectArguments.buffer, 32, 2, 32);
    else if (indirectMode == 2) vkCmdDrawIndexedIndirect(command, indirectArguments.buffer, 32, 2, 32);
    else vkCmdDrawIndexed(command, 3, 1, 0, 0, 0);
    if (clearRestore) {
        VkClearAttachment red{}; red.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        red.clearValue.color.float32[0] = red.clearValue.color.float32[3] = 1;
        VkClearRect rectangle{{{int32_t(width / 4), 0}, {width / 2, height}}, 0, 1};
        vkCmdClearAttachments(command, 1, &red, 1, &rectangle);
        // No app pipeline, resource, viewport, or scissor rebind after the helper.
        vkCmdDrawIndexed(command, 3, 1, 0, 0, 0);
    }
    if (occlusion) vkCmdEndQuery(command, queryPool, 2);
    vkCmdEndRenderPass(command);
    if (occlusion) {
        vkCmdCopyQueryPoolResults(command, queryPool, 0, queryCount, packedQueryResults.buffer, queryGuard, sizeof(uint64_t),
            VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WAIT_BIT);
        vkCmdCopyQueryPoolResults(command, queryPool, 0, queryCount, queryResults.buffer, queryGuard, queryStride,
            VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WITH_AVAILABILITY_BIT | VK_QUERY_RESULT_WAIT_BIT);
    }
    if (resolveMode == 2) {
        VkImageMemoryBarrier transitions[2]{};
        for (uint32_t i = 0; i < 2; ++i) {
            auto& transition = transitions[i]; transition.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
            transition.image = i ? partialResolved.image : resolved.image;
            transition.srcQueueFamilyIndex = transition.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
            transition.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
            transition.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED; transition.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
            transition.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        }
        vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 2, transitions);
        VkClearColorValue blue{{0, 0, 1, 1}};
        vkCmdClearColorImage(command, partialResolved.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &blue, 1, &transitions[1].subresourceRange);
        VkImageResolve full{}; full.srcSubresource = full.dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1}; full.extent = {width, height, 1};
        vkCmdResolveImage(command, target.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, resolved.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &full);
        barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT | VK_ACCESS_TRANSFER_READ_BIT,
                VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_READ_BIT | VK_ACCESS_TRANSFER_WRITE_BIT);
        // Resolve from the same source again: the first resolve must preserve all samples.
        VkImageResolve partial = full; partial.srcOffset = {2, 2, 0}; partial.dstOffset = {4, 4, 0}; partial.extent = {8, 8, 1};
        vkCmdResolveImage(command, target.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, partialResolved.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &partial);
        for (auto& transition : transitions) {
            transition.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL; transition.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
            transition.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; transition.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        }
        vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 2, transitions);
    }
    VkBufferImageCopy copy{}; copy.bufferOffset = guard; copy.bufferRowLength = rowBytes / 4;
    copy.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1}; copy.imageExtent = {width, height, 1};
    vkCmdCopyImageToBuffer(command, resolveMode ? resolved.image : image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback.buffer, 1, &copy);
    if (resolveMode == 2) vkCmdCopyImageToBuffer(command, partialResolved.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, partialReadback.buffer, 1, &copy);
    barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
    if (occlusion) {
        uint64_t unavailable[queryCount * 3]; std::fill(std::begin(unavailable), std::end(unavailable), querySentinel);
        require(vkGetQueryPoolResults(c.device, queryPool, 0, queryCount, sizeof(unavailable), unavailable, queryStride,
                VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WITH_AVAILABILITY_BIT) == VK_NOT_READY, "unsubmitted occlusion queries not ready");
        for (uint32_t query = 0; query < queryCount; ++query)
            require(unavailable[query * 3] == querySentinel && unavailable[query * 3 + 1] == 0 && unavailable[query * 3 + 2] == querySentinel,
                    "unavailable occlusion data/padding preserved with availability zero");
    }
    c.submit(command);
    if (occlusion) {
        uint64_t host[queryCount * 3]; std::fill(std::begin(host), std::end(host), querySentinel);
        VK_CHECK(vkGetQueryPoolResults(c.device, queryPool, 0, queryCount, sizeof(host), host, queryStride,
            VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WITH_AVAILABILITY_BIT | VK_QUERY_RESULT_WAIT_BIT));
        require(host[0] == 0 && host[3] == 0, "empty and helper-only occlusion queries return zero");
        require(c.preciseOcclusionSupported ? host[6] == width * height : host[6] != 0,
                "query accumulates both half-screen draws across clear/pass restart");
        for (uint32_t query = 0; query < queryCount; ++query)
            require(host[query * 3 + 1] != 0 && host[query * 3 + 2] == querySentinel, "completed occlusion availability/padding");
        const auto* gpu = static_cast<const uint8_t*>(queryResults.bytes);
        for (uint32_t i = 0; i < queryResults.size; ++i) {
            uint8_t expected = i >= queryGuard && i < queryGuard + queryBytes ? reinterpret_cast<const uint8_t*>(host)[i - queryGuard] : 0xA5;
            require(gpu[i] == expected, "GPU/host occlusion result/availability/guard mismatch at " + std::to_string(i));
        }
        const uint64_t packedHost[queryCount] = {host[0], host[3], host[6]};
        const auto* packed = static_cast<const uint8_t*>(packedQueryResults.bytes);
        for (uint32_t i = 0; i < packedQueryResults.size; ++i) {
            const uint8_t expected = i >= queryGuard && i < queryGuard + sizeof(packedHost)
                ? reinterpret_cast<const uint8_t*>(packedHost)[i - queryGuard] : 0xA5;
            require(packed[i] == expected, "packed occlusion result/guard mismatch at " + std::to_string(i));
        }
    }
    if (sampled) {
        // Re-submit unchanged Vulkan commands after each GPU retirement. Native
        // recordings are distinct; descriptor preparation and ownership differ.
        for (unsigned recording = 0; recording < 4; ++recording) {
            std::memset(readback.bytes, 0xA5, readback.size);
            c.submit(command, false);
            const auto* repeated = static_cast<const uint8_t*>(readback.bytes);
            for (uint32_t i = 0; i < readback.size; ++i) {
                bool pixel = i >= guard && i < guard + rowBytes * height && (i - guard) % rowBytes < width * 4;
                const uint8_t color[4] = {64, 128, 191, 255};
                uint8_t expected = 0xA5;
                if (pixel) {
                    uint32_t channel = (i - guard) % 4, x = ((i - guard) % rowBytes) / 4;
                    expected = color[channel];
                    if (clearRestore && x >= width / 2) {
                        const uint8_t red[4] = {255, 0, 0, 255}, blue[4] = {0, 0, 255, 255};
                        expected = x < width * 3 / 4 ? red[channel] : blue[channel];
                    }
                }
                require(pixel ? std::abs(int(repeated[i]) - int(expected)) <= 1 : repeated[i] == expected,
                        "persistent sampled descriptors preserve new-recording pixels/padding");
            }
        }
    }
    const uint8_t expected[4] = {64, 128, 191, 255}; const auto* bytes = static_cast<const uint8_t*>(readback.bytes);
    for (uint32_t i = 0; i < readback.size; ++i) {
        bool pixel = i >= guard && i < guard + rowBytes * height && (i - guard) % rowBytes < width * 4;
        if (pixel) {
            uint32_t channel = (i - guard) % 4, x = ((i - guard) % rowBytes) / 4;
            uint8_t value = expected[channel];
            if (clearRestore && x >= width / 2) {
                const uint8_t red[4] = {255, 0, 0, 255}, blue[4] = {0, 0, 255, 255};
                value = x < width * 3 / 4 ? red[channel] : blue[channel];
            }
            int delta = int(bytes[i]) - value;
            require(delta >= -1 && delta <= 1, "Vulkan indexed render/clear restoration pixel mismatch at " + std::to_string(i));
        }
        else require(bytes[i] == 0xA5, "Vulkan render readback padding/guard mismatch at " + std::to_string(i));
    }
    if (resolveMode == 2) {
        const auto* partialBytes = static_cast<const uint8_t*>(partialReadback.bytes);
        for (uint32_t i = 0; i < partialReadback.size; ++i) {
            bool pixel = i >= guard && i < guard + rowBytes * height && (i - guard) % rowBytes < width * 4;
            if (!pixel) { require(partialBytes[i] == 0xA5, "partial resolve readback guard"); continue; }
            uint32_t x = ((i - guard) % rowBytes) / 4, y = (i - guard) / rowBytes, channel = (i - guard) % 4;
            const uint8_t blue[4] = {0, 0, 255, 255};
            uint8_t value = x >= 4 && x < 12 && y >= 4 && y < 12 ? expected[channel] : blue[channel];
            require(std::abs(int(partialBytes[i]) - int(value)) <= 1, "partial resolve/source preservation mismatch at " + std::to_string(i));
        }
    }
    }
}

void mipmapBlit(Context& c) {
    constexpr uint32_t width = 8, levels = 4, rowBytes = 256, levelBytes = rowBytes * width, guard = 256;
    VkFormatProperties properties{}; vkGetPhysicalDeviceFormatProperties(c.physical, VK_FORMAT_R8G8B8A8_UNORM, &properties);
    require((properties.optimalTilingFeatures & (VK_FORMAT_FEATURE_BLIT_SRC_BIT | VK_FORMAT_FEATURE_BLIT_DST_BIT |
            VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT)) == (VK_FORMAT_FEATURE_BLIT_SRC_BIT | VK_FORMAT_FEATURE_BLIT_DST_BIT |
            VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT), "RGBA8 linear mipmap blit support");
    auto image = c.image(width, width, VK_FORMAT_R8G8B8A8_UNORM,
                         VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT,
                         VK_SAMPLE_COUNT_1_BIT, VK_IMAGE_ASPECT_COLOR_BIT, levels);
    auto upload = c.buffer(width * width * 4, VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
    auto readback = c.buffer(guard * 2 + levelBytes * levels, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    auto* input = static_cast<uint8_t*>(upload.bytes);
    for (uint32_t y = 0; y < width; ++y) for (uint32_t x = 0; x < width; ++x) {
        const uint8_t pixel[4] = {uint8_t(16 + 24 * x), uint8_t(24 + 20 * y), uint8_t(40 + 8 * (x + y)), 255};
        std::memcpy(input + (y * width + x) * 4, pixel, sizeof(pixel));
    }
    std::memset(readback.bytes, 0xA5, readback.size);
    VkCommandBuffer command = c.begin();
    VkImageMemoryBarrier transition{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER}; transition.image = image.image;
    transition.srcQueueFamilyIndex = transition.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    transition.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, levels, 0, 1};
    transition.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED; transition.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    transition.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &transition);
    VkBufferImageCopy uploadRegion{}; uploadRegion.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1}; uploadRegion.imageExtent = {width, width, 1};
    vkCmdCopyBufferToImage(command, upload.buffer, image.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &uploadRegion);
    transition.subresourceRange.levelCount = 1; transition.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    transition.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    transition.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; transition.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    for (uint32_t level = 0; level < levels; ++level) {
        transition.subresourceRange.baseMipLevel = level;
        vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &transition);
        if (level + 1 == levels) break;
        VkImageBlit blit{}; blit.srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, level, 0, 1};
        blit.dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, level + 1, 0, 1};
        blit.srcOffsets[1] = {int32_t(width >> level), int32_t(width >> level), 1};
        blit.dstOffsets[1] = {int32_t(width >> (level + 1)), int32_t(width >> (level + 1)), 1};
        vkCmdBlitImage(command, image.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                       image.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &blit, VK_FILTER_LINEAR);
    }
    VkBufferImageCopy copies[levels]{};
    for (uint32_t level = 0; level < levels; ++level) {
        copies[level].bufferOffset = guard + level * levelBytes; copies[level].bufferRowLength = rowBytes / 4;
        copies[level].imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, level, 0, 1};
        copies[level].imageExtent = {width >> level, width >> level, 1};
    }
    vkCmdCopyImageToBuffer(command, image.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback.buffer, levels, copies);
    barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
    c.submit(command);
    const auto* bytes = static_cast<const uint8_t*>(readback.bytes);
    for (uint32_t i = 0; i < readback.size; ++i) {
        uint32_t level = i >= guard ? (i - guard) / levelBytes : levels;
        uint32_t local = i >= guard ? (i - guard) % levelBytes : 0;
        bool pixel = level < levels && local / rowBytes < (width >> level) && local % rowBytes < (width >> level) * 4;
        if (!pixel) { require(bytes[i] == 0xA5, "mipmap padding/guard mismatch at " + std::to_string(i)); continue; }
        uint32_t x = (local % rowBytes) / 4, y = local / rowBytes, scale = 1u << level;
        const int expected[4] = {int(16 + 24 * scale * x + 12 * (scale - 1)),
            int(24 + 20 * scale * y + 10 * (scale - 1)), int(40 + 8 * scale * (x + y) + 8 * (scale - 1)), 255};
        require(std::abs(int(bytes[i]) - expected[local % 4]) <= 1,
                "linear mipmap pixel mismatch at level " + std::to_string(level) + " byte " + std::to_string(i));
    }
}

void depthStencilClear(Context& c) {
    constexpr uint32_t width = 8, height = 8, rowBytes = 256, guard = 256;
    auto image = c.image(width, height, VK_FORMAT_D32_SFLOAT_S8_UINT,
        VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        VK_SAMPLE_COUNT_1_BIT, VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT);
    auto depth = c.buffer(guard * 2 + rowBytes * height, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    auto stencil = c.buffer(guard * 2 + rowBytes * height, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    std::memset(depth.bytes, 0xA5, depth.size); std::memset(stencil.bytes, 0xA5, stencil.size);
    VkCommandBuffer command = c.begin();
    VkImageMemoryBarrier transition{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER}; transition.image = image.image;
    transition.srcQueueFamilyIndex = transition.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    transition.subresourceRange = {VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT, 0, 1, 0, 1};
    transition.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED; transition.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    transition.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &transition);
    VkClearDepthStencilValue value{0.375f, 93};
    vkCmdClearDepthStencilImage(command, image.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &value, 1, &transition.subresourceRange);
    transition.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL; transition.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    transition.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; transition.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &transition);
    VkBufferImageCopy copy{}; copy.bufferOffset = guard; copy.bufferRowLength = rowBytes / 4;
    copy.imageSubresource = {VK_IMAGE_ASPECT_DEPTH_BIT, 0, 0, 1}; copy.imageExtent = {width, height, 1};
    vkCmdCopyImageToBuffer(command, image.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, depth.buffer, 1, &copy);
    copy.bufferRowLength = rowBytes; copy.imageSubresource.aspectMask = VK_IMAGE_ASPECT_STENCIL_BIT;
    vkCmdCopyImageToBuffer(command, image.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, stencil.buffer, 1, &copy);
    barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
    c.submit(command);
    const uint8_t* depthPattern = reinterpret_cast<const uint8_t*>(&value.depth);
    for (uint32_t i = 0; i < depth.size; ++i) {
        bool inRows = i >= guard && i < guard + rowBytes * height;
        uint32_t column = inRows ? (i - guard) % rowBytes : rowBytes;
        uint8_t expectedDepth = column < width * 4 ? depthPattern[column % 4] : 0xA5;
        uint8_t expectedStencil = column < width ? 93 : 0xA5;
        require(static_cast<const uint8_t*>(depth.bytes)[i] == expectedDepth, "depth clear result/guard mismatch at " + std::to_string(i));
        require(static_cast<const uint8_t*>(stencil.bytes)[i] == expectedStencil, "stencil clear result/guard mismatch at " + std::to_string(i));
    }
}

void depthStencilTransfer(Context& c, uint32_t mode) {
    constexpr uint32_t width = 8, height = 8, rowBytes = 256, guard = 256;
    const VkClearDepthStencilValue sourceValue{0.375f, 93}, destinationValue{0.75f, 17};
    const VkFormat formats[2] = {VK_FORMAT_D32_SFLOAT, VK_FORMAT_S8_UINT};
    for (uint32_t iteration = 0; iteration < (mode == 0 ? 2u : 1u); ++iteration) {
        VkFormat format = mode ? VK_FORMAT_D32_SFLOAT_S8_UINT : formats[iteration];
        VkImageAspectFlags aspects = mode ? VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT :
            (iteration ? VK_IMAGE_ASPECT_STENCIL_BIT : VK_IMAGE_ASPECT_DEPTH_BIT);
        if (mode == 2) {
            VkFormatProperties properties{}; vkGetPhysicalDeviceFormatProperties(c.physical, format, &properties);
            require((properties.optimalTilingFeatures & (VK_FORMAT_FEATURE_BLIT_SRC_BIT | VK_FORMAT_FEATURE_BLIT_DST_BIT)) ==
                    (VK_FORMAT_FEATURE_BLIT_SRC_BIT | VK_FORMAT_FEATURE_BLIT_DST_BIT), "combined depth/stencil blit support");
        }
        VkImageUsageFlags usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
        auto source = c.image(width, height, format, usage, VK_SAMPLE_COUNT_1_BIT, aspects);
        auto destination = c.image(width, height, format, usage, VK_SAMPLE_COUNT_1_BIT, aspects);
        Buffer depth{}, stencil{};
        if (aspects & VK_IMAGE_ASPECT_DEPTH_BIT) { depth = c.buffer(guard * 2 + rowBytes * height, VK_BUFFER_USAGE_TRANSFER_DST_BIT); std::memset(depth.bytes, 0xA5, depth.size); }
        if (aspects & VK_IMAGE_ASPECT_STENCIL_BIT) { stencil = c.buffer(guard * 2 + rowBytes * height, VK_BUFFER_USAGE_TRANSFER_DST_BIT); std::memset(stencil.bytes, 0xA5, stencil.size); }
        VkCommandBuffer command = c.begin();
        VkImageMemoryBarrier transitions[2]{};
        for (uint32_t i = 0; i < 2; ++i) {
            auto& transition = transitions[i]; transition.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
            transition.image = i ? destination.image : source.image;
            transition.srcQueueFamilyIndex = transition.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
            transition.subresourceRange = {aspects, 0, 1, 0, 1};
            transition.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED; transition.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
            transition.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        }
        vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 2, transitions);
        vkCmdClearDepthStencilImage(command, source.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &sourceValue, 1, &transitions[0].subresourceRange);
        vkCmdClearDepthStencilImage(command, destination.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &destinationValue, 1, &transitions[1].subresourceRange);
        transitions[0].oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL; transitions[0].newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        transitions[0].srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; transitions[0].dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, transitions);
        barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT,
                VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_READ_BIT | VK_ACCESS_TRANSFER_WRITE_BIT);
        for (VkImageAspectFlagBits aspect : {VK_IMAGE_ASPECT_DEPTH_BIT, VK_IMAGE_ASPECT_STENCIL_BIT}) {
            if (!(aspects & aspect)) continue;
            VkOffset3D origin = !mode ? VkOffset3D{2, 2, 0} :
                (aspect == VK_IMAGE_ASPECT_DEPTH_BIT ? VkOffset3D{0, 0, 0} : VkOffset3D{4, 4, 0});
            if (mode == 2) {
                VkImageBlit blit{}; blit.srcSubresource = blit.dstSubresource = {aspect, 0, 0, 1};
                blit.srcOffsets[1] = {int32_t(width), int32_t(height), 1};
                blit.dstOffsets[0] = origin; blit.dstOffsets[1] = {origin.x + 4, origin.y + 4, 1};
                vkCmdBlitImage(command, source.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                               destination.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &blit, VK_FILTER_NEAREST);
            } else {
                VkImageCopy copy{}; copy.srcSubresource = copy.dstSubresource = {aspect, 0, 0, 1};
                copy.srcOffset = {1, 1, 0}; copy.dstOffset = origin; copy.extent = {4, 4, 1};
                vkCmdCopyImage(command, source.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                               destination.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copy);
            }
            barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT,
                    VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_READ_BIT | VK_ACCESS_TRANSFER_WRITE_BIT);
        }
        transitions[1].oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL; transitions[1].newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        transitions[1].srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; transitions[1].dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &transitions[1]);
        VkBufferImageCopy read{}; read.bufferOffset = guard; read.imageExtent = {width, height, 1};
        if (depth.buffer) {
            read.bufferRowLength = rowBytes / 4; read.imageSubresource = {VK_IMAGE_ASPECT_DEPTH_BIT, 0, 0, 1};
            vkCmdCopyImageToBuffer(command, destination.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, depth.buffer, 1, &read);
        }
        if (stencil.buffer) {
            read.bufferRowLength = rowBytes; read.imageSubresource = {VK_IMAGE_ASPECT_STENCIL_BIT, 0, 0, 1};
            vkCmdCopyImageToBuffer(command, destination.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, stencil.buffer, 1, &read);
        }
        barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
        c.submit(command);
        for (uint32_t i = 0; i < guard * 2 + rowBytes * height; ++i) {
            bool inRows = i >= guard && i < guard + rowBytes * height;
            uint32_t column = inRows ? (i - guard) % rowBytes : rowBytes, y = inRows ? (i - guard) / rowBytes : height;
            if (depth.buffer) {
                uint8_t expected = 0xA5;
                if (column < width * 4) {
                    uint32_t x = column / 4;
                    bool copied = mode ? x < 4 && y < 4 : x >= 2 && x < 6 && y >= 2 && y < 6;
                    const float& value = copied ? sourceValue.depth : destinationValue.depth;
                    expected = reinterpret_cast<const uint8_t*>(&value)[column % 4];
                }
                require(static_cast<const uint8_t*>(depth.bytes)[i] == expected, "depth transfer value/untouched aspect/guard mismatch at " + std::to_string(i));
            }
            if (stencil.buffer) {
                uint8_t expected = 0xA5;
                if (column < width) {
                    bool copied = mode ? column >= 4 && y >= 4 : column >= 2 && column < 6 && y >= 2 && y < 6;
                    expected = copied ? sourceValue.stencil : destinationValue.stencil;
                }
                require(static_cast<const uint8_t*>(stencil.bytes)[i] == expected, "stencil transfer value/untouched aspect/guard mismatch at " + std::to_string(i));
            }
        }
    }
}
} // namespace

// No-fence/no-semaphore submissions omit the native completion marker. A later
// fence-only submission must still cover them, and idle must account for every
// pending batch, including an empty batch whose own feedback can arrive early.
void unfencedSubmissionRetirement(Context& c) {
    auto output=c.buffer(256,VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    VkFenceCreateInfo info{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO}; VkFence fence;
    VK_CHECK(vkCreateFence(c.device,&info,nullptr,&fence));
    c.cleanup.push_back([&c,fence]{vkDestroyFence(c.device,fence,nullptr);});
    for(unsigned round=0;round<2;++round) {
        std::memset(output.bytes,0xa5,output.size);
        const uint32_t value=0x12340000+round;
        auto command=c.begin();vkCmdFillBuffer(command,output.buffer,16,224,value);
        barrier(command,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_TRANSFER_WRITE_BIT,VK_PIPELINE_STAGE_HOST_BIT,VK_ACCESS_HOST_READ_BIT);
        VK_CHECK(vkEndCommandBuffer(command));
        VkSubmitInfo work{VK_STRUCTURE_TYPE_SUBMIT_INFO};work.commandBufferCount=1;work.pCommandBuffers=&command;
        VkSubmitInfo empty{VK_STRUCTURE_TYPE_SUBMIT_INFO};c.inFlight=true;
        VK_CHECK(vkQueueSubmit(c.queue,1,&work,VK_NULL_HANDLE));
        VK_CHECK(vkQueueSubmit(c.queue,1,&empty,VK_NULL_HANDLE));
        if(round==0) {
            VK_CHECK(vkQueueSubmit(c.queue,1,&empty,fence));
            VK_CHECK(vkWaitForFences(c.device,1,&fence,VK_TRUE,10000000000ull));
        } else VK_CHECK(vkQueueWaitIdle(c.queue));
        const auto* words=static_cast<const uint32_t*>(output.bytes);
        for(unsigned i=0;i<64;++i)require(words[i]==(i<4||i>=60?0xa5a5a5a5:value),"unfenced submission prior-work coverage");
        VK_CHECK(vkQueueWaitIdle(c.queue));c.inFlight=false;
    }
    c.nativeAfter=c.counter(c.queue);
    require(c.nativeAfter>=c.nativeBefore+5,"both unfenced/empty batches retire through native feedback");
}

// A merged work + signal-only pair remains a single native completion unit.
// Fixtures use real semaphores, not only a metadata counter or empty commands.
static VkSemaphore fusionSemaphore(Context& c, bool timeline, uint64_t initial=0) {
    VkSemaphoreTypeCreateInfo type{VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO};
    type.semaphoreType=VK_SEMAPHORE_TYPE_TIMELINE;type.initialValue=initial;
    VkSemaphoreCreateInfo info{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};if(timeline)info.pNext=&type;
    VkSemaphore semaphore;VK_CHECK(vkCreateSemaphore(c.device,&info,nullptr,&semaphore));
    c.cleanup.push_back([&c,semaphore]{vkDestroySemaphore(c.device,semaphore,nullptr);});return semaphore;
}
static VkFence fusionFence(Context& c) {
    VkFenceCreateInfo info{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};VkFence fence;
    VK_CHECK(vkCreateFence(c.device,&info,nullptr,&fence));
    c.cleanup.push_back([&c,fence]{vkDestroyFence(c.device,fence,nullptr);});return fence;
}
struct FusionHostGate {
    VkDevice device;VkSemaphore semaphore;uint64_t finalValue;
    ~FusionHostGate() {
        uint64_t value=0;
        if(vkGetSemaphoreCounterValue(device,semaphore,&value)==VK_SUCCESS&&value<finalValue) {
            VkSemaphoreSignalInfo signal{VK_STRUCTURE_TYPE_SEMAPHORE_SIGNAL_INFO};signal.semaphore=semaphore;signal.value=finalValue;
            (void)vkSignalSemaphore(device,&signal);
        }
    }
};
static void signalFusionGate(Context& c,VkSemaphore semaphore,uint64_t value) {
    VkSemaphoreSignalInfo signal{VK_STRUCTURE_TYPE_SEMAPHORE_SIGNAL_INFO};signal.semaphore=semaphore;signal.value=value;
    VK_CHECK(vkSignalSemaphore(c.device,&signal));
}

void fusedMesaSignalSubmits(Context& c) {
    require(c.timelineSupported&&c.secondQueue,"timeline and second queue available for merged submission proof");
    auto gate=fusionSemaphore(c,true),done=fusionSemaphore(c,true),binary=fusionSemaphore(c,false);
    FusionHostGate release{c.device,gate,2};
    auto output=c.buffer(256,VK_BUFFER_USAGE_TRANSFER_SRC_BIT|VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    auto copied=c.buffer(256,VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    VkPipelineStageFlags stage=VK_PIPELINE_STAGE_TRANSFER_BIT;
    for(uint64_t cycle=1;cycle<=2;++cycle) {
        std::memset(output.bytes,0xa5,output.size);std::memset(copied.bytes,0xa5,copied.size);
        auto prior=c.begin();vkCmdFillBuffer(prior,output.buffer,16,96,uint32_t(0x10100000+cycle));
        VK_CHECK(vkEndCommandBuffer(prior));
        auto work=c.begin();vkCmdFillBuffer(work,output.buffer,128,112,uint32_t(0x20200000+cycle));
        barrier(work,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_TRANSFER_WRITE_BIT,VK_PIPELINE_STAGE_HOST_BIT,VK_ACCESS_HOST_READ_BIT);
        VK_CHECK(vkEndCommandBuffer(work));
        auto consumer=c.begin(true);VkBufferCopy copy{16,16,224};vkCmdCopyBuffer(consumer,output.buffer,copied.buffer,1,&copy);
        barrier(consumer,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_TRANSFER_WRITE_BIT,VK_PIPELINE_STAGE_HOST_BIT,VK_ACCESS_HOST_READ_BIT);
        VK_CHECK(vkEndCommandBuffer(consumer));
        auto fence=fusionFence(c),consumerFence=fusionFence(c);
        uint64_t before=c.counter(c.queue),secondBefore=c.counter(c.secondQueue);
        VkSubmitInfo earlier{VK_STRUCTURE_TYPE_SUBMIT_INFO};earlier.commandBufferCount=1;earlier.pCommandBuffers=&prior;
        c.inFlight=true;VK_CHECK(vkQueueSubmit(c.queue,1,&earlier,VK_NULL_HANDLE));
        VkTimelineSemaphoreSubmitInfo waits{VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO};
        waits.waitSemaphoreValueCount=1;waits.pWaitSemaphoreValues=&cycle;
        VkSemaphore signals[2]={binary,done};uint64_t values[2]={0,cycle};
        VkTimelineSemaphoreSubmitInfo signalsInfo{VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO};
        signalsInfo.signalSemaphoreValueCount=2;signalsInfo.pSignalSemaphoreValues=values;
        VkSubmitInfo pair[2]={{VK_STRUCTURE_TYPE_SUBMIT_INFO},{VK_STRUCTURE_TYPE_SUBMIT_INFO}};
        pair[0].pNext=&waits;pair[0].waitSemaphoreCount=1;pair[0].pWaitSemaphores=&gate;pair[0].pWaitDstStageMask=&stage;
        pair[0].commandBufferCount=1;pair[0].pCommandBuffers=&work;
        pair[1].pNext=&signalsInfo;pair[1].signalSemaphoreCount=2;pair[1].pSignalSemaphores=signals;
        VK_CHECK(vkQueueSubmit(c.queue,2,pair,fence));
        // Submission constructors must own the copied arrays before async work.
        std::memset(pair,0,sizeof(pair));std::memset(values,0,sizeof(values));std::memset(signals,0,sizeof(signals));
        require(vkWaitForFences(c.device,1,&fence,VK_TRUE,20000000)==VK_TIMEOUT&&vkGetFenceStatus(c.device,fence)==VK_NOT_READY,
                "merged final fence remains blocked by original work wait");
        uint64_t observed=0;VK_CHECK(vkGetSemaphoreCounterValue(c.device,done,&observed));require(observed==cycle-1,"merged signal cannot overtake work wait");
        signalFusionGate(c,gate,cycle);
        VK_CHECK(vkWaitForFences(c.device,1,&fence,VK_TRUE,10000000000ull));
        VK_CHECK(vkGetSemaphoreCounterValue(c.device,done,&observed));require(observed==cycle,"mixed timeline signal value preserved");
        const auto* words=static_cast<const uint32_t*>(output.bytes);
        for(uint32_t i=0;i<64;++i)require(words[i]==(i>=4&&i<28?uint32_t(0x10100000+cycle):i>=32&&i<60?uint32_t(0x20200000+cycle):0xa5a5a5a5),
                "final fence covers earlier queue work and merged work before waitIdle");
        VkSubmitInfo read{VK_STRUCTURE_TYPE_SUBMIT_INFO};read.waitSemaphoreCount=1;read.pWaitSemaphores=&binary;read.pWaitDstStageMask=&stage;
        read.commandBufferCount=1;read.pCommandBuffers=&consumer;
        VK_CHECK(vkQueueSubmit(c.secondQueue,1,&read,consumerFence));
        VK_CHECK(vkWaitForFences(c.device,1,&consumerFence,VK_TRUE,10000000000ull));
        require(std::memcmp(output.bytes,copied.bytes,256)==0,"binary generation publishes all work to second queue with guards");
        VK_CHECK(vkQueueWaitIdle(c.queue));VK_CHECK(vkQueueWaitIdle(c.secondQueue));c.inFlight=false;
        require(c.counter(c.queue)==before+2,"prior submission plus fused pair are exactly two native batches");
        require(c.counter(c.secondQueue)==secondBefore+1,"binary consumer completes once per generation");
    }
    c.nativeAfter=c.counter(c.queue);
}

void fusedSubmitLaterFence(Context& c) {
    require(c.timelineSupported,"timeline available");
    auto done=fusionSemaphore(c,true),gate=fusionSemaphore(c,true);FusionHostGate release{c.device,gate,1};
    auto output=c.buffer(256,VK_BUFFER_USAGE_TRANSFER_DST_BIT);std::memset(output.bytes,0xa5,output.size);
    auto work=c.begin();vkCmdFillBuffer(work,output.buffer,16,224,0x13579bdf);
    barrier(work,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_TRANSFER_WRITE_BIT,VK_PIPELINE_STAGE_HOST_BIT,VK_ACCESS_HOST_READ_BIT);VK_CHECK(vkEndCommandBuffer(work));
    uint64_t value=1;VkPipelineStageFlags stage=VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
    VkTimelineSemaphoreSubmitInfo signal{VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO},wait{VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO};
    signal.signalSemaphoreValueCount=1;signal.pSignalSemaphoreValues=&value;wait.waitSemaphoreValueCount=1;wait.pWaitSemaphoreValues=&value;
    VkSubmitInfo submits[3]={{VK_STRUCTURE_TYPE_SUBMIT_INFO},{VK_STRUCTURE_TYPE_SUBMIT_INFO},{VK_STRUCTURE_TYPE_SUBMIT_INFO}};
    submits[0].commandBufferCount=1;submits[0].pCommandBuffers=&work;
    submits[1].pNext=&signal;submits[1].signalSemaphoreCount=1;submits[1].pSignalSemaphores=&done;
    submits[2].pNext=&wait;submits[2].waitSemaphoreCount=1;submits[2].pWaitSemaphores=&gate;submits[2].pWaitDstStageMask=&stage;
    auto fence=fusionFence(c);uint64_t before=c.counter(c.queue);c.inFlight=true;
    VK_CHECK(vkQueueSubmit(c.queue,3,submits,fence));
    VkSemaphoreWaitInfo waitDone{VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO};waitDone.semaphoreCount=1;waitDone.pSemaphores=&done;waitDone.pValues=&value;
    VK_CHECK(vkWaitSemaphores(c.device,&waitDone,10000000000ull));
    require(vkWaitForFences(c.device,1,&fence,VK_TRUE,20000000)==VK_TIMEOUT&&vkGetFenceStatus(c.device,fence)==VK_NOT_READY,
            "last-element fence is not moved to the earlier fused pair");
    signalFusionGate(c,gate,1);VK_CHECK(vkWaitForFences(c.device,1,&fence,VK_TRUE,10000000000ull));
    const auto* words=static_cast<const uint32_t*>(output.bytes);
    for(uint32_t i=0;i<64;++i)require(words[i]==(i>=4&&i<60?0x13579bdfu:0xa5a5a5a5u),"later fence data and guards");
    VK_CHECK(vkQueueWaitIdle(c.queue));c.inFlight=false;
    c.nativeAfter=c.counter(c.queue);require(c.nativeAfter==before+2,"pair plus separate final wait are exactly two native batches");
}

void signalSubmitFusionExclusions(Context& c) {
    require(c.timelineSupported,"timeline available");
    auto output=c.buffer(256,VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    // Each case deliberately keeps two native batches. Conditions cannot be
    // inferred solely from the final successful fence, so count actual feedback.
    for(uint32_t scenario=0;scenario<6;++scenario) {
        auto done=fusionSemaphore(c,true),intermediate=fusionSemaphore(c,true),ready=fusionSemaphore(c,true,1);
        auto fence=fusionFence(c);uint64_t value=1;VkPipelineStageFlags stage=VK_PIPELINE_STAGE_TRANSFER_BIT;
        std::memset(output.bytes,0xa5,output.size);
        auto work=c.begin();vkCmdFillBuffer(work,output.buffer,16,224,0xcafe0000+scenario);
        barrier(work,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_TRANSFER_WRITE_BIT,VK_PIPELINE_STAGE_HOST_BIT,VK_ACCESS_HOST_READ_BIT);VK_CHECK(vkEndCommandBuffer(work));
        VkTimelineSemaphoreSubmitInfo signals{VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO};signals.signalSemaphoreValueCount=1;signals.pSignalSemaphoreValues=&value;
        VkTimelineSemaphoreSubmitInfo firstSignal=signals;
        VkProtectedSubmitInfo protectedInfo{VK_STRUCTURE_TYPE_PROTECTED_SUBMIT_INFO};protectedInfo.protectedSubmit=VK_FALSE;
        VkSubmitInfo pair[2]={{VK_STRUCTURE_TYPE_SUBMIT_INFO},{VK_STRUCTURE_TYPE_SUBMIT_INFO}};
        pair[0].commandBufferCount=1;pair[0].pCommandBuffers=&work;
        pair[1].pNext=&signals;pair[1].signalSemaphoreCount=1;pair[1].pSignalSemaphores=&done;
        if(scenario==0) {pair[0].pNext=&firstSignal;pair[0].signalSemaphoreCount=1;pair[0].pSignalSemaphores=&intermediate;}
        if(scenario==1) {pair[1].waitSemaphoreCount=1;pair[1].pWaitSemaphores=&ready;pair[1].pWaitDstStageMask=&stage;signals.waitSemaphoreValueCount=1;signals.pWaitSemaphoreValues=&value;}
        if(scenario==2)pair[0].pNext=&protectedInfo;
        if(scenario==3)signals.pNext=&protectedInfo;
        if(scenario==4) {pair[0].commandBufferCount=0;pair[0].pCommandBuffers=nullptr;}
        uint64_t before=c.counter(c.queue);c.inFlight=true;
        if(scenario==5) {VK_CHECK(vkQueueSubmit(c.queue,1,pair,VK_NULL_HANDLE));VK_CHECK(vkQueueSubmit(c.queue,1,pair+1,fence));}
        else VK_CHECK(vkQueueSubmit(c.queue,2,pair,fence));
        VK_CHECK(vkWaitForFences(c.device,1,&fence,VK_TRUE,10000000000ull));
        uint64_t observed=0;VK_CHECK(vkGetSemaphoreCounterValue(c.device,done,&observed));require(observed==1,"excluded pair still signals final timeline");
        if(scenario==0){VK_CHECK(vkGetSemaphoreCounterValue(c.device,intermediate,&observed));require(observed==1,"observable intermediate signal preserved");}
        const auto* words=static_cast<const uint32_t*>(output.bytes);
        for(uint32_t i=0;i<64;++i)require(words[i]==(scenario!=4&&i>=4&&i<60?0xcafe0000+scenario:0xa5a5a5a5),"excluded pair data and empty-submission guards");
        VK_CHECK(vkQueueWaitIdle(c.queue));c.inFlight=false;
        require(c.counter(c.queue)==before+2,"intermediate signal/wait/pNext/empty/cross-call exclusion retains two native batches");
    }
    c.nativeAfter=c.counter(c.queue);
}

void computeCompatible(Context& c, bool helperRestore = false, unsigned dependency = 0) {
    constexpr uint32_t count = 64;
    uint32_t offset = uint32_t(std::max<VkDeviceSize>(256, c.properties.limits.minStorageBufferOffsetAlignment));
    auto output = c.buffer(offset + count * 4 + 64, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    auto params = c.buffer(16, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
    std::memset(output.bytes, 0xA5, output.size); std::memset(params.bytes, 0, params.size);
    *static_cast<uint32_t*>(params.bytes) = 19;
    if (dependency == 2) {
        for (uint32_t i = 0; i < count; ++i) { static_cast<uint32_t*>(output.bytes)[offset / 4 + i] = i * 7 + 19; }
    }
    auto observed = c.buffer(count * 4 + 64, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
    std::memset(observed.bytes, 0xA5, observed.size);
    unsigned bindingCount = dependency == 2 ? 3 : 2;
    VkDescriptorSetLayoutBinding bindings[3] = {
        {0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr},
        {1, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr},
        {2, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr}};
    VkDescriptorSetLayoutCreateInfo setInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO}; setInfo.bindingCount = bindingCount; setInfo.pBindings = bindings;
    VkDescriptorSetLayout setLayout; VK_CHECK(vkCreateDescriptorSetLayout(c.device, &setInfo, nullptr, &setLayout));
    c.cleanup.push_back([&, setLayout] { vkDestroyDescriptorSetLayout(c.device, setLayout, nullptr); });
    VkPushConstantRange push{VK_SHADER_STAGE_COMPUTE_BIT, 0, 4};
    VkPipelineLayoutCreateInfo layoutInfo{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO}; layoutInfo.setLayoutCount = 1; layoutInfo.pSetLayouts = &setLayout;
    layoutInfo.pushConstantRangeCount = 1; layoutInfo.pPushConstantRanges = &push;
    VkPipelineLayout layout; VK_CHECK(vkCreatePipelineLayout(c.device, &layoutInfo, nullptr, &layout));
    c.cleanup.push_back([&, layout] { vkDestroyPipelineLayout(c.device, layout, nullptr); });
    VkComputePipelineCreateInfo pipelineInfo{VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO}; pipelineInfo.layout = layout;
    pipelineInfo.stage = {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, nullptr, 0, VK_SHADER_STAGE_COMPUTE_BIT, c.shader(computeShader()), "main", nullptr};
    VkPipeline pipeline; VK_CHECK(vkCreateComputePipelines(c.device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &pipeline));
    c.cleanup.push_back([&, pipeline] { vkDestroyPipeline(c.device, pipeline, nullptr); });
    VkPipeline reader = VK_NULL_HANDLE;
    if (dependency == 1 || dependency == 2) {
        pipelineInfo.stage.module = c.shader(computeShader(dependency));
        VK_CHECK(vkCreateComputePipelines(c.device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &reader));
        c.cleanup.push_back([&, reader] { vkDestroyPipeline(c.device, reader, nullptr); });
    }
    VkDescriptorPoolSize sizes[3] = {{VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC, 1}, {VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1}, {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1}};
    VkDescriptorPoolCreateInfo poolInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO}; poolInfo.maxSets = 1; poolInfo.poolSizeCount = bindingCount; poolInfo.pPoolSizes = sizes;
    VkDescriptorPool pool; VK_CHECK(vkCreateDescriptorPool(c.device, &poolInfo, nullptr, &pool));
    c.cleanup.push_back([&, pool] { vkDestroyDescriptorPool(c.device, pool, nullptr); });
    VkDescriptorSetLayout compatibleSetLayout; VK_CHECK(vkCreateDescriptorSetLayout(c.device, &setInfo, nullptr, &compatibleSetLayout));
    c.cleanup.push_back([&, compatibleSetLayout] { vkDestroyDescriptorSetLayout(c.device, compatibleSetLayout, nullptr); });
    VkDescriptorSetAllocateInfo allocate{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO}; allocate.descriptorPool = pool; allocate.descriptorSetCount = 1; allocate.pSetLayouts = &compatibleSetLayout;
    VkDescriptorSet set; VK_CHECK(vkAllocateDescriptorSets(c.device, &allocate, &set));
    VkDescriptorBufferInfo bufferInfos[3] = {{output.buffer, 0, count * 4}, {params.buffer, 0, 4}, {observed.buffer, 0, count * 4}};
    VkWriteDescriptorSet writes[3]{};
    for (unsigned i = 0; i < bindingCount; ++i) { writes[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET; writes[i].dstSet = set; writes[i].dstBinding = i;
        writes[i].descriptorCount = 1; writes[i].descriptorType = bindings[i].descriptorType; writes[i].pBufferInfo = &bufferInfos[i]; }
    vkUpdateDescriptorSets(c.device, bindingCount, writes, 0, nullptr);
    VkCommandBuffer command = c.begin();
    vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 1, &offset);
    uint32_t multiplier = 7; vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &multiplier);
    if (dependency != 2) { vkCmdDispatch(command, count, 1, 1); }
    if (dependency == 1 || dependency == 2) {
        if (dependency == 1) {
            barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT,
                    VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT);
        }
        vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, reader);
        multiplier = 3; vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &multiplier);
        vkCmdDispatch(command, count, 1, 1);
        if (dependency == 2) {
            // Reader writes a DISTINCT observed buffer. The source output is only
            // read here; its later overwrite needs execution ordering (WAR), not
            // visibility. Retain observed results to make the read observable.
            barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0);
            vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
            multiplier = 11; vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &multiplier);
            vkCmdDispatch(command, count, 1, 1);
        }
    }
    if (dependency == 3) {
        // Same recording repeats exactly owned buffers; updated push data must
        // still upload. Each changed value is followed by an unchanged dispatch,
        // exercising both invalidation and reuse through the actual Vulkan path.
        for (unsigned round = 0; round < 8; ++round) {
            barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT,
                    VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT);
            multiplier = round == 7 ? 3 : 13 + round;
            vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &multiplier);
            vkCmdDispatch(command, count, 1, 1);
            barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT,
                    VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT);
            vkCmdDispatch(command, count, 1, 1);
        }
    }
    if (helperRestore) {
        barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT);
        vkCmdFillBuffer(command, output.buffer, offset, count * 4, 0xDEADBEEF);
        barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT);
        // No vkCmdBindPipeline/DescriptorSets here: the helper must not disturb
        // the Vulkan application's persistent pipeline, descriptors, or constants.
        vkCmdDispatch(command, count, 1, 1);
    }
    barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
    c.submit(command);
    const auto* actual = static_cast<const uint32_t*>(output.bytes);
    for (uint32_t i = 0; i < output.size / 4; ++i) {
        uint32_t x = i - offset / 4;
        uint32_t value = dependency == 1 ? x * 10 + 38 : dependency == 2 ? x * 11 + 19 : dependency == 3 ? x * 3 + 19 : x * 7 + 19;
        uint32_t expected = i >= offset / 4 && i < offset / 4 + count ? value : 0xA5A5A5A5;
        require(actual[i] == expected, "Vulkan descriptor/dynamic-offset/push-constant mismatch at " + std::to_string(i));
    }
    if (dependency == 2) {
        const auto* values = static_cast<const uint32_t*>(observed.bytes);
        for (uint32_t i = 0; i < observed.size / 4; ++i) {
            require(values[i] == (i < count ? i * 10 + 38 : 0xA5A5A5A5), "execution-only WAR preserves earlier observed reads and guards");
        }
    }
    if (dependency == 3) {
        // Keep the exact descriptors across distinct native recordings before
        // replacing their resources. Push/dynamic data and fresh GPU ownership
        // must remain correct when CPU preparation survives recording retirement.
        for (unsigned recording = 0; recording < 4; ++recording) {
            // Churn unrelated native buffer membership between recordings.
            // Used descriptors remain unchanged and must acquire fresh leases.
            auto unrelated = c.buffer(256, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
            std::memset(unrelated.bytes, 0xCD, unrelated.size);
            auto releaseUnrelated = std::move(c.cleanup.back());
            c.cleanup.pop_back();
            releaseUnrelated();
            command = c.begin();
            vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
            vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 1, &offset);
            multiplier = 3; vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &multiplier);
            vkCmdDispatch(command, count, 1, 1);
            barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT,
                    VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
            c.submit(command);
            for (uint32_t i = 0; i < output.size / 4; ++i) {
                uint32_t expected = i >= offset / 4 && i < offset / 4 + count ? (i - offset / 4) * 3 + 19 : 0xA5A5A5A5;
                require(actual[i] == expected, "unchanged descriptors across native recordings preserve output/guards");
            }
        }
        auto revised = c.buffer(output.size, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
        auto revisedParams = c.buffer(16, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
        std::memset(revised.bytes, 0xA5, revised.size); std::memset(revisedParams.bytes, 0, revisedParams.size);
        *static_cast<uint32_t*>(revisedParams.bytes) = 37;
        // The exact same VkDescriptorSet handle now names different live Metal
        // buffers after the first recording completes. No set-pointer cache is valid.
        bufferInfos[0].buffer = revised.buffer; bufferInfos[1].buffer = revisedParams.buffer;
        vkUpdateDescriptorSets(c.device, bindingCount, writes, 0, nullptr);
        command = c.begin();
        vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
        vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 1, &offset);
        multiplier = 5; vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &multiplier);
        vkCmdDispatch(command, count, 1, 1);
        barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT,
                VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT);
        vkCmdDispatch(command, count, 1, 1);
        barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
        c.submit(command);
        const auto* changed = static_cast<const uint32_t*>(revised.bytes);
        for (uint32_t i = 0; i < revised.size / 4; ++i) {
            uint32_t expected = i >= offset / 4 && i < offset / 4 + count ? (i - offset / 4) * 5 + 37 : 0xA5A5A5A5;
            require(changed[i] == expected, "same descriptor handle rereads revised buffer identities and guards");
            require(actual[i] == (i >= offset / 4 && i < offset / 4 + count ? (i - offset / 4) * 3 + 19 : 0xA5A5A5A5), "revised descriptors leave previous owned buffer unchanged");
        }
    }
}

void barrierRepeated(VkCommandBuffer command, VkPipelineStageFlags source, VkAccessFlags sourceAccess, VkPipelineStageFlags target, VkAccessFlags targetAccess) {
 barrier(command,source,sourceAccess,target,targetAccess);barrier(command,source,sourceAccess,target,targetAccess);
}
void computeRepeated(Context& c, bool helperRestore = false, unsigned dependency = 0) {
    constexpr uint32_t count = 64;
    uint32_t offset = uint32_t(std::max<VkDeviceSize>(256, c.properties.limits.minStorageBufferOffsetAlignment));
    auto output = c.buffer(offset + count * 4 + 64, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    auto params = c.buffer(16, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
    std::memset(output.bytes, 0xA5, output.size); std::memset(params.bytes, 0, params.size);
    *static_cast<uint32_t*>(params.bytes) = 19;
    if (dependency == 2) {
        for (uint32_t i = 0; i < count; ++i) { static_cast<uint32_t*>(output.bytes)[offset / 4 + i] = i * 7 + 19; }
    }
    auto observed = c.buffer(count * 4 + 64, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
    std::memset(observed.bytes, 0xA5, observed.size);
    unsigned bindingCount = dependency == 2 ? 3 : 2;
    VkDescriptorSetLayoutBinding bindings[3] = {
        {0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr},
        {1, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr},
        {2, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr}};
    VkDescriptorSetLayoutCreateInfo setInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO}; setInfo.bindingCount = bindingCount; setInfo.pBindings = bindings;
    VkDescriptorSetLayout setLayout; VK_CHECK(vkCreateDescriptorSetLayout(c.device, &setInfo, nullptr, &setLayout));
    c.cleanup.push_back([&, setLayout] { vkDestroyDescriptorSetLayout(c.device, setLayout, nullptr); });
    VkPushConstantRange push{VK_SHADER_STAGE_COMPUTE_BIT, 0, 4};
    VkPipelineLayoutCreateInfo layoutInfo{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO}; layoutInfo.setLayoutCount = 1; layoutInfo.pSetLayouts = &setLayout;
    layoutInfo.pushConstantRangeCount = 1; layoutInfo.pPushConstantRanges = &push;
    VkPipelineLayout layout; VK_CHECK(vkCreatePipelineLayout(c.device, &layoutInfo, nullptr, &layout));
    c.cleanup.push_back([&, layout] { vkDestroyPipelineLayout(c.device, layout, nullptr); });
    VkComputePipelineCreateInfo pipelineInfo{VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO}; pipelineInfo.layout = layout;
    pipelineInfo.stage = {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, nullptr, 0, VK_SHADER_STAGE_COMPUTE_BIT, c.shader(computeShader()), "main", nullptr};
    VkPipeline pipeline; VK_CHECK(vkCreateComputePipelines(c.device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &pipeline));
    c.cleanup.push_back([&, pipeline] { vkDestroyPipeline(c.device, pipeline, nullptr); });
    VkPipeline reader = VK_NULL_HANDLE;
    if (dependency == 1 || dependency == 2) {
        pipelineInfo.stage.module = c.shader(computeShader(dependency));
        VK_CHECK(vkCreateComputePipelines(c.device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &reader));
        c.cleanup.push_back([&, reader] { vkDestroyPipeline(c.device, reader, nullptr); });
    }
    VkDescriptorPoolSize sizes[3] = {{VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC, 1}, {VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1}, {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1}};
    VkDescriptorPoolCreateInfo poolInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO}; poolInfo.maxSets = 1; poolInfo.poolSizeCount = bindingCount; poolInfo.pPoolSizes = sizes;
    VkDescriptorPool pool; VK_CHECK(vkCreateDescriptorPool(c.device, &poolInfo, nullptr, &pool));
    c.cleanup.push_back([&, pool] { vkDestroyDescriptorPool(c.device, pool, nullptr); });
    VkDescriptorSetAllocateInfo allocate{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO}; allocate.descriptorPool = pool; allocate.descriptorSetCount = 1; allocate.pSetLayouts = &setLayout;
    VkDescriptorSet set; VK_CHECK(vkAllocateDescriptorSets(c.device, &allocate, &set));
    VkDescriptorBufferInfo bufferInfos[3] = {{output.buffer, 0, count * 4}, {params.buffer, 0, 4}, {observed.buffer, 0, count * 4}};
    VkWriteDescriptorSet writes[3]{};
    for (unsigned i = 0; i < bindingCount; ++i) { writes[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET; writes[i].dstSet = set; writes[i].dstBinding = i;
        writes[i].descriptorCount = 1; writes[i].descriptorType = bindings[i].descriptorType; writes[i].pBufferInfo = &bufferInfos[i]; }
    vkUpdateDescriptorSets(c.device, bindingCount, writes, 0, nullptr);
    VkCommandBuffer command = c.begin();
    vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 1, &offset);
    uint32_t multiplier = 7; vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &multiplier);
    if (dependency != 2) { vkCmdDispatch(command, count, 1, 1); }
    if (dependency == 1 || dependency == 2) {
        if (dependency == 1) {
            barrierRepeated(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT,
                    VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT);
        }
        vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, reader);
        multiplier = 3; vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &multiplier);
        vkCmdDispatch(command, count, 1, 1);
        if (dependency == 2) {
            // Reader writes a DISTINCT observed buffer. The source output is only
            // read here; its later overwrite needs execution ordering (WAR), not
            // visibility. Retain observed results to make the read observable.
            barrierRepeated(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0);
            vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
            multiplier = 11; vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &multiplier);
            vkCmdDispatch(command, count, 1, 1);
        }
    }
    if (dependency == 3) {
        // Same recording repeats exactly owned buffers; updated push data must
        // still upload. Each changed value is followed by an unchanged dispatch,
        // exercising both invalidation and reuse through the actual Vulkan path.
        for (unsigned round = 0; round < 8; ++round) {
            barrierRepeated(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT,
                    VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT);
            multiplier = round == 7 ? 3 : 13 + round;
            vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &multiplier);
            vkCmdDispatch(command, count, 1, 1);
            barrierRepeated(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT,
                    VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT);
            vkCmdDispatch(command, count, 1, 1);
        }
    }
    if (helperRestore) {
        barrierRepeated(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT);
        vkCmdFillBuffer(command, output.buffer, offset, count * 4, 0xDEADBEEF);
        barrierRepeated(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT);
        // No vkCmdBindPipeline/DescriptorSets here: the helper must not disturb
        // the Vulkan application's persistent pipeline, descriptors, or constants.
        vkCmdDispatch(command, count, 1, 1);
    }
    barrierRepeated(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
    c.submit(command);
    const auto* actual = static_cast<const uint32_t*>(output.bytes);
    for (uint32_t i = 0; i < output.size / 4; ++i) {
        uint32_t x = i - offset / 4;
        uint32_t value = dependency == 1 ? x * 10 + 38 : dependency == 2 ? x * 11 + 19 : dependency == 3 ? x * 3 + 19 : x * 7 + 19;
        uint32_t expected = i >= offset / 4 && i < offset / 4 + count ? value : 0xA5A5A5A5;
        require(actual[i] == expected, "Vulkan descriptor/dynamic-offset/push-constant mismatch at " + std::to_string(i));
    }
    if (dependency == 2) {
        const auto* values = static_cast<const uint32_t*>(observed.bytes);
        for (uint32_t i = 0; i < observed.size / 4; ++i) {
            require(values[i] == (i < count ? i * 10 + 38 : 0xA5A5A5A5), "execution-only WAR preserves earlier observed reads and guards");
        }
    }
    if (dependency == 3) {
        // Keep the exact descriptors across distinct native recordings before
        // replacing their resources. Push/dynamic data and fresh GPU ownership
        // must remain correct when CPU preparation survives recording retirement.
        for (unsigned recording = 0; recording < 4; ++recording) {
            // Churn unrelated native buffer membership between recordings.
            // Used descriptors remain unchanged and must acquire fresh leases.
            auto unrelated = c.buffer(256, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
            std::memset(unrelated.bytes, 0xCD, unrelated.size);
            auto releaseUnrelated = std::move(c.cleanup.back());
            c.cleanup.pop_back();
            releaseUnrelated();
            command = c.begin();
            vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
            vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 1, &offset);
            multiplier = 3; vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &multiplier);
            vkCmdDispatch(command, count, 1, 1);
            barrierRepeated(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT,
                    VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
            c.submit(command);
            for (uint32_t i = 0; i < output.size / 4; ++i) {
                uint32_t expected = i >= offset / 4 && i < offset / 4 + count ? (i - offset / 4) * 3 + 19 : 0xA5A5A5A5;
                require(actual[i] == expected, "unchanged descriptors across native recordings preserve output/guards");
            }
        }
        auto revised = c.buffer(output.size, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
        auto revisedParams = c.buffer(16, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
        std::memset(revised.bytes, 0xA5, revised.size); std::memset(revisedParams.bytes, 0, revisedParams.size);
        *static_cast<uint32_t*>(revisedParams.bytes) = 37;
        // The exact same VkDescriptorSet handle now names different live Metal
        // buffers after the first recording completes. No set-pointer cache is valid.
        bufferInfos[0].buffer = revised.buffer; bufferInfos[1].buffer = revisedParams.buffer;
        vkUpdateDescriptorSets(c.device, bindingCount, writes, 0, nullptr);
        command = c.begin();
        vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
        vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 1, &offset);
        multiplier = 5; vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &multiplier);
        vkCmdDispatch(command, count, 1, 1);
        barrierRepeated(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT,
                VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT);
        vkCmdDispatch(command, count, 1, 1);
        barrierRepeated(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
        c.submit(command);
        const auto* changed = static_cast<const uint32_t*>(revised.bytes);
        for (uint32_t i = 0; i < revised.size / 4; ++i) {
            uint32_t expected = i >= offset / 4 && i < offset / 4 + count ? (i - offset / 4) * 5 + 37 : 0xA5A5A5A5;
            require(changed[i] == expected, "same descriptor handle rereads revised buffer identities and guards");
            require(actual[i] == (i >= offset / 4 && i < offset / 4 + count ? (i - offset / 4) * 3 + 19 : 0xA5A5A5A5), "revised descriptors leave previous owned buffer unchanged");
        }
    }
}


int main(int argc,char** argv){bool native=argc<2||std::strcmp(argv[1],"m3");setenv("MVK_CONFIG_USE_METAL4",native?"1":"0",1);unsigned failed=0,passed=0;
@autoreleasepool{auto test=[&](const char* name,const std::function<void(Context&)>& body){try{Context c;c.initialize(false,native);body(c);++passed;printf("PASS %s\n",name);fflush(stdout);}catch(const std::exception& e){++failed;fprintf(stderr,"FAIL %s: %s\n",name,e.what());}};
test("compute_dynamic_push",[](Context& c){compute(c);});
test("compute_RAW",[](Context& c){compute(c,false,1);});
test("compute_WAR",[](Context& c){compute(c,false,2);});
test("descriptor_revision_recording",[](Context& c){compute(c,false,3);});
test("compatible_layout_fallback",[](Context& c){computeCompatible(c,false,3);});
test("repeated_barrier_and_current_producer_RAW",[](Context& c){computeRepeated(c,false,1);});
test("repeated_barrier_and_current_producer_WAR",[](Context& c){computeRepeated(c,false,2);});
test("indexed_render",[](Context& c){render(c);});
test("helper_restore",[](Context& c){compute(c,true);});
test("fragment_texture_sampler",[](Context& c){render(c,true);});
test("partial_clear_restore",[](Context& c){render(c,false,true);});
test("msaa_renderpass_resolve",[](Context& c){render(c,false,true,1);});
test("msaa_explicit_resolve",[](Context& c){render(c,false,false,2);});
test("occlusion_accumulation_reuse",[](Context& c){render(c,false,true,0,0,true);});
test("single_use_msaa_handoff",[](Context& c){c.oneTime=true;render(c,false,true,1);});
}printf("{\"native\":%s,\"passed\":%u,\"failed\":%u}\n",native?"true":"false",passed,failed);return failed?1:0;}
