-- Buying at the auction house without Auctionator: a panel beside the AH listing what a
-- step (or the whole shopping list) needs. Each material is two clicks:
--   1. Price: the AH quotes the exact total for that amount at today's listings.
--   2. Buy <total>: pays that quote.
-- Nothing is ever bought without a click, and you pay what you were shown: if the quote
-- changes, the button shows the new total and waits for another click. Only stackable
-- goods (cloth, herbs, bars...) can be bought this way; anything else gets Search.
local _, ns = ...
local Core, UI = ns.Core, ns.UI
local BP = {}
ns.BuyPanel = BP

local W, ROWS = 330, 10
local panel
local rows = {}
local items = {}      -- { item, name, qty, state, total, unit, quotedAt, err }
local busy            -- the row whose quote or purchase is in flight
local AH = function() return C_AuctionHouse end

function BP.CanUse()
  local A = AH()
  return A and A.StartCommoditiesPurchase and A.ConfirmCommoditiesPurchase and true or false
end

local money = function(c) return UI.Money(c) end

local function setRow(i)
  local r, x = rows[i], items[i]
  if not x then r.name:Hide(); r.info:Hide(); r.btn:Hide(); return end
  r.name:Show(); r.info:Show(); r.btn:Show()
  r.name:SetText(("%d x %s"):format(x.qty, x.name))
  local idle = busy == nil or (items[busy] and items[busy].state == "quoted") -- nothing in flight
  local info, label, enabled = "", "Price", idle
  if x.state == "quoting" then info, label, enabled = "|cff999999asking the AH...|r", "Price", false
  elseif x.state == "quoted" then
    info = ("%s each"):format(money(x.unit or 0))
    label = "Buy " .. money(x.total)
    if GetMoney and GetMoney() < x.total then info, label, enabled = "|cffff4040not enough gold|r", "Buy", false
    else enabled = true end
    if x.warn then info = info .. "  |cffff8040" .. x.warn .. "|r" end
  elseif x.state == "buying" then info, label, enabled = "|cff999999buying...|r", "Buy", false
  elseif x.state == "bought" then info, label, enabled = "|cff40bf40bought|r", "Done", false
  elseif x.state == "search" then info, label = "|cffff8040not a stackable item|r", "Search"
  elseif x.state == "failed" then info, label = "|cffff4040" .. (x.err or "failed") .. ": try again|r", "Price" end
  r.info:SetText(info)
  r.btn:SetText(label)
  if enabled then r.btn:Enable() else r.btn:Disable() end
end

function BP.Refresh()
  if not panel then return end
  for i = 1, ROWS do setRow(i) end
  local left = 0
  for _, x in ipairs(items) do if x.state ~= "bought" then left = left + 1 end end
  panel.foot:SetText(#items > ROWS and ("+ %d more after these"):format(#items - ROWS)
    or left == 0 and "|cff40bf40All bought.|r" or "Price, then Buy: you pay exactly the price shown.")
end

-- Ask the AH for the exact total of one material.
local function quote(i)
  local x = items[i]
  local A = AH()
  if busy and busy ~= i then
    -- another material's quote not taken: drop it (it can be priced again); anything in
    -- flight has to finish first
    if items[busy].state ~= "quoted" then return end
    if A.CancelCommoditiesPurchase then pcall(A.CancelCommoditiesPurchase) end
    items[busy].state = "new"
  elseif busy == i and A.CancelCommoditiesPurchase then pcall(A.CancelCommoditiesPurchase) end
  busy = i
  x.state, x.total, x.unit, x.warn = "quoting", nil, nil, nil
  local ok = pcall(A.StartCommoditiesPurchase, x.item, x.qty)
  if not ok then x.state, x.err, busy = "failed", "the AH refused", nil end
  BP.Refresh()
end

-- Pay the quote shown on the button.
local function buy(i)
  local x = items[i]
  if x.state ~= "quoted" or busy ~= i then return end
  -- a quote that changed in the last moment hasn't been seen yet: show it, don't pay it
  if GetTime() - (x.quotedAt or 0) < 0.4 then return end
  if GetMoney and GetMoney() < (x.total or 0) then return end -- not enough gold
  x.state = "buying"
  local ok = pcall(AH().ConfirmCommoditiesPurchase, x.item, x.qty)
  if not ok then x.state, x.err, busy = "failed", "the purchase didn't start", nil end
  BP.Refresh()
end

local function click(i)
  local x = items[i]
  if not x then return end
  if x.state == "quoted" then buy(i)
  elseif x.state == "search" then Core.SearchAH(x.name)
  elseif x.state ~= "bought" and x.state ~= "buying" and x.state ~= "quoting" then quote(i) end
end
BP._click = click

local function build()
  local parent = AuctionHouseFrame or UIParent
  panel = CreateFrame("Frame", "SkillRouteBuy", parent, "BasicFrameTemplateWithInset")
  panel:SetSize(W, 72 + ROWS * 34)
  if parent ~= UIParent then panel:SetPoint("TOPLEFT", parent, "TOPRIGHT", 4, 0) else panel:SetPoint("CENTER") end
  panel:SetFrameStrata("HIGH")
  panel:SetMovable(true); panel:EnableMouse(true); panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  panel:SetScript("OnHide", function()
    if busy and items[busy] and items[busy].state == "quoted" and AH() and AH().CancelCommoditiesPurchase then
      pcall(AH().CancelCommoditiesPurchase)
    end
    busy = nil
  end)
  panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  panel.title:SetPoint("TOP", 0, -5)
  for i = 1, ROWS do
    local r = {}
    local y = -32 - (i - 1) * 34
    r.name = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetPoint("TOPLEFT", 12, y); r.name:SetWidth(W - 130); r.name:SetJustifyH("LEFT")
    r.info = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.info:SetPoint("TOPLEFT", 12, y - 15); r.info:SetWidth(W - 130); r.info:SetJustifyH("LEFT")
    r.btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    r.btn:SetSize(110, 22); r.btn:SetPoint("TOPRIGHT", -10, y - 3)
    r.btn:SetScript("OnClick", function() click(i) end)
    rows[i] = r
  end
  panel.foot = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  panel.foot:SetPoint("BOTTOMLEFT", 12, 12); panel.foot:SetWidth(W - 24); panel.foot:SetJustifyH("LEFT")
  panel:Hide()
end

-- Open the panel with { {item, name, qty, expect = estimated copper each}, ... }.
function BP.Open(list, title)
  if not panel then build() end
  if busy and items[busy] and AH() and AH().CancelCommoditiesPurchase then pcall(AH().CancelCommoditiesPurchase) end
  busy = nil
  wipe(items)
  for _, x in ipairs(list) do
    items[#items + 1] = { item = x.item, name = x.name, qty = x.qty, expect = x.expect, state = "new" }
  end
  panel.title:SetText(title or "SkillRoute: buy")
  panel:Show()
  BP.Refresh()
  return true
end

function BP.IsShown() return panel and panel:IsShown() end
function BP.Items() return items end

-- AH answers ---------------------------------------------------------------------------
local f = CreateFrame("Frame")
for _, ev in ipairs({ "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED",
  "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_CLOSED" }) do pcall(f.RegisterEvent, f, ev) end
f:SetScript("OnEvent", function(_, ev, a, b)
  if ev == "AUCTION_HOUSE_CLOSED" then
    busy = nil
    if panel then panel:Hide() end
    return
  end
  local x = busy and items[busy]
  if not x then return end
  if ev == "COMMODITY_PRICE_UPDATED" then -- (unitPrice, totalPrice): a new quote, to be clicked again
    x.state, x.unit, x.total, x.quotedAt = "quoted", a, b, GetTime()
    if x.expect and x.expect > 0 and a and a > x.expect * 1.5 then x.warn = "much more than expected" end
  elseif ev == "COMMODITY_PRICE_UNAVAILABLE" then -- not a commodity, or none listed
    x.state, busy = "search", nil
  elseif ev == "COMMODITY_PURCHASE_SUCCEEDED" then
    x.state, busy = "bought", nil
    Core.Changed()
  elseif ev == "COMMODITY_PURCHASE_FAILED" then
    x.state, x.err, busy = "failed", "the purchase failed", nil
  end
  BP.Refresh()
end)
