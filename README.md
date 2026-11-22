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
- **Vendor patterns fill gaps:** where no trainer recipe exists (Tailoring 255-300),
  the route buys plain vendor patterns (price counted once). Patterns that need
  reputation, and recipes with cooldowns (Mooncloth), are never planned.

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
