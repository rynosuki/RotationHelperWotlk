-- Enhancement Shaman: Maelstrom Weapon stacks, shared shock cooldown,
-- totems, imbues.
local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local SPELLS = { "Stormstrike", "Lava Lash", "Earth Shock", "Flame Shock", "Frost Shock", "Lightning Bolt",
    "Chain Lightning", "Fire Nova", "Magma Totem", "Searing Totem", "Lightning Shield", "Feral Spirit",
    "Shamanistic Rage", "Wind Shear" }

local function near(actual, expected, what, tolerance)
    if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 1e-6) then
        error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
    end
end

-- A standard Enhancement shaman in combat with a boss, Lightning Shield up.
local function Fight(opts)
    opts = opts or {}
    local s, RH = newAddon({ class = "SHAMAN" })
    s.talentTabs = {
        { name = "Elemental", talents = { { "Convection", 5 }, { "Reverberation", 5 } } },
        { name = "Enhancement", talents = { { "Maelstrom Weapon", 5 }, { "Improved Fire Nova", 2 }, { "Stormstrike", 1 },
            { "Lava Lash", 1 }, { "Feral Spirit", 1 }, { "Shamanistic Rage", 1 }, { "Dual Wield", 1 } } },
        { name = "Restoration", talents = {} },
    }
    s.power = { type = 0, current = opts.mana or 20000, max = 20000 }
    s:Learn(unpack(SPELLS))
    s.hasTarget = true
    s:FireEvent("PLAYER_TALENT_UPDATE")
    if not opts.outOfCombat then s:FireEvent("PLAYER_REGEN_DISABLED") end
    RH.db.profile.toggles.cooldowns = opts.cooldowns or false
    s:AddAura("player", { name = "Lightning Shield", spellId = 49281, count = 3, duration = 600, expires = s.time + 600 })
    if opts.setUp then
        s:AddAura("target", { name = "Flame Shock", spellId = 49233, duration = 18, expires = s.time + 15, harmful = true })
        s.totems[1] = { "Magma Totem VII", s.time - 2, 20 }
    end
    return s, RH
end

local function Queue(s, count)
    s:Tick(0.1)
    local out = {}
    for i, e in ipairs(s.env.RotationHelper.recommendations or {}) do
        if i > count then break end
        out[#out + 1] = e.wait < 0.05 and e.name or ("%s +%.1f"):format(e.name, e.wait)
    end
    return table.concat(out, ", ")
end

local function Eval(s, text)
    local resolve = s.ns.Expressions.CreateResolver(s.env.RotationHelper.classData)
    local fn, message = s.ns.APL.Compiler.CompileExpression(text, resolve)
    if not fn then error("compile failed: " .. message, 2) end
    return fn(s.ns.State:Reset())
end

test("shaman: class data and the Enhancement rotation load cleanly", function()
    local s, RH = Fight()
    eq(#RH.classData.badSpellIds, 0, "spell IDs")
    eq(s.ns.Spec.key, "enhancement", "spec")
    local apl = s.ns.Recommender:GetAPL()
    eq(apl.name, "Enhancement (default)", "rotation")
    eq(#apl.errors, 0, "compiles")
    Queue(s, 1)
    eq(#RH.errors, 0, "no errors while running (" .. tostring(RH.errors[1] and RH.errors[1].message) .. ")")
end)

test("opener: Stormstrike, Flame Shock, then Magma Totem and Fire Nova", function()
    local s = Fight()
    eq(Queue(s, 4), "stormstrike, flame_shock +1.5, magma_totem +3.0, fire_nova +4.5", "opener")
end)

test("the shocks share a cooldown", function()
    local s = Fight({ setUp = true })
    eq(Queue(s, 2), "stormstrike, earth_shock +1.5", "Earth Shock with Flame Shock up")
    local st = s.ns.State:Virtual()
    s.ns.Abilities.Apply(st, "earth_shock", st.now)
    near(st.cooldowns.flame_shock.readyAt, st.now + 5, "Flame Shock too (Reverberation 5/5: 5s)")
    near(st.cooldowns.frost_shock.readyAt, st.now + 5, "and Frost Shock")
end)

test("Lightning Bolt at 5 Maelstrom Weapon stacks, not before", function()
    local s, RH = Fight({ setUp = true })
    s:AddAura("player", { name = "Maelstrom Weapon", spellId = 53817, count = 4, duration = 30, expires = s.time + 30 })
    falsy(Queue(s, 1) == "lightning_bolt", "4 stacks")
    s.auras.player[#s.auras.player].count = 5
    eq(Queue(s, 2), "lightning_bolt, stormstrike +1.5", "5 stacks")
    eq(RH.recommendations[1].usesProc, "maelstrom_weapon", "glows")
    RH.db.profile.toggles.aoeMode = "aoe"
    eq(Queue(s, 1), "chain_lightning", "several targets: Chain Lightning")
end)

test("totems: read from the game, by element or by name", function()
    local s = Fight({ setUp = true })
    eq(Eval(s, "totem.fire.up"), 1, "fire totem")
    near(Eval(s, "totem.fire.remains"), 18, "remains")
    near(Eval(s, "totem.magma_totem.remains"), 18, "Magma Totem by name (rank stripped)")
    eq(Eval(s, "totem.searing_totem.up"), 0, "not Searing")
    eq(Eval(s, "totem.earth.up"), 0, "no earth totem")
    s.totems[1] = nil
    eq(Eval(s, "totem.fire.up"), 0, "gone")
end)

test("Magma Totem is refreshed as it runs out", function()
    local s = Fight({ setUp = true })
    for _, name in ipairs({ "Stormstrike", "Earth Shock", "Lava Lash", "Fire Nova" }) do s.cooldowns[name] = { s.time, 6 } end
    falsy(Queue(s, 1) == "magma_totem", "18s left")
    s.totems[1] = { "Magma Totem VII", s.time - 19, 20 }
    eq(Queue(s, 1), "magma_totem", "1s left")
end)

test("low mana: Shamanistic Rage (off the GCD)", function()
    local s = Fight({ setUp = true, mana = 8000 })
    eq(Queue(s, 2), "shamanistic_rage, stormstrike", "40% mana")
end)

test("cooldowns: Feral Spirit; Wind Shear is the interrupt", function()
    local s, RH = Fight({ setUp = true, cooldowns = true })
    eq(Queue(s, 1), "feral_spirit", "Feral Spirit")
    eq(RH.classData.interrupt, "wind_shear", "interrupt")
end)

test("pre-pull checklist: weapon imbues on both weapons", function()
    local s, RH = Fight({ outOfCombat = true })
    s.offhandWeapon = true
    s:Tick(0.1)
    local missing = table.concat(RH.checklist or {}, ", ")
    truthy(missing:find("Main-hand imbue", 1, true) and missing:find("Off-hand imbue", 1, true), missing)
    s.imbues.main, s.imbues.off = true, true
    s:Tick(0.1)
    missing = table.concat(RH.checklist or {}, ", ")
    falsy(missing:find("imbue", 1, true), "imbued: " .. missing)
end)

test("simulator: Enhancement with Maelstrom Weapon stacks and totems", function()
    local s = Fight()
    local summary = s.ns.Sim.Summarize(s.ns.Recommender:GetAPL(), { seconds = 180, cooldowns = true }, 2)
    local casts = {}
    for _, c in ipairs(summary.casts) do casts[c.key] = c.perMinute end
    truthy((casts.stormstrike or 0) > 6, "Stormstrike per minute " .. tostring(casts.stormstrike))
    truthy((casts.lightning_bolt or 0) > 1.5, "Lightning Bolt per minute " .. tostring(casts.lightning_bolt))
    truthy((casts.magma_totem or 0) > 2 and (casts.magma_totem or 0) < 3.5, "Magma Totem every ~20s: " .. tostring(casts.magma_totem))
    truthy((casts.fire_nova or 0) > 3, "Fire Nova per minute " .. tostring(casts.fire_nova))
    truthy(summary.debuffs[1] and summary.debuffs[1].uptime > 85, "Flame Shock uptime")
end)
