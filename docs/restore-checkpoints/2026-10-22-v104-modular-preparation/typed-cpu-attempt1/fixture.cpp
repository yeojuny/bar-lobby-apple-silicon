#include <cstring>
#include <memory>
/* This file is part of the Spring engine (GPL v2 or later), see LICENSE.html */
#include "Rendering/GL/StreamBuffer.h"
#include "Rendering/GL/VBO.h"
#include <cstdio>
#include <map>
#include <set>

extern "C" {
bool log_frontend_isEnabled(int, const char*) { return false; }
void log_frontend_register_section(const char*) {}
void log_frontend_register_runtime_section(int, const char*) {}
void log_frontend_record(int, const char*, const char*, ...) {}
}

// Ordered, deliberately delayed GPU reads. Production code owns all slots,
// pending reservations, mapping addresses, fence replacement and destruction.
struct __GLsync { unsigned sequence; };
struct Storage {
	std::vector<uint8_t> bytes;
	std::shared_ptr<std::vector<uint8_t>> backing=std::make_shared<std::vector<uint8_t>>();
	GLenum usage=0;
	uint8_t* external = nullptr;
	uint8_t* Data() { return external ? external : backing->data(); }
};
struct Read { GLuint buffer; size_t offset, bytes; unsigned sequence; };
static std::map<GLuint, Storage> buffers;
static std::set<GLsync> liveSyncs;
static std::vector<Read> reads;
static unsigned sequence = 0, completed = 0, fenceCount = 0, waitCount = 0;
static unsigned unmapCount = 0, checks = 0;
static GLuint bound = 0, indexed = 0, nextBuffer = 1;
static size_t indexedOffset = 0, indexedBytes = 0;
static bool failMapping = false;
static void Check(bool value) { ++checks; if (!value) std::abort(); }
// Keep real host allocation/free visible to ASan while mocking AMD's device
// allocation interface on Apple hardware.
namespace recoil {
void* aligned_alloc(size_t alignment, size_t bytes) {
	void* ptr = nullptr; Check(posix_memalign(&ptr, alignment, bytes) == 0); return ptr;
}
void aligned_free(void* ptr) { std::free(ptr); }
}
static GLsync FenceSync(GLenum, GLbitfield) {
	++fenceCount;
	auto* sync = new __GLsync{sequence}; liveSyncs.insert(sync); return sync;
}
static void DeleteSync(GLsync sync) { Check(liveSyncs.erase(sync) == 1); delete sync; }
static GLenum ClientWait(GLsync sync, GLbitfield flags, GLuint64 timeout) {
	Check(liveSyncs.contains(sync)); Check(flags == GL_SYNC_FLUSH_COMMANDS_BIT);
	Check(timeout == 250000); ++waitCount;
	completed = std::max(completed, sync->sequence); return GL_CONDITION_SATISFIED;
}
static void GenBuffers(GLsizei n, GLuint* ids) { while (n--) { *ids = nextBuffer++; buffers[*ids++] = {}; } }
static GLuint currentVAO=0;
static unsigned bindCalls=0;
static std::map<GLuint,GLuint> vaoEBO;
static std::map<GLenum,GLuint> targetBindings;
static GLuint& Bound(GLenum target) {return target==GL_ELEMENT_ARRAY_BUFFER?vaoEBO[currentVAO]:targetBindings[target];}
static void BindBuffer(GLenum target, GLuint id) {++bindCalls; Bound(target)=id; bound=id;}
static GLboolean IsBuffer(GLuint id) { return buffers.contains(id); }
static void DeleteBuffers(GLsizei n, const GLuint* ids) { while (n--) buffers.erase(*ids++); }
static void BufferStorage(GLenum, GLsizeiptr bytes, const void*, GLbitfield) { buffers.at(bound).bytes.resize(bytes); }
static void BufferData(GLenum target, GLsizeiptr bytes, const void* data, GLenum usage) {
    auto& storage=buffers.at(Bound(target)); storage.external=nullptr; storage.usage=usage;
    storage.backing=std::make_shared<std::vector<uint8_t>>(bytes,0xcd);
    if(data)std::memcpy(storage.Data(),data,bytes);
}
static void* MapBufferRange(GLenum, GLintptr offset, GLsizeiptr, GLbitfield) { return failMapping ? nullptr : buffers.at(bound).Data() + offset; }
static GLboolean UnmapBuffer(GLenum) { ++unmapCount; return GL_TRUE; }
static void Finish() { completed = sequence; }
static void FlushMappedBufferRange(GLenum, GLintptr, GLsizeiptr) {}
static void BindBufferRange(GLenum, GLuint, GLuint id, GLintptr offset, GLsizeiptr bytes) {
	indexed = id; indexedOffset = offset; indexedBytes = bytes;
}
PFNGLFENCESYNCPROC glad_glFenceSync = FenceSync;
PFNGLDELETESYNCPROC glad_glDeleteSync = DeleteSync;
PFNGLCLIENTWAITSYNCPROC glad_glClientWaitSync = ClientWait;
PFNGLGENBUFFERSPROC glad_glGenBuffers = GenBuffers;
PFNGLBINDBUFFERPROC glad_glBindBuffer = BindBuffer;
PFNGLISBUFFERPROC glad_glIsBuffer = IsBuffer;
PFNGLDELETEBUFFERSPROC glad_glDeleteBuffers = DeleteBuffers;
PFNGLBUFFERSTORAGEPROC glad_glBufferStorage = BufferStorage;
PFNGLBUFFERDATAPROC glad_glBufferData = BufferData;
PFNGLMAPBUFFERRANGEPROC glad_glMapBufferRange = MapBufferRange;
PFNGLUNMAPBUFFERPROC glad_glUnmapBuffer = UnmapBuffer;
PFNGLFINISHPROC glad_glFinish = Finish;
PFNGLFLUSHMAPPEDBUFFERRANGEPROC glad_glFlushMappedBufferRange = FlushMappedBufferRange;
PFNGLBINDBUFFERRANGEPROC glad_glBindBufferRange = BindBufferRange;
size_t VBO::GetAlignedSize(GLenum target, size_t size) { return target == GL_SHADER_STORAGE_BUFFER ? (size + 255) / 256 * 256 : size; }


/* This file is part of the Spring engine (GPL v2 or later), see LICENSE.html */
// Included after the existing StreamBuffer CPU fixture's GL surface.
#include <array>
#include <memory>

#define CHECK(expr) do { if (!(expr)) { std::fprintf(stderr, "FAIL line %u: %s\n", __LINE__, #expr); std::abort(); } ++checks; } while (false)
static unsigned namedCalls = 0;
#ifndef HEADLESS
int GLAD_GL_VERSION_4_5 = 1;
int GLAD_GL_ARB_direct_state_access = 0;
static void NamedBufferData(GLuint id, GLsizeiptr bytes, const void* data, GLenum usage) {
    CHECK(data == nullptr);
    auto& storage = buffers.at(id);
    storage.backing = std::make_shared<std::vector<uint8_t>>(bytes, 0xcd);
    storage.external = nullptr;
    storage.usage = usage;
    ++namedCalls;
}
PFNGLNAMEDBUFFERDATAPROC glad_glNamedBufferData = NamedBufferData;
#endif
static void BufferSubData(GLenum target, GLintptr offset, GLsizeiptr bytes, const void* data) {
    std::memcpy(buffers.at(Bound(target)).Data()+offset, data, bytes);
}
PFNGLBUFFERSUBDATAPROC glad_glBufferSubData = BufferSubData;
namespace Threading { bool IsMainThread() { return true; } }

static auto Params(GLenum target = GL_ARRAY_BUFFER, bool streaming = true) {
    IStreamBufferConcept::StreamBufferCreationParams params;
    params.numElems=8; params.target=target; params.optimizeForStreaming=streaming;
    return params;
}
static void Upload(IStreamBuffer<uint32_t>& buffer, uint32_t offset, uint32_t value) {
    *buffer.Map(nullptr, offset, 1)=value;
    buffer.Unmap();
}
static void ForeignState() {
    currentVAO=17; vaoEBO[17]=991;
    targetBindings[GL_ARRAY_BUFFER]=992; targetBindings[GL_COPY_WRITE_BUFFER]=993;
}
static void CheckForeignState(unsigned previousBinds) {
    CHECK(currentVAO==17 && vaoEBO.at(17)==991);
    CHECK(targetBindings.at(GL_ARRAY_BUFFER)==992 && targetBindings.at(GL_COPY_WRITE_BUFFER)==993);
    CHECK(bindCalls==previousBinds);
}

// These owner methods are extracted verbatim from each prepared RenderBuffers.h.
// The surrounding owner storage is a test surface; native draw methods are not mocked as proof.
struct TypedOwnerBase { virtual void SwapBuffer() {} };
struct TypedOwner : TypedOwnerBase {
    bool readOnly=false;
    size_t maxSize=0, vboStartIndex=0, eboStartIndex=0, vboUploadIndex=0, eboUploadIndex=0;
    std::vector<uint32_t> verts, indcs;
    std::array<size_t,2> numSubmits{};
    std::unique_ptr<IStreamBuffer<uint32_t>> vbo, ebo;
#include "typed-owner-methods.inc"
};

int main() {
    for (bool streaming : {false,true}) {
        for (GLenum target : {GL_ARRAY_BUFFER,GL_ELEMENT_ARRAY_BUFFER}) {
            currentVAO=0;
            BufferSubDataImpl<uint32_t> stream(Params(target,streaming));
            auto id=stream.GetID(); auto bytes=stream.GetByteSize();
            auto initial=namedCalls;
            stream.Invalidate(); CHECK(namedCalls==initial); // fresh has no uploaded bytes
            Upload(stream,0,0x11223344); Upload(stream,3,0x55667788);
            auto retained=buffers.at(id).backing;
            auto snapshot=*retained;
            stream.SwapBuffer(); CHECK(buffers.at(id).backing==retained); // general model path retains data
            ForeignState(); auto previousBinds=bindCalls;
            stream.Invalidate(); CheckForeignState(previousBinds);
            CHECK(stream.GetID()==id && stream.GetByteSize()==bytes && *retained==snapshot);
#ifndef HEADLESS
            CHECK(namedCalls==initial+1 && buffers.at(id).backing!=retained);
            CHECK(buffers.at(id).usage==(streaming?GL_STREAM_DRAW:GL_STATIC_DRAW));
            CHECK(std::all_of(buffers.at(id).backing->begin(),buffers.at(id).backing->end(),[](auto v){return v==0xcd;}));
#else
            CHECK(namedCalls==initial && buffers.at(id).backing==retained);
#endif
            auto after=namedCalls; stream.Invalidate(); CHECK(namedCalls==after);
            currentVAO=0; Upload(stream,0,42); CHECK(*retained==snapshot); // retained old storage survives new write
            stream.Resize(16); auto resized=buffers.at(id).backing;
            stream.Invalidate(); CHECK(namedCalls==after && buffers.at(id).backing==resized);
            std::vector<uint32_t> client(16,77);
            stream.Map(client.data(),2,2); stream.Unmap();
            CHECK(stream.HasClientPtr());
            stream.Invalidate(); CHECK(stream.HasClientPtr() && client[2]==77);
        }
    }
#ifndef HEADLESS
    for (int core : {0,1}) for(int arb : {0,1}) for(bool pointer : {false,true}) {
        GLAD_GL_VERSION_4_5=core; GLAD_GL_ARB_direct_state_access=arb;
        glad_glNamedBufferData=pointer?NamedBufferData:nullptr;
        BufferSubDataImpl<uint32_t> stream(Params());
        Upload(stream,0,51); auto before=namedCalls;
        ForeignState(); auto previousBinds=bindCalls;
        stream.Invalidate(); CheckForeignState(previousBinds);
        CHECK(namedCalls==before+((core||arb)&&pointer));
        // Unsupported calls consume the discard marker; enabling later must not orphan idle storage.
        GLAD_GL_VERSION_4_5=1; glad_glNamedBufferData=NamedBufferData;
        auto after=namedCalls; stream.Invalidate(); CHECK(namedCalls==after);
    }
    GLAD_GL_VERSION_4_5=1; GLAD_GL_ARB_direct_state_access=0; glad_glNamedBufferData=NamedBufferData;
#endif
    {
        TypedOwner writable, readonly;
        writable.vbo=std::make_unique<BufferSubDataImpl<uint32_t>>(Params());
        writable.ebo=std::make_unique<BufferSubDataImpl<uint32_t>>(Params(GL_ELEMENT_ARRAY_BUFFER));
        readonly.vbo=std::make_unique<BufferSubDataImpl<uint32_t>>(Params());
        readonly.readOnly=true;
        writable.verts={1,2}; writable.indcs={0,1}; writable.vboUploadIndex=2; writable.eboUploadIndex=2;
        readonly.verts=writable.verts; readonly.vboUploadIndex=2;
        currentVAO=0; Upload(*writable.vbo,0,25); Upload(*writable.ebo,0,1); Upload(*readonly.vbo,0,25);
        auto ro=buffers.at(readonly.vbo->GetID()).backing; auto v=buffers.at(writable.vbo->GetID()).backing;
        auto before=namedCalls; ForeignState(); auto previousBinds=bindCalls;
        readonly.SwapBuffer(); CHECK(namedCalls==before && readonly.verts.size()==2 && readonly.vboUploadIndex==2);
        writable.SwapBuffer(); CheckForeignState(previousBinds);
        CHECK(writable.verts.empty() && writable.indcs.empty() && writable.vboUploadIndex==0 && writable.eboUploadIndex==0);
        CHECK(buffers.at(readonly.vbo->GetID()).backing==ro && (*ro)[0]==25 && (*v)[0]==25);
#ifndef HEADLESS
        CHECK(namedCalls==before+2);
#else
        CHECK(namedCalls==before);
#endif
        auto after=namedCalls; writable.SwapBuffer(); CHECK(namedCalls==after);
        currentVAO=0; Upload(*writable.vbo,0,99);
        auto now=buffers.at(writable.vbo->GetID()).backing;
        writable.Clear(); CHECK(namedCalls==after && buffers.at(writable.vbo->GetID()).backing==now);
    }
    {
        BufferDataImpl<uint32_t> other(Params());
        auto initial=namedCalls; other.Invalidate(); CHECK(namedCalls==initial);
    }
    // Negative control: target-based orphan of an unrelated EBO corrupts foreign VAO state.
    {
        currentVAO=0; BufferSubDataImpl<uint32_t> ebo(Params(GL_ELEMENT_ARRAY_BUFFER));
        ForeignState(); ebo.Bind(); glBufferData(GL_ELEMENT_ARRAY_BUFFER,ebo.GetByteSize(),nullptr,GL_STREAM_DRAW); ebo.Unbind();
        CHECK(vaoEBO[17]!=991);
    }
    CHECK(buffers.empty());
    std::printf("typed-discard CPU checks %u; named replacements %u; foreign-VAO negative control detected\n",checks,namedCalls);
}
