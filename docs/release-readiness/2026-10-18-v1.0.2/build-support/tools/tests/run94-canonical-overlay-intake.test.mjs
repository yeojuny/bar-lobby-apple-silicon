import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { prepareCanonicalSources } from '../build-run94-official-ui-parity.mjs';
import { ARCHIVE_DEPENDENCIES, REQUIRED_REVIEWED_FILES, SOURCE_IDENTITY, parseCanonicalIntakeArguments, stageCanonicalOverlays } from '../lib/run94-canonical-overlay-intake.mjs';
import { generateBundledPresentationHeader } from '../lib/run94-release-source-adapter.mjs';

const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const lanes = ['bar-chobby', 'bar-lobby'];

function fixture() {
  const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'bar-canonical-intake-')));
  const sourceRoot = path.join(root, 'sources/bar-lobby/bundled-assets/macos-luaui-overlays');
  const outputRoot = path.join(root, 'reviewed-source-output');
  const lockPath = path.join(root, 'reviewed-canonical-lock.json');
  const bytes = new Map();
  const set = (relative, contents) => {
    const data = Buffer.from(contents);
    bytes.set(relative, data);
    const file = path.join(sourceRoot, relative);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, data);
  };
  set('README.md', '# Synthetic canonical source fixture\n');
  set('legacy-managed-files.json', '{"schemaVersion":1,"files":[]}\n');
  set('accepted-contract.json', JSON.stringify({ barChobbyForbiddenPrefixes: ['LuaRules/'], forbiddenFrozenWidgets: ['LuaUI/Widgets/gui_buildmenu.lua'] }));
  for (const lane of lanes) {
    const files = [...REQUIRED_REVIEWED_FILES, 'LuaUI/Widgets/gui_buildsquare_gl4.lua', 'LuaUI/Widgets/gui_attackrange_gl4.lua'];
    set(`${lane}/manifest.json`, JSON.stringify({ lane, files, revision: 'reviewed-Sept28-source', acceptance: { status: 'cpu-only' } }));
    for (const relative of files) set(`${lane}/${relative}`, `-- ${lane}/${relative}: reviewed Sept28 diagnostic Options InstanceVBO PIP F1/F4\nreturn 'canonical-current'\n`);
  }
  const lock = {
    schemaVersion: 2, kind: 'reviewed-canonical-overlays', revision: 'synthetic-reviewed-Sept28', ...SOURCE_IDENTITY,
    files: Object.fromEntries([...bytes].map(([relative, value]) => [relative, sha(value)])),
    archiveDependencies: Object.fromEntries(ARCHIVE_DEPENDENCIES.map(relative => [relative, sha(`official-fixture:${relative}`)])),
  };
  function pin() {
    const data = JSON.stringify(lock);
    fs.writeFileSync(lockPath, data);
    return { sourceRoot, outputRoot, lockPath, lockSha256: sha(data) };
  }
  function repin() {
    lock.files = Object.fromEntries([...bytes].map(([relative, value]) => [relative, sha(value)]));
    return pin();
  }
  function manifest(lane, transform) {
    const relative = `${lane}/manifest.json`;
    const value = JSON.parse(bytes.get(relative).toString());
    transform(value);
    set(relative, JSON.stringify(value));
  }
  function untouched() {
    for (const [relative, value] of bytes) assert.deepEqual(fs.readFileSync(path.join(sourceRoot, relative)), value);
  }
  // Fixtures are intentionally retained in the temporary directory: this batch
  // has no deletion permission and never cleans project or app paths.
  return { root, sourceRoot, outputRoot, lockPath, bytes, lock, set, pin, repin, manifest, untouched };
}

test('entrypoint snapshots both canonical lanes and metadata without a parent app or official repository', () => {
  const f = fixture();
  const args = f.pin();
  const receipt = prepareCanonicalSources(['--source-only', '--canonical-lock', args.lockPath, '--canonical-lock-sha256', args.lockSha256, '--source-output', args.outputRoot], f.root);
  assert.equal(receipt.parentOverlayImport, false);
  assert.equal(receipt.templateRegeneration, false);
  assert.equal(receipt.appAssemblyAllowed, false);
  assert.equal(receipt.requiresReleaseInputGate, true);
  assert.equal(receipt.archiveDependencyBytesChecked, false);
  assert.deepEqual(receipt.files, f.lock.files);
  for (const [relative, value] of f.bytes) assert.deepEqual(fs.readFileSync(path.join(f.outputRoot, 'macos-luaui-overlays', relative)), value);
  f.untouched();
});

test('old package and refresh routes reject before any source or output access', () => {
  for (const argv of [[], ['--refresh-package'], ['--source-only', '--refresh-package'], ['--source-only', '--defer-verification']]) {
    assert.throws(() => prepareCanonicalSources(argv, '/synthetic-missing-workspace'), /App assembly is blocked/);
  }
});

test('keeps reviewed code origin separate from an explicitly pinned current runtime archive', () => {
  const f = fixture();
  f.lock.archiveContent = '11f7f951bb74d9a1fe621b7f32d6b010f13c8709';
  const receipt = stageCanonicalOverlays(f.pin());
  assert.equal(receipt.selectedContent, SOURCE_IDENTITY.selectedContent);
  assert.equal(receipt.archiveContent, f.lock.archiveContent);
});

test('rejects malformed or coerced runtime archive identities before staging', () => {
  for (const value of ['byar:test', ['11f7f951bb74d9a1fe621b7f32d6b010f13c8709']]) {
    const f = fixture(); f.lock.archiveContent = value;
    assert.throws(() => stageCanonicalOverlays(f.pin()), /runtime archive content/);
    assert.equal(fs.existsSync(f.outputRoot), false);
  }
});

test('source-only requires a separate lock, digest and output; no implicit source approval', () => {
  assert.throws(() => parseCanonicalIntakeArguments(['--source-only']), /Required explicit input/);
  assert.throws(() => parseCanonicalIntakeArguments(['--source-only', '--canonical-lock=x', '--canonical-lock-sha256=bad', '--source-output=y']), /Invalid canonical lock/);
  assert.throws(() => parseCanonicalIntakeArguments(['--source-only', '--canonical-lock=x', '--canonical-lock=y']), /duplicate intake/);
  assert.throws(() => parseCanonicalIntakeArguments(['--source-only', '--unknown=x']), /Unknown/);
});

test('rejects an altered lock before writing the snapshot', () => {
  const f = fixture();
  const args = f.pin();
  fs.appendFileSync(f.lockPath, '\n');
  assert.throws(() => stageCanonicalOverlays(args), /lock SHA-256 mismatch/);
  assert.equal(fs.existsSync(f.outputRoot), false);
  f.untouched();
});

test('rejects historical generated-file locks even when their digest is supplied', () => {
  const f = fixture();
  f.lock.schemaVersion = 1;
  f.lock.generated = {};
  assert.throws(() => stageCanonicalOverlays(f.pin()), /schema-2 lock/);
  assert.equal(fs.existsSync(f.outputRoot), false);
});

for (const key of Object.keys(SOURCE_IDENTITY)) {
  test(`rejects changed ${key} ownership identity`, () => {
    const f = fixture();
    f.lock[key] = 'other-input';
    assert.throws(() => stageCanonicalOverlays(f.pin()), new RegExp(`${key} mismatch`));
    assert.equal(fs.existsSync(f.outputRoot), false);
  });
}

test('requires all official archive dependency pins without claiming to inspect archive bytes', () => {
  const f = fixture();
  f.lock.archiveDependencies = {};
  assert.throws(() => stageCanonicalOverlays(f.pin()), /Official archive dependency file set mismatch/);
  assert.equal(fs.existsSync(f.outputRoot), false);
});

test('rejects a source edit made after lock review instead of reverting it', () => {
  const f = fixture();
  const args = f.pin();
  f.set('bar-chobby/LuaUI/Widgets/gui_pip.lua', '-- newer parent-owned search-cost correction\n');
  assert.throws(() => stageCanonicalOverlays(args), /Canonical source hash mismatch/);
  f.untouched();
  assert.equal(fs.existsSync(f.outputRoot), false);
});

test('rejects unpinned extra source files', () => {
  const f = fixture();
  const args = f.pin();
  f.set('bar-lobby/LuaUI/Widgets/unreviewed.lua', '-- unreviewed\n');
  assert.throws(() => stageCanonicalOverlays(args), /Canonical lock\/source file set mismatch/);
  assert.equal(fs.existsSync(f.outputRoot), false);
  f.untouched();
});

test('requires the PIP widget/history pair in each manifest', () => {
  const f = fixture();
  f.manifest('bar-lobby', manifest => { manifest.files = manifest.files.filter(relative => relative !== 'LuaUI/Include/pip_history.lua'); });
  assert.throws(() => stageCanonicalOverlays(f.repin()), /Required reviewed source missing/);
  assert.equal(fs.existsSync(f.outputRoot), false);
});

test('does not accept pinned files missing from the lane manifest', () => {
  const f = fixture();
  f.set('bar-chobby/LuaUI/Widgets/undeclared.lua', '-- pinned but undeclared\n');
  assert.throws(() => stageCanonicalOverlays(f.repin()), /Canonical manifests\/source file set mismatch/);
});

test('rejects duplicate or traversing manifest paths', () => {
  const duplicate = fixture();
  duplicate.manifest('bar-chobby', manifest => manifest.files.push(manifest.files[0]));
  assert.throws(() => stageCanonicalOverlays(duplicate.repin()), /Duplicate canonical manifest/);
  const traversal = fixture();
  traversal.manifest('bar-lobby', manifest => manifest.files.push('../profile.lua'));
  assert.throws(() => stageCanonicalOverlays(traversal.repin()), /Unsafe source path/);
});

test('preserves Chobby LuaRules exclusion and rejects retired placement/frozen widgets', () => {
  for (const relative of ['LuaRules/Gadgets/synced.lua', 'LuaUI/Widgets/gui_buildsquare_macos.lua', 'LuaUI/Widgets/gui_buildmenu.lua']) {
    const f = fixture();
    f.set(`bar-chobby/${relative}`, '-- disallowed fixture\n');
    f.manifest('bar-chobby', manifest => manifest.files.push(relative));
    assert.throws(() => stageCanonicalOverlays(f.repin()), /ownership violation|Forbidden frozen/);
    assert.equal(fs.existsSync(f.outputRoot), false);
  }
});

function addShaderAdapter(f, { lanesToAdd = lanes, contract = true, different = false } = {}) {
  const relative = 'modules/graphics/LuaShader.lua';
  if (contract) {
    const value = JSON.parse(f.bytes.get('accepted-contract.json'));
    value.unsyncedShaderAdapter = { path: relative, scope: 'LuaRulesUnsynced-explicit-GS-policy-only', officialArchiveUnchanged: true };
    f.set('accepted-contract.json', JSON.stringify(value));
  }
  for (const lane of lanesToAdd) {
    f.set(`${lane}/${relative}`, `-- reviewed paired shader adapter${different ? lane : ''}\n`);
    f.manifest(lane, m => m.files.push(relative));
  }
}

test('stages only the explicitly reviewed identical two-lane graphics adapter', () => {
  const f = fixture(); addShaderAdapter(f);
  const receipt = stageCanonicalOverlays(f.repin());
  assert.equal(receipt.files['bar-lobby/modules/graphics/LuaShader.lua'], receipt.files['bar-chobby/modules/graphics/LuaShader.lua']);
  f.untouched();
});

test('CUS palette scope requires the pinned presentation-only contract before staging', () => {
  const valid = {
    revision: 'bounds-v1', upstreamHead: '9e774290b348d35f1f5ef30939abdaf4e2aa0667',
    nativePaletteEntries: 2048, simulationStateWrites: false, dynamicPaletteSweepImported: false,
  };
  for (const delta of [null, { nativePaletteEntries: 255 }, { simulationStateWrites: true },
    { dynamicPaletteSweepImported: true }, { upstreamHead: 'unreviewed' }, { revision: null }]) {
    const f = fixture(); addShaderAdapter(f);
    const contract = JSON.parse(f.bytes.get('accepted-contract.json'));
    Object.assign(contract.unsyncedShaderAdapter, {
      scope: 'LuaRulesUnsynced-GS-policy-and-CUS-palette', cusPalette: { ...valid, ...delta },
    });
    f.set('accepted-contract.json', JSON.stringify(contract));
    if (delta) {
      assert.throws(() => stageCanonicalOverlays(f.repin()), /shader adapter contract/);
      assert.equal(fs.existsSync(f.outputRoot), false);
    } else {
      const result = stageCanonicalOverlays(f.repin());
      assert.equal(result.files['bar-lobby/modules/graphics/LuaShader.lua'], result.files['bar-chobby/modules/graphics/LuaShader.lua']);
    }
    f.untouched();
  }
});

test('rejects shader adapter lane divergence, missing lane and absent scope contract', () => {
  for (const options of [{ different: true }, { lanesToAdd: ['bar-lobby'] }, { contract: false }]) {
    const f = fixture(); addShaderAdapter(f, options);
    assert.throws(() => stageCanonicalOverlays(f.repin()), /shader adapter/);
    assert.equal(fs.existsSync(f.outputRoot), false);
  }
});

test('the reviewed shader adapter does not allow other shared or synced modules', () => {
  for (const relative of ['modules/graphics/init.lua', 'modules/graphics/InstanceVBOTable.lua', 'modules/synced.lua']) {
    const f = fixture(); addShaderAdapter(f);
    f.set(`bar-chobby/${relative}`, '-- unreviewed module\n');
    f.manifest('bar-chobby', m => m.files.push(relative));
    assert.throws(() => stageCanonicalOverlays(f.repin()), /ownership violation/);
    assert.equal(fs.existsSync(f.outputRoot), false);
  }
});

test('rejects source symlinks before following their bytes', () => {
  const f = fixture();
  const args = f.pin();
  const external = path.join(f.root, 'outside.lua');
  fs.writeFileSync(external, '-- outside\n');
  fs.symlinkSync(external, path.join(f.sourceRoot, 'bar-chobby/LuaUI/Widgets/linked.lua'));
  assert.throws(() => stageCanonicalOverlays(args), /not symlinks/);
  assert.equal(fs.existsSync(f.outputRoot), false);
});

test('rejects lock path traversal and source/output overlap including symlink aliases', () => {
  const f = fixture();
  const args = f.pin();
  assert.throws(() => stageCanonicalOverlays({ ...args, outputRoot: path.join(f.sourceRoot, 'snapshot') }), /overlaps canonical source/);
  const alias = path.join(f.root, 'source-alias');
  fs.symlinkSync(f.sourceRoot, alias);
  assert.throws(() => stageCanonicalOverlays({ ...args, outputRoot: path.join(alias, 'snapshot') }), /overlaps canonical source/);
  f.lock.files['../outside.lua'] = sha('outside');
  assert.throws(() => stageCanonicalOverlays(f.pin()), /Unsafe source path/);
});

test('refuses app destinations and occupied source snapshots without replacing files', () => {
  const f = fixture();
  const args = f.pin();
  assert.throws(() => stageCanonicalOverlays({ ...args, outputRoot: path.join(f.root, 'Synthetic.app/Contents/staging') }), /inside an app bundle/);
  stageCanonicalOverlays(args);
  const receipt = fs.readFileSync(path.join(f.outputRoot, 'canonical-source-receipt.json'));
  assert.throws(() => stageCanonicalOverlays(args), /already exists/);
  assert.deepEqual(fs.readFileSync(path.join(f.outputRoot, 'canonical-source-receipt.json')), receipt);
  f.untouched();
});

function presentationFixture() {
  const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'bar-presentation-cpu-')));
  const overlay = path.join(root, 'macos-luaui-overlays/bar-lobby');
  const files = [
    'LuaUI/Include/DrawPrimitiveAtUnit_NoGS_Mesh.lua', 'LuaUI/Include/InstanceVBOTable_Local.lua',
    'LuaUI/Include/NoGSVAO.lua', 'LuaUI/Include/pip_history.lua',
    'LuaUI/Shaders/HealthbarsGL4_NoGS.vert.glsl',
    'LuaUI/Shaders/screen_distortion_combine_gl4.frag.glsl', 'LuaUI/Shaders/screen_distortion_combine_gl4.vert.glsl',
    'LuaUI/Widgets/gui_pip_macos_minimap_overlay.lua', 'LuaUI/Widgets/api_unit_tracker_gl4.lua',
    'modules/graphics/LuaShader.lua', 'LuaRules/Gadgets/historical.lua',
  ];
  const data = new Map();
  function set(relative, value) {
    const bytes = Buffer.from(value);
    const file = path.join(overlay, relative);
    fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, bytes); data.set(relative, bytes);
  }
  for (const relative of files) set(relative, '-- immutable CPU fixture\r\nreturn "source bytes"\n');
  set('modules/graphics/LuaShader.lua', 'local helper = VFS.Include("modules/graphics/LuaShader.lua", nil, VFS.ZIP_ONLY)\nreturn helper\n');
  set('LuaRules/Gadgets/historical.lua', 'NEVER_COMPILE_HISTORICAL_SYNCED_SOURCE');
  function args() {
    const bytes = Buffer.from(JSON.stringify({ schemaVersion: 1, lane: 'bar-lobby', files, diagnosticFiles: [] }));
    fs.writeFileSync(path.join(overlay, 'manifest.json'), bytes);
    return { stagedAssetsRoot: root, lane: 'bar-lobby', manifestSha256: sha(bytes),
      sourceSha256: Object.fromEntries([...data].filter(([name]) => !name.startsWith('LuaRules/')).map(([name, value]) => [name, sha(value)])) };
  }
  return { root, overlay, files, data, set, args };
}

test('native presentation header is deterministic, exact-source pinned, and excludes historical synced code', () => {
  const f = presentationFixture(); const args = f.args();
  const a = generateBundledPresentationHeader(args), b = generateBundledPresentationHeader(args);
  assert.deepEqual(a, b); assert.equal(a.receipt.widgetCount, 2);
  assert.equal(a.receipt.privateIncludeCount, 4); assert.equal(a.receipt.privateShaderCount, 3);
  assert.equal(a.receipt.inputs.length, 10); assert.deepEqual(a.receipt.excluded, ['LuaRules/Gadgets/historical.lua']);
  assert.ok(!a.header.includes('NEVER_COMPILE_HISTORICAL_SYNCED_SOURCE'));
  assert.ok(a.header.includes('local helper = ...')); assert.ok(a.header.includes('"\\r"'));
  assert.throws(() => generateBundledPresentationHeader({ ...args, manifestSha256: '0'.repeat(64) }), /SHA-256 mismatch/);
  f.set('LuaUI/Widgets/api_unit_tracker_gl4.lua', '-- changed after review');
  assert.throws(() => generateBundledPresentationHeader(args), /source SHA-256 mismatch/);
});

test('native presentation generator rejects malformed and extra resources before embedding', () => {
  for (const condition of ['nul', 'invalid-utf8', 'duplicate-case', 'unreviewed-include', 'diagnostic', 'symlink', 'extra-pin']) {
    const f = presentationFixture();
    if (condition === 'nul') f.set(f.files[0], Buffer.from([1, 0, 2]));
    if (condition === 'invalid-utf8') f.set(f.files[0], Buffer.from([0xff]));
    if (condition === 'duplicate-case') f.files.push(f.files[0].toLowerCase());
    if (condition === 'unreviewed-include') { f.files.push('LuaUI/Include/unreviewed.lua'); f.set(f.files.at(-1), 'return true'); }
    if (condition === 'diagnostic') { f.files.push('LuaUI/Widgets/gui_graphics_diagnostic.lua'); f.set(f.files.at(-1), 'return true'); }
    const args = f.args();
    if (condition === 'symlink') {
      fs.renameSync(path.join(f.overlay, f.files[0]), path.join(f.root, 'linked-input'));
      fs.symlinkSync(path.join(f.root, 'linked-input'), path.join(f.overlay, f.files[0]));
    }
    if (condition === 'extra-pin') args.sourceSha256['LuaUI/Widgets/unlisted.lua'] = '0'.repeat(64);
    assert.throws(() => generateBundledPresentationHeader(args), undefined, condition);
  }
});

test('actual native helper roundtrips compiled CRLF bytes, hashes exact originals and leaves unknown handlers unchanged', () => {
  const f = presentationFixture(), generated = generateBundledPresentationHeader(f.args());
  const nativeRoot = path.resolve('build/run91-recoil-src-694e9df7/rts');
  fs.writeFileSync(path.join(f.root, 'LuaBundledPresentationSources.h'), generated.header);
  fs.copyFileSync(path.join(nativeRoot, 'Lua/LuaBundledPresentation.h'), path.join(f.root, 'LuaBundledPresentation.h'));
  const evidence = path.resolve('artifacts/validation/release-imac-fix-20261015/provider');
  const output = path.join(f.root, 'cpu-generated'); fs.mkdirSync(output, { recursive: true });
  const source = `#include <cassert>\n#include <fstream>\n#include <iterator>\n#include "LuaBundledPresentation.h"\n
std::string Read(const std::string& p) { std::ifstream f(p, std::ios::binary); assert(f); return {std::istreambuf_iterator<char>(f), {}}; }
void Write(const std::string& p, const std::string& s) { std::ofstream f(p, std::ios::binary); f.write(s.data(), s.size()); }
int main(int argc, char** argv) {
 using namespace bundled_presentation;
 assert(FindWidget("LuaUI/Widgets/API_UNIT_TRACKER_GL4.lua") == "-- immutable CPU fixture\\r\\nreturn \\"source bytes\\"\\n");
 assert(FindPrivateSource("LuaUI/Include/NoGSVAO.lua") == "-- immutable CPU fixture\\r\\nreturn \\"source bytes\\"\\n");
 for (const auto* p: {"../luaui/widgets/api_unit_tracker_gl4.lua", "/luaui/widgets/api_unit_tracker_gl4.lua", "luaui//widgets/api_unit_tracker_gl4.lua", "luaui/./widgets/api_unit_tracker_gl4.lua", "luaui/widgets/../api_unit_tracker_gl4.lua", "luaui\\\\widgets/api_unit_tracker_gl4.lua", "luaui/widgets/unknown.lua"}) assert(FindWidget(p).empty());
 assert(FindWidget(std::string_view("luaui/widgets/api_unit_tracker_gl4.lua\\0suffix", 43)).empty());
 assert(FindPrivateSource("luaui/widgets/api_unit_tracker_gl4.lua").empty());
 assert(FindWidget("luaui/include/nogsvao.lua").empty());
 std::vector<std::string> files {"normal.lua"}; AddDistributionWidget(files); assert(files.size() == 2); AddDistributionWidget(files); assert(files.size() == 2);
 files.emplace_back("LUAUI/WIDGETS/GUI_PIP_MACOS_MINIMAP_OVERLAY.LUA"); AddDistributionWidget(files); assert(files.size() == 2);
 for (const auto* version: {"433a460", "ebba846"}) {
  const std::string stem = std::string(argv[1]) + "/official-" + version;
  const auto original = Read(stem + "-barwidgets.lua"); auto handler = original; assert(AugmentWidgetHandler(handler));
  assert(handler.find("local __barBundledWidgetSource = ...\\n") == 0);
  Write(std::string(argv[2]) + "/" + version + "-barwidgets.lua", handler);
  auto unknown = original; unknown.back() = unknown.back() == 'x' ? 'y' : 'x'; const auto before = unknown;
  assert(!AugmentWidgetHandler(unknown) && unknown == before);
  auto helper = Read(stem + "-LuaShader.lua"); assert(WrapLuaRulesHelper(helper));
  Write(std::string(argv[2]) + "/" + version + "-LuaShader.lua", helper);
  auto badHelper = Read(stem + "-LuaShader.lua") + " "; const auto badBefore = badHelper;
  assert(!WrapLuaRulesHelper(badHelper) && badHelper == badBefore);
 }
 const auto currentOriginal = Read(argv[3]); auto current = currentOriginal;
 assert(current.size() == 141304 && AugmentWidgetHandler(current));
 Write(std::string(argv[2]) + "/ad2e1b7-barwidgets.lua", current);
 auto changed = currentOriginal; changed.back() ^= 1; const auto changedBefore = changed;
 assert(!AugmentWidgetHandler(changed) && changed == changedBefore);
 auto unknownHandler = std::string("return {}"); assert(!AugmentWidgetHandler(unknownHandler) && unknownHandler == "return {}");
 Write(std::string(argv[2]) + "/compiled-fixture-widget.lua", std::string(FindWidget("luaui/widgets/api_unit_tracker_gl4.lua")));
}\n`;
  const cpp = path.join(f.root, 'provider-cpu.cpp'), binary = path.join(f.root, 'provider-cpu');
  fs.writeFileSync(cpp, source);
  execFileSync('/usr/bin/clang++', ['-std=c++17', '-O0', '-I', f.root, '-I', nativeRoot, cpp, path.join(nativeRoot, 'System/Sync/SHA512.cpp'), '-o', binary]);
  execFileSync(binary, [evidence, output, path.resolve('artifacts/validation/healthbar-radar-regression-20261017/current-content/luaui/barwidgets.lua')]);
  assert.deepEqual(fs.readFileSync(path.join(output, 'compiled-fixture-widget.lua')), f.data.get('LuaUI/Widgets/api_unit_tracker_gl4.lua'));
  for (const version of ['433a460', 'ebba846', 'ad2e1b7']) {
    const original = fs.readFileSync(version === 'ad2e1b7' ? 'artifacts/validation/healthbar-radar-regression-20261017/current-content/luaui/barwidgets.lua' : path.join(evidence, `official-${version}-barwidgets.lua`), 'utf8');
    const transformed = fs.readFileSync(path.join(output, `${version}-barwidgets.lua`), 'utf8');
    const prefix = 'local __barBundledWidgetSource = ...\n';
    const addition = '\tlocal __barBundledText = __barBundledWidgetSource(filename)\n\tif __barBundledText ~= nil then\n\t\ttext = __barBundledText\n\t\tfromZip = true\n\tend\n';
    assert.equal(transformed.slice(prefix.length).replace(addition, ''), original, 'all original handler/sandbox bytes preserved');
  }
});

test('final pinned production tables roundtrip every compiled byte and generate actual LuaRules wrappers', () => {
  const pinBytes = fs.readFileSync('artifacts/validation/spring-default-1.0.2-20261018/presentation-source-pins.json');
  assert.equal(sha(pinBytes), '0e19907b2f5918063280a156279b01a1af966e19cb669319fcd0e5faeb28659d');
  const pins = JSON.parse(pinBytes);
  const evidence = path.resolve('artifacts/validation/release-imac-fix-20261015/provider');
  const cpu = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'bar-production-presentation-cpu-')));
  const nativeRoots = {
    'bar-lobby': path.resolve('build/run91-recoil-src-694e9df7'),
    'bar-chobby': path.resolve('artifacts/runtime/run94-chobby-official-20260704-20260924/source'),
  };
  const rows = [];
  for (const [lane, root] of Object.entries(nativeRoots)) {
    const generated = generateBundledPresentationHeader({ stagedAssetsRoot: path.dirname(pins.assetRoot), lane, ...pins.lanes[lane] });
    assert.equal(sha(fs.readFileSync(path.join(root, 'rts/Lua/LuaBundledPresentationSources.h'))), sha(generated.header), 'exact production header digest');
    const cpp = path.join(cpu, lane + '.cpp'), binary = path.join(cpu, lane);
    const nativeVfs = fs.readFileSync(path.join(root, 'rts/Lua/LuaVFS.cpp'), 'utf8');
    const context = nativeVfs.slice(nativeVfs.indexOf('static bool IsUnsyncedPresentationHandle('), nativeVfs.indexOf('/*** Unified IO'));
    assert.ok(context.includes('#ifdef __APPLE__') && context.includes('!CLuaHandle::GetHandleSynced(L)'));
    const nonMacContext = context.replace('IsUnsyncedPresentationHandle', 'DisabledPresentationHandle').replace('#ifdef __APPLE__', '#if 0');
    fs.writeFileSync(cpp, `#include <cassert>\n#include <iostream>\n#include <fstream>\n#include <iterator>\n#include "Lua/LuaBundledPresentation.h"\n
struct lua_State;
struct CLuaHandle { std::string name; const std::string& GetName() const { return name; } static CLuaHandle* GetHandle(lua_State*); static bool GetHandleSynced(lua_State*); };
struct lua_State { CLuaHandle* owner; bool synced; const char* spoofedScriptName; };
CLuaHandle* CLuaHandle::GetHandle(lua_State* L) { return L->owner; } bool CLuaHandle::GetHandleSynced(lua_State* L) { return L->synced; }
${context}\n${nonMacContext}\n
void Print(std::string_view path, std::string_view text) { sha512::raw_digest raw{}; sha512::hex_digest hex{}; sha512::calc_digest(reinterpret_cast<const uint8_t*>(text.data()), text.size(), raw.data()); sha512::dump_digest(raw, hex); std::cout << path << "\\t" << text.size() << "\\t" << hex.data() << "\\n"; }
int main(int argc, char** argv) {
 CLuaHandle ui {"LuaUI"}, rules {"LuaRules"}, intro {"LuaIntro"};
 lua_State L {&ui, false, "LuaRules"}; assert(IsUnsyncedPresentationHandle(&L, "LuaUI")); assert(!DisabledPresentationHandle(&L, "LuaUI"));
 L.synced = true; assert(!IsUnsyncedPresentationHandle(&L, "LuaUI")); L.synced = false;
 L.owner = &rules; L.spoofedScriptName = "LuaUI"; assert(!IsUnsyncedPresentationHandle(&L, "LuaUI")); assert(IsUnsyncedPresentationHandle(&L, "LuaRules"));
 L.owner = &intro; assert(!IsUnsyncedPresentationHandle(&L, "LuaUI")); L.owner = nullptr; assert(!IsUnsyncedPresentationHandle(&L, "LuaUI"));
 for (const auto& entry: bundled_presentation_data::WIDGETS) Print(entry.path, entry.bytes);
 for (const auto& entry: bundled_presentation_data::PRIVATE_SOURCES) Print(entry.path, entry.bytes);
 Print("modules/graphics/luashader.lua", bundled_presentation_data::LUA_RULES_ADAPTER);
 for (const auto* version: {"433a460", "ebba846"}) {
  std::ifstream input(std::string(argv[1]) + "/official-" + version + "-LuaShader.lua", std::ios::binary);
  std::string source {std::istreambuf_iterator<char>(input), {}}; if (!bundled_presentation::WrapLuaRulesHelper(source)) return 1;
  std::ofstream output(std::string(argv[3]) + "/" + argv[2] + "-" + version + "-LuaShader.lua", std::ios::binary); output.write(source.data(), source.size());
 }
}\n`);
    execFileSync('/usr/bin/clang++', ['-std=c++17', '-O0', '-I', path.join(root, 'rts'), cpp, path.join(root, 'rts/System/Sync/SHA512.cpp'), '-o', binary]);
    const output = execFileSync(binary, [evidence, lane, cpu], { encoding: 'utf8' });
    const compiled = new Map(output.trim().split('\n').map(line => { const [file, bytes, sha512] = line.split('\t'); return [file, { bytes: Number(bytes), sha512 }]; }));
    assert.equal(compiled.size, generated.receipt.inputs.length);
    for (const entry of generated.receipt.inputs) {
      let bytes = fs.readFileSync(path.join(pins.assetRoot, lane, entry.path));
      if (entry.path === 'modules/graphics/LuaShader.lua') {
        bytes = Buffer.from(bytes.toString().replace('local helper = VFS.Include("modules/graphics/LuaShader.lua", nil, VFS.ZIP_ONLY)', 'local helper = ...'));
      }
      assert.deepEqual(compiled.get(entry.path.toLowerCase()), { bytes: bytes.length, sha512: crypto.createHash('sha512').update(bytes).digest('hex') }, entry.path);
    }
    rows.push({ lane, compiledEntries: compiled.size, headerSha256: generated.receipt.headerSha256, bytesMatched: true });
  }
  fs.writeFileSync(path.join(cpu, 'compiled-production-roundtrip.json'), JSON.stringify({ scope: 'CPU helper/table compilation only; no engine build or game/GPU', lanes: rows }, null, 2) + '\n');
});
