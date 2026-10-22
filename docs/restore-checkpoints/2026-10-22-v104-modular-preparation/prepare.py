#!/usr/bin/env python3
"""Prepare exact patch payloads; never write the active source/build trees."""
from pathlib import Path
import difflib
import hashlib
import json

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[2]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"Expected one source match, got {text.count(old)}: {old[:90]}")
    return text.replace(old, new, 1)


def save_blob(data):
    digest = sha(data)
    path = OUT / "payload" / digest
    path.parent.mkdir(exist_ok=True)
    if path.exists():
        assert path.read_bytes() == data
    else:
        path.write_bytes(data)
    return {"path": str(path.relative_to(OUT)), "sha256": digest, "bytes": len(data)}


def write_module(name, variants, metadata):
    directory = OUT / "modules" / name
    directory.mkdir(parents=True, exist_ok=True)
    result = dict(metadata, id=name, activation="awaiting-human-cue", variants={})
    for variant, rows in variants.items():
        entries, patch, reverse = [], [], []
        for path, before, after in rows:
            assert before != after
            entries.append({"target": path, "mode": (ROOT/path).stat().st_mode & 0o777,
                            "before": save_blob(before), "after": save_blob(after)})
            patch.extend(difflib.unified_diff(before.decode().splitlines(True), after.decode().splitlines(True),
                                             fromfile="a/"+path, tofile="b/"+path))
            reverse.extend(difflib.unified_diff(after.decode().splitlines(True), before.decode().splitlines(True),
                                               fromfile="a/"+path, tofile="b/"+path))
        patch = "".join(patch).encode()
        reverse = "".join(reverse).encode()
        (directory / (variant+".patch")).write_bytes(patch)
        (directory / (variant+".reverse.patch")).write_bytes(reverse)
        result["variants"][variant] = {"files": entries, "patchSHA256": sha(patch), "reversePatchSHA256": sha(reverse)}
    (directory/"module.json").write_text(json.dumps(result, ensure_ascii=False, indent=2)+"\n")
    return result


def stream_header(text):
    text = replace_once(text, "\tvirtual void SwapBuffer() {};\n", "\tvirtual void SwapBuffer() {};\n\t// Only callers that discard every byte may invalidate the storage.\n\tvirtual void Invalidate() {};\n")
    start = text.index("class BufferSubDataImpl :")
    end = text.index("template<typename T>\nclass MapAndOrphanImpl", start)
    body = text[start:end]
    body = replace_once(body, "\tvoid Init() override {\n", "\tvoid Init() override {\n\t\tuploadedSinceInvalidate = false;\n")
    body = replace_once(body, "\t\tthis->Unbind();\n\t}\n", "\t\tthis->Unbind();\n\t\tuploadedSinceInvalidate |= (this->mapElemCount != 0);\n\t}\n")
    invalidate = '''\tvoid Invalidate() override {
\t\tconst bool hadUpload = uploadedSinceInvalidate;
\t\tuploadedSinceInvalidate = false;
#ifndef HEADLESS
\t\t// Named storage replacement preserves the current VAO's EBO and all
\t\t// buffer bindings. Unsupported contexts keep their existing storage.
\t\tif (!hadUpload || !(GLAD_GL_VERSION_4_5 || GLAD_GL_ARB_direct_state_access) || !glNamedBufferData)
\t\t\treturn;
\t\tglNamedBufferData(this->id, this->byteSize, nullptr, this->optimizeForStreaming ? GL_STREAM_DRAW : GL_STATIC_DRAW);
#else
\t\t(void)hadUpload;
#endif
\t}

'''
    body = replace_once(body, "\tbool HasClientPtr() const override", invalidate+"\tbool HasClientPtr() const override")
    body = replace_once(body, "\tbool clientMem;\n", "\tbool clientMem;\n\tbool uploadedSinceInvalidate = false;\n")
    return text[:start]+body+text[end:]


def typed_header(text):
    old = '''\t\tif (vbo)
\t\t\tvbo->SwapBuffer();
\t\tif (ebo)
\t\t\tebo->SwapBuffer();

\t\tClear();'''
    new = '''\t\tif (vbo) {
\t\t\tvbo->SwapBuffer();
\t\t\tvbo->Invalidate();
\t\t}
\t\tif (ebo) {
\t\t\tebo->SwapBuffer();
\t\t\tebo->Invalidate();
\t\t}

\t\tClear();'''
    return replace_once(text, old, new)


def prepare_11a():
    lanes = ["build/run91-recoil-src-694e9df7", "artifacts/runtime/run94-chobby-official-20260704-20260924/source"]
    pins = json.loads((ROOT/"artifacts/validation/v104-r-small-bundle-20261021/independent-11a-preaudit.json").read_text())["readPins"]
    rows = []
    for lane in lanes:
        for filename, transform in [("StreamBuffer.h", stream_header), ("RenderBuffers.h", typed_header)]:
            path = lane+"/rts/Rendering/GL/"+filename
            before = (ROOT/path).read_bytes()
            assert sha(before) == pins[path], path
            rows.append((path, before, transform(before.decode()).encode()))
    return write_module("11a-typed-frame-discard", {"R-and-Small": rows}, {
        "inventoryGroup": 11,
        "title": "Frame-local TypedRenderBuffer storage discard",
        "scope": "Both native engine lanes; BufferSubData only; writable Typed Swap only",
        "implementation": "DSA only, capability and loaded entrypoint required; unsupported and HEADLESS no-op",
        "preserves": ["readOnly buffers", "Clear semantics", "same-frame ranges", "model partial/idle uploads", "general SwapBuffer", "fences and submission order", "buffer identity/size/usage"],
        "requiredAfterCue": ["single active native builds for both lanes", "actual Mesa context DSA/VAO/old backing/new upload checks", "new separately signed candidate", "authorized R/Small comparison after all other work ends"],
        "limits": "Source proposal only until receipts say otherwise. Orphan can increase transient allocations; no FPS or GPU lifetime proof. No whole pass merging."
    })


def descriptor_source(text):
    start = text.index("static void bindDescriptorSets(MVKImplicitBufferData& target,")
    end = text.index("\nstatic void bindImmediateData(", start)
    body = text[start:end]
    body = replace_once(body, "static void bindDescriptorSets(", "static bool bindDescriptorSets(")
    body = replace_once(body, "\t[[maybe_unused]]", "\tbool changed = false;\n\t[[maybe_unused]]")
    body = replace_once(body,
        "\t\t\t\tmvkEnsureSize(target.dynamicOffsets, offsets.dynamicOffsetBufferIndex + stride.dynamicOffsetBufferIndex);",
        "\t\t\t\t// Newly meaningful zero words still require a longer Metal payload.\n"
        "\t\t\t\tchanged |= target.dynamicOffsets.size() < offsets.dynamicOffsetBufferIndex + stride.dynamicOffsetBufferIndex;\n"
        "\t\t\t\tmvkEnsureSize(target.dynamicOffsets, offsets.dynamicOffsetBufferIndex + stride.dynamicOffsetBufferIndex);")
    body = replace_once(body, "\t\t\t\t\tmvkCopy(write, dynamicOffsets, binding.descriptorCount);".replace("\t\t\t\t\t", "\t\t\t\t\t\t"),
        "\t\t\t\t\t\tchanged |= memcmp(write, dynamicOffsets, binding.descriptorCount * sizeof(uint32_t)) != 0;\n"
        "\t\t\t\t\t\tmvkCopy(write, dynamicOffsets, binding.descriptorCount);")
    for condition in ("!layout->getMetalFeatures().nativeTextureSwizzle && stride.textureIndex", "stride.bufferIndex"):
        body = replace_once(body, "\t\t\tif ("+condition+") {\n", "\t\t\tif ("+condition+") {\n\t\t\t\tchanged = true; // Non-argument metadata retains conservative invalidation.\n")
    body = replace_once(body, '\tassert(dynamicOffsets == dynamicOffsetsEnd && "All dynamic offsets should have been used, and no more than that");\n',
        '\tassert(dynamicOffsets == dynamicOffsetsEnd && "All dynamic offsets should have been used, and no more than that");\n\treturn changed;\n')
    text = text[:start]+body+text[end:]
    for cls, limit in (("Graphics", "\n#pragma mark - MVKVulkanComputeCommandEncoderState"), ("Compute", "\n#pragma mark - MVKMetalGraphicsCommandEncoderState")):
        start = text.index("void MVKVulkan"+cls+"CommandEncoderState::bindDescriptorSets(")
        end = text.index(limit, start)
        body = text[start:end]
        body = replace_once(body, "void MVKVulkan", "bool MVKVulkan")
        body = replace_once(body, "\n{\n", "\n{\n\tbool changed = false;\n")
        body = replace_once(body, "::bindDescriptorSets(_implicitBufferData", "changed |= ::bindDescriptorSets(_implicitBufferData")
        before = "\t\t_descriptorSets[firstSet + i] = sets[i];\n\t}\n}"
        body = replace_once(body, before, before[:-1]+"\treturn changed;\n}")
        text = text[:start]+body+text[end:]
    for cls, field, point in (("Graphics", "_vkGraphics", "GRAPHICS"), ("Compute", "_vkCompute", "COMPUTE")):
        declaration = "void MVKCommandEncoderState::bind"+cls+"Pipeline(MVK"+cls+"Pipeline* pipeline) {\n"
        text = replace_once(text, declaration, declaration+
            "\t// A pipeline/layout transition can change implicit packing or payload length.\n"
            "\tif ("+field+"._pipeline != pipeline || "+field+"._layout != pipeline->getLayout()) {\n"
            "\t\tapplyToActiveMTLState(VK_PIPELINE_BIND_POINT_"+point+", [](auto& mtl){ invalidateDescriptorSetImplicitBuffers(mtl); });\n\t}\n")
    start = text.index("void MVKCommandEncoderState::bindDescriptorSets(\n")
    end = text.index("\nMVKVulkanCommonEncoderState*", start)
    body = text[start:end]
    tail = '''\tapplyToActiveMTLState(bindPoint, [affected](auto& mtl){
\t\tinvalidateDescriptorSetImplicitBuffers(mtl);
\t\tfor (MVKStageResourceBits& exists : mtl.exists()) {
\t\t\texists.descriptorSetData.clearAllIn(affected);
\t\t}
\t});
\tif (bindPoint == VK_PIPELINE_BIND_POINT_GRAPHICS) {
\t\t_vkGraphics.bindDescriptorSets(layout, firstSet, setCount, sets, dynamicOffsetCount, dynamicOffsets);
\t} else if (bindPoint == VK_PIPELINE_BIND_POINT_COMPUTE) {
\t\t_vkCompute.bindDescriptorSets(layout, firstSet, setCount, sets, dynamicOffsetCount, dynamicOffsets);
\t}'''
    replacement = '''\tbool sameLayout = false;
\tbool changed = true;
\tif (bindPoint == VK_PIPELINE_BIND_POINT_GRAPHICS) {
\t\tsameLayout = _vkGraphics._pipeline && _vkGraphics._layout == layout;
\t\tchanged = _vkGraphics.bindDescriptorSets(layout, firstSet, setCount, sets, dynamicOffsetCount, dynamicOffsets);
\t} else if (bindPoint == VK_PIPELINE_BIND_POINT_COMPUTE) {
\t\tsameLayout = _vkCompute._pipeline && _vkCompute._layout == layout;
\t\tchanged = _vkCompute.bindDescriptorSets(layout, firstSet, setCount, sets, dynamicOffsetCount, dynamicOffsets);
\t}
\tapplyToActiveMTLState(bindPoint, [affected, sameLayout, changed](auto& mtl){
\t\tif (!sameLayout || changed)
\t\t\tinvalidateDescriptorSetImplicitBuffers(mtl);
\t\t// Same set pointers do not prove unchanged residency or resource contents.
\t\tfor (MVKStageResourceBits& exists : mtl.exists()) {
\t\t\texists.descriptorSetData.clearAllIn(affected);
\t\t}
\t});'''
    body = replace_once(body, tail, replacement)
    return text[:start]+body+text[end:]


def prepare_8a():
    base = "build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/"
    header_path, source_path = base+"MVKCommandEncoderState.h", base+"MVKCommandEncoderState.mm"
    header = (ROOT/header_path).read_bytes()
    assert sha(header) == "dac7a20c3963887d5f054322a2bf7884d347271768dd0a124649f7d25862dade"
    old_decl = "\tvoid bindDescriptorSets(MVKPipelineLayout* layout,"
    assert header.decode().count(old_decl) == 2
    after_header = header.decode().replace(old_decl, "\tbool bindDescriptorSets(MVKPipelineLayout* layout,").encode()
    r_source = (ROOT/"artifacts/validation/v104-r-small-bundle-20261021/R-CommandEncoderState.mm").read_bytes()
    small_source = (ROOT/source_path).read_bytes()
    assert sha(r_source) == "9b28b9a30f6e0d8a975b732dcaf8a49c8e14b32f9ba3157e4f9dce03b14276b9"
    assert sha(small_source) == "b1013a4a907210de7f527f550758824d1dfcf5d79b05266a984aa2a1e97e62e3"
    variants = {}
    for parent, before in (("R", r_source), ("Small", small_source)):
        variants[parent] = [(header_path, header, after_header), (source_path, before, descriptor_source(before.decode()).encode())]
    return write_module("08a-conservative-rebind", variants, {
        "inventoryGroup": 8, "adjacentSubmodule": True,
        "title": "Conservative legacy implicit-buffer rebind suppression",
        "scope": "Same current pipeline/layout only; output dynamic values and pre-resize growth compared; non-argument metadata conservative",
        "preserves": ["affected descriptor resource-use clear every bind", "Metal4 separate invalidation", "argument root/helper restoration", "dynamic offset consumption/stage ordering", "R no-dynamic argument-buffer fast path"],
        "requiredAfterCue": ["single active MVK build with all header dependents rebuilt", "foundation OFF syntax and ON native M3/M4 related checks", "grow/shrink/layout transition and helper/encoder GPU cases", "signed isolated app and actual MVK identity", "separate performance comparison"],
        "limits": "Adjacent to PR2837, not its wholesale import and not cross-record snapshot sharing. M3 benefit hypothesis only; M4-specific invalidation intentionally retained. memcmp and transition invalidation add work."
    })


if __name__ == "__main__":
    results = [prepare_11a(), prepare_8a()]
    print(json.dumps({"modules": [m["id"] for m in results], "activeSourceWrites": 0}))
