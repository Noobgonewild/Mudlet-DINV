----------------------------------------------------------------------------------------------------
-- DINV Fix: Score Module
-- Complete item and set scoring implementation
----------------------------------------------------------------------------------------------------

-- Defensive initialization: ensure inv.score exists
inv = inv or {}
inv.score = inv.score or {}
inv.score.init = inv.score.init or {}

-- Ensure related modules exist (will be populated later by their files)
inv.set = inv.set or {}
inv.set.table = inv.set.table or {}
inv.items = inv.items or {}
inv.items.table = inv.items.table or {}
inv.priority = inv.priority or {}
inv.statBonus = inv.statBonus or {}
inv.statBonus.equipBonus = inv.statBonus.equipBonus or {}

-- These mappings are shared by every score calculation. Build the field map
-- lazily so lightweight regression harnesses can define DINV field constants
-- after loading their stubs without making module initialization fail.
local invScoreStatMapping = nil
local invScoreCappedStats = { str = true, int = true, wis = true, dex = true, con = true, luck = true }
local invScoreMaxStatList = { "int", "wis", "luck", "str", "dex", "con" }

local function invScoreGetStatMapping()
    if invScoreStatMapping ~= nil then
        return invScoreStatMapping
    end

    local mapping = {
        str = "str",
        int = "int",
        wis = "wis",
        dex = "dex",
        con = "con",
        luck = "luck",
        hit = "hit",
        dam = "dam",
        hitroll = "hit",
        damroll = "dam",
        hp = "hp",
        mana = "mana",
        moves = "moves",
        allphys = "allphys",
        allmagic = "allmagic",
        offhandDam = "offhandDam",
    }

    local function add(fieldName, priorityKey)
        if fieldName ~= nil then
            mapping[fieldName] = priorityKey
        end
    end

    add(invStatFieldStr, "str")
    add(invStatFieldInt, "int")
    add(invStatFieldWis, "wis")
    add(invStatFieldDex, "dex")
    add(invStatFieldCon, "con")
    add(invStatFieldLuck, "luck")
    add(invStatFieldHitroll, "hit")
    add(invStatFieldDamroll, "dam")
    add(invStatFieldHp, "hp")
    add(invStatFieldMana, "mana")
    add(invStatFieldMoves, "moves")
    add(invStatFieldAllPhys, "allphys")
    add(invStatFieldAllMagic, "allmagic")

    invScoreStatMapping = mapping
    return invScoreStatMapping
end

local function invScoreFormatEffectAccess(access)
    if not access then return "available without equipment" end
    if access.source == "race" then
        return "race:" .. tostring(access.race or "unknown")
    end
    if access.source == "superhero" then
        return string.format(
            "superhero wearableLevel:%d threshold:%d",
            tonumber(access.wearableLevel) or 0,
            tonumber(access.threshold) or 0
        )
    end
    return string.format(
        "class:%s ability:%s wearableLevel:%d threshold:%d",
        tostring(access.className or "Unknown"),
        tostring(access.ability or access.effect or "unknown"),
        tonumber(access.wearableLevel) or 0,
        tonumber(access.threshold) or 0
    )
end

local function invScoreShouldSkipEffect(effectName, level)
    if dbot and dbot.ability and dbot.ability.getEffectAccess then
        local available, access = dbot.ability.getEffectAccess(effectName, level)
        if available then
            return true, invScoreFormatEffectAccess(access)
        end
    end
    return false, ""
end

local function invScoreShouldSkipFlyingEffect(level)
    return invScoreShouldSkipEffect("flying", level)
end

function inv.score.getFlyingSkipReason(level)
    local shouldSkip, reason = invScoreShouldSkipFlyingEffect(level)
    if shouldSkip then
        return reason
    end
    return nil
end

local function invScoreShouldSkipDualWieldEffect(level)
    return invScoreShouldSkipEffect("dualwield", level)
end

function inv.score.getDualWieldSkipReason(level)
    local shouldSkip, reason = invScoreShouldSkipDualWieldEffect(level)
    if shouldSkip then
        return reason
    end
    return nil
end

function inv.score.getSanctuarySkipReason(level)
    local shouldSkip, reason = invScoreShouldSkipEffect("sanctuary", level)
    if shouldSkip then
        return reason
    end
    return nil
end

function inv.score.getEffectSkipReason(effectName, level)
    local shouldSkip, reason = invScoreShouldSkipEffect(effectName, level)
    if shouldSkip then
        return reason
    end
    return nil
end

----------------------------------------------------------------------------------------------------
-- Resolve level-stable scoring inputs once and reuse them across all handicap passes
----------------------------------------------------------------------------------------------------

function inv.score.createContext(priorityName, level)
    if priorityName == nil or priorityName == "" then
        return nil, DRL_RET_INVALID_PARAM
    end

    level = tonumber(level) or (dbot.gmcp and dbot.gmcp.getLevel and dbot.gmcp.getLevel()) or 1
    if not inv.priority or not inv.priority.get then
        return nil, DRL_RET_UNINITIALIZED
    end

    local priority = inv.priority.get(priorityName, level)
    if priority == nil then
        return nil, DRL_RET_MISSING_ENTRY
    end

    local equipCapDefault = 200
    if inv.statBonus and inv.statBonus.getEquipmentCap then
        equipCapDefault = inv.statBonus.getEquipmentCap(level)
    end

    local equipCapByStat = inv.statBonus and inv.statBonus.equipBonus
        and inv.statBonus.equipBonus[level] or nil
    if equipCapByStat == nil and inv.statBonus and inv.statBonus.get then
        local bonusType = invStatBonusTypeAve
        if level == (dbot.gmcp and dbot.gmcp.getLevel and dbot.gmcp.getLevel()) then
            bonusType = invStatBonusTypeCurrent
        end
        inv.statBonus.get(level, bonusType)
        equipCapByStat = inv.statBonus.equipBonus and inv.statBonus.equipBonus[level] or nil
    end

    local context = {
        priorityName = priorityName,
        level = level,
        priority = priority,
        equipCapDefault = equipCapDefault,
        equipCapByStat = equipCapByStat,
        weights = {},
        effectEntries = {},
    }

    local weightKeys = { avedam = true, offhandDam = true }
    for _, priorityKey in pairs(invScoreGetStatMapping()) do
        weightKeys[priorityKey] = true
    end
    for _, stat in ipairs(invScoreMaxStatList) do
        weightKeys["max" .. stat] = true
    end

    for priorityKey in pairs(weightKeys) do
        context.weights[priorityKey] = inv.score.getWeight(priority, priorityKey, level)
    end

    for effectName in pairs(priority.effects or {}) do
        local weight = inv.score.getWeight(priority, effectName, level)
        context.weights[effectName] = weight
        table.insert(context.effectEntries, { name = effectName, weight = weight })
    end

    return context, DRL_RET_SUCCESS
end

local function invScoreCalculateComponents(itemStats, context, handicap, normalizedEffectText)
    local basicScore = 0
    handicap = handicap or {}

    for statField, priorityKey in pairs(invScoreGetStatMapping()) do
        local statValue = tonumber(itemStats[statField]) or 0
        if statValue ~= 0 then
            local effectiveValue = statValue
            if invScoreCappedStats[priorityKey] then
                local statCap = context.equipCapDefault
                if context.equipCapByStat and context.equipCapByStat[priorityKey] ~= nil then
                    statCap = context.equipCapByStat[priorityKey]
                end
                effectiveValue = math.min(effectiveValue, statCap)
            end
            effectiveValue = math.max(0, effectiveValue - (handicap[priorityKey] or 0))
            basicScore = basicScore + (effectiveValue * (context.weights[priorityKey] or 0))
        end
    end

    local effectScore = 0
    if #context.effectEntries > 0 then
        local combined = normalizedEffectText
        if combined == nil then
            combined = inv.items.getEffectTextFromStats(itemStats)
        end
        for _, effectEntry in ipairs(context.effectEntries) do
            if effectEntry.weight > 0 and inv.items.effectTextHas(combined, effectEntry.name) then
                effectScore = effectScore + effectEntry.weight
                dbot.debug("  Effect '" .. effectEntry.name .. "' adds " .. effectEntry.weight .. " to score", "inv.score")
            end
        end
    end

    local maxStatScore = 0
    for _, stat in ipairs(invScoreMaxStatList) do
        local maxWeight = context.weights["max" .. stat] or 0
        if maxWeight > 0 and context.equipCapByStat then
            local maxAllowed = context.equipCapByStat[stat] or 999
            if (tonumber(itemStats[stat]) or 0) >= maxAllowed then
                maxStatScore = maxStatScore + maxWeight
                dbot.debug("  Max " .. stat .. " bonus adds " .. maxWeight .. " to score", "inv.score")
            end
        end
    end

    local aveDam = tonumber(itemStats[invStatFieldAveDam]) or tonumber(itemStats.avedam) or 0
    return basicScore, effectScore, maxStatScore, aveDam
end

local function invScoreRound(score)
    return tonumber(string.format("%.2f", score)) or 0
end

function inv.score.extendedWithContext(itemStats, context, handicap, isOffhand, normalizedEffectText)
    if itemStats == nil or type(context) ~= "table" or context.priority == nil then
        return 0, DRL_RET_INVALID_PARAM
    end

    local basicScore, effectScore, maxStatScore, aveDam =
        invScoreCalculateComponents(itemStats, context, handicap, normalizedEffectText)
    local damageKey = isOffhand and "offhandDam" or "avedam"
    local damageScore = aveDam > 0 and (aveDam * (context.weights[damageKey] or 0)) or 0
    local score = basicScore + damageScore + effectScore + maxStatScore
    return invScoreRound(score), DRL_RET_SUCCESS
end

function inv.score.itemWithContext(objId, context, handicap, normalizedEffectText)
    objId = tonumber(objId)
    if objId == nil then
        return 0, 0, DRL_RET_INVALID_PARAM
    end
    if type(context) ~= "table" or context.priority == nil then
        return 0, 0, DRL_RET_INVALID_PARAM
    end
    if not inv.items or not inv.items.getItem then
        return 0, 0, DRL_RET_UNINITIALIZED
    end

    local item = inv.items.getItem(objId)
    if item == nil then
        return 0, 0, DRL_RET_MISSING_ENTRY
    end

    local itemStats = item.stats or {}
    local basicScore, effectScore, maxStatScore, aveDam =
        invScoreCalculateComponents(itemStats, context, handicap, normalizedEffectText)
    local primaryScore = invScoreRound(
        basicScore + (aveDam > 0 and aveDam * (context.weights.avedam or 0) or 0)
            + effectScore + maxStatScore
    )

    local wearable = ""
    local typeNum = 0
    local typeName = ""
    if inv.items.getStatField then
        wearable = tostring(inv.items.getStatField(objId, invStatFieldWearable) or "")
        typeNum = tonumber(inv.items.getStatField(objId, invStatFieldTypeNum)) or 0
        typeName = tostring(inv.items.getStatField(objId, invStatFieldType) or "")
    end
    local weaponTypeId = (inv.items.typeId and inv.items.typeId["Weapon"]) or 5
    local isWeapon = typeNum == weaponTypeId or typeName == "Weapon" or wearable:lower():find("wield") ~= nil
    local offhandScore = 0
    if isWeapon then
        offhandScore = invScoreRound(
            basicScore + (aveDam > 0 and aveDam * (context.weights.offhandDam or 0) or 0)
                + effectScore + maxStatScore
        )
    end

    return primaryScore, offhandScore, DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Score an individual item based on priority
----------------------------------------------------------------------------------------------------

function inv.score.item(objId, priorityName, handicap, level)
    local score = 0
    local offhandScore = 0

    objId = tonumber(objId)
    if objId == nil then
        dbot.warn("inv.score.item: Invalid objId")
        return 0, 0, DRL_RET_INVALID_PARAM
    end

    if priorityName == nil or priorityName == "" then
        dbot.warn("inv.score.item: Missing priorityName")
        return 0, 0, DRL_RET_INVALID_PARAM
    end

    -- Defensive check: ensure inv.items exists and has a getItem function
    if not inv.items or not inv.items.getItem then
        dbot.warn("inv.score.item: inv.items module not loaded")
        return 0, 0, DRL_RET_UNINITIALIZED
    end

    level = tonumber(level) or (dbot.gmcp and dbot.gmcp.getLevel and dbot.gmcp.getLevel()) or 1
    local context, retval = inv.score.createContext(priorityName, level)
    if context == nil then
        return score, offhandScore, retval
    end
    return inv.score.itemWithContext(objId, context, handicap)
end

----------------------------------------------------------------------------------------------------
-- Extended scoring function
----------------------------------------------------------------------------------------------------

function inv.score.extended(itemStats, priorityName, handicap, level, isOffhand)
    if itemStats == nil then
        return 0, DRL_RET_INVALID_PARAM
    end

    if priorityName == nil or priorityName == "" then
        return 0, DRL_RET_INVALID_PARAM
    end

    level = tonumber(level) or (dbot.gmcp and dbot.gmcp.getLevel and dbot.gmcp.getLevel()) or 1

    local context, retval = inv.score.createContext(priorityName, level)
    if context == nil then
        return 0, retval
    end
    return inv.score.extendedWithContext(itemStats, context, handicap, isOffhand)
end

----------------------------------------------------------------------------------------------------
-- Get weight from priority for a stat at a level
----------------------------------------------------------------------------------------------------

function inv.score.getWeight(priority, statName, level)
    if priority == nil or statName == nil then
        return 0
    end

    -- Check if stat is in effects
    local data = priority[statName]
    if data == nil and priority.effects then
        data = priority.effects[statName]
    end

    if data == nil then
        return 0
    end

    local weight = inv.score.getWeightFromData(data, level)
    local isEffect = priority.effects and priority.effects[statName] ~= nil
    if isEffect and weight ~= 0 then
        local shouldSkip, reason = invScoreShouldSkipEffect(statName, level)
        if shouldSkip then
            dbot.debug(
                string.format("  Effect '%s' weight set to 0 (%s)", tostring(statName), tostring(reason)),
                "inv.score"
            )
            return 0
        end
    end
    return weight
end

function inv.score.getWeightFromData(data, level)
    if data == nil then
        return 0
    end

    -- Simple number
    if type(data) == "number" then
        return data
    end

    -- Table with levels array
    if type(data) == "table" then
        -- Check level-specific weights
        if data.levels and #data.levels > 0 then
            for _, levelData in ipairs(data.levels) do
                if level >= (levelData.min or 0) and level <= (levelData.max or 999) then
                    return levelData.weight or data.weight or 0
                end
            end
        end

        -- Fall back to default weight
        return data.weight or 0
    end

    return 0
end

----------------------------------------------------------------------------------------------------
-- Score a complete equipment set
----------------------------------------------------------------------------------------------------

function inv.score.setStats(setStats, priorityName, level, context)
    if setStats == nil then
        return 0, nil, DRL_RET_INVALID_PARAM
    end
    if priorityName == nil or priorityName == "" then
        return 0, setStats, DRL_RET_INVALID_PARAM
    end

    level = tonumber(level) or (dbot.gmcp.getLevel and dbot.gmcp.getLevel()) or 1
    if type(context) ~= "table" or context.priorityName ~= priorityName or context.level ~= level then
        context = inv.score.createContext(priorityName, level)
    end
    if context == nil then
        return 0, setStats, DRL_RET_MISSING_ENTRY
    end

    local setScore, retval = inv.score.extendedWithContext(setStats, context, nil, false)
    return setScore, setStats, retval
end

function inv.score.set(equipSet, priorityName, level, context, candidateIndex)
    if equipSet == nil then
        return 0, nil, DRL_RET_INVALID_PARAM
    end

    if priorityName == nil or priorityName == "" then
        return 0, nil, DRL_RET_INVALID_PARAM
    end

    level = tonumber(level) or (dbot.gmcp.getLevel and dbot.gmcp.getLevel()) or 1

    -- Get combined stats from all items in set
    local setStats = inv.set.getStats(equipSet, level, nil, candidateIndex)
    setStats.name = "Set for level " .. level .. " " .. priorityName
    return inv.score.setStats(setStats, priorityName, level, context)
end

----------------------------------------------------------------------------------------------------
-- Quick score function for item comparison
----------------------------------------------------------------------------------------------------

function inv.score.getItemScore(objId, priorityName, level)
    local score, _, _ = inv.score.item(objId, priorityName, nil, level)
    return score
end

function inv.score.getItemScoreForLoc(objId, priorityName, level, loc)
    local primaryScore, offhandScore = inv.score.item(objId, priorityName, nil, level)
    if tostring(loc or "") == "second" then
        return offhandScore or 0
    end
    return primaryScore or 0
end

function inv.score.getSetScore(itemIds, priorityName, level)
    local totalScore = 0

    if itemIds == nil then
        return 0
    end

    -- Handle both array and table formats
    if #itemIds > 0 then
        for _, objId in ipairs(itemIds) do
            totalScore = totalScore + inv.score.getItemScore(objId, priorityName, level)
        end
    else
        for _, objId in pairs(itemIds) do
            if type(objId) == "number" or tonumber(objId) then
                totalScore = totalScore + inv.score.getItemScore(tonumber(objId), priorityName, level)
            end
        end
    end

    return totalScore
end

dbot.debug("inv.score fix module loaded", "inv.score")
