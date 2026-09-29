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
--   - ElvUI: its keys are override bindings, which the binding list doesn't
--     show. The key stays on a command (ACTIONBUTTON1, ELVUIBAR2BUTTON1,
--     MULTIACTIONBAR3BUTTON1, ...) whose Blizzard button ElvUI hides, so its
--     buttons (ElvUI_Bar1Button1, ...) are read directly: each names that
--     command as its keyBoundTarget.
-- Buttons that exist but are hidden (e.g. Blizzard bars replaced by a bar
-- addon) are skipped. The map is rebuilt lazily after any bar or binding change.
local Keybinds = RH:NewModule("Keybinds", "AceEvent-3.0")
ns.Keybinds = Keybinds

local GetActionInfo, GetSpellInfo = GetActionInfo, GetSpellInfo
local GetSpellName, GetMacroSpell = GetSpellName, GetMacroSpell
local GetNumBindings, GetBinding, GetBindingKey = GetNumBindings, GetBinding, GetBindingKey
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
    -- LibActionButton (ElvUI): the current state's type and action. It
    -- sets button.action to 0 on every button, so that isn't the slot.
    local stateType = button._state_type
    if stateType == "action" then
        local slot = tonumber(button._state_action)
        return slot and slot > 0 and SlotSpellName(slot) or nil
    elseif stateType == "spell" then
        local spell = button._state_action
        if type(spell) == "number" then return (GetSpellInfo(spell)) end
        return spell
    elseif stateType then
        return nil -- empty, item, custom (ElvUI's vehicle exit button)
    end
    local slot = tonumber(button.action)
    if not slot or slot < 1 then slot = tonumber(Attribute(button, "action")) end
    return slot and slot > 0 and SlotSpellName(slot) or nil
end

-- ElvUI's bars and the binding command of each (ElvUI-WotLK's defaults,
-- used when a button doesn't say): bar N button I is bound through PREFIX .. I.
local ELVUI_BARS = 10
local ELVUI_BUTTONS = 12
local ELVUI_COMMANDS = {
    "ACTIONBUTTON", "MULTIACTIONBAR2BUTTON", "MULTIACTIONBAR1BUTTON", "MULTIACTIONBAR4BUTTON",
    "MULTIACTIONBAR3BUTTON", "ELVUIBAR6BUTTON", "ELVUIBAR7BUTTON", "ELVUIBAR8BUTTON",
    "ELVUIBAR9BUTTON", "ELVUIBAR10BUTTON",
}

-- The key text a button shows itself (ElvUI already abbreviates it), or
-- nil. The range dot some bars show without a key doesn't count.
local function HotKeyText(button)
    local hotkey = button.HotKey or _G[button:GetName() .. "HotKey"]
    local text = hotkey and hotkey.GetText and hotkey:GetText()
    if not text or text == "" or text == RANGE_INDICATOR or not text:find("%w") then return nil end
    return text
end

-- The key of an ElvUI button, or nil; and the binding command it's bound
-- through (for /rh keys). The binding first; the button's own key text
-- when the binding can't be found.
local function ElvUIKey(button, bar, index)
    local target = button.keyBoundTarget or (button.config and button.config.keyBoundTarget)
        or (ELVUI_COMMANDS[bar] and ELVUI_COMMANDS[bar] .. index)
    local key = target and GetBindingKey(target)
    if not key then key = GetBindingKey("CLICK " .. button:GetName() .. ":LeftButton") end
    if key then return Keybinds.FormatKey(key), target end
    local shown = HotKeyText(button)
    return shown and shown:upper(), target
end

-- Reads ElvUI's bars. `report` (a table, for /rh keys) collects a line per
-- button with a spell.
local function AddElvUI(report)
    if not (_G.ElvUI or _G.ElvUI_Bar1Button1) then return end -- ElvUI isn't loaded
    for bar = 1, ELVUI_BARS do
        for i = 1, ELVUI_BUTTONS do
            local button = _G["ElvUI_Bar" .. bar .. "Button" .. i]
            if button then
                local visible = not (button.IsVisible and not button:IsVisible())
                local key, target = ElvUIKey(button, bar, i)
                local name = ButtonSpellName(button)
                if name and key and visible and not keyBySpell[name] then keyBySpell[name] = key end
                if report and name then
                    report[#report + 1] = ("  Bar %d button %d: %s, bound through %s: %s%s"):format(bar, i, name,
                        tostring(target), key or "no key", visible and "" or " (hidden)")
                end
            end
        end
    end
end

-- The spell a binding command casts, or nil (also for a hidden button).
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
    AddElvUI(self.report)
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

-- /rh keys: every spell with a key, sorted, and which bar addon was seen.
function RH:PrintKeybinds()
    Keybinds.report = {}
    Keybinds:Rebuild()
    local report = Keybinds.report
    Keybinds.report = nil
    local names = {}
    for name in pairs(keyBySpell) do names[#names + 1] = name end
    table.sort(names)
    self:Print(("Keybinds found for %d spells:"):format(#names))
    for _, name in ipairs(names) do print("  " .. name .. ": " .. keyBySpell[name]) end
    if #names == 0 then print("  none: is the spell on a bar with a key bound to it?") end
    if #report > 0 then
        print("ElvUI buttons with a spell:")
        for _, line in ipairs(report) do print(line) end
    end
end
