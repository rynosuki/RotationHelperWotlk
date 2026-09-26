local ADDON_NAME, ns = ...
local RH = ns.RH

-- Burst windows: while a notable damage buff is up, cooldowns that
-- snapshot your stats (Summon Gargoyle) are worth more. Rotations read
-- burst.active and burst.remains.
--
-- Buffs are matched by name (enUS, as on Whitemane): one name covers every
-- rank and the normal and heroic versions of a trinket proc. More names or
-- spell IDs can be added in the options (profile.burst.extra).
local Burst = {}
ns.Burst = Burst

local UnitAura, tonumber, huge = UnitAura, tonumber, math.huge

Burst.DEFAULT_NAMES = {
    "Bloodlust", "Heroism",                -- raid haste
    "Hyperspeed Acceleration",             -- engineering gloves
    "Berserking", "Blood Fury",            -- racials
    "Hysteria",                            -- Blood Death Knight
    "Speed",                               -- Potion of Speed
    "Unholy Strength",                     -- Rune of the Fallen Crusader
    "Greatness",                           -- Darkmoon Card: Greatness
    "Paragon",                             -- Death's Verdict / Death's Choice
    "Strength of the Taunka", "Aim of the Iron Dwarves", "Speed of the Vrykul", -- Deathbringer's Will
    "Icy Rage",                            -- Whispering Fanged Skull
    -- Anything else: add its name or spell ID in the options.
}

local names, ids = {}, {}

-- Rebuilds the lookup from the defaults plus the profile's extra entries
-- ("Some Buff, 12345, ...").
function Burst:Rebuild()
    for k in pairs(names) do names[k] = nil end
    for k in pairs(ids) do ids[k] = nil end
    for _, name in ipairs(self.DEFAULT_NAMES) do names[name] = true end
    local extra = RH.db and RH.db.profile.burst.extra or ""
    for entry in extra:gmatch("[^,]+") do
        entry = entry:gsub("^%s+", ""):gsub("%s+$", "")
        local id = tonumber(entry)
        if id then ids[id] = true elseif entry ~= "" then names[entry] = true end
    end
    self.built = true
end

-- Seconds left on the longest burst buff on the player (0 if none).
function Burst:Remains(now)
    if not self.built then self:Rebuild() end
    local best = 0
    for i = 1, 40 do
        local name, _, _, _, _, _, expires, _, _, _, spellId = UnitAura("player", i, "HELPFUL")
        if not name then break end
        if names[name] or (spellId and ids[spellId]) then
            local remains = (expires and expires > 0) and (expires - now) or huge
            if remains > best then best = remains end
        end
    end
    return best
end
