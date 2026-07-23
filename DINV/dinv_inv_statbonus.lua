----------------------------------------------------------------------------------------------------
-- INV StatBonus Module
-- Calculation and storage of character bonuses from spells and equipment
----------------------------------------------------------------------------------------------------

inv.statBonus       = {}
inv.statBonus.init  = {}
inv.statBonus.table = {}
inv.statBonus.equipBonus = inv.statBonus.equipBonus or {}
inv.statBonus.stateName = "inv-statbonus.state"

inv.statBonus.timer = {}
inv.statBonus.timer.name = "drlInvStatBonusTimer"
inv.statBonus.timer.min = 5
inv.statBonus.timer.sec = 0

function inv.statBonus.init.atInstall()
    return DRL_RET_SUCCESS
end

function inv.statBonus.init.atActive()
    local retval = inv.statBonus.load()
    if retval ~= DRL_RET_SUCCESS then
        dbot.debug("inv.statBonus.init.atActive: Using fresh statbonus table", "inv.statBonus")
    end
    if inv.statBonus.refreshCurrent then
        inv.statBonus.refreshCurrent()
    end
    return DRL_RET_SUCCESS
end

function inv.statBonus.fini(doSaveState)
    if doSaveState then
        inv.statBonus.save()
    end
    return DRL_RET_SUCCESS
end

function inv.statBonus.save()
    if inv.statBonus.table == nil then
        return inv.statBonus.reset()
    end
    return DINV.database.saveModuleTable("statbonus", inv.statBonus.table)
end

function inv.statBonus.load()
    local value, retval = DINV.database.loadModuleTable("statbonus", inv.statBonus.reset)
    if value then inv.statBonus.table = value end
    return retval
end

local function ensureStatBonusTableShape()
    inv.statBonus.table = inv.statBonus.table or {}
    inv.statBonus.table.spellBonuses = inv.statBonus.table.spellBonuses or {}
    inv.statBonus.table.equipBonuses = inv.statBonus.table.equipBonuses or {}
    inv.statBonus.table.levelHistory = inv.statBonus.table.levelHistory or {}
end

function inv.statBonus.reset()
    inv.statBonus.table = {
        spellBonuses = {},
        equipBonuses = {},
        levelHistory = {}
    }
    inv.statBonus.equipBonus = {}
    return DRL_RET_SUCCESS
end

local trackedStats = {
    invStatFieldStr, invStatFieldInt, invStatFieldWis, invStatFieldDex,
    invStatFieldCon, invStatFieldLuck, invStatFieldHp, invStatFieldMana,
    invStatFieldMoves, invStatFieldHitroll, invStatFieldDamroll
}

function inv.statBonus.refreshCurrent()
    -- Keep the live GMCP snapshot in memory. This deliberately does not append
    -- history or write the database because char.stats can fire for every buff
    -- and equipment change on Mudlet's UI thread.
    if not (gmcp and gmcp.char and gmcp.char.stats) then
        return DRL_RET_UNINITIALIZED
    end

    ensureStatBonusTableShape()

    for _, stat in ipairs(trackedStats) do
        local statKey = tostring(stat)
        local modKey = statKey .. "_mod"
        local spellKey = statKey .. "_spell"
        local base = gmcp.char.base and gmcp.char.base[statKey] or nil
        local current = gmcp.char.stats[statKey] or nil
        local bonus = gmcp.char.stats[modKey]
        if bonus == nil and current ~= nil and base ~= nil then
            bonus = tonumber(current) - tonumber(base)
        end
        inv.statBonus.table.equipBonuses[statKey] = tonumber(bonus) or 0

        if gmcp.char.stats[spellKey] ~= nil then
            inv.statBonus.table.spellBonuses[statKey] = tonumber(gmcp.char.stats[spellKey]) or 0
        end
    end

    -- Force score/set consumers to derive the current level's equipment caps
    -- again from this fresh spell-bonus snapshot.
    local currentLevels = {}
    if dbot and dbot.gmcp then
        if dbot.gmcp.getLevel then
            local currentLevel = tonumber(dbot.gmcp.getLevel())
            if currentLevel ~= nil then
                currentLevels[currentLevel] = true
            end
        end
        if dbot.gmcp.getWearableLevel then
            local wearableLevel = tonumber(dbot.gmcp.getWearableLevel())
            if wearableLevel ~= nil then
                currentLevels[wearableLevel] = true
            end
        end
    end
    for currentLevel in pairs(currentLevels) do
        inv.statBonus.equipBonus[currentLevel] = nil
    end

    return DRL_RET_SUCCESS
end

invStatBonusTypeCurrent = "current"
invStatBonusTypeAve     = "average"
invStatBonusTypeMax     = "max"

function inv.statBonus.getEquipmentCap(level)
    level = tonumber(level) or 1
    if level < 25 then
        return 25
    end
    if level > 200 then
        return 200
    end
    return level
end

local function invStatBonusGetHistory(level)
    ensureStatBonusTableShape()
    if level and inv.statBonus.table.levelHistory[tostring(level)] then
        return inv.statBonus.table.levelHistory[tostring(level)]
    end
    return nil
end

local function invStatBonusGetAverage(level)
    local history = invStatBonusGetHistory(level)
    if not history or #history == 0 then
        return nil
    end
    local totals = { str = 0, int = 0, wis = 0, dex = 0, con = 0, luck = 0 }
    local count = 0
    for _, entry in ipairs(history) do
        if entry and entry.spellBonuses then
            totals.str = totals.str + (tonumber(entry.spellBonuses.str) or 0)
            totals.int = totals.int + (tonumber(entry.spellBonuses.int) or 0)
            totals.wis = totals.wis + (tonumber(entry.spellBonuses.wis) or 0)
            totals.dex = totals.dex + (tonumber(entry.spellBonuses.dex) or 0)
            totals.con = totals.con + (tonumber(entry.spellBonuses.con) or 0)
            totals.luck = totals.luck + (tonumber(entry.spellBonuses.luck) or 0)
            count = count + 1
        end
    end
    if count == 0 then
        return nil
    end
    return {
        str = totals.str / count,
        int = totals.int / count,
        wis = totals.wis / count,
        dex = totals.dex / count,
        con = totals.con / count,
        luck = totals.luck / count
    }
end

local function invStatBonusGetMax(level)
    local history = invStatBonusGetHistory(level)
    if not history or #history == 0 then
        return nil
    end
    local maxVals = { str = 0, int = 0, wis = 0, dex = 0, con = 0, luck = 0 }
    for _, entry in ipairs(history) do
        if entry and entry.spellBonuses then
            maxVals.str = math.max(maxVals.str, tonumber(entry.spellBonuses.str) or 0)
            maxVals.int = math.max(maxVals.int, tonumber(entry.spellBonuses.int) or 0)
            maxVals.wis = math.max(maxVals.wis, tonumber(entry.spellBonuses.wis) or 0)
            maxVals.dex = math.max(maxVals.dex, tonumber(entry.spellBonuses.dex) or 0)
            maxVals.con = math.max(maxVals.con, tonumber(entry.spellBonuses.con) or 0)
            maxVals.luck = math.max(maxVals.luck, tonumber(entry.spellBonuses.luck) or 0)
        end
    end
    return maxVals
end

function inv.statBonus.get(level, bonusType)
    ensureStatBonusTableShape()
    level = tonumber(level or "")
    if level == nil then
        return nil, DRL_RET_INVALID_PARAM
    end

    local spellBonus = nil
    if bonusType == invStatBonusTypeCurrent then
        inv.statBonus.refreshCurrent()
        spellBonus = {
            str = tonumber(inv.statBonus.table.spellBonuses.str) or 0,
            int = tonumber(inv.statBonus.table.spellBonuses.int) or 0,
            wis = tonumber(inv.statBonus.table.spellBonuses.wis) or 0,
            dex = tonumber(inv.statBonus.table.spellBonuses.dex) or 0,
            con = tonumber(inv.statBonus.table.spellBonuses.con) or 0,
            luck = tonumber(inv.statBonus.table.spellBonuses.luck) or 0
        }
    elseif bonusType == invStatBonusTypeMax then
        spellBonus = invStatBonusGetMax(level)
    else
        spellBonus = invStatBonusGetAverage(level)
    end

    spellBonus = spellBonus or { str = 0, int = 0, wis = 0, dex = 0, con = 0, luck = 0 }

    local equipCap = inv.statBonus.getEquipmentCap(level)
    local capped = {
        str = math.max(0, equipCap - (spellBonus.str or 0)),
        int = math.max(0, equipCap - (spellBonus.int or 0)),
        wis = math.max(0, equipCap - (spellBonus.wis or 0)),
        dex = math.max(0, equipCap - (spellBonus.dex or 0)),
        con = math.max(0, equipCap - (spellBonus.con or 0)),
        luck = math.max(0, equipCap - (spellBonus.luck or 0))
    }

    inv.statBonus.equipBonus[level] = capped
    return inv.statBonus.equipBonus[level], DRL_RET_SUCCESS
end

function inv.statBonus.set()
    -- Explicit historical sample. Live char.stats updates use refreshCurrent()
    -- so they never append history or synchronously rewrite the database.
    local retval = inv.statBonus.refreshCurrent()
    if retval ~= DRL_RET_SUCCESS then
        return retval
    end

    local level = dbot.gmcp.getLevel()
    inv.statBonus.table.levelHistory[tostring(level)] = inv.statBonus.table.levelHistory[tostring(level)] or {}
    local snapshot = { timestamp = os.time(), bonuses = {}, spellBonuses = {} }

    for _, stat in ipairs(trackedStats) do
        local statKey = tostring(stat)
        local spellKey = statKey .. "_spell"
        snapshot.bonuses[statKey] = tonumber(inv.statBonus.table.equipBonuses[statKey]) or 0
        if gmcp.char.stats[spellKey] ~= nil then
            snapshot.spellBonuses[statKey] = tonumber(inv.statBonus.table.spellBonuses[statKey]) or 0
        end
    end

    table.insert(inv.statBonus.table.levelHistory[tostring(level)], snapshot)
    return inv.statBonus.save()
end

function inv.statBonus.getSpellBonus(stat, level)
    -- Get estimated spell bonus for a stat at a given level
    ensureStatBonusTableShape()
    local statKey = tostring(stat)
    if level and inv.statBonus.table.levelHistory[tostring(level)] then
        local history = inv.statBonus.table.levelHistory[tostring(level)]
        local latest = history[#history]
        if latest and latest.spellBonuses then
            return latest.spellBonuses[statKey] or 0
        end
    end
    return inv.statBonus.table.spellBonuses[statKey] or 0
end

function inv.statBonus.getEquipBonus(stat)
    -- Get current equipment bonus for a stat
    ensureStatBonusTableShape()
    return inv.statBonus.table.equipBonuses[tostring(stat)] or 0
end

dbot.debug("inv.statBonus module loaded", "inv.statBonus")
