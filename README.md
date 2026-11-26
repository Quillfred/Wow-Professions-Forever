# SkillRoute

A WoW Forever addon that plans the cheapest way to level a crafting profession.

## Getting started
1. **Install:** put the `SkillRoute` folder in `World of Warcraft/_classic_/Interface/AddOns/`
   (whichever game folder Forever uses). [Auctionator](https://www.curseforge.com/wow/addons/auctionator)
   is recommended (prices, Buy buttons); without it, use SkillRoute's own **Scan AH** button. TomTom is optional
   (better waypoints).
2. **Scan the auction house** once (Auctionator's scan, or **Scan AH** in SkillRoute's window
   while the AH is open), so SkillRoute has prices.
3. **Open your profession window**: SkillRoute opens next to it (or type `/sr`, or click
   the minimap button). Pick the profession with the arrows and set your target skill.
4. **Read the route top to bottom.** Each row is a step: how many to craft, from what,
   and where the recipe comes from. Rank-ups (train, book or quest) appear where you
   need them.
   - **Hover** a step for details: cost per craft, the skill levels where it's orange,
     yellow and green, why it was picked, where to learn it and what to do with what you
     make.
   - **Click** opens the recipe (if you know it) or sets a waypoint; **right-click** skips
     a recipe you can't get and re-plans without it.
5. **Shopping list** (button at the top) is everything to buy, with what you already
   have (bags, bank, alts) taken off. With the auction house open, **Buy** on a step puts
   its reagents in an Auctionator list and opens the Shopping tab.
6. **Options** (button, or right-click the minimap button): safety margin, expect to sell
   what you make, prefer fewer crafts, alts, estimates. `/sr help` lists the commands;
   `/sr check` checks everything works.


- **Recipe data comes from the Forever client itself** (build in `SkillRoute/Data.lua`),
  not from Classic. Forever moved many skill-up ranges, which is why Classic-based
  guides and addons disagree.
- **Prices come from the freshest AH scan:** Auctionator's or SkillRoute's own (**Scan AH**,
  one search for the whole AH), item by item. Thread and dyes use the vendor price. An
  item not on the AH that you bought recently is priced at what you paid (hover it in the
  shopping list to see the source and age).
  Recipes whose reagents have no price are skipped and counted. Prices are never
  guessed unless you turn on `/sr estimate on`, and estimates are marked in orange.
- **Cheapest expected cost:** each skill point is planned with the classic skill-up
  chance (orange 100%, falling linearly from yellow to grey).
- **Uses what you own:** the shopping list subtracts bags and bank, and reuses
  products of earlier steps (for example bolts) in later ones.
- **Learn levels and sources from Wowhead** (`tools/wowhead_forever.json`): the skill
  each recipe is learned at (so cheap orange windows are used), trainer costs, and
  where patterns come from. The trainer window in game still overrides this if it
  disagrees.
- **Gathering professions:** Mining and Herbalism get a route of which node to gather
  in which zones for each skill range (node skill from the client, spawns from Classic
  data); rare ores (Silver, Gold, Truesilver) are "when you see them". Skinning names
  the beast levels to skin. Fishing: the catches needed per range (server rule: a point
  per catch below 75, then 25 / (skill - 50)) and the zones where no fish get away.
  Ranks no trainer teaches (Expert First Aid / Cooking / Fishing books, the Artisan
  quests) show the book's vendor or the quest giver.
- **Farming Cooking ingredients:** raw meat and fish the AH has no price for are planned
  as "Farm 20 x Boar Ribs: Goretusk (lvl 14-15, 29%) in Westfall" (or the fishing
  zones), not counted in what you spend; each kill/catch counts as a little of your time.
  Your faction's zones are listed first, then contested ones; the other faction's
  zones come last, marked "(Alliance)"/"(Horde)", and only count when nowhere else
  has the item (whose zone it is comes from Forever's own zone table). Mining,
  Herbalism, Skinning and Fishing zones are ordered the same way, and node/fishing choices
  count the other faction's zones only when nothing else fits.
- **Recipes taught by quests** ("Camping 101", Blacksmithing's Ornate Mithril quests):
  learnable when AllTheThings names a giver of your faction; the step names the quest
  and giver, with a waypoint. A quest counts as 1g of effort when choosing (time, and
  materials the data doesn't list), never in what you spend.
- **At the auction house**: each route step has a Buy button. Without Auctionator it
  searches the AH's own search box for the step's materials, one per click. With Auctionator it
  puts its reagents (crafts still needed x per craft, with your safety margin, minus
  what you have; vendor items left out) into the Auctionator list "SkillRoute
  <profession> (steps)". Clicking again updates the step; right-click removes it.
- **Crafted items in your bags** (shopping list, fresh AH prices only): list on the AH,
  disenchant (enchanters with the skill; results at AH prices) or sell to a vendor,
  whichever brings most. Disenchant results: Forever's brackets (ItemDisenchantLoot)
  with the Classic loot tables (cMaNGOS); the skill needed follows the Classic rule.
- **Data recorder** (`/sr log on`): while you play, records what the game tells addons
  about the data SkillRoute can't confirm offline. That covers trainer windows (what's
  offered, greyed out, skill/level needed, the trainer's text), vendors (stock, limited,
  usable), disenchants (item, item level, results, skill errors), fishing (casts,
  catches, "got away" per zone), gathering, and boat marks (`/sr log boat`). A small
  window lists the checks and ticks each off as it's done (`/sr log skip` skips one).
  Afterwards send `WTF/Account/<account>/SavedVariables/SkillRoute.lua`.
- **All crafting professions:** Alchemy, Blacksmithing, Cooking, Enchanting,
  Engineering, First Aid, Leatherworking and Tailoring. The window shows the ones
  your character has; switch with the arrows.
- **Tools:** recipes that need a rod, hammer, spanner or Philosopher's Stone are
  only planned once you own one, or the route gets one first: bought (a vendor's
  Blacksmith Hammer) or crafted by the profession itself (enchanting rods), whichever
  is cheaper. A tool in the bank doesn't count; keep it in your bags.
- **Buys vendor patterns when they pay off:** a vendor pattern is bought when it
  makes the whole route cheaper, its price included (each one is checked with a full
  re-plan), or when no trainer recipe covers a range (Tailoring 255-300). Drop
  patterns count too when Auctionator has seen them on the AH (never on an estimated
  price). Recipes with cooldowns (crafting Mooncloth) are never planned.
- **Cooldown materials:** recipes that use materials only made by cooldown crafts
  (Mooncloth, Arcanite Bar, Legionite Bar) are left out, since those are scarce and
  expensive. `/sr cdmats on` includes them.
- **Reputation:** patterns that need faction reputation (e.g. Cenarion Circle
  Honored) are only planned once your character has it, read live in game. Until
  then, gap suggestions say which standing they need.

## Install
Copy the `SkillRoute` folder into `World of Warcraft/_forever_/Interface/AddOns/`
(the folder next to your other addons).

## Use
- The window opens by itself when you open a crafting profession window, and
  closes with it. Opened with `/sr` or the **Route** button, it stays open until you
  close it. `/sr auto off` turns the automatic opening off.
- Set **Target**, then switch between **Route** and **Shopping list**.
- Hover a step to see why it was picked and what the next-best option costs.
- `/sr overtime <pct>` Working Overtime bonus, only used if your Legacy Tree can't be read
  (normally it's read from the game, per character).
- `/sr estimate on|off` turns price estimates for unpriced items on or off.
- `/sr cdmats on|off` includes recipes using Mooncloth / Arcanite Bar (default off).
- **Minimap button:** left-click opens SkillRoute, right-click the options, drag to
  move it. `/sr minimap off` hides it.
- **Options window** (right-click the minimap button, the Options button, or
  `/sr options`): every setting below, with checkboxes and sliders.
- `/sr check` lists what your client offers SkillRoute and runs a self-test.
- `/sr margin <50-99>` how often the shopping list should be enough to finish
  (default 90; 50 = the expected amount).
- `/sr ah` (or the button in the shopping list) sends the list to Auctionator.
- **Mini panel** (default): opens docked to the profession window with the next step,
  Craft 1 / Craft all and what's next; Options "Dock a mini panel" switches back to the
  full window. **At the trainer**, a panel lists the route's recipes there with Learn
  buttons. **At the bank**, "Take route mats" moves the next 3 steps' materials of each
  of your crafting professions to your bags. A reminder appears when a profession hits a rank cap you need to pass.
- `/sr scan` (or **Scan AH**, with the auction house open) scans the AH for prices.
- `/sr craftcost <copper>` prefer fewer crafts: the extra material cost you accept per
  craft saved (route choice only, never charged).
- `/sr resale <0-100>` expect to sell what you make: count that share of its AH price as
  money back when choosing recipes.
- `/sr alts on|off` count materials on your other characters (Syndicator / DataStore).
- Click a step whose recipe you know to open it in your profession window.
- **Right-click a step** to skip that recipe (e.g. its pattern isn't for sale) and
  re-plan without it; `/sr unskip` brings skipped recipes back. Patterns are only
  "on the AH" if Auctionator saw one today or yesterday.

**Where to go:** "Train Expert" rows and "Buy pattern from ..." steps name the trainer /
vendor for your faction that is quickest to reach (running, the boats and zeppelins your
faction can use, the flight paths you know — open any flight master's map once so
SkillRoute can see which ones — your hearthstone, counting its cooldown, and a mage's
teleports when you carry a Rune of Teleportation), with zone and map coordinates (Classic NPC data;
the zone is resolved by the game's own map, so it matches your map). **Click** the
row to set a waypoint: TomTom if installed, else the game's map pin, else the
coordinates in chat.

**Faction:** a pattern is only "bought from a vendor" if a vendor of your faction sells
it (vendor lists from the cMaNGOS Classic database, factions from Forever's own
tables; a vendor you visit overrides this). Patterns new in Forever are flagged
"vendor faction unverified". Other-faction patterns can still be bought on your AH.

**Trainers and vendors:** when you talk to a profession trainer or a vendor that sells
patterns, SkillRoute notes the NPC's name, zone and map coordinates (and which rank
the trainer teaches, or the pattern's price and whether stock is limited). From then
on "Train Expert" and "Buy pattern" steps say who and where. Shared by your
characters of the same faction.

For the best plan: scan the AH with Auctionator, open your profession window once,
and visit your trainer once.

## Updating the data after a patch
One step (downloads game tables, AllTheThings' Forever folder and the Classic
database, runs every importer, regenerates Data.lua, runs the tests):
```
tools/build_all.sh            # newest Forever build
tools/build_all.sh 1.60.1.71037
```
The individual steps, if you need one:
```
python3 -I tools/import_wowhead.py wow-forever-recipes.json   # optional: new Wowhead export
python3 -I tools/import_sources.py blank-source-recipes.csv   # optional: sources Wowhead left blank
python3 -I tools/import_vendors.py ClassicDB_*.sql.gz FactionTemplate.csv   # optional: vendor factions
(cd tools && python3 import_npcs.py ClassicDB_*.sql.gz WAGO_CACHE BUILD)     # optional: trainer/vendor locations
python3 -I tools/import_att.py ATT/.contrib/.db/forever WAGO_CACHE BUILD     # optional: AllTheThings Forever NPCs
(cd tools && python3 import_gather.py ClassicDB_*.sql.gz WAGO_CACHE BUILD)  # optional: herb/ore zones
(cd tools && python3 import_farm.py ClassicDB_*.sql.gz WAGO_CACHE BUILD)    # optional: where to farm ingredients
python3 -I tools/gen_data.py            # newest Forever build on wago.tools
python3 -I tools/gen_data.py 1.60.1.71037
```

## Tests
```
lua5.1 tests/test_planner.lua   # planner rules + optimality check on real data
lua5.1 tests/smoke_wow.lua      # whole addon against a fake WoW API
```

## Data sources
- Recipes, reagents, skill thresholds, tools, cooldowns, factions, flight paths: WoW Forever client
  tables via wago.tools.
- AllTheThings' Forever database (MIT, see THIRD_PARTY_NOTICES.md) first, for everything
  it covers: how each recipe is learned (trainer, pattern, quest, specialisation, not
  released yet), learn levels, how each rank is learned (trainer, book or quest, with the
  quest giver), trainers and the recipe tier each teaches, pattern vendors, and exact
  Forever coordinates.
- Wowhead (exported by hand): learn levels (its "Requires (N)", checked on Forever
  pages: ATT's numbers were often the yellow level), trainer costs, and sources for
  recipes AllTheThings doesn't list or where Wowhead's Forever page was checked and
  wins (tools/source_overrides.json, with the evidence). Recipes ATT calls unreleased
  are used only if their pattern is really on your auction house.
- cMaNGOS Classic database (github.com/cmangos/classic-db, GPL v3) for what AllTheThings
  doesn't have: other vendors/trainers and NPC positions, vendors of reagents and tools
  (unlimited stock, no reputation, not holiday-only), boats/zeppelins, herb/ore
  spawns, fishing loot, mob drops for farming, and skinnable beasts — Classic data,
  checked against Wowhead's Forever pages (445 pages, 2026-11-23): the corrections are
  in tools/forever_checks.json (applied on every rebuild), the report in
  tools/forever-classic-check-2026-11-23.md. Herb/ore zones, fishing zones and
  disenchant results now use Forever's own observed data.

## License
Copyright (C) 2026 Quillfred and SkillRoute contributors.

SkillRoute is free software: you can redistribute it and/or modify it under the terms of
the **GNU General Public License version 3**, as published by the Free Software
Foundation (full text in `LICENSE`). It is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.

It's GPL v3 because it includes data derived from cMaNGOS Classic-DB (GPL v3). Other
sources and their licenses are in `THIRD_PARTY_NOTICES.md`. World of Warcraft is a
trademark of Blizzard Entertainment; SkillRoute isn't affiliated with Blizzard.
