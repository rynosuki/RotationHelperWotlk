local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local FROST_SPELLS = { "Icy Touch", "Plague Strike", "Obliterate", "Frost Strike", "Howling Blast", "Blood Strike",
    "Pestilence", "Death and Decay", "Horn of Winter", "Blood Tap", "Unbreakable Armor", "Empower Rune Weapon",
    "Death Coil" }

-- A Frost DK with Rime and Killing Machine.
local function Frost()
    local s, RH = newAddon()
    table.insert(s.talentTabs[2].talents, { "Rime", 3 })
    s:FireEvent("PLAYER_TALENT_UPDATE")
    s:Learn(unpack(FROST_SPELLS))
    return s, RH
end

local function Compile(s, text)
    local apl = s.ns.Recommender:Compile(text)
    if #apl.errors > 0 then error(s.ns.APL.Compiler.FormatError(apl.errors[1]), 2) end
    return apl
end

local function Simulate(s, apl, opts, runs)
    return s.ns.Sim.Summarize(apl or s.ns.Recommender:GetAPL(), opts or { seconds = 120 }, runs or 3)
end

local function Casts(summary, key)
    for _, c in ipairs(summary.casts) do if c.key == key then return c.perMinute end end
    return 0
end

---------------------------------------------------------------------------
test("random numbers: repeatable and between 0 and 1", function()
    local s = newAddon()
    local a, b, c = s.ns.Sim.NewRandom(7), s.ns.Sim.NewRandom(7), s.ns.Sim.NewRandom(8)
    local sameAsA, differs = true, false
    for _ = 1, 100 do
        local x, y, z = a(), b(), c()
        truthy(x > 0 and x < 1, "in range")
        if x ~= y then sameAsA = false end
        if x ~= z then differs = true end
    end
    truthy(sameAsA, "same seed, same numbers")
    truthy(differs, "different seed, different numbers")
end)

test("the same seed gives the same result", function()
    local s = Frost()
    local one = Simulate(s, nil, { seconds = 120, seed = 3 })
    local two = Simulate(s, nil, { seconds = 120, seed = 3 })
    eq(one.gcdUsage, two.gcdUsage, "casting time")
    eq(Casts(one, "frost_strike"), Casts(two, "frost_strike"), "casts")
end)

test("the default Frost rotation looks sane", function()
    local s = Frost()
    local sm = Simulate(s, nil, { seconds = 300 }, 5)
    truthy(sm.gcdUsage > 70 and sm.gcdUsage <= 100, "casting time " .. sm.gcdUsage)
    truthy(sm.debuffs[1].uptime > 90, "Frost Fever up " .. sm.debuffs[1].uptime)
    truthy(sm.debuffs[2].uptime > 90, "Blood Plague up " .. sm.debuffs[2].uptime)
    truthy(Casts(sm, "obliterate") > 8, "Obliterate " .. Casts(sm, "obliterate"))
    eq(sm.procs[1].aura, "freezing_fog", "Rime tracked")
    truthy(sm.procs[1].gained > 0 and sm.procs[1].used > 0, "Rime procs and gets used")
    truthy(sm.procs[2].gained > 10, "Killing Machine about 5 per minute")
end)

test("a rotation that never refreshes diseases shows it", function()
    local s = Frost()
    local sm = Simulate(s, Compile(s, "actions=obliterate\nactions+=/blood_strike\nactions+=/frost_strike"))
    eq(sm.debuffs[1].uptime, 0, "no Frost Fever")
    eq(Casts(sm, "icy_touch"), 0, "no Icy Touch")
end)

test("a rotation that never spends runic power loses it at the cap", function()
    local s = Frost()
    local sm = Simulate(s, Compile(s, "actions=obliterate\nactions+=/blood_strike\nactions+=/icy_touch\nactions+=/plague_strike"))
    truthy(sm.rpCapped > 10, "at the cap " .. sm.rpCapped)
    truthy(sm.rpLost > 10, "lost " .. sm.rpLost)
end)

test("a rotation that waits a lot spends less time casting", function()
    local s = Frost()
    local default = Simulate(s)
    local lazy = Simulate(s, Compile(s, "actions=obliterate"))
    truthy(lazy.gcdUsage < default.gcdUsage - 20, ("%.1f vs %.1f"):format(lazy.gcdUsage, default.gcdUsage))
    truthy(lazy.runeWaste > default.runeWaste, "and wastes blood runes")
end)

test("Rime resets Howling Blast and makes it free", function()
    local s = Frost()
    local sm = Simulate(s, Compile(s, "actions=howling_blast,if=buff.freezing_fog.up\nactions+=/obliterate"),
        { seconds = 300 }, 5)
    truthy(Casts(sm, "howling_blast") > 0, "free Howling Blasts")
    eq(sm.procs[1].gained, sm.procs[1].used + sm.procs[1].wasted, "gained = used + wasted")
    truthy(sm.procs[1].used >= sm.procs[1].gained * 0.8, "top priority: nearly all used")
end)

test("more enemies switch to the AoE list", function()
    local s = Frost()
    local single = Simulate(s, nil, { seconds = 120, enemies = 1 })
    local aoe = Simulate(s, nil, { seconds = 120, enemies = 3 })
    eq(Casts(single, "death_and_decay"), 0, "no Death and Decay alone")
    truthy(Casts(aoe, "death_and_decay") > 0, "Death and Decay with 3")
end)

test("cooldowns off: no cooldowns used", function()
    local s = Frost()
    truthy(Casts(Simulate(s), "unbreakable_armor") > 0, "on")
    eq(Casts(Simulate(s, nil, { seconds = 120, cooldowns = false }), "unbreakable_armor"), 0, "off")
end)

test("simulating doesn't touch the live state", function()
    local s, RH = Frost()
    s.hasTarget = true
    s:FireEvent("PLAYER_REGEN_DISABLED")
    s:Tick(0.1)
    local real = s.ns.State.real
    local before = { real.power, real.runes[1].readyAt, RH.recommendations[1].name }
    Simulate(s)
    eq(real.power, before[1], "runic power")
    eq(real.runes[1].readyAt, before[2], "runes")
    eq(RH.recommendations[1].name, before[3], "recommendation")
end)

test("/rh sim prints the results", function()
    local s = Frost()
    s:ClearChat()
    s:Slash("ACECONSOLE_RH", "sim 60")
    truthy(s:ChatContains("Frost %(default%):"), "heading")
    truthy(s:ChatContains("Simulated 5 x 1:00"), "runs and length")
    truthy(s:ChatContains("Time spent casting: %d+%.%d%%"), "casting")
    truthy(s:ChatContains("Casts per minute: obliterate"), "casts")
end)

test("the Simulate button runs the editor's rotation for the current spec", function()
    local s = Frost()
    local args = s.ns.Options:GetOptionsTable().args.rotation.args
    falsy(args.simulate.disabled(), "enabled for the current spec")
    args.text.set(nil, "actions=obliterate")
    args.simulate.func()
    local text = args.simResults.name()
    truthy(text:find("Simulated 5 x 5:00"), "results shown")
    truthy(text:find("Casts per minute: obliterate"), "the editor's rotation (only Obliterate)")
    falsy(text:find("frost_strike"), "not the default one")
    args.spec.set(nil, "unholy")
    truthy(args.simulate.disabled(), "another spec: disabled")
    truthy(args.simResults.name():find("switch to it first"), "explained")
end)

test("the Simulate button refuses a rotation with errors", function()
    local s = Frost()
    local args = s.ns.Options:GetOptionsTable().args.rotation.args
    args.text.set(nil, "actions=obliterat") -- not saved; stays in the editor
    args.simulate.func()
    truthy(args.simResults.name():find("Fix the rotation's errors first"), "message")
end)
