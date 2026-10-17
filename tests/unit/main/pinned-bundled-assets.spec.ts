// SPDX-FileCopyrightText: 2026 The BAR Lobby Authors
// SPDX-License-Identifier: MIT

import { createHash } from "node:crypto";
import { chmodSync, mkdirSync, mkdtempSync, readdirSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import * as fileMatcher from "app-builder-lib/out/fileMatcher";
import type { FileMatcher } from "app-builder-lib/out/fileMatcher";
import { doMergeConfigs } from "app-builder-lib/out/util/config/config";
import { afterEach, describe, expect, it, vi } from "vitest";
import { createPinnedBundledAssets, hashBundledAssetEntry, REQUIRED_BUNDLED_ASSET_ENTRIES } from "../../../packaging/pinned-bundled-assets";
import type { BundledAssetsLock, BundledBaseline } from "../../../packaging/pinned-bundled-assets";

const roots: string[] = [];
const sha = (value: string) => createHash("sha256").update(value).digest("hex");

function fixture() {
    const root = mkdtempSync(path.join(tmpdir(), "bar-release-inputs-"));
    roots.push(root);
    const assets = path.join(root, "assets");
    const lockPath = path.join(root, "input-lock.json");
    const put = (name: string, contents: string) => {
        const file = path.join(assets, name);
        mkdirSync(path.dirname(file), { recursive: true });
        writeFileSync(file, contents);
        return file;
    };
    const baseline: BundledBaseline = {
        id: "cpu-fixture-protected",
        lanes: {
            "bar-chobby": { engineDirectory: "chobby-current", springSha256: sha("chobby-engine") },
            "bar-lobby": { engineDirectory: "lobby-current", springSha256: sha("lobby-engine") },
        },
    };
    chmodSync(put("engine/chobby-current/spring", "chobby-engine"), 0o755);
    chmodSync(put("engine/lobby-current/spring", "lobby-engine"), 0o755);
    put("runtime/lib/runtime.dylib", "shared-runtime");
    put("engine-fonts/font.otf", "engine-font");
    put("fonts/font.otf", "lobby-font");
    put("macos-luaui-overlays/bar-chobby/manifest.json", "{}");
    put("macos-luaui-overlays/bar-lobby/manifest.json", "{}");
    put("third-party-notices/README.md", "Third-party notices and corresponding-source sidecar reference");
    put("third-party-notices/source-map.json", "{}");
    put("third-party-notices/licenses/example/LICENSE", "Retained upstream notice");
    put("chobby-multiplayer-profile.json", JSON.stringify({ engineVersion: "chobby-current", gameRapidAlias: "byar:test" }));
    const lock: BundledAssetsLock = {
        schemaVersion: 1,
        baselineId: baseline.id,
        lanes: structuredClone(baseline.lanes),
        entries: Object.fromEntries(REQUIRED_BUNDLED_ASSET_ENTRIES.map((entry) => [entry, hashBundledAssetEntry(assets, entry)])) as BundledAssetsLock["entries"],
    };
    const pin = () => {
        const bytes = JSON.stringify(lock);
        writeFileSync(lockPath, bytes);
        return { BAR_BUNDLED_ASSETS_PATH: assets, BAR_BUNDLED_ASSETS_LOCK_PATH: lockPath, BAR_BUNDLED_ASSETS_LOCK_SHA256: sha(bytes) };
    };
    return { root, assets, baseline, lock, lockPath, put, pin };
}

afterEach(() => {
    for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
    vi.unstubAllEnvs();
});

describe("explicit pinned macOS packaging inputs", () => {
    it("requires all configuration, including a separately supplied lock digest", () => {
        const f = fixture();
        const env = f.pin();
        for (const key of Object.keys(env)) {
            expect(() => createPinnedBundledAssets({ ...env, [key]: undefined }, f.baseline).validate()).toThrow(/requires BAR_BUNDLED/);
        }
        expect(() => createPinnedBundledAssets({}, f.baseline).validate()).toThrow(/no implicit baseline/);
    });

    it("validates every required tree and copies overlays from the same explicit root", () => {
        const f = fixture();
        const input = createPinnedBundledAssets(f.pin(), f.baseline);
        expect(input.validate().overlayPath).toBe(path.join(f.assets, "macos-luaui-overlays"));
        expect(input.extraResources).toHaveLength(REQUIRED_BUNDLED_ASSET_ENTRIES.length + 1);
        expect(input.extraResources).toContainEqual({ from: f.lockPath, to: "bundled-assets/release-input-lock.json" });
        for (const entry of REQUIRED_BUNDLED_ASSET_ENTRIES) {
            expect(input.extraResources).toContainEqual({ from: path.join(f.assets, entry), to: `bundled-assets/${entry}` });
        }
    });

    it.each(REQUIRED_BUNDLED_ASSET_ENTRIES)("rejects a missing required %s instead of filtering it", (entry) => {
        const f = fixture();
        const input = createPinnedBundledAssets(f.pin(), f.baseline);
        rmSync(path.join(f.assets, entry), { recursive: true });
        expect(() => input.validate()).toThrow();
    });

    it("rejects a changed lock, wrong baseline and wrong engine pin", () => {
        const f = fixture();
        const oldEnv = f.pin();
        f.lock.baselineId = "historical-root-app";
        writeFileSync(f.lockPath, JSON.stringify(f.lock));
        expect(() => createPinnedBundledAssets(oldEnv, f.baseline).validate()).toThrow(/lock SHA-256 mismatch/);
        expect(() => createPinnedBundledAssets(f.pin(), f.baseline).validate()).toThrow(/baseline\/schema mismatch/);
        f.lock.baselineId = f.baseline.id;
        f.lock.lanes["bar-chobby"].springSha256 = sha("other-engine");
        expect(() => createPinnedBundledAssets(f.pin(), f.baseline).validate()).toThrow(/engine pin mismatch/);
    });

    it("preserves a complete git-describe sync identity including its branch", () => {
        const f = fixture();
        const version = "2026.09.01-24-g01efdf4 master";
        f.baseline.lanes["bar-lobby"].engineDirectory = version;
        f.lock.lanes["bar-lobby"].engineDirectory = version;
        chmodSync(f.put(`engine/${version}/spring`, "lobby-engine"), 0o755);
        f.lock.entries.engine = hashBundledAssetEntry(f.assets, "engine");
        expect(() => createPinnedBundledAssets(f.pin(), f.baseline).validate()).not.toThrow();
        f.put(`engine/${version}/spring`, "wrong-engine");
        expect(() => createPinnedBundledAssets(f.pin(), f.baseline).validate()).toThrow(/executable identity mismatch/);
    });

    it.each(["../engine", "engine/master", "engine\\master", "engine  master", "engine master/next", "engine\nmaster", "engine "])("rejects an unsafe engine directory %j", (version) => {
        const f = fixture();
        f.baseline.lanes["bar-lobby"].engineDirectory = version;
        f.lock.lanes["bar-lobby"].engineDirectory = version;
        expect(() => createPinnedBundledAssets(f.pin(), f.baseline).validate()).toThrow(/Invalid protected bar-lobby engine identity/);
    });

    it.each(["runtime/lib/runtime.dylib", "macos-luaui-overlays/bar-chobby/manifest.json", "engine/chobby-current/spring", "third-party-notices/source-map.json", "third-party-notices/licenses/example/LICENSE"])("rejects altered bytes in %s", (name) => {
        const f = fixture();
        const input = createPinnedBundledAssets(f.pin(), f.baseline);
        f.put(name, "changed-input");
        expect(() => input.validate()).toThrow(/mismatch/);
    });

    it("rejects a non-executable spring and a profile for another engine", () => {
        const f = fixture();
        const input = createPinnedBundledAssets(f.pin(), f.baseline);
        chmodSync(path.join(f.assets, "engine/chobby-current/spring"), 0o644);
        expect(() => input.validate()).toThrow(/executable identity mismatch/);
        chmodSync(path.join(f.assets, "engine/chobby-current/spring"), 0o755);
        f.put("chobby-multiplayer-profile.json", JSON.stringify({ engineVersion: "old-engine", gameRapidAlias: "byar:test" }));
        f.lock.entries["chobby-multiplayer-profile.json"] = hashBundledAssetEntry(f.assets, "chobby-multiplayer-profile.json");
        expect(() => createPinnedBundledAssets(f.pin(), f.baseline).validate()).toThrow(/Chobby profile/);
    });

    it("rejects omitted entry hashes and non-directory required trees", () => {
        const f = fixture();
        delete (f.lock.entries as Partial<BundledAssetsLock["entries"]>).fonts;
        expect(() => createPinnedBundledAssets(f.pin(), f.baseline).validate()).toThrow(/entry pin set/);
        f.lock.entries.fonts = hashBundledAssetEntry(f.assets, "fonts");
        rmSync(path.join(f.assets, "fonts"), { recursive: true });
        f.put("fonts", "wrong-type");
        expect(() => createPinnedBundledAssets(f.pin(), f.baseline).validate()).toThrow(/wrong type/);
    });

    it("pins internal symlinks and rejects escaping or dangling links", () => {
        const f = fixture();
        const link = path.join(f.assets, "runtime/lib/alias.dylib");
        symlinkSync("runtime.dylib", link);
        f.lock.entries.runtime = hashBundledAssetEntry(f.assets, "runtime");
        expect(() => createPinnedBundledAssets(f.pin(), f.baseline).validate()).not.toThrow();
        rmSync(link);
        writeFileSync(path.join(f.root, "external.dylib"), "external");
        symlinkSync("../../../external.dylib", link);
        expect(() => hashBundledAssetEntry(f.assets, "runtime")).toThrow(/escapes pinned entries/);
        rmSync(link);
        symlinkSync("missing.dylib", link);
        expect(() => hashBundledAssetEntry(f.assets, "runtime")).toThrow();
    });

    it("pins file modes and uses a stable canonical entry digest", () => {
        const f = fixture();
        f.put("fonts/font.otf", "lobby-font");
        chmodSync(path.join(f.assets, "fonts"), 0o755);
        chmodSync(path.join(f.assets, "fonts/font.otf"), 0o644);
        expect(hashBundledAssetEntry(f.assets, "fonts")).toBe(sha(JSON.stringify([
            ["fonts", "directory", 0o755],
            ["fonts/font.otf", "file", 0o644, sha("lobby-font")],
        ])));
        const before = hashBundledAssetEntry(f.assets, "fonts");
        chmodSync(path.join(f.assets, "fonts/font.otf"), 0o600);
        expect(hashBundledAssetEntry(f.assets, "fonts")).not.toBe(before);
    });

    it("gates macOS beforePack without requiring macOS assets for other platforms", async () => {
        for (const key of ["BAR_BUNDLED_ASSETS_PATH", "BAR_BUNDLED_ASSETS_LOCK_PATH", "BAR_BUNDLED_ASSETS_LOCK_SHA256"]) vi.stubEnv(key, "");
        const { default: config } = await import("../../../electron-builder");
        const hook = config.beforePack;
        if (typeof hook !== "function") throw Error("Missing packaging guard");
        expect(() => hook({ electronPlatformName: "darwin" } as never)).toThrow(/requires BAR_BUNDLED/);
        expect(hook({ electronPlatformName: "linux" } as never)).toBeUndefined();
        expect(hook({ electronPlatformName: "win32" } as never)).toBeUndefined();
    });

    it("uses normalized packaging matchers to exclude local output and keep only the ARM64 Mac archive utility", async () => {
        const { default: config } = await import("../../../electron-builder");
        const root = path.resolve(".");
        // The installed runtime exports these @internal helpers, whose types
        // app-builder-lib omits from its published declaration file.
        const builderMatchers = fileMatcher as unknown as {
            getMainFileMatchers: (...args: unknown[]) => FileMatcher[];
            getNodeModuleFileMatcher: (...args: unknown[]) => FileMatcher;
        };
        const normalized = doMergeConfigs([
            {
                ...config,
                files: [...(config.files as string[])],
                mac: { ...config.mac, files: [...(config.mac?.files as string[])] },
            },
            { directories: { output: "release-output" } },
        ]);
        // The real normalizer turns the global strings into a FileSet while
        // platform strings remain a separate matcher. Flattening hides this.
        expect(Array.isArray(normalized.files) && typeof normalized.files[0] === "object").toBe(true);
        const destination = path.join(root, "release-output/app");
        const packager = {
            projectDir: root,
            buildResourcesDir: "buildResources",
            config: normalized,
            isPrepackedAppAsar: false,
            debugLogger: { isEnabled: false },
        };
        const expand = (value: string) => value;
        const stat = { isDirectory: () => false } as never;
        for (const platform of [normalized.mac, normalized.linux, normalized.win]) {
            const matchers = builderMatchers.getMainFileMatchers(
                root, destination, expand, platform, { info: packager }, path.join(root, "release-output"), false
            );
            for (const [index, matcher] of matchers.entries()) {
                expect(matcher.from).toBe(root);
                const filter = matcher.createFilter();
                for (const name of [
                    "out/old.app/Contents/Resources/app.asar", "dist/old.app/Contents/MacOS/BAR", "src/main/main.ts",
                    ".npmrc", "tests/unit/main/private.spec.ts", "tools/private.mjs", "bundled-assets/runtime/private.dylib",
                    "cache/private.bin", ".cache/private.bin", ".vite/build/main.cjs.map",
                    ".vite/renderer/main_window/assets/index.js.map",
                ]) {
                    expect(filter(path.join(root, name), stat), `matcher ${index} must exclude ${name}`).toBe(false);
                }
            }
            for (const name of [
                ".vite/build/main.cjs", ".vite/renderer/main_window/assets/index.js",
                ".vite/renderer/main_window/assets/style.css", ".vite/renderer/main_window/assets/logo.svg",
                ".vite/renderer/main_window/assets/background.png",
            ]) {
                expect(matchers.some((matcher) => matcher.createFilter()(path.join(root, name), stat)), name).toBe(true);
            }
        }
        const mac = builderMatchers.getNodeModuleFileMatcher(root, destination, expand, normalized.mac, packager).createFilter();
        const other = builderMatchers.getNodeModuleFileMatcher(root, destination, expand, normalized.linux, packager).createFilter();
        for (const name of ["index.js", "package.json", "LICENSE.txt", "mac/arm64/7za"]) {
            expect(mac(path.join(root, "node_modules/7zip-bin", name), stat)).toBe(true);
        }
        for (const name of ["mac/x64/7za", "linux/arm64/7za", "win/x64/7za.exe", "7x.sh", "index.d.ts", "mac/arm64/unreviewed-binary"]) {
            const file = path.join(root, "node_modules/7zip-bin", name);
            expect(mac(file, stat)).toBe(false);
            expect(other(file, stat)).toBe(true);
        }
        const directory = { isDirectory: () => true } as never;
        for (const name of ["mac", "mac/arm64"]) {
            expect(mac(path.join(root, "node_modules/7zip-bin", name), directory)).toBe(true);
        }
        const archiveRoot = path.join(root, "node_modules/7zip-bin");
        function archiveFiles(filter?: ReturnType<FileMatcher["createFilter"]>, relative = ""): string[] {
            return readdirSync(path.join(archiveRoot, relative)).flatMap((name) => {
                const entry = path.join(relative, name);
                const file = path.join(archiveRoot, entry);
                const metadata = statSync(file);
                if (filter && !filter(file, metadata)) return [];
                return metadata.isDirectory() ? archiveFiles(filter, entry) : [entry];
            }).sort();
        }
        expect(archiveFiles(mac)).toEqual(["LICENSE.txt", "index.js", "mac/arm64/7za", "package.json"]);
        expect(archiveFiles(other)).toEqual(archiveFiles());
    });
});
