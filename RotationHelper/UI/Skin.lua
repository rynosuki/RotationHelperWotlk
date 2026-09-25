local ADDON_NAME, ns = ...

-- A flat dark theme for the AceGUI controls in our options window.
--
-- AceGUI widgets are pooled and shared by every addon, so a widget we
-- restyle can later be handed to someone else's options. Every change made
-- here is therefore recorded with a way to undo it, and undone when AceGUI
-- releases the widget (we wrap that widget's OnRelease). Textures we add
-- are kept on the widget for reuse and hidden while it isn't ours.
local Skin = {}
ns.Skin = Skin

local CreateFrame = CreateFrame
local ipairs, select, type, unpack = ipairs, select, type, unpack

Skin.theme = {
    font = "Fonts\\ARIALN.TTF", -- Arial Narrow, shipped with the 3.3.5 client
    window = { 0.06, 0.06, 0.08, 0.97 },
    titleBar = { 0.08, 0.08, 0.10, 1 },
    panel = { 0.09, 0.09, 0.11, 1 },
    control = { 0.14, 0.14, 0.16, 1 },
    controlHover = { 0.20, 0.20, 0.24, 1 },
    border = { 0.22, 0.22, 0.25, 1 },
    accent = { 0.09, 0.52, 0.82, 1 },
    text = { 0.92, 0.92, 0.92, 1 },
    textDim = { 0.60, 0.60, 0.63, 1 },
    heading = { 0.35, 0.68, 0.95, 1 },
}
local T = Skin.theme

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
Skin.BACKDROP = { bgFile = FLAT, edgeFile = FLAT, edgeSize = 1, tile = false,
    insets = { left = 0, right = 0, top = 0, bottom = 0 } }

---------------------------------------------------------------------------
-- Recorded changes
---------------------------------------------------------------------------
local function Record(w, undo)
    local list = w.rhUndo
    if not list then
        list = {}
        w.rhUndo = list
    end
    list[#list + 1] = undo
end

-- Hides a texture by alpha, so the widget's own Show/Hide calls can't bring it back.
local function Fade(w, region)
    if not region or (w.rhOwn and w.rhOwn[region]) then return end
    local alpha = region:GetAlpha()
    region:SetAlpha(0)
    Record(w, function() region:SetAlpha(alpha) end)
end

-- Fades every texture directly on `frame` (not our own).
local function FadeTextures(w, frame)
    for i = 1, select("#", frame:GetRegions()) do
        local region = select(i, frame:GetRegions())
        if region and region.GetObjectType and region:GetObjectType() == "Texture" then
            Fade(w, region)
        end
    end
end

-- Switches a font string (or edit box) to the theme font. `size` defaults
-- to its current size, one point larger since Arial Narrow runs small.
local function Font(w, fs, size, flags)
    if not fs then return end
    local path, oldSize, oldFlags = fs:GetFont()
    local fontObject = fs.GetFontObject and fs:GetFontObject()
    fs:SetFont(T.font, size or ((oldSize or 12) + 1), flags or "")
    Record(w, function()
        if path then
            fs:SetFont(path, oldSize, oldFlags)
        elseif fontObject then
            fs:SetFontObject(fontObject)
        end
    end)
end

local function TextColor(w, fs, color)
    if not fs then return end
    local r, g, b, a = fs:GetTextColor()
    fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    Record(w, function() fs:SetTextColor(r, g, b, a) end)
end

local function Backdrop(w, frame, bg, border)
    -- Without GetBackdrop the original couldn't be put back, so leave it be.
    if not (frame and frame.GetBackdrop) then return end
    local old = frame:GetBackdrop()
    local r, g, b, a, br, bgr, bb, ba
    if old then
        r, g, b, a = frame:GetBackdropColor()
        br, bgr, bb, ba = frame:GetBackdropBorderColor()
    end
    frame:SetBackdrop(Skin.BACKDROP)
    frame:SetBackdropColor(unpack(bg))
    frame:SetBackdropBorderColor(unpack(border))
    Record(w, function()
        frame:SetBackdrop(old)
        if old then
            frame:SetBackdropColor(r, g, b, a)
            frame:SetBackdropBorderColor(br, bgr, bb, ba)
        end
    end)
end

-- A texture of ours on `owner`, created once per widget and reused.
local function OwnTexture(w, key, owner, layer)
    w.rhTextures = w.rhTextures or {}
    w.rhOwn = w.rhOwn or {}
    local tex = w.rhTextures[key]
    if not tex then
        tex = owner:CreateTexture(nil, layer)
        w.rhTextures[key] = tex
        w.rhOwn[tex] = true
    end
    tex:ClearAllPoints()
    tex:Show()
    Record(w, function() tex:Hide() end)
    return tex
end

-- A flat box drawn under the widget's own art: a 1px border and a fill.
-- `anchor(tex, inset)` positions both. Returns the fill texture.
local function Box(w, key, owner, anchor, fill, border)
    local edge = OwnTexture(w, key .. "Edge", owner, "BACKGROUND")
    local body = OwnTexture(w, key .. "Fill", owner, "BORDER")
    anchor(edge, 0)
    anchor(body, 1)
    edge:SetTexture(unpack(border or T.border))
    body:SetTexture(unpack(fill or T.control))
    return body, edge
end

local function Around(region, left, top, right, bottom)
    left, top, right, bottom = left or 0, top or 0, right or 0, bottom or 0
    return function(tex, inset)
        tex:SetPoint("TOPLEFT", region, "TOPLEFT", left + inset, top - inset)
        tex:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", right - inset, bottom + inset)
    end
end

-- Hover highlight for one of our boxes. Hooks can't be removed, so the hook
-- is added once per frame and only acts while the widget is ours.
local function Hover(w, frame, fill, normal)
    if not frame.rhHoverHooked then
        frame.rhHoverHooked = true
        frame:HookScript("OnEnter", function(f)
            local box = f.rhHoverBox
            if box and box:IsShown() and not f.rhHoverLocked then box:SetTexture(unpack(T.controlHover)) end
        end)
        frame:HookScript("OnLeave", function(f)
            local box = f.rhHoverBox
            if box and box:IsShown() and not f.rhHoverLocked then box:SetTexture(unpack(f.rhHoverNormal)) end
        end)
    end
    frame.rhHoverBox = fill
    frame.rhHoverNormal = normal or T.control
    Record(w, function() frame.rhHoverBox = nil end)
end

---------------------------------------------------------------------------
-- Scroll bars (UIPanelScrollBarTemplate and plain sliders)
---------------------------------------------------------------------------
-- Hides a whole frame (e.g. a scroll arrow button) by alpha.
local function FadeFrame(w, frame)
    if not frame then return end
    local alpha = frame:GetAlpha()
    frame:SetAlpha(0)
    Record(w, function() frame:SetAlpha(alpha) end)
end

local function ScrollBar(w, bar)
    if not bar then return end
    -- The gold arrow buttons; the wheel and the thumb still scroll.
    local name = bar:GetName()
    if name then
        FadeFrame(w, _G[name .. "ScrollUpButton"])
        FadeFrame(w, _G[name .. "ScrollDownButton"])
    end
    local thumb = bar:GetThumbTexture()
    if thumb then
        local path, width, height = thumb:GetTexture(), thumb:GetWidth(), thumb:GetHeight()
        thumb:SetTexture(unpack(T.controlHover))
        thumb:SetWidth(8)
        thumb:SetHeight(24)
        Record(w, function()
            thumb:SetTexture(path)
            thumb:SetWidth(width)
            thumb:SetHeight(height)
        end)
    end
    Box(w, "scrollTrack", bar, Around(bar, 4, 0, -4, 0), T.panel, T.panel)
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
local skinners = {}

function skinners.CheckBox(w)
    Fade(w, w.checkbg)
    Fade(w, w.highlight)
    Box(w, "box", w.frame, function(tex, inset)
        tex:SetPoint("CENTER", w.checkbg, "CENTER")
        tex:SetWidth(16 - 2 * inset)
        tex:SetHeight(16 - 2 * inset)
    end)
    -- The check becomes a small accent square.
    local check = w.check
    local path = check:GetTexture()
    check:SetTexture(unpack(T.accent))
    check:ClearAllPoints()
    check:SetPoint("CENTER", w.checkbg, "CENTER")
    check:SetWidth(8)
    check:SetHeight(8)
    Record(w, function()
        check:SetTexture(path)
        check:SetVertexColor(1, 1, 1)
        check:ClearAllPoints()
        check:SetAllPoints(w.checkbg)
    end)
    Font(w, w.text)
end

local function SkinButtonFrame(w, button, text)
    FadeTextures(w, button)
    Fade(w, button.GetHighlightTexture and button:GetHighlightTexture())
    local fill = Box(w, "button" .. tostring(button), button, Around(button))
    Hover(w, button, fill)
    Font(w, text or button:GetFontString())
end

function skinners.Button(w)
    SkinButtonFrame(w, w.frame, w.text)
end

function skinners.EditBox(w)
    FadeTextures(w, w.editbox)
    Box(w, "box", w.editbox, Around(w.editbox, -6, 0, 0, 0))
    Font(w, w.editbox, 13)
    Font(w, w.label, 12)
    TextColor(w, w.label, T.textDim)
    if w.button then SkinButtonFrame(w, w.button) end
end

function skinners.Slider(w)
    Backdrop(w, w.slider, T.control, T.border)
    local thumb = w.slider:GetThumbTexture()
    if thumb then
        local path, width, height = thumb:GetTexture(), thumb:GetWidth(), thumb:GetHeight()
        thumb:SetTexture(unpack(T.accent))
        thumb:SetWidth(8)
        thumb:SetHeight(15)
        Record(w, function()
            thumb:SetTexture(path)
            thumb:SetWidth(width)
            thumb:SetHeight(height)
        end)
    end
    Backdrop(w, w.editbox, T.control, T.border)
    Font(w, w.label, 13)
    Font(w, w.editbox, 12)
    Font(w, w.lowtext, 11)
    Font(w, w.hightext, 11)
    TextColor(w, w.lowtext, T.textDim)
    TextColor(w, w.hightext, T.textDim)
end

function skinners.Dropdown(w)
    local name = w.dropdown:GetName()
    Fade(w, _G[name .. "Left"])
    Fade(w, _G[name .. "Middle"])
    Fade(w, _G[name .. "Right"])
    local fill = Box(w, "box", w.dropdown, function(tex, inset)
        tex:SetPoint("LEFT", w.frame, "LEFT", inset, 0)
        tex:SetPoint("RIGHT", w.frame, "RIGHT", -inset, 0)
        tex:SetPoint("TOP", w.button, "TOP", 0, -inset)
        tex:SetPoint("BOTTOM", w.button, "BOTTOM", 0, inset)
    end)
    Hover(w, w.button, fill)
    Font(w, w.text, 13)
    Font(w, w.label, 12)
    TextColor(w, w.label, T.textDim)
    if w.pullout and w.pullout.frame then
        Backdrop(w, w.pullout.frame, T.panel, T.border)
    end
end

function skinners.Heading(w)
    Fade(w, w.left)
    Fade(w, w.right)
    local left = OwnTexture(w, "left", w.frame, "BACKGROUND")
    left:SetTexture(unpack(T.border))
    left:SetHeight(1)
    left:SetPoint("LEFT", w.frame, "LEFT", 3, 0)
    left:SetPoint("RIGHT", w.label, "LEFT", -6, 0)
    local right = OwnTexture(w, "right", w.frame, "BACKGROUND")
    right:SetTexture(unpack(T.border))
    right:SetHeight(1)
    right:SetPoint("RIGHT", w.frame, "RIGHT", -3, 0)
    right:SetPoint("LEFT", w.label, "RIGHT", 6, 0)
    Font(w, w.label, 14)
    TextColor(w, w.label, T.heading)
end

function skinners.Label(w)
    Font(w, w.label)
    -- The label sized itself for the old font; SetText measures it again.
    if w.SetText then w:SetText(w.label:GetText()) end
end
skinners.InteractiveLabel = skinners.Label

function skinners.MultiLineEditBox(w)
    -- The scroll background isn't a widget field; it's what the scroll frame is anchored to.
    local _, scrollBG = w.scrollFrame:GetPoint(1)
    if scrollBG and scrollBG.SetBackdrop then Backdrop(w, scrollBG, T.panel, T.border) end
    Font(w, w.editBox, 13)
    Font(w, w.label, 12)
    TextColor(w, w.label, T.textDim)
    SkinButtonFrame(w, w.button)
    ScrollBar(w, w.scrollBar)
end

function skinners.ScrollFrame(w)
    ScrollBar(w, w.scrollbar)
end

function skinners.InlineGroup(w)
    Backdrop(w, w.content:GetParent(), { 0.08, 0.08, 0.10, 0.6 }, T.border)
    Font(w, w.titletext, 14)
    TextColor(w, w.titletext, T.heading)
end

-- Tabs are created lazily by the TabGroup, so this runs on every sweep
-- and styles the ones it hasn't seen.
local function UpdateTab(tab)
    local fill = tab.rhFill
    if not (fill and fill:IsShown()) then return end
    -- A selected tab is a disabled button, and WoW swaps in the disabled
    -- font object on every change, so the font is set again here.
    tab.text:SetFont(T.font, 13, "")
    if tab.selected then
        fill:SetTexture(unpack(T.accent))
        tab.text:SetTextColor(1, 1, 1)
    else
        fill:SetTexture(unpack(T.control))
        tab.text:SetTextColor(unpack(T.textDim))
    end
    tab.rhHoverLocked = tab.selected
end

local function SkinTab(w, tab)
    if tab.rhSkinned then return end
    tab.rhSkinned = true
    FadeTextures(w, tab)
    Fade(w, tab:GetHighlightTexture())
    local fill = Box(w, "tab" .. tab.id, tab, Around(tab, 4, -4, -4, 3))
    tab.rhFill = fill
    Hover(w, tab, fill)
    Font(w, tab.text, 13)
    local original = tab.SetSelected
    tab.SetSelected = function(frame, selected)
        original(frame, selected)
        UpdateTab(frame)
    end
    UpdateTab(tab)
    Record(w, function()
        tab.SetSelected = original
        tab.rhSkinned = nil
        tab.rhFill = nil
        tab.rhHoverLocked = nil
        -- Put the Blizzard text colors back.
        original(tab, tab.selected)
    end)
end

function skinners.TabGroup(w)
    Backdrop(w, w.border, T.panel, T.border)
    Font(w, w.titletext, 14)
end

local function SkinTabs(w)
    for _, tab in ipairs(w.tabs) do SkinTab(w, tab) end
end

---------------------------------------------------------------------------
-- Applying and undoing
---------------------------------------------------------------------------
function Skin.Unskin(w)
    local list = w.rhUndo
    if list then
        for i = #list, 1, -1 do
            list[i]()
            list[i] = nil
        end
    end
    w.rhSkinned = nil
end

-- Styles one widget, once, and arranges for it to be restored on release.
-- Returns true if it was newly styled.
function Skin.Apply(w)
    if w.rhSkinned then
        if w.type == "TabGroup" then SkinTabs(w) end
        return false
    end
    local skinner = skinners[w.type]
    if not skinner then return false end
    skinner(w)
    if w.type == "TabGroup" then SkinTabs(w) end
    w.rhSkinned = true

    local originalRelease = w.OnRelease
    w.OnRelease = function(self, ...)
        Skin.Unskin(self)
        self.OnRelease = originalRelease
        if originalRelease then return originalRelease(self, ...) end
    end
    return true
end

-- Styles a widget and everything inside it. Returns how many widgets were
-- newly styled.
function Skin.ApplyTree(w)
    local count = Skin.Apply(w) and 1 or 0
    if w.children then
        for _, child in ipairs(w.children) do count = count + Skin.ApplyTree(child) end
    end
    return count
end

-- Re-runs the layout of every container, innermost first: fonts changed
-- after AceConfigDialog laid the controls out.
function Skin.Relayout(w)
    if w.children then
        for _, child in ipairs(w.children) do Skin.Relayout(child) end
        if w.DoLayout then w:DoLayout() end
    end
end
