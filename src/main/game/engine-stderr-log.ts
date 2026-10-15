// SPDX-License-Identifier: MIT
import { closeSync, mkdirSync, openSync, renameSync, writeFileSync, writeSync } from "node:fs";
import path from "node:path";
import { randomUUID } from "node:crypto";

// Keep driver output available even after the human-readable lobby log fills.
// Files are bounded per engine run; older run evidence is not pruned here.
const DEFAULT_FILE_BYTES = 2 * 1024 * 1024;
const DEFAULT_FAULT_BYTES = 64 * 1024;
const CONTEXT_BYTES = 16 * 1024;
const GPU_FAULT = /VK_ERROR_DEVICE_LOST|GPU.{0,40}(?:Address Fault|page fault|restart)|MTLCommandBufferError|Caused GPU|device lost/i;

export function createEngineStderrLog(
    directory: string,
    metadata: Record<string, unknown>,
    warn: (text: string) => void,
    limits = { fileBytes: DEFAULT_FILE_BYTES, faultBytes: DEFAULT_FAULT_BYTES }
) {
    const stem = path.join(directory, `engine-${Date.now()}-${process.pid}-${randomUUID().slice(0, 8)}`);
    const paths = { current: `${stem}.stderr.log`, previous: `${stem}.stderr.previous.log`, fault: `${stem}.first-gpu-fault.log`, metadata: `${stem}.json` };
    const createdAt = new Date().toISOString();
    let fd: number | undefined;
    let faultFD: number | undefined;
    let currentBytes = 0;
    let totalBytes = 0;
    let faultBytes = 0;
    let rotations = 0;
    let faultCaptured = false;
    let closed = false;
    let failed = false;
    let context = Buffer.alloc(0);

    function closeDescriptors() {
        for (const descriptor of [fd, faultFD]) {
            if (descriptor !== undefined) {
                try { closeSync(descriptor); } catch { /* Report the original I/O failure. */ }
            }
        }
        fd = faultFD = undefined;
    }

    function fail(error: unknown) {
        if (!failed) warn(`Engine stderr recording failed: ${error instanceof Error ? error.message : String(error)}. Lobby mirroring remains active.`);
        failed = true;
        closeDescriptors();
    }

    function writeAll(descriptor: number, buffer: Buffer) {
        let offset = 0;
        while (offset < buffer.length) {
            const count = writeSync(descriptor, buffer, offset, buffer.length - offset);
            if (count <= 0) throw new Error("No progress writing engine stderr");
            offset += count;
        }
    }

    function writeFault(data: Buffer) {
        if (faultFD === undefined || faultBytes >= limits.faultBytes) return;
        const bounded = data.subarray(0, limits.faultBytes - faultBytes);
        writeAll(faultFD, bounded);
        faultBytes += bounded.length;
        if (faultBytes === limits.faultBytes) {
            closeSync(faultFD);
            faultFD = undefined;
        }
    }

    try {
        if (!Number.isSafeInteger(limits.fileBytes) || limits.fileBytes <= 0 || !Number.isSafeInteger(limits.faultBytes) || limits.faultBytes < 128) throw new Error("Invalid engine stderr file limits");
        mkdirSync(directory, { recursive: true });
        writeFileSync(paths.metadata, JSON.stringify({ ...metadata, createdAt, paths, limits }, null, 2) + "\n", { flag: "wx" });
        fd = openSync(paths.current, "wx");
    } catch (error) {
        fail(error);
    }

    return {
        path: failed ? undefined : paths.current,
        write(data: Buffer) {
            if (failed || closed || data.length === 0) return;
            try {
                // Match across pipe chunks. Preserve the first fault separately
                // so a later error storm cannot overwrite it in the rolling tail.
                const combined = Buffer.concat([context, data]);
                // Fault markers are ASCII. Latin-1 keeps the match index equal
                // to its byte offset even when nearby output contains UTF-8.
                const match = !faultCaptured ? GPU_FAULT.exec(combined.toString("latin1")) : null;
                if (match) {
                    faultCaptured = true;
                    faultFD = openSync(paths.fault, "wx");
                    const before = Math.min(CONTEXT_BYTES, Math.floor((limits.faultBytes - match[0].length) / 2));
                    writeFault(combined.subarray(Math.max(0, match.index - before)));
                    warn(`First GPU fault stderr preserved at ${paths.fault}`);
                } else if (faultCaptured) {
                    writeFault(data);
                }
                context = Buffer.from(combined.subarray(-CONTEXT_BYTES));

                for (let offset = 0; offset < data.length;) {
                    if (currentBytes === limits.fileBytes) {
                        closeSync(fd!);
                        fd = undefined;
                        renameSync(paths.current, paths.previous);
                        fd = openSync(paths.current, "wx");
                        currentBytes = 0;
                        rotations++;
                    }
                    const slice = data.subarray(offset, offset + limits.fileBytes - currentBytes);
                    writeAll(fd!, slice);
                    offset += slice.length;
                    currentBytes += slice.length;
                    totalBytes += slice.length;
                }
            } catch (error) {
                fail(error);
            }
        },
        close() {
            if (closed) return;
            closed = true;
            closeDescriptors();
            if (failed) return;
            try {
                writeFileSync(paths.metadata, JSON.stringify({ ...metadata, createdAt, closedAt: new Date().toISOString(), paths, limits, totalBytes, rotations, faultCaptured, faultBytes }, null, 2) + "\n");
            } catch (error) {
                fail(error);
            }
        },
    };
}
