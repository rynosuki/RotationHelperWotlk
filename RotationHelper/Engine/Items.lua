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
            known[key] = useSpell ~= nil
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
    self:Update()
end
