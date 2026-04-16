----------------------------------------------------------------------------------------------------
-- INV Usage Module
-- Item usage tracking across levels and priorities
----------------------------------------------------------------------------------------------------

inv.usage = {}

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
    formattedName = formattedName .. colorizedId

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
        dbot.print(formattedLevel .. formattedName .. itemType .. " " .. priorityName .. " " .. levelStr)
    end
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
