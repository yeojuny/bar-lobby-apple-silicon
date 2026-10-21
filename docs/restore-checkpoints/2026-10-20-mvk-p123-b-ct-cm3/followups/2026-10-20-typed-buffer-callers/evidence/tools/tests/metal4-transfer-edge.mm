// Extra native transfer coverage for Recoil's cube-map mipmap consumers.
// Reuse the production-linked Vulkan setup/fixtures without running its suite.
#define main mvkVulkanIntegrationSuiteEntry
#include "metal4-vulkan-integration.mm"
#undef main

namespace {
void cubeMipmapLayers(Context& c, bool subset) {
    constexpr uint32_t width = 8, levels = 4, rowBytes = 256, layerBytes = rowBytes * width, guard = 256;
    const uint32_t layers = subset ? 12 : 6;
    VkImageCreateInfo create{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    create.flags = VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT; create.imageType = VK_IMAGE_TYPE_2D;
    create.format = VK_FORMAT_R8G8B8A8_UNORM; create.extent = {width, width, 1};
    create.mipLevels = levels; create.arrayLayers = layers; create.samples = VK_SAMPLE_COUNT_1_BIT;
    create.tiling = VK_IMAGE_TILING_OPTIMAL;
    create.usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
    VkImage image; VK_CHECK(vkCreateImage(c.device, &create, nullptr, &image));
    VkMemoryRequirements requirements{}; vkGetImageMemoryRequirements(c.device, image, &requirements);
    VkMemoryAllocateInfo allocation{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO}; allocation.allocationSize = requirements.size;
    allocation.memoryTypeIndex = c.memoryType(requirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    VkDeviceMemory memory; VK_CHECK(vkAllocateMemory(c.device, &allocation, nullptr, &memory));
    VK_CHECK(vkBindImageMemory(c.device, image, memory, 0));
    c.cleanup.push_back([&, image, memory] { vkDestroyImage(c.device, image, nullptr); vkFreeMemory(c.device, memory, nullptr); });
    // Explicit cube views establish valid cube-compatible face groups. The
    // transfer commands still address the underlying Vulkan array layers.
    for (uint32_t base = 0; base < layers; base += 6) {
        VkImageViewCreateInfo viewInfo{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO}; viewInfo.image = image;
        viewInfo.viewType = VK_IMAGE_VIEW_TYPE_CUBE; viewInfo.format = create.format;
        viewInfo.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, levels, base, 6};
        VkImageView view; VK_CHECK(vkCreateImageView(c.device, &viewInfo, nullptr, &view));
        c.cleanup.push_back([&, view] { vkDestroyImageView(c.device, view, nullptr); });
    }
    auto upload = c.buffer(layers * width * width * 4, VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
    auto readback = c.buffer(guard * 2 + levels * layers * layerBytes, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    auto* input = static_cast<uint8_t*>(upload.bytes);
    for (uint32_t layer = 0; layer < layers; ++layer) for (uint32_t y = 0; y < width; ++y) for (uint32_t x = 0; x < width; ++x) {
        const uint8_t pixel[4] = {uint8_t(8 + 12 * layer + 8 * x), uint8_t(16 + 4 * layer + 8 * y),
                                  uint8_t(24 + 8 * layer + 4 * (x + y)), 255};
        std::memcpy(input + ((layer * width + y) * width + x) * 4, pixel, sizeof(pixel));
    }
    std::memset(readback.bytes, 0xA5, readback.size);
    VkCommandBuffer command = c.begin();
    VkImageMemoryBarrier transition{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER}; transition.image = image;
    transition.srcQueueFamilyIndex = transition.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    transition.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, levels, 0, layers};
    transition.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED; transition.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    transition.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &transition);
    VkClearColorValue untouched{{1, 0, 1, 1}};
    vkCmdClearColorImage(command, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &untouched, 1, &transition.subresourceRange);
    barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT);
    std::vector<VkBufferImageCopy> uploads(layers);
    for (uint32_t layer = 0; layer < layers; ++layer) {
        uploads[layer].bufferOffset = layer * width * width * 4;
        uploads[layer].imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, layer, 1}; uploads[layer].imageExtent = {width, width, 1};
    }
    vkCmdCopyBufferToImage(command, upload.buffer, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, layers, uploads.data());
    transition.subresourceRange.levelCount = 1; transition.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    transition.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    transition.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; transition.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    for (uint32_t level = 0; level < levels; ++level) {
        transition.subresourceRange.baseMipLevel = level;
        vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &transition);
        if (level + 1 == levels) break;
        VkImageBlit blits[2]{};
        const uint32_t count = subset ? 2 : 1;
        for (uint32_t index = 0; index < count; ++index) {
            uint32_t base = subset ? (index ? 7 : 1) : 0, length = subset ? (index ? 3 : 2) : layers;
            blits[index].srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, level, base, length};
            blits[index].dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, level + 1, base, length};
            blits[index].srcOffsets[1] = {int32_t(width >> level), int32_t(width >> level), 1};
            blits[index].dstOffsets[1] = {int32_t(width >> (level + 1)), int32_t(width >> (level + 1)), 1};
        }
        vkCmdBlitImage(command, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, count, blits, VK_FILTER_LINEAR);
    }
    std::vector<VkBufferImageCopy> copies(levels * layers);
    for (uint32_t level = 0; level < levels; ++level) for (uint32_t layer = 0; layer < layers; ++layer) {
        auto& copy = copies[level * layers + layer];
        copy.bufferOffset = guard + (level * layers + layer) * layerBytes; copy.bufferRowLength = rowBytes / 4;
        copy.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, level, layer, 1}; copy.imageExtent = {width >> level, width >> level, 1};
    }
    vkCmdCopyImageToBuffer(command, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback.buffer, uint32_t(copies.size()), copies.data());
    barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
    c.submit(command);
    const auto* bytes = static_cast<const uint8_t*>(readback.bytes);
    for (uint32_t i = 0; i < readback.size; ++i) {
        uint32_t slot = i >= guard ? (i - guard) / layerBytes : levels * layers;
        uint32_t level = slot / layers, layer = slot % layers, local = i >= guard ? (i - guard) % layerBytes : 0;
        bool pixel = level < levels && local / rowBytes < (width >> level) && local % rowBytes < (width >> level) * 4;
        if (!pixel) { require(bytes[i] == 0xA5, "cube mipmap padding/guard mismatch at " + std::to_string(i)); continue; }
        uint32_t x = (local % rowBytes) / 4, y = local / rowBytes, scale = 1u << level;
        int expected[4] = {int(8 + 12 * layer + 8 * scale * x + 4 * (scale - 1)),
                           int(16 + 4 * layer + 8 * scale * y + 4 * (scale - 1)),
                           int(24 + 8 * layer + 4 * scale * (x + y) + 4 * (scale - 1)), 255};
        bool selected = !subset || (layer >= 1 && layer < 3) || (layer >= 7 && layer < 10);
        if (level > 0 && !selected) { expected[0] = expected[2] = expected[3] = 255; expected[1] = 0; }
        require(std::abs(int(bytes[i]) - expected[local % 4]) <= 1,
            "cube face/layer isolation mismatch at mip " + std::to_string(level) + " layer " + std::to_string(layer) + " byte " + std::to_string(i));
    }
}

VkImage transferVolume(Context& c, uint32_t size, uint32_t levels) {
    VkImageCreateInfo create{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO}; create.imageType = VK_IMAGE_TYPE_3D;
    create.format = VK_FORMAT_R8G8B8A8_UNORM; create.extent = {size, size, size}; create.mipLevels = levels;
    create.arrayLayers = 1; create.samples = VK_SAMPLE_COUNT_1_BIT; create.tiling = VK_IMAGE_TILING_OPTIMAL;
    create.usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
    VkImage image; VK_CHECK(vkCreateImage(c.device, &create, nullptr, &image));
    VkMemoryRequirements requirements{}; vkGetImageMemoryRequirements(c.device, image, &requirements);
    VkMemoryAllocateInfo allocation{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO}; allocation.allocationSize = requirements.size;
    allocation.memoryTypeIndex = c.memoryType(requirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    VkDeviceMemory memory; VK_CHECK(vkAllocateMemory(c.device, &allocation, nullptr, &memory));
    VK_CHECK(vkBindImageMemory(c.device, image, memory, 0));
    c.cleanup.push_back([&, image, memory] { vkDestroyImage(c.device, image, nullptr); vkFreeMemory(c.device, memory, nullptr); });
    return image;
}

void volumeBlit(Context& c, bool reversedPartial) {
    constexpr uint32_t width = 8, rowBytes = 256, planeBytes = rowBytes * width, volumeBytes = planeBytes * width, guard = 256;
    const uint32_t levels = reversedPartial ? 1 : 4;
    VkImage source = transferVolume(c, width, levels);
    VkImage destination = reversedPartial ? transferVolume(c, width, 1) : source;
    auto upload = c.buffer(width * width * width * 4, VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
    auto readback = c.buffer(guard * 2 + volumeBytes * levels, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    auto* input = static_cast<uint8_t*>(upload.bytes);
    for (uint32_t z = 0; z < width; ++z) for (uint32_t y = 0; y < width; ++y) for (uint32_t x = 0; x < width; ++x) {
        const uint8_t pixel[4] = {uint8_t(16 + 16 * x + 8 * z), uint8_t(24 + 16 * y + 4 * z), uint8_t(32 + 16 * z + 4 * x + 4 * y), 255};
        std::memcpy(input + ((z * width + y) * width + x) * 4, pixel, sizeof(pixel));
    }
    std::memset(readback.bytes, 0xA5, readback.size);
    VkCommandBuffer command = c.begin();
    VkImageMemoryBarrier transition{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER}; transition.image = source;
    transition.srcQueueFamilyIndex = transition.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    transition.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, levels, 0, 1};
    transition.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED; transition.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    transition.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &transition);
    VkBufferImageCopy uploadRegion{}; uploadRegion.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1}; uploadRegion.imageExtent = {width, width, width};
    vkCmdCopyBufferToImage(command, upload.buffer, source, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &uploadRegion);
    if (reversedPartial) {
        transition.image = destination;
        vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &transition);
        VkClearColorValue untouched{{1, 0, 1, 1}};
        vkCmdClearColorImage(command, destination, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &untouched, 1, &transition.subresourceRange);
        barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT,
                VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT);
    }
    transition.image = source; transition.subresourceRange.levelCount = 1;
    transition.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL; transition.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    transition.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; transition.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    for (uint32_t level = 0; level < levels; ++level) {
        transition.subresourceRange.baseMipLevel = level;
        vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &transition);
        if (!reversedPartial && level + 1 == levels) break;
        VkImageBlit blit{}; blit.srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, level, 0, 1};
        blit.dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, reversedPartial ? 0u : level + 1, 0, 1};
        int32_t srcSize = int32_t(width >> level), dstSize = int32_t(width >> (level + 1));
        blit.srcOffsets[1] = {srcSize, srcSize, srcSize};
        blit.dstOffsets[1] = {dstSize, dstSize, dstSize};
        if (reversedPartial) { blit.dstOffsets[0] = {2, 2, 6}; blit.dstOffsets[1] = {6, 6, 2}; }
        vkCmdBlitImage(command, source, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, destination, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &blit, VK_FILTER_LINEAR);
    }
    if (reversedPartial) {
        transition.image = destination;
        vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &transition);
    }
    std::vector<VkBufferImageCopy> copies(levels);
    for (uint32_t level = 0; level < levels; ++level) {
        auto& copy = copies[level]; copy.bufferOffset = guard + level * volumeBytes;
        copy.bufferRowLength = rowBytes / 4; copy.bufferImageHeight = width;
        copy.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, level, 0, 1};
        copy.imageExtent = {width >> level, width >> level, width >> level};
    }
    vkCmdCopyImageToBuffer(command, destination, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback.buffer, levels, copies.data());
    barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
    c.submit(command);
    const auto* bytes = static_cast<const uint8_t*>(readback.bytes);
    for (uint32_t i = 0; i < readback.size; ++i) {
        uint32_t level = i >= guard ? (i - guard) / volumeBytes : levels;
        uint32_t local = i >= guard ? (i - guard) % volumeBytes : 0;
        uint32_t z = local / planeBytes, y = (local % planeBytes) / rowBytes, column = local % rowBytes;
        bool pixel = level < levels && z < (width >> level) && y < (width >> level) && column < (width >> level) * 4;
        if (!pixel) { require(bytes[i] == 0xA5, "volume mipmap row/plane/volume guard at " + std::to_string(i)); continue; }
        uint32_t x = column / 4, scale = 1u << level;
        int expected[4] = {int(16 + 16 * scale * x + 8 * scale * z + 12 * (scale - 1)),
                           int(24 + 16 * scale * y + 4 * scale * z + 10 * (scale - 1)),
                           int(32 + 16 * scale * z + 4 * scale * (x + y) + 12 * (scale - 1)), 255};
        if (reversedPartial) {
            if (x >= 2 && x < 6 && y >= 2 && y < 6 && z >= 2 && z < 6) {
                int dx = int(x) - 2, dy = int(y) - 2, dz = int(z) - 2;
                expected[0] = 76 + 32 * dx - 16 * dz; expected[1] = 58 + 32 * dy - 8 * dz;
                expected[2] = 140 + 8 * dx + 8 * dy - 32 * dz;
            } else { expected[0] = expected[2] = expected[3] = 255; expected[1] = 0; }
        }
        require(std::abs(int(bytes[i]) - expected[column % 4]) <= 1,
                "volume source-mip/Z interpolation mismatch at mip " + std::to_string(level) + " z " + std::to_string(z) + " byte " + std::to_string(i));
    }
}

void independentCopyRegions(Context& c, bool sameBuffer) {
    constexpr VkDeviceSize bytes = 1024, destinationBase = 2048, guard = 64;
    auto source = c.buffer(sameBuffer ? 4096 : bytes, VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, false);
    auto destination = sameBuffer ? source : c.buffer(bytes, VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, false);
    auto readback = c.buffer(bytes + 2 * guard, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    const VkDeviceSize base = sameBuffer ? destinationBase : 0;
    const VkBufferCopy relative[] = {{0, 32, 128}, {160, 400, 64}, {256, 160, 96},
        {128, 720, 16}, {512, 800, 128}, {768, 512, 64}};
    for (uint32_t cycle = 0; cycle < 2; ++cycle) {
        uint32_t pattern[bytes / 4];
        for (uint32_t i = 0; i < bytes / 4; ++i) pattern[i] = 0x51000000u + cycle * 0x10000u + 17 * i;
        std::memset(readback.bytes, 0xA5, readback.size);
        VkCommandBuffer command = c.begin();
        vkCmdFillBuffer(command, destination.buffer, base, bytes, 0xA5A5A5A5);
        vkCmdUpdateBuffer(command, source.buffer, 0, bytes, pattern);
        barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT,
                VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_READ_BIT | VK_ACCESS_TRANSFER_WRITE_BIT);
        VkBufferCopy regions[6];
        for (uint32_t i = 0; i < 6; ++i) { regions[i] = relative[i]; regions[i].dstOffset += base; }
        vkCmdCopyBuffer(command, source.buffer, destination.buffer, 6, regions);
        // A WAR dependency must complete the original reads before overwriting
        // their source. None of these barriers may be replaced by mere layout work.
        barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_READ_BIT | VK_ACCESS_TRANSFER_WRITE_BIT,
                VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT | VK_ACCESS_TRANSFER_READ_BIT);
        vkCmdFillBuffer(command, source.buffer, 0, bytes, 0xDEADBEEF);
        VkBufferCopy output{base, guard, bytes};
        vkCmdCopyBuffer(command, destination.buffer, readback.buffer, 1, &output);
        barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT,
                VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
        c.submit(command);
        const auto* actual = static_cast<const uint8_t*>(readback.bytes);
        for (VkDeviceSize i = 0; i < readback.size; ++i) {
            uint8_t expected = 0xA5;
            if (i >= guard && i < guard + bytes) for (const auto& region : relative) {
                VkDeviceSize local = i - guard;
                if (local >= region.dstOffset && local - region.dstOffset < region.size)
                    expected = reinterpret_cast<const uint8_t*>(pattern)[region.srcOffset + local - region.dstOffset];
            }
            require(actual[i] == expected, "independent copy region/WAR/guard mismatch at " + std::to_string(i));
        }
    }
}

void copyComputeContinuation(Context& c) {
    constexpr uint32_t count = 64, guard = 64, resultBytes = count * 4;
    auto output = c.buffer(resultBytes, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT, false);
    auto params = c.buffer(16, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, false);
    auto input = c.buffer(16, VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
    auto readback = c.buffer(guard * 2 + resultBytes * 2, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    const uint32_t values[4] = {19, 0, 0xABCDEF01, 0}; std::memcpy(input.bytes, values, sizeof(values));
    std::memset(readback.bytes, 0xA5, readback.size);
    VkDescriptorSetLayoutBinding bindings[2] = {
        {0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr},
        {1, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr}};
    VkDescriptorSetLayoutCreateInfo setInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
    setInfo.bindingCount = 2; setInfo.pBindings = bindings;
    VkDescriptorSetLayout setLayout; VK_CHECK(vkCreateDescriptorSetLayout(c.device, &setInfo, nullptr, &setLayout));
    c.cleanup.push_back([&, setLayout] { vkDestroyDescriptorSetLayout(c.device, setLayout, nullptr); });
    VkPushConstantRange push{VK_SHADER_STAGE_COMPUTE_BIT, 0, 4};
    VkPipelineLayoutCreateInfo layoutInfo{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    layoutInfo.setLayoutCount = 1; layoutInfo.pSetLayouts = &setLayout;
    layoutInfo.pushConstantRangeCount = 1; layoutInfo.pPushConstantRanges = &push;
    VkPipelineLayout layout; VK_CHECK(vkCreatePipelineLayout(c.device, &layoutInfo, nullptr, &layout));
    c.cleanup.push_back([&, layout] { vkDestroyPipelineLayout(c.device, layout, nullptr); });
    VkComputePipelineCreateInfo pipelineInfo{VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO}; pipelineInfo.layout = layout;
    pipelineInfo.stage = {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, nullptr, 0, VK_SHADER_STAGE_COMPUTE_BIT, c.shader(computeShader()), "main", nullptr};
    VkPipeline pipeline; VK_CHECK(vkCreateComputePipelines(c.device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &pipeline));
    c.cleanup.push_back([&, pipeline] { vkDestroyPipeline(c.device, pipeline, nullptr); });
    VkDescriptorPoolSize sizes[2] = {{VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC, 1}, {VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1}};
    VkDescriptorPoolCreateInfo poolInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO}; poolInfo.maxSets = 1;
    poolInfo.poolSizeCount = 2; poolInfo.pPoolSizes = sizes;
    VkDescriptorPool pool; VK_CHECK(vkCreateDescriptorPool(c.device, &poolInfo, nullptr, &pool));
    c.cleanup.push_back([&, pool] { vkDestroyDescriptorPool(c.device, pool, nullptr); });
    VkDescriptorSetAllocateInfo allocate{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
    allocate.descriptorPool = pool; allocate.descriptorSetCount = 1; allocate.pSetLayouts = &setLayout;
    VkDescriptorSet set; VK_CHECK(vkAllocateDescriptorSets(c.device, &allocate, &set));
    VkDescriptorBufferInfo buffers[2] = {{output.buffer, 0, resultBytes}, {params.buffer, 0, 4}};
    VkWriteDescriptorSet writes[2]{};
    for (uint32_t i = 0; i < 2; ++i) {
        writes[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET; writes[i].dstSet = set; writes[i].dstBinding = i;
        writes[i].descriptorCount = 1; writes[i].descriptorType = bindings[i].descriptorType; writes[i].pBufferInfo = &buffers[i];
    }
    vkUpdateDescriptorSets(c.device, 2, writes, 0, nullptr);
    VkCommandBuffer command = c.begin();
    VkBufferCopy inputs[2] = {{0, 0, 4}, {8, 8, 4}};
    vkCmdCopyBuffer(command, input.buffer, params.buffer, 2, inputs);
    barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT,
            VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_UNIFORM_READ_BIT);
    vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    uint32_t dynamicOffset = 0, multiplier = 7;
    vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 1, &dynamicOffset);
    vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &multiplier);
    for (uint32_t cycle = 0; cycle < 2; ++cycle) {
        vkCmdDispatch(command, count, 1, 1);
        barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT | VK_ACCESS_UNIFORM_READ_BIT,
                VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_READ_BIT | VK_ACCESS_TRANSFER_WRITE_BIT);
        VkBufferCopy copy{0, guard + cycle * resultBytes, resultBytes};
        vkCmdCopyBuffer(command, output.buffer, readback.buffer, 1, &copy);
        if (!cycle) {
            vkCmdFillBuffer(command, params.buffer, 0, 4, 41);
            barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_READ_BIT | VK_ACCESS_TRANSFER_WRITE_BIT,
                    VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT | VK_ACCESS_UNIFORM_READ_BIT);
            // No application pipeline/root/constants rebind after fill helper.
        }
    }
    barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT,
            VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);
    c.submit(command);
    const auto* actual = static_cast<const uint32_t*>(readback.bytes);
    for (uint32_t i = 0; i < readback.size / 4; ++i) {
        uint32_t expected = 0xA5A5A5A5;
        if (i >= guard / 4 && i < guard / 4 + 2 * count) {
            uint32_t local = i - guard / 4; expected = (local % count) * 7 + (local < count ? 19 : 41);
        }
        require(actual[i] == expected, "copy/dispatch/helper continuation or guard mismatch at " + std::to_string(i));
    }
}
}

int main() {
    setenv("MVK_CONFIG_USE_METAL4", "1", 1);
    @autoreleasepool {
        NSMutableArray* results = [NSMutableArray array]; unsigned failures = 0;
        for (unsigned variant = 0; variant < 9 && !failures; ++variant) {
            Context context;
            NSString* names[] = {@"cube_six_face_linear_mipmap_all_levels", @"cube_compatible_12_layers_subset_mips_preserve_other_layers",
                @"volume_linear_mipmaps_source_mip_depth", @"volume_scaled_reversed_z_partial_region_preservation",
                @"independent_copy_regions_distinct_allocations_and_war", @"independent_copy_regions_same_buffer_disjoint_ranges_and_war",
                @"copy_compute_fill_compute_same_encoder_root_restore", @"sampled_clear_draw_restore_msaa4_final_resolve",
                @"clear_draw_restore_occlusion_excludes_helper"};
            NSString* name = names[variant];
            try {
                context.initialize();
                if (variant < 2) cubeMipmapLayers(context, variant != 0);
                else if (variant < 4) volumeBlit(context, variant == 3);
                else if (variant < 6) independentCopyRegions(context, variant == 5);
                else if (variant == 6) copyComputeContinuation(context);
                else render(context, variant == 7, true, variant == 7 ? 1 : 0, 0, variant == 8);
                [results addObject:@{@"name":name, @"passed":@YES, @"native_queue":@(context.isNative(context.queue)),
                    @"uses_argument_buffers":@(context.usesArgumentBuffers(context.queue)),
                    @"completed_before":@(context.nativeBefore), @"completed_after":@(context.nativeAfter)}];
            } catch (const std::exception& error) {
                ++failures; [results addObject:@{@"name":name, @"passed":@NO, @"error":[NSString stringWithUTF8String:error.what()]}];
            }
        }
        NSDictionary* report = @{@"suite":@"metal4_transfer_edges", @"requested_metal4":@YES, @"bar_acceptance":@NO,
            @"test_count":@(results.count), @"planned_test_count":@9, @"passed":@(results.count - failures), @"failed":@(failures), @"tests":results};
        NSData* json = [NSJSONSerialization dataWithJSONObject:report options:0 error:nil];
        std::fwrite(json.bytes, 1, json.length, stdout); std::fputc('\n', stdout);
        return failures ? 1 : 0;
    }
}
