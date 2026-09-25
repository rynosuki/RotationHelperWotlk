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
actions.precombat=horn_of_winter,if=!buff.horn_of_winter.up

## Main priority
actions=call_action_list,name=cooldowns,if=toggle.cooldowns
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
actions+=/horn_of_winter

## Off-GCD cooldowns
actions.cooldowns=blood_tap,if=talent.unbreakable_armor.enabled&cooldown.unbreakable_armor.ready
actions.cooldowns+=/unbreakable_armor
# Deathchill guarantees a crit: save it for an Obliterate that's castable now.
actions.cooldowns+=/deathchill,if=runes.frost+runes.death>=1&runes.unholy+runes.death>=1&runes.frost+runes.unholy+runes.death>=2
actions.cooldowns+=/empower_rune_weapon,if=runes.total=0&runes.total.time_to_1>2

## 3+ targets
actions.aoe=icy_touch,if=!dot.frost_fever.up
actions.aoe+=/plague_strike,if=!dot.blood_plague.up
actions.aoe+=/pestilence,if=dot.frost_fever.up&dot.blood_plague.up,line_cd=20
actions.aoe+=/howling_blast
actions.aoe+=/death_and_decay
actions.aoe+=/frost_strike,if=buff.killing_machine.up|runic_power.deficit<25
actions.aoe+=/blood_boil,if=runes.blood>=1
actions.aoe+=/frost_strike
actions.aoe+=/horn_of_winter
]])
