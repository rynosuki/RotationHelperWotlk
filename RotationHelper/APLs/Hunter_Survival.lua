local ADDON_NAME, ns = ...

-- Default Survival Hunter priority for 3.3.5a:
--   Hunter's Mark > Kill Shot (below 20%) > Explosive Shot (on cooldown, and
--   twice with Lock and Load) > Black Arrow > Serpent Sting > Aimed Shot >
--   Steady Shot
-- Steady Shot waits for the Auto Shot it would clip, when that's cheaper.
ns.RegisterAPL("HUNTER", "survival", "Survival (default)", [[
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
# With Lock and Load, Explosive Shot skips its cooldown and costs nothing.
actions+=/explosive_shot
actions+=/black_arrow,if=target.time_to_die>10
# Refresh just before it runs out, so a Steady Shot cast doesn't let it drop.
actions+=/serpent_sting,if=dot.serpent_sting.remains<2&target.time_to_die>8
actions+=/multi_shot,if=active_enemies>=3
actions+=/aimed_shot
actions+=/steady_shot

## Cooldowns
actions.cooldowns=rapid_fire
actions.cooldowns+=/kill_command,if=pet.alive
actions.cooldowns+=/blood_fury
actions.cooldowns+=/berserking
actions.cooldowns+=/trinket1
actions.cooldowns+=/trinket2
actions.cooldowns+=/potion,if=buff.bloodlust.up|buff.rapid_fire.up|target.time_to_die<30
]])
