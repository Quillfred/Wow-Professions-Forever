-- Route planner. Pure logic: no WoW API calls, so it can be tested outside the game
-- (tests/test_planner.lua). Core.lua supplies prices, known recipes and trainer data.
local ns = select(2, ...) or SkillRouteTestNS
local Planner = {}
ns.Planner = Planner

local floor, ceil, huge = math.floor, math.ceil, math.huge

-- How close (fraction) another recipe must be before we keep using the same recipe
-- instead of switching. Avoids routes that flip A,B,A,B over near-equal costs.
local STICKY_DEFAULT = 0.03
local CAP_STEP = 75   -- Apprentice/Journeyman/Expert/Artisan caps: 75, 150, 225
local PER_CRAFT = 1   -- copper; all else equal, fewer crafts win
local GAP_COST = 1e9  -- per skill point with no usable recipe: filling a gap always wins

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
-- (wins over the data file); src "T": trainer recipe per Wowhead, with learn level;
-- a vendor pattern this plan buys (ctx.unlocked["p:<spell>"]).
function Planner.LearnAt(spell, r, ctx)
  if ctx.known[spell] or r.src == "a" then return 0, "known" end
  local t = ctx.trainer[spell]
  if t then return t.req or 0, "trainer" end
  if r.src == "T" then return r.learn or r.y, "trainer" end
  if r.src == "t" then return r.y, "trainer?" end -- unconfirmed: never earlier than yellow
  if ctx.unlocked and ctx.unlocked["p:" .. spell] then return r.learn or r.y, "pattern" end
  return nil
end

-- Reputation: r.rep = {patternItem, factionID, rank, ...} for pattern items that
-- need it (rank 0-7: 4 Friendly, 5 Honored, 6 Revered, 7 Exalted).
-- ctx.standing(factionID) -> your rank 0-7, or nil if unknown.
function Planner.RepNeed(r, item)
  local rep = r.rep
  if not rep then return nil end
  for i = 1, #rep, 3 do
    if rep[i] == item then return rep[i + 1], rep[i + 2] end
  end
end

function Planner.RepOK(ctx, r, item)
  local faction, rank = Planner.RepNeed(r, item)
  if not faction then return true end
  local mine = ctx.standing and ctx.standing(faction)
  return mine ~= nil and mine >= rank, faction, rank
end

local function hasTool(ctx, key)
  if not ctx.tools then return true end -- no tool data: don't block anything
  return ctx.hasTool and ctx.hasTool(key) or false
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

-- Reagent cost of one craft, or nil if a reagent has no price.
local function reagentCost(r, unit)
  local c, est = 0, false
  for i = 1, #r.r, 2 do
    local p, e = unit(r.r[i])
    if not p then return nil end
    c = c + p * r.r[i + 1]
    est = est or e
  end
  return c, est
end

-- Cost of one craft = what you pay for its reagents. Vendor resale is NOT
-- subtracted: on Forever it often covers the mats, which made long grinds look
-- free. Only an intermediate the route consumes later (e.g. bolts of cloth) is
-- credited, at what it would otherwise cost, scaled by credit[item] (the share
-- of produced units the route really uses).
local function craftCostFn(ctx, unit, credit)
  local memo = {}
  return function(spell)
    local m = memo[spell]
    if m then return m.c, m.est end
    local r = ctx.recipes[spell]
    local c, est = reagentCost(r, unit)
    if not c then memo[spell] = {}; return nil end
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

--[[ One-time unlocks: things bought once that make recipes usable.
  "p:<spell>"  a vendor pattern, no cooldown, reputation requirement met
  "t:<tool>"   a tool you keep in your bags (rod, hammer, spanner); bought, or
               crafted once by this profession from the skill its recipe allows ]]
local function findUnlocks(ctx, unit)
  local all = {}
  if not ctx.noPatterns then
    for spell, r in pairs(ctx.recipes) do
      -- Vendor patterns at their vendor price, and any pattern (drops too) that
      -- Auctionator has seen on the auction house. Never on an estimated price:
      -- untradeable patterns have no AH price, so they never show up here.
      if r.pat and not ctx.known[spell] and not r.cd then
        local isVendor = r.from and r.from:find("Vendor")
        local best, bestItem, bestVia, bestInfo
        for _, it in ipairs(r.pat) do
          if Planner.RepOK(ctx, r, it) then
            -- Can a vendor of YOUR faction sell it? A vendor you visited: yes. Else the
            -- vendor lists (Classic data): only if one serves your faction. Not listed
            -- (new in Forever): allowed, flagged unverified.
            local pv = ctx.patternVendors and ctx.patternVendors[it]
            local vendorOK, info = isVendor, nil
            if isVendor and not (ctx.vendorSeen and ctx.vendorSeen(it)) and ctx.faction then
              if pv then
                vendorOK = pv[1]:find(ctx.faction, 1, true) ~= nil
                info = { names = ctx.faction == "A" and pv[2] or pv[3] }
              else
                info = { unverified = true }
              end
            end
            local v = vendorOK and ctx.items[it] and ctx.items[it][3] or nil
            local ah, est = ctx.price(it)
            -- a one-off listing: only trust a recent sighting (ctx.ahFresh), not an old price
            if ah and ctx.ahFresh and not ctx.ahFresh(it) then ah = nil end
            if est or ah == v then ah = nil end -- estimate, or just the vendor price echoed back
            local p, via
            if v and (not ah or v <= ah) then p, via = v, "vendor" elseif ah then p, via = ah, "ah" end
            if p and (not best or p < best) then
              best, bestItem, bestVia, bestInfo = p, it, via, via == "vendor" and info or nil
            end
          end
        end
        if best then
          all["p:" .. spell] = { kind = "pattern", spell = spell, price = best, item = bestItem, from = 0,
                                 name = r.n, via = bestVia,
                                 vendorNames = bestInfo and bestInfo.names ~= "" and bestInfo.names or nil,
                                 unverified = bestInfo and bestInfo.unverified or nil }
        end
      end
    end
  end
  if ctx.tools then
    local needed = {}
    for _, r in pairs(ctx.recipes) do
      for _, t in ipairs(r.tool or {}) do needed[t] = true end
    end
    for t in pairs(needed) do
      local def = ctx.tools[t]
      if def and not hasTool(ctx, t) then
        local opt
        for _, it in ipairs(def[2]) do -- buy (vendor or AH)
          local p = ctx.price(it)
          if p and (not opt or p < opt.price) then opt = { price = p, item = it, from = 0 } end
        end
        local isTool = {}
        for _, it in ipairs(def[2]) do isTool[it] = true end
        for spell, r in pairs(ctx.recipes) do -- or craft it with this profession
          if r.out and isTool[r.out] and not r.cd then
            local learnAt, how = Planner.LearnAt(spell, r, { known = ctx.known, trainer = ctx.trainer })
            local ok = learnAt ~= nil
            for _, t2 in ipairs(r.tool or {}) do ok = ok and hasTool(ctx, t2) end
            local c = ok and reagentCost(r, unit)
            if c and (not opt or c < opt.price) then
              opt = { price = c, item = r.out, from = learnAt, craftSpell = spell,
                      learnHow = how ~= "known" and how or nil,
                      learnCost = (ctx.trainer[spell] and ctx.trainer[spell].cost) or r.tc }
            end
          end
        end
        if opt then
          opt.kind, opt.tool, opt.name = "tool", t, def[1]
          all["t:" .. t] = opt
        end
      end
    end
  end
  return all
end

-- Can this recipe be used under ctx.unlocked? Returns learnAt, how, missingKey:
-- missingKey = the unlock(s) still to buy, joined with "+" (e.g. a formula AND the
-- rod it needs: "p:20015+t:377"); nil = usable now. Returns nil if a requirement
-- can't be obtained at all.
local function requirements(spell, r, ctx, all)
  local learnAt, how = Planner.LearnAt(spell, r, ctx)
  local missing
  if not learnAt then
    local key = "p:" .. spell
    if not all[key] then return nil end
    learnAt, how, missing = r.learn or r.y, "pattern", { key }
  end
  for _, t in ipairs(r.tool or {}) do
    if not hasTool(ctx, t) then
      local key = "t:" .. t
      local u = ctx.unlocked[key] or all[key]
      if not u then return nil end
      if u.from > learnAt then learnAt = u.from end
      if not ctx.unlocked[key] then
        missing = missing or {}
        missing[#missing + 1] = key
      end
    end
  end
  if missing then
    table.sort(missing)
    missing = table.concat(missing, "+")
  end
  return learnAt, how, missing
end

-- Parts and total price of a (possibly combined) unlock key.
local function keyParts(key)
  local parts = {}
  for part in key:gmatch("[^+]+") do parts[#parts + 1] = part end
  return parts
end
local function keyPrice(all, key)
  local p = 0
  for _, part in ipairs(keyParts(key)) do p = p + all[part].price end
  return p
end

local function copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end

-- Plan, then lower the credit of any intermediate the route over-produces, and
-- plan again. Credits only go down, so this settles in a few passes.
local function creditPlan(ctx, credit)
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
  return plan
end

local function routeTotal(plan, chosen)
  local t = plan.expected + plan.gapPoints * GAP_COST
  for _, u in pairs(chosen) do t = t + u.price end
  return t
end

--[[ ctx = {
  recipes, items, tools -- from Data.lua (tools optional)
  skill, target         -- current skill, wanted skill
  known   = {[spell]=true}
  trainer = {[spell]={req=, cost=}}
  price   = function(itemID) -> copper|nil, isEstimate
  have    = function(itemID) -> count       (optional)
  haveAlts = function(itemID) -> count on your other characters (optional)
  hasTool = function(toolKey) -> bool       (optional)
  craftValue = copper per craft for your time (optional; affects the choice, not the total)
  z = safety margin in standard deviations for the shopping list (optional, 0 = expected)
  avoidMats = {[itemID]=true}               (optional; recipes using these are left out)
  skip = {[spell]=true}                     (optional; recipes you marked unavailable)
  ahFresh = function(item) -> bool          (optional; pattern seen on the AH recently?)
  faction = "A" | "H", patternVendors = Data.patternVendors, vendorSeen = function(item) -> bool
                                            (optional; vendor patterns only from your faction's vendors)
  maxSkill = current cap (e.g. 225)         (optional; steps split only at caps not yet trained)
  bonus   = 0..1                            (optional)
  fixedUnlocks = {[key]=true}  reuse an earlier choice instead of searching
} ]]
function Planner.Plan(ctx)
  local all = findUnlocks(ctx, makePricer(ctx))
  local credit = {}
  if ctx.noCredit then -- tests
    return Planner.PlanOnce(setmetatable({ unlocked = {}, all = all }, { __index = ctx }), credit)
  end
  -- Intermediates: items some usable or unlockable recipe uses as reagent.
  for spell, r in pairs(ctx.recipes) do
    if all["p:" .. spell] or Planner.LearnAt(spell, r, ctx) then
      for i = 1, #r.r, 2 do credit[r.r[i]] = 1 end
    end
  end
  -- Trainer fees of recipes you don't know yet are one-time costs. Spread each fee
  -- over the points the recipe can cover (first guess), then over the points the route
  -- really uses it for, re-planning twice: a 40s recipe isn't learned for 1 point.
  local surcharge, fees = {}, {}
  if not ctx.ignoreFees then
    for spell, r in pairs(ctx.recipes) do
      local learnAt, how = Planner.LearnAt(spell, r, ctx)
      local fee = (ctx.trainer[spell] and ctx.trainer[spell].cost) or r.tc
      if learnAt and how ~= "known" and how ~= "pattern" and fee and fee > 0 then
        fees[spell] = fee
        local span = math.min(r.g, ctx.target) - math.max(learnAt, ctx.skill)
        if span > 0 then surcharge[spell] = fee / span end
      end
    end
  end
  local function run(set, cr)
    return creditPlan(setmetatable({ unlocked = set, all = all, surcharge = surcharge }, { __index = ctx }), cr)
  end

  local chosen, plan = {}, nil
  if ctx.fixedUnlocks then
    for key in pairs(ctx.fixedUnlocks) do chosen[key] = all[key] end
    plan = run(chosen, credit)
  else
    -- Greedy: try the unlock whose estimated saving minus price is largest; keep it
    -- only if a full re-plan confirms the total (unlock prices included) drops.
    plan = run(chosen, credit)
    local rejected, tries = {}, 0
    while tries < 16 do
      local bestKey, bestGain
      for key, sav in pairs(plan.savings) do
        local gain = sav - keyPrice(all, key)
        if gain > 0 and not chosen[key] and not rejected[key] and (not bestGain or gain > bestGain) then
          bestKey, bestGain = key, gain
        end
      end
      if not bestKey then break end
      tries = tries + 1
      local trial = copy(chosen)
      local parts = keyParts(bestKey)
      for _, part in ipairs(parts) do trial[part] = all[part] end
      local cr = copy(credit)
      local tp = run(trial, cr)
      local before, after = routeTotal(plan, chosen), routeTotal(tp, trial)
      if after < before - 1 then
        for _, part in ipairs(parts) do all[part].saves = before - after end
        chosen, plan, credit = trial, tp, cr
      else
        rejected[bestKey] = true
      end
    end
    -- Drop unlocks a later purchase made unnecessary.
    local pruned, dropped = {}, false
    for key, u in pairs(chosen) do
      if plan.usedUnlocks[key] then pruned[key] = u else dropped = true end
    end
    if dropped then chosen, plan = pruned, run(pruned, copy(credit)) end
    plan.unlockTries = tries
  end

  -- refine the fee spreading on the route actually chosen
  if next(fees) then
    for _ = 1, 2 do
      local points = {}
      for _, st in ipairs(plan.steps) do
        if st.spell and fees[st.spell] then points[st.spell] = (points[st.spell] or 0) + (st.to - st.from) end
      end
      local changed = false
      for spell, n in pairs(points) do
        local v = fees[spell] / n
        if math.abs((surcharge[spell] or 0) - v) > 0.5 then surcharge[spell] = v; changed = true end
      end
      if not changed then break end
      plan = run(chosen, copy(credit))
    end
  end
  plan.fees = 0
  local seen = {}
  for _, st in ipairs(plan.steps) do
    if st.spell and fees[st.spell] and not seen[st.spell] then
      seen[st.spell] = true
      plan.fees = plan.fees + fees[st.spell]
    end
  end

  -- Bought patterns and tools go on the shopping list and into the total; tools
  -- crafted by this profession are added to the crafts (Planner.Shopping).
  plan.unlocks = chosen
  for key, u in pairs(chosen) do
    if not u.craftSpell then
      local it = ctx.items[u.item]
      table.insert(plan.shopping.buy, 1, { item = u.item, name = it and it[1] or u.name, need = 1, expected = 1, have = 0,
        buy = 1, price = u.price, vendor = u.via ~= "ah" and it and it[3] ~= nil, pattern = u.kind == "pattern",
        ah = u.via == "ah",
        tool = u.kind == "tool" })
      plan.total = plan.total + u.price
    end
    if u.saves and u.saves < GAP_COST / 2 then u.savesShown = u.saves end
  end
  return plan
end

function Planner.PlanOnce(ctx, credit)
  local recipes, from, to, all = ctx.recipes, ctx.skill, ctx.target, ctx.all or {}
  local unit = makePricer(ctx)
  local costOf = craftCostFn(ctx, unit, credit)

  -- Candidates: usable recipes not grey at our skill. Probes: recipes one unlock
  -- away; never chosen here, we only measure what that unlock would save.
  local cands, probes, unpriced = {}, {}, 0
  local perCraft = ctx.craftValue or 0     -- your time per craft (copper), choice only
  local sur = ctx.surcharge or {}          -- trainer fee per point
  local avoid = ctx.avoidMats
  local function usesAvoided(r)
    if not avoid then return false end
    for i = 1, #r.r, 2 do if avoid[r.r[i]] then return true end end
    return false
  end
  for spell, r in pairs(recipes) do
    if r.g > from and not r.cd and not usesAvoided(r) and not (ctx.skip and ctx.skip[spell]) then
      -- cooldown recipes can't be ground; skipped = you marked it unavailable
      local learnAt, how, missing = requirements(spell, r, ctx, all)
      if learnAt and learnAt < to then
        local c, est = costOf(spell)
        if not c then
          if not missing then unpriced = unpriced + 1 end -- skipped, not guessed
        elseif missing then
          probes[#probes + 1] = { key = missing, r = r, learnAt = learnAt, cost = c, spell = spell }
        else
          cands[#cands + 1] = { spell = spell, r = r, learnAt = learnAt, how = how, cost = c, est = est }
        end
      end
    end
  end

  -- Backward DP over skill points: best[s] = expected cost from s to target.
  -- Each point is independent, so the cheapest expected cost per point is optimal.
  local best, pick, alt, savings = {}, {}, {}, {}
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
          local v = (c.cost + perCraft) / p + (sur[c.spell] or 0)
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
    -- What each unlock would save at this point (exact for this DP).
    if #probes > 0 then
      local cur, low = bestK and bestC or GAP_COST, {}
      for _, pr in ipairs(probes) do
        if pr.learnAt <= s then
          local p = Planner.Chance(pr.r, s, ctx.bonus)
          if p > 0 then
            local v = (pr.cost + perCraft) / p
            if v < cur and (not low[pr.key] or v < low[pr.key]) then low[pr.key] = v end
          end
        end
      end
      for key, v in pairs(low) do savings[key] = (savings[key] or 0) + cur - v end
    end
  end

  -- Group consecutive points into steps.
  local steps, gaps, gapPoints, usedUnlocks = {}, {}, 0, {}
  local s = from
  while s < to do
    local k = pick[s]
    if not k then
      local e = s
      while e < to and not pick[e] do e = e + 1 end
      gaps[#gaps + 1] = { from = s, to = e, patterns = Planner.PatternsFor(ctx, s) }
      gapPoints = gapPoints + (e - s)
      steps[#steps + 1] = { gap = true, from = s, to = e }
      s = e
    else
      local c = cands[k]
      local e, crafts, var = s, 0, 0
      repeat -- stop at rank caps still to train, so "train the next rank" falls between steps
        local p = Planner.Chance(c.r, e, ctx.bonus)
        crafts = crafts + 1 / p
        var = var + (1 - p) / (p * p) -- crafts for one point: geometric, variance (1-p)/p^2
        e = e + 1
      until e >= to or pick[e] ~= k or (e % CAP_STEP == 0 and e >= (ctx.maxSkill or 0))
      local a = alt[s]
      local pkey = "p:" .. c.spell
      if c.how == "pattern" then usedUnlocks[pkey] = true end
      local tools
      for _, t in ipairs(c.r.tool or {}) do
        local u = ctx.unlocked["t:" .. t]
        if u then
          usedUnlocks["t:" .. t] = true
          tools = tools or {}
          tools[#tools + 1] = u
        end
      end
      local learnCost
      if c.how == "pattern" then learnCost = ctx.unlocked[pkey].price
      else learnCost = (ctx.trainer[c.spell] and ctx.trainer[c.spell].cost) or c.r.tc end
      steps[#steps + 1] = {
        spell = c.spell, name = c.r.n, from = s, to = e, crafts = crafts, var = var,
        cost = c.cost * crafts, perCraft = c.cost, est = c.est,
        learn = (c.how ~= "known") and c.how or nil, learnCost = learnCost,
        unlock = c.how == "pattern" and ctx.unlocked[pkey] or nil, tools = tools,
        color = Planner.Color(c.r, s),
        vendorBack = c.r.out and ctx.items[c.r.out] and ctx.items[c.r.out][2] * (c.r.outN or 1) * crafts or 0,
        credited = c.r.out and (credit[c.r.out] or 0) > 0 or false,
        grossCost = (reagentCost(c.r, unit) or 0) * crafts, -- materials, before crediting
        alt = a and { name = cands[a.k].r.n, perPoint = a.c, ours = c.cost / Planner.Chance(c.r, s, ctx.bonus) },
      }
      s = e
    end
  end

  -- Tools crafted by this profession: one craft each, unless a step already makes one.
  local extra = {}
  for key in pairs(usedUnlocks) do
    local u = ctx.unlocked[key]
    if u and u.craftSpell then
      local madeBySteps = false
      for _, st in ipairs(steps) do if st.spell and recipes[st.spell].out == u.item then madeBySteps = true end end
      if not madeBySteps then extra[#extra + 1] = u.craftSpell end
    end
  end
  local shopping, total, anyEst, made, leftover = Planner.Shopping(ctx, steps, unit, extra)
  return { steps = steps, gaps = gaps, shopping = shopping, total = total, estimated = anyEst,
           expected = best[from], unpriced = unpriced, made = made, leftover = leftover,
           gapPoints = gapPoints, savings = savings, usedUnlocks = usedUnlocks }
end

-- Patterns that would cover a gap at skill s (not known yet), cheapest first.
function Planner.PatternsFor(ctx, s)
  local list = {}
  for spell, r in pairs(ctx.recipes) do
    if r.pat and not ctx.known[spell] and not r.cd and (r.learn or r.y) <= s and s < r.g then
      local bestP, bestItem
      for _, it in ipairs(r.pat) do
        local p = ctx.price(it)
        if p and (not bestP or p < bestP) then bestP, bestItem = p, it end
      end
      local item = bestItem or r.pat[1]
      local ok, faction, rank = Planner.RepOK(ctx, r, item)
      local pv = ctx.patternVendors and ctx.patternVendors[item]
      local otherSide = pv and ctx.faction and not pv[1]:find(ctx.faction, 1, true) and pv[1] or nil
      list[#list + 1] = { spell = spell, name = r.n, item = item, price = bestP, to = r.g,
                          from = r.from, where = r.where, repFaction = not ok and faction or nil, repRank = rank,
                          otherSide = otherSide }
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
-- extra = recipes crafted once up front (tools such as enchanting rods).
-- ctx.z: safety margin. Skill-ups are random, so the crafts a step takes vary (orange
-- steps don't); buying the expected amount runs short about half the time. Each
-- reagent's need is mean + z * standard deviation (z = 1.28: enough 9 times in 10).
function Planner.Shopping(ctx, steps, unit, extra)
  local need, needVar, pool, crafts, made = {}, {}, {}, {}, {}
  local function add(item, n, depth, v)
    local _, _, via = unit(item)
    if via and depth < 4 then
      local r = ctx.recipes[via]
      local out = r.outN or 1
      local times, tv = n / out, (v or 0) / (out * out)
      crafts[via] = (crafts[via] or 0) + times
      for i = 1, #r.r, 2 do add(r.r[i], r.r[i + 1] * times, depth + 1, r.r[i + 1] ^ 2 * tv) end
    else
      need[item] = (need[item] or 0) + n
      needVar[item] = (needVar[item] or 0) + (v or 0)
    end
  end
  local toolCraft = {}
  for _, spell in ipairs(extra or {}) do
    local r = ctx.recipes[spell]
    crafts[spell] = (crafts[spell] or 0) + 1
    toolCraft[spell] = true
    for i = 1, #r.r, 2 do add(r.r[i], r.r[i + 1], 0) end
  end
  for _, st in ipairs(steps) do
    if st.spell then
      local r = ctx.recipes[st.spell]
      for i = 1, #r.r, 2 do
        local item, n = r.r[i], r.r[i + 1] * st.crafts
        local fromPool = math.min(pool[item] or 0, n)
        pool[item] = (pool[item] or 0) - fromPool
        if n - fromPool > 0 then add(item, n - fromPool, 0, r.r[i + 1] ^ 2 * (st.var or 0)) end
      end
      if r.out then
        local n = st.crafts * (r.outN or 1)
        pool[r.out] = (pool[r.out] or 0) + n
        made[r.out] = (made[r.out] or 0) + n
      end
    end
  end
  local list, total, anyEst = {}, 0, false
  local z = ctx.z or 0
  for item, n in pairs(need) do
    local expected = ceil(n - 1e-9)
    local want = ceil(n + z * math.sqrt(needVar[item] or 0) - 1e-9)
    local have = ctx.have and ctx.have(item) or 0
    local alts = ctx.haveAlts and ctx.haveAlts(item) or 0
    local buy = want - have - alts
    if buy < 0 then buy = 0 end
    local p, est = ctx.price(item)
    if p then total = total + p * buy end
    anyEst = anyEst or (est and buy > 0) or false
    local it = ctx.items[item]
    list[#list + 1] = { item = item, name = it and it[1] or ("item " .. item), need = want, expected = expected,
                        have = have, alts = alts, buy = buy, price = p, est = est,
                        vendor = it and it[3] ~= nil }
  end
  table.sort(list, function(a, b)
    local ca, cb = (a.price or 0) * a.buy, (b.price or 0) * b.buy
    if ca ~= cb then return ca > cb end
    return a.name < b.name
  end)
  local craftList = {}
  for spell, n in pairs(crafts) do
    craftList[#craftList + 1] = { spell = spell, name = ctx.recipes[spell].n, n = ceil(n - 1e-9),
                                  tool = toolCraft[spell] or nil }
  end
  table.sort(craftList, function(a, b)
    if (a.tool or false) ~= (b.tool or false) then return a.tool or false end
    return a.name < b.name
  end)
  return { buy = list, craft = craftList }, total, anyEst, made, pool
end

return Planner
