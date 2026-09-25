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
local function CreateButton(parent, index)
    local b = CreateFrame("Frame", "RotationHelperButton" .. index, parent)
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
    b.key = b.overlay:CreateFontString(nil, "OVERLAY", index == 1 and "NumberFontNormal" or "NumberFontNormalSmall")
    b.key:SetPoint("TOPRIGHT", -2, -3)
    b.key:SetJustifyH("RIGHT")

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
        self.buttons[i] = CreateButton(f, i)
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

local function Tint(texture, color)
    texture:SetVertexColor(color[1], color[2], color[3])
end

function Display:UpdateButton(b, entry, isMain, now)
    local info = SpellInfo(entry.spellId)
    b.icon:SetTexture(info.icon)
    b.key:SetText(ns.Keybinds:Get(info.name) or "")

    if info.name and UnitExists("target") and IsSpellInRange(info.name, "target") == 0 then
        Tint(b.icon, TINT_OUT_OF_RANGE)
    elseif entry.lacksResources then
        Tint(b.icon, TINT_NO_RESOURCES)
    else
        Tint(b.icon, TINT_NORMAL)
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
    elseif b.readyAt then
        b.cooldown:Hide()
        b.readyAt = nil
    end

    b:Show()
end

function Display:Refresh()
    if not self.frame then return end
    local entries = self:GetEntries()
    if not entries then
        self.frame:Hide()
        return
    end

    local now = GetTime()
    local count = self.db.numIcons
    for i, b in ipairs(self.buttons) do
        local entry = i <= count and entries[i]
        if entry then
            self:UpdateButton(b, entry, i == 1, now)
        else
            b:Hide()
        end
    end

    local showLabel = not self.db.locked
    if showLabel then self.frame.label:Show() else self.frame.label:Hide() end
    self.frame:Show()
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Display:OnEnable()
    self:CreateFrames()
    self:RegisterMessage("ROTATIONHELPER_CONFIG_CHANGED", "ApplySettings")
    self:RegisterMessage("ROTATIONHELPER_COMBAT_CHANGED", "Refresh")
    RH:RegisterUpdater(function() Display:Refresh() end)
    self:ApplySettings()
end
