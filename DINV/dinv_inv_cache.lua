----------------------------------------------------------------------------------------------------
-- INV Cache Module
-- Item identification cache management
----------------------------------------------------------------------------------------------------

inv.cache       = {}
inv.cache.init  = {}
inv.cache.table = {}
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
    local retval = inv.cache.load()
    if retval ~= DRL_RET_SUCCESS then
        dbot.debug("inv.cache.init.atActive: Using fresh cache", "inv.cache")
    end
    return DRL_RET_SUCCESS
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
    if inv.cache.table == nil then
        return inv.cache.reset()
    end
    return dbot.storage.saveTable(dbot.backup.getCurrentDir() .. inv.cache.stateName,
                                   "inv.cache.table", inv.cache.table, true)
end

function inv.cache.load()
    return dbot.storage.loadTable(dbot.backup.getCurrentDir() .. inv.cache.stateName, inv.cache.reset)
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
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Cache Operations
----------------------------------------------------------------------------------------------------

function inv.cache.get(cacheType, key)
    if inv.cache.table[cacheType] then
        return inv.cache.table[cacheType][key]
    end
    return nil
end

function inv.cache.set(cacheType, key, value)
    if inv.cache.table[cacheType] == nil then
        inv.cache.table[cacheType] = {}
    end
    inv.cache.table[cacheType][key] = value
    return DRL_RET_SUCCESS
end

function inv.cache.remove(cacheType, key)
    if inv.cache.table[cacheType] then
        inv.cache.table[cacheType][key] = nil
    end
    return DRL_RET_SUCCESS
end

function inv.cache.clear(cacheType)
    if cacheType == "all" then
        inv.cache.table.recent = {}
        inv.cache.table.frequent = {}
        inv.cache.table.custom = {}
    elseif inv.cache.table[cacheType] then
        inv.cache.table[cacheType] = {}
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
        inv.cache.table[sizeKey] = size
    end
    return DRL_RET_SUCCESS
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
