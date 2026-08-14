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

DRL_RET_SUCCESS = 0
DRL_RET_INVALID_PARAM = -2
dbot = {
    debug = function() end,
    stripColors = function(value) return tostring(value or "") end,
}
DINV = {}

dofile(root .. "/dinv_inv_core.lua")
dofile(root .. "/dinv_triggers.lua")

local aggregate = { stats = {} }
inv.items.identifyContinuation = nil
expect_equal(inv.items.parseIdentifyLine(
    aggregate,
    "| Resist Mods: All physical : +50      All magic    : +50         |"
), DRL_RET_SUCCESS, "aggregate resist parse result")
expect_equal(aggregate.stats.allphys, 50, "all physical resist")
expect_equal(aggregate.stats.allmagic, 50, "all magic resist")
expect_equal(aggregate.stats.magic, nil, "all magic is not individual magic")

local individual = { stats = {} }
inv.items.identifyContinuation = nil
expect_equal(inv.items.parseIdentifyLine(
    individual,
    "| Resist Mods: Acid         :  +7      Magic       :  +9         |"
), DRL_RET_SUCCESS, "individual resist parse result")
expect_equal(individual.stats.acid, 7, "first-column individual resist")
expect_equal(individual.stats.magic, 9, "second-column individual resist")

local stats = { stats = {} }
inv.items.identifyContinuation = nil
expect_equal(inv.items.parseIdentifyLine(
    stats,
    "| Stat Mods  : Hit points   : +400     Damage roll  : +56         |"
), DRL_RET_SUCCESS, "stat mods parse result")
expect_equal(stats.stats.hp, 400, "first-column stat mod")
expect_equal(stats.stats.damroll, 56, "second-column stat mod")

print("DINV identify resistance regression checks passed")
