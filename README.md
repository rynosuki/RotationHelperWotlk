# RotationHelper

A Hekili-style rotation helper for **World of Warcraft 3.3.5a** (WotLK), tested on Whitemane.
It shows the ability to press next, plus a prediction of the few after it, based on a
priority list you can read and edit in game.

Supported so far: all three **Death Knight** specs: **Frost**, **Unholy** and **Blood**. Blood
plays the DPS rotation in Blood Presence and switches to a tank list in Frost Presence (Rune
Strike after dodges and parries, Rune Tap and Vampiric Blood when you're hurt, runic power kept
for Rune Strike). **Retribution Paladin** plays the classic first-come-first-served priority
(Judgement, Hammer of Wrath, Crusader Strike, Divine Storm, Consecration, Exorcism with The Art
of War, Holy Wrath on undead and demons) and keeps your seal up; which Judgement it suggests is
set on the General tab. **Fury Warrior** plays Bloodthirst, Whirlwind, Slam with Bloodsurge and
Execute, with Heroic Strike (Cleave on several targets) on the next swing when there's rage to
spare. When you're short on rage, the icon counts down to when your rage income (learned during
the fight) will cover it. **Arms Warrior** keeps Rend up and plays Overpower (Taste for Blood or a
dodge), Mortal Strike, Execute (Sudden Death or below 20%), Bladestorm and Slam. The checklist
flags the wrong stance for your spec. **Enhancement Shaman** plays Lightning Bolt (Chain Lightning
on several targets) at 5 Maelstrom Weapon stacks, Stormstrike, Flame Shock, Earth Shock (without
letting Flame Shock drop), Magma Totem and Fire Nova, Lava Lash and Lightning Shield, with
Shamanistic Rage when mana runs low; the checklist wants weapon imbues on. **Shadow Priest** keeps
Vampiric Touch, Devouring Plague and Shadow Word: Pain up (refreshed before a Mind Flay would let
them drop; Mind Flay keeps Shadow Word: Pain going), with Mind Blast and Mind Flay. Casts and
channels delay the next icon by their hasted time, and while you move only instants are shown.
**Fire Mage** keeps the crit debuff (Improved Scorch, unless someone else's is up) and Living Bomb
going, casts Pyroblast when Hot Streak makes it instant, and fills with Fireball; Fire Blast
while moving. **Arcane Mage** spams Arcane Blast above 35% mana and below it builds 4 stacks and
spends them with Arcane Missiles; Missile Barrage procs are used at 4 stacks, Presence of Mind
makes an Arcane Blast instant, Arcane Barrage while moving. **Affliction Warlock** casts Haunt on
cooldown, keeps Unstable Affliction, Corruption (kept going by Everlasting Affliction) and Curse
of Agony up, and fills with Shadow Bolt (Drain Soul below 25%), with Life Tap for mana and
while moving. Other classes load but stay idle. See [docs/SPECS.md](docs/SPECS.md) for
what's planned.

## Install

1. Copy the `RotationHelper` folder into `World of Warcraft\Interface\AddOns\`.
2. Start the game (a new addon needs a full restart, `/reload` isn't enough).
3. At character select, make sure RotationHelper is ticked under AddOns.

## First steps

1. Log in on your Death Knight. Sample icons appear below the middle of the screen.
2. Drag them where you want them, then type `/rh lock`.
3. Target a training dummy and fight. The big icon is what to press now. The smaller icons
   show what comes after it, assuming you follow along.

## Reading the display

| What you see | Meaning |
|---|---|
| Big icon | The ability to use next. |
| Small icons | The predicted next abilities, in order. |
| Cooldown swipe on the big icon | The ability isn't usable yet: GCD, cooldown or runes. Auto attack until the swipe finishes. |
| Big icon flashes | Press it now. With latency compensation (General options) the flash comes slightly before the GCD ends, as soon as the client would queue your press. |
| Red `!` left of the icons | The addon hit an error; see `/rh errors`. |
| Pulsing orange border, `RUNES` / `RP` on the status line | Resources are going to waste right now: a rune pair is full, or runic power is near the cap. |
| Small icon above the big one | Your target is casting something you can interrupt: press it (Mind Freeze). |
| Golden glow on an icon | That ability spends a proc (Killing Machine, Rime). An optional sound can play for new procs (Display options). |
| Small proc icon in the bottom-right corner | That proc is *why* the ability is recommended now, e.g. Frost Strike because of Killing Machine, or the free Howling Blast from Rime. |
| `RUNES` / `COOLDOWN` / `CAST` / `WAIT` on the big icon | It's more than a GCD away; this is what it waits on. |
| Small icon below the status line | The big icon's ability is out of range; this is the best thing you can do from where you are. |
| Steady red border, `THREAT` on the status line | In a group: you're close to pulling aggro (default 90%). |
| Six small bars above the icons | Your runes: color = type (purple = death), dim with seconds while recharging. The strip under each shows the rune once the queued abilities are used: its type then, dimmed if the queue spends it. |
| Small icons above the runes | Major cooldowns and trinkets: grey with the time left while on cooldown. |
| `Missing: ...` under the icons | Out of combat with a boss or elite targeted: what you still need before the pull (flask, food, Horn of Winter, presence, ghoul). |
| Blue icon | Waiting on runes. |
| Red icon | Your target is out of range for it. |
| Text in the corner | The key the ability is bound to. |
| `CD` under the big icon | Green: cooldowns are recommended now. Yellow: on, but waiting for a boss. Red: off. |
| `POT` next to it (while you have a potion) | Green: potions can be suggested now. Yellow: on, but waiting for a boss. Red: off. |
| `ST` / `AOE` / a number under the big icon | The AoE mode is forced to single target / AoE, or (auto mode) how many enemies are counted. |

Colors can be changed under Display > Colors, including a color-blind friendly preset.

**Timeline** (Display > Extras): the queued icons are placed by when they can be used, with the
time under each and a tick every second. Back-to-back GCDs sit next to each other as usual; a gap
means waiting, usually on runes. The rune bar and cooldown strip can be turned off there too.

Hold **Shift** over the (locked) display to hover an icon for a tooltip explaining why it's
recommended (which rotation line, what it's waiting on), and to click `CD` or the AoE mode to
toggle them. Without Shift, clicks pass through as usual.

Procs like Killing Machine and Rime are random, so the prediction never assumes them. The icons
update as soon as one happens.

## Commands

| Command | What it does |
|---|---|
| `/rh` | Open the options panel (also under Interface > AddOns). |
| `/rh apl` | Open the rotation editor. |
| `/rh lock` | Lock or unlock the display. |
| `/rh cd` | Toggle cooldown recommendations. |
| `/rh pots` | Toggle consumables (potions). |
| `/rh aoe` | Cycle the AoE mode: auto > single > aoe. |
| `/rh pause` | Pause or resume. |
| `/rh test` | Show or hide sample icons. |
| `/rh scale <0.5-3>` | Display scale. |
| `/rh icons <1-5>` | How many icons to show. |
| `/rh snapshot` | Print everything the addon reads from the game, its prediction and why. |
| `/rh why <ability>` | Why an ability is or isn't recommended right now, e.g. `/rh why frost strike`. |
| `/rh review [n]` | Show the last fight review, or saved fight n. |
| `/rh damage` | Your damage per ability from the combat log. `/rh damage reset` starts over. |
| `/rh pull <seconds>` | Start a pull timer for the rotation (0 cancels). DBM and BigWigs pull timers work too. |
| `/rh sim [seconds]` | Simulate the active rotation (5 fights, 300s by default). |
| `/rh perf` | Show what the addon costs in CPU and memory. `/rh perf reset` starts over. |
| `/rh errors` | Show recorded addon errors (a red "!" next to the icons means there are new ones). `/rh errors clear` empties the list. |
| `/rh status` | Print the current settings. |
| `/rh help` | List the commands. |

Toggles can also be bound to keys (Escape > Key Bindings > RotationHelper), or used from the minimap
button: left click opens the options, right click toggles cooldowns, drag moves it.

## Before the pull, trinkets and burst

- **Checklist**: with a boss or elite targeted out of combat, the display lists what's missing:
  a flask or elixir, Well Fed, Horn of Winter (or Strength of Earth), your presence (Blood
  Presence by default; set per spec on the General tab) and, for Unholy, your ghoul.
- **Pull timer**: while a DBM or BigWigs pull timer runs (or one from `/rh pull 10`), the
  rotation suggests Army of the Dead about 10 seconds out and a potion right at the pull.
- **Trinkets, racials, potions**: trinkets with a use effect, Blood Fury, Berserking, Arcane
  Torrent and Potion of Speed (or Indestructible Potion) from your bags are part of the
  cooldowns list, so they only show with cooldowns on. Only trinkets whose use effect helps
  damage (attack power, haste, crit, armor penetration, ...) are suggested; tank trinkets like an
  armor or health on-use are left to you. General > Trinkets can change that and shows how your
  trinkets were read. A potion is suggested once per combat,
  with Bloodlust or near the end of a fight.
- **Bosses only**: big cooldowns (Empower Rune Weapon, Summon Gargoyle, Dancing Rune Weapon,
  Hysteria, racials, trinkets) are by default only suggested in boss fights, the same as
  consumables below. Short ones that are part of the rotation (Unbreakable Armor, Deathchill,
  Blood Tap) are used on trash too; turning CD off stops them as well. "Only against bosses" under the Cooldowns toggle turns
  that off. On trash the fight review doesn't count them as unused either.
- **Consumables**: potions have their own toggle (the `POT` chip, `/rh pots`, a key binding). By
  default they're only suggested against bosses, so trash and add pulls don't use them. A boss is
  a skull-level target, any target while boss frames are up, or a target whose name is on the
  built-in list (ICC, ToC, Naxxramas, Ulduar and the WotLK dungeons, every mob of multi-boss
  encounters included). Missing ones can be added under General > Extra bosses, which also shows
  whether your current target counts. "Only against bosses" turns the check off.
  For the pre-pull potion, have the boss targeted when the pull timer ends.
- **Burst windows**: Summon Gargoyle keeps the stats you have when it's summoned, so it waits
  for a burst buff (Bloodlust, Hyperspeed Acceleration, trinket procs, ...), but no more than
  15 seconds. More buffs can be added by name or spell ID on the General tab.

## Fight review

Every fight longer than 20 seconds is reviewed. `/rh review` (or the button on the General tab)
shows how it went, graded green, yellow or red; to have it pop up by itself after each fight,
turn on "Show after each fight" on the General tab.

- **Time spent casting**: the share of the fight the GCD was in use while there was something to
  press (latency compensation isn't counted against you).
- **Following the icons**: how many of your GCD casts matched one of the first two icons.
  Off-GCD cooldowns only count when they match, so weaving one early isn't a mistake.
- **Rune pairs sitting full** and **runic power at the cap**, in seconds per minute.
- **Disease uptime** on your target.
- **Cooldowns left unused** while they were ready, and the **biggest mistakes** with their time,
  e.g. `0:42 Frost Strike instead of Obliterate (ready)`.

The last 10 fights are kept per character: `/rh review` opens the latest, the arrows in the
title bar browse them, and `/rh review 3` opens a specific one.

## AoE detection

With several enemies, the status line shows how many carry your diseases, e.g. `2/4 DIS`
(yellow while some lack them). The AoE rotations only suggest Pestilence when an enemy is missing
them. Other enemies' diseases are tracked from the combat log.

3.3.5 doesn't let addons read nameplates as units, so enemies are counted from the combat log.
An enemy counts while you or your pet hit it (disease ticks included), it hits you, or you put a
debuff on it. It stops counting 6 seconds after the last of these, or when it dies. With 3 or more
enemies the AoE priority takes over. `/rh aoe` can force single target or AoE instead.

## Editing the rotation

`/rh apl` opens the editor. The rotation is a SimC-style action priority list; see
[docs/APL.md](docs/APL.md) for the full reference. A short example:

```
actions=icy_touch,if=dot.frost_fever.remains<2
actions+=/obliterate
actions+=/frost_strike,if=buff.killing_machine.up|runic_power.deficit<25
```

- The editor has line numbers and syntax colors, and checks the rotation shortly after you stop
  typing: the line under it says "Compiles" or shows the first error, and lines with errors are
  marked red.
- Press **Accept** to save. It's saved only if it compiles; otherwise the previous rotation stays
  active.
- **Names** opens a searchable list of everything you can use (abilities, buffs, debuffs,
  cooldowns, runes, your talents and glyphs); click one to insert it at the cursor.
- **Export** gives a one-line `RH1:` string to copy; **Import** reads one (or plain rotation
  text) back into the editor. **Share** sends the rotation to your party, raid or a player with
  RotationHelper; they're asked before it opens, and it's never saved without their Accept.
- **Revert to default** discards your version. Custom rotations are stored per profile.

## Simulating a rotation

The **Simulate** button on the Rotation tab (or `/rh sim`) plays the rotation for 5 fights of
5 minutes against a target that never dies, with your talents and glyphs and random Killing
Machine and Rime procs. It reports time spent casting, rune pairs sitting full, runic power
capped and lost, disease uptime, procs used and wasted, and casts per minute. Use it to compare
versions of a rotation, e.g. before and after moving a line up.

Once you've fought a bit, it also estimates **damage per minute** from your own damage log:
`/rh damage` shows what each ability hits for with your gear (per cast, per rune, per runic
power, crit rate, share of your damage; diseases per tick). The log is kept per character; reset
it after a big gear change (`/rh damage reset` or the General tab). Abilities cast fewer than 5
times aren't used yet and are listed as "no data".

For developers, `lua tests/sim.lua frost [--runs N] [--seconds N] [--enemies N] default my.apl`
compares rotations side by side outside the game.

## Something looks wrong?

Run `/rh snapshot` at the moment it happens. It prints runes, runic power, buffs, debuffs,
cooldowns, talents, the predicted queue, and one line per rotation entry explaining why it
was or wasn't chosen. That's usually enough to see whether the addon misread the game
or the rotation asks for the wrong thing.

## Development

The addon is plain Lua 5.1, with Ace3 r960 (the 3.3.5 release) bundled in `RotationHelper/Libs`.

Tests run outside the game against a mocked WoW API, with the real Ace3 libraries loaded:

```
lua tests/run.lua
```

(Lua 5.1 is needed, e.g. `winget install -e --id rjpcomputing.luaforwindows`.)

To add a spec or class, see [docs/ADDING_A_SPEC.md](docs/ADDING_A_SPEC.md). Planned specs
and the engine work they need are tracked in [docs/SPECS.md](docs/SPECS.md), and planned
enhancements (fight review, simulator, latency compensation, ...) in [docs/ROADMAP.md](docs/ROADMAP.md).
