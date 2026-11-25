# Changelog

## 0.35.0 (beta)

- **SkillRoute's own AH scan:** a **Scan AH** button (and `/sr scan`) while the auction
  house is open reads the lowest price of everything listed in one search. Auctionator is
  no longer required for prices.
- **Freshest price wins:** per item, SkillRoute uses whichever is newer, its own scan or
  Auctionator's.
- **What you paid:** AH purchases of stackable goods are remembered. An item that isn't on
  the AH now is priced at what you last paid (within 30 days). Hover an item in the
  shopping list to see its price, where it came from and how old it is, and what you paid.
- **Working Overtime is read from your Legacy Tree** (at login, after loading screens and
  when you change it), so there's no slider any more. `/sr overtime <pct>` is only used if
  the tree can't be read.

## 0.34.1 (beta)

- Options: the two route sliders are reworded so they no longer read like a charge.
  - **Expect to sell what you make** (was "Count crafted items as sold on the AH"): the
    value reads "45% of AH price", with a caution about listing many at once.
  - **Prefer fewer crafts** (was "What a craft's time is worth"): the value reads
    "up to 44s"; nothing is ever charged.
  - Both have end labels and a live example that changes as you drag, so you can see
    where the choice flips.
- **Shopping list safety margin** explained: the value reads "90% sure", with end labels
  and a live example of how much extra it buys.
- **Working Overtime** is now saved per character (it's a talent); your current value
  moves to the first character you log in with.
- Options: separators between options; the caution sits right under its example.
- Fixed: the Options button (and /sr before a profession window was opened) needed two
  clicks the first time.

## 0.34.0 (beta): first public release

SkillRoute Forever plans the cheapest way to level any profession in WoW Forever, from the
game's own recipe data and your Auctionator prices.

- Routes for every crafting profession (Alchemy, Blacksmithing, Enchanting, Engineering,
  Leatherworking, Tailoring, Cooking, First Aid), planned per skill point with real
  skill-up chances, using what's in your bags, bank and on your alts.
- Trainers, vendors and quest givers by name and location, nearest for your faction, with
  travel time (flight paths, boats, zeppelins, hearthstone) and click-to-waypoint (TomTom
  or the map pin).
- Forever's rules: trainers teach the rank below their title and only from its skill level;
  rank-ups by book or quest where Forever does it that way; character-level warnings;
  specialization recipes only if you have the spec.
- Patterns from vendors of your faction or the auction house, with reputation checks;
  patterns you already own count as free.
- Tooltips: cost per craft, the levels where a recipe is orange / yellow / green, why it
  was picked over the next best, where to learn it, and whether to sell, disenchant or
  vendor what you make.
- Shopping list with a safety margin; at the auction house, a Buy button per step opens
  Auctionator's Shopping tab with the amounts you need.
- Farming spots for Cooking ingredients the AH doesn't have; Mining, Herbalism, Skinning and
  Fishing routes with zones sorted by faction.
- Minimap button, options window, `/sr check` self-test.

Known limits: Forever is new, so some trainer, vendor and drop data is still being
confirmed; opening a trainer or vendor window corrects it for you. Some names are
English-only.
