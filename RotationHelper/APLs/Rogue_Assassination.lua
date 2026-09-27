local ADDON_NAME, ns = ...

-- Default Assassination (Mutilate) Rogue priority for 3.3.5a:
--   Slice and Dice always up > Hunger for Blood (needs a bleed) > Rupture
--   (only as the bleed for Hunger for Blood) > Envenom at 4+ points (a setting) (Cold Blood first) >
--   Mutilate to build points
-- At 4+ points with Slice and Dice running low, refresh it first. Vanish
-- with the big cooldowns, for Overkill's energy.
ns.RegisterAPL("ROGUE", "assassination", "Assassination (default)", [[
## Out of combat
actions.precombat=potion,if=toggle.cooldowns&pull.active&pull.remains<=1.5

## Main priority
# Big cooldowns follow the CD toggle (bosses only by default).
actions=call_action_list,name=cooldowns,if=toggle.cooldowns
actions+=/slice_and_dice,if=!buff.slice_and_dice.up
# Hunger for Blood needs a bleed on the target: your Rupture or anyone's.
actions+=/hunger_for_blood,if=buff.hunger_for_blood.remains<3&(dot.rupture.up|debuff.bleed.up)
# Rupture when Hunger for Blood will need a bleed and there is none; Envenom is the main finisher.
actions+=/rupture,if=combo_points>=option.finish_at&!dot.rupture.up&!debuff.bleed.up&buff.hunger_for_blood.remains<10&target.time_to_die>12
actions+=/slice_and_dice,if=combo_points>=option.finish_at&buff.slice_and_dice.remains<5
actions+=/envenom,if=combo_points>=option.finish_at
actions+=/mutilate,if=combo_points<option.finish_at

## Cooldowns
actions.cooldowns=cold_blood,if=combo_points>=option.finish_at
# Vanish for Overkill: 30% faster energy for 20 seconds, best while energy is low.
# (It can briefly count you as out of combat; a boss puts you straight back in.)
actions.cooldowns+=/vanish,if=talent.overkill.enabled&energy<50&!buff.overkill.up
actions.cooldowns+=/blood_fury
actions.cooldowns+=/berserking
actions.cooldowns+=/trinket1
actions.cooldowns+=/trinket2
actions.cooldowns+=/potion,if=buff.bloodlust.up|target.time_to_die<30
]], {
    { key = "finish_at", name = "Finishers at combo points", type = "range", default = 4, min = 3, max = 5, step = 1,
      desc = "Envenom (and Rupture, Slice and Dice, Cold Blood) from this many points. "
          .. "5 wastes fewer points, 4 keeps Envenom's buff up more." },
})
