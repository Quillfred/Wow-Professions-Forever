# SkillRoute

A WoW Forever addon that plans the cheapest way to level a crafting profession.

- **Recipe data comes from the Forever client itself** (build in `SkillRoute/Data.lua`),
  not from Classic. Forever moved many skill-up ranges, which is why Classic-based
  guides and addons disagree.
- **Prices come from your Auctionator scan.** Thread and dyes use the vendor price.
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
  the beast levels to skin. Fishing isn't planned.
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
- `/sr overtime <pct>` sets your Working Overtime talent bonus.
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
- `/sr craftcost <copper>` what a craft's time is worth to you (route choice only).
- `/sr resale <0-100>` count crafted items as sold on the AH at that share of their price.
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
- Learn levels, sources and trainer costs: Wowhead (exported by hand).
- Trainers (and the recipe tier each teaches), pattern vendors and their exact Forever
  coordinates: AllTheThings' Forever database (MIT, see THIRD_PARTY_NOTICES.md).
- Fallback where AllTheThings has nothing yet — vendors, trainers, NPC positions,
  boats/zeppelins: derived from the cMaNGOS Classic database
  (github.com/cmangos/classic-db, GPL v3) — Classic data, so Forever may differ.
