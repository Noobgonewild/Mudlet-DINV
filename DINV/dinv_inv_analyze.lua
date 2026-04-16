----------------------------------------------------------------------------------------------------
-- INV Analyze Module
-- Optimal equipment analysis across levels
----------------------------------------------------------------------------------------------------

inv.analyze = {}
inv.analyze.init = inv.analyze.init or {}
inv.analyze.table = {}
inv.analyze.queue = inv.analyze.queue or {}
inv.analyze.activeJob = inv.analyze.activeJob or nil
inv.analyze.stateName = "inv-analyze.state"
inv.analyze.lastAnnouncedLevel = inv.analyze.lastAnnouncedLevel or nil
inv.analyze.lastSeenBaseLevel = inv.analyze.lastSeenBaseLevel or nil

function inv.analyze.init.atInstall()
    return DRL_RET_SUCCESS
end

function inv.analyze.init.atActive()
    local retval = inv.analyze.load()
    if retval ~= DRL_RET_SUCCESS then
        dbot.debug("inv.analyze.init.atActive: Using fresh analysis table", "inv.analyze")
    end
    return DRL_RET_SUCCESS
end

function inv.analyze.fini(doSaveState)
    if doSaveState then
        inv.analyze.save()
    end
    return DRL_RET_SUCCESS
end

function inv.analyze.save()
    if inv.analyze.table == nil then
        return inv.analyze.reset()
    end
    return dbot.storage.saveTable(dbot.backup.getCurrentDir() .. inv.analyze.stateName,
        "inv.analyze.table", inv.analyze.table, true)
end

function inv.analyze.load()
    return dbot.storage.loadTable(dbot.backup.getCurrentDir() .. inv.analyze.stateName, inv.analyze.reset)
end

function inv.analyze.reset()
    inv.analyze.table = {}
    return DRL_RET_SUCCESS
end

function inv.analyze._expandPositions(positions)
    if positions == nil or positions == "" then
        return nil
    end

    local expanded = {}
    for token in tostring(positions):gmatch("%S+") do
        if inv.items.isWearableLoc(token) then
            expanded[token] = true
        elseif inv.items.isWearableType(token) then
            local locs = inv.items.wearableTypeToLocs(token)
            for loc in tostring(locs):gmatch("%S+") do
                expanded[loc] = true
            end
        end
    end

    return expanded
end

function inv.analyze.create(priorityName, positions, endTag, onComplete)
    if not inv.priority.exists(priorityName) then
        dbot.warn("Priority '" .. priorityName .. "' does not exist")
        return inv.tags.stop(invTagsAnalyze, endTag, DRL_RET_MISSING_ENTRY)
    end

    local maxLevel = 201
    local tier = dbot.gmcp.getTier and dbot.gmcp.getTier() or 0
    local tierBonus = tier * 10
    local allowedPositions = inv.analyze._expandPositions(positions)

    if inv.analyze.activeJob and inv.analyze.activeJob.priorityName == priorityName then
        if onComplete then
            table.insert(inv.analyze.activeJob.callbacks, onComplete)
        end
        dbot.info("Analysis already in progress for priority '" .. priorityName .. "'")
        return DRL_RET_SUCCESS
    end
    for _, queuedJob in ipairs(inv.analyze.queue or {}) do
        if queuedJob.priorityName == priorityName then
            if onComplete then
                table.insert(queuedJob.callbacks, onComplete)
            end
            dbot.info("Analysis already queued for priority '" .. priorityName .. "'")
            return DRL_RET_SUCCESS
        end
    end
    local job = {
        priorityName = priorityName,
        allowedPositions = allowedPositions,
        maxLevel = maxLevel,
        tierBonus = tierBonus,
        currentLevel = 1,
        batchSize = 5,
        delaySec = 0.5,
        endTag = endTag,
        callbacks = {},
    }

    inv.analyze.table[priorityName] = { positions = allowedPositions, levels = {} }
    dbot.info("Creating analysis for priority '" .. priorityName .. "'")

    if onComplete then
        table.insert(job.callbacks, onComplete)
    end

    table.insert(inv.analyze.queue, job)
    inv.analyze._startNextJob()
    return DRL_RET_SUCCESS
end

function inv.analyze._startNextJob()
    if inv.analyze.activeJob or #inv.analyze.queue == 0 then
        return
    end

    local job = table.remove(inv.analyze.queue, 1)
    inv.analyze.activeJob = job
    inv.analyze._runJobBatch()
end

function inv.analyze._runJobBatch()
    local job = inv.analyze.activeJob
    if not job then
        return
    end

    local batchStart = job.currentLevel
    local batchEnd = math.min(job.maxLevel, batchStart + job.batchSize - 1)

    dbot.info(string.format("Creating equipment sets for levels %d-%d", batchStart, batchEnd))

    for level = batchStart, batchEnd do
        local wearableLevel = level + job.tierBonus
        inv.set.create(job.priorityName, wearableLevel, nil, nil, true, level)
        local setData = inv.set.table[job.priorityName]
            and inv.set.table[job.priorityName][tostring(wearableLevel)]
        if setData then
            local entry = {
                created = setData.created,
                score = setData.score,
                equipment = {}
            }
            for loc, objId in pairs(setData.equipment or {}) do
                if not job.allowedPositions or job.allowedPositions[loc] then
                    entry.equipment[loc] = objId
                end
            end
            inv.analyze.table[job.priorityName].levels[tostring(level)] = entry
        end
    end

    job.currentLevel = batchEnd + 1

    if job.currentLevel > job.maxLevel then
        dbot.info("Analysis created for priority '" .. job.priorityName .. "' across levels 1-" .. job.maxLevel)
        local saveRetval = inv.analyze.save()
        if saveRetval ~= DRL_RET_SUCCESS then
            dbot.warn("inv.analyze: Failed to save analysis for priority '" .. job.priorityName .. "': " ..
                dbot.retval.getString(saveRetval))
        end
        if job.endTag then
            inv.tags.stop(invTagsAnalyze, job.endTag, DRL_RET_SUCCESS)
        end
        for _, callback in ipairs(job.callbacks or {}) do
            callback(job.priorityName)
        end
        inv.analyze.activeJob = nil
        inv.analyze._startNextJob()
        return
    end

    if tempTimer and job.delaySec and job.delaySec > 0 then
        tempTimer(job.delaySec, function() inv.analyze._runJobBatch() end)
    else
        inv.analyze._runJobBatch()
    end
end

function inv.analyze.sets(priorityName, positions, endTag)
    if priorityName == nil or priorityName == "" or priorityName == "all" then
        for name in pairs(inv.priority.table or {}) do
            inv.analyze.create(name, positions, nil)
        end
        dbot.info("Analysis sets generated for all priorities")
        return inv.tags.stop(invTagsAnalyze, endTag, DRL_RET_SUCCESS)
    end

    return inv.analyze.create(priorityName, positions, endTag)
end

function inv.analyze.delete(priorityName, endTag)
    if inv.analyze.table[priorityName] then
        inv.analyze.table[priorityName] = nil
        local saveRetval = inv.analyze.save()
        if saveRetval ~= DRL_RET_SUCCESS then
            dbot.warn("inv.analyze.delete: Failed to save analysis data: " .. dbot.retval.getString(saveRetval))
        end
        dbot.info("Deleted analysis for priority '" .. priorityName .. "'")
    end
    return inv.tags.stop(invTagsAnalyze, endTag, DRL_RET_SUCCESS)
end

function inv.analyze.list(endTag)
    dbot.print("@WAnalysis Reports:@w")
    local count = 0
    for name, _ in pairs(inv.analyze.table) do
        dbot.print("  @G" .. name .. "@w")
        count = count + 1
    end
    if count == 0 then
        dbot.print("  @Y(none)@w")
    end
    return inv.tags.stop(invTagsAnalyze, endTag, DRL_RET_SUCCESS)
end

function inv.analyze.display(priorityName, levelOrSkip, endTag)
    dbot.info("Displaying analysis for priority '" .. priorityName .. "'")
    local analysisData = inv.analyze.table[priorityName]
    if analysisData == nil then
        dbot.warn("No analysis found for priority '" .. priorityName .. "'")
        return inv.tags.stop(invTagsAnalyze, endTag, DRL_RET_MISSING_ENTRY)
    end

    dbot.print("@WAnalysis Results: @G" .. priorityName .. "@w")
    local levels = {}
    local analysis = analysisData.levels or {}
    for level in pairs(analysis) do
        table.insert(levels, tonumber(level))
    end
    table.sort(levels)

    local singleLevel = tonumber(levelOrSkip)

    if singleLevel then
        local entry = analysis[tostring(singleLevel)]
        if not entry then
            dbot.warn("No analysis entry found for level " .. tostring(singleLevel))
            return inv.tags.stop(invTagsAnalyze, endTag, DRL_RET_MISSING_ENTRY)
        end

        dbot.print(string.format("  @YLevel %3d@W: score @G%d@W", singleLevel, entry.score or 0))
        local locs = {}
        for loc in pairs(entry.equipment or {}) do
            table.insert(locs, loc)
        end
        table.sort(locs)
        for _, loc in ipairs(locs) do
            local objId = entry.equipment[loc]
            local name = inv.items.getStatField(objId, invStatFieldName) or ("obj " .. tostring(objId))
            dbot.print(string.format("    @C%-10s@W %s", loc .. ":", name))
        end
        return inv.tags.stop(invTagsAnalyze, endTag, DRL_RET_SUCCESS)
    end

    local function statValue(objId, field)
        return tonumber(inv.items.getStatField(objId, field)) or 0
    end

    local function formatAnalyzeLine(level, marker, objId, loc)
        local name = inv.items.getStatField(objId, invStatFieldName) or ("obj " .. tostring(objId))
        local markerColor = (marker == ">>") and "@G" or "@R"
        return string.format(
            "%3d %s%s@w %-24s %-10s %4d %4d %3d %3d %3d %3d %3d %3d %3d %5d %5d %5d",
            tonumber(level) or 0,
            markerColor,
            marker,
            name,
            loc,
            statValue(objId, invStatFieldHitroll),
            statValue(objId, invStatFieldDamroll),
            statValue(objId, invStatFieldInt),
            statValue(objId, invStatFieldWis),
            statValue(objId, invStatFieldLuck),
            statValue(objId, invStatFieldStr),
            statValue(objId, invStatFieldDex),
            statValue(objId, invStatFieldCon),
            statValue(objId, invStatFieldAllPhys),
            statValue(objId, invStatFieldHp),
            statValue(objId, invStatFieldMana),
            statValue(objId, invStatFieldMoves)
        )
    end

    local prevEquipment = nil
    for _, level in ipairs(levels) do
        local entry = analysis[tostring(level)]
        local equipment = entry and entry.equipment or {}
        local changed = {}

        for loc, objId in pairs(equipment) do
            local prevObjId = prevEquipment and prevEquipment[loc] or nil
            if prevObjId ~= objId then
                table.insert(changed, { loc = loc, fromObjId = prevObjId, toObjId = objId })
            end
        end

        if prevEquipment then
            for loc, prevObjId in pairs(prevEquipment) do
                if equipment[loc] == nil then
                    table.insert(changed, { loc = loc, fromObjId = prevObjId, toObjId = nil })
                end
            end
        end

        if #changed > 0 then
            table.sort(changed, function(a, b) return a.loc < b.loc end)
            dbot.print(string.format("\n@W-------------------------------------------- Level %3d --------------------------------------------@w", level))
            dbot.print("@WLvl Name of Armor            Type       HR   DR Int Wis Lck Str Dex Con Res HitP Mana Move@w")
            for _, change in ipairs(changed) do
                if change.fromObjId then
                    dbot.print(formatAnalyzeLine(change.fromObjId and level or 0, "<<", change.fromObjId, change.loc))
                end
                if change.toObjId then
                    dbot.print(formatAnalyzeLine(level, ">>", change.toObjId, change.loc))
                end
            end
        end

        prevEquipment = equipment
    end

    return inv.tags.stop(invTagsAnalyze, endTag, DRL_RET_SUCCESS)
end

function inv.analyze.getUpgradeSlotsForLevel(priorityName, level)
    if not priorityName or priorityName == "" then
        return {}
    end

    local analysisData = inv.analyze.table and inv.analyze.table[priorityName]
    local levels = analysisData and analysisData.levels or nil
    local previous = levels and levels[tostring(level - 1)] or nil
    local current = levels and levels[tostring(level)] or nil
    if not previous or not current then
        return {}
    end

    local previousEquipment = previous.equipment or {}
    local currentEquipment = current.equipment or {}
    local upgradeSlots = {}
    local seen = {}

    for loc, currentObjId in pairs(currentEquipment) do
        local previousObjId = previousEquipment[loc]
        if currentObjId and tostring(currentObjId) ~= tostring(previousObjId or "") and not seen[loc] then
            table.insert(upgradeSlots, tostring(loc))
            seen[loc] = true
        end
    end

    table.sort(upgradeSlots)
    return upgradeSlots
end

function inv.analyze.onLevelGained(newLevel)
    local level = tonumber(newLevel)
    if not level or level <= 0 then
        return DRL_RET_SUCCESS
    end

    if inv.analyze.lastAnnouncedLevel and level <= inv.analyze.lastAnnouncedLevel then
        return DRL_RET_SUCCESS
    end

    if not inv.priority or not inv.priority.getDefault then
        return DRL_RET_SUCCESS
    end

    local priorityName = inv.priority.getDefault()
    if not priorityName then
        return DRL_RET_SUCCESS
    end

    local upgradeSlots = inv.analyze.getUpgradeSlotsForLevel(priorityName, level)
    if #upgradeSlots == 0 then
        inv.analyze.lastAnnouncedLevel = level
        return DRL_RET_SUCCESS
    end

    dbot.printRaw(string.format("@c[DINV] You can wear @Y%d@c new equipment piece(s) for priority '@G%s@c'.",
        #upgradeSlots, priorityName))
    inv.analyze.lastAnnouncedLevel = level

    return DRL_RET_SUCCESS
end

function inv.analyze.captureLoginLevel(level)
    local baseLevel = tonumber(level)
    if not baseLevel or baseLevel <= 0 then
        return DRL_RET_SUCCESS
    end

    inv.analyze.lastSeenBaseLevel = baseLevel
    return DRL_RET_SUCCESS
end

function inv.analyze.getCurrentWornByLoc()
    local wornByLoc = {}
    local wearableLocationLookup = {}

    for _, loc in ipairs(inv.set.wearableLocations or {}) do
        wearableLocationLookup[loc] = true
    end

    for objId, _ in pairs(inv.items.table or {}) do
        local location = tostring(inv.items.getStatField(objId, invStatFieldLocation) or "")
        local wornLoc = nil

        if location ~= "" and location ~= invItemLocInventory then
            if wearableLocationLookup[location] then
                wornLoc = location
            else
                local wearLocNum = tonumber(location)
                if wearLocNum ~= nil and inv.items.wearLocById then
                    local mappedLoc = inv.items.wearLocById[wearLocNum]
                    if mappedLoc and mappedLoc ~= "undefined" then
                        wornLoc = mappedLoc
                    end
                end
            end
        end

        if wornLoc then
            wornByLoc[wornLoc] = tostring(objId)
        end
    end

    return wornByLoc
end

function inv.analyze.getLiveUpgradeCount(priorityName, baseLevel, wearableLevel)
    if not priorityName or priorityName == "" then
        return nil, "no priority"
    end

    if not inv.priority or not inv.priority.exists or not inv.priority.exists(priorityName) then
        return nil, "no priority"
    end

    local targetWearableLevel = tonumber(wearableLevel)
    if not targetWearableLevel or targetWearableLevel <= 0 then
        return nil, "invalid wearable level"
    end

    local targetBaseLevel = tonumber(baseLevel) or 1
    inv.set.delete(priorityName, targetWearableLevel)
    local retval = inv.set.create(priorityName, targetWearableLevel, nil, nil, true, targetBaseLevel)
    if retval ~= DRL_RET_SUCCESS then
        return nil, "set create failed"
    end

    local setData = inv.set.table[priorityName] and inv.set.table[priorityName][tostring(targetWearableLevel)]
    if not setData or not setData.equipment then
        return nil, "no generated set"
    end

    local wornByLoc = inv.analyze.getCurrentWornByLoc()
    local changes = 0
    for _, loc in ipairs(inv.set.wearableLocations or {}) do
        local desiredObjId = setData.equipment[loc]
        if desiredObjId then
            local currentObjId = wornByLoc[loc]
            if tostring(desiredObjId) ~= tostring(currentObjId or "") then
                changes = changes + 1
            end
        end
    end

    return changes, nil
end

function inv.analyze.onLevelStatus(currentBaseLevel, forceConfirm)
    local newBase = tonumber(currentBaseLevel)
    if not newBase or newBase <= 0 then
        return DRL_RET_SUCCESS
    end

    local isForcedConfirmation = (forceConfirm == true)
    local debugEnabled = inv.levelup and inv.levelup.getDebug and inv.levelup.getDebug()
    local oldBase = tonumber(inv.analyze.lastSeenBaseLevel)
    if not oldBase then
        if isForcedConfirmation then
            oldBase = math.max(0, newBase - 1)
            if debugEnabled then
                dbot.printRaw(string.format(
                    "@o[DINV DEBUG] Levelup forced-confirmation baseline inferred as @Y%d@o->@Y%d@o.",
                    oldBase, newBase))
            end
        else
            if debugEnabled then
                dbot.printRaw(string.format(
                    "@o[DINV DEBUG] Levelup trigger baseline initialized at base @Y%d@o (waiting for next increase).",
                    newBase))
            end
            inv.analyze.lastSeenBaseLevel = newBase
            return DRL_RET_SUCCESS
        end
    end

    if isForcedConfirmation and inv.analyze.lastAnnouncedLevel and newBase <= inv.analyze.lastAnnouncedLevel then
        if debugEnabled then
            dbot.printRaw(string.format(
                "@o[DINV DEBUG] Levelup forced confirmation ignored for base @Y%d@o (already announced up to @Y%d@o).",
                newBase, tonumber(inv.analyze.lastAnnouncedLevel) or 0))
        end
        inv.analyze.lastSeenBaseLevel = math.max(oldBase, newBase)
        return DRL_RET_SUCCESS
    end

    if isForcedConfirmation and newBase <= oldBase and debugEnabled then
        dbot.printRaw(string.format(
            "@o[DINV DEBUG] Levelup forced confirmation accepted at base @Y%d@o (last seen @Y%d@o).",
            newBase, oldBase))
    end

    if not isForcedConfirmation and newBase <= oldBase then
        return DRL_RET_SUCCESS
    end

    if isForcedConfirmation and newBase <= oldBase then
        oldBase = math.max(0, newBase - 1)
    end

    local mode = (inv.levelup and inv.levelup.getMode and inv.levelup.getMode()) or "cache"
    local wearableLevel = (dbot.gmcp and dbot.gmcp.getWearableLevel and dbot.gmcp.getWearableLevel()) or newBase
    local priorityName = inv.priority and inv.priority.getDefault and inv.priority.getDefault() or nil

    local effectiveMode = mode
    local disabledReason = nil
    local upgradeCount = nil

    if mode == "off" then
        effectiveMode = "off"
        disabledReason = "mode off"
    elseif not priorityName or priorityName == "" then
        effectiveMode = "off"
        disabledReason = "no priority"
    elseif mode == "cache" then
        local analysisData = inv.analyze.table and inv.analyze.table[priorityName]
        local levels = analysisData and analysisData.levels or nil
        if not levels or not levels[tostring(newBase)] or not levels[tostring(newBase - 1)] then
            effectiveMode = "off"
            disabledReason = "no analysis"
        else
            local upgradeSlots = inv.analyze.getUpgradeSlotsForLevel(priorityName, newBase)
            upgradeCount = #upgradeSlots
        end
    elseif mode == "live" then
        upgradeCount, disabledReason = inv.analyze.getLiveUpgradeCount(priorityName, newBase, wearableLevel)
        if upgradeCount == nil then
            effectiveMode = "off"
            upgradeCount = nil
        end
    else
        effectiveMode = "off"
        disabledReason = "invalid mode"
    end

    if effectiveMode ~= "off" and upgradeCount and upgradeCount > 0 then
        dbot.printRaw(string.format(
            "@c[DINV] You can wear @Y%d@c new equipment piece(s) for priority '@G%s@c' (@YL%d@c, @W%s@c).",
            upgradeCount, priorityName, tonumber(wearableLevel) or 0, effectiveMode))
    end

    if debugEnabled then
        local upgradesText = (upgradeCount ~= nil) and tostring(upgradeCount) or "n/a"
        local reasonText = disabledReason and (" (" .. disabledReason .. ")") or ""
        dbot.printRaw(string.format(
            "@o[DINV DEBUG] Levelup trigger: base @Y%d@o->@Y%d@o, wearable @YL%d@o, mode=@W%s@o, effective=@W%s@o%s, upgrades=@Y%s@o, source=@W%s@o.",
            oldBase, newBase, tonumber(wearableLevel) or 0, mode, effectiveMode, reasonText, upgradesText,
            isForcedConfirmation and "text-confirmed" or "gmcp"))
    end

    inv.analyze.lastSeenBaseLevel = newBase
    inv.analyze.lastAnnouncedLevel = newBase
    return DRL_RET_SUCCESS
end

dbot.debug("inv.analyze module loaded", "inv.analyze")
