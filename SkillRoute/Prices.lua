-- Prices: SkillRoute's own auction house scan, the freshest of it and Auctionator per
-- item, and what you actually paid on the AH. Works without Auctionator.
--
-- Scan: one empty browse search reads the whole AH (the lowest price of every item
-- listed, a page at a time), so a full scan is one query instead of one per item. Only
-- the modern AH (C_AuctionHouse) is supported; on anything else the button explains.
local _, ns = ...
local Core = ns.Core
local Prices = {}
ns.Prices = Prices

local CHUNK = 1500        -- results stored per frame, so the game never stalls
local PAGE_TIMEOUT = 15   -- seconds without an answer before the scan gives up
local KEEP_PAID = 10      -- purchases kept per item
local PAID_DAYS = 30      -- a purchase older than this is no longer used as a price

local function now() return time() end

-- Prices are per realm and faction (the AH you can use).
local cachedKey -- realm and faction don't change in a session; prices are looked up a lot
local function bookKey()
  if cachedKey then return cachedKey end
  local realm = GetRealmName and GetRealmName()
  local faction = UnitFactionGroup and UnitFactionGroup("player")
  local k = (realm or "?") .. "-" .. (faction or "?")
  if realm and faction then cachedKey = k end
  return k
end
local function root(kind)
  SkillRouteDB = SkillRouteDB or {}
  SkillRouteDB[kind] = SkillRouteDB[kind] or {}
  local k = bookKey()
  SkillRouteDB[kind][k] = SkillRouteDB[kind][k] or {}
  return SkillRouteDB[kind][k]
end
-- { t = time of the scan, items = { [itemID] = lowest unit price } }
function Prices.Book() return root("prices") end
-- { [itemID] = { { q = qty, c = copper, t = time }, ... newest first } }
function Prices.Paid() return root("paid") end

-- Our own price: copper, age in whole days, time of the scan.
-- Our own price: copper, age in whole days, time of the scan. For materials the second
-- pass priced, the average cost of the amount your routes need (not the cheapest one).
function Prices.Own(item)
  local b = Prices.Book()
  local p = b.items and b.items[item]
  if not p then return nil end
  local d = b.depth and b.depth[item]
  return d and d.p or p, math.floor((now() - (b.t or 0)) / 86400), b.t
end

-- For tooltips: the cheapest listing and, if priced, the amount and its average.
function Prices.Detail(item)
  local b = Prices.Book()
  return b.items and b.items[item], b.depth and b.depth[item]
end

-- When Auctionator last scanned (its saved state, or the last update it told us of).
local aucUpdated = 0
function Prices.NoteAuctionatorUpdate() aucUpdated = now() end
local function auctionatorScanTime()
  local s = Auctionator and Auctionator.SavedState
  local t = aucUpdated
  if type(s) == "table" then
    for _, k in ipairs({ "TimeOfLastReplicateScan", "TimeOfLastGetAllScan" }) do
      if type(s[k]) == "number" and s[k] > t then t = s[k] end
    end
  end
  return t
end

-- The freshest AH price for an item: copper, age in days (nil = unknown), source.
-- aucPrice/aucAge come from Auctionator (nil if it isn't installed or has none).
-- Fewer days wins; on the same day, the later scan wins (ours when Auctionator's time
-- is unknown: ours is exact).
-- aucAge may be a function (asked only when needed: it's a second Auctionator call).
function Prices.Freshest(item, aucPrice, aucAge)
  local own, ownAge, ownT = Prices.Own(item)
  if not own then
    if type(aucAge) == "function" then aucAge = nil end -- not asked for: nothing to compare
    return aucPrice, aucAge, aucPrice and "Auctionator" or nil
  end
  if type(aucAge) == "function" then aucAge = aucPrice and aucAge() or nil end
  if not aucPrice then return own, ownAge, "SkillRoute scan" end
  if aucAge and aucAge < ownAge then return aucPrice, aucAge, "Auctionator" end
  if aucAge and aucAge == ownAge and auctionatorScanTime() > ownT then return aucPrice, aucAge, "Auctionator" end
  return own, ownAge, "SkillRoute scan"
end

-- What you last paid per unit on the AH, if within PAID_DAYS: copper, days ago.
function Prices.LastPaid(item)
  local lots = Prices.Paid()[item]
  local l = lots and lots[1]
  if not l or l.q <= 0 then return nil end
  local days = math.floor((now() - l.t) / 86400)
  if days > PAID_DAYS then return nil end
  return math.floor(l.c / l.q + 0.5), days
end

function Prices.RecordPaid(item, qty, copper)
  if not (item and qty and qty > 0 and copper and copper > 0) then return end
  local paid = Prices.Paid()
  local lots = paid[item] or {}
  paid[item] = lots
  table.insert(lots, 1, { q = qty, c = copper, t = now() })
  for i = #lots, KEEP_PAID + 1, -1 do lots[i] = nil end
  Core.Changed()
end

-- Scan ---------------------------------------------------------------------------------
local AH = C_AuctionHouse
function Prices.CanScan()
  AH = C_AuctionHouse
  return AH ~= nil and AH.SendBrowseQuery ~= nil and AH.GetBrowseResults ~= nil
    and AH.RequestMoreBrowseResults ~= nil and AH.HasFullBrowseResults ~= nil
end

local scan          -- nil, or { started, lastPage, phase = "read"|"store" }
local ours = false  -- true while we send our own query (so our hook ignores it)
local listeners = {}
function Prices.OnStatus(f) listeners[#listeners + 1] = f end
local function status(text)
  Prices.statusText = text
  for _, f in ipairs(listeners) do pcall(f, text) end
end
function Prices.Scanning() return scan ~= nil end

local function stop(msg)
  scan = nil
  status(nil)
  if msg then print("SkillRoute: " .. msg) end
end

local function ready()
  return not AH.IsThrottledMessageSystemReady or AH.IsThrottledMessageSystemReady()
end

-- Send fn() as soon as the AH accepts messages: on its "ready" event, with a check every
-- 0.3 s as a backup. Time spent waiting is added to scan.tWait (shown at the end).
local waiting -- { fn, since }
local function fire()
  local w = waiting
  if not (w and scan) then waiting = nil; return end
  if not ready() then return end
  waiting = nil
  scan.tWait = (scan.tWait or 0) + (GetTime() - w.since)
  w.fn()
end
local function poll() if waiting then fire(); if waiting then C_Timer.After(0.3, poll) end end end
local function whenReady(fn)
  if not scan then return end
  if ready() then fn(); return end
  local first = waiting == nil
  waiting = { fn = fn, since = GetTime() }
  if first then C_Timer.After(0.3, poll) end
end
Prices._fireReady = fire -- for the event handler below

local function watchdog()
  if not scan or scan.phase ~= "read" then return end
  if GetTime() - scan.lastPage > PAGE_TIMEOUT then
    stop("the auction house stopped answering; scan cancelled, nothing saved. Try again.")
  else
    C_Timer.After(5, watchdog)
  end
end

-- Store the results a chunk per frame, then replace the book in one go: an item not in
-- this complete read isn't listed any more, so its old price goes too.
local function store()
  scan.phase = "store"
  local results = AH.GetBrowseResults() or {}
  local items, i, n = {}, 1, #results
  local function step()
    if not scan then return end
    local last = math.min(n, i + CHUNK - 1)
    for k = i, last do
      local r = results[k]
      local id = r and r.itemKey and r.itemKey.itemID
      local p = r and r.minPrice
      if id and p and p > 0 and (not items[id] or p < items[id]) then items[id] = p end
    end
    i = last + 1
    if i <= n then
      status(("Saving prices... %d%%"):format(math.floor(100 * i / n)))
      C_Timer.After(0, step)
      return
    end
    local b = Prices.Book()
    local count = 0
    for _ in pairs(items) do count = count + 1 end
    b.items, b.t, b.count, b.depth = items, now(), count, {}
    scan.count, scan.readTime = count, GetTime() - scan.started
    Core.InvalidatePatterns()
    Core.Changed()
    Prices.DepthPass()
  end
  step()
end

-- The end-of-scan line, with where the time went.
local function summary(extra)
  return ("auction house scanned: %d items priced in %.0f s (%d pages: %.0f s waiting for the AH to allow the next one, %.0f s for pages to arrive)%s.")
    :format(scan.count or 0, scan.readTime or 0, scan.pages or 0, scan.tWaitRead or scan.tWait or 0, scan.tPage or 0, extra or "")
end

-- Second pass: the materials your routes will buy, one search each, to price the amount
-- you need along the price ladder (the full read only has each item's cheapest listing).
-- Results are kept item by item, so closing the AH partway keeps what was priced.
local DEPTH_TIMEOUT = 4
local sendDepth -- below
function Prices.DepthPass()
  local want = (SkillRouteDB.settings or {}).depth ~= false and Core.BuyList and Core.BuyList() or {}
  local list = {}
  for item, n in pairs(want) do if Prices.Book().items[item] then list[#list + 1] = { item = item, n = n } end end
  table.sort(list, function(a, b) return a.item < b.item end)
  if #list == 0 or not (AH.SendSearchQuery and AH.MakeItemKey) then stop(summary()); return end
  scan.tWaitRead = scan.tWait or 0
  scan.phase, scan.depthList, scan.depthI, scan.depthStart, scan.priced = "depth", list, 0, GetTime(), 0
  Prices.NextDepth()
end

function Prices.NextDepth()
  if not scan or scan.phase ~= "depth" then return end
  scan.depthI = scan.depthI + 1
  local d = scan.depthList[scan.depthI]
  if not d then
    stop(summary((" + %d of %d materials priced for the amounts you need (%.0f s)")
      :format(scan.priced, #scan.depthList, GetTime() - scan.depthStart)))
    Core.InvalidatePatterns(); Core.Changed()
    return
  end
  status(("Pricing the amounts you need... %d/%d"):format(scan.depthI, #scan.depthList))
  scan.current = d
  sendDepth(d)
end

-- Average price per unit of buying n from listings { {price, qty}, ... } (cheapest
-- first); beyond what's listed, at the dearest price seen.
function Prices.CostFor(tiers, n)
  local left, total, last = n, 0, nil
  for _, t in ipairs(tiers) do
    local take = math.min(left, t[2])
    total, left, last = total + take * t[1], left - take, t[1]
    if left <= 0 then break end
  end
  if left > 0 and last then total = total + left * last end
  return n > 0 and total / n or nil
end

-- The price ladder the AH holds for an item after a search (commodity or not), or nil.
local function readCommodity(item)
  if not AH.GetNumCommoditySearchResults then return nil end
  local n = AH.GetNumCommoditySearchResults(item) or 0
  if n == 0 then return nil end
  local tiers = {}
  for i = 1, math.min(100, n) do
    local r = AH.GetCommoditySearchResultInfo(item, i)
    if r and r.unitPrice and r.quantity then tiers[#tiers + 1] = { r.unitPrice, r.quantity } end
  end
  return tiers
end
local function readItems(key)
  if not AH.GetNumItemSearchResults then return nil end
  local n = AH.GetNumItemSearchResults(key) or 0
  if n == 0 then return nil end
  local tiers = {}
  for i = 1, math.min(100, n) do
    local r = AH.GetItemSearchResultInfo(key, i)
    if r and r.buyoutAmount and r.quantity and r.quantity > 0 then tiers[#tiers + 1] = { r.buyoutAmount / r.quantity, r.quantity } end
  end
  return tiers
end
Prices._readCommodity, Prices._readItems = readCommodity, readItems

-- Send the search for the material being priced.
function sendDepth(d)
  whenReady(function()
    if not (scan and scan.current == d) then return end
    ours = true
    pcall(AH.SendSearchQuery, AH.MakeItemKey(d.item),
      { { sortOrder = (Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price) or 0, reverseSort = false } }, false)
    ours = false
    d.sentAt = GetTime()
    local tries = d.tries or 0
    C_Timer.After(DEPTH_TIMEOUT, function()
      if not (scan and scan.current == d and (d.tries or 0) == tries) then return end
      -- no "results" event: the answer may be there anyway; else retry once, then skip
      local tiers = readCommodity(d.item) or readItems(AH.MakeItemKey(d.item))
      if tiers then Prices.DepthResult(d.item, tiers)
      elseif tries < 1 then d.tries = tries + 1; sendDepth(d)
      else scan.current = nil; Prices.NextDepth() end
    end)
  end)
end
Prices._resendDepth = function() if scan and scan.current then sendDepth(scan.current) end end

-- A search answer for the material being priced: store its price for the amount needed.
function Prices.DepthResult(item, tiers)
  local d = scan and scan.phase == "depth" and scan.current
  if not d or d.item ~= item then return end
  scan.current = nil
  table.sort(tiers, function(a, b) return a[1] < b[1] end)
  local avg = #tiers > 0 and Prices.CostFor(tiers, d.n)
  if avg then
    Prices.Book().depth[item] = { p = math.floor(avg + 0.5), n = d.n, listed = (function()
      local q = 0 for _, t in ipairs(tiers) do q = q + t[2] end return q end)() }
    scan.priced = scan.priced + 1
  end
  Prices.NextDepth()
end

local function nextPage()
  if not scan or scan.phase ~= "read" then return end
  local t = GetTime()
  scan.lastPage = t
  scan.pages = (scan.pages or 0) + 1
  if scan.sentAt then scan.tPage = (scan.tPage or 0) + (t - scan.sentAt); scan.sentAt = nil end
  if AH.HasFullBrowseResults() then store(); return end
  status(("Scanning the auction house... %d items"):format(#(AH.GetBrowseResults() or {})))
  whenReady(function() scan.sentAt = GetTime(); AH.RequestMoreBrowseResults() end)
end

function Prices.Scan()
  if scan then print("SkillRoute: a scan is already running."); return false end
  if not Core.ahOpen then print("SkillRoute: open the auction house first, then scan."); return false end
  if not Prices.CanScan() then
    print("SkillRoute: this client's auction house can't be scanned by SkillRoute. Auctionator's scan still works.")
    return false
  end
  scan = { started = GetTime(), lastPage = GetTime(), phase = "read" }
  status("Scanning the auction house...")
  whenReady(function()
    ours = true
    scan.sentAt = GetTime()
    local ok, err = pcall(AH.SendBrowseQuery, { searchString = "", sorts = {}, filters = {}, itemClassFilters = {} })
    ours = false
    if not ok then stop("the scan couldn't start: " .. tostring(err)); return end
    C_Timer.After(5, watchdog)
  end)
  return true
end

-- Someone else searching mid-scan replaces the browse results: stop rather than save a
-- mix. An empty search with no filters (e.g. Auctionator's own full scan) reads the same
-- listings, so the scan carries on.
local function foreignSearch(query)
  if not scan or scan.phase ~= "read" or ours then return end
  local q = type(query) == "table" and query or {}
  local empty = (q.searchString or "") == "" and not (q.filters and #q.filters > 0)
    and not (q.itemClassFilters and #q.itemClassFilters > 0) and not q.minLevel and not q.maxLevel
  if not empty then stop("scan stopped because another search started; nothing saved. Scan again when you're done.") end
end

-- What you pay on the AH (stackable goods: cloth, herbs, meat...) ---------------------
local pending -- { item, qty, total, money }
local function hookAH()
  AH = C_AuctionHouse
  if not AH or Prices.hooked then return end
  Prices.hooked = true
  if AH.SendBrowseQuery then hooksecurefunc(AH, "SendBrowseQuery", foreignSearch) end
  if AH.SendSearchQuery then hooksecurefunc(AH, "SendSearchQuery", function() foreignSearch({ searchString = "x" }) end) end
  if AH.StartCommoditiesPurchase then
    hooksecurefunc(AH, "StartCommoditiesPurchase", function(item, qty)
      pending = { item = item, qty = qty }
    end)
  end
  if AH.ConfirmCommoditiesPurchase then
    hooksecurefunc(AH, "ConfirmCommoditiesPurchase", function(item, qty)
      if pending and pending.item == item then pending.money = GetMoney(); pending.qty = qty or pending.qty end
    end)
  end
end

-- A Scan button on the auction house window itself (title bar, top left), so it's there
-- whichever SkillRoute window is open. Its label shows the scan's progress.
local ahBtn
local function attachButton()
  local parent = AuctionHouseFrame or AuctionFrame
  if not parent or ahBtn then return end
  ahBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  ahBtn:SetSize(150, 20)
  ahBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -1)
  ahBtn:SetFrameStrata("HIGH")
  ahBtn:SetScript("OnClick", function() Prices.Scan() end)
  ahBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText("SkillRoute: scan the auction house")
    GameTooltip:AddLine("Reads the lowest price of everything listed, in one search. SkillRoute uses the freshest of this and Auctionator's prices.", 1, 1, 1, true)
    local b = Prices.Book()
    if b.t then GameTooltip:AddLine(("Last scan: %s, %d items."):format(date("%b %d %H:%M", b.t), b.count or 0), 0.6, 0.6, 0.6, true) end
    GameTooltip:Show()
  end)
  ahBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  Prices.OnStatus(function(text)
    if not ahBtn then return end
    -- short labels: the button is narrow ("Scanning 28000", "Saving 60%")
    local label = text and (text:match("(%d+/%d+)") and ("Pricing " .. text:match("(%d+/%d+)"))
                            or text:match("(%d+) items") and ("Scanning " .. text:match("(%d+) items"))
                            or text:match("(%d+%%)") and ("Saving " .. text:match("(%d+%%)"))
                            or "Scanning...")
    ahBtn:SetText(label or "SkillRoute: Scan AH")
    if text then ahBtn:Disable() else ahBtn:Enable() end
  end)
  ahBtn:SetText("SkillRoute: Scan AH")
end

local f = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_LOGIN", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
  "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "AUCTION_HOUSE_BROWSE_FAILURE",
  "COMMODITY_PRICE_UPDATED", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED",
  "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
  "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED" }) do
  pcall(f.RegisterEvent, f, ev) -- an event this client doesn't have is just skipped
end
f:SetScript("OnEvent", function(_, ev, a, b)
  if ev == "PLAYER_LOGIN" or ev == "AUCTION_HOUSE_SHOW" then
    hookAH()
    if ev == "AUCTION_HOUSE_SHOW" then
      local ok, err = pcall(attachButton)
      if not ok then Core.ReportError("AH scan button", err) end
    end
  elseif ev == "AUCTION_HOUSE_CLOSED" then
    if scan and scan.phase == "depth" then
      stop(summary((" + %d materials priced for the amounts you need before the AH closed"):format(scan.priced)))
      Core.InvalidatePatterns(); Core.Changed()
    elseif scan then stop("auction house closed; scan cancelled, nothing saved.") end
    pending = nil
  elseif ev == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or ev == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
    nextPage()
  elseif ev == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    fire()
  elseif ev == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
    -- the AH dropped a request (sent too soon): send it again when it allows
    if scan and scan.phase == "depth" then Prices._resendDepth()
    elseif scan and scan.phase == "read" and scan.sentAt then
      whenReady(function()
        scan.sentAt = GetTime()
        if (scan.pages or 0) == 0 then -- the first search itself was dropped
          ours = true
          pcall(AH.SendBrowseQuery, { searchString = "", sorts = {}, filters = {}, itemClassFilters = {} })
          ours = false
        else AH.RequestMoreBrowseResults() end
      end)
    end
  elseif ev == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    local item = a
    if scan and scan.current and scan.current.item == item then Prices.DepthResult(item, readCommodity(item) or {}) end
  elseif ev == "ITEM_SEARCH_RESULTS_UPDATED" then
    local key = a
    local item = type(key) == "table" and key.itemID
    if item and scan and scan.current and scan.current.item == item then Prices.DepthResult(item, readItems(key) or {}) end
  elseif ev == "AUCTION_HOUSE_BROWSE_FAILURE" then
    if scan and scan.phase == "read" then stop("the auction house refused the scan; nothing saved. Try again in a moment.") end
  elseif ev == "COMMODITY_PRICE_UPDATED" then
    if pending then pending.total = b end -- (unitPrice, totalPrice)
  elseif ev == "COMMODITY_PURCHASE_SUCCEEDED" then
    if pending then
      local spent = pending.money and (pending.money - GetMoney()) or nil
      local total = pending.total or (spent and spent > 0 and spent) or nil
      Prices.RecordPaid(pending.item, pending.qty, total)
    end
    pending = nil
  elseif ev == "COMMODITY_PURCHASE_FAILED" then
    pending = nil
  end
end)
