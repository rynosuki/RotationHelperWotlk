local ADDON_NAME, ns = ...
local RH = ns.RH

-- Produces RH.recommendations on every update: takes a state snapshot,
-- runs the APL for the current spec and hands the result to the display.
local Recommender = RH:NewModule("Recommender", "AceEvent-3.0")
ns.Recommender = Recommender

local Compiler, Runner = ns.APL.Compiler, ns.APL.Runner
local State, Abilities = ns.State, ns.Abilities

local wipe, ipairs = wipe, ipairs

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
    self.compiled = {} -- spec key -> compiled APL, or false if there is none
    if not RH.classSupported then return end
    self.resolver = ns.Expressions.CreateResolver(RH.classData)
    RH:RegisterUpdater(function(_, now) Recommender:Update(now) end, RH.UPDATE_ORDER.RECOMMEND)
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
