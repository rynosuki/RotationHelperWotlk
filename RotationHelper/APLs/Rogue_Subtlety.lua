local ADDON_NAME, ns = ...

-- Default Subtlety Rogue priority for 3.3.5a:
--   Slice and Dice always up > Shadow Dance on cooldown, then
--   Premeditation and Ambush during it > Rupture and Eviscerate at 5 points
--   > Hemorrhage (keep its debuff up) > Backstab to build points
-- Backstab and Ambush need you behind the target. Honor Among Thieves combo
-- points come from your group's crits and aren't predicted.
ns.RegisterAPL("ROGUE", "subtlety", "Subtlety (default)", [[
## Out of combat
actions.precombat=potion,if=toggle.cooldowns&pull.active&pull.remains<=1.5

## Main priority
# Big cooldowns follow the CD toggle (bosses only by default).
actions=call_action_list,name=cooldowns,if=toggle.cooldowns
actions+=/slice_and_dice,if=!buff.slice_and_dice.up
# Shadow Dance on cooldown (used on trash too): Premeditation and Ambushes during it.
actions+=/shadow_dance,if=toggle.short_cooldowns
actions+=/premeditation,if=combo_points<=3
actions+=/ambush,if=combo_points<5
actions+=/slice_and_dice,if=combo_points=5&buff.slice_and_dice.remains<6
actions+=/rupture,if=combo_points=5&!dot.rupture.up&target.time_to_die>12
actions+=/eviscerate,if=combo_points=5
actions+=/hemorrhage,if=!debuff.hemorrhage.up&combo_points<5
actions+=/backstab,if=combo_points<5

## Cooldowns
actions.cooldowns=blood_fury
actions.cooldowns+=/berserking
actions.cooldowns+=/trinket1
actions.cooldowns+=/trinket2
actions.cooldowns+=/potion,if=buff.bloodlust.up|target.time_to_die<30
]])
