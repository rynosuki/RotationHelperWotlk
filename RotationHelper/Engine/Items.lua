local ADDON_NAME, ns = ...
local RH = ns.RH

-- Item abilities (Classes/Shared.lua): trinkets with a use effect in their
-- slot, and the best potion in your bags. Updates their name, icon and
-- item ID, and whether they're available (Spec.known), when your gear or
-- bags change.
local Items = RH:NewModule("Items", "AceEvent-3.0")
ns.Items = Items

local GetInventoryItemID, GetInventoryItemTexture = GetInventoryItemID, GetInventoryItemTexture
local GetItemSpell, GetItemInfo, GetItemCount, GetItemIcon = GetItemSpell, GetItemInfo, GetItemCount, GetItemIcon

function Items.IsItemAbility(ability)
    return ability.itemSlot ~= nil or ability.potionItems ~= nil
end

---------------------------------------------------------------------------
-- Which trinkets to suggest. Only offensive use effects are suggested by
-- default: a tank trinket's armor or health on-use doesn't belong in a
-- damage rotation. The effect is read from the "Use:" line of the item's
-- tooltip (enUS wording, as on Whitemane).
---------------------------------------------------------------------------
local OFFENSIVE_WORDS = {
    "attack power", "haste rating", "critical strike rating", "armor penetration rating", "hit rating",
    "expertise rating", "spell power", "strength", "agility", "damage done", "melee haste", "attack speed",
}

-- "offensive", "other", or nil when the tooltip had no "Use:" line.
function Items.Classify(useText)
    if not useText then return nil end
    local text = useText:lower()
    for _, word in ipairs(OFFENSIVE_WORDS) do
        if text:find(word, 1, true) then return "offensive" end
    end
    return "other"
end

local SCANNER_NAME = "RotationHelperScanTooltip"
local scanner

-- The "Use: ..." line of the item in an inventory slot, or nil.
function Items.UseText(slot)
    if not scanner then
        scanner = CreateFrame("GameTooltip", SCANNER_NAME, nil, "GameTooltipTemplate")
    end
    scanner:SetOwner(UIParent, "ANCHOR_NONE")
    scanner:ClearLines()
    scanner:SetInventoryItem("player", slot)
    for i = 2, scanner:NumLines() do
        local line = _G[SCANNER_NAME .. "TextLeft" .. i]
        local text = line and line:GetText()
        if text and text:find("^Use:") then return text end
    end
    return nil
end

-- Whether a trinket with this kind of use effect should be suggested.
local function WantTrinket(kind)
    local mode = RH.db.profile.items.trinkets
    if mode == "all" then return true end
    if mode == "none" then return false end
    return kind == "offensive"
end

function Items:Update()
    local classData = RH.classData
    if not classData then return end
    local known = ns.Spec.known
    for key, ability in pairs(classData.abilities) do
        if ability.itemSlot then
            local itemID = GetInventoryItemID("player", ability.itemSlot)
            local useSpell = itemID and GetItemSpell(itemID)
            ability.itemID = useSpell and itemID or nil
            ability.name = useSpell and (GetItemInfo(itemID)) or nil
            ability.icon = useSpell and GetInventoryItemTexture("player", ability.itemSlot) or nil
            ability.useText = useSpell and Items.UseText(ability.itemSlot) or nil
            ability.useKind = Items.Classify(ability.useText)
            known[key] = useSpell ~= nil and WantTrinket(ability.useKind)
        elseif ability.potionItems then
            local found
            for _, id in ipairs(ability.potionItems) do
                if GetItemCount(id) > 0 then
                    found = id
                    break
                end
            end
            ability.itemID = found
            ability.name = found and (GetItemInfo(found)) or nil
            ability.icon = found and GetItemIcon(found) or nil
            known[key] = found ~= nil
        end
    end
    RH:Invalidate()
end

function Items:OnEnable()
    if not RH.classSupported then return end
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "Update")
    self:RegisterEvent("BAG_UPDATE", "Update")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "Update")
    -- Tooltips can be incomplete right after login; look again when a fight
    -- starts, and when the trinket setting changes.
    self:RegisterMessage("ROTATIONHELPER_COMBAT_CHANGED", "Update")
    self:RegisterMessage("ROTATIONHELPER_CONFIG_CHANGED", "Update")
    self:Update()
end
