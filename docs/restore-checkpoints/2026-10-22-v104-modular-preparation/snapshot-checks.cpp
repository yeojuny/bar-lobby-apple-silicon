// Production header is included by validate-control.py. Native retain callbacks
// are explicit mocks; their actual live-list/recording guards remain unchanged.
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <thread>

static int checks=0;
static void check(bool ok){++checks;if(!ok){std::fprintf(stderr,"failed check %d\n",checks);std::abort();}}
static std::atomic<int> failAfter{-1};
void* operator new(std::size_t size){
    int remaining=failAfter.load();
    if(remaining>=0 && failAfter.fetch_sub(1)==0)throw std::bad_alloc();
    if(void* p=std::malloc(size?size:1))return p;
    throw std::bad_alloc();
}
void operator delete(void* p)noexcept{std::free(p);}
void operator delete(void* p,std::size_t)noexcept{std::free(p);}
using Cache=MVKMetal4PreparedBindingSnapshots;
using Result=Cache::Result;
static std::shared_ptr<void> owner=MVKMetal4PreparationEpoch::owner();
static std::vector<Cache::Resource> resources(uintptr_t id,size_t count=1){
    MVKMetal4PreparedResourceProof proof;proof.count=1;proof.owners[0]=owner;
    std::vector<Cache::Resource> value;
    for(size_t i=0;i<count;++i)value.push_back({reinterpret_cast<void*>(id+i),Cache::Kind::Buffer,proof,false});
    return value;
}
static Result hit(const Cache::Resource& r){return r.proof.valid()?Result::Hit:Result::Miss;}
int main(){
    Cache cache;
    check(cache.replay(0,1,hit)==Result::Miss);
    cache.remember(0,1,resources(10,3));int visited=0;
    check(cache.replay(0,1,[&](const auto& r){check(reinterpret_cast<uintptr_t>(r.identity)==10+visited++);return hit(r);})==Result::Hit);
    check(visited==3);check(cache.replay(0,2,hit)==Result::Miss);
    check(cache.replay(0,1,[](const auto&){return Result::Failed;})==Result::Failed);
    check(cache.replay(0,1,hit)==Result::Hit);
    // Same-thread reentry proves callback is outside the cache mutex. A missed
    // old entry must not erase a replacement even with exactly the same revision.
    for(uint64_t rev:{1u,2u}){
        cache.remember(0,1,resources(10));
        check(cache.replay(0,1,[&](const auto&){cache.remember(0,rev,resources(20));return Result::Miss;})==Result::Miss);
        check(cache.replay(0,rev,[](const auto& r){return r.identity==reinterpret_cast<void*>(20)?Result::Hit:Result::Failed;})==Result::Hit);
    }
    cache.remember(0,1,resources(10));
    check(cache.replay(0,1,[&](const auto&){cache.clear();return Result::Hit;})==Result::Hit);
    check(cache.replay(0,1,hit)==Result::Miss);
    cache.remember(0,1,resources(10));
    check(cache.replay(0,1,[](const auto&){return Result::Miss;})==Result::Miss);
    check(cache.replay(0,1,hit)==Result::Miss);
    // A blocked retain overlaps both replacement and clear. Entry metadata stays
    // alive until callback returns; no source/resource lifetime is invented.
    for(bool clear:{false,true})for(Result completion:{Result::Hit,Result::Miss,Result::Failed}){
        cache.clear();cache.remember(0,1,resources(11,2));
        std::mutex m;std::condition_variable cv;bool entered=false,proceed=false;Result result=Result::Failed;
        std::thread worker([&]{result=cache.replay(0,1,[&](const auto& r){
            std::unique_lock<std::mutex> lock(m);entered=true;cv.notify_all();
            if(!cv.wait_for(lock,std::chrono::seconds(3),[&]{return proceed;}))std::abort();
            if(r.identity!=reinterpret_cast<void*>(11)&&r.identity!=reinterpret_cast<void*>(12))std::abort();
            return completion;
        });});
        {std::unique_lock<std::mutex> lock(m);check(cv.wait_for(lock,std::chrono::seconds(3),[&]{return entered;}));}
        if(clear)cache.clear();else cache.remember(0,1,resources(30));
        {std::lock_guard<std::mutex> lock(m);proceed=true;}cv.notify_all();worker.join();
        check(result==completion);
        check(cache.replay(0,1,hit)==(clear?Result::Miss:Result::Hit));
    }
    cache.clear();cache.remember(0,1,resources(10));
    auto replacement=resources(20);failAfter=0;
    cache.remember(0,1,std::move(replacement));failAfter=-1;
    check(cache.replay(0,1,[](const auto& r){return r.identity==reinterpret_cast<void*>(10)?Result::Hit:Result::Failed;})==Result::Hit);
    for(int allocation=0;allocation<3;++allocation){
        Cache fresh;auto value=resources(10);failAfter=allocation;
        fresh.remember(0,1,std::move(value));failAfter=-1;
        check(fresh.replay(0,1,hit)==Result::Miss); // entry/node/bucket allocation failure.
    }
    cache.clear();
    for(uint32_t i=0;i<Cache::kMaxBindings;++i)cache.remember(i,1,resources(100+i));
    auto rejected=resources(999);failAfter=0;cache.remember(999,1,std::move(rejected));
    int stillArmed=failAfter;failAfter=-1;check(stillArmed==0); // No allocation when full.
    check(cache.replay(999,1,hit)==Result::Miss);
    cache.remember(0,2,resources(888));check(cache.replay(0,2,hit)==Result::Hit);
    cache.remember(0,3,resources(111,17));check(cache.replay(0,2,hit)==Result::Hit);
    std::vector<Cache::Resource> appended;check(cache.append(0,2,appended,1));check(appended.size()==1);
    check(!cache.append(0,2,appended,1));check(!cache.append(0,3,appended,10));
    owner.reset();check(cache.replay(0,2,hit)==Result::Miss);check(!cache.append(1,1,appended,10));
    std::printf("{\"status\":\"passed\",\"checks\":%d,\"actualGPU\":false,\"concurrentSchedules\":6}\n",checks);
}
