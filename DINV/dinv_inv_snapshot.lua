----------------------------------------------------------------------------------------------------
-- INV Snapshot Module
-- Equipment set snapshots
----------------------------------------------------------------------------------------------------

inv.snapshot       = {}
inv.snapshot.init  = {}
inv.snapshot.table = {}
inv.snapshot.stateName = "inv-snapshot.state"

function inv.snapshot.init.atInstall()
    return DRL_RET_SUCCESS
end

function inv.snapshot.init.atActive()
    local retval = inv.snapshot.load()
    if retval ~= DRL_RET_SUCCESS then
        dbot.debug("inv.snapshot.init.atActive: Using fresh snapshot table", "inv.snapshot")
    end
    return DRL_RET_SUCCESS
end

function inv.snapshot.fini(doSaveState)
    if doSaveState then
        inv.snapshot.save()
    end
    return DRL_RET_SUCCESS
end

function inv.snapshot.save()
    if inv.snapshot.table == nil then
        return inv.snapshot.reset()
    end
    return dbot.storage.saveTable(dbot.backup.getCurrentDir() .. inv.snapshot.stateName,
                                   "inv.snapshot.table", inv.snapshot.table, true)
end

function inv.snapshot.load()
    return dbot.storage.loadTable(dbot.backup.getCurrentDir() .. inv.snapshot.stateName, inv.snapshot.reset)
end

function inv.snapshot.reset()
    inv.snapshot.table = {}
    return DRL_RET_SUCCESS
end

function inv.snapshot.create(name, endTag)
    if not name or name == "" then
        dbot.warn("inv.snapshot.create: missing snapshot name")
        return inv.tags.stop(invTagsSnapshot, endTag, DRL_RET_INVALID_PARAM)
    end
    dbot.info("Creating snapshot '" .. name .. "'")
    local equipment = {}

    for objId, item in pairs(inv.items.table or {}) do
        if inv.items.isWorn(objId) then
            local worn = inv.items.getStatField(objId, invStatFieldWorn) or item.worn
            local wearLoc = inv.items.getStatField(objId, invStatFieldWearable)
            if type(worn) == "string" and worn ~= "" then
                equipment[worn] = objId
            elseif wearLoc and wearLoc ~= "" then
                equipment[wearLoc] = objId
            end
        end
    end

    inv.snapshot.table[name] = {
        created = os.time(),
        equipment = equipment
    }

    dbot.info("Snapshot '" .. name .. "' saved with " .. dbot.table.getNumEntries(equipment) .. " item(s)")
    return inv.tags.stop(invTagsSnapshot, endTag, DRL_RET_SUCCESS)
end

function inv.snapshot.delete(name, endTag)
    if not name or name == "" then
        dbot.warn("inv.snapshot.delete: missing snapshot name")
        return inv.tags.stop(invTagsSnapshot, endTag, DRL_RET_INVALID_PARAM)
    end
    if inv.snapshot.table[name] == nil then
        dbot.warn("Snapshot '" .. name .. "' does not exist")
        return DRL_RET_MISSING_ENTRY
    end
    inv.snapshot.table[name] = nil
    dbot.info("Deleted snapshot '" .. name .. "'")
    return DRL_RET_SUCCESS
end

function inv.snapshot.list(endTag)
    dbot.print("@WSnapshots:@w")
    local count = 0
    for name, data in pairs(inv.snapshot.table) do
        local created = os.date("%Y-%m-%d %H:%M", data.created or 0)
        dbot.print("  @G" .. name .. "@W - " .. created)
        count = count + 1
    end
    if count == 0 then
        dbot.print("  @Y(none)@w")
    end
    return DRL_RET_SUCCESS
end

function inv.snapshot.display(name, endTag)
    if not name or name == "" then
        dbot.warn("inv.snapshot.display: missing snapshot name")
        return inv.tags.stop(invTagsSnapshot, endTag, DRL_RET_INVALID_PARAM)
    end
    if inv.snapshot.table[name] == nil then
        dbot.warn("Snapshot '" .. name .. "' does not exist")
        return DRL_RET_MISSING_ENTRY
    end
    dbot.print("@WSnapshot: @G" .. name .. "@w")
    local equipment = inv.snapshot.table[name].equipment or {}
    if dbot.table.getNumEntries(equipment) == 0 then
        dbot.print("  @Y(none)@w")
    else
        for loc, objId in pairs(equipment) do
            local itemName = inv.items.getStatField(objId, invStatFieldName) or "Unknown"
            dbot.print("  @C" .. loc .. "@W: @G" .. itemName .. "@w (" .. objId .. ")")
        end
    end
    return inv.tags.stop(invTagsSnapshot, endTag, DRL_RET_SUCCESS)
end

function inv.snapshot.wear(name, endTag)
    if not name or name == "" then
        dbot.warn("inv.snapshot.wear: missing snapshot name")
        return inv.tags.stop(invTagsSnapshot, endTag, DRL_RET_INVALID_PARAM)
    end
    if inv.snapshot.table[name] == nil then
        dbot.warn("Snapshot '" .. name .. "' does not exist")
        return DRL_RET_MISSING_ENTRY
    end
    dbot.info("Wearing snapshot '" .. name .. "'")
    local equipment = inv.snapshot.table[name].equipment or {}

    local function findWornAt(targetLoc)
        for objId, _ in pairs(inv.items.table or {}) do
            local wornLoc = inv.items.getStatField(objId, invStatFieldWorn) or ""
            if wornLoc == targetLoc then
                return tostring(objId)
            end
        end
        return nil
    end

    for wearLoc, objId in pairs(equipment) do
        local objIdStr = tostring(objId)
        local currentlyWorn = inv.items.getStatField(objIdStr, invStatFieldWorn) or ""
        local removedId = findWornAt(wearLoc)

        if currentlyWorn ~= wearLoc then
            local location = inv.items.getStatField(objIdStr, invStatFieldLocation) or ""
            if not inv.items.isWorn(objIdStr) and location ~= "" and location ~= "inventory" then
                inv.items.sendActionCommand("dinv get id " .. objIdStr)
            end
            inv.items.wearItem(objIdStr, wearLoc)
        end

        if removedId and removedId ~= objIdStr then
            inv.items.store("id " .. removedId)
        end
    end
    return inv.tags.stop(invTagsSnapshot, endTag, DRL_RET_SUCCESS)
end

dbot.debug("inv.snapshot module loaded", "inv.snapshot")
