local ADDON_NAME, ns = ...
local RH = ns.RH

-- Threat warning: in a group, close to (or over) the threat needed to pull
-- the target off the tank. Sets RH.threat = { warn, percent } every update.
-- Solo you're always "tanking", so there's no warning then.
local Threat = RH:NewModule("Threat")
ns.Threat = Threat

local UnitExists, UnitCanAttack, UnitDetailedThreatSituation = UnitExists, UnitCanAttack, UnitDetailedThreatSituation
local GetNumPartyMembers, GetNumRaidMembers = GetNumPartyMembers, GetNumRaidMembers

local result = { warn = false, percent = nil }

function Threat:Check(settings)
    result.warn, result.percent = false, nil
    if not settings.enabled then return result end
    if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then return result end
    if not (UnitExists("target") and UnitCanAttack("player", "target")) then return result end
    -- 3.3.5: isTanking, status, scaledPercent, rawPercent, threatValue.
    -- scaledPercent reaches 100 when you'd pull aggro.
    local isTanking, _, scaledPercent = UnitDetailedThreatSituation("player", "target")
    if scaledPercent then
        result.percent = scaledPercent
        result.warn = isTanking or scaledPercent >= settings.threshold
    end
    return result
end

function Threat:OnEnable()
    if not RH.classSupported then return end
    RH:RegisterUpdater(function() RH.threat = Threat:Check(RH.db.profile.threat) end,
        RH.UPDATE_ORDER.THREAT, "threat warning", function() RH.threat = nil end)
end
