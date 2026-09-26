local ADDON_NAME, ns = ...

-- Default Affliction Warlock priority for 3.3.5a:
--   Haunt on cooldown > Unstable Affliction (refreshed as it runs out) >
--   Corruption (once; Everlasting Affliction keeps it going) > Curse of
--   Agony > Drain Soul below 25% > Shadow Bolt
-- Life Tap for mana (and while moving). If you're the raid's Curse of the
-- Elements warlock, replace the Curse of Agony line with curse_of_the_elements.
ns.RegisterAPL("WARLOCK", "affliction", "Affliction (default)", [[
## Out of combat
actions.precombat=fel_armor,if=!buff.fel_armor.up
actions.precombat+=/potion,if=toggle.cooldowns&pull.active&pull.remains<=1.5

## Main priority
# Big cooldowns follow the CD toggle (bosses only by default).
actions=call_action_list,name=cooldowns,if=toggle.cooldowns
actions+=/life_tap,if=mana.pct<20
actions+=/run_action_list,name=aoe,if=active_enemies>=4
actions+=/haunt
# Recast so the new one lands as the old one runs out.
actions+=/unstable_affliction,if=dot.unstable_affliction.remains<action.unstable_affliction.cast_time&target.time_to_die>8
actions+=/corruption,if=!dot.corruption.up&target.time_to_die>10
actions+=/curse_of_agony,if=!dot.curse_of_agony.up&target.time_to_die>15
actions+=/drain_soul,if=target.health.pct<25
# While moving, Life Tap instead of standing still.
actions+=/life_tap,if=moving&mana.pct<80
actions+=/shadow_bolt

## Cooldowns
actions.cooldowns=blood_fury
actions.cooldowns+=/trinket1
actions.cooldowns+=/trinket2
actions.cooldowns+=/potion,if=buff.bloodlust.up|target.time_to_die<30

## 4+ targets
actions.aoe=corruption,if=!dot.corruption.up&target.time_to_die>10
actions.aoe+=/seed_of_corruption
]])
