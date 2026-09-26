local ADDON_NAME, ns = ...

-- Default Fury Warrior priority for 3.3.5a (Titan's Grip or dual one-handers),
-- in Berserker Stance:
--   Bloodthirst > Whirlwind > Slam with Bloodsurge > Execute (below 20%)
-- Heroic Strike (Cleave on 2+ targets) goes on the next swing when there's
-- rage to spare; it's off the GCD, so it shows next to the other abilities.
ns.RegisterAPL("WARRIOR", "fury", "Fury (default)", [[
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
# Spare rage goes into the next swing.
actions+=/heroic_strike,if=active_enemies<2&rage>=50
actions+=/cleave,if=active_enemies>=2&rage>=50
actions+=/whirlwind,if=active_enemies>=2
actions+=/bloodthirst
actions+=/whirlwind
actions+=/slam,if=buff.bloodsurge.up
actions+=/execute,if=target.health.pct<20
actions+=/battle_shout,if=!buff.battle_shout.up&!buff.blessing_of_might.up
actions+=/victory_rush

## Cooldowns
actions.cooldowns=death_wish
actions.cooldowns+=/recklessness,if=buff.death_wish.up|!talent.death_wish.enabled|cooldown.death_wish.remains>60
actions.cooldowns+=/blood_fury,if=buff.death_wish.up|cooldown.death_wish.remains>60|!talent.death_wish.enabled
actions.cooldowns+=/berserking,if=buff.death_wish.up|cooldown.death_wish.remains>60|!talent.death_wish.enabled
actions.cooldowns+=/trinket1
actions.cooldowns+=/trinket2
actions.cooldowns+=/potion,if=buff.bloodlust.up|buff.death_wish.up|target.time_to_die<30
]])
