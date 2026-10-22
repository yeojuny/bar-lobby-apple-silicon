#include <stddef.h>
#include "zink_context.h"
unsigned long long zinkContextSize=sizeof(struct zink_context);
unsigned long long vertexUBOOffset=offsetof(struct zink_context,di.t.ubos[MESA_SHADER_VERTEX][0]);
unsigned long long fragmentUBOOffset=offsetof(struct zink_context,di.t.ubos[MESA_SHADER_FRAGMENT][0]);
unsigned long long computeUBOOffset=offsetof(struct zink_context,di.t.ubos[MESA_SHADER_COMPUTE][0]);
unsigned long long descriptorInfoSize=sizeof(VkDescriptorBufferInfo);
unsigned long long descriptorWriteSize=sizeof(VkWriteDescriptorSet);
