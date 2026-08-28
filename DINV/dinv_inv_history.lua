----------------------------------------------------------------------------------------------------
-- INV History Module
-- Searchable, persistent object history backed by the SQLite inventory event journal.
----------------------------------------------------------------------------------------------------

inv = inv or {}
inv.history = inv.history or {}

local history = inv.history
local TERMINAL_ACTIONS = { [3] = true, [7] = true }


local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end


local function formatDate(timestamp)
    local numeric = tonumber(timestamp)
    if not numeric then return "unknown" end
    return os.date("%Y-%m-%d %H:%M:%S", numeric)
end


local function formatDuration(seconds)
    local remaining = math.max(0, math.floor(tonumber(seconds) or 0))
    if remaining < 60 then return "less than a minute" end
    local units = {
        { label = "day", seconds = 86400 },
        { label = "hour", seconds = 3600 },
        { label = "minute", seconds = 60 },
    }
    local parts = {}
    for _, unit in ipairs(units) do
        local value = math.floor(remaining / unit.seconds)
        if value > 0 then
            table.insert(parts, tostring(value) .. " " .. unit.label .. (value == 1 and "" or "s"))
            remaining = remaining - value * unit.seconds
            if #parts == 2 then break end
        end
    end
    return table.concat(parts, ", ")
end


local function statusForAction(action)
    action = tonumber(action)
    if action == 3 then return "left inventory" end
    if action == 7 then return "consumed or rotted" end
    return "currently held"
end


local function displayNameForItem(item)
    local colorName = tostring(item.colorName or "")
    if colorName ~= "" then return colorName end
    return "@C" .. tostring(item.name or "unknown item")
end


local function displayCandidates(searchName, matches, truncated)
    dbot.print('@W  Multiple historical items match "@C' .. tostring(searchName) .. '@W":@w')
    dbot.print("@W")
    dbot.print(string.format("  @C%-12s %5s  %-18s  %-19s  %s@w",
        "ID", "Level", "Status", "Last seen", "Name"))
    for _, item in ipairs(matches or {}) do
        local lastSeen = item.lastEventAt or item.lastSeenAt
        dbot.print(string.format("  @Y%-12s@W %5s  %-18s  %-19s  %s@w",
            tostring(item.objId), tostring(item.level or "-"), statusForAction(item.lastAction),
            formatDate(lastSeen), displayNameForItem(item)))
    end
    if truncated then
        dbot.print("@Y  Only the first 100 matches are shown; use a more specific name.@w")
    end
    dbot.print("@W  Use: @Gdinv history short <id>@W or @Gdinv history complete <id>@w")
end


local function findMatches(searchName)
    if not (DINV and DINV.database and DINV.database.findInventoryHistoryItems) then
        return nil, "inventory history database is unavailable"
    end
    return DINV.database.findInventoryHistoryItems(searchName)
end


local function resolveTarget(target)
    local requested = trim(target)
    if requested == "" then
        dbot.warn("History requires an object ID or item name")
        return nil, nil, DRL_RET_INVALID_PARAM
    end

    if requested:match("^%-?%d+$") then
        local item, itemErr = DINV.database.getInventoryHistoryItem(requested)
        if itemErr then
            dbot.warn("Unable to read inventory history: " .. tostring(itemErr))
            return nil, nil, DRL_RET_INTERNAL_ERROR
        end
        local events, eventsErr = DINV.database.getInventoryHistoryEvents(requested)
        if not events then
            dbot.warn("Unable to read inventory history: " .. tostring(eventsErr))
            return nil, nil, DRL_RET_INTERNAL_ERROR
        end
        if not item and #events == 0 then
            dbot.warn('No inventory history was found for object ID "' .. requested .. '"')
            return nil, nil, DRL_RET_MISSING_ENTRY
        end
        item = item or { objId = requested, name = "unknown item" }
        return item, events, DRL_RET_SUCCESS
    end

    local matches, findErr, _, truncated = findMatches(requested)
    if not matches then
        dbot.warn("Unable to search inventory history: " .. tostring(findErr))
        return nil, nil, DRL_RET_INTERNAL_ERROR
    end
    if #matches == 0 then
        dbot.warn('No historical items match "' .. requested .. '"')
        return nil, nil, DRL_RET_MISSING_ENTRY
    end
    if #matches > 1 then
        displayCandidates(requested, matches, truncated)
        return nil, nil, DRL_RET_SUCCESS
    end
    local item = matches[1]
    local events, eventsErr = DINV.database.getInventoryHistoryEvents(item.objId)
    if not events then
        dbot.warn("Unable to read inventory history: " .. tostring(eventsErr))
        return nil, nil, DRL_RET_INTERNAL_ERROR
    end
    return item, events, DRL_RET_SUCCESS
end


local function buildPossessionSummary(item, events)
    local firstEvent = events[1]
    local trackingStarted = tonumber(item.firstSeenAt)
        or (firstEvent and tonumber(firstEvent.observedAt)) or os.time()
    local currentStart = firstEvent and tonumber(firstEvent.action) == 4
        and nil or trackingStarted
    local firstAcquired
    local totalSeconds = 0
    local periods = 0
    local lastTerminal

    for _, event in ipairs(events) do
        local action = tonumber(event.action)
        local observedAt = tonumber(event.observedAt) or trackingStarted
        if action == 4 then
            if not firstAcquired then firstAcquired = observedAt end
            if not currentStart then
                currentStart = observedAt
            end
        elseif TERMINAL_ACTIONS[action] and currentStart then
            totalSeconds = totalSeconds + math.max(0, observedAt - currentStart)
            periods = periods + 1
            currentStart = nil
            lastTerminal = event
        end
    end

    if currentStart then
        totalSeconds = totalSeconds + math.max(0, os.time() - currentStart)
        periods = periods + 1
    end

    return {
        trackingStarted = trackingStarted,
        firstAcquired = firstAcquired,
        totalSeconds = totalSeconds,
        periods = periods,
        currentlyHeld = currentStart ~= nil,
        lastTerminal = lastTerminal,
        lastEvent = events[#events],
    }
end


function history.find(searchName)
    local requested = trim(searchName)
    if requested == "" then
        dbot.warn("Usage: dinv history find <name>")
        return DRL_RET_INVALID_PARAM
    end
    local matches, findErr, _, truncated = findMatches(requested)
    if not matches then
        dbot.warn("Unable to search inventory history: " .. tostring(findErr))
        return DRL_RET_INTERNAL_ERROR
    end
    if #matches == 0 then
        dbot.warn('No historical items match "' .. requested .. '"')
        return DRL_RET_MISSING_ENTRY
    end
    if #matches > 1 then
        displayCandidates(requested, matches, truncated)
        return DRL_RET_SUCCESS
    end
    return history.displayShort(matches[1].objId)
end


function history.repair(isConfirmed)
    if not (DINV and DINV.database and DINV.database.getInventoryHistoryRepairStatus) then
        dbot.warn("Inventory history repair is unavailable")
        return DRL_RET_UNINITIALIZED
    end
    local status, statusErr = DINV.database.getInventoryHistoryRepairStatus()
    if not status then
        dbot.warn("Unable to inspect inventory history: " .. tostring(statusErr))
        return DRL_RET_INTERNAL_ERROR
    end

    dbot.print("@W")
    dbot.print("@Y  Inventory history repair@W")
    dbot.print("@W  Searchable events: @C" .. tostring(status.linkedEvents) .. "@w")
    dbot.print("@W  Events without a known item name: @C" .. tostring(status.unseededEvents) .. "@w")
    if status.unseededEvents > 0 then
        dbot.print("@W  Unnamed event range: @C" .. formatDate(status.unseededFirstAt) ..
            "@W to @C" .. formatDate(status.unseededLastAt) .. "@w")
    end
    dbot.print("@W  Expiring or unclassified key items: @C" ..
        tostring(status.keyItems or 0) .. "@w")
    if (status.keyItems or 0) > 0 then
        dbot.print("@W    Known expiring keys: @C" .. tostring(status.expiringKeyItems or 0) .. "@w")
        dbot.print("@W    Keys without reliable timer data: @C" ..
            tostring(status.unclassifiedKeyItems or 0) .. "@w")
        dbot.print("@W    Events linked to those keys: @C" .. tostring(status.keyEvents or 0) .. "@w")
    end
    dbot.print("@W  Proven permanent keys preserved: @C" ..
        tostring(status.permanentKeyItems or 0) .. "@w")

    local needsRepair = status.unseededEvents > 0 or (status.keyItems or 0) > 0

    if not isConfirmed then
        dbot.print("@W")
        dbot.print("@W  A confirmed repair removes unnamed events and all history for keys that@w")
        dbot.print("@W  are expiring or cannot be proven permanent from their stored timer data.@w")
        dbot.print("@W  Timerless permanent keys, current inventory, module settings, and@w")
        dbot.print("@W  consumable configuration are preserved.@w")
        if needsRepair then
            dbot.print("@W  A full database backup will be created before any rows are removed.@w")
            dbot.print("@W  To proceed, run: @Gdinv history repair confirm@w")
        else
            dbot.print("@G  No inventory history rows need repair.@w")
        end
        return DRL_RET_SUCCESS
    end

    if not needsRepair then
        dbot.print("@G  No inventory history rows need repair.@w")
        return DRL_RET_SUCCESS
    end
    if not (dbot.backup and dbot.backup.create and dbot.backup.getBackupDir) then
        dbot.warn("History repair was cancelled because SQLite backup support is unavailable")
        return DRL_RET_UNSUPPORTED
    end

    local backupName = "history-repair-" .. os.date("%Y%m%d-%H%M%S")
    local backupRetval = dbot.backup.create(backupName, nil)
    if backupRetval ~= DRL_RET_SUCCESS then
        dbot.warn("History repair was cancelled because the database backup failed")
        return backupRetval
    end
    local repaired, repairResult = DINV.database.repairInventoryHistory()
    if not repaired then
        dbot.warn("History repair failed; the backup was preserved: " .. tostring(repairResult))
        return DRL_RET_INTERNAL_ERROR
    end

    local backupFile = tostring(dbot.backup.getBackupDir() or "") ..
        backupName .. "/dinv.db"
    local removed = type(repairResult) == "table" and repairResult or {
        unseededEvents = tonumber(repairResult) or 0,
        keyItems = 0,
        keyEvents = 0,
    }
    dbot.print("@G  Inventory history repair complete.@w")
    dbot.print("@W  Removed unnamed events: @C" .. tostring(removed.unseededEvents or 0) .. "@w")
    dbot.print("@W  Removed key history items: @C" .. tostring(removed.keyItems or 0) .. "@w")
    dbot.print("@W  Removed key history events: @C" .. tostring(removed.keyEvents or 0) .. "@w")
    dbot.print("@W  Backup: @C" .. backupFile .. "@w")
    return DRL_RET_SUCCESS
end


function history.displayShort(target)
    local item, events, retval = resolveTarget(target)
    if not item then return retval end
    local summary = buildPossessionSummary(item, events)
    local displayName = displayNameForItem(item)

    dbot.print("@W")
    dbot.print("@W  History for " .. displayName ..
        "@W [@Y" .. tostring(item.objId) .. "@W] @w(local time)")
    if summary.firstAcquired then
        dbot.print("@W  First acquired: @C" .. formatDate(summary.firstAcquired) .. "@w")
    else
        dbot.print("@W  Tracking began: @C" .. formatDate(summary.trackingStarted) .. "@w")
    end
    dbot.print("@W  Time possessed: @C" .. formatDuration(summary.totalSeconds) .. "@w")
    if summary.periods > 1 then
        dbot.print("@W  Possession periods: @C" .. tostring(summary.periods) .. "@w")
    end
    if summary.currentlyHeld then
        dbot.print("@W  Status: @Gcurrently held@w")
    elseif summary.lastTerminal then
        dbot.print("@W  " .. (tonumber(summary.lastTerminal.action) == 7
            and "Consumed or rotted: @C" or "Left inventory: @C") ..
            formatDate(summary.lastTerminal.observedAt) .. "@w")
    else
        dbot.print("@W  Status: @Cunknown@w")
    end
    return DRL_RET_SUCCESS
end


local function containerDescription(event)
    local containerId = tostring(event.containerId or "")
    if event.containerColorName and event.containerColorName ~= "" then
        return '"' .. tostring(event.containerColorName) .. '@C" [' .. containerId .. "]"
    end
    if event.containerName and event.containerName ~= "" then
        return '"' .. tostring(event.containerName) .. '" [' .. containerId .. "]"
    end
    if containerId == "" or containerId == "0" or containerId == "-1" then
        return "a container"
    end
    return "container [" .. containerId .. "]"
end


local function wearDescription(value)
    local numeric = tonumber(value)
    if numeric and inv.wearLoc and inv.wearLoc[numeric] then
        return tostring(inv.wearLoc[numeric])
    end
    local text = tostring(value or "")
    return text ~= "" and text or "an unknown slot"
end


local function describeEvent(event)
    local action = tonumber(event.action)
    if action == 1 then return "Removed from " .. wearDescription(event.wearLocation) end
    if action == 2 then return "Worn on " .. wearDescription(event.wearLocation) end
    if action == 3 then return "Left inventory" end
    if action == 4 then return "Acquired" end
    if action == 5 then return "Taken from " .. containerDescription(event) end
    if action == 6 then return "Put into " .. containerDescription(event) end
    if action == 7 then return "Consumed or rotted" end
    if action == 9 then return "Put into vault" end
    if action == 10 then return "Removed from vault" end
    if action == 11 then return "Put into keyring" end
    if action == 12 then return "Removed from keyring" end
    return "Inventory event " .. tostring(action or event.reason or "unknown")
end


function history.displayComplete(target)
    local item, events, retval = resolveTarget(target)
    if not item then return retval end
    local displayName = displayNameForItem(item)

    dbot.print("@W")
    dbot.print("@W  Complete history for " .. displayName ..
        "@W [@Y" .. tostring(item.objId) .. "@W] @w(local time)")
    if #events == 0 then
        dbot.print("@W  No movement has been recorded since tracking began on @C" ..
            formatDate(item.firstSeenAt) .. "@w")
        return DRL_RET_SUCCESS
    end
    for _, event in ipairs(events) do
        dbot.print("@W  " .. formatDate(event.observedAt) .. "  @C" .. describeEvent(event) .. "@w")
    end
    return DRL_RET_SUCCESS
end


history._formatDate = formatDate
history._formatDuration = formatDuration
history._buildPossessionSummary = buildPossessionSummary
history._describeEvent = describeEvent

dbot.debug("inv.history module loaded", "inv.history")
