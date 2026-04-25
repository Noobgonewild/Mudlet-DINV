----------------------------------------------------------------------------------------------------
-- DINV Triggers Module
-- Mudlet trigger definitions for DINV
----------------------------------------------------------------------------------------------------

DINV.triggers = {}
DINV.triggers.ids = {}

----------------------------------------------------------------------------------------------------
-- Register Enhanced Triggers
----------------------------------------------------------------------------------------------------

function DINV.triggers.registerEnhanced()
    -- Unregister old triggers first
    DINV.triggers.unregister()

    DINV.triggers.ids = {}

    -- GMCP event handlers (Mudlet uses event system instead of triggers for GMCP)
    -- These are registered in the loader, but we can add additional handlers here

    -- identify output triggers
    DINV.triggers.ids.identifyStart = tempRegexTrigger(
        "^\\{identify\\}$",
        function()
            -- RID identify interception disabled (RID command/module is commented out)
            inv.items.inIdentify = true
            inv.items.identifyContinuation = nil
            dbot.debug("identify start", "triggers")
        end
    )

    DINV.triggers.ids.identifyEnd = tempRegexTrigger(
        "^\\{/identify\\}$",
        function()
            -- RID identify interception disabled (RID command/module is commented out)
            inv.items.inIdentify = false
            local objId = inv.items.currentIdentifyId
            if objId then
                local item = inv.items.getItem(objId)
                if item and item.stats then
                    item.stats.identifyLevel = invIdLevelFull
                    inv.items.setItem(objId, item)
                    if inv.items.cacheIdentifiedItem then
                        inv.items.cacheIdentifiedItem(item)
                    end
                    dbot.debug("Identify complete for " .. tostring(objId) .. ", identifyLevel=" .. tostring(item.stats.identifyLevel), "triggers")
                end
            end
            inv.items.currentIdentifyId = nil
            inv.items.identifyContinuation = nil
            inv.items.identifyResetId = nil
            dbot.debug("identify end", "triggers")
        end
    )

    -- State machine for untagged identify parsing
    inv.items.identifyActive = false
    inv.items.identifyObjId = nil

    -- Capture ALL identify lines (lines starting with |)
    DINV.triggers.ids.identifyLine = tempRegexTrigger(
        "^(\\{identify\\})?(.*)$",
        function()
            -- Mudlet provides regex captures via global 'matches'. tempRegexTrigger
            -- callbacks are not guaranteed to receive captures as function args.
            if not matches then return end

            -- Only parse identify output while DINV is actively doing inventory work
            -- (build/refresh/identify) or inside an identify block.
            -- NOTE: do not gate on identifyActive itself, or a missed end marker can
            -- keep this parser effectively active outside operation windows.
            local inventoryCycleActive = inv and inv.items and (
                inv.items.buildInProgress or
                inv.items.refreshInProgress or
                inv.items.identifyInProgress or
                inv.items.inIdentify
            )

            if not inventoryCycleActive then
                return
            end

            local isTagged = matches[2] and matches[2] ~= ""
            local line = isTagged and matches[3] or matches[2]

            -- Skip empty lines
            if not line or line == "" then return end

            -- Check if this looks like an identify line (starts with |)
            local isIdentifyLine = line:match("^%s*|")

            -- Check for ID to start tracking
            local id = line:match("|%s*Id%s*:%s*(%d+)")
            if id then
                inv.items.identifyActive = true
                inv.items.identifyObjId = tonumber(id)
                inv.items.currentIdentifyId = inv.items.identifyObjId
                dbot.debug("Identify started for ID: " .. tostring(id), "inv.items")
            end

            -- Process line if we're in an active identify
            if inv.items.identifyActive and inv.items.identifyObjId and isIdentifyLine then
                inv.items.onIdentifyLine(line)
            end

            -- Check for end of identify (line with just dashes or doesn't start with |)
            if inv.items.identifyActive then
                local isEndLine = line:match("^%s*%-%-%-%-") or
                                  line:match("^%s*|%s*%-+%s*|%s*$") or
                                  (not isIdentifyLine and inv.items.identifyObjId)

                if isEndLine then
                    if inv.items.identifyObjId then
                        local item = inv.items.getItem(inv.items.identifyObjId)
                        if item and item.stats then
                            item.stats.identifyLevel = invIdLevelFull
                            inv.items.setItem(inv.items.identifyObjId, item)
                            dbot.debug("Identify complete for " .. tostring(inv.items.identifyObjId), "inv.items")
                        end
                    end
                    inv.items.identifyActive = false
                    inv.items.identifyObjId = nil
                    inv.items.currentIdentifyId = nil
                    inv.items.identifyResetId = nil
                end
            end
        end
    )

    -- Sleep detection trigger
    DINV.triggers.ids.sleep = tempRegexTrigger(
        "^You go to sleep\\.$",
        function()
            if inv and inv.regen and inv.regen.onSleep then
                inv.regen.onSleep()
            end
        end
    )

    -- Wake detection trigger
    DINV.triggers.ids.wake = tempRegexTrigger(
        "^You wake and stand up\\.$",
        function()
            if inv and inv.regen and inv.regen.onWake then
                inv.regen.onWake()
            end
        end
    )

    dbot.debug("Enhanced triggers registered", "triggers")
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Register all triggers
----------------------------------------------------------------------------------------------------

function DINV.triggers.register()
    return DINV.triggers.registerEnhanced()
end

----------------------------------------------------------------------------------------------------
-- Unregister all triggers
----------------------------------------------------------------------------------------------------

function DINV.triggers.unregister()
    for name, id in pairs(DINV.triggers.ids) do
        if id then
            killTrigger(id)
        end
    end
    DINV.triggers.ids = {}

    if DINV.discovery and DINV.discovery.unregister then
        DINV.discovery.unregister()
    end

    dbot.debug("DINV triggers unregistered", "triggers")
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Identify Line Handler
----------------------------------------------------------------------------------------------------

function inv.items.onIdentifyLine(dataLine)
    local line = tostring(dataLine or "")

    local objId = inv.items.currentIdentifyId
    if not objId then
        -- Try to extract ID from line
        local id = line:match("Id%s*:%s*(%d+)")
        if id then
            objId = tonumber(id)
            inv.items.currentIdentifyId = objId
        end
    end

    if not objId then
        return DRL_RET_SUCCESS
    end

    local item = inv.items.getItem(objId)
    if item == nil then
        item = { stats = {} }
        inv.items.setItem(objId, item)
    end
    item.stats = item.stats or {}
    if inv.items.identifyResetId ~= objId then
        inv.items.resetIdentifyStats(item)
        inv.items.setItem(objId, item)
        inv.items.identifyResetId = objId
    end

    -- Parse identify line
    local result = inv.items.parseIdentifyLine(item, line)
    inv.items.setItem(objId, item)
    return result
end

----------------------------------------------------------------------------------------------------
-- Parse Identify Line
----------------------------------------------------------------------------------------------------

function inv.items.parseIdentifyLine(item, line)
    if item == nil or line == nil then
        return DRL_RET_INVALID_PARAM
    end

    dbot.debug("parseIdentifyLine: " .. tostring(line):sub(1, 60), "inv.items")

    item.stats = item.stats or {}

    ---------------------------------------------------------------------------
    -- Character-by-character extraction (ported from RID module)
    ---------------------------------------------------------------------------

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
                i = i + 1  -- Skip commas in numbers
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

    local function parsePropertyName(source, colonPos)
        local idx = colonPos - 1
        local words = {}

        -- Skip trailing whitespace before colon
        while idx > 0 and source:sub(idx, idx):match("%s") do
            idx = idx - 1
        end
        if idx <= 0 or source:sub(idx, idx) == "|" then
            return nil, nil
        end

        -- Collect first word
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

        -- Collect additional words (multi-word property names like "Hit roll")
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
                break  -- Two+ spaces = property boundary
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
                break  -- Word contains digit = value, not property name
            end
            table.insert(words, 1, word)
            propStart = wordStart
        end

        local propName = table.concat(words, " "):gsub("^:+", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if propName == "" then
            return nil, nil
        end
        return propName, propStart
    end
    
    -- Initialize continuation state if needed
    inv.items.identifyContinuation = inv.items.identifyContinuation or {
        flags = false,
        affectMods = false,
        keywords = false,
        name = false,
    }
    local continuationState = inv.items.identifyContinuation

    -- Helper to convert strings with commas to numbers
    local function toNumber(value)
        if value == nil then
            return nil
        end
        -- gsub returns (newString, replacements); select(1, ...) avoids passing replacements as tonumber base
        local normalized = select(1, tostring(value):gsub(",", ""))
        return tonumber(normalized)
    end

    -- Clean up the line
    local trimmed = tostring(line):gsub("^%s+", ""):gsub("%s+$", "")
    local cleanLine = dbot.stripColors(trimmed)
    local lowerLine = cleanLine:lower()
    local lowerTrimmed = cleanLine:lower()
    local originalLine = line
    local isContinuationLine = cleanLine:match("|%s+:%s+(.-)%s*|") ~= nil

    -- Continuations are only valid on immediately-following wrapped lines.
    -- If we moved to a new non-continuation line, clear stale continuation state
    -- so unrelated sections (e.g. Spells) don't get appended to Name/Flags/etc.
    if not isContinuationLine then
        continuationState.name = false
        continuationState.keywords = false
        continuationState.flags = false
        continuationState.affectMods = false
    end

    ---------------------------------------------------------------------------
    -- RID-STYLE PARSING DISABLED
    -- (RID command/module was commented out per user request)
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    -- BASIC FIELDS (matching MUSHclient patterns exactly)
    ---------------------------------------------------------------------------

    -- Id : 1930857578
    local id = cleanLine:match("Id%s+:%s+(%d+)")
    if id then
        item.stats[invStatFieldId] = tostring(id)
        continuationState.name = false
    end

    -- Name : Axe of Aardwolf
    local name = cleanLine:match("Name%s+:%s+(.-)%s*|$")
    if name and name ~= "" then
        -- Strip enchant text that may have been appended (e.g., "Wisdom +4 (removable...)")
        name = name:gsub("%s+[A-Z][a-z]+%s+%+?%-?%d+%s*%(removable[^%)]*%)%s*", "")
        name = name:gsub("%s+%(removable[^%)]*%)%s*", "")
        item.stats[invStatFieldName] = dbot.stripColors(name)
        if not item.stats[invStatFieldColorName] or item.stats[invStatFieldColorName] == "" then
            local colorName = tostring(originalLine):match("Name%s+:%s+(.-)%s*|$") or name
            colorName = colorName:gsub("%s+[A-Z][a-z]+%s+%+?%-?%d+%s*%(removable[^%)]*%)%s*", "")
            colorName = colorName:gsub("%s+%(removable[^%)]*%)%s*", "")
            item.stats[invStatFieldColorName] = colorName
        end
        continuationState.keywords = false
        continuationState.name = true
    end

    -- Level : 100
    -- COMMENT OUT - now handled by numericProps loop
    -- local level = cleanLine:match("Level%s+:%s+(%d+)")
    -- if level then
    --     item.stats[invStatFieldLevel] = tonumber(level)
    -- end

    -- Weight : 20
    -- COMMENT OUT - now handled by numericProps loop
    -- local weight = cleanLine:match("Weight%s+:%s+([0-9,%-]+)")
    -- if weight then
    --     item.stats[invStatFieldWeight] = toNumber(weight)
    -- end

    -- Wearable : wield   (MUSHclient pattern: "Wearable%s+:%s+(.*) %s+")
    local wearable = cleanLine:match("Wearable%s+:%s+(.-)%s*|")
    if not wearable then
        wearable = cleanLine:match("Wearable%s+:%s+(.+)$")
    end
    if wearable then
        -- Strip commas and extra whitespace
        wearable = wearable:gsub(",", ""):gsub("%s+$", ""):gsub("|", "")
        if wearable ~= "" then
            item.stats[invStatFieldWearable] = wearable
        end
    end

    -- Score : 1300
    -- COMMENT OUT - now handled by numericProps loop
    -- local score = cleanLine:match("Score%s+:%s+([0-9,]+)")
    -- if score then
    --     item.stats[invStatFieldScore] = toNumber(score)
    -- end

    -- Worth : 1,000
    -- COMMENT OUT - now handled by numericProps loop
    -- local worth = cleanLine:match("Worth%s+:%s+([0-9,]+)")
    -- if worth then
    --     item.stats[invStatFieldWorth] = toNumber(worth)
    -- end

    -- Keywords : axe aardwolf (400298)
    local keywords = cleanLine:match("Keywords%s+:%s+(.-)%s*|")
    if keywords then
        local oldKeywords = item.stats[invStatFieldKeywords] or ""
        if dbot.mergeFields then
            item.stats[invStatFieldKeywords] = dbot.mergeFields(keywords, oldKeywords)
        else
            item.stats[invStatFieldKeywords] = keywords
        end
        continuationState.keywords = true
        continuationState.name = false
    end

    -- Type : Weapon   Level : 100  (combined line)
    local itemType = cleanLine:match("|%s*Type%s+:%s+(%a+)%s+")
    if not itemType then
        itemType = cleanLine:match("Type%s+:%s+(%a+)%s+Level")
    end
    if not itemType then
        -- Handle "Raw material" type
        local rawMat = cleanLine:match("Type%s+:%s+(Raw material[:%a]*)")
        if rawMat then
            itemType = rawMat:gsub("%s+", "")
        end
    end
    if itemType then
        item.stats[invStatFieldType] = itemType
    end

    -- Worn : Wielded
    local worn = cleanLine:match("Worn%s+:%s+(%a+)")
    if worn then
        item.stats[invStatFieldWorn] = worn
    end

    -- Flags : unique, glow, hum, magic, held, V3, precious
    local flags = cleanLine:match("Flags%s+:%s+(.-)%s*|")
    if flags then
        item.stats[invStatFieldFlags] = flags
        continuationState.flags = flags:match(",%s*$") ~= nil
    end

    -- Material : stone
    local material = cleanLine:match("Material%s+:%s+(.-)%s*|")
    if not material then
        material = cleanLine:match("Material%s+:%s+(.+)$")
    end
    if material then
        material = material:gsub("%s*|%s*$", ""):gsub("%s+$", "")
        item.stats[invStatFieldMaterial] = material
    end

    -- Found at : Immortal Homes
    local foundAt = cleanLine:match("Found at%s+:%s+(.-)%s*|")
    if foundAt then
        item.stats[invStatFieldFoundAt] = foundAt
    end

    -- Owned By : Gizmmo
    local ownedBy = cleanLine:match("Owned By%s+:%s+(.-)%s*|")
    if ownedBy then
        item.stats[invStatFieldOwner] = ownedBy
    end

    -- Clan Item : [clan name]
    local clan = cleanLine:match("Clan Item%s+:%s+(.-)%s*|")
    if clan then
        item.stats[invStatFieldClan] = clan
    end

    -- Affect Mods : haste, sanctuary
    local affectMods = cleanLine:match("Affect Mods%s*:%s+(.-)%s*|")
    if affectMods then
        item.stats[invStatFieldAffectMods] = affectMods
        item.stats[invStatFieldAffects] = affectMods
        continuationState.affectMods = affectMods:match(",%s*$") ~= nil
    end

    ---------------------------------------------------------------------------
    -- CONTAINER FIELDS
    ---------------------------------------------------------------------------

    local capacity = cleanLine:match("Capacity%s*:%s*([%d,]+)")
    if capacity then
        item.stats[invStatFieldCapacity] = toNumber(capacity)
    end

    local holding = cleanLine:match("Holding%s*:%s*([%d,]+)")
    if holding then
        item.stats[invStatFieldHolding] = toNumber(holding)
    end

    local itemsInside = cleanLine:match("Items Inside%s*:%s*([%d,]+)")
    if itemsInside then
        item.stats[invStatFieldItemsInside] = toNumber(itemsInside)
    end

    local totWeight = cleanLine:match("Tot Weight%s*:%s*([%d,]+)")
    if totWeight then
        item.stats[invStatFieldTotWeight] = toNumber(totWeight)
    end

    local itemBurden = cleanLine:match("Item Burden%s*:%s*([%d,]+)")
    if itemBurden then
        item.stats[invStatFieldItemBurden] = toNumber(itemBurden)
    end

    local reducedBy = cleanLine:match("Items inside weigh%s+(%d+)%%?%s+of their usual weight")
    if reducedBy then
        item.stats[invStatFieldReducedBy] = toNumber(reducedBy)
    end

    ---------------------------------------------------------------------------
    -- POTION/PILL/WAND/STAFF FIELDS
    ---------------------------------------------------------------------------

    local spellUses, spellLevel, spellName = cleanLine:match("(%d+) uses? of level (%d+) '(.-)'")
    if spellUses then
        item.stats[invStatFieldSpellUses] = toNumber(spellUses)
        item.stats[invStatFieldSpellLevel] = toNumber(spellLevel)
        item.stats[invStatFieldSpellName] = spellName
        continuationState.name = false
        continuationState.keywords = false
        continuationState.flags = false
        continuationState.affectMods = false
    end

    -- Portal: Leads to : [area]
    local leadsTo = cleanLine:match("Leads to%s+:%s+(.-)%s*|")
    if leadsTo then
        item.stats[invStatFieldLeadsTo] = leadsTo
    end

    ---------------------------------------------------------------------------
    -- RESIST FIELDS (standalone lines)
    ---------------------------------------------------------------------------

    local resistPatterns = {
        { pattern = "slash%s+:%s+([+-]?%d+)", field = invStatFieldSlash },
        { pattern = "pierce%s+:%s+([+-]?%d+)", field = invStatFieldPierce },
        { pattern = "bash%s+:%s+([+-]?%d+)", field = invStatFieldBash },
        { pattern = "acid%s+:%s+([+-]?%d+)", field = invStatFieldAcid },
        { pattern = "cold%s+:%s+([+-]?%d+)", field = invStatFieldCold },
        { pattern = "energy%s+:%s+([+-]?%d+)", field = invStatFieldEnergy },
        { pattern = "holy%s+:%s+([+-]?%d+)", field = invStatFieldHoly },
        { pattern = "electric%s+:%s+([+-]?%d+)", field = invStatFieldElectric },
        { pattern = "negative%s+:%s+([+-]?%d+)", field = invStatFieldNegative },
        { pattern = "shadow%s+:%s+([+-]?%d+)", field = invStatFieldShadow },
        { pattern = "magic%s+:%s+([+-]?%d+)", field = invStatFieldMagic },
        { pattern = "air%s+:%s+([+-]?%d+)", field = invStatFieldAir },
        { pattern = "earth%s+:%s+([+-]?%d+)", field = invStatFieldEarth },
        { pattern = "fire%s+:%s+([+-]?%d+)", field = invStatFieldFire },
        { pattern = "light%s+:%s+([+-]?%d+)", field = invStatFieldLight },
        { pattern = "mental%s+:%s+([+-]?%d+)", field = invStatFieldMental },
        { pattern = "sonic%s+:%s+([+-]?%d+)", field = invStatFieldSonic },
        { pattern = "water%s+:%s+([+-]?%d+)", field = invStatFieldWater },
        { pattern = "poison%s+:%s+([+-]?%d+)", field = invStatFieldPoison },
        { pattern = "disease%s+:%s+([+-]?%d+)", field = invStatFieldDisease },
    }

    for _, rp in ipairs(resistPatterns) do
        local value = lowerTrimmed:match(rp.pattern)
        if value then
            item.stats[rp.field] = toNumber(value)
        end
    end

    ---------------------------------------------------------------------------
    -- STAT EXTRACTION - Using RID's character-by-character method
    ---------------------------------------------------------------------------

    -- Known numeric properties and their field mappings
    local numericProps = {
        -- Basic item properties (NOT additive - set directly)
        ["level"] = { field = invStatFieldLevel, additive = false },
        ["weight"] = { field = invStatFieldWeight, additive = false },
        ["worth"] = { field = invStatFieldWorth, additive = false },
        ["score"] = { field = invStatFieldScore, additive = false },
        -- Weapon properties (NOT additive)
        -- Container properties (NOT additive)
        ["capacity"] = { field = invStatFieldCapacity, additive = false },
        ["holding"] = { field = invStatFieldHolding, additive = false },
        ["items inside"] = { field = invStatFieldItemsInside, additive = false },
        ["tot weight"] = { field = invStatFieldTotWeight, additive = false },
        ["item burden"] = { field = invStatFieldItemBurden, additive = false },
        ["heaviest item"] = { field = invStatFieldHeaviestItem, additive = false },
        ["weight reduction"] = { field = invStatFieldWeightReduction, additive = false },
        -- Stat mods (ADDITIVE - enchants add to base)
        ["hit roll"] = { field = invStatFieldHitroll, additive = true },
        ["damage roll"] = { field = invStatFieldDamroll, additive = true },
        ["strength"] = { field = invStatFieldStr, additive = true },
        ["intelligence"] = { field = invStatFieldInt, additive = true },
        ["wisdom"] = { field = invStatFieldWis, additive = true },
        ["dexterity"] = { field = invStatFieldDex, additive = true },
        ["constitution"] = { field = invStatFieldCon, additive = true },
        ["luck"] = { field = invStatFieldLuck, additive = true },
        ["hit points"] = { field = invStatFieldHp, additive = true },
        ["mana"] = { field = invStatFieldMana, additive = true },
        ["moves"] = { field = invStatFieldMoves, additive = true },
        -- Resists (ADDITIVE)
        ["all physical"] = { field = invStatFieldAllPhys, additive = true },
        ["all magic"] = { field = invStatFieldAllMagic, additive = true },
        ["slash"] = { field = invStatFieldSlash, additive = true },
        ["pierce"] = { field = invStatFieldPierce, additive = true },
        ["bash"] = { field = invStatFieldBash, additive = true },
        ["acid"] = { field = invStatFieldAcid, additive = true },
        ["cold"] = { field = invStatFieldCold, additive = true },
        ["energy"] = { field = invStatFieldEnergy, additive = true },
        ["holy"] = { field = invStatFieldHoly, additive = true },
        ["electric"] = { field = invStatFieldElectric, additive = true },
        ["negative"] = { field = invStatFieldNegative, additive = true },
        ["shadow"] = { field = invStatFieldShadow, additive = true },
        ["magic"] = { field = invStatFieldMagic, additive = true },
        ["air"] = { field = invStatFieldAir, additive = true },
        ["earth"] = { field = invStatFieldEarth, additive = true },
        ["fire"] = { field = invStatFieldFire, additive = true },
        ["light"] = { field = invStatFieldLight, additive = true },
        ["mental"] = { field = invStatFieldMental, additive = true },
        ["sonic"] = { field = invStatFieldSonic, additive = true },
        ["water"] = { field = invStatFieldWater, additive = true },
        ["poison"] = { field = invStatFieldPoison, additive = true },
        ["disease"] = { field = invStatFieldDisease, additive = true },
    }

    -- Find all colons and extract properties
    local i = 1
    while i <= #cleanLine do
        local colonPos = cleanLine:find(":", i)
        if not colonPos then break end

        local propName, propStart = parsePropertyName(cleanLine, colonPos)
        if propName then
            local propLower = propName:lower()
            local propDef = numericProps[propLower]

            if propDef then
                -- Extract numeric value after colon
                local value, endPos = extractNumber(cleanLine, colonPos + 1)
                if value then
                    if propDef.additive then
                        -- Additive: add to existing value (for stat mods, resists)
                        local currentVal = item.stats[propDef.field] or 0
                        item.stats[propDef.field] = currentVal + value
                    else
                        -- Assignment: set directly (for basic properties)
                        item.stats[propDef.field] = value
                    end
                    dbot.debug("  " .. propName:upper() .. " = " .. tostring(item.stats[propDef.field]) .. (propDef.additive and " (additive)" or ""), "inv.items")
                end
            end
        end

        i = colonPos + 1
    end

    ---------------------------------------------------------------------------
    -- WEAPON FIELDS (must come AFTER numericProps loop to not be overwritten)
    ---------------------------------------------------------------------------

    -- Weapon Type: dagger (note: no space before colon in Aardwolf output)
    local weaponType = lowerTrimmed:match("weapon type:%s*(%a+)")
    if weaponType then
        item.stats[invStatFieldWeaponType] = weaponType
        dbot.debug("  WeaponType: " .. weaponType, "inv.items")
    end

    -- Average Dam : 300 (note: space before colon, multiple spaces after)
    -- Use more flexible pattern that handles variable whitespace
    local aveDam = cleanLine:match("Average Dam%s*:%s*(%d+)")
    if not aveDam then
        aveDam = lowerTrimmed:match("average dam%s*:%s*(%d+)")
    end
    if aveDam then
        local newVal = tonumber(aveDam)
        if newVal and newVal > 0 then
            item.stats[invStatFieldAveDam] = newVal
            dbot.debug("  AVEDAM SET: " .. tostring(newVal), "inv.items")
        end
    end

    -- Inflicts : shock
    local inflicts = lowerTrimmed:match("inflicts%s*:%s*(%a+)")
    if inflicts then
        item.stats[invStatFieldInflicts] = inflicts
        dbot.debug("  Inflicts: " .. inflicts, "inv.items")
    end

    -- Damage Type : Electric
    local damType = lowerTrimmed:match("damage type%s*:%s*(%a+)")
    if damType then
        item.stats[invStatFieldDamtype] = damType
        dbot.debug("  DamType: " .. damType, "inv.items")
    end

    -- Specials : flaming
    local specials = lowerTrimmed:match("specials%s*:%s*(%a+)")
    if specials then
        item.stats[invStatFieldSpecials] = specials
        dbot.debug("  Specials: " .. specials, "inv.items")
    end

    ---------------------------------------------------------------------------
    -- CONTINUATION LINES
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    -- ENCHANTS SECTION - Stop all continuations when entering enchants
    ---------------------------------------------------------------------------

    if lowerTrimmed:find("enchants:") or
       lowerTrimmed:find("^|%s*illuminate%s*:") or
       lowerTrimmed:find("^|%s*resonate%s*:") or
       lowerTrimmed:find("^|%s*solidify%s*:") then
        continuationState.name = false
        continuationState.keywords = false
        continuationState.flags = false
        continuationState.affectMods = false
    end

    -- Handle continuation lines: |            : more flags here        |
    local continuation = cleanLine:match("|%s+:%s+(.-)%s*|")
    if continuation then
        if continuationState.flags then
            item.stats[invStatFieldFlags] = (item.stats[invStatFieldFlags] or "") .. " " .. continuation
            if not continuation:match(",%s*$") then
                continuationState.flags = false
            end
        elseif continuationState.affectMods then
            item.stats[invStatFieldAffectMods] = (item.stats[invStatFieldAffectMods] or "") .. " " .. continuation
            item.stats[invStatFieldAffects] = item.stats[invStatFieldAffectMods]
            if not continuation:match(",%s*$") then
                continuationState.affectMods = false
            end
        elseif continuationState.keywords then
            local oldKeywords = item.stats[invStatFieldKeywords] or ""
            if dbot.mergeFields then
                item.stats[invStatFieldKeywords] = dbot.mergeFields(continuation, oldKeywords)
            else
                item.stats[invStatFieldKeywords] = oldKeywords .. " " .. continuation
            end
        elseif continuationState.name then
            item.stats[invStatFieldName] = (item.stats[invStatFieldName] or "") .. " " .. continuation
            local existingColor = item.stats[invStatFieldColorName]
            if existingColor and existingColor ~= "" then
                if dbot.stripColors(existingColor) ~= item.stats[invStatFieldName] then
                    item.stats[invStatFieldColorName] = existingColor .. " " .. continuation
                end
            else
                item.stats[invStatFieldColorName] = item.stats[invStatFieldName]
            end
        end
    end

    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- GMCP Event Handlers
----------------------------------------------------------------------------------------------------

-- These functions are called by Mudlet's GMCP event system

function DINV.onGMCPCharVitals()
    -- Handle vitals updates (hp, mana, moves)
    if dbot and dbot.gmcp then
        -- Update stat bonus tracking if needed
        if inv and inv.statBonus and inv.statBonus.set then
            -- Periodically sample stats
        end
    end
end

function DINV.onGMCPCharStats()
    -- Handle stats updates
    if inv and inv.statBonus and inv.statBonus.set then
        inv.statBonus.set()
    end
end

function DINV.onGMCPCharWorth()
    -- Handle worth updates
end

function DINV.onGMCPRoomInfo()
    -- Handle room info updates
end

function DINV.onGMCPCommChannel()
    -- Handle communication channels (for auction tracking)
    if gmcp and gmcp.comm and gmcp.comm.channel then
        local channel = gmcp.comm.channel
        -- Check if it's an auction message
        if channel.chan == "auction" then
            -- Could be used for covet functionality
        end
    end
end

----------------------------------------------------------------------------------------------------
-- Register GMCP Event Handlers
----------------------------------------------------------------------------------------------------

function DINV.triggers.registerGMCPHandlers()
    if registerAnonymousEventHandler then
        registerAnonymousEventHandler("gmcp.char.vitals", "DINV.onGMCPCharVitals")
        registerAnonymousEventHandler("gmcp.char.stats", "DINV.onGMCPCharStats")
        registerAnonymousEventHandler("gmcp.char.worth", "DINV.onGMCPCharWorth")
        registerAnonymousEventHandler("gmcp.room.info", "DINV.onGMCPRoomInfo")
        registerAnonymousEventHandler("gmcp.comm.channel", "DINV.onGMCPCommChannel")
    end
    
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Initialize triggers
----------------------------------------------------------------------------------------------------

function DINV.triggers.init()
    DINV.triggers.register()
    DINV.triggers.registerGMCPHandlers()
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- End of triggers module
----------------------------------------------------------------------------------------------------

dbot.debug("DINV triggers fix module loaded", "triggers")
dbot.debug("DINV triggers module loaded", "triggers")
