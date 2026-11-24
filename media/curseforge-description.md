# SkillRoute

**Plans the cheapest way to level any profession in WoW Forever, using the game's own recipe data and your Auctionator prices, with trainers, vendors and waypoints for every step.**

Leveling guides written for Classic don't match Forever: many recipes changed skill-up ranges, new recipes were added, and trainers and ranks work differently. SkillRoute reads Forever's actual recipe data, prices each step from your own Auctionator scans, and works out the cheapest route from your current skill to your target.

---

## What it does

### A route built for you
- **Every crafting profession:** Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Tailoring, Cooking and First Aid.
- **Cheapest expected cost:** each skill point is planned with the real skill-up chances (orange, yellow, green), so it knows when a pricier recipe that skills up reliably beats a cheap one you'd craft three times.
- **Uses what you have:** materials in your bags, bank and on your alts (with Syndicator or DataStore) come off the shopping list. Patterns you already own count as free.
- **Updates live:** a new Auctionator scan, a learned recipe or a skill-up re-plans the route straight away.

### Where to go, and why
- **Trainers and vendors by name and location,** the nearest one for your faction, with travel time (flight paths you know, boats, zeppelins, even your hearthstone when it saves time).
- **Click a step to set a waypoint** (TomTom, or the game's own map pin).
- **Rank-ups in the right place:** train at the right trainer, buy the Expert book, or do the Artisan quest (Triage, Clamlette Surprise, Nat Pagle), with the quest giver's location.
- **Forever's trainer rules:** each trainer teaches the rank below its title and nothing until your skill reaches it; the route warns when your character level is too low for the next rank.
- **Patterns:** bought from a vendor of your faction, or on the auction house when that's cheaper, with reputation requirements checked.

### Hover any step to see
- **Cost per craft** and the skill levels where the recipe stays orange, yellow and green.
- **Why this recipe:** how much it saves over the next best, and what decided it.
- **Where to learn it:** trainer, vendor, quest or your bank.
- **What to do with what you make:** list it on the AH, disenchant it (if you're an enchanter, counting materials your Enchanting route still needs) or sell it to a vendor, whichever is worth most.

### Shopping, made easy
- **Shopping list:** everything to buy, minus what you have, with a safety margin so you don't run short.
- **At the auction house:** a **Buy** button on every step opens Auctionator's Shopping tab with that step's materials and the amounts you need.
- **Farming:** ingredients the AH doesn't have show where to farm them (mob, level, drop chance, zone) or where to fish them.

### Gathering and secondary skills
- **Mining and Herbalism:** which nodes to gather at each skill range, and the best zones, your faction's first.
- **Skinning:** the beast levels to skin and where to find them.
- **Fishing:** catches needed per range and the waters where no fish get away.

---

## Getting started

1. Install **[Auctionator](https://www.curseforge.com/wow/addons/auctionator)** (strongly recommended: SkillRoute's prices come from it) and do a full AH scan.
2. Open your profession window: SkillRoute opens next to it. You can also type **/sr** or click the minimap button.
3. Read the route top to bottom. **Hover** a step for details, **click** to open the recipe or set a waypoint, **right-click** to skip a recipe you can't get.
4. Use **Shopping list** for what to buy, and **Options** for the safety margin, alts, resale share and more.

**Optional:** TomTom (better waypoints), Syndicator or DataStore (count materials on your alts).

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

- **This is a beta.** Forever is new and some data is still being confirmed. If a trainer, vendor or recipe is wrong, open a trainer or vendor window once (SkillRoute learns from it) and please report it.
- Prices are only as fresh as your last Auctionator scan.
- Zone and NPC names in some places are English-only.

## Feedback and bugs

Please report issues on the [GitHub page](https://github.com/Quillfred/Wow-Professions-Forever/issues). Include a screenshot of `/sr check` if something looks broken.

---

*SkillRoute is free software under the GNU GPL v3. It isn't affiliated with Blizzard Entertainment. World of Warcraft is a trademark of Blizzard Entertainment.*
