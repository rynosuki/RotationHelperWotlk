local ADDON_NAME, ns = ...

-- Default Frost Mage priority for 3.3.5a:
--   Water Elemental out > Deep Freeze (with Fingers of Frost) > Frostfire
--   Bolt with Brain Freeze (instant, free) > Frostbolt
-- Ice Lance while moving. Icy Veins, Cold Snap to bring it back.
ns.RegisterAPL("MAGE", "frost", "Frost (default)", [[
## Out of combat
actions.precombat=molten_armor,if=!buff.molten_armor.up
actions.precombat+=/summon_water_elemental,if=!pet.alive
actions.precombat+=/potion,if=toggle.cooldowns&pull.active&pull.remains<=1.5

## Main priority
# Big cooldowns follow the CD toggle (bosses only by default).
actions=call_action_list,name=cooldowns,if=toggle.cooldowns
# Mana (used on trash too).
actions+=/evocation,if=mana.pct<10
actions+=/summon_water_elemental,if=!pet.alive
# Deep Freeze needs a frozen target: Fingers of Frost counts.
actions+=/deep_freeze
actions+=/frostfire_bolt,if=buff.brain_freeze.up
actions+=/ice_lance,if=moving
actions+=/frostbolt

## Cooldowns
actions.cooldowns=icy_veins
# Cold Snap once Icy Veins has run out, to use it again.
actions.cooldowns+=/cold_snap,if=cooldown.icy_veins.remains>60&!buff.icy_veins.up
actions.cooldowns+=/mirror_image
actions.cooldowns+=/berserking,if=buff.icy_veins.up|cooldown.icy_veins.remains>30
actions.cooldowns+=/trinket1
actions.cooldowns+=/trinket2
actions.cooldowns+=/potion,if=buff.bloodlust.up|buff.icy_veins.up|target.time_to_die<30
]])
