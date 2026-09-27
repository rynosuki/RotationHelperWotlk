local ADDON_NAME, ns = ...
local RH = ns.RH

-- The fight review window: one saved fight summary (Engine/Review.lua) at a
-- time, each metric graded green / yellow / red, unused cooldowns, and the
-- biggest mistakes. The arrows in the title bar browse the saved fights.
local ReviewWindow = {}
ns.ReviewWindow = ReviewWindow

local format, floor = string.format, math.floor

local WIDTH, HEIGHT = 440, 470
local ROW_HEIGHT = 20
local VALUE_X = 230

local GOOD, OK, BAD = { 0.3, 0.9, 0.4 }, { 1, 0.82, 0 }, { 1, 0.35, 0.35 }

-- Grades: { good, ok } thresholds; `lower` when smaller is better.
local GRADES = {
    gcdUsage = { 95, 85 },
    adherence = { 85, 70 },
    uptime = { 95, 85 },
    runeWaste = { 3, 8, lower = true },
    powerCapped = { 2, 6, lower = true },
    manaLow = { 5, 15, lower = true },
    procUsage = { 90, 75 },
}

function ReviewWindow.Grade(kind, value)
    if value == nil then return nil end
    local g = GRADES[kind]
    if g.lower then
        if value <= g[1] then return GOOD elseif value <= g[2] then return OK end
        return BAD
    end
    if value >= g[1] then return GOOD elseif value >= g[2] then return OK end
    return BAD
end

local function Clock(seconds)
    return format("%d:%02d", floor(seconds / 60), floor(seconds % 60))
end

local function AbilityName(key)
    local ability = RH.classData.abilities[key]
    return ability and ability.name or key
end

local function AuraName(key)
    local def = RH.classData.auras[key]
    local id = def and (def.id or (def.ids and def.ids[1]))
    return id and GetSpellInfo(id) or key
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local function ArrowButton(parent, glyph, onClick)
    local T = ns.Skin.theme
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(24)
    b:SetHeight(ns.Window.TITLE_HEIGHT)
    b.text = ns.Window.Text(b, 18, T.textDim)
    b.text:SetPoint("CENTER")
    b.text:SetText(glyph)
    b:SetScript("OnEnter", function() b.text:SetTextColor(1, 1, 1) end)
    b:SetScript("OnLeave", function() b.text:SetTextColor(unpack(T.textDim)) end)
    b:SetScript("OnClick", onClick)
    return b
end

function ReviewWindow:Create()
    local f = ns.Window.Create({ name = "RotationHelperReviewWindow", title = "Fight review",
        width = WIDTH, height = HEIGHT })
    self.frame = f
    self.next = ArrowButton(f.titleBar, ">", function() ReviewWindow:Show(ReviewWindow.index + 1) end)
    self.next:SetPoint("RIGHT", f.closeButton, "LEFT", -2, 0)
    self.previous = ArrowButton(f.titleBar, "<", function() ReviewWindow:Show(ReviewWindow.index - 1) end)
    self.previous:SetPoint("RIGHT", self.next, "LEFT", 0, 0)
    self.lines = {}
end

-- Line `i` of the content: a label and a value, created on first use.
function ReviewWindow:Line(i)
    local line = self.lines[i]
    if not line then
        local T, content = ns.Skin.theme, self.frame.content
        line = {
            label = ns.Window.Text(content, 14, T.text),
            value = ns.Window.Text(content, 14, T.text),
        }
        line.label:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(i - 1) * ROW_HEIGHT)
        line.value:SetPoint("TOPLEFT", content, "TOPLEFT", VALUE_X, -(i - 1) * ROW_HEIGHT)
        self.lines[i] = line
    end
    return line
end

---------------------------------------------------------------------------
-- Filling
---------------------------------------------------------------------------
-- Adds a line; `color` is a grade color or a theme color.
local function Add(self, label, value, labelColor, valueColor)
    self.used = self.used + 1
    local line = self:Line(self.used)
    local T = ns.Skin.theme
    line.label:SetText(label)
    line.label:SetTextColor(unpack(labelColor or T.textDim))
    line.value:SetText(value or "")
    line.value:SetTextColor(unpack(valueColor or T.text))
    line.label:Show()
    line.value:Show()
end

function ReviewWindow:Fill(summary)
    local T = ns.Skin.theme
    self.used = 0
    Add(self, summary.target, format("%s long, at %s", Clock(summary.duration), summary.when), T.heading, T.textDim)
    Add(self, "")

    local grade = ReviewWindow.Grade
    Add(self, "Time spent casting", summary.gcdUsage and format("%.1f%%", summary.gcdUsage) or "-",
        nil, grade("gcdUsage", summary.gcdUsage))
    Add(self, "Following the icons",
        summary.adherence and format("%.0f%% of %d casts", summary.adherence, summary.casts) or "no casts",
        nil, grade("adherence", summary.adherence))
    -- Only the rows that apply to the class (saved fights from before 1.38
    -- have runicPowerCapped instead of powerCapped).
    if summary.runeWaste then
        Add(self, "Rune pairs sitting full", format("%.1f s per minute", summary.runeWaste),
            nil, grade("runeWaste", summary.runeWaste))
    end
    local capped = summary.powerCapped or summary.runicPowerCapped
    if capped then
        Add(self, (summary.powerName or "Runic power") .. " at the cap", format("%.1f s per minute", capped),
            nil, grade("powerCapped", capped))
    end
    if summary.manaLow then
        Add(self, "Mana below 10%", format("%.0f%% of the fight", summary.manaLow), nil, grade("manaLow", summary.manaLow))
    end
    for _, d in ipairs(summary.debuffs) do
        Add(self, AuraName(d.key) .. " uptime", d.uptime and format("%.0f%%", d.uptime) or "-",
            nil, grade("uptime", d.uptime))
    end

    if summary.procs and #summary.procs > 0 then
        Add(self, "")
        Add(self, "Procs used", "", T.heading)
        for _, p in ipairs(summary.procs) do
            local usage = floor(p.used / p.gained * 100 + 0.5)
            Add(self, "   " .. AuraName(p.key), format("%d of %d", p.used, p.gained), nil, grade("procUsage", usage))
        end
    end

    Add(self, "")
    Add(self, "Cooldowns left unused", #summary.cooldowns == 0 and "none" or "", T.heading,
        #summary.cooldowns == 0 and GOOD or nil)
    for _, cd in ipairs(summary.cooldowns) do
        Add(self, "   " .. AbilityName(cd.key), "ready for " .. Clock(cd.unused))
    end

    Add(self, "")
    Add(self, "Biggest mistakes",
        summary.mistakeCount == 0 and "none" or format("%d in total", summary.mistakeCount),
        T.heading, summary.mistakeCount == 0 and GOOD or nil)
    for _, m in ipairs(summary.mistakes) do
        Add(self, "   " .. Clock(m.time) .. "  " .. AbilityName(m.cast),
            "instead of " .. AbilityName(m.expected) .. (m.expectedReady and " (ready)" or ""))
    end

    for i = self.used + 1, #self.lines do
        self.lines[i].label:Hide()
        self.lines[i].value:Hide()
    end
end

-- Shows saved fight `index` (default: the newest). Returns false if there
-- are no saved fights.
function ReviewWindow:Show(index)
    local reviews = RH.db.char.reviews
    if #reviews == 0 then
        RH:Print("No fights recorded yet (fights shorter than " .. RH.db.profile.review.minDuration
            .. "s aren't kept).")
        return false
    end
    if not self.frame then self:Create() end
    index = math.max(1, math.min(index or #reviews, #reviews))
    self.index = index
    self.frame.subtitle:SetText(format("%d of %d", index, #reviews))
    if index > 1 then self.previous:Show() else self.previous:Hide() end
    if index < #reviews then self.next:Show() else self.next:Hide() end
    self:Fill(reviews[index])
    self.frame:Show()
    return true
end
