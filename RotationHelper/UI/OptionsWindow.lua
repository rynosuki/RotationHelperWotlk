local ADDON_NAME, ns = ...
local RH = ns.RH

-- The options window: one of our themed windows (UI/Window.lua) that
-- AceConfigDialog draws the options table into (AceConfigDialog:Open(app,
-- container)). Controls inside are styled by UI/Skin.lua.
--
-- AceConfigDialog redraws the container itself after a control changes a
-- value, and the TabGroup redraws its content on tab switches. A sweep runs
-- every frame while the window is open so new controls are styled before
-- they're drawn; it only checks a flag on each widget.
local Window = {}
ns.OptionsWindow = Window

local LibStub = LibStub

local DEFAULT_WIDTH, DEFAULT_HEIGHT = 820, 660
local MIN_WIDTH, MIN_HEIGHT = 640, 480

-- Builds the window. Returns nil if AceGUI isn't available.
function Window:Create()
    local AceGUI = LibStub("AceGUI-3.0", true)
    if not AceGUI then return nil end

    local f = ns.Window.Create({
        name = "RotationHelperOptionsWindow", title = "RotationHelper", subtitle = "v" .. RH.version,
        width = DEFAULT_WIDTH, height = DEFAULT_HEIGHT, minWidth = MIN_WIDTH, minHeight = MIN_HEIGHT,
    })
    self.closeButton = f.closeButton
    local content = f.content

    -- Held for the window's lifetime, never released back to AceGUI.
    local container = AceGUI:Create("SimpleGroup")
    container:SetLayout("Fill")
    -- By default a SimpleGroup shrinks to fit its content after each layout.
    -- Its content (the tab group) fills it, so starting from 0 it could never
    -- grow back: the window decides the height instead.
    container:SetAutoAdjustHeight(false)
    container.frame:SetParent(content)
    container.frame:SetFrameStrata(content:GetFrameStrata())
    container.frame:SetFrameLevel(content:GetFrameLevel() + 1)
    container.frame:ClearAllPoints()
    container.frame:SetPoint("TOPLEFT", content, "TOPLEFT")
    container.frame:Show()
    self.container = container

    f:SetScript("OnSizeChanged", function() self:Resize() end)
    f:SetScript("OnShow", function() self:Resize() end)
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

-- Sizes the container from the window's own size (an anchored frame's
-- size reads as 0 right after the window is shown).
function Window:Resize()
    local f, W = self.frame, ns.Window
    self.container:SetWidth(f:GetWidth() - W.CONTENT_LEFT - W.CONTENT_RIGHT)
    self.container:SetHeight(f:GetHeight() - W.CONTENT_TOP - W.CONTENT_BOTTOM)
    self.container:DoLayout()
end

function Window:Render()
    self:Resize()
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
