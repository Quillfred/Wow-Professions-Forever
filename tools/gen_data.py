#!/usr/bin/env python3
"""Build SkillRoute/Data.lua from WoW Forever's client game tables (via wago.tools).

Usage: python3 -I tools/gen_data.py [BUILD] [CACHE_DIR]
  BUILD      client build, e.g. 1.60.1.71037 (default: newest "wowf" build on wago.tools)
  CACHE_DIR  where the CSV tables are downloaded (default: ./.db2cache)

Everything recipe-related comes from the client tables. Two things are NOT in the
client and are handled at runtime by the addon instead: the skill a trainer
recipe is learned at (read from the trainer window) and which recipes a trainer
actually teaches (until confirmed, assumed learnable at its yellow skill).
"""
import csv, json, os, sys, urllib.request, concurrent.futures as cf

PROFESSIONS = {171: "Alchemy", 164: "Blacksmithing", 333: "Enchanting", 202: "Engineering",
               165: "Leatherworking", 197: "Tailoring", 185: "Cooking", 129: "First Aid"}
TABLES = ["SkillLineAbility", "SpellReagents", "SpellName", "SpellEffect",
          "ItemSparse", "ItemEffect", "ItemXItemEffect", "SpellCooldowns",
          "SpellTotems", "TotemCategory", "Faction"]
# Not trainer recipes even though no item teaches them (quest rewards etc.). Only
# used when the player knows them.
NOT_TRAINER = {22813, 22815, 19435,  # Gordok Ogre Suits (quest), Mooncloth Boots (quest)
               11452,                # Restorative Potion (quest)
               23486, 23489, 13240}  # Goblin/Gnomish specialization only
SOD_SPELLS = range(400000, 500000)
# Materials whose only source is a cooldown craft (scarce, priced accordingly).
# Checked against the client: these are made only by spells with a cooldown and not
# smelted or otherwise crafted. Elemental essences are left out: transmutes make
# them too, but they mostly drop from mobs.
COOLDOWN_MATS = {"Mooncloth", "Arcanite Bar", "Legionite Bar"}   # Season of Discovery recipes: never assumed trainer
# Reagents sold by trade-supply vendors. Used only as a price fallback; Auctionator's
# own vendor price wins when it has one. Matched by name, prices from the client.
VENDOR = {"Coarse Thread", "Fine Thread", "Silken Thread", "Heavy Silken Thread", "Rune Thread",
          "Red Dye", "Blue Dye", "Gray Dye", "Green Dye", "Yellow Dye", "Black Dye", "Orange Dye",
          "Purple Dye", "Bleach", "Salt", "Mild Spices", "Hot Spices", "Refreshing Spring Water",
          "Ice Cold Milk", "Simple Flour", "Empty Vial", "Leaded Vial", "Crystal Vial",
          "Imbued Vial", "Weak Flux", "Strong Flux", "Copper Rod", "Simple Wood",
          "Heavy Stock", "Wooden Stock", "Engineer's Ink",
          # tools sold by trade-supply vendors
          "Blacksmith Hammer", "Flint and Tinder", "Mining Pick", "Skinning Knife"}
MAX_SKILL = 300  # Forever's profession cap; recipes only usable above it are dropped
SPELL_EFFECT_CREATE_ITEM, SPELL_EFFECT_LEARN_SPELL, ITEM_TRIGGER_ON_LEARN = "24", "36", "6"


def latest_build():
    with urllib.request.urlopen("https://wago.tools/api/builds", timeout=30) as r:
        return json.load(r)["wowf"][0]["version"]


def fetch(build, cache):
    os.makedirs(cache, exist_ok=True)
    def one(t):
        path = os.path.join(cache, f"{t}-{build}.csv")
        if not os.path.exists(path):  # tables are immutable per build: never re-download
            url = f"https://wago.tools/db2/{t}/csv?build={build}"
            with urllib.request.urlopen(url, timeout=180) as r, open(path + ".part", "wb") as f:
                f.write(r.read())
            os.replace(path + ".part", path)
        return t, path
    with cf.ThreadPoolExecutor(len(TABLES)) as ex:
        return dict(ex.map(one, TABLES))


def rows(path):
    with open(path, newline="", encoding="utf-8") as f:
        yield from csv.DictReader(f)


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def main():
    build = sys.argv[1] if len(sys.argv) > 1 else latest_build()
    cache = sys.argv[2] if len(sys.argv) > 2 else ".db2cache"
    p = fetch(build, cache)
    # Optional: learn levels / sources / trainer costs from Wowhead (tools/import_wowhead.py).
    wowhead = {}
    whpath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wowhead_forever.json")
    if os.path.exists(whpath):
        with open(whpath, encoding="utf-8") as f:
            wowhead = {int(k): {int(sp): v for sp, v in rec.items()}
                       for k, rec in json.load(f)["professions"].items()}

    # Optional: sources for recipes Wowhead's Recipes tab left blank (tools/import_sources.py).
    extra = {}
    xpath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "forever_sources.json")
    if os.path.exists(xpath):
        with open(xpath, encoding="utf-8") as f:
            extra = {int(k): v for k, v in json.load(f).items()}

    # Optional: which factions can buy each pattern from a vendor (tools/import_vendors.py).
    vendor_sides = {}
    vpath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vendor_factions.json")
    if os.path.exists(vpath):
        with open(vpath, encoding="utf-8") as f:
            vendor_sides = {int(k): v for k, v in json.load(f).items()}

    # Optional: trainers / pattern vendors with zone + coordinates (tools/import_npcs.py).
    npcdata = {"npcs": {}, "trainers": {}, "vendors": {}}
    npath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "npcs.json")
    if os.path.exists(npath):
        with open(npath, encoding="utf-8") as f:
            npcdata = json.load(f)

    abil = {}  # spell -> SkillLineAbility row (crafting recipes only)
    for r in rows(p["SkillLineAbility"]):
        sl = int(r["SkillLine"])
        if sl in PROFESSIONS and int(r["TrivialSkillLineRankHigh"]) > 0:
            abil[int(r["Spell"])] = r
    names = {int(r["ID"]): r["Name_lang"] for r in rows(p["SpellName"]) if int(r["ID"]) in abil}

    reagents = {}
    for r in rows(p["SpellReagents"]):
        s = int(r["SpellID"])
        if s in abil:
            lst = [(int(r[f"Reagent_{i}"]), int(r[f"ReagentCount_{i}"])) for i in range(8)]
            reagents[s] = [(i, c) for i, c in lst if i > 0 and c > 0]

    creates, learn_spell = {}, {}
    for r in rows(p["SpellEffect"]):
        s = int(r["SpellID"])
        if r["Effect"] == SPELL_EFFECT_CREATE_ITEM and s in abil and int(r["EffectItemType"]) > 0:
            creates[s] = (int(r["EffectItemType"]), max(1, int(float(r["EffectBasePointsF"]))))
        elif r["Effect"] == SPELL_EFFECT_LEARN_SPELL and int(r["EffectTriggerSpell"]) in abil:
            learn_spell[s] = int(r["EffectTriggerSpell"])

    effect_items = {}
    for r in rows(p["ItemXItemEffect"]):
        effect_items.setdefault(int(r["ItemEffectID"]), []).append(int(r["ItemID"]))
    taught_by = {}  # recipe spell -> [pattern item ids]
    for r in rows(p["ItemEffect"]):
        s = int(r["SpellID"])
        target = s if (s in abil and r["TriggerType"] == ITEM_TRIGGER_ON_LEARN) else learn_spell.get(s)
        if target:
            for it in effect_items.get(int(r["ID"]), []):
                taught_by.setdefault(target, set()).add(it)

    cooldown = {}  # spell -> seconds (e.g. Mooncloth ~4 days): never grindable
    for r in rows(p["SpellCooldowns"]):
        s = int(r["SpellID"])
        if s in abil:
            ms = max(int(r["RecoveryTime"]), int(r["CategoryRecoveryTime"]))
            if ms > 0:
                cooldown[s] = ms // 1000

    items = {}
    for r in rows(p["ItemSparse"]):
        items[int(r["ID"])] = r

    # Tools: recipes that need an item in your bags (rods, hammers, spanners).
    # A tool category is satisfied by any item of the same type whose mask covers it
    # (a Runed Arcanite Rod counts as every lower rod). Key -ItemID = one exact item.
    cats = {int(r["ID"]): (int(r["TotemCategoryType"]), int(r["TotemCategoryMask"]), r["Name_lang"])
            for r in rows(p["TotemCategory"])}
    needs_tool = {}
    for r in rows(p["SpellTotems"]):
        s = int(r["SpellID"])
        if s in abil:
            t = [int(r[k]) for k in ("RequiredTotemCategoryID_0", "RequiredTotemCategoryID_1") if int(r[k])]
            t += [-int(r[k]) for k in ("Totem_0", "Totem_1") if int(r[k])]
            if t:
                needs_tool[s] = t
    def satisfying(cat):
        if cat < 0:
            return [-cat]
        typ, mask, _ = cats[cat]
        out = []
        for iid, r in items.items():
            c = int(r["TotemCategoryID"] or 0)
            if c and c in cats and cats[c][0] == typ and (cats[c][1] & mask) == mask:
                out.append(iid)
        return sorted(out)
    tool_items = {}

    used_items, vendor_patterns, used_factions = set(), set(), set()
    out = {sl: [] for sl in PROFESSIONS}
    for s, a in sorted(abil.items()):
        if s not in reagents or s not in names:
            continue  # not a craft (no reagents) -> nothing to plan
        y, g = int(a["TrivialSkillLineRankLow"]), int(a["TrivialSkillLineRankHigh"])
        pats = sorted(taught_by.get(s, ()))
        learn, cost, origin = None, None, None
        w = wowhead.get(int(a["SkillLine"]), {}).get(s)  # [learnedAt, [sources], trainingCost]
        x = extra.get(s, {})
        where = x.get("where")
        if where and x.get("classic"):
            where += " (Classic data)"
        if a["AcquireMethod"] == "1":
            src = "a"  # learned together with the profession
        elif w and "Trainer" in w[1]:
            src = "T"  # a trainer teaches it (Wowhead), learnable at w[0]
            learn, cost = (w[0] if w[0] is not None else y), w[2]
        elif pats:
            src = "p"
            ranks = [int(items[i]["RequiredSkillRank"]) for i in pats
                     if i in items and int(items[i]["RequiredSkill"]) == int(a["SkillLine"])]
            # when it starts giving skill-ups (Wowhead) beats the pattern item's own requirement
            learn = w[0] if (w and w[0] is not None) else (min(ranks) if ranks else None)
            origin = (w and w[1]) or x.get("src")
        elif (w is None and s < 100000 and s not in NOT_TRAINER) or \
                (x.get("likelyTrainer") and s not in NOT_TRAINER and s not in SOD_SPELLS):
            src = "t"  # probably a trainer recipe (no item teaches it): confirmed in game at the trainer
        else:
            src = "x"  # quest/special/no known source: only used if the character knows it
            origin = w and w[1]
        if (learn if learn is not None else y) >= MAX_SKILL:
            continue
        o = creates.get(s)
        used_items.update(i for i, _ in reagents[s])
        used_items.update(pats)
        if o:
            used_items.add(o[0])
        fields = [f"n={lua_str(names[s])}", f"y={y}", f"g={g}", f'src="{src}"']
        if learn is not None:
            fields.append(f"learn={learn}")
        if cost:
            fields.append(f"tc={cost}")
        if where:
            fields.append(f"where={lua_str(where)}")
        if origin:
            fields.append(f"from={lua_str('/'.join(origin))}")
            if "Vendor" in origin:
                vendor_patterns.update(pats)
        if o:
            fields.append(f"out={o[0]}")
            if o[1] != 1:
                fields.append(f"outN={o[1]}")
        fields.append("r={" + ",".join(f"{i},{c}" for i, c in reagents[s]) + "}")
        if pats:
            fields.append("pat={" + ",".join(map(str, pats)) + "}")
            # Pattern items that need faction reputation: {item, factionID, rank 0-7,...}
            # (rank: 4 Friendly, 5 Honored, 6 Revered, 7 Exalted)
            reps = []
            for i in pats:
                f = int(items.get(i, {}).get("MinFactionID", 0) or 0)
                if f:
                    reps += [i, f, int(items[i]["MinReputation"] or 0)]
                    used_factions.add(f)
            if reps:
                fields.append("rep={" + ",".join(map(str, reps)) + "}")
        if s in cooldown:
            fields.append(f"cd={cooldown[s]}")
        if s in needs_tool:
            fields.append("tool={" + ",".join(map(str, needs_tool[s])) + "}")
            for c in needs_tool[s]:
                if c not in tool_items:
                    tool_items[c] = satisfying(c)
                    used_items.update(tool_items[c])
        out[int(a["SkillLine"])].append(f"    [{s}]={{{','.join(fields)}}},")

    lines = ["-- GENERATED by tools/gen_data.py from WoW Forever client build " + build
             + (" + Wowhead learn levels/sources" if wowhead else "") + ". Do not edit.",
             "SkillRouteData = {", f'  build = "{build}",', "  professions = {"]
    for sl, name in PROFESSIONS.items():
        lines += [f'  [{sl}] = {{ name = {lua_str(name)}, recipes = {{'] + out[sl] + ["  }},"]
    lines += ["  },", "  -- [itemID] = {name, vendorSellPrice, vendorBuyPrice-or-nil (trade-supply reagents)}",
              "  items = {"]
    for i in sorted(used_items):
        r = items.get(i)
        if not r:
            continue
        vendor = r["Display_lang"] in VENDOR or i in vendor_patterns
        buy = r["BuyPrice"] if vendor and int(r["BuyPrice"]) > 0 else "nil"
        lines.append(f"    [{i}]={{{lua_str(r['Display_lang'])},{r['SellPrice']},{buy}}},")
    lines += ["  },", "  -- [toolKey] = {name, itemIDs that satisfy it}; negative key = that exact item",
              "  tools = {"]
    tools_start = len(lines)
    for c in sorted(tool_items):
        name = cats[c][2] if c > 0 else items.get(-c, {}).get("Display_lang", str(-c))
        lines.append(f"    [{c}]={{{lua_str(name)},{{{','.join(map(str, tool_items[c]))}}}}},")
    lines += ["  },", "  -- reagents only made by cooldown crafts (Mooncloth...): avoided unless /sr cdmats on",
              "  cooldownMats = {"]
    for i in sorted(used_items):
        if items.get(i, {}).get("Display_lang") in COOLDOWN_MATS:
            lines.append(f"    [{i}]=true,")
    lines += ["  },", "  -- [patternItem] = {\"A\"|\"H\"|\"AH\" (who vendors sell it to), \"Alliance vendors\", \"Horde vendors\"}",
              "  -- (Classic vendor lists; a vendor you visit in game overrides this)",
              "  patternVendors = {"]
    for i in sorted(vendor_patterns):
        e = vendor_sides.get(i)
        if not e:
            continue
        side = ("A" if e["A"] else "") + ("H" if e["H"] else "")
        names_a = ", ".join(n for n, s in e["v"] if "A" in s)
        names_h = ", ".join(n for n, s in e["v"] if "H" in s)
        lines.append(f"    [{i}]={{\"{side}\",{lua_str(names_a)},{lua_str(names_h)}}},")
    # NPCs: [id] = {name, "A"|"H"|"AH", continent map, worldX, worldY, zone, zoneX, zoneY}
    used_npcs = set()
    tr_lines, vend_lines = [], []
    for line in sorted(PROFESSIONS):
        d = npcdata["trainers"].get(str(line), {})
        if d:
            tr_lines.append(f"    [{line}]={{" + ",".join(f"[{e}]={max(st)}" for e, st in sorted(d.items(), key=lambda kv: int(kv[0]))) + "},")
            used_npcs.update(int(e) for e in d)
    for i in sorted(vendor_patterns):
        es = npcdata["vendors"].get(str(i))
        if es:
            vend_lines.append(f"    [{i}]={{{','.join(map(str, es))}}},")
            used_npcs.update(es)
    lines += ["  },", "  -- profession trainers: [skillLine] = {[npcID] = highest rank taught (2 Journeyman, 3 Expert, 4 Artisan)}",
              "  trainers = {"] + tr_lines
    lines += ["  },", "  -- [patternItem] = {npcIDs of vendors selling it}", "  vendorNpcs = {"] + vend_lines
    # which trainers teach each trainer recipe; identical trainer lists stored once
    sets, set_index, rec_lines = [], {}, []
    for line in sorted(PROFESSIONS):
        for row in out[line]:
            sp = int(row.split("]")[0].strip()[1:])
            if 'src="T"' not in row and 'src="t"' not in row:
                continue
            es = npcdata.get("recipes", {}).get(str(sp))
            if not es:
                continue
            key = tuple(es)
            if key not in set_index:
                set_index[key] = len(sets) + 1
                sets.append(key)
                used_npcs.update(es)
            rec_lines.append(f"[{sp}]={set_index[key]}")
    lines += ["  },", "  -- trainer lists, and [recipe spell] = index of the list of trainers that teach it",
              "  trainerSets = {"] + ["    {" + ",".join(map(str, k)) + "}," for k in sets]
    lines += ["  },", "  recipeTrainers = {"]
    for i in range(0, len(rec_lines), 12):
        lines.append("    " + ",".join(rec_lines[i:i + 12]) + ",")
    lines += ["  },", "  -- [npcID] = {name, faction \"A\"|\"H\"|\"AH\", map, worldX, worldY, continentUiMap, contX, contY, zone, zoneX, zoneY}",
              "  -- (Classic spawns; zone only when unambiguous, the game resolves the rest)",
              "  npcs = {"]
    for e in sorted(used_npcs):
        n = npcdata["npcs"].get(str(e))
        if n:
            zone = lua_str(n["zone"]) if n["zone"] else "nil"
            v = lambda k: "nil" if n.get(k) is None else str(n[k])
            lines.append(f"    [{e}]={{{lua_str(n['n'])},\"{n['side']}\",{n['map']},{n['x']},{n['y']},"
                         f"{v('cui')},{v('cx')},{v('cy')},{zone},{v('zx')},{v('zy')}}},")
    factions = {int(r["ID"]): r["Name_lang"] for r in rows(p["Faction"])}
    lines += ["  },", "  factions = {"]
    for f in sorted(used_factions):
        lines.append(f"    [{f}]={lua_str(factions.get(f, str(f)))},")
    lines += ["  },", "}", ""]
    dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "SkillRoute", "Data.lua")
    with open(dst, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"build {build}: " + ", ".join(f"{PROFESSIONS[sl]} {len(v)}" for sl, v in out.items())
          + f"; {len(used_items)} items -> {os.path.relpath(dst)}")


if __name__ == "__main__":
    main()
