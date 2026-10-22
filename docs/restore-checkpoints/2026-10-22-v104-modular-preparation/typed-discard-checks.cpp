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
    std::array<size_t,2> maxSize{};
    size_t vboStartIndex=0, eboStartIndex=0, vboUploadIndex=0, eboUploadIndex=0;
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
            currentVAO=0; Upload(stream,0,42);
#ifndef HEADLESS
            CHECK(*retained==snapshot); // retained old storage survives new write
#endif
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
