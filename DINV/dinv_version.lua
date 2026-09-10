----------------------------------------------------------------------------------------------------
-- DINV Version
-- Single source of truth for DINV version
----------------------------------------------------------------------------------------------------

DINV = DINV or {}
DINV.version = type(DINV.version) == "table" and DINV.version or {}
DINV.version.major = 2
DINV.version.minor = 81

setmetatable(DINV.version, {
    __tostring = function(t)
        return string.format("%d.%04d", t.major or 0, t.minor or 0)
    end,
    __concat = function(a, b)
        return tostring(a) .. tostring(b)
    end,
})

inv = inv or {}
inv.version = DINV.version
