local ADDON_NAME, ns = ...

local Utils = {}
ns.Utils = Utils

local floor, format, tostring, type, pairs = math.floor, string.format, tostring, type, pairs
local wipe = wipe

---------------------------------------------------------------------------
-- Table pool: reuse tables in the hot path to avoid GC churn on 3.3.5.
---------------------------------------------------------------------------
local pool = {}
local poolSize = 0

function Utils.Acquire()
    if poolSize > 0 then
        local t = pool[poolSize]
        pool[poolSize] = nil
        poolSize = poolSize - 1
        return t
    end
    return {}
end

function Utils.Release(t)
    if type(t) ~= "table" then return end
    wipe(t)
    poolSize = poolSize + 1
    pool[poolSize] = t
end

function Utils.PoolSize()
    return poolSize
end

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------
function Utils.Round(n, decimals)
    local m = 10 ^ (decimals or 0)
    return floor(n * m + 0.5) / m
end

-- 0.53 -> "0.5", 12.3 -> "12", 75 -> "1:15"
function Utils.FormatTime(sec)
    if not sec or sec <= 0 then return "0" end
    if sec < 10 then return format("%.1f", sec) end
    if sec < 60 then return format("%d", floor(sec)) end
    return format("%d:%02d", floor(sec / 60), floor(sec % 60))
end

function Utils.Colorize(text, hex)
    return "|cff" .. hex .. tostring(text) .. "|r"
end

function Utils.OnOff(value)
    return value and Utils.Colorize("ON", "40ff40") or Utils.Colorize("OFF", "ff4040")
end

-- "Blood of the North" -> "blood_of_the_north", "Glyph of Frost Strike" -> "glyph_of_frost_strike"
function Utils.Key(name)
    if not name then return nil end
    return (name:lower():gsub("'", ""):gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", ""))
end

-- Shallow key count, handy for debug output.
function Utils.Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end
