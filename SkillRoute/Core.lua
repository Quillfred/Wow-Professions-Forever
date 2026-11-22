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
local recordTrainer -- defined with the places code below

function Core.ScanTrainer()
  if not (GetNumTrainerServices and GetTrainerServiceInfo and GetTrainerServiceSkillReq) then return end
  recordTrainer()
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

-- Places: trainers and pattern vendors you've visited ------------------------------
-- The client data has no NPC names or locations, so we note them when you talk to
-- a trainer or vendor: name, zone, map coordinates, your faction. Account-wide.
local RANK_TEXT = { Journeyman = true, Expert = true, Artisan = true }

local function places()
  local d = db()
  d.places = d.places or {}
  d.places.trainers = d.places.trainers or {}
  d.places.vendors = d.places.vendors or {}
  return d.places
end

local function here()
  local p = { zone = (GetRealZoneText and GetRealZoneText()) or "?",
              faction = UnitFactionGroup and UnitFactionGroup("player") or nil,
              t = time and time() or 0 }
  local sub = GetSubZoneText and GetSubZoneText()
  if sub and sub ~= "" and sub ~= p.zone then p.sub = sub end
  if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
    local map = C_Map.GetBestMapForUnit("player")
    p.ui = map
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if pos then
      local x, y = pos:GetXY()
      if x and y and (x > 0 or y > 0) then p.x, p.y = math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10 end
    end
  end
  return p
end

-- Best known place: your faction's, in your current zone if possible, else the
-- most recently seen. Returns entry (with .npc), number known.
function Core.Place(kind, key, rank)
  local pl = places()
  local list = (kind == "trainer" and pl.trainers[key]) or (kind == "vendor" and pl.vendors[key]) or nil
  if not list then return nil, 0 end
  local mine = UnitFactionGroup and UnitFactionGroup("player")
  local zone = GetRealZoneText and GetRealZoneText()
  local best, n = nil, 0
  for npc, e in pairs(list) do
    if (not mine or not e.faction or e.faction == mine) and (not rank or (e.ranks and e.ranks[rank])) then
      n = n + 1
      local better = not best
        or ((e.zone == zone) and best.zone ~= zone)
        or ((e.zone == zone) == (best.zone == zone) and (e.t or 0) > (best.t or 0))
      if better then best = e; best.npc = npc end
    end
  end
  return best, n
end

function Core.FormatPlace(e, withCoords)
  if not e then return nil end
  local where = e.zone .. (e.sub and (", " .. e.sub) or "")
  if withCoords and e.x then where = where .. (" (%.1f, %.1f)"):format(e.x, e.y) end
  return e.npc .. ", " .. where
end

recordTrainer = function()
  local npc = UnitName and UnitName("npc")
  if not npc or not GetNumTrainerServices then return end
  local lines = {}
  for i = 1, GetNumTrainerServices() do
    local name, sub = GetTrainerServiceInfo(i)
    local line = name and nameToLine[name]
    if line and sub and RANK_TEXT[sub] then -- a rank-up, e.g. "Tailoring" / "Expert"
      lines[line] = lines[line] or {}
      lines[line][sub] = true
    end
    local skillName = GetTrainerServiceSkillReq and GetTrainerServiceSkillReq(i)
    local l2 = skillName and nameToLine[skillName]
    if l2 then lines[l2] = lines[l2] or {} end
  end
  local spot = here()
  for line, ranks in pairs(lines) do
    local t = places().trainers
    t[line] = t[line] or {}
    local e = t[line][npc] or {}
    for k, v in pairs(spot) do e[k] = v end
    e.ranks = e.ranks or {}
    for r in pairs(ranks) do e.ranks[r] = true end
    t[line][npc] = e
  end
end

-- NPCs from the data (Classic spawns) -------------------------------------------
-- Zones overlap as rectangles, so the zone is asked from the game itself: world
-- position -> continent map -> zone at that spot -> zone coordinates. The continent
-- coordinates computed offline double-check the game's answer (and which way round
-- it wants the world axes) before it is used.
local function round1(v) return math.floor(v * 10 + 0.5) / 10 end
local resolved = {}

function Core.NPCLocation(id)
  local n = Data.npcs and Data.npcs[id]
  if not n then return nil end
  if resolved[id] then return resolved[id] end
  local loc = { npc = n[1], side = n[2], cui = n[6], cx = n[7], cy = n[8], zone = n[9], x = n[10], y = n[11] }
  if n[6] and C_Map and C_Map.GetMapPosFromWorldPos and C_Map.GetMapInfoAtPosition and CreateVector2D then
    for _, swap in ipairs({ false, true }) do
      local vec = swap and CreateVector2D(n[5], n[4]) or CreateVector2D(n[4], n[5])
      local ok, _, cpos = pcall(C_Map.GetMapPosFromWorldPos, n[3], vec, n[6])
      if ok and cpos and math.abs(cpos.x * 100 - n[7]) < 0.5 and math.abs(cpos.y * 100 - n[8]) < 0.5 then
        local info = C_Map.GetMapInfoAtPosition(n[6], cpos.x, cpos.y)
        if info and info.mapID then
          local ok2, _, zpos = pcall(C_Map.GetMapPosFromWorldPos, n[3], vec, info.mapID)
          if ok2 and zpos then
            loc.ui, loc.zone, loc.x, loc.y = info.mapID, info.name, round1(zpos.x * 100), round1(zpos.y * 100)
          end
        end
        break
      end
    end
  end
  if loc.ui then resolved[id] = loc end -- don't keep a failed lookup: try again next time
  return loc
end

-- your position on the continent map (uiMapID, x, y in 0-100), or nil
local function playerContinent()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo and C_Map.GetPlayerMapPosition) then return end
  local m = C_Map.GetBestMapForUnit("player")
  for _ = 1, 8 do
    local info = m and C_Map.GetMapInfo(m)
    if not info then return end
    if info.mapType == 2 then -- continent
      local pos = C_Map.GetPlayerMapPosition(m, "player")
      if pos then local x, y = pos:GetXY(); return m, x * 100, y * 100 end
      return
    end
    m = info.parentMapID
  end
end

-- The nearest of these NPCs that deals with your faction: same continent first.
function Core.NearestNPC(ids)
  local mine = UnitFactionGroup and UnitFactionGroup("player")
  local letter = mine == "Alliance" and "A" or mine == "Horde" and "H" or nil
  local cui, px, py = playerContinent()
  local best, bestD
  for _, id in ipairs(ids or {}) do
    local n = Data.npcs and Data.npcs[id]
    if n and (not letter or n[2]:find(letter, 1, true)) then
      local d = 1e9
      if cui and n[6] == cui then d = (n[7] - px) ^ 2 + (n[8] - py) ^ 2 end
      if not bestD or d < bestD then best, bestD = id, d end
    end
  end
  return best and Core.NPCLocation(best)
end

-- Who can teach a rank-up (rankStep: 2 Journeyman, 3 Expert, 4 Artisan)? In Forever a
-- trainer teaches up to the rank below its own title: Expert from an Artisan or Master.
function Core.NearestTrainer(line, rankStep)
  local ids = {}
  for id, rank in pairs(Data.trainers and Data.trainers[line] or {}) do
    if rank - 1 >= rankStep then ids[#ids + 1] = id end
  end
  table.sort(ids)
  return Core.NearestNPC(ids)
end

-- Nearest trainer who teaches this recipe. Candidates: the Classic trainer lists
-- for the recipe, plus every trainer of the profession whose rank (list or title)
-- covers its learn level (Journeyman from 50, Expert from 125, Artisan from 225) -
-- the Classic lists are incomplete. Assumption: a trainer teaches recipes of its own
-- rank (only the rank-up rule is documented for Forever).
function Core.NearestRecipeTrainer(line, spell, learnAt)
  local L = learnAt or 0
  local need = L >= 225 and 4 or L >= 125 and 3 or L >= 50 and 2 or 1
  local ids, listed = {}, {}
  local set = Data.recipeTrainers and Data.recipeTrainers[spell]
  for _, id in ipairs(set and Data.trainerSets[set] or {}) do ids[#ids + 1] = id; listed[id] = true end
  for id, top in pairs(Data.trainers and Data.trainers[line] or {}) do
    if top >= need and not listed[id] then ids[#ids + 1] = id end
  end
  table.sort(ids)
  local loc = Core.NearestNPC(ids)
  local id
  if loc then for _, i in ipairs(ids) do if Data.npcs[i] and Data.npcs[i][1] == loc.npc then id = i end end end
  return loc, id and listed[id] or false
end

function Core.NearestVendor(item)
  return Core.NearestNPC(Data.vendorNpcs and Data.vendorNpcs[item])
end

-- "Zone (x, y)"; for an NPC the game couldn't place, its spot on the continent map.
function Core.Where(loc)
  if not loc then return nil end
  if loc.zone and loc.x then return ("%s (%.1f, %.1f)"):format(loc.zone, loc.x, loc.y) end
  local cont = loc.cui and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(loc.cui)
  if loc.cx then return ("%s map (%.1f, %.1f)"):format(cont and cont.name or "continent", loc.cx, loc.cy) end
  return loc.zone
end

-- Waypoint to an NPC (TomTom, else the game's own map pin, else chat).
function Core.Waypoint(loc, title)
  if not loc then return end
  local ui, x, y = loc.ui, loc.x, loc.y
  if not (ui and x) then ui, x, y = loc.cui, loc.cx, loc.cy end
  title = title or loc.npc
  if not (ui and x) then
    print(("SkillRoute: no coordinates known for %s."):format(title or "?"))
    return
  end
  if TomTom and TomTom.AddWaypoint then
    TomTom:AddWaypoint(ui, x / 100, y / 100, { title = title, persistent = false, minimap = true, world = true })
    print(("SkillRoute: TomTom waypoint set to %s, %s."):format(title, Core.Where(loc) or ""))
  elseif C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates
      and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(ui)) then
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(ui, x / 100, y / 100))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    print(("SkillRoute: map pin set on %s, %s."):format(title, Core.Where(loc) or ""))
  else
    print(("SkillRoute: %s is at %s (install TomTom for waypoints)."):format(title, Core.Where(loc) or "?"))
  end
end

-- pattern item -> true, built on first use
local patternItems
local function isPattern(item)
  if not patternItems then
    patternItems = {}
    for _, p in pairs(Data.professions) do
      for _, r in pairs(p.recipes) do for _, it in ipairs(r.pat or {}) do patternItems[it] = true end end
    end
  end
  return patternItems[item]
end

function Core.ScanMerchant()
  local npc = UnitName and UnitName("npc")
  if not npc or not GetMerchantNumItems then return end
  local spot, found = nil, 0
  for i = 1, GetMerchantNumItems() do
    local id = (GetMerchantItemID and GetMerchantItemID(i))
               or itemIdFromLink(GetMerchantItemLink and GetMerchantItemLink(i))
    if id and isPattern(id) then
      spot = spot or here()
      local _, _, price, _, numAvailable = GetMerchantItemInfo(i)
      local v = places().vendors
      v[id] = v[id] or {}
      local e = {}
      for k, val in pairs(spot) do e[k] = val end
      e.price, e.limited = price, (numAvailable and numAvailable >= 0) or nil
      v[id][npc] = e
      found = found + 1
    end
  end
  if found > 0 then Core.Changed() end
end

-- Prices -----------------------------------------------------------------------
-- Auctionator's last scan; vendor price for trade-supply items. Nothing else is
-- guessed: an item with neither is unpriced, unless estimates are switched on.
local function auctionator()
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  return api and api.GetAuctionPriceByItemID and api or nil
end

-- Seen on the AH today or yesterday? For one-off listings such as patterns, an old
-- "last seen" price says nothing about whether one is for sale now. Without
-- Auctionator's age API we can't tell, and don't block (right-click skip covers it).
local MAX_AH_AGE_DAYS = 1
function Core.AHFresh(item)
  local api = auctionator()
  if not (api and api.GetAuctionAgeByItemID) then return true end
  local ok, age = pcall(api.GetAuctionAgeByItemID, CALLER, item)
  if not ok then return true end
  return age ~= nil and age <= MAX_AH_AGE_DAYS
end

-- Recipes you marked as unavailable (right-click a step); per character.
function Core.Skips(line)
  local c = Core.Char()
  c.skip = c.skip or {}
  c.skip[line] = c.skip[line] or {}
  return c.skip[line]
end
function Core.ToggleSkip(line, spell)
  local s = Core.Skips(line)
  s[spell] = not s[spell] or nil
  Core.InvalidatePatterns()
  return s[spell]
end
function Core.ClearSkips()
  Core.Char().skip = {}
  Core.InvalidatePatterns()
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

-- Your reputation with a faction as a rank 0-7 (4 Friendly ... 7 Exalted), or nil.
function Core.Standing(faction)
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local d = C_Reputation.GetFactionDataByID(faction)
    if d and d.reaction then return d.reaction - 1 end
  end
  if GetFactionInfoByID then
    local _, _, standingID = GetFactionInfoByID(faction)
    if standingID then return standingID - 1 end
  end
  return nil
end

local factionsFor = {}
function Core.FactionsFor(line) -- factions any pattern of this profession needs
  if not factionsFor[line] then
    local set = {}
    for _, r in pairs(Data.professions[line].recipes) do
      local rep = r.rep
      if rep then for i = 2, #rep, 3 do set[rep[i]] = true end end
    end
    local list = {}
    for f in pairs(set) do list[#list + 1] = f end
    table.sort(list)
    factionsFor[line] = list
  end
  return factionsFor[line]
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
                             tostring(settings.estimate), tostring(settings.cdmats) }, ":")
  local recipes = Data.professions[line].recipes
  local owned = {}
  for key in pairs(Core.ToolsFor(line)) do if Core.HasTool(key) then owned[#owned + 1] = key end end
  table.sort(owned)
  key = key .. ":" .. table.concat(owned, ",")
  for _, f in ipairs(Core.FactionsFor(line)) do key = key .. ":" .. f .. "=" .. tostring(Core.Standing(f)) end
  local cached = patternCache[line]
  local plan = Planner.Plan({
    recipes = recipes, items = Data.items, tools = Data.tools,
    skill = s.rank, target = target, maxSkill = s.max,
    known = known, trainer = db().trainer[line] or {},
    price = Core.Price, have = Core.Have, hasTool = Core.HasTool, standing = Core.Standing,
    avoidMats = not settings.cdmats and Data.cooldownMats or nil,
    faction = (UnitFactionGroup and UnitFactionGroup("player") == "Alliance") and "A"
              or (UnitFactionGroup and UnitFactionGroup("player") == "Horde") and "H" or nil,
    patternVendors = Data.patternVendors,
    vendorSeen = function(item) return Core.Place("vendor", item) ~= nil end,
    bonus = settings.bonus or 0,
    fixedUnlocks = cached and cached.key == key and cached.set or nil,
    skip = Core.Skips(line), ahFresh = Core.AHFresh,
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
    if ev == "TRADE_SKILL_SHOW" and db().settings.auto ~= false and ns.UI then
      -- next frame: the window's profession info is filled in after the event
      C_Timer.After(0, function()
        local T = C_TradeSkillUI
        local other = T and ((T.IsTradeSkillLinked and T.IsTradeSkillLinked())
                             or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
                             or (T.IsNPCCrafting and T.IsNPCCrafting()))
        local line = openLine()
        if line and not other then ns.UI.AutoOpen(line) end -- crafting professions only
      end)
    end
  elseif ev == "TRADE_SKILL_CLOSE" then
    if ns.UI then ns.UI.AutoClose() end
  elseif ev == "MERCHANT_SHOW" then
    Core.ScanMerchant()
  elseif ev == "TRAINER_SHOW" or ev == "TRAINER_UPDATE" then
    Core.ScanTrainer()
  else -- skill or bag change
    Core.Changed()
  end
end)
for _, ev in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE",
                      "NEW_RECIPE_LEARNED", "TRAINER_SHOW", "TRAINER_UPDATE", "SKILL_LINES_CHANGED", "MERCHANT_SHOW",
                      "BAG_UPDATE_DELAYED", "UPDATE_FACTION", "TRADE_SKILL_CLOSE" }) do
  pcall(f.RegisterEvent, f, ev) -- an event this client lacks must not break the addon
end
