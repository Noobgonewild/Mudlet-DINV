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
    reportMode = "classic",

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
    
    return DINV.database.saveModuleTable("config", inv.config.table)
end

function inv.config.load()
    local value, retval = DINV.database.loadModuleTable("config", inv.config.reset)
    if value then inv.config.table = value end
    return retval
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

function inv.config.getReportMode()
    return inv.config.get("reportMode") or "classic"
end

function inv.config.setReportMode(mode)
    local normalized = tostring(mode or ""):lower()
    if normalized ~= "classic" and normalized ~= "inline" and normalized ~= "off" then
        return DRL_RET_INVALID_PARAM
    end
    return inv.config.set("reportMode", normalized)
end

----------------------------------------------------------------------------------------------------
-- Ignore List Management
----------------------------------------------------------------------------------------------------

function inv.config.isIgnored(containerId)
    local ignoreList = inv.config.get("ignoreContainers") or {}
    return ignoreList[tostring(containerId)] == true
end

function inv.config.addIgnore(containerId)
    if inv.config.table == nil then
        inv.config.reset()
    end
    if inv.config.table.ignoreContainers == nil then
        inv.config.table.ignoreContainers = {}
    end
    inv.config.table.ignoreContainers[tostring(containerId)] = true

    local saveRet = inv.config.save()
    if saveRet ~= DRL_RET_SUCCESS and saveRet ~= DRL_RET_UNINITIALIZED then
        dbot.warn("inv.config.addIgnore: Failed to persist ignored container '" ..
                  tostring(containerId) .. "': " .. dbot.retval.getString(saveRet))
        return saveRet
    end

    return DRL_RET_SUCCESS
end

function inv.config.removeIgnore(containerId)
    if inv.config.table == nil then
        inv.config.reset()
    end
    if inv.config.table.ignoreContainers then
        inv.config.table.ignoreContainers[tostring(containerId)] = nil
    end

    local saveRet = inv.config.save()
    if saveRet ~= DRL_RET_SUCCESS and saveRet ~= DRL_RET_UNINITIALIZED then
        dbot.warn("inv.config.removeIgnore: Failed to persist ignored container '" ..
                  tostring(containerId) .. "': " .. dbot.retval.getString(saveRet))
        return saveRet
    end

    return DRL_RET_SUCCESS
end

function inv.config.listIgnored()
    local ignoreList = inv.config.get("ignoreContainers") or {}
    local count = 0
    
    local function getIgnoredDisplayLabel(containerId)
        local label = tostring(containerId)
        if label == tostring(invItemLocKeyring or "keyring") then
            return label
        end
        if inv.items and inv.items.getStatField then
            local colorName = inv.items.getStatField(containerId, invStatFieldColorName)
            if colorName == nil or tostring(colorName) == "" then
                colorName = inv.items.getStatField(containerId, invStatFieldName)
            end
            if colorName ~= nil and tostring(colorName) ~= "" then
                label = label .. " (" .. tostring(colorName) .. ")"
            end
        end
        return label
    end

    dbot.print("@WIgnored Containers:@w")
    for containerId, _ in pairs(ignoreList) do
        dbot.print("  @G" .. getIgnoredDisplayLabel(containerId) .. "@w")
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

local function trimOrganizeString(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function splitOrganizeQuery(query)
    local rules = {}
    for clause in tostring(query or ""):gmatch("[^|]+") do
        local trimmed = trimOrganizeString(clause)
        if trimmed ~= "" then
            table.insert(rules, trimmed)
        end
    end
    return rules
end

local function joinOrganizeRules(rules)
    local parts = {}
    if type(rules) == "table" then
        for _, rule in ipairs(rules) do
            local trimmed = trimOrganizeString(rule)
            if trimmed ~= "" then
                table.insert(parts, trimmed)
            end
        end
    end
    return table.concat(parts, " || ")
end

function inv.config.normalizeOrganizeRules()
    if inv.config.table == nil then
        inv.config.reset()
    end

    local current = inv.config.table.organizeRules
    if type(current) ~= "table" then
        current = {}
    end

    local normalized = {}
    for key, value in pairs(current) do
        local containerId = trimOrganizeString(key)
        local label = nil
        local query = ""

        if type(value) == "table" and (value.id or value.containerId or value.query or value.rules) then
            containerId = trimOrganizeString(value.id or value.containerId or key)
            label = value.label or value.name or value.containerName
            query = trimOrganizeString(value.query or joinOrganizeRules(value.rules))
        elseif type(value) == "table" then
            -- Legacy shape: organizeRules[containerName] = { "type potion", ... }
            label = tostring(key)
            query = joinOrganizeRules(value)
        elseif type(value) == "string" then
            query = trimOrganizeString(value)
        end

        if containerId ~= "" and query ~= "" then
            normalized[containerId] = {
                id = containerId,
                query = query,
                rules = splitOrganizeQuery(query),
            }
            if label ~= nil and tostring(label) ~= "" then
                normalized[containerId].label = tostring(label)
            end
        end
    end

    inv.config.table.organizeRules = normalized
    return normalized
end

function inv.config.getOrganizeRules()
    return inv.config.normalizeOrganizeRules()
end

function inv.config.getOrganizeRule(containerId)
    local normalizedId = trimOrganizeString(containerId)
    if normalizedId == "" then
        return nil
    end

    local rules = inv.config.getOrganizeRules()
    return rules[normalizedId]
end

function inv.config.getOrganizeQuery(containerId)
    local entry = inv.config.getOrganizeRule(containerId)
    if entry == nil then
        return ""
    end
    return trimOrganizeString(entry.query or joinOrganizeRules(entry.rules))
end

function inv.config.setOrganizeRule(containerId, query, label)
    local normalizedId = trimOrganizeString(containerId)
    local normalizedQuery = trimOrganizeString(query)
    if normalizedId == "" then
        return DRL_RET_INVALID_PARAM
    end

    local rules = inv.config.getOrganizeRules()
    if normalizedQuery == "" then
        rules[normalizedId] = nil
    else
        rules[normalizedId] = {
            id = normalizedId,
            query = normalizedQuery,
            rules = splitOrganizeQuery(normalizedQuery),
        }
        if label ~= nil and tostring(label) ~= "" then
            rules[normalizedId].label = tostring(label)
        end
    end

    return inv.config.save()
end

function inv.config.addOrganizeRule(containerId, query, label)
    local normalizedId = trimOrganizeString(containerId)
    local normalizedQuery = trimOrganizeString(query)
    if normalizedId == "" or normalizedQuery == "" then
        return DRL_RET_INVALID_PARAM
    end

    local existingQuery = inv.config.getOrganizeQuery(normalizedId)
    if existingQuery ~= "" then
        normalizedQuery = existingQuery .. " || " .. normalizedQuery
    end

    return inv.config.setOrganizeRule(normalizedId, normalizedQuery, label)
end

function inv.config.clearOrganizeRules(containerId)
    local rules = inv.config.getOrganizeRules()
    if containerId then
        rules[trimOrganizeString(containerId)] = nil
    else
        inv.config.table.organizeRules = {}
    end
    return inv.config.save()
end

function inv.config.displayOrganizeRules()
    local rules = inv.config.getOrganizeRules()
    local count = 0
    
    dbot.print("@WOrganize Rules:@w")
    for containerId, entry in pairs(rules) do
        local label = entry.label
        if label and label ~= "" then
            dbot.print("  @CContainer:@W " .. containerId .. " (" .. tostring(label) .. ")")
        else
            dbot.print("  @CContainer:@W " .. containerId)
        end

        for i, query in ipairs(entry.rules or splitOrganizeQuery(entry.query)) do
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
