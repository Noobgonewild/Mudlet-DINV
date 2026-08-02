DINV.discovery = DINV.discovery or {}
DINV.discovery.ids = DINV.discovery.ids or {}
DINV.discovery.identifyTriggerIds = DINV.discovery.identifyTriggerIds or {}
DINV.discovery.identifyBuffer = DINV.discovery.identifyBuffer or {}
DINV.discovery.currentSection = nil
DINV.discovery.currentContainerId = nil
DINV.discovery.keepFlagChanged = false
DINV.discovery.identifyCardOpen = DINV.discovery.identifyCardOpen or false
DINV.discovery.rawSuppressUntil = DINV.discovery.rawSuppressUntil or 0
DINV.discovery.perfSectionStart = DINV.discovery.perfSectionStart or nil
DINV.discovery.perfParseMs = DINV.discovery.perfParseMs or 0
DINV.discovery.debug = DINV.discovery.debug or {
    eq_lines = 0,
    inv_lines = 0,
    inv_calls_ok = 0,
    inv_calls_err = 0,
}

----------------------------------------------------------------------------------------------------
-- Build Phase Guard
-- Prevents stray inventory protocol data from interrupting the identify phase
----------------------------------------------------------------------------------------------------

DINV.buildPhase = DINV.buildPhase or 0
-- Phase 0: idle
-- Phase 1: scanning eqdata
-- Phase 2: scanning invdata
-- Phase 3: scanning containers/keyring
-- Phase 4: identifying (BLOCK all stray inventory protocol data)

function DINV.setBuildPhase(phase)
    DINV.buildPhase = phase
    dbot.debug("Build phase set to " .. phase, "discovery")
end

function DINV.shouldProcessData()
    -- CRITICAL: During identify phase (4), block ALL inventory protocol data
    if DINV.buildPhase == 4 then
        dbot.debug("@RBLOCKING inventory protocol data: in identify phase@W", "discovery")
        return false
    end
    return true
end

----------------------------------------------------------------------------------------------------
-- Helper Functions
----------------------------------------------------------------------------------------------------

local function _getLine()
    if getCurrentLine then
        return tostring(getCurrentLine() or "")
    end
    return ""
end

local function _hexDump(s, maxBytes)
    s = tostring(s or "")
    maxBytes = tonumber(maxBytes) or 64
    local out = {}
    local n = math.min(#s, maxBytes)
    for i = 1, n do
        out[#out + 1] = string.format("%02X", string.byte(s, i))
    end
    if #s > n then
        out[#out + 1] = "..."
    end
    return table.concat(out, " ")
end

local function _resetInvCounters()
    DINV.discovery.debug.inv_lines = 0
    DINV.discovery.debug.inv_calls_ok = 0
    DINV.discovery.debug.inv_calls_err = 0
    DINV.discovery.perfParseMs = 0
end

local function isDiscoveryActive()
    return inv and inv.items and (
        inv.items.buildInProgress
        -- refreshInProgress is the authoritative owner flag for refresh scans.
        -- Do not rely only on inv.state here: asynchronous item handling can
        -- temporarily change that broader state while validation still owns
        -- the protocol response.
        or inv.items.refreshInProgress
        or inv.items.identifyHydrateInProgress
        or inv.state == invStateDiscovery
    )
end

local function setSection(section, containerId)
    local isMainInventoryKeepSync = section == "invdata"
        and containerId == nil
        and inv
        and inv.items
        and inv.items.keepSync
        and inv.items.keepSync.active == true

    -- Protocol tags can also be produced by commands entered manually. Only
    -- admit them while DINV owns an active discovery workflow, except for the
    -- deliberately narrow main-inventory scan used to synchronize keep flags.
    if not isDiscoveryActive() and not isMainInventoryKeepSync then
        dbot.debug(
            "Ignoring unsolicited " .. tostring(section) .. " section while discovery is idle",
            "discovery"
        )
        return false
    end

    if inv and inv.items and inv.items.startRefreshScan
        and not inv.items.startRefreshScan(section, containerId) then
        return false
    end

    DINV.discovery.currentSection = section
    DINV.discovery.currentContainerId = containerId
    DINV.discovery.keepFlagChanged = false
    DINV.discovery.perfSectionStart = dbot.perfNow and dbot.perfNow() or nil
    DINV.discovery.perfParseMs = 0

    if section == "eqdata" then
        inv.items.inEqdata = true
        inv.items.inInvdata = false
        inv.items.inKeyring = false
        dbot.debug("@YNow in eqdata section@W", "discovery")
    elseif section == "invdata" then
        inv.items.inInvdata = true
        inv.items.inEqdata = false
        inv.items.inKeyring = false
        inv.items.currentContainerId = containerId
        _resetInvCounters()
        dbot.debug("@YNow in invdata section, container: " .. tostring(containerId) .. "@W", "discovery")
    elseif section == "keyring" then
        inv.items.inKeyring = true
        inv.items.inEqdata = false
        inv.items.inInvdata = false
        inv.items.currentContainerId = nil
        _resetInvCounters()
        dbot.debug("@YNow in keyring section@W", "discovery")
    end
    return true
end

local function shouldSuppressDiscoveryOutput()
    -- Once a protocol section has been admitted, DINV owns every line in it.
    -- Keep this independent of the broader workflow state so a late state
    -- transition cannot expose raw CSV rows while the section is open.
    if DINV.discovery.currentSection ~= nil then
        return true
    end
    if inv and inv.items and (inv.items.inEqdata or inv.items.inInvdata or inv.items.inKeyring) then
        return true
    end
    if inv and inv.items and inv.items.keepSync and inv.items.keepSync.active then
        return true
    end
    if inv and inv.items and inv.items.identifyHydrateInProgress then
        return true
    end
    if inv and inv.items and inv.items.buildInProgress then
        return true
    end
    if inv and inv.items and inv.items.refreshInProgress then
        return true
    end
    if inv and inv.state == invStateDiscovery then
        return true
    end
    -- Also suppress during any build phase > 0
    if DINV.buildPhase and DINV.buildPhase > 0 then
        return true
    end
    return false
end

function DINV.discovery.bumpRawSuppressWindow(command)
    local cmd = tostring(command or ""):lower()
    if not (cmd:find("^invdata") or cmd:find("^eqdata") or cmd:find("^keyring data")
        or cmd:find("^prompt")) then
        return
    end
    local now = os.clock()
    local window = now + 2.5
    if window > (DINV.discovery.rawSuppressUntil or 0) then
        DINV.discovery.rawSuppressUntil = window
    end
end

local function shouldSuppressRawDiscoveryNoise()
    local untilTs = tonumber(DINV.discovery.rawSuppressUntil) or 0
    return untilTs > os.clock()
end

function DINV.discovery.queuePromptSuppress()
    if not shouldSuppressDiscoveryOutput() then
        return
    end
    if not tempRegexTrigger then
        return
    end

    -- NOTE:
    -- This helper is only intended to catch the immediate prompt/blank line
    -- that can appear right after a silent discovery command is issued.
    -- Keep it one-shot and narrowly scoped so it cannot leak into normal play.
    local triggerId
    triggerId = tempRegexTrigger(
        "^(<[^>]+>|\\s*)$",
        function()
            if shouldSuppressDiscoveryOutput() and deleteLine then
                deleteLine()
            end
            if triggerId and killTrigger then
                killTrigger(triggerId)
                triggerId = nil
            end
        end
    )
end

local function finishKeepFlagCapture(section, containerId, wasActive)
    local changed = DINV.discovery.keepFlagChanged == true
    local completedSync = false

    if section == "invdata"
        and containerId == nil
        and inv.items.completeKeepFlagSync
        and inv.items.keepSync
        and inv.items.keepSync.active then
        completedSync = inv.items.completeKeepFlagSync(changed)
    end

    if changed and not completedSync and not wasActive and inv.items.save then
        inv.items.save()
    end

    if not wasActive then
        inv.items.currentInvdataSeen = nil
        inv.items.awaitingInvdataContainerId = nil
    end
    DINV.discovery.keepFlagChanged = false
    if inv.items.maybeStartKeepFlagSync then
        inv.items.maybeStartKeepFlagSync()
    end
end

local function clearSection(section)
    dbot.debug("@YClearing section: " .. tostring(section) .. "@W", "discovery")
    local wasActive = isDiscoveryActive()
    local perfSectionStart = DINV.discovery.perfSectionStart
    local perfParseMs = DINV.discovery.perfParseMs or 0

    if section == "eqdata" then
        if DINV.discovery.currentSection ~= "eqdata" then
            if inv.items.refreshInProgress and inv.items.invalidateRefresh then
                inv.items.invalidateRefresh("received eqdata end without an active eqdata response")
            end
            return
        end
        inv.items.inEqdata = false
        DINV.discovery.currentSection = nil
        DINV.discovery.currentContainerId = nil
        local validCompletion = not inv.items.completeRefreshScan
            or inv.items.completeRefreshScan("eqdata", nil)
        dbot.perf(
            string.format("scan eqdata parse %.1fms", perfParseMs),
            perfSectionStart
        )
        DINV.discovery.perfSectionStart = nil
        if validCompletion and inv.items.onEqdataComplete then
            inv.items.onEqdataComplete()
        end
        finishKeepFlagCapture(section, nil, wasActive)
        return
    end

    if section == "invdata" then
        if DINV.discovery.currentSection ~= "invdata" then
            if inv.items.refreshInProgress and inv.items.invalidateRefresh then
                inv.items.invalidateRefresh("received invdata end without an active invdata response")
            end
            return
        end
        inv.items.inInvdata = false
        local containerId = DINV.discovery.currentContainerId
        DINV.discovery.currentSection = nil
        DINV.discovery.currentContainerId = nil
        inv.items.currentContainerId = nil

        dbot.debug(string.format(
            "@Y[DINV DBG] invdata complete: containerId=%s | inv_lines=%d | ok=%d | err=%d@W",
            tostring(containerId),
            DINV.discovery.debug.inv_lines,
            DINV.discovery.debug.inv_calls_ok,
            DINV.discovery.debug.inv_calls_err
        ), "discovery")

        if inv.items.identifyHydrateInProgress and inv.items.finishIdentifyHydrateInvdata then
            dbot.perf(
                string.format(
                    "scan invdata container=%s lines=%d ok=%d err=%d parse %.1fms",
                    tostring(containerId),
                    DINV.discovery.debug.inv_lines,
                    DINV.discovery.debug.inv_calls_ok,
                    DINV.discovery.debug.inv_calls_err,
                    perfParseMs
                ),
                perfSectionStart
            )
            DINV.discovery.perfSectionStart = nil
            finishKeepFlagCapture(section, containerId, wasActive)
            inv.items.finishIdentifyHydrateInvdata()
            return
        end

        local validCompletion = not inv.items.completeRefreshScan
            or inv.items.completeRefreshScan("invdata", containerId)
        dbot.perf(
            string.format(
                "scan invdata container=%s lines=%d ok=%d err=%d parse %.1fms",
                tostring(containerId),
                DINV.discovery.debug.inv_lines,
                DINV.discovery.debug.inv_calls_ok,
                DINV.discovery.debug.inv_calls_err,
                perfParseMs
            ),
            perfSectionStart
        )
        DINV.discovery.perfSectionStart = nil
        if validCompletion and inv.items.onInvdataComplete then
            local ok, err = pcall(inv.items.onInvdataComplete, containerId)
            if not ok then
                dbot.debug("@R[DINV DBG] onInvdataComplete ERROR: " .. tostring(err) .. "@W", "discovery")
            end
        else
            dbot.debug("@R[DINV DBG] inv.items.onInvdataComplete is NIL@W", "discovery")
        end
        finishKeepFlagCapture(section, containerId, wasActive)
        return
    end

    if section == "keyring" then
        if DINV.discovery.currentSection ~= "keyring" then
            if inv.items.refreshInProgress and inv.items.invalidateRefresh then
                inv.items.invalidateRefresh("received keyring end without an active keyring response")
            end
            return
        end
        inv.items.inKeyring = false
        DINV.discovery.currentSection = nil
        DINV.discovery.currentContainerId = nil
        inv.items.currentContainerId = nil

        local validCompletion = not inv.items.completeRefreshScan
            or inv.items.completeRefreshScan("keyring", nil)
        dbot.perf(
            string.format(
                "scan keyring lines=%d ok=%d err=%d parse %.1fms",
                DINV.discovery.debug.inv_lines,
                DINV.discovery.debug.inv_calls_ok,
                DINV.discovery.debug.inv_calls_err,
                perfParseMs
            ),
            perfSectionStart
        )
        DINV.discovery.perfSectionStart = nil
        if validCompletion and inv.items.onKeyringComplete then
            inv.items.onKeyringComplete()
        end
    end
end

local function handleDataLine(section, dataLine)
    if not dataLine or dataLine == "" then
        return
    end

    if section == "eqdata" then
        if inv.items.onEqdata then
            local parseStart = dbot.perfNow and dbot.perfNow() or nil
            local ok, retval, keepFlagChanged = pcall(inv.items.onEqdata, dataLine)
            if parseStart and dbot.perfNow then
                local elapsedMs = (dbot.perfNow() - parseStart) * 1000
                DINV.discovery.perfParseMs = (DINV.discovery.perfParseMs or 0) + elapsedMs
                if elapsedMs >= 100 and dbot.perf then
                    dbot.perf("slow eqdata row id=" .. tostring(dataLine:match("^(%d+),") or "?"), parseStart)
                end
            end
            if ok and retval == DRL_RET_SUCCESS then
                if keepFlagChanged then
                    DINV.discovery.keepFlagChanged = true
                end
            else
                if inv.items.refreshInProgress and inv.items.invalidateRefresh then
                    inv.items.invalidateRefresh("failed to parse eqdata item line")
                end
                dbot.debug("@R[DINV DBG] onEqdata ERROR: " .. tostring(retval) .. "@W", "discovery")
            end
        end
        return
    end

    if section == "invdata" then
        DINV.discovery.debug.inv_lines = DINV.discovery.debug.inv_lines + 1

        if inv.items.keepSync and inv.items.keepSync.active
            and inv.items.updateKeepFlagFromDataLine then
            local retval, keepFlagChanged = inv.items.updateKeepFlagFromDataLine(dataLine)
            if retval == DRL_RET_SUCCESS then
                DINV.discovery.debug.inv_calls_ok = DINV.discovery.debug.inv_calls_ok + 1
                if keepFlagChanged then
                    DINV.discovery.keepFlagChanged = true
                end
            else
                DINV.discovery.debug.inv_calls_err = DINV.discovery.debug.inv_calls_err + 1
            end
            return
        end

        if inv.items.identifyHydrateInProgress and inv.items.handleIdentifyHydrateInvdataLine then
            inv.items.handleIdentifyHydrateInvdataLine(dataLine)
            return
        end

        if inv.items.onInvdata then
            local parseStart = dbot.perfNow and dbot.perfNow() or nil
            local ok, retval, keepFlagChanged = pcall(inv.items.onInvdata, dataLine)
            if parseStart and dbot.perfNow then
                local elapsedMs = (dbot.perfNow() - parseStart) * 1000
                DINV.discovery.perfParseMs = (DINV.discovery.perfParseMs or 0) + elapsedMs
                if elapsedMs >= 100 and dbot.perf then
                    dbot.perf("slow invdata row id=" .. tostring(dataLine:match("^(%d+),") or "?"), parseStart)
                end
            end
            if ok and retval == DRL_RET_SUCCESS then
                DINV.discovery.debug.inv_calls_ok = DINV.discovery.debug.inv_calls_ok + 1
                if keepFlagChanged then
                    DINV.discovery.keepFlagChanged = true
                end
            else
                DINV.discovery.debug.inv_calls_err = DINV.discovery.debug.inv_calls_err + 1
                if inv.items.refreshInProgress and inv.items.invalidateRefresh then
                    inv.items.invalidateRefresh("failed to parse invdata item line")
                end
                dbot.debug("@R[DINV DBG] onInvdata ERROR: " .. tostring(retval) .. "@W", "discovery")
                dbot.debug("@R[DINV DBG] onInvdata line was: " .. tostring(dataLine) .. "@W", "discovery")
            end
        else
            dbot.debug("@R[DINV DBG] inv.items.onInvdata is NIL@W", "discovery")
        end

        -- Track container membership
        local objId = dataLine:match("^(%d+),")
        local containerId = DINV.discovery.currentContainerId
        if objId and containerId and tostring(containerId):match("^%d+$") and tostring(containerId) ~= "0" then
            if inv.items.setStatField then
                inv.items.setStatField(objId, invStatFieldContainer, tostring(containerId))
            end
        end
    end

    if section == "keyring" then
        DINV.discovery.debug.inv_lines = DINV.discovery.debug.inv_lines + 1
        if inv.items.onKeyringData then
            local parseStart = dbot.perfNow and dbot.perfNow() or nil
            local ok, retval = pcall(inv.items.onKeyringData, dataLine)
            if parseStart and dbot.perfNow then
                local elapsedMs = (dbot.perfNow() - parseStart) * 1000
                DINV.discovery.perfParseMs = (DINV.discovery.perfParseMs or 0) + elapsedMs
                if elapsedMs >= 100 and dbot.perf then
                    dbot.perf("slow keyring row id=" .. tostring(dataLine:match("^(%d+),") or "?"), parseStart)
                end
            end
            if ok and retval == DRL_RET_SUCCESS then
                DINV.discovery.debug.inv_calls_ok = DINV.discovery.debug.inv_calls_ok + 1
            else
                DINV.discovery.debug.inv_calls_err = DINV.discovery.debug.inv_calls_err + 1
                if inv.items.refreshInProgress and inv.items.invalidateRefresh then
                    inv.items.invalidateRefresh("failed to parse keyring item line")
                end
                dbot.debug("@R[DINV DBG] onKeyringData ERROR: " .. tostring(retval) .. "@W", "discovery")
            end
        end
    end
end

----------------------------------------------------------------------------------------------------
-- Register Discovery Triggers
----------------------------------------------------------------------------------------------------

function DINV.discovery.register()
    DINV.discovery.unregister()

    dbot.debug("@YRegistering discovery triggers...@W", "discovery")

    -- Suppress prompts during build/refresh discovery
    DINV.discovery.ids.promptSuppress = tempRegexTrigger(
        "^<[0-9]+/[0-9]+hp [0-9]+/[0-9]+mn [0-9]+/[0-9]+mv",
        function()
            if shouldSuppressDiscoveryOutput() then
                deleteLine()
            end
        end
    )

    -- Suppress empty lines during build/refresh discovery
    DINV.discovery.ids.emptyLine = tempRegexTrigger(
        "^\\s*$",
        function()
            if shouldSuppressDiscoveryOutput() then
                deleteLine()
            end
        end
    )

    -- Suppress and handle invdata errors for missing items
    DINV.discovery.ids.itemNotFound = tempRegexTrigger(
        "^Item (\\d+) not found\\.$",
        function(matches)
            if shouldSuppressDiscoveryOutput() then
                deleteLine()
            end

            local objId = matches and matches[2] or nil
            if objId and inv and inv.items and inv.items.refreshInProgress
                and inv.items.completeMissingRefreshContainer then
                if inv.items.completeMissingRefreshContainer(objId)
                    and inv.items.onInvdataComplete then
                    inv.items.onInvdataComplete(objId)
                end
                return
            end

            if objId and inv and inv.items and inv.items.handleMissingItem then
                inv.items.handleMissingItem(objId)
            end

            if inv and inv.items and inv.items.onInvdataComplete
                and (inv.items.buildInProgress or inv.items.refreshInProgress) then
                inv.items.onInvdataComplete(objId)
            end
        end
    )

    -- {eqdata} start (anchored is fine)
    DINV.discovery.ids.eqdataStart = tempRegexTrigger(
        "^\\{eqdata\\}$",
        function()
            if not DINV.shouldProcessData() then
                deleteLine()
                return
            end
            dbot.debug("@YTrigger fired: eqdataStart@W", "discovery")
            dbot.debug("@Y=== EQDATA START ===@W", "discovery")
            if not setSection("eqdata", nil) then
                if shouldSuppressDiscoveryOutput() then deleteLine() end
                return
            end
            if shouldSuppressDiscoveryOutput() then deleteLine() end
        end
    )

    -- {/eqdata} end (anchored is fine)
    DINV.discovery.ids.eqdataEnd = tempRegexTrigger(
        "^\\{/eqdata\\}$",
        function()
            if not DINV.shouldProcessData() then
                deleteLine()
                return
            end
            dbot.debug("@YTrigger fired: eqdataEnd@W", "discovery")
            dbot.debug("@Y=== EQDATA END ===@W", "discovery")
            if shouldSuppressDiscoveryOutput() then deleteLine() end
            clearSection("eqdata")
        end
    )

    --------------------------------------------------------------------------------------------
    -- INV TAGS: robust matching (NO ^/$)
    --------------------------------------------------------------------------------------------

    -- Empty main inventory/container on ONE line: {invdata}{/invdata}
    -- or {invdata 123}{/invdata}.
    DINV.discovery.ids.invdataEmptyContainer = tempRegexTrigger(
        "\\{invdata\\s*(\\d*)\\}.*\\{/invdata\\}",
        function(matches)
            if not DINV.shouldProcessData() then
                deleteLine()
                return
            end
            local line = _getLine()
            local containerId = matches[2]
            if containerId == "" then
                containerId = nil
            end
            if not containerId and inv and inv.items
                and inv.items.expectedInvdataContainerId
                and inv.items.awaitingInvdataContainerId
                and tostring(inv.items.expectedInvdataContainerId)
                    == tostring(inv.items.awaitingInvdataContainerId) then
                containerId = tostring(inv.items.awaitingInvdataContainerId)
            end
            dbot.debug("@YTrigger fired: invdataEmptyContainer@W", "discovery")
            dbot.debug("@Yline=" .. line .. "@W", "discovery")
            dbot.debug("@Yhex=" .. _hexDump(line) .. "@W", "discovery")
            dbot.debug("@Y=== INVDATA EMPTY CONTAINER: " .. tostring(containerId) .. " ===@W", "discovery")

            if not setSection("invdata", containerId) then
                if shouldSuppressDiscoveryOutput() then deleteLine() end
                return
            end
            if shouldSuppressDiscoveryOutput() then deleteLine() end
            clearSection("invdata")
        end
    )

    -- Start tag (main OR container), robust, NO non-capturing groups
	-- matches[3] will be the digits if present
	-- Start tag (main OR container), robust, parse ID from the raw line (not from regex captures)
	DINV.discovery.ids.invdataStartAny = tempRegexTrigger(
	  "\\{invdata[^}]*\\}",
	  function()
		if not DINV.shouldProcessData() then
		  deleteLine()
		  return
		end
		local line = _getLine()

		-- If this line ALSO contains {/invdata}, let invdataEmptyContainer handle it
		if line:find("{/invdata}", 1, true) then
		  return
		end

		dbot.debug("@YTrigger fired: invdataStartAny@W", "discovery")
		dbot.debug("@Yline=" .. line .. "@W", "discovery")
		dbot.debug("@Yhex=" .. _hexDump(line) .. "@W", "discovery")

		-- Parse container id directly from the line.
		-- Some servers/clients only emit {invdata} without the container id,
		-- so fall back to the container we most recently requested.
		local containerId = line:match("%{invdata%s+(%d+)%}")
		if not containerId then
		  -- just in case the server ever sends it without a space
		  containerId = line:match("%{invdata(%d+)%}")
		end
		if (not containerId or containerId == "") and inv and inv.items then
		  -- Only use the request fallback for explicit container scans.
		  -- Main "invdata" responses may omit an id and should stay in inventory scope.
		  if inv.items.expectedInvdataContainerId and inv.items.awaitingInvdataContainerId
		      and tostring(inv.items.expectedInvdataContainerId) == tostring(inv.items.awaitingInvdataContainerId) then
		    containerId = tostring(inv.items.awaitingInvdataContainerId)
		  end
		end

		if containerId and containerId ~= "0" then
		  dbot.debug("@Y=== INVDATA CONTAINER START: " .. tostring(containerId) .. " ===@W", "discovery")
		  if not setSection("invdata", containerId) then
		    if shouldSuppressDiscoveryOutput() then deleteLine() end
		    return
		  end
		else
		  dbot.debug("@Y=== INVDATA START (MAIN) ===@W", "discovery")
		  dbot.debug(string.format(
			"@Y[DINV DBG] inv.state=%s invStateDiscovery=%s buildInProgress=%s@W",
			tostring(inv and inv.state),
			tostring(invStateDiscovery),
			tostring(inv and inv.items and inv.items.buildInProgress)
		  ), "discovery")
		  if not setSection("invdata", nil) then
		    if shouldSuppressDiscoveryOutput() then deleteLine() end
		    return
		  end
		end

        if shouldSuppressDiscoveryOutput() then deleteLine() end
	  end
	)



    -- End tag (robust), BUT only clear if we are actually inside invdata section
    DINV.discovery.ids.invdataEnd = tempRegexTrigger(
        "\\{/invdata\\}",
        function()
            if not DINV.shouldProcessData() then
                deleteLine()
                return
            end
            local line = _getLine()
            dbot.debug("@YTrigger fired: invdataEnd@W", "discovery")
            dbot.debug("@Yline=" .. line .. "@W", "discovery")
            dbot.debug("@Yhex=" .. _hexDump(line) .. "@W", "discovery")
            dbot.debug("@Y=== INVDATA END ===@W", "discovery")

            -- Critical guard: only complete invdata if we are currently in it
            if not (inv and inv.items and inv.items.inInvdata) and DINV.discovery.currentSection ~= "invdata" then
                dbot.debug("@R[DINV DBG] invdataEnd seen but NOT in invdata; ignoring to avoid double-complete@W", "discovery")
                return
            end

            if shouldSuppressDiscoveryOutput() then deleteLine() end
            clearSection("invdata")
        end
    )

    --------------------------------------------------------------------------------------------
    -- KEYRING TAGS
    --------------------------------------------------------------------------------------------

    DINV.discovery.ids.keyringEmpty = tempRegexTrigger(
        "\\{keyring\\}.*\\{/keyring\\}",
        function()
            if not DINV.shouldProcessData() then
                deleteLine()
                return
            end
            if not setSection("keyring", nil) then
                if shouldSuppressDiscoveryOutput() then deleteLine() end
                return
            end
            if shouldSuppressDiscoveryOutput() then deleteLine() end
            clearSection("keyring")
        end
    )

    DINV.discovery.ids.keyringStart = tempRegexTrigger(
        "^\\{keyring\\}$",
        function()
            if not DINV.shouldProcessData() then
                deleteLine()
                return
            end
            if not setSection("keyring", nil) then
                if shouldSuppressDiscoveryOutput() then deleteLine() end
                return
            end
            if shouldSuppressDiscoveryOutput() then deleteLine() end
        end
    )

    DINV.discovery.ids.keyringEnd = tempRegexTrigger(
        "^\\{/keyring\\}$",
        function()
            if not DINV.shouldProcessData() then
                deleteLine()
                return
            end
            if DINV.discovery.currentSection ~= "keyring" then
                dbot.debug("@R[DINV DBG] keyringEnd seen but NOT in keyring; ignoring@W", "discovery")
                return
            end
            if shouldSuppressDiscoveryOutput() then deleteLine() end
            clearSection("keyring")
        end
    )

    --------------------------------------------------------------------------------------------
    -- Data lines: (keep broad match; it fires only inside an admitted section)
    --------------------------------------------------------------------------------------------

    DINV.discovery.ids.dataLine = tempRegexTrigger(
        "^(\\d{5,},.*)$",
        function(matches)
            matches = matches or _G.matches
            local dataLine = nil
            if matches then
                dataLine = matches[2] or matches[1]
            end
            if (not dataLine or dataLine == "") and getCurrentLine then
                dataLine = getCurrentLine()
            end
            dataLine = tostring(dataLine or ""):gsub("^%s+", ""):gsub("%s+$", "")

            if not (inv.items.inEqdata or inv.items.inInvdata or inv.items.inKeyring) then
                if shouldSuppressRawDiscoveryNoise() and deleteLine then
                    deleteLine()
                end
                return
            end
            if inv.items.inEqdata or inv.items.inInvdata or inv.items.inKeyring then
                if shouldSuppressDiscoveryOutput() then deleteLine() end

                dbot.debug("@YTrigger fired: dataLine@W", "discovery")

                if dataLine == "" then
                    return
                end
                if not dataLine:match("^%d+,") then
                    dbot.debug(
                        "@YIgnoring non-protocol dataLine: " .. dataLine:sub(1, 60) .. "@W",
                        "discovery"
                    )
                    return
                end

                if inv.items.inEqdata then
                    handleDataLine("eqdata", dataLine)
                elseif inv.items.inInvdata then
                    handleDataLine("invdata", dataLine)

                    -- Probe store correctness (first time only is noisy; keep it lightweight)
                    if not inv.items.identifyHydrateInProgress then
                        local objId = tonumber(dataLine:match("^(%d+),"))
                        if objId and inv.items.getItem then
                            local it = inv.items.getItem(objId)
                            if it == nil then
                                dbot.debug(string.format("@R[DINV DBG] onInvdata did NOT store item id=%s@W", tostring(objId)), "discovery")
                            end
                        end
                    end
                elseif inv.items.inKeyring then
                    handleDataLine("keyring", dataLine)
                end
            end
        end
    )

    -- {invmon} for real-time updates AND build-time identification
    -- When the package trigger named "invmon" exists, it already handles
    -- processing this stream. Registering an extra temporary trigger causes
    -- duplicate onInvmon calls and noisy/conflicting debug output.
    local hasPackageInvmonTrigger = false
    if exists then
        local ok, triggerId = pcall(exists, "invmon", "trigger")
        hasPackageInvmonTrigger = ok and triggerId and triggerId ~= 0
    end

    if hasPackageInvmonTrigger then
        dbot.debug("@YSkipping temp invmon trigger: package trigger 'invmon' exists@W", "discovery")
    else
        DINV.discovery.ids.invmon = tempRegexTrigger(
            "^\\{invmon\\}(.+)$",
            function(matches)
                local line = getCurrentLine and getCurrentLine() or ""

                -- Extract payload
                local payload = nil
                if matches then
                    payload = matches[2]  -- First capture group in Mudlet
                end

                -- Fallback: extract from line directly
                if (not payload or payload == "") then
                    payload = line:match("^%s*%{invmon%}(.+)$")
                end

                dbot.debug("@YTrigger fired: invmon, payload=" .. tostring(payload) .. "@W", "discovery")

                if payload and payload ~= "" and inv.items.onInvmon then
                    local result = inv.items.onInvmon(payload)
                    dbot.debug("@Yinv.items.onInvmon returned: " .. tostring(result) .. "@W", "discovery")
                else
                    dbot.debug("@RInvmon trigger: no payload or onInvmon not available@W", "discovery")
                end

                local allowOutput = DINV
                    and DINV.debug
                    and DINV.debug.isEnabled
                    and DINV.debug.isEnabled("invmon")
                if not allowOutput then
                    -- Delete the line to suppress output
                    deleteLine()
                end
            end
        )
    end

    -- {invitem} for real-time updates. The package XML normally owns this
    -- stream; register a temporary fallback only when that trigger is absent.
    local hasPackageInvitemTrigger = false
    if exists then
        local ok, triggerId = pcall(exists, "invitem", "trigger")
        hasPackageInvitemTrigger = ok and triggerId and triggerId ~= 0
    end

    if hasPackageInvitemTrigger then
        dbot.debug("@YSkipping temp invitem trigger: package trigger 'invitem' exists@W", "discovery")
    else
        DINV.discovery.ids.invitem = tempRegexTrigger(
            "^\\{invitem\\}(.+)$",
            function(matches)
                dbot.debug("@YTrigger fired: invitem@W", "discovery")
                matches = matches or _G.matches
                if inv.items.onInvitem then
                    local payload = matches and (matches[2] or matches[1]) or nil
                    if payload then
                        inv.items.onInvitem(payload)
                    end
                end
                deleteLine()
            end
        )
    end

    dbot.debug("@YDiscovery triggers registered successfully@W", "discovery")
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Unregister Discovery Triggers
----------------------------------------------------------------------------------------------------

function DINV.discovery.unregister()
    for name, id in pairs(DINV.discovery.ids or {}) do
        if id then
            killTrigger(id)
        end
    end
    DINV.discovery.ids = {}
end

----------------------------------------------------------------------------------------------------
-- Register Identify Triggers (for suppressing identify output during build)
----------------------------------------------------------------------------------------------------

function DINV.discovery.registerIdentifyTriggers()
    DINV.discovery.unregisterIdentifyTriggers()
    DINV.discovery.identifyTriggerIds = {}
    DINV.discovery.identifyBuffer = {}
	if DINV.buildPhase == 4 then
		sendGMCP("config prompt off")
	end
    dbot.debug("@YRegistering identify triggers...@W", "discovery")
	
    local function shouldSuppressIdentifyOutput()
		local buildInProgress = inv and inv.items and inv.items.buildInProgress
		local refreshInProgress = inv and inv.items and inv.items.refreshInProgress
		local identifyInProgress = inv and inv.items and inv.items.identifyInProgress
		local workflowActive = (buildInProgress or refreshInProgress) and true or false
		local result = workflowActive and identifyInProgress and true or false
		dbot.debug(
			"shouldSuppress: build=" .. tostring(buildInProgress)
				.. " refresh=" .. tostring(refreshInProgress)
				.. " identify=" .. tostring(identifyInProgress)
				.. " => " .. tostring(result),
			"discovery"
		)
		return result
	end
	-- Suppress empty lines during identify phase
	DINV.discovery.identifyTriggerIds.emptyLine = tempRegexTrigger(
		"^\\s*$",
		function()
			if shouldSuppressIdentifyOutput() then
				deleteLine()
			end
		end
	)

	-- Suppress prompt during identify phase
	DINV.discovery.identifyTriggerIds.promptSuppress = tempRegexTrigger(
		"^<[0-9]+/[0-9]+hp [0-9]+/[0-9]+mn [0-9]+/[0-9]+mv",
		function()
			if shouldSuppressIdentifyOutput() then
				deleteLine()
			end
		end
	)
	-- Suppress Fantasy Series Collector's Card lines during build
	DINV.discovery.identifyTriggerIds.fantasyCard = tempRegexTrigger(
		"Fantasy Series Collector's Card",
		function()
			if shouldSuppressIdentifyOutput() then
				deleteLine()
			end
		end
	)

	DINV.discovery.identifyTriggerIds.cardTotal = tempRegexTrigger(
		"^Total:",
		function()
			if shouldSuppressIdentifyOutput() then
				deleteLine()
			end
		end
	)

	DINV.discovery.identifyTriggerIds.greatestMoment = tempRegexTrigger(
		"greatest moment #",
		function()
			if shouldSuppressIdentifyOutput() then
				deleteLine()
			end
		end
	)

	DINV.discovery.identifyTriggerIds.cardSeparator = tempRegexTrigger(
		"^%-%-%-%-%-%-%-%-%-%-",
		function()
			if shouldSuppressIdentifyOutput() then
				deleteLine()
			end
		end
	)

	DINV.discovery.identifyTriggerIds.cardsStored = tempRegexTrigger(
		"^You have the following cards stored:",
		function()
			if shouldSuppressIdentifyOutput() then
				deleteLine()
			end
		end
	)
    -- Suppress "You get X from Y" messages
    DINV.discovery.identifyTriggerIds.getMsg = tempRegexTrigger(
        "^\\s*You get .+ from .+",
        function()
            dbot.debug("@YTrigger fired: identify.getMsg@W", "discovery")
            local line = getCurrentLine() or ""
            local lineLower = line:lower()
            local fromCorpse = lineLower:find("corpse", 1, true)
                or lineLower:find("remains", 1, true)
                or lineLower:find("carcass", 1, true)
            if fromCorpse then
                dbot.debug("@Yidentify.getMsg preserving corpse loot line@W", "discovery")
                return
            end
            if shouldSuppressIdentifyOutput() then
                deleteLine()
            end
        end
    )

    -- Suppress "You put X in/into Y" messages
    DINV.discovery.identifyTriggerIds.putMsg = tempRegexTrigger(
        "^\\s*You put .+ (in|into) .+",
        function()
            dbot.debug("@YTrigger fired: identify.putMsg@W", "discovery")
            if shouldSuppressIdentifyOutput() then
                deleteLine()
            end
        end
    )

    -- Handle "already carrying" error
    DINV.discovery.identifyTriggerIds.alreadyCarrying = tempRegexTrigger(
        "^\\s*You are already carrying that",
        function()
            dbot.debug("@YTrigger fired: identify.alreadyCarrying@W", "discovery")
            if inv.items.identifyInProgress then
                if inv.items.handleIdentifyGetFailure then
                    inv.items.handleIdentifyGetFailure("already carrying")
                end
                if shouldSuppressIdentifyOutput() then
                    deleteLine()
                end
            end
        end
    )

    -- Handle "do not see that" error
    DINV.discovery.identifyTriggerIds.notSee = tempRegexTrigger(
        "^\\s*You do not see that",
        function()
            dbot.debug("@YTrigger fired: identify.notSee@W", "discovery")
            if inv.items.identifyInProgress then
                if inv.items.handleIdentifyGetFailure then
                    inv.items.handleIdentifyGetFailure("not seen")
                end
                if shouldSuppressIdentifyOutput() then
                    deleteLine()
                end
            end
        end
    )

    -- Match card borders: +--------+ or .--------. or +---------+
    DINV.discovery.identifyTriggerIds.cardBorder = tempRegexTrigger(
        "^\\s*[\\+\\.]-{5,}[\\+\\.]?\\s*$",
        function()
            dbot.debug("@YTrigger fired: identify.cardBorder@W", "discovery")
            if inv.items.identifyInProgress then
                DINV.discovery.identifyCardOpen = true
            end
            if shouldSuppressIdentifyOutput() then
                deleteLine()
            end
        end
    )

    -- THE CRITICAL FIX: Fence trigger with correct PCRE pattern
    -- inv.items.identifyFence = "DINV identify fence"
    DINV.discovery.identifyTriggerIds.identifyFence = tempRegexTrigger(
        "^\\s*DINV identify fence\\s*$",
        function()
            dbot.debug("@YTrigger fired: identify.fence@W", "discovery")
            if inv.items.identifyInProgress then
                dbot.debug("@YCalling handleIdentifyFence with id: " .. tostring(inv.items.identifyCurrentId) .. "@W", "discovery")
                if inv.items.handleIdentifyFence then
                    inv.items.handleIdentifyFence(inv.items.identifyCurrentId)
                else
                    dbot.debug("@RhandleIdentifyFence does not exist!@W", "discovery")
                end
            end
            -- Always delete the fence line
            deleteLine()
            DINV.discovery.identifyCardOpen = false
        end
    )

    -- Match card content lines: | ... |
	DINV.discovery.identifyTriggerIds.cardLine = tempRegexTrigger(
		"^\\s*\\|.*\\|\\s*$",
		function()
			local line = getCurrentLine() or ""
			local isIdentifyBorder = tostring(line):match("^%s*|%s*%-+%s*|%s*$") ~= nil
			local ok, err = pcall(function()
                dbot.debug("@YcardLine trigger fired: " .. tostring(line):sub(1, 50) .. "@W", "discovery")
				if not inv.items.identifyInProgress then
					return
				end
				if not DINV.discovery.identifyCardOpen then
					return
				end
				if line:match("|%s*Id%s*:") then
					return
				end
				if not inv.items.identifyCurrentId then
					table.insert(DINV.discovery.identifyBuffer, line)
					return
				end
				local item = inv.items.getItem(inv.items.identifyCurrentId)
				if item and inv.items.parseIdentifyLine then
                    if not isIdentifyBorder then
                        inv.items.identifySawOutput = inv.items.identifySawOutput or {}
                        inv.items.identifySawOutput[tostring(inv.items.identifyCurrentId)] = true
                    end
					inv.items.parseIdentifyLine(item, line)
					inv.items.setItem(inv.items.identifyCurrentId, item)
				end
			end)

            if not ok then
                dbot.debug("@RcardLine ERROR: " .. tostring(err) .. "@W", "discovery")
            end
			
			if shouldSuppressIdentifyOutput() and not isIdentifyBorder then
				deleteLine()
			end
		end
	)

    -- Suppress collector card output during build
    DINV.discovery.identifyTriggerIds.cardHeader = tempRegexTrigger(
        "^\\* .+ Collector's Card",
        function()
            if shouldSuppressIdentifyOutput() then
                deleteLine()
            end
        end
    )

    DINV.discovery.identifyTriggerIds.cardTotal = tempRegexTrigger(
        "^Total: ",
        function()
            if shouldSuppressIdentifyOutput() then
                deleteLine()
            end
        end
    )

    DINV.discovery.identifyTriggerIds.cardMoment = tempRegexTrigger(
        "greatest moment #\\d+!",
        function()
            if shouldSuppressIdentifyOutput() then
                deleteLine()
            end
        end
    )

    DINV.discovery.identifyTriggerIds.cardSeparator = tempRegexTrigger(
        "^%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-",
        function()
            if shouldSuppressIdentifyOutput() then
                deleteLine()
            end
        end
    )

    DINV.discovery.identifyTriggerIds.cardStored = tempRegexTrigger(
        "^You have the following cards stored:",
        function()
            if shouldSuppressIdentifyOutput() then
                deleteLine()
            end
        end
    )


    -- Extract ID from identify output
    DINV.discovery.identifyTriggerIds.identifyId = tempRegexTrigger(
        "\\|\\s*Id\\s*:\\s*(\\d+)",
        function(matches)
            dbot.debug("@YTrigger fired: identify.identifyId@W", "discovery")
            matches = matches or _G.matches
            local objId = matches and (matches[2] or matches[1]) or nil
            if objId and inv.items.identifyInProgress then
                inv.items.identifySawOutput = inv.items.identifySawOutput or {}
                inv.items.identifySawOutput[tostring(objId)] = true
                if objId ~= inv.items.identifyCurrentId then
                    dbot.debug("@YID update: " .. tostring(inv.items.identifyCurrentId) .. " -> " .. objId .. "@W", "discovery")
                end
                inv.items.identifyCurrentId = objId
                local item = inv.items.getItem(objId)
                if item and inv.items.parseIdentifyLine then
                    local line = getCurrentLine()
                    inv.items.parseIdentifyLine(item, line)
                    for _, bufferedLine in ipairs(DINV.discovery.identifyBuffer or {}) do
                        inv.items.parseIdentifyLine(item, bufferedLine)
                    end
                    inv.items.setItem(objId, item)
                    DINV.discovery.identifyBuffer = {}
                end
            end
            if shouldSuppressIdentifyOutput() then
                deleteLine()
            end
        end
    )

    -- Suppress "Your natural intuition reveals..."
    DINV.discovery.identifyTriggerIds.intuition = tempRegexTrigger(
        "^\\s*Your natural intuition reveals",
        function()
            dbot.debug("@YTrigger fired: identify.intuition@W", "discovery")
            if shouldSuppressIdentifyOutput() then
                deleteLine()
            end
        end
    )

    -- Suppress the appraisal message during build (line is useless)
    DINV.discovery.identifyTriggerIds.appraisal = tempRegexTrigger(
        "A full appraisal will reveal",
        function()
            if shouldSuppressIdentifyOutput() then
                deleteLine()
            end
        end
    )

    dbot.debug("@YIdentify triggers registered@W", "discovery")
end

----------------------------------------------------------------------------------------------------
-- Unregister Identify Triggers
----------------------------------------------------------------------------------------------------

function DINV.discovery.unregisterIdentifyTriggers()
    local triggerNames = {
        "cardFenceTop", "cardFenceBottom", "cardLine", "identifyId",
        "intuition", "appraisal",
        "cardHeader", "cardTotal", "cardMoment", "cardSeparator", "cardStored"
    }

    for _, name in ipairs(triggerNames) do
        local id = DINV.discovery.identifyTriggerIds and DINV.discovery.identifyTriggerIds[name]
        if id then
            killTrigger(id)
        end
    end

    for name, id in pairs(DINV.discovery.identifyTriggerIds or {}) do
        if id then
            killTrigger(id)
        end
    end
    DINV.discovery.identifyTriggerIds = {}
    DINV.discovery.identifyBuffer = {}
end

----------------------------------------------------------------------------------------------------
-- Initialize
----------------------------------------------------------------------------------------------------

function DINV.discovery.init()
    return DINV.discovery.register()
end

----------------------------------------------------------------------------------------------------
-- End of discovery module
----------------------------------------------------------------------------------------------------

dbot.debug("@Ydinv_discovery module loaded (DEBUG + ROBUST TAGS)@W", "discovery")
