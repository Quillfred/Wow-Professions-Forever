-- Route planner. Pure logic: no WoW API calls, so it can be tested outside the game
-- (tests/test_planner.lua). Core.lua supplies prices, known recipes and trainer data.
local ns = select(2, ...) or SkillRouteTestNS
local Planner = {}
ns.Planner = Planner

local floor, ceil, huge = math.floor, math.ceil, math.huge

-- How close (fraction) another recipe must be before we keep using the same recipe
-- instead of switching. Avoids routes that flip A,B,A,B over near-equal costs.
local STICKY_DEFAULT = 0.03

-- Classic skill-up chance: orange always, then falls linearly from yellow to grey.
-- bonus = extra chance on a failed roll (Forever's "Working Overtime" talent).
function Planner.Chance(r, s, bonus)
  if s >= r.g then return 0 end
  local p = 1
  if s >= r.y and r.g > r.y then p = (r.g - s) / (r.g - r.y) end
  return p + (1 - p) * (bonus or 0)
end

-- Colour of a recipe at skill s, using the same thresholds the game uses
-- (green starts halfway between yellow and grey).
function Planner.Color(r, s)
  if s >= r.g then return "grey" end
  if s < r.y then return "orange" end
  if s < floor((r.y + r.g) / 2) then return "yellow" end
  return "green"
end

-- Skill at which the recipe can first be used, or nil if not obtainable through
-- this plan. ctx.known: learned; ctx.trainer: confirmed at a trainer.
function Planner.LearnAt(spell, r, ctx)
  if ctx.known[spell] or r.src == "a" then return 0, "known" end
  local t = ctx.trainer[spell]
  if t then return t.req or 0, "trainer" end
  if r.src == "t" then return r.y, "trainer?" end -- unconfirmed: never earlier than yellow
  return nil
end

-- Unit prices. ctx.price(itemID) -> copper, estimated? (nil if unknown).
-- An item we can craft right now (e.g. bolts of cloth) costs min(buy, craft).
local function makePricer(ctx)
  local memo, busy = {}, {}
  local producers = {}
  for spell, r in pairs(ctx.recipes) do
    if r.out and (ctx.known[spell] or r.src == "a") then
      producers[r.out] = producers[r.out] or {}
      table.insert(producers[r.out], spell)
    end
  end
  local unit
  local function craftCost(spell)
    local r = ctx.recipes[spell]
    local total, est = 0, false
    for i = 1, #r.r, 2 do
      local p, e = unit(r.r[i])
      if not p then return nil end
      total = total + p * r.r[i + 1]
      est = est or e
    end
    return total / (r.outN or 1), est
  end
  unit = function(item)
    local m = memo[item]
    if m then return m.p, m.est, m.via end
    if busy[item] then return nil end -- recipe cycle
    busy[item] = true
    local p, est = ctx.price(item)
    local via
    for _, spell in ipairs(producers[item] or {}) do
      local c, e = craftCost(spell)
      if c and (not p or c < p) then p, est, via = c, e, spell end
    end
    busy[item] = nil
    memo[item] = { p = p, est = est, via = via }
    return p, est, via
  end
  return unit
end

-- Cost of one craft: reagents minus what the product sells to a vendor for
-- (the only resale value that is guaranteed).
local function craftCostFn(ctx, unit)
  local memo = {}
  return function(spell)
    local m = memo[spell]
    if m then return m.c, m.est end
    local r = ctx.recipes[spell]
    local c, est = 0, false
    for i = 1, #r.r, 2 do
      local p, e = unit(r.r[i])
      if not p then memo[spell] = {}; return nil end
      c = c + p * r.r[i + 1]
      est = est or e
    end
    local it = r.out and ctx.items[r.out]
    if it then c = c - (it[2] or 0) * (r.outN or 1) end
    if c < 0 then c = 0 end
    memo[spell] = { c = c, est = est }
    return c, est
  end
end

--[[ ctx = {
  recipes, items      -- from Data.lua
  skill, target       -- current skill, wanted skill
  known   = {[spell]=true}
  trainer = {[spell]={req=, cost=}}
  price   = function(itemID) -> copper|nil, isEstimate
  have    = function(itemID) -> count   (optional)
  bonus   = 0..1                          (optional)
} ]]
function Planner.Plan(ctx)
  local recipes, from, to = ctx.recipes, ctx.skill, ctx.target
  local unit = makePricer(ctx)
  local costOf = craftCostFn(ctx, unit)

  -- Candidates: obtainable recipes that are not grey at our current skill.
  local cands, unpriced = {}, 0
  for spell, r in pairs(recipes) do
    local learnAt, how = Planner.LearnAt(spell, r, ctx)
    if learnAt and r.g > from and learnAt < to then
      local c, est = costOf(spell)
      if c then
        cands[#cands + 1] = { spell = spell, r = r, learnAt = learnAt, how = how, cost = c, est = est }
      else
        unpriced = unpriced + 1 -- skipped, not guessed: a reagent has no price
      end
    end
  end

  -- Backward DP over skill points: best[s] = expected cost from s to target.
  -- Each point is independent, so the cheapest expected cost per point is optimal.
  local best, pick, alt = {}, {}, {}
  best[to] = 0
  for s = to - 1, from, -1 do
    local bestC, bestK, secondC, secondK = huge, nil, huge, nil
    local nextK = pick[s + 1]
    local stickyC
    for k = 1, #cands do
      local c = cands[k]
      if c.learnAt <= s then
        local p = Planner.Chance(c.r, s, ctx.bonus)
        if p > 0 then
          local v = c.cost / p
          if k == nextK then stickyC = v end
          if v < bestC then
            secondC, secondK = bestC, bestK
            bestC, bestK = v, k
          elseif v < secondC then
            secondC, secondK = v, k
          end
        end
      end
    end
    if stickyC and bestK ~= nextK and stickyC <= bestC * (1 + (ctx.sticky or STICKY_DEFAULT)) then
      secondC, secondK = bestC, bestK
      bestC, bestK = stickyC, nextK
    end
    if bestK then
      pick[s], best[s] = bestK, bestC + best[s + 1]
      alt[s] = secondK and { k = secondK, c = secondC } or nil
    else
      best[s] = best[s + 1] -- gap: no usable recipe at this skill
    end
  end

  -- Group consecutive points into steps.
  local steps, gaps = {}, {}
  local s = from
  while s < to do
    local k = pick[s]
    if not k then
      local e = s
      while e < to and not pick[e] do e = e + 1 end
      gaps[#gaps + 1] = { from = s, to = e, patterns = Planner.PatternsFor(ctx, s, unit) }
      steps[#steps + 1] = { gap = true, from = s, to = e }
      s = e
    else
      local c = cands[k]
      local e, crafts = s, 0
      while e < to and pick[e] == k do
        crafts = crafts + 1 / Planner.Chance(c.r, e, ctx.bonus)
        e = e + 1
      end
      local a = alt[s]
      steps[#steps + 1] = {
        spell = c.spell, name = c.r.n, from = s, to = e, crafts = crafts,
        cost = c.cost * crafts, perCraft = c.cost, est = c.est,
        learn = (c.how ~= "known") and c.how or nil,
        learnCost = ctx.trainer[c.spell] and ctx.trainer[c.spell].cost,
        color = Planner.Color(c.r, s),
        alt = a and { name = cands[a.k].r.n, perPoint = a.c, ours = c.cost / Planner.Chance(c.r, s, ctx.bonus) },
      }
      s = e
    end
  end

  local shopping, total, anyEst = Planner.Shopping(ctx, steps, unit)
  return { steps = steps, gaps = gaps, shopping = shopping, total = total, estimated = anyEst,
           expected = best[from], unpriced = unpriced }
end

-- Patterns that would cover a gap at skill s (not known yet), cheapest first.
function Planner.PatternsFor(ctx, s, unit)
  local list = {}
  for spell, r in pairs(ctx.recipes) do
    if r.pat and not ctx.known[spell] and (r.learn or r.y) <= s and s < r.g then
      local bestP, bestItem
      for _, it in ipairs(r.pat) do
        local p = ctx.price(it)
        if p and (not bestP or p < bestP) then bestP, bestItem = p, it end
      end
      list[#list + 1] = { spell = spell, name = r.n, item = bestItem or r.pat[1], price = bestP, to = r.g }
    end
  end
  table.sort(list, function(a, b)
    if (a.price ~= nil) ~= (b.price ~= nil) then return a.price ~= nil end
    if a.price and a.price ~= b.price then return a.price < b.price end
    return a.to > b.to
  end)
  return list
end

-- What to buy. Expected reagent use per step; intermediates we craft cheaper than
-- buying (bolts) are expanded into their reagents; products of earlier steps
-- cover later needs; then what you own is subtracted. Rounded up once, at the end.
function Planner.Shopping(ctx, steps, unit)
  local need, pool, crafts = {}, {}, {}
  local function add(item, n, depth)
    local _, _, via = unit(item)
    if via and depth < 4 then
      local r = ctx.recipes[via]
      local times = n / (r.outN or 1)
      crafts[via] = (crafts[via] or 0) + times
      for i = 1, #r.r, 2 do add(r.r[i], r.r[i + 1] * times, depth + 1) end
    else
      need[item] = (need[item] or 0) + n
    end
  end
  for _, st in ipairs(steps) do
    if st.spell then
      local r = ctx.recipes[st.spell]
      for i = 1, #r.r, 2 do
        local item, n = r.r[i], r.r[i + 1] * st.crafts
        local fromPool = math.min(pool[item] or 0, n)
        pool[item] = (pool[item] or 0) - fromPool
        if n - fromPool > 0 then add(item, n - fromPool, 0) end
      end
      if r.out then pool[r.out] = (pool[r.out] or 0) + st.crafts * (r.outN or 1) end
    end
  end
  local list, total, anyEst = {}, 0, false
  for item, n in pairs(need) do
    local want = ceil(n - 1e-9)
    local have = ctx.have and ctx.have(item) or 0
    local buy = want - have
    if buy < 0 then buy = 0 end
    local p, est = ctx.price(item)
    if p then total = total + p * buy end
    anyEst = anyEst or (est and buy > 0) or false
    local it = ctx.items[item]
    list[#list + 1] = { item = item, name = it and it[1] or ("item " .. item), need = want,
                        have = have, buy = buy, price = p, est = est,
                        vendor = it and it[3] ~= nil }
  end
  table.sort(list, function(a, b)
    local ca, cb = (a.price or 0) * a.buy, (b.price or 0) * b.buy
    if ca ~= cb then return ca > cb end
    return a.name < b.name
  end)
  local craftList = {}
  for spell, n in pairs(crafts) do
    craftList[#craftList + 1] = { spell = spell, name = ctx.recipes[spell].n, n = ceil(n - 1e-9) }
  end
  table.sort(craftList, function(a, b) return a.name < b.name end)
  return { buy = list, craft = craftList }, total, anyEst
end

return Planner
