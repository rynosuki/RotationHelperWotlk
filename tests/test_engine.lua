local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local function near(actual, expected, what)
    if type(actual) ~= "number" or math.abs(actual - expected) > 1e-6 then
        error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
    end
end

---------------------------------------------------------------------------
-- Expressions
---------------------------------------------------------------------------
-- Compiles `text` with the real resolver and evaluates it on a fresh
-- snapshot, optionally `offset` seconds in the future.
local function Eval(s, text, offset)
    local resolve = s.ns.Expressions.CreateResolver(s.env.RotationHelper.classData)
    local fn, message = s.ns.APL.Compiler.CompileExpression(text, resolve)
    if not fn then error("compile failed: " .. message, 2) end
    local st = s.ns.State:Reset()
    st.now = st.now + (offset or 0)
    return fn(st)
end

local function ResolveError(s, name)
    local resolve = s.ns.Expressions.CreateResolver(s.env.RotationHelper.classData)
    local getter, message = resolve(name)
    if getter then error("expected an error for " .. name, 2) end
    return message
end

test("expressions: buffs, debuffs and time shifting", function()
    local s = newAddon()
    s.hasTarget = true
    s:AddAura("player", { name = "Killing Machine", spellId = 51124, count = 2, duration = 30, expires = s.time + 5 })
    s:AddAura("target", { name = "Frost Fever", spellId = 55095, duration = 15, expires = s.time + 3, harmful = true })
    eq(Eval(s, "buff.killing_machine.up"), 1, "up")
    eq(Eval(s, "buff.killing_machine.react"), 1, "react")
    eq(Eval(s, "buff.killing_machine.down"), 0, "down")
    near(Eval(s, "buff.killing_machine.remains"), 5, "remains")
    eq(Eval(s, "buff.killing_machine.stack"), 2, "stack")
    eq(Eval(s, "buff.freezing_fog.up"), 0, "missing buff")
    eq(Eval(s, "buff.freezing_fog.remains"), 0, "missing remains")
    near(Eval(s, "dot.frost_fever.remains"), 3, "dot remains")
    eq(Eval(s, "debuff.frost_fever.ticking"), 1, "ticking")
    eq(Eval(s, "dot.frost_fever.up", 4), 0, "expired 4s later")
    near(Eval(s, "buff.killing_machine.remains", 2), 3, "remains 2s later")
end)

test("expressions: permanent auras", function()
    local s = newAddon()
    s:AddAura("player", { name = "Frost Presence", spellId = 48263 })
    eq(Eval(s, "buff.frost_presence.up"), 1, "up")
    eq(Eval(s, "buff.frost_presence.remains"), 9999, "remains")
end)

test("expressions: cooldowns", function()
    local s = newAddon()
    s.cooldowns["Howling Blast"] = { s.time - 2, 8 }
    eq(Eval(s, "cooldown.howling_blast.ready"), 0, "not ready")
    near(Eval(s, "cooldown.howling_blast.remains"), 6, "remains")
    eq(Eval(s, "cooldown.howling_blast.ready", 6), 1, "ready 6s later")
    eq(Eval(s, "cooldown.obliterate.ready"), 1, "no cooldown = ready")
    eq(Eval(s, "cooldown.obliterate.remains"), 0, "no cooldown = 0")
    eq(Eval(s, "cooldown.unbreakable_armor.duration"), 60, "duration")
end)

test("expressions: runes", function()
    local s = newAddon()
    s.runes[1].readyAt = s.time + 3
    s.runes[5].type = 4
    s.runes[6].readyAt = s.time + 6
    eq(Eval(s, "runes.blood"), 1, "blood")
    eq(Eval(s, "runes.frost"), 0, "frost (slot 5 is death, slot 6 recharging)")
    eq(Eval(s, "runes.death"), 1, "death")
    eq(Eval(s, "runes.total"), 4, "total")
    eq(Eval(s, "rune.unholy"), 2, "'rune' alias")
    eq(Eval(s, "runes.blood", 3), 2, "blood 3s later")
    near(Eval(s, "runes.blood.time_to_2"), 3, "time_to_2")
    eq(Eval(s, "runes.blood.time_to_1"), 0, "time_to_1")
    near(Eval(s, "runes.frost.time_to_1"), 6, "frost time_to_1")
    truthy(Eval(s, "runes.frost.time_to_2") > 1e9, "never 2 frost")
end)

test("expressions: power, gcd, time, toggles, talents, glyphs", function()
    local s, RH = newAddon()
    s.power.current = 100
    s.cooldowns["Death Coil"] = { s.time - 0.5, 1.5 }
    eq(Eval(s, "runic_power"), 100, "rp")
    eq(Eval(s, "runic_power.deficit"), 30, "deficit")
    eq(Eval(s, "runic_power.max"), 130, "max")
    near(Eval(s, "gcd.remains"), 1, "gcd remains")
    eq(Eval(s, "gcd"), 1.5, "gcd")
    eq(Eval(s, "time"), 0, "out of combat")
    s:FireEvent("PLAYER_REGEN_DISABLED")
    s.time = s.time + 12
    near(Eval(s, "time"), 12, "combat time")
    s.hasTarget = true -- a boss (cooldowns are for bosses only by default)
    eq(Eval(s, "toggle.cooldowns"), 1, "cooldowns on")
    RH.db.profile.toggles.cooldowns = false
    eq(Eval(s, "toggle.cooldowns"), 0, "cooldowns off")
    eq(Eval(s, "active_enemies"), 1, "single target")
    RH.db.profile.toggles.aoeMode = "aoe"
    eq(Eval(s, "active_enemies"), 3, "aoe mode")
    eq(Eval(s, "talent.killing_machine.rank"), 5, "talent rank")
    eq(Eval(s, "talent.killing_machine.enabled"), 1, "talent enabled")
    eq(Eval(s, "talent.butchery.enabled"), 0, "talent not taken")
    eq(Eval(s, "glyph.frost_strike.enabled"), 0, "no glyph")
    s.glyphs[1] = 58647
    s:FireEvent("GLYPH_ADDED")
    eq(Eval(s, "glyph.frost_strike.enabled"), 1, "glyph")
    s.hasTarget = true
    s.target.health = 30
    eq(Eval(s, "target.health.pct"), 30, "target health")
end)

test("expressions: helpful errors", function()
    local s = newAddon()
    eq(ResolveError(s, "buff.kiling_machine.up"), "unknown aura 'kiling_machine'", "typo")
    eq(ResolveError(s, "buff.frost_fever.up"), "'frost_fever' is a debuff; use dot.frost_fever", "buff vs debuff")
    eq(ResolveError(s, "dot.killing_machine.up"), "'killing_machine' is a buff; use buff.killing_machine", "debuff vs buff")
    eq(ResolveError(s, "buff.killing_machine.upp"), "unknown field 'upp' (use up, down, remains or stack)", "field")
    eq(ResolveError(s, "cooldown.obliterat.ready"), "unknown ability 'obliterat'", "cooldown ability")
    eq(ResolveError(s, "runes.fire"), "unknown rune type 'fire' (use blood, unholy, frost, death or total)", "rune type")
    eq(ResolveError(s, "runes.frost.time_to_9"), "unknown rune field 'time_to_9' (use time_to_1 .. time_to_6)", "rune field")
    eq(ResolveError(s, "focus"), "unknown name 'focus'", "unknown name")
end)

---------------------------------------------------------------------------
-- Ability readiness
---------------------------------------------------------------------------
local function ReadyAt(s, key)
    local st = s.ns.State:Reset()
    local t, why = s.ns.Abilities.ReadyAt(st, key)
    return t and (t - st.now), why
end

test("abilities: unknown and unlearned", function()
    local s = newAddon()
    local t, why = ReadyAt(s, "obliterate")
    eq(t, nil, "not learned")
    eq(why, "not in spellbook", "reason")
    s:Learn("Obliterate")
    eq(ReadyAt(s, "obliterate"), 0, "learned, runes ready")
end)

test("abilities: runes, with death runes as wildcards", function()
    local s = newAddon()
    s:Learn("Obliterate", "Icy Touch")
    s.runes[5].readyAt = s.time + 4 -- frost runes recharging
    s.runes[6].readyAt = s.time + 7
    local t, why = ReadyAt(s, "obliterate")
    near(t, 4, "waits for the first frost rune")
    eq(why, "runes", "limited by runes")
    s.runes[1].type = 4 -- a ready death rune can stand in for frost
    eq(ReadyAt(s, "obliterate"), 0, "death rune pays for frost")
    eq(ReadyAt(s, "icy_touch"), 0, "death rune pays for icy touch")
end)

test("abilities: GCD applies only to on-GCD abilities", function()
    local s = newAddon()
    s:Learn("Obliterate", "Unbreakable Armor")
    s.cooldowns["Death Coil"] = { s.time - 0.3, 1.5 }
    local t, why = ReadyAt(s, "obliterate")
    near(t, 1.2, "obliterate waits for GCD")
    eq(why, "gcd", "reason")
    eq(ReadyAt(s, "unbreakable_armor"), 0, "off-GCD")
end)

test("abilities: cooldown and runic power", function()
    local s = newAddon()
    s:Learn("Horn of Winter", "Frost Strike")
    s.cooldowns["Horn of Winter"] = { s.time - 5, 20 }
    local t, why = ReadyAt(s, "horn_of_winter")
    near(t, 15, "horn cooldown")
    eq(why, "cooldown", "reason")
    s.power.current = 39
    t, why = ReadyAt(s, "frost_strike")
    eq(t, nil, "not enough RP")
    eq(why, "runic power", "reason")
    s.power.current = 40
    eq(ReadyAt(s, "frost_strike"), 0, "enough RP")
end)

test("abilities: Glyph of Frost Strike lowers the cost", function()
    local s = newAddon()
    s:Learn("Frost Strike")
    s.power.current = 32
    eq(ReadyAt(s, "frost_strike"), nil, "32 RP is not enough unglyphed")
    s.glyphs[1] = 58647
    s:FireEvent("GLYPH_ADDED")
    eq(ReadyAt(s, "frost_strike"), 0, "enough with the glyph")
end)

test("abilities: Rime makes Howling Blast free", function()
    local s = newAddon()
    s:Learn("Howling Blast")
    for i = 1, 6 do s.runes[i].readyAt = s.time + 5 end
    near(ReadyAt(s, "howling_blast"), 5, "needs runes")
    s:AddAura("player", { name = "Freezing Fog", spellId = 59052, duration = 15, expires = s.time + 10 })
    eq(ReadyAt(s, "howling_blast"), 0, "free with Rime")
end)

---------------------------------------------------------------------------
-- Runner (with a fake readiness table)
---------------------------------------------------------------------------
local function Run(s, text, readyIn, values, opts)
    opts = opts or {}
    local Compiler, Runner = s.ns.APL.Compiler, s.ns.APL.Runner
    values = values or {}
    local apl = Compiler.CompileAPL(text, {
        resolve = function(name)
            return function(st) local v = values[name]; if type(v) == "function" then return v(st) end return v or 0 end
        end,
    })
    if #apl.errors > 0 then error(Compiler.FormatError(apl.errors[1]), 2) end
    local st = { now = 100, variables = {} }
    local trace = {}
    local action, t = Runner.Run(apl, st, {
        ReadyAt = function(_, name)
            local r = readyIn[name]
            if r == nil then return nil, "unknown" end
            return 100 + r
        end,
        LastUsed = opts.lastUsed,
    }, nil, trace)
    return action and action.name, t and (t - 100), trace, st
end

test("runner: first usable action wins", function()
    local s = newAddon()
    eq(Run(s, "actions=a\nactions+=/b", { a = 0, b = 0 }), "a", "priority")
    eq(Run(s, "actions=a,if=0\nactions+=/b", { a = 0, b = 0 }), "b", "condition false")
    eq(Run(s, "actions=missing\nactions+=/b", { b = 0 }), "b", "unusable skipped")
    eq(Run(s, "actions=a,if=0", { a = 0 }), nil, "nothing")
end)

test("runner: sooner beats higher priority, ties go to priority", function()
    local s = newAddon()
    local name, wait = Run(s, "actions=a\nactions+=/b", { a = 2, b = 0.5 })
    eq(name, "b", "sooner wins")
    eq(wait, 0.5, "wait")
    eq(Run(s, "actions=a\nactions+=/b", { a = 1, b = 1 }), "a", "tie goes to priority")
end)

test("runner: conditions are checked when the action is ready", function()
    local s = newAddon()
    local seen
    local values = { at = function(st) seen = st.now; return 1 end }
    Run(s, "actions=a,if=at", { a = 1.5 }, values)
    eq(seen, 101.5, "condition saw the future time")
end)

test("runner: call_action_list continues, run_action_list stops", function()
    local s = newAddon()
    local call = "actions=call_action_list,name=x\nactions+=/b\nactions.x=a,if=0"
    eq(Run(s, call, { a = 0, b = 0 }), "b", "call continues after the sub-list")
    local runList = "actions=run_action_list,name=x\nactions+=/b\nactions.x=a,if=0"
    eq(Run(s, runList, { a = 0, b = 0 }), nil, "run doesn't come back")
    eq(Run(s, "actions=call_action_list,name=x,if=0\nactions+=/b\nactions.x=a", { a = 0, b = 0 }), "b", "call condition")
end)

test("runner: variables", function()
    local s = newAddon()
    local apl = table.concat({
        "actions=variable,name=v,value=2",
        "actions+=/variable,name=v,op=add,value=3",
        "actions+=/variable,name=v,op=max,value=4",
        "actions+=/variable,name=w,op=setif,condition=0,value=1,value_else=7",
        "actions+=/a,if=variable.v=5&variable.w=7",
    }, "\n")
    eq(Run(s, apl, { a = 0 }), "a", "variable math")
    local _, _, _, st = Run(s, apl, { a = 0 })
    eq(st.variables.v, 5, "v")
end)

test("runner: wait holds back lower actions", function()
    local s = newAddon()
    local apl = "actions=a\nactions+=/wait,sec=1\nactions+=/b"
    local name, wait = Run(s, apl, { a = 0.5, b = 0 })
    eq(name, "a", "a (ready in 0.5) beats b held until 1.0")
    name, wait = Run(s, apl, { a = 3, b = 0 })
    eq(name .. " " .. wait, "b 1", "b after the wait")
end)

test("runner: line_cd", function()
    local s = newAddon()
    local lastUsed = function(_, name) return name == "a" and 95 or nil end
    eq(Run(s, "actions=a,line_cd=10\nactions+=/b", { a = 0, b = 0 }, nil, { lastUsed = lastUsed }), "b", "a used 5s ago")
    eq(Run(s, "actions=a,line_cd=3\nactions+=/b", { a = 0, b = 0 }, nil, { lastUsed = lastUsed }), "a", "line_cd over")
end)

test("runner: runaway recursion is stopped", function()
    local s = newAddon()
    local name, _, trace = Run(s, "actions=call_action_list,name=x\nactions.x=call_action_list,name=x", {})
    eq(name, nil, "nothing")
    truthy(trace[#trace]:find("nested too deep"), "trace says why")
end)

test("runner: trace explains each decision", function()
    local s = newAddon()
    local _, _, trace = Run(s, "actions=a,if=0\nactions+=/missing\nactions+=/b\nactions+=/c", { a = 0, b = 1, c = 2 })
    eq(table.concat(trace, "\n"), table.concat({
        "default:a  condition false at +0.0s",
        "default:missing  unusable: unknown",
        "default:b  best so far, ready in 1.0s",
        "default:c  later than b",
    }, "\n"), "trace")
end)
