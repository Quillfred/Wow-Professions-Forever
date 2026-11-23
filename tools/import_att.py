#!/usr/bin/env python3
"""Forever trainers and pattern vendors from AllTheThings (MIT licence,
github.com/ATTWoWAddon/AllTheThings, folder .contrib/.db/forever).

ATT's Forever database lists, per zone, each profession trainer (with the recipe
group it teaches: APPRENTICE / JOURNEYMAN / EXPERT / ARTISAN, each group holding its
rank-up spell and recipes) and each vendor (with the patterns it sells), with exact
zone coordinates and faction. Zone coordinates are converted to world and continent
positions with Forever's own map tables (UiMapAssignment), for travel times.

Usage: python3 -I tools/import_att.py ATT_FOREVER_DIR WAGO_CACHE_DIR BUILD
Writes tools/att_forever.json.
"""
import csv, json, os, re, sys

RECIPE_PREFIX = {"ALCHEMY": 171, "BLACKSMITHING": 164, "ENCHANTING": 333, "ENGINEERING": 202,
                 "LEATHERWORKING": 165, "TAILORING": 197, "COOKING": 185, "FIRST_AID": 129}
TIERS = {"APPRENTICE": 1, "JOURNEYMAN": 2, "EXPERT": 3, "ARTISAN": 4}


def strip_comments(text):
    """Blank out comments and string contents (same length, so offsets stay valid)."""
    out, i, n = list(text), 0, len(text)
    while i < n:
        c = text[i]
        if c == "-" and text.startswith("--", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = " "
            i = j
        elif c in "\"'":
            j = i + 1
            while j < n and text[j] != c:
                j += 2 if text[j] == "\\" else 1
            for k in range(i + 1, min(j, n)):
                out[k] = " "
            i = j + 1
        else:
            i += 1
    return "".join(out)


def block_end(code, open_paren):
    """Index of the ')' closing the '(' at open_paren (code has comments blanked)."""
    depth = 0
    for k in range(open_paren, len(code)):
        ch = code[k]
        if ch in "({":
            depth += 1
        elif ch in ")}":
            depth -= 1
            if depth == 0:
                return k
    return len(code)


def read_tiers(struct_dir):
    """{skillLine: {tierName: {"rank": 1-4 or None, "spells": [...]}}}"""
    out = {}
    for fn in os.listdir(struct_dir):
        text = open(os.path.join(struct_dir, fn), encoding="utf-8").read()
        code = strip_comments(text)
        m = re.search(r"\b([A-Z_]+)_RECIPES\s*=\s*\{", code)
        if not m or m.group(1) not in RECIPE_PREFIX:
            continue
        line = RECIPE_PREFIX[m.group(1)]
        top_end = block_end(code, m.end() - 1)
        tiers = {}
        for t in re.finditer(r"^\t([A-Z_]+)\s*=", code[m.end():top_end], re.M):
            start = m.end() + t.end()
            brace = code.find("{", start)
            end = block_end(code, brace) if brace >= 0 else start
            body = code[brace:end]
            spells = [int(x) for x in re.findall(r"\br\((\d+)", body)]
            rank = None
            for s, rk in re.findall(r"\br\((\d+),\s*\{[^}]*?\brank\s*=\s*(\d)", body):
                rank = int(rk)
            tiers[t.group(1)] = {"rank": rank, "spells": spells}
        out[line] = tiers
    return out


def read_maps(path):
    code = open(path, encoding="utf-8").read()
    return {k: int(v) for k, v in re.findall(r"\b([A-Z_0-9]+)\s*=\s*(\d+)\s*;", code)}


def main():
    att, cache, build = sys.argv[1], sys.argv[2], sys.argv[3]
    maps = read_maps(os.path.join(att, ".config", "constants", "maps.lua"))
    tiers = read_tiers(os.path.join(att, ".config", "structures"))

    # zone (uiMap) -> world rectangle, to turn zone coordinates into world positions
    tbl = lambda t: os.path.join(cache, f"{t}-{build}.csv")
    uimap = {int(r["ID"]): r for r in csv.DictReader(open(tbl("UiMap"), encoding="utf-8"))}
    assigns = {}
    for r in csv.DictReader(open(tbl("UiMapAssignment"), encoding="utf-8")):
        assigns.setdefault(int(r["UiMapID"]), []).append(r)

    def to_world(ui, u, v):
        for a in assigns.get(ui, []):
            u0, v0, u1, v1 = (float(a[k]) for k in ("UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1"))
            if u0 <= u <= u1 and v0 <= v <= v1 and u1 > u0 and v1 > v0:
                x0, y0, x1, y1 = (float(a[f"Region_{i}"]) for i in (0, 1, 3, 4))
                return int(a["MapID"]), x1 - (v - v0) / (v1 - v0) * (x1 - x0), y1 - (u - u0) / (u1 - u0) * (y1 - y0)
        return None

    npcs, trainers, vendors = {}, {}, {}
    zone_dir = os.path.join(att, "zones")
    for root, _, files in os.walk(zone_dir):
        for fn in files:
            if not fn.endswith(".lua"):
                continue
            text = open(os.path.join(root, fn), encoding="utf-8").read()
            code = strip_comments(text)
            # context spans: vendor sections and profession (trainer) sections
            spans = []
            for m in re.finditer(r"\bn\(VENDORS\s*,", code):
                spans.append(("vendor", m.start(), block_end(code, m.start() + 1)))
            for m in re.finditer(r"\bprof\(([A-Z_]+)\s*,", code):
                spans.append(("trainer", m.start(), block_end(code, m.start() + 4)))
            for m in re.finditer(r"\bn\((\d+)\s*,\s*\{", code):
                start = m.start()
                ctx = [k for k, a, b in spans if a < start < b]
                if not ctx:
                    continue
                end = block_end(code, start + 1)
                body = code[start:end]
                # name/title from the comment after the opening brace
                head = text[m.end():text.find("\n", m.end())]
                nm = re.match(r"\s*--\s*(.*?)\s*(?:<(.*)>)?\s*$", head)
                name = nm.group(1) if nm else str(m.group(1))
                title = nm.group(2) if nm else None
                cm = re.search(r"\bcoords?\s*=\s*\{\s*\{?\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*MAP\.([A-Z_0-9.]+)", body)
                if not cm:
                    continue
                ui = maps.get(cm.group(3).split(".")[-1]) if "." in cm.group(3) else maps.get(cm.group(3))
                if not ui:
                    continue
                zx, zy = float(cm.group(1)), float(cm.group(2))
                side = "H" if "HORDE_ONLY" in body else "A" if "ALLIANCE_ONLY" in body else "AH"
                key = f"{m.group(1)}:{side}"  # the same NPC can be listed per faction
                w = to_world(ui, zx / 100, zy / 100)
                npc = npcs.setdefault(key, {"id": int(m.group(1)), "n": name, "title": title, "side": side,
                                            "ui": ui, "zone": uimap.get(ui, {}).get("Name_lang"),
                                            "zx": zx, "zy": zy, "map": w[0] if w else None,
                                            "x": round(w[1], 1) if w else None, "y": round(w[2], 1) if w else None})
                if "trainer" in ctx:
                    for prefix, tier in re.findall(r"\b([A-Z_]+)_RECIPES\.([A-Z_]+)", body):
                        if prefix in RECIPE_PREFIX and tier in TIERS:
                            trainers.setdefault(str(RECIPE_PREFIX[prefix]), {}).setdefault(key, set()).add(TIERS[tier])
                if "vendor" in ctx:
                    for im in re.finditer(r"\bi\((\d+)", body):
                        limited = "isLimited" in body[im.end():im.end() + 80].split("i(")[0]
                        vendors.setdefault(im.group(1), {})[key] = limited

    recipe_tier = {}
    for line, ts in tiers.items():
        for tname, t in ts.items():
            if tname in TIERS:
                for s in t["spells"]:
                    recipe_tier.setdefault(str(s), TIERS[tname])
    out = {"npcs": npcs,
           "trainers": {l: {k: sorted(v) for k, v in d.items()} for l, d in trainers.items()},
           "vendors": {it: [[k, lim] for k, lim in d.items()] for it, d in vendors.items()},
           "recipeTier": recipe_tier}
    dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "att_forever.json")
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(out, f, separators=(",", ":"), sort_keys=True)
    nt = sum(len(d) for d in out["trainers"].values())
    print(f"{len(npcs)} NPCs, {nt} trainer entries in {len(out['trainers'])} professions, "
          f"{len(vendors)} items sold, {len(recipe_tier)} recipes with a trainer tier -> {os.path.relpath(dst)}")


if __name__ == "__main__":
    main()
