// CPU fixture: the method definitions below are extracted verbatim from the selected source.
#include <algorithm>
#include <array>
#include <cassert>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <initializer_list>
#include <iostream>
#include <limits>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#ifdef RUN73_REAL_LUA
#include "lib/sol2/sol.hpp"
#include "System/SafeUtil.h"
namespace recoil { inline void aligned_free(void* ptr) { std::free(ptr); } }
#endif

using GLenum = unsigned; using GLint = int; using GLsizei = int; using GLubyte = unsigned char;
using GLuint = unsigned; using GLfloat = float;
#ifndef RUN73_REAL_LUA
using lua_Number = double;
#endif
constexpr GLenum GL_BYTE=0x1400, GL_UNSIGNED_BYTE=0x1401, GL_SHORT=0x1402,
    GL_UNSIGNED_SHORT=0x1403, GL_INT=0x1404, GL_UNSIGNED_INT=0x1405,
    GL_FLOAT=0x1406, GL_FLOAT_VEC4=0x8B52, GL_INT_VEC4=0x8B55,
    GL_UNSIGNED_INT_VEC4=0x8DC8, GL_FLOAT_MAT4=0x8B5C,
    GL_ARRAY_BUFFER=0x8892, GL_ELEMENT_ARRAY_BUFFER=0x8893,
    GL_UNIFORM_BUFFER=0x8A11, GL_SHADER_STORAGE_BUFFER=0x90D2,
    GL_ELEMENT_ARRAY_BUFFER_BINDING=0x8895, GL_MAP_READ_BIT=1;
constexpr int L_ERROR=0;
#define LOG_L(...) ((void)0)
inline uint32_t AlignUp(uint32_t n, uint32_t a) { return (n+a-1)/a*a; }
inline void glGetIntegerv(GLenum, GLint* x) { *x=7; }
inline void glBindBuffer(GLenum, GLuint) {}
#ifndef RUN73_REAL_LUA
namespace spring { template<class Out, class In> Out SafeCast(In x) { return static_cast<Out>(x); } }
#endif
namespace LuaUtils { template<class... Args> void SolLuaError(const char*, Args...) { throw std::runtime_error("Lua error"); } }
#ifndef RUN73_REAL_LUA
namespace sol {
    template<class T> struct optional {
        bool has=false; T val{};
        optional()=default; optional(T x):has(true),val(x){}
        T value_or(T fallback) const { return has?val:fallback; }
    };
    template<class T> struct as_table_t { T data; const T& value() const { return data; } };
    template<class T> as_table_t<T> as_table(T x) { return {std::move(x)}; }
}
#endif
struct VBO {
    std::vector<uint8_t> gpu;
    size_t logicalSize=0;
    size_t uploadOffset=~size_t(0), uploadBytes=0;
    int maps=0, unmaps=0;
    void Bind() {} void Unbind() {}
    void SetBufferSubData(size_t offset, size_t size, const void* ptr) {
        if (offset>logicalSize || size>logicalSize-offset) throw std::runtime_error("GPU overrun");
        uploadOffset=offset; uploadBytes=size;
        std::memcpy(gpu.data()+offset,ptr,size);
    }
    GLubyte* MapBuffer(size_t offset, size_t size, unsigned) {
        if (offset>logicalSize || size>logicalSize-offset) throw std::runtime_error("map overrun");
        ++maps; return gpu.data()+offset;
    }
    void UnmapBuffer() { ++unmaps; }
};
inline void VBOExistenceCheck(const VBO* p, const char*) { if (!p) throw std::runtime_error("no VBO"); }
struct S3DModelVAO {
    static bool IsValid() { return false; }
    static S3DModelVAO& GetInstance() { static S3DModelVAO value; return value; }
    void InvalidateIndexRestartProof(VBO*) {}
};
#ifdef RUN75_INTERNAL_UPLOAD
#include "test-run95-luavbo-internal-stubs.inc"
#endif
class LuaVBOImpl {
public:
    struct BufferAttribDef { GLenum type; GLint size; int normalized; std::string name; GLsizei pointer, typeSizeInBytes, strideSizeInBytes; };
    GLenum defTarget=GL_ARRAY_BUFFER;
    uint32_t elementsCount=0, elemSizeInBytes=0, bufferSizeInBytes=0;
    VBO* vbo=nullptr; void* bufferData=nullptr;
    bool vboOwner=false;
    std::vector<std::pair<const int, BufferAttribDef>> bufferAttribDefsVec;
    std::map<const int, BufferAttribDef> bufferAttribDefs;
    void GetTypePtr(GLenum, GLint, uint32_t&, uint32_t&, GLsizei&, GLsizei&);
    sol::as_table_t<std::vector<lua_Number>> Download(sol::optional<int>,sol::optional<int>,sol::optional<int>,sol::optional<bool>);
#ifdef RUN73_DIRECT_UPLOAD
    template<class TIn,class I,class F> size_t UploadImpl(I,I,uint32_t,F);
    template<class TIn,class F> size_t UploadImpl(const std::vector<TIn>& v,uint32_t o,F f) {
        return UploadImpl<TIn>(v.cbegin(),v.cend(),o,f);
    }
#else
    template<class TIn,class F> size_t UploadImpl(const std::vector<TIn>&,uint32_t,F);
#endif
    template<class TIn> size_t UploadImpl(const std::vector<TIn>& v,uint32_t o,int id) {
        return UploadImpl(v,o,[id](int x){return id==-1 || id==x;});
    }
    template<class TIn> size_t UploadImpl(const std::vector<TIn>& v,uint32_t o,const std::initializer_list<int>& ids) {
        return UploadImpl(v,o,[&](int x){return std::find(ids.begin(),ids.end(),x)!=ids.end();});
    }
    template<class TIn,class TOut,class TIter> bool TransformAndWrite(int&,GLubyte*&,int,int,TIter&,const TIter&,bool);
    template<class TIn> bool TransformAndRead(int&,GLubyte*&,int,int,std::vector<lua_Number>&,bool);
#ifdef RUN73_REAL_LUA
    void Delete();
    size_t Upload(const sol::stack_table&,sol::optional<int>,sol::optional<int>,sol::optional<int>,sol::optional<int>);
    size_t UploadBefore(const sol::stack_table&,sol::optional<int>,sol::optional<int>,sol::optional<int>,sol::optional<int>);
    template<class TIn,class F> size_t UploadImplBefore(const std::vector<TIn>&,uint32_t,F);
    template<class TIn> size_t UploadImplBefore(const std::vector<TIn>& v,uint32_t o,int id) {
        return UploadImplBefore(v,o,[id](int x){return id==-1 || id==x;});
    }
#endif
#ifdef RUN75_INTERNAL_UPLOAD
    const BufferAttribDef& InstanceBufferCheck(int,const char*);
    void InstanceBufferCheckAndFormatCheck(int,const char*);
    template<class T> static SInstanceData InstanceDataFromGetData(int id,int,uint16_t palette) {
        if (id < 0 || id >= 8) throw std::runtime_error("invalid object ID");
        return SInstanceData(0xf0000000u+id,palette,41+id,0xa0000000u+id,0xb0000000u+id);
    }
    template<class T> size_t InstanceDataFromImpl(int,int,uint16_t,const sol::optional<int>&);
    template<class T> size_t InstanceDataFromImpl(const sol::stack_table&,int,uint16_t,const sol::optional<int>&);
    template<class T> size_t InstanceDataFromImplBefore(int,int,uint16_t,const sol::optional<int>&);
    template<class T> size_t InstanceDataFromImplBefore(const sol::stack_table&,int,uint16_t,const sol::optional<int>&);
    size_t UploadInstanceData(const SInstanceData*,size_t,uint32_t,int);
    template<class F> size_t MatrixDataFromProjectileIDsImpl(size_t,F,int,sol::optional<int>,const char*);
    template<class I> size_t MatrixDataFromProjectileIDsImplBefore(const I&,int,sol::optional<int>,const char*);
    size_t MatrixDataFromProjectileIDs(int,int,sol::optional<int>);
    size_t MatrixDataFromProjectileIDs(const sol::stack_table&,int,sol::optional<int>);
    size_t MatrixDataFromProjectileIDsBefore(int,int,sol::optional<int>);
    size_t MatrixDataFromProjectileIDsBefore(const sol::stack_table&,int,sol::optional<int>);
#endif
};
#include "methods.inc"

static int failures=0, assertions=0, cases=0;
void check(bool ok,const char* name);
struct Fixture {
    LuaVBOImpl impl; VBO vbo; std::vector<uint8_t> cpu;
    Fixture(GLenum target, uint32_t elements, std::initializer_list<std::pair<GLenum,int>> defs) {
        ++cases;
        impl.defTarget=target; impl.elementsCount=elements; impl.vbo=&vbo; impl.vboOwner=true;
        uint32_t next=0; int id=0;
        for (auto [type,size]:defs) {
            uint32_t pointer=0; GLsizei align=0, bytes=0;
        impl.GetTypePtr(type,size,pointer,next,align,bytes);
            if (target==GL_ELEMENT_ARRAY_BUFFER) {
                bytes=(type==GL_UNSIGNED_BYTE?1:type==GL_UNSIGNED_SHORT?2:4)*size;
                pointer=next; next+=bytes;
            }
            if (!bytes) throw std::runtime_error("type not laid out");
            LuaVBOImpl::BufferAttribDef def{type,size,0,"",int(pointer),bytes/size,bytes};
            impl.bufferAttribDefs.emplace(id,def);
            impl.bufferAttribDefsVec.emplace_back(id,def);
            ++id;
        }
        impl.elemSizeInBytes=next;
        impl.bufferSizeInBytes=next*elements;
        cpu.assign(impl.bufferSizeInBytes+16,0xCC);
        vbo.gpu.assign(impl.bufferSizeInBytes+16,0xCC);
        vbo.logicalSize=impl.bufferSizeInBytes;
        impl.bufferData=cpu.data();
    }
    template<class T> T at(size_t offset) const {
        T x; std::memcpy(&x,cpu.data()+offset,sizeof x); return x;
    }
    void canary() const {
        check(cpu==vbo.gpu,"entire CPU/GPU byte equality");
        for (size_t i=impl.bufferSizeInBytes;i<cpu.size();++i)
            check(cpu[i]==0xCC && vbo.gpu[i]==0xCC,"guard byte untouched");
    }
};
void check(bool ok,const char* name) { ++assertions; if (!ok) { std::cerr<<"FAIL "<<name<<'\n'; ++failures; } }
template<class T> void eq(T got,T want,const char* name) { check(got==want,name); }
void expectVec(const std::vector<lua_Number>& got,std::initializer_list<lua_Number> want,const char* name) {
    check(got==std::vector<lua_Number>(want),name);
    if (got!=std::vector<lua_Number>(want)) {
        std::cerr<<"actual values:"; for (auto value:got) std::cerr<<' '<<value; std::cerr<<'\n';
    }
}
#ifdef RUN75_INTERNAL_UPLOAD
#include "test-run95-luavbo-internal-checks.inc"
#endif

#ifdef RUN73_REAL_LUA
static void luaUploadChecks() {
    sol::state lua;
    auto* L=lua.lua_state();
    luaopen_base(L);
    lua_settop(L,0);
    auto compare=[&](GLenum target, std::initializer_list<std::pair<GLenum,int>> defs,
                     int count, int attr, int offset, int first, int last) {
        Fixture actual(target,count,defs), before(target,count,defs);
        const int top=lua_gettop(L);
        sol::stack_table input(L,-1);
        bool actualError=false, beforeError=false;
        size_t actualBytes=0,beforeBytes=0;
        try { actualBytes=actual.impl.Upload(input,attr,offset,first,last); }
        catch (const std::runtime_error&) { actualError=true; }
        try { beforeBytes=before.impl.UploadBefore(input,attr,offset,first,last); }
        catch (const std::runtime_error&) { beforeError=true; }
        check(actualError==beforeError,"Lua API error parity");
        eq(actualBytes,beforeBytes,"Lua API uploaded span parity");
        check(actual.cpu==before.cpu,"Lua API independent CPU bytes parity");
        check(actual.vbo.gpu==before.vbo.gpu,"Lua API independent GPU bytes parity");
        eq(actual.vbo.uploadOffset,before.vbo.uploadOffset,"Lua API upload offset parity");
        eq(actual.vbo.uploadBytes,before.vbo.uploadBytes,"Lua API upload count parity");
        eq(lua_gettop(L),top,"Lua stack balanced after Upload");
        actual.canary(); before.canary();
    };

    // The raw getter must keep numeric-string handling, zero defaults and
    // metamethod bypass from the selected engine's implementation.
    lua.script("indexCalls=0; values=setmetatable({11, '2.5', false, {}, 'bad', 8, 9, 10}, {__index=function() indexCalls=indexCalls+1; return 999 end})");
    sol::table values=lua["values"]; values.push();
    compare(GL_ARRAY_BUFFER,{{GL_FLOAT,1}},8,-1,0,1,8);
    {
        Fixture f(GL_ARRAY_BUFFER,8,{{GL_FLOAT,1}});
        sol::stack_table input(L,-1);
        eq(f.impl.Upload(input,{}, {}, {}, {}),size_t(32),"default Lua options span");
        expectVec(f.impl.Download({}, {}, {}, {}).value(),{11,0,0,0,0,8,9,10},"real Lua fallback oracle");
    }
    for (int offset:{-2,0,1,7,8})
        for (int first:{-1,1,2,8,9})
            for (int last:{-1,1,3,8,9})
                compare(GL_ARRAY_BUFFER,{{GL_FLOAT,1}},8,-1,offset,first,last);
    compare(GL_ARRAY_BUFFER,{{GL_UNSIGNED_BYTE,1},{GL_FLOAT,1}},4,-1,0,1,8);
    compare(GL_ARRAY_BUFFER,{{GL_FLOAT,1}},8,5,0,1,8);
    eq(lua.get<int>("indexCalls"),0,"raw Upload never calls __index");
    lua_pop(L,1);

    for (GLenum target:{GL_ARRAY_BUFFER,GL_ELEMENT_ARRAY_BUFFER}) {
        for (GLenum type:{GL_BYTE,GL_UNSIGNED_BYTE,GL_SHORT,GL_UNSIGNED_SHORT,GL_INT,GL_UNSIGNED_INT,GL_FLOAT}) {
            for (int size:{1,4}) {
                if (target==GL_ELEMENT_ARRAY_BUFFER &&
                    (size!=1 || (type!=GL_UNSIGNED_BYTE && type!=GL_UNSIGNED_SHORT && type!=GL_UNSIGNED_INT))) continue;
                lua_newtable(L);
                for (int i=1;i<=40;++i) { lua_pushnumber(L,i%100); lua_rawseti(L,-2,i); }
                for (int offset:{0,1,3})
                    for (int last:{1,3,4,7,8,16,40})
                        compare(target,{{type,size}},4,-1,offset,1,last);
                lua_pop(L,1);
            }
        }
    }
    lua_newtable(L);
    for (int i=1;i<=90;++i) { lua_pushnumber(L,i); lua_rawseti(L,-2,i); }
    for (int attr:{-1,0,1,2})
        for (int offset:{0,1,2})
            for (int last:{1,2,3,5,6,7,20,90})
                compare(GL_ARRAY_BUFFER,{{GL_UNSIGNED_BYTE,1},{GL_SHORT,1},{GL_FLOAT,4}},3,attr,offset,2,last);
    compare(GL_UNIFORM_BUFFER,{{GL_FLOAT_VEC4,1},{GL_FLOAT_MAT4,1}},3,-1,0,1,60);
    compare(GL_SHADER_STORAGE_BUFFER,{{GL_FLOAT_VEC4,2},{GL_INT_VEC4,1},{GL_UNSIGNED_INT_VEC4,1}},3,-1,0,1,48);
    lua_pop(L,1);

    lua.script("holeValues=setmetatable({1,2,3,4,5,6,7,8},{__index=function() indexCalls=indexCalls+1; return 999 end}); holeValues[3]=nil");
    sol::table holes=lua["holeValues"]; holes.push();
    compare(GL_ARRAY_BUFFER,{{GL_FLOAT,1}},8,-1,0,1,8);
    {
        Fixture f(GL_ARRAY_BUFFER,8,{{GL_FLOAT,1}}); sol::stack_table input(L,-1);
        f.impl.Upload(input,{}, {},1,8);
        eq(f.at<float>(8),0.0f,"nil hole raw numeric fallback");
    }
    eq(lua.get<int>("indexCalls"),0,"holes never call __index");
    lua_pop(L,1);
    lua_newtable(L);
    const lua_Number floatingValues[]={-0.0f,std::numeric_limits<lua_Number>::max(),
        std::numeric_limits<lua_Number>::infinity(),-std::numeric_limits<lua_Number>::infinity(),
        std::numeric_limits<lua_Number>::quiet_NaN()};
    for (int i=0;i<5;++i) { lua_pushnumber(L,floatingValues[i]); lua_rawseti(L,-2,i+1); }
    compare(GL_ARRAY_BUFFER,{{GL_FLOAT,1}},5,-1,0,1,5);
    lua_pop(L,1);
    lua_newtable(L);
    compare(GL_ARRAY_BUFFER,{{GL_FLOAT,1}},1,-1,0,1,1);
    lua_pop(L,1);
    eq(lua_gettop(L),0,"all Lua tests leave stack empty");
}

static void luaUploadLengthChecks() {
    // Storage/layout setup models Define; Delete and Upload are actual source
    // bodies. Heap ownership lets the real Delete run under the sanitizers.
    struct OwnedBuffer {
        LuaVBOImpl impl;
        ~OwnedBuffer() { impl.Delete(); }
        void define(uint32_t count, std::initializer_list<std::pair<GLenum,int>> defs, GLenum target=GL_ARRAY_BUFFER) {
            impl.Delete();
            Fixture replacement(target,count,defs);
            impl=std::move(replacement.impl);
            impl.vboOwner=true;
            impl.vbo=new VBO(replacement.vbo);
            impl.bufferData=std::malloc(replacement.cpu.size());
            if (!impl.bufferData) throw std::bad_alloc();
            std::memcpy(impl.bufferData,replacement.cpu.data(),replacement.cpu.size());
        }
        void unchanged() const {
            if (!impl.vbo) return;
            eq(impl.vbo->uploadOffset,~size_t(0),"invalid callback produces no GPU upload");
            check(std::all_of(impl.vbo->gpu.begin(),impl.vbo->gpu.end(),[](uint8_t b){return b==0xCC;}),"invalid callback leaves GPU bytes untouched");
            if (impl.bufferData) {
                const auto* bytes=static_cast<const uint8_t*>(impl.bufferData);
                check(std::all_of(bytes,bytes+impl.bufferSizeInBytes+16,[](uint8_t b){return b==0xCC;}),"invalid callback leaves CPU bytes untouched");
            }
        }
        void coherent() const {
            const auto* bytes=static_cast<const uint8_t*>(impl.bufferData);
            check(std::equal(bytes,bytes+impl.bufferSizeInBytes+16,impl.vbo->gpu.begin()),"redefined CPU/GPU bytes match");
            for (size_t i=impl.bufferSizeInBytes;i<impl.bufferSizeInBytes+16;++i)
                eq(bytes[i],uint8_t(0xCC),"redefined upload guard untouched");
        }
    };
    sol::state lua;
    auto* L=lua.lua_state();
    luaopen_base(L); lua_settop(L,0);
    for (int mutation=0;mutation<10;++mutation) {
        OwnedBuffer buffer;
        buffer.define(2,{{GL_FLOAT,1},{GL_UNSIGNED_INT,1}});
        int calls=0;
        lua["mutateUploadBuffer"]=[&]() {
            ++calls;
            switch (mutation) {
                case 0: buffer.impl.Delete(); break;
                case 1: buffer.define(2,{{GL_UNSIGNED_BYTE,1}}); break;
                case 2: buffer.define(1,{{GL_FLOAT,1}}); break;
                case 3: buffer.define(2,{{GL_FLOAT,1}}); break;
                case 4: buffer.define(0,{{GL_FLOAT,1}}); break;
                case 5:
                    std::free(buffer.impl.bufferData); buffer.impl.bufferData=nullptr;
                    break;
                case 6: buffer.impl.bufferAttribDefs.clear(); buffer.impl.bufferAttribDefsVec.clear(); break;
                case 7: break;
                case 8:
                    // A non-owning Delete leaves the GPU object alive but
                    // removes its upload shadow/layout. Restore ownership
                    // only so this heap-backed fixture can clean it up.
                    buffer.impl.vboOwner=false; buffer.impl.Delete(); buffer.impl.vboOwner=true;
                    break;
                case 9: buffer.define(3,{{GL_FLOAT,1}}); break;
            }
        };
        lua.script("values=setmetatable({7,8},{__len=function() mutateUploadBuffer(); return 2 end})");
        lua_getglobal(L,"values");
        const int top=lua_gettop(L);
        bool error=false; size_t written=0;
        try { written=buffer.impl.Upload(sol::stack_table(L,-1),mutation==3?1:-1,mutation==2?1:0,{},{}); }
        catch (const std::runtime_error&) { error=true; }
        eq(calls,1,"Upload invokes real length callback once");
        check(error==(mutation!=1 && mutation!=7 && mutation!=9),"Upload validates receiver after callback");
        eq(lua_gettop(L),top,"callback Upload leaves Lua stack balanced");
        if (error) buffer.unchanged();
        else {
            eq(written,size_t(mutation==1?2:8),"valid callback upload span");
            buffer.coherent();
            if (mutation==1) {
                const auto* bytes=static_cast<const uint8_t*>(buffer.impl.bufferData);
                eq(bytes[0],uint8_t(7),"redefined type first value");
                eq(bytes[1],uint8_t(8),"redefined type second value");
            }
        }
        lua_pop(L,1); lua_pushnil(L); lua_setglobal(L,"mutateUploadBuffer");
    }
    // Model the selected production ModelsVBOImpl index branch: replace
    // the GPU object/count/layout, append its attribute and retain the old
    // CPU shadow. Cover rebinding during __len and an already shared target.
    for (int alreadyShared=0;alreadyShared<2;++alreadyShared) {
        OwnedBuffer buffer;
        buffer.define(16,{{GL_UNSIGNED_SHORT,1}},GL_ELEMENT_ARRAY_BUFFER);
        VBO* owned=buffer.impl.vbo;
        Fixture engine(GL_ELEMENT_ARRAY_BUFFER,64,{{GL_UNSIGNED_INT,1}});
        const auto* bytes=static_cast<const uint8_t*>(buffer.impl.bufferData);
        const std::vector<uint8_t> shadowBefore(bytes,bytes+32+16);
        const auto ownedGpuBefore=owned->gpu;
        const auto engineGpuBefore=engine.vbo.gpu;
        auto rebind=[&]() {
            buffer.impl.vbo=&engine.vbo;
            buffer.impl.elementsCount=engine.impl.elementsCount;
            buffer.impl.elemSizeInBytes=engine.impl.elemSizeInBytes;
            buffer.impl.bufferSizeInBytes=engine.impl.bufferSizeInBytes;
            buffer.impl.bufferAttribDefs[0]=engine.impl.bufferAttribDefs.at(0);
            buffer.impl.bufferAttribDefsVec.emplace_back(0,engine.impl.bufferAttribDefs.at(0));
            buffer.impl.vboOwner=false;
        };
        if (alreadyShared) rebind();
        int calls=0;
        lua["mutateUploadBuffer"]=[&]() { ++calls; if (!alreadyShared) rebind(); };
        lua.script("values=setmetatable({1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18},{__len=function() mutateUploadBuffer(); return 18 end})");
        lua_getglobal(L,"values");
        const int top=lua_gettop(L);
        bool error=false;
        try { buffer.impl.Upload(sol::stack_table(L,-1),{}, {}, {}, {}); }
        catch (const std::runtime_error&) { error=true; }
        eq(calls,1,"shared target length callback called once");
        check(error,"engine-owned upload target rejected");
        eq(lua_gettop(L),top,"shared target rejection balances Lua stack");
        check(std::equal(shadowBefore.begin(),shadowBefore.end(),bytes),"shared target preserves old CPU shadow and guard");
        check(owned->gpu==ownedGpuBefore,"shared target preserves original GPU buffer");
        check(engine.vbo.gpu==engineGpuBefore,"shared target preserves engine GPU buffer");
        eq(engine.vbo.uploadOffset,~size_t(0),"shared target issues no engine GPU upload");
        // Restore only the heap object for teardown; never delete engine.vbo.
        buffer.impl.vbo=owned; buffer.impl.vboOwner=true;
        lua_pop(L,1); lua_pushnil(L); lua_setglobal(L,"mutateUploadBuffer");
    }
    // Initial argument errors must still precede any Lua mutation callback.
    for (int invalid=0;invalid<3;++invalid) {
        OwnedBuffer buffer; buffer.define(2,{{GL_FLOAT,1}});
        int calls=0; lua["mutateUploadBuffer"]=[&]() { ++calls; };
        lua.script("values=setmetatable({7},{__len=function() mutateUploadBuffer(); return 1 end})");
        lua_getglobal(L,"values");
        if (invalid==0) buffer.impl.Delete();
        bool error=false;
        try { buffer.impl.Upload(sol::stack_table(L,-1),invalid==2?99:-1,invalid==1?2:0,{},{}); }
        catch (const std::runtime_error&) { error=true; }
        check(error,"initial invalid receiver/offset/attribute rejected");
        eq(calls,0,"initial invalid arguments bypass length callback");
        buffer.unchanged();
        lua_pop(L,1); lua_pushnil(L); lua_setglobal(L,"mutateUploadBuffer");
    }
    eq(lua_gettop(L),0,"all Upload callback tests leave empty Lua stack");
    std::cout<<"Upload length callback cases=15\n";
}
#endif

int main() {
    {
        // The GLTF model record adds normalized byte color at slot 15 after
        // the four float3s, float4 UVs and uint3 bone data (80 bytes total).
        Fixture f(GL_ARRAY_BUFFER,3,{{GL_FLOAT,3},{GL_FLOAT,3},{GL_FLOAT,3},{GL_FLOAT,3},{GL_FLOAT,4},{GL_UNSIGNED_INT,3},{GL_UNSIGNED_BYTE,4}});
        auto color = f.impl.bufferAttribDefs.at(6);
        color.normalized = 1;
        f.impl.bufferAttribDefs.erase(6);
        f.impl.bufferAttribDefs.emplace(15,color);
        f.impl.bufferAttribDefsVec.clear();
        for (const auto& entry : f.impl.bufferAttribDefs) f.impl.bufferAttribDefsVec.push_back(entry);
        eq(f.impl.elemSizeInBytes,80u,"GLTF model record stride");
        eq(color.pointer,76,"GLTF color byte offset");
        eq(f.impl.UploadImpl(std::vector<double>{17,34,51,255,68,85,102,128},1,15),size_t(160),"color partial upload span");
        expectVec(f.impl.Download(15,1,2,true).value(),{17,34,51,255,68,85,102,128},"slot15 color survives GPU roundtrip");
        for (int record=0;record<3;++record) {
            for (int offset=0;offset<76;++offset) eq(f.cpu[record*80+offset],uint8_t(0xCC),"model geometry and bones remain untouched");
        }
        for (int offset=76;offset<80;++offset) eq(f.cpu[offset],uint8_t(0xCC),"previous vertex color remains untouched");
        f.canary();
    }
    // Every byte assertion below uses declared offsets, independently of Download.
    {
        Fixture f(GL_ARRAY_BUFFER,3,{{GL_UNSIGNED_BYTE,1},{GL_FLOAT,1}});
        eq(f.impl.elemSizeInBytes,8u,"UBYTE1/FLOAT1 stride");
        eq(f.impl.bufferAttribDefsVec[1].second.pointer,4,"UBYTE1/FLOAT1 offset");
        std::vector<double> in{3,1.5,4,2.5,5,3.5};
        eq(f.impl.UploadImpl(in,0,-1),size_t(24),"mixed uploaded bytes");
        for (int i=0;i<3;++i) {
            eq(f.at<uint8_t>(8*i),uint8_t(3+i),"mixed byte position");
            eq(f.at<float>(8*i+4),float(1.5+i),"mixed float position");
        }
        expectVec(f.impl.Download({}, {}, {}, {}).value(),{3,1.5,4,2.5,5,3.5},"mixed CPU read");
        expectVec(f.impl.Download({}, {}, {}, true).value(),{3,1.5,4,2.5,5,3.5},"mixed GPU read");
        eq(f.vbo.uploadOffset,size_t(0),"mixed GPU offset");
        f.canary();
    }
    {
        Fixture f(GL_ARRAY_BUFFER,3,{{GL_UNSIGNED_BYTE,1},{GL_FLOAT,1}});
        // Select only the final field, starting at the second record.
        f.impl.UploadImpl(std::vector<double>{8.5,9.5},1,1);
        eq(f.at<float>(12),8.5f,"last-only float at offset");
        eq(f.at<float>(20),9.5f,"last-only float next record");
        check(f.cpu[0]==0xCC && f.cpu[8]==0xCC && f.cpu[16]==0xCC,"last-only first fields intact");
        check(f.cpu[1]==0xCC && f.cpu[2]==0xCC && f.cpu[3]==0xCC,"last-only padding intact");
        eq(f.vbo.uploadOffset,size_t(8),"last-only GPU offset");
        expectVec(f.impl.Download(1,1,2,true).value(),{8.5,9.5},"last-only GPU read");
        f.canary();
    }
    {
        Fixture f(GL_ARRAY_BUFFER,3,{{GL_UNSIGNED_BYTE,1},{GL_SHORT,1},{GL_FLOAT,1}});
        f.impl.UploadImpl(std::vector<double>{-12,-13},1,1);
        eq(f.at<int16_t>(10),int16_t(-12),"middle-only short at offset");
        eq(f.at<int16_t>(18),int16_t(-13),"middle-only short next record");
        check(f.cpu[8]==0xCC && f.cpu[9]==0xCC && f.cpu[12]==0xCC,"middle-only neighbors intact");
        check(f.cpu[16]==0xCC && f.cpu[17]==0xCC && f.cpu[20]==0xCC,"middle-only next neighbors intact");
        expectVec(f.impl.Download(1,1,2,false).value(),{-12,-13},"middle-only CPU read");
        f.canary();
    }
    {
        Fixture f(GL_ARRAY_BUFFER,3,{{GL_FLOAT,1},{GL_UNSIGNED_BYTE,1}});
        eq(f.impl.elemSizeInBytes,5u,"FLOAT1/UBYTE1 odd stride");
        f.impl.UploadImpl(std::vector<double>{1.25,7,2.25,8,3.25,9},0,-1);
        for (int i=0;i<3;++i) {
            eq(f.at<float>(5*i),float(1.25+i),"odd float position");
            eq(f.at<uint8_t>(5*i+4),uint8_t(7+i),"odd byte position");
        }
        f.canary();
    }
    {
        Fixture f(GL_ARRAY_BUFFER,3,{{GL_UNSIGNED_BYTE,1},{GL_FLOAT,1}});
        // Partial attribute starts on record 1 and must leave the other field intact.
        f.impl.UploadImpl(std::vector<double>{11,12},1,0);
        eq(f.at<uint8_t>(8),uint8_t(11),"partial record 1");
        eq(f.at<uint8_t>(16),uint8_t(12),"partial record 2");
        eq(f.at<uint8_t>(0),uint8_t(0xCC),"partial prior record");
        check(f.cpu[12]==0xCC && f.cpu[20]==0xCC,"partial companion untouched");
        eq(f.vbo.uploadOffset,size_t(8),"partial GPU offset");
        expectVec(f.impl.Download(0,1,2,false).value(),{11,12},"partial CPU read");
        expectVec(f.impl.Download(0,1,2,true).value(),{11,12},"partial GPU read");
        f.canary();
    }
    {
        Fixture f(GL_ARRAY_BUFFER,2,{{GL_UNSIGNED_BYTE,1},{GL_SHORT,1},{GL_INT,1}});
        eq(f.impl.elemSizeInBytes,8u,"SHORT padding stride");
        eq(f.impl.bufferAttribDefsVec[1].second.pointer,2,"SHORT padding offset");
        f.impl.UploadImpl(std::vector<double>{2,-30,-3000,3,-31,-3001},0,-1);
        eq(f.at<int16_t>(2),int16_t(-30),"signed short position");
        eq(f.at<int32_t>(4),int32_t(-3000),"signed int position");
        eq(f.at<int16_t>(10),int16_t(-31),"second signed short position");
        expectVec(f.impl.Download({}, {}, {}, {}).value(),{2,-30,-3000,3,-31,-3001},"signed read");
        f.canary();
    }
    {
        Fixture f(GL_ARRAY_BUFFER,2,{{GL_FLOAT,4},{GL_UNSIGNED_INT,1}});
        f.impl.UploadImpl(std::vector<uint32_t>{1,2,3,4,42,5,6,7,8,43},0,-1);
        eq(f.at<float>(0),1.0f,"common float4");
        eq(f.at<uint32_t>(16),42u,"common uint32");
        eq(f.at<uint32_t>(36),43u,"common uint32 second");
        f.canary();
    }
    {
        Fixture f(GL_ARRAY_BUFFER,2,{{GL_BYTE,1},{GL_SHORT,1}});
        f.impl.UploadImpl(std::vector<double>{-7,-700,-8,-800},0,-1);
        eq(f.at<int8_t>(0),int8_t(-7),"signed byte first");
        eq(f.at<int16_t>(2),int16_t(-700),"signed short first");
        eq(f.at<int8_t>(4),int8_t(-8),"signed byte second");
        eq(f.at<int16_t>(6),int16_t(-800),"signed short second");
        expectVec(f.impl.Download({}, {}, {}, true).value(),{-7,-700,-8,-800},"signed GPU read");
        f.canary();
    }
    {
        Fixture f(GL_ARRAY_BUFFER,2,{{GL_UNSIGNED_BYTE,4},{GL_FLOAT,1}});
        f.impl.UploadImpl(std::vector<double>{1,2,3,4,5.5,6,7,8,9,10.5},0,-1);
        eq(f.at<float>(4),5.5f,"UBYTE4/FLOAT first");
        eq(f.at<float>(12),10.5f,"UBYTE4/FLOAT second");
        f.canary();
    }
    {
        Fixture f(GL_UNIFORM_BUFFER,1,{{GL_FLOAT_VEC4,1},{GL_FLOAT_MAT4,1}});
        std::vector<double> in; for (int i=1;i<=20;++i) in.push_back(i);
        f.impl.UploadImpl(in,0,-1);
        eq(f.impl.elemSizeInBytes,80u,"vec4/mat4 stride");
        eq(f.at<float>(16),5.0f,"mat4 start");
        eq(f.at<float>(76),20.0f,"mat4 end");
        f.canary();
    }
    {
        Fixture f(GL_SHADER_STORAGE_BUFFER,1,{{GL_FLOAT_VEC4,2},{GL_INT_VEC4,1},{GL_UNSIGNED_INT_VEC4,1}});
        std::vector<double> in{1,2,3,4,5,6,7,8,-1,-2,-3,-4,21,22,23,24};
        eq(f.impl.elemSizeInBytes,64u,"SSBO vec4 array stride");
        f.impl.UploadImpl(in,0,-1);
        eq(f.at<float>(16),5.0f,"SSBO vec4 second slot");
        eq(f.at<int32_t>(32),int32_t(-1),"SSBO signed vec4");
        eq(f.at<uint32_t>(48),uint32_t(21),"SSBO unsigned vec4");
        expectVec(f.impl.Download({}, {}, {}, true).value(),{1,2,3,4,5,6,7,8,-1,-2,-3,-4,21,22,23,24},"SSBO GPU read");
        f.canary();
    }
    for (GLenum type:{GL_UNSIGNED_BYTE,GL_UNSIGNED_SHORT,GL_UNSIGNED_INT}) {
        Fixture f(GL_ELEMENT_ARRAY_BUFFER,3,{{type,1}});
        f.impl.UploadImpl(std::vector<double>{1,2,3},0,-1);
        expectVec(f.impl.Download({}, {}, {}, true).value(),{1,2,3},"IBO GPU read");
        eq(f.vbo.maps,1,"IBO map"); eq(f.vbo.unmaps,1,"IBO unmap");
        f.canary();
    }
    {
        Fixture f(GL_ARRAY_BUFFER,2,{{GL_UNSIGNED_BYTE,1},{GL_FLOAT,1}});
        // A complete first attribute may be retained on a truncated record.
        // Its upload span must match the CPU shadow, including alignment bytes.
        size_t n=f.impl.UploadImpl(std::vector<double>{7},0,-1);
        eq(n,size_t(4),"truncated bounded return");
        eq(f.at<uint8_t>(0),uint8_t(7),"truncated complete first attribute");
        check(std::equal(f.cpu.begin(),f.cpu.begin()+n,f.vbo.gpu.begin()),"truncated CPU/GPU coherent");
        check(f.cpu[4]==0xCC && f.vbo.gpu[4]==0xCC,"truncated next attribute untouched");
        f.canary();
    }
    {
        Fixture f(GL_ARRAY_BUFFER,1,{{GL_FLOAT,4}});
        size_t n=f.impl.UploadImpl(std::vector<double>{1,2,3},0,-1);
        eq(n,size_t(0),"short attribute return");
        check(f.cpu[0]==0xCC && f.vbo.gpu[0]==0xCC,"short attribute CPU/GPU unchanged");
        f.canary();
    }
    {
        Fixture f(GL_ARRAY_BUFFER,2,{{GL_UNSIGNED_BYTE,1},{GL_FLOAT,4}});
        size_t n=f.impl.UploadImpl(std::vector<double>{9,1,2},0,-1);
        eq(n,size_t(4),"second incomplete attribute bounded return");
        eq(f.at<uint8_t>(0),uint8_t(9),"complete field retained");
        check(f.cpu[4]==0xCC && f.vbo.gpu[4]==0xCC,"incomplete vector untouched");
        f.canary();
    }
    {
        Fixture f(GL_ARRAY_BUFFER,2,{{GL_FLOAT,1}});
        size_t n=f.impl.UploadImpl(std::vector<double>{99},0,[](int){return false;});
        eq(n,size_t(8),"no selected attribute bounded");
        check(f.cpu[0]==0xCC && f.cpu[4]==0xCC,"no selected attribute unchanged");
        f.canary();
    }
    {
        Fixture f(GL_ARRAY_BUFFER,3,{{GL_UNSIGNED_BYTE,1},{GL_FLOAT,1}});
        // Independent bytes in fake GPU memory must be decoded at declared offsets.
        f.vbo.gpu[8]=17; f.vbo.gpu[16]=18;
        float x=2.25f,y=3.25f;
        std::memcpy(f.vbo.gpu.data()+12,&x,sizeof x);
        std::memcpy(f.vbo.gpu.data()+20,&y,sizeof y);
        expectVec(f.impl.Download({},1,2,true).value(),{17,2.25,18,3.25},"independent GPU bytes");
        check(f.cpu[8]==0xCC && f.cpu[12]==0xCC,"independent GPU differs from CPU shadow");
        f.cpu=f.vbo.gpu;
        f.canary();
    }
    {
        Fixture f(GL_ARRAY_BUFFER,1,{{GL_UNSIGNED_BYTE,1},{GL_FLOAT,1}});
        size_t n=f.impl.UploadImpl(std::vector<double>{2,1.25,3,2.25},0,-1);
        eq(n,size_t(8),"oversized bounded return");
        eq(f.at<uint8_t>(0),uint8_t(2),"oversized first record");
        check(f.cpu[8]==0xCC && f.vbo.gpu[8]==0xCC,"oversized CPU/GPU canary");
        f.canary();
    }
    {
        Fixture f(GL_ARRAY_BUFFER,2,{{GL_FLOAT,1}});
        eq(f.impl.UploadImpl(std::vector<double>{12},2,-1),size_t(0),"offset at end rejected");
#ifndef RUN95_BASELINE
        eq(f.impl.UploadImpl(std::vector<double>{12},UINT32_MAX,-1),size_t(0),"wrapped offset rejected");
#endif
        check(f.cpu[0]==0xCC && f.vbo.gpu[0]==0xCC,"invalid offsets unchanged");
        f.canary();
    }
#ifdef RUN73_REAL_LUA
    luaUploadChecks();
    luaUploadLengthChecks();
#endif
#ifdef RUN75_INTERNAL_UPLOAD
    internalUploadChecks();
#endif
    if (failures) std::cerr<<failures<<" failures\n";
    else std::cout<<"LuaVBO layout CPU fixture passed\n";
    std::cout<<"cases="<<cases<<" assertions="<<assertions<<" failures="<<failures<<'\n';
    return failures?1:0;
}
