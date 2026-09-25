local ADDON_NAME, ns = ...
local RH = ns.RH

-- A minimap button, without a library: left click opens the options, right
-- click toggles cooldowns, drag moves it around the minimap. Its angle is
-- stored in the profile.
local MinimapButton = RH:NewModule("MinimapButton", "AceEvent-3.0")
ns.MinimapButton = MinimapButton

local GetCursorPosition = GetCursorPosition
local atan2, cos, sin, rad, deg = math.atan2, math.cos, math.sin, math.rad, math.deg

local RADIUS = 80 -- from the minimap's center to the button's
local ICON = "Interface\\Icons\\Spell_Deathknight_ClassIcon"

function MinimapButton:Place()
    local angle = rad(RH.db.profile.minimap.angle)
    self.button:ClearAllPoints()
    self.button:SetPoint("CENTER", Minimap, "CENTER", cos(angle) * RADIUS, sin(angle) * RADIUS)
end

-- While dragging: the angle from the minimap's center to the cursor.
local function FollowCursor()
    local x, y = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = Minimap:GetCenter()
    RH.db.profile.minimap.angle = deg(atan2(y / scale - cy, x / scale - cx)) % 360
    MinimapButton:Place()
end

function MinimapButton:ShowTooltip()
    local toggles = RH.db.profile.toggles
    GameTooltip:SetOwner(self.button, "ANCHOR_LEFT")
    GameTooltip:AddLine("RotationHelper " .. RH.version)
    GameTooltip:AddLine(("Cooldowns: %s   AoE mode: %s"):format(toggles.cooldowns and "on" or "off", toggles.aoeMode),
        1, 1, 1)
    GameTooltip:AddLine("Left-click: options", 0.6, 0.6, 0.63)
    GameTooltip:AddLine("Right-click: toggle cooldowns", 0.6, 0.6, 0.63)
    GameTooltip:AddLine("Drag: move", 0.6, 0.6, 0.63)
    GameTooltip:Show()
end

function MinimapButton:Create()
    local b = CreateFrame("Button", "RotationHelperMinimapButton", Minimap)
    b:SetWidth(31)
    b:SetHeight(31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = b:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetWidth(20)
    background:SetHeight(20)
    background:SetPoint("CENTER")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetPoint("CENTER")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetWidth(53)
    border:SetHeight(53)
    border:SetPoint("TOPLEFT")

    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            RH:ToggleCooldowns()
            MinimapButton:ShowTooltip()
        else
            ns.Options:Open()
        end
    end)
    b:SetScript("OnDragStart", function(frame) frame:SetScript("OnUpdate", FollowCursor) end)
    b:SetScript("OnDragStop", function(frame) frame:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function() MinimapButton:ShowTooltip() end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.button = b
end

function MinimapButton:Update()
    if not self.button then self:Create() end
    if RH.db.profile.minimap.show then
        self:Place()
        self.button:Show()
    else
        self.button:Hide()
    end
end

function MinimapButton:OnEnable()
    if not (RH.classSupported and Minimap) then return end
    self:RegisterMessage("ROTATIONHELPER_CONFIG_CHANGED", function() MinimapButton:Update() end)
    self:Update()
end
