-- Mini panel docked to the profession window: the next step of the route (what to
-- craft, how many, materials you have against what it needs), Craft 1 / Craft all,
-- the two steps after it, and what's left to buy. It moves and closes with the
-- profession window and updates as you craft.
local _, ns = ...
local Core, UI, Data = ns.Core, ns.UI, SkillRouteData
local Mini = {}
ns.Mini = Mini

local W = 270
local MAT_ROWS = 6
local RANKS = { [75] = "Journeyman", [150] = "Expert", [225] = "Artisan" }
local RANK_STEP = { Journeyman = 2, Expert = 3, Artisan = 4 }
local COLORS = { orange = "ff8040", yellow = "ffff00", green = "40bf40" }
local LEARN = { trainer = "learn it at your trainer", ["trainer?"] = "learn it at your trainer",
                pattern = "get the pattern first", quest = "it comes from a quest" }

local panel, line
local ui = {}

-- The route as a list of things to do, in order: rank-ups where they're needed, tools,
-- crafts, gathering, gaps. Same rules as the full window's route.
function Mini.Entries(plan)
  local out, trained = {}, plan.max
  for _, st in ipairs(plan.steps) do
    while RANKS[trained] and st.from >= trained do
      local rank = RANKS[trained]
      local rh = Core.RankHow(plan.line, RANK_STEP[rank]) or {}
      local need, mine = Core.RankLevelShort(plan.line, RANK_STEP[rank])
      local text
      if rh.book then text = (rh.book.owned and "Read " or "Buy ") .. rh.book.name .. " (" .. rank .. ")"
      elseif rh.quest then text = ('Quest "%s" for %s'):format(rh.quest.title, rank)
      else text = "Train " .. rank .. (rh.loc and (" at " .. rh.loc.npc) or "") end
      out[#out + 1] = { kind = "rank", text = text, at = trained,
                        warn = need and ("needs character level %d (you're %d)"):format(need, mine) or nil }
      trained = trained + 75
    end
    for _, u in ipairs(st.tools or {}) do
      out[#out + 1] = { kind = "tool", text = ((u.craftSpell and "Craft" or "Buy") .. " 1 x " .. UI.ItemName(u.item) .. " (tool)"), at = st.from }
    end
    if st.gap then
      out[#out + 1] = { kind = "gap", text = ("No usable recipe for %d-%d: see the full route"):format(st.from, st.to), at = st.from }
    elseif st.gather then
      out[#out + 1] = { kind = "gather", text = ("~%d x %s (%d-%d)"):format(math.ceil(st.crafts - 1e-9), st.name, st.from, st.to), at = st.from }
    elseif st.spell then
      out[#out + 1] = { kind = "craft", st = st, at = st.from,
                        text = ("%d x %s (%d-%d)"):format(math.ceil(st.crafts - 1e-9), st.name, st.from, st.to) }
    end
  end
  return out
end

local function font(tmpl, parent) return (parent or panel):CreateFontString(nil, "OVERLAY", tmpl) end
local function button(text, w, onClick)
  local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  b:SetSize(w, 20); b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function parentFrame() return ProfessionsFrame or TradeSkillFrame end

local function build(parent)
  panel = CreateFrame("Frame", "SkillRouteMini", parent, "BasicFrameTemplateWithInset")
  panel:SetWidth(W)
  panel:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, -24)
  panel:SetFrameStrata("HIGH")
  local title = font("GameFontHighlight"); title:SetPoint("TOP", 0, -5); title:SetText("SkillRoute")
  ui.head = font("GameFontDisableSmall"); ui.head:SetPoint("TOPRIGHT", -12, -30)
  ui.cap1 = font("GameFontDisableSmall"); ui.cap1:SetText("NEXT STEP")
  ui.icon = panel:CreateTexture(nil, "ARTWORK"); ui.icon:SetSize(30, 30)
  ui.main = font("GameFontHighlight"); ui.main:SetWidth(W - 66); ui.main:SetJustifyH("LEFT")
  ui.sub = font("GameFontHighlightSmall"); ui.sub:SetWidth(W - 66); ui.sub:SetJustifyH("LEFT")
  -- clicking the step selects its recipe in the profession window
  ui.hit = CreateFrame("Button", nil, panel)
  ui.hit:SetScript("OnClick", function() if ui.spell then Core.OpenRecipe(ui.spell) end end)
  ui.mats = {}
  for i = 1, MAT_ROWS do
    local l, r = font("GameFontHighlightSmall"), font("GameFontHighlightSmall")
    l:SetJustifyH("LEFT"); l:SetWidth(W - 110)
    ui.mats[i] = { l = l, r = r }
  end
  ui.note = font("GameFontHighlightSmall"); ui.note:SetWidth(W - 24); ui.note:SetJustifyH("LEFT")
  ui.note:SetTextColor(1, 0.5, 0.25)
  ui.craft1 = button("Craft 1", 72, function()
    if ui.spell then Core.OpenRecipe(ui.spell); Core.Craft(ui.spell, 1) end
  end)
  ui.craftAll = button("Craft all", 92, function()
    if ui.spell and ui.allN and ui.allN > 0 then Core.OpenRecipe(ui.spell); Core.Craft(ui.spell, ui.allN) end
  end)
  ui.full = button("Full route", 76, function() UI.Toggle(line) end)
  ui.cap2 = font("GameFontDisableSmall"); ui.cap2:SetText("THEN")
  ui.then1 = font("GameFontHighlightSmall"); ui.then1:SetWidth(W - 24); ui.then1:SetJustifyH("LEFT")
  ui.then2 = font("GameFontHighlightSmall"); ui.then2:SetWidth(W - 24); ui.then2:SetJustifyH("LEFT")
  ui.sep = panel:CreateTexture(nil, "ARTWORK")
  if ui.sep.SetColorTexture then ui.sep:SetColorTexture(1, 1, 1, 0.16) end
  ui.sep:SetHeight(1)
  ui.costL = font("GameFontHighlightSmall"); ui.costL:SetText("Left to buy")
  ui.costR = font("GameFontHighlightSmall")
  panel:SetScript("OnShow", function() Mini.Refresh() end)
end

local function place(fs, x, y) fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", x, y) end
local function h(fs) return (fs:GetStringHeight() or 12) end

-- Colour bands of a recipe: the last skill it's orange, yellow and green at.
local function bands(r)
  local greenFrom = math.floor((r.y + r.g) / 2)
  local learnAt = math.min(r.learn or r.y, r.y)
  local b = {}
  if r.y - 1 >= learnAt then b[#b + 1] = ("|cff%s%d|r"):format(COLORS.orange, r.y - 1) end
  if greenFrom - 1 >= r.y then b[#b + 1] = ("|cff%s%d|r"):format(COLORS.yellow, greenFrom - 1) end
  if r.g - 1 >= greenFrom then b[#b + 1] = ("|cff%s%d|r"):format(COLORS.green, r.g - 1) end
  return table.concat(b, " ")
end

local function draw()
  if not (panel and panel:IsShown() and line) then return end
  local c = Core.Char()
  local plan, err = Core.Plan(line, c.targets[line] or 300)
  local y = -30
  for _, m in ipairs(ui.mats) do m.l:SetText(""); m.r:SetText("") end
  ui.note:SetText(""); ui.then1:SetText(""); ui.then2:SetText("")
  ui.spell, ui.allN = nil, 0
  local entries = plan and Mini.Entries(plan) or {}
  local nCraft = 0
  for _, e in ipairs(entries) do if e.kind == "craft" then nCraft = nCraft + 1 end end
  ui.head:SetText(plan and ("%d -> %d  -  %d step%s left"):format(plan.skill, plan.target, nCraft, nCraft == 1 and "" or "s") or "")
  y = y - 16
  place(ui.cap1, 12, y); y = y - 14
  local e = entries[1]
  place(ui.icon, 12, y); place(ui.main, 48, y)
  if not plan then
    ui.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    ui.main:SetText(err or "No route"); ui.sub:SetText("")
  elseif not e then
    ui.icon:SetTexture("Interface\\Icons\\Achievement_Profession_ChefHat")
    ui.main:SetText("|cff40bf40Target reached|r"); ui.sub:SetText("Raise the target in the full route to keep going.")
  elseif e.kind == "craft" then
    local st = e.st
    local r = Data.professions[line].recipes[st.spell]
    ui.spell = st.spell
    ui.icon:SetTexture(UI.Icon(r.out, st.spell))
    ui.main:SetText(("Craft |cffffffff%d x|r %s"):format(math.ceil(st.crafts - 1e-9), st.name))
    ui.sub:SetText(("|cff999999skill %d -> %d|r  %s"):format(st.from, st.to, bands(r)))
  else
    ui.icon:SetTexture(e.kind == "rank" and "Interface\\Icons\\INV_Misc_Book_09" or "Interface\\Icons\\INV_Scroll_03")
    ui.main:SetText("|cffffd100" .. e.text .. "|r")
    ui.sub:SetText(e.warn and ("|cffff4040" .. e.warn .. "|r") or ("|cff999999at skill %d|r"):format(e.at))
  end
  place(ui.sub, 48, y - h(ui.main) - 2)
  local stepH = math.max(30, h(ui.main) + 2 + h(ui.sub))
  ui.hit:ClearAllPoints(); ui.hit:SetPoint("TOPLEFT", 12, y); ui.hit:SetSize(W - 24, stepH)
  y = y - stepH - 6

  -- materials: have (bags) / needed for the rest of this step
  local known = false
  if ui.spell then
    local st = e.st
    local r = Data.professions[line].recipes[st.spell]
    local crafts = math.ceil(st.crafts - 1e-9)
    for i = 1, math.min(#r.r / 2, MAT_ROWS) do
      local item, per = r.r[2 * i - 1], r.r[2 * i]
      local need = per * crafts
      local have = GetItemCount and GetItemCount(item) or 0
      local it = Data.items[item]
      local m = ui.mats[i]
      m.l:SetText(UI.ItemName(item))
      m.r:SetText(("|cff%s%d / %d|r%s"):format(have >= need and "40bf40" or "ff6060", have, need,
        (have < need and it and it[3]) and " |cff999999vendor|r" or ""))
      place(m.l, 12, y); m.r:ClearAllPoints(); m.r:SetPoint("TOPRIGHT", -12, y)
      y = y - 14
    end
    known = Core.IsRecipeKnown(line, st.spell)
    ui.allN = math.min(crafts, Core.CraftableNow(line, st.spell))
    if not known then ui.note:SetText("Not learned yet: " .. (LEARN[st.learn] or "learn it first") .. ".") end
  end
  if ui.note:GetText() ~= "" then place(ui.note, 12, y - 2); y = y - h(ui.note) - 4 end

  y = y - 4
  for _, b in ipairs({ ui.craft1, ui.craftAll }) do
    if ui.spell and known and ui.allN > 0 then b:Enable() else b:Disable() end
  end
  ui.craftAll:SetText(ui.allN > 0 and ("Craft all (%d)"):format(ui.allN) or "Craft all")
  ui.craft1:ClearAllPoints(); ui.craft1:SetPoint("TOPLEFT", 12, y)
  ui.craftAll:ClearAllPoints(); ui.craftAll:SetPoint("LEFT", ui.craft1, "RIGHT", 4, 0)
  ui.full:ClearAllPoints(); ui.full:SetPoint("TOPRIGHT", -12, y)
  y = y - 28

  if entries[2] then
    place(ui.cap2, 12, y); y = y - 14
    ui.then1:SetText(entries[2].text); place(ui.then1, 12, y); y = y - h(ui.then1) - 2
    if entries[3] then ui.then2:SetText(entries[3].text); place(ui.then2, 12, y); y = y - h(ui.then2) - 2 end
    ui.cap2:Show()
  else ui.cap2:Hide() end

  y = y - 6
  ui.sep:ClearAllPoints(); ui.sep:SetPoint("TOPLEFT", 12, y); ui.sep:SetPoint("TOPRIGHT", -12, y)
  y = y - 6
  place(ui.costL, 12, y)
  ui.costR:ClearAllPoints(); ui.costR:SetPoint("TOPRIGHT", -12, y)
  ui.costR:SetText(plan and UI.Money(plan.total) or "")
  panel:SetHeight(-y + 24)
end

function Mini.Refresh()
  local ok, err = pcall(draw)
  if not ok then
    Core.ReportError("mini panel", err)
    if ui.main then ui.main:SetText("|cffff4040SkillRoute couldn't plan: /sr check|r") end
  end
end

-- Show it for a profession (called when the profession window opens). Returns false if
-- there's no profession window to dock to, so the full window opens instead.
function Mini.Show(l)
  local parent = parentFrame()
  if not parent then return false end
  if not panel then build(parent) end
  line = l
  if panel:IsShown() then Mini.Refresh() else panel:Show() end
  return true
end

function Mini.IsShown() return panel and panel:IsShown() end
