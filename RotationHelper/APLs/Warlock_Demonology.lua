local ADDON_NAME, ns = ...

-- Default Demonology Warlock priority for 3.3.5a:
--   Demonic Empowerment > Immolation Aura (in Metamorphosis) > Soul Fire with
--   Decimation > Immolate > Corruption > Curse of Doom / Agony > Incinerate
--   with Molten Core > Shadow Bolt
-- Metamorphosis with the big cooldowns; Life Tap for mana and while moving.
ns.RegisterAPL("WARLOCK", "demonology", "Demonology (default)", [[
## Out of combat
actions.precombat=fel_armor,if=!buff.fel_armor.up
actions.precombat+=/potion,if=toggle.cooldowns&pull.active&pull.remains<=1.5

## Main priority
# Big cooldowns follow the CD toggle (bosses only by default).
actions=call_action_list,name=cooldowns,if=toggle.cooldowns
actions+=/life_tap,if=mana.pct<20
actions+=/demonic_empowerment,if=pet.alive
actions+=/immolation_aura,if=buff.metamorphosis.up
# Decimation: fast Soul Fire on targets below 35%.
actions+=/soul_fire,if=buff.decimation.up
actions+=/immolate,if=dot.immolate.remains<action.immolate.cast_time&target.time_to_die>6
actions+=/corruption,if=!dot.corruption.up&target.time_to_die>10
actions+=/curse_of_the_elements,if=option.curse.elements&!dot.curse_of_the_elements.up&target.time_to_die>15
actions+=/curse_of_doom,if=(option.curse.auto|option.curse.doom)&!dot.curse_of_doom.up&target.time_to_die>60
actions+=/curse_of_agony,if=(option.curse.agony|option.curse.auto&!dot.curse_of_doom.up)&!dot.curse_of_agony.up&target.time_to_die>15
actions+=/incinerate,if=buff.molten_core.up
actions+=/life_tap,if=moving&mana.pct<80
actions+=/shadow_bolt

## Cooldowns
actions.cooldowns=metamorphosis
actions.cooldowns+=/blood_fury
actions.cooldowns+=/trinket1
actions.cooldowns+=/trinket2
actions.cooldowns+=/potion,if=buff.bloodlust.up|buff.metamorphosis.up|target.time_to_die<30
]], {
    { key = "curse", name = "Curse", type = "select", default = "auto",
      values = { auto = "Doom on long fights, else Agony", agony = "Curse of Agony",
          doom = "Curse of Doom", elements = "Curse of the Elements", none = "None (someone else curses)" },
      desc = "Pick Curse of the Elements if you're the raid's Elements warlock." },
})
