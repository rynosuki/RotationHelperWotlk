local ADDON_NAME, ns = ...

-- Default Arcane Mage priority for 3.3.5a:
--   Above 35% mana (a setting): Arcane Blast (Arcane Missiles only with Missile Barrage
--   at 4 stacks).
--   Below: build 4 Arcane Blast stacks, then spend them with Arcane Missiles.
-- Arcane Blast costs 175% more per stack; Missile Barrage makes Arcane
-- Missiles fast and free. Arcane Barrage while moving.
ns.RegisterAPL("MAGE", "arcane", "Arcane (default)", [[
## Out of combat
actions.precombat=molten_armor,if=!buff.molten_armor.up
actions.precombat+=/potion,if=toggle.cooldowns&pull.active&pull.remains<=1.5

## Main priority
# Big cooldowns follow the CD toggle (bosses only by default).
actions=call_action_list,name=cooldowns,if=toggle.cooldowns
# Mana (used on trash too).
actions+=/evocation,if=mana.pct<option.evocation_below
actions+=/arcane_missiles,if=buff.missile_barrage.up&buff.arcane_blast.stack=4
actions+=/arcane_blast,if=mana.pct>=option.blast_above|buff.arcane_blast.stack<4
actions+=/arcane_missiles
actions+=/arcane_barrage,if=moving

## Cooldowns
actions.cooldowns=arcane_power
actions.cooldowns+=/presence_of_mind,if=buff.arcane_power.up|cooldown.arcane_power.remains>30
actions.cooldowns+=/mirror_image
actions.cooldowns+=/berserking,if=buff.arcane_power.up|cooldown.arcane_power.remains>30
actions.cooldowns+=/trinket1
actions.cooldowns+=/trinket2
actions.cooldowns+=/potion,if=buff.bloodlust.up|buff.arcane_power.up|target.time_to_die<30
]], {
    { key = "blast_above", name = "Keep casting Arcane Blast above mana %", type = "range", default = 35,
      min = 0, max = 100, step = 5,
      desc = "Above this, Arcane Blast keeps stacking; below it, 4 stacks are spent with Arcane Missiles. "
          .. "Lower it for short fights or lots of mana regen." },
    { key = "evocation_below", name = "Evocation below mana %", type = "range", default = 10,
      min = 0, max = 50, step = 5 },
})
