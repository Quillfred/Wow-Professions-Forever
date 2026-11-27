-- Disenchanting in item tooltips: what a weapon or piece of armour disenchants into
-- (Forever's own brackets), what that's worth at today's AH prices after the cut, and
-- SkillRoute's advice: disenchant, list it on the AH, or sell it to a vendor - counting
-- materials your Enchanting route still needs, and your Enchanting skill.
local _, ns = ...
local Core, UI, Data = ns.Core, ns.UI, SkillRouteData
local TT = {}
ns.Tooltip = TT

local CUT = 0.95
local MARK = "SkillRouteDE" -- set on a tooltip once our lines are in (until it's cleared)

local function enabled() return (SkillRouteDB.settings or {}).deTooltip ~= false end

local function itemIDFromLink(link)
  if type(link) == "number" then return link end
  return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- The item a tooltip setter shows, from its own arguments.
local function C(name) return C_Container and C_Container[name] or _G[name] end
local LINK_OF = {
  SetBagItem = function(bag, slot) local f = C("GetContainerItemLink"); return f and f(bag, slot) end,
  SetInventoryItem = function(unit, slot) return GetInventoryItemLink and GetInventoryItemLink(unit, slot) end,
  SetHyperlink = function(link) return link end,
  SetItemByID = function(id) return id end,
  SetMerchantItem = function(i) return GetMerchantItemLink and GetMerchantItemLink(i) end,
  SetAuctionItem = function(kind, i) return GetAuctionItemLink and GetAuctionItemLink(kind, i) end,
  SetAuctionSellItem = function() return nil end, -- the tooltip knows it
}

-- Soulbound? Read from the tooltip's own lines (no API says it for any item).
local function isSoulbound(tt)
  local text = ITEM_SOULBOUND or "Soulbound"
  local name = tt.GetName and tt:GetName()
  if not name then return false end
  for i = 1, tt:NumLines() or 0 do
    local fs = _G[name .. "TextLeft" .. i]
    local t = fs and fs:GetText()
    if t == text then return true end
  end
  return false
end

-- Per material: { item, chance, min, max, price (copper each, after the cut, or nil) },
-- the expected value of one disenchant (sum over priced materials), and the names of
-- materials with no fresh price (the value is then a lower bound).
function TT.Value(key)
  local loot = Data.disenchant and Data.disenchant.loot[key]
  if not loot then return nil end
  local rows, total, missing = {}, 0, {}
  for i = 1, #loot, 4 do
    local mat, chance, lo, hi = loot[i], loot[i + 1], loot[i + 2], loot[i + 3]
    local p = Core.AHPrice(mat)
    if p and not Core.AHFresh(mat) then p = nil end
    local each = p and p * CUT or nil
    rows[#rows + 1] = { item = mat, chance = chance, min = lo, max = hi, price = each }
    if each then total = total + chance / 100 * (lo + hi) / 2 * each
    else missing[#missing + 1] = UI.ItemName(mat) end
  end
  return rows, total, missing
end

-- The lines for one item, as { {left, right, r, g, b}, ... }; nil if it can't be
-- disenchanted. bound: soulbound (no AH option).
function TT.Lines(item, bound, vendorPrice)
  local key, skill, unverified = Core.DisenchantOf(item)
  if not key then
    if unverified then
      return { { "SkillRoute", "new Forever item: no disenchant data yet", 0.6, 0.6, 0.6 } }
    end
    return nil
  end
  local ench = Core.Skills()[333]
  local lines = {}
  local skillText
  if not ench then skillText = "|cff999999you don't have Enchanting|r"
  else skillText = "|cff40bf40you can disenchant this|r" end -- Forever: no skill requirement
  lines[#lines + 1] = { "|cff33ccffSkillRoute: disenchants into|r", skillText }
  local rows, total, missing = TT.Value(key)
  for _, r in ipairs(rows) do
    local qty = r.min == r.max and ("x%d"):format(r.min) or ("x%d-%d"):format(r.min, r.max)
    local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(r.item)) or (GetItemIcon and GetItemIcon(r.item))
    lines[#lines + 1] = { ("%s%s %s"):format(icon and ("|T" .. icon .. ":0|t ") or "", UI.ItemName(r.item), qty),
                          ("%d%%  %s"):format(math.floor(r.chance + 0.5), r.price and (UI.Money(r.price) .. " each") or "|cff999999no price|r"),
                          1, 1, 1 }
  end
  if #missing == #rows then
    lines[#lines + 1] = { "Disenchanting", "|cff999999no fresh AH prices: scan the AH|r" }
  else
    lines[#lines + 1] = { "Disenchanting", (#missing > 0 and "at least ~%s" or "~%s"):format(UI.Money(total))
                          .. " |cff999999after the AH cut|r" }
    if #missing > 0 then lines[#lines + 1] = { "", "|cff999999no price: " .. table.concat(missing, ", ") .. "|r" } end
  end
  -- the advice, as on the route: counts what your Enchanting route needs, your skill
  local a = Core.ItemAdvice(item, ench and ench.rank, 1, ench and Core.EnchantingNeeds() or nil,
                            { bound = bound, vendor = vendorPrice })
  local WORDS = { ah = "list it on the AH", de = "disenchant it", vendor = "sell it to a vendor" }
  lines[#lines + 1] = { "|cffffd100Best: " .. WORDS[a.best] .. ", " .. UI.Money(a.bestValue) .. "|r", "" }
  return lines
end

-- Inside SkillRoute's own windows the step tooltips already give this advice.
local function fromSkillRoute(tt)
  local o = tt.GetOwner and tt:GetOwner()
  for _ = 1, 8 do
    if not o then return false end
    local n = o.GetName and o:GetName()
    if n and n:find("^SkillRoute") then return true end
    o = o.GetParent and o:GetParent()
  end
  return false
end

-- link: from the setter's own arguments when known (some Forever tooltips don't fill in
-- GetItem on those paths); else asked from the tooltip.
local function addLines(tt, link)
  if not enabled() or tt[MARK] or fromSkillRoute(tt) then return end
  if not link then
    local ok, _, l = pcall(tt.GetItem, tt)
    link = ok and l or nil
  end
  if not link then return end
  if issecretvalue and issecretvalue(link) then return end
  local item = itemIDFromLink(link)
  if not item then return end
  local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local vendor = info and select(11, info(item)) or nil
  local lines = TT.Lines(item, isSoulbound(tt), vendor)
  if not lines then return end
  tt[MARK] = true
  tt:AddLine(" ")
  for _, l in ipairs(lines) do
    if l[2] and l[2] ~= "" then tt:AddDoubleLine(l[1], l[2], l[3] or 1, l[4] or 1, l[5] or 1, 1, 1, 1)
    else tt:AddLine(l[1], l[3] or 1, l[4] or 1, l[5] or 1) end
  end
  tt:Show() -- resize to fit
end
TT._add = addLines

-- Hooks, once: the game's item-tooltip callback, plus the older setters (some Forever
-- tooltips don't go through the callback). The mark stops lines being added twice.
local hooked = false
function TT.Install()
  if hooked then return end
  hooked = true
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tt) pcall(addLines, tt) end)
  end
  for _, tt in ipairs({ GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2 }) do
    if tt then
      pcall(tt.HookScript, tt, "OnTooltipCleared", function(self) self[MARK] = nil end)
      pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self) pcall(addLines, self) end)
      for setter, linkOf in pairs(LINK_OF) do
        if tt[setter] then
          pcall(hooksecurefunc, tt, setter, function(self, ...)
            local ok, link = pcall(linkOf, ...)
            pcall(addLines, self, ok and link or nil)
          end)
        end
      end
    end
  end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() TT.Install() end)
