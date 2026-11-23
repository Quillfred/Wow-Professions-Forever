-- Run from the repo root: lua5.1 tests/test_planner.lua
SkillRouteTestNS = {}
dofile("SkillRoute/Data.lua")
dofile("SkillRoute/Planner.lua")
local P = SkillRouteTestNS.Planner
local fails = 0
local function check(cond, msg) if not cond then fails = fails + 1; print("FAIL: " .. msg) end end
local function near(a, b) return math.abs(a - b) < 1e-6 * math.max(1, math.abs(a), math.abs(b)) end

-- 1. skill-up chance (Classic formula) and colours
local r = { y = 110, g = 145 }
check(P.Chance(r, 100) == 1, "orange = 100%")
check(P.Chance(r, 110) == 1, "at yellow = 100%")
check(near(P.Chance(r, 130), 15 / 35), "linear yellow->grey")
check(P.Chance(r, 145) == 0, "grey = 0")
check(near(P.Chance(r, 130, 0.2), 15 / 35 + (20 / 35) * 0.2), "bonus on failed roll")
check(P.Color(r, 109) == "orange" and P.Color(r, 110) == "yellow" and P.Color(r, 127) == "green" and P.Color(r, 145) == "grey", "colours")

-- Mock market: 3x vendor sell price for everything except a few deliberately missing items.
local T = SkillRouteData.professions[197].recipes
local items = SkillRouteData.items
local missing = {}
local function price(id)
  if missing[id] then return nil end
  local it = items[id]; if not it then return nil end
  if it[3] then return it[3], false end
  return (it[2] > 0 and it[2] or 1) * 3, false
end
local function ctxFor(from, to, known, extra)
  local c = { recipes = T, items = items, skill = from, target = to, known = known or {}, trainer = {}, price = price }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

-- 2. structural invariants on a 1 -> 300 plan
local t0 = os.clock()
local plan = P.Plan(ctxFor(1, 300))
local ms = (os.clock() - t0) * 1000
local s = 1
for _, st in ipairs(plan.steps) do
  check(st.from == s, "steps contiguous at " .. s); s = st.to
  if st.spell then
    local rr = T[st.spell]
    local learnAt = P.LearnAt(st.spell, rr, ctxFor(1, 300))
    check(st.to <= rr.g, st.name .. " used while grey")
    check(not rr.cd, st.name .. " has a cooldown and can't be ground")
    if st.learn == "pattern" then -- vendor pattern bought to fill a gap
      check(((rr.from and rr.from:find("Vendor")) or st.unlock.via == "ah") and P.RepOK({}, rr, st.unlock.item) and st.learnCost,
        st.name .. ": only vendor/AH patterns whose reputation you have are bought")
      check((rr.learn or rr.y) <= st.from, st.name .. " pattern used before its learn level")
    else
      check(learnAt and learnAt <= st.from, st.name .. " used before it can be learned")
      check(rr.src ~= "p" and rr.src ~= "x", st.name .. " is not obtainable without a pattern")
    end
  end
end
check(s == 300, "plan reaches target")
print(("1->300 Tailoring plan: %d steps, %d gaps, %.1f ms"):format(#plan.steps, #plan.gaps, ms))

-- 3. optimality: without intermediate credit or stickiness, the DP total equals the
-- sum over points of the cheapest (reagent cost / chance); crafting reagents
-- yourself (bolts) can only make it cheaper.
local ctx = ctxFor(110, 300, nil, { sticky = 0, noCredit = true })
local p0 = P.Plan(ctx)
local brute = 0
for sk = 110, 299 do
  local m = math.huge
  for spell, rr in pairs(T) do
    local la = P.LearnAt(spell, rr, ctx)
    if la and la <= sk then
      local ch = P.Chance(rr, sk)
      local c = 0
      for i = 1, #rr.r, 2 do local pr = price(rr.r[i]); if not pr then c = nil break end c = c + pr * rr.r[i + 1] end
      if c and ch > 0 then
        if c < 1 then c = 1 end
        if c / ch < m then m = c / ch end
      end
    end
  end
  if m < math.huge then brute = brute + m end
end
check(p0.expected <= brute + 1e-6, ("DP %.1f should be <= brute force %.1f"):format(p0.expected, brute))
local sticky = P.Plan(ctxFor(110, 300))
print(("110->300 expected cost: no-credit optimal %.0fc, final plan %.0fc"):format(p0.expected, sticky.expected))

-- 3b. regression (in-game report): when vendoring the product covers the mats,
-- steps must not look free and the route must not pick huge green grinds.
local cheap = function(id) local it = items[id]; if not it then return nil end
  if it[3] then return it[3], false end; return math.max(1, it[2]), false end
local pc = P.Plan(ctxFor(110, 300, nil, { price = cheap }))
for _, st in ipairs(pc.steps) do
  if st.spell and not st.credited then
    check(st.cost >= st.crafts * 1, st.name .. " shown as free")
    check(not st.alt or st.alt.ours <= st.alt.perPoint * 1.03 + 1e-6,
      ("%s chosen although %s is cheaper per point"):format(st.name, st.alt and st.alt.name or "?"))
  end
end
-- intermediates are only credited for what the route uses
for item, made in pairs(pc.made) do
  local left = pc.leftover[item] or 0
  if left > 0.5 then
    for _, st in ipairs(pc.steps) do
      if st.spell and T[st.spell].out == item and st.credited then
        check(left / made < 0.5, ("%s: %d of %d made are never used but still credited"):format(st.name, left, made))
      end
    end
  end
end
-- steps never cross a rank cap
for _, st in ipairs(pc.steps) do
  for cap = 75, 225, 75 do check(not (st.from < cap and st.to > cap), st.name or "gap" .. " crosses cap " .. cap) end
end
print("\nRoute with Forever-like cheap cloth (vendor ~ AH):")
for _, st in ipairs(pc.steps) do
  if st.gap then print(("  %3d-%3d  GAP"):format(st.from, st.to))
  else print(("  %3d-%3d  ~%5.1f x %-32s %8dc %s"):format(st.from, st.to, st.crafts, st.name, st.cost, st.credited and "(intermediate)" or "")) end
end

-- 4. a known pattern recipe becomes usable; an unknown one never is
local pat; for spell, rr in pairs(T) do if rr.src == "p" and rr.y >= 160 and rr.y < 200 then pat = spell break end end
local pk = P.Plan(ctxFor(150, 220, { [pat] = true }))
local usedUnknown = false
for _, st in ipairs(P.Plan(ctxFor(150, 220)).steps) do if st.spell == pat then usedUnknown = true end end
check(not usedUnknown, "unknown pattern never used")

-- 5. confirmed trainer level overrides the 'yellow' assumption
local ds = 3848 -- Double-stitched Woolen Shoulders: Wowhead learn 85, yellow 110
check(T[ds].src == "T" and P.LearnAt(ds, T[ds], ctxFor(80, 110)) == 85, "Wowhead learn level used")
local c5 = ctxFor(80, 110); c5.trainer = { [ds] = { req = 90, cost = 500 } }
check(P.LearnAt(ds, T[ds], c5) == 90, "in-game trainer scan wins over data file")
check(P.LearnAt(1, { y = 120, g = 150, src = "t" }, ctxFor(100, 110)) == 120, "unconfirmed trainer recipe waits for yellow")
check(P.LearnAt(1, { y = 120, g = 150, src = "x" }, ctxFor(100, 110)) == nil, "quest/special recipe never assumed")
-- an orange window is used: White Woolen Dress learnable at 85, guaranteed skill-ups until 110
local ow = P.Plan(ctxFor(85, 110))
local guaranteed = 0
for _, st in ipairs(ow.steps) do if st.spell and st.color == "orange" then guaranteed = guaranteed + 1 end end
check(guaranteed > 0, "orange (100%) window used between 85 and 110")

-- 6. unpriced reagents exclude a recipe instead of guessing
missing[2321] = true -- Fine Thread
for _, st in ipairs(P.Plan(ctxFor(110, 150)).steps) do
  if st.spell then
    local rr = T[st.spell]
    for i = 1, #rr.r, 2 do check(rr.r[i] ~= 2321, st.name .. " needs unpriced Fine Thread") end
  end
end
missing[2321] = nil

-- 7. shopping list: owned items subtracted, products of earlier steps reused
local have = { [2589] = 5 }
local p7 = P.Plan(ctxFor(1, 75, nil, { have = function(id) return have[id] or 0 end }))
for _, b in ipairs(p7.shopping.buy) do
  check(b.buy == math.max(0, b.need - b.have), "buy = need - have for " .. b.name)
  if b.item == 2589 then check(b.have == 5, "linen owned counted") end
end

-- 8. gaps list pattern suggestions
local p8 = P.Plan(ctxFor(250, 300, nil, { noPatterns = true }))
check(#p8.gaps > 0, "no trainer recipes 255+ -> gap expected without buying patterns")
if p8.gaps[1] then check(#p8.gaps[1].patterns > 0, "gap has pattern suggestions") end
local p8b = P.Plan(ctxFor(250, 300))
check(#p8b.gaps == 0, "vendor patterns fill the 255+ gap")

-- 9. vendor patterns bought only when they pay for themselves
local function total(plan)
  local t = plan.expected
  for _, b in pairs(plan.unlocks or {}) do t = t + b.price end
  return t
end
local base = P.Plan(ctxFor(110, 250, nil, { noPatterns = true }))
check(#base.gaps == 0, "110-250 has trainer recipes everywhere")
local t0p = os.clock()
local withP = P.Plan(ctxFor(110, 250))
local searchMs = (os.clock() - t0p) * 1000
local bought = 0
for key, b in pairs(withP.unlocks) do
  local spell = b.spell
  bought = bought + 1
  -- leave this one pattern out: the route must get more expensive
  local fixed = {}
  for k in pairs(withP.unlocks) do if k ~= key then fixed[k] = true end end
  local without = P.Plan(ctxFor(110, 250, nil, { fixedUnlocks = fixed }))
  check(total(without) > total(withP), T[spell].n .. " pattern doesn't pay for itself")
  local onList = false
  for _, it in ipairs(withP.shopping.buy) do if it.pattern and it.item == b.item then onList = true end end
  check(onList, T[spell].n .. " pattern missing from shopping list")
  check((b.via == "ah" or (T[spell].from or ""):find("Vendor")) and P.RepOK({}, T[spell], b.item) and not T[spell].cd,
    T[spell].n .. " not a buyable pattern")
end
check(total(withP) <= total(base) + 1e-6, "patterns never make the route dearer")
print(("110->250: %d patterns bought, %.0fc -> %.0fc (%.1f%% cheaper), search %.0f ms"):format(
  bought, total(base), total(withP), 100 * (1 - total(withP) / total(base)), searchMs))
-- reusing the choice (bag change) skips the search
local fixedAll = {}
for k in pairs(withP.unlocks) do fixedAll[k] = true end
local t1 = os.clock()
local again = P.Plan(ctxFor(110, 250, nil, { fixedUnlocks = fixedAll }))
check(math.abs(total(again) - total(withP)) < 1, "fixed pattern choice reproduces the plan")
print(("re-plan with cached pattern choice: %.1f ms"):format((os.clock() - t1) * 1000))

-- 10. tools (rods, hammers, spanners)
local D = SkillRouteData
local function plan(line, from, to, priceFn, owned, standing)
  return P.Plan({ recipes = D.professions[line].recipes, items = items, tools = D.tools,
    skill = from, target = to, known = {}, trainer = {}, price = priceFn or price, standing = standing,
    hasTool = function(k) return owned and owned[k] or false end })
end
-- quest recipes: allowing them never makes a route cost more (they're a last resort
-- at 1g of effort); the 1g never shows as a training fee
for line, prof in pairs(D.professions) do
  if not prof.gather then
    local ok = {}
    for s, r in pairs(prof.recipes) do if r.src == "q" then ok[s] = true end end
    local function pl(q)
      return P.Plan({ recipes = prof.recipes, items = items, tools = D.tools, skill = 1, target = 300, maxSkill = 300,
        known = {}, trainer = {}, price = price, questOK = q, hasTool = function() return true end })
    end
    local without, with = pl({}), pl(ok)
    check(with.total <= without.total + 1, ("%s: quest recipes allowed made the route dearer (%d -> %d)")
      :format(prof.name, without.total, with.total))
    local qfee = 0
    for _, st in ipairs(with.steps) do if st.learn == "quest" then qfee = qfee + 1 end end
    check(qfee == 0 or with.fees == without.fees, prof.name .. ": quest effort counted as a training fee")
  end
end

-- every NPC has a name, not its ID (ATT lists some quest givers over two lines)
do
  local bad = {}
  for k, n in pairs(D.npcs) do if tostring(n[1]):match("^%d+$") then bad[#bad + 1] = k .. "=" .. n[1] end end
  check(#bad == 0, "NPCs named by their ID: " .. table.concat(bad, ", "))
  check(D.npcs[-81253] and D.npcs[-81253][1] == "Dirge Quikcleave", "Clamlette Surprise giver named")
end

-- the Forever check (tools/forever_checks.json) is applied to the data
do
  check(not (D.trainers[165] or {})[7866], "leatherworking specialization trainer 7866 teaches no rank in Forever")
  check((D.trainers[356] or {})[14740] == 3, "Katoom the Angler: Apprentice + Journeyman")
  check((D.trainers[171] or {})[11042] == 2, "crafting trainers teach one tier (Sylvanna Forestmoon: Journeyman)")
  check(D.professions[197].recipes[12079].learn == 200, "Red Mageweave Bag: its Master trainer offers nothing below 200")
  check(D.rankLevel[4] == 35 and D.rankLevel[3] == 20 and D.rankLevel[2] == 10, "character level per rank")
  check(D.npcNotes[11073] and D.npcNotes[11073]:find("Uldaman"), "Annora's note: inside Uldaman")
  check(D.items[858] and D.items[858][3] == nil, "Lesser Healing Potion: no vendor price (limited stock everywhere)")
  check(D.items[6887] and D.items[6887][3] == nil and not D.vendorNpcs[6887], "Spotted Yellowtail: no vendor")
  check(not D.farm[3821], "Goldthorn: no mob drops it in Forever")
  local ok = true
  for _, s in ipairs(D.farm[2924] or {}) do if s[3] ~= "Loch Modan" then ok = false end end
  check(ok, "Crocolisk Meat: Loch Modan only")
  local g = D.gather[186][1]
  check(g[1] == "Copper Vein" and g[3][1] == "Zephras Isle", "Copper Vein: Forever spawn counts (Zephras Isle leads)")
  local found = false
  for item, v in pairs(D.disenchant.of) do if v[1] == 13256 then found = true end end
  check(found and D.disenchant.loot[13256][1] == 16204, "green armor 56-60: Forever-observed disenchant (no shard)")
end

-- every step in every profession: its tools are owned or acquired by the plan, in time
for line, prof in pairs(D.professions) do
  local pl = plan(line, 1, 300)
  for _, st in ipairs(pl.steps) do
    for _, t in ipairs(st.spell and prof.recipes[st.spell].tool or {}) do
      local u = pl.unlocks["t:" .. t]
      check(u ~= nil, ("%s: %s needs %s but the plan never gets it"):format(prof.name, st.name, D.tools[t][1]))
      check(not u or u.from <= st.from, ("%s: %s used before its tool can be made"):format(prof.name, st.name))
    end
  end
end
-- Enchanting with no rods on the AH: the rod is crafted, on the shopping list as a tool
local noRods = {}
for _, t in ipairs({ 373, 374, 375, 376, 377 }) do for _, it in ipairs(D.tools[t][2]) do noRods[it] = true end end
local ench = plan(333, 1, 120, function(id) if noRods[id] then return nil end return price(id) end)
local rod = ench.unlocks["t:373"]
check(rod and rod.craftSpell, "Enchanting crafts its Runed Copper Rod when it can't be bought")
local listed = false
for _, c in ipairs(ench.shopping.craft) do if c.tool then listed = true end end
check(listed, "crafted rod is on the shopping list")
-- Blacksmithing: buys a hammer unless one is owned
local bs = plan(164, 1, 100)
local hammer = bs.unlocks["t:162"]
check(hammer and not hammer.craftSpell and hammer.price == D.items[5956][3], "buys a Blacksmith Hammer from a vendor")
local onList = false
for _, b in ipairs(bs.shopping.buy) do if b.tool and b.item == 5956 then onList = true end end
check(onList, "hammer on the shopping list")
check(plan(164, 1, 100, nil, { [162] = true }).unlocks["t:162"] == nil, "owned hammer is not bought again")

-- 10b. a recipe needing two purchases (formula + rod) is considered: Enchant Weapon -
-- Strength needs its formula (Thorium Brotherhood Friendly) AND a Runed Arcanite Rod.
-- Make both cheap and give the reputation: both bought.
local ws = 23799
local cheapCombo = function(id)
  if id == 16207 then return 1, false end -- Runed Arcanite Rod
  local wr = D.professions[333].recipes[ws]
  for _, it in ipairs(wr.pat) do if id == it then return 1, false end end
  for i = 1, #wr.r, 2 do if id == wr.r[i] then return 1, false end end -- its reagents
  return price(id)
end
local owned4 = { [373] = true, [374] = true, [375] = true, [376] = true }
local friendlyTB = function(f) return f == 59 and 4 or nil end
local combo = plan(333, 290, 300, cheapCombo, owned4, friendlyTB)
check(combo.unlocks["p:" .. ws] and combo.unlocks["t:377"], "formula + rod bought together when they pay off")
local usedCombo = false
for _, st in ipairs(combo.steps) do if st.spell == ws then usedCombo = true end end
check(usedCombo, "Enchant Weapon - Strength used once both are bought")
-- and not when the rod is too expensive to pay off
local dearRod = function(id) if id == 16207 then return 1e9, false end return cheapCombo(id) end
check(not plan(333, 290, 300, dearRod, owned4, friendlyTB).unlocks["t:377"], "an expensive rod is not bought")
check(not plan(333, 290, 300, cheapCombo, owned4).unlocks["p:" .. ws], "no reputation -> formula not bought")

-- 10d. rank caps already trained don't split steps (Expert trained: cap 225)
local splitAt150 = false
local ex = P.Plan({ recipes = D.professions[333].recipes, items = items, tools = D.tools, hasTool = function() return true end,
  skill = 130, target = 225, maxSkill = 225, known = {}, trainer = {}, price = price })
for _, st in ipairs(ex.steps) do if st.to == 150 and ex.steps[_ + 1] and ex.steps[_ + 1].spell == st.spell then splitAt150 = true end end
check(not splitAt150, "no split at 150 when Expert is already trained")

-- 10c. First Aid: the Artisan bandages (confirmed by ATT's trainer lists) close the old 270-290 gap
local fa = plan(129, 1, 300)
check(fa.gapPoints == 0, "First Aid plans all the way to 300")
for _, st in ipairs(fa.steps) do
  if st.spell == 18630 or st.spell == 18629 then check(st.learn == "trainer", st.name .. " is a confirmed trainer recipe") end
end

-- 10e. drop patterns: bought only on a real AH price, never on an estimate
local dropPat = 18444 -- Runecloth Headband: a drop pattern, 250-295
check(T[dropPat] and T[dropPat].from == "Drop", "Runecloth Headband is a drop pattern")
local anyPattern = {}
for _, r in pairs(T) do for _, it in ipairs(r.pat or {}) do anyPattern[it] = true end end
local patItem = T[dropPat].pat[1]
local function only(id, est)  -- everything unpriced except this pattern's reagents and the pattern
  local r = T[dropPat]
  if id == patItem then return 1, est end
  if anyPattern[id] then return nil end -- no other pattern on the AH
  for i = 1, #r.r, 2 do if id == r.r[i] then return 1, false end end
  return price(id)
end
local function pp(est) return P.Plan({ recipes = T, items = items, tools = D.tools, hasTool = function() return true end,
  skill = 250, target = 280, known = {}, trainer = {}, price = function(id) return only(id, est) end }) end
local seen = pp(false)
check(seen.unlocks["p:" .. dropPat] and seen.unlocks["p:" .. dropPat].via == "ah", "drop pattern bought on its AH price")
check(not pp(true).unlocks["p:" .. dropPat], "never bought on an estimated price")

-- 10f. cooldown-only materials (Mooncloth) avoided when asked
check(D.cooldownMats and next(D.cooldownMats), "cooldown materials in the data")
local function usesCd(pl)
  for _, st in ipairs(pl.steps) do
    if st.spell then local r = T[st.spell]; for i = 1, #r.r, 2 do if D.cooldownMats[r.r[i]] then return st.name end end end
  end
end
local allowCd = P.Plan(ctxFor(250, 300))
local avoidCd = P.Plan(ctxFor(250, 300, nil, { avoidMats = D.cooldownMats }))
check(not usesCd(avoidCd), "avoidMats: no step uses Mooncloth/Arcanite (" .. (usesCd(avoidCd) or "none") .. ")")
-- forced case: only Mooncloth Robe (and its mats) is priced
local robe = 22902
local function robeOnly(id)
  local r = T[robe]
  for _, it in ipairs(r.pat) do if id == it then return 1, false end end
  for i = 1, #r.r, 2 do if id == r.r[i] then return 1, false end end
  return nil
end
local withRobe = P.Plan(ctxFor(290, 300, nil, { price = robeOnly }))
local noRobe = P.Plan(ctxFor(290, 300, nil, { price = robeOnly, avoidMats = D.cooldownMats }))
check(usesCd(withRobe) == "Mooncloth Robe", "Mooncloth Robe used when cooldown mats are allowed")
check(not usesCd(noRobe) and noRobe.gapPoints > 0, "left out (gap shown) when they are avoided")
print(("250->300 with cooldown mats: %s; without: %s, %d gap points"):format(
  usesCd(allowCd) or "none used", "none used", avoidCd.gapPoints))

-- 10g. vendor patterns only from vendors of your faction (Bright Yellow Shirt: Alliance only)
local bys
for spell, r in pairs(T) do if r.n == "Bright Yellow Shirt" then bys = spell end end
local bysItem = T[bys].pat[1]
check(D.patternVendors[bysItem] and D.patternVendors[bysItem][1] == "A", "Bright Yellow Shirt pattern: Alliance vendors only")
local function bysPrice(id)
  if anyPattern[id] and id ~= bysItem then return nil end
  if id == bysItem then return nil end -- not on the AH: only a vendor could sell it
  local r = T[bys]; for i = 1, #r.r, 2 do if id == r.r[i] then return 1, false end end
  return price(id)
end
local function factionPlan(f) return P.Plan(ctxFor(110, 150, nil, { price = bysPrice, faction = f,
  patternVendors = D.patternVendors, vendorSeen = function() return false end })) end
local horde, alliance = factionPlan("H"), factionPlan("A")
check(not horde.unlocks["p:" .. bys], "Horde: Bright Yellow Shirt pattern never bought from a vendor")
check(alliance.unlocks["p:" .. bys] and alliance.unlocks["p:" .. bys].vendorNames == "Danielle Zipstitch",
  "Alliance: bought from Danielle Zipstitch")
-- a Horde-visited vendor that sells it overrides the vendor lists
local seenPlan = P.Plan(ctxFor(110, 150, nil, { price = bysPrice, faction = "H",
  patternVendors = D.patternVendors, vendorSeen = function(it) return it == bysItem end }))
check(seenPlan.unlocks["p:" .. bys], "a vendor you visited counts, whatever the lists say")

-- 10h. stale AH sightings and skipped recipes
check(seen.unlocks["p:" .. dropPat], "(baseline) drop pattern bought on its AH price")
local stale = P.Plan({ recipes = T, items = items, tools = D.tools, hasTool = function() return true end,
  skill = 250, target = 280, known = {}, trainer = {}, price = function(id) return only(id, false) end,
  ahFresh = function() return false end })
check(not stale.unlocks["p:" .. dropPat], "a pattern not seen on the AH recently is not bought there")
local skipped = P.Plan({ recipes = T, items = items, tools = D.tools, hasTool = function() return true end,
  skill = 250, target = 280, known = {}, trainer = {}, price = function(id) return only(id, false) end,
  skip = { [dropPat] = true } })
for _, st in ipairs(skipped.steps) do check(st.spell ~= dropPat, "skipped recipe not planned") end

-- 10i. safety margin: orange-only steps need no extra; yellow/green steps do
local noMargin = P.Plan(ctxFor(110, 160))
local withMargin = P.Plan(ctxFor(110, 160, nil, { z = 1.2816 }))
local extra, anyOver = 0, false
for _, b in ipairs(withMargin.shopping.buy) do
  check(b.need >= b.expected, b.name .. ": margin never lowers the amount")
  if b.need > b.expected then anyOver = true; extra = extra + b.need - b.expected end
end
check(anyOver, "yellow/green steps get a margin")
check(withMargin.total >= noMargin.total, "margin costs more, never less")
for _, st in ipairs(withMargin.steps) do
  if st.spell and st.color == "orange" and st.to <= T[st.spell].y then check(st.var == 0, st.name .. ": orange step has no variance") end
end
-- a route that is all orange (only White Woolen Dress allowed, 85-100) gets no margin
local wwd
for sp, r in pairs(T) do if r.n == "White Woolen Dress" then wwd = sp end end
local skipAll = {}
for sp in pairs(T) do if sp ~= wwd then skipAll[sp] = true end end
local orangeOnly = P.Plan(ctxFor(85, 100, nil, { z = 1.2816, skip = skipAll, noPatterns = true }))
check(#orangeOnly.steps >= 1 and orangeOnly.steps[1].spell == wwd, "only White Woolen Dress planned")
for _, b in ipairs(orangeOnly.shopping.buy) do check(b.need == b.expected, "orange-only: no margin for " .. b.name) end
print(("margin 90%%: %d extra items, %.0fc -> %.0fc"):format(extra, noMargin.total, withMargin.total))

-- 10j. time per craft: fewer crafts when it's worth it; never changes the shopping total rule
local cheap0 = P.Plan(ctxFor(110, 200))
local timed = P.Plan(ctxFor(110, 200, nil, { craftValue = 5000 }))
local function crafts(pl) local n = 0 for _, st in ipairs(pl.steps) do if st.spell then n = n + st.crafts end end return n end
check(crafts(timed) <= crafts(cheap0) + 1e-6, "valuing time never means more crafts")
print(("craftcost 50s: %.0f -> %.0f crafts, %.0fc -> %.0fc"):format(crafts(cheap0), crafts(timed), cheap0.total, timed.total))

-- 10k. trainer fees: counted once per learned recipe; a recipe isn't learned for a sliver
local feePlan = P.Plan(ctxFor(110, 200))
local noFee = P.Plan(ctxFor(110, 200, nil, { ignoreFees = true }))
check(feePlan.fees and feePlan.fees > 0, "fees reported")
local learned = 0
for _, st in ipairs(feePlan.steps) do if st.learn == "trainer" then learned = learned + 1 end end
local learnedNo = 0
for _, st in ipairs(noFee.steps) do if st.learn == "trainer" then learnedNo = learnedNo + 1 end end
check(learned <= learnedNo, "counting fees never learns more recipes")
print(("trainer fees 110-200: %d recipes learned (%d ignoring fees), fees %.0fc"):format(learned, learnedNo, feePlan.fees))

-- 10l. resale: never treated as profit; route cost only goes down or equal in the choice
local base = P.Plan(ctxFor(110, 200))
local sell = P.Plan(ctxFor(110, 200, nil, { resale = 0.5 }))
local back = 0
for _, st in ipairs(sell.steps) do
  if st.spell then
    check(st.perCraft >= 1, st.name .. ": resale never makes a craft profit in the choice")
    back = back + (st.resale or 0)
  end
end
check(back > 0, "resale reported")
check(sell.expected <= base.expected + 1e-6, "counting resale never makes the chosen route dearer")
print(("resale 50%%: route %.0fc -> %.0fc to buy, ~%.0fc back from sales"):format(base.total, sell.total, back))

-- 10m. gathering: Mining 1-300 goes Copper -> Tin -> Iron -> Mithril -> Thorium, no gaps
local mine = P.GatherPlan({ nodes = D.gather[186], skill = 1, target = 300 })
check(#mine.gaps == 0, "mining 1-300 without gaps")
local order = {}
for _, st in ipairs(mine.steps) do
  check(st.gather and st.crafts >= st.to - st.from, "gather step")
  if order[#order] ~= st.name then order[#order + 1] = st.name end
end
check(order[1] == "Copper Vein" and order[#order]:find("Thorium"), "starts on Copper, ends on Thorium")
for _, n in ipairs(order) do check(n ~= "Silver Vein" and n ~= "Gold Vein" and n ~= "Truesilver Deposit", "rare ore not a planned step: " .. n) end
print("mining route: " .. table.concat(order, " -> ") .. (" (~%d nodes)"):format(mine.gathers))
local herb = P.GatherPlan({ nodes = D.gather[182], skill = 1, target = 300 })
check(#herb.gaps == 0, "herbalism 1-300 without gaps")
local skin = P.GatherPlan({ skinning = true, skill = 120, target = 160 })
check(skin.steps[1].name == "level 21-24 beasts", "skinning at 120: level 24 beasts (" .. skin.steps[1].name .. ")")

-- 10n. fishing: catches follow the server rule, zones never lose fish
check(P.FishChance(50) == 1 and math.abs(P.FishChance(100) - 0.5) < 1e-9 and math.abs(P.FishChance(300) - 0.1) < 1e-9, "fish skill-up chance")
local fish = P.GatherPlan({ fishing = D.fishing, skill = 1, target = 300 })
local catches, prev = 0, 0
for _, st in ipairs(fish.steps) do
  catches = catches + st.crafts
  for k = 2, #st.zones, 2 do check(st.zones[k] + 95 <= st.from, "no fish lost in " .. st.zones[k - 1] .. " at " .. st.from) end
end
check(catches > 1000 and catches < 1600, ("1-300 catches plausible: %.0f"):format(catches))
print(("fishing 1-300: ~%.0f catches; at 225: %s"):format(catches, (function()
  for _, st in ipairs(fish.steps) do if st.from == 225 then local z = {} for k = 1, #st.zones, 2 do z[#z+1] = st.zones[k] end return table.concat(z, ", ") end end end)()))

-- 11. reputation patterns: only with the standing they need
local function repPlan(standing)
  return P.Plan({ recipes = T, items = items, tools = D.tools, hasTool = function() return false end,
    skill = 250, target = 300, known = {}, trainer = {}, price = price, standing = standing })
end
local function repUsed(pl)
  local used = {}
  for _, u in pairs(pl.unlocks) do
    if u.kind == "pattern" then
      local f, rank = P.RepNeed(T[u.spell], u.item)
      if f then used[#used + 1] = { f = f, rank = rank, total = pl.total } end
    end
  end
  return used
end
local none = repPlan(nil)
check(#repUsed(none) == 0, "no reputation known -> no reputation patterns")
local exalted = repPlan(function() return 7 end)
check(#repUsed(exalted) > 0, "exalted everywhere -> reputation patterns used")
check(exalted.total < none.total, "reputation patterns make the route cheaper")
-- Cenarion Circle Friendly only: Honored/Revered patterns stay out
local friendly = repPlan(function(f) return f == 609 and 4 or 3 end)
for _, u in ipairs(repUsed(friendly)) do
  check(u.f == 609 and u.rank <= 4, "pattern used without the reputation it needs")
end
print(("rep check 250->300: none %.0fg, Cenarion Friendly %.0fg, exalted everywhere %.0fg"):format(
  none.total / 1e4, friendly.total / 1e4, exalted.total / 1e4))

print("\n110->300 route (mock prices):")
for _, st in ipairs(sticky.steps) do
  if st.gap then print(("  %3d-%3d  GAP: needs a pattern"):format(st.from, st.to))
  else print(("  %3d-%3d  ~%4.1f x %-34s %-8s %s"):format(st.from, st.to, st.crafts, st.name, st.learn or "", st.color)) end
end
print(fails == 0 and "\nALL TESTS PASSED" or ("\n" .. fails .. " FAILURES"))
os.exit(fails == 0 and 0 or 1)
