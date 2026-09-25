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

    print(format("%s %s %d/%d   %s %s   %s %s%s", Label("Power:"), s.powerType, s.power, s.powerMax,
        Label("GCD:"), Utils.FormatTime(s.gcdRemains),
        Label("Cast:"), s.castName or "-", s.castName and (" " .. Utils.FormatTime(s.castRemains)) or ""))

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
