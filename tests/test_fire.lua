-- Fire Mage: Hot Streak (instant Pyroblast), Living Bomb, Improved Scorch,
-- talent-dependent cast times.
local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local SPELLS = { "Fireball", "Pyroblast", "Living Bomb", "Scorch", "Fire Blast", "Flamestrike", "Combustion",
    "Mirror Image", "Evocation", "Molten Armor", "Counterspell", "Arcane Intellect" }

local function near(actual, expected, what, tolerance)
    if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 1e-6) then
        error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
    end
end

-- A Fire mage in combat with a boss, Molten Armor up; `setUp` puts the
-- scorch debuff (from another mage) and Living Bomb on the target.
local function Fight(opts)
    opts = opts or {}
    local s, RH = newAddon({ class = "MAGE" })
    s.talentTabs = {
        { name = "Arcane", talents = { { "Arcane Focus", 3 } } },
        { name = "Fire", talents = { { "Improved Fireball", 5 }, { "Improved Scorch", 3 }, { "Hot Streak", 3 },
            { "Living Bomb", 1 }, { "Combustion", 1 } } },
        { name = "Frost", talents = {} },
    }
    s.power = { type = 0, current = opts.mana or 20000, max = 20000 }
    s:Learn(unpack(SPELLS))
    s.hasTarget = true
    s:FireEvent("PLAYER_TALENT_UPDATE")
    if not opts.outOfCombat then s:FireEvent("PLAYER_REGEN_DISABLED") end
    RH.db.profile.toggles.cooldowns = opts.cooldowns or false
    if not opts.noArmor then s:AddAura("player", { name = "Molten Armor", spellId = 43046, duration = 1800, expires = s.time + 1800 }) end
    if opts.setUp then
        s:AddAura("target", { name = "Improved Scorch", spellId = 22959, duration = 30, expires = s.time + 25,
            harmful = true, caster = "raid1" })
        s:AddAura("target", { name = "Living Bomb", spellId = 55360, duration = 12, expires = s.time + 10, harmful = true })
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

test("mage: class data and the Fire rotation load cleanly", function()
    local s, RH = Fight()
    eq(#RH.classData.badSpellIds, 0, "spell IDs")
    eq(s.ns.Spec.key, "fire", "spec")
    local apl = s.ns.Recommender:GetAPL()
    eq(apl.name, "Fire (default)", "rotation")
    eq(#apl.errors, 0, "compiles")
    Queue(s, 1)
    eq(#RH.errors, 0, "no errors while running (" .. tostring(RH.errors[1] and RH.errors[1].message) .. ")")
end)

test("opener: Scorch for the debuff, Living Bomb, then Fireballs (3s with Improved Fireball)", function()
    local s = Fight()
    eq(Queue(s, 4), "scorch, living_bomb +1.5, fireball +3.0, fireball +6.0", "opener")
    near(Eval(s, "action.fireball.cast_time"), 3.0, "Improved Fireball 5/5")
end)

test("someone else's crit debuff counts; Winter's Chill too", function()
    local s = Fight({ setUp = true })
    eq(Queue(s, 1), "fireball", "another mage's Improved Scorch")
    s = Fight()
    s:AddAura("target", { name = "Winter's Chill", spellId = 12579, count = 5, duration = 15, expires = s.time + 15,
        harmful = true, caster = "raid2" })
    falsy(Queue(s, 1) == "scorch", "Winter's Chill")
end)

test("Hot Streak: Pyroblast is instant and uses it up", function()
    local s, RH = Fight({ setUp = true })
    s:AddAura("player", { name = "Hot Streak", spellId = 48108, duration = 10, expires = s.time + 10 })
    eq(Queue(s, 2), "pyroblast, fireball +1.5", "instant: only the GCD")
    eq(RH.recommendations[1].usesProc, "hot_streak", "glows")
    eq(Eval(s, "action.pyroblast.cast_time"), 0, "instant")
    s.speed = 7
    eq(Queue(s, 1), "pyroblast", "even while moving")
    s.auras.player = {}
    near(Eval(s, "action.pyroblast.cast_time"), 5, "5 seconds without it")
end)

test("Living Bomb when it's gone; Fire Blast while moving", function()
    local s = Fight({ setUp = true })
    s.auras.target[2].expires = s.time - 1
    eq(Queue(s, 1), "living_bomb", "Living Bomb ran out")
    s = Fight({ setUp = true })
    s.speed = 7
    eq(Queue(s, 1), "fire_blast", "moving")
end)

test("cooldowns and mana", function()
    local s = Fight({ setUp = true, cooldowns = true })
    eq(Queue(s, 2), "combustion, mirror_image", "Combustion (off the GCD), Mirror Image")
    s = Fight({ setUp = true, mana = 1500 })
    eq(Queue(s, 1), "evocation", "low mana")
end)

test("simulator: Fire with Hot Streak and Living Bomb", function()
    local s = Fight()
    local summary = s.ns.Sim.Summarize(s.ns.Recommender:GetAPL(), { seconds = 180, cooldowns = true }, 2)
    local casts = {}
    for _, c in ipairs(summary.casts) do casts[c.key] = c.perMinute end
    truthy(summary.gcdUsage > 95, "time spent casting " .. summary.gcdUsage)
    truthy((casts.fireball or 0) > 12, "Fireball per minute " .. tostring(casts.fireball))
    truthy((casts.pyroblast or 0) > 1.5, "Pyroblast per minute " .. tostring(casts.pyroblast))
    truthy((casts.living_bomb or 0) > 3.5, "Living Bomb per minute " .. tostring(casts.living_bomb))
end)
