-- Shadow Priest: cast times and channels, spell haste, DoT refreshes,
-- Pain and Suffering, moving.
local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local SPELLS = { "Vampiric Touch", "Shadow Word: Pain", "Devouring Plague", "Mind Blast", "Mind Flay", "Mind Sear",
    "Shadow Word: Death", "Shadowfiend", "Dispersion", "Shadowform", "Inner Fire", "Vampiric Embrace", "Silence",
    "Power Word: Fortitude" }

local function near(actual, expected, what, tolerance)
    if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 1e-6) then
        error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
    end
end

-- A Shadow priest in Shadowform, in combat with a boss; `haste` is the
-- reported Mind Blast cast time in ms (1500 = no haste).
local function Fight(opts)
    opts = opts or {}
    local s, RH = newAddon({ class = "PRIEST" })
    s.talentTabs = {
        { name = "Discipline", talents = { { "Twin Disciplines", 5 } } },
        { name = "Holy", talents = {} },
        { name = "Shadow", talents = { { "Improved Mind Blast", 5 }, { "Pain and Suffering", 3 }, { "Vampiric Touch", 1 },
            { "Shadowform", 1 }, { "Dispersion", 1 }, { "Misery", 3 } } },
    }
    s.power = { type = 0, current = opts.mana or 22000, max = 22000 }
    s:Learn(unpack(SPELLS))
    s.castTimes["Mind Blast"] = opts.haste or 1500
    s.hasTarget = true
    s:FireEvent("PLAYER_TALENT_UPDATE")
    if not opts.outOfCombat then s:FireEvent("PLAYER_REGEN_DISABLED") end
    RH.db.profile.toggles.cooldowns = opts.cooldowns or false
    if not opts.noForm then s:AddAura("player", { name = "Shadowform", spellId = 15473, duration = 0, expires = 0 }) end
    if opts.dots then
        s:AddAura("target", { name = "Vampiric Touch", spellId = 48160, duration = 15, expires = s.time + opts.dots, harmful = true })
        s:AddAura("target", { name = "Devouring Plague", spellId = 48300, duration = 24, expires = s.time + 20, harmful = true })
        s:AddAura("target", { name = "Shadow Word: Pain", spellId = 48125, duration = 18, expires = s.time + 15, harmful = true })
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

test("priest: class data and the Shadow rotation load cleanly", function()
    local s, RH = Fight()
    eq(#RH.classData.badSpellIds, 0, "spell IDs")
    eq(s.ns.Spec.key, "shadow", "spec")
    local apl = s.ns.Recommender:GetAPL()
    eq(apl.name, "Shadow (default)", "rotation")
    eq(#apl.errors, 0, "compiles")
    Queue(s, 1)
    eq(#RH.errors, 0, "no errors while running (" .. tostring(RH.errors[1] and RH.errors[1].message) .. ")")
end)

test("casts: the next ability waits for the cast, not just the GCD", function()
    local s = Fight()
    eq(Queue(s, 4), "vampiric_touch, devouring_plague +1.5, mind_blast +3.0, shadow_word_pain +4.5", "opener, no haste")
    local recs = s.env.RotationHelper.recommendations
    eq(recs[4].limitedBy, "cast", "Shadow Word: Pain waits for Mind Blast's cast")
end)

test("spell haste shortens casts, channels and the GCD", function()
    local s = Fight({ haste = 1200 }) -- 25% haste
    local st = s.ns.State:Reset()
    near(st.hasteFactor, 0.8, "haste factor")
    near(st.gcdDuration, 1.2, "GCD")
    near(Eval(s, "action.mind_flay.cast_time"), 2.4, "Mind Flay channel")
    near(Eval(s, "action.vampiric_touch.cast_time"), 1.2, "Vampiric Touch cast")
    near(Eval(s, "action.devouring_plague.execute_time"), 1.2, "an instant takes the GCD")
    s = Fight({ haste = 600 })
    near(s.ns.State:Reset().gcdDuration, 1.0, "the GCD stops at 1 second")
end)

test("Mind Flay fills; the next ability waits for the channel", function()
    local s = Fight({ dots = 12 })
    eq(Queue(s, 3), "mind_blast, mind_flay +1.5, mind_flay +4.5", "dots up")
end)

test("DoTs are refreshed if they'd run out during the next Mind Flay", function()
    -- Vampiric Touch: 1.5s cast + 3s Mind Flay.
    local s = Fight({ dots = 4 })
    eq(Queue(s, 1), "vampiric_touch", "4s left")
    s = Fight({ dots = 5 })
    falsy(Queue(s, 1) == "vampiric_touch", "5s left: not yet")
end)

test("Pain and Suffering: Mind Flay refreshes Shadow Word: Pain", function()
    local s, RH = Fight({ dots = 12 })
    s.ns.State:Reset()
    local st = s.ns.State:Virtual()
    s.ns.Abilities.Apply(st, "mind_flay", st.now)
    near(st.debuffs.shadow_word_pain.expires, st.now + 3 + 18, "refreshed when the channel ends")
    near(st.castEnd, st.now + 3, "busy for the channel")
end)

test("moving: only instants", function()
    local s = Fight({ dots = 12 })
    s.speed = 7
    local queue = Queue(s, 1)
    eq(queue, "shadow_word_death", "moving")
    local st = s.ns.State:Reset()
    local t, reason = s.ns.Abilities.ReadyAt(st, "mind_blast")
    eq(reason, "moving", "Mind Blast")
end)

test("Shadowform and buffs out of combat; mana tools", function()
    local s = Fight({ outOfCombat = true, noForm = true })
    eq(Queue(s, 3), "shadowform, inner_fire +1.5, vampiric_embrace +3.0", "buffs")
    s = Fight({ dots = 12, mana = 9000 })
    eq(Queue(s, 1), "shadowfiend", "40% mana")
end)

test("simulator: Shadow with casts, channels and DoTs", function()
    local s = Fight({ haste = 1250 })
    local summary = s.ns.Sim.Summarize(s.ns.Recommender:GetAPL(), { seconds = 180, cooldowns = true }, 2)
    local casts, uptime = {}, {}
    for _, c in ipairs(summary.casts) do casts[c.key] = c.perMinute end
    for _, d in ipairs(summary.debuffs) do uptime[d.key] = d.uptime end
    truthy(summary.gcdUsage > 90, "time spent casting " .. summary.gcdUsage)
    -- Mind Blast often comes back mid-Mind Flay (the channel isn't clipped).
    truthy((casts.mind_blast or 0) > 6, "Mind Blast per minute " .. tostring(casts.mind_blast))
    truthy((casts.mind_flay or 0) > 10, "Mind Flay per minute " .. tostring(casts.mind_flay))
    truthy((casts.shadow_word_pain or 0) < 1, "Shadow Word: Pain kept up by Mind Flay: " .. tostring(casts.shadow_word_pain))
    for key, value in pairs(uptime) do truthy(value > 90, key .. " uptime " .. value) end
end)
