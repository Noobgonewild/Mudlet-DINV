----------------------------------------------------------------------------------------------------
-- INV Keyword Module
-- Custom keyword management for items
----------------------------------------------------------------------------------------------------

inv.keyword = {}

local function trim(value)
    return (tostring(value):match("^%s*(.-)%s*$"))
end

function inv.keyword.add(keyword, query, endTag)
    local cleanKeyword = string.lower(trim(keyword or ""))
    if cleanKeyword == "" then
        dbot.warn("Keyword cannot be empty")
        return DRL_RET_INVALID_PARAM
    end

    local itemIds, retval = inv.items.search(query or "")
    if retval ~= DRL_RET_SUCCESS then
        return retval
    end

    if #itemIds == 0 then
        dbot.info("No items matching '" .. (query or "") .. "' found.")
        return DRL_RET_MISSING_ENTRY
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
                updated = updated + 1
            end
        end
    end

    dbot.info("Added keyword '" .. cleanKeyword .. "' to " .. updated .. " item(s)")
    return inv.tags.stop(invTagsKeyword, endTag, DRL_RET_SUCCESS)
end

function inv.keyword.remove(keyword, query, endTag)
    local cleanKeyword = string.lower(trim(keyword or ""))
    if cleanKeyword == "" then
        dbot.warn("Keyword cannot be empty")
        return DRL_RET_INVALID_PARAM
    end

    local itemIds, retval = inv.items.search(query or "")
    if retval ~= DRL_RET_SUCCESS then
        return retval
    end

    if #itemIds == 0 then
        dbot.info("No items matching '" .. (query or "") .. "' found.")
        return DRL_RET_MISSING_ENTRY
    end

    local updated = 0
    for _, objId in ipairs(itemIds) do
        local item = inv.items.getItem(objId)
        if item and item.keywords and item.keywords[cleanKeyword] then
            item.keywords[cleanKeyword] = nil
            updated = updated + 1
        end
    end

    dbot.info("Removed keyword '" .. cleanKeyword .. "' from " .. updated .. " item(s)")
    return inv.tags.stop(invTagsKeyword, endTag, DRL_RET_SUCCESS)
end

dbot.debug("inv.keyword module loaded", "inv.keyword")
