// The validator includes the complete production header before this fixture.
// Native retention/execution is mocked; partition/cache/lifetime code is real.
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <new>
#include <thread>

static std::atomic<int> checks{0};
static void checkAt(bool ok,int line) { int n=++checks; if(!ok){std::fprintf(stderr,"check %d failed at fixture line %d\n",n,line);std::abort();} }
#define check(value) checkAt((value),__LINE__)
static std::atomic<int> failAfter{-1};
void* operator new(std::size_t size) {
    if(failAfter.load()>=0 && failAfter.fetch_sub(1)==0)throw std::bad_alloc();
    if(void* p=std::malloc(size?size:1))return p;
    throw std::bad_alloc();
}
void operator delete(void* p)noexcept{std::free(p);}
void operator delete(void* p,std::size_t)noexcept{std::free(p);}
using Snapshot=MVKMetal4PreparedGroupSnapshot;
using Binding=MVKMetal4PreparedBindingSnapshots;
using Result=Binding::Result;
using Stamp=MVKMetal4PreparedGroupStamp;
static Stamp stamp(){Stamp s;s.script=17;s.stage=2;s.setMask=1;s.sets[0]={44,1};s.epochs.fill(1);return s;}
static Result retain(const Binding::Resource& r){return r.proof.valid()?Result::Hit:Result::Miss;}
static Snapshot::RecordingProofRef remember(Snapshot& cache,const Stamp& s,const std::shared_ptr<void>& owner,
    const std::vector<uint32_t>& counts,uint64_t residualMask=0,uintptr_t base=1000){
    std::vector<Binding::Resource> resources;std::vector<Snapshot::BindingVersion> covered;std::vector<uint32_t> residual;
    for(size_t i=0;i<counts.size();++i){
        if(residualMask&(uint64_t(1)<<i)){residual.push_back(i);continue;}
        covered.push_back({uint32_t(i),0,uint32_t(i),counts[i],1});
        for(uint32_t j=0;j<counts[i];++j){
            MVKMetal4PreparedResourceProof proof;proof.count=1;proof.owners[0]=owner;
            resources.push_back({reinterpret_cast<void*>(base+100*i+j),
                i==0?Binding::Kind::Texture:Binding::Kind::Buffer,proof,i!=0});
        }
    }
    return cache.remember(s,s,std::move(resources),std::move(covered),std::move(residual),counts.size());
}
int main(){
    auto owner=MVKMetal4PreparationEpoch::owner();auto original=stamp();
    auto unchanged=[](uint32_t,uint32_t){return uint64_t(1);};
    Snapshot empty;bool capture=true;Snapshot::RecordingProofRef result;
    check(empty.replay(original,unchanged,retain,capture,&result)==Result::Miss);check(!capture&&!result);
    // Distinct slice lengths and holes expose cursor, partition, and ordering bugs.
    for(uint64_t oldResidual:{uint64_t(0),uint64_t(2),uint64_t(18)})for(uint64_t changed=0;changed<32;++changed){
        Snapshot cache;std::vector<uint32_t> counts{3,1,2,3,1};
        auto prior=remember(cache,original,owner,counts,oldResidual);check(bool(prior));
        auto current=original;if(changed)++current.sets[0].revision;
        std::vector<uintptr_t> expected;std::vector<uint32_t> residual;std::vector<uint32_t> kept;
        bool changedCovered=false;
        for(uint32_t i=0;i<5;++i){
            if((oldResidual|changed)&(uint64_t(1)<<i))residual.push_back(i);
            else {kept.push_back(i);for(uint32_t j=0;j<counts[i];++j)expected.push_back(1000+100*i+j);}
            changedCovered|=(changed&(uint64_t(1)<<i))&&!(oldResidual&(uint64_t(1)<<i));
        }
        auto revision=[&](uint32_t set,uint32_t binding){check(set==0&&binding<5);return (changed&(uint64_t(1)<<binding))?uint64_t(2):uint64_t(1);};
        std::vector<uintptr_t> seen;capture=true;result.reset();
        auto actual=cache.replay(current,revision,[&](const auto& resource){seen.push_back(reinterpret_cast<uintptr_t>(resource.identity));return retain(resource);},capture,&result);
        bool hit=!expected.empty() && (EXPECT_PARTIAL || !changedCovered);
        check(actual==(hit?Result::Hit:Result::Miss));
        if(hit){
            check(!capture&&bool(result));check(seen==expected);check(result->residual==residual);
            check(result->covered.size()==kept.size());
            for(size_t i=0;i<kept.size();++i)check(result->covered[i].ordinal==kept[i]);
            check(result->drawableIndependent==(kept.front()!=0));
            if(changedCovered)check(result->stamp==current);
            // The actual recording cache accepts only a stabilized complete preparation.
            MVKMetal4PreparedGroupCache local;auto altered=current;++altered.epochs[0];
            local.remember(current,altered,result);check(!local.lookup(current,revision,[&]{return current;}).complete);
            local.remember(current,current,result);check(local.lookup(current,revision,[&]{return current;}).complete);
            auto next=current;++next.epochs[0];auto lookup=local.lookup(next,revision,[&]{return next;});
            check(result->residual.empty()?lookup.complete:bool(lookup.partial));
        } else {check(seen.empty()&&!result);}
        // Replaying the original combination still returns the original immutable entry.
        Snapshot::RecordingProofRef back;check(cache.replay(original,unchanged,retain,capture,&back)==Result::Hit);check(back==prior);
        if(changedCovered)check(cache.replay(current,revision,retain,capture)==Result::Miss);
    }
    Snapshot cache;auto prior=remember(cache,original,owner,{1,2,1});check(bool(prior));
    // Full hits stay allocation-free, including when the output is not requested.
    failAfter=0;auto full=cache.replay(original,unchanged,retain,capture,&result);int armed=failAfter;failAfter=-1;
    check(full==Result::Hit&&armed==0&&result==prior);check(cache.replay(original,unchanged,retain,capture)==Result::Hit);
    for(int kind=0;kind<6;++kind){auto invalid=original;
        if(kind==0)++invalid.script;else if(kind==1)++invalid.stage;else if(kind==2)invalid.setMask=2;
        else if(kind==3)++invalid.sets[0].incarnation;else if(kind==4)invalid.epochs[2]=0;else invalid.epochs[2]=UINT64_MAX;
        int called=0;check(cache.replay(invalid,unchanged,[&](const auto&){++called;return Result::Hit;},capture,&result)==Result::Miss);check(!called&&!result);
    }
    auto current=original;++current.sets[0].revision;
    auto middleChanged=[](uint32_t,uint32_t binding){return binding==1?uint64_t(0):uint64_t(1);};
#if EXPECT_PARTIAL
    // revision zero is never a reusable binding, even if another binding survives.
    check(cache.replay(current,middleChanged,retain,capture,&result)==Result::Hit);
    check(result->residual==std::vector<uint32_t>{1});check(result->resources.size()==2);
    auto oldResult=result;
    // Same new descriptor combination permits the existing normal full capture
    // on the next snapshot observation (not necessarily the next draw).
    check(cache.replay(current,middleChanged,retain,capture,&result)==Result::Miss);
    check(capture&&!result);
    check(cache.replay(original,unchanged,retain,capture,&result)==Result::Hit&&result==prior);
    {
        Snapshot stable;auto old=remember(stable,original,owner,{1,2,1});
        auto changedRevision=[](uint32_t,uint32_t binding){return binding==1?uint64_t(2):uint64_t(1);};
        check(stable.replay(current,changedRevision,retain,capture,&result)==Result::Hit&&!capture);
        check(stable.replay(current,changedRevision,retain,capture,&result)==Result::Miss&&capture&&!result);
        // Existing sink prepares the whole group, then publishes only if stable.
        auto resources=old->resources;auto covered=old->covered;covered[1].revision=2;
        auto published=stable.remember(current,current,std::move(resources),std::move(covered),{},3);
        check(bool(published));
        failAfter=0;auto status=stable.replay(current,changedRevision,retain,capture,&result);armed=failAfter;failAfter=-1;
        check(status==Result::Hit&&armed==0&&!capture&&result==published);
    }
    for(int allocation=0;allocation<4;++allocation){
        failAfter=allocation;auto actual=cache.replay(current,middleChanged,retain,capture,&result);failAfter=-1;
        check(actual==Result::Miss&&!result);check(cache.replay(original,unchanged,retain,capture,&result)==Result::Hit&&result==prior);
    }
    auto allChanged=[](uint32_t,uint32_t){return uint64_t(2);};
    failAfter=0;auto miss=cache.replay(current,allChanged,retain,capture,&result);armed=failAfter;failAfter=-1;
    check(miss==Result::Miss&&armed==0&&!result);
    // Make this a fresh combination observation so it reaches retain, rather
    // than the separately tested repeated-combination recapture path.
    check(cache.replay(original,unchanged,retain,capture,&result)==Result::Hit&&result==prior);
    check(cache.replay(current,middleChanged,[](const auto&){return Result::Failed;},capture,&result)==Result::Failed);
    check(cache.replay(original,unchanged,retain,capture,&result)==Result::Hit&&result==prior);
    // Callback runs outside the lock; an old miss cannot erase a replacement.
    Snapshot::RecordingProofRef replacement;
    check(cache.replay(current,middleChanged,[&](const auto&){replacement=remember(cache,original,owner,{1,2,1},0,9000);return Result::Miss;},capture,&result)==Result::Miss);
    check(cache.replay(original,unchanged,retain,capture,&result)==Result::Hit&&result==replacement);
    for(Result completion:{Result::Hit,Result::Miss,Result::Failed}){
        prior=remember(cache,original,owner,{1,2,1});
        std::mutex mutex;std::condition_variable cv;bool entered=false,proceed=false;Result observed=Result::Miss;
        Snapshot::RecordingProofRef workerProof;
        std::thread worker([&]{bool localCapture=false;observed=cache.replay(current,middleChanged,[&](const auto& resource){
            std::unique_lock<std::mutex> lock(mutex);entered=true;cv.notify_all();
            if(!cv.wait_for(lock,std::chrono::seconds(3),[&]{return proceed;}))std::abort();
            check(resource.identity==reinterpret_cast<void*>(1000)||resource.identity==reinterpret_cast<void*>(1200));return completion;
        },localCapture,&workerProof);if(observed==Result::Hit)check(!localCapture);});
        {std::unique_lock<std::mutex> lock(mutex);check(cv.wait_for(lock,std::chrono::seconds(3),[&]{return entered;}));}
        replacement=remember(cache,original,owner,{1,2,1},0,9000);prior.reset();
        {std::lock_guard<std::mutex> lock(mutex);proceed=true;}cv.notify_all();worker.join();
        check(observed==completion);check(cache.replay(original,unchanged,retain,capture,&result)==Result::Hit&&result==replacement);
    }
    // Bound of64 includes last ordinal/variable resource slices; no fixed-word overflow.
    Snapshot maximum;std::vector<uint32_t> counts(64,1);auto maxProof=remember(maximum,original,owner,counts);check(bool(maxProof));
    check(maximum.replay(current,[](uint32_t,uint32_t binding){return binding==63?uint64_t(1):uint64_t(2);},retain,capture,&result)==Result::Hit);
    check(result->covered.size()==1&&result->covered[0].ordinal==63&&result->residual.size()==63);
    // Revocation remains effective even while derived metadata is strongly held.
    Snapshot revoked;auto shortOwner=MVKMetal4PreparationEpoch::owner();auto shortProof=remember(revoked,original,shortOwner,{1,2,1});shortOwner.reset();
    check(revoked.replay(current,middleChanged,retain,capture,&result)==Result::Miss&&!result);
#else
    check(cache.replay(current,middleChanged,retain,capture,&result)==Result::Miss);
#endif
    std::printf("{\"status\":\"passed\",\"checks\":%d,\"partialEnabled\":%d,\"concurrentSchedules\":%d,\"actualGPU\":false}\n",checks.load(),EXPECT_PARTIAL,EXPECT_PARTIAL?3:0);
}
