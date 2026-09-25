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
            direction = { type = "select", name = "Queue direction", order = 16, values = DIRECTIONS },
            visibility = { type = "header", name = "Visibility", order = 20 },
            hideOutOfCombat = { type = "toggle", name = "Hide out of combat", order = 21 },
            showStatus = { type = "toggle", name = "Show toggle status", order = 22,
                desc = "CD / AoE mode / enemy count under the main icon." },
        },
    }, ProfileOption("display"))

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
            -- WoW edit boxes read '|' as an escape code (|r would vanish from
            -- "a|runic_power"), so the editor shows it as '||'.
            text = { type = "input", name = "Action priority list", order = 3, multiline = 22, width = "full",
                desc = "Edit, then press Accept. It's saved only if it compiles.",
                get = function() return (Options:RotationText(Options:EditSpec()):gsub("|", "||")) end,
                set = function(_, value) Options:SaveRotation(Options:EditSpec(), (value:gsub("||", "|"))) end },
            result = { type = "description", order = 4, fontSize = "medium", width = "full",
                name = function() return Options.results[Options:EditSpec()] or "" end },
            revert = { type = "execute", name = "Revert to default", order = 5,
                confirm = true, confirmText = "Discard your custom rotation for this spec?",
                disabled = function()
                    local specKey = Options:EditSpec()
                    return not (Customs()[specKey] or Options.drafts[specKey])
                end,
                func = function() Options:RevertRotation(Options:EditSpec()) end },
            help = { type = "description", order = 10, name = "\n" .. SYNTAX_HELP },
        },
    }

    local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(RH.db)
    profiles.order = 4

    return {
        type = "group", name = "RotationHelper " .. RH.version, childGroups = "tab",
        args = { general = general, display = display, rotation = rotation, profiles = profiles },
    }
end

function Options:GetOptionsTable()
    if not self.options then self.options = self:BuildOptionsTable() end
    return self.options
end

---------------------------------------------------------------------------
-- Opening
---------------------------------------------------------------------------
-- Opens the panel, optionally on a tab ("rotation"). Returns false if the
-- config dialog isn't available.
function Options:Open(tab)
    local dialog = LibStub("AceConfigDialog-3.0", true)
    if not dialog then return false end
    dialog:Open(ADDON_NAME)
    if tab then dialog:SelectGroup(ADDON_NAME, tab) end
    return true
end

function Options:OnEnable()
    LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable(ADDON_NAME, function()
        return Options:GetOptionsTable()
    end)
    local dialog = LibStub("AceConfigDialog-3.0", true)
    if dialog then
        dialog:SetDefaultSize(ADDON_NAME, 780, 640)
        dialog:AddToBlizOptions(ADDON_NAME, "RotationHelper")
    end
end
