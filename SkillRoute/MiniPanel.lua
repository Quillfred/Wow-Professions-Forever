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
  local out, trained, toolShown = {}, plan.max, {}
  for _, st in ipairs(plan.steps) do
    while RANKS[trained] and st.from >= trained do
      local rank = RANKS[trained]
      local rh = Core.RankHow(plan.line, RANK_STEP[rank]) or {}
      local need, mine = Core.RankLevelShort(plan.line, RANK_STEP[rank])
      local text, loc
      if rh.book then text, loc = (rh.book.owned and "Read " or "Buy ") .. rh.book.name .. " (" .. rank .. ")", rh.book.loc
      elseif rh.quest then text, loc = ('Quest "%s" for %s'):format(rh.quest.title, rank), rh.quest.loc
      else text, loc = "Train " .. rank .. (rh.loc and (" at " .. rh.loc.npc) or ""), rh.loc end
      out[#out + 1] = { kind = "rank", text = text, at = trained, loc = loc,
                        warn = need and ("needs character level %d (you're %d)"):format(need, mine) or nil }
      trained = trained + 75
    end
    for _, u in ipairs(st.tools or {}) do
      if not toolShown[u] then -- once, before the first step that needs it
        toolShown[u] = true
        out[#out + 1] = { kind = "tool", spell = u.craftSpell, item = u.item, learn = u.learnHow, at = st.from,
                          text = ((u.craftSpell and "Craft" or "Buy") .. " 1 x " .. UI.ItemName(u.item) .. " (tool)"),
                          -- a one-craft step, so Buy and "To buy" work for its materials too
                          buy = u.craftSpell and { spell = u.craftSpell, name = UI.ItemName(u.item), crafts = 1, var = 0,
                                                   from = st.from, to = st.from } or nil }
      end
    end
    if st.gap then
      out[#out + 1] = { kind = "gap", text = ("No usable recipe for %d-%d: see the full route"):format(st.from, st.to), at = st.from }
    elseif st.gather then
      out[#out + 1] = { kind = "gather", st = st, at = st.from,
                        text = ("~%d x %s (%d-%d)"):format(math.ceil(st.crafts - 1e-9), st.name, st.from, st.to) }
    elseif st.spell then
      out[#out + 1] = { kind = "craft", st = st, at = st.from,
                        text = st.smeltStep and ("Smelt %d x %s (%d-%d)"):format(st.crafts, st.ore, st.from, st.to)
                               or ("%d x %s (%d-%d)"):format(math.ceil(st.crafts - 1e-9), st.name, st.from, st.to) }
    end
  end
  return out
end

-- Smelting the ore in your bags needs a forge. Away from one (or out in the world, for
-- the tracker: atForge nil) the vein step comes first and the smelt is a reminder under
-- it, yellow once waiting would cost sure skill-ups. Returns the entries to show (a new
-- list when it moves something) and the smelt entry, or nil.
function Mini.DeferSmelt(entries, atForge)
  local e = entries[1]
  if atForge or not (e and e.kind == "craft" and e.st.smeltStep and entries[2]) then return entries, nil end
  local out = {}
  for i = 2, #entries do out[#out + 1] = entries[i] end
  return out, e
end
function Mini.SmeltReminder(plan, st)
  local r = Data.professions[186].recipes[st.spell]
  local what = ("Smelt %d x %s"):format(st.crafts, st.ore)
  if plan.skill >= r.y then
    return ("|cffffd100%s soon: a chance at a skill-up each now, none from %d|r"):format(what, r.g)
  elseif plan.skill + 5 >= r.y then
    return ("|cffffd100%s soon: a sure skill-up each only until %d|r"):format(what, r.y)
  end
  return ("|cffcccccc%s at a forge (skill %d-%d)|r"):format(what, st.from, st.to)
end

-- How to learn a step's recipe: the full route's own words and waypoint (vendor, AH,
-- your bank, quest, trainer), so the two panels always agree. nil if it says nothing.
function Mini.LearnNote(plan, st)
  local ok, _, _, waypoint, learnText = pcall(UI.StepTip, plan, st)
  if ok and learnText and learnText ~= "" then return UI.Plain(learnText), waypoint end
end

-- Where to get what's missing of a material: in the mail, a vendor, or the AH (cheaper
-- than the vendor). The same rule as the step's buy list. Shared with the tracker.
function Mini.MatTag(item, have, need)
  if have >= need then return "" end
  local mail = Core.InMail(item)
  if mail > 0 then return (" |cff33ccff%d in the mail|r"):format(mail) end -- bought: collect it
  local it = Data.items[item]
  if it and it[3] then return Core.FromVendor(item) and " |cff999999vendor|r" or " |cff999999AH: cheaper|r" end
  return ""
end

-- The step's AH buy line: the same amounts the Buy button sends (your safety margin
-- included, bank, mail and alts taken off), so they always agree. nil: nothing to buy.
function Mini.BuyText(plan, buyStep)
  if not (buyStep and Core.StepShopping) then return nil end
  local list = Core.StepShopping(plan, buyStep)
  if #list == 0 then return nil, 0 end
  local cost, qty, missing = 0, 0, false
  for _, x in ipairs(list) do
    local p = Core.Price(x.item)
    qty = qty + x.qty
    if p then cost = cost + p * x.qty else missing = true end
  end
  local sure = (SkillRouteDB.settings or {}).margin or 90
  return (#list == 1 and ("|cffff6060This step: buy %d|r (%d%% sure): ~%s on the AH%s"):format(qty, sure, UI.Money(cost), missing and " (unpriced)" or "")
          or ("|cffff6060This step:|r ~%s on the AH (%d%% sure)%s"):format(UI.Money(cost), sure, missing and " (some unpriced)" or "")), #list
end

local function font(tmpl, parent) return (parent or panel):CreateFontString(nil, "OVERLAY", tmpl) end
local function button(text, w, onClick)
  local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  b:SetSize(w, 20); b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function parentFrame() return ProfessionsFrame or TradeSkillFrame end

-- How far right of the profession window to dock: past anything sticking out of its
-- right edge (the side tabs for your other professions).
local function dockX(parent)
  local edge = parent.GetRight and parent:GetRight()
  if not edge then return 2 end
  local far = edge
  local kids = { parent:GetChildren() }
  for _, k in ipairs(kids) do
    if k ~= panel and not (k.IsForbidden and k:IsForbidden()) and k.IsShown and k:IsShown() and k.GetLeft then
      local l, r = k:GetLeft(), k:GetRight()
      if l and r and l >= edge - 12 and r > far and r - edge < 120 then far = r end
    end
  end
  return math.floor(far - edge + 2)
end

-- Docked by default; drag it anywhere (the spot is remembered, relative to the window);
-- right-click the title bar to dock it again.
local function dock(parent)
  local o = (SkillRouteDB.settings or {}).miniPos
  panel:ClearAllPoints()
  if o then panel:SetPoint("TOPLEFT", parent, "TOPRIGHT", o[1], o[2])
  else panel:SetPoint("TOPLEFT", parent, "TOPRIGHT", dockX(parent), -24) end
end

local function build(parent)
  panel = CreateFrame("Frame", "SkillRouteMini", parent, "BasicFrameTemplateWithInset")
  panel:SetWidth(W)
  panel:SetFrameStrata("HIGH")
  panel:SetMovable(true); panel:EnableMouse(true); panel:RegisterForDrag("LeftButton")
  panel:SetClampedToScreen(true)
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local l, t, pr, pt = self:GetLeft(), self:GetTop(), parent:GetRight(), parent:GetTop()
    if l and t and pr and pt then
      SkillRouteDB.settings = SkillRouteDB.settings or {}
      SkillRouteDB.settings.miniPos = { math.floor(l - pr + 0.5), math.floor(t - pt + 0.5) }
    end
    dock(parent)
  end)
  panel:SetScript("OnMouseUp", function(_, btn)
    if btn == "RightButton" then SkillRouteDB.settings.miniPos = nil; dock(parent) end
  end)
  local title = font("GameFontHighlight"); title:SetPoint("TOP", 0, -5); title:SetText("SkillRoute")
  ui.head = font("GameFontDisableSmall"); ui.head:SetPoint("TOPRIGHT", -12, -30)
  ui.cap1 = font("GameFontDisableSmall"); ui.cap1:SetText("NEXT STEP")
  ui.icon = panel:CreateTexture(nil, "ARTWORK"); ui.icon:SetSize(30, 30)
  ui.main = font("GameFontHighlight"); ui.main:SetWidth(W - 66); ui.main:SetJustifyH("LEFT")
  ui.sub = font("GameFontHighlightSmall"); ui.sub:SetWidth(W - 66); ui.sub:SetJustifyH("LEFT")
  -- clicking the step selects its recipe in the profession window
  ui.hit = CreateFrame("Button", nil, panel)
  -- click: open a recipe you know; else a waypoint to whoever teaches or sells it
  ui.hit:SetScript("OnClick", function()
    if ui.spell and Core.IsRecipeKnown(line, ui.spell) then Core.OpenRecipe(ui.spell)
    elseif ui.loc then Core.Waypoint(ui.loc) end
  end)
  -- hover: the same tooltip as the step in the full route
  ui.hit:SetScript("OnEnter", function(self)
    if not ui.st and ui.loc then -- a trainer, book or quest step
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(ui.loc.npc or "Waypoint")
      GameTooltip:AddLine(Core.Where(ui.loc) or "", 1, 1, 1, true)
      local tr = Core.TravelText(ui.loc)
      if tr then GameTooltip:AddLine(tr, 0.7, 0.7, 0.7, true) end
      GameTooltip:AddLine("Click: waypoint", 0.6, 0.6, 0.6)
      GameTooltip:Show()
      return
    end
    if not (ui.plan and ui.st) then return end
    local ok, r, tip = pcall(UI.StepTip, ui.plan, ui.st)
    if not ok or not tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if r.out and GameTooltip.SetItemByID then GameTooltip:SetItemByID(r.out)
    elseif GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(ui.st.spell) end
    UI.AddTipLines(tip)
    GameTooltip:Show()
  end)
  ui.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
  ui.mats = {}
  for i = 1, MAT_ROWS do
    local l, r = font("GameFontHighlightSmall"), font("GameFontHighlightSmall")
    l:SetJustifyH("LEFT"); l:SetWidth(W - 110)
    ui.mats[i] = { l = l, r = r }
  end
  ui.short = font("GameFontHighlightSmall"); ui.short:SetWidth(W - 90); ui.short:SetJustifyH("LEFT")
  ui.buy = button("Buy", 60, function()
    if ui.plan and ui.buyStep then ui.buy:SetText(Core.BuyStep(ui.plan, ui.buyStep)) end
  end)
  ui.after = font("GameFontHighlightSmall"); ui.after:SetWidth(W - 24); ui.after:SetJustifyH("LEFT")
  ui.note = font("GameFontHighlightSmall"); ui.note:SetWidth(W - 24); ui.note:SetJustifyH("LEFT")
  ui.note:SetTextColor(1, 0.5, 0.25)
  -- the note is clickable too: a waypoint to whoever teaches it
  ui.noteHit = CreateFrame("Button", nil, panel)
  ui.noteHit:SetScript("OnClick", function() if ui.loc then Core.Waypoint(ui.loc) end end)
  ui.noteHit:SetScript("OnEnter", function(self)
    if not ui.loc then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(ui.loc.npc or "Waypoint")
    local tr = Core.TravelText(ui.loc)
    if tr then GameTooltip:AddLine(tr, 0.7, 0.7, 0.7, true) end
    GameTooltip:AddLine("Click: waypoint", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  ui.noteHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
  ui.noteHit:Hide()
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
  panel:SetScript("OnShow", function() dock(parent); Mini.Refresh() end)
  -- walking up to (or away from) a forge with the window open: the game sends no event
  -- for it, so look twice a second, and redraw only when the answer changes
  local since = 0
  panel:SetScript("OnUpdate", function(_, dt)
    if not ui.toolSpell then return end
    since = since + (dt or 0)
    if since < 0.5 then return end
    since = 0
    local miss = Core.MissingTools(ui.toolSpell)
    if (miss and table.concat(miss, ",")) ~= ui.toolKey then Mini.Refresh() end
  end)
  dock(parent)
end

local function place(fs, x, y) fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", x, y) end
local function h(fs) return (fs:GetStringHeight() or 12) end

local function bands(r) return UI.Bands(r, " ") end -- the full route's own

local function draw()
  if not (panel and panel:IsShown() and line) then return end
  local c = Core.Char()
  local plan, err, why = Core.Plan(line, c.targets[line] or 300)
  local y = -30
  for _, m in ipairs(ui.mats) do m.l:SetText(""); m.r:SetText("") end
  ui.note:SetText(""); ui.then1:SetText(""); ui.then2:SetText("")
  ui.spell, ui.allN, ui.crafts, ui.learn, ui.st, ui.plan, ui.buyStep, ui.loc, ui.missing = nil, 0, 0, nil, nil, plan, nil, nil, nil
  ui.toolSpell, ui.toolKey = nil, nil -- the recipe whose forge/tools decide what's shown (watched while open)
  ui.short:SetText(""); ui.after:SetText(""); ui.buy:Hide()
  local entries = plan and Mini.Entries(plan) or {}
  local remind -- smelting with no forge here: mine first, smelt later
  if entries[1] and entries[1].kind == "craft" and entries[1].st.smeltStep then
    local miss = Core.MissingTools(entries[1].st.spell)
    ui.toolSpell, ui.toolKey = entries[1].st.spell, miss and table.concat(miss, ",")
    entries, remind = Mini.DeferSmelt(entries, not (miss and #miss > 0))
  end
  local nCraft = remind and 1 or 0
  for _, e in ipairs(entries) do if e.kind == "craft" or e.kind == "gather" then nCraft = nCraft + 1 end end
  ui.head:SetText(plan and ("%d -> %d  -  %d step%s left"):format(plan.skill, plan.target, nCraft, nCraft == 1 and "" or "s") or "")
  y = y - 16
  place(ui.cap1, 12, y); y = y - 14
  local e = entries[1]
  place(ui.icon, 12, y); place(ui.main, 48, y)
  if not plan and why == "maxed" then
    ui.icon:SetTexture("Interface\\Icons\\Achievement_Profession_ChefHat")
    ui.main:SetText("|cff40bf40" .. err .. "|r"); ui.sub:SetText("")
  elseif not plan then
    ui.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    ui.main:SetText(err or "No route"); ui.sub:SetText("")
  elseif not e then
    ui.icon:SetTexture("Interface\\Icons\\Achievement_Profession_ChefHat")
    ui.main:SetText("|cff40bf40Target reached|r"); ui.sub:SetText("Raise the target in the full route to keep going.")
  elseif e.kind == "craft" then
    local st = e.st
    local r = Data.professions[line].recipes[st.spell]
    ui.spell, ui.crafts, ui.learn, ui.st, ui.buyStep = st.spell, math.ceil(st.crafts - 1e-9), st.learn, st, st
    ui.icon:SetTexture(UI.Icon(r.out, st.spell))
    ui.main:SetText(st.smeltStep and ("Smelt |cffffffff%d x|r %s"):format(ui.crafts, st.ore)
                    or ("Craft |cffffffff%d x|r %s"):format(ui.crafts, st.name))
    ui.sub:SetText(("|cff999999skill %d -> %d|r  %s"):format(st.from, st.to, bands(r)))
  elseif e.kind == "tool" and e.spell then -- a tool you craft: same as a craft, once
    ui.spell, ui.crafts, ui.learn, ui.buyStep = e.spell, 1, e.learn, e.buy
    ui.icon:SetTexture(UI.Icon(e.item, e.spell))
    ui.main:SetText("|cffff8040" .. e.text .. "|r")
    ui.sub:SetText(("|cff999999needed from skill %d; keep it in your bags|r"):format(e.at))
  elseif e.kind == "gather" then -- where to go: the best zones (as on the full route)
    local st = e.st
    ui.icon:SetTexture(st.skinning and "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" or st.fishing and "Interface\\Icons\\Trade_Fishing"
      or line == 186 and "Interface\\Icons\\Trade_Mining" or "Interface\\Icons\\Trade_Herbalism")
    ui.main:SetText(("|cffffd100~%d x %s|r"):format(math.ceil(st.crafts - 1e-9), st.name)
      .. ((st.alt and st.alt[1]) and (" |cffcccccc(or %s)|r"):format(st.alt[1]) or "")
      .. (st.smelt and "|cffffd100, smelting the ore|r" or ""))
    local zones = UI.GatherZones(st)
    ui.sub:SetText(("|cff999999skill %d -> %d|r  %s"):format(st.from, st.to, #zones > 0 and table.concat(zones, ", ") or ""))
  else
    ui.icon:SetTexture(e.kind == "rank" and "Interface\\Icons\\INV_Misc_Book_09" or "Interface\\Icons\\INV_Scroll_03")
    ui.main:SetText("|cffffd100" .. e.text .. "|r")
    ui.loc = e.loc
    ui.sub:SetText(e.warn and ("|cffff4040" .. e.warn .. "|r") or ("|cff999999at skill %d|r"):format(e.at))
  end
  place(ui.sub, 48, y - h(ui.main) - 2)
  local stepH = math.max(30, h(ui.main) + 2 + h(ui.sub))
  ui.hit:ClearAllPoints(); ui.hit:SetPoint("TOPLEFT", 12, y); ui.hit:SetSize(W - 24, stepH)
  y = y - stepH - 6

  -- materials: have (bags) / needed for the rest of this step
  local known = false
  if ui.spell then
    local r = Data.professions[line].recipes[ui.spell]
    local crafts = ui.crafts
    for i = 1, math.min(#r.r / 2, MAT_ROWS) do
      local item, per = r.r[2 * i - 1], r.r[2 * i]
      local need = per * crafts
      local have = Core.InBags(item)
      local m = ui.mats[i]
      m.l:SetText(UI.ItemName(item))
      m.r:SetText(("|cff%s%d / %d|r%s"):format(have >= need and "40bf40" or "ff6060", have, need, Mini.MatTag(item, have, need)))
      place(m.l, 12, y); m.r:ClearAllPoints(); m.r:SetPoint("TOPRIGHT", -12, y)
      y = y - 14
    end
    -- what you're short of, at AH prices (vendor items say "vendor" on their row)
    local shortCost, shortN, unpriced = 0, 0, false
    for i = 1, #r.r, 2 do
      local item, need = r.r[i], r.r[i + 1] * crafts
      local miss = need - Core.InBags(item)
      if miss > 0 and not Core.FromVendor(item) then
        local p = Core.Price(item)
        shortN = shortN + 1
        if p then shortCost = shortCost + p * miss else unpriced = true end
      end
    end
    -- a craft step: the same amounts the Buy button sends to Auctionator (your safety
    -- margin included, bank and alts taken off), so the two always agree
    local buyText, n = Mini.BuyText(ui.plan, ui.buyStep)
    if n then shortN = n end
    if shortN > 0 then
      -- the Buy button only shows at the AH: elsewhere the line uses the whole width
      local showBuy = ui.buyStep and Core.CanBuyHere()
      ui.short:SetWidth(showBuy and (W - 90) or (W - 24))
      ui.short:SetText(buyText or ("|cffff6060Short:|r ~%s on the AH%s"):format(UI.Money(shortCost), unpriced and " (some unpriced)" or ""))
      place(ui.short, 12, y - 2)
      local bk = ui.buyStep and ((ui.buyStep.spell or 0) .. ":" .. (ui.buyStep.from or 0))
      if bk ~= ui.buyKey then ui.buyKey = bk; ui.buy:SetText("Buy") end -- a new step starts at its first material
      if showBuy then
        ui.buy:ClearAllPoints(); ui.buy:SetPoint("TOPRIGHT", -12, y + 2); ui.buy:Show()
      end
      y = y - math.max(h(ui.short), 16) - 4
    end
    -- afterwards: what to do with what you make (the full tooltip has the comparison)
    if ui.st then
      local after
      if ui.st.smeltStep then after = nil
      elseif ui.st.credited then after = "used by later steps"
      elseif ui.st.resale then after = "|cff40bf40sell on the AH|r"
      elseif r.out then after = UI.AfterCrafting(r.out, crafts * (r.outN or 1)) end
      if after then
        ui.after:SetText("|cff999999Afterwards:|r " .. after)
        place(ui.after, 12, y - 2); y = y - h(ui.after) - 4
      end
    end
    known = Core.IsRecipeKnown(line, ui.spell)
    ui.allN = math.min(crafts, Core.CraftableNow(line, ui.spell))
    local miss = Core.MissingTools(ui.spell) -- a forge, an anvil, a rod you aren't at / don't carry
    ui.missing = miss and #miss > 0 and miss or nil
    ui.toolSpell, ui.toolKey = ui.spell, miss and table.concat(miss, ",")
    if known and ui.missing then
      ui.note:SetText("|cffff6060Needs: " .. table.concat(ui.missing, ", ") .. "|r")
    end
    if not known then
      local how
      if ui.st then how, ui.loc = Mini.LearnNote(ui.plan, ui.st) end
      if not how then -- a tool: the trainer that teaches it, as on the full route's tool row
        local t = Core.NearestRecipeTrainer(line, ui.spell, r.learn or r.y)
        if t then how = ("Learn at %s, %s"):format(t.npc, Core.Where(t) or "?"); ui.loc = t
        else how = LEARN[ui.learn] or "learn it first" end
      end
      ui.note:SetText("Not learned yet: " .. how .. (ui.loc and " (click for a waypoint)" or ""))
    end
  end
  if remind and ui.note:GetText() == "" then ui.note:SetText(Mini.SmeltReminder(plan, remind.st)) end
  ui.noteHit:Hide()
  if ui.note:GetText() ~= "" then
    place(ui.note, 12, y - 2)
    if ui.loc then
      ui.noteHit:ClearAllPoints(); ui.noteHit:SetPoint("TOPLEFT", 12, y - 2)
      ui.noteHit:SetSize(W - 24, h(ui.note)); ui.noteHit:Show()
    end
    y = y - h(ui.note) - 4
  end

  y = y - 4
  local gathering = plan and plan.gather and not ui.spell -- (smelting your ore has Craft buttons)
  for _, b in ipairs({ ui.craft1, ui.craftAll }) do if gathering then b:Hide() else b:Show() end end
  for _, b in ipairs({ ui.craft1, ui.craftAll }) do
    if ui.spell and known and ui.allN > 0 and not ui.missing then b:Enable() else b:Disable() end
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
  if plan and plan.gather then -- no gold to spend (smelt steps included): how many nodes in all
    ui.costL:SetText(plan.fishing and "Catches in all" or "Nodes in all")
    ui.costR:SetText(("~%d"):format(math.ceil(plan.gathers or 0)))
  else
    ui.costL:SetText("Left to buy")
    ui.costR:SetText(plan and UI.Money(plan.total) or "")
  end
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
  Core.Char().lastLine = l -- the tracker shows this profession once the window closes
  if panel:IsShown() then Mini.Refresh() else panel:Show() end
  return true
end

function Mini.IsShown() return panel and panel:IsShown() end
