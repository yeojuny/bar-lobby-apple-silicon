#!/usr/bin/env python3
"""CPU-only exact prepared-resource helpers/registry and admission regression."""
from pathlib import Path
import hashlib,json,subprocess,re,sys
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK'
OUT=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else ROOT/'artifacts/validation/metal4-r42-structural-20261004/binding-cpu'
OUT.mkdir(parents=True,exist_ok=True)
files=['GPUObjects/MVKMetal4PreparedResource.h','GPUObjects/MVKDevice.h','GPUObjects/MVKDevice.mm','GPUObjects/MVKImage.h','GPUObjects/MVKImage.mm','Commands/MVKCommandEncoderState.h','Commands/MVKCommandEncoderState.mm']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
pins={n:sha(BASE/n) for n in files}
dev=(BASE/files[2]).read_text();state=(BASE/files[-1]).read_text()
membership=dev[dev.index('void MVKLiveList::add(id object) {'):dev.index('\nstd::pair<MVKLiveList::Lock*, bool>')]
proofs=dev[dev.index('void MVKLiveList::addPrepared('):dev.index('\n#pragma mark - MVKVisibilityBuffer')]
lookup_start=state.index('if (textureCacheEligible) {')
lookup_branch=state[lookup_start:state.index('\n\t\t\t\tstd::vector<MVKMetal4PreparedResourceProof> textureProofs;',lookup_start)]
assert lookup_branch.count('texturePreparation.lookup(')==1
assert 'texturePreparation.matches(' not in lookup_branch and 'texturePreparation.shouldAttempt(' not in lookup_branch
payload=state.index('auto captureSnapshot =')
start=state.index('auto live = liveResources.textures.isLive(value);',payload)
branch=state[start:state.index('\n\t\t\t\t}\n\t\t\t\tif (counts.buffer',start)]
start=state.index('auto live = liveResources.isLive(static_cast<id<MTLSamplerState>>(value));',payload)
sampler_branch=state[start:state.index('\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t}',start)]
assert branch.count('preparationProof(value, live)')==1
assert sampler_branch.count('preparationProof(value, live)')==1
# Only erase the native Objective-C sampler type in this CPU registry fixture.
sampler_cpp=sampler_branch.replace('static_cast<id<MTLSamplerState>>(value)','value')
source=r'''
#include "MVKMetal4PreparedResource.h"
#include <atomic>
#include <mutex>
#include <thread>
#include <cstdio>
#include <stdexcept>
#include <functional>
using id = const void*;
class FixtureLiveList {
public:
    using Lock = std::mutex;
    struct Group { Lock lock; std::unordered_map<id,uint32_t> entries; std::unordered_map<id,MVKMetal4PreparedResourceIdentity> preparationIdentities; std::unordered_map<id,std::shared_ptr<void>> membershipIdentities; };
    Group groups[16]; std::atomic<uint64_t> _generation{1};
    Group* getGroup(id object) { return &groups[(reinterpret_cast<uintptr_t>(object)>>4)%16]; }
    struct IsLiveResult {
        Lock* lock; bool value;
        IsLiveResult(Lock* l,bool v):lock(l),value(v) {}
        IsLiveResult(IsLiveResult&&)=delete;
        ~IsLiveResult(){lock->unlock();}
        operator bool() const {return value;}
    };
    IsLiveResult isLive(id object) {auto*g=getGroup(object);g->lock.lock();return {&g->lock,g->entries.count(object)!=0};}
    void add(id); void remove(id); void advanceGeneration();
    void addPrepared(id,const MVKMetal4PreparedResourceProof* parent=nullptr);
    MVKMetal4PreparedResourceProof preparationProof(id,const IsLiveResult&);
    MVKMetal4PreparedResourceProof membershipProof(id,const IsLiveResult&);
    uint64_t generation()const{return _generation.load(std::memory_order_acquire);}
};
''' + (membership+proofs).replace('MVKLiveList::','FixtureLiveList::') + r'''
static unsigned assertions=0;
void require(bool value,const char*msg){++assertions;if(!value)throw std::runtime_error(msg);}
MVKMetal4PreparedResourceProof proof(FixtureLiveList& list,id object){auto live=list.isLive(object);return list.preparationProof(object,live);}
struct Sink {bool success=true;unsigned registrations=0,appendedGroups=0;bool resource(id){++registrations;return success;} bool object(id value){return resource(value);}};
// Execute the exact production first-use live/retain/proof branch.
bool scan(MVKMetal4PreparedTextureBindingCache& cache,FixtureLiveList& list,Sink&sink,id value,
          uint64_t incarnation=1,uint64_t revision=1,uint32_t binding=0,
          bool sampler=false,bool snapshotEligible=false,std::function<void()> afterSnapshot={}){
    auto& texturePreparation=cache;
    bool textureCacheEligible=true;
    struct Preparation {uint64_t incarnation;};
    struct Set {Preparation metal4Preparation;} payload{{incarnation}};
    auto* set=&payload;
    uint64_t bindingRevision=revision;
    struct Used {uint32_t bindingIdx;} used{binding};
    uint32_t count=1;
    struct Counts {uint32_t texture,sampler;} counts{sampler?0u:1u,sampler?1u:0u};
    struct Stats {unsigned textureCacheEligible=0,textureCacheHits=0,textureCacheMisses=0,textureProofAttempts=0,textureNegativeMemoSkips=0;uint64_t textureHitResourceSlots=0;};
    Stats* stats=nullptr;
    auto appendGroupBinding=[&](const Preparation&,uint32_t,uint64_t){++sink.appendedGroups;};
''' + lookup_branch + r'''
    bool allTexturesProven=textureCacheEligible;
    bool attempted=allTexturesProven;
    struct LiveResources {
        FixtureLiveList& textures; FixtureLiveList& samplers;
        auto isLive(id value) { return samplers.isLive(value); }
    } liveResources{list,list};
    using Snapshots=MVKMetal4PreparedBindingSnapshots;
    constexpr auto nil=nullptr;
    auto captureSnapshot=[&](id value,Snapshots::Kind,const MVKMetal4PreparedResourceProof& p){
        if(!snapshotEligible)return;
        if(!value||!p.valid()){snapshotEligible=false;return;}
        if(afterSnapshot)afterSnapshot();
    };
    std::vector<MVKMetal4PreparedResourceProof> textureProofs;
    if(sampler){
''' + sampler_cpp + r'''
    }else{
''' + branch + r'''
    }
    if(allTexturesProven) cache.remember(incarnation,revision,binding,std::move(textureProofs));
    else if(attempted) cache.reject(incarnation,revision,binding);
    return true;
}
int main(){
    FixtureLiveList list;
    id root=(id)16,view=(id)32,other=(id)48;
    list.addPrepared(root);auto rootProof=proof(list,root);
    require(rootProof.valid(),"owned allocation proof admitted");
    list.addPrepared(view,&rootProof);auto viewProof=proof(list,view);
    require(viewProof.valid()&&viewProof.count==2,"view depends on exact base incarnation");
    MVKMetal4PreparedTextureBindingCache cache;Sink sink;
    require(scan(cache,list,sink,view)&&sink.registrations==1&&cache.matches(1,1,0),"first full validation retained and admitted");
    require(scan(cache,list,sink,view)&&sink.registrations==1,"same recording hit removes live/registration scan");
    require(!cache.matches(1,2,0)&&scan(cache,list,sink,view,1,2)&&sink.registrations==2,"descriptor revision requires fresh retention validation");
    require(!cache.matches(1,2,1),"shader-used binding identity differs");
    require(!cache.matches(2,2,0),"pool incarnation differs");
    cache.clear();require(!cache.matches(1,2,0),"recording change clears preparation");
    list.remove(root);require(!rootProof.valid()&&!viewProof.valid(),"base release revokes retained native view proof");
    list.addPrepared(root);require(proof(list,root).valid()&&!viewProof.valid(),"same address new allocation cannot resurrect old view proof");
    Sink unproved;require(scan(cache,list,unproved,view)&&!cache.matches(1,1,0),"stale parent never admitted");
    require(!cache.shouldAttempt(1,1,0)&&scan(cache,list,unproved,view)&&unproved.registrations==2,"negative memo preserves original validation");
    require(cache.shouldAttempt(1,2,0),"revision allows negative admission retry");
    cache.clear();require(cache.shouldAttempt(1,1,0),"new recording allows negative admission retry");
    auto currentRoot=proof(list,root);list.addPrepared(other,&currentRoot);auto otherProof=proof(list,other);
    list.add(other);require(!otherProof.valid()&&!proof(list,other).valid(),"unproved alias registration revokes prepared identity");
    list.remove(other);list.addPrepared(other,&currentRoot);require(!proof(list,other).valid(),"remaining unknown owner cannot be promoted");
    list.remove(other);list.remove(other);list.addPrepared(other,&currentRoot);require(proof(list,other).valid(),"new membership after final remove can qualify");
    list.addPrepared(root);list.remove(root);require(currentRoot.valid(),"immutable native shared owners preserve actual incarnation");
    list.remove(root);require(!currentRoot.valid()&&!proof(list,other).valid(),"last shared owner revokes child proof");
    list.addPrepared(nullptr);require(!proof(list,nullptr).valid(),"nil never admits");
    Sink dead;require(scan(cache,list,dead,(id)64)&&dead.registrations==0&&!cache.matches(1,1,0),"dead binding never retained or admitted");
    list.addPrepared((id)80);Sink failed;failed.success=false;cache.clear();
    require(!scan(cache,list,failed,(id)80)&&!cache.matches(1,1,0),"retention failure never admits");
    auto owned=proof(list,(id)80);std::vector<MVKMetal4PreparedResourceProof> full(16,owned),oversize(17,owned);
    cache.remember(7,1,0,full);require(cache.matches(7,1,0),"bounded16 resource payload admitted");
    require(full.size()==16&&full.front().valid(),"lvalue proof caller keeps its payload");
    std::vector<MVKMetal4PreparedResourceProof> moved{owned};
    cache.remember(7,1,2,std::move(moved));
    require(cache.matches(7,1,2),"rvalue proof payload remains valid after ownership transfer");
    cache.remember(7,1,1,oversize);require(!cache.matches(7,1,1),"oversize payload remains original path");
    cache.remember(0,1,0,full);cache.remember(8,0,0,full);require(!cache.matches(0,1,0)&&!cache.matches(8,0,0),"zero/saturated descriptor identities reject");
    cache.clear();for(unsigned i=0;i<257;++i)cache.remember(9,1,i,full);
    require(cache.matches(9,1,255)&&!cache.matches(9,1,256),"positive capacity bounded256");
    cache.clear();for(unsigned i=0;i<257;++i)cache.reject(10,1,i);
    require(!cache.shouldAttempt(10,1,255)&&cache.shouldAttempt(10,1,256)&&!cache.matches(10,1,255),"negative capacity shares same256 bound without hits");
    MVKMetal4PreparedResourceIdentity parent;auto chain=parent.proof();
    std::vector<std::unique_ptr<MVKMetal4PreparedResourceIdentity>> chainOwners;
    for(unsigned i=1;i<4;++i){auto next=std::make_unique<MVKMetal4PreparedResourceIdentity>();next->parents=chain;chain=next->proof();chainOwners.push_back(std::move(next));}
    require(chain.valid()&&chain.count==4,"bounded nested ordinary views retain all weak dependencies");
    MVKMetal4PreparedResourceIdentity tooDeep;tooDeep.parents=chain;require(!tooDeep.proof().valid(),"excess view depth excluded");
    chainOwners.front().reset();require(!chain.valid(),"intermediate view destruction revokes descendants");
    // Actual weak-control-block expiry races are safe to observe without locks.
    std::atomic<bool> released{false};auto owner=std::make_shared<int>(1);MVKMetal4PreparedResourceProof concurrent;concurrent.count=1;concurrent.owners[0]=owner;
    std::thread destroyer([&]{owner.reset();released.store(true,std::memory_order_release);});while(!released.load(std::memory_order_acquire)){(void)concurrent.valid();}destroyer.join();
    require(!concurrent.valid(),"concurrent token release cannot resurrect cache");
    for(bool sampler:{false,true}){
        FixtureLiveList raced;MVKMetal4PreparedTextureBindingCache prepared;Sink retained;
        raced.addPrepared(root);auto base=proof(raced,root);raced.addPrepared(view,&base);
        bool snapshotVisited=false;
        require(scan(prepared,raced,retained,view,30,1,0,sampler,true,[&]{
            snapshotVisited=true;raced.remove(root);
        }),"parent expiry between consumers preserves normal resource path");
        require(snapshotVisited&&retained.registrations==1&&!prepared.matches(30,1,0),
                "second consumer rejects expiry despite the native object's live guard");
        require(!prepared.shouldAttempt(30,1,0),"expired shared proof retains negative memo behavior");
        raced.remove(view);raced.addPrepared(root);base=proof(raced,root);raced.addPrepared(view,&base);
        require(scan(prepared,raced,retained,view,30,2,0,sampler,true)&&prepared.matches(30,2,0),
                "new revision and exact parent identity admit both consumers");
        raced.remove(root);require(!prepared.matches(30,2,0),"moved cache proof remains weak after admission");
        std::vector<MVKMetal4PreparedResourceProof> stale{base};
        prepared.remember(31,1,0,std::move(stale));
        require(!prepared.matches(31,1,0),"expired rvalue never creates a positive cache entry");
    }
    const unsigned originalAssertions=assertions;
    using Lookup=MVKMetal4PreparedTextureBindingCache::Result;
    cache.clear();
    require(cache.lookup(41,1,0)==Lookup::Attempt,"empty cache permits proof attempt");
    cache.remember(41,1,0,{owned});
    require(cache.lookup(41,1,0)==Lookup::Hit,"exact valid identity/revision returns Hit");
    require(cache.lookup(41,0,0)==Lookup::Attempt&&cache.lookup(41,1,0)==Lookup::Hit,"zero revision permits attempt without erasing valid entry");
    require(cache.lookup(0,1,0)==Lookup::Attempt&&cache.lookup(41,1,0)==Lookup::Hit,"zero incarnation never mutates other entries");
    require(cache.lookup(41,2,0)==Lookup::Attempt&&cache.lookup(41,1,0)==Lookup::Attempt,"stale positive revision erases before retry");
    cache.reject(41,3,0);
    require(cache.lookup(41,3,0)==Lookup::Negative,"same-revision negative has a distinct result");
    require(cache.lookup(41,0,0)==Lookup::Attempt&&cache.lookup(41,3,0)==Lookup::Negative,"invalid revision leaves negative entry unchanged");
    require(cache.lookup(41,4,0)==Lookup::Attempt&&cache.lookup(41,3,0)==Lookup::Attempt,"stale negative revision erases before retry");
    cache.remember(UINT64_MAX,UINT64_MAX,0,{owned});
    require(cache.lookup(UINT64_MAX,UINT64_MAX,0)==Lookup::Hit,"nonzero maximum identities retain existing acceptance");
    cache.clear();
    {
        auto expiring=std::make_unique<MVKMetal4PreparedResourceIdentity>();
        cache.remember(42,1,0,{expiring->proof()});
        for(unsigned i=1;i<256;++i)cache.remember(42,1,i,{owned});
        expiring.reset();
        require(cache.lookup(42,1,0)==Lookup::Attempt,"expired positive proof permits admission retry");
        cache.remember(42,1,256,{owned});
        require(cache.lookup(42,1,256)==Lookup::Hit,"expired entry erasure frees original bounded cache capacity");
    }
    for(bool sampler:{false,true}){
        FixtureLiveList negative;MVKMetal4PreparedTextureBindingCache prepared;Sink retained;
        negative.addPrepared(view);prepared.reject(43,1,0);
        bool snapshotVisited=false;
        require(scan(prepared,negative,retained,view,43,1,0,sampler,true,[&]{snapshotVisited=true;}),
                "negative result keeps independent snapshot and resource path");
        require(snapshotVisited&&retained.registrations==1&&prepared.lookup(43,1,0)==Lookup::Negative,
                "negative memo suppresses only cache proof admission, not snapshot proof capture");
        retained.success=false;
        require(!scan(prepared,negative,retained,view,43,1,0,sampler)&&retained.registrations==2,
                "negative memo retains original native resource retention failure");
        negative.remove(view);
        require(scan(prepared,negative,retained,view,43,1,0,sampler)&&retained.registrations==2&&prepared.lookup(43,1,0)==Lookup::Negative,
                "negative memo retains current dead-payload live validation");
    }
    require(sink.appendedGroups==1,"actual caller Hit still appends its group binding");
    printf("{\"passed\":true,\"assertions\":%u,\"originalAssertions\":%u,\"lookupAssertions\":%u}\n",assertions,originalAssertions,assertions-originalAssertions);
}
'''
cpp=OUT/'prepared-texture-exact.cpp';cpp.write_text(source)
exe=OUT/'prepared-texture-exact'
command=['xcrun','clang++','-std=c++17','-Wall','-Wextra','-Werror','-O1','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-pthread','-I'+str(BASE/'GPUObjects'),str(cpp),'-o',str(exe)]
p=subprocess.run(command,capture_output=True,text=True);(OUT/'prepared-texture-compile.log').write_text(p.stdout+p.stderr)
if p.returncode:raise SystemExit(p.stderr)
p=subprocess.run([str(exe)],capture_output=True,text=True);(OUT/'prepared-texture-run.log').write_text(p.stdout+p.stderr)
if p.returncode:raise SystemExit(p.stderr)
result=json.loads(p.stdout);result.update(gpuExecuted=False,linkedMoltenVK=False,sourceHashes=pins,sourceUnchanged=all(sha(BASE/n)==h for n,h in pins.items()),compileCommand=command,exactRegistryMethodsSHA256=hashlib.sha256((membership+proofs).encode()).hexdigest(),exactAdmissionBranchSHA256=hashlib.sha256(branch.encode()).hexdigest(),samplerAdmissionBranchSHA256=hashlib.sha256(sampler_branch.encode()).hexdigest(),exactLookupBranchSHA256=hashlib.sha256(lookup_branch.encode()).hexdigest(),samplerFixtureNativeTypeErased=True)
(OUT/'prepared-texture-receipt.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
