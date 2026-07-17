----------------------------------------------------------------------------------------------------
-- INV Cache Module
-- Item identification cache management
----------------------------------------------------------------------------------------------------

inv.cache       = {}
inv.cache.init  = {}
inv.cache.table = {}
inv.cache.access = {}
inv.cache.clock = 0
inv.cache.stateName = "inv-cache.state"

-- Cache types
inv.cache.types = {
    recent = "recent",
    frequent = "frequent",
    custom = "custom"
}

-- Default cache sizes
inv.cache.defaults = {
    recentSize = 100,
    frequentSize = 200,
    customSize = 50
}

----------------------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------------------

function inv.cache.init.atInstall()
    return DRL_RET_SUCCESS
end

function inv.cache.init.atActive()
    -- Persistent reusable templates now live in SQLite. This table is only a
    -- small session-local compatibility cache for existing callers; only its
    -- size settings persist alongside the SQLite templates.
    return inv.cache.load()
end

function inv.cache.fini(doSaveState)
    if doSaveState then
        inv.cache.save()
    end
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Save/Load/Reset
----------------------------------------------------------------------------------------------------

function inv.cache.save()
    if not DINV or not DINV.database or not DINV.database.saveModuleTable then
        return DRL_RET_INTERNAL_ERROR
    end
    return DINV.database.saveModuleTable("cache", inv.cache.getPersistentState())
end

function inv.cache.load()
    inv.cache.reset()
    if not DINV or not DINV.database or not DINV.database.loadModuleState then
        return DRL_RET_INTERNAL_ERROR
    end
    local stored, err = DINV.database.loadModuleState("cache")
    if stored == nil then
        if err == nil or err == "not found" then return DRL_RET_SUCCESS end
        dbot.warn("Unable to load SQLite cache settings: " .. tostring(err))
        return DRL_RET_INTERNAL_ERROR
    end
    for _, key in ipairs({ "recentSize", "frequentSize", "customSize" }) do
        local value = tonumber(stored[key])
        if value ~= nil then
            inv.cache.table[key] = math.max(0, math.floor(value))
        end
    end
    if DINV.database.enforceConsumableTemplateLimit then
        local ok, limitErr = DINV.database.enforceConsumableTemplateLimit(
            inv.cache.table.frequentSize
        )
        if not ok then
            dbot.warn("Unable to enforce persisted consumable template limit: " .. tostring(limitErr))
            return DRL_RET_INTERNAL_ERROR
        end
    end
    -- Replace a migrated legacy cache table with settings only. Object-id
    -- entries remain session-local and reusable SQL templates remain
    -- consumable-only.
    return inv.cache.save()
end

function inv.cache.getPersistentState()
    return {
        recentSize = tonumber(inv.cache.table.recentSize) or inv.cache.defaults.recentSize,
        frequentSize = tonumber(inv.cache.table.frequentSize) or inv.cache.defaults.frequentSize,
        customSize = tonumber(inv.cache.table.customSize) or inv.cache.defaults.customSize,
    }
end

function inv.cache.reset()
    inv.cache.table = {
        recent = {},
        frequent = {},
        custom = {},
        recentSize = inv.cache.defaults.recentSize,
        frequentSize = inv.cache.defaults.frequentSize,
        customSize = inv.cache.defaults.customSize
    }
    inv.cache.access = { recent = {}, frequent = {}, custom = {} }
    inv.cache.clock = 0
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Cache Operations
----------------------------------------------------------------------------------------------------

local function touch(cacheType, key)
    inv.cache.clock = (tonumber(inv.cache.clock) or 0) + 1
    inv.cache.access[cacheType] = inv.cache.access[cacheType] or {}
    inv.cache.access[cacheType][key] = inv.cache.clock
end

local function enforceMaxSize(cacheType)
    local bucket = inv.cache.table[cacheType]
    if type(bucket) ~= "table" then return end
    local maximum = math.max(0, math.floor(tonumber(inv.cache.table[cacheType .. "Size"]) or 0))
    while dbot.table.getNumEntries(bucket) > maximum do
        local oldestKey, oldestAccess = nil, nil
        for key, _ in pairs(bucket) do
            local accessed = inv.cache.access[cacheType] and inv.cache.access[cacheType][key] or 0
            if oldestAccess == nil or accessed < oldestAccess
                or (accessed == oldestAccess and tostring(key) < tostring(oldestKey)) then
                oldestKey, oldestAccess = key, accessed
            end
        end
        if oldestKey == nil then break end
        bucket[oldestKey] = nil
        if inv.cache.access[cacheType] then inv.cache.access[cacheType][oldestKey] = nil end
    end
end

function inv.cache.get(cacheType, key)
    if inv.cache.table[cacheType] then
        local value = inv.cache.table[cacheType][key]
        if value ~= nil then touch(cacheType, key) end
        return value
    end
    return nil
end

function inv.cache.set(cacheType, key, value)
    if inv.cache.table[cacheType] == nil then
        inv.cache.table[cacheType] = {}
    end
    inv.cache.table[cacheType][key] = value
    touch(cacheType, key)
    enforceMaxSize(cacheType)
    return DRL_RET_SUCCESS
end

function inv.cache.remove(cacheType, key)
    if inv.cache.table[cacheType] then
        inv.cache.table[cacheType][key] = nil
    end
    if inv.cache.access[cacheType] then inv.cache.access[cacheType][key] = nil end
    return DRL_RET_SUCCESS
end

function inv.cache.clear(cacheType)
    if cacheType == "all" then
        inv.cache.table.recent = {}
        inv.cache.table.frequent = {}
        inv.cache.table.custom = {}
        inv.cache.access = { recent = {}, frequent = {}, custom = {} }
    elseif inv.cache.table[cacheType] then
        inv.cache.table[cacheType] = {}
        inv.cache.access[cacheType] = {}
    end
    if (cacheType == "all" or cacheType == "frequent")
        and DINV and DINV.database and DINV.database.clearConsumableTemplates then
        local ok, err = DINV.database.clearConsumableTemplates()
        if not ok then
            dbot.warn("Unable to clear SQLite consumable templates: " .. tostring(err))
            return DRL_RET_INTERNAL_ERROR
        end
    end
    return DRL_RET_SUCCESS
end

function inv.cache.getSize(cacheType)
    if inv.cache.table[cacheType] then
        return dbot.table.getNumEntries(inv.cache.table[cacheType])
    end
    return 0
end

function inv.cache.setMaxSize(cacheType, size)
    local sizeKey = cacheType .. "Size"
    if inv.cache.table[sizeKey] ~= nil then
        inv.cache.table[sizeKey] = math.max(0, math.floor(tonumber(size) or 0))
        enforceMaxSize(cacheType)
        if cacheType == "frequent" and DINV and DINV.database
            and DINV.database.enforceConsumableTemplateLimit then
            local ok, err = DINV.database.enforceConsumableTemplateLimit(inv.cache.table[sizeKey])
            if not ok then
                dbot.warn("Unable to enforce SQLite consumable template limit: " .. tostring(err))
                return DRL_RET_INTERNAL_ERROR
            end
        end
    end
    return inv.cache.save()
end

function inv.cache.display(cacheType)
    cacheType = cacheType or "all"
    
    dbot.print("@WCache Status:@w")
    
    if cacheType == "all" or cacheType == "recent" then
        local size = inv.cache.getSize("recent")
        local maxSize = inv.cache.table.recentSize or inv.cache.defaults.recentSize
        dbot.print(string.format("  @CRecent:@W   %d / %d entries", size, maxSize))
    end
    
    if cacheType == "all" or cacheType == "frequent" then
        local size = inv.cache.getSize("frequent")
        if DINV and DINV.database and DINV.database.getStatus then
            size = tonumber(DINV.database.getStatus().consumableTemplates) or size
        end
        local maxSize = inv.cache.table.frequentSize or inv.cache.defaults.frequentSize
        dbot.print(string.format("  @CFrequent:@W %d / %d entries", size, maxSize))
    end
    
    if cacheType == "all" or cacheType == "custom" then
        local size = inv.cache.getSize("custom")
        local maxSize = inv.cache.table.customSize or inv.cache.defaults.customSize
        dbot.print(string.format("  @CCustom:@W   %d / %d entries", size, maxSize))
    end
    
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- End of inv cache module
----------------------------------------------------------------------------------------------------

dbot.debug("inv.cache module loaded", "inv.cache")
