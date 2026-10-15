#!/usr/bin/env node

import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const toolDirectory = dirname(fileURLToPath(import.meta.url));
const workspaceRoot = resolve(toolDirectory, "..");
const defaultOverlayRoot = join(
    workspaceRoot,
    "sources/bar-lobby/bundled-assets/macos-luaui-overlays",
);
const overlayRoot = resolve(process.argv[2] || defaultOverlayRoot);
const contractPath = join(overlayRoot, "accepted-contract.json");
const errors = [];

function readJson(path, label) {
    try {
        return JSON.parse(readFileSync(path, "utf8"));
    } catch (error) {
        errors.push(`${label} is unreadable: ${error.message}`);
        return null;
    }
}

function normalizePath(path) {
    return path.split(sep).join("/");
}

function collectFiles(root, current = root, output = []) {
    if (!existsSync(current)) return output;
    for (const entry of readdirSync(current, { withFileTypes: true })) {
        if (entry.name === ".DS_Store") continue;
        const absolutePath = join(current, entry.name);
        if (entry.isDirectory()) {
            collectFiles(root, absolutePath, output);
        } else if (entry.isFile()) {
            output.push(normalizePath(relative(root, absolutePath)));
        }
    }
    return output;
}

if (!existsSync(contractPath)) {
    errors.push(`accepted contract is missing: ${contractPath}`);
}

const contract = existsSync(contractPath) ? readJson(contractPath, "accepted contract") : null;

if (contract && contract.schemaVersion !== 1) {
    errors.push(`unsupported accepted contract schema: ${contract.schemaVersion}`);
}

for (const lane of contract?.lanes || []) {
    const laneRoot = join(overlayRoot, lane);
    const manifestPath = join(laneRoot, "manifest.json");
    const manifest = existsSync(manifestPath) ? readJson(manifestPath, `${lane} manifest`) : null;

    if (!existsSync(manifestPath)) {
        errors.push(`${lane} manifest is missing: ${manifestPath}`);
        continue;
    }
    if (!manifest) continue;
    if (manifest.schemaVersion !== 1) {
        errors.push(`${lane} has unsupported manifest schema: ${manifest.schemaVersion}`);
    }
    if (manifest.lane !== lane) {
        errors.push(`${lane} manifest declares lane ${manifest.lane}`);
    }
    if (!Array.isArray(manifest.files)) {
        errors.push(`${lane} manifest files must be an array`);
        continue;
    }

    const listedFiles = manifest.files.map(normalizePath);
    const listedSet = new Set(listedFiles);
    if (listedSet.size !== listedFiles.length) {
        errors.push(`${lane} manifest contains duplicate file entries`);
    }

    for (const listedFile of listedFiles) {
        const absolutePath = join(laneRoot, listedFile);
        if (!existsSync(absolutePath) || !statSync(absolutePath).isFile()) {
            errors.push(`${lane} manifest entry is missing on disk: ${listedFile}`);
        }
    }

    const diskFiles = collectFiles(laneRoot).filter((path) => path !== "manifest.json");
    for (const diskFile of diskFiles) {
        if (!listedSet.has(diskFile)) {
            errors.push(`${lane} contains an unmanifested overlay file: ${diskFile}`);
        }
    }

    for (const delegate of contract.protectedDelegates || []) {
        const relativePath = normalizePath(delegate.path);
        const absolutePath = join(laneRoot, relativePath);
        if (!listedSet.has(relativePath)) {
            errors.push(`${lane} removed protected delegate from manifest: ${relativePath}`);
            continue;
        }
        if (!existsSync(absolutePath)) continue;

        const size = statSync(absolutePath).size;
        if (size > delegate.maxBytes) {
            errors.push(
                `${lane} protected delegate looks like a frozen full copy: ${relativePath} (${size} > ${delegate.maxBytes} bytes)`,
            );
        }

        const source = readFileSync(absolutePath, "utf8");
        for (const anchor of delegate.mustContain || []) {
            if (!source.includes(anchor)) {
                errors.push(`${lane} protected delegate lost required anchor ${JSON.stringify(anchor)}: ${relativePath}`);
            }
        }
    }

    for (const forbidden of contract.forbiddenFrozenWidgets || []) {
        const relativePath = normalizePath(forbidden);
        if (listedSet.has(relativePath) || existsSync(join(laneRoot, relativePath))) {
            errors.push(`${lane} restored forbidden frozen UI copy: ${relativePath}`);
        }
    }

    if (lane === "bar-chobby") {
        for (const listedFile of listedFiles) {
            for (const prefix of contract.barChobbyForbiddenPrefixes || []) {
                if (listedFile.startsWith(prefix)) {
                    errors.push(`bar-chobby synced-content purity violation: ${listedFile}`);
                }
            }
        }
    }
}

if (errors.length > 0) {
    process.stderr.write("macOS LuaUI contract FAILED\n");
    for (const error of errors) process.stderr.write(`- ${error}\n`);
    process.exit(1);
}

process.stdout.write(
    `macOS LuaUI contract OK: ${contract.lanes.length} lanes, ${contract.protectedDelegates.length} protected delegates\n`,
);
