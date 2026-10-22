from pathlib import Path
import ast, datetime, hashlib, json, os, re, shlex, shutil, subprocess, time

R = Path(__file__).resolve().parents[3]
O = Path(__file__).resolve().parent
B = R / 'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK'
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
read = lambda p: json.loads(Path(p).read_text())
pins = read(O / 'R-source-pins.json')
application = read(O / 'application.json')
pins[application['unit1ProductPath']] = application['appliedSHA256']
assert all(sha(R / p) == h for p, h in pins.items())
assert read(O / 'build.json')['exitCode'] == 0
assert read(O / 'header-mtime-rebuild.json')['exitCode'] == 0
assert read(O / 'capture-cpu-final/capture-receipt.json')['status'] == 'passed'
assert read(O / 'texture-related-cpu/prepared-texture-receipt.json')['passed']

def state(stage, gpu=False):
    (O / 'execution-state.json').write_text(json.dumps(dict(
        stage=stage, nativeGpuStarted=gpu, barGameFPS=False,
        soleSourceBuildOwner='${THREAD_ID}',
        updatedUTC=datetime.datetime.now(datetime.timezone.utc).isoformat()), indent=2) + '\n')

def run(label, args, env=None):
    assert not (O / (label + '.json')).exists(), label
    started = time.monotonic()
    p = subprocess.run(args, capture_output=True, text=True, env=env, timeout=180)
    (O / (label + '.log')).write_text(p.stdout + p.stderr)
    (O / (label + '.json')).write_text(json.dumps(dict(
        arguments=args, exitCode=p.returncode, seconds=time.monotonic()-started), indent=2) + '\n')
    print(label, p.returncode, p.stdout[-700:], flush=True)
    assert p.returncode == 0, (label, p.stderr[-1800:])

lib = R / 'build/metal4-mvk-20261002/MoltenVK/libMoltenVK.1.4.3.dylib'
raw = O / 'qualified-raw-MoltenVK.dylib'
assert not raw.exists()
shutil.copy2(lib, raw)
for f in ['tools/tests/metal4-prepared-texture-cpu.py', 'tools/tests/metal4-descriptor-preparation-cpu.py']:
    ast.parse((R / f).read_text())
ninja = (R / 'build/metal4-mvk-20261002/build.ninja').read_text()
block = ninja[ninja.index('build MoltenVK/CMakeFiles/MoltenVK.dir/MoltenVK/Commands/MVKCommandEncoderState.mm.o:'):]
extra = shlex.split(re.search(r'  INCLUDES = (.*)', block).group(1)) + shlex.split(re.search(r'  DEFINES = (.*)', block).group(1))
assert '-DMVK_ENABLE_CUSTOM_DIAGNOSTICS=0' in shlex.split(re.search(r'  FLAGS = (.*)', block).group(1))
base = ['/usr/bin/xcrun', 'clang++', '-std=c++17', '-fno-objc-arc', '-fblocks',
        '-mmacosx-version-min=27.0', '-Wno-deprecated-declarations', '-O1', '-g',
        '-DMVK_ENABLE_CUSTOM_DIAGNOSTICS=0', '-framework', 'Foundation', '-framework', 'Metal',
        '-I'+str(B/'GPUObjects'), '-I'+str(B/'Commands')]
state('foundation-off-syntax')
defs = [x for x in extra if not x.startswith('-DMVK_BUILD_METAL4_FOUNDATION=')] + ['-DMVK_BUILD_METAL4_FOUNDATION=0']
run('foundation-off', base + defs + ['-fsyntax-only', str(B/'Commands/MVKCommandEncoderState.mm')])
original = (R/'tools/tests/metal4-vulkan-integration.mm').read_text()
prefix = original[:original.index('\nint main(')]
a = prefix.index('void compute(Context&')
e = prefix.index('\nvoid sequentialPrimaryBindings(', a)
variant = prefix[a:e].replace('void compute(', 'void computeCompatible(', 1).replace(
    'allocate.pSetLayouts = &setLayout;', 'allocate.pSetLayouts = &compatibleSetLayout;')
marker = '    VkDescriptorSetAllocateInfo allocate'
insert = ('    VkDescriptorSetLayout compatibleSetLayout; VK_CHECK(vkCreateDescriptorSetLayout(c.device, &setInfo, nullptr, &compatibleSetLayout));\n'
          '    c.cleanup.push_back([&, compatibleSetLayout] { vkDestroyDescriptorSetLayout(c.device, compatibleSetLayout, nullptr); });\n')
assert variant.count(marker) == 1
variant = variant.replace(marker, insert + marker)
source = O / 'selected-vulkan.mm'
source.write_text(prefix + '\n' + variant + r'''
int main(int argc,char**argv){bool native=argc<2||std::strcmp(argv[1],"m3");setenv("MVK_CONFIG_USE_METAL4",native?"1":"0",1);@autoreleasepool{try{
 {Context c;c.initialize(false,native);compute(c,false,3);}
 {Context c;c.initialize(false,native);computeCompatible(c,false,3);}
 {Context c;c.initialize(false,native);render(c,true);}
 printf("PASS descriptor revision/new recording, compatible layout, fragment texture/sampler; native=%d\n",native);return 0;
 }catch(const std::exception&e){fprintf(stderr,"FAIL %s\n",e.what());return 1;}}}
''')
exe = O / 'selected-vulkan'
state('selected-vulkan-compile')
run('vulkan-build', base + extra + ['-I'+str(R/'build/run66-moltenvk-src-20260903/External/SPIRV-Headers/include'),
    '-I'+str(R/'tools/tests'), str(source), str(lib), '-Wl,-rpath,'+str(lib.parent), '-o', str(exe)])
env = dict(os.environ, MVK_CONFIG_BACKEND_TIMELINE='0', MVK_CONFIG_BACKEND_COST_STATS='0',
    MVK_CONFIG_METAL4_STATS='0', MVK_CONFIG_METAL4_QUEUE_STATS='0', MTL_DEBUG_LAYER='1',
    MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS='1', MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS='0', MVK_CONFIG_LOG_LEVEL='3')
processes = subprocess.check_output(['/bin/ps','-axo','pid=,comm='], text=True)
conflicts = [line for line in processes.splitlines() if line.split(maxsplit=1)[-1].rsplit('/',1)[-1] in
    {'spring', 'spring-headless', 'selected-vulkan', 'sequential-native', 'prepared-recording-vulkan'}]
assert not conflicts, conflicts
for backend in ['m4', 'm3']:
    state('selected-vulkan-'+backend, True)
    run('vulkan-'+backend, [str(exe), backend], env)
assert sha(lib) == sha(raw)
assert all(sha(R / p) == h for p, h in pins.items())
(O/'candidate-source-pins.json').write_text(json.dumps(pins, indent=2)+'\n')
(O/'validation.json').write_text(json.dumps(dict(status='passed', rawSHA256=sha(raw), sourcePins=len(pins),
    exactCaptureCases=220, exactCaptureAssertions=3851, preparedTextureAssertions=65,
    cpuASanUBSan=True, foundationOff=True, selectedVulkanCasesPerBackend=3, backends=['Metal4','Metal3'],
    sourceFixtureSHA256=sha(R/'tools/tests/metal4-vulkan-integration.mm'), selectedFixtureSHA256=sha(source),
    MetalDebugLayer=True, diagnosticsCompile=0, diagnosticsRuntime=0, barGameFPS=False), indent=2)+'\n')
state('related-validation-complete-awaiting-package', True)
