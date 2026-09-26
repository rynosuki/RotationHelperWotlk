# Spec roadmap

Every WotLK 3.3.5a DPS spec, what it needs from the engine, and a suggested order.
Enhancements planned before more specs (fight review, simulator, ...) are in [ROADMAP.md](ROADMAP.md).
Tick a spec off when it has a default APL, scenario tests, and has been checked in game.

How to add one: [ADDING_A_SPEC.md](ADDING_A_SPEC.md).

## Engine features the specs need

Most specs need something the engine doesn't do yet. Each feature is built once and shared.

| # | Feature | Needed by | Notes |
|---|---|---|---|
| E1 | **Mana costs** (done) | most non-DK specs | `mana = <% of base mana>` in class data; the client's real cost is used in game. No regen in the prediction (abilities can add some, e.g. Divine Plea); the simulator has `simPower.regen`. |
| E2 | **Cast times and channels** (done: `castTime`/`channel`, haste from `hasteProbe`, instants only while moving; channels aren't clipped) | all casters | A cast delays the next action by its cast time (hasted), not the GCD. Channels (Mind Flay, Arcane Missiles) likewise. |
| E3 | **Rage** (done) | Warrior | Costs like runic power; rage income can't be predicted, so no regen. |
| E4 | **"On next swing" abilities** (done) | Warrior | Heroic Strike and Cleave are off-GCD queued attacks; recommend them alongside the GCD ability. |
| E5 | **Energy regen + combo points** (done: `energyRegen`, `energyBoost`, `comboGain` / `finisher`) | Rogue, Cat | Energy comes back at 10/s: `ReadyAt` must predict when there's enough. Finishers use combo points. |
| E6 | **Buff stacks as a resource** (done: `buff.X.stack`, stacking procs in the simulator) | Enhancement, Arcane, others | Maelstrom Weapon (5 stacks = instant cast), Arcane Blast stacks, Sudden Death, etc. |
| E7 | **DoT refresh rules** (done with `action.X.cast_time`; tick-aware clipping not modelled) | Affliction, Shadow, Balance, Feral | Refresh at the right time without clipping the last tick; haste-dependent tick times. |
| E8 | **Pets, totems, forms** (totems and stances done; pets partly: `pet.alive`) | Hunter, Warlock, Shaman, Druid | Pet active/abilities, totems up, current form (`GetShapeshiftForm()`). |
| E9 | **Auto Shot timing** | Hunter | Steady Shot shouldn't clip Auto Shot; needs the ranged swing timer. |

## Specs

Legend: role · power · engine features needed · notes.

### Death Knight — runes + runic power (engine complete)

- [x] **Frost** (DPS) · done
- [ ] **Unholy** (DPS) · implemented in 1.1.0, waiting on an in-game check · Scourge Strike, Desolation, Ghoul Frenzy, Summon Gargoyle, Bone Shield.
- [ ] **Blood** (DPS or tank) · implemented in 1.14.0, waiting on an in-game check · Heart Strike, Death Strike, Dancing Rune Weapon, Hysteria; in Frost Presence a tank list with Rune Strike (new: `reactive` abilities), Rune Tap and Vampiric Blood by `health.pct`.

### Paladin — mana

- [ ] **Retribution** (DPS) · E1 · implemented in 1.16.0 (mana costs, variants for Judgement, `target.type.X`, group auras for seals), waiting on an in-game check · Famous "first come, first served" priority (Judgement, Divine Storm, Crusader Strike, Consecration, Exorcism with Art of War, Hammer of Wrath). The best first non-DK spec: only needs mana costs.

### Warrior — rage

- [ ] **Fury** (DPS) · E3, E4 · implemented in 1.17.0 (rage income learned in combat, `nextSwing` abilities, stances), waiting on an in-game check · Bloodthirst, Whirlwind, Slam with Bloodsurge, Heroic Strike rage dumping.
- [ ] **Arms** (DPS) · E3, E4 · implemented in 1.18.0 (stance requirements, `usableWith` for Taste for Blood, per-spec review debuffs), waiting on an in-game check · Mortal Strike, Overpower, Execute and Sudden Death, Rend upkeep.

### Shaman — mana

- [ ] **Enhancement** (DPS) · E1, E6, E8 · implemented in 1.19.0 (totems, shared shock cooldown, stacking procs in the simulator, imbue checklist), waiting on an in-game check · Stormstrike, Lava Lash, shocks, Maelstrom Weapon at 5 stacks, Magma Totem, Shamanistic Rage.
- [ ] **Elemental** (DPS) · E1, E2, E7 · implemented in 1.25.0, waiting on an in-game check · Flame Shock upkeep, Lava Burst, Chain Lightning, Lightning Bolt, Thunderstorm.

### Rogue — energy + combo points

- [ ] **Combat** (DPS) · E5 · implemented in 1.27.0, waiting on an in-game check · Slice and Dice upkeep, Rupture, Sinister Strike, Killing Spree, Adrenaline Rush.
- [ ] **Assassination** (DPS) · E5 · Mutilate, Envenom with Hunger for Blood and SnD upkeep.
- [ ] **Subtlety** (DPS) · E5 · Hemorrhage and Honor Among Thieves; rarely played for PvE.

### Druid

- [ ] **Feral, cat** (DPS) · E5, E7, E8 · Savage Roar, Rip, Rake, Mangle upkeep, Shred, Tiger's Fury, Berserk. The hardest melee rotation.
- [ ] **Balance** (DPS) · E1, E2, E7 · implemented in 1.26.0 (`last.X` for the last Eclipse, proc cooldowns in the simulator), waiting on an in-game check · Eclipse (Wrath/Starfire switching), Moonfire and Insect Swarm upkeep, Starfall.

### Hunter — mana (focus only arrives in Cataclysm)

- [ ] **Marksmanship** (DPS) · E1, E2, E9 · Serpent Sting, Chimera Shot, Aimed Shot, Steady Shot around Auto Shot.
- [ ] **Survival** (DPS) · E1, E2, E9 · Explosive Shot with Lock and Load, Black Arrow, Serpent Sting.
- [ ] **Beast Mastery** (DPS) · E1, E2, E8, E9 · Kill Command, Bestial Wrath, pet focus.

### Mage — mana

- [ ] **Fire** (DPS) · E1, E2, E6 · implemented in 1.21.0 (`instantWith` for Hot Streak, `castTimeFn`), waiting on an in-game check · Fireball, Hot Streak (instant Pyroblast), Living Bomb upkeep, Scorch debuff.
- [ ] **Arcane** (DPS) · E1, E2, E6 · implemented in 1.22.0 (state-dependent costs and cast times, debuffs on yourself), waiting on an in-game check · Arcane Blast stacking and mana management, Missile Barrage, Arcane Power.
- [ ] **Frost** (DPS) · E1, E2 · Frostbolt, Fingers of Frost, Brain Freeze; mostly PvP in WotLK.

### Warlock — mana

- [ ] **Affliction** (DPS) · E1, E2, E7 · implemented in 1.23.0, waiting on an in-game check · Haunt, Corruption, Unstable Affliction, Curse of Agony, Drain Soul execute.
- [ ] **Destruction** (DPS) · E1, E2, E7 · implemented in 1.24.0 (Backdraft charges via `fx.ConsumeStack`), waiting on an in-game check · Immolate, Conflagrate, Chaos Bolt, Incinerate, Backdraft.
- [ ] **Demonology** (DPS) · E1, E2, E7, E8 · Metamorphosis, Decimation (Soul Fire), Molten Core (Incinerate).

### Priest — mana

- [ ] **Shadow** (DPS) · E1, E2, E7 · implemented in 1.20.0, waiting on an in-game check · Vampiric Touch, Shadow Word: Pain, Devouring Plague upkeep, Mind Blast, Mind Flay filler, Shadowfiend.

## Suggested order

1. **Unholy DK** (done), **Blood DK** (done; needed reactive abilities and `health.pct`).
2. **E1 mana costs** (done) → **Retribution Paladin** (done).
3. **E3 + E4 rage** (done) → **Fury** (done), **Arms** (done).
4. **E6 stacks + E8 totems** (done) → **Enhancement Shaman** (done).
5. **E2 cast times + E7 DoTs** (done) → **Shadow Priest** (done), then the other casters (Fire Mage (done), Arcane Mage (done),
   Affliction (done)/Destruction (done) Warlock, Elemental (done), Balance (done)).
6. **E5 energy + combo points** (done) → **Combat** (done)/**Assassination Rogue**, then **Feral cat**.
7. **E9 Auto Shot timing** → **Hunters**.
8. Niche specs (Subtlety Rogue, Frost Mage).

## Out of scope for now: tanks and healers

The list covers DPS specs only, to start.

- **Tanks** (Protection Paladin, Protection Warrior, Feral bear) may come later. Blood Death
  Knight is the exception: its rotation already switches to a tank list in Frost Presence.
- **Healers** (Holy Paladin, Restoration Shaman, Restoration Druid, Discipline and Holy Priest)
  are out of scope. Healing depends on the raid's health, not on a priority of your own
  resources, so a "press this next" helper doesn't fit. Hekili doesn't support healers either.
