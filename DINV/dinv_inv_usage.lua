----------------------------------------------------------------------------------------------------
-- INV Usage Module
-- Item usage tracking across levels and priorities
----------------------------------------------------------------------------------------------------

inv.usage = {}
inv.usage.analysisJob = nil

function inv.usage.display(priorityName, query, endTag)
    dbot.info("Displaying usage for priority '" .. priorityName .. "'")
    if priorityName == nil or priorityName == "" then
        dbot.warn("Usage: dinv usage <priority name | all | allUsed> <query>")
        return inv.tags.stop(invTagsUsage, endTag, DRL_RET_INVALID_PARAM)
    end

    local normalizedQuery = tostring(query or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if normalizedQuery:match("^%d+$") then
        normalizedQuery = "id " .. normalizedQuery
    elseif normalizedQuery:match("^id:%d+$") then
        normalizedQuery = normalizedQuery:gsub("^id:", "id ")
    end

    local itemIds, retval = inv.items.search(normalizedQuery)
    if retval ~= DRL_RET_SUCCESS then
        return inv.tags.stop(invTagsUsage, endTag, retval)
    end

    if #itemIds == 0 then
        dbot.info("No items matching '" .. (query or "") .. "' found.")
        return inv.tags.stop(invTagsUsage, endTag, DRL_RET_MISSING_ENTRY)
    end

    local priorities = {}
    if priorityName == "all" or priorityName == "allUsed" then
        for name in pairs(inv.priority.table or {}) do
            table.insert(priorities, name)
        end
    else
        table.insert(priorities, priorityName)
    end

    for _, prio in ipairs(priorities) do
        local analysisData = inv.analyze.table and inv.analyze.table[prio]
        if analysisData and analysisData.levels then
            local fresh, freshRetval = inv.analyze.checkAvailable(prio, "Usage")
            if not fresh then
                return inv.tags.stop(invTagsUsage, endTag, freshRetval)
            end
        end
    end

    local function displayUsage()
        inv.items.sort(itemIds, {
            { field = invStatFieldType, isAscending = true },
            { field = invStatFieldLevel, isAscending = true },
            { field = invStatFieldWearable, isAscending = true },
            { field = invStatFieldName, isAscending = true }
        })

        for _, objId in ipairs(itemIds) do
            local wearableField = inv.items.getStatField(objId, invStatFieldWearable)
            local typeField = inv.items.getStatField(objId, invStatFieldType)

            if wearableField and wearableField ~= "" and wearableField ~= "undefined"
                and tostring(typeField) ~= "Potion"
                and tostring(typeField) ~= "Pill"
                and tostring(typeField) ~= "Food"
                and not (tostring(typeField) == "Treasure" and tostring(wearableField) == "hold") then

                for _, prio in ipairs(priorities) do
                    local doDisplayUnused = (priorityName ~= "allUsed")
                    inv.usage.displayItem(prio, objId, doDisplayUnused)
                end
            end
        end

        return inv.tags.stop(invTagsUsage, endTag, DRL_RET_SUCCESS)
    end

    local pending = 0
    local function onAnalysisComplete()
        pending = pending - 1
        if pending == 0 then
            displayUsage()
        end
    end

    for _, prio in ipairs(priorities) do
        if not inv.analyze.table[prio] or not inv.analyze.table[prio].levels then
            pending = pending + 1
            inv.analyze.create(prio, nil, nil, onAnalysisComplete)
        end
    end

    if pending == 0 then
        return displayUsage()
    end

    dbot.info("Usage analysis requires equipment sets; building analysis now.")
    return DRL_RET_SUCCESS
end

function inv.usage.displayItem(priorityName, objId, doDisplayUnused)
    local colorName = inv.items.getStatField(objId, invStatFieldColorName)
        or inv.items.getStatField(objId, invStatFieldName)
        or "Unknown"
    local maxNameLen = 44

    local formattedId = ""
    local colorizedId = ""
    local idPrefix = DRL_ANSI_WHITE
    local idSuffix = DRL_ANSI_WHITE
    local idLevel = inv.items.getStatField(objId, "identifyLevel")
    if idLevel ~= nil then
        if idLevel == invIdLevelNone or idLevel == invIdLevelSoft then
            idPrefix = DRL_ANSI_RED
        elseif idLevel == invIdLevelPartial then
            idPrefix = DRL_ANSI_YELLOW
        elseif idLevel == invIdLevelFull then
            idPrefix = DRL_ANSI_GREEN
        end

        formattedId = "(" .. objId .. ") "
        colorizedId = idPrefix .. formattedId .. idSuffix
    end

    local formattedName = ""
    local index = 0
    while (#strip_colours(formattedName) < maxNameLen - #formattedId) and (index < 50) do
        formattedName = string.sub(colorName, 1, maxNameLen - #formattedId + index)
        formattedName = string.gsub(formattedName, "%%@", "%%%%@")
        index = index + 1
    end

    if (#strip_colours(formattedName) < maxNameLen - #formattedId) then
        formattedName = formattedName .. string.rep(" ", maxNameLen - #strip_colours(formattedName) - #formattedId)
    end
    formattedName = string.gsub(formattedName, "@$", " ") .. " " .. DRL_ANSI_WHITE

    local levelUsage = inv.usage.get(priorityName, objId)
    local itemLevel = tonumber(inv.items.getStatField(objId, invStatFieldLevel)) or 0
    local itemType = DRL_ANSI_YELLOW .. (inv.items.getStatField(objId, invStatFieldType) or "No Type") ..
                     DRL_ANSI_WHITE
    local levelStr = ""
    local levelPrefix = "@G"
    local levelSuffix = "@W"

    if levelUsage == nil or #levelUsage == 0 then
        levelStr = DRL_ANSI_RED .. "Unused"
        levelPrefix = "@R"
    else
        levelStr = DRL_ANSI_GREEN .. inv.usage.formatLevelRanges(levelUsage)
    end

    if ((levelUsage ~= nil) and (#levelUsage > 0)) or doDisplayUnused then
        local formattedLevel = string.format("%s%3d%s ", levelPrefix, itemLevel, levelSuffix)
        local linePrefix = formattedLevel .. formattedName
        local lineDetails = colorizedId .. itemType .. " " .. priorityName .. " " .. levelStr

        if levelUsage and #levelUsage > 0
            and cecho and cechoLink and dbot and dbot.convertColors then
            local command = string.format(
                "inv.usage.showAnalysis(%q, %q)",
                tostring(priorityName),
                tostring(objId)
            )
            local ranges = inv.usage.formatLevelRanges(levelUsage)
            cecho(dbot.convertColors(linePrefix))
            cechoLink(
                dbot.convertColors(lineDetails),
                command,
                "Show usage analysis for " .. tostring(priorityName) .. " at levels " .. ranges,
                true
            )
            cecho("\n")
        else
            dbot.print(linePrefix .. lineDetails)
        end
    end
end

function inv.usage.showAnalysis(priorityName, objId)
    local pr = tostring(priorityName or "")
    local targetId = tonumber(objId or "")
    if pr == "" or targetId == nil then
        dbot.warn("Usage analysis requires a priority and numeric item ID.")
        return DRL_RET_INVALID_PARAM
    end

    if not inv.set or not inv.set.createPreview
        or not inv.compare or not inv.compare.covetAnalyze then
        dbot.warn("Usage analysis renderer is unavailable.")
        return DRL_RET_MISSING_ENTRY
    end

    local fresh, freshRetval = inv.analyze.checkAvailable(pr, "Usage analysis")
    if not fresh then
        return freshRetval
    end

    local levels, levelsRetval = inv.usage.get(pr, targetId)
    if levelsRetval ~= DRL_RET_SUCCESS or not levels or #levels == 0 then
        dbot.warn("Item " .. tostring(targetId) .. " is unused by priority '" .. pr .. "'.")
        return DRL_RET_MISSING_ENTRY
    end

    if inv.usage.analysisJob then
        dbot.info("A usage analysis is already being built. Please wait for it to complete.")
        return DRL_RET_BUSY
    end

    local targetName = inv.items.getStatField(targetId, invStatFieldColorName)
        or inv.items.getStatField(targetId, invStatFieldName)
        or tostring(targetId)
    local tierBonus = ((dbot.gmcp and dbot.gmcp.getTier and dbot.gmcp.getTier()) or 0) * 10
    local excludedItems = {
        [targetId] = true,
        [tostring(targetId)] = true,
    }
    local comparisonData = {
        levels = {},
        context = inv.context and inv.context.copy
            and inv.context.copy(inv.analyze.table[pr].context)
            or inv.analyze.table[pr].context,
    }
    local job = {
        priorityName = pr,
        targetId = targetId,
        nextIndex = 1,
    }
    inv.usage.analysisJob = job

    dbot.info("Building usage comparison for item " .. tostring(targetId) .. " across "
        .. tostring(#levels) .. " used level" .. (#levels == 1 and "" or "s") .. ".")

    local immediateRetval = DRL_RET_SUCCESS

    local function fail(message, retval)
        if inv.usage.analysisJob == job then
            inv.usage.analysisJob = nil
        end
        dbot.warn(message)
        immediateRetval = retval or DRL_RET_INTERNAL_ERROR
        return immediateRetval
    end

    local function finish()
        if inv.usage.analysisJob ~= job then
            return DRL_RET_BUSY
        end
        inv.usage.analysisJob = nil
        return inv.compare.covetAnalyze(pr, targetId, 1, {
            analysisChecked = true,
            analysisData = comparisonData,
            levels = levels,
            title = "@WUsage Analysis:@w",
            targetLabel = targetName,
            targetReportName = targetName,
            skipTargetHeader = true,
            comparisonSource = "rebuilt owned-equipment sets excluding item " .. tostring(targetId)
                .. " at its used levels for priority '" .. pr .. "'",
        })
    end

    local processBatch
    processBatch = function()
        if inv.usage.analysisJob ~= job then
            return
        end

        local batchEnd = math.min(#levels, job.nextIndex + 4)
        for index = job.nextIndex, batchEnd do
            local baseLevel = levels[index]
            local wearableLevel = baseLevel + tierBonus
            local ok, equipment, _, score, retval = pcall(
                inv.set.createPreview,
                pr,
                wearableLevel,
                excludedItems,
                nil,
                baseLevel
            )
            if not ok then
                fail("Failed to build usage comparison for level " .. tostring(baseLevel) .. ".",
                    DRL_RET_INTERNAL_ERROR)
                return
            end
            if retval ~= DRL_RET_SUCCESS then
                fail("Unable to build usage comparison for level " .. tostring(baseLevel) .. ".", retval)
                return
            end

            comparisonData.levels[tostring(baseLevel)] = {
                equipment = equipment or {},
                score = score or 0,
                wearableLevel = wearableLevel,
            }
        end

        job.nextIndex = batchEnd + 1
        if job.nextIndex <= #levels then
            if tempTimer then
                tempTimer(0.05, processBatch)
            else
                processBatch()
            end
            return
        end

        local ok, retval = pcall(finish)
        if not ok then
            fail("Failed to render usage analysis for item " .. tostring(targetId) .. ".",
                DRL_RET_INTERNAL_ERROR)
        elseif retval ~= nil then
            immediateRetval = retval
        end
    end

    processBatch()
    return immediateRetval
end

function inv.usage.formatLevelRanges(levelUsage)
    if not levelUsage or #levelUsage == 0 then
        return ""
    end

    table.sort(levelUsage)
    local ranges = {}
    local rangeStart = levelUsage[1]
    local rangeEnd = levelUsage[1]

    for i = 2, #levelUsage do
        local level = levelUsage[i]
        if level == rangeEnd + 1 then
            rangeEnd = level
        else
            if rangeStart == rangeEnd then
                table.insert(ranges, tostring(rangeStart))
            else
                table.insert(ranges, rangeStart .. "-" .. rangeEnd)
            end
            rangeStart = level
            rangeEnd = level
        end
    end

    if rangeStart == rangeEnd then
        table.insert(ranges, tostring(rangeStart))
    else
        table.insert(ranges, rangeStart .. "-" .. rangeEnd)
    end

    return table.concat(ranges, " ")
end

function inv.usage.get(priorityName, objId)
    if priorityName == nil then
        dbot.warn("inv.usage.get: priorityName parameter is nil!")
        return nil, DRL_RET_INVALID_PARAM
    end

    objId = tonumber(objId or "")
    if objId == nil then
        dbot.warn("inv.usage.get: objId parameter is not a number")
        return nil, DRL_RET_INVALID_PARAM
    end

    local analysis = inv.analyze.table[priorityName]
    if not analysis or not analysis.levels then
        return {}, DRL_RET_MISSING_ENTRY
    end

    local levelArray = {}
    for level, entry in pairs(analysis.levels or {}) do
        for _, eqId in pairs(entry.equipment or {}) do
            if tonumber(eqId) == objId then
                table.insert(levelArray, tonumber(level))
                break
            end
        end
    end

    table.sort(levelArray)
    return levelArray, DRL_RET_SUCCESS
end

dbot.debug("inv.usage module loaded", "inv.usage")
