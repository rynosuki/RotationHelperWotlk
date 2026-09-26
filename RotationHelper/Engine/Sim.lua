local ADDON_NAME, ns = ...
local RH = ns.RH

-- Rotation simulator: plays a rotation against a target that never dies
-- and measures how well it uses its time and resources. There's no damage
-- model: the numbers are for comparing rotations with each other.
--
-- Event-driven: ask the rotation for the next action, jump to when it's
-- usable and apply it (Abilities.Apply). Random procs (class data
-- simProcs) that land before that moment are applied first and the
-- rotation is asked again, since a proc can change what to press.
-- Measurements are exact per interval between events.
--
-- It uses your real talents, glyphs and spellbook (ns.Spec), starting from
-- a fresh fight: every rune ready, no runic power, nothing on cooldown.
local Sim = {}
ns.Sim = Sim

local Abilities = ns.Abilities
local huge, min, max, floor, log = math.huge, math.min, math.max, math.floor, math.log

local IDLE_STEP = 0.5 -- when nothing is usable at all, look again this much later
local PAIRS = { { 1, 2 }, { 3, 4 }, { 5, 6 } }
local SLOT_BASE = { "blood", "blood", "unholy", "unholy", "frost", "frost" }

---------------------------------------------------------------------------
-- Random numbers: our own generator (Park-Miller), so runs are repeatable
-- and WoW's shared math.random isn't touched.
---------------------------------------------------------------------------
function Sim.NewRandom(seed)
    local state = (floor(seed or 1) % 2147483646) + 1
    return function()
        state = (state * 16807) % 2147483647
        return state / 2147483647
    end
end

-- Seconds until the next event of a process happening `rate` times a second.
local function Exponential(random, rate)
    if rate <= 0 then return huge end
    return -log(1 - random()) / rate
end

---------------------------------------------------------------------------
-- The starting state
---------------------------------------------------------------------------
function Sim.NewState(opts)
    local classData = RH.classData
    local s = {
        now = 0, runes = {}, buffs = {}, debuffs = {}, cooldowns = {}, variables = {}, lastCast = {},
        runeRegen = 10, powerType = classData.simPower and classData.simPower.type or "runic_power",
        power = classData.simPower and classData.simPower.start or 0,
        powerRegen = classData.simPower and classData.simPower.regen, powerTime = 0,
        powerMax = opts.powerMax or (classData.simPower and classData.simPower.max) or 130,
        gcdDuration = 1.5, gcdEnd = 0, gcdRemains = 0, castRemains = 0, castEnd = 0, hasteFactor = 1, realGcdEnd = 0, realCastRemains = 0,
        lookahead = 0, inCombat = true, combatStart = 0, moving = false, petAlive = true,
        cooldownsEnabled = opts.cooldowns ~= false, shortCooldownsEnabled = opts.cooldowns ~= false,
        activeEnemies = opts.enemies or 1,
        target = { exists = true, canAttack = true, dead = false, name = "Simulated target", guid = "sim",
            health = 1, healthMax = 1, healthPct = 100, level = -1, timeToDie = 3600 },
    }
    if classData.usesRunes then
        for i = 1, 6 do s.runes[i] = { type = SLOT_BASE[i], base = SLOT_BASE[i], readyAt = 0 } end
    end
    s.readySince = {}
    for key, ability in pairs(classData.abilities) do
        if ability.cooldown and ability.cooldown > 0 then
            s.cooldowns[key] = { readyAt = 0, duration = Abilities.CooldownDuration(ability) }
            s.readySince[key] = 0
        end
    end
    s.burstUntil = 0 -- no burst buffs (and no pull timer) in a simulation
    -- The other enemies start without diseases; Pestilence spreads them.
    s.otherDots, s.otherDotsUntil, s.otherDiseased, s.otherDiseasedUntil = {}, {}, 0, 0
    -- Full health, and no dodges or parries (Rune Strike never comes up).
    local form = classData.simForm or 0
    if type(form) == "table" then form = form[ns.Spec.key] or 0 end
    s.healthPct, s.usable, s.queued, s.form = 100, {}, {}, form
    s.totemKey, s.totemExpires = {}, {} -- no totems down at the start
    return s
end

---------------------------------------------------------------------------
-- Measuring
---------------------------------------------------------------------------
-- Adds what happened between t0 and t1 (nothing changes in between except
-- runes coming back and auras running out, both at known times).
local function Measure(s, m, t0, t1)
    if t1 <= t0 then return end
    for _, pair in ipairs(PAIRS) do
        local a, b = s.runes[pair[1]], s.runes[pair[2]]
        if a and b then
            local cappedFrom = max(a.readyAt, b.readyAt, t0)
            if cappedFrom < t1 then m.runeWaste = m.runeWaste + (t1 - cappedFrom) end
        end
    end
    if s.powerType == "runic_power" and s.power >= s.powerMax then m.rpCapped = m.rpCapped + (t1 - t0) end

    for key, up in pairs(m.debuffUp) do
        local rec = s.debuffs[key]
        if rec and rec.expires > t0 then m.debuffUp[key] = up + (min(t1, rec.expires) - t0) end
    end
end

-- A proc lands. Stacking procs (maxStacks, e.g. Maelstrom Weapon) add a
-- stack; one landing at the maximum is lost.
local function GainProc(s, proc, m)
    local stats = m.procs[proc.aura]
    local rec = s.buffs[proc.aura]
    local up = rec and rec.expires > s.now
    local stacks = 1
    if proc.maxStacks then
        stacks = up and math.min(proc.maxStacks, rec.stacks + 1) or 1
        if up and rec.stacks >= proc.maxStacks then stats.overwritten = stats.overwritten + 1 end
    elseif up then
        stats.overwritten = stats.overwritten + 1
    end
    Abilities.Effects.ApplyBuff(s, proc.aura, proc.duration, stacks)
    stats.gained = stats.gained + 1
    if proc.resetCooldown and s.cooldowns[proc.resetCooldown] then
        s.cooldowns[proc.resetCooldown].readyAt = s.now
    end
end

---------------------------------------------------------------------------
-- One run
---------------------------------------------------------------------------
-- opts: seconds (300), seed (1), enemies (1), cooldowns (true).
-- Returns the raw measurements of one run.
function Sim.Run(apl, opts)
    opts = opts or {}
    local seconds = opts.seconds or 300
    local random = Sim.NewRandom(opts.seed or 1)
    local classData, Spec = RH.classData, ns.Spec
    local Recommender, context = ns.Recommender, ns.Recommender.context
    local s = Sim.NewState(opts)
    local m = { seconds = seconds, busy = 0, runeWaste = 0, rpCapped = 0, rpLost = 0, casts = {},
        debuffUp = {}, procs = {} }
    for _, key in ipairs(RH:ReviewDebuffs()) do m.debuffUp[key] = 0 end

    local procs = classData.simProcs or {}
    local nextProc, rates = {}, {}
    for i, proc in ipairs(procs) do
        m.procs[proc.aura] = { gained = 0, used = 0, overwritten = 0 }
        if proc.perMinute then
            rates[i] = proc.perMinute(Spec) / 60
            nextProc[i] = Exponential(random, rates[i])
        end
    end

    local t, steps, maxSteps = 0, 0, seconds * 20
    local swingAt = {} -- on-next-swing ability -> when its swing lands (it's queued until then)
    local swing = classData.simSwing or 2.5
    if type(swing) == "table" then swing = swing[ns.Spec.key] or 2.5 end
    while t < seconds and steps < maxSteps do
        steps = steps + 1
        s.now = t
        for key, at in pairs(swingAt) do
            if at <= t then
                s.queued[key] = false
                swingAt[key] = nil
            end
        end
        local action, readyAt = Recommender:Evaluate(s, nil, context, apl)
        local nextTime = action and readyAt or (t + IDLE_STEP)

        -- A random proc landing first changes the picture: apply it, ask again.
        local procIndex, procTime = nil, huge
        for i, time in pairs(nextProc) do
            if time < procTime then procIndex, procTime = i, time end
        end
        if procTime < nextTime and procTime < seconds then
            Measure(s, m, t, procTime)
            t = procTime
            s.now = t
            local proc = procs[procIndex]
            GainProc(s, proc, m)
            nextProc[procIndex] = t + Exponential(random, rates[procIndex])
        elseif nextTime >= seconds then
            Measure(s, m, t, seconds)
            t = seconds
        else
            Measure(s, m, t, nextTime)
            t = nextTime
            if action then
                local key = action.name
                local ability = classData.abilities[key]
                for aura, stats in pairs(m.procs) do
                    -- A stacking proc is used up all at once (5 Maelstrom Weapon stacks).
                    if Abilities.SpendsProc(s, key, aura, t) then stats.used = stats.used + (s.buffs[aura].stacks or 1) end
                end
                local after = s.power - Abilities.RunicPowerCost(ability) + Abilities.RunicPowerGain(ability)
                if after > s.powerMax then m.rpLost = m.rpLost + (after - s.powerMax) end
                -- Busy for the GCD, or the whole cast or channel if longer (measured
                -- before using it: an instant-with buff like Hot Streak is used up).
                local busy = max(ability.offGcd and 0 or s.gcdDuration, Abilities.CastTime(s, ability))
                if busy > 0 then m.busy = m.busy + min(busy, seconds - t) end
                Abilities.Apply(s, key, t)
                if ability.nextSwing then swingAt[key] = t + swing end
                m.casts[key] = (m.casts[key] or 0) + 1
                for _, proc in ipairs(procs) do
                    if proc.on and proc.on[key] and random() < proc.chance(Spec) then GainProc(s, proc, m) end
                end
            end
        end
    end
    return m
end

---------------------------------------------------------------------------
-- Several runs, averaged
---------------------------------------------------------------------------
-- Runs `runs` simulations (seeds seed .. seed+runs-1) and averages them.
-- Returns { seconds, runs, gcdUsage (%), runeWaste / rpCapped (s per
-- minute), rpLost (per minute), casts = { {key, perMinute}, ... } most
-- first, debuffs = { {key, uptime %} }, procs = { {aura, gained, used,
-- wasted} per run } }.
function Sim.Summarize(apl, opts, runs)
    opts = opts or {}
    runs = runs or 10
    local seed = opts.seed or 1
    local total = { busy = 0, runeWaste = 0, rpCapped = 0, rpLost = 0, casts = {}, debuffUp = {}, procs = {} }
    local seconds = opts.seconds or 300
    for r = 1, runs do
        local runOpts = { seconds = seconds, seed = seed + r - 1, enemies = opts.enemies, cooldowns = opts.cooldowns }
        local m = Sim.Run(apl, runOpts)
        total.busy = total.busy + m.busy
        total.runeWaste = total.runeWaste + m.runeWaste
        total.rpCapped = total.rpCapped + m.rpCapped
        total.rpLost = total.rpLost + m.rpLost
        for key, n in pairs(m.casts) do total.casts[key] = (total.casts[key] or 0) + n end
        for key, up in pairs(m.debuffUp) do total.debuffUp[key] = (total.debuffUp[key] or 0) + up end
        for aura, p in pairs(m.procs) do
            local tp = total.procs[aura] or { gained = 0, used = 0 }
            tp.gained, tp.used = tp.gained + p.gained, tp.used + p.used
            total.procs[aura] = tp
        end
    end

    local minutes = seconds / 60 * runs
    local round1 = function(x) return floor(x * 10 + 0.5) / 10 end
    local summary = {
        seconds = seconds, runs = runs,
        gcdUsage = round1(total.busy / (seconds * runs) * 100),
        runeWaste = round1(total.runeWaste / minutes),
        rpCapped = round1(total.rpCapped / minutes),
        rpLost = round1(total.rpLost / minutes),
        casts = {}, debuffs = {}, procs = {},
    }
    for key, n in pairs(total.casts) do summary.casts[#summary.casts + 1] = { key = key, perMinute = round1(n / minutes) } end
    table.sort(summary.casts, function(a, b)
        if a.perMinute ~= b.perMinute then return a.perMinute > b.perMinute end
        return a.key < b.key
    end)
    for _, key in ipairs(RH:ReviewDebuffs()) do
        summary.debuffs[#summary.debuffs + 1] = { key = key, uptime = round1((total.debuffUp[key] or 0) / (seconds * runs) * 100) }
    end
    for _, proc in ipairs(RH.classData.simProcs or {}) do
        local p = total.procs[proc.aura]
        if p then
            summary.procs[#summary.procs + 1] = { aura = proc.aura, gained = round1(p.gained / runs),
                used = round1(p.used / runs), wasted = round1((p.gained - p.used) / runs) }
        end
    end
    summary.damage = Sim.EstimateDamage(total.casts, total.debuffUp, minutes)
    return summary
end

-- Damage per minute from the player's damage log (Engine/DamageLog.lua):
-- casts x damage per cast, plus the diseases' ticks (one every 3 seconds
-- of uptime). Returns { perMinute, missing = { key, ... } }, or nil
-- without any data. Abilities cast but never seen doing damage count as 0
-- and are listed in `missing`, unless the log has seen them cast often
-- without damage (buffs, cooldowns).
function Sim.EstimateDamage(casts, debuffUp, minutes)
    local log = ns.DamageLog
    if not (log and RH.db and RH.db.char.damage and RH.db.char.damage.total > 0) then return nil end
    local recorded = RH.db.char.damage.abilities
    local damage, missing = 0, {}
    for key, n in pairs(casts) do
        local perCast = log:PerCast(key)
        if perCast then
            damage = damage + n * perCast
        else
            missing[#missing + 1] = key
        end
    end
    for key, up in pairs(debuffUp) do
        local perTick = log:PerTick(key)
        if perTick then damage = damage + up / 3 * perTick
        elseif not (recorded[key] and recorded[key].hits > 0) then missing[#missing + 1] = key end
    end
    table.sort(missing)
    return { perMinute = damage / minutes, missing = missing }
end

-- The summary as text lines, for chat, the options panel or the console.
function Sim.Format(summary)
    local lines = {}
    local function add(text) lines[#lines + 1] = text end
    add(("Simulated %d x %d:%02d:"):format(summary.runs, floor(summary.seconds / 60), summary.seconds % 60))
    add(("  Time spent casting: %.1f%%"):format(summary.gcdUsage))
    if RH.classData.usesRunes then
        add(("  Rune pairs sitting full: %.1f s/min   Runic power at cap: %.1f s/min, lost: %.1f/min")
            :format(summary.runeWaste, summary.rpCapped, summary.rpLost))
    end
    for _, d in ipairs(summary.debuffs) do add(("  %s uptime: %.1f%%"):format(d.key, d.uptime)) end
    for _, p in ipairs(summary.procs) do
        add(("  %s: %.1f per fight, %.1f used, %.1f wasted"):format(p.aura, p.gained, p.used, p.wasted))
    end
    local casts = {}
    for _, c in ipairs(summary.casts) do casts[#casts + 1] = ("%s %.1f"):format(c.key, c.perMinute) end
    add("  Casts per minute: " .. table.concat(casts, ", "))
    local damage = summary.damage
    if damage then
        local line = ("  Estimated damage (from your damage log): %s per minute"):format(
            ns.DamageLog.Thousands(damage.perMinute))
        if #damage.missing > 0 then line = line .. " (no data for " .. table.concat(damage.missing, ", ") .. ")" end
        add(line)
    end
    return lines
end
