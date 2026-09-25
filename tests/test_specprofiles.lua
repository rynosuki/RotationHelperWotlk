local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

-- An addon with a "Frost" and an "Unholy" profile, on the Default one.
local function WithProfiles()
    local s, RH = newAddon()
    local db = RH.db
    db:SetProfile("Unholy")
    db.profile.display.scale = 1.4
    db:SetProfile("Frost")
    db.profile.display.scale = 1.1
    db:SetProfile("Default")
    return s, RH
end

local function SwitchTalents(s, group)
    s.talentGroup = group
    s:FireEvent("ACTIVE_TALENT_GROUP_CHANGED", group, 3 - group)
end

test("switching talents switches to the mapped profile", function()
    local s, RH = WithProfiles()
    local SP = s.ns.SpecProfiles
    SP:Set(1, "Frost") -- the active group: switches now
    eq(RH.db:GetCurrentProfile(), "Frost", "switched right away")
    SP:Set(2, "Unholy")
    eq(RH.db:GetCurrentProfile(), "Frost", "other group: no switch yet")
    s:ClearChat()
    SwitchTalents(s, 2)
    eq(RH.db:GetCurrentProfile(), "Unholy", "secondary talents")
    eq(RH.db.profile.display.scale, 1.4, "its settings")
    truthy(s:ChatContains("Switched to profile 'Unholy' for your secondary talents"), "told")
    SwitchTalents(s, 1)
    eq(RH.db:GetCurrentProfile(), "Frost", "back")
end)

test("an unmapped spec leaves the profile alone", function()
    local s, RH = WithProfiles()
    s.ns.SpecProfiles:Set(2, "Unholy")
    RH.db:SetProfile("Frost")
    SwitchTalents(s, 1) -- primary has no mapping
    eq(RH.db:GetCurrentProfile(), "Frost", "unchanged")
end)

test("a deleted profile isn't recreated empty", function()
    local s, RH = WithProfiles()
    local SP = s.ns.SpecProfiles
    SP:Set(2, "Unholy")
    RH.db:DeleteProfile("Unholy")
    s:ClearChat()
    SwitchTalents(s, 2)
    eq(RH.db:GetCurrentProfile(), "Default", "not switched")
    eq(SP:Mapping()[2], nil, "mapping cleared")
    truthy(s:ChatContains("'Unholy' for your secondary talents no longer exists"), "told why")
    for _, name in ipairs(RH.db:GetProfiles()) do
        falsy(name == "Unholy", "not recreated")
    end
end)

test("the mapping is applied at login", function()
    local s, RH = WithProfiles()
    s.ns.SpecProfiles:Mapping()[1] = "Frost"
    s.ns.SpecProfiles:OnEnable()
    eq(RH.db:GetCurrentProfile(), "Frost", "applied")
end)

test("profiles tab: a dropdown per talent group", function()
    local s, RH = WithProfiles()
    local args = s.ns.Options:GetOptionsTable().args.profiles.args
    eq(args.specPrimary.name(), "Primary talents (Frost)", "label names the main tree")
    local choices = args.specPrimary.values()
    eq(choices[""], "Don't switch", "no-switch choice")
    eq(choices.Unholy, "Unholy", "profiles listed")
    eq(args.specSecondary.get(), "", "unset")
    args.specSecondary.set(nil, "Unholy")
    eq(s.ns.SpecProfiles:Mapping()[2], "Unholy", "set")
    args.specSecondary.set(nil, "")
    eq(s.ns.SpecProfiles:Mapping()[2], nil, "cleared")
    falsy(args.specSecondary.disabled(), "dual spec: enabled")
    s.numTalentGroups = 1
    truthy(args.specSecondary.disabled(), "no dual spec: disabled")
    truthy(args.specInfo.name():find("Learn Dual Talent Specialization"), "hint")
end)

test("the options table still validates with the new section", function()
    local s = newAddon()
    local registry = s.env.LibStub("AceConfigRegistry-3.0")
    local ok, err = pcall(registry.ValidateOptionsTable, registry, s.ns.Options:GetOptionsTable(), "RotationHelper")
    truthy(ok, tostring(err))
end)
