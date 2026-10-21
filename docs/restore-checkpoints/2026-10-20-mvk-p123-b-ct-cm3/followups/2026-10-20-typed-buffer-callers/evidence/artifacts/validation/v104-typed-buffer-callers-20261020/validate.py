from pathlib import Path
import hashlib, json, os, re, shlex, subprocess, time

R = Path(__file__).resolve().parents[3]
O = Path(__file__).resolve().parent
B = R / 'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK'
V = O / 'validation'
V.mkdir(exist_ok=False)
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
write = lambda p, d: p.write_text(json.dumps(d, indent=2) + '\n')
ninja = (R / 'build/metal4-mvk-20261002/build.ninja').read_text()
block = ninja[ninja.index('build MoltenVK/CMakeFiles/MoltenVK.dir/MoltenVK/Commands/MVKCmdDraw.mm.o:'):]
incs = shlex.split(re.search(r'  INCLUDES = (.*)', block).group(1))
defs = shlex.split(re.search(r'  DEFINES = (.*)', block).group(1))
base = ['/usr/bin/xcrun', 'clang++', '-std=c++17', '-mmacosx-version-min=27.0', '-DMVK_ENABLE_CUSTOM_DIAGNOSTICS=0'] + incs
rows = []
for foundation in (0, 1):
    for rel in ('Commands/MVKCmdDraw.mm', 'Commands/MVKCmdTransfer.mm', 'GPUObjects/MVKQueryPool.mm'):
        args = base + [d for d in defs if not d.startswith('-DMVK_BUILD_METAL4_FOUNDATION=')] + [
            '-DMVK_BUILD_METAL4_FOUNDATION=' + str(foundation), '-Wno-deprecated-declarations',
            '-Wno-vla-cxx-extension', '-fsyntax-only', str(B / rel)]
        result = subprocess.run(args, capture_output=True, text=True, timeout=60)
        log = rel.replace('/', '-') + '-' + str(foundation) + '.log'
        (V / log).write_text(result.stdout + result.stderr)
        rows.append(dict(file=rel, foundation=foundation, arguments=args, exitCode=result.returncode, log=log))
        write(V / 'syntax.json', rows)
        if result.returncode: raise SystemExit(result.returncode)
print('Affected foundation OFF/ON syntax: 6/6.', flush=True)
args = ['/opt/homebrew/bin/ninja', '-C', str(R / 'build/metal4-mvk-20261002'), '-j', '4', 'MoltenVK']
start = time.monotonic()
with (V / 'incremental-build.log').open('w') as log:
    result = subprocess.run(args, stdout=log, stderr=subprocess.STDOUT)
lib = R / 'build/metal4-mvk-20261002/MoltenVK/libMoltenVK.1.4.3.dylib'
write(V / 'build.json', dict(arguments=args, exitCode=result.returncode, seconds=time.monotonic()-start,
                           rawLibrarySHA256=sha(lib), diagnostics=False))
if result.returncode: raise SystemExit(result.returncode)
print('Incremental MVK build passed.', flush=True)

# Select existing production-linked test bodies without running unrelated cases.
edge = (R / 'tools/tests/metal4-transfer-edge.mm').read_text()
host = (R / 'tools/tests/metal4-recording-host-state.mm').read_text()
shared = host[host.index('static void sharedStorage(Context& c) {'):host.index('\nint main()')]
source = V / 'selected-existing-vulkan.mm'
source.write_text(edge[:edge.index('\nint main()')] + '\n#include <thread>\n#include <atomic>\n' + shared + r'''
int main(int argc, char** argv) {
    if (argc != 2 || (std::strcmp(argv[1], "m3") && std::strcmp(argv[1], "m4"))) return 2;
    const bool native = !std::strcmp(argv[1], "m4");
    setenv("MVK_CONFIG_USE_METAL4", native ? "1" : "0", 1);
    @autoreleasepool {
        NSMutableArray* results = [NSMutableArray array]; unsigned failures = 0;
        auto test = [&](NSString* name, const std::function<void(Context&)>& body) {
            if (failures) return;
            Context context;
            try {
                context.initialize(false, native); body(context);
                [results addObject:@{@"name":name, @"passed":@YES,
                    @"native_queue":@(context.isNative(context.queue)),
                    @"completed_before":@(context.nativeBefore), @"completed_after":@(context.nativeAfter)}];
            } catch (const std::exception& error) {
                ++failures; [results addObject:@{@"name":name, @"passed":@NO,
                    @"error":[NSString stringWithUTF8String:error.what()]}];
            }
        };
        test(@"indexed_render_readback", [](Context& c) { render(c); });
        test(@"fill_update_aligned_copy_guards", transfer);
        test(@"independent_copy_distinct_allocations", [](Context& c) { independentCopyRegions(c, false); });
        test(@"independent_copy_same_buffer", [](Context& c) { independentCopyRegions(c, true); });
        test(@"copy_compute_fill_compute_continuation", copyComputeContinuation);
        test(@"timestamp_packed_narrow_strided_copy_reset_reuse", timestamps);
        test(@"parallel_byte_copy_pool_reset", sharedStorage);
        NSDictionary* report = @{@"suite":@"selected_existing_typed_buffer_paths", @"native_expected":@(native),
            @"planned":@7, @"passed":@(results.count-failures), @"failed":@(failures),
            @"gameExecuted":@NO, @"windowCreated":@NO, @"tests":results};
        NSData* data = [NSJSONSerialization dataWithJSONObject:report options:0 error:nil];
        std::fwrite(data.bytes, 1, data.length, stdout); std::fputc('\n', stdout);
        return failures ? 1 : 0;
    }
}
''')
exe = V / 'selected-existing-vulkan'
args = base + defs + ['-fno-objc-arc', '-fblocks', '-O2', '-g', '-Wno-deprecated-declarations',
    '-I' + str(R / 'tools/tests'), '-I' + str(R / 'build/run66-moltenvk-src-20260903/External/SPIRV-Headers/include'),
    '-framework', 'Foundation', str(source), str(lib), '-Wl,-rpath,' + str(lib.parent), '-o', str(exe)]
result = subprocess.run(args, capture_output=True, text=True, timeout=60)
(V / 'vulkan-build.log').write_text(result.stdout + result.stderr)
receipt = dict(arguments=args, compileExitCode=result.returncode, sourceSHA256=sha(source), rawLibrarySHA256=sha(lib),
    selectedBodies='Existing transfer-edge prefix and exact sharedStorage from recording-host-state; timestamps retains native-only completion assertion under nativeExpected.',
    fixturePins={p:sha(R/p) for p in ['tools/tests/metal4-transfer-edge.mm','tools/tests/metal4-vulkan-integration.mm','tools/tests/metal4-recording-host-state.mm']}, backends=[])
write(V / 'vulkan-receipt.json', receipt)
if result.returncode: raise SystemExit(result.returncode)
env = os.environ.copy()
for key in list(env):
    if key.startswith(('MVK_CONFIG_', 'MTL_CAPTURE', 'VK_')): env.pop(key)
settings = {'MTL_DEBUG_LAYER':'1', 'MVK_CONFIG_LOG_LEVEL':'2', 'MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS':'1', 'MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS':'0'}
env.update(settings)
for backend in ('m4', 'm3'):
    row = dict(backend=backend, arguments=[str(exe),backend], environment=settings)
    try:
        result = subprocess.run([str(exe),backend], env=env, capture_output=True, text=True, timeout=60)
        (V / (backend + '-stdout.json')).write_text(result.stdout)
        (V / (backend + '-stderr.log')).write_text(result.stderr)
        row.update(exitCode=result.returncode)
        if not result.returncode: row['result'] = json.loads(result.stdout)
    except subprocess.TimeoutExpired as error:
        (V / (backend + '-stdout.partial')).write_bytes(error.stdout or b'')
        (V / (backend + '-stderr.partial')).write_bytes(error.stderr or b'')
        row.update(exitCode=None, timeoutSeconds=60)
        receipt['backends'].append(row); write(V / 'vulkan-receipt.json', receipt)
        raise SystemExit('Existing bounded Vulkan test timeout; stop without relaxing it.')
    receipt['backends'].append(row); write(V / 'vulkan-receipt.json', receipt)
    if result.returncode: raise SystemExit(result.returncode)
    assert row['result']['passed'] == 7
    print(backend + ' actual Vulkan outputs: 7/7.', flush=True)
