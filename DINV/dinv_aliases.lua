----------------------------------------------------------------------------------------------------
-- DINV Aliases Module
-- Mudlet alias definitions for DINV
----------------------------------------------------------------------------------------------------

DINV.aliases = DINV.aliases or {}
DINV.aliases.ids = DINV.aliases.ids or {}

----------------------------------------------------------------------------------------------------
-- Register all aliases
----------------------------------------------------------------------------------------------------

function DINV.aliases.register()
    -- Clean up any existing aliases first
    DINV.aliases.unregister()
    
    -- Main dinv alias - routes all commands through CLI
    DINV.aliases.ids.dinv = tempAlias(
        "^dinv(.*)$",
        function()
            if not (inv and inv.cli and inv.cli.main) then
                cecho("<red>DINV: Not initialized. Run: lua DINV.initialize()\n")
                return
            end

            local args = matches and matches[2] or ""
            args = args:match("^%s*(.-)%s*$") -- trim whitespace
            inv.cli.main(args)
        end
    )
    
    -- Alternative short aliases for common commands
    
    -- dinvs <query> - quick search
    DINV.aliases.ids.dinvs = tempAlias(
        "^dinvs(.*)$",
        function()
            if not (inv and inv.cli and inv.cli.main) then
                cecho("<red>DINV: Not initialized.\n")
                return
            end

            local args = matches and matches[2] or ""
            args = args:match("^%s*(.-)%s*$")
            inv.cli.main("search " .. args)
        end
    )
    
    -- dinvp <portal> - quick portal
    DINV.aliases.ids.dinvp = tempAlias(
        "^dinvp(.*)$",
        function()
            if not (inv and inv.cli and inv.cli.main) then
                cecho("<red>DINV: Not initialized.\n")
                return
            end

            local args = matches and matches[2] or ""
            args = args:match("^%s*(.-)%s*$")
            inv.cli.main("portal " .. args)
        end
    )
    
    -- dinvw <priority> <damtype> - quick weapon swap
    DINV.aliases.ids.dinvw = tempAlias(
        "^dinvw(.*)$",
        function()
            if not (inv and inv.cli and inv.cli.main) then
                cecho("<red>DINV: Not initialized.\n")
                return
            end

            local args = matches and matches[2] or ""
            args = args:match("^%s*(.-)%s*$")
            inv.cli.main("weapon " .. args)
        end
    )
    
    -- dinvset <priority> - quick set wear
    DINV.aliases.ids.dinvset = tempAlias(
        "^dinvset(.*)$",
        function()
            if not (inv and inv.cli and inv.cli.main) then
                cecho("<red>DINV: Not initialized.\n")
                return
            end

            local args = matches and matches[2] or ""
            args = args:match("^%s*(.-)%s*$")
            if args ~= "" then
                inv.cli.main("set wear " .. args)
            else
                dbot.warn("Usage: dinvset <priority> [level]")
            end
        end
    )
    
    -- dinvsnap <name> - quick snapshot wear
    DINV.aliases.ids.dinvsnap = tempAlias(
        "^dinvsnap(.*)$",
        function()
            if not (inv and inv.cli and inv.cli.main) then
                cecho("<red>DINV: Not initialized.\n")
                return
            end

            local args = matches and matches[2] or ""
            args = args:match("^%s*(.-)%s*$")
            if args ~= "" then
                inv.cli.main("snapshot wear " .. args)
            else
                inv.cli.main("snapshot list")
            end
        end
    )
    
    -- dinvnext - quick weapon next
    DINV.aliases.ids.dinvnext = tempAlias(
        "^dinvnext$",
        function()
            if not (inv and inv.cli and inv.cli.main) then
                cecho("<red>DINV: Not initialized.\n")
                return
            end

            inv.cli.main("weapon next")
        end
    )

    -- dinvcovet <priority> <auction #> [skip] - quick covet via alias bridge
    DINV.aliases.ids.dinvcovet = tempAlias(
        "^dinvcovet(.*)$",
        function()
            if not (inv and inv.cli and inv.cli.main) then
                cecho("<red>DINV: Not initialized.\n")
                return
            end

            local args = matches and matches[2] or ""
            args = args:match("^%s*(.-)%s*$")
            if args ~= "" then
                inv.cli.main("covet " .. args)
            else
                dbot.warn("Usage: dinvcovet <priority> <auction #> [skip]")
            end
        end
    )

    -- NOTE: no dedicated `dinv unused` alias is needed.
    -- It is handled by the main `^dinv(.*)$` alias via inv.cli.main().
    -- Keeping a second direct alias causes duplicate execution/output.

    -- Suppress eqdata/invdata command echo
    DINV.aliases.ids.eqdataSuppress = tempAlias(
        "^eqdata$",
        function()
            send("eqdata", false)
            return true
        end
    )

    DINV.aliases.ids.invdataSuppress = tempAlias(
        "^invdata ?(.*)$",
        function()
            local arg = matches and matches[2] or ""
            if arg ~= "" then
                send("invdata " .. arg, false)
            else
                send("invdata", false)
            end
            return true
        end
    )
    
    dbot.debug("DINV aliases registered", "aliases")
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Unregister all aliases
----------------------------------------------------------------------------------------------------

function DINV.aliases.unregister()
    for name, id in pairs(DINV.aliases.ids) do
        if id then
            killAlias(id)
        end
    end
    DINV.aliases.ids = {}
    
    dbot.debug("DINV aliases unregistered", "aliases")
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Initialize aliases
----------------------------------------------------------------------------------------------------

function DINV.aliases.init()
    DINV.aliases.register()
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- End of aliases module
----------------------------------------------------------------------------------------------------

dbot.debug("DINV aliases module loaded", "aliases")
