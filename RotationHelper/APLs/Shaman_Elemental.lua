local ADDON_NAME, ns = ...

-- Default Elemental Shaman priority for 3.3.5a:
--   Totem of Wrath > Flame Shock (when missing) > Lava Burst (while Flame
--   Shock lasts the cast) > Chain Lightning on 2+ targets > Lightning Bolt
-- Thunderstorm for mana, Earth Shock while moving.
ns.RegisterAPL("SHAMAN", "elemental", "Elemental (default)", [[
## Out of combat
actions.precombat=water_shield,if=!buff.water_shield.up
actions.precombat+=/potion,if=toggle.cooldowns&pull.active&pull.remains<=1.5

## Main priority
# Big cooldowns follow the CD toggle (bosses only by default).
actions=call_action_list,name=cooldowns,if=toggle.cooldowns
# Mana back (used on trash too).
actions+=/thunderstorm,if=mana.pct<85
actions+=/totem_of_wrath,if=!totem.fire.up
actions+=/flame_shock,if=!dot.flame_shock.up&target.time_to_die>6
# Lava Burst crits when Flame Shock is still up as it lands.
actions+=/lava_burst,if=dot.flame_shock.remains>action.lava_burst.cast_time
actions+=/chain_lightning,if=active_enemies>=2
actions+=/earth_shock,if=moving
actions+=/lightning_bolt

## Cooldowns
actions.cooldowns=elemental_mastery
actions.cooldowns+=/fire_elemental_totem
actions.cooldowns+=/blood_fury
actions.cooldowns+=/berserking
actions.cooldowns+=/trinket1
actions.cooldowns+=/trinket2
actions.cooldowns+=/potion,if=buff.bloodlust.up|target.time_to_die<30
]])
