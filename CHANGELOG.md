# Changelog

## 0.38.7 (not released yet)

- **Smelting in the Mining route:** smelting ore gives Mining skill too (checked in
  game), so the route now has you smelt the ore you mine as you go: "~23 x Copper Vein,
  smelting the ore as you go" instead of ~80 veins for 1-65 (a vein gives ~3 ore: Classic
  data, 2-4 mines a node). Ore already in your bags comes first: "Smelt 12 x Copper Ore",
  with Craft 1 / Craft all at a forge. Only where smelting gives skill (Forever: up to 140,
  then 155-185); mining only from 140 to 155 and after 185. Each step's tooltip (and the
  tracker) also gives the other way: "or buy ~107 Copper Ore on the AH (~X) and smelt".
  The whole Mining route drops from ~339 to ~270 veins.
- Mining route: a step with an alternative node ("or Poor Copper Vein") says "+ smelt"
  instead of being cut off; the mini panel shows "Nodes in all" (not "Left to buy 0c")
  while you smelt your bag ore.
- Mining: away from a forge, the mini panel and the tracker show the vein step first; the
  ore in your bags becomes a line under it ("Smelt 12 x Copper Ore at a forge"), yellow
  once waiting would cost sure skill-ups ("soon: a sure skill-up each only until 46").
  With the Mining window open at a forge, the smelt step comes first with its Craft
  buttons.
- Mini panel: Craft buttons stay off when the recipe needs a forge, anvil or rod you
  aren't at or don't carry ("Needs: Anvil"). `/sr check` lists the API this uses.
- Mini panel: walking up to a forge (or away) with the profession window open now
  switches between smelting and mining within half a second; before, you had to close
  and reopen the window.
- Mining: Bronze, only when another of your professions' routes uses Bronze Bars
  (Blacksmithing, Engineering), and only as many as it needs. The Tin Vein steps then say
  "smelting the ore into Bronze", with how many bars, for which route, and the Copper Ore
  to buy for them (each Bronze needs a Copper Bar and a Tin Bar). Bars or ore already in
  your bags become a "Smelt N x Bronze" step with Craft buttons at a forge. Bronze is a
  chance at a skill-up from 65 to 115: with plenty of bars wanted, 75-125 drops from
  ~62 Tin Veins to ~39.
- Tooltips no longer name websites or other addons: gathering zones are just "most spots
  of this node", the shopping list says when a price was seen (not where from), and the
  Buy and Scan AH tooltips describe what they do. Nothing changes in how prices, alts or
  waypoints work.
- No other addon is named anywhere in SkillRoute now: the window header says "SkillRoute
  scan + AH addon prices", the button is "Send to AH list", and chat messages and
  `/sr check` say "AH addon", "waypoint addon" and so on.
- Mining: the Amber chunks in Teldrassil are counted as Copper Veins (they are one in
  game), so Copper Vein lists Teldrassil. Each node now keeps its top 16 zones instead of
  6, so your side's starting zones make the list (Durotar, Tirisfal, Teldrassil). With
  Mithril's spots fully counted, the route mines Mithril until 242 rather than switching
  to Dark Iron (only in Burning Steppes and Searing Gorge) at 230.
- Gathering routes start with the tool when you don't have one: "Buy 1 x Mining Pick
  (tool)", "Skinning Knife" or "Fishing Pole" (equipped), with the nearest vendor and a
  waypoint, and it's on the shopping list. From the game's own spell data, so a Forever
  item that counts (its multi-tool) counts too. Herbalism needs no tool. Crafting routes
  already did this for hammers, spanners and rods.
- Every crafting profession: the station a recipe needs comes from the game's data (811
  recipes: Anvil, Forge, Master Forge, Loom, Sewing Machine, Cooking Fire...). The step's
  tooltip says "Craft at an Anvil", the tracker "Ready to craft: at an Anvil, open
  Blacksmithing". The mini panel's Craft buttons stay off until you're at it ("Needs:
  Anvil", or a missing Blacksmith Hammer), and come on within half a second when you
  walk up, with the window open.
- Gathering routes in the mini panel and tracker: the step now says where to go (its
  three best zones, your faction's first), counts as a step ("13 steps left"), and the
  Craft buttons and "Left to buy" make way for "Nodes in all". A gathering step's tooltip
  says it counts nodes: one skill-up per node, however many times you gather it.
- A gathering step names an alternative needing the same skill: "Copper Vein (or Poor
  Copper Vein)" (Forever's starting-zone copper), Peacebloom's Wilted Peacebloom, etc.
- Fixed: on the full route, a gathering step's "when you see them" list ran off the end
  of the line. It now says "+ 2 more when you see them"; the step's tooltip lists them,
  with the alternatives and its zones.
- **Mining and Herbalism from Forever's own maps:** the gathering routes now use the
  herb and ore spots on Wowhead's WoW Forever maps (27,800 spots in 46 zones) instead of
  Classic spawn data. 32 nodes SkillRoute didn't know are in: Forever's Heavy Thorium
  Vein, Cold Iron Deposit, Starsilver Vein, Fool's Gold Vein, Greater Moonstone, Amber,
  Demonsage, Marefoil, Dreamroot, Moonroot and others, plus Black Lotus and the Ooze
  Covered veins (shown as "gather when you see them"). Zones are ranked by real spot
  counts: The Barrens now features for Mageroyal, Briarthorn and Bruiseweed, Mount Hyjal
  for Rich Thorium. The skill each node needs matches the game's own tables.
- Data: AllTheThings reorganised its Forever database; SkillRoute's importer reads the new
  layout. 33 materials gain vendors (no vendor lost), 36 more recipe sources and 7 more
  learn levels, NPC positions refreshed. Trainer tiers stay as checked in game: ATT's new
  trainer tags don't reliably say which rank a trainer teaches.
## 0.38.6

- **Waylaid Crate helper:** hovering a Waylaid Crate shows every bundle it accepts at
  today's AH prices, cheapest first, which ones you already have in your bags ("Dream
  Dust: ready now"), what it pays in Merchant's Favor and the cost per Favor, a warning
  when a bundle uses something one of your routes needs, the level it needs, where to
  hand it in (Dokimi / Marcy Baker), and the one-time +50 Favor bonus if you haven't had
  it yet. Gathering crates pay 5/10/15/20 Favor, crafted crates 10/20/30/40.
- The route's Merchant's Favor note says how much reputation a pattern still needs
  ("Black Handwraps (needs Friendly, 1,000 rep)"); hover it for each pattern's Favor,
  reputation and saving, and what the Favor you're short would cost in crate materials,
  per crate tier you can use (which crates drop depends on the mobs you fight).
- Game data rebuilt for Forever build 1.60.1.71139: adds Centaur Hoofwarmers
  (Tailoring 170-180, a pattern). The other Favor recipes not in SkillRoute all need
  skill 300 to learn, so they can't give a skill-up and are left out on purpose.
## 0.38.5

- Fixed: the full route window and the options window went back to the middle of the
  screen after a reload. They now open where you last dragged them.
- **Fixed: Merchant's Favor patterns.** Forever's profession vendors in the Barrens
  (Horde) and Redridge Mountains (Alliance) sell their patterns for Merchant's Favor
  only, but SkillRoute priced about 290 of them in gold, so a route could plan on
  patterns you can't buy with gold. Now:
  - a Favor pattern costs no gold and is only used within your Favor balance, and only
    with the reputation it needs with your side's trade faction (184 of 315 need
    Friendly or Honored), Cooking's Smoothies included
  - the route says where: "Buy pattern from Jim'bek (60 Favor)", with a waypoint, and
    its tooltip shows your balance and any reputation needed
  - the shopping list shows "60 Favor" instead of a gold price
  - the route's header shows your Favor; patterns that would save gold but need more
    Favor or reputation are listed there
  - a vendor visit records the Favor price you see, which wins over the data
  Sources: costs and vendors from AllTheThings (MIT), reputation from Wowhead Forever's
  item tooltips (tools/import_favor.py, tools/fetch_favor_rep.py).
- **Keep the mini panel on screen** (Options, General; off by default). Away from the
  profession window, the next step stays on screen like the quest list: see-through,
  text only. You get the step, its materials as objectives ("- 4/51 Bolt of Silk Cloth",
  "vendor", "1 in the mail"), the step's AH cost, and what comes next. It hides while the
  profession window is open (the docked mini panel takes over) and comes back when it
  closes, showing the profession you had open last. Drag its header to move it (saved),
  "-" folds it to one line, click the step for its waypoint or the full route, hover for
  the full tooltip (shown beside the tracker, never over it).
- **Notices** (Options, General; on by default): one notice in the middle of the screen,
  with a sound, when a step's materials are all in your bags ("Azure Silk Cloak is ready
  to craft"), when you reach a rank cap ("Tailoring 225 reached: Train Artisan at Daryl
  Stack…"), and when you reach your target. Watching for them doesn't re-plan the route
  on every loot; materials are counted straight from your bags.
- **TSM prices:** with TradeSkillMaster installed, items that neither SkillRoute's scan
  nor Auctionator has priced use TSM's price (its latest scan's lowest price, else its
  market value). Your own scan and Auctionator still come first. TSM's market value is
  used as a price only, never as "for sale now", so no pattern is bought because TSM
  remembers one. `/sr check` lists it.
## 0.38.4

- Fixed: the trainer panel only listed recipes for skill-up steps, so a tool your route
  crafts (Runed Truesilver Rod) wasn't offered at the trainer. It's now listed, before
  the step that needs it, as "Runed Truesilver Rod (tool) - needed from 210", with a
  Learn button and in Learn all.

## 0.38.3

- **Buying panel: one-of-a-kind items** (rods, tools, AH patterns) can now be bought
  from SkillRoute's panel instead of "Search". Price finds the cheapest listing that
  isn't yours; Buy pays exactly that listing's price (if someone buys it first, the AH
  refuses and nothing is paid). Need more than one? It finds the next listing after each
  purchase, one click each. Bought items count as on their way by mail.
- Fixed: AH purchases arrive in your mailbox, and SkillRoute only counted bags and bank,
  so until you collected the mail it still listed what you'd just bought (and you could
  buy it twice). What you buy on the AH (with SkillRoute, the AH's own window or
  Auctionator) now counts as yours straight away, and opening the mailbox counts exactly
  what's in it. The mini panel shows "1 in the mail" next to a material waiting there.
- Buying panel: the "Search" note ("the AH can't quote this…") ran into the next row. It
  now fits on one line, and is only shown when too few of a stackable good are listed.

## 0.38.2

- Fixed: when the route window's footer ran to two lines (a long total with training
  costs), it covered the last step. The "planned in" timing is now left off when the
  line is too long, and if it still wraps, the list ends above it.
- "N recipes skipped: reagents with no price (scan the AH)" was shown even right after a
  scan, when scanning again can't help. After a scan it now names the reagents nobody is
  selling: "2 recipes left out: no Silk Cloth on the AH right now".
- Disenchant tooltips: "Best" now says what it beat ("compared: AH 25s (12 listed) ·
  vendor 21s 30c"), as the route's tooltips do; soulbound items say "soulbound: no AH".
  The "counts Vision Dust at buy price (your Enchanting route needs it)" note is shorter,
  on its own line, and names every material it counted (it left out ones you need less
  than one of). Long notes wrap instead of making the tooltip wider.
- When a crowded AH loses to another choice despite a higher price, it says what it
  counted as, and the share used: "AH 23s 74c (47 listed: crowded, counted as 16s 61c (70%))".
- **New option: "Crowded AH listings count for"** (30% to full price, default 70%; also
  `/sr crowded <pct>`). When 20 or more of an item are already listed, this is how much of
  the AH price counts when choosing between listing, disenchanting and selling to a
  vendor. A live example shows what it does.
- Step tooltips list what "Afterwards" was compared with one per line, so a crowded AH
  note no longer makes the tooltip screen-wide.
- Mini panel: when a step needs more than one thing from the AH, the buy line reads
  "This step: ~4g 0s 36c on the AH (90% sure)" (it said "This step: buy (90% sure): …"
  and wrapped mid-price). Away from the AH, where there's no Buy button, the line uses
  the panel's full width.
- Mini panel: a material a vendor sells but the AH has cheaper said "vendor" while the
  buy list got it from the AH. Both now use one rule, and the row says "AH: cheaper".
- Arrow: the distance line now says "First: Flight master, Thunder Bluff, 144 yd", so
  the stop on the way isn't mistaken for the NPC you're going to (the name above it).
- Shopping list: a line above the list says what its amounts mean: "need: covers bad
  luck, 90% sure (Options) · expected: the average".
- **Options in two tabs:** "General" (checkboxes, safety margin, Working Overtime) and
  "Buying & selling" (Expect to sell, Crowded AH, Prefer fewer crafts). The window was
  taller than the screen at UI scale 1 and had to shrink; now each page fits at full
  size. It opens on the tab you used last, and still shrinks if a screen is too small.

## 0.38.1

- Fixed: the mini panel's "Not learned yet" note was its own, vaguer wording ("get the
  pattern first"). It now says exactly what the full route says, from the same code
  ("Buy pattern from Naal Mistrunner (12s 0c)", AH patterns, your bank, quests), with the
  same waypoint on click.
- Fixed: the disenchant tooltip's "Disenchanting" value now matches the value "Best:"
  decides on. When a material is one your Enchanting route needs, it's counted at what
  you'd pay for it, and the line says so ("counts the Vision Dust your Enchanting route
  needs at what you'd pay").
- Fixed: "keep it" in tooltips used the average amount while the shopping list adds your
  safety margin, so the two could disagree. "Keep it" now reads the shopping list's own
  amounts, including what bolts and bars are made from, plus anything a step makes for a
  later step.
- Fixed: "Take route mats" from the bank now takes the safety margin too, so it no longer
  takes less than the shopping list says you need.
- Fixed: on a flight the arrow kept working the route out from mid-air, so it pointed
  back to the flight master you'd left, or said "walk". In flight it now points straight
  at the destination ("On a flight: the route picks up again when you land") and works
  the route out again the moment you land.
- The mini panel's buy line now says it's for this step: "This step: buy 12 (90% sure)".
- The mini panel's skill colour bands now come from the same code as the full route's.

## 0.38.0

- **"Keep it" in item tooltips:** anything one of your routes still uses (materials,
  things the route crafts and uses later such as bolts, and tools) says so in its tooltip,
  with how many: "SkillRoute: keep it. Your Tailoring route needs 17 (Enchanting: 4)".
  So it isn't sold to a vendor or listed by mistake. Options: "Mark materials my routes
  need in item tooltips".

## 0.37.0

- **Disenchanting in item tooltips:** any weapon or armour (not only crafted items) shows
  what it disenchants into from Forever's own brackets, what that's worth at today's AH
  prices after the cut (a lower bound, named, when a material has no price), and
  SkillRoute's advice: disenchant, list it, or sell it to a vendor. It counts materials
  your Enchanting route needs and soulbound items. Options: "Disenchanting in item
  tooltips". Enchanters' wands are excluded; new Forever rares without data say so.
- Forever has **no Enchanting skill requirement** for disenchanting (checked in game: an
  item level 55 green at skill 170), so SkillRoute no longer says "needs Enchanting N".
- Buying panel: sized to what it lists; a bought material shows what you paid.
- Fixed (buying panel): more than 10 materials (a full shopping list) couldn't all be
  reached; there are pages now. A purchase made in the AH's own window was counted as
  the panel's. "Can't quote" now says why (not stackable, or too few listed).
- Fixed (arrow): standing at a flight master, it re-planned 20 times a second; it now
  says "Flight master, ...: here" and checks for the next leg once a second.
- **Selling advice knows the competition:** SkillRoute's scan now keeps how many of each
  item are listed. "Afterwards" and the shopping list show it ("List on the AH, 1g 20s
  each (12 listed)"), and when a market is crowded (20+ listed, and 3x what you'd sell)
  the AH counts for 70% when choosing, so the vendor or disenchanting can win.
- Fixed: the shopping list's "Crafted items in your bags" only appeared with Auctionator
  installed; SkillRoute's own scan now counts.
- **Take route mats** checks your bags: it moves no more stacks than fit, reports what
  actually arrived (a moment later), and says "Your bags are full: N stacks stayed in the
  bank" when something didn't.
- Fixed: a Mining trainer showed an empty "your route here" panel.
- NPCs inside dungeons (Annora in Uldaman, Blackrock Depths and Dire Maul vendors...) now
  have a location: the dungeon's entrance, from the game's own data, with a note. The
  route used to say "no Artisan trainer known" for Annora.
- **The arrow follows the route:** when the fastest way starts with a flight, boat or
  zeppelin, it points at the flight master or dock first ("Flight master, Thunder Bluff,
  240 yd"), then works out the next leg when you get there or arrive somewhere new, and
  points at the NPC on the last leg. A hearthstone first says "Use: Hearthstone".
- The arrow's text is the same every time: name, distance (or "On another continent"),
  and "Fastest: ..." (flight, boat, or walk), also for NPCs you visited yourself.
- Mini panel: click a trainer, book or quest step, a recipe you haven't learned, or its
  "learn it at ..." note, for a waypoint (a recipe you know still opens).
- Fixed: the full route window, opened with **Full route**, stayed on the old profession
  when you switched (e.g. Enchanting to Tailoring). It now follows.
- **No addons needed any more.** Auctionator and TomTom are still used when installed, but
  SkillRoute now does both jobs itself:
  - **Buying:** without Auctionator, **Buy** (and **Buy shopping list**) opens a panel beside
    the auction house. For each material: **Price** gets the AH's exact total for the
    amount you need, then **Buy** pays exactly that. A price that changes needs a new click;
    nothing is bought without one. Items that aren't stackable get **Search** instead.
  - **Waypoints:** without TomTom, clicking a trainer or vendor shows SkillRoute's own arrow
    with the distance (green ahead, red behind) and "Arrived" when you get there; on
    another continent it says how to get there. Drag to move, right-click to clear. The
    game's map pin is set too.

## 0.36.0

- **Your other professions help:** when one of your other professions can make a material
  this one uses (a miner smelting Mithril Bars for Blacksmithing, a tailor's bolts...), and
  making it is cheaper than buying, the route counts it that way. The shopping list says
  "Make 12 x Mithril Bar (Mining: Smelt Mithril)", and uses the ore you have first.
- Bars, bolts and other craftable materials you already own are used before making more
  (before, the shopping list could ask for ore for bars you already had).
- **Buy without Auctionator:** the Buy buttons now also work without Auctionator: they
  search the auction house's own search box for the step's materials, one per click
  ("Next 2/3"), and chat says how many you need. With Auctionator installed, Buy still
  fills its shopping list as before.
- Tools you craft (e.g. the Runed Golden Rod) get a **Buy** button for their materials, on
  the mini panel and the full route, and "To buy" works for them too.
- Fixed: a maxed profession (300/300) looked for a route to 301 and found none. It now
  says it's maxed (and the full window no longer keeps the previous profession's rows).
- Fixed: the mini panel listed a tool again under "Then" when a later step also needed it.

## 0.35.0

- The full route window steps aside while Options is open and comes back when you close
  it; Options always draws on top.
- **SkillRoute's own AH scan:** a **Scan AH** button (and `/sr scan`) while the auction
  house is open reads the lowest price of everything listed in one search. Auctionator is
  no longer required for prices. The button sits on the auction house window's title bar
  (and on the full SkillRoute window) and shows the scan's progress.
- **Prices for the amount you need:** after the full read, one search per material your
  routes buy prices *all* of it along the price ladder, not just the cheapest listing
  (Options: "Price the amounts I need", on by default). The button shows "Pricing 7/18";
  closing the AH partway keeps what was priced. It looks up each material's AH item info
  before searching it (searches for items the AH hadn't looked up were often ignored), so
  first searches now nearly always answer. `/sr scanlog` sums up the last scan's searches.
- The scan sends each request the moment the AH allows it (no more 0.3 s polling), and the
  finish line says where the time went (pages, waiting, answers).
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
  what to do with what you make; when you're short of materials it says how many to buy
  (with your safety margin, the same amount the **Buy** button sends) and what that costs.
- Fixed: the trainer panel's Learn buttons stayed disabled at the right skill (the
  client reports learnable recipes differently); it now goes by your skill and level.
- The mini panel docks past the profession window's side tabs; drag it anywhere
  (remembered), right-click it to dock again. Tools you craft get Craft buttons and say
  which trainer teaches them.
- **At the trainer:** a "your route here" panel lists the recipes this trainer has that
  your route uses, with the skill range each is for, the cost, **Learn** and **Learn all**.
- **Rank-up reminder:** when a profession hits 75, 150 or 225 and your target is higher,
  SkillRoute says what to do next (trainer, book or quest), where, and how far.
- **At the bank:** **Take route mats** moves what the next 3 steps of each of your crafting
  professions still need from the bank into your bags (whole stacks). Works with bank tabs and with bag addons that
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
