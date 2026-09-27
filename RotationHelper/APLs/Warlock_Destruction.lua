local ADDON_NAME, ns = ...

-- Default Destruction Warlock priority for 3.3.5a:
--   Immolate (refreshed as it runs out) > Conflagrate > Chaos Bolt >
--   Curse of Doom (long fights) / Curse of Agony > Incinerate
-- Conflagrate starts Backdraft: the next three casts are faster. Without
-- Glyph of Conflagrate it uses up Immolate, which then comes first again.
ns.RegisterAPL("WARLOCK", "destruction", "Destruction (default)", [[
## Out of combat
actions.precombat=fel_armor,if=!buff.fel_armor.up
actions.precombat+=/potion,if=toggle.cooldowns&pull.active&pull.remains<=1.5

## Main priority
# Big cooldowns follow the CD toggle (bosses only by default).
actions=call_action_list,name=cooldowns,if=toggle.cooldowns
actions+=/life_tap,if=mana.pct<20
actions+=/run_action_list,name=aoe,if=active_enemies>=4
# Recast so the new one lands as the old one runs out.
actions+=/immolate,if=dot.immolate.remains<action.immolate.cast_time&target.time_to_die>6
actions+=/conflagrate,if=dot.immolate.up
actions+=/chaos_bolt
# One curse per target (a setting). By default Doom when the target lives long enough, else Agony.
actions+=/curse_of_the_elements,if=option.curse.elements&!dot.curse_of_the_elements.up&target.time_to_die>15
actions+=/curse_of_doom,if=(option.curse.auto|option.curse.doom)&!dot.curse_of_doom.up&target.time_to_die>60
actions+=/curse_of_agony,if=(option.curse.agony|option.curse.auto&!dot.curse_of_doom.up)&!dot.curse_of_agony.up&target.time_to_die>15
# While moving, Life Tap instead of standing still.
actions+=/life_tap,if=moving&mana.pct<80
actions+=/incinerate

## Cooldowns
actions.cooldowns=blood_fury
actions.cooldowns+=/trinket1
actions.cooldowns+=/trinket2
actions.cooldowns+=/potion,if=buff.bloodlust.up|target.time_to_die<30

## 4+ targets
actions.aoe=seed_of_corruption
]], {
    { key = "curse", name = "Curse", type = "select", default = "auto",
      values = { auto = "Doom on long fights, else Agony", agony = "Curse of Agony",
          doom = "Curse of Doom", elements = "Curse of the Elements", none = "None (someone else curses)" },
      desc = "Pick Curse of the Elements if you're the raid's Elements warlock." },
})
