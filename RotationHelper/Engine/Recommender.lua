local ADDON_NAME, ns = ...
local RH = ns.RH

-- Produces RH.recommendations on every update: takes a state snapshot,
-- runs the APL for the current spec and hands the result to the display.
local Recommender = RH:NewModule("Recommender")
ns.Recommender = Recommender

local Compiler, Runner = ns.APL.Compiler, ns.APL.Runner
local State, Abilities = ns.State, ns.Abilities

local context = {
    ReadyAt = function(s, key) return Abilities.ReadyAt(s, key) end,
    LastUsed = function(s, key) return s.lastCast[key] end,
}

local MAX_PREDICTIONS = 5

-- Reused so updates don't create garbage.
local recommendations = {}
local entries = {}
for i = 1, MAX_PREDICTIONS do entries[i] = {} end

function Recommender:OnEnable()
    if not RH.classSupported then return end
    self.resolver = ns.Expressions.CreateResolver(RH.classData)
    self.compiled = {} -- spec key -> compiled APL, or false if there is none
    RH:RegisterUpdater(function(_, now) Recommender:Update(now) end, RH.UPDATE_ORDER.RECOMMEND)
end

-- Compiles (once per spec) and returns the APL for the current spec.
function Recommender:GetAPL()
    local Spec = ns.Spec
    if not (Spec.key and Spec.supported) then return nil end
    local cached = self.compiled[Spec.key]
    if cached ~= nil then return cached or nil end

    local sources = ns.APLs[RH.playerClass]
    local source = sources and sources[Spec.key]
    if not source then
        self.compiled[Spec.key] = false
        return nil
    end

    local abilities = RH.classData.abilities
    local apl = Compiler.CompileAPL(source.text, {
        resolve = self.resolver,
        isAction = function(name) return abilities[name] ~= nil end,
    })
    apl.name = source.name
    if #apl.errors > 0 then
        RH:Print(("%d problem(s) in action list '%s' (those lines are skipped):"):format(#apl.errors, apl.name))
        for _, err in ipairs(apl.errors) do
            print("  " .. Compiler.FormatError(err))
        end
    end
    self.compiled[Spec.key] = apl
    return apl
end

-- Runs the APL against state `s`. Out of combat the precombat list goes
-- first; the main list needs a living hostile target.
-- Returns action, readyAt, limitedBy (or nil).
function Recommender:Evaluate(s, trace)
    local apl = self:GetAPL()
    if not apl then return nil end

    local action, readyAt, limitedBy
    if not s.inCombat and apl.lists.precombat then
        action, readyAt, limitedBy = Runner.Run(apl, s, context, "precombat", trace)
    end
    local t = s.target
    if not action and t.exists and t.canAttack and not t.dead then
        action, readyAt, limitedBy = Runner.Run(apl, s, context, "default", trace)
    end
    return action, readyAt, limitedBy
end

-- Predicts the next `count` actions from the current real state: pick an
-- action, simulate using it on a virtual copy of the state, and repeat.
-- Fills and returns the shared recommendations list (entries:
-- { name, spellId, wait, lacksResources }, wait counted from now), and the
-- number of entries. `trace` collects the decision trace of the first pick.
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
end
