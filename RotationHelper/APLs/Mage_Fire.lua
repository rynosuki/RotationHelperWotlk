local ADDON_NAME, ns = ...

-- Default Fire Mage priority for 3.3.5a:
--   Improved Scorch debuff (unless someone provides it) > Living Bomb >
--   Pyroblast with Hot Streak > Fireball
-- Fire Blast while moving; Flamestrike on 4+ targets.
ns.RegisterAPL("MAGE", "fire", "Fire (default)", [[
## Out of combat
actions.precombat=molten_armor,if=!buff.molten_armor.up
actions.precombat+=/potion,if=toggle.cooldowns&pull.active&pull.remains<=1.5

## Main priority
# Big cooldowns follow the CD toggle (bosses only by default).
actions=call_action_list,name=cooldowns,if=toggle.cooldowns
# Mana (used on trash too).
actions+=/evocation,if=mana.pct<10
# The 5% crit debuff; Winter's Chill or Shadow Mastery count too.
actions+=/scorch,if=talent.improved_scorch.enabled&debuff.improved_scorch.remains<3
actions+=/living_bomb,if=!dot.living_bomb.up&target.time_to_die>12
actions+=/pyroblast,if=buff.hot_streak.up
actions+=/fire_blast,if=moving
actions+=/flamestrike,if=active_enemies>=4
actions+=/fireball

## Cooldowns
actions.cooldowns=combustion
actions.cooldowns+=/mirror_image
actions.cooldowns+=/berserking
actions.cooldowns+=/trinket1
actions.cooldowns+=/trinket2
actions.cooldowns+=/potion,if=buff.bloodlust.up|target.time_to_die<30
]])
