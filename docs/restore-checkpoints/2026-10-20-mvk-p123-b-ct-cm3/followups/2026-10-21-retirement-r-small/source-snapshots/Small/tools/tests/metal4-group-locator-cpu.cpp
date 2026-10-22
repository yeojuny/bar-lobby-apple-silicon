// Actual production group cache versus its frozen pre-change implementation.
// No native objects: tests recording-local metadata/proof/invalidation only.
#include <cstdio>
#include <cstdlib>
#include <type_traits>
#include <random>
#include MVK_GROUP_LOOKUP_HEADER
#include MVK_GROUP_REFERENCE_BODY
#include MVK_GROUP_COUNTED_BODIES
using Stamp = MVKMetal4PreparedGroupStamp;
using Snapshot = MVKMetal4PreparedGroupSnapshot;
static unsigned checks = 0;
static void check(bool ok) { ++checks; if (!ok) { std::fprintf(stderr,"group locator check %u failed\n",checks); std::abort(); } }
static Stamp stamp(uint64_t script, uint32_t stage = 0) {
    Stamp s; s.script=script; s.stage=stage; s.setMask=1; s.sets[0]={17,23}; s.epochs={1,2,3,4,5}; return s;
}
struct Pair {
    MVKMetal4PreparedGroupCache current;
    ReferenceGroupCache reference;
    void clear(){current.clear();reference.clear();}
    void remember(const Stamp& before, const Stamp& after, Snapshot::RecordingProofRef p={}) {
        current.remember(before,after,p);reference.remember(before,after,p);
    }
    auto lookup(const Stamp& s, uint64_t revision=23, bool stable=true) {
        unsigned newRevisions=0,oldRevisions=0,newStamps=0,oldStamps=0;
        auto currentResult=current.lookup(s,[&](uint32_t,uint32_t){++newRevisions;return revision;},[&]{++newStamps;auto result=s;if(!stable)++result.epochs[0];return result;});
        auto oldResult=reference.lookup(s,[&](uint32_t,uint32_t){++oldRevisions;return revision;},[&]{++oldStamps;auto result=s;if(!stable)++result.epochs[0];return result;});
        check(currentResult.complete==oldResult.complete && currentResult.partial==oldResult.partial);
        check(newRevisions==oldRevisions && newStamps==oldStamps);
        return currentResult;
    }
};
static Snapshot::RecordingProofRef proof(const Stamp& s,const std::shared_ptr<void>& owner,bool partial=false,bool drawable=false) {
    MVKMetal4PreparedResourceProof p;p.count=1;p.owners[0]=owner;
    Snapshot snapshot;
    auto result=snapshot.remember(s,s,{{reinterpret_cast<void*>(16),drawable?MVKMetal4PreparedBindingSnapshots::Kind::Texture:MVKMetal4PreparedBindingSnapshots::Kind::Buffer,p,!drawable}},{{0,0,0,1,23}},partial?std::vector<uint32_t>{1}:std::vector<uint32_t>{},partial?2:1);
    check(bool(result));return result;
}
int main(){
    static_assert(!std::is_copy_constructible_v<MVKMetal4PreparedGroupCache>);
    static_assert(!std::is_copy_assignable_v<MVKMetal4PreparedGroupCache>);
    static_assert(!std::is_move_constructible_v<MVKMetal4PreparedGroupCache>);
    static_assert(!std::is_move_assignable_v<MVKMetal4PreparedGroupCache>);
    Pair p;auto s=stamp(1);
    check(!p.lookup(s).complete);p.remember(s,s);check(p.lookup(s).complete);
    // Keep stage0's location while insertion through stage1 grows/rehashes map.
    for(uint64_t key=2;key<=128;++key){auto t=stamp(key,1);p.remember(t,t);check(p.lookup(t).complete);check(p.lookup(s).complete);}
    auto overflow=stamp(129);p.remember(overflow,overflow);check(!p.lookup(overflow).complete);
    auto updated=s;++updated.epochs[0];p.remember(updated,updated);check(p.lookup(updated).complete);check(!p.lookup(s).complete);
    // Script, not stage, is the authoritative map key. Old location sees update.
    auto anotherStage=updated;anotherStage.stage=4;p.remember(anotherStage,anotherStage);check(p.lookup(anotherStage).complete);check(!p.lookup(updated).complete);
    p.clear();check(!p.lookup(anotherStage).complete);p.remember(s,s);check(p.lookup(s).complete);
    for(uint32_t stage:{6u,31u,UINT32_MAX}){auto t=stamp(900+stage,stage);p.remember(t,t);check(p.lookup(t).complete);++t.epochs[0];check(!p.lookup(t).complete);}
    // Expired CPU proof, revision mismatch and unstable refresh cannot be hidden.
    p.clear();auto owner=MVKMetal4PreparationEpoch::owner();auto full=proof(s,owner);p.remember(s,s,full);check(p.lookup(s).complete);
    auto changed=s;++changed.epochs[0];check(!p.lookup(changed,23,false).complete);check(p.lookup(changed).complete);
    auto revised=changed;++revised.sets[0].revision;check(!p.lookup(revised,24).complete);check(p.lookup(revised,23).complete);
    owner.reset();auto expired=revised;++expired.epochs[3];check(!p.lookup(expired).complete);
    p.clear();owner=MVKMetal4PreparationEpoch::owner();auto partial=proof(s,owner,true);p.remember(s,s,partial);check(p.lookup(s).complete);
    check(!p.lookup(changed).complete && p.lookup(changed).partial==partial);
    auto wrongIdentity=changed;++wrongIdentity.sets[0].incarnation;check(!p.lookup(wrongIdentity).partial);
    p.clear();auto drawable=proof(s,owner,false,true);p.remember(s,s,drawable);auto acquired=s;++acquired.epochs[4];check(!p.lookup(acquired).complete);
    p.clear();p.remember(s,s,full);auto invalid=s;invalid.epochs[2]=UINT64_MAX;check(!p.lookup(invalid).complete);invalid=s;invalid.setMask=1u<<16;check(!p.lookup(invalid).complete);invalid=s;invalid.script=0;check(!p.lookup(invalid).complete);
    // Clearing drops metadata ownership; same key after clear is a genuine miss.
    p.clear();auto weakProof=proof(s,owner);std::weak_ptr<const Snapshot::RecordingProof> weak=weakProof;p.remember(s,s,std::move(weakProof));check(!weak.expired());p.clear();check(weak.expired()&&!p.lookup(s).complete);
    std::mt19937_64 random(0x4d564b);
    for(unsigned i=0;i<50000;++i){auto t=stamp(1+random()%192,random()%10);t.epochs[0]+=random()%3;t.sets[0].revision+=random()%3;switch(random()%7){case 0:p.clear();break;case 1:case 2:p.remember(t,t);break;case 3:{auto after=t;++after.epochs[0];p.remember(t,after);break;}default:p.lookup(t,23+random()%3,random()%5!=0);break;}}
    // Observation-only counting hash is substituted in the two extracted class
    // declarations. It does not alter product code or implement a shadow cache.
    CountedCurrentGroupCache counted;CountedReferenceGroupCache old;
    for(unsigned stage=0;stage<6;++stage){auto t=stamp(300+stage,stage);counted.remember(t,t);old.remember(t,t);counted.lookup(t,[](auto,auto){return 23;},[&]{return t;});}
    CountingHash::calls=0;
    for(unsigned i=0;i<1200;++i){auto t=stamp(300+i%6,i%6);check(counted.lookup(t,[](auto,auto){return 23;},[&]{return t;}).complete);}
    const auto newHashes=CountingHash::calls;check(newHashes==0);CountingHash::calls=0;
    for(unsigned i=0;i<1200;++i){auto t=stamp(300+i%6,i%6);check(old.lookup(t,[](auto,auto){return 23;},[&]{return t;}).complete);}
    const auto oldHashes=CountingHash::calls;check(oldHashes>=1200);
    std::printf("PASS %u checks; frozen/current results and callbacks match; 1200 hot lookups hash calls %llu -> %llu; metadata %zu -> %zu bytes\n",checks,(unsigned long long)oldHashes,(unsigned long long)newHashes,sizeof(ReferenceGroupCache),sizeof(MVKMetal4PreparedGroupCache));
}
