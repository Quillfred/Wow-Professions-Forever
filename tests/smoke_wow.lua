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
for _, f in ipairs({ "Data", "Planner", "Core", "UI" }) do
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
  assert(loc and loc.side:find("H") and loc.zone == "Undercity" and loc.ui == 1458 and loc.x == 70.8,
    "nearest Horde Expert trainer, zone from the game: " .. tostring(loc and loc.npc))
  print("nearest Expert Tailoring trainer (Horde): " .. loc.npc .. ", " .. Core.Where(loc))
  -- the game wants the axes the other way round: detected via the continent check
  wantSwap = true
  for k in pairs(D.npcs) do end
  local fresh = Core.NPCLocation(2668) -- not resolved before
  assert(fresh and fresh.zone == "Undercity", "axis order detected")
  -- Alliance-only vendor never offered to Horde
  local v = Core.NearestVendor(SkillRouteData.professions[197].recipes[select(1, (function()
    for sp, r in pairs(SkillRouteData.professions[197].recipes) do if r.n == "Bright Yellow Shirt" then return sp end end end)())].pat[1])
  assert(v == nil, "Bright Yellow Shirt: no Horde vendor")
  -- TomTom waypoint
  local got
  _G.TomTom = { AddWaypoint = function(self, ui, x, y, opts) got = { ui, x, y, opts.title } end }
  Core.Waypoint(loc)
  assert(got and got[1] == 1458 and math.abs(got[2] - 0.708) < 1e-9 and got[4] == loc.npc, "TomTom waypoint")
  _G.TomTom = nil
end
print("SMOKE TEST PASSED")
