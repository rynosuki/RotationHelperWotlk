local ADDON_NAME, ns = ...
local RH = ns.RH

-- A separate small icon for the class's interrupt (Death Knight: Mind
-- Freeze), shown above the main icon only while the hostile target casts
-- or channels something interruptible. It never takes a rotation slot.
--
-- Hidden when the interrupt isn't known, or its cooldown won't be over
-- before the cast ends. Keybind, range and runic power tints and the
-- cooldown swipe work like the other icons.
local Interrupt = RH:NewModule("Interrupt", "AceEvent-3.0")
ns.Interrupt = Interrupt

local GetTime, UnitCastingInfo, UnitChannelInfo = GetTime, UnitCastingInfo, UnitChannelInfo
local max = math.max

local PREVIEW_CAST_SECONDS = 2

local entry = {} -- reused display entry

-- Seconds left on the target's interruptible cast or channel, or nil.
-- 3.3.5: notInterruptible is the 9th return for casts, the 8th for channels.
function Interrupt:TargetCastRemains(now)
    local name, _, _, _, _, endTime, _, _, notInterruptible = UnitCastingInfo("target")
    if not name then
        name, _, _, _, _, endTime, _, notInterruptible = UnitChannelInfo("target")
    end
    if not name or notInterruptible or not endTime then return nil end
    return max(0, endTime / 1000 - now)
end

-- The entry to show, or nil. `s` is the real state.
function Interrupt:GetEntry(s, now)
    local key = RH.classData.interrupt
    local ability = key and RH.classData.abilities[key]
    if not (ability and ns.Spec.known[key]) then return nil end

    local castRemains
    if ns.Display.testMode or not ns.Display.db.locked then
        castRemains = PREVIEW_CAST_SECONDS -- sample, so it can be seen while positioning
    else
        local t = s.target
        if not (t.exists and t.canAttack and not t.dead) then return nil end
        castRemains = self:TargetCastRemains(now)
        if not castRemains then return nil end
    end

    local cd = s.cooldowns[key]
    local cdRemains = cd and max(0, cd.readyAt - s.now) or 0
    if cdRemains > castRemains then return nil end -- can't make it

    entry.spellId = ability.id
    entry.wait = cdRemains
    entry.lacksResources = s.power < ns.Abilities.RunicPowerCost(ability)
    return entry
end

function Interrupt:Create()
    local Display = ns.Display
    local b = Display.CreateButton(Display.frame, "RotationHelperInterruptButton", false)
    self.button = b
    self:Layout()
end

function Interrupt:Layout()
    local b, d = self.button, RH.db.profile.display
    local size = d.iconSize * d.queueScale
    b:ClearAllPoints()
    -- Above the main icon, clear of the "drag to move" label.
    b:SetPoint("BOTTOMLEFT", ns.Display.buttons[1], "TOPLEFT", 0, 20)
    ns.Display.SetButtonSize(b, size)
end

function Interrupt:Update(now)
    local Display = ns.Display
    if not Display.frame then return end
    if not self.button then self:Create() end
    local shownEntry = RH.db.profile.display.interrupt and Display.frame:IsShown()
        and self:GetEntry(ns.State.real, now)
    if shownEntry then
        Display:UpdateButton(self.button, shownEntry, true, now)
    else
        self.button:Hide()
    end
end

function Interrupt:OnEnable()
    if not RH.classSupported then return end
    -- Casts start and stop between regular updates; react right away.
    local function OnTargetCast(_, unit)
        if unit == "target" then RH:Invalidate() end
    end
    for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
        self:RegisterEvent(event, OnTargetCast)
    end
    self:RegisterMessage("ROTATIONHELPER_CONFIG_CHANGED", function()
        if Interrupt.button then Interrupt:Layout() end
    end)
    -- After the display, which decides whether the display is shown.
    RH:RegisterUpdater(function(_, now) Interrupt:Update(now) end, RH.UPDATE_ORDER.INTERRUPT,
        "interrupt icon", function() if Interrupt.button then Interrupt.button:Hide() end end)
end
