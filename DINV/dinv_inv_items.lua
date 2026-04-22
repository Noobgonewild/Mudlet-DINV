----------------------------------------------------------------------------------------------------
-- INV Items Module
-- Core inventory table management - build, refresh, search, display
----------------------------------------------------------------------------------------------------

-- Defensive initialization
inv = inv or {}
inv.items = inv.items or {}
inv.items.init = inv.items.init or {}
inv.items.table = inv.items.table or {}
inv.items.timer = inv.items.timer or { name = "drlInvItemsRefreshTimer" }
inv.items.stateName = inv.items.stateName or "inv-items.state"

----------------------------------------------------------------------------------------------------
-- Timer Configuration
----------------------------------------------------------------------------------------------------

inv.items.timer = inv.items.timer or {}
inv.items.timer.name = inv.items.timer.name or "drlInvItemsRefreshTimer"
inv.items.timer.invmonSaveName = inv.items.timer.invmonSaveName or "drlInvItemsInvmonSaveTimer"
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
if inv.items.progress.reportMode ~= "classic" and inv.items.progress.reportMode ~= "inline" then
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
        if configured == "classic" or configured == "inline" then
            inv.items.progress.reportMode = configured
            return configured
        end
    end
    return inv.items.progress.reportMode or "classic"
end

function inv.items.setReportMode(mode)
    local normalized = tostring(mode or ""):lower()
    if normalized ~= "classic" and normalized ~= "inline" then
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

-- Strip @X codes only; dbot.stripColors also consumes literal '<' characters.
local function stripAardwolfCodes(s)
    if s == nil then return "" end
    s = s:gsub("@@", "\001AT\001")
    s = s:gsub("@x%d+", "")
    s = s:gsub("@[%a]", "")
    s = s:gsub("\001AT\001", "@")
    return s
end

function inv.items.showProgress(stage, current, total, itemName)
    inv.items.progress.stage = stage
    inv.items.progress.current = current
    inv.items.progress.total = total

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

    local mode = inv.items.getReportMode()

    -- Build message with Aardwolf color codes
    local msg = string.format("@w[%s@w] @W%d%% @w(%d/%d)", bar, pct, current, total)

    local cleanedItemName = nil
    if itemName then
        -- Strip enchant text from display name
        local displayName = itemName:gsub("%s+[A-Z][a-z]+%s+%+?%-?%d+%s*%(removable[^%)]*%)%s*", "")
        displayName = displayName:gsub("%s+%(removable[^%)]*%)%s*", "")
        cleanedItemName = stripAardwolfCodes(displayName)
        msg = msg .. " " .. displayName
    end

    local plainMsg = stripAardwolfCodes(msg)
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
    if expandAlias then
        expandAlias(cmd, false)
    elseif send then
        send(cmd)
    end
end

function inv.items.runReportFromLink(objId)
    local itemId = tostring(objId or "")
    if itemId == "" then
        return
    end

    local cmd = "dinv report " .. itemId
    if expandAlias then
        expandAlias(cmd, false)
    elseif send then
        send(cmd)
    else
        dbot.warn("inv.items.runReportFromLink: unable to execute '" .. cmd .. "'")
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

----------------------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------------------

function inv.items.init.atInstall()
    return DRL_RET_SUCCESS
end

function inv.items.init.atActive()
    local retval = inv.items.load()
    if retval ~= DRL_RET_SUCCESS then
        dbot.warn("inv.items.init.atActive: Failed to load items data from storage: " ..
                  dbot.retval.getString(retval))
    end
    
    -- Set up refresh timer if enabled
    if inv.config.isRefreshEnabled() then
        inv.items.refreshOn(inv.config.getRefreshPeriod(), 0)
    end
    
    return retval
end

function inv.items.fini(doSaveState)
    local retval = DRL_RET_SUCCESS
    
    if doSaveState then
        retval = inv.items.save()
        if retval ~= DRL_RET_SUCCESS and retval ~= DRL_RET_UNINITIALIZED then
            dbot.warn("inv.items.fini: Failed to save inv.items module data: " ..
                      dbot.retval.getString(retval))
        end
    end
    
    -- Clean up timer
    dbot.deleteTimer(inv.items.timer.name)
    
    return retval
end

----------------------------------------------------------------------------------------------------
-- Save/Load/Reset
----------------------------------------------------------------------------------------------------

function inv.items.save()
    if inv.items.table == nil then
        return inv.items.reset()
    end
    
    return dbot.storage.saveTable(dbot.backup.getCurrentDir() .. inv.items.stateName,
                                   "inv.items.table", inv.items.table, true)
end

function inv.items.loadPersistentItemsTable()
    if not dbot or not dbot.backup or not dbot.backup.getCurrentDir then
        return nil
    end
    local fileName = dbot.backup.getCurrentDir() .. (inv.items and inv.items.stateName or "inv-items.state")
    local f = io.open(fileName, "r")
    if f == nil then
        dbot.debug("inv.items: persistence file not found: " .. fileName, "inv.items")
        return nil
    end
    local content = f:read("*a")
    f:close()
    if not content or content == "" then
        return nil
    end

    local chunk, err = loadstring(content)
    if not chunk then
        dbot.warn("inv.items: Failed to parse persistence file: " .. (err or "unknown"))
        return nil
    end

    local env = { inv = { items = {} } }
    setmetatable(env, { __index = _G })
    if setfenv then
        setfenv(chunk, env)
    end
    chunk()

    local persisted = env.inv.items.table
    if persisted then
        for _, entry in pairs(persisted) do
            local stats = entry and entry.stats
            if stats then
                local loc = tostring(stats[invStatFieldLocation] or "")
                local wornLoc = tostring(stats[invStatFieldWorn] or "")

                if loc == invItemLocWorn and wornLoc ~= "" and wornLoc ~= "undefined" and wornLoc ~= invItemWornNotWorn then
                    local wearNum = inv.wearLocId and inv.wearLocId[wornLoc]
                    if wearNum ~= nil then
                        stats[invStatFieldLocation] = tostring(wearNum)
                        loc = tostring(wearNum)
                    end
                end

                local lastStored = tostring(stats[invStatFieldLastStored] or "")
                if lastStored ~= "" and not inv.items.isStorageLocation(lastStored) then
                    stats[invStatFieldLastStored] = ""
                end

                if loc ~= "" and inv.items.isStorageLocation(loc) then
                    stats[invStatFieldLastStored] = loc
                end

                if tostring(stats[invStatFieldLastStored] or "") == invItemLocKeyring
                    and tostring(stats[invStatFieldLocation] or "") == "unknown" then
                    stats[invStatFieldLocation] = invItemLocKeyring
                    stats[invStatFieldContainer] = invItemLocKeyring
                end
            end
        end
    end

    return persisted
end

function inv.items.lookupPersistentItem(objId)
    if not objId or objId == "" then
        return nil
    end

    local itemsTable = inv.items.loadPersistentItemsTable()
    if not itemsTable then
        dbot.debug("inv.items: persistence lookup skipped (no inv-items.state)", "inv.items")
        return nil
    end

    local entry = itemsTable[tostring(objId)]
    if entry then
        dbot.debug("inv.items: persistence hit for objId=" .. tostring(objId), "inv.items")
    else
        dbot.debug("inv.items: persistence miss for objId=" .. tostring(objId), "inv.items")
    end
    return entry
end

function inv.items.load()
    return dbot.storage.loadTable(dbot.backup.getCurrentDir() .. inv.items.stateName, inv.items.reset)
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
    -- Try to auto-initialize if not already done
    if not inv.init.initializedActive then
        inv.items.ensureInitialized()
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
    
    dbot.debug("inv.items.refresh: Refresh requested for location '" .. tostring(refreshLoc or "nil") .. "'", "inv.items")

    if refreshLoc == invItemsRefreshLocAll then
        dbot.debug("inv.items.refresh: full-location refresh requested; preserving existing identify data", "inv.items")
    end

    if refreshLoc == invItemsRefreshLocAll then
        inv.items.refreshIdentifyPartials = true
    elseif type(callback) == "table" and callback.identifyPartials then
        inv.items.refreshIdentifyPartials = true
    else
        inv.items.refreshIdentifyPartials = false
    end
    inv.state = invStateDiscovery
    inv.items.refreshInProgress = true
    inv.items.refreshSeen = {}
    inv.items.eqdataSeen = {}
    inv.items.expectedInvdataContainerId = nil

    -- Ensure discovery triggers are registered for refresh scans
    if DINV.discovery and DINV.discovery.register then
        DINV.discovery.register()
    end

    -- Toggle prompt handling at refresh boundaries to suppress stray prompt output.
    if inv.items.sendDiscoveryCommand then
        inv.items.sendDiscoveryCommand("prompt")
    else
        sendSilent("prompt")
    end

    local function startDiscovery()
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
            dbot.execute.queue.fence(startDiscovery)
        else
            startDiscovery()
        end
    end

    if delay and delay > 0 and tempTimer then
        tempTimer(delay, startWithFence)
    else
        startWithFence()
    end

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
    inv.items.identifyNext()
    return DRL_RET_SUCCESS
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
    if inv.items.buildInProgress or inv.items.identifyInProgress then
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

----------------------------------------------------------------------------------------------------
-- Item Access Functions
----------------------------------------------------------------------------------------------------

function inv.items.getItem(objId)
    if inv.items.table == nil then
        return nil
    end
    return inv.items.table[tostring(objId)]
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

function inv.items._parseQuerySegment(segment)
    local tokens = {}
    for token in tostring(segment):gmatch("%S+") do
        table.insert(tokens, token)
    end

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

function inv.items.setItem(objId, itemData)
    if inv.items.table == nil then
        inv.items.table = {}
    end
    inv.items.table[tostring(objId)] = itemData
    return DRL_RET_SUCCESS
end

function inv.items.removeItem(objId)
    if inv.items.table then
        inv.items.table[tostring(objId)] = nil
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

    if item and inv.items.getFrequentCacheKeys then
        local nameKeys = inv.items.getFrequentCacheKeys(item)
        if nameKeys then
            for _, nameKey in ipairs(nameKeys) do
                inv.cache.remove("frequent", nameKey)
            end
        end
    end

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
    local item = inv.items.getItem(key)
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

    if not inv.cache or not inv.cache.get then
        return false
    end

    local itemId = item.stats[invStatFieldId]
    if itemId then
        local cached = inv.cache.get("recent", tostring(itemId))
        if cached and cached.stats and cached.stats.identifyLevel == invIdLevelFull then
            dbot.debug("Cache hit (recent) for ID: " .. tostring(itemId), "inv.items")
            for k, v in pairs(cached.stats) do
                if k ~= invStatFieldId then
                    if k == invStatFieldWearable and (v == "undefined" or v == "unknown") then
                        -- Keep existing wearable data when cache only has placeholder values.
                    elseif k == invStatFieldLocation
                        or k == invStatFieldContainer
                        or k == invStatFieldWorn
                        or k == invStatFieldLastStored then
                        -- Never restore dynamic location fields from cache.
                    else
                        item.stats[k] = v
                    end
                end
            end
            item.stats.identifyLevel = invIdLevelFull
            return true
        end
    end

    local itemType = item.stats[invStatFieldType]
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
                                elseif k == invStatFieldLocation
                                    or k == invStatFieldContainer
                                    or k == invStatFieldWorn
                                    or k == invStatFieldLastStored then
                                    -- Never restore dynamic location fields from cache.
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

    local itemId = item.stats[invStatFieldId]
    if not itemId then
        return
    end

    local itemType = item.stats[invStatFieldType]
    local isFrequent = inv.items.isFrequentCacheType(itemType)

    if item.stats.identifyLevel == invIdLevelPartial and not isFrequent then
        return
    end

    if not inv.cache or not inv.cache.set then
        return
    end

    inv.cache.set("recent", tostring(itemId), item)

    if isFrequent then
        local nameKeys = inv.items.getFrequentCacheKeys(item)
        if nameKeys then
            local stored = { stats = {} }
            for k, v in pairs(item.stats) do
                if k ~= invStatFieldId then
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
    if not item or not item.stats then
        return
    end

    local itemId = item.stats[invStatFieldId]
    if not itemId then
        return
    end

    if not inv.cache or not inv.cache.get or not inv.cache.set then
        return
    end

    local key = tostring(itemId)
    local cached = inv.cache.get("frequent", key)
    if cached and cached.stats then
        cached.stats = cached.stats or {}
        for k, v in pairs(item.stats) do
            if k ~= "identifyLevel" then
                cached.stats[k] = v
            end
        end
        if item.stats.identifyLevel == invIdLevelFull then
            cached.stats.identifyLevel = invIdLevelFull
        end
        inv.cache.set("frequent", key, cached)
        return
    end

    local stored = { stats = {} }
    for k, v in pairs(item.stats) do
        stored.stats[k] = v
    end
    if stored.stats.identifyLevel ~= invIdLevelFull then
        stored.stats.identifyLevel = invIdLevelSoft
    end
    inv.cache.set("frequent", key, stored)
end

----------------------------------------------------------------------------------------------------
-- Invdata/Eqdata Parsing
----------------------------------------------------------------------------------------------------

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
    item.stats[invStatFieldName] = dbot.stripColors and dbot.stripColors(itemName) or itemName
    -- Always update colorname from invdata if we have a valid name
    -- Only keep existing if the new itemName is empty or worse
    if itemName and itemName ~= "" then
        local existingPlain = existingColorName and (dbot.stripColors and dbot.stripColors(existingColorName) or existingColorName) or ""
        local newPlain = dbot.stripColors and dbot.stripColors(itemName) or itemName
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
        item.stats[invStatFieldTimer] = timer
        if item.stats.identifyLevel ~= invIdLevelFull then
            item.stats.identifyLevel = invIdLevelPartial
        end
        item.flags = flags
        item.unique = unique
    end

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
        item.stats[invStatFieldWorn] = wornValue
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

    -- Check cache for previously identified data
    if inv.cache and inv.cache.get then
        local cached = inv.cache.get("frequent", tostring(objId))
        if cached and cached.stats and cached.stats.identifyLevel == invIdLevelFull then
            for k, v in pairs(cached.stats) do
                if item.stats[k] == nil then
                    item.stats[k] = v
                end
            end
            item.stats.identifyLevel = invIdLevelFull
            dbot.debug("Restored full identify from cache for " .. objId, "inv.items")
        end
    end

    local cacheHit = inv.items.applyCachedStats(item)
    if cacheHit then
        dbot.debug("Cache hit: " .. itemName:sub(1, 30), "inv.items")
    end

    inv.items.markSoftIdentified(item)

    inv.items.setItem(objId, item)
    inv.items.cacheObservedItem(item)

    dbot.debug("Parsed: " .. objId .. " [" .. typeName .. "] " .. itemName:sub(1, 25), "inv.items")

    return DRL_RET_SUCCESS
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
                if item.stats[k] == nil then
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

    if objId and (not persisted or not (persisted.stats and persisted.stats.identifyLevel == invIdLevelFull)) then
        local retval = inv.items.buildSingleItem(objId, "invitem")
        if retval == DRL_RET_IN_COMBAT then
            inv.items.enqueueDeferredIdentify(objId, "invitem")
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
    if requestedContainerId then
        inv.items.awaitingInvdataContainerId = tostring(requestedContainerId)
    elseif cmd:match("^invdata%s*$") then
        inv.items.awaitingInvdataContainerId = nil
    end

    if DINV and DINV.discovery and DINV.discovery.bumpRawSuppressWindow then
        DINV.discovery.bumpRawSuppressWindow(cmd)
    end

    if DINV and DINV.discovery and DINV.discovery.queuePromptSuppress then
        DINV.discovery.queuePromptSuppress()
    end
    sendSilent(cmd)
end

function inv.items.discoverChain()
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

        if inv.items.refreshInProgress and inv.items.save then
            inv.items.save()
            dbot.debug("Refresh main invdata complete: persisted inventory state.", "inv.items")
        end

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
    local prunedItems = {}
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
                    if item then
                        inv.items.removeItemFromCache(objId, item)
                    end
                    table.insert(prunedItems, {
                        objId = tostring(objId),
                        name = tostring(item and item.stats and item.stats[invStatFieldName] or "unknown"),
                        colorName = tostring(item and item.stats and item.stats[invStatFieldColorName] or ""),
                    })
                    inv.items.removeItem(objId)
                    unseen = unseen + 1
                end
            end
        end
    end

    if unseen > 0 then
        dbot.debug("Refresh pruned " .. unseen .. " unseen item(s) from persistence", "inv.items")
        dbot.print("")
        for _, pruned in ipairs(prunedItems) do
            local displayName = pruned.colorName
            if not displayName or displayName == "" then
                displayName = pruned.name or "Unidentified"
            end
            dbot.print("@C[DINV INFO]@W Removed orphan: \"" .. tostring(displayName) .. "@W\" (" .. tostring(pruned.objId) .. ")")
            dbot.debug(string.format("Pruned item objId=%s name=%s", tostring(pruned.objId), tostring(pruned.name)), "inv.items")
        end
        inv.items.pendingInvmonSave = true
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
        inv.items.pruneRefreshOrphans()
        inv.items.refreshSeen = nil
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
            inv.items.save()
            dbot.debug("Refresh complete: persisted inventory state.", "inv.items")
        end

        if inv.items.pendingInvmonSave then
            inv.items.pendingInvmonSave = nil
            dbot.debug("Refresh complete: cleared pending invmon save flag.", "inv.items")
        end

        if inv.items.refreshIdentifyPartials then
            inv.items.refreshIdentifyPartials = false
            local identifyRet = inv.items.identifyPartialItems()
            if identifyRet ~= DRL_RET_SUCCESS then
                dbot.warn("Refresh complete: unable to start partial identification (" .. tostring(identifyRet) .. ")")
            end
        else
            inv.items.eqdataSeen = {}
        end
        return
    end

    inv.items.discoveryStage = 4
    local itemCount = inv.items.getCount()

    cecho("\n<cyan>[DINV] Stage 4/4: Identifying " .. itemCount .. " items...\n")
    inv.items.progress.stage = "Identifying items"
    inv.items.progress.total = itemCount

    inv.items.discoveryComplete = true
    inv.state = invStateIdentify
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
    if inv.items.buildInProgress or inv.items.identifyInProgress then
        return DRL_RET_BUSY
    end

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
    return DRL_RET_SUCCESS
end

function inv.items.startIdentification()
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

    if inv.items.identifyTotal == 0 then
        cecho("\n<green>[DINV] All items already identified (or cached)!\n")
        inv.items.buildComplete()
        return
    end

    cecho("\n<cyan>[DINV] Need to identify " .. inv.items.identifyTotal .. " item(s)...\n")
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

    inv.items.identifyIndex = (inv.items.identifyIndex or 0) + 1

    -- Check if done
    if inv.items.identifyIndex > #inv.items.identifyQueue then
        inv.items.identifyInProgress = false
        inv.items.identifyCurrentId = nil
        inv.items.identifyCurrentContainer = nil

        if DINV.discovery and DINV.discovery.unregisterIdentifyTriggers then
            DINV.discovery.unregisterIdentifyTriggers()
        end

        inv.items.buildComplete()
        return
    end

    local objId = inv.items.identifyQueue[inv.items.identifyIndex]
    local item = inv.items.getItem(objId)

    if not item then
        -- Item gone, skip
        tempTimer(0.1, function() inv.items.identifyNext() end)
        return
    end

    if inv.items.applyCachedStats(item) then
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
    if item and item.stats then
        item.stats.identifyLevel = invIdLevelFull
        inv.items.ensureKeywordsField(item)
        dbot.debug("handleIdentifyFence: Marked item as identified", "inv.items")

        inv.items.setItem(objId, item)

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
        inv.state = invStateIdle
        if DINV and DINV.setBuildPhase then
            DINV.setBuildPhase(0)
            sendGMCP("config prompt on")
        end
        if inv.items.save then
            inv.items.save()
        end
        dbot.debug("buildComplete: single-item identify complete for objId=" .. tostring(singleId), "inv.items")
        tempTimer(0.1, function()
            if inv and inv.items and inv.items.processDeferredIdentifyQueue then
                inv.items.processDeferredIdentifyQueue("buildComplete")
            end
        end)
        return
    end

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

    -- Save data
    if inv.items.save then inv.items.save() end
    if inv.config and inv.config.save then inv.config.save() end
    if inv.config and inv.config.table then
        inv.config.table.isBuildExecuted = true
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
end

function inv.items.buildAbort()
    if not inv.items.buildInProgress then
        dbot.info("No build is currently in progress.")
        return DRL_RET_SUCCESS
    end

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
    inv.state = invStateIdle
    if DINV and DINV.setBuildPhase then
        DINV.setBuildPhase(0)
		sendGMCP("config prompt on")
    end

    -- Unregister identify triggers
    if DINV.discovery and DINV.discovery.unregisterIdentifyTriggers then
        DINV.discovery.unregisterIdentifyTriggers()
    end

    cecho("\n<yellow>[DINV] Build aborted by user.\n")

    local endTag = inv.items.buildEndTag
    inv.items.buildEndTag = nil

    if endTag and inv.tags and inv.tags.stop then
        inv.tags.stop(invTagsBuild, endTag, DRL_RET_HALTED)
    end

    return DRL_RET_SUCCESS
end

function inv.items.onInvmon(dataLine)
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

    if objId == "" then
        dbot.debug("onInvmon: objId is empty after parse", "inv.items")
        return DRL_RET_INVALID_PARAM
    end

    dbot.debug(string.format("onInvmon parsed: action=%d, objId=%s, containerId=%s, wearLoc=%s",
        actionNum, tostring(objId), tostring(containerId), tostring(wearLoc)), "inv.items")

    -- Check if we have a wait state for the identify process
    local waitState = inv.items.identifyWaitForInvmon
    local item = inv.items.getItem(objId)
    local actionName = invmon and invmon.action and invmon.action[actionNum] or "Unknown"
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

    -- Any action other than explicit consumption indicates the item still exists
    -- somewhere, so cancel delayed removal if one is pending.
    if actionNum ~= invmonActionConsumed then
        inv.items.cancelPendingRemoval(objId)
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
            inv.items.removeItemFromCache(objId, item)
            inv.items.removeItem(objId)
            item = nil
            dbot.debug("onInvmon: Item removed from inventory and pruned from persistence", "inv.items")
            shouldSave = true

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
            inv.items.removeItemAndSaveNow(objId, "invmon_consumed")
            dbot.debug("onInvmon: Item consumed: " .. tostring(objId), "inv.items")
            shouldSave = false
        end
    elseif actionNum == invmonActionAddedToInv then
        -- New item added - create an entry for it
        if inv.items.eqdataSeen then
            inv.items.eqdataSeen[tostring(objId)] = nil
        end
        if inv.items.add then
            inv.items.add(objId)
            local newItem = inv.items.getItem(objId)
            if newItem then
                newItem.stats = newItem.stats or {}
                newItem.stats[invStatFieldLocation] = "inventory"
            end
        end
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

    if shouldSave then
        inv.items.scheduleSaveFromInvmon()
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

function inv.items.search(query, displayMode)
    displayMode = displayMode or "basic"

    if inv.items.table == nil or dbot.table.getNumEntries(inv.items.table) == 0 then
        dbot.info("Your inventory table is empty. Run '@Gdinv build confirm@W' to populate it.")
        return {}, DRL_RET_SUCCESS
    end

    local results = {}
    local clauses = inv.items.parseQuery(query or "")

    for objId, item in pairs(inv.items.table) do
        local itemName = inv.items.getStatField(objId, invStatFieldName) or ""
        local itemType = inv.items.getStatField(objId, invStatFieldType) or ""
        local level = tonumber(inv.items.getStatField(objId, invStatFieldLevel)) or 0
        local wearable = inv.items.getStatField(objId, invStatFieldWearable) or ""
        local container = inv.items.getStatField(objId, invStatFieldContainer) or ""
        local wornLoc = inv.items.getStatField(objId, invStatFieldWorn) or ""

        local clauseMatch = false
        for _, criteria in ipairs(clauses) do
            local matchedAll = true
            local relativeIndex = nil
            local relativeName = nil

            for _, entry in ipairs(criteria) do
                local key = tostring(entry.key or ""):lower()
                local value = entry.value
                local negated = entry.negated
                local match = false

                if key == "type" then
                    match = string.lower(itemType) == string.lower(value)
                elseif key == "name" then
                    relativeIndex, relativeName = inv.items.convertRelative(value)
                    if relativeIndex then
                        match = string.find(string.lower(itemName), string.lower(relativeName), 1, true) ~= nil
                    else
                        match = string.find(string.lower(itemName), string.lower(value), 1, true) ~= nil
                    end
                elseif key == "wearable" then
                    match = string.find(string.lower(wearable), string.lower(value), 1, true) ~= nil
                elseif key == "keyword" or key == "keywords" then
                    local keywordsStr = inv.items.getStatField(objId, invStatFieldKeywords) or ""
                    for word in keywordsStr:gmatch("%S+") do
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
                    local flagsStr = inv.items.getStatField(objId, invStatFieldFlags) or ""
                    for flag in flagsStr:gmatch("%S+") do
                        flag = flag:gsub(",", "")
                        if string.find(string.lower(flag), string.lower(value), 1, true) ~= nil then
                            match = true
                            break
                        end
                    end
                elseif key == "id" then
                    match = tostring(objId) == tostring(value)
                elseif key == "container" then
                    match = tostring(container) == tostring(value)
                elseif key == "location" or key == "loc" then
                    local location = inv.items.getStatField(objId, invStatFieldLocation) or ""
                    match = string.find(string.lower(tostring(location)), string.lower(tostring(value)), 1, true) ~= nil
                elseif key == "rname" then
                    local relIdx, relVal = inv.items.convertRelative(value)
                    local target = relVal or value
                    local hay = string.lower(itemName)
                    local needle = string.lower(tostring(target))
                    match = string.find(hay, needle, 1, true) ~= nil
                    if match and relIdx then
                        relativeIndex = relIdx
                        relativeName = target
                    end
                elseif key == "rlocation" or key == "rloc" then
                    local relIdx, relVal = inv.items.convertRelative(value)
                    local target = relVal or value
                    local location = inv.items.getStatField(objId, invStatFieldLocation) or ""
                    match = string.find(string.lower(tostring(location)), string.lower(tostring(target)), 1, true) ~= nil
                    if match and relIdx then
                        relativeIndex = relIdx
                        relativeName = target
                    end
                elseif key == "worn" then
                    match = inv.items.isWorn(objId)
                elseif key == "minlevel" then
                    match = level >= tonumber(value or 0)
                elseif key == "maxlevel" then
                    match = level <= tonumber(value or 999)
                elseif key == "level" then
                    match = level == tonumber(value or 0)
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
                clauseMatch = true
                break
            end
        end

        if clauseMatch then
            if container ~= "" and inv.config.isIgnored(container) then
                -- Skip ignored containers.
            else
                table.insert(results, objId)
            end
        end
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
        return false
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

    local function printLine(msg)
        local raw = tostring(msg or "")
        if cechoLink then
            local idPrefix = "@Y" .. formattedId .. "@W "
            if raw:sub(1, #idPrefix) == idPrefix then
                local linkCommand = string.format("inv.items.runReportFromLink(%q)", tostring(objId))
                local tooltip = "Run: dinv report " .. tostring(objId)
                local remainder = raw:sub(#idPrefix + 1)
                cechoLink("<yellow>" .. formattedId .. "<reset>", linkCommand, tooltip, true)
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
            table.insert(baseStats, string.format("@G%d@D%s@w", val, stat.label))
        end

        local rollStats = {}
        table.insert(rollStats, string.format("@G%d@Dhr@w", hr))
        table.insert(rollStats, string.format("@G%d@Ddr@w", dr))

        local resourceStats = {}
        local hpVal = tonumber(inv.items.getStatField(objId, invStatFieldHp)) or 0
        local manaVal = tonumber(inv.items.getStatField(objId, invStatFieldMana)) or 0
        local movesVal = tonumber(inv.items.getStatField(objId, invStatFieldMoves)) or 0
        if hpVal ~= 0 then
            table.insert(resourceStats, string.format("@G%d@Dhp@w", hpVal))
        end
        if manaVal ~= 0 then
            table.insert(resourceStats, string.format("@G%d@Dmn@w", manaVal))
        end
        if movesVal ~= 0 then
            table.insert(resourceStats, string.format("@G%d@Dmv@w", movesVal))
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
            local function stripColorCodes(value)
                if dbot.stripColors then
                    return dbot.stripColors(value or "")
                end
                local text = tostring(value or "")
                text = text:gsub("@x%d+", "")
                text = text:gsub("@.", "")
                return text
            end

            local function padColored(value, width)
                local raw = tostring(value or "")
                local plain = stripColorCodes(raw)
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
            local nameWidth = widths.name or 42
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
                return string.format("@G%d@D%s@w", num, suffix)
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

            local wrappedNameLines = wrapColoredText(nameText, effectiveNameWidth)

            local cells = {
                "@Y", formattedId, "@W ",
                padColored(wrappedNameLines[1] or "", effectiveNameWidth), sep,
                padColored(levelText, levelWidth), sep,
            }

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
            table.insert(cells, padColored(hpText, resourceWidth))
            table.insert(cells, sep)
            table.insert(cells, padColored(mnText, resourceWidth))
            table.insert(cells, sep)
            table.insert(cells, padColored(mvText, resourceWidth))
            table.insert(cells, sep)
            table.insert(cells, padColored(risText, risWidth))

            local firstLine = table.concat(cells, "")
            if #wrappedNameLines > 1 then
                local continuationLines = {}
                local idBlank = string.rep(" ", #formattedId)
                for i = 2, #wrappedNameLines do
                    table.insert(continuationLines, table.concat({
                        "@Y", idBlank, "@W ",
                        padColored(wrappedNameLines[i], effectiveNameWidth)
                    }, ""))
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
        local plainName = dbot.stripColors and dbot.stripColors(rawName) or rawName
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
    maxNameWidth = math.min(maxNameWidth, 48)

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

    local usableContainer = isUsableContainerFn or isUsableContainer
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
