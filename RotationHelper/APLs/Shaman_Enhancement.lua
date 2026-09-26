local ADDON_NAME, ns = ...

-- Default Enhancement Shaman priority for 3.3.5a:
--   Lightning Bolt at 5 Maelstrom Weapon > Stormstrike > Flame Shock (when
--   missing) > Earth Shock > Magma Totem > Fire Nova > Lava Lash >
--   Lightning Shield
-- The shocks share a cooldown. Magma Totem is worth it even on one target.
ns.RegisterAPL("SHAMAN", "enhancement", "Enhancement (default)", [[
## Out of combat
actions.precombat=lightning_shield,if=!buff.lightning_shield.up
actions.precombat+=/potion,if=toggle.cooldowns&pull.active&pull.remains<=1.5

## Main priority
# Big cooldowns follow the CD toggle (bosses only by default).
actions=call_action_list,name=cooldowns,if=toggle.cooldowns
# Mana back when running low (used on trash too).
actions+=/shamanistic_rage,if=mana.pct<50
actions+=/chain_lightning,if=active_enemies>=2&buff.maelstrom_weapon.stack=5
actions+=/lightning_bolt,if=buff.maelstrom_weapon.stack=5
actions+=/magma_totem,if=active_enemies>=3&totem.fire.remains<2
actions+=/fire_nova,if=active_enemies>=3&totem.fire.up
actions+=/stormstrike
actions+=/flame_shock,if=!dot.flame_shock.up
# Not when Flame Shock would run out during the shared cooldown it starts.
actions+=/earth_shock,if=dot.flame_shock.remains>cooldown.earth_shock.duration
# Refresh Magma Totem as it runs out (not in the first seconds of a trash pull).
actions+=/magma_totem,if=totem.fire.remains<2&target.time_to_die>10
actions+=/fire_nova,if=totem.fire.up&mana.pct>30
actions+=/lava_lash
actions+=/lightning_shield,if=!buff.lightning_shield.up

## Cooldowns
actions.cooldowns=feral_spirit
actions.cooldowns+=/blood_fury
actions.cooldowns+=/berserking
actions.cooldowns+=/trinket1
actions.cooldowns+=/trinket2
actions.cooldowns+=/potion,if=buff.bloodlust.up|target.time_to_die<30
]])
