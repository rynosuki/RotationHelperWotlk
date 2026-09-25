local ADDON_NAME, ns = ...

-- Walks a compiled APL and picks the action to recommend.
--
-- Like Hekili, it recommends the action that can be used *soonest*; among
-- actions usable at the same time, the higher-priority one wins. Each
-- ability's condition is checked at the moment it would become usable (by
-- moving state.now there), so e.g. "icy_touch,if=dot.frost_fever.remains<2"
-- looks at the disease as it will be when Icy Touch is actually castable.
--
-- List-level entries (call_action_list, variable, wait) are evaluated at
-- the base time, i.e. the state's own `now`.
ns.APL = ns.APL or {}
local Runner = {}
ns.APL.Runner = Runner

local format, max, wipe = string.format, math.max, wipe

local MAX_DEPTH = 8

-- Variable operations: fn(current, value) -> new value
local VARIABLE_OPS = {
    set = function(_, v) return v end,
    add = function(c, v) return c + v end,
    sub = function(c, v) return c - v end,
    mul = function(c, v) return c * v end,
    div = function(c, v) if v == 0 then return 0 end return c / v end,
    min = function(c, v) return c < v and c or v end,
    max = function(c, v) return c > v and c or v end,
}

-- Per-evaluation data, reused between calls.
local run = {}

local function Trace(action, message, ...)
    local trace = run.trace
    if trace then
        trace[#trace + 1] = format("%s:%s  %s", action.list, action.name, format(message, ...))
    end
end

local function Condition(fn, s)
    return not fn or fn(s) ~= 0
end

local RunList

local function EvaluateAbility(action, s)
    local ctx = run.ctx
    if action.lineCd and ctx.LastUsed then
        local last = ctx.LastUsed(s, action.name)
        if last and run.base - last < action.lineCd then
            Trace(action, "line_cd (%.1fs left)", action.lineCd - (run.base - last))
            return
        end
    end

    local t, limitedBy = ctx.ReadyAt(s, action.name)
    if not t then
        Trace(action, "unusable: %s", limitedBy or "?")
        return
    end
    if run.minTime > t then t, limitedBy = run.minTime, "wait" end
    if run.best and t >= run.bestTime then
        Trace(action, "later than %s", run.best.name)
        return
    end

    s.now = t
    local ok = Condition(action.condition, s)
    s.now = run.base
    if not ok then
        Trace(action, "condition false at +%.1fs", t - run.base)
        return
    end

    run.best, run.bestTime, run.bestLimitedBy = action, t, limitedBy
    Trace(action, "best so far, ready in %.1fs%s", t - run.base, limitedBy and (" (" .. limitedBy .. ")") or "")
end

local function ApplyVariable(action, s)
    local vars = s.variables
    local name = action.variable
    if action.op == "reset" then
        vars[name] = nil
    elseif action.op == "setif" then
        local fn = Condition(action.varCondition, s) and action.value or action.valueElse
        vars[name] = fn(s)
    else
        vars[name] = VARIABLE_OPS[action.op](vars[name] or 0, action.value(s))
    end
end

-- Returns true to stop evaluating entirely (a run_action_list finished, or
-- nothing can beat the current best).
function RunList(apl, listName, s, depth)
    if depth > MAX_DEPTH then
        if run.trace then run.trace[#run.trace + 1] = "action lists nested too deep at " .. listName end
        return true
    end
    local list = apl.lists[listName]
    for i = 1, #list do
        local action = list[i]
        local kind = action.kind
        if kind == "ability" then
            EvaluateAbility(action, s)
            if run.best and run.bestTime <= run.floor then return true end
        elseif kind == "variable" then
            if Condition(action.condition, s) then ApplyVariable(action, s) end
        elseif kind == "call" or kind == "run" then
            if Condition(action.condition, s) then
                if RunList(apl, action.target, s, depth + 1) then return true end
                if kind == "run" then return true end
            end
        elseif kind == "wait" then
            -- Nothing further down may be recommended before the wait ends.
            if Condition(action.condition, s) then
                local sec = action.sec(s)
                if sec > 0 then
                    run.minTime = max(run.minTime, run.base + sec)
                    Trace(action, "waiting %.1fs", sec)
                end
            end
        end
    end
    return false
end

-- Evaluates `listName` (default "default") against state `s`.
-- ctx.ReadyAt(s, name) -> time, limitedBy | nil, reason   (required)
-- ctx.LastUsed(s, name) -> time of last use, for line_cd (optional)
-- ctx.floor            -> earliest time anything can be used (default s.now)
-- Returns action, readyAt, limitedBy; or nil if nothing is usable.
-- Pass a table as `trace` to collect a line per decision.
function Runner.Run(apl, s, ctx, listName, trace)
    run.ctx = ctx
    run.trace = trace
    run.base = s.now
    run.floor = ctx.floor or s.now
    run.minTime = s.now
    run.best, run.bestTime, run.bestLimitedBy = nil, nil, nil
    wipe(s.variables)

    RunList(apl, listName or "default", s, 1)
    s.now = run.base
    run.ctx, run.trace = nil, nil
    return run.best, run.bestTime, run.bestLimitedBy
end
