----------------------------------------------------------------------------------------------------
-- INV Compare Module
-- Item comparison functionality
----------------------------------------------------------------------------------------------------

inv.compare = {}
inv.compare.covetPkg = inv.compare.covetPkg or nil

local function covetDebugDumpItem(item)
    if not item then
        return "(nil item)"
    end

    local stats = item.stats or {}
    local function f(key)
        local value = stats[key]
        if value == nil then
            return "nil"
        end
        return tostring(value)
    end

    return table.concat({
        "id=" .. f(invStatFieldId),
        "name=" .. f(invStatFieldName),
        "colorName=" .. f(invStatFieldColorName),
        "wearable=" .. f(invStatFieldWearable),
        "type=" .. f(invStatFieldType),
        "level=" .. f(invStatFieldLevel),
        "worth=" .. f(invStatFieldWorth),
        "weight=" .. f(invStatFieldWeight),
        "identifyLevel=" .. f("identifyLevel"),
    }, ", ")
end

local function covetCleanup(removeTemp)
    local pkg = inv.compare.covetPkg
    if not pkg then
        return
    end

    if pkg.fenceTriggerId and killTrigger then
        pcall(killTrigger, pkg.fenceTriggerId)
    end
    if pkg.collectTriggerId and killTrigger then
        pcall(killTrigger, pkg.collectTriggerId)
    end
    if pkg.timeoutTimerId and killTimer then
        pcall(killTimer, pkg.timeoutTimerId)
    end

    if inv.items then
        inv.items.inIdentify = false
        inv.items.identifyActive = false
        inv.items.identifyObjId = nil
        inv.items.currentIdentifyId = nil
        inv.items.identifyResetId = nil
    end

    if removeTemp and pkg.addedTempItem and inv.items and inv.items.removeItem then
        local item = inv.items.getItem and inv.items.getItem(pkg.objId) or nil
        if inv.items.removeItemFromCache then
            inv.items.removeItemFromCache(pkg.objId, item)
        end
        inv.items.removeItem(pkg.objId)
    end

    inv.compare.covetPkg = nil
end

function inv.compare._covetFinishFromMarket()
    local pkg = inv.compare.covetPkg
    if not pkg then
        return DRL_RET_SUCCESS
    end

    local item = inv.items.getItem and inv.items.getItem(pkg.objId) or nil
    local itemName = item and item.stats and item.stats[invStatFieldName] or nil
    if item and item.stats then
        inv.items.setItem(pkg.objId, item)
    end

    if not itemName or itemName == "" then
        dbot.warn("Failed to parse market item details for #" .. tostring(pkg.auctionNum))
        dbot.debug("covet parse failure dump: " .. covetDebugDumpItem(item), "inv.compare")

        if inv.items and inv.items.getItem then
            local stored = inv.items.getItem(pkg.objId)
            dbot.debug("covet parse failure stored item: " .. covetDebugDumpItem(stored), "inv.compare")
        end

        if inv.items and inv.items.currentIdentifyId then
            dbot.debug("covet parse failure identify state: currentIdentifyId=" .. tostring(inv.items.currentIdentifyId) ..
                ", identifyObjId=" .. tostring(inv.items.identifyObjId) ..
                ", inIdentify=" .. tostring(inv.items.inIdentify) ..
                ", identifyActive=" .. tostring(inv.items.identifyActive), "inv.compare")
        end

        if gmcp and gmcp.comm and gmcp.comm.channel then
            dbot.debug("covet parse failure gmcp.comm.channel.chan=" .. tostring(gmcp.comm.channel.chan) ..
                ", msg=" .. tostring(gmcp.comm.channel.msg), "inv.compare")
        end

        covetCleanup(true)
        return inv.tags.stop(invTagsCovet, pkg.endTag, DRL_RET_MISSING_ENTRY)
    end

    dbot.info("Evaluating market item '#" .. tostring(pkg.auctionNum) .. "' against analyzed level sets.")
    inv.compare.covetAnalyze(pkg.priorityName, pkg.objId, pkg.skipLevels)
    covetCleanup(true)
    return inv.tags.stop(invTagsCovet, pkg.endTag, DRL_RET_SUCCESS)
end

function inv.compare._expandWearLocations(itemId)
    local wearable = tostring(inv.items.getStatField(itemId, invStatFieldWearable) or "")
    local aliasToSetLoc = {
        ear1 = "lear",
        ear2 = "rear",
        wrist1 = "lwrist",
        wrist2 = "rwrist",
        finger1 = "lfinger",
        finger2 = "rfinger",
        wield = "wielded",
    }

    local function normalizeLoc(token)
        token = tostring(token or ""):lower():gsub("[^%a%d]", "")
        if token == "" then
            return nil
        end

        if inv.set and inv.set.wearLocMap and inv.set.wearLocMap[token] then
            return tostring(inv.set.wearLocMap[token])
        end

        if aliasToSetLoc[token] then
            return aliasToSetLoc[token]
        end

        return token
    end

    local locs = {}
    for token in wearable:gmatch("%S+") do
        if inv.items.isWearableLoc(token) then
            local mapped = normalizeLoc(token)
            if mapped then
                locs[mapped] = true
            end
        elseif inv.items.isWearableType(token) then
            local mapped = tostring(inv.items.wearableTypeToLocs(token) or "")
            for loc in mapped:gmatch("%S+") do
                local normalized = normalizeLoc(loc)
                if normalized then
                    locs[normalized] = true
                end
            end
        else
            local mapped = normalizeLoc(token)
            if mapped then
                locs[mapped] = true
            end
        end
    end

    if next(locs) == nil and wearable ~= "" then
        dbot.debug("covet: unable to map wearable string to set locations: '" .. wearable .. "'", "inv.compare")
    end

    return locs
end

local covetWeightedStats = {
    { key = "str", field = invStatFieldStr },
    { key = "int", field = invStatFieldInt },
    { key = "wis", field = invStatFieldWis },
    { key = "dex", field = invStatFieldDex },
    { key = "con", field = invStatFieldCon },
    { key = "luck", field = invStatFieldLuck },
    { key = "hit", field = invStatFieldHitroll },
    { key = "dam", field = invStatFieldDamroll },
    { key = "hp", field = invStatFieldHp },
    { key = "mana", field = invStatFieldMana },
    { key = "moves", field = invStatFieldMoves },
    { key = "allphys", field = invStatFieldAllPhys },
    { key = "allmagic", field = invStatFieldAllMagic },
    { key = "avedam", field = invStatFieldAveDam },
}

local covetReadableStatNames = {
    str = "str",
    int = "int",
    wis = "wis",
    dex = "dex",
    con = "con",
    luck = "luck",
    hit = "hitroll",
    dam = "damroll",
    hp = "hp",
    mana = "mana",
    moves = "moves",
    allphys = "allphys",
    allmagic = "allmagic",
    avedam = "avedam",
}

local function covetBuildWeightedDiff(targetId, wornId, priorityName, level)
    local priority = inv.priority and inv.priority.get and inv.priority.get(priorityName, level) or nil
    if not priority then
        return "", {}, ""
    end

    local weighted = {}
    local ignored = {}
    for _, spec in ipairs(covetWeightedStats) do
        local targetValue = tonumber(inv.items.getStatField(targetId, spec.field)) or 0
        local wornValue = tonumber(inv.items.getStatField(wornId, spec.field)) or 0
        local rawDiff = targetValue - wornValue
        if rawDiff ~= 0 then
            local weight = inv.score.getWeight(priority, spec.key, level)
            local weightedDiff = rawDiff * weight
            if weightedDiff ~= 0 then
                table.insert(weighted, {
                    key = spec.key,
                    rawDiff = rawDiff,
                    weight = weight,
                    weightedDiff = weightedDiff,
                })
            else
                table.insert(ignored, {
                    key = spec.key,
                    rawDiff = rawDiff,
                    weight = weight,
                })
            end
        end
    end

    table.sort(weighted, function(a, b)
        return math.abs(a.weightedDiff) > math.abs(b.weightedDiff)
    end)

    local parts = {}
    for i = 1, math.min(3, #weighted) do
        local w = weighted[i]
        table.insert(parts, string.format("%s %+d (w %.2f => %+0.1f)",
            w.key, w.rawDiff, w.weight, w.weightedDiff))
    end

    local ignoredParts = {}
    for i = 1, math.min(3, #ignored) do
        local stat = ignored[i]
        table.insert(ignoredParts, string.format("%s %+d (w %.2f)",
            covetReadableStatNames[stat.key] or stat.key,
            stat.rawDiff,
            stat.weight))
    end

    return table.concat(parts, ", "), weighted, table.concat(ignoredParts, ", ")
end

function inv.compare.covetAnalyze(priorityName, targetId, skipLevels)
    local analysisData = inv.analyze and inv.analyze.table and inv.analyze.table[priorityName] or nil
    if not analysisData or not analysisData.levels then
        dbot.warn("Covet requires analysis data. Run 'dinv analyze create " .. priorityName .. "' first.")
        return DRL_RET_MISSING_ENTRY
    end

    local itemLevel = tonumber(inv.items.getStatField(targetId, invStatFieldLevel)) or 1
    local tierBonus = ((dbot.gmcp and dbot.gmcp.getTier and dbot.gmcp.getTier()) or 0) * 10
    local minLevel = math.max(1, itemLevel - tierBonus)
    local maxLevel = 201
    local skip = tonumber(skipLevels) or 1
    if skip < 1 then
        skip = 1
    end

    local targetName = inv.items.getStatField(targetId, invStatFieldName) or ("Auction #" .. tostring(targetId))
    local targetLocs = inv.compare._expandWearLocations(targetId)
    do
        local locList = {}
        for loc in pairs(targetLocs) do
            table.insert(locList, loc)
        end
        table.sort(locList)
        dbot.debug("covet target wearable='" .. tostring(inv.items.getStatField(targetId, invStatFieldWearable) or "") ..
            "' mappedLocs='" .. table.concat(locList, " ") .. "'", "inv.compare")
    end
    local found = false
    local rows = {}

    local function setStat(stats, key)
        return tonumber(stats and stats[key]) or 0
    end

    local function calcSetDelta(baseSet, candidateSet, level)
        local effectiveLevel = (tonumber(level) or 1) + tierBonus
        local baseScore, baseStats = inv.score.set(baseSet, priorityName, effectiveLevel)
        local candScore, candStats = inv.score.set(candidateSet, priorityName, effectiveLevel)
        return {
            scoreDelta = (tonumber(candScore) or 0) - (tonumber(baseScore) or 0),
            ave = setStat(candStats, "avedam") - setStat(baseStats, "avedam"),
            sec = setStat(candStats, "offhandDam") - setStat(baseStats, "offhandDam"),
            hr = setStat(candStats, "hit") - setStat(baseStats, "hit"),
            dr = setStat(candStats, "dam") - setStat(baseStats, "dam"),
            str = setStat(candStats, "str") - setStat(baseStats, "str"),
            int = setStat(candStats, "int") - setStat(baseStats, "int"),
            wis = setStat(candStats, "wis") - setStat(baseStats, "wis"),
            dex = setStat(candStats, "dex") - setStat(baseStats, "dex"),
            con = setStat(candStats, "con") - setStat(baseStats, "con"),
            lck = setStat(candStats, "luck") - setStat(baseStats, "luck"),
            res = setStat(candStats, "allphys") - setStat(baseStats, "allphys"),
            hp = setStat(candStats, "hp") - setStat(baseStats, "hp"),
            mana = setStat(candStats, "mana") - setStat(baseStats, "mana"),
            move = setStat(candStats, "moves") - setStat(baseStats, "moves"),
            effects = 0,
        }
    end

    local function calcItemDelta(targetObjId, wornObjId, level)
        local effectiveLevel = (tonumber(level) or 1) + tierBonus
        local targetScore = inv.score.getItemScore(targetObjId, priorityName, effectiveLevel)
        local wornScore = inv.score.getItemScore(wornObjId, priorityName, effectiveLevel)
        return (tonumber(targetScore) or 0) - (tonumber(wornScore) or 0)
    end

    local function roundInt(v)
        local n = tonumber(v) or 0
        if n >= 0 then
            return math.floor(n + 0.5)
        end
        return math.ceil(n - 0.5)
    end

    local function visibleLen(text)
        local s = tostring(text or "")
        s = s:gsub("@x%d+", "")
        s = s:gsub("@.", "")
        return #s
    end

    local function padCell(value, width, align)
        local s = tostring(value or "")
        local w = tonumber(width) or 0
        local len = visibleLen(s)
        local pad = math.max(0, w - len)
        if align == "right" then
            return string.rep(" ", pad) .. s
        end
        return s .. string.rep(" ", pad)
    end

    local function colorizeDelta(v)
        local n = roundInt(v)
        if n > 0 then
            return "@G" .. tostring(n) .. "@w"
        end
        if n < 0 then
            return "@R" .. tostring(n) .. "@w"
        end
        return "@D0@w"
    end

    local function colorizeStat(v)
        local n = roundInt(v)
        if n == 0 then
            return "@D0@w"
        end
        return "@G" .. tostring(n) .. "@w"
    end

    for level = minLevel, maxLevel, skip do
        local entry = analysisData.levels[tostring(level)]
        if entry and entry.equipment then
            local bestDelta = nil
            local bestLoc = nil
            local bestAgainstId = nil
            local bestDiff = nil

            for loc, _ in pairs(targetLocs) do
                local wornId = tonumber(entry.equipment[loc])
                if wornId then
                    local itemDelta = calcItemDelta(targetId, wornId, level)
                    if itemDelta <= 0 then
                        dbot.debug(string.format("covet L%d [%s] target item score not improved vs worn item (delta=%0.2f)",
                            level,
                            tostring(loc),
                            itemDelta), "inv.compare")
                    else
                        local baseSet = {}
                        local candidateSet = {}
                        for slot, equippedId in pairs(entry.equipment or {}) do
                            baseSet[slot] = tonumber(equippedId)
                            candidateSet[slot] = tonumber(equippedId)
                        end
                        candidateSet[loc] = tonumber(targetId)

                        local diff = calcSetDelta(baseSet, candidateSet, level)
                        local delta = diff.scoreDelta
                        if bestDelta == nil or delta > bestDelta then
                            bestDelta = delta
                            bestLoc = loc
                            bestAgainstId = wornId
                            bestDiff = diff
                        end
                    end
                end
            end

            if bestDelta and bestAgainstId then
                local againstName = inv.items.getStatField(bestAgainstId, invStatFieldName) or tostring(bestAgainstId)
                dbot.debug(string.format("covet L%d [%s] target=%s vs %s delta=%0.2f",
                    level,
                    tostring(bestLoc),
                    tostring(targetName),
                    tostring(againstName),
                    bestDelta), "inv.compare")
            end

            if bestDelta and bestDelta > 0 then
                found = true
                local row = {
                    level = level,
                    loc = bestLoc,
                    againstId = bestAgainstId,
                    againstName = inv.items.getStatField(bestAgainstId, invStatFieldName) or tostring(bestAgainstId),
                    diff = bestDiff,
                }
                table.insert(rows, row)
            end
        end
    end

    dbot.print("@WCovet Results:@w")
    dbot.print("  @CTarget@W: " .. targetName .. " @Y(level " .. tostring(itemLevel) .. ")@w")
    dbot.print("  @CComparison source@W: analyzed equipment snapshots for priority '" .. tostring(priorityName) .. "' only")
    dbot.print("")
    local topColumns = {
        { title = "Lvl", key = "lvl", width = 3, align = "right" },
        { title = "Name of Armor", key = "name", width = 24, align = "left" },
        { title = "Type", key = "type", width = 10, align = "left" },
        { title = "HR", key = "hr", width = 4, align = "right" },
        { title = "DR", key = "dr", width = 4, align = "right" },
        { title = "Int", key = "int", width = 3, align = "right" },
        { title = "Wis", key = "wis", width = 3, align = "right" },
        { title = "Lck", key = "lck", width = 3, align = "right" },
        { title = "Str", key = "str", width = 3, align = "right" },
        { title = "Dex", key = "dex", width = 3, align = "right" },
        { title = "Con", key = "con", width = 3, align = "right" },
        { title = "Res", key = "res", width = 3, align = "right" },
        { title = "HitP", key = "hp", width = 5, align = "right" },
        { title = "Mana", key = "mana", width = 5, align = "right" },
        { title = "Move", key = "move", width = 5, align = "right" },
    }
    local function renderHeader(columns)
        local parts = {}
        for i, col in ipairs(columns) do
            table.insert(parts, padCell("@W" .. col.title .. "@w", col.width, col.align))
            if i < #columns then
                table.insert(parts, " ")
            end
        end
        return table.concat(parts, "")
    end

    dbot.print(renderHeader(topColumns))
    local targetLoc = "item"
    do
        local targetLocList = {}
        for loc in pairs(targetLocs) do
            table.insert(targetLocList, tostring(loc))
        end
        table.sort(targetLocList)
        if #targetLocList > 0 then
            targetLoc = targetLocList[1]
        end
    end
    local auctionRow = {
        lvl = tostring(itemLevel),
        name = "@GAuction #" .. tostring(targetId) .. "@w",
        type = "@C" .. tostring(targetLoc) .. "@w",
        hr = colorizeStat(inv.items.getStatField(targetId, invStatFieldHitroll)),
        dr = colorizeStat(inv.items.getStatField(targetId, invStatFieldDamroll)),
        int = colorizeStat(inv.items.getStatField(targetId, invStatFieldInt)),
        wis = colorizeStat(inv.items.getStatField(targetId, invStatFieldWis)),
        lck = colorizeStat(inv.items.getStatField(targetId, invStatFieldLuck)),
        str = colorizeStat(inv.items.getStatField(targetId, invStatFieldStr)),
        dex = colorizeStat(inv.items.getStatField(targetId, invStatFieldDex)),
        con = colorizeStat(inv.items.getStatField(targetId, invStatFieldCon)),
        res = colorizeStat(inv.items.getStatField(targetId, invStatFieldAllPhys)),
        hp = colorizeStat(inv.items.getStatField(targetId, invStatFieldHp)),
        mana = colorizeStat(inv.items.getStatField(targetId, invStatFieldMana)),
        move = colorizeStat(inv.items.getStatField(targetId, invStatFieldMoves)),
    }

    local function renderRow(columns, row)
        local parts = {}
        for i, col in ipairs(columns) do
            table.insert(parts, padCell(row[col.key] or "", col.width, col.align))
            if i < #columns then
                table.insert(parts, " ")
            end
        end
        return table.concat(parts, "")
    end

    dbot.print(renderRow(topColumns, auctionRow))
    if not found then
        dbot.print("  @YNo upgrades found in analyzed levels " .. minLevel .. "-" .. maxLevel .. ".@w")
        return DRL_RET_SUCCESS
    end

    dbot.print("")
    dbot.print("@WPriority '" .. tostring(priorityName) .. "' advantages with auction #" .. tostring(targetId) .. ":@w")
    local advColumns = {
        { title = "", key = "prefix", width = 10, align = "left" },
        { title = "Ave", key = "ave", width = 5, align = "right" },
        { title = "Sec", key = "sec", width = 5, align = "right" },
        { title = "HR", key = "hr", width = 4, align = "right" },
        { title = "DR", key = "dr", width = 4, align = "right" },
        { title = "Str", key = "str", width = 4, align = "right" },
        { title = "Int", key = "int", width = 4, align = "right" },
        { title = "Wis", key = "wis", width = 4, align = "right" },
        { title = "Dex", key = "dex", width = 4, align = "right" },
        { title = "Con", key = "con", width = 4, align = "right" },
        { title = "Lck", key = "lck", width = 4, align = "right" },
        { title = "Res", key = "res", width = 4, align = "right" },
        { title = "HitP", key = "hp", width = 5, align = "right" },
        { title = "Mana", key = "mana", width = 5, align = "right" },
        { title = "Move", key = "move", width = 5, align = "right" },
        { title = "Effects", key = "effects", width = 7, align = "right" },
    }
    dbot.print(renderHeader(advColumns))
    for _, row in ipairs(rows) do
        local d = row.diff or {}
        local advRow = {
            prefix = string.format("@WLevel %3d:@w", row.level),
            ave = colorizeDelta(d.ave),
            sec = colorizeDelta(d.sec),
            hr = colorizeDelta(d.hr),
            dr = colorizeDelta(d.dr),
            str = colorizeDelta(d.str),
            int = colorizeDelta(d.int),
            wis = colorizeDelta(d.wis),
            dex = colorizeDelta(d.dex),
            con = colorizeDelta(d.con),
            lck = colorizeDelta(d.lck),
            res = colorizeDelta(d.res),
            hp = colorizeDelta(d.hp),
            mana = colorizeDelta(d.mana),
            move = colorizeDelta(d.move),
            effects = colorizeDelta(d.effects),
        }
        dbot.print(renderRow(advColumns, advRow))
    end

    return DRL_RET_SUCCESS
end

function inv.compare.items(priorityName, itemName, skipLevels, endTag)
    dbot.info("Comparing items for priority '" .. priorityName .. "'")
    if not inv.priority.exists(priorityName) then
        dbot.warn("Priority '" .. priorityName .. "' does not exist")
        return inv.tags.stop(invTagsCompare, endTag, DRL_RET_MISSING_ENTRY)
    end

    local itemIds, retval = inv.items.search(itemName or "")
    if retval ~= DRL_RET_SUCCESS then
        return inv.tags.stop(invTagsCompare, endTag, retval)
    end

    if #itemIds == 0 then
        dbot.warn("No items found matching '" .. (itemName or "") .. "'")
        return inv.tags.stop(invTagsCompare, endTag, DRL_RET_MISSING_ENTRY)
    end

    if #itemIds > 2 then
        dbot.warn("Multiple items matched; refine your query.")
        inv.items.displayResults(itemIds, "basic")
        return inv.tags.stop(invTagsCompare, endTag, DRL_RET_BUSY)
    end

    local targetId = itemIds[1]
    local compareId = itemIds[2]
    local targetWear = inv.items.getStatField(targetId, invStatFieldWearable) or ""
    local targetScore = inv.score.getItemScore(targetId, priorityName, nil)

    local wornId = compareId
    if not wornId then
        for objId, _ in pairs(inv.items.table or {}) do
            local wornLoc = inv.items.getStatField(objId, invStatFieldWorn)
            if wornLoc and wornLoc ~= "" and string.find(targetWear, wornLoc, 1, true) then
                wornId = objId
                break
            end
        end
    end

    dbot.print("@WCompare Results:@w")
    dbot.print("  @CTarget@W: " .. (inv.items.getStatField(targetId, invStatFieldName) or "Unknown") ..
               " @Y(score " .. targetScore .. ")@w")

    if wornId then
        local wornScore = inv.score.getItemScore(wornId, priorityName, nil)
        dbot.print("  @CCompare@W: " .. (inv.items.getStatField(wornId, invStatFieldName) or "Unknown") ..
                   " @Y(score " .. wornScore .. ")@w")
        dbot.print("  @CDelta@W: " .. tostring(targetScore - wornScore))
    else
        dbot.print("  @YNo comparison item detected for this slot.@w")
    end

    return inv.tags.stop(invTagsCompare, endTag, DRL_RET_SUCCESS)
end

function inv.compare.covet(priorityName, auctionNum, skipLevels, endTag)
    dbot.info("Analyzing auction item " .. tostring(auctionNum) .. " for priority '" .. tostring(priorityName) .. "'")

    if not priorityName or priorityName == "" then
        dbot.warn("inv.compare.covet: missing priority name")
        return inv.tags.stop(invTagsCovet, endTag, DRL_RET_INVALID_PARAM)
    end

    if not inv.priority.exists(priorityName) then
        dbot.warn("Priority '" .. priorityName .. "' does not exist")
        return inv.tags.stop(invTagsCovet, endTag, DRL_RET_MISSING_ENTRY)
    end

    local objId = tonumber(auctionNum)
    if not objId then
        dbot.warn("inv.compare.covet: auction # must be numeric")
        return inv.tags.stop(invTagsCovet, endTag, DRL_RET_INVALID_PARAM)
    end

    local cachedItem = inv.items.getItem(objId)
    if cachedItem then
        dbot.info("Auction #" .. objId .. " is already in memory; evaluating against analyzed level sets.")
        inv.compare.covetAnalyze(priorityName, objId, skipLevels)
        return inv.tags.stop(invTagsCovet, endTag, DRL_RET_SUCCESS)
    end

    if inv.compare.covetPkg then
        dbot.info("A covet market scrape is already in progress. Please wait for it to complete.")
        return inv.tags.stop(invTagsCovet, endTag, DRL_RET_BUSY)
    end

    local threshold = 1000
    local marketCmd = (objId < threshold) and "bid " or "lbid "
    local fence = "DINV covet fence " .. tostring(objId) .. " " .. tostring(os.time())

    inv.items.setItem(objId, { stats = { [invStatFieldId] = tostring(objId), identifyLevel = invIdLevelNone } })
    inv.compare.covetPkg = {
        priorityName = priorityName,
        auctionNum = objId,
        objId = objId,
        skipLevels = tonumber(skipLevels) or 1,
        endTag = endTag,
        fence = fence,
        addedTempItem = true,
    }

    inv.items.inIdentify = true
    inv.items.identifyActive = true
    inv.items.identifyObjId = objId
    inv.items.currentIdentifyId = objId
    inv.items.identifyResetId = nil

    if tempRegexTrigger then
        inv.compare.covetPkg.collectTriggerId = tempRegexTrigger("^(.*)$", function()
            if not inv.compare.covetPkg then
                return
            end
            if not matches or not matches[2] then
                return
            end
            inv.items.currentIdentifyId = objId
            inv.items.onIdentifyLine(matches[2])
        end)
    end

    if tempRegexTrigger then
        -- Use a regex trigger with leading/trailing whitespace tolerance.
        -- Aardwolf's `echo` command prefixes the echoed text with a space,
        -- which would break a strict tempExactMatchTrigger on the fence.
        local fencePattern = "^\\s*" .. fence:gsub("([^%w%s])", "\\%1") .. "\\s*$"
        inv.compare.covetPkg.fenceTriggerId = tempRegexTrigger(fencePattern, function()
            if tempTimer then
                tempTimer(0.05, function()
                    inv.compare._covetFinishFromMarket()
                end)
            else
                inv.compare._covetFinishFromMarket()
            end
        end)
    end

    if tempTimer then
        inv.compare.covetPkg.timeoutTimerId = tempTimer(12, function()
            if inv.compare.covetPkg then
                dbot.warn("Timed out waiting for market identify output for auction #" .. tostring(objId))
                covetCleanup(true)
                inv.tags.stop(invTagsCovet, endTag, DRL_RET_TIMEOUT)
            end
        end)
    end

    dbot.info("Scraping market item #" .. tostring(objId) .. " via '" .. marketCmd:gsub("%s+$", "") .. "'.")
    dbot.debug("covet: temporary collect trigger active for lbid lines", "inv.compare")
    if sendSilent then
        sendSilent(marketCmd .. tostring(objId))
        sendSilent("echo " .. fence)
    else
        send(marketCmd .. tostring(objId))
        send("echo " .. fence)
    end
    return DRL_RET_SUCCESS

end

dbot.debug("inv.compare module loaded", "inv.compare")
