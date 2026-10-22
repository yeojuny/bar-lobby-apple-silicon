// Actual production emission and compute-local barrier block are supplied by
// the runner. Native receivers are CPU doubles; this creates no GPU device.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "MVKMetal4DependencyScopes.h"
#include <cassert>
#include <cstdio>
#include <vector>
using Scopes=MVKMetal4DependencyScopes<MTLStageVertex,MTLStageFragment,MTLStageDispatch,MTLStageBlit>;
using Summary=MVKMetal4PreparedDependencySummary<MTLStageVertex,MTLStageFragment,MTLStageDispatch,MTLStageBlit>;
struct Edge { MTLStages sources,destinations;MTL4VisibilityOptions visibility; };
@interface QueueBarrierCPU : NSObject { @public std::vector<Edge> queue,local; }
- (void)barrierAfterQueueStages:(MTLStages)s beforeStages:(MTLStages)d visibilityOptions:(MTL4VisibilityOptions)v;
- (void)barrierAfterEncoderStages:(MTLStages)s beforeEncoderStages:(MTLStages)d visibilityOptions:(MTL4VisibilityOptions)v;
@end
@implementation QueueBarrierCPU
- (void)barrierAfterQueueStages:(MTLStages)s beforeStages:(MTLStages)d visibilityOptions:(MTL4VisibilityOptions)v {queue.push_back({s,d,v});}
- (void)barrierAfterEncoderStages:(MTLStages)s beforeEncoderStages:(MTLStages)d visibilityOptions:(MTL4VisibilityOptions)v {local.push_back({s,d,v});}
@end
struct Stats {unsigned computeBarrierContinuations=0;};
struct MVKCommandEncoder {
 Scopes _metal4Dependencies,_metal4EncoderDependencies,_metal4ComputeQueueDependencies;
 Summary _metal4PreparedSummary;bool _metal4CollectPreparedDependencies=true;
 id<MTL4ComputeCommandEncoder> _mtl4ComputeEncoder=nil;
 Stats stats;Stats* getMetal4EncodingStats(){return &stats;}
 void encodeMetal4PendingDependencies(id<MTL4CommandEncoder>,MTLStages,MTLStages=0);
 void computeBarrier(MTLStages sourceStages,MTLStages destinationStages,bool memoryDependency);
 MVKCommandEncoder(){_metal4Dependencies.satisfy(Scopes::all,Scopes::all);_metal4EncoderDependencies.satisfy(Scopes::all,Scopes::all);_metal4ComputeQueueDependencies.satisfy(Scopes::all,Scopes::all);}
};
#include MVK_QUEUE_BARRIER_BODY
int main(){@autoreleasepool{
 unsigned checks=0;auto check=[&](bool v){assert(v);++checks;};
 // Exhaust the stage-pair lattice independently: a required edge remains iff
 // that pair lacks sufficient execution/memory coverage, only in selected dst.
 for(unsigned need=0;need<256;++need)for(unsigned covered=0;covered<256;++covered){
  Scopes p,e;p.satisfy(Scopes::all,Scopes::all);e.satisfy(Scopes::all,Scopes::all);
  for(unsigned d=0;d<4;++d)for(unsigned s=0;s<4;++s){
   if(need&(1u<<s))p.add(Scopes::stages[s],Scopes::stages[d],need&(1u<<(s+4)));
   if(covered&(1u<<s))e.add(Scopes::stages[s],Scopes::stages[d],covered&(1u<<(s+4)));
  }
  Scopes old=p;p.satisfyAlreadyEmitted(e,MTLStageDispatch|MTLStageBlit);
  for(unsigned d=0;d<4;++d)for(unsigned s=0;s<4;++s){auto bit=Scopes::stages[s];
   bool required=old.sources[d]&bit,visible=old.memory[d]&bit;
   bool satisfied=d>=2&&(e.sources[d]&bit)&&(!visible||(e.memory[d]&bit));
   check(bool(p.sources[d]&bit)==(required&&!satisfied));check(bool(p.memory[d]&bit)==(visible&&!satisfied));
  }
 }
 auto* receiver=[QueueBarrierCPU new];MVKCommandEncoder c;c._mtl4ComputeEncoder=(id<MTL4ComputeCommandEncoder>)receiver;
 c.computeBarrier(MTLStageDispatch,MTLStageDispatch,true);
 check(receiver->queue.size()==1&&receiver->local.size()==1);
 c._metal4PreparedSummary={};c.computeBarrier(MTLStageDispatch,MTLStageDispatch,true);
 check(receiver->queue.size()==1&&receiver->local.size()==2);
 check(c._metal4PreparedSummary.consumedDestinations==MTLStageDispatch);
 check(c._metal4EncoderDependencies.memory[2]&MTLStageDispatch);
 c.computeBarrier(MTLStageBlit,MTLStageDispatch,false);check(receiver->queue.size()==2);
 c.computeBarrier(MTLStageBlit,MTLStageDispatch,true);check(receiver->queue.size()==3);
 c.computeBarrier(MTLStageBlit,MTLStageDispatch,false);check(receiver->queue.size()==3&&receiver->local.size()==5);
 c.encodeMetal4PendingDependencies((id<MTL4CommandEncoder>)receiver,MTLStageDispatch,MTLStageDispatch|MTLStageBlit);
 check(receiver->queue.size()==3);
 c._metal4Dependencies.add(MTLStageDispatch,MTLStageFragment,true);
 c.encodeMetal4PendingDependencies((id<MTL4CommandEncoder>)receiver,MTLStageFragment);
 c._metal4Dependencies.add(MTLStageDispatch,MTLStageFragment,true);
 c.encodeMetal4PendingDependencies((id<MTL4CommandEncoder>)receiver,MTLStageFragment);
 check(receiver->queue.size()==5); // Graphics destination intentionally excluded.
 c._metal4ComputeQueueDependencies.satisfy(Scopes::all,Scopes::all);
 c.computeBarrier(MTLStageDispatch,MTLStageDispatch,true);check(receiver->queue.size()==6);
 auto* render=[QueueBarrierCPU new];c._metal4Dependencies.add(MTLStageDispatch,MTLStageDispatch,true);
 c.encodeMetal4PendingDependencies((id<MTL4CommandEncoder>)render,MTLStageDispatch);check(render->queue.size()==1);
 [render release];[receiver release];printf("PASS %u checks; production queue emission and compute-local block; GPU=false\n",checks);
}}
