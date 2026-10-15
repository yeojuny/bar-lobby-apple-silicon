// SPDX-FileCopyrightText: 2026 The BAR Lobby Authors
//
// SPDX-License-Identifier: MIT

import type { ChildProcess } from "node:child_process";
import { randomUUID } from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";

// Shared by writers in this Electron main process only, not by other processes.
// Keys are physical assets directories, never engine versions or Rapid aliases.
const writerTails = new Map<string, Promise<void>>();

/** Non-reentrant: wrap the actual writer, not a caller that invokes other writers. */
export async function withContentWrite<T>(assetsDirectory: string, write: (canonicalAssetsDirectory: string) => T | Promise<T>): Promise<T> {
    const assetsPath = path.resolve(assetsDirectory);
    await fs.mkdir(assetsPath, { recursive: true });
    const canonicalAssetsPath = await fs.realpath(assetsPath);
    const previous = writerTails.get(canonicalAssetsPath) ?? Promise.resolve();
    let release!: () => void;
    const completed = new Promise<void>((resolve) => {
        release = resolve;
    });
    writerTails.set(canonicalAssetsPath, completed);

    await previous;
    try {
        return await write(canonicalAssetsPath);
    } finally {
        release();
        if (writerTails.get(canonicalAssetsPath) === completed) {
            writerTails.delete(canonicalAssetsPath);
        }
    }
}

/** An error can precede close; never admit another writer while the child lives. */
export function waitForContentWriterClose(child: ChildProcess): Promise<{ code: number | null; signal: NodeJS.Signals | null }> {
    return new Promise((resolve, reject) => {
        let processError: Error | undefined;
        const onError = (error: Error) => {
            processError ??= error;
        };
        child.on("error", onError);
        child.once("close", (code: number | null, signal: NodeJS.Signals | null) => {
            child.removeListener("error", onError);
            if (processError) {
                reject(processError);
            } else {
                resolve({ code, signal });
            }
        });
    });
}

/** Fetch/decode outside this operation; only publication owns the writer slot. */
export async function publishContentMetadata(assetsDirectory: string, metadataPath: string, contents: string | Uint8Array): Promise<void> {
    await withContentWrite(assetsDirectory, async () => {
        await fs.mkdir(path.dirname(metadataPath), { recursive: true });
        const temporaryPath = `${metadataPath}.${randomUUID()}.tmp`;
        try {
            await fs.writeFile(temporaryPath, contents, { flag: "wx" });
            await fs.rename(temporaryPath, metadataPath);
        } finally {
            await fs.rm(temporaryPath, { force: true });
        }
    });
}
