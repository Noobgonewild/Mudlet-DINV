----------------------------------------------------------------------------------------------------
-- INV Unused Module
-- Find and manage unused inventory items
-- 
-- Original Author: Gizmmo
-- Ported to Mudlet from MUSHclient
----------------------------------------------------------------------------------------------------

-- Defensive initialization
inv = inv or {}
inv.items = inv.items or {}
inv.items.table = inv.items.table or {}
inv.set = inv.set or {}
inv.set.table = inv.set.table or {}
inv.tags = inv.tags or {}
inv.cli = inv.cli or {}

-- Module initialization
inv.unused = inv.unused or {}
inv.unused.init = inv.unused.init or {}
inv.cli.unused = inv.cli.unused or {}

-- Store the list of unused item IDs from the last "dinv unused" report
inv.unused.lastUnusedIds = {}

----------------------------------------------------------------------------------------------------
-- Module lifecycle hooks
----------------------------------------------------------------------------------------------------

function inv.unused.init.atInstall()
    return DRL_RET_SUCCESS
end

function inv.unused.init.atActive()
    return DRL_RET_SUCCESS
end

function inv.unused.fini(doSaveState)
    return DRL_RET_SUCCESS
end

function inv.unused.reset()
    inv.unused.lastUnusedIds = {}
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Core logic to find unused items
-- @return (table) An array of object IDs for unused items, or nil
-- @return (number) A DRL return code
----------------------------------------------------------------------------------------------------
function inv.unused.find()
    -- Check if items table exists and has data
    if not inv.items.table or next(inv.items.table) == nil then
        dbot.warn("Cannot find unused items: inventory table is empty or not built.")
        dbot.info("Run \"@Gdinv build confirm@W\" first to build your inventory.")
        return nil, DRL_RET_UNINITIALIZED
    end

    -- Step 1: Get a list of ALL potential equipment IDs from the main inventory table
    local allItemIds = {}
    for objId, itemEntry in pairs(inv.items.table) do
        -- Only consider items that are explicitly wearable gear
        local itemType = ""
        local wearable = ""
        
        if inv.items.getStatField then
            itemType = inv.items.getStatField(objId, "type") or ""
            wearable = inv.items.getStatField(objId, "wearable") or ""
        elseif itemEntry.stats then
            itemType = itemEntry.stats.type or itemEntry.stats[invStatFieldType] or ""
            wearable = itemEntry.stats.wearable or itemEntry.stats[invStatFieldWearable] or ""
        end
        
        -- Only include items that have a wearable location
        if wearable ~= "" then
            -- Further filter to only include types that are considered equipment
            if itemType == "Armor" or itemType == "Weapon" or itemType == "Light" or itemType == "Treasure" then
                table.insert(allItemIds, objId)
            end
        end
    end
    
    if #allItemIds == 0 then
        dbot.info("No wearable equipment found in your inventory.")
        return {}, DRL_RET_SUCCESS
    end

    -- Step 2: Build a set of all USED item IDs from all analyses (all priorities)
    local usedItemIds = {}
    local hasAnalysisData = false

    local function markUsedItem(itemInfo)
        local itemId = nil

        -- Handle different data formats
        if type(itemInfo) == "table" and itemInfo.id then
            itemId = itemInfo.id
        elseif type(itemInfo) == "number" then
            itemId = itemInfo
        elseif type(itemInfo) == "string" then
            itemId = tonumber(itemInfo)
        end

        if itemId then
            -- Use both numeric and string keys for safe cross-module comparisons
            usedItemIds[itemId] = true
            usedItemIds[tostring(itemId)] = true
        end
    end

    local function collectUsedFromSetLevels(levels)
        if not levels then
            return false
        end

        local found = false
        for _, equipmentSet in pairs(levels) do
            if equipmentSet then
                -- Handle both equipment sub-table format and direct format
                local equipment = equipmentSet.equipment or equipmentSet
                if equipment and next(equipment) then
                    found = true
                    for _, itemInfo in pairs(equipment) do
                        markUsedItem(itemInfo)
                    end
                end
            end
        end

        return found
    end

    -- Prefer analyze data, because that is the canonical per-priority analysis store.
    if inv.analyze and inv.analyze.table then
        for _, analysisEntry in pairs(inv.analyze.table) do
            if collectUsedFromSetLevels(analysisEntry.levels) then
                hasAnalysisData = true
            end
        end
    end

    -- Fallback to set data when analysis reports are not available.
    if not hasAnalysisData and inv.set and inv.set.table then
        for _, levels in pairs(inv.set.table) do
            if collectUsedFromSetLevels(levels) then
                hasAnalysisData = true
            end
        end
    end

    if not hasAnalysisData then
        dbot.warn("Cannot find unused items. No analysis data found.")
        dbot.info("Please run \"@Gdinv analyze create <priority_name>@W\" for one or more priorities first.")
        return nil, DRL_RET_MISSING_ENTRY
    end
    
    -- Step 3: Find the difference: all potential equipment minus used equipment
    local unusedItemIds = {}
    for _, objId in ipairs(allItemIds) do
        if not usedItemIds[objId] and not usedItemIds[tostring(objId)] then
            table.insert(unusedItemIds, objId)
        end
    end
    
    return unusedItemIds, DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Displays a report of all unused items
----------------------------------------------------------------------------------------------------
function inv.unused.report()
    local unusedIds, retval = inv.unused.find()
    
    if retval ~= DRL_RET_SUCCESS then
        return retval -- Error message was already printed in find()
    end
    
    -- Cache the result for the 'store' command
    inv.unused.lastUnusedIds = unusedIds
    
    if #unusedIds == 0 then
        dbot.info("No unused equipment found based on your current analysis reports!")
        return DRL_RET_SUCCESS
    end
    
    -- Sort and display the results using the main plugin's display function
    local sortCriteria = {
        { field = invStatFieldLevel, isAscending = true },
        { field = invStatFieldType, isAscending = true },
        { field = invStatFieldName, isAscending = true }
    }
    inv.items.sort(unusedIds, sortCriteria)
    
    dbot.print("\n@WThe following items were not found in any of your 'dinv analyze' reports:@w")
    inv.items.displayLastType = "" -- Force a header print
    
    for _, objId in ipairs(unusedIds) do
        inv.items.displayItem(objId, "basic")
    end
    
    dbot.print(string.format("\n@Y%d@W unused item(s) found.", #unusedIds))
    dbot.info("To store these items, use \"@Gdinv unused store <container>@W\".")
    
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Stores all unused items in a specified container
-- @param containerName (string) The relative name of the container (e.g., "3.bag")
----------------------------------------------------------------------------------------------------
function inv.unused.store(containerName)
    if #inv.unused.lastUnusedIds == 0 then
        dbot.info("No unused items to store. Run \"@Gdinv unused@W\" first to generate the list.")
        return DRL_RET_MISSING_ENTRY
    end
    
    dbot.info(string.format("Attempting to store @Y%d@W unused items in '@C%s@W'...", 
              #inv.unused.lastUnusedIds, containerName))
    
    -- Step 1: Build the query string from the list of unused IDs
    -- The query will look like: "id 12345 || id 67890 || id 24680"
    local queryParts = {}
    for _, objId in ipairs(inv.unused.lastUnusedIds) do
        table.insert(queryParts, "id " .. objId)
    end
    local queryString = table.concat(queryParts, " || ")
    
    -- Step 2: Use the existing 'dinv put' functionality
    inv.items.put(containerName, queryString, nil)
    
    -- Clear the cache so the user must run 'dinv unused' again before storing
    inv.unused.lastUnusedIds = {}
    
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- CLI entry point for 'dinv unused' commands
----------------------------------------------------------------------------------------------------
function inv.cli.unused.fn(name, line, wildcards)
    local command = wildcards[1] or ""
    local param = wildcards[2] or ""
    local endTag = inv.tags.new(line)
    
    if command == "" then
        -- This is the 'dinv unused' report command
        inv.unused.report()
    elseif command == "store" then
        if param == "" then
            dbot.warn("Missing container name for 'store' command.")
            inv.cli.unused.usage()
            return inv.tags.stop(invTagsUnused, endTag, DRL_RET_INVALID_PARAM)
        end
        inv.unused.store(param)
    else
        dbot.warn("Invalid 'unused' command.")
        inv.cli.unused.usage()
        return inv.tags.stop(invTagsUnused, endTag, DRL_RET_INVALID_PARAM)
    end
    
    return inv.tags.stop(invTagsUnused, endTag, DRL_RET_SUCCESS)
end

----------------------------------------------------------------------------------------------------
-- Usage and Examples for the help system
----------------------------------------------------------------------------------------------------
function inv.cli.unused.usage()
    dbot.print(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " unused", "Report equipment not used in any analysis"))
    dbot.print(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " unused store @G<container>", "Store all unused equipment"))
end

function inv.cli.unused.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.unused.usage()
    
    dbot.print([[@W
The 'unused' command helps you identify and manage equipment that is not part of any of your optimal sets.

@CIMPORTANT@W: This command's accuracy depends entirely on your 'dinv analyze' reports. An item is considered "unused" if it does not appear in ANY of the equipment sets generated by 'dinv analyze create' for ANY priority. If you haven't analyzed a 'mage' priority, for example, your mage gear will likely be listed as unused.

@Wdinv unused@w
  Analyzes your inventory and produces a colored table of all equipment (Armor, Weapons, Lights, and wearable Treasure) that is not used in any of your generated equipment sets. This is a great way to find items you can potentially sell, trade, or store away. The list of unused items is cached temporarily.

@Wdinv unused store <container>@w
  Takes the cached list of items generated by the last 'dinv unused' command and moves all of them into the specified container. This is an excellent command for quickly cleaning up your main inventory.

Examples:
  1) Generate a report of all your unused equipment.
     "@Gdinv unused@w"

  2) After reviewing the list, move all those unused items into your 4th bag.
     "@Gdinv unused store 4.bag@w"
  
  3) After reviewing the list, move all those unused items into your bag with the id 1919691768.
     "@Gdinv unused store 1919691768@w"
]])
end

----------------------------------------------------------------------------------------------------
-- End of unused module
----------------------------------------------------------------------------------------------------

dbot.debug("inv.unused module loaded", "inv.unused")
