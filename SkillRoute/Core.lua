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
  d.settings = d.settings or {}
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

-- Working Overtime: a Legacy Tree (Professions) talent, 5 ranks of +4% skill-up chance.
-- Read from the game: the tree's nodes are searched for the talent's spell (never its
-- name, so any language works). Read only; nothing is ever bought or changed.
local WO_SPELL, WO_PER_RANK, WO_MAX, WO_TREE = 1225451, 0.04, 5, 1187
local woRank -- nil until the tree has been read

-- Returns the rank (0 = not learned), or nil if the game can't tell yet.
local function readOvertime()
  local T = C_Traits
  if not (T and T.GetConfigIDByTreeID and T.GetTreeNodes and T.GetNodeInfo and T.GetEntryInfo
          and T.GetDefinitionInfo) then return nil end
  local L = Constants and Constants.LegacyConsts
  local tree = (L and L.LEGACY_TREE_PROFESSIONS_ID) or WO_TREE
  local ok, config = pcall(T.GetConfigIDByTreeID, tree)
  if not ok or not config then return nil end -- not loaded yet
  local ok2, nodes = pcall(T.GetTreeNodes, tree)
  if not ok2 or type(nodes) ~= "table" then return nil end
  local function spellOf(entry)
    local okE, e = pcall(T.GetEntryInfo, config, entry)
    if not okE or not e or not e.definitionID then return nil end
    local okD, d = pcall(T.GetDefinitionInfo, e.definitionID)
    return okD and d and d.spellID or nil
  end
  for _, node in ipairs(nodes) do
    local okN, info = pcall(T.GetNodeInfo, config, node)
    if okN and type(info) == "table" then
      local entries = {}
      if info.activeEntry and info.activeEntry.entryID then entries[1] = info.activeEntry.entryID end
      for _, e in ipairs(info.entryIDs or {}) do entries[#entries + 1] = e end
      for _, e in ipairs(entries) do
        if spellOf(e) == WO_SPELL then
          local r = math.floor(tonumber(info.activeRank or info.ranksPurchased or 0) or 0)
          return math.max(0, math.min(WO_MAX, r))
        end
      end
    end
  end
  return 0 -- the whole tree read, no Working Overtime
end

-- Read again; re-plan if the rank changed. Returns whether the tree could be read.
function Core.ReadOvertime()
  local r = readOvertime()
  if r ~= nil and r ~= woRank then
    woRank = r
    Core.InvalidatePatterns(); Core.Changed()
  end
  return r ~= nil
end

-- { rank (nil = couldn't read), max, per, name }
function Core.OvertimeInfo()
  local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(WO_SPELL)
  return { rank = woRank, max = WO_MAX, per = WO_PER_RANK, name = name or "Working Overtime" }
end

-- The skill-up bonus (0-1): your rank from the Legacy Tree; only when the game can't tell,
-- what you set with /sr overtime (saved per character: it's a talent). An older
-- account-wide value moves to the first character that logs in after the update.
function Core.Bonus()
  if woRank then return woRank * WO_PER_RANK end
  local c, d = Core.Char(), db()
  if c.bonus == nil then c.bonus = d.settings.bonus or 0; d.settings.bonus = nil end
  return c.bonus
end

-- Read at login and after every loading screen (retrying every 5 s for ~30 s while the
-- tree loads), and straight away when a talent changes.
do
  local tries = 0
  local function attempt()
    if not Core.ReadOvertime() and tries < 6 then
      tries = tries + 1
      C_Timer.After(5, attempt)
    end
  end
  local f = CreateFrame("Frame")
  for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "TRAIT_CONFIG_LIST_UPDATED", "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED" }) do
    pcall(f.RegisterEvent, f, ev) -- an event this client doesn't have is skipped
  end
  f:SetScript("OnEvent", function(_, ev)
    if ev == "PLAYER_ENTERING_WORLD" then tries = 0; attempt() else Core.ReadOvertime() end
  end)
end

-- Professions ------------------------------------------------------------------
-- Profession names -> skill line. English from the data, plus the player's language:
-- each profession's Apprentice rank spell is named after it ("Schneiderei").
local nameToLine = {}
for line, p in pairs(Data.professions) do nameToLine[p.name] = line end
local localized = false
local function localizeNames()
  if localized then return end
  for line, p in pairs(Data.professions) do
    local n = p.spell and ((C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(p.spell))
                           or (GetSpellInfo and GetSpellInfo(p.spell)))
    if n and n ~= "" then
      rawset(nameToLine, n, line)
      localized = true -- done once spell names are available; retried until then
    end
  end
end
setmetatable(nameToLine, { __index = function(t, k) -- localize on first miss
  if not localized then localizeNames(); return rawget(t, k) end
end })

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
  local mine = known[line]
  -- what the window says wins: learned -> true, listed as not learned -> false (that
  -- also overrides the game's spell check). Recipes it doesn't list (search box,
  -- filters) are left as they were.
  local changed, bad = false, 0
  for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
    local info = T.GetRecipeInfo(id)
    if info then
      local v = info.learned and true or false
      if mine[id] ~= v and (v or recipes[id]) then mine[id] = v; changed = true end
      if v then
        local r = recipes[id]
        local live = DIFF[info.relativeDifficulty] or DIFF[info.difficulty]
        if r and rank and live and live ~= Planner.Color(r, rank) then bad = bad + 1 end
      end
    end
  end
  Core.mismatch[line] = bad
  if changed then Core.InvalidatePatterns() end
  Core.Changed()
end

-- Recipes are spells: also pick up ones learned while the window was closed.
local function knownSet(line)
  local saved = Core.Char().known[line] or {}
  local set = {}
  for id, v in pairs(saved) do if v then set[id] = true end end
  local isKnown = IsPlayerSpell or IsSpellKnown
  if isKnown then
    for id in pairs(Data.professions[line].recipes) do
      -- false = the profession window listed it as not learned: that wins
      if saved[id] == nil and isKnown(id) then set[id] = true end
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

-- output item -> {spell,...} per profession (language-independent match first)
local byOut = {}
local function recipesMaking(line, item)
  local idx = byOut[line]
  if not idx then
    idx = {}
    for spell, r in pairs(Data.professions[line].recipes) do
      if r.out then idx[r.out] = idx[r.out] or {}; table.insert(idx[r.out], spell) end
    end
    byOut[line] = idx
  end
  return idx[item]
end

-- name -> {spell,...} per profession, built on first use (English names: fallback)
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

-- Trainer service i -> profession line, recipe spell, skill required, cost, and the
-- service type ("available", "unavailable", "used"). nil if it isn't a recipe we know.
function Core.TrainerService(i)
  local name, _, kind = GetTrainerServiceInfo(i)
  local skillName, req = GetTrainerServiceSkillReq(i)
  local line = skillName and nameToLine[skillName]
  local out = line and GetTrainerServiceItemLink and itemIdFromLink(GetTrainerServiceItemLink(i))
  local spells = line and ((out and recipesMaking(line, out)) or (name and recipesNamed(line, name)))
  if not spells then return nil end
  local recipes = Data.professions[line].recipes
  local match, matchScore = nil, -1
  for _, spell in ipairs(spells) do -- same name can exist twice (e.g. Earthen Vest)
    local r = recipes[spell]
    local score = (out and r.out == out and 2 or 0) + ((r.src == "T" or r.src == "t") and 1 or 0)
    if score > matchScore then match, matchScore = spell, score end
  end
  local cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or nil
  return line, match, req, cost, kind
end

function Core.ScanTrainer()
  if not (GetNumTrainerServices and GetTrainerServiceInfo and GetTrainerServiceSkillReq) then return end
  recordTrainer()
  local d, found = db(), 0
  for i = 1, GetNumTrainerServices() do
    local line, match, req, cost = Core.TrainerService(i)
    if match then
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
    if line and sub and sub ~= "" then -- a rank-up, e.g. "Tailoring" / "Expert"
      local rank = RANK_TEXT[sub] and sub
      if not rank then -- other languages: from the skill the rank-up needs
        local _, req = GetTrainerServiceSkillReq(i)
        req = req or 0
        rank = req >= 200 and "Artisan" or req >= 125 and "Expert" or req >= 50 and "Journeyman" or nil
      end
      if rank then
        lines[line] = lines[line] or {}
        lines[line][rank] = true
      end
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
  if n[12] then -- exact zone map + coordinates (AllTheThings): nothing to resolve
    loc.ui = n[12]
    resolved[id] = loc
    return loc
  end
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

-- Travel ---------------------------------------------------------------------------
-- "Nearest" = shortest travel time: running (RUN yards/second) on a continent, plus
-- boats/zeppelins your faction can use (a full trip each, to cover waiting + riding),
-- chained as needed (Orgrimmar -> Undercity -> Grom'gol). Flight paths and terrain
-- are ignored: it ranks trainers, it isn't an ETA.
local RUN = 7

local function myLetter()
  local mine = UnitFactionGroup and UnitFactionGroup("player")
  return mine == "Alliance" and "A" or mine == "Horde" and "H" or nil
end

-- your world position (map, x, y) from your spot on the continent map
local function playerWorld()
  local cui, px, py = playerContinent()
  if not cui then return end
  for map, c in pairs(Data.continents or {}) do
    if c[1] == cui then
      local u, v = px / 100, py / 100
      local x0, y0, x1, y1, u0, v0, u1, v1 = c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9]
      return map, x1 - (v - v0) / (v1 - v0) * (x1 - x0), y1 - (u - u0) / (u1 - u0) * (y1 - y0)
    end
  end
end

Core.PlayerWorld = playerWorld

-- Errors: never leave the window blank or spam chat. The last error is kept for
-- /sr check and shown once per session.
local shownError = false
-- this copy's version (the .toc), to tell an old saved error from a current one
function Core.Version()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ok, v = pcall(get or error, addonName, "Version")
  return ok and v or "?"
end
function Core.ReportError(where, err)
  local msg = ("%s: %s"):format(where, tostring(err))
  if SkillRouteDB then
    SkillRouteDB.lastError = msg
    SkillRouteDB.lastErrorVersion = Core.Version()
    SkillRouteDB.lastErrorTime = time and time() or nil
  end
  if not shownError then
    shownError = true
    print("|cffff4040SkillRoute hit an error|r (" .. msg .. "). Type /sr check and send a screenshot.")
  end
end

local function walk(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) / RUN end

-- Flight points this character knows: recorded when a flight map is open (the map
-- shows known and unknown ones). Only these are used for travel.
local taxiVersion = 0
function Core.KnownTaxi()
  local c = Core.Char()
  c.taxi = c.taxi or {}
  return c.taxi
end

function Core.RecordTaxi()
  local known, added = Core.KnownTaxi(), 0
  local T = C_TaxiMap
  if T and T.GetAllTaxiNodes and GetTaxiMapID then
    local ok, nodes = pcall(T.GetAllTaxiNodes, GetTaxiMapID())
    local unreachable = Enum and Enum.FlightPathState and Enum.FlightPathState.Unreachable or 2
    for _, node in ipairs(ok and nodes or {}) do
      if node.nodeID and node.state ~= unreachable and not known[node.nodeID] then
        known[node.nodeID] = true; added = added + 1
      end
    end
  elseif NumTaxiNodes and TaxiNodeName and TaxiNodeGetType then
    local byName = {}
    for id, n in pairs(Data.taxi and Data.taxi.nodes or {}) do byName[n[5]] = id end
    for i = 1, NumTaxiNodes() do
      local t = TaxiNodeGetType(i)
      local id = byName[TaxiNodeName(i)]
      if id and (t == "CURRENT" or t == "REACHABLE") and not known[id] then known[id] = true; added = added + 1 end
    end
  end
  if added > 0 then taxiVersion = taxiVersion + 1; Core.Changed() end
end

-- Hearthstone and mage teleports -------------------------------------------------
-- Used as a first leg from where you stand. The hearthstone counts with its cooldown:
-- ready = the 10 s cast; on cooldown = the time left + the cast; plus HEARTH_COST, so
-- it only wins when it saves real time (not for a vendor across town). Its destination: where you were standing when you
-- last bound it (recorded), else the flight master of the town GetBindLocation()
-- names. Teleports: only for a mage who knows the spell and carries a Rune of
-- Teleportation (another player's portal can't be planned).
local HEARTHSTONE, RUNE_OF_TELEPORTATION, CAST = 6948, 17031, 10
-- Using the hearthstone costs more than its cast: an hour of cooldown and you end up
-- far from where you were. It's only worth it when it saves at least this much.
local HEARTH_COST = 300
local function itemCount(item) -- bags only
  local f = (C_Item and C_Item.GetItemCount) or GetItemCount
  return f and f(item) or 0
end
local TELEPORTS = { [3561] = "Stormwind", [3562] = "Ironforge", [3563] = "Undercity",
                    [3565] = "Darnassus", [3566] = "Thunder Bluff", [3567] = "Orgrimmar" }

local function townNode(town) -- the flight master of a town, by name ("Orgrimmar, Durotar")
  if not town then return nil end
  local want = town:lower():gsub("^the ", "")
  local letter = myLetter()
  for _, n in pairs(Data.taxi and Data.taxi.nodes or {}) do
    local first = (n[5]:match("^([^,]+)") or n[5]):lower():gsub("^the ", "")
    if first == want and (not letter or n[4]:find(letter, 1, true)) then return n end
  end
end

function Core.RecordBind()
  local pm, px, py = playerWorld()
  if pm then Core.Char().bind = { map = pm, x = px, y = py, name = GetBindLocation and GetBindLocation() } end
end

local function cooldownLeft(item)
  local start, duration
  if C_Container and C_Container.GetItemCooldown then start, duration = C_Container.GetItemCooldown(item)
  elseif GetItemCooldown then start, duration = GetItemCooldown(item) end
  if not (start and duration and start > 0 and GetTime) then return 0 end
  return math.max(0, start + duration - GetTime())
end

-- first legs from your position: { map, x, y, seconds, label }
function Core.Shortcuts()
  local out = {}
  if itemCount(HEARTHSTONE) > 0 then
    local bindName = GetBindLocation and GetBindLocation()
    local b = Core.Char().bind
    local dest
    if b and b.name == bindName then dest = { b.map, b.x, b.y }
    else local n = townNode(bindName); if n then dest = { n[1], n[2], n[3] } end end
    if dest then
      local left = cooldownLeft(HEARTHSTONE)
      out[#out + 1] = { dest[1], dest[2], dest[3], left + CAST + HEARTH_COST,
        ("hearthstone to %s%s"):format(bindName or "?", left > 0 and (" (ready in %d min)"):format(math.ceil(left / 60)) or "") }
    end
  end
  local class = UnitClass and select(2, UnitClass("player"))
  if class == "MAGE" and itemCount(RUNE_OF_TELEPORTATION) > 0 then
    local known = IsPlayerSpell or IsSpellKnown
    for spell, town in pairs(TELEPORTS) do
      local n = known and known(spell) and townNode(town)
      if n then out[#out + 1] = { n[1], n[2], n[3], CAST, "teleport to " .. town } end
    end
  end
  return out
end

-- Travel graph: boat/zeppelin stops and your known flight points (your faction's).
-- Legs: run between any two points on the same continent; ride a boat/zeppelin
-- (one full trip); fly a known flight path. Dijkstra from your position.
local travelCache
local function travelTable(pm, px, py)
  local letter = myLetter()
  local known = Core.KnownTaxi()
  local shortcuts = Core.Shortcuts()
  local sk = {}
  for _, sc in ipairs(shortcuts) do sk[#sk + 1] = sc[5]:gsub("%(ready in %d+ min%)", "") .. math.floor(sc[4] / 60) end
  local key = table.concat({ pm, math.floor(px / 100), math.floor(py / 100), taxiVersion, tostring(letter),
                             table.concat(sk, "|") }, ":")
  if travelCache and travelCache.key == key then return travelCache[1], travelCache[2], travelCache[3], travelCache[4] end
  local pts, adj = {}, {}
  local function add(map, x, y) pts[#pts + 1] = { map, x, y }; adj[#pts] = {}; return #pts end
  for _, t in ipairs(Data.transports or {}) do
    if not letter or t[2]:find(letter, 1, true) then
      local first = #pts + 1
      for i = 4, #t do add(t[i][1], t[i][2], t[i][3]) end
      for a = first, #pts do
        for b = first, #pts do
          if a ~= b then table.insert(adj[a], { b, t[3], "boat/zeppelin: " .. t[1] }) end
        end
      end
    end
  end
  local taxiIdx = {}
  for id, n in pairs(Data.taxi and Data.taxi.nodes or {}) do
    if known[id] and (not letter or n[4]:find(letter, 1, true)) then
      taxiIdx[id] = add(n[1], n[2], n[3])
      pts[taxiIdx[id]].name = n[5]:match("^([^,]+)") or n[5]
    end
  end
  for _, f in ipairs(Data.taxi and Data.taxi.flights or {}) do
    local a, b = taxiIdx[f[1]], taxiIdx[f[2]]
    if a and b then table.insert(adj[a], { b, f[3], "flight" }) end
  end
  local first = {}
  for _, sc in ipairs(shortcuts) do first[add(sc[1], sc[2], sc[3])] = sc end
  local N = #pts
  -- firstPt[i]: where you go first on the way to point i (a point index you walk to,
  -- or the shortcut you use, e.g. your hearthstone) - what the arrow points at
  local dist, via, done, firstPt = {}, {}, {}, {}
  for i = 1, N do
    dist[i] = pts[i][1] == pm and walk(px, py, pts[i][2], pts[i][3]) or math.huge
    firstPt[i] = i
    local sc = first[i]
    if sc and sc[4] < dist[i] then dist[i] = sc[4]; via[i] = { sc[5] }; firstPt[i] = { shortcut = sc[5] } end
  end
  for _ = 1, N do
    local u, best = nil, math.huge
    for i = 1, N do if not done[i] and dist[i] < best then u, best = i, dist[i] end end
    if not u then break end
    done[u] = true
    local pu = pts[u]
    for v = 1, N do -- run to any point on the same continent
      local pv = pts[v]
      if not done[v] and pv[1] == pu[1] then
        local c = dist[u] + walk(pu[2], pu[3], pv[2], pv[3])
        if c < dist[v] then dist[v] = c; via[v] = via[u]; firstPt[v] = firstPt[u] end
      end
    end
    for _, e in ipairs(adj[u]) do
      local v = e[1]
      if not done[v] and dist[u] + e[2] < dist[v] then
        dist[v] = dist[u] + e[2]
        -- describe the route: consecutive flights collapse into "flight to <last stop>"
        local legs = {}
        for i, l in ipairs(via[u] or {}) do legs[i] = l end
        local label = e[3] == "flight" and ("flight to " .. (pts[v].name or "?")) or e[3]
        if e[3] == "flight" and legs[#legs] and legs[#legs]:find("^flight to ") then legs[#legs] = label
        else legs[#legs + 1] = label end
        via[v] = legs
        firstPt[v] = firstPt[u]
      end
    end
  end
  travelCache = { key = key, pts, dist, via, firstPt }
  return pts, dist, via, firstPt
end

-- seconds from you to an NPC, and the first boat/zeppelin on the way (or nil)
local function travelTo(tt, pm, px, py, n)
  local best, how, firstIdx = math.huge, nil, nil
  if n[3] == pm then best = walk(px, py, n[4], n[5]) end
  local stops, dist, via, firstPt = tt[1], tt[2], tt[3], tt[4]
  for i, st in ipairs(stops) do
    if st[1] == n[3] and dist[i] < math.huge then
      local c = dist[i] + walk(st[2], st[3], n[4], n[5])
      if c < best then best, how, firstIdx = c, via[i], firstPt and firstPt[i] end
    end
  end
  return best, how, firstIdx
end

-- The first stop on a route, for the arrow: { map, x, y, label } (data world position)
-- or { shortcut = "Hearthstone ..." }; nil when you just walk there.
local function firstStop(tt, idx, how)
  if not idx then return nil end
  if type(idx) == "table" then return { shortcut = idx.shortcut } end
  local p = tt[1][idx]
  local leg = how and how[1] or ""
  local label = p.name and ("Flight master, " .. p.name) or ("Boat/zeppelin: " .. leg:gsub("^boat/zeppelin: ", ""))
  return { map = p[1], x = p[2], y = p[3], label = label }
end

-- The nearest (by travel time) of these NPCs that deals with your faction.
function Core.NearestNPC(ids)
  local letter = myLetter()
  local pm, px, py = playerWorld()
  local tt = pm and { travelTable(pm, px, py) }
  local best, bestD, bestHow, bestFirst
  for _, id in ipairs(ids or {}) do
    local n = Data.npcs and Data.npcs[id]
    if n and (not letter or n[2]:find(letter, 1, true)) then
      local d, how, fi = math.huge, nil, nil
      if tt then d, how, fi = travelTo(tt, pm, px, py, n) end
      if not bestD or d < bestD then best, bestD, bestHow, bestFirst = id, d, how, fi end
    end
  end
  if not best then return nil end
  local loc = Core.NPCLocation(best)
  local copy = {}
  for k, v in pairs(loc) do copy[k] = v end
  copy.id = best
  copy.note = Data.npcNotes and Data.npcNotes[best] -- "inside Uldaman (dungeon)"
  copy.travel = bestD < math.huge and bestD or nil
  copy.via = bestHow
  copy.first = tt and bestHow and firstStop(tt, bestFirst, bestHow) or nil
  return copy
end

function Core.TravelText(loc)
  if not (loc and loc.travel) then return nil end
  local min = math.max(1, math.floor(loc.travel / 60 + 0.5))
  local route = loc.via and #loc.via > 0 and (" (" .. table.concat(loc.via, ", then ") .. ")") or ""
  local hint = next(Core.KnownTaxi()) == nil and " - flight paths not counted yet: open a flight master's map once" or ""
  return ("about %d min away%s%s"):format(min, route, hint)
end

-- Trainers teach recipe tiers (bits: 1 Apprentice, 2 Journeyman, 4 Expert, 8 Artisan);
-- a tier holds its rank-up and its recipes. In Forever a trainer teaches the tier below
-- its own title: Journeyman from an Expert, Expert from an Artisan, Artisan from a Master.
local function trainersTeaching(line, tier)
  local ids, bit = {}, 2 ^ (tier - 1)
  for id, mask in pairs(Data.trainers and Data.trainers[line] or {}) do
    if math.floor(mask / bit) % 2 == 1 then ids[#ids + 1] = id end
  end
  table.sort(ids)
  return ids
end

function Core.NearestTrainer(line, rankStep) -- rankStep: 2 Journeyman, 3 Expert, 4 Artisan
  return Core.NearestNPC(trainersTeaching(line, rankStep))
end

-- Nearest trainer who teaches this recipe: its tier from AllTheThings; for recipes it
-- doesn't list, estimated from the learn level. Returns loc, tierKnown.
function Core.NearestRecipeTrainer(line, spell, learnAt)
  local tier = Data.recipeTier and Data.recipeTier[spell]
  local known = tier ~= nil
  if not tier then
    local L = learnAt or 0
    tier = L >= 225 and 4 or L >= 125 and 3 or L >= 50 and 2 or 1
  end
  local ids = trainersTeaching(line, tier)
  -- estimated tier with no trainer (Cooking trainers only list Journeyman): the highest
  -- tier below that has one, rather than no name at all
  local t = tier
  while not known and #ids == 0 and t > 1 do
    t = t - 1
    ids = trainersTeaching(line, t)
  end
  return Core.NearestNPC(ids), known
end

-- Ranks no trainer teaches. A book (Expert First Aid - Under Wraps): owned, or the
-- nearest vendor of your faction. A quest (Artisan First Aid: "Triage"): the nearest
-- giver of your faction.
function Core.RankBook(line, rankStep)
  local books = Data.rankBooks and Data.rankBooks[line] and Data.rankBooks[line][rankStep]
  for _, item in ipairs(books or {}) do
    local it = Data.items[item]
    local total = Core.Have(item) or 0 -- bags + bank
    local inBags = itemCount(item) -- bags only
    local owned = total > 0
    local loc = not owned and Core.NearestVendor(item) or nil
    if owned or loc then
      return { item = item, name = it and it[1] or ("item " .. item), price = it and it[3], owned = owned, loc = loc,
               where = owned and (inBags > 0 and "in your bags" or "in your bank") or nil }
    end
  end
end

-- Character level a rank needs (Data.rankLevel; crafting and secondary professions),
-- if you're below it: returns needed, yours.
function Core.RankLevelShort(line, rankStep)
  local need = Data.rankLevel and Data.rankLevel[rankStep]
  if not need or Data.professions[line].gather and line ~= 356 then return nil end
  local mine = UnitLevel and UnitLevel("player")
  if mine and mine < need then return need, mine end
end

-- How to get a rank: the trainer you visited, else ATT's book/quest, else the nearest
-- trainer, else a book or quest. One place for both the route and the shopping list.
local RANK_NAME = { [2] = "Journeyman", [3] = "Expert", [4] = "Artisan" }
function Core.RankHow(line, rankStep)
  local rank = RANK_NAME[rankStep]
  local p, n = Core.Place("trainer", line, rank)
  local loc = p or Core.NearestTrainer(line, rankStep)
  local how = not p and Data.rankSource and Data.rankSource[line] and Data.rankSource[line][rankStep]
  local book = (how == "B" or not loc) and Core.RankBook(line, rankStep) or nil
  local quest = not book and (how == "Q" or not loc) and Core.RankQuest(line, rankStep) or nil
  return { place = p, nPlaces = n, loc = loc, book = book, quest = quest }
end

-- A recipe taught by a quest: the nearest giver of your faction, or nil.
function Core.RecipeQuest(spell)
  local quests = Data.recipeQuests and Data.recipeQuests[spell]
  local ids, byGiver = {}, {}
  for _, q in ipairs(quests or {}) do
    for _, g in ipairs(q[4]) do ids[#ids + 1] = g; byGiver[g] = q end
  end
  local loc = Core.NearestNPC(ids)
  local q = loc and byGiver[loc.id]
  if q then return { quest = q[1], title = q[2], skill = q[3], loc = loc } end
end

-- quest recipes with a giver of your faction (no travel maths: for the planner)
local function questsForFaction(recipes)
  local me, ok = myLetter(), {}
  for spell, r in pairs(recipes) do
    if r.src == "q" then
      for _, q in ipairs(Data.recipeQuests and Data.recipeQuests[spell] or {}) do
        for _, g in ipairs(q[4]) do
          local n = Data.npcs and Data.npcs[g]
          if n and (not me or n[2]:find(me, 1, true)) then ok[spell] = true end
        end
      end
    end
  end
  return ok
end

Core.QuestsForFaction = questsForFaction

function Core.RankQuest(line, rankStep)
  local quests = Data.rankQuests and Data.rankQuests[line] and Data.rankQuests[line][rankStep]
  local ids, byGiver = {}, {}
  for _, q in ipairs(quests or {}) do
    for _, g in ipairs(q[4]) do ids[#ids + 1] = g; byGiver[g] = q end
  end
  local loc = Core.NearestNPC(ids)
  local q = loc and byGiver[loc.id]
  if q then return { quest = q[1], title = q[2], skill = q[3], loc = loc } end
end

function Core.NearestVendor(item)
  return Core.NearestNPC(Data.vendorNpcs and Data.vendorNpcs[item])
end

-- "Zone (x, y)"; for an NPC the game couldn't place, its spot on the continent map.
local whereRaw
function Core.Where(loc)
  local w = whereRaw(loc)
  if w and loc.note then w = w .. " - |cffff8040" .. loc.note .. "|r" end
  return w
end
whereRaw = function(loc)
  if not loc then return nil end
  if loc.zone and loc.x then return ("%s (%.1f, %.1f)"):format(loc.zone, loc.x, loc.y) end
  local cont = loc.cui and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(loc.cui)
  if loc.cx then return ("%s map (%.1f, %.1f)"):format(cont and cont.name or "continent", loc.cx, loc.cy) end
  return loc.zone
end

-- NPC ids in the data with this name (cached).
local byName
function Core.NPCsNamed(name)
  if not byName then
    byName = {}
    for id, n in pairs(Data.npcs or {}) do
      byName[n[1]] = byName[n[1]] or {}
      table.insert(byName[n[1]], id)
    end
  end
  return byName[name] or {}
end

-- Waypoint to an NPC: TomTom if installed, else SkillRoute's arrow and the game's map pin.
function Core.Waypoint(loc, title)
  if not loc then return end
  local ui, x, y = loc.ui, loc.x, loc.y
  if not (ui and x) then ui, x, y = loc.cui, loc.cx, loc.cy end
  title = title or loc.npc
  if not (ui and x) then
    print(("SkillRoute: no coordinates known for %s."):format(title or "?"))
    return
  end
  -- TomTom first when it's installed; else SkillRoute's own arrow, plus the game's map
  -- pin (and its on-screen marker where the client has one)
  if TomTom and TomTom.AddWaypoint then
    TomTom:AddWaypoint(ui, x / 100, y / 100, { title = title, persistent = false, minimap = true, world = true })
    print(("SkillRoute: TomTom waypoint set to %s, %s."):format(title, Core.Where(loc) or ""))
    return "tomtom"
  end
  local pinned = false
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates
      and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(ui)) then
    pinned = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(ui, x / 100, y / 100))
    if pinned and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
  end
  -- an NPC you visited has no route worked out yet: find it in the data and work it out
  if not loc.via and not loc.travel and loc.npc then
    local found = Core.NearestNPC(Core.NPCsNamed(loc.npc))
    if found then loc = setmetatable({ via = found.via, travel = found.travel }, { __index = loc }) end
  end
  local via = loc.via and #loc.via > 0 and ("via " .. table.concat(loc.via, ", then ")) or nil
  local ids = loc.id and { loc.id } or (loc.npc and Core.NPCsNamed(loc.npc)) or nil
  local arrow = ns.Arrow and ns.Arrow.Set(ui, x / 100, y / 100, title, Core.Where(loc), via, ids)
  if arrow or pinned then
    print(("SkillRoute: %s to %s, %s."):format(arrow and "arrow pointing" or "map pin set", title, Core.Where(loc) or ""))
    return arrow and "arrow" or "pin"
  end
  print(("SkillRoute: %s is at %s."):format(title, Core.Where(loc) or "?"))
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

-- price and stock of merchant slot i: the old global API, or Forever's modern
-- C_MerchantFrame.GetItemInfo (a table). Either can be missing.
local function merchantInfo(i)
  if GetMerchantItemInfo then
    local _, _, price, _, numAvailable = GetMerchantItemInfo(i)
    return price, numAvailable
  end
  local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo and C_MerchantFrame.GetItemInfo(i)
  if type(info) == "table" then return info.price, info.numAvailable end
end

function Core.ScanMerchant()
  local npc = UnitName and UnitName("npc")
  local count = GetMerchantNumItems or (C_MerchantFrame and C_MerchantFrame.GetNumItems)
  if not npc or not count then return end
  local spot, found = nil, 0
  for i = 1, count() or 0 do
    local id = (GetMerchantItemID and GetMerchantItemID(i))
               or itemIdFromLink(GetMerchantItemLink and GetMerchantItemLink(i))
    if id and isPattern(id) then
      spot = spot or here()
      local price, numAvailable = merchantInfo(i)
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

-- Auctionator's price, and a function giving its age (whole days, 0 = today; nil if it
-- can't tell). The age is a second call, so it's only made when needed.
local function aucQuote(item)
  local api = auctionator()
  if not api then return nil end
  local ok, v = pcall(api.GetAuctionPriceByItemID, CALLER, item)
  local p = ok and v or nil
  if not p then return nil end
  return p, function()
    if not api.GetAuctionAgeByItemID then return nil end
    local ok2, a = pcall(api.GetAuctionAgeByItemID, CALLER, item)
    return ok2 and a or nil
  end
end

-- The freshest AH price: Auctionator's or SkillRoute's own scan, whichever is newer.
-- Returns copper, age in days (nil = unknown), source name. wantAge: always work out
-- the age (otherwise only when two sources have to be compared).
local function ahQuote(item, wantAge)
  local p, age = aucQuote(item)
  if wantAge and age then age = age() end
  if ns.Prices then return ns.Prices.Freshest(item, p, age) end
  if type(age) == "function" then age = nil end
  return p, age, p and "Auctionator" or nil
end

-- Seen on the AH today or yesterday? For one-off listings such as patterns, an old
-- "last seen" price says nothing about whether one is for sale now. When the source
-- can't tell its age we don't block (right-click skip covers it).
local MAX_AH_AGE_DAYS = 1
function Core.AHFresh(item)
  local p, age = ahQuote(item, true)
  return p ~= nil and (age == nil or age <= MAX_AH_AGE_DAYS)
end

-- For tooltips: { ah, age, src, paid, paidDays, cheapest, forN } (any may be nil).
-- cheapest/forN: SkillRoute's scan priced the amount your routes need (ah = average
-- per unit for forN; cheapest = the cheapest listing).
function Core.PriceInfo(item)
  local p, age, src = ahQuote(item, true)
  local paid, days, cheapest, forN
  if ns.Prices then
    paid, days = ns.Prices.LastPaid(item)
    if src == "SkillRoute scan" then
      local minP, d = ns.Prices.Detail(item)
      if d then cheapest, forN = minP, d.n end
    end
  end
  return { ah = p, age = age, src = src, paid = paid, paidDays = days, cheapest = cheapest, forN = forN }
end

-- What all your crafting routes will buy on the AH: { [item] = units }. Stackable
-- materials only (not patterns, tools, books, vendor or farmed items).
function Core.BuyList()
  local c, out = Core.Char(), {}
  for line in pairs(Core.Skills()) do
    local prof = Data.professions[line]
    if prof and not prof.gather then
      local ok, plan = pcall(Core.Plan, line, c.targets[line] or 300)
      if ok and plan and plan.shopping then
        for _, b in ipairs(plan.shopping.buy) do
          if b.buy and b.buy > 0 and not (b.vendor or b.farm or b.pattern or b.tool or b.book) then
            out[b.item] = (out[b.item] or 0) + b.buy
          end
        end
      end
    end
  end
  return out
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

-- Farming ------------------------------------------------------------------------
local FARM_ACTION = 25 -- copper per kill / catch, or your "value of a craft" if higher

-- 0 your faction's land, 1 contested, 2 the other faction's land
local function zoneRank(zone)
  local s = Data.zoneSide and Data.zoneSide[zone]
  if not s then return 1 end
  local me = myLetter()
  return (not me or s == me) and 0 or 2
end
Core.ZoneRank = zoneRank
-- the zone's name, marked "(Alliance)" / "(Horde)" when it's the other faction's
function Core.ZoneName(zone)
  if zoneRank(zone) ~= 2 then return zone end
  return zone .. (Data.zoneSide[zone] == "A" and " (Alliance)" or " (Horde)")
end
local function srcZone(s) return s[1] == "m" and s[3] or s[2] end
local function srcChance(s) return (s[1] == "m" and s[4] or s[3]) or 0 end

-- Sources in the order to show them: your faction's zones, contested, then enemy land;
-- the data's own order (best first) within each. Cached per item (faction is fixed).
local farmOrder = {}
local function farmSources(item)
  local o = farmOrder[item]
  if o then return o end
  local farm = Data.farm and Data.farm[item]
  if not farm then return nil end
  o = {}
  for i, s in ipairs(farm) do o[i] = { s = s, r = zoneRank(srcZone(s)), i = i } end
  table.sort(o, function(a, b) if a.r ~= b.r then return a.r < b.r end return a.i < b.i end)
  for i, x in ipairs(o) do o[i] = x.s end
  if myLetter() then farmOrder[item] = o end -- faction not known yet: don't keep
  return o
end

-- What a farmed item costs in time: kills/catches per item x a small value each. Enemy
-- land counts only when nowhere else has it.
function Core.FarmCost(item)
  local src = farmSources(item)
  if not src then return nil end
  local per = math.max(FARM_ACTION, db().settings.craftValue or 0)
  local best, bestEnemy = math.huge, math.huge
  for _, s in ipairs(src) do
    local c = srcChance(s)
    if c > 0 then
      if zoneRank(srcZone(s)) < 2 then best = math.min(best, 100 / c)
      else bestEnemy = math.min(bestEnemy, 100 / c) end
    end
  end
  if best == math.huge then best = bestEnemy end
  return best < math.huge and best * per or nil
end

-- "Goretusk (lvl 14-15, 29%) in Westfall"; full = every source, one per line.
-- Your faction's zones first; the other faction's are marked.
function Core.FarmText(item, full)
  local src = farmSources(item)
  if not src then return nil end
  local parts = {}
  for _, s in ipairs(src) do
    local z = Core.ZoneName(srcZone(s))
    if s[1] == "m" then
      local lvl = s[5] == s[6] and tostring(s[5]) or (s[5] .. "-" .. s[6])
      parts[#parts + 1] = ("%s (lvl %s, %d%%) in %s"):format(s[2], lvl, math.floor(s[4] + 0.5), z)
    else
      parts[#parts + 1] = ("fish in %s (%d%%%s)"):format(z, math.floor(s[3] + 0.5),
        s[4] and s[4] > 0 and (", fishing " .. (s[4] + 95) .. " to lose none") or "")
    end
    if not full and #parts >= 2 then break end
  end
  return table.concat(parts, full and "\n" or "; or ")
end

-- Where prices come from, for the window's header: nil when there are none.
function Core.PriceSource()
  local own = ns.Prices and (ns.Prices.Book().t or 0) > 0
  local auc = auctionator() ~= nil
  if auc and own then return "Auctionator + SkillRoute scan" end
  return auc and "Auctionator" or own and "SkillRoute scan" or nil
end

-- The auction house price alone (the freshest scan), never a vendor price.
function Core.AHPrice(item)
  return (ahQuote(item))
end

-- Can you buy it from a vendor? A pattern only if a vendor of your faction sells it (or
-- you saw one); other vendor-priced items are sold to both factions (see gen_data).
local function vendorForMe(item)
  local pv = Data.patternVendors and Data.patternVendors[item]
  if not pv then return true end
  local me = myLetter()
  return not me or pv[1]:find(me, 1, true) ~= nil or Core.Place("vendor", item) ~= nil
end

-- Enchanting essences: 3 lesser make 1 greater (combine) and 1 greater splits into 3
-- lesser (right-click), for free. lesser -> greater and greater -> lesser.
local ESSENCE = {}
for _, p in ipairs({ { 10938, 10939 }, { 10998, 11082 }, { 11134, 11135 }, { 11174, 11175 }, { 16202, 16203 } }) do
  ESSENCE[p[1]] = { other = p[2], ratio = 1 / 3 } -- 1 lesser = 1/3 greater
  ESSENCE[p[2]] = { other = p[1], ratio = 3 }     -- 1 greater = 3 lesser
end
local basePrice

-- Price of an item, or of its other essence form when that's cheaper (converted).
function Core.Price(item)
  local p, est, kind = basePrice(item)
  local e = ESSENCE[item]
  if e then
    local op, oest, okind = basePrice(e.other)
    if op and okind ~= "farm" and (not p or op * e.ratio < p) then return op * e.ratio, oest or false end
  end
  return p, est, kind
end

-- For the shopping list: buying the other form is cheaper. Returns other item, how
-- many of it for n, its unit price and "split"/"combine"; nil if this form is fine.
function Core.EssenceSwap(item, n)
  local e = ESSENCE[item]
  if not e then return nil end
  local p = basePrice(item)
  local op = basePrice(e.other)
  if not op or (p and op * e.ratio >= p) then return nil end
  return e.other, math.ceil(n * e.ratio - 1e-9), op, e.ratio < 1 and "split" or "combine"
end

function basePrice(item)
  local api = auctionator()
  local ah, vendor = (ahQuote(item))
  if api and api.GetVendorPriceByItemID then
    local ok, v = pcall(api.GetVendorPriceByItemID, CALLER, item)
    vendor = ok and v or nil
  end
  local it = Data.items[item]
  vendor = vendor or (it and it[3])
  if vendor and not vendorForMe(item) then vendor = nil end -- e.g. an Alliance-only recipe for Horde
  if ah and vendor then return math.min(ah, vendor), false end
  if ah or vendor then return ah or vendor, false end
  -- not on the AH now, but you bought some recently: what you paid
  local paid = ns.Prices and ns.Prices.LastPaid(item)
  if paid then return paid, false end
  -- not on the AH, but farmable (meat, fish): no gold, a small time cost so a rare drop
  -- doesn't look free. Marked "farm": not added to what you spend.
  local farm = Core.FarmCost(item)
  if farm then return farm, false, "farm" end
  if db().settings.estimate and it and it[2] and it[2] > 0 then
    return it[2] * 4, true -- clearly flagged as an estimate in the UI
  end
  return nil
end

local function getCount(item, bank) -- looked up per call (the API can load after us)
  local f = (C_Item and C_Item.GetItemCount) or GetItemCount
  return f and f(item, bank) or 0
end
function Core.Have(item)
  return getCount(item, true) -- bags + bank
end
function Core.InBags(item)
  return getCount(item, false)
end

-- Materials on your other characters (same faction): Syndicator, else DataStore.
-- Counted once per plan (cache reset in Core.Plan); 0 when neither is installed or
-- /sr alts off.
local altCache = {}
function Core.HaveOnAlts(item)
  local settings = db().settings
  if settings.alts == false then return 0 end
  if altCache[item] then return altCache[item] end
  local me, n = UnitName and UnitName("player"), 0
  local S = Syndicator and Syndicator.API
  if S and S.GetInventoryInfoByItemID then
    local ok, info = pcall(S.GetInventoryInfoByItemID, item, true, true)
    for _, c in ipairs(ok and info and info.characters or {}) do
      if c.character ~= me then
        n = n + (c.bags or 0) + (c.bank or 0) + (c.mail or 0)
      end
    end
  elseif DataStore and DataStore.GetCharacters and DataStore.GetContainerItemCount then
    local ok, chars = pcall(DataStore.GetCharacters, DataStore)
    for name, key in pairs(ok and chars or {}) do
      if name ~= me then
        local ok2, bags, bank = pcall(DataStore.GetContainerItemCount, DataStore, key, item)
        if ok2 then n = n + (bags or 0) + (bank or 0) end
      end
    end
  end
  altCache[item] = n
  return n
end

-- A tool only counts in your bags (or equipped), not in the bank.
function Core.HasTool(key)
  local def = Data.tools[key]
  if not def then return false end
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
-- bumped whenever SkillRoute re-plans anyway (prices, bags, recipes): Enchanting's
-- needs for the disenchant advice are recomputed after that
local needsCache, needsVersion = nil, 0
local routeVersion = 0 -- recipes, prices or settings changed (not every bag update)
function Core.InvalidatePatterns() patternCache = {}; needsVersion = needsVersion + 1; routeVersion = routeVersion + 1 end

-- What your routes still use, for item tooltips: { [item] = { {prof, units}, ... } }.
-- Every crafting profession you have: its shopping list's amounts (what you'd buy or
-- already own, with your safety margin), what its steps make for later steps, and tools. Worked out again when recipes, prices or
-- settings change, or after a minute - not on every bag update (tooltips stay quick).
local routeNeeds
function Core.RouteNeeds()
  local now = GetTime and GetTime() or 0
  if routeNeeds and routeNeeds.ver == routeVersion and now - routeNeeds.t < 60 then return routeNeeds.map end
  local map, c = {}, Core.Char()
  for line in pairs(Core.Skills()) do
    local prof = Data.professions[line]
    if prof and not prof.gather then
      local ok, plan = pcall(Core.Plan, line, (c.targets and c.targets[line]) or 300)
      if ok and plan and plan.steps then
        -- the shopping list's own amounts (bolts and bars expanded into what they're made
        -- of, what earlier steps make taken off, the same safety margin), plus tools
        local per = {}
        for _, b in ipairs(plan.shopping and plan.shopping.buy or {}) do
          if b.need and b.need > 0 then per[b.item] = b.need end
        end
        -- what a step makes and a later step uses (bolts) isn't bought: count its use
        local made, use = {}, {}
        for _, st in ipairs(plan.steps) do
          local r = st.spell and prof.recipes[st.spell]
          if r and r.r then
            for i = 1, #r.r, 2 do
              if made[r.r[i]] then use[r.r[i]] = (use[r.r[i]] or 0) + r.r[i + 1] * st.crafts end
            end
            if r.out then made[r.out] = true end
          end
          for _, u in ipairs(st.tools or {}) do per[u.item] = math.max(per[u.item] or 0, 1) end
        end
        for it, n in pairs(use) do per[it] = math.max(per[it] or 0, math.ceil(n - 1e-9)) end
        for item, n in pairs(per) do
          map[item] = map[item] or {}
          table.insert(map[item], { prof.name, n })
        end
      end
    end
  end
  for _, list in pairs(map) do table.sort(list, function(a, b) return a[2] > b[2] end) end
  routeNeeds = { ver = routeVersion, t = now, map = map }
  return map
end

-- Items this profession's recipes use, per profession (fixed data: worked out once).
local usesCache = {}
local function itemsUsedBy(line)
  local u = usesCache[line]
  if u then return u end
  u = {}
  for _, r in pairs(Data.professions[line].recipes) do
    for i = 1, #(r.r or {}), 2 do u[r.r[i]] = true end
  end
  usesCache[line] = u
  return u
end

-- Known recipes of your other professions that make something `line` uses:
-- { [spell] = recipe, n = how many }, { [spell] = their profession }.
function Core.OtherMakers(line)
  local uses, out, from, n = itemsUsedBy(line), {}, {}, 0
  for other in pairs(Core.Skills()) do
    local prof = Data.professions[other]
    if other ~= line and prof and next(prof.recipes) then
      local known
      for spell, r in pairs(prof.recipes) do
        if r.out and r.r and uses[r.out] and not r.cd then
          known = known or knownSet(other)
          if known[spell] or r.src == "a" then out[spell], from[spell], n = r, other, n + 1 end
        end
      end
    end
  end
  out.n = n
  return out, from
end

local MAX_SKILL = 300
function Core.Plan(line, target)
  local s = Core.Skills()[line]
  if not s then -- fall back to the open profession window, if it is this profession
    local liveLine, liveRank, liveMax = openLine()
    if liveLine == line and liveRank then s = { rank = liveRank, max = liveMax } end
  end
  if not s then return nil, "This character doesn't have " .. Data.professions[line].name .. "." end
  -- maxed: nothing to plan (aiming one point above your skill would ask for 301)
  if s.rank >= MAX_SKILL then
    return nil, ("%s is maxed (%d/%d). Nothing left to level."):format(Data.professions[line].name, s.rank, MAX_SKILL), "maxed"
  end
  target = math.max(s.rank + 1, math.min(target or MAX_SKILL, MAX_SKILL))
  if Data.professions[line].gather then -- Mining, Herbalism, Skinning: a zone route
    local t0g = debugprofilestop and debugprofilestop()
    local plan = Planner.GatherPlan({ nodes = Data.gather and Data.gather[line], skinning = line == 393,
      fishing = line == 356 and Data.fishing or nil, zoneRank = zoneRank,
      skinZones = line == 393 and Data.skinZones or nil,
      skill = s.rank, target = target, maxSkill = s.max, bonus = Core.Bonus() })
    plan.ms = t0g and (debugprofilestop() - t0g)
    plan.skill, plan.max, plan.target, plan.line = s.rank, s.max, target, line
    return plan
  end
  local t0 = debugprofilestop and debugprofilestop()
  altCache = {}
  local known, settings = knownSet(line), db().settings
  local nKnown = 0
  for _ in pairs(known) do nKnown = nKnown + 1 end
  local key = table.concat({ s.rank, target, nKnown, Core.dataVersion, Core.Bonus(), settings.craftValue or 0, settings.resale or 0,
                             tostring(settings.estimate), tostring(settings.cdmats) }, ":")
  local recipes = Data.professions[line].recipes
  local owned = {}
  for key in pairs(Core.ToolsFor(line)) do if Core.HasTool(key) then owned[#owned + 1] = key end end
  table.sort(owned)
  key = key .. ":" .. table.concat(owned, ",")
  -- patterns you already have for recipes you don't know: bags, bank, or an alt (if
  -- alts are counted). Part of the cache key, so picking one up re-plans.
  local ownedPatterns, ownedList = {}, {}
  for spell, r in pairs(recipes) do
    if r.pat and not known[spell] then
      for _, it in ipairs(r.pat) do
        if ownedPatterns[it] == nil then
          local w = getCount(it) > 0 and "in your bags" or Core.Have(it) > 0 and "in your bank"
                    or Core.HaveOnAlts(it) > 0 and "on an alt" or false
          ownedPatterns[it] = w
          if w then ownedList[#ownedList + 1] = it end
        end
      end
    end
  end
  for it, w in pairs(ownedPatterns) do if not w then ownedPatterns[it] = nil end end
  table.sort(ownedList)
  key = key .. ":" .. table.concat(ownedList, ",")
  for _, f in ipairs(Core.FactionsFor(line)) do key = key .. ":" .. f .. "=" .. tostring(Core.Standing(f)) end
  -- specialisations you have (they unlock recipes): part of the cache key
  local isKnown = IsPlayerSpell or IsSpellKnown
  for id in pairs(Data.specNames or {}) do if isKnown and isKnown(id) then key = key .. ":spec" .. id end end
  -- your other professions' known recipes that make something this one uses (a miner's
  -- bars for Blacksmithing, a tailor's bolts...): make it instead of buying when cheaper
  local otherRecipes, otherLine = Core.OtherMakers(line)
  key = key .. ":other" .. otherRecipes.n
  otherRecipes.n = nil
  local cached = patternCache[line]
  local plan = Planner.Plan({
    otherRecipes = otherRecipes, otherLine = otherLine,
    recipes = recipes, items = Data.items, tools = Data.tools,
    skill = s.rank, target = target, maxSkill = s.max,
    known = known, trainer = db().trainer[line] or {},
    price = Core.Price, have = Core.Have, haveAlts = Core.HaveOnAlts, hasTool = Core.HasTool, standing = Core.Standing,
    avoidMats = not settings.cdmats and Data.cooldownMats or nil,
    z = Core.MarginZ(settings.margin),
    craftValue = settings.craftValue or 0,
    resale = (settings.resale or 0) / 100,
    faction = (UnitFactionGroup and UnitFactionGroup("player") == "Alliance") and "A"
              or (UnitFactionGroup and UnitFactionGroup("player") == "Horde") and "H" or nil,
    patternVendors = Data.patternVendors,
    vendorSeen = function(item) return Core.Place("vendor", item) ~= nil end,
    bonus = Core.Bonus(),
    fixedUnlocks = cached and cached.key == key and cached.set or nil,
    skip = Core.Skips(line), ahFresh = Core.AHFresh, ownedPatterns = ownedPatterns,
    questOK = questsForFaction(recipes), ahPrice = Core.AHPrice,
    hasSpec = function(id) local k = IsPlayerSpell or IsSpellKnown; return k and k(id) or false end,
  })
  if not (cached and cached.key == key) then
    local set = {}
    for k in pairs(plan.unlocks or {}) do set[k] = true end
    patternCache[line] = { key = key, set = set }
  end
  -- rank books to buy (Expert Cookbook): on the shopping list and in "Buy for", like patterns
  for cap = s.max, target - 1, 75 do
    local stepN = ({ [75] = 2, [150] = 3, [225] = 4 })[cap]
    local b = stepN and Core.RankHow(line, stepN).book
    if b and not b.owned and b.price then
      table.insert(plan.shopping.buy, 1, { item = b.item, name = b.name, need = 1, expected = 1, have = 0, buy = 1,
        price = b.price, vendor = true, book = true })
      plan.total = plan.total + b.price
    end
  end
  plan.ms = t0 and (debugprofilestop() - t0)
  plan.skill, plan.max, plan.target, plan.line = s.rank, s.max, target, line
  plan.mismatch = Core.mismatch[line]
  return plan
end

-- Open a known recipe in the profession window. Returns true if the client could.
function Core.IsRecipeKnown(line, spell)
  local saved = Core.Char().known[line]
  if saved and saved[spell] ~= nil then return saved[spell] end
  local isKnown = IsPlayerSpell or IsSpellKnown
  return isKnown and isKnown(spell) or false
end

function Core.OpenRecipe(spell)
  local T = C_TradeSkillUI
  if T and T.OpenRecipe then
    local ok = pcall(T.OpenRecipe, spell)
    if ok then return true end
  end
  if T and T.SetSelectedRecipeID then
    local ok = pcall(T.SetSelectedRecipeID, spell)
    if ok then return true end
  end
  return false
end

-- Craft a known recipe n times (from a click: the game needs one). Returns true if the
-- client took it.
function Core.Craft(spell, n)
  local T = C_TradeSkillUI
  if not (T and T.CraftRecipe) then return false end
  return (pcall(T.CraftRecipe, spell, n or 1))
end

-- How many crafts the materials in your bags (not the bank) allow.
function Core.CraftableNow(line, spell)
  local r = Data.professions[line].recipes[spell]
  if not (r and r.r) then return 0 end
  local n = math.huge
  for i = 1, #r.r, 2 do
    local have = Core.InBags(r.r[i])
    n = math.min(n, math.floor(have / r.r[i + 1]))
  end
  return n == math.huge and 0 or n
end

-- Send the shopping list to Auctionator as a shopping list (exact names, amounts).
-- Vendor items (thread, dyes, vendor patterns/tools) are left out: not on the AH.
-- One route step's reagents for the auction house: reagents per craft x the crafts the
-- step needs (with your safety margin), intermediates the route crafts (bolts) opened
-- up into what they're made of, minus what you have (bags, bank, alts). Vendor-only
-- items left out, as in the full export. Returns { {item, name, qty}, ... }.
function Core.StepShopping(plan, st)
  local recipes = Data.professions[plan.line].recipes
  local r = st.spell and recipes[st.spell]
  if not (r and r.r) then return {} end
  local z = Core.MarginZ(db().settings.margin)
  local crafts = st.crafts + z * math.sqrt(st.var or 0)
  local made = {} -- items this route crafts itself -> recipe
  for _, c in ipairs(plan.shopping.craft or {}) do
    local cr = recipes[c.spell] or (c.line and Data.professions[c.line].recipes[c.spell])
    if cr and cr.out then made[cr.out] = cr end
  end
  local want, ownedLeft = {}, {}
  local function add(item, n, depth)
    local mr = made[item]
    if mr and depth < 2 then
      -- bars or bolts you already have go first; only the rest is made from raw materials
      if ownedLeft[item] == nil then ownedLeft[item] = (Core.Have(item) or 0) + (Core.HaveOnAlts(item) or 0) end
      local use = math.min(n, ownedLeft[item])
      ownedLeft[item] = ownedLeft[item] - use
      n = n - use
      if n <= 1e-9 then return end
      local times = math.ceil(n / (mr.outN or 1) - 1e-9)
      for i = 1, #mr.r, 2 do add(mr.r[i], mr.r[i + 1] * times, depth + 1) end
    else
      want[item] = (want[item] or 0) + n
    end
  end
  for i = 1, #r.r, 2 do add(r.r[i], r.r[i + 1] * crafts, 0) end
  local out = {}
  for item, n in pairs(want) do
    local it = Data.items[item]
    local ah = Core.Price(item)
    local vendorOnly = it and it[3] and (not ah or it[3] <= ah)
    local qty = math.ceil(n - 1e-9) - (Core.Have(item) or 0) - (Core.HaveOnAlts(item) or 0)
    if qty > 0 and not vendorOnly then
      out[#out + 1] = { item = item, name = (GetItemInfo and GetItemInfo(item)) or (it and it[1]) or ("item " .. item), qty = qty }
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- Add (or update) one step in the "SkillRoute <profession> (steps)" Auctionator list.
-- The steps you added are remembered, and the list is rebuilt from them, so clicking a
-- step twice updates it instead of doubling it. remove = take the step back out.
function Core.AddStepToAuctionator(plan, st, remove)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (api and api.CreateShoppingList) then
    print("SkillRoute: your Auctionator version can't create shopping lists.")
    return false
  end
  local c = Core.Char()
  c.ahSteps = c.ahSteps or {}
  c.ahSteps[plan.line] = c.ahSteps[plan.line] or {}
  local steps = c.ahSteps[plan.line]
  local key = st.spell .. ":" .. st.from
  if remove then
    steps[key] = nil
  else
    local items = Core.StepShopping(plan, st)
    if #items == 0 then
      print(("SkillRoute: nothing to buy on the auction house for %s (you have it, or it's from a vendor)."):format(st.name))
      steps[key] = nil
    else
      steps[key] = { name = st.name, items = items }
    end
  end
  -- the list: every remembered step, quantities summed per item
  local total, order = {}, {}
  for _, s in pairs(steps) do
    for _, x in ipairs(s.items) do
      if not total[x.name] then order[#order + 1] = x.name end
      total[x.name] = (total[x.name] or 0) + x.qty
    end
  end
  table.sort(order)
  local terms = {}
  for _, name in ipairs(order) do
    local term
    if api.ConvertToSearchString then
      local ok, s = pcall(api.ConvertToSearchString, addonName, { searchString = name, isExact = true, quantity = total[name] })
      term = ok and s or nil
    end
    terms[#terms + 1] = term or ('"' .. name .. '"')
  end
  local listName = "SkillRoute " .. Data.professions[plan.line].name .. " (steps)"
  if api.DeleteShoppingList then pcall(api.DeleteShoppingList, addonName, listName) end
  if #terms == 0 then
    print(("SkillRoute: Auctionator list \"%s\" is empty now."):format(listName))
    return true
  end
  local ok, err = pcall(api.CreateShoppingList, addonName, listName, terms)
  if not ok then Core.ReportError("Auctionator step list", err); return false end
  local here = steps[key]
  -- open Auctionator's Shopping tab on this step's reagents (its public search; the
  -- quantities are on the list). Only with the AH open.
  -- MultiSearchAdvanced takes full search terms, quantity included, so Auctionator's buy
  -- pane starts at the amount you need; MultiSearchExact (names only) is the fallback.
  local searched, withQty = false, false
  if here and Core.ahOpen then
    if api.MultiSearchAdvanced then
      local adv = {}
      for _, x in ipairs(here.items) do adv[#adv + 1] = { searchString = x.name, isExact = true, quantity = x.qty } end
      searched = pcall(api.MultiSearchAdvanced, addonName, adv)
      withQty = searched
    end
    local search = api.MultiSearchExact or api.MultiSearch
    if not searched and search then
      local names = {}
      for _, x in ipairs(here.items) do names[#names + 1] = x.name end
      searched = pcall(search, addonName, names)
    end
  end
  print(("SkillRoute: %s %s - Auctionator list \"%s\" now has %d item(s)%s.%s"):format(
    remove and "removed" or "added", st.name, listName, #terms,
    here and (": " .. table.concat((function() local t = {} for _, x in ipairs(here.items) do t[#t + 1] = x.qty .. " " .. x.name end return t end)(), ", ")) or "",
    searched and (withQty and " Searching them in Auctionator's Shopping tab, with the amounts."
      or (" Searching them in Auctionator's Shopping tab (amounts are on the \"%s\" list)."):format(listName)) or ""))
  return true
end

-- What to do with a crafted item: list it on the AH (fresh price, minus the 5% cut),
-- disenchant it (enchanters with the skill; results at fresh AH prices minus the cut)
-- or sell it to a vendor. Only fresh AH prices count: no stale guesses. Returns
-- { ah, de, vendor, best, deSkill, deLoot } (copper per item; nil = not known).
local function freshAH(item)
  local v = Core.AHPrice(item)
  if v and v > 0 and Core.AHFresh(item) then return v end
end
-- What your Enchanting route still has to buy: { [item] = units }. One Enchanting plan
-- (to your Enchanting target) per change of prices, bags or recipes, not per tooltip.
function Core.EnchantingNeeds()
  if not Core.Skills()[333] then return nil end
  if needsCache and needsCache.version == needsVersion then return needsCache.needs end
  local c = Core.Char()
  local ok, plan = pcall(Core.Plan, 333, (c.targets and c.targets[333]) or 300)
  local needs = {}
  if ok and plan and plan.shopping then
    for _, b in ipairs(plan.shopping.buy) do
      if b.buy and b.buy > 0 and not b.farm then needs[b.item] = (needs[b.item] or 0) + b.buy end
    end
  end
  needsCache = { version = needsVersion, needs = needs }
  return needs
end

-- n = how many of the item (the batch: results add up), needs = Core.EnchantingNeeds():
-- disenchant results your Enchanting route still has to buy count at what you'd pay for
-- them (no AH cut), up to the amount it needs; the rest at their AH price minus the cut.
-- What any item disenchants into: loot key and Enchanting skill needed, or nil. Crafted
-- items from the data; anything else by quality and item level in Forever's brackets
-- (weapons and armour, uncommon to epic). Second result "unverified": a new Forever
-- rare no bracket covers (no guess is made).
-- Forever has no Enchanting skill requirement for disenchanting (its table says 0, and
-- checked in game: an item level 55 green disenchanted at skill 170). Having Enchanting
-- is all it takes.
local NO_SKILL = 1
local deCache = {}
function Core.DisenchantOf(item)
  local D = Data.disenchant
  if not (D and item) then return nil end
  if D.never and D.never[item] then return nil end
  local of = D.of and D.of[item]
  if of then return of[1], NO_SKILL end
  if deCache[item] ~= nil then return deCache[item][1], deCache[item][2], deCache[item][3] end
  local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not info then return nil end
  local _, _, q, ilvl, _, _, _, _, _, _, _, cls, sub = info(item)
  if not q then return nil end -- not loaded yet: ask again next time
  local key
  if (cls == 2 or cls == 4) and q >= 2 and q <= 4 then
    for _, r in ipairs(D.rows or {}) do
      if r[1] == cls and r[3] == q and r[4] <= ilvl and ilvl <= r[5] and (r[2] == -1 or r[2] == sub) then
        if not key or r[2] ~= -1 then key = r[6] end -- an exact subclass beats "any"
      end
    end
  end
  local skill = key and NO_SKILL or nil
  local unverified = not key and (cls == 2 or cls == 4) and q == 3 and item >= 200000 or nil
  deCache[item] = { key, skill, unverified }
  return key, skill, unverified
end

local CROWDED_MIN, CROWDED_TIMES, CROWDED_SHARE = 20, 3, 0.7
function Core.ItemAdvice(item, enchantSkill, n, needs, opts)
  n = math.max(1, n or 1)
  local it = Data.items[item]
  local a = { vendor = (it and it[2]) or (opts and opts.vendor) or 0, bound = opts and opts.bound or nil }
  local p = not (opts and opts.bound) and freshAH(item) or nil -- soulbound: no AH
  if p then a.ah = math.floor(p * 0.95) end
  -- how many are already listed (SkillRoute's scan): a crowded market means undercutting
  -- and unsold items, so the AH counts for less when choosing (shown at its real price)
  a.listed = ns.Prices and ns.Prices.Listed(item) or nil
  a.crowded = a.ah and a.listed and a.listed >= math.max(CROWDED_MIN, CROWDED_TIMES * n) or nil
  local dKey, dSkill = Core.DisenchantOf(item)
  if dKey then
    a.deSkill = dSkill
    local loot = Data.disenchant.loot[dKey]
    if loot and enchantSkill and enchantSkill >= (dSkill or 0) then
      local ev, ok, used = 0, true, nil
      for i = 1, #loot, 4 do
        local mat = loot[i]
        local mp = freshAH(mat)
        if not mp then ok = false; break end
        local total = n * loot[i + 1] / 100 * (loot[i + 2] + loot[i + 3]) / 2 -- expected units from the batch
        local need = needs and needs[mat] or 0
        local own = math.min(total, need)
        local buyPrice = math.min(mp, (Data.items[mat] and Data.items[mat][3]) or mp)
        ev = ev + own * buyPrice + (total - own) * mp * 0.95
        if own > 0 then -- named in the tooltips whenever it changed the value
          used = used or {}
          used[#used + 1] = { item = mat, units = math.floor(own + 0.5) }
        end
      end
      if ok then a.de, a.deLoot, a.deUsed = math.floor(ev / n), loot, used end
    end
  end
  local best, bestV = "vendor", a.vendor
  if a.de and a.de > bestV then best, bestV = "de", a.de end
  local ahV = a.ah and (a.crowded and a.ah * CROWDED_SHARE or a.ah)
  if ahV and ahV > bestV then best, bestV = "ah", ahV end
  a.best, a.bestValue = best, best == "ah" and a.ah or bestV
  return a
end

-- Crafted items in your bags (anything a recipe makes), minus what the route still
-- uses as reagents, with advice. Empty without fresh AH prices (vendor-only advice
-- isn't worth a list). { {item, count, advice}, ... }, most valuable first.
local craftedItems
function Core.CraftedAdvice(plan)
  if not Core.PriceSource() then return {} end -- no AH prices at all (no scan, no Auctionator)
  if not craftedItems then
    craftedItems = {}
    for _, prof in pairs(Data.professions) do
      for _, r in pairs(prof.recipes) do if r.out then craftedItems[r.out] = true end end
    end
  end
  local keep = {} -- reagents this route still needs
  for _, b in ipairs(plan and plan.shopping and plan.shopping.buy or {}) do keep[b.item] = true end
  for _, st in ipairs(plan and plan.steps or {}) do
    local r = st.spell and Data.professions[plan.line].recipes[st.spell]
    for i = 1, #(r and r.r or {}), 2 do keep[r.r[i]] = true end
  end
  local counts = {}
  local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local itemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
  if not (numSlots and itemID) then return {} end
  for bag = 0, 4 do
    for slot = 1, numSlots(bag) or 0 do
      local id = itemID(bag, slot)
      if id and craftedItems[id] and not keep[id] then counts[id] = true end
    end
  end
  local ench = Core.Skills()[333]
  local needs = {}
  for k, v in pairs(ench and Core.EnchantingNeeds() or {}) do needs[k] = v end
  local out = {}
  for id in pairs(counts) do
    local n = itemCount(id)
    local a = Core.ItemAdvice(id, ench and ench.rank, n, needs)
    if a.best == "de" then -- these results go to Enchanting: later items can't count them again
      for _, u in ipairs(a.deUsed or {}) do needs[u.item] = math.max(0, (needs[u.item] or 0) - u.units) end
    end
    if a.ah or a.de then out[#out + 1] = { item = id, count = n, advice = a } end
  end
  table.sort(out, function(x, y) return x.advice.bestValue * x.count > y.advice.bestValue * y.count end)
  return out
end

-- Auction house open? (AUCTION_HOUSE_SHOW / CLOSED): the step buttons show only then
Core.ahOpen = false

function Core.CanExportToAuctionator()
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  return api and api.CreateShoppingList and true or false
end

-- Buy buttons: Auctionator's shopping list when it's installed (always first); without
-- it, the auction house's own search, one material per click.
-- Everything the shopping list buys on the AH (not vendor or farmed items), for the
-- buying panel: { {item, name, qty, expect}, ... }.
function Core.ShoppingToBuy(plan)
  local out = {}
  for _, b in ipairs(plan and plan.shopping and plan.shopping.buy or {}) do
    if b.buy and b.buy > 0 and not b.farm and not (b.vendor and not b.ah) then
      out[#out + 1] = { item = b.item, name = b.name, qty = b.buy, expect = b.price }
    end
  end
  return out
end

function Core.CanSearchAH()
  local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
  return (bar and bar.SetSearchText and bar.StartSearch) and true
    or (C_AuctionHouse and C_AuctionHouse.SendBrowseQuery) and true or false
end
function Core.CanBuyHere()
  return Core.ahOpen and (Core.CanExportToAuctionator() or Core.CanSearchAH()) or false
end

-- Search the auction house window for one item, as if typed in its search box.
function Core.SearchAH(name)
  local f = AuctionHouseFrame
  if f and f.SetDisplayMode and AuctionHouseFrameDisplayMode and AuctionHouseFrameDisplayMode.Buy then
    pcall(f.SetDisplayMode, f, AuctionHouseFrameDisplayMode.Buy) -- the Buy tab, not Sell
  end
  local bar = f and f.SearchBar
  if bar and bar.SetSearchText and bar.StartSearch then
    bar:SetSearchText(name)
    bar:StartSearch()
    return true
  end
  if C_AuctionHouse and C_AuctionHouse.SendBrowseQuery then
    return (pcall(C_AuctionHouse.SendBrowseQuery, { searchString = name, sorts = {}, filters = {}, itemClassFilters = {} }))
  end
  return false
end

local searchQ -- { key, items, i }: the step being searched without Auctionator
-- Buy for one step. Returns the label the button should show next ("Buy" or "Next 2/3").
function Core.BuyStep(plan, st, remove)
  if Core.CanExportToAuctionator() then
    Core.AddStepToAuctionator(plan, st, remove)
    return "Buy"
  end
  if remove then searchQ = nil; return "Buy" end
  -- no Auctionator: SkillRoute's own buying panel (price, then buy), else the AH search
  if ns.BuyPanel and ns.BuyPanel.CanUse() then
    local list = Core.StepShopping(plan, st)
    if #list == 0 then
      print("|cff33ccffSkillRoute:|r nothing to buy on the auction house for this step (vendor items aside).")
      return "Buy"
    end
    for _, x in ipairs(list) do x.expect = Core.AHPrice(x.item) end -- an AH price, not a farming time
    ns.BuyPanel.Open(list, "Buy for: " .. (st.name or "this step"))
    return "Buy"
  end
  local key = (st.spell or 0) .. ":" .. (st.from or 0)
  if not (searchQ and searchQ.key == key and searchQ.i < #searchQ.items) then
    searchQ = { key = key, items = Core.StepShopping(plan, st), i = 0 }
  end
  local n = #searchQ.items
  if n == 0 then
    searchQ = nil
    print("|cff33ccffSkillRoute:|r nothing to buy on the auction house for this step (vendor items aside).")
    return "Buy"
  end
  searchQ.i = searchQ.i + 1
  local x = searchQ.items[searchQ.i]
  Core.SearchAH(x.name)
  print(("|cff33ccffSkillRoute:|r searching the auction house for %s: you need %d.%s"):format(x.name, x.qty,
    n > 1 and (" (%d of %d: click Buy again for the next)"):format(searchQ.i, n) or ""))
  if searchQ.i < n then return ("Next %d/%d"):format(searchQ.i + 1, n) end
  searchQ = nil
  return "Buy"
end

function Core.ExportToAuctionator(plan)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (api and api.CreateShoppingList) then
    print("SkillRoute: your Auctionator version can't create shopping lists.")
    return false
  end
  local terms, n = {}, 0
  for _, b in ipairs(plan.shopping.buy) do
    if b.buy > 0 and not (b.vendor and not b.ah) then
      local name = (GetItemInfo and GetItemInfo(b.item)) or b.name
      local term
      if api.ConvertToSearchString then
        local ok, s = pcall(api.ConvertToSearchString, addonName, { searchString = name, isExact = true, quantity = b.buy })
        term = ok and s or nil
      end
      terms[#terms + 1] = term or ('"' .. name .. '"')
      n = n + 1
    end
  end
  if n == 0 then
    print("SkillRoute: nothing to buy on the auction house.")
    return false
  end
  local listName = "SkillRoute " .. Data.professions[plan.line].name
  local ok, err = pcall(api.CreateShoppingList, addonName, listName, terms)
  if ok then
    print(("SkillRoute: Auctionator shopping list \"%s\" created with %d items (vendor items left out)."):format(listName, n))
  else
    Core.ReportError("Auctionator shopping list", err)
  end
  return ok
end

-- Safety margin: confidence (%) that the shopping list covers the whole route ->
-- standard deviations (Abramowitz & Stegun 26.2.23, error < 0.0005).
function Core.MarginZ(conf)
  conf = conf or 90
  if conf <= 50 then return 0 end
  local p = 1 - math.min(conf, 99.9) / 100
  local t = math.sqrt(-2 * math.log(p))
  return t - (2.515517 + 0.802853 * t + 0.010328 * t * t) / (1 + 1.432788 * t + 0.189269 * t * t + 0.001308 * t ^ 3)
end

-- Change notification: coalesce bursts of events into one re-plan.
local pending = false
function Core.Changed()
  needsVersion = needsVersion + 1 -- prices, bags or recipes changed: re-plan Enchanting's needs
  local mini = ns.Mini and ns.Mini.IsShown()
  if pending or not ((ns.UI and ns.UI.IsShown()) or mini) then return end
  pending = true
  C_Timer.After(0.1, function()
    pending = false
    if ns.UI.IsShown() then ns.UI.Refresh() end
    if ns.Mini and ns.Mini.IsShown() then ns.Mini.Refresh() end
  end)
end

-- Events -------------------------------------------------------------------------
local f = CreateFrame("Frame")
local function onEvent(_, ev, arg1)
  if ev == "ADDON_LOADED" and arg1 == addonName then
    db()
    -- an error saved by an older version is about code that's gone: drop it
    if SkillRouteDB.lastError and SkillRouteDB.lastErrorVersion ~= Core.Version() then
      SkillRouteDB.lastError, SkillRouteDB.lastErrorVersion, SkillRouteDB.lastErrorTime = nil, nil, nil
    end
  elseif ev == "PLAYER_LOGIN" then
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if api and api.RegisterForDBUpdate then
      pcall(api.RegisterForDBUpdate, CALLER, function()
        if ns.Prices then ns.Prices.NoteAuctionatorUpdate() end
        Core.InvalidatePatterns(); Core.Changed()
      end)
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
  elseif ev == "AUCTION_HOUSE_SHOW" or ev == "AUCTION_HOUSE_CLOSED" then
    Core.ahOpen = ev == "AUCTION_HOUSE_SHOW"
    if ns.UI and ns.UI.IsShown() then ns.UI.Refresh() end
    if ns.Mini and ns.Mini.IsShown() then ns.Mini.Refresh() end
  elseif ev == "HEARTHSTONE_BOUND" then
    Core.RecordBind()
  elseif ev == "TAXIMAP_OPENED" then
    Core.RecordTaxi()
  elseif ev == "MERCHANT_SHOW" then
    Core.ScanMerchant()
  elseif ev == "TRAINER_SHOW" or ev == "TRAINER_UPDATE" then
    Core.ScanTrainer()
  else -- skill or bag change
    Core.Changed()
  end
end
f:SetScript("OnEvent", function(self, ev, ...)
  local ok, err = pcall(onEvent, self, ev, ...)
  if not ok then Core.ReportError(ev, err) end
end)
for _, ev in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE",
                      "NEW_RECIPE_LEARNED", "TRAINER_SHOW", "TRAINER_UPDATE", "SKILL_LINES_CHANGED", "MERCHANT_SHOW",
                      "BAG_UPDATE_DELAYED", "UPDATE_FACTION", "TRADE_SKILL_CLOSE", "TAXIMAP_OPENED",
                      "HEARTHSTONE_BOUND", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }) do
  pcall(f.RegisterEvent, f, ev) -- an event this client lacks must not break the addon
end
