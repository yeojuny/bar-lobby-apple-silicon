// Focused r67 prepared-prefix/suffix Vulkan regression. Private offscreen only.
#include "MVKCommandBuffer.h"
#include "MVKPipeline.h"
#include "MVKCmdPipeline.h"
#define main metal4_existing_integration_main
#include "metal4-vulkan-integration.mm"
#undef main
#include <array>
#include <memory>

// Protected access is confined to the test: these are pointers to members of
// the real base object, never a forged derived object or a product diagnostic.
struct PreparedInspection : MVKCommandBuffer {
    static MVKCommandBuffer* object(VkCommandBuffer cb) { return getMVKCommandBuffer(cb); }
    static bool hasPrefix(VkCommandBuffer cb) {
        auto field = &PreparedInspection::_metal4PreparedSubmission;
        return bool(object(cb)->*field);
    }
    static MVKCommandEncoder* encoder(VkCommandBuffer cb) {
        auto field = &PreparedInspection::_metal4PreparedEncoder;
        return object(cb)->*field;
    }
    static size_t replaySize(VkCommandBuffer cb) {
        auto field = &PreparedInspection::_metal4PreparedReplay;
        return (object(cb)->*field).size();
    }
    static MVKCommand* head(VkCommandBuffer cb) {
        auto field = &PreparedInspection::_head;
        return object(cb)->*field;
    }
};
struct EncoderInspection : MVKCommandEncoder {
    static bool owns(MVKCommandEncoder* encoder, MVKVulkanAPIObject* object) {
        auto field = &EncoderInspection::_metal4VulkanStateOwners;
        const auto& owners = encoder->*field;
        return owners.find(object) != owners.end();
    }
};
struct CompactUniformInspection : MVKCmdPushDescriptorSetWithTemplate {
    static uint32_t count(MVKCmdPushDescriptorSetWithTemplate* command) {
        auto field = &CompactUniformInspection::_compactUniformWriteCount;
        return command->*field;
    }
    static size_t bytes(MVKCmdPushDescriptorSetWithTemplate* command) {
        auto field = &CompactUniformInspection::_dataSize;
        return command->*field;
    }
    static const VkWriteDescriptorSet* writes(MVKCmdPushDescriptorSetWithTemplate* command) {
        auto field = &CompactUniformInspection::_pData;
        auto* infos = static_cast<const VkDescriptorBufferInfo*>(command->*field);
        return reinterpret_cast<const VkWriteDescriptorSet*>(infos + count(command));
    }
    static MVKCmdPushDescriptorSetWithTemplate* tail(VkCommandBuffer command) {
        auto* node = PreparedInspection::head(command);
        require(node, "deferred template keeps its command node");
        while (node->_next) node = node->_next;
        return static_cast<MVKCmdPushDescriptorSetWithTemplate*>(node);
    }
};
static void prepared(VkCommandBuffer cb, bool suffix) {
    require(PreparedInspection::hasPrefix(cb), "real native prefix exists before queue submit");
    require(bool(PreparedInspection::head(cb)) == suffix, "only the deferred suffix retains command nodes");
}
static VkCommandPool preparedPool(Context& c) {
    VkCommandPoolCreateInfo info{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    info.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    info.queueFamilyIndex = c.family;
    VkCommandPool pool; VK_CHECK(vkCreateCommandPool(c.device, &info, nullptr, &pool));
    c.cleanup.push_back([device=c.device, pool] { vkDestroyCommandPool(device, pool, nullptr); });
    return pool;
}
static VkCommandBuffer beginPrepared(Context& c, VkCommandPool pool) {
    VkCommandBufferAllocateInfo allocate{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    allocate.commandPool = pool; allocate.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY; allocate.commandBufferCount = 1;
    VkCommandBuffer command; VK_CHECK(vkAllocateCommandBuffers(c.device, &allocate, &command));
    VkCommandBufferBeginInfo begin{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    VK_CHECK(vkBeginCommandBuffer(command, &begin));
    return command;
}
static VkQueryPool preparedQueries(Context& c) {
    require(c.timestampValidBits != 0, "timestamp stage supported for deferred query fixture");
    VkQueryPoolCreateInfo info{VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO};
    info.queryType = VK_QUERY_TYPE_TIMESTAMP; info.queryCount = 1;
    VkQueryPool query; VK_CHECK(vkCreateQueryPool(c.device, &info, nullptr, &query));
    c.cleanup.push_back([device=c.device, query] { vkDestroyQueryPool(device, query, nullptr); });
    return query;
}
static void timestampAvailable(Context& c, VkQueryPool query) {
    uint64_t values[2] = {};
    VK_CHECK(vkGetQueryPoolResults(c.device, query, 0, 1, sizeof(values), values, sizeof(values),
                                VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WITH_AVAILABILITY_BIT));
    require(values[1] != 0, "deferred timestamp query completes with availability");
}
static void submitPrepared(Context& c, const std::vector<VkCommandBuffer>& commands) {
    auto fence = fusionFence(c);
    VkSubmitInfo submit{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    submit.commandBufferCount = uint32_t(commands.size()); submit.pCommandBuffers = commands.data();
    const auto before = c.counter(c.queue);
    c.inFlight = true; VK_CHECK(vkQueueSubmit(c.queue, 1, &submit, fence));
    VK_CHECK(vkWaitForFences(c.device, 1, &fence, VK_TRUE, 10000000000ull));
    VK_CHECK(vkQueueWaitIdle(c.queue)); c.inFlight = false;
    c.nativeAfter = c.counter(c.queue);
    require(c.nativeAfter == before + 1, "one Vulkan submit retires as one native completion group");
}
struct PreparedCompute {
    static constexpr uint32_t count = 16;
    Buffer output{}, params{};
    uint32_t offset = 0;
    VkDescriptorSetLayout setLayout = VK_NULL_HANDLE;
    VkPipelineLayout layout = VK_NULL_HANDLE;
    VkPipeline pipeline = VK_NULL_HANDLE;
    VkDescriptorSet set = VK_NULL_HANDLE;
};
static VkPipelineLayout preparedLayout(Context& c, VkDescriptorSetLayout setLayout) {
    VkPushConstantRange push{VK_SHADER_STAGE_COMPUTE_BIT, 0, 4};
    VkPipelineLayoutCreateInfo info{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    info.setLayoutCount = 1; info.pSetLayouts = &setLayout;
    info.pushConstantRangeCount = 1; info.pPushConstantRanges = &push;
    VkPipelineLayout layout; VK_CHECK(vkCreatePipelineLayout(c.device, &info, nullptr, &layout));
    return layout;
}
static PreparedCompute preparedCompute(Context& c, unsigned mode = 0, const Buffer* source = nullptr) {
    PreparedCompute state;
    state.offset = uint32_t(std::max<VkDeviceSize>(256, c.properties.limits.minStorageBufferOffsetAlignment));
    state.output = c.buffer(state.offset + state.count * 4 + 64, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    state.params = c.buffer(16, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
    std::memset(state.output.bytes, 0xa5, state.output.size);
    std::memset(state.params.bytes, 0, state.params.size);
    *static_cast<uint32_t*>(state.params.bytes) = 19;
    VkDescriptorSetLayoutBinding bindings[3] = {
        {0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr},
        {1, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr},
        {2, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr}};
    VkDescriptorSetLayoutCreateInfo setInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
    setInfo.bindingCount = mode == 2 ? 3 : 2; setInfo.pBindings = bindings;
    VK_CHECK(vkCreateDescriptorSetLayout(c.device, &setInfo, nullptr, &state.setLayout));
    c.cleanup.push_back([device=c.device, layout=state.setLayout] { vkDestroyDescriptorSetLayout(device, layout, nullptr); });
    state.layout = preparedLayout(c, state.setLayout);
    c.cleanup.push_back([device=c.device, layout=state.layout] { vkDestroyPipelineLayout(device, layout, nullptr); });
    VkComputePipelineCreateInfo pipelineInfo{VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO};
    pipelineInfo.layout = state.layout;
    pipelineInfo.stage = {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, nullptr, 0, VK_SHADER_STAGE_COMPUTE_BIT,
                          c.shader(computeShader(mode)), "main", nullptr};
    VK_CHECK(vkCreateComputePipelines(c.device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &state.pipeline));
    c.cleanup.push_back([device=c.device, pipeline=state.pipeline] { vkDestroyPipeline(device, pipeline, nullptr); });
    VkDescriptorPoolSize sizes[3] = {{VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC, 1},
        {VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1}, {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1}};
    VkDescriptorPoolCreateInfo poolInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
    poolInfo.maxSets = 1; poolInfo.poolSizeCount = setInfo.bindingCount; poolInfo.pPoolSizes = sizes;
    VkDescriptorPool pool; VK_CHECK(vkCreateDescriptorPool(c.device, &poolInfo, nullptr, &pool));
    c.cleanup.push_back([device=c.device, pool] { vkDestroyDescriptorPool(device, pool, nullptr); });
    VkDescriptorSetAllocateInfo allocate{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
    allocate.descriptorPool = pool; allocate.descriptorSetCount = 1; allocate.pSetLayouts = &state.setLayout;
    VK_CHECK(vkAllocateDescriptorSets(c.device, &allocate, &state.set));
    require(mode != 2 || source, "read-mode fixture requires shared source");
    VkDescriptorBufferInfo infos[3] = {{mode == 2 ? source->buffer : state.output.buffer, 0, state.count * 4},
        {state.params.buffer, 0, 4}, {state.output.buffer, state.offset, state.count * 4}};
    VkWriteDescriptorSet writes[3]{};
    for (uint32_t i = 0; i < setInfo.bindingCount; ++i) {
        writes[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET; writes[i].dstSet = state.set;
        writes[i].dstBinding = i; writes[i].descriptorCount = 1;
        writes[i].descriptorType = bindings[i].descriptorType; writes[i].pBufferInfo = &infos[i];
    }
    vkUpdateDescriptorSets(c.device, setInfo.bindingCount, writes, 0, nullptr);
    return state;
}
static void bindPrepared(VkCommandBuffer command, const PreparedCompute& state, uint32_t multiplier,
                         VkPipelineLayout bindingLayout = VK_NULL_HANDLE, uint32_t offset = UINT32_MAX) {
    vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, state.pipeline);
    const auto layout = bindingLayout ? bindingLayout : state.layout;
    const uint32_t dynamicOffset = offset == UINT32_MAX ? state.offset : offset;
    vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &state.set, 1, &dynamicOffset);
    vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &multiplier);
}
static void computeOutput(const PreparedCompute& state, const std::function<uint32_t(uint32_t)>& expected) {
    const auto* words = static_cast<const uint32_t*>(state.output.bytes);
    for (uint32_t i = 0; i < state.output.size / 4; ++i) {
        const uint32_t want = i >= state.offset / 4 && i < state.offset / 4 + state.count
            ? expected(i - state.offset / 4) : 0xa5a5a5a5u;
        require(words[i] == want, "prepared compute output/guard mismatch at " + std::to_string(i));
    }
}
static void canceledPrepared(Context& c) {
    auto output = c.buffer(256, VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    auto observed = c.buffer(256, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    std::memset(output.bytes, 0xa5, output.size); std::memset(observed.bytes, 0, observed.size);
    auto command = c.begin(); vkCmdFillBuffer(command, output.buffer, 16, 224, 0x12345678);
    VK_CHECK(vkEndCommandBuffer(command)); prepared(command, false);
    require(!PreparedInspection::encoder(command), "complete prefix closes native recording at vkEnd");
    require(c.counter(c.queue) == c.nativeBefore, "vkEnd does not submit native GPU work");
    VK_CHECK(vkResetCommandBuffer(command, 0));
    require(!PreparedInspection::hasPrefix(command), "reset cancels and releases the unsubmitted prefix");
    auto verify = c.begin(); VkBufferCopy copy{0, 0, 256};
    vkCmdCopyBuffer(verify, output.buffer, observed.buffer, 1, &copy);
    barrier(verify, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
    VK_CHECK(vkEndCommandBuffer(verify)); submitPrepared(c, {verify});
    for (uint32_t i = 0; i < 64; ++i) {
        require(static_cast<uint32_t*>(output.bytes)[i] == 0xa5a5a5a5u &&
                static_cast<uint32_t*>(observed.bytes)[i] == 0xa5a5a5a5u, "canceled prefix produced no GPU effects");
    }
    auto query = preparedQueries(c);
    vkResetQueryPool(c.device, query, 0, 1);
    auto timestamp = c.begin();
    vkCmdWriteTimestamp(timestamp, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, query, 0);
    require(!PreparedInspection::hasPrefix(timestamp) && !PreparedInspection::encoder(timestamp) &&
            PreparedInspection::head(timestamp), "leading timestamp alone does not allocate native preparation");
    vkCmdFillBuffer(timestamp, output.buffer, 0, output.size, 0x99999999);
    VK_CHECK(vkEndCommandBuffer(timestamp)); prepared(timestamp, false);
    require(PreparedInspection::encoder(timestamp) && PreparedInspection::replaySize(timestamp)==2,
            "leading timestamp retains activation and exact fallback prefix until submit");
    uint64_t values[2]={0xa5a5a5a5a5a5a5a5ull,123};
    require(vkGetQueryPoolResults(c.device,query,0,1,sizeof(values),values,sizeof(values),
            VK_QUERY_RESULT_64_BIT|VK_QUERY_RESULT_WITH_AVAILABILITY_BIT)==VK_NOT_READY && values[1]==0,
            "recording a leading timestamp does not publish availability");
    VK_CHECK(vkResetCommandBuffer(timestamp,0));
    require(!PreparedInspection::hasPrefix(timestamp) && !PreparedInspection::encoder(timestamp) &&
            PreparedInspection::replaySize(timestamp)==0, "cancel releases prepared timestamp and original nodes");
    require(vkGetQueryPoolResults(c.device,query,0,1,sizeof(values),values,sizeof(values),
            VK_QUERY_RESULT_64_BIT|VK_QUERY_RESULT_WITH_AVAILABILITY_BIT)==VK_NOT_READY && values[1]==0,
            "cancelled leading timestamp remains unavailable");
    for(uint32_t i=0;i<64;++i) require(static_cast<uint32_t*>(output.bytes)[i]==0xa5a5a5a5u,
                                      "cancelled timestamp prefix cannot execute following fill");
}
static void reverseRecordedThreePools(Context& c) {
    auto source = c.buffer(PreparedCompute::count * 4, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    std::memset(source.bytes, 0, source.size);
    auto b = preparedCompute(c, 2, &source), d = preparedCompute(c, 2, &source);
    auto p0 = preparedPool(c), p1 = preparedPool(c), p2 = preparedPool(c);
    auto consumer2 = beginPrepared(c, p2); bindPrepared(consumer2, d, 5, VK_NULL_HANDLE, 0);
    vkCmdDispatch(consumer2, d.count, 1, 1);
    barrier(consumer2, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
    VK_CHECK(vkEndCommandBuffer(consumer2)); prepared(consumer2, true);
    auto consumer1 = beginPrepared(c, p1); bindPrepared(consumer1, b, 3, VK_NULL_HANDLE, 0);
    vkCmdDispatch(consumer1, b.count, 1, 1);
    barrier(consumer1, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
    VK_CHECK(vkEndCommandBuffer(consumer1)); prepared(consumer1, true);
    auto producer = beginPrepared(c, p0); vkCmdFillBuffer(producer, source.buffer, 0, source.size, 37);
    barrier(producer, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT,
            VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_READ_BIT);
    VK_CHECK(vkEndCommandBuffer(producer)); prepared(producer, false);
    require(c.counter(c.queue) == c.nativeBefore, "recording in reverse order does not execute any child");
    submitPrepared(c, {producer, consumer1, consumer2});
    computeOutput(b, [](uint32_t i) { return 37 + i * 3 + 19; });
    computeOutput(d, [](uint32_t i) { return 37 + i * 5 + 19; });
}
static void compactUniformSnapshot(Context& c) {
    const auto push = reinterpret_cast<PFN_vkCmdPushDescriptorSetKHR>(vkGetDeviceProcAddr(c.device, "vkCmdPushDescriptorSetKHR"));
    const auto pushTemplate = reinterpret_cast<PFN_vkCmdPushDescriptorSetWithTemplateKHR>(vkGetDeviceProcAddr(c.device, "vkCmdPushDescriptorSetWithTemplateKHR"));
    require(push && pushTemplate, "actual push descriptor entry points");
    PreparedCompute state;
    state.offset = uint32_t(std::max<VkDeviceSize>(256, c.properties.limits.minStorageBufferOffsetAlignment));
    state.output = c.buffer(state.offset + state.count * 4 + 64, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
    state.params = c.buffer(16, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
    auto alternate = c.buffer(16, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
    auto helper = c.buffer(64, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    auto image = c.image(1, 1, VK_FORMAT_R8G8B8A8_UNORM, VK_IMAGE_USAGE_SAMPLED_BIT);
    VkDescriptorSetLayoutBinding bindings[] = {
        {0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr},
        {1, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr},
        {3, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 3, VK_SHADER_STAGE_COMPUTE_BIT, nullptr},
        {4, VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr}};
    VkDescriptorSetLayoutCreateInfo setInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
    setInfo.flags = VK_DESCRIPTOR_SET_LAYOUT_CREATE_PUSH_DESCRIPTOR_BIT_KHR;
    setInfo.bindingCount = 4; setInfo.pBindings = bindings;
    VK_CHECK(vkCreateDescriptorSetLayout(c.device, &setInfo, nullptr, &state.setLayout));
    c.cleanup.push_back([device=c.device, layout=state.setLayout] { vkDestroyDescriptorSetLayout(device, layout, nullptr); });
    state.layout = preparedLayout(c, state.setLayout);
    c.cleanup.push_back([device=c.device, layout=state.layout] { vkDestroyPipelineLayout(device, layout, nullptr); });
    VkComputePipelineCreateInfo pipelineInfo{VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO};
    pipelineInfo.layout = state.layout;
    pipelineInfo.stage = {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, nullptr, 0, VK_SHADER_STAGE_COMPUTE_BIT,
        c.shader(computeShader()), "main", nullptr};
    VK_CHECK(vkCreateComputePipelines(c.device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &state.pipeline));
    c.cleanup.push_back([device=c.device, pipeline=state.pipeline] { vkDestroyPipeline(device, pipeline, nullptr); });
    auto query = preparedQueries(c);
    const size_t strides[] = {0, 8, sizeof(VkDescriptorBufferInfo), 4096, sizeof(VkDescriptorBufferInfo), 0};
    MVKCmdPushDescriptorSetWithTemplate* canceledNode = nullptr;
    for (unsigned cycle = 0; cycle < 6; ++cycle) {
        std::memset(state.output.bytes, 0xa5, state.output.size);
        *static_cast<uint32_t*>(state.params.bytes) = 11;
        *static_cast<uint32_t*>(alternate.bytes) = 19;
        const bool mixed = cycle == 4;
        VkDescriptorUpdateTemplateEntry entries[] = {
            {1, 0, 1, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 8193, strides[cycle]},
            {3, 1, 1, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 16385, strides[cycle]},
            {1, 0, 1, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 24577, strides[cycle]},
            {4, 0, 1, VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, 32769, sizeof(VkDescriptorImageInfo)}};
        VkDescriptorUpdateTemplateCreateInfo info{VK_STRUCTURE_TYPE_DESCRIPTOR_UPDATE_TEMPLATE_CREATE_INFO};
        info.descriptorUpdateEntryCount = mixed ? 4 : 3; info.pDescriptorUpdateEntries = entries;
        info.templateType = VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_PUSH_DESCRIPTORS_KHR;
        info.pipelineBindPoint = VK_PIPELINE_BIND_POINT_COMPUTE; info.pipelineLayout = state.layout;
        VkDescriptorUpdateTemplate descriptorTemplate;
        VK_CHECK(vkCreateDescriptorUpdateTemplate(c.device, &info, nullptr, &descriptorTemplate));
        c.cleanup.push_back([device=c.device, descriptorTemplate] { vkDestroyDescriptorUpdateTemplate(device, descriptorTemplate, nullptr); });
        std::vector<uint8_t> data((mixed ? entries[3].offset : entries[2].offset) + sizeof(VkDescriptorBufferInfo), 0xcd);
        VkDescriptorBufferInfo inputs[] = {{state.params.buffer, 0, 4}, {state.params.buffer, 0, 4}, {alternate.buffer, 0, 4}};
        for (unsigned i = 0; i < 3; ++i) std::memcpy(data.data() + entries[i].offset, &inputs[i], sizeof(inputs[i]));
        if (mixed) {
            VkDescriptorImageInfo input{VK_NULL_HANDLE, image.view, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
            std::memcpy(data.data() + entries[3].offset, &input, sizeof(input));
        }
        if (!cycle) {
            auto canceled = c.begin();
            pushTemplate(canceled, descriptorTemplate, state.layout, 0, data.data());
            canceledNode = CompactUniformInspection::tail(canceled);
            require(CompactUniformInspection::count(canceledNode) == 3, "canceled command admitted compact metadata");
            VK_CHECK(vkEndCommandBuffer(canceled)); VK_CHECK(vkResetCommandBuffer(canceled, 0));
            require(!PreparedInspection::head(canceled), "cancel releases the captured command without GPU work");
        }
        vkResetQueryPool(c.device, query, 0, 1);
        auto command = c.begin();
        vkCmdWriteTimestamp(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, query, 0);
        vkCmdFillBuffer(command, helper.buffer, 0, helper.size, 0x12345678);
        vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, state.pipeline);
        VkDescriptorBufferInfo output{state.output.buffer, state.offset, state.count * 4};
        VkWriteDescriptorSet write{VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET};
        write.dstBinding = 0; write.descriptorCount = 1; write.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER; write.pBufferInfo = &output;
        push(command, VK_PIPELINE_BIND_POINT_COMPUTE, state.layout, 0, 1, &write);
        pushTemplate(command, descriptorTemplate, state.layout, 0, data.data());
        auto* node = CompactUniformInspection::tail(command);
        require(CompactUniformInspection::count(node) == (mixed ? 0u : 3u), "all-entry compact admission versus mixed image fallback");
        if (!cycle) require(node == canceledNode, "canceled compact node is actually reused by the command pool");
        if (!mixed) {
            require(CompactUniformInspection::bytes(node) == 3 * (sizeof(VkDescriptorBufferInfo) + sizeof(VkWriteDescriptorSet)), "captured storage excludes distant prefix and gaps");
            const auto* writes = CompactUniformInspection::writes(node);
            require(writes[0].dstBinding == 1 && writes[1].dstBinding == 3 && writes[1].dstArrayElement == 1 &&
                    writes[2].dstBinding == 1 && writes[2].pBufferInfo->buffer == alternate.buffer,
                    "ordered duplicates and sparse in-binding target metadata retained");
        }
        std::fill(data.begin(), data.end(), 0);
        uint32_t multiplier = 7;
        vkCmdPushConstants(command, state.layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &multiplier);
        vkCmdDispatch(command, state.count, 1, 1);
        barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT | VK_PIPELINE_STAGE_TRANSFER_BIT,
            VK_ACCESS_SHADER_WRITE_BIT | VK_ACCESS_TRANSFER_WRITE_BIT,
            VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT | VK_PIPELINE_STAGE_TRANSFER_BIT,
            VK_ACCESS_SHADER_WRITE_BIT | VK_ACCESS_TRANSFER_WRITE_BIT);
        vkCmdCopyQueryPoolResults(command, query, 0, 1, helper.buffer, 0, 16,
            VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WITH_AVAILABILITY_BIT | VK_QUERY_RESULT_WAIT_BIT);
        vkCmdFillBuffer(command, helper.buffer, 32, 32, 0x55aa55aa);
        vkCmdDispatch(command, state.count, 1, 1);
        barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT | VK_PIPELINE_STAGE_TRANSFER_BIT,
            VK_ACCESS_SHADER_WRITE_BIT | VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
        VK_CHECK(vkEndCommandBuffer(command)); prepared(command, true);
        *static_cast<uint32_t*>(alternate.bytes) = 37 + cycle;
        submitPrepared(c, {command});
        computeOutput(state, [cycle](uint32_t i) { return i * 7 + 37 + cycle; });
        timestampAvailable(c, query);
        require(static_cast<uint64_t*>(helper.bytes)[1] != 0 && static_cast<uint32_t*>(helper.bytes)[8] == 0x55aa55aau,
                "query result and helper survive retained descriptor replay");
        VK_CHECK(vkResetCommandBuffer(command, 0));
    }
    // Extend the same original snapshot case with the actual graphics consumer.
    render(c, false, false, 0, 0, false, true);
}
static void hostLatestAndUpdateSnapshot(Context& c) {
    auto source = c.buffer(256, VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
    auto latest = c.buffer(256, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    auto snapshot = c.buffer(256, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    std::memset(source.bytes, 0x11, source.size);
    std::memset(latest.bytes, 0xa5, latest.size); std::memset(snapshot.bytes, 0xa5, snapshot.size);
    uint32_t patch[4] = {0x01234567, 0x89abcdef, 0, 0xffffffff};
    const std::array<uint32_t, 4> original = {patch[0], patch[1], patch[2], patch[3]};
    auto command = c.begin(); VkBufferCopy copy{16, 16, 224};
    vkCmdCopyBuffer(command, source.buffer, latest.buffer, 1, &copy);
    vkCmdUpdateBuffer(command, snapshot.buffer, 16, sizeof(patch), patch);
    std::memset(patch, 0x22, sizeof(patch));
    barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
    VK_CHECK(vkEndCommandBuffer(command)); prepared(command, true);
    std::memset(source.bytes, 0x77, source.size); std::memset(patch, 0x33, sizeof(patch));
    submitPrepared(c, {command});
    for (uint32_t i = 0; i < 64; ++i) {
        require(static_cast<uint32_t*>(latest.bytes)[i] == (i >= 4 && i < 60 ? 0x77777777u : 0xa5a5a5a5u),
                "mapped source is read at GPU execution after vkEnd");
        require(static_cast<uint32_t*>(snapshot.bytes)[i] == (i >= 4 && i < 8 ? original[i - 4] : 0xa5a5a5a5u),
                "vkCmdUpdateBuffer preserves API-call snapshot and guards");
    }
    compactUniformSnapshot(c);
}
static void mixedComputeQuerySuffix(Context& c) {
    auto state = preparedCompute(c, 1); auto query = preparedQueries(c);
    auto helper = c.buffer(256, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    std::memset(helper.bytes, 0, helper.size);
    for (uint32_t i = 0; i < state.count; ++i) static_cast<uint32_t*>(state.output.bytes)[state.offset / 4 + i] = 10;
    auto command = c.begin(); bindPrepared(command, state, 7);
    vkCmdDispatch(command, state.count, 1, 1);
    barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT,
            VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT);
    vkCmdResetQueryPool(command, query, 0, 1);
    vkCmdWriteTimestamp(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, query, 0);
    vkCmdFillBuffer(command, helper.buffer, 0, helper.size, 0x55aa55aa);
    // No repeated application bind or push: suffix must use preserved state
    // after a query boundary and a temporary fill compute helper.
    vkCmdDispatch(command, state.count, 1, 1);
    barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT | VK_PIPELINE_STAGE_TRANSFER_BIT,
            VK_ACCESS_SHADER_WRITE_BIT | VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
    VK_CHECK(vkEndCommandBuffer(command)); prepared(command, true);
    require(PreparedInspection::encoder(command), "suffix keeps the original Vulkan state encoder");
    submitPrepared(c, {command});
    computeOutput(state, [](uint32_t i) { return 10 + 2 * (i * 7 + 19); });
    for (uint32_t i = 0; i < 64; ++i) require(static_cast<uint32_t*>(helper.bytes)[i] == 0x55aa55aau, "late fill helper result");
    timestampAvailable(c, query);
    // Record in the opposite order to submission. Reset must take effect before
    // activating the already-encoded leading timestamp, in both generations.
    for(unsigned cycle=0;cycle<2;++cycle) {
        auto leading=c.begin();
        vkCmdWriteTimestamp(leading,VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,query,0);
        vkCmdFillBuffer(leading,helper.buffer,0,helper.size,0x76543210+cycle);
        barrier(leading,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_TRANSFER_WRITE_BIT,
                VK_PIPELINE_STAGE_HOST_BIT,VK_ACCESS_HOST_READ_BIT);
        VK_CHECK(vkEndCommandBuffer(leading)); prepared(leading,true);
        require(PreparedInspection::encoder(leading) && PreparedInspection::replaySize(leading)==2,
                "leading timestamp and fill prepared before reset recording");
        auto reset=c.begin(); vkCmdResetQueryPool(reset,query,0,1); VK_CHECK(vkEndCommandBuffer(reset));
        submitPrepared(c,{reset,leading});
        require(PreparedInspection::replaySize(leading)==0 && !PreparedInspection::encoder(leading),
                "successful adoption releases fallback nodes and encoder");
        timestampAvailable(c,query);
        for(uint32_t i=0;i<64;++i) require(static_cast<uint32_t*>(helper.bytes)[i]==0x76543210+cycle,
                                          "leading timestamp preserves following fill through actual submit order");
    }
}
static void destroyedLayoutNodeReuse(Context& c) {
    auto state = preparedCompute(c, 1), unrelated = preparedCompute(c);
    auto query = preparedQueries(c);
    auto layout = std::make_shared<VkPipelineLayout>(preparedLayout(c, state.setLayout));
    c.cleanup.push_back([device=c.device, layout] { if (*layout) vkDestroyPipelineLayout(device, *layout, nullptr); });
    auto* layoutObject = (MVKPipelineLayout*)*layout;
    const uint32_t originalPushLength = layoutObject->getPushConstantsLength();
    require(originalPushLength >= 4, "layout owns the requested push-constant range");
    for (uint32_t i = 0; i < state.count; ++i) static_cast<uint32_t*>(state.output.bytes)[state.offset / 4 + i] = 10;
    auto command = c.begin(); bindPrepared(command, state, 9, *layout);
    auto* bindNode = PreparedInspection::head(command)->_next;
    require(bindNode, "descriptor bind begins as a staged state node");
    vkCmdDispatch(command, state.count, 1, 1);
    auto* encoder = PreparedInspection::encoder(command);
    require(encoder && EncoderInspection::owns(encoder, layoutObject), "persistent encoder owns the binding layout before node recycling");
    vkDestroyPipelineLayout(c.device, *layout, nullptr); *layout = VK_NULL_HANDLE;
    // An identical command type from the same pool must take the recycled node
    // and release its old layout reference. This command is canceled, not sent.
    auto churn = c.begin(); uint32_t offset = unrelated.offset;
    vkCmdBindDescriptorSets(churn, VK_PIPELINE_BIND_POINT_COMPUTE, unrelated.layout, 0, 1, &unrelated.set, 1, &offset);
    require(PreparedInspection::head(churn) == bindNode, "descriptor node was actually reused before original suffix encoding");
    require(EncoderInspection::owns(encoder, layoutObject) && layoutObject->getPushConstantsLength() == originalPushLength,
            "destroyed API layout remains live after the node releases its original reference");
    barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT,
            VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT);
    vkCmdResetQueryPool(command, query, 0, 1); vkCmdWriteTimestamp(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, query, 0);
    vkCmdDispatch(command, state.count, 1, 1);
    barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
    VK_CHECK(vkEndCommandBuffer(command)); prepared(command, true);
    VK_CHECK(vkEndCommandBuffer(churn));
    require(!PreparedInspection::hasPrefix(churn), "state-only node reuse does not create a native child");
    VK_CHECK(vkResetCommandBuffer(churn, 0));
    submitPrepared(c, {command});
    computeOutput(state, [](uint32_t i) { return 10 + 2 * (i * 9 + 19); });
    timestampAvailable(c, query);
}
static void stateOnlyThenQuery(Context& c) {
    auto state = preparedCompute(c); auto query = preparedQueries(c);
    auto command = c.begin(); bindPrepared(command, state, 13);
    require(!PreparedInspection::hasPrefix(command) && PreparedInspection::head(command), "CPU state alone remains staged without a native pack");
    vkCmdResetQueryPool(command, query, 0, 1); vkCmdWriteTimestamp(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, query, 0);
    vkCmdDispatch(command, state.count, 1, 1);
    barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
    VK_CHECK(vkEndCommandBuffer(command));
    require(!PreparedInspection::hasPrefix(command) && !PreparedInspection::encoder(command) && PreparedInspection::head(command),
            "first deferred query retains the complete late path without a prepared child");
    submitPrepared(c, {command}); computeOutput(state, [](uint32_t i) { return i * 13 + 19; });
    timestampAvailable(c, query);

    // Exercise the actual admission/ownership transitions in the same existing
    // case: no native pack for T or T+state, deferred copy remains whole replay,
    // and useful compute still prepares T exactly once before the staged state.
    auto results = c.buffer(32, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    for (unsigned mode = 0; mode < 4; ++mode) {
        vkResetQueryPool(c.device, query, 0, 1);
        std::memset(results.bytes, 0xa5, results.size);
        std::memset(state.output.bytes, 0xa5, state.output.size);
        auto leading = c.begin();
        vkCmdWriteTimestamp(leading, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, query, 0);
        if (mode) { bindPrepared(leading, state, 17); }
        require(!PreparedInspection::hasPrefix(leading) && !PreparedInspection::encoder(leading) &&
                PreparedInspection::head(leading) && PreparedInspection::replaySize(leading) == 0,
                "timestamp and CPU state remain original nodes without native ownership");
        if (mode == 3) {
            vkCmdDispatch(leading, state.count, 1, 1);
            require(PreparedInspection::hasPrefix(leading) && PreparedInspection::encoder(leading) &&
                    PreparedInspection::replaySize(leading) > 1,
                    "useful dispatch prepares the leading timestamp and staged state");
        }
        if (mode >= 2) {
            vkCmdCopyQueryPoolResults(leading, query, 0, 1, results.buffer, 8, 16,
                    VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WITH_AVAILABILITY_BIT | VK_QUERY_RESULT_WAIT_BIT);
            barrier(leading, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_ACCESS_MEMORY_WRITE_BIT,
                    VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
        }
        VK_CHECK(vkEndCommandBuffer(leading));
        require(PreparedInspection::hasPrefix(leading) == (mode == 3),
                "only actual prepared work owns a native prefix at vkEnd");
        uint64_t before[2] = {};
        require(vkGetQueryPoolResults(c.device, query, 0, 1, sizeof(before), before, sizeof(before),
                VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WITH_AVAILABILITY_BIT) == VK_NOT_READY && before[1] == 0,
                "staged or prepared leading timestamp remains unavailable before submit");
        submitPrepared(c, {leading}); timestampAvailable(c, query);
        require(!PreparedInspection::hasPrefix(leading) && !PreparedInspection::encoder(leading) &&
                !PreparedInspection::head(leading) && PreparedInspection::replaySize(leading) == 0,
                "both adoption and whole replay release their original nodes once");
        if (mode >= 2) {
            const auto* words = static_cast<const uint64_t*>(results.bytes);
            require(words[0] == 0xa5a5a5a5a5a5a5a5ull && words[2] != 0 &&
                    words[3] == 0xa5a5a5a5a5a5a5a5ull, "timestamp result and guards survive deferred copy");
        }
        if (mode == 3) { computeOutput(state, [](uint32_t i) { return i * 17 + 19; }); }
        VK_CHECK(vkResetCommandBuffer(leading, 0));
    }
    vkResetQueryPool(c.device, query, 0, 1);
    auto canceled = c.begin();
    vkCmdWriteTimestamp(canceled, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, query, 0);
    bindPrepared(canceled, state, 23);
    VK_CHECK(vkEndCommandBuffer(canceled)); VK_CHECK(vkResetCommandBuffer(canceled, 0));
    require(!PreparedInspection::hasPrefix(canceled) && !PreparedInspection::head(canceled) &&
            PreparedInspection::replaySize(canceled) == 0, "cancel releases timestamp/state without native storage");
    uint64_t canceledResult[2] = {};
    require(vkGetQueryPoolResults(c.device, query, 0, 1, sizeof(canceledResult), canceledResult, sizeof(canceledResult),
            VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WITH_AVAILABILITY_BIT) == VK_NOT_READY && canceledResult[1] == 0,
            "canceling the lazy prefix never publishes availability");
}
int main() {
    setenv("MVK_CONFIG_USE_METAL4", "1", 1);
    @autoreleasepool {
        NSMutableArray* results = [NSMutableArray array]; unsigned failures = 0;
        auto test = [&](NSString* name, const std::function<void(Context&)>& body) {
            Context context; context.oneTime = true;
            try {
                context.initialize([name isEqualToString:@"mapped_latest_bytes_and_update_call_snapshot"]); body(context);
                [results addObject:@{@"name":name, @"passed":@YES, @"native_queue":@(context.isNative(context.queue)),
                    @"completed_before":@(context.nativeBefore), @"completed_after":@(context.nativeAfter)}];
            } catch (const std::exception& error) {
                ++failures;
                [results addObject:@{@"name":name, @"passed":@NO, @"error":[NSString stringWithUTF8String:error.what()]}];
            }
        };
        test(@"ended_canceled_prefix_has_no_gpu_effect", canceledPrepared);
        if (!failures) test(@"reverse_recorded_three_pools_ordered_single_submit", reverseRecordedThreePools);
        if (!failures) test(@"mapped_latest_bytes_and_update_call_snapshot", hostLatestAndUpdateSnapshot);
        if (!failures) test(@"compute_prefix_query_helper_suffix_preserves_state_once", mixedComputeQuerySuffix);
        if (!failures) test(@"destroyed_binding_layout_survives_actual_node_reuse", destroyedLayoutNodeReuse);
        if (!failures) test(@"state_only_then_query_remains_whole_late_without_child", stateOnlyThenQuery);
        NSDictionary* report = @{@"suite":@"metal4_prepared_recording_vulkan", @"planned_test_count":@6,
            @"test_count":@(results.count), @"failed":@(failures), @"passed":@(results.count-failures),
            @"private_header_inspection":@YES, @"game_executed":@NO, @"window_created":@NO, @"tests":results};
        NSData* json = [NSJSONSerialization dataWithJSONObject:report options:0 error:nil];
        std::fwrite(json.bytes, 1, json.length, stdout); std::fputc('\n', stdout);
        return failures ? 1 : 0;
    }
}
