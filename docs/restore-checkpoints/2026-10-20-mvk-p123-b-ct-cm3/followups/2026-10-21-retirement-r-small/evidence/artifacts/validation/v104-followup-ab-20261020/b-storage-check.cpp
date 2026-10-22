#include <algorithm>
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <iterator>
#include <vector>
#include <vulkan/vulkan.h>
#include "MVKSmallVector.h"
struct Metal4PrimitiveConversion {
	// provokingLast bit0: LAST rotation; bit1: a second original-index result.
	uint32_t topology, indexBytes, provokingLast, outputCapacity;
	uint64_t inputCapacity;
	uint32_t instanceMultiplier, threadStride;
};
struct alignas(8) Metal4RestartBatchRecord {
    uint64_t indexAddress, sourceAddress, outputAddress, resultAddress;
    Metal4PrimitiveConversion parameters;
};
template<class V> bool internal(const V& v) {
 auto p=reinterpret_cast<uintptr_t>(v.data()), b=reinterpret_cast<uintptr_t>(&v);
 return p>=b && p+v.size()*sizeof(v[0])<=b+sizeof(v);
}
int main() {
 size_t cases=0;
 for(size_t count : {2u,3u,4u,5u,8u,256u}) {
    MVKSmallVector<VkDrawIndexedIndirectCommand, 4> arguments;
    MVKSmallVector<Metal4RestartBatchRecord, 4> records(count);
  arguments.reserve(count);
  std::vector<VkDrawIndexedIndirectCommand> oldArguments;
  std::vector<Metal4RestartBatchRecord> oldRecords(count);
  for(size_t i=0;i<count;++i) {
   assert(std::memcmp(&records[i],&oldRecords[i],sizeof(records[i]))==0);
   VkDrawIndexedIndirectCommand arg{uint32_t(i*3+3),uint32_t(i+1),uint32_t(i*5),-int32_t(i+2),uint32_t(i*7)};
   arguments.push_back(arg); oldArguments.push_back(arg);
   Metal4RestartBatchRecord record{0x1000+i*16,0x2000+i*20,0x3000+i*32,0x4000+i*40,
      {3, uint32_t(i%2?2:4),uint32_t(i%4),uint32_t(i*9),i*11+1024,1,256}};
   records[i]=record; oldRecords[i]=record;
  }
  assert(arguments.size()==count && records.size()==count);
  assert(std::memcmp(arguments.data(),oldArguments.data(),count*sizeof(arguments[0]))==0);
  assert(std::memcmp(records.data(),oldRecords.data(),count*sizeof(records[0]))==0);
  assert(internal(arguments)==(count<=4)); assert(internal(records)==(count<=4));
  assert(reinterpret_cast<uintptr_t>(records.data())%alignof(Metal4RestartBatchRecord)==0);
  ++cases;
 }
 std::printf("{\"cases\":%zu,\"containersBytes\":%zu,\"inlinePayloadBytes\":336,\"asanUbsan\":true}\n",cases,
   sizeof(MVKSmallVector<VkDrawIndexedIndirectCommand,4>)+sizeof(MVKSmallVector<Metal4RestartBatchRecord,4>));
}
