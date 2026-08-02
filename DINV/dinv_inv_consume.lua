----------------------------------------------------------------------------------------------------
-- INV Consume Module
-- Consumable items management (potions, pills, scrolls, etc.)
----------------------------------------------------------------------------------------------------

inv.consume           = inv.consume or {}
inv.consume.init      = inv.consume.init or {}
inv.consume.table     = inv.consume.table or {}
inv.consume.stateName = "inv-consume.state"
inv.consume.addPkg = nil
inv.consume.buyPkg = nil
inv.consume.usePkg = nil

drlConsumeBig   = "big"
drlConsumeSmall = "small"
drlConsumeMaxConsecutiveItems = 10

local function normalizeTypeName(typeName)
    return tostring(typeName or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
end

local function normalizeItemName(itemName)
    return tostring(itemName or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function sanitizeConsumeAliasName(itemName)
    local normalized = normalizeItemName(itemName)
    local withoutPrefix = normalized:match("^[Nn][Aa][Mm][Ee]%s+(.+)$")
    if withoutPrefix and withoutPrefix ~= "" then
        return normalizeItemName(withoutPrefix)
    end
    return normalized
end

local function firstNonEmpty(...)
    local values = { ... }
    for i = 1, #values do
        local value = tostring(values[i] or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if value ~= "" then
            return value
        end
    end
    return ""
end

local function namesMatch(left, right)
    if left == nil or right == nil then
        return false
    end
    return tostring(left):lower() == tostring(right):lower()
end

local function splitWords(value)
    local words = {}
    local normalized = tostring(value or ""):lower()
    for word in normalized:gmatch("%S+") do
        local cleaned = word:gsub("[^%w]", "")
        if cleaned ~= "" then
            table.insert(words, cleaned)
        end
    end
    return words
end

local function getItemKeywordTarget(objId, fallback)
    local keywords = tostring(inv.items.getStatField(objId, invStatFieldKeywords) or "")
    for word in keywords:gmatch("%S+") do
        local normalized = tostring(word or ""):gsub(",", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if normalized ~= "" then
            return normalized
        end
    end

    local fallbackStr = tostring(fallback or "")
    local fallbackWord = fallbackStr:match("^(%S+)")
    if fallbackWord and fallbackWord ~= "" then
        return fallbackWord
    end

    return nil
end

local function getPreferredStoreTarget(entry)
    if not entry then
        return nil
    end

    local explicit = tostring(entry.storeKeyword or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if explicit ~= "" then
        return explicit
    end

    local itemName = tostring(entry.itemName or entry.fullName or entry.name or "")
    local loweredName = itemName:lower()

    local nameWords = {}
    for word in loweredName:gmatch("%w+") do
        table.insert(nameWords, word)
    end

    local keywordWords = {}
    local keywords = tostring(entry.keywords or ""):lower()
    for word in keywords:gmatch("%w+") do
        keywordWords[word] = true
    end

    for i = #nameWords, 1, -1 do
        local word = nameWords[i]
        if keywordWords[word] then
            return word
        end
    end

    if #nameWords > 0 then
        return nameWords[#nameWords]
    end

    return nil
end


local function itemMatchesConsumeEntry(entry, objId)
    if not entry or not objId then
        return false
    end

    local entryLevel = tonumber(entry.level or "") or 0
    local itemLevel = tonumber(inv.items.getStatField(objId, invStatFieldLevel) or "") or 0
    if entryLevel ~= itemLevel then
        return false
    end

    local itemName = tostring(inv.items.getStatField(objId, invStatFieldName) or "")
    if namesMatch(entry.fullName, itemName) or namesMatch(entry.name, itemName) then
        return true
    end

    -- The user-configured name/key is the authority for consume matching.
    -- Do not use the persisted item's complete keyword list as a set of
    -- alternatives: generic words such as "potion" can identify an unrelated
    -- consumable at the same level.
    local configuredTarget = firstNonEmpty(entry.name, entry.key)
    local configuredWords = splitWords(configuredTarget)
    local keywords = tostring(inv.items.getStatField(objId, invStatFieldKeywords) or ""):lower()
    if keywords ~= "" and #configuredWords > 0 then
        for _, word in ipairs(configuredWords) do
            if not dbot.isWordInString(word, keywords) then
                return false
            end
        end
        return true
    end

    return false
end

function inv.consume.getEntry(typeName, entryIndex)
    local normalizedType = normalizeTypeName(typeName)
    local entries = inv.consume.table and inv.consume.table[normalizedType] or nil
    local index = tonumber(entryIndex)
    if type(entries) ~= "table" or not index or index < 1 then
        return nil
    end
    return entries[math.floor(index)], normalizedType
end

function inv.consume.countEntry(entry)
    local count = 0
    if not entry then return count end
    for objId, _ in pairs(inv.items and inv.items.table or {}) do
        local containerId = inv.items.getStatField(objId, invStatFieldContainer)
        local isIgnored = containerId ~= nil and containerId ~= ""
            and inv.config and inv.config.isIgnored and inv.config.isIgnored(containerId)
        if not isIgnored and itemMatchesConsumeEntry(entry, objId) then
            count = count + 1
        end
    end
    return count
end

function inv.consume.notifyWindowChanged()
    if inv.consumeWindow and inv.consumeWindow.scheduleRefresh then
        inv.consumeWindow.scheduleRefresh(true)
    end
end

local function loadPersistentConsumableTemplates()
    if not DINV or not DINV.database or not DINV.database.listConsumableTemplates then
        return nil
    end
    local templates, err = DINV.database.listConsumableTemplates()
    if not templates then
        dbot.warn("inv.consume.add: SQLite consumable lookup failed: " .. tostring(err))
        return nil
    end
    return templates
end

local function isConsumableType(itemType)
    local normalized = tostring(itemType or ""):lower()
    return normalized == "potion"
        or normalized == "pill"
        or normalized == "scroll"
        or normalized == "wand"
        or normalized == "stave"
end

local function lookupPersistentConsumable(itemName, expectedLevel, expectedType)
    local templates = loadPersistentConsumableTemplates()
    if not templates then
        dbot.debug("inv.consume.add: SQLite consumable-template lookup skipped", "inv.consume")
        return nil
    end

    local normalized = dbot.stripColors(itemName or "")
    normalized = normalized:gsub(",", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if normalized == "" then
        return nil
    end
    local lowered = normalized:lower()
    dbot.debug("inv.consume.add: persistence lookup for \"" .. lowered .. "\"", "inv.consume")

    local expectedTypeLower = tostring(expectedType or ""):lower()
    local bestMatch = nil
    local bestScore = -1

    for _, entry in ipairs(templates) do
        local stats = entry and entry.stats
        if stats then
            local itemType = tostring(stats[invStatFieldType] or "")
            local itemTypeLower = itemType:lower()
            if isConsumableType(itemTypeLower) then
                local typeMatches = expectedTypeLower == "" or itemTypeLower == expectedTypeLower
                if typeMatches then
                    local entryName = stats[invStatFieldName] or stats[invStatFieldColorName] or ""
                    local keywords = stats[invStatFieldKeywords] or ""
                    local entryLevel = tonumber(stats[invStatFieldLevel] or "")
                    local levelMatches = expectedLevel == nil or entryLevel == tonumber(expectedLevel)
                    if levelMatches then
                        local keywordMatch = keywords ~= "" and dbot.isWordInString(lowered, keywords:lower())
                        local entryLower = tostring(entryName):lower()
                        local nameMatch = entryName ~= "" and entryLower:find(lowered, 1, true) ~= nil
                        if (keywordMatch or nameMatch) and entryLevel then
                            local score = 1
                            if nameMatch then
                                score = score + 2
                                if entryLower == lowered then
                                    score = score + 2
                                end
                            end
                            if keywordMatch then
                                score = score + 1
                            end
                            if expectedLevel ~= nil and entryLevel == tonumber(expectedLevel) then
                                score = score + 3
                            end
                            if score > bestScore then
                                bestScore = score
                                bestMatch = {
                                    level = entryLevel,
                                    name = entryName,
                                    itemType = itemType,
                                    keywords = keywords
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    if bestMatch then
        dbot.debug("inv.consume.add: persistence hit name=\"" .. tostring(bestMatch.name) ..
            "\" level=" .. tostring(bestMatch.level) .. " keywords=\"" ..
            tostring(bestMatch.keywords or "") .. "\" type=" .. tostring(bestMatch.itemType), "inv.consume")
        return bestMatch.level, bestMatch.name, bestMatch.itemType, bestMatch.keywords
    end

    return nil
end

function inv.consume.backfillFromPersistence()
    if type(inv.consume.table) ~= "table" then
        return false
    end

    local changed = false
    for _, entries in pairs(inv.consume.table) do
        if type(entries) == "table" then
            for _, entry in ipairs(entries) do
                local searchName = firstNonEmpty(entry.fullName, entry.name)
                local existingKeywords = tostring(entry.keywords or ""):gsub("^%s+", ""):gsub("%s+$", "")
                local needsKeywords = existingKeywords == ""
                local needsFullName = tostring(entry.fullName or "") == ""
                if searchName ~= "" and (needsKeywords or needsFullName) then
                    local level = tonumber(entry.level or "")
                    local _, persistentName, _, persistentKeywords =
                        lookupPersistentConsumable(searchName, level, nil)
                    if needsKeywords and persistentKeywords and tostring(persistentKeywords) ~= "" then
                        entry.keywords = tostring(persistentKeywords)
                        changed = true
                    end
                    if needsFullName and persistentName and tostring(persistentName) ~= "" then
                        entry.fullName = tostring(persistentName)
                        changed = true
                    end
                end
            end
        end
    end

    return changed
end

function inv.consume.init.atInstall()
    return DRL_RET_SUCCESS
end

function inv.consume.init.atActive()
    local retval = inv.consume.load()
    if retval ~= DRL_RET_SUCCESS then
        dbot.warn("inv.consume.init.atActive: failed to load consume data from storage: " ..
            dbot.retval.getString(retval))
    end
    return retval
end

function inv.consume.fini(doSaveState)
    if doSaveState then
        local retval = inv.consume.save()
        if retval ~= DRL_RET_SUCCESS and retval ~= DRL_RET_UNINITIALIZED then
            dbot.warn("inv.consume.fini: Failed to save inv.consume module data: " .. dbot.retval.getString(retval))
        end
    end
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Save/Load/Reset
----------------------------------------------------------------------------------------------------

function inv.consume.save()
    if inv.consume.table == nil then
        return inv.consume.reset()
    end
    local retval = DINV.database.saveModuleTable("consume", inv.consume.table)
    if retval ~= DRL_RET_SUCCESS and retval ~= DRL_RET_UNINITIALIZED then
        dbot.warn("inv.consume.save: Failed to save consume table: " .. dbot.retval.getString(retval))
    end
    return retval
end

function inv.consume.load()
    local value, retval = DINV.database.loadModuleTable("consume", inv.consume.reset)
    if value then inv.consume.table = value end
    if retval ~= DRL_RET_SUCCESS then
        dbot.warn("inv.consume.load: Failed to load consume rules from SQLite: " ..
            dbot.retval.getString(retval))
        return retval
    end

    if inv.consume.backfillFromPersistence and inv.consume.backfillFromPersistence() then
        local saveRet = inv.consume.save()
        if saveRet ~= DRL_RET_SUCCESS and saveRet ~= DRL_RET_UNINITIALIZED then
            dbot.warn("inv.consume.load: Failed to save consume table after persistence backfill: " ..
                dbot.retval.getString(saveRet))
        else
            dbot.debug("inv.consume.load: Backfilled consume keywords/fullName from persistence", "inv.consume")
        end
    end
    return retval
end

function inv.consume.reset()
    inv.consume.table = {
        heal = {
            { level = 1, name = "light relief", room = "32476", fullName = "light relief", storeKeyword = "relief" },
            { level = 20, name = "serious relief", room = "32476", fullName = "serious relief", storeKeyword = "relief" }
        },
        mana = {
            { level = 1, name = "lotus rush", room = "32476", fullName = "lotus rush" }
        },
        fly = {
            { level = 1, name = "griff", room = "32476", fullName = "griffon's blood" }
        }
    }
    local retval = inv.consume.save()
    if retval ~= DRL_RET_SUCCESS and retval ~= DRL_RET_UNINITIALIZED then
        dbot.warn("inv.consume.reset: Failed to save consumable data: " .. dbot.retval.getString(retval))
    end
    return retval
end

----------------------------------------------------------------------------------------------------
-- Add/Remove/Display
----------------------------------------------------------------------------------------------------

function inv.consume.add(typeName, itemName)
    local normalizedType = normalizeTypeName(typeName)
    local normalizedItem = sanitizeConsumeAliasName(itemName)

    if normalizedType == "" then
        dbot.warn("inv.consume.add: Missing type name")
        return DRL_RET_INVALID_PARAM
    end

    if normalizedItem == "" then
        dbot.warn("inv.consume.add: Missing item name")
        return DRL_RET_INVALID_PARAM
    end

    if inv.consume.addPkg ~= nil then
        dbot.info("Skipping request to add a consumable item: another request is in progress")
        return DRL_RET_BUSY
    end

    local roomId = tostring(dbot.gmcp.getRoomId() or "")
    local objId = nil
    local fullName = normalizedItem
    local itemLevel = nil

    if inv.items.table ~= nil and dbot.table.getNumEntries(inv.items.table) > 0 then
        local idArray, retval = inv.items.search(normalizedItem)
        if retval ~= DRL_RET_SUCCESS then
            dbot.warn("inv.consume.add: Failed to search inventory table: " .. dbot.retval.getString(retval))
            return retval
        end

        if idArray ~= nil and #idArray > 0 then
            if #idArray > 1 then
                dbot.warn("inv.consume.add: Multiple items matched \"" .. normalizedItem ..
                    "\"; using the first match")
            end
            objId = idArray[1]
            itemLevel = tonumber(inv.items.getStatField(objId, invStatFieldLevel) or "") or 0
            fullName = inv.items.getStatField(objId, invStatFieldName) or normalizedItem
            local entryKeywords = inv.items.getStatField(objId, invStatFieldKeywords)
            return inv.consume.addResolved(normalizedType, normalizedItem, itemLevel, roomId, fullName, entryKeywords)
        end
    end

    local cachedLevel, cachedName, cachedType, cachedKeywords =
        lookupPersistentConsumable(normalizedItem, nil, nil)
    if cachedLevel ~= nil and cachedType ~= nil then
        dbot.debug("inv.consume.add: cache match for \"" .. normalizedItem .. "\" name=\"" ..
            (cachedName or normalizedItem) .. "\" level=" .. tostring(cachedLevel) ..
            " type=" .. tostring(cachedType), "inv.consume")
        return inv.consume.addResolved(normalizedType, normalizedItem, cachedLevel, roomId,
            cachedName or normalizedItem, cachedKeywords)
    end

    if not tempTimer then
        dbot.warn("inv.consume.add: Inventory does not contain \"" .. normalizedItem ..
            "\" and tempTimer is unavailable for identification fallback")
        return DRL_RET_UNSUPPORTED
    end

    local preExistingObjIds = {}
    for existingObjId, _ in pairs(inv.items.table or {}) do
        preExistingObjIds[tostring(existingObjId)] = true
    end

    inv.consume.addPkg = {
        type = normalizedType,
        name = normalizedItem,
        room = roomId,
        objId = nil,
        startTime = os.time(),
        timeoutSec = 15,
        buyIssued = false,
        identifyIssued = false,
        preExistingObjIds = preExistingObjIds
    }

    dbot.debug("inv.consume.add: buy/identify fallback for \"" .. normalizedItem .. "\" in room " ..
        (roomId or "unknown"), "inv.consume")

    send("buy " .. normalizedItem)
    inv.consume.addPkg.buyIssued = true
    tempTimer(0.5, inv.consume.addCR)

    return DRL_RET_SUCCESS
end

function inv.consume.addResolved(typeName, itemName, itemLevel, roomId, fullName, keywords)
    if inv.consume.table[typeName] == nil then
        inv.consume.table[typeName] = {}
    end

    for _, entry in ipairs(inv.consume.table[typeName]) do
        if entry.level == itemLevel and namesMatch(entry.name, itemName) then
            dbot.note("Skipping addition of consumable item \"" .. itemName .. "\" of type \"" ..
                typeName .. "\": item already exists")
            return DRL_RET_SUCCESS
        end
    end

    table.insert(inv.consume.table[typeName], {
        level = itemLevel,
        name = itemName,
        room = roomId,
        fullName = fullName or itemName,
        keywords = tostring(keywords or "")
    })
    table.sort(inv.consume.table[typeName], function(v1, v2)
        return (v1.level or 0) < (v2.level or 0)
    end)

    inv.consume.save()
    inv.consume.notifyWindowChanged()
    dbot.info("Added \"" .. itemName .. "\" to consumable type \"" .. typeName .. "\"")
    return DRL_RET_SUCCESS
end

local function detectBoughtConsumableObjId(pkg)
    if not pkg or not inv.items or not inv.items.table then
        return nil
    end

    local found = nil
    for objId, _ in pairs(inv.items.table) do
        local idKey = tostring(objId)
        local wasPresent = pkg.preExistingObjIds and pkg.preExistingObjIds[idKey]
        if not wasPresent then
            local itemType = tostring(inv.items.getStatField(objId, invStatFieldType) or ""):lower()
            if itemType == "potion" or itemType == "pill" or itemType == "scroll" then
                found = objId
            end
        end
    end

    return found
end

function inv.consume.addCR()
    local pkg = inv.consume.addPkg
    if pkg == nil then
        return DRL_RET_INTERNAL_ERROR
    end

    local cachedLevel, cachedName, cachedType, cachedKeywords =
        lookupPersistentConsumable(pkg.name, nil, nil)
    if cachedLevel ~= nil and cachedType ~= nil then
        dbot.debug("inv.consume.addCR: persistence hit after identify for \"" .. pkg.name ..
            "\" level=" .. tostring(cachedLevel), "inv.consume")
        inv.consume.addPkg = nil
        return inv.consume.addResolved(pkg.type, pkg.name, cachedLevel, pkg.room, cachedName or pkg.name, cachedKeywords)
    end

    if inv.items.table ~= nil and dbot.table.getNumEntries(inv.items.table) > 0 then
        local idArray, retval = inv.items.search(pkg.name)
        if retval ~= DRL_RET_SUCCESS then
            dbot.warn("inv.consume.addCR: Failed to search inventory table: " .. dbot.retval.getString(retval))
            inv.consume.addPkg = nil
            return retval
        end

        if idArray ~= nil and #idArray > 0 then
            if #idArray > 1 then
                dbot.warn("inv.consume.addCR: Multiple items matched \"" .. pkg.name ..
                    "\"; using the first match")
            end
            pkg.objId = idArray[1]
        end

        if not pkg.objId then
            pkg.objId = detectBoughtConsumableObjId(pkg)
            if pkg.objId then
                dbot.debug("inv.consume.addCR: detected newly bought consumable objId=" .. tostring(pkg.objId) ..
                    " for \"" .. pkg.name .. "\"", "inv.consume")
            end
        end
    end

    local elapsed = os.time() - (pkg.startTime or os.time())
    if elapsed > pkg.timeoutSec then
        dbot.warn("inv.consume.addCR: Timed out waiting for identify on \"" .. pkg.name .. "\"")
        inv.consume.addPkg = nil
        return DRL_RET_TIMEOUT
    end

    if pkg.objId then
        local item = inv.items.getItem(pkg.objId)
        local identifyLevel = item and item.stats and item.stats.identifyLevel or nil
        local itemLevel = tonumber(inv.items.getStatField(pkg.objId, invStatFieldLevel) or "")
        local fullName = inv.items.getStatField(pkg.objId, invStatFieldName) or pkg.name
        local entryKeywords = inv.items.getStatField(pkg.objId, invStatFieldKeywords)

        if identifyLevel == invIdLevelFull and itemLevel ~= nil then
            dbot.debug("inv.consume.addCR: identify complete for \"" .. pkg.name ..
                "\" level=" .. tostring(itemLevel), "inv.consume")
            inv.consume.addPkg = nil
            return inv.consume.addResolved(pkg.type, pkg.name, itemLevel, pkg.room, fullName, entryKeywords)
        end

        if not pkg.identifyIssued then
            local retval = inv.items.buildSingleItem(pkg.objId, "consume-add")
            if retval == DRL_RET_SUCCESS then
                pkg.identifyIssued = true
                dbot.debug("inv.consume.addCR: forced single-item identify for \"" .. pkg.name ..
                    "\" objId=" .. tostring(pkg.objId), "inv.consume")
            end
        end
    end

    if tempTimer then
        tempTimer(0.5, inv.consume.addCR)
        return DRL_RET_SUCCESS
    end

    dbot.warn("inv.consume.addCR: tempTimer unavailable; aborting")
    inv.consume.addPkg = nil
    return DRL_RET_UNSUPPORTED
end

function inv.consume.addType(typeName)
    local normalizedType = normalizeTypeName(typeName)
    if normalizedType == "" then
        dbot.warn("inv.consume.addType: Missing type name")
        return DRL_RET_INVALID_PARAM
    end

    if inv.consume.table[normalizedType] ~= nil then
        dbot.note('Consumable type "' .. normalizedType .. '" already exists')
        return DRL_RET_SUCCESS
    end

    inv.consume.table[normalizedType] = {}
    inv.consume.save()
    inv.consume.notifyWindowChanged()
    dbot.info('Added empty consumable type "' .. normalizedType .. '"')
    return DRL_RET_SUCCESS
end

function inv.consume.removeType(typeName)
    local normalizedType = normalizeTypeName(typeName)
    if normalizedType == "" then
        dbot.warn("inv.consume.removeType: Missing type name")
        return DRL_RET_INVALID_PARAM
    end

    if inv.consume.table[normalizedType] == nil then
        dbot.info('Type "' .. normalizedType .. '" is not in the consumable table')
        return DRL_RET_MISSING_ENTRY
    end

    inv.consume.table[normalizedType] = nil
    inv.consume.save()
    inv.consume.notifyWindowChanged()
    dbot.note('Removed consumable type "' .. normalizedType .. '"')
    return DRL_RET_SUCCESS
end

function inv.consume.remove(typeName, itemName)
    local normalizedType = normalizeTypeName(typeName)
    local normalizedItem = sanitizeConsumeAliasName(itemName)

    if normalizedType == "" then
        dbot.warn("inv.consume.remove: Missing type name")
        return DRL_RET_INVALID_PARAM
    end

    if inv.consume.table == nil then
        dbot.info("Consumable table is empty")
        return DRL_RET_MISSING_ENTRY
    end

    local function removeEntryFromType(targetType, targetName)
        if targetType == nil or inv.consume.table[targetType] == nil then
            return DRL_RET_MISSING_ENTRY
        end

        if targetName == "" then
            inv.consume.table[targetType] = nil
            inv.consume.save()
            inv.consume.notifyWindowChanged()
            return DRL_RET_SUCCESS
        end

        for i, entry in ipairs(inv.consume.table[targetType]) do
            if namesMatch(entry.name, targetName) or namesMatch(entry.fullName, targetName) then
                dbot.note('Removed "' .. (entry.name or targetName) .. '" from "' ..
                    targetType .. '" consumable table')
                table.remove(inv.consume.table[targetType], i)
                inv.consume.save()
                inv.consume.notifyWindowChanged()
                return DRL_RET_SUCCESS
            end
        end

        return DRL_RET_MISSING_ENTRY
    end

    if inv.consume.table[normalizedType] ~= nil then
        local retval = removeEntryFromType(normalizedType, normalizedItem)
        if retval == DRL_RET_MISSING_ENTRY then
            dbot.info('Skipping removal of consumable "' .. (normalizedItem ~= "" and normalizedItem or "all") ..
                '": item is not in consumable table')
        end
        return retval
    end

    local nameOnlyQuery = normalizedItem ~= "" and (normalizedType .. " " .. normalizedItem) or normalizedType
    local loweredQuery = nameOnlyQuery:lower()

    for consumeType, entries in pairs(inv.consume.table) do
        for i, entry in ipairs(entries) do
            local entryName = tostring(entry.name or ""):lower()
            local entryFull = tostring(entry.fullName or ""):lower()
            if entryName == loweredQuery or entryFull == loweredQuery then
                dbot.note('Removed "' .. (entry.name or nameOnlyQuery) .. '" from "' ..
                    consumeType .. '" consumable table')
                table.remove(entries, i)
                inv.consume.save()
                inv.consume.notifyWindowChanged()
                return DRL_RET_SUCCESS
            end
        end
    end

    dbot.info('Type "' .. normalizedType .. '" is not in the consumable table')
    return DRL_RET_MISSING_ENTRY
end

function inv.consume.getSortedTypes()
    local sortedTypes = {}
    for itemType, _ in pairs(inv.consume.table or {}) do
        table.insert(sortedTypes, itemType)
    end
    local priority = { heal = 1, mana = 2 }
    table.sort(sortedTypes, function(left, right)
        local leftPriority = priority[tostring(left):lower()] or 100
        local rightPriority = priority[tostring(right):lower()] or 100
        if leftPriority ~= rightPriority then
            return leftPriority < rightPriority
        end
        return tostring(left):lower() < tostring(right):lower()
    end)
    return sortedTypes
end

function inv.consume.display(typeName)
    local normalizedType = normalizeTypeName(typeName)
    if inv.config and inv.config.isConsumeWindowEnabled
        and inv.config.isConsumeWindowEnabled()
        and inv.consumeWindow and inv.consumeWindow.show then
        local shown, showErr = inv.consumeWindow.show(normalizedType)
        if shown then
            return DRL_RET_SUCCESS
        end
        dbot.warn("Unable to show the consumables miniwindow; using console rows: " ..
            tostring(showErr or "unknown error"))
    end
    return inv.consume.displayConsole(normalizedType)
end

function inv.consume.displayConsole(typeName)
    local normalizedType = normalizeTypeName(typeName)
    local numEntries = 0
    local isOwned = normalizedType == "owned"

    if normalizedType ~= "" and not isOwned then
        numEntries = inv.consume.displayType(normalizedType, isOwned)
    else
        for _, itemType in ipairs(inv.consume.getSortedTypes()) do
            numEntries = numEntries + inv.consume.displayType(itemType, isOwned)
        end
    end

    if numEntries == 0 then
        dbot.print("@W  No items of type \"" .. (normalizedType ~= "" and normalizedType or "all") ..
            "\" are in the consumable table@w")
        return DRL_RET_MISSING_ENTRY
    end

    return DRL_RET_SUCCESS
end

function inv.consume.displayType(typeName, isOwned)
    local numEntries = 0
    if inv.consume.table == nil or typeName == nil or typeName == "" or inv.consume.table[typeName] == nil then
        dbot.warn("inv.consume.displayType: Type \"" .. (typeName or "nil") ..
            "\" is not in the consumable table")
        return numEntries
    end

    local header = string.format("\n@W@C%-12s@W  Level  # Avail  Name", (typeName or "nil"))
    local didPrintHeader = false

    for entryIndex, entry in ipairs(inv.consume.table[typeName]) do
        local count = inv.consume.countEntry(entry)
        if not isOwned or count > 0 then
            if not didPrintHeader then
                dbot.print(header)
                didPrintHeader = true
            end

            local buyOne = string.format("inv.consume.buyExact(%q, %d, 1, nil, %q)",
                tostring(typeName), entryIndex, "console")
            local buyTen = string.format("inv.consume.buyExact(%q, %d, 10, nil, %q)",
                tostring(typeName), entryIndex, "console")
            local buyFifty = string.format("inv.consume.buyExact(%q, %d, 50, nil, %q)",
                tostring(typeName), entryIndex, "console")
            local travel = string.format("inv.consume.travelExact(%q, %d, %q)",
                tostring(typeName), entryIndex, "console")
            local displayName = dbot.stripColors(tostring(entry.name or "nil"))
            displayName = displayName:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")

            if cecho and cechoLink then
                cecho("  ")
                cechoLink("<cyan>x1 <reset>", buyOne, "Buy 1 " .. displayName, true)
                cechoLink("<cyan>x10<reset>", buyTen, "Buy 10 " .. displayName, true)
                cecho(" ")
                cechoLink("<cyan>x50<reset>", buyFifty, "Buy 50 " .. displayName, true)
                cecho(string.format("    %3d     ", tonumber(entry.level) or 0))
                cecho(count > 0 and "<magenta>" or "<white>")
                cecho(string.format("%4d<reset>  ", count))
                cechoLink("<white>" .. displayName .. "<reset>", travel,
                    "Travel to the vendor for " .. displayName, true)
                cecho("\n")
            else
                dbot.print(string.format("  x1  x10  x50    %3d     %4d  %s",
                    tonumber(entry.level) or 0, count, tostring(entry.name or "nil")))
            end
            numEntries = numEntries + 1
        end
    end

    return numEntries
end

----------------------------------------------------------------------------------------------------
-- Buy
----------------------------------------------------------------------------------------------------

local function startMapperTravel(room)
    if snd and snd.mapper and type(snd.mapper.xrt) == "function" then
        local travelOk, travelResult = pcall(snd.mapper.xrt, tostring(room))
        if not travelOk or travelResult == false then
            return false, tostring(not travelOk and travelResult or "route was not started")
        end
        return true
    end
    if type(expandAlias) == "function" then
        expandAlias("xrt " .. tostring(room), false)
        return true
    end
    return false, "Aardwolf mapper xrt is unavailable"
end

local function finishWindowAction(pkg, succeeded)
    if pkg and pkg.source == "window" and inv.consumeWindow
        and inv.consumeWindow.completeTravel then
        inv.consumeWindow.completeTravel(succeeded == true)
    end
end

function inv.consume.startBuyEntry(entry, numItems, containerName, source)
    if type(entry) ~= "table" then
        dbot.info("The selected consumable is no longer in the consumable table")
        return DRL_RET_MISSING_ENTRY
    end
    if inv.consume.buyPkg ~= nil then
        dbot.info("Skipping consumable purchase: another request is in progress")
        return DRL_RET_BUSY
    end

    numItems = math.max(1, math.floor(tonumber(numItems or "") or 1))
    local normalizedContainerName = tostring(containerName or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if normalizedContainerName == "" then
        normalizedContainerName = inv.consume.getAutoPotionContainerId() or ""
        if normalizedContainerName ~= "" then
            dbot.debug("inv.consume.buy: Using auto potion container " .. normalizedContainerName, "inv.consume")
        end
    end

    inv.consume.buyPkg = {
        room = entry.room,
        itemName = entry.name,
        fullName = entry.fullName,
        keywords = entry.keywords,
        storeKeyword = getPreferredStoreTarget(entry),
        numItems = numItems,
        containerName = normalizedContainerName,
        timeoutSec = 10,
        source = source,
    }

    if source == "window" and inv.consumeWindow and inv.consumeWindow.beginTravel then
        inv.consumeWindow.beginTravel(entry.room, "buy")
    end

    return inv.consume.buyCR()
end

function inv.consume.buyExact(typeName, entryIndex, numItems, containerName, source)
    if not (inv.init and inv.init.initializedActive) then
        dbot.info("Skipping consumable purchase: plugin is not yet initialized")
        return DRL_RET_UNINITIALIZED
    end
    if dbot.gmcp and dbot.gmcp.statePreventsActions and dbot.gmcp.statePreventsActions() then
        dbot.info("Skipping consumable purchase: character's state does not allow actions")
        return DRL_RET_NOT_ACTIVE
    end
    local entry = inv.consume.getEntry(typeName, entryIndex)
    if not entry then
        dbot.info("The selected consumable is no longer in the consumable table")
        inv.consume.notifyWindowChanged()
        return DRL_RET_MISSING_ENTRY
    end
    return inv.consume.startBuyEntry(entry, numItems, containerName, source)
end

function inv.consume.travelExact(typeName, entryIndex, source)
    if not (inv.init and inv.init.initializedActive) then
        dbot.info("Skipping consumable travel: plugin is not yet initialized")
        return DRL_RET_UNINITIALIZED
    end
    if dbot.gmcp and dbot.gmcp.statePreventsActions and dbot.gmcp.statePreventsActions() then
        dbot.info("Skipping consumable travel: character's state does not allow actions")
        return DRL_RET_NOT_ACTIVE
    end
    local entry = inv.consume.getEntry(typeName, entryIndex)
    if not entry then
        dbot.info("The selected consumable is no longer in the consumable table")
        inv.consume.notifyWindowChanged()
        return DRL_RET_MISSING_ENTRY
    end

    local room = tonumber(entry.room or "")
    if not room or room == 0 then
        dbot.warn("The selected consumable has no vendor room")
        return DRL_RET_INVALID_PARAM
    end

    if source == "window" and inv.consumeWindow and inv.consumeWindow.beginTravel then
        inv.consumeWindow.beginTravel(room, "travel")
    end
    if tonumber(dbot.gmcp.getRoomId() or "") == room then
        finishWindowAction({ source = source }, true)
        return DRL_RET_SUCCESS
    end

    local traveled, travelErr = startMapperTravel(room)
    if not traveled then
        dbot.warn("Unable to travel to the consumable vendor: " .. tostring(travelErr))
        finishWindowAction({ source = source }, false)
        return DRL_RET_UNSUPPORTED
    end
    return DRL_RET_SUCCESS
end

function inv.consume.buy(typeName, numItems, containerName)
    local normalizedType = normalizeTypeName(typeName)
    if normalizedType == "" then
        dbot.warn("inv.consume.buy: Missing type name")
        return DRL_RET_INVALID_PARAM
    end
    if inv.consume.table[normalizedType] == nil then
        dbot.info("No items of type \"" .. normalizedType .. "\" are in the consumable table")
        return DRL_RET_MISSING_ENTRY
    end

    local effectiveLevel = dbot.gmcp.getLevel()
    if dbot.gmcp.getWearableLevel then
        effectiveLevel = dbot.gmcp.getWearableLevel()
    end
    local bestEntry = nil
    for _, entry in ipairs(inv.consume.table[normalizedType]) do
        if (entry.level or 0) <= effectiveLevel then
            bestEntry = entry
        end
    end
    if bestEntry == nil then
        dbot.info("No items of type \"" .. normalizedType .. "\" are available at level " .. effectiveLevel)
        return DRL_RET_MISSING_ENTRY
    end
    return inv.consume.startBuyEntry(bestEntry, numItems, containerName, nil)
end

function inv.consume.getAutoPotionContainerId()
    if not (inv and inv.items and inv.items.table) then
        return nil
    end

    for objId, _ in pairs(inv.items.table) do
        local organizeQuery = tostring(inv.items.getStatField(objId, invQueryKeyOrganize) or "")
        local normalizedQuery = " " .. organizeQuery:lower() .. " "
        if organizeQuery ~= "" and normalizedQuery:find(" type%s+potion[%s|]", 1) then
            return tostring(objId)
        end
    end

    return nil
end

local function sendConsumeCommands(commandArray)
    if inv.items and inv.items.sendActionCommands then
        inv.items.sendActionCommands(commandArray)
    else
        for _, cmd in ipairs(commandArray) do
            send(cmd)
        end
    end
    return DRL_RET_SUCCESS
end

function inv.consume.buyCR()
    local pkg = inv.consume.buyPkg
    if pkg == nil then
        return DRL_RET_INTERNAL_ERROR
    end

    local room = tonumber(pkg.room or "")
    if room == nil or room == 0 then
        dbot.warn("inv.consume.buyCR: Target room is missing")
        inv.consume.buyPkg = nil
        finishWindowAction(pkg, false)
        return DRL_RET_INVALID_PARAM
    end

    local currentRoom = tonumber(dbot.gmcp.getRoomId() or "")
    if currentRoom == room then
        local commands = { "buy " .. pkg.numItems .. " " .. pkg.itemName }
        if pkg.containerName ~= nil and pkg.containerName ~= "" then
            local storeTarget = tostring(pkg.storeKeyword or "")
            if storeTarget ~= "" and storeTarget:match("^[%w_%-]+$") then
                table.insert(commands, "put all." .. storeTarget .. " " .. pkg.containerName)
            else
                table.insert(commands, "put all.'" .. pkg.itemName .. "' " .. pkg.containerName)
            end
        end
        sendConsumeCommands(commands)
        inv.consume.buyPkg = nil
        finishWindowAction(pkg, true)
        return DRL_RET_SUCCESS
    end

    if not pkg.travelIssued then
        pkg.travelIssued = true
        pkg.startTime = os.time()
        dbot.debug("Running to \"" .. pkg.room .. "\" to buy \"" .. pkg.numItems ..
            "\" of \"" .. pkg.itemName .. "\"", "inv.consume")
        local traveled, travelErr = startMapperTravel(room)
        if not traveled then
            dbot.warn("inv.consume.buyCR: mapper travel failed: " .. tostring(travelErr))
            inv.consume.buyPkg = nil
            finishWindowAction(pkg, false)
            return DRL_RET_UNSUPPORTED
        end
    end

    if pkg.startTime and (os.time() - pkg.startTime) > pkg.timeoutSec then
        dbot.warn("inv.consume.buyCR: Timed out running to room " .. room)
        inv.consume.buyPkg = nil
        finishWindowAction(pkg, false)
        return DRL_RET_TIMEOUT
    end

    if tempTimer then
        tempTimer(0.5, inv.consume.buyCR)
        return DRL_RET_SUCCESS
    end

    dbot.warn("inv.consume.buyCR: tempTimer unavailable; aborting")
    inv.consume.buyPkg = nil
    finishWindowAction(pkg, false)
    return DRL_RET_UNSUPPORTED
end

----------------------------------------------------------------------------------------------------
-- Get/Use
----------------------------------------------------------------------------------------------------

function inv.consume.get(typeName, size, containerId)
    local normalizedType = normalizeTypeName(typeName)
    local curLevel = dbot.gmcp.getLevel()
    local effectiveLevel = curLevel
    if dbot.gmcp.getWearableLevel then
        effectiveLevel = dbot.gmcp.getWearableLevel()
    end

    if normalizedType == "" then
        dbot.warn("inv.consume.get: type name is missing")
        return nil, nil, DRL_RET_INVALID_PARAM
    end

    if inv.consume.table[normalizedType] == nil then
        dbot.warn("inv.consume.get: no consumables of type \"" .. normalizedType .. "\" are available")
        return nil, nil, DRL_RET_INVALID_PARAM
    end

    local preferredLocation
    local normalizedContainer = inv.items.normalizeContainerId(containerId)
    if normalizedContainer ~= nil then
        preferredLocation = normalizedContainer
    else
        preferredLocation = invItemLocInventory
    end

    dbot.debug("inv.consume.get: type=\"" .. normalizedType .. "\" size=\"" .. tostring(size) ..
        "\" containerId=" .. tostring(containerId) .. " preferredLocation=" .. tostring(preferredLocation) ..
        " curLevel=" .. tostring(curLevel) .. " effectiveLevel=" .. tostring(effectiveLevel), "inv.consume")

    local typeTable
    if size == drlConsumeBig then
        typeTable = dbot.table.getCopy(inv.consume.table[normalizedType])
        table.sort(typeTable, function(v1, v2) return (v1.level or 0) > (v2.level or 0) end)
    elseif size == drlConsumeSmall then
        typeTable = inv.consume.table[normalizedType]
    else
        dbot.warn("inv.consume.get: invalid size parameter")
        return nil, nil, DRL_RET_INVALID_PARAM
    end

    for _, entry in pairs(typeTable) do
        local finalId = nil
        local preferredId = nil
        local count = 0
        local entryLevel = entry.level or 0
        local searchTerm = firstNonEmpty(entry.name, entry.key, entry.fullName)

        dbot.debug("inv.consume.get: checking entry level=" .. tostring(entryLevel) ..
            " key=\"" .. tostring(searchTerm) .. "\"", "inv.consume")

        -- Every tracked object is checked against this exact configured entry.
        -- There is deliberately no fallback that broadens the match when the
        -- configured consumable is unavailable.
        for objId, _ in pairs(inv.items.table or {}) do
            local container = inv.items.getStatField(objId, invStatFieldContainer)
            local isIgnored = container ~= nil and container ~= "" and inv.config.isIgnored(container)
            if not isIgnored and itemMatchesConsumeEntry(entry, objId) then
                local location = inv.items.getStatField(objId, invStatFieldLocation)
                count = count + 1
                if preferredId == nil and location == preferredLocation then
                    preferredId = objId
                else
                    finalId = objId
                end
            end
        end

        if preferredId ~= nil then
            finalId = preferredId
        end

        local countColor
        if count > 50 then
            countColor = "@G"
        elseif count > 20 then
            countColor = "@Y"
        else
            countColor = "@R"
        end

        if finalId ~= nil and (entry.level or 0) <= effectiveLevel then
            dbot.info("(" .. countColor .. count .. " available@W) " ..
                "Consuming L" .. (entry.level or 0) .. " \"@C" .. normalizedType .. "@W\" @Y" ..
                (inv.items.getStatField(finalId, invStatFieldName) or "") .. "@W")
            return finalId, searchTerm, DRL_RET_SUCCESS
        end

        if finalId ~= nil and (entry.level or 0) > effectiveLevel then
            dbot.debug("inv.consume.get: matched L" .. tostring(entryLevel) ..
                " but effectiveLevel=" .. tostring(effectiveLevel) .. " blocks use", "inv.consume")
        else
            dbot.debug("inv.consume.get: no configured consumable match for L" .. tostring(entryLevel) ..
                " key=\"" .. tostring(searchTerm) .. "\" (count=" .. tostring(count) .. ")", "inv.consume")
        end
    end

    return nil, nil, DRL_RET_MISSING_ENTRY
end

function inv.consume.use(typeName, size, numItems, containerName)
    local normalizedType = normalizeTypeName(typeName)
    if normalizedType == "" then
        dbot.warn("inv.consume.use: Missing type name")
        return DRL_RET_INVALID_PARAM
    end

    numItems = tonumber(numItems or "") or 1
    if numItems < 1 then
        numItems = 1
    end

    if inv.consume.usePkg ~= nil then
        dbot.info("Skipping request to use \"" .. normalizedType .. "\": another request is in progress")
        return DRL_RET_BUSY
    end

    if size ~= drlConsumeBig and size ~= drlConsumeSmall then
        dbot.warn("inv.consume.use: size must be either \"" .. drlConsumeBig .. "\" or \"" ..
            drlConsumeSmall .. "\"")
        return DRL_RET_INVALID_PARAM
    end

    inv.consume.usePkg = {
        numItems = numItems,
        typeName = normalizedType,
        size = size,
        container = containerName or ""
    }

    return inv.consume.useCR()
end

function inv.consume.findContainer(containerName)
    if containerName == nil or containerName == "" then
        return nil
    end

    local numeric = tonumber(containerName)
    if numeric then
        local objId = tostring(numeric)
        local itemType = inv.items.getStatField(objId, invStatFieldType) or ""
        if itemType == "Container" then
            return objId
        end
        dbot.warn("Object " .. containerName .. " is not a container (type: " .. itemType .. ")")
        return nil
    end

    local relativeIndex, relativeName = inv.items.convertRelative(containerName)
    local matches = {}
    for objId, _ in pairs(inv.items.table or {}) do
        local itemType = inv.items.getStatField(objId, invStatFieldType) or ""
        if itemType == "Container" then
            local itemName = inv.items.getStatField(objId, invStatFieldName) or ""
            if string.find(string.lower(itemName), string.lower(relativeName), 1, true) then
                table.insert(matches, { id = tostring(objId), name = itemName })
            end
        end
    end

    if #matches == 0 then
        dbot.warn("Container \"" .. containerName .. "\" not found in inventory")
        return nil
    end

    table.sort(matches, function(a, b)
        local nameA = string.lower(a.name or "")
        local nameB = string.lower(b.name or "")
        if nameA == nameB then
            return tonumber(a.id or 0) < tonumber(b.id or 0)
        end
        return nameA < nameB
    end)

    if relativeIndex then
        if matches[relativeIndex] then
            return matches[relativeIndex].id
        end
        dbot.warn("Container \"" .. containerName .. "\" did not have a unique match")
        return nil
    end

    if #matches > 1 then
        dbot.warn("Container \"" .. containerName .. "\" did not have a unique match")
        return nil
    end

    return matches[1].id
end

function inv.consume.useCR()
    local pkg = inv.consume.usePkg
    if pkg == nil or pkg.size == nil or pkg.numItems == nil or pkg.typeName == nil then
        dbot.error("inv.consume.useCR: usePkg is nil or contains nil components")
        return DRL_RET_INTERNAL_ERROR
    end

    dbot.debug("inv.consume.useCR: type=\"" .. tostring(pkg.typeName) .. "\" size=\"" ..
        tostring(pkg.size) .. "\" numItems=" .. tostring(pkg.numItems) ..
        " container=\"" .. tostring(pkg.container) .. "\"", "inv.consume")

    if pkg.numItems > drlConsumeMaxConsecutiveItems then
        dbot.note("Capping number of \"" .. pkg.size .. "\" items to consume to " ..
            drlConsumeMaxConsecutiveItems .. " in one burst")
        pkg.numItems = drlConsumeMaxConsecutiveItems
    end

    local containerId = nil
    if pkg.container ~= nil and pkg.container ~= "" then
        containerId = inv.consume.findContainer(pkg.container)
        if containerId == nil then
            dbot.warn("Container \"" .. pkg.container ..
                "\" did not have a unique match: no preferred container will be used for consume request")
        else
            dbot.debug("inv.consume.useCR: resolved container \"" .. pkg.container ..
                "\" to objId=" .. tostring(containerId), "inv.consume")
        end
    end

    local commandArray = {}
    local retval = DRL_RET_SUCCESS
    for i = 1, pkg.numItems do
        local objId
        objId, _, retval = inv.consume.get(pkg.typeName, pkg.size, containerId)
        if objId ~= nil and retval == DRL_RET_SUCCESS then
            retval = inv.consume.useItem(objId, commandArray)
            if retval ~= DRL_RET_SUCCESS then
                dbot.warn("inv.consume.useCR: Failed to consume item: " .. dbot.retval.getString(retval))
                break
            end
        end

        if retval ~= DRL_RET_SUCCESS then
            dbot.debug("inv.consume.useCR: stopping consume loop at index " .. tostring(i) ..
                " retval=" .. dbot.retval.getString(retval), "inv.consume")
            break
        end
    end

    if commandArray ~= nil then
        if #commandArray > 0 then
            sendConsumeCommands(commandArray)
        elseif retval == DRL_RET_MISSING_ENTRY then
            dbot.note("No available items match the configured \"" .. pkg.typeName ..
                "\" consumable list; nothing was consumed")
        else
            dbot.note("Skipping request to consume items: no items matching the request were found")
        end
    end

    inv.consume.usePkg = nil
    return retval
end

function inv.consume.useItem(objId, commandArray)
    local itemType = inv.items.getStatField(objId, invStatFieldType) or ""
    local consumeCmd

    if itemType == "Potion" then
        consumeCmd = "quaff"
    elseif itemType == "Pill" then
        consumeCmd = "eat"
    elseif itemType == "Scroll" then
        consumeCmd = "recite"
    elseif itemType == "Staff" or itemType == "Stave" or itemType == "Wand" then
        consumeCmd = "hold"
    else
        dbot.warn("inv.consume.useItem: Unsupported item type \"" .. itemType .. "\"")
        return DRL_RET_UNSUPPORTED
    end

    local objectId = tostring(objId or "")
    if objectId == "" then
        dbot.warn("inv.consume.useItem: Missing object id")
        return DRL_RET_INVALID_PARAM
    end

    local location = tostring(inv.items.getStatField(objId, invStatFieldLocation) or "")
    if location ~= "" and location ~= invItemLocInventory then
        table.insert(commandArray, "get " .. objectId .. " " .. location)
    end

    if commandArray ~= nil then
        table.insert(commandArray, consumeCmd .. " " .. objectId)
    end

    -- Never update persistence optimistically from consume; rely on invitem/invmon events.
    return DRL_RET_SUCCESS
end

dbot.debug("inv.consume module loaded", "inv.consume")
