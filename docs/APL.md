# Action priority lists (APLs)

RotationHelper rotations use the SimulationCraft APL format with a few 3.3.5-specific names.
The default Frost rotation, in [RotationHelper/APLs/DeathKnight_Frost.lua](../RotationHelper/APLs/DeathKnight_Frost.lua),
is a good worked example.

## How a recommendation is chosen

1. Out of combat, the `precombat` list runs first. The main list (`actions=`) needs a living,
   hostile target.
2. For every ability line, the addon works out **when** that ability could be used, from the GCD,
   its cooldown, runes (death runes pay for any type) and runic power. It then checks the line's
   `if=` condition **at that moment**. So `if=dot.frost_fever.remains<2` looks at the disease as it
   will be when the ability is actually castable.
3. The ability usable **soonest** is recommended. Between abilities usable at the same time, the
   higher line wins. Off-GCD abilities (Unbreakable Armor, Blood Tap, Empower Rune Weapon, Deathchill)
   can be recommended during the GCD.
4. For the queue icons, the addon simulates using that ability (spends its runes and runic power,
   starts its cooldown and the GCD, applies its debuff, uses up the procs it consumes, creates death
   runes) and runs the list again.

You don't need conditions for resources: an ability you can't afford is never recommended as
"ready now", and it's shown with a countdown when it's the next thing to become usable.

## Lines

```
# A comment
actions.precombat=horn_of_winter,if=!buff.horn_of_winter.up
actions=call_action_list,name=cooldowns,if=toggle.cooldowns
actions+=/obliterate,if=runes.frost=2|runes.unholy=2
actions+=/frost_strike/howling_blast
actions.cooldowns=unbreakable_armor
```

| Form | Meaning |
|---|---|
| `actions=...` | Starts (or replaces) the main list. |
| `actions+=/...` | Adds to the main list. |
| `actions.NAME=...` / `actions.NAME+=/...` | The same for the list called NAME. |
| `a/b/c` | Several actions on one line. |
| `# ...` | A comment. |

Each action is `name,option=value,option=value`.

| Option | Meaning |
|---|---|
| `if=EXPR` | Only use this line when EXPR is true. |
| `line_cd=SECONDS` | Skip this line for SECONDS after the ability was last used. |

## Special actions

| Action | Meaning |
|---|---|
| `call_action_list,name=X` | Run list X. If it recommends nothing, carry on below. |
| `run_action_list,name=X` | Run list X and stop here: nothing below is considered. |
| `variable,name=X,value=EXPR` | Set variable X; read it as `variable.X`. |
| `variable,name=X,op=OP,value=EXPR` | OP is `set`, `add`, `sub`, `mul`, `div`, `min`, `max` or `reset` (no value). |
| `variable,name=X,op=setif,condition=C,value=A,value_else=B` | X = C ? A : B. |
| `wait,sec=EXPR` | Nothing below this line may be recommended for EXPR seconds. Useful for pooling. |
| `use_item,slot=13` / `slot=14` | The same as `trinket1` / `trinket2`. Other slots are an error. |
| `auto_attack`, `snapshot_stats`, `flask`, `food`, `augmentation`, `use_items` | Accepted and ignored, so SimC exports load. |

## Expressions

Every value is a number; true is 1 and false is 0. So `buff.a.up+buff.b.up>=2` counts buffs.

| Operator | Meaning |
|---|---|
| `&` `\|` `^` `!` | and, or, xor, not (`&&` and `\|\|` also work) |
| `=` `!=` `<` `<=` `>` `>=` | comparisons (`==` also works) |
| `+` `-` `*` | arithmetic |
| `%` | **division** (`/` separates actions), divide by zero gives 0 |
| `%%` | modulo |
| `@` | absolute value |
| `( )` | grouping |

Precedence, loosest first: `|` `^` > `&` > comparisons > `+ -` > `* % %%` > unary `! - @`.

`||` works as "or" too.

## Names

### Auras

| Name | Value |
|---|---|
| `buff.NAME.up` / `.down` / `.react` | 1 if the buff is (not) on you |
| `buff.NAME.remains` | seconds left (0 if missing, 9999 if permanent) |
| `buff.NAME.stack` | stacks (0 if missing) |
| `dot.NAME.up` / `.ticking` / `.remains` / `.stack` | the same for your debuffs on the target |
| `debuff.NAME.*` | same as `dot.NAME.*` |

Death Knight auras: buffs `killing_machine`, `freezing_fog` (Rime), `unbreakable_armor`,
`deathchill`, `horn_of_winter`, `desolation`, `bone_shield`, `blood_presence`, `frost_presence`,
`unholy_presence`, `bloodlust` (also Heroism); debuffs `frost_fever`, `blood_plague`.

### Cooldowns

| Name | Value |
|---|---|
| `cooldown.NAME.ready` / `.up` | 1 if off cooldown (always 1 for abilities without one) |
| `cooldown.NAME.remains` | seconds until ready |
| `cooldown.NAME.duration` | the cooldown's length |
| `cooldown.NAME.ready_for` | seconds since it came off cooldown (0 while on cooldown). Use it to hold a cooldown for a burst window, but not forever. |

### Runes and runic power

| Name | Value |
|---|---|
| `runes.blood` / `.frost` / `.unholy` | ready runes of exactly that type (death runes not included) |
| `runes.death` | ready death runes |
| `runes.total` | all ready runes |
| `runes.TYPE.time_to_N` | seconds until N runes of that type are ready (N = 1-6) |
| `runic_power` | current runic power |
| `runic_power.deficit` / `.max` / `.pct` | missing, maximum, percent |
| `mana`, `mana.deficit` / `.max` / `.pct` | the same for mana users (Paladin) |
| `rage`, `rage.deficit` / `.max` | rage (Warrior), including the expected income up to the moment the condition is checked |
| `stance.battle` / `.defensive` / `.berserker` | 1 in that Warrior stance |
| `totem.fire.up` / `.remains` (also `earth`, `water`, `air`) | your totem of that element |
| `totem.NAME.up` / `.remains` | a specific totem, e.g. `totem.magma_totem.remains` |
| `action.NAME.cast_time` | the ability's cast or channel time with your spell haste (0 for instants) |
| `action.NAME.execute_time` | that, or the GCD if longer: how long using it keeps you busy |

`rune.` works the same as `runes.`.

### Everything else

| Name | Value |
|---|---|
| `gcd` | GCD length (1.5, or 1.0 in Unholy Presence) |
| `gcd.remains` | seconds left on the current GCD |
| `time` | seconds since combat started |
| `active_enemies` | enemies counted (see AoE detection in the README) |
| `active_dot.NAME` | enemies with that dot of yours, the target included (other enemies tracked from the combat log), e.g. `active_dot.frost_fever` |
| `diseased_enemies` | enemies with all of your spreadable diseases (Frost Fever and Blood Plague), the target included. `diseased_enemies<active_enemies` means Pestilence has someone to spread to. |
| `moving` | 1 while moving |
| `pet.alive` | 1 while your pet (ghoul) is out and alive |
| `target.health.pct` | target health percent |
| `health.pct` | your own health percent (for defensives like Rune Tap) |
| `target.type.NAME` | 1 if the target is that creature type, e.g. `target.type.undead`, `target.type.demon` |
| `target.time_to_die` | estimated seconds until the target dies (3600 if unknown, e.g. training dummies) |
| `talent.NAME.enabled` / `.rank` | talent by name, e.g. `talent.blood_of_the_north.rank` |
| `glyph.NAME.enabled` | glyph by name without "Glyph of", e.g. `glyph.disease.enabled` |
| `toggle.cooldowns` | 1 when cooldowns are toggled on and (by default) in a boss fight |
| `toggle.short_cooldowns` | 1 when the CD toggle is on, boss fight or not: for short cooldowns used on trash too |
| `toggle.consumables` | 1 when consumables may be used now: toggled on and (by default) in a boss fight. `potion` checks this by itself. |
| `pull.active` | 1 while a pull timer runs (DBM, BigWigs or `/rh pull N`), and for 2 seconds after it reaches 0 |
| `pull.remains` | seconds until the pull (0 without a timer) |
| `burst.active` | 1 while a burst buff is on you: Bloodlust/Heroism, Hyperspeed Acceleration, racials, Potion of Speed, common trinket procs, plus any added in the options |
| `burst.remains` | seconds left on the longest burst buff |
| `variable.NAME` | a variable set by a `variable` action (0 if unset) |

Talent and glyph names are the in-game names in lowercase, with spaces and punctuation replaced
by `_`. `/rh snapshot` lists your talents and glyphs in exactly this form.

### Abilities

Death Knight: `icy_touch`, `plague_strike`, `obliterate`, `frost_strike`, `howling_blast`,
`scourge_strike`, `blood_strike`, `pestilence`, `blood_boil`, `death_and_decay`, `death_coil`,
`death_strike`, `horn_of_winter`, `blood_tap`, `unbreakable_armor`, `empower_rune_weapon`,
`deathchill`, `ghoul_frenzy`, `summon_gargoyle`, `bone_shield`, `army_of_the_dead`, `raise_dead`,
`mind_freeze`, `heart_strike`, `rune_strike`, `dancing_rune_weapon`, `hysteria`, `rune_tap`,
`vampiric_blood`.

`rune_strike` is only considered while the game allows it (after you dodge or parry) and it isn't
already queued for your next swing.

Paladin: `crusader_strike`, `divine_storm`, `judgement` (Light, Wisdom or Justice, as chosen on the
General tab), `consecration`, `exorcism`, `hammer_of_wrath`, `holy_wrath`, `avenging_wrath`,
`divine_plea`, `seal_of_vengeance`, `seal_of_corruption`, `seal_of_command`,
`seal_of_righteousness`. `buff.seal.up` is 1 while any seal is up.

Warrior: `bloodthirst`, `whirlwind`, `slam` (use it with `buff.bloodsurge.up`), `execute`,
`heroic_strike`, `cleave`, `battle_shout`, `commanding_shout`, `bloodrage`, `berserker_rage`,
`death_wish`, `recklessness`, `pummel`, `victory_rush`, `mortal_strike`, `rend` (`dot.rend`),
`overpower` (after a dodge or with `buff.taste_for_blood`), `bladestorm`, `sweeping_strikes`.
Abilities that need a stance (Overpower: Battle; Whirlwind, Pummel, Recklessness: Berserker) are
skipped in the wrong one. Heroic Strike and Cleave are on the next
swing: they're off the GCD and not suggested again while one is queued.

Shaman: `stormstrike`, `lava_lash`, `earth_shock`, `flame_shock` (`dot.flame_shock`), `frost_shock`
(the shocks share a cooldown), `lightning_bolt` and `chain_lightning` (use them with
`buff.maelstrom_weapon.stack=5`), `fire_nova` (needs `totem.fire.up`), `magma_totem`,
`searing_totem`, `lightning_shield`, `feral_spirit`, `shamanistic_rage`, `wind_shear`.

Priest: `vampiric_touch`, `shadow_word_pain`, `devouring_plague` (all `dot.*`), `mind_blast`,
`mind_flay`, `mind_sear`, `shadow_word_death`, `shadowfiend`, `dispersion`, `shadowform`,
`inner_fire`, `vampiric_embrace`, `silence`. Abilities with a cast time aren't suggested while
you're moving, and the next ability waits for the cast or channel to finish.

Every class: `trinket1` / `trinket2` (the trinket in slot 13 / 14, only if its use effect helps
damage, unless changed under General > Trinkets),
`potion` (Potion of Speed, or Indestructible Potion, from your bags; once per combat),
`blood_fury`, `berserking`, `arcane_torrent` (only if your race has it). Lines for things you
don't have are skipped.

Abilities you don't have (talents you didn't take) are skipped automatically, and so are
abilities that need a pet (Ghoul Frenzy) while you have none.
