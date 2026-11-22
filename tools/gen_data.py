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
          "ItemSparse", "ItemEffect", "ItemXItemEffect"]
# Not trainer recipes even though no item teaches them (quest rewards etc.). Only
# used when the player knows them.
NOT_TRAINER = {22813, 19435}
# Reagents sold by trade-supply vendors. Used only as a price fallback; Auctionator's
# own vendor price wins when it has one. Matched by name, prices from the client.
VENDOR = {"Coarse Thread", "Fine Thread", "Silken Thread", "Heavy Silken Thread", "Rune Thread",
          "Red Dye", "Blue Dye", "Gray Dye", "Green Dye", "Yellow Dye", "Black Dye", "Orange Dye",
          "Purple Dye", "Bleach", "Salt", "Mild Spices", "Hot Spices", "Refreshing Spring Water",
          "Ice Cold Milk", "Simple Flour", "Empty Vial", "Leaded Vial", "Crystal Vial",
          "Imbued Vial", "Weak Flux", "Strong Flux", "Copper Rod", "Simple Wood"}
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

    items = {}
    for r in rows(p["ItemSparse"]):
        items[int(r["ID"])] = r

    used_items = set()
    out = {sl: [] for sl in PROFESSIONS}
    for s, a in sorted(abil.items()):
        if s not in reagents or s not in names:
            continue  # not a craft (no reagents) -> nothing to plan
        y, g = int(a["TrivialSkillLineRankLow"]), int(a["TrivialSkillLineRankHigh"])
        pats = sorted(taught_by.get(s, ()))
        learn = None
        if a["AcquireMethod"] == "1":
            src = "a"  # learned together with the profession
        elif pats:
            src = "p"
            ranks = [int(items[i]["RequiredSkillRank"]) for i in pats
                     if i in items and int(items[i]["RequiredSkill"]) == int(a["SkillLine"])]
            learn = min(ranks) if ranks else None
        elif s < 100000 and s not in NOT_TRAINER:
            src = "t"  # classic-era trainer recipe; confirmed in-game at the trainer
        else:
            src = "x"  # special/event recipe: only used if the character knows it
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
        if o:
            fields.append(f"out={o[0]}")
            if o[1] != 1:
                fields.append(f"outN={o[1]}")
        fields.append("r={" + ",".join(f"{i},{c}" for i, c in reagents[s]) + "}")
        if pats:
            fields.append("pat={" + ",".join(map(str, pats)) + "}")
        out[int(a["SkillLine"])].append(f"    [{s}]={{{','.join(fields)}}},")

    lines = ["-- GENERATED by tools/gen_data.py from WoW Forever client build " + build + ". Do not edit.",
             "SkillRouteData = {", f'  build = "{build}",', "  professions = {"]
    for sl, name in PROFESSIONS.items():
        lines += [f'  [{sl}] = {{ name = {lua_str(name)}, recipes = {{'] + out[sl] + ["  }},"]
    lines += ["  },", "  -- [itemID] = {name, vendorSellPrice, vendorBuyPrice-or-nil (trade-supply reagents)}",
              "  items = {"]
    for i in sorted(used_items):
        r = items.get(i)
        if not r:
            continue
        buy = r["BuyPrice"] if r["Display_lang"] in VENDOR else "nil"
        lines.append(f"    [{i}]={{{lua_str(r['Display_lang'])},{r['SellPrice']},{buy}}},")
    lines += ["  },", "}", ""]
    dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "SkillRoute", "Data.lua")
    with open(dst, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"build {build}: " + ", ".join(f"{PROFESSIONS[sl]} {len(v)}" for sl, v in out.items())
          + f"; {len(used_items)} items -> {os.path.relpath(dst)}")


if __name__ == "__main__":
    main()
