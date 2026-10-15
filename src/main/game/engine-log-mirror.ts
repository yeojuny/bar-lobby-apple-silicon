// SPDX-License-Identifier: MIT

const LIMIT_BYTES = 256 * 1024;
const LIMIT_LINES = 1200;
type OutputLevel = "info" | "error";
type OutputSink = Record<OutputLevel | "warn", (text: string) => void>;

function createStreamState() {
    return {
        mirroredBytes: 0,
        mirroredLines: 0,
        suppressedBytes: 0,
        suppressedLines: 0,
        suppressedChunks: 0,
        limitNoticeLogged: false,
    };
}

export function createEngineLobbyLogMirror(sink: OutputSink, infologPath: string) {
    // Driver diagnostics use stderr and are not necessarily written to infolog.
    // Startup stdout must not consume their independent, bounded allowance.
    const streams = { info: createStreamState(), error: createStreamState() };

    return {
        write(data: Buffer, level: OutputLevel) {
            const state = streams[level];
            const text = data.toString();
            const byteLength = Buffer.byteLength(text);
            const lineCount = Math.max(1, text.split(/\r?\n/).filter(Boolean).length);
            if (state.mirroredBytes + byteLength <= LIMIT_BYTES && state.mirroredLines + lineCount <= LIMIT_LINES) {
                sink[level](text);
                state.mirroredBytes += byteLength;
                state.mirroredLines += lineCount;
                return;
            }
            state.suppressedBytes += byteLength;
            state.suppressedLines += lineCount;
            state.suppressedChunks++;
            if (!state.limitNoticeLogged) {
                state.limitNoticeLogged = true;
                const stream = level === "info" ? "stdout" : "stderr";
                sink.warn(
                    `Engine ${stream} lobby log allowance reached (bytes=${LIMIT_BYTES}, lines=${LIMIT_LINES}). ` +
                        `The other stream has an independent allowance. Engine-owned messages may also be in ${infologPath}; driver stderr is not guaranteed there.`
                );
            }
        },
        summarize() {
            for (const level of ["info", "error"] as const) {
                const state = streams[level];
                if (state.suppressedChunks) {
                    const stream = level === "info" ? "stdout" : "stderr";
                    sink.warn(`Suppressed ${state.suppressedChunks} engine ${stream} chunks from the lobby log (${state.suppressedLines} lines, ${state.suppressedBytes} bytes).`);
                }
            }
        },
    };
}
