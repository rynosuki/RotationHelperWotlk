local ADDON_NAME, ns = ...
local RH = ns.RH

-- Produces RH.recommendations on every update: takes a state snapshot,
-- runs the APL for the current spec and hands the result to the display.
local Recommender = RH:NewModule("Recommender", "AceEvent-3.0")
ns.Recommender = Recommender

local Compiler, Runner = ns.APL.Compiler, ns.APL.Runner
local State, Abilities = ns.State, ns.Abilities

local wipe, ipairs, IsSpellInRange = wipe, ipairs, IsSpellInRange

local context = {
    ReadyAt = function(s, key) return Abilities.ReadyAt(s, key) end,
    LastUsed = function(s, key) return s.lastCast[key] end,
}

-- For the out-of-range alternative: the same, but abilities that are out
-- of range of the target are unusable. Abilities without a range (Horn of
-- Winter, self buffs) report nil and count as in range.
local function InRange(key)
    local name = RH.classData.abilities[key].name
    return not (name and IsSpellInRange(name, "target") == 0)
end

local rangedContext = {
    ReadyAt = function(s, key)
        if not InRange(key) then return nil, "out of range" end
        return Abilities.ReadyAt(s, key)
    end,
    LastUsed = context.LastUsed,
}

local alternativeEntry = {}

Recommender.context = context -- for the simulator

local MAX_PREDICTIONS = 5

-- Reused so updates don't create garbage.
local recommendations = {}
local entries = {}
for i = 1, MAX_PREDICTIONS do entries[i] = {} end

function Recommender:OnEnable()
    self.compiled = {} -- spec key -> compiled APL, or false if there is none
    if not RH.classSupported then return end
    self.resolver = ns.Expressions.CreateResolver(RH.classData)
    -- After an error, clear the icons: stale advice is worse than none.
    RH:RegisterUpdater(function(_, now) Recommender:Update(now) end, RH.UPDATE_ORDER.RECOMMEND,
        "recommendations", function() RH.recommendations, RH.alternative = nil, nil end)
    -- A profile switch can change the custom rotations.
    self:RegisterMessage("ROTATIONHELPER_CONFIG_CHANGED", "Reset")
end

-- Forgets compiled APLs, e.g. after a custom rotation was saved.
function Recommender:Reset()
    wipe(self.compiled)
    RH:Invalidate()
end

-- The rotation for a spec: the profile's custom text if there is one, else
-- the default. Returns source ({ name, text, custom }) and the default (or nil).
function Recommender:GetSource(specKey)
    local defaults = ns.APLs[RH.playerClass]
    local default = defaults and defaults[specKey]
    local customs = RH.db.profile.customAPLs[RH.playerClass]
    local text = customs and customs[specKey]
    if text then
        local treeName = ns.Spec.trees[specKey] or specKey
        return { name = treeName .. " (custom)", text = text, custom = true }, default
    end
    return default, default
end

function Recommender:Compile(text)
    local abilities = RH.classData.abilities
    return Compiler.CompileAPL(text, {
        resolve = self.resolver,
        isAction = function(name) return abilities[name] ~= nil end,
    })
end

local function PrintErrors(apl)
    for _, err in ipairs(apl.errors) do
        print("  " .. Compiler.FormatError(err))
    end
end

-- Compiles (once per spec) and returns the APL for the current spec.
function Recommender:GetAPL()
    local specKey = ns.Spec.key
    if not specKey then return nil end
    local cached = self.compiled[specKey]
    if cached ~= nil then return cached or nil end

    local source, default = self:GetSource(specKey)
    if not source then
        self.compiled[specKey] = false
        return nil
    end

    local apl = self:Compile(source.text)
    apl.name, apl.custom = source.name, source.custom
    if #apl.errors > 0 then
        if source.custom and default then
            -- Saved rotations are checked when saved, so this means something
            -- changed since (e.g. an addon update). Don't run half a rotation.
            RH:Print(("Your custom rotation '%s' has %d problem(s); using the default until it's fixed (/rh apl):")
                :format(apl.name, #apl.errors))
            PrintErrors(apl)
            apl = self:Compile(default.text)
            apl.name = default.name
        else
            RH:Print(("%d problem(s) in action list '%s' (those lines are skipped):"):format(#apl.errors, apl.name))
            PrintErrors(apl)
        end
    end
    self.compiled[specKey] = apl
    return apl
end

-- Runs the APL against state `s`. Out of combat the precombat list goes
-- first; the main list needs a living hostile target.
-- Returns action, readyAt, limitedBy (or nil).
-- `ctx` defaults to the normal context and `apl` to the current spec's.
function Recommender:Evaluate(s, trace, ctx, apl)
    apl = apl or self:GetAPL()
    if not apl then return nil end
    ctx = ctx or context

    local action, readyAt, limitedBy
    if not s.inCombat and apl.lists.precombat then
        action, readyAt, limitedBy = Runner.Run(apl, s, ctx, "precombat", trace)
    end
    local t = s.target
    if not action and t.exists and t.canAttack and not t.dead then
        action, readyAt, limitedBy = Runner.Run(apl, s, ctx, "default", trace)
    end
    return action, readyAt, limitedBy
end

-- When the main recommendation is out of range of the target: the best
-- thing that is in range (Icy Touch, Howling Blast, Death Coil, ...), or nil.
function Recommender:Alternative(recs, n)
    if n == 0 or not RH.db.profile.display.alternative then return nil end
    local s = State.real
    local t = s.target
    if not (t.exists and t.canAttack and not t.dead) or InRange(recs[1].name) then return nil end
    local action, readyAt, limitedBy = self:Evaluate(s, nil, rangedContext)
    if not action or action.name == recs[1].name then return nil end
    local e = alternativeEntry
    e.name = action.name
    e.spellId = RH.classData.abilities[action.name].id
    e.wait = readyAt - s.now
    e.lacksResources = limitedBy == "runes"
    e.action, e.limitedBy = action, limitedBy
    return e
end

-- Whether `proc` is *why* this line was picked, not just spent by it: the
-- line's condition would be false without it (e.g. frost_strike,if=
-- buff.killing_machine.up), or the ability is only affordable thanks to it
-- (Rime's free Howling Blast). Checked by hiding the proc for a moment.
-- Returns the proc key or nil.
local function ProcIsReason(v, action, proc, readyAt)
    local rec = v.buffs[proc]
    local expires, now = rec.expires, v.now
    rec.expires = 0
    v.now = readyAt
    local reason = action.condition ~= nil and action.condition(v) == 0
    if not reason and RH.classData.abilities[action.name].freeWith == proc then
        local t = Abilities.ReadyAt(v, action.name)
        reason = not t or t > readyAt + 0.01
    end
    rec.expires, v.now = expires, now
    return reason and proc or nil
end

-- Predicts the next `count` actions from the current real state: pick an
-- action, simulate using it on a virtual copy of the state, and repeat.
-- Fills and returns the shared recommendations list (entries:
-- { name, spellId, wait, lacksResources, action, limitedBy, usesProc,
-- procExpires, procReason }, wait counted from now; action is the APL line
-- that chose it), and the number of entries. `trace` collects the decision trace of the first pick.
function Recommender:Predict(count, trace)
    local now = State.real.now
    local v = State:Virtual()
    local n = 0
    for i = 1, math.min(count, MAX_PREDICTIONS) do
        local action, readyAt, limitedBy = self:Evaluate(v, i == 1 and trace or nil)
        if not action then break end
        n = i
        local entry = entries[i]
        entry.name = action.name
        entry.spellId = RH.classData.abilities[action.name].id
        entry.wait = readyAt - now
        entry.lacksResources = limitedBy == "runes"
        -- For the tooltip (A6) and the proc glow (A7).
        entry.action = action
        entry.limitedBy = limitedBy
        entry.usesProc, entry.procExpires = Abilities.ProcUsed(v, action.name, readyAt)
        entry.procReason = entry.usesProc and ProcIsReason(v, action, entry.usesProc, readyAt) or nil
        recommendations[i] = entry
        Abilities.Apply(v, action.name, readyAt)
    end
    for i = n + 1, #recommendations do recommendations[i] = nil end
    return recommendations, n
end

function Recommender:Update(now)
    State:Reset(now)
    local recs, n = self:Predict(RH.db.profile.display.numIcons)
    RH.recommendations = n > 0 and recs or nil
    RH.alternative = self:Alternative(recs, n)
end
