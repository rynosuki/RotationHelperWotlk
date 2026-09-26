-- E1-E4: pre-pull checklist, pull timer, trinkets/racials/potions, burst windows.
local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local function near(actual, expected, what)
    if type(actual) ~= "number" or math.abs(actual - expected) > 1e-6 then
        error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
    end
end

local FROST = { "Icy Touch", "Plague Strike", "Obliterate", "Frost Strike", "Howling Blast", "Blood Strike",
    "Horn of Winter", "Death Coil" }

local function Eval(s, text)
    local resolve = s.ns.Expressions.CreateResolver(s.env.RotationHelper.classData)
    local fn, message = s.ns.APL.Compiler.CompileExpression(text, resolve)
    if not fn then error("compile failed: " .. message, 2) end
    return fn(s.ns.State:Reset())
end

local function Recommend(s)
    local st = s.ns.State:Reset()
    local action, t = s.ns.Recommender:Evaluate(st)
    if not action then return nil end
    local wait = t - st.now
    if wait < 1e-9 then return action.name end
    return ("%s +%.1f"):format(action.name, wait)
end

-- Out of combat, a boss targeted.
local function BeforePull()
    local s, RH = newAddon()
    s:Learn(unpack(FROST))
    s.hasTarget = true
    RH.db.profile.toggles.cooldowns = true
    s:Tick(0.1)
    return s, RH
end

-- In combat with diseases and Horn up.
local function Fight()
    local s, RH = newAddon()
    s:Learn(unpack(FROST))
    s.hasTarget = true
    s:FireEvent("PLAYER_REGEN_DISABLED")
    RH.db.profile.toggles.cooldowns = true
    s:AddAura("target", { name = "Frost Fever", spellId = 55095, duration = 15, expires = s.time + 900, harmful = true })
    s:AddAura("target", { name = "Blood Plague", spellId = 55078, duration = 15, expires = s.time + 900, harmful = true })
    s:AddAura("player", { name = "Horn of Winter", spellId = 57623, duration = 120, expires = s.time + 900 })
    return s, RH
end

local function Missing(RH) return RH.checklist and table.concat(RH.checklist, ", ") or "nothing" end

---------------------------------------------------------------------------
-- E1 Pre-pull checklist
---------------------------------------------------------------------------
test("checklist: lists what's missing before a boss", function()
    local s, RH = BeforePull()
    eq(Missing(RH), "Flask, Food, Horn of Winter, Blood Presence", "nothing up")
    local text = s.ns.Display.frame.checklist
    truthy(text:IsShown(), "shown under the icons")
    eq(text:GetText(), "Missing: Flask, Food, Horn of Winter, Blood Presence", "text")

    s:AddAura("player", { name = "Flask of Endless Rage", spellId = 53760, duration = 3600, expires = s.time + 3600 })
    s:AddAura("player", { name = "Well Fed", spellId = 57371, duration = 3600, expires = s.time + 3600 })
    s:AddAura("player", { name = "Horn of Winter", spellId = 57623, duration = 120, expires = s.time + 120 })
    s:AddAura("player", { name = "Blood Presence", spellId = 48266, duration = 0, expires = 0 })
    s:Tick(0.1)
    eq(Missing(RH), "nothing", "all up")
    falsy(text:IsShown(), "hidden")
end)

test("checklist: elixirs and Strength of Earth count, presence can be skipped", function()
    local s, RH = BeforePull()
    s:AddAura("player", { name = "Elixir of Mighty Strength", spellId = 53748, duration = 3600, expires = s.time + 3600 })
    s:AddAura("player", { name = "Strength of Earth", spellId = 58643, duration = 0, expires = 0 })
    RH.db.profile.prepull.presence.frost = "any"
    s:Tick(0.1)
    eq(Missing(RH), "Food", "only food")
    RH.db.profile.prepull.presence.frost = "unholy"
    s:Tick(0.1)
    eq(Missing(RH), "Food, Unholy Presence", "another presence")
end)

test("checklist: only out of combat, only for bosses and elites, can be turned off", function()
    local s, RH = BeforePull()
    truthy(RH.checklist, "boss")
    s.target.level, s.target.classification = 80, "normal"
    s:Tick(0.1)
    falsy(RH.checklist, "normal mob")
    s.target.classification = "elite"
    s:Tick(0.1)
    truthy(RH.checklist, "elite")
    s:FireEvent("PLAYER_REGEN_DISABLED")
    s:Tick(0.1)
    falsy(RH.checklist, "in combat")
    s:FireEvent("PLAYER_REGEN_ENABLED")
    RH.db.profile.prepull.enabled = false
    s:Tick(0.1)
    falsy(RH.checklist, "turned off")
end)

---------------------------------------------------------------------------
-- E2 Pull timer
---------------------------------------------------------------------------
test("pull timer: DBM and BigWigs messages start it, other addons don't", function()
    local s, RH = BeforePull()
    eq(Eval(s, "pull.active"), 0, "no timer")
    eq(Eval(s, "pull.remains"), 0, "no timer: 0")
    s:FireEvent("CHAT_MSG_ADDON", "SomeAddon", "pull 10", "RAID", "Someone")
    eq(Eval(s, "pull.active"), 0, "ignored")
    s:FireEvent("CHAT_MSG_ADDON", "DBMv4-Pizza", "10\tPull in", "RAID", "Tank")
    eq(Eval(s, "pull.active"), 1, "DBM")
    near(Eval(s, "pull.remains"), 10, "DBM remains")
    s.time = s.time + 4
    near(Eval(s, "pull.remains"), 6, "counts down")
    s:FireEvent("CHAT_MSG_ADDON", "BigWigs", "T:BWPull 15", "RAID", "Tank")
    near(Eval(s, "pull.remains"), 15, "BigWigs restarts it")
    s:FireEvent("CHAT_MSG_ADDON", "DBMv4-Pizza", "0\tPull in", "RAID", "Tank")
    eq(Eval(s, "pull.active"), 0, "0 cancels")
end)

test("pull timer: /rh pull, lingers briefly, ends with combat", function()
    local s, RH = BeforePull()
    s:Slash("ACECONSOLE_RH", "pull 5")
    near(Eval(s, "pull.remains"), 5, "/rh pull 5")
    s.time = s.time + 6
    eq(Eval(s, "pull.active"), 1, "still active just after 0")
    eq(Eval(s, "pull.remains"), 0, "remains 0")
    s.time = s.time + 2
    eq(Eval(s, "pull.active"), 0, "gone after a moment")

    s:Slash("ACECONSOLE_RH", "pull 10")
    s:FireEvent("PLAYER_REGEN_DISABLED")
    eq(Eval(s, "pull.active"), 0, "combat ends it")
    s:ClearChat()
    s:Slash("ACECONSOLE_RH", "pull 99")
    truthy(s.chat[1] and s.chat[1]:find("Usage"), "bad value")
end)

test("pull timer: Army of the Dead about 10s out, a potion at the pull", function()
    local s, RH = BeforePull()
    s:Learn("Army of the Dead")
    s.bags[40211] = 2
    s:FireEvent("BAG_UPDATE")
    s:AddAura("player", { name = "Horn of Winter", spellId = 57623, duration = 120, expires = s.time + 120 })
    local recommendation = Recommend(s)
    falsy(recommendation == "army_of_the_dead" or recommendation == "potion", "no timer: " .. tostring(recommendation))
    s:Slash("ACECONSOLE_RH", "pull 12")
    falsy(Recommend(s) == "army_of_the_dead", "not yet at 12s")
    s.time = s.time + 2
    eq(Recommend(s), "army_of_the_dead", "at 10s")
    s.time = s.time + 9
    eq(Recommend(s), "potion", "at 1s")
end)

---------------------------------------------------------------------------
-- E3 Trinkets, racials, potions
---------------------------------------------------------------------------
test("items: trinkets with a use effect, the best potion in the bags", function()
    local s, RH = newAddon()
    s.items[50000] = { "Some Trinket", "Interface\\Icons\\Trinket", "Some Use" }
    s.items[50001] = { "Passive Trinket", "i" }
    s.equipped[13], s.equipped[14] = 50000, 50001
    s:FireEvent("PLAYER_EQUIPMENT_CHANGED")
    local abilities, known = RH.classData.abilities, s.ns.Spec.known
    truthy(known.trinket1, "trinket1 has a use effect")
    eq(abilities.trinket1.name, "Some Trinket", "name")
    eq(abilities.trinket1.icon, "Interface\\Icons\\Trinket", "icon")
    falsy(known.trinket2, "trinket2 is passive")
    falsy(known.potion, "no potion")

    s.bags[40093] = 1
    s:FireEvent("BAG_UPDATE")
    eq(abilities.potion.name, "Indestructible Potion", "the only potion")
    s.bags[40211] = 3
    s:FireEvent("BAG_UPDATE")
    eq(abilities.potion.name, "Potion of Speed", "Speed first")
    s.bags[40211], s.bags[40093] = nil, nil
    s:FireEvent("BAG_UPDATE")
    falsy(known.potion, "all used")
end)

test("items: trinket and potion cooldowns come from the client", function()
    local s, RH = newAddon()
    s.items[50000] = { "Some Trinket", "i", "Some Use" }
    s.equipped[13] = 50000
    s.bags[40211] = 1
    s:FireEvent("PLAYER_EQUIPMENT_CHANGED")
    s.itemCooldowns[50000] = { s.time - 20, 120 }
    local st = s.ns.State:Reset()
    near(st.cooldowns.trinket1.readyAt, s.time + 100, "trinket")
    -- A potion used in combat stays unusable until combat ends (enabled = 0).
    s.itemCooldowns[40211] = { s.time, 0, 0 }
    st = s.ns.State:Reset()
    eq(st.cooldowns.potion.readyAt, math.huge, "potion locked")
end)

test("items: used in the rotation when cooldowns are on", function()
    local s, RH = Fight()
    s.items[50000] = { "Some Trinket", "i", "Some Use" }
    s.equipped[13] = 50000
    s:FireEvent("PLAYER_EQUIPMENT_CHANGED")
    eq(Recommend(s), "trinket1", "trinket")
    s.itemCooldowns[50000] = { s.time, 120 }
    falsy(Recommend(s) == "trinket1", "on cooldown")
    RH.db.profile.toggles.cooldowns = false
    s.itemCooldowns[50000] = nil
    falsy(Recommend(s) == "trinket1", "cooldowns off")
end)

test("items: a potion once per combat, with Bloodlust", function()
    local s, RH = Fight()
    s.bags[40211] = 2
    s:FireEvent("BAG_UPDATE")
    falsy(Recommend(s) == "potion", "no Bloodlust")
    s:AddAura("player", { name = "Bloodlust", spellId = 2825, duration = 40, expires = s.time + 40 })
    eq(Recommend(s), "potion", "Bloodlust")
    local st = s.ns.State:Virtual()
    s.ns.Abilities.Apply(st, "potion", RH.classData.abilities.potion)
    eq(st.cooldowns.potion.readyAt, math.huge, "not again this combat")
end)

test("racials: Blood Fury when you have it", function()
    local s, RH = Fight()
    eq(RH.classData.abilities.blood_fury.name, "Blood Fury", "shared racial")
    falsy(Recommend(s) == "blood_fury", "not learned")
    s:Learn("Blood Fury")
    s:FireEvent("SPELLS_CHANGED")
    eq(Recommend(s), "blood_fury", "orc")
end)

test("use_item,slot=13/14 and potion in rotations", function()
    local s = newAddon()
    local Compiler = s.ns.APL.Compiler
    local resolve = s.ns.Expressions.CreateResolver(s.env.RotationHelper.classData)
    local apl = Compiler.CompileAPL("actions=use_item,slot=13\nactions+=/use_item,slot=14\nactions+=/potion", {
        resolve = resolve, isAction = function(name) return s.env.RotationHelper.classData.abilities[name] ~= nil end })
    eq(#apl.errors, 0, "no errors")
    local list = apl.lists.default
    eq(list[1].name .. " " .. list[2].name .. " " .. list[3].name, "trinket1 trinket2 potion", "names")
    eq(list[3].kind, "ability", "potion is an ability now")
    apl = Compiler.CompileAPL("actions=use_item,slot=2", { resolve = resolve })
    truthy(apl.errors[1] and apl.errors[1].message:find("slot=13"), "other slots")
end)

---------------------------------------------------------------------------
-- E4 Burst windows
---------------------------------------------------------------------------
test("burst: built-in buffs, extra names and IDs", function()
    local s, RH = Fight()
    eq(Eval(s, "burst.active"), 0, "nothing up")
    s:AddAura("player", { name = "Hyperspeed Acceleration", spellId = 54758, duration = 12, expires = s.time + 12 })
    eq(Eval(s, "burst.active"), 1, "Hyperspeed")
    near(Eval(s, "burst.remains"), 12, "remains")
    s:AddAura("player", { name = "Heroism", spellId = 32182, duration = 40, expires = s.time + 30 })
    near(Eval(s, "burst.remains"), 30, "the longest one")

    s = Fight()
    s:AddAura("player", { name = "My Proc", spellId = 11111, duration = 10, expires = s.time + 10 })
    s:AddAura("player", { name = "Other Proc", spellId = 22222, duration = 20, expires = s.time + 20 })
    eq(Eval(s, "burst.active"), 0, "unknown procs")
    local options = s.ns.Options:GetOptionsTable().args.general.args
    options.burstExtra.set(nil, " My Proc , 22222")
    near(Eval(s, "burst.remains"), 20, "extra names and IDs")
    options.burstExtra.set(nil, "")
    eq(Eval(s, "burst.active"), 0, "removed again")
end)

test("cooldown.X.ready_for counts from when the cooldown came back", function()
    local s, RH = Fight()
    s:Learn("Death Coil", "Army of the Dead")
    s.cooldowns["Army of the Dead"] = { s.time, 30 }
    s.ns.State:Reset()
    eq(Eval(s, "cooldown.army_of_the_dead.ready_for"), 0, "on cooldown")
    s.time = s.time + 30
    s.cooldowns["Army of the Dead"] = nil
    s.ns.State:Reset()
    s.time = s.time + 7
    near(Eval(s, "cooldown.army_of_the_dead.ready_for"), 7, "ready for 7s")
end)

test("options: pre-pull and burst settings", function()
    local s, RH = newAddon()
    local args = s.ns.Options:GetOptionsTable().args.general.args
    truthy(args.prepullEnabled and args.presence_frost and args.presence_unholy and args.burstExtra, "present")
    eq(args.presence_frost.get(), "blood", "default presence")
    args.presence_frost.set(nil, "any")
    eq(RH.db.profile.prepull.presence.frost, "any", "set")
    truthy(args.presence_frost.values.unholy, "choices")
end)
