----------------------------------------------------------------------------------------------------
-- INV Keyword Module
-- Custom keyword management for items
----------------------------------------------------------------------------------------------------

inv.keyword = {}

local function trim(value)
    return (tostring(value):match("^%s*(.-)%s*$"))
end

local function syncCustomKeywords(objId, item)
    if not item then return end
    local words = {}
    for kw, active in pairs(item.keywords or {}) do
        if active then
            table.insert(words, kw)
        end
    end
    table.sort(words)
    item.stats = item.stats or {}
    item.stats.custom_keywords = #words > 0 and table.concat(words, " ") or nil
    if DINV and DINV.database and DINV.database.markItem then
        DINV.database.markItem(objId, item, "active")
    end
end

function inv.keyword.add(keyword, query, endTag)
    local cleanKeyword = string.lower(trim(keyword or ""))
    if cleanKeyword == "" then
        dbot.warn("Keyword cannot be empty")
        return inv.tags.stop(invTagsKeyword, endTag, DRL_RET_INVALID_PARAM)
    end

    local itemIds, retval = inv.items.search(query or "")
    if retval ~= DRL_RET_SUCCESS then
        return inv.tags.stop(invTagsKeyword, endTag, retval)
    end

    if #itemIds == 0 then
        dbot.info("No items matching '" .. (query or "") .. "' found.")
        return inv.tags.stop(invTagsKeyword, endTag, DRL_RET_MISSING_ENTRY)
    end

    local updated = 0
    for _, objId in ipairs(itemIds) do
        local item = inv.items.getItem(objId)
        if item then
            if item.keywords == nil then
                item.keywords = {}
            end
            if not item.keywords[cleanKeyword] then
                item.keywords[cleanKeyword] = true
                syncCustomKeywords(objId, item)
                updated = updated + 1
            end
        end
    end

    if updated > 0 and DINV and DINV.database and DINV.database.flush then
        local ok, err = DINV.database.flush("active")
        if not ok then
            dbot.warn("Failed to persist custom keywords: " .. tostring(err))
            return inv.tags.stop(invTagsKeyword, endTag, DRL_RET_INTERNAL_ERROR)
        end
    end

    dbot.info("Added keyword '" .. cleanKeyword .. "' to " .. updated .. " item(s)")
    return inv.tags.stop(invTagsKeyword, endTag, DRL_RET_SUCCESS)
end

function inv.keyword.remove(keyword, query, endTag)
    local cleanKeyword = string.lower(trim(keyword or ""))
    if cleanKeyword == "" then
        dbot.warn("Keyword cannot be empty")
        return inv.tags.stop(invTagsKeyword, endTag, DRL_RET_INVALID_PARAM)
    end

    local itemIds, retval = inv.items.search(query or "")
    if retval ~= DRL_RET_SUCCESS then
        return inv.tags.stop(invTagsKeyword, endTag, retval)
    end

    if #itemIds == 0 then
        dbot.info("No items matching '" .. (query or "") .. "' found.")
        return inv.tags.stop(invTagsKeyword, endTag, DRL_RET_MISSING_ENTRY)
    end

    local updated = 0
    for _, objId in ipairs(itemIds) do
        local item = inv.items.getItem(objId)
        if item and item.keywords and item.keywords[cleanKeyword] then
            item.keywords[cleanKeyword] = nil
            syncCustomKeywords(objId, item)
            updated = updated + 1
        end
    end

    if updated > 0 and DINV and DINV.database and DINV.database.flush then
        local ok, err = DINV.database.flush("active")
        if not ok then
            dbot.warn("Failed to persist custom keywords removal: " .. tostring(err))
            return inv.tags.stop(invTagsKeyword, endTag, DRL_RET_INTERNAL_ERROR)
        end
    end

    dbot.info("Removed keyword '" .. cleanKeyword .. "' from " .. updated .. " item(s)")
    return inv.tags.stop(invTagsKeyword, endTag, DRL_RET_SUCCESS)
end

dbot.debug("inv.keyword module loaded", "inv.keyword")
