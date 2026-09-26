local ADDON_NAME, ns = ...
local RH = ns.RH

-- The options panel (AceConfig): General, Display, Rotation and Profiles
-- tabs. Also added to Blizzard's Interface > AddOns list.
--
-- The Rotation tab edits the APL for any spec of the class. A rotation is
-- saved only if it compiles; otherwise the text stays in the editor with
-- the errors listed below it, and the previous rotation stays active.
local Options = RH:NewModule("Options")
ns.Options = Options

local format, concat = string.format, table.concat

local DEFAULT_POINT = { "CENTER", "UIParent", "CENTER", 0, -150 }

local AOE_MODES = { auto = "Auto (count enemies)", single = "Single target", aoe = "AoE (3+ targets)" }
local DIRECTIONS = { RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down" }
local LATENCY_MODES = {
    auto = "By lag tolerance / latency (recommended)",
    fixed = "By a fixed amount",
    off = "Off",
}

local SYNTAX_HELP = table.concat({
    "Lines look like |cffffd100actions+=/obliterate,if=runes.frost>=1|r. "
        .. "|cffffd100actions=|r starts the main list, |cffffd100actions.NAME=|r a named list, "
        .. "|cffffd100+=/|r adds a line. Lines starting with # are comments.",
    "The ability usable soonest is recommended; ties go to the higher line. "
        .. "Rune and runic power costs are checked for you.",
    "Operators: & (and), | (or), ! (not), = != < <= > >=, + - * and % (division). "
        .. "True is 1 and false is 0.",
    "Names: buff.NAME.up/remains/stack, dot.NAME.remains, cooldown.NAME.ready/remains, "
        .. "runes.blood/frost/unholy/death/total, runic_power(.deficit), gcd, active_enemies, "
        .. "target.health.pct, target.time_to_die, talent.NAME.enabled, glyph.NAME.enabled, toggle.cooldowns.",
    "Actions: call_action_list,name=X / run_action_list,name=X / variable,name=X,value=... / wait,sec=...",
}, "\n\n")

---------------------------------------------------------------------------
-- Rotation editing
---------------------------------------------------------------------------
Options.drafts = {}  -- spec key -> text that didn't compile, kept in the editor
Options.results = {} -- spec key -> message shown under the editor

local function Customs()
    local all = RH.db.profile.customAPLs
    all[RH.playerClass] = all[RH.playerClass] or {}
    return all[RH.playerClass]
end

function Options:EditSpec()
    return self.editSpec or ns.Spec.key
end

-- The text shown in the editor for a spec.
function Options:RotationText(specKey)
    if self.drafts[specKey] then return self.drafts[specKey] end
    local source = ns.Recommender:GetSource(specKey)
    return source and source.text or ""
end

-- Compiles `text` and saves it as the spec's rotation if it compiles.
-- Empty text or the default's exact text removes the custom rotation.
-- Returns true if saved.
function Options:SaveRotation(specKey, text)
    local _, default = ns.Recommender:GetSource(specKey)
    if text:match("^%s*$") or (default and text == default.text) then
        return self:RevertRotation(specKey)
    end

    local apl = ns.Recommender:Compile(text)
    if #apl.errors > 0 then
        local lines = {}
        for i, err in ipairs(apl.errors) do lines[i] = ns.APL.Compiler.FormatError(err) end
        self.drafts[specKey] = text
        -- Messages can quote '|' from the rotation; escape it for display.
        self.results[specKey] = format("|cffff4040Not saved: %d problem(s). The previous rotation is still active.|r\n%s",
            #apl.errors, (concat(lines, "\n"):gsub("|", "||")))
        return false
    end

    local actions = 0
    for _, list in pairs(apl.lists) do actions = actions + #list end
    Customs()[specKey] = text
    self.drafts[specKey] = nil
    self.results[specKey] = format("|cff40ff40Saved and active: %d actions in %d lists.|r", actions, #apl.listOrder)
    ns.Recommender:Reset()
    return true
end

function Options:RevertRotation(specKey)
    Customs()[specKey] = nil
    self.drafts[specKey] = nil
    local _, default = ns.Recommender:GetSource(specKey)
    self.results[specKey] = default and "|cff40ff40Using the default rotation.|r"
        or "|cffffd100No rotation for this spec. Paste one above and press Accept.|r"
    ns.Recommender:Reset()
    return true
end

-- Simulates the rotation in the editor (Engine/Sim.lua) with your talents,
-- so only for your current spec. Results appear under the editor.
Options.simResults = {}
local SIM_SECONDS, SIM_RUNS = 300, 5

function Options:Simulate(specKey)
    local apl = ns.Recommender:Compile(self:RotationText(specKey))
    if #apl.errors > 0 then
        self.simResults[specKey] = "|cffff4040Fix the rotation's errors first (Accept shows them).|r"
        return
    end
    local summary = ns.Sim.Summarize(apl, { seconds = SIM_SECONDS, cooldowns = RH.db.profile.toggles.cooldowns },
        SIM_RUNS)
    self.simResults[specKey] = table.concat(ns.Sim.Format(summary), "\n"):gsub("|", "||")
end

-- A rotation someone sent (UI/APLShare.lua), after the player said yes:
-- shown in the editor for its spec, not saved.
function Options:OpenReceived(specKey, text, sender)
    if specKey and ns.Spec.trees[specKey] then self.editSpec = specKey end
    local target = self:EditSpec()
    self.drafts[target] = text
    self.results[target] = ("|cffffd100From %s: check it, then press Accept to save it.|r"):format(sender or "?")
    self:Open("rotation")
end

function Options:RotationStatus(specKey)
    local source = ns.Recommender:GetSource(specKey)
    local treeName = ns.Spec.trees[specKey] or tostring(specKey)
    local active = specKey == ns.Spec.key and " (your current spec)" or ""
    if not source then
        return format("%s%s: no rotation yet. Write or paste one below and press Accept.", treeName, active)
    end
    return format("%s%s: using |cffffd100%s|r.", treeName, active, source.name)
end

---------------------------------------------------------------------------
-- Options table
---------------------------------------------------------------------------
local function Changed()
    RH:OnConfigChanged()
end

local function ProfileOption(tableName)
    return {
        get = function(info) return RH.db.profile[tableName][info[#info]] end,
        set = function(info, value)
            RH.db.profile[tableName][info[#info]] = value
            Changed()
        end,
    }
end

local function WithAccessors(group, accessors)
    group.get, group.set = accessors.get, accessors.set
    return group
end

function Options:BuildOptionsTable()
    local general = WithAccessors({
        type = "group", name = "General", order = 1,
        args = {
            cooldowns = { type = "toggle", name = "Cooldowns", order = 1,
                desc = "Recommend major cooldowns (Unbreakable Armor, Empower Rune Weapon, ...)." },
            consumables = { type = "toggle", name = "Consumables", order = 1.1,
                desc = "Suggest potions (the POT chip under the icons)." },
            consumablesBossOnly = { type = "toggle", name = "Only against bosses", order = 1.2,
                desc = "Consumables only while you target a boss or boss frames are up, so trash and add "
                    .. "pulls don't use them.",
                disabled = function() return not RH.db.profile.toggles.consumables end,
                get = function() return RH.db.profile.items.consumablesBossOnly end,
                set = function(_, value) RH.db.profile.items.consumablesBossOnly = value; Changed() end },
            aoeMode = { type = "select", name = "AoE mode", order = 2, values = AOE_MODES,
                desc = "Auto counts enemies from the combat log; the others force a mode." },
            bindings = { type = "description", order = 3, fontSize = "medium",
                name = "\nKey bindings for these toggles: Escape > Key Bindings > RotationHelper." },
        },
    }, ProfileOption("toggles"))

    general.args.enabled = { type = "toggle", name = "Enabled", order = 0, width = "full",
        get = function() return RH.db.profile.enabled end,
        set = function(_, value) RH.db.profile.enabled = value; Changed() end }
    general.args.updateInterval = { type = "range", name = "Update interval (seconds)", order = 4,
        min = 0.05, max = 0.5, step = 0.05,
        desc = "How often recommendations refresh, besides right after game events.",
        get = function() return RH.db.profile.updateInterval end,
        set = function(_, value) RH.db.profile.updateInterval = value end }

    general.args.minimap = { type = "toggle", name = "Minimap button", order = 5,
        get = function() return RH.db.profile.minimap.show end,
        set = function(_, value) RH.db.profile.minimap.show = value; Changed() end }

    local function ReviewOption(option)
        option.get = function(info) return RH.db.profile.review[info[#info]] end
        option.set = function(info, value) RH.db.profile.review[info[#info]] = value end
        return option
    end
    general.args.reviewHeader = { type = "header", name = "Fight review", order = 30 }
    general.args.reviewInfo = { type = "description", order = 31, fontSize = "medium",
        name = "After each fight: time spent casting, waste, disease uptime, unused cooldowns and how closely "
            .. "you followed the icons. /rh review opens the last one." }
    general.args.reviewEnabled = { type = "toggle", name = "Record fights", order = 32,
        get = function() return RH.db.profile.review.enabled end,
        set = function(_, value) RH.db.profile.review.enabled = value end }
    general.args.autoShow = ReviewOption({ type = "toggle", name = "Show after each fight", order = 33,
        disabled = function() return not RH.db.profile.review.enabled end })
    general.args.minDuration = ReviewOption({ type = "range", name = "Only fights longer than (seconds)",
        order = 34, min = 5, max = 120, step = 5,
        disabled = function() return not RH.db.profile.review.enabled end })
    general.args.openReview = { type = "execute", name = "Show the last review", order = 35,
        func = function() ns.ReviewWindow:Show() end }

    general.args.prepullHeader = { type = "header", name = "Pre-pull checklist", order = 40 }
    general.args.prepullInfo = { type = "description", order = 41, fontSize = "medium",
        name = "Out of combat with a boss or elite targeted, the display lists what's missing: flask, food, "
            .. "Horn of Winter, presence, ghoul." }
    general.args.prepullEnabled = { type = "toggle", name = "Show the checklist", order = 42,
        get = function() return RH.db.profile.prepull.enabled end,
        set = function(_, value) RH.db.profile.prepull.enabled = value; Changed() end }
    local presenceValues = { any = "Don't check" }
    for key, presence in pairs(ns.PrePull.PRESENCES) do presenceValues[key] = presence.label end
    local specOrder = 43
    for _, spec in ipairs({ "blood", "frost", "unholy" }) do
        if RH.classData and RH.classData.auras.blood_presence then
            general.args["presence_" .. spec] = { type = "select", order = specOrder, values = presenceValues,
                name = ("Presence for %s%s"):format(spec:sub(1, 1):upper(), spec:sub(2)),
                disabled = function() return not RH.db.profile.prepull.enabled end,
                get = function() return RH.db.profile.prepull.presence[spec] or "any" end,
                set = function(_, value) RH.db.profile.prepull.presence[spec] = value; Changed() end }
            specOrder = specOrder + 1
        end
    end

    general.args.damageHeader = { type = "header", name = "Damage log", order = 60 }
    general.args.damageInfo = { type = "description", order = 61, fontSize = "medium",
        name = "Your damage per ability, learned from the combat log with your gear. The simulator uses it to "
            .. "estimate a rotation's damage. Reset it after a big gear change." }
    general.args.damageShow = { type = "execute", name = "Print to chat", order = 62,
        func = function() RH:PrintDamage("") end }
    general.args.damageReset = { type = "execute", name = "Reset", order = 63,
        confirm = true, confirmText = "Forget all recorded damage for this character?",
        func = function() RH:PrintDamage("reset") end }

    general.args.trinketsHeader = { type = "header", name = "Trinkets", order = 55 }
    general.args.trinkets = { type = "select", name = "Suggest trinkets", order = 56,
        values = { offensive = "Damage on-use effects only", all = "Every on-use trinket", none = "Never" },
        desc = "By default only trinkets whose use effect helps damage (attack power, haste, crit, armor "
            .. "penetration, ...) are suggested; tank trinkets like armor or health on-use are left to you.",
        get = function() return RH.db.profile.items.trinkets end,
        set = function(_, value) RH.db.profile.items.trinkets = value; Changed() end }
    general.args.trinketsCurrent = { type = "description", order = 57, fontSize = "medium",
        name = function()
            local parts = {}
            for _, key in ipairs({ "trinket1", "trinket2" }) do
                local ability = RH.classData and RH.classData.abilities[key]
                if ability and ability.name then
                    local state = ns.Spec.known[key] and "suggested" or "not suggested"
                    local kind = ability.useKind == "offensive" and "damage" or (ability.useKind and "other" or "unknown")
                    parts[#parts + 1] = ("%s (%s effect): %s"):format(ability.name, kind, state)
                end
            end
            return #parts > 0 and table.concat(parts, "\n") or "No trinkets with a use effect equipped."
        end }

    general.args.burstHeader = { type = "header", name = "Burst windows", order = 50 }
    general.args.burstInfo = { type = "description", order = 51, fontSize = "medium",
        name = "Rotations can hold cooldowns for burst.active: Bloodlust/Heroism, Hyperspeed Acceleration, "
            .. "racials, Potion of Speed and common trinket procs are built in." }
    general.args.burstExtra = { type = "input", name = "More burst buffs", order = 52, width = "full",
        desc = "Buff names or spell IDs, separated by commas.",
        get = function() return RH.db.profile.burst.extra end,
        set = function(_, value) RH.db.profile.burst.extra = value; Changed() end }

    general.args.threatHeader = { type = "header", name = "Threat warning", order = 20 }
    general.args.threatEnabled = { type = "toggle", name = "Warn about threat", order = 21,
        desc = "In a group: a red border and THREAT under the icons when you're close to pulling aggro.",
        get = function() return RH.db.profile.threat.enabled end,
        set = function(_, value) RH.db.profile.threat.enabled = value end }
    general.args.threatThreshold = { type = "range", name = "Warn at (% of aggro)", order = 22,
        min = 50, max = 100, step = 5,
        disabled = function() return not RH.db.profile.threat.enabled end,
        get = function() return RH.db.profile.threat.threshold end,
        set = function(_, value) RH.db.profile.threat.threshold = value end }

    general.args.latencyHeader = { type = "header", name = "Latency", order = 10 }
    general.args.latencyMode = { type = "select", name = "Show the next ability early", order = 11,
        values = LATENCY_MODES,
        desc = "The client queues a press made just before the GCD ends. Showing the next ability that much "
            .. "early lets you press as soon as it will be accepted.",
        get = function() return RH.db.profile.latency.mode end,
        set = function(_, value) RH.db.profile.latency.mode = value; Changed() end }
    general.args.latencyFixed = { type = "range", name = "Fixed amount (ms)", order = 12,
        min = 0, max = 400, step = 10,
        hidden = function() return RH.db.profile.latency.mode ~= "fixed" end,
        get = function() return RH.db.profile.latency.fixedMs end,
        set = function(_, value) RH.db.profile.latency.fixedMs = value; Changed() end }
    general.args.latencyCurrent = { type = "description", order = 13, fontSize = "medium",
        name = function()
            local seconds, source = ns.State:Lookahead()
            return ("Currently %d ms (%s)."):format(seconds * 1000 + 0.5, source)
        end }

    local display = WithAccessors({
        type = "group", name = "Display", order = 2,
        args = {
            locked = { type = "toggle", name = "Lock position", order = 1,
                desc = "Unlocked, the display shows sample icons and can be dragged." },
            testMode = { type = "toggle", name = "Show sample icons", order = 2,
                get = function() return ns.Display.testMode end,
                set = function(_, value) ns.Display:SetTestMode(value) end },
            resetPosition = { type = "execute", name = "Reset position", order = 3,
                func = function()
                    RH.db.profile.display.point = { unpack(DEFAULT_POINT) }
                    Changed()
                end },
            layout = { type = "header", name = "Layout", order = 10 },
            numIcons = { type = "range", name = "Icons", order = 11, min = 1, max = 5, step = 1,
                desc = "The main icon plus predicted next actions." },
            scale = { type = "range", name = "Scale", order = 12, min = 0.5, max = 3, step = 0.05, isPercent = true },
            iconSize = { type = "range", name = "Icon size", order = 13, min = 24, max = 96, step = 1 },
            queueScale = { type = "range", name = "Queue icon size", order = 14, min = 0.4, max = 1, step = 0.05,
                isPercent = true, desc = "Queued icons relative to the main icon." },
            spacing = { type = "range", name = "Spacing", order = 15, min = 0, max = 20, step = 1 },
            direction = { type = "select", name = "Queue direction", order = 16, values = DIRECTIONS,
                disabled = function() return RH.db.profile.display.timeline end },
            visibility = { type = "header", name = "Visibility", order = 20 },
            hideOutOfCombat = { type = "toggle", name = "Hide out of combat", order = 21 },
            showStatus = { type = "toggle", name = "Show toggle status", order = 22,
                desc = "CD / AoE mode / enemy count under the main icon." },
            pressFlash = { type = "toggle", name = "Flash when it's time to press", order = 23,
                desc = "Briefly brighten the main icon the moment its ability can be pressed." },
            interrupt = { type = "toggle", name = "Interrupt icon", order = 24,
                desc = "A separate icon above the main one while your target casts something interruptible." },
            shiftInteract = { type = "toggle", name = "Shift: tooltips and clickable toggles", order = 25,
                desc = "While Shift is held, hover an icon to see why it's recommended, "
                    .. "and click CD or the AoE mode to toggle them." },
            procGlow = { type = "toggle", name = "Glow on proc abilities", order = 26,
                desc = "Glow on icons whose ability spends Killing Machine or Rime." },
            procBadge = { type = "toggle", name = "Proc icon in the corner", order = 26.5,
                desc = "Show the proc's icon in the bottom-right corner when the proc is why "
                    .. "the ability is recommended (e.g. Frost Strike because of Killing Machine)." },
            procSound = { type = "select", name = "Sound on a new proc", order = 27,
                values = function() return ns.Display.PROC_SOUNDS end },
        },
    }, ProfileOption("display"))

    -- Waste warnings live in their own profile table.
    local function WasteOption(option)
        option.get = function(info) return RH.db.profile.waste[info[#info]] end
        option.set = function(info, value) RH.db.profile.waste[info[#info]] = value end
        if option.disabled == nil then
            option.disabled = function() return not RH.db.profile.waste.enabled end
        end
        return option
    end
    local wasteArgs = {
        wasteHeader = { type = "header", name = "Waste warnings", order = 30 },
        wasteInfo = { type = "description", order = 31, fontSize = "medium",
            name = "In combat, the main icon gets a pulsing orange border (and RUNES / RP on the status line) "
                .. "while resources go to waste." },
        enabled = WasteOption({ type = "toggle", name = "Enabled", order = 32, disabled = false }),
        runes = WasteOption({ type = "toggle", name = "Capped rune pairs", order = 33,
            desc = "Both runes of a pair ready: that pair isn't regenerating." }),
        runicPower = WasteOption({ type = "toggle", name = "Runic power near the cap", order = 34 }),
        rpDeficit = WasteOption({ type = "range", name = "Runic power: warn within", order = 35,
            min = 0, max = 40, step = 5, desc = "Warn when runic power is this close to the maximum." }),
        grace = WasteOption({ type = "range", name = "Warn after (seconds)", order = 36,
            min = 0, max = 5, step = 0.5, desc = "How long a cap may last before warning (about one GCD by default)." }),
    }
    for key, option in pairs(wasteArgs) do display.args[key] = option end

    display.args.holdIndicator = { type = "toggle", name = "Say what the icon waits on", order = 28,
        desc = "When the main ability is more than a GCD away, label it RUNES, COOLDOWN, CAST or WAIT." }
    display.args.alternative = { type = "toggle", name = "In-range alternative", order = 29,
        desc = "When the main ability is out of range, show the best in-range one below it." }

    display.args.extrasHeader = { type = "header", name = "Extras", order = 35 }
    display.args.runeBar = { type = "toggle", name = "Rune bar", order = 36,
        hidden = function() return not (RH.classData and RH.classData.usesRunes) end,
        desc = "Your runes above the icons. The strip under each rune shows its type once the queued "
            .. "abilities are used, dimmed if they spend it." }
    display.args.cooldownStrip = { type = "toggle", name = "Cooldown strip", order = 37,
        desc = "Major cooldowns and trinkets above the icons, with the time left." }
    display.args.timeline = { type = "toggle", name = "Timeline", order = 38,
        desc = "Place the queued icons by when they can be used, with a second under each: a gap means "
            .. "waiting (on runes, usually). Always grows to the right." }

    -- Colors, with presets.
    local function ColorOption(key, name, order)
        return { type = "color", name = name, order = order,
            get = function() return unpack(RH.db.profile.display.colors[key]) end,
            set = function(_, r, g, b)
                RH.db.profile.display.colors[key] = { r, g, b }
                Changed()
            end }
    end
    local function Preset(presetName)
        return function()
            local colors = RH.db.profile.display.colors
            for key, color in pairs(ns.Display.COLOR_PRESETS[presetName]) do
                colors[key] = { color[1], color[2], color[3] }
            end
            Changed()
        end
    end
    display.args.colorsHeader = { type = "header", name = "Colors", order = 40 }
    display.args.colorOutOfRange = ColorOption("outOfRange", "Out of range", 41)
    display.args.colorNoResources = ColorOption("noResources", "Not enough resources", 42)
    display.args.colorWaste = ColorOption("waste", "Waste warning", 43)
    display.args.colorThreat = ColorOption("threat", "Threat warning", 44)
    display.args.colorsDefault = { type = "execute", name = "Default colors", order = 45, func = Preset("default") }
    display.args.colorsColorblind = { type = "execute", name = "Color-blind friendly", order = 46,
        desc = "The Okabe-Ito palette: easy to tell apart with the common kinds of color blindness.",
        func = Preset("colorblind") }

    local rotation = {
        type = "group", name = "Rotation", order = 3,
        hidden = function() return not RH.classSupported end,
        args = {
            spec = { type = "select", name = "Spec", order = 1,
                values = function() return ns.Spec.trees end,
                get = function() return Options:EditSpec() end,
                set = function(_, value) Options.editSpec = value end },
            status = { type = "description", order = 2, fontSize = "medium", width = "full",
                name = function() return Options:RotationStatus(Options:EditSpec()) end },
            -- Our editor widget (UI/APLEditor.lua) works in plain text and
            -- handles WoW's '|' escaping itself.
            text = { type = "input", name = "Action priority list", order = 3, multiline = 22, width = "full",
                dialogControl = ns.APLEditor.TYPE,
                desc = "Edit, then press Accept. It's saved only if it compiles.",
                get = function() return Options:RotationText(Options:EditSpec()) end,
                set = function(_, value) Options:SaveRotation(Options:EditSpec(), value) end },
            syntaxColors = { type = "toggle", name = "Syntax colors", order = 8,
                desc = "Color abilities, names, numbers and comments in the editor.",
                get = function() return RH.db.profile.editor.syntaxColors end,
                set = function(_, value) RH.db.profile.editor.syntaxColors = value end },
            result = { type = "description", order = 4, fontSize = "medium", width = "full",
                name = function() return Options.results[Options:EditSpec()] or "" end },
            revert = { type = "execute", name = "Revert to default", order = 5,
                confirm = true, confirmText = "Discard your custom rotation for this spec?",
                disabled = function()
                    local specKey = Options:EditSpec()
                    return not (Customs()[specKey] or Options.drafts[specKey])
                end,
                func = function() Options:RevertRotation(Options:EditSpec()) end },
            simulate = { type = "execute", name = "Simulate", order = 6,
                desc = "Play the rotation in the editor for 5 fights of 5 minutes with your talents and random "
                    .. "procs, and show how well it uses its time and resources. No damage numbers: use it to "
                    .. "compare versions of a rotation.",
                disabled = function() return Options:EditSpec() ~= ns.Spec.key end,
                func = function() Options:Simulate(Options:EditSpec()) end },
            simResults = { type = "description", order = 7, fontSize = "medium", width = "full",
                name = function()
                    if Options:EditSpec() ~= ns.Spec.key then
                        return "|cff999999Simulating needs this spec's talents: switch to it first.|r"
                    end
                    return Options.simResults[Options:EditSpec()] or ""
                end },
            help = { type = "description", order = 10, name = "\n" .. SYNTAX_HELP },
        },
    }

    local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(RH.db)
    profiles.order = 4
    self:AddSpecProfileOptions(profiles)

    return {
        type = "group", name = "RotationHelper " .. RH.version, childGroups = "tab",
        args = { general = general, display = display, rotation = rotation, profiles = profiles },
    }
end

-- "Per talent spec" section on the Profiles tab (see SpecProfiles.lua).
local DONT_SWITCH = ""

function Options:AddSpecProfileOptions(profiles)
    local SpecProfiles = ns.SpecProfiles
    local function ProfileChoices()
        local choices = { [DONT_SWITCH] = "Don't switch" }
        for _, name in ipairs(RH.db:GetProfiles()) do choices[name] = name end
        return choices
    end
    local function GroupOption(group, order)
        return {
            type = "select", order = order, width = "double",
            name = function() return SpecProfiles:GroupLabel(group) end,
            values = ProfileChoices,
            disabled = function() return SpecProfiles:NumGroups() < group end,
            -- These get/set override AceDBOptions' handler methods for the group.
            get = function() return SpecProfiles:Mapping()[group] or DONT_SWITCH end,
            set = function(_, value)
                SpecProfiles:Set(group, value ~= DONT_SWITCH and value or nil)
            end,
        }
    end
    profiles.args.specHeader = { type = "header", name = "Per talent spec", order = 100 }
    profiles.args.specInfo = { type = "description", order = 101, fontSize = "medium",
        name = function()
            if SpecProfiles:NumGroups() < 2 then
                return "Learn Dual Talent Specialization to switch profiles with your talents."
            end
            return "Switch to a profile automatically when you change talent spec. "
                .. "Choosing one for the spec you're in switches now."
        end }
    profiles.args.specPrimary = GroupOption(1, 102)
    profiles.args.specSecondary = GroupOption(2, 103)
end

function Options:GetOptionsTable()
    if not self.options then self.options = self:BuildOptionsTable() end
    return self.options
end

---------------------------------------------------------------------------
-- Opening
---------------------------------------------------------------------------
-- Opens the options window, optionally on a tab ("rotation"). Returns false
-- if the config libraries aren't available.
function Options:Open(tab)
    return ns.OptionsWindow:Open(tab)
end

-- Redraws the window if it's open; for settings changed outside it (slash
-- commands, key bindings).
function Options:RefreshIfOpen()
    ns.OptionsWindow:QueueRender()
end

-- Interface > AddOns entry: a short page with a button that opens our
-- window, instead of drawing the options in Blizzard's panel.
function Options:CreateBlizzardLauncher()
    if not InterfaceOptions_AddCategory then return end
    local panel = CreateFrame("Frame", "RotationHelperInterfaceOptionsPanel", UIParent)
    panel.name = "RotationHelper"
    panel:Hide()

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("RotationHelper " .. RH.version)
    local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    text:SetText("The options have their own window. You can also open it with /rh.")

    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetWidth(160)
    button:SetHeight(24)
    button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)
    button:SetText("Open options")
    button:SetScript("OnClick", function()
        HideUIPanel(InterfaceOptionsFrame)
        HideUIPanel(GameMenuFrame)
        Options:Open()
    end)
    InterfaceOptions_AddCategory(panel)
end

function Options:OnEnable()
    LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable(ADDON_NAME, function()
        return Options:GetOptionsTable()
    end)
    self:CreateBlizzardLauncher()
end
