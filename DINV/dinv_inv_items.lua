----------------------------------------------------------------------------------------------------
-- INV Items Module
-- Core inventory table management - build, refresh, search, display
----------------------------------------------------------------------------------------------------

-- Defensive initialization
inv = inv or {}
inv.items = inv.items or {}
inv.items.init = inv.items.init or {}
inv.items.table = inv.items.table or {}
inv.items.detached = inv.items.detached or {}
inv.items.pendingRemoved = inv.items.pendingRemoved or {}
inv.items.timer = inv.items.timer or { name = "drlInvItemsRefreshTimer" }
inv.items.stateName = inv.items.stateName or "inv-items.state"
inv.items.keepSync = inv.items.keepSync or {
    active = false,
    scheduled = false,
    pending = false,
}

----------------------------------------------------------------------------------------------------
-- Timer Configuration
----------------------------------------------------------------------------------------------------

inv.items.timer = inv.items.timer or {}
inv.items.timer.name = inv.items.timer.name or "drlInvItemsRefreshTimer"
inv.items.timer.invmonSaveName = inv.items.timer.invmonSaveName or "drlInvItemsInvmonSaveTimer"
inv.items.timer.keepSyncStartName = inv.items.timer.keepSyncStartName or "drlInvItemsKeepSyncStartTimer"
inv.items.timer.keepSyncTimeoutName = inv.items.timer.keepSyncTimeoutName or "drlInvItemsKeepSyncTimeoutTimer"
inv.items.timer.databaseBatchName = inv.items.timer.databaseBatchName or "drlInvItemsDatabaseBatchTimer"
inv.items.timer.refreshMin = 5
inv.items.timer.refreshEagerSec = 0
inv.items.timer.refreshNextTs = nil

----------------------------------------------------------------------------------------------------
-- Display Tracking
----------------------------------------------------------------------------------------------------

inv.items.displayLastType = ""
inv.items.pendingForget = inv.items.pendingForget or nil

----------------------------------------------------------------------------------------------------
-- Progress Tracking
----------------------------------------------------------------------------------------------------

inv.items.progress = inv.items.progress or {
    stage = "Idle",
    current = 0,
    total = 0,
    startTime = 0,
    lastUpdate = 0,
}
inv.items.progress.reportMode = inv.items.progress.reportMode or "classic"
if inv.items.progress.reportMode ~= "classic" and inv.items.progress.reportMode ~= "inline"
    and inv.items.progress.reportMode ~= "off" then
    inv.items.progress.reportMode = "classic"
end
inv.items.progress.inlineActive = inv.items.progress.inlineActive or false
inv.items.progress.inlineLineNum = inv.items.progress.inlineLineNum or nil
inv.items.progress.inlinePlainText = inv.items.progress.inlinePlainText or nil


-- Refresh identify follow-up state
inv.items.refreshIdentifyPartials = inv.items.refreshIdentifyPartials or false
inv.items.partialIdentifyMode = inv.items.partialIdentifyMode or false
inv.items.identifyPartialOnly = inv.items.identifyPartialOnly or false
inv.items.deferredIdentifyQueue = inv.items.deferredIdentifyQueue or {}
inv.items.eventSequence = inv.items.eventSequence or 0
inv.items.refreshGeneration = inv.items.refreshGeneration or 0
inv.items.databaseBuildId = inv.items.databaseBuildId or nil
inv.items.databaseBuildBatchSize = 10
inv.items.databaseBuildBatchSeconds = 10
inv.items.databaseBuildIdentifiedSinceFlush = 0
inv.items.eventTombstones = inv.items.eventTombstones or {}
inv.items.workflowRemovalEvents = inv.items.workflowRemovalEvents or {}

function inv.items.getProgressString()
    local p = inv.items.progress
    if p.total == 0 then
        return p.stage or "Idle"
    end
    local pct = math.floor((p.current / p.total) * 100)
    return string.format("%s: %d/%d (%d%%)", p.stage, p.current, p.total, pct)
end

function inv.items.getReportMode()
    if inv.config and inv.config.getReportMode then
        local configured = inv.config.getReportMode()
        if configured == "classic" or configured == "inline" or configured == "off" then
            inv.items.progress.reportMode = configured
            return configured
        end
    end
    return inv.items.progress.reportMode or "classic"
end

function inv.items.setReportMode(mode)
    local normalized = tostring(mode or ""):lower()
    if normalized ~= "classic" and normalized ~= "inline" and normalized ~= "off" then
        return DRL_RET_INVALID_PARAM
    end

    inv.items.clearInlineProgress()
    inv.items.progress.reportMode = normalized

    if inv.config and inv.config.setReportMode then
        return inv.config.setReportMode(normalized)
    end
    return DRL_RET_SUCCESS
end

function inv.items.finalizeInlineProgress()
    if not inv.items.progress then
        return
    end
    inv.items.progress.inlineActive = false
    inv.items.progress.inlineLineNum = nil
    inv.items.progress.inlinePlainText = nil
end

-- Returns true iff `text` is present anywhere in the last `depth` buffer lines.
local function bufferContains(text, depth)
    if not text or text == "" or not (getLines and getLineCount) then
        return false
    end
    local totalLines = getLineCount() or 0
    if totalLines <= 0 then
        return false
    end
    local searchStart = math.max(0, totalLines - (depth or 200))
    local ok, lines = pcall(getLines, "main", searchStart, totalLines)
    if not ok or type(lines) ~= "table" then
        return false
    end
    for _, lineText in ipairs(lines) do
        if lineText and lineText:find(text, 1, true) then
            return true
        end
    end
    return false
end

local function clearMainConsoleLine(lineNum, targetText)
    if type(lineNum) ~= "number" or lineNum < 0 or not moveCursor then
        return false
    end

    if deleteLine then
        if moveCursor("main", 0, lineNum) then
            pcall(deleteLine)
            if not bufferContains(targetText) then
                return true
            end
        end
    end

    if selectCurrentLine and replace then
        if moveCursor("main", 0, lineNum) then
            selectCurrentLine("main")
            pcall(replace, "")
            if not bufferContains(targetText) then
                return true
            end
        end
    end

    return false
end

function inv.items.deleteInlineProgressLine()
    if not (inv.items.progress and inv.items.progress.inlineActive) then
        return false
    end

    if not (getLines and getLineCount) then
        return false
    end

    local targetText = inv.items.progress.inlinePlainText
    if not targetText or targetText == "" then
        return false
    end

    local totalLines = getLineCount() or 0
    if totalLines <= 0 then
        return false
    end

    -- Search a generous window of recent buffer lines for the tracked
    -- progress line. MUD output can arrive between identify steps, so
    -- the stored line number drifts; a textual search is authoritative.
    local searchDepth = 200
    local searchStart = math.max(0, totalLines - searchDepth)
    local lines = getLines("main", searchStart, totalLines) or {}

    for lineNum = totalLines, searchStart, -1 do
        local idx = (lineNum - searchStart) + 1
        local lineText = lines[idx]
        if lineText and lineText:find(targetText, 1, true) then
            if clearMainConsoleLine(lineNum, targetText) then
                return true
            end
            -- Clearing this match failed; keep scanning in case an
            -- earlier occurrence can be cleared instead.
        end
    end

    return false
end

function inv.items.clearInlineProgress()
    if not (inv.items.progress and inv.items.progress.inlineActive) then
        return
    end

    inv.items.deleteInlineProgressLine()

    inv.items.finalizeInlineProgress()
end

function inv.items.showProgress(stage, current, total, itemName)
    inv.items.progress.stage = stage
    inv.items.progress.current = current
    inv.items.progress.total = total

    local mode = inv.items.getReportMode()
    if mode == "off" then
        inv.items.clearInlineProgress()
        return
    end

    local pct = 0
    if total > 0 then
        pct = math.floor((current / total) * 100)
    end

    -- Determine bar color based on percentage (whole bar is one color)
    local barColor
    if pct < 33 then
        barColor = "@R"  -- Red for 0-32%
    elseif pct < 66 then
        barColor = "@Y"  -- Yellow for 33-65%
    else
        barColor = "@G"  -- Green for 66-100%
    end

    -- Create progress bar (20 chars wide)
    local barWidth = 20
    local filled = math.floor((pct / 100) * barWidth)
    local empty = barWidth - filled
    local bar = barColor .. string.rep("=", filled) .. "@w" .. string.rep("-", empty)

    -- Build message with Aardwolf color codes
    local msg = string.format("@w[%s@w] @W%d%% @w(%d/%d)", bar, pct, current, total)

    local cleanedItemName = nil
    if itemName then
        -- Strip enchant text from display name
        local displayName = itemName:gsub("%s+[A-Z][a-z]+%s+%+?%-?%d+%s*%(removable[^%)]*%)%s*", "")
        displayName = displayName:gsub("%s+%(removable[^%)]*%)%s*", "")
        cleanedItemName = dbot.stripColors(displayName)
        msg = msg .. " " .. displayName
    end

    local plainMsg = dbot.stripColors(msg)
    local converted = dbot.convertColors and dbot.convertColors(msg) or msg
    local fullMsg = "<cyan>[DINV] " .. stage .. ": <reset>" .. converted

    if mode == "inline"
        and cleanedItemName and cleanedItemName ~= ""
        and not plainMsg:find(cleanedItemName, 1, true) then
        fullMsg = fullMsg .. " <reset>" .. cleanedItemName
        plainMsg = plainMsg .. " " .. cleanedItemName
    end

    if mode == "inline" then
        local hadActive = inv.items.progress.inlineActive
        local removed = hadActive and inv.items.deleteInlineProgressLine() or false
        if hadActive and not removed then
            inv.items.finalizeInlineProgress()
        end

        cecho(fullMsg .. "\n")
        inv.items.progress.inlineActive = true
        local lineCount = getLineCount and getLineCount() or nil
        if type(lineCount) == "number" and lineCount > 0 then
            inv.items.progress.inlineLineNum = lineCount - 1
        else
            inv.items.progress.inlineLineNum = nil
        end
        inv.items.progress.inlinePlainText = "[DINV] " .. stage .. ": " .. plainMsg
        return
    end

    inv.items.clearInlineProgress()
    cecho(fullMsg .. "\n")
end

----------------------------------------------------------------------------------------------------
-- Data Parsing Helpers
----------------------------------------------------------------------------------------------------

function sendSilent(cmd)
    if send then
        send(cmd, false)
    end
end

function inv.items.runReportFromLink(objId)
    local itemId = tostring(objId or "")
    if itemId == "" then
        return
    end

    if inv.report and inv.report.reportItemIds then
        return inv.report.reportItemIds({ itemId })
    else
        dbot.warn("inv.items.runReportFromLink: report module is unavailable")
        return DRL_RET_UNINITIALIZED
    end
end

-- Item type lookup table (numeric ID -> string name)
inv.items.typeStr = {
    [1]  = "Light",
    [2]  = "Scroll",
    [3]  = "Wand",
    [4]  = "Stave",
    [5]  = "Weapon",
    [6]  = "Treasure",
    [7]  = "Armor",
    [8]  = "Potion",
    [9]  = "Furniture",
    [10] = "Trash",
    [11] = "Container",
    [12] = "Drink Container",
    [13] = "Key",
    [14] = "Food",
    [15] = "Boat",
    [16] = "Mob Corpse",
    [17] = "Player Corpse",
    [18] = "Fountain",
    [19] = "Pill",
    [20] = "Portal",
    [21] = "Beacon",
    [22] = "Gift Card",
    [23] = "Unused",
    [24] = "Raw Material",
    [25] = "Campfire",
    [26] = "Forge",
    [27] = "Runestone",
}

-- Reverse lookup (string name -> numeric ID)
inv.items.typeId = {
    ["Light"] = 1,
    ["Scroll"] = 2,
    ["Wand"] = 3,
    ["Stave"] = 4,
    ["Weapon"] = 5,
    ["Treasure"] = 6,
    ["Armor"] = 7,
    ["Potion"] = 8,
    ["Furniture"] = 9,
    ["Trash"] = 10,
    ["Container"] = 11,
    ["Drink Container"] = 12,
    ["Key"] = 13,
    ["Food"] = 14,
    ["Boat"] = 15,
    ["Mob Corpse"] = 16,
    ["Player Corpse"] = 17,
    ["Fountain"] = 18,
    ["Pill"] = 19,
    ["Portal"] = 20,
    ["Beacon"] = 21,
    ["Gift Card"] = 22,
    ["Unused"] = 23,
    ["Raw Material"] = 24,
    ["Campfire"] = 25,
    ["Forge"] = 26,
    ["Runestone"] = 27,
}

inv.items.currentIdentifyId = nil
inv.items.identifyFence = "DINV identify fence"
inv.items.identifyContinuationKey = nil
inv.items.identifyContinuation = nil
inv.items.buildInProgress = false
inv.items.buildEndTag = nil
inv.items.discoveryComplete = false
inv.items.identifyQueue = {}
inv.items.identifyInProgress = false
inv.items.identifyCurrentId = nil
inv.items.identifyCurrentContainer = nil
inv.items.identifyWaitForInvmon = nil
inv.items.identifyWaitForFence = nil
inv.items.identifyResetId = nil
inv.items.identifyCreatedMissing = inv.items.identifyCreatedMissing or {}
inv.items.identifySawOutput = inv.items.identifySawOutput or {}
inv.items.identifyHydratedFromInvdata = inv.items.identifyHydratedFromInvdata or {}
inv.items.identifyHydrateInProgress = inv.items.identifyHydrateInProgress or false
inv.items.identifyHydrateId = inv.items.identifyHydrateId or nil
inv.items.identifyHydrateSource = inv.items.identifyHydrateSource or nil
inv.items.identifyHydrateFound = inv.items.identifyHydrateFound or false
inv.items.identifyHydratePreviousState = inv.items.identifyHydratePreviousState or nil
inv.items.identifyHydrateTimerName = inv.items.identifyHydrateTimerName or nil
inv.items.discoveryStage = 0
inv.items.discoveryContainers = {}
inv.items.containerIndex = 0
inv.items.inEqdata = false
inv.items.inInvdata = false
inv.items.eqdataSeen = {}

inv.items.identifyAdditiveFields = {
    invStatFieldHitroll,
    invStatFieldDamroll,
    invStatFieldStr,
    invStatFieldInt,
    invStatFieldWis,
    invStatFieldDex,
    invStatFieldCon,
    invStatFieldLuck,
    invStatFieldHp,
    invStatFieldMana,
    invStatFieldMoves,
    invStatFieldAllPhys,
    invStatFieldAllMagic,
    invStatFieldSlash,
    invStatFieldPierce,
    invStatFieldBash,
    invStatFieldAcid,
    invStatFieldCold,
    invStatFieldEnergy,
    invStatFieldHoly,
    invStatFieldElectric,
    invStatFieldNegative,
    invStatFieldShadow,
    invStatFieldMagic,
    invStatFieldAir,
    invStatFieldEarth,
    invStatFieldFire,
    invStatFieldLight,
    invStatFieldMental,
    invStatFieldSonic,
    invStatFieldWater,
    invStatFieldPoison,
    invStatFieldDisease,
}

function inv.items.ensureKeywordsField(item)
    if not item or not item.stats then
        return
    end

    -- Preserve keywords exactly as parsed from identify output.
    -- No normalization or name-derived fallback should happen here.
end

function inv.items.resetIdentifyStats(item)
    if not item or not item.stats then
        return
    end

    for _, field in ipairs(inv.items.identifyAdditiveFields) do
        item.stats[field] = 0
    end
end

function inv.items.resetIdentifyEnchantFields(item)
    if not item or not item.stats then
        return
    end

    item.stats[invStatFieldEnchants] = nil
    item.stats[invStatFieldIlluminate] = nil
    item.stats[invStatFieldResonate] = nil
    item.stats[invStatFieldSolidify] = nil
end

----------------------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------------------

function inv.items.init.atInstall()
    return DRL_RET_SUCCESS
end

function inv.items.init.atActive()
    if not DINV or not DINV.database then
        dbot.warn("inv.items.init.atActive: SQLite database module is not loaded")
        return DRL_RET_INTERNAL_ERROR
    end

    local databaseOk, databaseResult = DINV.database.initialize()
    if not databaseOk then
        dbot.warn("inv.items.init.atActive: Failed to initialize SQLite persistence: " .. tostring(databaseResult))
        return DRL_RET_INTERNAL_ERROR
    end

    local retval = inv.items.load()
    if retval ~= DRL_RET_SUCCESS then
        dbot.warn("inv.items.init.atActive: Failed to load items data from SQLite: " ..
                  dbot.retval.getString(retval))
    end
    inv.items.eventSequence = math.max(
        tonumber(inv.items.eventSequence) or 0,
        tonumber(DINV.database.getMaxEventSequence and DINV.database.getMaxEventSequence()) or 0
    )
    
    -- Set up refresh timer if enabled
    if inv.config.isRefreshEnabled() then
        inv.items.refreshOn(inv.config.getRefreshPeriod(), 0)
    end
    
    return retval
end

function inv.items.fini(doSaveState)
    local retval = DRL_RET_SUCCESS

    -- A Mudlet profile can reload or reconnect as another character while a
    -- workflow is in flight. Resolve that workflow against the old database
    -- before the connection is closed, then clear every runtime-only marker so
    -- it cannot redirect writes into the next character's build staging.
    if inv.items.refreshInProgress and inv.items.refreshValidation then
        inv.items.abortInvalidRefresh({ quiet = true })
    elseif inv.items.refreshInProgress then
        inv.items.refreshInProgress = false
        inv.items.suppressDatabaseWrites = false
        inv.items.applyWorkflowRemovalEvents("shutdown_refresh")
    end
    if inv.items.buildInProgress or inv.items.identifyInProgress then
        inv.items.buildAbort({ quiet = true, interrupt = true })
    elseif inv.items.databaseBuildId and DINV and DINV.database
        and DINV.database.interruptBuild then
        DINV.database.interruptBuild(inv.items.databaseBuildId)
        inv.items.databaseBuildId = nil
    end

    if doSaveState then
        retval = inv.items.save()
        if retval ~= DRL_RET_SUCCESS and retval ~= DRL_RET_UNINITIALIZED then
            dbot.warn("inv.items.fini: Failed to save inv.items module data: " ..
                      dbot.retval.getString(retval))
        end
    end
    
    -- Clean up timer
    dbot.deleteTimer(inv.items.timer.name)
    dbot.deleteTimer(inv.items.timer.invmonSaveName)
    dbot.deleteTimer(inv.items.timer.keepSyncStartName)
    dbot.deleteTimer(inv.items.timer.keepSyncTimeoutName)
    dbot.deleteTimer(inv.items.timer.databaseBatchName)

    inv.items.refreshInProgress = false
    inv.items.identifyInProgress = false
    inv.items.buildInProgress = false
    inv.items.suppressDatabaseWrites = false
    inv.items.databaseBuildId = nil
    inv.items.databaseBuildIdentifiedSinceFlush = 0
    inv.items.refreshValidation = nil
    inv.items.refreshSeen = nil
    inv.items.buildOriginalTable = nil
    inv.items.buildOriginalDetached = nil
    inv.items.buildOriginalPendingRemoved = nil
    inv.items.buildStartEventSequence = nil
    inv.items.workflowRemovalEvents = {}
    inv.items.eventTombstones = {}
    inv.items.pendingInvmonSave = nil
    inv.items.pendingRemoval = {}
    inv.items.pendingRemoved = {}
    inv.items._invmonLastPayload = nil
    inv.items._invmonLastAt = nil

    return retval
end

----------------------------------------------------------------------------------------------------
-- Save/Load/Reset
----------------------------------------------------------------------------------------------------

function inv.items.save(options)
    if inv.items.table == nil then
        return inv.items.reset()
    end

    if inv.items.refreshInProgress and inv.items.suppressDatabaseWrites then
        inv.items.pendingInvmonSave = true
        return DRL_RET_SUCCESS, {}
    end

    if not DINV or not DINV.database or not DINV.database.syncItems then
        return DRL_RET_INTERNAL_ERROR
    end
    local target = inv.items.databaseBuildId and "build" or "active"
    local identifiedBatchCount = tonumber(inv.items.databaseBuildIdentifiedSinceFlush) or 0
    local databaseTimingWall, databaseTimingCpu = nil, nil
    if DINV.debug and DINV.debug.beginWearTimingSample then
        databaseTimingWall, databaseTimingCpu = DINV.debug.beginWearTimingSample()
    end
    local ok, result, purgedPendingIds = DINV.database.syncItems(inv.items.table, target, options)
    if DINV.debug and DINV.debug.recordWearTimingDatabase then
        DINV.debug.recordWearTimingDatabase(databaseTimingWall, databaseTimingCpu)
    end
    if not ok then
        dbot.warn("inv.items.save: SQLite batch failed: " .. tostring(result))
        return DRL_RET_INTERNAL_ERROR
    end
    if inv.items.databaseBuildId and identifiedBatchCount > 0
        and DINV.database.noteBuildIdentified then
        local noted, noteErr = DINV.database.noteBuildIdentified(
            inv.items.databaseBuildId,
            identifiedBatchCount
        )
        if not noted then
            dbot.warn("inv.items.save: Unable to record build progress: " .. tostring(noteErr))
            return DRL_RET_INTERNAL_ERROR
        end
    end
    inv.items.databaseBuildIdentifiedSinceFlush = 0
    return DRL_RET_SUCCESS, purgedPendingIds or {}
end

function inv.items.normalizePersistentItem(item)
    local stats = item and item.stats
    if not stats then return false end
    local changed = false
    local loc = tostring(stats[invStatFieldLocation] or "")
    local wornLoc = tostring(stats[invStatFieldWorn] or "")

    if loc == tostring(invItemLocWorn or "worn")
        and wornLoc ~= "" and wornLoc ~= "undefined"
        and wornLoc ~= tostring(invItemWornNotWorn or "not-worn") then
        local wearNum = inv.wearLocId and inv.wearLocId[wornLoc]
        if wearNum ~= nil then
            stats[invStatFieldLocation] = tostring(wearNum)
            loc = tostring(wearNum)
            changed = true
        end
    end

    local lastStored = tostring(stats[invStatFieldLastStored] or "")
    if lastStored ~= "" and not inv.items.isStorageLocation(lastStored) then
        stats[invStatFieldLastStored] = ""
        lastStored = ""
        changed = true
    end
    if loc ~= "" and inv.items.isStorageLocation(loc)
        and tostring(stats[invStatFieldLastStored] or "") ~= loc then
        stats[invStatFieldLastStored] = loc
        lastStored = loc
        changed = true
    end
    if lastStored == tostring(invItemLocKeyring or "keyring") and loc == "unknown" then
        stats[invStatFieldLocation] = invItemLocKeyring or "keyring"
        stats[invStatFieldContainer] = invItemLocKeyring or "keyring"
        changed = true
    end
    return changed
end

function inv.items.loadPersistentItemsTable()
    if not DINV or not DINV.database then
        return nil
    end
    local items = DINV.database.loadActiveItems()
    for _, item in pairs(items or {}) do
        inv.items.normalizePersistentItem(item)
    end
    return items
end

function inv.items.lookupPersistentItem(objId)
    if not objId or objId == "" then
        return nil
    end

    local key = tostring(objId)
    local entry = (inv.items.table and inv.items.table[key])
        or (inv.items.detached and inv.items.detached[key])
        or (inv.items.pendingRemoved and inv.items.pendingRemoved[key])
    if not entry and not inv.items.databaseBuildId
        and DINV and DINV.database and DINV.database.loadActiveItem then
        entry = DINV.database.loadActiveItem(key)
    end
    if entry then inv.items.normalizePersistentItem(entry) end
    if entry then
        dbot.debug("inv.items: persistence hit for objId=" .. tostring(objId), "inv.items")
    else
        dbot.debug("inv.items: persistence miss for objId=" .. tostring(objId), "inv.items")
    end
    return entry
end

function inv.items.load()
    if not DINV or not DINV.database then
        return DRL_RET_INTERNAL_ERROR
    end
    local active, activeErr = DINV.database.loadActiveItems()
    if not active then
        dbot.warn("inv.items.load: " .. tostring(activeErr))
        return DRL_RET_INTERNAL_ERROR
    end
    local detached, detachedErr = DINV.database.loadDetachedItems()
    if not detached then
        dbot.warn("inv.items.load detached: " .. tostring(detachedErr))
        return DRL_RET_INTERNAL_ERROR
    end
    local pendingRemoved, pendingErr = DINV.database.loadPendingRemovedItems()
    if not pendingRemoved then
        dbot.warn("inv.items.load pending removals: " .. tostring(pendingErr))
        return DRL_RET_INTERNAL_ERROR
    end
    local normalized = false
    for _, item in pairs(active) do
        normalized = inv.items.normalizePersistentItem(item) or normalized
    end
    for _, item in pairs(pendingRemoved) do
        normalized = inv.items.normalizePersistentItem(item) or normalized
    end
    inv.items.table = active
    inv.items.detached = detached
    inv.items.pendingRemoved = pendingRemoved
    inv.items.pendingForget = nil
    if normalized then inv.items.save() end
    return DRL_RET_SUCCESS
end

function inv.items.reset()
    inv.items.table = {}
    inv.items.pendingForget = nil
    return DRL_RET_SUCCESS
end

-- One-shot: normalize legacy worn values (nil/""/"undefined") to the sentinel and save.
function inv.items.normalizeWornState()
    if not inv.items.table then
        cecho("<yellow>[DINV] No items loaded; nothing to normalize.\n")
        return 0
    end
    local changed = 0
    for _, entry in pairs(inv.items.table) do
        local stats = entry and entry.stats
        if stats then
            local rawWorn = stats[invStatFieldWorn]
            if rawWorn == nil or rawWorn == "" or rawWorn == "undefined" then
                stats[invStatFieldWorn] = invItemWornNotWorn
                changed = changed + 1
            end
        end
    end
    if changed > 0 then
        inv.items.save()
    end
    cecho(string.format("<cyan>[DINV] Normalized %d item(s) to '%s'.\n", changed, invItemWornNotWorn))
    return changed
end

function inv.items.clearPendingForget()
    inv.items.pendingForget = nil
end

function inv.items.setPendingForget(query, itemIds)
    local staged = {}
    for _, objId in ipairs(itemIds or {}) do
        table.insert(staged, tostring(objId))
    end
    inv.items.pendingForget = {
        query = tostring(query or ""),
        itemIds = staged,
        count = #staged,
    }
end

function inv.items.getPendingForget()
    return inv.items.pendingForget
end

function inv.items.scheduleSaveFromInvmon()
    if inv.items.buildInProgress or inv.items.refreshInProgress or inv.items.identifyInProgress then
        inv.items.pendingInvmonSave = true
        return DRL_RET_SUCCESS
    end

    if not inv.items.save or not tempTimer then
        return DRL_RET_SUCCESS
    end

    dbot.deleteTimer(inv.items.timer.invmonSaveName)
    dbot.timers[inv.items.timer.invmonSaveName] = tempTimer(0.5, function()
        if not inv.items.buildInProgress and not inv.items.refreshInProgress and not inv.items.identifyInProgress then
            inv.items.save()
        end
    end)

    return DRL_RET_SUCCESS
end

function inv.items.isKeepFlagSyncBusy()
    return inv.items.buildInProgress
        or inv.items.refreshInProgress
        or inv.items.identifyInProgress
        or inv.items.identifyHydrateInProgress
        or inv.items.inEqdata
        or inv.items.inInvdata
        or (inv.organize and inv.organize.runPkg ~= nil)
end

inv.items.keepFlagSyncTimeoutSeconds = inv.items.keepFlagSyncTimeoutSeconds or 5

function inv.items.rememberKeepFlagForSync(objId, item)
    local sync = inv.items.keepSync
    local key = tostring(objId or "")
    if not sync or not sync.active or key == "" or not item then
        return
    end

    sync.originalKeepFlags = sync.originalKeepFlags or {}
    if sync.originalKeepFlags[key] ~= nil then
        return
    end

    item.stats = item.stats or {}
    local value = item.stats[invStatFieldKeepflag]
    sync.originalKeepFlags[key] = {
        hadValue = value ~= nil,
        value = value,
    }
end

function inv.items.rollbackKeepFlagSync()
    local sync = inv.items.keepSync
    if not sync then
        return
    end

    for objId, original in pairs(sync.originalKeepFlags or {}) do
        local item = inv.items.getItem(objId)
        if item then
            item.stats = item.stats or {}
            if original.hadValue then
                item.stats[invStatFieldKeepflag] = original.value
            else
                item.stats[invStatFieldKeepflag] = nil
            end
            inv.items.setItem(objId, item, { silentApi = true })
        end
    end

    sync.originalKeepFlags = nil
end

function inv.items.armKeepFlagSyncTimeout()
    local sync = inv.items.keepSync
    if not sync or not sync.active or not tempTimer then
        return
    end

    dbot.deleteTimer(inv.items.timer.keepSyncTimeoutName)
    local timeoutSeconds = tonumber(inv.items.keepFlagSyncTimeoutSeconds) or 5
    dbot.timers[inv.items.timer.keepSyncTimeoutName] = tempTimer(timeoutSeconds, function()
        if not sync.active then
            return
        end

        inv.items.rollbackKeepFlagSync()
        sync.active = false
        sync.changed = false
        inv.items.inInvdata = false
        inv.items.currentContainerId = nil
        if DINV and DINV.discovery then
            DINV.discovery.currentSection = nil
            DINV.discovery.currentContainerId = nil
            DINV.discovery.keepFlagChanged = false
        end
        dbot.debug(
            "Keep flag invdata synchronization timed out after " ..
                tostring(timeoutSeconds) .. " seconds of inactivity; partial changes were rolled back",
            "inv.items"
        )
        if sync.pending then
            inv.items.maybeStartKeepFlagSync()
        end
    end)
end

function inv.items.maybeStartKeepFlagSync()
    local sync = inv.items.keepSync
    if not sync or not sync.pending or sync.active or sync.scheduled then
        return
    end
    if inv.items.isKeepFlagSyncBusy() then
        return
    end

    sync.pending = false
    sync.scheduled = true
    dbot.deleteTimer(inv.items.timer.keepSyncStartName)

    local function startSync()
        sync.scheduled = false
        if inv.items.isKeepFlagSyncBusy() then
            sync.pending = true
            return
        end

        -- Commands issued during the short settle window are covered by this
        -- scan. Commands arriving after the scan starts set pending again.
        sync.pending = false
        sync.active = true
        sync.changed = false
        sync.originalKeepFlags = {}
        inv.items.expectedInvdataContainerId = nil
        inv.items.awaitingInvdataContainerId = nil

        if inv.items.sendDiscoveryCommand then
            inv.items.sendDiscoveryCommand("invdata")
        else
            sendSilent("invdata")
        end

        inv.items.armKeepFlagSyncTimeout()
    end

    if tempTimer then
        dbot.timers[inv.items.timer.keepSyncStartName] = tempTimer(0.2, startSync)
    else
        startSync()
    end
end

function inv.items.requestKeepFlagSync()
    inv.items.keepSync = inv.items.keepSync or {
        active = false,
        scheduled = false,
        pending = false,
    }
    inv.items.keepSync.pending = true
    inv.items.maybeStartKeepFlagSync()
end

function inv.items.completeKeepFlagSync(changed)
    local sync = inv.items.keepSync
    if not sync or not sync.active then
        return false
    end

    dbot.deleteTimer(inv.items.timer.keepSyncTimeoutName)
    sync.active = false
    sync.changed = changed == true
    sync.originalKeepFlags = nil

    if sync.changed and inv.items.save then
        inv.items.save()
    end

    sync.changed = false
    if sync.pending then
        inv.items.maybeStartKeepFlagSync()
    end
    return true
end

function inv.items.cancelPendingRemoval(objId)
    local key = tostring(objId or "")
    if key == "" then
        return
    end

    local pending = inv.items.pendingRemoval and inv.items.pendingRemoval[key]
    if not pending then
        return
    end

    if pending.timerName and dbot and dbot.deleteTimer then
        dbot.deleteTimer(pending.timerName)
    end
    inv.items.pendingRemoval[key] = nil
end

function inv.items.schedulePendingRemoval(objId, source)
    local key = tostring(objId or "")
    if key == "" then
        return
    end

    inv.items.pendingRemoval = inv.items.pendingRemoval or {}
    inv.items.cancelPendingRemoval(key)

    local timerName = "inv.items.pendingRemoval." .. key
    inv.items.pendingRemoval[key] = {
        source = tostring(source or "unknown"),
        timerName = timerName,
        createdAt = os.time(),
    }

    if not tempTimer then
        inv.items.removeItemAndSaveNow(key, "pending_removed_from_inventory")
        inv.items.pendingRemoval[key] = nil
        return
    end

    dbot.timers[timerName] = tempTimer(1.5, function()
        local pending = inv.items.pendingRemoval and inv.items.pendingRemoval[key]
        if not pending then
            return
        end

        -- During refresh/build/identify, we should never hard-delete from invmon action 3,
        -- because container operations can emit transient remove/add sequences.
        if inv.items.buildInProgress or inv.items.refreshInProgress or inv.items.identifyInProgress then
            local item = inv.items.getItem(key)
            if item and item.stats then
                if not inv.items.normalizeKeyringLocation(item) then
                    item.stats[invStatFieldWorn] = invItemWornNotWorn
                    item.stats[invStatFieldContainer] = ""
                    inv.items.updateLocation(item, "unknown")
                end
                inv.items.setItem(key, item)
                inv.items.scheduleSaveFromInvmon()
            end
            inv.items.pendingRemoval[key] = nil
            return
        end

        inv.items.removeItemAndSaveNow(key, "pending_removed_from_inventory")
        inv.items.pendingRemoval[key] = nil
    end)
end

----------------------------------------------------------------------------------------------------
-- Refresh Management
----------------------------------------------------------------------------------------------------

local function copyRefreshValue(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[copyRefreshValue(key, seen)] = copyRefreshValue(child, seen)
    end
    return copy
end

local function refreshScopeKey(kind, containerId)
    if kind == "eqdata" then
        return "worn"
    end
    local normalizedContainerId = inv.items.normalizeContainerId
        and inv.items.normalizeContainerId(containerId)
        or nil
    if normalizedContainerId then
        return "container:" .. normalizedContainerId
    end
    return "inventory"
end

function inv.items.invalidateRefresh(reason)
    local validation = inv.items.refreshValidation
    if not inv.items.refreshInProgress or not validation then
        return
    end
    validation.valid = false
    validation.errors = validation.errors or {}
    table.insert(validation.errors, tostring(reason or "unknown refresh validation error"))
    dbot.debug("Refresh validation failed: " .. tostring(reason), "inv.items")
end

function inv.items.expectRefreshScan(kind, containerId)
    local validation = inv.items.refreshValidation
    if not inv.items.refreshInProgress or not validation then
        return true
    end

    if validation.expected then
        inv.items.invalidateRefresh("started a new scan before the previous scan completed")
        return false
    end

    validation.scanSerial = (tonumber(validation.scanSerial) or 0) + 1
    validation.expected = {
        kind = tostring(kind),
        containerId = inv.items.normalizeContainerId(containerId),
        key = refreshScopeKey(kind, containerId),
        serial = validation.scanSerial,
        started = false,
    }
    validation.requested = validation.requested or {}
    validation.requested[validation.expected.key] =
        (validation.requested[validation.expected.key] or 0) + 1

    if tempTimer then
        local serial = validation.scanSerial
        local validationOwner = validation
        tempTimer(30, function()
            local current = inv.items.refreshValidation
            if inv.items.refreshInProgress
                and current == validationOwner
                and current.expected
                and current.expected.serial == serial then
                inv.items.invalidateRefresh("timed out waiting for " ..
                    tostring(current.expected.key))
                inv.items.abortInvalidRefresh()
            end
        end)
    end

    return true
end

function inv.items.startRefreshScan(kind, containerId)
    local validation = inv.items.refreshValidation
    if not inv.items.refreshInProgress or not validation then
        return true
    end

    local expected = validation.expected
    local actualKey = refreshScopeKey(kind, containerId)
    if not expected then
        inv.items.invalidateRefresh("received unexpected " .. actualKey .. " response")
        return false
    end
    if expected.key ~= actualKey or expected.kind ~= tostring(kind) then
        inv.items.invalidateRefresh("expected " .. tostring(expected.key) ..
            " but received " .. actualKey)
        return false
    end
    if expected.started then
        inv.items.invalidateRefresh("received duplicate start for " .. actualKey)
        return false
    end

    expected.started = true
    return true
end

function inv.items.completeRefreshScan(kind, containerId)
    local validation = inv.items.refreshValidation
    if not inv.items.refreshInProgress or not validation then
        return true
    end

    local expected = validation.expected
    local actualKey = refreshScopeKey(kind, containerId)
    if not expected then
        inv.items.invalidateRefresh("received unexpected completion for " .. actualKey)
        return false
    end
    if expected.key ~= actualKey or expected.kind ~= tostring(kind) then
        inv.items.invalidateRefresh("completed " .. actualKey ..
            " while waiting for " .. tostring(expected.key))
        return false
    end
    if not expected.started then
        inv.items.invalidateRefresh("completed " .. actualKey .. " before its start marker")
        return false
    end

    validation.completed = validation.completed or {}
    validation.completed[actualKey] = (validation.completed[actualKey] or 0) + 1
    validation.expected = nil
    return true
end

function inv.items.completeMissingRefreshContainer(objId)
    local validation = inv.items.refreshValidation
    local normalizedId = inv.items.normalizeContainerId(objId)
    if not inv.items.refreshInProgress or not validation or not normalizedId then
        return false
    end

    local expected = validation.expected
    local actualKey = refreshScopeKey("invdata", normalizedId)
    if not expected or expected.key ~= actualKey then
        inv.items.invalidateRefresh("item-not-found response for unexpected container " ..
            tostring(objId))
        return false
    end

    expected.started = true
    return inv.items.completeRefreshScan("invdata", normalizedId)
end

function inv.items.abortInvalidRefresh(options)
    local validation = inv.items.refreshValidation
    if not inv.items.refreshInProgress or not validation then
        return
    end
    local quiet = options == true
        or (type(options) == "table" and options.quiet == true)

    if validation.originalTable then
        local restored = validation.originalTable
        local restoredDetached = validation.originalDetached or {}
        local restoredPendingRemoved = validation.originalPendingRemoved or {}
        local startEventSequence = tonumber(validation.startEventSequence) or 0
        local reattached = {}
        local pendingReattached = {}
        -- A refresh rollback must not undo invmon events that arrived after
        -- the refresh began.
        for objId, currentItem in pairs(inv.items.table or {}) do
            if (tonumber(currentItem and currentItem.__dinvLastEventSeq) or 0) > startEventSequence then
                local key = tostring(objId)
                if restoredDetached[key] then reattached[key] = currentItem end
                if restoredPendingRemoved[key] then pendingReattached[key] = currentItem end
                restored[key] = currentItem
                restoredDetached[key] = nil
                restoredPendingRemoved[key] = nil
            end
        end
        for objId, eventSeq in pairs(inv.items.eventTombstones or {}) do
            if (tonumber(eventSeq) or 0) > startEventSequence then
                restored[tostring(objId)] = nil
                restoredDetached[tostring(objId)] = nil
                restoredPendingRemoved[tostring(objId)] = nil
            end
        end
        inv.items.table = restored
        inv.items.detached = restoredDetached
        inv.items.pendingRemoved = restoredPendingRemoved
        if DINV and DINV.database and DINV.database.discardPending then
            DINV.database.discardPending("active")
        end
        -- The scan itself is rolled back, but a post-start invmon return is
        -- authoritative. Move those rows out of detached persistence when the
        -- restored active snapshot is saved.
        if DINV and DINV.database and DINV.database.markReattached then
            for objId, item in pairs(reattached) do
                DINV.database.markReattached(objId, item, "active")
            end
        end
        if DINV and DINV.database and DINV.database.markPendingReattached then
            for objId, item in pairs(pendingReattached) do
                DINV.database.markPendingReattached(objId, item, "active")
            end
        end
    end

    inv.items.suppressDatabaseWrites = validation.previousSuppressDatabaseWrites == true

    local reason = table.concat(validation.errors or {}, "; ")
    inv.items.refreshValidation = nil
    inv.items.refreshSeen = nil
    inv.items.refreshRecheckQueue = nil
    inv.items.refreshRecheckIndex = nil
    inv.items.refreshInProgress = false
    inv.items.refreshIdentifyPartials = false
    inv.items.discoveryStage = 0
    inv.items.inEqdata = false
    inv.items.inInvdata = false
    inv.items.currentContainerId = nil
    inv.items.expectedInvdataContainerId = nil
    inv.items.awaitingInvdataContainerId = nil
    inv.items.currentInvdataSeen = nil
    inv.state = invStateIdle

    if DINV and DINV.discovery then
        DINV.discovery.currentSection = nil
        DINV.discovery.currentContainerId = nil
    end
    if DINV and DINV.setBuildPhase then
        DINV.setBuildPhase(0)
    end

    if not quiet then
        dbot.warn("Refresh was not internally consistent; no refresh detachments were committed." ..
            (reason ~= "" and " Reason: " .. reason or ""))
    end
    inv.items.applyWorkflowRemovalEvents("refresh_abort")
    if inv.items.save then
        inv.items.save()
    end
    if not quiet then
        inv.items.maybeStartKeepFlagSync()
        inv.items.scheduleDeferredIdentifyProcessing("refreshAbort")
    end
end

function inv.items.refreshOn(periodMin, eagerSec)
    inv.items.timer.refreshMin = periodMin or 5
    inv.items.timer.refreshEagerSec = eagerSec or 0
    
    inv.config.set("isRefreshEnabled", true, true)
    inv.config.set("refreshPeriodMin", inv.items.timer.refreshMin, true)
    inv.config.set("refreshEagerSec", inv.items.timer.refreshEagerSec, true)
    local saveRet = inv.config.save()
    if saveRet ~= DRL_RET_SUCCESS and saveRet ~= DRL_RET_UNINITIALIZED then
        return saveRet
    end
    
    -- Set up the timer
    local intervalSec = inv.items.timer.refreshMin * 60
    inv.items.timer.refreshNextTs = os.time() + intervalSec
    if tempTimer then
        dbot.deleteTimer(inv.items.timer.name)
        dbot.timers[inv.items.timer.name] = tempTimer(intervalSec, [[inv.items.refreshTick()]], true)
    end
    
    return DRL_RET_SUCCESS
end

function inv.items.refreshOff()
    local setRet = inv.config.set("isRefreshEnabled", false)
    if setRet ~= DRL_RET_SUCCESS and setRet ~= DRL_RET_UNINITIALIZED then
        return setRet
    end
    dbot.deleteTimer(inv.items.timer.name)
    inv.state = invStatePaused
    inv.items.timer.refreshNextTs = nil
    return DRL_RET_SUCCESS
end

function inv.items.refreshGetPeriods()
    if inv.config.isRefreshEnabled() then
        return inv.config.getRefreshPeriod()
    end
    return 0
end

function inv.items.refreshTick()
    if inv.config.isRefreshEnabled() then
        local intervalSec = (inv.items.timer.refreshMin or 0) * 60
        if intervalSec > 0 then
            inv.items.timer.refreshNextTs = os.time() + intervalSec
        end

        -- Never interrupt active build/identify/refresh workflows.
        -- Periodic refresh should quietly skip and try again on the next tick.
        if inv.items.buildInProgress or inv.items.identifyInProgress or inv.items.refreshInProgress then
            dbot.debug("inv.items.refreshTick: skipping periodic refresh while workflow is active", "inv.items")
            return DRL_RET_BUSY
        end

        inv.items.refresh(0, invItemsRefreshLocDirty, nil, nil)
    end
end

function inv.items.refreshGetMinutesLeft()
    if not inv.config.isRefreshEnabled() then
        return nil
    end
    local nextTs = inv.items.timer.refreshNextTs
    if not nextTs then
        return nil
    end
    local secondsLeft = math.max(0, nextTs - os.time())
    return math.ceil(secondsLeft / 60)
end

function inv.items.refresh(delay, refreshLoc, endTag, callback)
    local perfStart = dbot.perfNow and dbot.perfNow() or nil
    dbot.perf("refresh requested loc=" .. tostring(refreshLoc or "nil"))

    -- Try to auto-initialize if not already done
    if not inv.init.initializedActive then
        local initStart = dbot.perfNow and dbot.perfNow() or nil
        inv.items.ensureInitialized()
        dbot.perf("refresh ensureInitialized", initStart)
    end
    
    -- Check if we can run
    if not inv.init.initializedActive then
        dbot.debug("inv.items.refresh: Not initialized, skipping", "inv.items")
        return DRL_RET_UNINITIALIZED
    end
    
    if inv.state == invStatePaused then
        return DRL_RET_HALTED
    end
    
    if dbot.gmcp and dbot.gmcp.statePreventsActions and dbot.gmcp.statePreventsActions() then
        return DRL_RET_NOT_ACTIVE
    end
    
    if dbot.gmcp and dbot.gmcp.stateIsInCombat and dbot.gmcp.stateIsInCombat() then
        return DRL_RET_IN_COMBAT
    end

    if inv.items.buildInProgress or inv.items.identifyInProgress or inv.items.refreshInProgress then
        dbot.debug("inv.items.refresh: workflow already in progress, skipping refresh", "inv.items")
        return DRL_RET_BUSY
    end

    -- Establish a clean persistence boundary before discovery. Refresh mutations
    -- remain memory-only until every requested scan and recheck validates, so a
    -- search or backup cannot flush a half-reattached detached subtree.
    if inv.items.save then
        local saveRet = inv.items.save()
        if saveRet ~= DRL_RET_SUCCESS then
            dbot.warn("Unable to start refresh because the current SQLite state could not be committed.")
            return saveRet
        end
    end
    
    dbot.debug("inv.items.refresh: Refresh requested for location '" .. tostring(refreshLoc or "nil") .. "'", "inv.items")

    if refreshLoc == invItemsRefreshLocAll then
        dbot.debug("inv.items.refresh: full-location refresh requested; preserving existing identify data", "inv.items")
    end

    inv.items.refreshPerfStart = perfStart
    inv.items.refreshIdentifyPartials = type(callback) == "table"
        and callback.identifyPartials == true
    inv.state = invStateDiscovery
    inv.items.refreshInProgress = true
    inv.items.refreshSeen = {}
    inv.items.refreshGeneration = (tonumber(inv.items.refreshGeneration) or 0) + 1

    local copyStart = dbot.perfNow and dbot.perfNow() or nil
    local originalTable = copyRefreshValue(inv.items.table or {})
    local originalDetached = copyRefreshValue(inv.items.detached or {})
    local originalPendingRemoved = copyRefreshValue(inv.items.pendingRemoved or {})
    dbot.perf("refresh copy original table", copyStart)

    inv.items.refreshValidation = {
        valid = true,
        errors = {},
        expected = nil,
        requested = {},
        completed = {},
        phase = "initial",
        discoveryStarted = false,
        initialComplete = false,
        recheckComplete = false,
        originalTable = originalTable,
        originalDetached = originalDetached,
        originalPendingRemoved = originalPendingRemoved,
        reattached = {},
        pendingReattached = {},
        previousSuppressDatabaseWrites = inv.items.suppressDatabaseWrites == true,
        generation = inv.items.refreshGeneration,
        startEventSequence = tonumber(inv.items.eventSequence) or 0,
    }
    inv.items.suppressDatabaseWrites = true
    inv.items.refreshRecheckQueue = nil
    inv.items.refreshRecheckIndex = nil
    inv.items.eqdataSeen = {}
    inv.items.expectedInvdataContainerId = nil

    -- Ensure discovery triggers are registered for refresh scans
    if DINV.discovery and DINV.discovery.register then
        local registerStart = dbot.perfNow and dbot.perfNow() or nil
        DINV.discovery.register()
        dbot.perf("refresh register discovery triggers", registerStart)
    end

    -- Toggle prompt handling at refresh boundaries to suppress stray prompt output.
    if inv.items.sendDiscoveryCommand then
        inv.items.sendDiscoveryCommand("prompt")
    else
        sendSilent("prompt")
    end

    local function startDiscovery()
        dbot.perf("refresh discovery start", inv.items.refreshPerfStart)
        -- Use the staged discovery pipeline for refreshes.
        -- discoverCR also issues a timed standalone "invdata" command,
        -- which duplicates main-inventory scans and can leak container context.
        if inv.items.discoverChain then
            inv.items.discoverChain()
        elseif inv.items.discoverCR then
            inv.items.discoverCR()
        end
    end

    local function startWithFence()
        if dbot and dbot.execute and dbot.execute.queue and dbot.execute.queue.fence then
            local validationOwner = inv.items.refreshValidation
            local retval = dbot.execute.queue.fence(startDiscovery, nil, function()
                if inv.items.refreshInProgress
                    and inv.items.refreshValidation == validationOwner
                    and validationOwner
                    and not validationOwner.discoveryStarted then
                    inv.items.invalidateRefresh("timed out waiting for refresh fence")
                    inv.items.abortInvalidRefresh()
                end
            end)
            if retval ~= DRL_RET_SUCCESS then
                startDiscovery()
            end
        else
            startDiscovery()
        end
    end

    if delay and delay > 0 and tempTimer then
        tempTimer(delay, startWithFence)
    else
        startWithFence()
    end
    dbot.perf("refresh setup returned", perfStart)

    -- Refresh should not mass-identify items; the build pipeline handles identify safely.
    
    if inv.tags and inv.tags.stop then
        return inv.tags.stop(invTagsRefresh, endTag, DRL_RET_SUCCESS)
    end
    
    return DRL_RET_SUCCESS
end

function inv.items.build(endTag)
    -- Check if already in progress
    if inv.items.buildInProgress then
        dbot.warn("A build is already in progress!")
        cecho("\n<yellow>[DINV] Current status: " .. inv.items.getProgressString() .. "\n")
        cecho("<yellow>[DINV] To cancel, type: dinv build abort\n")
        if endTag then
            return inv.tags.stop(invTagsBuild, endTag, DRL_RET_BUSY)
        end
        return DRL_RET_BUSY
    end

    if not DINV or not DINV.database or not DINV.database.beginBuild then
        dbot.warn("Cannot start build: SQLite persistence is unavailable")
        return DRL_RET_INTERNAL_ERROR
    end
    -- Keep the active inventory as a clean rollback boundary. All subsequent
    -- build writes go only to staging until finishBuild activates them.
    if inv.items.save then
        local activeSaveRet = inv.items.save()
        if activeSaveRet ~= DRL_RET_SUCCESS then
            dbot.warn("Cannot start build because the active SQLite inventory could not be committed.")
            return activeSaveRet
        end
    end
    local databaseBuildId, resumedOrError = DINV.database.beginBuild()
    if not databaseBuildId then
        dbot.warn("Cannot start crash-safe build: " .. tostring(resumedOrError))
        return DRL_RET_INTERNAL_ERROR
    end
    inv.items.databaseBuildId = databaseBuildId
    inv.items.databaseBuildIdentifiedSinceFlush = 0
    inv.items.buildResumeItems = nil
    if resumedOrError == true and DINV.database.loadStagedItems then
        inv.items.buildResumeItems = DINV.database.loadStagedItems() or {}
        dbot.info("Resuming staged SQLite build data; unchanged object IDs will not be re-identified.")
    end

    -- Reset state
    inv.items.buildInProgress = true
    inv.items.buildEndTag = endTag
    inv.items.discoveryComplete = false
    inv.items.identifyQueue = {}
    inv.items.identifyIndex = 0
    inv.items.identifyTotal = 0
    inv.items.currentContainerId = nil
    inv.items.expectedInvdataContainerId = nil
    inv.items.inEqdata = false
    inv.items.inInvdata = false
    inv.items.eqdataSeen = {}
    inv.items.forceIdentify = true

    dbot.deleteTimer(inv.items.timer.databaseBatchName)
    if tempTimer then
        dbot.timers[inv.items.timer.databaseBatchName] = tempTimer(
            inv.items.databaseBuildBatchSeconds,
            function()
                if inv.items.databaseBuildId and inv.items.save then
                    inv.items.save()
                end
            end,
            true
        )
    end

    -- Reset progress
    inv.items.progress = {
        stage = "Starting",
        current = 0,
        total = 0,
        startTime = os.time(),
        lastUpdate = 0,
    }

    -- Make sure discovery triggers are registered
    if DINV.discovery and DINV.discovery.register then
        DINV.discovery.register()
    end

    -- Print header
    cecho("\n<yellow>================================================================================\n")
    cecho("<green>  DINV Inventory Build Starting\n")
    cecho("<yellow>================================================================================\n")
    cecho("\n")
    cecho("<white>  This process will:\n")
    cecho("<white>  1. Scan all worn equipment (eqdata)\n")
    cecho("<white>  2. Scan main inventory (invdata)\n")
    cecho("<white>  3. Scan all containers\n")
    cecho("<white>  4. Identify each item (get from container if needed)\n")
    cecho("\n")
    cecho("<yellow>  Please wait... This may take several minutes.\n")
    cecho("<yellow>  To abort: dinv build abort\n")
    cecho("\n")

    -- Preserve legacy item-attached organize rules before the rebuild resets item state.
    if inv.organize and inv.organize.migrateItemRulesToConfig then
        inv.organize.migrateItemRulesToConfig()
    end

    inv.items.buildOriginalTable = copyRefreshValue(inv.items.table or {})
    inv.items.buildOriginalDetached = copyRefreshValue(inv.items.detached or {})
    inv.items.buildOriginalPendingRemoved = copyRefreshValue(inv.items.pendingRemoved or {})
    inv.items.buildStartEventSequence = tonumber(inv.items.eventSequence) or 0

    -- Reset inventory table
    inv.items.reset()
    inv.state = invStateDiscovery

    -- Mark as initialized
    inv.init.initializedActive = true
    if dbot and dbot.gmcp then
        dbot.gmcp.isInitialized = true
    end
    if dbot and dbot.init then
        dbot.init.initializedActive = true
    end

    -- Start discovery chain
    cecho("\n<cyan>[DINV] Stage 1/4: Scanning worn equipment...\n")
    inv.items.progress.stage = "Scanning equipment"
    if DINV and DINV.setBuildPhase then
        DINV.setBuildPhase(1)
    end

    -- Send eqdata silently (after fence, if available)
    local function startDiscovery()
        if inv.items.sendDiscoveryCommand then
            inv.items.sendDiscoveryCommand("eqdata")
        else
            sendSilent("eqdata")
        end
    end

    if dbot and dbot.execute and dbot.execute.queue and dbot.execute.queue.fence then
        dbot.execute.queue.fence(startDiscovery)
    else
        startDiscovery()
    end

    return DRL_RET_SUCCESS
end

function inv.items.buildSingleItem(objId, source)
    if not objId or objId == "" then
        dbot.debug("buildSingleItem: missing objId (source=" .. tostring(source) .. ")", "inv.items")
        return DRL_RET_INVALID_PARAM
    end
    -- A refresh owns the eqdata/invdata protocol stream. Starting a one-item
    -- identify here would switch buildPhase to 4, discard the refresh tags,
    -- and leave that refresh waiting until its timeout.
    if inv.items.refreshInProgress then
        dbot.debug("buildSingleItem: refresh active, deferring objId=" .. tostring(objId), "inv.items")
        return DRL_RET_BUSY
    end
    if inv.items.buildInProgress or inv.items.identifyInProgress then
        if inv.items.singleIdentifyMode and type(inv.items.identifyQueue) == "table" then
            local normalizedObjId = tostring(objId)
            local alreadyQueued = false
            for _, queuedObjId in ipairs(inv.items.identifyQueue) do
                if tostring(queuedObjId) == normalizedObjId then
                    alreadyQueued = true
                    break
                end
            end

            if not alreadyQueued then
                table.insert(inv.items.identifyQueue, normalizedObjId)
                inv.items.identifyTotal = #inv.items.identifyQueue
                if inv.items.progress then
                    inv.items.progress.total = inv.items.identifyTotal
                end
                dbot.debug("buildSingleItem: busy, queued follow-up objId=" .. normalizedObjId,
                           "inv.items")
            else
                dbot.debug("buildSingleItem: busy, objId already queued=" .. normalizedObjId,
                           "inv.items")
            end

            return DRL_RET_SUCCESS
        end

        dbot.debug("buildSingleItem: busy, skipping objId=" .. tostring(objId), "inv.items")
        return DRL_RET_BUSY
    end

    if dbot.gmcp and dbot.gmcp.stateIsInCombat and dbot.gmcp.stateIsInCombat() then
        dbot.debug("buildSingleItem: in combat, deferring objId=" .. tostring(objId), "inv.items")
        return DRL_RET_IN_COMBAT
    end

    local item = inv.items.getItem(objId)
    if not item then
        dbot.debug("buildSingleItem: item not found in table for objId=" .. tostring(objId), "inv.items")
        return DRL_RET_MISSING_ENTRY
    end

    inv.items.buildInProgress = true
    inv.items.identifyInProgress = true
    inv.items.forceIdentify = true
    inv.items.singleIdentifyMode = true
    inv.items.singleIdentifyId = tostring(objId)
    inv.items.identifyQueue = { tostring(objId) }
    inv.items.identifyIndex = 0
    inv.items.identifyTotal = 1
    inv.items.progress = {
        stage = "Identifying item",
        current = 0,
        total = 1,
        startTime = os.time(),
        lastUpdate = 0,
    }
    inv.state = invStateIdentify
    if DINV and DINV.setBuildPhase then
        DINV.setBuildPhase(4)
        sendGMCP("config prompt off")
    end

    if DINV.discovery and DINV.discovery.registerIdentifyTriggers then
        DINV.discovery.registerIdentifyTriggers()
    end

    dbot.debug("buildSingleItem: starting identify for objId=" .. tostring(objId) .. " source=" .. tostring(source), "inv.items")

    local debounceSeconds = inv.items.identifyBatchDebounceSeconds or 0.3
    inv.items.identifyBatchPending = true
    tempTimer(debounceSeconds, function()
        if not inv.items.identifyBatchPending then
            return
        end
        inv.items.identifyBatchPending = nil
        if not inv.items.buildInProgress or not inv.items.identifyInProgress then
            return
        end
        local total = #(inv.items.identifyQueue or {})
        inv.items.identifyTotal = total
        if inv.items.progress then
            inv.items.progress.total = total
        end
        dbot.debug("buildSingleItem: batch debounce fired, identify queue total=" .. tostring(total), "inv.items")
        inv.items.identifyNext()
    end)
    return DRL_RET_SUCCESS
end

function inv.items.identifySingleItem(objId, source)
    local normalizedObjId = tostring(objId or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if normalizedObjId == "" then
        return DRL_RET_INVALID_PARAM
    end

    if inv.items.refreshInProgress or inv.items.identifyHydrateInProgress then
        return DRL_RET_BUSY
    end

    inv.items.identifyCreatedMissing = inv.items.identifyCreatedMissing or {}
    inv.items.identifySawOutput = inv.items.identifySawOutput or {}

    if not inv.items.getItem(normalizedObjId) then
        return inv.items.startIdentifyHydrateFromInvdata(normalizedObjId, source or "single-identify")
    end

    inv.items.identifyCreatedMissing[normalizedObjId] = nil
    inv.items.identifySawOutput[normalizedObjId] = nil

    local retval = inv.items.buildSingleItem(normalizedObjId, source or "single-identify")
    if retval == DRL_RET_IN_COMBAT then
        inv.items.enqueueDeferredIdentify(normalizedObjId, source or "single-identify")
        return DRL_RET_SUCCESS
    end

    return retval
end

function inv.items.startIdentifyHydrateFromInvdata(objId, source)
    local normalizedObjId = tostring(objId or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if normalizedObjId == "" then
        return DRL_RET_INVALID_PARAM
    end

    if inv.items.buildInProgress or inv.items.identifyInProgress
        or inv.items.refreshInProgress or inv.items.identifyHydrateInProgress then
        return DRL_RET_BUSY
    end

    if dbot.gmcp and dbot.gmcp.statePreventsActions and dbot.gmcp.statePreventsActions() then
        return DRL_RET_NOT_ACTIVE
    end

    if dbot.gmcp and dbot.gmcp.stateIsInCombat and dbot.gmcp.stateIsInCombat() then
        return DRL_RET_IN_COMBAT
    end

    inv.items.identifyHydrateInProgress = true
    inv.items.identifyHydrateId = normalizedObjId
    inv.items.identifyHydrateSource = source or "single-identify"
    inv.items.identifyHydrateFound = false
    inv.items.identifyHydratePreviousState = inv.state
    inv.items.identifyHydrateTimerName = "inv.items.identifyHydrate." .. normalizedObjId
    inv.items.inEqdata = false
    inv.items.inInvdata = false
    inv.items.currentContainerId = nil
    inv.items.currentInvdataSeen = nil
    inv.items.expectedInvdataContainerId = nil
    inv.items.awaitingInvdataContainerId = nil
    inv.state = invStateDiscovery

    if DINV and DINV.setBuildPhase then
        DINV.setBuildPhase(2)
    end

    if DINV.discovery and DINV.discovery.register then
        DINV.discovery.register()
    end

    dbot.debug("identify hydrate: scanning main invdata for objId=" .. normalizedObjId, "inv.items")
    if inv.items.sendDiscoveryCommand then
        inv.items.sendDiscoveryCommand("invdata")
    else
        sendSilent("invdata")
    end

    if tempTimer then
        local expectedObjId = normalizedObjId
        dbot.timers[inv.items.identifyHydrateTimerName] = tempTimer(5.0, function()
            if inv.items.identifyHydrateInProgress
                and tostring(inv.items.identifyHydrateId or "") == expectedObjId then
                dbot.debug("identify hydrate: invdata timeout for objId=" .. expectedObjId, "inv.items")
                if inv.items.identifyHydrateTimerName and dbot and dbot.timers then
                    dbot.timers[inv.items.identifyHydrateTimerName] = nil
                end
                inv.items.identifyHydrateTimerName = nil
                inv.items.finishIdentifyHydrateInvdata()
            end
        end)
    end

    return DRL_RET_SUCCESS
end

function inv.items.handleIdentifyHydrateInvdataLine(dataLine)
    local targetId = tostring(inv.items.identifyHydrateId or "")
    if targetId == "" then
        return DRL_RET_INVALID_PARAM
    end

    local lineObjId = tostring(dataLine or ""):match("^(%d+),")
    if tostring(lineObjId or "") ~= targetId then
        return DRL_RET_SUCCESS
    end

    dbot.debug("identify hydrate: found target objId=" .. targetId, "inv.items")
    local retval = inv.items._parseDataLine(dataLine, "invdata")
    if retval == DRL_RET_SUCCESS then
        inv.items.identifyHydrateFound = true
    else
        dbot.warn("dinv identify: failed to parse invdata for item " .. targetId ..
                  " (" .. dbot.retval.getString(retval) .. ")")
    end
    return retval
end

function inv.items.finishIdentifyHydrateInvdata()
    local objId = tostring(inv.items.identifyHydrateId or "")
    local source = inv.items.identifyHydrateSource or "single-identify"
    local found = inv.items.identifyHydrateFound == true
    local previousState = inv.items.identifyHydratePreviousState
    local timerName = inv.items.identifyHydrateTimerName

    if timerName and dbot and dbot.deleteTimer then
        dbot.deleteTimer(timerName)
    end

    inv.items.identifyHydrateInProgress = false
    inv.items.identifyHydrateId = nil
    inv.items.identifyHydrateSource = nil
    inv.items.identifyHydrateFound = false
    inv.items.identifyHydratePreviousState = nil
    inv.items.identifyHydrateTimerName = nil
    inv.items.inEqdata = false
    inv.items.inInvdata = false
    inv.items.currentContainerId = nil
    inv.items.currentInvdataSeen = nil
    inv.items.expectedInvdataContainerId = nil
    inv.items.awaitingInvdataContainerId = nil
    inv.state = previousState or invStateIdle

    if DINV and DINV.setBuildPhase then
        DINV.setBuildPhase(0)
    end

    if objId == "" then
        return DRL_RET_INVALID_PARAM
    end

    if not found or not inv.items.getItem(objId) then
        dbot.warn("dinv identify: item " .. objId .. " was not found in main inventory.")
        return DRL_RET_MISSING_ENTRY
    end

    inv.items.identifyCreatedMissing = inv.items.identifyCreatedMissing or {}
    inv.items.identifySawOutput = inv.items.identifySawOutput or {}
    inv.items.identifyHydratedFromInvdata = inv.items.identifyHydratedFromInvdata or {}
    inv.items.identifyCreatedMissing[objId] = nil
    inv.items.identifySawOutput[objId] = nil
    inv.items.identifyHydratedFromInvdata[objId] = true

    dbot.debug("identify hydrate: starting identify for objId=" .. objId, "inv.items")
    local retval = inv.items.buildSingleItem(objId, source)
    if retval == DRL_RET_BUSY or retval == DRL_RET_IN_COMBAT then
        inv.items.enqueueDeferredIdentify(objId, source)
        return DRL_RET_SUCCESS
    elseif retval ~= DRL_RET_SUCCESS then
        dbot.warn("dinv identify: unable to identify item " .. objId ..
                  " after invdata scan (" .. dbot.retval.getString(retval) .. ")")
    end

    return retval
end

function inv.items.enqueueDeferredIdentify(objId, source)
    local normalizedObjId = tostring(objId or "")
    if normalizedObjId == "" then
        return DRL_RET_INVALID_PARAM
    end

    inv.items.deferredIdentifyQueue = inv.items.deferredIdentifyQueue or {}
    for _, queuedObjId in ipairs(inv.items.deferredIdentifyQueue) do
        if tostring(queuedObjId) == normalizedObjId then
            return DRL_RET_SUCCESS
        end
    end

    table.insert(inv.items.deferredIdentifyQueue, normalizedObjId)
    dbot.debug("enqueueDeferredIdentify: queued objId=" .. normalizedObjId .. " source=" .. tostring(source), "inv.items")
    return DRL_RET_SUCCESS
end

function inv.items.processDeferredIdentifyQueue(source)
    if inv.items.buildInProgress or inv.items.identifyInProgress or inv.items.refreshInProgress then
        return DRL_RET_BUSY
    end

    if dbot.gmcp and dbot.gmcp.stateIsInCombat and dbot.gmcp.stateIsInCombat() then
        return DRL_RET_IN_COMBAT
    end

    inv.items.deferredIdentifyQueue = inv.items.deferredIdentifyQueue or {}
    while #inv.items.deferredIdentifyQueue > 0 do
        local queuedObjId = table.remove(inv.items.deferredIdentifyQueue, 1)
        if inv.items.getItem(queuedObjId) then
            local retval = inv.items.buildSingleItem(queuedObjId, tostring(source or "deferred"))
            if retval == DRL_RET_BUSY or retval == DRL_RET_IN_COMBAT then
                table.insert(inv.items.deferredIdentifyQueue, 1, queuedObjId)
            end
            return retval
        end
    end

    return DRL_RET_SUCCESS
end

function inv.items.scheduleDeferredIdentifyProcessing(source)
    if not inv.items.deferredIdentifyQueue or #inv.items.deferredIdentifyQueue == 0 then
        return DRL_RET_SUCCESS
    end

    local function processQueue()
        if inv and inv.items and inv.items.processDeferredIdentifyQueue then
            inv.items.processDeferredIdentifyQueue(tostring(source or "deferred"))
        end
    end

    if tempTimer then
        tempTimer(0.1, processQueue)
    else
        processQueue()
    end
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Item Access Functions
----------------------------------------------------------------------------------------------------

function inv.items.getItem(objId)
    if inv.items.table == nil then
        return nil
    end
    return inv.items.table[tostring(objId)]
end

function inv.items.getDetachedItem(objId)
    if inv.items.detached == nil then
        return nil
    end
    return inv.items.detached[tostring(objId)]
end

function inv.items.getPendingRemovedItem(objId)
    if inv.items.pendingRemoved == nil then
        return nil
    end
    return inv.items.pendingRemoved[tostring(objId)]
end

function inv.items.nextEventSequence()
    inv.items.eventSequence = (tonumber(inv.items.eventSequence) or 0) + 1
    return inv.items.eventSequence
end

function inv.items.markLocationObserved(item, source, eventSeq)
    if not item then
        return
    end
    item.__dinvPresence = "active"
    item.__dinvDetachedRoot = nil
    item.__dinvRemovedAt = nil
    item.__dinvPurgeAfter = nil
    item.__dinvRemovalAction = nil
    item.__dinvRemovalReason = nil
    item.__dinvLocationSource = tostring(source or "unknown")
    item.__dinvLocationSession = DINV and DINV.database and DINV.database.getSessionId
        and DINV.database.getSessionId() or nil
    item.__dinvLocationConfirmedAt = os.time()
    if eventSeq then
        item.__dinvLastEventSeq = tonumber(eventSeq) or 0
    end
    if inv.items.refreshInProgress then
        item.__dinvRefreshGeneration = tonumber(inv.items.refreshGeneration) or 0
    end
end

function inv.items.collectActiveSubtree(rootId)
    local rootKey = tostring(rootId or "")
    if rootKey == "" or not inv.items.table or not inv.items.table[rootKey] then
        return nil
    end

    local subtree = {}
    local queue = { rootKey }
    local queued = { [rootKey] = true }
    local index = 1
    while index <= #queue do
        local currentId = queue[index]
        index = index + 1
        local current = inv.items.table[currentId]
        if current then
            subtree[currentId] = current
            for childId, child in pairs(inv.items.table) do
                local container = child and child.stats and child.stats[invStatFieldContainer]
                if tostring(container or "") == currentId and not queued[tostring(childId)] then
                    local childKey = tostring(childId)
                    queued[childKey] = true
                    table.insert(queue, childKey)
                end
            end
        end
    end

    return subtree
end

function inv.items.detachSubtree(rootId, reason)
    local rootKey = tostring(rootId or "")
    local subtree = inv.items.collectActiveSubtree(rootKey)
    if not subtree then
        return false
    end

    if DINV and DINV.database and DINV.database.detachItems then
        local ok, err = DINV.database.detachItems(subtree, rootKey)
        if not ok then
            dbot.warn("Unable to detach inventory subtree " .. rootKey .. ": " .. tostring(err))
            return false
        end
    else
        return false
    end

    inv.items.detached = inv.items.detached or {}
    for objId, item in pairs(subtree) do
        if inv.items.databaseBuildId and DINV.database.markDeleted then
            DINV.database.markDeleted(objId, "build")
        end
        item.__dinvPresence = "detached"
        item.__dinvDetachedRoot = rootKey
        inv.items.detached[objId] = item
        inv.items.table[objId] = nil
    end
    dbot.debug(string.format("Detached subtree root=%s items=%d reason=%s",
        rootKey, dbot.table.getNumEntries(subtree), tostring(reason or "unknown")), "inv.items")
    return true
end

function inv.items.isFullyIdentified(item)
    return item and item.stats and item.stats.identifyLevel == invIdLevelFull
end

function inv.items.getPendingRemovalRetentionSeconds()
    local periodMinutes = inv.config and inv.config.getRefreshPeriod
        and tonumber(inv.config.getRefreshPeriod()) or nil
    if not periodMinutes or periodMinutes <= 0 then
        periodMinutes = tonumber(inv.items.timer and inv.items.timer.refreshMin) or 5
    end
    return math.max(1, math.floor(periodMinutes * 60))
end

function inv.items.moveItemsToPendingRemoval(entries, reason, action)
    if type(entries) ~= "table" or not next(entries)
        or not DINV or not DINV.database or not DINV.database.moveItemsToPendingRemoval then
        return false, 0
    end
    local removedAt = os.time()
    local purgeAfter = removedAt + inv.items.getPendingRemovalRetentionSeconds()
    local target = inv.items.databaseBuildId and "build" or "active"
    local prepared = {}
    local databaseEntries = {}
    for _, entry in pairs(entries) do
        local key = tostring(entry and entry.objId or "")
        local item = entry and entry.item or nil
        if key == "" or not item or not inv.items.isFullyIdentified(item) then
            for _, restore in ipairs(prepared) do
                restore.item.__dinvLastEventSeq = restore.previousEventSeq
            end
            return false, 0
        end
        local removalSeq = tonumber(entry.eventSeq) or tonumber(inv.items.eventSequence) or 0
        local entryAction = tonumber(entry.action)
        if entryAction == nil then entryAction = tonumber(action) or invmonActionRemovedFromInv end
        local entryReason = tostring(entry.reason or reason or "removed_from_inventory")
        local preparedEntry = {
            key = key,
            item = item,
            removalSeq = removalSeq,
            previousEventSeq = item.__dinvLastEventSeq,
            action = entryAction,
            reason = entryReason,
        }
        item.__dinvLastEventSeq = removalSeq
        table.insert(prepared, preparedEntry)
        table.insert(databaseEntries, {
            objId = key,
            item = item,
            details = {
                removedAt = removedAt,
                purgeAfter = purgeAfter,
                action = entryAction,
                reason = entryReason,
            },
        })
    end

    local moved, moveErr = DINV.database.moveItemsToPendingRemoval(databaseEntries, target)
    if not moved then
        for _, restore in ipairs(prepared) do
            restore.item.__dinvLastEventSeq = restore.previousEventSeq
        end
        dbot.warn("Unable to preserve removed objects: " .. tostring(moveErr))
        return false, 0
    end

    inv.items.pendingRemoved = inv.items.pendingRemoved or {}
    for _, pending in ipairs(prepared) do
        inv.items.removeItemFromCache(pending.key, pending.item)
        inv.items.removeItem(pending.key, { skipDatabase = true })
        pending.item.__dinvPresence = "pending-removal"
        pending.item.__dinvDetachedRoot = nil
        pending.item.__dinvRemovedAt = removedAt
        pending.item.__dinvPurgeAfter = purgeAfter
        pending.item.__dinvRemovalAction = pending.action
        pending.item.__dinvRemovalReason = pending.reason
        inv.items.pendingRemoved[pending.key] = pending.item
        inv.items.eventTombstones[pending.key] = pending.removalSeq
        dbot.debug(string.format(
            "Pending removal objId=%s identify=full purgeAfter=%d reason=%s",
            pending.key, purgeAfter, pending.reason), "inv.items")
    end
    return true, #prepared
end

function inv.items.moveToPendingRemoval(objId, item, eventSeq, reason, action)
    local moved = inv.items.moveItemsToPendingRemoval({ {
        objId = objId,
        item = item,
        eventSeq = eventSeq,
        reason = reason,
        action = action,
    } }, reason, action)
    return moved
end

function inv.items.removePurgedPendingItems(objIds)
    local removed = 0
    for _, objId in ipairs(objIds or {}) do
        local key = tostring(objId)
        local item = inv.items.pendingRemoved and inv.items.pendingRemoved[key] or nil
        if item then
            inv.items.removeItemFromCache(key, item)
            inv.items.pendingRemoved[key] = nil
            removed = removed + 1
        end
    end
    if removed > 0 then
        dbot.debug("Purged " .. tostring(removed) .. " expired pending removal(s)", "inv.items")
    end
    return removed
end

function inv.items.finalizeRemovedFromInventory(objId, eventSeq, reason, action)
    local key = tostring(objId or "")
    if key == "" then
        return false
    end

    local subtree = inv.items.collectActiveSubtree(key)
    if subtree and dbot.table.getNumEntries(subtree) > 1 then
        local root = subtree[key]
        if root then root.__dinvLastEventSeq = tonumber(eventSeq) or 0 end
        return inv.items.detachSubtree(key, reason or "removed_from_inventory")
    end

    local item = inv.items.getItem(key) or inv.items.getDetachedItem(key)
    if item then
        item.__dinvLastEventSeq = tonumber(eventSeq) or tonumber(inv.items.eventSequence) or 0
        if inv.items.isFullyIdentified(item) then
            return inv.items.moveToPendingRemoval(key, item, eventSeq, reason, action)
        end
        inv.items.removeItemFromCache(key, item)
        inv.items.removeItem(key)
    end
    inv.items.eventTombstones[key] = tonumber(eventSeq) or tonumber(inv.items.eventSequence) or 0
    dbot.debug("Terminal removal for partial singleton object " .. key, "inv.items")
    return true
end

function inv.items.reattachDetachedSubtree(rootId, eventSeq)
    local rootKey = tostring(rootId or "")
    if rootKey == "" or not inv.items.detached then
        return 0
    end

    local selected = {}
    local reachable = { [rootKey] = true }
    local changed = true
    while changed do
        changed = false
        for objId, item in pairs(inv.items.detached) do
            local key = tostring(objId)
            local container = item and item.stats and item.stats[invStatFieldContainer] or ""
            local detachedRoot = tostring(item and item.__dinvDetachedRoot or "")
            local belongsToRoot = key == rootKey or detachedRoot == rootKey
            -- Current detached rows always carry their root ID. Only rows from
            -- an older/incomplete store may fall back to container ancestry;
            -- an explicit different root must never cross-attach.
            local legacyReachable = detachedRoot == "" and reachable[tostring(container)]
            if not selected[key]
                and (belongsToRoot or legacyReachable) then
                selected[key] = item
                reachable[key] = true
                changed = true
            end
        end
    end

    local count = 0
    for objId, item in pairs(selected) do
        inv.items.markLocationObserved(item, "detached_return", eventSeq)
        inv.items.setItem(objId, item, { silentApi = true })
        count = count + 1
    end
    if count > 0 then
        dbot.debug(string.format("Reattached detached subtree root=%s descendants=%d",
            rootKey, count), "inv.items")
    end
    return count
end

function inv.items.recordWorkflowRemoval(objId, action, eventSeq)
    local key = tostring(objId or "")
    if key == "" then return end
    inv.items.workflowRemovalEvents = inv.items.workflowRemovalEvents or {}
    inv.items.workflowRemovalEvents[key] = {
        action = tonumber(action),
        eventSeq = tonumber(eventSeq) or 0,
    }
end

function inv.items.applyWorkflowRemovalEvents(reason, options)
    local pending = inv.items.workflowRemovalEvents or {}
    local retainApplied = type(options) == "table" and options.retainApplied == true
    local ordered = {}
    for objId, event in pairs(pending) do
        table.insert(ordered, { objId = tostring(objId), event = event })
    end
    table.sort(ordered, function(left, right)
        return (tonumber(left.event.eventSeq) or 0) < (tonumber(right.event.eventSeq) or 0)
    end)

    for _, entry in ipairs(ordered) do
        local action = tonumber(entry.event.action)
        local applied = true
        if action == invmonActionRemovedFromInv then
            local item = inv.items.getItem(entry.objId)
            if item then
                applied = inv.items.finalizeRemovedFromInventory(
                    entry.objId,
                    entry.event.eventSeq,
                    tostring(reason or "workflow") .. "_invmon_" .. tostring(action),
                    action)
            end
        elseif action == invmonActionPutIntoVault then
            local item = inv.items.getItem(entry.objId)
            if item then
                item.__dinvLastEventSeq = tonumber(entry.event.eventSeq) or 0
                applied = inv.items.detachSubtree(entry.objId,
                    tostring(reason or "workflow") .. "_invmon_" .. tostring(action))
            end
        end
        if applied then
            if not retainApplied then
                pending[entry.objId] = nil
            end
        else
            dbot.warn("Unable to apply deferred inventory removal for object " .. entry.objId)
        end
    end
end

function inv.items.isTransientItem(item)
    if type(item) ~= "table" then
        return false
    end
    if item.__dinvTransient == true then
        return true
    end
    return type(item.stats) == "table" and item.stats.__dinvTransient == true
end

----------------------------------------------------------------------------------------------------
-- Query Parsing
----------------------------------------------------------------------------------------------------

function inv.items.convertRelative(relativeName)
    local index, name = tostring(relativeName or ""):match("^(%d+)%.(.+)$")
    if not index then
        return nil, relativeName
    end
    return tonumber(index), name
end

local function tokenizeQuerySegment(segment)
    local tokens = {}
    local text = tostring(segment or "")
    local index = 1
    while index <= #text do
        while index <= #text and text:sub(index, index):match("%s") do
            index = index + 1
        end
        if index > #text then break end
        local quote = text:sub(index, index)
        if quote == '"' or quote == "'" then
            index = index + 1
            local value = {}
            while index <= #text do
                local character = text:sub(index, index)
                if character == quote then
                    index = index + 1
                    break
                elseif character == "\\" and index < #text then
                    index = index + 1
                    table.insert(value, text:sub(index, index))
                else
                    table.insert(value, character)
                end
                index = index + 1
            end
            table.insert(tokens, table.concat(value))
        else
            local startIndex = index
            while index <= #text and not text:sub(index, index):match("%s") do
                index = index + 1
            end
            table.insert(tokens, text:sub(startIndex, index - 1))
        end
    end
    return tokens
end

function inv.items._parseQuerySegment(segment)
    local tokens = tokenizeQuerySegment(segment)

    local function normalizeKey(rawKey)
        local key = tostring(rawKey or "")
        local negated = false
        if key:sub(1, 1) == "~" then
            negated = true
            key = key:sub(2)
        end
        key = key:lower()
        if key == "key" or key == "keyword" then
            key = "keywords"
        elseif key == "loc" then
            key = "location"
        elseif key == "rloc" then
            key = "rlocation"
        elseif key == "leadsto" then
            key = invStatFieldLeadsTo
        end
        return key, negated
    end

    local criteria = {}
    local i = 1
    while i <= #tokens do
        local key, negated = normalizeKey(tokens[i])
        local nextToken = tokens[i + 1]

        if not nextToken then
            table.insert(criteria, { key = "name", value = tokens[i], negated = negated })
            break
        end

        if not inv.items.isKnownQueryKey(key) then
            table.insert(criteria, { key = "name", value = tokens[i], negated = negated })
            i = i + 1
        else
            local valueParts = {}
            local j = i + 1
            while j <= #tokens do
                local possibleKey, _ = normalizeKey(tokens[j])
                if inv.items.isKnownQueryKey(possibleKey) and #valueParts > 0 then
                    break
                end
                table.insert(valueParts, tokens[j])
                j = j + 1
            end
            table.insert(criteria, { key = key, value = table.concat(valueParts, " "), negated = negated })
            i = j
        end
    end

    return criteria
end

function inv.items.isKnownQueryKey(key)
    local normalized = tostring(key or ""):lower()
    if normalized == "" then
        return false
    end

    local explicit = {
        type = true, name = true, wearable = true, keywords = true, key = true, keyword = true,
        id = true, container = true, worn = true, minlevel = true, maxlevel = true, level = true,
        flag = true, flags = true, loc = true, location = true, rloc = true, rlocation = true,
        rname = true, specials = true, damtype = true, weapontype = true, clan = true,
        score = true, weight = true, worth = true, owner = true, material = true, leadsto = true
    }
    if explicit[normalized] then
        return true
    end

    for _, item in pairs(inv.items.table or {}) do
        local stats = item and item.stats or nil
        if stats then
            for statKey, _ in pairs(stats) do
                if tostring(statKey):lower() == normalized then
                    return true
                end
            end
        end
    end

    return false
end

function inv.items.parseQuery(query)
    local parts = {}
    local raw = tostring(query or "")
    local numericQuery = raw:match("^%s*(%d+)%s*$")
    if numericQuery then
        return {
            {
                { key = "id", value = numericQuery, negated = false }
            }
        }
    end
    for segment in raw:gmatch("[^|]+") do
        local trimmed = segment:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" and trimmed ~= "||" then
            table.insert(parts, trimmed)
        end
    end

    local clauses = {}
    for _, segment in ipairs(parts) do
        if segment ~= "" then
            table.insert(clauses, inv.items._parseQuerySegment(segment))
        end
    end

    if #clauses == 0 then
        table.insert(clauses, {})
    end

    return clauses
end

----------------------------------------------------------------------------------------------------
-- Stat Search Query Functions
----------------------------------------------------------------------------------------------------

inv.items.statSearchFieldKinds = {
    [invStatFieldStr] = "numeric",
    [invStatFieldInt] = "numeric",
    [invStatFieldWis] = "numeric",
    [invStatFieldDex] = "numeric",
    [invStatFieldCon] = "numeric",
    [invStatFieldLuck] = "numeric",
    [invStatFieldHp] = "numeric",
    [invStatFieldMana] = "numeric",
    [invStatFieldMoves] = "numeric",
    [invStatFieldHitroll] = "numeric",
    [invStatFieldDamroll] = "numeric",
    [invStatFieldSaves] = "numeric",
    [invStatFieldAllPhys] = "numeric",
    [invStatFieldAllMagic] = "numeric",
    [invStatFieldBash] = "numeric",
    [invStatFieldPierce] = "numeric",
    [invStatFieldSlash] = "numeric",
    [invStatFieldAcid] = "numeric",
    [invStatFieldCold] = "numeric",
    [invStatFieldEnergy] = "numeric",
    [invStatFieldHoly] = "numeric",
    [invStatFieldElectric] = "numeric",
    [invStatFieldNegative] = "numeric",
    [invStatFieldShadow] = "numeric",
    [invStatFieldMagic] = "numeric",
    [invStatFieldAir] = "numeric",
    [invStatFieldEarth] = "numeric",
    [invStatFieldFire] = "numeric",
    [invStatFieldLight] = "numeric",
    [invStatFieldMental] = "numeric",
    [invStatFieldSonic] = "numeric",
    [invStatFieldWater] = "numeric",
    [invStatFieldDisease] = "numeric",
    [invStatFieldPoison] = "numeric",
    [invStatFieldAveDam] = "numeric",
    [invStatFieldIlluminate] = "enchant",
    [invStatFieldResonate] = "enchant",
    [invStatFieldSolidify] = "enchant",
}

local function trimStatSearchText(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function tokenizeStatSearchSegment(segment)
    local tokens = {}
    local text = tostring(segment or "")
    local index = 1

    while index <= #text do
        while index <= #text and text:sub(index, index):match("%s") do
            index = index + 1
        end
        if index > #text then
            break
        end

        local quote = text:sub(index, index)
        if quote == "\"" or quote == "'" then
            index = index + 1
            local value = {}
            local closed = false
            while index <= #text do
                local character = text:sub(index, index)
                if character == quote then
                    closed = true
                    index = index + 1
                    break
                elseif character == "\\" and index < #text then
                    index = index + 1
                    table.insert(value, text:sub(index, index))
                else
                    table.insert(value, character)
                end
                index = index + 1
            end
            if not closed then
                return nil, "Unclosed quote in stat search."
            end
            table.insert(tokens, { value = table.concat(value), quoted = true })
        else
            local startIndex = index
            while index <= #text and not text:sub(index, index):match("%s") do
                index = index + 1
            end
            table.insert(tokens, {
                value = text:sub(startIndex, index - 1),
                quoted = false,
            })
        end
    end

    return tokens
end

local function parseStatSearchNumber(value)
    local text = trimStatSearchText(value)
    local isDecimal = text:match("^[%+%-]?%d+%.?%d*$") ~= nil
        or text:match("^[%+%-]?%d*%.%d+$") ~= nil
    if not isDecimal then
        return nil
    end

    local number = tonumber(text)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then
        return nil
    end
    return number
end

local statSearchComparisonOperators = { ">=", "<=", ">", "<", "=" }

local function splitStatSearchComparison(value)
    local text = trimStatSearchText(value)
    for _, operator in ipairs(statSearchComparisonOperators) do
        if text:sub(1, #operator) == operator then
            return operator, trimStatSearchText(text:sub(#operator + 1))
        end
    end
    return nil, nil
end

local function consumeStatSearchComparison(tokens, index, field)
    local token = tokens[index]
    if not token then
        return nil, index, nil, false
    end

    local operator, operand = splitStatSearchComparison(token.value)
    if not operator then
        return nil, index, nil, false
    end

    local nextIndex = index + 1
    if operand == "" then
        local operandToken = tokens[nextIndex]
        if not operandToken then
            return nil, index,
                "Missing numeric value after '" .. tostring(field) .. " " .. operator .. "'.", true
        end
        operand = operandToken.value
        nextIndex = nextIndex + 1
    end

    local number = parseStatSearchNumber(operand)
    if number == nil then
        return nil, index,
            "Invalid numeric value '" .. tostring(operand) .. "' for stat '" .. tostring(field) .. "'.", true
    end

    return { operator = operator, number = number }, nextIndex, nil, true
end

local function splitStatSearchClauses(query)
    local raw = trimStatSearchText(query)
    if raw == "" then
        return nil, "Stat search requires at least one stat field."
    end

    local clauses = {}
    local cursor = 1
    while cursor <= #raw + 1 do
        local startIndex, endIndex = raw:find("||", cursor, true)
        local segment
        if startIndex then
            segment = raw:sub(cursor, startIndex - 1)
            cursor = endIndex + 1
        else
            segment = raw:sub(cursor)
            cursor = #raw + 2
        end

        segment = trimStatSearchText(segment)
        if segment == "" then
            return nil, "Each side of '||' must contain a stat expression."
        end
        if segment:find("|", 1, true) then
            return nil, "Use '||' (two pipes) between stat-search clauses."
        end
        table.insert(clauses, segment)
    end

    return clauses
end

function inv.items.getStatSearchFieldNames()
    local fields = {}
    for field in pairs(inv.items.statSearchFieldKinds or {}) do
        table.insert(fields, tostring(field))
    end
    table.sort(fields)
    return fields
end

function inv.items.parseStatSearchQuery(query)
    local segments, splitError = splitStatSearchClauses(query)
    if not segments then
        return nil, splitError
    end

    local spec = {
        clauses = {},
        fields = {},
        primary = nil,
    }
    local seenFields = {}

    for _, segment in ipairs(segments) do
        local tokens, tokenError = tokenizeStatSearchSegment(segment)
        if not tokens then
            return nil, tokenError
        end

        local predicates = {}
        local index = 1
        while index <= #tokens do
            local keyToken = tokens[index]
            local key = tostring(keyToken.value or ""):lower()
            if key == "stat" then
                return nil, "'stat' is the search mode and should appear only once, immediately after 'dinv search'."
            end
            if key:sub(1, 1) == "~" then
                return nil, "Negation is not supported in stat mode; use an explicit comparison instead."
            end

            local kind = inv.items.statSearchFieldKinds[key]
            if not kind then
                return nil, "'" .. tostring(keyToken.value) .. "' is not a searchable stat in stat mode."
            end

            local predicate = { field = key, kind = kind }
            index = index + 1

            if kind == "numeric" then
                local nextToken = tokens[index]
                if nextToken then
                    local nextKey = tostring(nextToken.value or ""):lower()
                    if inv.items.statSearchFieldKinds[nextKey] then
                        -- A following stat key starts another bare predicate.
                    elseif nextKey == "stat" then
                        return nil, "'stat' is the search mode and should not be repeated inside the query."
                    else
                        local comparison, nextIndex, comparisonError, comparisonSeen =
                            consumeStatSearchComparison(tokens, index, key)
                        if comparisonError then
                            return nil, comparisonError
                        elseif comparisonSeen then
                            predicate.comparison = comparison
                            index = nextIndex
                        else
                            local number = parseStatSearchNumber(nextToken.value)
                            if number == nil then
                                return nil, "Invalid numeric value '" .. tostring(nextToken.value) ..
                                    "' for stat '" .. key .. "'."
                            end
                            predicate.comparison = { operator = "=", number = number }
                            index = index + 1
                        end
                    end
                end
            else
                local nextToken = tokens[index]
                if nextToken then
                    local nextKey = tostring(nextToken.value or ""):lower()
                    if nextToken.quoted then
                        predicate.selector = trimStatSearchText(nextToken.value):lower()
                        if predicate.selector == "" then
                            return nil, "The text selector for stat '" .. key .. "' cannot be empty."
                        end
                        index = index + 1

                        local comparison, nextIndex, comparisonError, comparisonSeen =
                            consumeStatSearchComparison(tokens, index, key)
                        if comparisonError then
                            return nil, comparisonError
                        elseif comparisonSeen then
                            predicate.comparison = comparison
                            index = nextIndex
                        elseif tokens[index]
                            and not inv.items.statSearchFieldKinds[tostring(tokens[index].value or ""):lower()] then
                            return nil, "Unexpected value '" .. tostring(tokens[index].value) ..
                                "' after selector for stat '" .. key .. "'."
                        end
                    elseif inv.items.statSearchFieldKinds[nextKey] then
                        -- An unquoted following stat key starts another bare predicate.
                    elseif nextKey == "stat" then
                        return nil, "'stat' is the search mode and should not be repeated inside the query."
                    else
                        local comparison, nextIndex, comparisonError, comparisonSeen =
                            consumeStatSearchComparison(tokens, index, key)
                        if comparisonError then
                            return nil, comparisonError
                        elseif comparisonSeen then
                            predicate.comparison = comparison
                            index = nextIndex
                        else
                            return nil, "Text selectors for stat '" .. key ..
                                "' must be quoted, for example: " .. key .. " \"hit roll\"."
                        end
                    end
                end
            end

            table.insert(predicates, predicate)
            if not spec.primary then
                spec.primary = predicate
            end
            if not seenFields[key] then
                seenFields[key] = true
                table.insert(spec.fields, key)
            end
        end

        if #predicates == 0 then
            return nil, "Each stat-search clause must contain at least one stat field."
        end
        table.insert(spec.clauses, predicates)
    end

    return spec
end

function inv.items.setItem(objId, itemData, options)
    if inv.items.table == nil then
        inv.items.table = {}
    end
    local key = tostring(objId)
    local detachedItem = inv.items.detached and inv.items.detached[key]
    local pendingRemovedItem = inv.items.pendingRemoved and inv.items.pendingRemoved[key]
    local previousItem = inv.items.table[key] or detachedItem
    if itemData then
        itemData.__dinvPresence = "active"
        itemData.__dinvDetachedRoot = nil
        itemData.__dinvRemovedAt = nil
        itemData.__dinvPurgeAfter = nil
        itemData.__dinvRemovalAction = nil
        itemData.__dinvRemovalReason = nil
    end
    inv.items.table[key] = itemData
    if detachedItem then
        inv.items.detached[key] = nil
        if inv.items.refreshInProgress and inv.items.refreshValidation then
            inv.items.refreshValidation.reattached = inv.items.refreshValidation.reattached or {}
            inv.items.refreshValidation.reattached[key] = true
        end
    end
    if pendingRemovedItem then
        inv.items.pendingRemoved[key] = nil
        if inv.items.refreshInProgress and inv.items.refreshValidation then
            inv.items.refreshValidation.pendingReattached =
                inv.items.refreshValidation.pendingReattached or {}
            inv.items.refreshValidation.pendingReattached[key] = true
        end
    end
    if not inv.items.suppressDatabaseWrites and DINV and DINV.database then
        if pendingRemovedItem and DINV.database.markPendingReattached then
            DINV.database.markPendingReattached(
                key,
                itemData,
                inv.items.databaseBuildId and "build" or "active"
            )
        elseif detachedItem and DINV.database.markReattached then
            DINV.database.markReattached(
                key,
                itemData,
                inv.items.databaseBuildId and "build" or "active"
            )
        elseif DINV.database.markItem then
            DINV.database.markItem(key, itemData, inv.items.databaseBuildId and "build" or "active")
        end
    end
    local bulkWorkflow = inv.items.refreshInProgress
        or inv.items.buildInProgress
        or inv.items.identifyInProgress
    local silentApi = options == true
        or (type(options) == "table" and options.silentApi == true)
        or inv.items.suppressApiEvents == true
        or inv.items.isTransientItem(itemData)
    if not bulkWorkflow
        and not silentApi
        and DINV and DINV.api and DINV.api._onItemSet then
        pcall(DINV.api._onItemSet, key, previousItem, itemData)
    end
    return DRL_RET_SUCCESS
end

function inv.items.removeItem(objId, options)
    if inv.items.table or inv.items.detached then
        local key = tostring(objId)
        local previousItem = inv.items.table and inv.items.table[key]
        local detachedItem = inv.items.detached and inv.items.detached[key]
        local pendingRemovedItem = inv.items.pendingRemoved and inv.items.pendingRemoved[key]
        if inv.items.table then inv.items.table[key] = nil end
        if inv.items.detached then inv.items.detached[key] = nil end
        if inv.items.pendingRemoved then inv.items.pendingRemoved[key] = nil end
        local skipDatabase = type(options) == "table" and options.skipDatabase == true
        if not skipDatabase and not inv.items.suppressDatabaseWrites and DINV and DINV.database then
            if previousItem and DINV.database.markDeleted then
                DINV.database.markDeleted(key, inv.items.databaseBuildId and "build" or "active")
            end
            if detachedItem and DINV.database.deleteDetachedItem then
                DINV.database.deleteDetachedItem(key)
            end
            if pendingRemovedItem and DINV.database.deletePendingRemovedItem then
                DINV.database.deletePendingRemovedItem(key)
            end
        end
        local bulkWorkflow = inv.items.refreshInProgress
            or inv.items.buildInProgress
            or inv.items.identifyInProgress
        local silentApi = options == true
            or (type(options) == "table" and options.silentApi == true)
            or inv.items.suppressApiEvents == true
            or inv.items.isTransientItem(previousItem)
        if previousItem
            and not bulkWorkflow
            and not silentApi
            and DINV and DINV.api and DINV.api._onItemRemoved then
            pcall(DINV.api._onItemRemoved, key, previousItem)
        end
    end
    return DRL_RET_SUCCESS
end

function inv.items.removeItemFromCache(objId, item)
    if not objId or not inv.cache or not inv.cache.remove then
        return DRL_RET_SUCCESS
    end

    local key = tostring(objId)
    inv.cache.remove("recent", key)
    inv.cache.remove("custom", key)

    -- A consumed/dropped object must not delete a reusable full consumable
    -- template shared by other objects of the same type and name.

    return DRL_RET_SUCCESS
end

function inv.items.handleMissingItem(objId)
    if not objId then
        return DRL_RET_INVALID_PARAM
    end

    local item = inv.items.getItem(objId)
    inv.items.removeItemFromCache(objId, item)
    inv.items.removeItem(objId)
    inv.items.pendingInvmonSave = true

    if not inv.items.refreshInProgress and not inv.items.buildInProgress and inv.items.save then
        inv.items.save()
    end

    return DRL_RET_SUCCESS
end

function inv.items.removeItemAndSaveNow(objId, source)
    if not objId then
        return DRL_RET_INVALID_PARAM
    end

    local key = tostring(objId)
    local item = inv.items.getItem(key) or inv.items.getDetachedItem(key)
    if item then
        inv.items.removeItemFromCache(key, item)
    end

    inv.items.removeItem(key)

    if inv.items.save then
        local retval = inv.items.save()
        if retval ~= DRL_RET_SUCCESS and retval ~= DRL_RET_UNINITIALIZED then
            dbot.warn(string.format("inv.items.removeItemAndSaveNow: failed to save after removing objId=%s source=%s retval=%s",
                tostring(key),
                tostring(source or "unknown"),
                tostring(retval)
            ))
        else
            dbot.debug(string.format("inv.items.removeItemAndSaveNow: removed objId=%s source=%s",
                tostring(key),
                tostring(source or "unknown")
            ), "inv.items")
        end
    end

    return DRL_RET_SUCCESS
end

function inv.items.applyCachedStats(item)
    if not item or not item.stats then
        return false
    end

    local itemId = item.stats[invStatFieldId]
    local dynamicFields = {
        [invStatFieldId] = true,
        [invStatFieldLocation] = true,
        [invStatFieldContainer] = true,
        [invStatFieldWorn] = true,
        [invStatFieldLastStored] = true,
        [invStatFieldKeepflag] = true,
        [invStatFieldTimer] = true,
    }

    -- A resumed full build may reuse a full record for the exact same object ID.
    -- This is staged build recovery, not a cross-object stat template.
    local staged = itemId and inv.items.buildResumeItems
        and inv.items.buildResumeItems[tostring(itemId)] or nil
    if staged and staged.stats and staged.stats.identifyLevel == invIdLevelFull then
        for key, value in pairs(staged.stats) do
            if not dynamicFields[key] then
                item.stats[key] = value
            end
        end
        item.stats.identifyLevel = invIdLevelFull
        return true
    end

    local itemType = item.stats[invStatFieldType]
    if not inv.items.isFrequentCacheType(itemType) then
        return false
    end

    if DINV and DINV.database and DINV.database.loadConsumableTemplate then
        local template = DINV.database.loadConsumableTemplate(item)
        if template and template.stats and template.stats.identifyLevel == invIdLevelFull then
            for key, value in pairs(template.stats) do
                if not dynamicFields[key] then
                    item.stats[key] = value
                end
            end
            item.stats.identifyLevel = invIdLevelFull
            return true
        end
    end

    if not inv.cache or not inv.cache.get then
        return false
    end

    if itemId then
        local cached = inv.cache.get("recent", tostring(itemId))
        if cached and cached.stats and cached.stats.identifyLevel == invIdLevelFull then
            dbot.debug("Cache hit (recent) for ID: " .. tostring(itemId), "inv.items")
            for k, v in pairs(cached.stats) do
                if k ~= invStatFieldId then
                    if k == invStatFieldWearable and (v == "undefined" or v == "unknown") then
                        -- Keep existing wearable data when cache only has placeholder values.
                    elseif dynamicFields[k] then
                        -- Never restore dynamic protocol state from cache.
                    else
                        item.stats[k] = v
                    end
                end
            end
            item.stats.identifyLevel = invIdLevelFull
            return true
        end
    end

    if inv.items.isFrequentCacheType(itemType) then
        local nameKeys = inv.items.getFrequentCacheKeys(item)
        if nameKeys then
            for _, nameKey in ipairs(nameKeys) do
                local cached = inv.cache.get("frequent", nameKey)
                if cached and cached.stats then
                    local cachedIdentify = cached.stats.identifyLevel or invIdLevelNone
                    if cachedIdentify == invIdLevelFull then
                        dbot.debug("Cache hit (frequent) for: " .. nameKey, "inv.items")
                        for k, v in pairs(cached.stats) do
                            if k ~= invStatFieldId then
                                if k == invStatFieldWearable and (v == "undefined" or v == "unknown") then
                                    -- Keep existing wearable data when cache only has placeholder values.
                                elseif dynamicFields[k] then
                                    -- Never restore dynamic protocol state from cache.
                                else
                                    item.stats[k] = v
                                end
                            end
                        end
                        item.stats.identifyLevel = invIdLevelFull
                        return true
                    end
                end
            end
        end
    end

    return false
end

function inv.items.getFrequentCacheKeys(item)
    if not item or not item.stats then
        return nil
    end

    local name = item.stats[invStatFieldName] or item.stats[invStatFieldColorName]
    if not name or name == "" then
        return nil
    end

    local normalized = dbot.stripColors(name)
    normalized = normalized:gsub(",", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if normalized == "" then
        return nil
    end

    local keys = { normalized }
    local trimmed = normalized:gsub("^:+", ""):gsub(":+$", "")
    if trimmed ~= "" and trimmed ~= normalized then
        table.insert(keys, trimmed)
    end
    local tagStripped = normalized
        :gsub("^%b()%s*", "")
        :gsub("^%b[]%s*", "")
        :gsub("^%b{}%s*", "")
    tagStripped = tagStripped:gsub("^[%p]+%s*", ""):gsub("%s*[%p]+$", "")
    if tagStripped ~= "" and tagStripped ~= normalized then
        table.insert(keys, tagStripped)
        local tagTrimmed = tagStripped:gsub("^:+", ""):gsub(":+$", "")
        if tagTrimmed ~= "" and tagTrimmed ~= tagStripped then
            table.insert(keys, tagTrimmed)
        end
    end
    local typeName = tostring(item.stats[invStatFieldType] or ""):lower()
    if typeName == "" then
        return nil
    end
    for index, key in ipairs(keys) do
        keys[index] = typeName .. "\31" .. key
    end
    return keys
end

function inv.items.getFrequentCacheKey(item)
    local keys = inv.items.getFrequentCacheKeys(item)
    if not keys then
        return nil
    end
    return keys[1]
end

function inv.items.isFrequentCacheType(itemType)
    if not itemType or itemType == "" then
        return false
    end

    local typeName = tostring(itemType):lower()
    return typeName == "potion"
        or typeName == "pill"
        or typeName == "food"
        or typeName == "wand"
        or typeName == "stave"
        or typeName == "scroll"
end

function inv.items.cacheIdentifiedItem(item)
    if not item or not item.stats then
        return
    end

    if item.stats.identifyLevel ~= invIdLevelFull then
        return
    end

    local itemId = item.stats[invStatFieldId]
    if not itemId then
        return
    end

    local itemType = item.stats[invStatFieldType]
    local isFrequent = inv.items.isFrequentCacheType(itemType)

    -- Cross-object reusable stats are safe only for consumables. Equipment,
    -- keys, portals, raw materials, and other items can share names while
    -- having different rarity or randomized stats.
    if not isFrequent then
        return
    end

    if not inv.cache or not inv.cache.set then
        return
    end

    local recent = {}
    for k, v in pairs(item) do
        if k ~= "stats" then
            recent[k] = v
        end
    end
    recent.stats = {}
    for k, v in pairs(item.stats) do
        if k ~= invStatFieldKeepflag and k ~= invStatFieldTimer then
            recent.stats[k] = v
        end
    end
    inv.cache.set("recent", tostring(itemId), recent)

    if isFrequent then
        local nameKeys = inv.items.getFrequentCacheKeys(item)
        if nameKeys then
            local stored = { stats = {} }
            for k, v in pairs(item.stats) do
                if k ~= invStatFieldId
                    and k ~= invStatFieldKeepflag
                    and k ~= invStatFieldTimer
                    and k ~= invStatFieldLocation
                    and k ~= invStatFieldContainer
                    and k ~= invStatFieldWorn
                    and k ~= invStatFieldLastStored then
                    stored.stats[k] = v
                end
            end
            stored.stats.identifyLevel = invIdLevelFull
            for _, nameKey in ipairs(nameKeys) do
                inv.cache.set("frequent", nameKey, stored)
                dbot.debug("Cached '" .. nameKey .. "' to frequent cache", "inv.items")
            end
        end
    end
end

function inv.items.isStorageLocation(location)
    if location == nil or location == "" then
        return false
    end

    if tostring(location) == invItemLocInventory then
        return true
    end

    return inv.items.normalizeContainerId(location) ~= nil
end

function inv.items.updateLocation(item, newLocation)
    if not item or not item.stats then
        return
    end

    if newLocation == nil then
        return
    end

    local currentLocation = item.stats[invStatFieldLocation]
    if currentLocation ~= newLocation then
        if inv.items.isStorageLocation(currentLocation) then
            item.stats[invStatFieldLastStored] = currentLocation
        end
        item.stats[invStatFieldLocation] = newLocation
    end
end

function inv.items.normalizeKeyringLocation(item)
    if not item or not item.stats then
        return false
    end

    local location = tostring(item.stats[invStatFieldLocation] or "")
    local container = tostring(item.stats[invStatFieldContainer] or "")
    local lastStored = tostring(item.stats[invStatFieldLastStored] or "")
    local isKeyring = (location == invItemLocKeyring)
        or (container == invItemLocKeyring)
        or (lastStored == invItemLocKeyring)

    if not isKeyring then
        return false
    end

    item.stats[invStatFieldLocation] = invItemLocKeyring
    item.stats[invStatFieldContainer] = invItemLocKeyring
    item.stats[invStatFieldLastStored] = invItemLocKeyring
    item.stats[invStatFieldWorn] = invItemWornNotWorn
    return true
end

function inv.items.markSoftIdentified(item)
    if not item or not item.stats then
        return
    end

    local level = item.stats.identifyLevel
    if level == nil or level == invIdLevelNone then
        item.stats.identifyLevel = invIdLevelSoft
    end
end

function inv.items.cacheObservedItem(item)
    -- Partial observations belong to the primary item record. They must never
    -- become reusable templates. Full consumable templates are written only by
    -- cacheIdentifiedItem / the SQLite repository.
    return
end

----------------------------------------------------------------------------------------------------
-- Invdata/Eqdata Parsing
----------------------------------------------------------------------------------------------------

function inv.items.updateKeepFlagFromProtocol(item, flags)
    if not item then
        return false
    end

    item.stats = item.stats or {}
    local isKept = tostring(flags or ""):find("K", 1, true) ~= nil
    local changed = item.stats[invStatFieldKeepflag] ~= isKept
    item.stats[invStatFieldKeepflag] = isKept
    return changed
end

function inv.items.updateKeepFlagFromDataLine(dataLine)
    local objId, flags = tostring(dataLine or ""):match("^(%d+),([^,]*),")
    if not objId then
        return DRL_RET_INVALID_PARAM, false
    end

    local item = inv.items.getItem(objId)
    if not item then
        return DRL_RET_MISSING_ENTRY, false
    end

    inv.items.rememberKeepFlagForSync(objId, item)
    local changed = inv.items.updateKeepFlagFromProtocol(item, flags)
    if changed then
        inv.items.setItem(objId, item)
    end
    inv.items.armKeepFlagSyncTimeout()
    return DRL_RET_SUCCESS, changed
end

function inv.items._parseDataLine(dataLine, source)
    if dataLine == nil or dataLine == "" then
        return DRL_RET_SUCCESS
    end

    -- Parse invdata format: objectid,flags,itemname,level,type,unique,wear-loc,timer
    -- Item names can contain commas, so we parse from both ends
    local objId, flags, rest = dataLine:match("^(%d+),([^,]*),(.+)$")
    if not objId then
        dbot.debug("_parseDataLine: Failed initial parse: " .. dataLine:sub(1, 60), "inv.items")
        return DRL_RET_INVALID_PARAM
    end

    if source == "invdata" then
        inv.items.markInvdataSeen(objId)
    end
    if source == "eqdata" then
        inv.items.eqdataSeen = inv.items.eqdataSeen or {}
        inv.items.eqdataSeen[tostring(objId)] = true
    end
    if inv.items.refreshInProgress and source ~= "invitem" then
        inv.items.markRefreshSeen(objId)
    end

    -- Parse from the end: timer,wear-loc,unique,type,level
    -- Find the last 5 comma-separated numeric fields
    local itemName, level, typeField, unique, wearLoc, timer

    -- Match backwards: ,level,type,unique,wearloc,timer at the end
    local nameAndRest = rest
    local endFields = {}
    for i = 1, 5 do
        local beforeComma, afterComma = nameAndRest:match("^(.*),([^,]+)$")
        if beforeComma then
            table.insert(endFields, 1, afterComma)
            nameAndRest = beforeComma
        else
            break
        end
    end

    if #endFields == 5 then
        itemName = nameAndRest
        level = tonumber(endFields[1]) or 0
        typeField = tonumber(endFields[2]) or 0
        unique = tonumber(endFields[3]) or 0
        wearLoc = tonumber(endFields[4]) or 0
        timer = tonumber(endFields[5]) or -1
    else
        -- Fallback: simple split (may fail on names with commas)
        local parts = {}
        for p in dataLine:gmatch("([^,]+)") do
            table.insert(parts, p)
        end
        if #parts >= 8 then
            objId = parts[1]
            flags = parts[2]
            itemName = parts[3]
            level = tonumber(parts[4]) or 0
            typeField = tonumber(parts[5]) or 0
            unique = tonumber(parts[6]) or 0
            wearLoc = tonumber(parts[7]) or 0
            timer = tonumber(parts[8]) or -1
        else
            dbot.debug("_parseDataLine: Missing required fields: " .. dataLine:sub(1, 60), "inv.items")
            return DRL_RET_INVALID_PARAM
        end
    end

    local typeName = inv.items.typeStr[typeField] or "Unknown"
    local wearLocText = (wearLoc == -1 and "undefined") or inv.wearLoc[wearLoc] or "unknown"

    local item = inv.items.getItem(objId)
        or inv.items.getDetachedItem(objId)
        or inv.items.getPendingRemovedItem(objId)
    if item == nil then
        item = { stats = {} }
    end
    local isRefreshExisting = inv.items.refreshInProgress
        and item
        and item.stats
        and item.stats[invStatFieldId]
    item.stats = item.stats or {}
    local existingColorName = item.stats[invStatFieldColorName]
    item.stats[invStatFieldId] = objId
    item.stats[invStatFieldName] = dbot.stripColors(itemName)
    local keepFlagChanged = inv.items.updateKeepFlagFromProtocol(item, flags)
    -- Always update colorname from invdata if we have a valid name
    -- Only keep existing if the new itemName is empty or worse
    if itemName and itemName ~= "" then
        local existingPlain = existingColorName and dbot.stripColors(existingColorName) or ""
        local newPlain = dbot.stripColors(itemName)
        local existingHasColorCodes = existingColorName and tostring(existingColorName):find("@", 1, true) ~= nil
        local newHasColorCodes = tostring(itemName):find("@", 1, true) ~= nil
        if existingHasColorCodes and not newHasColorCodes and newPlain == existingPlain then
            -- Preserve richer colored name when invdata only provides plain text.
            item.stats[invStatFieldColorName] = existingColorName
        -- Use new name if it's longer or existing is empty
        elseif #newPlain >= #existingPlain or existingPlain == "" then
            item.stats[invStatFieldColorName] = itemName
        end
    elseif not existingColorName or existingColorName == "" then
        item.stats[invStatFieldColorName] = itemName
    end
    if not isRefreshExisting then
        item.stats[invStatFieldLevel] = level
        item.stats[invStatFieldType] = typeName
        item.stats[invStatFieldTypeNum] = typeField
        if wearLocText ~= "undefined" and wearLocText ~= "unknown" then
            item.stats[invStatFieldWearable] = wearLocText
        end
        if item.stats.identifyLevel ~= invIdLevelFull then
            item.stats.identifyLevel = invIdLevelPartial
        end
        item.flags = flags
        item.unique = unique
    end
    -- Timer is dynamic. Refreshes must update it even when the item already
    -- has full identify data; otherwise expiring keys keep a stale timer.
    item.stats[invStatFieldTimer] = timer

    local wornValue = (wearLoc and wearLoc >= 0) and wearLocText or invItemWornNotWorn

    if source == "eqdata" then
        item.stats[invStatFieldWorn] = wornValue
        item.stats[invStatFieldContainer] = nil
        if wearLoc and wearLoc > 0 then
            inv.items.updateLocation(item, tostring(wearLoc))
        else
            inv.items.updateLocation(item, wearLocText)
        end
    else
        -- invdata's wear-loc describes where the item *can* be worn. It is
        -- not evidence that an inventory/container item is currently worn.
        item.stats[invStatFieldWorn] = invItemWornNotWorn
        -- Only trust container context while we are actively inside an invdata block.
        -- This guards against stale currentContainerId values leaking into standalone
        -- invdata/itemDataStats callbacks after refresh/build boundaries.
        local containerId = nil
        if inv.items.inInvdata then
            containerId = inv.items.normalizeContainerId(inv.items.currentContainerId)
        end
        if containerId then
            item.stats[invStatFieldContainer] = containerId
            inv.items.updateLocation(item, containerId)
        else
            item.stats[invStatFieldContainer] = ""
            inv.items.updateLocation(item, "inventory")
        end
    end

    local cacheHit = inv.items.applyCachedStats(item)
    if cacheHit then
        dbot.debug("Cache hit: " .. itemName:sub(1, 30), "inv.items")
    end

    inv.items.markSoftIdentified(item)
    inv.items.markLocationObserved(item, source)

    inv.items.setItem(objId, item)
    inv.items.cacheObservedItem(item)

    dbot.debug("Parsed: " .. objId .. " [" .. typeName .. "] " .. itemName:sub(1, 25), "inv.items")

    return DRL_RET_SUCCESS, keepFlagChanged
end

function inv.items.onInvdata(dataLine)
    if inv.items.identifyInProgress then
        dbot.debug("Skipping invdata during identify phase", "inv.items")
        return DRL_RET_SUCCESS
    end
    return inv.items._parseDataLine(dataLine, "invdata")
end

function inv.items.onEqdata(dataLine)
    if inv.items.identifyInProgress then
        dbot.debug("Skipping eqdata during identify phase", "inv.items")
        return DRL_RET_SUCCESS
    end
    return inv.items._parseDataLine(dataLine, "eqdata")
end

function inv.items.onInvitem(dataLine)
    local objId = tostring(dataLine or ""):match("^(%d+),")
    local persisted = nil
    if objId then
        persisted = inv.items.lookupPersistentItem(objId)
    else
        dbot.debug("onInvitem: unable to parse objId for persistence lookup", "inv.items")
    end

    local result = inv.items._parseDataLine(dataLine, "invitem")

    if objId and persisted and persisted.stats then
        local item = inv.items.getItem(objId)
        if item then
            item.stats = item.stats or {}
            for k, v in pairs(persisted.stats) do
                if k ~= invStatFieldKeepflag and item.stats[k] == nil then
                    item.stats[k] = v
                end
            end
            if persisted.stats.identifyLevel == invIdLevelFull then
                item.stats.identifyLevel = invIdLevelFull
                inv.items.ensureKeywordsField(item)
            end
            inv.items.setItem(objId, item)
            dbot.debug("onInvitem: applied persistent stats for objId=" .. tostring(objId), "inv.items")
        end
    end

    if objId then
        local item = inv.items.getItem(objId)
        local idLevel = item and item.stats and item.stats.identifyLevel
        if idLevel ~= invIdLevelFull then
            dbot.debug("onInvitem: stored partial item data; full identify deferred to build/refresh", "inv.items")
        end
    end

    inv.items.scheduleSaveFromInvmon()
    return result
end

function inv.items.onIdentify(dataLine)
    local line = tostring(dataLine or "")
    if line == "" then
        return DRL_RET_SUCCESS
    end

    if line:find(inv.items.identifyFence, 1, true) then
        local currentId = inv.items.identifyCurrentId
        if currentId then
            local item = inv.items.getItem(currentId)
            if item and item.stats then
                item.stats.identifyLevel = invIdLevelFull
                inv.items.ensureKeywordsField(item)
                inv.items.setItem(currentId, item)
                if inv.items.cacheIdentifiedItem then
                    inv.items.cacheIdentifiedItem(item)
                end
            end
        end
        inv.items.identifyContinuationKey = nil
        inv.items.identifyContinuation = nil
        inv.items.identifyRidState = nil
        inv.items.handleIdentifyFence(currentId)
        inv.items.identifyCurrentId = nil
        inv.items.identifyResetId = nil
        return DRL_RET_SUCCESS
    end

    local objId = inv.items.identifyCurrentId or inv.items.currentIdentifyId
    local id = line:match("Id%s*:%s*(%d+)")
    if id then
        objId = tostring(id)
        inv.items.currentIdentifyId = objId
        inv.items.identifyCurrentId = objId
        if inv.items.getItem(objId) == nil then
            inv.items.setItem(objId, { stats = {} })
        end
        if inv.items.identifyResetId ~= objId then
            local resetItem = inv.items.getItem(objId)
            if resetItem then
                inv.items.resetIdentifyStats(resetItem)
                inv.items.resetIdentifyEnchantFields(resetItem)
                inv.items.setItem(objId, resetItem)
            end
            inv.items.identifyResetId = objId
        end
    end

    if not objId then
        return DRL_RET_SUCCESS
    end

    local item = inv.items.getItem(objId)
    if item == nil then
        return DRL_RET_MISSING_ENTRY
    end
    item.stats = item.stats or {}
    local result = inv.items.parseIdentifyLine(item, line)
    inv.items.setItem(objId, item)
    return result
end

-- Discovery / Identification Pipeline

function inv.items.sendDiscoveryCommand(command)
    local cmd = tostring(command or "")
    local requestedContainerId = cmd:match("^invdata%s+(%d+)%s*$")
    local scanAccepted = true
    if requestedContainerId then
        inv.items.awaitingInvdataContainerId = tostring(requestedContainerId)
        scanAccepted = inv.items.expectRefreshScan("invdata", requestedContainerId)
    elseif cmd:match("^invdata%s*$") then
        inv.items.awaitingInvdataContainerId = nil
        scanAccepted = inv.items.expectRefreshScan("invdata", nil)
    elseif cmd:match("^eqdata%s*$") then
        scanAccepted = inv.items.expectRefreshScan("eqdata", nil)
    end

    if scanAccepted == false then
        return DRL_RET_BUSY
    end

    if DINV and DINV.discovery and DINV.discovery.bumpRawSuppressWindow then
        DINV.discovery.bumpRawSuppressWindow(cmd)
    end

    if DINV and DINV.discovery and DINV.discovery.queuePromptSuppress then
        DINV.discovery.queuePromptSuppress()
    end
    sendSilent(cmd)
    return DRL_RET_SUCCESS
end

function inv.items.discoverChain()
    if inv.items.refreshInProgress and inv.items.refreshValidation then
        if inv.items.refreshValidation.discoveryStarted then
            inv.items.invalidateRefresh("refresh discovery was started more than once")
            return
        end
        inv.items.refreshValidation.discoveryStarted = true
    end

    inv.items.discoveryStage = 1
    inv.items.discoveryContainers = {}
    inv.items.discoveryItemCount = 0
    inv.items.currentContainerId = nil
    inv.items.expectedInvdataContainerId = nil
    inv.items.awaitingInvdataContainerId = nil
    inv.items.currentInvdataSeen = nil
    inv.items.inEqdata = false
    inv.items.inInvdata = false
    inv.items.eqdataSeen = {}

    cecho("\n<cyan>[DINV] Stage 1/4: Scanning worn equipment...\n")
    inv.items.progress.stage = "Scanning equipment"
    if DINV and DINV.setBuildPhase then
        DINV.setBuildPhase(1)
    end
    if inv.items.sendDiscoveryCommand then
        inv.items.sendDiscoveryCommand("eqdata")
    else
        sendSilent("eqdata")
    end
end

function inv.items.onEqdataComplete()
    if not inv.items.buildInProgress and not inv.items.refreshInProgress then
        return
    end

    if inv.items.refreshInProgress
        and inv.items.refreshValidation
        and inv.items.refreshValidation.phase == "recheck" then
        inv.items.sendNextRefreshRecheck()
        return
    end

    inv.items.discoveryStage = 2
    local itemCount = inv.items.getCount()

    if not inv.items.refreshInProgress then
        cecho("\n<cyan>[DINV] Stage 2/4: Scanning main inventory... (" .. itemCount .. " items so far)\n")
    end
    inv.items.progress.stage = "Scanning inventory"
    inv.items.progress.current = itemCount
    if DINV and DINV.setBuildPhase then
        DINV.setBuildPhase(2)
    end

    inv.items.expectedInvdataContainerId = nil
    inv.items.awaitingInvdataContainerId = nil
    if inv.items.sendDiscoveryCommand then
        inv.items.sendDiscoveryCommand("invdata")
    else
        sendSilent("invdata")
    end
end

function inv.items.onInvdataComplete(containerId)
    if not inv.items.buildInProgress and not inv.items.refreshInProgress then
        return
    end

    if inv.items.refreshInProgress
        and inv.items.refreshValidation
        and inv.items.refreshValidation.phase == "recheck" then
        inv.items.reconcileInvdataLocations(containerId)
        inv.items.sendNextRefreshRecheck()
        return
    end

    -- If this was a container scan, continue to next container
    local normalizedContainerId = inv.items.normalizeContainerId(containerId)
    if normalizedContainerId then
        inv.items.reconcileInvdataLocations(normalizedContainerId)
        inv.items.discoverNextContainer()
        return
    end

    -- Main invdata complete, now scan containers
    if inv.items.discoveryStage < 3 then
        inv.items.discoveryStage = 3
        inv.items.applyMainInvdataInventoryLocations()
        inv.items.reconcileInvdataLocations(nil)

        local itemCount = inv.items.getCount()
        if not inv.items.refreshInProgress then
            cecho("\n<cyan>[DINV] Stage 3/4: Scanning containers... (" .. itemCount .. " items so far)\n")
        end
        inv.items.progress.stage = "Scanning containers"
        inv.items.progress.current = itemCount
        if DINV and DINV.setBuildPhase then
            DINV.setBuildPhase(3)
        end
        inv.items.discoverContainers()
    end
end

function inv.items.applyMainInvdataInventoryLocations()
    local seen = inv.items.currentInvdataSeen
    if not seen then
        return
    end

    for objId, _ in pairs(seen) do
        local item = inv.items.getItem(objId)
        if item and item.stats then
            item.stats[invStatFieldWorn] = invItemWornNotWorn
            item.stats[invStatFieldContainer] = ""
            inv.items.updateLocation(item, "inventory")
            inv.items.setItem(objId, item)
            inv.items.cacheObservedItem(item)
        end
    end
end

function inv.items.markInvdataSeen(objId)
    if not objId then
        return
    end
    if inv.items.currentInvdataSeen == nil then
        inv.items.currentInvdataSeen = {}
    end
    inv.items.currentInvdataSeen[tostring(objId)] = true
end

function inv.items.markRefreshSeen(objId)
    if not objId then
        return
    end
    if inv.items.refreshSeen == nil then
        inv.items.refreshSeen = {}
    end
    inv.items.refreshSeen[tostring(objId)] = true
end

function inv.items.reconcileInvdataLocations(containerId)
    local seen = inv.items.currentInvdataSeen or {}
    local locationKey = "inventory"
    local normalizedContainerId = inv.items.normalizeContainerId(containerId)
    if normalizedContainerId then
        locationKey = normalizedContainerId
    end

    if not inv.items.refreshInProgress then
        for objId, item in pairs(inv.items.table or {}) do
            if item and item.stats then
                if item.stats[invStatFieldLocation] == locationKey
                    and not seen[tostring(objId)] then
                    inv.items.updateLocation(item, "unknown")
                    inv.items.cacheObservedItem(item)
                end
            end
        end
    end

    inv.items.currentInvdataSeen = nil
    inv.items.awaitingInvdataContainerId = nil
end

function inv.items.pruneRefreshOrphans()
    if not inv.items.refreshSeen then
        return
    end

    local unseen = 0
    local removedSingletons = 0
    local detachedItems = {}
    local pendingSingletons = {}
    local candidates = {}
    local startEventSequence = tonumber(inv.items.refreshValidation
        and inv.items.refreshValidation.startEventSequence) or 0
    for objId, item in pairs(inv.items.table or {}) do
        if not inv.items.refreshSeen[tostring(objId)] then
            local container = item and item.stats and item.stats[invStatFieldContainer] or ""
            if container ~= "" and inv.config.isIgnored(container) then
                -- Keep items in ignored containers.
            else
                if item and inv.items.normalizeKeyringLocation(item) then
                    inv.items.cacheObservedItem(item)
                    inv.items.setItem(objId, item)
                    dbot.debug(string.format("Refresh kept keyring item objId=%s name=%s", tostring(objId), tostring(item.stats[invStatFieldName] or "unknown")), "inv.items")
                else
                    local lastEventSequence = tonumber(item and item.__dinvLastEventSeq) or 0
                    if lastEventSequence > startEventSequence then
                        dbot.debug("Refresh kept item changed after scan start: " .. tostring(objId), "inv.items")
                    else
                        candidates[tostring(objId)] = item
                    end
                end
            end
        end
    end

    local groups = {}
    for objId, item in pairs(candidates) do
        local rootId = objId
        local visited = { [objId] = true }
        local parentId = item and item.stats
            and inv.items.normalizeContainerId(item.stats[invStatFieldContainer]) or nil
        while parentId and candidates[parentId] and not visited[parentId] do
            rootId = parentId
            visited[parentId] = true
            local parent = candidates[parentId]
            parentId = parent and parent.stats
                and inv.items.normalizeContainerId(parent.stats[invStatFieldContainer]) or nil
        end
        groups[rootId] = groups[rootId] or {}
        groups[rootId][objId] = item
    end

    for rootId, group in pairs(groups) do
        local groupSize = dbot.table.getNumEntries(group)
        if groupSize == 1 then
            local objId, item = next(group)
            if inv.items.isFullyIdentified(item) then
                table.insert(pendingSingletons, { objId = objId, item = item })
            else
                local finalized = inv.items.finalizeRemovedFromInventory(
                    objId, nil, "refresh_confirmed_absent", 0)
                if finalized then
                    unseen = unseen + 1
                    removedSingletons = removedSingletons + 1
                    dbot.debug("Refresh reconciled confirmed-absent singleton " ..
                        tostring(objId), "inv.items")
                else
                    dbot.warn("Refresh could not reconcile unseen singleton " ..
                        tostring(objId) .. "; keeping it active")
                end
            end
        else
            local detached = DINV and DINV.database and DINV.database.detachItems
                and DINV.database.detachItems(group, rootId)
            if detached then
                inv.items.detached = inv.items.detached or {}
                for objId, item in pairs(group) do
                    item.__dinvPresence = "detached"
                    item.__dinvDetachedRoot = rootId
                    inv.items.detached[objId] = item
                    inv.items.table[objId] = nil
                    table.insert(detachedItems, {
                        objId = tostring(objId),
                        name = tostring(item and item.stats and item.stats[invStatFieldName] or "unknown"),
                        colorName = tostring(item and item.stats and item.stats[invStatFieldColorName] or ""),
                    })
                    unseen = unseen + 1
                end
            else
                dbot.warn("Refresh could not detach unseen subtree rooted at " .. tostring(rootId) .. "; keeping it active")
            end
        end
    end

    if #pendingSingletons > 0 then
        local moved, movedCount = inv.items.moveItemsToPendingRemoval(
            pendingSingletons, "refresh_confirmed_absent", 0)
        if moved then
            unseen = unseen + movedCount
            removedSingletons = removedSingletons + movedCount
        else
            dbot.warn("Refresh could not preserve " .. tostring(#pendingSingletons) ..
                " fully identified unseen singleton(s); keeping them active")
        end
    end

    if unseen > 0 then
        dbot.debug(string.format(
            "Refresh reconciled %d unseen item(s): detached=%d removed=%d",
            unseen, #detachedItems, removedSingletons
        ), "inv.items")
        if #detachedItems > 0 then
            dbot.print("")
            for _, detached in ipairs(detachedItems) do
                local displayName = detached.colorName
                if not displayName or displayName == "" then
                    displayName = detached.name or "Unidentified"
                end
                dbot.print("@C[DINV INFO]@W Detached unseen item: \"" .. tostring(displayName) .. "@W\" (" .. tostring(detached.objId) .. ")")
            end
        end
        inv.items.pendingInvmonSave = true
    end
end

function inv.items.buildRefreshRecheckQueue()
    if not inv.items.refreshSeen then
        return {}
    end

    local scopes = {}
    for objId, item in pairs(inv.items.table or {}) do
        if not inv.items.refreshSeen[tostring(objId)] and item and item.stats then
            local location = tostring(item.stats[invStatFieldLocation] or "")
            local container = tostring(item.stats[invStatFieldContainer] or "")
            local worn = tostring(item.stats[invStatFieldWorn] or "")

            if not inv.items.normalizeKeyringLocation(item)
                and not (container ~= "" and inv.config.isIgnored(container)) then
                local isWorn = location == tostring(invItemLocWorn or "worn")
                    or (worn ~= ""
                        and worn ~= "undefined"
                        and worn ~= tostring(invItemWornNotWorn or "not-worn"))
                    or (inv.items.resolveWearSlot and inv.items.resolveWearSlot(location) ~= nil)
                local containerId = inv.items.normalizeContainerId(container)
                if not containerId and not isWorn then
                    containerId = inv.items.normalizeContainerId(location)
                end

                if isWorn then
                    scopes.worn = { kind = "eqdata" }
                elseif containerId then
                    scopes["container:" .. containerId] = {
                        kind = "invdata",
                        containerId = containerId,
                    }
                elseif location == tostring(invItemLocInventory or "inventory")
                    or location == "" then
                    scopes.inventory = { kind = "invdata" }
                end
            end
        end
    end

    local queue = {}
    if scopes.worn then
        table.insert(queue, scopes.worn)
    end
    if scopes.inventory then
        table.insert(queue, scopes.inventory)
    end

    local containerIds = {}
    for key, scope in pairs(scopes) do
        if scope.containerId then
            table.insert(containerIds, scope.containerId)
        end
    end
    table.sort(containerIds, function(left, right)
        return tostring(left) < tostring(right)
    end)
    for _, containerId in ipairs(containerIds) do
        table.insert(queue, scopes["container:" .. containerId])
    end

    return queue
end

function inv.items.startRefreshRecheck()
    local validation = inv.items.refreshValidation
    if not inv.items.refreshInProgress or not validation then
        return false
    end

    local recheckStart = dbot.perfNow and dbot.perfNow() or nil
    validation.initialComplete = true
    validation.phase = "recheck"
    inv.items.refreshRecheckQueue = inv.items.buildRefreshRecheckQueue()
    inv.items.refreshRecheckIndex = 0
    dbot.perf(
        "refresh build recheck queue size=" .. tostring(#inv.items.refreshRecheckQueue),
        recheckStart
    )

    if #inv.items.refreshRecheckQueue == 0 then
        validation.recheckComplete = true
        return false
    end

    dbot.debug("Refresh verifying " .. #inv.items.refreshRecheckQueue ..
        " location(s) containing unseen items.", "inv.items")
    inv.items.sendNextRefreshRecheck()
    return true
end

function inv.items.sendNextRefreshRecheck()
    local validation = inv.items.refreshValidation
    if not inv.items.refreshInProgress or not validation then
        return
    end

    inv.items.refreshRecheckIndex = (inv.items.refreshRecheckIndex or 0) + 1
    local scope = inv.items.refreshRecheckQueue
        and inv.items.refreshRecheckQueue[inv.items.refreshRecheckIndex]
        or nil
    if not scope then
        validation.recheckComplete = true
        dbot.perf("refresh recheck complete", inv.items.refreshPerfStart)
        inv.items.finishDiscovery()
        return
    end

    inv.items.currentInvdataSeen = nil
    inv.items.inEqdata = false
    inv.items.inInvdata = false
    if scope.kind == "eqdata" then
        inv.items.sendDiscoveryCommand("eqdata")
    elseif scope.containerId then
        inv.items.expectedInvdataContainerId = tostring(scope.containerId)
        inv.items.sendDiscoveryCommand("invdata " .. tostring(scope.containerId))
    else
        inv.items.expectedInvdataContainerId = nil
        inv.items.sendDiscoveryCommand("invdata")
    end
end

function inv.items.discoverContainers()
    inv.items.discoveryContainers = {}

    for objId, item in pairs(inv.items.table or {}) do
        local typeNum = item.stats and item.stats[invStatFieldTypeNum]

        -- Type 11 = Container
        if typeNum == 11 then
            -- Skip containers with 0 capacity (card cases, etc.)
            local capacity = item.stats and item.stats[invStatFieldCapacity]
            if not capacity or capacity > 0 then
                table.insert(inv.items.discoveryContainers, objId)
                local name = (item.stats and item.stats[invStatFieldName]) or "container"
                dbot.debug("Queue container: " .. objId .. " = " .. name:sub(1, 30), "inv.items")
            else
                dbot.debug("Skipping empty container: " .. objId, "inv.items")
            end
        end
    end

    local numContainers = #inv.items.discoveryContainers
    if numContainers == 0 then
        dbot.debug("No containers found to scan", "inv.items")
        if inv.items.refreshInProgress and inv.items.startRefreshRecheck() then
            return
        end
        inv.items.finishDiscovery()
        return
    end

    if not inv.items.refreshInProgress then
        cecho("\n<cyan>[DINV] Found " .. numContainers .. " container(s) to scan\n")
    end
    inv.items.containerIndex = 0
    inv.items.discoverNextContainer()
end

function inv.items.discoverNextContainer()
    inv.items.containerIndex = (inv.items.containerIndex or 0) + 1

    if inv.items.containerIndex > #inv.items.discoveryContainers then
        inv.items.containerIndex = 0
        inv.items.expectedInvdataContainerId = nil
        inv.items.awaitingInvdataContainerId = nil
        dbot.debug("Finished scanning all containers", "inv.items")
        if inv.items.refreshInProgress and inv.items.startRefreshRecheck() then
            return
        end
        inv.items.finishDiscovery()
        return
    end

    local containerId = inv.items.discoveryContainers[inv.items.containerIndex]
    inv.items.expectedInvdataContainerId = tostring(containerId)
    local item = inv.items.getItem(containerId)
    local containerName = (item and item.stats and item.stats[invStatFieldName]) or "container"

    dbot.debug("Scanning container " .. inv.items.containerIndex .. "/" .. #inv.items.discoveryContainers .. ": " .. containerName:sub(1, 30), "inv.items")

    if inv.items.sendDiscoveryCommand then
        inv.items.sendDiscoveryCommand("invdata " .. containerId)
    else
        sendSilent("invdata " .. containerId)
    end

    -- Refresh relies on invdata completion markers that can occasionally be delayed,
    -- so toggle prompt back immediately after the final container command is sent.
    if inv.items.refreshInProgress and inv.items.containerIndex == #inv.items.discoveryContainers then
        sendSilent("prompt")
    end
end

function inv.items.finishDiscovery()
    if inv.items.refreshInProgress then
        local finishStart = dbot.perfNow and dbot.perfNow() or nil
        dbot.perf("refresh finish begin", inv.items.refreshPerfStart)
        local validation = inv.items.refreshValidation
        local validationStart = dbot.perfNow and dbot.perfNow() or nil
        if validation then
            for key, requestedCount in pairs(validation.requested or {}) do
                local completedCount = validation.completed
                    and validation.completed[key]
                    or 0
                if completedCount ~= requestedCount then
                    inv.items.invalidateRefresh("scan count mismatch for " .. tostring(key) ..
                        " (requested " .. tostring(requestedCount) ..
                        ", completed " .. tostring(completedCount) .. ")")
                end
            end
        end
        dbot.perf("refresh finish validation", validationStart)
        if not validation
            or not validation.valid
            or validation.expected ~= nil
            or not validation.discoveryStarted
            or not validation.initialComplete
            or not validation.recheckComplete then
            if validation and validation.valid then
                inv.items.invalidateRefresh("refresh ended before all required scans completed")
            end
            inv.items.abortInvalidRefresh()
            return
        end

        local refreshOriginalTable = validation.originalTable
        inv.items.suppressDatabaseWrites = validation.previousSuppressDatabaseWrites == true
        if DINV and DINV.database and DINV.database.markReattached then
            for objId, _ in pairs(validation.reattached or {}) do
                local item = inv.items.table and inv.items.table[tostring(objId)] or nil
                if item then
                    DINV.database.markReattached(objId, item)
                end
            end
        end
        if DINV and DINV.database and DINV.database.markPendingReattached then
            for objId, _ in pairs(validation.pendingReattached or {}) do
                local item = inv.items.table and inv.items.table[tostring(objId)] or nil
                if item then
                    DINV.database.markPendingReattached(objId, item)
                end
            end
        end
        inv.items.applyWorkflowRemovalEvents("refresh_complete")
        local pruneStart = dbot.perfNow and dbot.perfNow() or nil
        inv.items.pruneRefreshOrphans()
        dbot.perf("refresh prune orphans", pruneStart)
        inv.items.refreshSeen = nil
        inv.items.refreshValidation = nil
        inv.items.refreshRecheckQueue = nil
        inv.items.refreshRecheckIndex = nil
        inv.items.refreshInProgress = false

        inv.items.discoveryStage = 0
        inv.items.awaitingInvdataContainerId = nil
        inv.state = invStateIdle
        if DINV and DINV.setBuildPhase then
            DINV.setBuildPhase(0)
        end
        dbot.debug("Refresh complete: inventory locations updated.", "inv.items")

        -- Refresh changes dynamic fields (location/container/worn) via invdata/eqdata,
        -- so persist immediately when refresh completes.
        if inv.items.save then
            local saveStart = dbot.perfNow and dbot.perfNow() or nil
            local saveRet, purgedPendingIds = inv.items.save({
                pendingRemovalPurgeCutoff = os.time(),
            })
            dbot.perf("refresh save items", saveStart)
            if saveRet == DRL_RET_SUCCESS then
                local purgedCount = inv.items.removePurgedPendingItems(purgedPendingIds)
                dbot.debug("Refresh complete: persisted inventory state; purged pending=" ..
                    tostring(purgedCount) .. ".", "inv.items")
            else
                dbot.warn("Refresh completed, but SQLite persistence failed; pending removals were not purged.")
            end
        end

        if inv.items.pendingInvmonSave then
            inv.items.pendingInvmonSave = nil
            dbot.debug("Refresh complete: cleared pending invmon save flag.", "inv.items")
        end

        if inv.items.refreshIdentifyPartials then
            inv.items.refreshIdentifyPartials = false
            local partialStart = dbot.perfNow and dbot.perfNow() or nil
            local identifyRet = inv.items.identifyPartialItems()
            dbot.perf("refresh start partial identify", partialStart)
            if identifyRet ~= DRL_RET_SUCCESS then
                dbot.warn("Refresh complete: unable to start partial identification (" .. tostring(identifyRet) .. ")")
            end
        else
            inv.items.eqdataSeen = {}
        end
        if DINV and DINV.api and DINV.api._onRefreshComplete then
            local apiStart = dbot.perfNow and dbot.perfNow() or nil
            pcall(DINV.api._onRefreshComplete, refreshOriginalTable)
            dbot.perf("refresh API complete callbacks", apiStart)
        end
        inv.items.maybeStartKeepFlagSync()
        if not inv.items.buildInProgress and not inv.items.identifyInProgress then
            inv.items.scheduleDeferredIdentifyProcessing("refreshComplete")
        end
        dbot.perf("refresh finish total", finishStart)
        return
    end

    inv.items.discoveryStage = 4
    local itemCount = inv.items.getCount()

    cecho("\n<cyan>[DINV] Stage 4/4: Identifying " .. itemCount .. " items...\n")
    inv.items.progress.stage = "Identifying items"
    inv.items.progress.total = itemCount

    inv.items.discoveryComplete = true
    inv.state = invStateIdentify
    -- Persist the complete discovery snapshot into build staging before the
    -- one-item-per-second identify phase begins.
    if inv.items.databaseBuildId and inv.items.save then
        inv.items.save()
    end
    inv.items.startIdentification()
end

function inv.items.discoverLocation(location)
    if location == invItemLocWorn then
        if inv.items.sendDiscoveryCommand then
            inv.items.sendDiscoveryCommand("eqdata")
        else
            sendSilent("eqdata")
        end
    elseif location and location ~= "" then
        if inv.items.sendDiscoveryCommand then
            inv.items.sendDiscoveryCommand("invdata " .. location)
        else
            sendSilent("invdata " .. location)
        end
    else
        if inv.items.sendDiscoveryCommand then
            inv.items.sendDiscoveryCommand("invdata")
        else
            sendSilent("invdata")
        end
    end
    return DRL_RET_SUCCESS
end

function inv.items.discoverCR()
    if inv.items.sendDiscoveryCommand then
        inv.items.sendDiscoveryCommand("eqdata")
    else
        sendSilent("eqdata")
    end

    if tempTimer then
        tempTimer(1.0, function()
            if inv.items.sendDiscoveryCommand then
                inv.items.sendDiscoveryCommand("invdata")
            else
                sendSilent("invdata")
            end
        end)
    end

    return DRL_RET_SUCCESS
end

function inv.items.identifyItem(objId, commandArray)
    if not objId then
        return DRL_RET_INVALID_PARAM
    end
    local cmd = "identify " .. tostring(objId)
    inv.items.prepareIdentify(objId)
    if commandArray then
        table.insert(commandArray, cmd)
        table.insert(commandArray, "echo " .. inv.items.identifyFence)
        return DRL_RET_SUCCESS
    end

    local commands = { cmd, "echo " .. inv.items.identifyFence }
    return dbot.execute.safe.commands(commands, nil, nil, nil, nil)
end

function inv.items.identifyCR()
    for objId, item in pairs(inv.items.table or {}) do
        local idLevel = item.stats and item.stats.identifyLevel
        if idLevel == nil or idLevel == invIdLevelNone then
            send("identify " .. objId)
        end
    end
    return DRL_RET_SUCCESS
end

function inv.items.identifyPartialItems()
    local partialStart = dbot.perfNow and dbot.perfNow() or nil
    if inv.items.buildInProgress or inv.items.identifyInProgress then
        return DRL_RET_BUSY
    end

    dbot.perf("identifyPartialItems begin")
    inv.items.partialIdentifyMode = true
    inv.items.identifyPartialOnly = true
    inv.items.buildInProgress = true
    inv.items.identifyInProgress = false
    inv.items.forceIdentify = false
    inv.items.progress.stage = "Identifying partial items"
    inv.items.progress.startTime = os.time()

    if DINV and DINV.setBuildPhase then
        DINV.setBuildPhase(4)
    end

    inv.state = invStateIdentify
    inv.items.startIdentification()
    dbot.perf("identifyPartialItems setup", partialStart)
    return DRL_RET_SUCCESS
end

function inv.items.startIdentification()
    local startIdentificationPerf = dbot.perfNow and dbot.perfNow() or nil
    inv.items.clearInlineProgress()
    inv.items.identifyQueue = {}
    inv.items.identifyIndex = 0

    -- Build queue of items needing identification
    for objId, item in pairs(inv.items.table or {}) do
        local idLevel = item.stats and item.stats.identifyLevel

        if inv.items.forceIdentify then
            table.insert(inv.items.identifyQueue, objId)
        elseif inv.items.identifyPartialOnly then
            if idLevel == invIdLevelPartial then
                local cacheHit = inv.items.applyCachedStats(item)
                if not cacheHit then
                    table.insert(inv.items.identifyQueue, objId)
                end
            end
        else
            -- Queue items that are NOT fully identified
            -- nil/none/soft = never seen, partial = seen via invdata/eqdata but not identified
            if idLevel == nil or idLevel == invIdLevelNone or idLevel == invIdLevelSoft or idLevel == invIdLevelPartial then
                local cacheHit = inv.items.applyCachedStats(item)
                if not cacheHit then
                    table.insert(inv.items.identifyQueue, objId)
                end
            end
        end
    end

    inv.items.identifyTotal = #inv.items.identifyQueue
    dbot.perf(
        "startIdentification queue build total=" .. tostring(inv.items.identifyTotal),
        startIdentificationPerf
    )

    if inv.items.identifyTotal == 0 then
        cecho("\n<green>[DINV] All items already identified (or cached)!\n")
        local completeStart = dbot.perfNow and dbot.perfNow() or nil
        inv.items.buildComplete()
        dbot.perf("startIdentification buildComplete no queue", completeStart)
        return
    end

    local identifyMessage = inv.items.forceIdentify and "Need to process " or "Need to identify "
    cecho("\n<cyan>[DINV] " .. identifyMessage .. inv.items.identifyTotal .. " item(s)...\n")
    if DINV and DINV.setBuildPhase then
        DINV.setBuildPhase(4)
		sendGMCP("config prompt off")
    end
    inv.items.buildInProgress = true
    inv.items.identifyInProgress = true
    inv.items.progress.total = inv.items.identifyTotal
    inv.items.progress.startTime = os.time()

    -- Register identify triggers
    if DINV.discovery and DINV.discovery.registerIdentifyTriggers then
        DINV.discovery.registerIdentifyTriggers()
    end

    -- Start identifying
    inv.items.identifyNext()
end

function inv.items.identifyNext()
    -- Check if we were aborted
    if not inv.items.buildInProgress then
        return
    end

    inv.items.identifyWaitForInvmon = nil
    inv.items.identifyWaitForFence = nil

    local queue = inv.items.identifyQueue or {}
    local nextIndex = (inv.items.identifyIndex or 0) + 1

    -- Skip stale queue entries that disappeared before identification.
    while nextIndex <= #queue do
        local candidateId = queue[nextIndex]
        if inv.items.getItem(candidateId) then
            break
        end
        dbot.debug("identifyNext: skipping missing queued item objId=" .. tostring(candidateId), "inv.items")
        table.remove(queue, nextIndex)
        inv.items.identifyTotal = #queue
        if inv.items.progress then
            inv.items.progress.total = #queue
        end
    end

    inv.items.identifyQueue = queue

    if nextIndex > #queue then
        inv.items.identifyIndex = nextIndex
        inv.items.identifyInProgress = false
        inv.items.identifyPausedForCombat = nil
        inv.items.identifyCurrentId = nil
        inv.items.identifyCurrentContainer = nil

        if DINV.discovery and DINV.discovery.unregisterIdentifyTriggers then
            DINV.discovery.unregisterIdentifyTriggers()
        end

        inv.items.buildComplete()
        return
    end

    if dbot.gmcp and dbot.gmcp.stateIsInCombat and dbot.gmcp.stateIsInCombat() then
        if not inv.items.identifyPausedForCombat then
            inv.items.identifyPausedForCombat = true
            dbot.debug("identifyNext: in combat, pausing identify until combat ends", "inv.items")
        end
        tempTimer(0.3, function()
            if inv.items.buildInProgress and inv.items.identifyInProgress then
                inv.items.identifyNext()
            end
        end)
        return
    end
    inv.items.identifyPausedForCombat = nil
    inv.items.identifyIndex = nextIndex

    local objId = queue[inv.items.identifyIndex]
    local item = inv.items.getItem(objId)

    if not item then
        -- Item disappeared after queue compaction; move to next.
        tempTimer(0.1, function() inv.items.identifyNext() end)
        return
    end

    local itemType = item.stats and item.stats[invStatFieldType]
    local stagedResume = inv.items.buildResumeItems
        and inv.items.buildResumeItems[tostring(objId)] or nil
    local hasStagedFull = stagedResume and stagedResume.stats
        and stagedResume.stats.identifyLevel == invIdLevelFull
    local canUseCache = hasStagedFull
        or not inv.items.forceIdentify
        or inv.items.isFrequentCacheType(itemType)
    if canUseCache and inv.items.applyCachedStats(item) then
        item.stats.identifyLevel = invIdLevelFull
        inv.items.setItem(objId, item)
        local cachedName = (item.stats and item.stats[invStatFieldColorName])
            or (item.stats and item.stats[invStatFieldName])
            or "Unknown"
        inv.items.showProgress("Identifying", inv.items.identifyIndex, inv.items.progress.total,
                               cachedName .. " @w(cached)")
        tempTimer(0.05, function()
            if inv.items.buildInProgress and inv.items.identifyInProgress then
                inv.items.identifyNext()
            end
        end)
        return
    end

    inv.items.identifyCurrentId = objId
    inv.items.identifyEnchantResetId = nil
    -- Prefer colorname, fall back to name, then Unknown
    local itemName = (item.stats and item.stats[invStatFieldColorName])
        or (item.stats and item.stats[invStatFieldName])
        or "Unknown"

    -- Show progress
    inv.items.showProgress("Identifying", inv.items.identifyIndex, inv.items.progress.total, itemName)

    -- Determine item location
    local containerId = item.stats and item.stats[invStatFieldContainer]
    local location = item.stats and item.stats[invStatFieldLocation]
    local seenInEqdata = inv.items.eqdataSeen and inv.items.eqdataSeen[tostring(objId)] == true
    local isWorn = seenInEqdata
    if not isWorn and inv.items.isWornLocation then
        isWorn = inv.items.isWornLocation(objId, location)
    end

    local normalizedContainerId = inv.items.normalizeContainerId(containerId)
    if normalizedContainerId then
        -- Item is in a container
        inv.items.identifyCurrentContainer = normalizedContainerId
        inv.items.identifyFromContainer(objId, normalizedContainerId)
    elseif isWorn then
        -- Item is worn - identify directly (no need to remove for identify)
        inv.items.identifyCurrentContainer = nil
        inv.items.identifyDirect(objId, true)
    else
        -- Item is in main inventory
        inv.items.identifyCurrentContainer = nil
        inv.items.identifyDirect(objId, false)
    end
end

function inv.items.identifyDirect(objId, isWorn, containerId)
    dbot.debug("Identify direct: " .. objId, "inv.items")

    local command = "identify " .. objId
    if isWorn then
        command = command .. " worn"
    end

    inv.items.prepareIdentify(objId)

    inv.items.identifyWaitForFence = {
        objId = objId,
        containerId = containerId,
        nextStep = "advance"
    }

    -- Send identify command and fence marker
    sendSilent(command)
    sendSilent("echo " .. inv.items.identifyFence)
end

function inv.items.prepareIdentify(objId)
    local item = inv.items.getItem(objId)
    if not item then
        return
    end
    item.stats = item.stats or {}
    item.stats.identifyLevel = invIdLevelNone
    inv.items.resetIdentifyEnchantFields(item)

    local resetFields = {
        invStatFieldStr,
        invStatFieldInt,
        invStatFieldWis,
        invStatFieldDex,
        invStatFieldCon,
        invStatFieldLuck,
        invStatFieldHitroll,
        invStatFieldDamroll,
        invStatFieldHp,
        invStatFieldMana,
        invStatFieldMoves,
        invStatFieldAllPhys,
        invStatFieldAllMagic,
        invStatFieldAveDam,
        invStatFieldAcid,
        invStatFieldCold,
        invStatFieldEnergy,
        invStatFieldHoly,
        invStatFieldElectric,
        invStatFieldNegative,
        invStatFieldShadow,
        invStatFieldMagic,
        invStatFieldAir,
        invStatFieldEarth,
        invStatFieldFire,
        invStatFieldLight,
        invStatFieldMental,
        invStatFieldSonic,
        invStatFieldWater,
        invStatFieldPoison,
        invStatFieldDisease,
        invStatFieldSlash,
        invStatFieldPierce,
        invStatFieldBash,
    }

    for _, field in ipairs(resetFields) do
        item.stats[field] = 0
    end
end

function inv.items.identifyFromContainer(objId, containerId)
    -- Ensure IDs are in usable formats
    objId = tostring(objId or "")
    containerId = inv.items.normalizeContainerId(containerId)

    dbot.debug("Identify from container: objId=" .. tostring(objId) .. " containerId=" .. tostring(containerId), "inv.items")

    if objId == "" or not containerId then
        dbot.debug("identifyFromContainer: Invalid objId or containerId", "inv.items")
        tempTimer(0.1, function()
            if inv.items.buildInProgress and inv.items.identifyInProgress then
                inv.items.identifyNext()
            end
        end)
        return
    end

    -- Set up the wait state BEFORE sending command
    inv.items.identifyWaitForInvmon = {
        objId = objId,              -- Store as string
        containerId = containerId,  -- Store as string
        action = 5,                 -- invmonActionTakenOutOfContainer
        nextStep = "identify"
    }

    -- Remember which container this item is in
    inv.items.identifyCurrentContainer = containerId

    -- Send the get command
    dbot.debug("Sending: get " .. objId .. " " .. containerId, "inv.items")
    sendSilent("get " .. objId .. " " .. containerId)

    -- Set up timeout in case invmon doesn't fire
    local expectedObjId = objId
    local expectedContainerId = containerId

    tempTimer(2.0, function()  -- Increased timeout to 2 seconds
        local waitState = inv.items.identifyWaitForInvmon
        if not waitState then
            -- Wait state was cleared, invmon was handled
            dbot.debug("identifyFromContainer timeout: wait state already cleared (good)", "inv.items")
            return
        end

        -- Check if this timeout is for our request
        local waitObjId = tostring(waitState.objId)
        local waitContainerId = waitState.containerId and tostring(waitState.containerId) or nil

        if waitObjId ~= expectedObjId or waitContainerId ~= expectedContainerId then
            dbot.debug("identifyFromContainer timeout: wait state is for different item", "inv.items")
            return
        end

        dbot.debug("identifyFromContainer timeout: invmon not received, falling back to direct identify", "inv.items")
        inv.items.handleIdentifyGetFailure("invmon timeout")
    end)
end

function inv.items.handleIdentifyGetFailure(reason)
    dbot.debug("handleIdentifyGetFailure: " .. tostring(reason), "inv.items")

    if not inv.items.buildInProgress or not inv.items.identifyInProgress then
        dbot.debug("handleIdentifyGetFailure: Not in build/identify mode, ignoring", "inv.items")
        return false
    end

    local waitState = inv.items.identifyWaitForInvmon
    if not waitState then
        dbot.debug("handleIdentifyGetFailure: No wait state, ignoring", "inv.items")
        return false
    end

    if waitState.nextStep ~= "identify" then
        dbot.debug("handleIdentifyGetFailure: nextStep is not 'identify', ignoring", "inv.items")
        return false
    end

    local objId = tostring(waitState.objId or "")

    -- Clear the wait state
    inv.items.identifyWaitForInvmon = nil

    -- Remember the container for putting back later
    local containerId = inv.items.normalizeContainerId(waitState.containerId)
    inv.items.identifyCurrentContainer = containerId

    dbot.debug("handleIdentifyGetFailure: Falling back to direct identify for objId=" .. tostring(objId), "inv.items")

    -- Try direct identify - the item might already be in main inventory
    -- or we might need to identify it in place
    inv.items.identifyDirect(objId, false, containerId)
    return true
end

function inv.items.handleIdentifyFence(fallbackObjId)
    dbot.debug("handleIdentifyFence: fallbackObjId=" .. tostring(fallbackObjId), "inv.items")

    local waitState = inv.items.identifyWaitForFence

    -- If no wait state but we have a fallback and container, create one
    if not waitState and fallbackObjId and inv.items.identifyCurrentContainer then
        dbot.debug("handleIdentifyFence: Creating wait state from fallback", "inv.items")
        waitState = {
            objId = fallbackObjId,
            containerId = inv.items.identifyCurrentContainer,
            nextStep = "put"
        }
    end

    if not waitState then
        dbot.debug("handleIdentifyFence: No wait state, ignoring", "inv.items")
        return
    end

    if not inv.items.buildInProgress or not inv.items.identifyInProgress then
        dbot.debug("handleIdentifyFence: Not in build/identify mode, clearing state", "inv.items")
        inv.items.identifyWaitForFence = nil
        return
    end

    -- Clear the wait state
    inv.items.identifyWaitForFence = nil

    local objId = tostring(waitState.objId or "")
    local targetContainer = inv.items.normalizeContainerId(waitState.containerId)
        or inv.items.normalizeContainerId(inv.items.identifyCurrentContainer)

    dbot.debug("handleIdentifyFence: objId=" .. tostring(objId) .. " targetContainer=" .. tostring(targetContainer), "inv.items")

    -- Mark item as fully identified - we extracted all available stats
    local item = inv.items.getItem(objId)
    local createdMissing = inv.items.identifyCreatedMissing and inv.items.identifyCreatedMissing[objId]
    local sawIdentifyOutput = inv.items.identifySawOutput and inv.items.identifySawOutput[objId]
    local hydratedFromInvdata = inv.items.identifyHydratedFromInvdata
        and inv.items.identifyHydratedFromInvdata[objId]
    if createdMissing and not sawIdentifyOutput then
        if inv.items.table then
            inv.items.table[objId] = nil
        end
        if inv.items.identifyCreatedMissing then
            inv.items.identifyCreatedMissing[objId] = nil
        end
        if inv.items.identifySawOutput then
            inv.items.identifySawOutput[objId] = nil
        end
        item = nil
        dbot.debug("handleIdentifyFence: no identify output for new objId=" .. tostring(objId) .. "; not persisting", "inv.items")
    elseif hydratedFromInvdata and not sawIdentifyOutput then
        if item and item.stats then
            item.stats.identifyLevel = invIdLevelPartial
            inv.items.setItem(objId, item)
        end
        if inv.items.identifyHydratedFromInvdata then
            inv.items.identifyHydratedFromInvdata[objId] = nil
        end
        if inv.items.identifySawOutput then
            inv.items.identifySawOutput[objId] = nil
        end
        dbot.debug("handleIdentifyFence: no identify output for hydrated objId=" .. tostring(objId) .. "; keeping invdata only", "inv.items")
    elseif item and item.stats then
        item.stats.identifyLevel = invIdLevelFull
        inv.items.ensureKeywordsField(item)
        dbot.debug("handleIdentifyFence: Marked item as identified", "inv.items")

        inv.items.setItem(objId, item)
        if inv.items.databaseBuildId then
            inv.items.databaseBuildIdentifiedSinceFlush =
                (tonumber(inv.items.databaseBuildIdentifiedSinceFlush) or 0) + 1
            if inv.items.databaseBuildIdentifiedSinceFlush >=
                (tonumber(inv.items.databaseBuildBatchSize) or 10) then
                inv.items.save()
            end
        end
        if inv.items.identifyCreatedMissing then
            inv.items.identifyCreatedMissing[objId] = nil
        end
        if inv.items.identifySawOutput then
            inv.items.identifySawOutput[objId] = nil
        end
        if inv.items.identifyHydratedFromInvdata then
            inv.items.identifyHydratedFromInvdata[objId] = nil
        end

        -- Cache the identified item
        if inv.items.cacheIdentifiedItem then
            inv.items.cacheIdentifiedItem(item)
        end
    end

    -- If the item came from a container, put it back
    if targetContainer then
        dbot.debug("handleIdentifyFence: Putting item back in container " .. tostring(targetContainer), "inv.items")

        -- Short delay before putting back
        tempTimer(0.3, function()
            if not inv.items.buildInProgress or not inv.items.identifyInProgress then
                return
            end

            if item and item.stats then
                item.stats[invStatFieldContainer] = targetContainer
                item.stats[invStatFieldLocation] = targetContainer
                inv.items.setItem(objId, item)
            end

            -- Set up wait state for put confirmation
            inv.items.identifyWaitForInvmon = {
                objId = objId,
                containerId = targetContainer,
                action = 6,  -- invmonActionPutIntoContainer
                nextStep = "advance"
            }

            sendSilent("put " .. objId .. " " .. targetContainer)

            -- Timeout for put operation
            local expectedObjId = objId
            tempTimer(2.0, function()
                local putWaitState = inv.items.identifyWaitForInvmon
                if not putWaitState then
                    return  -- Already handled
                end
                if tostring(putWaitState.objId) ~= expectedObjId then
                    return  -- Different item
                end

                dbot.debug("handleIdentifyFence: Put timeout, advancing anyway", "inv.items")
                inv.items.identifyWaitForInvmon = nil
                inv.items.identifyCurrentContainer = nil

                tempTimer(0.1, function()
                    if inv.items.buildInProgress and inv.items.identifyInProgress then
                        inv.items.identifyNext()
                    end
                end)
            end)
        end)
        return
    end

    -- Item was not from container, or no container - advance immediately
    dbot.debug("handleIdentifyFence: No container, advancing to next item", "inv.items")
    inv.items.identifyCurrentContainer = nil

    tempTimer(0.1, function()
        if inv.items.buildInProgress and inv.items.identifyInProgress then
            inv.items.identifyNext()
        end
    end)
end

function inv.items.restoreBuildOriginalState(reason)
    local restored = inv.items.buildOriginalTable or {}
    local restoredDetached = inv.items.buildOriginalDetached or {}
    local restoredPendingRemoved = inv.items.buildOriginalPendingRemoved or {}
    local current = inv.items.table or {}
    local startEventSequence = tonumber(inv.items.buildStartEventSequence) or 0
    local reattached = {}
    local pendingReattached = {}

    for objId, currentItem in pairs(current) do
        if (tonumber(currentItem and currentItem.__dinvLastEventSeq) or 0) > startEventSequence then
            local key = tostring(objId)
            if restoredDetached[key] then reattached[key] = currentItem end
            if restoredPendingRemoved[key] then pendingReattached[key] = currentItem end
            restored[key] = currentItem
            restoredDetached[key] = nil
            restoredPendingRemoved[key] = nil
        end
    end
    for objId, eventSeq in pairs(inv.items.eventTombstones or {}) do
        if (tonumber(eventSeq) or 0) > startEventSequence then
            restored[tostring(objId)] = nil
            restoredDetached[tostring(objId)] = nil
            restoredPendingRemoved[tostring(objId)] = nil
        end
    end

    inv.items.table = restored
    inv.items.detached = restoredDetached
    inv.items.pendingRemoved = restoredPendingRemoved
    if DINV and DINV.database and DINV.database.discardPending then
        DINV.database.discardPending("active")
    end
    if DINV and DINV.database and DINV.database.markReattached then
        for objId, item in pairs(reattached) do
            DINV.database.markReattached(objId, item, "active")
        end
    end
    if DINV and DINV.database and DINV.database.markPendingReattached then
        for objId, item in pairs(pendingReattached) do
            DINV.database.markPendingReattached(objId, item, "active")
        end
    end
    inv.items.applyWorkflowRemovalEvents(tostring(reason or "build_restore"))
    if inv.items.save then
        inv.items.save()
    end

    inv.items.buildOriginalTable = nil
    inv.items.buildOriginalDetached = nil
    inv.items.buildOriginalPendingRemoved = nil
    inv.items.buildStartEventSequence = nil
end

function inv.items.buildComplete()
    inv.items.finalizeInlineProgress()
    if inv.items.singleIdentifyMode then
        local singleId = inv.items.singleIdentifyId
        inv.items.singleIdentifyMode = false
        inv.items.singleIdentifyId = nil
        inv.items.buildInProgress = false
        inv.items.identifyInProgress = false
        inv.items.forceIdentify = false
        inv.items.eqdataSeen = {}
        for objId, _ in pairs(inv.items.identifyCreatedMissing or {}) do
            if inv.items.table then
                inv.items.table[tostring(objId)] = nil
            end
        end
        inv.items.identifyCreatedMissing = {}
        inv.items.identifySawOutput = {}
        inv.items.identifyHydratedFromInvdata = {}
        inv.state = invStateIdle
        if DINV and DINV.setBuildPhase then
            DINV.setBuildPhase(0)
            sendGMCP("config prompt on")
        end
        if inv.organize and inv.organize.syncRulesFromConfig then
            inv.organize.syncRulesFromConfig({ warnMissing = false, saveItems = false })
        end
        if inv.items.save then
            inv.items.save()
        end
        if raiseEvent and singleId then
            raiseEvent("DINV.identifyComplete", tostring(singleId))
        end
        if DINV and DINV.api and DINV.api._onIdentifyComplete and singleId then
            pcall(DINV.api._onIdentifyComplete, tostring(singleId))
        end
        dbot.debug("buildComplete: single-item identify complete for objId=" .. tostring(singleId), "inv.items")
        inv.items.scheduleDeferredIdentifyProcessing("buildComplete")
        inv.items.maybeStartKeepFlagSync()
        return
    end

    local wasPartialIdentify = inv.items.partialIdentifyMode
        or inv.items.identifyPartialOnly

    inv.items.buildInProgress = false
    inv.items.identifyInProgress = false
    inv.items.forceIdentify = false
    inv.items.partialIdentifyMode = false
    inv.items.identifyPartialOnly = false
    inv.items.refreshIdentifyPartials = false
    inv.items.eqdataSeen = {}
    inv.state = invStateIdle
    if DINV and DINV.setBuildPhase then
        DINV.setBuildPhase(0)
		sendGMCP("config prompt on")
    end
    if inv.organize and inv.organize.syncRulesFromConfig then
        inv.organize.syncRulesFromConfig({ warnMissing = false, saveItems = false })
    end
    local retainBuildRemovalEvents = inv.items.databaseBuildId ~= nil
    inv.items.applyWorkflowRemovalEvents(
        "build_complete",
        retainBuildRemovalEvents and { retainApplied = true } or nil
    )

    -- Count results
    local totalItems = 0
    local identifiedItems = 0
    local partialItems = 0
    local containerItems = 0

    for objId, item in pairs(inv.items.table or {}) do
        totalItems = totalItems + 1
        local idLevel = item.stats and item.stats.identifyLevel
        if idLevel == invIdLevelFull then
            identifiedItems = identifiedItems + 1
        elseif idLevel == invIdLevelPartial then
            partialItems = partialItems + 1
        end
        if item.stats and item.stats[invStatFieldContainer] then
            containerItems = containerItems + 1
        end
    end

    -- Calculate time
    local elapsed = os.time() - (inv.items.progress.startTime or os.time())
    local minutes = math.floor(elapsed / 60)
    local seconds = elapsed % 60

    -- Save data. A full build is staged and becomes primary only after this
    -- final transaction; partial-identify runs update the active inventory.
    local persistenceRet = inv.items.save and inv.items.save() or DRL_RET_INTERNAL_ERROR
    if persistenceRet ~= DRL_RET_SUCCESS then
        local failedBuildId = inv.items.databaseBuildId
        if failedBuildId and DINV and DINV.database and DINV.database.interruptBuild then
            DINV.database.interruptBuild(failedBuildId)
        end
        inv.items.databaseBuildId = nil
        inv.items.databaseBuildIdentifiedSinceFlush = 0
        dbot.deleteTimer(inv.items.timer.databaseBatchName)
        inv.items.restoreBuildOriginalState("build_save_failure")
        dbot.warn("Build activation was cancelled because the SQLite batch could not be committed; the active inventory was restored.")
        return
    end
    if inv.items.databaseBuildId then
        local buildId = inv.items.databaseBuildId
        local finished, finishErr = DINV.database.finishBuild(buildId)
        if not finished then
            DINV.database.interruptBuild(buildId)
            inv.items.databaseBuildId = nil
            inv.items.databaseBuildIdentifiedSinceFlush = 0
            dbot.deleteTimer(inv.items.timer.databaseBatchName)
            inv.items.restoreBuildOriginalState("build_activation_failure")
            dbot.warn("Build staging was preserved, activation failed, and the active inventory was restored: " .. tostring(finishErr))
            return
        end
        inv.items.databaseBuildId = nil
        inv.items.buildResumeItems = nil
        dbot.deleteTimer(inv.items.timer.databaseBatchName)
        if retainBuildRemovalEvents then
            inv.items.workflowRemovalEvents = {}
        end
    end
    if not wasPartialIdentify then
        if inv.config and inv.config.table then
            inv.config.table.isBuildExecuted = true
        end
        if inv.config and inv.config.save then inv.config.save() end
    end

    if wasPartialIdentify then
        dbot.note("Partial identify complete. Fully identified: " ..
            tostring(identifiedItems) .. "; partial: " .. tostring(partialItems) .. ".")
        inv.items.maybeStartKeepFlagSync()
        inv.items.scheduleDeferredIdentifyProcessing("partialIdentifyComplete")
        return
    end

    -- Print results
    cecho("\n")
    cecho("<yellow>================================================================================\n")
    cecho("<green>  DINV Inventory Build Complete!\n")
    cecho("<yellow>================================================================================\n")
    cecho("\n")
    cecho("<white>  Results:\n")
    cecho("<white>    Total items found:    <green>" .. totalItems .. "\n")
    cecho("<white>    Fully identified:     <green>" .. identifiedItems .. "\n")
    if partialItems > 0 then
        cecho("<white>    Partially identified: <yellow>" .. partialItems .. "\n")
    end
    cecho("<white>    Items in containers:  <green>" .. containerItems .. "\n")
    cecho("<white>    Time elapsed:         <green>" .. minutes .. "m " .. seconds .. "s\n")
    cecho("\n")
    cecho("<white>  Your inventory is ready! Try:\n")
    cecho("<white>    <green>dinv search type weapon<white>  - View all weapons\n")
    cecho("<white>    <green>dinv help<white>               - See all commands\n")
    cecho("\n")

    local endTag = inv.items.buildEndTag
    inv.items.buildEndTag = nil

    if endTag and inv.tags and inv.tags.stop then
        inv.tags.stop(invTagsBuild, endTag, DRL_RET_SUCCESS)
    end
    local buildOriginalTable = inv.items.buildOriginalTable
    inv.items.buildOriginalTable = nil
    inv.items.buildOriginalDetached = nil
    inv.items.buildOriginalPendingRemoved = nil
    inv.items.buildStartEventSequence = nil
    if DINV and DINV.api and DINV.api._onBuildComplete then
        pcall(DINV.api._onBuildComplete, buildOriginalTable)
    end
    inv.items.maybeStartKeepFlagSync()
    inv.items.scheduleDeferredIdentifyProcessing("buildComplete")
end

function inv.items.buildAbort(options)
    if not inv.items.buildInProgress and not inv.items.identifyInProgress then
        dbot.info("No build is currently in progress.")
        return DRL_RET_SUCCESS
    end
    local quiet = options == true
        or (type(options) == "table" and options.quiet == true)
    local interrupt = type(options) == "table" and options.interrupt == true

    -- Stop everything
    inv.items.clearInlineProgress()
    inv.items.buildInProgress = false
    inv.items.identifyInProgress = false
    inv.items.identifyQueue = {}
    inv.items.identifyWaitForInvmon = nil
    inv.items.identifyWaitForFence = nil
    inv.items.eqdataSeen = {}
    inv.items.identifyCurrentId = nil
    inv.items.identifyCurrentContainer = nil
    inv.items.identifyIndex = nil
    inv.items.forceIdentify = false
    inv.items.partialIdentifyMode = false
    inv.items.identifyPartialOnly = false
    inv.items.refreshIdentifyPartials = false
    for objId, _ in pairs(inv.items.identifyCreatedMissing or {}) do
        if inv.items.table then
            inv.items.table[tostring(objId)] = nil
        end
    end
    inv.items.identifyCreatedMissing = {}
    inv.items.identifySawOutput = {}
    inv.items.identifyHydratedFromInvdata = {}
    local hasBuildSnapshot = inv.items.buildOriginalTable ~= nil
    if inv.items.databaseBuildId and DINV and DINV.database then
        local persistenceOk, persistenceErr
        if interrupt and DINV.database.interruptBuild then
            persistenceOk, persistenceErr = DINV.database.interruptBuild(inv.items.databaseBuildId)
        elseif DINV.database.abortBuild then
            persistenceOk, persistenceErr = DINV.database.abortBuild(inv.items.databaseBuildId)
        elseif DINV.database.interruptBuild then
            persistenceOk, persistenceErr = DINV.database.interruptBuild(inv.items.databaseBuildId)
        end
        if persistenceOk == false then
            dbot.warn("Unable to finalize SQLite build staging: " .. tostring(persistenceErr))
        end
    end
    inv.items.databaseBuildId = nil
    inv.items.buildResumeItems = nil
    inv.items.databaseBuildIdentifiedSinceFlush = 0
    dbot.deleteTimer(inv.items.timer.databaseBatchName)
    if hasBuildSnapshot then
        inv.items.restoreBuildOriginalState(interrupt and "build_interrupt" or "build_abort")
    else
        inv.items.applyWorkflowRemovalEvents("identify_abort")
        if inv.items.save then inv.items.save() end
    end
    inv.state = invStateIdle
    if DINV and DINV.setBuildPhase then
        DINV.setBuildPhase(0)
		sendGMCP("config prompt on")
    end

    -- Unregister identify triggers
    if DINV.discovery and DINV.discovery.unregisterIdentifyTriggers then
        DINV.discovery.unregisterIdentifyTriggers()
    end

    if not quiet then
        cecho("\n<yellow>[DINV] Build aborted by user.\n")
    end

    local endTag = inv.items.buildEndTag
    inv.items.buildEndTag = nil

    if endTag and inv.tags and inv.tags.stop then
        inv.tags.stop(invTagsBuild, endTag, DRL_RET_HALTED)
    end

    if not quiet then
        inv.items.maybeStartKeepFlagSync()
    end
    return DRL_RET_SUCCESS
end

function inv.items.onInvmon(dataLine)
    local wearInvmonTimingWall, wearInvmonTimingCpu = nil, nil
    if DINV and DINV.debug and DINV.debug.beginWearTimingSample then
        wearInvmonTimingWall, wearInvmonTimingCpu = DINV.debug.beginWearTimingSample()
    end

    -- Normalize and de-duplicate payloads because some environments can
    -- fire both package and temporary discovery triggers for {invmon}.
    local normalizedDataLine = tostring(dataLine or ""):gsub("^%s+", ""):gsub("%s+$", "")

    -- Debug: Show that onInvmon was called
    dbot.debug("onInvmon called with: " .. tostring(normalizedDataLine), "inv.items")

    if normalizedDataLine == "" then
        dbot.debug("onInvmon: Failed to parse dataLine", "inv.items")
        return DRL_RET_INVALID_PARAM
    end

    local now = os.clock()
    local lastPayload = inv.items._invmonLastPayload
    local lastAt = tonumber(inv.items._invmonLastAt) or 0
    if lastPayload == normalizedDataLine and (now - lastAt) <= 0.05 then
        dbot.debug("onInvmon: Duplicate payload suppressed", "inv.items")
        return DRL_RET_SUCCESS
    end
    inv.items._invmonLastPayload = normalizedDataLine
    inv.items._invmonLastAt = now

    -- Parse the invmon data
    local action, objId, containerId, wearLoc = normalizedDataLine:match("^([0-9]+),([0-9%-]+),([0-9%-]+),([0-9%-]+)$")
    if not action then
        dbot.debug("onInvmon: Failed to parse dataLine", "inv.items")
        return DRL_RET_INVALID_PARAM
    end

    -- Convert to numbers
    local actionNum = tonumber(action) or 0
    objId = tostring(objId)
    containerId = tostring(containerId)
    wearLoc = tonumber(wearLoc)
    local eventSeq = inv.items.nextEventSequence()

    if objId == "" then
        dbot.debug("onInvmon: objId is empty after parse", "inv.items")
        return DRL_RET_INVALID_PARAM
    end

    dbot.debug(string.format("onInvmon parsed: action=%d, objId=%s, containerId=%s, wearLoc=%s",
        actionNum, tostring(objId), tostring(containerId), tostring(wearLoc)), "inv.items")

    -- Check if we have a wait state for the identify process
    local waitState = inv.items.identifyWaitForInvmon
    local item = inv.items.getItem(objId)
        or inv.items.getDetachedItem(objId)
        or inv.items.getPendingRemovedItem(objId)
    local actionName = invmon and invmon.action and invmon.action[actionNum] or "Unknown"
    local eventReason = actionNum == invmonActionConsumed
        and "consumed_or_rotted" or tostring(actionName):lower()
    if DINV and DINV.database then
        if actionNum == invmonActionConsumed and DINV.database.recordTerminalRemoval then
            local persisted, persistErr = DINV.database.recordTerminalRemoval(
                eventSeq, objId, actionNum, eventReason, containerId, wearLoc
            )
            if not persisted then
                dbot.warn("Unable to persist consumed/rotted removal immediately: " .. tostring(persistErr))
                if DINV.database.recordInventoryEvent then
                    DINV.database.recordInventoryEvent(
                        eventSeq, objId, actionNum, eventReason, containerId, wearLoc
                    )
                end
            end
        elseif DINV.database.recordInventoryEvent then
            DINV.database.recordInventoryEvent(
                eventSeq, objId, actionNum, eventReason, containerId, wearLoc
            )
        end
    end
    local preLocation = item and item.stats and item.stats[invStatFieldLocation] or "unknown"
    local preContainer = item and item.stats and item.stats[invStatFieldContainer] or ""
    local itemName = item
        and item.stats
        and (item.stats[invStatFieldColorName] or item.stats[invStatFieldName])
        or "unknown item"
    dbot.debug(
        string.format(
            "Invmon action=%s(%s) objId=%s name=%s containerId=%s wearLoc=%s location=%s container=%s",
            tostring(actionNum),
            tostring(actionName),
            tostring(objId),
            tostring(itemName),
            tostring(containerId),
            tostring(wearLoc),
            tostring(preLocation),
            tostring(preContainer)
        ),
        "invmon"
    )
    local waitHandled = false

    -- Debug: Show current state
    dbot.debug(string.format("onInvmon state: waitState=%s, buildInProgress=%s, identifyInProgress=%s",
        waitState and "yes" or "no",
        tostring(inv.items.buildInProgress),
        tostring(inv.items.identifyInProgress)), "inv.items")

    -- Check if this invmon should advance the identify process
    if waitState then
        -- Normalize waitState.objId for comparison (always treat as string)
        local waitObjId = tostring(waitState.objId)
        local waitContainerId = waitState.containerId and tostring(waitState.containerId) or nil
        local waitAction = tonumber(waitState.action)

        dbot.debug(string.format("onInvmon comparing: waitObjId=%s vs objId=%s, waitAction=%s vs action=%s, waitContainerId=%s vs containerId=%s",
            tostring(waitObjId), tostring(objId),
            tostring(waitAction), tostring(actionNum),
            tostring(waitContainerId), tostring(containerId)), "inv.items")

        local actionMatch = (actionNum == waitAction)
        local objIdMatch = (tostring(objId) == tostring(waitObjId))
        local containerMatch = (waitContainerId == nil or waitContainerId == containerId)

        dbot.debug(string.format("onInvmon match results: action=%s, objId=%s, container=%s",
            tostring(actionMatch), tostring(objIdMatch), tostring(containerMatch)), "inv.items")

        if inv.items.buildInProgress
            and inv.items.identifyInProgress
            and actionMatch
            and objIdMatch
            and containerMatch then

            dbot.debug("onInvmon: All conditions match! Advancing identify process.", "inv.items")

            -- Clear the wait state FIRST to prevent timeout
            inv.items.identifyWaitForInvmon = nil
            waitHandled = true

            if waitState.nextStep == "identify" then
                dbot.debug("onInvmon: nextStep=identify, sending identify command", "inv.items")

                -- Set up fence wait state
                inv.items.identifyWaitForFence = {
                    objId = objId,
                containerId = containerId,
                nextStep = "put"
            }

                -- Store the current container for putting back later
                inv.items.identifyCurrentContainer = containerId

                -- Send identify command and fence marker
                sendSilent("identify " .. objId)
                sendSilent("echo " .. inv.items.identifyFence)

            elseif waitState.nextStep == "advance" then
                dbot.debug("onInvmon: nextStep=advance, moving to next item", "inv.items")

                -- Item was put back, advance to next
                inv.items.identifyCurrentContainer = nil
                tempTimer(0.1, function()
                    if inv.items.buildInProgress and inv.items.identifyInProgress then
                        inv.items.identifyNext()
                    end
                end)
            end
        else
            dbot.debug("onInvmon: Conditions did not match for identify wait state", "inv.items")
        end
    end

    -- Update item location in our tracking (both during build and after)
    local shouldSave = false
    local forceImmediateSave = false

    -- Any action other than explicit consumption indicates the item still exists
    -- somewhere, so cancel delayed removal if one is pending.
    if actionNum ~= invmonActionConsumed then
        inv.items.cancelPendingRemoval(objId)
        if inv.items.workflowRemovalEvents then
            inv.items.workflowRemovalEvents[tostring(objId)] = nil
        end
    end

    if item then
		
        if actionNum == invmonActionRemoved then
            if inv.portal and inv.portal.pendingUseId and inv.portal.noteRemoved then
                inv.portal.noteRemoved(objId, wearLoc)
            end
            -- Item was removed (un-worn)
            item.stats = item.stats or {}
            item.stats[invStatFieldWorn] = invItemWornNotWorn
            item.stats[invStatFieldLocation] = "inventory"
            if inv.items.eqdataSeen then
                inv.items.eqdataSeen[tostring(objId)] = nil
            end
            dbot.debug("onInvmon: Item removed from worn slot", "inv.items")
            shouldSave = true

        elseif actionNum == invmonActionWorn then
            -- Item was worn
            item.stats = item.stats or {}
            local wornLoc = inv.wearLoc and inv.wearLoc[wearLoc] or tostring(wearLoc)
            item.stats[invStatFieldWorn] = wornLoc
            if wearLoc and wearLoc > 0 then
                item.stats[invStatFieldLocation] = tostring(wearLoc)
            else
                item.stats[invStatFieldLocation] = wornLoc
            end
            item.stats[invStatFieldContainer] = nil
            inv.items.eqdataSeen = inv.items.eqdataSeen or {}
            inv.items.eqdataSeen[tostring(objId)] = true
            dbot.debug("onInvmon: Item worn at " .. tostring(wornLoc), "inv.items")
            shouldSave = true

        elseif actionNum == invmonActionRemovedFromInv then
            -- Action 3 means item is gone from inventory (dropped/given away).
            inv.items.cancelPendingRemoval(objId)
            if inv.items.eqdataSeen then
                inv.items.eqdataSeen[tostring(objId)] = nil
            end
            if inv.items.buildInProgress or inv.items.refreshInProgress or inv.items.identifyInProgress then
                item.stats = item.stats or {}
                item.stats[invStatFieldWorn] = invItemWornNotWorn
                item.stats[invStatFieldContainer] = ""
                inv.items.updateLocation(item, "unknown")
                inv.items.recordWorkflowRemoval(objId, actionNum, eventSeq)
                dbot.debug("onInvmon: Deferred action 3 removal during active workflow", "inv.items")
                shouldSave = true
            else
                local finalized = inv.items.finalizeRemovedFromInventory(
                    objId, eventSeq, "invmon_removed_from_inventory", actionNum
                )
                if finalized then
                    item = nil
                    dbot.debug("onInvmon: Item removed, pending, or subtree detached after action 3", "inv.items")
                else
                    dbot.warn("Unable to reconcile removed inventory object " .. tostring(objId) ..
                        "; retaining its active record")
                end
                shouldSave = true
            end

        elseif actionNum == invmonActionAddedToInv then
            -- Item was added to inventory
            item.stats = item.stats or {}
            item.stats[invStatFieldLocation] = "inventory"
            item.stats[invStatFieldContainer] = nil
            item.stats[invStatFieldWorn] = invItemWornNotWorn
            if inv.items.eqdataSeen then
                inv.items.eqdataSeen[tostring(objId)] = nil
            end
            dbot.debug("onInvmon: Item added to inventory", "inv.items")
            -- An invitem message can arrive before action 4 and reactivate the
            -- root by itself. Always reconcile descendants by this exact
            -- detached-root ID so that ordering cannot strand the subtree.
            forceImmediateSave = inv.items.reattachDetachedSubtree(objId, eventSeq) > 0
            shouldSave = true

        elseif actionNum == invmonActionTakenOutOfContainer then
            -- Item was taken out of container (action 5)
            item.stats = item.stats or {}
            local normalizedContainerId = inv.items.normalizeContainerId(containerId)
            item.stats[invStatFieldLocation] = "inventory"
            item.stats[invStatFieldContainer] = nil
            item.stats[invStatFieldWorn] = invItemWornNotWorn
            if inv.items.eqdataSeen then
                inv.items.eqdataSeen[tostring(objId)] = nil
            end
            if normalizedContainerId then
                item.stats[invStatFieldLastStored] = normalizedContainerId
            end
            dbot.debug("onInvmon: Item taken from container " .. tostring(containerId), "inv.items")
            shouldSave = true

        elseif actionNum == invmonActionPutIntoContainer then
            -- Item was put into container (action 6)
            item.stats = item.stats or {}
            local normalizedContainerId = inv.items.normalizeContainerId(containerId)
            if normalizedContainerId then
                item.stats[invStatFieldLocation] = normalizedContainerId
                item.stats[invStatFieldContainer] = normalizedContainerId
                item.stats[invStatFieldLastStored] = normalizedContainerId
            end
            item.stats[invStatFieldWorn] = invItemWornNotWorn
            if inv.items.eqdataSeen then
                inv.items.eqdataSeen[tostring(objId)] = nil
            end
            dbot.debug("onInvmon: Item put into container " .. tostring(containerId), "inv.items")
            shouldSave = true

        elseif actionNum == invmonActionPutIntoVault then
            item.stats = item.stats or {}
            item.stats[invStatFieldLocation] = "vault"
            item.stats[invStatFieldContainer] = "vault"
            item.stats[invStatFieldWorn] = invItemWornNotWorn
            item.__dinvLastEventSeq = eventSeq
            local workflowActive = inv.items.buildInProgress or inv.items.refreshInProgress
                or inv.items.identifyInProgress
            if not workflowActive and inv.items.table[tostring(objId)] then
                inv.items.detachSubtree(objId, "invmon_put_into_vault")
                item = nil
            elseif workflowActive then
                inv.items.recordWorkflowRemoval(objId, actionNum, eventSeq)
            end
            dbot.debug("onInvmon: Item put into vault", "inv.items")
            shouldSave = true

        elseif actionNum == invmonActionRemovedFromVault then
            item.stats = item.stats or {}
            item.stats[invStatFieldLocation] = invItemLocInventory
            item.stats[invStatFieldContainer] = nil
            item.stats[invStatFieldWorn] = invItemWornNotWorn
            dbot.debug("onInvmon: Item removed from vault", "inv.items")
            -- Vault retrieval has the same possible invitem-before-invmon
            -- ordering as a normal get. The root-scoped lookup is a no-op
            -- when this object has no detached subtree.
            forceImmediateSave = inv.items.reattachDetachedSubtree(objId, eventSeq) > 0
            shouldSave = true

        elseif actionNum == invmonActionPutIntoKeyring then
            -- Item was put into keyring (action 11)
            item.stats = item.stats or {}
            item.stats[invStatFieldLocation] = invItemLocKeyring
            item.stats[invStatFieldContainer] = invItemLocKeyring
            item.stats[invStatFieldLastStored] = invItemLocKeyring
            item.stats[invStatFieldWorn] = invItemWornNotWorn
            if inv.items.eqdataSeen then
                inv.items.eqdataSeen[tostring(objId)] = nil
            end
            dbot.debug("onInvmon: Item put into keyring", "inv.items")
            shouldSave = true

        elseif actionNum == invmonActionGetFromKeyring then
            -- Item was removed from keyring (action 12)
            item.stats = item.stats or {}
            item.stats[invStatFieldLocation] = invItemLocInventory
            item.stats[invStatFieldContainer] = nil
            item.stats[invStatFieldWorn] = invItemWornNotWorn
            if inv.items.eqdataSeen then
                inv.items.eqdataSeen[tostring(objId)] = nil
            end
            dbot.debug("onInvmon: Item removed from keyring", "inv.items")
            shouldSave = true
        elseif actionNum == invmonActionConsumed then
            -- Item was consumed (quaffed, eaten, rotted) - action 7
            inv.items.cancelPendingRemoval(objId)
            if inv.items.eqdataSeen then
                inv.items.eqdataSeen[tostring(objId)] = nil
            end
            inv.items.eventTombstones[tostring(objId)] = eventSeq
            inv.items.removeItemAndSaveNow(objId, "invmon_consumed_or_rotted")
            item = nil
            dbot.debug("onInvmon: Item consumed or rotted: " .. tostring(objId), "inv.items")
            shouldSave = false
        end
    elseif actionNum == invmonActionAddedToInv then
        -- New item added - create an entry for it
        if inv.items.eqdataSeen then
            inv.items.eqdataSeen[tostring(objId)] = nil
        end
        local newItem = { stats = {
            [invStatFieldId] = tostring(objId),
            [invStatFieldLocation] = "inventory",
            [invStatFieldWorn] = invItemWornNotWorn,
            identifyLevel = invIdLevelNone,
        } }
        inv.items.markLocationObserved(newItem, "invmon", eventSeq)
        inv.items.setItem(objId, newItem)
        item = newItem
        dbot.debug("onInvmon: New item added to inventory: " .. tostring(objId), "inv.items")
        shouldSave = true
    else
        dbot.debug(
            string.format(
                "Invmon action=%s(%s) for unknown objId=%s (no item to update)",
                tostring(actionNum),
                tostring(actionName),
                tostring(objId)
            ),
            "invmon"
        )
    end

    if item then
        inv.items.markLocationObserved(item, "invmon", eventSeq)
        inv.items.setItem(objId, item)
        local postLocation = item.stats and item.stats[invStatFieldLocation] or "unknown"
        local postContainer = item.stats and item.stats[invStatFieldContainer] or ""
        local postWorn = item.stats and item.stats[invStatFieldWorn] or ""
        dbot.debug(
            string.format(
                "Invmon result objId=%s location=%s container=%s worn=%s",
                tostring(objId),
                tostring(postLocation),
                tostring(postContainer),
                tostring(postWorn)
            ),
            "invmon"
        )
    end

    if forceImmediateSave and not inv.items.buildInProgress
        and not inv.items.refreshInProgress and not inv.items.identifyInProgress then
        inv.items.save()
    elseif shouldSave or actionNum ~= invmonActionConsumed then
        inv.items.scheduleSaveFromInvmon()
    end

    if inv.operations and inv.operations.observe then
        inv.operations.observe(actionNum, objId, containerId, wearLoc)
    end

    if DINV and DINV.api and DINV.api._onInventoryAction then
        pcall(DINV.api._onInventoryAction, objId, actionName, {
            previousLocation = preLocation,
            previousContainer = preContainer,
            existedBefore = item ~= nil or preLocation ~= "unknown",
            containerId = containerId,
            wearLocation = wearLoc,
        })
    end

    if DINV and DINV.debug and DINV.debug.recordWearTimingInvmon then
        DINV.debug.recordWearTimingInvmon(
            objId, actionNum, wearInvmonTimingWall, wearInvmonTimingCpu
        )
    end

    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Trigger-Compatible Handlers
----------------------------------------------------------------------------------------------------

inv.items.trigger = {}

function inv.items.trigger.invmon(action, objId, containerId, wearLoc)
    dbot.debug("@Gtrigger.invmon CALLED: action=" .. tostring(action) ..
               " objId=" .. tostring(objId) ..
               " containerId=" .. tostring(containerId) ..
               " wearLoc=" .. tostring(wearLoc) .. "@W", "inv.items")

    local actionStr = tostring(action or "")
    local objIdStr = tostring(objId or "")
    local containerIdStr = tostring(containerId or "")
    local wearLocStr = tostring(wearLoc or "")

    if actionStr == ""
        or objIdStr == ""
        or containerIdStr == ""
        or wearLocStr == ""
        or not actionStr:match("^%d+$")
        or not objIdStr:match("^[0-9%-]+$")
        or not containerIdStr:match("^[0-9%-]+$")
        or not wearLocStr:match("^[0-9%-]+$") then
        dbot.debug("@Ytrigger.invmon ignored malformed payload fields@W", "inv.items")
        return DRL_RET_INVALID_PARAM
    end

    local payload = table.concat({
        actionStr,
        objIdStr,
        containerIdStr,
        wearLocStr
    }, ",")

    dbot.debug("@Gtrigger.invmon payload: " .. payload .. "@W", "inv.items")

    if inv.items.onInvmon then
        return inv.items.onInvmon(payload)
    else
        dbot.debug("@Rinv.items.onInvmon does not exist!@W", "inv.items")
        return DRL_RET_INTERNAL_ERROR
    end
end

function inv.items.trigger.invitem(objId, flags, itemName, level, typeField, unique, wearLoc, timer)
    local payload = table.concat({
        objId or "",
        flags or "",
        itemName or "",
        level or "",
        typeField or "",
        unique or "",
        wearLoc or "",
        timer or ""
    }, ",")
    return inv.items.onInvitem(payload)
end

function inv.items.trigger.itemDataStats(objId, flags, itemName, level, typeField, unique, wearLoc, timer)
    local payload = table.concat({
        objId or "",
        flags or "",
        itemName or "",
        level or "",
        typeField or "",
        unique or "",
        wearLoc or "",
        timer or ""
    }, ",")
    return inv.items._parseDataLine(payload, "invdata")
end

function inv.items.trigger.itemDataEnd()
    return DRL_RET_SUCCESS
end

function inv.items.trigger.identify(line)
    return inv.items.onIdentify(line)
end

function inv.items.getStatField(objId, field)
    local item = inv.items.getItem(objId)
    if item and item.stats and item.stats[field] ~= nil then
        return item.stats[field]
    end
    if item then
        return item[field]
    end
    return nil
end

function inv.items.getField(objId, field)
    local item = inv.items.getItem(objId)
    if item then
        return item[field]
    end
    return nil
end

function inv.items.setStatField(objId, field, value)
    local item = inv.items.getItem(objId)
    if item == nil then
        item = { stats = {} }
        inv.items.setItem(objId, item)
    end
    if item.stats == nil then
        item.stats = {}
    end
    item.stats[field] = value
    inv.items.setItem(objId, item)
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Item Counting
----------------------------------------------------------------------------------------------------

function inv.items.getCount()
    local count = 0
    if inv.items.table then
        for _ in pairs(inv.items.table) do
            count = count + 1
        end
    end
    return count
end

function inv.items.getCountByType(itemType)
    local count = 0
    if inv.items.table then
        for objId, item in pairs(inv.items.table) do
            local iType = inv.items.getStatField(objId, invStatFieldType)
            if iType == itemType then
                count = count + 1
            end
        end
    end
    return count
end

----------------------------------------------------------------------------------------------------
-- Wearable Helpers
----------------------------------------------------------------------------------------------------

function inv.items.isWearableLoc(wearableLoc)
    if wearableLoc == nil or wearableLoc == "" then
        return false
    end
    return inv.wearLocNames and inv.wearLocNames[wearableLoc] == true
end

-- Returns true when the item's `worn` stat is a real slot (not the not-worn sentinel).
function inv.items.isWorn(objId)
    local worn = inv.items.getStatField and inv.items.getStatField(objId, invStatFieldWorn)
    if worn == nil or worn == "" or worn == invItemWornNotWorn or worn == "undefined" then
        return false
    end
    return true
end

function inv.items.isWearableType(wearableType)
    if wearableType == nil or wearableType == "" then
        return false
    end
    return inv.wearables and inv.wearables[wearableType] ~= nil
end

function inv.items.wearableTypeToLocs(wearableType)
    if not inv.items.isWearableType(wearableType) then
        return ""
    end
    return table.concat(inv.wearables[wearableType], " ")
end

----------------------------------------------------------------------------------------------------
-- Search Functions
----------------------------------------------------------------------------------------------------

function inv.items.hasSearchFlag(objId, value)
    local normalized = tostring(value or ""):lower()
    if normalized == "kept" then
        return inv.items.getStatField(objId, invStatFieldKeepflag) == true
    end

    local flagsStr = inv.items.getStatField(objId, invStatFieldFlags) or ""
    for flag in tostring(flagsStr):gmatch("%S+") do
        flag = flag:gsub(",", "")
        if string.find(string.lower(flag), normalized, 1, true) ~= nil then
            return true
        end
    end
    return false
end

function inv.items.matchesParsedQuery(objId, clauses)
    local item = inv.items.getItem(objId)
    if not item then
        return false
    end

    local itemName = inv.items.getStatField(objId, invStatFieldName) or ""
    local itemType = inv.items.getStatField(objId, invStatFieldType) or ""
    local level = tonumber(inv.items.getStatField(objId, invStatFieldLevel)) or 0
    local wearable = inv.items.getStatField(objId, invStatFieldWearable) or ""
    local container = inv.items.getStatField(objId, invStatFieldContainer) or ""

    for _, criteria in ipairs(clauses or {}) do
        local matchedAll = true

        for _, entry in ipairs(criteria) do
            local key = tostring(entry.key or ""):lower()
            local value = entry.value
            local negated = entry.negated
            local match = false

            if key == "type" then
                match = string.lower(itemType) == string.lower(value)
            elseif key == "name" then
                local relativeIndex, relativeName = inv.items.convertRelative(value)
                local target = relativeIndex and relativeName or value
                match = string.find(string.lower(itemName), string.lower(target), 1, true) ~= nil
            elseif key == "wearable" then
                match = string.find(string.lower(wearable), string.lower(value), 1, true) ~= nil
            elseif key == "keyword" or key == "keywords" then
                local keywordsStr = inv.items.getStatField(objId, invStatFieldKeywords) or ""
                for word in tostring(keywordsStr):gmatch("%S+") do
                    word = word:gsub(",", "")
                    if string.find(string.lower(word), string.lower(value), 1, true) ~= nil then
                        match = true
                        break
                    end
                end
            elseif key == invStatFieldLeadsTo then
                local leadsTo = inv.items.getStatField(objId, invStatFieldLeadsTo) or ""
                match = string.find(string.lower(leadsTo), string.lower(value), 1, true) ~= nil
            elseif key == invStatFieldMaterial then
                local material = inv.items.getStatField(objId, invStatFieldMaterial) or ""
                match = string.find(string.lower(material), string.lower(value), 1, true) ~= nil
            elseif key == "flag" or key == "flags" then
                match = inv.items.hasSearchFlag(objId, value)
            elseif key == "id" then
                match = tostring(objId) == tostring(value)
            elseif key == "container" then
                match = tostring(container) == tostring(value)
            elseif key == "location" or key == "loc" then
                local location = inv.items.getStatField(objId, invStatFieldLocation) or ""
                match = string.find(string.lower(tostring(location)), string.lower(tostring(value)), 1, true) ~= nil
            elseif key == "rname" then
                local _, relVal = inv.items.convertRelative(value)
                local target = relVal or value
                match = string.find(string.lower(itemName), string.lower(tostring(target)), 1, true) ~= nil
            elseif key == "rlocation" or key == "rloc" then
                local _, relVal = inv.items.convertRelative(value)
                local target = relVal or value
                local location = inv.items.getStatField(objId, invStatFieldLocation) or ""
                match = string.find(string.lower(tostring(location)), string.lower(tostring(target)), 1, true) ~= nil
            elseif key == "worn" then
                match = inv.items.isWorn(objId)
            elseif key == "minlevel" then
                local minLevel = tonumber(value)
                match = minLevel ~= nil and level >= minLevel
            elseif key == "maxlevel" then
                local maxLevel = tonumber(value)
                match = maxLevel ~= nil and level <= maxLevel
            elseif key == "level" then
                local exactLevel = tonumber(value)
                match = exactLevel ~= nil and level == exactLevel
            elseif inv.items.isKnownQueryKey(key) then
                local statValue = inv.items.getStatField(objId, key)
                local lhs = tostring(statValue or ""):lower()
                local rhs = tostring(value or ""):lower()
                local lhsNum = tonumber(lhs)
                local rhsNum = tonumber(rhs)
                if lhsNum ~= nil and rhsNum ~= nil then
                    match = (lhsNum == rhsNum)
                else
                    match = string.find(lhs, rhs, 1, true) ~= nil
                end
            end

            if negated then
                match = not match
            end
            if not match then
                matchedAll = false
                break
            end
        end

        if matchedAll then
            return true
        end
    end

    return false
end

function inv.items.matchesQuery(objId, query)
    return inv.items.matchesParsedQuery(objId, inv.items.parseQuery(query or ""))
end

function inv.items.search(query, displayMode, options)
    displayMode = displayMode or "basic"
    options = options or {}

    if inv.items.table == nil or dbot.table.getNumEntries(inv.items.table) == 0 then
        dbot.info("Your inventory table is empty. Run '@Gdinv build confirm@W' to populate it.")
        return {}, DRL_RET_SUCCESS
    end

    local clauses = inv.items.parseQuery(query or "")
    local results = nil
    if DINV and DINV.database and DINV.database.searchParsed then
        local searchError
        results, searchError = DINV.database.searchParsed(
            clauses,
            inv.items.databaseBuildId and "build" or "active"
        )
        if not results then
            dbot.warn("SQLite search failed: " .. tostring(searchError))
            return {}, DRL_RET_INTERNAL_ERROR
        end
    else
        results = {}
        for objId, _ in pairs(inv.items.table) do
            if inv.items.matchesParsedQuery(objId, clauses) then
                table.insert(results, tostring(objId))
            end
        end
    end

    if not options.includeIgnored then
        local visible = {}
        for _, objId in ipairs(results) do
            local container = inv.items.getStatField(objId, invStatFieldContainer) or ""
            if container == "" or not inv.config.isIgnored(container) then
                table.insert(visible, objId)
            end
        end
        results = visible
    end

    -- Handle relative matches like "3.sword" by applying ordinal filtering.
    local relIndex, relName = inv.items.convertRelative(query or "")
    if relIndex and relName then
        local filtered = {}
        local count = 0
        for _, objId in ipairs(results) do
            local itemName = inv.items.getStatField(objId, invStatFieldName) or ""
            if string.find(string.lower(itemName), string.lower(relName), 1, true) then
                count = count + 1
                if count == relIndex then
                    table.insert(filtered, objId)
                    break
                end
            end
        end
        results = filtered
    end

    local clausesLower = tostring(query or ""):lower()
    local rnameValue = clausesLower:match("rname%s+(%S+)")
    if rnameValue then
        local idx, namePart = inv.items.convertRelative(rnameValue)
        if idx and namePart then
            local filtered = {}
            local count = 0
            for _, objId in ipairs(results) do
                local itemName = inv.items.getStatField(objId, invStatFieldName) or ""
                if string.find(string.lower(itemName), string.lower(namePart), 1, true) then
                    count = count + 1
                    if count == idx then
                        table.insert(filtered, objId)
                        break
                    end
                end
            end
            results = filtered
        end
    end

    return results, DRL_RET_SUCCESS
end

local function compareStatSearchNumbers(left, operator, right)
    if operator == ">=" then
        return left >= right
    elseif operator == "<=" then
        return left <= right
    elseif operator == ">" then
        return left > right
    elseif operator == "<" then
        return left < right
    elseif operator == "=" then
        return left == right
    end
    return false
end

local function statSearchEnchantComponents(rawValue, selector)
    local matches = {}
    local normalizedSelector = trimStatSearchText(selector):lower()
    for component in tostring(rawValue or ""):gmatch("[^,]+") do
        local trimmedComponent = trimStatSearchText(component)
        if normalizedSelector == ""
            or trimmedComponent:lower():find(normalizedSelector, 1, true) then
            table.insert(matches, trimmedComponent)
        end
    end
    return matches
end

local function statSearchComponentNumber(component)
    local text = tostring(component or "")
    local value = text:match("([%+%-]?%d+%.?%d*)")
    if value == nil then
        value = text:match("([%+%-]?%d*%.%d+)")
    end
    return parseStatSearchNumber(value)
end

local function statSearchPredicateMatches(objId, predicate)
    local rawValue = inv.items.getStatField(objId, predicate.field)
    if rawValue == nil then
        return false
    end

    if predicate.kind == "numeric" then
        local number = tonumber(rawValue)
        if number == nil then
            return false
        end
        if predicate.comparison then
            return compareStatSearchNumbers(
                number,
                predicate.comparison.operator,
                predicate.comparison.number
            )
        end
        return number ~= 0
    end

    local text = trimStatSearchText(rawValue)
    if text == "" then
        return false
    end

    local components = statSearchEnchantComponents(text, predicate.selector)
    if #components == 0 then
        return false
    end
    if not predicate.comparison then
        return true
    end

    for _, component in ipairs(components) do
        local number = statSearchComponentNumber(component)
        if number ~= nil and compareStatSearchNumbers(
            number,
            predicate.comparison.operator,
            predicate.comparison.number
        ) then
            return true
        end
    end
    return false
end

function inv.items.matchesStatSearch(objId, spec)
    for _, clause in ipairs((spec and spec.clauses) or {}) do
        local matchedAll = true
        for _, predicate in ipairs(clause) do
            if not statSearchPredicateMatches(objId, predicate) then
                matchedAll = false
                break
            end
        end
        if matchedAll then
            return true
        end
    end
    return false
end

function inv.items.searchStats(spec, options)
    local candidates, retval = inv.items.search("", nil, options)
    if retval ~= DRL_RET_SUCCESS then
        return {}, retval
    end

    local results = {}
    for _, objId in ipairs(candidates or {}) do
        if inv.items.matchesStatSearch(objId, spec) then
            table.insert(results, tostring(objId))
        end
    end
    return results, DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Sort Functions
----------------------------------------------------------------------------------------------------

function inv.items.sort(itemIds, sortCriteria)
    if itemIds == nil or #itemIds == 0 then
        return
    end
    
    sortCriteria = sortCriteria or {
        { field = invStatFieldLevel, isAscending = true },
        { field = invStatFieldType, isAscending = true },
        { field = invStatFieldName, isAscending = true }
    }
    
    table.sort(itemIds, function(id1, id2)
        for _, criteria in ipairs(sortCriteria) do
            local val1 = inv.items.getStatField(id1, criteria.field) or ""
            local val2 = inv.items.getStatField(id2, criteria.field) or ""
            
            -- Convert to numbers if both are numeric
            local num1, num2 = tonumber(val1), tonumber(val2)
            if num1 and num2 then
                val1, val2 = num1, num2
            else
                val1, val2 = tostring(val1), tostring(val2)
            end
            
            if val1 ~= val2 then
                if criteria.isAscending then
                    return val1 < val2
                else
                    return val1 > val2
                end
            end
        end
        local numericId1, numericId2 = tonumber(id1), tonumber(id2)
        if numericId1 and numericId2 and numericId1 ~= numericId2 then
            return numericId1 < numericId2
        end
        return tostring(id1) < tostring(id2)
    end)
end

local function statSearchSortValue(objId, predicate)
    if not predicate then
        return nil, nil
    end

    local rawValue = inv.items.getStatField(objId, predicate.field)
    if rawValue == nil or trimStatSearchText(rawValue) == "" then
        return nil, nil
    end

    if predicate.kind == "numeric" then
        local number = tonumber(rawValue)
        return number ~= nil and "number" or nil, number
    end

    local components = statSearchEnchantComponents(rawValue, predicate.selector)
    if #components == 0 then
        return nil, nil
    end
    local number = statSearchComponentNumber(components[1])
    if number ~= nil then
        return "number", number
    end
    return "text", components[1]:lower()
end

function inv.items.sortStatSearchResults(itemIds, spec)
    if itemIds == nil or #itemIds == 0 then
        return
    end

    table.sort(itemIds, function(leftId, rightId)
        local leftKind, leftValue = statSearchSortValue(leftId, spec and spec.primary)
        local rightKind, rightValue = statSearchSortValue(rightId, spec and spec.primary)

        if leftKind == nil and rightKind ~= nil then
            return false
        elseif leftKind ~= nil and rightKind == nil then
            return true
        elseif leftKind ~= nil and rightKind ~= nil then
            if leftKind ~= rightKind then
                return leftKind == "number"
            elseif leftValue ~= rightValue then
                if leftKind == "number" then
                    return leftValue > rightValue
                end
                return leftValue < rightValue
            end
        end

        local leftName = tostring(inv.items.getStatField(leftId, invStatFieldName) or ""):lower()
        local rightName = tostring(inv.items.getStatField(rightId, invStatFieldName) or ""):lower()
        if leftName ~= rightName then
            return leftName < rightName
        end

        local leftNumber = tonumber(leftId)
        local rightNumber = tonumber(rightId)
        if leftNumber and rightNumber and leftNumber ~= rightNumber then
            return leftNumber < rightNumber
        end
        return tostring(leftId) < tostring(rightId)
    end)
end

----------------------------------------------------------------------------------------------------
-- Display Functions
----------------------------------------------------------------------------------------------------

function inv.items.displayItem(objId, displayMode, options)
    displayMode = displayMode or "basic"

    local item = inv.items.getItem(objId)
    if item == nil then
        return DRL_RET_MISSING_ENTRY
    end

    -- Use 11-character width for ID as string (handles large IDs safely)
    local formattedId = string.format("%11s", tostring(objId))

    local function isItemWornForDisplay()
        local worn = tostring(inv.items.getStatField(objId, invStatFieldWorn) or "")

        if worn == "" or worn == "undefined" or worn == invItemWornNotWorn then
            return false
        end

        return true
    end

    local idColorCode = isItemWornForDisplay() and "@G" or "@Y"
    local idMudletColor = isItemWornForDisplay() and "<green>" or "<yellow>"
    local includeId = displayMode ~= "basic"
    local includeExtendedStats = displayMode ~= "basic"

    local function printLine(msg)
        local raw = tostring(msg or "")
        if cechoLink then
            local idPrefix = idColorCode .. formattedId .. "@W "
            if raw:sub(1, #idPrefix) == idPrefix then
                local location = tostring(inv.items.getStatField(objId, invStatFieldLocation) or "")
                local remainder = raw:sub(#idPrefix + 1)
                local auctionLabelPrefix = "Auction #" .. tostring(objId)
                if location == "auction" and remainder:sub(1, #auctionLabelPrefix) == auctionLabelPrefix then
                    local linkCommand = string.format("send([[lbid %s]])", tostring(objId))
                    local tooltip = "Run: lbid " .. tostring(objId)
                    cechoLink(idMudletColor .. formattedId .. "<reset>", linkCommand, tooltip, true)
                elseif location ~= "auction" then
                    local linkCommand = string.format("inv.items.runReportFromLink(%q)", tostring(objId))
                    local tooltip = "Run: dinv report " .. tostring(objId)
                    cechoLink(idMudletColor .. formattedId .. "<reset>", linkCommand, tooltip, true)
                else
                    cecho(idMudletColor .. formattedId .. "<reset>")
                end
                cecho(" " .. dbot.convertColors(remainder) .. "\n")
                return
            end
        end

        local text = dbot.convertColors(raw)
        cecho(text .. "\n")
    end

    -- Get all stats with safe defaults
    local rawName = inv.items.getStatField(objId, invStatFieldColorName)
        or inv.items.getStatField(objId, invStatFieldName)
        or "Unknown"
    local level = tonumber(inv.items.getStatField(objId, invStatFieldLevel)) or 0
    local itemType = inv.items.getStatField(objId, invStatFieldType) or "Unknown"
    local score = tonumber(inv.items.getStatField(objId, invStatFieldScore)) or 0
    local hr = tonumber(inv.items.getStatField(objId, invStatFieldHitroll)) or 0
    local dr = tonumber(inv.items.getStatField(objId, invStatFieldDamroll)) or 0

    -- Print type header if changed
    if displayMode ~= "itemid" then
        if itemType ~= inv.items.displayLastType then
            inv.items.displayLastType = itemType
            cecho("\n" .. dbot.convertColors("@C--- " .. itemType .. " ---@w") .. "\n")
        end
    end

    -- Process name for display
    rawName = rawName:gsub("%s+[A-Z][a-z]+%s+%+?%-?%d+%s*%(removable[^%)]*%).*", "")
    local colorName = dbot.convertColors(rawName)
    local colorNameRaw = rawName

    if displayMode == "basic" or displayMode == "objid" or displayMode == "full" or displayMode == "itemid" then
        local statOrder = {
            { field = invStatFieldStr, label = "str" },
            { field = invStatFieldInt, label = "int" },
            { field = invStatFieldWis, label = "wis" },
            { field = invStatFieldDex, label = "dex" },
            { field = invStatFieldCon, label = "con" },
            { field = invStatFieldLuck, label = "luck" },
            { field = invStatFieldHp, label = "hp" },
            { field = invStatFieldMana, label = "mana" },
            { field = invStatFieldMoves, label = "moves" },
        }
        local stats = {}
        for _, stat in ipairs(statOrder) do
            local val = tonumber(inv.items.getStatField(objId, stat.field)) or 0
            if val ~= 0 then
                table.insert(stats, string.format("%s:%d", stat.label, val))
            end
        end

        dbot.debug(string.format(
            "itemid debug objId=%s stats=%s hr=%s dr=%s flags.stats=%s flags.item=%s",
            tostring(objId),
            #stats > 0 and table.concat(stats, " ") or "(none)",
            tostring(hr),
            tostring(dr),
            tostring(item.stats and item.stats[invStatFieldFlags] or ""),
            tostring(item[invStatFieldFlags] or "")
        ), "inv.items")

        local rolls = {}
        if hr ~= 0 then
            table.insert(rolls, string.format("HR:%d", hr))
        end
        if dr ~= 0 then
            table.insert(rolls, string.format("DR:%d", dr))
        end

        local flags = tostring(inv.items.getStatField(objId, invStatFieldFlags) or ""):lower()
        flags = flags:gsub("[\r\n]", " ")
        local hasResonated = "@R"
        local hasIlluminated = "@R"
        local hasSolidified = "@R"
        for flag in flags:gmatch("[^,%s]+") do
            if flag == "resonated" then
                hasResonated = "@G"
            elseif flag == "illuminated" then
                hasIlluminated = "@G"
            elseif flag == "solidified" then
                hasSolidified = "@G"
            end
        end
        dbot.debug(string.format(
            "itemid flags normalized=%s resonated=%s illuminated=%s solidified=%s",
            flags,
            tostring(hasResonated),
            tostring(hasIlluminated),
            tostring(hasSolidified)
        ), "inv.items")
        local enchantFlags = table.concat({
            hasResonated,
            "R@w",
            hasIlluminated,
            "I@w",
            hasSolidified,
            "S@w",
        }, "")

        local function buildStatBlock(entries)
            if #entries == 0 then
                return ""
            end
            return " [" .. table.concat(entries, " ") .. "]"
        end

        local wearableLoc = inv.items.getStatField(objId, invStatFieldWearable) or ""
        local wearText = wearableLoc ~= "" and (" [" .. wearableLoc .. "] ") or " "

        local baseStats = {}
        local statLabels = {
            { field = invStatFieldStr, label = "str" },
            { field = invStatFieldInt, label = "int" },
            { field = invStatFieldWis, label = "wis" },
            { field = invStatFieldDex, label = "dex" },
            { field = invStatFieldCon, label = "con" },
            { field = invStatFieldLuck, label = "luck" },
        }
        for _, stat in ipairs(statLabels) do
            local val = tonumber(inv.items.getStatField(objId, stat.field)) or 0
            table.insert(baseStats, string.format("%s%d@D%s@w", val < 0 and "@R" or "@G", val, stat.label))
        end

        local rollStats = {}
        table.insert(rollStats, string.format("%s%d@Dhr@w", hr < 0 and "@R" or "@G", hr))
        table.insert(rollStats, string.format("%s%d@Ddr@w", dr < 0 and "@R" or "@G", dr))

        local resourceStats = {}
        local hpVal = tonumber(inv.items.getStatField(objId, invStatFieldHp)) or 0
        local manaVal = tonumber(inv.items.getStatField(objId, invStatFieldMana)) or 0
        local movesVal = tonumber(inv.items.getStatField(objId, invStatFieldMoves)) or 0
        if hpVal ~= 0 then
            table.insert(resourceStats, string.format("%s%d@Dhp@w", hpVal < 0 and "@R" or "@G", hpVal))
        end
        if manaVal ~= 0 then
            table.insert(resourceStats, string.format("%s%d@Dmn@w", manaVal < 0 and "@R" or "@G", manaVal))
        end
        if movesVal ~= 0 then
            table.insert(resourceStats, string.format("%s%d@Dmv@w", movesVal < 0 and "@R" or "@G", movesVal))
        end

        local statText = buildStatBlock(baseStats)
        local rollText = buildStatBlock(rollStats)
        local resourceText = buildStatBlock(resourceStats)
        local risText = enchantFlags ~= "" and (" [" .. enchantFlags .. "]") or ""

        local weightVal = tonumber(inv.items.getStatField(objId, invStatFieldWeight)) or 0
        local weightText = " [" .. string.format("@G%d@Dwgt@w", weightVal) .. "]"

        local useRaw = options and options.useRawColors
        local channelFormat = options and options.channelFormat
        local nameText
        if channelFormat then
            nameText = useRaw and colorNameRaw or colorName
        else
            -- Search/list table output should preserve item color tags from colorname.
            nameText = colorNameRaw
        end
        local line

        if channelFormat then
            local levelText = string.format(" [@Wlv%s@w]", tostring(level))
            local wearBracket = wearableLoc ~= "" and (" [" .. wearableLoc .. "]") or ""
            local weaponType = ""
            local weaponDam = ""
            local weaponDamType = ""
            if tostring(itemType):lower() == "weapon" then
                local wType = inv.items.getStatField(objId, invStatFieldWeaponType) or ""
                if wType ~= "" then
                    weaponType = " [" .. wType .. "]"
                end
                local aveDam = tonumber(inv.items.getStatField(objId, invStatFieldAveDam)) or 0
                if aveDam ~= 0 then
                    weaponDam = " [" .. string.format("@G%d@Ddam@w", aveDam) .. "]"
                end
                local damType = inv.items.getStatField(objId, invStatFieldDamtype) or ""
                if damType ~= "" then
                    weaponDamType = " [" .. damType .. "]"
                end
            end
            local weightBracket = ""
            if weightText ~= "" then
                weightBracket = weightText
            end
            local scoreBracket = " [@C" .. tostring(score) .. "@W Score@w]"
            local hrDrBracket = rollText ~= "" and rollText or ""
            local hpMvMn = buildStatBlock(resourceStats)
            local risChannel = ""
            if enchantFlags ~= "" then
                local risOrder = table.concat({
                    hasIlluminated, "I@w",
                    hasResonated, "R@w",
                    hasSolidified, "S@w",
                }, "")
                risChannel = " [" .. risOrder .. "]"
            end
            line = table.concat({
                "@w", nameText,
                levelText,
                wearBracket,
                weaponType,
                weaponDam,
                weaponDamType,
                weightBracket,
                scoreBracket,
                statText,
                hrDrBracket,
                hpMvMn,
                risChannel
            }, "")
        else
            local function padColored(value, width)
                local raw = tostring(value or "")
                local plain = dbot.stripColors(raw)
                local pad = math.max(0, (width or 0) - #plain)
                return raw .. string.rep(" ", pad)
            end

            local function wrapColoredText(value, width)
                local raw = tostring(value or "")
                local limit = tonumber(width) or 0
                if limit <= 0 then
                    return { raw }
                end

                local function nextToken(text, idx)
                    local c = text:sub(idx, idx)
                    if c ~= "@" then
                        return c, 1, false
                    end

                    local xcode = text:match("^@x%d+", idx)
                    if xcode then
                        return xcode, #xcode, true
                    end

                    if idx < #text then
                        local code = text:sub(idx, idx + 1)
                        return code, 2, true
                    end

                    return "@", 1, false
                end

                local out = {}
                local line = ""
                local visible = 0
                local idx = 1
                local activeColor = "@w"

                while idx <= #raw do
                    local token, tokenLen, isCode = nextToken(raw, idx)
                    idx = idx + tokenLen

                    if isCode then
                        line = line .. token
                        activeColor = token
                    else
                        line = line .. token
                        visible = visible + 1
                        if visible >= limit and idx <= #raw then
                            table.insert(out, line)
                            line = activeColor
                            visible = 0
                        end
                    end
                end

                if line ~= "" then
                    table.insert(out, line)
                end
                if #out == 0 then
                    table.insert(out, "")
                end
                return out
            end

            local function truncateColoredText(value, width)
                local raw = tostring(value or "")
                local limit = tonumber(width) or 0
                if limit <= 0 or #dbot.stripColors(raw) <= limit then
                    return raw
                end

                local suffix = "..."
                if limit <= #suffix then
                    return suffix:sub(1, limit)
                end

                local keep = limit - #suffix
                local out = {}
                local visible = 0
                local idx = 1

                while idx <= #raw and visible < keep do
                    local c = raw:sub(idx, idx)
                    if c == "@" then
                        local escapedAt = raw:sub(idx, idx + 1) == "@@"
                        local xcode = raw:match("^@x%d+", idx)
                        if escapedAt then
                            table.insert(out, "@@")
                            idx = idx + 2
                            visible = visible + 1
                        elseif xcode then
                            table.insert(out, xcode)
                            idx = idx + #xcode
                        elseif idx < #raw then
                            table.insert(out, raw:sub(idx, idx + 1))
                            idx = idx + 2
                        else
                            table.insert(out, c)
                            idx = idx + 1
                            visible = visible + 1
                        end
                    else
                        table.insert(out, c)
                        idx = idx + 1
                        visible = visible + 1
                    end
                end

                return table.concat(out, "") .. suffix .. "@w"
            end

            local isWeapon = tostring(itemType):lower() == "weapon"
            local weaponType = ""
            local weaponDam = ""
            if isWeapon then
                local wType = inv.items.getStatField(objId, invStatFieldWeaponType) or ""
                if wType ~= "" then
                    weaponType = string.lower(wType)
                else
                    weaponType = "-"
                end
                local aveDam = tonumber(inv.items.getStatField(objId, invStatFieldAveDam)) or 0
                if aveDam ~= 0 then
                    weaponDam = string.format("@G%d@Ddam@w", aveDam)
                else
                    weaponDam = "-"
                end
            end

            local widths = (options and options.columnWidths) or {}
            local nameWidth = widths.name or 40
            local levelWidth = widths.level or 5
            local wearLocWidth = widths.wearLoc or 8
            local weaponTypeWidth = widths.weaponType or 6
            local weaponDamWidth = widths.weaponDam or 7
            local statWidth = widths.stat or 5
            local rollWidth = widths.roll or 5
            local resourceWidth = widths.resource or 5
            local risWidth = widths.ris or 3
            local cellPad = widths.cellPad or 1
            local sep = string.rep(" ", cellPad)

            local function formatValueCell(value, suffix)
                local num = tonumber(value) or 0
                if num == 0 then
                    return string.format("@D%d%s@w", num, suffix)
                end
                local valueColor = num < 0 and "@R" or "@G"
                return string.format("%s%d@D%s@w", valueColor, num, suffix)
            end

            local levelText = string.format("@Wlv@G%d@w", level)
            local strText = formatValueCell(inv.items.getStatField(objId, invStatFieldStr), "str")
            local intText = formatValueCell(inv.items.getStatField(objId, invStatFieldInt), "int")
            local wisText = formatValueCell(inv.items.getStatField(objId, invStatFieldWis), "wis")
            local dexText = formatValueCell(inv.items.getStatField(objId, invStatFieldDex), "dex")
            local conText = formatValueCell(inv.items.getStatField(objId, invStatFieldCon), "con")
            local lucText = formatValueCell(inv.items.getStatField(objId, invStatFieldLuck), "luc")
            local hrText = formatValueCell(hr, "hr")
            local drText = formatValueCell(dr, "dr")
            local hpText = formatValueCell(hpVal, "hp")
            local mnText = formatValueCell(manaVal, "mn")
            local mvText = formatValueCell(movesVal, "mv")
            local risText = table.concat({ hasIlluminated, "I", hasResonated, "R", hasSolidified, "S@w" }, "")

            local weaponTypeCell = isWeapon and ("@M" .. weaponType .. "@w") or ""
            local weaponDamCell = isWeapon and weaponDam or ""
            local includeWearLoc = options and options.includeWearLoc
            local wearLocCell = includeWearLoc and ((wearableLoc ~= "" and wearableLoc) or "-") or ""
            local effectiveNameWidth = nameWidth
            if not isWeapon then
                effectiveNameWidth = nameWidth + weaponTypeWidth + weaponDamWidth + (cellPad * 2)
            end

            local wrappedNameLines
            if options and options.truncateName then
                wrappedNameLines = { truncateColoredText(nameText, effectiveNameWidth) }
            else
                wrappedNameLines = wrapColoredText(nameText, effectiveNameWidth)
            end

            local cells = {}
            if includeId then
                table.insert(cells, idColorCode)
                table.insert(cells, formattedId)
                table.insert(cells, "@W ")
            end
            table.insert(cells, padColored(wrappedNameLines[1] or "", effectiveNameWidth))
            table.insert(cells, sep)
            table.insert(cells, padColored(levelText, levelWidth))
            table.insert(cells, sep)

            if includeWearLoc then
                table.insert(cells, padColored("@C" .. wearLocCell .. "@w", wearLocWidth))
                table.insert(cells, sep)
            end

            if isWeapon then
                table.insert(cells, padColored(weaponTypeCell, weaponTypeWidth))
                table.insert(cells, sep)
                table.insert(cells, padColored(weaponDamCell, weaponDamWidth))
                table.insert(cells, sep)
            end

            table.insert(cells, padColored(strText, statWidth))
            table.insert(cells, sep)
            table.insert(cells, padColored(intText, statWidth))
            table.insert(cells, sep)
            table.insert(cells, padColored(wisText, statWidth))
            table.insert(cells, sep)
            table.insert(cells, padColored(dexText, statWidth))
            table.insert(cells, sep)
            table.insert(cells, padColored(conText, statWidth))
            table.insert(cells, sep)
            table.insert(cells, padColored(lucText, statWidth))
            table.insert(cells, sep)
            table.insert(cells, padColored(hrText, rollWidth))
            table.insert(cells, sep)
            table.insert(cells, padColored(drText, rollWidth))
            table.insert(cells, sep)
            if includeExtendedStats then
                table.insert(cells, padColored(hpText, resourceWidth))
                table.insert(cells, sep)
                table.insert(cells, padColored(mnText, resourceWidth))
                table.insert(cells, sep)
                table.insert(cells, padColored(mvText, resourceWidth))
                table.insert(cells, sep)
                table.insert(cells, padColored(risText, risWidth))
            end

            local firstLine = table.concat(cells, "")
            if #wrappedNameLines > 1 then
                local continuationLines = {}
                for i = 2, #wrappedNameLines do
                    local continuation = {}
                    if includeId then
                        table.insert(continuation, idColorCode)
                        table.insert(continuation, string.rep(" ", #formattedId))
                        table.insert(continuation, "@W ")
                    end
                    table.insert(continuation, padColored(wrappedNameLines[i], effectiveNameWidth))
                    table.insert(continuationLines, table.concat(continuation, ""))
                end
                line = firstLine .. "\n" .. table.concat(continuationLines, "\n")
            else
                line = firstLine
            end
        end
        if not (options and options.suppress) then
            printLine(line)
            if displayMode == "full" then
                local stats = {}
                for k, v in pairs(item.stats or {}) do
                    table.insert(stats, { key = tostring(k), value = tostring(v) })
                end
                table.sort(stats, function(a, b)
                    return a.key < b.key
                end)

                local lineParts = {}
                local function flushParts()
                    if #lineParts > 0 then
                        printLine("    " .. table.concat(lineParts, " "))
                        lineParts = {}
                    end
                end

                for _, entry in ipairs(stats) do
                    local valueText = entry.value
                    if entry.key == invStatFieldColorName then
                        -- Keep literal @ color tags visible in full-mode stat dump.
                        valueText = tostring(valueText or ""):gsub("@", "@@")
                    end
                    table.insert(lineParts, string.format("@C%s@w:\"%s\"", entry.key, valueText))
                    if #lineParts >= 4 then
                        flushParts()
                    end
                end
                flushParts()
            end
        end
        return DRL_RET_SUCCESS, line
    end

    return DRL_RET_SUCCESS
end

function inv.items.displayResults(itemIds, displayMode, options)
    displayMode = displayMode or "basic"
    inv.items.displayLastType = ""
    
    if itemIds == nil or #itemIds == 0 then
        dbot.print("@WNo items found.@w")
        return DRL_RET_SUCCESS
    end
    
    local maxNameWidth = 24
    local maxWeaponTypeWidth = 6
    local maxWearLocWidth = 8
    local armorOnly = (#itemIds > 0)
    for _, objId in ipairs(itemIds) do
        local rawName = inv.items.getStatField(objId, invStatFieldColorName)
            or inv.items.getStatField(objId, invStatFieldName)
            or "Unknown"
        rawName = rawName:gsub("%s+[A-Z][a-z]+%s+%+?%-?%d+%s*%(removable[^%)]*%).*", "")
        local plainName = dbot.stripColors(rawName)
        if #plainName > maxNameWidth then
            maxNameWidth = #plainName
        end

        local itemType = tostring(inv.items.getStatField(objId, invStatFieldType) or "")
        if string.lower(itemType) ~= "armor" then
            armorOnly = false
        end

        local wearLoc = tostring(inv.items.getStatField(objId, invStatFieldWearable) or "")
        if #wearLoc > maxWearLocWidth then
            maxWearLocWidth = #wearLoc
        end

        if string.lower(itemType) == "weapon" then
            local wType = inv.items.getStatField(objId, invStatFieldWeaponType) or "-"
            wType = string.lower(tostring(wType))
            if #wType > maxWeaponTypeWidth then
                maxWeaponTypeWidth = #wType
            end
        end
    end
    maxNameWidth = math.min(maxNameWidth, 35)

    local displayOptions = {
        columnWidths = {
            name = maxNameWidth,
            level = 5,
            wearLoc = math.min(maxWearLocWidth, 12),
            weaponType = maxWeaponTypeWidth,
            weaponDam = 7,
            stat = 5,
            roll = 5,
            resource = 5,
            ris = 3,
            cellPad = 1,
        }
    }
    if options then
        for key, value in pairs(options) do
            displayOptions[key] = value
        end
    end
    displayOptions.includeWearLoc = armorOnly

    for _, objId in ipairs(itemIds) do
        inv.items.displayItem(objId, displayMode, displayOptions)
    end

    local countLine = dbot.convertColors(string.format("@Y%d@W item(s) found.", #itemIds))
    cecho(countLine .. "\n")

    return DRL_RET_SUCCESS
end

local function formatStatSearchDisplayValue(rawValue, kind)
    if rawValue == nil or trimStatSearchText(rawValue) == "" then
        return "@D-@w"
    end

    if kind == "numeric" then
        local number = tonumber(rawValue)
        if number == nil then
            return "@D-@w"
        end
        local text
        if number == math.floor(number) then
            text = string.format("%d", number)
        else
            text = tostring(number)
        end
        if number < 0 then
            return "@R" .. text .. "@w"
        elseif number > 0 then
            return "@G" .. text .. "@w"
        end
        return "@D" .. text .. "@w"
    end

    local text = dbot.stripColors(tostring(rawValue or ""))
    text = text:gsub("[\r\n]", " ")
    return "@W" .. text .. "@w"
end

local function truncateStatSearchColorName(value, width)
    local raw = tostring(value or "")
    local limit = tonumber(width) or 0
    if limit <= 0 or #dbot.stripColors(raw) <= limit then
        return raw
    end

    local suffix = "..."
    local keep = math.max(0, limit - #suffix)
    local out = {}
    local visible = 0
    local index = 1

    while index <= #raw and visible < keep do
        local character = raw:sub(index, index)
        if character == "@" then
            local escapedAt = raw:sub(index, index + 1) == "@@"
            local xcode = raw:match("^@x%d+", index)
            if escapedAt then
                table.insert(out, "@@")
                index = index + 2
                visible = visible + 1
            elseif xcode then
                table.insert(out, xcode)
                index = index + #xcode
            elseif index < #raw then
                table.insert(out, raw:sub(index, index + 1))
                index = index + 2
            else
                table.insert(out, character)
                index = index + 1
                visible = visible + 1
            end
        else
            table.insert(out, character)
            index = index + 1
            visible = visible + 1
        end
    end

    return table.concat(out, "") .. suffix .. "@w"
end

function inv.items.displayStatSearchResults(itemIds, spec)
    if itemIds == nil or #itemIds == 0 then
        dbot.print("@WNo items found.@w")
        return DRL_RET_SUCCESS
    end

    local nameWidth = 24
    local displayNames = {}
    for _, objId in ipairs(itemIds) do
        local rawName = tostring(inv.items.getStatField(objId, invStatFieldColorName)
            or inv.items.getStatField(objId, invStatFieldName)
            or "Unknown")
        rawName = rawName:gsub("[\r\n]", " ")
        rawName = rawName:gsub("%s+[A-Z][a-z]+%s+%+?%-?%d+%s*%(removable[^%)]*%).*", "")
        rawName = truncateStatSearchColorName(rawName, 40)
        local visibleWidth = #dbot.stripColors(rawName)
        displayNames[tostring(objId)] = {
            raw = rawName,
            width = visibleWidth,
        }
        nameWidth = math.max(nameWidth, visibleWidth)
    end

    cecho(dbot.convertColors(string.format(
        "@C%-11s %-" .. tostring(nameWidth) .. "s  Stat value(s)@w\n",
        "Object ID",
        "Item name"
    )))

    for _, objId in ipairs(itemIds) do
        local normalizedId = tostring(objId)
        local formattedId = string.format("%11s", normalizedId)
        local pairsText = {}
        for _, field in ipairs((spec and spec.fields) or {}) do
            local kind = inv.items.statSearchFieldKinds[field]
            local rawValue = inv.items.getStatField(normalizedId, field)
            table.insert(pairsText, "@C" .. tostring(field) .. "@w " ..
                formatStatSearchDisplayValue(rawValue, kind))
        end

        if cechoLink then
            local linkCommand = string.format("inv.items.runReportFromLink(%q)", normalizedId)
            local tooltip = "Run: dinv report " .. normalizedId
            cechoLink("<yellow>" .. formattedId .. "<reset>", linkCommand, tooltip, true)
        else
            cecho("<yellow>" .. formattedId .. "<reset>")
        end
        local displayName = displayNames[normalizedId]
        local namePadding = string.rep(" ", math.max(0, nameWidth - displayName.width))
        local rowText = displayName.raw .. "@w" .. namePadding ..
            "  " .. table.concat(pairsText, " @D|@w ")
        cecho(" " .. dbot.convertColors(rowText) .. "\n")
    end

    cecho(dbot.convertColors(string.format("@Y%d@W item(s) found.@w\n", #itemIds)))
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Get/Put/Store Item Commands
----------------------------------------------------------------------------------------------------

function inv.items.get(query, endTag)
    local itemIds, retval = inv.items.search(query)
    if retval ~= DRL_RET_SUCCESS then
        return retval
    end
    
    if #itemIds == 0 then
        dbot.info("No items matching '" .. query .. "' found.")
        return DRL_RET_MISSING_ENTRY
    end
    
    for _, objId in ipairs(itemIds) do
        local container = inv.items.getStatField(objId, invStatFieldContainer)
        if container and container ~= "" then
            inv.items.sendActionCommand("get " .. objId .. " " .. container)
        else
            inv.items.sendActionCommand("get " .. objId)
        end
    end
    
    dbot.info("Retrieved " .. #itemIds .. " item(s)")
    return DRL_RET_SUCCESS
end

function inv.items.findContainerId(containerRef)
    if containerRef == nil or containerRef == "" then
        return nil
    end

    local numericId = tonumber(containerRef)
    if numericId then
        local objId = tostring(numericId)
        local itemType = inv.items.getStatField(objId, invStatFieldType) or ""
        if itemType == "Container" then
            return objId
        end
        dbot.warn("Object " .. tostring(containerRef) .. " is not a container (type: " .. tostring(itemType) .. ")")
        return nil
    end

    local relName = tostring(containerRef)
    if not relName:match("^%d+%.") then
        relName = "1." .. relName
    end

    local idArray, retval = inv.items.search("type container rname " .. relName)
    if retval == DRL_RET_SUCCESS and idArray and #idArray == 1 then
        return tostring(idArray[1])
    elseif idArray and #idArray > 1 then
        dbot.warn("Multiple containers match '" .. tostring(containerRef) .. "'. Use object ID or relative name.")
        return nil
    end

    idArray, retval = inv.items.search("type container name " .. tostring(containerRef))
    if retval == DRL_RET_SUCCESS and idArray and #idArray == 1 then
        return tostring(idArray[1])
    elseif idArray and #idArray > 1 then
        dbot.warn("Multiple containers match '" .. tostring(containerRef) .. "'. Use object ID or relative name.")
        return nil
    end

    dbot.warn("No container found matching '" .. tostring(containerRef) .. "'")
    return nil
end

function inv.items.put(containerName, query, endTag)
    local targetContainerId = inv.items.findContainerId(containerName)
    if targetContainerId == nil then
        return DRL_RET_MISSING_ENTRY
    end

    local itemIds, retval = inv.items.search(query)
    if retval ~= DRL_RET_SUCCESS then
        return retval
    end
    
    if #itemIds == 0 then
        dbot.info("No items matching '" .. query .. "' found.")
        return DRL_RET_MISSING_ENTRY
    end
    
    local moved = 0
    local skipped = 0
    for _, objId in ipairs(itemIds) do
        local currentLoc = inv.items.getStatField(objId, invStatFieldLocation) or ""
        local isWornLoc = inv.items.isWornLocation(objId, currentLoc)
        local containerLoc
        if isWornLoc then
            containerLoc = nil
        else
            containerLoc = inv.items.normalizeContainerId(currentLoc)
        end

        if containerLoc == targetContainerId then
            skipped = skipped + 1
        elseif containerLoc ~= nil and inv.config.isIgnored(containerLoc) then
            skipped = skipped + 1
        elseif currentLoc == "inventory" or currentLoc == "" then
            inv.items.sendActionCommand("put " .. objId .. " " .. targetContainerId)
            moved = moved + 1
        elseif containerLoc ~= nil then
            inv.items.sendActionCommand("get " .. objId .. " " .. containerLoc)
            inv.items.sendActionCommand("put " .. objId .. " " .. targetContainerId)
            moved = moved + 1
        elseif isWornLoc then
            inv.items.sendActionCommand("remove " .. objId)
            inv.items.sendActionCommand("put " .. objId .. " " .. targetContainerId)
            moved = moved + 1
        else
            skipped = skipped + 1
        end
    end

    local targetLabel = tostring(containerName) .. " [id " .. tostring(targetContainerId) .. "]"
    dbot.info("Stored " .. moved .. " item(s) in " .. targetLabel .. ". Skipped " .. skipped .. " already in place, ignored-container, or unavailable item(s).")
    return DRL_RET_SUCCESS
end

function inv.items.store(query, endTag)
    local itemIds, retval = inv.items.search(query)
    if retval ~= DRL_RET_SUCCESS then
        return retval
    end

    if #itemIds == 0 then
        dbot.info("No items matching '" .. query .. "' found.")
        return DRL_RET_MISSING_ENTRY
    end

    if inv.organize and inv.organize.syncRulesFromConfig then
        inv.organize.syncRulesFromConfig({ warnMissing = false })
    end

    local function parseOrganizeTypeRules()
        local rulesByType = {}
        local duplicateTypes = {}

        for objId, _ in pairs(inv.items.table or {}) do
            local typeName = tostring(inv.items.getStatField(objId, invStatFieldType) or "")
            local typeNum = tonumber(inv.items.getStatField(objId, invStatFieldTypeNum)) or 0
            local isContainer = (typeName == "Container" or typeNum == 11)
            if isContainer then
                local organizeQuery = tostring(inv.items.getStatField(objId, invQueryKeyOrganize) or "")
                if organizeQuery ~= "" then
                    for clause in organizeQuery:gmatch("[^|]+") do
                        local trimmed = clause:match("^%s*(.-)%s*$")
                        local typeValue = trimmed and trimmed:match("type%s+(%S+)")
                        if typeValue and typeValue ~= "" then
                            local normalizedType = string.lower(typeValue)
                            local existing = rulesByType[normalizedType]
                            if existing == nil then
                                rulesByType[normalizedType] = tostring(objId)
                            elseif existing ~= tostring(objId) then
                                duplicateTypes[normalizedType] = true
                            end
                        end
                    end
                end
            end
        end

        return rulesByType, duplicateTypes
    end

    local targetContainerByType, duplicateTypes = parseOrganizeTypeRules()

    local movedByRule = 0
    local movedByFallback = 0
    local keptInInventory = 0
    local skippedInPlace = 0
    local skippedIgnored = 0

    for _, objId in ipairs(itemIds) do
        local itemType = string.lower(tostring(inv.items.getStatField(objId, invStatFieldType) or ""))
        local targetContainerId = targetContainerByType[itemType]
        local currentLoc = tostring(inv.items.getStatField(objId, invStatFieldLocation) or "")
        local isWornLoc = inv.items.isWornLocation(objId, currentLoc)
        local containerLoc
        if isWornLoc then
            containerLoc = nil
        else
            containerLoc = inv.items.normalizeContainerId(currentLoc)
        end

        if targetContainerId == nil then
            targetContainerId = inv.items.resolveStoreContainer(objId)
        end

        if targetContainerId == nil then
            if currentLoc ~= "" and currentLoc ~= invItemLocInventory then
                if containerLoc ~= nil then
                    inv.items.sendActionCommand("get " .. objId .. " " .. containerLoc)
                elseif isWornLoc then
                    inv.items.sendActionCommand("remove " .. objId)
                else
                    inv.items.sendActionCommand("get " .. objId .. " " .. currentLoc)
                end
            end
            keptInInventory = keptInInventory + 1
        else
            if containerLoc == targetContainerId then
                skippedInPlace = skippedInPlace + 1
            elseif containerLoc ~= nil and inv.config.isIgnored(containerLoc) then
                skippedIgnored = skippedIgnored + 1
            else
                if currentLoc ~= "" and currentLoc ~= invItemLocInventory then
                    if containerLoc ~= nil then
                        inv.items.sendActionCommand("get " .. objId .. " " .. containerLoc)
                    elseif isWornLoc then
                        inv.items.sendActionCommand("remove " .. objId)
                    else
                        inv.items.sendActionCommand("get " .. objId .. " " .. currentLoc)
                    end
                end

                inv.items.sendActionCommand("put " .. objId .. " " .. targetContainerId)
                if targetContainerByType[itemType] ~= nil then
                    movedByRule = movedByRule + 1
                else
                    movedByFallback = movedByFallback + 1
                end
            end
        end
    end

    for typeName, _ in pairs(duplicateTypes) do
        dbot.warn("Multiple organize containers define type '" .. tostring(typeName) .. "'. Using first match found.")
    end

    local movedTotal = movedByRule + movedByFallback
    local actionParts = {}

    if movedByRule > 0 then
        table.insert(actionParts, movedByRule .. " via organize rules")
    end
    if movedByFallback > 0 then
        table.insert(actionParts, movedByFallback .. " via lastStored/container fallback")
    end
    if keptInInventory > 0 then
        table.insert(actionParts, "Kept " .. keptInInventory .. " in inventory")
    end

    local skippedParts = {}
    if skippedInPlace > 0 then
        table.insert(skippedParts, skippedInPlace .. " already in place")
    end
    if skippedIgnored > 0 then
        table.insert(skippedParts, skippedIgnored .. " in ignored containers")
    end
    if #skippedParts > 0 then
        table.insert(actionParts, "Skipped " .. table.concat(skippedParts, " and "))
    end

    if #actionParts > 0 then
        dbot.info("Stored " .. movedTotal .. " item(s): " .. table.concat(actionParts, ". ") .. ".")
    else
        dbot.info("Stored " .. movedTotal .. " item(s).")
    end
    return DRL_RET_SUCCESS
end


----------------------------------------------------------------------------------------------------
-- Wear/Remove Item Commands
----------------------------------------------------------------------------------------------------

function inv.items.isActionCommand(command)
    if not command or command == "" then
        return false
    end
    local verb = tostring(command):match("^(%S+)")
    if not verb then
        return false
    end
    verb = verb:lower()
    return verb == "get" or verb == "wear" or verb == "put" or verb == "remove"
end

function inv.items.logActionCommand(command)
    if not inv.items.isActionCommand(command) then
        return
    end
    dbot.debug("Action command: " .. tostring(command), "inv.commands")
end

function inv.items.sendActionCommand(command)
    if not command or command == "" then
        return DRL_RET_INVALID_PARAM
    end
    if sendSilent then
        sendSilent(command)
    else
        send(command)
    end
    inv.items.logActionCommand(command)
    return DRL_RET_SUCCESS
end

function inv.items.sendActionCommands(commandArray)
    if not commandArray then
        return DRL_RET_INVALID_PARAM
    end
    for _, cmd in ipairs(commandArray) do
        inv.items.sendActionCommand(cmd)
    end
    return DRL_RET_SUCCESS
end

function inv.items.normalizeContainerId(containerId)
    if containerId == nil then
        return nil
    end
    local value = tostring(containerId)
    if value == "" or value == "0" then
        return nil
    end
    if not value:match("^%d+$") then
        return nil
    end
    -- Wear-slot ids (0-32) are never container ids.
    if inv.wearLoc and inv.wearLoc[tonumber(value)] ~= nil then
        return nil
    end
    return value
end

-- Returns the canonical wear-slot name for value, or nil if value is not a wear slot.
-- Accepts: numeric id ("24"), slot name ("wielded"), or invItemLocWorn ("worn").
function inv.items.resolveWearSlot(value)
    if value == nil then return nil end
    local s = tostring(value)
    if s == "" or s == invItemLocInventory or s == invItemLocKeyring then
        return nil
    end
    if s == invItemLocWorn then
        return invItemLocWorn
    end
    local n = tonumber(s)
    if n ~= nil then
        if inv.wearLoc and inv.wearLoc[n] ~= nil then
            return inv.wearLoc[n]
        end
        return nil
    end
    if inv.wearLocNames and inv.wearLocNames[s] then
        return s
    end
    return nil
end

function inv.items.isWearSlot(value)
    return inv.items.resolveWearSlot(value) ~= nil
end

function inv.items.isWornLocation(objId, locationValue)
    if inv.items.isWearSlot(locationValue) then
        return true
    end
    return inv.items.isWorn(objId)
end

function inv.items.wearItem(objId, wearLoc, commandArray)
    -- Add wear command to array or execute directly
    local itemName = inv.items.getStatField(objId, invStatFieldName) or "item"
    dbot.debug("Wearing: " .. itemName .. " (" .. tostring(objId) .. ")", "inv.items")
    local command = nil
    if wearLoc == "wielded" then
        command = "wield " .. objId
    elseif wearLoc == "second" then
        command = "wield " .. objId .. " second"
    elseif wearLoc == "hold" then
        command = "hold " .. objId
    elseif wearLoc and wearLoc ~= "" then
        command = "wear " .. objId .. " " .. wearLoc
    else
        command = "wear " .. objId
    end
    if commandArray then
        table.insert(commandArray, command)
    else
        inv.items.sendActionCommand(command)
    end
    return DRL_RET_SUCCESS
end

function inv.items.removeWornItem(objId, commandArray)
    -- Add remove command to array or execute directly
    if commandArray then
        table.insert(commandArray, "remove " .. objId)
    else
        inv.items.sendActionCommand("remove " .. objId)
    end
    return DRL_RET_SUCCESS
end

function inv.items.storeItem(objId, commandArray)
    local container = inv.items.resolveStoreContainer(objId)
    if inv.items.isWorn(objId) then
        if commandArray then
            table.insert(commandArray, "remove " .. objId)
        else
            inv.items.sendActionCommand("remove " .. objId)
        end
    end
    if container then
        if commandArray then
            table.insert(commandArray, "put " .. objId .. " " .. container)
        else
            inv.items.sendActionCommand("put " .. objId .. " " .. container)
        end
    end
    return DRL_RET_SUCCESS
end

function inv.items.resolveStoreContainer(objId, isUsableContainerFn)
    if objId == nil then
        return nil
    end

    local function isUsableContainer(containerId)
        local normalized = inv.items.normalizeContainerId(containerId)
        if not normalized then
            return nil
        end

        -- Ignored containers must never become automatic storage destinations,
        -- even when an item's stale lastStored/container field points at one.
        if inv.config and inv.config.isIgnored and inv.config.isIgnored(normalized) then
            return nil
        end

        if isUsableContainerFn then
            return isUsableContainerFn(normalized)
        end

        local containerItem = inv.items.table and inv.items.table[normalized]
        if not containerItem then
            return nil
        end

        local typeName = inv.items.getStatField(normalized, invStatFieldType) or ""
        local typeNum = tonumber(inv.items.getStatField(normalized, invStatFieldTypeNum)) or 0
        if typeName == "Container" or typeNum == 11 then
            return normalized
        end

        return nil
    end

    local usableContainer = isUsableContainer
    local lastStored = inv.items.getStatField(objId, invStatFieldLastStored)
    local normalizedLastStored = usableContainer(lastStored)
    if normalizedLastStored then
        return normalizedLastStored
    end

    local configuredContainer = inv.items.getStatField(objId, invStatFieldContainer)
    local normalizedConfigured = usableContainer(configuredContainer)
    if normalizedConfigured then
        return normalizedConfigured
    end

    return nil
end

function inv.items.getItemCommand(objId, commandArray)
    -- Get item from wherever it is
    if commandArray then
        table.insert(commandArray, "get " .. objId)
    else
        inv.items.sendActionCommand("get " .. objId)
    end
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Forget Item (remove from table)
----------------------------------------------------------------------------------------------------

function inv.items.forget(query, endTag)
    local itemIds, retval = inv.items.search(query)
    if retval ~= DRL_RET_SUCCESS then
        return retval
    end
    
    if #itemIds == 0 then
        dbot.info("No items matching '" .. query .. "' found.")
        return DRL_RET_MISSING_ENTRY
    end
    
    for _, objId in ipairs(itemIds) do
        local key = tostring(objId)
        local item = inv.items.getItem(key)
        inv.items.removeItemFromCache(key, item)
        inv.items.table[key] = nil
    end

    local saveRet = inv.items.save()
    if saveRet ~= DRL_RET_SUCCESS then
        dbot.warn("inv.items.forget: removed " .. #itemIds ..
                  " item(s) from memory, but failed to persist: " ..
                  dbot.retval.getString(saveRet))
        return saveRet
    end
    
    dbot.info("Forgot " .. #itemIds .. " item(s) from inventory table")
    return DRL_RET_SUCCESS
end

function inv.items.forgetByIds(itemIds)
    if itemIds == nil or #itemIds == 0 then
        return DRL_RET_MISSING_ENTRY
    end

    for _, objId in ipairs(itemIds) do
        local key = tostring(objId)
        local item = inv.items.getItem(key)
        inv.items.removeItemFromCache(key, item)
        inv.items.table[key] = nil
    end

    local saveRet = inv.items.save()
    if saveRet ~= DRL_RET_SUCCESS then
        dbot.warn("inv.items.forgetByIds: removed " .. #itemIds ..
                  " item(s) from memory, but failed to persist: " ..
                  dbot.retval.getString(saveRet))
        return saveRet
    end

    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- End of inv items module
----------------------------------------------------------------------------------------------------

dbot.debug("inv.items module loaded", "inv.items")

if DINV and DINV.debug and DINV.debug.registerModule then
    DINV.debug.registerModule("invmon", "Invmon message handling and location updates.")
end
