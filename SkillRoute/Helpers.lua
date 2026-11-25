-- Two small helpers around the route:
--  * Rank-up reminder: when a profession hits its rank's cap (75, 150, 225) and your
--    target is higher, a message says what to do next and where (trainer, book or
--    quest), once per cap per session.
--  * Take route materials at the bank: a button on the bank window moves what the next
--    steps of your route need from the bank into your bags (whole stacks).
local _, ns = ...
local Core, UI, Data = ns.Core, ns.UI, SkillRouteData
local H = {}
ns.Helpers = H

local NEXT_STEP = { [75] = 2, [150] = 3, [225] = 4 }
local RANK = { [2] = "Journeyman", [3] = "Expert", [4] = "Artisan" }

-- Rank-up reminder ---------------------------------------------------------------------
local reminded = {}

-- The message for one profession at its cap, or nil if nothing to say.
function H.RankMessage(line, s)
  local step = NEXT_STEP[s.max]
  local target = Core.Char().targets[line] or 300
  if not (step and s.rank >= s.max and target > s.max) then return nil end
  local rank, prof = RANK[step], Data.professions[line].name
  local rh = Core.RankHow(line, step) or {}
  local what, loc
  if rh.book then
    what, loc = (rh.book.owned and "read your " or "buy ") .. rh.book.name, rh.book.loc
  elseif rh.quest then
    what, loc = ('do the quest "%s"'):format(rh.quest.title), rh.quest.loc
  else
    what, loc = "train " .. rank .. (rh.loc and (" at " .. rh.loc.npc) or ""), rh.loc
  end
  local where = loc and Core.Where(loc)
  local travel = loc and Core.TravelText(loc)
  local need, mine = Core.RankLevelShort(line, step)
  local msg = ("%s is capped at %d: %s%s%s."):format(prof, s.max, what,
    where and (", " .. where) or "", travel and (" (" .. travel .. ")") or "")
  if need then msg = msg .. (" Needs character level %d (you're %d)."):format(need, mine) end
  return msg, ("%s %d/%d: time to %s"):format(prof, s.rank, s.max, what)
end

function H.CheckRanks()
  for line, s in pairs(Core.Skills()) do
    local key = line .. ":" .. (s.max or 0)
    if not reminded[key] then
      local msg, short = H.RankMessage(line, s)
      if msg then
        reminded[key] = true
        print("|cff33ccffSkillRoute:|r " .. msg)
        if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(short, 1, 0.82, 0) end
      end
    end
  end
end

-- Take route materials at the bank -----------------------------------------------------
local LOOKAHEAD = 3 -- craft steps

-- The bank's containers. Newer clients have bank tabs (Enum.BagIndex.CharacterBankTab_N);
-- older ones the bank slots (-1) plus bank bags after your own bags. Never a bag you
-- carry: using an item from one of those at the bank would deposit it instead.
function H.BankBags()
  local B = Enum and Enum.BagIndex
  local bags = {}
  if B and B.CharacterBankTab_1 then
    for i = 1, 12 do
      local id = B["CharacterBankTab_" .. i]
      if not id then break end
      bags[#bags + 1] = id
    end
    return bags
  end
  bags[1] = BANK_CONTAINER or -1
  local first = (NUM_BAG_SLOTS or 4) + 1
  local carried = {}
  if B then for k, v in pairs(B) do if type(k) == "string" and not k:find("Bank") then carried[v] = true end end end
  for b = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do
    if not carried[b] then bags[#bags + 1] = b end
  end
  return bags
end
local bankBags = H.BankBags

local function slots(bag)
  local C = C_Container
  return (C and C.GetContainerNumSlots and C.GetContainerNumSlots(bag)) or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
end
local function slotItem(bag, slot) -- itemID, count, locked
  local C = C_Container
  if C and C.GetContainerItemInfo then
    local i = C.GetContainerItemInfo(bag, slot)
    if i then return i.itemID, i.stackCount, i.isLocked end
    return nil
  end
  if GetContainerItemInfo then
    local _, count, locked, _, _, _, _, _, _, id = GetContainerItemInfo(bag, slot)
    return id, count, locked
  end
end
local function useSlot(bag, slot)
  local C = C_Container
  if C and C.UseContainerItem then C.UseContainerItem(bag, slot) elseif UseContainerItem then UseContainerItem(bag, slot) end
end

-- What the next craft steps of every crafting profession you have still need in your
-- bags. Returns the total short per item { [item] = n } and, for the tooltip, per
-- profession { { line, name, items = { [item] = n } }, ... } (sorted by name).
function H.BagNeeds()
  local c = Core.Char()
  local total, byLine = {}, {}
  for line in pairs(Core.Skills()) do
    local prof = Data.professions[line]
    local plan = prof and not prof.gather and Core.Plan(line, c.targets[line] or 300)
    if plan and not plan.gather then
      local want, steps = {}, 0
      for _, st in ipairs(plan.steps) do
        if st.spell and not st.gather and not st.gap then
          local r = prof.recipes[st.spell]
          local crafts = math.ceil(st.crafts - 1e-9)
          for i = 1, #(r.r or {}), 2 do
            want[r.r[i]] = (want[r.r[i]] or 0) + r.r[i + 1] * crafts
            total[r.r[i]] = (total[r.r[i]] or 0) + r.r[i + 1] * crafts
          end
          steps = steps + 1
          if steps >= LOOKAHEAD then break end
        end
      end
      if next(want) then byLine[#byLine + 1] = { line = line, name = prof.name, items = want } end
    end
  end
  -- minus what's in your bags: the totals first (two routes can share a material)
  local have = {}
  for item, n in pairs(total) do
    have[item] = Core.InBags(item)
    local short = n - have[item]
    total[item] = short > 0 and short or nil
  end
  for _, p in ipairs(byLine) do
    for item, n in pairs(p.items) do
      local short = n - (have[item] or 0)
      p.items[item] = short > 0 and short or nil
    end
  end
  table.sort(byLine, function(x, y) return x.name < y.name end)
  return total, byLine
end

-- For the button's tooltip: only what's in the bank (that's what a click takes), per
-- profession { { name, { { item, take, needed }, ... } }, ... }, and how many other
-- materials the routes need that the bank doesn't have.
function H.BankRows(byLine)
  local shown, missing, seen = {}, 0, {}
  for _, p in ipairs(byLine or {}) do
    local rows = {}
    for item, n in pairs(p.items) do
      local banked = Core.Have(item) - Core.InBags(item)
      if banked > 0 then rows[#rows + 1] = { item, math.min(n, banked), n }
      elseif not seen[item] then missing = missing + 1 end
      seen[item] = true
    end
    table.sort(rows, function(a, b) return UI.ItemName(a[1]) < UI.ItemName(b[1]) end)
    if #rows > 0 then shown[#shown + 1] = { p.name, rows } end
  end
  return shown, missing
end

-- Move whole stacks from the bank until each need is met. Returns stacks moved.
function H.TakeFromBank()
  local want = H.BagNeeds()
  if not want or not next(want) then
    print("|cff33ccffSkillRoute:|r your bags already hold what the next steps need.")
    return 0
  end
  local moved = 0
  for _, bag in ipairs(bankBags()) do
    for slot = 1, slots(bag) do
      local id, count, locked = slotItem(bag, slot)
      if id and want[id] and not locked then
        useSlot(bag, slot)
        moved = moved + 1
        want[id] = want[id] - (count or 1)
        if want[id] <= 0 then want[id] = nil end
      end
    end
  end
  local left = {}
  for item, n in pairs(want) do left[#left + 1] = n .. " " .. UI.ItemName(item) end
  print(("|cff33ccffSkillRoute:|r took %d stack%s from the bank.%s"):format(moved, moved == 1 and "" or "s",
    #left > 0 and (" Still short: " .. table.concat(left, ", ") .. ".") or ""))
  return moved
end

-- The bank window you can see: a bag addon's (Baganator, Bagnon, ...: the largest
-- top-level frame with "bank" in its name), else Blizzard's. Only one that's really on
-- screen: bag addons often keep Blizzard's open but moved away or transparent.
local function onScreen(f)
  if not f or (f.IsForbidden and f:IsForbidden()) then return false end
  if not (f.IsVisible and f:IsVisible()) then return false end
  if f.GetEffectiveAlpha and (f:GetEffectiveAlpha() or 1) < 0.05 then return false end
  local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
  local W, H = UIParent:GetWidth(), UIParent:GetHeight()
  if not (l and r and t and b and W and H) then return false end
  return r > 20 and l < W - 20 and t > 20 and b < H - 20
end
H.OnScreen = onScreen

-- The name of a top-level frame, or nil. Some of the game's own frames are forbidden to
-- addons (touching them is an error), so those are skipped.
local function frameName(f)
  if f.IsForbidden and f:IsForbidden() then return nil end
  local ok, n = pcall(f.GetName, f)
  return ok and n or nil
end

function H.BankWindow()
  local best, area = nil, 0
  for _, f in ipairs({ UIParent:GetChildren() }) do
    local name = frameName(f)
    if name and name ~= "BankFrame" and name ~= "SkillRouteBankButton" and name:lower():find("bank", 1, true)
       and onScreen(f) then
      local w, h = f:GetWidth() or 0, f:GetHeight() or 0
      -- a window, not a full-screen holder frame
      if w > 150 and h > 150 and w < UIParent:GetWidth() * 0.9 and h < UIParent:GetHeight() * 0.9
         and w * h > area then best, area = f, w * h end
    end
  end
  if best then return best end
  if BankFrame and onScreen(BankFrame) then return BankFrame end
end

-- /sr bank: what SkillRoute sees of the bank windows, to find where the button went.
function H.BankDebug()
  local out = {}
  local function desc(f)
    local n = frameName(f) or "?"
    return ("%s %dx%d at %d,%d alpha %.2f %s"):format(n, f:GetWidth() or 0, f:GetHeight() or 0,
      f:GetLeft() or -1, f:GetBottom() or -1, f.GetEffectiveAlpha and f:GetEffectiveAlpha() or 1,
      onScreen(f) and "on screen" or "OFF screen")
  end
  for _, f in ipairs({ UIParent:GetChildren() }) do
    local n = frameName(f)
    if n and n:lower():find("bank", 1, true) and f:IsVisible() then out[#out + 1] = desc(f) end
  end
  if BankFrame then out[#out + 1] = "BankFrame: " .. (BankFrame:IsVisible() and desc(BankFrame) or "hidden") end
  local host = H.BankWindow()
  out[#out + 1] = "docks to: " .. (host and (host:GetName() or "?") or "nothing (floats)")
  local b = SkillRouteBankButton
  out[#out + 1] = "button: " .. (b and (b:IsVisible() and desc(b) or "hidden") or "not made yet")
  for _, l in ipairs(out) do print("|cff33ccffSkillRoute bank:|r " .. l) end
end

local bankBtn
local function showBankButton()
  if not bankBtn then
    bankBtn = CreateFrame("Button", "SkillRouteBankButton", UIParent, "UIPanelButtonTemplate")
    bankBtn:SetSize(170, 24)
    bankBtn:SetFrameStrata("DIALOG")
    bankBtn:SetMovable(true); bankBtn:RegisterForDrag("LeftButton"); bankBtn:SetClampedToScreen(true)
    -- drag to move (bag addons replace the bank window, so it can't always dock)
    bankBtn:SetScript("OnDragStart", bankBtn.StartMoving)
    bankBtn:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      local x, y = self:GetCenter()
      if x and y then SkillRouteDB.settings.bankBtnPos = { math.floor(x), math.floor(y) } end
    end)
    bankBtn:SetScript("OnClick", function() H.TakeFromBank() end)
    bankBtn:SetScript("OnEnter", function(self)
      local want, byLine = H.BagNeeds()
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:SetText("Take route materials")
      GameTooltip:AddLine(("From your bank, what the next %d steps of each of your professions still need in your bags (whole stacks):")
        :format(LOOKAHEAD), 1, 1, 1, true)
      local shown, missing = H.BankRows(byLine)
      for _, g in ipairs(shown) do
        GameTooltip:AddLine(g[1], 1, 0.82, 0)
        for _, r in ipairs(g[2]) do
          GameTooltip:AddDoubleLine("  " .. UI.ItemName(r[1]),
            r[2] < r[3] and ("%d |cff999999(of %d needed)|r"):format(r[2], r[3]) or tostring(r[2]), 1, 1, 1, 1, 1, 1)
        end
      end
      if #shown == 0 then GameTooltip:AddLine("Nothing your routes need is in your bank.", 0.6, 0.6, 0.6, true) end
      if missing > 0 then
        GameTooltip:AddLine(("%d other material%s not in your bank: see the shopping list."):format(missing, missing == 1 and "" or "s"),
          0.6, 0.6, 0.6, true)
      end
      if not H.BankWindow() then GameTooltip:AddLine("Drag to move this button.", 0.6, 0.6, 0.6) end
      GameTooltip:Show()
    end)
    bankBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  bankBtn:ClearAllPoints()
  local host = H.BankWindow()
  local pos = SkillRouteDB.settings and SkillRouteDB.settings.bankBtnPos
  if host then bankBtn:SetPoint("BOTTOMRIGHT", host, "TOPRIGHT", 0, 2) -- docked above the bank
  elseif pos then bankBtn:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos[1], pos[2])
  else bankBtn:SetPoint("TOP", UIParent, "TOP", 0, -120) end
  bankBtn:SetText("Take route mats")
  bankBtn:Show()
end

local f = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "BANKFRAME_OPENED", "BANKFRAME_CLOSED" }) do
  pcall(f.RegisterEvent, f, ev)
end
local checking = false
f:SetScript("OnEvent", function(_, ev)
  if ev == "BANKFRAME_OPENED" then
    -- a moment later: bag addons show their bank window after the event
    C_Timer.After(0.2, function()
      local ok, err = pcall(showBankButton)
      if not ok then Core.ReportError("bank button", err) end
    end)
  elseif ev == "BANKFRAME_CLOSED" then
    if bankBtn then bankBtn:Hide() end
  elseif not checking then
    checking = true -- skill events come in bursts: check once, a moment later
    C_Timer.After(1, function()
      checking = false
      local ok, err = pcall(H.CheckRanks)
      if not ok then Core.ReportError("rank reminder", err) end
    end)
  end
end)
