local ADDON_NAME, ns = ...

-- Default Unholy Death Knight priority for 3.3.5a.
--
-- Based on the common 3.3.5 PvE priority: keep both diseases up, keep
-- Desolation (Blood Strike) up, spend runes before runic power (Scourge
-- Strike, Blood Strike), Death Coil when the runes are down. With Reaping,
-- Blood Strike's blood runes come back as death runes for Scourge Strike.
-- Glyph of Disease is usually not taken for Unholy; the Pestilence refresh
-- line only matters if you have it.
ns.RegisterAPL("DEATHKNIGHT", "unholy", "Unholy (default)", [[
## Out of combat
actions.precombat=horn_of_winter,if=!buff.horn_of_winter.up
actions.precombat+=/raise_dead,if=!pet.alive
actions.precombat+=/bone_shield,if=!buff.bone_shield.up

## Main priority
actions=call_action_list,name=cooldowns,if=toggle.cooldowns
actions+=/run_action_list,name=aoe,if=active_enemies>=2
actions+=/pestilence,if=glyph.disease.enabled&dot.frost_fever.up&dot.blood_plague.up&(dot.frost_fever.remains<4|dot.blood_plague.remains<4)
actions+=/plague_strike,if=dot.blood_plague.remains<2
actions+=/icy_touch,if=dot.frost_fever.remains<2
# Don't waste runic power at the cap.
actions+=/death_coil,if=runic_power.deficit<10
# Desolation: +5% damage for 20s from Blood Strike.
actions+=/blood_strike,if=talent.desolation.enabled&buff.desolation.remains<2
# Ghoul Frenzy lasts 30s on the ghoul; recast it about every 25s.
actions+=/ghoul_frenzy,line_cd=25
actions+=/bone_shield,if=!buff.bone_shield.up
actions+=/scourge_strike
actions+=/blood_strike,if=runes.blood>=1
actions+=/death_coil
actions+=/horn_of_winter,if=!buff.horn_of_winter.up
actions+=/raise_dead,if=!pet.alive

## Cooldowns
# The Gargoyle keeps the attack power and haste you had when it was summoned.
actions.cooldowns=summon_gargoyle,if=dot.frost_fever.up&dot.blood_plague.up
# Blood Tap a death rune for Bone Shield when no unholy rune is ready.
actions.cooldowns+=/blood_tap,if=talent.bone_shield.enabled&!buff.bone_shield.up&cooldown.bone_shield.ready&runes.unholy+runes.death=0
actions.cooldowns+=/empower_rune_weapon,if=runes.total=0&runes.total.time_to_1>2&target.time_to_die>10

## 2+ targets
actions.aoe=plague_strike,if=!dot.blood_plague.up
actions.aoe+=/icy_touch,if=!dot.frost_fever.up
actions.aoe+=/pestilence,if=dot.frost_fever.up&dot.blood_plague.up,line_cd=20
actions.aoe+=/death_and_decay
actions.aoe+=/death_coil,if=runic_power.deficit<10
actions.aoe+=/blood_strike,if=talent.desolation.enabled&buff.desolation.remains<2
actions.aoe+=/scourge_strike
actions.aoe+=/blood_boil,if=runes.blood>=1
actions.aoe+=/death_coil
actions.aoe+=/horn_of_winter,if=!buff.horn_of_winter.up
]])
