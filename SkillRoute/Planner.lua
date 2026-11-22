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
-- this plan. ctx.known: learned; ctx.trainer: seen in this client's trainer window
-- (wins over the data file); src "T": trainer recipe per Wowhead, with learn level.
function Planner.LearnAt(spell, r, ctx)
  if ctx.known[spell] or r.src == "a" then return 0, "known" end
  local t = ctx.trainer[spell]
  if t then return t.req or 0, "trainer" end
  if r.src == "T" then return r.learn or r.y, "trainer" end
  if r.src == "t" then return r.y, "trainer?" end -- unconfirmed: never earlier than yellow
  if ctx.buyable and ctx.buyable[spell] then return r.learn or r.y, "pattern" end
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

-- Cost of one craft = what you pay for its reagents. Vendor resale is NOT
-- subtracted: on Forever it often covers the mats, which made long grinds look
-- free. Only an intermediate the route consumes later (e.g. bolts of cloth) is
-- credited, at what it would otherwise cost, scaled by credit[item] (the share
-- of produced units the route really uses). Every craft costs at least PER_CRAFT
-- so that, all else equal, fewer crafts win.
local PER_CRAFT = 1 -- copper
local function craftCostFn(ctx, unit, credit)
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
    local share = r.out and credit[r.out]
    if share and share > 0 then
      local v = unit(r.out)
      if v then c = c - share * v * (r.outN or 1) end
    end
    if c < PER_CRAFT then c = PER_CRAFT end
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
local CAP_STEP = 75 -- Apprentice/Journeyman/Expert/Artisan caps: 75, 150, 225

function Planner.Plan(ctx)
  -- Intermediates: items some obtainable recipe of this profession uses as reagent.
  local credit = {}
  if ctx.noCredit then return Planner.PlanOnce(ctx, credit) end -- tests
  for spell, r in pairs(ctx.recipes) do
    if Planner.LearnAt(spell, r, ctx) then
      for i = 1, #r.r, 2 do credit[r.r[i]] = 1 end
    end
  end
  -- Plan, then lower the credit of any intermediate the route over-produces, and
  -- plan again. Credits only go down, so this settles in a few passes.
  local plan
  for _ = 1, 4 do
    plan = Planner.PlanOnce(ctx, credit)
    local changed = false
    for item, made in pairs(plan.made) do
      local used = made - (plan.leftover[item] or 0)
      local share = made > 0 and used / made or 0
      if (credit[item] or 0) > share + 0.01 then credit[item] = share; changed = true end
    end
    if not changed then break end
  end
  if #plan.gaps > 0 and not ctx.noPatterns then plan = Planner.FillGaps(ctx, credit, plan) end
  return plan
end

-- Where no known or trainer recipe exists, allow buying vendor-sold patterns. The
-- pattern's price is a one-time cost, spread over the points it can cover inside
-- the gap. Patterns are only allowed inside gaps, never to replace a trainer recipe.
function Planner.FillGaps(ctx, credit, plan)
  local inGap = {}
  for _, g in ipairs(plan.gaps) do for s = g.from, g.to - 1 do inGap[s] = true end end
  local buyable = {}
  for spell, r in pairs(ctx.recipes) do
    if r.pat and not ctx.known[spell] and not r.rep and not r.cd and r.from and r.from:find("Vendor") then
      local best
      for _, it in ipairs(r.pat) do
        local v = ctx.items[it] and ctx.items[it][3]
        local ah = ctx.price(it)
        local p = (v and ah) and math.min(v, ah) or v or ah
        if p and (not best or p < best) then best = p end
      end
      if best then
        local span = 0
        for s = (r.learn or r.y), r.g - 1 do if inGap[s] then span = span + 1 end end
        if span > 0 then buyable[spell] = { price = best, perPoint = best / span } end
      end
    end
  end
  if next(buyable) == nil then return plan end
  local ctx2 = setmetatable({ buyable = buyable, onlyGaps = inGap }, { __index = ctx })
  local filled = Planner.PlanOnce(ctx2, credit)
  filled.patternsBought = buyable
  return filled
end

function Planner.PlanOnce(ctx, credit)
  local recipes, from, to = ctx.recipes, ctx.skill, ctx.target
  local unit = makePricer(ctx)
  local costOf = craftCostFn(ctx, unit, credit)

  -- Candidates: obtainable recipes that are not grey at our current skill.
  local cands, unpriced = {}, 0
  for spell, r in pairs(recipes) do
    local learnAt, how = Planner.LearnAt(spell, r, ctx)
    if learnAt and r.g > from and learnAt < to and not r.cd then -- cooldown recipes can't be ground
      local c, est = costOf(spell)
      if c then
        cands[#cands + 1] = { spell = spell, r = r, learnAt = learnAt, how = how, cost = c, est = est,
                              buy = how == "pattern" and ctx.buyable[spell] or nil }
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
      if c.learnAt <= s and (not c.buy or ctx.onlyGaps[s]) then
        local p = Planner.Chance(c.r, s, ctx.bonus)
        if p > 0 then
          local v = c.cost / p + (c.buy and c.buy.perPoint or 0)
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
      repeat -- stop at rank caps so "train the next rank" falls between steps
        crafts = crafts + 1 / Planner.Chance(c.r, e, ctx.bonus)
        e = e + 1
      until e >= to or pick[e] ~= k or e % CAP_STEP == 0
      local a = alt[s]
      steps[#steps + 1] = {
        spell = c.spell, name = c.r.n, from = s, to = e, crafts = crafts,
        cost = c.cost * crafts, perCraft = c.cost, est = c.est,
        learn = (c.how ~= "known") and c.how or nil,
        learnCost = (c.buy and c.buy.price) or (ctx.trainer[c.spell] and ctx.trainer[c.spell].cost) or c.r.tc,
        color = Planner.Color(c.r, s),
        vendorBack = c.r.out and ctx.items[c.r.out] and ctx.items[c.r.out][2] * (c.r.outN or 1) * crafts or 0,
        credited = c.r.out and (credit[c.r.out] or 0) > 0 or false,
        alt = a and { name = cands[a.k].r.n, perPoint = a.c, ours = c.cost / Planner.Chance(c.r, s, ctx.bonus) },
      }
      s = e
    end
  end

  local shopping, total, anyEst, made, leftover = Planner.Shopping(ctx, steps, unit)
  return { steps = steps, gaps = gaps, shopping = shopping, total = total, estimated = anyEst,
           expected = best[from], unpriced = unpriced, made = made, leftover = leftover }
end

-- Patterns that would cover a gap at skill s (not known yet), cheapest first.
function Planner.PatternsFor(ctx, s, unit)
  local list = {}
  for spell, r in pairs(ctx.recipes) do
    if r.pat and not ctx.known[spell] and not r.cd and (r.learn or r.y) <= s and s < r.g then
      local bestP, bestItem
      for _, it in ipairs(r.pat) do
        local p = ctx.price(it)
        if p and (not bestP or p < bestP) then bestP, bestItem = p, it end
      end
      list[#list + 1] = { spell = spell, name = r.n, item = bestItem or r.pat[1], price = bestP, to = r.g,
                          from = r.from, rep = r.rep }
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
  local need, pool, crafts, made = {}, {}, {}, {}
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
      if r.out then
        local n = st.crafts * (r.outN or 1)
        pool[r.out] = (pool[r.out] or 0) + n
        made[r.out] = (made[r.out] or 0) + n
      end
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
  return { buy = list, craft = craftList }, total, anyEst, made, pool
end

return Planner
