// SPDX-FileCopyrightText: 2026 The BAR Lobby Authors
//
// SPDX-License-Identifier: MIT

import { createHash } from "node:crypto";
import { lstatSync, readFileSync, readdirSync, readlinkSync, realpathSync } from "node:fs";
import path from "node:path";

export const REQUIRED_BUNDLED_ASSET_ENTRIES = [
    "runtime",
    "engine",
    "engine-fonts",
    "fonts",
    "chobby-multiplayer-profile.json",
    "macos-luaui-overlays",
    "third-party-notices",
] as const;

type AssetEntry = (typeof REQUIRED_BUNDLED_ASSET_ENTRIES)[number];
type Lane = "bar-chobby" | "bar-lobby";
type EnginePin = { engineDirectory: string; springSha256: string };
export type BundledBaseline = { id: string; lanes: Record<Lane, EnginePin> };

// The external lock is reviewed separately and pinned by its raw-byte SHA-256.
// Entries use hashBundledAssetEntry; springSha256 uses the executable's raw bytes.
// No lock is generated from whichever assets happen to be available at build time.
export type BundledAssetsLock = {
    schemaVersion: 1;
    baselineId: string;
    lanes: Record<Lane, EnginePin>;
    entries: Record<AssetEntry, string>;
};

const sha256 = (bytes: string | Buffer) => createHash("sha256").update(bytes).digest("hex");
const isSha256 = (value: unknown): value is string => typeof value === "string" && /^[a-f0-9]{64}$/.test(value);

function record(value: unknown, label: string): Record<string, unknown> {
    if (value === null || typeof value !== "object" || Array.isArray(value)) throw new Error(`Invalid ${label}`);
    return value as Record<string, unknown>;
}

// Canonical digest: SHA-256(JSON.stringify(rows)), sorted depth-first by filename.
// Each row is [bundle-relative path, kind, mode, file SHA-256 or symlink target].
// Directory rows omit the last value. Timestamps and absolute paths are excluded.
export function hashBundledAssetEntry(assetsPath: string, entry: AssetEntry): string {
    const root = realpathSync(assetsPath);
    const rows: (string | number)[][] = [];
    const walk = (relativePath: string) => {
        const file = path.join(root, relativePath);
        const stat = lstatSync(file);
        const mode = stat.mode & 0o777;
        if (stat.isSymbolicLink()) {
            const target = readlinkSync(file);
            if (path.isAbsolute(target)) throw new Error(`Absolute bundled symlink: ${relativePath}`);
            const resolved = path.relative(root, realpathSync(file));
            const topLevel = resolved.split(path.sep)[0];
            if (!REQUIRED_BUNDLED_ASSET_ENTRIES.some((name) => name === topLevel)) {
                throw new Error(`Bundled symlink escapes pinned entries: ${relativePath}`);
            }
            rows.push([relativePath, "symlink", mode, target]);
        } else if (stat.isDirectory()) {
            rows.push([relativePath, "directory", mode]);
            for (const name of readdirSync(file).sort()) walk(`${relativePath}/${name}`);
        } else if (stat.isFile()) {
            rows.push([relativePath, "file", mode, sha256(readFileSync(file))]);
        } else {
            throw new Error(`Unsupported bundled file type: ${relativePath}`);
        }
    };
    walk(entry);
    return sha256(JSON.stringify(rows));
}

export function createPinnedBundledAssets(env: NodeJS.ProcessEnv, baseline: BundledBaseline) {
    // Capture configuration once so validation and copy paths cannot use different env values.
    const configuredPath = env.BAR_BUNDLED_ASSETS_PATH?.trim();
    const configuredLock = env.BAR_BUNDLED_ASSETS_LOCK_PATH?.trim();
    const lockSha256 = env.BAR_BUNDLED_ASSETS_LOCK_SHA256?.trim();
    const assetsPath = configuredPath ? path.resolve(configuredPath) : undefined;
    const lockPath = configuredLock ? path.resolve(configuredLock) : undefined;
    const extraResources = assetsPath && lockPath
        ? [
              ...REQUIRED_BUNDLED_ASSET_ENTRIES.map((entry) => ({ from: path.join(assetsPath, entry), to: `bundled-assets/${entry}` })),
              { from: lockPath, to: "bundled-assets/release-input-lock.json" },
          ]
        : [];

    return {
        extraResources,
        validate(): { overlayPath: string } {
            if (!assetsPath || !lockPath || !lockSha256) {
                throw new Error("macOS packaging requires BAR_BUNDLED_ASSETS_PATH, BAR_BUNDLED_ASSETS_LOCK_PATH and BAR_BUNDLED_ASSETS_LOCK_SHA256; no implicit baseline is allowed");
            }
            if (!isSha256(lockSha256)) throw new Error("Invalid BAR_BUNDLED_ASSETS_LOCK_SHA256");
            const lockBytes = readFileSync(lockPath);
            if (sha256(lockBytes) !== lockSha256) throw new Error("Bundled asset lock SHA-256 mismatch");
            const lock = record(JSON.parse(lockBytes.toString("utf8")), "bundled asset lock");
            if (lock.schemaVersion !== 1 || lock.baselineId !== baseline.id) throw new Error("Bundled asset lock baseline/schema mismatch");
            const lanes = record(lock.lanes, "engine lane pins");
            for (const lane of ["bar-chobby", "bar-lobby"] as const) {
                const pin = record(lanes[lane], `${lane} pin`);
                const expected = baseline.lanes[lane];
                if (pin.engineDirectory !== expected.engineDirectory || pin.springSha256 !== expected.springSha256) {
                    throw new Error(`Protected ${lane} engine pin mismatch`);
                }
                if (!/^[A-Za-z0-9][A-Za-z0-9._+-]*$/.test(expected.engineDirectory) || !isSha256(expected.springSha256)) {
                    throw new Error(`Invalid protected ${lane} engine identity`);
                }
                const spring = path.join(assetsPath, "engine", expected.engineDirectory, "spring");
                const stat = lstatSync(spring);
                if (!stat.isFile() || !(stat.mode & 0o111) || sha256(readFileSync(spring)) !== expected.springSha256) {
                    throw new Error(`Bundled ${lane} executable identity mismatch`);
                }
            }
            const entries = record(lock.entries, "bundled entry pins");
            if (Object.keys(entries).length !== REQUIRED_BUNDLED_ASSET_ENTRIES.length) throw new Error("Required bundled entry pin set mismatch");
            for (const entry of REQUIRED_BUNDLED_ASSET_ENTRIES) {
                if (!isSha256(entries[entry])) throw new Error(`Missing or invalid bundled entry pin: ${entry}`);
                const stat = lstatSync(path.join(assetsPath, entry));
                const expectedType = entry === "chobby-multiplayer-profile.json" ? stat.isFile() : stat.isDirectory();
                if (!expectedType) throw new Error(`Required bundled entry has wrong type: ${entry}`);
                if (hashBundledAssetEntry(assetsPath, entry) !== entries[entry]) throw new Error(`Bundled entry SHA-256 mismatch: ${entry}`);
            }
            const profile = record(JSON.parse(readFileSync(path.join(assetsPath, "chobby-multiplayer-profile.json"), "utf8")), "Chobby profile");
            if (profile.engineVersion !== baseline.lanes["bar-chobby"].engineDirectory || profile.gameRapidAlias !== "byar:test") {
                throw new Error("Bundled Chobby profile does not match the protected engine/content channel");
            }
            return { overlayPath: path.join(assetsPath, "macos-luaui-overlays") };
        },
    };
}
