local ADDON_NAME, ns = ...
local RH = ns.RH
local Utils = ns.Utils

-- Spec, talents and glyphs for the active talent group. 3.3.5 has no
-- specialization API, so the spec is the tree with the most points.
-- Talents and glyphs are keyed by snake_case name, e.g.
--   Spec.talents.blood_of_the_north = 3
--   Spec.glyphs.frost_strike = true   ("Glyph of Frost Strike")
local Spec = RH:NewModule("Spec", "AceEvent-3.0", "AceTimer-3.0")
ns.Spec = Spec

local GetNumTalentTabs, GetTalentTabInfo, GetNumTalents, GetTalentInfo =
    GetNumTalentTabs, GetTalentTabInfo, GetNumTalents, GetTalentInfo
local GetActiveTalentGroup, GetGlyphSocketInfo, GetSpellInfo = GetActiveTalentGroup, GetGlyphSocketInfo, GetSpellInfo
local wipe, pairs = wipe, pairs

local NUM_GLYPH_SOCKETS = 6
local RETRY_DELAY = 2 -- seconds between retries while talent data isn't loaded
local MAX_RETRIES = 30

Spec.key = nil        -- "frost", "blood", ...
Spec.points = {}      -- points per tree
Spec.group = 1        -- active talent group (dual spec)
Spec.talents = {}
Spec.glyphs = {}
Spec.known = {}       -- ability key -> true if in the spellbook
Spec.trees = {}       -- spec key -> tree name, e.g. frost = "Frost"

function Spec:Update()
    local group = GetActiveTalentGroup and GetActiveTalentGroup() or 1
    self.group = group
    wipe(self.points)
    wipe(self.talents)
    wipe(self.glyphs)

    local bestPoints, bestKey, totalPoints = 0, nil, 0
    self.numTabs = GetNumTalentTabs() or 0
    for tab = 1, self.numTabs do
        local tabName, _, pointsSpent = GetTalentTabInfo(tab, false, false, group)
        self.points[tab] = pointsSpent or 0
        if tabName then self.trees[Utils.Key(tabName)] = tabName end
        totalPoints = totalPoints + (pointsSpent or 0)
        if (pointsSpent or 0) > bestPoints then
            bestPoints, bestKey = pointsSpent, Utils.Key(tabName)
        end
        for i = 1, GetNumTalents(tab, false, false) do
            local name, _, _, _, rank = GetTalentInfo(tab, i, false, false, group)
            if name and rank and rank > 0 then
                self.talents[Utils.Key(name)] = rank
            end
        end
    end
    self.key = bestKey

    -- Right after login the talent API can return nothing yet. Keep
    -- retrying until it does.
    self.loaded = totalPoints > 0
    if self.loaded then
        self.retries = 0
    elseif not self.retryTimer and (self.retries or 0) < MAX_RETRIES then
        self.retries = (self.retries or 0) + 1
        self.retryTimer = self:ScheduleTimer("RetryUpdate", RETRY_DELAY)
    end

    for socket = 1, NUM_GLYPH_SOCKETS do
        local enabled, _, glyphSpellId = GetGlyphSocketInfo(socket, group)
        if enabled and glyphSpellId then
            local key = Utils.Key(GetSpellInfo(glyphSpellId))
            if key then
                self.glyphs[(key:gsub("^glyph_of_", ""))] = true
            end
        end
    end

    -- Looking a spell up by name only succeeds if it's in the spellbook.
    wipe(self.known)
    local classData = RH.classData
    if classData then
        for key, ability in pairs(classData.abilities) do
            self.known[key] = ability.name ~= nil and GetSpellInfo(ability.name) ~= nil
        end
    end

    self.supported = classData and classData.specs[self.key] or false
    RH:Invalidate()
end

function Spec:RetryUpdate()
    self.retryTimer = nil
    self:Update()
end

function Spec:TalentRank(key)
    return self.talents[key] or 0
end

function Spec:HasGlyph(key)
    return self.glyphs[key] or false
end

function Spec:OnEnable()
    if not RH.classSupported then return end
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "Update")
    self:RegisterEvent("PLAYER_ALIVE", "Update")
    self:RegisterEvent("SPELLS_CHANGED", "Update")
    self:RegisterEvent("PLAYER_TALENT_UPDATE", "Update")
    self:RegisterEvent("GLYPH_ADDED", "Update")
    self:RegisterEvent("GLYPH_REMOVED", "Update")
    self:RegisterEvent("GLYPH_UPDATED", "Update")
    self:RegisterEvent("LEARNED_SPELL_IN_TAB", "Update")
    self:RegisterMessage("ROTATIONHELPER_TALENTS_CHANGED", "Update")
    self:Update()
end
