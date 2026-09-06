----------------------------------------------------------------------------------------------------
-- DINV Public API
-- Stable, silent integration surface for other Mudlet scripts.
----------------------------------------------------------------------------------------------------

DINV = DINV or {}
DINV.api = DINV.api or {}
DINV.actions = DINV.actions or {}

local api = DINV.api
local actions = DINV.actions

api.version = 5
api.mode = "controlled-actions"
actions.version = 1
api.revision = tonumber(api.revision) or 0
api.history = api.history or {}
api.historyLimit = tonumber(api.historyLimit) or 250
api.subscriptions = {}
api.nextSubscriptionId = 0
api.pendingRequests = {}
api.nextRequestId = 0
api.readyRaised = false

local SUMMARY_FIELDS = {
    "id", "name", "colorName", "normalizedName", "type", "level", "keywords", "flags",
    "location", "container", "lastStored", "worn", "wearable", "timer", "owner", "clan",
    "material", "weight", "worth", "score", "identifyLevel",
    "charges", "chargeKnown", "chargeDirty", "chargeSource", "chargeObservedAt", "chargeRevision",
    "knownKeySourceRoom", "knownKeySourceArea", "knownKeyKeywordSignature", "knownKeyKnowledgeSource",
}

local FIELD_ALIASES = {
    id = { "id" },
    name = { "name" },
    colorName = { "colorName", "colorname", "coloredName" },
    type = { "type" },
    typeNum = { "typeNum", "typenum" },
    level = { "level" },
    keywords = { "keywords", "keyword", "key" },
    flags = { "flags", "flag" },
    location = { "location", "loc" },
    container = { "container" },
    lastStored = { "lastStored", "laststored" },
    worn = { "worn" },
    wearable = { "wearable" },
    timer = { "timer" },
    owner = { "owner" },
    clan = { "clan" },
    material = { "material" },
    weight = { "weight" },
    worth = { "worth" },
    score = { "score" },
    identifyLevel = { "identifyLevel", "idlevel" },
    damtype = { "damtype", "inflicts" },
    weapontype = { "weapontype" },
    avedam = { "avedam" },
    specials = { "specials" },
    spells = { "spells" },
    spelluses = { "spelluses" },
    spelllevel = { "spelllevel" },
    charges = { "charges" },
    chargeKnown = { "chargeKnown", "chargeknown" },
    chargeDirty = { "chargeDirty", "chargedirty" },
    chargeSource = { "chargeSource", "chargesource" },
    chargeObservedAt = { "chargeObservedAt", "chargeobservedat" },
    chargeRevision = { "chargeRevision", "chargerevision" },
    knownKeySourceRoom = { "knownKeySourceRoom" },
    knownKeySourceArea = { "knownKeySourceArea" },
    knownKeyKeywordSignature = { "knownKeyKeywordSignature" },
    knownKeyKnowledgeSource = { "knownKeyKnowledgeSource" },
    servings = { "servings" },
    liquid = { "liquid" },
    destination = { "destination" },
    leadsto = { "leadsto" },
    enchants = { "enchants" },
    capacity = { "capacity" },
    holding = { "holding" },
    affects = { "affects" },
}

local RESULT_CODES = {
    [DRL_RET_SUCCESS or 0] = "OK",
    [DRL_RET_UNINITIALIZED or -1] = "NOT_READY",
    [DRL_RET_INVALID_PARAM or -2] = "INVALID_ARGUMENT",
    [DRL_RET_MISSING_ENTRY or -3] = "NOT_FOUND",
    [DRL_RET_BUSY or -4] = "BUSY",
    [DRL_RET_UNSUPPORTED or -5] = "UNSUPPORTED",
    [DRL_RET_TIMEOUT or -6] = "TIMEOUT",
    [DRL_RET_HALTED or -7] = "HALTED",
    [DRL_RET_INTERNAL_ERROR or -8] = "INTERNAL_ERROR",
    [DRL_RET_UNIDENTIFIED or -9] = "UNIDENTIFIED",
    [DRL_RET_NOT_ACTIVE or -10] = "NOT_ACTIVE",
    [DRL_RET_IN_COMBAT or -11] = "IN_COMBAT",
}

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function tableCount(value)
    local count = 0
    for _ in pairs(value or {}) do
        count = count + 1
    end
    return count
end

local function deepCopy(value, seen)
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
        copy[deepCopy(key, seen)] = deepCopy(child, seen)
    end
    return copy
end

local function deepEqual(left, right, seen)
    if rawequal(left, right) then
        return true
    end
    if type(left) ~= type(right) then
        return false
    end
    if type(left) ~= "table" then
        return left == right
    end

    seen = seen or {}
    seen[left] = seen[left] or {}
    if seen[left][right] then
        return true
    end
    seen[left][right] = true

    for key, value in pairs(left) do
        if not deepEqual(value, right[key], seen) then
            return false
        end
    end
    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end
    return true
end

local function stripColors(value)
    local text = tostring(value or "")
    if dbot and dbot.stripColors then
        return dbot.stripColors(text)
    end
    return text:gsub("@.", ""):gsub("<[^>]+>", "")
end

local function normalizeName(value)
    return trim(stripColors(value):gsub("%s+", " ")):lower()
end

local function normalizeKeywordSignature(value)
    local seen, tokens = {}, {}
    for token in stripColors(value):lower():gmatch("%S+") do
        if not seen[token] then
            seen[token] = true
            table.insert(tokens, token)
        end
    end
    table.sort(tokens)
    return table.concat(tokens, " ")
end

local function getRawField(item, field)
    if type(item) ~= "table" then
        return nil
    end

    local stats = type(item.stats) == "table" and item.stats or item
    local aliases = FIELD_ALIASES[field] or { field }
    for _, alias in ipairs(aliases) do
        if stats[alias] ~= nil then
            return stats[alias]
        end
        if item[alias] ~= nil then
            return item[alias]
        end
    end
    return nil
end

local function isTransientItem(item)
    if inv and inv.items and inv.items.isTransientItem then
        return inv.items.isTransientItem(item)
    end
    if type(item) ~= "table" then
        return false
    end
    if item.__dinvTransient == true then
        return true
    end
    return type(item.stats) == "table" and item.stats.__dinvTransient == true
end

local function shouldExposeItem(item, options)
    return (options and options.includeTransient == true) or not isTransientItem(item)
end

local function visibleItemCount(source, options)
    local count = 0
    for _, item in pairs(source or {}) do
        if shouldExposeItem(item, options) then
            count = count + 1
        end
    end
    return count
end

local function inventoryDiff(previousTable, currentTable)
    previousTable = type(previousTable) == "table" and previousTable or {}
    currentTable = type(currentTable) == "table" and currentTable or {}

    local addedIds = {}
    local removedIds = {}
    local updatedIds = {}

    for objId, item in pairs(currentTable) do
        local key = tostring(objId)
        local previousItem = previousTable[key] or previousTable[tonumber(key)]
        if shouldExposeItem(item) then
            if not previousItem or not shouldExposeItem(previousItem) then
                table.insert(addedIds, key)
            elseif not deepEqual(previousItem, item) then
                table.insert(updatedIds, key)
            end
        end
    end

    for objId, item in pairs(previousTable) do
        local key = tostring(objId)
        local currentItem = currentTable[key] or currentTable[tonumber(key)]
        if shouldExposeItem(item) and (not currentItem or not shouldExposeItem(currentItem)) then
            table.insert(removedIds, key)
        end
    end

    table.sort(addedIds)
    table.sort(removedIds)
    table.sort(updatedIds)
    return addedIds, removedIds, updatedIds
end

local function isWornItem(item)
    local worn = tostring(getRawField(item, "worn") or "")
    if worn ~= "" and worn ~= "undefined" and worn ~= tostring(invItemWornNotWorn or "not-worn") then
        return true
    end

    local location = tostring(getRawField(item, "location") or "")
    if inv and inv.items and inv.items.resolveWearSlot then
        return inv.items.resolveWearSlot(location) ~= nil
    end
    return location == "worn"
end

local function normalizeItem(objId, item, options)
    options = options or {}
    if type(item) ~= "table" then
        return nil
    end

    local detail = tostring(options.detail or "summary"):lower()
    if detail == "raw" then
        local raw = deepCopy(item)
        raw.id = tostring(objId or getRawField(item, "id") or "")
        return raw
    end

    local normalized = {}
    if detail == "full" then
        for key, value in pairs(item) do
            if key ~= "stats" then
                normalized[key] = deepCopy(value)
            end
        end
        for key, value in pairs(item.stats or {}) do
            normalized[key] = deepCopy(value)
        end
    end

    for _, field in ipairs(SUMMARY_FIELDS) do
        if field == "id" then
            normalized.id = tostring(objId or getRawField(item, "id") or "")
        elseif field == "normalizedName" then
            normalized.normalizedName = normalizeName(getRawField(item, "name") or getRawField(item, "colorName"))
        else
            normalized[field] = deepCopy(getRawField(item, field))
        end
    end

    normalized.id = tostring(normalized.id or "")
    normalized.isWorn = isWornItem(item)

    if type(options.fields) == "table" and #options.fields > 0 then
        local selected = {}
        for _, field in ipairs(options.fields) do
            field = tostring(field)
            if field == "id" then
                selected.id = normalized.id
            elseif field == "normalizedName" then
                selected.normalizedName = normalized.normalizedName
            elseif field == "isWorn" then
                selected.isWorn = normalized.isWorn
            elseif normalized[field] ~= nil then
                selected[field] = deepCopy(normalized[field])
            else
                selected[field] = deepCopy(getRawField(item, field))
            end
        end
        if selected.id == nil then
            selected.id = normalized.id
        end
        return selected
    end

    return normalized
end

local function result(ok, code, message, extra)
    local out = {
        ok = ok == true,
        code = code or (ok and "OK" or "INTERNAL_ERROR"),
        message = message,
        apiVersion = api.version,
        revision = api.revision,
    }
    for key, value in pairs(extra or {}) do
        out[key] = value
    end
    return out
end

local function success(extra)
    return result(true, "OK", nil, extra)
end

local function failure(code, message, extra)
    return result(false, code, message, extra)
end

local function retvalResult(retval, extra)
    local numeric = tonumber(retval)
    local code = RESULT_CODES[numeric] or (numeric == 0 and "OK" or "INTERNAL_ERROR")
    local message = nil
    if numeric ~= 0 then
        if dbot and dbot.retval and dbot.retval.getString then
            message = dbot.retval.getString(numeric)
        else
            message = code
        end
    end
    return result(numeric == 0, code, message, extra)
end

local function debugEnabled()
    return DINV.debug and DINV.debug.isEnabled and DINV.debug.isEnabled("inv.api") or false
end

local function debugLog(message)
    if dbot and dbot.debug then
        dbot.debug(tostring(message), "inv.api")
    end
end

local function invoke(endpoint, options, fn)
    local started = os.clock()
    local function onError(err)
        local trace = debug and debug.traceback and debug.traceback(tostring(err), 2) or tostring(err)
        return { error = tostring(err), traceback = trace }
    end

    local ok, value = xpcall(fn, onError)
    if not ok then
        local diagnostics = {
            endpoint = endpoint,
            elapsedMs = math.floor((os.clock() - started) * 1000 + 0.5),
            error = value.error,
        }
        if options and options.trace then
            diagnostics.traceback = value.traceback
        end
        debugLog("endpoint=" .. endpoint .. " code=INTERNAL_ERROR error=" .. tostring(value.error))
        return failure("INTERNAL_ERROR", "DINV API endpoint failed.", {
            endpoint = endpoint,
            diagnostics = diagnostics,
        })
    end

    if type(value) ~= "table" then
        value = success({ value = value })
    end
    value.endpoint = value.endpoint or endpoint
    value.apiVersion = api.version
    value.revision = api.revision

    local elapsedMs = math.floor((os.clock() - started) * 1000 + 0.5)
    if options and options.trace then
        value.diagnostics = value.diagnostics or {}
        value.diagnostics.endpoint = endpoint
        value.diagnostics.elapsedMs = elapsedMs
    end

    if debugEnabled() then
        debugLog(string.format(
            "endpoint=%s code=%s elapsedMs=%d count=%s",
            endpoint,
            tostring(value.code),
            elapsedMs,
            tostring(value.count or "")
        ))
    end
    return value
end

local function getSourceTable(options)
    options = options or {}
    local requested = tostring(options.source or "auto"):lower()
    local live = inv and inv.items and type(inv.items.table) == "table" and inv.items.table or nil

    if requested == "live" then
        return live or {}, "live"
    end

    if requested == "auto" and live and tableCount(live) > 0 then
        return live, "live"
    end

    if requested == "persistence" or requested == "auto" then
        if inv and inv.items and inv.items.loadPersistentItemsTable then
            local ok, persisted = pcall(inv.items.loadPersistentItemsTable)
            if ok and type(persisted) == "table" then
                return persisted, "persistence"
            end
        end
    end

    return live or {}, live and "live" or "unavailable"
end

local function normalizeQueryKey(rawKey)
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
    end
    return key, negated
end

local function knownQueryKey(key, source)
    local explicit = {
        type = true, name = true, wearable = true, keywords = true, id = true,
        container = true, worn = true, minlevel = true, maxlevel = true, level = true,
        flag = true, flags = true, location = true, rlocation = true, rname = true,
        specials = true, damtype = true, weapontype = true, clan = true, score = true,
        weight = true, worth = true, owner = true, material = true, leadsto = true,
    }
    if explicit[key] then
        return true
    end
    for _, item in pairs(source or {}) do
        for statKey in pairs(type(item.stats) == "table" and item.stats or item) do
            if tostring(statKey):lower() == key then
                return true
            end
        end
    end
    return false
end

local function parseQuery(query, source)
    local raw = trim(query)
    if raw:match("^%d+$") then
        return { { { key = "id", value = raw, negated = false } } }
    end

    local clauses = {}
    for segment in raw:gmatch("[^|]+") do
        segment = trim(segment)
        if segment ~= "" and segment ~= "||" then
            local tokens = {}
            for token in segment:gmatch("%S+") do
                table.insert(tokens, token)
            end

            local criteria = {}
            local index = 1
            while index <= #tokens do
                local key, negated = normalizeQueryKey(tokens[index])
                if not tokens[index + 1] then
                    if key == "worn" then
                        table.insert(criteria, { key = key, value = "any", negated = negated })
                    else
                        table.insert(criteria, { key = "name", value = tokens[index], negated = negated })
                    end
                    break
                end

                if not knownQueryKey(key, source) then
                    table.insert(criteria, { key = "name", value = tokens[index], negated = negated })
                    index = index + 1
                else
                    local valueParts = {}
                    local cursor = index + 1
                    while cursor <= #tokens do
                        local possibleKey = normalizeQueryKey(tokens[cursor])
                        if knownQueryKey(possibleKey, source) and #valueParts > 0 then
                            break
                        end
                        table.insert(valueParts, tokens[cursor])
                        cursor = cursor + 1
                    end
                    table.insert(criteria, {
                        key = key,
                        value = table.concat(valueParts, " "),
                        negated = negated,
                    })
                    index = cursor
                end
            end
            table.insert(clauses, criteria)
        end
    end

    if #clauses == 0 then
        table.insert(clauses, {})
    end
    return clauses
end

local function contains(haystack, needle)
    return tostring(haystack or ""):lower():find(tostring(needle or ""):lower(), 1, true) ~= nil
end

local function hasFlag(item, value)
    local normalized = tostring(value or ""):lower()
    if normalized == "kept" then
        local keep = getRawField(item, "keepflag")
        return keep == true or tostring(keep):lower() == "true" or tostring(keep) == "1"
    end
    for flag in tostring(getRawField(item, "flags") or ""):gmatch("[^,%s]+") do
        local candidate = tostring(flag):lower()
        if candidate == normalized then
            return true
        end
    end
    return false
end

local function hasFlags(item, value)
    local found = false
    for flag in tostring(value or ""):gmatch("[^,%s]+") do
        found = true
        if not hasFlag(item, flag) then
            return false
        end
    end
    return found
end

local apiWornGroups = {
    ear = { lear = true, rear = true },
    neck = { neck1 = true, neck2 = true },
    wrist = { lwrist = true, rwrist = true },
    finger = { lfinger = true, rfinger = true },
    medal = { medal1 = true, medal2 = true, medal3 = true, medal4 = true },
}

local apiWornAliases = {
    wield = "wielded",
    ear1 = "lear",
    ear2 = "rear",
    wrist1 = "lwrist",
    wrist2 = "rwrist",
    finger1 = "lfinger",
    finger2 = "rfinger",
}

local function matchesWornValue(item, value)
    local target = trim(value):lower()
    local isWorn = isWornItem(item)
    if target == "" or target == "any" or target == "true"
        or target == "worn" or target == "equipped" or target == "*" then
        return isWorn
    end
    if target == "false" or target == "none" or target == "not-worn"
        or target == "unworn" then
        return not isWorn
    end
    if not isWorn then
        return false
    end

    local numeric = tonumber(target)
    if numeric and inv and inv.wearLoc and inv.wearLoc[numeric] then
        target = tostring(inv.wearLoc[numeric]):lower()
    end
    target = apiWornAliases[target] or target

    local worn = tostring(getRawField(item, "worn") or ""):lower()
    local group = apiWornGroups[target]
    if group then
        return group[worn] == true
    end
    return worn == target
end

local function relativeParts(value)
    local index, name = tostring(value or ""):match("^(%d+)%.(.+)$")
    return tonumber(index), name
end

local function matchesCriteria(objId, item, clauses)
    local name = getRawField(item, "name") or ""
    local itemType = getRawField(item, "type") or ""
    local level = tonumber(getRawField(item, "level")) or 0

    for _, criteria in ipairs(clauses or {}) do
        local matchedAll = true
        for _, entry in ipairs(criteria) do
            local key = tostring(entry.key or ""):lower()
            local value = entry.value
            local matched = false

            if key == "type" then
                local actualType = tostring(itemType):lower()
                local requestedType = tostring(value):lower()
                if actualType == "staff" then actualType = "stave" end
                if requestedType == "staff" then requestedType = "stave" end
                matched = actualType == requestedType
            elseif key == "name" then
                local _, relativeName = relativeParts(value)
                matched = contains(name, relativeName or value)
            elseif key == "wearable" then
                matched = contains(getRawField(item, "wearable"), value)
            elseif key == "keywords" then
                matched = contains(getRawField(item, "keywords"), value)
            elseif key == "leadsto" then
                matched = contains(getRawField(item, "leadsto"), value)
            elseif key == "material" then
                matched = contains(getRawField(item, "material"), value)
            elseif key == "flag" or key == "flags" then
                matched = hasFlags(item, value)
            elseif key == "id" then
                matched = tostring(objId) == tostring(value)
            elseif key == "container" then
                matched = tostring(getRawField(item, "container") or "") == tostring(value)
            elseif key == "location" then
                matched = contains(getRawField(item, "location"), value)
            elseif key == "rname" then
                local _, relativeName = relativeParts(value)
                matched = contains(name, relativeName or value)
            elseif key == "rlocation" then
                local _, relativeLocation = relativeParts(value)
                matched = contains(getRawField(item, "location"), relativeLocation or value)
            elseif key == "worn" then
                matched = matchesWornValue(item, value)
            elseif key == "minlevel" then
                matched = tonumber(value) ~= nil and level >= tonumber(value)
            elseif key == "maxlevel" then
                matched = tonumber(value) ~= nil and level <= tonumber(value)
            elseif key == "level" then
                matched = tonumber(value) ~= nil and level == tonumber(value)
            else
                local left = getRawField(item, key)
                local leftNumber = tonumber(left)
                local rightNumber = tonumber(value)
                if leftNumber ~= nil and rightNumber ~= nil then
                    matched = leftNumber == rightNumber
                else
                    matched = contains(left, value)
                end
            end

            if entry.negated then
                matched = not matched
            end
            if not matched then
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

local function compareValues(left, right)
    local leftNumber = tonumber(left)
    local rightNumber = tonumber(right)
    if leftNumber ~= nil and rightNumber ~= nil then
        return leftNumber, rightNumber
    end
    return tostring(left or ""):lower(), tostring(right or ""):lower()
end

local function sortItems(items, sortBy)
    local criteria = sortBy
    if type(criteria) ~= "table" or #criteria == 0 then
        criteria = { "level", "type", "name", "id" }
    end

    table.sort(items, function(left, right)
        for _, spec in ipairs(criteria) do
            local field
            local descending = false
            if type(spec) == "table" then
                field = tostring(spec.field or spec[1] or "")
                descending = spec.descending == true or spec.isAscending == false
            else
                field = tostring(spec)
                if field:sub(1, 1) == "-" then
                    descending = true
                    field = field:sub(2)
                end
            end

            local leftValue, rightValue = compareValues(left[field], right[field])
            if leftValue ~= rightValue then
                if descending then
                    return leftValue > rightValue
                end
                return leftValue < rightValue
            end
        end
        return tostring(left.id or "") < tostring(right.id or "")
    end)
end

local function applyRelativeFilter(query, items)
    local relativeIndex, relativeName = relativeParts(trim(query))
    if not relativeIndex then
        local lowered = tostring(query or ""):lower()
        local value = lowered:match("rname%s+(%S+)")
        relativeIndex, relativeName = relativeParts(value)
    end
    if not relativeIndex or not relativeName then
        return items
    end

    local count = 0
    for _, item in ipairs(items) do
        if contains(item.name, relativeName) then
            count = count + 1
            if count == relativeIndex then
                return { item }
            end
        end
    end
    return {}
end

local function combineQuery(base, extra)
    base = trim(base)
    extra = trim(extra)
    if base == "" then
        return extra
    end
    if extra == "" then
        return base
    end

    -- Each parsed clause is an independent OR branch, so mandatory helper
    -- filters must be added to every branch rather than only the last one.
    local clauses = {}
    for clause in base:gmatch("[^|]+") do
        clause = trim(clause)
        if clause ~= "" then
            table.insert(clauses, clause .. " " .. extra)
        end
    end
    if #clauses == 0 then
        return extra
    end
    return table.concat(clauses, " || ")
end

local function normalizeWearLocation(value)
    local raw = trim(value):lower()
    local aliases = {
        wield = "wielded", ear1 = "lear", ear2 = "rear",
        wrist1 = "lwrist", wrist2 = "rwrist",
        finger1 = "lfinger", finger2 = "rfinger",
    }
    raw = aliases[raw] or raw
    local numeric = tonumber(raw)
    if numeric and inv and inv.wearLoc then
        return tostring(inv.wearLoc[numeric] or raw)
    end
    return raw
end

local function itemWornAt(item, wearLocation)
    wearLocation = normalizeWearLocation(wearLocation)
    local worn = normalizeWearLocation(getRawField(item, "worn"))
    local location = normalizeWearLocation(getRawField(item, "location"))
    return worn == wearLocation or location == wearLocation
end

local function recordChange(action, objId, details)
    api.revision = api.revision + 1
    local payload = deepCopy(details or {})
    payload.action = action
    payload.id = objId ~= nil and tostring(objId) or nil
    payload.revision = api.revision
    payload.timestamp = os.time()

    table.insert(api.history, payload)
    while #api.history > api.historyLimit do
        table.remove(api.history, 1)
    end

    return payload
end

local function withMutedOutput(fn)
    if not dbot then
        return pcall(fn)
    end

    local names = { "info", "warn", "note", "print", "printRaw", "error" }
    local saved = {}
    for _, name in ipairs(names) do
        saved[name] = dbot[name]
        dbot[name] = function() end
    end

    local values = { pcall(fn) }
    for _, name in ipairs(names) do
        dbot[name] = saved[name]
    end
    return unpack(values)
end

----------------------------------------------------------------------------------------------------
-- Public status and diagnostics
----------------------------------------------------------------------------------------------------

function api.getVersion()
    return {
        apiVersion = api.version,
        mode = api.mode,
        dinvVersion = DINV.version,
    }
end

function api.getCapabilities()
    return success({
        mode = api.mode,
        capabilities = {
            read = {
                "search", "getItem", "findOne", "count", "exists", "distinct", "groupBy",
                "getEquipment", "getEquipped", "getContainer", "getContainerContents",
                "getLocationContents", "getKeyring", "getItemLocation", "resolveContainer",
                "getWeapons", "getWeaponDamageTypes", "getPortals", "getConsumables", "getKeys", "getKnownKeys",
                "getWearableItems", "getNewItems", "findDuplicates", "getPriority",
                "listPriorities", "scoreItem", "compareItems", "getBestItems", "getChangesSince",
                "getStaves", "getStaveChargeState",
            },
            actions = {
                "identify", "retrieve", "hold", "remove", "reserveStaveUse",
                "observeStaveCharges", "cancelStaveUse", "markStaveChargesUnknown",
            },
            events = {},
        },
    })
end

function api.getRevision()
    return api.revision
end

function api.isReady()
    return inv ~= nil
        and inv.items ~= nil
        and type(inv.items.table) == "table"
        and inv.init ~= nil
        and inv.init.initializedActive == true
end

function api.getStatus(options)
    return invoke("getStatus", options, function()
        return success({
            ready = api.isReady(),
            initialized = inv and inv.init and inv.init.initializedActive == true or false,
            itemCount = inv and inv.items and visibleItemCount(inv.items.table, options) or 0,
            buildInProgress = inv and inv.items and inv.items.buildInProgress == true or false,
            refreshInProgress = inv and inv.items and inv.items.refreshInProgress == true or false,
            identifyInProgress = inv and inv.items and inv.items.identifyInProgress == true or false,
            targetedIdentifyInProgress = inv and inv.items
                and inv.items.singleIdentifyMode == true or false,
            mode = api.mode,
        })
    end)
end

function api.setDebug(enabled)
    enabled = enabled == true
    if DINV.debug and DINV.debug.setEnabled then
        DINV.debug.setEnabled("inv.api", enabled)
    end
    return success({ enabled = enabled })
end

function api.getDebug()
    return debugEnabled()
end

----------------------------------------------------------------------------------------------------
-- Public item queries
----------------------------------------------------------------------------------------------------

function api.search(query, options)
    options = options or {}
    return invoke("search", options, function()
        if type(query) ~= "string" then
            return failure("INVALID_ARGUMENT", "query must be a string.", { count = 0, items = {} })
        end

        local source, sourceName = getSourceTable(options)
        local clauses = parseQuery(query, source)
        local items = {}
        local scanned = 0
        local exactName = options.exactName ~= nil and normalizeName(options.exactName) or nil

        -- The public source contract is stronger than the internal default
        -- search target: live, active persistence, and build staging can be
        -- different tables during a workflow. Match the selected source
        -- directly so returned IDs and returned records always agree.
        for objId, item in pairs(source) do
            scanned = scanned + 1
            local ignored = false
            if not options.includeIgnored and inv and inv.config and inv.config.isIgnored then
                local container = tostring(getRawField(item, "container") or "")
                ignored = container ~= "" and inv.config.isIgnored(container)
            end
            local itemName = getRawField(item, "name") or getRawField(item, "colorName")
            local exactNameMatches = exactName == nil or normalizeName(itemName) == exactName
            if shouldExposeItem(item, options) and not ignored
                and exactNameMatches and matchesCriteria(objId, item, clauses) then
                table.insert(items, normalizeItem(objId, item, options))
            end
        end

        sortItems(items, options.sortBy)
        items = applyRelativeFilter(query, items)

        local total = #items
        local offset = math.max(0, tonumber(options.offset) or 0)
        local limit = tonumber(options.limit)
        if offset > 0 or limit ~= nil then
            local paged = {}
            local last = limit and math.min(total, offset + math.max(0, limit)) or total
            for index = offset + 1, last do
                table.insert(paged, items[index])
            end
            items = paged
        end

        return success({
            query = query,
            source = sourceName,
            count = #items,
            total = total,
            items = items,
            diagnostics = options.trace and {
                scannedItems = scanned,
                matchedItems = total,
                parsedClauses = #clauses,
            } or nil,
        })
    end)
end

function api.getItem(objId, options)
    options = options or {}
    return invoke("getItem", options, function()
        local id = trim(objId)
        if id == "" then
            return failure("INVALID_ARGUMENT", "objId is required.")
        end
        local source, sourceName = getSourceTable(options)
        local item = source[id] or source[tonumber(id)]
        if not item or not shouldExposeItem(item, options) then
            return failure("NOT_FOUND", "Item was not found.", { id = id, source = sourceName })
        end
        return success({
            id = id,
            source = sourceName,
            item = normalizeItem(id, item, options),
        })
    end)
end

function api.findOne(query, options)
    options = options or {}
    return invoke("findOne", options, function()
        local searchOptions = deepCopy(options)
        searchOptions.limit = nil
        searchOptions.offset = nil
        local found = api.search(query, searchOptions)
        if not found.ok then
            return found
        end
        if found.total == 0 then
            return failure("NOT_FOUND", "No items matched the query.", {
                query = query, count = 0, items = {},
            })
        end
        if found.total > 1 then
            return failure("MULTIPLE_MATCHES", "More than one item matched the query.", {
                query = query, count = found.total, items = found.items,
            })
        end
        return success({ query = query, count = 1, item = found.items[1] })
    end)
end

function api.count(query, options)
    options = options or {}
    local searchOptions = deepCopy(options)
    searchOptions.fields = { "id" }
    searchOptions.limit = nil
    searchOptions.offset = nil
    local found = api.search(query or "", searchOptions)
    if not found.ok then
        return found
    end
    return success({ query = query or "", count = found.total })
end

function api.exists(query, options)
    local counted = api.count(query, options)
    if not counted.ok then
        return counted
    end
    return success({ query = query or "", exists = counted.count > 0, count = counted.count })
end

function api.distinct(field, query, options)
    options = options or {}
    return invoke("distinct", options, function()
        field = trim(field)
        if field == "" then
            return failure("INVALID_ARGUMENT", "field is required.")
        end
        local searchOptions = deepCopy(options)
        searchOptions.fields = { "id", field }
        searchOptions.limit = nil
        searchOptions.offset = nil
        local found = api.search(query or "", searchOptions)
        if not found.ok then
            return found
        end

        local seen = {}
        local values = {}
        for _, item in ipairs(found.items) do
            local value = item[field]
            local key = type(value) .. ":" .. tostring(value)
            if value ~= nil and not seen[key] then
                seen[key] = true
                table.insert(values, deepCopy(value))
            end
        end
        table.sort(values, function(left, right)
            local a, b = compareValues(left, right)
            return a < b
        end)
        return success({ field = field, query = query or "", count = #values, values = values })
    end)
end

function api.groupBy(field, query, options)
    options = options or {}
    return invoke("groupBy", options, function()
        field = trim(field)
        if field == "" then
            return failure("INVALID_ARGUMENT", "field is required.")
        end
        local found = api.search(query or "", options)
        if not found.ok then
            return found
        end
        local groups = {}
        for _, item in ipairs(found.items) do
            local value = item[field]
            local key = value == nil and "(nil)" or tostring(value)
            groups[key] = groups[key] or { value = deepCopy(value), count = 0, items = {} }
            groups[key].count = groups[key].count + 1
            table.insert(groups[key].items, deepCopy(item))
        end
        return success({ field = field, query = query or "", count = tableCount(groups), groups = groups })
    end)
end

----------------------------------------------------------------------------------------------------
-- Inventory structure and specialized queries
----------------------------------------------------------------------------------------------------

function api.getEquipment(options)
    options = options or {}
    return invoke("getEquipment", options, function()
        local source, sourceName = getSourceTable(options)
        local items = {}
        for objId, item in pairs(source) do
            if shouldExposeItem(item, options) and isWornItem(item) then
                table.insert(items, normalizeItem(objId, item, options))
            end
        end
        sortItems(items, options.sortBy or { "worn", "name", "id" })
        return success({ source = sourceName, count = #items, items = items })
    end)
end

function api.getEquipped(wearLocation, options)
    options = options or {}
    return invoke("getEquipped", options, function()
        local target = normalizeWearLocation(wearLocation)
        if target == "" then
            return failure("INVALID_ARGUMENT", "wearLocation is required.")
        end
        local source, sourceName = getSourceTable(options)
        local items = {}
        for objId, item in pairs(source) do
            if shouldExposeItem(item, options) and itemWornAt(item, target) then
                table.insert(items, normalizeItem(objId, item, options))
            end
        end
        sortItems(items, options.sortBy or { "name", "id" })
        return success({
            wearLocation = target,
            source = sourceName,
            count = #items,
            item = #items == 1 and items[1] or nil,
            items = items,
        })
    end)
end

function api.resolveContainer(reference, options)
    options = options or {}
    return invoke("resolveContainer", options, function()
        local value = trim(reference)
        if value == "" then
            return failure("INVALID_ARGUMENT", "container reference is required.")
        end

        local source, sourceName = getSourceTable(options)
        local direct = source[value] or source[tonumber(value)]
        if direct and shouldExposeItem(direct, options)
            and tostring(getRawField(direct, "type") or ""):lower() == "container" then
            return success({
                id = value,
                source = sourceName,
                item = normalizeItem(value, direct, options),
            })
        end

        local ordinal, name = relativeParts(value)
        name = name or value
        local matches = {}
        for objId, item in pairs(source) do
            if shouldExposeItem(item, options)
                and tostring(getRawField(item, "type") or ""):lower() == "container"
                and contains(getRawField(item, "name"), name) then
                table.insert(matches, normalizeItem(objId, item, options))
            end
        end
        sortItems(matches, { "name", "id" })

        if ordinal then
            local selected = matches[ordinal]
            if selected then
                return success({ id = selected.id, source = sourceName, item = selected })
            end
            return failure("NOT_FOUND", "Container was not found.")
        end
        if #matches == 0 then
            return failure("NOT_FOUND", "Container was not found.")
        end
        if #matches > 1 then
            return failure("MULTIPLE_MATCHES", "More than one container matched.", {
                count = #matches, items = matches,
            })
        end
        return success({ id = matches[1].id, source = sourceName, item = matches[1] })
    end)
end

function api.getContainer(reference, options)
    return api.resolveContainer(reference, options)
end

function api.getContainerContents(reference, options)
    options = options or {}
    local resolved = api.resolveContainer(reference, options)
    if not resolved.ok then
        return resolved
    end
    local queryOptions = deepCopy(options)
    return api.search("container " .. tostring(resolved.id), queryOptions)
end

function api.getLocationContents(location, options)
    location = trim(location)
    if location == "" then
        return failure("INVALID_ARGUMENT", "location is required.")
    end
    return api.search("location " .. location, options)
end

function api.getKeyring(options)
    return api.getLocationContents(tostring(invItemLocKeyring or "keyring"), options)
end

function api.getItemLocation(objId, options)
    local itemResult = api.getItem(objId, options)
    if not itemResult.ok then
        return itemResult
    end
    return success({
        id = itemResult.id,
        location = itemResult.item.location,
        container = itemResult.item.container,
        lastStored = itemResult.item.lastStored,
        worn = itemResult.item.worn,
        isWorn = itemResult.item.isWorn,
    })
end

function api.getWeapons(options)
    options = options or {}
    return api.search(combineQuery(options.query, "type weapon"), options)
end

function api.getWeaponDamageTypes(options)
    options = options or {}
    return invoke("getWeaponDamageTypes", options, function()
        local weaponOptions = deepCopy(options)
        weaponOptions.fields = { "id", "name", "level", "damtype" }
        weaponOptions.limit = nil
        weaponOptions.offset = nil
        local weapons = api.getWeapons(weaponOptions)
        if not weapons.ok then
            return weapons
        end
        local byType = {}
        for _, item in ipairs(weapons.items) do
            local damtype = trim(item.damtype):lower()
            if damtype ~= "" then
                byType[damtype] = byType[damtype] or {
                    damageType = damtype, count = 0, bestId = item.id, bestLevel = tonumber(item.level) or 0,
                }
                local entry = byType[damtype]
                entry.count = entry.count + 1
                if (tonumber(item.level) or 0) > entry.bestLevel then
                    entry.bestId = item.id
                    entry.bestLevel = tonumber(item.level) or 0
                end
            end
        end
        local types = {}
        for _, entry in pairs(byType) do
            table.insert(types, entry)
        end
        table.sort(types, function(left, right) return left.damageType < right.damageType end)
        return success({ count = #types, damageTypes = types })
    end)
end

function api.getPortals(options)
    options = options or {}
    return api.search(combineQuery(options.query, "type portal"), options)
end

function api.getConsumables(options)
    options = options or {}
    return invoke("getConsumables", options, function()
        local allowedTypes = {
            potion = true,
            pill = true,
            scroll = true,
            wand = true,
            staff = true,
            stave = true,
            food = true,
            ["drink container"] = true,
        }
        local source, sourceName = getSourceTable(options)
        local clauses = parseQuery(options.query or "", source)
        local items = {}
        for objId, item in pairs(source) do
            local itemType = tostring(getRawField(item, "type") or ""):lower()
            local ignored = false
            if not options.includeIgnored and inv and inv.config and inv.config.isIgnored then
                local container = tostring(getRawField(item, "container") or "")
                ignored = container ~= "" and inv.config.isIgnored(container)
            end
            if shouldExposeItem(item, options) and not ignored and allowedTypes[itemType] and matchesCriteria(objId, item, clauses) then
                table.insert(items, normalizeItem(objId, item, options))
            end
        end
        sortItems(items, options.sortBy)
        local total = #items
        local offset = math.max(0, tonumber(options.offset) or 0)
        local limit = tonumber(options.limit)
        if offset > 0 or limit ~= nil then
            local paged = {}
            local last = limit and math.min(total, offset + math.max(0, limit)) or total
            for index = offset + 1, last do
                table.insert(paged, items[index])
            end
            items = paged
        end
        return success({ source = sourceName, count = #items, total = total, items = items })
    end)
end

function api.getStaves(options)
    options = options or {}
    return invoke("getStaves", options, function()
        local source, sourceName = getSourceTable(options)
        local clauses = parseQuery(options.query or "", source)
        local items = {}
        for objId, item in pairs(source) do
            local itemType = tostring(getRawField(item, "type") or ""):lower()
            if itemType == "staff" then itemType = "stave" end
            if itemType == "stave" and shouldExposeItem(item, options)
                and matchesCriteria(objId, item, clauses) then
                table.insert(items, normalizeItem(objId, item, options))
            end
        end
        sortItems(items, options.sortBy or { "name" })
        return success({ source = sourceName, count = #items, items = items })
    end)
end

function api.getStaveChargeState(objId, options)
    options = options or {}
    return invoke("getStaveChargeState", options, function()
        local key = tostring(objId or "")
        if key == "" then
            return failure("INVALID_ARGUMENT", "objId is required.")
        end
        local source, sourceName = getSourceTable(options)
        local item = source[key] or source[tonumber(key)]
        if not item then
            return failure("NOT_FOUND", "Item was not found in DINV.", { id = key })
        end
        local itemType = tostring(getRawField(item, "type") or ""):lower()
        if itemType ~= "stave" and itemType ~= "staff" then
            return failure("WRONG_TYPE", "Item is not a stave.", { id = key })
        end
        local knownValue = getRawField(item, "chargeKnown")
        local known = knownValue == true or knownValue == 1 or tostring(knownValue):lower() == "true"
        local dirtyValue = getRawField(item, "chargeDirty")
        local dirty = dirtyValue == true or dirtyValue == 1 or tostring(dirtyValue):lower() == "true"
        local charges = known and tonumber(getRawField(item, "charges")) or nil
        local runtimeState = sourceName == "live" and inv.items.getStaveChargeState
            and inv.items.getStaveChargeState(key) or nil
        return success({
            source = sourceName,
            state = {
                id = key,
                charges = charges and math.max(0, math.floor(charges)) or nil,
                known = known,
                dirty = dirty,
                source = tostring(getRawField(item, "chargeSource") or ""),
                observedAt = tonumber(getRawField(item, "chargeObservedAt")),
                revision = tonumber(getRawField(item, "chargeRevision")) or 0,
                pending = runtimeState and runtimeState.pending or false,
                reservationToken = runtimeState and runtimeState.reservationToken or nil,
            },
            item = normalizeItem(key, item, options),
        })
    end)
end

function api.getKeys(options)
    options = options or {}
    -- Aardwolf uses both representations in live data: some usable keys carry
    -- the isKey flag regardless of object type, while ordinary temporary keys
    -- can be Type Key without that flag. A caller query must apply to both OR
    -- branches. exactName is normalized by api.search.
    local searchOptions = deepCopy(options)
    if options.exactKeywords ~= nil and type(searchOptions.fields) == "table" then
        local wanted = { keywords = true, identifyLevel = true }
        for _, field in ipairs(searchOptions.fields) do wanted[tostring(field)] = nil end
        for field in pairs(wanted) do table.insert(searchOptions.fields, field) end
    end
    local flagged = combineQuery(options.query, "flag iskey")
    local typed = combineQuery(options.query, "type key")
    local result = api.search(flagged .. " || " .. typed, searchOptions)
    if type(result) == "table" then
        result.keyDefinition = "isKeyOrTypeKey"
        result.exactNameApplied = options.exactName ~= nil
        result.exactName = options.exactName ~= nil and normalizeName(options.exactName) or nil
        result.exactKeywordsApplied = options.exactKeywords ~= nil
        result.exactKeywords = options.exactKeywords ~= nil
            and normalizeKeywordSignature(options.exactKeywords) or nil
        result.keywordDefinition = "exactFullIdentifyTokenSet"
        if result.ok == true and options.exactKeywords ~= nil then
            local matched = {}
            for _, item in ipairs(type(result.items) == "table" and result.items or {}) do
                if tostring(item.identifyLevel or ""):lower() == "full"
                    and normalizeKeywordSignature(item.keywords) == result.exactKeywords then
                    table.insert(matched, item)
                end
            end
            result.items = matched
            result.count = #matched
            result.total = #matched
        end
    end
    return result
end

function api.getKnownKeys(options)
    options = type(options) == "table" and options or {}
    return invoke("getKnownKeys", options, function()
        if not DINV or not DINV.database or type(DINV.database.findKnownKeys) ~= "function" then
            return failure("UNSUPPORTED", "Persistent key definitions are unavailable.")
        end
        local keys, queryErr = DINV.database.findKnownKeys(options)
        if not keys then
            return failure("INTERNAL_ERROR", "Unable to query persistent key definitions: " .. tostring(queryErr))
        end
        return success({
            count = #keys,
            total = #keys,
            items = keys,
            identityDefinition = "normalizedName+keywordSignature+sourceRoom+sourceArea",
            keywordDefinition = "exactFullIdentifyTokenSet",
        })
    end)
end

function api.getWearableItems(wearLocation, options)
    options = options or {}
    local target = normalizeWearLocation(wearLocation)
    if target == "" then
        return failure("INVALID_ARGUMENT", "wearLocation is required.")
    end
    -- "second" is an equipment slot, not a value stored in an item's
    -- wearable field. Offhand candidates are normal weapons and are scored
    -- for the second-wield slot by getBestItems below.
    if target == "second" then
        return api.getWeapons(options)
    end
    return api.search(combineQuery(options.query, "wearable " .. target), options)
end

function api.getNewItems(sinceRevision, options)
    options = options or {}
    return invoke("getNewItems", options, function()
        local revision = tonumber(sinceRevision)
        if revision == nil then
            return failure("INVALID_ARGUMENT", "sinceRevision must be a number.")
        end
        local ids = {}
        for _, change in ipairs(api.history) do
            if change.revision > revision then
                if change.action == "added" and change.id then
                    ids[change.id] = true
                end
                for _, id in ipairs(change.addedIds or {}) do
                    ids[tostring(id)] = true
                end
            end
        end
        local items = {}
        for id in pairs(ids) do
            local found = api.getItem(id, options)
            if found.ok then
                table.insert(items, found.item)
            end
        end
        sortItems(items, options.sortBy)
        return success({ sinceRevision = revision, count = #items, items = items })
    end)
end

function api.findDuplicates(options)
    options = options or {}
    return invoke("findDuplicates", options, function()
        local found = api.search(options.query or "", options)
        if not found.ok then
            return found
        end
        local field = tostring(options.groupBy or "normalizedName")
        local grouped = {}
        for _, item in ipairs(found.items) do
            local value = item[field]
            if field == "normalizedName" and value == nil then
                value = normalizeName(item.name or item.colorName)
            end
            local key = tostring(value or "")
            if key ~= "" then
                grouped[key] = grouped[key] or {}
                table.insert(grouped[key], item)
            end
        end

        local duplicates = {}
        for key, items in pairs(grouped) do
            if #items > 1 then
                table.insert(duplicates, { key = key, count = #items, items = items })
            end
        end
        table.sort(duplicates, function(left, right) return left.key < right.key end)
        return success({ count = #duplicates, groups = duplicates })
    end)
end

----------------------------------------------------------------------------------------------------
-- Priority and scoring helpers
----------------------------------------------------------------------------------------------------

function api.getPriority(name, options)
    options = options or {}
    return invoke("getPriority", options, function()
        name = trim(name)
        if name == "" then
            return failure("INVALID_ARGUMENT", "priority name is required.")
        end
        local priority = inv and inv.priority and inv.priority.table and inv.priority.table[name]
        if not priority then
            return failure("NOT_FOUND", "Priority was not found.")
        end
        return success({ name = name, priority = deepCopy(priority) })
    end)
end

function api.listPriorities(options)
    options = options or {}
    return invoke("listPriorities", options, function()
        local names = {}
        for name in pairs(inv and inv.priority and inv.priority.table or {}) do
            table.insert(names, tostring(name))
        end
        table.sort(names)
        return success({
            count = #names,
            priorities = names,
            default = inv and inv.priority and inv.priority.getDefault and inv.priority.getDefault() or nil,
        })
    end)
end

function api.scoreItem(objId, priorityName, options)
    options = options or {}
    return invoke("scoreItem", options, function()
        local id = trim(objId)
        priorityName = trim(priorityName)
        if id == "" or priorityName == "" then
            return failure("INVALID_ARGUMENT", "objId and priorityName are required.")
        end
        local item = inv and inv.items and inv.items.getItem and inv.items.getItem(id) or nil
        if not item or not shouldExposeItem(item, options) then
            return failure("NOT_FOUND", "Item was not found.")
        end
        if not (inv.priority and inv.priority.exists and inv.priority.exists(priorityName)) then
            return failure("NOT_FOUND", "Priority was not found.")
        end
        if not (inv.score and inv.score.item) then
            return failure("UNSUPPORTED", "Scoring module is unavailable.")
        end
        local ok, primary, offhand, retval = withMutedOutput(function()
            return inv.score.item(id, priorityName, options.handicap, options.level)
        end)
        if not ok then
            return failure("INTERNAL_ERROR", "Unable to score item.", { error = tostring(primary) })
        end
        if retval ~= DRL_RET_SUCCESS then
            return retvalResult(retval)
        end
        return success({
            id = id,
            priority = priorityName,
            level = options.level,
            score = primary,
            offhandScore = offhand,
        })
    end)
end

function api.compareItems(firstId, secondId, priorityName, options)
    options = options or {}
    return invoke("compareItems", options, function()
        local first = api.scoreItem(firstId, priorityName, options)
        if not first.ok then
            return first
        end
        local second = api.scoreItem(secondId, priorityName, options)
        if not second.ok then
            return second
        end
        return success({
            priority = priorityName,
            first = first,
            second = second,
            delta = (tonumber(first.score) or 0) - (tonumber(second.score) or 0),
            offhandDelta = (tonumber(first.offhandScore) or 0) - (tonumber(second.offhandScore) or 0),
        })
    end)
end

function api.getBestItems(wearLocation, priorityName, options)
    options = options or {}
    return invoke("getBestItems", options, function()
        priorityName = trim(priorityName)
        if priorityName == "" then
            return failure("INVALID_ARGUMENT", "priorityName is required.")
        end
        if not (inv.priority and inv.priority.exists and inv.priority.exists(priorityName)) then
            return failure("NOT_FOUND", "Priority was not found.")
        end
        if not (inv.score and inv.score.item) then
            return failure("UNSUPPORTED", "Scoring module is unavailable.")
        end

        -- Score the complete candidate set. Pagination belongs to the ranked
        -- result, not the search's default ordering.
        local searchOptions = deepCopy(options)
        searchOptions.limit = nil
        searchOptions.offset = nil
        local found = api.getWearableItems(wearLocation, searchOptions)
        if not found.ok then
            return found
        end
        local scored = {}
        for _, item in ipairs(found.items) do
            local score = api.scoreItem(item.id, priorityName, options)
            if not score.ok then
                return score
            end
            table.insert(scored, {
                id = item.id,
                item = item,
                score = normalizeWearLocation(wearLocation) == "second"
                    and score.offhandScore or score.score,
            })
        end
        table.sort(scored, function(left, right)
            if tonumber(left.score) == tonumber(right.score) then
                return tostring(left.id) < tostring(right.id)
            end
            return (tonumber(left.score) or 0) > (tonumber(right.score) or 0)
        end)

        local total = #scored
        local offset = math.max(0, tonumber(options.offset) or 0)
        local limit = tonumber(options.limit)
        if offset > 0 or limit ~= nil then
            local paged = {}
            local last = limit and math.min(total, offset + math.max(0, limit)) or total
            for index = offset + 1, last do
                table.insert(paged, scored[index])
            end
            scored = paged
        end
        return success({ count = #scored, total = total, items = scored, priority = priorityName })
    end)
end

----------------------------------------------------------------------------------------------------
-- History and disabled subscriptions
----------------------------------------------------------------------------------------------------

function api.getChangesSince(revision, options)
    options = options or {}
    return invoke("getChangesSince", options, function()
        revision = tonumber(revision)
        if revision == nil then
            return failure("INVALID_ARGUMENT", "revision must be a number.")
        end
        local changes = {}
        for _, change in ipairs(api.history) do
            if change.revision > revision then
                table.insert(changes, deepCopy(change))
            end
        end
        return success({
            fromRevision = revision,
            count = #changes,
            changes = changes,
        })
    end)
end

function api.subscribe(eventName, subscriber)
    return failure("UNSUPPORTED", "DINV API subscriptions are disabled; use Mudlet events or polling.", {
        mode = api.mode,
    })
end

function api.unsubscribe(subscriptionId)
    return failure("UNSUPPORTED", "DINV API subscriptions are disabled; use Mudlet events or polling.", {
        mode = api.mode,
    })
end

-- Controlled action namespace
----------------------------------------------------------------------------------------------------

local function normalizeActionIds(value)
    local source = type(value) == "table" and value or { value }
    local ids, seen = {}, {}
    for _, candidate in ipairs(source) do
        local id = tostring(candidate or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if id ~= "" and id:match("^%d+$") and not seen[id] then
            seen[id] = true
            table.insert(ids, id)
        end
    end
    return ids
end

local function chargeActionResult(endpointName, state, code, message)
    if not state then
        return failure(code or "INTERNAL_ERROR", message or "Stave charge action failed.")
    end
    return success({ endpoint = endpointName, state = deepCopy(state) })
end

local function startObservedCommands(label, commands, options)
    options = options or {}
    if #commands == 0 then
        return success({ operationId = nil, commandCount = 0, commands = {} })
    end
    if not inv or not inv.items or not inv.items.sendActionCommands then
        return failure("NOT_READY", "DINV inventory actions are not ready.")
    end
    local operationId = nil
    if inv.operations and inv.operations.startBatchFromCommands then
        operationId = inv.operations.startBatchFromCommands(label, commands, {
            report = options.report == true,
            timeout = options.timeout,
            onFinish = options.onFinish,
        })
    end
    local retval = inv.items.sendActionCommands(commands)
    if tonumber(retval) ~= tonumber(DRL_RET_SUCCESS or 0) then
        return retvalResult(retval, { operationId = operationId })
    end
    return success({
        operationId = operationId,
        commandCount = #commands,
        commands = deepCopy(commands),
    })
end

local function isCarriedContainer(containerId, seen)
    local key = tostring(containerId or "")
    if key == "" then return false end
    seen = seen or {}
    if seen[key] then return false end
    seen[key] = true
    local container = inv.items and inv.items.getItem and inv.items.getItem(key) or nil
    if not container or not container.stats then return false end
    if isWornItem(container) then return true end
    local location = tostring(container.stats[invStatFieldLocation] or "")
    if location == tostring(invItemLocInventory or "inventory") then return true end
    local parent = inv.items.normalizeContainerId(container.stats[invStatFieldContainer])
        or inv.items.normalizeContainerId(location)
    return parent ~= nil and isCarriedContainer(parent, seen) or false
end

function actions.identify(objIds, options)
    options = options or {}
    return invoke("actions.identify", options, function()
        local ids = normalizeActionIds(objIds)
        if #ids == 0 then
            return failure("INVALID_ARGUMENT", "At least one numeric object id is required.")
        end
        if not inv or not inv.items or not inv.items.identifySingleItem then
            return failure("NOT_READY", "DINV identification is not ready.")
        end
        local accepted, rejected = {}, {}
        for _, id in ipairs(ids) do
            local retval = inv.items.identifySingleItem(id, options.source or "DINV.api")
            if tonumber(retval) == tonumber(DRL_RET_SUCCESS or 0) then
                table.insert(accepted, id)
            else
                table.insert(rejected, {
                    id = id,
                    retval = retval,
                    code = RESULT_CODES[tonumber(retval)] or "INTERNAL_ERROR",
                })
            end
        end
        if #accepted == 0 then
            return failure(rejected[1] and rejected[1].code or "BUSY",
                "No items were accepted for identification.", { rejected = rejected })
        end
        return success({ accepted = accepted, rejected = rejected, count = #accepted })
    end)
end

function actions.retrieve(objIds, options)
    options = options or {}
    return invoke("actions.retrieve", options, function()
        local ids = normalizeActionIds(objIds)
        if #ids == 0 then
            return failure("INVALID_ARGUMENT", "At least one numeric object id is required.")
        end
        local commands, skipped = {}, {}
        for _, id in ipairs(ids) do
            local item = inv.items and inv.items.getItem and inv.items.getItem(id) or nil
            local stats = item and item.stats or nil
            if not stats then
                table.insert(skipped, { id = id, code = "NOT_FOUND" })
            else
                local location = tostring(stats[invStatFieldLocation] or "")
                local container = inv.items.normalizeContainerId(stats[invStatFieldContainer])
                    or inv.items.normalizeContainerId(location)
                if container and isCarriedContainer(container) then
                    table.insert(commands, "get " .. id .. " " .. container)
                elseif container then
                    table.insert(skipped, { id = id, code = "NOT_IN_CARRIED_CONTAINER" })
                elseif location ~= tostring(invItemLocInventory or "inventory") then
                    table.insert(skipped, { id = id, code = "NOT_IN_CARRIED_CONTAINER" })
                end
            end
        end
        local response = startObservedCommands(options.label or "DINV retrieve", commands, options)
        response.ids = ids
        response.skipped = skipped
        return response
    end)
end

function actions.hold(objId, options)
    options = options or {}
    return invoke("actions.hold", options, function()
        local ids = normalizeActionIds(objId)
        if #ids ~= 1 then
            return failure("INVALID_ARGUMENT", "Exactly one numeric object id is required.")
        end
        local id = ids[1]
        local item = inv.items and inv.items.getItem and inv.items.getItem(id) or nil
        if not item or not item.stats then
            return failure("NOT_FOUND", "Item was not found in DINV.", { id = id })
        end
        if not inv.items.isStaveType(item.stats[invStatFieldType]) then
            return failure("WRONG_TYPE", "Item is not a stave.", { id = id })
        end
        local commands = {}
        local location = tostring(item.stats[invStatFieldLocation] or "")
        local container = inv.items.normalizeContainerId(item.stats[invStatFieldContainer])
            or inv.items.normalizeContainerId(location)
        if container and not isCarriedContainer(container) then
            return failure("NOT_IN_CARRIED_CONTAINER",
                "The stave's container is not currently carried.", { id = id, container = container })
        end
        if container then table.insert(commands, "get " .. id .. " " .. container) end
        local worn = tostring(item.stats[invStatFieldWorn] or "")
        if worn ~= tostring(invWearLocHold or "hold") and location ~= tostring(invWearLocHold or "hold") then
            table.insert(commands, "hold " .. id)
        end
        local response = startObservedCommands(options.label or "DINV hold stave", commands, options)
        response.id = id
        return response
    end)
end

function actions.remove(objIds, options)
    options = options or {}
    return invoke("actions.remove", options, function()
        local ids = normalizeActionIds(objIds)
        if #ids == 0 then
            return failure("INVALID_ARGUMENT", "At least one numeric object id is required.")
        end
        local commands = {}
        for _, id in ipairs(ids) do
            local item = inv.items and inv.items.getItem and inv.items.getItem(id) or nil
            if item and isWornItem(item) then table.insert(commands, "remove " .. id) end
        end
        local response = startObservedCommands(options.label or "DINV remove", commands, options)
        response.ids = ids
        return response
    end)
end

function actions.reserveStaveUse(objId, options)
    options = options or {}
    return invoke("actions.reserveStaveUse", options, function()
        if not inv or not inv.items or not inv.items.reserveStaveChargeUse then
            return failure("NOT_READY", "DINV stave charge tracking is not ready.")
        end
        local state, code, message = inv.items.reserveStaveChargeUse(
            objId, options.floor, options.expectedRevision)
        return chargeActionResult("actions.reserveStaveUse", state, code, message)
    end)
end

function actions.observeStaveCharges(objId, charges, options)
    options = options or {}
    return invoke("actions.observeStaveCharges", options, function()
        if not inv or not inv.items or not inv.items.observeStaveCharges then
            return failure("NOT_READY", "DINV stave charge tracking is not ready.")
        end
        local state, code, message = inv.items.observeStaveCharges(
            objId, charges, options.source, options.expectedRevision)
        return chargeActionResult("actions.observeStaveCharges", state, code, message)
    end)
end

function actions.cancelStaveUse(objId, token, options)
    options = options or {}
    return invoke("actions.cancelStaveUse", options, function()
        if not inv or not inv.items or not inv.items.cancelStaveChargeUse then
            return failure("NOT_READY", "DINV stave charge tracking is not ready.")
        end
        local state, code, message = inv.items.cancelStaveChargeUse(
            objId, token, options.markUnknown == true, options.source)
        return chargeActionResult("actions.cancelStaveUse", state, code, message)
    end)
end

function actions.markStaveChargesUnknown(objId, options)
    options = options or {}
    return invoke("actions.markStaveChargesUnknown", options, function()
        if not inv or not inv.items or not inv.items.markStaveChargesUnknown then
            return failure("NOT_READY", "DINV stave charge tracking is not ready.")
        end
        local state, code, message = inv.items.markStaveChargesUnknown(objId, options.source)
        return chargeActionResult("actions.markStaveChargesUnknown", state, code, message)
    end)
end

local disabledActionEndpointNames = {
    "ensureIdentified", "ensureInInventory", "moveToContainer", "restoreToHome",
    "wear", "usePortal", "useConsumable", "selectWeapon",
}

local function disabledAction(endpointName)
    return function()
        return failure("UNSUPPORTED", "This DINV action is not exposed by the controlled API.", {
            endpoint = endpointName,
            mode = api.mode,
        })
    end
end

for _, endpointName in ipairs(disabledActionEndpointNames) do
    actions[endpointName] = disabledAction(endpointName)
    api[endpointName] = nil
end

----------------------------------------------------------------------------------------------------
-- Hooks called by DINV internals
----------------------------------------------------------------------------------------------------

function api._onItemSet(objId, previousItem, item)
    if item and not shouldExposeItem(item) then
        return nil
    end
    local action = previousItem == nil and "added" or "updated"
    return recordChange(action, objId, {
        item = normalizeItem(objId, item, { detail = "summary" }),
    })
end

function api._onItemRemoved(objId, previousItem)
    if previousItem and not shouldExposeItem(previousItem) then
        return nil
    end
    return recordChange("removed", objId, {
        previousItem = normalizeItem(objId, previousItem, { detail = "summary" }),
    })
end

function api._onInventoryAction(objId, actionName, details)
    details = details or {}
    local action = "updated"
    local normalized = tostring(actionName or ""):lower()
    if normalized == "addedtoinv" then
        action = details.existedBefore and "moved" or "added"
    elseif normalized == "removedfrominv" or normalized == "consumed" then
        action = "removed"
    elseif normalized ~= "" then
        action = "moved"
    end
    details.inventoryAction = actionName
    local current = inv and inv.items and inv.items.getItem and inv.items.getItem(objId) or nil
    if current and not shouldExposeItem(current) then
        return nil
    end
    details.item = current and normalizeItem(objId, current, { detail = "summary" }) or nil
    return recordChange(action, objId, details)
end

function api._onIdentifyComplete(objId)
    local item = inv and inv.items and inv.items.getItem and inv.items.getItem(objId) or nil
    if item and not shouldExposeItem(item) then
        return nil
    end
    return recordChange("identified", objId, {
        item = item and normalizeItem(objId, item, { detail = "full" }) or nil,
    })
end

function api._onRefreshComplete(previousTable)
    local currentTable = inv and inv.items and inv.items.table or {}
    local addedIds, removedIds, updatedIds = inventoryDiff(previousTable, currentTable)
    return recordChange("refreshComplete", nil, {
        itemCount = visibleItemCount(currentTable),
        addedIds = addedIds,
        removedIds = removedIds,
        updatedIds = updatedIds,
    })
end

function api._onBuildComplete(previousTable)
    local currentTable = inv and inv.items and inv.items.table or {}
    local addedIds, removedIds, updatedIds = inventoryDiff(previousTable, currentTable)
    return recordChange("buildComplete", nil, {
        itemCount = visibleItemCount(currentTable),
        addedIds = addedIds,
        removedIds = removedIds,
        updatedIds = updatedIds,
    })
end

function api._onReady()
    if api.readyRaised then
        return
    end
    api.readyRaised = true
    return recordChange("ready", nil, {
        ready = api.isReady(),
        itemCount = inv and inv.items and visibleItemCount(inv.items.table) or 0,
    })
end

if DINV.debug and DINV.debug.registerModule then
    DINV.debug.registerModule("inv.api", "Read-only public API request diagnostics.")
end

dbot.debug("inv.api module loaded", "inv.api")
