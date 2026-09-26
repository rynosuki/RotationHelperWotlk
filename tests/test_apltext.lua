local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local s = newAddon()
local X = s.ns.APLText

local ABILITIES = { obliterate = true, frost_strike = true, icy_touch = true, howling_blast = true }
local function isAbility(w) return ABILITIES[w] or false end
local function isName(w) return w:find("^buff%.") or w:find("^dot%.") or w == "runic_power"
    or w:find("^runic_power%.") or w:find("^runes%.") or false end
local function Colorize(text) return X.Colorize(text, isAbility, isName) end

local SAMPLE = table.concat({
    "# Frost | test",
    "actions=obliterate,if=runes.frost=2|runes.unholy=2",
    "actions+=/frost_strike,if=buff.killing_machine.up||runic_power.deficit<25",
    "",
    "actions.aoe=howling_blast/icy_touch,if=!dot.frost_fever.up&1.5>0.5",
    "actions+=/mystery_spell,if=foo.bar>3",
}, "\n")

---------------------------------------------------------------------------
test("escape and strip round-trip, including '|'", function()
    eq(X.Escape("a|b||c"), "a||b||||c", "escape")
    eq(X.Strip("a||b||||c"), "a|b||c", "strip")
    eq(X.Strip("|cff00ff00green|r and |cFFabcdefX|r"), "green and X", "color codes removed")
    eq(X.Strip("odd | pipe"), "odd | pipe", "a lone '|' is kept")
    eq(X.Strip("|r|r"), "", "stray resets removed")
end)

test("colorize: stripping always gives back the exact text", function()
    eq(X.Strip(Colorize(SAMPLE)), SAMPLE, "round trip")
    for _, text in ipairs({ "", "\n\n", "|", "||", "actions=", "a|b|c", "x.y.z=1", "1.", ".5", "#|#" }) do
        eq(X.Strip(Colorize(text)), text, "round trip of " .. text)
    end
end)

test("colorize: what gets which color", function()
    local out = Colorize(SAMPLE)
    local C = X.COLORS
    truthy(out:find("|c" .. C.comment .. "# Frost || test|r", 1, true), "comment, '|' escaped")
    truthy(out:find("|c" .. C.header .. "actions=|r", 1, true), "header")
    truthy(out:find("|c" .. C.ability .. "obliterate|r", 1, true), "ability")
    truthy(out:find("|c" .. C.option .. "if|r=", 1, true), "option key")
    truthy(out:find("|c" .. C.name .. "buff.killing_machine.up|r", 1, true), "known name")
    truthy(out:find("|c" .. C.number .. "25|r", 1, true), "number")
    truthy(out:find("|c" .. C.unknown .. "foo.bar|r", 1, true), "unknown dotted name")
    truthy(out:find("||||", 1, true), "'||' in the text stays '||' when shown")
    falsy(out:find("|c" .. C.ability .. "mystery_spell", 1, true), "unknown action isn't gold")
end)

test("cursor positions map between raw and plain text", function()
    local plain = "actions=obliterate,if=1"
    local raw = Colorize(plain)
    for p = 0, #plain do
        local r = X.PlainToRaw(raw, p)
        eq(X.RawToPlain(raw, r), p, "plain " .. p .. " -> raw " .. r .. " -> back")
    end
    -- The raw position after "obliterate" is past its color codes.
    local r = X.PlainToRaw(raw, #"actions=obliterate")
    eq(X.Strip(raw:sub(1, r)), "actions=obliterate", "prefix up to the cursor")
end)

test("cursor positions with escaped pipes", function()
    local plain = "a|b"
    local raw = X.Escape(plain) -- "a||b"
    eq(X.RawToPlain(raw, 3), 2, "after the '||' is after one plain character")
    eq(X.PlainToRaw(raw, 2), 3, "and back")
    eq(X.RawToPlain(raw, 2), 1, "inside '||' counts as before it")
end)

---------------------------------------------------------------------------
test("export and import round-trip", function()
    local exported = X.Export("frost", SAMPLE)
    falsy(exported:find("\n"), "one line")
    falsy(exported:find("|", 1, true), "no pipes")
    truthy(exported:find("^RH1:frost:"), "prefix and spec")
    local spec, text = X.Import(exported)
    eq(spec, "frost", "spec")
    eq(text, SAMPLE, "text")
    local _, back = X.Import(X.Export("unholy", "a\\nb\\c"))
    eq(back, "a\\nb\\c", "backslashes survive")
end)

test("import accepts plain rotations and rejects junk", function()
    local spec, text = X.Import("  actions=obliterate\n")
    eq(spec, nil, "no spec")
    eq(text, "actions=obliterate", "plain text")
    local _, _, err = X.Import("hello")
    eq(err, "not a rotation or an RH1: string", "junk")
    _, _, err = X.Import("RH1:bad")
    eq(err, "damaged RH1: string", "damaged")
end)

test("chunks", function()
    local chunks = X.Chunks(string.rep("x", 600), 250)
    eq(#chunks, 3, "three")
    eq(#chunks[3], 100, "last one shorter")
    eq(table.concat(chunks), string.rep("x", 600), "back together")
end)

---------------------------------------------------------------------------
test("names for the picker", function()
    local s2 = newAddon()
    s2.glyphs[1] = 58647
    s2:FireEvent("GLYPH_ADDED")
    local names = s2.ns.APLText.Names(s2.env.RotationHelper.classData)
    local set = {}
    for _, n in ipairs(names) do set[n.text] = n.kind end
    eq(set.obliterate, "ability", "abilities")
    eq(set["cooldown.howling_blast.ready"], "name", "cooldowns")
    eq(set["buff.killing_machine.up"], "name", "buffs")
    eq(set["dot.frost_fever.remains"], "name", "debuffs as dot.")
    eq(set["runes.frost.time_to_2"], "name", "runes")
    eq(set["talent.blood_of_the_north.rank"], "name", "your talents")
    eq(set["glyph.frost_strike.enabled"], "name", "your glyphs")
    eq(set["call_action_list,name="], "template", "action templates")
    local filtered = s2.ns.APLText.Filter(names, "KILLING")
    truthy(#filtered >= 4, "search is case-insensitive")
    for _, n in ipairs(filtered) do truthy(n.text:find("killing"), n.text) end
end)
