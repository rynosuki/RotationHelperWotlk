local ADDON_NAME, ns = ...
local RH = ns.RH

-- The recommendation display: one large icon for the next action plus
-- smaller icons for the predicted queue.
--
-- It renders RH.recommendations, an array of entries set by the engine:
--   { spellId = 51425, wait = 0.4, lacksResources = false }
-- `wait` is seconds until the action is usable and drives the cooldown
-- swipe on the main icon.
local Display = RH:NewModule("Display", "AceEvent-3.0")
ns.Display = Display

local GetSpellInfo, GetTime, UnitExists, IsSpellInRange = GetSpellInfo, GetTime, UnitExists, IsSpellInRange
local abs = math.abs

local MAX_ICONS = 5
local FLASH_DURATION = 0.3
local FLASH_ALPHA = 0.55
local WARN_PULSE_SPEED = 5 -- radians per second
local WHITE = "Interface\\Buttons\\WHITE8X8"

local TINT_NORMAL = { 1, 1, 1 }
local TINT_OUT_OF_RANGE = { 1, 0.25, 0.25 }
local TINT_NO_RESOURCES = { 0.4, 0.5, 1 }

-- Where each queued icon goes relative to the previous one.
local GROW = {
    RIGHT = { "LEFT", "RIGHT", 1, 0 },
    LEFT = { "RIGHT", "LEFT", -1, 0 },
    UP = { "BOTTOM", "TOP", 0, 1 },
    DOWN = { "TOP", "BOTTOM", 0, -1 },
}

-- Obliterate, Frost Strike, Howling Blast, Icy Touch, Horn of Winter
local PREVIEW = {
    { spellId = 51425, wait = 0 },
    { spellId = 55268 },
    { spellId = 51411 },
    { spellId = 49909 },
    { spellId = 57623 },
}

local spellCache = {}

local function SpellInfo(spellId)
    local info = spellCache[spellId]
    if not info then
        local name, _, icon = GetSpellInfo(spellId)
        info = { name = name, icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark" }
        spellCache[spellId] = info
    end
    return info
end

---------------------------------------------------------------------------
-- Frame construction
---------------------------------------------------------------------------
-- Creates an icon button (also used by the interrupt icon). `large` picks
-- the bigger keybind font used on the main icon.
function Display.CreateButton(parent, name, large)
    local b = CreateFrame("Frame", name, parent)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b:SetBackdropColor(0, 0, 0, 0.6)
    b:SetBackdropBorderColor(0, 0, 0, 1)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints(b.icon)
    b.cooldown:Hide()

    -- Keybind text sits above the cooldown swipe.
    b.overlay = CreateFrame("Frame", nil, b)
    b.overlay:SetAllPoints(b)
    b.overlay:SetFrameLevel(b.cooldown:GetFrameLevel() + 1)
    b.key = b.overlay:CreateFontString(nil, "OVERLAY", large and "NumberFontNormal" or "NumberFontNormalSmall")
    b.key:SetPoint("TOPRIGHT", -2, -3)
    b.key:SetJustifyH("RIGHT")

    -- "Press now" flash: brightens the icon briefly (additive white).
    b.flash = b.overlay:CreateTexture(nil, "OVERLAY")
    b.flash:SetAllPoints(b.icon)
    b.flash:SetTexture(1, 1, 1)
    b.flash:SetBlendMode("ADD")
    b.flash:Hide()

    b:Hide()
    return b
end

function Display:CreateFrames()
    local f = CreateFrame("Frame", "RotationHelperDisplay", UIParent)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        Display:SavePosition()
    end)

    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 4)
    f.label:SetText("RotationHelper: drag to move, /rh lock when done")

    self.frame = f
    self.buttons = {}
    for i = 1, MAX_ICONS do
        self.buttons[i] = Display.CreateButton(f, "RotationHelperButton" .. i, i == 1)
    end

    -- Waste warning: an orange border around the main icon that pulses.
    local main = self.buttons[1]
    local warn = CreateFrame("Frame", nil, main)
    warn:SetPoint("TOPLEFT", -3, 3)
    warn:SetPoint("BOTTOMRIGHT", 3, -3)
    warn:SetBackdrop({ edgeFile = WHITE, edgeSize = 2 })
    warn:SetBackdropBorderColor(1, 0.5, 0, 1)
    warn:Hide()
    main.warn = warn

    -- Toggle states under the main icon, e.g. "CD  AUTO 3".
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", self.buttons[1], "BOTTOMLEFT", 0, -2)

    -- Shown after an error until /rh errors has been used.
    f.errorMark = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.errorMark:SetPoint("RIGHT", self.buttons[1], "LEFT", -4, 0)
    f.errorMark:SetTextColor(1, 0.2, 0.2)
    f.errorMark:SetText("!")
    f.errorMark:Hide()

    -- Per frame, only while the display is shown: times the flash exactly,
    -- since the GCD ending fires no event and updates run at most 20/s.
    f:SetScript("OnUpdate", function() Display:Animate(GetTime()) end)
end

function Display:StartFlash(b, now)
    -- Only the main icon animates its flash.
    if b == self.buttons[1] and self.db.pressFlash and b:IsShown() then b.flashStart = now end
end

-- Flashes the main icon when its predicted ready time is reached, and
-- pulses the waste warning.
function Display:Animate(now)
    local b = self.buttons[1]
    if b.warn:IsShown() then
        b.warn:SetAlpha(0.35 + 0.65 * abs(math.sin(now * WARN_PULSE_SPEED)))
    end
    if b.readyAt and now >= b.readyAt then
        b.readyAt = nil
        self:StartFlash(b, now)
    end
    local start = b.flashStart
    if start then
        local t = now - start
        if t >= FLASH_DURATION then
            b.flash:Hide()
            b.flashStart = nil
        else
            b.flash:SetAlpha(FLASH_ALPHA * (1 - t / FLASH_DURATION))
            b.flash:Show()
        end
    end
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function Display:SavePosition()
    local point, _, relPoint, x, y = self.frame:GetPoint(1)
    self.db.point = { point, "UIParent", relPoint, x, y }
end

function Display:ApplySettings()
    self.db = RH.db.profile.display
    local d, f = self.db, self.frame

    f:ClearAllPoints()
    local p = d.point
    f:SetPoint(p[1], _G[p[2]] or UIParent, p[3], p[4], p[5])
    f:SetScale(d.scale)
    f:SetWidth(d.iconSize)
    f:SetHeight(d.iconSize)
    f:EnableMouse(not d.locked)

    local grow = GROW[d.direction] or GROW.RIGHT
    local queueSize = d.iconSize * d.queueScale
    for i, b in ipairs(self.buttons) do
        b:ClearAllPoints()
        if i == 1 then
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
            b:SetWidth(d.iconSize)
            b:SetHeight(d.iconSize)
        else
            b:SetPoint(grow[1], self.buttons[i - 1], grow[2], grow[3] * d.spacing, grow[4] * d.spacing)
            b:SetWidth(queueSize)
            b:SetHeight(queueSize)
        end
    end

    self:Refresh()
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------
function Display:SetTestMode(enabled)
    self.testMode = enabled
    self:Refresh()
end

-- Returns the entries to draw, or nil to hide the display.
function Display:GetEntries()
    local d = self.db
    local unlockedPreview = not d.locked and RH.classSupported

    if self.testMode or unlockedPreview then
        local recs = RH.recommendations
        if not self.testMode and RH:IsActive() and recs and #recs > 0 then return recs end
        return PREVIEW
    end
    if not RH:IsActive() then return nil end
    if d.hideOutOfCombat and not RH.inCombat then return nil end

    local recs = RH.recommendations
    if recs and #recs > 0 then return recs end
end

-- The setters below skip calls into the client when nothing changed; the
-- display refreshes up to 20 times a second and rarely changes.
local function Tint(b, color)
    if b.tint == color then return end
    b.tint = color
    b.icon:SetVertexColor(color[1], color[2], color[3])
end

local function SetIcon(b, path)
    if b.iconPath == path then return end
    b.iconPath = path
    b.icon:SetTexture(path)
end

local function SetKeyText(b, text)
    if b.keyText == text then return end
    b.keyText = text
    b.key:SetText(text)
end

function Display:UpdateButton(b, entry, isMain, now)
    local info = SpellInfo(entry.spellId)
    SetIcon(b, info.icon)
    SetKeyText(b, ns.Keybinds:Get(info.name) or "")

    if info.name and UnitExists("target") and IsSpellInRange(info.name, "target") == 0 then
        Tint(b, TINT_OUT_OF_RANGE)
    elseif entry.lacksResources then
        Tint(b, TINT_NO_RESOURCES)
    else
        Tint(b, TINT_NORMAL)
    end

    -- Restarting the swipe every refresh would make it flicker, so only
    -- restart it when the predicted ready time actually moves.
    local wait = isMain and entry.wait or 0
    if wait and wait > 0.05 then
        local readyAt = now + wait
        if not b.readyAt or abs(readyAt - b.readyAt) > 0.1 then
            b.cooldown:Show()
            b.cooldown:SetCooldown(now, wait)
            b.readyAt = readyAt
        end
        b.readySpell = entry.spellId
    elseif b.readyAt then
        -- The ability we were counting down to is ready now (a refresh got
        -- here before Animate did).
        if isMain and b.readySpell == entry.spellId then self:StartFlash(b, now) end
        b.cooldown:Hide()
        b.readyAt = nil
    end

    b:Show()
end

function Display:Refresh()
    if not self.frame then return end
    local entries = self:GetEntries()
    -- An unseen error keeps the display (and its "!") visible even when the
    -- error left nothing to recommend.
    local showError = RH.unseenErrors > 0 and RH:IsActive()
    if not entries and not showError then
        self.frame.errorMark:Hide()
        self.frame:Hide()
        return
    end

    local now = GetTime()
    local count = self.db.numIcons
    for i, b in ipairs(self.buttons) do
        local entry = entries and i <= count and entries[i]
        if entry then
            self:UpdateButton(b, entry, i == 1, now)
        else
            b:Hide()
        end
    end

    local showLabel = not self.db.locked
    if showLabel then self.frame.label:Show() else self.frame.label:Hide() end
    if showError then self.frame.errorMark:Show() else self.frame.errorMark:Hide() end
    local waste = RH.waste
    if waste and waste.any and entries then self.buttons[1].warn:Show() else self.buttons[1].warn:Hide() end
    self:UpdateStatus()
    self.frame:Show()
end

local AOE_LABELS = { single = "ST", aoe = "AOE" }

-- "CD" is green when cooldowns are on, red when off. The AoE part shows
-- the forced mode, or in auto mode the enemy count once there's more than one.
function Display:UpdateStatus()
    local status = self.frame.status
    if not self.db.showStatus then
        status:Hide()
        return
    end
    local toggles = RH.db.profile.toggles
    local text = toggles.cooldowns and "|cff40ff40CD|r" or "|cffff4040CD|r"
    local mode = AOE_LABELS[toggles.aoeMode]
    local enemies = ns.State.real.activeEnemies or 1
    if mode then
        text = text .. "  |cffffd100" .. mode .. "|r"
    elseif enemies > 1 then
        text = text .. "  " .. enemies
    end
    local waste = RH.waste
    if waste and waste.runes then text = text .. "  |cffff8000RUNES|r" end
    if waste and waste.runicPower then text = text .. "  |cffff8000RP|r" end
    if status.lastText ~= text then
        status.lastText = text
        status:SetText(text)
    end
    status:Show()
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Display:OnEnable()
    self:CreateFrames()
    self:RegisterMessage("ROTATIONHELPER_CONFIG_CHANGED", "ApplySettings")
    self:RegisterMessage("ROTATIONHELPER_COMBAT_CHANGED", "Refresh")
    RH:RegisterUpdater(function() Display:Refresh() end, RH.UPDATE_ORDER.DISPLAY, "display")
    self:ApplySettings()
end
