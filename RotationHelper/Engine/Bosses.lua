local ADDON_NAME, ns = ...
local RH = ns.RH

-- Known boss names, for "is this a boss fight" (consumables, bosses only).
-- It adds to the level check (skull, worldboss) and boss frames: those
-- already cover most raid bosses, but not dungeon bosses (level 82 elite)
-- or every mob of a multi-boss encounter. Names are enUS (as on Whitemane)
-- and matched ignoring case. More can be added in the options
-- (profile.items.extraBosses, comma separated).
local Bosses = {}
ns.Bosses = Bosses

Bosses.KNOWN = {
    -- Icecrown Citadel
    "Lord Marrowgar", "Lady Deathwhisper", "Deathbringer Saurfang", "Festergut", "Rotface",
    "Professor Putricide", "Prince Valanar", "Prince Keleseth", "Prince Taldaram", "Blood-Queen Lana'thel",
    "Sindragosa", "The Lich King",
    -- Trial of the Crusader
    "Gormok the Impaler", "Acidmaw", "Dreadscale", "Icehowl", "Lord Jaraxxus", "Fjola Lightbane",
    "Eydis Darkbane", "Anub'arak",
    -- Naxxramas
    "Anub'Rekhan", "Grand Widow Faerlina", "Maexxna", "Noth the Plaguebringer", "Heigan the Unclean",
    "Loatheb", "Instructor Razuvious", "Gothik the Harvester", "Thane Korth'azz", "Lady Blaumeux",
    "Sir Zeliek", "Baron Rivendare", "Patchwerk", "Grobbulus", "Gluth", "Thaddius", "Stalagg", "Feugen",
    "Sapphiron", "Kel'Thuzad",
    -- Ulduar
    "Flame Leviathan", "Ignis the Furnace Master", "Razorscale", "XT-002 Deconstructor", "Steelbreaker",
    "Runemaster Molgeim", "Stormcaller Brundir", "Kologarn", "Auriaya", "Hodir", "Thorim", "Freya",
    "Elder Brightleaf", "Elder Ironbranch", "Elder Stonebark", "Mimiron", "Leviathan Mk II", "VX-001",
    "Aerial Command Unit", "General Vezax", "Yogg-Saron", "Algalon the Observer",
    -- Trial of the Champion
    "Marshal Jacob Alerius", "Ambrose Boltspark", "Colosos", "Jaelyna Evensong", "Lana Stouthammer",
    "Mokra the Skullcrusher", "Eressea Dawnsinger", "Runok Wildmane", "Zul'tore", "Deathstalker Visceri",
    "Eadric the Pure", "Argent Confessor Paletress", "The Black Knight",
    -- The Forge of Souls, Pit of Saron, Halls of Reflection
    "Bronjahm", "Devourer of Souls", "Forgemaster Garfrost", "Ick", "Krick", "Scourgelord Tyrannus",
    "Falric", "Marwyn",
    -- Utgarde Keep, Utgarde Pinnacle
    "Skarvald the Constructor", "Dalronn the Controller", "Ingvar the Plunderer",
    "Svala Sorrowgrave", "Gortok Palehoof", "Skadi the Ruthless", "King Ymiron",
    -- The Nexus, The Oculus
    "Grand Magus Telestra", "Anomalus", "Ormorok the Tree-Shaper", "Keristrasza", "Commander Kolurg",
    "Commander Stoutbeard", "Drakos the Interrogator", "Varos Cloudstrider", "Mage-Lord Urom",
    "Ley-Guardian Eregos",
    -- Azjol-Nerub, Ahn'kahet
    "Krik'thir the Gatewatcher", "Hadronox", "Elder Nadox", "Jedoga Shadowseeker", "Amanitar",
    "Herald Volazj",
    -- Drak'Tharon Keep, Gundrak
    "Trollgore", "Novos the Summoner", "King Dred", "The Prophet Tharon'ja", "Slad'ran", "Drakkari Colossus",
    "Moorabi", "Gal'darah", "Eck the Ferocious",
    -- The Violet Hold
    "Erekem", "Moragg", "Ichoron", "Xevozz", "Lavanthor", "Zuramat the Obliterator", "Cyanigosa",
    -- Halls of Stone, Halls of Lightning
    "Maiden of Grief", "Krystallus", "Sjonnir the Ironshaper", "General Bjarngrim", "Volkhan", "Ionar", "Loken",
    -- The Culling of Stratholme
    "Meathook", "Salramm the Fleshcrafter", "Chrono-Lord Epoch", "Mal'Ganis", "Infinite Corruptor",
}

local known = {}

-- Rebuilds the lookup from the list plus the profile's extra names.
function Bosses:Rebuild()
    for k in pairs(known) do known[k] = nil end
    for _, name in ipairs(self.KNOWN) do known[name:lower()] = true end
    local extra = RH.db and RH.db.profile.items.extraBosses or ""
    for entry in extra:gmatch("[^,]+") do
        entry = entry:gsub("^%s+", ""):gsub("%s+$", "")
        if entry ~= "" then known[entry:lower()] = true end
    end
    self.built = true
end

function Bosses:IsKnown(name)
    if not name then return false end
    if not self.built then self:Rebuild() end
    return known[name:lower()] == true
end
