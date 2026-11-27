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
    if k == "SetWidth" then return function(self, w) rawset(self, "width", w) end end
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
_G.date = os.date
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
for _, f in ipairs({ "Data", "Planner", "Core", "Prices", "Arrow", "UI", "MiniPanel", "TrainerPanel", "Helpers", "BuyPanel", "Tooltip", "Options", "Recorder", "Check" }) do
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
assert(next(plan.unpricedItems), "the reagents with no price are named")
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
-- the mini panel docks to the profession window by default, instead of the full window
do
  local M = ns.Mini
  fire("TRADE_SKILL_SHOW")
  assert(M.IsShown() and not UI.IsShown(), "mini panel, not the full window")
  local main, head, costR
  for _, t in ipairs(texts) do
    local v = rawget(t, "text")
    if type(v) == "string" then
      if v:find("^Craft |cffffffff%d+ x|r") or v:find("^|cffffd100Train") or v:find("^|cffffd100Buy") then main = v end
      if v:find("steps? left$") then head = v end
    end
  end
  assert(main and head, "next step and steps left shown: " .. tostring(main) .. " / " .. tostring(head))
  local plan = Core.Plan(197, Core.Char().targets[197] or 300)
  local e = M.Entries(plan)
  assert(#e > 2 and e[1].text, "route entries")
  local kinds = {}
  for _, x in ipairs(e) do kinds[x.kind] = true end
  assert(kinds.craft and kinds.rank, "crafts and rank-ups in order")
  local rankE
  for _, x in ipairs(e) do if x.kind == "rank" then rankE = x; break end end
  assert(rankE.loc and rankE.loc.npc, "a rank-up step knows where to go (click: waypoint)")
  local ann = Core.NPCLocation(11073)
  ann.note = SkillRouteData.npcNotes[11073]
  local w = Core.Where(ann)
  assert(ann.cx and w and w:find("Uldaman entrance", 1, true), "Annora: placed at the Uldaman entrance: " .. tostring(w))
  -- an unlearned step: the mini panel says exactly what the full route says
  local learnStep
  for _, x in ipairs(e) do if x.kind == "craft" and x.st.learn then learnStep = x.st; break end end
  assert(learnStep, "the test route has a step to learn")
  local _, _, _, learnText = UI.StepTip(plan, learnStep)
  local note = M.LearnNote(plan, learnStep)
  assert(learnText ~= "" and note == UI.Plain(learnText) and not note:find("|c", 1, true),
    "mini matches the full route: " .. tostring(note) .. " vs " .. tostring(learnText))
  print("mini = full route: " .. note)
  M.Refresh() -- live update path runs
  SkillRouteDB.lastError = nil
  local after, short
  for _, t in ipairs(texts) do
    local v = rawget(t, "text")
    if type(v) == "string" and v:find("Afterwards:", 1, true) then after = v end
    if type(v) == "string" and v:find("This step: buy", 1, true) then short = v end
  end
  assert(after or e[1].kind ~= "craft", "Afterwards line on a craft step")
  -- the test data's first step is a craft you're short for: this must run, not skip
  assert(e[1].kind == "craft" and short and short:find("This step: buy %d"), "buy line on the step: " .. tostring(short))
  do
    local list = Core.StepShopping(Core.Plan(197, 300), e[1].st)
    local n = tonumber(short:match("This step: buy (%d+)"))
    assert(#list == 1 and list[1].qty == n, "the panel's amount is what Buy sends: " .. n .. " vs " .. tostring(list[1] and list[1].qty))
    -- moving the safety margin slider changes it straight away
    ns.Options.Set("margin", 50)
    M.Refresh()
    local n50
    for _, t in ipairs(texts) do local v = rawget(t, "text"); if type(v) == "string" and v:find("This step: buy %d+") and v:find("50%% sure") then n50 = tonumber(v:match("This step: buy (%d+)")) end end
    assert(n50 and n50 < n, "50% sure buys less: " .. tostring(n50) .. " < " .. n)
    ns.Options.Set("margin", nil)
    print(("safety margin: 90%% sure -> buy %d, 50%% sure -> buy %d"):format(n, n50))
  end
  -- several things to buy: the price first, on one line, no dangling "buy"
  do
    local savedSS = Core.StepShopping
    Core.StepShopping = function() return { { item = 4306, qty = 188, name = "Silk Cloth" }, { item = 6260, qty = 20, name = "Blue Dye" } } end
    local savedCBH = Core.CanBuyHere
    local multi, fsAway, fsAH
    for _, atAH in ipairs({ false, true }) do
      Core.CanBuyHere = function() return atAH end
      M.Refresh()
      for _, t in ipairs(texts) do
        local v = rawget(t, "text")
        if type(v) == "string" and v:find("This step:", 1, true) then multi = v; if atAH then fsAH = rawget(t, "width") else fsAway = rawget(t, "width") end end
      end
    end
    Core.CanBuyHere = savedCBH
    -- away from the AH (no Buy button) the line gets the whole width
    assert(fsAway == 246 and fsAH == 180, "width: " .. tostring(fsAway) .. " away, " .. tostring(fsAH) .. " at the AH")
    Core.StepShopping = savedSS
    M.Refresh()
    assert(multi and multi:find("This step:|r ~", 1, true) and multi:find("on the AH (90% sure)", 1, true)
      and not multi:find("buy|r", 1, true), "multi-item line: " .. tostring(multi))
  end
  -- vendor or AH: a vendor item the AH sells cheaper is bought there, and its row says so
  do
    local vItem
    for id, x in pairs(SkillRouteData.items) do if x[3] and x[3] > 10 then vItem = id; break end end
    local savedP = prices[vItem]
    prices[vItem] = nil
    assert(Core.FromVendor(vItem), "no AH price: the vendor")
    prices[vItem] = SkillRouteData.items[vItem][3] - 5
    assert(not Core.FromVendor(vItem), "cheaper on the AH: the AH")
    prices[vItem] = SkillRouteData.items[vItem][3] + 5
    assert(Core.FromVendor(vItem), "dearer on the AH: the vendor")
    prices[vItem] = savedP
    assert(not Core.FromVendor(4306), "not sold by vendors: never the vendor")
  end
  -- hovering the step shows the full route's tooltip
  local hit
  for _, f in ipairs(frames) do if rawget(f, "OnEnter") and rawget(f, "OnClick") and not rawget(f, "events") then hit = f end end
  local ok, r, tip = pcall(UI.StepTip, Core.Plan(197, 300), (function() for _, x in ipairs(e) do if x.kind == "craft" then return x.st end end end)())
  assert(ok and tip and #tip > 3, "step tooltip builds for the mini panel: " .. tostring(r))
  assert(not SkillRouteDB.lastError, tostring(SkillRouteDB.lastError))
  print("mini panel extras: " .. (after or "?"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. (short and ("; " .. short:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) or ""))
  print(("mini panel: %s  |  %s  |  then: %s"):format(main:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), head, e[2].text))
  -- a tool two steps need shows once, and its Buy covers the tool's materials
  local R = SkillRouteData.professions[197].recipes
  local tspell, tr
  for id, x in pairs(R) do if x.r and x.out and #x.r >= 2 then tspell, tr = id, x; break end end
  local u = { craftSpell = tspell, item = tr.out, learnHow = "trainer" }
  local fake = { max = 300, line = 197, shopping = { craft = {} }, steps = {
    { from = 150, to = 155, spell = tspell, name = "a", crafts = 3, tools = { u } },
    { from = 155, to = 160, spell = tspell, name = "b", crafts = 3, tools = { u } } } }
  local te = M.Entries(fake)
  local tools = 0
  for _, x in ipairs(te) do if x.kind == "tool" then tools = tools + 1 end end
  assert(tools == 1 and te[1].kind == "tool" and te[1].buy and te[1].buy.crafts == 1, "tool once, with a Buy step")
  local tl = Core.StepShopping(fake, te[1].buy)
  assert(type(tl) == "table", "tool materials for Auctionator")
  -- the full window, opened with Full route, follows a switch of profession
  UI.Toggle(197); assert(UI.IsShown())
  UI.AutoOpen(182) -- the test character's other profession
  local follows
  for _, t in ipairs(texts) do if rawget(t, "text") == "Herbalism" then follows = true end end
  assert(follows, "full window switched to the profession you opened")
  UI.AutoOpen(197); UI.Toggle()
  fire("TRADE_SKILL_CLOSE")
  SkillRouteDB.settings.mini = false -- the rest checks the full window's auto-open
end
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
SkillRouteDB.settings.mini = nil
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
  prices[1], prices[2] = 100, 100
  Auctionator.API.v1.GetAuctionAgeByItemID = function(_, id) return id == 1 and 0 or 5 end
  assert(Core.AHFresh(1) and not Core.AHFresh(2), "seen today: fresh; 5 days ago: not")
  Auctionator.API.v1.GetAuctionAgeByItemID = nil
  assert(Core.AHFresh(2), "no age API: don't block")
  assert(not Core.AHFresh(3), "no AH price at all: not on the AH")
  prices[1], prices[2] = nil, nil
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
  -- the alternatives it was compared with: one per line (keeps the tooltip narrow)
  local nCompared = 0
  for _, l in ipairs(tipOf) do
    if type(l) == "table" and l.sub and (l[1] == "compared" or (nCompared > 0 and l[1] == "")) then
      assert(not tostring(l[2]):find(" · ", 1, true), "one alternative per line: " .. tostring(l[2]))
      nCompared = nCompared + 1
    end
  end
  assert(nCompared >= 2, "compared with two alternatives, on two lines: " .. nCompared)
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
  assert(moved >= 4, "sliders built: " .. moved)
  assert(SkillRouteDB.settings.crowded == 45, "the crowded slider sets its setting (44 -> step 45): " .. tostring(SkillRouteDB.settings.crowded))
  local seen88, seenOrange
  for _, fs in ipairs(texts) do
    if type(fs.text) == "string" and fs.text:find("88s to you") then seen88 = true end
    if fs.text == "up to 44s" then seenOrange = true end
  end
  assert(seen88 and seenOrange, "dragging Prefer fewer crafts to 44s rewrites its value and example")
  SkillRouteDB.settings.craftValue, SkillRouteDB.settings.resale, SkillRouteDB.settings.crowded = nil, nil, nil
  -- the full route window steps aside while the options are open, then comes back
  O.Toggle() -- close first
  UI.Toggle(197); assert(UI.IsShown())
  -- the shopping list says what "need" and "expected" mean, with your margin
  UI._state.mode = "shopping"; UI.Refresh()
  local legend
  for _, t in ipairs(texts) do local v = rawget(t, "text"); if type(v) == "string" and v:find("need: covers bad luck", 1, true) then legend = t end end
  local m = SkillRouteDB.settings.margin or 90
  assert(legend and legend.text:find(m .. "% sure", 1, true) and legend.shown, "shopping legend: " .. tostring(legend and legend.text))
  UI._state.mode = "route"; UI.Refresh()
  assert(not legend.shown, "route view: no legend")
  O.Toggle(); assert(O.IsShown() and not UI.IsShown(), "route window hidden while options are open")
  O.Toggle(); assert(not O.IsShown() and UI.IsShown(), "and back when they close")
  UI.Toggle(); assert(not UI.IsShown())
  O.Toggle(); O.Toggle(); assert(not UI.IsShown(), "a closed route window stays closed")
  SkillRouteDB.settings.mini = false
  fire("TRADE_SKILL_SHOW"); assert(UI.IsShown(), "opened with the profession window")
  O.Toggle(); fire("TRADE_SKILL_CLOSE"); O.Toggle()
  assert(not UI.IsShown(), "profession window closed meanwhile: the route window doesn't come back")
  SkillRouteDB.settings.mini = nil
  O.Toggle()
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

-- SkillRoute's own AH scan, freshest price wins, and what you paid
do
  local P = ns.Prices
  local queue, savedAfter = {}, C_Timer.After
  C_Timer.After = function(_, f) queue[#queue + 1] = f end
  local function run() for _ = 1, 50 do local f = table.remove(queue, 1); if not f then return end; f() end end
  _G.hooksecurefunc = function(t, name, fn)
    local orig = t[name]
    t[name] = function(...) local r = orig(...); fn(...); return r end
  end
  local money = 100000
  _G.GetMoney = function() return money end
  local results = { { itemKey = { itemID = 2589 }, minPrice = 50, totalQuantity = 30 }, { itemKey = { itemID = 2589 }, minPrice = 40, totalQuantity = 12 },
                    { itemKey = { itemID = 4306 }, minPrice = 300, totalQuantity = 7 } }
  local full, sent = false, 0
  _G.C_AuctionHouse = {
    SendBrowseQuery = function() sent = sent + 1; full = false end,
    GetBrowseResults = function() return results end,
    RequestMoreBrowseResults = function() full = true end,
    HasFullBrowseResults = function() return full end,
    IsThrottledMessageSystemReady = function() return true end,
    StartCommoditiesPurchase = function() end,
    ConfirmCommoditiesPurchase = function() end,
  }
  local pf
  for _, f in ipairs(frames) do local e = rawget(f, "events"); if e and e.AUCTION_HOUSE_BROWSE_RESULTS_ADDED then pf = f end end
  assert(pf, "price events registered")
  local function fireP(ev, ...) pf.OnEvent(pf, ev, ...) end
  local realPrint = print; local said = {}
  _G.print = function(s) said[#said + 1] = tostring(s) end

  assert(not P.Scan(), "no scan with the AH closed")
  _G.AuctionHouseFrame = stubObj()
  fire("AUCTION_HOUSE_SHOW"); fireP("AUCTION_HOUSE_SHOW")
  local scanBtn
  for _, f in ipairs(frames) do if f.text == "SkillRoute: Scan AH" then scanBtn = f end end
  assert(scanBtn, "Scan button on the auction house window")
  assert(P.Scan() and P.Scanning(), "scan starts at the AH")
  assert(scanBtn.text == "Scanning...", "button shows progress: " .. tostring(scanBtn.text))
  run(); assert(sent == 1, "one browse search for the whole AH")
  fireP("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") -- first page: asks for more
  assert(full, "asked for the next page")
  assert(scanBtn.text == "Scanning 3", "short progress label: " .. tostring(scanBtn.text))
  fireP("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")   -- all in: stored
  run()
  assert(not P.Scanning(), "scan finished")
  assert(scanBtn.text == "SkillRoute: Scan AH", "button back to Scan AH")
  local b = P.Book()
  assert(b.items[2589] == 40 and b.items[4306] == 300 and b.count == 2, "lowest price per item kept")
  assert(b.listed[2589] == 42 and P.Listed(4306) == 7, "how many are listed, all versions together")
  assert(Core.PriceSource():find("SkillRoute scan"), Core.PriceSource())

  -- freshest wins: same day and Auctionator's time unknown -> ours; older ours -> Auctionator
  assert(P.Freshest(2589, 99, 0) == 40)
  assert(P.Freshest(2589, 99, nil) == 40, "Auctionator age unknown: ours (exact time)")
  b.t = time() - 3 * 86400
  assert(P.Freshest(2589, 99, 0) == 99, "Auctionator's newer price wins")
  assert(P.Freshest(2589, nil, nil) == 40, "only ours")
  b.t = time()

  -- a search of your own mid-scan stops it; nothing saved
  results = { { itemKey = { itemID = 2589 }, minPrice = 1 } }
  assert(P.Scan()); run()
  C_AuctionHouse.SendBrowseQuery({ searchString = "linen" })
  assert(not P.Scanning(), "stopped by another search")
  assert(b.items[2589] == 40, "nothing saved from a stopped scan")
  -- an empty search (Auctionator's full scan) doesn't stop it; closing the AH does
  assert(P.Scan()); run()
  C_AuctionHouse.SendBrowseQuery({ searchString = "" })
  assert(P.Scanning(), "empty search carries on")
  fireP("AUCTION_HOUSE_CLOSED")
  assert(not P.Scanning() and b.items[2589] == 40, "closing the AH cancels")

  -- the AH's "ready" event sends the next page at once; then the second pass prices the
  -- amount your routes need along the price ladder
  local isReady, searched = true, nil
  C_AuctionHouse.IsThrottledMessageSystemReady = function() return isReady end
  C_AuctionHouse.MakeItemKey = function(id) return { itemID = id } end
  local looked = {}
  C_AuctionHouse.GetItemKeyInfo = function(k) looked[k.itemID] = true; return { isCommodity = true } end
  C_AuctionHouse.SendSearchQuery = function(key) assert(looked[key.itemID], "item info asked before searching"); searched = key.itemID end
  local ladder = { { unitPrice = 60, quantity = 50 }, { unitPrice = 40, quantity = 2 } }
  C_AuctionHouse.GetNumCommoditySearchResults = function() return #ladder end
  C_AuctionHouse.GetCommoditySearchResultInfo = function(_, i) return ladder[i] end
  local savedBuy = Core.BuyList
  Core.BuyList = function() return { [2589] = 10 } end
  results = { { itemKey = { itemID = 2589 }, minPrice = 40 } }
  fire("AUCTION_HOUSE_SHOW")
  said = {}
  local savedCItem, loaded = _G.C_Item, {}
  _G.C_Item = setmetatable({ RequestLoadItemDataByID = function(id) loaded[id] = true end,
                             IsItemDataCachedByID = function(id) return loaded[id] or false end }, { __index = savedCItem })
  assert(P.Scan()); run()
  assert(loaded[2589], "materials asked to load at the start of the scan")
  isReady = false
  fireP("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") -- wants the next page, AH not ready
  assert(not full, "waits for the AH")
  isReady = true
  fireP("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
  assert(full, "sent as soon as the AH said it's ready")
  fireP("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
  do local q = queue; queue = {}; for _, f in ipairs(q) do f() end end -- the short pause (not the timeouts)
  assert(P.Scanning() and searched == 2589, "second pass searches the material")
  assert(scanBtn.text == "Pricing 1/1", "button: " .. tostring(scanBtn.text))
  fireP("COMMODITY_SEARCH_RESULTS_UPDATED", 2589); run()
  assert(not P.Scanning(), "done")
  assert(P.Own(2589) == 56, "10 priced along the ladder: 2 at 40s + 8 at 60s = 56 each: " .. tostring(P.Own(2589)))
  assert(P.CostFor({ { 10, 1 } }, 3) == 10, "beyond what's listed: at the dearest price")
  local line = said[#said] or ""
  assert(line:find("pages:") and line:find("1 of 1 materials priced for the amounts you need"), line)
  local pi2 = Core.PriceInfo(2589)
  assert(pi2.ah == 56 and pi2.cheapest == 40 and pi2.forN == 10, "tooltip shows the amount and the cheapest")
  -- a dropped search is sent again; a material with no answer is retried once, and an
  -- answer that came without the event is read at the timeout
  Core.BuyList = function() return { [2589] = 10, [4306] = 5 } end
  results = { { itemKey = { itemID = 2589 }, minPrice = 40 }, { itemKey = { itemID = 4306 }, minPrice = 300 } }
  local sends = {}
  C_AuctionHouse.SendSearchQuery = function(key) sends[#sends + 1] = key.itemID end
  local silent = {} -- item -> ladder the AH holds without firing the event
  C_AuctionHouse.GetNumCommoditySearchResults = function(id) return silent[id] and #silent[id] or 0 end
  C_AuctionHouse.GetCommoditySearchResultInfo = function(id, i) return silent[id][i] end
  queue = {}
  assert(P.Scan()); run()
  fireP("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"); fireP("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
  do local q = queue; queue = {}; for _, f in ipairs(q) do f() end end
  assert(sends[1] == 2589, "first material searched")
  fireP("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")
  assert(sends[2] == 2589, "dropped search sent again")
  silent[2589] = { { unitPrice = 45, quantity = 99 } }
  -- the timeouts: answer was there without the event -> used; next material no answer at all
  local function timeouts() local q = queue; queue = {}; for _, f in ipairs(q) do f() end end
  local function until_(cond) for _ = 1, 30 do if cond() then return true end; timeouts() end return cond() end
  assert(until_(function() return sends[#sends] == 4306 end) and P.Own(2589) == 45,
    "answer read without its event, then the next material after a pause: " .. tostring(P.Own(2589)))
  assert(until_(function() return #sends == 4 end) and sends[4] == 4306, "no answer: retried once")
  assert(until_(function() return not P.Scanning() end), "then skipped and finished")
  assert(said[#said]:find("1 of 2 materials") and said[#said]:find("1 retried"), said[#said])
  -- an error inside the second pass stops it with a message (never stuck at "Pricing 1/N")
  Core.BuyList = function() return { [2589] = 10 } end
  results = { { itemKey = { itemID = 2589 }, minPrice = 40 } }
  local savedMake = C_AuctionHouse.MakeItemKey
  C_AuctionHouse.MakeItemKey = function() error("Usage: bad argument") end
  SkillRouteDB.lastError = nil
  assert(P.Scan()); run()
  fireP("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"); fireP("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
  do local q = queue; queue = {}; for _, f in ipairs(q) do f() end end -- the pause, then the failing search
  assert(not P.Scanning() and said[#said]:find("stopped on an error"), "error: scan stops: " .. tostring(said[#said]))
  assert(SkillRouteDB.lastError and SkillRouteDB.lastError:find("second pass"), "and /sr check has it")
  SkillRouteDB.lastError = nil
  C_AuctionHouse.MakeItemKey = savedMake
  -- a material that never answers and never times out: the watchdog stops it after 15 s
  local clock = 1000
  local savedGT = _G.GetTime
  _G.GetTime = function() return clock end
  C_AuctionHouse.SendSearchQuery = function() end
  silent = {}
  local savedAfter2 = C_Timer.After
  local slow = {}
  C_Timer.After = function(d, f) if d >= 1 and d < 5 then slow[#slow + 1] = f else queue[#queue + 1] = { d, f } end end
  queue = {}
  assert(P.Scan())
  local function step() local q = queue; queue = {}; for _, x in ipairs(q) do clock = clock + (x[1] or 0); x[2]() end end
  step()
  fireP("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"); fireP("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
  for _ = 1, 10 do if not P.Scanning() then break end; step() end
  assert(not P.Scanning() and said[#said]:find("stalled on material 1"), "watchdog: " .. tostring(said[#said]))
  C_Timer.After, _G.GetTime = savedAfter2, savedGT
  queue = {}
  C_Timer.After = function(_, f) queue[#queue + 1] = f end

  -- the diagnostic log: /sr scanlog sums it up
  local log = P.ScanLogLines()
  local joined = table.concat(log, "\n")
  assert(joined:find("by AH ready at send", 1, true) and joined:find("events after first tries that failed", 1, true)
    and #SkillRouteDB.scanLog.items >= 1, joined)
  realPrint("scanlog sample:\n  " .. table.concat(log, "\n  "))
  Core.BuyList = savedBuy
  _G.C_Item = savedCItem
  realPrint("scan summary: " .. line)

  -- what you paid: 5 at 1s each; used when the AH has none
  C_AuctionHouse.StartCommoditiesPurchase(999123, 5)
  C_AuctionHouse.ConfirmCommoditiesPurchase(999123, 5)
  fireP("COMMODITY_PRICE_UPDATED", 100, 500)
  money = money - 500
  fireP("COMMODITY_PURCHASE_SUCCEEDED")
  assert(P.LastPaid(999123) == 100, "paid 1s each")
  assert(Core.Price(999123) == 100, "no AH price: what you paid")
  local pi = Core.PriceInfo(2589)
  assert(pi.ah == P.Own(2589) and pi.src == "SkillRoute scan" and pi.age == 0, "tooltip info (the amount-priced average)")

  _G.print = realPrint
  fire("AUCTION_HOUSE_CLOSED")
  C_Timer.After, _G.C_AuctionHouse, _G.AuctionHouseFrame = savedAfter, nil, nil
  SkillRouteDB.prices, SkillRouteDB.paid = nil, nil
  Core.InvalidatePatterns()
  print(("own AH scan: %d items in one search, freshest-price rules and paid prices OK"):format(b.count))
end

-- Working Overtime read from the Legacy Tree (by spell ID), no slider
do
  local O = ns.Options
  local manual = Core.Bonus()
  assert(Core.OvertimeInfo().rank == nil and O.OvertimeText():find("Couldn't read"), "no C_Traits: manual value")
  local rank = 3
  _G.C_Traits = {
    GetConfigIDByTreeID = function(tree) return tree == 1187 and 77 or nil end,
    GetTreeNodes = function() return { 10, 11 } end,
    GetNodeInfo = function(_, node) return node == 11 and { activeEntry = { entryID = 501 }, entryIDs = { 501 }, activeRank = rank }
                                          or { entryIDs = { 500 }, activeRank = 1 } end,
    GetEntryInfo = function(_, e) return { definitionID = e + 1000 } end,
    GetDefinitionInfo = function(d) return { spellID = d == 1501 and 1225451 or 999 } end,
  }
  assert(Core.ReadOvertime() and math.abs(Core.Bonus() - 0.12) < 1e-9, "rank 3 = 12%: " .. Core.Bonus())
  assert(O.OvertimeText():find("Rank 3 of 5"), O.OvertimeText())
  rank = 9; Core.ReadOvertime(); assert(math.abs(Core.Bonus() - 0.20) < 1e-9, "capped at rank 5")
  rank = 0; Core.ReadOvertime(); assert(Core.Bonus() == 0 and O.OvertimeText():find("Not learned"), "not learned")
  _G.C_Traits.GetConfigIDByTreeID = function() return nil end
  assert(not Core.ReadOvertime() and Core.Bonus() == 0, "tree not loaded yet: keeps the last rank read")
  _G.C_Traits = nil
  print(("working overtime: read from the Legacy Tree (rank 3 = 12%%); manual value %d%% only without it"):format(manual * 100))
end

-- essence swap, rank-up reminder, bank grab, trainer panel
do
  -- essences: 3 lesser = 1 greater; the cheaper form prices both
  local savedP = { prices[10938], prices[10939] }
  prices[10938], prices[10939] = 500, 900        -- greater is cheaper per lesser (300)
  assert(Core.Price(10938) == 300, "lesser priced via greater: " .. tostring(Core.Price(10938)))
  assert(Core.Price(10939) == 900, "greater stays")
  local other, n2, _, how = Core.EssenceSwap(10938, 7)
  assert(other == 10939 and n2 == 3 and how == "split", "buy 3 greater for 7 lesser, split")
  prices[10938], prices[10939] = 200, 900         -- 3 lesser (600) beat a greater
  assert(Core.Price(10939) == 600 and select(4, Core.EssenceSwap(10939, 2)) == "combine")
  assert(Core.EssenceSwap(10938, 5) == nil, "lesser is fine as it is")
  prices[10938], prices[10939] = savedP[1], savedP[2]

  -- rank-up reminder: capped at 150 with a higher target -> one message, once
  local H = ns.Helpers
  local savedSkills = Core.Skills
  Core.Skills = function() return { [197] = { rank = 150, max = 150 } } end
  Core.Char().targets[197] = 300
  local msg = H.RankMessage(197, { rank = 150, max = 150 })
  assert(msg and msg:find("capped at 150") and msg:find("Expert"), tostring(msg))
  assert(not H.RankMessage(197, { rank = 149, max = 150 }), "not capped yet")
  local out, realPrint = {}, print
  _G.print = function(s) out[#out + 1] = s end
  H.CheckRanks(); H.CheckRanks()
  _G.print = realPrint
  assert(#out == 1, "reminded once per cap: " .. #out)
  Core.Skills = savedSkills

  -- bank: moves whole stacks of what the next steps need
  local plan = Core.Plan(197, 300)
  Core.Char().lastLine = 197
  local want, byLine = H.BagNeeds()
  local item = next(want)
  assert(item, "the next steps need something")
  local names = {}
  for _, p in ipairs(byLine) do names[#names + 1] = p.name end
  assert(#byLine >= 1 and table.concat(names, ","):find("Tailoring"), "every crafting profession you have: " .. table.concat(names, ","))
  -- the tooltip lists only what's in the bank: 12 of the item banked, one item not at all
  local other
  for it in pairs(want) do if it ~= item then other = it; break end end
  local savedHave, savedBags = Core.Have, Core.InBags
  Core.Have = function(it) return it == item and 12 or 0 end
  Core.InBags = function() return 0 end
  local shown, missing = H.BankRows({ { name = "Tailoring", items = { [item] = 40, [other or 1] = 5 } } })
  assert(#shown == 1 and #shown[1][2] == 1 and shown[1][2][1][2] == 12 and shown[1][2][1][3] == 40, "take 12 of 40")
  assert(missing == 1, "one material not in the bank")
  Core.Have, Core.InBags = savedHave, savedBags
  local moved, inBags, free, accepts = {}, 0, 5, true
  _G.C_Container = {
    GetContainerNumSlots = function(bag) return bag == -1 and 2 or 0 end,
    GetContainerItemInfo = function(bag, slot) if bag == -1 and slot == 1 then return { itemID = item, stackCount = 20 } end end,
    UseContainerItem = function(bag, slot) moved[#moved + 1] = bag .. ":" .. slot; if accepts then inBags = inBags + 20 end end,
    GetContainerNumFreeSlots = function(bag) return bag == 0 and free or 0, 0 end,
  }
  local savedIB = Core.InBags
  Core.InBags = function(id) return id == item and inBags or 0 end
  local said
  _G.print = function(x) said = x end
  -- room in the bags: moved, and what arrived is reported
  local n = H.TakeFromBank()
  assert(n == 1 and moved[1] == "-1:1", "took the stack from the bank")
  assert(said:find("took 20 ", 1, true) and not said:find("full"), "what arrived: " .. said)
  -- bags full: nothing moved, and it says so
  moved, inBags, free = {}, 0, 0
  n = H.TakeFromBank()
  assert(n == 0 and #moved == 0 and said:find("Your bags are full: 1 stack stayed in the bank"), "full: " .. said)
  -- the game refuses the move: not reported as taken
  moved, inBags, free, accepts = {}, 0, 3, false
  H.TakeFromBank()
  assert(said:find("nothing could be moved") and said:find("1 stack stayed"), "refused: " .. said)
  _G.print = realPrint
  Core.InBags = savedIB
  _G.C_Container = nil
  -- bank tabs (newer clients): only the tabs; a reagent bag you carry is never "the bank"
  _G.Enum = { BagIndex = { Backpack = 0, ReagentBag = 5, Bank = -1, CharacterBankTab_1 = 6, CharacterBankTab_2 = 7 } }
  local b = H.BankBags()
  assert(#b == 2 and b[1] == 6 and b[2] == 7, "bank tabs only")
  _G.Enum = { BagIndex = { Backpack = 0, ReagentBag = 5, Bank = -1 } }
  b = H.BankBags()
  for _, x in ipairs(b) do assert(x ~= 5 and x ~= 0, "never a carried bag: " .. x) end
  _G.Enum = nil
  -- a bag addon's bank window is found by name, the biggest visible one
  local function frameAt(name, l, b, w, h, alpha)
    return setmetatable({ GetName = function() return name end, IsVisible = function() return true end,
      GetWidth = function() return w end, GetHeight = function() return h end, GetEffectiveAlpha = function() return alpha or 1 end,
      GetLeft = function() return l end, GetRight = function() return l + w end, GetBottom = function() return b end,
      GetTop = function() return b + h end }, { __index = function() return function() end end })
  end
  local bagAddon = frameAt("Baganator_BankViewFrame", 400, 200, 600, 400)
  local offscreen = frameAt("OtherBankWindow", -5000, 200, 900, 900)
  local clear = frameAt("ClearBankWindow", 100, 100, 900, 900, 0)
  _G.BankFrame = frameAt("BankFrame", -3000, -3000, 400, 400) -- moved away by the bag addon
  local tiny = frameAt("SomeBankIcon", 500, 500, 20, 20)
  local savedUIP = _G.UIParent
  _G.UIParent = setmetatable({ GetChildren = function() return tiny, offscreen, clear, bagAddon end,
    GetWidth = function() return 1920 end, GetHeight = function() return 1080 end }, { __index = savedUIP })
  assert(H.BankWindow() == bagAddon, "the bag addon's on-screen bank window, not off-screen or transparent ones")
  local holder = frameAt("BagAddonBankHolder", 0, 0, 1920, 1080)
  -- a forbidden frame: touching it (even GetName) errors in game
  local forbidden = setmetatable({ IsForbidden = function() return true end },
    { __index = function() return function() error("Attempt to access forbidden object") end end })
  local kids = { forbidden, tiny, offscreen, clear, bagAddon, holder }
  _G.UIParent = setmetatable({ GetChildren = function() return unpack(kids) end,
    GetWidth = function() return 1920 end, GetHeight = function() return 1080 end }, { __index = savedUIP })
  assert(H.BankWindow() == bagAddon, "a full-screen holder frame isn't the bank window")
  local said = {}
  local rp = print; _G.print = function(x) said[#said + 1] = x end
  SlashCmdList.SKILLROUTE("bank")
  _G.print = rp
  assert(#said >= 3 and table.concat(said, "\n"):find("docks to: Baganator_BankViewFrame", 1, true), "/sr bank explains")
  _G.UIParent = setmetatable({ GetChildren = function() return tiny end,
    GetWidth = function() return 1920 end, GetHeight = function() return 1080 end }, { __index = savedUIP })
  assert(H.BankWindow() == nil, "Blizzard's bank moved off screen: not docked to it")
  _G.UIParent, _G.BankFrame = savedUIP, nil

  -- trainer panel: route recipes this trainer offers, with Learn buttons
  local TP = ns.TrainerPanel
  local st
  for _, s in ipairs(plan.steps) do if s.spell and s.learn == "trainer" then st = s; break end end
  if st then
    local saved = { GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceSkillReq, GetTrainerServiceItemLink, GetTrainerServiceCost }
    _G.GetNumTrainerServices = function() return 1 end
    _G.GetTrainerServiceInfo = function() return st.name, "", "AVAILABLE?" end -- odd type: skill decides
    _G.GetTrainerServiceSkillReq = function() return "Tailoring", 100, true end -- your skill is 110
    _G.GetTrainerServiceItemLink = nil
    _G.GetTrainerServiceCost = function() return 500 end
    local d = TP.Collect()
    assert(d and #d.items == 1 and d.items[1].spell == st.spell and d.items[1].now and d.totalNow == 500, "route recipe at this trainer")
    _G.ClassTrainerFrame = stubObj(); _G.wipe = function(t) for k in pairs(t) do t[k] = nil end end
    SkillRouteDB.lastError = nil
    TP.Refresh()
    assert(not SkillRouteDB.lastError, "trainer panel draws: " .. tostring(SkillRouteDB.lastError))
    local learnAll = false
    for _, t in ipairs(texts) do local v = rawget(t, "text"); if type(v) == "string" and v:find("^1 recipe your route uses") then learnAll = true end end
    assert(learnAll, "panel lists it")
    _G.ClassTrainerFrame = nil
    GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceSkillReq, GetTrainerServiceItemLink, GetTrainerServiceCost =
      saved[1], saved[2], saved[3], saved[4], saved[5]
    print(("trainer panel: %s (used %d-%d) at this trainer"):format(st.name, st.from, st.to))
  end
  print("essence swap, rank reminder (" .. msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "), bank grab OK")
end

-- what the profession window says about a recipe wins: "not learned" un-knows it,
-- even if it was recorded before or the game's spell check says otherwise
do
  local T = C_TradeSkillUI
  local savedInfo, savedIPS = T.GetRecipeInfo, _G.IsPlayerSpell
  Core.ScanRecipes()
  assert(Core.IsRecipeKnown(197, 3848), "learned in the window")
  T.GetRecipeInfo = function(id) return { learned = id ~= 3848, relativeDifficulty = 3 } end
  _G.IsPlayerSpell = function() return true end
  Core.ScanRecipes()
  assert(Core.IsRecipeKnown(197, 3848) == false, "listed as not learned: not known")
  local savedIDs = T.GetAllRecipeIDs
  T.GetAllRecipeIDs = function() return { 2963 } end -- search box: shorter list
  Core.ScanRecipes()
  assert(Core.IsRecipeKnown(197, 3848) == false and Core.IsRecipeKnown(197, 2963), "unlisted recipes keep their state")
  T.GetAllRecipeIDs, T.GetRecipeInfo, _G.IsPlayerSpell = savedIDs, savedInfo, savedIPS
  Core.ScanRecipes()
  assert(Core.IsRecipeKnown(197, 3848), "learned again")
  print("known recipes: the window's learned / not learned wins; search-filtered lists don't forget")
end

-- clients with only C_Item.GetItemCount (no global GetItemCount): bag counts still work
do
  local savedG, savedC = _G.GetItemCount, _G.C_Item
  _G.GetItemCount = nil
  _G.C_Item = setmetatable({ GetItemCount = function(item, bank) return item == 4305 and (bank and 30 or 19) or 0 end },
                           { __index = savedC })
  assert(Core.InBags(4305) == 19 and Core.Have(4305) == 30, "C_Item counts: bags 19, with bank 30")
  local r = SkillRouteData.professions[197].recipes
  local spell
  for id, x in pairs(r) do if x.r and #x.r == 2 and x.r[1] == 4305 then spell = id; break end end
  if spell then assert(Core.CraftableNow(197, spell) == math.floor(19 / r[spell].r[2]), "Craft all counts bags via C_Item") end
  _G.GetItemCount, _G.C_Item = savedG, savedC
  print("bag counts via C_Item.GetItemCount OK")
end

-- a maxed profession (300/300) says so instead of looking for a route to 301
do
  local saved = Core.Skills
  Core.Skills = function() return { [129] = { rank = 300, max = 300 } } end
  local plan, err, why = Core.Plan(129, 300)
  assert(plan == nil and why == "maxed" and err:find("maxed %(300/300%)"), tostring(err))
  local bn = ns.Helpers.BagNeeds()
  assert(next(bn) == nil and next(Core.BuyList()) == nil, "nothing to buy or take for it")
  Core.Skills = saved
  print("maxed: " .. err)
end

-- Buy: Auctionator's shopping list when installed; else the AH's own search, one per click
do
  local plan = { line = 197, shopping = { craft = {} } }
  local st = { spell = 1, from = 140 }
  local savedSS, savedAdd, savedAuc = Core.StepShopping, Core.AddStepToAuctionator, _G.Auctionator
  Core.StepShopping = function() return { { item = 4338, name = "Mageweave Cloth", qty = 111 }, { item = 4291, name = "Silken Thread", qty = 6 } } end
  local added = 0
  Core.AddStepToAuctionator = function() added = added + 1; return true end
  local searched = {}
  _G.AuctionHouseFrame = { SearchBar = { SetSearchText = function(_, t) searched[#searched + 1] = t end, StartSearch = function() end } }
  fire("AUCTION_HOUSE_SHOW")
  _G.Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() end, CreateShoppingList = function() end } } }
  assert(Core.CanBuyHere() and Core.BuyStep(plan, st) == "Buy" and added == 1 and #searched == 0, "Auctionator first")
  _G.Auctionator = nil
  local said = {}
  local rp = print; _G.print = function(x) said[#said + 1] = x end
  assert(Core.CanBuyHere(), "Buy still offered without Auctionator")
  assert(Core.BuyStep(plan, st) == "Next 2/2" and searched[1] == "Mageweave Cloth", "first material searched")
  assert(Core.BuyStep(plan, st) == "Buy" and searched[2] == "Silken Thread", "then the next")
  assert(Core.BuyStep(plan, st) == "Next 2/2" and searched[3] == "Mageweave Cloth", "and round again")
  _G.print = rp
  assert(said[1]:find("you need 111") and said[1]:find("1 of 2"), said[1])
  fire("AUCTION_HOUSE_CLOSED")
  assert(not Core.CanBuyHere(), "no Buy with the AH closed")
  Core.StepShopping, Core.AddStepToAuctionator, _G.Auctionator, _G.AuctionHouseFrame = savedSS, savedAdd, savedAuc, nil
  print("buy: Auctionator first; without it the AH search, one material per click")
end

-- another profession can make a material: a blacksmith who mines smelts the bars
do
  local savedSkills, savedIPS, savedCount = Core.Skills, _G.IsPlayerSpell, _G.GetItemCount
  Core.Skills = function() return { [164] = { rank = 200, max = 225 }, [186] = { rank = 200, max = 225 } } end
  _G.IsPlayerSpell = function(id) return id == 10097 end -- Smelt Mithril
  local savedP = {}
  -- everything dear except mithril ore, so the route's recipes use Mithril Bar
  for id in pairs(SkillRouteData.items) do savedP[id] = prices[id]; prices[id] = 1000000 end
  prices[3860], prices[3858] = 8000, 1000 -- Mithril Bar 80s, Mithril Ore 10s
  _G.GetItemCount = function(id, bank) return id == 3858 and 500 or 0 end -- plenty of ore in the bags
  Core.InvalidatePatterns()
  local other, from = Core.OtherMakers(164)
  assert(other[10097] and from[10097] == 186, "Smelt Mithril offered to Blacksmithing")
  local plan = Core.Plan(164, 225)
  local smelt, barBuy, oreBuy
  for _, c in ipairs(plan.shopping.craft) do if c.spell == 10097 then smelt = c end end
  for _, b in ipairs(plan.shopping.buy) do
    if b.item == 3860 then barBuy = b.buy end
    if b.item == 3858 then oreBuy = b.buy end
  end
  if smelt then
    assert(smelt.line == 186 and not barBuy and (oreBuy or 0) == 0, "smelt the bars from your ore, buy none: " .. tostring(barBuy) .. "/" .. tostring(oreBuy))
    print(("cross-profession: Blacksmithing 200-225 smelts %d Mithril Bar from ore you have (Mining)"):format(smelt.n))
    -- the shopping list says so
    SkillRouteDB.settings.mini = false
    UI.Toggle(164); UI.SetMode("shopping")
    local row
    for _, t in ipairs(texts) do local v = rawget(t, "text"); if type(v) == "string" and v:find("^Make %d+ x Mithril Bar") then row = v end end
    assert(row and row:find("Mining: Smelt Mithril", 1, true), "shopping row: " .. tostring(row))
    print("  shopping list: " .. row:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    UI.SetMode("route"); UI.Toggle()
    SkillRouteDB.settings.mini = nil
  else
    error("the test route should use Mithril Bar")
  end
  -- owned bars count first: with 40 bars, fewer are smelted
  if smelt then
    _G.GetItemCount = function(id) return (id == 3858 and 500) or (id == 3860 and 40) or 0 end
    Core.InvalidatePatterns()
    local plan2 = Core.Plan(164, 225)
    local s2 = 0
    for _, c in ipairs(plan2.shopping.craft) do if c.spell == 10097 then s2 = c.n end end
    assert(s2 <= math.max(0, smelt.n - 40) + 1, "owned bars used first: " .. s2 .. " vs " .. smelt.n)
  end
  for id, v in pairs(savedP) do prices[id] = v end
  Core.Skills, _G.IsPlayerSpell, _G.GetItemCount = savedSkills, savedIPS, savedCount
  Core.InvalidatePatterns()
end

-- the waypoint arrow points the right way whichever order the game gives world axes in
do
  local A = ns.Arrow
  local savedMap, savedV = _G.C_Map, _G.CreateVector2D
  _G.CreateVector2D = function(x, y) return { x = x, y = y } end
  local function check(northFirst)
    _G.C_Map = setmetatable({ GetWorldPosFromMapPos = function(map, v)
      local north, west = (1 - v.y) * 1000, (1 - v.x) * 1000
      return 1, northFirst and { x = north, y = west } or { x = west, y = north }
    end }, { __index = savedMap })
    local ax = A._axes(northFirst and 101 or 102)
    local function bearing(tx, ty, facing)
      local pc, pa, pb = A._worldOf(1, 0.5, 0.5)
      local tc, ta, tb = A._worldOf(1, tx, ty)
      return A.Bearing(pc, pa, pb, facing, tc, ta, tb, ax)
    end
    local near = function(a, b) return math.abs((a - b + math.pi) % (2 * math.pi) - math.pi) < 1e-6 end
    local a, d = bearing(0.5, 0.4, 0)
    assert(near(a, 0) and math.abs(d - 100) < 1e-6, "north while facing north: straight ahead, 100 yd")
    assert(near(bearing(0.6, 0.5, 0), -math.pi / 2), "east while facing north: to the right")
    assert(near(bearing(0.4, 0.5, 0), math.pi / 2), "west: to the left")
    assert(near(bearing(0.5, 0.6, 0), math.pi), "south: behind")
    assert(near(bearing(0.5, 0.4, math.pi / 2), -math.pi / 2), "north while facing west: to the right")
  end
  check(true); check(false)
  -- a waypoint click without TomTom opens SkillRoute's arrow
  local savedTT = _G.TomTom
  _G.TomTom = nil
  local rp = print; _G.print = function() end
  local how = Core.Waypoint({ npc = "Josef Gregorian", ui = 90, x = 70.8, y = 29.2, zone = "Undercity" })
  _G.print = rp
  assert(how == "arrow" and A.Target() and A.Target().title == "Josef Gregorian", "arrow set: " .. tostring(how))
  assert(A.Target().route and A.Target().route:find("Fastest", 1, true), "route line: " .. tostring(A.Target().route))
  -- a visited NPC (no route of its own) gets its route from the data
  local someone
  for id, n in pairs(SkillRouteData.npcs) do if n[12] then someone = n; break end end
  local named = Core.NPCsNamed(someone[1])
  assert(#named >= 1, "found by name")
  A.Clear(); assert(not A.Target())
  _G.TomTom = savedTT
  -- data world positions -> the game's, axis order worked out from an NPC known both ways
  local ref
  for _, n in pairs(SkillRouteData.npcs) do if n[12] and n[10] and n[3] == 1 then ref = n; break end end
  for _, swapped in ipairs({ false, true }) do
    A._resetOrders()
    _G.C_Map = setmetatable({ GetWorldPosFromMapPos = function(ui, v)
      if ui == ref[12] and math.abs(v.x - ref[10] / 100) < 1e-9 and math.abs(v.y - ref[11] / 100) < 1e-9 then
        return 1, swapped and { x = ref[5], y = ref[4] } or { x = ref[4], y = ref[5] }
      end
      return 1, { x = 0, y = 0 }
    end }, { __index = savedMap })
    local c, a, b = A.DataToWorld(1, 100, 200)
    assert(c == 1 and (swapped and (a == 200 and b == 100) or (a == 100 and b == 200)), "axis order: " .. tostring(swapped))
  end
  -- the arrow points at the route's first stop (a flight master), then the NPC
  local savedNearest = Core.NearestNPC
  Core.NearestNPC = function() return { via = { "flight to Orgrimmar", "boat/zeppelin: Orgrimmar and Undercity" },
    first = { map = 1, x = 100, y = 200, label = "Flight master, Thunder Bluff" } } end
  local rp2 = print; _G.print = function() end
  Core.Waypoint({ npc = "Josef Gregorian", ui = 90, x = 70.8, y = 29.2, zone = "Undercity", id = 1 })
  _G.print = rp2
  local t = A.Target()
  assert(t.leg and t.leg.label == "Flight master, Thunder Bluff" and t.leg.cont == 1, "first stop: the flight master")
  assert(t.route:find("flight to Orgrimmar, then boat/zeppelin", 1, true), t.route)
  -- the distance line names the first stop as such (the title is the destination)
  local savedMap, savedFacing, savedV2 = _G.C_Map, _G.GetPlayerFacing, _G.CreateVector2D
  _G.CreateVector2D = function(x, y) return { x = x, y = y } end
  _G.C_Map = setmetatable({ GetWorldPosFromMapPos = function(_, v) return 1, { x = v.x * 1000, y = v.y * 1000 } end },
    { __index = savedMap })
  _G.GetPlayerFacing = function() return 0 end
  A.Update()
  _G.C_Map, _G.GetPlayerFacing, _G.CreateVector2D = savedMap, savedFacing, savedV2
  local legText
  for _, x in ipairs(texts) do local v = rawget(x, "text"); if type(v) == "string" and v:find("Flight master, Thunder Bluff|r, ", 1, true) then legText = v end end
  assert(legText and legText:find("First:|r", 1, true), "leg line: " .. tostring(legText))
  Core.NearestNPC = function() return { first = { shortcut = "Hearthstone to Orgrimmar" } } end
  A.Reroute()
  assert(A.Target().leg.shortcut == "Hearthstone to Orgrimmar", "a hearthstone first")
  Core.NearestNPC = function() return {} end
  A.Reroute()
  assert(A.Target().leg == nil, "last leg: straight to the NPC")
  -- on a flight: not sent back to the flight master you left; rerouted on landing
  Core.NearestNPC = function() return { via = { "flight to Sun Rock Retreat" },
    first = { map = 1, x = 100, y = 200, label = "Flight master, Thunder Bluff" } } end
  _G.UnitOnTaxi = function() return true end
  A.Update()
  assert(A.Target().leg == nil and A.Target().route:find("On a flight", 1, true), "in flight: straight at the NPC")
  _G.UnitOnTaxi = function() return false end
  A.Update()
  assert(A.Target().leg and A.Target().leg.label == "Flight master, Thunder Bluff", "landed: rerouted at once")
  _G.UnitOnTaxi = nil
  A.Update()
  print("arrow in flight: " .. "On a flight -> rerouted on landing")
  Core.NearestNPC = savedNearest
  A.Clear()
  assert(A.Bearing(1, 0, 0, 0, 2, 5, 5, { 1, 0, 0, 1 }) == nil, "another continent: no arrow")
  _G.C_Map, _G.CreateVector2D = savedMap, savedV
  print("waypoint arrow: right direction and distance with either world-axis order")
end

-- SkillRoute's own buying (no Auctionator): price, then pay exactly that
do
  local BP = ns.BuyPanel
  local calls = {}
  local savedAH, savedGT, savedMoney, savedAuc = _G.C_AuctionHouse, _G.GetTime, _G.GetMoney, _G.Auctionator
  _G.Auctionator = nil
  _G.C_AuctionHouse = {
    StartCommoditiesPurchase = function(item, qty) calls[#calls + 1] = "start " .. item .. " " .. qty end,
    ConfirmCommoditiesPurchase = function(item, qty) calls[#calls + 1] = "confirm " .. item .. " " .. qty end,
    CancelCommoditiesPurchase = function() calls[#calls + 1] = "cancel" end,
  }
  local clock, gold = 100, 1000000
  _G.GetTime = function() return clock end
  _G.GetMoney = function() return gold end
  local bf
  for _, f in ipairs(frames) do local e = rawget(f, "events"); if e and e.COMMODITY_PRICE_UNAVAILABLE then bf = f end end
  local function ev(name, ...) bf.OnEvent(bf, name, ...) end
  assert(BP.CanUse())
  BP.Open({ { item = 4338, name = "Mageweave Cloth", qty = 111, expect = 407 }, { item = 9999, name = "Odd Thing", qty = 1 } }, "test")
  local it = BP.Items()
  BP._click(1)
  assert(calls[1] == "start 4338 111" and it[1].state == "quoting", "asked for a quote")
  ev("COMMODITY_PRICE_UPDATED", 407, 45177)
  assert(it[1].state == "quoted" and it[1].total == 45177, "quote shown")
  BP._click(1)
  assert(#calls == 1, "a click the moment a quote arrives doesn't buy (it hasn't been seen)")
  clock = clock + 1
  ev("COMMODITY_PRICE_UPDATED", 450, 49950) -- the price moved
  clock = clock + 0.1
  BP._click(1)
  assert(#calls == 1 and it[1].total == 49950, "a changed quote needs a new click")
  clock = clock + 1
  BP._click(1)
  assert(calls[2] == "confirm 4338 111" and it[1].state == "buying", "bought at the quote shown")
  ev("COMMODITY_PURCHASE_SUCCEEDED")
  assert(it[1].state == "bought", "done")
  -- more than 10 materials: pages reach them all
  local many = {}
  for k = 1, 12 do many[k] = { item = 5000 + k, name = "Thing " .. k, qty = 1 } end
  BP.Open(many, "many")
  BP.Page(1)
  BP._click(11)
  assert(calls[#calls] == "start 5011 1", "item 11 reachable on page 2")
  -- a purchase made elsewhere (the AH's own window) while ours is only quoted: not ours
  ev("COMMODITY_PRICE_UPDATED", 10, 10)
  ev("COMMODITY_PURCHASE_SUCCEEDED")
  assert(BP.Items()[11].state == "quoted", "someone else's purchase isn't marked bought here")
  BP.Open({ { item = 4338, name = "Mageweave Cloth", qty = 111, expect = 407 }, { item = 9999, name = "Odd Thing", qty = 1 } }, "test")
  it = BP.Items()
  -- not a stackable item: Search instead
  BP._click(2)
  ev("COMMODITY_PRICE_UNAVAILABLE")
  assert(it[2].state == "search", "not stackable: search")
  -- not enough gold: no Buy
  BP.Open({ { item = 4338, name = "Mageweave Cloth", qty = 999 } }, "test2")
  BP._click(1); ev("COMMODITY_PRICE_UPDATED", 407, 406593)
  gold = 1000
  clock = clock + 1
  local before = #calls
  BP.Refresh()
  BP._click(1)
  assert(#calls == before and BP.Items()[1].state == "quoted", "not enough gold: nothing bought")
  -- Buy without Auctionator opens the panel
  local savedSS = Core.StepShopping
  Core.StepShopping = function() return { { item = 4338, name = "Mageweave Cloth", qty = 5 } } end
  assert(Core.BuyStep({ line = 197, shopping = { craft = {} } }, { spell = 1, from = 1, name = "Bolt" }) == "Buy" and BP.IsShown()
    and BP.Items()[1].qty == 5, "step Buy opens the buying panel")
  Core.StepShopping = savedSS
  ev("AUCTION_HOUSE_CLOSED")
  _G.C_AuctionHouse, _G.GetTime, _G.GetMoney, _G.Auctionator = savedAH, savedGT, savedMoney, savedAuc
  print("buying panel: quote, pay the quote shown, re-confirm a changed price, search for non-stackables")
end

-- crowded AH: how many are listed counts when choosing AH / disenchant / vendor
do
  local P = ns.Prices
  local item, it
  for id, x in pairs(SkillRouteData.items) do
    if x[2] and x[2] >= 100 and not (SkillRouteData.disenchant and SkillRouteData.disenchant.of and SkillRouteData.disenchant.of[id]) then item, it = id, x; break end
  end
  local savedP, savedListed = prices[item], P.Listed
  prices[item] = math.floor(it[2] * 1.2 / 0.95) -- the AH pays ~20% more than a vendor
  P.Listed = function() return 5 end
  local a = Core.ItemAdvice(item, nil, 1)
  assert(a.best == "ah" and not a.crowded, "few listed: list it on the AH")
  P.Listed = function() return 80 end
  a = Core.ItemAdvice(item, nil, 1)
  assert(a.crowded and a.best == "vendor", "80 listed: crowded, the vendor wins")
  local action, compared = UI.AfterCrafting(item, 1)
  assert(compared:find("80 listed: crowded, counted as", 1, true) and compared:find("(70%))", 1, true), compared)
  P.Listed, prices[item] = savedListed, savedP
  print("crowded AH: " .. compared:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- disenchanting in item tooltips: any weapon or armour, by quality and item level
do
  local TT = ns.Tooltip
  local savedCItem = _G.C_Item
  local fake = {}
  _G.C_Item = setmetatable({ GetItemInfo = function(id)
    local f = fake[id]
    if f then return "x", "link", f.q, f.ilvl, 0, "", "", 1, "", 0, f.sell or 3218, f.cls, f.sub end
  end }, { __index = savedCItem })
  fake[900001] = { q = 2, ilvl = 38, cls = 4, sub = 2 }         -- green leather, ilvl 38 (Spirit Hunter Headdress-like)
  fake[11288] = { q = 2, ilvl = 30, cls = 2, sub = 19 }         -- a wand enchanters make: never
  fake[250001] = { q = 3, ilvl = 150, cls = 4, sub = 1 }        -- a new Forever rare no bracket covers
  local key, skill = Core.DisenchantOf(900001)
  local loot = SkillRouteData.disenchant.loot[key]
  local mats = {}
  for i = 1, #loot, 4 do mats[loot[i]] = loot[i + 1] end
  assert(mats[11137] == 75 and mats[11135] == 20 and mats[11139] == 5, "ilvl 36-40: Vision Dust 75%, Greater Mystic 20%, Large Glowing 5%")
  assert(skill == 1, "Forever: no skill requirement (checked in game): " .. tostring(skill))
  assert(Core.DisenchantOf(11288) == nil, "enchanters' wands can't be disenchanted")
  assert(select(3, Core.DisenchantOf(250001)) == true, "a new Forever rare: no guess")
  -- value: priced materials add up; one unpriced -> a lower bound, named
  local saved = { prices[11137], prices[11135], prices[11139] }
  prices[11137], prices[11135], prices[11139] = 900, 3100, nil
  local rows, total, missing = TT.Value(key)
  assert(#rows == 3 and #missing == 1 and math.abs(total - (0.75 * 1.5 * 900 + 0.20 * 1.5 * 3100) * 0.95) < 1, "partial value: " .. total)
  local lines = TT.Lines(900001, true, 3218)
  local text = {}
  for _, l in ipairs(lines) do text[#text + 1] = (l[1] or "") .. " | " .. (l[2] or "") end
  local joined = table.concat(text, "\n")
  assert(joined:find("at least", 1, true) and joined:find("no price:", 1, true) and joined:find("Best:", 1, true), joined)
  -- material names in their quality colour; chance by the name, amount x price on the right
  local savedCI2 = _G.C_Item
  _G.C_Item = setmetatable({ GetItemInfo = function(id) if id == 11135 then return "Greater Mystic Essence", "l", 2 end
    return savedCI2.GetItemInfo and savedCI2.GetItemInfo(id) end,
    GetItemQualityColor = function(q) return 0.1, 1, 0, q == 2 and "ff1eff00" or "ffffffff" end }, { __index = savedCI2 })
  local ql = TT.Lines(900001, false, 3218)
  local savedSk = Core.Skills
  Core.Skills = function() return { [333] = { rank = 170, max = 225 } } end
  assert(TT.Lines(900001, false, 3218)[1][2] == "", "with Enchanting: no note")
  Core.Skills = function() return {} end
  assert(TT.Lines(900001, false, 3218)[1][2]:find("ff4040you don't have Enchanting", 1, true), "without: a red note")
  -- all priced, with Enchanting: the Disenchanting line shows the advice's own value
  prices[11139] = 5000
  Core.Skills = function() return { [333] = { rank = 170, max = 225 } } end
  local savedEN = Core.EnchantingNeeds
  Core.EnchantingNeeds = function() return {} end
  local adv = Core.ItemAdvice(900001, 170, 1, {}, { bound = false, vendor = 3218 })
  local deLine
  for _, l in ipairs(TT.Lines(900001, false, 3218)) do if l[1] == "Disenchanting" then deLine = l[2] end end
  assert(adv.de and deLine and deLine:find("~" .. UI.Money(adv.de), 1, true), "tooltip value = advice value: " .. tostring(deLine))
  -- a material your route needs: counted at what you'd pay, and said so
  Core.EnchantingNeeds = function() return { [11137] = 100 } end
  local adv2 = Core.ItemAdvice(900001, 170, 1, { [11137] = 100 }, { bound = false, vendor = 3218 })
  local all2 = {}
  for _, l in ipairs(TT.Lines(900001, false, 3218)) do
    if l[1] == "Disenchanting" then deLine = l[2] end
    if l[1]:find("at buy price", 1, true) or l[1]:find("compared:", 1, true) then
      assert(l.wrap, "long notes wrap instead of widening the tooltip: " .. l[1])
    end
    all2[#all2 + 1] = l[1] .. " | " .. (l[2] or "")
  end
  local joined2 = table.concat(all2, "\n")
  assert(adv2.deUsed and deLine == "~" .. UI.Money(adv2.de) and joined2:find("at buy price (your Enchanting route needs", 1, true),
    "route-needed material counted: " .. joined2)
  -- "Best" says what it beat (AH and vendor; disenchanting is shown above it)
  assert(joined2:find("compared: ", 1, true) and not joined2:find("compared:[^\n]*disenchant"), "compared line: " .. joined2)
  -- a crowded AH that loses to the vendor says what it counted as (why the higher price lost)
  do
    local savedListed, savedP = ns.Prices.Listed, prices[900001]
    prices[900001] = 2500 -- 23s 75c after the cut
    ns.Prices.Listed = function(it) return it == 900001 and 47 or nil end
    local ca = Core.ItemAdvice(900001, 170, 1, {}, { vendor = 2130 })
    assert(ca.crowded and ca.best ~= "ah" and ca.ahCounted == math.floor(ca.ah * 0.7), "crowded AH counted at 70%")
    local cmp = UI.Compared(ca, 900001, true)
    assert(cmp:find("47 listed: crowded, counted as", 1, true) and cmp:find(UI.Money(ca.ahCounted, "ff8040"), 1, true), cmp)
    assert(cmp:find("(70%))", 1, true), "the share used, after the amount: " .. cmp)
    -- the slider's setting decides it: at 90% the same listing beats the vendor
    ns.Options.Set("crowded", 90)
    local ca90 = Core.ItemAdvice(900001, 170, 1, {}, { vendor = 2130 })
    assert(ca90.best == "ah", "at 90% the crowded AH wins: " .. tostring(ca90.best))
    ns.Options.Set("crowded", 50)
    local cmp50 = UI.Compared(Core.ItemAdvice(900001, 170, 1, {}, { vendor = 2130 }), 900001, true)
    assert(cmp50:find("(50%))", 1, true), cmp50)
    ns.Options.Set("crowded", nil)
    -- the slider's live example follows the same rule
    assert(ns.Options.CrowdedExample(70):find("count as 17s, less than a vendor's 20s", 1, true), ns.Options.CrowdedExample(70))
    assert(ns.Options.CrowdedExample(90):find("still more than a vendor's 20s", 1, true), ns.Options.CrowdedExample(90))
    assert(ns.Options.CrowdedExample(100):find("crowding is ignored", 1, true))
    print("crowded: " .. cmp:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    print("crowded slider: " .. ns.Options.CrowdedExample(70))
    ns.Prices.Listed, prices[900001] = savedListed, savedP
  end
  -- soulbound: no AH option, and it says so
  local bound = {}
  for _, l in ipairs(TT.Lines(900001, true, 3218)) do bound[#bound + 1] = l[1] end
  assert(table.concat(bound, "\n"):find("soulbound: no AH", 1, true), "soulbound said: " .. table.concat(bound, "\n"))
  Core.EnchantingNeeds = savedEN
  prices[11139] = nil
  print("tooltip value = Best's value:\n  " .. joined2:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]*|t ", ""):gsub("\n", "\n  "))
  Core.Skills = savedSk
  local essence
  for _, l in ipairs(ql) do if l[1]:find("Greater Mystic Essence", 1, true) then essence = l end end
  assert(essence and essence[1]:find("|cff1eff00", 1, true) and essence[1]:find("(20%)", 1, true) and essence[2]:find("^1%-2 x "),
    "quality colour, chance by the name, amount x price: " .. tostring(essence and (essence[1] .. " | " .. essence[2])))
  _G.C_Item = savedCI2
  -- the hook adds the lines once, until the tooltip is cleared
  local post
  _G.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) post = fn end }
  _G.Enum = { TooltipDataType = { Item = 0 } }
  local added = 0
  local tt = { GetItem = function() return "x", "|Hitem:900001::|h[x]|h" end, NumLines = function() return 1 end,
    GetName = function() return "TestTip" end, AddLine = function() added = added + 1 end,
    AddDoubleLine = function() added = added + 1 end, Show = function() end, GetOwner = function() return nil end }
  TT.Install()
  post(tt); local once = added; post(tt)
  assert(once > 3 and added == once, "lines added once: " .. once .. "/" .. added)
  -- a setter path where the tooltip doesn't know its item: the link comes from the arguments
  added = 0
  local blind = { GetItem = function() return nil end, NumLines = function() return 1 end,
    GetName = function() return "BlindTip" end, AddLine = function() added = added + 1 end,
    AddDoubleLine = function() added = added + 1 end, Show = function() end, GetOwner = function() return nil end }
  TT._add(blind, "|Hitem:900001::|h[x]|h")
  assert(added > 3, "lines from the setter's link")
  _G.TooltipDataProcessor, _G.Enum = nil, nil
  -- the value works from either price source: SkillRoute's own scan alone, or Auctionator alone
  local P, savedAuc = ns.Prices, _G.Auctionator
  _G.Auctionator = nil
  local book = P.Book()
  local savedItems, savedT = book.items, book.t
  book.items, book.t = { [11137] = 1000, [11135] = 3000, [11139] = 5000 }, time()
  local _, ownTotal, ownMissing = TT.Value(key)
  assert(#ownMissing == 0 and math.abs(ownTotal - (0.75 * 1.5 * 1000 + 0.20 * 1.5 * 3000 + 0.05 * 5000) * 0.95) < 1,
    "own scan only: " .. ownTotal)
  book.items, book.t = savedItems, savedT
  _G.Auctionator = savedAuc
  prices[11137], prices[11135], prices[11139] = 1000, 3000, 5000
  local _, aucTotal, aucMissing = TT.Value(key)
  assert(#aucMissing == 0 and math.abs(aucTotal - ownTotal) < 1, "Auctionator only: " .. aucTotal)
  print(("disenchant value: own scan %d c = Auctionator %d c"):format(ownTotal, aucTotal))
  prices[11137], prices[11135], prices[11139] = saved[1], saved[2], saved[3]
  _G.C_Item = savedCItem
  print("tooltip disenchant: " .. text[#text]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- "keep it": items your routes still use are marked in their tooltips
do
  local TT = ns.Tooltip
  Core.InvalidatePatterns()
  local needs = Core.RouteNeeds()
  local item, list = next(needs)
  assert(item and list[1][1] == "Tailoring" and list[1][2] > 0, "the Tailoring route needs something")
  local line = TT.NeedLine(item)
  assert(line and line:find("keep it", 1, true) and line:find("Your Tailoring route needs " .. list[1][2], 1, true), tostring(line))
  assert(TT.NeedLine(999999999) == nil, "nothing for an item no route uses")
  -- the same amounts as the shopping list (same safety margin, bolts expanded)
  local checked = 0
  for _, b in ipairs(Core.Plan(197, 300).shopping.buy) do
    if b.need > 0 then
      local n = needs[b.item]
      assert(n and n[1][2] >= b.need, ("keep it %s = shopping %d for %s"):format(tostring(n and n[1][2]), b.need, b.item))
      checked = checked + 1
    end
  end
  assert(checked > 0, "compared keep-it with the shopping list")

  -- shown on a tooltip even when the item can't be disenchanted
  local added = {}
  local tt = { GetItem = function() return "x", "|Hitem:" .. item .. "::|h[x]|h" end, NumLines = function() return 1 end,
    GetName = function() return "NeedTip" end, AddLine = function(_, t) added[#added + 1] = t end,
    AddDoubleLine = function(_, t) added[#added + 1] = t end, Show = function() end, GetOwner = function() return nil end }
  TT._add(tt)
  assert(added[1] and added[1]:find("keep it", 1, true), "tooltip line: " .. tostring(added[1]))
  print("keep it: " .. line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- a long footer: the timing goes first; if it still wraps, the list ends above it
do
  local footer, scroll = ns.UI._footer()
  assert(footer and scroll, "route window built")
  local total = "Buy for 485g 38s 10c (~385g 30s 65c of it after level 35) + 3g 20s 0c training"
  footer.GetFont = function() return "f", 12 end
  footer.GetStringHeight = function(self) return #(rawget(self, "text") or "") > 90 and 28 or 14 end
  footer:SetText(total .. "   |cff808080planned in 33.9 ms|r")
  assert(rawget(footer, "text") == total and scroll.bottom == 34, "timing dropped, one line: " .. tostring(rawget(footer, "text")))
  footer:SetText("Gathering route: about 120 gathers   |cff808080planned in 3.0 ms|r")
  assert(rawget(footer, "text"):find("planned in", 1, true), "room for it: timing kept")
  footer.GetStringHeight = function() return 28 end
  footer:SetText(total .. total)
  assert(scroll.bottom == 48, "still two lines: list ends above it: " .. tostring(scroll.bottom))
  footer.GetStringHeight = function() return 14 end
  ns.UI.FitFooter()
  assert(scroll.bottom == 34, "one line again: " .. tostring(scroll.bottom))
  footer.GetStringHeight, footer.GetFont = nil, nil
  print("footer: timing dropped when long; list ends above a two-line footer")
end

-- recipes left out for unpriced reagents: "scan the AH" only before any scan; after one,
-- the reagents nobody is selling are named
do
  local savedPlan, savedSrc = Core.Plan, Core.PriceSource
  Core.Plan = function(...)
    local p = savedPlan(...)
    if not p then return p end
    local copy = setmetatable({ unpriced = 2, unpricedItems = { [4306] = true } }, { __index = p }) -- not the cached plan
    return copy
  end
  local wasShown = ns.UI.IsShown()
  if not wasShown then ns.UI.Toggle(197) end
  local function infoText()
    ns.UI.Refresh()
    for _, t in ipairs(texts) do
      local v = rawget(t, "text")
      if type(v) == "string" and v:find("recipes ", 1, true) and (v:find("left out", 1, true) or v:find("skipped:", 1, true)) then return v end
    end
  end
  Core.PriceSource = function() return nil end
  local before = infoText()
  assert(before and before:find("scan the AH", 1, true), "no scan yet: scan the AH: " .. tostring(before))
  Core.PriceSource = function() return "SkillRoute scan" end
  local after = infoText()
  assert(after and after:find("2 recipes left out: no ", 1, true) and after:find("on the AH right now", 1, true)
    and not after:find("scan the AH", 1, true), "scanned: names the reagent: " .. tostring(after))
  Core.Plan, Core.PriceSource = savedPlan, savedSrc
  if not wasShown then ns.UI.Toggle() else ns.UI.Refresh() end
  print("unpriced: " .. after:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
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
