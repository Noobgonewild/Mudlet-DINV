----------------------------------------------------------------------------------------------------
-- DINV Notify Module
-- Controls user-facing info/warn/note message visibility
----------------------------------------------------------------------------------------------------

-- Keep notify namespace on dbot for compatibility with dbot.modules init lifecycle.
dbot.notify = dbot.notify or {}
dbot.notify.init = dbot.notify.init or {}
dbot.notify.name = "dbot-notify.state"

dbot.notify.defaults = {
    info = true,
    warn = true,
    note = true,
}

dbot.notify.table = dbot.notify.table or {
    channels = {
        info = true,
        warn = true,
        note = true,
    }
}

local function normalizeChannel(channel)
    local value = tostring(channel or ""):lower()
    if value == "info" or value == "warn" or value == "note" then
        return value
    end
    return nil
end

local function normalizeFlag(value)
    local normalized = tostring(value or ""):lower()
    if normalized == "on" or normalized == "true" or normalized == "1" or normalized == "yes" then
        return true
    end
    if normalized == "off" or normalized == "false" or normalized == "0" or normalized == "no" then
        return false
    end
    return nil
end

function dbot.notify.reset()
    dbot.notify.table = {
        channels = {
            info = dbot.notify.defaults.info,
            warn = dbot.notify.defaults.warn,
            note = dbot.notify.defaults.note,
        }
    }
    return DRL_RET_SUCCESS
end

function dbot.notify.save()
    if dbot.notify.table == nil then
        return dbot.notify.reset()
    end
    return dbot.storage.saveTable(
        dbot.backup.getCurrentDir() .. dbot.notify.name,
        "dbot.notify.table",
        dbot.notify.table,
        true
    )
end

function dbot.notify.load()
    return dbot.storage.loadTable(dbot.backup.getCurrentDir() .. dbot.notify.name, dbot.notify.reset)
end

function dbot.notify.init.atInstall()
    if dbot.notify.table == nil then
        return dbot.notify.reset()
    end
    return DRL_RET_SUCCESS
end

function dbot.notify.init.atActive()
    local retval = dbot.notify.load()
    if retval ~= DRL_RET_SUCCESS then
        dbot.notify.reset()
    end

    dbot.notify.table.channels = dbot.notify.table.channels or {}
    for channel, defaultValue in pairs(dbot.notify.defaults) do
        if dbot.notify.table.channels[channel] == nil then
            dbot.notify.table.channels[channel] = defaultValue
        end
    end

    return DRL_RET_SUCCESS
end

function dbot.notify.fini(doSaveState)
    if doSaveState then
        dbot.notify.save()
    end
    return DRL_RET_SUCCESS
end

function dbot.notify.get(channel)
    local normalized = normalizeChannel(channel)
    if not normalized then
        return nil
    end

    local channels = (dbot.notify.table and dbot.notify.table.channels) or {}
    if channels[normalized] == nil then
        return dbot.notify.defaults[normalized] == true
    end

    return channels[normalized] == true
end

function dbot.notify.shouldShow(channel)
    local value = dbot.notify.get(channel)
    if value == nil then
        return true
    end
    return value
end

function dbot.notify.set(channel, flag, isVerbose)
    local normalized = normalizeChannel(channel)
    local enabled = normalizeFlag(flag)

    if not normalized or enabled == nil then
        return DRL_RET_INVALID_PARAM
    end

    dbot.notify.table = dbot.notify.table or {}
    dbot.notify.table.channels = dbot.notify.table.channels or {}
    dbot.notify.table.channels[normalized] = enabled

    local retval = dbot.notify.save()
    if retval ~= DRL_RET_SUCCESS then
        return retval
    end

    if isVerbose then
        local state = enabled and "ON" or "OFF"
        dbot.printRaw(string.format("@W[DINV] notify %s is now @Y%s@W.", normalized, state))
    end

    return DRL_RET_SUCCESS
end

function dbot.notify.statusLines()
    local infoState = dbot.notify.get("info") and "on" or "off"
    local warnState = dbot.notify.get("warn") and "on" or "off"
    local noteState = dbot.notify.get("note") and "on" or "off"

    return {
        "Notify channels:",
        "  info = " .. infoState,
        "  warn = " .. warnState,
        "  note = " .. noteState,
    }
end

function dbot.notify.showStatus()
    for _, line in ipairs(dbot.notify.statusLines()) do
        dbot.printRaw("@W" .. line)
    end
end
