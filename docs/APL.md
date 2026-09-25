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
| `auto_attack`, `snapshot_stats`, `flask`, `food`, `potion`, ... | Accepted and ignored, so SimC exports load. |

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

In the in-game editor, WoW shows `|` as `||`. Both mean "or".

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
`deathchill`, `horn_of_winter`, `blood_presence`, `frost_presence`, `unholy_presence`,
`bloodlust` (also Heroism); debuffs `frost_fever`, `blood_plague`.

### Cooldowns

| Name | Value |
|---|---|
| `cooldown.NAME.ready` / `.up` | 1 if off cooldown (always 1 for abilities without one) |
| `cooldown.NAME.remains` | seconds until ready |
| `cooldown.NAME.duration` | the cooldown's length |

### Runes and runic power

| Name | Value |
|---|---|
| `runes.blood` / `.frost` / `.unholy` | ready runes of exactly that type (death runes not included) |
| `runes.death` | ready death runes |
| `runes.total` | all ready runes |
| `runes.TYPE.time_to_N` | seconds until N runes of that type are ready (N = 1-6) |
| `runic_power` | current runic power |
| `runic_power.deficit` / `.max` / `.pct` | missing, maximum, percent |

`rune.` works the same as `runes.`.

### Everything else

| Name | Value |
|---|---|
| `gcd` | GCD length (1.5, or 1.0 in Unholy Presence) |
| `gcd.remains` | seconds left on the current GCD |
| `time` | seconds since combat started |
| `active_enemies` | enemies counted (see AoE detection in the README) |
| `moving` | 1 while moving |
| `target.health.pct` | target health percent |
| `target.time_to_die` | estimated seconds until the target dies (3600 if unknown, e.g. training dummies) |
| `talent.NAME.enabled` / `.rank` | talent by name, e.g. `talent.blood_of_the_north.rank` |
| `glyph.NAME.enabled` | glyph by name without "Glyph of", e.g. `glyph.disease.enabled` |
| `toggle.cooldowns` | 1 when cooldowns are toggled on |
| `variable.NAME` | a variable set by a `variable` action (0 if unset) |

Talent and glyph names are the in-game names in lowercase, with spaces and punctuation replaced
by `_`. `/rh snapshot` lists your talents and glyphs in exactly this form.

### Abilities

Death Knight: `icy_touch`, `plague_strike`, `obliterate`, `frost_strike`, `howling_blast`,
`blood_strike`, `pestilence`, `blood_boil`, `death_and_decay`, `death_coil`, `death_strike`,
`horn_of_winter`, `blood_tap`, `unbreakable_armor`, `empower_rune_weapon`, `deathchill`,
`army_of_the_dead`, `raise_dead`, `mind_freeze`.

Abilities you don't have (talents you didn't take) are skipped automatically.
