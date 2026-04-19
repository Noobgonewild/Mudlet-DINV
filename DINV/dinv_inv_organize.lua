----------------------------------------------------------------------------------------------------
-- INV Organize Module
-- Container organization - assigns search queries to containers and moves matching items
----------------------------------------------------------------------------------------------------

inv.organize = inv.organize or {}
inv.organize.init = inv.organize.init or {}
inv.items = inv.items or {}
inv.items.organize = inv.items.organize or {}

-- Tag for organize operations
invTagsOrganize = "organize"

----------------------------------------------------------------------------------------------------
-- Helper: Get container/item color name with proper fallbacks
----------------------------------------------------------------------------------------------------

function inv.organize.getColorName(objId)
    local strId = tostring(objId)

    -- First try: stats.colorname (where it's actually stored)
    local colorName = inv.items.getStatField(strId, "colorname")
    if colorName and colorName ~= "" then
        return colorName
    end

    -- Second try: stats.name
    local name = inv.items.getStatField(strId, "name")
    if name and name ~= "" then
        return name
    end

    -- Third try: direct item lookup
    local item = inv.items.table and inv.items.table[strId]
    if item then
        if item.stats then
            if item.stats.colorname and item.stats.colorname ~= "" then
                return item.stats.colorname
            end
            if item.stats.name and item.stats.name ~= "" then
                return item.stats.name
            end
        end
    end

    -- Final fallback
    return "Unknown (" .. strId .. ")"
end

----------------------------------------------------------------------------------------------------
-- Add an organize query to a container
----------------------------------------------------------------------------------------------------

function inv.organize.add(containerRef, queryString, endTag)
    if containerRef == nil or containerRef == "" then
        dbot.warn("inv.organize.add: Missing container reference")
        return inv.tags.stop(invTagsOrganize, endTag, DRL_RET_INVALID_PARAM)
    end

    if queryString == nil or queryString == "" then
        dbot.warn("inv.organize.add: Containers are not allowed to own all possible items (empty query)")
        return inv.tags.stop(invTagsOrganize, endTag, DRL_RET_INVALID_PARAM)
    end

    -- Find the container
    local objId = inv.organize.findContainer(containerRef)
    if objId == nil then
        return inv.tags.stop(invTagsOrganize, endTag, DRL_RET_MISSING_ENTRY)
    end

    -- Append the query to any previous organization queries for that container
    local organizeField = inv.items.getStatField(objId, invQueryKeyOrganize) or ""
    if organizeField ~= "" then
        organizeField = organizeField .. " || "
    end
    organizeField = organizeField .. queryString

    -- Set the organize field on the item
    inv.items.setStatField(objId, invQueryKeyOrganize, organizeField)
    inv.items.save()

    -- Add to custom cache for persistence
    if inv.cache and inv.cache.addCustom then
        inv.cache.addCustom(objId, "organize", organizeField)
        if inv.cache.saveCustom then
            inv.cache.saveCustom()
        end
    end

    local colorName = inv.organize.getColorName(objId)
    dbot.info("Added organization query \"@C" .. queryString ..
              "@W\" to container \"" .. colorName .. "@W\" (" .. objId .. ")")

    return inv.tags.stop(invTagsOrganize, endTag, DRL_RET_SUCCESS)
end

----------------------------------------------------------------------------------------------------
-- Clear organize queries from a container
----------------------------------------------------------------------------------------------------

function inv.organize.clear(containerRef, endTag)
    if containerRef == nil or containerRef == "" then
        dbot.warn("inv.organize.clear: Missing container reference")
        return inv.tags.stop(invTagsOrganize, endTag, DRL_RET_INVALID_PARAM)
    end

    -- Find the container
    local objId = inv.organize.findContainer(containerRef)
    if objId == nil then
        return inv.tags.stop(invTagsOrganize, endTag, DRL_RET_MISSING_ENTRY)
    end

    local colorName = inv.organize.getColorName(objId)

    -- Clear the organize field
    inv.items.setStatField(objId, invQueryKeyOrganize, "")
    inv.items.save()

    -- Update custom cache
    if inv.cache and inv.cache.addCustom then
        inv.cache.addCustom(objId, "organize", "")
        if inv.cache.saveCustom then
            inv.cache.saveCustom()
        end
    end

    dbot.info("Cleared all organization queries from container \"" .. colorName .. "@W\" (" .. objId .. ")")

    return inv.tags.stop(invTagsOrganize, endTag, DRL_RET_SUCCESS)
end

----------------------------------------------------------------------------------------------------
-- Display all containers with organize queries
----------------------------------------------------------------------------------------------------

function inv.organize.display(containerRef, endTag)
    local foundAny = false

    dbot.print("@WContainers that have associated organizational queries:@w")

    if inv.items.table == nil then
        dbot.print("@W  Inventory table not initialized@w")
        return inv.tags.stop(invTagsOrganize, endTag, DRL_RET_UNINITIALIZED)
    end

    if containerRef and containerRef ~= "" then
        local objId = inv.organize.findContainer(containerRef)
        if objId == nil then
            return inv.tags.stop(invTagsOrganize, endTag, DRL_RET_MISSING_ENTRY)
        end

        local organizeQuery = inv.items.getStatField(objId, invQueryKeyOrganize) or ""
        local colorName = inv.organize.getColorName(objId)
        if organizeQuery ~= "" then
            dbot.print("@W  " .. colorName .. "@W (" .. objId .. "): @C" .. organizeQuery .. "@w")
            return inv.tags.stop(invTagsOrganize, endTag, DRL_RET_SUCCESS)
        end

        dbot.print("@W  No containers with organizational queries were found@w")
        return inv.tags.stop(invTagsOrganize, endTag, DRL_RET_SUCCESS)
    end

    for objId, item in pairs(inv.items.table) do
        local organizeQuery = inv.items.getStatField(objId, invQueryKeyOrganize) or ""
        if organizeQuery ~= "" then
            local colorName = inv.organize.getColorName(objId)
            dbot.print("@W  " .. colorName .. "@W (" .. objId .. "): @C" .. organizeQuery .. "@w")
            foundAny = true
        end
    end

    if not foundAny then
        dbot.print("@W  No containers with organizational queries were found@w")
        return inv.tags.stop(invTagsOrganize, endTag, DRL_RET_SUCCESS)
    end

    return inv.tags.stop(invTagsOrganize, endTag, DRL_RET_SUCCESS)
end

----------------------------------------------------------------------------------------------------
-- Run the organize process
-- 1. Sends invdata to get FRESH inventory data
-- 2. Captures items currently in main inventory
-- 3. Matches items against organize rules by type
-- 4. Executes put commands with prompt suppression
----------------------------------------------------------------------------------------------------

inv.organize.runPkg = nil
inv.organize.triggerIds = {}

-- Type number to type name mapping (from Aardwolf)
inv.organize.typeNumToName = {
    [1] = "Light",
    [2] = "Scroll",
    [3] = "Wand",
    [4] = "Staff",
    [5] = "Weapon",
    [6] = "Treasure",
    [7] = "Armor",
    [8] = "Potion",
    [9] = "Furniture",
    [10] = "Trash",
    [11] = "Container",
    [12] = "Drink",
    [13] = "Key",
    [14] = "Food",
    [15] = "Boat",
    [16] = "Mobcorpse",
    [17] = "Corpse",
    [18] = "Fountain",
    [19] = "Pill",
    [20] = "Portal",
    [21] = "Beacon",
    [22] = "Giftcard",
    [23] = "Gold",
    [24] = "Raw Material",
    [25] = "Campfire",
}

function inv.organize.run(queryString, endTag)
    queryString = queryString or ""

    -- Check if another organize is in progress
    if inv.organize.runPkg ~= nil then
        dbot.info("Skipping request to organize inventory: another request is in progress")
        return inv.tags.stop(invTagsOrganize, endTag, DRL_RET_BUSY)
    end

    -- Get all organize rules from containers
    local organizeRules = {}
    for objId, item in pairs(inv.items.table) do
        local organizeQuery = inv.items.getStatField(objId, invQueryKeyOrganize) or ""
        if organizeQuery ~= "" then
            -- Parse the query to extract type conditions
            -- Format: "type armor" or "type armor || type weapon"
            local types = {}
            for clause in organizeQuery:gmatch("[^|]+") do
                clause = clause:match("^%s*(.-)%s*$")  -- trim
                local typeValue = clause:match("type%s+(%S+)")
                if typeValue then
                    table.insert(types, string.lower(typeValue))
                end
            end
            if #types > 0 then
                table.insert(organizeRules, {
                    containerId = tostring(objId),
                    containerName = inv.organize.getColorName(objId),
                    types = types,
                    query = organizeQuery
                })
            end
        end
    end

    -- Debug: Show parsed rules
    for _, rule in ipairs(organizeRules) do
        dbot.debug(string.format("Organize rule: container=%s, types={%s}, query=%s",
            rule.containerId, table.concat(rule.types, ", "), rule.query), "organize")
    end

    if #organizeRules == 0 then
        dbot.info("No organize rules defined. Falling back to lastStored/container/inventory.")
    end

    -- Store state for the async operation
    inv.organize.runPkg = {
        query = queryString,
        endTag = endTag,
        rules = organizeRules,
        pendingCommands = {},
        inventoryItems = {},
        capturingInvdata = false,
        phase = "invdata",
        numOrganized = 0,
        numFallbackStored = 0,
        numKeptInventory = 0
    }

    -- Register triggers
    inv.organize.registerTriggers()

    -- Suppress prompts during organize
    inv.organize.suppressPrompts(true)

    -- Send invdata to get fresh inventory (main inventory only, no container argument)
    dbot.debug("Sending invdata to get fresh inventory...", "organize")
    send("invdata", false)

    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Register triggers for organize operation
----------------------------------------------------------------------------------------------------

function inv.organize.registerTriggers()
    inv.organize.unregisterTriggers()

    -- IMPORTANT: Temporarily disable discovery triggers to prevent conflict
    if DINV and DINV.discovery and DINV.discovery.ids then
        for name, id in pairs(DINV.discovery.ids) do
            if id and type(id) == "number" and name ~= "invmon" then
                disableTrigger(id)
            end
        end
        dbot.debug("Organize: Disabled discovery triggers (except invmon)", "organize")
    end

    -- Trigger for invdata start
    inv.organize.triggerIds.invdataStart = tempRegexTrigger(
        "^\\{invdata\\}$",
        function()
            if inv.organize.runPkg and inv.organize.runPkg.phase == "invdata" then
                dbot.debug("Organize: invdata start received", "organize")
                inv.organize.runPkg.inventoryItems = {}
                deleteLine()
            end
        end
    )

    -- Trigger for invdata lines (item data)
    -- Format: objectid,flags,itemname,level,type,unique,wear-loc,timer
    inv.organize.triggerIds.invdataLine = tempRegexTrigger(
        "^(\\d+),",
        function()
            if inv.organize.runPkg and inv.organize.runPkg.phase == "invdata" then
                local line = getCurrentLine()
                dbot.debug("Organize: Raw invdata line: " .. (line or "nil"):sub(1, 80), "organize")
                inv.organize.parseInvdataLine(line)
                deleteLine()
            end
        end
    )

    -- Trigger for invdata end
    inv.organize.triggerIds.invdataEnd = tempRegexTrigger(
        "^\\{/invdata\\}$",
        function()
            if inv.organize.runPkg and inv.organize.runPkg.phase == "invdata" then
                dbot.debug("Organize: invdata end received, captured " ..
                    #inv.organize.runPkg.inventoryItems .. " items", "organize")
                deleteLine()
                inv.organize.processInventory()
            end
        end
    )

    -- Trigger for "You don't have that" errors
    inv.organize.triggerIds.dontHave = tempRegexTrigger(
        "^You don't have that\\.$",
        function()
            if inv.organize.runPkg and inv.organize.runPkg.phase == "execute" then
                deleteLine()
            end
        end
    )

    -- Trigger for successful put
    inv.organize.triggerIds.putSuccess = tempRegexTrigger(
        "^You put .+ in .+\\.$",
        function()
            if inv.organize.runPkg and inv.organize.runPkg.phase == "execute" then
                deleteLine()
            end
        end
    )
end

----------------------------------------------------------------------------------------------------
-- Unregister triggers
----------------------------------------------------------------------------------------------------

function inv.organize.unregisterTriggers()
    for name, id in pairs(inv.organize.triggerIds) do
        if id then
            killTrigger(id)
        end
    end
    inv.organize.triggerIds = {}

    -- Re-enable discovery triggers
    if DINV.discovery and DINV.discovery.ids then
        if DINV.discovery.ids.invdataStartAny then
            enableTrigger(DINV.discovery.ids.invdataStartAny)
        end
        if DINV.discovery.ids.invdataEnd then
            enableTrigger(DINV.discovery.ids.invdataEnd)
        end
        if DINV.discovery.ids.dataLine then
            enableTrigger(DINV.discovery.ids.dataLine)
        end
    end
end

----------------------------------------------------------------------------------------------------
-- Prompt suppression during organize
----------------------------------------------------------------------------------------------------

function inv.organize.suppressPrompts(enable)
    if enable then
        if not inv.organize.triggerIds.promptSuppress then
            inv.organize.triggerIds.promptSuppress = tempRegexTrigger(
                "^<[0-9]+/[0-9]+hp [0-9]+/[0-9]+mn [0-9]+/[0-9]+mv",
                function()
                    if inv.organize.runPkg then
                        deleteLine()
                    end
                end
            )
        end
        -- Also suppress empty lines
        if not inv.organize.triggerIds.emptySuppress then
            inv.organize.triggerIds.emptySuppress = tempRegexTrigger(
                "^\\s*$",
                function()
                    if inv.organize.runPkg then
                        deleteLine()
                    end
                end
            )
        end
    else
        if inv.organize.triggerIds.promptSuppress then
            killTrigger(inv.organize.triggerIds.promptSuppress)
            inv.organize.triggerIds.promptSuppress = nil
        end
        if inv.organize.triggerIds.emptySuppress then
            killTrigger(inv.organize.triggerIds.emptySuppress)
            inv.organize.triggerIds.emptySuppress = nil
        end
    end
end

----------------------------------------------------------------------------------------------------
-- Parse a single invdata line
-- Format: objectid,flags,itemname,level,type,unique,wear-loc,timer
----------------------------------------------------------------------------------------------------

function inv.organize.parseInvdataLine(line)
    if not line or line == "" then return end

    local pkg = inv.organize.runPkg
    if not pkg then return end

    -- Parse from both ends since item name can contain commas
    -- Start: objId,flags,
    local objId, flags, rest = line:match("^(%d+),([^,]*),(.+)$")
    if not objId then
        dbot.debug("Organize: Failed to parse invdata line: " .. line:sub(1, 50), "organize")
        return
    end

    -- Parse from end: ,level,type,unique,wearloc,timer
    local timer = rest:match(",([%-]?%d+)$")
    if timer then
        rest = rest:sub(1, -(#timer + 2))
    end

    local wearLoc = rest:match(",([%-]?%d+)$")
    if wearLoc then
        rest = rest:sub(1, -(#wearLoc + 2))
    end

    local unique = rest:match(",(%d+)$")
    if unique then
        rest = rest:sub(1, -(#unique + 2))
    end

    local typeNum = rest:match(",(%d+)$")
    if typeNum then
        rest = rest:sub(1, -(#typeNum + 2))
    end

    local level = rest:match(",(%d+)$")
    if level then
        rest = rest:sub(1, -(#level + 2))
    end

    local itemName = rest

    -- Convert type number to type name
    typeNum = tonumber(typeNum) or 0
    local typeName = inv.organize.typeNumToName[typeNum] or "Unknown"
    dbot.debug(string.format("Organize: Parsed item %s: typeNum=%d, typeName='%s', name=%s",
        objId, typeNum, typeName, (itemName or ""):sub(1, 30)), "organize")

    dbot.debug(string.format("Organize: Found item %s, type=%d (%s), name=%s",
        objId, typeNum, typeName, (itemName or ""):sub(1, 30)), "organize")

    -- Store the item info
    table.insert(pkg.inventoryItems, {
        objId = objId,
        typeNum = typeNum,
        typeName = string.lower(typeName),
        itemName = itemName or "Unknown",
        level = tonumber(level) or 0
    })
end

----------------------------------------------------------------------------------------------------
-- Process inventory items against organize rules
----------------------------------------------------------------------------------------------------

function inv.organize.processInventory()
    local pkg = inv.organize.runPkg
    if not pkg then return end

    local function isIgnoredDestination(containerId)
        if containerId == nil then
            return false
        end
        return inv.config and inv.config.isIgnored and inv.config.isIgnored(containerId) == true
    end

    dbot.debug("Organize: Processing " .. #pkg.inventoryItems .. " inventory items", "organize")

    local ruleCount = 0
    local fallbackCount = 0
    local keptCount = 0

    -- For each item in inventory, check if it matches any organize rule
    for _, item in ipairs(pkg.inventoryItems) do
        -- Skip containers themselves
        if item.typeNum == 11 then
            dbot.debug("Organize: Skipping container " .. item.objId, "organize")
        else
            local didMatchRule = false
            -- Check against each rule
            for _, rule in ipairs(pkg.rules) do
                local matches = false
                for _, ruleType in ipairs(rule.types) do
                    dbot.debug(string.format("Organize: Comparing item.typeName='%s' vs ruleType='%s'",
                        item.typeName, ruleType), "organize")
                    if item.typeName == ruleType then
                        matches = true
                        break
                    end
                end

                if matches then
                    dbot.debug(string.format("Organize: Item %s (%s) matches rule for container %s",
                        item.objId, item.typeName, rule.containerId), "organize")

                    if isIgnoredDestination(rule.containerId) then
                        dbot.debug(string.format("Organize: Skipping rule destination for item %s because container %s is ignored",
                            tostring(item.objId), tostring(rule.containerId)), "organize")
                        keptCount = keptCount + 1
                        didMatchRule = true
                    else
                        table.insert(pkg.pendingCommands, {
                            itemId = item.objId,
                            containerId = rule.containerId,
                            itemName = item.itemName,
                            containerName = rule.containerName,
                            destination = "rule"
                        })
                        didMatchRule = true
                        ruleCount = ruleCount + 1
                    end
                    break  -- Only organize to first matching container
                end
            end

            if not didMatchRule then
                local fallbackContainer = inv.items.resolveStoreContainer(item.objId)
                if fallbackContainer then
                    if isIgnoredDestination(fallbackContainer) then
                        dbot.debug(string.format("Organize: Skipping fallback destination for item %s because container %s is ignored",
                            tostring(item.objId), tostring(fallbackContainer)), "organize")
                        keptCount = keptCount + 1
                    else
                        table.insert(pkg.pendingCommands, {
                            itemId = item.objId,
                            containerId = fallbackContainer,
                            itemName = item.itemName,
                            containerName = fallbackContainer,
                            destination = "fallback"
                        })
                        fallbackCount = fallbackCount + 1
                    end
                else
                    keptCount = keptCount + 1
                end
            end
        end
    end

    pkg.numOrganized = ruleCount
    pkg.numFallbackStored = fallbackCount
    pkg.numKeptInventory = keptCount

    if #pkg.pendingCommands == 0 then
        dbot.info("No organize moves needed. Kept " .. keptCount .. " item(s) in inventory.")
        inv.organize.finish()
        return
    end

    dbot.info("Found @G" .. #pkg.pendingCommands .. "@W item(s) to move: " ..
        "@G" .. ruleCount .. "@W via rules, @G" .. fallbackCount .. "@W via lastStored/container fallback. " ..
        "Keeping @G" .. keptCount .. "@W in inventory.")

    -- Start executing commands
    pkg.phase = "execute"
    pkg.commandIndex = 1
    inv.organize.executeNext()
end

----------------------------------------------------------------------------------------------------
-- Execute put commands one at a time
----------------------------------------------------------------------------------------------------

function inv.organize.executeNext()
    local pkg = inv.organize.runPkg
    if not pkg then return end

    if pkg.commandIndex > #pkg.pendingCommands then
        inv.organize.finish()
        return
    end

    local cmd = pkg.pendingCommands[pkg.commandIndex]
    local putCmd = "put " .. cmd.itemId .. " " .. cmd.containerId

    dbot.debug("Organize: " .. putCmd, "organize")

    send(putCmd, false)
    pkg.commandIndex = pkg.commandIndex + 1

    -- Schedule next command with delay
    if pkg.commandIndex <= #pkg.pendingCommands then
        tempTimer(0.1, function()
            inv.organize.executeNext()
        end)
    else
        -- All commands sent, wait then finish
        tempTimer(0.3, function()
            inv.organize.finish()
        end)
    end
end

----------------------------------------------------------------------------------------------------
-- Finish the organize operation
----------------------------------------------------------------------------------------------------

function inv.organize.finish()
    local pkg = inv.organize.runPkg
    if not pkg then return end

    -- Unregister triggers
    inv.organize.unregisterTriggers()

    -- Restore prompts
    inv.organize.suppressPrompts(false)

    local movedTotal = (pkg.numOrganized or 0) + (pkg.numFallbackStored or 0)
    if movedTotal > 0 then
        dbot.info("Stored @G" .. movedTotal .. "@W item(s): " ..
            "@G" .. tostring(pkg.numOrganized or 0) .. "@W by rules, " ..
            "@G" .. tostring(pkg.numFallbackStored or 0) .. "@W by lastStored/container fallback. Kept " ..
            "@G" .. tostring(pkg.numKeptInventory or 0) .. "@W in inventory.")

        -- Save inventory table to persist location updates from invmon
        if inv.items.save then
            inv.items.save()
        end
    else
        dbot.info("No items were moved. Kept " .. tostring(pkg.numKeptInventory or 0) .. " in inventory.")
    end

    local endTag = pkg.endTag
    inv.organize.runPkg = nil
    return inv.tags.stop(invTagsOrganize, endTag, DRL_RET_SUCCESS)
end

----------------------------------------------------------------------------------------------------
-- Helper: Find container by ID or relative name
----------------------------------------------------------------------------------------------------

function inv.organize.findContainer(containerRef)
    if containerRef == nil or containerRef == "" then
        return nil
    end

    -- Check if it's a numeric object ID
    local numericId = tonumber(containerRef)
    if numericId then
        -- CRITICAL: inv.items.table uses STRING keys, not numeric!
        local strId = tostring(numericId)
        local item = inv.items.table and inv.items.table[strId]
        if item then
            local itemType = inv.items.getStatField(strId, invStatFieldType) or ""
            if itemType == "Container" then
                return strId
            else
                dbot.warn("Object " .. containerRef .. " is not a container (type: " .. itemType .. ")")
                return nil
            end
        else
            dbot.warn("Object ID " .. containerRef .. " not found in inventory")
            return nil
        end
    end

    -- Try as relative name (add "1." prefix if no number)
    local relName = containerRef
    if not relName:match("^%d+%.") then
        relName = "1." .. relName
    end

    local idArray, retval = inv.items.search("type container rname " .. relName)

    if retval == DRL_RET_SUCCESS and idArray and #idArray == 1 then
        return tostring(idArray[1])
    elseif idArray and #idArray > 1 then
        dbot.warn("Multiple containers match '" .. containerRef .. "'. Use '1.bag', '2.bag', etc.")
        return nil
    end

    -- Try by name keyword
    idArray, retval = inv.items.search("type container name " .. containerRef)
    if retval == DRL_RET_SUCCESS and idArray and #idArray == 1 then
        return tostring(idArray[1])
    elseif idArray and #idArray > 1 then
        dbot.warn("Multiple containers match '" .. containerRef .. "'. Use object ID or relative name.")
        return nil
    end

    dbot.warn("No container found matching '" .. containerRef .. "'")
    return nil
end

----------------------------------------------------------------------------------------------------
-- Compatibility wrappers for legacy callers (inv.items.organize.*)
----------------------------------------------------------------------------------------------------

inv.items.organize.add = inv.items.organize.add or function(containerRef, queryString, endTag)
    return inv.organize.add(containerRef, queryString, endTag)
end

inv.items.organize.clear = inv.items.organize.clear or function(containerRef, endTag)
    return inv.organize.clear(containerRef, endTag)
end

inv.items.organize.display = inv.items.organize.display or function(endTag)
    return inv.organize.display(nil, endTag)
end

inv.items.organize.cleanup = inv.items.organize.cleanup or function(queryString, endTag)
    return inv.organize.run(queryString, endTag)
end

----------------------------------------------------------------------------------------------------
-- Module initialization
----------------------------------------------------------------------------------------------------

dbot.debug("inv.organize module loaded", "inv.organize")
