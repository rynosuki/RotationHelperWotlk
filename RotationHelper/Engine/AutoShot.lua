local ADDON_NAME, ns = ...
local RH = ns.RH

-- Auto Shot timing (Hunters). Auto Shot fires every ranged-weapon swing on
-- its own; a cast (Steady Shot) that is still going when the next Auto Shot
-- is due delays it ("clipping"). The state gets:
--   s.autoShotSpeed  seconds between Auto Shots (hasted), from UnitRangedDamage
--   s.autoShotNext   when the next one fires, or nil when Auto Shot isn't on
-- Abilities with `avoidAutoClip` wait for the Auto Shot when their cast would
-- overlap it (Engine/Abilities.lua).
local AutoShot = RH:NewModule("AutoShot", "AceEvent-3.0")
ns.AutoShot = AutoShot

local GetTime, UnitRangedDamage, GetSpellInfo = GetTime, UnitRangedDamage, GetSpellInfo
local ceil = math.ceil

local AUTO_SHOT = 75

-- When the Auto Shot after (or at) time `t` fires, from the state.
function AutoShot.NextAt(s, t)
    local nextShot, speed = s.autoShotNext, s.autoShotSpeed
    if not nextShot or not speed or speed <= 0 then return nil end
    if nextShot >= t then return nextShot end
    return nextShot + ceil((t - nextShot) / speed) * speed
end

function AutoShot:Read(s, now)
    local speed = UnitRangedDamage("player")
    s.autoShotSpeed = speed and speed > 0 and speed or nil
    s.autoShotNext = nil
    if self.repeating and self.lastShot and s.autoShotSpeed then
        s.autoShotNext = self.lastShot + s.autoShotSpeed
        if s.autoShotNext < now then s.autoShotNext = AutoShot.NextAt(s, now) end
    end
end

function AutoShot:OnSpellcastSucceeded(_, unit, spellName)
    if unit == "player" and spellName == self.name then
        self.lastShot = GetTime()
        self.repeating = true
        RH:Invalidate()
    end
end

function AutoShot:OnEnable()
    if not (RH.classSupported and RH.classData.autoShot) then return end
    self.name = GetSpellInfo(AUTO_SHOT)
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellcastSucceeded")
    self:RegisterEvent("START_AUTOREPEAT_SPELL", function() AutoShot.repeating = true end)
    self:RegisterEvent("STOP_AUTOREPEAT_SPELL", function()
        AutoShot.repeating, AutoShot.lastShot = false, nil
        RH:Invalidate()
    end)
end
