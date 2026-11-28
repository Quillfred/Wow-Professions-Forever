# Third-party data

## AllTheThings (tools/att_forever.json, and the trainer/vendor/NPC data derived from it in SkillRoute/Data.lua)

Derived from the Forever database of AllTheThings, https://github.com/ATTWoWAddon/AllTheThings
(folder `.contrib/.db/forever`).

MIT License

Copyright (c) 2026 AllTheThings WoW Addon

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## cMaNGOS Classic-DB (tools/vendor_factions.json, npcs.json, gather.json, farm.json, skinning.json, disenchant.json, zone_points.json)

Derived from Classic-DB, https://github.com/cmangos/classic-db, released under the GNU
General Public License version 3 (the full text is in LICENSE). Used where Forever's own
data and AllTheThings have nothing: vendor and trainer lists, NPC spawns, boats and
zeppelins, herb and ore spawns, mob and fishing loot, skinnable beasts and disenchant
results of Classic WoW, partly corrected for Forever (tools/forever_checks.json).
Because SkillRoute includes this data, SkillRoute as a whole is released under the GPL v3.

Classic-DB's own notice: World of Warcraft content and materials are trademarks and
copyrights of Blizzard or its licensors. All rights reserved. Classic-DB and SkillRoute
are not affiliated with Blizzard.

## WoW Forever client tables (via wago.tools)

Recipes, reagents, items, spells, maps, flight paths and factions read from the game
client's own tables. World of Warcraft content is the property of Blizzard Entertainment.

## Wowhead (tools/wowhead_forever.json, tools/forever_sources.json, tools/node_points.json, SkillRoute/NodeSpots.lua, tools/node_reqs.json, tools/favor_rep.json, tools/crates.json)

Recipe learn levels, trainer costs and recipe sources were taken from Wowhead's WoW
Forever pages (https://www.wowhead.com/forever), and some corrections in
tools/source_overrides.json and tools/forever_checks.json were checked there. Herb and
ore spots and the skill each node needs (Mining and Herbalism routes, and the spots on
the map and minimap), the reputation
Merchant's Favor patterns need, and what each Waylaid Crate accepts come from Wowhead's
WoW Forever maps and tooltips. Thanks to
Wowhead and its contributors. If you represent Wowhead and want this data removed,
open an issue at https://github.com/Quillfred/Wow-Professions-Forever and it will be:
`NO_WOWHEAD=1 tools/build_all.sh` rebuilds the addon without it.

