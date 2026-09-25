# RotationHelper

A Hekili-style rotation helper for **World of Warcraft 3.3.5a** (WotLK), tested on Whitemane.
It shows the ability to press next, plus a prediction of the few after it, based on a
priority list you can read and edit in game.

Supported so far: **Frost** and **Unholy Death Knight**. Blood can get a rotation by writing one
in the in-game editor. Other classes load but stay idle. See [docs/SPECS.md](docs/SPECS.md) for
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
| Blue icon | Waiting on runes. |
| Red icon | Your target is out of range for it. |
| Text in the corner | The key the ability is bound to. |
| `CD` under the big icon | Green: cooldowns are recommended. Red: they're not. |
| `ST` / `AOE` / a number under the big icon | The AoE mode is forced to single target / AoE, or (auto mode) how many enemies are counted. |

Procs like Killing Machine and Rime are random, so the prediction never assumes them. The icons
update as soon as one happens.

## Commands

| Command | What it does |
|---|---|
| `/rh` | Open the options panel (also under Interface > AddOns). |
| `/rh apl` | Open the rotation editor. |
| `/rh lock` | Lock or unlock the display. |
| `/rh cd` | Toggle cooldown recommendations. |
| `/rh aoe` | Cycle the AoE mode: auto > single > aoe. |
| `/rh pause` | Pause or resume. |
| `/rh test` | Show or hide sample icons. |
| `/rh scale <0.5-3>` | Display scale. |
| `/rh icons <1-5>` | How many icons to show. |
| `/rh snapshot` | Print everything the addon reads from the game, its prediction and why. |
| `/rh perf` | Show what the addon costs in CPU and memory. `/rh perf reset` starts over. |
| `/rh errors` | Show recorded addon errors (a red "!" next to the icons means there are new ones). `/rh errors clear` empties the list. |
| `/rh status` | Print the current settings. |
| `/rh help` | List the commands. |

Toggles can also be bound to keys: Escape > Key Bindings > RotationHelper.

## AoE detection

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
actions+=/frost_strike,if=buff.killing_machine.up||runic_power.deficit<25
```

- Press **Accept** to save. It's saved only if it compiles. Otherwise the errors are listed
  with line and column, and the previous rotation stays active.
- WoW edit boxes show `|` as `||`. Type `||` for "or".
- **Revert to default** discards your version. Custom rotations are stored per profile.

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
