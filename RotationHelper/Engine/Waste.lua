local ADDON_NAME, ns = ...
local RH = ns.RH

-- Waste warnings: resources going to waste right now, while it can still
-- be fixed. Sets RH.waste = { runes, runicPower, any } every update.
--
--   runes       a rune pair (slots 1-2, 3-4, 5-6) has both runes ready, so
--               that pair's regeneration is lost
--   runicPower  runic power within `rpDeficit` of the maximum
--
-- Only in combat, and only after the cap has lasted `grace` seconds: at the
-- pull every rune is full and nothing can be done about it for a GCD.
local Waste = RH:NewModule("Waste")
ns.Waste = Waste

local PAIRS = { { 1, 2 }, { 3, 4 }, { 5, 6 } }

local result = { runes = false, runicPower = false, any = false }
local cappedSince = { runes = {}, runicPower = nil }

-- Returns true if `key` has been capped for at least `grace` seconds.
local function Held(capped, since, now, grace)
    if not capped then return nil, false end
    since = since or now
    return since, now - since >= grace
end

function Waste:Check(s, settings)
    local now = s.now
    result.runes, result.runicPower = false, false

    if settings.enabled and s.inCombat then
        if settings.runes and RH.classData.usesRunes then
            for i, pair in ipairs(PAIRS) do
                local a, b = s.runes[pair[1]], s.runes[pair[2]]
                local capped = a and b and a.readyAt <= now and b.readyAt <= now
                local wasting
                cappedSince.runes[i], wasting = Held(capped, cappedSince.runes[i], now, settings.grace)
                if wasting then result.runes = true end
            end
        end
        if settings.runicPower and s.powerType == "runic_power" then
            local capped = s.powerMax > 0 and s.power >= s.powerMax - settings.rpDeficit
            cappedSince.runicPower, result.runicPower =
                Held(capped, cappedSince.runicPower, now, settings.grace)
        end
    else
        for i in ipairs(PAIRS) do cappedSince.runes[i] = nil end
        cappedSince.runicPower = nil
    end

    result.any = result.runes or result.runicPower
    return result
end

function Waste:OnEnable()
    if not RH.classSupported then return end
    -- After the recommender, which refreshes the real state.
    RH:RegisterUpdater(function()
        RH.waste = Waste:Check(ns.State.real, RH.db.profile.waste)
    end, RH.UPDATE_ORDER.WASTE, "waste warnings", function() RH.waste = nil end)
end
