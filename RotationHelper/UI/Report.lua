local ADDON_NAME, ns = ...
local RH = ns.RH

-- /rh report: everything needed to look into a problem, as text to copy
-- into a GitHub issue: version, class, spec, talents and glyphs, rotation
-- (with the text if it's a custom one), settings, what the engine sees and
-- decides right now (the /rh snapshot), recent errors, and the last fight
-- review.
local Report = {}
ns.Report = Report

local format, concat = string.format, table.concat

Report.ISSUES_URL = "https://github.com/rynosuki/RotationHelperWotlk/issues"

local MAX_ERRORS = 5
local STACK_LINES = 3

local function OnOff(value) return value and "on" or "off" end

-- The report as one string.
function Report.Build()
    local lines = {}
    local function Add(text) lines[#lines + 1] = text end
    local p = RH.db.profile

    Add("RotationHelper report")
    local build, _, _, toc = nil, nil, nil, nil
    if GetBuildInfo then build, _, _, toc = GetBuildInfo() end
    Add(format("Version %s, client %s (%s)", RH.version, tostring(build or "?"), tostring(toc or "?")))
    local _, race = UnitRace("player")
    Add(format("%s %s, level %d", tostring(race), tostring(RH.playerClass), UnitLevel("player") or 0))

    local spec = ns.Spec and ns.Spec.key
    local source = RH.classSupported and spec and ns.Recommender:GetSource(spec)
    Add(format("Spec: %s; rotation: %s", tostring(spec),
        source and source.name or "none"))
    local t = p.toggles
    Add(format("Settings: cooldowns %s%s, consumables %s, AoE mode %s, latency %s, display %s, %d icons",
        OnOff(t.cooldowns), t.cooldownsBossOnly and " (bosses only)" or "", OnOff(t.consumables),
        tostring(t.aoeMode), tostring(p.latency.mode), p.display.locked and "locked" or "unlocked",
        p.display.numIcons))

    Add("")
    Add("--- What the addon sees ---")
    if RH.classSupported then
        for _, line in ipairs(RH:SnapshotLines()) do Add(line) end
    else
        Add("No rotation support for this class.")
    end

    if source and source.custom then
        Add("")
        Add("--- Custom rotation ---")
        Add(source.text)
    end

    Add("")
    Add("--- Recent errors ---")
    local errors = RH.errors or {}
    if #errors == 0 then Add("none") end
    for i = #errors, math.max(1, #errors - MAX_ERRORS + 1), -1 do
        local err = errors[i]
        Add(format("%s: %s (x%d)", tostring(err.source), tostring(err.message), err.count or 1))
        local n = 0
        for stackLine in tostring(err.stack or ""):gmatch("[^\n]+") do
            n = n + 1
            if n > STACK_LINES then break end
            Add("   " .. stackLine)
        end
    end

    Add("")
    Add("--- Last fight review ---")
    local reviews = RH.db.char.reviews
    local r = reviews[#reviews]
    if not r then
        Add("none")
    else
        Add(format("%s, %ds, casting %s%%, followed the icons %s%% of %d casts", tostring(r.target), r.duration or 0,
            tostring(r.gcdUsage), tostring(r.adherence), r.casts or 0))
        for _, m in ipairs(r.mistakes or {}) do
            Add(format("   %ds: %s instead of %s%s", math.floor(m.time or 0), tostring(m.cast), tostring(m.expected),
                m.expectedReady and " (ready)" or ""))
        end
    end
    return concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Window: the report in a box to copy from
---------------------------------------------------------------------------
local WIDTH, HEIGHT = 620, 460

function Report:Create()
    local T = ns.Skin.theme
    local f = ns.Window.Create({ name = "RotationHelperReportWindow", title = "Bug report",
        width = WIDTH, height = HEIGHT, minWidth = 420, minHeight = 260 })
    self.frame = f

    local hint = ns.Window.Text(f.content, 13, T.textDim)
    hint:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, 0)
    hint:SetPoint("RIGHT", f.content, "RIGHT")
    hint:SetJustifyH("LEFT")
    hint:SetText("Everything is selected: press Ctrl+C, then paste it into a new issue at\n" .. Report.ISSUES_URL
        .. "\nand say what you expected and what happened.")
    self.hint = hint

    local box = CreateFrame("Frame", nil, f.content)
    box:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
    box:SetPoint("BOTTOMRIGHT", f.content, "BOTTOMRIGHT")
    ns.Window.Flat(box, T.panel, T.border)

    local scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -6, 6)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(s, delta)
        local maxScroll = math.max(0, Report.editBox:GetHeight() - s:GetHeight())
        s:SetVerticalScroll(math.max(0, math.min(maxScroll, s:GetVerticalScroll() - delta * 40)))
    end)

    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFont(T.font, 12, "")
    editBox:SetTextColor(unpack(T.text))
    editBox:SetWidth(WIDTH - 60)
    editBox:SetScript("OnEscapePressed", function() f:Hide() end)
    -- Read-only: typing puts the report back.
    editBox:SetScript("OnTextChanged", function(box2, userInput)
        if userInput then
            box2:SetText(Report.text or "")
            box2:HighlightText()
        end
    end)
    scroll:SetScrollChild(editBox)
    self.editBox = editBox
end

function Report:Show()
    if not self.frame then self:Create() end
    self.text = Report.Build()
    self.editBox:SetText(self.text)
    self.frame:Show()
    self.editBox:SetFocus()
    self.editBox:HighlightText()
    return self.text
end

-- /rh report
function RH:ShowReport()
    Report:Show()
end
