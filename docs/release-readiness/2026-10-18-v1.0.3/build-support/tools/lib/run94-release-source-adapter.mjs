import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { SOURCE_IDENTITY, REQUIRED_REVIEWED_FILES, ARCHIVE_DEPENDENCIES } from './run94-canonical-overlay-intake.mjs';
// Uses the project's Node >=22.18 native TypeScript support. Reuse the builder's
// digest and validation implementation instead of defining a second tree format.
import { createPinnedBundledAssets, hashBundledAssetEntry, REQUIRED_BUNDLED_ASSET_ENTRIES } from '../../sources/bar-lobby/packaging/pinned-bundled-assets.ts';

export const PROTECTED_RELEASE_BASELINE = Object.freeze({
  id: SOURCE_IDENTITY.baselineId,
  lanes: Object.freeze({
    'bar-chobby': Object.freeze({ engineDirectory: '2026.07.04', springSha256: '2339edaa15d165ffd45fe3c3429ef150958407296906997692c834ae1b1ea0e3' }),
    'bar-lobby': Object.freeze({ engineDirectory: '2026.09.10-0-g694e9df7', springSha256: '6a28609d19f6bf7809e18515f4d15c439e3fbe6765b9cdd28fe71754b96c8707' }),
  }),
});

const workspace = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const lanes = ['bar-chobby', 'bar-lobby'];
const metadata = ['accepted-contract.json', 'legacy-managed-files.json', 'README.md'];
const overlayEntry = 'macos-luaui-overlays';
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const isSha = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);

function object(value, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error(`Invalid ${label}`);
  return value;
}
function absolute(value, label) {
  if (typeof value !== 'string' || !path.isAbsolute(value)) throw new Error(`${label} must be an explicit absolute path`);
  return path.resolve(value);
}
function inside(parent, child) {
  const relative = path.relative(parent, child);
  return !relative || (!path.isAbsolute(relative) && relative !== '..' && !relative.startsWith(`..${path.sep}`));
}
function exists(file) {
  try { fs.lstatSync(file); return true; } catch (error) {
    if (error.code === 'ENOENT') return false;
    throw error;
  }
}
function sourceDirectory(value, label) {
  const directory = fs.realpathSync(absolute(value, label));
  if (!fs.lstatSync(directory).isDirectory()) throw new Error(`${label} must be a directory`);
  return directory;
}
function regularFile(value, label) {
  const file = fs.realpathSync(absolute(value, label));
  if (!fs.lstatSync(file).isFile()) throw new Error(`${label} must be a regular file`);
  return file;
}
function hashFile(file) {
  const hash = crypto.createHash('sha256');
  const buffer = Buffer.alloc(1024 * 1024);
  const fd = fs.openSync(file, 'r');
  try {
    let length;
    while ((length = fs.readSync(fd, buffer, 0, buffer.length, null)) !== 0) hash.update(buffer.subarray(0, length));
  } finally {
    fs.closeSync(fd);
  }
  return hash.digest('hex');
}
function pinnedJson(filePath, digest, label) {
  if (!isSha(digest)) throw new Error(`${label} requires an explicit SHA-256 pin`);
  const file = regularFile(filePath, label);
  const bytes = fs.readFileSync(file);
  if (sha(bytes) !== digest) throw new Error(`${label} SHA-256 mismatch`);
  return { file, bytes, sha256: digest, value: object(JSON.parse(bytes.toString('utf8')), label) };
}
function relativeFile(value) {
  if (typeof value !== 'string' || !value || value.includes('\\') || value.includes('\0') || path.posix.isAbsolute(value) ||
      value.split('/').some(part => !part || part === '.' || part === '..')) throw new Error(`Unsafe canonical path: ${value}`);
  return value;
}
function exactKeys(value, expected, label) {
  if (JSON.stringify(Object.keys(value).sort()) !== JSON.stringify([...expected].sort())) throw new Error(`${label} key set mismatch`);
}
function sameHashMap(actual, expected, label) {
  object(actual, label);
  exactKeys(actual, Object.keys(expected), label);
  for (const key of Object.keys(expected)) if (actual[key] !== expected[key]) throw new Error(`${label} mismatch: ${key}`);
}
function newDestination(value, inputs) {
  const requested = absolute(value, 'outputRoot');
  if (exists(requested)) throw new Error('Release input output already exists; refusing overwrite');
  let ancestor = requested;
  while (!exists(ancestor)) ancestor = path.dirname(ancestor);
  const physical = path.resolve(fs.realpathSync(ancestor), path.relative(ancestor, requested));
  if ([requested, physical].some(item => item.split(path.sep).some(part => /\.app$/i.test(part)))) throw new Error('Release input output cannot be inside an app bundle');
  for (const input of inputs) {
    const resolved = exists(input) ? fs.realpathSync(input) : path.resolve(input);
    if (inside(resolved, physical) || inside(physical, resolved)) throw new Error(`Release input output overlaps source/input: ${resolved}`);
  }
  return physical;
}

function validateReleaseLock(lock) {
  if (lock.schemaVersion !== 1 || lock.baselineId !== PROTECTED_RELEASE_BASELINE.id) throw new Error('Release input lock schema/baseline mismatch');
  const pins = object(lock.lanes, 'release engine pins');
  exactKeys(pins, lanes, 'Release engine lanes');
  for (const lane of lanes) {
    const pin = object(pins[lane], `${lane} engine pin`);
    const expected = PROTECTED_RELEASE_BASELINE.lanes[lane];
    if (pin.engineDirectory !== expected.engineDirectory || pin.springSha256 !== expected.springSha256) throw new Error(`Protected ${lane} engine pin mismatch`);
  }
  const entries = object(lock.entries, 'release entry pins');
  exactKeys(entries, REQUIRED_BUNDLED_ASSET_ENTRIES, 'Release bundled entries');
  for (const entry of REQUIRED_BUNDLED_ASSET_ENTRIES) if (!isSha(entries[entry])) throw new Error(`Invalid release entry digest: ${entry}`);
}

function captureCanonicalSnapshot(snapshotRoot, reviewed) {
  const lock = reviewed.value;
  if (lock.schemaVersion !== 2 || lock.kind !== 'reviewed-canonical-overlays' || typeof lock.revision !== 'string' || !lock.revision.trim()) {
    throw new Error('A reviewed canonical schema-2 lock is required');
  }
  for (const [key, expected] of Object.entries(SOURCE_IDENTITY)) if (lock[key] !== expected) throw new Error(`Canonical ${key} mismatch`);
  if (lock.archiveContent !== undefined && (typeof lock.archiveContent !== 'string' || !/^[a-f0-9]{40}$/.test(lock.archiveContent))) throw new Error('Invalid separately pinned runtime archive content');
  const pins = object(lock.files, 'canonical file pins');
  for (const [relative, digest] of Object.entries(pins)) if (!isSha(digest) || !relativeFile(relative)) throw new Error(`Invalid canonical pin: ${relative}`);
  const archivePins = object(lock.archiveDependencies, 'canonical archive pins');
  exactKeys(archivePins, ARCHIVE_DEPENDENCIES, 'Canonical archive dependencies');
  for (const [relative, digest] of Object.entries(archivePins)) if (!isSha(digest)) throw new Error(`Invalid archive pin: ${relative}`);

  const copiedLock = pinnedJson(path.join(snapshotRoot, 'canonical-source-lock.json'), reviewed.sha256, 'snapshot canonical lock');
  if (!copiedLock.bytes.equals(reviewed.bytes)) throw new Error('Snapshot lock differs from reviewed canonical lock');
  const receiptFile = regularFile(path.join(snapshotRoot, 'canonical-source-receipt.json'), 'canonical snapshot receipt');
  const receiptBytes = fs.readFileSync(receiptFile);
  const receipt = object(JSON.parse(receiptBytes.toString('utf8')), 'canonical snapshot receipt');
  if (receipt.schemaVersion !== 1 || receipt.status !== 'reviewed-canonical-source-snapshot-only' || receipt.lockSha256 !== reviewed.sha256 || receipt.revision !== lock.revision ||
      receipt.sourceModified !== false || receipt.templateRegeneration !== false || receipt.parentOverlayImport !== false || receipt.appAssemblyAllowed !== false ||
      receipt.requiresReleaseInputGate !== true || receipt.archiveDependencyBytesChecked !== false) throw new Error('Canonical snapshot receipt contract mismatch');
  for (const [key, expected] of Object.entries(SOURCE_IDENTITY)) if (receipt[key] !== expected) throw new Error(`Canonical receipt ${key} mismatch`);
  sameHashMap(receipt.files, pins, 'Canonical receipt files');
  sameHashMap(receipt.archiveDependencies, archivePins, 'Canonical receipt archive pins');

  const overlayRoot = sourceDirectory(path.join(snapshotRoot, overlayEntry), 'canonical overlay snapshot');
  const files = new Map();
  const directories = [];
  function capture(directory, prefix = '') {
    directories.push({ relative: prefix, mode: fs.lstatSync(directory).mode & 0o777 });
    for (const name of fs.readdirSync(directory).sort()) {
      const relative = relativeFile(prefix ? `${prefix}/${name}` : name);
      const file = path.join(directory, name);
      const stat = fs.lstatSync(file);
      if (stat.isDirectory()) {
        if (!Object.keys(pins).some(key => key.startsWith(`${relative}/`))) throw new Error(`Unpinned canonical directory: ${relative}`);
        capture(file, relative);
      } else if (stat.isFile()) {
        if (!Object.hasOwn(pins, relative)) throw new Error(`Unpinned canonical file: ${relative}`);
        const bytes = fs.readFileSync(file);
        if (sha(bytes) !== pins[relative]) throw new Error(`Canonical snapshot hash mismatch: ${relative}`);
        files.set(relative, { bytes, mode: stat.mode & 0o777 });
      } else throw new Error(`Canonical snapshot contains a symlink or special entry: ${relative}`);
    }
  }
  capture(overlayRoot);
  exactKeys(Object.fromEntries(files), Object.keys(pins), 'Canonical snapshot files');
  function json(relative) {
    const entry = files.get(relative);
    if (!entry) throw new Error(`Required canonical metadata missing: ${relative}`);
    return object(JSON.parse(entry.bytes.toString('utf8')), relative);
  }
  const contract = json('accepted-contract.json');
  if (!Array.isArray(contract.barChobbyForbiddenPrefixes) || !contract.barChobbyForbiddenPrefixes.includes('LuaRules/') || !Array.isArray(contract.forbiddenFrozenWidgets)) {
    throw new Error('Canonical official-content ownership contract missing');
  }
  const forbidden = new Set([...contract.forbiddenFrozenWidgets.map(relativeFile), 'LuaUI/Widgets/gui_build_placement_extension.lua', 'LuaUI/Widgets/gui_buildsquare_macos.lua']);
  const declared = new Set(metadata);
  for (const lane of lanes) {
    const manifestPath = `${lane}/manifest.json`;
    declared.add(manifestPath);
    const manifest = json(manifestPath);
    if (manifest.lane !== lane || !Array.isArray(manifest.files) || manifest.engineDirectory !== PROTECTED_RELEASE_BASELINE.lanes[lane].engineDirectory ||
        manifest.selectedContentCommit !== (lock.archiveContent ?? SOURCE_IDENTITY.selectedContent)) throw new Error(`Canonical ${lane} manifest identity mismatch`);
    const paths = manifest.files.map(relativeFile);
    if (new Set(paths).size !== paths.length) throw new Error(`Duplicate canonical ${lane} manifest entry`);
    for (const required of REQUIRED_REVIEWED_FILES) if (!paths.includes(required)) throw new Error(`Missing reviewed ${lane} source: ${required}`);
    for (const relative of paths) {
      if (forbidden.has(relative) || !(relative.startsWith('LuaUI/') || (lane === 'bar-lobby' && relative.startsWith('LuaRules/')))) {
        throw new Error(`Canonical content ownership violation: ${lane}/${relative}`);
      }
      declared.add(`${lane}/${relative}`);
    }
  }
  exactKeys(pins, declared, 'Canonical manifests');
  return { overlayRoot, files, directories, receiptBytes, sourceRoot: absolute(receipt.sourceRoot, 'canonical receipt sourceRoot') };
}

// This is independent evidence, not another copy of lock.archiveDependencies:
// { schemaVersion: 1, kind: 'verified-official-archive-dependencies',
//   status: 'verified', method: 'selected-archive-extraction', selectedContent,
//   archive: { path: '/existing/selected-archive-or-Rapid-package', sha256 },
//   dependencies: { 'luaui/...': { path: '/existing/extraction/file', sha256 }, ... } }
// Its separately supplied digest identifies the parent's reviewed extraction
// receipt. The adapter also checks the referenced archive and dependency bytes.
// It does not extract an archive or establish in-game VFS selection itself.
function inspectArchiveEvidence(options, canonicalLock, excludedRoots, excludedFiles) {
  if (!options.archiveEvidencePath || !options.archiveEvidenceSha256) {
    return { blockers: ['Missing separately pinned selected-archive extraction evidence; copied dependency pins are not proof.'], inputs: [] };
  }
  try {
    const evidence = pinnedJson(options.archiveEvidencePath, options.archiveEvidenceSha256, 'official archive evidence');
    const value = evidence.value;
    if (value.schemaVersion !== 1 || value.kind !== 'verified-official-archive-dependencies' || value.status !== 'verified' ||
        value.method !== 'selected-archive-extraction' || value.selectedContent !== (canonicalLock.archiveContent ?? canonicalLock.selectedContent)) throw new Error('Official archive evidence schema/status/content mismatch');
    const archive = object(value.archive, 'evidence archive identity');
    if (!isSha(archive.sha256)) throw new Error('Missing evidence archive SHA-256');
    const archivePath = regularFile(archive.path, 'evidence archive');
    if (excludedFiles.includes(archivePath) || archivePath === evidence.file || excludedRoots.some(root => inside(root, archivePath))) {
      throw new Error('Official archive evidence cannot use a source lock, overlay snapshot or bundle input as its archive');
    }
    if (hashFile(archivePath) !== archive.sha256) throw new Error('Evidence archive bytes no longer match the reviewed extraction receipt');
    const dependencies = object(value.dependencies, 'evidence dependencies');
    exactKeys(dependencies, ARCHIVE_DEPENDENCIES, 'Evidence dependencies');
    const paths = new Set([evidence.file, archivePath, ...excludedFiles]);
    const inputs = [evidence.file, archivePath];
    const verified = {};
    for (const relative of ARCHIVE_DEPENDENCIES) {
      const entry = object(dependencies[relative], `evidence dependency ${relative}`);
      if (entry.sha256 !== canonicalLock.archiveDependencies[relative]) throw new Error(`Official dependency evidence/pin mismatch: ${relative}`);
      const file = regularFile(entry.path, `extracted official dependency ${relative}`);
      if (paths.has(file) || excludedRoots.some(root => inside(root, file))) throw new Error(`Official dependency lacks an independent extraction file: ${relative}`);
      if (hashFile(file) !== entry.sha256) throw new Error(`Official extracted dependency bytes mismatch: ${relative}`);
      paths.add(file);
      inputs.push(file);
      verified[relative] = entry.sha256;
    }
    return {
      blockers: [], inputs, bytes: evidence.bytes,
      summary: {
        receiptSha256: evidence.sha256,
        method: value.method,
        selectedContent: value.selectedContent,
        archiveSha256: archive.sha256,
        checkedDependencyFiles: verified,
        extractionAttestedByReviewedReceipt: true,
        inGameVfsSelectionChecked: false,
      },
    };
  } catch (error) {
    return { blockers: [`Official archive evidence blocked: ${error instanceof Error ? error.message : String(error)}`], inputs: [] };
  }
}

function prepare(options) {
  const bundledAssetsRoot = sourceDirectory(options.bundledAssetsRoot, 'bundledAssetsRoot');
  const canonicalSnapshotRoot = sourceDirectory(options.canonicalSnapshotRoot, 'canonicalSnapshotRoot');
  const canonical = pinnedJson(options.canonicalLockPath, options.canonicalLockSha256, 'reviewed canonical lock');
  const release = pinnedJson(options.releaseLockPath, options.releaseLockSha256, 'reviewed release input lock');
  validateReleaseLock(release.value);
  const snapshot = captureCanonicalSnapshot(canonicalSnapshotRoot, canonical);
  const entries = [];
  for (const entry of REQUIRED_BUNDLED_ASSET_ENTRIES) {
    // Deliberately never inspect or import the old bundle's overlay root.
    const sourceRoot = entry === overlayEntry ? canonicalSnapshotRoot : bundledAssetsRoot;
    const from = path.join(sourceRoot, entry);
    const stat = fs.lstatSync(from);
    if (!(entry === 'chobby-multiplayer-profile.json' ? stat.isFile() : stat.isDirectory())) throw new Error(`Required bundled root has wrong type: ${entry}`);
    const digest = hashBundledAssetEntry(sourceRoot, entry);
    if (digest !== release.value.entries[entry]) throw new Error(`Reviewed release input digest mismatch: ${entry}`);
    entries.push({ entry, from, sha256: digest });
  }
  for (const lane of lanes) {
    const pin = PROTECTED_RELEASE_BASELINE.lanes[lane];
    const spring = path.join(bundledAssetsRoot, 'engine', pin.engineDirectory, 'spring');
    const stat = fs.lstatSync(spring);
    if (!stat.isFile() || !(stat.mode & 0o111) || hashFile(spring) !== pin.springSha256) throw new Error(`Protected ${lane} engine bytes mismatch`);
  }
  const profile = JSON.parse(fs.readFileSync(path.join(bundledAssetsRoot, 'chobby-multiplayer-profile.json'), 'utf8'));
  if (profile?.engineVersion !== PROTECTED_RELEASE_BASELINE.lanes['bar-chobby'].engineDirectory || profile?.gameRapidAlias !== 'byar:test') throw new Error('Protected Chobby profile mismatch');

  const protectedInputs = [bundledAssetsRoot, canonicalSnapshotRoot, canonical.file, release.file, snapshot.sourceRoot, path.join(workspace, 'sources'), path.join(workspace, 'tools')];
  const evidence = inspectArchiveEvidence(options, canonical.value, [bundledAssetsRoot, canonicalSnapshotRoot, snapshot.sourceRoot], [canonical.file, release.file]);
  protectedInputs.push(...evidence.inputs);
  const outputRoot = newDestination(options.outputRoot, protectedInputs);
  const stagedAssetsRoot = path.join(outputRoot, 'bundled-assets');
  const buildEnvironment = {
    BAR_BUNDLED_ASSETS_PATH: stagedAssetsRoot,
    BAR_BUNDLED_ASSETS_LOCK_PATH: path.join(outputRoot, 'release-input-lock.json'),
    BAR_BUNDLED_ASSETS_LOCK_SHA256: release.sha256,
  };
  const plan = {
    schemaVersion: 1,
    status: evidence.blockers.length ? 'blocked-official-archive-evidence' : 'ready-for-pinned-release-input-staging',
    blockers: evidence.blockers,
    outputRoot, stagedAssetsRoot,
    baselineId: PROTECTED_RELEASE_BASELINE.id,
    sourceOriginContent: canonical.value.selectedContent,
    archiveContent: canonical.value.archiveContent ?? canonical.value.selectedContent,
    engines: PROTECTED_RELEASE_BASELINE.lanes,
    canonicalLockSha256: canonical.sha256,
    releaseLockSha256: release.sha256,
    entries,
    archiveEvidence: evidence.summary ?? null,
    buildEnvironment,
    requiresFreshReviewedLauncherBuild: true,
    completeSourceDependencyLockEstablished: false,
    createsApp: false,
    promotesApp: false,
  };
  return { plan, snapshot, canonical, release, evidence, protectedInputs };
}

/** Read-only planning. Missing independent archive evidence is returned as a blocker. */
export function createReleaseSourcePlan(options) {
  return prepare(options).plan;
}

/**
 * Explicit execution by the parent: copy into a previously absent input directory.
 * Does not build, sign, launch, publish, promote, edit source, or replace an app.
 * Failure leaves an unaccepted staging directory for inspection; no cleanup or
 * overwrite is attempted. Do not run this as part of a source-only code review.
 */
export function stageReleaseSources(options) {
  const prepared = prepare(options);
  const { plan, snapshot, canonical, release, evidence, protectedInputs } = prepared;
  if (plan.blockers.length) throw new Error(plan.blockers.join('\n'));
  newDestination(plan.outputRoot, protectedInputs);
  fs.mkdirSync(path.dirname(plan.outputRoot), { recursive: true });
  fs.mkdirSync(plan.outputRoot);
  fs.mkdirSync(plan.stagedAssetsRoot);
  for (const entry of plan.entries) {
    if (entry.entry === overlayEntry) continue;
    fs.cpSync(entry.from, path.join(plan.stagedAssetsRoot, entry.entry), {
      recursive: true, dereference: false, verbatimSymlinks: true,
      preserveTimestamps: true, force: false, errorOnExist: true,
    });
  }
  const overlayRoot = path.join(plan.stagedAssetsRoot, overlayEntry);
  for (const directory of snapshot.directories) {
    const destination = path.join(overlayRoot, directory.relative);
    fs.mkdirSync(destination, { mode: directory.mode });
    fs.chmodSync(destination, directory.mode);
  }
  for (const [relative, file] of snapshot.files) {
    const destination = path.join(overlayRoot, relative);
    fs.writeFileSync(destination, file.bytes, { flag: 'wx', mode: file.mode });
    fs.chmodSync(destination, file.mode);
  }
  fs.writeFileSync(plan.buildEnvironment.BAR_BUNDLED_ASSETS_LOCK_PATH, release.bytes, { flag: 'wx' });
  // The same gate is run again by electron-builder beforePack. This check binds
  // the copied native inputs and captured canonical bytes to all six entry pins.
  createPinnedBundledAssets(plan.buildEnvironment, PROTECTED_RELEASE_BASELINE).validate();
  const provenance = path.join(plan.outputRoot, 'source-provenance');
  fs.mkdirSync(provenance);
  fs.writeFileSync(path.join(provenance, 'canonical-source-lock.json'), canonical.bytes, { flag: 'wx' });
  fs.writeFileSync(path.join(provenance, 'canonical-source-receipt.json'), snapshot.receiptBytes, { flag: 'wx' });
  fs.writeFileSync(path.join(provenance, 'official-archive-evidence.json'), evidence.bytes, { flag: 'wx' });
  const receipt = { ...plan, status: 'pinned-release-inputs-staged-not-built', blockers: [], stagedInputGatePassed: true };
  fs.writeFileSync(path.join(plan.outputRoot, 'release-source-stage-receipt.json'), `${JSON.stringify(receipt, null, 2)}\n`, { flag: 'wx' });
  return receipt;
}

const privatePresentationPaths = Object.freeze([
  'luaui/include/drawprimitiveatunit_nogs_mesh.lua',
  'luaui/include/instancevbotable_local.lua',
  'luaui/include/nogsvao.lua',
  'luaui/include/pip_history.lua',
  'luaui/barmacos/healthbars/healthbars.vert.glsl',
  'luaui/barmacos/healthbars/healthbars.frag.glsl',
  'luaui/shaders/screen_distortion_combine_gl4.frag.glsl',
  'luaui/shaders/screen_distortion_combine_gl4.vert.glsl',
]);

/**
 * Generate immutable native presentation data from one explicitly pinned final
 * production manifest. Pure output: the caller writes the returned header and
 * receipt to its existing engine/build evidence paths. No build, runtime file
 * discovery, canonical historical tree import, or archive edit is performed.
 */
export function generateBundledPresentationHeader(options) {
  const assets = sourceDirectory(options.stagedAssetsRoot, 'staged production assets');
  if (!lanes.includes(options.lane)) throw new Error('Unknown presentation lane');
  const overlay = sourceDirectory(path.join(assets, overlayEntry, options.lane), 'staged production overlay');
  const pinned = pinnedJson(path.join(overlay, 'manifest.json'), options.manifestSha256, 'production presentation manifest');
  const sourcePins = object(options.sourceSha256, 'reviewed production source SHA-256 pins');
  for (const [relative, digest] of Object.entries(sourcePins)) {
    relativeFile(relative);
    if (!isSha(digest)) throw new Error(`Invalid production source pin: ${relative}`);
  }
  const manifest = pinned.value;
  if (manifest.schemaVersion !== 1 || manifest.lane !== options.lane || !Array.isArray(manifest.files)
      || !Array.isArray(manifest.diagnosticFiles) || manifest.diagnosticFiles.length !== 0) {
    throw new Error('A production manifest without diagnostic widgets is required');
  }
  const widgets = [], privateSources = [], inputs = [], excluded = [], keys = new Set();
  let adapter;
  for (const relative of [...manifest.files].sort()) {
    relativeFile(relative);
    const normalized = relative.toLowerCase();
    if (keys.has(normalized)) throw new Error(`Duplicate normalized presentation path: ${relative}`);
    keys.add(normalized);
    if (/^luarules\/gadgets\/[a-z0-9_]+\.lua$/.test(normalized)) {
      excluded.push(relative); // Historical synced content is never compiled.
      continue;
    }
    if (/diagnostic|observer|probe/.test(normalized)) throw new Error(`Diagnostic source cannot be compiled: ${relative}`);
    const widget = /^luaui\/widgets\/[a-z0-9_]+\.lua$/.test(normalized);
    const privateSource = privatePresentationPaths.includes(normalized);
    const helper = normalized === 'modules/graphics/luashader.lua';
    if (!widget && !privateSource && !helper) throw new Error(`Unreviewed presentation path class: ${relative}`);
    const file = path.join(overlay, relative);
    if (!fs.lstatSync(file).isFile() || fs.realpathSync(file) !== file) throw new Error(`Presentation input must be a regular non-symlink file: ${relative}`);
    const bytes = fs.readFileSync(file);
    if (sha(bytes) !== sourcePins[relative]) throw new Error(`Reviewed production source SHA-256 mismatch: ${relative}`);
    if (!bytes.length || bytes.length > 2 * 1024 * 1024 || bytes.includes(0)) {
      throw new Error(`Bounded NUL-free presentation source required: ${relative}`);
    }
    const text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
    if (!Buffer.from(text).equals(bytes)) throw new Error(`Presentation UTF-8 roundtrip changed bytes: ${relative}`);
    const entry = { path: normalized, relative, bytes: bytes.length, sha256: sha(bytes), text };
    inputs.push({ path: relative, bytes: entry.bytes, sha256: entry.sha256 });
    if (widget) widgets.push(entry);
    if (privateSource) privateSources.push(entry);
    if (helper) adapter = entry;
  }
  exactKeys(sourcePins, inputs.map(entry => entry.path), 'Reviewed production presentation source set');
  exactKeys(Object.fromEntries(privateSources.map(entry => [entry.path, true])), privatePresentationPaths, 'Private presentation resources');
  if (!['gui_pip_macos_minimap_overlay.lua', 'gui_healthbars_gl4.lua', 'api_unit_tracker_gl4.lua']
      .every(name => widgets.some(entry => entry.path === `luaui/widgets/${name}`)) || !adapter) {
    throw new Error('Production widget/custom PIP/helper set is incomplete');
  }
  const adapterAnchor = 'local helper = VFS.Include("modules/graphics/LuaShader.lua", nil, VFS.ZIP_ONLY)';
  if (adapter.text.split(adapterAnchor).length !== 2) throw new Error('Recursive helper adapter anchor missing or ambiguous');
  const adapted = adapter.text.replace(adapterAnchor, 'local helper = ...');
  function rawLiteral(text) {
    // C++ raw delimiters have a 16-byte limit. Derive a deterministic safe one;
    // CR is emitted separately below, avoiding C++ newline normalization.
    for (let counter = 0; counter < 1024; counter++) {
      const delimiter = `BAR${sha(`${counter}:${text}`).slice(0, 12)}`;
      if (!text.includes(`)${delimiter}"`)) return `R"${delimiter}(${text})${delimiter}"`;
    }
    throw new Error('No safe bounded C++ raw-string delimiter');
  }
  function literal(text) {
    return text.split('\r').map(rawLiteral).join(' "\\r" ');
  }
  function table(name, entries) {
    return `inline constexpr Source ${name}[] = {\n${entries.map(entry =>
      `\t{ "${entry.path}", std::string_view(${literal(entry.text)}, ${entry.bytes}) },`).join('\n')}\n};\n`;
  }
  const header = Buffer.from('/* This file is part of the Spring engine (GPL v2 or later), see LICENSE.html */\n'
    + '// Generated from the pinned production manifest by run94-release-source-adapter.mjs.\n#pragma once\n#include <string_view>\n'
    + 'namespace bundled_presentation_data {\nstruct Source { std::string_view path; std::string_view bytes; };\n'
    + `inline constexpr std::string_view LANE = "${options.lane}";\n`
    + `inline constexpr std::string_view MANIFEST_SHA256 = "${pinned.sha256}";\n`
    + table('WIDGETS', widgets) + table('PRIVATE_SOURCES', privateSources)
    + `inline constexpr std::string_view LUA_RULES_ADAPTER(${literal(adapted)}, ${Buffer.byteLength(adapted)});\n`
    + '} // namespace bundled_presentation_data\n');
  return {
    header,
    receipt: {
      schemaVersion: 1, kind: 'immutable-native-presentation-sources', lane: options.lane,
      manifestSha256: pinned.sha256, inputs, excluded,
      widgetCount: widgets.length, privateIncludeCount: 4, privateShaderCount: 4,
      adapterSourceSha256: adapter.sha256, adaptedSourceSha256: sha(adapted),
      adapterTransformation: 'First exact recursive Include becomes local helper = ...; all other adapter bytes preserved.',
      headerBytes: header.length, headerSha256: sha(header),
      originalArchivesModified: false, runtimeFilesystemSourceSelection: false,
    },
  };
}
