----------------------------------------------------------------------------------------------------
-- INV Weapon Module
-- Weapon-specific equipment sets based on damage types
----------------------------------------------------------------------------------------------------

inv.weapon = {}
inv.weapon.currentPriority = nil
inv.weapon.requestedDamTypes = {}
inv.weapon.availableDamTypeMap = {}
inv.weapon.lastSelectedDamType = nil
inv.weapon.anyCycleUsed = {}

local function splitDamTypes(damTypes)
    local out = {}
    for dam in tostring(damTypes or ""):gmatch("[^,%s]+") do
        local normalized = string.lower(tostring(dam))
        if normalized ~= "" then
            table.insert(out, normalized)
        end
    end
    return out
end

local function getWeaponDamType(objId)
    local damType = inv.items.getStatField(objId, invStatFieldDamtype)
        or inv.items.getStatField(objId, invStatFieldInflicts)
        or ""
    return string.lower(tostring(damType))
end

local function getCurrentWearableLevel()
    if dbot and dbot.gmcp and dbot.gmcp.getWearableLevel then
        return tonumber(dbot.gmcp.getWearableLevel()) or 1
    end
    if dbot and dbot.gmcp and dbot.gmcp.getLevel then
        return tonumber(dbot.gmcp.getLevel()) or 1
    end
    return 1
end

local function isWeaponWearable(objId, wearableLevel)
    local itemLevel = tonumber(inv.items.getStatField(objId, invStatFieldLevel)) or 0
    return itemLevel <= (tonumber(wearableLevel) or 1)
end

local function getBestWeaponForDamType(priorityName, damType)
    local best = nil
    local wearableLevel = getCurrentWearableLevel()
    for objId, _ in pairs(inv.items.table or {}) do
        local itemType = inv.items.getStatField(objId, invStatFieldType) or ""
        if itemType == invItemTypeWeapon and isWeaponWearable(objId, wearableLevel) then
            local weaponDamType = getWeaponDamType(objId)
            if weaponDamType ~= "" and string.find(weaponDamType, damType, 1, true) then
                local level = tonumber(inv.items.getStatField(objId, invStatFieldLevel)) or 0
                local score = 0
                if priorityName and priorityName ~= "" and inv.priority.exists and inv.priority.exists(priorityName) then
                    score = tonumber(inv.score.getItemScore(objId, priorityName, nil)) or 0
                end
                if (not best)
                    or level > best.level
                    or (level == best.level and score > best.score)
                    or (level == best.level and score == best.score and tostring(objId) > tostring(best.id)) then
                    best = { id = tostring(objId), level = level, score = score, damType = weaponDamType }
                end
            end
        end
    end
    return best
end

local function getCurrentWieldedId()
    local function isPrimaryWieldLoc(rawLoc)
        local loc = tostring(rawLoc or ""):lower()
        return loc == "wielded" or loc == "wield" or loc == "24"
    end
    for objId, _ in pairs(inv.items.table or {}) do
        local wornLoc = inv.items.getStatField(objId, invStatFieldWorn) or ""
        if isPrimaryWieldLoc(wornLoc) then
            return tostring(objId)
        end
    end
    return nil
end

local function getCurrentSecondWieldId()
    local function isSecondWieldLoc(rawLoc)
        local loc = tostring(rawLoc or ""):lower()
        return loc == "second" or loc == "25"
    end
    for objId, _ in pairs(inv.items.table or {}) do
        local wornLoc = inv.items.getStatField(objId, invStatFieldWorn) or ""
        if isSecondWieldLoc(wornLoc) then
            return tostring(objId)
        end
    end
    return nil
end

local function hasDualWieldAvailable(wearableLevel)
    local level = tonumber(wearableLevel) or getCurrentWearableLevel()
    local dualWieldAvailable = false

    if dbot.ability and dbot.ability.isAvailable then
        dualWieldAvailable = dbot.ability.isAvailable("dual wield", level)
    end

    if not dualWieldAvailable then
        local function isHandsLoc(rawLoc)
            local loc = tostring(rawLoc or ""):lower()
            return loc == "hands" or loc == "18"
        end
        for objId, _ in pairs(inv.items.table or {}) do
            local wornLoc = inv.items.getStatField(objId, invStatFieldWorn) or ""
            if isHandsLoc(wornLoc) then
                local name = (inv.items.getStatField(objId, invStatFieldName) or ""):lower()
                if name:find("aardwolf gloves of dexterity", 1, true) then
                    dualWieldAvailable = true
                    break
                end

                local affects = inv.items.getStatField(objId, invStatFieldAffects) or ""
                local flags = inv.items.getStatField(objId, invStatFieldFlags) or ""
                local combined = (affects .. " " .. flags):lower()
                if combined:find("dualwield", 1, true) or combined:find("dual wield", 1, true) then
                    dualWieldAvailable = true
                    break
                end
            end
        end
    end

    if dualWieldAvailable and inv.weapon.currentPriority and inv.priority and inv.priority.locIsAllowed then
        dualWieldAvailable = inv.priority.locIsAllowed("second", inv.weapon.currentPriority, level)
    end

    return dualWieldAvailable
end

local function canPairWithCurrentOffhand(primaryObjId, offhandObjId, wearableLevel)
    if not offhandObjId then
        return true
    end

    if tostring(primaryObjId) == tostring(offhandObjId) then
        return false
    end

    if not hasDualWieldAvailable(wearableLevel) then
        return false
    end

    local subclass = ""
    if dbot.gmcp and dbot.gmcp.getClass then
        local _, sc = dbot.gmcp.getClass()
        subclass = tostring(sc or "")
    end
    if subclass:lower() == "soldier" then
        return true
    end

    local primaryWeight = tonumber(inv.items.getStatField(primaryObjId, invStatFieldWeight)) or 0
    local offhandWeight = tonumber(inv.items.getStatField(offhandObjId, invStatFieldWeight)) or 0
    if primaryWeight == 0 and offhandWeight == 0 then
        return true
    end
    return primaryWeight >= (offhandWeight * 2)
end

local function ensureItemAvailable(objId)
    if not objId then
        return
    end
    if inv.items.isWorn(objId) then
        return
    end

    local containerId = inv.items.normalizeContainerId and inv.items.normalizeContainerId(inv.items.getStatField(objId, invStatFieldContainer))
    local location = (inv.items.getStatField(objId, invStatFieldLocation) or ""):lower()

    if containerId ~= nil then
        inv.items.sendActionCommand("dinv get " .. tostring(objId))
    elseif location ~= "" and location ~= "inventory" then
        inv.items.sendActionCommand("dinv get " .. tostring(objId))
    end
end

local function equipWeaponForDamType(priorityName, damType)
    local wearableLevel = getCurrentWearableLevel()
    local currentSecondId = getCurrentSecondWieldId()
    local best = getBestWeaponForDamType(priorityName, damType)
    local selected = best

    if selected and not canPairWithCurrentOffhand(selected.id, currentSecondId, wearableLevel) then
        selected = nil
        for objId, _ in pairs(inv.items.table or {}) do
            local itemType = inv.items.getStatField(objId, invStatFieldType) or ""
            if itemType == invItemTypeWeapon and isWeaponWearable(objId, wearableLevel) then
                local weaponDamType = getWeaponDamType(objId)
                if weaponDamType ~= "" and string.find(weaponDamType, damType, 1, true)
                   and canPairWithCurrentOffhand(objId, currentSecondId, wearableLevel) then
                    local level = tonumber(inv.items.getStatField(objId, invStatFieldLevel)) or 0
                    local score = 0
                    if priorityName and priorityName ~= "" and inv.priority.exists and inv.priority.exists(priorityName) then
                        score = tonumber(inv.score.getItemScore(objId, priorityName, nil)) or 0
                    end
                    if (not selected)
                        or level > selected.level
                        or (level == selected.level and score > selected.score)
                        or (level == selected.level and score == selected.score and tostring(objId) > tostring(selected.id)) then
                        selected = { id = tostring(objId), level = level, score = score, damType = weaponDamType }
                    end
                end
            end
        end
    end

    if not selected then
        return DRL_RET_MISSING_ENTRY, nil
    end

    local currentWieldedId = getCurrentWieldedId()
    if currentWieldedId == selected.id then
        return DRL_RET_SUCCESS, selected
    end

    if currentWieldedId and currentWieldedId ~= selected.id then
        inv.items.sendActionCommand("remove " .. tostring(currentWieldedId))
    end

    ensureItemAvailable(selected.id)
    inv.items.wearItem(selected.id, "wielded")

    if currentWieldedId and currentWieldedId ~= selected.id then
        local storeContainer = inv.items.resolveStoreContainer and inv.items.resolveStoreContainer(currentWieldedId) or nil
        if storeContainer and storeContainer ~= "" then
            inv.items.sendActionCommand("put " .. tostring(currentWieldedId) .. " " .. tostring(storeContainer))
        else
            inv.items.store("id " .. tostring(currentWieldedId))
        end
    end

    return DRL_RET_SUCCESS, selected
end

local function getAllWeaponDamTypeData()
    local data = {}
    local wearableLevel = getCurrentWearableLevel()
    for objId, _ in pairs(inv.items.table or {}) do
        local itemType = inv.items.getStatField(objId, invStatFieldType) or ""
        if itemType == invItemTypeWeapon and isWeaponWearable(objId, wearableLevel) then
            local damType = getWeaponDamType(objId)
            if damType ~= "" then
                local level = tonumber(inv.items.getStatField(objId, invStatFieldLevel)) or 0
                local rec = data[damType]
                if not rec then
                    rec = { count = 0, bestId = tostring(objId), bestLevel = level }
                    data[damType] = rec
                end
                rec.count = rec.count + 1
                if level > (rec.bestLevel or 0) then
                    rec.bestLevel = level
                    rec.bestId = tostring(objId)
                end
            end
        end
    end
    return data
end

local function orderedDamTypesFromData(data)
    local ordered = {}
    for damType, _ in pairs(data or {}) do
        table.insert(ordered, damType)
    end
    table.sort(ordered)
    return ordered
end

function inv.weapon.use(priorityName, damTypes, endTag)
    if string.lower(tostring(priorityName or "")) == "any" then
        dbot.warn("Priority name 'any' is reserved. Use: dinv weapon next any")
        return inv.tags.stop(invTagsWeapon, endTag, DRL_RET_INVALID_PARAM)
    end

    if not inv.priority.exists(priorityName) then
        dbot.warn("Priority '" .. tostring(priorityName) .. "' does not exist")
        return inv.tags.stop(invTagsWeapon, endTag, DRL_RET_MISSING_ENTRY)
    end

    local requested = splitDamTypes(damTypes)
    if #requested == 0 then
        dbot.warn("Usage: dinv weapon <priority> <damtype1> [damtype2 ...]")
        return inv.tags.stop(invTagsWeapon, endTag, DRL_RET_INVALID_PARAM)
    end

    inv.weapon.currentPriority = priorityName
    inv.weapon.requestedDamTypes = requested
    inv.weapon.availableDamTypeMap = {}
    inv.weapon.lastSelectedDamType = nil

    dbot.info("Setting weapon damage types to '" .. table.concat(requested, " ") .. "' for priority '" .. priorityName .. "'")

    for _, damType in ipairs(requested) do
        local best = getBestWeaponForDamType(priorityName, damType)
        if best then
            inv.weapon.availableDamTypeMap[damType] = true
        else
            dbot.warn("No persisted weapon found for damage type '" .. damType .. "'")
        end
    end

    local retval = inv.weapon.next(endTag)
    return retval
end

function inv.weapon.next(endTag, useAnyCycle)
    if useAnyCycle then
        local data = getAllWeaponDamTypeData()
        local ordered = orderedDamTypesFromData(data)
        if #ordered == 0 then
            dbot.warn("No persisted weapon damage types found.")
            return inv.tags.stop(invTagsWeapon, endTag, DRL_RET_MISSING_ENTRY)
        end

        local selectedDamType = nil
        for _, damType in ipairs(ordered) do
            if not inv.weapon.anyCycleUsed[damType] then
                selectedDamType = damType
                break
            end
        end

        if not selectedDamType then
            inv.weapon.anyCycleUsed = {}
            selectedDamType = ordered[1]
        end

        local retval, best = equipWeaponForDamType(nil, selectedDamType)
        if retval ~= DRL_RET_SUCCESS then
            dbot.warn("No weapon available for damage type '" .. selectedDamType .. "'")
            return inv.tags.stop(invTagsWeapon, endTag, retval)
        end

        inv.weapon.anyCycleUsed[selectedDamType] = true
        dbot.info("Cycling (any): wielding '" .. (inv.items.getStatField(best.id, invStatFieldName) or best.id) ..
                  "' for damage type '" .. selectedDamType .. "'")
        return inv.tags.stop(invTagsWeapon, endTag, DRL_RET_SUCCESS)
    end

    if inv.weapon.currentPriority == nil or not inv.priority.exists(inv.weapon.currentPriority) then
        dbot.warn("No active weapon priority set. Use 'dinv weapon <priority> <damtypes>' first.")
        return inv.tags.stop(invTagsWeapon, endTag, DRL_RET_INVALID_PARAM)
    end

    if #inv.weapon.requestedDamTypes == 0 then
        dbot.warn("No configured weapon damage types. Use 'dinv weapon <priority> <damtypes>' first.")
        return inv.tags.stop(invTagsWeapon, endTag, DRL_RET_INVALID_PARAM)
    end

    local currentWieldedId = getCurrentWieldedId()
    local currentDamType = currentWieldedId and getWeaponDamType(currentWieldedId) or ""

    local currentIndex = nil
    for i, damType in ipairs(inv.weapon.requestedDamTypes) do
        if currentDamType ~= "" and string.find(currentDamType, damType, 1, true) then
            currentIndex = i
            break
        end
    end

    local startIndex = currentIndex or 0
    local selectedDamType = nil
    for offset = 1, #inv.weapon.requestedDamTypes do
        local idx = ((startIndex + offset - 1) % #inv.weapon.requestedDamTypes) + 1
        local candidateDamType = inv.weapon.requestedDamTypes[idx]
        if inv.weapon.availableDamTypeMap[candidateDamType] then
            selectedDamType = candidateDamType
            break
        end
    end

    if not selectedDamType then
        dbot.warn("None of the configured damage types have matching persisted weapons.")
        return inv.tags.stop(invTagsWeapon, endTag, DRL_RET_MISSING_ENTRY)
    end

    local retval, best = equipWeaponForDamType(inv.weapon.currentPriority, selectedDamType)
    if retval ~= DRL_RET_SUCCESS then
        dbot.warn("No weapon available for damage type '" .. selectedDamType .. "'")
        return inv.tags.stop(invTagsWeapon, endTag, retval)
    end

    inv.weapon.lastSelectedDamType = selectedDamType
    dbot.info("Wielding '" .. (inv.items.getStatField(best.id, invStatFieldName) or best.id) .. "' for damage type '" .. selectedDamType .. "'")
    return inv.tags.stop(invTagsWeapon, endTag, DRL_RET_SUCCESS)
end

function inv.weapon.listDamTypes(endTag)
    local data = getAllWeaponDamTypeData()
    local ordered = orderedDamTypesFromData(data)
    if #ordered == 0 then
        dbot.warn("No persisted weapon damage types found.")
        return inv.tags.stop(invTagsWeapon, endTag, DRL_RET_MISSING_ENTRY)
    end

    dbot.print("@WAvailable weapon damage types in persistence:@w")
    for _, damType in ipairs(ordered) do
        local rec = data[damType] or {}
        local bestName = inv.items.getStatField(rec.bestId, invStatFieldColorName)
            or inv.items.getStatField(rec.bestId, invStatFieldName)
            or "Unknown"
        dbot.print(string.format("  @C%-14s@W : @Y%d@W weapon(s), best lv @G%d@W (@C%s@W / %s)",
            damType, tonumber(rec.count) or 0, tonumber(rec.bestLevel) or 0, tostring(bestName), tostring(rec.bestId or "?")))
    end
    return inv.tags.stop(invTagsWeapon, endTag, DRL_RET_SUCCESS)
end

dbot.debug("inv.weapon module loaded", "inv.weapon")
