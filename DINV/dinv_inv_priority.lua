----------------------------------------------------------------------------------------------------
-- INV Priority Module
-- Stat priority/weight definitions for equipment sets
----------------------------------------------------------------------------------------------------

inv.priority       = {}
inv.priority.init  = {}
inv.priority.table = {}
inv.priority.stateName = "inv-priority.state"
inv.priority.lastImported = nil

-- Clipboard for copy/paste
inv.priority.clipboard = nil

-- Priority file directory
inv.priority.fileDir = getMudletHomeDir() .. "/DINV/priorities/"

function inv.priority.ensureDir()
    local lfs = require("lfs")
    local parentDir = getMudletHomeDir() .. "/DINV"
    lfs.mkdir(parentDir)
    lfs.mkdir(inv.priority.fileDir)
end

function inv.priority.getFilePath(priorityName)
    return inv.priority.fileDir .. priorityName .. ".txt"
end

----------------------------------------------------------------------------------------------------
-- Default Priority Template
----------------------------------------------------------------------------------------------------

inv.priority.template = {
    -- Basic stats
    [invStatFieldStr]  = { weight = 100, levels = {} },
    [invStatFieldInt]  = { weight = 100, levels = {} },
    [invStatFieldWis]  = { weight = 100, levels = {} },
    [invStatFieldDex]  = { weight = 100, levels = {} },
    [invStatFieldCon]  = { weight = 100, levels = {} },
    [invStatFieldLuck] = { weight = 100, levels = {} },
    
    -- Combat stats
    [invStatFieldHitroll] = { weight = 50, levels = {} },
    [invStatFieldDamroll] = { weight = 75, levels = {} },
    
    -- Resources
    [invStatFieldHp]    = { weight = 25, levels = {} },
    [invStatFieldMana]  = { weight = 25, levels = {} },
    [invStatFieldMoves] = { weight = 10, levels = {} },
    
    -- Resists
    [invStatFieldAllPhys]  = { weight = 10, levels = {} },
    [invStatFieldAllMagic] = { weight = 10, levels = {} },
    
    -- Effects
    effects = {
        sanctuary = { weight = 200 },
        haste = { weight = 150 },
        regeneration = { weight = 100 },
        dualwield = { weight = 100 },
        irongrip = { weight = 50 },
    },
    
    -- Weapon damage types
    allowedDamTypes = "all",
}

inv.priority.fieldDescriptions = {
    [invStatFieldStr] = "Strength",
    [invStatFieldInt] = "Intelligence",
    [invStatFieldWis] = "Wisdom",
    [invStatFieldDex] = "Dexterity",
    [invStatFieldCon] = "Constitution",
    [invStatFieldLuck] = "Luck",
    [invStatFieldHitroll] = "Hitroll",
    [invStatFieldDamroll] = "Damroll",
    [invStatFieldHp] = "Hit points",
    [invStatFieldMana] = "Mana",
    [invStatFieldMoves] = "Moves",
    [invStatFieldAllPhys] = "All physical resistance",
    [invStatFieldAllMagic] = "All magic resistance",
}

inv.priority.fieldOrder = {
    invStatFieldStr, invStatFieldInt, invStatFieldWis, invStatFieldDex, invStatFieldCon,
    invStatFieldLuck, invStatFieldHitroll, invStatFieldDamroll, invStatFieldHp,
    invStatFieldMana, invStatFieldMoves, invStatFieldAllPhys, invStatFieldAllMagic,
}

inv.priority.editor = {}

inv.priority.allFields = {
    { name = "str", desc = "Value of 1 point of the strength stat" },
    { name = "int", desc = "Value of 1 point of the intelligence stat" },
    { name = "wis", desc = "Value of 1 point of the wisdom stat" },
    { name = "dex", desc = "Value of 1 point of the dexterity stat" },
    { name = "con", desc = "Value of 1 point of the constitution stat" },
    { name = "luck", desc = "Value of 1 point of the luck stat" },
    { name = "dam", desc = "Value of 1 point of damroll" },
    { name = "hit", desc = "Value of 1 point of hitroll" },
    { name = "avedam", desc = "Value of 1 point of primary weapon ave damage" },
    { name = "offhandDam", desc = "Value of 1 point of offhand weapon ave damage" },
    { name = "hp", desc = "Value of 1 hit point" },
    { name = "mana", desc = "Value of 1 mana point" },
    { name = "moves", desc = "Value of 1 movement point" },
    { name = "sanctuary", desc = "Value placed on the sanctuary effect" },
    { name = "haste", desc = "Value placed on the haste effect" },
    { name = "flying", desc = "Value placed on the flying effect" },
    { name = "invis", desc = "Value placed on the invisible effect" },
    { name = "regeneration", desc = "Value placed on the regeneration effect" },
    { name = "detectinvis", desc = "Value placed on the detect invis effect" },
    { name = "detecthidden", desc = "Value placed on the detect hidden effect" },
    { name = "detectevil", desc = "Value placed on the detect evil effect" },
    { name = "detectgood", desc = "Value placed on the detect good effect" },
    { name = "dualwield", desc = "Value of an item's dual wield effect" },
    { name = "irongrip", desc = "Value of an item's irongrip effect" },
    { name = "shield", desc = "Value of a shield's damage reduction effect" },
    { name = "allmagic", desc = "Value of 1 point in each magical resist type" },
    { name = "allphys", desc = "Value of 1 point in each physical resist type" },
    { name = "maxint", desc = "Value of hitting a level's intelligence ceiling" },
    { name = "maxwis", desc = "Value of hitting a level's wisdom ceiling" },
    { name = "maxluck", desc = "Value of hitting a level's luck ceiling" },
    { name = "maxstr", desc = "Value of hitting a level's strength ceiling" },
    { name = "maxdex", desc = "Value of hitting a level's dexterity ceiling" },
    { name = "maxcon", desc = "Value of hitting a level's constitution ceiling" },
    { name = "~second", desc = "Set to 1 to disable offhand weapon slot" },
}

inv.priority.effectFields = {
    "sanctuary", "haste", "flying", "invis", "regeneration",
    "detectinvis", "detecthidden", "detectevil", "detectgood",
    "dualwield", "irongrip", "shield",
}

function inv.priority.isEffect(fieldName)
    for _, effect in ipairs(inv.priority.effectFields) do
        if fieldName == effect then
            return true
        end
    end
    return false
end

function inv.priority.getWeight(priorityTable, fieldName, level)
    if priorityTable == nil or fieldName == nil then
        return 0
    end

    level = tonumber(level) or 1
    local isEffect = inv.priority.isEffect(fieldName)
    local data = isEffect and (priorityTable.effects and priorityTable.effects[fieldName]) or priorityTable[fieldName]

    if data == nil then
        return 0
    end

    if type(data) == "number" then
        return data
    end

    if type(data) == "table" then
        if data.levels and #data.levels > 0 then
            for _, levelData in ipairs(data.levels) do
                if level >= (levelData.min or 0) and level <= (levelData.max or 999) then
                    return levelData.weight or data.weight or 0
                end
            end
        end
        return data.weight or 0
    end

    return 0
end

function inv.priority.getLevelRanges(priorityTable)
    local levelRanges = {}
    local rangeSet = {}

    for _, fieldInfo in ipairs(inv.priority.allFields) do
        local fieldName = fieldInfo.name
        local isEffect = inv.priority.isEffect(fieldName)
        local data = isEffect and (priorityTable.effects and priorityTable.effects[fieldName]) or priorityTable[fieldName]

        if data and type(data) == "table" and data.levels then
            for _, levelData in ipairs(data.levels) do
                local rangeKey = (levelData.min or 1) .. "-" .. (levelData.max or 291)
                if not rangeSet[rangeKey] then
                    rangeSet[rangeKey] = true
                    table.insert(levelRanges, { min = levelData.min or 1, max = levelData.max or 291 })
                end
            end
        end
    end

    if #levelRanges == 0 then
        levelRanges = { { min = 1, max = 291 } }
    end

    table.sort(levelRanges, function(a, b) return a.min < b.min end)
    return levelRanges
end

local function trimString(value)
    if value == nil then
        return ""
    end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

----------------------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------------------

function inv.priority.init.atInstall()
    return DRL_RET_SUCCESS
end

function inv.priority.init.atActive()
    local retval = inv.priority.load()
    if retval ~= DRL_RET_SUCCESS then
        dbot.debug("inv.priority.init.atActive: Using fresh priority table", "inv.priority")
    end
    return DRL_RET_SUCCESS
end

function inv.priority.fini(doSaveState)
    if doSaveState then
        inv.priority.save()
    end
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Save/Load/Reset
----------------------------------------------------------------------------------------------------

function inv.priority.save()
    if inv.priority.table == nil then
        return inv.priority.reset()
    end
    return dbot.storage.saveTable(dbot.backup.getCurrentDir() .. inv.priority.stateName,
                                   "inv.priority.table", inv.priority.table, true)
end

function inv.priority.load()
    return dbot.storage.loadTable(dbot.backup.getCurrentDir() .. inv.priority.stateName, inv.priority.reset)
end

function inv.priority.reset()
    inv.priority.table = {}
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Priority CRUD Operations
----------------------------------------------------------------------------------------------------

function inv.priority.create(priorityName, endTag)
    if priorityName == nil or priorityName == "" then
        dbot.warn("Usage: dinv priority create <name>")
        if endTag then return inv.tags.stop(invTagsPriority, endTag, DRL_RET_INVALID_PARAM) end
        return DRL_RET_INVALID_PARAM
    end
    if string.lower(tostring(priorityName)) == "any" then
        dbot.warn("Priority name 'any' is reserved for weapon cycling (dinv weapon next any).")
        if endTag then return inv.tags.stop(invTagsPriority, endTag, DRL_RET_INVALID_PARAM) end
        return DRL_RET_INVALID_PARAM
    end

    if inv.priority.table[priorityName] ~= nil then
        dbot.warn("Priority '" .. priorityName .. "' already exists")
        if endTag then return inv.tags.stop(invTagsPriority, endTag, DRL_RET_ALREADY_EXISTS) end
        return DRL_RET_ALREADY_EXISTS
    end

    -- Create new empty priority with default structure
    local newPriority = {}
    for _, fieldInfo in ipairs(inv.priority.allFields or {}) do
        newPriority[fieldInfo.name] = { weight = 0, levels = {} }
    end
    newPriority.effects = {}

    inv.priority.table[priorityName] = newPriority
    inv.priority.save()

    -- Export to file for editing
    local retval = inv.priority.exportToFile(priorityName)
    local filePath = inv.priority.getFilePath(priorityName)

    -- *** FIX: Show confirmation message like the original MUSHclient version ***
    dbot.info("Created priority \"@C" .. priorityName .. "@W\"")

    dbot.print("@Y================================================================================@W")
    dbot.print("@W  Priority '@G" .. priorityName .. "@W' created and exported to:@w")
    dbot.print("@C  " .. filePath .. "@w")
    dbot.print("@Y================================================================================@W")
    dbot.print("@W  1. Open the file above in your favorite text editor@w")
    dbot.print("@W  2. Modify the stat weights as desired@w")
    dbot.print("@W  3. Save the file@w")
    dbot.print("@W  4. Run: @Gdinv priority import " .. priorityName .. "@w")

    if endTag then return inv.tags.stop(invTagsPriority, endTag, DRL_RET_SUCCESS) end
    return DRL_RET_SUCCESS
end

function inv.priority.delete(priorityName, endTag)
    if priorityName == nil or priorityName == "" then
        dbot.warn("Usage: dinv priority delete <name>")
        if endTag then return inv.tags.stop(invTagsPriority, endTag, DRL_RET_INVALID_PARAM) end
        return DRL_RET_INVALID_PARAM
    end

    if inv.priority.table[priorityName] == nil then
        dbot.warn("Priority '" .. priorityName .. "' does not exist")
        if endTag then return inv.tags.stop(invTagsPriority, endTag, DRL_RET_MISSING_ENTRY) end
        return DRL_RET_MISSING_ENTRY
    end

    inv.priority.table[priorityName] = nil
    if inv.priority.getDefault() == priorityName then
        inv.priority.setDefault(nil, true)
    end
    inv.priority.save()

    dbot.info("Priority '" .. priorityName .. "' deleted")

    if endTag then return inv.tags.stop(invTagsPriority, endTag, DRL_RET_SUCCESS) end
    return DRL_RET_SUCCESS
end

function inv.priority.getDefault()
    if inv.config and inv.config.get then
        local name = inv.config.get("defaultPriorityName")
        if name and name ~= "" and inv.priority.exists(name) then
            return name
        end
    end
    return nil
end

function inv.priority.setDefault(priorityName, skipInfo)
    local normalized = tostring(priorityName or ""):match("^%s*(.-)%s*$")

    if normalized == "" or normalized == "none" then
        inv.config.set("defaultPriorityName", nil)
        if not skipInfo then
            dbot.info("Default priority cleared")
        end
        return DRL_RET_SUCCESS
    end

    if not inv.priority.exists(normalized) then
        dbot.warn("Priority '" .. normalized .. "' does not exist")
        return DRL_RET_MISSING_ENTRY
    end

    inv.config.set("defaultPriorityName", normalized)
    if not skipInfo then
        dbot.info("Default priority set to '" .. normalized .. "'")
    end
    return DRL_RET_SUCCESS
end

function inv.priority.clone(sourceName, destName, endTag)
    if sourceName == nil or destName == nil or sourceName == "" or destName == "" then
        dbot.warn("Usage: dinv priority clone <source> <destination>")
        if endTag then return inv.tags.stop(invTagsPriority, endTag, DRL_RET_INVALID_PARAM) end
        return DRL_RET_INVALID_PARAM
    end

    if inv.priority.table[sourceName] == nil then
        dbot.warn("Source priority '" .. sourceName .. "' does not exist")
        if endTag then return inv.tags.stop(invTagsPriority, endTag, DRL_RET_MISSING_ENTRY) end
        return DRL_RET_MISSING_ENTRY
    end

    if inv.priority.table[destName] ~= nil then
        dbot.warn("Destination priority '" .. destName .. "' already exists")
        if endTag then return inv.tags.stop(invTagsPriority, endTag, DRL_RET_ALREADY_EXISTS) end
        return DRL_RET_ALREADY_EXISTS
    end

    inv.priority.table[destName] = dbot.table.getCopy(inv.priority.table[sourceName])
    inv.priority.save()

    dbot.info("Priority '" .. sourceName .. "' cloned to '" .. destName .. "'")

    if endTag then return inv.tags.stop(invTagsPriority, endTag, DRL_RET_SUCCESS) end
    return DRL_RET_SUCCESS
end

function inv.priority.get(priorityName, level)
    if priorityName == nil or priorityName == "" then
        return nil
    end

    local priority = inv.priority.table[priorityName]
    if priority == nil then
        return nil
    end

    level = tonumber(level) or 1
    return priority
end

function inv.priority.exists(name)
    return inv.priority.table[name] ~= nil
end

----------------------------------------------------------------------------------------------------
-- Copy/Paste
----------------------------------------------------------------------------------------------------

function inv.priority.copy(name)
    if inv.priority.table[name] == nil then
        dbot.warn("Priority '" .. name .. "' does not exist")
        return DRL_RET_MISSING_ENTRY
    end
    
    inv.priority.clipboard = dbot.table.getCopy(inv.priority.table[name])
    dbot.info("Copied priority '" .. name .. "' to clipboard")
    return DRL_RET_SUCCESS
end

function inv.priority.paste(name)
    if inv.priority.clipboard == nil then
        dbot.warn("Clipboard is empty")
        return DRL_RET_MISSING_ENTRY
    end
    
    inv.priority.table[name] = dbot.table.getCopy(inv.priority.clipboard)
    dbot.info("Pasted clipboard to priority '" .. name .. "'")
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Display
----------------------------------------------------------------------------------------------------

function inv.priority.list(endTag)
    dbot.print("@WPriorities:@w")
    local count = 0

    local sorted = {}
    for name, _ in pairs(inv.priority.table) do
        table.insert(sorted, name)
    end
    table.sort(sorted)

    for _, name in ipairs(sorted) do
        dbot.print("  @G" .. name .. "@w")
        count = count + 1
    end

    if count == 0 then
        dbot.print("  @Y(none defined)@w")
    else
        dbot.print(string.format("\n@Y%d@W priority(s) defined.", count))
    end

    if endTag then
        return inv.tags.stop(invTagsPriority, endTag, DRL_RET_SUCCESS)
    end
    return DRL_RET_SUCCESS
end

function inv.priority.status(endTag)
    local total = 0
    for _ in pairs(inv.priority.table or {}) do
        total = total + 1
    end

    dbot.print("@WPriority status:@w")
    dbot.print("  @WDefined priorities: @Y" .. tostring(total) .. "@w")
    local defaultPriority = inv.priority.getDefault()
    if defaultPriority then
        dbot.print("  @WDefault priority: @G" .. defaultPriority .. "@w")
    else
        dbot.print("  @WDefault priority: @Y(none)@w")
    end

    if inv.priority.lastImported and inv.priority.exists(inv.priority.lastImported) then
        dbot.print("  @WLast imported: @G" .. inv.priority.lastImported .. "@w")
    else
        dbot.print("  @WLast imported: @Y(none this session)@w")
    end

    local weaponPriority = inv.weapon and inv.weapon.currentPriority or nil
    if weaponPriority and inv.priority.exists(weaponPriority) then
        local damTypes = (inv.weapon and inv.weapon.currentDamTypes) or "all"
        dbot.print("  @WActive weapon priority: @G" .. weaponPriority .. " @W(damtypes: @C" .. tostring(damTypes) .. "@W)@w")
    else
        dbot.print("  @WActive weapon priority: @Y(none)@w")
    end

    dbot.print("  @WNote: set/analyze/compare commands use the priority name you pass to each command.@w")

    if endTag then
        return inv.tags.stop(invTagsPriority, endTag, DRL_RET_SUCCESS)
    end
    return DRL_RET_SUCCESS
end

function inv.priority.display(priorityName, endTag)
    if priorityName == nil or priorityName == "" then
        dbot.warn("Usage: dinv priority display <name>")
        if endTag then
            return inv.tags.stop(invTagsPriority, endTag, DRL_RET_INVALID_PARAM)
        end
        return DRL_RET_INVALID_PARAM
    end

    local priority = inv.priority.table[priorityName]
    if priority == nil then
        dbot.warn("Priority '" .. priorityName .. "' does not exist")
        if endTag then
            return inv.tags.stop(invTagsPriority, endTag, DRL_RET_MISSING_ENTRY)
        end
        return DRL_RET_MISSING_ENTRY
    end

    local levelRanges = inv.priority.getLevelRanges(priority)

    local header1 = string.format("@C%12s", priorityName)
    for _, range in ipairs(levelRanges) do
        local rangeLabel = string.format("%d-%d", range.min, range.max)
        header1 = header1 .. string.format("@G%7s", rangeLabel)
    end

    dbot.print("@W")
    dbot.print(header1 .. "@w")
    dbot.print("@W")

    for _, fieldInfo in ipairs(inv.priority.allFields) do
        local fieldName = fieldInfo.name
        local hasValues = false
        local values = {}

        for _, range in ipairs(levelRanges) do
            local weight = inv.priority.getWeight(priority, fieldName, range.min)
            table.insert(values, weight)
            if weight ~= 0 then
                hasValues = true
            end
        end

        if hasValues then
            local line = string.format("@C%12s", fieldName)
            for _, weight in ipairs(values) do
                local color = "@g"
                if weight >= 1 then color = "@G" end
                if weight >= 10 then color = "@Y" end
                if weight >= 50 then color = "@R" end
                if weight == 0 then color = "@r" end
                line = line .. string.format("%s%7.2f", color, weight)
            end
            line = line .. "@W  : @c" .. fieldInfo.desc .. "@w"
            dbot.print(line)
        end
    end

    dbot.print("@W")
    if endTag then
        return inv.tags.stop(invTagsPriority, endTag, DRL_RET_SUCCESS)
    end
    return DRL_RET_SUCCESS
end

function inv.priority.compare(name1, name2)
    local p1 = inv.priority.table[name1]
    local p2 = inv.priority.table[name2]
    
    if p1 == nil then
        dbot.warn("Priority '" .. name1 .. "' does not exist")
        return DRL_RET_MISSING_ENTRY
    end
    
    if p2 == nil then
        dbot.warn("Priority '" .. name2 .. "' does not exist")
        return DRL_RET_MISSING_ENTRY
    end
    
    dbot.print("@WComparing: @G" .. name1 .. "@W vs @C" .. name2 .. "@w\n")
    
    local stats = {
        invStatFieldStr, invStatFieldInt, invStatFieldWis, invStatFieldDex,
        invStatFieldCon, invStatFieldLuck, invStatFieldHitroll, invStatFieldDamroll,
        invStatFieldHp, invStatFieldMana, invStatFieldMoves, invStatFieldAllPhys,
        invStatFieldAllMagic
    }

    dbot.print("@CStat Weights:@w")
    for _, stat in ipairs(stats) do
        local w1 = p1[stat] and p1[stat].weight or 0
        local w2 = p2[stat] and p2[stat].weight or 0
        if w1 ~= w2 then
            dbot.print(string.format("  @Y%-10s@W: @G%d@W vs @C%d@W", stat, w1, w2))
        end
    end

    dbot.print("\n@CEffect Weights:@w")
    local effects = {}
    for effect, _ in pairs(p1.effects or {}) do
        effects[effect] = true
    end
    for effect, _ in pairs(p2.effects or {}) do
        effects[effect] = true
    end
    for effect in pairs(effects) do
        local w1 = p1.effects and p1.effects[effect] and p1.effects[effect].weight or 0
        local w2 = p2.effects and p2.effects[effect] and p2.effects[effect].weight or 0
        if w1 ~= w2 then
            dbot.print(string.format("  @Y%-12s@W: @G%d@W vs @C%d@W", effect, w1, w2))
        end
    end
    
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Edit Functions
----------------------------------------------------------------------------------------------------

function inv.priority.tableToColumnarString(priorityTable, priorityName)
    if priorityTable == nil then
        return nil, DRL_RET_MISSING_ENTRY
    end

    local levelRanges = {}

    for _, statData in pairs(priorityTable) do
        if type(statData) == "table" and statData.levels then
            for _, levelData in ipairs(statData.levels) do
                local rangeKey = levelData.min .. "-" .. levelData.max
                levelRanges[rangeKey] = { min = levelData.min, max = levelData.max }
            end
        end
    end

    if priorityTable.effects then
        for _, effectData in pairs(priorityTable.effects) do
            if type(effectData) == "table" and effectData.levels then
                for _, levelData in ipairs(effectData.levels) do
                    local rangeKey = levelData.min .. "-" .. levelData.max
                    levelRanges[rangeKey] = { min = levelData.min, max = levelData.max }
                end
            end
        end
    end

    if next(levelRanges) == nil then
        levelRanges["1-291"] = { min = 1, max = 291 }
    end

    local sortedRanges = {}
    for _, rangeData in pairs(levelRanges) do
        table.insert(sortedRanges, rangeData)
    end
    table.sort(sortedRanges, function(a, b) return a.min < b.min end)

    local lines = {}
    local headerParts = { string.format("%-12s", "levels") }
    for _, range in ipairs(sortedRanges) do
        table.insert(headerParts, string.format("%-8s", range.min .. "-" .. range.max))
    end
    table.insert(lines, table.concat(headerParts, " "))

    local statFields = {
        "str", "int", "wis", "dex", "con", "luck",
        "dam", "hit",
        "avedam", "offhandDam",
        "hp", "mana", "moves",
        "sanctuary", "haste", "flying", "invis", "regeneration",
        "detectinvis", "detecthidden", "detectevil", "detectgood",
        "dualwield", "irongrip", "shield",
        "allmagic", "allphys",
        "maxint", "maxwis", "maxluck", "maxstr", "maxdex", "maxcon",
        "~second",
    }

    for _, statName in ipairs(statFields) do
        local statData = priorityTable[statName]
        local effectData = priorityTable.effects and priorityTable.effects[statName]

        local hasValues = false
        local valueParts = { string.format("%-12s", statName) }

        for _, range in ipairs(sortedRanges) do
            local weight = 0.00

            if statData and type(statData) == "table" then
                if statData.levels and #statData.levels > 0 then
                    for _, levelData in ipairs(statData.levels) do
                        if levelData.min == range.min and levelData.max == range.max then
                            weight = levelData.weight or statData.weight or 0
                            break
                        end
                    end
                    if weight == 0 then
                        weight = statData.weight or 0
                    end
                else
                    weight = statData.weight or 0
                end
            end

            if effectData and type(effectData) == "table" then
                if effectData.levels and #effectData.levels > 0 then
                    for _, levelData in ipairs(effectData.levels) do
                        if levelData.min == range.min and levelData.max == range.max then
                            weight = levelData.weight or effectData.weight or 0
                            break
                        end
                    end
                    if weight == 0 then
                        weight = effectData.weight or 0
                    end
                else
                    weight = effectData.weight or 0
                end
            end

            if weight ~= 0 then
                hasValues = true
            end

            table.insert(valueParts, string.format("%-8.2f", weight))
        end

        local commonStats = {
            str = true, int = true, wis = true, dex = true, con = true, luck = true,
            dam = true, hit = true,
            avedam = true, offhandDam = true,
            hp = true, mana = true, moves = true,
            allmagic = true, allphys = true,
        }
        if hasValues or commonStats[statName] then
            table.insert(lines, table.concat(valueParts, " "))
        end
    end

    return table.concat(lines, "\n"), DRL_RET_SUCCESS
end

function inv.priority.columnarStringToTable(content)
    local priorityTable = { effects = {} }
    local lines = {}

    for line in content:gmatch("[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" and not trimmed:match("^%-%-") and not trimmed:match("^#") then
            table.insert(lines, trimmed)
        end
    end

    if #lines == 0 then return nil, DRL_RET_INVALID_PARAM end

    local levelRanges = {}
    local headerParts = {}
    for part in lines[1]:gmatch("%S+") do table.insert(headerParts, part) end

    local startIdx = (headerParts[1] and headerParts[1]:lower() == "levels") and 2 or 1
    for i = startIdx, #headerParts do
        local min, max = headerParts[i]:match("(%d+)%-(%d+)")
        if min and max then
            table.insert(levelRanges, { min = tonumber(min), max = tonumber(max) })
        end
    end

    if #levelRanges == 0 then levelRanges = { { min = 1, max = 291 } } end

    for lineIdx = 2, #lines do
        local parts = {}
        for part in lines[lineIdx]:gmatch("%S+") do table.insert(parts, part) end

        if #parts >= 2 then
            local fieldName = parts[1]
            if fieldName:lower() == "offhanddam" then fieldName = "offhandDam" end

            local isEffect = inv.priority.isEffect(fieldName)
            local levelWeights = {}

            for i = 2, #parts do
                local weight = tonumber(parts[i])
                if weight and levelRanges[i - 1] then
                    table.insert(levelWeights, {
                        min = levelRanges[i - 1].min,
                        max = levelRanges[i - 1].max,
                        weight = weight
                    })
                end
            end

            local defaultWeight = levelWeights[1] and levelWeights[1].weight or 0

            if isEffect then
                priorityTable.effects[fieldName] = { weight = defaultWeight, levels = levelWeights }
            else
                priorityTable[fieldName] = { weight = defaultWeight, levels = levelWeights }
            end
        end
    end

    return priorityTable, DRL_RET_SUCCESS
end

function inv.priority.exportToFile(priorityName)
    if priorityName == nil or inv.priority.table[priorityName] == nil then
        return DRL_RET_INVALID_PARAM
    end

    inv.priority.ensureDir()
    local priority = inv.priority.table[priorityName]
    local levelRanges = inv.priority.getLevelRanges(priority)
    local filePath = inv.priority.getFilePath(priorityName)

    local file = io.open(filePath, "w")
    if file == nil then
        dbot.warn("Failed to open file: " .. filePath)
        return DRL_RET_INTERNAL_ERROR
    end

    file:write("-- DINV Priority: " .. priorityName .. "\n")
    file:write("-- After editing, run: dinv priority import " .. priorityName .. "\n\n")

    local header = string.format("%-12s", "levels")
    for _, range in ipairs(levelRanges) do
        header = header .. string.format(" %-7s", range.min .. "-" .. range.max)
    end
    file:write(header .. "\n")

    for _, fieldInfo in ipairs(inv.priority.allFields) do
        local line = string.format("%-12s", fieldInfo.name)
        for _, range in ipairs(levelRanges) do
            local weight = inv.priority.getWeight(priority, fieldInfo.name, range.min)
            line = line .. string.format(" %-7.2f", weight)
        end
        file:write(line .. "\n")
    end

    file:close()
    dbot.info("Priority exported to: " .. filePath)
    return DRL_RET_SUCCESS
end

function inv.priority.importFromFile(priorityName, endTag)
    if priorityName == nil or priorityName == "" then
        dbot.warn("Usage: dinv priority import <name>")
        if endTag then return inv.tags.stop(invTagsPriority, endTag, DRL_RET_INVALID_PARAM) end
        return DRL_RET_INVALID_PARAM
    end

    local filePath = inv.priority.getFilePath(priorityName)
    local file = io.open(filePath, "r")
    if file == nil then
        dbot.warn("File not found: " .. filePath)
        dbot.info("Make sure the priority file exists at the path above.")
        dbot.info("You can create it with: @Gdinv priority create " .. priorityName .. "@W")
        if endTag then return inv.tags.stop(invTagsPriority, endTag, DRL_RET_MISSING_ENTRY) end
        return DRL_RET_MISSING_ENTRY
    end

    local content = file:read("*all")
    file:close()

    local priorityEntry, retval = inv.priority.columnarStringToTable(content)
    if retval ~= DRL_RET_SUCCESS then
        dbot.warn("Failed to parse priority file: " .. filePath)
        dbot.info("Check the file format - each line should be: statname  value1  value2 ...")
        if endTag then return inv.tags.stop(invTagsPriority, endTag, retval) end
        return retval
    end

    -- Determine if this is a new priority or an update
    local operation = "Updated"
    if inv.priority.table[priorityName] == nil then
        operation = "Created"
    end

    inv.priority.table[priorityName] = priorityEntry
    inv.priority.lastImported = priorityName
    inv.priority.save()

    -- Invalidate any equipment set analysis based on this priority
    if inv.set and inv.set.table then
        inv.set.table[priorityName] = nil
        if inv.set.save then
            inv.set.save()
        end
    end

    -- *** FIX: Show complete success message ***
    dbot.print("@Y================================================================================@W")
    dbot.print("@G  SUCCESS: @WPriority '@C" .. priorityName .. "@W' imported!@w")
    dbot.print("@Y================================================================================@W")
    dbot.print("@W  " .. operation .. " from: @C" .. filePath .. "@w")
    dbot.print("@W")
    dbot.print("@W  Next steps:@w")
    dbot.print("@W    @Gdinv priority display " .. priorityName .. "@W  - View the priority@w")
    dbot.print("@W    @Gdinv analyze create " .. priorityName .. "@W   - Generate optimal sets@w")
    dbot.print("@W")

    -- Also show the standard info message for scripting/automation
    dbot.info(operation .. " priority \"@C" .. priorityName .. "@W\" from file")

    if endTag then return inv.tags.stop(invTagsPriority, endTag, DRL_RET_SUCCESS) end
    return DRL_RET_SUCCESS
end

function inv.priority.tableToString(priorityTable, doDisplayUnused, doDisplayColors, doDisplayDesc)
    if not priorityTable then
        return "", DRL_RET_INVALID_PARAM
    end

    local lines = {}
    table.insert(lines, "# DINV priority format v1")
    table.insert(lines, "# Lines are formatted as key=value")
    table.insert(lines, "allowedDamTypes=" .. tostring(priorityTable.allowedDamTypes or "all"))
    table.insert(lines, "")

    for _, stat in ipairs(inv.priority.fieldOrder) do
        local entry = priorityTable[stat]
        local weight = entry and entry.weight or 0
        if doDisplayUnused or weight ~= 0 then
            local desc = ""
            if doDisplayDesc and inv.priority.fieldDescriptions[stat] then
                desc = " # " .. inv.priority.fieldDescriptions[stat]
            end
            table.insert(lines, string.format("%s=%d%s", stat, weight, desc))
        end
    end

    local effects = priorityTable.effects or {}
    local effectNames = {}
    for effectName in pairs(effects) do
        table.insert(effectNames, effectName)
    end
    table.sort(effectNames)
    if #effectNames > 0 then
        table.insert(lines, "")
        table.insert(lines, "# effects.<name>=weight")
        for _, effectName in ipairs(effectNames) do
            local weight = effects[effectName] and effects[effectName].weight or 0
            if doDisplayUnused or weight ~= 0 then
                table.insert(lines, string.format("effect.%s=%d", effectName, weight))
            end
        end
    end

    return table.concat(lines, "\n"), DRL_RET_SUCCESS
end

function inv.priority.stringToTable(priorityString, baseTable, keepMissing)
    if not priorityString or priorityString == "" then
        return nil, DRL_RET_INVALID_PARAM
    end

    local priorityEntry = baseTable and dbot.table.getCopy(baseTable)
        or dbot.table.getCopy(inv.priority.template)
    local seenStats = {}
    local seenEffects = {}

    for line in priorityString:gmatch("[^\r\n]+") do
        local trimmed = trimString(line)
        if trimmed ~= "" and not trimmed:match("^#") then
            local key, value = trimmed:match("^(.-)%s*=%s*(.+)$")
            if key and value then
                if key == "allowedDamTypes" then
                    priorityEntry.allowedDamTypes = value
                elseif key:sub(1, 7) == "effect." then
                    local effectName = key:sub(8)
                    priorityEntry.effects = priorityEntry.effects or {}
                    priorityEntry.effects[effectName] = priorityEntry.effects[effectName] or {}
                    priorityEntry.effects[effectName].weight = tonumber(value) or 0
                    seenEffects[effectName] = true
                else
                    priorityEntry[key] = priorityEntry[key] or { weight = 0, levels = {} }
                    priorityEntry[key].weight = tonumber(value) or 0
                    seenStats[key] = true
                end
            end
        end
    end

    if not keepMissing then
        for _, stat in ipairs(inv.priority.fieldOrder) do
            if priorityEntry[stat] and not seenStats[stat] then
                priorityEntry[stat].weight = 0
            end
        end
        if priorityEntry.effects then
            for effectName, effectData in pairs(priorityEntry.effects) do
                if effectData and not seenEffects[effectName] then
                    effectData.weight = 0
                end
            end
        end
    end

    return priorityEntry, DRL_RET_SUCCESS
end

function inv.priority.update(priorityName, priorityString, isQuiet)
    if priorityName == nil or priorityName == "" then
        dbot.warn("inv.priority.update: Missing priority name parameter")
        return DRL_RET_INVALID_PARAM
    end

    if priorityString == nil or priorityString == "" then
        dbot.warn("inv.priority.update: Missing priority string parameter")
        return DRL_RET_INVALID_PARAM
    end

    local existing = inv.priority.table[priorityName]
    local priorityEntry, retval = inv.priority.stringToTable(priorityString, existing, true)
    if retval ~= DRL_RET_SUCCESS then
        dbot.debug("inv.priority.update: Failed to convert priority string: " .. dbot.retval.getString(retval), "inv.priority")
        return retval
    end

    inv.priority.table[priorityName] = priorityEntry
    if not isQuiet then
        dbot.info("Updated priority '" .. priorityName .. "'")
    end
    inv.priority.save()

    if inv.set and inv.set.table then
        inv.set.table[priorityName] = nil
        if inv.set.save then
            inv.set.save()
        end
    end

    return DRL_RET_SUCCESS
end

function inv.priority.edit(priorityName, useAllFields, isQuiet, endTag)
    if priorityName == nil or priorityName == "" then
        dbot.warn("Usage: dinv priority edit <name>")
        if endTag then return inv.tags.stop(invTagsPriority, endTag, DRL_RET_INVALID_PARAM) end
        return DRL_RET_INVALID_PARAM
    end

    if inv.priority.table[priorityName] == nil then
        dbot.warn("Priority '" .. priorityName .. "' does not exist")
        if endTag then return inv.tags.stop(invTagsPriority, endTag, DRL_RET_MISSING_ENTRY) end
        return DRL_RET_MISSING_ENTRY
    end

    inv.priority.exportToFile(priorityName)
    local filePath = inv.priority.getFilePath(priorityName)

    dbot.print("@Y================================================================================@W")
    dbot.print("@W  Priority '@G" .. priorityName .. "@W' exported to:@w")
    dbot.print("@C  " .. filePath .. "@w")
    dbot.print("@Y================================================================================@W")
    dbot.print("@W  1. Open the file above in your favorite text editor@w")
    dbot.print("@W  2. Save the file@w")
    dbot.print("@W  3. Run: @Gdinv priority import " .. priorityName .. "@w")

    if endTag then return inv.tags.stop(invTagsPriority, endTag, DRL_RET_SUCCESS) end
    return DRL_RET_SUCCESS
end

function inv.priority.setWeight(name, stat, weight)
    local priority = inv.priority.table[name]
    if priority == nil then
        dbot.warn("Priority '" .. name .. "' does not exist")
        return DRL_RET_MISSING_ENTRY
    end
    
    if priority[stat] == nil then
        priority[stat] = { weight = 0, levels = {} }
    end
    
    priority[stat].weight = tonumber(weight) or 0
    dbot.info("Set " .. stat .. " weight to " .. priority[stat].weight .. " in priority '" .. name .. "'")
    return DRL_RET_SUCCESS
end

function inv.priority.setEffectWeight(name, effect, weight)
    local priority = inv.priority.table[name]
    if priority == nil then
        dbot.warn("Priority '" .. name .. "' does not exist")
        return DRL_RET_MISSING_ENTRY
    end
    
    if priority.effects == nil then
        priority.effects = {}
    end
    
    if priority.effects[effect] == nil then
        priority.effects[effect] = {}
    end
    
    priority.effects[effect].weight = tonumber(weight) or 0
    dbot.info("Set " .. effect .. " weight to " .. priority.effects[effect].weight .. " in priority '" .. name .. "'")
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- End of inv priority module
----------------------------------------------------------------------------------------------------

inv.priority.ensureDir()
dbot.debug("inv.priority module loaded", "inv.priority")
