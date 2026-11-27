-- Buying at the auction house without Auctionator: a panel beside the AH listing what a
-- step (or the whole shopping list) needs. Each material is two clicks:
--   1. Price: the AH quotes the exact total for that amount at today's listings.
--   2. Buy <total>: pays that quote.
-- Nothing is ever bought without a click, and you pay what you were shown: if the quote
-- changes, the button shows the new total and waits for another click. Stackable goods
-- (cloth, herbs, bars...) are bought by amount; one-of-a-kind items (rods, tools,
-- patterns) one listing per click: Price finds the cheapest listing, Buy pays exactly it.
local _, ns = ...
local Core, UI = ns.Core, ns.UI
local BP = {}
ns.BuyPanel = BP

local W, ROWS = 330, 10
local panel
local rows = {}
local items = {}      -- { item, name, qty, state, total, unit, quotedAt, err }
local busy            -- the item whose quote or purchase is in flight
local page = 0        -- first item shown minus 1 (pages of ROWS)
local AH = function() return C_AuctionHouse end

function BP.CanUse()
  local A = AH()
  return A and A.StartCommoditiesPurchase and A.ConfirmCommoditiesPurchase and true or false
end

-- Single listings (rods, patterns): search the item, pay one listing's buyout.
local function canBuyListings()
  local A = AH()
  return A and A.MakeItemKey and A.SendSearchQuery and A.GetNumItemSearchResults and A.GetItemSearchResultInfo
    and A.PlaceBid and true or false
end
BP.CanBuyListings = canBuyListings

local money = function(c) return UI.Money(c) end

local function setRow(row)
  local i = page + row
  local r, x = rows[row], items[i]
  if not x then r.name:Hide(); r.info:Hide(); r.btn:Hide(); return end
  r.name:Show(); r.info:Show(); r.btn:Show()
  r.name:SetText(("%d x %s"):format(x.qty, x.name))
  local idle = busy == nil or (items[busy] and items[busy].state == "quoted") -- nothing in flight
  local info, label, enabled = "", "Price", idle
  if x.state == "quoting" then info, label, enabled = "|cff999999asking the AH...|r", "Price", false
  elseif x.state == "quoted" then
    info = ("%s each"):format(money(x.unit or 0))
    if x.kind == "item" then -- one listing: the cheapest; more listings after it
      info = x.qty > 1 and ("cheapest listing, %d of %d"):format((x.got or 0) + 1, x.qty) or "the cheapest listing"
    end
    label = "Buy " .. money(x.total)
    if GetMoney and GetMoney() < x.total then info, label, enabled = "|cffff4040not enough gold|r", "Buy", false
    else enabled = true end
    if x.warn then info = info .. "  |cffff8040" .. x.warn .. "|r" end
  elseif x.state == "buying" then info, label, enabled = "|cff999999buying...|r", "Buy", false
  elseif x.state == "bought" then
    local paid = x.kind == "item" and x.spent or x.total
    info, label, enabled = paid and ("|cff40bf40bought for %s|r"):format(money(paid)) or "|cff40bf40bought|r", "Done", false
  elseif x.state == "none" then info, label = "|cffff8040none listed right now|r", "Price"
  elseif x.state == "search" then
    -- no quote for an amount (one-of-a-kind items such as rods, or none listed): the AH's own list
    info, label = "|cffff8040Search, then buy from the list|r", "Search"
  elseif x.state == "failed" then info, label = "|cffff4040" .. (x.err or "failed") .. ": try again|r", "Price" end
  r.info:SetText(info)
  r.btn:SetText(label)
  if enabled then r.btn:Enable() else r.btn:Disable() end
end

function BP.Refresh()
  if not panel then return end
  for row = 1, ROWS do setRow(row) end
  local left = 0
  for _, x in ipairs(items) do if x.state ~= "bought" then left = left + 1 end end
  local pages = math.max(1, math.ceil(#items / ROWS))
  -- as tall as what it lists (1 to ROWS rows), plus room for the page buttons
  local shown = math.max(1, math.min(ROWS, #items - page))
  panel:SetHeight(72 + shown * 34 + (pages > 1 and 10 or 0))
  if pages > 1 then
    panel.foot:SetText(("Page %d of %d"):format(page / ROWS + 1, pages))
    panel.prev:Show(); panel.next:Show()
    if page > 0 then panel.prev:Enable() else panel.prev:Disable() end
    if page + ROWS < #items then panel.next:Enable() else panel.next:Disable() end
  else
    panel.prev:Hide(); panel.next:Hide()
    panel.foot:SetText(left == 0 and "|cff40bf40All bought.|r" or "Price, then Buy: you pay exactly the price shown.")
  end
end
function BP.Page(delta)
  page = math.max(0, math.min(page + delta * ROWS, (math.ceil(#items / ROWS) - 1) * ROWS))
  BP.Refresh()
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
  if x.kind == "item" then BP.QuoteListing(i); return end
  local ok = pcall(A.StartCommoditiesPurchase, x.item, x.qty)
  if not ok then x.state, x.err, busy = "failed", "the AH refused", nil end
  BP.Refresh()
end

-- One-of-a-kind items: the cheapest listing that isn't yours, from an item search.
local function readListing(x)
  local A = AH()
  local key = A.MakeItemKey(x.item)
  local n = A.GetNumItemSearchResults(key) or 0
  local best
  for k = 1, math.min(n, 100) do
    local r = A.GetItemSearchResultInfo(key, k)
    if r and r.auctionID and r.buyoutAmount and r.buyoutAmount > 0 and (r.quantity or 0) > 0
       and not r.containsOwnerItem and (not best or r.buyoutAmount / r.quantity < best.buyoutAmount / best.quantity) then
      best = r
    end
  end
  return best
end

local LISTING_WAIT = 5 -- seconds for the AH to answer a search
function BP.QuoteListing(i)
  local x = items[i]
  local A = AH()
  x.state, x.listing = "quoting", nil
  local sentAt = GetTime()
  x.searchedAt = sentAt
  local ok = pcall(A.SendSearchQuery, A.MakeItemKey(x.item),
    { { sortOrder = (Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price) or 0, reverseSort = false } }, true)
  if not ok then x.state, x.err, busy = "failed", "the AH refused", nil; BP.Refresh(); return end
  BP.Refresh()
  -- the answer can come without its event: look every 0.25 s, up to LISTING_WAIT
  local function check()
    if busy ~= i or x.state ~= "quoting" or x.searchedAt ~= sentAt then return end
    local best = readListing(x)
    if best then BP.ListingFound(i, best)
    elseif GetTime() - sentAt >= LISTING_WAIT then
      -- a stackable good with too few listed for the amount: the AH's own list (buy what
      -- there is); otherwise none listed (or only yours)
      local A2 = AH()
      local stack = A2.GetNumCommoditySearchResults and (A2.GetNumCommoditySearchResults(x.item) or 0) > 0
      x.state, busy = stack and "search" or "none", nil
      BP.Refresh()
    else C_Timer.After(0.25, check) end
  end
  C_Timer.After(0.25, check)
end

function BP.ListingFound(i, r)
  local x = items[i]
  if not x or x.state ~= "quoting" then return end
  x.listing = { id = r.auctionID, price = r.buyoutAmount, q = r.quantity }
  x.state, x.total, x.unit, x.quotedAt = "quoted", r.buyoutAmount, math.floor(r.buyoutAmount / r.quantity), GetTime()
  if x.expect and x.expect > 0 and x.unit > x.expect * 1.5 then x.warn = "much more than expected" end
  BP.Refresh()
end

-- A listing bought: count it, then find the next one if more are needed.
local function listingBought(i)
  local x = items[i]
  local l = x.listing
  if not (x and l) or x.state ~= "buying" then return end
  x.got, x.spent, x.listing = (x.got or 0) + l.q, (x.spent or 0) + l.price, nil
  if ns.Prices and ns.Prices.RecordPaid then ns.Prices.RecordPaid(x.item, l.q, l.price) end
  Core.AddToMail(x.item, l.q) -- arrives by mail: don't buy it again
  busy = nil
  if x.got >= x.qty then x.state = "bought"; BP.Refresh()
  else busy = i; BP.QuoteListing(i) end -- the next listing (a search, not a purchase)
end
BP._listingBought = listingBought

-- Pay the quote shown on the button.
local function buy(i)
  local x = items[i]
  if x.state ~= "quoted" or busy ~= i then return end
  -- a quote that changed in the last moment hasn't been seen yet: show it, don't pay it
  if GetTime() - (x.quotedAt or 0) < 0.4 then return end
  if GetMoney and GetMoney() < (x.total or 0) then return end -- not enough gold
  x.state = "buying"
  if x.kind == "item" then
    -- pay exactly this listing's buyout (if it's gone, the AH refuses: nothing is paid)
    local l, before = x.listing, GetMoney and GetMoney() or nil
    local ok = l and pcall(AH().PlaceBid, l.id, l.price)
    if not ok then x.state, x.err, busy = "failed", "the purchase didn't start", nil; BP.Refresh(); return end
    BP.Refresh()
    -- no "bought" event on some clients: the gold leaving your bags says so
    C_Timer.After(4, function()
      if x.state ~= "buying" or x.listing ~= l then return end
      if before and GetMoney and GetMoney() <= before - l.price then listingBought(i)
      else x.state, x.err, busy = "failed", "not bought (someone may have bought it first)", nil; BP.Refresh() end
    end)
    return
  end
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
    if r.info.SetWordWrap then r.info:SetWordWrap(false) end -- one line: never runs into the next row
    r.btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    r.btn:SetSize(110, 22); r.btn:SetPoint("TOPRIGHT", -10, y - 3)
    r.btn:SetScript("OnClick", function() click(page + i) end)
    rows[i] = r
  end
  panel.prev = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.prev:SetSize(60, 20); panel.prev:SetPoint("BOTTOMRIGHT", -76, 8); panel.prev:SetText("< Prev")
  panel.prev:SetScript("OnClick", function() BP.Page(-1) end)
  panel.next = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.next:SetSize(60, 20); panel.next:SetPoint("BOTTOMRIGHT", -10, 8); panel.next:SetText("Next >")
  panel.next:SetScript("OnClick", function() BP.Page(1) end)
  panel.foot = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  panel.foot:SetPoint("BOTTOMLEFT", 12, 12); panel.foot:SetWidth(W - 24); panel.foot:SetJustifyH("LEFT")
  panel:Hide()
end

-- Open the panel with { {item, name, qty, expect = estimated copper each}, ... }.
function BP.Open(list, title)
  if not panel then build() end
  if busy and items[busy] and AH() and AH().CancelCommoditiesPurchase then pcall(AH().CancelCommoditiesPurchase) end
  busy, page = nil, 0
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
  "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_CLOSED", "ITEM_SEARCH_RESULTS_UPDATED",
  "AUCTION_HOUSE_PURCHASE_COMPLETED", "AUCTION_HOUSE_SHOW_ERROR" }) do pcall(f.RegisterEvent, f, ev) end
f:SetScript("OnEvent", function(_, ev, a, b)
  if ev == "AUCTION_HOUSE_CLOSED" then
    busy = nil
    if panel then panel:Hide() end
    return
  end
  local x = busy and items[busy]
  if not x then return end
  -- one-of-a-kind items
  if x.kind == "item" then
    if ev == "ITEM_SEARCH_RESULTS_UPDATED" and x.state == "quoting" and type(a) == "table" and a.itemID == x.item then
      local best = readListing(x)
      if best then BP.ListingFound(busy, best) end
    elseif ev == "AUCTION_HOUSE_PURCHASE_COMPLETED" and x.state == "buying" and x.listing and a == x.listing.id then
      listingBought(busy)
    elseif ev == "AUCTION_HOUSE_SHOW_ERROR" and x.state == "buying" then
      x.state, x.err, busy = "failed", "the AH refused the purchase", nil
      BP.Refresh()
    end
    return
  end
  if ev == "COMMODITY_PRICE_UPDATED" and x.state ~= "quoting" and x.state ~= "quoted" then return end
  if (ev == "COMMODITY_PURCHASE_SUCCEEDED" or ev == "COMMODITY_PURCHASE_FAILED") and x.state ~= "buying" then
    return -- someone else's purchase (the AH's own window, another addon), not this one
  end
  if ev == "COMMODITY_PRICE_UPDATED" then -- (unitPrice, totalPrice): a new quote, to be clicked again
    x.state, x.unit, x.total, x.quotedAt = "quoted", a, b, GetTime()
    if x.expect and x.expect > 0 and a and a > x.expect * 1.5 then x.warn = "much more than expected" end
  elseif ev == "COMMODITY_PRICE_UNAVAILABLE" then -- not a commodity (a rod, a pattern), or none listed
    if canBuyListings() then
      x.kind = "item" -- buy it one listing at a time
      BP.QuoteListing(busy)
      return
    end
    x.state, busy = "search", nil
  elseif ev == "COMMODITY_PURCHASE_SUCCEEDED" then
    x.state, busy = "bought", nil
    Core.Changed()
  elseif ev == "COMMODITY_PURCHASE_FAILED" then
    x.state, x.err, busy = "failed", "the purchase failed", nil
  end
  BP.Refresh()
end)
