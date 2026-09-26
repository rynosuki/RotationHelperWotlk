local ADDON_NAME, ns = ...

-- Default Shadow Priest priority for 3.3.5a:
--   Vampiric Touch (refreshed as it runs out) > Devouring Plague > Mind Blast >
--   Shadow Word: Pain (Mind Flay keeps it up with Pain and Suffering) > Mind Flay
-- Casts and channels wait for the cast before; while moving only instants
-- are suggested (Shadow Word: Death).
ns.RegisterAPL("PRIEST", "shadow", "Shadow (default)", [[
## Out of combat
actions.precombat=shadowform,if=!buff.shadowform.up
actions.precombat+=/inner_fire,if=!buff.inner_fire.up
actions.precombat+=/vampiric_embrace,if=!buff.vampiric_embrace.up
actions.precombat+=/potion,if=toggle.cooldowns&pull.active&pull.remains<=1.5

## Main priority
actions=shadowform,if=!buff.shadowform.up
# Big cooldowns follow the CD toggle (bosses only by default).
actions+=/call_action_list,name=cooldowns,if=toggle.cooldowns
# Mana (used on trash too).
actions+=/shadowfiend,if=mana.pct<50
actions+=/dispersion,if=mana.pct<10
actions+=/run_action_list,name=aoe,if=active_enemies>=4
# Refresh the DoTs if they'd run out during the next Mind Flay (a channel
# isn't cut short here): Vampiric Touch so the new one lands in time.
actions+=/vampiric_touch,if=dot.vampiric_touch.remains<action.vampiric_touch.cast_time+action.mind_flay.cast_time&target.time_to_die>6
actions+=/devouring_plague,if=dot.devouring_plague.remains<action.mind_flay.cast_time&target.time_to_die>8
actions+=/mind_blast
# Once up, Mind Flay keeps it going (Pain and Suffering).
actions+=/shadow_word_pain,if=!dot.shadow_word_pain.up&target.time_to_die>6
actions+=/shadow_word_death,if=moving
actions+=/mind_flay

## Cooldowns
actions.cooldowns=berserking
actions.cooldowns+=/trinket1
actions.cooldowns+=/trinket2
actions.cooldowns+=/potion,if=buff.bloodlust.up|target.time_to_die<30

## 4+ targets
actions.aoe=vampiric_touch,if=dot.vampiric_touch.remains<action.vampiric_touch.cast_time&target.time_to_die>6
actions.aoe+=/shadow_word_pain,if=!dot.shadow_word_pain.up&target.time_to_die>6
actions.aoe+=/mind_sear
]])
