----------------------------------------------------------------------------------------------------
-- INV Regen Module
-- Auto-wear regen ring when sleeping
----------------------------------------------------------------------------------------------------

inv.regen = {}
inv.regen.wearableLoc = "finger"

function inv.regen.init()
    -- Initialize regen module
    return DRL_RET_SUCCESS
end

function inv.regen.onSleep()
    if not inv.config.isRegenEnabled() then
        return DRL_RET_SUCCESS
    end
    local regenId = nil
    local regenName = "regen item"

    for objId, item in pairs(inv.items.table or {}) do
        local affects = inv.items.getStatField(objId, invStatFieldAffects) or ""
        local wearable = inv.items.getStatField(objId, invStatFieldWearable) or ""
        if string.find(string.lower(tostring(affects)), "regeneration", 1, true) and
           string.find(string.lower(tostring(wearable)), inv.regen.wearableLoc, 1, true) then
            regenId = objId
            regenName = inv.items.getStatField(objId, invStatFieldName) or regenName
            break
        end
    end

    if regenId == nil then
        dbot.info("No regeneration item found to auto-wear.")
        return DRL_RET_MISSING_ENTRY
    end

    for objId, item in pairs(inv.items.table or {}) do
        local wornLoc = inv.items.getStatField(objId, invStatFieldWorn)
        if wornLoc == inv.regen.wearableLoc then
            inv.config.table.regenOrigObjId = objId
            break
        end
    end

    inv.config.table.regenNewObjId = regenId
    if inv.config.table.regenOrigObjId ~= 0 then
        inv.items.removeItem(inv.config.table.regenOrigObjId)
    end
    inv.items.wearItem(regenId)
    dbot.info("Auto-wearing regen item: " .. regenName)
    return DRL_RET_SUCCESS
end

function inv.regen.onWake()
    if not inv.config.isRegenEnabled() then
        return DRL_RET_SUCCESS
    end
    local regenId = inv.config.table.regenNewObjId or 0
    local origId = inv.config.table.regenOrigObjId or 0

    if regenId ~= 0 then
        inv.items.storeItem(regenId)
    end
    if origId ~= 0 then
        inv.items.wearItem(origId)
    end

    inv.config.table.regenOrigObjId = 0
    inv.config.table.regenNewObjId = 0
    dbot.info("Restored original equipment after regen sleep.")
    return DRL_RET_SUCCESS
end

dbot.debug("inv.regen module loaded", "inv.regen")
