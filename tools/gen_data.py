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

# weapons that can't be disenchanted: enchanters' wands (Classic 11287-11290, Forever's own)
NEVER_DE = [11287, 11288, 11289, 11290, 247789, 249144, 249232, 249234, 249237, 249385]
# gathering professions with recipes other professions can use (Mining: smelting)
MAKE_LINES = {186}
PROFESSIONS = {171: "Alchemy", 164: "Blacksmithing", 333: "Enchanting", 202: "Engineering",
               165: "Leatherworking", 197: "Tailoring", 185: "Cooking", 129: "First Aid"}
TABLES = ["Map", "SkillLineAbility", "SpellReagents", "SpellName", "SpellEffect",
          "ItemSparse", "ItemEffect", "ItemXItemEffect", "SpellCooldowns",
          "SpellTotems", "TotemCategory", "Faction", "TaxiNodes", "TaxiPath", "TaxiPathNode", "Item"]
# specialisations (ATT constant -> the spec's spell in Forever's SpellName table)
SPEC_SPELL = {"ARMORSMITH": 9788, "WEAPONSMITH": 9787, "MASTER_AXESMITH": 17041, "MASTER_HAMMERSMITH": 17040,
              "MASTER_SWORDSMITH": 17039, "DRAGONSCALE_LEATHERWORKING": 10656, "ELEMENTAL_LEATHERWORKING": 10658,
              "TRIBAL_LEATHERWORKING": 10660, "GNOMISH_ENGINEERING": 20219, "GOBLIN_ENGINEERING": 20222}
SPEC_NAME = {9788: "Armorsmith", 9787: "Weaponsmith", 17041: "Master Axesmith", 17040: "Master Hammersmith",
             17039: "Master Swordsmith", 10656: "Dragonscale Leatherworking", 10658: "Elemental Leatherworking",
             10660: "Tribal Leatherworking", 20219: "Gnomish Engineer", 20222: "Goblin Engineer"}
FLY_SPEED = 32      # yards/second on a flight path
FLY_OVERHEAD = 10   # seconds: take-off, landing
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


UA = {"User-Agent": "SkillRoute-datagen/1.0"}  # wago.tools refuses Python's default agent


def latest_build():
    with urllib.request.urlopen(urllib.request.Request("https://wago.tools/api/builds", headers=UA), timeout=30) as r:
        return json.load(r)["wowf"][0]["version"]


def fetch(build, cache):
    os.makedirs(cache, exist_ok=True)
    def one(t):
        path = os.path.join(cache, f"{t}-{build}.csv")
        if not os.path.exists(path):  # tables are immutable per build: never re-download
            url = f"https://wago.tools/db2/{t}/csv?build={build}"
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=180) as r, \
                    open(path + ".part", "wb") as f:
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
    # NO_WOWHEAD=1: build without anything taken from Wowhead (wowhead_forever.json,
    # forever_sources.json, the Wowhead-first source overrides): AllTheThings, Forever's
    # own tables and Classic-DB only. Trainer fees then come only from trainer windows.
    no_wowhead = os.environ.get("NO_WOWHEAD") == "1"
    if no_wowhead:
        print("NO_WOWHEAD=1: building without Wowhead-derived data")
    wowhead = {}
    whpath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wowhead_forever.json")
    if os.path.exists(whpath) and not no_wowhead:
        with open(whpath, encoding="utf-8") as f:
            wowhead = {int(k): {int(sp): v for sp, v in rec.items()}
                       for k, rec in json.load(f)["professions"].items()}

    # Optional: sources for recipes Wowhead's Recipes tab left blank (tools/import_sources.py).
    extra = {}
    xpath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "forever_sources.json")
    if os.path.exists(xpath) and not no_wowhead:
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

    # AllTheThings (tools/import_att.py): loaded early, its trainer lists confirm recipes
    att = {"npcs": {}, "trainers": {}, "vendors": {}, "recipeTier": {}}
    apath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "att_forever.json")
    if os.path.exists(apath):
        with open(apath, encoding="utf-8") as f:
            att = json.load(f)
    abil = {}  # spell -> SkillLineAbility row (crafting recipes only)
    for r in rows(p["SkillLineAbility"]):
        sl = int(r["SkillLine"])
        # plus Mining's smelting: other professions use its bars (a miner can make them)
        if (sl in PROFESSIONS or sl in MAKE_LINES) and int(r["TrivialSkillLineRankHigh"]) > 0:
            abil[int(r["Spell"])] = r
    names = {int(r["ID"]): r["Name_lang"] for r in rows(p["SpellName"]) if int(r["ID"]) in abil}

    reagents = {}
    for r in rows(p["SpellReagents"]):
        s = int(r["SpellID"])
        if s in abil:
            lst = [(int(r[f"Reagent_{i}"]), int(r[f"ReagentCount_{i}"])) for i in range(8)]
            reagents[s] = [(i, c) for i, c in lst if i > 0 and c > 0]

    creates, learn_spell, rank1 = {}, {}, {}
    rank_step, rank_learn = {}, {}  # rank-up spells (effect 118) and the spells that teach them
    for r in rows(p["SpellEffect"]):
        s = int(r["SpellID"])
        if r["Effect"] == "118":
            rank_step[s] = (int(r["EffectMiscValue_0"]), int(float(r["EffectBasePointsF"] or 0)))
        elif r["Effect"] == SPELL_EFFECT_LEARN_SPELL:
            rank_learn[s] = int(r["EffectTriggerSpell"])
        # the Apprentice rank spell of each profession (effect 118, step 1): its name is
        # the profession's name in the player's language, for matching at runtime
        if r["Effect"] == "118" and float(r["EffectBasePointsF"] or 0) == 1:
            rank1.setdefault(int(r["EffectMiscValue_0"]), s)
        if r["Effect"] == SPELL_EFFECT_CREATE_ITEM and s in abil and int(r["EffectItemType"]) > 0:
            creates[s] = (int(r["EffectItemType"]), max(1, int(float(r["EffectBasePointsF"]))))
        elif r["Effect"] == SPELL_EFFECT_LEARN_SPELL and int(r["EffectTriggerSpell"]) in abil:
            learn_spell[s] = int(r["EffectTriggerSpell"])

    effect_items = {}
    for r in rows(p["ItemXItemEffect"]):
        effect_items.setdefault(int(r["ItemEffectID"]), []).append(int(r["ItemID"]))
    taught_by = {}  # recipe spell -> [pattern item ids]
    rank_books = {}  # (line, rank) -> items that teach the rank (Expert First Aid - Under Wraps)
    for r in rows(p["ItemEffect"]):
        sp = int(r["SpellID"])
        tgt = sp if sp in rank_step else rank_learn.get(sp)
        if tgt in rank_step:
            for it in effect_items.get(int(r["ID"]), []):
                rank_books.setdefault(rank_step[tgt], set()).add(it)
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
    GATHER_LINES = {186, 182, 393, 356}
    for (line, st), its in rank_books.items():
        if line in PROFESSIONS or line in GATHER_LINES:
            for it in its:
                if it in items and items[it]["Display_lang"]:
                    used_items.add(it)
                    vendor_patterns.add(it)  # vendor price + vendor lists, like patterns
    # ATT: rank-ups learned from a book (ITEM) or a quest (QUEST) instead of a trainer
    rank_source = {}  # (line, step) -> "B" | "Q"
    def att_rank_spells():  # (ATT spell, (line, step)) for rank spells and their learn spells
        for sp in list(att.get("sources", {})) + list(att.get("quests", {})):
            tgt = int(sp) if int(sp) in rank_step else rank_learn.get(int(sp))
            if tgt in rank_step:
                yield sp, rank_step[tgt]
    for sp, (line, st) in att_rank_spells():
        av = att.get("sources", {}).get(str(sp))
        if not av or (line not in PROFESSIONS and line not in GATHER_LINES):
            continue
        for it in av["items"]:
            if it in items:
                rank_books.setdefault((line, st), set()).add(it)
                if line in PROFESSIONS or line in GATHER_LINES:
                    used_items.add(it)
                    vendor_patterns.add(it)
        if "T" not in av["how"]:
            if "Q" in av["how"]:
                rank_source[(line, st)] = "Q"
            elif av["items"]:
                rank_source[(line, st)] = "B"
    out = {sl: [] for sl in list(PROFESSIONS) + sorted(MAKE_LINES)}
    att_decided = {}
    supply_priced = 0
    # corrections from checking the Classic data against Wowhead's Forever pages
    cpath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "forever_checks.json")
    checks = json.load(open(cpath, encoding="utf-8")) if os.path.exists(cpath) else {}
    ck_vend = checks.get("vendors", {}).get("remove", {})
    no_vendor_price = set(checks.get("vendors", {}).get("noVendorPrice", []))
    ck_train = {int(k): v for k, v in checks.get("trainers", {}).get("set", {}).items()}
    ck_de = {tuple(b): loot for b, loot, _ in checks.get("disenchant", {}).get("set", [])}
    ck_farm = checks.get("farm", {})
    ck_gather = checks.get("gather", {}).get("zones", {})
    ck_skin = checks.get("skinning", {}).get("remove", {})

    def vendor_ok(item, npc):  # a vendor the Forever check found doesn't sell it
        rm = ck_vend.get(str(item))
        return not (rm == "all" or (rm and npc in rm))
    recipe_quests = {}  # recipe spell -> ATT quests that teach it
    gated = 0
    # items that teach something (patterns, rank books): vendor handling of their own
    teaching_items = {it for its in taught_by.values() for it in its} | {it for its in rank_books.values() for it in its}
    # recipes where Wowhead's Forever page was checked and beats ATT on the source
    opath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "source_overrides.json")
    wh_first = set() if no_wowhead else {k for k in (json.load(open(opath, encoding="utf-8")) if os.path.exists(opath) else {})
                if not k.startswith("_")}
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
        # AllTheThings' Forever lists decide where they have an answer; the Wowhead and
        # Classic-based choice above stays for recipes ATT doesn't list (or lists as unknown)
        tier_gate = int(checks.get("trainerGate", {}).get("tiers", {}).get(str(att["recipeTier"].get(str(s), 0)), 0))
        av = None if str(s) in wh_first else att.get("sources", {}).get(str(s))
        a_learn = att.get("learnAt", {}).get(str(s))
        w_learn = w[0] if (w and w[0] is not None) else None
        if src != "a" and av:
            how = av["how"]
            if "T" in how:
                if src != "T":
                    cost = None  # Wowhead's fee belongs to Wowhead's source
                src = "T"
                learn = w_learn if w_learn is not None else (a_learn if a_learn is not None else y)
                if w and "Trainer" in w[1]:
                    cost = w[2]
                origin = None
            elif "p" in how:
                pats = sorted(set(pats) | {i for i in av["items"] if i in items})
                src = "p"
                if w_learn is not None:
                    learn = w_learn
                elif a_learn is not None:
                    learn = a_learn
                elif learn is None:
                    ranks = [int(items[i]["RequiredSkillRank"]) for i in pats
                             if int(items[i]["RequiredSkill"]) == int(a["SkillLine"])]
                    learn = min(ranks) if ranks else None
            elif "Q" in how:
                # taught by a quest: learnable when ATT names a giver (recipeQuests below)
                givers = [g for q in att.get("quests", {}).get(str(s), []) for g in q["givers"] if g in att["npcs"]]
                if givers:
                    src, origin, cost = "q", None, None  # no trainer fee for a quest
                    qskill = max([q["skill"] for q in att["quests"][str(s)]] or [0])
                    learn = max(x for x in (w_learn, a_learn, qskill or None, y) if x is not None) \
                        if (w_learn or a_learn or qskill) else y
                    recipe_quests[s] = att["quests"][str(s)]
                else:
                    src, origin = "x", ["Quest"]
            elif "u" in how:
                # ATT: not released yet. Wowhead lists sources for these (data-mined), so
                # allow the pattern only when it's really on your AH: no vendor, no drop hint
                if pats:
                    src, origin = "p", ["Not confirmed in Forever"]
                    if learn is None:
                        learn = w_learn if w_learn is not None else a_learn
                else:
                    src, origin = "x", ["Not in Forever yet"]
            att_decided[src] = att_decided.get(src, 0) + 1
        elif src in ("t", "x") and str(s) in att["recipeTier"] and s not in NOT_TRAINER:
            src, learn, origin = "T", y, None  # ATT lists it under a Forever trainer's tier
        elif src != "a" and a_learn is not None and src in ("T", "p") and w_learn is None:
            learn = a_learn  # Wowhead's learn level first (checked on Forever pages), ATT if none
        if src == "T" and tier_gate and (learn if learn is not None else y) < tier_gate:
            learn = tier_gate  # its trainer offers nothing below the tier's gate
            gated += 1
        if (learn if learn is not None else y) >= MAX_SKILL:
            continue
        o = creates.get(s)
        used_items.update(i for i, _ in reagents[s])
        used_items.update(pats)
        if o:
            used_items.add(o[0])
        # a specialisation recipe (Armorsmith, Dragonscale...): usable only with that spec,
        # whose spell the game knows (IsPlayerSpell)
        spec_id = SPEC_SPELL.get(av["spec"]) if (av and av.get("spec") and src != "a") else None
        fix = checks.get("recipeFixes", {}).get(str(s))
        if fix:
            learn = fix.get("learn", learn)
            cost = fix.get("tc", cost)
        fields = [f"n={lua_str(names[s])}", f"y={y}", f"g={g}", f'src="{src}"']
        if spec_id:
            fields.append(f"spec={spec_id}")
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

    # Gathering tools: the Mining and Skinning spells need a Mining Pick / Skinning Knife
    # in your bags (SpellTotems, like recipes); every Fishing spell needs a fishing pole
    # equipped (SpellEquippedItems: weapon subclass 20). Herbalism needs nothing.
    gather_tool = {}
    for r in rows(p["SpellTotems"]):
        line = {2575: 186, 8613: 393}.get(int(r["SpellID"]))
        cat = line and int(r["RequiredTotemCategoryID_0"] or 0)
        if cat:
            gather_tool[line] = cat
            if cat not in tool_items:
                tool_items[cat] = satisfying(cat)
                used_items.update(tool_items[cat])
    poles = sorted(int(r["ID"]) for r in rows(p["Item"])
                   if r["ClassID"] == "2" and r["SubclassID"] == "20" and int(r["ID"]) in items)
    if poles:
        gather_tool[356] = '"pole"'
        used_items.update(poles)
    if 186 not in gather_tool or 393 not in gather_tool:
        sys.exit("no Mining Pick / Skinning Knife in SpellTotems: did the spell IDs change?")

    GATHER = {186: "Mining", 182: "Herbalism", 393: "Skinning", 356: "Fishing"}
    lines = ["-- GENERATED by tools/gen_data.py from WoW Forever client build " + build
             + (" + Wowhead learn levels/sources" if wowhead else "") + ". Do not edit.",
             "SkillRouteData = {", f'  build = "{build}",', "  professions = {"]
    for sl, name in PROFESSIONS.items():
        sp = f", spell = {rank1[sl]}" if sl in rank1 else ""
        lines += [f'  [{sl}] = {{ name = {lua_str(name)}{sp}, recipes = {{'] + out[sl] + ["  }},"]
    for sl, name in GATHER.items():  # gathering: a zone route; Mining's smelting recipes only for others to use
        sp = f", spell = {rank1[sl]}" if sl in rank1 else ""
        if out.get(sl):
            lines += [f'  [{sl}] = {{ name = {lua_str(name)}{sp}, gather = true, recipes = {{'] + out[sl] + ["  }},"]
        else:
            lines.append(f'  [{sl}] = {{ name = {lua_str(name)}{sp}, recipes = {{}}, gather = true }},')
    # Disenchanting (tools/import_disenchant.py): each crafted item's bracket in Forever's
    # ItemDisenchantLoot (class, quality, item level), its Classic loot. Forever's table
    # leaves the skill at 0, so the Classic rule: item level 20 and below 1, then +25
    # per 5 levels (21-25: 25 ... 61-65: 225).
    dpath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "disenchant.json")
    de = json.load(open(dpath, encoding="utf-8")) if os.path.exists(dpath) else {"rows": [], "loot": {}}
    item_class = {int(r["ID"]): (int(r["ClassID"]), int(r["SubclassID"])) for r in rows(p["Item"])}
    de_of = {}
    for sp_out in {o[0] for o in creates.values()} & used_items:
        r = items.get(sp_out)
        cs = item_class.get(sp_out)
        if not r or not cs:
            continue
        q, lvl = int(r["OverallQualityID"]), int(r["ItemLevel"])
        best = None
        for c, sub, qq, lo, hi, _, key in de["rows"]:
            if c == cs[0] and qq == q and lo <= lvl <= hi and sub in (-1, cs[1]):
                if best is None or sub != -1:
                    best = key
        if best:
            for (bc, bq, blo, bhi), oloot in ck_de.items():
                if bc == cs[0] and bq == q and blo <= lvl <= bhi:
                    best = str(9000 + bc * 1000 + bq * 100 + blo)  # Forever-observed bracket
                    de["loot"][best] = oloot
            skill = 1 if lvl <= 20 else min(300, 25 * ((lvl - 16) // 5))
            de_of[sp_out] = (best, skill)
    # every bracket of Forever's table, for any item (not only crafted ones): a row's loot,
    # or the Forever-observed loot (forever_checks.json) where it covers the row
    de_rows = []
    for cls, sub, q, lo, hi, _skill, key in de["rows"]:
        for (bc, bq, blo, bhi), oloot in ck_de.items():
            if bc == cls and bq == q and blo <= lo and hi <= bhi:
                key = str(9000 + bc * 1000 + bq * 100 + blo)
                de["loot"][key] = oloot
        if key in de["loot"]:
            de_rows.append((cls, sub, q, lo, hi, key))
    for key in {k for k, _ in de_of.values()} | {r[5] for r in de_rows}:
        used_items.update(it for it, *_ in de["loot"][key])
    lines += ["  },", "  -- [itemID] = {name, vendorSellPrice, vendorBuyPrice-or-nil (trade-supply reagents)}",
              "  items = {"]
    for i in sorted(used_items):
        r = items.get(i)
        if not r:
            continue
        # a vendor price: trade-supply names, patterns, or anything Classic vendors of both
        # factions sell without a stock limit (Mild Spices, Flint and Tinder, vials)
        sup_sides = {c for e, lim in npcdata.get("supplies", {}).get(str(i), []) if not lim
                     for c in npcdata["npcs"].get(str(e), {}).get("side", "")}
        vendor = (r["Display_lang"] in VENDOR or i in vendor_patterns
                  or ({"A", "H"} <= sup_sides and i not in teaching_items)) and i not in no_vendor_price
        if vendor and not (r["Display_lang"] in VENDOR or i in vendor_patterns):
            supply_priced += 1
        buy = r["BuyPrice"] if vendor and int(r["BuyPrice"]) > 0 else "nil"
        lines.append(f"    [{i}]={{{lua_str(r['Display_lang'])},{r['SellPrice']},{buy}}},")
    lines += ["  },", "  -- [toolKey] = {name, itemIDs that satisfy it}; negative key = that exact item",
              "  tools = {"]
    tools_start = len(lines)
    for c in sorted(tool_items):
        name = cats[c][2] if c > 0 else items.get(-c, {}).get("Display_lang", str(-c))
        lines.append(f"    [{c}]={{{lua_str(name)},{{{','.join(map(str, tool_items[c]))}}}}},")
    if poles:
        lines.append(f'    ["pole"]={{"Fishing Pole",{{{",".join(map(str, poles))}}},true}},  -- true: equipped, not in bags')
    lines += ["  },", "  -- the tool each gathering profession needs: [skillLine] = toolKey",
              "  gatherTools = { " + ", ".join(f"[{l}]={k}" for l, k in sorted(gather_tool.items())) + " },"]
    lines += ["  -- reagents only made by cooldown crafts (Mooncloth...): avoided unless /sr cdmats on",
              "  cooldownMats = {"]
    for i in sorted(used_items):
        if items.get(i, {}).get("Display_lang") in COOLDOWN_MATS:
            lines.append(f"    [{i}]=true,")
    # Trainers, pattern vendors and their NPCs. AllTheThings' Forever data first
    # (tools/import_att.py: exact zone coordinates, the recipe tier each trainer
    # teaches, vendors' pattern lists); Classic data (tools/import_npcs.py) for NPCs
    # and patterns ATT doesn't list yet.
    conts = npcdata.get("continents", {})

    def continent(mapid, x, y):
        c = conts.get(str(mapid))
        if c is None or x is None:
            return None
        x0, y0, x1, y1 = c["r"]
        u0, v0, u1, v1 = c["u"]
        return c["ui"], round((u0 + (u1 - u0) * (y1 - y) / (y1 - y0)) * 100, 2), round((v0 + (v1 - v0) * (x1 - x) / (x1 - x0)) * 100, 2)

    npc_rows = {}  # key -> (name, side, lua row)
    SIDE_K = {"A": 1, "H": 2, "AH": 3}

    def att_npc(k):
        n = att["npcs"][k]
        key = -(n["id"] * 10 + SIDE_K[n["side"]])  # negative: never collides with Classic IDs
        if key not in npc_rows:
            c = continent(n["map"], n["x"], n["y"])
            v = lambda val: "nil" if val is None else str(val)
            npc_rows[key] = (n["n"], n["side"],
                             f"{{{lua_str(n['n'])},\"{n['side']}\",{v(n['map'])},{v(n['x'])},{v(n['y'])},"
                             f"{v(c and c[0])},{v(c and c[1])},{v(c and c[2])},{lua_str(n['zone'] or '')},"
                             f"{n['zx']},{n['zy']},{n['ui']}}}")
        return key

    # dungeons: where the entrance is (the client's Map table: where your spirit appears
    # when you die inside), so an NPC inside one can still be found and walked to
    entrance, auto_notes = {}, {}
    for r in rows(p["Map"]):
        if r.get("CorpseMapID") not in (None, "", "-1") and r.get("Corpse_0") not in (None, "") \
                and (float(r["Corpse_0"]), float(r["Corpse_1"])) != (0.0, 0.0):  # 0,0 = none given
            entrance[int(r["ID"])] = (int(r["CorpseMapID"]), float(r["Corpse_0"]), float(r["Corpse_1"]), r["MapName_lang"])

    def classic_npc(e):
        n = npcdata["npcs"].get(str(e))
        if not n:
            return None
        if str(n["map"]) not in conts and n["map"] in entrance and n.get("cui") is None:
            m, ex, ey, _name = entrance[n["map"]]
            c = continent(m, ex, ey)
            if c:  # placed at the dungeon's entrance on its continent
                auto_notes[str(e)] = f"inside {_name} (dungeon): the waypoint is its entrance"
                n = dict(n, map=m, x=round(ex, 1), y=round(ey, 1), cui=c[0], cx=c[1], cy=c[2])
        if e not in npc_rows:
            zone = lua_str(n["zone"]) if n["zone"] else "nil"
            v = lambda k: "nil" if n.get(k) is None else str(n[k])
            npc_rows[e] = (n["n"], n["side"],
                           f"{{{lua_str(n['n'])},\"{n['side']}\",{n['map']},{n['x']},{n['y']},"
                           f"{v('cui')},{v('cx')},{v('cy')},{zone},{v('zx')},{v('zy')}}}")
        return e

    # trainers: [line] = {[npc] = bitmask of recipe tiers taught (1 Apprentice, 2 Journeyman,
    # 4 Expert, 8 Artisan); a tier holds its rank-up spell and its recipes
    tr_lines = []
    for line in sorted(set(PROFESSIONS) | set(GATHER)):
        entries = {}
        att_ids = set()
        for k, tiers in att["trainers"].get(str(line), {}).items():
            entries[att_npc(k)] = sum(1 << (t - 1) for t in tiers)
            att_ids.add(att["npcs"][k]["id"])
        for e, rank in npcdata["trainers"].get(str(line), {}).items():
            # Classic fallback: a trainer titled rank R teaches tier R-1 (ATT confirms:
            # Magar <Expert> teaches JOURNEYMAN, Josef <Artisan> EXPERT, Master ARTISAN)
            # Forever trainers teach every rank up to that one (Wowhead Forever: Expert-titled
            # trainers teach Apprentice + Journeyman; gathering trainers Apprentice-Artisan)
            # Forever: a crafting/secondary trainer teaches the one tier below its title and
            # nothing until your skill reaches that tier (Wowhead guide; players at Timothy
            # Worthington). Gathering trainers: every rank up to it (not confirmed otherwise).
            if int(e) not in att_ids and rank >= 2 and classic_npc(int(e)) is not None:
                top = min(rank, 5) - 1
                default = ((1 << top) - 1) if (line in GATHER or line in (185, 129)) else (1 << (top - 1))
                mask = ck_train.get(int(e), default)
                if mask:
                    entries[int(e)] = mask
        if entries:
            tr_lines.append(f"    [{line}]={{" + ",".join(f"[{k}]={m}" for k, m in sorted(entries.items())) + "},")
    lines += ["  },", "  -- trainers: [skillLine] = {[npc] = tiers taught, bits 1 Apprentice 2 Journeyman 4 Expert 8 Artisan}",
              "  trainers = {"] + tr_lines
    # recipe tier (ATT): which trainer tier teaches each recipe / rank-up spell
    recipes_all = {int(r.split("]")[0].strip()[1:]) for l in out.values() for r in l}
    tier_lines = [f"[{sp}]={t}" for sp, t in sorted((int(k), v) for k, v in att["recipeTier"].items()) if sp in recipes_all]
    lines += ["  },", "  -- [recipe spell] = trainer tier that teaches it (1 Apprentice .. 4 Artisan), from ATT",
              "  recipeTier = {"]
    for i in range(0, len(tier_lines), 12):
        lines.append("    " + ",".join(tier_lines[i:i + 12]) + ",")
    # pattern vendors: ATT's where it lists the pattern, else Classic
    vend_lines, pv_lines = [], []
    for i in sorted(vendor_patterns):
        keys = [att_npc(k) for k, _ in att["vendors"].get(str(i), []) if k in att["npcs"]]
        if not keys:
            keys = [k for k in (classic_npc(e) for e in npcdata["vendors"].get(str(i), []) if vendor_ok(i, e))
                    if k is not None]
        if not keys:
            continue
        vend_lines.append(f"    [{i}]={{{','.join(map(str, keys))}}},")
        sides = "".join(sorted({c for k in keys for c in npc_rows[k][1]}))
        names_a = ", ".join(npc_rows[k][0] for k in keys if "A" in npc_rows[k][1])
        names_h = ", ".join(npc_rows[k][0] for k in keys if "H" in npc_rows[k][1])
        pv_lines.append(f"    [{i}]={{\"{sides}\",{lua_str(names_a)},{lua_str(names_h)}}},")
    lines += ["  },", "  -- [patternItem] = {who vendors sell it to \"A\"|\"H\"|\"AH\", Alliance vendors, Horde vendors}",
              "  patternVendors = {"] + pv_lines
    # every other item recipes use that a vendor sells (reagents, tools): ATT's vendors
    # where it lists the item, else Classic vendors without a stock limit
    supply_items = 0
    for i in sorted(used_items - set(vendor_patterns) - teaching_items):
        # ATT's vendors plus Classic's: ATT lists common supplies (thread, dye) at only some of
        # their vendors (others use shared lists outside its Forever folder), so ATT alone
        # would drop most sellers. A Classic NPC ATT already places (same name) isn't repeated.
        keys = [att_npc(k) for k, lim in att["vendors"].get(str(i), []) if k in att["npcs"] and not lim]
        named = {npc_rows[k][0] for k in keys}
        for k in (classic_npc(e) for e, lim in npcdata.get("supplies", {}).get(str(i), [])
                  if not lim and vendor_ok(i, e)):
            if k is not None and k not in keys and npc_rows[k][0] not in named:
                keys.append(k)
        if keys:
            vend_lines.append(f"    [{i}]={{{','.join(map(str, keys))}}},")
            supply_items += 1
    vend_lines.sort(key=lambda l: int(l.split("]")[0].strip()[1:]))
    lines += ["  },", "  -- [item] = {npc keys of vendors selling it} (patterns, books, reagents, tools)",
              "  vendorNpcs = {"] + vend_lines
    # ranks no trainer teaches: books (vendors above) and quests
    lines += ["  },", "  -- rank-up books: [skillLine] = {[rank] = {itemIDs}} (rank 3 Expert, 4 Artisan)", "  rankBooks = {"]
    for line in sorted({l for l, _ in rank_books}):
        if line not in PROFESSIONS and line not in GATHER_LINES:
            continue
        parts = []
        for (l, st), its in sorted(rank_books.items()):
            ok = [i for i in sorted(its) if i in used_items]
            if l == line and ok:
                parts.append(f"[{st}]={{{','.join(map(str, ok))}}}")
        if parts:
            lines.append(f"    [{line}]={{{','.join(parts)}}},")
    lines += ["  },", "  -- rank-up quests: [skillLine] = {[rank] = {{questID, title, skill needed, {giver npcs}}}}",
              "  rankQuests = {"]
    # ATT's quests (exact givers) first; Classic quest data for ranks ATT has none for
    rq = {}  # (line, step) -> rows
    for sp, (line, st) in set(att_rank_spells()):
        if line not in PROFESSIONS and line not in GATHER_LINES:
            continue
        for q in att.get("quests", {}).get(str(sp), []):
            givers = [att_npc(k) for k in q["givers"] if k in att["npcs"]]
            if givers:
                rq.setdefault((line, st), []).append(
                    "{%d,%s,%d,{%s}}" % (q["q"], lua_str(q["t"]), q["skill"], ",".join(map(str, givers))))
    for line, ranks in npcdata.get("rankQuests", {}).items():
        for st, qs in ranks.items():
            if (int(line), int(st)) in rq:
                continue
            for q in qs:
                givers = [k for k in (classic_npc(g) for g in q["givers"]) if k is not None]
                rq.setdefault((int(line), int(st)), []).append(
                    "{%d,%s,%d,{%s}}" % (q["q"], lua_str(q["t"]), q["skill"], ",".join(map(str, givers))))
    for line in sorted({l for l, _ in rq}):
        parts = [f"[{st}]={{{','.join(rows_)}}}" for (l, st), rows_ in sorted(rq.items()) if l == line]
        lines.append(f"    [{line}]={{{','.join(parts)}}},")
    lines += ["  },", "  -- recipes taught by a quest (ATT): [spell] = {{questID, title, skill needed, {giver npcs}}}",
              "  recipeQuests = {"]
    for sp in sorted(recipe_quests):
        qrows = []
        for q in recipe_quests[sp]:
            givers = [att_npc(k) for k in q["givers"] if k in att["npcs"]]
            if givers:
                qrows.append("{%d,%s,%d,{%s}}" % (q["q"], lua_str(q["t"]), q["skill"], ",".join(map(str, givers))))
        if qrows:
            lines.append(f"    [{sp}]={{{','.join(qrows)}}},")
    lv = checks.get("rankLevel", {}).get("levels", {})
    notes = dict(auto_notes)  # dungeon NPCs; a checked note (forever_checks.json) wins
    notes.update({k: v for k, v in checks.get("npcNotes", {}).items() if not k.startswith("_")})
    note_rows = []
    for k, v in sorted(notes.items()):
        for key in sorted(npc_rows):  # Classic key = the ID; ATT keys = -(ID*10 + side)
            if key == int(k) or (key < 0 and -key // 10 == int(k)):
                note_rows.append(f"[{key}]={lua_str(v)}")
    lines += ["  },", "  -- specialisations: [spec spell] = name (recipes carry spec = <spell>)",
              "  specNames = {" + ",".join(f"[{k}]={lua_str(v)}" for k, v in sorted(SPEC_NAME.items())) + "},"]
    lines += ["  -- character level to learn a rank (crafting and secondary professions)",
              "  rankLevel = {" + ",".join(f"[{k}]={v}" for k, v in sorted(lv.items())) + "},",
              "  -- notes shown with an NPC (e.g. inside a dungeon)",
              "  npcNotes = {" + ",".join(note_rows) + "},"]
    lines += ["  -- rank-ups no trainer teaches in Forever (ATT): [skillLine] = {[rank] = \"B\" book | \"Q\" quest}",
              "  rankSource = {"]
    for line in sorted({l for l, _ in rank_source}):
        parts = [f"[{st}]=\"{v}\"" for (l, st), v in sorted(rank_source.items()) if l == line]
        lines.append(f"    [{line}]={{{','.join(parts)}}},")
    lines += ["  },", "  -- [npc] = {name, faction, map, worldX, worldY, continentUiMap, contX, contY, zone, zoneX, zoneY, zoneUiMap}",
              "  -- (zoneUiMap set = exact, from ATT; else Classic spawn, zone resolved by the game)",
              "  npcs = {"]
    for k in sorted(npc_rows):
        lines.append(f"    [{k}]={npc_rows[k][2]},")
    lines += ["  },", "  -- boats/zeppelins: {name, \"A\"|\"H\"|\"AH\", seconds per trip, {map, worldX, worldY}, ...}",
              "  transports = {"]
    for t in npcdata.get("transports", []):
        stops = ",".join("{%d,%d,%d}" % tuple(st) for st in t["stops"])
        lines.append(f"    {{{lua_str(t['name'])},\"{t['side']}\",{t['sec']},{stops}}},")
    lines += ["  },", "  -- continent maps: [map] = {uiMapID, worldX0, worldY0, worldX1, worldY1, uMin, vMin, uMax, vMax}",
              "  continents = {"]
    for m, c in sorted(npcdata.get("continents", {}).items()):
        lines.append(f"    [{m}]={{{c['ui']},{','.join(str(round(v, 3)) for v in c['r'] + c['u'])}}},")
    # Flight paths (Forever client): flight masters and the direct flights between
    # them; a flight's time = length of its route / FLY_SPEED. MountCreatureID_0 is the
    # Horde mount, _1 the Alliance one (a node without a mount for a side isn't theirs).
    taxi_nodes = {}
    for r in rows(p["TaxiNodes"]):
        cont = int(r["ContinentID"])
        side = ("A" if int(r["MountCreatureID_1"]) else "") + ("H" if int(r["MountCreatureID_0"]) else "")
        if cont in (0, 1) and side:
            taxi_nodes[int(r["ID"])] = (cont, float(r["Pos_0"]), float(r["Pos_1"]), side, r["Name_lang"])
    route = {}
    for r in rows(p["TaxiPathNode"]):
        route.setdefault(int(r["PathID"]), []).append((int(r["NodeIndex"]), int(r["ContinentID"]),
                                                        float(r["Loc_0"]), float(r["Loc_1"])))
    flights, used_taxi = [], set()
    for r in rows(p["TaxiPath"]):
        a, b, pid = int(r["FromTaxiNode"]), int(r["ToTaxiNode"]), int(r["ID"])
        pts = sorted(route.get(pid, []))
        if a not in taxi_nodes or b not in taxi_nodes or len(pts) < 2:
            continue
        length = sum(((p2[2] - p1[2]) ** 2 + (p2[3] - p1[3]) ** 2) ** 0.5
                     for p1, p2 in zip(pts, pts[1:]) if p1[1] == p2[1])
        flights.append((a, b, round(length / FLY_SPEED + FLY_OVERHEAD)))
        used_taxi.update((a, b))
    lines += ["  },", "  -- flight paths: nodes [id] = {map, worldX, worldY, \"A\"|\"H\"|\"AH\", name};",
              "  -- flights {from, to, seconds}. Only flight points the character knows are used.",
              "  taxi = { nodes = {"]
    for i in sorted(used_taxi):
        m, x, y, sd, nm = taxi_nodes[i]
        lines.append(f"    [{i}]={{{m},{round(x)},{round(y)},\"{sd}\",{lua_str(nm)}}},")
    lines += ["  }, flights = {"]
    for k in range(0, len(flights), 8):
        lines.append("    " + ",".join("{%d,%d,%d}" % f for f in flights[k:k + 8]) + ",")
    lines += ["  } },"]
    factions = {int(r["ID"]): r["Name_lang"] for r in rows(p["Faction"])}
    # gathering nodes (tools/import_gather.py): [skillLine] = {{node, skill, {zone, spawns, ...}}, ...}
    gpath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gather.json")
    gather = json.load(open(gpath, encoding="utf-8")) if os.path.exists(gpath) else {}
    # rare variants that replace common ore at the same spots now and then: never a
    # planned step (the pool data gives them equal shares, overstating them)
    RARE_NODES = {"Silver Vein", "Gold Vein", "Truesilver Deposit",
                  # special or quest nodes: never a planned step, "gather when you see them"
                  "Black Lotus", "Incendicite Mineral Vein", "Lesser Bloodstone Deposit",
                  "Ooze Covered Silver Vein", "Ooze Covered Gold Vein", "Ooze Covered Mithril Deposit",
                  "Ooze Covered Truesilver Deposit", "Ooze Covered Thorium Vein", "Ooze Covered Rich Thorium Vein"}
    wowhead_nodes = gather.get("_source") == "wowhead"  # Forever's own spot counts (tools/import_nodes.py)
    lines += ["  -- gathering nodes: [skillLine] = {{node, skill needed, {zone, spawns, ...}, rare}, ...} (top zones)",
              "  gather = {"]
    for line, nodes in sorted(gather.items()):
        if line in ("fishing", "_source"):
            continue
        rows_ = []
        for nd in nodes:
            # Classic counts: Forever spawn points where checked; Wowhead's: already Forever's
            zs = nd["zones"] if wowhead_nodes else ck_gather.get(nd["n"], nd["zones"])
            # enough zones that each side's starting areas make the list (the route shows
            # your side's first): Copper Vein's Durotar is 8th, Teldrassil 13th
            top = sorted(zs.items(), key=lambda kv: -kv[1])[:16]
            rows_.append("{%s,%d,{%s}%s}" % (lua_str(nd["n"]), nd["req"],
                                              ",".join(f"{lua_str(z)},{round(c)}" for z, c in top),
                                              ",true" if nd["n"] in RARE_NODES else ""))
        lines.append(f"    [{line}]={{" + ",".join(rows_) + "},")
    # where to farm Cooking ingredients (tools/import_farm.py): used when the AH has no price
    fpath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "farm.json")
    farm = json.load(open(fpath, encoding="utf-8")) if os.path.exists(fpath) else {}
    lines += ["  },", "  -- farm: [item] = {{\"m\", mob, zone, drop%, minLvl, maxLvl} | {\"f\", zone, catch%, fishing level}, ...}",
              "  farm = {"]
    fish_level = {z: lv for z, lv in gather.get("fishing", [])}
    for it, d in sorted(farm.items(), key=lambda kv: int(kv[0])):
        if int(it) not in used_items:
            continue
        rm = ck_farm.get("removeMobs", {}).get(it)
        mobs = [] if rm == "all" else [m for m in d["mobs"]
                                       if not (rm and (m[0] in rm or ("zone:" + m[1]) in rm))]
        fish = d["fish"]
        if it in ck_farm.get("fish", {}):  # Forever catch shares (relative), up to 100%
            fish = [[z, min(100.0, c), fish_level.get(z, 0)] for z, c in ck_farm["fish"][it].items()]
        srcs = [f"{{\"m\",{lua_str(m[0])},{lua_str(m[1])},{m[2]},{m[3]},{m[4]}}}" for m in mobs]
        srcs += [f"{{\"f\",{lua_str(f[0])},{f[1]},{f[2]}}}" for f in fish]
        if srcs:
            lines.append(f"    [{it}]={{{','.join(srcs)}}},")
    spath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "zone_sides.json")
    sides = json.load(open(spath, encoding="utf-8")) if os.path.exists(spath) else {}
    lines += ["  },", "  -- zoneSide: [zone] = \"A\"|\"H\" (Forever's AreaTable); contested zones absent",
              "  zoneSide = {" + ",".join(f"[{lua_str(z)}]={lua_str(v)}" for z, v in sorted(sides.items())) + "},"]
    lines += ["  -- disenchant: loot = {[key] = {item, chance%, min, max, ...}}; of = {[crafted item] = {key, skill}}",
              "  disenchant = {", "    loot = {"]
    for key in sorted({k for k, _ in de_of.values()} | {r[5] for r in de_rows}, key=int):
        lines.append(f"      [{key}]={{{','.join(f'{i},{c},{a},{b}' for i, c, a, b in de['loot'][key])}}},")
    lines += ["    },", "    of = {"]
    ofs = [f"[{i}]={{{k},{sk}}}" for i, (k, sk) in sorted(de_of.items())]
    for i in range(0, len(ofs), 10):
        lines.append("      " + ",".join(ofs[i:i + 10]) + ",")
    lines += ["    },",
              "    -- brackets for any weapon or armour: {class, subclass (-1 any), quality, min ilvl, max ilvl, loot key}",
              "    rows = {"]
    for i in range(0, len(de_rows), 6):
        lines.append("      " + ",".join("{%d,%d,%d,%d,%d,%s}" % r for r in de_rows[i:i + 6]) + ",")
    # can't be disenchanted although they're weapons (enchanters' wands, Classic and
    # Forever's own). This list of facts was noted from Disenchantry, by Shadowblade.
    lines += ["    },", "    never = {" + ",".join(f"[{i}]=true" for i in NEVER_DE) + "},", "  },"]
    kpath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "skinning.json")
    skin = json.load(open(kpath, encoding="utf-8")) if os.path.exists(kpath) else {}
    lines += ["  -- skinZones: [zone] = {first beast level, skinnable spawns at it, at the next level, ...}",
              "  skinZones = {"]
    for z, gone in ck_skin.items():  # levels with no beasts in Forever
        if z in skin:
            for lv in gone:
                k = lv - skin[z][0] + 1
                if 1 <= k < len(skin[z]):
                    skin[z][k] = 0
    for z, v in sorted(skin.items()):
        lines.append(f"    [{lua_str(z)}]={{{v[0]},{','.join(str(round(c)) for c in v[1:])}}},")
    lines += ["  },", "  -- fishing: {zone, fishing level} (you lose fish below level + 95)", "  fishing = {"]
    for z, lvl in gather.get("fishing", []):
        lines.append(f"    {{{lua_str(z)},{lvl}}},")
    lines += ["  },", "  factions = {"]
    for f in sorted(used_factions):
        lines.append(f"    [{f}]={lua_str(factions.get(f, str(f)))},")
    lines += ["  },", "}", ""]
    dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "SkillRoute", "Data.lua")
    with open(dst, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"vendor locations for {supply_items} reagents/tools; {supply_priced} newly vendor-priced; "
          f"{gated} trainer recipes moved to their tier's gate")
    print(f"ATT decided {sum(att_decided.values())} recipe sources {att_decided}; "
          f"rank-ups from ATT: {len(rank_source)} not from trainers, {sum(1 for k in rq if k in rank_source)} with quests")
    print(f"build {build}: " + ", ".join(f"{PROFESSIONS.get(sl, 'Mining smelting')} {len(v)}" for sl, v in out.items())
          + f"; {len(used_items)} items -> {os.path.relpath(dst)}")


if __name__ == "__main__":
    main()
