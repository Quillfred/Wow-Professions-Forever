# How WoW Forever profession trainers decide what they'll teach (researched 2026-11-23)

Sources: 27 Wowhead Forever pages (25 Tailoring trainer NPC pages, the Professions Overview guide, the Tailoring Overview guide), each trainer's comments dated 2026, other Forever guide sites and the Blizzard Forever forum. Confidence labels:
- **Player-confirmed:** 2026 player reports.
- **Guide:** a Forever guide states it.
- **Wowhead data:** Wowhead's Teaches tab.
- **Inferred:** follows from the above but nobody states it.
- **Classic:** older reports, not confirmed for Forever.

**Big caveat: Wowhead's Teaches tabs don't show Forever's gating.** They list every rank a trainer has spells for: Josef Gregorian shows Apprentice, Journeyman and Expert with recipes from skill 1 to 190, and Timothy Worthington shows Apprentice through Artisan with recipes 1-210. A 2026-11-14 comment on Timothy's page says the "Teaches tab on website needs to be updated to reflect forever content". So the Teaches tab says what a trainer *has*, not what they'll *offer you*.

---

## 1. Rules summary

### Q1. Trainer gating
- **Rule (Guide):** "Each trainer teaches up to the rank below their own. To learn Journeyman, visit an Expert trainer, and to learn Expert, visit an Artisan trainer." Also: "Once a trainer has taught you everything they can, if you talk to them, they should have a text that directs you to the next trainer." Source: [Wowhead Tailoring Overview](https://www.wowhead.com/forever/guide/professions/tailoring-overview-trainer-locations-recipes), by Serenal, updated 2026-11-21.
- **The gate is your skill reaching the threshold of the rank that trainer teaches (Player-confirmed for Master trainers).** On [Timothy Worthington](https://www.wowhead.com/forever/npc=11052) (Master Tailor), 2026 comments say:
  - 2026-11-14, Rageinjector: "he has nothing to teach with 190 tailoring".
  - 2026-11-14, Coot: "At 200 tailoring I could speak to him … and learn new recipes".
  - 2026-11-15, reply: "I just wanted the red mageweave bag recipe which requires 195, but I needed 200 to make him offer training to me".
  - 2026-11-20, reply: "dont bother talking to him till you have 200 skill".

  So a Master trainer offers nothing, not even recipes below 200, until Tailoring 200 (the Artisan rank-up threshold).
- **Thresholds per tier:**

  | Trainer title | Teaches | Gate | Confidence |
  |---|---|---|---|
  | Journeyman | Apprentice | none | Guide |
  | Expert | Journeyman | skill 50 | Inferred |
  | Artisan | Expert | skill 125 | Inferred; fits your player's experience with Josef |
  | Master | Artisan | skill 200 | Player-confirmed |

- **What the trainer says or shows:** not found word for word. Players describe it as "nothing to teach" and needing 200 "to make him offer training". In-game check needed.
- **Skill, rank or character level?** Every 2026 report cites **skill** only. Whether the gate also checks your current rank or character level: not found.
- **Same for every profession?**
  - Cooking and First Aid: Apprentice and Journeyman from trainers, Expert from a vendor book, Artisan from a quest (Wowhead [Cooking](https://www.wowhead.com/forever/guide/professions/cooking/overview-leveling) and [First Aid](https://www.wowhead.com/forever/guide/professions/first-aid/overview) guides, Nov 2026).
  - Fishing: same pattern. The Expert book is *Expert Fishing - The Bass and You* (Old Man Heming, Booty Bay, skill 125 and level 20); Artisan comes from *Nat Pagle, Angler Extreme* (skill 225 and level 35) ([Method](https://www.method.gg/wow-forever/fishing-in-wow-forever-leveling-guide-fishing-items-trainers); [EpicCarry](https://epiccarry.com/blogs/wow-forever-fishing-guide/), updated 2026-11-07).
  - Gathering: Wowhead's Teaches tab shows gathering trainers with all four ranks. Whether they gate by title: not found.

### Q2. What each tier teaches (Tailoring)
See the table in section 2.
- **Can a Journeyman-level player learn Journeyman recipes at an Artisan or Master trainer?** Probably not (Inferred). Timothy offered nothing at 190 Tailoring (Expert range) even though his Teaches tab lists recipes from skill 1. By the same logic, Josef should offer nothing below 125.

### Q3. Character level per rank-up
See the table in section 3: Journeyman level 10, Expert 20, Artisan 35 (Guide, several sources agree). There is no Master rank: the skill cap is 300.

### Q4. Recipes shown vs learnable
- Below a trainer's gate, the whole list is withheld (Player-confirmed, Timothy Worthington).
- Above the gate, whether recipes you can't learn yet are greyed out or hidden: not found.

### Q5. Other trainer problems
See section 4.

### The addon's four assumptions
1. "Trainer teaches up to the rank below its title": **supported** (Wowhead guide plus Timothy reports). Josef teaching only the Expert tier fits this. Magar ("Expert Tailor") teaching the Journeyman tier fits too. The addon should also **gate the whole trainer on the threshold skill**: Expert-titled 50, Artisan-titled 125, Master-titled 200.
2. "Trainers teach every rank up to their top one" (from the Teaches tabs): **wrong for Forever.** That's Wowhead's raw data, which a 2026 comment says is out of date.
3. "No character-level requirement for rank-ups": **wrong.** Guides agree on levels 10 / 20 / 35 for crafting professions.
4. "Requires <Profession> (N)" overriding a recipe's learn level: not tested here. Note that at a gated trainer, even a recipe with a lower requirement (195) isn't offered until the gate (200).

---

## 2. Tailoring trainers

- **Title** = the NPC's subtitle on Wowhead. The Wowhead guide's "Level" column matches it.
- **Teaches tab** = ranks and recipe skill range Wowhead lists. Per the caveat above, this isn't what Forever offers.
- **Actually teaches** = by the Forever rule (Q1).
- All IDs link as `https://www.wowhead.com/forever/npc=<ID>`.

| ID | Trainer | Title | Faction | Zone | Teaches tab (ranks; recipe skill) | Actually teaches (rank; recipe tier) | Min to train (skill / level) | Source |
|---|---|---|---|---|---|---|---|---|
| 1103 | Eldrin | Journeyman Tailor | A | Elwynn Forest | Apprentice; 1-55 | Apprentice; Apprentice recipes | none / none | Wowhead data, guide |
| 1703 | Uthrar Threx | Journeyman Tailor | A | Ironforge | Apprentice; 1-55 | Apprentice | none / none | Wowhead data, guide |
| 1300 | Lawrence Schneider | Journeyman Tailor | A | Stormwind City | Apprentice, Journeyman (50), Expert (125); 1-190 | Apprentice per title, **but his Teaches tab is an outlier** | unclear | Wowhead data (conflicts with title) |
| 3523 | Bowen Brisboise | Journeyman Tailor | H | Tirisfal Glades | Apprentice; 1-55 | Apprentice | none / none | Wowhead data, guide |
| 11048 | Victor Ward | Journeyman Tailor | H | Undercity | Apprentice; 1-55 | Apprentice | none / none | Wowhead data, guide |
| 2855 | Snang | Journeyman Tailor | H | Orgrimmar | Apprentice; 1-55 | Apprentice | none / none | Wowhead data, guide |
| 4193 | Grondal Moonbreeze | Journeyman Tailor | A | Darkshore | Apprentice; 1-55 | Apprentice | none / none | Wowhead data, guide |
| 11050 | Trianna | Journeyman Tailor | A | Darnassus | Apprentice; 1-55 | Apprentice | none / none | Wowhead data, guide |
| 3484 | Kil'hala | Journeyman Tailor | H | The Barrens | Apprentice; 1-55 | Apprentice | none / none | Wowhead data, guide |
| 11051 | Vhan | Journeyman Tailor | H | Thunder Bluff | Apprentice; 1-55 | Apprentice | none / none | Wowhead data, guide |
| 252380 | Othesia Evengale | Tailor (no tier) | A and H | Zephras Isle (Valanaar) | Apprentice, Journeyman (50); 1-150 | Apprentice + Journeyman per Wowhead | unclear | Wowhead data; wow-professions lists her for both |
| 251991 | Taleen Shimmerthread | Tailor (no tier) | A and H | Zephras Isle (Shen'dar Village) | Apprentice, Journeyman (50); 1-150 | Apprentice + Journeyman per Wowhead | unclear | Wowhead data; wow-professions lists her for both |
| 3363 | Magar | Expert Tailor | H | Orgrimmar | Apprentice, Journeyman (50); 1-150 | Journeyman; Journeyman recipes | 50 (Inferred) / 10 | Wowhead data, guide |
| 5567 | Sellandus | Expert Tailor | A | Stormwind City (Larson Clothiers) | Apprentice, Journeyman (50); 1-150 | Journeyman | 50 (Inferred) / 10 | Wowhead data, guide |
| 5153 | Jormund Stonebrow | Expert Tailor | A | Ironforge | Apprentice, Journeyman (50); 1-150 | Journeyman | 50 (Inferred) / 10 | Wowhead data, guide |
| 4159 | Me'lynn | Expert Tailor | A | Darnassus | Apprentice, Journeyman (50); 1-150 | Journeyman | 50 (Inferred) / 10 | Wowhead data, guide |
| 11049 | Rhiannon Davis | Expert Tailor | H | Undercity | Apprentice, Journeyman (50); 1-150 | Journeyman | 50 (Inferred) / 10 | Wowhead data, guide |
| 3704 | Mahani | Expert Tailor | H | The Barrens | Apprentice, Journeyman (50); 1-150 | Journeyman | 50 (Inferred) / 10 | Wowhead data, guide |
| 3004 | Tepa | Expert Tailor | H | Thunder Bluff | Apprentice, Journeyman (50); 1-150 | Journeyman | 50 (Inferred) / 10 | Wowhead data, guide |
| 2627 | Grarnik Goodstitch | Expert Tailor | A and H | Stranglethorn Vale (Booty Bay) | Apprentice, Journeyman (50); 1-150 | Journeyman | 50 (Inferred) / 10 | Wowhead data, guide |
| 251972 | Charles Worth | Expert Tailor | A | Alterac Mountains (Dalaran) | Apprentice, Journeyman (50), Expert (125); 1-190 | **unclear**: his title says Journeyman, but the Teaches tab and wow-professions say up to Expert | unclear | Wowhead data; [wow-professions](https://www.wow-professions.com/forever/tailoring-trainers) |
| 4576 | **Josef Gregorian** | Artisan Tailor | H | Undercity (70.8, 29.2) | Apprentice, Journeyman (50), Expert (125); 1-190 | **Expert; Expert recipes** | **125 (Inferred)** / 20 | Wowhead data, guide; no 2026 comments on his page |
| 1346 | **Georgio Bolero** | Artisan Tailor | A | Stormwind City (Duncan's Textiles) | Apprentice, Journeyman (50), Expert (125); 1-190 | Expert; Expert recipes | 125 (Inferred) / 20 | Wowhead data, guide |
| 11052 | **Timothy Worthington** | Master Tailor | A | Dustwallow Marsh (Theramore) | Apprentice-Artisan (200); 1-210 | **Artisan; Artisan recipes** | **200 (Player-confirmed)** / 35 | 2026 comments on his page |
| 2399 | Daryl Stack | Master Tailor | H | Hillsbrad Foothills (Tarren Mill) | Apprentice-Artisan (200); 1-210 | Artisan; Artisan recipes | 200 (Inferred from Timothy) / 35 | Wowhead data, guide |
| (no ID found) | Melanori | special trainer | ? | Shen'dralas | not checked | Apprentice through Expert per wow-professions | Needs 5 quests first (see section 4) | [wow-professions](https://www.wow-professions.com/forever/tailoring-trainers) (undated) |

**Where sources disagree:**
- [Method](https://www.method.gg/wow-forever/tailoring-in-wow-forever-1-300-leveling-guide-and-trainers) (2026-11-16) lists "max rank trained": Expert-titled trainers → Journeyman, Josef/Georgio → Expert, Timothy/Daryl → Artisan. That matches the rule.
- Wowhead's guide and the NPC subtitles agree on every title above. Lawrence Schneider and Charles Worth have Teaches tabs that don't fit their titles; check them in game.

---

## 3. Character level per rank-up

| Rank (skill cap) | Skill to train | Crafting char. level | Gathering char. level | Sources |
|---|---|---|---|---|
| Apprentice (75) | none | Wowhead 1; Method 0; wow-professions none; icy-veins 5 | icy-veins none | conflict: most say none |
| Journeyman (150) | 50 | 10 | icy-veins none | Wowhead, Method, icy-veins, wow-professions agree |
| Expert (225) | 125 | 20 | icy-veins 10 | Wowhead, Method, icy-veins, wow-professions agree for crafting |
| Artisan (300) | **Wowhead 225; Method, icy-veins, wow-professions 200** | 35 | icy-veins 25 | Timothy reports (2026-11) show training offered at **200** |
| Master | not a rank in Forever | - | - | Wowhead lists only 4 ranks, cap 300 |

Sources:
- Wowhead's [Professions Overview](https://www.wowhead.com/forever/guide/professions/overview) table ("Min. Skill to Train / Min. Level to Train": 1/1, 50/10, 125/20, 225/35; page about 4 days old).
- [Method Tailoring](https://www.method.gg/wow-forever/tailoring-in-wow-forever-1-300-leveling-guide-and-trainers) (2026-11-16).
- [icy-veins Professions](https://www.icy-veins.com/wow-forever/professions-overview) (2026-09-29, pre-launch).
- [wow-professions](https://www.wow-professions.com/forever/tailoring-trainers) (undated).

Secondary professions use the same thresholds, with Expert from a book and Artisan from a quest (see Q1).

---

## 4. Other trainer problems players report

- **Wowhead Teaches tabs are out of date for Forever:** [Timothy Worthington](https://www.wowhead.com/forever/npc=11052), comment 2026-11-14.
- **Expert Blacksmithing won't train:** [Blizzard forum thread](https://us.forums.blizzard.com/en/wow/t/cant-train-blacksmithing-beyond-150/2407596).
  - 2026-11-09: a player meets level 20 and 125 skill, yet "nobody is giving it to me".
  - 2026-11-18: a level 34 player with 140 Blacksmithing has the same problem.
  - One reply says the Expert quest chain "appears to start at level 45". Unconfirmed, and no Blizzard reply.
- **Quest-gated trainer:** Melanori (Shen'dralas) can't be spoken to until you finish five quests: Strange Pylons, Fragments of the Pylons, Powering the Pylons, A Brief History Lesson, Meeting the Magister. The author isn't sure it's intended. [wow-professions](https://www.wow-professions.com/forever/tailoring-trainers) (undated).
- **Trainer without a map icon:** Othesia Evengale (Zephras Isle) "was not showing as a trainer icon on the minimap" ([Wowhead comment](https://www.wowhead.com/forever/npc=252380), 2026-11-06).
- **Trainer in a dungeon:** Annora, the Artisan Enchanting trainer, is inside Uldaman behind trash ([Wowhead comments](https://www.wowhead.com/forever/npc=11073), 2026-11-20).
- **Specialization trainers:** the five Classic leatherworking specialization trainers (7866-7870) teach no rank in Forever, per Wowhead data (from the earlier check).
- **Secondary professions:** no trainer teaches Expert or Artisan Cooking, First Aid or Fishing; those come from a book and a quest (Wowhead Cooking and First Aid guides; Method Fishing). Katoom the Angler teaches only Apprentice and Journeyman.
- **"Send you elsewhere" gossip:** Wowhead's guide says trainers that have nothing left to teach direct you to the next trainer. The exact text: not found.
- **Faction or race-only trainers:** none reported for Forever. Faction-specific patterns can't be sold on the combined auction house ([comment on the Wowhead Tailoring guide](https://www.wowhead.com/forever/guide/professions/tailoring-overview-trainer-locations-recipes), about 13 days old).
- **Classic only, not confirmed for Forever:** in 2019-2020 Classic, Journeyman Tailoring was trainable only at an Expert-titled tailor ([thread](https://us.forums.blizzard.com/en/wow/t/cant-learn-journeyman-tailoring/276971)). An Expert trainer also told a 75/75 tailor they "need to be 80/80" ([thread](https://us.forums.blizzard.com/en/wow/t/where-to-train-expert-tailoring/534942)). Same pattern as Forever, but these are Classic reports.

---

## 5. Still needs an in-game check
1. Talk to Josef Gregorian at Tailoring 120 and copy his gossip text, then again at 125 and note whether the Train option appears.
2. At 125, open Josef's trainer window: are Expert recipes above your skill (e.g. 150+) greyed out or hidden?
3. Talk to Magar at Tailoring 45 and at 50; copy the message and note when he offers training.
4. Talk to Timothy Worthington or Daryl Stack at 195 and copy the exact "nothing to teach" text.
5. Learn Artisan at 200 vs 225, to settle the Wowhead (225) vs other guides (200) conflict.
6. At 125 skill, try to learn Expert at character level 19 and then 20; copy any level message.
7. Ask Lawrence Schneider and Charles Worth to train at 125 to see whether either teaches Expert.
8. Talk to an Expert-titled trainer of a gathering profession (e.g. a Mining trainer) at skill 40 to see whether gathering trainers gate the same way.
9. Ask an Expert Blacksmithing trainer to train at level 20 with 125 skill; if refused, look for a quest giver and its level.
