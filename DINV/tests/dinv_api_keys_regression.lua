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

dbot = {
    debug = function() end,
    stripColors = function(value)
        return tostring(value or ""):gsub("@.", "")
    end,
}

invItemWornNotWorn = "not-worn"
invItemLocInventory = "inventory"
invItemLocKeyring = "keyring"
inv = {
    init = {initializedActive = true},
    items = {
        table = {
            ["1"] = {stats = {
                name = "the Crest of Wood", colorName = "@Gthe Crest of Wood",
                type = "Armor", flags = "magic, V3, iskey", location = "keyring",
                identifyLevel = "full", keywords = "crest wood shield",
            }},
            ["2"] = {stats = {
                name = "a brass sigil", type = "Treasure", flags = "glow isKey",
                location = "inventory", identifyLevel = "full", keywords = "brass sigil",
            }},
            ["3"] = {stats = {
                name = "a typed key", type = "Key", flags = "magic",
                location = "inventory", identifyLevel = "full", keywords = "typed key",
            }},
            ["4"] = {stats = {
                name = "a false key", type = "Armor", flags = "notiskey",
                location = "inventory",
            }},
            ["5"] = {stats = {
                name = "  THE   CREST OF WOOD  ", type = "Shield", flags = "isKey",
                location = "12345", container = "12345", identifyLevel = "full",
                keywords = "different crest token set",
            }},
            ["6"] = {stats = {
                name = "a small key", type = "Key", flags = "magic",
                location = "keyring", identifyLevel = "full",
                keywords = "eternal damnation small key",
            }},
            ["7"] = {stats = {
                name = "a small key", type = "Key", flags = "magic",
                location = "keyring", identifyLevel = "full",
                keywords = "academy cellar small key",
            }},
            ["8"] = {stats = {
                name = "a small key", type = "Key", flags = "magic",
                location = "inventory", identifyLevel = "partial",
                keywords = "eternal damnation small key",
            }},
        },
    },
}

DINV = nil
dofile(root .. "/dinv_api.lua")

local all = DINV.api.getKeys({source = "live"})
assert(all.ok, tostring(all.message))
expect_equal(all.keyDefinition, "isKeyOrTypeKey", "key definition")
expect_equal(all.count, 7, "all isKey or Type Key items across types and locations")

local exact = DINV.api.getKeys({source = "live", exactName = "the Crest of Wood"})
assert(exact.ok, tostring(exact.message))
expect_equal(exact.exactNameApplied, true, "exact name marker")
expect_equal(exact.exactName, "the crest of wood", "normalized requested name")
expect_equal(exact.count, 2, "exact normalized duplicate names")

local typed = DINV.api.getKeys({source = "live", exactName = "a typed key"})
assert(typed.ok, tostring(typed.message))
expect_equal(typed.count, 1, "Type Key without isKey flag")

local absent = DINV.api.getKeys({source = "live", exactName = "a missing key"})
assert(absent.ok, tostring(absent.message))
expect_equal(absent.count, 0, "missing exact key")

local exact_keywords = DINV.api.getKeys({
    source = "live", exactKeywords = "small key damnation eternal",
})
assert(exact_keywords.ok, tostring(exact_keywords.message))
expect_equal(exact_keywords.exactKeywordsApplied, true, "exact keyword marker")
expect_equal(exact_keywords.keywordDefinition, "exactFullIdentifyTokenSet", "keyword definition")
expect_equal(exact_keywords.exactKeywords, "damnation eternal key small", "canonical keyword set")
expect_equal(exact_keywords.count, 1, "same-name keys are disambiguated by full keywords")
expect_equal(exact_keywords.items[1].id, "6", "matching full-identified key")

print("DINV getKeys regression checks passed")
