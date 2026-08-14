local source = debug.getinfo(1, "S").source or ""
local script_path = source:sub(1, 1) == "@" and source:sub(2) or source
local tests_dir = script_path:gsub("\\", "/"):match("^(.*)/") or "."
local root = tests_dir:match("^(.*)/tests$") or tests_dir

local function expect_equal(actual, expected, label)
    assert(actual == expected, string.format(
        "%s: expected %s (%s), got %s (%s)",
        label, tostring(expected), type(expected), tostring(actual), type(actual)
    ))
end

local commands, timers, raised = {}, {}, {}
DRL_RET_SUCCESS = 0
DRL_RET_INVALID_PARAM = -2
DRL_RET_MISSING_ENTRY = -3
DRL_RET_BUSY = -4
DRL_RET_IN_COMBAT = -11
dbot = {
    debug = function() end,
    warn = function() end,
    info = function() end,
    stripColors = function(value) return tostring(value or "") end,
    gmcp = { stateIsInCombat = function() return false end },
}
function send(command) table.insert(commands, tostring(command)) end
function sendGMCP() end
function cecho() end
function echo() end
function tempTimer(delay, callback)
    table.insert(timers, {delay = delay, callback = callback})
    return #timers
end
function raiseEvent(name, id) table.insert(raised, {name = name, id = id}) end

DINV = {discovery = {unregisterIdentifyTriggers = function() end}}
dofile(root .. "/dinv_inv_core.lua")
dofile(root .. "/dinv_inv_items.lua")

-- Type Key and the exact isKey flag both qualify; a substring does not.
assert(inv.items.isKeyItem({stats = {type = "Key", flags = ""}}), "Type Key qualifies")
assert(inv.items.isKeyItem({stats = {type = "Armor", flags = "magic, isKey, V3"}}),
    "isKey flag qualifies regardless of item type")
assert(not inv.items.isKeyItem({stats = {type = "Armor", flags = "notiskey"}}),
    "isKey matching is token-exact")

-- Items completed by a surrounding build/refresh are not identified twice
-- when the deferred automatic queue drains.
inv.items.table = {
    ["1"] = {stats = {identifyLevel = invIdLevelFull}},
    ["2"] = {stats = {identifyLevel = invIdLevelPartial}},
    ["3"] = {stats = {identifyLevel = invIdLevelPartial}},
}
inv.items.deferredIdentifyQueue = {"1", "2", "3"}
inv.items.buildInProgress = false
inv.items.identifyInProgress = false
inv.items.refreshInProgress = false
timers = {}
expect_equal(inv.items.processDeferredIdentifyQueue("test"), DRL_RET_SUCCESS,
    "deferred identify result")
expect_equal(table.concat(inv.items.identifyQueue, ","), "2,3",
    "partial backlog forms one identify batch")
expect_equal(inv.items.progress.total, 2, "batched progress total")
expect_equal(#inv.items.deferredIdentifyQueue, 0, "deferred queue drained")
inv.items.identifyBatchPending = nil
inv.items.buildInProgress = false
inv.items.identifyInProgress = false
inv.items.singleIdentifyMode = false
inv.items.singleIdentifyId = nil
inv.items.identifyQueue = {}
timers = {}

-- Live invitem tracking never starts identification. It only announces the
-- observed ID so Mapper can selectively identify configured key names.
local queued_id, queued_source, scheduled_source
local original_queue_key = inv.items.queueKeyIdentificationIfNeeded
inv.items.lookupPersistentItem = function() return nil end
inv.items._parseDataLine = function(dataLine)
    local id = tostring(dataLine):match("^(%d+),")
    inv.items.table[id] = {stats = {
        id = id, name = "a white key", type = "Key", flags = "",
        location = "inventory", identifyLevel = invIdLevelPartial,
    }}
    return DRL_RET_SUCCESS
end
inv.items.queueKeyIdentificationIfNeeded = function() return false end
inv.items.enqueueDeferredIdentify = function(id, source_name)
    queued_id, queued_source = tostring(id), tostring(source_name)
    return true
end
inv.items.scheduleDeferredIdentifyProcessing = function(source_name)
    scheduled_source = tostring(source_name)
    return DRL_RET_SUCCESS
end
inv.items.scheduleSaveFromInvmon = function() end

raised = {}
expect_equal(inv.items.onInvitem("77,partial"), DRL_RET_SUCCESS, "partial invitem result")
expect_equal(queued_id, nil, "partial loot is not automatically queued")
expect_equal(queued_source, nil, "partial loot has no identify reason")
expect_equal(scheduled_source, nil, "partial loot schedules no identify")
expect_equal(#raised, 1, "partial loot observation event count")
expect_equal(raised[1].name, "DINV.itemObserved", "partial loot observation event")
expect_equal(raised[1].id, "77", "partial loot observation id")

-- Keyring data queues partial keys only as part of build/refresh.
local keyring_queued
inv.items.queueKeyIdentificationIfNeeded = function(id, source_name)
    keyring_queued = tostring(id) .. ":" .. tostring(source_name)
    return true
end
inv.items.buildInProgress = false
inv.items.refreshInProgress = false
expect_equal(inv.items.onKeyringData("78,partial"), DRL_RET_SUCCESS, "live keyring data")
expect_equal(keyring_queued, nil, "live keyring data does not identify")
inv.items.buildInProgress = true
expect_equal(inv.items.onKeyringData("78,partial"), DRL_RET_SUCCESS, "build keyring data")
expect_equal(keyring_queued, "78:keyring data", "build keyring key queued")
inv.items.buildInProgress = false

-- A keyring target follows get -> identify -> put and only then completes.
inv.items.queueKeyIdentificationIfNeeded = original_queue_key
inv.items.enqueueDeferredIdentify = function() return true end
inv.items.scheduleDeferredIdentifyProcessing = function() return DRL_RET_SUCCESS end
inv.items.table = {
    ["9"] = {stats = {
        id = "9", name = "a small key", type = "Key", flags = "magic",
        location = invItemLocKeyring, container = invItemLocKeyring,
        lastStored = invItemLocKeyring, worn = invItemWornNotWorn,
        identifyLevel = invIdLevelPartial,
    }},
}
inv.items.detached = {}
inv.items.pendingRemoved = {}
inv.items.identifyQueue = {"9"}
inv.items.identifyIndex = 0
inv.items.identifyInProgress = true
inv.items.buildInProgress = true
inv.items.forceIdentify = true
inv.items.progress = {total = 1}
inv.items.applyCachedStats = function() return false end
inv.items.showProgress = function() end
inv.items.cancelPendingRemoval = function() end
inv.items.markLocationObserved = function() end
inv.items.scheduleSaveFromInvmon = function() end
local complete = false
local actual_build_complete = inv.items.buildComplete
inv.items.buildComplete = function()
    complete = true
    inv.items.buildInProgress = false
    inv.items.identifyInProgress = false
end

commands, timers = {}, {}
inv.items.identifyNext()
expect_equal(commands[1], "keyring get 9", "keyring retrieval command")
expect_equal(inv.items.identifyWaitForInvmon.action, invmonActionGetFromKeyring,
    "waits for keyring retrieval invmon")

expect_equal(inv.items.onInvmon("12,9,0,0"), DRL_RET_SUCCESS, "keyring get invmon")
expect_equal(commands[2], "identify 9", "targeted identify command")
expect_equal(commands[3], "echo " .. inv.items.identifyFence, "identify fence command")
assert(inv.items.identifyWaitForFence.returnToKeyring, "identify remembers keyring origin")

inv.items.table["9"].stats.keywords = "eternal damnation small key"
inv.items.identifySawOutput = { ["9"] = true }
inv.items.handleIdentifyFence("9")
expect_equal(inv.items.table["9"].stats.identifyLevel, invIdLevelFull,
    "successful key identify is full")

local put_callback
for _, timer in ipairs(timers) do
    if tonumber(timer.delay) == 0.3 then put_callback = timer.callback end
end
assert(type(put_callback) == "function", "keyring restore timer scheduled")
put_callback()
expect_equal(commands[4], "keyring put 9", "keyring restore command")
expect_equal(inv.items.identifyWaitForInvmon.action, invmonActionPutIntoKeyring,
    "waits for keyring restore invmon")

expect_equal(inv.items.onInvmon("11,9,0,0"), DRL_RET_SUCCESS, "keyring put invmon")
expect_equal(inv.items.table["9"].stats.location, invItemLocKeyring,
    "restored key location")
local advance_callback
for _, timer in ipairs(timers) do
    if tonumber(timer.delay) == 0.1 then advance_callback = timer.callback end
end
assert(type(advance_callback) == "function", "identify advance timer scheduled")
advance_callback()
assert(complete, "targeted identify completes only after keyring restore")

-- Every ID accepted into a targeted identify batch gets its completion event.
inv.items.buildComplete = actual_build_complete
inv.items.finalizeInlineProgress = function() end
inv.items.save = function() return DRL_RET_SUCCESS end
inv.items.maybeStartKeepFlagSync = function() end
inv.items.scheduleDeferredIdentifyProcessing = function() return DRL_RET_SUCCESS end
inv.items.singleIdentifyMode = true
inv.items.singleIdentifyId = "9"
inv.items.identifyQueue = {"9", "10"}
inv.items.identifyCreatedMissing = {}
inv.items.identifySawOutput = {}
inv.items.identifyHydratedFromInvdata = {}
inv.items.buildInProgress = true
inv.items.identifyInProgress = true
raised = {}
inv.items.buildComplete()
expect_equal(#raised, 2, "completion event count")
expect_equal(raised[1].id, "9", "first completion id")
expect_equal(raised[2].id, "10", "queued completion id")

-- DINV's temporary keyring movement messages are gagged during identification.
local regex_callbacks, deleted_lines = {}, 0
function tempRegexTrigger(pattern, callback)
    regex_callbacks[pattern] = callback
    return pattern
end
function killTrigger() end
function deleteLine() deleted_lines = deleted_lines + 1 end
function getCurrentLine() return "" end
dofile(root .. "/dinv_discovery.lua")
inv.items.buildInProgress = true
inv.items.identifyInProgress = true
inv.items.refreshInProgress = false
DINV.discovery.registerIdentifyTriggers()
local get_message = regex_callbacks["^\\s*You remove .+ from your keyring\\.?\\s*$"]
local put_message = regex_callbacks["^\\s*You put .+ on your keyring\\.?\\s*$"]
assert(type(get_message) == "function", "keyring get message suppressor registered")
assert(type(put_message) == "function", "keyring put message suppressor registered")
get_message()
put_message()
expect_equal(deleted_lines, 2, "keyring workflow messages suppressed")
inv.items.buildInProgress = false
inv.items.identifyInProgress = false
get_message()
put_message()
expect_equal(deleted_lines, 2, "manual keyring messages remain visible")

print("DINV targeted/keyring identify regression checks passed")
