local ADDON_NAME, ns = ...
local RH = ns.RH

-- Text helpers for the rotation editor, free of frames so they're easy to
-- test:
--   Escape / Strip      WoW edit boxes read '|' as an escape code: '|' is
--                       stored as '||'. Strip also removes color codes.
--   Colorize            syntax colors, as color codes in the edit box text
--   RawToPlain /        cursor positions between the edit box's raw text
--   PlainToRaw          (with codes) and the plain rotation text
--   Export / Import     "RH1:<spec>:<text>" on one line: no '|', no newlines
--   Chunks / Assemble   splitting that string for addon messages
--   Names               every name the rotation language knows, for the picker
local APLText = {}
ns.APLText = APLText

local format, byte, sub, find, gsub = string.format, string.byte, string.sub, string.find, string.gsub
local concat, sort = table.concat, table.sort

local PIPE = byte("|")

---------------------------------------------------------------------------
-- Escaping
---------------------------------------------------------------------------
function APLText.Escape(plain)
    return (gsub(plain, "|", "||"))
end

-- Raw edit box text -> plain rotation text: removes color codes (|cAARRGGBB
-- and |r) and turns '||' back into '|'. Anything else after a single '|' is
-- kept as it is.
function APLText.Strip(raw)
    local out, i, n = {}, 1, #raw
    while i <= n do
        local c = byte(raw, i)
        if c == PIPE then
            local nextChar = sub(raw, i + 1, i + 1)
            if nextChar == "|" then
                out[#out + 1] = "|"
                i = i + 2
            elseif nextChar == "c" and find(sub(raw, i + 2, i + 9), "^%x%x%x%x%x%x%x%x$") then
                i = i + 10
            elseif nextChar == "r" then
                i = i + 2
            else
                out[#out + 1] = "|"
                i = i + 1
            end
        else
            -- Copy a run of ordinary characters at once.
            local s, e = find(raw, "^[^|]+", i)
            out[#out + 1] = sub(raw, s, e)
            i = e + 1
        end
    end
    return concat(out)
end

---------------------------------------------------------------------------
-- Cursor positions (WoW edit box positions count raw characters, codes
-- included; 0 = before the first character)
---------------------------------------------------------------------------
-- Width in raw characters of the token at raw index i (1-based), and how
-- many plain characters it stands for.
local function RawToken(raw, i)
    if byte(raw, i) == PIPE then
        local nextChar = sub(raw, i + 1, i + 1)
        if nextChar == "|" then return 2, 1 end
        if nextChar == "c" and find(sub(raw, i + 2, i + 9), "^%x%x%x%x%x%x%x%x$") then return 10, 0 end
        if nextChar == "r" then return 2, 0 end
    end
    return 1, 1
end

function APLText.RawToPlain(raw, rawPos)
    local i, plain = 1, 0
    while i <= rawPos and i <= #raw do
        local width, count = RawToken(raw, i)
        if i + width - 1 > rawPos then break end
        plain = plain + count
        i = i + width
    end
    return plain
end

-- The raw position just after `plainPos` plain characters (after any codes
-- that follow, so typing continues in the right color).
function APLText.PlainToRaw(raw, plainPos)
    local i, plain = 1, 0
    while i <= #raw do
        local width, count = RawToken(raw, i)
        if count > 0 and plain + count > plainPos then break end
        plain = plain + count
        i = i + width
    end
    return i - 1
end

---------------------------------------------------------------------------
-- Syntax colors
---------------------------------------------------------------------------
APLText.COLORS = {
    comment = "ff808080",
    header = "ff6fa8dc",  -- actions.aoe+=/
    ability = "ffffd100", -- obliterate
    option = "ff9fc5e8",  -- if= name= value=
    name = "ff7fd67f",    -- buff.killing_machine.up
    number = "ffffa050",
    unknown = "ffff6060", -- an identifier the language doesn't know
}
local C = APLText.COLORS

local function Colored(color, text)
    return "|c" .. color .. text .. "|r"
end

-- Colors one line (plain text in, escaped + colored out).
local function ColorLine(line, isAbility, isName)
    if find(line, "^%s*#") then return Colored(C.comment, APLText.Escape(line)) end
    local out = {}
    local i, n = 1, #line
    local _, headerEnd = find(line, "^%s*actions[%w_%.]*%+?=/?")
    if headerEnd then
        out[1] = Colored(C.header, sub(line, 1, headerEnd))
        i = headerEnd + 1
    end
    while i <= n do
        local s, e = find(line, "^[%a_][%w_%.]*", i)
        if s then
            local word = sub(line, s, e)
            local color
            if sub(line, e + 1, e + 1) == "=" and not find(sub(line, e + 1, e + 2), "^==") then
                color = C.option
            elseif isAbility(word) then
                color = C.ability
            elseif find(word, "%.") or isName(word) then
                color = isName(word) and C.name or C.unknown
            end
            out[#out + 1] = color and Colored(color, word) or word
            i = e + 1
        else
            s, e = find(line, "^%d*%.?%d+", i)
            if s then
                out[#out + 1] = Colored(C.number, sub(line, s, e))
                i = e + 1
            else
                local ch = sub(line, i, i)
                out[#out + 1] = ch == "|" and "||" or ch
                i = i + 1
            end
        end
    end
    return concat(out)
end

-- Plain rotation text -> escaped edit box text with color codes.
-- isAbility(word) and isName(word) decide how identifiers are colored.
function APLText.Colorize(plain, isAbility, isName)
    local lines = {}
    for line in (plain .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = ColorLine(line, isAbility, isName)
    end
    return concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Import / export
---------------------------------------------------------------------------
APLText.EXPORT_PREFIX = "RH1:"

-- One line: '\' -> '\\', newline -> '\n', '|' -> '\p'.
function APLText.Export(specKey, plain)
    local body = gsub(gsub(gsub(gsub(plain, "\r", ""), "\\", "\\\\"), "\n", "\\n"), "|", "\\p")
    return APLText.EXPORT_PREFIX .. specKey .. ":" .. body
end

-- Accepts an export string or plain rotation text. Returns specKey (nil for
-- plain text) and the rotation text; or nil, nil, message.
function APLText.Import(str)
    str = gsub(gsub(str, "^%s+", ""), "%s+$", "")
    if sub(str, 1, #APLText.EXPORT_PREFIX) ~= APLText.EXPORT_PREFIX then
        if find(str, "actions") then return nil, APLText.Strip(str) end
        return nil, nil, "not a rotation or an RH1: string"
    end
    local specKey, body = str:match("^RH1:([%w_]+):(.*)$")
    if not specKey then return nil, nil, "damaged RH1: string" end
    local text = gsub(body, "\\(.)", function(c)
        if c == "n" then return "\n" elseif c == "p" then return "|" end
        return c
    end)
    return specKey, text
end

-- Splits `str` into pieces of at most `size` characters.
function APLText.Chunks(str, size)
    local chunks = {}
    for i = 1, #str, size do chunks[#chunks + 1] = sub(str, i, i + size - 1) end
    if #chunks == 0 then chunks[1] = "" end
    return chunks
end

---------------------------------------------------------------------------
-- Names for the picker
---------------------------------------------------------------------------
local SIMPLE_NAMES = {
    "runic_power", "runic_power.deficit", "runic_power.max", "runic_power.pct",
    "gcd", "gcd.remains", "time", "active_enemies", "moving", "pet.alive",
    "target.health.pct", "target.time_to_die", "toggle.cooldowns",
}
local ACTION_TEMPLATES = {
    "call_action_list,name=", "run_action_list,name=", "variable,name=,value=", "wait,sec=",
    "if=", "line_cd=",
}

-- Every name the language knows for this class and your current talents
-- and glyphs, sorted. Each entry: { text = "buff.killing_machine.up", kind = "name" }.
function APLText.Names(classData)
    local names, seen = {}, {}
    local function add(text, kind)
        if not seen[text] then
            seen[text] = true
            names[#names + 1] = { text = text, kind = kind }
        end
    end
    for key in pairs(classData.abilities) do
        add(key, "ability")
        if classData.abilities[key].cooldown then
            add("cooldown." .. key .. ".ready", "name")
            add("cooldown." .. key .. ".remains", "name")
        end
    end
    for key, def in pairs(classData.auras) do
        local prefix = def.debuff and "dot." or "buff."
        for _, field in ipairs({ "up", "down", "remains", "stack" }) do add(prefix .. key .. "." .. field, "name") end
    end
    if classData.usesRunes then
        for _, rune in ipairs({ "blood", "unholy", "frost", "death", "total" }) do
            add("runes." .. rune, "name")
            add("runes." .. rune .. ".time_to_1", "name")
            add("runes." .. rune .. ".time_to_2", "name")
        end
    end
    for _, name in ipairs(SIMPLE_NAMES) do add(name, "name") end
    for key in pairs(ns.Spec.talents) do
        add("talent." .. key .. ".enabled", "name")
        add("talent." .. key .. ".rank", "name")
    end
    for key in pairs(ns.Spec.glyphs) do add("glyph." .. key .. ".enabled", "name") end
    for _, text in ipairs(ACTION_TEMPLATES) do add(text, "template") end
    sort(names, function(a, b) return a.text < b.text end)
    return names
end

-- Names containing `search` (case-insensitive, plain text).
function APLText.Filter(names, search, out)
    out = out or {}
    for i = #out, 1, -1 do out[i] = nil end
    search = (search or ""):lower()
    for _, entry in ipairs(names) do
        if search == "" or find(entry.text, search, 1, true) then out[#out + 1] = entry end
    end
    return out
end
