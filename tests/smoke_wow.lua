-- Loads the whole addon against a fake WoW API and drives the main paths, to catch
-- nil/typo errors outside the game. Run from the repo root: lua5.1 tests/smoke_wow.lua
local function stubObj()
  local o = { shown = false, text = "" }
  return setmetatable(o, { __index = function(t, k)
    if k == "IsShown" then return function(self) return self.shown end end
    if k == "Show" then return function(self) self.shown = true; if self.onShow then self.onShow(self) end end end
    if k == "Hide" then return function(self) self.shown = false end end
    if k == "SetText" then return function(self, v) self.text = v end end
    if k == "GetText" then return function(self) return self.text end end
    if k == "SetScript" then return function(self, n, f) if n == "OnShow" then self.onShow = f end; self[n] = f end end
    if k == "CreateTexture" or k == "CreateFontString" then return function() return stubObj() end end
    return function() end
  end })
end
_G.CreateFrame = function() return stubObj() end
_G.UIParent, _G.UISpecialFrames, _G.SlashCmdList = stubObj(), {}, {}
_G.tinsert = table.insert
_G.GameTooltip = stubObj()
_G.C_Timer = { After = function(_, f) f() end }
_G.UnitName = function() return "Tester" end
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
local prices = {}
_G.Auctionator = { API = { v1 = {
  GetAuctionPriceByItemID = function(_, id) return prices[id] end,
  RegisterForDBUpdate = function() end } } }
-- trainer window with two services
_G.GetNumTrainerServices = function() return 2 end
_G.GetTrainerServiceInfo = function(i) return i == 1 and "Earthen Vest" or "Robe of Power" end
_G.GetTrainerServiceSkillReq = function(i) return "Tailoring", i == 1 and 145 or 160, true end
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

-- UI: open, both modes, cycle, slash commands
SlashCmdList.SKILLROUTE("")
assert(UI.IsShown())
SlashCmdList.SKILLROUTE("overtime 10"); assert(SkillRouteDB.settings.bonus == 0.1)
SlashCmdList.SKILLROUTE("estimate on"); assert(SkillRouteDB.settings.estimate == true)
SlashCmdList.SKILLROUTE("help")
UI.Refresh()
UI._state.mode = "shopping"; UI.Refresh(); UI._state.mode = "route"
UI.AttachButton()
SlashCmdList.SKILLROUTE("") -- close
assert(not UI.IsShown())
print("SMOKE TEST PASSED")
