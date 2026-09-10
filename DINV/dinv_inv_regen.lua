----------------------------------------------------------------------------------------------------
-- INV Regen Module
-- Auto-wear regen ring before server tick (gmcp.comm.tick) and restore after tick
----------------------------------------------------------------------------------------------------

inv.regen = inv.regen or {}
inv.regen.wearableLoc = "finger"
inv.regen.pretickSeconds = 25  -- 5 seconds before 30-second tick
inv.regen.posttickDelay = 0.5  -- 0.5 seconds after tick
inv.regen.pretickTimerId = nil
inv.regen.posttickTimerId = nil
inv.regen.tickHandlerId = nil
inv.regen.isWornForTick = false

local function clearPretickTimer()
    if inv.regen.pretickTimerId and killTimer then
        pcall(killTimer, inv.regen.pretickTimerId)
    end
    inv.regen.pretickTimerId = nil
end

local function clearPosttickTimer()
    if inv.regen.posttickTimerId and killTimer then
        pcall(killTimer, inv.regen.posttickTimerId)
    end
    inv.regen.posttickTimerId = nil
end

local function clearAllTimers()
    clearPretickTimer()
    clearPosttickTimer()
end

function inv.regen.getWornFingerRings()
    local rings = { lfinger = nil, rfinger = nil }
    for objId, _ in pairs(inv.items.table or {}) do
        local wornLoc = tostring(inv.items.getStatField(objId, invStatFieldWorn) or ""):lower()
        if wornLoc == invWearLocFinger1 or wornLoc == "lfinger" or wornLoc == "finger1" or wornLoc == "19" then
            rings.lfinger = tostring(objId)
        elseif wornLoc == invWearLocFinger2 or wornLoc == "rfinger" or wornLoc == "finger2" or wornLoc == "20" then
            rings.rfinger = tostring(objId)
        end
    end
    return rings
end

function inv.regen.isInInventory(objId)
    if not objId or not inv.items or not inv.items.table then
        return false
    end
    local item = inv.items.table[tostring(objId)]
    if not item then
        return false
    end
    if inv.items.isWorn and inv.items.isWorn(objId) then
        return false
    end
    local loc = tostring(inv.items.getStatField(objId, invStatFieldLocation) or ""):lower()
    local invLoc = tostring(invItemLocInventory or "inventory"):lower()
    return loc == invLoc or loc == "inventory" or loc == ""
end

function inv.regen.getHpThreshold()
    if inv.config and inv.config.getRegenHpThreshold then
        return inv.config.getRegenHpThreshold()
    end
    if inv.config and inv.config.get then
        return tonumber(inv.config.get("regenHpThreshold")) or 80
    end
    return 80
end

function inv.regen.getHpPercent()
    local curHp = nil
    local maxHp = nil

    if dbot and dbot.gmcp and dbot.gmcp.getHp then
        local c, m = dbot.gmcp.getHp()
        if c and m and m > 0 then
            curHp = c
            maxHp = m
        end
    end

    if not curHp or not maxHp or maxHp <= 0 then
        if gmcp and gmcp.char then
            if gmcp.char.vitals then
                curHp = curHp or tonumber(gmcp.char.vitals.hp)
                maxHp = maxHp or tonumber(gmcp.char.vitals.maxhp)
            end
            if gmcp.char.maxstats then
                maxHp = maxHp or tonumber(gmcp.char.maxstats.maxhp)
            end
        end
    end

    if curHp and maxHp and maxHp > 0 then
        return (curHp / maxHp) * 100, curHp, maxHp
    end
    return nil, nil, nil
end

function inv.regen.getColorName(objId)
    local strId = tostring(objId)
    if not inv.items then return strId end

    local colorName = inv.items.getStatField and inv.items.getStatField(strId, "colorname")
    if colorName and colorName ~= "" then
        return colorName
    end

    if invStatFieldColorName and inv.items.getStatField then
        colorName = inv.items.getStatField(strId, invStatFieldColorName)
        if colorName and colorName ~= "" then
            return colorName
        end
    end

    local name = inv.items.getStatField and inv.items.getStatField(strId, invStatFieldName or "name")
    if name and name ~= "" then
        return name
    end

    if inv.items.table and inv.items.table[strId] and inv.items.table[strId].stats then
        local st = inv.items.table[strId].stats
        if st.colorname and st.colorname ~= "" then return st.colorname end
        if st.colorName and st.colorName ~= "" then return st.colorName end
        if st.name and st.name ~= "" then return st.name end
    end

    return strId
end

function inv.regen.selectBestRegenRing()
    local bestId = nil
    local bestScore = -1
    local bestLevel = -1
    local bestName = ""
    local defaultPriority = (inv.priority and inv.priority.getDefault and inv.priority.getDefault()) or nil

    for objId, _ in pairs(inv.items.table or {}) do
        local affects = tostring(inv.items.getStatField(objId, invStatFieldAffects) or ""):lower()
        local wearable = tostring(inv.items.getStatField(objId, invStatFieldWearable) or ""):lower()
        if string.find(affects, "regeneration", 1, true) and
           string.find(wearable, inv.regen.wearableLoc, 1, true) then
            local idStr = tostring(objId)
            local score = 0
            if defaultPriority and inv.score and inv.score.item then
                local s = inv.score.item(idStr, defaultPriority)
                score = tonumber(s) or 0
            end
            local level = tonumber(inv.items.getStatField(idStr, invStatFieldLevel)) or 0
            local colorName = inv.regen.getColorName(idStr)

            local isBetter = false
            if bestId == nil then
                isBetter = true
            elseif score > bestScore then
                isBetter = true
            elseif score == bestScore then
                if level > bestLevel then
                    isBetter = true
                elseif level == bestLevel then
                    local numNew = tonumber(idStr) or 0
                    local numBest = tonumber(bestId) or 0
                    if numNew < numBest then
                        isBetter = true
                    end
                end
            end

            if isBetter then
                bestId = idStr
                bestScore = score
                bestLevel = level
                bestName = colorName
            end
        end
    end

    return bestId, bestName
end

function inv.regen.onPretick()
    clearPretickTimer()
    if not inv.config or not inv.config.isRegenEnabled or not inv.config.isRegenEnabled() then
        return DRL_RET_SUCCESS
    end

    local pinnedId = tostring(inv.config.table.regenPinnedObjId or inv.config.table.regenNewObjId or 0)
    if pinnedId == "0" or pinnedId == "" then
        local bestId = inv.regen.selectBestRegenRing()
        if bestId then
            pinnedId = tostring(bestId)
            inv.config.table.regenPinnedObjId = pinnedId
            inv.config.table.regenNewObjId = pinnedId
            if inv.config.save then inv.config.save() end
        else
            return DRL_RET_MISSING_ENTRY
        end
    end

    if inv.config.table.regenPreWorn == true or (inv.items.isWorn and inv.items.isWorn(pinnedId)) then
        return DRL_RET_SUCCESS
    end

    local threshold = inv.regen.getHpThreshold()
    local hpPct, curHp, maxHp = inv.regen.getHpPercent()
    if hpPct and threshold and hpPct >= threshold then
        if dbot and dbot.debug then
            dbot.debug(string.format("HP is at %.1f%% (>= %d%% threshold); skipping regen ring wear", hpPct, threshold), "inv.regen")
        end
        return DRL_RET_SUCCESS
    end

    if not inv.regen.isInInventory(pinnedId) then
        if dbot and dbot.debug then
            dbot.debug("Pinned regen ring " .. pinnedId .. " not in inventory; skipping pre-tick wear", "inv.regen")
        end
        return DRL_RET_MISSING_ENTRY
    end

    local rings = inv.regen.getWornFingerRings()
    local targetLoc = nil
    local displacedId = nil

    if rings.lfinger == nil then
        targetLoc = invWearLocFinger1 or "lfinger"
    elseif rings.rfinger == nil then
        targetLoc = invWearLocFinger2 or "rfinger"
    else
        local lScore = 0
        local rScore = 0
        local defaultPriority = (inv.priority and inv.priority.getDefault and inv.priority.getDefault()) or nil
        if defaultPriority and inv.score and inv.score.item then
            local l = inv.score.item(rings.lfinger, defaultPriority)
            local r = inv.score.item(rings.rfinger, defaultPriority)
            lScore = tonumber(l) or 0
            rScore = tonumber(r) or 0
        end

        if lScore < rScore then
            displacedId = rings.lfinger
            targetLoc = invWearLocFinger1 or "lfinger"
        elseif rScore < lScore then
            displacedId = rings.rfinger
            targetLoc = invWearLocFinger2 or "rfinger"
        else
            local lLevel = 0
            local rLevel = 0
            if inv.items and inv.items.getStatField then
                lLevel = tonumber(inv.items.getStatField(rings.lfinger, invStatFieldLevel)) or 0
                rLevel = tonumber(inv.items.getStatField(rings.rfinger, invStatFieldLevel)) or 0
            end
            if lLevel <= rLevel then
                displacedId = rings.lfinger
                targetLoc = invWearLocFinger1 or "lfinger"
            else
                displacedId = rings.rfinger
                targetLoc = invWearLocFinger2 or "rfinger"
            end
        end
    end

    if displacedId then
        inv.config.table.regenOrigObjId = displacedId
        inv.config.table.regenDisplacedLoc = targetLoc
        if inv.items.removeWornItem then
            inv.items.removeWornItem(displacedId)
        end
    else
        inv.config.table.regenOrigObjId = 0
        inv.config.table.regenDisplacedLoc = targetLoc
    end

    if inv.items.wearItem then
        inv.items.wearItem(pinnedId, targetLoc)
    end
    inv.regen.isWornForTick = true
    if dbot and dbot.debug then
        dbot.debug("Pre-tick: wearing regen ring " .. pinnedId .. " at " .. tostring(targetLoc), "inv.regen")
    end
    return DRL_RET_SUCCESS
end

function inv.regen.onPosttick()
    clearPosttickTimer()
    if not inv.config or not inv.config.isRegenEnabled or not inv.config.isRegenEnabled() then
        return DRL_RET_SUCCESS
    end

    if inv.config.table.regenPreWorn == true then
        return DRL_RET_SUCCESS
    end

    local pinnedId = tostring(inv.config.table.regenPinnedObjId or inv.config.table.regenNewObjId or 0)
    local origId = tostring(inv.config.table.regenOrigObjId or 0)
    local origLoc = inv.config.table.regenDisplacedLoc

    if pinnedId ~= "0" and inv.items.isWorn and inv.items.isWorn(pinnedId) then
        if inv.items.removeWornItem then
            inv.items.removeWornItem(pinnedId)
        end
    end

    if origId ~= "0" and origId ~= "" then
        if inv.items.wearItem then
            inv.items.wearItem(origId, origLoc)
        end
    end

    inv.config.table.regenOrigObjId = 0
    inv.config.table.regenDisplacedLoc = ""
    inv.regen.isWornForTick = false
    if dbot and dbot.debug then
        dbot.debug("Post-tick: removed regen ring and restored equipment", "inv.regen")
    end
    return DRL_RET_SUCCESS
end

function inv.regen.onServerTick()
    if not inv.config or not inv.config.isRegenEnabled or not inv.config.isRegenEnabled() then
        return DRL_RET_SUCCESS
    end

    clearPretickTimer()

    local pinnedId = tostring(inv.config.table.regenPinnedObjId or inv.config.table.regenNewObjId or 0)
    local isWorn = pinnedId ~= "0" and inv.items.isWorn and inv.items.isWorn(pinnedId)

    if inv.regen.isWornForTick or (isWorn and not inv.config.table.regenPreWorn) then
        clearPosttickTimer()
        if tempTimer then
            inv.regen.posttickTimerId = tempTimer(inv.regen.posttickDelay, function()
                inv.regen.posttickTimerId = nil
                inv.regen.onPosttick()
            end)
        else
            inv.regen.onPosttick()
        end
    end

    if tempTimer then
        inv.regen.pretickTimerId = tempTimer(inv.regen.pretickSeconds, function()
            inv.regen.pretickTimerId = nil
            inv.regen.onPretick()
        end)
    end

    return DRL_RET_SUCCESS
end

function inv.regen.armServerTick()
    -- GMCP server tick handler is centrally registered by DINV.triggers
    return DRL_RET_SUCCESS
end

function inv.regen.enable()
    local bestId, bestName = inv.regen.selectBestRegenRing()
    if not bestId then
        if dbot and dbot.warn then
            dbot.warn("No regeneration ring found to manage.")
        end
        return DRL_RET_MISSING_ENTRY
    end

    inv.config.setRegenEnabled(true)
    inv.config.table.regenPinnedObjId = tostring(bestId)
    inv.config.table.regenNewObjId = tostring(bestId)

    if inv.items.isWorn and inv.items.isWorn(bestId) then
        inv.config.table.regenPreWorn = true
        inv.config.table.regenHomeContainer = 0
        if inv.config.save then inv.config.save() end
        if dbot and dbot.info then
            dbot.info(string.format("Regen auto-swap enabled: %s@W (@Y%s@W) is already worn (pre-worn mode).", bestName, bestId))
        end
        inv.regen.armServerTick()
        return DRL_RET_SUCCESS
    end

    inv.config.table.regenPreWorn = false
    local container = inv.items.resolveStoreContainer and inv.items.resolveStoreContainer(bestId)
    if not container or container == "" or container == "0" then
        local loc = tostring(inv.items.getStatField(bestId, invStatFieldLocation) or "")
        local invLoc = tostring(invItemLocInventory or "inventory"):lower()
        if loc ~= "" and loc:lower() ~= invLoc and loc:lower() ~= "inventory" then
            container = loc
        end
    end
    inv.config.table.regenHomeContainer = container or 0
    if inv.config.save then inv.config.save() end

    if not inv.regen.isInInventory(bestId) then
        if dbot and dbot.info then
            dbot.info(string.format("Retrieving regeneration ring to inventory: %s@W (@Y%s@W)", bestName, bestId))
        end
        if inv.items.get then
            inv.items.get("id " .. tostring(bestId))
        end
    else
        if dbot and dbot.info then
            dbot.info(string.format("Regen auto-swap enabled: %s@W (@Y%s@W) pinned in inventory.", bestName, bestId))
        end
    end

    inv.regen.armServerTick()
    return DRL_RET_SUCCESS
end

function inv.regen.disable()
    clearAllTimers()
    local pinnedId = tostring(inv.config.table.regenPinnedObjId or inv.config.table.regenNewObjId or 0)
    local isPreWorn = inv.config.table.regenPreWorn == true
    local homeContainer = inv.config.table.regenHomeContainer
    local origId = tostring(inv.config.table.regenOrigObjId or 0)
    local origLoc = inv.config.table.regenDisplacedLoc

    if not isPreWorn and pinnedId ~= "0" and inv.items.isWorn and inv.items.isWorn(pinnedId) then
        if inv.items.removeWornItem then
            inv.items.removeWornItem(pinnedId)
        end
    end

    if not isPreWorn and origId ~= "0" and origId ~= "" and inv.items.wearItem then
        local origIsWorn = inv.items.isWorn and inv.items.isWorn(origId)
        if not origIsWorn then
            inv.items.wearItem(origId, origLoc)
        end
    end

    if not isPreWorn and pinnedId ~= "0" then
        if homeContainer and homeContainer ~= 0 and homeContainer ~= "0" and homeContainer ~= "" then
            if inv.items.sendActionCommand then
                inv.items.sendActionCommand("put " .. pinnedId .. " " .. tostring(homeContainer))
            elseif inv.items.storeItem then
                inv.items.storeItem(pinnedId)
            end
        elseif inv.items.storeItem then
            inv.items.storeItem(pinnedId)
        end
    end

    inv.config.table.regenPinnedObjId = 0
    inv.config.table.regenNewObjId = 0
    inv.config.table.regenOrigObjId = 0
    inv.config.table.regenDisplacedLoc = ""
    inv.config.table.regenPreWorn = false
    inv.config.table.regenHomeContainer = 0
    inv.config.setRegenEnabled(false)
    if inv.config.save then inv.config.save() end

    if dbot and dbot.info then
        dbot.info("Regen ring auto-swap disabled and item returned to storage.")
    end
    return DRL_RET_SUCCESS
end

function inv.regen.init()
    if not inv.config or not inv.config.isRegenEnabled or not inv.config.isRegenEnabled() then
        return DRL_RET_SUCCESS
    end

    inv.regen.armServerTick()

    local pinnedId = tostring(inv.config.table.regenPinnedObjId or inv.config.table.regenNewObjId or 0)
    if pinnedId ~= "0" and pinnedId ~= "" then
        if inv.items.isWorn and inv.items.isWorn(pinnedId) then
            -- Pre-worn or currently worn
        elseif not inv.regen.isInInventory(pinnedId) then
            if inv.items.get then
                inv.items.get("id " .. pinnedId)
            end
        end
    else
        local bestId = inv.regen.selectBestRegenRing()
        if bestId then
            inv.config.table.regenPinnedObjId = tostring(bestId)
            inv.config.table.regenNewObjId = tostring(bestId)
            if inv.config.save then inv.config.save() end
            if not inv.items.isWorn(bestId) and not inv.regen.isInInventory(bestId) then
                if inv.items.get then
                    inv.items.get("id " .. tostring(bestId))
                end
            end
        end
    end

    return DRL_RET_SUCCESS
end

function inv.regen.onSleep()
    return DRL_RET_SUCCESS
end

function inv.regen.onWake()
    if inv.config and inv.config.isRegenEnabled and inv.config.isRegenEnabled() and inv.regen.isWornForTick then
        return inv.regen.onPosttick()
    end
    return DRL_RET_SUCCESS
end

function inv.regen.onInvmon(action, objId, wearLoc)
    return DRL_RET_SUCCESS
end

if dbot and dbot.debug then
    dbot.debug("inv.regen module loaded", "inv.regen")
end
