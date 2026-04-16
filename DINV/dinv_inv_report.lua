----------------------------------------------------------------------------------------------------
-- INV Report Module
-- Report item summaries to a channel
----------------------------------------------------------------------------------------------------

inv.report = {}
inv.report.itemPkg = nil

local reportDefaultChannel = "echo"

function inv.report.getChannel()
    if inv.config and inv.config.getReportChannel then
        return inv.config.getReportChannel()
    end
    return reportDefaultChannel
end

function inv.report.setChannel(channel)
    if inv.config and inv.config.setReportChannel then
        return inv.config.setReportChannel(channel)
    end
    return DRL_RET_SUCCESS
end

local function reportLine(line, channel)
    local reportChannel = channel or inv.report.getChannel() or reportDefaultChannel
    local cleanedLine = tostring(line or ""):gsub("^@w", ""):gsub("%s+$", "")
    if reportChannel == "echo" then
        if dbot and dbot.convertColors then
            cecho(dbot.convertColors(cleanedLine) .. "\n")
        else
            cecho(cleanedLine .. "\n")
        end
    else
        if send then
            send(reportChannel .. " " .. cleanedLine)
        else
            dbot.warn("inv.report: send is unavailable; using echo output instead")
            if dbot and dbot.convertColors then
                cecho(dbot.convertColors(cleanedLine) .. "\n")
            else
                cecho(cleanedLine .. "\n")
            end
        end
    end
    return DRL_RET_SUCCESS
end

local function formatItemSummary(objId)
    local name = inv.items.getStatField(objId, invStatFieldName) or "Unknown"
    local level = tonumber(inv.items.getStatField(objId, invStatFieldLevel)) or 0
    local itemType = inv.items.getStatField(objId, invStatFieldType) or "Unknown"
    local score = tonumber(inv.items.getStatField(objId, invStatFieldScore)) or 0
    local wearable = inv.items.getStatField(objId, invStatFieldWearable) or ""

    local summary = string.format("%s [Lvl %d %s] Score %d", name, level, itemType, score)
    if wearable ~= "" then
        summary = summary .. " (" .. wearable .. ")"
    end
    return summary
end

function inv.report.reportItemIds(itemIds, channel)
    if itemIds == nil or #itemIds == 0 then
        return DRL_RET_MISSING_ENTRY
    end

    local reportChannel = channel or inv.report.getChannel() or reportDefaultChannel

    for _, objId in ipairs(itemIds) do
        local _, lineOut = inv.items.displayItem(objId, "itemid", {
            suppress = true,
            useRawColors = true,
            channelFormat = true
        })
        if lineOut then
            local lineToSend = lineOut
            if reportChannel == "echo" then
                lineToSend = tostring(objId) .. " " .. lineOut
            end
            reportLine(lineToSend, channel)
        end
    end

    return DRL_RET_SUCCESS
end

local function addStatEntry(entries, label, value)
    local val = tonumber(value) or 0
    if val ~= 0 then
        table.insert(entries, string.format("@G%d@D%s@w", val, label))
    end
end

local function buildStatBlock(entries)
    if #entries == 0 then
        return ""
    end
    return " [" .. table.concat(entries, " ") .. "]"
end

function inv.report.reportSetStats(priorityName, level, channel)
    if priorityName == nil or priorityName == "" then
        dbot.warn("Usage: dinv report set <priority> [level]")
        return DRL_RET_INVALID_PARAM
    end

    if inv.set == nil or inv.set.table == nil then
        dbot.warn("Set module is not loaded. Try: lua DINV.initialize()")
        return DRL_RET_UNINITIALIZED
    end

    if inv.items == nil or inv.items.table == nil or dbot.table.getNumEntries(inv.items.table) == 0 then
        dbot.info("Your inventory table is empty. Run '@Gdinv build confirm@W' to populate it.")
        return DRL_RET_MISSING_ENTRY
    end

    local targetLevel = tostring(tonumber(level) or (dbot.gmcp.getWearableLevel and dbot.gmcp.getWearableLevel()) or (dbot.gmcp.getLevel and dbot.gmcp.getLevel()) or 1)

    if inv.set and inv.set.delete then
        inv.set.delete(priorityName, targetLevel)
    end

    if inv.set and inv.set.table and
       (inv.set.table[priorityName] == nil or inv.set.table[priorityName][targetLevel] == nil) then
        if inv.set and inv.set.create then
            local retval = inv.set.create(priorityName, tonumber(targetLevel))
            if retval ~= DRL_RET_SUCCESS then
                return retval
            end
        end
    end

    local setData = inv.set and inv.set.table and inv.set.table[priorityName] and inv.set.table[priorityName][targetLevel]
    if setData == nil or setData.equipment == nil then
        dbot.warn("No set found for priority '" .. priorityName .. "' at level " .. targetLevel)
        return DRL_RET_MISSING_ENTRY
    end

    local stats = { str=0, int=0, wis=0, dex=0, con=0, luck=0, hr=0, dr=0, hp=0, mana=0, moves=0 }
    local effects = {}

    for _, loc in ipairs(inv.set.wearableLocations or {}) do
        local objId = setData.equipment and setData.equipment[loc]
        if objId then
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

            local affects = inv.items.getStatField(objId, invStatFieldAffects) or ""
            local flags = inv.items.getStatField(objId, invStatFieldFlags) or ""
            local combined = string.lower(affects .. " " .. flags)
            for _, eff in ipairs({ "flying", "haste", "regeneration", "dualwield", "sanctuary", "invis" }) do
                if combined:find(eff, 1, true) then
                    effects[eff] = true
                end
            end
        end
    end

    local baseStats = {}
    addStatEntry(baseStats, "int", stats.int)
    addStatEntry(baseStats, "wis", stats.wis)
    addStatEntry(baseStats, "lck", stats.luck)
    addStatEntry(baseStats, "str", stats.str)
    addStatEntry(baseStats, "dex", stats.dex)
    addStatEntry(baseStats, "con", stats.con)

    local rollStats = {}
    addStatEntry(rollStats, "hr", stats.hr)
    addStatEntry(rollStats, "dr", stats.dr)

    local resourceStats = {}
    addStatEntry(resourceStats, "hp", stats.hp)
    addStatEntry(resourceStats, "mn", stats.mana)
    addStatEntry(resourceStats, "mv", stats.moves)

    local effectsOrdered = {}
    for _, eff in ipairs({ "flying", "haste", "regeneration", "dualwield", "sanctuary", "invis" }) do
        if effects[eff] then
            table.insert(effectsOrdered, eff)
        end
    end

    local effectText = #effectsOrdered > 0 and (" [" .. table.concat(effectsOrdered, " ") .. "]") or ""
    local nameText = string.format("@w%s [@Wlv%s@w] [set]", priorityName, targetLevel)

    local line = table.concat({
        nameText,
        buildStatBlock(baseStats),
        buildStatBlock(rollStats),
        buildStatBlock(resourceStats),
        effectText
    }, "")

    return reportLine(line, channel)
end

function inv.report.item(channel, name)
    if channel == nil or channel == "" then
        dbot.warn("inv.report.item: Missing channel name")
        return DRL_RET_INVALID_PARAM
    end

    if name == nil or name == "" then
        dbot.warn("inv.report.item: Missing relative name of item to report")
        return DRL_RET_INVALID_PARAM
    end

    inv.report.itemPkg = { channel = channel, name = name }
    return inv.report.itemCR()
end

function inv.report.itemCR()
    if inv.report.itemPkg == nil then
        dbot.warn("inv.report.itemCR: package is nil")
        return DRL_RET_INTERNAL_ERROR
    end

    local channel = inv.report.itemPkg.channel
    local name = inv.report.itemPkg.name
    local objId = tonumber(name)
    local idArray = {}
    local retval = DRL_RET_SUCCESS

    if objId then
        if inv.items.getItem(objId) ~= nil then
            table.insert(idArray, objId)
        end
    else
        idArray, retval = inv.items.search("name " .. name)
    end

    if retval ~= DRL_RET_SUCCESS then
        dbot.warn("inv.report.itemCR: failed to search inventory table: " .. dbot.retval.getString(retval))
        inv.report.itemPkg = nil
        return retval
    end

    if #idArray == 0 then
        dbot.warn("inv.report.itemCR: No items matched name \"" .. name .. "\"")
        inv.report.itemPkg = nil
        return DRL_RET_MISSING_ENTRY
    end

    if #idArray > 1 then
        dbot.warn("inv.report.itemCR: More than one item matched name \"" .. name .. "\"")
        inv.report.itemPkg = nil
        return DRL_RET_INTERNAL_ERROR
    end

    local summary = formatItemSummary(idArray[1])
    send(channel .. " " .. summary)
    inv.report.itemPkg = nil
    return DRL_RET_SUCCESS
end

dbot.debug("inv.report module loaded", "inv.report")
