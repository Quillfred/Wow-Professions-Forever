-- Minimap button and options window. Every control writes the same setting as its
-- /sr command and re-plans at once.
local _, ns = ...
local Core, UI = ns.Core, ns.UI
local Options = {}
ns.Options = Options

local function settings()
  SkillRouteDB = SkillRouteDB or {}
  SkillRouteDB.settings = SkillRouteDB.settings or {}
  return SkillRouteDB.settings
end

-- One place to change a setting: store it, drop cached choices, re-plan if open.
function Options.Set(key, value)
  settings()[key] = value
  Core.InvalidatePatterns()
  Core.Changed()
  if key == "minimapHide" then Options.UpdateMinimap() end
end

-- Minimap button ---------------------------------------------------------------------
local button

local function placeButton()
  local a = math.rad(settings().minimapAngle or 215)
  local r = (Minimap:GetWidth() / 2) + 5
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function dragUpdate()
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  cx, cy = cx / scale, cy / scale
  settings().minimapAngle = math.deg(math.atan2(cy - my, cx - mx)) % 360
  placeButton()
end

function Options.CreateMinimapButton()
  if button or not Minimap then return button end
  button = CreateFrame("Button", "SkillRouteMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local bg = button:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20); bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(17, 17); icon:SetTexture("Interface\\Icons\\Trade_Tailoring")
  icon:SetPoint("TOPLEFT", 7, -6)
  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetPoint("TOPLEFT")
  button:SetScript("OnClick", function(_, which)
    if which == "RightButton" then Options.Toggle() else UI.Toggle() end
  end)
  button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", dragUpdate) end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("SkillRoute")
    GameTooltip:AddLine("Left-click: open / close", 1, 1, 1)
    GameTooltip:AddLine("Right-click: options", 1, 1, 1)
    GameTooltip:AddLine("Drag: move around the minimap", 1, 1, 1)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  placeButton()
  Options.UpdateMinimap()
  return button
end

function Options.UpdateMinimap()
  if not button then return end
  if settings().minimapHide then button:Hide() else button:Show() end
end

-- Options window ---------------------------------------------------------------------
local panel
local refreshers = {} -- functions that show the current setting values

local function check(parent, y, label, tip, get, set)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(24, 24)
  c:SetPoint("TOPLEFT", 16, y)
  local t = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  t:SetPoint("LEFT", c, "RIGHT", 4, 0)
  t:SetText(label)
  c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  c:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(label)
    GameTooltip:AddLine(tip, 1, 1, 1, true); GameTooltip:Show()
  end)
  c:SetScript("OnLeave", function() GameTooltip:Hide() end)
  refreshers[#refreshers + 1] = function() c:SetChecked(get()) end
  return y - 28
end

-- A slider where the client has the classic template, else a number box.
-- A slider row. opts (optional): ends = { left, right } labels under the slider (the
-- left one turns gold at the minimum), example = function(v) -> text (blue, rewritten as
-- the slider moves), caution = text (orange, below the rest).
local WIDTH = 340
local function number(parent, y, label, tip, lo, hi, step, fmt, get, set, opts)
  opts = opts or {}
  local t = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("TOPLEFT", 20, y)
  t:SetText(label)
  local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  value:SetPoint("TOPRIGHT", -24, y)
  local below = y - 40
  local left, right
  if opts.ends then
    left = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    left:SetPoint("TOPLEFT", 24, y - 38); left:SetText(opts.ends[1])
    right = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    right:SetPoint("TOPRIGHT", -24, y - 38); right:SetText(opts.ends[2])
    below = y - 54
  end
  local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 20, below); hint:SetWidth(WIDTH); hint:SetJustifyH("LEFT")
  hint:SetText(tip)
  below = below - (hint:GetStringHeight() or 12) - 4
  local example
  if opts.example then
    example = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    example:SetPoint("TOPLEFT", 20, below); example:SetWidth(WIDTH); example:SetJustifyH("LEFT")
    example:SetTextColor(0.56, 0.78, 1)
    below = below - 40 -- room for three lines, so the rows below don't move as the text changes
  end
  if opts.caution then
    local c = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c:SetPoint("TOPLEFT", 20, below); c:SetWidth(WIDTH); c:SetJustifyH("LEFT")
    c:SetTextColor(0.95, 0.68, 0.35)
    c:SetText(opts.caution)
    below = below - (c:GetStringHeight() or 24) - 4
  end
  local function show(v)
    value:SetText(fmt(v))
    if example then example:SetText(opts.example(v)) end
    if left then
      if v <= lo then left:SetTextColor(1, 0.82, 0) else left:SetTextColor(0.5, 0.5, 0.5) end
    end
  end
  local ok, s = pcall(CreateFrame, "Slider", nil, parent, "OptionsSliderTemplate")
  if ok and s then
    s:SetPoint("TOPLEFT", 24, y - 20); s:SetPoint("RIGHT", -24, 0)
    s:SetMinMaxValues(lo, hi); s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    for _, k in ipairs({ "Low", "High", "Text" }) do
      local fs = s[k]
      if type(fs) ~= "table" then fs = s.GetName and s:GetName() and _G[s:GetName() .. k] end
      if type(fs) == "table" and fs.SetText then fs:SetText("") end
    end
    local busy = false
    s:SetScript("OnValueChanged", function(_, v)
      v = math.floor(v / step + 0.5) * step
      show(v)
      if not busy then set(v) end
    end)
    refreshers[#refreshers + 1] = function() busy = true; s:SetValue(get()); show(get()); busy = false end
  else
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(60, 20); e:SetPoint("TOPLEFT", 28, y - 20)
    e:SetAutoFocus(false); e:SetNumeric(true)
    e:SetScript("OnEnterPressed", function(self)
      local v = tonumber(self:GetText())
      if v then set(math.max(lo, math.min(hi, v))); show(get()) end
      self:ClearFocus()
    end)
    refreshers[#refreshers + 1] = function() e:SetText(tostring(get())); show(get()) end
  end
  return below - 8
end

-- Silver amount as text: 44 -> "44s", 138 -> "1g 38s".
local function silver(n)
  n = math.floor(n + 0.5)
  local g, s = math.floor(n / 100), n % 100
  if g == 0 then return s .. "s" end
  return s == 0 and (g .. "g") or (g .. "g " .. s .. "s")
end

local WIN = "|cff40bf40wins|r"

-- Live example for "Expect to sell what you make": a 30s craft whose item sells for 40s.
-- Mirrors the planner: share x 95% (after the AH cut) x price comes off the craft's cost,
-- and a craft that pays for itself counts as nearly free, never as profit.
function Options.ResaleExample(pct)
  if pct <= 0 then return "Off: only what you spend counts." end
  local back = math.floor(40 * 0.95 * pct / 100 + 0.5)
  if back >= 30 then
    return ("At %d%%: a 30s craft whose item sells for 40s pays for itself (%s back), so it counts as nearly free.")
      :format(pct, silver(back))
  end
  return ("At %d%%: a 30s craft whose item sells for 40s counts as %s (30s minus %s back).")
    :format(pct, silver(30 - back), silver(back))
end

-- Live example for "Prefer fewer crafts": an orange 50s recipe (1 craft per point) against
-- a 10s one at a 1-in-3 chance (3 crafts, 30s per point). The planner compares
-- (cost + v) / chance, so the orange one wins above v = 10s: 20s more to save 2 crafts.
function Options.FewerExample(v)
  if v <= 0 then
    return "Off: always the cheapest materials. A 10s recipe you craft 3 times (30s per point) " .. WIN .. " over an orange 50s one."
  end
  if v < 10 then
    return ("At %s: the 10s recipe you craft 3 times (30s) still %s. The orange 50s one costs 20s more, and saving 2 crafts is only worth %s to you.")
      :format(silver(v), WIN, silver(2 * v))
  elseif v == 10 then
    return "At 10s: about even. The orange 50s one costs 20s more, and saving 2 crafts is worth exactly 20s to you."
  end
  return ("At %s: the orange 50s recipe %s over a 10s one you craft 3 times (30s). It costs 20s more, and saving 2 crafts is worth %s to you.")
    :format(silver(v), WIN, silver(2 * v))
end

local function build()
  panel = CreateFrame("Frame", "SkillRouteOptions", UIParent, "BasicFrameTemplateWithInset")
  panel:SetSize(380, 560)
  panel:SetPoint("CENTER", 220, 0)
  panel:SetMovable(true); panel:EnableMouse(true); panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  panel:SetClampedToScreen(true)
  panel:SetScript("OnShow", function() for _, f in ipairs(refreshers) do f() end end)
  tinsert(UISpecialFrames, "SkillRouteOptions")
  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", 0, -5)
  title:SetText("SkillRoute options")

  local S = settings
  local y = -34
  y = check(panel, y, "Open with the profession window",
    "Opening a crafting profession window opens SkillRoute too.",
    function() return S().auto ~= false end, function(v) Options.Set("auto", v) end)
  y = check(panel, y, "Count materials on my alts",
    "Uses Syndicator or DataStore, if installed.",
    function() return S().alts ~= false end, function(v) Options.Set("alts", v) end)
  y = check(panel, y, "Estimate prices the AH hasn't shown",
    "4x the vendor price, marked in orange. Off: recipes with unpriced materials are skipped.",
    function() return S().estimate == true end, function(v) Options.Set("estimate", v) end)
  y = check(panel, y, "Allow cooldown materials (Mooncloth, Arcanite)",
    "These are scarce and expensive; off by default.",
    function() return S().cdmats == true end, function(v) Options.Set("cdmats", v) end)
  y = check(panel, y, "Show the minimap button",
    "Left-click opens SkillRoute, right-click these options.",
    function() return not S().minimapHide end, function(v) Options.Set("minimapHide", not v) end)
  y = y - 6
  y = number(panel, y, "Shopping list safety margin",
    "Buy enough to finish the route this often (50% = the expected amount).",
    50, 99, 1, function(v) return ("%d%%"):format(v) end,
    function() return S().margin or 90 end, function(v) Options.Set("margin", v) end)
  y = number(panel, y, "Working Overtime talent",
    "Extra skill-up chance from the talent; 0 if you don't have it.",
    0, 20, 1, function(v) return ("%d%%"):format(v) end,
    function() return math.floor((S().bonus or 0) * 100 + 0.5) end, function(v) Options.Set("bonus", v / 100) end)
  y = number(panel, y, "Expect to sell what you make",
    "Recipes whose items sell well get picked more often. Counts this share of each item's AH price (after the 5% cut) as money back. Nothing is listed for you; the route shows it as \"~X back from sales\".",
    0, 100, 5, function(v) return v == 0 and "off" or ("%d%% of AH price"):format(v) end,
    function() return S().resale or 0 end, function(v) Options.Set("resale", v) end,
    { ends = { "Ignore sales", "Full AH price" }, example = Options.ResaleExample,
      caution = "You may need to craft many of the same item. Listing them all at once drives the price down, and you lose the deposit on any that don't sell. Set this low unless you know they sell well." })
  y = number(panel, y, "Prefer fewer crafts",
    "Picks a recipe that skills up more reliably even if its materials cost more for each craft it saves you. Nothing is charged; it only changes which recipe is chosen.",
    0, 100, 1, function(v) return v == 0 and "off" or ("up to " .. silver(v)) end,
    function() return math.floor((S().craftValue or 0) / 100) end, function(v) Options.Set("craftValue", v * 100) end,
    { ends = { "Cheapest materials", "Fewest crafts" }, example = Options.FewerExample })

  panel:SetHeight(-y + 46)
  panel:Hide() -- new frames start shown; the first Toggle must open it, not close it

  local b1 = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  b1:SetSize(160, 22); b1:SetPoint("BOTTOMLEFT", 16, 14); b1:SetText("Run self-check")
  b1:SetScript("OnClick", function() Core.Check() end)
  local b2 = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  b2:SetSize(170, 22); b2:SetPoint("BOTTOMRIGHT", -16, 14); b2:SetText("Bring back skipped recipes")
  b2:SetScript("OnClick", function() Core.ClearSkips(); Core.Changed() end)
end

function Options.Toggle()
  if not panel then build() end
  if panel:IsShown() then panel:Hide() else panel:Show() end
end

function Options.IsShown() return panel and panel:IsShown() end

-- create the minimap button once the saved settings are loaded
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() Options.CreateMinimapButton() end)
