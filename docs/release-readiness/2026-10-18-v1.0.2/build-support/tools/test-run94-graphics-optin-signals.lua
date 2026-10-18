-- CPU-only checks for the source overlays. Run with Lua 5.4; no engine or GL.
local root = arg[1] or "."
local overlay = root .. "/sources/bar-lobby/bundled-assets/macos-luaui-overlays/"
local lanes = {"bar-lobby", "bar-chobby"}
local paths = {
    diagnostic = "LuaUI/Widgets/gui_runtime_graphics_diagnostic.lua",
    options = "LuaUI/Widgets/gui_options.lua",
    instanceVBO = "LuaUI/Include/InstanceVBOTable_Local.lua",
    font = "LuaUI/Widgets/gui_fonthandler.lua",
    mapEdge = "LuaUI/Widgets/map_edge_extension2.lua",
}
local counts = {diagnostic = 0, options = 0, instanceVBO = 0, font = 0, mapEdge = 0, laneIdentity = 0}
local sources = {}
local function read(path)
    local file = assert(io.open(path, "rb"))
    local contents = file:read("*a")
    file:close()
    return contents
end
local function check(group, name, fn)
    local ok, message = pcall(fn)
    if not ok then error("FAIL " .. group .. " / " .. name .. ": " .. tostring(message), 0) end
    counts[group] = counts[group] + 1
end
local function replace(text, old, new)
    local first, last = assert(text:find(old, 1, true))
    return text:sub(1, first - 1) .. new .. text:sub(last + 1)
end
local function environment()
    local env = setmetatable({WG = {}, widget = {}, gl = {}, Platform = {}}, {__index = _G})
    env._G = env
    -- Emulate the engine's implicit archive environment under the CPU interpreter.
    env.load = function(text, name, mode, target)
        return load(text, name, mode or "t", target or env)
    end
    return env
end
local function run(source, env)
    return assert(load(source, "@source-overlay-cpu", "t", env))()
end
for _, lane in ipairs(lanes) do
    sources[lane] = {}
    for group, relative in pairs(paths) do
        sources[lane][group] = read(overlay .. lane .. "/" .. relative)
    end
end
for group in pairs(paths) do
    check("laneIdentity", group, function()
        assert(sources[lanes[1]][group] == sources[lanes[2]][group])
    end)
end

local function diagnosticEnv(config, timers)
    local env = environment()
    local observed = {queries = 0, writes = {}, logs = {}, removed = 0, draws = 0}
    local target = {whInfo = {name = "CPU fixture"}}
    local original = function() observed.draws = observed.draws + 1; return "draw-ok" end
    target.DrawWorld = original
    env.widgetHandler = {
        DrawWorldList = {target},
        RemoveWidget = function(_, widget)
            assert(widget == env.widget)
            observed.removed = observed.removed + 1
        end,
    }
    env.Spring = {
        Echo = function(line) observed.logs[#observed.logs + 1] = line end,
        GetConfigInt = function(key, default)
            if config[key] == nil then return default end
            return config[key]
        end,
        SetConfigInt = function(key, value)
            observed.writes[#observed.writes + 1] = {key, value}
            config[key] = value
        end,
        GetConfigFloat = function(_, default) return default end,
        GetGameFrame = function() return 1 end,
        GetViewGeometry = function() return 1512, 950, 0, 0 end,
        GetActiveCommand = function() return nil, 42 end,
        GetMouseState = function() return 0, 0, false end,
        GetDrawFrame = function() return 1 end,
    }
    if timers ~= false then
        env.Spring.GetTimer = function() return 0 end
        env.Spring.DiffTimers = function() return 0 end
    end
    env.gl.GetNumber = function()
        observed.queries = observed.queries + 1
        return 0, 0, 0, 0
    end
    return env, observed, target, original
end
local function exerciseDiagnostic(widget)
    widget:ViewResize()
    widget:Update()
    widget:SelectionChanged({1})
    widget:DrawGenesis()
    widget:DrawWorld()
    widget:DrawScreenEffects()
    widget:DrawScreen()
end

local needle = "\t\t\tif not shown[option] then\n\t\t\t\tresult[#result + 1] = option\n\t\t\tend"
local fixed = "\t\t\tif not shown[option] then\n\t\t\t\tshown[option] = true\n\t\t\t\tresult[#result + 1] = option\n\t\t\tend"
local function optionsFixture(block)
    return [[local isPotatoGpu = true
if false then
elseif Platform.glHaveNVidia then
    isPotatoGpu = true
end
local samples = {"x4", "x8"}
widget.samples, widget.potato = samples, isPotatoGpu
function widget.Search(options)
    local result, shown = {}, {}
    for _, option in ipairs(options) do
]] .. block .. [[

    end
    for _, option in ipairs(options) do
        if not shown[option] then
            shown[option] = true
            result[#result + 1] = option
        end
    end
    return result
end
function widget:Initialize() self.archiveInitialized = true end
return "archive-ok"
]]
end
-- Current official recursive search shape, with shared parent and spacer rows.
local recursiveSearch = [[
		local shown = {}
		local result = {}
		local function show(option)
			if not shown[option] then
				shown[option] = true
				if option.parentOption then
					show(option.parentOption)
				end
				result[#result + 1] = option
				if option.spacer then
					result[#result + 1] = option.spacer
				end
			end
		end
]]
local function recursiveFixture(block)
    return 'local samples = {"x4", "x8"}\nwidget.samples = samples\nfunction widget.Search(options)\n'
        .. block .. '\nfor _, option in ipairs(options) do show(option) end\nreturn result\nend\nreturn "archive-ok"'
end

local function optionsEnv(archive, msaa)
    local env = environment()
    local observed = {writes = {}, logs = {}, commands = {}}
    env.Platform = {glHaveZinkMoltenVK = true}
    local config = {MSAALevel = msaa or 4, BARMacOSCloudsRestoreRun91 = 1}
    env.Spring = {
        Echo = function(line) observed.logs[#observed.logs + 1] = line end,
        GetConfigInt = function(key, default)
            if config[key] == nil then return default end
            return config[key]
        end,
        SetConfigInt = function(key, value)
            observed.writes[#observed.writes + 1] = {key, value}
            config[key] = value
        end,
        SendCommands = function(command) observed.commands[#observed.commands + 1] = command end,
    }
    env.VFS = {ZIP_ONLY = "zip", LoadFile = function(path, mode)
        assert(path == "LuaUI/Widgets/gui_options.lua" and mode == "zip")
        return archive
    end}
    return env, observed
end

local offset = "local offset = new_usedElements * iTStep"
local upload = "\tiT.instanceVBO:Upload(iT.instanceData, nil, 0, 1, iT.usedElements * iT.instanceStep)"
local recalculate = "\t\tiTusedElements = iT.usedElements -- because during validation of unitIDs during resizing, we can decrease the actual size of the table!"
local instanceFixture = [[local originalApi = gl.InstanceVBOTable
local function resizeInstanceVBOTable(iT)
    local iTStep, i, new_usedElements = 1, 1, 0
]] .. offset .. "\n" .. upload .. [[

end
--[[ from Ivand: ]] .. "]]" .. [[

local function append(iT)
    local iTusedElements, endOffset, iTStep = 0, 0, 1
]] .. recalculate .. [[

end
local api = {fixture = true}
gl.InstanceVBOTable = api
return api
]]
local function instanceEnv(archive, fallbackAvailable)
    local env = environment()
    local baseline = fallbackAvailable ~= false and {sentinel = true} or nil
    local observed = {logs = {}, compiled = nil}
    env.gl.InstanceVBOTable = baseline
    env.Spring = {Echo = function(line) observed.logs[#observed.logs + 1] = line end}
    env.VFS = {ZIP_ONLY = "zip", LoadFile = function(path, mode)
        assert(path == "modules/graphics/instancevbotable.lua" and mode == "zip")
        return archive
    end}
    env.load = function(text, name, mode, target)
        observed.compiled = text
        return load(text, name, mode, target)
    end
    return env, observed, baseline
end

for _, lane in ipairs(lanes) do
    local input = sources[lane]
    for _, scenario in ipairs({
        {name = "missing request", config = {}},
        {name = "zero request", config = {BARGraphicsTraceOnce = 0}},
        {name = "negative request", config = {BARGraphicsTraceOnce = -1}},
        {name = "non-one request", config = {BARGraphicsTraceOnce = 2}},
        {name = "capture alone", config = {BARGraphicsCaptureOnce = 1}},
        {name = "observer alone", config = {BARGraphicsObserverOnce = 1}},
    }) do
        check("diagnostic", lane .. " / " .. scenario.name, function()
            local env, observed, target, original = diagnosticEnv(scenario.config)
            run(input.diagnostic, env)
            assert(env.widget:GetInfo().enabled == false)
            env.widget:Initialize() -- Also covers a stale saved positive widget order.
            exerciseDiagnostic(env.widget)
            env.widget:Shutdown()
            assert(observed.removed == 1 and observed.queries == 0)
            assert(#observed.logs == 0 and #observed.writes == 0)
            assert(target.DrawWorld == original and env.WG.BARGraphicsTraceRequested == false)
        end)
    end
    check("diagnostic", lane .. " / explicit one-run trace", function()
        local config = {BARGraphicsTraceOnce = 1, BARGraphicsCaptureOnce = 0, BARGraphicsObserverOnce = 0}
        local env, observed, target, original = diagnosticEnv(config)
        run(input.diagnostic, env)
        assert(env.widget:GetInfo().enabled == true)
        env.widget:Initialize()
        assert(config.BARGraphicsTraceOnce == 0 and env.WG.BARGraphicsTraceRequested == true)
        assert(#observed.writes == 1 and observed.writes[1][1] == "BARGraphicsTraceOnce")
        exerciseDiagnostic(env.widget)
        assert(observed.removed == 0 and observed.queries > 0)
        assert(target.DrawWorld ~= original and target.DrawWorld() == "draw-ok")
        env.widget:Shutdown()
        assert(target.DrawWorld == original)
        assert(config.BARGraphicsCaptureOnce == 0 and config.BARGraphicsObserverOnce == 0)
        local nextEnv = diagnosticEnv(config)
        run(input.diagnostic, nextEnv)
        assert(nextEnv.widget:GetInfo().enabled == false)
    end)
    check("diagnostic", lane .. " / trace without owner timers", function()
        local env, observed, target, original = diagnosticEnv({BARGraphicsTraceOnce = 1}, false)
        run(input.diagnostic, env)
        env.widget:Initialize()
        exerciseDiagnostic(env.widget)
        assert(observed.queries > 0 and target.DrawWorld == original)
        assert(#observed.writes == 1)
    end)
    check("diagnostic", lane .. " / request latched at source load", function()
        local config = {}
        local env, observed = diagnosticEnv(config)
        run(input.diagnostic, env)
        config.BARGraphicsTraceOnce = 1
        env.widget:Initialize()
        exerciseDiagnostic(env.widget)
        assert(observed.queries == 0 and #observed.writes == 0 and observed.removed == 1)
    end)

    for _, scenario in ipairs({
        {name = "exact patch", block = needle, status = "applied", satisfied = true},
        {name = "already fixed", block = fixed, status = "already-present", satisfied = true},
        {name = "missing anchor", block = replace(needle, "not shown[option]", "shown[option] == nil"), status = "fallback"},
        {name = "duplicate original", block = needle .. "\n" .. needle, status = "fallback"},
        {name = "duplicate fixed", block = fixed .. "\n" .. fixed, status = "fallback"},
        {name = "mixed anchors", block = needle .. "\n" .. fixed, status = "fallback"},
    }) do
        check("options", lane .. " / " .. scenario.name, function()
            local env, observed = optionsEnv(optionsFixture(scenario.block))
            assert(run(input.options, env) == "archive-ok")
            local status = env.WG.BARMacOSOverlayStatus.optionsSearch
            assert(status.status == scenario.status and status.required == true)
            assert(status.satisfied == (scenario.satisfied == true))
            assert(status.applied == (scenario.status == "applied") and status.archiveLoaded == true)
            assert(env.widget.potato == false and #env.widget.samples == 1)
            env.widget:Initialize()
            assert(env.widget.archiveInitialized and #observed.writes == 0 and #observed.commands == 0)
            if scenario.satisfied then assert(#env.widget.Search({"a", "a", "b"}) == 2) end
            if scenario.name == "missing anchor" then assert(#env.widget.Search({"a", "a", "b"}) == 5) end
        end)
    end
    for _, scenario in ipairs({
        {name = "official recursive", block = recursiveSearch, satisfied = true},
        {name = "recursive CRLF", block = recursiveSearch:gsub("\n", "\r\n"), satisfied = true},
        {name = "recursive duplicate", block = recursiveSearch .. recursiveSearch},
        {name = "recursive mixed old", block = recursiveSearch .. "\n" .. needle},
        {name = "recursive mixed fixed", block = recursiveSearch .. "\n" .. fixed},
        {name = "recursive missing guard", block = replace(recursiveSearch, "shown[option] = true", "shown[option] = false")},
    }) do
        check("options", lane .. " / " .. scenario.name, function()
            local env = optionsEnv(recursiveFixture(scenario.block))
            assert(run(input.options, env) == "archive-ok")
            local status = env.WG.BARMacOSOverlayStatus.optionsSearch
            assert(status.status == (scenario.satisfied and "already-present" or "fallback"))
            assert(status.satisfied == (scenario.satisfied == true) and not status.applied)
            if scenario.satisfied then
                local parent, child, spacer = {}, {}, {}
                child.parentOption, child.spacer = parent, spacer
                local result = env.widget.Search({child, parent, child})
                assert(#result == 3 and result[1] == parent and result[2] == child and result[3] == spacer)
                parent.parentOption = child
                assert(#env.widget.Search({child, parent}) == 3, "parent cycle was not guarded")
            end
        end)
    end
    for _, scenario in ipairs({
        {name = "missing archive"},
        {name = "invalid archive type", archive = 17},
        {name = "compile failure", archive = optionsFixture(needle) .. "\n!"},
        {name = "module exception", archive = replace(optionsFixture(needle), 'return "archive-ok"', 'error("fixture exception")\nreturn "archive-ok"')},
    }) do
        check("options", lane .. " / " .. scenario.name, function()
            local env = optionsEnv(scenario.archive)
            env.WG.BARMacOSOverlayStatus = {optionsSearch = {applied = true, satisfied = true}}
            assert(not pcall(run, input.options, env))
            local status = env.WG.BARMacOSOverlayStatus.optionsSearch
            assert(status.status == "failed" and not status.applied and not status.satisfied)
            assert(not status.archiveLoaded and status.reason)
        end)
    end
    check("options", lane .. " / CRLF and retained MSAA policy", function()
        local env, observed = optionsEnv(optionsFixture(needle):gsub("\n", "\r\n"), 8)
        assert(run(input.options, env) == "archive-ok")
        assert(env.WG.BARMacOSOverlayStatus.optionsSearch.satisfied)
        assert(#observed.writes == 1 and observed.writes[1][1] == "MSAALevel" and observed.writes[1][2] == 4)
    end)

    for _, scenario in ipairs({
        {name = "normal preset order", keys = '"low","medium","high","ultra","custom"', index = 4},
        {name = "developer preset order", keys = '"lowest","low","medium","high","ultra","custom"', index = 5},
        {name = "missing fog option", keys = '"low","ultra","custom"', missing = true},
        {name = "non-Apple backend", keys = '"low","ultra","custom"', otherBackend = true},
    }) do
        check("options", lane .. " / one-time graphics / " .. scenario.name, function()
            local archive = [[local samples = {"x4", "x8"}
local options = {preset={id="preset"}, msaa={id="msaa"}, fogdiaglines={id="fogdiaglines"}}
local function getOption(id) return options[id] end
function applyOptionValue(option, value)
    widget.applied[#widget.applied+1] = {option.id, value}
end
function widget:Initialize()
    self.applied = self.applied or {}
    local presetKeys = {]] .. scenario.keys .. [[}
	local presetNames = {}
end
return "archive-ok"
]]
            if scenario.missing then archive = archive:gsub(', fogdiaglines={id="fogdiaglines"}', '') end
            local env, observed = optionsEnv(archive)
            if scenario.otherBackend then env.Platform.glHaveZinkMoltenVK = false end
            assert(run(input.options, env) == "archive-ok")
            env.widget:Initialize()
            assert(#env.widget.applied == 0, "defaults ran before all widgets initialized")
            env.widget:Update()
            if scenario.index then
                assert(#env.widget.applied == 3)
                assert(env.widget.applied[1][1] == "preset" and env.widget.applied[1][2] == scenario.index)
                assert(env.widget.applied[2][1] == "msaa" and env.widget.applied[2][2] == 1)
                assert(env.widget.applied[3][1] == "fogdiaglines" and env.widget.applied[3][2] == 0)
                assert(#observed.writes == 1 and observed.writes[1][1] == "BARMacOSGraphicsDefaults102")
                env.widget.applied = {} -- a later user choice must not be reset
                env.widget:Initialize()
                env.widget:Update()
                env.widget:BARMacOSApplyGraphicsDefaults()
                assert(#env.widget.applied == 0 and #observed.writes == 1)
            else
                assert(#env.widget.applied == 0 and #observed.writes == 0)
            end
        end)
    end

    for _, scenario in ipairs({
        {name="saved overhead restored before update", expected=2},
        {name="graphics migration already applied", graphicsDone=true, expected=2},
        {name="later user camera choice", cameraDone=true, expected=3},
        {name="missing camera option", missing=true, expected=3},
        {name="unexpected camera list", shortList=true, expected=3},
        {name="non-Apple camera unchanged", otherBackend=true, expected=3},
    }) do
        check("options", lane .. " / Spring default / " .. scenario.name, function()
            local archive = [[local samples = {"x4", "x8"}
local camera = {id="camera", options={"fps","overhead","spring","rot","free"}}
local function getOption(id) if id == "camera" then return camera end end
function applyOptionValue(option, value)
    assert(option == camera and value == 3)
    Spring.SetConfigInt("CamMode", value - 1)
    Spring.SendCommands("viewspring")
end
function widget:Initialize()
    local presetKeys = {"low","ultra","custom"}
	local presetNames = {}
end
return "archive-ok"
]]
            if scenario.missing then archive = archive:gsub('return camera', 'return nil') end
            if scenario.shortList then archive = archive:gsub(',"free"', '') end
            local env, observed = optionsEnv(archive)
            local liveMode = 3
            env.Spring.SendCommands = function(command)
                observed.commands[#observed.commands + 1] = command
                if command == "viewspring" then liveMode = 2 end
            end
            if scenario.otherBackend then env.Platform.glHaveZinkMoltenVK = false end
            if scenario.graphicsDone then env.Spring.SetConfigInt("BARMacOSGraphicsDefaults102", 1) end
            if scenario.cameraDone then env.Spring.SetConfigInt("BARMacOSSpringCamera102", 1) end
            assert(run(input.options, env) == "archive-ok")
            env.widget:Initialize()
            assert(liveMode == 3 and #observed.commands == 0, "camera changed before saved-camera initialization")
            liveMode = 3 -- Camera Remember restores the previous overhead state.
            env.widget:Update()
            assert(liveMode == scenario.expected)
            if scenario.expected == 2 then
                assert(env.Spring.GetConfigInt("CamMode") == 2)
                assert(env.Spring.GetConfigInt("BARMacOSSpringCamera102") == 1)
                assert(#observed.commands == 1)
                liveMode = 4 -- Later user preference, including a LuaUI reload.
                env.Spring.SetConfigInt("CamMode", 4)
                env.widget:Initialize()
                env.widget:Update()
                env.widget:BARMacOSApplyCameraDefault()
                assert(liveMode == 4 and #observed.commands == 1)
            else
                assert(#observed.commands == 0)
            end
        end)
    end

    check("instanceVBO", lane .. " / applied private module", function()
        local env, observed, baseline = instanceEnv(instanceFixture)
        local api, status = run(input.instanceVBO, env)
        assert(api ~= baseline and api.fixture and env.gl.InstanceVBOTable == baseline)
        assert(status == env.WG.BARMacOSOverlayStatus.instanceVBO and api._barCompactionStatus == status)
        assert(status.applied and status.satisfied and status.status == "applied" and status.required)
        assert(api._barCompactionRevision == status.revision)
        assert(#observed.logs == 0, "per-consumer success output returned")
        assert(not baseline._barCompactionRevision and not baseline._barCompactionStatus)
        assert(observed.compiled:find("local offset = (i - 1) * iTStep", 1, true))
        assert(observed.compiled:find("if iT.usedElements > 0 then", 1, true))
        assert(observed.compiled:find("endOffset = iTusedElements * iTStep", 1, true))
    end)
    local failures = {
        {name = "missing archive"},
        {name = "invalid archive type", archive = 17},
        {name = "missing resize boundary", archive = replace(instanceFixture, "--[[ from Ivand:", "--[[ changed:")},
        {name = "duplicate resize boundary", archive = "local function resizeInstanceVBOTable(iT) end\n" .. instanceFixture},
        {name = "duplicate end boundary", archive = replace(instanceFixture, "local function append(iT)", "--[[ from Ivand: duplicate ]]\nlocal function append(iT)")},
        {name = "missing compaction anchor", archive = replace(instanceFixture, offset, "local offset = 0")},
        {name = "duplicate compaction anchor", archive = replace(instanceFixture, offset, offset .. "\n" .. offset)},
        {name = "duplicate upstream compaction anchor", archive = replace(instanceFixture, offset,
            "local offset = (i - 1) * iTStep\nlocal offset = (i - 1) * iTStep")},
        {name = "missing upload anchor", archive = replace(instanceFixture, upload, "-- omitted upload")},
        {name = "duplicate upload anchor", archive = replace(instanceFixture, upload, upload .. "\n" .. upload)},
        {name = "missing append anchor", archive = replace(instanceFixture, recalculate, "-- omitted append")},
        {name = "duplicate append anchor", archive = replace(instanceFixture, recalculate, recalculate .. "\n" .. recalculate)},
        {name = "unknown upstream append offset", archive = replace(instanceFixture, recalculate,
            recalculate .. "\n\t\tendOffset = 123")},
        {name = "unknown upload guard", archive = replace(instanceFixture, upload,
            "\tif iT.usedElements < 0 then\n" .. upload .. "\n\tend")},
        {name = "compile failure", archive = instanceFixture .. "\n!"},
        {name = "module exception", archive = replace(instanceFixture, "return api", 'error("fixture exception")\nreturn api')},
        {name = "invalid module result", archive = replace(instanceFixture, "return api", "return nil")},
        {name = "reused global API", archive = replace(instanceFixture, "return api", "return originalApi")},
    }
    for _, scenario in ipairs(failures) do
        check("instanceVBO", lane .. " / " .. scenario.name, function()
            local env, observed, baseline = instanceEnv(scenario.archive)
            env.WG.BARMacOSOverlayStatus = {instanceVBO = {applied = true, satisfied = true}}
            local api, status = run(input.instanceVBO, env)
            assert(api == baseline and env.gl.InstanceVBOTable == baseline)
            assert(status == env.WG.BARMacOSOverlayStatus.instanceVBO)
            assert(status.status == "fallback" and status.fallbackAvailable)
            assert(not status.applied and not status.satisfied and status.required and status.reason)
            assert(not status.revision and not baseline._barCompactionRevision and not baseline._barCompactionStatus)
            assert(#observed.logs == 1 and observed.logs[1]:find("satisfied=false", 1, true))
        end)
    end
    check("instanceVBO", lane .. " / no fallback API", function()
        local env = instanceEnv(nil, false)
        local api, status = run(input.instanceVBO, env)
        assert(api == nil and status.status == "failed" and not status.fallbackAvailable)
        assert(not status.applied and not status.satisfied)
    end)
    check("instanceVBO", lane .. " / no WG test environment", function()
        local env = instanceEnv(instanceFixture)
        env.WG = nil
        local api, status = run(input.instanceVBO, env)
        assert(api._barCompactionStatus == status and status.satisfied)
    end)
end

-- Optional pinned official-source matrix. These are CPU GL mocks: execute the
-- real archive code and delegate, check API arguments and lifecycle, no GPU.
-- arg[2]: directory containing official-{433a460,ebba846}-*.lua evidence.
-- arg[3]: pre-change Lua backup root, to compare the retained legacy seam bytes.
if arg[2] then
    local function compileIn(source, name, env)
        return assert(load(source, name, "t", env))()
    end
    local function fontEnv(archive, zink)
        local env = environment()
        env.LUAUI_DIRNAME = "LuaUI/"
        local observed = {loads = {}, deletes = 0, compiled = nil, height = 900}
        env.Platform.glHaveZinkMoltenVK = zink
        env.math = setmetatable({clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end}, {__index = math})
        env.Spring = {
            Echo = function() end,
            GetViewGeometry = function() return 1600, observed.height end,
            GetConfigString = function(_, default) return default end,
            GetConfigFloat = function(_, default) return default end,
            GetGameFrame = function() return 0 end,
        }
        env.gl.LoadFont = function(file, size, outline, strength)
            local font = {file = file, size = size, outline = outline, strength = strength}
            observed.loads[#observed.loads + 1] = font
            return font
        end
        env.gl.DeleteFont = function() observed.deletes = observed.deletes + 1 end
        env.gl.AddFallbackFont = function() end
        env.VFS = {ZIP_ONLY = "zip", LoadFile = function(path, mode)
            assert(path == "LuaUI/Widgets/gui_fonthandler.lua" and mode == "zip")
            return archive
        end}
        env.loadstring = function(text, name)
            observed.compiled = text
            return load(text, name, "t", env)
        end
        return env, observed
    end
    local function mapEnv(archive)
        local env = environment()
        local observed = {compiled = nil, shaders = {}, draws = {}, buffers = {}, vaos = {}, removed = 0}
        env.Game = {mapSizeX = 128, mapSizeZ = 96}
        env.BAR = {Lava = {isLavaMap = false}}
        env.GL = {TRIANGLES = 4, TRIANGLE_STRIP = 5, POINTS = 0, ARRAY_BUFFER = 0x8892, BACK = 0x0405, LEQUAL = 0x0203, ALWAYS = 0x0207}
        env.Platform = {gpuVendor = "Apple", osFamily = "MacOSX"}
        env.Spring = {
            Echo = function() end, SendCommands = function() end,
            IsAABBInView = function() return true end,
            GetGroundExtremes = function() return -10, 100 end,
            GetCameraPosition = function() return 64, 200, 48 end,
            GetCameraDirection = function() return 0, -1, 0 end,
        }
        env.widgetHandler = {RemoveWidget = function() observed.removed = observed.removed + 1 end}
        env.gl.GetVBO = function()
            local buffer = {}
            function buffer:Define(count) self.count = count end
            function buffer:Upload(data) assert(not self.deleted and #data > 0); self.dataCount = #data end
            function buffer:Delete() assert(not self.deleted); self.deleted = true end
            observed.buffers[#observed.buffers + 1] = buffer
            return buffer
        end
        env.gl.GetVAO = function()
            local vao = {}
            function vao:AttachInstanceBuffer(buffer) self.instance = buffer end
            function vao:AttachVertexBuffer(buffer) self.vertex = buffer end
            function vao:AttachIndexBuffer(buffer) self.index = buffer end
            function vao:DrawArrays(primitive, vertices, first, instances)
                assert(not self.deleted and not self.instance.deleted and vertices > 0)
                observed.draws[#observed.draws + 1] = {primitive = primitive, vertices = vertices, instances = instances}
            end
            function vao:DrawElements(primitive, vertices, first, instances)
                assert(self.index and self.vertex and not self.deleted)
                observed.draws[#observed.draws + 1] = {primitive = primitive, instances = instances}
            end
            function vao:Delete() assert(not self.deleted); self.deleted = true end
            observed.vaos[#observed.vaos + 1] = vao
            return vao
        end
        env.gl.InstanceVBOTable = {
            makePlaneVBO = function() return env.gl.GetVBO(), 4 end,
            makePlaneIndexVBO = function() return env.gl.GetVBO(), 6 end,
        }
        env.gl.LuaShader = setmetatable({
            GetEngineUniformBufferDefs = function() return "" end,
            isGeometryShaderSupported = true, -- a false advertised positive must not select GS
        }, {__call = function(_, config)
            assert(config.geometry == nil, "map edge tried a Geometry Shader")
            observed.shaders[#observed.shaders + 1] = config
            return {
                shaderObj = 1, Initialize = function() return true end,
                Activate = function() end, Deactivate = function() end,
                ActivateWith = function(_, fn) fn() end,
                SetUniform = function() end, SetUniformAlways = function() end,
                Finalize = function(self) assert(self.shaderObj); self.shaderObj = nil end,
            }
        end})
        env.gl.CreateShader = function() error("unexpected direct CreateShader") end
        env.gl.GetMapRendering = function() return false end
        for _, key in ipairs({"Culling", "Texture", "DepthTest", "DepthMask"}) do env.gl[key] = function() end end
        env.VFS = {ZIP_ONLY = "zip", LoadFile = function(path, mode)
            assert(path == "LuaUI/Widgets/map_edge_extension2.lua" and mode == "zip")
            return archive
        end}
        env.loadstring = function(text, name)
            observed.compiled = text
            return load(text, name, "t", env)
        end
        return env, observed
    end
    for _, version in ipairs({"433a460", "ebba846"}) do
        local fontArchive = read(arg[2] .. "/official-" .. version .. "-gui_fonthandler.lua")
        local mapArchive = read(arg[2] .. "/official-" .. version .. "-map_edge_extension2.lua")
        for _, lane in ipairs(lanes) do
            for _, zink in ipairs({false, true}) do
                check("font", lane .. " / " .. version .. " / raster=" .. tostring(zink), function()
                    local plain, expected = fontEnv(fontArchive, zink)
                    local adapted, actual = fontEnv(fontArchive, zink)
                    compileIn(fontArchive, "@official-font", plain)
                    run(sources[lane].font, adapted)
                    plain.widget:Initialize()
                    adapted.widget:Initialize()
                    for _, height in ipairs({900, 720}) do
                        expected.height, actual.height = height, height
                        plain.widget:ViewResize(1600, height)
                        adapted.widget:ViewResize(1600, height)
                        for _, size in ipairs({1.3, 1.31, 1.8}) do
                            local _, logical = plain.WG.fonts.getFont(1, size, 0.2, 1.7)
                            local _, scaledLogical = adapted.WG.fonts.getFont(1, size, 0.2, 1.7)
                            assert(logical == scaledLogical, "font logical size changed")
                        end
                    end
                    assert(#actual.loads == #expected.loads and actual.deletes == expected.deletes, "font cache/lifetime policy changed")
                    local scale = zink and 2 or 1
                    for i, font in ipairs(expected.loads) do
                        local raster = actual.loads[i]
                        assert(raster.file == font.file and raster.strength == font.strength)
                        assert(raster.size == font.size * scale and raster.outline == font.outline * scale)
                    end
                end)
            end
            check("mapEdge", lane .. " / " .. version .. " / actual archive lifecycle", function()
                local env, observed = mapEnv(mapArchive)
                run(sources[lane].mapEdge, env)
                env.widget:Initialize()
                assert(observed.removed == 0 and #observed.shaders == 2)
                env.widget:DrawWorldPreUnit()
                env.widget:DrawGroundDeferred()
                assert(#observed.draws == 2)
                if version == "ebba846" then
                    assert(observed.compiled == mapArchive, "common path source was transformed")
                    for _, draw in ipairs(observed.draws) do
                        assert(draw.primitive == env.GL.TRIANGLE_STRIP and draw.instances == 8)
                    end
                    env.WG.mapedgeextension.setCurvature(false)
                    env.widget:DrawWorldPreUnit()
                    assert(observed.draws[3].vertices >= observed.draws[1].vertices)
                else
                    assert(observed.draws[1].primitive == env.GL.TRIANGLES and observed.draws[1].instances == 9)
                    assert(observed.draws[2].primitive == env.GL.TRIANGLES and observed.draws[2].instances == 8)
                    assert(observed.shaders[1].vertex:find("const float SEAMHEIGHT = -128.0;", 1, true))
                    if arg[3] then
                        local beforeEnv, before = mapEnv(mapArchive)
                        run(read(arg[3] .. "/sources/bar-lobby/bundled-assets/macos-luaui-overlays/" .. lane .. "/LuaUI/Widgets/map_edge_extension2.lua"), beforeEnv)
                        assert(observed.compiled == before.compiled, "accepted legacy seam shader/mesh changed")
                    end
                end
                env.widget:Shutdown()
                if version == "ebba846" then
                    for _, buffer in ipairs(observed.buffers) do assert(buffer.deleted) end
                    for _, vao in ipairs(observed.vaos) do assert(vao.deleted) end
                end
            end)
            for _, scenario in ipairs({
                {name = "missing archive"},
                {name = "unknown load call", archive = fontArchive:gsub("gl%.LoadFont%(file,", "gl.LoadFont(changedFile,")},
                {name = "duplicate load call", archive = fontArchive .. "\ngl.LoadFont(file, px, outlinePx, outlineStrength)\n"},
                {name = "changed outline", archive = fontArchive:gsub("local outlineMult = math%.clamp", "local outlineMult = changedClamp")},
            }) do
                check("font", lane .. " / " .. version .. " / " .. scenario.name, function()
                    local env, observed = fontEnv(scenario.archive, true)
                    assert(not pcall(run, sources[lane].font, env))
                    assert(observed.compiled == nil and env.WG.fonts == nil, "partial font delegate escaped")
                end)
            end
        end
    end
    local common = read(arg[2] .. "/official-ebba846-map_edge_extension2.lua")
    for _, lane in ipairs(lanes) do
        for _, scenario in ipairs({
            {name = "missing archive"},
            {name = "changed common draw", archive = replace(common, "terrainVAO:DrawArrays(GL.TRIANGLE_STRIP,", "terrainVAO:DrawArrays(GL.POINTS,")},
            {name = "unknown common mesh", archive = replace(common, "int line = gl_VertexID / perLine;", "int line = gl_VertexID;")},
            {name = "ambiguous common shader", archive = common .. "\n-- vertex = assemble(vsSrc),\n"},
            {name = "unexpected GS branch", archive = common .. '\nlocal unexpected = {geometry = "GS"}\n'},
        }) do
            check("mapEdge", lane .. " / " .. scenario.name, function()
                local env, observed = mapEnv(scenario.archive)
                assert(not pcall(run, sources[lane].mapEdge, env))
                assert(observed.compiled == nil and #observed.shaders == 0, "partial map delegate escaped")
            end)
        end
    end
end
-- Optional native-provider handler output. Exercise the real LoadWidget method,
-- unchanged current sandbox, tracker producer and healthbar consumer bodies.
-- GL buffers and unit data are CPU recorders; this does not prove visible pixels.
if arg[4] then
    counts.healthDispatch = 0
    local provider = arg[4]
    local handler = read(provider .. "/cpu-generated/ebba846-barwidgets.lua")
    local originalHandler = read(provider .. "/official-ebba846-barwidgets.lua")
    local tracker = read(overlay .. "bar-lobby/LuaUI/Widgets/api_unit_tracker_gl4.lua"):gsub("\r\n", "\n")
    local healthbar = read(overlay .. "bar-lobby/LuaUI/Widgets/gui_healthbars_gl4.lua"):gsub("\r\n", "\n")
    local function section(text, first, last)
        local start = assert(text:find(first, 1, true))
        local finish = assert(text:find(last, start + #first, true))
        return text:sub(start, finish - 1)
    end
    local trackerBodies = section(tracker, "local function visibleUnitsChanged()", "local instanceVBOCacheTable")
        .. section(tracker, "local function visibleUnitsAdd(", "local function visibleUnitsRemove(")
    local trackerFixture = "local visibleUnits, visibleUnitsTeam, numVisibleUnits = {}, {}, 0\nlocal debuglevel, debugdrawvisible = 0, false\n"
        .. 'function widget:GetInfo() return {name="Provider tracker CPU",enabled=true,handler=true} end\n'
        .. trackerBodies .. "\nwidget.cpuAdd = visibleUnitsAdd; widget.cpuChanged = visibleUnitsChanged\n"
    local rawFixture = trackerFixture:gsub("Provider tracker CPU", "Raw tracker CPU")
    local healthBodies = section(healthbar, "local function addBarForUnit(", "local function removeBarsFromUnit(")
        .. section(healthbar, "function widget:VisibleUnitAdded(", "function widget:PlayerChanged(")
    local loadWidget = section(handler, "function widgetHandler:LoadWidget(", "local WidgetMeta =")
    local nativePrefix = "local __barBundledWidgetSource = ...\n"
    assert(handler:sub(1, #nativePrefix) == nativePrefix)
    local sandbox = section(originalHandler, "\tlocal sandboxedScript = copyTable(Script)", "\tlocal sandboxedSpring = copyTable(Spring)")
    local createWidget = section(originalHandler, "newWidget = function(self, enableLocalsAccess, fromZip, filename)", "\n\t-- wrapped calls")
        .. "\nwidget.widgetHandler = {}; return widget, canControlUnits\nend\n"
    local dispatch = section(originalHandler, "function widgetHandler:VisibleUnitAdded(", "function widgetHandler:AlliedUnitAdded(")
    for _, allowUsers in ipairs({true, false}) do
        check("healthDispatch", "actual current handler / user widgets=" .. tostring(allowUsers), function()
            local records, rawRan = {}, false
            local hb = environment()
            local vbo = {instanceIDtoIndex = {}}
            hb.Spring = {
                ValidUnitID = function() return true end, GetUnitIsDead = function() return false end,
                GetUnitAllyTeam = function() return 1 end, GetMyAllyTeamID = function() return 1 end,
            }
            hb.spGetUnitHealth = function() return 50, 100, 0, 0, 1 end
            hb.spGetUnitTeam = function() return 1 end
            hb.spGetSpectatingState = function() return false, false end
            hb.spGetUnitDefID = function() return 7 end
            hb.unitBars, hb.unitDefIgnore, hb.unitDefHideDamage, hb.unitDefhasShield = {}, {}, {}, {}
            hb.unitDefReactiveArmor, hb.unitDefCanStockpile, hb.unitDefPrimaryWeapon = {}, {}, {}
            hb.unitReloadWatch, hb.unitStockPileWatch, hb.unitCaptureWatch = {}, {}, {}
            hb.unitShieldWatch, hb.unitReactiveArmorWatch, hb.unitEmpDamagedWatch, hb.unitParalyzedWatch = {}, {}, {}, {}
            hb.debugmode, hb.fullview, hb.myAllyTeamID = false, false, 1
            hb.variableBarSizes, hb.barScale, hb.additionalheightaboveunit = false, 2, 5
            hb.unitDefHeights, hb.healthBarVBO = {[7] = 64}, vbo
            hb.barTypeMap = {health = {cache = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}}}
            hb.pushElementInstance = function(target, data, id, update, noUpload, unitID)
                assert(target == vbo and data[1] == 74 and data[2] == 2 and unitID == 101)
                records[id], target.instanceIDtoIndex[id] = unitID, 1
                return id
            end
            hb.InstanceVBOTable = {clearInstanceTable = function(target)
                assert(target == vbo); records = {}; target.instanceIDtoIndex = {}
            end}
            assert(load(healthBodies, "@actual-healthbar-consumer", "t", hb))()
            local wh = {WG = {}, globals = {}, allowUserWidgets = allowUsers, knownWidgets = {}, knownCount = 0,
                orderList = {}, configData = {}, errorLog = {}, widgetHashes = {},
                VisibleUnitAddedList = {hb.widget}, VisibleUnitRemovedList = {}, VisibleUnitsChangedList = {hb.widget}}
            function wh:FinalizeWidget(widget) widget.whInfo = widget:GetInfo() end
            function wh:ValidateWidget() return nil end
            local env = environment()
            env.widgetHandler, env.tracyZoneBeginN, env.tracyZoneEnd = wh, function() end, function() end
            assert(load(dispatch, "@actual-handler-dispatch", "t", env))()
            local calls = {}
            for _, name in ipairs({"VisibleUnitAdded", "VisibleUnitsChanged"}) do
                calls[name] = function(...) return wh[name](wh, ...) end
                env[name] = calls[name] -- actual handler's engine-visible global, not RegisterGlobal
            end
            local script = {LuaUI = setmetatable(calls, {__call = function(_, name) return calls[name] ~= nil end})}
            env.Script = script
            env.copyTable = function(t) local r = {}; for k,v in pairs(t) do r[k] = v end; return r end
            env.unavailableFunction, env.warnOnce = function() end, function() end
            local sandboxed = assert(load(sandbox .. "\nreturn sandboxedScript", "@actual-user-Script-sandbox", "t", env))()
            env.System, env.SandboxedSystem = {Script = script}, {Script = sandboxed}
            env.WidgetMeta, env.SandboxedWidgetMeta = {__index = env.System}, {__index = env.SandboxedSystem}
            assert(load(createWidget, "@actual-widget-system-selection", "t", env))()
            env.allowuserwidgets, env.vfsZip, env.vfsRawFirst = allowUsers, "zip", "raw-first"
            env.Basename = function(p) return p:match("([^/]+)$") end
            env.loadFailed = function(_, reason) return nil, reason end
            env.spEcho, env.usesRmlUi = function() end, function() return false end
            env.zipOnly, env.loadedWidgets = {}, {}
            env.VFS = {
                GetBundledPresentationWidget = function() error("spoofable global provider was used") end,
                CalculateHash = function() return "raw-widget-hash" end,
            }
            env.vfsLoadFile = function(filename, mode)
                if filename:find("api_unit_tracker", 1, true) then
                    return 'rawMaliciousRan=true; error("same-name RAW source must not execute")'
                end
                if filename:find("user_custom", 1, true) and mode == "raw-first" then return rawFixture end
                return nil -- distribution-only PIP has no archive member
            end
            env.loadstring = function(text, name) return load(text, name, "t", env) end
            env.setfenv = function(fn, target)
                for i = 1, math.huge do
                    local name = debug.getupvalue(fn, i)
                    if not name then break end
                    if name == "_ENV" then debug.setupvalue(fn, i, target); break end
                end
                return fn
            end
            local nativeProvider = function(filename)
                if filename:lower() == "luaui/widgets/api_unit_tracker_gl4.lua" then return trackerFixture end
                if filename:lower() == "luaui/widgets/gui_pip_macos_minimap_overlay.lua" then
                    return 'function widget:GetInfo() return {name="Distribution only CPU", enabled=true} end'
                end
            end
            assert(load(nativePrefix .. loadWidget, "@actual-native-augmented-LoadWidget", "t", env))(nativeProvider)
            local trusted = assert(wh:LoadWidget("LuaUI/Widgets/api_unit_tracker_gl4.lua", false))
            assert(trusted.widgetHandler == wh and wh.knownWidgets[trusted.whInfo.name].fromZip)
            assert(trusted.Script == script and not env.rawMaliciousRan)
            trusted.cpuAdd(101, 7, 1, false, "post-start-newly-visible")
            assert(records["101_health"] == 101, "post-start tracker event did not add actual healthbar instance")
            trusted.cpuChanged()
            assert(records["101_health"] == 101, "bulk tracker event did not rebuild actual healthbar instance")
            local distribution = assert(wh:LoadWidget("LuaUI/Widgets/gui_pip_macos_minimap_overlay.lua", true))
            assert(wh.knownWidgets[distribution.whInfo.name].fromZip)
            local raw = wh:LoadWidget("LuaUI/Widgets/user_custom.lua", false)
            if allowUsers then
                assert(raw and raw.widgetHandler ~= wh and raw.Script == sandboxed)
                raw.cpuAdd(202, 7, 1, false, "raw-caller-negative")
                assert(records["202_health"] == nil and not wh.globals.VisibleUnitAdded)
            else
                assert(raw == nil, "forbidden RAW user widget loaded")
            end
        end)
    end
end
-- Optional current-game and real OS-query fixtures; no engine/network/GL run.
if arg[5] then
    local fixture = arg[5]
    local official = read(fixture .. "/official-api_analytics.lua")
    local start = assert(official:find("local function trim1(s)", 1, true))
    local finish = assert(official:find("local socket = socket", start, true))
    local core = official:sub(start, finish - 1)
    local function analytics(hw)
        local env = environment()
        env.Platform = {hwConfig = hw}
        env.Spring = {Utilities = {Base64Encode = function(v) return v end}}
        env.VFS = {GetFileAbsolutePath = function() return "fixture/infolog.txt" end, CalculateHash = function(v) return v end}
        return run(core .. "\nMachineHash()\nreturn cpuinfo", env)
    end
    counts.platformCompatibility = 0
    check("platformCompatibility", "official analytics old Mac input reproduces nil arithmetic", function()
        local ok, message = pcall(analytics, "16384MB RAM")
        assert(not ok and tostring(message):find("arithmetic", 1, true))
    end)
    for _, hw in ipairs({read(fixture .. "/hardware-cpu-output.txt"):gsub("\n$", ""), "Unknown CPU; 16384MB RAM"}) do
        check("platformCompatibility", "official analytics consumes native CPU field", function()
            assert(analytics(hw) == hw:match("^(.-);"))
        end)
    end
    for _, lane in ipairs(lanes) do
        check("options", lane .. " / exact c648e9c Options source recognition and syntax", function()
            local env = optionsEnv(read(fixture .. "/official-current-gui_options.lua"))
            local compiled
            env.load = function(text, name)
                assert(load(text, name, "t", {}), "adapted official source syntax failed")
                compiled = text
                return function() return "archive-ok" end -- no runtime widget/GL here
            end
            assert(run(sources[lane].options, env) == "archive-ok")
            local status = env.WG.BARMacOSOverlayStatus.optionsSearch
            assert(status.satisfied and not status.applied and status.status == "already-present")
            assert(compiled:find(recursiveSearch, 1, true), "official recursive implementation changed")
        end)
    end
end

local total = 0
for _, count in pairs(counts) do total = total + count end
print(string.format("PASS %d CPU cases: diagnostic=%d options=%d instanceVBO=%d font=%d mapEdge=%d healthDispatch=%d laneIdentity=%d",
    total, counts.diagnostic, counts.options, counts.instanceVBO, counts.font, counts.mapEdge, counts.healthDispatch or 0, counts.laneIdentity))

