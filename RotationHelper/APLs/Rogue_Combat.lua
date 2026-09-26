local ADDON_NAME, ns = ...

-- Default Combat Rogue priority for 3.3.5a:
--   Slice and Dice always up > Rupture (5 points, long fights) >
--   Eviscerate (5 points) > Sinister Strike to build points
-- At 5 points with Slice and Dice running low, refresh it first.
-- Killing Spree when low on energy, Blade Flurry and Adrenaline Rush.
ns.RegisterAPL("ROGUE", "combat", "Combat (default)", [[
## Out of combat
actions.precombat=potion,if=toggle.cooldowns&pull.active&pull.remains<=1.5

## Main priority
# Big cooldowns follow the CD toggle (bosses only by default).
actions=call_action_list,name=cooldowns,if=toggle.cooldowns
actions+=/slice_and_dice,if=!buff.slice_and_dice.up
actions+=/blade_flurry,if=toggle.short_cooldowns
# Killing Spree while energy is low, so none is wasted during it.
actions+=/killing_spree,if=toggle.short_cooldowns&energy<40&buff.slice_and_dice.remains>3
actions+=/slice_and_dice,if=combo_points=5&buff.slice_and_dice.remains<6
actions+=/rupture,if=combo_points=5&!dot.rupture.up&target.time_to_die>12
actions+=/eviscerate,if=combo_points=5
actions+=/sinister_strike,if=combo_points<5

## Cooldowns
actions.cooldowns=adrenaline_rush,if=energy<50
actions.cooldowns+=/blood_fury
actions.cooldowns+=/berserking
actions.cooldowns+=/trinket1
actions.cooldowns+=/trinket2
actions.cooldowns+=/potion,if=buff.bloodlust.up|buff.adrenaline_rush.up|target.time_to_die<30
]])
