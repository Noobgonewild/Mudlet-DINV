----------------------------------------------------------------------------------------------------
-- INV Set Module
-- Equipment set generation and wearing
----------------------------------------------------------------------------------------------------

-- Defensive initialization
inv = inv or {}
inv.set = inv.set or {}
inv.set.init = inv.set.init or {}
inv.set.table = inv.set.table or {}
inv.set.stateName = inv.set.stateName or "inv-set.state"
inv.set.createPkg = nil
inv.set.displayPkg = nil
inv.set.createAndWearPkg = nil
inv.set.analyzeIntensity = inv.set.analyzeIntensity or 8
inv.set.createIntensity = inv.set.createIntensity or 16

function inv.set.init.atInstall()
    return DRL_RET_SUCCESS
end

function inv.set.init.atActive()
    local retval = inv.set.load()
    if retval ~= DRL_RET_SUCCESS then
        dbot.debug("inv.set.init.atActive: Using fresh set table", "inv.set")
    end
    return DRL_RET_SUCCESS
end

function inv.set.fini(doSaveState)
    if doSaveState then
        inv.set.save()
    end
    return DRL_RET_SUCCESS
end

function inv.set.save()
    if inv.set.table == nil then
        return inv.set.reset()
    end
    return DINV.database.saveModuleTable("set", inv.set.table)
end

function inv.set.load()
    local value, retval = DINV.database.loadModuleTable("set", inv.set.reset)
    if value then inv.set.table = value end
    return retval
end

function inv.set.reset()
    inv.set.table = {}
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Wearable Locations
----------------------------------------------------------------------------------------------------

inv.set.wearableLocations = {
    "light", "head", "eyes", "lear", "rear", "neck1", "neck2", "back",
    "medal1", "medal2", "medal3", "medal4", "torso", "body", "waist",
    "arms", "lwrist", "rwrist", "hands", "lfinger", "rfinger", "legs", "feet",
    "shield", "wielded", "second", "hold", "float", "above", "portal", "sleeping"
}

inv.set.wearLocMap = {
    light = "light", head = "head", eyes = "eyes",
    ["left ear"] = "lear", ["right ear"] = "rear", lear = "lear", rear = "rear",
    neck = "neck1", ["neck1"] = "neck1", ["neck2"] = "neck2",
    back = "back",
    medal = "medal1", ["medal1"] = "medal1", ["medal2"] = "medal2", ["medal3"] = "medal3", ["medal4"] = "medal4",
    torso = "torso", body = "body", waist = "waist",
    arms = "arms",
    ["left wrist"] = "lwrist", ["right wrist"] = "rwrist", lwrist = "lwrist", rwrist = "rwrist",
    hands = "hands",
    ["left finger"] = "lfinger", ["right finger"] = "rfinger", lfinger = "lfinger", rfinger = "rfinger",
    legs = "legs", feet = "feet",
    shield = "shield",
    wield = "wielded", wielded = "wielded", ["second wield"] = "second", second = "second",
    hold = "hold", float = "float", above = "above", portal = "portal", sleeping = "sleeping",
}

-- Build the structural part of the equipment candidate search once, then
-- reuse it across levels and handicap passes. Scoring and level-dependent
-- eligibility deliberately remain in createWithHandicap().
function inv.set.buildCandidateIndex()
    local candidateIndex = {
        allItems = {},
        byId = {},
        byLocation = {},
        locationMembership = {},
        weapons = {},
        sourceTable = inv.items and inv.items.table or nil,
        eventSequence = tonumber(inv.items and inv.items.eventSequence) or 0,
    }

    for _, loc in ipairs(inv.set.wearableLocations or {}) do
        if loc ~= "wielded" and loc ~= "second" then
            candidateIndex.byLocation[loc] = {}
        end
    end

    local weaponTypeId = (inv.items and inv.items.typeId and inv.items.typeId["Weapon"]) or 5
    for objId, item in pairs(inv.items and inv.items.table or {}) do
        local record = { id = objId, item = item, effectMatches = {} }
        if inv.items.getEffectTextFromStats then
            record.effectText = inv.items.getEffectTextFromStats(item.stats or item)
        end
        table.insert(candidateIndex.allItems, record)
        candidateIndex.byId[tostring(objId)] = record

        local wearable = inv.items.getStatField(objId, invStatFieldWearable) or ""
        local memberships = {}
        candidateIndex.locationMembership[objId] = memberships

        for _, loc in ipairs(inv.set.wearableLocations or {}) do
            if loc ~= "wielded" and loc ~= "second"
                and inv.set.canWearAt(wearable, loc) then
                memberships[loc] = true
                table.insert(candidateIndex.byLocation[loc], record)
            end
        end

        local typeNum = tonumber(inv.items.getStatField(objId, invStatFieldTypeNum)) or 0
        local typeName = inv.items.getStatField(objId, invStatFieldType) or ""
        local isWeaponType = (typeNum == weaponTypeId) or (typeName == "Weapon")
        if inv.set.canWearAt(wearable, "wielded") or isWeaponType then
            table.insert(candidateIndex.weapons, record)
        end
    end

    return candidateIndex
end

function inv.set.isCandidateIndexCurrent(candidateIndex)
    if type(candidateIndex) ~= "table" then
        return false
    end
    if candidateIndex.sourceTable ~= (inv.items and inv.items.table or nil) then
        return false
    end
    return (tonumber(candidateIndex.eventSequence) or 0)
        == (tonumber(inv.items and inv.items.eventSequence) or 0)
end

function inv.set.ensureCandidateIndex(candidateIndex)
    if inv.set.isCandidateIndexCurrent(candidateIndex) then
        return candidateIndex
    end
    return inv.set.buildCandidateIndex()
end

local function itemHasEffect(objId, effectName)
    return inv.items.hasEffect and inv.items.hasEffect(objId, effectName) or false
end

local function candidateHasEffect(record, effectName)
    if record and record.effectText ~= nil and inv.items.effectTextHas then
        local effectKey = string.lower(tostring(effectName or "")) or ""
        local cached = record.effectMatches and record.effectMatches[effectKey] or nil
        if cached ~= nil then
            return cached
        end
        local hasEffect = inv.items.effectTextHas(record.effectText, effectName)
        record.effectMatches = record.effectMatches or {}
        record.effectMatches[effectKey] = hasEffect
        return hasEffect
    end
    return record and itemHasEffect(record.id, effectName) or false
end

local function itemIsHeroOnly(objId)
    local flags = tostring(inv.items.getStatField(objId, invStatFieldFlags) or "")

    for token in flags:gmatch("%S+") do
        local cleaned = token:gsub(",", ""):lower()
        if cleaned == "heroonly" then
            return true
        end
    end

    return false
end

----------------------------------------------------------------------------------------------------
-- Create Equipment Set (Complete Rewrite)
-- Properly implements weapon weight rules and dual wield vs single weapon + shield + hold comparison
----------------------------------------------------------------------------------------------------

local function invSetResolveTargetLevel(level)
    return tonumber(level)
        or (dbot.gmcp.getWearableLevel and tonumber(dbot.gmcp.getWearableLevel()))
        or (dbot.gmcp.getLevel and tonumber(dbot.gmcp.getLevel()))
        or 1
end

local function invSetResolveBaseLevel(targetLevel)
    local tier = (dbot.gmcp and dbot.gmcp.getTier and tonumber(dbot.gmcp.getTier())) or 0
    local projectedBase = (tonumber(targetLevel) or invSetResolveTargetLevel(nil)) - (tier * 10)
    return math.max(1, math.min(201, projectedBase))
end

function inv.set.create(priorityName, level, synchronous, intensity, isQuiet, baseLevelOverride, options)
    if priorityName == nil or priorityName == "" then
        dbot.warn("inv.set.create: Missing priority name")
        return DRL_RET_INVALID_PARAM
    end

    if not inv.priority.exists(priorityName) then
        dbot.warn("Priority '" .. priorityName .. "' does not exist")
        return DRL_RET_MISSING_ENTRY
    end

    local targetLevel = invSetResolveTargetLevel(level)

    if inv.score and inv.score.getFlyingSkipReason then
        local flyingSkipReason = inv.score.getFlyingSkipReason(targetLevel)
        if flyingSkipReason then
            dbot.debug(
                string.format("Flying priority override active for level %d (%s)", tonumber(targetLevel) or 0, flyingSkipReason),
                "inv.set"
            )
        end
    end

    if inv.score and inv.score.getDualWieldSkipReason then
        local dualWieldSkipReason = inv.score.getDualWieldSkipReason(targetLevel)
        if dualWieldSkipReason then
            dbot.debug(
                string.format("Dual wield priority override active for level %d (%s)", tonumber(targetLevel) or 0, dualWieldSkipReason),
                "inv.set"
            )
        end
    end

    if inv.score and inv.score.getSanctuarySkipReason then
        local sanctuarySkipReason = inv.score.getSanctuarySkipReason(targetLevel)
        if sanctuarySkipReason then
            dbot.debug(
                string.format("Sanctuary priority override active for level %d (%s)", tonumber(targetLevel) or 0, sanctuarySkipReason),
                "inv.set"
            )
        end
    end

    local baseLevel
    if baseLevelOverride ~= nil then
        baseLevel = tonumber(baseLevelOverride) or 1
    else
        local tier = (dbot.gmcp and dbot.gmcp.getTier and tonumber(dbot.gmcp.getTier())) or 0
        local projectedBase = targetLevel - (tier * 10)
        projectedBase = math.max(1, math.min(201, projectedBase))
        baseLevel = projectedBase
    end

    if not isQuiet then
        dbot.info("Creating equipment set for priority @Y'" .. priorityName .. "'@W at level @G" .. targetLevel .. "@W")
    end

    if inv.set.table[priorityName] == nil then
        inv.set.table[priorityName] = {}
    end

    local bonusType = invStatBonusTypeAve
    if targetLevel == invSetResolveTargetLevel(nil) then
        bonusType = invStatBonusTypeCurrent
    end

    local statDelta = nil
    if inv.statBonus and inv.statBonus.get then
        statDelta = inv.statBonus.get(targetLevel, bonusType)
    end

    options = options or {}
    local candidateIndex = inv.set.ensureCandidateIndex(options.candidateIndex)
    local scoreContext = inv.score.createContext and inv.score.createContext(priorityName, targetLevel) or nil
    local createIntensity = intensity or inv.set.createIntensity or 1
    local handicap = { int = 0, wis = 0, luck = 0, str = 0, dex = 0, con = 0 }
    local handicapDelta = 1 / math.max(1, createIntensity)

    local bestScore = -999999
    local bestEquipment = nil
    local bestStats = nil

    for iteration = 1, createIntensity do
        local equipment, rawStats, score = inv.set.createWithHandicap(
            priorityName,
            targetLevel,
            baseLevel,
            handicap,
            iteration == 1,
            nil,
            candidateIndex,
            scoreContext
        )

        if score > bestScore then
            bestScore = score
            bestEquipment = equipment
            bestStats = rawStats
        end

        local overstat = false
        if statDelta and rawStats then
            for statName, delta in pairs(statDelta) do
                if rawStats[statName] ~= nil and delta ~= nil then
                    if tonumber(rawStats[statName]) > tonumber(delta) then
                        handicap[statName] = handicap[statName] + handicapDelta
                        overstat = true
                    end
                end
            end
        end

        if not overstat then
            break
        end
    end

    local equipment = bestEquipment or {}

    ---------------------------------------------------------------------------
    -- PHASE 7: Calculate total set score
    ---------------------------------------------------------------------------

    local totalScore = bestScore
    if totalScore == -999999 and equipment then
        local setScore = inv.score.set(equipment, priorityName, targetLevel, scoreContext, candidateIndex)
        totalScore = setScore or 0
    end

    ---------------------------------------------------------------------------
    -- PHASE 8: Save the set
    ---------------------------------------------------------------------------

    local itemNames = {}
    for loc, objId in pairs(equipment) do
        local itemName = inv.items and inv.items.getStatField
            and inv.items.getStatField(objId, invStatFieldName) or nil
        if itemName ~= nil and tostring(itemName) ~= "" then
            itemNames[loc] = tostring(itemName)
        end
    end

    inv.set.table[priorityName][tostring(targetLevel)] = {
        equipment = equipment,
        itemNames = itemNames,
        score = totalScore,
        level = targetLevel,
        created = os.time(),
        context = inv.context and inv.context.capture and inv.context.capture() or nil,
    }

    if options.persist ~= false then
        inv.set.save()
    end

    if not isQuiet then
        dbot.info("Equipment set created with score: @G" .. string.format("%.2f", totalScore) .. "@W")
    end

    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Create equipment set with stat handicap to avoid overmaxing
----------------------------------------------------------------------------------------------------

function inv.set.createWithHandicap(priorityName, targetLevel, baseLevel, handicap, debugEnabled, excludedItems,
                                    candidateIndex, scoreContext)
    candidateIndex = inv.set.ensureCandidateIndex(candidateIndex)
    local equipment = {}
    local usedItems = {}
    local weaponArray = {}
    local forcedLocations = {}
    local function debug(message)
        if debugEnabled then
            dbot.debug(message, "inv.set")
        end
    end

    local scoreCache = {}
    local function scoreItemPair(objId, record)
        local cacheKey = tostring(objId)
        local cached = scoreCache[cacheKey]
        if cached then
            return cached.primary, cached.offhand
        end

        local primaryScore, offhandScore
        if scoreContext and inv.score.itemWithContext then
            primaryScore, offhandScore = inv.score.itemWithContext(
                objId,
                scoreContext,
                handicap,
                record and record.effectText or nil
            )
        else
            primaryScore, offhandScore = inv.score.item(objId, priorityName, handicap, targetLevel)
        end
        cached = {
            primary = primaryScore or 0,
            offhand = offhandScore or 0,
        }
        scoreCache[cacheKey] = cached
        return cached.primary, cached.offhand
    end

    local function scoreItem(objId, record)
        local score = scoreItemPair(objId, record)
        return score or 0
    end

    local function isExcluded(objId)
        if not excludedItems then
            return false
        end
        return excludedItems[objId] == true
            or excludedItems[tostring(objId)] == true
            or (tonumber(objId) ~= nil and excludedItems[tonumber(objId)] == true)
    end

    local function hasHeroOnlyFlag(objId)
        return itemIsHeroOnly(objId)
    end

    local function heroOnlyOk(objId)
        if not hasHeroOnlyFlag(objId) then
            return true
        end

        local base = tonumber(baseLevel) or 0
        return base == 200 or base == 201
    end

    local priority = inv.priority.get and inv.priority.get(priorityName, targetLevel) or nil
    local forcedEffects = inv.priority.getForcedEffects
        and inv.priority.getForcedEffects(priority, targetLevel) or {}
    local forcedEffectSet = {}
    for _, effectName in ipairs(forcedEffects) do
        forcedEffectSet[effectName] = true
    end

    local function forcedCandidateEligible(objId, item, loc)
        if isExcluded(objId) then return false end
        if usedItems[objId] then return false end
        if inv.items.isKeyringItem and inv.items.isKeyringItem(item) then return false end

        local memberships = candidateIndex.locationMembership[objId] or {}
        if not memberships[loc] then return false end

        local container = inv.items.getStatField(objId, invStatFieldContainer) or ""
        if container ~= "" and inv.config.isIgnored(container) then return false end

        local itemLevel = tonumber(inv.items.getStatField(objId, invStatFieldLevel)) or 0
        if itemLevel > targetLevel or not heroOnlyOk(objId) then return false end

        if inv.priority.locIsAllowed
            and not inv.priority.locIsAllowed(loc, priorityName, targetLevel) then
            return false
        end
        return true
    end

    local function forcedCandidateCoverage(record, satisfied)
        local coverage = 0
        for effectName in pairs(forcedEffectSet) do
            if not satisfied[effectName] and candidateHasEffect(record, effectName) then
                coverage = coverage + 1
            end
        end
        return coverage
    end

    ---------------------------------------------------------------------------
    -- PHASE 0: Reserve providers for effect rows marked "force"
    ---------------------------------------------------------------------------

    local satisfiedForcedEffects = {}
    if #forcedEffects > 0 then
        local scarcity = {}
        for _, effectName in ipairs(forcedEffects) do
            local candidateItems = {}
            for _, record in ipairs(candidateIndex.allItems) do
                local objId, item = record.id, record.item
                if candidateHasEffect(record, effectName) then
                    for _, loc in ipairs(inv.set.wearableLocations) do
                        if loc ~= "wielded" and loc ~= "second"
                            and forcedCandidateEligible(objId, item, loc) then
                            candidateItems[tostring(objId)] = true
                            break
                        end
                    end
                end
            end
            table.insert(scarcity, { effect = effectName, count = dbot.table.getNumEntries(candidateItems) })
        end
        table.sort(scarcity, function(a, b)
            if a.count ~= b.count then return a.count < b.count end
            return a.effect < b.effect
        end)

        for _, required in ipairs(scarcity) do
            local effectName = required.effect
            if not satisfiedForcedEffects[effectName] then
                local best = nil
                for _, record in ipairs(candidateIndex.allItems) do
                    local objId, item = record.id, record.item
                    if candidateHasEffect(record, effectName) then
                        for _, loc in ipairs(inv.set.wearableLocations) do
                            if loc ~= "wielded" and loc ~= "second" and equipment[loc] == nil
                                and forcedCandidateEligible(objId, item, loc) then
                                local candidate = {
                                    id = objId,
                                    loc = loc,
                                    record = record,
                                    coverage = forcedCandidateCoverage(record, satisfiedForcedEffects),
                                    score = scoreItem(objId, record),
                                    level = tonumber(inv.items.getStatField(objId, invStatFieldLevel)) or 0,
                                    name = inv.items.getStatField(objId, invStatFieldName) or "Unknown",
                                }
                                if best == nil
                                    or candidate.coverage > best.coverage
                                    or (candidate.coverage == best.coverage and candidate.score > best.score)
                                    or (candidate.coverage == best.coverage and candidate.score == best.score
                                        and candidate.level > best.level)
                                    or (candidate.coverage == best.coverage and candidate.score == best.score
                                        and candidate.level == best.level
                                        and tostring(candidate.id) > tostring(best.id)) then
                                    best = candidate
                                end
                            end
                        end
                    end
                end

                if best then
                    equipment[best.loc] = best.id
                    usedItems[best.id] = true
                    forcedLocations[best.loc] = true
                    for forcedEffect in pairs(forcedEffectSet) do
                        if candidateHasEffect(best.record, forcedEffect) then
                            satisfiedForcedEffects[forcedEffect] = true
                        end
                    end
                    debug(string.format(
                        "Phase 0: Forced effect %s -> %s at %s (score=%.1f)",
                        effectName, best.name, best.loc, best.score
                    ))
                elseif debugEnabled then
                    dbot.warn(string.format(
                        "Priority '%s' forces effect '%s' at level %d, but no compatible owned item can provide it.",
                        tostring(priorityName), effectName, tonumber(targetLevel) or 0
                    ))
                end
            end
        end
    end

    ---------------------------------------------------------------------------
    -- PHASE 1: Find best item for each non-weapon slot
    ---------------------------------------------------------------------------

    for _, loc in ipairs(inv.set.wearableLocations) do
        if loc ~= "wielded" and loc ~= "second" and equipment[loc] == nil then
            local bestItem = nil
            local bestScore = -999999
            local bestLevel = 0
            local bestName = nil
            local candidateNames = {}

            local filteredNames = {}

            for _, record in ipairs(candidateIndex.byLocation[loc] or {}) do
                local objId, item = record.id, record.item
                local isKeyringItem = inv.items.isKeyringItem
                    and inv.items.isKeyringItem(item)
                if not isExcluded(objId) and not usedItems[objId] and not isKeyringItem then
                    local itemName = inv.items.getStatField(objId, invStatFieldName) or "Unknown"
                    local container = inv.items.getStatField(objId, invStatFieldContainer) or ""
                    local isIgnored = container ~= "" and inv.config.isIgnored(container)
                    if isIgnored then
                        table.insert(filteredNames, string.format("%s [ignored container %s]", itemName, tostring(container)))
                    else
                        local itemLevel = tonumber(inv.items.getStatField(objId, invStatFieldLevel)) or 0
                        local levelOk = itemLevel <= targetLevel
                        local heroOk = heroOnlyOk(objId)

                        local locAllowed = true
                        if inv.priority.locIsAllowed then
                            locAllowed = inv.priority.locIsAllowed(loc, priorityName, targetLevel)
                        end

                        if levelOk and heroOk and locAllowed then
                            table.insert(candidateNames, itemName)

                            local score = scoreItem(objId, record)
                            debug(string.format("Phase 1: Candidate for %s -> %s (L%d) score=%.1f",
                                  loc, itemName,
                                  itemLevel, score or 0))

                            if score > bestScore then
                                bestScore = score
                                bestItem = objId
                                bestLevel = itemLevel
                                bestName = itemName
                            end
                        else
                            local reasons = {}
                            if not levelOk then
                                table.insert(reasons, string.format("level %d>%d", itemLevel, targetLevel))
                            end
                            if not heroOk then
                                table.insert(reasons, "heroOnly gate")
                            end
                            if not locAllowed then
                                table.insert(reasons, "priority blocked")
                            end
                            table.insert(filteredNames, string.format("%s [%s]", itemName, table.concat(reasons, ", ")))
                        end
                    end
                end
            end

            if #candidateNames > 0 then
                debug(string.format("Phase 1: %s items found: %s", loc, table.concat(candidateNames, ", ")))
            else
                debug(string.format("Phase 1: %s items found: (none)", loc))
            end

            if #filteredNames > 0 then
                debug(string.format("Phase 1: %s items filtered: %s", loc, table.concat(filteredNames, ", ")))
            end

            if bestItem then
                equipment[loc] = bestItem
                usedItems[bestItem] = true
                debug(string.format("Phase 1: %s -> %s (L%d) score=%.1f",
                      loc, bestName or "Unknown", bestLevel or 0, bestScore or 0))
            else
                debug(string.format("Phase 1: %s -> (no eligible item found)", loc))
            end
        end
    end

    ---------------------------------------------------------------------------
    -- PHASE 2: Build weapon array with scores and weights
    ---------------------------------------------------------------------------

    debug("Phase 2: Building weapon array for level " .. targetLevel)

    for _, record in ipairs(candidateIndex.weapons) do
        local objId, item = record.id, record.item
        local container = inv.items.getStatField(objId, invStatFieldContainer) or ""
        local isIgnored = container ~= "" and inv.config.isIgnored(container)
        local isKeyringItem = inv.items.isKeyringItem
            and inv.items.isKeyringItem(item)
        if not isExcluded(objId) and not isIgnored and not isKeyringItem then
            local itemLevel = tonumber(inv.items.getStatField(objId, invStatFieldLevel)) or 0
            if itemLevel <= targetLevel and heroOnlyOk(objId) then
                local primaryScore, offhandScore = scoreItemPair(objId, record)
                local weight = tonumber(inv.items.getStatField(objId, invStatFieldWeight)) or 0
                local aveDam = tonumber(inv.items.getStatField(objId, invStatFieldAveDam)) or 0
                local name = inv.items.getStatField(objId, invStatFieldName) or "Unknown"

                debug(string.format("  Weapon: %s (L%d W%d) primary=%.1f offhand=%.1f",
                      name, itemLevel, weight, primaryScore or 0, offhandScore or 0))

                table.insert(weaponArray, {
                    id = objId,
                    score = primaryScore or 0,
                    offhand = offhandScore or 0,
                    weight = weight,
                    name = name,
                    level = itemLevel,
                    aveDam = aveDam
                })
            end
        end
    end

    debug("Phase 2: Found " .. #weaponArray .. " weapons")

    ---------------------------------------------------------------------------
    -- PHASE 3: Check for dual wield availability
    ---------------------------------------------------------------------------

    local dualWieldAvailable = false

    if dbot.ability and dbot.ability.hasDualWieldAccess then
        dualWieldAvailable = dbot.ability.hasDualWieldAccess(targetLevel)
        debug("Phase 3: Natural dual wield: " .. tostring(dualWieldAvailable))
    end

    if not dualWieldAvailable and equipment.hands then
        local handsName = inv.items.getStatField(equipment.hands, invStatFieldName) or ""
        if handsName:lower():find("aardwolf gloves of dexterity") then
            dualWieldAvailable = true
            debug("Phase 3: Dual wield from Aard Gloves")
        end
        local affects = inv.items.getStatField(equipment.hands, invStatFieldAffects) or ""
        local flags = inv.items.getStatField(equipment.hands, invStatFieldFlags) or ""
        local combined = (affects .. " " .. flags):lower()
        if combined:find("dualwield") or combined:find("dual wield") then
            dualWieldAvailable = true
            debug("Phase 3: Dual wield from glove affects/flags")
        end
    end

    if dualWieldAvailable and inv.priority.locIsAllowed then
        local secondAllowed = inv.priority.locIsAllowed("second", priorityName, targetLevel)
        if not secondAllowed then
            dualWieldAvailable = false
            debug("Phase 3: Second slot disabled by priority")
        end
    end

    debug("Phase 3: Dual wield available: " .. tostring(dualWieldAvailable))

    ---------------------------------------------------------------------------
    -- PHASE 4: Find best weapon combination (respecting weight rules)
    ---------------------------------------------------------------------------

    local bestWeaponSet = { score = 0, primary = nil, offhand = nil }

    if dualWieldAvailable and #weaponArray >= 2 then
        local primaryArray = {}
        local offhandArray = {}
        for _, w in ipairs(weaponArray) do
            table.insert(primaryArray, w)
            table.insert(offhandArray, w)
        end
        table.sort(primaryArray, function(a, b)
            if a.score ~= b.score then
                return a.score > b.score
            end
            if a.aveDam ~= b.aveDam then
                return a.aveDam > b.aveDam
            end
            if a.level ~= b.level then
                return a.level > b.level
            end
            return a.id > b.id
        end)
        table.sort(offhandArray, function(a, b)
            if a.offhand ~= b.offhand then
                return a.offhand > b.offhand
            end
            if a.aveDam ~= b.aveDam then
                return a.aveDam > b.aveDam
            end
            if a.level ~= b.level then
                return a.level > b.level
            end
            return a.id > b.id
        end)

        local subclass = ""
        if dbot.gmcp and dbot.gmcp.getClass then
            local _, sc = dbot.gmcp.getClass()
            subclass = sc or ""
        end
        local isSoldier = subclass:lower() == "soldier"

        debug("Phase 4: Searching for valid weapon combos (Soldier=" .. tostring(isSoldier) .. ")")

        for _, primary in ipairs(primaryArray) do
            local foundValidOffhand = false
            for _, offhand in ipairs(offhandArray) do
                if primary.id ~= offhand.id and not foundValidOffhand then
                    local weightValid = false
                    local reason = ""

                    if isSoldier then
                        weightValid = true
                        reason = "Soldier"
                    elseif primary.weight == 0 and offhand.weight == 0 then
                        weightValid = true
                        reason = "Both 0 weight"
                    elseif primary.weight >= (offhand.weight * 2) then
                        weightValid = true
                        reason = string.format("%d >= %d*2", primary.weight, offhand.weight)
                    else
                        reason = string.format("FAIL: %d < %d*2", primary.weight, offhand.weight)
                    end

                    if weightValid then
                        local comboScore = primary.score + offhand.offhand
                        debug(string.format("  Valid combo: %s + %s = %.1f (%s)",
                              primary.name, offhand.name, comboScore, reason))

                        if comboScore > bestWeaponSet.score then
                            bestWeaponSet.score = comboScore
                            bestWeaponSet.primary = { id = primary.id, score = primary.score, name = primary.name }
                            bestWeaponSet.offhand = { id = offhand.id, score = offhand.offhand, name = offhand.name }
                        end
                        foundValidOffhand = true
                    end
                end
            end
        end

        if bestWeaponSet.primary then
            debug(string.format("Phase 4: Best combo: %s + %s = %.1f",
                  bestWeaponSet.primary.name, bestWeaponSet.offhand.name, bestWeaponSet.score))
        else
            debug("Phase 4: No valid weapon combo found!")
        end
    end

    ---------------------------------------------------------------------------
    -- PHASE 5: Find best single weapon
    ---------------------------------------------------------------------------

    local bestSingleWeapon = nil
    local bestSingleScore = -999999
    for _, w in ipairs(weaponArray) do
        if w.score > bestSingleScore then
            bestSingleScore = w.score
            bestSingleWeapon = w
        elseif w.score == bestSingleScore and bestSingleWeapon then
            if w.aveDam > bestSingleWeapon.aveDam then
                bestSingleWeapon = w
            elseif w.aveDam == bestSingleWeapon.aveDam then
                if w.level > bestSingleWeapon.level then
                    bestSingleWeapon = w
                elseif w.level == bestSingleWeapon.level and w.id > bestSingleWeapon.id then
                    bestSingleWeapon = w
                end
            end
        end
    end

    if bestSingleWeapon then
        debug(string.format("Phase 5: Best single weapon: %s (L%d) score=%.1f",
              bestSingleWeapon.name, bestSingleWeapon.level, bestSingleWeapon.score))
    end

    ---------------------------------------------------------------------------
    -- PHASE 6: Compare dual wield vs single weapon + shield + hold
    ---------------------------------------------------------------------------

    local scorePrimary = bestSingleWeapon and bestSingleWeapon.score or 0
    local scoreShield = 0
    local scoreHold = 0

    if equipment.shield then
        scoreShield = scoreItem(equipment.shield)
    end

    if equipment.hold then
        scoreHold = scoreItem(equipment.hold)
    end

    local singleWeaponTotal = scorePrimary + scoreShield + scoreHold
    local dualWieldTotal = bestWeaponSet.score

    debug(string.format("Phase 6: Single(%.1f + %.1f + %.1f = %.1f) vs Dual(%.1f)",
          scorePrimary, scoreShield, scoreHold, singleWeaponTotal, dualWieldTotal))

    local forceRequiresSingleWeapon = forcedLocations.shield or forcedLocations.hold
    if forceRequiresSingleWeapon then
        debug("Phase 6: Forced shield/hold effect requires single-weapon equipment")
    end

    if dualWieldAvailable and bestWeaponSet.primary and dualWieldTotal > singleWeaponTotal
        and not forceRequiresSingleWeapon then
        equipment.wielded = bestWeaponSet.primary.id
        equipment.second = bestWeaponSet.offhand.id
        equipment.shield = nil
        equipment.hold = nil

        usedItems[bestWeaponSet.primary.id] = true
        usedItems[bestWeaponSet.offhand.id] = true

        debug("Phase 6: SELECTED DUAL WIELD")
    else
        if bestSingleWeapon then
            equipment.wielded = bestSingleWeapon.id
            usedItems[bestSingleWeapon.id] = true
        end
        equipment.second = nil

        debug("Phase 6: SELECTED SINGLE WEAPON + HOLD")
    end

    local rawStats = inv.set.getStats(equipment, targetLevel, false, candidateIndex)
    local setScore
    if scoreContext and inv.score.setStats then
        setScore = inv.score.setStats(rawStats, priorityName, targetLevel, scoreContext)
    else
        setScore = inv.score.set(equipment, priorityName, targetLevel, scoreContext, candidateIndex)
    end

    return equipment, rawStats, setScore or 0
end

----------------------------------------------------------------------------------------------------
-- Create an in-memory equipment preview without changing or saving inv.set.table
----------------------------------------------------------------------------------------------------

function inv.set.createPreview(priorityName, level, excludedItems, intensity, baseLevelOverride)
    if priorityName == nil or priorityName == "" then
        dbot.warn("inv.set.createPreview: Missing priority name")
        return nil, nil, nil, DRL_RET_INVALID_PARAM
    end

    if not inv.priority.exists(priorityName) then
        dbot.warn("Priority '" .. priorityName .. "' does not exist")
        return nil, nil, nil, DRL_RET_MISSING_ENTRY
    end

    local targetLevel = invSetResolveTargetLevel(level)
    local baseLevel = tonumber(baseLevelOverride) or invSetResolveBaseLevel(targetLevel)
    local bonusType = invStatBonusTypeAve
    if targetLevel == invSetResolveTargetLevel(nil) then
        bonusType = invStatBonusTypeCurrent
    end

    local statDelta = nil
    if inv.statBonus and inv.statBonus.get then
        statDelta = inv.statBonus.get(targetLevel, bonusType)
    end

    local candidateIndex = inv.set.buildCandidateIndex()
    local scoreContext = inv.score.createContext and inv.score.createContext(priorityName, targetLevel) or nil
    local createIntensity = intensity or inv.set.createIntensity or 1
    local handicap = { int = 0, wis = 0, luck = 0, str = 0, dex = 0, con = 0 }
    local handicapDelta = 1 / math.max(1, createIntensity)
    local bestScore = -999999
    local bestEquipment = nil
    local bestStats = nil

    for _ = 1, createIntensity do
        local equipment, rawStats, score = inv.set.createWithHandicap(
            priorityName,
            targetLevel,
            baseLevel,
            handicap,
            false,
            excludedItems,
            candidateIndex,
            scoreContext
        )

        if score > bestScore then
            bestScore = score
            bestEquipment = equipment
            bestStats = rawStats
        end

        local overstat = false
        if statDelta and rawStats then
            for statName, delta in pairs(statDelta) do
                if rawStats[statName] ~= nil and delta ~= nil
                    and tonumber(rawStats[statName]) > tonumber(delta) then
                    handicap[statName] = handicap[statName] + handicapDelta
                    overstat = true
                end
            end
        end

        if not overstat then
            break
        end
    end

    return bestEquipment or {}, bestStats, bestScore, DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Check if item can be worn at a location
----------------------------------------------------------------------------------------------------

function inv.set.canWearAt(itemWearable, targetLoc)
    if itemWearable == nil or itemWearable == "" then
        return false
    end

    itemWearable = string.lower(itemWearable)
    targetLoc = string.lower(targetLoc)

    local mappings = {
        ear = { "lear", "rear" },
        ["left ear"] = { "lear" },
        ["right ear"] = { "rear" },

        neck = { "neck1", "neck2" },

        wrist = { "lwrist", "rwrist" },
        ["left wrist"] = { "lwrist" },
        ["right wrist"] = { "rwrist" },

        finger = { "lfinger", "rfinger" },
        ["left finger"] = { "lfinger" },
        ["right finger"] = { "rfinger" },

        medal = { "medal1", "medal2", "medal3", "medal4" },
        pride = { "medal1", "medal2", "medal3", "medal4" },

        wield = { "wielded", "second" },
        ["second wield"] = { "second" },
    }

    local function matchesWearable(wearableValue)
        if wearableValue == targetLoc then
            return true
        end

        local mapped = mappings[wearableValue]
        if mapped then
            for _, loc in ipairs(mapped) do
                if loc == targetLoc then
                    return true
                end
            end
        end

        return false
    end

    for entry in itemWearable:gmatch("([^,]+)") do
        local cleaned = entry:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        if cleaned ~= "" then
            if matchesWearable(cleaned) then
                return true
            end
            for token in cleaned:gmatch("%S+") do
                if matchesWearable(token) then
                    return true
                end
            end
        end
    end

    return false
end

----------------------------------------------------------------------------------------------------
-- Check if set has dual wield capability
----------------------------------------------------------------------------------------------------

function inv.set.hasDualWield(equipment)
    if equipment == nil then
        return false
    end

    if equipment.hands then
        local affects = inv.items.getStatField(equipment.hands, invStatFieldAffects) or ""
        local flags = inv.items.getStatField(equipment.hands, invStatFieldFlags) or ""
        local combined = string.lower(affects .. " " .. flags)

        if combined:find("dualwield", 1, true) or combined:find("dual wield", 1, true) then
            return true
        end
    end

    return false
end

function inv.set.getStaleReason(priorityName, level)
    local targetLevel = tostring(tonumber(level) or level or "")
    local setData = inv.set.table
        and inv.set.table[priorityName]
        and inv.set.table[priorityName][targetLevel]
    if not setData then
        return nil
    end
    if inv.context and inv.context.getStaleReason then
        return inv.context.getStaleReason(setData.context)
    end
    return nil
end


function inv.set.display(priorityName, level, endTag, forceRebuild)
    if priorityName == nil or priorityName == "" then
        dbot.warn("Usage: dinv set display <priority> [level]")
        if endTag then
            return inv.tags.stop(invTagsSet, endTag, DRL_RET_INVALID_PARAM)
        end
        return DRL_RET_INVALID_PARAM
    end

    if inv.items == nil or inv.items.table == nil or dbot.table.getNumEntries(inv.items.table) == 0 then
        dbot.info("Your inventory table is empty. Run '@Gdinv build confirm@W' to populate it.")
        if endTag then
            return inv.tags.stop(invTagsSet, endTag, DRL_RET_MISSING_ENTRY)
        end
        return DRL_RET_MISSING_ENTRY
    end

    local targetLevel = tostring(tonumber(level) or (dbot.gmcp.getWearableLevel and dbot.gmcp.getWearableLevel()) or (dbot.gmcp.getLevel and dbot.gmcp.getLevel()) or 1)

    if forceRebuild == nil then
        forceRebuild = true
    end

    local staleReason = inv.set.getStaleReason(priorityName, targetLevel)
    if staleReason then
        dbot.warn("Cached set for '" .. priorityName .. "' is stale: " .. staleReason .. ". Continuing with the requested operation.")
    end

    if forceRebuild then
        inv.set.delete(priorityName, targetLevel)
    end

    if inv.set.table[priorityName] == nil or inv.set.table[priorityName][targetLevel] == nil then
        dbot.info("Creating set for display...")
        local retval = inv.set.create(priorityName, tonumber(targetLevel))
        if retval ~= DRL_RET_SUCCESS then
            if endTag then
                return inv.tags.stop(invTagsSet, endTag, retval)
            end
            return retval
        end
    end

    local setData = inv.set.table[priorityName][targetLevel]
    if setData == nil then
        dbot.warn("No set found for priority '" .. priorityName .. "' at level " .. targetLevel)
        if endTag then
            return inv.tags.stop(invTagsSet, endTag, DRL_RET_MISSING_ENTRY)
        end
        return DRL_RET_MISSING_ENTRY
    end

    dbot.print("@W")
    dbot.print("@WEquipment set:   @GLevel " .. string.format("%3d", targetLevel) .. " @C" .. priorityName .. "@w")
    dbot.print("@W")

    local stats = { str=0, int=0, wis=0, dex=0, con=0, luck=0, hr=0, dr=0, hp=0, mana=0, moves=0 }
    local effects = {}

    for _, loc in ipairs(inv.set.wearableLocations) do
        local objId = setData.equipment and setData.equipment[loc]
        if objId then
            -- Use colorname if available, fallback to name
            local colorName = inv.items.getStatField(objId, invStatFieldColorName)
            local name = inv.items.getStatField(objId, invStatFieldName) or "Unknown"
            local displayName = colorName or name
            local itemLevel = inv.items.getStatField(objId, invStatFieldLevel) or 0

            -- Strip enchant text from display name
            displayName = displayName:gsub("%s+[A-Z][a-z]+%s+%+?%-?%d+%s*%(removable[^%)]*%).*", "")

            dbot.print(string.format("@Y%10s@W: @GLevel %3d@W \"%s@W\"",
                       loc, itemLevel, displayName))

            stats.str = stats.str + (tonumber(inv.items.getStatField(objId, invStatFieldStr)) or 0)
            stats.int = stats.int + (tonumber(inv.items.getStatField(objId, invStatFieldInt)) or 0)
            stats.wis = stats.wis + (tonumber(inv.items.getStatField(objId, invStatFieldWis)) or 0)
            stats.dex = stats.dex + (tonumber(inv.items.getStatField(objId, invStatFieldDex)) or 0)
            stats.con = stats.con + (tonumber(inv.items.getStatField(objId, invStatFieldCon)) or 0)
            stats.luck = stats.luck + (tonumber(inv.items.getStatField(objId, invStatFieldLuck)) or 0)
            stats.hr = stats.hr + (tonumber(inv.items.getStatField(objId, invStatFieldHitroll)) or 0)
            stats.dr = stats.dr + (tonumber(inv.items.getStatField(objId, invStatFieldDamroll)) or 0)
            stats.hp = stats.hp + (tonumber(inv.items.getStatField(objId, invStatFieldHp)) or 0)
            stats.mana = stats.mana + (tonumber(inv.items.getStatField(objId, invStatFieldMana)) or 0)
            stats.moves = stats.moves + (tonumber(inv.items.getStatField(objId, invStatFieldMoves)) or 0)

            for _, eff in ipairs({
                "sanctuary", "haste", "regeneration", "dualwield", "flying", "invis",
                "irongrip", "shield", "detectgood", "detectevil", "detecthidden", "detectinvis", "detectmagic"
            }) do
                if itemHasEffect(objId, eff) then
                    effects[eff] = true
                end
            end
        end
    end

    dbot.print("@W")
    local effectStr = ""
    for eff, _ in pairs(effects) do
        effectStr = effectStr .. eff .. " "
    end

    dbot.print(string.format("@WHR  DR Int Wis Lck Str Dex Con HitP Mana Move Effects"))
    dbot.print(string.format("@G%3d %3d %3d %3d %3d %3d %3d %3d %4d %4d %4d @C%s@w",
               stats.hr, stats.dr, stats.int, stats.wis, stats.luck,
               stats.str, stats.dex, stats.con, stats.hp, stats.mana, stats.moves,
               effectStr))

    dbot.print("@W")
    dbot.print("@WTotal Score: @G" .. string.format("%.2f", setData.score or 0) .. "@w")

    if endTag then
        return inv.tags.stop(invTagsSet, endTag, DRL_RET_SUCCESS)
    end
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Delete a cached equipment set
----------------------------------------------------------------------------------------------------

function inv.set.delete(priorityName, level)
    if priorityName == nil or priorityName == "" then
        return DRL_RET_INVALID_PARAM
    end

    local targetLevel = tostring(tonumber(level) or (dbot.gmcp.getWearableLevel and dbot.gmcp.getWearableLevel()) or (dbot.gmcp.getLevel and dbot.gmcp.getLevel()) or 1)

    if inv.set.table[priorityName] and inv.set.table[priorityName][targetLevel] then
        inv.set.table[priorityName][targetLevel] = nil
        inv.set.save()
    end

    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Get combined stats from an equipment set
----------------------------------------------------------------------------------------------------

function inv.set.getStats(equipSet, level, doCap, candidateIndex)
    local retval = DRL_RET_SUCCESS

    if equipSet == nil then
        if dbot and dbot.warn then
            dbot.warn("inv.set.getStats: Attempted to get set stats for nil set")
        end
        return nil, DRL_RET_INVALID_PARAM
    end

    -- Initialize stats table with all possible stat fields
    local setStats = {
        -- Primary stats
        str = 0, int = 0, wis = 0, dex = 0, con = 0, luck = 0,
        -- Resources
        hp = 0, mana = 0, moves = 0,
        -- Combat stats
        hit = 0, dam = 0,
        avedam = 0, offhandDam = 0,
        -- Physical resistances
        slash = 0, pierce = 0, bash = 0,
        -- Magical resistances
        acid = 0, cold = 0, energy = 0, holy = 0, electric = 0,
        negative = 0, shadow = 0, poison = 0, disease = 0, magic = 0,
        air = 0, earth = 0, fire = 0, light = 0, mental = 0, sonic = 0, water = 0,
        -- Consolidated resistances
        allphys = 0, allmagic = 0,
        -- Affects/Effects
        haste = 0, regeneration = 0, sanctuary = 0, invis = 0, flying = 0,
        detectgood = 0, detectevil = 0, detecthidden = 0, detectinvis = 0, detectmagic = 0,
        dualwield = 0, irongrip = 0, shield = 0,
        -- Effects tracking
        effects = {}
    }

    -- Handle both old format (equipment sub-table) and direct format
    local equipment = equipSet.equipment or equipSet

    local setStatFieldMap = {
        hit = invStatFieldHitroll,
        dam = invStatFieldDamroll,
    }

    for itemLoc, itemData in pairs(equipment) do
        -- Get the object ID - handle both formats
        local objId
        if type(itemData) == "table" then
            objId = tonumber(itemData.id) or tonumber(itemData)
        else
            objId = tonumber(itemData)
        end

        if objId and objId > 0 then
            -- Aggregate all stats from this item
            for statName, statValue in pairs(setStats) do
                if type(statValue) == "number" then
                    local itemValue = 0

                    -- Get item stat value if inv.items is available
                    if inv.items and inv.items.getStatField then
                        local sourceField = setStatFieldMap[statName] or statName
                        itemValue = inv.items.getStatField(objId, sourceField) or 0
                    end

                    -- Offhand weapons should give stats to offhandDam, not avedam
                    if itemLoc == "second" and statName == "avedam" then
                        setStats.offhandDam = setStats.offhandDam + (itemValue or 0)
                    elseif statName ~= "offhandDam" or itemLoc == "second" then
                        if itemValue and itemValue ~= 0 then
                            setStats[statName] = setStats[statName] + itemValue
                        end
                    end
                end
            end

            -- Track effects from affects/flags
            if inv.items and inv.items.getStatField then
                local effectsList = {
                    "sanctuary", "haste", "flying", "invis", "regeneration",
                    "dualwield", "irongrip", "shield", "detectinvis", "detecthidden",
                    "detectmagic", "detectgood", "detectevil"
                }

                local candidateRecord = candidateIndex and candidateIndex.byId
                    and candidateIndex.byId[tostring(objId)] or nil

                for _, effect in ipairs(effectsList) do
                    local hasEffect
                    if candidateRecord then
                        hasEffect = candidateHasEffect(candidateRecord, effect)
                    else
                        hasEffect = itemHasEffect(objId, effect)
                    end
                    if hasEffect then
                        setStats.effects[effect] = true
                    end
                end
            end
        end
    end

    -- If level is available, cap stats that have maximums
    if doCap == nil then
        doCap = true
    end

    level = tonumber(level or "")
    if level ~= nil and doCap then
        local statsWithCaps = { "int", "wis", "luck", "str", "dex", "con" }

        for _, statName in ipairs(statsWithCaps) do
            if inv.statBonus and inv.statBonus.equipBonus and
               inv.statBonus.equipBonus[level] and
               inv.statBonus.equipBonus[level][statName] then
                local maxValue = inv.statBonus.equipBonus[level][statName]
                local currentValue = tonumber(setStats[statName] or 0)

                if currentValue > maxValue then
                    if dbot and dbot.debug then
                        dbot.debug("inv.set.getStats: capping " .. statName ..
                                   " from " .. currentValue .. " to " .. maxValue, "inv.set")
                    end
                    setStats[statName] = maxValue
                end
            end
        end
    end

    return setStats, retval
end

----------------------------------------------------------------------------------------------------
-- Display stats from an equipment set
----------------------------------------------------------------------------------------------------

function inv.set.displayStats(setStats, msgString, doPrintHeader, doDisplayIfZero, channel)
    local totResists = 0
    local didFindAStat = false

    if setStats == nil then
        if dbot and dbot.warn then
            dbot.warn("inv.set.displayStats: set stats are nil")
        end
        return didFindAStat, DRL_RET_INVALID_PARAM
    end

    -- Calculate total resistances (weighted)
    local resistNames = {
        [1]  = { "allphys", "allmagic" },
        [3]  = { "bash", "pierce", "slash" },
        [17] = { "acid", "cold", "energy", "holy", "electric", "negative",
                 "shadow", "magic", "air", "earth", "fire", "light",
                 "mental", "sonic", "water", "disease", "poison" }
    }

    for resistWeight, resistTable in pairs(resistNames) do
        for _, resistName in ipairs(resistTable) do
            totResists = totResists + tonumber(setStats[resistName] or 0) / tonumber(resistWeight)
        end
    end
    setStats.totResists = totResists

    -- Build display string
    local setStr = (msgString or "")

    -- Print header if requested
    if doPrintHeader then
        local header = string.rep(" ", #(msgString or "")) ..
                       " Ave  Sec  HR  DR Str Int Wis Dex Con Lck Res HitP Mana Move Effects"
        if dbot and dbot.print then
            dbot.print("@W" .. header)
        else
            cecho("<white>" .. header .. "\n")
        end
    end

    -- Format stats
    local function fmtStat(val, width)
        val = tonumber(val) or 0
        if val ~= 0 then
            didFindAStat = true
        end
        return string.format("%" .. width .. "d", val)
    end

    setStr = setStr .. " " .. fmtStat(setStats.avedam, 3)
    setStr = setStr .. "  " .. fmtStat(setStats.offhandDam, 3)
    setStr = setStr .. "  " .. fmtStat(setStats.hit, 2)
    setStr = setStr .. "  " .. fmtStat(setStats.dam, 2)
    setStr = setStr .. " " .. fmtStat(setStats.str, 3)
    setStr = setStr .. " " .. fmtStat(setStats.int, 3)
    setStr = setStr .. " " .. fmtStat(setStats.wis, 3)
    setStr = setStr .. " " .. fmtStat(setStats.dex, 3)
    setStr = setStr .. " " .. fmtStat(setStats.con, 3)
    setStr = setStr .. " " .. fmtStat(setStats.luck, 3)
    setStr = setStr .. " " .. fmtStat(setStats.totResists, 3)
    setStr = setStr .. " " .. fmtStat(setStats.hp, 4)
    setStr = setStr .. " " .. fmtStat(setStats.mana, 4)
    setStr = setStr .. " " .. fmtStat(setStats.moves, 4)

    -- Add effects
    local effectsStr = ""
    if setStats.effects then
        for effect, _ in pairs(setStats.effects) do
            if effectsStr ~= "" then
                effectsStr = effectsStr .. ", "
            end
            effectsStr = effectsStr .. effect
        end
    end
    if effectsStr ~= "" then
        setStr = setStr .. " " .. effectsStr
    end

    -- Only print if we found stats or doDisplayIfZero is true
    if didFindAStat or doDisplayIfZero then
        if dbot and dbot.print then
            dbot.print("@w" .. setStr)
        else
            cecho("<white>" .. setStr .. "\n")
        end
    end

    return didFindAStat, DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Wear Equipment Set
----------------------------------------------------------------------------------------------------

function inv.set.wear(priorityName, level, endTag, options)
    options = options or {}
    if priorityName == nil or priorityName == "" then
        dbot.warn("Usage: dinv set wear <priority> [level]")
        if endTag then
            return inv.tags.stop(invTagsSet, endTag, DRL_RET_INVALID_PARAM)
        end
        return DRL_RET_INVALID_PARAM
    end

    local targetLevel = tostring(invSetResolveTargetLevel(level))
    local setLabel = (options.cached and "Cached set" or "Equipment set") ..
        " '" .. tostring(priorityName) .. "' at level " .. targetLevel
    local wearTimingId = DINV and DINV.debug and DINV.debug.startWearTiming
        and DINV.debug.startWearTiming(priorityName, targetLevel) or nil
    local cacheTimingWall, cacheTimingCpu = nil, nil
    if wearTimingId and DINV.debug.beginWearTimingSample then
        cacheTimingWall, cacheTimingCpu = DINV.debug.beginWearTimingSample()
    end

    local function finishWearTiming(result, delayed)
        if not wearTimingId or not DINV or not DINV.debug then
            return
        end
        if delayed and DINV.debug.requestWearTimingFinish then
            DINV.debug.requestWearTimingFinish(wearTimingId, result)
        elseif DINV.debug.finishWearTiming then
            DINV.debug.finishWearTiming(wearTimingId, result)
        end
    end

    if inv.set.table[priorityName] == nil or inv.set.table[priorityName][targetLevel] == nil then
        dbot.info("Creating set before wearing...")
        local retval = inv.set.create(priorityName, tonumber(targetLevel))
        if retval ~= DRL_RET_SUCCESS then
            finishWearTiming({ status = "set creation failed" })
            if endTag then
                return inv.tags.stop(invTagsSet, endTag, retval)
            end
            return retval
        end
    end

    local setData = inv.set.table[priorityName][targetLevel]
    if setData == nil or setData.equipment == nil then
        finishWearTiming({ status = "set unavailable" })
        dbot.warn("No set found for priority '" .. priorityName .. "' at level " .. targetLevel)
        if endTag then
            return inv.tags.stop(invTagsSet, endTag, DRL_RET_MISSING_ENTRY)
        end
        return DRL_RET_MISSING_ENTRY
    end

    if wearTimingId and DINV.debug.recordWearTimingPhase then
        DINV.debug.recordWearTimingPhase(wearTimingId, "cache", cacheTimingWall, cacheTimingCpu)
    end
    local planTimingWall, planTimingCpu = nil, nil
    if wearTimingId and DINV.debug.beginWearTimingSample then
        planTimingWall, planTimingCpu = DINV.debug.beginWearTimingSample()
    end

    dbot.info("Wearing equipment set for priority '" .. priorityName .. "' at level " .. targetLevel)
    local function wearDebug(message)
        if dbot and dbot.debug then
            dbot.debug("inv.set.wear: " .. message, "inv.set")
        end
    end

    local commands = {}
    local wornById = {}
    local wornByLoc = {}
    local desiredLocsById = {}
    local removedForReequip = {}
    local removedOrStoredById = {}
    local function isKnownWearSlotLocation(locationValue)
        return inv.items.isWearSlot(locationValue)
    end

    local function resolveStoreContainer(objId)
        local function isUsableContainer(containerId)
            local normalized = inv.items.normalizeContainerId(containerId)
            if not normalized then
                return nil
            end

            local containerItem = inv.items.table and inv.items.table[normalized]
            if not containerItem then
                return nil
            end

            local typeName = inv.items.getStatField(normalized, invStatFieldType) or ""
            local typeNum = tonumber(inv.items.getStatField(normalized, invStatFieldTypeNum)) or 0
            if typeName == "Container" or typeNum == 11 then
                return normalized
            end
            return nil
        end

        local lastStored = inv.items.getStatField(objId, invStatFieldLastStored)
        local configuredContainer = inv.items.getStatField(objId, invStatFieldContainer)
        return isUsableContainer(lastStored) or isUsableContainer(configuredContainer)
    end

    local function markItemInventory(objId)
        -- Invmon is authoritative; do not persist an expected state before the
        -- server confirms the command batch.
    end

    local function markItemStored(objId, containerId)
        -- Invmon action 6 will update location/container.
    end

    local function markItemWorn(objId, wearLoc)
        -- Invmon action 2 will update the exact observed wear slot.
    end

    local function queueStoreRemovedItem(objId, alreadyRemoved)
        local idKey = tostring(objId)
        local containerId = resolveStoreContainer(objId)
        if not alreadyRemoved then
            table.insert(commands, "remove " .. objId)
        end
        if containerId then
            table.insert(commands, "put " .. objId .. " " .. containerId)
            markItemStored(objId, containerId)
        else
            markItemInventory(objId)
        end
        removedOrStoredById[idKey] = true
        wearDebug(string.format("queue store objId=%s to container=%s (alreadyRemoved=%s)",
            idKey, tostring(containerId), tostring(alreadyRemoved == true)))
    end

    for _, loc in ipairs(inv.set.wearableLocations) do
        local objId = setData.equipment[loc]
        if objId then
            local idKey = tostring(objId)
            if desiredLocsById[idKey] == nil then
                desiredLocsById[idKey] = {}
            end
            desiredLocsById[idKey][loc] = true
        end
    end

    for objId, item in pairs(inv.items.table) do
        local location = tostring(inv.items.getStatField(objId, invStatFieldLocation) or "")
        local resolvedSlot = inv.items.resolveWearSlot(location)
        local wornLoc = (resolvedSlot ~= invItemLocWorn) and resolvedSlot or nil

        local isActuallyWorn = wornLoc ~= nil

        if isActuallyWorn then
            local idKey = tostring(objId)
            wornById[idKey] = wornLoc
            wornByLoc[wornLoc] = idKey
            local desiredLocs = desiredLocsById[idKey]
            if desiredLocs == nil or not desiredLocs[wornLoc] then
                if desiredLocs then
                    -- If already worn (even in a different slot), don't remove for re-wear.
                    removedForReequip[idKey] = true
                else
                    queueStoreRemovedItem(objId, false)
                end
            else
                wearDebug(string.format("objId=%s already worn at desired slot %s (location=%s)",
                    idKey, tostring(wornLoc), tostring(location)))
            end
        end
    end

    for _, loc in ipairs(inv.set.wearableLocations) do
        local desiredObjId = setData.equipment[loc]
        if desiredObjId then
            local desiredIdKey = tostring(desiredObjId)
            local currentIdAtLoc = wornByLoc[loc]
            if currentIdAtLoc and currentIdAtLoc ~= desiredIdKey and not removedOrStoredById[currentIdAtLoc] then
                local currentDesiredLocs = desiredLocsById[currentIdAtLoc]
                table.insert(commands, "remove " .. currentIdAtLoc)
                removedOrStoredById[currentIdAtLoc] = true
                markItemInventory(currentIdAtLoc)
                wearDebug(string.format("queue remove objId=%s from targetLoc=%s (desiredObjId=%s)",
                    tostring(currentIdAtLoc), tostring(loc), tostring(desiredIdKey)))

                if currentDesiredLocs == nil then
                    queueStoreRemovedItem(currentIdAtLoc, true)
                else
                    wearDebug(string.format("keep removed objId=%s in inventory for swap/re-equip", tostring(currentIdAtLoc)))
                end
            end
        end
    end

    local processedDesiredIds = {}
    for _, loc in ipairs(inv.set.wearableLocations) do
        local objId = setData.equipment[loc]
        if objId then
            local idKey = tostring(objId)
            if not processedDesiredIds[idKey] then
                processedDesiredIds[idKey] = true
                local wornLoc = wornById[idKey]
                local desiredLocs = desiredLocsById[idKey]
                local isWornAtAnyDesiredLoc = wornLoc ~= nil and desiredLocs ~= nil and desiredLocs[wornLoc] == true
                if not isWornAtAnyDesiredLoc then
                    local container = inv.items.getStatField(objId, invStatFieldContainer)
                    local location = inv.items.getStatField(objId, invStatFieldLocation)
                    local containerId = inv.items.normalizeContainerId(container)
                    if containerId == nil and location and not isKnownWearSlotLocation(location) then
                        containerId = inv.items.normalizeContainerId(location)
                    end
                    wearDebug(string.format(
                        "queue wear objId=%s targetLoc=%s currentLocation=%s mappedWornLoc=%s container=%s containerId=%s removedForReequip=%s",
                        tostring(objId),
                        tostring(loc),
                        tostring(location),
                        tostring(wornLoc or ""),
                        tostring(container or ""),
                        tostring(containerId or ""),
                        tostring(removedForReequip[idKey] == true)))
                    if location ~= "inventory" and not removedForReequip[idKey] and not isKnownWearSlotLocation(location) then
                        if containerId then
                            wearDebug(string.format("queue get objId=%s from containerId=%s before wear", tostring(objId), tostring(containerId)))
                            table.insert(commands, "get " .. objId .. " " .. containerId)
                        else
                            wearDebug(string.format("queue get objId=%s from current location '%s' before wear", tostring(objId), tostring(location)))
                            table.insert(commands, "get " .. objId)
                        end
                    end
                    table.insert(commands, "wear " .. objId .. " " .. loc)
                    markItemWorn(objId, loc)
                else
                    wearDebug(string.format(
                        "skip wear objId=%s targetLoc=%s because already worn in desired slot set (current=%s)",
                        tostring(objId),
                        tostring(loc),
                        tostring(wornLoc)))
                end
            end
        end
    end

    if wearTimingId and DINV.debug.recordWearTimingPhase then
        DINV.debug.recordWearTimingPhase(wearTimingId, "plan", planTimingWall, planTimingCpu)
    end
    if wearTimingId and DINV.debug.setWearTimingCommands then
        DINV.debug.setWearTimingCommands(wearTimingId, commands)
    end

    local operationId = nil
    local dispatchTimingWall, dispatchTimingCpu = nil, nil
    if wearTimingId and DINV.debug.beginWearTimingSample then
        dispatchTimingWall, dispatchTimingCpu = DINV.debug.beginWearTimingSample()
    end

    if #commands > 0 then
        if inv.operations and inv.operations.startBatchFromCommands then
            local operationOptions = {
                timeout = math.max(8, #commands * 0.2 + 4),
                onFinish = function(result)
                    if wearTimingId then
                        finishWearTiming(result, true)
                    end
                    if result and #(result.failures or {}) == 0 then
                        dbot.info(setLabel .. " equipped.")
                    else
                        dbot.warn(setLabel .. " was not fully equipped.")
                    end
                    if type(options.onFinish) == "function" then
                        pcall(options.onFinish, result)
                    end
                end
            }
            operationId = inv.operations.startBatchFromCommands(
                setLabel,
                commands,
                operationOptions
            )
        end
        if inv.items and inv.items.sendActionCommands then
            inv.items.sendActionCommands(commands)
        elseif dbot.execute and dbot.execute.safe and dbot.execute.safe.commands then
            dbot.execute.safe.commands(commands, nil, nil, nil, nil)
        else
            for i, cmd in ipairs(commands) do
                if tempTimer then
                    tempTimer(i * 0.3, function() send(cmd) end)
                else
                    send(cmd)
                end
            end
        end
    end

    if wearTimingId and DINV.debug.recordWearTimingPhase then
        DINV.debug.recordWearTimingPhase(wearTimingId, "dispatch", dispatchTimingWall, dispatchTimingCpu)
    end
    if wearTimingId and (#commands == 0 or operationId == nil) then
        finishWearTiming({ status = #commands == 0 and "already matched" or "untracked" }, #commands > 0)
    end

    if #commands > 0 then
        dbot.debug("Equipment set commands sent; waiting for final invmon observations.", "inv.set")
        if operationId == nil then
            dbot.warn(setLabel .. " commands were sent, but completion tracking was unavailable.")
        end
    else
        dbot.info(setLabel .. " is already equipped.")
        if type(options.onFinish) == "function" then
            pcall(options.onFinish, { total = 0, confirmed = 0, failures = {}, timedOut = false })
        end
    end

    if endTag then
        return inv.tags.stop(invTagsSet, endTag, DRL_RET_SUCCESS)
    end
    return DRL_RET_SUCCESS
end

local function invSetGetMissingCachedItems(setData)
    local missing = {}
    local equipment = setData and setData.equipment or {}
    local itemNames = setData and setData.itemNames or {}

    for _, loc in ipairs(inv.set.wearableLocations or {}) do
        local objId = equipment[loc]
        if objId ~= nil and not (inv.items and inv.items.getItem and inv.items.getItem(objId)) then
            local itemName = itemNames and itemNames[loc] or nil
            if itemName == nil or tostring(itemName) == "" then
                itemName = "(name not recorded)"
            end
            table.insert(missing, {
                loc = tostring(loc),
                objId = tostring(objId),
                name = tostring(itemName),
            })
        end
    end

    return missing
end

function inv.set.reportMissingCache(priorityName, level)
    local targetLevel = tostring(invSetResolveTargetLevel(level))
    dbot.info("No cached '@G" .. tostring(priorityName) .. "@W' set exists for wearable level @G" ..
        targetLevel .. "@W.")
end

function inv.set.getCachedChangeCount(priorityName, level)
    local targetLevel = tostring(invSetResolveTargetLevel(level))
    local setData = inv.set.table[priorityName] and inv.set.table[priorityName][targetLevel] or nil
    if setData == nil or setData.equipment == nil then
        return nil, targetLevel
    end

    local wornByLoc = {}
    for objId, _ in pairs(inv.items.table or {}) do
        local location = tostring(inv.items.getStatField(objId, invStatFieldLocation) or "")
        local resolvedSlot = inv.items.resolveWearSlot(location)
        local wornLoc = (resolvedSlot ~= invItemLocWorn) and resolvedSlot or nil
        if wornLoc then
            wornByLoc[wornLoc] = tostring(objId)
        end
    end

    local changes = 0
    for _, loc in ipairs(inv.set.wearableLocations or {}) do
        local desiredObjId = setData.equipment[loc]
        if desiredObjId then
            local currentObjId = wornByLoc[loc]
            if tostring(desiredObjId) ~= tostring(currentObjId or "") then
                changes = changes + 1
            end
        end
    end

    return changes, targetLevel, setData
end

function inv.set.wearCached(priorityName, level, endTag)
    if priorityName == nil or priorityName == "" then
        dbot.warn("Usage: dinv set wear cache [priority] [level]")
        if endTag then
            return inv.tags.stop(invTagsSet, endTag, DRL_RET_INVALID_PARAM)
        end
        return DRL_RET_INVALID_PARAM
    end

    local targetLevel = tostring(invSetResolveTargetLevel(level))
    local setData = inv.set.table[priorityName] and inv.set.table[priorityName][targetLevel] or nil
    if setData == nil or setData.equipment == nil then
        inv.set.reportMissingCache(priorityName, targetLevel)
        if endTag then
            return inv.tags.stop(invTagsSet, endTag, DRL_RET_MISSING_ENTRY)
        end
        return DRL_RET_MISSING_ENTRY
    end

    local missing = invSetGetMissingCachedItems(setData)
    if #missing > 0 then
        dbot.warn("Cached set '" .. priorityName .. "' at level " .. targetLevel .. " cannot be worn.")
        dbot.warn("Missing cached items:")
        for _, entry in ipairs(missing) do
            dbot.warn(string.format("  %-10s %s [%s]", entry.loc .. ":", entry.name, entry.objId))
        end
        dbot.warn("No equipment was changed.")
        dbot.info("Run @Gdinv set wear " .. priorityName .. " " .. targetLevel ..
            "@W to calculate and wear a current set.")
        if endTag then
            return inv.tags.stop(invTagsSet, endTag, DRL_RET_MISSING_ENTRY)
        end
        return DRL_RET_MISSING_ENTRY
    end

    return inv.set.wear(priorityName, tonumber(targetLevel), endTag, { cached = true })
end

function inv.set.test(priorityName, mode, endTag)
    local normalizedMode = tostring(mode or ""):lower()
    if priorityName == nil or priorityName == "" or (normalizedMode ~= "cache" and normalizedMode ~= "live") then
        dbot.warn("Usage: dinv set test <priority> <cache|live>")
        if endTag then
            return inv.tags.stop(invTagsSet, endTag, DRL_RET_INVALID_PARAM)
        end
        return DRL_RET_INVALID_PARAM
    end

    if not (inv.priority and inv.priority.exists and inv.priority.exists(priorityName)) then
        dbot.warn("Priority '" .. tostring(priorityName) .. "' does not exist.")
        if endTag then
            return inv.tags.stop(invTagsSet, endTag, DRL_RET_MISSING_ENTRY)
        end
        return DRL_RET_MISSING_ENTRY
    end

    local wearableLevel = tonumber((dbot.gmcp.getWearableLevel and dbot.gmcp.getWearableLevel())
        or (dbot.gmcp.getLevel and dbot.gmcp.getLevel()) or 1) or 1
    local baseLevel = tonumber((dbot.gmcp.getLevel and dbot.gmcp.getLevel()) or wearableLevel) or wearableLevel
    local debugEnabled = inv.levelup and inv.levelup.getDebug and inv.levelup.getDebug()

    local count = nil
    local effectiveMode = normalizedMode

    if debugEnabled then
        dbot.printRaw(string.format(
            "@D[DINV DEBUG] set test: priority='@Y%s@D', mode='@W%s@D', testLevel=@Y%d@D, wearableLevel=@Y%d@D, baseLevel=@Y%d@D.@w",
            tostring(priorityName), tostring(normalizedMode), tonumber(baseLevel) or 0, tonumber(wearableLevel) or 0, tonumber(baseLevel) or 0))
    end

    if normalizedMode == "cache" then
        local targetLevel = tostring(wearableLevel)
        local staleReason = inv.set.getStaleReason(priorityName, targetLevel)
        if staleReason then
            dbot.warn("Cached set for '" .. priorityName .. "' is stale: " .. staleReason .. ". Continuing with cached results.")
        end
        if debugEnabled then
            dbot.printRaw(string.format(
                "@D[DINV DEBUG] set test cache: using saved set for '@Y%s@D' at wearable level @Y%d@D.@w",
                tostring(priorityName), tonumber(targetLevel) or 0))
        end
        count = inv.set.getCachedChangeCount(priorityName, targetLevel)
        if count == nil then
            inv.set.reportMissingCache(priorityName, targetLevel)
            if endTag then
                return inv.tags.stop(invTagsSet, endTag, DRL_RET_MISSING_ENTRY)
            end
            return DRL_RET_MISSING_ENTRY
        end
    end

    if effectiveMode == "live" then
        local liveReason = nil
        count, liveReason = inv.analyze.getLiveUpgradeCount(priorityName, tonumber(baseLevel), tonumber(wearableLevel))
        if count == nil then
            dbot.warn("Unable to calculate live set changes: " .. tostring(liveReason or "unknown error"))
            if endTag then
                return inv.tags.stop(invTagsSet, endTag, DRL_RET_MISSING_ENTRY)
            end
            return DRL_RET_MISSING_ENTRY
        end
    end

    if tonumber(count) and tonumber(count) > 0 then
        dbot.info(string.format(
            "New item upgrades are available for '@G%s@W' (@G%s@W): @Y%d@W pieces ready to equip.",
            priorityName, effectiveMode, tonumber(count) or 0))
    else
        dbot.info(string.format(
            "No additional item upgrades available for '@G%s@W' (@G%s@W).",
            priorityName, effectiveMode))
    end

    if endTag then
        return inv.tags.stop(invTagsSet, endTag, DRL_RET_SUCCESS)
    end
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Create and Wear
----------------------------------------------------------------------------------------------------

function inv.set.createAndWear(priorityName, level, intensity, endTag, wearOptions)
    local targetLevel = invSetResolveTargetLevel(level)
    local retval = inv.set.create(priorityName, targetLevel, nil, intensity)
    if retval ~= DRL_RET_SUCCESS then
        if endTag then
            return inv.tags.stop(invTagsSet, endTag, retval)
        end
        return retval
    end

    local setData = inv.set.table[priorityName] and inv.set.table[priorityName][tostring(targetLevel)] or nil
    if setData and inv.analyze and inv.analyze.recordSet then
        local analysisRetval = inv.analyze.recordSet(priorityName, invSetResolveBaseLevel(targetLevel), setData)
        if analysisRetval ~= DRL_RET_SUCCESS then
            dbot.warn("Live set was created, but its analysis entry could not be saved.")
        end
    end

    return inv.set.wear(priorityName, targetLevel, endTag, wearOptions)
end

----------------------------------------------------------------------------------------------------
-- Check if item is in set
----------------------------------------------------------------------------------------------------

function inv.set.isItemInSet(objId, equipSet)
    if equipSet == nil or objId == nil then
        return false
    end

    objId = tonumber(objId)
    local items = equipSet.equipment or equipSet

    for _, itemId in pairs(items) do
        if tonumber(itemId) == objId then
            return true
        end
    end

    return false
end

dbot.debug("inv.set module loaded", "inv.set")
