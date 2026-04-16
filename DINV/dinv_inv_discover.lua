----------------------------------------------------------------------------------------------------
-- DINV Discover Module
-- Market scanner + priority-weighted scoring against analyzed sets
----------------------------------------------------------------------------------------------------

inv.discover = inv.discover or {}
inv.discover.init = inv.discover.init or {}
inv.discover.state = inv.discover.state or {
    marketType = "",
    busy = false,
    currentNum = nil,
    listBuffering = false,
    itemBuffering = false,
    inStats = false,
    inResists = false,
    pendingNums = {},
    collected = {},
    itemWork = nil,
    triggers = {},
    eligiblePriorities = {},
    priorityFilter = nil,
    cachedResults = {},
    cachedAt = nil,
    itemCache = {},
    parsedCount = 0,
    totalToInspect = 0,
    scoreProgressStep = 10,
}

inv.cli.discover = inv.cli.discover or {}

local function trim(s)
    return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function lower(s)
    return string.lower(tostring(s or ""))
end

local function push(t, value)
    t[#t + 1] = value
end

local function popFront(t)
    if #t == 0 then
        return nil
    end
    local v = t[1]
    table.remove(t, 1)
    return v
end

local function stripBorder(text)
    local s = trim(text)
    s = s:gsub("%s*|%s*$", "")
    return trim(s)
end

local function roundInt(v)
    local n = tonumber(v) or 0
    if n >= 0 then
        return math.floor(n + 0.5)
    end
    return math.ceil(n - 0.5)
end

local function hasAnyAnalysis()
    for name, data in pairs((inv.analyze and inv.analyze.table) or {}) do
        if name and data and data.levels and next(data.levels) then
            return true
        end
    end
    return false
end

local function mapStatKey(rawKey)
    local key = lower(trim(rawKey))
    key = key:gsub("%s+", " ")
    local map = {
        ["strength"] = invStatFieldStr,
        ["str"] = invStatFieldStr,
        ["intelligence"] = invStatFieldInt,
        ["int"] = invStatFieldInt,
        ["wisdom"] = invStatFieldWis,
        ["wis"] = invStatFieldWis,
        ["dexterity"] = invStatFieldDex,
        ["dex"] = invStatFieldDex,
        ["constitution"] = invStatFieldCon,
        ["con"] = invStatFieldCon,
        ["luck"] = invStatFieldLuck,
        ["hitroll"] = invStatFieldHitroll,
        ["damroll"] = invStatFieldDamroll,
        ["hit points"] = invStatFieldHp,
        ["hp"] = invStatFieldHp,
        ["mana"] = invStatFieldMana,
        ["moves"] = invStatFieldMoves,
        ["move"] = invStatFieldMoves,
        ["average dam"] = invStatFieldAveDam,
        ["all physical"] = invStatFieldAllPhys,
        ["allphys"] = invStatFieldAllPhys,
        ["all magic"] = invStatFieldAllMagic,
        ["allmagic"] = invStatFieldAllMagic,
    }
    return map[key], key
end

local function parsePairsInto(dest, text)
    if not text or text == "" then
        return
    end
    for key, value in string.gmatch(text, "([A-Za-z][A-Za-z %/%-]+)%s*:%s*([+%-]?%d+)") do
        local k = trim(key)
        local v = tonumber(value) or 0
        local mapped = mapStatKey(k)
        if mapped then
            dest[mapped] = v
        else
            dest[lower(k)] = v
        end
    end
end

local function unregisterTriggers()
    local st = inv.discover.state
    for _, id in pairs(st.triggers or {}) do
        if id and killTrigger then
            killTrigger(id)
        end
    end
    st.triggers = {}
end

local clearTempIdentifyParse

local function clearRuntime(keepCache)
    local st = inv.discover.state
    if st.currentNum then
        clearTempIdentifyParse(st.currentNum)
    end
    st.busy = false
    st.currentNum = nil
    st.listBuffering = false
    st.itemBuffering = false
    st.inStats = false
    st.inResists = false
    st.pendingNums = {}
    st.collected = {}
    st.itemWork = nil
    st.eligiblePriorities = {}
    st.priorityFilter = nil
    if not keepCache then
        st.cachedResults = {}
        st.cachedAt = nil
        st.itemCache = {}
    end
    unregisterTriggers()
end

local function cechoDiscoverPrefix()
    if cecho then
        cecho("<cyan>[dinv - scan]<reset> ")
    end
end

local function info(message)
	cechoDiscoverPrefix()
    if cecho then
        cecho("<white>" .. tostring(message) .. "<reset>\n")
    else
        dbot.info("[dinv - scan] " .. tostring(message))
    end
end

local function infoProgress(message)
    if cecho then
        cecho("<cyan>[dinv - scan]<reset><white>" .. tostring(message) .. "<reset>\n\n")
    else
        dbot.info("[dinv - scan] " .. tostring(message))
    end
end

local function warn(message)
    if dbot and dbot.warn then
        dbot.warn(message)
    else
        cecho("<yellow>[DINV] " .. tostring(message) .. "\n")
    end
end

local function debug(message)
    if dbot and dbot.debug then
        dbot.debug(tostring(message), "inv.discover")
    end
end

local function copyTable(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = copyTable(v)
    end
    return out
end

local function sendSilentCommand(cmd)
    if sendSilent then
        sendSilent(cmd)
    else
        send(cmd)
    end
end

local function beginTempIdentifyParse(objId)
    if not objId then
        return
    end

    local idNum = tonumber(objId) or objId
    inv.items.currentIdentifyId = idNum
    inv.items.identifyResetId = nil
    inv.items.setItem(idNum, {
        stats = {
            [invStatFieldId] = tostring(objId),
        },
    })
end

local function readTempIdentifyParse(objId)
    if not objId then
        return nil
    end

    local idNum = tonumber(objId) or objId
    local parsed = inv.items.getItem(idNum)
    if not parsed then
        return nil
    end
    return copyTable(parsed)
end

clearTempIdentifyParse = function(objId)
    if not objId then
        return
    end

    local idNum = tonumber(objId) or objId
    inv.items.removeItem(idNum)
    if inv.items.currentIdentifyId == idNum then
        inv.items.currentIdentifyId = nil
    end
    if inv.items.identifyResetId == idNum then
        inv.items.identifyResetId = nil
    end
end

local function discoverEligiblePriorities(priorityFilter)
    local out = {}
    local tableData = (inv.analyze and inv.analyze.table) or {}

    if priorityFilter and priorityFilter ~= "" then
        local data = tableData[priorityFilter]
        if data and data.levels and next(data.levels) then
            out[#out + 1] = priorityFilter
            return out, DRL_RET_SUCCESS
        end
        return out, DRL_RET_MISSING_ENTRY
    end

    for priorityName, data in pairs(tableData) do
        if data and data.levels and next(data.levels) then
            out[#out + 1] = priorityName
        end
    end
    table.sort(out)
    return out, DRL_RET_SUCCESS
end

local function emitScoredRow(entry)
    local summaryParts = {}
    for _, priorityName in ipairs(entry.betterFor or {}) do
        local priorityScore = roundInt((entry.priorityScores or {})[priorityName] or 0)
        local levelRange = (entry.priorityLevelRanges or {})[priorityName]
        if levelRange and levelRange ~= "" then
            summaryParts[#summaryParts + 1] = string.format("%s (%+d @ %s)", tostring(priorityName), priorityScore, levelRange)
        else
            summaryParts[#summaryParts + 1] = string.format("%s (%+d)", tostring(priorityName), priorityScore)
        end
    end
    local summary = (#summaryParts > 0) and table.concat(summaryParts, " / ") or "-"
    if cecho and cechoLink then
        cecho("<cyan>[<reset>")
        cechoLink("<yellow>" .. tostring(entry.num) .. "<reset>", "send([[lbid " .. tostring(entry.num) .. "]])", "Run: lbid " .. tostring(entry.num), true)
        cecho("<cyan>]<reset> ")
        cecho("<white>" .. tostring(entry.name) .. "<reset> ")
        cecho("<magenta>" .. summary .. "<reset>\n")
    else
        dbot.print(string.format("@C[%s]@w %s @M%s@w", tostring(entry.num), tostring(entry.name), summary))
    end
end

local function formatLevelRanges(levels)
    if not levels or #levels == 0 then
        return ""
    end

    local ordered = {}
    local seen = {}
    for _, lvl in ipairs(levels) do
        local n = tonumber(lvl)
        if n and not seen[n] then
            seen[n] = true
            ordered[#ordered + 1] = n
        end
    end

    if #ordered == 0 then
        return ""
    end

    table.sort(ordered)
    local parts = {}
    local startLevel = ordered[1]
    local prevLevel = ordered[1]

    local function flushRange()
        if startLevel == prevLevel then
            parts[#parts + 1] = tostring(startLevel)
        else
            parts[#parts + 1] = string.format("%d-%d", startLevel, prevLevel)
        end
    end

    for i = 2, #ordered do
        local n = ordered[i]
        if n == prevLevel + 1 then
            prevLevel = n
        else
            flushRange()
            startLevel = n
            prevLevel = n
        end
    end
    flushRange()

    return table.concat(parts, ",")
end

local function getItemLevelForScore(item)
    local level = tonumber(item.level) or tonumber(item.list_level) or 1
    if level < 1 then
        level = 1
    end
    return level
end

local function buildTemporaryItem(item)
    local objId = tostring(item.num)
    local previous = inv.items.getItem(objId)
    local stats = {}

    stats[invStatFieldId] = objId
    stats[invStatFieldName] = item.name or item.desc or ("Auction #" .. objId)
    stats[invStatFieldLevel] = getItemLevelForScore(item)
    stats[invStatFieldWearable] = item.wearable or ""
    stats[invStatFieldType] = item.type or item.list_type or ""

    if item.stats then
        for k, v in pairs(item.stats) do
            stats[k] = v
        end
    end
    if item.resists then
        for k, v in pairs(item.resists) do
            stats[k] = v
        end
    end

    inv.items.setItem(objId, {
        stats = stats,
        location = invItemLocInventory,
    })

    return objId, previous
end

local function restoreTemporaryItem(objId, previous)
    if previous then
        inv.items.setItem(objId, previous)
    else
        inv.items.removeItem(objId)
    end
end

local function scoreItemAgainstPriorities(item, priorities)
    local objId, previous = buildTemporaryItem(item)
    local locs = (inv.compare and inv.compare._expandWearLocations and inv.compare._expandWearLocations(objId)) or {}
    local betterFor = {}
    local priorityScores = {}
    local priorityLevelRanges = {}
    local totalScore = 0
    local itemLevel = getItemLevelForScore(item)
    local tier = (dbot.gmcp and dbot.gmcp.getTier and dbot.gmcp.getTier()) or 0
    local tierBonus = tier * 10
    local minLevel = math.max(1, itemLevel - tierBonus)
    local maxLevel = 201

    for _, priorityName in ipairs(priorities) do
        local analysis = inv.analyze.table and inv.analyze.table[priorityName]
        local levels = analysis and analysis.levels or nil
        local bestDelta = 0
        local positiveLevels = {}

        if levels then
            for lvl = minLevel, maxLevel do
                local entry = levels[tostring(lvl)]
                if entry and entry.equipment then
                    local effectiveLevel = lvl + tierBonus
                    local targetScore = inv.score.getItemScore(objId, priorityName, effectiveLevel)
                    local levelBestDelta = nil

                    for loc in pairs(locs) do
                        local wornId = entry.equipment[loc]
                        if wornId then
                            local wornScore = inv.score.getItemScore(wornId, priorityName, effectiveLevel)
                            local delta = (tonumber(targetScore) or 0) - (tonumber(wornScore) or 0)
                            if not levelBestDelta or delta > levelBestDelta then
                                levelBestDelta = delta
                            end
                        end
                    end

                    if levelBestDelta and levelBestDelta > bestDelta then
                        bestDelta = levelBestDelta
                    end
                    if levelBestDelta and levelBestDelta > 0 then
                        positiveLevels[#positiveLevels + 1] = lvl
                    end
                end
            end
        end

        if bestDelta > 0 then
            betterFor[#betterFor + 1] = priorityName
            priorityScores[priorityName] = bestDelta
            priorityLevelRanges[priorityName] = formatLevelRanges(positiveLevels)
            totalScore = totalScore + bestDelta
        end
    end

    restoreTemporaryItem(objId, previous)

    return totalScore, betterFor, priorityScores, priorityLevelRanges
end

local function scoreCollectedItems()
    local st = inv.discover.state
    local scored = {}
    local collectedList = {}

    for _, item in pairs(st.collected) do
        collectedList[#collectedList + 1] = item
    end

    table.sort(collectedList, function(a, b)
        return tonumber(a.num or 0) < tonumber(b.num or 0)
    end)

    local total = #collectedList
    if total > 0 then
        info(string.format("scoring progress: 0/%d", total))
    end

    for idx, item in ipairs(collectedList) do
        local score, betterFor, priorityScores, priorityLevelRanges = scoreItemAgainstPriorities(item, st.eligiblePriorities)
        if score > 0 and #betterFor > 0 then
            scored[#scored + 1] = {
                num = tostring(item.num),
                name = stripBorder(item.name or item.desc or "Unknown item"),
                score = score,
                betterFor = betterFor,
                priorityScores = priorityScores,
                priorityLevelRanges = priorityLevelRanges,
                level = getItemLevelForScore(item),
            }
        end

        if (idx % (st.scoreProgressStep or 10) == 0) or idx == total then
            info(string.format("scoring progress: %d/%d", idx, total))
        end
    end

    table.sort(scored, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        return tonumber(a.num) < tonumber(b.num)
    end)

    st.cachedResults = scored
    st.cachedAt = os.time()

    return scored
end

local function printCachedResults()
    local st = inv.discover.state
    if not st.cachedResults or #st.cachedResults == 0 then
        info("no scored upgrades in cache")
        return DRL_RET_SUCCESS
    end

    info(string.format("showing %d scored market items", #st.cachedResults))
    if cecho then
        cecho("\n")
    end
    for _, entry in ipairs(st.cachedResults) do
        emitScoredRow(entry)
    end

    return DRL_RET_SUCCESS
end

local function finishScan()
    local st = inv.discover.state
    local count = 0
    for _ in pairs(st.collected) do
        count = count + 1
    end

    info(string.format("market parsing complete (%d items), scoring...", count))
    local scored = scoreCollectedItems()
    debug(string.format("finishScan: parsed=%d scored_positive=%d", count, #scored))
    info(string.format("scoring complete: %d positive items", #scored))
    printCachedResults()
    clearRuntime(true)
end

local function startNextBid()
    local st = inv.discover.state
    if st.currentNum ~= nil then
        return
    end

    local nextNum = popFront(st.pendingNums)
    if not nextNum then
        finishScan()
        return
    end

    local cached = st.itemCache and st.itemCache[tostring(nextNum)]
    if cached then
        st.collected[tostring(nextNum)] = copyTable(cached)
        debug("startNextBid: cache hit for lbid " .. tostring(nextNum))
        st.parsedCount = (st.parsedCount or 0) + 1
        if st.totalToInspect > 0 and ((st.parsedCount % 10 == 0) or st.parsedCount == st.totalToInspect) then
            infoProgress(string.format("inspect progress: %d/%d", st.parsedCount, st.totalToInspect))
        end
        startNextBid()
        return
    end

    st.currentNum = tostring(nextNum)
    st.itemBuffering = true
    st.itemWork = st.collected[st.currentNum] or { num = st.currentNum, stats = {}, resists = {} }
    beginTempIdentifyParse(st.currentNum)
    debug("startNextBid: fetching lbid " .. tostring(st.currentNum))
    sendSilentCommand("lbid " .. tostring(st.currentNum))
end

function inv.discover.onRawItemLine(v)
    local st = inv.discover.state
    if st.busy and tostring(v or ""):find("Aardwolf Marketplace%s*%-%s*Current List of Inventory") then
        if deleteLine then deleteLine() end
        return
    end

    if st.listBuffering then
        if deleteLine then deleteLine() end
        return
    end

    if not st.itemBuffering or not st.currentNum then
        return
    end

    if inv.items and inv.items.onIdentifyLine then
        inv.items.currentIdentifyId = tonumber(st.currentNum) or st.currentNum
        inv.items.onIdentifyLine(v or "")
    end

    if deleteLine then deleteLine() end
end

function inv.discover.onListHeader()
    local st = inv.discover.state
    if not st.busy then
        return
    end
    st.listBuffering = true
    debug("onListHeader: started buffering market search list")
    if deleteLine then deleteLine() end
end

function inv.discover.onListRow(num, desc, lvl, typ, lastBid, bids, timeLeft)
    local st = inv.discover.state
    if not st.busy or not st.listBuffering then
        return
    end

    local n = tostring(num)
    local cached = st.itemCache and st.itemCache[n]
    st.collected[n] = st.collected[n] or { num = n, stats = {}, resists = {} }
    local it = st.collected[n]
    it.desc = trim(desc)
    it.list_level = tonumber(lvl) or 0
    it.list_type = trim((typ or ""):gsub("^%s*%*%s*", ""))
    it.last_bid = tostring(lastBid or ""):gsub("%*$", "")
    it.bids = tonumber(bids) or 0
    it.time_left = trim(timeLeft)
    if cached then
        st.collected[n] = copyTable(cached)
        debug("onListRow: cache hit for lbid " .. n .. " (skipping fetch)")
    else
        push(st.pendingNums, n)
    end

    if deleteLine then deleteLine() end
end

function inv.discover.onListFooter()
    local st = inv.discover.state
    if not st.busy then
        return
    end
    st.listBuffering = false
    st.totalToInspect = #st.pendingNums
    st.parsedCount = 0
    local totalListed = 0
    for _ in pairs(st.collected or {}) do
        totalListed = totalListed + 1
    end
    local cachedCount = totalListed - st.totalToInspect
    debug("onListFooter: queued_for_fetch=" .. tostring(#st.pendingNums))
    info(string.format("market list parsed: %d item(s), %d cached, %d to inspect", totalListed, cachedCount, st.totalToInspect))
    if st.totalToInspect > 0 then
        infoProgress(string.format("inspect progress: 0/%d", st.totalToInspect))
    end
    if deleteLine then deleteLine() end
    startNextBid()
end

function inv.discover.onName(v)
    local st = inv.discover.state
    if not st.itemBuffering or not st.currentNum then
        return
    end
    st.itemWork.name = stripBorder(v)
    if deleteLine then deleteLine() end
end

function inv.discover.onTypeLevel(typeName, level)
    local st = inv.discover.state
    if not st.itemBuffering or not st.currentNum then
        return
    end
    st.itemWork.type = stripBorder(typeName)
    st.itemWork.level = tonumber(level) or 0
    if deleteLine then deleteLine() end
end

function inv.discover.onWearable(v)
    local st = inv.discover.state
    if not st.itemBuffering or not st.currentNum then
        return
    end
    st.itemWork.wearable = stripBorder(v)
    if deleteLine then deleteLine() end
end

function inv.discover.onWeaponLine(weaponType, averageDam)
    local st = inv.discover.state
    if not st.itemBuffering or not st.currentNum then
        return
    end
    st.itemWork.weapon_type = stripBorder(weaponType)
    st.itemWork.stats = st.itemWork.stats or {}
    st.itemWork.stats[invStatFieldAveDam] = tonumber(averageDam) or 0
    if deleteLine then deleteLine() end
end

function inv.discover.onStatLine(v)
    local st = inv.discover.state
    if not st.itemBuffering or not st.currentNum then
        return
    end
    st.inStats = true
    st.inResists = false
    st.itemWork.stats = st.itemWork.stats or {}
    parsePairsInto(st.itemWork.stats, v)
    if deleteLine then deleteLine() end
end

function inv.discover.onResistLine(v)
    local st = inv.discover.state
    if not st.itemBuffering or not st.currentNum then
        return
    end
    st.inResists = true
    st.inStats = false
    st.itemWork.resists = st.itemWork.resists or {}
    parsePairsInto(st.itemWork.resists, v)
    if deleteLine then deleteLine() end
end

function inv.discover.onContLine(v)
    local st = inv.discover.state
    if not st.itemBuffering or not st.currentNum then
        return
    end
    if st.inStats then
        st.itemWork.stats = st.itemWork.stats or {}
        parsePairsInto(st.itemWork.stats, v)
    elseif st.inResists then
        st.itemWork.resists = st.itemWork.resists or {}
        parsePairsInto(st.itemWork.resists, v)
    end
    if deleteLine then deleteLine() end
end

function inv.discover.onBorder()
    local st = inv.discover.state
    st.inStats = false
    st.inResists = false
    if st.busy and deleteLine then
        deleteLine()
    end
end

function inv.discover.onMarketBanner()
    local st = inv.discover.state
    if not st.busy then
        return
    end
    if deleteLine then
        deleteLine()
    elseif setTriggerOption then
        setTriggerOption("omit_from_output", "y")
    end
end

function inv.discover.onMarketNum(num)
    local st = inv.discover.state
    if not st.itemBuffering or not st.currentNum then
        return
    end
    st.itemWork.num = tostring(num)
    if deleteLine then deleteLine() end
end

function inv.discover.onCurrentBid(v)
    local st = inv.discover.state
    if not st.itemBuffering or not st.currentNum then
        return
    end
    st.itemWork.current_bid = stripBorder(v)

    local parsed = readTempIdentifyParse(st.currentNum)
    if parsed and parsed.stats then
        st.itemWork.stats = copyTable(parsed.stats)
        st.itemWork.wearable = st.itemWork.wearable or parsed.stats[invStatFieldWearable]
        st.itemWork.type = st.itemWork.type or parsed.stats[invStatFieldType]
        st.itemWork.level = st.itemWork.level or parsed.stats[invStatFieldLevel]
    end

    st.collected[tostring(st.currentNum)] = st.itemWork
    st.itemCache[tostring(st.currentNum)] = copyTable(st.itemWork)
    st.parsedCount = (st.parsedCount or 0) + 1
    if deleteLine then deleteLine() end
    if st.totalToInspect > 0 and ((st.parsedCount % 10 == 0) or st.parsedCount == st.totalToInspect) then
        infoProgress(string.format("inspect progress: %d/%d", st.parsedCount, st.totalToInspect))
    end
    debug("onCurrentBid: cached lbid " .. tostring(st.currentNum))
    clearTempIdentifyParse(st.currentNum)

    st.itemWork = nil
    st.itemBuffering = false
    st.currentNum = nil
    st.inStats = false
    st.inResists = false

    startNextBid()
end

function inv.discover.registerTriggers()
    unregisterTriggers()

    local st = inv.discover.state

    if not tempRegexTrigger then
        warn("discover scanning requires tempRegexTrigger support")
        return DRL_RET_UNINITIALIZED
    end

    st.triggers.listHeader = tempRegexTrigger(
        "^Num\\s+Item Description\\s+Lvl\\s+Type\\s+Last Bid\\s+Bids\\s+Time Left$",
        function()
            inv.discover.onListHeader()
        end
    )

    st.triggers.marketBanner = tempRegexTrigger(
        "^.*Aardwolf Marketplace%s*%-%s*Current List of Inventory.*$",
        function()
            inv.discover.onMarketBanner()
        end
    )

    st.triggers.listRow = tempRegexTrigger(
        "^\\s*(\\d+)\\s+(.+?)\\s+(\\d+)\\s+(\\*?\\s*\\S+)\\s+((?:[\\d,]+(?:\\*)?)|[A-Za-z]+)\\s+(\\d+)\\s+(?:(?:\\d+\\s+day[s]?\\s+and\\s+)|(?:\\d+d\\s+))?\\d{2}:\\d{2}:\\d{2}\\s*$",
        function()
            if matches then
                inv.discover.onListRow(matches[2], matches[3], matches[4], matches[5], matches[6], matches[7], matches[8])
            end
        end
    )

    st.triggers.listFooter = tempRegexTrigger(
        "^Type:\\s*'market bid",
        function()
            inv.discover.onListFooter()
        end
    )

    st.triggers.name = tempRegexTrigger(
        "^\\|\\s*Name\\s*:\\s*(.+?)\\s*$",
        function() if matches then inv.discover.onName(matches[2]) end end
    )

    st.triggers.typeLevel = tempRegexTrigger(
        "^\\|\\s*Type\\s*:\\s*(\\S.*?)\\s+Level\\s*:\\s*(\\d+)\\s*$",
        function() if matches then inv.discover.onTypeLevel(matches[2], matches[3]) end end
    )

    st.triggers.wearable = tempRegexTrigger(
        "^\\|\\s*Wearable\\s*:\\s*(.+?)\\s*$",
        function() if matches then inv.discover.onWearable(matches[2]) end end
    )

    st.triggers.weaponLine = tempRegexTrigger(
        "^\\|\\s*Weapon Type\\s*:\\s*(\\S+)\\s+Average Dam\\s*:\\s*(\\d+)\\s*",
        function() if matches then inv.discover.onWeaponLine(matches[2], matches[3]) end end
    )

    st.triggers.statLine = tempRegexTrigger(
        "^\\|\\s*Stat Mods\\s*:\\s*(.+?)\\s*$",
        function() if matches then inv.discover.onStatLine(matches[2]) end end
    )

    st.triggers.resistLine = tempRegexTrigger(
        "^\\|\\s*Resist Mods\\s*:\\s*(.+?)\\s*$",
        function() if matches then inv.discover.onResistLine(matches[2]) end end
    )

    st.triggers.contLine = tempRegexTrigger(
        "^\\|\\s{1,}([A-Za-z].+?:\\s*[+-]?\\d+.*)$",
        function() if matches then inv.discover.onContLine(matches[2]) end end
    )

    st.triggers.border = tempRegexTrigger(
        "^\\+[-\\+]+\\+$",
        function() inv.discover.onBorder() end
    )

    st.triggers.marketNum = tempRegexTrigger(
        "^\\|\\s*Market Item Number\\s*:\\s*(\\d+)\\s*$",
        function() if matches then inv.discover.onMarketNum(matches[2]) end end
    )

    st.triggers.currentBid = tempRegexTrigger(
        "^\\|\\s*Current bid\\s*:\\s*(.+?)\\s*$",
        function() if matches then inv.discover.onCurrentBid(matches[2]) end end
    )

    st.triggers.itemAnyLine = tempRegexTrigger(
        "^(.*)$",
        function()
            local line = matches and matches[2] or ""
            inv.discover.onRawItemLine(line)
        end
    )

    return DRL_RET_SUCCESS
end

function inv.discover.setType(itemType)
    local st = inv.discover.state
    st.marketType = trim(itemType)
    if st.marketType == "" then
        warn("Usage: dinv discover <armor|weapon>")
        return DRL_RET_INVALID_PARAM
    end
    dbot.info("Discover market type set to '@G" .. st.marketType .. "@W'.")
    return DRL_RET_SUCCESS
end

function inv.discover.scan(priorityFilter)
    local st = inv.discover.state

    if st.busy then
        warn("Discover scan already in progress.")
        return DRL_RET_BUSY
    end

    if not st.marketType or st.marketType == "" then
        warn("Set market type first: dinv discover armor or dinv discover weapon")
        return DRL_RET_INVALID_PARAM
    end

    if not hasAnyAnalysis() then
        warn("Discover requires analysis data. Run @Gdinv analyze create <priority>@W first.")
        return DRL_RET_MISSING_ENTRY
    end

    local priorities, retval = discoverEligiblePriorities(priorityFilter)
    if retval ~= DRL_RET_SUCCESS or #priorities == 0 then
        warn("No eligible analysis data found for discover scan.")
        if priorityFilter and priorityFilter ~= "" then
            dbot.info("Run @Gdinv analyze create " .. tostring(priorityFilter) .. "@W first.")
        end
        return DRL_RET_MISSING_ENTRY
    end

    clearRuntime(true)
    st.busy = true
    st.priorityFilter = priorityFilter
    st.eligiblePriorities = priorities

    local itemCacheSize = 0
    for _ in pairs(st.itemCache or {}) do
        itemCacheSize = itemCacheSize + 1
    end
    debug("scan: type='" .. tostring(st.marketType) .. "' priorityFilter='" .. tostring(priorityFilter) .. "' eligible=" .. tostring(#priorities) .. " itemCacheSize=" .. tostring(itemCacheSize))

    local triggerRet = inv.discover.registerTriggers()
    if triggerRet ~= DRL_RET_SUCCESS then
        clearRuntime(true)
        return triggerRet
    end

    info("scanning market type '" .. st.marketType .. "'...")
    info("scoring against priorities: " .. table.concat(priorities, ", "))
    sendSilentCommand("market search " .. st.marketType)

    return DRL_RET_SUCCESS
end

function inv.discover.cancel()
    local st = inv.discover.state
    if not st.busy then
        dbot.info("No discover scan is running.")
        return DRL_RET_SUCCESS
    end
    clearRuntime(true)
    dbot.info("Discover scan canceled.")
    return DRL_RET_SUCCESS
end

function inv.discover.show()
    return printCachedResults()
end

function inv.discover.clearType()
    local st = inv.discover.state
    st.marketType = ""
    st.cachedResults = {}
    st.cachedAt = nil
    st.itemCache = {}
    dbot.info("Discover type and cached results cleared.")
    return DRL_RET_SUCCESS
end

function inv.discover.status()
    local st = inv.discover.state
    local typeLabel = (st.marketType ~= "" and st.marketType) or "(not set)"
    local busyLabel = st.busy and "yes" or "no"
    local cacheCount = st.cachedResults and #st.cachedResults or 0
    local itemCacheCount = 0
    for _ in pairs(st.itemCache or {}) do
        itemCacheCount = itemCacheCount + 1
    end
    dbot.info(string.format("Discover status: type=%s, running=%s, cached_results=%d, cached_items=%d", typeLabel, busyLabel, cacheCount, itemCacheCount))
    return DRL_RET_SUCCESS
end

function inv.cli.discover.fn(name, line, wildcards)
    local arg1 = trim((wildcards and wildcards[1]) or "")
    local arg2 = trim((wildcards and wildcards[2]) or "")

    if arg1 == "" then
        inv.cli.discover.examples()
        return DRL_RET_SUCCESS
    end

    local cmd = lower(arg1)
    if cmd == "scan" then
        local priorityFilter = arg2 ~= "" and arg2 or nil
        return inv.discover.scan(priorityFilter)
    elseif cmd == "show" then
        return inv.discover.show()
    elseif cmd == "cancel" or cmd == "abort" or cmd == "stop" then
        return inv.discover.cancel()
    elseif cmd == "clear" then
        return inv.discover.clearType()
    elseif cmd == "status" then
        return inv.discover.status()
    end

    -- Any other first arg is treated as replacement type, e.g. armor/weapon.
    return inv.discover.setType(arg1)
end

function inv.cli.discover.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", pluginNameCmd .. " discover @G<type>", "Set discover market type (replaces previous type)"))
    dbot.printRaw(string.format("@W    %-50s @w- %s", pluginNameCmd .. " discover @Gscan [priority]", "Scan market and score positive upgrades only"))
    dbot.printRaw(string.format("@W    %-50s @w- %s", pluginNameCmd .. " discover @Gshow", "Show cached discover results from current session"))
end

function inv.cli.discover.examples()
    dbot.print([[@W
Usage:
    dinv discover armor
    dinv discover scan
    dinv discover scan mage
    dinv discover show
    dinv discover clear

Notes:
  - Setting a type replaces the previous discover type.
  - Scan output is quiet and only prints scored items with @Gscore > 0@W.
  - Market numbers are clickable and run @Glbid <num>@W.
  - Results are cached in-memory only and are not saved across client restarts.
]])
end

function inv.discover.init.atInstall()
    local st = inv.discover.state
    st.marketType = st.marketType or ""
    st.cachedResults = st.cachedResults or {}
    st.itemCache = st.itemCache or {}
    return DRL_RET_SUCCESS
end

function inv.discover.init.atActive()
    return DRL_RET_SUCCESS
end

dbot.debug("inv.discover module loaded", "inv.discover")
