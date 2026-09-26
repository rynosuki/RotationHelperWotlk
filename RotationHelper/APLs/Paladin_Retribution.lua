local ADDON_NAME, ns = ...

-- Default Retribution Paladin priority for 3.3.5a: the classic "first come,
-- first served" list. Everything is on a short cooldown; use whatever is
-- ready, in this order:
--   Judgement > Hammer of Wrath > Crusader Strike > Divine Storm >
--   Consecration > Exorcism (with The Art of War) > Holy Wrath (undead/demons)
-- Seal of Vengeance (Alliance) or Corruption (Horde) stays up; lines for
-- the one you don't have are skipped.
ns.RegisterAPL("PALADIN", "retribution", "Retribution (default)", [[
## Out of combat
actions.precombat=seal_of_vengeance,if=!buff.seal.up
actions.precombat+=/seal_of_corruption,if=!buff.seal.up
actions.precombat+=/potion,if=toggle.cooldowns&pull.active&pull.remains<=1.5

## Main priority
actions=seal_of_vengeance,if=!buff.seal.up
actions+=/seal_of_corruption,if=!buff.seal.up
# Big cooldowns follow the CD toggle (bosses only by default).
actions+=/call_action_list,name=cooldowns,if=toggle.cooldowns
actions+=/run_action_list,name=aoe,if=active_enemies>=3
actions+=/judgement
actions+=/hammer_of_wrath,if=target.health.pct<20
actions+=/crusader_strike
actions+=/divine_storm
# Not worth the mana on something that's about to die.
actions+=/consecration,if=target.time_to_die>=6
# Exorcism is only instant with The Art of War.
actions+=/exorcism,if=buff.the_art_of_war.up
actions+=/holy_wrath,if=target.type.undead|target.type.demon
# Divine Plea fills a gap when nothing else is ready.
actions+=/divine_plea,if=mana.pct<90

## Cooldowns
actions.cooldowns=avenging_wrath
actions.cooldowns+=/trinket1
actions.cooldowns+=/trinket2
actions.cooldowns+=/potion,if=buff.bloodlust.up|buff.avenging_wrath.up|target.time_to_die<30
actions.cooldowns+=/arcane_torrent,if=mana.pct<90

## 3+ targets
actions.aoe=consecration
actions.aoe+=/divine_storm
actions.aoe+=/holy_wrath,if=target.type.undead|target.type.demon
actions.aoe+=/judgement
actions.aoe+=/hammer_of_wrath,if=target.health.pct<20
actions.aoe+=/crusader_strike
actions.aoe+=/exorcism,if=buff.the_art_of_war.up
actions.aoe+=/divine_plea,if=mana.pct<90
]])
