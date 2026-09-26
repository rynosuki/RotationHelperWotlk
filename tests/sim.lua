-- Offline rotation simulator: compares rotations side by side.
--
--   lua tests/sim.lua <blood|frost|unholy|retribution|arms|fury|enhancement|shadow|fire|arcane|affliction|destruction|elemental> [options] [rotation files...]
--
-- Without files it simulates the spec's default rotation. With files, each
-- file is simulated (add "default" to include the default for comparison).
-- Options:
--   --seconds N     fight length (300)
--   --runs N        fights to average (20)
--   --enemies N     targets for AoE lists (1)
--   --seed N        first random seed (1)
--   --no-cooldowns  as if cooldowns were toggled off
--
-- Uses a typical 3.3.5 build for the spec (below) and the mocked client
-- from the test suite; the numbers are proxies, not damage.
package.path = "./tests/?.lua;" .. package.path
local Mock = require("wowmock")

local BUILDS = {
    elemental = {
        class = "SHAMAN", power = { type = 0, current = 22000, max = 22000 },
        talents = {
            { name = "Elemental", talents = { { "Lightning Mastery", 5 }, { "Elemental Mastery", 1 }, { "Thunderstorm", 1 },
                { "Totem of Wrath", 1 }, { "Lava Flows", 3 }, { "Reverberation", 5 } } },
            { name = "Enhancement", talents = { { "Ancestral Knowledge", 5 } } },
            { name = "Restoration", talents = {} },
        },
        spells = { "Lava Burst", "Lightning Bolt", "Chain Lightning", "Flame Shock", "Earth Shock", "Frost Shock",
            "Thunderstorm", "Elemental Mastery", "Totem of Wrath", "Fire Elemental Totem", "Water Shield", "Wind Shear",
            "Lesser Healing Wave", "Lightning Shield" },
    },
    destruction = {
        class = "WARLOCK", power = { type = 0, current = 20000, max = 20000 },
        talents = {
            { name = "Affliction", talents = { { "Improved Curse of Agony", 2 } } },
            { name = "Demonology", talents = { { "Demonic Embrace", 3 } } },
            { name = "Destruction", talents = { { "Bane", 5 }, { "Emberstorm", 5 }, { "Backdraft", 3 }, { "Conflagrate", 1 },
                { "Chaos Bolt", 1 }, { "Ruin", 5 }, { "Devastation", 1 } } },
        },
        spells = { "Immolate", "Conflagrate", "Chaos Bolt", "Incinerate", "Curse of Doom", "Curse of Agony", "Corruption",
            "Shadow Bolt", "Seed of Corruption", "Searing Pain", "Life Tap", "Fel Armor", "Demon Skin" },
    },
    affliction = {
        class = "WARLOCK", power = { type = 0, current = 20000, max = 20000 },
        talents = {
            { name = "Affliction", talents = { { "Everlasting Affliction", 5 }, { "Haunt", 1 }, { "Unstable Affliction", 1 },
                { "Pandemic", 1 }, { "Shadow Embrace", 5 } } },
            { name = "Demonology", talents = { { "Demonic Embrace", 3 } } },
            { name = "Destruction", talents = { { "Bane", 5 } } },
        },
        spells = { "Haunt", "Corruption", "Unstable Affliction", "Curse of Agony", "Curse of the Elements", "Shadow Bolt",
            "Drain Soul", "Seed of Corruption", "Searing Pain", "Life Tap", "Fel Armor", "Demon Skin" },
    },
    arcane = {
        class = "MAGE", power = { type = 0, current = 20000, max = 20000 },
        talents = {
            { name = "Arcane", talents = { { "Missile Barrage", 5 }, { "Arcane Flows", 2 }, { "Arcane Power", 1 },
                { "Presence of Mind", 1 }, { "Arcane Empowerment", 3 } } },
            { name = "Fire", talents = { { "Improved Fireball", 2 } } },
            { name = "Frost", talents = {} },
        },
        spells = { "Arcane Blast", "Arcane Missiles", "Arcane Barrage", "Arcane Power", "Presence of Mind",
            "Mirror Image", "Evocation", "Molten Armor", "Counterspell", "Arcane Intellect", "Scorch", "Fireball" },
    },
    fire = {
        class = "MAGE", power = { type = 0, current = 20000, max = 20000 },
        talents = {
            { name = "Arcane", talents = { { "Arcane Focus", 3 } } },
            { name = "Fire", talents = { { "Improved Fireball", 5 }, { "Improved Scorch", 3 }, { "Hot Streak", 3 },
                { "Living Bomb", 1 }, { "Combustion", 1 } } },
            { name = "Frost", talents = {} },
        },
        spells = { "Fireball", "Pyroblast", "Living Bomb", "Scorch", "Fire Blast", "Flamestrike", "Combustion",
            "Mirror Image", "Evocation", "Molten Armor", "Counterspell", "Arcane Intellect" },
    },
    shadow = {
        class = "PRIEST", power = { type = 0, current = 22000, max = 22000 },
        talents = {
            { name = "Discipline", talents = { { "Twin Disciplines", 5 } } },
            { name = "Holy", talents = {} },
            { name = "Shadow", talents = { { "Improved Mind Blast", 5 }, { "Pain and Suffering", 3 }, { "Vampiric Touch", 1 },
                { "Shadowform", 1 }, { "Dispersion", 1 }, { "Misery", 3 } } },
        },
        spells = { "Vampiric Touch", "Shadow Word: Pain", "Devouring Plague", "Mind Blast", "Mind Flay", "Mind Sear",
            "Shadow Word: Death", "Shadowfiend", "Dispersion", "Shadowform", "Inner Fire", "Vampiric Embrace",
            "Silence", "Power Word: Fortitude" },
    },
    enhancement = {
        class = "SHAMAN", power = { type = 0, current = 20000, max = 20000 },
        talents = {
            { name = "Elemental", talents = { { "Convection", 5 }, { "Reverberation", 5 } } },
            { name = "Enhancement", talents = { { "Maelstrom Weapon", 5 }, { "Improved Fire Nova", 2 }, { "Stormstrike", 1 },
                { "Lava Lash", 1 }, { "Feral Spirit", 1 }, { "Shamanistic Rage", 1 }, { "Dual Wield", 1 } } },
            { name = "Restoration", talents = {} },
        },
        spells = { "Stormstrike", "Lava Lash", "Earth Shock", "Flame Shock", "Frost Shock", "Lightning Bolt",
            "Chain Lightning", "Fire Nova", "Magma Totem", "Searing Totem", "Lightning Shield", "Feral Spirit",
            "Shamanistic Rage", "Wind Shear" },
    },
    arms = {
        class = "WARRIOR", power = { type = 1, current = 20, max = 100 },
        talents = {
            { name = "Arms", talents = { { "Improved Heroic Strike", 3 }, { "Taste for Blood", 3 }, { "Sudden Death", 3 },
                { "Improved Mortal Strike", 3 }, { "Unrelenting Assault", 2 }, { "Bladestorm", 1 }, { "Mortal Strike", 1 } } },
            { name = "Fury", talents = { { "Improved Berserker Rage", 2 } } },
            { name = "Protection", talents = {} },
        },
        spells = { "Mortal Strike", "Rend", "Overpower", "Bladestorm", "Sweeping Strikes", "Slam", "Execute",
            "Heroic Strike", "Cleave", "Battle Shout", "Bloodrage", "Berserker Rage", "Hamstring", "Pummel" },
    },
    fury = {
        class = "WARRIOR", power = { type = 1, current = 20, max = 100 },
        talents = {
            { name = "Arms", talents = { { "Improved Heroic Strike", 3 } } },
            { name = "Fury", talents = { { "Bloodsurge", 3 }, { "Intensify Rage", 3 }, { "Improved Berserker Rage", 2 },
                { "Death Wish", 1 }, { "Bloodthirst", 1 }, { "Titan's Grip", 1 } } },
            { name = "Protection", talents = {} },
        },
        spells = { "Bloodthirst", "Whirlwind", "Slam", "Execute", "Heroic Strike", "Cleave", "Battle Shout",
            "Bloodrage", "Berserker Rage", "Death Wish", "Recklessness", "Pummel", "Hamstring" },
    },
    retribution = {
        class = "PALADIN", power = { type = 0, current = 25000, max = 25000 },
        talents = {
            { name = "Holy", talents = { { "Divine Intellect", 5 } } },
            { name = "Protection", talents = { { "Divine Strength", 5 } } },
            { name = "Retribution", talents = { { "Improved Judgements", 2 }, { "The Art of War", 2 },
                { "Sanctified Wrath", 2 }, { "Judgements of the Wise", 3 } } },
        },
        spells = { "Crusader Strike", "Divine Storm", "Judgement of Light", "Consecration", "Exorcism",
            "Hammer of Wrath", "Holy Wrath", "Avenging Wrath", "Divine Plea", "Seal of Vengeance", "Blessing of Might" },
    },
    blood = {
        talents = {
            { name = "Blood", talents = { { "Heart Strike", 1 }, { "Dancing Rune Weapon", 1 }, { "Hysteria", 1 },
                { "Rune Tap", 1 }, { "Vampiric Blood", 1 }, { "Butchery", 2 }, { "Subversion", 3 },
                { "Bladed Armor", 5 }, { "Blood-Caked Blade", 3 }, { "Veteran of the Third War", 3 },
                { "Might of Mograine", 3 }, { "Bloody Vengeance", 3 }, { "Improved Death Strike", 2 },
                { "Sudden Doom", 3 }, { "Blood Gorged", 5 }, { "Dark Conviction", 5 } } },
            { name = "Frost", talents = { { "Improved Icy Touch", 3 } } },
            { name = "Unholy", talents = { { "Epidemic", 2 }, { "Virulence", 3 }, { "Morbidity", 3 } } },
        },
        spells = { "Icy Touch", "Plague Strike", "Heart Strike", "Death Strike", "Death Coil", "Pestilence",
            "Blood Boil", "Death and Decay", "Horn of Winter", "Blood Tap", "Empower Rune Weapon",
            "Dancing Rune Weapon", "Hysteria", "Rune Tap", "Vampiric Blood", "Rune Strike", "Mind Freeze" },
    },
    frost = {
        talents = {
            { name = "Blood", talents = { { "Subversion", 3 }, { "Butchery", 2 } } },
            { name = "Frost", talents = { { "Blood of the North", 3 }, { "Killing Machine", 5 },
                { "Chill of the Grave", 2 }, { "Rime", 3 }, { "Unbreakable Armor", 1 }, { "Deathchill", 1 },
                { "Howling Blast", 1 }, { "Frost Strike", 1 }, { "Icy Talons", 5 }, { "Merciless Combat", 2 } } },
            { name = "Unholy", talents = { { "Epidemic", 2 } } },
        },
        spells = { "Icy Touch", "Plague Strike", "Obliterate", "Frost Strike", "Howling Blast", "Blood Strike",
            "Pestilence", "Blood Boil", "Death and Decay", "Horn of Winter", "Blood Tap", "Unbreakable Armor",
            "Empower Rune Weapon", "Deathchill", "Death Coil", "Mind Freeze" },
    },
    unholy = {
        talents = {
            { name = "Blood", talents = { { "Subversion", 3 } } },
            { name = "Frost", talents = { { "Icy Talons", 5 } } },
            { name = "Unholy", talents = { { "Reaping", 3 }, { "Desolation", 5 }, { "Dirge", 2 },
                { "Master of Ghouls", 1 }, { "Epidemic", 2 }, { "Ghoul Frenzy", 1 }, { "Bone Shield", 1 },
                { "Summon Gargoyle", 1 }, { "Morbidity", 3 } } },
        },
        spells = { "Icy Touch", "Plague Strike", "Scourge Strike", "Blood Strike", "Death Coil", "Pestilence",
            "Blood Boil", "Death and Decay", "Horn of Winter", "Raise Dead", "Ghoul Frenzy", "Summon Gargoyle",
            "Bone Shield", "Blood Tap", "Empower Rune Weapon", "Mind Freeze" },
    },
}

local function Usage(message)
    if message then print(message) end
    print("usage: lua tests/sim.lua <blood|frost|unholy|retribution|arms|fury|enhancement|shadow|fire|arcane|affliction|destruction|elemental> [--seconds N] [--runs N] [--enemies N] [--seed N] "
        .. "[--no-cooldowns] [default] [rotation files...]")
    os.exit(1)
end

-- Arguments
local specKey = arg[1]
local build = BUILDS[specKey or ""]
if not build then Usage(specKey and ("unknown spec '" .. specKey .. "'") or nil) end
local opts, runs, files = { seconds = 300, seed = 1, enemies = 1 }, 20, {}
local i = 2
while arg[i] do
    local a = arg[i]
    if a == "--seconds" then opts.seconds = tonumber(arg[i + 1]); i = i + 1
    elseif a == "--runs" then runs = tonumber(arg[i + 1]); i = i + 1
    elseif a == "--enemies" then opts.enemies = tonumber(arg[i + 1]); i = i + 1
    elseif a == "--seed" then opts.seed = tonumber(arg[i + 1]); i = i + 1
    elseif a == "--no-cooldowns" then opts.cooldowns = false
    elseif a:sub(1, 2) == "--" then Usage("unknown option " .. a)
    else files[#files + 1] = a end
    i = i + 1
end
if #files == 0 then files[1] = "default" end

-- A mocked client with the build
local s = Mock.NewSession({ class = build.class })
if build.power then s.power = build.power end
s.talentTabs = build.talents
s:LoadAddon()
s:Learn(unpack(build.spells))
local ns = s.ns
if ns.Spec.key ~= specKey then Usage("the build didn't come out as " .. specKey) end

-- Compile each rotation
local rotations = {}
for _, file in ipairs(files) do
    local text
    if file == "default" then
        text = ns.APLs[build.class or "DEATHKNIGHT"][specKey].text
    else
        local f = io.open(file, "r")
        if not f then Usage("can't read " .. file) end
        text = f:read("*a")
        f:close()
    end
    local apl = ns.Recommender:Compile(text)
    if #apl.errors > 0 then
        print(file .. " has errors:")
        for _, err in ipairs(apl.errors) do print("  " .. ns.APL.Compiler.FormatError(err)) end
        os.exit(1)
    end
    rotations[#rotations + 1] = { name = file, summary = ns.Sim.Summarize(apl, opts, runs) }
end

-- Side-by-side table
local rows = {
    { "Time spent casting %", function(sm) return sm.gcdUsage end },
}
if not build.class then -- Death Knights
    rows[#rows + 1] = { "Rune pairs full s/min", function(sm) return sm.runeWaste end }
    rows[#rows + 1] = { "Runic power at cap s/min", function(sm) return sm.rpCapped end }
    rows[#rows + 1] = { "Runic power lost /min", function(sm) return sm.rpLost end }
end
local first = rotations[1].summary
for d = 1, #first.debuffs do
    rows[#rows + 1] = { first.debuffs[d].key .. " uptime %", function(sm) return sm.debuffs[d].uptime end }
end
for p = 1, #first.procs do
    local aura = first.procs[p].aura
    rows[#rows + 1] = { aura .. " wasted /fight", function(sm) return sm.procs[p].wasted end }
end
local abilities, seen = {}, {}
for _, r in ipairs(rotations) do
    for _, c in ipairs(r.summary.casts) do
        if not seen[c.key] then seen[c.key] = true; abilities[#abilities + 1] = c.key end
    end
end
for _, key in ipairs(abilities) do
    rows[#rows + 1] = { key .. " /min", function(sm)
        for _, c in ipairs(sm.casts) do if c.key == key then return c.perMinute end end
        return 0
    end }
end

print(("%s, %d fights of %ds, %d enemies%s"):format(specKey, runs, opts.seconds, opts.enemies,
    opts.cooldowns == false and ", cooldowns off" or ""))
local header = ("%-28s"):format("")
for _, r in ipairs(rotations) do header = header .. ("%14s"):format(r.name:sub(-14)) end
print(header)
for _, row in ipairs(rows) do
    local line = ("%-28s"):format(row[1])
    for _, r in ipairs(rotations) do line = line .. ("%14.1f"):format(row[2](r.summary)) end
    print(line)
end
