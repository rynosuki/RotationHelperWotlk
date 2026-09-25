local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local function CountChat(s, pattern)
    local n = 0
    for _, line in ipairs(s.chat) do
        local plain = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        if plain:find(pattern) then n = n + 1 end
    end
    return n
end

test("a failing updater is recorded and the others keep running", function()
    local s, RH = newAddon()
    local after = 0
    RH:RegisterUpdater(function() error("boom") end, 1, "broken thing")
    RH:RegisterUpdater(function() after = after + 1 end, 2, "fine thing")
    s:ClearChat()
    s:Tick(0.1)
    eq(after, 1, "later updater ran")
    eq(#RH.errors, 1, "one error")
    local err = RH.errors[1]
    eq(err.source, "broken thing", "source")
    truthy(err.message:find("boom"), "message")
    truthy(err.stack and #err.stack > 0, "stack captured")
    eq(CountChat(s, "Error in broken thing: .*boom"), 1, "one chat line")
end)

test("a repeated error only counts, it doesn't spam chat", function()
    local s, RH = newAddon()
    RH:RegisterUpdater(function() error("same problem") end, 1, "loop")
    s:ClearChat()
    for _ = 1, 10 do s:Tick(0.1) end
    eq(#RH.errors, 1, "still one entry")
    eq(RH.errors[1].count, 10, "counted")
    eq(CountChat(s, "Error in loop"), 1, "printed once")
end)

test("only the newest 20 unique errors are kept", function()
    local s, RH = newAddon()
    local n = 0
    RH:RegisterUpdater(function() n = n + 1; error("error " .. n, 0) end, 1, "many")
    for _ = 1, 25 do s:Tick(0.1) end
    eq(#RH.errors, 20, "capped")
    eq(RH.errors[1].message, "error 6", "oldest dropped")
    eq(RH.errors[20].message, "error 25", "newest last")
end)

test("a recommender error clears the icons instead of leaving stale ones", function()
    local s, RH = newAddon()
    s.hasTarget = true
    RH.recommendations = { { spellId = 51425, wait = 0 } }
    s.ns.Recommender.Update = function() error("engine bug") end
    s:Tick(0.1)
    eq(RH.recommendations, nil, "cleared")
    eq(RH.errors[1].source, "recommendations", "named source")
end)

test("the display shows '!' until /rh errors is used", function()
    local s, RH = newAddon()
    s:Slash("ACECONSOLE_RH", "lock")
    s.ns.Recommender.Update = function() error("engine bug") end
    s:Tick(0.1)
    local D = s.ns.Display
    truthy(D.frame:IsShown(), "display shown despite no icons")
    truthy(D.frame.errorMark:IsShown(), "'!' shown")
    s:ClearChat()
    s:Slash("ACECONSOLE_RH", "errors")
    truthy(s:ChatContains("recommendations: .*engine bug"), "error listed")
    s:Tick(0.1)
    falsy(D.frame.errorMark:IsShown(), "'!' gone after viewing")
    s:Slash("ACECONSOLE_RH", "errors clear")
    eq(#RH.errors, 0, "cleared")
    s:ClearChat()
    s:Slash("ACECONSOLE_RH", "errors")
    truthy(s:ChatContains("No errors recorded"), "empty")
end)

test("the no-error path still creates no garbage", function()
    local s, RH = newAddon()
    for _ = 1, 20 do s:Tick(0.1) end
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 300 do s:Tick(0.1) end
    local perTick = (collectgarbage("count") - before) * 1024 / 300
    collectgarbage("restart")
    truthy(perTick < 16, ("%.1f bytes per tick"):format(perTick))
end)
