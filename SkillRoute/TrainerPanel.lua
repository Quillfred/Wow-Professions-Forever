-- At a profession trainer: a panel docked to the trainer window listing the recipes
-- this trainer offers that your route uses, with the skill range each one is for, its
-- cost, and a Learn button (plus Learn all for what you can learn now). Reads the
-- window as it is: recipes the trainer's filter hides aren't listed.
local _, ns = ...
local Core, UI = ns.Core, ns.UI
local TP = {}
ns.TrainerPanel = TP

local W, ROWS = 300, 8
local panel
local rows = {}
local ready = {} -- service indexes you can learn now (for Learn all)

local function font(tmpl, parent) return (parent or panel):CreateFontString(nil, "OVERLAY", tmpl) end

-- { line, items = { { index, spell, name, from, to, cost, kind } }, totalNow } or nil
function TP.Collect()
  if not (GetNumTrainerServices and GetTrainerServiceInfo and GetTrainerServiceSkillReq) then return nil end
  local byLine, lineOf = {}, nil
  for i = 1, GetNumTrainerServices() do
    local line, spell, req, cost, kind = Core.TrainerService(i)
    if spell and kind ~= "used" and not Core.IsRecipeKnown(line, spell) then
      lineOf = lineOf or line
      byLine[line] = byLine[line] or {}
      byLine[line][spell] = { index = i, req = req or 0, cost = cost or 0, kind = kind }
    end
  end
  if not lineOf then return nil end
  local skills = Core.Skills()
  if not skills[lineOf] then return nil end -- not your profession
  local plan = Core.Plan(lineOf, Core.Char().targets[lineOf] or 300)
  if not plan then return nil end
  local out, seen, totalNow = {}, {}, 0
  local skill = skills[lineOf].rank or 0
  local myLevel = UnitLevel and UnitLevel("player") or 0
  for _, st in ipairs(plan.steps) do
    local svc = st.spell and byLine[lineOf][st.spell]
    if svc and not seen[st.spell] then
      seen[st.spell] = true
      -- learnable now: your skill (and level, if the trainer says) is enough. Decided
      -- here rather than from the service type, which clients report differently.
      local lvl = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(svc.index) or 0
      local now = skill >= svc.req and myLevel >= (lvl or 0)
      if now then totalNow = totalNow + svc.cost end
      out[#out + 1] = { index = svc.index, spell = st.spell, name = st.name, from = st.from, to = st.to,
                        cost = svc.cost, req = svc.req, now = now }
    end
  end
  return { line = lineOf, items = out, totalNow = totalNow }
end

local function build(parent)
  panel = CreateFrame("Frame", "SkillRouteTrainer", parent, "BasicFrameTemplateWithInset")
  panel:SetWidth(W)
  panel:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, -24)
  panel:SetFrameStrata("HIGH")
  local title = font("GameFontHighlight"); title:SetPoint("TOP", 0, -5); title:SetText("SkillRoute: your route here")
  panel.intro = font("GameFontHighlightSmall"); panel.intro:SetPoint("TOPLEFT", 12, -30)
  panel.intro:SetWidth(W - 24); panel.intro:SetJustifyH("LEFT")
  for i = 1, ROWS do
    local r = {}
    r.name = font("GameFontHighlight"); r.name:SetJustifyH("LEFT"); r.name:SetWidth(W - 90)
    r.sub = font("GameFontHighlightSmall"); r.sub:SetJustifyH("LEFT"); r.sub:SetWidth(W - 90)
    r.btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    r.btn:SetSize(62, 20); r.btn:SetText("Learn")
    r.btn:SetScript("OnClick", function(self) if self.index and BuyTrainerService then BuyTrainerService(self.index) end end)
    rows[i] = r
  end
  panel.all = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.all:SetSize(W - 24, 22)
  panel.all:SetScript("OnClick", function()
    -- highest index first, so earlier indexes stay valid while buying
    table.sort(ready, function(a, b) return a > b end)
    for _, i in ipairs(ready) do BuyTrainerService(i) end
  end)
  panel.foot = font("GameFontDisableSmall"); panel.foot:SetWidth(W - 24); panel.foot:SetJustifyH("LEFT")
end

local function draw()
  local parent = ClassTrainerFrame
  local data = parent and TP.Collect()
  if not data then if panel then panel:Hide() end return end
  if not panel then build(parent) end
  panel:Show()
  local money = UI.Money
  local n = #data.items
  wipe(ready)
  panel.intro:SetText(n == 0 and "Nothing here for your route right now."
    or ("%d recipe%s your route uses. Learn them when you get here, or on the way past."):format(n, n == 1 and "" or "s"))
  local y = -30 - (panel.intro:GetStringHeight() or 12) - 8
  for i, r in ipairs(rows) do
    local it = data.items[i]
    if it then
      r.name:SetText(it.name); r.name:ClearAllPoints(); r.name:SetPoint("TOPLEFT", 12, y)
      r.sub:SetText(("used %d-%d  -  %s%s"):format(it.from, it.to, it.cost > 0 and money(it.cost) or "free",
        it.now and "" or ("  -  |cffff8040at skill %d|r"):format(it.req)))
      r.sub:ClearAllPoints(); r.sub:SetPoint("TOPLEFT", 12, y - 14)
      r.btn.index = it.index
      r.btn:ClearAllPoints(); r.btn:SetPoint("TOPRIGHT", -12, y - 4)
      if it.now then r.btn:Enable(); ready[#ready + 1] = it.index else r.btn:Disable() end
      r.name:Show(); r.sub:Show(); r.btn:Show()
      y = y - 32
    else
      r.name:Hide(); r.sub:Hide(); r.btn:Hide()
    end
  end
  if n > ROWS then
    panel.foot:SetText(("+ %d more in the full route."):format(n - ROWS))
  else
    panel.foot:SetText("Recipes the trainer hides (its filter) aren't listed.")
  end
  if #ready > 1 then
    panel.all:SetText(("Learn all %d now (%s)"):format(#ready, money(data.totalNow)))
    panel.all:ClearAllPoints(); panel.all:SetPoint("TOPLEFT", 12, y - 2); panel.all:Show()
    y = y - 28
  else panel.all:Hide() end
  panel.foot:ClearAllPoints(); panel.foot:SetPoint("TOPLEFT", 12, y - 2)
  y = y - (panel.foot:GetStringHeight() or 12) - 6
  panel:SetHeight(-y + 10)
end

function TP.Refresh()
  local ok, err = pcall(draw)
  if not ok then Core.ReportError("trainer panel", err) end
end

local f = CreateFrame("Frame")
for _, ev in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED" }) do pcall(f.RegisterEvent, f, ev) end
f:SetScript("OnEvent", function(_, ev)
  if ev == "TRAINER_CLOSED" then if panel then panel:Hide() end
  else C_Timer.After(0, TP.Refresh) end -- after Core has read the window
end)
