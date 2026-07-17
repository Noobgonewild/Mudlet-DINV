----------------------------------------------------------------------------------------------------
-- DINV Observed Operation Coordinator
-- Bulk operations remain pipelined; invmon observations are collected behind a final barrier.
----------------------------------------------------------------------------------------------------

inv = inv or {}
inv.operations = inv.operations or {}
inv.operations.active = inv.operations.active or {}
inv.operations.nextId = inv.operations.nextId or 0

local function normalizeWearLocation(value)
    local numeric = tonumber(value)
    if numeric and inv.wearLoc then
        return inv.wearLoc[numeric] or tostring(value)
    end
    return tostring(value or "")
end

local function actionSet(values)
    local result = {}
    for _, value in ipairs(values or {}) do
        result[tonumber(value)] = true
    end
    return result
end

local function expectationFromCommand(command)
    local verb, objId, arg = tostring(command or ""):match("^(%S+)%s+(%d+)%s*(%S*)")
    verb = verb and verb:lower() or nil
    if not verb or not objId then
        return nil
    end

    if verb == "wear" or verb == "hold" then
        return {
            objId = tostring(objId),
            command = command,
            kind = "worn",
            actions = actionSet({ invmonActionWorn }),
            wearLocation = verb == "hold" and invWearLocHold or normalizeWearLocation(arg),
        }
    elseif verb == "get" then
        return {
            objId = tostring(objId),
            command = command,
            kind = "inventory",
            actions = actionSet({ invmonActionAddedToInv, invmonActionTakenOutOfContainer, invmonActionGetFromKeyring }),
        }
    elseif verb == "put" then
        return {
            objId = tostring(objId),
            command = command,
            kind = "container",
            containerId = tostring(arg or ""),
            actions = actionSet({ invmonActionPutIntoContainer, invmonActionPutIntoKeyring }),
        }
    elseif verb == "remove" then
        return {
            objId = tostring(objId),
            command = command,
            kind = "inventory",
            actions = actionSet({ invmonActionRemoved }),
        }
    end
    return nil
end

local function currentState(objId)
    local item = inv.items and inv.items.getItem and inv.items.getItem(objId) or nil
    local stats = item and item.stats or {}
    return {
        exists = item ~= nil,
        location = tostring(stats[invStatFieldLocation] or ""),
        container = tostring(stats[invStatFieldContainer] or ""),
        worn = tostring(stats[invStatFieldWorn] or ""),
    }
end

local function stateSatisfies(expectation)
    local state = currentState(expectation.objId)
    if not state.exists then
        return false, state
    end
    if expectation.kind == "worn" then
        local expected = normalizeWearLocation(expectation.wearLocation)
        local actual = normalizeWearLocation(state.worn)
        local location = normalizeWearLocation(state.location)
        return actual == expected or location == expected, state
    elseif expectation.kind == "inventory" then
        local worn = state.worn
        return state.location == invItemLocInventory
            and (worn == "" or worn == "undefined" or worn == invItemWornNotWorn), state
    elseif expectation.kind == "container" then
        return state.container == tostring(expectation.containerId)
            or state.location == tostring(expectation.containerId), state
    end
    return false, state
end

local function stopTimer(operation)
    if operation.timerName and dbot and dbot.deleteTimer then
        dbot.deleteTimer(operation.timerName)
    end
end

function inv.operations.finish(operationId, timedOut)
    local operation = inv.operations.active[operationId]
    if not operation or operation.finished then
        return
    end
    operation.finished = true
    stopTimer(operation)

    local confirmed = 0
    local failures = {}
    for _, expectation in ipairs(operation.expectations) do
        if not expectation.confirmed then
            local satisfied, state = stateSatisfies(expectation)
            if satisfied then
                expectation.confirmed = true
                expectation.confirmedBy = "final_state"
            else
                expectation.finalState = state
                table.insert(failures, expectation)
            end
        end
        if expectation.confirmed then
            confirmed = confirmed + 1
        end
    end

    local result = {
        id = operation.id,
        label = operation.label,
        total = #operation.expectations,
        confirmed = confirmed,
        failures = failures,
        timedOut = timedOut == true,
    }

    if operation.report ~= false then
        if #failures == 0 then
            dbot.debug(string.format("%s observed: %d/%d requested item actions confirmed.",
                operation.label, confirmed, #operation.expectations), "inv.operations")
        else
            dbot.warn(string.format("%s observed: %d/%d confirmed; %d failed or unobserved.",
                operation.label, confirmed, #operation.expectations, #failures))
            for _, failure in ipairs(failures) do
                local state = failure.finalState or currentState(failure.objId)
                dbot.warn(string.format("  item %s: %s; final location=%s container=%s worn=%s",
                    tostring(failure.objId), tostring(failure.command or failure.kind),
                    tostring(state.location), tostring(state.container), tostring(state.worn)))
            end
        end
    end

    inv.operations.active[operationId] = nil
    if type(operation.onFinish) == "function" then
        pcall(operation.onFinish, result)
    end
end

function inv.operations.start(label, expectations, options)
    options = options or {}
    local normalized = {}
    for _, expectation in ipairs(expectations or {}) do
        expectation.objId = tostring(expectation.objId or "")
        expectation.actions = expectation.actions or actionSet(expectation.action and { expectation.action } or {})
        if expectation.objId ~= "" then
            table.insert(normalized, expectation)
        end
    end
    if #normalized == 0 then
        return nil
    end

    inv.operations.nextId = inv.operations.nextId + 1
    local operationId = inv.operations.nextId
    local operation = {
        id = operationId,
        label = tostring(label or "DINV operation"),
        expectations = normalized,
        report = options.report,
        onFinish = options.onFinish,
        finished = false,
    }
    inv.operations.active[operationId] = operation

    local timeout = tonumber(options.timeout) or math.max(6, #normalized * 0.15 + 3)
    operation.timerName = "dinv.operations." .. tostring(operationId)
    if tempTimer then
        dbot.timers[operation.timerName] = tempTimer(timeout, function()
            inv.operations.finish(operationId, true)
        end)
    end
    return operationId
end

function inv.operations.startBatchFromCommands(label, commands, options)
    local expectations = {}
    for _, command in ipairs(commands or {}) do
        local expectation = expectationFromCommand(command)
        if expectation then
            table.insert(expectations, expectation)
        end
    end
    return inv.operations.start(label, expectations, options)
end

function inv.operations.cancelAll()
    for _, operation in pairs(inv.operations.active or {}) do
        stopTimer(operation)
        operation.finished = true
    end
    inv.operations.active = {}
end

function inv.operations.observe(action, objId, containerId, wearLocation)
    local actionNumber = tonumber(action)
    local objectKey = tostring(objId or "")
    local completedOperations = {}
    for operationId, operation in pairs(inv.operations.active) do
        for expectationIndex, expectation in ipairs(operation.expectations) do
            if not expectation.confirmed
                and expectation.objId == objectKey
                and expectation.actions[actionNumber] then
                local matches = true
                if expectation.kind == "worn" and expectation.wearLocation then
                    matches = normalizeWearLocation(expectation.wearLocation)
                        == normalizeWearLocation(wearLocation)
                elseif expectation.kind == "container" and expectation.containerId ~= "" then
                    matches = tostring(expectation.containerId) == tostring(containerId)
                end
                if matches then
                    expectation.confirmed = true
                    expectation.confirmedBy = "invmon"
                    expectation.eventSequence = tonumber(inv.items and inv.items.eventSequence) or 0
                    -- A later exact-object observation also proves earlier
                    -- dependent commands for that object succeeded (for
                    -- example wear proves the preceding get completed).
                    for priorIndex = 1, expectationIndex - 1 do
                        local prior = operation.expectations[priorIndex]
                        if not prior.confirmed and prior.objId == objectKey then
                            prior.confirmed = true
                            prior.confirmedBy = "downstream_invmon"
                            prior.eventSequence = expectation.eventSequence
                        end
                    end
                    break
                end
            end
        end

        local complete = true
        for _, expectation in ipairs(operation.expectations) do
            if not expectation.confirmed then
                complete = false
                break
            end
        end
        if complete then
            table.insert(completedOperations, operationId)
        end
    end
    for _, operationId in ipairs(completedOperations) do
        if tempTimer then
            tempTimer(0.2, function() inv.operations.finish(operationId, false) end)
        else
            inv.operations.finish(operationId, false)
        end
    end
end

dbot.debug("inv.operations module loaded", "inv.operations")
