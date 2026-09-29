-- While you cast or channel, the main icon shows that spell (greyed, with
-- its progress and time left) and the next action moves to the first
-- queue icon, with a gold border, the countdown and the flash.
local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local CAST_ICON = "Interface\\Icons\\Spell_Fire_Burnout"

local function Fight()
    local s, RH = newAddon({ class = "WARLOCK" })
    s.talentTabs = {
        { name = "Affliction", talents = {} },
        { name = "Demonology", talents = {} },
        { name = "Destruction", talents = { { "Bane", 5 }, { "Conflagrate", 1 }, { "Chaos Bolt", 1 } } },
    }
    s.power = { type = 0, current = 20000, max = 20000 }
    s:Learn("Immolate", "Conflagrate", "Chaos Bolt", "Incinerate", "Curse of Doom", "Curse of Agony", "Corruption",
        "Shadow Bolt", "Life Tap", "Fel Armor")
    s.hasTarget = true
    s:FireEvent("PLAYER_TALENT_UPDATE")
    s:FireEvent("PLAYER_REGEN_DISABLED")
    RH.db.profile.display.locked = true
    RH.db.profile.toggles.cooldowns = false
    s:AddAura("player", { name = "Fel Armor", spellId = 47893, duration = 1800, expires = s.time + 1800 })
    s:AddAura("target", { name = "Immolate", spellId = 47811, duration = 15, expires = s.time + 12, harmful = true })
    s:AddAura("target", { name = "Curse of Doom", spellId = 47867, duration = 60, expires = s.time + 50, harmful = true })
    s.cooldowns["Conflagrate"] = { s.time, 10 }
    s.cooldowns["Chaos Bolt"] = { s.time, 12 }
    RH:OnConfigChanged()
    return s, RH
end

local function Icon(D, i) return D.buttons[i]:IsShown() and D.buttons[i].icon:GetTexture() or nil end

test("not casting: the main icon is the next action, no border", function()
    local s, RH = Fight()
    s:Tick(0.1)
    local D = s.ns.Display
    eq(D.offset, 0, "no offset")
    eq(D.primary, D.buttons[1], "main icon is next")
    truthy(Icon(D, 1), "main icon shown")
    falsy(D.buttons[2].nextBorder:IsShown(), "no border")
end)

test("casting: the cast on the main icon, next beside it with a gold border", function()
    local s, RH = Fight()
    s:Tick(0.1)
    local D = s.ns.Display
    local nextIcon = Icon(D, 1)
    local secondIcon = Icon(D, 2)
    s.playerCast = { name = "Incinerate", startedAgo = 0.5, endsIn = 1.5, icon = CAST_ICON }
    s:Tick(0.1)
    eq(D.offset, 1, "shifted")
    eq(Icon(D, 1), CAST_ICON, "your cast on the main icon")
    truthy(D.buttons[1].cooldown:IsShown(), "progress sweep")
    eq(D.buttons[1].key:GetText(), "", "no keybind on the cast")
    eq(D.buttons[1].hold:GetText(), "1.5", "time left (the mock ends it 1.5s after the read)")
    eq(D.primary, D.buttons[2], "next is the first queue icon")
    truthy(D.buttons[2].nextBorder:IsShown(), "gold border")
    eq(Icon(D, 2), nextIcon, "the same next action as before the cast")
    eq(Icon(D, 3), secondIcon, "the queue moved along")
    truthy(D.buttons[2].cooldown:IsShown(), "the countdown is on the next icon")
    truthy(D.buttons[4]:IsShown(), "your cast + 3 queued")
    falsy(D.buttons[5]:IsShown(), "still 4 icons in total")
    -- The cast ends: back to normal.
    s.playerCast = nil
    s:Tick(0.1)
    eq(D.offset, 0, "back")
    eq(Icon(D, 1), nextIcon, "next on the main icon again")
    falsy(D.buttons[2].nextBorder:IsShown(), "no border")
end)

test("channels too; the tooltips follow the shift", function()
    local s, RH = Fight()
    s.playerChannel = { name = "Drain Life", startedAgo = 1, endsIn = 4, icon = CAST_ICON }
    s:Tick(0.1)
    local D = s.ns.Display
    eq(D.offset, 1, "channel shown")
    eq(Icon(D, 1), CAST_ICON, "channel icon")
    local shown
    local GameTooltip = s.env.GameTooltip
    local orig = GameTooltip.SetHyperlink
    GameTooltip.SetHyperlink = function(tt, link) shown = link; if orig then return orig(tt, link) end end
    D:ShowTooltip(D.buttons[2], 2)
    eq(shown, "spell:" .. RH.recommendations[1].spellId, "icon 2 explains the next action")
end)

test("off, timeline mode or a single icon: no cast on the main icon", function()
    local s, RH = Fight()
    s.playerCast = { name = "Incinerate", startedAgo = 0.5, endsIn = 1.5, icon = CAST_ICON }
    local D = s.ns.Display
    RH.db.profile.display.castSlot = false
    RH:OnConfigChanged()
    s:Tick(0.1)
    eq(D.offset, 0, "setting off")
    RH.db.profile.display.castSlot = true
    RH.db.profile.display.timeline = true
    RH:OnConfigChanged()
    s:Tick(0.1)
    eq(D.offset, 0, "timeline")
    RH.db.profile.display.timeline = false
    RH.db.profile.display.numIcons = 1
    RH:OnConfigChanged()
    s:Tick(0.1)
    eq(D.offset, 0, "one icon")
    RH.db.profile.display.numIcons = 4
    RH:OnConfigChanged()
    s:Tick(0.1)
    eq(D.offset, 1, "on again")
end)
