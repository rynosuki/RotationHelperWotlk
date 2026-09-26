local ADDON_NAME, ns = ...

-- Default Marksmanship Hunter priority for 3.3.5a:
--   Hunter's Mark > Kill Shot (below 20%) > Serpent Sting > Chimera Shot >
--   Aimed Shot > Arcane Shot > Steady Shot
-- Steady Shot waits for the Auto Shot it would clip (instants fill the gap).
-- Aspect of the Viper when mana runs out, back to Dragonhawk at 40%.
ns.RegisterAPL("HUNTER", "marksmanship", "Marksmanship (default)", [[
## Out of combat
actions.precombat=aspect_of_the_dragonhawk,if=!buff.aspect_of_the_dragonhawk.up&!buff.aspect_of_the_viper.up
actions.precombat+=/hunters_mark,if=!debuff.hunters_mark.up
actions.precombat+=/potion,if=toggle.cooldowns&pull.active&pull.remains<=1.5

## Main priority
# Big cooldowns follow the CD toggle (bosses only by default).
actions=call_action_list,name=cooldowns,if=toggle.cooldowns
actions+=/aspect_of_the_viper,if=mana.pct<10&!buff.aspect_of_the_viper.up
actions+=/aspect_of_the_dragonhawk,if=mana.pct>40&!buff.aspect_of_the_dragonhawk.up
actions+=/hunters_mark,if=!debuff.hunters_mark.up&target.time_to_die>15
actions+=/kill_shot,if=target.health.pct<20
actions+=/serpent_sting,if=!dot.serpent_sting.up&target.time_to_die>8
# Chimera Shot also refreshes Serpent Sting.
actions+=/chimera_shot
actions+=/multi_shot,if=active_enemies>=3
actions+=/aimed_shot
actions+=/arcane_shot
actions+=/steady_shot

## Cooldowns
actions.cooldowns=rapid_fire
# Readiness right after Rapid Fire brings it straight back.
actions.cooldowns+=/readiness,if=buff.rapid_fire.up|cooldown.rapid_fire.remains>60
actions.cooldowns+=/kill_command,if=pet.alive
actions.cooldowns+=/blood_fury
actions.cooldowns+=/berserking
actions.cooldowns+=/trinket1
actions.cooldowns+=/trinket2
actions.cooldowns+=/potion,if=buff.bloodlust.up|buff.rapid_fire.up|target.time_to_die<30
]])
