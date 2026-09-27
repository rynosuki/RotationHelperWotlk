# Enhancements roadmap

Improvements planned before more rotations are added (the spec list is in [SPECS.md](SPECS.md)).
The aim is optimal play rather than feature parity with Hekili:
- **react faster** (latency compensation, "press now" cue),
- **see mistakes** (waste warnings, fight review),
- **measure rotations** (a simulator, so new specs aren't tuned by feel),
- **fewer surprises** (interrupts, pre-pull checks, error protection).

Sizes: **S** under an hour, **M** a session, **L** several sessions. Tick an item when it has
offline tests and has been checked in game.

## Suggested order

1. Phase A's safety and reaction items: A5, A1, A2, A3, A4.
2. Phase B, the fight review.
3. Phase C, the simulator, **before adding more specs**.
4. Phases D, E and F, and the rest of Phase A.
5. Phase G last.

## Building blocks already in place

| Piece | Where |
|---|---|
| Real and virtual game state | `State:Reset()`, `State:Virtual()` in [Engine/State.lua](../RotationHelper/Engine/State.lua) |
| When an ability is usable, what using it does | `Abilities.ReadyAt`, `Abilities.Apply` in [Engine/Abilities.lua](../RotationHelper/Engine/Abilities.lua) |
| Decision trace | `Runner.Run(apl, state, ctx, list, trace)` in [APL/Runner.lua](../RotationHelper/APL/Runner.lua) |
| Recommendation and prediction | `Recommender:Evaluate`, `Recommender:Predict` in [Engine/Recommender.lua](../RotationHelper/Engine/Recommender.lua) |
| Update loop and timing | `RH:RegisterUpdater(fn, order)`, `RH.perf` in [Core.lua](../RotationHelper/Core.lua) |
| Icon buttons | `CreateButton` in [UI/Display.lua](../RotationHelper/UI/Display.lua) |
| Themed window and control styling | [UI/OptionsWindow.lua](../RotationHelper/UI/OptionsWindow.lua), [UI/Skin.lua](../RotationHelper/UI/Skin.lua) |
| Combat log handling | [Engine/Targets.lua](../RotationHelper/Engine/Targets.lua) |
| Chat diagnostics | `/rh snapshot` in [Debug.lua](../RotationHelper/Debug.lua) |
| Offline tests | [tests/](../tests) with the mocked WoW API in `tests/wowmock.lua` |

---

## Phase A — small wins

- [ ] **A1 Latency compensation** (S) — *implemented in 1.3.0, waiting on the in-game check*
  - *Play:* the 3.3.5 client queues a press made shortly before the GCD ends: the "lag tolerance"
    window, set under Interface > Combat > Custom Lag Tolerance, otherwise based on latency.
    Showing the next ability, with a "press now" flash, as soon as a press would be queued
    removes the wait-and-react gap.
  - *How:* `State:ApplyLookahead` ends the GCD and the current cast early by the lookahead.
    - The lookahead is the Custom Lag Tolerance CVar (`MaxSpellStartRecoveryOffset`) if enabled,
      otherwise the latency from `GetNetStats()`. A fixed value or "off" are the alternatives.
      It's capped at 400 ms.
    - Runes and cooldowns are *not* shifted: a press for a rune that isn't back yet is refused,
      not queued.
    - The main icon flashes when its ready time arrives. That's timed per frame, since the GCD
      ending fires no event.
  - *Check in game:* the icon changes and flashes slightly before the GCD swipe ends, and a press
    at the flash goes through. `/rh snapshot` shows the lookahead and where it came from.

- [ ] **A2 Waste warnings** (S) — *implemented in 1.4.0, waiting on the in-game check*
  - *Play:* a capped rune pair or capped runic power is lost damage. A warning while it's
    happening is more useful than a report afterwards.
  - *How:* new `Engine/Waste.lua` checks the real state:
    - a rune pair is capped when both runes of a slot pair (1-2, 3-4, 5-6, via `rune.base`) are ready,
    - runic power is at or above a threshold.

    It drives a pulsing border texture on the main button. Thresholds and an on/off switch go in
    the Display options.
  - *Check in game:* let runes sit on a dummy; the pulse starts about when the pair caps and
    stops when a rune is spent.

- [ ] **A3 Interrupt icon** (S–M) — *implemented in 1.4.0, waiting on the in-game check*
  - *Play:* a separate small icon appears only when the target is casting something interruptible.
    It never displaces the rotation.
  - *How:* `UI/Interrupt.lua`.
    - It's a separate button; the button creation in Display moves into a shared helper.
    - It shows while `UnitCastingInfo`/`UnitChannelInfo("target")` reports a cast with
      `notInterruptible` false (9th return in 3.3.5).
    - The ability comes from a new class data field `interrupt` (Death Knight: `mind_freeze`) and
      must be known.
    - Keybind text as on the main icons, and a cooldown swipe from `state.cooldowns`.
  - *Check in game:* the icon appears on an interruptible cast, not on a shielded one, and shows
    Mind Freeze's cooldown after use.

- [ ] **A4 Profile per talent spec** (S) — *implemented in 1.5.0, waiting on the in-game check*
  - *Play:* dual spec switches layout, toggles and custom rotations automatically.
  - *How:* on `ACTIVE_TALENT_GROUP_CHANGED`, switch the AceDB profile to
    `db.char.specProfiles[group]`, if set. Two dropdowns (primary and secondary talents) go on
    the Profiles tab.
  - *Check in game:* switching talents switches the profile; the Profiles tab shows the new one.

- [ ] **A5 Error protection** (S) — *implemented in 1.3.0, waiting on the in-game check*
  - *Play:* a bug should never leave you with a frozen display or chat spam mid-fight.
  - *How:*
    - `RunUpdaters` in Core calls each updater through `xpcall` with `debugstack`.
    - The last 20 unique errors are kept.
    - The display shows a red "!", and each new error prints one chat line.
    - `/rh errors` prints the list with stack traces.
  - *Check in game:* a deliberately broken custom rotation expression, or a forced error, shows
    the "!" while the other updaters keep running.

- [ ] **A6 Tooltip and clickable status chips** (S) — *implemented in 1.6.0, waiting on the in-game check*
  - *Play:* see *why* an ability is recommended without typing commands, and toggle cooldowns or
    AoE mode with the mouse.
  - *How:*
    - While Shift is held, the locked display accepts the mouse.
    - Hovering the main icon shows its rotation line and the condition that chose it. The
      Recommender keeps the last trace entry for the main pick.
    - The `CD` and AoE status text becomes two small buttons that toggle on click.
  - *Check in game:* Shift+hover shows the line; Shift+click toggles; without Shift, clicks pass
    through as before.

- [ ] **A7 Proc glow and sound** (S) — *implemented in 1.6.0, waiting on the in-game check*
  - *Play:* Killing Machine and Rime are the moments that matter in Frost; make them impossible
    to miss.
  - *How:* class data `procs = { "killing_machine", "freezing_fog" }`. When the main
    recommendation spends one (via its `consumes` or `freeWith`), the icon glows, with an
    optional sound.
  - *Check in game:* glow on the Frost Strike that uses Killing Machine and on the free Howling
    Blast, and no glow otherwise.

- [ ] **A8 Configurable colors** (S) — *implemented in 1.7.0, waiting on the in-game check*
  - *Play:* readable for everyone, including colour-blind players.
  - *How:*
    - The tints for out of range, missing resources, waste and threat move into
      `profile.display.colors`.
    - Colour pickers in the options, plus a skinner for AceGUI's ColorPicker.
    - A colour-blind friendly preset.
  - *Check in game:* changed colours apply immediately; the preset switches all of them.

- [ ] **A9 `/rh why <ability>`** (S) — *implemented in 1.7.0, waiting on the in-game check*
  - *Play:* a direct answer to "why isn't it telling me to press X?".
  - *How:* runs one evaluation with a trace and prints that ability's lines: whether its
    condition is true, when it's ready, and what it waits for (runes, cooldown, runic power,
    line_cd, a higher-priority action).
  - *Check in game:* `/rh why obliterate` while runes are down says it waits on runes, with the time.

- [ ] **A10 Hold indicator** (S) — *implemented in 1.7.0, waiting on the in-game check*
  - *Play:* a clear "wait" state instead of an icon that just sits there.
  - *How:* when the main wait is longer than a GCD, an hourglass overlays the icon, with a short
    reason taken from `limitedBy`, e.g. "runes 2.3s" or "cooldown".
  - *Check in game:* with all runes down and no runic power, the hourglass and reason appear.

- [ ] **A11 Out-of-range alternative** (S) — *implemented in 1.7.0, waiting on the in-game check*
  - *Play:* when you're pushed away or the boss moves, you get the best thing you *can* do from
    there (Icy Touch, Howling Blast, Death Coil).
  - *How:* when the main ability is out of range, the Runner runs once more with a context filter
    that rejects out-of-range abilities. The result appears as a small secondary icon.
  - *Check in game:* step out of melee; a ranged option appears beside the red main icon.

- [ ] **A12 Threat warning** (S) — *implemented in 1.7.0, waiting on the in-game check*
  - *Play:* avoid pulling aggro in pugs.
  - *How:* `UnitDetailedThreatSituation("player", "target")`: when the scaled percent reaches the
    setting (default 90), the display border turns orange.
  - *Check in game:* in a group, the border turns orange when close to the tank's threat.

- [ ] **A13 Minimap button** (S) — *implemented in 1.7.0, waiting on the in-game check*
  - *Play:* quick access without slash commands.
  - *How:* our own small button, with no library. Left click opens the options, right click
    toggles cooldowns, and it can be dragged around the minimap. Its position is stored in the
    profile.
  - *Check in game:* clicks work; the position survives `/reload`.

## Phase B — Fight review (M–L)

- [ ] **B1 Recording** — *implemented in 1.8.0, waiting on the in-game check*
  - *Play:* the addon tells you how well you played, not only what to press.
  - *How:* `Engine/Review.lua`, an updater that runs after the Recommender. For each fight it
    records:
    - active time,
    - GCD idle time (GCD free, not casting, and the main wait is 0),
    - rune-capped time per pair, and time with runic power at the cap,
    - disease uptime on the target,
    - time that major cooldowns were ready but unused (new class data list `majorCooldowns`),
    - recommendation adherence: on `UNIT_SPELLCAST_SUCCEEDED`, the cast is compared with the
      first two icons shown at that moment. Mismatches are stored with the combat time.
- [ ] **B2 Shared themed window** — *implemented in 1.8.0*
  - *How:* the window builder in `UI/OptionsWindow.lua` (title bar, close, resize grip, Escape)
    moves to `UI/Window.lua`, so the options and the review share it.
- [ ] **B3 Review window** — *implemented in 1.8.0, waiting on the in-game check*
  - *How:* `UI/Review.lua` shows:
    - a summary with colour-coded grades per metric,
    - the three biggest mistakes, e.g. "0:42 Plague Strike instead of Obliterate".

    It opens after fights longer than a set time (default 20s; can be turned off for trash).
    `/rh review` reopens the last one, and the last 10 summaries are kept in `db.char`.
- *Check in game:* after a dummy fight where you ignore the icons on purpose, the review shows
  low adherence and names the moments.

## Phase C — Rotation checker / simulator (M–L)

- [ ] **C1 Simulation loop** — *implemented in 1.9.0*
  - *Play:* compare rotations with numbers before trusting them in raids. This gets built before
    more specs are added.
  - *How:* `Engine/Sim.lua`.
    - It loops `Recommender:Evaluate` and `Abilities.Apply` on a virtual state, moving time
      forward to each pick.
    - The target never dies, and the number of enemies is a parameter.
- [ ] **C2 Random procs** — *implemented in 1.9.0*
  - *How:* class data `simProcs`.
    - Rime: on Obliterate, 5% per rank.
    - Killing Machine: a chance per second from its rank.

    A seeded random number generator makes runs repeatable.
- [ ] **C3 Metrics** (there's no damage model, so these are proxies) — *implemented in 1.9.0*
  - GCD usage %
  - rune waste seconds
  - runic power lost at the cap
  - casts per ability per minute
  - disease uptime
  - proc usage
- [ ] **C4 Offline tool** — *implemented in 1.9.0*
  - `lua tests/sim.lua <spec> [apl file] [seconds] [runs]` prints the metrics, so two
    rotations can be compared side by side.
- [ ] **C5 In-game button** — *implemented in 1.9.0, waiting on the in-game check*
  - A "Simulate" button on the Rotation tab runs a short simulation and shows the results under
    the editor.
- *Check:* the offline default rotations show realistic GCD usage and disease uptime near 100%.
  A deliberately bad rotation scores clearly worse.

## Phase D — Rotation editor (M)

- [ ] **D1 Custom editor control** — *implemented in 1.10.0, waiting on the in-game check*
  - The Rotation tab's text box becomes our own AceGUI widget (registered with AceGUI and used
    through `dialogControl`), which makes D2–D5 possible.
- [ ] **D2 Validation while typing** — *implemented in 1.10.0, waiting on the in-game check*
  - Checked shortly after you stop typing (debounced), with line numbers and the line that has
    the error highlighted.
- [ ] **D3 Name picker** — *implemented in 1.10.0, waiting on the in-game check*
  - A searchable list of abilities, auras, talents, glyphs and expression names (from
    `Engine/Expressions.lua`) that inserts at the cursor.
- [ ] **D4 Import/export and sharing** — *implemented in 1.10.0, waiting on the in-game check*
  - Import/export strings: `RH1:` plus the text.
  - Sending to party, raid or a whisper with `SendAddonMessage`, in 250-byte chunks. The
    receiver confirms before anything is saved.
- [ ] **D5 Syntax colouring** — *implemented in 1.10.0, waiting on the in-game check*
  - Colour codes inside the edit box, stripped again when the text is read, with the cursor
    position kept.
  - The riskiest part, so it's done last.
- *Check in game:* typing a typo shows the error within a second; a shared rotation arrives and
  asks for confirmation.

## Phase E — Pre-pull, items and burst (M)

- [ ] **E1 Pre-pull checklist** — *implemented in 1.11.0, waiting on the in-game check*
  - Shown under the icons out of combat with a boss or elite targeted ("Missing: Flask, Food").
    It checks:
    - a flask or elixir and Well Fed (matched by buff name, so every flask and food counts),
    - the wrong presence for the spec (a setting per spec; Blood Presence by default),
    - no ghoul for Unholy,
    - Horn of Winter missing (a shaman's Strength of Earth counts).
- [ ] **E2 Pull timer** — *implemented in 1.11.0, waiting on the in-game check*
  - Any addon message whose prefix contains "DBM" or "BigWigs" and whose text mentions "pull"
    with a number (≤ 60) starts it; `/rh pull N` starts one locally. 0 cancels, combat ends it.
    The exact messages of Whitemane's DBM/BigWigs versions still need checking in game.
  - `pull.active` and `pull.remains` for precombat lines. The default rotations use Army of the
    Dead between 10 and 5 seconds out and a potion at 1.5 seconds.
- [ ] **E3 Trinkets, racials, potions** — *implemented in 1.11.0, waiting on the in-game check*
  - `Classes/Shared.lua` adds abilities every class gets: `trinket1` / `trinket2` (slots 13/14,
    only with a use effect), `potion` (Potion of Speed, else Indestructible Potion, from the
    bags, once per combat), `blood_fury`, `berserking`, `arcane_torrent`.
  - `Engine/Items.lua` keeps item names, icons and availability current; cooldowns come from
    `GetInventoryItemCooldown` / `GetItemCooldown`. `use_item,slot=13/14` compiles to
    `trinket1` / `trinket2`, so no new Runner action kind was needed.
- [ ] **E4 Burst window** — *implemented in 1.11.0, waiting on the in-game check*
  - Built-in buff names (Bloodlust/Heroism, Hyperspeed Acceleration, racials, Speed, common
    trinket procs) plus extra names or spell IDs from the options give `burst.active` and
    `burst.remains`.
  - `cooldown.NAME.ready_for` (seconds since a cooldown came back) caps the hold: Summon
    Gargoyle waits for a burst, but at most 15 seconds.
- *Check in game:* with a pull timer running, Army of the Dead is suggested at about −10s. With a
  trinket equipped, it appears when it's off cooldown. The checklist shows on a boss dummy.

## Phase F — Display extras (S–M)

- [ ] **F1 Predicted rune bar** — *implemented in 1.12.0, waiting on the in-game check*
  - Above the icons (`UI/DisplayExtras.lua`): the six runes colored by type, dim and partly
    filled with seconds left while recharging.
  - A strip under each rune shows it after the queued abilities (`Recommender.predictedRunes`,
    from the virtual state): its type then (e.g. blood becoming death), dimmed if the queue
    spends it.
- [ ] **F2 Cooldown strip** — *implemented in 1.12.0, waiting on the in-game check*
  - The class's `majorCooldowns` plus trinkets, when known: swipe, grey and time left while on
    cooldown.
- [ ] **F3 Timeline mode** — *implemented in 1.12.0, waiting on the in-game check*
  - Off by default. Queued icons are placed by the time they're usable; the scale makes one GCD
    one icon plus spacing, so waits show as gaps and icons never overlap (off-GCD cooldowns go
    side by side). Time under each icon, an axis with a tick per second.
- *Check in game:* the rune bar matches the default rune frame; the timeline spacing matches
  the queue's waits.

## Phase G — Experimental (L)

- [ ] **G1 Tracking diseases on several targets** — *implemented in 1.13.0, waiting on the in-game check*
  - `Engine/Dots.lua`: which enemies carry our `spreadDots` (applied/refreshed/ticking until
    removed, dead, or 6s without a tick), limited to enemies Targets still counts.
  - `active_dot.X` and `diseased_enemies`; Pestilence spreads them in the prediction and the
    simulator. The AoE lists only Pestilence when `diseased_enemies<active_enemies`.
  - `2/4 DIS` on the status line with several enemies.
- [ ] **G2 Learning from the combat log** — *implemented in 1.13.0, waiting on the in-game check*
  - `Engine/DamageLog.lua`: damage per cast / rune / runic power, crits, dot ticks and melee,
    per character. `/rh damage` prints it.
  - The simulator estimates damage per minute from it, so rotations can be compared by damage.
  - Not done: suggesting thresholds automatically. The numbers are there to compare by hand
    (e.g. damage per rune of Obliterate vs Blood Strike); a sound suggestion needs a damage model
    that the log alone doesn't give.

## Phase H — Every class, reports, tuning, smarter engine

- [x] **H1 Make it work for everyone** — *1.38.0*
  - Waste warnings for energy and rage as well as runic power (runes only for Death Knights);
    old `runicPower` / `rpDeficit` settings carry over.
  - Fight review: "<power> at the cap" per class, time below 10% mana for mana users, and how many
    procs were used; rows that don't apply are hidden (old reviews stay readable).
  - Rotation help text uses the class's own power, abilities and auras.
- [x] **H2 Bug reports and in-game testing** — *1.39.0*
  - `/rh report` (and a General tab button): version, class, spec, rotation (with the text if
    custom), settings, the `/rh snapshot`, recent errors and the last review, in a window to copy.
  - GitHub issue template asking for it; [TESTING.md](TESTING.md) lists what to check per spec.
- [x] **H3 Easier tuning without the editor** — *1.40.0*
  - Rotations declare settings (`ns.RegisterAPL(..., options)`), read as `option.NAME` /
    `option.NAME.VALUE`, checked when compiling, shown on the Rotation tab with a reset button,
    listed by Names and in `/rh report`.
  - Settings in the default rotations: Heroic Strike / Cleave rage, Arcane Blast mana %, the
    warlock curse, Envenom combo points, not behind the target (Feral, Subtlety), Blood tank
    health %, Gargoyle wait, hunter aspect mana %. The defaults simulate the same as before.
- [ ] **H4 More rotation smarts** — *planned for 1.41.0*: clipping channels, energy / rage pooling
  (`energy.time_to_N`), Backdraft shortening the GCD, multi-DoT hints.

## How items are verified

Every item follows the same routine as the milestones so far:
1. Offline tests in a new or existing `tests/test_*.lua` (the mock is extended when needed), and
   `lua tests/run.lua` passes.
2. The in-game check listed with the item.
3. The item is ticked here in the same commit.
