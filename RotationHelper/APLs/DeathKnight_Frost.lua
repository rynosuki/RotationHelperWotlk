local ADDON_NAME, ns = ...

-- Default Frost Death Knight priority for 3.3.5a (dual-wield or 2H).
--
-- How the engine reads this:
--   - The action usable *soonest* is recommended; ties go to the higher line.
--   - A condition is checked at the moment its ability becomes usable.
--   - runes.frost / runes.unholy / runes.blood count only runes of that exact
--     type that are ready; runes.death counts death runes. Rune and runic
--     power costs are checked automatically (death runes pay for anything).
ns.RegisterAPL("DEATHKNIGHT", "frost", "Frost (default)", [[
## Out of combat
# With a pull timer (DBM/BigWigs or /rh pull): Army of the Dead about 10s out, a potion at the pull.
actions.precombat=army_of_the_dead,if=toggle.cooldowns&pull.active&pull.remains<=10&pull.remains>=5
actions.precombat+=/potion,if=toggle.cooldowns&pull.active&pull.remains<=1.5
actions.precombat+=/horn_of_winter,if=!buff.horn_of_winter.up

## Main priority
# Short cooldowns follow the CD toggle but are used on trash too; the big ones
# are for bosses only by default.
actions=call_action_list,name=short_cooldowns,if=toggle.short_cooldowns
actions+=/call_action_list,name=cooldowns,if=toggle.cooldowns
actions+=/run_action_list,name=aoe,if=active_enemies>=3
# With Glyph of Disease, Pestilence refreshes both diseases for one blood rune.
actions+=/pestilence,if=glyph.disease.enabled&dot.frost_fever.up&dot.blood_plague.up&(dot.frost_fever.remains<4|dot.blood_plague.remains<4)
actions+=/icy_touch,if=dot.frost_fever.remains<2
actions+=/plague_strike,if=dot.blood_plague.remains<2
# Don't let a full frost/unholy pair sit capped.
actions+=/obliterate,if=runes.frost=2|runes.unholy=2|runes.death>=2
actions+=/frost_strike,if=buff.killing_machine.up|runic_power.deficit<25
actions+=/obliterate
# Blood runes turn into death runes (Blood of the North); keep death runes for Obliterate.
actions+=/blood_strike,if=runes.blood>=1
actions+=/frost_strike
actions+=/howling_blast,if=buff.freezing_fog.up
# Horn only to restore the buff. When nothing is ready, the display shows the
# next ability counting down instead of a filler.
actions+=/horn_of_winter,if=!buff.horn_of_winter.up

## Short cooldowns (1-2 minutes, used on trash too)
actions.short_cooldowns=blood_tap,if=talent.unbreakable_armor.enabled&cooldown.unbreakable_armor.ready
actions.short_cooldowns+=/unbreakable_armor
# Deathchill guarantees a crit: save it for an Obliterate that's castable now.
actions.short_cooldowns+=/deathchill,if=runes.frost+runes.death>=1&runes.unholy+runes.death>=1&runes.frost+runes.unholy+runes.death>=2

## Big cooldowns (the CD toggle)
# 5 minute cooldown: don't spend it on something that's about to die.
actions.cooldowns=empower_rune_weapon,if=runes.total=0&runes.total.time_to_1>2&target.time_to_die>10
# Racials and trinkets with Unbreakable Armor (or when it's far away), a potion with Bloodlust or at the end.
actions.cooldowns+=/blood_fury,if=buff.unbreakable_armor.up|cooldown.unbreakable_armor.remains>20|!talent.unbreakable_armor.enabled
actions.cooldowns+=/berserking,if=buff.unbreakable_armor.up|cooldown.unbreakable_armor.remains>20|!talent.unbreakable_armor.enabled
actions.cooldowns+=/trinket1
actions.cooldowns+=/trinket2
actions.cooldowns+=/potion,if=buff.bloodlust.up|target.time_to_die<30
actions.cooldowns+=/arcane_torrent,if=runic_power.deficit>=20

## 3+ targets
actions.aoe=icy_touch,if=!dot.frost_fever.up
actions.aoe+=/plague_strike,if=!dot.blood_plague.up
# Spread the diseases when an enemy lacks them (tracked from the combat log).
actions.aoe+=/pestilence,if=dot.frost_fever.up&dot.blood_plague.up&diseased_enemies<active_enemies,line_cd=10
actions.aoe+=/howling_blast
actions.aoe+=/death_and_decay
actions.aoe+=/frost_strike,if=buff.killing_machine.up|runic_power.deficit<25
actions.aoe+=/blood_boil,if=runes.blood>=1
actions.aoe+=/frost_strike
actions.aoe+=/horn_of_winter,if=!buff.horn_of_winter.up
]])
