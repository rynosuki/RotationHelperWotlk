local ADDON_NAME, ns = ...

local RH = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0")
ns.RH = RH
_G.RotationHelper = RH

local Utils = ns.Utils
local GetTime, UnitClass = GetTime, UnitClass
local tinsert, ipairs, lower = table.insert, ipairs, string.lower

RH.version = GetAddOnMetadata(ADDON_NAME, "Version") or "dev"

-- Classes that have a rotation module. Filled in by Classes/*.lua.
RH.supportedClasses = { DEATHKNIGHT = true }

local AOE_MODES = { "auto", "single", "aoe" }

local defaults = {
    profile = {
        enabled = true,
        paused = false,
        debug = false,
        updateInterval = 0.1, -- seconds between recommendation refreshes
        toggles = {
            cooldowns = true,
            aoeMode = "auto", -- auto | single | aoe
        },
        display = {
            locked = false,
            scale = 1.0,
            numIcons = 4,
            iconSize = 50,
            queueScale = 0.8, -- queued icons relative to the main icon
            spacing = 4,
            direction = "RIGHT", -- RIGHT | LEFT | UP | DOWN
            hideOutOfCombat = false,
            point = { "CENTER", "UIParent", "CENTER", 0, -150 },
        },
    },
}

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function RH:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("RotationHelperDB", defaults, true)
    self.db.RegisterCallback(self, "OnProfileChanged", "OnConfigChanged")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnConfigChanged")
    self.db.RegisterCallback(self, "OnProfileReset", "OnConfigChanged")

    self:RegisterChatCommand("rh", "SlashCommand")
    self:RegisterChatCommand("rotationhelper", "SlashCommand")

    local _, class = UnitClass("player")
    self.playerClass = class
    self.classSupported = self.supportedClasses[class] or false
end

function RH:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "Invalidate")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatChanged")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatChanged")
    self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", "OnTalentsChanged")
    self:RegisterEvent("CHARACTER_POINTS_CHANGED", "OnTalentsChanged")
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "Invalidate")

    self:StartUpdateLoop()

    if not self.classSupported then
        self:Print(("No rotation available for %s yet; the addon will stay idle."):format(self.playerClass or "?"))
    end
end

function RH:OnDisable()
    self:StopUpdateLoop()
end

---------------------------------------------------------------------------
-- Update loop
--
-- Modules register an updater with RH:RegisterUpdater(fn). The loop calls
-- every updater at most once per `updateInterval`, and immediately on the
-- next frame after something calls RH:Invalidate().
---------------------------------------------------------------------------
local updaters = {}
local updateFrame = CreateFrame("Frame")
updateFrame:Hide()

local elapsedSince = 0
local dirty = true

function RH:RegisterUpdater(fn)
    tinsert(updaters, fn)
end

function RH:Invalidate()
    dirty = true
end

function RH:IsActive()
    local p = self.db.profile
    return self.classSupported and p.enabled and not p.paused
end

local function RunUpdaters(now)
    for _, fn in ipairs(updaters) do
        fn(RH, now)
    end
end

updateFrame:SetScript("OnUpdate", function(_, elapsed)
    elapsedSince = elapsedSince + elapsed
    if not dirty and elapsedSince < RH.db.profile.updateInterval then return end
    elapsedSince = 0
    dirty = false
    if RH:IsActive() then
        RunUpdaters(GetTime())
    end
end)

function RH:StartUpdateLoop()
    dirty = true
    updateFrame:Show()
end

function RH:StopUpdateLoop()
    updateFrame:Hide()
end

---------------------------------------------------------------------------
-- Event handlers
---------------------------------------------------------------------------
-- InCombatLockdown() can still be false while PLAYER_REGEN_DISABLED fires,
-- so trust the event name.
function RH:OnCombatChanged(event)
    self.inCombat = event == "PLAYER_REGEN_DISABLED"
    self:SendMessage("ROTATIONHELPER_COMBAT_CHANGED", self.inCombat)
    self:Invalidate()
end

function RH:OnTalentsChanged()
    self:SendMessage("ROTATIONHELPER_TALENTS_CHANGED")
    self:Invalidate()
end

function RH:OnConfigChanged()
    self:SendMessage("ROTATIONHELPER_CONFIG_CHANGED")
    self:Invalidate()
end

---------------------------------------------------------------------------
-- Toggles (also used by key bindings, see Bindings.xml)
---------------------------------------------------------------------------
function RH:ToggleCooldowns()
    local t = self.db.profile.toggles
    t.cooldowns = not t.cooldowns
    self:Print("Cooldowns: " .. Utils.OnOff(t.cooldowns))
    self:OnConfigChanged()
end

function RH:CycleAoEMode()
    local t = self.db.profile.toggles
    local nextIndex = 1
    for i, mode in ipairs(AOE_MODES) do
        if mode == t.aoeMode then nextIndex = i % #AOE_MODES + 1 end
    end
    t.aoeMode = AOE_MODES[nextIndex]
    self:Print("AoE mode: " .. Utils.Colorize(t.aoeMode, "ffd100"))
    self:OnConfigChanged()
end

function RH:TogglePause()
    local p = self.db.profile
    p.paused = not p.paused
    self:Print(p.paused and "Paused." or "Resumed.")
    self:OnConfigChanged()
end

function RH:ToggleLock()
    local d = self.db.profile.display
    d.locked = not d.locked
    self:Print("Display " .. (d.locked and "locked." or "unlocked; drag to move."))
    self:OnConfigChanged()
end

function RH:ToggleDebug()
    local p = self.db.profile
    p.debug = not p.debug
    self:Print("Debug: " .. Utils.OnOff(p.debug))
end

function RH:Debug(...)
    if self.db and self.db.profile.debug then
        self:Print(Utils.Colorize("[debug]", "888888"), ...)
    end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
function RH:ToggleTestMode()
    local display = ns.Display
    display:SetTestMode(not display.testMode)
    self:Print("Test icons " .. (display.testMode and "shown." or "hidden."))
end

-- Parses a number argument and stores it in the display settings.
local function SetDisplayNumber(self, key, label, arg, minValue, maxValue, integer)
    local value = tonumber(arg)
    if not value or value < minValue or value > maxValue then
        self:Print(("Usage: /rh %s <%s-%s> (currently %s)"):format(label, minValue, maxValue,
            tostring(self.db.profile.display[key])))
        return
    end
    if integer then value = math.floor(value + 0.5) end
    self.db.profile.display[key] = value
    self:Print(("%s set to %s."):format(label, value))
    self:OnConfigChanged()
end

function RH:SetScale(arg)
    SetDisplayNumber(self, "scale", "scale", arg, 0.5, 3)
end

function RH:SetIconCount(arg)
    SetDisplayNumber(self, "numIcons", "icons", arg, 1, 5, true)
end

local HELP = {
    { "status", "show current settings" },
    { "lock", "lock/unlock the display" },
    { "test", "show/hide sample icons" },
    { "scale <n>", "display scale (0.5-3)" },
    { "icons <n>", "number of icons shown (1-5)" },
    { "cd", "toggle cooldown recommendations" },
    { "aoe", "cycle AoE mode (auto / single / aoe)" },
    { "pause", "pause/resume recommendations" },
    { "debug", "toggle debug output" },
    { "reset", "reset the current profile to defaults" },
}

function RH:PrintHelp()
    self:Print(("v%s commands:"):format(self.version))
    for _, entry in ipairs(HELP) do
        print(("  |cffffd100/rh %s|r - %s"):format(entry[1], entry[2]))
    end
end

function RH:PrintStatus()
    local p = self.db.profile
    self:Print(("v%s, class %s (%s)"):format(self.version, self.playerClass or "?",
        self.classSupported and "supported" or "not supported"))
    print("  Enabled: " .. Utils.OnOff(p.enabled) .. "  Paused: " .. Utils.OnOff(p.paused))
    print("  Cooldowns: " .. Utils.OnOff(p.toggles.cooldowns) .. "  AoE mode: " .. p.toggles.aoeMode)
    print("  Display locked: " .. Utils.OnOff(p.display.locked) .. "  Debug: " .. Utils.OnOff(p.debug))
    print("  Profile: " .. self.db:GetCurrentProfile())
end

local commands = {
    status = "PrintStatus",
    lock = "ToggleLock",
    unlock = "ToggleLock",
    cd = "ToggleCooldowns",
    cooldowns = "ToggleCooldowns",
    aoe = "CycleAoEMode",
    pause = "TogglePause",
    debug = "ToggleDebug",
    test = "ToggleTestMode",
    scale = "SetScale",
    icons = "SetIconCount",
    help = "PrintHelp",
}

function RH:SlashCommand(input)
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = lower(cmd)
    if cmd == "" then
        self:PrintHelp()
    elseif cmd == "reset" then
        self.db:ResetProfile()
        self:Print("Profile reset.")
    elseif commands[cmd] then
        self[commands[cmd]](self, rest)
    else
        self:Print(("Unknown command '%s'."):format(cmd))
        self:PrintHelp()
    end
end

---------------------------------------------------------------------------
-- Key bindings (names referenced from Bindings.xml)
---------------------------------------------------------------------------
BINDING_HEADER_ROTATIONHELPER = "RotationHelper"
BINDING_NAME_ROTATIONHELPER_TOGGLE_COOLDOWNS = "Toggle Cooldowns"
BINDING_NAME_ROTATIONHELPER_CYCLE_AOE = "Cycle AoE Mode"
BINDING_NAME_ROTATIONHELPER_TOGGLE_PAUSE = "Pause / Resume"
