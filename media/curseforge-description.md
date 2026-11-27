# SkillRoute Forever

**Plans the cheapest way to level any profession in WoW Forever, using the game's own recipe data and fresh auction house prices, with trainers, vendors and waypoints for every step.**

Leveling guides written for Classic don't match Forever: many recipes changed skill-up ranges, new recipes were added, and trainers and ranks work differently. SkillRoute reads Forever's actual recipe data, prices each step from your own AH scans (its own or Auctionator's, whichever is newer), and works out the cheapest route from your current skill to your target.

---

## What it does

### A route built for you
- **Every crafting profession:** Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Tailoring, Cooking and First Aid.
- **Cheapest expected cost:** each skill point is planned with the real skill-up chances (orange, yellow, green), so it knows when a pricier recipe that skills up reliably beats a cheap one you'd craft three times.
- **Your other professions help:** a miner smelts the bars a blacksmith needs, a tailor makes the bolts, when that's cheaper than buying.
- **Uses what you have:** materials in your bags, bank and on your alts (with Syndicator or DataStore) come off the shopping list. Patterns you already own count as free.
- **Updates live:** a new AH scan, a learned recipe or a skill-up re-plans the route straight away.

### Where to go, and why
- **Trainers and vendors by name and location,** the nearest one for your faction, with travel time (flight paths you know, boats, zeppelins, even your hearthstone when it saves time).
- **Click a step for a waypoint arrow** with the distance (SkillRoute's own, or TomTom's if you have it).
- **Rank-ups in the right place:** train at the right trainer, buy the Expert book, or do the Artisan quest (Triage, Clamlette Surprise, Nat Pagle), with the quest giver's location.
- **Forever's trainer rules:** each trainer teaches the rank below its title and nothing until your skill reaches it; the route warns when your character level is too low for the next rank.
- **Patterns:** bought from a vendor of your faction, or on the auction house when that's cheaper, with reputation requirements checked.

### Hover any step to see
- **Cost per craft** and the skill levels where the recipe stays orange, yellow and green.
- **Why this recipe:** how much it saves over the next best, and what decided it.
- **Where to learn it:** trainer, vendor, quest or your bank.
- **What to do with what you make:** list it on the AH, disenchant it (if you're an enchanter, counting materials your Enchanting route still needs) or sell it to a vendor, whichever is worth most.

### At the profession window, trainer and bank
- **Mini panel** next to your profession window: the next step, materials you have against what it needs, **Craft 1** / **Craft all**, and what comes after.
- **At the trainer:** the recipes this trainer has that your route uses, what each is for, and **Learn** buttons.
- **Rank-up reminder** when you hit a cap, with where to train (or the book or quest).
- **At the bank:** one button takes the next steps' materials for all your professions into your bags.

### Shopping, made easy
- **Shopping list:** everything to buy, minus what you have, with a safety margin so you don't run short.
- **At the auction house:** a **Buy** button on every step lists that step's materials and the amounts you need: **Price**, then **Buy** pays exactly the price shown. With Auctionator installed, it uses Auctionator's Shopping tab instead.
- **Farming:** ingredients the AH doesn't have show where to farm them (mob, level, drop chance, zone) or where to fish them.

### Gathering and secondary skills
- **Mining and Herbalism:** which nodes to gather at each skill range, and the best zones, your faction's first.
- **Skinning:** the beast levels to skin and where to find them.
- **Fishing:** catches needed per range and the waters where no fish get away.

---

## Getting started

1. Scan the auction house: click **SkillRoute: Scan AH** on the auction house window. No other addons are needed ([Auctionator](https://www.curseforge.com/wow/addons/auctionator)'s scan works too).
2. Open your profession window: SkillRoute opens next to it. You can also type **/sr** or click the minimap button.
3. Read the route top to bottom. **Hover** a step for details, **click** to open the recipe or set a waypoint, **right-click** to skip a recipe you can't get.
4. Use **Shopping list** for what to buy, and **Options** for the safety margin, alts, selling what you make and more.

**Optional:** Auctionator and TomTom (used instead of SkillRoute's own buying and arrow when installed), Syndicator or DataStore (count materials on your alts).

### Commands
| Command | What it does |
|---|---|
| `/sr` | Open or close the window |
| `/sr options` | Settings |
| `/sr check` | Check everything works (send a screenshot if something's wrong) |
| `/sr minimap on\|off` | Show or hide the minimap button |
| `/sr help` | All commands |

---

## Where the data comes from

- **The WoW Forever client:** recipes, reagents, skill-up ranges, items, tools, flight paths and zones.
- **[AllTheThings](https://www.curseforge.com/wow/addons/all-the-things)' Forever database:** trainers, vendors, quest givers and how each recipe is learned.
- **Wowhead's WoW Forever pages:** learn levels, trainer costs and recipe sources.
- **cMaNGOS Classic-DB:** where Forever data isn't available yet (some vendors, herb and ore spawns, mob drops, fishing and disenchant tables), checked against Forever where possible.
- **What you see in game:** opening a trainer or vendor window records what they really offer, and that always wins.

---

## Good to know

- **Forever is new** and some data is still being confirmed. If a trainer, vendor or recipe is wrong, open a trainer or vendor window once (SkillRoute learns from it) and please report it.
- Prices are only as fresh as your last AH scan (SkillRoute uses whichever is newer: its own or Auctionator's).
- Zone and NPC names in some places are English-only.

## Feedback and bugs

Please report issues on the [GitHub page](https://github.com/Quillfred/Wow-Professions-Forever/issues). Include a screenshot of `/sr check` if something looks broken.

---

*SkillRoute is free software under the GNU GPL v3. It isn't affiliated with Blizzard Entertainment. World of Warcraft is a trademark of Blizzard Entertainment.*
