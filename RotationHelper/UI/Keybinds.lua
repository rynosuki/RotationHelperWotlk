local ADDON_NAME, ns = ...
local RH = ns.RH

-- Maps spell names to the key that casts them.
--
-- Walks every key binding instead of knowing each bar addon:
--   - "CLICK <button>:LeftButton" bindings (Bartender4, Dominos, DragonUI's
--     extra bars, ElvUI, ...): the button's action slot, or its spell/macro
--     attribute, says what it casts.
--   - Blizzard bar commands (ACTIONBUTTON3, MULTIACTIONBAR1BUTTON2, ...):
--     mapped to the Blizzard button and its current action.
-- Buttons that exist but are hidden (e.g. Blizzard bars replaced by a bar
-- addon) are skipped. The map is rebuilt lazily after any bar or binding change.
local Keybinds = RH:NewModule("Keybinds", "AceEvent-3.0")
ns.Keybinds = Keybinds

local GetActionInfo, GetSpellInfo = GetActionInfo, GetSpellInfo
local GetSpellName, GetMacroSpell = GetSpellName, GetMacroSpell
local GetNumBindings, GetBinding = GetNumBindings, GetBinding
local wipe, tonumber, type = wipe, tonumber, type

-- Blizzard binding command prefix -> button name prefix and first action slot.
local BLIZZARD_BARS = {
    ACTIONBUTTON = { button = "ActionButton", firstSlot = 1 },
    MULTIACTIONBAR3BUTTON = { button = "MultiBarRightButton", firstSlot = 25 },
    MULTIACTIONBAR4BUTTON = { button = "MultiBarLeftButton", firstSlot = 37 },
    MULTIACTIONBAR2BUTTON = { button = "MultiBarBottomRightButton", firstSlot = 49 },
    MULTIACTIONBAR1BUTTON = { button = "MultiBarBottomLeftButton", firstSlot = 61 },
}

-- Longest patterns first so e.g. MOUSEWHEELUP isn't caught by BUTTON.
local KEY_ABBREVIATIONS = {
    { "SHIFT%-", "S" },
    { "CTRL%-", "C" },
    { "ALT%-", "A" },
    { "MOUSEWHEELUP", "MwU" },
    { "MOUSEWHEELDOWN", "MwD" },
    { "MIDDLEMOUSE", "M3" },
    { "BUTTON", "M" },
    { "NUMPAD", "N" },
    { "PLUS", "+" },
    { "MINUS", "-" },
    { "MULTIPLY", "*" },
    { "DIVIDE", "/" },
    { "DECIMAL", "." },
    { "SPACE", "Spc" },
}

local keyBySpell = {}
local dirty = true

function Keybinds.FormatKey(key)
    if not key then return nil end
    key = key:upper()
    for _, abbr in ipairs(KEY_ABBREVIATIONS) do
        key = key:gsub(abbr[1], abbr[2])
    end
    return key
end

-- 3.3.5 GetActionInfo returns ("spell", spellbookIndex, bookType, spellID);
-- fall back to the spellbook lookup if the spell ID is missing.
local function SlotSpellName(slot)
    local actionType, id, subType, spellId = GetActionInfo(slot)
    if actionType == "spell" then
        if spellId then return (GetSpellInfo(spellId)) end
        return GetSpellName and (GetSpellName(id, subType or "spell"))
    elseif actionType == "item" then
        return (GetItemInfo(id)) -- trinkets and potions, looked up by item name
    elseif actionType == "macro" and GetMacroSpell then
        return (GetMacroSpell(id))
    end
end

local function Attribute(button, name)
    return button.GetAttribute and button:GetAttribute(name)
end

-- What a button casts: an action slot (most bar addons), or a spell or
-- macro set directly as a secure attribute.
local function ButtonSpellName(button)
    local buttonType = Attribute(button, "type")
    if buttonType == "spell" then
        local spell = Attribute(button, "spell")
        if type(spell) == "number" then return (GetSpellInfo(spell)) end
        return spell
    elseif buttonType == "macro" and GetMacroSpell then
        local macro = Attribute(button, "macro")
        return macro and (GetMacroSpell(macro))
    end
    local slot = tonumber(button.action or button._state_action or Attribute(button, "action"))
    return slot and SlotSpellName(slot)
end

-- The spell a binding command casts, or nil. A nil second return means the
-- binding points at a hidden button and should be ignored.
local function CommandSpellName(command)
    local buttonName = command:match("^CLICK (.+):[%w]+$")
    if buttonName then
        local button = _G[buttonName]
        if not button or (button.IsVisible and not button:IsVisible()) then return nil end
        return ButtonSpellName(button)
    end

    local prefix, index = command:match("^(ACTIONBUTTON)(%d+)$")
    if not prefix then prefix, index = command:match("^(MULTIACTIONBAR%dBUTTON)(%d+)$") end
    local bar = prefix and BLIZZARD_BARS[prefix]
    if not bar then return nil end
    index = tonumber(index)
    local button = _G[bar.button .. index]
    if button then
        if button.IsVisible and not button:IsVisible() then return nil end
        if button.action then return SlotSpellName(button.action) end
    end
    return SlotSpellName(bar.firstSlot + index - 1)
end

function Keybinds:Rebuild()
    wipe(keyBySpell)
    for i = 1, GetNumBindings() do
        local command, key = GetBinding(i)
        if command and key then
            local name = CommandSpellName(command)
            if name and not keyBySpell[name] then
                keyBySpell[name] = Keybinds.FormatKey(key)
            end
        end
    end
    dirty = false
end

function Keybinds:Get(spellName)
    if not spellName then return nil end
    if dirty then self:Rebuild() end
    return keyBySpell[spellName]
end

function Keybinds:MarkDirty()
    dirty = true
    RH:Invalidate()
end

function Keybinds:OnEnable()
    self:RegisterEvent("ACTIONBAR_SLOT_CHANGED", "MarkDirty")
    self:RegisterEvent("UPDATE_BINDINGS", "MarkDirty")
    self:RegisterEvent("ACTIONBAR_PAGE_CHANGED", "MarkDirty")
    self:RegisterEvent("UPDATE_BONUS_ACTIONBAR", "MarkDirty")
    self:RegisterEvent("UPDATE_MACROS", "MarkDirty")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "MarkDirty")
end
