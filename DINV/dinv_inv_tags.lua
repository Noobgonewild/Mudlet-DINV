----------------------------------------------------------------------------------------------------
-- INV Tags Module
-- End tag support for command completion
----------------------------------------------------------------------------------------------------

inv.tags           = {}
inv.tags.init      = {}
inv.tags.table     = {}
inv.tags.cleanup   = {}
inv.tags.stateName = "inv-tags.state"

invTagsRefresh   = invTagsRefresh or "refresh"
invTagsBuild     = invTagsBuild or "build"
invTagsSearch    = invTagsSearch or "search"
invTagsGet       = invTagsGet or "get"
invTagsPut       = invTagsPut or "put"
invTagsStore     = invTagsStore or "store"
invTagsKeyword   = invTagsKeyword or "keyword"
invTagsOrganize  = invTagsOrganize or "organize"
invTagsSet       = invTagsSet or "set"
invTagsWeapon    = invTagsWeapon or "weapon"
invTagsSnapshot  = invTagsSnapshot or "snapshot"
invTagsPriority  = invTagsPriority or "priority"
invTagsAnalyze   = invTagsAnalyze or "analyze"
invTagsUsage     = invTagsUsage or "usage"
invTagsCompare   = invTagsCompare or "compare"
invTagsCovet     = invTagsCovet or "covet"
invTagsBackup    = invTagsBackup or "backup"
invTagsReset     = invTagsReset or "reset"
invTagsConsume   = invTagsConsume or "consume"
invTagsPortal    = invTagsPortal or "portal"
invTagsVersion   = invTagsVersion or "version"
invTagsUnused    = invTagsUnused or "unused"

inv.tags.modules = table.concat({
    invTagsBuild, invTagsRefresh, invTagsSearch, invTagsGet, invTagsPut,
    invTagsStore, invTagsKeyword, invTagsOrganize, invTagsSet, invTagsSnapshot,
    invTagsWeapon, invTagsPriority, invTagsAnalyze, invTagsUsage, invTagsCompare,
    invTagsCovet, invTagsBackup, invTagsReset, invTagsConsume, invTagsPortal,
    invTagsVersion, invTagsUnused
}, " ")

drlInvTagOn      = "on"
drlInvTagOff     = "off"

----------------------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------------------

function inv.tags.init.atInstall()
    return DRL_RET_SUCCESS
end

function inv.tags.init.atActive()
    return inv.tags.load()
end

function inv.tags.fini(doSaveState)
    if doSaveState then
        return inv.tags.save()
    end
    return DRL_RET_SUCCESS
end

function inv.tags.save()
    if inv.tags.table == nil then
        return inv.tags.reset()
    end
    return dbot.storage.saveTable(dbot.backup.getCurrentDir() .. inv.tags.stateName,
                                   "inv.tags.table", inv.tags.table, true)
end

function inv.tags.load()
    local retval = dbot.storage.loadTable(dbot.backup.getCurrentDir() .. inv.tags.stateName, inv.tags.reset)
    if retval ~= DRL_RET_SUCCESS then
        dbot.warn("inv.tags.load: Failed to load tags table: " .. dbot.retval.getString(retval))
        return retval
    end
    return inv.tags.migrateLegacy()
end

function inv.tags.reset()
    inv.tags.table = {}
    for tag in inv.tags.modules:gmatch("%S+") do
        inv.tags.table[tag] = drlInvTagOff
    end
    inv.tags.table["tags"] = drlInvTagOn
    return inv.tags.save()
end

function inv.tags.migrateLegacy()
    if inv.tags.table == nil then
        return inv.tags.reset()
    end
    if inv.tags.table.enabled ~= nil then
        local legacy = inv.tags.table
        inv.tags.table = {}
        for tag in inv.tags.modules:gmatch("%S+") do
            local enabled = legacy.enabled[tag]
            if enabled == nil then
                enabled = legacy.defaultEnabled == true
            end
            inv.tags.table[tag] = enabled and drlInvTagOn or drlInvTagOff
        end
        inv.tags.table["tags"] = drlInvTagOn
        return inv.tags.save()
    end
    return DRL_RET_SUCCESS
end

function inv.tags.enable()
    inv.tags.table["tags"] = drlInvTagOn
    dbot.info("Tags module is @GENABLED@W (specific tags may or may not be enabled)")
    return inv.tags.save()
end

function inv.tags.disable()
    inv.tags.table["tags"] = drlInvTagOff
    dbot.info("Tags module is @RDISABLED@W (individual tag status is ignored when the module is disabled)")
    return inv.tags.save()
end

function inv.tags.isEnabled()
    if inv.tags.table == nil or inv.tags.table["tags"] == nil then
        inv.tags.reset()
    end
    return inv.tags.table ~= nil and inv.tags.table["tags"] == drlInvTagOn
end

function inv.tags.display()
    local isEnabled = inv.tags.isEnabled() and "@GENABLED@W" or "@RDISABLED@W"
    dbot.print("@y" .. pluginNameAbbr .. "@W : tags are " .. isEnabled)
    dbot.print("@WSupported tags")
    for tag in inv.tags.modules:gmatch("%S+") do
        local tagValue = inv.tags.table[tag] or "uninitialized"
        local valuePrefix = (tagValue == drlInvTagOn) and "@G" or "@R"
        dbot.print(string.format("@C  %10s@W = ", tag) .. valuePrefix .. tagValue)
    end
    return DRL_RET_SUCCESS
end

function inv.tags.set(tagNames, tagValue)
    local retval = DRL_RET_SUCCESS
    if (tagValue ~= drlInvTagOn) and (tagValue ~= drlInvTagOff) then
        dbot.warn("inv.tags.set: Invalid tag value \"" .. (tagValue or "nil") .. "\"")
        return DRL_RET_INVALID_PARAM
    end
    for tag in tagNames:gmatch("%S+") do
        if dbot.isWordInString(tag, inv.tags.modules) then
            inv.tags.table[tag] = tagValue
            local valuePrefix = (tagValue == drlInvTagOn) and "@G" or "@R"
            dbot.note("Set tag \"@C" .. tag .. "@W\" to \"" .. valuePrefix .. tagValue .. "@W\"")
        else
            dbot.warn("inv.tags.set: Failed to set tag \"@C" .. tag .. "@W\": Unsupported tag")
            retval = DRL_RET_INVALID_PARAM
        end
    end
    local saveRetval = inv.tags.save()
    if (saveRetval ~= DRL_RET_SUCCESS) and (retval ~= DRL_RET_UNINITIALIZED) then
        dbot.warn("inv.tags.set: Failed to save tags persistent data: " .. dbot.retval.getString(saveRetval))
    end
    if (retval == DRL_RET_SUCCESS) and (saveRetval ~= DRL_RET_SUCCESS) then
        return saveRetval
    end
    return retval
end

function inv.tags.start(moduleName, startTag)
    return DRL_RET_SUCCESS
end

function inv.tags.stop(moduleName, endTag, retval)
    if retval == nil then
        retval = DRL_RET_INTERNAL_ERROR
    end
    if endTag == nil then
        return retval
    end
    if endTag.cleanupFn ~= nil then
        endTag.cleanupFn(endTag, retval)
    else
        inv.tags.cleanup.info(endTag, retval)
    end
    if (moduleName ~= nil) and (endTag.tagMsg ~= nil) and (endTag.tagMsg ~= "") and
        (inv.tags.table ~= nil) and (inv.tags.table[moduleName] == drlInvTagOn) and
        inv.tags.isEnabled() then
        local tagMsg = "{/" .. endTag.tagMsg .. ":" .. dbot.getTime() - endTag.startTime .. ":" ..
            retval .. ":" .. dbot.retval.getString(retval) .. "}"
        local charState = dbot.gmcp.getState()
        if (charState == dbot.stateActive) or (charState == dbot.stateCombat) or
            (charState == dbot.stateSleeping) or (charState == dbot.stateTBD) or
            (charState == dbot.stateResting) or (charState == dbot.stateRunning) then
            dbot.execute.fast.command("echo " .. tagMsg)
        else
            dbot.warn("You are in state \"@C" .. dbot.gmcp.getStateString(charState) ..
                "@W\": Could not echo end tag \"@G" .. tagMsg .. "@W\"")
        end
    end
    return retval
end

function inv.tags.new(tagMsg, infoMsg, setupFn, cleanupFn)
    local newTag = {
        tagMsg = tagMsg or "",
        infoMsg = infoMsg or "",
        cleanupFn = cleanupFn,
        startTime = dbot.getTime()
    }
    if setupFn ~= nil then
        setupFn(newTag)
    end
    return newTag
end

function inv.tags.cleanup.timed(tag, retval)
    if (tag == nil) or (retval == nil) then
        return
    end
    local executionTime = dbot.getTime() - tag.startTime
    local minutes = math.floor(executionTime / 60)
    local seconds = executionTime - (minutes * 60)
    local timeString = ""
    if minutes == 1 then
        timeString = minutes .. " minute, "
    elseif minutes > 1 then
        timeString = minutes .. " minutes, "
    end
    if seconds == 1 then
        timeString = timeString .. seconds .. " second"
    else
        timeString = timeString .. seconds .. " seconds"
    end
    if (tag.infoMsg ~= nil) and (tag.infoMsg ~= "") then
        dbot.info(tag.infoMsg .. " (@C" .. timeString .. "@W): " .. dbot.retval.getString(retval))
    else
        dbot.info("Total time for command: " .. timeString)
    end
end

function inv.tags.cleanup.info(tag, retval)
    if (tag == nil) or (retval == nil) then
        return
    end
    if (tag.infoMsg ~= nil) and (tag.infoMsg ~= "") then
        dbot.info(tag.infoMsg .. ": " .. dbot.retval.getString(retval))
    end
end

dbot.debug("inv.tags module loaded", "inv.tags")
