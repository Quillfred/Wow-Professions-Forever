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
      check(rr.from and rr.from:find("Vendor") and not rr.rep and st.learnCost, st.name .. ": only plain vendor patterns are bought")
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
  for _, b in pairs(plan.patterns or {}) do t = t + b.price end
  return t
end
local base = P.Plan(ctxFor(110, 250, nil, { noPatterns = true }))
check(#base.gaps == 0, "110-250 has trainer recipes everywhere")
local t0p = os.clock()
local withP = P.Plan(ctxFor(110, 250))
local searchMs = (os.clock() - t0p) * 1000
local bought = 0
for spell, b in pairs(withP.patterns) do
  bought = bought + 1
  -- leave this one pattern out: the route must get more expensive
  local fixed = {}
  for sp in pairs(withP.patterns) do if sp ~= spell then fixed[sp] = true end end
  local without = P.Plan(ctxFor(110, 250, nil, { fixedPatterns = fixed }))
  check(total(without) > total(withP), T[spell].n .. " pattern doesn't pay for itself")
  local onList = false
  for _, it in ipairs(withP.shopping.buy) do if it.pattern and it.item == b.item then onList = true end end
  check(onList, T[spell].n .. " pattern missing from shopping list")
  check(T[spell].from:find("Vendor") and not T[spell].rep and not T[spell].cd, T[spell].n .. " not a plain vendor pattern")
end
check(total(withP) <= total(base) + 1e-6, "patterns never make the route dearer")
print(("110->250: %d patterns bought, %.0fc -> %.0fc (%.1f%% cheaper), search %.0f ms"):format(
  bought, total(base), total(withP), 100 * (1 - total(withP) / total(base)), searchMs))
-- reusing the choice (bag change) skips the search
local fixedAll = {}
for sp in pairs(withP.patterns) do fixedAll[sp] = true end
local t1 = os.clock()
local again = P.Plan(ctxFor(110, 250, nil, { fixedPatterns = fixedAll }))
check(math.abs(total(again) - total(withP)) < 1, "fixed pattern choice reproduces the plan")
print(("re-plan with cached pattern choice: %.1f ms"):format((os.clock() - t1) * 1000))

print("\n110->300 route (mock prices):")
for _, st in ipairs(sticky.steps) do
  if st.gap then print(("  %3d-%3d  GAP: needs a pattern"):format(st.from, st.to))
  else print(("  %3d-%3d  ~%4.1f x %-34s %-8s %s"):format(st.from, st.to, st.crafts, st.name, st.learn or "", st.color)) end
end
print(fails == 0 and "\nALL TESTS PASSED" or ("\n" .. fails .. " FAILURES"))
os.exit(fails == 0 and 0 or 1)
