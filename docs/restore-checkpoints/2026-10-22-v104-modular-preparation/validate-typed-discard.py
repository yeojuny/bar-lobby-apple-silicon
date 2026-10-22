#!/usr/bin/env python3
"""Exercise prepared source through a Clang overlay; no active source writes or GPU."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]


def block(text,start):
    depth=0
    for i in range(text.index('{',start),len(text)):
        depth += (text[i]=='{')-(text[i]=='}')
        if not depth:return text[start:i+1]
    raise ValueError('unclosed source')


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args(); out=args.output.resolve(); out.mkdir(parents=True,exist_ok=False)
    m=json.loads((HERE/'modules/11a-typed-frame-discard/module.json').read_text())
    files=m['variants']['R-and-Small']['files']
    mockpath=ROOT/'artifacts/validation/r58-stream-lifetime-20261005/stream-lifetime-checks.cpp'
    mock=mockpath.read_text().split('static auto Params(',1)[0]
    mock='#include <cstring>\n#include <memory>\n'+mock
    mock=mock.replace('std::vector<uint8_t> bytes;', 'std::vector<uint8_t> bytes;\n\tstd::shared_ptr<std::vector<uint8_t>> backing=std::make_shared<std::vector<uint8_t>>();\n\tGLenum usage=0;')
    mock=mock.replace('return external ? external : bytes.data();','return external ? external : backing->data();')
    mock=mock.replace('static void BindBuffer(GLenum, GLuint id) { bound = id; }', '''static GLuint currentVAO=0;
static unsigned bindCalls=0;
static std::map<GLuint,GLuint> vaoEBO;
static std::map<GLenum,GLuint> targetBindings;
static GLuint& Bound(GLenum target) {return target==GL_ELEMENT_ARRAY_BUFFER?vaoEBO[currentVAO]:targetBindings[target];}
static void BindBuffer(GLenum target, GLuint id) {++bindCalls; Bound(target)=id; bound=id;}''')
    begin=mock.index('static void BufferData('); end=mock.index('static void* MapBufferRange',begin)
    mock=mock[:begin]+'''static void BufferData(GLenum target, GLsizeiptr bytes, const void* data, GLenum usage) {
    auto& storage=buffers.at(Bound(target)); storage.external=nullptr; storage.usage=usage;
    storage.backing=std::make_shared<std::vector<uint8_t>>(bytes,0xcd);
    if(data)std::memcpy(storage.Data(),data,bytes);
}
'''+mock[end:]
    # Full production StreamBuffer.h/cpp remain compiled. Only this GL test surface is changed.
    fixture=out/'fixture.cpp'; fixture.write_text(mock+'\n'+(HERE/'typed-discard-checks.cpp').read_text())
    original=json.loads((ROOT/'artifacts/validation/r58-stream-lifetime-20261005/cpu-compile-command.json').read_text())
    command=original[:original.index(str(mockpath))]
    command.remove('-DNDEBUG')
    results=[]
    for lane in ('lobby','chobby'):
        prefix='build/run91-recoil-src-694e9df7' if lane=='lobby' else 'artifacts/runtime/run94-chobby-official-20260704-20260924/source'
        selected=[entry for entry in files if entry['target'].startswith(prefix+'/')]
        assert len(selected)==2
        mapping=[]
        for entry in selected:
            payload=HERE/entry['after']['path']
            assert hashlib.sha256(payload.read_bytes()).hexdigest()==entry['after']['sha256']
            mapping.append({'type':'file','name':str(ROOT/entry['target']),'external-contents':str(payload)})
        overlay=out/(lane+'-overlay.json')
        overlay.write_text(json.dumps({'version':0,'use-external-names':False,'roots':mapping}))
        render=next(entry for entry in selected if entry['target'].endswith('/RenderBuffers.h'))
        text=(HERE/render['after']['path']).read_text(); start=text.index('class TypedRenderBuffer')
        methods=block(text,text.index('\tvoid Clear()',start))+'\n'+block(text,text.index('\tvoid SwapBuffer() override',start))+'\n'
        (out/'typed-owner-methods.inc').write_text(methods)
        cmd=[arg.replace(str(ROOT/'build/run91-recoil-src-694e9df7'),str(ROOT/prefix)) for arg in command]
        for headless in (False,True):
            label=lane+('-headless' if headless else '-interactive')
            binary=out/label
            run_command=cmd+['-I',str(out),'-ivfsoverlay',str(overlay),str(fixture),str(ROOT/prefix/'rts/Rendering/GL/StreamBuffer.cpp'),'-Wl,-dead_strip','-o',str(binary)]
            if headless:run_command.insert(1,'-DHEADLESS')
            comp=subprocess.run(run_command,capture_output=True,text=True)
            (out/(label+'-compile.log')).write_text(comp.stdout+comp.stderr)
            assert comp.returncode==0,comp.stderr[-6000:]
            run=subprocess.run([str(binary)],capture_output=True,text=True,timeout=30)
            (out/(label+'-run.log')).write_text(run.stdout+run.stderr)
            results.append({'lane':lane,'headless':headless,'compileCommand':run_command,'returncode':run.returncode,'stdout':run.stdout,'stderr':run.stderr})
            assert run.returncode==0,run.stdout+run.stderr
    receipt={'status':'passed','results':results,'moduleSHA256':hashlib.sha256((HERE/'modules/11a-typed-frame-discard/module.json').read_bytes()).hexdigest(),
             'limits':'ASan/UBSan CPU model; actual stream implementation and extracted Typed Clear/Swap. GL and backing lifetime mocked. Full native build, actual CopyCurrent/DrawElementsRange and actual GPU storage/DSA checks remain after cue. No active source/build/app modifications.'}
    (out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({'status':'passed','configurations':len(results),'output':str(out)}))


if __name__=='__main__':main()
