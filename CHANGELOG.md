# Changelog

## 0.35.0 (beta)

- **SkillRoute's own AH scan:** a **Scan AH** button (and `/sr scan`) while the auction
  house is open reads the lowest price of everything listed in one search. Auctionator is
  no longer required for prices. The button sits on the auction house window's title bar
  (and on the full SkillRoute window) and shows the scan's progress.
- **Freshest price wins:** per item, SkillRoute uses whichever is newer, its own scan or
  Auctionator's.
- **What you paid:** AH purchases of stackable goods are remembered. An item that isn't on
  the AH now is priced at what you last paid (within 30 days). Hover an item in the
  shopping list to see its price, where it came from and how old it is, and what you paid.
- **Mini panel** docked to the profession window: the next step, its materials (have /
  need), **Craft 1** and **Craft all**, the two steps after it and what's left to buy. It
  opens instead of the full window (Options: "Dock a mini panel"); **Full route** opens it.
- Fixed: a recipe recorded as known once (e.g. the Runed Golden Rod) stayed known even
  when the profession window lists it as not learned. The window's answer now wins.
- Fixed: the mini panel showed 0 of every material (so no Craft buttons) on clients
  without the old GetItemCount; the bank button had the same problem.
- Mini panel: hover the step for the full route's tooltip; an **Afterwards** line says
  what to do with what you make; when you're short of materials it says what the rest
  costs on the AH, with a **Buy** button while the AH is open.
- Fixed: the trainer panel's Learn buttons stayed disabled at the right skill (the
  client reports learnable recipes differently); it now goes by your skill and level.
- The mini panel docks past the profession window's side tabs; drag it anywhere
  (remembered), right-click it to dock again. Tools you craft get Craft buttons and say
  which trainer teaches them.
- **At the trainer:** a "your route here" panel lists the recipes this trainer has that
  your route uses, with the skill range each is for, the cost, **Learn** and **Learn all**.
- **Rank-up reminder:** when a profession hits 75, 150 or 225 and your target is higher,
  SkillRoute says what to do next (trainer, book or quest), where, and how far.
- **At the bank:** **Take <profession> mats** moves what your next 3 steps still need from
  the bank into your bags (whole stacks). Works with bank tabs and with bag addons that
  replace the bank window: it docks above the bank window you can see, or floats where you
  can drag it. `/sr bank` shows what it found.
- **Essences:** 3 lesser = 1 greater, so each is priced at the cheaper form, and the
  shopping list says when to buy the other one and split or combine.
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
