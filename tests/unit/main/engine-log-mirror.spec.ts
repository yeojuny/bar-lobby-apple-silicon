// SPDX-License-Identifier: MIT
import { describe, expect, it, vi } from "vitest";
import { createEngineLobbyLogMirror } from "@main/game/engine-log-mirror";

function setup() {
    const sink = { info: vi.fn(), error: vi.fn(), warn: vi.fn() };
    return { sink, mirror: createEngineLobbyLogMirror(sink, "/data/infolog.txt") };
}

describe("engine driver diagnostics after startup", () => {
    it("retains a late GPU fault after startup stdout exhausts its line allowance", () => {
        const { sink, mirror } = setup();
        mirror.write(Buffer.from("Loaded gadget\n".repeat(1200)), "info");
        mirror.write(Buffer.from("more startup output\n"), "info");
        const fault = "[mvk-error] Lost VkDevice: Caused GPU Address Fault Error\n";
        mirror.write(Buffer.from(fault), "error");
        expect(sink.info).toHaveBeenCalledTimes(1);
        expect(sink.error).toHaveBeenCalledWith(fault);
        expect(sink.warn).toHaveBeenCalledTimes(1);
    });

    it("bounds repeated driver errors without suppressing stdout shutdown evidence", () => {
        const { sink, mirror } = setup();
        for (let i = 0; i < 1400; i++) mirror.write(Buffer.from("driver diagnostic\n"), "error");
        mirror.write(Buffer.from("[SpringApp::Kill][8]\n"), "info");
        expect(sink.error).toHaveBeenCalledTimes(1200);
        expect(sink.info).toHaveBeenCalledWith("[SpringApp::Kill][8]\n");
        expect(sink.warn).toHaveBeenCalledTimes(1);
        mirror.summarize();
        expect(sink.warn).toHaveBeenLastCalledWith(expect.stringContaining("200 engine stderr chunks"));
    });

    it("bounds each stream by UTF-8 bytes as well as lines", () => {
        const { sink, mirror } = setup();
        const chunk = Buffer.from("오".repeat(4096));
        for (let i = 0; i < 40; i++) {
            mirror.write(chunk, "info");
            mirror.write(chunk, "error");
        }
        for (const output of [sink.info, sink.error]) {
            const bytes = output.mock.calls.reduce((sum, [text]) => sum + Buffer.byteLength(text), 0);
            expect(bytes).toBeLessThanOrEqual(256 * 1024);
            expect(bytes).toBeGreaterThan(240 * 1024);
        }
        expect(sink.warn).toHaveBeenCalledTimes(2);
    });
});
