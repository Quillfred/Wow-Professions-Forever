#!/usr/bin/env bash
# Rebuild all of SkillRoute's data in one go, then run the tests.
#
#   tools/build_all.sh [FOREVER_BUILD]
#
# FOREVER_BUILD defaults to the newest "wowf" build on wago.tools. Downloads go to
# .db2cache/ (game tables, kept per build) and .external/ (AllTheThings' Forever
# folder, the cMaNGOS Classic database); both are git-ignored.
#
# Hand-made inputs stay as committed unless you pass new ones:
#   WOWHEAD_JSON=export.json BLANK_CSV=blank-sources.csv tools/build_all.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
CACHE=$ROOT/.db2cache
EXT=$ROOT/.external
mkdir -p "$CACHE" "$EXT"

latest() { # newest version of a wago.tools product
  curl -fsS --max-time 30 https://wago.tools/api/builds |
    python3 -I -c "import json,sys; print(json.load(sys.stdin)['$1'][0]['version'])"
}
BUILD=${1:-$(latest wowf)}
ERA=$(latest wow_classic_era)
echo "Forever build $BUILD, Classic Era build $ERA"

fetch() { # table build [saved-as]
  local out=$CACHE/${3:-$1-$2}.csv
  [ -s "$out" ] && return 0   # tables are immutable per build
  curl -fsS --max-time 300 "https://wago.tools/db2/$1/csv?build=$2" -o "$out.part" && mv "$out.part" "$out"
}
pids=()
for t in FactionTemplate SpellEffect UiMapAssignment UiMap TaxiPathNode Lock SpellName ItemEffect ItemXItemEffect AreaTable; do
  fetch "$t" "$BUILD" & pids+=($!)
done
fetch SpellEffect "$ERA" SpellEffect-era & pids+=($!)
for p in "${pids[@]}"; do wait "$p"; done
echo "game tables ready"

# cMaNGOS Classic database: only the full dump
if [ ! -d "$EXT/classic-db/.git" ]; then
  git clone -q --depth 1 --filter=blob:none --no-checkout https://github.com/cmangos/classic-db "$EXT/classic-db"
fi
git -C "$EXT/classic-db" fetch -q --depth 1 origin HEAD
git -C "$EXT/classic-db" checkout -q FETCH_HEAD -- Full_DB
CLASSIC=$(ls "$EXT"/classic-db/Full_DB/*.sql.gz | head -1)

# AllTheThings: only its Forever database folder
if [ ! -d "$EXT/att/.git" ]; then
  git clone -q --depth 1 --filter=blob:none --sparse https://github.com/ATTWoWAddon/AllTheThings "$EXT/att"
  git -C "$EXT/att" sparse-checkout set .contrib/.db/forever
else # a shallow copy can't "pull": fetch the newest commit and move to it
  git -C "$EXT/att" fetch -q --depth 1 origin HEAD
  git -C "$EXT/att" reset -q --hard FETCH_HEAD
fi
ATT=$EXT/att/.contrib/.db/forever
echo "external data ready"

if [ -n "${WOWHEAD_JSON:-}" ]; then python3 -I tools/import_wowhead.py "$WOWHEAD_JSON"; fi
if [ -n "${BLANK_CSV:-}" ]; then python3 -I tools/import_sources.py "$BLANK_CSV"; fi
(cd tools && python3 import_vendors.py "$CLASSIC" "$CACHE/FactionTemplate-$BUILD.csv")
(cd tools && python3 import_npcs.py "$CLASSIC" "$CACHE" "$BUILD")
python3 -I tools/import_att.py "$ATT" "$CACHE" "$BUILD"
# Merchant's Favor patterns (cost, reputation) and their vendors -> SkillRoute/Favor.lua.
# The reputation list (tools/favor_rep.json) is re-read from Wowhead only on request:
#   FAVOR_REP=1 tools/build_all.sh   (about 3 minutes, one request per pattern)
if [ "${FAVOR_REP:-}" = 1 ]; then (cd tools && python3 fetch_favor_rep.py "$ATT"); fi
# what each Waylaid Crate accepts (tools/crates.json), also from Wowhead, also on request:
#   CRATES=1 tools/build_all.sh   (~30 requests)
if [ "${CRATES:-}" = 1 ]; then fetch ItemSparse "$BUILD"; python3 -I tools/fetch_crates.py "$ATT" "$CACHE" "$BUILD"; fi
python3 -I tools/import_favor.py "$ATT" "$CACHE" "$BUILD"
(cd tools && python3 import_gather.py "$CLASSIC" "$CACHE" "$BUILD")
fetch SkillLineAbility "$BUILD"; fetch SpellReagents "$BUILD"; fetch ItemDisenchantLoot "$BUILD"
(cd tools && python3 import_farm.py "$CLASSIC" "$CACHE" "$BUILD")
(cd tools && python3 import_disenchant.py "$CLASSIC" "$CACHE" "$BUILD")
python3 -I tools/gen_data.py "$BUILD" "$CACHE"

lua5.1 tests/test_planner.lua | tail -1
lua5.1 tests/smoke_wow.lua | tail -1
echo "done: SkillRoute/Data.lua rebuilt for $BUILD"
