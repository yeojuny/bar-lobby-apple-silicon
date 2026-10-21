// Production-linked image host-state and device-storage regressions.
#define main mvkVulkanIntegrationSuiteEntry
#include "metal4-vulkan-integration.mm"
#undef main
#include <thread>
#include <atomic>

static void mappedImage(Context& c, bool mapAfterCompletion) {
    VkImageCreateInfo ci{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    ci.imageType=VK_IMAGE_TYPE_2D; ci.format=VK_FORMAT_R8G8B8A8_UNORM; ci.extent={16,16,1};
    ci.mipLevels=1; ci.arrayLayers=1; ci.samples=VK_SAMPLE_COUNT_1_BIT;
    ci.tiling=VK_IMAGE_TILING_OPTIMAL; ci.usage=VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    VkImage image; VK_CHECK(vkCreateImage(c.device,&ci,nullptr,&image));
    VkMemoryRequirements req; vkGetImageMemoryRequirements(c.device,image,&req);
    VkMemoryDedicatedAllocateInfo dedicated{VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO}; dedicated.image=image;
    VkMemoryAllocateInfo ai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO}; ai.pNext=&dedicated; ai.allocationSize=req.size;
    ai.memoryTypeIndex=c.memoryType(req.memoryTypeBits,VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    VkDeviceMemory memory; VK_CHECK(vkAllocateMemory(c.device,&ai,nullptr,&memory));
    VK_CHECK(vkBindImageMemory(c.device,image,memory,0));
    void* bytes=nullptr;
    if(!mapAfterCompletion) { VK_CHECK(vkMapMemory(c.device,memory,0,VK_WHOLE_SIZE,0,&bytes)); std::memset(bytes,0xA5,req.size); }
    auto command=c.begin(); VkImageMemoryBarrier b{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER}; b.image=image;
    b.srcQueueFamilyIndex=b.dstQueueFamilyIndex=VK_QUEUE_FAMILY_IGNORED; b.subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1};
    b.oldLayout=VK_IMAGE_LAYOUT_UNDEFINED; b.newLayout=VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL; b.dstAccessMask=VK_ACCESS_TRANSFER_WRITE_BIT;
    vkCmdPipelineBarrier(command,VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT,0,0,nullptr,0,nullptr,1,&b);
    VkClearColorValue color{{1,0,1,1}}; vkCmdClearColorImage(command,image,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,&color,1,&b.subresourceRange);
    b.oldLayout=b.newLayout; b.newLayout=VK_IMAGE_LAYOUT_GENERAL; b.srcAccessMask=VK_ACCESS_TRANSFER_WRITE_BIT; b.dstAccessMask=VK_ACCESS_HOST_READ_BIT;
    vkCmdPipelineBarrier(command,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_PIPELINE_STAGE_HOST_BIT,0,0,nullptr,0,nullptr,1,&b);
    c.submit(command);
    if(mapAfterCompletion) VK_CHECK(vkMapMemory(c.device,memory,0,VK_WHOLE_SIZE,0,&bytes));
    // MoltenVK's dedicated mapped optimal-image backing is a driver-specific CPU shadow.
    // Verify its first texel row without making an invalid Vulkan linear-layout
    // query or claiming this byte layout is portable to other Vulkan drivers.
    const uint8_t expected[4]={255,0,255,255};
    for(unsigned i=0;i<64;++i) require(static_cast<uint8_t*>(bytes)[i]==expected[i%4],"mapped image shadow mode="+std::to_string(mapAfterCompletion)+" byte="+std::to_string(i)+" actual="+std::to_string(static_cast<uint8_t*>(bytes)[i]));
    vkUnmapMemory(c.device,memory); vkDestroyImage(c.device,image,nullptr); vkFreeMemory(c.device,memory,nullptr);
}
static void sharedStorage(Context& c) {
    require(c.secondQueue,"two queues");
    auto src=c.buffer(4096,VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
    auto a=c.buffer(4096,VK_BUFFER_USAGE_TRANSFER_DST_BIT), b=c.buffer(4096,VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    for(unsigned i=0;i<4096;++i) static_cast<uint8_t*>(src.bytes)[i]=uint8_t(i*13+7);
    std::memset(a.bytes,0,4096);std::memset(b.bytes,0,4096);
    VkCommandBuffer cmds[2]={c.begin(),c.begin(true)};
    for(unsigned i=0;i<2;++i) {
        VkBufferCopy region{1,3,4001}; vkCmdCopyBuffer(cmds[i],src.buffer,i?b.buffer:a.buffer,1,&region);
        barrier(cmds[i],VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_TRANSFER_WRITE_BIT,VK_PIPELINE_STAGE_HOST_BIT,VK_ACCESS_HOST_READ_BIT);
        VK_CHECK(vkEndCommandBuffer(cmds[i]));
    }
    std::atomic<bool> start{false}; VkResult status[2]={VK_NOT_READY,VK_NOT_READY};
    auto submit=[&](unsigned i) { @autoreleasepool {
        while(!start.load(std::memory_order_acquire)) std::this_thread::yield();
        VkSubmitInfo info{VK_STRUCTURE_TYPE_SUBMIT_INFO};info.commandBufferCount=1;info.pCommandBuffers=&cmds[i];
        status[i]=vkQueueSubmit(i?c.secondQueue:c.queue,1,&info,VK_NULL_HANDLE);
    }};
    c.inFlight=true;std::thread t0(submit,0),t1(submit,1);start.store(true,std::memory_order_release);t0.join();t1.join();
    VK_CHECK(status[0]);VK_CHECK(status[1]);VK_CHECK(vkQueueWaitIdle(c.queue));VK_CHECK(vkQueueWaitIdle(c.secondQueue));c.inFlight=false;
    for(auto output:{a,b}) {
        auto* bytes=static_cast<uint8_t*>(output.bytes);
        for(unsigned i=0;i<4096;++i) require(bytes[i]==(i>=3&&i<4004?static_cast<uint8_t*>(src.bytes)[i-2]:0),"parallel helper copy and guards");
    }
    VK_CHECK(vkResetCommandPool(c.device,c.pool,VK_COMMAND_POOL_RESET_RELEASE_RESOURCES_BIT));
    VK_CHECK(vkResetCommandPool(c.device,c.secondPool,VK_COMMAND_POOL_RESET_RELEASE_RESOURCES_BIT));
    // Recreate the same helper state after pool reset, with a fresh allocation.
    transfer(c);
}
int main() { @autoreleasepool {
    try { Context c;c.initialize();mappedImage(c,false);mappedImage(c,true);sharedStorage(c);
        std::puts("{\"suite\":\"r66_vulkan_host_state_and_pool\",\"passed\":3,\"failed\":0,\"windowCreated\":false}");return 0;
    } catch(const std::exception& error) { std::fprintf(stderr,"%s\n",error.what());return 1; }
}}
