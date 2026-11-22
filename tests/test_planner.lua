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
      check(rr.from and rr.from:find("Vendor") and P.RepOK({}, rr, st.unlock.item) and st.learnCost,
        st.name .. ": only vendor patterns whose reputation you have are bought")
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
  check(T[spell].from:find("Vendor") and P.RepOK({}, T[spell], b.item) and not T[spell].cd, T[spell].n .. " not a plain vendor pattern")
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
local function plan(line, from, to, priceFn, owned)
  return P.Plan({ recipes = D.professions[line].recipes, items = items, tools = D.tools,
    skill = from, target = to, known = {}, trainer = {}, price = priceFn or price,
    hasTool = function(k) return owned and owned[k] or false end })
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
