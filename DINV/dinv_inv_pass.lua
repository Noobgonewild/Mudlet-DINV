----------------------------------------------------------------------------------------------------
-- INV Pass Module
-- Area pass management
----------------------------------------------------------------------------------------------------

invTagsPass = invTagsPass or "pass"

inv.pass = inv.pass or {}
inv.pass.timerByPass = inv.pass.timerByPass or {}

function inv.pass.use(passNameOrId, useTimeSec, endTag)
    if (passNameOrId == nil) or (passNameOrId == "") then
        dbot.warn("inv.pass.use: Missing pass name")
        return inv.tags.stop(invTagsPass, endTag, DRL_RET_INVALID_PARAM)
    end

    useTimeSec = tonumber(useTimeSec or "")
    if (useTimeSec == nil) then
        dbot.warn("inv.pass.use: useTimeSec parameter is not a number")
        return inv.tags.stop(invTagsPass, endTag, DRL_RET_INVALID_PARAM)
    end

    local query = "id " .. tostring(passNameOrId) .. " || name " .. tostring(passNameOrId)
    local getRet = inv.items.get(query)
    if getRet ~= DRL_RET_SUCCESS then
        dbot.warn("inv.pass.use: Failed to get pass '" .. tostring(passNameOrId) .. "'")
        return inv.tags.stop(invTagsPass, endTag, getRet)
    end

    local existingTimer = inv.pass.timerByPass[passNameOrId]
    if existingTimer and killTimer then
        pcall(killTimer, existingTimer)
        inv.pass.timerByPass[passNameOrId] = nil
    end

    if tempTimer then
        local timerId = tempTimer(useTimeSec, function()
            inv.items.store(query)
            inv.pass.timerByPass[passNameOrId] = nil
        end)
        inv.pass.timerByPass[passNameOrId] = timerId
    else
        dbot.warn("inv.pass.use: tempTimer is unavailable; pass will not auto-store")
        return inv.tags.stop(invTagsPass, endTag, DRL_RET_UNSUPPORTED)
    end

    dbot.info("Using pass '" .. tostring(passNameOrId) .. "' for " .. tostring(useTimeSec) .. " second(s)")
    return inv.tags.stop(invTagsPass, endTag, DRL_RET_SUCCESS)
end

dbot.debug("inv.pass module loaded", "inv.pass")
