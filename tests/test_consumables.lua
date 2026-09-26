-- The consumables toggle (POT): potions only when allowed, bosses only by default.
local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

-- In combat with a target, Bloodlust up (so the potion line wants to fire),
-- Potion of Speed in the bags, cooldowns on.
local function Fight()
    local s, RH = newAddon()
    s:Learn("Icy Touch", "Plague Strike", "Obliterate", "Frost Strike", "Howling Blast", "Blood Strike",
        "Horn of Winter", "Death Coil")
    s.hasTarget = true
    s:FireEvent("PLAYER_REGEN_DISABLED")
    s:Slash("ACECONSOLE_RH", "lock")
    RH.db.profile.toggles.cooldowns = true
    s.bags[40211] = 2
    s:FireEvent("BAG_UPDATE")
    s:AddAura("target", { name = "Frost Fever", spellId = 55095, duration = 15, expires = s.time + 900, harmful = true })
    s:AddAura("target", { name = "Blood Plague", spellId = 55078, duration = 15, expires = s.time + 900, harmful = true })
    s:AddAura("player", { name = "Horn of Winter", spellId = 57623, duration = 120, expires = s.time + 900 })
    s:AddAura("player", { name = "Bloodlust", spellId = 2825, duration = 40, expires = s.time + 40 })
    return s, RH
end

local function First(s)
    s:Tick(0.1)
    local recs = s.env.RotationHelper.recommendations
    return recs and recs[1].name
end

local function Trash(s)
    s.target.level, s.target.classification = 80, "elite"
end

test("potions only against bosses by default", function()
    local s, RH = Fight()
    eq(First(s), "potion", "boss targeted (skull level)")
    Trash(s)
    falsy(First(s) == "potion", "trash pull: no potion")
    s.bossFrames = true
    eq(First(s), "potion", "an add targeted while boss frames are up")
    s.bossFrames = false
    s.target.level, s.target.classification = 83, "worldboss"
    eq(First(s), "potion", "worldboss classification")
end)

test("the toggle turns them off; 'only against bosses' can be turned off", function()
    local s, RH = Fight()
    s:Slash("ACECONSOLE_RH", "pots")
    eq(RH.db.profile.toggles.consumables, false, "/rh pots")
    falsy(First(s) == "potion", "off: no potion on the boss")
    s:Slash("ACECONSOLE_RH", "pots")
    Trash(s)
    local args = s.ns.Options:GetOptionsTable().args.general.args
    args.consumablesBossOnly.set(nil, false)
    eq(First(s), "potion", "everywhere")
    truthy(s.env.BINDING_NAME_ROTATIONHELPER_TOGGLE_CONSUMABLES, "key binding")
end)

test("toggle.consumables in rotations", function()
    local s, RH = Fight()
    local resolve = s.ns.Expressions.CreateResolver(s.env.RotationHelper.classData)
    local fn = s.ns.APL.Compiler.CompileExpression("toggle.consumables", resolve)
    eq(fn(s.ns.State:Reset()), 1, "boss")
    Trash(s)
    eq(fn(s.ns.State:Reset()), 0, "trash")
end)

test("POT chip: green on a boss, yellow waiting for one, red when off; click toggles", function()
    local s, RH = Fight()
    local D = s.ns.Display
    First(s)
    eq(D.frame.potChip.text:GetText(), "|cff40ff40POT|r", "green")
    eq(D:GetStatusText(), "CD  POT", "status line")
    Trash(s)
    First(s)
    eq(D.frame.potChip.text:GetText(), "|cffffd100POT|r", "yellow")
    D.frame.potChip.scripts.OnClick(D.frame.potChip)
    First(s)
    eq(D.frame.potChip.text:GetText(), "|cffff4040POT|r", "red")
    s.bags[40211] = nil
    s:FireEvent("BAG_UPDATE")
    First(s)
    falsy(D.frame.potChip:IsShown(), "no potions: no chip")
end)
