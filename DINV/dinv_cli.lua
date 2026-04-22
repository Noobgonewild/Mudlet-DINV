----------------------------------------------------------------------------------------------------
-- DINV CLI Module
-- Command-line interface routing and help system
----------------------------------------------------------------------------------------------------

inv.cli = inv.cli or {}

----------------------------------------------------------------------------------------------------
-- CLI Command Definitions
-- Each command has: fn (function), usage (usage string), examples (help examples)
----------------------------------------------------------------------------------------------------

inv.cli.commands = {
    -- Inventory table access
    "build", "refresh", "search", "query", "report",
    -- Item management
    "get", "put", "store", "keyword", "organize",
    -- Equipment sets
    "set", "snapshot", "priority", "weapon",
    -- Equipment analysis
    "analyze", "usage", "compare", "covet",
    -- Advanced options
    "backup", "progress", "notify", "debug", "levelup", "forget", "ignore", "reset", "cache", "tags", "regen",
    -- Using equipment
    "portal", "consume", "pass",
    -- About the plugin
    "help",
    -- Custom modules
    "unused", "discover" -- "rid" command disabled per user request (kept in source as comments below)
}

----------------------------------------------------------------------------------------------------
-- Main CLI Router
----------------------------------------------------------------------------------------------------

function inv.cli.main(input)
    if input == nil or input == "" then
        inv.cli.help.fn()
        return DRL_RET_SUCCESS
    end
    
    -- Parse the input into command and arguments
    local words = {}
    for word in input:gmatch("%S+") do
        table.insert(words, word)
    end
    
    local command = string.lower(words[1] or "")
    local args = table.concat(words, " ", 2)
    
    -- Build wildcards table (for compatibility with original code)
    local wildcards = {}
    for i = 2, #words do
        wildcards[i-1] = words[i]
    end
    
    -- Route to appropriate command handler
    if inv.cli[command] and inv.cli[command].fn then
        return inv.cli[command].fn(command, input, wildcards)
    else
        dbot.warn("Unknown command: '" .. command .. "'")
        dbot.info("Type '@Gdinv help@W' for a list of commands.")
        return DRL_RET_INVALID_PARAM
    end
end

----------------------------------------------------------------------------------------------------
-- Help System
----------------------------------------------------------------------------------------------------

inv.cli.help = {}

function inv.cli.help.fn(name, line, wildcards)
    local topic = wildcards and wildcards[1] or nil
    
    if topic == nil or topic == "" then
        inv.cli.fullUsage()
    elseif inv.cli[topic] then
        if inv.cli[topic].examples then
            inv.cli[topic].examples()
        elseif inv.cli[topic].usage then
            inv.cli[topic].usage()
        else
            dbot.warn("No help available for '" .. topic .. "'")
            inv.cli.fullUsage()
        end
    else
        dbot.warn("No help available for '" .. topic .. "'")
        inv.cli.fullUsage()
    end
    
    return DRL_RET_SUCCESS
end

-- RID fallback help/command intentionally commented out (feature retained in source but disabled).
--[=[
inv.cli.rid = inv.cli.rid or {}

if not inv.cli.rid.usage then
    function inv.cli.rid.usage()
        dbot.printRaw(string.format("@W    %-50s @w- %s",
            pluginNameCmd .. " rid <itemid> [default|say|gt|tell <name>|channel <name>]",
            "Report identify stats for a single item over a channel"))
    end
end

if not inv.cli.rid.examples then
    function inv.cli.rid.examples()
        dbot.print([[@W
Usage:
    dinv rid <itemid>                         - Report stats in the default output
    dinv rid <itemid> say                     - Report stats via say
    dinv rid <itemid> tell <name>             - Report stats via tell
    dinv rid <itemid> channel <channel_name>  - Report stats via channel

This command is intended for testing item stat collection and does not store data.
]])
    end
end

if not inv.cli.rid.fn then
    function inv.cli.rid.fn(name, line, wildcards)
        local currentFn = inv.cli.rid.fn

        if DINV and DINV.loadModule then
            DINV.loadModule("dinv_rid")
        end

        if inv.cli.rid.fn and inv.cli.rid.fn ~= currentFn then
            return inv.cli.rid.fn(name, line, wildcards)
        end

        dbot.warn("rid module is not loaded. Try: lua DINV.initialize()")
        return DRL_RET_UNINITIALIZED
    end
end
]=]

function inv.cli.help.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " help @G[command]", "Display help information"))
end

function inv.cli.help.examples()
    dbot.print([[@W
Usage:
    dinv help           - Show full command list
    dinv help <command> - Show detailed help for a specific command
    
Available topics: build, refresh, search, query, set, priority, analyze,
                  report, progress, compare, covet, snapshot, weapon, portal, consume,
                  backup, notify, debug, levelup, unused, and more.
]])
end

----------------------------------------------------------------------------------------------------
-- Full Usage Display
----------------------------------------------------------------------------------------------------

function inv.cli.fullUsage()
    dbot.printRaw([[@Y
  DINV - Durel's Inventory Manager (Mudlet Port)
  ================================================@W
@CInventory Table Access:@w]])

    if inv.cli.build and inv.cli.build.usage then inv.cli.build.usage() end
    if inv.cli.refresh and inv.cli.refresh.usage then inv.cli.refresh.usage() end
    if inv.cli.search and inv.cli.search.usage then inv.cli.search.usage() end
    if inv.cli.query and inv.cli.query.usage then inv.cli.query.usage() end
    if inv.cli.report and inv.cli.report.usage then inv.cli.report.usage() end

    dbot.printRaw("@CItem Management:@w")
    if inv.cli.get and inv.cli.get.usage then inv.cli.get.usage() end
    if inv.cli.put and inv.cli.put.usage then inv.cli.put.usage() end
    if inv.cli.store and inv.cli.store.usage then inv.cli.store.usage() end
    if inv.cli.keyword and inv.cli.keyword.usage then inv.cli.keyword.usage() end
    if inv.cli.organize and inv.cli.organize.usage then inv.cli.organize.usage() end
    if inv.cli.unused and inv.cli.unused.usage then inv.cli.unused.usage() end

    dbot.printRaw("@CEquipment Sets:@w")
    if inv.cli.set and inv.cli.set.usage then inv.cli.set.usage() end
    if inv.cli.snapshot and inv.cli.snapshot.usage then inv.cli.snapshot.usage() end
    if inv.cli.priority and inv.cli.priority.usage then inv.cli.priority.usage() end
    if inv.cli.weapon and inv.cli.weapon.usage then inv.cli.weapon.usage() end

    dbot.printRaw("@CEquipment Analysis:@w")
    if inv.cli.analyze and inv.cli.analyze.usage then inv.cli.analyze.usage() end
    if inv.cli.usage and inv.cli.usage.usage then inv.cli.usage.usage() end
    if inv.cli.compare and inv.cli.compare.usage then inv.cli.compare.usage() end
    if inv.cli.covet and inv.cli.covet.usage then inv.cli.covet.usage() end
    if inv.cli.discover and inv.cli.discover.usage then inv.cli.discover.usage() end

    dbot.printRaw("@CNotification Options:@w")
    if inv.cli.notify and inv.cli.notify.usage then inv.cli.notify.usage() end
    if inv.cli.debug and inv.cli.debug.usage then inv.cli.debug.usage() end
    if inv.cli.levelup and inv.cli.levelup.usage then inv.cli.levelup.usage() end

    dbot.printRaw("@CAdvanced Options:@w")
    if inv.cli.backup and inv.cli.backup.usage then inv.cli.backup.usage() end
    if inv.cli.forget and inv.cli.forget.usage then inv.cli.forget.usage() end
    if inv.cli.ignore and inv.cli.ignore.usage then inv.cli.ignore.usage() end
    if inv.cli.reset and inv.cli.reset.usage then inv.cli.reset.usage() end
    if inv.cli.cache and inv.cli.cache.usage then inv.cli.cache.usage() end
    if inv.cli.tags and inv.cli.tags.usage then inv.cli.tags.usage() end
    if inv.cli.regen and inv.cli.regen.usage then inv.cli.regen.usage() end
    if inv.cli.progress and inv.cli.progress.usage then inv.cli.progress.usage() end

    dbot.printRaw("@CUsing Equipment:@w")
    if inv.cli.portal and inv.cli.portal.usage then inv.cli.portal.usage() end
    if inv.cli.consume and inv.cli.consume.usage then inv.cli.consume.usage() end
    if inv.cli.pass and inv.cli.pass.usage then inv.cli.pass.usage() end

    dbot.printRaw("@CAbout:@w")
    inv.cli.help.usage()
end

----------------------------------------------------------------------------------------------------
-- Build Command - with abort support
----------------------------------------------------------------------------------------------------

inv.cli.build = inv.cli.build or {}

function inv.cli.build.fn(name, line, wildcards)
    local arg = wildcards and wildcards[1] or ""
    local endTag = inv.tags.new(line)

    arg = string.lower(arg):gsub("^%s*(.-)%s*$", "%1")  -- trim and lowercase

    -- Handle abort
    if arg == "abort" or arg == "stop" or arg == "cancel" then
        if inv.items.buildAbort then
            return inv.items.buildAbort()
        else
            dbot.info("No build abort function available")
            return DRL_RET_SUCCESS
        end
    end

    -- Handle status check
    if arg == "status" then
        if inv.items.buildInProgress then
            cecho("\n<cyan>[DINV] Build in progress: " .. (inv.items.getProgressString and inv.items.getProgressString() or "unknown") .. "\n")
        else
            cecho("\n<cyan>[DINV] No build in progress.\n")
        end
        return inv.tags.stop(invTagsBuild, endTag, DRL_RET_SUCCESS)
    end

    -- Require confirmation
    if arg ~= "confirm" then
        -- Show status if build in progress
        if inv.items.buildInProgress then
            cecho("\n<yellow>[DINV] Build in progress: " .. (inv.items.getProgressString and inv.items.getProgressString() or "unknown") .. "\n")
            cecho("<yellow>[DINV] To cancel: dinv build abort\n")
            return inv.tags.stop(invTagsBuild, endTag, DRL_RET_SUCCESS)
        end

        dbot.print([[@W
Building the inventory table will scan ALL items in your inventory and identify them.
This can take several minutes depending on how many items you have.

@YCommands:@w
  @Gdinv build [confirm | abort]@w  - Start or cancel a build
]])
        return inv.tags.stop(invTagsBuild, endTag, DRL_RET_SUCCESS)
    end

    -- Start build
    return inv.items.build(endTag)
end

function inv.cli.build.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s",
               pluginNameCmd .. " build @G[confirm | abort]", "Build inventory table or cancel a running build"))
end

function inv.cli.build.examples()
    dbot.print([[@W
Usage:
    dinv build [confirm | abort]

This command scans your entire inventory and identifies all items. This is required
before you can use most other dinv features. The process may take several minutes
depending on how many items you have.

The build process:
  1. Scans worn equipment (eqdata)
  2. Scans main inventory (invdata)
  3. Scans inside each container
  4. Identifies each item (taking from containers if needed)

After the initial build, changes are tracked automatically via invmon/invitem.
Use "dinv refresh" to check tracking status.
]])
end

----------------------------------------------------------------------------------------------------
-- Refresh Command - Fixed to not rebuild
----------------------------------------------------------------------------------------------------

inv.cli.refresh = inv.cli.refresh or {}

function inv.cli.refresh.fn(name, line, wildcards)
    local endTag = inv.tags.new(line)
    local args = wildcards or {}

    -- Check if build is in progress
    if inv.items.buildInProgress then
        cecho("\n<yellow>[DINV] A build is currently in progress.\n")
        cecho("<yellow>[DINV] Status: " .. (inv.items.getProgressString and inv.items.getProgressString() or "unknown") .. "\n")
        cecho("<yellow>[DINV] To cancel: dinv build abort\n")
        return inv.tags.stop(invTagsRefresh, endTag, DRL_RET_BUSY)
    end

    local action = args[1] and args[1]:lower() or "status"
    if action == "on" then
        local periodMin = inv.config.getRefreshPeriod()
        local eagerSec = inv.config.get("refreshEagerSec") or 0
        inv.items.refreshOn(periodMin, eagerSec)
        cecho("\n<green>[DINV] Refresh enabled. Period: " .. periodMin .. " minute(s).\n")
        return inv.tags.stop(invTagsRefresh, endTag, DRL_RET_SUCCESS)
    elseif action == "force" then
        local retval = inv.items.refresh(0, invItemsRefreshLocDirty, nil, { identifyPartials = true })
        if retval ~= DRL_RET_SUCCESS then
            return inv.tags.stop(invTagsRefresh, endTag, retval)
        end
        cecho("\n<green>[DINV] Refresh started (partial items will be fully identified).\n")
        return inv.tags.stop(invTagsRefresh, endTag, DRL_RET_SUCCESS)
    elseif action == "off" then
        inv.items.refreshOff()
        cecho("\n<yellow>[DINV] Refresh disabled.\n")
        return inv.tags.stop(invTagsRefresh, endTag, DRL_RET_SUCCESS)
    elseif action == "period" then
        local minutes = tonumber(args[2] or "")
        if not minutes or minutes <= 0 then
            cecho("\n<yellow>[DINV] Invalid refresh period. Usage: dinv refresh period <minutes>\n")
            return inv.tags.stop(invTagsRefresh, endTag, DRL_RET_INVALID_PARAM)
        end
        if inv.config.isRefreshEnabled() then
            local retval = inv.items.refreshOn(minutes, inv.config.get("refreshEagerSec") or 0)
            if retval ~= DRL_RET_SUCCESS then
                return inv.tags.stop(invTagsRefresh, endTag, retval)
            end
        else
            local retval = inv.config.setRefreshPeriod(minutes)
            if retval ~= DRL_RET_SUCCESS then
                return inv.tags.stop(invTagsRefresh, endTag, retval)
            end
        end
        cecho("\n<green>[DINV] Refresh period set to " .. minutes .. " minute(s).\n")
        return inv.tags.stop(invTagsRefresh, endTag, DRL_RET_SUCCESS)
    elseif action == "check" then
        if not inv.config.isRefreshEnabled() then
            cecho("\n<yellow>[DINV] Refresh is disabled.\n")
            return inv.tags.stop(invTagsRefresh, endTag, DRL_RET_SUCCESS)
        end
        local minutesLeft = inv.items.refreshGetMinutesLeft and inv.items.refreshGetMinutesLeft() or nil
        if minutesLeft then
            cecho("\n<green>[DINV] Next refresh in " .. minutesLeft .. " minute(s).\n")
        else
            cecho("\n<yellow>[DINV] Refresh timer is active, but next refresh time is unknown.\n")
        end
        return inv.tags.stop(invTagsRefresh, endTag, DRL_RET_SUCCESS)
    end

    -- Check if we have inventory data
    local itemCount = inv.items.getCount and inv.items.getCount() or 0

    if itemCount == 0 then
        cecho("\n<yellow>[DINV] No inventory data found.\n")
        cecho("<yellow>[DINV] Run 'dinv build confirm' to scan your inventory.\n")
        return inv.tags.stop(invTagsRefresh, endTag, DRL_RET_UNINITIALIZED)
    end

    -- Count items by type
    local containerCount = 0
    local wornCount = 0
    local invCount = 0

    for objId, item in pairs(inv.items.table or {}) do
        if item.stats then
            if inv.items.isWorn(objId) then
                wornCount = wornCount + 1
            elseif item.stats[invStatFieldContainer] and item.stats[invStatFieldContainer] ~= "" then
                containerCount = containerCount + 1
            else
                invCount = invCount + 1
            end
        end
    end

    cecho("\n<cyan>[DINV] Inventory Status:\n")
    cecho("<white>  Total items tracked: <green>" .. itemCount .. "\n")
    cecho("<white>    - Worn:            <green>" .. wornCount .. "\n")
    cecho("<white>    - In inventory:    <green>" .. invCount .. "\n")
    cecho("<white>    - In containers:   <green>" .. containerCount .. "\n")
    cecho("\n")
    cecho("<white>  Changes are tracked automatically via invmon/invitem.\n")
    cecho("<white>  Refresh timer:       <green>" .. (inv.config.isRefreshEnabled() and "on" or "off") .. "<white> (" .. tostring(inv.config.getRefreshPeriod()) .. " min)\n")
    if inv.config.isRefreshEnabled() then
        local minutesLeft = inv.items.refreshGetMinutesLeft and inv.items.refreshGetMinutesLeft() or nil
        if minutesLeft then
            cecho("<white>  Next refresh in:     <green>" .. minutesLeft .. "<white> min\n")
        end
    end
    cecho("<white>  To do a full rescan: <green>dinv build confirm\n")
    cecho("\n")

    return inv.tags.stop(invTagsRefresh, endTag, DRL_RET_SUCCESS)
end

function inv.cli.refresh.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s",
               pluginNameCmd .. " refresh @G[on | force | off | period <min> | check]", "Inventory tracking status and refresh controls"))
end

function inv.cli.refresh.examples()
    dbot.print([[@W
Usage:
    dinv refresh [on | force | off | period <min> | check]

Shows the current inventory tracking status. Changes to your inventory are
tracked automatically via invmon/invitem events.

Subcommands:
  on            Enable automatic refreshes using the configured period.
  force         Run an immediate refresh (dirty locations only), then fully identify
                any items still marked partial.
  off           Disable automatic refreshes.
  period <min>  Set the automatic refresh period (minutes). If refreshes are on,
                the timer is rescheduled to the new period.
  check         Show time remaining until the next automatic refresh.

If you need to do a full rescan (e.g., after manual changes or if data seems
out of sync), use 'dinv build confirm' instead.
]])
end


----------------------------------------------------------------------------------------------------
-- Search Command
----------------------------------------------------------------------------------------------------

inv.cli.search = {}

function inv.cli.search.fn(name, line, wildcards)
    local tokens = wildcards or {}
    local displayMode = "basic"
    local explicitMode = false
    if #tokens > 0 then
        local mode = tostring(tokens[1]):lower()
        if mode == "basic" or mode == "objid" or mode == "full" then
            displayMode = mode
            explicitMode = true
            table.remove(tokens, 1)
        end
    end

    local query = table.concat(tokens, " ")
    local endTag = inv.tags.new(line)

    local itemIds, retval = inv.items.search(query)
    if retval == DRL_RET_SUCCESS then
        inv.items.sort(itemIds)
        local trimmed = tostring(query or ""):gsub("^%s*(.-)%s*$", "%1")
        if (not explicitMode) and trimmed:match("^%d+$") then
            displayMode = "itemid"
        end
        inv.items.displayResults(itemIds, displayMode)
    end
    
    return inv.tags.stop(invTagsSearch, endTag, retval)
end

function inv.cli.search.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " search @G[basic|objid|full] <query>", "Search inventory"))
end

----------------------------------------------------------------------------------------------------
-- Query Help Topic
----------------------------------------------------------------------------------------------------

inv.cli.query = {}
function inv.cli.query.fn(name, line, wildcards)
    inv.cli.query.examples()
    return DRL_RET_SUCCESS
end
function inv.cli.query.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s",
               pluginNameCmd .. " query", "Query syntax and searchable tags"))
end

----------------------------------------------------------------------------------------------------
-- Report Command
----------------------------------------------------------------------------------------------------

inv.cli.report = {}

function inv.cli.report.fn(name, line, wildcards)
    local tokens = wildcards or {}
    local action = tostring(tokens[1] or ""):lower()
    local channel = inv.report and inv.report.getChannel and inv.report.getChannel() or "echo"

    if action == nil or action == "" then
        inv.cli.report.usage()
        return DRL_RET_INVALID_PARAM
    end

    if action == "channel" then
        local channelName = tokens[2]
        if channelName == nil or channelName == "" then
            dbot.warn("Usage: dinv report channel <channel>")
            return DRL_RET_INVALID_PARAM
        end
        if inv.report and inv.report.setChannel then
            inv.report.setChannel(channelName)
        end
        dbot.info("Report channel set to '" .. channelName .. "'")
        return DRL_RET_SUCCESS
    end

    if action == "set" then
        local priorityName = tokens[2]
        local level = tokens[3]
        if inv.report and inv.report.reportSetStats then
            return inv.report.reportSetStats(priorityName, level, channel)
        end
        dbot.warn("Report module is not loaded. Try: lua DINV.initialize()")
        return DRL_RET_UNINITIALIZED
    end

    local query = table.concat(tokens, " ")
    local trimmed = tostring(query or ""):gsub("^%s*(.-)%s*$", "%1")
    if trimmed == "" then
        inv.cli.report.usage()
        return DRL_RET_INVALID_PARAM
    end

    local itemIds, retval = inv.items.search(query)
    if retval == DRL_RET_SUCCESS then
        inv.items.sort(itemIds)
        local displayMode = trimmed:match("^%d+$") and "itemid" or "basic"
        if displayMode ~= "itemid" or channel ~= "echo" then
            inv.items.displayResults(itemIds, displayMode)
        end
        if displayMode == "itemid" and inv.report and inv.report.reportItemIds then
            inv.report.reportItemIds(itemIds, channel)
        elseif displayMode ~= "itemid" then
            dbot.info("@WClick an ID or use '@Gdinv report <itemid>@W' to send a report over the configured channel (@G" ..
                tostring(channel) .. "@W).")
        end
    end

    return retval
end

function inv.cli.report.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s",
               pluginNameCmd .. " report @G<itemid|itemname|set|channel>", "Report item or set stats"))
end

function inv.cli.report.examples()
    dbot.print([[@W
Usage:
    dinv report channel @G<channel>@W        - Set the report channel (default: echo)
    dinv report @G<itemid>@W                 - Report an item summary to the configured channel
    dinv report @G<itemname>@W               - Run a search (reports require an id)
    dinv report set @G<priority> [level]@W   - Report set bonuses for a priority
]])
end

----------------------------------------------------------------------------------------------------
-- Progress Command
----------------------------------------------------------------------------------------------------

inv.cli.progress = {}

function inv.cli.progress.fn(name, line, wildcards)
    local mode = tostring((wildcards and wildcards[1]) or ""):lower()
    if mode == "" or mode == "status" then
        local current = (inv.items and inv.items.getReportMode and inv.items.getReportMode()) or "classic"
        dbot.info("Progress mode is '" .. tostring(current) .. "'. Usage: dinv progress <classic|inline>")
        return DRL_RET_SUCCESS
    end

    if mode ~= "classic" and mode ~= "inline" then
        dbot.warn("Usage: dinv progress <classic|inline>")
        return DRL_RET_INVALID_PARAM
    end

    if inv.items and inv.items.setReportMode then
        local retval = inv.items.setReportMode(mode)
        if retval == DRL_RET_SUCCESS then
            dbot.info("Progress mode set to '" .. mode .. "'")
            return DRL_RET_SUCCESS
        end
    end

    dbot.warn("Unable to set progress mode to '" .. mode .. "'")
    return DRL_RET_INVALID_PARAM
end

function inv.cli.progress.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s",
               pluginNameCmd .. " progress @G<classic|inline>", "Set identify progress display mode"))
end

function inv.cli.progress.examples()
    local mode = (inv.items and inv.items.getReportMode and inv.items.getReportMode()) or "classic"
    dbot.print([[@W
Usage:
    dinv progress @G<classic|inline>@W - Set identify progress style
    dinv progress status                       - Show current progress style

Current mode: @G]] .. tostring(mode) .. [[@W

Modes:
    classic - Default line-by-line progress output
    inline  - Reuse a single progress line in the main console
]])
end


----------------------------------------------------------------------------------------------------
-- Get/Put/Store Commands
----------------------------------------------------------------------------------------------------

inv.cli.get = {}
function inv.cli.get.fn(name, line, wildcards)
    local query = table.concat(wildcards or {}, " ")
    return inv.items.get(query, inv.tags.new(line))
end
function inv.cli.get.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " get @G<query>", "Get items from containers"))
end

inv.cli.put = {}
function inv.cli.put.fn(name, line, wildcards)
    local container = wildcards and wildcards[1] or ""
    local query = table.concat(wildcards or {}, " ", 2)
    return inv.items.put(container, query, inv.tags.new(line))
end
function inv.cli.put.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " put @G<container> <query>", "Put items in container"))
end

inv.cli.store = {}
function inv.cli.store.fn(name, line, wildcards)
    local query = table.concat(wildcards or {}, " ")
    return inv.items.store(query, inv.tags.new(line))
end
function inv.cli.store.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " store @G<query>", "Store items in home containers"))
end

----------------------------------------------------------------------------------------------------
-- Keyword Command
----------------------------------------------------------------------------------------------------

inv.cli.keyword = {}
function inv.cli.keyword.fn(name, line, wildcards)
    local action = wildcards and wildcards[1] or ""
    local keyword = wildcards and wildcards[2] or ""
    local query = table.concat(wildcards or {}, " ", 3)
    
    if action == "add" then
        return inv.keyword.add(keyword, query, inv.tags.new(line))
    elseif action == "remove" then
        return inv.keyword.remove(keyword, query, inv.tags.new(line))
    else
        dbot.warn("Usage: dinv keyword [add|remove] <keyword> <query>")
        return DRL_RET_INVALID_PARAM
    end
end
function inv.cli.keyword.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " keyword @G[add|remove] <kw> <query>", "Manage custom keywords"))
end

----------------------------------------------------------------------------------------------------
-- Organize Command
----------------------------------------------------------------------------------------------------

inv.cli.organize = {}

----------------------------------------------------------------------------------------------------
-- Organize Command Dispatcher
-- Handles: dinv organize add <container> <query>
--          dinv organize clear <container>
--          dinv organize display [<container>]
--          dinv organize [<query>]  (runs organize)
----------------------------------------------------------------------------------------------------

function inv.cli.organize.dispatch(name, line, wildcards, args, endTag)
    -- Create endTag if not provided
    endTag = endTag or inv.tags.new(line or "organize")

    -- Check initialization
    if not inv.init.initializedActive then
        dbot.info("Skipping organize request: plugin is not yet initialized (are you AFK or sleeping?)")
        return inv.tags.stop(invTagsOrganize, endTag, DRL_RET_UNINITIALIZED)
    end

    if dbot.gmcp and dbot.gmcp.statePreventsActions and dbot.gmcp.statePreventsActions() then
        dbot.info("Skipping organize request: character's state does not allow actions")
        return inv.tags.stop(invTagsOrganize, endTag, DRL_RET_NOT_ACTIVE)
    end

    -- Parse first word as subcommand
    local subCmd = wildcards and wildcards[1] or ""
    subCmd = string.lower(subCmd or "")

    dbot.debug("CLI: organize dispatch subCmd=\"" .. subCmd .. "\" args=\"" .. (args or "") .. "\"", "inv.cli")

    if subCmd == "add" then
        -- dinv organize add <container> <query>
        local container = wildcards[2] or ""
        -- Query is everything from wildcards[3] onward
        local queryParts = {}
        for i = 3, #wildcards do
            table.insert(queryParts, wildcards[i])
        end
        local queryString = table.concat(queryParts, " ")

        if container == "" then
            dbot.warn("Usage: dinv organize add <container> <query>")
            return inv.tags.stop(invTagsOrganize, endTag, DRL_RET_INVALID_PARAM)
        end
        if queryString == "" then
            dbot.warn("Usage: dinv organize add <container> <query>")
            dbot.warn("Containers are not allowed to own all possible items (empty query)")
            return inv.tags.stop(invTagsOrganize, endTag, DRL_RET_INVALID_PARAM)
        end

        return inv.organize.add(container, queryString, endTag)

    elseif subCmd == "clear" then
        -- dinv organize clear <container>
        local container = wildcards[2] or ""
        if container == "" then
            dbot.warn("Usage: dinv organize clear <container>")
            return inv.tags.stop(invTagsOrganize, endTag, DRL_RET_INVALID_PARAM)
        end

        return inv.organize.clear(container, endTag)

    elseif subCmd == "display" then
        -- dinv organize display [<container>]
        local container = wildcards[2]  -- optional
        return inv.organize.display(container, endTag)

    else
        -- No recognized subcommand - run organize with the full args as query
        -- This handles: dinv organize
        --               dinv organize type weapon
        local queryString = args or ""
        if subCmd ~= "" then
            -- subCmd wasn't a known command, so it's part of the query
            queryString = table.concat(wildcards or {}, " ")
        end

        return inv.organize.run(queryString, endTag)
    end
end

-- Set fn to point to dispatch for compatibility
inv.cli.organize.fn = inv.cli.organize.dispatch

function inv.cli.organize.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", pluginNameCmd .. " organize @Gadd <container> <query>", "Add query to container"))
    dbot.printRaw(string.format("@W    %-50s @w- %s", pluginNameCmd .. " organize @Gclear <container>", "Clear container queries"))
    dbot.printRaw(string.format("@W    %-50s @w- %s", pluginNameCmd .. " organize @Gdisplay [container]", "Show organize rules"))
    dbot.printRaw(string.format("@W    %-50s @w- %s", pluginNameCmd .. " organize @G[query]", "Run organize"))
end

----------------------------------------------------------------------------------------------------
-- Set Command
----------------------------------------------------------------------------------------------------

inv.cli.set = {}
function inv.cli.set.fn(name, line, wildcards)
    local action = wildcards and wildcards[1] or ""
    local priority = wildcards and wildcards[2] or ""
    local arg3 = wildcards and wildcards[3] or ""
    local level = tonumber(arg3)
    local endTag = inv.tags.new(line)
    
    if action == "wear" then
        return inv.set.wear(priority, level, endTag)
    elseif action == "test" then
        return inv.set.test(priority, arg3, endTag)
    elseif action == "display" then
        return inv.set.display(priority, level, endTag, true)
    elseif action == "clear" or action == "delete" then
        local retval = inv.set.delete(priority, level)
        if retval == DRL_RET_SUCCESS then
            dbot.info("Cleared set cache for '" .. priority .. "' at level " .. tostring(level or "current") .. ".")
        end
        return inv.tags.stop(invTagsSet, endTag, retval)
    else
        dbot.warn("Usage: dinv set [wear | test <cache|live> | display | clear] <priority> [level]")
        return inv.tags.stop(invTagsSet, endTag, DRL_RET_INVALID_PARAM)
    end
end
function inv.cli.set.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " set @G[wear | test <cache|live> | display | clear] <priority> [level]", "Equipment sets"))
end

----------------------------------------------------------------------------------------------------
-- Snapshot Command
----------------------------------------------------------------------------------------------------

inv.cli.snapshot = {}
function inv.cli.snapshot.fn(name, line, wildcards)
    local action = wildcards and wildcards[1] or ""
    local name = wildcards and wildcards[2] or ""
    local endTag = inv.tags.new(line)
    
    if action == "create" then
        if name == "" then
            dbot.warn("Usage: dinv snapshot create <name>")
            return inv.tags.stop(invTagsSnapshot, endTag, DRL_RET_INVALID_PARAM)
        end
        return inv.snapshot.create(name, endTag)
    elseif action == "delete" then
        if name == "" then
            dbot.warn("Usage: dinv snapshot delete <name>")
            return inv.tags.stop(invTagsSnapshot, endTag, DRL_RET_INVALID_PARAM)
        end
        return inv.snapshot.delete(name, endTag)
    elseif action == "wear" then
        if name == "" then
            dbot.warn("Usage: dinv snapshot wear <name>")
            return inv.tags.stop(invTagsSnapshot, endTag, DRL_RET_INVALID_PARAM)
        end
        return inv.snapshot.wear(name, endTag)
    elseif action == "display" then
        return inv.snapshot.display(name, endTag)
    elseif action == "list" or action == "" then
        return inv.snapshot.list(endTag)
    else
        dbot.warn("Usage: dinv snapshot [create|delete|wear|display|list] [name]")
        return inv.tags.stop(invTagsSnapshot, endTag, DRL_RET_INVALID_PARAM)
    end
end
function inv.cli.snapshot.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " snapshot @G[create|delete|wear|display|list] [name]", "Equipment snapshots"))
end

----------------------------------------------------------------------------------------------------
-- Priority Command
----------------------------------------------------------------------------------------------------

inv.cli.priority = {}
function inv.cli.priority.fn(name, line, wildcards)
    local action = wildcards and wildcards[1] or ""
    local name = wildcards and wildcards[2] or ""
    local option = wildcards and wildcards[3] or ""
    local endTag = inv.tags.new(line)
    
    if action == "create" then
        return inv.priority.create(name, endTag)
    elseif action == "delete" then
        return inv.priority.delete(name)
    -- elseif action == "edit" then
    --     local useAllFields = option == "full"
    --     return inv.priority.edit(name, useAllFields, false, endTag)
    elseif action == "copy" then
        return inv.priority.copy(name)
    elseif action == "paste" then
        return inv.priority.paste(name)
    elseif action == "export" then
        local retval = inv.priority.exportToFile(name)
        return inv.tags.stop(invTagsPriority, endTag, retval)
    elseif action == "import" then
        return inv.priority.importFromFile(name, endTag)
    elseif action == "display" then
        return inv.priority.display(name, endTag)
    elseif action == "default" then
        local retval = inv.priority.setDefault(name)
        return inv.tags.stop(invTagsPriority, endTag, retval)
    elseif action == "status" then
        return inv.priority.status(endTag)
    elseif action == "compare" then
        local name2 = wildcards and wildcards[3] or ""
        if name == "" or name2 == "" then
            dbot.warn("Usage: dinv priority compare <priority1> <priority2>")
            return DRL_RET_INVALID_PARAM
        end
        return inv.priority.compare(name, name2)
    elseif action == "list" or action == "" then
        return inv.priority.list(endTag)
    else
        dbot.warn("Usage: dinv priority [list|display|default|status|create|delete|copy|paste|compare|export|import] [name]")
        return DRL_RET_INVALID_PARAM
    end
end
function inv.cli.priority.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " priority @G[list|display|default|status|create|delete|copy|paste|compare|export|import] [name]", "Stat priorities"))
end

----------------------------------------------------------------------------------------------------
-- Weapon Command
----------------------------------------------------------------------------------------------------

inv.cli.weapon = {}
function inv.cli.weapon.fn(name, line, wildcards)
    local priority = wildcards and wildcards[1] or ""
    local arg2 = wildcards and wildcards[2] or ""
    local damTypes = table.concat(wildcards or {}, " ", 2)
    local endTag = inv.tags.new(line)
    
    if priority == "listdamtypes" then
        return inv.weapon.listDamTypes(endTag)
    elseif priority == "next" and string.lower(arg2) == "any" then
        return inv.weapon.next(endTag, true)
    elseif priority == "next" then
        return inv.weapon.next(endTag, false)
    else
        return inv.weapon.use(priority, damTypes, endTag)
    end
end
function inv.cli.weapon.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " weapon @G[next [any] | listdamtypes | <priority> <damtypes>]", "Weapon sets by damage type"))
end

----------------------------------------------------------------------------------------------------
-- Analyze Command
----------------------------------------------------------------------------------------------------

inv.cli.analyze = {}
function inv.cli.analyze.fn(name, line, wildcards)
    local action = wildcards and wildcards[1] or ""
    local priority = wildcards and wildcards[2] or ""
    local levelOrSkip = wildcards and wildcards[3] or ""
    local endTag = inv.tags.new(line)
    
    if action == "create" then
        return inv.analyze.create(priority, nil, endTag)
    elseif action == "delete" then
        return inv.analyze.delete(priority, endTag)
    elseif action == "display" then
        return inv.analyze.display(priority, levelOrSkip, endTag)
    elseif action == "list" or action == "" then
        return inv.analyze.list(endTag)
    else
        dbot.warn("Usage: dinv analyze [create|delete|display|list] [priority] [level]")
        return inv.tags.stop(invTagsAnalyze, endTag, DRL_RET_INVALID_PARAM)
    end
end
function inv.cli.analyze.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " analyze @G[create|delete|display|list] [priority] [level]", "Optimal set analysis"))
end

----------------------------------------------------------------------------------------------------
-- Usage Command (item usage tracking)
----------------------------------------------------------------------------------------------------

inv.cli.usage = {}
function inv.cli.usage.fn(name, line, wildcards)
    local priority = wildcards and wildcards[1] or ""
    local query = table.concat(wildcards or {}, " ", 2)
    return inv.usage.display(priority, query, inv.tags.new(line))
end
function inv.cli.usage.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " usage @G<priority> [query]", "Item usage by level"))
end

----------------------------------------------------------------------------------------------------
-- Compare Command
----------------------------------------------------------------------------------------------------

inv.cli.compare = {}
function inv.cli.compare.fn(name, line, wildcards)
    local priority = wildcards and wildcards[1] or ""
    local itemName = table.concat(wildcards or {}, " ", 2)
    return inv.compare.items(priority, itemName, nil, inv.tags.new(line))
end
function inv.cli.compare.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " compare @G<priority> <item>", "Compare item to current gear"))
end

----------------------------------------------------------------------------------------------------
-- Covet Command
----------------------------------------------------------------------------------------------------

inv.cli.covet = {}
function inv.cli.covet.fn(name, line, wildcards)
    local priority = wildcards and wildcards[1] or ""
    local auctionNum = wildcards and wildcards[2] or ""
    local skipLevels = tonumber(wildcards and wildcards[3] or "1") or 1
    if skipLevels < 1 then
        skipLevels = 1
    elseif skipLevels > 200 then
        skipLevels = 200
    end
    return inv.compare.covet(priority, auctionNum, skipLevels, inv.tags.new(line))
end
function inv.cli.covet.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " covet @G<priority name> <auction #> @Y<skip #>", "Analyze auction item"))
end

----------------------------------------------------------------------------------------------------
-- Backup Command
----------------------------------------------------------------------------------------------------

inv.cli.backup = {}
function inv.cli.backup.fn(name, line, wildcards)
    local action = wildcards and wildcards[1] or ""
    local name = wildcards and wildcards[2] or ""
    local endTag = inv.tags.new(line)
    
    if action == "create" then
        return dbot.backup.create(name, endTag)
    elseif action == "delete" then
        return dbot.backup.delete(name, endTag)
    elseif action == "restore" then
        return dbot.backup.restore(name, endTag)
    elseif action == "list" or action == "" then
        return dbot.backup.list(endTag)
    else
        dbot.warn("Usage: dinv backup [create|delete|restore|list] [name]")
        return DRL_RET_INVALID_PARAM
    end
end
function inv.cli.backup.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " backup @G[create|delete|restore|list] [name]", "Backup management"))
end

----------------------------------------------------------------------------------------------------
-- Notify Command
----------------------------------------------------------------------------------------------------

inv.cli.notify = {}
function inv.cli.notify.fn(name, line, wildcards)
    local channel = wildcards and wildcards[1] or ""
    local flag = wildcards and wildcards[2] or ""

    if not dbot.notify or not dbot.notify.set then
        dbot.warn("Notify module is not available.")
        return DRL_RET_UNINITIALIZED
    end

    if channel == "" then
        dbot.notify.showStatus()
        return DRL_RET_SUCCESS
    end

    if flag == "" then
        local enabled = dbot.notify.get(channel)
        if enabled == nil then
            dbot.warn("Usage: dinv notify [info|warn|note] [on|off]")
            return DRL_RET_INVALID_PARAM
        end
        dbot.printRaw("@W[DINV] notify " .. channel .. " is " .. (enabled and "@YON@W." or "@ROFF@W."))
        return DRL_RET_SUCCESS
    end

    local retval = dbot.notify.set(channel, flag, true)
    if retval ~= DRL_RET_SUCCESS then
        dbot.warn("Usage: dinv notify [info|warn|note] [on|off]")
    end
    return retval
end
function inv.cli.notify.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " notify @G[info|warn|note] [on|off]", "Toggle INFO/WARN/NOTE message channels"))
end

----------------------------------------------------------------------------------------------------
-- Level-up Command
----------------------------------------------------------------------------------------------------

inv.cli.levelup = inv.cli.levelup or {}
function inv.cli.levelup.fn(name, line, wildcards)
    if not inv.levelup or not inv.levelup.getMode or not inv.levelup.setMode then
        dbot.warn("Level-up module is not available.")
        return DRL_RET_UNINITIALIZED
    end

    local action = wildcards and tostring(wildcards[1] or ""):lower() or ""
    if action == "" or action == "status" then
        dbot.info("Level-up trigger: " .. inv.levelup.getMode())
        dbot.note("Level-up debug is " .. (inv.levelup.getDebug and inv.levelup.getDebug() and "ON." or "OFF."))
        return DRL_RET_SUCCESS
    end

    local retval = inv.levelup.setMode(action, true)
    if retval ~= DRL_RET_SUCCESS then
        dbot.warn("Usage: dinv levelup [cache|live|off|status]")
    end
    return retval
end
function inv.cli.levelup.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s",
               pluginNameCmd .. " levelup @G[cache|live|off|status]", "Arm/disarm level-up trigger mode"))
end

----------------------------------------------------------------------------------------------------
-- Forget Command
----------------------------------------------------------------------------------------------------

inv.cli.forget = {}
function inv.cli.forget.fn(name, line, wildcards)
    local tokens = wildcards or {}
    local first = tostring(tokens[1] or ""):lower()
    local query = table.concat(tokens, " ")

    if first == "confirm" and #tokens == 1 then
        local pending = inv.items.getPendingForget and inv.items.getPendingForget() or nil
        if pending == nil or pending.itemIds == nil or #pending.itemIds == 0 then
            dbot.info("No pending forget list. Run '@Gdinv forget <query>@W' first.")
            return DRL_RET_SUCCESS
        end

        local retval = inv.items.forgetByIds(pending.itemIds)
        if retval == DRL_RET_SUCCESS then
            dbot.info("Forgot " .. tostring(#pending.itemIds) .. " item(s) from inventory table.")
            inv.items.clearPendingForget()
        end
        return retval
    end

    if inv.items.clearPendingForget then
        inv.items.clearPendingForget()
    end

    local itemIds, retval = inv.items.search(query)
    if retval ~= DRL_RET_SUCCESS then
        return retval
    end

    if #itemIds == 0 then
        dbot.info("No items matching '" .. query .. "' found.")
        return DRL_RET_MISSING_ENTRY
    end

    inv.items.sort(itemIds)
    if #itemIds == 1 then
        inv.items.displayResults(itemIds, "itemid")
        retval = inv.items.forgetByIds(itemIds)
        if retval == DRL_RET_SUCCESS then
            dbot.info("Forgot 1 item from inventory table.")
        end
        return retval
    end

    inv.items.displayResults(itemIds, "basic")
    inv.items.setPendingForget(query, itemIds)
    dbot.printRaw("@RAll @Y" .. tostring(#itemIds) .. "@R listed item(s) will be forgotten.")
    dbot.printRaw("@WRun @Gdinv forget confirm@W to proceed.")
    return DRL_RET_SUCCESS
end
function inv.cli.forget.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " forget @G<query|confirm>", "Remove items from table"))
end

----------------------------------------------------------------------------------------------------
-- Ignore Command
----------------------------------------------------------------------------------------------------

inv.cli.ignore = {}
function inv.cli.ignore.fn(name, line, wildcards)
    local action = wildcards and wildcards[1] or ""
    local containerRef = wildcards and wildcards[2] or ""

    local function resolveIgnoreTarget(ref)
        local normalizedRef = tostring(ref or "")
        if normalizedRef == "" then
            return nil
        end
        if normalizedRef:lower() == tostring(invItemLocKeyring or "keyring") then
            return tostring(invItemLocKeyring or "keyring")
        end
        if inv.items and inv.items.findContainerId then
            return inv.items.findContainerId(normalizedRef)
        end
        return nil
    end

    local function formatIgnoredContainerLabel(objId)
        local label = tostring(objId)
        if label == tostring(invItemLocKeyring or "keyring") then
            return label
        end
        if inv.items and inv.items.getStatField then
            local colorName = inv.items.getStatField(objId, invStatFieldColorName)
            if colorName == nil or tostring(colorName) == "" then
                colorName = inv.items.getStatField(objId, invStatFieldName)
            end
            if colorName ~= nil and tostring(colorName) ~= "" then
                label = label .. " (" .. tostring(colorName) .. ")"
            end
        end
        return label
    end
    
    if action == "add" then
        local containerId = resolveIgnoreTarget(containerRef)
        if containerId == nil then
            dbot.warn("Usage: dinv ignore add [containerId|relativeName|keyring]")
            return DRL_RET_INVALID_PARAM
        end
        local retval = inv.config.addIgnore(containerId)
        if retval == DRL_RET_SUCCESS then
            dbot.info("Now ignoring container: " .. formatIgnoredContainerLabel(containerId))
        end
        return retval
    elseif action == "remove" then
        local containerId = resolveIgnoreTarget(containerRef)
        if containerId == nil then
            dbot.warn("Usage: dinv ignore remove [containerId|relativeName|keyring]")
            return DRL_RET_INVALID_PARAM
        end
        local retval = inv.config.removeIgnore(containerId)
        if retval == DRL_RET_SUCCESS then
            dbot.info("Removed ignored container: " .. formatIgnoredContainerLabel(containerId))
        end
        return retval
    elseif action == "list" or action == "" then
        return inv.config.listIgnored()
    else
        dbot.warn("Usage: dinv ignore [add|remove|list] [containerRef]")
        return DRL_RET_INVALID_PARAM
    end
end
function inv.cli.ignore.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " ignore @G[add|remove|list] [containerRef]", "Ignore containers"))
end

----------------------------------------------------------------------------------------------------
-- Reset Command
----------------------------------------------------------------------------------------------------

inv.cli.reset = {}
function inv.cli.reset.fn(name, line, wildcards)
    local module = wildcards and wildcards[1] or ""
    return inv.reset(module, inv.tags.new(line))
end
function inv.cli.reset.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " reset @G[module]", "Reset module data"))
end

----------------------------------------------------------------------------------------------------
-- Cache Command
----------------------------------------------------------------------------------------------------

inv.cli.cache = {}
function inv.cli.cache.fn(name, line, wildcards)
    local action = wildcards and wildcards[1] or ""
    
    if action == "clear" then
        local cacheType = wildcards and wildcards[2] or "all"
        return inv.cache.clear(cacheType)
    else
        return inv.cache.display()
    end
end
function inv.cli.cache.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " cache @G[clear [type]]", "Cache management"))
end

----------------------------------------------------------------------------------------------------
-- Tags Command
----------------------------------------------------------------------------------------------------

inv.cli.tags = {}
function inv.cli.tags.fn(name, line, wildcards)
    local args = wildcards or {}
    local action = nil
    local tagNames = {}

    if #args > 0 then
        local lastArg = args[#args]
        if lastArg == "on" or lastArg == "off" then
            action = lastArg
            table.remove(args, #args)
        end
    end

    for _, arg in ipairs(args) do
        if arg and arg ~= "" then
            table.insert(tagNames, arg)
        end
    end

    if #tagNames == 0 and action == nil then
        return inv.tags.display()
    end

    if #tagNames == 0 then
        if action == "on" then
            return inv.tags.enable()
        elseif action == "off" then
            return inv.tags.disable()
        end
        return inv.tags.display()
    end

    for _, tagName in ipairs(tagNames) do
        if tagName == "all" then
            tagNames = { inv.tags.modules }
            break
        end
    end

    if action == nil then
        return inv.tags.display()
    end

    return inv.tags.set(table.concat(tagNames, " "), action)
end
function inv.cli.tags.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " tags @G<names | all> [on | off]", "Command end tags"))
end

function inv.cli.tags.examples()
    dbot.print([[@W
Usage:
    @Gdinv tags <names | all> [on | off]@W

This plugin supports optional end tags for all operations. An end tag has the
form "{/the command line:execution time in seconds:return value:return value string}".
This gives users an easy way to use the plugin in other scripts because those scripts can
trigger on the end tag to know an operation is done and what result the operation had.

For example, if you type "dinv refresh", you could trigger on an end tag that has
an output like "{/dinv refresh:0:0:success}" to know when the refresh completed. Of
course, you would want to double check the return value in the end tag to ensure
that everything happened the way you want.

The plugin tags subsystem mirrors the syntax for the aardwolf tags subsystem. Using
"dinv tags" by itself will display a list of all supported tags. You can toggle
one or more individual tags on or off by providing the tag names as follows:
"dinv tags tagName1 tagName2 [on | off]". You can also enable or disable the
entire tag subsystem at once by using "dinv tags [on | off]".

If the plugin tags are enabled, they will echo an end tag at the conclusion of an operation.
However, if the user goes into a state (e.g., AFK) that doesn't allow echoing then the plugin
cannot report the end tag. In this scenario, the plugin will notify the user about the end
tag via a warning notification instead of an echo. Triggers cannot catch notifications
though so any code relying on end tags should either detect when you go AFK or cleanly time
out after a reasonable amount of time.

Examples:
  1) Display all supported tags
     "dinv tags"

  2) Temporarily disable the entire tags subsystem
     "dinv tags off"

  3) Turn on tags for the "refresh", "organize", and "set" components
     "dinv tags refresh organize set on"

  4) Turn all tags off (but leave the tags subsystem enabled)
     "dinv tags all off"
]])
end

----------------------------------------------------------------------------------------------------
-- Regen Command
----------------------------------------------------------------------------------------------------

inv.cli.regen = {}
function inv.cli.regen.fn(name, line, wildcards)
    local action = wildcards and wildcards[1] or ""
    
    if action == "on" then
        inv.config.setRegenEnabled(true)
        dbot.info("Regen ring auto-swap enabled")
    elseif action == "off" then
        inv.config.setRegenEnabled(false)
        dbot.info("Regen ring auto-swap disabled")
    else
        local status = inv.config.isRegenEnabled() and "enabled" or "disabled"
        dbot.info("Regen ring auto-swap is " .. status)
    end
    return DRL_RET_SUCCESS
end
function inv.cli.regen.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " regen @G[on|off]", "Auto regen ring when sleeping"))
end

----------------------------------------------------------------------------------------------------
-- Portal Command
----------------------------------------------------------------------------------------------------

inv.cli.portal = {}
function inv.cli.portal.fn(name, line, wildcards)
    local query = table.concat(wildcards or {}, " ")
    return inv.portal.use(query, inv.tags.new(line))
end
function inv.cli.portal.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " portal @G<query>", "Use a portal"))
end

----------------------------------------------------------------------------------------------------
-- Consume Command
----------------------------------------------------------------------------------------------------

inv.cli.consume = {}
function inv.cli.consume.fn(name, line, wildcards)
    local command = wildcards and wildcards[1] or ""
    local itemType = wildcards and wildcards[2] or ""
    local itemName = ""
    local container = ""

    if wildcards and #wildcards >= 3 then
        itemName = table.concat(wildcards, " ", 3)
    end

    if not inv.init.initializedActive then
        dbot.info("Skipping consume request: plugin is not yet initialized (are you AFK or sleeping?)")
        return DRL_RET_UNINITIALIZED
    end

    if dbot.gmcp and dbot.gmcp.statePreventsActions and dbot.gmcp.statePreventsActions() then
        dbot.info("Skipping consume request: character's state does not allow actions")
        return DRL_RET_NOT_ACTIVE
    end

    if command == "add" then
        return inv.consume.add(itemType, itemName)
    elseif command == "remove" then
        return inv.consume.remove(itemType, itemName)
    elseif command == "display" or command == "list" then
        return inv.consume.display(itemType)
    elseif command == "type" or command == "category" then
        local typeAction = itemType
        local targetType = wildcards and wildcards[3] or ""
        if typeAction == "add" then
            return inv.consume.addType(targetType)
        elseif typeAction == "remove" then
            return inv.consume.removeType(targetType)
        elseif typeAction == "display" or typeAction == "list" or typeAction == "" then
            return inv.consume.display()
        else
            dbot.warn("Invalid consume type action: " .. tostring(typeAction))
            return DRL_RET_INVALID_PARAM
        end
    elseif command == "buy" then
        local itemNum = tonumber(wildcards and wildcards[3]) or 1
        if wildcards and wildcards[4] then
            container = table.concat(wildcards, " ", 4)
        end
        return inv.consume.buy(itemType, itemNum, container)
    elseif command == drlConsumeSmall or command == drlConsumeBig then
        local itemNum = tonumber(wildcards and wildcards[3]) or 1
        if wildcards and wildcards[4] then
            container = table.concat(wildcards, " ", 4)
        end
        return inv.consume.use(itemType, command, itemNum, container)
    else
        inv.cli.consume.usage()
        return DRL_RET_INVALID_PARAM
    end
end
function inv.cli.consume.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " consume @G[add | remove | display | buy | small | big | type] <type> <name or quantity> <container>",
               "Consumables management"))
end

----------------------------------------------------------------------------------------------------
-- Pass Command
----------------------------------------------------------------------------------------------------

inv.cli.pass = {}
function inv.cli.pass.fn(name, line, wildcards)
    local passId = wildcards and wildcards[1] or ""
    local seconds = tonumber(wildcards and wildcards[2] or "")
    if passId == "" or seconds == nil then
        dbot.warn("Usage: dinv pass <id|name> <seconds>")
        return DRL_RET_INVALID_PARAM
    end
    return inv.pass.use(passId, seconds, inv.tags.new(line))
end
function inv.cli.pass.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " pass @G<id|name> <seconds>", "Use area pass"))
end

----------------------------------------------------------------------------------------------------
-- Version Command
----------------------------------------------------------------------------------------------------

inv.cli.version = {}
function inv.cli.version.fn(name, line, wildcards)
    return inv.version.display()
end
function inv.cli.version.usage()
    dbot.printRaw(string.format("@W    %-50s @w- %s", 
               pluginNameCmd .. " version", "Display version information"))
end

----------------------------------------------------------------------------------------------------
-- Examples (ported from original MUSHclient plugin)
----------------------------------------------------------------------------------------------------

function inv.cli.search.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.search.usage()
    dbot.print(
[[@W
An inventory table isn't much help if you can't access it!  That's where search queries come
into play.  A query specifies characteristics about inventory items and returns matches for
all items that match the query.  Queries are used in many of the dinv plugin's modes.  For
example, the "@Cget@W", "@Cput@W", "@Cstore@W", "@Ckeyword@W", "@Corganize@W", and "@Cusage@W" options all take query
arguments and then get, put, store, etc. whatever items match the query.  See the helpfile at
"@Gdinv help query@W" for more details and examples.

A query consists of one or more sets of key-value pairs where the key can be any key listed 
when you identify/lore an item.  For example, a query could be "@Gtype container keywords box@W"
if you wanted to find everything with a type value of "container" that has keywords containing "box".

Queries also support three prefixes that can be prepended onto a normal key: "@Cmin@W", "@Cmax@W",
and "@C~@W" (where "@C~@W" means "not").  To find weapons with a minimum level of 100 that do not have
a vorpal special, you could use this query: "@Gtype weapon minlevel 100 ~specials vorpal@W".

You can also "OR" multiple query clauses together into a larger query using the "@C||@W" operator.
If you want move all of your potions and pills into a container named "2.bag" you could do that
with this command: "@Gdinv put 2.bag type potion || type pill@W".

Most queries are in the form "someKey someValue". If you use an empty query (i.e., the query
is "") then it will match everything in your inventory that is not currently equipped.

Search queries support both absolute and relative names and locations.  If you want to specify
all weapons that have "axe" in their name, use "@Gtype weapon name axe@W".  If you want to
specifically target the third axe in your main inventory, use "@Gtype weapon rname 3.axe@W" 
(or you could just get by with "@Grname 3.axe@W" and skip the "@Gtype weapon@W" clause.)  The use
of the key "rname" instead of "name" means that the search is relative to your main inventory
and you can use the format [number].[name] to target a specific item.  Similarly, you can use
"@Grlocation 3.bag@W" to target every item contained by the third bag in your main inventory
(i.e., the third bag is their relative location.)

There are a few "one-off" query modes for convenience.  It is so common to search for just a
name that the default is to assume you are searching within an item's name if no other data
is supplied.  In other words, "@Gdinv search sunstone@W" will find any item with "sunstone" in
its name.  Also, queries will accept "key" instead of "keywords", "loc" instead of "location",
and "rloc" instead of "rlocation".  Yeah, I'm lazy sometimes...

Performing a search will display relevant information about the items whose characteristics match
the query.  There are three modes of searches: "basic", "objid", and "full".  A basic search displays
just basic information about the items -- surprise!  An objid search shows everything in the basic
search in addition to the item's unique ID.  A full search shows lots of info for each item and is
very verbose.

Examples:
  1) Show basic info for all weapons between the levels of 1 to 40
     "@Gdinv search type weapon minlevel 1 maxlevel 40@W"

@WLvl Name of Weapon           Type     Ave Wgt   HR   DR Dam Type Specials Int Wis Lck Str Dex Con
  8 a Flamethrower           exotic     4   0   10   18 Fire     none       2   0   3   0   0   0
 11 Dagger of Aardwolf       dagger    27   1    5    5 Cold     sharp      0   0   0   0   0   0
 20 Searing Blaze            whip      30   3    2    2 Fire     flaming    1   4   7   1   0   0
 26 Melpomene's Betrayal     dagger    36   1    2    2 Pierce   sharp      0   0   0   0   2   0
 40 Dagger of Aardwolf       dagger   100   0   20   20 Fire     sharp      1   0   0   0   0   0
 40 Dagger of Aardwolf       dagger   100  10    5    5 Mental   sharp      0   0   0   0   0   0

  2) Show unique IDs and info for all level 91 ear and neck items
     "@Gdinv search objid wearable ear level 91 || wearable neck level 91@W"

@W--- Armor ---
 3537310336 :::Sterling Cuff:::                     lv91  ear      0str  4int  0wis  0dex  0con  3luc  0hr   14dr  0hp   30mn  -60mv IRS

  3) Show full info from persistence for anything with an anti-evil flag
     "@Gdinv search full flag anti-evil@W"

@WLvl Name of Weapon           Type     Ave Wgt   HR   DR Dam Type Specials Int Wis Lck Str Dex Con
 20 Searing Bl  (1743467081) whip      30   3    2    2 Fire     flaming    1   4   7   1   0   0
    colorName:"Searing Blaze" objectID:1743467081
    keywords:"searing blaze vengeance"
    flags:"unique, glow, hum, magic, anti-evil, held, resonated, illuminated, V3"
    score:309 worth:2690 material:steel foundAt:"Unknown"
    allphys:0 allmagic:0 slash:0 pierce:0 bash:0 acid:0 poison:0
    disease:0 cold:0 energy:0 holy:0 electric:0 negative:0 shadow:0
    air:0 earth:0 fire:0 water:0 light:0 mental:0 sonic:0 magic:0
    weight:3 ownedBy:""
    clan:"From Crusaders of the Nameless One" affectMods:""

  4) Show info on any containers that are wearable on your back
     "@Gdinv search type container wearable back@W"

@WLvl Name of Container        Type       HR   DR Int Wis Lck Str Dex Con Wght  Cap Hold Hvy #In Wgt%
201 Pandora's [Box]          Contain    20   26   5   0   3   0   0   5    8 1500   16  50  33   50

  5) Show info on any portals leading to the Empire of Talsa
     "@Gdinv search type portal leadsto talsa@W"

@WLvl Name of Portal           Type     Leads to            HR  DR Int Wis Lck Str Dex Con
 60 Irresistible Calling     portal   The Empire of Tals   0   0   0   0   0   0   0   0
100 Evil Intentions          portal   The Empire of Tals   0   0   0   0   0   0   0   0
150 Cosmic Calling           portal   The Empire of Tals   0   0   0   0   0   0   0   0

  6) Look at sorted lists of your poker cards and aardwords tiles
     "@Gdinv search key poker || key aardwords@W"

  7) Find armor that is enchantable
     "@Gdinv search type armor flag invis || type armor ~flag hum || type armor ~flag glow@W"

  8) Find items made of metal
     "@Gdinv search material metal@W"

]])
end

function inv.cli.set.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.set.usage()
    dbot.print(
[[@W
This plugin can automatically generate equipment sets based on statistic priorities
defined by the user.  This is similar to aardwolf's default "score" value for items.
If you enter "@Gcompare set all@W", you will see aardwolf's default weighting for each
statistic based on your class.  

The plugin implements a similar approach, but with many more options.  For example, the
plugin's "priority" feature allows you to define statistic weightings for particular levels
or ranges of levels.  It also supports weightings for item effects such as dual wielding,
iron grip, sanctuary, or regeneration.  You can even indicate how important it is to you to
max out specific stats.  Also, the plugin provides controls that are much more fine-grained
than the default aardwolf implementation.  See "@Gdinv help priority@W" for more details and
examples using stat priorities.

Once you define a group of priorities, you have the ability to create equipment sets based
on those priorities.  The plugin finds the optimal (OK, technically it is near-optimal)
set of items that maximizes your equipment set's score relative to the specified priority.
The plugin accounts for overmaxing stats and at times may use items that superficially 
appear to be worse than other items in your inventory.  An item that looks "better" may
be contributing points to stats that are already maxed and alternative "lesser" items may
be more valuable when combined with your other equipment.

If you create a set for your current level, the plugin knows how many bonus stats you
have due to your current spellup.  It can find the exact combination of equipment relative
to your current state so that you don't overmax stats unnecessarily.  If you create one
equipment set while having a normal spellup and a second equipment set after getting a
superhero spellup, chances are high that there would be different equipment in both sets.
However, if you create a set for a level that is either higher or lower than your current
level, then the plugin must make some estimates since it can't know how many stats you would
have due to spells at that level.  It starts by guessing what an "average" spellup should
look like at a specific level.  The plugin also periodically samples your stats as you
play the game and keeps a running weighted average of spell bonuses for each level.  If
you play a style that involves always maintaining an SH spellup, then over time the plugin
will learn to use high estimates for your spell bonuses when it creates a set.  Similarly,
if you don't bother to use spellups, then over time the plugin will learn to use lower
spell bonuses that more accurately reflect your playing style.

The set creation algorithm is smart enough to detect if you have the ability to dual wield
either from aard gloves or naturally via the skill and will base the set accordingly.  It
also checks weapon weights to find the most optimal combination of weapons if dual wield
is available and it is prioritized.

The key point is that we care about maximizing the total *usable* stats in an equipment
set.  Finding pieces that are complementary without wasting points on overmaxed stats is
a process that is well-suited for a plugin -- hence this plugin :)

The "@Cset@W" mode creates the specified set and then either wears the equipment or displays
the results depending on if the "@Cwear@W" or the "@Cdisplay@W" option is specified.
The "@Ctest@W" option controls how set creation is evaluated:
  - "@Ctest cache@W" uses cached set data only (faster, no rebuild)
  - "@Ctest live@W" rebuilds data from current inventory state
An optional "@Clevel@W" parameter will create the set targeted at a specific level.  If the
level is not provided, the plugin will default to creating a set for your current level.

For example, consider a scenario where a user creates a priority designed for a primary psi
with at least one melee class and names that priority "@Cpsi-melee@W" (yes, this is what
I normally use -- psis are awesome if you haven't noticed :)).  The following examples
will use this priority.

Examples:
  1) Display what equipment set best matches the psi-melee priority for level 20.  The 
     stat summary listed on the last line indicates the cumulative stats for the entire
     set.  This reflects just the stats provided directly by the equipment and it does not
     include any bonuses you may get naturally or via spells.  Also, note the long list
     of effects provided by equipment in this set (haste, regen, etc.).  Each of those
     effects is given a weighting in the psi-melee priority table.
     "@Gdinv set display psi-melee 20@W"

@WEquipment set:   @GLevel  20 @Cpsi-melee
@w
@Y     light@W( 16): @GLevel   1@W "a hallowed light"
@Y      head@W( 40): @GLevel   1@W "Aardwolf Helm of True Sight"
@Y      eyes@W(  8): @GLevel   1@W "(+) Howling Tempest (+)"
@Y      lear@W(  8): @GLevel   1@W "(+) Magica Elemental (+)"
@Y      rear@W(  8): @GLevel   1@W "(+) Magica Elemental (+)"
@Y     neck1@W(  8): @GLevel   1@W "(+) Biting Winds (+)"
@Y     neck2@W(  8): @GLevel   1@W "(+) Biting Winds (+)"
@Y      back@W(  8): @GLevel   1@W "(+) Cyclone Blast (+)"
@Y    medal1@W(  9): @GLevel   1@W "Academy Graduation Medal"
@Y    medal2@W(  7): @GLevel   1@W "V3 Aardwolf Supporters Pin"
@Y    medal3@W( 19): @GLevel   1@W "V3 Order Of The First Tier"
@Y     torso@W( 17): @GLevel   1@W "Aardwolf Breastplate of Magic Resistance"
@Y      body@W(  6): @GLevel   1@W "a Trench Coat"
@Y     waist@W(  8): @GLevel   1@W "(+) Stiff Breeze (+) "
@Y      arms@W(  8): @GLevel   1@W "(+) Frosty Draft (+)"
@Y    lwrist@W( 12): @GLevel  16@W "-=< Clasp of the Keeper >=-"
@Y    rwrist@W(  8): @GLevel  15@W "thieves' patch"
@Y     hands@W( 30): @GLevel   1@W "Aardwolf Gloves of Dexterity"
@Y   lfinger@W( 31): @GLevel   1@W "Aardwolf Ring of Regeneration"
@Y   rfinger@W( 31): @GLevel   1@W "Aardwolf Ring of Regeneration"
@Y      legs@W(  6): @GLevel   1@W "(+) Cooling Zephyr (+)"
@Y      feet@W( 65): @GLevel   1@W "Aardwolf Boots of Speed"
@Y   wielded@W( 36): @GLevel  20@W "Searing Blaze"
@Y    second@W( 27): @GLevel   8@W "a Flamethrower"
@Y     float@W(110): @GLevel   1@W "Aardwolf Aura of Sanctuary"
@Y     above@W( 14): @GLevel   1@W "Aura of Trivia"
@Y    portal@W(  3): @GLevel   5@W "Aura of the Sage"
@Y  sleeping@W(  0): @GLevel   1@W "V3 Trivia Sleeping Bag"

@WAve Sec  HR  DR Int Wis Lck Str Dex Con Res HitP Mana Move Effects
 30   4 114 205  20  37  71  22  24  13 103  405  235  385 haste regeneration sanctuary dualwield detectgood detectevil detecthidden detectinvis detectmagic

  2) Display the psi-melee equipment set for my current level (which was 211 at the
     time I ran this example -- 201 + 10 levels as a T1 tier bonus)
     "@Gdinv set display psi-melee@W"

  3) I also use an "enchanter" priority group to boost int, wis, and luck when I
     want to enchant something.  To wear the equipment set associated with this priority
     I would use the command given below.  It automatically removes any currently worn
     items that are not in the new set and stores those items in their respective "home"
     containers.  It then pulls the new items from wherever they are stored and wears
     them.  Easy peasy.
     "@Gdinv set wear enchanter@W"
]])
end

function inv.cli.priority.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.priority.usage()
    dbot.print(
[[@W
Before you can create an equipment set, you must first define priorities.  These tell the plugin
how much you value each stat.  For example, a tank might value con over everything else while a
caster probably values int, wis, or luck more than str, dex, or con.  The plugin comes with some
default priorities but I strongly recommend creating your own priorities tuned to your specific
playstyle.

A "priority" is essentially an ordered list of statistics and the relative value you place on each
statistic.  You can create priorities using the "@Gdinv priority create <n>@W" command.  This
creates a file on disk that you can edit and then re-import.

The priority values can vary by level.  This is useful if you value different stats at different
points in your leveling experience.  For example, you might value haste highly at low levels but
not care about it at high levels where you can cast it yourself.

Priority fields include:
  - Basic stats: str, int, wis, dex, con, luck
  - Combat: hit, dam, avedam, offhandDam
  - Resources: hp, mana, moves
  - Resists: allphys, allmagic (individual resists also available)
  - Effects: sanctuary, haste, regeneration, dualwield, irongrip, and more
  - Max bonuses: maxint, maxwis, maxluck, maxstr, maxdex, maxcon

The "@Gdinv priority default <name>@W" command sets which priority DINV should treat as your
global default. DINV uses this default when a feature needs a priority and you did not explicitly
provide one (for example, automatic level-up upgrade suggestions from analyzed data). Use
"@Gdinv priority default none@W" to clear it, and "@Gdinv priority status@W" to see what is currently set.

Examples:
  1) List all priorities you have defined (including default priorities)
     "@Gdinv priority list@W"

  2) Display the weighting values for a specific priority
     "@Gdinv priority display mage@W"

@C       mage@G 1-31   32-44   45-54  55-124  125-180  181-291
@W
@C        str@g   1.00   1.00   1.00   1.00   1.00   1.00@W  : @cValue placed on strength
@C        int@G   2.50   2.50   2.50   2.50   2.50   2.50@W  : @cValue placed on intelligence
@C        wis@G   2.60   2.60   2.60   2.60   2.60   2.60@W  : @cValue placed on wisdom
@C        dex@g   0.50   0.50   0.50   0.50   0.50   0.50@W  : @cValue placed on dexterity
@C        con@g   1.50   1.50   1.50   1.50   1.50   1.50@W  : @cValue placed on constitution
@C       luck@G   2.00   2.00   2.00   2.00   2.00   2.00@W  : @cValue placed on luck
@C        dam@G   2.50   2.50   2.50   2.50   2.50   2.50@W  : @cValue placed on damroll
@C        hit@g   1.00   1.00   1.00   1.00   1.00   1.00@W  : @cValue placed on hitroll
@C     avedam@G   3.50   3.50   3.50   3.50   3.50   3.50@W  : @cValue placed on average weapon damage
@C offhandDam@G   2.50   2.50   2.50   2.50   2.50   2.50@W  : @cValue placed on offhand weapon's average damage
@C  sanctuary@G  50.00  50.00   0.00   0.00   0.00   0.00@W  : @cValue of an item's sanctuary effect
@C      haste@G  20.00   0.00   0.00   0.00   0.00   0.00@W  : @cValue of an item's haste effect
@C  dualwield@G 300.00 300.00 300.00 300.00 300.00 300.00@W  : @cValue of an item's dual wield effect
@C   irongrip@G 100.00 100.00 100.00 100.00 100.00 100.00@W  : @cValue of an item's irongrip effect

  3) Create a new priority from scratch.  This will export a text file that you can edit.
     "@Gdinv priority create sillyTankMage@W"

  4) Yeah, that tank mage thing was probably too silly.  Let's delete it.
     "@Gdinv priority delete sillyTankMage@W"

  5) Export a priority to a file for manual edits.
     "@Gdinv priority export psi-no-melee@W"

  6) Import a priority after editing the file.
     "@Gdinv priority import psi-no-melee@W"

  7) Use an external editor to modify a priority.  You can copy the priority data to the system
     clipboard to make it easy to transfer the priority to your own editor.
     "@Gdinv priority copy psi-melee@W"

  8) Paste priority data from the system clipboard and use that data to either create a new
     priority (if it doesn't exist yet) or update an existing priority.
     "@Gdinv priority paste myThief@W"

  9) Compare the stat differences at all levels for the equipment sets generated by two different
     priorities.
     "@Gdinv priority compare psi psi-melee@W"

 10) Set your global default priority.
     "@Gdinv priority default mage@W"

 11) Clear your global default priority.
     "@Gdinv priority default none@W"

 12) Check the currently configured default priority and other status details.
     "@Gdinv priority status@W"
]])
end

function inv.cli.organize.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.organize.usage()
    dbot.print(
[[@W
The organize command lets you define rules for automatically sorting items into containers.

Examples:
  1) Associate a query with a container by object id
     "@Gdinv organize add 3537310336 type potion@W"

  2) Associate a query with a container by relative/container name
     "@Gdinv organize add 1.bag type potion@W"

  3) Display the organize rules for a container
     "@Gdinv organize display 1.bag@W"

  4) Clear all organize rules for a container
     "@Gdinv organize clear 1.bag@W"

  5) Run the organize process to sort items
     "@Gdinv organize@W"
]])
end

function inv.cli.query.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.query.usage()
    dbot.print(
[[@W
Search queries support @Call persisted item properties@W in DINV data.

Common tags:
  @Cname@W, @Ctype@W, @Ckeywords@W/@Ckey@W, @Cflags@W/@Cflag@W, @Clevel@W/@Cminlevel@W/@Cmaxlevel@W,
  @Cwearable@W, @Cmaterial@W, @Cclan@W, @Cscore@W, @Cweight@W, @Cworth@W, @Cowner@W,
  @Cdamtype@W, @Cweapontype@W, @Cspecials@W, @Cleadsto@W, and any other stored item property.

Operators:
  @C~key value@W   negates a match
  @C||@W           OR between clauses

Examples:
  "@Gdinv search clan From Crusaders of the Nameless One@W"
  "@Gdinv search clan loqui@W"
  "@Gdinv search score 309@W"
  "@Gdinv search keywords searing blaze vengeance@W"
  "@Gdinv search keywords hot searing@W"
  "@Gdinv search weight 5@W"
  "@Gdinv search flags resonated anti-evil@W"
  "@Gdinv search type weapon minlevel 100 ~specials vorpal@W"
]])
end

function inv.cli.get.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.get.usage()
    dbot.print(
[[@W
Move items matching the query from containers to your main inventory.

Examples:
  1) Get all potions from all containers
     "@Gdinv get type potion@W"

  2) Get a specific item by name
     "@Gdinv get name sunstone@W"

  3) Get items from a specific container
     "@Gdinv get rloc 2.bag@W"

  4) Get all weapons with "axe" in the name
     "@Gdinv get type weapon name axe@W"
]])
end

function inv.cli.put.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.put.usage()
    dbot.print(
[[@W
Move items matching the query into the specified container.

Examples:
  1) Put all potions into your second bag
     "@Gdinv put 2.bag type potion@W"

  2) Put all armor into a container
     "@Gdinv put 3.bag type armor@W"

  3) Put items with a keyword into a container
     "@Gdinv put 1.bag keyword junk@W"

  4) Put all potions and pills into a bag
     "@Gdinv put 2.bag type potion || type pill@W"
]])
end

function inv.cli.store.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.store.usage()
    dbot.print(
[[@W
Store items in their "home" container - the container where each item was most 
recently located.  This is useful for putting items back where they came from.

Examples:
  1) Store all items that are in your main inventory
     "@Gdinv store@W"

  2) Store all weapons
     "@Gdinv store type weapon@W"

  3) Store items with a specific keyword
     "@Gdinv store keyword temp@W"
]])
end

function inv.cli.keyword.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.keyword.usage()
    dbot.print(
[[@W
Add or remove custom keywords to/from items matching the query.  Keywords are useful for
organizing and finding items.

Examples:
  1) Your friend Bob has some cool stuff in his 3rd bag and he lets you borrow them.
     You can then use the items and when you are ready to give them back, you can put
     them back with "@Gdinv put 3.bag keyword borrowedFromBob@W".  Nice!
     "@Gdinv keyword add borrowedFromBob rloc 3.bag@W"

  2) Add "@Cfavorite@W" keyword to a level 80 aardwolf sword.
     "@Gdinv keyword add favorite level 80 keyword aardwolf name sword@W"

  3) Remove "@Cfavorite@W" keyword from everything in your inventory.
     "@Gdinv keyword remove favorite@W"
]])
end

function inv.cli.snapshot.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.snapshot.usage()
    dbot.print(
[[@W
Take an equipment "snapshot" of what you are currently wearing and re-wear those exact
items at a later time.

Examples:
  1) Take a snapshot of what you currently are wearing
     "@Gdinv snapshot create myAwesomeSnapshot@W"

  2) List existing snapshots
     "@Gdinv snapshot list@W"

  3) Display what equipment is in a snapshot
     "@Gdinv snapshot display myAwesomeSnapshot@W"

  4) Wear the equipment from a snapshot
     "@Gdinv snapshot wear myAwesomeSnapshot@W"

  5) Delete a snapshot
     "@Gdinv snapshot delete myAwesomeSnapshot@W"
]])
end

function inv.cli.analyze.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.analyze.usage()
    dbot.print(
[[@W
The analyze mode lets you see which equipment is best suited for you at all levels.

Examples:
  1) Create a set analysis for the psi-melee priority
     "@Gdinv analyze create psi-melee@W"

  2) Display the analysis results
     "@Gdinv analyze display psi-melee@W"

  3) List all analyses
     "@Gdinv analyze list@W"

  4) Delete an analysis
     "@Gdinv analyze delete psi-melee@W"

  5) Create partial analysis (every 10 levels)
     "@Gdinv analyze create psi-melee 10@W"
]])
end

function inv.cli.compare.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.compare.usage()
    dbot.print(
[[@W
Compare an item to what you currently have equipped at that slot, using the specified
priority's weightings.  This helps you decide if a new item is better than what you have.

Examples:
  1) Compare a new sword to your current weapon
     "@Gdinv compare melee 2.sword@W"

  2) Compare an item by ID
     "@Gdinv compare mage 12345678@W"
]])
end

function inv.cli.covet.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.covet.usage()
    dbot.print(
[[@W
The plugin's "@Ccovet@W" mode helps you monitor short-term and long-term auctions to help
you find items that can improve stats over your existing equipment.

Pick a priority (see "@Gdinv help priority@W") that has a completed analysis available
(see "@Gdinv help analyze@W"), find a short-term or long-term auction number and you're
good to go. The plugin will scrape the market item, temporarily add it for analysis,
re-run analysis, and then discard the temporary market item.

By default, "@Ccovet@W" analyzes every level. Use @Y<skip #>@W to evaluate every N levels
for a faster (but less detailed) pass.

Examples:
  1) Evaluate a short-term market item
     "@Gdinv covet psi-melee 12@W"

  2) Evaluate a long-term market item while only checking every 10 levels
     "@Gdinv covet psi-melee 80561 10@W"
]])
end

function inv.cli.weapon.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.weapon.usage()
    dbot.print(
[[@W
Find and wear the best weapon for a specific damage type.  This is useful for switching
weapons during combat to exploit mob weaknesses.

Examples:
  1) Find the best slash weapon using your "melee" priority
     "@Gdinv weapon melee slash@W"

  2) Find a weapon that does fire OR energy damage
     "@Gdinv weapon melee fire energy@W"

  3) Cycle to the next configured damage type for your current weapon profile
     "@Gdinv weapon next@W"

  4) Cycle through every available persisted weapon damage type (no priority needed)
     "@Gdinv weapon next any@W"

  5) List all available persisted weapon damage types
     "@Gdinv weapon listdamtypes@W"
]])
end

function inv.cli.backup.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.backup.usage()
    dbot.print(
[[@W
Manage backups of your inventory table and configuration.

Examples:
  1) List existing backups
     "@Gdinv backup list@W"

  2) Create a backup before making changes
     "@Gdinv backup create before_cleanup@W"

  3) Restore from a backup
     "@Gdinv backup restore before_cleanup@W"

  4) Delete an old backup
     "@Gdinv backup delete old_backup@W"
]])
end

function inv.cli.portal.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.portal.usage()
    dbot.print(
[[@W
Find and use a portal matching the query.

Examples:
  1) Use a portal with "aylor" in its destination
     "@Gdinv portal aylor@W"

  2) Use a portal by name
     "@Gdinv portal name amulet@W"
]])
end

function inv.cli.consume.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.consume.usage()
    dbot.print(
[[@W
Manage consumable items like potions and pills.

Examples:
  1) Display your configured consumables
     "@Gdinv consume display@W"

  2) Add a specific consumable by keyword/shortname
     "@Gdinv consume add heal taohealpill@W"

  3) Add a specific consumable by full name (legacy "name" prefix is optional)
     "@Gdinv consume add heal name little jade pill@W"

  4) Create a new empty consume category
     "@Gdinv consume type add cures@W"

  5) Use a small heal consumable
     "@Gdinv consume small heal@W"

  6) Use a big heal consumable
     "@Gdinv consume big heal@W"
]])
end

function inv.cli.notify.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.notify.usage()
    dbot.print(
[[@W
Control plugin message channels individually.

  info on|off  - Controls messages like "@C[DINV INFO] Building inventory...@W"
  warn on|off  - Controls warning messages like "@Y[DINV WARN] Invalid input@W"
  note on|off  - Controls neutral note messages like "@W[DINV] Resetting module...@W"

Default state:
  info = on
  warn = on
  note = on

Examples:
  1) Show current notify channel settings
     "@Gdinv notify@W"

  2) Turn INFO messages off
     "@Gdinv notify info off@W"

  3) Turn WARN messages off
     "@Gdinv notify warn off@W"

  4) Turn NOTE messages back on
     "@Gdinv notify note on@W"
]])
end

function inv.cli.levelup.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.levelup.usage()
    dbot.print(
[[@W
Configure the level-up trigger mode.

  cache    - Arm trigger and run dry-run test via cache mode
  live     - Arm trigger and run dry-run test via live mode
  off      - Disarm level-up trigger

Debug output:
  Use "@Gdinv debug levelup on@W" to enable the concise level-up debug line.
  This debug line is independent of notify info/warn/note channels.

Examples:
  1) Show level-up status
     "@Gdinv levelup status@W"

  2) Arm in live mode
     "@Gdinv levelup live@W"

  3) Turn level-up debug line on
     "@Gdinv debug levelup on@W"
]])
end

function inv.cli.forget.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.forget.usage()
    dbot.print(
[[@W
Remove items from the inventory table.  Useful if an item was modified (enchanted,
tempered) and you want to re-identify it.

Examples:
  1) Forget a specific item so it gets re-identified
     "@Gdinv forget id 12345678@W"

  2) Stage all matching items, then confirm removal
     "@Gdinv forget name old sword@W"
     "@Gdinv forget confirm@W"
]])
end

function inv.cli.ignore.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.ignore.usage()
    dbot.print(
[[@W
Ignore containers or the keyring during inventory scans. Useful if you have locations
with items you don't want tracked.

Examples:
  1) Ignore your keyring
     "@Gdinv ignore add keyring@W"

  2) Ignore a specific container by relative name
     "@Gdinv ignore add 2.case@W"

  3) Stop ignoring a container
     "@Gdinv ignore remove 2.case@W"

  4) List ignored locations
     "@Gdinv ignore list@W"
]])
end

function inv.cli.regen.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.regen.usage()
    dbot.print(
[[@W
Automatically swap to a regeneration ring when you sleep, and swap back to your normal
ring when you wake up.

Examples:
  1) Enable auto-regen ring swapping
     "@Gdinv regen on@W"

  2) Disable auto-regen ring swapping
     "@Gdinv regen off@W"
]])
end

function inv.cli.refresh.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.refresh.usage()
    dbot.print(
[[@W
Refresh shows the current inventory tracking status.

Examples:
  1) Show tracking status
     "@Gdinv refresh@W"
]])
end

function inv.cli.version.examples()
    dbot.print("@W\nUsage:\n")
    inv.cli.version.usage()
    dbot.print(
[[@W
Display version information.

Examples:
  1) Display your current version
     "@Gdinv version@W"

  2) Check for updates
     "@Gdinv version check@W"
]])
end

-- End of CLI module
----------------------------------------------------------------------------------------------------

dbot.debug("inv.cli module loaded", "inv.cli")
