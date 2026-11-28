#!/usr/bin/env python3
"""Herb and ore nodes from Wowhead's WoW Forever map data -> tools/gather.json (and the
spots themselves -> tools/node_points.json).

Input: the export collected from Wowhead Forever's object pages in a browser
(window.g_mapperData per object; see the SkillRoute notes), as JSON:
  {"lists": {"mining": [{id, name}], "herb": [...]},
   "objects": {"<id>": {"name", "mapper": {"<areaID>": [{"count", "coords": [[x, y], ...]}]}}}}
Wowhead's zone IDs are the game's own area IDs; Forever's AreaTable names them and
UiMapAssignment gives the in-game map. Only real outdoor zones are kept (a dungeon or
raid isn't somewhere a gathering route should send you). Alternate object IDs of the
same node are merged and spots deduplicated (0.1 map units).

Skill needed: each node's Wowhead tooltip ("Requires Mining (230)"), cached in
tools/node_reqs.json; only nodes not in the cache are fetched (half a second apart).

Usage: python3 -I tools/import_nodes.py WOWHEAD_EXPORT.json WAGO_CACHE_DIR BUILD
       python3 -I tools/import_nodes.py --from-points WAGO_CACHE_DIR BUILD   (rebuild from the repo copy)
Writes tools/gather.json (Mining and Herbalism from Wowhead; Fishing kept as it was),
tools/node_points.json (every spot, packed, for features that use positions) and
tools/node_reqs.json.
"""
import csv, json, os, re, sys, time, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
LINES = {"mining": 186, "herb": 182}
UA = {"User-Agent": "Mozilla/5.0"}
# Forever models of a node that are the same node in game (same ore, same skill): their
# spots count as that node's. Checked in game: the Amber chunks in Teldrassil are Copper Veins.
SAME_NODE = {"Chunk of Amber": "Copper Vein", "Large Chunk of Amber": "Copper Vein"}


def merged_rows(per_node, reqs):
    """{name: {zone: spots}} -> gather rows, with SAME_NODE's models added to their node."""
    out = {}
    for name, zones in per_node.items():
        to = SAME_NODE.get(name, name)
        if reqs.get(name) is None or reqs.get(to) is None:
            continue
        z = out.setdefault(to, {})
        for zone, n in zones.items():
            z[zone] = z.get(zone, 0) + n
    return sorted(({"n": n, "req": reqs[n], "zones": z} for n, z in out.items() if z), key=lambda x: (x["req"], x["n"]))


def fetch_req(oid):
    url = f"https://nether.wowhead.com/forever/tooltip/object/{oid}"
    for attempt in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=20) as r:
                tip = re.sub(r"<[^>]+>", " ", json.load(r).get("tooltip", ""))
            m = re.search(r"Requires (?:Mining|Herbalism) \((\d+)\)", tip)
            return int(m.group(1)) if m else None
        except Exception:
            time.sleep(2 * (attempt + 1))
    raise SystemExit(f"no answer from Wowhead for object {oid} (nothing written)")


def from_points(cache, build):
    """Rebuild tools/gather.json's Mining and Herbalism from the committed
    tools/node_points.json (no browser export needed): for tools/build_all.sh, after the
    Classic import has rewritten gather.json."""
    uimap = {int(r["ID"]): r for r in csv.DictReader(open(os.path.join(cache, f"UiMap-{build}.csv"), encoding="utf-8"))}
    pts = json.load(open(os.path.join(HERE, "node_points.json"), encoding="utf-8"))
    reqs = json.load(open(os.path.join(HERE, "node_reqs.json"), encoding="utf-8"))
    gpath = os.path.join(HERE, "gather.json")
    gather = json.load(open(gpath, encoding="utf-8"))
    for line in pts.get("lines", {}):
        per_node = {}
        for name in pts["lines"][line]:
            zones = per_node.setdefault(name, {})
            for m, packed in pts["points"][name].items():
                z = uimap[int(m)]["Name_lang"]
                zones[z] = zones.get(z, 0) + len(packed) // 6
        gather[line] = merged_rows(per_node, reqs)
    gather["_source"] = "wowhead"
    json.dump(gather, open(gpath, "w", encoding="utf-8"), separators=(",", ":"), sort_keys=True)
    print(f"Mining and Herbalism from Wowhead spots (tools/node_points.json) -> tools/gather.json")


def main():
    if sys.argv[1] == "--from-points":
        return from_points(sys.argv[2], sys.argv[3])
    src, cache, build = sys.argv[1], sys.argv[2], sys.argv[3]
    d = json.load(open(src, encoding="utf-8"))
    kind = {str(r["id"]): k for k in ("mining", "herb") for r in d["lists"][k]}
    tbl = lambda t: os.path.join(cache, f"{t}-{build}.csv")
    area = {int(r["ID"]): r["AreaName_lang"] for r in csv.DictReader(open(tbl("AreaTable"), encoding="utf-8"))}
    uimap = {int(r["ID"]): r for r in csv.DictReader(open(tbl("UiMap"), encoding="utf-8"))}
    zone_map = {}  # area -> its zone map (UiMap type 3: an outdoor zone)
    for r in csv.DictReader(open(tbl("UiMapAssignment"), encoding="utf-8")):
        a, m = int(r["AreaID"]), int(r["UiMapID"])
        if a and m in uimap and uimap[m]["Type"] == "3":
            zone_map.setdefault(a, m)

    nodes, best_id, skipped = {}, {}, {}
    for oid, o in d["objects"].items():
        k = kind.get(oid)
        name = re.sub(r"\s+", " ", o.get("name") or "").strip()
        if not (k and name and o.get("mapper")):
            continue
        nd = nodes.setdefault(name, {"kind": k, "maps": {}})
        n = 0
        for a, floors in o["mapper"].items():
            a = int(a)
            m = zone_map.get(a)
            if not m:
                skipped[area.get(a, a)] = skipped.get(area.get(a, a), 0) + 1
                continue
            spots = nd["maps"].setdefault(m, {"zone": area[a], "pts": set()})["pts"]
            for fl in floors:
                for x, y in fl.get("coords") or []:
                    spots.add((round(x, 1), round(y, 1)))
                    n += 1
        if n > best_id.get(name, (0, None))[0]:
            best_id[name] = (n, oid)

    rpath = os.path.join(HERE, "node_reqs.json")
    reqs = json.load(open(rpath, encoding="utf-8")) if os.path.exists(rpath) else {}
    for name in sorted(nodes):
        if name not in reqs:
            reqs[name] = fetch_req(best_id[name][1])
            time.sleep(0.5)
    json.dump(reqs, open(rpath, "w", encoding="utf-8"), indent=0, sort_keys=True)

    gpath = os.path.join(HERE, "gather.json")
    gather = json.load(open(gpath, encoding="utf-8")) if os.path.exists(gpath) else {}
    for k, line in LINES.items():
        per_node = {}
        for name, nd in nodes.items():
            if nd["kind"] == k:
                zones = per_node.setdefault(name, {})
                for m in nd["maps"].values():
                    zones[m["zone"]] = zones.get(m["zone"], 0) + len(m["pts"])
        gather[str(line)] = merged_rows(per_node, reqs)
    gather["_source"] = "wowhead"  # gen_data: Forever's own spot counts, no Classic corrections needed
    json.dump(gather, open(gpath, "w", encoding="utf-8"), separators=(",", ":"), sort_keys=True)

    # every spot, packed per zone map: "xxxyyy" (map units x 10) one after another
    pts = {}
    for name, nd in sorted(nodes.items()):
        pts[name] = {str(m): "".join(f"{min(999, round(x * 10)):03d}{min(999, round(y * 10)):03d}"
                                    for x, y in sorted(v["pts"])) for m, v in sorted(nd["maps"].items())}
    lines = {str(LINES[k]): sorted(n for n, nd in nodes.items() if nd["kind"] == k and reqs.get(n) is not None)
             for k in LINES}
    json.dump({"source": "wowhead.com/forever (g_mapperData)", "format": "per node, per zone map: xxxyyy x 10",
               "lines": lines, "points": pts}, open(os.path.join(HERE, "node_points.json"), "w", encoding="utf-8"),
              separators=(",", ":"), sort_keys=True)
    total = sum(len(v["pts"]) for nd in nodes.values() for v in nd["maps"].values())
    print(f"{len(nodes)} nodes, {total} spots in {len({m for nd in nodes.values() for m in nd['maps']})} zones"
          f" -> tools/gather.json, tools/node_points.json"
          + (f"; left out (not an outdoor zone): {skipped}" if skipped else ""))


if __name__ == "__main__":
    main()
