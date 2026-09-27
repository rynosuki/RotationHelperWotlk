local ADDON_NAME, ns = ...
local RH = ns.RH

-- Waste warnings: resources going to waste right now, while it can still
-- be fixed. Sets RH.waste = { runes, power, powerLabel, any } every update.
--
--   runes       a rune pair (slots 1-2, 3-4, 5-6) has both runes ready, so
--               that pair's regeneration is lost (Death Knights)
--   power       runic power, energy or rage within `powerDeficit` of the
--               maximum; powerLabel says which ("RP", "ENERGY", "RAGE")
--
-- Only in combat, and only after the cap has lasted `grace` seconds: at the
-- pull every rune is full and nothing can be done about it for a GCD. Mana
-- isn't warned about: sitting at full mana wastes nothing.
local Waste = RH:NewModule("Waste", "AceEvent-3.0")
ns.Waste = Waste

local PAIRS = { { 1, 2 }, { 3, 4 }, { 5, 6 } }

-- Power types that are wasted at the cap, and their status-line label.
Waste.POWER_LABELS = { runic_power = "RP", energy = "ENERGY", rage = "RAGE" }
local POWER_LABELS = Waste.POWER_LABELS

local result = { runes = false, power = false, powerLabel = nil, any = false }
local cappedSince = { runes = {}, power = nil }

-- Returns true if `key` has been capped for at least `grace` seconds.
local function Held(capped, since, now, grace)
    if not capped then return nil, false end
    since = since or now
    return since, now - since >= grace
end

function Waste:Check(s, settings)
    local now = s.now
    result.runes, result.power = false, false
    result.powerLabel = POWER_LABELS[s.powerType]

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
        if settings.power and result.powerLabel then
            local capped = s.powerMax > 0 and s.power >= s.powerMax - settings.powerDeficit
            cappedSince.power, result.power = Held(capped, cappedSince.power, now, settings.grace)
        end
    else
        for i in ipairs(PAIRS) do cappedSince.runes[i] = nil end
        cappedSince.power = nil
    end

    result.any = result.runes or result.power
    return result
end

-- Settings saved before 1.38 called the power warning runicPower / rpDeficit.
function Waste.Migrate(settings)
    if settings.runicPower ~= nil then
        settings.power, settings.runicPower = settings.runicPower, nil
    end
    if settings.rpDeficit ~= nil then
        settings.powerDeficit, settings.rpDeficit = settings.rpDeficit, nil
    end
end

function Waste:OnEnable()
    Waste.Migrate(RH.db.profile.waste)
    self:RegisterMessage("ROTATIONHELPER_CONFIG_CHANGED", function() Waste.Migrate(RH.db.profile.waste) end)
    if not RH.classSupported then return end
    -- After the recommender, which refreshes the real state.
    RH:RegisterUpdater(function()
        RH.waste = Waste:Check(ns.State.real, RH.db.profile.waste)
    end, RH.UPDATE_ORDER.WASTE, "waste warnings", function() RH.waste = nil end)
end
