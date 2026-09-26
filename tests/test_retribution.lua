-- Retribution Paladin: mana costs, the FCFS priority, Art of War, seals,
-- Judgement variants, execute and undead-only abilities.
local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local SPELLS = { "Crusader Strike", "Divine Storm", "Judgement of Light", "Judgement of Wisdom", "Judgement of Justice",
    "Consecration", "Exorcism", "Hammer of Wrath", "Holy Wrath", "Avenging Wrath", "Divine Plea", "Seal of Vengeance",
    "Seal of Command", "Seal of Righteousness", "Blessing of Might" }

local function near(actual, expected, what, tolerance)
    if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 1e-6) then
        error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
    end
end

-- A 0/5/66 style Ret Paladin in combat with a boss, Seal of Vengeance up.
local function Fight(opts)
    opts = opts or {}
    local s, RH = newAddon({ class = "PALADIN" })
    s.talentTabs = {
        { name = "Holy", talents = { { "Divine Intellect", 5 } } },
        { name = "Protection", talents = { { "Divine Strength", 5 } } },
        { name = "Retribution", talents = { { "Improved Judgements", 2 }, { "The Art of War", 2 },
            { "Sanctified Wrath", 2 }, { "Divine Storm", 1 }, { "Crusader Strike", 1 } } },
    }
    s.power = { type = 0, current = 20000, max = 20000 }
    s:Learn(unpack(SPELLS))
    s.hasTarget = true
    s:FireEvent("PLAYER_TALENT_UPDATE")
    s:FireEvent("PLAYER_REGEN_DISABLED")
    RH.db.profile.toggles.cooldowns = opts.cooldowns or false
    if not opts.noSeal then
        s:AddAura("player", { name = "Seal of Vengeance", spellId = 31801, duration = 1800, expires = s.time + 1800 })
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

test("paladin: class data and the Retribution rotation load cleanly", function()
    local s, RH = Fight()
    eq(#RH.classData.badSpellIds, 0, "spell IDs")
    eq(s.ns.Spec.key, "retribution", "spec")
    truthy(s.ns.Spec.supported, "supported")
    local apl = s.ns.Recommender:GetAPL()
    eq(apl.name, "Retribution (default)", "rotation")
    eq(#apl.errors, 0, "compiles")
    Queue(s, 1)
    eq(#RH.errors, 0, "no errors while running (" .. tostring(RH.errors[1] and RH.errors[1].message) .. ")")
end)

test("priority: Judgement, Crusader Strike, Divine Storm, Consecration", function()
    local s = Fight()
    eq(Queue(s, 4), "judgement, crusader_strike +1.5, divine_storm +3.0, consecration +4.5", "all ready")
end)

test("seal first when none is up; the other faction's seal is skipped", function()
    local s = Fight({ noSeal = true })
    eq(Queue(s, 2), "seal_of_vengeance, judgement +1.5", "no seal")
    local st = s.ns.State:Reset()
    falsy(s.ns.Spec.known.seal_of_corruption, "Seal of Corruption not learned")
    s:AddAura("player", { name = "Seal of Command", spellId = 20375, duration = 1800, expires = s.time + 1800 })
    eq(Eval(s, "buff.seal.up"), 1, "any seal counts")
    eq(Queue(s, 1), "judgement", "Seal of Command is fine too")
end)

test("Hammer of Wrath below 20%; Exorcism only with The Art of War", function()
    local s = Fight()
    s.target.health = 15
    eq(Queue(s, 2), "judgement, hammer_of_wrath +1.5", "execute")
    s.target.health = 100
    s.cooldowns["Judgement of Light"] = { s.time, 8 }
    s.cooldowns["Crusader Strike"] = { s.time, 4 }
    s.cooldowns["Divine Storm"] = { s.time, 10 }
    s.cooldowns["Consecration"] = { s.time, 8 }
    falsy(Queue(s, 1):find("^exorcism"), "no Art of War: no Exorcism")
    s:AddAura("player", { name = "The Art of War", spellId = 59578, duration = 15, expires = s.time + 15 })
    eq(Queue(s, 1), "exorcism", "Art of War")
    truthy(s.env.RotationHelper.recommendations[1].usesProc == "the_art_of_war", "marked as spending the proc")
end)

test("Holy Wrath only against undead and demons", function()
    local s = Fight()
    for _, name in ipairs({ "Judgement of Light", "Crusader Strike", "Divine Storm", "Consecration" }) do
        s.cooldowns[name] = { s.time, 8 }
    end
    falsy(Queue(s, 1):find("^holy_wrath"), "humanoid")
    s.target.creatureType = "Undead"
    eq(Eval(s, "target.type.undead"), 1, "target.type.undead")
    eq(Queue(s, 1), "holy_wrath", "undead")
end)

test("Consecration isn't wasted on a target about to die", function()
    local s = Fight()
    for _, name in ipairs({ "Judgement of Light", "Crusader Strike", "Divine Storm" }) do
        s.cooldowns[name] = { s.time, 8 }
    end
    eq(Queue(s, 1), "consecration", "long fight")
    -- Health falling fast: dying in about 3 seconds.
    for i = 1, 12 do
        s.target.health = 100 - i * 6
        s:Tick(0.25)
    end
    falsy(Queue(s, 1) == "consecration", "dying target")
end)

test("mana: costs from the client or from base mana; too little means not usable", function()
    local s, RH = Fight()
    local Abilities, divineStorm = s.ns.Abilities, RH.classData.abilities.divine_storm
    near(Abilities.PowerCost(divineStorm), 0.12 * 4394, "12% of base mana (no client cost)")
    s.spellCosts["Divine Storm"] = 400
    s:FireEvent("SPELLS_CHANGED")
    eq(Abilities.PowerCost(divineStorm), 400, "the client's cost")
    eq(Eval(s, "mana"), 20000, "mana")
    eq(Eval(s, "mana.pct"), 100, "mana.pct")
    s.power.current = 300
    local st = s.ns.State:Reset()
    local t, reason = Abilities.ReadyAt(st, "divine_storm")
    eq(t, nil, "not enough")
    eq(reason, "mana", "reason")
end)

test("low mana: Divine Plea, and the prediction gets the mana back", function()
    local s = Fight()
    s.power.current = 1200
    local queue = Queue(s, 5)
    truthy(queue:find("divine_plea", 1, true), "Divine Plea: " .. queue)
    falsy(queue:find("divine_plea.*divine_plea"), "only once: " .. queue)
end)

test("cooldowns: Avenging Wrath (off the GCD), cooldowns with talents", function()
    local s, RH = Fight({ cooldowns = true })
    eq(Queue(s, 2), "avenging_wrath, judgement", "Avenging Wrath first, off the GCD")
    local Abilities = s.ns.Abilities
    eq(Abilities.CooldownDuration(RH.classData.abilities.avenging_wrath), 120, "Sanctified Wrath 2/2")
    eq(Abilities.CooldownDuration(RH.classData.abilities.judgement), 8, "Improved Judgements 2/2")
    -- The prediction uses the shorter Judgement cooldown.
    local st = s.ns.State:Virtual()
    s.ns.Abilities.Apply(st, "judgement", st.now)
    near(st.cooldowns.judgement.readyAt, st.now + 8, "8s")
end)

test("Judgement: Light by default; Wisdom or Justice from the options", function()
    local s, RH = Fight()
    local judgement = RH.classData.abilities.judgement
    eq(judgement.name, "Judgement of Light", "default")
    RH.db.profile.variants.judgement = "wisdom"
    RH:OnConfigChanged()
    eq(judgement.name, "Judgement of Wisdom", "wisdom")
    eq(RH.classData.abilityByName["Judgement of Justice"], "judgement", "every variant counts as a cast")
    local args = s.ns.Options:GetOptionsTable().args.general.args
    truthy(args.variant_judgement, "option")
    args.variant_judgement.set(nil, "justice")
    eq(judgement.name, "Judgement of Justice", "set from the options")
end)

test("AoE: Consecration and Divine Storm first", function()
    local s, RH = Fight()
    RH.db.profile.toggles.aoeMode = "aoe"
    eq(Queue(s, 2), "consecration, divine_storm +1.5", "3+ targets")
end)

test("simulator: Ret uses everything and The Art of War", function()
    local s = Fight()
    local summary = s.ns.Sim.Summarize(s.ns.Recommender:GetAPL(), { seconds = 180, cooldowns = true }, 2)
    truthy(summary.gcdUsage > 80, "time spent casting " .. summary.gcdUsage)
    local casts = {}
    for _, c in ipairs(summary.casts) do casts[c.key] = c.perMinute end
    truthy((casts.crusader_strike or 0) > 10, "Crusader Strike per minute " .. tostring(casts.crusader_strike))
    truthy((casts.judgement or 0) > 6.5, "Judgement per minute (8s with Improved Judgements) " .. tostring(casts.judgement))
    truthy((casts.exorcism or 0) > 1, "Exorcism per minute " .. tostring(casts.exorcism))
    local text = table.concat(s.ns.Sim.Format(summary), "\n")
    falsy(text:find("Rune pairs", 1, true), "no rune numbers for a paladin")
end)
