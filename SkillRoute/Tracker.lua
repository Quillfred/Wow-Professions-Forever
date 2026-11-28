-- "Keep on screen": away from the profession window, the mini panel's next step stays on
-- screen like the quest list (see-through, text only): the step, its materials as
-- objectives, what to buy, what comes next. Hidden while the profession window is open
-- (the docked mini panel takes over) and back when it closes. Drag the header to move it
-- (saved), "-" folds it to the header. Also: one-time notices when a step's materials are
-- all in your bags, and when you reach a rank cap or your target.
local _, ns = ...
local Core, UI, Data = ns.Core, ns.UI, SkillRouteData
local T = {}
ns.Tracker = T

local W = 300
local frame, header, title, fold, hit, rule
local lines = {}   -- font strings, reused
local shownLine    -- the profession on screen
local stepLoc      -- the step's waypoint (a trainer, book or quest), if any
local stepTip      -- { plan, st } for the hover tooltip
local cache        -- { key, plan, entries }: the last plan, while nothing it depends on changed

local function S() SkillRouteDB.settings = SkillRouteDB.settings or {}; return SkillRouteDB.settings end
function T.Enabled() return S().tracker == true end
function T.NotifyEnabled() return S().notify ~= false end
-- wanted on bag/skill changes: shown, or watching for notices
function T.Wants() return T.Enabled() or T.NotifyEnabled() end

local function professionOpen()
  return (ProfessionsFrame and ProfessionsFrame:IsShown()) or (TradeSkillFrame and TradeSkillFrame:IsShown()) or false
end

-- Notices ---------------------------------------------------------------------------
local wasReady, lastSkill = {}, {} -- this session: per step, per profession
function T.Notify(text, sub)
  if not T.NotifyEnabled() then return end
  local msg = "SkillRoute: " .. text .. (sub and ("\n|cffffffff" .. sub .. "|r") or "")
  if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo and ChatTypeInfo.RAID_WARNING then
    pcall(RaidNotice_AddMessage, RaidWarningFrame, msg, ChatTypeInfo.RAID_WARNING)
  elseif UIErrorsFrame then
    UIErrorsFrame:AddMessage(msg, 1, 0.82, 0)
  end
  local sound = SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE
  if sound and PlaySound then pcall(PlaySound, sound) end
  T.lastNotice = msg
end

-- Everything for the step in your bags? { ready, need = { {item, have, need} } }
local function materials(lineID, spell, crafts)
  local r = Data.professions[lineID].recipes[spell]
  local list, ready = {}, true
  for i = 1, #r.r, 2 do
    local item, need = r.r[i], r.r[i + 1] * crafts
    local have = Core.InBags(item)
    if have < need then ready = false end
    list[#list + 1] = { item = item, have = have, need = need }
  end
  return ready, list
end

-- Called on every change: a notice the first time a step becomes ready, and when the
-- skill reaches a rank cap or the target.
local function check(lineID, plan, e)
  local name = Data.professions[lineID].name
  if e and e.kind == "craft" then
    local key = lineID .. ":" .. e.st.spell .. ":" .. e.st.from
    local ready = materials(lineID, e.st.spell, math.ceil(e.st.crafts - 1e-9))
    if ready and wasReady[key] == false then
      T.Notify(e.st.name .. " is ready to craft", ("you have everything for the next %d"):format(math.ceil(e.st.crafts - 1e-9)))
    end
    wasReady[key] = ready
  end
  local skills = Core.Skills()[lineID]
  local skill = skills and skills.rank
  if not skill then return end
  local before = lastSkill[lineID]
  lastSkill[lineID] = skill
  if not before or skill <= before then return end
  local target = Core.Char().targets[lineID] or 300
  if skill >= target then
    T.Notify(("%s %d: target reached"):format(name, skill))
  elseif skills.max and skill >= skills.max and skills.max < target then
    local nextStep = e and e.kind == "rank" and e.text or ("raise your rank to go past " .. skills.max)
    T.Notify(("%s %d reached"):format(name, skill), nextStep .. " to go on to " .. target)
  end
end
T._check = check
T._reset = function() wasReady, lastSkill, cache = {}, {}, nil end

-- Frame -----------------------------------------------------------------------------
local function savePos()
  local l, t = frame:GetLeft(), frame:GetTop()
  if l and t then S().trackerPos = { math.floor(l + 0.5), math.floor(t + 0.5) } end
end

local function place()
  frame:ClearAllPoints()
  local p = S().trackerPos
  if p then frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1], p[2])
  else frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -420) end -- the right side, below the quest list
end

-- Tooltips go beside the whole tracker, on the side with more room, never over it.
local function tipBeside(owner)
  GameTooltip:SetOwner(owner, "ANCHOR_NONE")
  GameTooltip:ClearAllPoints()
  local mid = UIParent and UIParent.GetWidth and UIParent:GetWidth()
  local x = frame.GetCenter and frame:GetCenter()
  if mid and x and x > mid / 2 then
    GameTooltip:SetPoint("TOPRIGHT", frame, "TOPLEFT", -12, 0)  -- tracker on the right: tooltip to its left
  else
    GameTooltip:SetPoint("TOPLEFT", frame, "TOPRIGHT", 12, 0)
  end
end
T._tipBeside = tipBeside

local function build()
  frame = CreateFrame("Frame", "SkillRouteTracker", UIParent)
  frame:SetSize(W, 24)
  frame:SetMovable(true); frame:SetClampedToScreen(true)
  frame:SetFrameStrata("LOW")
  header = CreateFrame("Button", nil, frame)
  header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT", -22, 0); header:SetHeight(18)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function() frame:StartMoving() end)
  header:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); savePos(); place() end)
  header:SetScript("OnClick", function() if shownLine then UI.Toggle(shownLine) end end)
  header:SetScript("OnEnter", function(self)
    tipBeside(self); GameTooltip:SetText("SkillRoute")
    GameTooltip:AddLine("Drag to move. Click: the full route.", 1, 1, 1)
    GameTooltip:AddLine("Turn it off in Options (General).", 0.6, 0.6, 0.6); GameTooltip:Show()
  end)
  header:SetScript("OnLeave", function() GameTooltip:Hide() end)
  title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 0, -2); title:SetJustifyH("LEFT")
  fold = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  fold:SetSize(18, 16); fold:SetPoint("TOPRIGHT", 0, 0)
  fold:SetScript("OnClick", function() S().trackerFolded = not S().trackerFolded or nil; T.Refresh() end)
  rule = frame:CreateTexture(nil, "ARTWORK")
  if rule.SetColorTexture then rule:SetColorTexture(1, 0.82, 0, 0.35) end
  rule:SetHeight(1); rule:SetPoint("TOPLEFT", 0, -19); rule:SetPoint("TOPRIGHT", 0, -19)
  -- the step line: click for its waypoint (or the full route), hover for its tooltip
  hit = CreateFrame("Button", nil, frame)
  hit:SetScript("OnClick", function()
    if stepLoc then Core.Waypoint(stepLoc) elseif shownLine then UI.Toggle(shownLine) end
  end)
  hit:SetScript("OnEnter", function(self)
    if not stepTip then return end
    local ok, r, tip = pcall(UI.StepTip, stepTip[1], stepTip[2])
    if not ok or not tip then return end
    tipBeside(self)
    if r.out and GameTooltip.SetItemByID then GameTooltip:SetItemByID(r.out)
    elseif GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(stepTip[2].spell) end
    UI.AddTipLines(tip)
    GameTooltip:Show()
  end)
  hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
  place()
  frame:Hide()
end

local function lineAt(i, template)
  local fs = lines[i]
  if not fs then
    fs = frame:CreateFontString(nil, "OVERLAY", template)
    fs:SetJustifyH("LEFT")
    lines[i] = fs
  end
  fs:SetFontObject(_G[template] or template)
  return fs
end

-- The step, as quest-style objectives.
local function draw(lineID, plan, entries)
  local name = Data.professions[lineID].name
  title:SetText(("SkillRoute  |cffffffff%s %d/%d -> %d|r"):format(name, plan.skill, plan.max, plan.target))
  fold:SetText(S().trackerFolded and "+" or "-")
  for _, fs in ipairs(lines) do fs:Hide() end
  stepLoc, stepTip = nil, nil
  hit:Hide()
  if S().trackerFolded then frame:SetHeight(20); return end
  local y, n = -24, 0
  local function add(text, template, indent)
    n = n + 1
    local fs = lineAt(n, template or "GameFontHighlightSmall")
    fs:SetWidth(W - (indent or 0)); fs:SetText(text)
    fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", indent or 0, y); fs:Show()
    y = y - (fs:GetStringHeight() or 12) - 2
    return fs
  end
  local e = entries[1]
  local stepTop = y
  if e.kind == "craft" or (e.kind == "tool" and e.spell) then
    local spell, crafts = e.kind == "craft" and e.st.spell or e.spell, e.kind == "craft" and math.ceil(e.st.crafts - 1e-9) or 1
    local label = e.kind == "craft" and (e.st.smeltStep and ("Smelt %d x %s  |cffcccccc%d-%d|r"):format(crafts, e.st.ore, e.st.from, e.st.to)
                  or ("Craft %d x %s  |cffcccccc%d-%d|r"):format(crafts, e.st.name, e.st.from, e.st.to)) or e.text
    add(label, "GameFontNormal")
    if e.kind == "craft" then stepTip = { plan, e.st } end
    local ready, mats = materials(lineID, spell, crafts)
    if not Core.IsRecipeKnown(lineID, spell) then
      local how, loc
      if e.st then how, loc = ns.Mini.LearnNote(plan, e.st) end
      stepLoc = loc
      add("|cffff8040Not learned yet: " .. (how or "learn it first") .. "|r", "GameFontHighlightSmall", 12)
    elseif ready then
      add("|cffffd100Ready to craft: " .. (e.st and e.st.smeltStep and "at a forge" or ("open " .. name)) .. "|r", "GameFontHighlightSmall", 12)
    end
    for _, m in ipairs(mats) do
      add(("- |cff%s%d/%d|r %s%s"):format(m.have >= m.need and "40bf40" or "ff6060", m.have, m.need, UI.ItemName(m.item),
        ns.Mini.MatTag(m.item, m.have, m.need)), "GameFontHighlightSmall", 12)
    end
    local buy = ns.Mini.BuyText(plan, e.kind == "craft" and e.st or e.buy)
    if buy then add(buy, "GameFontHighlightSmall", 12) end
  elseif e.kind == "gather" then -- the node and where: the best zones as objectives
    add(e.text, "GameFontNormal")
    if e.st.alt and e.st.alt[1] then add("|cffcccccc- or " .. e.st.alt[1] .. "|r", "GameFontHighlightSmall", 12) end
    for _, z in ipairs(UI.GatherZones(e.st)) do add("- " .. z, "GameFontHighlightSmall", 12) end
    if e.st.smelt then add(("- |cffffd100smelt the ore as you go (~%d %s)|r"):format(e.st.smelt.n, e.st.smelt.ore), "GameFontHighlightSmall", 12) end
    if e.st.buy then
      local p = Core.Price(e.st.buy.oreItem)
      add(("|cffcccccc- or buy ~%d %s%s and smelt|r"):format(e.st.buy.n, e.st.buy.ore, p and (" (~" .. UI.Money(p * e.st.buy.n) .. ")") or ""),
        "GameFontHighlightSmall", 12)
    end
  else
    add(e.text, "GameFontNormal")
    stepLoc = e.loc
    if e.loc then add("- " .. (Core.Where(e.loc) or "?"), "GameFontHighlightSmall", 12) end
    if e.warn then add("- |cffff4040" .. e.warn .. "|r", "GameFontHighlightSmall", 12) end
  end
  hit:ClearAllPoints(); hit:SetPoint("TOPLEFT", 0, stepTop); hit:SetSize(W, math.max(14, stepTop - y)); hit:Show()
  if entries[2] then y = y - 4; add("|cffccccccThen: " .. entries[2].text .. "|r", "GameFontHighlightSmall") end
  frame:SetHeight(-y + 4)
end

-- Re-plan and redraw (or hide), and look for notices. Cheap when nothing is wanted.
function T.Refresh()
  if not T.Wants() then if frame then frame:Hide() end return end
  local c = Core.Char()
  local lineID = c.lastLine
  local prof = lineID and Data.professions[lineID]
  if not (prof and Core.Skills()[lineID]) then if frame then frame:Hide() end return end
  -- re-plan only when the route can change (skill, target, recipes, prices, settings): a
  -- plan takes ~30 ms, and bags change with every loot. Materials are counted live.
  local sk = Core.Skills()[lineID]
  local key = table.concat({ lineID, sk.rank or 0, sk.max or 0, c.targets[lineID] or 300, Core.RouteVersion() }, ":")
  if lineID == 186 then -- Mining: the ore in your bags decides the "smelt it" step
    for _, sm in pairs(Core.SmeltData()) do key = key .. ":" .. Core.InBags(sm.ore) end
  end
  local plan, entries
  if cache and cache.key == key then plan, entries = cache.plan, cache.entries
  else
    plan = Core.Plan(lineID, c.targets[lineID] or 300)
    entries = plan and ns.Mini.Entries(plan) or {}
    cache = { key = key, plan = plan, entries = entries }
  end
  check(lineID, plan, entries[1])
  local show = T.Enabled() and plan and entries[1] and not professionOpen()
  if not show then if frame then frame:Hide() end return end
  if not frame then build() end
  shownLine = lineID
  draw(lineID, plan, entries)
  frame:Show()
end

function T.IsShown() return frame and frame:IsShown() or false end
function T.Frame() return frame end
T._parts = function() return frame, header, fold end

-- the profession window took over or let go; logging in
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, e)
  -- next frame: the window has finished opening or closing
  C_Timer.After(e == "PLAYER_LOGIN" and 2 or 0, function()
    local ok, err = pcall(T.Refresh)
    if not ok then Core.ReportError("tracker", err) end
  end)
end)
