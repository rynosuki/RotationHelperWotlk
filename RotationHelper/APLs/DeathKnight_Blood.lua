local ADDON_NAME, ns = ...

-- Default Blood Death Knight priority for 3.3.5a, DPS and tanking.
--
-- Frost Presence means tanking: the tank list takes over. Otherwise the
-- classic Blood DPS rotation: keep both diseases up, Death Strike with
-- frost/unholy pairs, Heart Strike with blood (and death) runes, Death
-- Coil with the runic power, Dancing Rune Weapon on cooldown.
ns.RegisterAPL("DEATHKNIGHT", "blood", "Blood (default)", [[
## Out of combat
# With a pull timer (DBM/BigWigs or /rh pull): Army of the Dead about 10s out, a potion at the pull.
actions.precombat=army_of_the_dead,if=toggle.cooldowns&pull.active&pull.remains<=10&pull.remains>=5&!buff.frost_presence.up
actions.precombat+=/potion,if=toggle.cooldowns&pull.active&pull.remains<=1.5
actions.precombat+=/horn_of_winter,if=!buff.horn_of_winter.up

## Main priority (DPS)
actions=run_action_list,name=tank,if=buff.frost_presence.up
actions+=/call_action_list,name=cooldowns,if=toggle.cooldowns
actions+=/run_action_list,name=aoe,if=active_enemies>=3
# With Glyph of Disease, Pestilence refreshes both diseases for one blood rune.
actions+=/pestilence,if=glyph.disease.enabled&dot.frost_fever.up&dot.blood_plague.up&(dot.frost_fever.remains<4|dot.blood_plague.remains<4)
actions+=/icy_touch,if=dot.frost_fever.remains<2
actions+=/plague_strike,if=dot.blood_plague.remains<2
actions+=/death_coil,if=runic_power.deficit<10
# Don't let a full rune pair sit capped.
actions+=/death_strike,if=runes.frost=2|runes.unholy=2
actions+=/heart_strike,if=runes.blood=2
actions+=/death_strike
actions+=/heart_strike
actions+=/death_coil
actions+=/horn_of_winter,if=!buff.horn_of_winter.up

## Cooldowns (DPS)
actions.cooldowns=dancing_rune_weapon
# Hysteria on yourself; in a raid you may prefer to give it to another melee player.
actions.cooldowns+=/hysteria
actions.cooldowns+=/empower_rune_weapon,if=runes.total=0&runes.total.time_to_1>2&target.time_to_die>10
actions.cooldowns+=/blood_fury,if=buff.hysteria.up|cooldown.hysteria.remains>30|!talent.hysteria.enabled
actions.cooldowns+=/berserking,if=buff.hysteria.up|cooldown.hysteria.remains>30|!talent.hysteria.enabled
actions.cooldowns+=/trinket1
actions.cooldowns+=/trinket2
actions.cooldowns+=/potion,if=buff.bloodlust.up|target.time_to_die<30
actions.cooldowns+=/arcane_torrent,if=runic_power.deficit>=20

## 3+ targets (DPS)
actions.aoe=icy_touch,if=!dot.frost_fever.up
actions.aoe+=/plague_strike,if=!dot.blood_plague.up
# Spread the diseases when an enemy lacks them (tracked from the combat log).
actions.aoe+=/pestilence,if=dot.frost_fever.up&dot.blood_plague.up&diseased_enemies<active_enemies,line_cd=10
actions.aoe+=/death_and_decay
actions.aoe+=/blood_boil,if=active_enemies>=4
actions.aoe+=/heart_strike
actions.aoe+=/death_strike
actions.aoe+=/death_coil,if=runic_power.deficit<20
actions.aoe+=/blood_boil
actions.aoe+=/death_coil
actions.aoe+=/horn_of_winter,if=!buff.horn_of_winter.up

## Tanking (Frost Presence)
# Rune Strike whenever a dodge or parry allows it: off the GCD, it hits with the next swing.
actions.tank=rune_strike
# Defensives when you're hurt.
actions.tank+=/rune_tap,if=health.pct<75
actions.tank+=/vampiric_blood,if=health.pct<45
actions.tank+=/dancing_rune_weapon,if=toggle.cooldowns
actions.tank+=/icy_touch,if=dot.frost_fever.remains<2
actions.tank+=/plague_strike,if=dot.blood_plague.remains<2
actions.tank+=/pestilence,if=active_enemies>=2&dot.frost_fever.up&dot.blood_plague.up&diseased_enemies<active_enemies,line_cd=10
actions.tank+=/pestilence,if=glyph.disease.enabled&dot.frost_fever.up&dot.blood_plague.up&(dot.frost_fever.remains<4|dot.blood_plague.remains<4)
actions.tank+=/death_and_decay,if=active_enemies>=3
actions.tank+=/blood_boil,if=active_enemies>=3
# Runic power is for Rune Strike: Death Coil only to avoid the cap.
actions.tank+=/death_coil,if=runic_power.deficit<25
# Death Strike heals; Heart Strike brings the threat.
actions.tank+=/death_strike
actions.tank+=/heart_strike
actions.tank+=/horn_of_winter,if=!buff.horn_of_winter.up
]])
