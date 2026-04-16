----------------------------------------------------------------------------------------------------
-- DINV Loader
-- Durel's Inventory Manager - Ported to Mudlet
--
-- Original Author: Durel
-- Mudlet Port: Converted from MUSHclient plugin
--
-- This is the main entry point that loads all DINV modules.
-- Comment out modules you don't want to load.
----------------------------------------------------------------------------------------------------

DINV = DINV or {}
DINV.version = "2.0056"
DINV.name = "Durel's Inventory Manager"

-- Determine the path to the DINV directory
-- Mudlet stores scripts in getMudletHomeDir()
DINV.path = getMudletHomeDir() .. "/DINV/"

-- Plugin identifiers (kept for compatibility)
pluginNameCmd = "dinv"
pluginNameAbbr = "DINV"
pluginId = "88c86ea252fc1918556df9fe"

-- State path for saving data
pluginStatePath = getMudletHomeDir() .. "/dinv-" .. pluginId .. "/"

----------------------------------------------------------------------------------------------------
-- Module List
-- Comment out any modules you don't want to load
----------------------------------------------------------------------------------------------------

DINV.modules = {
    -- Core utilities (DBOT) - MUST be loaded first
    "dinv_dbot",
    
    -- INV Core and Configuration
    "dinv_inv_core",
    "dinv_debug",
    "dinv_inv_config",
    
    -- Inventory Management
    "dinv_inv_items",
    "dinv_discovery",
    "dinv_inv_cache",
    
    -- Equipment Sets and Priorities
    "dinv_inv_priority",
    "dinv_inv_score",
    "dinv_inv_set",
    "dinv_inv_weapon",
    "dinv_inv_snapshot",
    
    -- Analysis
    "dinv_inv_analyze",
    "dinv_inv_usage",
    "dinv_inv_compare",
    "dinv_inv_statbonus",
    "dinv_inv_report",
    
    -- Item Actions
    "dinv_inv_consume",
    "dinv_inv_portal",
    "dinv_inv_pass",
    "dinv_inv_regen",
    "dinv_inv_organize",
    "dinv_inv_keyword",
    
    -- Custom/Extended Modules
    "dinv_inv_unused",
    "dinv_inv_discover",
    -- "dinv_rid", -- RID command/module disabled per user request (kept commented, not removed)
    
    -- User Interface (load last)
    "dinv_cli",
    "dinv_triggers",
    "dinv_aliases",
}

----------------------------------------------------------------------------------------------------
-- Module Loader
----------------------------------------------------------------------------------------------------

DINV.loadedModules = {}
DINV.failedModules = {}
DINV.pendingLoad = false
DINV.pendingInit = false

function DINV.loadModule(moduleName)
    local path = DINV.path .. moduleName .. ".lua"
    local ok, err = pcall(dofile, path)
    
    if ok then
        table.insert(DINV.loadedModules, moduleName)
        cecho("<white>DINV: Loaded module: " .. moduleName .. "\n")
        return true
    else
        table.insert(DINV.failedModules, {name = moduleName, error = err})
        cecho("<red>DINV: Failed to load module '" .. moduleName .. "'\n")
        cecho("<orange>  Error: " .. tostring(err) .. "\n")
        return false
    end
end

function DINV.loadAllModules()
    DINV.loadedModules = {}
    DINV.failedModules = {}
    
    cecho("<cyan>DINV: Loading modules...\n")
    
    for _, moduleName in ipairs(DINV.modules) do
        DINV.loadModule(moduleName)
    end
    
    -- Report results
    local loaded = #DINV.loadedModules
    local failed = #DINV.failedModules
    
    if failed == 0 then
        cecho("<green>DINV: Successfully loaded " .. loaded .. " modules.\n")
    else
        cecho("<yellow>DINV: Loaded " .. loaded .. " modules, " .. failed .. " failed.\n")
    end
    
    return failed == 0
end

function DINV.reload()
    -- Cleanup existing state if needed
    if inv and inv.fini then
        inv.fini(true)
    end
    if dbot and dbot.fini then
        dbot.fini(true)
    end
    
    -- Reload all modules
    DINV.loadAllModules()
    
    -- Re-initialize
    if dbot and dbot.init and dbot.init.atInstall then
        dbot.init.atInstall()
    end
    if inv and inv.init and inv.init.atInstall then
        inv.init.atInstall()
    end
end

----------------------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------------------

function DINV.finishInitialization()
    if not DINV.pendingInit then
        return true
    end

    DINV.pendingInit = false

    if dbot and dbot.init and dbot.init.atInstall then
        local retval = dbot.init.atInstall()
        if retval ~= DRL_RET_SUCCESS then
            cecho("<yellow>DINV: Warning during dbot initialization\n")
        end
    end

    if inv and inv.init and inv.init.atInstall then
        local retval = inv.init.atInstall()
        if retval ~= DRL_RET_SUCCESS then
            cecho("<yellow>DINV: Warning during inv initialization\n")
        end
    end

    cecho("<green>DINV v" .. DINV.version .. " initialized successfully!\n")
    cecho("<white>Type 'dinv help' for usage information.\n")
    return true
end

function DINV.initialize()
    -- Create state directory
    local lfs = require("lfs")
    lfs.mkdir(pluginStatePath)
    
    -- Load all modules IMMEDIATELY (don't wait for GMCP)
    cecho("<cyan>DINV: Loading modules...\n")
    local success = DINV.loadAllModules()
    
    if not success then
        cecho("<red>DINV: Some modules failed to load. Check errors above.\n")
        -- Continue anyway - we can work with what we have
    end
    
    -- Initialize dbot first
    if dbot and dbot.init and dbot.init.atInstall then
        local retval = dbot.init.atInstall()
        if retval ~= DRL_RET_SUCCESS then
            cecho("<yellow>DINV: Warning during dbot installation init\n")
        end
    end
    
    -- Initialize inv
    if inv and inv.init and inv.init.atInstall then
        local retval = inv.init.atInstall()
        if retval ~= DRL_RET_SUCCESS then
            cecho("<yellow>DINV: Warning during inv installation init\n")
        end
    end

    -- Register triggers and aliases once modules are loaded
    if DINV.triggers and DINV.triggers.init then
        local retval = DINV.triggers.init()
        if retval ~= DRL_RET_SUCCESS then
            cecho("<yellow>DINV: Warning during triggers initialization\n")
        end
    end

    if DINV.discovery and DINV.discovery.init then
        local retval = DINV.discovery.init()
        if retval ~= DRL_RET_SUCCESS then
            cecho("<yellow>DINV: Warning during discovery initialization\n")
        end
    end

    if DINV.aliases and DINV.aliases.init then
        local retval = DINV.aliases.init()
        if retval ~= DRL_RET_SUCCESS then
            cecho("<yellow>DINV: Warning during aliases initialization\n")
        end
    end
    
    -- Register GMCP event handlers
    if registerAnonymousEventHandler then
        registerAnonymousEventHandler("gmcp.char.base", "DINV.onGMCPCharBase")
        registerAnonymousEventHandler("gmcp.char.status", "DINV.onGMCPCharStatus")
    end

    return true
end

----------------------------------------------------------------------------------------------------
-- GMCP Event Handlers for Mudlet
----------------------------------------------------------------------------------------------------

function DINV.onGMCPCharBase()
    -- Mark GMCP as initialized
    if dbot and dbot.gmcp then
        if not dbot.gmcp.isInitialized then
            dbot.gmcp.isInitialized = true
            dbot.debug("GMCP char.base received: GMCP is initialized!", "loader")
        end
    end
    
    -- Run active initialization if not already done
    if inv and inv.init then
        if not inv.init.initializedActive then
            local retval = inv.init.atActive()
            if retval == DRL_RET_SUCCESS then
                cecho("<green>DINV: Active initialization triggered by GMCP.\n")
            end
        end
    end

    if inv and inv.analyze and inv.analyze.captureLoginLevel and dbot and dbot.gmcp and dbot.gmcp.getLevel then
        local baseLevel = tonumber(dbot.gmcp.getLevel())
        if baseLevel and baseLevel > 0 then
            inv.analyze.captureLoginLevel(baseLevel)
        end
    end
end

function DINV.onGMCPCharStatus()
    if DINV.pendingLoad then
        DINV.onGMCPCharBase()
    end

    if dbot and dbot.gmcp and dbot.gmcp.isInitialized then
        local state = dbot.gmcp.getState()

        if state ~= dbot.stateCombat and inv and inv.items and inv.items.processDeferredIdentifyQueue then
            inv.items.processDeferredIdentifyQueue("gmcp.char.status")
        end

        if state == dbot.stateActive then
            if inv and not inv.init.initializedActive then
                if inv.init and inv.init.atActive then
                    inv.init.atActive()
                end
            end

            if inv and inv.regen and inv.regen.onWake then
                inv.regen.onWake()
            end
        end
    end
end

----------------------------------------------------------------------------------------------------
-- Auto-initialize when loaded
----------------------------------------------------------------------------------------------------

function DINV.startup()
    cecho("<cyan>\n")
    cecho("<cyan>====================================\n")
    cecho("<cyan>  DINV - Durel's Inventory Manager\n")
    cecho("<cyan>  Version " .. DINV.version .. "\n")
    cecho("<cyan>====================================\n\n")
    
    -- Step 1: Initialize (load modules, set up handlers)
    local success = DINV.initialize()
    
    if not success then
        cecho("<red>DINV: Initialization failed!\n")
        return false
    end
    
    -- Step 2: Force active initialization if GMCP is already available
    -- This handles the case where we connect AFTER Mudlet is already running
    DINV.forceInit()
    
    cecho("<green>DINV: Startup complete!\n")
    cecho("<white>Type 'dinv help' for usage information.\n\n")
    
    return true
end

function DINV.forceInit()
    -- Check if GMCP data is already available (we're already connected)
    if gmcp and gmcp.char and gmcp.char.base and gmcp.char.base.name then
        cecho("<cyan>DINV: GMCP data detected, forcing active initialization...\n")
        
        -- Mark GMCP as initialized
        if dbot and dbot.gmcp then
            dbot.gmcp.isInitialized = true
        end
        
        -- Run active initialization
        if inv and inv.init and inv.init.atActive then
            local retval = inv.init.atActive()
            if retval == DRL_RET_SUCCESS then
                cecho("<green>DINV: Active initialization complete!\n")
            elseif retval == DRL_RET_BUSY then
                cecho("<yellow>DINV: Initialization already in progress.\n")
            else
                cecho("<yellow>DINV: Active initialization returned: " .. tostring(retval) .. "\n")
            end
        end
    else
        cecho("<cyan>DINV: Waiting for GMCP data. If already connected, try: lua sendGMCP('request char')\n")
        
        -- Request GMCP data to trigger initialization
        if sendGMCP then
            sendGMCP("request char")
        end
    end
end

-- Uncomment the line below to auto-initialize on load
-- DINV.startup()

-- Or call DINV.startup() manually after ensuring all files are in place
cecho("<cyan>DINV: Loader ready. Call DINV.startup() to initialize.\n")
