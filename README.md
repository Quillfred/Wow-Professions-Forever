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
- **All crafting professions:** Alchemy, Blacksmithing, Cooking, Enchanting,
  Engineering, First Aid, Leatherworking and Tailoring. The window shows the ones
  your character has; switch with the arrows.
- **Tools:** recipes that need a rod, hammer, spanner or Philosopher's Stone are
  only planned once you own one, or the route gets one first: bought (a vendor's
  Blacksmith Hammer) or crafted by the profession itself (enchanting rods), whichever
  is cheaper. A tool in the bank doesn't count; keep it in your bags.
- **Buys vendor patterns when they pay off:** a vendor pattern is bought when it
  makes the whole route cheaper, its price included (each one is checked with a full
  re-plan), or when no trainer recipe covers a range (Tailoring 255-300). Recipes
  with cooldowns (Mooncloth) are never planned.
- **Reputation:** patterns that need faction reputation (e.g. Cenarion Circle
  Honored) are only planned once your character has it, read live in game. Until
  then, gap suggestions say which standing they need.

## Install
Copy the `SkillRoute` folder into `World of Warcraft/_forever_/Interface/AddOns/`
(the folder next to your other addons).

## Use
- `/sr` opens or closes the window. The **Route** button on the profession window
  does the same.
- Set **Target**, then switch between **Route** and **Shopping list**.
- Hover a step to see why it was picked and what the next-best option costs.
- `/sr overtime <pct>` sets your Working Overtime talent bonus.
- `/sr estimate on|off` turns price estimates for unpriced items on or off.

For the best plan: scan the AH with Auctionator, open your profession window once,
and visit your trainer once.

## Updating the data after a patch
```
python3 -I tools/import_wowhead.py wow-forever-recipes.json   # optional: new Wowhead export
python3 -I tools/gen_data.py            # newest Forever build on wago.tools
python3 -I tools/gen_data.py 1.60.1.71037
```

## Tests
```
lua5.1 tests/test_planner.lua   # planner rules + optimality check on real data
lua5.1 tests/smoke_wow.lua      # whole addon against a fake WoW API
```
