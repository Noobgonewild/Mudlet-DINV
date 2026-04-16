----------------------------------------------------------------------------------------------------
-- INV Core Module
-- Core inventory namespace, initialization, and version management
----------------------------------------------------------------------------------------------------

inv = inv or {}

----------------------------------------------------------------------------------------------------
-- Inventory State Constants
----------------------------------------------------------------------------------------------------

invStateIdle       = "idle"
invStatePaused     = "paused"
invStateDiscovery  = "discovery"
invStateIdentify   = "identify"

----------------------------------------------------------------------------------------------------
-- Stat Field Constants
----------------------------------------------------------------------------------------------------

-- Item identification fields
invStatFieldId         = "id"
invStatFieldName       = "name"
invStatFieldType       = "type"
invStatFieldTypeNum    = "typeNum"
invStatFieldColorName  = "colorName"
invStatFieldLevel      = "level"
invStatFieldWearable   = "wearable"
invStatFieldScore      = "score"
invStatFieldWeight     = "weight"
invStatFieldWorth      = "worth"
invStatFieldFlags      = "flags"
invStatFieldKeywords   = "keywords"
invStatFieldFoundAt    = "foundat"
invStatFieldMaterial   = "material"
invStatFieldSerial     = "serial"
invStatFieldTimer      = "timer"
invStatFieldOwner      = "owner"
invStatFieldClan       = "clan"
invStatFieldKeepflag   = "keepflag"
invStatFieldWorn       = "worn"
invStatFieldContainer  = "container"
invStatFieldLocation   = "location"
invStatFieldLastStored = "lastStored"

-- Stat fields
invStatFieldStr        = "str"
invStatFieldInt        = "int"
invStatFieldWis        = "wis"
invStatFieldDex        = "dex"
invStatFieldCon        = "con"
invStatFieldLuck       = "luck"

invStatFieldHp         = "hp"
invStatFieldMana       = "mana"
invStatFieldMoves      = "moves"

invStatFieldHitroll    = "hitroll"
invStatFieldDamroll    = "damroll"
invStatFieldSaves      = "saves"

invStatFieldHr         = "hr"
invStatFieldDr         = "dr"

-- Resists
invStatFieldAllPhys    = "allphys"
invStatFieldAllMagic   = "allmagic"

invStatFieldBash       = "bash"
invStatFieldPierce     = "pierce"
invStatFieldSlash      = "slash"

invStatFieldAcid       = "acid"
invStatFieldCold       = "cold"
invStatFieldEnergy     = "energy"
invStatFieldHoly       = "holy"
invStatFieldElectric   = "electric"
invStatFieldNegative   = "negative"
invStatFieldShadow     = "shadow"
invStatFieldMagic      = "magic"
invStatFieldAir        = "air"
invStatFieldEarth      = "earth"
invStatFieldFire       = "fire"
invStatFieldLight      = "light"
invStatFieldMental     = "mental"
invStatFieldSonic      = "sonic"
invStatFieldWater      = "water"
invStatFieldDisease    = "disease"
invStatFieldPoison     = "poison"

-- Weapon fields
invStatFieldAveDam     = "avedam"
invStatFieldInflicts   = "inflicts"
invStatFieldDamtype    = "damtype"
invStatFieldWeaponType = "weapontype"
invStatFieldSpecials   = "specials"

-- Armor fields
invStatFieldArmor      = "armor"

-- Container fields
invStatFieldCapacity   = "capacity"
invStatFieldHolding    = "holding"
invStatFieldHeaviestItem = "heaviestitem"
invStatFieldItemsInside = "itemsinside"
invStatFieldTotWeight  = "totweight"
invStatFieldItemBurden = "itemburden"
invStatFieldItemWeight = "itemweight"
invStatFieldReducedBy  = "reducedby"

-- Light fields
invStatFieldDuration   = "duration"

-- Food/Drink fields
invStatFieldNutrition  = "nutrition"
invStatFieldFoodAffects = "foodaffects"

-- Portal fields
invStatFieldDestination = "destination"
invStatFieldLeadsTo     = "leadsto"

-- Misc fields
invStatFieldSpells     = "spells"
invStatFieldSpellUses  = "spelluses"
invStatFieldSpellLevel = "spelllevel"
invStatFieldSpellName  = "spellname"
invStatFieldSkills     = "skills"
invStatFieldAffects    = "affects"
invStatFieldAffectMods = "affectMods"
invStatFieldAbilMods   = "abilmods"
invStatFieldEnchants   = "enchants"

-- Calculated/derived fields
invStatFieldLocType    = "loctype"
invStatFieldLocName    = "locname"
invStatFieldColorName  = "colorname"

----------------------------------------------------------------------------------------------------
-- Query Key Constants
----------------------------------------------------------------------------------------------------

invQueryKeyOrganize = "organize"

----------------------------------------------------------------------------------------------------
-- Invmon Action Constants
----------------------------------------------------------------------------------------------------

invmonActionRemoved             = 1
invmonActionWorn                = 2
invmonActionRemovedFromInv      = 3
invmonActionAddedToInv          = 4
invmonActionTakenOutOfContainer = 5
invmonActionPutIntoContainer    = 6
invmonActionConsumed            = 7
invmonActionPutIntoVault        = 9
invmonActionRemovedFromVault    = 10
invmonActionPutIntoKeyring      = 11
invmonActionGetFromKeyring      = 12

if type(invmon) ~= "table" then
    invmon = {}
end
invmon.action = {
    [1]  = "Removed",
    [2]  = "Worn",
    [3]  = "RemovedFromInv",
    [4]  = "AddedToInv",
    [5]  = "TakenOutOfContainer",
    [6]  = "PutIntoContainer",
    [7]  = "Consumed",
    [9]  = "PutIntoVault",
    [10] = "RemovedFromVault",
    [11] = "PutIntoKeyring",
    [12] = "GetFromKeyring",
}

----------------------------------------------------------------------------------------------------
-- Wear Location Table
----------------------------------------------------------------------------------------------------

inv.wearLoc = {
    [0]  = "light",
    [1]  = "head",
    [2]  = "eyes",
    [3]  = "lear",
    [4]  = "rear",
    [5]  = "neck1",
    [6]  = "neck2",
    [7]  = "back",
    [8]  = "medal1",
    [9]  = "medal2",
    [10] = "medal3",
    [11] = "medal4",
    [12] = "torso",
    [13] = "body",
    [14] = "waist",
    [15] = "arms",
    [16] = "lwrist",
    [17] = "rwrist",
    [18] = "hands",
    [19] = "lfinger",
    [20] = "rfinger",
    [21] = "legs",
    [22] = "feet",
    [23] = "shield",
    [24] = "wielded",
    [25] = "second",
    [26] = "hold",
    [27] = "float",
    [30] = "above",
    [31] = "portal",
    [32] = "sleeping",
}
----------------------------------------------------------------------------------------------------
-- Wear Location Constants
----------------------------------------------------------------------------------------------------

invWearLocLight      = "light"
invWearLocHead       = "head"
invWearLocEyes       = "eyes"
invWearLocEar1       = "ear1"
invWearLocEar2       = "ear2"
invWearLocNeck1      = "neck1"
invWearLocNeck2      = "neck2"
invWearLocBack       = "back"
invWearLocMedal1     = "medal1"
invWearLocMedal2     = "medal2"
invWearLocMedal3     = "medal3"
invWearLocMedal4     = "medal4"
invWearLocTorso      = "torso"
invWearLocBody       = "body"
invWearLocWaist      = "waist"
invWearLocArms       = "arms"
invWearLocWrist1     = "wrist1"
invWearLocWrist2     = "wrist2"
invWearLocHands      = "hands"
invWearLocFinger1    = "finger1"
invWearLocFinger2    = "finger2"
invWearLocHold       = "hold"
invWearLocLegs       = "legs"
invWearLocFeet       = "feet"
invWearLocShield     = "shield"
invWearLocWield      = "wield"
invWearLocSecond     = "second"
invWearLocAbove      = "above"
invWearLocFloat      = "float"
invWearLocPortal     = "portal"

----------------------------------------------------------------------------------------------------
-- Wear Location Tables
----------------------------------------------------------------------------------------------------

inv.wearLoc = {
    [invWearLocLight]  = invWearLocLight,
    [invWearLocHead]   = invWearLocHead,
    [invWearLocEyes]   = invWearLocEyes,
    [invWearLocEar1]   = invWearLocEar1,
    [invWearLocEar2]   = invWearLocEar2,
    [invWearLocNeck1]  = invWearLocNeck1,
    [invWearLocNeck2]  = invWearLocNeck2,
    [invWearLocBack]   = invWearLocBack,
    [invWearLocMedal1] = invWearLocMedal1,
    [invWearLocMedal2] = invWearLocMedal2,
    [invWearLocMedal3] = invWearLocMedal3,
    [invWearLocMedal4] = invWearLocMedal4,
    [invWearLocTorso]  = invWearLocTorso,
    [invWearLocBody]   = invWearLocBody,
    [invWearLocWaist]  = invWearLocWaist,
    [invWearLocArms]   = invWearLocArms,
    [invWearLocWrist1] = invWearLocWrist1,
    [invWearLocWrist2] = invWearLocWrist2,
    [invWearLocHands]  = invWearLocHands,
    [invWearLocFinger1]= invWearLocFinger1,
    [invWearLocFinger2]= invWearLocFinger2,
    [invWearLocHold]   = invWearLocHold,
    [invWearLocLegs]   = invWearLocLegs,
    [invWearLocFeet]   = invWearLocFeet,
    [invWearLocShield] = invWearLocShield,
    [invWearLocWield]  = invWearLocWield,
    [invWearLocSecond] = invWearLocSecond,
    [invWearLocAbove]  = invWearLocAbove,
    [invWearLocFloat]  = invWearLocFloat,
    [invWearLocPortal] = invWearLocPortal,
}

inv.wearables = {
    light = { invWearLocLight },
    head = { invWearLocHead },
    eyes = { invWearLocEyes },
    ear = { invWearLocEar1, invWearLocEar2 },
    neck = { invWearLocNeck1, invWearLocNeck2 },
    back = { invWearLocBack },
    medal = { invWearLocMedal1, invWearLocMedal2, invWearLocMedal3, invWearLocMedal4 },
    torso = { invWearLocTorso },
    body = { invWearLocBody },
    waist = { invWearLocWaist },
    arms = { invWearLocArms },
    wrist = { invWearLocWrist1, invWearLocWrist2 },
    hands = { invWearLocHands },
    finger = { invWearLocFinger1, invWearLocFinger2 },
    legs = { invWearLocLegs },
    feet = { invWearLocFeet },
    shield = { invWearLocShield },
    wield = { invWearLocWield, invWearLocSecond },
    hold = { invWearLocHold },
    float = { invWearLocFloat },
    above = { invWearLocAbove },
    portal = { invWearLocPortal },
}

----------------------------------------------------------------------------------------------------
-- Item Type Constants
----------------------------------------------------------------------------------------------------

invItemTypeArmor     = "Armor"
invItemTypeWeapon    = "Weapon"
invItemTypeLight     = "Light"
invItemTypeTreasure  = "Treasure"
invItemTypeContainer = "Container"
invItemTypePotion    = "Potion"
invItemTypePill      = "Pill"
invItemTypeScroll    = "Scroll"
invItemTypeWand      = "Wand"
invItemTypeStaff     = "Staff"
invItemTypePortal    = "Portal"
invItemTypeFood      = "Food"
invItemTypeDrink     = "Drink Container"
invItemTypeKey       = "Key"
invItemTypeFurniture = "Furniture"
invItemTypeTrash     = "Trash"
invItemTypeBoat      = "Boat"
invItemTypeRaw       = "Raw Material"

----------------------------------------------------------------------------------------------------
-- Refresh Location Constants
----------------------------------------------------------------------------------------------------

invItemsRefreshLocDirty = "dirty"
invItemsRefreshLocAll   = "all"

----------------------------------------------------------------------------------------------------
-- Inventory Location Constants
----------------------------------------------------------------------------------------------------

invItemLocInventory = "inventory"
invItemLocWorn      = "worn"
invItemLocKeyring   = "keyring"

----------------------------------------------------------------------------------------------------
-- Identification Levels
----------------------------------------------------------------------------------------------------

invIdLevelNone    = "none"
invIdLevelSoft    = "soft"
invIdLevelPartial = "partial"
invIdLevelFull    = "full"

----------------------------------------------------------------------------------------------------
-- Tags Constants
----------------------------------------------------------------------------------------------------

invTagsBuild     = "build"
invTagsRefresh   = "refresh"
invTagsSearch    = "search"
invTagsSet       = "set"
invTagsWeapon    = "weapon"
invTagsSnapshot  = "snapshot"
invTagsAnalyze   = "analyze"
invTagsUsage     = "usage"
invTagsCompare   = "compare"
invTagsCovet     = "covet"
invTagsPriority  = "priority"
invTagsBackup    = "backup"
invTagsConsume   = "consume"
invTagsPortal    = "portal"
invTagsVersion   = "version"
invTagsUnused    = "unused"
invTagsKeyword   = "keyword"
invTagsReset     = "reset"
invTagsDiscover  = "discover"

----------------------------------------------------------------------------------------------------
-- Base Inventory Module
----------------------------------------------------------------------------------------------------

inv = {}
inv.init = {}
inv.modules = "config items cache priority set statBonus consume snapshot tags analyze levelup"
inv.inSafeMode = false

-- Pre-declare all inv module tables to prevent nil errors during load
-- These will be fully populated when their respective modules load
inv.config   = inv.config or {}
inv.items    = inv.items or {}
inv.cache    = inv.cache or {}
inv.priority = inv.priority or {}
inv.score    = inv.score or {}
inv.set      = inv.set or {}
inv.statBonus = inv.statBonus or {}
inv.consume  = inv.consume or {}
inv.snapshot = inv.snapshot or {}
inv.tags     = inv.tags or {}
inv.weapon   = inv.weapon or {}
inv.analyze  = inv.analyze or {}
inv.usage    = inv.usage or {}
inv.compare  = inv.compare or {}
inv.portal   = inv.portal or {}
inv.pass     = inv.pass or {}
inv.regen    = inv.regen or {}
inv.organize = inv.organize or {}
inv.keyword  = inv.keyword or {}
inv.unused   = inv.unused or {}
inv.discover = inv.discover or {}
inv.cli      = inv.cli or {}

-- Pre-declare init sub-tables for each module
inv.config.init   = inv.config.init or {}
inv.items.init    = inv.items.init or {}
inv.cache.init    = inv.cache.init or {}
inv.priority.init = inv.priority.init or {}
inv.score.init    = inv.score.init or {}
inv.set.init      = inv.set.init or {}
inv.statBonus.init = inv.statBonus.init or {}
inv.consume.init  = inv.consume.init or {}
inv.snapshot.init = inv.snapshot.init or {}
inv.tags.init     = inv.tags.init or {}
inv.weapon.init   = inv.weapon.init or {}
inv.analyze.init  = inv.analyze.init or {}
inv.usage.init    = inv.usage.init or {}
inv.compare.init  = inv.compare.init or {}
inv.portal.init   = inv.portal.init or {}
inv.pass.init     = inv.pass.init or {}
inv.regen.init    = inv.regen.init or {}
inv.organize.init = inv.organize.init or {}
inv.keyword.init  = inv.keyword.init or {}
inv.unused.init   = inv.unused.init or {}
inv.discover.init = inv.discover.init or {}
inv.cli.init      = inv.cli.init or {}

-- Pre-declare some critical tables that other modules reference
inv.set.table     = inv.set.table or {}
inv.items.table   = inv.items.table or {}
inv.priority.table = inv.priority.table or {}
inv.cache.table   = inv.cache.table or {}
inv.snapshot.table = inv.snapshot.table or {}

inv.init.initializedInstall = false
inv.init.initializedActive  = false
inv.init.activePending      = false

inv.state = invStateIdle

----------------------------------------------------------------------------------------------------
-- Version Information
----------------------------------------------------------------------------------------------------

inv.version = {}
inv.version.pluginMajor = 2
inv.version.pluginMinor = 56
inv.version.full = inv.version.pluginMajor + (inv.version.pluginMinor / 10000)

inv.version.table = {
    pluginVer      = { major = inv.version.pluginMajor, minor = inv.version.pluginMinor },
    tableFormat    = { major = 0, minor = 1 },
    cacheFormat    = { major = 0, minor = 1 },
    consumeFormat  = { major = 0, minor = 1 },
    priorityFormat = { major = 0, minor = 1 },
    setFormat      = { major = 0, minor = 1 },
    snapshotFormat = { major = 0, minor = 1 }
}

function inv.version.get()
    return inv.version.table
end

function inv.version.display()
    dbot.print("\n  @y" .. pluginNameAbbr .. "  Aardwolf Plugin\n" ..
               "-------------------------@w")
    dbot.print("@WPlugin Version:    @G" ..
               string.format("%01d", inv.version.table.pluginVer.major) .. "." ..
               string.format("%04d", inv.version.table.pluginVer.minor) .. "@w")
    dbot.print("")
    dbot.print("@WInv. Table Format: @G" ..
               inv.version.table.tableFormat.major .. "." ..
               inv.version.table.tableFormat.minor .. "@w")
    dbot.print("@WInv. Cache Format: @G" ..
               inv.version.table.cacheFormat.major .. "." ..
               inv.version.table.cacheFormat.minor .. "@w")
    dbot.print("@WConsumable Format: @G" ..
               inv.version.table.consumeFormat.major .. "." ..
               inv.version.table.consumeFormat.minor .. "@w")
    dbot.print("@WPriorities Format: @G" ..
               inv.version.table.priorityFormat.major .. "." ..
               inv.version.table.priorityFormat.minor .. "@w")
    dbot.print("@WEquip Set Format:  @G" ..
               inv.version.table.setFormat.major .. "." ..
               inv.version.table.setFormat.minor .. "@w")
    dbot.print("@WSnapshot Format:   @G" ..
               inv.version.table.snapshotFormat.major .. "." ..
               inv.version.table.snapshotFormat.minor .. "@w")
    dbot.print("")
    
    return DRL_RET_SUCCESS
end

----------------------------------------------------------------------------------------------------
-- Initialization Functions
----------------------------------------------------------------------------------------------------

drlDoSaveState    = true
drlDoNotSaveState = false

function inv.init.atInstall()
    local retval = DRL_RET_SUCCESS
    
    -- Initialize dbot first if not already done
    if dbot.init.initializedInstall == false then
        retval = dbot.init.atInstall()
        if retval ~= DRL_RET_SUCCESS then
            dbot.warn("inv.init.atInstall: Failed to initialize 'at install' dbot modules: " ..
                      dbot.retval.getString(retval))
        else
            dbot.init.initializedInstall = true
        end
    end
    
    if inv.init.initializedInstall then
        dbot.note("Skipping inv.init.atInstall request: it is already initialized")
        return retval
    end
    
    -- Set initial state
    inv.state = invStateIdle
    
    -- Initialize all inv modules
    retval = DRL_RET_SUCCESS
    for module in inv.modules:gmatch("%S+") do
        if inv[module] and inv[module].init and inv[module].init.atInstall then
            local initVal = inv[module].init.atInstall()
            if initVal ~= DRL_RET_SUCCESS then
                dbot.warn("inv.init.atInstall: Failed to initialize 'at install' inv." .. module ..
                          " module: " .. dbot.retval.getString(initVal))
                retval = initVal
            else
                dbot.debug("Initialized 'at install' module inv." .. module, "inv.core")
            end
        end
    end
    
    if retval == DRL_RET_SUCCESS then
        inv.init.initializedInstall = true
    end
    
    -- Request GMCP data to trigger initialization
    if sendGMCP then
        sendGMCP("request char")
    end
    
    return retval
end

function inv.init.atActive()
    local retval = DRL_RET_SUCCESS
    
    if not inv.init.activePending then
        inv.init.activePending = true
        
        -- In Mudlet, we don't have coroutines the same way, so we call directly
        retval = inv.init.atActiveDirect()
        
        inv.init.activePending = false
    else
        dbot.debug("inv.init.atActive: Another initialization is in progress", "inv.core")
        retval = DRL_RET_BUSY
    end
    
    return retval
end

function inv.init.atActiveDirect()
    local retval = DRL_RET_SUCCESS
    
    if dbot.gmcp.isInitialized == false then
        dbot.warn("inv.init.atActiveDirect: GMCP is not initialized when we are active!")
        return DRL_RET_INTERNAL_ERROR
    end
    
    -- Initialize dbot "at active" modules
    if dbot.init.initializedActive == false then
        retval = dbot.init.atActive()
        if retval ~= DRL_RET_SUCCESS then
            dbot.warn("inv.init.atActiveDirect: Failed to initialize 'at active' dbot modules: " ..
                      dbot.retval.getString(retval))
        else
            dbot.debug("Initialized dbot 'at active' modules", "inv.core")
            dbot.init.initializedActive = true
        end
    end
    
    -- Initialize all inv "at active" modules
    retval = DRL_RET_SUCCESS
    if inv.init.initializedActive == false then
        for module in inv.modules:gmatch("%S+") do
            if inv[module] and inv[module].init and inv[module].init.atActive then
                local initVal = inv[module].init.atActive()
                if initVal ~= DRL_RET_SUCCESS then
                    dbot.warn("inv.init.atActiveDirect: Failed to initialize 'at active' inv." .. module ..
                              " module: " .. dbot.retval.getString(initVal))
                    retval = initVal
                else
                    dbot.debug("Initialized 'at active' module inv." .. module, "inv.core")
                end
            end
        end
        
        if retval == DRL_RET_SUCCESS then
            inv.init.initializedActive = true
            local fullVer = string.format("%d.%04d", inv.version.pluginMajor, inv.version.pluginMinor)
            dbot.info("Plugin version " .. fullVer .. " is fully initialized")
            
            -- Kick off initial refresh if enabled
            if inv.items and inv.items.refreshGetPeriods and inv.items.refreshGetPeriods() > 0 then
                dbot.info("Running initial full scan to check if your inventory was modified outside of this plugin")
                -- inv.items.refresh(0, invItemsRefreshLocAll, nil, nil)
            end
        end
    end
    
    return retval
end

function inv.fini(doSaveState)
    local retval = DRL_RET_SUCCESS
    
    -- De-initialize all inv modules
    for module in inv.modules:gmatch("%S+") do
        if inv[module] and inv[module].fini then
            local finiVal = inv[module].fini(doSaveState)
            if finiVal ~= DRL_RET_SUCCESS and finiVal ~= DRL_RET_UNINITIALIZED then
                dbot.warn("inv.fini: Failed to de-initialize inv." .. module .. " module: " ..
                          dbot.retval.getString(finiVal))
                retval = finiVal
            else
                dbot.debug("De-initialized inv module '" .. module .. "'", "inv.core")
            end
        end
    end
    
    inv.init.initializedInstall = false
    inv.init.initializedActive  = false
    
    return retval
end

function inv.reset(moduleNames, endTag)
    local modules, retval = dbot.wordsToArray(moduleNames or "")
    if retval ~= DRL_RET_SUCCESS or #modules == 0 then
        dbot.warn("inv.reset: missing module names to reset")
        return inv.tags.stop(invTagsReset, endTag, DRL_RET_INVALID_PARAM)
    end

    local numModulesReset = 0
    for _, moduleName in ipairs(modules) do
        if moduleName == "all" then
            modules = {}
            for name in inv.modules:gmatch("%S+") do
                table.insert(modules, name)
            end
            numModulesReset = 0
        end

        if inv[moduleName] and inv[moduleName].reset then
            dbot.note("Resetting module \"@C" .. moduleName .. "@W\"")
            local currentRetval = inv[moduleName].reset()
            if currentRetval ~= DRL_RET_SUCCESS then
                dbot.warn("inv.reset: Failed to reset module \"@C" .. moduleName .. "@W\": " ..
                          dbot.retval.getString(currentRetval))
                retval = currentRetval
            else
                numModulesReset = numModulesReset + 1
            end
        else
            dbot.warn("inv.reset: Attempted to reset invalid module name \"@C" .. moduleName .. "@W\"")
            retval = DRL_RET_INVALID_PARAM
        end
    end

    local suffix = (numModulesReset == 1) and "" or "s"
    dbot.info("Successfully reset " .. numModulesReset .. " module" .. suffix)
    return inv.tags.stop(invTagsReset, endTag, retval or DRL_RET_SUCCESS)
end

function inv.reload(doSaveState)
    local retval = DRL_RET_SUCCESS
    
    -- De-init if already initialized
    if inv.init.initializedInstall or dbot.init.initializedInstall then
        retval = inv.fini(doSaveState)
        if retval ~= DRL_RET_SUCCESS then
            dbot.warn("inv.reload: Failed to de-initialize inventory module: " ..
                      dbot.retval.getString(retval))
        end
    end
    
    -- Re-init at install
    retval = inv.init.atInstall()
    if retval ~= DRL_RET_SUCCESS then
        dbot.warn("inv.reload: Failed to init 'at install' inventory code: " ..
                  dbot.retval.getString(retval))
    end
    
    return retval
end

----------------------------------------------------------------------------------------------------
-- CLI Namespace Setup
----------------------------------------------------------------------------------------------------

inv.cli = inv.cli or {}

----------------------------------------------------------------------------------------------------
-- End of inv core module
----------------------------------------------------------------------------------------------------

dbot.debug("inv core module loaded", "inv.core")
