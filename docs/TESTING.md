# Checking a spec in game

Every rotation is built from 3.3.5 knowledge, the simulator (`lua tests/sim.lua <spec>`) and offline
tests, but only Frost Death Knight has been played with so far. This list is what to look at the
first time you play a spec; tick it off in [SPECS.md](SPECS.md) once it holds up.

If something is off: `/rh report` right when it happens, and paste it into a
[new issue](https://github.com/rynosuki/RotationHelperWotlk/issues/new?template=bug_report.md).

## For every spec

- [ ] At a training dummy, the icons follow what you press; the queue makes sense.
- [ ] `/rh snapshot` lists your talents and glyphs, and no abilities you have as "Not in spellbook".
- [ ] Procs light up (glow and corner icon) when they happen. If one never does, its spell ID is
      probably wrong: note the buff's name and, if you can, its ID.
- [ ] Short on resources, the icon counts down (RUNES / RAGE / ENERGY / CAST / AUTO) and the flash
      comes when you can press.
- [ ] Cooldowns follow the CD toggle, and only show against bosses (skull, boss frames or a known
      boss name) unless that's turned off.
- [ ] After a fight of 20+ seconds, `/rh review` has sensible numbers.

## Per spec

| Spec | Things to check |
|---|---|
| Frost DK | (checked) |
| Unholy DK | Summon Gargoyle waits for a burst buff, at most 15 s; Ghoul Frenzy about every 25 s. |
| Blood DK | Frost Presence switches to the tank list; Rune Strike appears after a dodge or parry and disappears once queued; Rune Tap, Vampiric Blood and Hysteria are off the GCD. |
| Retribution | Mana costs match the tooltips; Judgement follows General > Judgement; Holy Wrath only on undead and demons; Exorcism with The Art of War. |
| Fury | The rage countdown once the income is learned; Heroic Strike disappears once queued; 50 rage threshold feels right. |
| Arms | Overpower after a dodge and with Taste for Blood, only in Battle Stance; Rend isn't clipped early. |
| Enhancement | Totems read correctly (fire totem remains); shocks share a cooldown; Fire Nova only with a fire totem; imbue checklist. |
| Elemental | Lava Burst skipped when Flame Shock would drop mid-cast; no Totem of Wrath reminder while Fire Elemental is out. |
| Shadow | The countdown during Mind Flay matches the channel; haste read (GCD in `/rh snapshot`); only instants while moving. |
| Fire | Scorch skipped when another Improved Scorch / Winter's Chill is up; Pyroblast lights up with Hot Streak. |
| Arcane | Arcane Blast stacks read from the debuff on you; Missiles with Missile Barrage (2.5 s) vs without (5 s); the 35% mana point. |
| Frost Mage | Deep Freeze with Fingers of Frost; Frostfire Bolt instant with Brain Freeze (buff named "Fireball!"). |
| Affliction | Corruption stays up from Shadow Bolt; Unstable Affliction recast timing; Life Tap when low. |
| Destruction | Backdraft makes the next casts faster; Curse of Doom on bosses, Agony otherwise; Immolate straight back after Conflagrate (unglyphed). |
| Demonology | Molten Core Incinerates; Decimation Soul Fire below 35%; Immolation Aura only in Metamorphosis. |
| Balance | Eclipse buffs detected (IDs 48518 / 48517); keeps casting the last eclipse's spell. |
| Feral cat | Energy countdown; Clearcasting makes the next icon free; Rip vs Ferocious Bite at 5 points. |
| Combat | Energy countdown; combo points; Rupture vs Eviscerate. |
| Assassination | Hunger for Blood with someone else's bleed; Vanish for Overkill; Envenom at 4 points. |
| Subtlety | Ambush and Premeditation during Shadow Dance; finishers keep up with Honor Among Thieves. |
| Marksmanship | Auto Shot tracking (AUTO wait before Steady Shot); Readiness brings Rapid Fire back. |
| Survival | Lock and Load: two free Explosive Shots with the glow. |
| Beast Mastery | Kill Command as soon as it's ready; Bestial Wrath with Rapid Fire; nothing needing the pet without one. |
