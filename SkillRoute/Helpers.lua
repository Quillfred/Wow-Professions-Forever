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

local function bankBags()
  local bags = { BANK_CONTAINER or -1 }
  local first = (NUM_BAG_SLOTS or 4) + 1
  for b = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do bags[#bags + 1] = b end
  return bags
end
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

-- What the next craft steps still need in your bags: { [item] = count }, and the line.
function H.BagNeeds()
  local c = Core.Char()
  local line = c.lastLine
  if not (line and Data.professions[line] and Core.Skills()[line]) then return nil end
  local plan = Core.Plan(line, c.targets[line] or 300)
  if not plan then return nil end
  local want, steps = {}, 0
  for _, st in ipairs(plan.steps) do
    if st.spell and not st.gather and not st.gap then
      local r = Data.professions[line].recipes[st.spell]
      local crafts = math.ceil(st.crafts - 1e-9)
      for i = 1, #(r.r or {}), 2 do want[r.r[i]] = (want[r.r[i]] or 0) + r.r[i + 1] * crafts end
      steps = steps + 1
      if steps >= LOOKAHEAD then break end
    end
  end
  for item, n in pairs(want) do
    local short = n - Core.InBags(item)
    want[item] = short > 0 and short or nil
  end
  return want, line
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

local bankBtn
local function showBankButton()
  local parent = BankFrame
  if not parent then return end
  if not bankBtn then
    bankBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    bankBtn:SetSize(170, 22)
    bankBtn:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", 0, -2)
    bankBtn:SetScript("OnClick", function() H.TakeFromBank() end)
    bankBtn:SetScript("OnEnter", function(self)
      local want, line = H.BagNeeds()
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:SetText("Take route materials")
      if line then
        GameTooltip:AddLine(("What the next %d %s steps still need in your bags, from the bank (whole stacks):")
          :format(LOOKAHEAD, Data.professions[line].name), 1, 1, 1, true)
        local any = false
        for item, n in pairs(want or {}) do GameTooltip:AddDoubleLine(UI.ItemName(item), n, 1, 1, 1, 1, 1, 1); any = true end
        if not any then GameTooltip:AddLine("Nothing: your bags have it all.", 0.6, 0.6, 0.6) end
      else
        GameTooltip:AddLine("Open a profession once so SkillRoute knows which route.", 0.6, 0.6, 0.6, true)
      end
      GameTooltip:Show()
    end)
    bankBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  local c = Core.Char()
  local name = c.lastLine and Data.professions[c.lastLine] and Data.professions[c.lastLine].name
  bankBtn:SetText(name and ("Take %s mats"):format(name) or "Take route mats")
  bankBtn:Show()
end

local f = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "BANKFRAME_OPENED" }) do
  pcall(f.RegisterEvent, f, ev)
end
local checking = false
f:SetScript("OnEvent", function(_, ev)
  if ev == "BANKFRAME_OPENED" then
    local ok, err = pcall(showBankButton)
    if not ok then Core.ReportError("bank button", err) end
  elseif not checking then
    checking = true -- skill events come in bursts: check once, a moment later
    C_Timer.After(1, function()
      checking = false
      local ok, err = pcall(H.CheckRanks)
      if not ok then Core.ReportError("rank reminder", err) end
    end)
  end
end)
