local ADDON_NAME, ns = ...

-- Default Arms Warrior priority for 3.3.5a, in Battle Stance:
--   Rend upkeep > Overpower (Taste for Blood or a dodge) > Mortal Strike >
--   Execute (Sudden Death, or below 20%) > Bladestorm > Slam
-- Heroic Strike (Cleave on 2+ targets) goes on the next swing when there's
-- rage to spare; Sweeping Strikes with 2+ targets.
ns.RegisterAPL("WARRIOR", "arms", "Arms (default)", [[
## Out of combat
# Rage for the shout.
actions.precombat=bloodrage,if=!buff.battle_shout.up&!buff.blessing_of_might.up&rage<10
actions.precombat+=/battle_shout,if=!buff.battle_shout.up&!buff.blessing_of_might.up
actions.precombat+=/potion,if=toggle.cooldowns&pull.active&pull.remains<=1.5

## Main priority
# Big cooldowns follow the CD toggle (bosses only by default).
actions=call_action_list,name=cooldowns,if=toggle.cooldowns
# Rage generators when short on rage (used on trash too).
actions+=/berserker_rage,if=toggle.short_cooldowns&rage<60
actions+=/bloodrage,if=toggle.short_cooldowns&rage<50
actions+=/sweeping_strikes,if=active_enemies>=2
# Spare rage goes into the next swing.
actions+=/heroic_strike,if=active_enemies<2&rage>=60
actions+=/cleave,if=active_enemies>=2&rage>=50
# Rend feeds Taste for Blood; refresh it just before it runs out.
actions+=/rend,if=dot.rend.remains<3&target.time_to_die>10
actions+=/overpower
actions+=/mortal_strike
actions+=/execute,if=buff.sudden_death.up|target.health.pct<20
actions+=/bladestorm,if=toggle.short_cooldowns
actions+=/slam
actions+=/battle_shout,if=!buff.battle_shout.up&!buff.blessing_of_might.up
actions+=/victory_rush

## Cooldowns
actions.cooldowns=blood_fury
actions.cooldowns+=/berserking
actions.cooldowns+=/trinket1
actions.cooldowns+=/trinket2
actions.cooldowns+=/potion,if=buff.bloodlust.up|target.time_to_die<30
]])
