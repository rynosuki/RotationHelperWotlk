local ADDON_NAME, ns = ...
local RH = ns.RH

-- Pull timer: rotations can prepare for the pull with pull.active and
-- pull.remains (e.g. Army of the Dead at 10 seconds).
--
-- Started by boss mods' pull timers (DBM's "pizza" timer:
-- prefix DBMv4-Pizza, message "10\tPull in"; BigWigs likewise: any DBM or
-- BigWigs message mentioning "pull" with a number), or by /rh pull N.
-- A 0 cancels; entering combat ends it.
local PullTimer = RH:NewModule("PullTimer", "AceEvent-3.0")
ns.PullTimer = PullTimer

local GetTime, tonumber, max = GetTime, tonumber, math.max

local MAX_SECONDS = 60
local LINGER = 2 -- keep reporting 0 this long after the countdown ends

function PullTimer:Start(seconds, source)
    if seconds <= 0 then
        self.pullAt, self.source = nil, nil
    else
        self.pullAt, self.source = GetTime() + seconds, source
    end
    RH:Invalidate()
end

-- Seconds until the pull, or nil when no timer runs.
function PullTimer:Remains(now)
    if not self.pullAt then return nil end
    local remains = self.pullAt - now
    if remains < -LINGER then
        self.pullAt = nil
        return nil
    end
    return max(0, remains)
end

function PullTimer:OnAddonMessage(_, prefix, message, _, sender)
    local p = prefix:lower()
    if not (p:find("dbm", 1, true) or p:find("bigwigs", 1, true)) then return end
    if not message:lower():find("pull", 1, true) then return end
    local seconds = tonumber(message:match("(%d+)"))
    if seconds and seconds <= MAX_SECONDS then self:Start(seconds, sender) end
end

function PullTimer:OnEnable()
    if not RH.classSupported then return end
    self:RegisterEvent("CHAT_MSG_ADDON", "OnAddonMessage")
    self:RegisterMessage("ROTATIONHELPER_COMBAT_CHANGED", function(_, inCombat)
        if inCombat then PullTimer.pullAt = nil end
    end)
end
