local ADDON_NAME, ns = ...

-- Default Feral (cat) Druid priority for 3.3.5a:
--   Faerie Fire and Mangle debuffs (anyone's count) > Savage Roar (even at 1
--   point) > Rip at 5 points > Rake > Ferocious Bite at 5 points when Rip and
--   Savage Roar have long left > Shred to build points (and to not cap energy)
-- Tiger's Fury when low on energy, Berserk with the big cooldowns.
ns.RegisterAPL("DRUID", "feral_combat", "Feral cat (default)", [[
## Out of combat
actions.precombat=cat_form,if=!buff.cat_form.up
actions.precombat+=/potion,if=toggle.cooldowns&pull.active&pull.remains<=1.5

## Main priority
actions=cat_form,if=!buff.cat_form.up
# Big cooldowns follow the CD toggle (bosses only by default).
actions+=/call_action_list,name=cooldowns,if=toggle.cooldowns
# Energy (used on trash too).
actions+=/tigers_fury,if=toggle.short_cooldowns&energy<30
actions+=/faerie_fire_feral,if=!debuff.faerie_fire.up
actions+=/mangle_cat,if=!debuff.mangle.up
actions+=/savage_roar,if=buff.savage_roar.remains<2
actions+=/rip,if=combo_points=5&dot.rip.remains<2&target.time_to_die>10
actions+=/rake,if=dot.rake.remains<1&target.time_to_die>9
actions+=/ferocious_bite,if=combo_points=5&dot.rip.remains>8&buff.savage_roar.remains>8
actions+=/shred,if=combo_points<5
# At 5 points waiting on Rip or Savage Roar: Shred rather than capping energy.
actions+=/shred,if=energy>80

## Cooldowns
actions.cooldowns=berserk,if=buff.tigers_fury.up|cooldown.tigers_fury.remains>15
actions.cooldowns+=/berserking
actions.cooldowns+=/trinket1
actions.cooldowns+=/trinket2
actions.cooldowns+=/potion,if=buff.bloodlust.up|buff.berserk.up|target.time_to_die<30
]])
