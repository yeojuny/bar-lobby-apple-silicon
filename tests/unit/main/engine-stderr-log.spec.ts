// SPDX-License-Identifier: MIT
import { afterEach, describe, expect, it, vi } from "vitest";
import { mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import path from "node:path";
import os from "node:os";
import { createEngineStderrLog } from "@main/game/engine-stderr-log";
import { createEngineLobbyLogMirror } from "@main/game/engine-log-mirror";

const directories: string[] = [];
function directory() {
    const result = mkdtempSync(path.join(os.tmpdir(), "bar-driver-log-"));
    directories.push(result);
    return result;
}
afterEach(() => { for (const d of directories.splice(0)) rmSync(d, { recursive: true, force: true }); });

describe("bounded engine driver evidence", () => {
    it("persists a late GPU fault after both lobby allowances are exhausted", () => {
        const d = directory();
        const sink = { info: vi.fn(), error: vi.fn(), warn: vi.fn() };
        const mirror = createEngineLobbyLogMirror(sink, "/data/infolog.txt");
        const recorder = createEngineStderrLog(d, { engineVersion: "test" }, sink.warn);
        for (let i = 0; i < 1300; i++) {
            const line = Buffer.from("startup output\n");
            mirror.write(line, "info"); mirror.write(line, "error"); recorder.write(line);
        }
        const fault = Buffer.from("[mvk-error] Caused GPU Address Fault Error\n");
        mirror.write(fault, "error"); recorder.write(fault);
        expect(sink.error).not.toHaveBeenCalledWith(fault.toString());
        expect(readFileSync(recorder.path!, "utf8")).toContain(fault.toString());
        const saved = readdirSync(d).find(n => n.endsWith(".first-gpu-fault.log"))!;
        expect(readFileSync(path.join(d, saved), "utf8")).toContain(fault.toString());
        recorder.close();
    });

    it("rotates a long stream and bounds both tail files while preserving byte order", () => {
        const d = directory();
        const recorder = createEngineStderrLog(d, {}, vi.fn(), { fileBytes: 256, faultBytes: 128 });
        const input = Buffer.from("한글 stderr 기록\n".repeat(200));
        recorder.write(input);
        recorder.close();
        const files = readdirSync(d);
        const previous = path.join(d, files.find(n => n.endsWith(".stderr.previous.log"))!);
        const current = path.join(d, files.find(n => n.endsWith(".stderr.log"))!);
        const actual = Buffer.concat([readFileSync(previous), readFileSync(current)]);
        expect(actual).toEqual(input.subarray(-actual.length));
        expect(statSync(previous).size).toBeLessThanOrEqual(256);
        expect(statSync(current).size).toBeLessThanOrEqual(256);
    });

    it("recognizes a fault split across chunks and retains it after later rotations", () => {
        const d = directory();
        const recorder = createEngineStderrLog(d, {}, vi.fn(), { fileBytes: 256, faultBytes: 128 });
        recorder.write(Buffer.from("context\nCaused GPU Addr"));
        recorder.write(Buffer.from("ess Fault Error\n"));
        recorder.write(Buffer.from("later storm\n".repeat(1000)));
        recorder.close();
        const fault = path.join(d, readdirSync(d).find(n => n.endsWith(".first-gpu-fault.log"))!);
        expect(readFileSync(fault, "utf8")).toContain("Caused GPU Address Fault Error");
        expect(statSync(fault).size).toBe(128);
    });

    it("reports an unavailable destination once and leaves the caller running", () => {
        const d = directory(); const invalid = path.join(d, "file"); writeFileSync(invalid, "not a directory");
        const warn = vi.fn(); const recorder = createEngineStderrLog(invalid, {}, warn);
        expect(recorder.path).toBeUndefined();
        expect(() => { recorder.write(Buffer.from("anything")); recorder.close(); recorder.close(); }).not.toThrow();
        expect(warn).toHaveBeenCalledTimes(1);
    });

    it("captures a fault near the end of a large UTF-8 chunk without letting startup errors consume the snapshot", () => {
        const d = directory();
        const recorder = createEngineStderrLog(d, {}, vi.fn(), { fileBytes: 256, faultBytes: 128 });
        recorder.write(Buffer.from("[mvk-error] VK_ERROR_FEATURE_NOT_PRESENT: optional feature\n"));
        expect(readdirSync(d).some(n => n.endsWith(".first-gpu-fault.log"))).toBe(false);
        recorder.write(Buffer.from("한글 startup\n".repeat(10000) + "[mvk-error] Caused GPU Address Fault Error\n"));
        recorder.write(Buffer.from("later VK_ERROR_DEVICE_LOST\n".repeat(1000)));
        recorder.close();
        const fault = path.join(d, readdirSync(d).find(n => n.endsWith(".first-gpu-fault.log"))!);
        expect(readFileSync(fault, "utf8")).toContain("[mvk-error] Caused GPU Address Fault Error\n");
        expect(statSync(fault).size).toBe(128);
    });
});
