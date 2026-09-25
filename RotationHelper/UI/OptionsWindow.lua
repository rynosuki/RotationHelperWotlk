local ADDON_NAME, ns = ...
local RH = ns.RH

-- The options window: a dark frame of our own that AceConfigDialog draws
-- the options table into (AceConfigDialog:Open(app, container)). Controls
-- inside are styled by UI/Skin.lua.
--
-- AceConfigDialog redraws the container itself after a control changes a
-- value, and the TabGroup redraws its content on tab switches. A sweep runs
-- every frame while the window is open so new controls are styled before
-- they're drawn; it only checks a flag on each widget.
local Window = {}
ns.OptionsWindow = Window

local CreateFrame, LibStub, UIParent = CreateFrame, LibStub, UIParent
local unpack, tinsert = unpack, table.insert

local DEFAULT_WIDTH, DEFAULT_HEIGHT = 820, 660
local MIN_WIDTH, MIN_HEIGHT = 640, 480
local TITLE_HEIGHT = 34
local CLOSE_GLYPH = "\195\151" -- U+00D7 multiplication sign

local function Flat(frame, bg, border)
    frame:SetBackdrop(ns.Skin.BACKDROP)
    frame:SetBackdropColor(unpack(bg))
    frame:SetBackdropBorderColor(unpack(border or bg))
end

local function Text(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(ns.Skin.theme.font, size, "")
    fs:SetTextColor(unpack(color))
    return fs
end

local function CreateTitleBar(self, f)
    local T = ns.Skin.theme
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(TITLE_HEIGHT)
    Flat(bar, T.titleBar)
    bar:EnableMouse(true)
    bar:SetScript("OnMouseDown", function() f:StartMoving() end)
    bar:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

    local name = Text(bar, 17, T.accent)
    name:SetPoint("LEFT", 12, 0)
    name:SetText("RotationHelper")
    local version = Text(bar, 13, T.textDim)
    version:SetPoint("LEFT", name, "RIGHT", 8, -1)
    version:SetText("v" .. RH.version)

    local line = bar:CreateTexture(nil, "ARTWORK")
    line:SetTexture(unpack(T.accent))
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")

    local close = CreateFrame("Button", nil, bar)
    close:SetWidth(TITLE_HEIGHT)
    close:SetHeight(TITLE_HEIGHT)
    close:SetPoint("RIGHT")
    local glyph = Text(close, 22, T.textDim)
    glyph:SetPoint("CENTER", 0, 1)
    glyph:SetText(CLOSE_GLYPH)
    close:SetScript("OnEnter", function() glyph:SetTextColor(1, 0.35, 0.35) end)
    close:SetScript("OnLeave", function() glyph:SetTextColor(unpack(T.textDim)) end)
    close:SetScript("OnClick", function() f:Hide() end)
    self.closeButton = close
end

local function CreateResizeGrip(f)
    local grip = CreateFrame("Button", nil, f)
    grip:SetWidth(16)
    grip:SetHeight(16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)
end

-- Builds the window. Returns nil if AceGUI isn't available.
function Window:Create()
    local AceGUI = LibStub("AceGUI-3.0", true)
    if not AceGUI then return nil end
    local T = ns.Skin.theme

    local f = CreateFrame("Frame", "RotationHelperOptionsWindow", UIParent)
    f:Hide()
    f:SetWidth(DEFAULT_WIDTH)
    f:SetHeight(DEFAULT_HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG") -- the strata AceGUI's own windows use
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    Flat(f, T.window, T.border)
    tinsert(UISpecialFrames, f:GetName()) -- Escape closes it

    CreateTitleBar(self, f)
    CreateResizeGrip(f)

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 10, -(TITLE_HEIGHT + 10))
    content:SetPoint("BOTTOMRIGHT", -10, 14)

    -- Held for the window's lifetime, never released back to AceGUI.
    local container = AceGUI:Create("SimpleGroup")
    container:SetLayout("Fill")
    container.frame:SetParent(content)
    container.frame:SetFrameStrata(content:GetFrameStrata())
    container.frame:SetFrameLevel(content:GetFrameLevel() + 1)
    container.frame:ClearAllPoints()
    container.frame:SetPoint("TOPLEFT", content, "TOPLEFT")
    container.frame:Show()
    self.container = container

    local function Resize()
        container:SetWidth(content:GetWidth())
        container:SetHeight(content:GetHeight())
        container:DoLayout()
    end
    content:SetScript("OnSizeChanged", Resize)

    f:SetScript("OnShow", Resize)
    f:SetScript("OnHide", function()
        -- Give the widgets back to AceGUI; releasing them undoes our styling.
        container:ReleaseChildren()
    end)
    f:SetScript("OnUpdate", function()
        if self.renderPending then
            self.renderPending = false
            self:Render()
        end
        self:Style()
    end)

    LibStub("AceConfigRegistry-3.0").RegisterCallback(self, "ConfigTableChange", "OnConfigTableChange")
    self.frame = f
    return f
end

function Window:Render()
    LibStub("AceConfigDialog-3.0"):Open(ADDON_NAME, self.container)
    self:Style()
end

-- Styles any new widgets, and lays everything out again if some were.
function Window:Style()
    if ns.Skin.ApplyTree(self.container) > 0 then
        ns.Skin.Relayout(self.container)
    end
end

-- Redraw on the next frame, e.g. after a slash command changed a setting
-- while the window is open.
function Window:QueueRender()
    if self.frame and self.frame:IsShown() then self.renderPending = true end
end

function Window:OnConfigTableChange(_, appName)
    if appName == ADDON_NAME then self:QueueRender() end
end

-- Opens the window, optionally on a tab ("rotation"). Returns false if the
-- config libraries aren't available.
function Window:Open(tab)
    local dialog = LibStub("AceConfigDialog-3.0", true)
    if not dialog then return false end
    if not self.frame and not self:Create() then return false end
    if tab then dialog:SelectGroup(ADDON_NAME, tab) end
    self.frame:Show()
    self:Render()
    return true
end

function Window:Close()
    if self.frame then self.frame:Hide() end
end
