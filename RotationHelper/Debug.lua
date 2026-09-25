local ADDON_NAME, ns = ...
local RH = ns.RH
local Utils = ns.Utils

-- /rh snapshot: prints what the engine sees, to check against the game.
local format, concat, sort, pairs, ipairs = string.format, table.concat, table.sort, pairs, ipairs
local GetTime, GetCVar = GetTime, GetCVar
local UpdateAddOnMemoryUsage, GetAddOnMemoryUsage = UpdateAddOnMemoryUsage, GetAddOnMemoryUsage
local UpdateAddOnCPUUsage, GetAddOnCPUUsage = UpdateAddOnCPUUsage, GetAddOnCPUUsage
local huge = math.huge

local RUNE_LETTER = { blood = "B", unholy = "U", frost = "F", death = "D" }
local ITEMS_PER_LINE = 6

local function Label(text) return Utils.Colorize(text, "ffd100") end
local function Dim(text) return Utils.Colorize(text, "888888") end

local function SortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    sort(keys)
    return keys
end

-- Prints `items` after `label`, wrapping every ITEMS_PER_LINE entries.
local function PrintList(label, items)
    if #items == 0 then
        print(Label(label) .. " " .. Dim("none"))
        return
    end
    for i = 1, #items, ITEMS_PER_LINE do
        local chunk = {}
        for j = i, math.min(i + ITEMS_PER_LINE - 1, #items) do chunk[#chunk + 1] = items[j] end
        print((i == 1 and Label(label) or "   ") .. " " .. concat(chunk, ", "))
    end
end

local function AuraItems(list, now)
    local items = {}
    for _, key in ipairs(SortedKeys(list)) do
        local rec = list[key]
        local text = key
        if rec.expires ~= huge then text = text .. " " .. Utils.FormatTime(rec.expires - now) end
        if rec.stacks > 1 then text = text .. " x" .. rec.stacks end
        items[#items + 1] = text
    end
    return items
end

local function PrintRunes(s, now)
    local parts = {}
    for i, rune in ipairs(s.runes) do
        local wait = rune.readyAt - now
        parts[i] = (RUNE_LETTER[rune.type] or "?") .. " " .. (wait > 0 and Utils.FormatTime(wait) or "ready")
    end
    local R = ns.Resources
    print(format("%s %s  %s", Label("Runes:"), concat(parts, " | "),
        Dim(format("(ready B%d U%d F%d D%d, regen %.1fs)", R.RunesReady(s, "blood", now),
            R.RunesReady(s, "unholy", now), R.RunesReady(s, "frost", now),
            R.RunesReady(s, "death", now), s.runeRegen))))
end

function RH:PrintSnapshot()
    if not self.classSupported then
        self:Print("No class data for " .. tostring(self.playerClass) .. ".")
        return
    end

    local Spec = ns.Spec
    Spec:Update() -- read talents fresh, so the output never shows stale data
    local s = ns.State:Reset()
    local now = s.now
    local classData = self.classData

    self:Print(format("Snapshot at %.1f (%s)", now, s.inCombat and "in combat" or "out of combat"))

    if Spec.loaded then
        local source = ns.Recommender:GetSource(Spec.key)
        print(format("%s %s (%s), talent group %d, %s", Label("Spec:"), tostring(Spec.key),
            concat(Spec.points, "/"), Spec.group,
            source and ("rotation: " .. source.name) or Dim("no rotation for this spec yet (/rh apl)")))
    else
        print(format("%s %s", Label("Spec:"), Utils.Colorize(format(
            "talent API returned no points (%d trees, talent group %d)", Spec.numTabs or 0, Spec.group), "ff4040")))
    end

    if classData.usesRunes then PrintRunes(s, now) end

    print(format("%s %s %d/%d   %s %s   %s %s%s   %s %d ms %s", Label("Power:"), s.powerType, s.power, s.powerMax,
        Label("GCD:"), Utils.FormatTime(s.gcdRemains),
        Label("Cast:"), s.castName or "-", s.castName and (" " .. Utils.FormatTime(s.castRemains)) or "",
        Label("Lookahead:"), s.lookahead * 1000 + 0.5, Dim("(" .. s.lookaheadSource .. ")")))

    PrintList("Buffs:", AuraItems(s.buffs, now))

    local t = s.target
    if t.exists then
        local ttd = t.timeToDie >= ns.Targets.TTD_UNKNOWN and "unknown" or Utils.FormatTime(t.timeToDie)
        print(format("%s %s, level %s %s, %.0f%% health, dies in %s%s%s", Label("Target:"), t.name,
            t.level == -1 and "??" or tostring(t.level), t.classification or "",
            t.healthPct, ttd, t.canAttack and "" or ", not attackable", t.dead and ", dead" or ""))
        PrintList("Debuffs:", AuraItems(s.debuffs, now))
    else
        print(Label("Target:") .. " " .. Dim("none"))
    end
    print(format("%s %d active (AoE mode %s, %d seen in the combat log)", Label("Enemies:"), s.activeEnemies,
        self.db.profile.toggles.aoeMode, ns.Targets:CountEnemies(now)))

    local cds = {}
    for _, key in ipairs(SortedKeys(s.cooldowns)) do
        if Spec.known[key] then
            local remains = ns.Cooldowns.Remains(s.cooldowns[key], now)
            cds[#cds + 1] = key .. " " .. (remains > 0 and Utils.FormatTime(remains) or Dim("ready"))
        end
    end
    PrintList("Cooldowns:", cds)

    local unknown = {}
    for _, key in ipairs(SortedKeys(classData.abilities)) do
        if not Spec.known[key] then unknown[#unknown + 1] = key end
    end
    PrintList("Not in spellbook:", unknown)

    local talents = {}
    for _, key in ipairs(SortedKeys(Spec.talents)) do
        talents[#talents + 1] = key .. " " .. Spec.talents[key]
    end
    PrintList("Talents:", talents)
    PrintList("Glyphs:", SortedKeys(Spec.glyphs))

    self:PrintDecision(s)
end

-- /rh why <ability>: why an ability is (or isn't) recommended right now.
-- Accepts "frost_strike" or "frost strike".
local WAITING_ON = { gcd = "the GCD", runes = "runes", cooldown = "its cooldown", cast = "your cast",
    wait = "a wait line" }

function RH:PrintWhy(arg)
    if not self.classSupported then
        self:Print("No class data for " .. tostring(self.playerClass) .. ".")
        return
    end
    local key = Utils.Key(arg or "")
    if key == "" then
        self:Print("Usage: /rh why <ability>, e.g. /rh why frost strike")
        return
    end
    local ability = self.classData.abilities[key]
    if not ability then
        self:Print(format("Unknown ability '%s'. Use the rotation's names, e.g. frost_strike.", key))
        return
    end
    local apl = ns.Recommender:GetAPL()
    if not apl then
        self:Print("No rotation for this spec.")
        return
    end

    local s = ns.State:Reset()
    local trace = {}
    local chosen, chosenAt = ns.Recommender:Evaluate(s, trace)
    self:Print(format("Why (not) %s?", Utils.Colorize(key, "ffd100")))

    -- Where the rotation uses it.
    local places = {}
    for _, listName in ipairs(apl.listOrder) do
        for _, action in ipairs(apl.lists[listName]) do
            if action.name == key then
                places[#places + 1] = format("%s line %d", listName == "default" and "main list" or listName, action.line)
            end
        end
    end
    if #places == 0 then
        print(format("   It isn't in your rotation (%s).", apl.name))
    else
        print("   In " .. apl.name .. ": " .. concat(places, ", "))
    end

    -- Whether it can be used, and when.
    local t, reason = ns.Abilities.ReadyAt(s, key)
    if not t then
        local detail = reason
        if reason == "runic power" then
            detail = format("runic power (needs %d, have %d)", ns.Abilities.RunicPowerCost(ability), s.power)
        end
        print("   Can't be used now: " .. detail)
    elseif t - s.now <= 0.05 then
        print("   Usable now.")
    else
        print(format("   Usable in %.1fs, waiting on %s.", t - s.now, WAITING_ON[reason] or tostring(reason)))
    end

    -- What the rotation made of it.
    local mentioned = false
    for _, line in ipairs(trace) do
        if line:find(":" .. key .. "  ", 1, true) then
            print("   " .. Dim(line))
            mentioned = true
        end
    end
    if #places > 0 and not mentioned then
        print("   " .. Dim("Not checked this time: something before it was chosen, or its list wasn't run."))
    end

    if not chosen then
        print("   Nothing is recommended right now.")
    elseif chosen.name == key then
        print("   " .. Utils.Colorize("It is the recommendation.", "40ff40"))
    else
        local wait = chosenAt - s.now
        print(format("   Recommended instead: %s (%s line %d)%s", Utils.Colorize(chosen.name, "40ff40"),
            chosen.list == "default" and "main list" or chosen.list, chosen.line,
            wait > 0.05 and format(", ready in %.1fs", wait) or ""))
    end
end

-- /rh sim [seconds]: simulates the active rotation (Engine/Sim.lua).
function RH:PrintSim(arg)
    local apl = self.classSupported and ns.Recommender:GetAPL()
    if not apl then
        self:Print("No rotation to simulate for this spec.")
        return
    end
    local seconds = math.max(30, math.min(tonumber(arg) or 300, 1200))
    local summary = ns.Sim.Summarize(apl, { seconds = seconds, cooldowns = self.db.profile.toggles.cooldowns }, 5)
    self:Print(apl.name .. ":")
    for _, line in ipairs(ns.Sim.Format(summary)) do print(line) end
end

-- /rh errors: recorded errors with their stacks. "/rh errors clear" empties
-- the list. Viewing them clears the "!" on the display.
function RH:PrintErrors(arg)
    if arg == "clear" then
        self:ClearErrors()
        self:Print("Errors cleared.")
        self:Invalidate()
        return
    end
    if #self.errors == 0 then
        self:Print("No errors recorded.")
        return
    end
    self:Print(format("%d error(s), newest last:", #self.errors))
    for _, err in ipairs(self.errors) do
        print(format("%s %s%s", Label(err.source .. ":"), err.message,
            err.count > 1 and Dim(format(" (x%d)", err.count)) or ""))
        for line in (err.stack or ""):gmatch("[^\n]+") do
            print("   " .. Dim(line))
        end
    end
    print(Dim("/rh errors clear to empty the list."))
    self.unseenErrors = 0
    self:Invalidate()
end

-- /rh perf: what the addon costs. "/rh perf reset" starts a new measurement,
-- e.g. right before a boss pull.
function RH:PrintPerf(arg)
    if arg == "reset" then
        self:ResetPerf()
        self:Print("Performance counters reset.")
        return
    end
    local perf = self.perf
    local seconds = math.max(GetTime() - perf.since, 0.001)
    UpdateAddOnMemoryUsage()
    local memory = GetAddOnMemoryUsage(ADDON_NAME)

    self:Print(format("Performance over the last %s:", Utils.FormatTime(seconds)))
    if perf.updates > 0 then
        print(format("%s %d (%.1f per second), %.3f ms average, %.3f ms worst",
            Label("Updates:"), perf.updates, perf.updates / seconds, perf.totalMs / perf.updates, perf.maxMs))
        print(format("%s %.2f ms per second of play (%.3f%% of one CPU core)",
            Label("Update cost:"), perf.totalMs / seconds, perf.totalMs / seconds / 10))
    else
        print(Label("Updates:") .. " " .. Dim("none yet"))
    end
    -- Memory goes up as garbage piles up and drops when Lua collects it,
    -- so a steady climb here means garbage is being created.
    print(format("%s %.0f KB (%+.2f KB/s since the start)", Label("Memory:"), memory,
        (memory - perf.memoryStart) / seconds))
    if GetCVar("scriptProfile") == "1" then
        UpdateAddOnCPUUsage()
        local cpu = GetAddOnCPUUsage(ADDON_NAME)
        print(format("%s %.0f ms since login (includes events and the combat log)", Label("Total CPU:"), cpu))
    else
        print(Dim("For total CPU including events: /console scriptProfile 1, then /reload. "
            .. "Turn it off again afterwards, it slows every addon down."))
    end
end

-- Prints what the APL recommends for state `s`, and why.
function RH:PrintDecision(s)
    local Recommender = ns.Recommender
    local apl = Recommender:GetAPL()
    if not apl then
        print(Label("Recommendation:") .. " " .. Dim("no action list for this spec"))
        return
    end
    local trace = {}
    local recs, n = Recommender:Predict(self.db.profile.display.numIcons, trace)
    if n > 0 then
        local queue = {}
        for i = 1, n do
            local entry = recs[i]
            queue[i] = (i == 1 and Utils.Colorize(entry.name, "40ff40") or entry.name)
                .. (entry.wait > 0.05 and (" " .. Dim("+" .. Utils.FormatTime(entry.wait))) or "")
        end
        print(Label("Recommendation:") .. " " .. concat(queue, " > "))
    else
        local t = s.target
        local why = (t.exists and t.canAttack and not t.dead) and "nothing usable" or "no hostile target"
        print(Label("Recommendation:") .. " " .. Dim("none (" .. why .. ")"))
    end
    if #trace > 0 then print("   " .. Dim("Why the first one:")) end
    for _, line in ipairs(trace) do
        print("   " .. Dim(line))
    end
end
