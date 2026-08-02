----------------------------------------------------------------------------------------------------
-- DINV Consumables Window
-- Bookmark-style Geyser/Adjustable miniwindow for configured consumables.
----------------------------------------------------------------------------------------------------

if type(inv.consumeWindow) == "table" and type(inv.consumeWindow.shutdown) == "function" then
    pcall(inv.consumeWindow.shutdown, true, true)
end

inv.consumeWindow = {
    init = {},
    ui = {},
    handlers = {},
    visible = false,
    filterType = "",
    lastRoom = nil,
    pendingTravel = nil,
    refreshTimer = nil,
    travelTimer = nil,
}

local window = inv.consumeWindow
local CONTAINER_NAME = "DINVConsumeWindow"
local HEADER_HEIGHT = 24
local BODY_GAP = 1
local RESIZE_MARGIN = 3
local CONTENT_MARGIN = 2
local SECTION_HEIGHT = 17
local CARD_HEIGHT = 48
local CARD_NAME_HEIGHT = 28
local CARD_GAP = 4

local colors = {
    frame = "#000000",
    background = "#101216",
    panel = "#181b21",
    card = "#1d2630",
    cardHover = "#25313d",
    action = "#182029",
    border = "#4a4f59",
    divider = "#7a8491",
    text = "#e6e6e6",
    muted = "#8b9099",
    accent = "#f0a500",
    count = "#64d8ff",
}

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function clean(value)
    local text = dbot and dbot.stripColors and dbot.stripColors(value) or tostring(value or "")
    return trim(text:gsub("[\r\n\t]+", " "))
end

local function htmlEscape(value)
    local text = tostring(value or "")
    text = text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    text = text:gsub('"', "&quot;"):gsub("'", "&#39;")
    return text
end

local function displayName(entry)
    local name = clean(entry and entry.name or "Consumable")
    if name == "" then name = "Consumable" end
    return name:gsub("^%l", string.upper)
end

local function labelStyle(background, border, foreground, extra)
    return string.format(
        "background-color: %s; border: 1px solid %s; color: %s; padding: 1px; font-size: 8pt; %s",
        background or "transparent",
        border or "transparent",
        foreground or colors.text,
        extra or ""
    )
end

local function actionStyle(leftDivider)
    return string.format(
        "background-color: %s; border: 0px; border-top: 1px solid %s; %s color: %s; padding: 0px; font-size: 8pt; font-weight: bold;",
        colors.action,
        colors.border,
        leftDivider and ("border-left: 1px solid " .. colors.divider .. ";") or "",
        colors.text
    )
end

local function setLabel(label, text, foreground, alignment)
    if label and type(label.echo) == "function" then
        pcall(label.echo, label, htmlEscape(text), foreground or colors.text, alignment or "l")
    end
end

local function setRichLabel(label, markup, alignment)
    if label and type(label.echo) == "function" then
        pcall(label.echo, label, tostring(markup or ""), colors.text, alignment or "l")
    end
end

local function setClickable(label, callback, arguments, tooltip)
    if not label then return end
    if type(label.setClickCallback) == "function" then
        local callbackArgs = { label, callback }
        for _, argument in ipairs(arguments or {}) do
            callbackArgs[#callbackArgs + 1] = argument
        end
        pcall(label.setClickCallback, unpack(callbackArgs))
    end
    if type(label.setToolTip) == "function" then
        pcall(label.setToolTip, label, tooltip or "")
    end
    if type(label.setCursor) == "function" then
        pcall(label.setCursor, label, "PointingHand")
    end
end

local function destroyObject(object)
    if not object then return end
    if type(object.hide) == "function" then pcall(object.hide, object) end
    if type(object.delete) == "function" then pcall(object.delete, object) end
end

local function configuredGeometry()
    if inv.config and inv.config.getConsumeWindowGeometry then
        return inv.config.getConsumeWindowGeometry()
    end
    return { x = "2%", y = "2%", width = 190, height = 390 }
end

local function currentWidth()
    local container = window.ui and window.ui.container
    if container and type(container.get_width) == "function" then
        local ok, value = pcall(container.get_width, container)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return tonumber(configuredGeometry().width) or 190
end

function window.captureGeometry()
    local container = window.ui and window.ui.container
    if not container then return nil end
    local geometry = {}
    for key, getter in pairs({
        x = "get_x",
        y = "get_y",
        width = "get_width",
        height = "get_height",
    }) do
        if type(container[getter]) == "function" then
            local ok, value = pcall(container[getter], container)
            if ok and value ~= nil then geometry[key] = value end
        end
    end
    return geometry
end

function window.saveGeometry()
    local geometry = window.captureGeometry()
    if geometry and inv.config and inv.config.setConsumeWindowGeometry then
        return inv.config.setConsumeWindowGeometry(geometry)
    end
    return DRL_RET_SUCCESS
end

function window.destroyUI()
    if not window.ui then return end
    for _, card in ipairs(window.ui.cards or {}) do
        destroyObject(card.container)
    end
    for _, section in ipairs(window.ui.sections or {}) do
        destroyObject(section)
    end
    destroyObject(window.ui.empty)
    destroyObject(window.ui.scroll)
    destroyObject(window.ui.header)
    destroyObject(window.ui.container)
    window.ui = {}
end

function window.shutdown(saveGeometry, destroy)
    if saveGeometry then pcall(window.saveGeometry) end
    if window.refreshTimer and type(killTimer) == "function" then
        pcall(killTimer, window.refreshTimer)
    end
    if window.travelTimer and type(killTimer) == "function" then
        pcall(killTimer, window.travelTimer)
    end
    window.refreshTimer = nil
    window.travelTimer = nil
    for _, handlerId in pairs(window.handlers or {}) do
        if handlerId and type(killAnonymousEventHandler) == "function" then
            pcall(killAnonymousEventHandler, handlerId)
        end
    end
    window.handlers = {}
    window.visible = false
    if destroy then
        window.destroyUI()
    elseif window.ui and window.ui.container and type(window.ui.container.hide) == "function" then
        pcall(window.ui.container.hide, window.ui.container)
    end
end

local function bodyParent()
    return window.ui.scroll or window.ui.container
end

local function makeSection(index)
    local section = Geyser.Label:new({
        name = "DINVConsumeWindowSection" .. tostring(index),
        x = CONTENT_MARGIN,
        y = 0,
        width = "100%-" .. tostring(CONTENT_MARGIN * 2) .. "px",
        height = SECTION_HEIGHT,
    }, bodyParent())
    section:setStyleSheet(labelStyle(colors.background, "transparent", colors.accent, "font-weight: bold;"))
    window.ui.sections[index] = section
    return section
end

local function makeCard(index)
    local prefix = "DINVConsumeWindowCard" .. tostring(index)
    local card = {}
    card.container = Geyser.Container:new({
        name = prefix,
        x = CONTENT_MARGIN,
        y = 0,
        width = "100%-" .. tostring(CONTENT_MARGIN * 2) .. "px",
        height = CARD_HEIGHT,
    }, bodyParent())
    card.background = Geyser.Label:new({
        name = prefix .. "Background", x = 0, y = 0, width = "100%", height = "100%",
    }, card.container)
    card.name = Geyser.Label:new({
        name = prefix .. "Name", x = 1, y = 1, width = "100%-2px", height = CARD_NAME_HEIGHT - 1,
    }, card.container)
    card.buyOne = Geyser.Label:new({
        name = prefix .. "BuyOne", x = 1, y = CARD_NAME_HEIGHT, width = "33%", height = CARD_HEIGHT - CARD_NAME_HEIGHT - 1,
    }, card.container)
    card.buyTen = Geyser.Label:new({
        name = prefix .. "BuyTen", x = "33%", y = CARD_NAME_HEIGHT, width = "34%", height = CARD_HEIGHT - CARD_NAME_HEIGHT - 1,
    }, card.container)
    card.buyFifty = Geyser.Label:new({
        name = prefix .. "BuyFifty", x = "67%", y = CARD_NAME_HEIGHT, width = "33%-1px", height = CARD_HEIGHT - CARD_NAME_HEIGHT - 1,
    }, card.container)
    window.ui.cards[index] = card
    return card
end

local function ensureUI()
    if not Geyser then
        return false, "Geyser is unavailable"
    end
    if window.ui.container then return true end

    local geometry = configuredGeometry()
    local container
    if Adjustable and Adjustable.Container and type(Adjustable.Container.new) == "function" then
        local ok, result = pcall(function()
            return Adjustable.Container:new({
                name = CONTAINER_NAME,
                x = geometry.x,
                y = geometry.y,
                width = geometry.width,
                height = geometry.height,
                autoLoad = false,
                autoSave = false,
                padding = 0,
                adjLabelstyle = "border: 1px solid " .. colors.frame .. "; background-color: " .. colors.frame .. ";",
                buttonstyle = "",
                lockStyle = "border: 0px;",
                titleText = "",
                titleTxtColor = "white",
            })
        end)
        if ok then container = result end
    end
    if not container then
        container = Geyser.Container:new({
            name = CONTAINER_NAME,
            x = geometry.x,
            y = geometry.y,
            width = geometry.width,
            height = geometry.height,
        })
        if type(container.enableDrag) == "function" then pcall(container.enableDrag, container) end
        if type(container.enableResize) == "function" then pcall(container.enableResize, container) end
    end
    window.ui.container = container
    if type(container.setPadding) == "function" then pcall(container.setPadding, container, 0) end

    window.ui.header = Geyser.Label:new({
        name = "DINVConsumeWindowHeader",
        x = 0,
        y = 0,
        width = "100%",
        height = HEADER_HEIGHT,
        clickthrough = true,
    }, container)
    window.ui.header:setStyleSheet(labelStyle(colors.panel, colors.border, colors.text, "font-weight: bold;"))
    setLabel(window.ui.header, "DINV Consumables", colors.text, "l")

    local bodyTop = HEADER_HEIGHT + BODY_GAP
    -- A plain container deliberately clips overflow instead of showing the
    -- horizontal and vertical scrollbars added by Geyser.ScrollBox.
    window.ui.scroll = Geyser.Container:new({
        name = "DINVConsumeWindowBody",
        x = RESIZE_MARGIN,
        y = bodyTop,
        width = "100%-" .. tostring(RESIZE_MARGIN * 2) .. "px",
        height = "100%-" .. tostring(bodyTop + RESIZE_MARGIN) .. "px",
    }, container)
    window.ui.sections = {}
    window.ui.cards = {}
    window.ui.empty = Geyser.Label:new({
        name = "DINVConsumeWindowEmpty",
        x = 4,
        y = 4,
        width = "100%-8px",
        height = 30,
    }, bodyParent())
    window.ui.empty:setStyleSheet(labelStyle(colors.background, "transparent", colors.muted, ""))

    if container.exitLabel and type(container.exitLabel.setClickCallback) == "function" then
        pcall(container.exitLabel.setClickCallback, container.exitLabel, "inv.consumeWindow.hide")
    end
    if type(container.newCustomItem) == "function" then
        pcall(container.newCustomItem, container, "Refresh consumables", function() window.render() end)
        pcall(container.newCustomItem, container, "Hide consumables", function() window.hide() end)
    end
    return true
end

local function cardInfo(entry, count)
    local name = htmlEscape(displayName(entry))
    local level = tonumber(entry and entry.level) or 0
    local width = currentWidth()
    local quantity = string.format(
        "<span style='color: %s; font-weight: bold;'>×%d</span>",
        colors.count,
        count
    )
    if width >= 220 then
        return string.format(
            "%s (L%d) · <span style='color: %s; font-weight: bold;'>%d available</span>",
            name,
            level,
            colors.count,
            count
        )
    elseif width >= 110 then
        return string.format("%s · L%d · %s", name, level, quantity)
    end
    return string.format("%s · %s", name, quantity)
end

local function renderCard(card, typeName, entryIndex, entry, count, y)
    card.container:show()
    card.container:move(CONTENT_MARGIN, y)
    card.container:resize("100%-" .. tostring(CONTENT_MARGIN * 2) .. "px", CARD_HEIGHT)
    card.background:setStyleSheet(labelStyle(colors.card, colors.border, colors.text, "border-radius: 3px;"))
    card.name:setStyleSheet(
        "background-color: transparent; border: 0px; color: " .. colors.text ..
        "; padding: 3px 6px; font-size: 8pt;"
    )
    card.buyOne:setStyleSheet(actionStyle(false))
    card.buyTen:setStyleSheet(actionStyle(true))
    card.buyFifty:setStyleSheet(actionStyle(true))

    setRichLabel(card.name, cardInfo(entry, count), "l")
    setLabel(card.buyOne, "x1", colors.text, "c")
    setLabel(card.buyTen, "x10", colors.text, "c")
    setLabel(card.buyFifty, "x50", colors.text, "c")

    local name = displayName(entry)
    local travelArgs = { tostring(typeName), tostring(entryIndex) }
    setClickable(card.background, "inv.consumeWindow.travel", travelArgs,
        "Travel to the vendor for " .. name)
    setClickable(card.name, "inv.consumeWindow.travel", travelArgs,
        "Travel to the vendor for " .. name)
    setClickable(card.buyOne, "inv.consumeWindow.buy",
        { tostring(typeName), tostring(entryIndex), "1" }, "Buy 1 " .. name)
    setClickable(card.buyTen, "inv.consumeWindow.buy",
        { tostring(typeName), tostring(entryIndex), "10" }, "Buy 10 " .. name)
    setClickable(card.buyFifty, "inv.consumeWindow.buy",
        { tostring(typeName), tostring(entryIndex), "50" }, "Buy 50 " .. name)
end

function window.render()
    if not window.visible then return true end
    local ok, err = ensureUI()
    if not ok then return false, err end

    local types = {}
    local filter = trim(window.filterType):lower()
    local ownedOnly = filter == "owned"
    if filter ~= "" and not ownedOnly then
        if inv.consume.table and inv.consume.table[filter] then types = { filter } end
    elseif inv.consume and inv.consume.getSortedTypes then
        types = inv.consume.getSortedTypes()
    end

    local y = 2
    local sectionIndex = 0
    local cardIndex = 0
    for _, typeName in ipairs(types) do
        local rows = {}
        for entryIndex, entry in ipairs(inv.consume.table[typeName] or {}) do
            local count = inv.consume.countEntry(entry)
            if not ownedOnly or count > 0 then
                rows[#rows + 1] = { index = entryIndex, entry = entry, count = count }
            end
        end
        if #rows > 0 then
            sectionIndex = sectionIndex + 1
            local section = window.ui.sections[sectionIndex] or makeSection(sectionIndex)
            section:show()
            section:move(CONTENT_MARGIN, y)
            section:resize("100%-" .. tostring(CONTENT_MARGIN * 2) .. "px", SECTION_HEIGHT)
            section:setStyleSheet(labelStyle(colors.background, "transparent", colors.accent, "font-weight: bold;"))
            setLabel(section, tostring(typeName):upper(), colors.accent, "l")
            y = y + SECTION_HEIGHT

            for _, row in ipairs(rows) do
                cardIndex = cardIndex + 1
                local card = window.ui.cards[cardIndex] or makeCard(cardIndex)
                renderCard(card, typeName, row.index, row.entry, row.count, y)
                y = y + CARD_HEIGHT + CARD_GAP
            end
            y = y + 2
        end
    end

    for index = sectionIndex + 1, #(window.ui.sections or {}) do
        window.ui.sections[index]:hide()
    end
    for index = cardIndex + 1, #(window.ui.cards or {}) do
        window.ui.cards[index].container:hide()
    end

    if cardIndex == 0 then
        window.ui.empty:show()
        setLabel(window.ui.empty, "No configured consumables to show.", colors.muted, "l")
    else
        window.ui.empty:hide()
    end

    setLabel(window.ui.header, "DINV Consumables", colors.text, "l")
    if type(window.ui.container.show) == "function" then
        pcall(window.ui.container.show, window.ui.container)
    end
    return true
end

function window.scheduleRefresh(structureChanged)
    if not window.visible then return DRL_RET_SUCCESS end
    if window.refreshTimer and type(killTimer) == "function" then
        pcall(killTimer, window.refreshTimer)
    end
    window.refreshTimer = nil
    if structureChanged then
        window.render()
        return DRL_RET_SUCCESS
    end
    if type(tempTimer) == "function" then
        window.refreshTimer = tempTimer(0.15, function()
            window.refreshTimer = nil
            if window.visible then window.render() end
        end)
    else
        window.render()
    end
    return DRL_RET_SUCCESS
end

function window.show(filterType)
    if not (inv.config and inv.config.isConsumeWindowEnabled
        and inv.config.isConsumeWindowEnabled()) then
        return false, "the consumables miniwindow is disabled"
    end
    local ok, err = ensureUI()
    if not ok then return false, err end
    window.filterType = trim(filterType):lower()
    window.visible = true
    local rendered, renderErr = window.render()
    if not rendered then
        window.visible = false
        return false, renderErr
    end
    return true
end

function window.hide()
    window.visible = false
    window.filterType = ""
    if window.ui and window.ui.container and type(window.ui.container.hide) == "function" then
        pcall(window.ui.container.hide, window.ui.container)
    end
    pcall(window.saveGeometry)
    return true
end

function window.isVendorRoom(roomId)
    local target = tonumber(roomId or "")
    if not target then return false end
    for _, entries in pairs(inv.consume and inv.consume.table or {}) do
        for _, entry in ipairs(entries or {}) do
            if tonumber(entry.room or "") == target then return true end
        end
    end
    return false
end

function window.beginTravel(roomId, actionKind)
    if window.travelTimer and type(killTimer) == "function" then
        pcall(killTimer, window.travelTimer)
    end
    window.travelTimer = nil
    window.pendingTravel = {
        room = tonumber(roomId or ""),
        kind = tostring(actionKind or "travel"),
    }
    if type(tempTimer) == "function" then
        local pending = window.pendingTravel
        window.travelTimer = tempTimer(30, function()
            window.travelTimer = nil
            if window.pendingTravel == pending then
                window.completeTravel(false)
            end
        end)
    end
    return true
end

function window.completeTravel(succeeded)
    if window.travelTimer and type(killTimer) == "function" then
        pcall(killTimer, window.travelTimer)
    end
    window.travelTimer = nil
    window.pendingTravel = nil
    if not succeeded and not window.isVendorRoom(dbot.gmcp.getRoomId()) then
        window.hide()
    elseif window.visible then
        window.scheduleRefresh()
    end
    return true
end

function window.travel(typeName, entryIndex)
    return inv.consume.travelExact(typeName, entryIndex, "window")
end

function window.buy(typeName, entryIndex, quantity)
    return inv.consume.buyExact(typeName, entryIndex, quantity, nil, "window")
end

function window.onRoomChanged()
    local room = tonumber(dbot.gmcp.getRoomId() or "")
    if not room or room == 0 then return end
    if room == window.lastRoom then return end
    window.lastRoom = room

    if not (inv.config and inv.config.isConsumeWindowEnabled
        and inv.config.isConsumeWindowEnabled()) then
        if window.visible then window.hide() end
        return
    end

    if window.pendingTravel then
        if window.pendingTravel.kind == "travel" and room == window.pendingTravel.room then
            window.completeTravel(true)
        end
        if window.visible then window.scheduleRefresh() end
        return
    end

    if window.isVendorRoom(room) then
        window.show("")
    elseif window.visible then
        window.hide()
    end
end

function window.onResize()
    if window.visible then window.render() end
end

function window.onRepositionFinish(_, containerName, width, height, x, y)
    if tostring(containerName or "") ~= CONTAINER_NAME then return end
    local geometry = {}
    if tonumber(x) then geometry.x = tonumber(x) end
    if tonumber(y) then geometry.y = tonumber(y) end
    if tonumber(width) then geometry.width = tonumber(width) end
    if tonumber(height) then geometry.height = tonumber(height) end
    if next(geometry) and inv.config and inv.config.setConsumeWindowGeometry then
        inv.config.setConsumeWindowGeometry(geometry)
    end
    if window.visible then window.render() end
end

function window.onConfigChanged(enabled)
    if enabled then
        window.lastRoom = tonumber(dbot.gmcp.getRoomId() or "")
        if window.isVendorRoom(window.lastRoom) then
            window.show("")
        end
    else
        window.pendingTravel = nil
        window.hide()
    end
    return DRL_RET_SUCCESS
end

function window.onExit()
    window.shutdown(true, false)
end

function window.init.atInstall()
    if type(registerAnonymousEventHandler) == "function" then
        window.handlers.resize = registerAnonymousEventHandler(
            "sysWindowResizeEvent", "inv.consumeWindow.onResize")
        window.handlers.reposition = registerAnonymousEventHandler(
            "AdjustableContainerRepositionFinish", "inv.consumeWindow.onRepositionFinish")
        window.handlers.exit = registerAnonymousEventHandler(
            "sysExitEvent", "inv.consumeWindow.onExit")
    end
    return DRL_RET_SUCCESS
end

function window.init.atActive()
    window.lastRoom = tonumber(dbot.gmcp.getRoomId() or "")
    if inv.config and inv.config.isConsumeWindowEnabled
        and inv.config.isConsumeWindowEnabled()
        and window.isVendorRoom(window.lastRoom) then
        window.show("")
    end
    return DRL_RET_SUCCESS
end

function window.fini()
    window.shutdown(true, true)
    return DRL_RET_SUCCESS
end

dbot.debug("inv.consumeWindow module loaded", "inv.consumeWindow")
