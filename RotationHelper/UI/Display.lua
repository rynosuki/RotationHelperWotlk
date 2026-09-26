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
local PlaySound = PlaySound
local abs = math.abs

local MAX_ICONS = 5
local FLASH_DURATION = 0.3
local FLASH_ALPHA = 0.55
local WARN_PULSE_SPEED = 5 -- radians per second
local WHITE = "Interface\\Buttons\\WHITE8X8"
local GLOW_TEXTURE = "Interface\\Buttons\\UI-ActionButton-Border"
local GLOW_SCALE = 1.75 -- the glow ring sits in the middle of that texture
local BADGE_SCALE = 0.42 -- proc badge size relative to the icon
local STATUS_HEIGHT = 14
local CHIP_GAP = 6

-- Sounds for a new proc (PlaySound names in the 3.3.5 client).
Display.PROC_SOUNDS = { none = "None", MapPing = "Ping", RaidWarning = "Raid warning", ReadyCheck = "Ready check" }

local TINT_NORMAL = { 1, 1, 1 }

-- Color presets for the configurable colors (profile.display.colors).
-- The color-blind friendly one uses the Okabe-Ito palette, whose colors
-- stay distinguishable with the common kinds of color blindness.
Display.COLOR_PRESETS = {
    default = {
        outOfRange = { 1, 0.25, 0.25 },
        noResources = { 0.4, 0.5, 1 },
        waste = { 1, 0.5, 0 },
        threat = { 0.9, 0.1, 0.1 },
    },
    colorblind = {
        outOfRange = { 0.84, 0.37, 0 },    -- vermillion
        noResources = { 0.34, 0.71, 0.91 }, -- sky blue
        waste = { 0.9, 0.62, 0 },          -- orange
        threat = { 0.8, 0.47, 0.65 },      -- reddish purple
    },
}

-- What the main icon waits on, when it's more than a GCD away.
local HOLD_LABELS = { runes = "RUNES", cooldown = "COOLDOWN", cast = "CAST", wait = "WAIT" }

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

-- Item abilities (trinkets, potions): name and icon from the entry.
local itemCache = {}
local function ItemInfo(entry)
    local info = itemCache[entry.itemID]
    if not info then
        info = { name = entry.itemName, icon = entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark" }
        itemCache[entry.itemID] = info
    end
    return info
end

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

    -- Proc glow: the action button border glow, around the icon (sized in
    -- Display:SetButtonSize).
    b.glow = b.overlay:CreateTexture(nil, "OVERLAY")
    b.glow:SetTexture(GLOW_TEXTURE)
    b.glow:SetBlendMode("ADD")
    b.glow:SetPoint("CENTER", b, "CENTER")
    b.glow:Hide()

    -- Proc badge: the proc's icon in the bottom-right corner when the proc
    -- is why this ability is recommended.
    local badge = CreateFrame("Frame", nil, b.overlay)
    badge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    badge:SetBackdrop({ bgFile = WHITE })
    badge:SetBackdropColor(0, 0, 0, 1)
    badge.icon = badge:CreateTexture(nil, "ARTWORK")
    badge.icon:SetPoint("TOPLEFT", 1, -1)
    badge.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    badge.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    badge:Hide()
    b.badge = badge

    -- Hold label: what the main icon waits on (RUNES, COOLDOWN, ...).
    b.hold = b.overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.hold:SetPoint("BOTTOM", b, "BOTTOM", 0, 2)
    b.hold:SetTextColor(1, 1, 1)
    b.hold:SetShadowOffset(1, -1)
    b.hold:Hide()

    b:Hide()
    return b
end

function Display.SetButtonSize(b, size)
    b:SetWidth(size)
    b:SetHeight(size)
    b.glow:SetWidth(size * GLOW_SCALE)
    b.glow:SetHeight(size * GLOW_SCALE)
    b.badge:SetWidth(size * BADGE_SCALE)
    b.badge:SetHeight(size * BADGE_SCALE)
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
    warn:Hide()
    main.warn = warn

    -- Threat warning: a steady border outside the waste border.
    local threat = CreateFrame("Frame", nil, main)
    threat:SetPoint("TOPLEFT", -6, 6)
    threat:SetPoint("BOTTOMRIGHT", 6, -6)
    threat:SetBackdrop({ edgeFile = WHITE, edgeSize = 2 })
    threat:Hide()
    main.threat = threat

    -- In-range alternative when the main ability is out of range, below
    -- the status line.
    self.altButton = Display.CreateButton(f, "RotationHelperAlternativeButton", false)

    -- Status line under the main icon: "CD", the AoE mode or enemy count,
    -- and waste labels. The first two are chips that Shift-click toggles.
    local status = CreateFrame("Frame", nil, f)
    status:SetPoint("TOPLEFT", self.buttons[1], "BOTTOMLEFT", 0, -2)
    status:SetWidth(1)
    status:SetHeight(STATUS_HEIGHT)
    f.status = status
    f.cdChip = self:CreateChip(status, function() RH:ToggleCooldowns() end)
    f.cdChip:SetPoint("TOPLEFT", status, "TOPLEFT")
    f.aoeChip = self:CreateChip(status, function() RH:CycleAoEMode() end)
    f.aoeChip:SetPoint("LEFT", f.cdChip, "RIGHT", CHIP_GAP, 0)
    f.wasteText = status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.wasteText:SetPoint("LEFT", f.aoeChip, "RIGHT", CHIP_GAP, 0)

    -- Pre-pull checklist, e.g. "Missing: Flask, Food" (out of combat only,
    -- so it can share the space of the in-range alternative icon).
    f.checklist = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.checklist:SetPoint("TOPLEFT", self.buttons[1], "BOTTOMLEFT", 0, -(STATUS_HEIGHT + 4))
    f.checklist:SetTextColor(1, 0.6, 0.2)
    f.checklist:SetJustifyH("LEFT")
    f.checklist:Hide()

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
    self:UpdateMouseMode()
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
            Display.SetButtonSize(b, d.iconSize)
        else
            b:SetPoint(grow[1], self.buttons[i - 1], grow[2], grow[3] * d.spacing, grow[4] * d.spacing)
            Display.SetButtonSize(b, queueSize)
        end
        b.tint = nil -- colors may have changed
    end

    local main, colors = self.buttons[1], d.colors
    main.warn:SetBackdropBorderColor(colors.waste[1], colors.waste[2], colors.waste[3], 1)
    main.threat:SetBackdropBorderColor(colors.threat[1], colors.threat[2], colors.threat[3], 1)
    local alt = self.altButton
    alt:ClearAllPoints()
    alt:SetPoint("TOPLEFT", main, "BOTTOMLEFT", 0, -(STATUS_HEIGHT + 4))
    Display.SetButtonSize(alt, queueSize)
    alt.tint = nil

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
    local info = entry.itemID and ItemInfo(entry) or SpellInfo(entry.spellId)
    SetIcon(b, info.icon)
    SetKeyText(b, ns.Keybinds:Get(info.name) or "")

    local colors = self.db.colors
    if info.name and UnitExists("target") and IsSpellInRange(info.name, "target") == 0 then
        Tint(b, colors.outOfRange)
    elseif entry.lacksResources then
        Tint(b, colors.noResources)
    else
        Tint(b, TINT_NORMAL)
    end

    -- Hold label on the main icon when it's more than a GCD away.
    local hold = isMain and self.db.holdIndicator and entry.wait
        and entry.wait > (ns.State.real.gcdDuration or 1.5) and HOLD_LABELS[entry.limitedBy]
    if hold then
        if b.holdText ~= hold then
            b.holdText = hold
            b.hold:SetText(hold)
        end
        b.hold:Show()
    else
        b.hold:Hide()
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
    -- The checklist also keeps it visible: before a pull there's often
    -- nothing to press yet.
    local checklist = RH:IsActive() and RH.checklist
    if not entries and not showError and not checklist then
        self.frame.errorMark:Hide()
        self.frame.checklist:Hide()
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
    self:UpdateChecklist(checklist)
    local main = self.buttons[1]
    local waste = RH.waste
    if waste and waste.any and entries then main.warn:Show() else main.warn:Hide() end
    local threat = RH.threat
    if threat and threat.warn and entries then main.threat:Show() else main.threat:Hide() end

    local alternative = self.db.alternative and entries and RH.alternative
    if alternative then
        self:UpdateButton(self.altButton, alternative, false, now)
    else
        self.altButton:Hide()
    end
    self:UpdateProcs(entries, count)
    self:UpdateStatus()
    self.frame:Show()
end

local AOE_LABELS = { single = "ST", aoe = "AOE" }

-- A small clickable text on the status line. Only takes the mouse while
-- Shift is held (see UI/DisplayMouse.lua).
function Display:CreateChip(parent, onClick)
    local chip = CreateFrame("Button", nil, parent)
    chip:SetHeight(STATUS_HEIGHT)
    chip.text = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chip.text:SetPoint("LEFT", chip, "LEFT")
    chip:SetScript("OnClick", onClick)
    chip:EnableMouse(false)
    return chip
end

-- Sets a chip's text and width; an empty text hides it.
local function SetChipText(chip, text)
    if chip.lastText ~= text then
        chip.lastText = text
        chip.text:SetText(text)
        chip:SetWidth(math.max(1, chip.text:GetStringWidth()))
    end
    if text == "" then chip:Hide() else chip:Show() end
end

-- "CD" is green when cooldowns are on, red when off. The AoE chip shows
-- the forced mode, or in auto mode the enemy count once there's more than
-- one ("AUTO" while Shift is held, so there's always something to click).
-- Waste labels follow.
function Display:UpdateStatus()
    local f = self.frame
    if not self.db.showStatus then
        f.status:Hide()
        return
    end
    local toggles = RH.db.profile.toggles
    SetChipText(f.cdChip, toggles.cooldowns and "|cff40ff40CD|r" or "|cffff4040CD|r")

    local mode = AOE_LABELS[toggles.aoeMode]
    local enemies = ns.State.real.activeEnemies or 1
    local aoeText = ""
    if mode then
        aoeText = "|cffffd100" .. mode .. "|r"
    elseif enemies > 1 then
        aoeText = tostring(enemies)
    elseif self.mouseMode then
        aoeText = "|cff999999AUTO|r"
    end
    SetChipText(f.aoeChip, aoeText)

    local waste = RH.waste
    local wasteText = ""
    if waste and waste.runes then wasteText = "|cffff8000RUNES|r" end
    if waste and waste.runicPower then
        wasteText = wasteText == "" and "|cffff8000RP|r" or (wasteText .. "  |cffff8000RP|r")
    end
    local threat = RH.threat
    if threat and threat.warn then
        wasteText = wasteText == "" and "|cffff2020THREAT|r" or (wasteText .. "  |cffff2020THREAT|r")
    end
    if f.wasteText.lastText ~= wasteText then
        f.wasteText.lastText = wasteText
        f.wasteText:SetText(wasteText)
    end
    -- Waste labels move left when the AoE chip is empty (re-anchored only
    -- when that changes; this runs 20 times a second).
    local anchor = f.aoeChip:IsShown() and f.aoeChip or f.cdChip
    if f.wasteText.anchor ~= anchor then
        f.wasteText.anchor = anchor
        f.wasteText:ClearAllPoints()
        f.wasteText:SetPoint("LEFT", anchor, "RIGHT", CHIP_GAP, 0)
    end
    f.status:Show()
end

-- "Missing: Flask, Food"; the text is only rebuilt when the list changes.
function Display:UpdateChecklist(checklist)
    local fs = self.frame.checklist
    if not checklist then
        fs:Hide()
        fs.key = nil
        return
    end
    local key = table.concat(checklist, ", ")
    if fs.key ~= key then
        fs.key = key
        fs:SetText("Missing: " .. key)
    end
    fs:Show()
end

-- The status line as plain text, e.g. "CD  3  RP" (for tests and debugging).
function Display:GetStatusText()
    local f, parts = self.frame, {}
    if not f.status:IsShown() then return "" end
    for _, fs in ipairs({ f.cdChip:IsShown() and f.cdChip.text, f.aoeChip:IsShown() and f.aoeChip.text, f.wasteText }) do
        local text = fs and fs:GetText()
        if text and text ~= "" then parts[#parts + 1] = (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    end
    return table.concat(parts, "  ")
end

-- Proc glow on buttons whose ability spends a proc, and a sound once per
-- new proc (a proc is new when its expiry time changes).
-- The icon of a proc aura, e.g. Killing Machine's.
local function ProcIcon(key)
    local def = RH.classData.auras[key]
    local id = def and (def.id or (def.ids and def.ids[1]))
    return id and SpellInfo(id).icon
end

function Display:UpdateProcs(entries, count)
    local glowOn, badgeOn = self.db.procGlow, self.db.procBadge
    for i, b in ipairs(self.buttons) do
        local entry = entries and i <= count and entries[i]
        local shown = entry and b:IsShown()
        if glowOn and shown and entry.usesProc then b.glow:Show() else b.glow:Hide() end
        local reason = badgeOn and shown and entry.procReason
        if reason then
            local icon = ProcIcon(reason)
            if b.badge.iconPath ~= icon then
                b.badge.iconPath = icon
                b.badge.icon:SetTexture(icon)
            end
            b.badge:Show()
        else
            b.badge:Hide()
        end
    end
    local main = entries and entries[1]
    local sound = self.db.procSound
    if main and main.usesProc and sound and sound ~= "none" then
        local key = main.usesProc
        self.procHeard = self.procHeard or {}
        if self.procHeard[key] ~= main.procExpires then
            self.procHeard[key] = main.procExpires
            PlaySound(sound)
        end
    end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Display:OnEnable()
    self:CreateFrames()
    self:SetupMouse()
    self:RegisterMessage("ROTATIONHELPER_CONFIG_CHANGED", "ApplySettings")
    self:RegisterMessage("ROTATIONHELPER_COMBAT_CHANGED", "Refresh")
    RH:RegisterUpdater(function() Display:Refresh() end, RH.UPDATE_ORDER.DISPLAY, "display")
    self:ApplySettings()
end
