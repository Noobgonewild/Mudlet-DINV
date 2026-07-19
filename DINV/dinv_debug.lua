----------------------------------------------------------------------------------------------------
-- DINV Debug Module
-- Per-module debug toggles and persistence
----------------------------------------------------------------------------------------------------

inv = inv or {}
inv.cli = inv.cli or {}

DINV.debug = DINV.debug or {}
DINV.debug.name = "dinv.debug.state"
DINV.debug.table = DINV.debug.table or {
    enabled = {},
    global = false,
}
DINV.debug.known = DINV.debug.known or {}
DINV.debug.descriptions = DINV.debug.descriptions or {
    aliases = "Mudlet alias registration and command shortcuts.",
    dbot = "Core utility/logging framework.",
    discovery = "Equipment/inventory parsing triggers.",
    ["inv.analyze"] = "Analyze item stats and recommendations.",
    ["inv.api"] = "Public API requests, events, and callback diagnostics.",
    ["inv.cache"] = "Inventory cache initialization.",
    ["inv.cli"] = "Command routing and help.",
    ["inv.compare"] = "Compare items and sets.",
    ["inv.config"] = "Configuration defaults and persistence.",
    ["inv.consume"] = "Consume items by effect.",
    ["inv.core"] = "Inventory core lifecycle and initialization.",
    ["inv.commands"] = "Command logging for get/wear/put/remove actions.",
    ["inv.items"] = "Inventory parsing and item actions.",
    ["inv.keyword"] = "Keyword tagging for items.",
    ["inv.organize"] = "Container organization helpers.",
    ["inv.operations"] = "Observed item-operation progress and confirmations.",
    ["inv.pass"] = "Pass items to other players.",
    ["inv.portal"] = "Portal usage helpers.",
    ["inv.priority"] = "Priority tables for item scoring.",
    ["inv.regen"] = "Regenerate or refresh data flows.",
    ["inv.report"] = "Inventory reporting and summaries.",
    ["inv.score"] = "Item scoring rules.",
    ["inv.set"] = "Set wear and equipment management.",
    ["inv.snapshot"] = "Snapshot storage and recall.",
    ["inv.statBonus"] = "Stat bonus tracking.",
    ["inv.tags"] = "Tagging helpers.",
    ["inv.unused"] = "Find unused items.",
    ["inv.usage"] = "Usage suggestions per item.",
    ["inv.weapon"] = "Weapon swapping and priority rules.",
    levelup = "Level-up trigger diagnostics line (independent of module debug toggles).",
    loader = "Module loader and initialization hooks.",
    ["wear-timing"] = "Aggregate set-wear build, dispatch, invmon, and database timings.",
    -- rid = "RID identify reporting (debug output per identify line).", -- RID disabled
    triggers = "Mudlet trigger registration.",
}

-- Runtime-only aggregate timing state. Individual inventory events are never
-- printed; one compact report is emitted after a tracked set-wear operation.
local priorWearTimingId = DINV.debug.wearTiming and DINV.debug.wearTiming.nextId or 0
DINV.debug.wearTiming = {
    nextId = priorWearTimingId,
    active = {},
}

local function wearTimingWallNow()
    if type(getEpoch) == "function" then
        local ok, value = pcall(getEpoch)
        if ok and tonumber(value) then
            return tonumber(value)
        end
    end
    return os.clock()
end

local function wearTimingNow()
    return wearTimingWallNow(), os.clock()
end

local function wearTimingElapsedMs(startValue, endValue)
    return math.max(0, ((tonumber(endValue) or 0) - (tonumber(startValue) or 0)) * 1000)
end

local function wearTimingAddAggregate(aggregate, wallMs, cpuMs)
    aggregate.count = (aggregate.count or 0) + 1
    aggregate.wallMs = (aggregate.wallMs or 0) + wallMs
    aggregate.cpuMs = (aggregate.cpuMs or 0) + cpuMs
    aggregate.maxWallMs = math.max(aggregate.maxWallMs or 0, wallMs)
    aggregate.maxCpuMs = math.max(aggregate.maxCpuMs or 0, cpuMs)
end

local function wearTimingFormatPhase(phase)
    phase = phase or {}
    return string.format("%.1f/%.1f", tonumber(phase.wallMs) or 0, tonumber(phase.cpuMs) or 0)
end

local function wearTimingLatestMatching(objId)
    local objectKey = tostring(objId or "")
    local selected = nil
    for _, timing in pairs(DINV.debug.wearTiming.active or {}) do
        if not timing.finished
            and (objectKey == "" or (timing.objIds and timing.objIds[objectKey]))
            and (not selected or timing.id > selected.id) then
            selected = timing
        end
    end
    return selected
end

function DINV.debug.hasActiveWearTiming()
    return next(DINV.debug.wearTiming.active or {}) ~= nil
end

function DINV.debug.beginWearTimingSample()
    if not DINV.debug.hasActiveWearTiming() then
        return nil, nil
    end
    return wearTimingNow()
end

function DINV.debug.startWearTiming(priorityName, level)
    if not DINV.debug.isEnabled("wear-timing") then
        return nil
    end

    DINV.debug.wearTiming.nextId = DINV.debug.wearTiming.nextId + 1
    local timingId = DINV.debug.wearTiming.nextId
    local wallNow, cpuNow = wearTimingNow()
    DINV.debug.wearTiming.active[timingId] = {
        id = timingId,
        priority = tostring(priorityName or ""),
        level = tostring(level or ""),
        startWall = wallNow,
        startCpu = cpuNow,
        phases = {},
        invmon = {},
        database = {},
        commandCount = 0,
        objIds = {},
        finished = false,
    }
    return timingId
end

function DINV.debug.recordWearTimingPhase(timingId, phaseName, startWall, startCpu)
    local timing = DINV.debug.wearTiming.active[tonumber(timingId)]
    if not timing or timing.finished or not startWall or not startCpu then
        return
    end
    local wallNow, cpuNow = wearTimingNow()
    timing.phases[tostring(phaseName)] = {
        wallMs = wearTimingElapsedMs(startWall, wallNow),
        cpuMs = wearTimingElapsedMs(startCpu, cpuNow),
    }
end

function DINV.debug.setWearTimingCommands(timingId, commands)
    local timing = DINV.debug.wearTiming.active[tonumber(timingId)]
    if not timing or timing.finished then
        return
    end
    timing.commandCount = #(commands or {})
    timing.objIds = {}
    for _, command in ipairs(commands or {}) do
        local objId = tostring(command or ""):match("^%S+%s+(%d+)")
        if objId then
            timing.objIds[objId] = true
        end
    end
end

function DINV.debug.recordWearTimingInvmon(objId, action, startWall, startCpu)
    if not startWall or not startCpu then
        return
    end
    local timing = wearTimingLatestMatching(objId)
    if not timing then
        return
    end
    local wallNow, cpuNow = wearTimingNow()
    wearTimingAddAggregate(
        timing.invmon,
        wearTimingElapsedMs(startWall, wallNow),
        wearTimingElapsedMs(startCpu, cpuNow)
    )
    local actionKey = tostring(action or "unknown")
    timing.invmon.actions = timing.invmon.actions or {}
    timing.invmon.actions[actionKey] = (timing.invmon.actions[actionKey] or 0) + 1
end

function DINV.debug.recordWearTimingDatabase(startWall, startCpu)
    if not startWall or not startCpu then
        return
    end
    local timing = wearTimingLatestMatching("")
    if not timing then
        return
    end
    local wallNow, cpuNow = wearTimingNow()
    wearTimingAddAggregate(
        timing.database,
        wearTimingElapsedMs(startWall, wallNow),
        wearTimingElapsedMs(startCpu, cpuNow)
    )
end

function DINV.debug.finishWearTiming(timingId, result)
    local numericId = tonumber(timingId)
    local timing = DINV.debug.wearTiming.active[numericId]
    if not timing or timing.finished then
        return
    end
    timing.finished = true
    local wallNow = wearTimingWallNow()
    local elapsedMs = wearTimingElapsedMs(timing.startWall, wallNow)
    local status = "complete"
    if type(result) == "table" then
        if result.status then
            status = tostring(result.status)
        elseif result.timedOut then
            status = "timed out"
        elseif result.failures and #result.failures > 0 then
            status = tostring(#result.failures) .. " unconfirmed"
        end
    elseif result ~= nil then
        status = tostring(result)
    end

    local phases = timing.phases or {}
    local invmonTiming = timing.invmon or {}
    local databaseTiming = timing.database or {}
    dbot.printRaw(string.format(
        "@D[DINV WEAR TIMING] @W%s level %s@w | commands=%d | elapsed=%.1fms | %s",
        timing.priority, timing.level, timing.commandCount or 0, elapsedMs, status
    ))
    dbot.printRaw(string.format(
        "@D  wall/cpu ms:@w cache=%s plan=%s dispatch=%s | invmon=%d calls %.1f/%.1f max %.1f | database=%d saves %.1f/%.1f max %.1f",
        wearTimingFormatPhase(phases.cache),
        wearTimingFormatPhase(phases.plan),
        wearTimingFormatPhase(phases.dispatch),
        invmonTiming.count or 0,
        invmonTiming.wallMs or 0,
        invmonTiming.cpuMs or 0,
        invmonTiming.maxWallMs or 0,
        databaseTiming.count or 0,
        databaseTiming.wallMs or 0,
        databaseTiming.cpuMs or 0,
        databaseTiming.maxWallMs or 0
    ))
    DINV.debug.wearTiming.active[numericId] = nil
end

function DINV.debug.requestWearTimingFinish(timingId, result)
    local timing = DINV.debug.wearTiming.active[tonumber(timingId)]
    if not timing or timing.finished or timing.finishRequested then
        return
    end
    timing.finishRequested = true
    if type(tempTimer) == "function" then
        -- Invmon persistence is debounced by 0.5 seconds. Waiting slightly
        -- longer includes the final save in the aggregate report.
        tempTimer(0.75, function()
            DINV.debug.finishWearTiming(timingId, result)
        end)
    else
        DINV.debug.finishWearTiming(timingId, result)
    end
end

function DINV.debug.reset()
    DINV.debug.table = {
        enabled = {},
        global = false,
    }
    return DRL_RET_SUCCESS
end

function DINV.debug.load()
    if DINV and DINV.database and DINV.database.loadModuleTable then
        local value, retval = DINV.database.loadModuleTable("debug", DINV.debug.reset)
        if value then DINV.debug.table = value end
        return retval
    end
    return DRL_RET_UNINITIALIZED
end

function DINV.debug.save()
    if DINV and DINV.database and DINV.database.saveModuleTable then
        return DINV.database.saveModuleTable("debug", DINV.debug.table)
    end
    return DRL_RET_UNINITIALIZED
end

function DINV.debug.registerModule(moduleName, description)
    if not moduleName or moduleName == "" then
        return
    end
    if moduleName == "on" or moduleName == "off" or moduleName == "debug" then
        return
    end
    DINV.debug.known[moduleName] = true
    if description and description ~= "" then
        DINV.debug.descriptions[moduleName] = description
    end
end

function DINV.debug.getDescription(moduleName)
    if not moduleName or moduleName == "" then
        return ""
    end
    return DINV.debug.descriptions[moduleName] or ""
end

function DINV.debug.parseEnabledFlag(flag)
    if not flag or flag == "" then
        return nil
    end

    local normalized = tostring(flag):lower()
    if normalized == "on" or normalized == "enable" or normalized == "enabled" or normalized == "true" or normalized == "1" then
        return true
    end
    if normalized == "off" or normalized == "disable" or normalized == "disabled" or normalized == "false" or normalized == "0" then
        return false
    end

    return nil
end

function DINV.debug.isEnabled(moduleName)
    if not moduleName or moduleName == "" then
        return false
    end

    DINV.debug.registerModule(moduleName)

    if DINV.debug.table.global then
        return true
    end

    if DINV.debug.table.enabled[moduleName] == true then
        return true
    end

    if tostring(moduleName):match("^dbot%.") then
        return DINV.debug.table.enabled.dbot == true
    end

    return false
end

function DINV.debug.setEnabled(moduleName, enabled)
    if not moduleName or moduleName == "" then
        return false
    end

    if moduleName == "all" then
        DINV.debug.table.global = enabled and true or false
    else
        DINV.debug.registerModule(moduleName)
        DINV.debug.table.enabled[moduleName] = enabled and true or nil
    end

    DINV.debug.save()
    return enabled and true or false
end

function DINV.debug.toggle(moduleName)
    if not moduleName or moduleName == "" then
        return false
    end

    if moduleName == "all" then
        DINV.debug.table.global = not DINV.debug.table.global
        DINV.debug.save()
        return DINV.debug.table.global
    end

    DINV.debug.registerModule(moduleName)
    local nextState = not (DINV.debug.table.enabled[moduleName] == true)
    DINV.debug.table.enabled[moduleName] = nextState or nil
    DINV.debug.save()
    return nextState
end

function DINV.debug.listModules()
    local list = {}
    local seen = {}
    for moduleName in pairs(DINV.debug.known) do
        if moduleName ~= "on" and moduleName ~= "off" and moduleName ~= "debug" then
            local entryName = moduleName
            if tostring(moduleName):match("^dbot%.") then
                entryName = "dbot"
            end
            if entryName and not seen[entryName] then
                table.insert(list, entryName)
                seen[entryName] = true
            end
        end
    end
    for moduleName in pairs(DINV.debug.descriptions) do
        local entryName = moduleName
        if tostring(moduleName):match("^dbot%.") then
            entryName = "dbot"
        end
        if entryName and not seen[entryName] and entryName ~= "debug" then
            seen[entryName] = true
            table.insert(list, entryName)
        end
    end
    table.sort(list)
    return list
end

----------------------------------------------------------------------------------------------------
-- CLI Command
----------------------------------------------------------------------------------------------------

inv.cli.debug = inv.cli.debug or {}

function inv.cli.debug.fn(name, line, wildcards)
    if not DINV.debug then
        dbot.warn("Debug module not available.")
        return DRL_RET_UNINITIALIZED
    end

    local moduleName = wildcards and wildcards[1] or nil
    if not moduleName or moduleName == "" then
        inv.cli.debug.usage()
        return DRL_RET_INVALID_PARAM
    end

    moduleName = tostring(moduleName):lower()
    if moduleName == "levelup" then
        if not inv.levelup or not inv.levelup.setDebug or not inv.levelup.getDebug then
            dbot.warn("Level-up module is not available.")
            return DRL_RET_UNINITIALIZED
        end

        local flag = wildcards and wildcards[2] or nil
        if not flag or flag == "" then
            local toggled = inv.levelup.getDebug() and "off" or "on"
            return inv.levelup.setDebug(toggled, true)
        end

        local retval = inv.levelup.setDebug(flag, true)
        if retval ~= DRL_RET_SUCCESS then
            dbot.warn("Usage: dinv debug levelup [on|off]")
        end
        return retval
    end

    if moduleName == "list" then
        local list = DINV.debug.listModules()
        if #list == 0 then
            dbot.note("No debug modules registered yet.")
            return DRL_RET_SUCCESS
        end

        dbot.print("@W\nRegistered debug modules:")
        for _, entry in ipairs(list) do
            local isEnabled = DINV.debug.isEnabled(entry)
            if entry == "levelup" and inv.levelup and inv.levelup.getDebug then
                isEnabled = inv.levelup.getDebug()
            end
            local state = isEnabled and "@GON@W" or "@ROFF@W"
            local description = DINV.debug.getDescription(entry)
            local suffix = description ~= "" and (" - " .. description) or ""
            dbot.print(string.format("  @C%-24s@W %s%s", entry, state, suffix))
        end
        dbot.print("@W")
        return DRL_RET_SUCCESS
    end

    local requestedState = DINV.debug.parseEnabledFlag(wildcards and wildcards[2] or nil)

    if moduleName == "on" or moduleName == "off" then
        requestedState = moduleName == "on"
        moduleName = "all"
    end

    local enabled = requestedState
    if enabled == nil then
        enabled = DINV.debug.toggle(moduleName)
    else
        enabled = DINV.debug.setEnabled(moduleName, enabled)
    end
    dbot.note(string.format("Debug for '%s' is now %s.", moduleName, enabled and "ON" or "OFF"))
    return DRL_RET_SUCCESS
end

function inv.cli.debug.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s",
               pluginNameCmd .. " debug @G<module|list|all|levelup> [on|off]",
               "Toggle per-module debug output or list modules"))
end

function inv.cli.debug.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.debug.usage()
    dbot.print(
[[@W
Examples:
  1) Show available debug modules
     "@Gdinv debug list@W"

  2) Toggle debug output for discovery
     "@Gdinv debug discovery@W"

  3) Toggle debug output for all modules
     "@Gdinv debug all@W"

  4) Enable or disable all modules explicitly
     "@Gdinv debug all on@W"
     "@Gdinv debug all off@W"

  5) Toggle debug output for a specific module (example: inv.items)
     "@Gdinv debug inv.items@W"

  6) Enable or disable a specific module
     "@Gdinv debug inv.items on@W"
     "@Gdinv debug inv.items off@W"

  7) Print one aggregate timing report after each equipment-set wear
     "@Gdinv debug wear-timing on@W"
     "@Gdinv debug wear-timing off@W"
]])
end

----------------------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------------------

-- Loaded from inv.init.atActiveDirect after GMCP has supplied the character
-- name and the per-character database is open.

dbot.debug("debug module loaded", "debug")
