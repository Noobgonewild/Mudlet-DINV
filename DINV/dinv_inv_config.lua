----------------------------------------------------------------------------------------------------
-- INV Config Module
-- Configuration management for the inventory system
----------------------------------------------------------------------------------------------------

inv.config           = {}
inv.config.init      = {}
inv.config.table     = {}
inv.config.stateName = "inv-config.state"

----------------------------------------------------------------------------------------------------
-- Default Configuration Values
----------------------------------------------------------------------------------------------------

local configDefaults = {
    -- Refresh settings
    isRefreshEnabled = true,
    refreshPeriodMin = 5,
    refreshEagerSec = 0,
    
    -- Backup settings
    isBackupEnabled = true,
    
    -- Regen ring settings
    isRegenEnabled = false,
    regenOrigObjId = 0,
    regenNewObjId = 0,
    
    -- Prompt tracking
    isPromptEnabled = true,
    
    -- Organize settings
    organizeRules = {},
    
    -- Ignore settings
    ignoreContainers = {},
    ignoreKeyrings = true,

    -- Report settings
    reportChannel = "echo",

    -- Priority defaults
    defaultPriorityName = nil,
}

----------------------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------------------

function inv.config.init.atInstall()
    return DRL_RET_SUCCESS
end

function inv.config.init.atActive()
    local retval = inv.config.load()
    if retval ~= DRL_RET_SUCCESS then
        dbot.warn("inv.config.init.atActive: Failed to load config data from storage: " ..
                  dbot.retval.getString(retval))
    end
    
    -- Restore prompt state if needed
    if inv.config.table.isPromptEnabled ~= nil and
       inv.config.table.isPromptEnabled ~= dbot.prompt.isEnabled then
        dbot.info("Prompt state does not match expected state: toggling prompt")
        send("prompt")
    end
    
    -- Initialize regen module if available
    if inv.regen and inv.regen.init then
        inv.regen.init()
    end
    
    return retval
end

function inv.config.fini(doSaveState)
    local retval = DRL_RET_SUCCESS
    
    if doSaveState then
        retval = inv.config.save()
        if retval ~= DRL_RET_SUCCESS and retval ~= DRL_RET_UNINITIALIZED then
            dbot.warn("inv.config.fini: Failed to save inv.config module data: " ..
                      dbot.retval.getString(retval))
        end
    end
    
    return retval
end

----------------------------------------------------------------------------------------------------
-- Save/Load/Reset Functions
----------------------------------------------------------------------------------------------------

function inv.config.save()
    if inv.config.table == nil then
        return inv.config.reset()
    end
    
    return dbot.storage.saveTable(dbot.backup.getCurrentDir() .. inv.config.stateName,
                                   "inv.config.table", inv.config.table, true)
end

function inv.config.load()
    return dbot.storage.loadTable(dbot.backup.getCurrentDir() .. inv.config.stateName, inv.config.reset)
end

function inv.config.reset()
    inv.config.table = dbot.table.getCopy(configDefaults)
    return DRL_RET_SUCCESS
end

function inv.config.new()
    return inv.config.reset()
end

----------------------------------------------------------------------------------------------------
-- Configuration Getters/Setters
----------------------------------------------------------------------------------------------------

function inv.config.get(key)
    if inv.config.table == nil then
        inv.config.reset()
    end
    return inv.config.table[key]
end

function inv.config.set(key, value, skipSave)
    if inv.config.table == nil then
        inv.config.reset()
    end
    inv.config.table[key] = value

    if skipSave then
        return DRL_RET_SUCCESS
    end

    -- Persist configuration changes immediately so runtime setting updates
    -- (for example refresh period changes) survive client/plugin restarts.
    local saveRet = inv.config.save()
    if saveRet ~= DRL_RET_SUCCESS and saveRet ~= DRL_RET_UNINITIALIZED then
        dbot.warn("inv.config.set: Failed to persist key '" .. tostring(key) .. "': " ..
                  dbot.retval.getString(saveRet))
        return saveRet
    end

    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Specific Configuration Functions
----------------------------------------------------------------------------------------------------

function inv.config.isRefreshEnabled()
    return inv.config.get("isRefreshEnabled") == true
end

function inv.config.setRefreshEnabled(enabled)
    return inv.config.set("isRefreshEnabled", enabled == true)
end

function inv.config.getRefreshPeriod()
    return inv.config.get("refreshPeriodMin") or 5
end

function inv.config.setRefreshPeriod(minutes)
    return inv.config.set("refreshPeriodMin", tonumber(minutes) or 5)
end

function inv.config.isBackupEnabled()
    return inv.config.get("isBackupEnabled") == true
end

function inv.config.setBackupEnabled(enabled)
    return inv.config.set("isBackupEnabled", enabled == true)
end

function inv.config.isRegenEnabled()
    return inv.config.get("isRegenEnabled") == true
end

function inv.config.setRegenEnabled(enabled)
    return inv.config.set("isRegenEnabled", enabled == true)
end

function inv.config.getReportChannel()
    return inv.config.get("reportChannel") or "echo"
end

function inv.config.setReportChannel(channel)
    if channel == nil or channel == "" then
        return inv.config.set("reportChannel", "echo")
    end
    return inv.config.set("reportChannel", channel)
end

----------------------------------------------------------------------------------------------------
-- Ignore List Management
----------------------------------------------------------------------------------------------------

function inv.config.isIgnored(containerId)
    local ignoreList = inv.config.get("ignoreContainers") or {}
    return ignoreList[tostring(containerId)] == true
end

function inv.config.addIgnore(containerId)
    if inv.config.table.ignoreContainers == nil then
        inv.config.table.ignoreContainers = {}
    end
    inv.config.table.ignoreContainers[tostring(containerId)] = true
    return DRL_RET_SUCCESS
end

function inv.config.removeIgnore(containerId)
    if inv.config.table.ignoreContainers then
        inv.config.table.ignoreContainers[tostring(containerId)] = nil
    end
    return DRL_RET_SUCCESS
end

function inv.config.listIgnored()
    local ignoreList = inv.config.get("ignoreContainers") or {}
    local count = 0
    
    dbot.print("@WIgnored Containers:@w")
    for containerId, _ in pairs(ignoreList) do
        dbot.print("  @G" .. containerId .. "@w")
        count = count + 1
    end
    
    if count == 0 then
        dbot.print("  @Y(none)@w")
    end
    
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Organize Rules Management
----------------------------------------------------------------------------------------------------

function inv.config.addOrganizeRule(containerName, query)
    if inv.config.table.organizeRules == nil then
        inv.config.table.organizeRules = {}
    end
    
    if inv.config.table.organizeRules[containerName] == nil then
        inv.config.table.organizeRules[containerName] = {}
    end
    
    table.insert(inv.config.table.organizeRules[containerName], query)
    return DRL_RET_SUCCESS
end

function inv.config.clearOrganizeRules(containerName)
    if inv.config.table.organizeRules then
        if containerName then
            inv.config.table.organizeRules[containerName] = nil
        else
            inv.config.table.organizeRules = {}
        end
    end
    return DRL_RET_SUCCESS
end

function inv.config.displayOrganizeRules()
    local rules = inv.config.get("organizeRules") or {}
    local count = 0
    
    dbot.print("@WOrganize Rules:@w")
    for containerName, queries in pairs(rules) do
        dbot.print("  @CContainer:@W " .. containerName)
        for i, query in ipairs(queries) do
            dbot.print("    @G" .. i .. ".@w " .. query)
            count = count + 1
        end
    end
    
    if count == 0 then
        dbot.print("  @Y(no rules defined)@w")
    end
    
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- End of inv config module
----------------------------------------------------------------------------------------------------

dbot.debug("inv.config module loaded", "inv.config")
