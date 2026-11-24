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
    if k == "SetAlpha" then return function(self, a) rawset(self, "alpha", a) end end
    if k == "SetScript" then return function(self, n, f) if n == "OnShow" then self.onShow = f end; self[n] = f end end
    if k == "RegisterEvent" then return function(self, ev) local e = rawget(self, "events") or {}; rawset(self, "events", e); e[ev] = true end end
    if k == "CreateTexture" then return function() return stubObj() end end
    if k == "CreateFontString" then return function() local o = stubObj(); texts[#texts + 1] = o; return o end end
    return function() end
  end })
end
local frames = {}
_G.CreateFrame = function() local f = stubObj(); f.shown = true; frames[#frames + 1] = f; return f end -- WoW: new frames start shown
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
for _, f in ipairs({ "Data", "Planner", "Core", "UI", "Options", "Recorder", "Check" }) do
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
-- Forever's client: no GetMerchantItemInfo / GetMerchantNumItems, only C_MerchantFrame
do
  local oldInfo, oldNum = _G.GetMerchantItemInfo, _G.GetMerchantNumItems
  _G.GetMerchantItemInfo, _G.GetMerchantNumItems = nil, nil
  _G.C_MerchantFrame = { GetNumItems = function() return 1 end,
                         GetItemInfo = function() return { name = "Pattern", price = 90000, stackCount = 1, numAvailable = 2 } end }
  npcName = "Kania2"
  local ok, err = pcall(Core.ScanMerchant)
  assert(ok, "vendor scan with the modern merchant API: " .. tostring(err))
  local e = SkillRouteDB.places.vendors[patItem].Kania2
  assert(e and e.price == 90000 and e.limited, "modern API: price and limited stock recorded")
  SkillRouteDB.places.vendors[patItem].Kania2 = nil
  _G.C_MerchantFrame, _G.GetMerchantItemInfo, _G.GetMerchantNumItems = nil, oldInfo, oldNum
  npcName = "Kania"
end
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
SlashCmdList.SKILLROUTE("overtime 10"); assert(ns.Core.Char().bonus == 0.1 and SkillRouteDB.settings.bonus == nil, "overtime is per character")
do -- the old account-wide value moves to the first character, others start at 0
  local me = ns.Core.Char(); local mine = me.bonus
  me.bonus = nil; SkillRouteDB.settings.bonus = 0.05
  assert(ns.Core.Bonus() == 0.05 and SkillRouteDB.settings.bonus == nil, "migrated to this character")
  local saved = _G.UnitName; _G.UnitName = function() return "Alt" end
  assert(ns.Core.Bonus() == 0, "an alt has its own (none)")
  _G.UnitName = saved; me.bonus = mine
end
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
-- an error saved by an older version is dropped on load; a current one is kept, with
-- its version, and /sr check shows it
_G.C_AddOns = { GetAddOnMetadata = function(_, k) if k == "Version" then return "9.9.9" end end }
SkillRouteDB.lastError, SkillRouteDB.lastErrorVersion = "MERCHANT_SHOW: old", "0.23.1"
fire("ADDON_LOADED", "SkillRoute")
assert(SkillRouteDB.lastError == nil, "an older version's error is cleared on load")
Core.ReportError("TEST", "boom")
assert(SkillRouteDB.lastErrorVersion == "9.9.9", "error tagged with the version")
fire("ADDON_LOADED", "SkillRoute")
assert(SkillRouteDB.lastError == "TEST: boom", "a current version's error is kept")
SkillRouteDB.lastError, SkillRouteDB.lastErrorVersion, SkillRouteDB.lastErrorTime = nil, nil, nil
_G.C_AddOns = nil
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
  -- an errand in town: hearth bound to Thunder Bluff and ready, standing in Undercity:
  -- Flint and Tinder from Undercity's own vendor, not "hearth to Thunder Bluff"
  cdStart = 0
  _G.GetBindLocation = function() return "Thunder Bluff" end
  local kuruk = SkillRouteData.npcs[8362] -- bound at the inn: you land right by Kuruk
  local savedBind = Core.Char().bind
  Core.Char().bind = { map = kuruk[3], x = kuruk[4] + 5, y = kuruk[5], name = "Thunder Bluff" }
  local fl = Core.NearestVendor(4471)
  Core.Char().bind = savedBind
  assert(fl and not (fl.via and fl.via[1] and fl.via[1]:find("^hearthstone")),
    "no hearthstone for a vendor in town: " .. tostring(fl and fl.npc) .. " " .. tostring(fl and fl.via and fl.via[1]))
  print("flint and tinder from Undercity, hearth to Thunder Bluff ready: " .. fl.npc .. ", " .. tostring(Core.TravelText(fl)))
  _G.GetBindLocation = function() return "Orgrimmar" end
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
  -- Horde: no Alliance zone listed before a Horde/contested one, in every gathering row
  for _, line in ipairs({ 186, 182, 356, 393 }) do
    local name = ({ [186] = "Mining", [182] = "Herbalism", [356] = "Fishing", [393] = "Skinning" })[line]
    GetProfessionInfo = function() return name, 0, 1, 300, 0, 0, line end
    local plan = Core.Plan(line, 300)
    local rows = 0
    for _, st in ipairs(plan.steps) do
      if st.gather and st.zones then
        local seenEnemy = false
        local shown = {}
        for k = 1, #st.zones, 2 do shown[#shown + 1] = { z = st.zones[k], i = k } end
        table.sort(shown, function(a, b)
          local ra, rb = Core.ZoneRank(a.z), Core.ZoneRank(b.z)
          if ra ~= rb then return ra < rb end return a.i < b.i end)
        for _, x in ipairs(shown) do
          local enemy = Core.ZoneRank(x.z) == 2
          assert(enemy or not seenEnemy, "Alliance zones last")
          assert(enemy == (Core.ZoneName(x.z) ~= x.z), "only Alliance zones marked")
          seenEnemy = seenEnemy or enemy
        end
        if line == 356 and #st.zones > 0 then
          -- fishing picks: no Alliance zone chosen while a Horde/contested one is safe
          local hasOk = false
          for _, z in ipairs(SkillRouteData.fishing) do
            if z[2] + 95 <= st.from and Core.ZoneRank(z[1]) < 2 then hasOk = true end
          end
          if hasOk then assert(Core.ZoneRank(st.zones[1]) < 2, "fishing: Horde or contested zone first at " .. st.from) end
        end
        rows = rows + 1
      end
    end
    assert(rows > 0, name .. " gather rows")
  end
  GetProfessionInfo = function() return "Mining", 0, 50, 75, 0, 0, 186 end
  UI.Toggle(); UI.Toggle(186)
  found = nil
  for _, t in ipairs(texts) do
    local v = rawget(t, "text")
    if type(v) == "string" and v:find("^Best zones") then found = found or v end
  end
  print("mining row: " .. found:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. " | " .. foot:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  UI.Toggle()
  GetProfessions, GetProfessionInfo = saved[1], saved[2]
end

-- ranks ATT says come from a quest: Horde First Aid at 225 gets "Triage" from its giver,
-- not a trainer; Skinning rows name zones (Horde first)
do
  local saved = { GetProfessions, GetProfessionInfo }
  GetProfessions = function() return 1 end
  GetProfessionInfo = function() return "First Aid", 0, 225, 225, 0, 0, 129 end
  UI.Toggle(129)
  local quest
  for _, t in ipairs(texts) do
    local v = rawget(t, "text")
    if type(v) == "string" and v:find('Quest "Triage"', 1, true) then quest = v end
  end
  assert(quest, "Artisan First Aid shown as the Triage quest")
  local sub
  for _, t in ipairs(texts) do
    local v = rawget(t, "text")
    if type(v) == "string" and v:find("^Needs skill 225") then sub = v end
  end
  assert(sub and sub:find("Gregory Victor", 1, true), "Horde Triage giver: " .. tostring(sub))
  print("first aid 225 (Horde): " .. quest:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. " | " .. sub)
  UI.Toggle()
  GetProfessionInfo = function() return "Skinning", 0, 100, 150, 0, 0, 393 end
  UI.Toggle(393)
  local skin
  for _, t in ipairs(texts) do
    local v = rawget(t, "text")
    if type(v) == "string" and v:find("^Best zones") then skin = skin or v end
  end
  assert(skin, "skinning rows list zones")
  print("skinning 100 (Horde): " .. skin)
  UI.Toggle()
  GetProfessions, GetProfessionInfo = saved[1], saved[2]
end

-- a rank book you own: "in your bags" only when it's in your bags; bank-only says bank
do
  local saved = { GetProfessions, GetProfessionInfo, _G.GetItemCount }
  GetProfessions = function() return 1 end
  GetProfessionInfo = function() return "First Aid", 0, 150, 150, 0, 0, 129 end
  local function sub()
    UI.Toggle(129)
    local found
    for _, t in ipairs(texts) do
      local v = rawget(t, "text")
      if type(v) == "string" and v:find("^Teaches Expert") then found = v end
    end
    UI.Toggle()
    return found
  end
  _G.GetItemCount = function(id, bank) if id == 16084 then return bank and 1 or 0 end return saved[3](id, bank) end
  local s1 = sub()
  assert(s1 and s1:find("in your bank", 1, true), "bank-only book: " .. tostring(s1))
  _G.GetItemCount = function(id, bank) if id == 16084 then return 1 end return saved[3](id, bank) end
  local s2 = sub()
  assert(s2 and s2:find("in your bags", 1, true), "book in bags: " .. tostring(s2))
  _G.GetItemCount = function(id, bank) if id == 16084 then return 0 end return saved[3](id, bank) end
  local s3 = sub()
  assert(not s3 or not s3:find("in your", 1, true), "no book: not claimed owned: " .. tostring(s3))
  print("expert book rows: bank -> " .. s1 .. " | none -> " .. tostring(s3))
  GetProfessions, GetProfessionInfo, _G.GetItemCount = saved[1], saved[2], saved[3]
end

-- patterns you own (bank) are free: no AH purchase, nothing on the shopping list
do
  local saved = { GetProfessions, GetProfessionInfo, _G.GetItemCount }
  GetProfessions = function() return 1 end
  GetProfessionInfo = function() return "First Aid", 0, 180, 225, 0, 0, 129 end
  local manuals = { [16112] = true, [16113] = true } -- Heavy Silk, Mageweave Bandage
  local function stepFor(plan, spell) for _, st in ipairs(plan.steps) do if st.spell == spell then return st end end end
  _G.GetItemCount = function(id, bank) if manuals[id] then return 0 end return saved[3](id, bank) end
  local before = Core.Plan(129, 225)
  _G.GetItemCount = function(id, bank) if manuals[id] then return bank and 1 or 0 end return saved[3](id, bank) end
  local after = Core.Plan(129, 225)
  for _, b in ipairs(after.shopping.buy) do assert(not manuals[b.item], "owned manual not on the shopping list") end
  local mw = stepFor(after, 10840)
  assert(mw and mw.unlock and mw.unlock.via == "owned" and mw.unlock.owned == "in your bank", "Mageweave from the owned manual")
  assert(after.total <= before.total, "owning patterns never costs more")
  UI.Toggle(129)
  local row
  for _, t in ipairs(texts) do
    local v = rawget(t, "text")
    if type(v) == "string" and v:find("Learn from your", 1, true) then row = row or v end
  end
  UI.Toggle()
  assert(row and row:find("in your bank", 1, true), "row says where the manual is: " .. tostring(row))
  print(("owned manuals: total %d -> %d copper; row: %s"):format(before.total, after.total,
    row:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
  GetProfessions, GetProfessionInfo, _G.GetItemCount = saved[1], saved[2], saved[3]
end

-- shopping list: rank books (Expert Cookbook) are on it and in the total; patterns and
-- books name the vendor and set a waypoint, like the route
do
  local saved = { GetProfessions, GetProfessionInfo }
  GetProfessions = function() return 1 end
  GetProfessionInfo = function() return "Cooking", 0, 1, 75, 0, 0, 185 end
  local plan = Core.Plan(185, 300)
  local book
  for _, b in ipairs(plan.shopping.buy) do if b.book then book = b end end
  assert(book and book.item == 16072, "Expert Cookbook on the shopping list")
  local spent = 0
  for _, b in ipairs(plan.shopping.buy) do if not b.farm then spent = spent + (b.price or 0) * b.buy end end
  assert(math.abs(plan.total - spent) < 1, "Buy for includes the book")
  UI.Toggle(185)
  UI.SetMode("shopping")
  local bookRow, bookWp
  for _, r in ipairs(UI.Rows()) do
    local sub = r.sub and rawget(r.sub, "text")
    if type(sub) == "string" and sub:find("rank-up book, from ", 1, true) and not sub:find("a vendor", 1, true) then
      bookRow, bookWp = sub, rawget(r, "waypoint")
    end
  end
  UI.SetMode("route")
  UI.Toggle()
  assert(bookRow and type(bookWp) == "table" and bookWp.npc, "book row names its vendor and has a waypoint")
  -- vendor reagents and tools: nearest vendor named (Horde); Flint and Tinder has vendors
  assert(SkillRouteData.vendorNpcs[4471] and #SkillRouteData.vendorNpcs[4471] > 0, "Flint and Tinder vendors in the data")
  local fl = Core.NearestVendor(4471)
  assert(fl and fl.npc, "nearest Flint and Tinder vendor for Horde")
  print("flint and tinder: " .. fl.npc .. ", " .. tostring(Core.Where(fl)))
  print("shopping: " .. bookRow:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. " (waypoint: " .. bookWp.npc .. ")")
  GetProfessions, GetProfessionInfo = saved[1], saved[2]
end

-- a pattern bought on the AH says why: Cooked Crab Claw's (2698) only vendor is Alliance
do
  local why = UI.AhWhy(2698, true):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  assert(why:find("only Alliance vendors sell it: Kendor Kabonka", 1, true), why)
  local short = UI.AhWhy(2698):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  assert(short == " (only Alliance vendors sell it)", "row text stays short: " .. short)
  -- Goblin Deviled Clams (6500, learned at 125+): a Cooking trainer is named
  local loc = Core.NearestRecipeTrainer(185, 6500, 125)
  assert(loc and loc.npc, "a Cooking trainer for an Expert-level recipe")
  print("goblin deviled clams trainer: " .. loc.npc)
  print("ah why (Horde, Cooked Crab Claw):" .. why)
  -- its 4s vendor price is Alliance-only: for Horde the price is the AH's 1g 50s, and
  -- an AH pattern step shows that, not "last seen 4s"
  assert(SkillRouteData.items[2698][3] == 400, "the recipe's vendor price is 4s")
  prices[2698] = 15000
  assert(Core.Price(2698) == 15000, "Horde: no Alliance vendor price, the AH price: " .. tostring(Core.Price(2698)))
  assert(Core.AHPrice(2698) == 15000, "AH price alone")
  local savedAge = Auctionator.API.v1.GetAuctionAgeByItemID
  Auctionator.API.v1.GetAuctionAgeByItemID = function() return 0 end
  local savedP = { GetProfessions, GetProfessionInfo }
  GetProfessions = function() return 1 end
  GetProfessionInfo = function() return "Cooking", 0, 85, 150, 0, 0, 185 end
  local cp = Core.Plan(185, 100)
  for _, st in ipairs(cp.steps) do
    if st.unlock and st.unlock.item == 2698 then
      assert(st.unlock.price == 15000, "pattern bought at the AH price, not the vendor's: " .. tostring(st.unlock.price))
    end
  end
  for _, u in pairs(cp.unlocks or {}) do
    if u.item == 2698 then assert(u.via == "ah" and u.price == 15000, "Crab Claw pattern: AH at 1g 50s") end
  end
  GetProfessions, GetProfessionInfo = savedP[1], savedP[2]
  Auctionator.API.v1.GetAuctionAgeByItemID = savedAge
  prices[2698] = nil
end

-- recipes taught by a quest (ATT): learnable when your faction has a giver; the row
-- names the quest and giver; its 1g effort isn't added to training
do
  local P = ns.Planner
  local tailoring, firstAid = SkillRouteData.professions[197].recipes, SkillRouteData.professions[129].recipes
  local okH = Core.QuestsForFaction(firstAid)
  assert(okH[1230117], "First Aid Kit: Horde givers (Brakk, Kaga Wildhoof...)")
  assert(not Core.QuestsForFaction(tailoring)[1263425], "Faction Banner: Alliance givers only, not for Horde")
  local at, how = P.LearnAt(1230117, firstAid[1230117], { known = {}, trainer = {}, questOK = okH })
  assert(at == 20 and how == "quest", "quest recipe learnable at 20")
  assert(P.LearnAt(1263425, tailoring[1263425], { known = {}, trainer = {}, questOK = {} }) == nil, "no giver: not learnable")
  local q = Core.RecipeQuest(1230117)
  assert(q and q.title == "Camping 101: First Aid" and q.loc.npc, "nearest Horde giver")
  -- a plan using it (First Aid 1 -> 21): the quest's 1g never shows as training
  local plan = P.Plan({ recipes = firstAid, items = SkillRouteData.items, skill = 19, target = 21, maxSkill = 75,
    known = {}, trainer = {}, questOK = okH, price = function() return 100 end })
  assert((plan.fees or 0) == 0 or not plan.steps[1] or plan.steps[1].learn ~= "quest", "quest effort not in training fees")
  -- the row: stub one plan step through the window
  local saved = { GetProfessions, GetProfessionInfo, Core.Plan }
  GetProfessions = function() return 1 end
  GetProfessionInfo = function() return "First Aid", 0, 20, 75, 0, 0, 129 end
  Core.Plan = function(line, target)
    local p = saved[3](line, target)
    p.steps = { { spell = 1230117, name = "First Aid Kit", from = 20, to = 21, crafts = 1, cost = 100, perCraft = 100,
                  color = "orange", learn = "quest", var = 0, vendorBack = 0 } }
    return p
  end
  UI.Toggle(129)
  local row, wp
  for _, r in ipairs(UI.Rows()) do
    local sub = r.sub and rawget(r.sub, "text")
    if type(sub) == "string" and sub:find('Quest "Camping 101: First Aid" from', 1, true) then row, wp = sub, rawget(r, "waypoint") end
  end
  UI.Toggle()
  GetProfessions, GetProfessionInfo, Core.Plan = saved[1], saved[2], saved[3]
  assert(row and type(wp) == "table" and wp.npc == q.loc.npc, "quest row names the giver, with a waypoint")
  print("quest recipe row: " .. row:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- auction house open: each step gets a Buy button that puts its reagents (crafts x per
-- craft, with the margin, minus what you have) into an Auctionator list; clicking
-- twice doesn't double; right-click removes; closing the AH hides the buttons
do
  local lists, deleted = {}, 0
  local api = Auctionator.API.v1
  api.CreateShoppingList = function(_, name, terms) lists[name] = terms end
  api.DeleteShoppingList = function(_, name) lists[name] = nil; deleted = deleted + 1 end
  api.ConvertToSearchString = function(_, t) return ('"%s";;;;;;;;;;;;;%d'):format(t.searchString, t.quantity or 0) end
  local saved = { GetProfessions, GetProfessionInfo, print }
  GetProfessions = function() return 1 end
  GetProfessionInfo = function() return "First Aid", 0, 150, 225, 0, 0, 129 end
  fire("AUCTION_HOUSE_SHOW")
  assert(Core.ahOpen, "AH open recorded")
  UI.Toggle(129)
  local btnRow
  for _, r in ipairs(UI.Rows()) do
    local b = rawget(r, "buyBtn")
    if b and b.shown and rawget(r, "ahStep") then btnRow = btnRow or r end
  end
  assert(btnRow, "a step row has a Buy button while the AH is open")
  local st = rawget(btnRow, "ahStep")
  local expect = Core.StepShopping(UI._lastPlan(), st)
  assert(#expect > 0, "the step has something to buy")
  local said
  _G.print = function(m) said = m end
  local searchedFor, advFor
  api.MultiSearchExact = function(_, names) searchedFor = names end
  btnRow.buyBtn.OnClick(btnRow.buyBtn, "LeftButton")
  assert(searchedFor and #searchedFor == #expect, "no advanced search: names-only fallback")
  api.MultiSearchAdvanced = function(_, terms) advFor = terms end
  searchedFor = nil
  btnRow.buyBtn.OnClick(btnRow.buyBtn, "LeftButton")
  assert(advFor and #advFor == #expect and not searchedFor, "advanced search used when available")
  for i, t in ipairs(advFor) do
    assert(t.isExact and t.quantity == expect[i].qty and t.searchString == expect[i].name, "search term carries the quantity")
  end
  api.MultiSearchAdvanced = nil
  local name = "SkillRoute First Aid (steps)"
  assert(lists[name] and #lists[name] == #expect, "list created with the step's reagents")
  local qty1 = lists[name][1]
  btnRow.buyBtn.OnClick(btnRow.buyBtn, "LeftButton")
  assert(lists[name][1] == qty1, "clicking again updates, doesn't double: " .. tostring(lists[name][1]))
  local addedMsg = said
  btnRow.buyBtn.OnClick(btnRow.buyBtn, "RightButton")
  assert(lists[name] == nil, "right-click takes the step out (list empty, removed)")
  _G.print = saved[3]
  -- quantity check: per craft x (crafts + margin), rounded up, minus what you have
  local r = SkillRouteData.professions[129].recipes[st.spell]
  local z = Core.MarginZ(SkillRouteDB.settings.margin)
  local want = math.ceil(r.r[2] * (st.crafts + z * math.sqrt(st.var or 0)) - 1e-9)
  local got = tonumber(qty1:match(";(%d+)$"))
  assert(#expect ~= 1 or got == want - (Core.Have(r.r[1]) or 0) - (Core.HaveOnAlts(r.r[1]) or 0),
    ("quantity %s vs %d"):format(tostring(got), want))
  api.MultiSearchExact = nil
  fire("AUCTION_HOUSE_CLOSED")
  assert(not Core.ahOpen and not btnRow.buyBtn.shown, "buttons hidden once the AH closes")
  UI.Toggle()
  GetProfessions, GetProfessionInfo = saved[1], saved[2]
  SkillRouteDB = SkillRouteDB -- keep
  print("ah step button: " .. addedMsg)
end

-- what to do with crafted items: AH / disenchant / vendor, fresh AH prices only
do
  local D = SkillRouteData
  local pick
  for _, r in pairs(D.professions[197].recipes) do
    local d = r.out and D.disenchant.of[r.out]
    if d and d[2] <= 100 and D.items[r.out] and D.items[r.out][2] > 0 then pick = pick or r.out end
  end
  assert(pick, "a disenchantable Tailoring item")
  local d = D.disenchant.of[pick]
  local loot = D.disenchant.loot[d[1]]
  local savedAge = Auctionator.API.v1.GetAuctionAgeByItemID
  Auctionator.API.v1.GetAuctionAgeByItemID = function() return 0 end -- everything fresh
  local ev = 0
  for i = 1, #loot, 4 do prices[loot[i]] = 1000; ev = ev + loot[i + 1] / 100 * (loot[i + 2] + loot[i + 3]) / 2 * 1000 * 0.95 end
  prices[pick] = 1
  local a = Core.ItemAdvice(pick, 130)
  assert(a.de == math.floor(ev) and a.best == "de", ("disenchant wins: %s vs %d"):format(tostring(a.de), math.floor(ev)))
  assert(Core.ItemAdvice(pick, 0).de == nil, "no disenchant without the skill")
  prices[pick] = 10000000
  assert(Core.ItemAdvice(pick, 130).best == "ah", "a high AH price wins")
  -- results your Enchanting route still needs count at what you'd pay (no cut), up to the need
  do
    local n = 4
    local mat = loot[1]
    local total1 = n * loot[2] / 100 * (loot[3] + loot[4]) / 2
    local half = math.floor(total1 / 2)
    local withNeed = Core.ItemAdvice(pick, 130, n, { [mat] = half })
    local expect = 0
    for i = 1, #loot, 4 do
      local t = n * loot[i + 1] / 100 * (loot[i + 2] + loot[i + 3]) / 2
      local own = (loot[i] == mat) and math.min(t, half) or 0
      local buy = math.min(1000, (SkillRouteData.items[loot[i]] and SkillRouteData.items[loot[i]][3]) or 1000)
      expect = expect + own * buy + (t - own) * 1000 * 0.95
    end
    assert(withNeed.de == math.floor(expect / n), ("needed results at the buy price: %s vs %d"):format(tostring(withNeed.de), math.floor(expect / n)))
    assert(withNeed.de > Core.ItemAdvice(pick, 130, n).de, "needed by Enchanting -> disenchanting is worth more")
    assert(withNeed.deUsed and withNeed.deUsed[1].item == mat and withNeed.deUsed[1].units == half, "says what it counted")
    -- a big enough need makes disenchanting beat the vendor
    prices[pick] = nil
    local big = Core.ItemAdvice(pick, 130, n, { [loot[1]] = 999, [loot[5] or 0] = 999, [loot[9] or 0] = 999 })
    print(("disenchant for Enchanting: %d each (plain %d, vendor %d) -> %s"):format(big.de, Core.ItemAdvice(pick, 130, n).de, big.vendor, big.best))
    prices[pick] = 1
  end
  Auctionator.API.v1.GetAuctionAgeByItemID = function() return 5 end -- stale
  local stale = Core.ItemAdvice(pick, 130)
  assert(not stale.ah and not stale.de and stale.best == "vendor", "stale prices: no AH or disenchant advice")
  -- bags: the item shows in the shopping list's crafted section (fresh prices)
  Auctionator.API.v1.GetAuctionAgeByItemID = function() return 0 end
  prices[pick] = 1
  local savedC, savedCount = _G.C_Container, _G.GetItemCount
  _G.C_Container = { GetContainerNumSlots = function(b) return b == 0 and 2 or 0 end,
                     GetContainerItemID = function(b, s) if b == 0 and s == 1 then return pick end end }
  _G.GetItemCount = function(id, bank) if id == pick then return 3 end return savedCount(id, bank) end
  local saved = { GetProfessions, GetProfessionInfo }
  GetProfessions = function() return 1, 2 end
  GetProfessionInfo = function(i)
    if i == 1 then return "Tailoring", 0, 110, 150, 0, 0, 197 end
    return "Enchanting", 0, 130, 150, 0, 0, 333
  end
  local n1 = Core.EnchantingNeeds()
  assert(type(n1) == "table" and Core.EnchantingNeeds() == n1, "Enchanting needs cached until something changes")
  Core.InvalidatePatterns()
  local t0 = os.clock()
  assert(Core.EnchantingNeeds() ~= n1, "re-planned after a change")
  local t1 = os.clock()
  Core.Changed()
  Core.EnchantingNeeds()
  print(("enchanting needs: %.1f ms after a pattern change, %.1f ms after a price/bag change, 0 when cached"):format(
    (t1 - t0) * 1000, (os.clock() - t1) * 1000))
  local list = Core.CraftedAdvice(Core.Plan(197, 150))
  assert(list[1] and list[1].item == pick and list[1].count == 3 and list[1].advice.best == "de", "crafted item advice from the bags")
  UI.Toggle(197); UI.SetMode("shopping")
  local row
  for _, t in ipairs(texts) do
    local v = rawget(t, "text")
    if type(v) == "string" and v:find("Disenchant|r 3 x", 1, true) then row = v end
  end
  UI.SetMode("route"); UI.Toggle()
  assert(row, "shopping list shows 'Disenchant 3 x ...'")
  print("crafted advice: " .. row:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  _G.C_Container, _G.GetItemCount = savedC, savedCount
  GetProfessions, GetProfessionInfo = saved[1], saved[2]
  Auctionator.API.v1.GetAuctionAgeByItemID = savedAge
  for i = 1, #loot, 4 do prices[loot[i]] = nil end
  prices[pick] = nil
end

-- first-time tips: printed once per account
do
  assert(SkillRouteDB.tipsShown, "first-run tips were shown when the window first opened")
  local said = 0
  local realPrint = print
  _G.print = function() said = said + 1 end
  UI.Toggle(197); UI.Toggle()
  _G.print = realPrint
  assert(said == 0, "tips only once")
end

-- step tooltips: what to do with what the step makes (same advice as the shopping list)
do
  local saved = { GetProfessions, GetProfessionInfo }
  GetProfessions = function() return 1 end
  GetProfessionInfo = function() return "Tailoring", 0, 135, 225, 0, 0, 197 end
  UI.Toggle(197)
  local tipRow, tipOf
  for _, r in ipairs(UI.Rows()) do
    for _, l in ipairs(rawget(r, "tip") or {}) do
      if type(l) == "table" and l[1] == "Afterwards" and not tipRow then tipRow, tipOf = l, rawget(r, "tip") end
    end
  end
  UI.Toggle()
  assert(tipRow and tipRow[2]:find("each", 1, true), "step tooltip: Afterwards row")
  -- render it the way the game would: label | value lines
  local out = {}
  local savedTT = _G.GameTooltip
  _G.GameTooltip = { AddLine = function(_, t) out[#out + 1] = t end,
                     AddDoubleLine = function(_, a, b) out[#out + 1] = a .. "  |  " .. b end }
  UI.AddTipLines(tipOf)
  _G.GameTooltip = savedTT
  local strip = function(t) return (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
  local hasHeader, lastGap = false, false
  for i, t in ipairs(out) do
    if t == "SkillRoute" then hasHeader = true end
    assert(not (t == " " and lastGap), "no doubled blank lines")
    lastGap = t == " "
  end
  assert(hasHeader and out[#out] ~= " ", "header, and no blank line at the end")
  local bands = false
  for _, t in ipairs(out) do if strip(t):find("^Skill%-ups through  |  %d+ · %d+ · %d+") and t:find("|cffffff00%d+|r") then bands = true end end
  assert(bands, "Skill-ups shows the last level of each colour")
  print("step tooltip:\n    " .. table.concat((function() local t = {} for _, x in ipairs(out) do t[#t + 1] = strip(x) end return t end)(), "\n    "))
  GetProfessions, GetProfessionInfo = saved[1], saved[2]
end

-- a rank the character is too low-level for: the row warns (Artisan needs level 35)
do
  local saved = { GetProfessions, GetProfessionInfo, _G.UnitLevel }
  GetProfessions = function() return 1 end
  GetProfessionInfo = function() return "Tailoring", 0, 200, 225, 0, 0, 197 end
  _G.UnitLevel = function() return 29 end
  UI.Toggle(197)
  local warn
  for _, t in ipairs(texts) do
    local v = rawget(t, "text")
    if type(v) == "string" and v:find("needs character level 35 (you're 29)", 1, true) then warn = v end
  end
  UI.Toggle()
  assert(warn, "Artisan row warns about character level 35")
  local top, divider, foot
  for _, t in ipairs(texts) do
    local v = rawget(t, "text")
    if type(v) == "string" and v:find("You can level to 225 now; past it needs character level 35", 1, true) then top = v end
    if type(v) == "string" and v:find("After character level 35", 1, true) then divider = v end
    if type(v) == "string" and v:find("of it after level 35", 1, true) then foot = v end
  end
  assert(top and divider and foot, "header, divider row and footer split for the level stop")
  -- rows after the divider are faded, rows before aren't
  local seenDivider, fadedAfter, fadedBefore = false, 0, 0
  for _, r in ipairs(UI.Rows()) do
    if rawget(r, "shown") then
      local tx = r.text and rawget(r.text, "text") or ""
      if tostring(tx):find("After character level", 1, true) then seenDivider = true
      elseif rawget(r, "alpha") and rawget(r, "alpha") < 1 then
        if seenDivider then fadedAfter = fadedAfter + 1 else fadedBefore = fadedBefore + 1 end
      end
    end
  end
  assert(fadedAfter > 0 and fadedBefore == 0, ("faded after the divider only (%d after, %d before)"):format(fadedAfter, fadedBefore))
  print("level stop: " .. top:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. " | " .. foot:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  print("rank level warning: " .. warn:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  GetProfessions, GetProfessionInfo, _G.UnitLevel = saved[1], saved[2], saved[3]
end

-- /sr log: records trainers, vendors, disenchants, fishing, boats; steps tick off
do
  local Rec = ns.Recorder
  local clock = 50000
  local savedTime, savedGuid, savedCount = _G.GetTime, _G.UnitGUID, _G.GetItemCount
  _G.GetTime = function() return clock end
  _G.UnitGUID = function() return "Creature-0-1-0-1-4576-0000" end
  _G.strsplit = _G.strsplit or function(sep, str)
    local t = {}
    for part in (str .. sep):gmatch("(.-)" .. sep:gsub("%-", "%%-")) do t[#t + 1] = part end
    return unpack(t)
  end
  _G.ERR_FISH_ESCAPED, _G.ERR_FISH_NOT_HOOKED = "Your fish got away!", "No fish are hooked."
  local saved = { GetProfessions, GetProfessionInfo }
  GetProfessions = function() return 1, 2, 3 end
  GetProfessionInfo = function(i)
    if i == 1 then return "Tailoring", 0, 130, 150, 0, 0, 197 end
    if i == 2 then return "Enchanting", 0, 130, 150, 0, 0, 333 end
    return "Fishing", 0, 60, 75, 0, 0, 356
  end
  local said = {}
  local realPrint = print
  _G.print = function(m) said[#said + 1] = m end
  SlashCmdList.SKILLROUTE("log on")
  local rf
  for _, fr in ipairs(frames) do local e = rawget(fr, "events"); if e and e.LOOT_READY then rf = fr end end
  assert(rf and SkillRouteDB.log.on, "recorder on, events registered")
  local function fireR(ev, ...) rf.OnEvent(rf, ev, ...) end
  assert(Rec.Current().id == "trainer", "first step: the trainer")
  -- trainer window (Josef): services recorded
  fireR("TRAINER_SHOW")
  -- second trainer
  fireR("TRAINER_SHOW")
  fireR("GOSSIP_SHOW")
  assert(SkillRouteDB.log.done.trainer and SkillRouteDB.log.done.trainer2, "trainer steps done")
  -- vendor
  fireR("MERCHANT_SHOW")
  assert(SkillRouteDB.log.done.vendor, "vendor step done")
  -- disenchant: item 7051 leaves the bags, loot recorded
  local bag = { [1] = 7051 }
  local savedC = _G.C_Container
  _G.C_Container = { GetContainerNumSlots = function(b) return b == 0 and 1 or 0 end,
                     GetContainerItemID = function(b, sl) return b == 0 and bag[sl] or nil end }
  local have = 1
  _G.GetItemCount = function(id, bank) if id == 7051 then return have end return savedCount(id, bank) end
  _G.GetItemInfo = function(id) if id == 7051 then return "Earthen Vest", nil, 2, 22, 0, "Armor", "Cloth", 1, "", 0, 0, 4 end end
  _G.GetNumLootItems = function() return 1 end
  _G.GetLootSlotLink = function() return "|Hitem:10940::|h" end
  _G.GetLootSlotInfo = function() return nil, "Strange Dust", 3 end
  _G.IsFishingLoot = function() return false end
  fireR("UNIT_SPELLCAST_SENT", "player", "Earthen Vest", "guid", 13262)
  fireR("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 13262)
  have = 0; bag[1] = nil
  fireR("LOOT_READY")
  local de
  for _, e in ipairs(SkillRouteDB.log.entries) do if e.kind == "disenchant" then de = e end end
  assert(de and de.item == 7051 and de.ilvl == 22 and de.loot[1][1] == 10940 and de.loot[1][2] == 3,
    "disenchant recorded: item, item level, results")
  assert(SkillRouteDB.log.done.disenchant, "disenchant step done")
  -- skill too low: the error text is kept
  clock = clock + 5
  fireR("UNIT_SPELLCAST_SENT", "player", "Big Vest", "g2", 13262)
  fireR("UI_ERROR_MESSAGE", 50, "Requires Enchanting (150)")
  assert(SkillRouteDB.log.done.deskill, "disenchant skill error recorded")
  -- fishing: a cast, a catch, a fish that got away
  local fishSpell = SkillRouteData.professions[356].spell
  _G.GetSpellInfo = function(id) if id == fishSpell or id == 7620 then return "Fishing" end end
  clock = clock + 5
  fireR("UNIT_SPELLCAST_CHANNEL_START", "player", "g3", 7620)
  _G.IsFishingLoot = function() return true end
  fireR("LOOT_READY")
  fireR("UNIT_SPELLCAST_CHANNEL_START", "player", "g4", 7620)
  fireR("UI_ERROR_MESSAGE", 51, "Your fish got away!")
  local fz
  for _, f in pairs(SkillRouteDB.log.fishing) do fz = f end
  assert(fz and fz.casts == 2 and fz.caught == 1 and fz.away == 1, "fishing counted per zone")
  -- disenchant5 / fish need more; skip them, then the boat
  SlashCmdList.SKILLROUTE("log skip") -- disenchant5
  SlashCmdList.SKILLROUTE("log skip") -- fish (20 casts)
  assert(Rec.Current().id == "boat", "next: boat (Felwood n/a without Herbalism): " .. tostring(Rec.Current() and Rec.Current().id))
  SlashCmdList.SKILLROUTE("log boat")
  clock = clock + 356
  SlashCmdList.SKILLROUTE("log boat")
  assert(SkillRouteDB.log.done.boat and Rec.Current() == nil, "boat done: all checks done")
  local allDone = false
  for _, m in ipairs(said) do if tostring(m):find("all checks done", 1, true) then allDone = true end end
  assert(allDone, "says what to send when everything's done")
  SlashCmdList.SKILLROUTE("log off")
  assert(not SkillRouteDB.log.on, "log off")
  _G.print = realPrint
  print(("recorder: %d entries, steps ticked in order; last message: %s"):format(#SkillRouteDB.log.entries,
    tostring(said[#said - 1]):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
  _G.C_Container, _G.GetItemCount, _G.GetTime, _G.UnitGUID = savedC, savedCount, savedTime, savedGuid
  _G.GetItemInfo = function() return nil end
  GetProfessions, GetProfessionInfo = saved[1], saved[2]
  SkillRouteDB.log = nil
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
  -- the two reworded sliders: their blue examples follow the slider and flip where the planner does
  assert(O.FewerExample(0):find("^Off"), O.FewerExample(0))
  assert(O.FewerExample(5):find("still") and O.FewerExample(5):find("10s to you"), O.FewerExample(5))
  assert(O.FewerExample(10):find("about even"), O.FewerExample(10))
  assert(O.FewerExample(44):find("orange 50s recipe") and O.FewerExample(44):find("88s to you"), O.FewerExample(44))
  assert(O.FewerExample(100):find("2g to you"), O.FewerExample(100))
  -- safety margin example: the same mean + z x sd the shopping list buys (20 crafts, sd sqrt 20)
  assert(O.MarginExample(50):find("enough for 20, the expected amount%. Runs short about half the time"), O.MarginExample(50))
  assert(O.MarginExample(75):find("enough for 24%. Runs short about 1 time in 4"), O.MarginExample(75))
  assert(O.MarginExample(90):find("enough for 26%. Runs short about 1 time in 10"), O.MarginExample(90))
  assert(O.MarginExample(99):find("enough for 31%. Runs short about 1 time in 100"), O.MarginExample(99))
  assert(O.MarginExample(93):find("7 times in 100"), O.MarginExample(93))
  assert(O.ResaleExample(0) == "Off: only what you spend counts.")
  assert(O.ResaleExample(45):find("counts as 13s %(30s minus 17s back%)"), O.ResaleExample(45))
  assert(O.ResaleExample(80):find("pays for itself"), O.ResaleExample(80))
  local moved = 0
  for _, f in ipairs(frames) do
    local h = rawget(f, "OnValueChanged")
    if h then
      h(f, 44)
      moved = moved + 1
    end
  end
  assert(moved >= 3, "sliders built: " .. moved)
  local seen88, seenOrange
  for _, fs in ipairs(texts) do
    if type(fs.text) == "string" and fs.text:find("88s to you") then seen88 = true end
    if fs.text == "up to 44s" then seenOrange = true end
  end
  assert(seen88 and seenOrange, "dragging Prefer fewer crafts to 44s rewrites its value and example")
  SkillRouteDB.settings.craftValue, SkillRouteDB.settings.resale = nil, nil
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

-- Fishing: route + Expert book (Old Man Heming sells to both factions) + Artisan quest
do
  local book = Core.RankBook(356, 3)
  assert(book and book.name:find("Expert Fishing") and book.loc and book.loc.npc == "Old Man Heming", "fishing book vendor")
  local q = Core.RankQuest(356, 4)
  assert(q and q.title == "Nat Pagle, Angler Extreme", "fishing Artisan quest")
  local saved = { GetProfessions, GetProfessionInfo }
  GetProfessions = function() return 1 end
  GetProfessionInfo = function() return "Fishing", 0, 100, 150, 0, 0, 356 end
  UI.Toggle(356)
  local row
  for _, t in ipairs(texts) do local v = rawget(t, "text"); if type(v) == "string" and v:find("catches", 1, true) and v:find("~") then row = v end end
  assert(row, "fishing rows")
  UI.Toggle()
  GetProfessions, GetProfessionInfo = saved[1], saved[2]
  print(("Fishing: Expert book from %s, Artisan quest '%s' from %s"):format(book.loc.npc, q.title, q.loc.npc))
end

-- Cooking with nothing on the AH: farmable ingredients make the route possible,
-- shown as "Farm ..." and not counted in what you spend
do
  local savedPrices = {}
  for k, v in pairs(prices) do savedPrices[k] = v; prices[k] = nil end
  local saved = { GetProfessions, GetProfessionInfo }
  GetProfessions = function() return 1 end
  GetProfessionInfo = function() return "Cooking", 0, 1, 75, 0, 0, 185 end
  local plan = Core.Plan(185, 75)
  assert(#plan.steps > 0 and #plan.gaps == 0, "cooking planned from farmable ingredients")
  local farmRows, spent = 0, 0
  for _, b in ipairs(plan.shopping.buy) do
    if b.farm then farmRows = farmRows + 1 else spent = spent + (b.price or 0) * b.buy end
  end
  assert(farmRows > 0, "farm rows in the shopping list")
  assert(math.abs(plan.total - spent) < 1, "farmed items not counted in 'Buy for'")
  local first
  for _, b in ipairs(plan.shopping.buy) do if b.farm then first = b break end end
  print(("cooking 1-75 without AH prices: %d steps, %d farm rows, e.g. Farm %d x %s: %s"):format(
    #plan.steps, farmRows, first.buy, first.name, Core.FarmText(first.item)))
  GetProfessions, GetProfessionInfo = saved[1], saved[2]
  for k, v in pairs(savedPrices) do prices[k] = v end
end

local Data = SkillRouteData
-- Farm zones sorted by faction (harness player is Horde): Alliance land last and marked,
-- and it only sets the cost when no Horde or contested zone has the item
do
  local marked, checked = 0, 0
  for item, src in pairs(Data.farm) do
    local seenEnemy = false
    for line in (Core.FarmText(item, true) .. "\n"):gmatch("(.-)\n") do
      local enemy = line:find("(Alliance)", 1, true) ~= nil
      assert(not line:find("(Horde)", 1, true), "own faction is never marked")
      assert(enemy or not seenEnemy, "Alliance zones come after the others: " .. item)
      seenEnemy = seenEnemy or enemy
      if enemy then marked = marked + 1 end
    end
    local bestOk, bestAny = math.huge, math.huge
    for _, s in ipairs(src) do
      local z, c = s[1] == "m" and s[3] or s[2], s[1] == "m" and s[4] or s[3]
      if c > 0 then
        bestAny = math.min(bestAny, 100 / c)
        if Data.zoneSide[z] ~= "A" then bestOk = math.min(bestOk, 100 / c) end
      end
    end
    local want = (bestOk < math.huge and bestOk or bestAny) * 25
    assert(math.abs(Core.FarmCost(item) - want) < 1e-6, "farm cost uses Horde/contested zones first: " .. item)
    checked = checked + 1
  end
  local t = Core.FarmText(723)
  assert(not t:find("^Goretusk"), "Westfall (Alliance) isn't listed first for Horde: " .. t)
  print(("farm zones by faction: %d items, %d Alliance-zone sources marked and listed last; Horde sees 723 as: %s")
    :format(checked, marked, t))
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
