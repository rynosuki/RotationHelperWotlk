-- /rh report: a bug report to copy into a GitHub issue.
local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local function Fight()
    local s, RH = newAddon()
    s:Learn("Icy Touch", "Plague Strike", "Obliterate", "Frost Strike", "Howling Blast", "Blood Strike",
        "Horn of Winter", "Death Coil")
    s.hasTarget = true
    s:FireEvent("PLAYER_REGEN_DISABLED")
    s:Tick(0.1)
    return s, RH
end

test("the report has what's needed to look into a problem", function()
    local s, RH = Fight()
    local text = s.ns.Report.Build()
    for _, want in ipairs({ "Version " .. RH.version, "DEATHKNIGHT", "Spec: frost; rotation: Frost (default)",
        "Settings: cooldowns", "--- What the addon sees ---", "Talents:", "Recommendation:",
        "--- Recent errors ---", "--- Last fight review ---" }) do
        truthy(text:find(want, 1, true), "contains " .. want)
    end
    falsy(text:find("|c", 1, true), "no color codes")
    falsy(text:find("--- Custom rotation ---", 1, true), "no custom rotation")
end)

test("a custom rotation, errors and the last review are included", function()
    local s, RH = Fight()
    s.ns.Options:SaveRotation("frost", "actions=obliterate\nactions+=/frost_strike")
    RH:RecordError("display", "boom", "Interface\AddOns\RotationHelper\UI\Display.lua:10: boom\nline 2\nline 3\nline 4")
    RH.db.char.reviews = { { target = "Boss", duration = 60, gcdUsage = 90, adherence = 80, casts = 40,
        mistakes = { { time = 12, cast = "frost_strike", expected = "obliterate", expectedReady = true } } } }
    local text = s.ns.Report.Build()
    truthy(text:find("rotation: Frost (custom)\n", 1, true), "custom named once")
    truthy(text:find("--- Custom rotation ---\nactions=obliterate\nactions+=/frost_strike", 1, true), "its text")
    truthy(text:find("display: boom (x1)", 1, true), "error")
    truthy(text:find("   line 2", 1, true) and not text:find("line 4", 1, true), "first stack lines only")
    truthy(text:find("12s: frost_strike instead of obliterate (ready)", 1, true), "review mistake")
end)

test("/rh report opens the window with everything selected", function()
    local s, RH = Fight()
    s:Slash("ACECONSOLE_RH", "report")
    local R = s.ns.Report
    truthy(R.frame and R.frame:IsShown(), "window")
    eq(R.editBox:GetText(), R.text, "the report in the box")
    truthy(R.hint:GetText():find("github.com/rynosuki/RotationHelperWotlk/issues", 1, true), "where to send it")
    -- Typing doesn't change it.
    R.editBox:SetText("oops")
    R.editBox.scripts.OnTextChanged(R.editBox, true)
    eq(R.editBox:GetText(), R.text, "read-only")
    truthy(s.ns.Options:GetOptionsTable().args.general.args.report, "button on the General tab")
end)

test("works for an unsupported class too", function()
    local s = newAddon({ class = "MONK" })
    local text = s.ns.Report.Build()
    truthy(text:find("No rotation support for this class.", 1, true), "says so")
end)
