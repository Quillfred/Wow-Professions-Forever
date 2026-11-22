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
    check(learnAt and learnAt <= st.from, st.name .. " used before it can be learned")
    check(st.to <= rr.g, st.name .. " used while grey")
    check(rr.src ~= "p" and rr.src ~= "x", st.name .. " is not obtainable without a pattern")
  end
end
check(s == 300, "plan reaches target")
print(("1->300 Tailoring plan: %d steps, %d gaps, %.1f ms"):format(#plan.steps, #plan.gaps, ms))

-- 3. optimality: with no stickiness, DP total == sum over points of the cheapest cost/chance
local ctx = ctxFor(110, 300, nil, { sticky = 0 })
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
        local it = rr.out and items[rr.out]
        if it then c = c - it[2] * (rr.outN or 1) end
        if c < 0 then c = 0 end
        if c / ch < m then m = c / ch end
      end
    end
  end
  if m < math.huge then brute = brute + m end
end
-- the planner may buy reagents cheaper by crafting them (bolts) -> can only be <= brute force
check(p0.expected <= brute + 1e-6, ("DP %.1f should be <= brute force %.1f"):format(p0.expected, brute))
local sticky = P.Plan(ctxFor(110, 300))
check(sticky.expected <= p0.expected * 1.03 + 1e-6, "stickiness costs at most 3%")
print(("110->300 expected cost: optimal %.0fc, with stickiness %.0fc (%d vs %d steps)"):format(p0.expected, sticky.expected, #p0.steps, #sticky.steps))

-- 4. a known pattern recipe becomes usable; an unknown one never is
local pat; for spell, rr in pairs(T) do if rr.src == "p" and rr.y >= 160 and rr.y < 200 then pat = spell break end end
local pk = P.Plan(ctxFor(150, 220, { [pat] = true }))
local usedUnknown = false
for _, st in ipairs(P.Plan(ctxFor(150, 220)).steps) do if st.spell == pat then usedUnknown = true end end
check(not usedUnknown, "unknown pattern never used")

-- 5. confirmed trainer level overrides the 'yellow' assumption
local ds = 3848 -- Double-stitched Woolen Shoulders (y=110)
local c5 = ctxFor(100, 110); c5.trainer = { [ds] = { req = 100, cost = 500 } }
check(P.LearnAt(ds, T[ds], c5) == 100, "trainer req used")
check(P.LearnAt(ds, T[ds], ctxFor(100, 110)) == 110, "unconfirmed trainer recipe waits for yellow")

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
local p8 = P.Plan(ctxFor(250, 300))
check(#p8.gaps > 0, "no trainer recipes 250+ -> gap expected (Forever: patterns only)")
if p8.gaps[1] then check(#p8.gaps[1].patterns > 0, "gap has pattern suggestions") end

print("\n110->300 route (mock prices):")
for _, st in ipairs(sticky.steps) do
  if st.gap then print(("  %3d-%3d  GAP: needs a pattern"):format(st.from, st.to))
  else print(("  %3d-%3d  ~%4.1f x %-34s %-8s %s"):format(st.from, st.to, st.crafts, st.name, st.learn or "", st.color)) end
end
print(fails == 0 and "\nALL TESTS PASSED" or ("\n" .. fails .. " FAILURES"))
os.exit(fails == 0 and 0 or 1)
