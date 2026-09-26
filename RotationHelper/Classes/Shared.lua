local ADDON_NAME, ns = ...

-- Abilities and auras every class has, merged into each class's data by
-- ns.RegisterClass (a class's own entry with the same key wins).
--
-- Item abilities have no spell ID: `itemSlot` (a trinket slot) or
-- `potionItems` (item IDs, best first; the first one in your bags is
-- used). Engine/Items.lua decides whether they're available.
ns.SharedAbilities = {
    trinket1 = { itemSlot = 13, cooldown = 120, offGcd = true },
    trinket2 = { itemSlot = 14, cooldown = 120, offGcd = true },
    -- Potion of Speed, Indestructible Potion. Once per combat.
    -- consumable: only while consumables are allowed (the POT toggle, bosses only by default).
    potion = { potionItems = { 40211, 40093 }, cooldown = 60, offGcd = true, oncePerCombat = true, consumable = true },
    -- Racials (known only to that race, so skipped for everyone else).
    blood_fury = { id = 20572, cooldown = 120, offGcd = true },     -- Orc (attack power)
    berserking = { id = 26297, cooldown = 180, offGcd = true },     -- Troll
    arcane_torrent = { id = 50613, cooldown = 120, offGcd = true, rp = -15 }, -- Blood Elf, runic power
}

ns.SharedAuras = {
    blood_fury = { id = 20572 },
    berserking = { id = 26297 },
    speed = { id = 53908 }, -- Potion of Speed
}
