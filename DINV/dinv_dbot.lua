----------------------------------------------------------------------------------------------------
-- DBOT - Durel's Bag of Tricks
-- Utility library for DINV - Ported to Mudlet
--
-- This module provides common utility functions used throughout the DINV system:
--   - Return values / error codes
--   - Table utilities
--   - Notification system (print, warn, error, info, debug)
--   - GMCP interface
--   - Storage (save/load tables)
--   - Backup system
--   - Command execution framework
--   - And more...
----------------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------------
-- Return Values / Error Codes
----------------------------------------------------------------------------------------------------

DRL_RET_SUCCESS        =  0
DRL_RET_UNINITIALIZED  = -1
DRL_RET_INVALID_PARAM  = -2
DRL_RET_MISSING_ENTRY  = -3
DRL_RET_BUSY           = -4
DRL_RET_UNSUPPORTED    = -5
DRL_RET_TIMEOUT        = -6
DRL_RET_HALTED         = -7
DRL_RET_INTERNAL_ERROR = -8
DRL_RET_UNIDENTIFIED   = -9
DRL_RET_NOT_ACTIVE     = -10
DRL_RET_IN_COMBAT      = -11
DRL_RET_VER_MISMATCH   = -12

----------------------------------------------------------------------------------------------------
-- Base Module
----------------------------------------------------------------------------------------------------

dbot = {}
pluginNameCmd = pluginNameCmd or "dinv"
pluginNameAbbr = pluginNameAbbr or "DINV"

----------------------------------------------------------------------------------------------------
-- Return Value Module
----------------------------------------------------------------------------------------------------

dbot.retval = {}
dbot.retval.table = {}
dbot.retval.table[DRL_RET_SUCCESS]        = "success"
dbot.retval.table[DRL_RET_UNINITIALIZED]  = "component is not initialized"
dbot.retval.table[DRL_RET_INVALID_PARAM]  = "invalid parameter"
dbot.retval.table[DRL_RET_MISSING_ENTRY]  = "missing entry"
dbot.retval.table[DRL_RET_BUSY]           = "resource is in use"
dbot.retval.table[DRL_RET_UNSUPPORTED]    = "unsupported feature"
dbot.retval.table[DRL_RET_TIMEOUT]        = "timeout"
dbot.retval.table[DRL_RET_HALTED]         = "component is halted"
dbot.retval.table[DRL_RET_INTERNAL_ERROR] = "internal error"
dbot.retval.table[DRL_RET_UNIDENTIFIED]   = "item is not yet identified"
dbot.retval.table[DRL_RET_NOT_ACTIVE]     = "you are not in the active state"
dbot.retval.table[DRL_RET_IN_COMBAT]      = "you are in combat!"
dbot.retval.table[DRL_RET_VER_MISMATCH]   = "version mismatch"

function dbot.retval.getString(retval)
    local str = dbot.retval.table[retval]
    if str == nil then
        str = "Unknown return value (" .. tostring(retval) .. ")"
    end
    return str
end

----------------------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------------------

drlSpinnerPeriodDefault = 0.1

-- Color codes (Mudlet uses different format, we'll convert @X to cecho format)
DRL_ANSI_GREEN  = "@G"
DRL_ANSI_RED    = "@R"
DRL_ANSI_YELLOW = "@Y"
DRL_ANSI_WHITE  = "@W"

----------------------------------------------------------------------------------------------------
-- Plugin Info Fields
----------------------------------------------------------------------------------------------------

dbot.pluginInfo = {}
dbot.pluginInfo.dir = 20

----------------------------------------------------------------------------------------------------
-- Init / De-init Module
----------------------------------------------------------------------------------------------------

dbot.init = {}
dbot.init.initializedInstall = false
dbot.init.initializedActive  = false

-- Modules that dbot manages (in order of initialization)
dbot.modules = "storage emptyLine backup notify prompt invmon wish execute pagesize gmcp"

function dbot.init.atInstall()
    local retval = DRL_RET_SUCCESS
    
    for module in dbot.modules:gmatch("%S+") do
        if dbot[module] and dbot[module].init and dbot[module].init.atInstall then
            local initVal = dbot[module].init.atInstall()
            if initVal ~= DRL_RET_SUCCESS then
                dbot.warn("dbot.init.atInstall: Failed to initialize 'at install' dbot." .. module .. 
                          " module: " .. dbot.retval.getString(initVal))
                retval = initVal
            else
                dbot.debug("Initialized 'at install' module dbot." .. module, "dbot")
            end
        end
    end
    
    dbot.init.initializedInstall = true
    return retval
end

function dbot.init.atActive()
    local retval = DRL_RET_SUCCESS
    
    for module in dbot.modules:gmatch("%S+") do
        if dbot[module] and dbot[module].init and dbot[module].init.atActive then
            local initVal = dbot[module].init.atActive()
            if initVal ~= DRL_RET_SUCCESS then
                dbot.warn("dbot.init.atActive: Failed to initialize 'at active' dbot." .. module .. 
                          " module: " .. dbot.retval.getString(initVal))
                retval = initVal
            else
                dbot.debug("Initialized 'at active' module dbot." .. module, "dbot")
            end
        end
    end
    
    dbot.init.initializedActive = true
    return retval
end

function dbot.fini(doSaveState)
    local retval = DRL_RET_SUCCESS
    
    for module in dbot.modules:gmatch("%S+") do
        if dbot[module] and dbot[module].fini then
            local initVal = dbot[module].fini(doSaveState)
            if initVal ~= DRL_RET_SUCCESS and initVal ~= DRL_RET_UNINITIALIZED then
                dbot.warn("dbot.fini: Failed to de-initialize dbot." .. module .. " module: " ..
                          dbot.retval.getString(initVal))
                retval = initVal
            end
        end
    end
    
    dbot.init.initializedInstall = false
    dbot.init.initializedActive  = false
    
    return retval
end

----------------------------------------------------------------------------------------------------
-- Color Conversion: Convert @X codes to Mudlet cecho format
----------------------------------------------------------------------------------------------------

local colorMap = {
    -- IMPORTANT: Mudlet uses ansi_* for dark colors, not dark_*
    ["@w"] = "<ansi_white>",
    ["@W"] = "<white>",
    ["@r"] = "<ansi_red>",           -- dark red
    ["@R"] = "<ansi_light_red>",     -- bright red
    ["@g"] = "<ansi_green>",         -- dark green
    ["@G"] = "<ansi_light_green>",   -- bright green
    ["@y"] = "<ansi_yellow>",        -- dark yellow (brown-ish)
    ["@Y"] = "<ansi_light_yellow>",  -- bright yellow
    ["@b"] = "<ansi_blue>",          -- dark blue
    ["@B"] = "<ansi_light_blue>",    -- bright blue
    ["@m"] = "<ansi_magenta>",       -- dark magenta
    ["@M"] = "<ansi_light_magenta>", -- bright magenta
    ["@c"] = "<ansi_cyan>",          -- dark cyan
    ["@C"] = "<ansi_light_cyan>",    -- bright cyan
    ["@d"] = "<ansi_black>",         -- dark grey (bright black)
    ["@D"] = "<ansi_light_black>",   -- light grey
}

-- Xterm 256 to Mudlet color approximation
local function xtermToMudlet(num)
    num = tonumber(num) or 0

    -- System colors 0-15
    if num == 0 then return "<ansi_black>"
    elseif num == 1 then return "<ansi_red>"
    elseif num == 2 then return "<ansi_green>"
    elseif num == 3 then return "<ansi_yellow>"
    elseif num == 4 then return "<ansi_blue>"
    elseif num == 5 then return "<ansi_magenta>"
    elseif num == 6 then return "<ansi_cyan>"
    elseif num == 7 then return "<ansi_white>"
    elseif num == 8 then return "<ansi_light_black>"
    elseif num == 9 then return "<ansi_light_red>"
    elseif num == 10 then return "<ansi_light_green>"
    elseif num == 11 then return "<ansi_light_yellow>"
    elseif num == 12 then return "<ansi_light_blue>"
    elseif num == 13 then return "<ansi_light_magenta>"
    elseif num == 14 then return "<ansi_light_cyan>"
    elseif num == 15 then return "<white>"
    -- Greyscale 232-255
    elseif num >= 232 then
        local grey = num - 232
        if grey < 8 then return "<ansi_black>"
        elseif grey < 16 then return "<ansi_light_black>"
        else return "<white>" end
    -- 216 color cube (16-231) - approximate to nearest ANSI
    else
        local n = num - 16
        local b = n % 6
        local g = math.floor(n / 6) % 6
        local r = math.floor(n / 36)
        local max = math.max(r, g, b)
        local bright = max >= 3

        if r > g and r > b then return bright and "<ansi_light_red>" or "<ansi_red>"
        elseif g > r and g > b then return bright and "<ansi_light_green>" or "<ansi_green>"
        elseif b > r and b > g then return bright and "<ansi_light_blue>" or "<ansi_blue>"
        elseif r == g and r > b then return bright and "<ansi_light_yellow>" or "<ansi_yellow>"
        elseif r == b and r > g then return bright and "<ansi_light_magenta>" or "<ansi_magenta>"
        elseif g == b and g > r then return bright and "<ansi_light_cyan>" or "<ansi_cyan>"
        else return bright and "<white>" or "<ansi_white>" end
    end
end

function dbot.convertColors(str)
    if str == nil then return "" end

    -- Handle @@ (escaped @) - temporarily replace
    str = str:gsub("@@", "\001ATESCAPE\001")

    -- Convert basic @X color codes
    for code, cechoColor in pairs(colorMap) do
        local pattern = code:gsub("@", "%%@")
        str = str:gsub(pattern, cechoColor)
    end

    -- Convert xterm @xNNN codes
    str = str:gsub("@x(%d+)", function(num)
        return xtermToMudlet(num)
    end)

    -- Restore escaped @
    str = str:gsub("\001ATESCAPE\001", "@")

    return str
end

-- Strip Aardwolf @ color codes and ANSI escape sequences. Single source
-- of truth for color stripping across the plugin. Must NOT remove other
-- punctuation such as '<...>' substrings, which are part of some item
-- names (e.g. "<! Jenny's Magical Pendant !>").
function dbot.stripColors(str)
    if str == nil then return "" end
    str = tostring(str)
    str = str:gsub("@@", "\001AT\001")   -- protect escaped @
    str = str:gsub("@x%d+", "")           -- extended color codes
    str = str:gsub("@[%a]", "")           -- single-letter color codes
    str = str:gsub("\027%[[%d;]*m", "")   -- ANSI escape sequences
    str = str:gsub("\001AT\001", "@")     -- restore escaped @
    return str
end

-- Global alias for compatibility with MUSHclient code
function strip_colours(str)
    return dbot.stripColors(str)
end

----------------------------------------------------------------------------------------------------
-- Notification module moved to dinv_notify.lua
----------------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------------
-- Convenience Notification Functions
----------------------------------------------------------------------------------------------------

-- Debug level: 0 = errors only, 1 = info, 2 = debug
dbot.debugLevel = dbot.debugLevel or 1

function dbot.error(msg)
    cecho("\n<red>[DINV ERROR] " .. tostring(msg) .. "\n")
end

function dbot.warn(msg)
    if dbot.notify and dbot.notify.shouldShow and not dbot.notify.shouldShow("warn") then
        return
    end
    cecho("\n<yellow>[DINV WARN] " .. tostring(msg) .. "\n")
end

function dbot.info(msg)
    if dbot.notify and dbot.notify.shouldShow and not dbot.notify.shouldShow("info") then
        return
    end
    local coloredMsg = dbot.convertColors(msg)
    cecho("\n<cyan>[DINV INFO] <white>" .. tostring(coloredMsg) .. "\n")
end

function dbot.note(msg)
    if dbot.notify and dbot.notify.shouldShow and not dbot.notify.shouldShow("note") then
        return
    end
    cecho("\n<white>[DINV NOTE] " .. tostring(msg) .. "\n")
end

function dbot.debug(msg, moduleName)
    if DINV and DINV.debug and DINV.debug.isEnabled and moduleName then
        if not DINV.debug.isEnabled(moduleName) then
            return
        end
    else
        if dbot.debugLevel < 2 then
            return
        end
    end

    local prefix = "[DINV DEBUG]"
    if moduleName and moduleName ~= "" then
        prefix = "[DINV DEBUG " .. tostring(moduleName) .. "]"
    end
    cecho("\n<dim_grey>" .. prefix .. " " .. tostring(msg) .. "\n")
end

-- Print with color code conversion (@G -> green, etc.)
function dbot.print(msg)
    local text = tostring(msg or "")
    text = dbot.convertColors(text)
    cecho(text .. "\n")
end

-- Print a single line without extra leading spacing.
function dbot.printRaw(msg)
    local text = tostring(msg or "")
    text = dbot.convertColors(text)
    cecho(text .. "\n")
end

----------------------------------------------------------------------------------------------------
-- Table Utilities
----------------------------------------------------------------------------------------------------

dbot.table = {}

function dbot.table.getCopy(origItem)
    local newItem
    
    if type(origItem) == 'table' then
        newItem = {}
        for origKey, origValue in next, origItem, nil do
            newItem[dbot.table.getCopy(origKey)] = dbot.table.getCopy(origValue)
        end
        setmetatable(newItem, dbot.table.getCopy(getmetatable(origItem)))
    else
        newItem = origItem
    end
    
    return newItem
end

function dbot.table.getNumEntries(theTable)
    local numEntries = 0
    
    if theTable ~= nil then
        for k, v in pairs(theTable) do
            numEntries = numEntries + 1
        end
    end
    
    return numEntries
end

----------------------------------------------------------------------------------------------------
-- Generic Utilities
----------------------------------------------------------------------------------------------------

function dbot.getTime()
    return tonumber(os.time()) or 0
end

function dbot.tonumber(numString)
    if numString == nil then return nil end
    local noCommas = string.gsub(tostring(numString), ",", "")
    return tonumber(noCommas)
end

function dbot.isWordInString(word, field)
    if word == nil or word == "" or field == nil or field == "" then
        return false
    end
    
    for element in field:gmatch("%S+") do
        if string.lower(word) == string.lower(element) then
            return true
        end
    end
    
    return false
end

function dbot.wordsToArray(myString)
    local wordTable = {}
    
    if myString == nil then
        dbot.warn("dbot.wordsToArray: Missing string parameter")
        return wordTable, DRL_RET_INVALID_PARAM
    end
    
    for word in string.gmatch(myString, "%S+") do
        table.insert(wordTable, word)
    end
    
    return wordTable, DRL_RET_SUCCESS
end

function dbot.mergeFields(field1, field2)
    local mergedField = field1 or ""
    
    if field2 ~= nil and field2 ~= "" then
        for word in field2:gmatch("%S+") do
            if not dbot.isWordInString(word, field1) then
                mergedField = mergedField .. " " .. word
            end
        end
    end
    
    return mergedField
end

function dbot.arrayConcat(array1, array2)
    local mergedArray = {}
    
    if array1 ~= nil then
        for _, entry in ipairs(array1) do
            table.insert(mergedArray, entry)
        end
    end
    
    if array2 ~= nil then
        for _, entry in ipairs(array2) do
            table.insert(mergedArray, entry)
        end
    end
    
    return mergedArray
end

----------------------------------------------------------------------------------------------------
-- File Utilities
----------------------------------------------------------------------------------------------------

function dbot.fileExists(fileName)
    if fileName == nil or fileName == "" then
        return false
    end
    
    local f = io.open(fileName, "r")
    if f then
        f:close()
        return true
    end
    return false
end

function dbot.ensureDirectory(path)
    -- Use lfs (LuaFileSystem) which is available in Mudlet
    if lfs then
        if path == nil or path == "" then
            return
        end

        local normalized = tostring(path):gsub("\\", "/")
        if lfs.attributes(normalized, "mode") == "directory" then
            return
        end

        local current = ""
        if normalized:match("^%a:") then
            current = normalized:sub(1, 2)
            normalized = normalized:sub(3)
            if normalized:sub(1, 1) == "/" then
                normalized = normalized:sub(2)
            end
        elseif normalized:sub(1, 1) == "/" then
            current = "/"
            normalized = normalized:sub(2)
        end

        for segment in normalized:gmatch("[^/]+") do
            if current == "" then
                current = segment
            elseif current == "/" then
                current = current .. segment
            else
                current = current .. "/" .. segment
            end

            if lfs.attributes(current, "mode") ~= "directory" then
                lfs.mkdir(current)
            end
        end
    end
end

----------------------------------------------------------------------------------------------------
-- Reload Function
----------------------------------------------------------------------------------------------------

function dbot.reload()
    if DINV and DINV.reload then
        DINV.reload()
    else
        dbot.warn("dbot.reload: DINV.reload not available")
    end
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- GMCP Module
----------------------------------------------------------------------------------------------------

dbot.gmcp      = {}
dbot.gmcp.init = {}
dbot.gmcp.isInitialized = false
dbot.gmcp.currentState = {}

-- Character states
dbot.stateLogin    = "1"
dbot.stateMOTD     = "2"
dbot.stateActive   = "3"
dbot.stateAFK      = "4"
dbot.stateNote     = "5"
dbot.stateBuilding = "6"
dbot.statePaged    = "7"
dbot.stateCombat   = "8"
dbot.stateSleeping = "9"
dbot.stateTBD      = "10"
dbot.stateResting  = "11"
dbot.stateRunning  = "12"

dbot.stateNames = {}
dbot.stateNames[dbot.stateLogin]    = "Login"
dbot.stateNames[dbot.stateMOTD]     = "MOTD"
dbot.stateNames[dbot.stateActive]   = "Active"
dbot.stateNames[dbot.stateAFK]      = "AFK"
dbot.stateNames[dbot.stateNote]     = "Note"
dbot.stateNames[dbot.stateBuilding] = "Building"
dbot.stateNames[dbot.statePaged]    = "Paged"
dbot.stateNames[dbot.stateCombat]   = "Combat"
dbot.stateNames[dbot.stateSleeping] = "Sleeping"
dbot.stateNames[dbot.stateTBD]      = "Uninitialized"
dbot.stateNames[dbot.stateResting]  = "Resting"
dbot.stateNames[dbot.stateRunning]  = "Running"

function dbot.gmcp.init.atActive()
    return DRL_RET_SUCCESS
end

function dbot.gmcp.fini(doSaveState)
    dbot.gmcp.isInitialized = false
    return DRL_RET_SUCCESS
end

function dbot.gmcp.getState()
    if not dbot.gmcp.isInitialized then
        dbot.debug("dbot.gmcp.getState: GMCP is not initialized", "dbot.gmcp")
        return dbot.stateTBD
    end
    
    -- Mudlet GMCP access - use the global gmcp table
    if gmcp and gmcp.char and gmcp.char.status then
        local state = gmcp.char.status.state
        if state then
            return tostring(state)
        end
    end
    
    return dbot.stateTBD
end

function dbot.gmcp.getStateString(state)
    return dbot.stateNames[state] or "Unknown"
end

function dbot.gmcp.stateIsActive()
    local state = dbot.gmcp.getState()
    return state == dbot.stateActive
end

function dbot.gmcp.stateIsInCombat()
    local state = dbot.gmcp.getState()
    return state == dbot.stateCombat
end

function dbot.gmcp.statePreventsActions()
    local state = dbot.gmcp.getState()
    
    -- States that prevent actions: AFK, Sleeping, Note, Building, Paged
    local preventingStates = {
        [dbot.stateAFK] = true,
        [dbot.stateSleeping] = true,
        [dbot.stateNote] = true,
        [dbot.stateBuilding] = true,
        [dbot.statePaged] = true,
    }
    
    return preventingStates[state] or false
end

function dbot.gmcp.getName()
    if gmcp and gmcp.char and gmcp.char.base then
        return gmcp.char.base.name or "Unknown"
    end
    return "Unknown"
end

dbot.gmcp.charName = "unknown"
dbot.gmcp.charPretitle = ""

function dbot.gmcp.getLevel()
    local baseLevel = 1
    if gmcp and gmcp.char and gmcp.char.status then
        baseLevel = tonumber(gmcp.char.status.level) or 1
    elseif gmcp and gmcp.char and gmcp.char.base then
        baseLevel = tonumber(gmcp.char.base.level) or 1
    end
    return baseLevel
end

-- Returns the effective level for wearing equipment (base level + tier*10)
function dbot.gmcp.getWearableLevel()
    local baseLevel = dbot.gmcp.getLevel()
    local tier = dbot.gmcp.getTier()
    return baseLevel + (tier * 10)
end

function dbot.gmcp.getTier()
    if gmcp and gmcp.char and gmcp.char.base then
        return tonumber(gmcp.char.base.tier) or 0
    end
    return 0
end

function dbot.gmcp.getAlign()
    if dbot.gmcp.isInitialized and gmcp and gmcp.char and gmcp.char.status then
        return tonumber(gmcp.char.status.align) or 0
    end
    return 0
end

function dbot.gmcp.getClass()
    if gmcp and gmcp.char and gmcp.char.base then
        return gmcp.char.base.class or "Unknown"
    end
    return "Unknown"
end

function dbot.gmcp.getRace()
    if gmcp and gmcp.char and gmcp.char.base then
        return gmcp.char.base.race or "Unknown"
    end
    return "Unknown"
end

function dbot.gmcp.updateState()
    -- This is called by GMCP event handlers when char.status updates
    -- Currently just a placeholder - state is fetched directly from gmcp tables
    return DRL_RET_SUCCESS
end

function dbot.gmcp.getMaxStats()
    -- Prefer authoritative GMCP data when available.
    if gmcp and gmcp.char and gmcp.char.maxstats then
        return {
            str = tonumber(gmcp.char.maxstats.str) or 25,
            int = tonumber(gmcp.char.maxstats.int) or 25,
            wis = tonumber(gmcp.char.maxstats.wis) or 25,
            dex = tonumber(gmcp.char.maxstats.dex) or 25,
            con = tonumber(gmcp.char.maxstats.con) or 25,
            luck = tonumber(gmcp.char.maxstats.luck) or 25
        }
    end

    -- Fallback formula from help maxstats:
    --   L1-70:   level + 25
    --   L71-155: 95 + 2*(level-70)
    --   L156-200:265 + 3*(level-155)
    -- Plus +2 max trainable per tier (to hard cap 400).
    local level = tonumber(dbot.gmcp.getLevel and dbot.gmcp.getLevel()) or 1
    local tier = tonumber(dbot.gmcp.getTier and dbot.gmcp.getTier()) or 0

    local baseCap = 25
    if level <= 70 then
        baseCap = level + 25
    elseif level <= 155 then
        baseCap = 95 + (2 * (level - 70))
    elseif level <= 200 then
        baseCap = 265 + (3 * (level - 155))
    else
        baseCap = 400
    end

    local tierBonus = math.max(0, tier) * 2
    local finalCap = math.min(400, baseCap + tierBonus)

    return {
        str = finalCap, int = finalCap, wis = finalCap,
        dex = finalCap, con = finalCap, luck = finalCap
    }
end

function dbot.gmcp.getCurrentStats()
    local stats = {
        str = 0, int = 0, wis = 0, dex = 0, con = 0, luck = 0,
        hp = 0, maxhp = 0, mana = 0, maxmana = 0, moves = 0, maxmoves = 0
    }
    
    if gmcp and gmcp.char and gmcp.char.stats then
        stats.str = tonumber(gmcp.char.stats.str) or 0
        stats.int = tonumber(gmcp.char.stats.int) or 0
        stats.wis = tonumber(gmcp.char.stats.wis) or 0
        stats.dex = tonumber(gmcp.char.stats.dex) or 0
        stats.con = tonumber(gmcp.char.stats.con) or 0
        stats.luck = tonumber(gmcp.char.stats.luck) or 0
    end
    
    if gmcp and gmcp.char and gmcp.char.vitals then
        stats.hp = tonumber(gmcp.char.vitals.hp) or 0
        stats.maxhp = tonumber(gmcp.char.vitals.maxhp) or 0
        stats.mana = tonumber(gmcp.char.vitals.mana) or 0
        stats.maxmana = tonumber(gmcp.char.vitals.maxmana) or 0
        stats.moves = tonumber(gmcp.char.vitals.moves) or 0
        stats.maxmoves = tonumber(gmcp.char.vitals.maxmoves) or 0
    end
    
    return stats
end

function dbot.gmcp.getArea()
    if dbot.gmcp.isInitialized and gmcp and gmcp.room and gmcp.room.info then
        return gmcp.room.info.zone or ""
    end
    return ""
end

function dbot.gmcp.getRoomId()
    if dbot.gmcp.isInitialized and gmcp and gmcp.room and gmcp.room.info then
        return gmcp.room.info.num or 0
    end
    return 0
end

function dbot.gmcp.getHp()
    local currentHp, maxHp = 0, 0
    if dbot.gmcp.isInitialized and gmcp and gmcp.char then
        if gmcp.char.vitals then
            currentHp = tonumber(gmcp.char.vitals.hp) or 0
        end
        if gmcp.char.maxstats then
            maxHp = tonumber(gmcp.char.maxstats.maxhp) or 0
        end
    end
    return currentHp, maxHp
end

function dbot.gmcp.getMana()
    local currentMana, maxMana = 0, 0
    if dbot.gmcp.isInitialized and gmcp and gmcp.char then
        if gmcp.char.vitals then
            currentMana = tonumber(gmcp.char.vitals.mana) or 0
        end
        if gmcp.char.maxstats then
            maxMana = tonumber(gmcp.char.maxstats.maxmana) or 0
        end
    end
    return currentMana, maxMana
end

function dbot.gmcp.getMoves()
    local currentMoves, maxMoves = 0, 0
    if dbot.gmcp.isInitialized and gmcp and gmcp.char then
        if gmcp.char.vitals then
            currentMoves = tonumber(gmcp.char.vitals.moves) or 0
        end
        if gmcp.char.maxstats then
            maxMoves = tonumber(gmcp.char.maxstats.maxmoves) or 0
        end
    end
    return currentMoves, maxMoves
end

function dbot.gmcp.isGood()
    return dbot.gmcp.getAlign() > 875
end

function dbot.gmcp.isNeutral()
    local align = dbot.gmcp.getAlign()
    return align >= -875 and align <= 875
end

function dbot.gmcp.isEvil()
    return dbot.gmcp.getAlign() < -875
end

----------------------------------------------------------------------------------------------------
-- Storage Module
----------------------------------------------------------------------------------------------------

dbot.storage = {}
dbot.storage.init = {}
dbot.storage.fileVersion = 1

function dbot.storage.init.atInstall()
    return DRL_RET_SUCCESS
end

function dbot.storage.init.atActive()
    -- Ensure directories exist
    dbot.ensureDirectory(pluginStatePath)
    
    local baseDir = dbot.backup.getBaseDir()
    dbot.ensureDirectory(baseDir)
    
    local currentDir = dbot.backup.getCurrentDir()
    dbot.ensureDirectory(currentDir)
    
    return DRL_RET_SUCCESS
end

function dbot.storage.fini(doSaveState)
    return DRL_RET_SUCCESS
end

function dbot.storage.saveTable(fileName, tableName, theTable, doForceSave)
    local retval = DRL_RET_SUCCESS
    
    if not dbot.init.initializedActive and not doForceSave then
        dbot.note("Skipping save for '" .. (tableName or "Unknown") .. "' table: plugin is not initialized")
        return DRL_RET_UNINITIALIZED
    end
    
    if fileName == nil or fileName == "" then
        dbot.warn("dbot.storage.saveTable: Missing fileName parameter")
        return DRL_RET_INVALID_PARAM
    end
    
    if tableName == nil or tableName == "" then
        dbot.warn("dbot.storage.saveTable: Missing tableName parameter")
        return DRL_RET_INVALID_PARAM
    end
    
    if theTable == nil then
        dbot.warn("dbot.storage.saveTable: Missing table parameter")
        return DRL_RET_INVALID_PARAM
    end
    
    local shortName = fileName:match("([^/\\]+)$") or fileName
    local targetDir = fileName:match("^(.*)[/\\][^/\\]+$")
    if targetDir and targetDir ~= "" then
        dbot.ensureDirectory(targetDir)
    end
    dbot.debug("dbot.storage.saveTable: Saving '" .. shortName .. "'", "dbot.storage")
    
    -- Serialize the table
    local serialized = dbot.storage.serialize(theTable)
    
    local f, errString = io.open(fileName, "w+")
    if f == nil then
        dbot.warn("dbot.storage.saveTable: Failed to save file: " .. (errString or "unknown error"))
        return DRL_RET_INTERNAL_ERROR
    end
    
    f:write("-- " .. tableName .. "\n")
    f:write("-- Version: " .. dbot.storage.fileVersion .. "\n")
    f:write(tableName .. " = " .. serialized .. "\n")
    f:flush()
    f:close()
    
    return retval
end

function dbot.storage.loadTable(fileName, resetFn)
    local retval = DRL_RET_SUCCESS
    
    if fileName == nil or fileName == "" or resetFn == nil then
        dbot.warn("dbot.storage.loadTable: Missing parameter")
        return DRL_RET_INVALID_PARAM
    end
    
    local shortName = fileName:match("([^/\\]+)$") or fileName
    dbot.debug("dbot.storage.loadTable: Loading '" .. shortName .. "'", "dbot.storage")
    
    local f = io.open(fileName, "r")
    if f ~= nil then
        local content = f:read("*a")
        f:close()
        
        if content then
            local chunk, err = loadstring(content)
            if not chunk and content:find("= return") then
                local repaired = content:gsub("= return%s+", "= ")
                chunk, err = loadstring(repaired)
            end
            if chunk then
                chunk()
            else
                dbot.error("dbot.storage.loadTable: Failed to parse file '" .. fileName .. "': " .. (err or "unknown"))
                resetFn()
                return DRL_RET_INTERNAL_ERROR
            end
        end
    else
        -- File doesn't exist, use reset function to create defaults
        retval = resetFn()
    end
    
    return retval
end

-- Simple table serialization
function dbot.storage.serialize(val, indent)
    indent = indent or 0
    local spaces = string.rep("  ", indent)
    
    local t = type(val)
    
    if t == "nil" then
        return "nil"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        return tostring(val)
    elseif t == "string" then
        return string.format("%q", val)
    elseif t == "table" then
        local parts = {}
        local isArray = true
        local maxIndex = 0
        
        -- Check if it's an array
        for k, v in pairs(val) do
            if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
                isArray = false
                break
            end
            if k > maxIndex then maxIndex = k end
        end
        
        if isArray and maxIndex > 0 then
            for i = 1, maxIndex do
                table.insert(parts, dbot.storage.serialize(val[i], indent + 1))
            end
            return "{\n" .. spaces .. "  " .. table.concat(parts, ",\n" .. spaces .. "  ") .. "\n" .. spaces .. "}"
        else
            for k, v in pairs(val) do
                local key
                if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                    key = k
                else
                    key = "[" .. dbot.storage.serialize(k) .. "]"
                end
                table.insert(parts, key .. " = " .. dbot.storage.serialize(v, indent + 1))
            end
            if #parts == 0 then
                return "{}"
            end
            return "{\n" .. spaces .. "  " .. table.concat(parts, ",\n" .. spaces .. "  ") .. "\n" .. spaces .. "}"
        end
    else
        return "nil -- unsupported type: " .. t
    end
end

----------------------------------------------------------------------------------------------------
-- Backup Module
----------------------------------------------------------------------------------------------------

dbot.backup = {}
dbot.backup.init = {}
dbot.backup.inProgress = false

dbot.backup.timer = {}
dbot.backup.timer.name = "drlInvBackupTimer"
dbot.backup.timer.intervalSeconds = 4 * 60 * 60 + 30  -- 4 hours, 30 seconds

function dbot.backup._sanitizeName(name)
    if name == nil or name == "" then
        return os.date("backup-%Y%m%d-%H%M%S")
    end
    local cleaned = tostring(name):gsub("[^%w%-_]+", "_")
    if cleaned == "" then
        cleaned = os.date("backup-%Y%m%d-%H%M%S")
    end
    return cleaned
end

function dbot.backup._copyFile(sourcePath, destPath)
    local input = io.open(sourcePath, "rb")
    if not input then
        return false
    end
    local output = io.open(destPath, "wb")
    if not output then
        input:close()
        return false
    end
    output:write(input:read("*a"))
    input:close()
    output:close()
    return true
end

function dbot.backup._listFiles(dirPath)
    local files = {}
    if not lfs then
        return files
    end
    for entry in lfs.dir(dirPath) do
        if entry ~= "." and entry ~= ".." then
            local fullPath = dirPath .. entry
            local attr = lfs.attributes(fullPath)
            if attr and attr.mode == "file" then
                table.insert(files, entry)
            end
        end
    end
    return files
end

function dbot.backup._listDirs(dirPath)
    local dirs = {}
    if not lfs then
        return dirs
    end
    for entry in lfs.dir(dirPath) do
        if entry ~= "." and entry ~= ".." then
            local fullPath = dirPath .. entry
            local attr = lfs.attributes(fullPath)
            if attr and attr.mode == "directory" then
                table.insert(dirs, entry)
            end
        end
    end
    table.sort(dirs)
    return dirs
end

function dbot.backup._removeDir(dirPath)
    if not lfs then
        return false
    end
    for entry in lfs.dir(dirPath) do
        if entry ~= "." and entry ~= ".." then
            local fullPath = dirPath .. entry
            local attr = lfs.attributes(fullPath)
            if attr and attr.mode == "directory" then
                dbot.backup._removeDir(fullPath .. "/")
            else
                os.remove(fullPath)
            end
        end
    end
    lfs.rmdir(dirPath)
    return true
end

function dbot.backup.init.atInstall()
    return DRL_RET_SUCCESS
end

function dbot.backup.init.atActive()
    local backupDir = dbot.backup.getBackupDir()
    dbot.ensureDirectory(backupDir)
    
    -- Set up periodic backup timer
    if tempTimer then
        tempTimer(dbot.backup.timer.intervalSeconds, [[dbot.backup.current()]], true)
    end
    
    return DRL_RET_SUCCESS
end

function dbot.backup.fini(doSaveState)
    return DRL_RET_SUCCESS
end

local function getPluginStatePath()
    if not pluginStatePath then
        local safePluginId = pluginId or "unknown"
        pluginStatePath = getMudletHomeDir() .. "/dinv-" .. safePluginId .. "/"
    end
    return pluginStatePath
end

function dbot.backup.getBaseDir()
    local name = dbot.gmcp.getName()
    return getPluginStatePath() .. name .. "/", DRL_RET_SUCCESS
end

function dbot.backup.getCurrentDir()
    local name = dbot.gmcp.getName()
    return getPluginStatePath() .. name .. "/current/", DRL_RET_SUCCESS
end

function dbot.backup.getBackupDir()
    local name = dbot.gmcp.getName()
    return getPluginStatePath() .. name .. "/backup/", DRL_RET_SUCCESS
end

function dbot.backup.current()
    -- Placeholder for automatic backup functionality
    if not dbot.gmcp.isInitialized then
        return DRL_RET_UNINITIALIZED
    end
    
    if not dbot.init.initializedActive then
        return DRL_RET_UNINITIALIZED
    end
    
    dbot.debug("dbot.backup.current: Automatic backup triggered", "dbot.backup")
    return DRL_RET_SUCCESS
end

function dbot.backup.create(name, endTag)
    if not lfs then
        dbot.warn("Backup creation requires LuaFileSystem (lfs)")
        return DRL_RET_UNSUPPORTED
    end

    local backupName = dbot.backup._sanitizeName(name)
    local currentDir = dbot.backup.getCurrentDir()
    local backupDir = dbot.backup.getBackupDir()
    local targetDir = backupDir .. backupName .. "/"

    dbot.ensureDirectory(backupDir)
    dbot.ensureDirectory(targetDir)

    local files = dbot.backup._listFiles(currentDir)
    for _, fileName in ipairs(files) do
        local sourcePath = currentDir .. fileName
        local destPath = targetDir .. fileName
        if not dbot.backup._copyFile(sourcePath, destPath) then
            dbot.warn("Failed to copy file '" .. fileName .. "' to backup '" .. backupName .. "'")
            return DRL_RET_INTERNAL_ERROR
        end
    end

    dbot.info("Created backup '" .. backupName .. "' with " .. #files .. " file(s)")
    if inv and inv.tags and inv.tags.stop then
        return inv.tags.stop(invTagsBackup, endTag, DRL_RET_SUCCESS)
    end
    return DRL_RET_SUCCESS
end

function dbot.backup.delete(name, endTag, isQuiet)
    if not lfs then
        dbot.warn("Backup deletion requires LuaFileSystem (lfs)")
        return DRL_RET_UNSUPPORTED
    end

    local backupName = dbot.backup._sanitizeName(name)
    local backupDir = dbot.backup.getBackupDir() .. backupName .. "/"

    if lfs.attributes(backupDir) == nil then
        if not isQuiet then
            dbot.warn("Backup '" .. backupName .. "' does not exist")
        end
        return DRL_RET_MISSING_ENTRY
    end

    dbot.backup._removeDir(backupDir)
    if not isQuiet then
        dbot.info("Deleted backup '" .. backupName .. "'")
    end

    if inv and inv.tags and inv.tags.stop then
        return inv.tags.stop(invTagsBackup, endTag, DRL_RET_SUCCESS)
    end
    return DRL_RET_SUCCESS
end

function dbot.backup.restore(name, endTag)
    if not lfs then
        dbot.warn("Backup restore requires LuaFileSystem (lfs)")
        return DRL_RET_UNSUPPORTED
    end

    local backupName = dbot.backup._sanitizeName(name)
    local backupDir = dbot.backup.getBackupDir() .. backupName .. "/"
    local currentDir = dbot.backup.getCurrentDir()

    if lfs.attributes(backupDir) == nil then
        dbot.warn("Backup '" .. backupName .. "' does not exist")
        return DRL_RET_MISSING_ENTRY
    end

    dbot.ensureDirectory(currentDir)

    local currentFiles = dbot.backup._listFiles(currentDir)
    for _, fileName in ipairs(currentFiles) do
        os.remove(currentDir .. fileName)
    end

    local backupFiles = dbot.backup._listFiles(backupDir)
    for _, fileName in ipairs(backupFiles) do
        local sourcePath = backupDir .. fileName
        local destPath = currentDir .. fileName
        if not dbot.backup._copyFile(sourcePath, destPath) then
            dbot.warn("Failed to restore file '" .. fileName .. "' from backup '" .. backupName .. "'")
            return DRL_RET_INTERNAL_ERROR
        end
    end

    dbot.info("Restored backup '" .. backupName .. "' (" .. #backupFiles .. " file(s))")
    if inv and inv.tags and inv.tags.stop then
        return inv.tags.stop(invTagsBackup, endTag, DRL_RET_SUCCESS)
    end
    return DRL_RET_SUCCESS
end

function dbot.backup.list(endTag)
    if not lfs then
        dbot.warn("Backup listing requires LuaFileSystem (lfs)")
        return DRL_RET_UNSUPPORTED
    end

    local backupDir = dbot.backup.getBackupDir()
    dbot.ensureDirectory(backupDir)

    local backups = dbot.backup._listDirs(backupDir)
    dbot.print("@WBackups:@w")
    if #backups == 0 then
        dbot.print("  @Y(none)@w")
    else
        for _, backupName in ipairs(backups) do
            dbot.print("  @G" .. backupName .. "@w")
        end
    end

    if inv and inv.tags and inv.tags.stop then
        return inv.tags.stop(invTagsBackup, endTag, DRL_RET_SUCCESS)
    end
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Empty Line Module (suppress empty lines during operations)
----------------------------------------------------------------------------------------------------

dbot.emptyLine = {}
dbot.emptyLine.init = {}

function dbot.emptyLine.init.atInstall()
    return DRL_RET_SUCCESS
end

function dbot.emptyLine.fini(doSaveState)
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Prompt Module
----------------------------------------------------------------------------------------------------

dbot.prompt = {}
dbot.prompt.init = {}
dbot.prompt.isEnabled = true

----------------------------------------------------------------------------------------------------
-- Telnet Constants (placeholder for Mudlet)
----------------------------------------------------------------------------------------------------

dbot.telnet = {}
dbot.telnet.IAC          = 255
dbot.telnet.SB           = 250
dbot.telnet.SE           = 240
dbot.telnet.promptOption = 52
dbot.telnet.optionOn     = 1
dbot.telnet.optionOff    = 2

function dbot.prompt.init.atInstall()
    return DRL_RET_SUCCESS
end

function dbot.prompt.fini(doSaveState)
    return DRL_RET_SUCCESS
end

function dbot.prompt.enable()
    if not dbot.prompt.isEnabled then
        send("prompt")
        dbot.prompt.isEnabled = true
    end
end

function dbot.prompt.disable()
    if dbot.prompt.isEnabled then
        send("prompt")
        dbot.prompt.isEnabled = false
    end
end

----------------------------------------------------------------------------------------------------
-- Invmon Module
----------------------------------------------------------------------------------------------------

dbot.invmon = {}
dbot.invmon.init = {}
dbot.invmon.isEnabled = false

function dbot.invmon.init.atInstall()
    return DRL_RET_SUCCESS
end

function dbot.invmon.fini(doSaveState)
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Wish Module
----------------------------------------------------------------------------------------------------

dbot.wish = {}
dbot.wish.init = {}
dbot.wish.table = {}

function dbot.wish.init.atInstall()
    return DRL_RET_SUCCESS
end

function dbot.wish.fini(doSaveState)
    return DRL_RET_SUCCESS
end

function dbot.wish.has(wishName)
    return dbot.wish.table[wishName] == true
end

----------------------------------------------------------------------------------------------------
-- Execute Module (command execution framework)
----------------------------------------------------------------------------------------------------

dbot.execute = {}
dbot.execute.init = {}
dbot.execute.doDelayCommands = false
dbot.execute.afkIsPending = false
dbot.execute.quitIsPending = false
dbot.execute.noteIsPending = false
dbot.execute.bypassPrefix = "##DINV##"

dbot.execute.queue = {}
dbot.execute.queue.commands = {}
dbot.execute.queue.isDequeueRunning = false
dbot.execute.queue.fenceCounter = 1
dbot.execute.queue.fenceTimeoutSeconds = 30
dbot.execute.queue.fenceIsDetected = false
dbot.execute.fast = {}
dbot.execute.safe = {}

function dbot.execute.init.atInstall()
    return DRL_RET_SUCCESS
end

function dbot.execute.fini(doSaveState)
    return DRL_RET_SUCCESS
end

function dbot.execute.new()
    return {}
end

function dbot.execute.add(commandArray, command)
    if commandArray and command then
        table.insert(commandArray, command)
    end
end

function dbot.execute.fast.command(cmd)
    if cmd then
        send(cmd)
    end
end

function dbot.execute.queue.pushFast(cmd)
    table.insert(dbot.execute.queue.commands, 1, cmd)
end

function dbot.execute.queue.push(cmd)
    table.insert(dbot.execute.queue.commands, cmd)
end

function dbot.execute.queue.pop()
    return table.remove(dbot.execute.queue.commands, 1)
end

function dbot.execute.queue.fence(onDetected, timeoutSeconds)
    -- Process all queued commands
    while #dbot.execute.queue.commands > 0 do
        local cmd = dbot.execute.queue.pop()
        send(cmd)
    end

    if not tempRegexTrigger then
        dbot.warn("dbot.execute.queue.fence: tempRegexTrigger is unavailable")
        return DRL_RET_UNSUPPORTED
    end

    local fenceNumber = dbot.execute.queue.fenceCounter or 1
    local uniqueString = "{ DINV fence " .. fenceNumber .. " }"
    dbot.execute.queue.fenceCounter = fenceNumber + 1
    dbot.execute.queue.fenceIsDetected = false

    local function handleFence()
        dbot.execute.queue.fenceIsDetected = true
        if deleteLine then
            deleteLine()
        end
        if inv and inv.items and inv.items.refreshInProgress then
            dbot.note("Refresh in progress")
        end
        if onDetected then
            onDetected()
        end
    end

    tempRegexTrigger("^" .. uniqueString .. "$", handleFence)
    if sendSilent then
        sendSilent("echo " .. uniqueString)
    else
        send("echo " .. uniqueString)
    end

    if tempTimer then
        local timeout = timeoutSeconds or dbot.execute.queue.fenceTimeoutSeconds
        tempTimer(timeout, function()
            if not dbot.execute.queue.fenceIsDetected then
                dbot.warn("dbot.execute.queue.fence: fence message timed out")
            end
        end)
    end

    return DRL_RET_SUCCESS
end

function dbot.execute.safe.command(commandString, setupFn, setupData, resultFn, resultData)
    if commandString == nil or commandString == "" then
        return DRL_RET_INVALID_PARAM
    end
    return dbot.execute.safe.commands({ commandString }, setupFn, setupData, resultFn, resultData)
end

function dbot.execute.safe.commands(commandArray, setupFn, setupData, resultFn, resultData)
    if commandArray == nil then
        return DRL_RET_INVALID_PARAM
    end

    if setupFn then
        setupFn(setupData)
    end

    for _, cmd in ipairs(commandArray) do
        send(cmd)
    end

    if resultFn then
        resultFn(resultData, DRL_RET_SUCCESS)
    end

    return DRL_RET_SUCCESS
end

-- Safe execution with blocking
function dbot.execute.safe.blocking(commandArray, successCallback, failCallback, defaultCallback, timeout)
    if commandArray == nil then
        return DRL_RET_INVALID_PARAM
    end
    
    for _, cmd in ipairs(commandArray) do
        send(cmd)
    end
    
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Pagesize Module
----------------------------------------------------------------------------------------------------

dbot.pagesize = {}
dbot.pagesize.init = {}

function dbot.pagesize.init.atInstall()
    return DRL_RET_SUCCESS
end

function dbot.pagesize.fini(doSaveState)
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Remote Fetch Module (Mudlet HTTP helpers)
----------------------------------------------------------------------------------------------------

dbot.remote = {}
dbot.remote.getPkg = nil

function dbot.remote.get(url, protocol)
    if url == nil or url == "" then
        dbot.warn("dbot.remote.get: missing url parameter")
        return nil, DRL_RET_INVALID_PARAM
    end

    if protocol == nil or protocol == "" then
        dbot.warn("dbot.remote.get: missing protocol parameter")
        return nil, DRL_RET_INVALID_PARAM
    end

    if dbot.remote.getPkg ~= nil then
        dbot.info("Skipping remote request: another request is in progress")
        return nil, DRL_RET_BUSY
    end

    if not getHTTP then
        dbot.warn("dbot.remote.get: Mudlet HTTP API is unavailable")
        return nil, DRL_RET_UNSUPPORTED
    end

    dbot.remote.getPkg = {
        url = url,
        protocol = protocol,
        fileData = nil,
        status = nil,
        done = false,
    }

    getHTTP(url, function(body, status)
        if dbot.remote.getPkg then
            dbot.remote.getPkg.fileData = body
            dbot.remote.getPkg.status = status
            dbot.remote.getPkg.done = true
        end
    end)

    return nil, DRL_RET_BUSY
end

function dbot.remote.getCR()
    if dbot.remote.getPkg == nil then
        dbot.warn("dbot.remote.getCR: remote package is missing")
        return nil, DRL_RET_INTERNAL_ERROR
    end

    if not dbot.remote.getPkg.done then
        return nil, DRL_RET_BUSY
    end

    if tonumber(dbot.remote.getPkg.status) ~= 200 then
        dbot.warn("dbot.remote.getCR: Failed to retrieve remote file")
        local status = dbot.remote.getPkg.status
        dbot.remote.getPkg = nil
        return nil, status and DRL_RET_INTERNAL_ERROR or DRL_RET_MISSING_ENTRY
    end

    local data = dbot.remote.getPkg.fileData
    dbot.remote.getPkg = nil
    return data, DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Callback Module
----------------------------------------------------------------------------------------------------

dbot.callback = {}
dbot.callback.default = function() return DRL_RET_SUCCESS end
dbot.callback.waitInterval = 0.05

function dbot.callback.new()
    return { done = false, retval = DRL_RET_SUCCESS }
end

function dbot.callback.setReturn(resultData, retval)
    if resultData == nil then
        dbot.warn("dbot.callback.setReturn: callback parameter is nil")
        return DRL_RET_INVALID_PARAM
    end
    resultData.done = true
    resultData.retval = retval
    return DRL_RET_SUCCESS
end

function dbot.callback.isDone(resultData)
    return resultData ~= nil and resultData.done == true
end

function dbot.callback.wait(resultData, timeout)
    if resultData == nil then
        return DRL_RET_INVALID_PARAM
    end

    if dbot.callback.isDone(resultData) then
        return resultData.retval or DRL_RET_SUCCESS
    end

    if timeout and timeout > 0 and tempTimer then
        tempTimer(timeout, function()
            if resultData and not resultData.done then
                dbot.callback.setReturn(resultData, DRL_RET_TIMEOUT)
            end
        end)
    end

    return DRL_RET_BUSY
end

----------------------------------------------------------------------------------------------------
-- Ability Module (simple GMCP-backed availability checks)
----------------------------------------------------------------------------------------------------

dbot.ability = {}

function dbot.ability.isAvailable(abilityName)
    if not abilityName or abilityName == "" then
        return false
    end
    if gmcp and gmcp.char and gmcp.char.skills then
        for _, skill in pairs(gmcp.char.skills) do
            if type(skill) == "table" and skill.name and string.lower(skill.name) == string.lower(abilityName) then
                return true
            end
        end
    end
    return false
end

----------------------------------------------------------------------------------------------------
-- Damage Type Utilities
----------------------------------------------------------------------------------------------------

-- These will be populated once invStatField constants are defined
dbot.physicalTypes = {}
dbot.magicalTypes = {}

function dbot.isPhysical(damType)
    for _, physType in ipairs(dbot.physicalTypes) do
        if physType == damType then
            return true
        end
    end
    return false
end

function dbot.isMagical(damType)
    for _, magType in ipairs(dbot.magicalTypes) do
        if magType == damType then
            return true
        end
    end
    return false
end

----------------------------------------------------------------------------------------------------
-- Mob Name Normalization
----------------------------------------------------------------------------------------------------

function dbot.normalizeMobName(fullMobName)
    local mobName = fullMobName
    mobName = mobName:gsub("^[Aa]n? (.-)$", "%1")
    mobName = mobName:gsub("^[Tt]he (.-)$", "%1")
    mobName = mobName:gsub("^[Ss]ome (.-)$", "%1")
    mobName = mobName:gsub("^.*soul of (.-)$", "%1")
    mobName = mobName:gsub("^(.-) sea snake$", "%1")
    return mobName
end

----------------------------------------------------------------------------------------------------
-- Trigger/Timer Utilities (Mudlet versions)
----------------------------------------------------------------------------------------------------

dbot.triggers = {}
dbot.timers = {}

function dbot.deleteTrigger(name)
    if name == nil or name == "" then
        return DRL_RET_INVALID_PARAM
    end
    
    if dbot.triggers[name] then
        killTrigger(dbot.triggers[name])
        dbot.triggers[name] = nil
    end
    
    return DRL_RET_SUCCESS
end

function dbot.deleteTimer(name)
    if name == nil or name == "" then
        return DRL_RET_INVALID_PARAM
    end
    
    if dbot.timers[name] then
        killTimer(dbot.timers[name])
        dbot.timers[name] = nil
    end
    
    return DRL_RET_SUCCESS
end

function dbot.addTrigger(name, pattern, callback, flags)
    -- Create a Mudlet trigger
    local triggerId = tempRegexTrigger(pattern, callback)
    if triggerId then
        dbot.triggers[name] = triggerId
        return DRL_RET_SUCCESS
    end
    return DRL_RET_INTERNAL_ERROR
end

function dbot.addTimer(name, seconds, callback, isRepeating)
    local timerId
    if isRepeating then
        timerId = tempTimer(seconds, callback, true)
    else
        timerId = tempTimer(seconds, callback)
    end
    
    if timerId then
        dbot.timers[name] = timerId
        return DRL_RET_SUCCESS
    end
    return DRL_RET_INTERNAL_ERROR
end

----------------------------------------------------------------------------------------------------
-- Version Module
----------------------------------------------------------------------------------------------------

dbot.version = {}
dbot.version.changelog = {}
dbot.version.update = {}

function dbot.version.display()
    dbot.print("@WDINV Version: @G" .. (DINV.version or "unknown"))
end

----------------------------------------------------------------------------------------------------
-- Communication Log (placeholder)
----------------------------------------------------------------------------------------------------

function dbot.commLog(msg)
    -- Placeholder for communication log functionality
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- End of dbot module
----------------------------------------------------------------------------------------------------

dbot.debug("dbot module loaded", "dbot")
