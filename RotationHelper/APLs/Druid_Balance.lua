local ADDON_NAME, ns = ...

-- Default Balance Druid priority for 3.3.5a:
--   Faerie Fire (unless someone's is up) > Insect Swarm > Moonfire >
--   Starfire in Lunar Eclipse / Wrath in Solar Eclipse >
--   between eclipses: keep casting the spell of the last one (Starfire after
--   Lunar, to proc Solar; Wrath after Solar, to proc Lunar)
-- Starfall on cooldown (trash too), Force of Nature with the big cooldowns.
ns.RegisterAPL("DRUID", "balance", "Balance (default)", [[
## Out of combat
actions.precombat=moonkin_form,if=!buff.moonkin_form.up
actions.precombat+=/potion,if=toggle.cooldowns&pull.active&pull.remains<=1.5

## Main priority
actions=moonkin_form,if=!buff.moonkin_form.up
# Big cooldowns follow the CD toggle (bosses only by default).
actions+=/call_action_list,name=cooldowns,if=toggle.cooldowns
actions+=/starfall,if=toggle.short_cooldowns
actions+=/hurricane,if=active_enemies>=5
actions+=/faerie_fire,if=!debuff.faerie_fire.up
actions+=/insect_swarm,if=!dot.insect_swarm.up&target.time_to_die>8
actions+=/moonfire,if=!dot.moonfire.up&target.time_to_die>8
actions+=/starfire,if=buff.lunar_eclipse.up
actions+=/wrath,if=buff.solar_eclipse.up
# Between eclipses: the spell of the last one, which procs the other.
actions+=/starfire,if=last.lunar_eclipse
actions+=/moonfire,if=moving
actions+=/wrath

## Cooldowns
actions.cooldowns=force_of_nature
actions.cooldowns+=/berserking
actions.cooldowns+=/trinket1
actions.cooldowns+=/trinket2
actions.cooldowns+=/potion,if=buff.bloodlust.up|target.time_to_die<30
]])
