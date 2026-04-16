----------------------------------------------------------------------------------------------------
-- INV Portal Module
-- Portal item management
----------------------------------------------------------------------------------------------------

inv.portal = {}

if _G.dinvPortalUseWornPortalId == nil then
    _G.dinvPortalUseWornPortalId = nil
end
if remember then
    remember("dinvPortalUseWornPortalId")
end

function inv.portal.noteRemoved(objId, wearLoc)
    local numericLoc = tonumber(wearLoc)
    local mappedLoc = numericLoc and inv.wearLoc and inv.wearLoc[numericLoc] or nil
    if mappedLoc == invWearLocPortal or numericLoc == 31 or numericLoc == 32 then
        inv.portal.lastRemovedPortalId = objId
    end
end

function inv.portal.use(query, endTag)
    if inv.items.table == nil or dbot.table.getNumEntries(inv.items.table) == 0 then
        dbot.info("Your inventory table is empty. Run '@Gdinv build confirm@W' to populate it.")
        return inv.tags.stop(invTagsPortal, endTag, DRL_RET_UNINITIALIZED)
    end

    local portalQuery = tostring(query or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if portalQuery:lower():match("^use%s+") then
        portalQuery = portalQuery:gsub("^%s*[Uu][Ss][Ee]%s+", "")
    end

    local portalId = portalQuery:match("^id%s+(%d+)%s*$")
    if portalId then
        portalId = tonumber(portalId)
    else
        portalId = tonumber(portalQuery)
    end

    if not portalId then
        if portalQuery == "" then
            dbot.warn("inv.portal.use: Missing portal query parameter")
            return inv.tags.stop(invTagsPortal, endTag, DRL_RET_INVALID_PARAM)
        end

        local idArray, retval = inv.items.search(portalQuery .. " type portal")
        if retval ~= DRL_RET_SUCCESS then
            dbot.warn("inv.portal.use: failed to search inventory table: " .. dbot.retval.getString(retval))
            return inv.tags.stop(invTagsPortal, endTag, retval)
        end

        if idArray == nil or #idArray == 0 then
            dbot.info("No match found for portal query: \"" .. (portalQuery or "nil") .. "\"")
            return inv.tags.stop(invTagsPortal, endTag, DRL_RET_MISSING_ENTRY)
        end

        if #idArray > 1 then
            dbot.warn("Found multiple portals matching query \"" .. (portalQuery or "nil") .. "\"")
        end

        portalId = idArray[1]
    end

    local function normalizeWearLoc(value)
        local numeric = tonumber(value)
        if numeric and inv.wearLoc then
            return inv.wearLoc[numeric] or tostring(value)
        end
        return value
    end

    local function getPortalDisplayName(itemId)
        local colorName = inv.items.getStatField(itemId, invStatFieldColorName)
        if colorName and colorName ~= "" then
            return colorName
        end

        if inv.items and inv.items.loadPersistentItemsTable then
            local persistedItems = inv.items.loadPersistentItemsTable()
            local persisted = persistedItems and persistedItems[tostring(itemId)]
            local persistedStats = persisted and persisted.stats or {}
            local persistedColor = persistedStats[invStatFieldColorName] or persistedStats.colorname
            if persistedColor and persistedColor ~= "" then
                return persistedColor
            end
        end

        return inv.items.getStatField(itemId, invStatFieldName) or tostring(itemId)
    end

    local portalLoc = normalizeWearLoc(inv.items.getStatField(portalId, invStatFieldLocation) or "") or ""
    if portalLoc == invWearLocPortal or portalLoc == invWearLocHold or portalLoc == invWearLocSecond then
        dbot.info("Entering portal: " .. getPortalDisplayName(portalId) .. "@W")
        return inv.tags.stop(invTagsPortal, endTag, dbot.execute.fast.command("enter"))
    end

    -- Capture currently worn portal item from persistence BEFORE sending command batch.
    local function isPortalSlotLocation(value)
        local asText = tostring(value or "")
        return asText == "31" or asText == invWearLocPortal
    end

    local function isPortalItemEntry(itemEntry)
        local stats = itemEntry and itemEntry.stats or {}
        local itemType = tostring(stats[invStatFieldType] or stats.type or "")
        return itemType:lower() == tostring(invItemTypePortal or "portal"):lower() or itemType:lower() == "portal"
    end

    local oldWornPortalId = nil
    if inv.items and inv.items.loadPersistentItemsTable then
        local persistedItems = inv.items.loadPersistentItemsTable()
        if persistedItems then
            for objId, itemEntry in pairs(persistedItems) do
                local stats = itemEntry and itemEntry.stats or {}
                local loc = stats[invStatFieldLocation] or stats.location or ""
                local wornLoc = stats[invStatFieldWorn] or stats.worn or ""
                if (isPortalSlotLocation(loc) or tostring(wornLoc) == invWearLocPortal)
                    and isPortalItemEntry(itemEntry) then
                    oldWornPortalId = tonumber(objId) or objId
                    break
                end
            end
        end
    end

    -- Fallback when persistence file is unavailable/stale in-session.
    if not oldWornPortalId then
        for objId in pairs(inv.items.table) do
            local currentLocRaw = inv.items.getStatField(objId, invStatFieldLocation) or ""
            local currentWorn = inv.items.getStatField(objId, invStatFieldWorn) or ""
            local currentLoc = normalizeWearLoc(currentLocRaw) or ""
            if isPortalSlotLocation(currentLocRaw)
                or currentLoc == invWearLocPortal
                or tostring(currentWorn) == invWearLocPortal then
                oldWornPortalId = objId
                break
            end
        end
    end

    local origId = oldWornPortalId
    local origLoc = invWearLocPortal

    inv.portal.pendingUseId = portalId
    inv.portal.lastRemovedPortalId = nil
    _G.dinvPortalUseWornPortalId = origId

    if origId == portalId then
        dbot.info("Entering portal: " .. getPortalDisplayName(portalId) .. "@W")
        return inv.tags.stop(invTagsPortal, endTag, dbot.execute.fast.command("enter"))
    end

    local commands = {}

    if origId ~= nil and origId ~= portalId then
        table.insert(commands, "remove " .. origId)
    end

    local objLoc = inv.items.getStatField(portalId, invStatFieldLocation) or ""
    local objLocNum = inv.items.normalizeContainerId(objLoc)
    local shouldReturnToContainer = objLoc ~= invItemLocInventory and objLoc ~= "" and objLocNum ~= nil
    if shouldReturnToContainer then
        table.insert(commands, "get " .. portalId .. " " .. objLocNum)
    end

    table.insert(commands, "hold " .. portalId)
    table.insert(commands, "enter")

    dbot.info("Using portal: " .. getPortalDisplayName(portalId) .. "@W")
    local retval = dbot.execute.safe.commands(commands, nil, nil, nil, nil)
    if retval ~= DRL_RET_SUCCESS then
        inv.portal.lastRemovedPortalId = nil
        inv.portal.pendingUseId = nil
        _G.dinvPortalUseWornPortalId = nil
        return inv.tags.stop(invTagsPortal, endTag, retval)
    end

    if shouldReturnToContainer then
        local postCommands = {}
        if origId ~= nil and origId ~= portalId then
            table.insert(postCommands, "wear " .. origId .. " " .. origLoc)
        else
            table.insert(postCommands, "remove " .. portalId)
        end
        table.insert(postCommands, "put " .. portalId .. " " .. objLocNum)
        retval = dbot.execute.safe.commands(postCommands, nil, nil, nil, nil)
    end
    inv.portal.lastRemovedPortalId = nil
    inv.portal.pendingUseId = nil
    _G.dinvPortalUseWornPortalId = nil
    return inv.tags.stop(invTagsPortal, endTag, retval)
end

dbot.debug("inv.portal module loaded", "inv.portal")
