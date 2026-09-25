local ADDON_NAME, ns = ...
local Utils = ns.Utils

-- Reads the class's tracked auras into state.buffs (player) and
-- state.debuffs (target). Each entry is keyed by the aura's key in the
-- class data and looks like:
--   { spellId, stacks, duration, expires }   (expires = math.huge if permanent)
-- Auras that aren't up have no entry.
local Auras = {}
ns.Auras = Auras

local UnitAura, GetSpellInfo = UnitAura, GetSpellInfo
local pairs, ipairs, huge = pairs, ipairs, math.huge

local MAX_AURAS = 40

-- Lookup tables: spell ID or localized name -> aura key.
local function BuildIndex(classData)
    local index = {
        buff = { byId = {}, byName = {} },
        debuff = { byId = {}, byName = {} },
    }
    for key, def in pairs(classData.auras) do
        local lookup = def.debuff and index.debuff or index.buff
        for _, id in ipairs(def.ids or { def.id }) do
            lookup.byId[id] = key
            local name = GetSpellInfo(id)
            if name then lookup.byName[name] = key end
        end
    end
    return index
end

local function Clear(list)
    for key, rec in pairs(list) do
        Utils.Release(rec)
        list[key] = nil
    end
end

local function ReadUnit(list, unit, filter, lookup, defs)
    Clear(list)
    for i = 1, MAX_AURAS do
        local name, _, _, count, _, duration, expires, caster, _, _, spellId = UnitAura(unit, i, filter)
        if not name then break end
        local key = (spellId and lookup.byId[spellId]) or lookup.byName[name]
        if key and not list[key] then
            local def = defs[key]
            if not def.debuff or def.anySource or caster == "player" then
                local rec = Utils.Acquire()
                rec.spellId = spellId
                rec.stacks = (count and count > 0) and count or 1
                rec.duration = duration or 0
                rec.expires = (expires and expires > 0) and expires or huge
                list[key] = rec
            end
        end
    end
end

function Auras.Read(state, classData)
    if not classData.auraIndex then
        classData.auraIndex = BuildIndex(classData)
    end
    local index = classData.auraIndex
    ReadUnit(state.buffs, "player", "HELPFUL", index.buff, classData.auras)
    ReadUnit(state.debuffs, "target", "HARMFUL", index.debuff, classData.auras)
end

-- Seconds left on an aura entry, 0 if missing.
function Auras.Remains(rec, now)
    if not rec then return 0 end
    local r = rec.expires - now
    return r > 0 and r or 0
end
