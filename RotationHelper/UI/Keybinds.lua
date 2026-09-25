local ADDON_NAME, ns = ...
local RH = ns.RH

-- Maps spell names to the key that casts them, by scanning action bars.
-- Supports the default UI, Bartender4 and Dominos. The map is rebuilt
-- lazily on the next lookup after any bar or binding change.
local Keybinds = RH:NewModule("Keybinds", "AceEvent-3.0")
ns.Keybinds = Keybinds

local GetActionInfo, GetBindingKey, GetSpellInfo = GetActionInfo, GetBindingKey, GetSpellInfo
local GetSpellName, GetMacroSpell = GetSpellName, GetMacroSpell
local wipe = wipe

local MAX_ACTION_SLOTS = 120

-- Default UI: action slot ranges and the binding command for each bar.
local BLIZZARD_BARS = {
    { first = 1, last = 12, command = "ACTIONBUTTON" },
    { first = 25, last = 36, command = "MULTIACTIONBAR3BUTTON" }, -- right bar
    { first = 37, last = 48, command = "MULTIACTIONBAR4BUTTON" }, -- right bar 2
    { first = 49, last = 60, command = "MULTIACTIONBAR2BUTTON" }, -- bottom right
    { first = 61, last = 72, command = "MULTIACTIONBAR1BUTTON" }, -- bottom left
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

local function BlizzardCommand(slot)
    for _, bar in ipairs(BLIZZARD_BARS) do
        if slot >= bar.first and slot <= bar.last then
            return bar.command .. (slot - bar.first + 1)
        end
    end
end

local function SlotKey(slot)
    if _G.Bartender4 then
        local key = GetBindingKey("CLICK BT4Button" .. slot .. ":LeftButton")
        if key then return key end
    end
    if _G.Dominos then
        local key = GetBindingKey("CLICK DominosActionButton" .. slot .. ":LeftButton")
        if key then return key end
    end
    local command = BlizzardCommand(slot)
    return command and GetBindingKey(command)
end

-- 3.3.5 GetActionInfo returns ("spell", spellbookIndex, bookType, spellID);
-- fall back to the spellbook lookup if the spell ID is missing.
local function SlotSpellName(slot)
    local actionType, id, subType, spellId = GetActionInfo(slot)
    if actionType == "spell" then
        if spellId then return (GetSpellInfo(spellId)) end
        return GetSpellName and (GetSpellName(id, subType or "spell"))
    elseif actionType == "macro" and GetMacroSpell then
        return (GetMacroSpell(id))
    end
end

function Keybinds:Rebuild()
    wipe(keyBySpell)
    for slot = 1, MAX_ACTION_SLOTS do
        local name = SlotSpellName(slot)
        if name and not keyBySpell[name] then
            local key = SlotKey(slot)
            if key then keyBySpell[name] = Keybinds.FormatKey(key) end
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
    self:RegisterEvent("UPDATE_MACROS", "MarkDirty")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "MarkDirty")
end
