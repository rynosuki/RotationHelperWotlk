local ADDON_NAME, ns = ...

-- Default Beast Mastery Hunter priority for 3.3.5a:
--   Hunter's Mark > Kill Shot (below 20%) > Serpent Sting > Kill Command >
--   Aimed Shot > Arcane Shot > Steady Shot
-- Bestial Wrath (The Beast Within halves your costs) with Rapid Fire.
-- Steady Shot waits for the Auto Shot it would clip, when that's cheaper.
ns.RegisterAPL("HUNTER", "beast_mastery", "Beast Mastery (default)", [[
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
actions+=/serpent_sting,if=dot.serpent_sting.remains<2&target.time_to_die>8
# Kill Command whenever it's ready (used on trash too).
actions+=/kill_command,if=pet.alive
actions+=/multi_shot,if=active_enemies>=3
actions+=/aimed_shot
actions+=/arcane_shot
actions+=/steady_shot

## Cooldowns
actions.cooldowns=bestial_wrath,if=pet.alive
actions.cooldowns+=/rapid_fire,if=buff.the_beast_within.up|cooldown.bestial_wrath.remains>60
actions.cooldowns+=/blood_fury,if=buff.the_beast_within.up|cooldown.bestial_wrath.remains>60
actions.cooldowns+=/berserking,if=buff.the_beast_within.up|cooldown.bestial_wrath.remains>60
actions.cooldowns+=/trinket1
actions.cooldowns+=/trinket2
actions.cooldowns+=/potion,if=buff.bloodlust.up|buff.the_beast_within.up|target.time_to_die<30
]])
