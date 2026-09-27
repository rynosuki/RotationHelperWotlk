local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local function near(actual, expected, tolerance, what)
    if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
        error(("%s: expected %s (+-%s), got %s"):format(what, tostring(expected), tolerance, tostring(actual)), 2)
    end
end

-- A Frost DK at a dummy, not yet in combat. Runes recharging, both diseases
-- up for the whole fight, Horn up, Unbreakable Armor known and ready.
local function Setup()
    local s, RH = newAddon()
    s:Learn("Icy Touch", "Plague Strike", "Obliterate", "Frost Strike", "Blood Strike", "Horn of Winter",
        "Death Coil", "Unbreakable Armor")
    s.hasTarget = true
    RH.db.profile.toggles.cooldowns = false
    for i = 1, 6 do s.runes[i].readyAt = s.time + 1000 end
    s:AddAura("target", { name = "Frost Fever", spellId = 55095, duration = 15, expires = s.time + 1000, harmful = true })
    s:AddAura("target", { name = "Blood Plague", spellId = 55078, duration = 15, expires = s.time + 1000, harmful = true })
    s:AddAura("player", { name = "Horn of Winter", spellId = 57623, duration = 120, expires = s.time + 1000 })
    return s, RH
end

-- Ticks `seconds` in 0.1s steps, calling `each(s)` before every tick.
local function Run(s, seconds, each)
    for _ = 1, math.floor(seconds * 10 + 0.5) do
        if each then each(s) end
        s:Tick(0.1)
    end
end

-- Keeps the GCD running (as if pressing something every GCD).
local function Busy(s)
    local gcd = s.cooldowns["Death Coil"]
    if not gcd or gcd[1] + 1.5 <= s.time then s.cooldowns["Death Coil"] = { s.time, 1.5 } end
end

local function Cast(s, name)
    s:FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", name, "")
end

---------------------------------------------------------------------------
test("a 30s fight: time casting, waste, uptime, cooldowns, adherence", function()
    local s, RH = Setup()
    s:FireEvent("PLAYER_REGEN_DISABLED")
    truthy(s.ns.Review:IsRecording(), "recording")

    -- 0-20s: busy, runes recharging; Obliterate becomes ready at 20s.
    Run(s, 20, Busy)
    -- 20-30s: the frost pair is full and nothing is pressed: idle + waste.
    s.runes[5].readyAt, s.runes[6].readyAt = s.time, s.time
    s.runes[3].readyAt = s.time -- one unholy rune: Obliterate is ready
    s.auras.target[2].expires = s.time + 5 -- Blood Plague drops at 25s
    s.cooldowns["Death Coil"] = nil -- the last GCD is over: casts only happen then
    s:Tick(0.1)                -- the icons update before you react
    Cast(s, "Obliterate")      -- matches the icon
    Cast(s, "Frost Strike")    -- doesn't (not in the first two icons): Obliterate was ready
    Run(s, 10)
    s:FireEvent("PLAYER_REGEN_ENABLED")

    falsy(s.ns.Review:IsRecording(), "stopped")
    local r = RH.db.char.reviews[1]
    truthy(r, "summary saved")
    eq(r.target, "Training Dummy", "target")
    near(r.duration, 30, 1, "duration")
    near(r.gcdUsage, 66.7, 1.5, "20 of 30s casting")
    near(r.runeWaste, 20, 1, "one pair full for 10s of 30s = 20 s/min")
    eq(r.powerCapped, 0, "no runic power at the cap")
    eq(r.powerName, "Runic power", "named for the class")
    eq(r.manaLow, nil, "no mana row for a Death Knight")
    eq(r.debuffs[1].key, "frost_fever", "first debuff")
    near(r.debuffs[1].uptime, 100, 0.5, "Frost Fever always up")
    near(r.debuffs[2].uptime, 83.3, 1.5, "Blood Plague 25 of 30s")
    eq(r.cooldowns[1].key, "unbreakable_armor", "unused cooldown")
    near(r.cooldowns[1].unused, 30, 1, "ready the whole fight")
    eq(r.casts, 2, "casts counted")
    eq(r.adherence, 50, "one of two matched")
    eq(r.mistakeCount, 1, "one mistake")
    local m = r.mistakes[1]
    eq(m.cast .. " instead of " .. m.expected, "frost_strike instead of obliterate", "the mistake")
    eq(m.expectedReady, true, "Obliterate was ready")
end)

test("latency compensation doesn't count as idle time", function()
    local s, RH = Setup()
    s.latencyMs = 300 -- the GCD ends 0.3s early for recommending
    s:FireEvent("PLAYER_REGEN_DISABLED")
    Run(s, 25, Busy)
    s:FireEvent("PLAYER_REGEN_ENABLED")
    near(RH.db.char.reviews[1].gcdUsage, 100, 0.5, "the real GCD end is used")
end)

test("off-GCD casts only count when they match", function()
    local s, RH = Setup()
    s:FireEvent("PLAYER_REGEN_DISABLED")
    Run(s, 1, Busy)
    Cast(s, "Unbreakable Armor") -- not on the icons: ignored, not a mistake
    Run(s, 24, Busy)
    s:FireEvent("PLAYER_REGEN_ENABLED")
    local r = RH.db.char.reviews[1]
    eq(r.casts, 0, "not counted")
    eq(r.mistakeCount, 0, "not a mistake")
end)

test("mistakes: ready ones first, at most three shown", function()
    local s, RH = Setup()
    s:FireEvent("PLAYER_REGEN_DISABLED")
    Run(s, 2, Busy)
    Cast(s, "Death Coil")       -- never on the icons; the main one was waiting: less telling
    s.runes[3].readyAt, s.runes[5].readyAt = s.time, s.time
    Run(s, 1)
    Cast(s, "Plague Strike")    -- Obliterate ready
    Cast(s, "Blood Strike")     -- Obliterate ready
    Cast(s, "Frost Strike")     -- Obliterate ready
    Run(s, 22)
    s:FireEvent("PLAYER_REGEN_ENABLED")
    local r = RH.db.char.reviews[1]
    eq(r.mistakeCount, 4, "four mistakes")
    eq(#r.mistakes, 3, "three shown")
    for i = 1, 3 do eq(r.mistakes[i].expectedReady, true, "mistake " .. i .. " had the right one ready") end
end)

test("short fights aren't kept; only the last 10 are", function()
    local s, RH = Setup()
    s:FireEvent("PLAYER_REGEN_DISABLED")
    Run(s, 5)
    s:FireEvent("PLAYER_REGEN_ENABLED")
    eq(#RH.db.char.reviews, 0, "5s fight not kept")
    for i = 1, 12 do
        s:FireEvent("PLAYER_REGEN_DISABLED")
        s.time = s.time + 21
        s:Tick(0.1)
        s:FireEvent("PLAYER_REGEN_ENABLED")
    end
    eq(#RH.db.char.reviews, 10, "capped at 10")
end)

test("turned off: nothing kept", function()
    local s, RH = Setup()
    RH.db.profile.review.enabled = false
    s:FireEvent("PLAYER_REGEN_DISABLED")
    Run(s, 25)
    s:FireEvent("PLAYER_REGEN_ENABLED")
    eq(#RH.db.char.reviews, 0, "nothing")
end)

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function WindowText(s)
    local out = {}
    for _, line in ipairs(s.ns.ReviewWindow.lines) do
        if line.label:IsShown() then out[#out + 1] = (line.label:GetText() or "") .. " | " .. (line.value:GetText() or "") end
    end
    return table.concat(out, "\n")
end

test("the popup is off by default; nothing opens after a fight", function()
    local s, RH = Setup()
    eq(RH.db.profile.review.autoShow, false, "default")
    s:FireEvent("PLAYER_REGEN_DISABLED")
    Run(s, 25, Busy)
    s:FireEvent("PLAYER_REGEN_ENABLED")
    eq(#RH.db.char.reviews, 1, "still recorded")
    falsy(s.ns.ReviewWindow.frame and s.ns.ReviewWindow.frame:IsShown(), "no popup")
end)

test("with the popup on, the review opens after a fight and shows the numbers", function()
    local s, RH = Setup()
    RH.db.profile.review.autoShow = true
    s:FireEvent("PLAYER_REGEN_DISABLED")
    Run(s, 20, Busy)
    s.runes[3].readyAt, s.runes[5].readyAt = s.time, s.time
    s.cooldowns["Death Coil"] = nil
    s:Tick(0.1)
    Cast(s, "Frost Strike")
    Run(s, 5)
    s:FireEvent("PLAYER_REGEN_ENABLED")
    local W = s.ns.ReviewWindow
    truthy(W.frame:IsShown(), "opened")
    eq(W.frame.subtitle:GetText(), "1 of 1", "position")
    local text = WindowText(s)
    truthy(text:find("Training Dummy | 0:25 long"), "header")
    truthy(text:find("Time spent casting | %d+%.%d%%"), "casting")
    truthy(text:find("Following the icons | 0%% of 1 casts"), "adherence")
    truthy(text:find("Frost Fever uptime | 100%%"), "uptime")
    truthy(text:find("Unbreakable Armor | ready for 0:25"), "unused cooldown")
    truthy(text:find("0:20  Frost Strike | instead of Obliterate %(ready%)"), "mistake")
end)

test("grades: green, yellow, red", function()
    local s = newAddon()
    local Grade = s.ns.ReviewWindow.Grade
    eq(Grade("gcdUsage", 97)[1], 0.3, "97% green")
    eq(Grade("gcdUsage", 90)[1], 1, "90% yellow")
    eq(Grade("gcdUsage", 70)[2], 0.35, "70% red")
    eq(Grade("runeWaste", 2)[1], 0.3, "low waste green")
    eq(Grade("runeWaste", 20)[2], 0.35, "high waste red")
    eq(Grade("adherence", nil), nil, "no value, no grade")
end)

test("browsing saved fights and /rh review", function()
    local s, RH = Setup()
    s:ClearChat()
    s:Slash("ACECONSOLE_RH", "review")
    truthy(s:ChatContains("No fights recorded yet"), "nothing yet")
    for _ = 1, 3 do
        s:FireEvent("PLAYER_REGEN_DISABLED")
        Run(s, 21, Busy)
        s:FireEvent("PLAYER_REGEN_ENABLED")
    end
    local W = s.ns.ReviewWindow
    s:Slash("ACECONSOLE_RH", "review")
    eq(W.frame.subtitle:GetText(), "3 of 3", "newest")
    falsy(W.next:IsShown(), "no next")
    W.previous.scripts.OnClick(W.previous)
    eq(W.frame.subtitle:GetText(), "2 of 3", "previous")
    truthy(W.next:IsShown(), "next shown")
    s:Slash("ACECONSOLE_RH", "review 1")
    eq(W.frame.subtitle:GetText(), "1 of 3", "by number")
    falsy(W.previous:IsShown(), "no previous")
end)

test("recording creates no garbage per update", function()
    local s = Setup()
    s:FireEvent("PLAYER_REGEN_DISABLED")
    -- Warm up past the 15s time-to-die window so every buffer is full size;
    -- growing them the first time isn't garbage.
    Run(s, 20)
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 300 do s:Tick(0.1) end
    local perTick = (collectgarbage("count") - before) * 1024 / 300
    collectgarbage("restart")
    truthy(perTick < 16, ("%.1f bytes per tick"):format(perTick))
end)

---------------------------------------------------------------------------
-- Every class
---------------------------------------------------------------------------
local function FuryFight()
    local s, RH = newAddon({ class = "WARRIOR" })
    s.talentTabs = {
        { name = "Arms", talents = {} },
        { name = "Fury", talents = { { "Bloodsurge", 3 }, { "Bloodthirst", 1 } } },
        { name = "Protection", talents = {} },
    }
    s.power = { type = 1, current = 100, max = 100 }
    s.form = 3
    s:Learn("Bloodthirst", "Whirlwind", "Slam", "Heroic Strike", "Battle Shout", "Hamstring")
    s:FireEvent("PLAYER_TALENT_UPDATE")
    s.hasTarget = true
    RH.db.profile.toggles.cooldowns = false
    return s, RH
end

test("a Fury fight: rage at the cap, Bloodsurge used and wasted, no rune row", function()
    local s, RH = FuryFight()
    s:FireEvent("PLAYER_REGEN_DISABLED")
    Run(s, 10) -- 10s at 100 rage
    s.power.current = 40
    -- A Bloodsurge that is used (gone early) and one that runs out.
    s:AddAura("player", { name = "Slam!", spellId = 46916, duration = 5, expires = s.time + 5 })
    Run(s, 1)
    s.auras.player = {}
    Run(s, 2)
    s:AddAura("player", { name = "Slam!", spellId = 46916, duration = 5, expires = s.time + 2 })
    Run(s, 3)
    s.auras.player = {}
    Run(s, 20)
    s:FireEvent("PLAYER_REGEN_ENABLED")
    local r = RH.db.char.reviews[#RH.db.char.reviews]
    eq(r.powerName, "Rage", "rage")
    near(r.powerCapped, 10 / 36 * 60, 1, "10s of 36 at the cap")
    eq(r.runeWaste, nil, "no runes")
    eq(r.procs[1].key, "bloodsurge", "proc")
    eq(r.procs[1].gained .. "/" .. r.procs[1].used, "2/1", "one used, one ran out")
    s.ns.ReviewWindow:Show()
    local text = WindowText(s)
    truthy(text:find("Rage at the cap", 1, true), "rage row")
    falsy(text:find("Rune pairs", 1, true), "no rune row")
    truthy(text:find("Procs used", 1, true), "procs heading")
end)

test("a Retribution fight: time below 10% mana", function()
    local s, RH = newAddon({ class = "PALADIN" })
    s.talentTabs = {
        { name = "Holy", talents = {} },
        { name = "Protection", talents = {} },
        { name = "Retribution", talents = { { "Crusader Strike", 1 }, { "Divine Storm", 1 } } },
    }
    s.power = { type = 0, current = 20000, max = 20000 }
    s:Learn("Crusader Strike", "Divine Storm", "Judgement of Light", "Blessing of Might")
    s:FireEvent("PLAYER_TALENT_UPDATE")
    s.hasTarget = true
    s:FireEvent("PLAYER_REGEN_DISABLED")
    Run(s, 15)
    s.power.current = 1000 -- 5%
    Run(s, 5)
    s:FireEvent("PLAYER_REGEN_ENABLED")
    local r = RH.db.char.reviews[#RH.db.char.reviews]
    near(r.manaLow, 25, 2, "5s of 20 below 10%")
    eq(r.powerCapped, nil, "full mana isn't a cap")
    s.ns.ReviewWindow:Show()
    truthy(WindowText(s):find("Mana below 10%", 1, true), "mana row")
end)

test("fights saved before 1.38 still show", function()
    local s, RH = Setup()
    RH.db.char.reviews = { { when = "12:00", target = "Old Dummy", duration = 30, gcdUsage = 90, runeWaste = 2,
        runicPowerCapped = 1, debuffs = {}, cooldowns = {}, casts = 10, adherence = 80, mistakes = {},
        mistakeCount = 0 } }
    s.ns.ReviewWindow:Show()
    local text = WindowText(s)
    truthy(text:find("Runic power at the cap | 1.0", 1, true), "old field: " .. text)
    truthy(text:find("Rune pairs sitting full", 1, true), "runes")
end)
