from pathlib import Path
import json,hashlib,datetime,shutil,difflib
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent;B=R/'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK';prior=R/'artifacts/validation/v104-r-combined-20261021'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
read=lambda p:json.loads(Path(p).read_text())
before=read(prior/'performance-before.json')
assert all(sha(R/p)==h for p,h in before['sourcePins'].items())
assert sha(R/'build/metal4-mvk-20261002/MoltenVK/libMoltenVK.1.4.3.dylib')==before['rawSHA256']
assert sha(R/'build/metal4-mvk-20261002/CMakeCache.txt')==before['CMakeCacheSHA256']
assert read(R/'artifacts/runtime/v104-local-candidate.json')==before['currentCandidate']
f=B/'GPUObjects/MVKMetal4PreparedResource.h';old=f.read_text();start=old.index('class MVKMetal4PreparedGroupCache {');end=old.index('\n};',start)+len('\n};');body=old[start:end]
rheader=(prior/'preimage/GPUObjects/MVKMetal4PreparedResource.h').read_text();a=rheader.index('class MVKMetal4PreparedGroupCache {');e=rheader.index('\n};',a)+len('\n};');assert rheader[a:e]==body
(O/'Combined-preimage.h').write_text(old);(O/'R-preimage.h').write_text(rheader)
new=body.replace('    std::unordered_map<uint64_t, Entry> _groups;\npublic:', '''    std::unordered_map<uint64_t, Entry> _groups;
    struct RecentEntry { uint64_t script = 0; Entry* entry = nullptr; };
    // Locations only, never a cached validation result. Node references survive
    // unordered_map rehash; this map erases entries only at recording clear.
    std::array<RecentEntry, 6> _recent{};
    Entry* findEntry(uint64_t script, uint32_t stage) {
        RecentEntry* recent = stage < _recent.size() ? &_recent[stage] : nullptr;
        if (recent && recent->script == script && recent->entry) { return recent->entry; }
        auto found = _groups.find(script);
        if (found == _groups.end()) { return nullptr; }
        Entry* entry = &found->second;
        if (recent) { *recent = {script, entry}; }
        return entry;
    }
public:
    MVKMetal4PreparedGroupCache() = default;
    // Cached locations belong to this recording's map, never to a copied owner.
    MVKMetal4PreparedGroupCache(const MVKMetal4PreparedGroupCache&) = delete;
    MVKMetal4PreparedGroupCache& operator=(const MVKMetal4PreparedGroupCache&) = delete;
    MVKMetal4PreparedGroupCache(MVKMetal4PreparedGroupCache&&) = delete;
    MVKMetal4PreparedGroupCache& operator=(MVKMetal4PreparedGroupCache&&) = delete;''')
new=new.replace('void clear() { _groups.clear(); }','void clear() { _recent = {}; _groups.clear(); }')
new=new.replace('auto entry = _groups.find(stamp.script);','auto* entry = findEntry(stamp.script, stamp.stage);').replace('entry != _groups.end() && entry->second.stamp == stamp','entry && entry->stamp == stamp').replace('!stamp.valid() || entry == _groups.end()','!stamp.valid() || !entry').replace('entry->second.proof','entry->proof').replace('entry->second.stamp','entry->stamp')
new=new.replace('auto entry = _groups.find(before.script);','auto* entry = findEntry(before.script, before.stage);').replace('if (entry != _groups.end()) { entry->second =','if (entry) { *entry =')
assert new!=body and 'entry->second' not in new
newheader=old[:start]+new+old[end:];f.write_text(newheader)
(O/'group-cache-before.inc').write_text(body+'\n');(O/'group-cache-after.inc').write_text(new+'\n')
for role,pre in [('R',rheader),('Combined',old)]:
 s=pre.index('class MVKMetal4PreparedGroupCache {');e=pre.index('\n};',s)+len('\n};');result=pre[:s]+new+pre[e:];(O/(role+'-next.h')).write_text(result)
 (O/(role+'-next.patch')).write_text(''.join(difflib.unified_diff(pre.splitlines(True),result.splitlines(True),fromfile='a/GPUObjects/MVKMetal4PreparedResource.h',tofile='b/GPUObjects/MVKMetal4PreparedResource.h')))
 grant=dict(humanTask='그러면 그 다음 개선안을 R과 R+전체에 올려보자',owner='root single active source/build lane',createdUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),change='recording-local stage recent script-to-entry locator; all existing validation preserved',maximumGameSessions=0,FPSNotMeasured=True,diagnosticsCompile=0,countLimit=32,baselinesPreserved=True)
(O/'root-source-build-grant.json').write_text(json.dumps(grant,ensure_ascii=False,indent=2)+'\n')
(O/'before.json').write_text(json.dumps(before,indent=2)+'\n')
(O/'application.json').write_text(json.dumps(dict(productFiles=['GPUObjects/MVKMetal4PreparedResource.h'],sameClassBeforeBothBaselines=True,commonClassPatchSHA256=sha(O/'group-cache-after.inc'),beforeSourcePins=before['sourcePins'],afterHeaderSHA256=sha(f),nextHeaderSHA256={k:sha(O/(k+'-next.h')) for k in ['R','Combined']}),indent=2)+'\n')
print('Applied the same recording-local group locator change to Combined; R proposal shares identical class body.')
