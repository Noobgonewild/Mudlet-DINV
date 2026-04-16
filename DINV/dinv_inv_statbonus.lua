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
    return dbot.storage.saveTable(dbot.backup.getCurrentDir() .. inv.statBonus.stateName,
                                   "inv.statBonus.table", inv.statBonus.table, true)
end

function inv.statBonus.load()
    return dbot.storage.loadTable(dbot.backup.getCurrentDir() .. inv.statBonus.stateName, inv.statBonus.reset)
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
        spellBonus = {
            str = inv.statBonus.getSpellBonus("str", level),
            int = inv.statBonus.getSpellBonus("int", level),
            wis = inv.statBonus.getSpellBonus("wis", level),
            dex = inv.statBonus.getSpellBonus("dex", level),
            con = inv.statBonus.getSpellBonus("con", level),
            luck = inv.statBonus.getSpellBonus("luck", level)
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
    -- Called periodically to sample current stat bonuses
    if not (gmcp and gmcp.char and gmcp.char.stats) then
        return DRL_RET_UNINITIALIZED
    end

    ensureStatBonusTableShape()

    local level = dbot.gmcp.getLevel()
    local stats = {
        invStatFieldStr, invStatFieldInt, invStatFieldWis, invStatFieldDex,
        invStatFieldCon, invStatFieldLuck, invStatFieldHp, invStatFieldMana,
        invStatFieldMoves, invStatFieldHitroll, invStatFieldDamroll
    }

    inv.statBonus.table.levelHistory[tostring(level)] = inv.statBonus.table.levelHistory[tostring(level)] or {}
    local snapshot = { timestamp = os.time(), bonuses = {}, spellBonuses = {} }

    for _, stat in ipairs(stats) do
        local statKey = tostring(stat)
        local modKey = statKey .. "_mod"
        local spellKey = statKey .. "_spell"
        local base = gmcp.char.base and gmcp.char.base[statKey] or nil
        local current = gmcp.char.stats[statKey] or nil
        local bonus = gmcp.char.stats[modKey]
        if bonus == nil and current ~= nil and base ~= nil then
            bonus = tonumber(current) - tonumber(base)
        end
        bonus = tonumber(bonus) or 0
        inv.statBonus.table.equipBonuses[statKey] = bonus
        if gmcp.char.stats[spellKey] ~= nil then
            local spellBonus = tonumber(gmcp.char.stats[spellKey]) or 0
            inv.statBonus.table.spellBonuses[statKey] = spellBonus
            snapshot.spellBonuses[statKey] = spellBonus
        end
        snapshot.bonuses[statKey] = bonus
    end

    table.insert(inv.statBonus.table.levelHistory[tostring(level)], snapshot)
    return DRL_RET_SUCCESS
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
