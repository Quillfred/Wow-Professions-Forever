-- Recorder: with /sr log on, quietly writes down what the game tells addons about the
-- data SkillRoute can't confirm offline (trainers, vendors, fishing, disenchanting,
-- gathering, boat times) into SkillRouteDB.log, and walks you through the checks one
-- step at a time. Send the SavedVariables file (WTF/Account/<account>/SavedVariables/
-- SkillRoute.lua) afterwards: it holds everything recorded.
local _, ns = ...
local Core, Data = ns.Core, SkillRouteData
local R = {}
ns.Recorder = R

local MAX_ENTRIES = 3000
local DISENCHANT = 13262
local FELWOOD_SECONDS = 600

local function log()
  SkillRouteDB = SkillRouteDB or {}
  local l = SkillRouteDB.log
  if not l then
    l = { on = false, entries = {}, done = {}, skipped = {}, fishing = {}, zoneTime = {}, boats = {} }
    SkillRouteDB.log = l
  end
  return l
end

local function say(msg) print("|cff33ccffSkillRoute log:|r " .. msg) end

local function spellName(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function npcID()
  local g = UnitGUID and UnitGUID("npc")
  local id = g and select(6, strsplit("-", g))
  return id and tonumber(id)
end

local function where()
  local m = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local p = m and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(m, "player")
  local info = m and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
  local x, y
  if p then x, y = p.GetXY and p:GetXY() end
  return (info and info.name) or (GetRealZoneText and GetRealZoneText()) or "?",
         x and math.floor(x * 1000 + 0.5) / 10, y and math.floor(y * 1000 + 0.5) / 10
end

local function skills()
  local out = {}
  for line, s in pairs(Core.Skills()) do out[Data.professions[line].name] = s.rank .. "/" .. s.max end
  return out
end

local function add(kind, t)
  local l = log()
  t.kind, t.time = kind, time and time() or nil
  t.zone, t.x, t.y = where()
  t.level = UnitLevel and UnitLevel("player")
  l.entries[#l.entries + 1] = t
  while #l.entries > MAX_ENTRIES do table.remove(l.entries, 1) end
  return t
end

-- Steps -------------------------------------------------------------------------------
local function count(kind, test)
  local n = 0
  for _, e in ipairs(log().entries) do if e.kind == kind and (not test or test(e)) then n = n + 1 end end
  return n
end
local function has(line) return Core.Skills()[line] ~= nil end
local function maxFishCasts()
  local best, zone = 0, nil
  for z, c in pairs(log().fishing) do if c.casts > best then best, zone = c.casts, z end end
  return best, zone
end

-- the artisan-level trainer of your first crafting profession, for the gating check
local function artisanTrainerHint()
  if not has(197) then return "the highest-rank trainer of one of your crafting professions" end
  local mine = UnitFactionGroup and UnitFactionGroup("player")
  return mine == "Alliance" and "Georgio Bolero (Artisan Tailor, Stormwind)"
         or "Josef Gregorian (Artisan Tailor, Undercity, 70.8 29.2)"
end

R.steps = {
  { id = "trainer", text = function() return "Talk to " .. artisanTrainerHint()
      .. " and open the training window (even if it's empty or he won't train you). If he only talks, that's recorded too." end,
    done = function() return count("trainer") + count("gossip") >= 1 end },
  { id = "trainer2", text = "Open the training window of any other trainer of your professions (a lower-rank one is best).",
    done = function() return count("trainer") >= 2 end },
  { id = "vendor", text = "Open any Trade Supplies or general goods vendor (thread, dyes, vials, spices).",
    done = function() return count("vendor") >= 1 end },
  { id = "disenchant", text = "Disenchant any green item.", applies = function() return has(333) end,
    done = function() return count("disenchant") >= 1 end },
  { id = "disenchant5", text = "Disenchant 4 more items when you have them (different item levels help most).",
    applies = function() return has(333) end, done = function() return count("disenchant") >= 5 end,
    progress = function() return count("disenchant") .. "/5" end },
  { id = "deskill", text = "Try to disenchant a green that's above your Enchanting skill (item level 46-50 below skill 150): the error message is recorded. /sr log skip if you have none.",
    applies = function() return has(333) end,
    done = function() return count("error", function(e) return e.spell == DISENCHANT end) >= 1 end },
  { id = "fish", text = "Fish 20 casts in one zone (where your skill is near the zone's level is best).",
    applies = function() return has(356) end, done = function() return maxFishCasts() >= 20 end,
    progress = function() local n, z = maxFishCasts(); return ("%d/20%s"):format(n, z and (" in " .. z) or "") end },
  { id = "felwood", text = "Ride around Felwood for 10 minutes with Find Herbs on; gather any herb you see.",
    applies = function() return has(182) end, done = function() return (log().zoneTime.Felwood or 0) >= FELWOOD_SECONDS end,
    progress = function() return ("%d/10 min"):format(math.floor((log().zoneTime.Felwood or 0) / 60)) end },
  { id = "boat", text = "At a zeppelin tower or dock: type /sr log boat when the ship leaves, and again when the same ship leaves next.",
    done = function()
      local b = log().boats
      for i = 2, #b do if b[i].zone == b[i - 1].zone and b[i].time - b[i - 1].time > 60 then return true end end
      return false
    end,
    progress = function() return #log().boats .. " mark(s)" end },
}

local function stepText(s) return type(s.text) == "function" and s.text() or s.text end
local function stepState(s)
  local l = log()
  if l.skipped[s.id] then return "skipped" end
  if s.applies and not s.applies() then return "n/a" end
  if l.done[s.id] then return "done" end
  return "open"
end

function R.Current()
  for _, s in ipairs(R.steps) do if stepState(s) == "open" then return s end end
end

-- after anything is recorded: mark finished steps, say the next one
function R.Advance()
  local l = log()
  if not l.on then return end
  local finished
  for _, s in ipairs(R.steps) do
    if stepState(s) == "open" and s.done() then l.done[s.id] = true; finished = s end
  end
  if finished then
    local nxt = R.Current()
    say("|cff40bf40done:|r " .. stepText(finished))
    if nxt then say("|cffffd100next:|r " .. stepText(nxt))
    else say("|cff40bf40all checks done.|r Log out (or /reload) and send WTF/Account/<account>/SavedVariables/SkillRoute.lua. /sr log off to stop recording.") end
  end
  if R.Refresh then R.Refresh() end
end

-- Recording ---------------------------------------------------------------------------
local function trainerScan()
  if not (GetNumTrainerServices and GetTrainerServiceInfo) then return end
  local services = {}
  for i = 1, math.min(GetNumTrainerServices() or 0, 120) do
    local name, sub, kind = GetTrainerServiceInfo(i)
    local skill, req = nil, nil
    if GetTrainerServiceSkillReq then skill, req = GetTrainerServiceSkillReq(i) end
    services[#services + 1] = { name = name, sub = sub, type = kind, skill = skill, req = req,
      level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or nil,
      cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or nil }
  end
  local filters = {}
  if GetTrainerServiceTypeFilter then
    for _, f in ipairs({ "available", "unavailable", "used" }) do filters[f] = GetTrainerServiceTypeFilter(f) and true or false end
  end
  add("trainer", { npc = UnitName and UnitName("npc"), id = npcID(), skills = skills(), services = services,
                   greeting = GetTrainerGreetingText and GetTrainerGreetingText() or nil, filters = filters,
                   count = GetNumTrainerServices() })
end

local function gossipScan()
  local text = C_GossipInfo and C_GossipInfo.GetText and C_GossipInfo.GetText() or (GetGossipText and GetGossipText())
  local opts = {}
  if C_GossipInfo and C_GossipInfo.GetOptions then
    for _, o in ipairs(C_GossipInfo.GetOptions() or {}) do opts[#opts + 1] = o.name end
  end
  add("gossip", { npc = UnitName and UnitName("npc"), id = npcID(), text = text, options = opts, skills = skills() })
end

local function vendorScan()
  local n = (GetMerchantNumItems and GetMerchantNumItems()) or (C_MerchantFrame and C_MerchantFrame.GetNumItems and C_MerchantFrame.GetNumItems()) or 0
  local items = {}
  for i = 1, math.min(n, 150) do
    local id = GetMerchantItemID and GetMerchantItemID(i)
    local price, avail, usable
    if GetMerchantItemInfo then
      local _, _, p, _, a, _, u = GetMerchantItemInfo(i)
      price, avail, usable = p, a, u
    elseif C_MerchantFrame and C_MerchantFrame.GetItemInfo then
      local info = C_MerchantFrame.GetItemInfo(i)
      if type(info) == "table" then price, avail, usable = info.price, info.numAvailable, info.isUsable end
    end
    if id then items[#items + 1] = { id, price, avail, usable } end
  end
  add("vendor", { npc = UnitName and UnitName("npc"), id = npcID(), items = items })
end

-- bags snapshot (item -> count) to find which item a disenchant used up
local function bagCounts()
  local out = {}
  local slots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local itemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
  if not (slots and itemID) then return out end
  for bag = 0, 4 do
    for slot = 1, slots(bag) or 0 do
      local id = itemID(bag, slot)
      if id then out[id] = true end
    end
  end
  local count = (C_Item and C_Item.GetItemCount) or GetItemCount
  for id in pairs(out) do out[id] = count and count(id) or 1 end
  return out
end

local pending -- the spell in progress: { spell, time, bags }
local fishingName
local function isFishing(id)
  fishingName = fishingName or (Data.professions[356] and Data.professions[356].spell and spellName(Data.professions[356].spell))
  local n = spellName(id)
  return n and fishingName and n == fishingName
end

local function lootItems()
  local out = {}
  for i = 1, (GetNumLootItems and GetNumLootItems()) or 0 do
    local link = GetLootSlotLink and GetLootSlotLink(i)
    local id = link and tonumber(link:match("item:(%d+)"))
    local name, qty
    if GetLootSlotInfo then
      local _, n, q = GetLootSlotInfo(i) -- (not "x and f()": that keeps only the first value)
      name, qty = n, q
    end
    out[#out + 1] = { id or name, qty }
  end
  return out
end

local lastLoot = 0
local gatherNames
local function isGather(id)
  if not gatherNames then
    gatherNames = {}
    for _, s in ipairs({ 2366, 2575, 8613 }) do local n = spellName(s); if n then gatherNames[n] = true end end
  end
  local n = spellName(id)
  return n and gatherNames[n]
end
local function onLoot()
  local l = log()
  if GetTime() - lastLoot < 1 then return end -- one loot window can fire twice
  lastLoot = GetTime()
  if IsFishingLoot and IsFishingLoot() then
    local zone = where()
    local f = l.fishing[zone] or { casts = 0, caught = 0, away = 0 }
    f.caught = f.caught + 1
    l.fishing[zone] = f
    add("fish", { result = "caught", loot = lootItems(), skills = skills() })
    return
  end
  if pending and pending.spell == DISENCHANT and (GetTime() - pending.time) < 10 then
    local loot, before = lootItems(), pending.bags
    pending = nil
    -- the item that left your bags is the one disenchanted (bags settle a moment later)
    C_Timer.After(1, function()
      local after = bagCounts()
      local used
      for id, n in pairs(before) do if (after[id] or 0) < n then used = id end end
      local info = used and { GetItemInfo(used) }
      add("disenchant", { item = used, ilvl = info and info[4], quality = info and info[3],
                          class = info and info[12], loot = loot, skills = skills() })
      R.Advance()
    end)
    return
  end
  if pending and (GetTime() - pending.time) < 10 and isGather(pending.spell) then -- herb, ore, skinning
    add("gather", { spell = pending.spell, spellName = spellName(pending.spell), loot = lootItems(), skills = skills() })
    pending = nil
  end
end

local function onError(msg)
  local l = log()
  local recent = pending and (GetTime() - pending.time) < 10
  if msg == ERR_FISH_ESCAPED or msg == ERR_FISH_NOT_HOOKED then
    local zone = where()
    local f = l.fishing[zone] or { casts = 0, caught = 0, away = 0 }
    if msg == ERR_FISH_ESCAPED then f.away = f.away + 1 end
    l.fishing[zone] = f
    add("fish", { result = msg == ERR_FISH_ESCAPED and "got away" or "not hooked", skills = skills() })
    return
  end
  if recent then add("error", { spell = pending.spell, spellName = spellName(pending.spell), text = msg, skills = skills() }) end
end

-- Felwood (and any zone) time while logging, for the herb check
local ticker, lastTick
local function tick()
  local l = log()
  if not l.on then return end
  local now = GetTime()
  if lastTick then
    local zone = where()
    l.zoneTime[zone] = (l.zoneTime[zone] or 0) + math.min(now - lastTick, 30)
  end
  lastTick = now
  R.Advance()
end

local f = CreateFrame("Frame")
local EVENTS = { "TRAINER_SHOW", "GOSSIP_SHOW", "MERCHANT_SHOW", "LOOT_READY", "UI_ERROR_MESSAGE",
                 "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START" }
f:SetScript("OnEvent", function(_, ev, a1, a2, a3, a4)
  local ok, err = pcall(function()
    if not log().on then return end
    if ev == "TRAINER_SHOW" then trainerScan()
    elseif ev == "GOSSIP_SHOW" then gossipScan()
    elseif ev == "MERCHANT_SHOW" then vendorScan()
    elseif ev == "LOOT_READY" then onLoot()
    elseif ev == "UI_ERROR_MESSAGE" then onError(a2 or a1)
    elseif ev == "UNIT_SPELLCAST_SENT" and a1 == "player" then
      pending = { spell = a4, time = GetTime(), bags = a4 == DISENCHANT and bagCounts() or nil }
    elseif ev == "UNIT_SPELLCAST_SUCCEEDED" and a1 == "player" then
      if pending and pending.spell == a3 then pending.time = GetTime() else pending = { spell = a3, time = GetTime() } end
    elseif ev == "UNIT_SPELLCAST_CHANNEL_START" and a1 == "player" and isFishing(a3) then
      local zone = where()
      local fz = log().fishing[zone] or { casts = 0, caught = 0, away = 0 }
      fz.casts = fz.casts + 1
      log().fishing[zone] = fz
    end
    R.Advance()
  end)
  if not ok then Core.ReportError("log " .. ev, err) end
end)

local function setOn(on)
  local l = log()
  l.on = on
  for _, ev in ipairs(EVENTS) do if on then f:RegisterEvent(ev) else f:UnregisterEvent(ev) end end
  if on and not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(10, tick) end
  if not on and ticker then ticker:Cancel(); ticker = nil end
  lastTick = nil
end

-- Window: the steps, ticked as they're done ---------------------------------------------
local panel, lines = nil, {}
function R.Refresh()
  if not panel or not panel:IsShown() then return end
  local cur = R.Current()
  for i, s in ipairs(R.steps) do
    local fs = lines[i]
    local st = stepState(s)
    local mark = st == "done" and "|cff40bf40[done]|r " or st == "skipped" and "|cff808080[skipped]|r "
                 or st == "n/a" and "|cff808080[not for you]|r " or (s == cur and "|cffffd100> now:|r " or "|cffbbbbbb[later]|r ")
    local prog = (st == "open" and s.progress) and (" |cff33ccff(" .. s.progress() .. ")|r") or ""
    fs:SetText(("%d. %s%s%s"):format(i, mark, stepText(s), prog))
  end
  local l = log()
  panel.status:SetText(l.on and ("Recording: %d entries. /sr log off to stop."):format(#l.entries)
                       or "Not recording. /sr log on to start.")
end

function R.Show()
  if not panel then
    panel = CreateFrame("Frame", "SkillRouteLog", UIParent, "BasicFrameTemplateWithInset")
    panel:SetSize(460, 60 + #R.steps * 44)
    panel:SetPoint("LEFT", 40, 0)
    panel:SetMovable(true); panel:EnableMouse(true); panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetClampedToScreen(true)
    panel:SetScript("OnShow", function() R.Refresh() end)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5); title:SetText("SkillRoute data checks")
    for i = 1, #R.steps do
      local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetPoint("TOPLEFT", 14, -30 - (i - 1) * 44); fs:SetPoint("RIGHT", -14, 0)
      fs:SetJustifyH("LEFT"); fs:SetWordWrap(true)
      lines[i] = fs
    end
    panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.status:SetPoint("BOTTOMLEFT", 14, 10)
    tinsert(UISpecialFrames, "SkillRouteLog")
  end
  panel:Show()
  R.Refresh()
end

-- /sr log on|off|skip|boat|clear|status ---------------------------------------------------
function R.Command(arg)
  local l = log()
  if arg == "on" then
    setOn(true)
    say("recording. Steps are in the window; each one ticks off by itself.")
    local cur = R.Current()
    if cur then say("|cffffd100first:|r " .. stepText(cur)) end
    R.Show()
  elseif arg == "off" then
    setOn(false)
    say(("stopped. %d entries kept; they're in your SavedVariables after you log out or /reload."):format(#l.entries))
    R.Refresh()
  elseif arg == "skip" then
    local cur = R.Current()
    if cur then l.skipped[cur.id] = true; say("skipped: " .. stepText(cur)) end
    local nxt = R.Current()
    if nxt then say("|cffffd100next:|r " .. stepText(nxt)) end
    R.Refresh()
  elseif arg == "boat" then
    local zone, x, y = where()
    l.boats[#l.boats + 1] = { time = GetTime(), clock = date and date("%H:%M:%S"), zone = zone, x = x, y = y }
    local b = l.boats
    if #b >= 2 and b[#b - 1].zone == zone then
      say(("boat mark %d at %s: %d s since the last one here."):format(#b, zone, math.floor(b[#b].time - b[#b - 1].time)))
    else
      say(("boat mark at %s. Type /sr log boat again when the same ship leaves next."):format(zone))
    end
    R.Advance()
  elseif arg == "clear" then
    SkillRouteDB.log = nil
    setOn(false)
    say("cleared.")
    R.Refresh()
  else
    R.Show()
    say(l.on and "recording (/sr log off to stop)." or "not recording. /sr log on to start.")
  end
end

-- keep recording across reloads when it was on
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function() if log().on then setOn(true) end end)
