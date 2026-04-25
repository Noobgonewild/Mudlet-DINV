----------------------------------------------------------------------------------------------------
-- DINV RID Module
-- Report identify data for a single item
-- Parses identify output character by character as specified
----------------------------------------------------------------------------------------------------

-- RID command/module disabled per user request.
-- Keep code in repository, but do not execute/load it.
if false then

inv = inv or {}
inv.rid = inv.rid or {}
inv.cli = inv.cli or {}

inv.rid.ids = inv.rid.ids or {}
inv.rid.active = inv.rid.active or false
inv.rid.fence = "DINV rid fence"
inv.rid.item = inv.rid.item or nil
inv.rid.target = inv.rid.target or nil
inv.rid.channel = inv.rid.channel or { type = "default", name = nil }
inv.rid.lineCount = inv.rid.lineCount or 0
inv.rid.lastProperty = inv.rid.lastProperty or nil  -- Track last property for continuation lines
inv.rid.inEnchants = inv.rid.inEnchants or false    -- Track if we're in enchants section
inv.rid.suppressIdentifyOutput = true

----------------------------------------------------------------------------------------------------
-- Helper Functions
----------------------------------------------------------------------------------------------------

local function trim(str)
    if not str then return "" end
    return str:match("^%s*(.-)%s*$") or ""
end

----------------------------------------------------------------------------------------------------
-- Extract a number from a string starting at position
-- Returns: number value, end position (or nil if no number found)
----------------------------------------------------------------------------------------------------

local function extractNumber(str, startPos)
    startPos = startPos or 1
    local sign = 1
    local numStr = ""
    local i = startPos
    local foundDigit = false
    
    -- Skip leading spaces
    while i <= #str do
        local char = str:sub(i, i)
        if char ~= " " then break end
        i = i + 1
    end
    
    -- Check for sign
    if i <= #str then
        local char = str:sub(i, i)
        if char == "+" then
            i = i + 1
        elseif char == "-" then
            sign = -1
            i = i + 1
        end
    end
    
    -- Collect digits (and commas for numbers like 23,300)
    while i <= #str do
        local char = str:sub(i, i)
        if char >= "0" and char <= "9" then
            numStr = numStr .. char
            foundDigit = true
            i = i + 1
        elseif char == "," and foundDigit then
            -- Skip commas in numbers like 23,300
            i = i + 1
        else
            break
        end
    end
    
    if foundDigit then
        local value = tonumber(numStr)
        if value then
            return value * sign, i
        end
    end
    
    return nil, startPos
end

----------------------------------------------------------------------------------------------------
-- Extract text value (non-numeric) until we hit another property or end
-- Used for things like flags, keywords, material, etc.
----------------------------------------------------------------------------------------------------

local function extractTextValue(str, startPos)
    startPos = startPos or 1
    local value = ""
    local i = startPos
    
    -- Skip leading spaces and colon
    while i <= #str do
        local char = str:sub(i, i)
        if char ~= " " and char ~= ":" then break end
        i = i + 1
    end
    
    -- Collect until we hit | or end
    while i <= #str do
        local char = str:sub(i, i)
        if char == "|" then break end
        value = value .. char
        i = i + 1
    end
    
    return trim(value), i
end

----------------------------------------------------------------------------------------------------
-- Parse a single property:value pair from the line
-- Returns: propertyName, value, remainingString (or nil if no property found)
----------------------------------------------------------------------------------------------------

local function parseNextProperty(line)
    -- Find the first colon
    local colonPos = line:find(":")
    if not colonPos then
        return nil, nil, nil
    end
    
    -- Extract property name: everything before the colon
    local beforeColon = line:sub(1, colonPos - 1)
    -- Remove leading | and spaces
    local propName = beforeColon:gsub("^[|%s]+", "")
    propName = trim(propName)
    
    -- If property name is empty, this is a continuation line
    if propName == "" then
        return "", nil, line:sub(colonPos + 1)
    end
    
    -- Now parse the value after the colon
    local afterColon = line:sub(colonPos + 1)
    
    -- Check if this is a known numeric property
    local numericProps = {
        ["hit roll"] = true, ["damage roll"] = true,
        ["strength"] = true, ["intelligence"] = true, ["wisdom"] = true,
        ["dexterity"] = true, ["constitution"] = true, ["luck"] = true,
        ["hit points"] = true, ["mana"] = true, ["moves"] = true,
        ["level"] = true, ["worth"] = true, ["weight"] = true,
        ["score"] = true, ["capacity"] = true, ["holding"] = true,
        ["average dam"] = true,
        ["all physical"] = true, ["all magic"] = true,
        ["acid"] = true, ["cold"] = true, ["energy"] = true, ["holy"] = true,
        ["electric"] = true, ["negative"] = true, ["shadow"] = true, ["magic"] = true,
        ["air"] = true, ["earth"] = true, ["fire"] = true, ["light"] = true,
        ["mental"] = true, ["sonic"] = true, ["water"] = true,
        ["poison"] = true, ["disease"] = true,
        ["slash"] = true, ["pierce"] = true, ["bash"] = true,
        ["items inside"] = true, ["tot weight"] = true, ["item burden"] = true,
        ["heaviest item"] = true, ["weight reduction"] = true,
    }
    
    local propLower = propName:lower()
    
    if numericProps[propLower] then
        -- Extract numeric value
        local value, endPos = extractNumber(afterColon, 1)
        if value then
            local remaining = afterColon:sub(endPos)
            return propName, value, remaining
        end
    end
    
    -- For text values, extract until next property or |
    -- Look for the next colon that might indicate another property
    local nextColonPos = afterColon:find(":")
    if nextColonPos then
        -- There's another property on this line
        -- Find where the value ends (look backwards from the colon for property name)
        local beforeNextColon = afterColon:sub(1, nextColonPos - 1)
        -- Find the last word before the colon - that's the next property name
        local lastWordStart = beforeNextColon:match(".*%s+()%S+%s*$")
        if lastWordStart then
            local value = trim(afterColon:sub(1, lastWordStart - 1))
            local remaining = afterColon:sub(lastWordStart)
            return propName, value, remaining
        end
    end
    
    -- No more properties on this line, take everything until |
    local value = afterColon:match("^(.-)%s*|") or afterColon:match("^(.-)%s*$")
    value = trim(value or "")
    
    return propName, value, nil
end

----------------------------------------------------------------------------------------------------
-- Known property names for better matching
----------------------------------------------------------------------------------------------------

local knownProperties = {
    -- Basic
    "Keywords", "Name", "Id", "Type", "Level", "Worth", "Weight",
    "Wearable", "Score", "Material", "Duration", "Flags", "Notes",
    "Found at", "Owned By", "Clan Item",
    -- Stats (these appear in "Stat Mods" section)
    "Stat Mods", "Hit roll", "Damage roll", "Strength", "Intelligence",
    "Wisdom", "Dexterity", "Constitution", "Luck", "Hit points", "Mana", "Moves",
    -- Weapon
    "Weapon Type", "Average Dam", "Inflicts", "Damage Type", "Specials",
    -- Container
    "Capacity", "Holding", "Items Inside", "Tot Weight", "Item Burden",
    -- Portal
    "Leads to",
    -- Light
    "Light",
    -- Enchants
    "Enchants", "Illuminate", "Resonate", "Solidify",
}

----------------------------------------------------------------------------------------------------
-- Parse a line for all property:value pairs
----------------------------------------------------------------------------------------------------

local function parseLine(line, data, state)
    local parseState = state or inv.rid
    local clean = dbot.stripColors(line)
    
    -- Must start with |
    if not clean:match("^%s*|") then
        return
    end
    
    -- Check if we're entering enchants section
    if clean:lower():find("enchants:") then
        parseState.inEnchants = true
        dbot.debug("[RID] Entering enchants section", "rid")
        return
    end
    
    -- Handle enchant lines (Illuminate, Resonate, Solidify)
    if parseState.inEnchants then
        local cleanLower = clean:lower()
        
        if cleanLower:find("illuminate") then
            if cleanLower:find("%(removable by enchanter%)") then
                data.enchants = data.enchants or {}
                data.enchants.illuminate = "enchanter"
                dbot.debug("[RID] Illuminate: removable by enchanter", "rid")
            elseif cleanLower:find("%(removable with tp only%)") then
                data.enchants = data.enchants or {}
                data.enchants.illuminate = "tp"
                dbot.debug("[RID] Illuminate: removable with TP only", "rid")
            end
        end
        
        if cleanLower:find("resonate") then
            if cleanLower:find("%(removable by enchanter%)") then
                data.enchants = data.enchants or {}
                data.enchants.resonate = "enchanter"
                dbot.debug("[RID] Resonate: removable by enchanter", "rid")
            elseif cleanLower:find("%(removable with tp only%)") then
                data.enchants = data.enchants or {}
                data.enchants.resonate = "tp"
                dbot.debug("[RID] Resonate: removable with TP only", "rid")
            end
        end
        
        if cleanLower:find("solidify") then
            if cleanLower:find("%(removable by enchanter%)") then
                data.enchants = data.enchants or {}
                data.enchants.solidify = "enchanter"
                dbot.debug("[RID] Solidify: removable by enchanter", "rid")
            elseif cleanLower:find("%(removable with tp only%)") then
                data.enchants = data.enchants or {}
                data.enchants.solidify = "tp"
                dbot.debug("[RID] Solidify: removable with TP only", "rid")
            end
        end
        
        -- Don't process enchant values further
        return
    end
    
    -- Check if this is a continuation line (starts with | then spaces then :)
    if clean:match("^|%s*:") then
        -- Continuation of previous property
        local contValue = clean:match("^|%s*:%s*(.-)%s*|")
        if contValue and parseState.lastProperty then
            local prop = parseState.lastProperty
            dbot.debug("[RID] Continuation for " .. prop .. ": " .. contValue, "rid")
            
            -- Add to the property's values
            if data[prop] then
                if type(data[prop]) == "table" then
                    -- Split by comma and add each value
                    for val in contValue:gmatch("([^,]+)") do
                        val = trim(val)
                        if val ~= "" then
                            table.insert(data[prop], val)
                        end
                    end
                else
                    -- Convert to table and add
                    local oldVal = data[prop]
                    data[prop] = {}
                    for val in oldVal:gmatch("([^,]+)") do
                        val = trim(val)
                        if val ~= "" then
                            table.insert(data[prop], val)
                        end
                    end
                    for val in contValue:gmatch("([^,]+)") do
                        val = trim(val)
                        if val ~= "" then
                            table.insert(data[prop], val)
                        end
                    end
                end
            end
        end
        return
    end
    
    -- Parse the line for property:value pairs by scanning around colons
    local function parsePropertyName(source, colonPos)
        local idx = colonPos - 1
        local words = {}

        while idx > 0 and source:sub(idx, idx):match("%s") do
            idx = idx - 1
        end
        if idx <= 0 or source:sub(idx, idx) == "|" then
            return nil, nil
        end

        local wordEnd = idx
        while idx > 0 do
            local ch = source:sub(idx, idx)
            if ch == "|" or ch:match("%s") then
                break
            end
            idx = idx - 1
        end
        local wordStart = idx + 1
        table.insert(words, 1, source:sub(wordStart, wordEnd))
        local propStart = wordStart

        while idx > 0 do
            local spaceCount = 0
            while idx > 0 and source:sub(idx, idx):match("%s") do
                spaceCount = spaceCount + 1
                idx = idx - 1
            end
            if idx <= 0 or source:sub(idx, idx) == "|" then
                break
            end
            if spaceCount >= 2 then
                break
            end

            wordEnd = idx
            while idx > 0 do
                local ch = source:sub(idx, idx)
                if ch == "|" or ch:match("%s") then
                    break
                end
                idx = idx - 1
            end
            wordStart = idx + 1
            local word = source:sub(wordStart, wordEnd)
            if word:match("%d") then
                break
            end
            table.insert(words, 1, word)
            propStart = wordStart
        end

        local propName = trim(table.concat(words, " "))
        propName = trim(propName:gsub("^:+", ""))
        if propName == "" then
            return nil, nil
        end
        return propName, propStart
    end

    local function parseNumericValue(rawValue)
        local cleaned = rawValue:gsub(",", ""):gsub("^%s*", ""):gsub("%s*$", ""):gsub("^%+", "")
        local numericStr = cleaned:match("^[+-]?%d+%.?%d*")
        if numericStr and numericStr ~= "" then
            return tonumber(numericStr)
        end
        return nil
    end

    local remaining = clean
    local foundProps = {}
    local i = 1
    while i <= #remaining do
        local colonPos = remaining:find(":", i)
        if not colonPos then
            break
        end
        local propName, propStart = parsePropertyName(remaining, colonPos)
        if propName and propStart then
            table.insert(foundProps, {
                name = propName,
                colonPos = colonPos,
                propStart = propStart,
            })
        end
        i = colonPos + 1
    end

    for idx, prop in ipairs(foundProps) do
        local valueStart = prop.colonPos + 1
        local valueEnd

        if idx < #foundProps and prop.name:lower() ~= "name" then
            valueEnd = foundProps[idx + 1].propStart - 1
        else
            valueEnd = #remaining
            local pipePos = remaining:find("|", valueStart)
            if pipePos then
                valueEnd = pipePos - 1
            end
        end

        local rawValue = remaining:sub(valueStart, valueEnd)
        rawValue = trim(rawValue)

        repeat
            if prop.name:lower() == "stat mods" then
                break
            end

            local propKey = prop.name:lower():gsub(" ", "")
            local numericProps = {
                hitroll = true, damageroll = true,
                strength = true, intelligence = true, wisdom = true,
                dexterity = true, constitution = true, luck = true,
                hitpoints = true, mana = true, moves = true,
                level = true, worth = true, weight = true,
                score = true, capacity = true, holding = true,
                averagedam = true, itemsinside = true, totweight = true,
                allphysical = true, allmagic = true,
                acid = true, cold = true, energy = true, holy = true,
                electric = true, negative = true, shadow = true, magic = true,
                air = true, earth = true, fire = true, light = true,
                mental = true, sonic = true, water = true,
                poison = true, disease = true,
                slash = true, pierce = true, bash = true,
                itemburden = true, heaviestitem = true, weightreduction = true,
            }

            local normalizedKey = propKey
            if propKey == "hitroll" then normalizedKey = "hitroll"
            elseif propKey == "damageroll" then normalizedKey = "damroll"
            elseif propKey == "hitpoints" then normalizedKey = "hp"
            elseif propKey == "averagedam" then normalizedKey = "avedam"
            elseif propKey == "itemsinside" then normalizedKey = "itemsinside"
            elseif propKey == "totweight" then normalizedKey = "totweight"
            elseif propKey == "allphysical" then normalizedKey = "allphys"
            elseif propKey == "allmagic" then normalizedKey = "allmagic"
            elseif propKey == "itemburden" then normalizedKey = "itemburden"
            elseif propKey == "heaviestitem" then normalizedKey = "heaviestitem"
            elseif propKey == "weightreduction" then normalizedKey = "weightreduction"
            end

            local numericValue = parseNumericValue(rawValue)
            if numericValue ~= nil then
                if numericProps[propKey] then
                    -- RID lines can be replayed by multiple triggers while identify text is
                    -- still streaming. Numeric stats should reflect the latest parsed value,
                    -- not an accumulated total across duplicate parses.
                    data[normalizedKey] = numericValue
                else
                    data[normalizedKey] = numericValue
                end
                dbot.debug("[RID] " .. prop.name .. " = " .. tostring(numericValue), "rid")
            else
                local multiValueProps = { flags = true, keywords = true, notes = true }

                if multiValueProps[propKey] then
                    data[propKey] = data[propKey] or {}
                    for val in rawValue:gmatch("([^,]+)") do
                        val = trim(val)
                        if val ~= "" then
                            table.insert(data[propKey], val)
                        end
                    end
                    parseState.lastProperty = propKey
                    dbot.debug("[RID] " .. prop.name .. " (multi) = " .. rawValue, "rid")
                else
                    if rawValue ~= "" then
                        data[propKey] = rawValue
                        parseState.lastProperty = propKey
                        dbot.debug("[RID] " .. prop.name .. " = " .. rawValue, "rid")
                    end
                end
            end
        until true
    end
end

function inv.rid.parseLine(line, data, state)
    if not line or not data then
        return
    end
    parseLine(line, data, state)
end

----------------------------------------------------------------------------------------------------
-- State Management
----------------------------------------------------------------------------------------------------

function inv.rid.isActive()
    return inv.rid.active == true
end

function inv.rid.resetState()
    inv.rid.disableTriggers()
    inv.rid.active = false
    inv.rid.item = nil
    inv.rid.target = nil
    inv.rid.channel = { type = "default", name = nil }
    inv.rid.lineCount = 0
    inv.rid.lastProperty = nil
    inv.rid.inEnchants = false
end

----------------------------------------------------------------------------------------------------
-- Trigger Registration
----------------------------------------------------------------------------------------------------

function inv.rid.registerTriggers()
    inv.rid.ids = inv.rid.ids or {}
    if inv.rid.ids.registered then
        return
    end

    inv.rid.ids.fence = tempRegexTrigger(
        "^\\s*" .. inv.rid.fence .. "\\s*$",
        function()
            if inv.rid.isActive() then
                inv.rid.finish()
            end
        end
    )

    inv.rid.ids.cardLine = tempRegexTrigger(
        "^[^|]*\\|.+\\|",
        function()
            if not inv.rid.isActive() then return end
            local line = getCurrentLine() or ""
            inv.rid.handleLine(line)
            if inv.rid.suppressIdentifyOutput and deleteLine then
                deleteLine()
            end
        end
    )

    inv.rid.ids.plainLine = tempRegexTrigger(
        "^[^|]*:%s*",
        function()
            if not inv.rid.isActive() then return end
            if inv.rid.suppressIdentifyOutput and deleteLine then
                deleteLine()
            end
        end
    )

    inv.rid.ids.borderLine = tempRegexTrigger(
        "^\\+[-]+\\+$",
        function()
            if not inv.rid.isActive() then return end
            if deleteLine then
                deleteLine()
            end
        end
    )

    inv.rid.ids.appraisalLine = tempRegexTrigger(
        "A full appraisal will reveal",
        function()
            if not inv.rid.isActive() then return end
            if deleteLine then
                deleteLine()
            end
        end
    )

    inv.rid.ids.registered = true
    inv.rid.disableTriggers()
end

function inv.rid.enableTriggers()
    for key, id in pairs(inv.rid.ids or {}) do
        if key ~= "registered" and id and enableTrigger then
            pcall(enableTrigger, id)
        end
    end
end

function inv.rid.disableTriggers()
    for key, id in pairs(inv.rid.ids or {}) do
        if key ~= "registered" and id and disableTrigger then
            pcall(disableTrigger, id)
        end
    end
end

----------------------------------------------------------------------------------------------------
-- Line Handler
----------------------------------------------------------------------------------------------------

function inv.rid.handleLine(line)
    if not inv.rid.isActive() then return end
    inv.rid.lineCount = inv.rid.lineCount + 1
    inv.rid.item = inv.rid.item or { data = {} }
    inv.rid.item.data = inv.rid.item.data or {}
    parseLine(line, inv.rid.item.data)
end

----------------------------------------------------------------------------------------------------
-- Format value for display (no + for positive, - for negative)
----------------------------------------------------------------------------------------------------

local function formatValue(value)
    local num = tonumber(value)
    if num then
        return tostring(num)
    end
    return tostring(value)
end

----------------------------------------------------------------------------------------------------
-- Build enchant indicator: R I S with colors
-- Green (@G) = removable by enchanter
-- Red (@R) = removable with TP only
-- Skip letter if not present
----------------------------------------------------------------------------------------------------

local function buildEnchantIndicator(enchants)
    if not enchants then return nil end
    
    local parts = {}
    
    if enchants.resonate then
        if enchants.resonate == "enchanter" then
            table.insert(parts, "@GR@w")
        else
            table.insert(parts, "@RR@w")
        end
    end
    
    if enchants.illuminate then
        if enchants.illuminate == "enchanter" then
            table.insert(parts, "@GI@w")
        else
            table.insert(parts, "@RI@w")
        end
    end
    
    if enchants.solidify then
        if enchants.solidify == "enchanter" then
            table.insert(parts, "@GS@w")
        else
            table.insert(parts, "@RS@w")
        end
    end
    
    if #parts > 0 then
        return "[" .. table.concat(parts, "") .. "]"
    end
    
    return nil
end

----------------------------------------------------------------------------------------------------
-- Build compact report (for channels)
----------------------------------------------------------------------------------------------------

function inv.rid.buildCompactReport()
    local d = (inv.rid.item and inv.rid.item.data) or {}
    
    local parts = {}
    table.insert(parts, "@Cdinv rid@w")
    table.insert(parts, tostring(d.id or inv.rid.target or "?"))
    table.insert(parts, tostring(d.name or inv.rid.target or "?"))
    
    if d.type then table.insert(parts, "type: " .. d.type) end
    if d.level then table.insert(parts, "lvl: " .. formatValue(d.level)) end
    if d.score then table.insert(parts, "score: " .. formatValue(d.score)) end
    
    if tonumber(d.damroll) and tonumber(d.damroll) ~= 0 then
        table.insert(parts, "dr: " .. formatValue(d.damroll))
    end
    if tonumber(d.hitroll) and tonumber(d.hitroll) ~= 0 then
        table.insert(parts, "hr: " .. formatValue(d.hitroll))
    end
    
    local statOrder = {
        { field = "strength", label = "str" },
        { field = "int", label = "int" },
        { field = "intelligence", label = "int" },
        { field = "wisdom", label = "wis" },
        { field = "dexterity", label = "dex" },
        { field = "constitution", label = "con" },
        { field = "luck", label = "luck" },
        { field = "hp", label = "hp" },
        { field = "mana", label = "mana" },
        { field = "moves", label = "moves" },
    }
    
    local seenStats = {}
    for _, s in ipairs(statOrder) do
        if not seenStats[s.label] then
            local val = tonumber(d[s.field])
            if val and val ~= 0 then
                table.insert(parts, s.label .. ": " .. formatValue(val))
                seenStats[s.label] = true
            end
        end
    end
    
    if d.wearable then table.insert(parts, "wear: " .. d.wearable) end
    
    -- Enchant indicator
    local enchantInd = buildEnchantIndicator(d.enchants)
    if enchantInd then
        table.insert(parts, enchantInd)
    end
    
    return table.concat(parts, " ")
end

----------------------------------------------------------------------------------------------------
-- Build detailed report (for screen)
----------------------------------------------------------------------------------------------------

function inv.rid.buildDetailedReport()
    local d = (inv.rid.item and inv.rid.item.data) or {}
    local lines = {}
    
    table.insert(lines, "@C--- DINV RID Report ---@w")
    
    if d.name then table.insert(lines, "@WName:@w " .. d.name) end
    if d.id then table.insert(lines, "@WId:@w " .. d.id) end
    
    -- Keywords as comma-separated
    if d.keywords then
        if type(d.keywords) == "table" then
            table.insert(lines, "@WKeywords:@w " .. table.concat(d.keywords, ", "))
        else
            table.insert(lines, "@WKeywords:@w " .. d.keywords)
        end
    end
    
    if d.type then table.insert(lines, "@WType:@w " .. d.type) end
    if d.level then table.insert(lines, "@WLevel:@w " .. formatValue(d.level)) end
    if d.wearable then table.insert(lines, "@WWearable:@w " .. d.wearable) end
    if d.score then table.insert(lines, "@WScore:@w " .. formatValue(d.score)) end
    if d.worth then table.insert(lines, "@WWorth:@w " .. formatValue(d.worth)) end
    if d.weight then table.insert(lines, "@WWeight:@w " .. formatValue(d.weight)) end
    if d.material then table.insert(lines, "@WMaterial:@w " .. d.material) end
    if d.duration then table.insert(lines, "@WDuration:@w " .. d.duration) end
    
    -- Weapon info
    if d.weapontype then table.insert(lines, "@WWeapon Type:@w " .. d.weapontype) end
    if d.avedam then table.insert(lines, "@WAverage Dam:@w " .. formatValue(d.avedam)) end
    if d.damagetype then table.insert(lines, "@WDamage Type:@w " .. d.damagetype) end
    if d.inflicts then table.insert(lines, "@WInflicts:@w " .. d.inflicts) end
    if d.specials then table.insert(lines, "@WSpecials:@w " .. d.specials) end
    
    -- Container info
    if d.capacity then table.insert(lines, "@WCapacity:@w " .. formatValue(d.capacity)) end
    if d.holding then table.insert(lines, "@WHolding:@w " .. formatValue(d.holding)) end
    if d.heaviestitem then table.insert(lines, "@WHeaviest Item:@w " .. formatValue(d.heaviestitem)) end
    if d.itemsinside then table.insert(lines, "@WItems Inside:@w " .. formatValue(d.itemsinside)) end
    if d.totweight then table.insert(lines, "@WTot Weight:@w " .. formatValue(d.totweight)) end
    if d.itemburden then table.insert(lines, "@WItem Burden:@w " .. formatValue(d.itemburden)) end
    if d.weightreduction then table.insert(lines, "@WWeight Reduction:@w " .. formatValue(d.weightreduction)) end
    
    -- Portal info
    if d.leadsto then table.insert(lines, "@WLeads to:@w " .. d.leadsto) end
    
    -- Stats
    local stats = {}
    local statDefs = {
        { field = "hitroll", label = "Hit roll" },
        { field = "damroll", label = "Damage roll" },
        { field = "strength", label = "Str" },
        { field = "intelligence", label = "Int" },
        { field = "wisdom", label = "Wis" },
        { field = "dexterity", label = "Dex" },
        { field = "constitution", label = "Con" },
        { field = "luck", label = "Luck" },
        { field = "hp", label = "HP" },
        { field = "mana", label = "Mana" },
        { field = "moves", label = "Moves" },
        { field = "allphys", label = "All physical" },
        { field = "allmagic", label = "All magic" },
        { field = "slash", label = "Slash" },
        { field = "pierce", label = "Pierce" },
        { field = "bash", label = "Bash" },
        { field = "acid", label = "Acid" },
        { field = "cold", label = "Cold" },
        { field = "energy", label = "Energy" },
        { field = "holy", label = "Holy" },
        { field = "electric", label = "Electric" },
        { field = "negative", label = "Negative" },
        { field = "shadow", label = "Shadow" },
        { field = "magic", label = "Magic" },
        { field = "air", label = "Air" },
        { field = "earth", label = "Earth" },
        { field = "fire", label = "Fire" },
        { field = "light", label = "Light" },
        { field = "mental", label = "Mental" },
        { field = "sonic", label = "Sonic" },
        { field = "water", label = "Water" },
        { field = "poison", label = "Poison" },
        { field = "disease", label = "Disease" },
    }
    
    for _, s in ipairs(statDefs) do
        local val = tonumber(d[s.field])
        if val and val ~= 0 then
            table.insert(stats, s.label .. ": " .. formatValue(val))
        end
    end
    
    if #stats > 0 then
        table.insert(lines, "@WStats:@w " .. table.concat(stats, ", "))
    end
    
    -- Flags as comma-separated
    if d.flags then
        local flagStr
        if type(d.flags) == "table" then
            flagStr = table.concat(d.flags, ", ")
        else
            flagStr = d.flags
        end
        table.insert(lines, "@WFlags:@w " .. flagStr)
    end
    
    -- Notes
    if d.notes then
        local noteStr
        if type(d.notes) == "table" then
            noteStr = table.concat(d.notes, " | ")
        else
            noteStr = d.notes
        end
        table.insert(lines, "@WNotes:@w " .. noteStr)
    end
    
    -- Other info
    if d.foundat then table.insert(lines, "@WFound at:@w " .. d.foundat) end
    if d.ownedby then table.insert(lines, "@WOwner:@w " .. d.ownedby) end
    if d.clanitem then table.insert(lines, "@WClan:@w " .. d.clanitem) end
    
    -- Enchant indicator
    local enchantInd = buildEnchantIndicator(d.enchants)
    if enchantInd then
        table.insert(lines, "@WEnchants:@w " .. enchantInd)
    end
    
    return table.concat(lines, "\n")
end

----------------------------------------------------------------------------------------------------
-- Report Sending
----------------------------------------------------------------------------------------------------

function inv.rid.sendReport()
    local channel = inv.rid.channel or { type = "default" }
    
    if channel.type == "default" then
        dbot.print(inv.rid.buildDetailedReport())
        return
    end

    local report = inv.rid.buildCompactReport()
    local message = dbot.stripColors(report)
    
    if channel.type == "gt" or channel.type == "gtell" then
        send("gt " .. message)
    elseif channel.type == "say" then
        send("say " .. message)
    elseif channel.type == "tell" and channel.name then
        send("tell " .. channel.name .. " " .. message)
    elseif channel.type == "channel" and channel.name then
        send(channel.name .. " " .. message)
    else
        dbot.print(report)
    end
end

function inv.rid.finish()
    if not inv.rid.isActive() then return end
    dbot.debug("[RID] Finish - processed " .. tostring(inv.rid.lineCount) .. " lines", "rid")
    inv.rid.sendReport()
    inv.rid.resetState()
end

----------------------------------------------------------------------------------------------------
-- Channel Resolution
----------------------------------------------------------------------------------------------------

local function resolveChannel(wildcards)
    local channel = { type = "default", name = nil }
    local arg = wildcards and wildcards[2] or nil
    if not arg or arg == "" then return channel end

    local channelType = tostring(arg):lower()
    channel.type = channelType
    
    if channelType == "tell" or channelType == "channel" then
        channel.name = wildcards[3]
    end

    return channel
end

----------------------------------------------------------------------------------------------------
-- Main Start Function
----------------------------------------------------------------------------------------------------

function inv.rid.start(target, channel)
    if inv.rid.isActive() then
        dbot.warn("rid: already running")
        return DRL_RET_BUSY
    end

    if not target or target == "" then
        dbot.warn("rid: missing target")
        return DRL_RET_INVALID_PARAM
    end

    dbot.debug("[RID] Starting for: " .. tostring(target), "rid")

    inv.rid.active = true
    inv.rid.target = target
    inv.rid.channel = channel or { type = "default", name = nil }
    inv.rid.lineCount = 0
    inv.rid.lastProperty = nil
    inv.rid.inEnchants = false
    inv.rid.item = { data = {} }

    inv.rid.registerTriggers()
    inv.rid.enableTriggers()

    send("identify " .. target)
    send("echo " .. inv.rid.fence)

    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- CLI Command
----------------------------------------------------------------------------------------------------

inv.cli.rid = inv.cli.rid or {}

function inv.cli.rid.fn(name, line, wildcards)
    local target = wildcards and wildcards[1] or nil
    if not target or target == "" then
        inv.cli.rid.usage()
        return DRL_RET_INVALID_PARAM
    end

    local channel = resolveChannel(wildcards or {})
    return inv.rid.start(target, channel)
end

function inv.cli.rid.usage()
    dbot.print(string.format("@W    %-50s @w- %s",
        pluginNameCmd .. " rid <target> [say|gt|tell <n>|channel <n>]",
        "Report identify stats for an item"))
end

function inv.cli.rid.examples()
    dbot.print([[@W
Usage:
    dinv rid <target>              - Detailed report to screen
    dinv rid <target> gt           - Compact report to group
    dinv rid <target> say          - Compact report via say
    dinv rid <target> tell <n>     - Compact report via tell

Examples:
    dinv rid light
    dinv rid 2.sword
    dinv rid aura gt

Enchant indicator at end: [RIS]
  @GR@w = Resonate (removable by enchanter)
  @RR@w = Resonate (TP only)
  @GI@w = Illuminate (removable by enchanter)  
  @RI@w = Illuminate (TP only)
  @GS@w = Solidify (removable by enchanter)
  @RS@w = Solidify (TP only)
]])
end

if DINV and DINV.debug and DINV.debug.registerModule then
    DINV.debug.registerModule("rid", "RID identify reporting")
end

end -- RID module disabled
