local ADDON_NAME, ns = ...
local RH = ns.RH

-- A profile per talent spec (dual spec): switching talents switches the
-- profile, and with it the layout, toggles and custom rotations.
--
-- The mapping is per character: db.char.specProfiles[group] = profile name,
-- for talent group 1 (primary) and 2 (secondary). Groups without a mapping
-- leave the profile alone.
local SpecProfiles = RH:NewModule("SpecProfiles", "AceEvent-3.0")
ns.SpecProfiles = SpecProfiles

local GetActiveTalentGroup, GetNumTalentGroups = GetActiveTalentGroup, GetNumTalentGroups
local GetNumTalentTabs, GetTalentTabInfo = GetNumTalentTabs, GetTalentTabInfo

local GROUP_NAMES = { "Primary talents", "Secondary talents" }

function SpecProfiles:Mapping()
    return RH.db.char.specProfiles
end

local function ProfileExists(name)
    for _, profile in ipairs(RH.db:GetProfiles()) do
        if profile == name then return true end
    end
    return false
end

-- Switches to the profile mapped to the active talent group, if any.
function SpecProfiles:Apply()
    local group = GetActiveTalentGroup and GetActiveTalentGroup() or 1
    local name = self:Mapping()[group]
    if not name or name == RH.db:GetCurrentProfile() then return end
    if not ProfileExists(name) then
        -- SetProfile would quietly recreate it empty; don't.
        self:Mapping()[group] = nil
        RH:Print(("Profile '%s' for your %s no longer exists; not switching."):format(name, GROUP_NAMES[group]:lower()))
        return
    end
    RH.db:SetProfile(name)
    RH:Print(("Switched to profile '%s' for your %s."):format(name, GROUP_NAMES[group]:lower()))
    ns.Options:RefreshIfOpen()
end

-- Sets (or clears, with nil) the profile for a talent group. Setting it for
-- the active group switches right away.
function SpecProfiles:Set(group, name)
    self:Mapping()[group] = name
    local active = GetActiveTalentGroup and GetActiveTalentGroup() or 1
    if group == active then self:Apply() end
end

-- "Primary talents (Frost)": the group's name plus its main tree.
function SpecProfiles:GroupLabel(group)
    local best, bestPoints = nil, 0
    for tab = 1, GetNumTalentTabs() do
        local name, _, points = GetTalentTabInfo(tab, false, false, group)
        if points and points > bestPoints then best, bestPoints = name, points end
    end
    return best and ("%s (%s)"):format(GROUP_NAMES[group], best) or GROUP_NAMES[group]
end

function SpecProfiles:NumGroups()
    return GetNumTalentGroups and GetNumTalentGroups() or 1
end

function SpecProfiles:OnEnable()
    self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", "Apply")
    self:Apply()
end
