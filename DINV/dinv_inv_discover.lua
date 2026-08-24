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
    parsedCount = 0,
    totalToInspect = 0,
    scoreProgressStep = 10,
    activeContext = nil,
    resultContext = nil,
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
    st.tempIdentifyPrevious = {}
    if not keepCache then
        st.cachedResults = {}
        st.cachedAt = nil
        st.resultContext = nil
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

local function markTransientItem(item)
    item = item or {}
    item.__dinvTransient = true
    item.stats = item.stats or {}
    item.stats.__dinvTransient = true
    return item
end

local function setTransientItem(objId, item)
    inv.items.setItem(objId, markTransientItem(item), { silentApi = true })
end

local function restoreTransientItem(objId, previous)
    if previous then
        inv.items.setItem(objId, previous, { silentApi = true })
    else
        inv.items.removeItem(objId, { silentApi = true })
    end
end

local function beginTempIdentifyParse(objId)
    if not objId then
        return
    end

    local idNum = tonumber(objId) or objId
    local key = tostring(idNum)
    local st = inv.discover.state
    st.tempIdentifyPrevious = st.tempIdentifyPrevious or {}
    if st.tempIdentifyPrevious[key] == nil then
        st.tempIdentifyPrevious[key] = copyTable(inv.items.getItem(idNum)) or false
    end
    inv.items.currentIdentifyId = idNum
    inv.items.identifyCurrentId = idNum
    inv.items.identifyResetId = nil
    setTransientItem(idNum, {
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
    local key = tostring(idNum)
    local st = inv.discover.state
    local previous = st.tempIdentifyPrevious and st.tempIdentifyPrevious[key]
    if previous ~= nil then
        restoreTransientItem(idNum, previous ~= false and previous or nil)
        st.tempIdentifyPrevious[key] = nil
    else
        inv.items.removeItem(idNum, { silentApi = true })
    end
    if inv.items.currentIdentifyId == idNum then
        inv.items.currentIdentifyId = nil
    end
    if inv.items.identifyCurrentId == idNum then
        inv.items.identifyCurrentId = nil
    end
    if inv.items.identifyResetId == idNum then
        inv.items.identifyResetId = nil
    end
end

local function discoverEligiblePriorities(priorityFilter)
    local out = {}
    local stale = {}
    local tableData = (inv.analyze and inv.analyze.table) or {}

    if priorityFilter and priorityFilter ~= "" then
        local data = tableData[priorityFilter]
        if data and data.levels and next(data.levels) then
            local staleReason = inv.analyze and inv.analyze.getStaleReason and inv.analyze.getStaleReason(priorityFilter) or nil
            if staleReason then
                stale[#stale + 1] = { name = priorityFilter, reason = staleReason }
            end
            out[#out + 1] = priorityFilter
            return out, DRL_RET_SUCCESS, stale
        end
        return out, DRL_RET_MISSING_ENTRY, stale
    end

    for priorityName, data in pairs(tableData) do
        if data and data.levels and next(data.levels) then
            local staleReason = inv.analyze and inv.analyze.getStaleReason and inv.analyze.getStaleReason(priorityName) or nil
            if staleReason then
                stale[#stale + 1] = { name = priorityName, reason = staleReason }
            end
            out[#out + 1] = priorityName
        end
    end
    table.sort(out)
    table.sort(stale, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return out, DRL_RET_SUCCESS, stale
end

local function emitScoredRow(entry)
    local function countLevelsInRanges(rangeText)
        local total = 0
        local text = tostring(rangeText or "")
        if text == "" then
            return 0
        end
        for chunk in string.gmatch(text, "[^,]+") do
            local token = trim(chunk)
            local startLvl, endLvl = token:match("^(%-?%d+)%s*%-%s*(%-?%d+)$")
            if startLvl and endLvl then
                local a = tonumber(startLvl) or 0
                local b = tonumber(endLvl) or a
                if b < a then
                    a, b = b, a
                end
                total = total + (b - a + 1)
            else
                local single = tonumber(token)
                if single then
                    total = total + 1
                end
            end
        end
        return total
    end

    local function prioritySummaryPart(priorityName)
        local pr = tostring(priorityName)
        local score = roundInt((entry.priorityScores or {})[pr] or 0)
        local ranges = tostring((entry.priorityLevelRanges or {})[pr] or "")
        local levelCount = countLevelsInRanges(ranges)
        return string.format("%s(+%d over %d levels)", pr, math.abs(score), levelCount)
    end

    local priorities = entry.betterFor or {}
    local summaryParts = {}
    local coloredSummaryParts = {}
    for _, priorityName in ipairs(priorities) do
        local part = prioritySummaryPart(priorityName)
        summaryParts[#summaryParts + 1] = part
        coloredSummaryParts[#coloredSummaryParts + 1] = "@C" .. part .. "@w"
    end
    local summary = (#summaryParts > 0) and table.concat(summaryParts, " / ") or "-"
    local coloredSummary = (#coloredSummaryParts > 0)
        and table.concat(coloredSummaryParts, "@W / @w") or "@W-@w"
    local timeLeft = tostring(entry.timeLeft or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local reportTimingSuffix = timeLeft ~= "" and ("@W Auction will end in " .. timeLeft .. "@w") or ""
    local reportIdColor = entry.isWinningBid and "@G" or "@Y"
    local reportLine = string.format("@C[%s%s@C]@w @W%s@w %s%s",
        reportIdColor, tostring(entry.num), tostring(entry.name), coloredSummary, reportTimingSuffix)

    local function appendAuctionTimingText()
        if timeLeft ~= "" then
            cecho("<white> Auction will end in " .. timeLeft .. "<reset>")
        end
    end

    if cecho then
        cecho("<cyan>[<reset>")
        local lbidCmd = "lbid " .. tostring(entry.num)
        local idColor = entry.isWinningBid and "<green>" or "<yellow>"
        local visible = idColor .. tostring(entry.num) .. "<reset>"
        local popupShown = inv.items and inv.items.echoReportChannelPopup
            and inv.items.echoReportChannelPopup(
                visible,
                function(channel)
                    inv.items.runReportLineFromLink(reportLine, channel)
                end,
                "Left-click: report this market result via ",
                function()
                    if send then
                        send(lbidCmd)
                    end
                end,
                "Run: " .. lbidCmd
            )
        if not popupShown and cechoLink then
            cechoLink(visible, "send([[" .. lbidCmd .. "]])", "Run: " .. lbidCmd, true)
        elseif not popupShown then
            cecho(visible)
        end
        cecho("<cyan>]<reset> ")
        cecho("<white>" .. tostring(entry.name) .. "<reset> ")

        if #priorities > 0 and cechoLink then
            for i, priorityName in ipairs(priorities) do
                if i > 1 then
                    cecho("<white> / <reset>")
                end

                local pr = tostring(priorityName)
                local label = string.format("<cyan>%s<reset>", prioritySummaryPart(pr))
                local command = string.format("inv.discover.showPriorityAnalysis(%q, %q)", tostring(entry.num), pr)
                cechoLink(label, command, "Show discover analysis for " .. pr, true)
            end
            appendAuctionTimingText()
            cecho("\n")
        elseif #priorities > 0 then
            cecho("<white>" .. summary .. "<reset>")
            appendAuctionTimingText()
            cecho("\n")
        else
            cecho("-\n")
        end
    else
        dbot.print(reportLine)
    end
    return nil
end

local function findCachedEntryByAuctionNum(auctionNum)
    local st = inv.discover.state
    local key = tostring(auctionNum or "")
    for _, entry in ipairs(st.cachedResults or {}) do
        if tostring(entry.num or "") == key then
            return entry
        end
    end
    return nil
end

function inv.discover.showPriorityAnalysis(auctionNum, priorityName)
    local entry = findCachedEntryByAuctionNum(auctionNum)
    local pr = tostring(priorityName or "")
    if not entry then
        dbot.warn("No cached discover result found for auction #" .. tostring(auctionNum))
        return DRL_RET_MISSING_ENTRY
    end

    local details = entry.priorityDetails and entry.priorityDetails[pr] or nil
    if not details or #details == 0 then
        dbot.warn("No cached discover analysis for auction #" .. tostring(auctionNum) .. " priority '" .. pr .. "'.")
        return DRL_RET_MISSING_ENTRY
    end

    if not inv.compare or not inv.compare.covetAnalyze then
        dbot.warn("Discover analysis renderer is unavailable.")
        return DRL_RET_MISSING_ENTRY
    end

    local st = inv.discover.state
    local key = tostring(auctionNum or "")
    local sourceItem = entry.itemData
    if not sourceItem then
        dbot.warn("No cached market item payload found for auction #" .. tostring(auctionNum))
        return DRL_RET_MISSING_ENTRY
    end

    local previous = copyTable(inv.items.getItem(key))
    local tempItem = copyTable(sourceItem)
    tempItem.stats = copyTable(tempItem.stats or {})
    tempItem.stats[invStatFieldId] = key
    tempItem.stats[invStatFieldName] = "Auction #" .. key
    tempItem.stats[invStatFieldColorName] = "Auction #" .. key
    tempItem.stats[invStatFieldLocation] = "auction"

    setTransientItem(key, tempItem)

    local ok, retval = pcall(function()
        return inv.compare.covetAnalyze(pr, tonumber(key) or key, 1, {
            targetReportName = entry.name,
        })
    end)

    restoreTransientItem(key, previous)

    if not ok then
        dbot.warn("Failed to render discover analysis for auction #" .. tostring(auctionNum))
        return DRL_RET_INTERNAL_ERROR
    end

    return retval or DRL_RET_SUCCESS
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

    setTransientItem(objId, {
        stats = stats,
        location = "auction",
    })

    return objId, previous
end

local function restoreTemporaryItem(objId, previous)
    restoreTransientItem(objId, previous)
end

local function scoreItemAgainstPriorities(item, priorities)
    local objId, previous = buildTemporaryItem(item)
    local ok, totalScore, betterFor, priorityScores, priorityLevelRanges, priorityDetails = pcall(function()
        local locs = (inv.compare and inv.compare._expandWearLocations and inv.compare._expandWearLocations(objId)) or {}
        local foundBetterFor = {}
        local foundPriorityScores = {}
        local foundPriorityLevelRanges = {}
        local foundPriorityDetails = {}
        local foundTotalScore = 0
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
            local rows = {}
            local positiveDeltaSum = 0
            local positiveDeltaCount = 0

            if levels then
                for lvl = minLevel, maxLevel do
                    local entry = levels[tostring(lvl)]
                    if entry and entry.equipment then
                        local effectiveLevel = lvl + tierBonus
                        local levelBestDelta = nil

                        for loc in pairs(locs) do
                            local wornId = entry.equipment[loc]
                            if wornId then
                                local targetScore = inv.score.getItemScoreForLoc(objId, priorityName, effectiveLevel, loc)
                                local wornScore = inv.score.getItemScoreForLoc(wornId, priorityName, effectiveLevel, loc)
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
                            rows[#rows + 1] = {
                                level = lvl,
                                scoreDelta = levelBestDelta,
                            }
                            positiveDeltaSum = positiveDeltaSum + levelBestDelta
                            positiveDeltaCount = positiveDeltaCount + 1
                        end
                    end
                end
            end

            if bestDelta > 0 then
                foundBetterFor[#foundBetterFor + 1] = priorityName
                local averageDelta = 0
                if positiveDeltaCount > 0 then
                    averageDelta = roundInt(positiveDeltaSum / positiveDeltaCount)
                end
                foundPriorityScores[priorityName] = averageDelta
                foundPriorityLevelRanges[priorityName] = formatLevelRanges(positiveLevels)
                foundPriorityDetails[priorityName] = rows
                foundTotalScore = foundTotalScore + averageDelta
            end
        end

        return foundTotalScore, foundBetterFor, foundPriorityScores, foundPriorityLevelRanges, foundPriorityDetails
    end)

    restoreTemporaryItem(objId, previous)

    if not ok then
        warn("Failed to score market item #" .. tostring(item and item.num or objId) .. ": " .. tostring(totalScore))
        return 0, {}, {}, {}, {}
    end

    return totalScore, betterFor, priorityScores, priorityLevelRanges, priorityDetails
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
        local score, betterFor, priorityScores, priorityLevelRanges, priorityDetails = scoreItemAgainstPriorities(item, st.eligiblePriorities)
        if score > 0 and #betterFor > 0 then
            scored[#scored + 1] = {
                num = tostring(item.num),
                name = stripBorder(item.name or item.desc or "Unknown item"),
                score = score,
                betterFor = betterFor,
                priorityScores = priorityScores,
                priorityLevelRanges = priorityLevelRanges,
                priorityDetails = priorityDetails,
                level = getItemLevelForScore(item),
                timeLeft = item.time_left,
                isWinningBid = item.is_winning_bid == true,
                itemData = copyTable(item),
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
    st.resultContext = inv.context and inv.context.copy and inv.context.copy(st.activeContext)
        or (inv.context and inv.context.capture and inv.context.capture())

    return scored
end

local function printCachedResults()
    local st = inv.discover.state
    local staleReason = inv.context and inv.context.getStaleReason and inv.context.getStaleReason(st.resultContext) or nil
    if st.cachedAt and staleReason then
        warn("Cached scan results are stale: " .. staleReason .. ". Displaying them anyway; run dinv discover scan to refresh them.")
    end
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
        inv.items.identifyCurrentId = inv.items.currentIdentifyId
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
    st.collected[n] = st.collected[n] or { num = n, stats = {}, resists = {} }
    local it = st.collected[n]
    it.desc = trim(desc)
    it.list_level = tonumber(lvl) or 0
    it.list_type = trim((typ or ""):gsub("^%s*%*%s*", ""))
    local rawLastBid = tostring(lastBid or "")
    it.last_bid = rawLastBid:gsub("%*$", "")
    it.is_winning_bid = rawLastBid:find("%*$") ~= nil
    it.bids = tonumber(bids) or 0
    it.time_left = trim(timeLeft)
    push(st.pendingNums, n)

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
    local currentBid = stripBorder(v)
    st.itemWork.current_bid = currentBid

    -- The market list marker is useful as a fallback, but lbid is the
    -- authoritative source for the current bidder.  A discover scan fetches
    -- every item, so use its fresh bidder value whenever the character name
    -- is available through GMCP.
    local currentBidder = trim(currentBid:match("%(([^()]*)%)%s*$") or "")
    if currentBidder ~= "" then
        st.itemWork.current_bidder = currentBidder
        local characterName = dbot and dbot.gmcp and dbot.gmcp.getName
            and trim(dbot.gmcp.getName() or "") or ""
        if characterName ~= "" then
            st.itemWork.is_winning_bid = lower(currentBidder) == lower(characterName)
        end
    else
        st.itemWork.current_bidder = nil
    end

    local parsed = readTempIdentifyParse(st.currentNum)
    if parsed and parsed.stats then
        st.itemWork.stats = copyTable(parsed.stats)
        st.itemWork.wearable = st.itemWork.wearable or parsed.stats[invStatFieldWearable]
        st.itemWork.type = st.itemWork.type or parsed.stats[invStatFieldType]
        st.itemWork.level = st.itemWork.level or parsed.stats[invStatFieldLevel]
    end

    st.collected[tostring(st.currentNum)] = st.itemWork
    st.parsedCount = (st.parsedCount or 0) + 1
    if deleteLine then deleteLine() end
    if st.totalToInspect > 0 and ((st.parsedCount % 10 == 0) or st.parsedCount == st.totalToInspect) then
        infoProgress(string.format("inspect progress: %d/%d", st.parsedCount, st.totalToInspect))
    end
    debug("onCurrentBid: inspected lbid " .. tostring(st.currentNum))
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

    st.triggers.emptyLine = tempRegexTrigger(
        "^\\s*$",
        function()
            if inv.discover.state.busy and deleteLine then
                deleteLine()
            end
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

    local priorities, retval, stalePriorities = discoverEligiblePriorities(priorityFilter)
    for _, staleEntry in ipairs(stalePriorities or {}) do
        warn("Analysis '" .. tostring(staleEntry.name) .. "' is stale: " .. tostring(staleEntry.reason) .. ".")
        dbot.info("Run @Gdinv analyze create " .. tostring(staleEntry.name) .. "@W to refresh it.")
    end
    if retval ~= DRL_RET_SUCCESS or #priorities == 0 then
        warn("No eligible analysis data found for discover scan.")
        if priorityFilter and priorityFilter ~= "" then
            dbot.info("Run @Gdinv analyze create " .. tostring(priorityFilter) .. "@W first.")
        end
        return DRL_RET_MISSING_ENTRY
    end

    clearRuntime(true)
    -- Results remain available to `dinv discover show`, but every new scan
    -- rebuilds all item payloads from fresh lbid output. Clear the retired
    -- per-item cache as well when upgrading an already-loaded session.
    st.itemCache = nil
    st.busy = true
    st.priorityFilter = priorityFilter
    st.eligiblePriorities = priorities
    st.activeContext = inv.context and inv.context.capture and inv.context.capture() or nil

    debug("scan: type='" .. tostring(st.marketType) .. "' priorityFilter='" .. tostring(priorityFilter) .. "' eligible=" .. tostring(#priorities) .. " fullRescan=true")

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
    st.itemCache = nil
    st.activeContext = nil
    st.resultContext = nil
    dbot.info("Discover type and cached results cleared.")
    return DRL_RET_SUCCESS
end

function inv.discover.status()
    local st = inv.discover.state
    local typeLabel = (st.marketType ~= "" and st.marketType) or "(not set)"
    local busyLabel = st.busy and "yes" or "no"
    local cacheCount = st.cachedResults and #st.cachedResults or 0
    dbot.info(string.format("Discover status: type=%s, running=%s, cached_results=%d", typeLabel, busyLabel, cacheCount))
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
  - Delta values are computed against max-stat caps for your setup.
  - Because caps are considered, replacing a @G6str@W item with a @G7str@W item can still show @D0str@W delta.
  - Left-click a market number to run @Glbid <num>@W; right-click it to report the summary or copy its colored text.
  - Results are cached in-memory only and are not saved across client restarts.
]])
end

function inv.discover.init.atInstall()
    local st = inv.discover.state
    st.marketType = st.marketType or ""
    st.cachedResults = st.cachedResults or {}
    st.itemCache = nil
    return DRL_RET_SUCCESS
end

function inv.discover.init.atActive()
    return DRL_RET_SUCCESS
end

dbot.debug("inv.discover module loaded", "inv.discover")
