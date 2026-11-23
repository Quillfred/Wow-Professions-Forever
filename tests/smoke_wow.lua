-- Loads the whole addon against a fake WoW API and drives the main paths, to catch
-- nil/typo errors outside the game. Run from the repo root: lua5.1 tests/smoke_wow.lua
local texts = {}
local function stubObj()
  local o = { shown = false, text = "" }
  return setmetatable(o, { __index = function(t, k)
    if k == "IsShown" then return function(self) return self.shown end end
    if k == "Show" then return function(self) self.shown = true; if self.onShow then self.onShow(self) end end end
    if k == "Hide" then return function(self) self.shown = false; if self.OnHide then self.OnHide(self) end end end
    if k == "SetText" then return function(self, v) self.text = v end end
    if k == "GetText" then return function(self) return self.text end end
    if k == "RegisterForClicks" then return function() end end
    if k == "SetScript" then return function(self, n, f) if n == "OnShow" then self.onShow = f end; self[n] = f end end
    if k == "RegisterEvent" then return function(self, ev) local e = rawget(self, "events") or {}; rawset(self, "events", e); e[ev] = true end end
    if k == "CreateTexture" then return function() return stubObj() end end
    if k == "CreateFontString" then return function() local o = stubObj(); texts[#texts + 1] = o; return o end end
    return function() end
  end })
end
local frames = {}
_G.CreateFrame = function() local f = stubObj(); frames[#frames + 1] = f; return f end
_G.UIParent, _G.UISpecialFrames, _G.SlashCmdList = stubObj(), {}, {}
_G.tinsert = table.insert
_G.GameTooltip = stubObj()
_G.C_Timer = { After = function(_, f) f() end }
local npcName = "Hgarth"
_G.UnitName = function(u) if u == "npc" then return npcName end return "Tester" end
_G.UnitFactionGroup = function() return "Horde" end
_G.GetRealZoneText = function() return "Stonetalon Mountains" end
_G.GetSubZoneText = function() return "Sun Rock Retreat" end
_G.time = os.time
_G.C_Map = { GetBestMapForUnit = function() return 1442 end,
             GetPlayerMapPosition = function() return { GetXY = function() return 0.4723, 0.6181 end } end }
_G.GetRealmName = function() return "Forever" end
_G.debugprofilestop = function() return os.clock() * 1000 end
_G.GetProfessions = function() return 1, 2 end
_G.GetProfessionInfo = function(i)
  if i == 1 then return "Tailoring", 0, 110, 150, 0, 0, 197 end
  return "Herbalism", 0, 80, 150, 0, 0, 182
end
_G.IsPlayerSpell = function(id) return id == 3848 end
_G.GetItemCount = function(id) return id == 2592 and 40 or 0 end
_G.GetItemInfo = function() return nil end
_G.GetFactionInfoByID = function(f) if f == 609 then return "Cenarion Circle", "", 5 end end
local prices = {}
_G.Auctionator = { API = { v1 = {
  GetAuctionPriceByItemID = function(_, id) return prices[id] end,
  RegisterForDBUpdate = function() end } } }
-- trainer window with two services
_G.GetNumTrainerServices = function() return 3 end
_G.GetTrainerServiceInfo = function(i)
  if i == 3 then return "Tailoring", "Expert" end -- the rank-up service
  return i == 1 and "Earthen Vest" or "Robe of Power"
end
_G.GetTrainerServiceSkillReq = function(i) return "Tailoring", (i == 1 and 145) or (i == 2 and 160) or 125, true end
_G.GetTrainerServiceCost = function() return 1500 end
_G.GetTrainerServiceItemLink = function(i) return i == 1 and "|Hitem:7051::|h" or nil end
-- open profession window (modern API)
_G.C_TradeSkillUI = {
  GetBaseProfessionInfo = function() return { professionID = 197, skillLevel = 110, maxSkillLevel = 150 } end,
  GetAllRecipeIDs = function() return { 2963, 3848, 999999 } end,
  GetRecipeInfo = function(id) return { learned = true, relativeDifficulty = (id == 3848) and 1 or 3 } end,
}
_G.TradeSkillFrame = stubObj()

local ns = {}
_G.Minimap = setmetatable({ GetWidth = function() return 140 end, GetCenter = function() return 1000, 700 end,
  GetEffectiveScale = function() return 1 end }, { __index = function() return function() end end })
_G.GetCursorPosition = function() return 1000, 800 end -- straight above the minimap
for _, f in ipairs({ "Data", "Planner", "Core", "UI", "Options", "Check" }) do
  local chunk = assert(loadfile("SkillRoute/" .. f .. ".lua"))
  chunk("SkillRoute", ns)
end
-- fire events the way the client would
local evFrame -- Core created exactly one event frame; reach its handler via the stub
local Core, UI = ns.Core, ns.UI
SkillRouteDB = nil
Core.Char()
Core.ScanTrainer()
assert(SkillRouteDB.trainer[197][8764].req == 145, "Earthen Vest matched by created item -> classic version")
assert(SkillRouteDB.trainer[197][8764].cost == 1500)
local tr = SkillRouteDB.places.trainers[197].Hgarth
assert(tr and tr.ranks.Expert and tr.zone == "Stonetalon Mountains" and tr.x == 47.2 and tr.y == 61.8 and tr.faction == "Horde",
  "trainer name, rank, zone and coordinates recorded")
-- a vendor selling a pattern
local patItem = SkillRouteData.professions[197].recipes[1257487].pat[1] -- Runecloth Cuffs
npcName = "Kania"
_G.GetMerchantNumItems = function() return 1 end
_G.GetMerchantItemID = function() return patItem end
_G.GetMerchantItemInfo = function() return "Pattern", nil, 100000, 1, -1 end
Core.ScanMerchant()
local vp = Core.Place("vendor", patItem)
assert(vp and vp.npc == "Kania" and vp.price == 100000 and not vp.limited, "pattern vendor recorded")
assert(Core.FormatPlace(vp, true) == "Kania, Stonetalon Mountains, Sun Rock Retreat (47.2, 61.8)", Core.FormatPlace(vp, true))
UnitFactionGroup = function() return "Alliance" end
assert(not Core.Place("vendor", patItem), "other faction's vendor not suggested")
UnitFactionGroup = function() return "Horde" end
npcName = "Hgarth"
Core.ScanRecipes()
assert(Core.Char().known[197][3848], "learned recipe recorded")
assert(Core.mismatch[197] == 0, "live colours match data at 110: got " .. tostring(Core.mismatch[197]))

-- no prices at all: plan must not invent any
local plan = Core.Plan(197, 300)
assert(plan.total == 0 and plan.unpriced > 0, "unpriced recipes skipped")
-- prices for everything (3x vendor sell)
for id, it in pairs(SkillRouteData.items) do prices[id] = math.max(1, it[2]) * 3 end
plan = Core.Plan(197, 300)
assert(plan.skill == 110 and plan.unpriced == 0 and #plan.steps > 0)
local usedTrainer
for _, st in ipairs(plan.steps) do if st.spell == 8764 then usedTrainer = st end end
assert(not usedTrainer or (usedTrainer.from >= 145 and usedTrainer.learn == "trainer"), "scanned trainer level used")
print(("plan 110->300: %d steps, buy %d items, %.1f ms"):format(#plan.steps, #plan.shopping.buy, plan.ms))
local again = Core.Plan(197, 300) -- same inputs: cached pattern choice
assert(math.abs(again.total - plan.total) < 1, "cached pattern choice reproduces the plan")
print(("re-plan with cached patterns: %.1f ms"):format(again.ms))
Core.InvalidatePatterns()

-- UI: open, both modes, cycle, slash commands
SlashCmdList.SKILLROUTE("")
assert(UI.IsShown())
SlashCmdList.SKILLROUTE("overtime 10"); assert(SkillRouteDB.settings.bonus == 0.1)
SlashCmdList.SKILLROUTE("estimate on"); assert(SkillRouteDB.settings.estimate == true)
SlashCmdList.SKILLROUTE("help")
SlashCmdList.SKILLROUTE("cdmats on"); assert(SkillRouteDB.settings.cdmats == true)
SlashCmdList.SKILLROUTE("cdmats off"); assert(SkillRouteDB.settings.cdmats == false)
UI.Refresh()
UI._state.mode = "shopping"; UI.Refresh(); UI._state.mode = "route"
UI.AttachButton()
SlashCmdList.SKILLROUTE("") -- close
assert(not UI.IsShown())
assert(Core.Standing(609) == 4 and Core.Standing(576) == nil, "standing from GetFactionInfoByID (standingID - 1)")
-- tools: Enchanting without rods -> route rows tell you to craft them
local ench = SkillRouteTestNS and nil
do
  local Planner = ns.Planner
  local D = SkillRouteData
  local pl = Planner.Plan({ recipes = D.professions[333].recipes, items = D.items, tools = D.tools,
    skill = 130, target = 225, maxSkill = 225, known = {}, trainer = {},
    price = function(id) if id == 6339 or id == 11130 or id == 11145 or id == 16207 then return nil end return Core.Price(id) end,
    hasTool = function(k) return k == 373 or k == 374 end })
  local crafted = {}
  for k, u in pairs(pl.unlocks) do if u.kind == "tool" and u.craftSpell then crafted[#crafted + 1] = u.name end end
  table.sort(crafted)
  assert(#crafted >= 1, "rods crafted when they can't be bought")
  print("rods to craft 130->225: " .. table.concat(crafted, ", "))
end
-- and the window shows "Craft 1 x Runed ... Rod" as a route row
do
  local saved = { GetProfessions, GetProfessionInfo }
  GetProfessions = function() return 1 end
  GetProfessionInfo = function() return "Enchanting", 0, 130, 225, 0, 0, 333 end
  for _, id in ipairs({ 6339, 11130, 11145, 16207 }) do prices[id] = nil end
  SkillRouteDB.settings.estimate = false -- no guessed rod prices: they must be crafted
  UI.Toggle(333)
  local found
  for _, t in ipairs(texts) do
    if type(rawget(t, "text")) == "string" and t.text:find("Craft 1 x Runed ", 1, true) then found = t.text end
  end
  assert(found, "route shows a 'Craft 1 x Runed ... Rod' row")
  print("route row: " .. found:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  UI.Toggle() -- close
  GetProfessions, GetProfessionInfo = saved[1], saved[2]
end

-- auto open/close with the profession window
local evf
for _, f in ipairs(frames) do local e = rawget(f, "events"); if e and e.TRADE_SKILL_SHOW then evf = f end end
assert(evf and evf.events.TRADE_SKILL_CLOSE, "events registered")
local function fire(ev, ...) evf.OnEvent(evf, ev, ...) end
assert(not UI.IsShown())
fire("TRADE_SKILL_SHOW"); assert(UI.IsShown(), "opens with the profession window")
fire("TRADE_SKILL_CLOSE"); assert(not UI.IsShown(), "closes with it when it opened itself")
SlashCmdList.SKILLROUTE("")            -- opened by hand
fire("TRADE_SKILL_SHOW"); fire("TRADE_SKILL_CLOSE")
assert(UI.IsShown(), "a window opened by hand stays open")
SlashCmdList.SKILLROUTE("")            -- close
C_TradeSkillUI.IsTradeSkillLinked = function() return true end
fire("TRADE_SKILL_SHOW"); assert(not UI.IsShown(), "another player's linked profession: no auto-open")
C_TradeSkillUI.IsTradeSkillLinked = nil
SlashCmdList.SKILLROUTE("auto off")
fire("TRADE_SKILL_SHOW"); assert(not UI.IsShown(), "auto off respected")
SlashCmdList.SKILLROUTE("auto on")
-- money is drawn like the game's: coloured g/s/c, surrounding colour resumed
do
  local foot
  for _, t in ipairs(texts) do local v = rawget(t, "text"); if type(v) == "string" and v:find("^Buy for") then foot = v end end
  assert(foot and foot:find("|cffffd700g|r", 1, true) or foot:find("|cffeda55fc|r", 1, true), "footer uses coloured coin letters")
  print("footer: " .. foot)
end
-- intermediate steps (bolts) show "counted later", not a near-zero cost
do
  local saved = { GetProfessions, GetProfessionInfo }
  GetProfessions = function() return 1 end
  GetProfessionInfo = function() return "Tailoring", 0, 117, 150, 0, 0, 197 end
  for id, it in pairs(SkillRouteData.items) do prices[id] = math.max(1, it[2]) * 3 end
  UI.Toggle(197)
  local later = false
  for _, t in ipairs(texts) do local v = rawget(t, "text"); if type(v) == "string" and v:find("counted later", 1, true) then later = true end end
  assert(later, "an intermediate step shows 'counted later'")
  UI.Toggle()
  GetProfessions, GetProfessionInfo = saved[1], saved[2]
end
-- the "Train Expert" row names the trainer and where they are
do
  local saved = { GetProfessions, GetProfessionInfo }
  GetProfessions = function() return 1 end
  GetProfessionInfo = function() return "Tailoring", 0, 140, 150, 0, 0, 197 end
  UI.Toggle(197)
  local row
  for _, t in ipairs(texts) do local v = rawget(t, "text"); if type(v) == "string" and v:find("Train Expert", 1, true) then row = v end end
  assert(row and row:find("at Hgarth", 1, true), "train row names the trainer: " .. tostring(row))
  print("train row: " .. row:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  UI.Toggle()
  GetProfessions, GetProfessionInfo = saved[1], saved[2]
end
-- right-click skip + /sr unskip; AH age check
do
  assert(Core.ToggleSkip(197, 3848) == true and Core.Skips(197)[3848], "skip recorded")
  assert(Core.ToggleSkip(197, 3848) == nil, "toggle back")
  Core.ToggleSkip(197, 3848); SlashCmdList.SKILLROUTE("unskip")
  assert(next(Core.Skips(197)) == nil, "/sr unskip clears")
  Auctionator.API.v1.GetAuctionAgeByItemID = function(_, id) return id == 1 and 0 or 5 end
  assert(Core.AHFresh(1) and not Core.AHFresh(2), "seen today: fresh; 5 days ago: not")
  Auctionator.API.v1.GetAuctionAgeByItemID = nil
  assert(Core.AHFresh(2), "no age API: don't block")
end
-- trainers / vendors from the data: zone asked from the game, nearest, TomTom waypoint
do
  local D = SkillRouteData
  local wantSwap = false -- which axis order the fake game expects
  _G.CreateVector2D = function(x, y) return { x = x, y = y } end
  C_Map.GetMapInfo = function(m)
    if m == 1442 then return { mapType = 3, parentMapID = 1414, name = "Stonetalon Mountains" } end
    if m == 1414 or m == 1415 then return { mapType = 2, parentMapID = 946, name = m == 1414 and "Kalimdor" or "Eastern Kingdoms" } end
  end
  C_Map.GetMapPosFromWorldPos = function(map, vec, ui)
    for id, n in pairs(D.npcs) do
      local ok = wantSwap and (vec.x == n[5] and vec.y == n[4]) or (not wantSwap and vec.x == n[4] and vec.y == n[5])
      if ok and n[3] == map then
        if ui == n[6] then return ui, { x = n[7] / 100, y = n[8] / 100 } end
        return ui, { x = 0.708, y = 0.307 }
      end
    end
    return ui, { x = 0.99, y = 0.99 } -- wrong axis order: lands somewhere else
  end
  C_Map.GetMapInfoAtPosition = function() return { mapID = 1458, name = "Undercity" } end

  local loc = Core.NearestTrainer(197, 3) -- Expert Tailoring, Horde
  assert(loc and (loc.npc == "Josef Gregorian" or loc.npc == "Daryl Stack") and loc.zone == "Undercity" and loc.ui == 1458 and loc.x == 70.8,
    "nearest Horde Expert trainer, zone from the game: " .. tostring(loc and loc.npc))
  print("nearest Expert Tailoring trainer (Horde): " .. loc.npc .. ", " .. Core.Where(loc))
  -- the game wants the axes the other way round: detected via the continent check
  wantSwap = true
  for k in pairs(D.npcs) do end
  local classicId
  for id, n in pairs(D.npcs) do if id > 0 and not n[12] and n[6] then classicId = id; break end end
  local fresh = Core.NPCLocation(classicId) -- a Classic NPC, not resolved before
  assert(fresh and fresh.zone == "Undercity", "axis order detected")
  -- Alliance-only vendor never offered to Horde
  local v = Core.NearestVendor(SkillRouteData.professions[197].recipes[select(1, (function()
    for sp, r in pairs(SkillRouteData.professions[197].recipes) do if r.n == "Bright Yellow Shirt" then return sp end end end)())].pat[1])
  assert(v == nil, "Bright Yellow Shirt: no Horde vendor")
  -- recipe trainers: exact list for Silk Headband; rank fallback for a recipe not in it
  local t1 = Core.NearestRecipeTrainer(197, 8762, 125)
  assert(t1 and t1.side:find("H"), "Silk Headband: a Horde trainer")
  -- Forever: Magar <Expert Tailor> teaches Journeyman, not Expert; Expert comes from an Artisan/Master
  -- AllTheThings (exact): Magar teaches the Journeyman tier, Josef Expert, Daryl Stack Artisan
  local function maskOf(name)
    for id, m in pairs(SkillRouteData.trainers[197]) do if SkillRouteData.npcs[id][1] == name then return m, id end end
  end
  assert(maskOf("Magar") == 2 and maskOf("Josef Gregorian") == 4 and maskOf("Daryl Stack") == 8, "tiers from ATT")
  local _, jid = maskOf("Josef Gregorian")
  assert(jid < 0 and SkillRouteData.npcs[jid][12] == 1458, "ATT NPC carries its exact zone map")
  local ex = Core.NearestTrainer(197, 3)
  assert(ex and (ex.npc == "Josef Gregorian" or ex.npc == "Daryl Stack"), "Horde Expert Tailoring from an Artisan/Master: " .. tostring(ex and ex.npc))
  local jm = Core.NearestTrainer(197, 2)
  assert(jm and jm.npc ~= "Snang" and jm.npc ~= "Kil'hala", "Journeyman needs an Expert+ trainer: " .. tostring(jm and jm.npc))
  local t2, exact2 = Core.NearestRecipeTrainer(197, 999999, 160)
  assert(t2 and not exact2, "unknown recipe: nearest Expert+ trainer")
  print("Silk Headband trainer (Horde): " .. t1.npc)
  -- travel: from Orgrimmar, Expert (needs Artisan/Master) -> Josef Gregorian in Undercity
  -- via the zeppelin, not Daryl Stack (Hillsbrad); Artisan (needs Master) -> Daryl Stack
  local savedPos = C_Map.GetPlayerMapPosition
  C_Map.GetPlayerMapPosition = function(m) -- Orgrimmar on the Kalimdor map
    if m == 1414 then return { GetXY = function() return 0.588, 0.448 end } end
    return { GetXY = function() return 0.4723, 0.6181 end }
  end
  local e3 = Core.NearestTrainer(197, 3)
  assert(e3 and e3.npc == "Josef Gregorian" and e3.via and e3.via[1] == "boat/zeppelin: Orgrimmar and Undercity",
    "Expert from Orgrimmar: Josef via zeppelin, got " .. tostring(e3 and e3.npc))
  local e4 = Core.NearestTrainer(197, 4)
  assert(e4 and e4.npc == "Daryl Stack", "Artisan: Daryl Stack (Master)")
  print(("from Orgrimmar: Expert -> %s, %s; Artisan -> %s, %s"):format(e3.npc, Core.TravelText(e3), e4.npc, Core.TravelText(e4)))
  -- flight paths: none known -> zeppelin + run; after recording known flight points the
  -- Hillsbrad trip uses the Undercity -> Tarren Mill flight and gets shorter
  local before = e4.travel
  assert(e4.via and #e4.via == 1, "no flights known yet: zeppelin then run")
  local T = SkillRouteData.taxi.nodes
  local uc, tm
  for id, n in pairs(T) do
    if n[5]:find("^Undercity") then uc = id end
    if n[5]:find("^Tarren Mill") then tm = id end
  end
  _G.GetTaxiMapID = function() return 1415 end
  _G.C_TaxiMap = { GetAllTaxiNodes = function() return {
    { nodeID = uc, state = 1 }, { nodeID = tm, state = 1 }, { nodeID = 999999, state = 2 } } end }
  Core.RecordTaxi()
  assert(Core.KnownTaxi()[uc] and Core.KnownTaxi()[tm] and not Core.KnownTaxi()[999999], "known flight points recorded")
  local e4b = Core.NearestTrainer(197, 4)
  assert(e4b.npc == "Daryl Stack" and e4b.travel < before, "flight makes Hillsbrad faster")
  print(("Artisan with flights: %s, %s (was %.0f s, now %.0f s)"):format(e4b.npc, Core.TravelText(e4b), before, e4b.travel))
  local j2 = Core.NearestTrainer(197, 2)
  assert(j2 and j2.npc == "Magar", "Journeyman from Orgrimmar: Magar, got " .. tostring(j2 and j2.npc))
  C_Map.GetPlayerMapPosition = savedPos
  -- TomTom waypoint
  local got
  _G.TomTom = { AddWaypoint = function(self, ui, x, y, opts) got = { ui, x, y, opts.title } end }
  Core.Waypoint(loc)
  assert(got and got[1] == 1458 and math.abs(got[2] - 0.708) < 1e-9 and got[4] == loc.npc, "TomTom waypoint")
  _G.TomTom = nil
end
-- hearthstone (with its cooldown) and mage teleports
do
  local savedBest, savedInfo, savedPos, savedCount = C_Map.GetBestMapForUnit, C_Map.GetMapInfo, C_Map.GetPlayerMapPosition, GetItemCount
  -- stand in Undercity (Eastern Kingdoms), hearthstone bound to Orgrimmar
  C_Map.GetBestMapForUnit = function() return 1458 end
  C_Map.GetMapInfo = function(m)
    if m == 1458 then return { mapType = 3, parentMapID = 1415, name = "Undercity" } end
    return savedInfo(m)
  end
  C_Map.GetPlayerMapPosition = function(m)
    if m == 1415 then return { GetXY = function() return 0.449, 0.2465 end } end
    return { GetXY = function() return 0.5, 0.5 end }
  end
  _G.GetBindLocation = function() return "Orgrimmar" end
  _G.GetTime = function() return 10000 end
  local cdStart = 0
  _G.GetItemCooldown = function(item) if item == 6948 then return cdStart, 3600 end return 0, 0 end
  _G.GetItemCount = function(id) if id == 6948 then return 1 end return savedCount(id) end
  -- Journeyman (Magar, Orgrimmar): hearthstone ready -> hearth
  -- route to Magar (Orgrimmar) specifically; the nearest Journeyman trainer from Undercity
  -- is Rhiannon Davis right there, which needs no travel
  local magar
  for id, n in pairs(SkillRouteData.npcs) do if n[1] == "Magar" then magar = id end end
  local function toMagar() return Core.NearestNPC({ magar }) end
  local j = toMagar()
  assert(j and j.npc == "Magar" and j.via and j.via[1]:find("^hearthstone to Orgrimmar"), "ready hearthstone used: " .. tostring(j and j.via and j.via[1]))
  print("Journeyman from Undercity, hearth ready: " .. j.npc .. ", " .. Core.TravelText(j))
  -- hearthstone with 55 min left: the zeppelin is faster, so it's not used
  cdStart = 10000 - 300
  local j2 = toMagar()
  assert(j2 and j2.npc == "Magar" and not (j2.via[1]:find("^hearthstone")), "hearthstone on long cooldown not used")
  print("hearth 55 min left: " .. Core.TravelText(j2))
  -- 2 min left: waiting for it still beats the zeppelin
  cdStart = 10000 - 3600 + 120
  local j3 = toMagar()
  assert(j3.via[1]:find("^hearthstone to Orgrimmar %(ready in 2 min%)"), "short cooldown: wait for the hearth: " .. tostring(j3.via[1]))
  print("hearth 2 min left: " .. Core.TravelText(j3))
  -- mage with Teleport: Orgrimmar and a rune
  _G.UnitClass = function() return "Mage", "MAGE" end
  _G.IsPlayerSpell = function(id) return id == 3567 or id == 3848 end
  _G.GetItemCount = function(id) if id == 17031 then return 5 end if id == 6948 then return 0 end return savedCount(id) end
  local m = toMagar()
  assert(m.via[1] == "teleport to Orgrimmar", "mage teleport used: " .. tostring(m.via[1]))
  print("mage: " .. Core.TravelText(m))
  _G.UnitClass = nil
  _G.IsPlayerSpell = function(id) return id == 3848 end
  C_Map.GetBestMapForUnit, C_Map.GetMapInfo, C_Map.GetPlayerMapPosition, _G.GetItemCount = savedBest, savedInfo, savedPos, savedCount
end

-- worst case timing: every flight point known, empty travel cache
do
  local known = Core.KnownTaxi()
  for id in pairs(SkillRouteData.taxi.nodes) do known[id] = true end
  _G.C_TaxiMap = { GetAllTaxiNodes = function() local t = {} for id in pairs(SkillRouteData.taxi.nodes) do t[#t + 1] = { nodeID = id, state = 1 } end return t end }
  Core.RecordTaxi() -- bumps the version: cache invalid
  local t0 = os.clock()
  local e = Core.NearestTrainer(197, 4)
  local first = (os.clock() - t0) * 1000
  t0 = os.clock()
  for _ = 1, 20 do Core.NearestTrainer(197, 3) end
  local cached = (os.clock() - t0) * 1000 / 20
  print(("travel graph, every flight point known (%d flights): first %.1f ms, cached %.2f ms per lookup (%s)"):format(
    #SkillRouteData.taxi.flights, first, cached, e and e.npc or "?"))
end
-- shopping list -> Auctionator shopping list (vendor items left out)
do
  local created
  Auctionator.API.v1.CreateShoppingList = function(caller, name, terms) created = { name = name, terms = terms } end
  Auctionator.API.v1.ConvertToSearchString = function(caller, t) return ('"%s";;;;;;;;;;;;;%d'):format(t.searchString, t.quantity or 0) end
  local plan = Core.Plan(197, 300)
  local realPrint = print; _G.print = function() end
  assert(Core.ExportToAuctionator(plan), "export succeeded")
  _G.print = realPrint
  assert(created and created.name == "SkillRoute Tailoring" and #created.terms > 0, "list created")
  for _, t in ipairs(created.terms) do
    assert(not t:find("Fine Thread", 1, true) and not t:find("Dye", 1, true), "vendor items left out: " .. t)
  end
  print(("Auctionator list '%s': %d items, e.g. %s"):format(created.name, #created.terms, created.terms[1]))
  Auctionator.API.v1.CreateShoppingList, Auctionator.API.v1.ConvertToSearchString = nil, nil
end

-- click a known recipe -> opens it; unknown -> waypoint
do
  local opened
  C_TradeSkillUI.OpenRecipe = function(id) opened = id end
  assert(Core.IsRecipeKnown(197, 3848), "Double-stitched Woolen Shoulders known (IsPlayerSpell stub)")
  assert(Core.OpenRecipe(3848) and opened == 3848, "OpenRecipe called")
  assert(not Core.IsRecipeKnown(197, 8762), "Silk Headband not known")
  C_TradeSkillUI.OpenRecipe = nil
  assert(not Core.OpenRecipe(3848), "no API: reports it couldn't")
end

-- materials on alts (Syndicator): subtracted from what to buy, shown separately
do
  _G.Syndicator = { API = { GetInventoryInfoByItemID = function(item)
    return { characters = { { character = "Tester", bags = 99 }, { character = "Altbank", bags = 3, bank = 7, mail = 1 } } }
  end } }
  local plan = Core.Plan(197, 300)
  local b = plan.shopping.buy[#plan.shopping.buy]
  for _, x in ipairs(plan.shopping.buy) do if not x.pattern and not x.tool then b = x break end end
  assert(b.alts == 11, "alts counted, own character excluded: " .. tostring(b.alts))
  assert(b.buy == math.max(0, b.need - b.have - 11), "alts reduce what to buy")
  SlashCmdList.SKILLROUTE("alts off")
  local plan2 = Core.Plan(197, 300)
  for _, x in ipairs(plan2.shopping.buy) do assert((x.alts or 0) == 0, "alts off") end
  SlashCmdList.SKILLROUTE("alts on")
  _G.Syndicator = nil
end

-- gathering: Mining shows a zone route, no shopping
do
  local saved = { GetProfessions, GetProfessionInfo }
  GetProfessions = function() return 1 end
  GetProfessionInfo = function() return "Mining", 0, 50, 75, 0, 0, 186 end
  UI.Toggle(186)
  local found, foot
  for _, t in ipairs(texts) do
    local v = rawget(t, "text")
    if type(v) == "string" and v:find("Copper Vein", 1, true) then found = v end
    if type(v) == "string" and v:find("^Gathering route") then foot = v end
  end
  assert(found and foot, "mining route rows + footer")
  print("mining row: " .. found:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. " | " .. foot:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  UI.Toggle()
  GetProfessions, GetProfessionInfo = saved[1], saved[2]
end

-- another language: German names still match (profession via its rank spell,
-- recipes via the item they make, rank-ups via the skill they need)
do
  local tailorSpell = SkillRouteData.professions[197].spell
  assert(tailorSpell, "profession rank spell in the data")
  _G.GetSpellInfo = function(id) if id == tailorSpell then return "Schneiderei" end end
  local saved = { GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceSkillReq, GetTrainerServiceItemLink, npcName }
  npcName = "Ausbilder"
  _G.GetNumTrainerServices = function() return 2 end
  _G.GetTrainerServiceInfo = function(i) if i == 1 then return "Erdene Weste" end return "Schneiderei", "Experte" end
  _G.GetTrainerServiceSkillReq = function(i) return "Schneiderei", i == 1 and 140 or 125, true end
  _G.GetTrainerServiceItemLink = function(i) if i == 1 then return "|Hitem:7051::|h" end end
  SkillRouteDB.trainer[197][8764] = nil
  Core.ScanTrainer()
  assert(SkillRouteDB.trainer[197][8764] and SkillRouteDB.trainer[197][8764].req == 140, "German recipe matched by its item")
  assert(SkillRouteDB.places.trainers[197].Ausbilder.ranks.Expert, "German rank-up recognised from its skill requirement")
  GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceSkillReq, GetTrainerServiceItemLink, npcName =
    saved[1], saved[2], saved[3], saved[4], saved[5]
  _G.GetSpellInfo = nil
end

-- minimap button and options window
do
  local O = ns.Options
  local b = O.CreateMinimapButton()
  assert(b, "minimap button created")
  local opened = 0
  local savedToggle = UI.Toggle
  UI.Toggle = function() opened = opened + 1 end
  b.OnClick(b, "LeftButton")
  assert(opened == 1, "left-click opens the window")
  UI.Toggle = savedToggle
  b.OnClick(b, "RightButton")
  assert(O.IsShown(), "right-click opens the options")
  -- dragging: cursor straight above the minimap centre -> 90 degrees, saved
  b.OnDragStart(b); local upd = rawget(b, "OnUpdate"); assert(upd, "drag follows the cursor"); upd(b)
  assert(math.abs(SkillRouteDB.settings.minimapAngle - 90) < 1e-6, "angle saved: " .. tostring(SkillRouteDB.settings.minimapAngle))
  -- a setting changed in the options re-plans with it
  O.Set("margin", 75)
  assert(SkillRouteDB.settings.margin == 75)
  O.Set("minimapHide", true); assert(not b:IsShown(), "minimap button hidden")
  O.Set("minimapHide", false); assert(b:IsShown(), "and shown again")
  SlashCmdList.SKILLROUTE("minimap off"); assert(not b:IsShown())
  SlashCmdList.SKILLROUTE("minimap on"); assert(b:IsShown())
  O.Toggle(); assert(not O.IsShown(), "options close")
  SkillRouteDB.settings.margin = nil
end

-- First Aid: Expert from the book (Horde vendor), Artisan from the "Triage" quest
do
  assert(not Core.NearestTrainer(129, 3), "no trainer teaches Expert First Aid")
  local book = Core.RankBook(129, 3)
  assert(book and book.name == "Expert First Aid - Under Wraps" and book.loc and book.loc.npc == "Balai Lok'Wein",
    "Horde: book from Balai Lok'Wein, got " .. tostring(book and book.loc and book.loc.npc))
  local q = Core.RankQuest(129, 4)
  assert(q and q.title == "Triage" and q.loc.npc == "Doctor Gregory Victor" and q.skill == 225, "Horde: Triage from Doctor Gregory Victor")
  print(("First Aid (Horde): Expert -> buy %s from %s, %s; Artisan -> quest %s from %s"):format(
    book.name, book.loc.npc, Core.Where(book.loc), q.title, q.loc.npc))
  -- the window row
  local saved = { GetProfessions, GetProfessionInfo }
  GetProfessions = function() return 1 end
  GetProfessionInfo = function() return "First Aid", 0, 150, 150, 0, 0, 129 end
  UI.Toggle(129)
  local row
  for _, t in ipairs(texts) do local v = rawget(t, "text"); if type(v) == "string" and v:find("Buy Expert First Aid", 1, true) then row = v end end
  assert(row, "window shows the book row")
  UI.Toggle()
  GetProfessions, GetProfessionInfo = saved[1], saved[2]
end

-- /sr check runs and reports; errors are caught, not thrown
do
  local out = {}
  local realPrint = print
  _G.print = function(s) out[#out + 1] = tostring(s) end
  SlashCmdList.SKILLROUTE("check")
  _G.print = realPrint
  assert(#out > 20, "check printed a report")
  local joined = table.concat(out, "\n")
  assert(joined:find("Auctionator prices", 1, true) and joined:find("plan Tailoring", 1, true), "report covers APIs and a live plan")
  -- a failing refresh shows a message instead of erroring
  local savedPlan = Core.Plan
  Core.Plan = function() error("boom") end
  local realPrint2 = print
  _G.print = function() end
  UI.Toggle(197)
  _G.print = realPrint2
  Core.Plan = savedPlan
  assert(SkillRouteDB.lastError and SkillRouteDB.lastError:find("boom"), "error recorded")
  UI.Toggle()
  SkillRouteDB.lastError = nil
  realPrint(("check: %d lines, e.g. %s"):format(#out, out[2]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
end
print("SMOKE TEST PASSED")
