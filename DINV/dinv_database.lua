----------------------------------------------------------------------------------------------------
-- DINV SQLite Database
-- Per-character primary persistence, crash-safe build staging, and inventory event journal.
----------------------------------------------------------------------------------------------------

DINV = DINV or {}
DINV.database = DINV.database or {}

local database = DINV.database

database.schemaVersion = 4
database.env = database.env or nil
database.conn = database.conn or nil
database.isOpen = database.isOpen or false
database.file = database.file or nil
database.character = database.character or nil
database.sessionId = database.sessionId or nil
database.pending = database.pending or {
    active = { upserts = {}, deletes = {}, reattach = {}, pendingReattach = {} },
    build = { upserts = {}, deletes = {}, reattach = {}, pendingReattach = {} },
}
database.persistedFingerprints = database.persistedFingerprints or {
    active = {},
    build = {},
}
database.pendingEvents = database.pendingEvents or {}

local CORE_FIELDS = {
    id = true,
    name = true,
    type = true,
    typeNum = true,
    colorname = true,
    colorName = true,
    level = true,
    identifyLevel = true,
    location = true,
    container = true,
    lastStored = true,
    worn = true,
    wearable = true,
    keepflag = true,
    timer = true,
}

local DYNAMIC_TEMPLATE_FIELDS = {
    id = true,
    location = true,
    container = true,
    lastStored = true,
    worn = true,
    keepflag = true,
    timer = true,
    __dinvPresence = true,
    __dinvDetachedRoot = true,
    __dinvLastEventSeq = true,
    __dinvRefreshGeneration = true,
    __dinvLocationSource = true,
    __dinvLocationSession = true,
    __dinvLocationConfirmedAt = true,
    charges = true,
    chargeknown = true,
    chargedirty = true,
    chargesource = true,
    chargeobservedat = true,
    chargerevision = true,
}

local CONSUMABLE_TYPES = {
    potion = true,
    pill = true,
    food = true,
    drink = true,
    scroll = true,
    wand = true,
}

local LEGACY_MODULES = {
    { namespace = "config", file = "inv-config.state", path = { "inv", "config", "table" } },
    { namespace = "cache", file = "inv-cache.state", path = { "inv", "cache", "table" } },
    { namespace = "analyze", file = "inv-analyze.state", path = { "inv", "analyze", "table" } },
    { namespace = "consume", file = "inv-consume.state", path = { "inv", "consume", "table" } },
    { namespace = "priority", file = "inv-priority.state", path = { "inv", "priority", "table" } },
    { namespace = "set", file = "inv-set.state", path = { "inv", "set", "table" } },
    { namespace = "snapshot", file = "inv-snapshot.state", path = { "inv", "snapshot", "table" } },
    { namespace = "statbonus", file = "inv-statbonus.state", path = { "inv", "statBonus", "table" } },
    { namespace = "tags", file = "inv-tags.state", path = { "inv", "tags", "table" } },
    { namespace = "levelup", file = "inv-levelup.state", path = { "inv", "levelup", "table" } },
    { namespace = "notify", file = "dbot-notify.state", path = { "dbot", "notify", "table" } },
    { namespace = "debug", file = "dinv.debug.state", path = { "DINV", "debug", "table" } },
}

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
    )]],
    [[CREATE TABLE IF NOT EXISTS items (
        obj_id TEXT PRIMARY KEY,
        name TEXT,
        color_name TEXT,
        type_name TEXT,
        type_num INTEGER,
        level REAL,
        identify_level TEXT,
        protocol_flags TEXT,
        unique_value TEXT,
        location TEXT,
        container_id TEXT,
        last_stored TEXT,
        worn TEXT,
        wearable TEXT,
        keep_flag INTEGER,
        timer REAL,
        presence TEXT NOT NULL DEFAULT 'active',
        detached_root TEXT,
        refresh_generation INTEGER NOT NULL DEFAULT 0,
        last_event_seq INTEGER NOT NULL DEFAULT 0,
        location_source TEXT,
        location_session TEXT,
        location_confirmed_at INTEGER,
        updated_at INTEGER NOT NULL
    )]],
    [[CREATE TABLE IF NOT EXISTS item_stats (
        obj_id TEXT NOT NULL,
        stat_key TEXT NOT NULL,
        value_type TEXT NOT NULL,
        text_value TEXT,
        numeric_value REAL,
        boolean_value INTEGER,
        PRIMARY KEY (obj_id, stat_key),
        FOREIGN KEY (obj_id) REFERENCES items(obj_id) ON DELETE CASCADE
    )]],
    [[CREATE TABLE IF NOT EXISTS detached_items (
        obj_id TEXT PRIMARY KEY,
        name TEXT,
        color_name TEXT,
        type_name TEXT,
        type_num INTEGER,
        level REAL,
        identify_level TEXT,
        protocol_flags TEXT,
        unique_value TEXT,
        location TEXT,
        container_id TEXT,
        last_stored TEXT,
        worn TEXT,
        wearable TEXT,
        keep_flag INTEGER,
        timer REAL,
        presence TEXT NOT NULL DEFAULT 'detached',
        detached_root TEXT,
        refresh_generation INTEGER NOT NULL DEFAULT 0,
        last_event_seq INTEGER NOT NULL DEFAULT 0,
        location_source TEXT,
        location_session TEXT,
        location_confirmed_at INTEGER,
        updated_at INTEGER NOT NULL
    )]],
    [[CREATE TABLE IF NOT EXISTS detached_item_stats (
        obj_id TEXT NOT NULL,
        stat_key TEXT NOT NULL,
        value_type TEXT NOT NULL,
        text_value TEXT,
        numeric_value REAL,
        boolean_value INTEGER,
        PRIMARY KEY (obj_id, stat_key),
        FOREIGN KEY (obj_id) REFERENCES detached_items(obj_id) ON DELETE CASCADE
    )]],
    [[CREATE TABLE IF NOT EXISTS pending_removed_items (
        obj_id TEXT PRIMARY KEY,
        name TEXT,
        color_name TEXT,
        type_name TEXT,
        type_num INTEGER,
        level REAL,
        identify_level TEXT,
        protocol_flags TEXT,
        unique_value TEXT,
        location TEXT,
        container_id TEXT,
        last_stored TEXT,
        worn TEXT,
        wearable TEXT,
        keep_flag INTEGER,
        timer REAL,
        presence TEXT NOT NULL DEFAULT 'pending-removal',
        detached_root TEXT,
        refresh_generation INTEGER NOT NULL DEFAULT 0,
        last_event_seq INTEGER NOT NULL DEFAULT 0,
        location_source TEXT,
        location_session TEXT,
        location_confirmed_at INTEGER,
        updated_at INTEGER NOT NULL,
        removed_at INTEGER NOT NULL DEFAULT 0,
        purge_after INTEGER NOT NULL DEFAULT 0,
        removal_action INTEGER,
        removal_reason TEXT
    )]],
    [[CREATE TABLE IF NOT EXISTS pending_removed_item_stats (
        obj_id TEXT NOT NULL,
        stat_key TEXT NOT NULL,
        value_type TEXT NOT NULL,
        text_value TEXT,
        numeric_value REAL,
        boolean_value INTEGER,
        PRIMARY KEY (obj_id, stat_key),
        FOREIGN KEY (obj_id) REFERENCES pending_removed_items(obj_id) ON DELETE CASCADE
    )]],
    [[CREATE TABLE IF NOT EXISTS build_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        status TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        identified_count INTEGER NOT NULL DEFAULT 0,
        completed_at INTEGER
    )]],
    [[CREATE TABLE IF NOT EXISTS build_items (
        obj_id TEXT PRIMARY KEY,
        name TEXT,
        color_name TEXT,
        type_name TEXT,
        type_num INTEGER,
        level REAL,
        identify_level TEXT,
        protocol_flags TEXT,
        unique_value TEXT,
        location TEXT,
        container_id TEXT,
        last_stored TEXT,
        worn TEXT,
        wearable TEXT,
        keep_flag INTEGER,
        timer REAL,
        presence TEXT NOT NULL DEFAULT 'active',
        detached_root TEXT,
        refresh_generation INTEGER NOT NULL DEFAULT 0,
        last_event_seq INTEGER NOT NULL DEFAULT 0,
        location_source TEXT,
        location_session TEXT,
        location_confirmed_at INTEGER,
        updated_at INTEGER NOT NULL
    )]],
    [[CREATE TABLE IF NOT EXISTS build_item_stats (
        obj_id TEXT NOT NULL,
        stat_key TEXT NOT NULL,
        value_type TEXT NOT NULL,
        text_value TEXT,
        numeric_value REAL,
        boolean_value INTEGER,
        PRIMARY KEY (obj_id, stat_key),
        FOREIGN KEY (obj_id) REFERENCES build_items(obj_id) ON DELETE CASCADE
    )]],
    [[CREATE TABLE IF NOT EXISTS consumable_templates (
        template_key TEXT PRIMARY KEY,
        type_name TEXT NOT NULL,
        item_name TEXT NOT NULL,
        identify_level TEXT NOT NULL,
        source_obj_id TEXT,
        updated_at INTEGER NOT NULL
    )]],
    [[CREATE TABLE IF NOT EXISTS consumable_template_stats (
        template_key TEXT NOT NULL,
        stat_key TEXT NOT NULL,
        value_type TEXT NOT NULL,
        text_value TEXT,
        numeric_value REAL,
        boolean_value INTEGER,
        PRIMARY KEY (template_key, stat_key),
        FOREIGN KEY (template_key) REFERENCES consumable_templates(template_key) ON DELETE CASCADE
    )]],
    [[CREATE TABLE IF NOT EXISTS inventory_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_seq INTEGER NOT NULL,
        obj_id TEXT NOT NULL,
        action INTEGER NOT NULL,
        reason TEXT NOT NULL,
        container_id TEXT,
        wear_location TEXT,
        observed_at INTEGER NOT NULL,
        session_id TEXT NOT NULL
    )]],
    [[CREATE TABLE IF NOT EXISTS module_state_entries (
        namespace TEXT NOT NULL,
        node_id INTEGER NOT NULL,
        parent_id INTEGER,
        key_type TEXT,
        key_text TEXT,
        key_number REAL,
        key_boolean INTEGER,
        value_type TEXT NOT NULL,
        text_value TEXT,
        numeric_value REAL,
        boolean_value INTEGER,
        ordinal INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (namespace, node_id)
    )]],
    [[CREATE INDEX IF NOT EXISTS idx_items_type_name ON items(type_name, name)]],
    [[CREATE INDEX IF NOT EXISTS idx_items_location ON items(location, container_id)]],
    [[CREATE INDEX IF NOT EXISTS idx_items_identify ON items(identify_level)]],
    [[CREATE INDEX IF NOT EXISTS idx_item_stats_key_numeric ON item_stats(stat_key, numeric_value)]],
    [[CREATE INDEX IF NOT EXISTS idx_detached_root ON detached_items(detached_root)]],
    [[CREATE INDEX IF NOT EXISTS idx_pending_removed_purge ON pending_removed_items(purge_after)]],
    [[CREATE INDEX IF NOT EXISTS idx_events_obj_seq ON inventory_events(obj_id, event_seq)]],
    [[CREATE INDEX IF NOT EXISTS idx_module_state_parent
        ON module_state_entries(namespace, parent_id, ordinal)]],
}

local function now()
    return os.time()
end

local function closeCursor(cursor)
    if cursor and type(cursor.close) == "function" then
        pcall(function() cursor:close() end)
    end
end

local function execute(sql)
    if not database.conn then
        return nil, "database is not open"
    end
    local result, err = database.conn:execute(sql)
    if not result then
        return nil, tostring(err)
    end
    if type(result) == "userdata" or type(result) == "table" then
        if type(result.fetch) == "function" then
            closeCursor(result)
        end
    end
    return result
end

local function query(sql)
    if not database.conn then
        return nil, "database is not open"
    end
    return database.conn:execute(sql)
end

local function sqlQuote(value)
    if value == nil then
        return "NULL"
    end
    if type(value) == "boolean" then
        return value and "1" or "0"
    end
    if type(value) == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return "NULL"
        end
        return tostring(value)
    end
    return "'" .. tostring(value):gsub("'", "''") .. "'"
end

local function beginTransaction()
    local ok, err = execute("BEGIN IMMEDIATE")
    return ok ~= nil, err
end

local function rollback()
    if database.conn then
        pcall(function() database.conn:execute("ROLLBACK") end)
    end
end

local function commit()
    local ok, err = execute("COMMIT")
    if not ok then
        rollback()
        return false, err
    end
    return true
end

local function scalar(sql)
    local cursor, err = query(sql)
    if not cursor then
        return nil, err
    end
    if type(cursor.fetch) ~= "function" then
        closeCursor(cursor)
        return cursor
    end
    local row = cursor:fetch({}, "n")
    closeCursor(cursor)
    return row and row[1] or nil
end

local function sanitizePathPart(value)
    local sanitized = tostring(value or "Unknown"):gsub("[^%w%._%-]", "_")
    if sanitized == "" then
        return "Unknown"
    end
    return sanitized
end

local function normalizeName(value)
    local text = tostring(value or "")
    if dbot and dbot.stripColors then
        text = dbot.stripColors(text)
    end
    return text:lower():gsub(",", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
end

local function normalizeConsumableType(value)
    local typeName = tostring(value or ""):lower()
    if typeName == "drink container" then
        return "drink"
    end
    return typeName
end

local function isConsumableType(value)
    return CONSUMABLE_TYPES[normalizeConsumableType(value)] == true
end

local function templateKey(item)
    local stats = item and item.stats or {}
    local typeName = tostring(stats.type or "")
    local itemName = normalizeName(stats.name or stats.colorname or stats.colorName)
    if not isConsumableType(typeName) or itemName == "" then
        return nil
    end
    return normalizeConsumableType(typeName) .. "\31" .. itemName, typeName, itemName
end

local function fingerprintValue(value)
    local valueType = type(value)
    if valueType == "nil" then
        return "z:"
    elseif valueType == "boolean" then
        return value and "b:1" or "b:0"
    elseif valueType == "number" then
        return "n:" .. tostring(value)
    elseif valueType == "string" then
        return "s:" .. #value .. ":" .. value
    end
    return "x:" .. tostring(value)
end

local function itemFingerprint(item)
    local parts = {
        "flags=" .. fingerprintValue(item and item.flags),
        "unique=" .. fingerprintValue(item and item.unique),
        "presence=" .. fingerprintValue(item and item.__dinvPresence),
        "root=" .. fingerprintValue(item and item.__dinvDetachedRoot),
        "refresh=" .. fingerprintValue(item and item.__dinvRefreshGeneration),
        "event=" .. fingerprintValue(item and item.__dinvLastEventSeq),
        "source=" .. fingerprintValue(item and item.__dinvLocationSource),
        "session=" .. fingerprintValue(item and item.__dinvLocationSession),
        "confirmed=" .. fingerprintValue(item and item.__dinvLocationConfirmedAt),
    }
    local keys = {}
    for key, value in pairs(item and item.stats or {}) do
        if type(value) ~= "table" then
            table.insert(keys, tostring(key))
        end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        table.insert(parts, key .. "=" .. fingerprintValue(item.stats[key]))
    end
    return table.concat(parts, "\30")
end

local function copyItemWithPresence(item, presence, detachedRoot)
    local copied = {}
    for key, value in pairs(item or {}) do
        if key == "stats" and type(value) == "table" then
            copied.stats = {}
            for statKey, statValue in pairs(value) do
                copied.stats[statKey] = statValue
            end
        else
            copied[key] = value
        end
    end
    copied.stats = copied.stats or {}
    copied.__dinvPresence = presence
    copied.__dinvDetachedRoot = detachedRoot
    return copied
end

local function valueColumns(value)
    local valueType = type(value)
    if valueType == "number" then
        return "number", nil, value, nil
    elseif valueType == "boolean" then
        return "boolean", nil, nil, value and 1 or 0
    elseif valueType == "string" then
        return "string", value, nil, nil
    end
    return "string", tostring(value), nil, nil
end

local function decodeValue(row)
    if row.value_type == "number" then
        return tonumber(row.numeric_value)
    elseif row.value_type == "boolean" then
        return tonumber(row.boolean_value) == 1
    end
    return row.text_value
end

local function getMeta(key)
    return scalar("SELECT value FROM meta WHERE key=" .. sqlQuote(key) .. " LIMIT 1")
end

local function setMeta(key, value)
    return execute("INSERT OR REPLACE INTO meta(key, value) VALUES(" ..
        sqlQuote(key) .. "," .. sqlQuote(value) .. ")") ~= nil
end

local function getCharacterName()
    local name = dbot and dbot.gmcp and dbot.gmcp.getName and dbot.gmcp.getName() or nil
    name = tostring(name or "")
    if name == "" or name:lower() == "unknown" then
        return nil
    end
    return name
end

function database.getDirectory(character)
    local name = character or database.character or getCharacterName() or "Unknown"
    return getMudletHomeDir() .. "/dinv-database/" .. sanitizePathPart(name) .. "/current/"
end

function database.getCharacterDirectory(character)
    local name = character or database.character or getCharacterName() or "Unknown"
    return getMudletHomeDir() .. "/dinv-database/" .. sanitizePathPart(name) .. "/"
end

function database.getBackupDirectory(character)
    return database.getCharacterDirectory(character) .. "backup/"
end

function database.getFile(character)
    return database.getDirectory(character) .. "dinv.db"
end

function database.getSessionId()
    if not database.sessionId then
        database.sessionId = string.format("%d-%06d", now(), math.random(0, 999999))
    end
    return database.sessionId
end

function database.resetRuntimeState()
    database.pending = {
        active = { upserts = {}, deletes = {}, reattach = {}, pendingReattach = {} },
        build = { upserts = {}, deletes = {}, reattach = {}, pendingReattach = {} },
    }
    database.persistedFingerprints = { active = {}, build = {} }
    database.pendingEvents = {}
    database.sessionId = nil
end

local function ensureSchema(character)
    local txOk, txErr = beginTransaction()
    if not txOk then
        return false, txErr
    end
    for _, statement in ipairs(SCHEMA) do
        local schemaOk, schemaErr = execute(statement)
        if not schemaOk then
            rollback()
            return false, "schema creation failed: " .. tostring(schemaErr)
        end
    end
    if not setMeta("schema_version", tostring(database.schemaVersion))
        or not setMeta("character_name", character) then
        rollback()
        return false, "unable to persist database schema metadata"
    end
    return commit()
end

function database.open()
    local character = getCharacterName()
    if not character then
        return false, "character name is not available yet"
    end

    if database.isOpen then
        if tostring(database.character or ""):lower() == tostring(character):lower() then
            return ensureSchema(character)
        end

        -- A Mudlet profile can reconnect as another character without reloading
        -- the package. Never allow the old character's connection or pending
        -- batches to become the new character's persistence target.
        local activeOk, activeErr = database.flush("active")
        if not activeOk then
            return false, "unable to flush previous character before switch: " .. tostring(activeErr)
        end
        local buildOk, buildErr = database.flush("build")
        if not buildOk then
            return false, "unable to flush previous build before switch: " .. tostring(buildErr)
        end
        database.close()
        database.resetRuntimeState()
    end

    local okLfs, lfsModule = pcall(require, "lfs")
    if okLfs and not lfs then
        lfs = lfsModule
    end
    database.character = character
    database.file = database.getFile(character)
    if dbot and dbot.ensureDirectory then
        dbot.ensureDirectory(database.getDirectory(character))
    end

    local okDriver, driver = pcall(require, "luasql.sqlite3")
    if not okDriver or not driver then
        return false, "LuaSQL SQLite is unavailable: " .. tostring(driver)
    end

    database.env = driver.sqlite3()
    if not database.env then
        return false, "unable to create LuaSQL SQLite environment"
    end

    local err
    database.conn, err = database.env:connect(database.file)
    if not database.conn then
        database.env:close()
        database.env = nil
        return false, "unable to open " .. database.file .. ": " .. tostring(err)
    end

    database.isOpen = true
    database.getSessionId()
    execute("PRAGMA foreign_keys = ON")
    execute("PRAGMA journal_mode = WAL")
    execute("PRAGMA synchronous = NORMAL")
    execute("PRAGMA busy_timeout = 5000")

    local schemaOk, schemaErr = ensureSchema(character)
    if not schemaOk then
        database.close()
        return false, schemaErr
    end

    return true
end

function database.close()
    if database.conn then
        pcall(function() database.conn:close() end)
    end
    if database.env then
        pcall(function() database.env:close() end)
    end
    database.conn = nil
    database.env = nil
    database.isOpen = false
    database.file = nil
    database.character = nil
    database.sessionId = nil
end

local function strictLoadLegacyValue(fileName, valuePath)
    local file = io.open(fileName, "rb")
    if not file then
        return nil, "file not found"
    end
    local content = file:read("*a")
    file:close()
    if not content or content == "" then
        return nil, "file is empty"
    end

    local env = { inv = {}, dbot = {}, DINV = {} }
    local pathParent = env
    for index = 1, #valuePath - 1 do
        local pathPart = valuePath[index]
        pathParent[pathPart] = pathParent[pathPart] or {}
        pathParent = pathParent[pathPart]
    end
    local chunk, err
    if loadstring and setfenv then
        chunk, err = loadstring(content, "@" .. fileName)
        if not chunk and content:find("= return", 1, true) then
            chunk, err = loadstring(content:gsub("= return%s+", "= "), "@" .. fileName)
        end
        if chunk then
            setfenv(chunk, env)
        end
    else
        chunk, err = load(content, "@" .. fileName, "t", env)
    end
    if not chunk then
        return nil, err
    end
    local ok, runtimeErr = pcall(chunk)
    if not ok then
        return nil, runtimeErr
    end
    local value = env
    for _, pathPart in ipairs(valuePath) do
        value = type(value) == "table" and value[pathPart] or nil
    end
    if type(value) ~= "table" then
        return nil, "legacy file did not define " .. table.concat(valuePath, ".")
    end
    return value
end

local function strictLoadLegacyTable(fileName)
    return strictLoadLegacyValue(fileName, { "inv", "items", "table" })
end

local function legacyCandidates(fileName)
    fileName = tostring(fileName or "inv-items.state")
    local home = getMudletHomeDir()
    local character = database.character or getCharacterName() or "Unknown"
    local candidates = {
        home .. "/dinv-unknown/" .. character .. "/current/" .. fileName,
    }
    if pluginId and tostring(pluginId) ~= "" then
        table.insert(candidates, home .. "/dinv-" .. tostring(pluginId) .. "/" .. character ..
            "/current/" .. fileName)
    end
    if dbot and dbot.backup and dbot.backup.getCurrentDir then
        local current = dbot.backup.getCurrentDir()
        table.insert(candidates, tostring(current) .. fileName)
    end

    local unique = {}
    local result = {}
    for _, candidate in ipairs(candidates) do
        local normalized = tostring(candidate):gsub("\\", "/")
        if not unique[normalized] then
            unique[normalized] = true
            table.insert(result, candidate)
        end
    end
    return result
end

local function sortedStateKeys(value)
    local keys = {}
    for key, _ in pairs(value or {}) do
        local keyType = type(key)
        if keyType ~= "string" and keyType ~= "number" and keyType ~= "boolean" then
            return nil, "unsupported table key type: " .. keyType
        end
        table.insert(keys, key)
    end
    local rank = { number = 1, string = 2, boolean = 3 }
    table.sort(keys, function(left, right)
        local leftType, rightType = type(left), type(right)
        if leftType ~= rightType then
            return rank[leftType] < rank[rightType]
        end
        if leftType == "number" then
            return left < right
        elseif leftType == "boolean" then
            return left == false and right == true
        end
        return tostring(left) < tostring(right)
    end)
    return keys
end

local function flattenModuleState(rootValue)
    local nodes = {}
    local visiting = {}

    local function appendNode(value, parentId, key, ordinal)
        local valueType = type(value)
        if valueType ~= "table" and valueType ~= "string" and valueType ~= "number"
            and valueType ~= "boolean" then
            return nil, "unsupported persisted value type: " .. valueType
        end
        if valueType == "number"
            and (value ~= value or value == math.huge or value == -math.huge) then
            return nil, "non-finite numbers cannot be persisted"
        end
        if valueType == "table" and visiting[value] then
            return nil, "cyclic tables cannot be persisted"
        end

        local keyType = key ~= nil and type(key) or nil
        local node = {
            nodeId = #nodes + 1,
            parentId = parentId,
            keyType = keyType,
            keyText = keyType == "string" and key or nil,
            keyNumber = keyType == "number" and key or nil,
            keyBoolean = keyType == "boolean" and (key and 1 or 0) or nil,
            valueType = valueType,
            textValue = valueType == "string" and value or nil,
            numericValue = valueType == "number" and value or nil,
            booleanValue = valueType == "boolean" and (value and 1 or 0) or nil,
            ordinal = ordinal or 0,
        }
        table.insert(nodes, node)

        if valueType == "table" then
            visiting[value] = true
            local keys, keysErr = sortedStateKeys(value)
            if not keys then
                visiting[value] = nil
                return nil, keysErr
            end
            for childOrdinal, childKey in ipairs(keys) do
                local _, childErr = appendNode(value[childKey], node.nodeId, childKey, childOrdinal)
                if childErr then
                    visiting[value] = nil
                    return nil, childErr
                end
            end
            visiting[value] = nil
        end
        return node.nodeId
    end

    local _, err = appendNode(rootValue, nil, nil, 0)
    if err then
        return nil, err
    end
    return nodes
end

local MODULE_STATE_COLUMNS = table.concat({
    "namespace", "node_id", "parent_id", "key_type", "key_text", "key_number",
    "key_boolean", "value_type", "text_value", "numeric_value", "boolean_value",
    "ordinal", "updated_at",
}, ",")

local function insertModuleStateNodes(namespace, nodes)
    local insertedAt = now()
    local values = {}
    local function flushValues()
        if #values == 0 then
            return true
        end
        local ok, err = execute("INSERT INTO module_state_entries(" .. MODULE_STATE_COLUMNS ..
            ") VALUES " .. table.concat(values, ","))
        values = {}
        return ok ~= nil, err
    end

    for _, node in ipairs(nodes or {}) do
        table.insert(values, "(" .. table.concat({
            sqlQuote(namespace), sqlQuote(node.nodeId), sqlQuote(node.parentId),
            sqlQuote(node.keyType), sqlQuote(node.keyText), sqlQuote(node.keyNumber),
            sqlQuote(node.keyBoolean), sqlQuote(node.valueType), sqlQuote(node.textValue),
            sqlQuote(node.numericValue), sqlQuote(node.booleanValue), sqlQuote(node.ordinal),
            sqlQuote(insertedAt),
        }, ",") .. ")")
        if #values >= 100 then
            local ok, err = flushValues()
            if not ok then
                return false, err
            end
        end
    end
    return flushValues()
end

local function replaceModuleStateInTransaction(namespace, value)
    local nodes, flattenErr = flattenModuleState(value)
    if not nodes then
        return false, flattenErr
    end
    local deleted, deleteErr = execute("DELETE FROM module_state_entries WHERE namespace=" ..
        sqlQuote(namespace))
    if not deleted then
        return false, deleteErr
    end
    return insertModuleStateNodes(namespace, nodes)
end

local function decodeStateKey(row)
    if row.key_type == "number" then
        return tonumber(row.key_number)
    elseif row.key_type == "boolean" then
        return tonumber(row.key_boolean) == 1
    end
    return row.key_text
end

local function decodeStateValue(row)
    if row.value_type == "table" then
        return {}
    elseif row.value_type == "number" then
        return tonumber(row.numeric_value)
    elseif row.value_type == "boolean" then
        return tonumber(row.boolean_value) == 1
    end
    return row.text_value
end

local function loadModuleStateDirect(namespace)
    local cursor, err = query("SELECT node_id,parent_id,key_type,key_text,key_number,key_boolean," ..
        "value_type,text_value,numeric_value,boolean_value,ordinal FROM module_state_entries " ..
        "WHERE namespace=" .. sqlQuote(namespace) .. " ORDER BY node_id")
    if not cursor then
        return nil, err
    end
    local valuesById = {}
    local rootValue = nil
    local found = false
    local row = cursor:fetch({}, "a")
    while row do
        found = true
        local nodeId = tonumber(row.node_id)
        local value = decodeStateValue(row)
        valuesById[nodeId] = value
        local parentId = tonumber(row.parent_id)
        if parentId then
            local parent = valuesById[parentId]
            if type(parent) ~= "table" then
                closeCursor(cursor)
                return nil, "invalid module state parent for namespace " .. tostring(namespace)
            end
            parent[decodeStateKey(row)] = value
        else
            rootValue = value
        end
        row = cursor:fetch(row, "a")
    end
    closeCursor(cursor)
    if not found then
        return nil, "not found"
    end
    return rootValue
end

local function itemColumns(objId, item)
    local stats = item and item.stats or {}
    local presence = item and item.__dinvPresence or stats.__dinvPresence or "active"
    return {
        obj_id = tostring(objId),
        name = stats.name,
        color_name = stats.colorname or stats.colorName,
        type_name = stats.type,
        type_num = tonumber(stats.typeNum),
        level = tonumber(stats.level),
        identify_level = stats.identifyLevel,
        protocol_flags = item and item.flags,
        unique_value = item and item.unique,
        location = stats.location,
        container_id = stats.container,
        last_stored = stats.lastStored,
        worn = stats.worn,
        wearable = stats.wearable,
        keep_flag = stats.keepflag,
        timer = tonumber(stats.timer),
        presence = presence,
        detached_root = item and item.__dinvDetachedRoot or stats.__dinvDetachedRoot,
        refresh_generation = tonumber(item and item.__dinvRefreshGeneration or stats.__dinvRefreshGeneration) or 0,
        last_event_seq = tonumber(item and item.__dinvLastEventSeq or stats.__dinvLastEventSeq) or 0,
        location_source = item and item.__dinvLocationSource or stats.__dinvLocationSource,
        location_session = item and item.__dinvLocationSession or stats.__dinvLocationSession,
        location_confirmed_at = tonumber(item and item.__dinvLocationConfirmedAt or stats.__dinvLocationConfirmedAt),
        updated_at = now(),
    }
end

local ITEM_COLUMN_ORDER = {
    "obj_id", "name", "color_name", "type_name", "type_num", "level", "identify_level",
    "protocol_flags", "unique_value", "location", "container_id", "last_stored", "worn",
    "wearable", "keep_flag", "timer", "presence", "detached_root", "refresh_generation",
    "last_event_seq", "location_source", "location_session", "location_confirmed_at", "updated_at",
}

local function insertItem(tableName, statsTableName, objId, item)
    local columns = itemColumns(objId, item)
    local values = {}
    for _, key in ipairs(ITEM_COLUMN_ORDER) do
        table.insert(values, sqlQuote(columns[key]))
    end
    local sql = "INSERT OR REPLACE INTO " .. tableName .. "(" .. table.concat(ITEM_COLUMN_ORDER, ",") ..
        ") VALUES(" .. table.concat(values, ",") .. ")"
    local ok, err = execute(sql)
    if not ok then
        return false, err
    end

    local statsOk, statsErr = execute("DELETE FROM " .. statsTableName .. " WHERE obj_id=" .. sqlQuote(objId))
    if not statsOk then
        return false, statsErr
    end
    for key, value in pairs(item and item.stats or {}) do
        if value ~= nil and type(value) ~= "table" and not CORE_FIELDS[tostring(key)] then
            local valueType, textValue, numericValue, booleanValue = valueColumns(value)
            local statSql = "INSERT INTO " .. statsTableName ..
                "(obj_id,stat_key,value_type,text_value,numeric_value,boolean_value) VALUES(" ..
                table.concat({
                    sqlQuote(objId), sqlQuote(key), sqlQuote(valueType), sqlQuote(textValue),
                    sqlQuote(numericValue), sqlQuote(booleanValue),
                }, ",") .. ")"
            local statOk, statErr = execute(statSql)
            if not statOk then
                return false, statErr
            end
        end
    end
    return true
end

local function saveConsumableTemplate(objId, item)
    local key, typeName, itemName = templateKey(item)
    local stats = item and item.stats or {}
    if not key or stats.identifyLevel ~= "full" then
        return true
    end

    local ok, err = execute("INSERT OR REPLACE INTO consumable_templates(" ..
        "template_key,type_name,item_name,identify_level,source_obj_id,updated_at) VALUES(" ..
        table.concat({
            sqlQuote(key), sqlQuote(typeName), sqlQuote(itemName), sqlQuote("full"),
            sqlQuote(objId), sqlQuote(now()),
        }, ",") .. ")")
    if not ok then
        return false, err
    end
    ok, err = execute("DELETE FROM consumable_template_stats WHERE template_key=" .. sqlQuote(key))
    if not ok then
        return false, err
    end
    for statKey, value in pairs(stats) do
        if value ~= nil and type(value) ~= "table" and not DYNAMIC_TEMPLATE_FIELDS[statKey] then
            local valueType, textValue, numericValue, booleanValue = valueColumns(value)
            local statOk, statErr = execute("INSERT INTO consumable_template_stats(" ..
                "template_key,stat_key,value_type,text_value,numeric_value,boolean_value) VALUES(" ..
                table.concat({
                    sqlQuote(key), sqlQuote(statKey), sqlQuote(valueType), sqlQuote(textValue),
                    sqlQuote(numericValue), sqlQuote(booleanValue),
                }, ",") .. ")")
            if not statOk then
                return false, statErr
            end
        end
    end
    local limit = tonumber(inv and inv.cache and inv.cache.table and inv.cache.table.frequentSize) or 200
    limit = math.max(0, math.floor(limit))
    local pruneOk, pruneErr = execute("DELETE FROM consumable_templates WHERE template_key IN (" ..
        "SELECT template_key FROM consumable_templates ORDER BY updated_at DESC,template_key DESC " ..
        "LIMIT -1 OFFSET " .. tostring(limit) .. ")")
    if not pruneOk then return false, pruneErr end
    return true
end

local function loadTableItems(tableName, statsTableName, requestedObjId)
    local result = {}
    local itemWhere = requestedObjId ~= nil and
        (" WHERE obj_id=" .. sqlQuote(tostring(requestedObjId))) or ""
    local cursor, err = query("SELECT * FROM " .. tableName .. itemWhere .. " ORDER BY obj_id")
    if not cursor then
        return nil, err
    end
    local row = cursor:fetch({}, "a")
    while row do
        local objId = tostring(row.obj_id)
        local item = {
            stats = {
                id = objId,
                name = row.name,
                colorname = row.color_name,
                type = row.type_name,
                typeNum = tonumber(row.type_num),
                level = tonumber(row.level),
                identifyLevel = row.identify_level,
                location = row.location,
                container = row.container_id,
                lastStored = row.last_stored,
                worn = row.worn,
                wearable = row.wearable,
                timer = tonumber(row.timer),
            },
            flags = row.protocol_flags,
            unique = tonumber(row.unique_value) or row.unique_value,
            __dinvPresence = row.presence or "active",
            __dinvDetachedRoot = row.detached_root,
            __dinvRefreshGeneration = tonumber(row.refresh_generation) or 0,
            __dinvLastEventSeq = tonumber(row.last_event_seq) or 0,
            __dinvLocationSource = row.location_source,
            __dinvLocationSession = row.location_session,
            __dinvLocationConfirmedAt = tonumber(row.location_confirmed_at),
        }
        if row.keep_flag ~= nil then
            item.stats.keepflag = tonumber(row.keep_flag) == 1
        end
        result[objId] = item
        row = cursor:fetch(row, "a")
    end
    closeCursor(cursor)

    local statsWhere = requestedObjId ~= nil and
        (" WHERE obj_id=" .. sqlQuote(tostring(requestedObjId))) or ""
    cursor, err = query("SELECT obj_id,stat_key,value_type,text_value,numeric_value,boolean_value FROM " ..
        statsTableName .. statsWhere .. " ORDER BY obj_id,stat_key")
    if not cursor then
        return nil, err
    end
    row = cursor:fetch({}, "a")
    while row do
        local item = result[tostring(row.obj_id)]
        if item then
            item.stats[row.stat_key] = decodeValue(row)
        end
        row = cursor:fetch(row, "a")
    end
    closeCursor(cursor)
    return result
end

local function rememberFingerprints(target, items)
    local fingerprints = {}
    for objId, item in pairs(items or {}) do
        fingerprints[tostring(objId)] = itemFingerprint(item)
    end
    database.persistedFingerprints[target] = fingerprints
end

function database.loadActiveItems()
    if not database.isOpen then
        local ok, err = database.open()
        if not ok then
            return nil, err
        end
    end
    local items, err = loadTableItems("items", "item_stats")
    if items then
        rememberFingerprints("active", items)
    end
    return items, err
end

function database.loadActiveItem(objId)
    if not database.isOpen then
        local ok, err = database.open()
        if not ok then return nil, err end
    end
    local items, err = loadTableItems("items", "item_stats", objId)
    if not items then return nil, err end
    return items[tostring(objId)]
end

function database.loadDetachedItems()
    if not database.isOpen then
        local ok, err = database.open()
        if not ok then
            return nil, err
        end
    end
    return loadTableItems("detached_items", "detached_item_stats")
end

function database.loadPendingRemovedItems()
    if not database.isOpen then
        local ok, err = database.open()
        if not ok then
            return nil, err
        end
    end

    local items, err = loadTableItems("pending_removed_items", "pending_removed_item_stats")
    if not items then
        return nil, err
    end

    local cursor, queryErr = query("SELECT obj_id,removed_at,purge_after,removal_action,removal_reason " ..
        "FROM pending_removed_items ORDER BY obj_id")
    if not cursor then
        return nil, queryErr
    end
    local row = cursor:fetch({}, "a")
    while row do
        local item = items[tostring(row.obj_id)]
        if item then
            item.__dinvPresence = "pending-removal"
            item.__dinvDetachedRoot = nil
            item.__dinvRemovedAt = tonumber(row.removed_at) or 0
            item.__dinvPurgeAfter = tonumber(row.purge_after) or 0
            item.__dinvRemovalAction = tonumber(row.removal_action)
            item.__dinvRemovalReason = row.removal_reason
        end
        row = cursor:fetch(row, "a")
    end
    closeCursor(cursor)
    return items
end

function database.loadStagedItem(objId)
    local all, err = loadTableItems("build_items", "build_item_stats", objId)
    if not all then
        return nil, err
    end
    return all[tostring(objId)]
end


function database.loadStagedItems()
    local items, err = loadTableItems("build_items", "build_item_stats")
    if items then
        rememberFingerprints("build", items)
    end
    return items, err
end

function database.loadConsumableTemplate(item)
    local key = templateKey(item)
    if not key then
        return nil
    end
    local identifyLevel = scalar("SELECT identify_level FROM consumable_templates WHERE template_key=" ..
        sqlQuote(key) .. " LIMIT 1")
    if identifyLevel ~= "full" then
        return nil
    end
    local template = { stats = { identifyLevel = "full" } }
    local cursor, err = query("SELECT stat_key,value_type,text_value,numeric_value,boolean_value " ..
        "FROM consumable_template_stats WHERE template_key=" .. sqlQuote(key))
    if not cursor then
        return nil, err
    end
    local row = cursor:fetch({}, "a")
    while row do
        template.stats[row.stat_key] = decodeValue(row)
        row = cursor:fetch(row, "a")
    end
    closeCursor(cursor)
    execute("UPDATE consumable_templates SET updated_at=" .. sqlQuote(now()) ..
        " WHERE template_key=" .. sqlQuote(key))
    return template
end

function database.listConsumableTemplates()
    if not database.isOpen then
        local initialized, initErr = database.initialize()
        if not initialized then
            return nil, initErr
        end
    end
    local templates = {}
    local byKey = {}
    local cursor, err = query("SELECT template_key,type_name,item_name,identify_level " ..
        "FROM consumable_templates WHERE identify_level='full' ORDER BY type_name,item_name")
    if not cursor then
        return nil, err
    end
    local row = cursor:fetch({}, "a")
    while row do
        local template = {
            templateKey = row.template_key,
            stats = {
                type = row.type_name,
                name = row.item_name,
                identifyLevel = row.identify_level,
            },
        }
        byKey[row.template_key] = template
        table.insert(templates, template)
        row = cursor:fetch(row, "a")
    end
    closeCursor(cursor)

    cursor, err = query("SELECT template_key,stat_key,value_type,text_value,numeric_value,boolean_value " ..
        "FROM consumable_template_stats ORDER BY template_key,stat_key")
    if not cursor then
        return nil, err
    end
    row = cursor:fetch({}, "a")
    while row do
        local template = byKey[row.template_key]
        if template then
            template.stats[row.stat_key] = decodeValue(row)
        end
        row = cursor:fetch(row, "a")
    end
    closeCursor(cursor)
    return templates
end


function database.clearConsumableTemplates()
    local txOk, txErr = beginTransaction()
    if not txOk then
        return false, txErr
    end
    local ok, err = execute("DELETE FROM consumable_template_stats")
    if ok then ok, err = execute("DELETE FROM consumable_templates") end
    if not ok then
        rollback()
        return false, err
    end
    return commit()
end

function database.enforceConsumableTemplateLimit(limit)
    local maximum = math.max(0, math.floor(tonumber(limit) or 0))
    local ok, err = execute("DELETE FROM consumable_templates WHERE template_key IN (" ..
        "SELECT template_key FROM consumable_templates ORDER BY updated_at DESC,template_key DESC " ..
        "LIMIT -1 OFFSET " .. tostring(maximum) .. ")")
    return ok ~= nil, err
end

local function pendingBucket(target)
    target = target == "build" and "build" or "active"
    database.pending[target] = database.pending[target]
        or { upserts = {}, deletes = {}, reattach = {}, pendingReattach = {} }
    database.pending[target].reattach = database.pending[target].reattach or {}
    database.pending[target].pendingReattach = database.pending[target].pendingReattach or {}
    return database.pending[target], target
end

function database.markItem(objId, item, target)
    local bucket = pendingBucket(target)
    local key = tostring(objId)
    bucket.deletes[key] = nil
    bucket.upserts[key] = item
end

function database.markDeleted(objId, target)
    local bucket = pendingBucket(target)
    local key = tostring(objId)
    bucket.upserts[key] = nil
    bucket.deletes[key] = true
end


function database.markReattached(objId, item, target)
    local bucket, normalizedTarget = pendingBucket(target)
    local key = tostring(objId)
    bucket.deletes[key] = nil
    bucket.upserts[key] = item
    -- A staged build must leave the detached copy intact until the build is
    -- activated. finishBuild removes every detached row represented by the
    -- completed build in the same activation transaction.
    if normalizedTarget == "active" then
        bucket.reattach[key] = true
    end
end

function database.markPendingReattached(objId, item, target)
    local bucket, normalizedTarget = pendingBucket(target)
    local key = tostring(objId)
    bucket.deletes[key] = nil
    bucket.upserts[key] = item
    -- A staged build must preserve the pending snapshot until activation, just
    -- like detached subtrees. finishBuild removes pending rows represented by
    -- the completed build in the same activation transaction.
    if normalizedTarget == "active" then
        bucket.pendingReattach[key] = true
    end
end


function database.discardPending(target)
    local _, normalizedTarget = pendingBucket(target)
    database.pending[normalizedTarget] = {
        upserts = {}, deletes = {}, reattach = {}, pendingReattach = {},
    }
end


function database.syncItems(items, target, options)
    local _, normalizedTarget = pendingBucket(target)
    local fingerprints = database.persistedFingerprints[normalizedTarget] or {}
    local seen = {}
    for objId, item in pairs(items or {}) do
        local key = tostring(objId)
        seen[key] = true
        local currentFingerprint = itemFingerprint(item)
        if fingerprints[key] ~= currentFingerprint then
            database.markItem(key, item, normalizedTarget)
        end
    end
    for objId, _ in pairs(fingerprints) do
        if not seen[objId] then
            database.markDeleted(objId, normalizedTarget)
        end
    end
    return database.flush(normalizedTarget, options)
end

local function inventoryEventSql(event)
    return "INSERT INTO inventory_events(event_seq,obj_id,action,reason,container_id," ..
        "wear_location,observed_at,session_id) VALUES(" .. table.concat({
            sqlQuote(event.eventSeq), sqlQuote(event.objId), sqlQuote(event.action),
            sqlQuote(event.reason), sqlQuote(event.containerId), sqlQuote(event.wearLocation),
            sqlQuote(event.observedAt), sqlQuote(event.sessionId),
        }, ",") .. ")"
end

function database.flush(target, options)
    if not database.isOpen then
        local opened, openErr = database.open()
        if not opened then
            return false, openErr
        end
    end
    local bucket, normalizedTarget = pendingBucket(target)
    local purgeCutoff = type(options) == "table"
        and tonumber(options.pendingRemovalPurgeCutoff) or nil
    if not next(bucket.upserts) and not next(bucket.deletes)
        and not next(bucket.reattach) and not next(bucket.pendingReattach)
        and #database.pendingEvents == 0 and not purgeCutoff then
        return true, 0, {}
    end

    local tableName = normalizedTarget == "build" and "build_items" or "items"
    local statsTableName = normalizedTarget == "build" and "build_item_stats" or "item_stats"
    local txOk, txErr = beginTransaction()
    if not txOk then
        return false, txErr
    end

    local count = 0
    for objId, _ in pairs(bucket.deletes) do
        local ok, err = execute("DELETE FROM " .. tableName .. " WHERE obj_id=" .. sqlQuote(objId))
        if not ok then
            rollback()
            return false, err
        end
        count = count + 1
    end
    for objId, item in pairs(bucket.upserts) do
        local ok, err = insertItem(tableName, statsTableName, objId, item)
        if not ok then
            rollback()
            return false, err
        end
        if normalizedTarget == "active" then
            local templateOk, templateErr = saveConsumableTemplate(objId, item)
            if not templateOk then
                rollback()
                return false, templateErr
            end
        end
        count = count + 1
    end
    if normalizedTarget == "active" then
        for objId, _ in pairs(bucket.reattach) do
            local ok, err = execute("DELETE FROM detached_items WHERE obj_id=" .. sqlQuote(objId))
            if not ok then
                rollback()
                return false, err
            end
        end
    end
    for objId, _ in pairs(bucket.pendingReattach) do
        local ok, err = execute("DELETE FROM pending_removed_items WHERE obj_id=" .. sqlQuote(objId))
        if not ok then
            rollback()
            return false, err
        end
    end

    local purgedPendingIds = {}
    if normalizedTarget == "active" and purgeCutoff then
        local cursor, queryErr = query("SELECT obj_id FROM pending_removed_items " ..
            "WHERE purge_after <= " .. sqlQuote(purgeCutoff) ..
            " AND NOT EXISTS (SELECT 1 FROM items WHERE items.obj_id=pending_removed_items.obj_id) " ..
            "ORDER BY obj_id")
        if not cursor then
            rollback()
            return false, queryErr
        end
        local row = cursor:fetch({}, "a")
        while row do
            table.insert(purgedPendingIds, tostring(row.obj_id))
            row = cursor:fetch(row, "a")
        end
        closeCursor(cursor)

        local purgeOk, purgeErr = execute("DELETE FROM pending_removed_items " ..
            "WHERE purge_after <= " .. sqlQuote(purgeCutoff) ..
            " AND NOT EXISTS (SELECT 1 FROM items WHERE items.obj_id=pending_removed_items.obj_id)")
        if not purgeOk then
            rollback()
            return false, purgeErr
        end
    end
    for _, event in ipairs(database.pendingEvents) do
        local eventOk, eventErr = execute(inventoryEventSql(event))
        if not eventOk then
            rollback()
            return false, eventErr
        end
    end

    local committed, commitErr = commit()
    if not committed then
        return false, commitErr
    end
    local fingerprints = database.persistedFingerprints[normalizedTarget] or {}
    for objId, _ in pairs(bucket.deletes) do
        fingerprints[objId] = nil
    end
    for objId, item in pairs(bucket.upserts) do
        fingerprints[objId] = itemFingerprint(item)
    end
    database.persistedFingerprints[normalizedTarget] = fingerprints
    bucket.upserts = {}
    bucket.deletes = {}
    bucket.reattach = {}
    bucket.pendingReattach = {}
    database.pendingEvents = {}
    return true, count, purgedPendingIds
end

local function importLegacyItems(items, sourcePath)
    local txOk, txErr = beginTransaction()
    if not txOk then
        return false, txErr
    end
    local imported = 0
    for objId, item in pairs(items or {}) do
        local stats = item and item.stats or {}
        local loc = tostring(stats[invStatFieldLocation] or "")
        local wornLoc = tostring(stats[invStatFieldWorn] or "")
        if loc == tostring(invItemLocWorn or "worn")
            and wornLoc ~= "" and wornLoc ~= "undefined"
            and wornLoc ~= tostring(invItemWornNotWorn or "not-worn") then
            local wearNum = inv and inv.wearLocId and inv.wearLocId[wornLoc]
            if wearNum ~= nil then
                stats[invStatFieldLocation] = tostring(wearNum)
                loc = tostring(wearNum)
            end
        end
        local isStorage = inv and inv.items and inv.items.isStorageLocation
        local lastStored = tostring(stats[invStatFieldLastStored] or "")
        if lastStored ~= "" and isStorage and not inv.items.isStorageLocation(lastStored) then
            stats[invStatFieldLastStored] = ""
        end
        if loc ~= "" and isStorage and inv.items.isStorageLocation(loc) then
            stats[invStatFieldLastStored] = loc
        end
        if tostring(stats[invStatFieldLastStored] or "") == tostring(invItemLocKeyring or "keyring")
            and tostring(stats[invStatFieldLocation] or "") == "unknown" then
            stats[invStatFieldLocation] = invItemLocKeyring or "keyring"
            stats[invStatFieldContainer] = invItemLocKeyring or "keyring"
        end
        local ok, err = insertItem("items", "item_stats", tostring(objId), item)
        if not ok then
            rollback()
            return false, err
        end
        local templateOk, templateErr = saveConsumableTemplate(tostring(objId), item)
        if not templateOk then
            rollback()
            return false, templateErr
        end
        imported = imported + 1
    end
    local metadataSaved = setMeta("legacy_items_source", sourcePath)
        and setMeta("legacy_items_imported_at", tostring(now()))
        and setMeta("legacy_items_imported_count", tostring(imported))
        and setMeta("legacy_items_migration_v1", "imported")
    if not metadataSaved then
        rollback()
        return false, "unable to persist legacy item migration metadata"
    end
    local committed, commitErr = commit()
    if not committed then
        return false, commitErr
    end
    return true, imported
end

function database.migrateLegacyItemsOnce()
    if getMeta("legacy_items_migration_v1") then
        return true, "already migrated"
    end

    local existingCount = tonumber(scalar("SELECT COUNT(*) FROM items")) or 0
    if existingCount > 0 then
        if not setMeta("legacy_items_migration_v1", "database already populated") then
            return false, "unable to persist legacy item migration marker"
        end
        return true, "database already populated"
    end

    for _, candidate in ipairs(legacyCandidates()) do
        local file = io.open(candidate, "rb")
        if file then
            file:close()
            local items, loadErr = strictLoadLegacyTable(candidate)
            if not items then
                return false, "legacy import failed for " .. candidate .. ": " .. tostring(loadErr)
            end
            return importLegacyItems(items, candidate)
        end
    end

    if not setMeta("legacy_items_imported_at", tostring(now()))
        or not setMeta("legacy_items_migration_v1", "new install") then
        return false, "unable to persist new-install migration marker"
    end
    return true, "new install"
end

local function moduleMigrationMarker(namespace)
    return "legacy_module_" .. tostring(namespace) .. "_migration_v1"
end

function database.migrateLegacyModuleOnce(definition)
    local namespace = definition and definition.namespace
    if not namespace then
        return false, "missing legacy module namespace"
    end
    local marker = moduleMigrationMarker(namespace)
    if getMeta(marker) then
        return true, "already migrated"
    end

    local existing = tonumber(scalar("SELECT COUNT(*) FROM module_state_entries WHERE namespace=" ..
        sqlQuote(namespace))) or 0
    if existing > 0 then
        if not setMeta(marker, "database already populated") then
            return false, "unable to persist module migration marker for " .. tostring(namespace)
        end
        return true, "database already populated"
    end

    for _, candidate in ipairs(legacyCandidates(definition.file)) do
        local file = io.open(candidate, "rb")
        if file then
            file:close()
            local value, loadErr = strictLoadLegacyValue(candidate, definition.path)
            if not value then
                return false, "legacy import failed for " .. candidate .. ": " .. tostring(loadErr),
                    "legacy_parse"
            end
            local txOk, txErr = beginTransaction()
            if not txOk then
                return false, txErr
            end
            local saved, saveErr = replaceModuleStateInTransaction(namespace, value)
            if not saved then
                rollback()
                return false, saveErr
            end
            local metadataSaved = setMeta(marker .. "_source", candidate)
                and setMeta(marker .. "_at", tostring(now()))
                and setMeta(marker, "imported")
            if not metadataSaved then
                rollback()
                return false, "unable to persist module migration metadata for " .. tostring(namespace)
            end
            local committed, commitErr = commit()
            if not committed then
                return false, commitErr
            end
            return true, "imported"
        end
    end

    if not setMeta(marker .. "_at", tostring(now()))
        or not setMeta(marker, "new install") then
        return false, "unable to persist new-install module marker for " .. tostring(namespace)
    end
    return true, "new install"
end

function database.migrateAllLegacyModulesOnce()
    local failures = {}
    for _, definition in ipairs(LEGACY_MODULES) do
        local ok, result, failureKind = database.migrateLegacyModuleOnce(definition)
        if not ok then
            if failureKind ~= "legacy_parse" then
                return false, result
            end
            local marker = moduleMigrationMarker(definition.namespace)
            if not setMeta(marker .. "_error", tostring(result))
                or not setMeta(marker .. "_at", tostring(now()))
                or not setMeta(marker, "failed; defaults will be used") then
                return false, "unable to persist failed migration marker for " ..
                    tostring(definition.namespace)
            end
            table.insert(failures, definition.file .. ": " .. tostring(result))
            if dbot and dbot.warn then
                dbot.warn("Legacy state '" .. tostring(definition.file) ..
                    "' could not be imported; DINV will use defaults for that module. " .. tostring(result))
            end
        end
    end
    return true, failures
end

function database.repairPrimaryDataOnce()
    local marker = "primary_data_repairs_v3"
    if getMeta(marker) then
        return true, 0
    end

    local txOk, txErr = beginTransaction()
    if not txOk then
        return false, txErr
    end

    -- Core fields already have typed columns on each item row. Older v2
    -- databases also duplicated them in the dynamic stat tables, which made
    -- inspection noisy and needlessly multiplied rows.
    local coreKeys = {}
    for key, _ in pairs(CORE_FIELDS) do
        table.insert(coreKeys, sqlQuote(key))
    end
    table.sort(coreKeys)
    local coreList = table.concat(coreKeys, ",")
    for _, tableName in ipairs({ "item_stats", "detached_item_stats", "build_item_stats" }) do
        local cleaned, cleanErr = execute(
            "DELETE FROM " .. tableName .. " WHERE stat_key IN (" .. coreList .. ")"
        )
        if not cleaned then
            rollback()
            return false, cleanErr
        end
    end

    if not setMeta(marker, tostring(now())) then
        rollback()
        return false, "unable to persist primary data repair marker"
    end
    local committed, commitErr = commit()
    if not committed then
        return false, commitErr
    end
    return true, 0
end

function database.restoreLegacyStateDirectory(directory)
    if not database.isOpen then
        local initialized, initErr = database.initialize()
        if not initialized then
            return false, initErr
        end
    end

    local root = tostring(directory or ""):gsub("\\", "/")
    if root == "" then
        return false, "legacy backup directory is required"
    end
    if root:sub(-1) ~= "/" then root = root .. "/" end

    local items, itemsErr = strictLoadLegacyTable(root .. "inv-items.state")
    if not items then
        return false, "invalid legacy inv-items.state: " .. tostring(itemsErr)
    end

    -- Parse every available file before changing the current database.
    local moduleValues = {}
    for _, definition in ipairs(LEGACY_MODULES) do
        local path = root .. definition.file
        local file = io.open(path, "rb")
        if file then
            file:close()
            local value, loadErr = strictLoadLegacyValue(path, definition.path)
            if not value then
                return false, "invalid legacy " .. definition.file .. ": " .. tostring(loadErr)
            end
            moduleValues[definition.namespace] = value
        end
    end

    local txOk, txErr = beginTransaction()
    if not txOk then return false, txErr end
    local clears = {
        "DELETE FROM item_stats", "DELETE FROM items",
        "DELETE FROM detached_item_stats", "DELETE FROM detached_items",
        "DELETE FROM pending_removed_item_stats", "DELETE FROM pending_removed_items",
        "DELETE FROM build_item_stats", "DELETE FROM build_items",
        "DELETE FROM build_sessions", "DELETE FROM inventory_events",
        "DELETE FROM consumable_template_stats", "DELETE FROM consumable_templates",
    }
    for _, statement in ipairs(clears) do
        local ok, err = execute(statement)
        if not ok then rollback(); return false, err end
    end
    for _, definition in ipairs(LEGACY_MODULES) do
        local ok, err = execute("DELETE FROM module_state_entries WHERE namespace=" ..
            sqlQuote(definition.namespace))
        if not ok then rollback(); return false, err end
    end

    local imported = 0
    for objId, item in pairs(items) do
        local stats = item and item.stats or {}
        local loc = tostring(stats[invStatFieldLocation] or "")
        local wornLoc = tostring(stats[invStatFieldWorn] or "")
        if loc == tostring(invItemLocWorn or "worn")
            and wornLoc ~= "" and wornLoc ~= "undefined"
            and wornLoc ~= tostring(invItemWornNotWorn or "not-worn") then
            local wearNum = inv and inv.wearLocId and inv.wearLocId[wornLoc]
            if wearNum ~= nil then
                stats[invStatFieldLocation] = tostring(wearNum)
                loc = tostring(wearNum)
            end
        end
        local isStorage = inv and inv.items and inv.items.isStorageLocation
        local lastStored = tostring(stats[invStatFieldLastStored] or "")
        if lastStored ~= "" and isStorage and not inv.items.isStorageLocation(lastStored) then
            stats[invStatFieldLastStored] = ""
        end
        if loc ~= "" and isStorage and inv.items.isStorageLocation(loc) then
            stats[invStatFieldLastStored] = loc
        end
        if tostring(stats[invStatFieldLastStored] or "") == tostring(invItemLocKeyring or "keyring")
            and tostring(stats[invStatFieldLocation] or "") == "unknown" then
            stats[invStatFieldLocation] = invItemLocKeyring or "keyring"
            stats[invStatFieldContainer] = invItemLocKeyring or "keyring"
        end
        local ok, err = insertItem("items", "item_stats", tostring(objId), item)
        if not ok then rollback(); return false, err end
        local templateOk, templateErr = saveConsumableTemplate(tostring(objId), item)
        if not templateOk then rollback(); return false, templateErr end
        imported = imported + 1
    end
    for namespace, value in pairs(moduleValues) do
        local ok, err = replaceModuleStateInTransaction(namespace, value)
        if not ok then rollback(); return false, err end
        if not setMeta(moduleMigrationMarker(namespace), "restored legacy backup") then
            rollback()
            return false, "unable to persist restored module marker for " .. tostring(namespace)
        end
    end
    if not setMeta("legacy_backup_restored_from", root)
        or not setMeta("legacy_backup_restored_at", tostring(now()))
        or not setMeta("legacy_backup_restored_items", tostring(imported)) then
        rollback()
        return false, "unable to persist legacy backup restore metadata"
    end

    local committed, commitErr = commit()
    if not committed then return false, commitErr end
    database.pending = {
        active = { upserts = {}, deletes = {}, reattach = {}, pendingReattach = {} },
        build = { upserts = {}, deletes = {}, reattach = {}, pendingReattach = {} },
    }
    database.pendingEvents = {}
    database.persistedFingerprints = { active = {}, build = {} }
    database.loadActiveItems()
    return true, imported
end

function database.saveModuleState(namespace, value)
    if type(namespace) ~= "string" or namespace == "" or type(value) ~= "table" then
        return false, "module namespace and table value are required"
    end
    if not database.isOpen then
        local initialized, initErr = database.initialize()
        if not initialized then
            return false, initErr
        end
    end
    local nodes, flattenErr = flattenModuleState(value)
    if not nodes then
        return false, flattenErr
    end
    local txOk, txErr = beginTransaction()
    if not txOk then
        return false, txErr
    end
    local deleted, deleteErr = execute("DELETE FROM module_state_entries WHERE namespace=" ..
        sqlQuote(namespace))
    if not deleted then
        rollback()
        return false, deleteErr
    end
    local inserted, insertErr = insertModuleStateNodes(namespace, nodes)
    if not inserted then
        rollback()
        return false, insertErr
    end
    if not setMeta("module_" .. namespace .. "_updated_at", tostring(now())) then
        rollback()
        return false, "unable to persist module update metadata"
    end
    local committed, commitErr = commit()
    if not committed then
        return false, commitErr
    end
    return true
end

function database.saveModuleStates(states)
    local flattened = {}
    for namespace, value in pairs(states or {}) do
        if type(value) == "table" then
            local nodes, flattenErr = flattenModuleState(value)
            if not nodes then
                return false, tostring(namespace) .. ": " .. tostring(flattenErr)
            end
            flattened[namespace] = nodes
        end
    end
    if not database.isOpen then
        local initialized, initErr = database.initialize()
        if not initialized then
            return false, initErr
        end
    end
    local txOk, txErr = beginTransaction()
    if not txOk then
        return false, txErr
    end
    for namespace, nodes in pairs(flattened) do
        local deleted, deleteErr = execute("DELETE FROM module_state_entries WHERE namespace=" ..
            sqlQuote(namespace))
        if not deleted then
            rollback()
            return false, deleteErr
        end
        local inserted, insertErr = insertModuleStateNodes(namespace, nodes)
        if not inserted then
            rollback()
            return false, insertErr
        end
        if not setMeta("module_" .. namespace .. "_updated_at", tostring(now())) then
            rollback()
            return false, "unable to persist module update metadata for " .. tostring(namespace)
        end
    end
    return commit()
end

function database.loadModuleState(namespace)
    if not database.isOpen then
        local initialized, initErr = database.initialize()
        if not initialized then
            return nil, initErr
        end
    end
    return loadModuleStateDirect(namespace)
end

function database.saveModuleTable(namespace, value)
    local ok, err = database.saveModuleState(namespace, value)
    if not ok then
        if dbot and dbot.warn then
            dbot.warn("Unable to save SQLite module state '" .. tostring(namespace) .. "': " .. tostring(err))
        end
        return DRL_RET_INTERNAL_ERROR
    end
    return DRL_RET_SUCCESS
end

function database.loadModuleTable(namespace, resetFn)
    local value, err = database.loadModuleState(namespace)
    if value ~= nil then
        return value, DRL_RET_SUCCESS
    end
    if err == "not found" then
        local resetResult = resetFn and resetFn() or DRL_RET_SUCCESS
        return nil, resetResult
    end
    if dbot and dbot.warn then
        dbot.warn("Unable to load SQLite module state '" .. tostring(namespace) .. "': " .. tostring(err))
    end
    return nil, DRL_RET_INTERNAL_ERROR
end

function database.initialize()
    local ok, err = database.open()
    if not ok then
        return false, err
    end
    local migrated, migrationResult = database.migrateLegacyItemsOnce()
    if not migrated then
        return false, migrationResult
    end
    local modulesMigrated, moduleMigrationErr = database.migrateAllLegacyModulesOnce()
    if not modulesMigrated then
        return false, moduleMigrationErr
    end
    local repaired, repairResult = database.repairPrimaryDataOnce()
    if not repaired then
        return false, repairResult
    end
    return true, migrationResult
end

function database.beginBuild()
    if not database.isOpen then
        local ok, err = database.initialize()
        if not ok then
            return nil, err
        end
    end

    local resumableId = scalar("SELECT id FROM build_sessions WHERE status IN ('in_progress','interrupted') " ..
        "ORDER BY id DESC LIMIT 1")
    if resumableId then
        local resumed, resumeErr = execute("UPDATE build_sessions SET status='in_progress',updated_at=" .. sqlQuote(now()) ..
            " WHERE id=" .. sqlQuote(resumableId))
        if not resumed then
            return nil, resumeErr
        end
        local staged, stagedErr = database.loadStagedItems()
        if not staged then
            return nil, stagedErr
        end
        return tonumber(resumableId), true
    end

    local txOk, txErr = beginTransaction()
    if not txOk then
        return nil, txErr
    end
    local ok, err = execute("DELETE FROM build_item_stats")
    if ok then ok, err = execute("DELETE FROM build_items") end
    if ok then
        ok, err = execute("INSERT INTO build_sessions(status,started_at,updated_at,identified_count) VALUES(" ..
            table.concat({ sqlQuote("in_progress"), sqlQuote(now()), sqlQuote(now()), "0" }, ",") .. ")")
    end
    if not ok then
        rollback()
        return nil, err
    end
    local buildId = scalar("SELECT last_insert_rowid()")
    local committed, commitErr = commit()
    if not committed then
        return nil, commitErr
    end
    database.persistedFingerprints.build = {}
    return tonumber(buildId), false
end

function database.noteBuildIdentified(buildId, count)
    if not buildId then
        return false, "build id is required"
    end
    local ok, err = execute("UPDATE build_sessions SET identified_count=identified_count+" ..
        sqlQuote(tonumber(count) or 1) .. ",updated_at=" .. sqlQuote(now()) ..
        " WHERE id=" .. sqlQuote(buildId))
    return ok ~= nil, err
end

function database.interruptBuild(buildId)
    if not buildId then
        return false, "build id is required"
    end
    local flushed, flushErr = database.flush("build")
    if not flushed then
        return false, flushErr
    end
    local ok, err = execute("UPDATE build_sessions SET status='interrupted',updated_at=" .. sqlQuote(now()) ..
        " WHERE id=" .. sqlQuote(buildId))
    return ok ~= nil, err
end

function database.abortBuild(buildId)
    if not buildId then
        return false, "build id is required"
    end
    local txOk, txErr = beginTransaction()
    if not txOk then
        return false, txErr
    end
    local statements = {
        "DELETE FROM build_item_stats",
        "DELETE FROM build_items",
        "UPDATE build_sessions SET status='aborted',updated_at=" .. sqlQuote(now()) ..
            " WHERE id=" .. sqlQuote(buildId),
    }
    for _, statement in ipairs(statements) do
        local ok, err = execute(statement)
        if not ok then
            rollback()
            return false, err
        end
    end
    local committed, commitErr = commit()
    if not committed then
        return false, commitErr
    end
    database.pending.build = {
        upserts = {}, deletes = {}, reattach = {}, pendingReattach = {},
    }
    database.persistedFingerprints.build = {}
    return true
end

function database.finishBuild(buildId)
    local flushed, flushErr = database.flush("build")
    if not flushed then
        return false, flushErr
    end
    local txOk, txErr = beginTransaction()
    if not txOk then
        return false, txErr
    end
    local statements = {
        "DELETE FROM item_stats",
        "DELETE FROM items",
        "INSERT INTO items SELECT * FROM build_items",
        "INSERT INTO item_stats SELECT * FROM build_item_stats",
        "DELETE FROM detached_items WHERE obj_id IN (SELECT obj_id FROM build_items)",
        "DELETE FROM pending_removed_items WHERE obj_id IN (SELECT obj_id FROM build_items)",
        "UPDATE build_sessions SET status='complete',updated_at=" .. sqlQuote(now()) ..
            ",completed_at=" .. sqlQuote(now()) .. " WHERE id=" .. sqlQuote(buildId),
    }
    for _, statement in ipairs(statements) do
        local ok, err = execute(statement)
        if not ok then
            rollback()
            return false, err
        end
    end

    local templatesCursor = query("SELECT obj_id FROM items WHERE lower(type_name) IN " ..
        "('potion','pill','food','scroll','wand') AND identify_level='full'")
    if templatesCursor then
        local ids = {}
        local row = templatesCursor:fetch({}, "a")
        while row do
            table.insert(ids, tostring(row.obj_id))
            row = templatesCursor:fetch(row, "a")
        end
        closeCursor(templatesCursor)
        local loaded = loadTableItems("items", "item_stats") or {}
        for _, objId in ipairs(ids) do
            local templateOk, templateErr = saveConsumableTemplate(objId, loaded[objId])
            if not templateOk then
                rollback()
                return false, templateErr
            end
        end
    end

    local committed, commitErr = commit()
    if not committed then
        return false, commitErr
    end
    local activeItems = loadTableItems("items", "item_stats") or {}
    rememberFingerprints("active", activeItems)
    database.persistedFingerprints.build = {}
    database.pending.build = {
        upserts = {}, deletes = {}, reattach = {}, pendingReattach = {},
    }
    return true
end

function database.detachItems(items, rootId)
    if not items or not next(items) then
        return true
    end
    local txOk, txErr = beginTransaction()
    if not txOk then
        return false, txErr
    end
    local committedItems = {}
    for objId, item in pairs(items) do
        local detachedRoot = tostring(rootId or objId)
        local detachedCopy = copyItemWithPresence(item, "detached", detachedRoot)
        local ok, err = insertItem("detached_items", "detached_item_stats", objId, detachedCopy)
        if ok then
            ok, err = execute("DELETE FROM items WHERE obj_id=" .. sqlQuote(objId))
        end
        if not ok then
            rollback()
            return false, err
        end
        committedItems[tostring(objId)] = {
            item = item,
            root = detachedRoot,
        }
    end
    local committed, commitErr = commit()
    if not committed then
        return false, commitErr
    end
    -- Mutate runtime state only after SQLite has committed. A failed detach
    -- therefore leaves both memory and the pending/fingerprint model intact.
    for objId, detached in pairs(committedItems) do
        detached.item.__dinvPresence = "detached"
        detached.item.__dinvDetachedRoot = detached.root
        database.pending.active.upserts[objId] = nil
        database.pending.active.deletes[objId] = nil
        database.pending.active.reattach[objId] = nil
        database.persistedFingerprints.active[objId] = nil
    end
    return true
end

function database.reattachItem(objId, item)
    local txOk, txErr = beginTransaction()
    if not txOk then
        return false, txErr
    end
    local activeCopy = copyItemWithPresence(item, "active", nil)
    local ok, err = insertItem("items", "item_stats", objId, activeCopy)
    if ok then
        ok, err = execute("DELETE FROM detached_items WHERE obj_id=" .. sqlQuote(objId))
    end
    if not ok then
        rollback()
        return false, err
    end
    local committed, commitErr = commit()
    if not committed then
        return false, commitErr
    end
    item.__dinvPresence = "active"
    item.__dinvDetachedRoot = nil
    return true
end


function database.deleteDetachedItem(objId)
    if not database.isOpen then
        return false, "database is not open"
    end
    local ok, err = execute("DELETE FROM detached_items WHERE obj_id=" .. sqlQuote(objId))
    return ok ~= nil, err
end

function database.moveItemsToPendingRemoval(entries, target)
    if not database.isOpen then
        local opened, openErr = database.open()
        if not opened then
            return false, openErr
        end
    end
    if type(entries) ~= "table" or not next(entries) then
        return false, "pending removal entries are required"
    end

    local normalizedTarget = target == "build" and "build" or "active"
    local sourceTable = normalizedTarget == "build" and "build_items" or "items"
    local txOk, txErr = beginTransaction()
    if not txOk then
        return false, txErr
    end

    local committedKeys = {}
    for _, entry in pairs(entries) do
        local objId = entry and entry.objId
        local item = entry and entry.item
        local details = entry and type(entry.details) == "table" and entry.details or {}
        if not objId or not item then
            rollback()
            return false, "each pending removal requires an object ID and item"
        end
        local key = tostring(objId)
        local removedAt = tonumber(details.removedAt) or now()
        local purgeAfter = math.max(removedAt, tonumber(details.purgeAfter) or removedAt)
        local pendingCopy = copyItemWithPresence(item, "pending-removal", nil)
        local ok, err = insertItem(
            "pending_removed_items", "pending_removed_item_stats", key, pendingCopy)
        if ok then
            ok, err = execute("UPDATE pending_removed_items SET removed_at=" .. sqlQuote(removedAt) ..
                ",purge_after=" .. sqlQuote(purgeAfter) ..
                ",removal_action=" .. sqlQuote(tonumber(details.action)) ..
                ",removal_reason=" .. sqlQuote(tostring(details.reason or "removed_from_inventory")) ..
                " WHERE obj_id=" .. sqlQuote(key))
        end
        if ok then
            ok, err = execute("DELETE FROM " .. sourceTable .. " WHERE obj_id=" .. sqlQuote(key))
        end
        if not ok then
            rollback()
            return false, err
        end
        table.insert(committedKeys, key)
    end

    local committed, commitErr = commit()
    if not committed then
        return false, commitErr
    end

    local bucket = pendingBucket(normalizedTarget)
    for _, key in ipairs(committedKeys) do
        bucket.upserts[key] = nil
        bucket.deletes[key] = nil
        bucket.reattach[key] = nil
        bucket.pendingReattach[key] = nil
        database.persistedFingerprints[normalizedTarget][key] = nil
    end
    return true, #committedKeys
end

function database.moveItemToPendingRemoval(objId, item, details, target)
    return database.moveItemsToPendingRemoval({
        { objId = objId, item = item, details = details },
    }, target)
end

function database.deletePendingRemovedItem(objId)
    if not database.isOpen then
        return false, "database is not open"
    end
    local ok, err = execute("DELETE FROM pending_removed_items WHERE obj_id=" .. sqlQuote(objId))
    return ok ~= nil, err
end

function database.recordTerminalRemoval(eventSeq, objId, action, reason, containerId, wearLocation)
    if not database.isOpen then
        return false, "database is not open"
    end

    local event = {
        eventSeq = eventSeq,
        objId = objId,
        action = action,
        reason = reason,
        containerId = containerId,
        wearLocation = wearLocation,
        observedAt = now(),
        sessionId = database.getSessionId(),
    }
    local txOk, txErr = beginTransaction()
    if not txOk then
        return false, txErr
    end
    local keySql = sqlQuote(objId)
    local statements = {
        "DELETE FROM items WHERE obj_id=" .. keySql,
        "DELETE FROM detached_items WHERE obj_id=" .. keySql,
        "DELETE FROM pending_removed_items WHERE obj_id=" .. keySql,
        "DELETE FROM build_items WHERE obj_id=" .. keySql,
        inventoryEventSql(event),
    }
    for _, statement in ipairs(statements) do
        local ok, err = execute(statement)
        if not ok then
            rollback()
            return false, err
        end
    end
    local committed, commitErr = commit()
    if not committed then
        return false, commitErr
    end

    local key = tostring(objId)
    for _, target in ipairs({ "active", "build" }) do
        local bucket = pendingBucket(target)
        bucket.upserts[key] = nil
        bucket.deletes[key] = nil
        bucket.reattach[key] = nil
        bucket.pendingReattach[key] = nil
        database.persistedFingerprints[target][key] = nil
    end
    return true
end

function database.recordInventoryEvent(eventSeq, objId, action, reason, containerId, wearLocation)
    if not database.isOpen then
        return false
    end
    table.insert(database.pendingEvents, {
        eventSeq = eventSeq,
        objId = objId,
        action = action,
        reason = reason,
        containerId = containerId,
        wearLocation = wearLocation,
        observedAt = now(),
        sessionId = database.getSessionId(),
    })
    return true
end


function database.getMaxEventSequence()
    return tonumber(scalar("SELECT COALESCE(MAX(event_seq), 0) FROM inventory_events")) or 0
end


local function numericComparison(value, defaultOperator)
    local text = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local operator, number = text:match("^(>=)%s*(%-?[%d%.]+)$")
    if not operator then operator, number = text:match("^(<=)%s*(%-?[%d%.]+)$") end
    if not operator then operator, number = text:match("^(>)%s*(%-?[%d%.]+)$") end
    if not operator then operator, number = text:match("^(<)%s*(%-?[%d%.]+)$") end
    if not operator then operator, number = text:match("^(=)%s*(%-?[%d%.]+)$") end
    if not operator then
        number = text:match("^(%-?[%d%.]+)$")
        operator = number and (defaultOperator or "=") or nil
    end
    if not operator or tonumber(number) == nil then
        return nil
    end
    return operator, tonumber(number)
end

local function containsSql(expression, value)
    return "instr(lower(COALESCE(" .. expression .. ",'')),lower(" .. sqlQuote(value) .. "))>0"
end

local function statValueExpression(alias)
    return "COALESCE(" .. alias .. ".text_value,CAST(" .. alias .. ".numeric_value AS TEXT)," ..
        "CAST(" .. alias .. ".boolean_value AS TEXT),'')"
end

local function criterionSql(entry, statsTableName)
    local key = tostring(entry.key or ""):lower()
    local value = tostring(entry.value or "")
    local condition
    if key == "type" then
        condition = "lower(COALESCE(i.type_name,''))=lower(" .. sqlQuote(value) .. ")"
    elseif key == "name" or key == "rname" then
        local relativeName = value:match("^%d+%.(.+)$") or value
        condition = containsSql("i.name", relativeName)
    elseif key == "wearable" then
        condition = containsSql("i.wearable", value)
    elseif key == "colorname" then
        condition = containsSql("i.color_name", value)
    elseif key == "identifylevel" then
        condition = containsSql("i.identify_level", value)
    elseif key == "laststored" then
        condition = containsSql("i.last_stored", value)
    elseif key == "typenum" or key == "timer" then
        local column = key == "typenum" and "i.type_num" or "i.timer"
        local operator, number = numericComparison(value, "=")
        condition = operator and "COALESCE(" .. column .. ",0)" .. operator .. sqlQuote(number) or "0"
    elseif key == "keepflag" then
        local normalized = value:lower():gsub("^%s+", ""):gsub("%s+$", "")
        if normalized == "true" or normalized == "1" or normalized == "kept" then
            condition = "COALESCE(i.keep_flag,0)=1"
        elseif normalized == "false" or normalized == "0" then
            condition = "COALESCE(i.keep_flag,0)=0"
        else
            condition = "0"
        end
    elseif key == "id" then
        condition = "i.obj_id=" .. sqlQuote(value)
    elseif key == "container" then
        condition = "COALESCE(i.container_id,'')=" .. sqlQuote(value)
    elseif key == "location" or key == "loc" or key == "rlocation" or key == "rloc" then
        local relativeLocation = value:match("^%d+%.(.+)$") or value
        condition = containsSql("i.location", relativeLocation)
    elseif key == "worn" then
        condition = "COALESCE(i.worn,'') NOT IN ('','undefined','not-worn')"
    elseif key == "minlevel" then
        local _, number = numericComparison(value, ">=")
        condition = number and "COALESCE(i.level,0)>=" .. sqlQuote(number) or "0"
    elseif key == "maxlevel" then
        local _, number = numericComparison(value, "<=")
        condition = number and "COALESCE(i.level,0)<=" .. sqlQuote(number) or "0"
    elseif key == "level" then
        local operator, number = numericComparison(value, "=")
        condition = operator and "COALESCE(i.level,0)" .. operator .. sqlQuote(number) or "0"
    elseif key == "flag" or key == "flags" then
        if value:lower() == "kept" then
            condition = "COALESCE(i.keep_flag,0)=1"
        else
            condition = "EXISTS(SELECT 1 FROM " .. statsTableName .. " sf WHERE sf.obj_id=i.obj_id " ..
                "AND lower(sf.stat_key)='flags' AND " .. containsSql(statValueExpression("sf"), value) .. ")"
        end
    else
        local operator, number = numericComparison(value, nil)
        local valueCondition
        if operator and number then
            valueCondition = "sv.numeric_value IS NOT NULL AND sv.numeric_value" .. operator .. sqlQuote(number)
        else
            valueCondition = containsSql(statValueExpression("sv"), value)
        end
        condition = "EXISTS(SELECT 1 FROM " .. statsTableName .. " sv WHERE sv.obj_id=i.obj_id " ..
            "AND lower(sv.stat_key)=" .. sqlQuote(key) .. " AND " .. valueCondition .. ")"
    end
    if entry.negated then
        return "NOT(" .. condition .. ")"
    end
    return condition
end

function database.searchParsed(clauses, target)
    target = target == "build" and "build" or "active"
    local tableName = target == "build" and "build_items" or "items"
    local statsTableName = target == "build" and "build_item_stats" or "item_stats"
    local flushed, flushErr = database.flush(target)
    if not flushed then
        return nil, flushErr
    end

    local orConditions = {}
    for _, criteria in ipairs(clauses or {}) do
        local andConditions = {}
        for _, entry in ipairs(criteria or {}) do
            table.insert(andConditions, criterionSql(entry, statsTableName))
        end
        table.insert(orConditions, #andConditions > 0 and ("(" .. table.concat(andConditions, " AND ") .. ")") or "1")
    end
    local where = #orConditions > 0 and table.concat(orConditions, " OR ") or "1"
    local sql = "SELECT i.obj_id FROM " .. tableName .. " i WHERE " .. where ..
        " ORDER BY COALESCE(i.level,0),lower(COALESCE(i.type_name,''))," ..
        "lower(COALESCE(i.name,'')),CAST(i.obj_id AS INTEGER),i.obj_id"
    local cursor, err = query(sql)
    if not cursor then
        return nil, err
    end
    local ids = {}
    local row = cursor:fetch({}, "a")
    while row do
        table.insert(ids, tostring(row.obj_id))
        row = cursor:fetch(row, "a")
    end
    closeCursor(cursor)
    return ids
end

function database.collectRuntimeModuleStates()
    local states = {}
    if inv then
        if inv.config and type(inv.config.table) == "table" then states.config = inv.config.table end
        if inv.cache and inv.cache.getPersistentState then
            states.cache = inv.cache.getPersistentState()
        end
        if inv.analyze and type(inv.analyze.table) == "table" then states.analyze = inv.analyze.table end
        if inv.consume and type(inv.consume.table) == "table" then states.consume = inv.consume.table end
        if inv.priority and type(inv.priority.table) == "table" then states.priority = inv.priority.table end
        if inv.set and type(inv.set.table) == "table" then states.set = inv.set.table end
        if inv.snapshot and type(inv.snapshot.table) == "table" then states.snapshot = inv.snapshot.table end
        if inv.statBonus and type(inv.statBonus.table) == "table" then states.statbonus = inv.statBonus.table end
        if inv.tags and type(inv.tags.table) == "table" then states.tags = inv.tags.table end
        if inv.levelup and type(inv.levelup.table) == "table" then states.levelup = inv.levelup.table end
    end
    if dbot and dbot.notify and type(dbot.notify.table) == "table" then
        states.notify = dbot.notify.table
    end
    if DINV and DINV.debug and type(DINV.debug.table) == "table" then
        states.debug = DINV.debug.table
    end
    return states
end

function database.persistRuntimeModuleStates()
    return database.saveModuleStates(database.collectRuntimeModuleStates())
end

function database.createBackupSnapshot(targetFile)
    if not database.isOpen then
        local initialized, initErr = database.initialize()
        if not initialized then
            return false, initErr
        end
    end
    local existing = io.open(targetFile, "rb")
    if existing then
        existing:close()
        return false, "backup database already exists"
    end

    local activeFlushed, activeErr = database.flush("active")
    if not activeFlushed then
        return false, activeErr
    end
    local buildFlushed, buildErr = database.flush("build")
    if not buildFlushed then
        return false, buildErr
    end
    local statesSaved, statesErr = database.persistRuntimeModuleStates()
    if not statesSaved then
        return false, statesErr
    end
    local vacuumed, vacuumErr = execute("VACUUM INTO " .. sqlQuote(targetFile))
    if not vacuumed then
        return false, vacuumErr
    end
    return true
end

function database.reopenAfterExternalReplace()
    database.close()
    database.resetRuntimeState()
    return database.initialize()
end

function database.quickCheck()
    local result, err = scalar("PRAGMA quick_check")
    if not result then
        return false, err
    end
    return tostring(result) == "ok", tostring(result)
end

function database.quickCheckFile(fileName)
    local path = tostring(fileName or "")
    if path == "" then return false, "database file is required" end

    local okDriver, driver = pcall(require, "luasql.sqlite3")
    if not okDriver or not driver then
        return false, "LuaSQL SQLite is unavailable: " .. tostring(driver)
    end
    local env = driver.sqlite3()
    if not env then return false, "unable to create SQLite validation environment" end
    local conn, connectErr = env:connect(path)
    if not conn then
        env:close()
        return false, "unable to open staged database: " .. tostring(connectErr)
    end

    local function finish(ok, detail)
        pcall(function() conn:close() end)
        pcall(function() env:close() end)
        return ok, detail
    end

    local cursor, queryErr = conn:execute("PRAGMA quick_check")
    if not cursor or type(cursor.fetch) ~= "function" then
        return finish(false, tostring(queryErr or "quick_check did not return a result"))
    end
    local row = cursor:fetch({}, "n")
    closeCursor(cursor)
    local result = row and row[1] or nil
    if tostring(result) ~= "ok" then
        return finish(false, tostring(result or "quick_check failed"))
    end

    cursor, queryErr = conn:execute("SELECT COUNT(*) FROM sqlite_master " ..
        "WHERE type='table' AND name IN ('meta','items','item_stats','module_state_entries')")
    if not cursor or type(cursor.fetch) ~= "function" then
        return finish(false, tostring(queryErr or "schema validation failed"))
    end
    row = cursor:fetch({}, "n")
    closeCursor(cursor)
    if tonumber(row and row[1]) ~= 4 then
        return finish(false, "file is SQLite but is not a DINV database")
    end
    return finish(true, "ok")
end

function database.getStatus()
    return {
        file = database.file,
        character = database.character,
        sessionId = database.sessionId,
        activeItems = tonumber(scalar("SELECT COUNT(*) FROM items")) or 0,
        detachedItems = tonumber(scalar("SELECT COUNT(*) FROM detached_items")) or 0,
        pendingRemovedItems = tonumber(scalar("SELECT COUNT(*) FROM pending_removed_items")) or 0,
        stagedItems = tonumber(scalar("SELECT COUNT(*) FROM build_items")) or 0,
        consumableTemplates = tonumber(scalar("SELECT COUNT(*) FROM consumable_templates")) or 0,
        events = tonumber(scalar("SELECT COUNT(*) FROM inventory_events")) or 0,
        moduleNamespaces = tonumber(scalar("SELECT COUNT(DISTINCT namespace) FROM module_state_entries")) or 0,
    }
end

database._sqlQuote = sqlQuote
database._isConsumableType = isConsumableType
database._templateKey = templateKey
