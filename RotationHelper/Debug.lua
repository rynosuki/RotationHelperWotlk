local ADDON_NAME, ns = ...
local RH = ns.RH
local Utils = ns.Utils

-- /rh snapshot: prints what the engine sees, to check against the game.
local format, concat, sort, pairs, ipairs = string.format, table.concat, table.sort, pairs, ipairs
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

    local s = ns.State:Reset()
    local now = s.now
    local Spec = ns.Spec
    local classData = self.classData

    self:Print(format("Snapshot at %.1f (%s)", now, s.inCombat and "in combat" or "out of combat"))

    print(format("%s %s (%s), talent group %d%s", Label("Spec:"), tostring(Spec.key),
        concat(Spec.points, "/"), Spec.group, Spec.supported and "" or Dim(" (no rotation for this spec yet)")))

    if classData.usesRunes then PrintRunes(s, now) end

    print(format("%s %s %d/%d   %s %s   %s %s%s", Label("Power:"), s.powerType, s.power, s.powerMax,
        Label("GCD:"), Utils.FormatTime(s.gcdRemains),
        Label("Cast:"), s.castName or "-", s.castName and (" " .. Utils.FormatTime(s.castRemains)) or ""))

    PrintList("Buffs:", AuraItems(s.buffs, now))

    local t = s.target
    if t.exists then
        print(format("%s %s, level %s %s, %.0f%% health%s%s", Label("Target:"), t.name,
            t.level == -1 and "??" or tostring(t.level), t.classification or "",
            t.healthPct, t.canAttack and "" or ", not attackable", t.dead and ", dead" or ""))
        PrintList("Debuffs:", AuraItems(s.debuffs, now))
    else
        print(Label("Target:") .. " " .. Dim("none"))
    end

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
end
