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

    local item = inv.items.getItem(objId)
    if item == nil then
        return 0, 0, DRL_RET_MISSING_ENTRY
    end

    level = tonumber(level) or (dbot.gmcp and dbot.gmcp.getLevel and dbot.gmcp.getLevel()) or 1

    -- Get primary score
    score = inv.score.extended(item.stats or {}, priorityName, handicap, level, false)

    -- Get offhand score for weapons
    local wearable = ""
    local typeNum = 0
    local typeName = ""
    if inv.items.getStatField then
        wearable = inv.items.getStatField(objId, invStatFieldWearable) or ""
        typeNum = tonumber(inv.items.getStatField(objId, invStatFieldTypeNum)) or 0
        typeName = inv.items.getStatField(objId, invStatFieldType) or ""
    end
    local weaponTypeId = (inv.items.typeId and inv.items.typeId["Weapon"]) or 5
    local isWeaponType = (typeNum == weaponTypeId) or (typeName == "Weapon")
    if isWeaponType or wearable:lower():find("wield") then
        offhandScore = inv.score.extended(item.stats or {}, priorityName, handicap, level, true)
    end

    return score, offhandScore, DRL_RET_SUCCESS
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

    -- Defensive check: ensure inv.priority exists
    if not inv.priority or not inv.priority.get then
        dbot.warn("inv.score.extended: inv.priority module not loaded")
        return 0, DRL_RET_UNINITIALIZED
    end

    -- Get priority weights for this level
    local priority = inv.priority.get(priorityName, level)
    if priority == nil then
        -- Priority might not exist - return 0 score instead of error
        dbot.debug("inv.score.extended: Priority '" .. priorityName .. "' not found", "inv.score")
        return 0, DRL_RET_MISSING_ENTRY
    end

    local score = 0
    handicap = handicap or {}

    -- Score basic stats
    local statMapping = {
        [invStatFieldStr] = "str",
        [invStatFieldInt] = "int",
        [invStatFieldWis] = "wis",
        [invStatFieldDex] = "dex",
        [invStatFieldCon] = "con",
        [invStatFieldLuck] = "luck",
        [invStatFieldHitroll] = "hit",
        [invStatFieldDamroll] = "dam",
        [invStatFieldHp] = "hp",
        [invStatFieldMana] = "mana",
        [invStatFieldMoves] = "moves",
        [invStatFieldAllPhys] = "allphys",
        [invStatFieldAllMagic] = "allmagic",
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

    -- Calculate stat contribution with equipment cap per stat
    local equipCapDefault = 200
    if inv.statBonus and inv.statBonus.getEquipmentCap then
        equipCapDefault = inv.statBonus.getEquipmentCap(level)
    end
    local equipCapByStat = nil
    if inv.statBonus and inv.statBonus.equipBonus then
        equipCapByStat = inv.statBonus.equipBonus[level]
    end
    if equipCapByStat == nil and inv.statBonus and inv.statBonus.get then
        local bonusType = invStatBonusTypeAve
        if level == (dbot.gmcp and dbot.gmcp.getLevel and dbot.gmcp.getLevel()) then
            bonusType = invStatBonusTypeCurrent
        end
        inv.statBonus.get(level, bonusType)
        if inv.statBonus.equipBonus then
            equipCapByStat = inv.statBonus.equipBonus[level]
        end
    end
    local cappedStats = { str = true, int = true, wis = true, dex = true, con = true, luck = true }

    for statField, priorityKey in pairs(statMapping) do
        local statValue = tonumber(itemStats[statField]) or 0
        if statValue ~= 0 then
            local weight = inv.score.getWeight(priority, priorityKey, level)
            local handicapValue = handicap[priorityKey] or 0

            -- Apply equipment cap per stat, then handicap (reduces effective stat value)
            local effectiveValue = statValue
            if cappedStats[priorityKey] then
                local statCap = equipCapDefault
                if equipCapByStat and equipCapByStat[priorityKey] ~= nil then
                    statCap = equipCapByStat[priorityKey]
                end
                effectiveValue = math.min(effectiveValue, statCap)
            end
            effectiveValue = math.max(0, effectiveValue - handicapValue)
            score = score + (effectiveValue * weight)
        end
    end

    -- Score weapon damage
    local aveDam = tonumber(itemStats[invStatFieldAveDam]) or tonumber(itemStats.avedam) or 0
    if aveDam > 0 then
        local damKey = isOffhand and "offhandDam" or "avedam"
        local weight = inv.score.getWeight(priority, damKey, level)
        score = score + (aveDam * weight)
    end

    -- Score effects from priority.effects
    if priority.effects then
        local combined = inv.items.getEffectTextFromStats(itemStats)

        for effectName in pairs(priority.effects) do
            local weight = inv.score.getWeight(priority, effectName, level)

            if weight > 0 and inv.items.effectTextHas(combined, effectName) then
                score = score + weight
                dbot.debug("  Effect '" .. effectName .. "' adds " .. weight .. " to score", "inv.score")
            end
        end
    end

    -- Check for max stat bonuses
    local maxStatList = { "int", "wis", "luck", "str", "dex", "con" }
    for _, stat in ipairs(maxStatList) do
        local maxKey = "max" .. stat
        local maxWeight = inv.score.getWeight(priority, maxKey, level)

        if maxWeight > 0 then
            -- Check if we have equipment bonus tracking
            if inv.statBonus and inv.statBonus.equipBonus and inv.statBonus.equipBonus[level] then
                local maxAllowed = inv.statBonus.equipBonus[level][stat] or 999
                local statValue = tonumber(itemStats[stat]) or 0

                if statValue >= maxAllowed then
                    score = score + maxWeight
                    dbot.debug("  Max " .. stat .. " bonus adds " .. maxWeight .. " to score", "inv.score")
                end
            end
        end
    end

    -- Round to 2 decimal places
    score = tonumber(string.format("%.2f", score)) or 0

    return score, DRL_RET_SUCCESS
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

function inv.score.set(equipSet, priorityName, level)
    if equipSet == nil then
        return 0, nil, DRL_RET_INVALID_PARAM
    end

    if priorityName == nil or priorityName == "" then
        return 0, nil, DRL_RET_INVALID_PARAM
    end

    level = tonumber(level) or (dbot.gmcp.getLevel and dbot.gmcp.getLevel()) or 1

    -- Get combined stats from all items in set
    local setStats = inv.set.getStats(equipSet, level)
    setStats.name = "Set for level " .. level .. " " .. priorityName

    -- Score the combined stats
    local setScore, retval = inv.score.extended(setStats, priorityName, nil, level, false)

    return setScore, setStats, retval
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
