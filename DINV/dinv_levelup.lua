----------------------------------------------------------------------------------------------------
-- DINV Level-up Module
-- Controls level-up recommendation mode and lightweight level-up debug line
----------------------------------------------------------------------------------------------------

inv.levelup = inv.levelup or {}
inv.levelup.init = inv.levelup.init or {}
inv.levelup.name = "inv-levelup.state"

inv.levelup.defaults = {
    armed = false,
    mode = "cache",
    debug = false,
}

inv.levelup.table = inv.levelup.table or {
    armed = inv.levelup.defaults.armed,
    mode = inv.levelup.defaults.mode,
    debug = inv.levelup.defaults.debug,
}

local function normalizeMode(mode)
    local value = tostring(mode or ""):lower()
    if value == "off" or value == "cache" or value == "live" then
        return value
    end
    return nil
end

local function normalizeFlag(flag)
    local value = tostring(flag or ""):lower()
    if value == "on" or value == "true" or value == "1" or value == "yes" then
        return true
    end
    if value == "off" or value == "false" or value == "0" or value == "no" then
        return false
    end
    return nil
end

function inv.levelup.reset()
    inv.levelup.table = {
        armed = inv.levelup.defaults.armed,
        mode = inv.levelup.defaults.mode,
        debug = inv.levelup.defaults.debug,
    }
    return DRL_RET_SUCCESS
end

function inv.levelup.save()
    if inv.levelup.table == nil then
        return inv.levelup.reset()
    end
    return dbot.storage.saveTable(
        dbot.backup.getCurrentDir() .. inv.levelup.name,
        "inv.levelup.table",
        inv.levelup.table,
        true
    )
end

function inv.levelup.load()
    return dbot.storage.loadTable(dbot.backup.getCurrentDir() .. inv.levelup.name, inv.levelup.reset)
end

function inv.levelup.init.atInstall()
    if inv.levelup.table == nil then
        return inv.levelup.reset()
    end
    return DRL_RET_SUCCESS
end

function inv.levelup.init.atActive()
    local retval = inv.levelup.load()
    if retval ~= DRL_RET_SUCCESS then
        inv.levelup.reset()
    end

    if normalizeMode(inv.levelup.table.mode) == nil then
        inv.levelup.table.mode = inv.levelup.defaults.mode
    end
    if inv.levelup.table.armed == nil then
        inv.levelup.table.armed = inv.levelup.defaults.armed
    end
    if inv.levelup.table.debug == nil then
        inv.levelup.table.debug = inv.levelup.defaults.debug
    end

    return DRL_RET_SUCCESS
end

function inv.levelup.getMode()
    if not (inv.levelup.table and inv.levelup.table.armed) then
        return "off"
    end
    return normalizeMode(inv.levelup.table and inv.levelup.table.mode) or inv.levelup.defaults.mode
end

function inv.levelup.isArmed()
    return inv.levelup.table and inv.levelup.table.armed == true
end

function inv.levelup.getArmedMode()
    if not inv.levelup.isArmed() then
        return nil
    end
    return normalizeMode(inv.levelup.table and inv.levelup.table.mode) or inv.levelup.defaults.mode
end

function inv.levelup.setMode(mode, isVerbose)
    local normalized = normalizeMode(mode)
    if not normalized then
        return DRL_RET_INVALID_PARAM
    end

    if normalized == "off" then
        inv.levelup.table.armed = false
    else
        inv.levelup.table.armed = true
        inv.levelup.table.mode = normalized
    end
    local retval = inv.levelup.save()
    if retval ~= DRL_RET_SUCCESS then
        return retval
    end

    if isVerbose then
        if normalized == "off" then
            dbot.info("Level-up trigger disarmed.")
        else
            dbot.info("Level-up trigger armed in '" .. normalized .. "' mode.")
        end
    end

    return DRL_RET_SUCCESS
end

function inv.levelup.getDebug()
    return inv.levelup.table and inv.levelup.table.debug == true
end

function inv.levelup.setDebug(flag, isVerbose)
    local enabled = normalizeFlag(flag)
    if enabled == nil then
        return DRL_RET_INVALID_PARAM
    end

    inv.levelup.table.debug = enabled
    local retval = inv.levelup.save()
    if retval ~= DRL_RET_SUCCESS then
        return retval
    end

    if isVerbose then
        dbot.note("Level-up debug is now " .. (enabled and "ON" or "OFF") .. ".")
    end

    return DRL_RET_SUCCESS
end
