// SPDX-FileCopyrightText: 2026 The BAR Lobby Authors
// SPDX-License-Identifier: MIT

import fs from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";
import luaparse from "luaparse";

const MIGRATION_VERSION = 1;

// Only change the two display literals. Never evaluate or reserialize the user's
// Lua table: it also contains account details and unrelated preferences.
export function inheritChobbyDisplaySettings(source: string, fullscreen: boolean): string {
    let ast;
    try {
        ast = luaparse.parse(source, { ranges: true, comments: false });
    } catch {
        throw new Error("Cannot safely read Chobby display settings; original file preserved.");
    }
    const statement = ast.body[0];
    if (ast.body.length !== 1 || statement.type !== "ReturnStatement" || statement.arguments.length !== 1 || statement.arguments[0].type !== "TableConstructorExpression") {
        throw new Error("Unsupported Chobby settings layout; original file preserved.");
    }
    const root = statement.arguments[0];
    const keyName = (field: (typeof root.fields)[number]): string => {
        if (field.type === "TableKeyString") return field.key.name;
        if (field.type === "TableKey" && field.key.type === "StringLiteral" && !field.key.raw.includes("\\")) return field.key.raw.slice(1, -1);
        throw new Error("Unsupported Chobby setting key; original file preserved.");
    };
    // IGL_data.lua is widget-handler data. Chobby preferences are inside this
    // widget's table, not at the file's root alongside other widgets.
    const wrappers = root.fields.filter((field) => keyName(field) === "Chili lobby");
    if (wrappers.length > 1 || (wrappers.length === 1 && wrappers[0].value.type !== "TableConstructorExpression")) {
        throw new Error("Ambiguous Chobby widget settings; original file preserved.");
    }
    if (!wrappers.length) {
        if (root.fields.some((field) => field.value.type !== "TableConstructorExpression")) {
            throw new Error("Unsupported Chobby widget settings; original file preserved.");
        }
        const start = root.range![0] + 1;
        const mode = fullscreen ? 3 : 2;
        const insertion = `\n    ["Chili lobby"] = { lobby_fullscreen = ${mode}, game_fullscreen = ${mode} },\n`;
        const next = source.slice(0, start) + insertion + source.slice(start);
        luaparse.parse(next);
        return next;
    }
    const table = wrappers[0].value;
    if (table.type !== "TableConstructorExpression") throw new Error("Unsupported Chobby widget settings; original file preserved.");
    const keys = ["lobby_fullscreen", "game_fullscreen"];
    const edits: { start: number; end: number; value: string }[] = [];
    const missing = new Set(keys);
    const seen = new Set<string>();
    for (const field of table.fields) {
        const key = keyName(field);
        if (!keys.includes(key)) continue;
        if (seen.has(key) || field.value.type !== "NumericLiteral" || !Number.isInteger(field.value.value) || field.value.value < 1 || field.value.value > 6) {
            throw new Error("Ambiguous Chobby display setting; original file preserved.");
        }
        seen.add(key);
        missing.delete(key);
        // The user requested a one-time move of the old borderless default to
        // the launcher's fullscreen mode. Other explicit modes remain intact.
        if (fullscreen && field.value.value === 1) {
            const [start, end] = field.value.range!;
            edits.push({ start, end, value: "3" });
        }
    }
    if (missing.size) {
        const start = table.range![0] + 1;
        edits.push({ start, end: start, value: `\n${[...missing].map((key) => `    ${key} = ${fullscreen ? 3 : 2},`).join("\n")}\n` });
    }
    let next = source;
    for (const edit of edits.sort((a, b) => b.start - a.start)) next = next.slice(0, edit.start) + edit.value + next.slice(edit.end);
    // The result must remain a valid Lua table before any write is attempted.
    luaparse.parse(next);
    return next;
}

async function readRegular(file: string): Promise<Buffer | undefined> {
    try {
        const stat = await fs.lstat(file);
        if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 4 * 1024 * 1024) throw new Error("Unsafe Chobby settings file; original preserved.");
        return await fs.readFile(file);
    } catch (error) {
        if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined;
        throw error;
    }
}

async function atomicWrite(file: string, content: string) {
    const temporary = `${file}.${randomUUID()}.tmp`;
    try {
        await fs.writeFile(temporary, content, { flag: "wx", mode: 0o600 });
        await fs.rename(temporary, file);
    } finally {
        await fs.rm(temporary, { force: true });
    }
}

// Chobby imports its own game settings after launcher startup. Change only the
// two AA literals so its saved 4x default cannot undo the requested first run.
export function inheritChobbyAADefaults(source: string): string {
    const ast = luaparse.parse(source, { ranges: true, comments: false });
    const statement = ast.body[0];
    if (ast.body.length !== 1 || statement.type !== "ReturnStatement" || statement.arguments.length !== 1 || statement.arguments[0].type !== "TableConstructorExpression") {
        throw new Error("Unsupported Chobby settings layout; original file preserved.");
    }
    const root = statement.arguments[0];
    type Table = typeof root;
    const range = (node: object): [number, number] => (node as { range: [number, number] }).range;
    const keyName = (field: Table["fields"][number]): string => {
        if (field.type === "TableKeyString") return field.key.name;
        if (field.type === "TableKey" && field.key.type === "StringLiteral" && !field.key.raw.includes("\\")) return field.key.raw.slice(1, -1);
        throw new Error("Unsupported Chobby setting key; original file preserved.");
    };
    const child = (table: Table, key: string): Table | undefined => {
        const fields = table.fields.filter((field) => keyName(field) === key);
        if (fields.length > 1 || (fields.length === 1 && fields[0].value.type !== "TableConstructorExpression")) {
            throw new Error("Ambiguous Chobby settings; original file preserved.");
        }
        return fields[0]?.value as Table | undefined;
    };
    const lobby = child(root, "Chili lobby");
    const game = lobby && child(lobby, "game_settings");
    const values = new Map([["MSAA", 0], ["MSAALevel", -1]]);
    const edits: { start: number; end: number; value: string }[] = [];
    if (game) {
        const seen = new Set<string>();
        for (const field of game.fields) {
            const key = keyName(field);
            if (!values.has(key)) continue;
            const literal = field.value.type === "NumericLiteral" ? field.value : field.value.type === "UnaryExpression" && field.value.operator === "-" && field.value.argument.type === "NumericLiteral" ? field.value.argument : undefined;
            if (seen.has(key) || !literal || !Number.isInteger(literal.value)) {
                throw new Error("Ambiguous Chobby AA setting; original file preserved.");
            }
            seen.add(key);
            const [start, end] = range(field.value);
            edits.push({ start, end, value: String(values.get(key)) });
        }
        const missing = [...values].filter(([key]) => !seen.has(key));
        if (missing.length) edits.push({ start: range(game)[0] + 1, end: range(game)[0] + 1, value: `\n${missing.map(([key, value]) => `    ${key} = ${value},`).join("\n")}\n` });
    } else {
        const target = lobby ?? root;
        const settings = "game_settings = { MSAA = 0, MSAALevel = -1 },";
        edits.push({ start: range(target)[0] + 1, end: range(target)[0] + 1, value: `\n    ${lobby ? settings : `["Chili lobby"] = { ${settings} },`}\n` });
    }
    let next = source;
    for (const edit of edits.sort((a, b) => b.start - a.start)) next = next.slice(0, edit.start) + edit.value + next.slice(edit.end);
    luaparse.parse(next);
    return next;
}

export async function prepareChobbyAADefaults(writeDataPath: string): Promise<void> {
    const markerPath = path.join(writeDataPath, "bar-macos-aa-1.0.2.json");
    const marker = await readRegular(markerPath);
    if (marker) {
        if (JSON.parse(marker.toString("utf8")).version === 1) return;
        throw new Error("Unknown Chobby AA migration state; settings preserved.");
    }
    const configPath = path.join(writeDataPath, "LuaMenu", "Config", "IGL_data.lua");
    const original = await readRegular(configPath);
    const source = original ? new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(original) : "return {}\n";
    const next = inheritChobbyAADefaults(source);
    await fs.mkdir(path.dirname(configPath), { recursive: true });
    const current = await readRegular(configPath);
    if (original ? !current?.equals(original) : current !== undefined) throw new Error("Chobby settings changed during launch; retry after the other writer stops.");
    if (original && next !== source) {
        const backupPath = `${configPath}.before-bar-aa-1.0.2`;
        const backup = await readRegular(backupPath);
        if (backup && !backup.equals(original)) throw new Error("Existing Chobby AA rollback differs; original settings preserved.");
        if (!backup) await fs.writeFile(backupPath, original, { flag: "wx", mode: 0o600 });
    }
    if (!original || next !== source) await atomicWrite(configPath, next);
    await atomicWrite(markerPath, `${JSON.stringify({ version: 1 })}\n`);
}

export async function prepareChobbyDisplaySettings(writeDataPath: string, fullscreen: boolean): Promise<void> {
    const markerPath = path.join(writeDataPath, "bar-macos-chobby-display.json");
    const marker = await readRegular(markerPath);
    if (marker) {
        try {
            if (JSON.parse(marker.toString("utf8")).version === MIGRATION_VERSION) return;
        } catch {
            /* Preserve an unknown marker instead of repeating a migration. */
        }
        throw new Error("Unknown Chobby display migration state; settings preserved.");
    }
    const configPath = path.join(writeDataPath, "LuaMenu", "Config", "IGL_data.lua");
    const original = await readRegular(configPath);
    let source: string;
    try {
        source = original ? new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(original) : "return {}\n";
    } catch {
        throw new Error("Chobby settings are not UTF-8; original file preserved.");
    }
    const next = inheritChobbyDisplaySettings(source, fullscreen);
    await fs.mkdir(path.dirname(configPath), { recursive: true });
    const current = await readRegular(configPath);
    if (original ? !current?.equals(original) : current !== undefined) throw new Error("Chobby settings changed during launch; retry after the other writer stops.");
    if (original && next !== source) {
        const backupPath = `${configPath}.before-bar-display-v1`;
        const backup = await readRegular(backupPath);
        if (backup && !backup.equals(original)) throw new Error("Existing Chobby display rollback differs; original settings preserved.");
        if (!backup) await fs.writeFile(backupPath, original, { flag: "wx", mode: 0o600 });
    }
    if (!original || next !== source) await atomicWrite(configPath, next);
    await fs.mkdir(writeDataPath, { recursive: true });
    // Separate from Chobby's serializer, which intentionally saves known keys
    // only. Never migrate again after a user later selects Borderless/Windowed.
    await atomicWrite(markerPath, `${JSON.stringify({ version: MIGRATION_VERSION })}\n`);
}
