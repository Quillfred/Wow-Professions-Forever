-- Game-side glue: reads skills, known recipes, trainer data, prices and bags, and
-- feeds them to the planner. Every client API is checked before use, because
-- WoW Forever mixes the classic-era and the modern (C_TradeSkillUI) API.
local addonName, ns = ...
local Core = {}
ns.Core = Core

local Data, Planner = SkillRouteData, ns.Planner
local CALLER = addonName

-- Saved data -----------------------------------------------------------------
-- SkillRouteDB.trainer is account-wide (trainers teach the same to everyone).
-- SkillRouteDB.chars[char] holds what this character knows.
local function db()
  SkillRouteDB = SkillRouteDB or {}
  local d = SkillRouteDB
  d.trainer = d.trainer or {}
  d.chars = d.chars or {}
  d.settings = d.settings or { bonus = 0 }
  return d
end

local function charKey()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end

function Core.Char()
  local d = db()
  local k = charKey()
  d.chars[k] = d.chars[k] or { known = {}, targets = {} }
  return d.chars[k]
end

-- Professions ------------------------------------------------------------------
local nameToLine = {}
for line, p in pairs(Data.professions) do nameToLine[p.name] = line end

-- Returns {[skillLine] = {rank=, max=}} for the crafting professions this character has.
function Core.Skills()
  local out = {}
  if GetProfessions and GetProfessionInfo then
    for _, idx in pairs({ GetProfessions() }) do
      if idx then
        local name, _, rank, max, _, _, line = GetProfessionInfo(idx)
        line = (line and Data.professions[line]) and line or nameToLine[name]
        if line then out[line] = { rank = rank, max = max } end
      end
    end
  end
  if next(out) == nil and GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, header, _, rank, _, _, max = GetSkillLineInfo(i)
      local line = not header and nameToLine[name]
      if line then out[line] = { rank = rank, max = max } end
    end
  end
  return out
end

-- Recipe window scan -------------------------------------------------------------
-- Records learned recipes, and counts recipes whose live colour disagrees with our
-- data (that would mean Data.lua is stale for this client build).
Core.mismatch = {}

local DIFF = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "grey",
               optimal = "orange", medium = "yellow", easy = "green", trivial = "grey" }

local function openLine()
  local T = C_TradeSkillUI
  if not T then return end
  if T.GetBaseProfessionInfo then
    local info = T.GetBaseProfessionInfo()
    if info and info.professionID and Data.professions[info.professionID] then
      return info.professionID, info.skillLevel, info.maxSkillLevel
    end
    if info and info.professionName and nameToLine[info.professionName] then
      return nameToLine[info.professionName], info.skillLevel, info.maxSkillLevel
    end
  end
  if T.GetTradeSkillLine then
    local line, name, rank, max = T.GetTradeSkillLine()
    line = (line and Data.professions[line]) and line or nameToLine[name]
    if line then return line, rank, max end
  end
end

function Core.ScanRecipes()
  local T = C_TradeSkillUI
  if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo) then return end
  local line, rank = openLine()
  if not line then return end
  local recipes = Data.professions[line].recipes
  local known = Core.Char().known
  known[line] = known[line] or {}
  local bad = 0
  for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
    local info = T.GetRecipeInfo(id)
    if info and info.learned then
      known[line][id] = true
      local r = recipes[id]
      local live = DIFF[info.relativeDifficulty] or DIFF[info.difficulty]
      if r and rank and live and live ~= Planner.Color(r, rank) then bad = bad + 1 end
    end
  end
  Core.mismatch[line] = bad
  Core.Changed()
end

-- Recipes are spells: also pick up ones learned while the window was closed.
local function knownSet(line)
  local saved = Core.Char().known[line] or {}
  local set = {}
  for id in pairs(saved) do set[id] = true end
  local isKnown = IsPlayerSpell or IsSpellKnown
  if isKnown then
    for id in pairs(Data.professions[line].recipes) do
      if not set[id] and isKnown(id) then set[id] = true end
    end
  end
  return set
end

-- Trainer scan -----------------------------------------------------------------
-- The skill a trainer recipe is learned at and its price are server-side; the
-- trainer window is the only place the client sees them, so we save them here.
local function itemIdFromLink(link)
  return link and tonumber(link:match("item:(%d+)"))
end

-- name -> {spell,...} per profession, built on first use
local byName = {}
local function recipesNamed(line, name)
  local idx = byName[line]
  if not idx then
    idx = {}
    for spell, r in pairs(Data.professions[line].recipes) do
      idx[r.n] = idx[r.n] or {}
      table.insert(idx[r.n], spell)
    end
    byName[line] = idx
  end
  return idx[name]
end

-- Reads only what the trainer window shows. It never changes the window's filters:
-- that fires TRAINER_UPDATE, which would re-run the scan in a loop.
function Core.ScanTrainer()
  if not (GetNumTrainerServices and GetTrainerServiceInfo and GetTrainerServiceSkillReq) then return end
  local d, found = db(), 0
  for i = 1, GetNumTrainerServices() do
    local name = GetTrainerServiceInfo(i)
    local skillName, req = GetTrainerServiceSkillReq(i)
    local line = skillName and nameToLine[skillName]
    local spells = line and name and recipesNamed(line, name)
    if spells then
      local out = GetTrainerServiceItemLink and itemIdFromLink(GetTrainerServiceItemLink(i))
      local recipes = Data.professions[line].recipes
      local match, matchScore = nil, -1
      for _, spell in ipairs(spells) do -- same name can exist twice (e.g. Earthen Vest)
        local r = recipes[spell]
        local score = (out and r.out == out and 2 or 0) + ((r.src == "T" or r.src == "t") and 1 or 0)
        if score > matchScore then match, matchScore = spell, score end
      end
      local cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or nil
      d.trainer[line] = d.trainer[line] or {}
      local old = d.trainer[line][match]
      if not old or old.req ~= (req or 0) or old.cost ~= cost then
        d.trainer[line][match] = { req = req or 0, cost = cost }
        found = found + 1
      end
    end
  end
  if found > 0 then Core.dataVersion = Core.dataVersion + 1; Core.Changed() end
end

-- Prices -----------------------------------------------------------------------
-- Auctionator's last scan; vendor price for trade-supply items. Nothing else is
-- guessed: an item with neither is unpriced, unless estimates are switched on.
local function auctionator()
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  return api and api.GetAuctionPriceByItemID and api or nil
end

function Core.PriceSource()
  return auctionator() and "Auctionator" or nil
end

function Core.Price(item)
  local api = auctionator()
  local ah, vendor
  if api then
    local ok, v = pcall(api.GetAuctionPriceByItemID, CALLER, item)
    ah = ok and v or nil
    if api.GetVendorPriceByItemID then
      ok, v = pcall(api.GetVendorPriceByItemID, CALLER, item)
      vendor = ok and v or nil
    end
  end
  local it = Data.items[item]
  vendor = vendor or (it and it[3])
  if ah and vendor then return math.min(ah, vendor), false end
  if ah or vendor then return ah or vendor, false end
  if db().settings.estimate and it and it[2] and it[2] > 0 then
    return it[2] * 4, true -- clearly flagged as an estimate in the UI
  end
  return nil
end

local getCount = (C_Item and C_Item.GetItemCount) or GetItemCount
function Core.Have(item)
  return getCount and getCount(item, true) or 0 -- bags + bank
end

-- A tool only counts in your bags (or equipped), not in the bank.
function Core.HasTool(key)
  local def = Data.tools[key]
  if not (def and getCount) then return false end
  for _, item in ipairs(def[2]) do
    if getCount(item) > 0 then return true end
  end
  return false
end

local toolsFor = {}
function Core.ToolsFor(line) -- tool keys any recipe of this profession needs
  if not toolsFor[line] then
    local set = {}
    for _, r in pairs(Data.professions[line].recipes) do
      for _, t in ipairs(r.tool or {}) do set[t] = true end
    end
    toolsFor[line] = set
  end
  return toolsFor[line]
end

-- Planning ---------------------------------------------------------------------
-- The search for patterns/tools worth buying (tens of ms) depends on skill,
-- target, known recipes, trainer data, owned tools, prices and settings, but not
-- on reagents in your bags. Bag changes re-plan with the cached choice (a few ms).
-- Any input change, an Auctionator scan, or reopening the window searches again.
Core.dataVersion = 0
local patternCache = {}
function Core.InvalidatePatterns() patternCache = {} end

function Core.Plan(line, target)
  local s = Core.Skills()[line]
  if not s then -- fall back to the open profession window, if it is this profession
    local liveLine, liveRank, liveMax = openLine()
    if liveLine == line and liveRank then s = { rank = liveRank, max = liveMax } end
  end
  if not s then return nil, "This character doesn't have " .. Data.professions[line].name .. "." end
  target = math.max(s.rank + 1, math.min(target or 300, 300))
  local t0 = debugprofilestop and debugprofilestop()
  local known, settings = knownSet(line), db().settings
  local nKnown = 0
  for _ in pairs(known) do nKnown = nKnown + 1 end
  local key = table.concat({ s.rank, target, nKnown, Core.dataVersion, settings.bonus or 0,
                             tostring(settings.estimate) }, ":")
  local recipes = Data.professions[line].recipes
  local owned = {}
  for key in pairs(Core.ToolsFor(line)) do if Core.HasTool(key) then owned[#owned + 1] = key end end
  table.sort(owned)
  key = key .. ":" .. table.concat(owned, ",")
  local cached = patternCache[line]
  local plan = Planner.Plan({
    recipes = recipes, items = Data.items, tools = Data.tools,
    skill = s.rank, target = target,
    known = known, trainer = db().trainer[line] or {},
    price = Core.Price, have = Core.Have, hasTool = Core.HasTool, bonus = settings.bonus or 0,
    fixedUnlocks = cached and cached.key == key and cached.set or nil,
  })
  if not (cached and cached.key == key) then
    local set = {}
    for k in pairs(plan.unlocks or {}) do set[k] = true end
    patternCache[line] = { key = key, set = set }
  end
  plan.ms = t0 and (debugprofilestop() - t0)
  plan.skill, plan.max, plan.target, plan.line = s.rank, s.max, target, line
  plan.mismatch = Core.mismatch[line]
  return plan
end

-- Change notification: coalesce bursts of events into one re-plan.
local pending = false
function Core.Changed()
  if pending or not (ns.UI and ns.UI.IsShown()) then return end
  pending = true
  C_Timer.After(0.1, function() pending = false; ns.UI.Refresh() end)
end

-- Events -------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(_, ev, arg1)
  if ev == "ADDON_LOADED" and arg1 == addonName then
    db()
  elseif ev == "PLAYER_LOGIN" then
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if api and api.RegisterForDBUpdate then
      pcall(api.RegisterForDBUpdate, CALLER, function() Core.InvalidatePatterns(); Core.Changed() end)
    end
  elseif ev == "TRADE_SKILL_SHOW" or ev == "TRADE_SKILL_LIST_UPDATE" or ev == "NEW_RECIPE_LEARNED" then
    if ev == "NEW_RECIPE_LEARNED" then Core.dataVersion = Core.dataVersion + 1 end
    Core.ScanRecipes()
    if ns.UI then ns.UI.AttachButton() end
  elseif ev == "TRAINER_SHOW" or ev == "TRAINER_UPDATE" then
    Core.ScanTrainer()
  else -- skill or bag change
    Core.Changed()
  end
end)
for _, ev in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE",
                      "NEW_RECIPE_LEARNED", "TRAINER_SHOW", "TRAINER_UPDATE", "SKILL_LINES_CHANGED",
                      "BAG_UPDATE_DELAYED" }) do
  pcall(f.RegisterEvent, f, ev) -- an event this client lacks must not break the addon
end
