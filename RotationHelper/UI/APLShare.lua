local ADDON_NAME, ns = ...
local RH = ns.RH

-- Sharing rotations over addon messages (party, raid or whisper).
--
-- The rotation goes as one RH1: export string (UI/APLText.lua) cut into
-- chunks: a header "H:<id>:<count>" and then "D:<id>:<index>:<data>".
-- Sending is paced, a few messages a second. The receiver is asked before
-- anything opens, and a received rotation lands in the editor unsaved.
local APLShare = RH:NewModule("APLShare", "AceEvent-3.0")
ns.APLShare = APLShare

local SendAddonMessage, UnitName, GetTime = SendAddonMessage, UnitName, GetTime
local format, tonumber = string.format, tonumber

APLShare.PREFIX = "RotHelperAPL" -- at most 16 characters
local CHUNK_SIZE = 200
local SEND_INTERVAL = 0.25 -- seconds between messages
local MAX_CHUNKS = 64      -- about 12 KB: far more than any rotation
local STALE_AFTER = 60     -- seconds before an incomplete transfer is dropped

local queue = {}  -- messages waiting to be sent: { text, channel, target }
local incoming = {} -- [sender .. id] = { count, parts, received, started }
local sendFrame

local function Pump()
    local message = table.remove(queue, 1)
    if message then SendAddonMessage(APLShare.PREFIX, message[1], message[2], message[3]) end
    if #queue == 0 then sendFrame:SetScript("OnUpdate", nil) end
end

-- Queues the rotation for sending. Returns ok, message for the player.
function APLShare:Send(channel, target, specKey, text)
    if channel == "WHISPER" and (not target or target:match("^%s*$")) then
        return false, "Type the player's name first."
    end
    if channel == "PARTY" and GetNumPartyMembers() == 0 and GetNumRaidMembers() == 0 then
        return false, "You're not in a party."
    end
    if channel == "RAID" and GetNumRaidMembers() == 0 then
        return false, "You're not in a raid."
    end
    local chunks = ns.APLText.Chunks(ns.APLText.Export(specKey, text), CHUNK_SIZE)
    if #chunks > MAX_CHUNKS then return false, "That rotation is too long to send." end
    local id = format("%04d", math.random(0, 9999))
    target = target and target:gsub("^%s+", ""):gsub("%s+$", "")
    table.insert(queue, { format("H:%s:%d", id, #chunks), channel, target })
    for i, chunk in ipairs(chunks) do
        table.insert(queue, { format("D:%s:%d:%s", id, i, chunk), channel, target })
    end
    local elapsed = 0
    sendFrame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= SEND_INTERVAL then
            elapsed = 0
            Pump()
        end
    end)
    return true, format("Sending to %s (%d messages)...", channel == "WHISPER" and target or channel:lower(),
        #chunks + 1)
end

-- Handles one addon message; returns the finished export string when a
-- transfer completes.
function APLShare:Receive(message, sender, now)
    local kind, id, rest = message:match("^(%u):(%d+):(.*)$")
    if not kind then return nil end
    local key = sender .. ":" .. id
    for k, t in pairs(incoming) do
        if now - t.started > STALE_AFTER then incoming[k] = nil end
    end
    if kind == "H" then
        local count = tonumber(rest)
        if count and count >= 1 and count <= MAX_CHUNKS then
            incoming[key] = { count = count, parts = {}, received = 0, started = now }
        end
        return nil
    end
    local transfer = incoming[key]
    local index, data = rest:match("^(%d+):(.*)$")
    index = tonumber(index)
    if not (transfer and index and index >= 1 and index <= transfer.count) then return nil end
    if not transfer.parts[index] then
        transfer.parts[index] = data
        transfer.received = transfer.received + 1
    end
    if transfer.received < transfer.count then return nil end
    incoming[key] = nil
    return table.concat(transfer.parts)
end

function APLShare:OnAddonMessage(_, prefix, message, _, sender)
    if prefix ~= APLShare.PREFIX or sender == UnitName("player") then return end
    local str = self:Receive(message, sender, GetTime())
    if not str then return end
    local specKey, text = ns.APLText.Import(str)
    if not text then return end
    StaticPopup_Show("ROTATIONHELPER_RECEIVED_APL",
        format("%s sent you a %s rotation.", sender, specKey or "?"), nil,
        { sender = sender, specKey = specKey, text = text })
end

function APLShare:OnEnable()
    sendFrame = CreateFrame("Frame")
    StaticPopupDialogs["ROTATIONHELPER_RECEIVED_APL"] = {
        text = "%s Open it in the rotation editor? (It isn't saved until you press Accept.)",
        button1 = "Open", button2 = "Ignore",
        OnAccept = function(_, data) ns.Options:OpenReceived(data.specKey, data.text, data.sender) end,
        timeout = 0, whileDead = 1, hideOnEscape = 1,
    }
    self:RegisterEvent("CHAT_MSG_ADDON", "OnAddonMessage")
end
