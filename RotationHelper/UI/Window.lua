local ADDON_NAME, ns = ...
local RH = ns.RH

-- Builds our dark themed windows (options, fight review): a flat frame
-- with a title bar that drags it, an accent line, a close button, Escape
-- to close, and optionally a resize grip.
local Window = {}
ns.Window = Window

local CreateFrame, UIParent = CreateFrame, UIParent
local unpack, tinsert = unpack, table.insert

Window.TITLE_HEIGHT = 34
-- Space around the content area inside the window.
Window.CONTENT_LEFT, Window.CONTENT_RIGHT = 10, 10
Window.CONTENT_TOP, Window.CONTENT_BOTTOM = Window.TITLE_HEIGHT + 10, 14
local CLOSE_GLYPH = "\195\151" -- U+00D7 multiplication sign

function Window.Flat(frame, bg, border)
    frame:SetBackdrop(ns.Skin.BACKDROP)
    frame:SetBackdropColor(unpack(bg))
    frame:SetBackdropBorderColor(unpack(border or bg))
end

-- A font string in the theme font.
function Window.Text(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(ns.Skin.theme.font, size, "")
    fs:SetTextColor(unpack(color))
    return fs
end

local function CreateTitleBar(f, title)
    local T = ns.Skin.theme
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(Window.TITLE_HEIGHT)
    Window.Flat(bar, T.titleBar)
    bar:EnableMouse(true)
    bar:SetScript("OnMouseDown", function() f:StartMoving() end)
    bar:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

    local name = Window.Text(bar, 17, T.accent)
    name:SetPoint("LEFT", 12, 0)
    name:SetText(title)
    local subtitle = Window.Text(bar, 13, T.textDim)
    subtitle:SetPoint("LEFT", name, "RIGHT", 8, -1)

    local line = bar:CreateTexture(nil, "ARTWORK")
    line:SetTexture(unpack(T.accent))
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")

    local close = CreateFrame("Button", nil, bar)
    close:SetWidth(Window.TITLE_HEIGHT)
    close:SetHeight(Window.TITLE_HEIGHT)
    close:SetPoint("RIGHT")
    local glyph = Window.Text(close, 22, T.textDim)
    glyph:SetPoint("CENTER", 0, 1)
    glyph:SetText(CLOSE_GLYPH)
    close:SetScript("OnEnter", function() glyph:SetTextColor(1, 0.35, 0.35) end)
    close:SetScript("OnLeave", function() glyph:SetTextColor(unpack(T.textDim)) end)
    close:SetScript("OnClick", function() f:Hide() end)

    f.titleBar, f.title, f.subtitle, f.closeButton = bar, name, subtitle, close
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

-- opts: name (global frame name), title, subtitle, width, height,
-- minWidth, minHeight (resizable when given). The window starts hidden.
-- Returns the frame; f.content is the inset content area.
function Window.Create(opts)
    local T = ns.Skin.theme
    local f = CreateFrame("Frame", opts.name, UIParent)
    f:Hide()
    f:SetWidth(opts.width)
    f:SetHeight(opts.height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG") -- the strata AceGUI's own windows use
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    Window.Flat(f, T.window, T.border)
    tinsert(UISpecialFrames, opts.name) -- Escape closes it

    CreateTitleBar(f, opts.title)
    f.subtitle:SetText(opts.subtitle or "")
    if opts.minWidth then
        f:SetResizable(true)
        f:SetMinResize(opts.minWidth, opts.minHeight)
        CreateResizeGrip(f)
    end

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", Window.CONTENT_LEFT, -Window.CONTENT_TOP)
    content:SetPoint("BOTTOMRIGHT", -Window.CONTENT_RIGHT, Window.CONTENT_BOTTOM)
    f.content = content
    return f
end
