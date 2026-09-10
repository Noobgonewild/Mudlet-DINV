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
    return DINV.database.saveModuleTable("snapshot", inv.snapshot.table)
end

function inv.snapshot.load()
    local value, retval = DINV.database.loadModuleTable("snapshot", inv.snapshot.reset)
    if value then inv.snapshot.table = value end
    return retval
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

    local previous = inv.snapshot.table[name]
    inv.snapshot.table[name] = {
        created = os.time(),
        equipment = equipment
    }

    local saveRet = inv.snapshot.save()
    if saveRet ~= DRL_RET_SUCCESS then
        inv.snapshot.table[name] = previous
        return inv.tags.stop(invTagsSnapshot, endTag, saveRet)
    end
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
        return inv.tags.stop(invTagsSnapshot, endTag, DRL_RET_MISSING_ENTRY)
    end
    local previous = inv.snapshot.table[name]
    inv.snapshot.table[name] = nil
    local saveRet = inv.snapshot.save()
    if saveRet ~= DRL_RET_SUCCESS then
        inv.snapshot.table[name] = previous
        return inv.tags.stop(invTagsSnapshot, endTag, saveRet)
    end
    dbot.info("Deleted snapshot '" .. name .. "'")
    return inv.tags.stop(invTagsSnapshot, endTag, DRL_RET_SUCCESS)
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
    return inv.tags.stop(invTagsSnapshot, endTag, DRL_RET_SUCCESS)
end

function inv.snapshot.display(name, endTag)
    if not name or name == "" then
        dbot.warn("inv.snapshot.display: missing snapshot name")
        return inv.tags.stop(invTagsSnapshot, endTag, DRL_RET_INVALID_PARAM)
    end
    if inv.snapshot.table[name] == nil then
        dbot.warn("Snapshot '" .. name .. "' does not exist")
        return inv.tags.stop(invTagsSnapshot, endTag, DRL_RET_MISSING_ENTRY)
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
        return inv.tags.stop(invTagsSnapshot, endTag, DRL_RET_MISSING_ENTRY)
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

    local desiredItems = {}
    local slotsToChange = {}
    for wearLoc, objId in pairs(equipment) do
        local objIdStr = tostring(objId)
        desiredItems[objIdStr] = wearLoc
        local currentWornLoc = inv.items.getStatField(objIdStr, invStatFieldWorn) or ""
        if currentWornLoc ~= wearLoc then
            table.insert(slotsToChange, { loc = wearLoc, id = objIdStr })
        end
    end

    local removedOccupants = {}
    for _, slot in ipairs(slotsToChange) do
        local occupantId = findWornAt(slot.loc)
        if occupantId and occupantId ~= slot.id and not removedOccupants[occupantId] then
            removedOccupants[occupantId] = true
            if desiredItems[occupantId] then
                inv.items.removeWornItem(occupantId)
            else
                inv.items.store("id " .. occupantId)
            end
        end

        local currentLoc = inv.items.getStatField(slot.id, invStatFieldWorn) or ""
        if currentLoc ~= "" and currentLoc ~= "not-worn" and currentLoc ~= "undefined"
            and not removedOccupants[slot.id] then
            removedOccupants[slot.id] = true
            inv.items.removeWornItem(slot.id)
        end
    end

    for _, slot in ipairs(slotsToChange) do
        local location = inv.items.getStatField(slot.id, invStatFieldLocation) or ""
        if not inv.items.isWorn(slot.id) and location ~= "" and location ~= "inventory" then
            inv.items.get("id " .. slot.id)
        end
        inv.items.wearItem(slot.id, slot.loc)
    end
    return inv.tags.stop(invTagsSnapshot, endTag, DRL_RET_SUCCESS)
end

dbot.debug("inv.snapshot module loaded", "inv.snapshot")
