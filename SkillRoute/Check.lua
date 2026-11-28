-- /sr check: what this client offers SkillRoute, and a live self-test. Everything
-- SkillRoute uses is optional at runtime; when something is missing a feature
-- quietly does less, so this is the place to see which.
local _, ns = ...
local Core, Data = ns.Core, SkillRouteData

local OK, NO, WARN = "|cff40ff40OK|r", "|cffff4040missing|r", "|cffffd100?|r"

local function has(path)
  local v = _G
  for part in path:gmatch("[^%.]+") do
    if type(v) ~= "table" then return false end
    v = v[part]
  end
  return v ~= nil
end

-- {label, any of these must exist, what it is for}
local APIS = {
  { "Profession skills", { "GetProfessions", "GetSkillLineInfo" }, "your skill levels" },
  { "Recipe list", { "C_TradeSkillUI.GetAllRecipeIDs" }, "known recipes, live colours" },
  { "Recipe info", { "C_TradeSkillUI.GetRecipeInfo" }, "known recipes, live colours" },
  { "Open profession", { "C_TradeSkillUI.GetBaseProfessionInfo", "C_TradeSkillUI.GetTradeSkillLine" }, "which window is open" },
  { "Select a recipe", { "C_TradeSkillUI.OpenRecipe", "C_TradeSkillUI.SetSelectedRecipeID", "TradeSkillFrame_SetSelection" }, "click a step to open its recipe" },
  { "Trainer window", { "GetTrainerServiceSkillReq" }, "real learn levels and trainer ranks" },
  { "Vendor window", { "GetMerchantItemID", "GetMerchantItemLink" }, "remembering pattern vendors" },
  { "Vendor prices", { "C_MerchantFrame.GetItemInfo", "GetMerchantItemInfo" }, "price and stock at vendors you visit" },
  { "Your map position", { "C_Map.GetPlayerMapPosition" }, "nearest trainer, travel times" },
  { "World -> map", { "C_Map.GetMapPosFromWorldPos" }, "zone + coordinates of Classic NPCs" },
  { "Zone at a spot", { "C_Map.GetMapInfoAtPosition" }, "zone names of Classic NPCs" },
  { "Flight map", { "C_TaxiMap.GetAllTaxiNodes", "NumTaxiNodes" }, "which flight points you know" },
  { "Item cooldown", { "C_Container.GetItemCooldown", "GetItemCooldown" }, "hearthstone cooldown" },
  { "Bind location", { "GetBindLocation" }, "where your hearthstone goes" },
  { "Reputation", { "C_Reputation.GetFactionDataByID", "GetFactionInfoByID" }, "reputation patterns" },
  { "Craft from a button", { "C_TradeSkillUI.CraftRecipe" }, "Craft 1 / Craft all on the mini panel" },
  { "Tools and forges", { "C_TradeSkillUI.GetRecipeRequirements", "C_TradeSkillUI.GetRecipeTools", "GetTradeSkillTools" },
    "Craft buttons only at a forge or anvil" },
  { "Learn at a trainer", { "BuyTrainerService" }, "Learn buttons on the trainer panel" },
  { "Bank to bags", { "C_Container.UseContainerItem", "UseContainerItem" }, "Take mats at the bank" },
  { "Legacy Tree", { "C_Traits.GetConfigIDByTreeID", "C_Traits.GetTreeNodes" }, "read your Working Overtime rank" },
  { "AH scan", { "C_AuctionHouse.SendBrowseQuery" }, "SkillRoute's own AH scan (Scan AH button)" },
  { "AH purchases", { "C_AuctionHouse.StartCommoditiesPurchase", "C_AuctionHouse.ConfirmCommoditiesPurchase" }, "buy without Auctionator; remember what you paid" },
  { "Auctionator prices", { "Auctionator.API.v1.GetAuctionPriceByItemID" }, "prices (or use Scan AH)" },
  { "Auctionator scan updates", { "Auctionator.API.v1.RegisterForDBUpdate" }, "re-plan after a scan" },
  { "Auctionator listing age", { "Auctionator.API.v1.GetAuctionAgeByItemID" }, "ignore old AH sightings of patterns" },
  { "TSM prices (optional)", { "TSM_API.GetCustomPriceValue" }, "prices for items your scan and Auctionator haven't seen" },
  { "Auctionator shopping lists", { "Auctionator.API.v1.CreateShoppingList" }, "send the shopping list to Auctionator" },
  { "Item tooltips", { "TooltipDataProcessor.AddTooltipPostCall", "GameTooltip.SetBagItem" }, "disenchanting in item tooltips" },
  { "Waypoint arrow", { "GetPlayerFacing", "C_Map.GetWorldPosFromMapPos" }, "SkillRoute's own arrow" },
  { "TomTom", { "TomTom.AddWaypoint" }, "waypoints (optional: SkillRoute's arrow otherwise)" },
  { "Map pin", { "C_Map.SetUserWaypoint" }, "waypoints without TomTom" },
  { "Alt inventories", { "Syndicator.API.GetInventoryInfoByItemID", "DataStore.GetContainerItemCount" }, "materials on your alts" },
}

local function line(s) print("|cff33ccffSkillRoute check:|r " .. s) end

function Core.Check()
  line(("data from client build %s"):format(Data.build or "?"))
  local missing = 0
  for _, a in ipairs(APIS) do
    local found
    for _, p in ipairs(a[2]) do if has(p) then found = p break end end
    if not found then missing = missing + 1 end
    line(("%s %s - %s"):format(found and OK or NO, a[1], a[3]))
  end

  -- live tests
  local okSkills, skills = pcall(Core.Skills)
  local names = {}
  for l in pairs(okSkills and skills or {}) do names[#names + 1] = Data.professions[l].name .. " " .. skills[l].rank end
  line(("%s professions found: %s"):format(#names > 0 and OK or WARN, #names > 0 and table.concat(names, ", ") or "none"))

  local okPos, pm, px, py = pcall(Core.PlayerWorld)
  line(("%s your world position: %s"):format(okPos and pm and OK or WARN,
    okPos and pm and ("map %d, %.0f / %.0f"):format(pm, px, py) or "unknown (in an instance, or the map API is missing)"))

  -- resolve a Classic NPC's zone through the game's map (the check it relies on)
  local tried, resolved
  for id, n in pairs(Data.npcs or {}) do
    if not n[12] and n[6] then
      tried = n[1]
      local ok, loc = pcall(Core.NPCLocation, id)
      resolved = ok and loc and loc.ui and Core.Where(loc)
      break
    end
  end
  line(("%s zone lookup for Classic NPCs (%s): %s"):format(resolved and OK or WARN, tried or "-",
    resolved or "not resolved - those NPCs show continent coordinates instead"))

  local known = 0
  for _ in pairs(Core.KnownTaxi()) do known = known + 1 end
  line(("%s known flight points: %d%s"):format(known > 0 and OK or WARN, known,
    known == 0 and " (open a flight master's map once)" or ""))

  for l in pairs(okSkills and skills or {}) do
    local ok, plan = pcall(Core.Plan, l, 300)
    line(("%s plan %s: %s"):format(ok and plan and OK or NO, Data.professions[l].name,
      ok and plan and ("%d steps, %.1f ms"):format(#plan.steps, plan.ms or 0) or tostring(plan)))
  end

  local err = SkillRouteDB and SkillRouteDB.lastError
  local when = SkillRouteDB and SkillRouteDB.lastErrorTime and date and date("%Y-%m-%d %H:%M", SkillRouteDB.lastErrorTime)
  line(err and ("|cffff4040last error|r (v%s%s): %s"):format(SkillRouteDB.lastErrorVersion or "?",
         when and (", " .. when) or "", err)
       or (OK .. " no errors recorded (v" .. Core.Version() .. ")"))
  line(missing == 0 and "everything SkillRoute can use is available."
       or ("%d feature(s) above are missing: those parts do less, the rest works."):format(missing))
end
