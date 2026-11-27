-- A waypoint arrow, so TomTom isn't needed: points to the trainer or vendor you clicked,
-- with the distance, and says "Arrived" when you get there. On another continent it
-- says how to get there instead (boat, zeppelin, flight). Hidden in instances, where
-- the game doesn't give addons your position. Drag to move; right-click to clear.
local _, ns = ...
local Core = ns.Core
local Arrow = {}
ns.Arrow = Arrow

local ARRIVED = 8     -- yards
local INTERVAL = 0.05 -- seconds between updates

local frame, target
local acc = 0

-- World position (yards, continent) of a map point: the game's own conversion.
local function worldOf(ui, x, y)
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D and ui and x) then return nil end
  local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, ui, CreateVector2D(x, y))
  if not ok or not cont or not pos then return nil end
  local wx, wy = pos.x, pos.y
  if pos.GetXY then wx, wy = pos:GetXY() end
  return cont, wx, wy
end
Arrow._worldOf = worldOf

-- Your map and world position, or nil (instances, loading).
local function playerWorld()
  local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local pos = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
  if not pos then return nil end
  local x, y = pos.x, pos.y
  if pos.GetXY then x, y = pos:GetXY() end
  local cont, wx, wy = worldOf(map, x, y)
  return cont, wx, wy, map
end

-- Which way east and south run in world coordinates, worked out from a map's corners
-- (so the arrow doesn't depend on how the game orders its world axes). Per map, cached.
local basis = {}
local function axes(map)
  local b = basis[map]
  if b then return b end
  local c0, a0, b0 = worldOf(map, 0, 0)
  local c1, a1, b1 = worldOf(map, 1, 0) -- map right = east
  local c2, a2, b2 = worldOf(map, 0, 1) -- map down = south
  if not (c0 and c1 and c2) then return nil end
  local ea, eb, sa, sb = a1 - a0, b1 - b0, a2 - a0, b2 - b0
  local el, sl = math.sqrt(ea * ea + eb * eb), math.sqrt(sa * sa + sb * sb)
  if el == 0 or sl == 0 then return nil end
  b = { ea / el, eb / el, sa / sl, sb / sl }
  basis[map] = b
  return b
end
Arrow._axes = axes

-- Direction and distance from you to the target: the angle to turn the arrow (radians,
-- counter-clockwise from straight ahead; facing 0 = north, counter-clockwise) and
-- yards. nil if it can't point (another continent, no facing).
function Arrow.Bearing(pc, pa, pb, facing, tc, ta, tb, ax)
  if not (pc and tc and pc == tc and facing and ax) then return nil end
  local da, db = ta - pa, tb - pb
  local east = da * ax[1] + db * ax[2]
  local south = da * ax[3] + db * ax[4]
  local dist = math.sqrt(da * da + db * db)
  return math.atan2(-east, -south) - facing, dist -- atan2(west, north)
end

local function build()
  frame = CreateFrame("Button", "SkillRouteArrow", UIParent)
  frame:SetSize(120, 92)
  frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
  frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
  frame:RegisterForClicks("RightButtonUp")
  frame:SetClampedToScreen(true)
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local x, y = self:GetCenter()
    if x and y then SkillRouteDB.settings = SkillRouteDB.settings or {}; SkillRouteDB.settings.arrowPos = { math.floor(x), math.floor(y) } end
  end)
  frame:SetScript("OnClick", function(_, button) if button == "RightButton" then Arrow.Clear() end end)
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("SkillRoute waypoint")
    if target then GameTooltip:AddLine(target.title .. (target.where and (", " .. target.where) or ""), 1, 1, 1, true) end
    GameTooltip:AddLine("Drag to move. Right-click to clear.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
  frame.arrow = frame:CreateTexture(nil, "ARTWORK")
  frame.arrow:SetSize(44, 44)
  frame.arrow:SetPoint("TOP", 0, 0)
  frame.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.title:SetPoint("TOP", frame.arrow, "BOTTOM", 0, -2)
  frame.dist = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.dist:SetPoint("TOP", frame.title, "BOTTOM", 0, -1)
  frame.route = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.route:SetPoint("TOP", frame.dist, "BOTTOM", 0, -1)
  frame.route:SetWidth(260)
  frame:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < INTERVAL then return end
    acc = 0
    Arrow.Update()
  end)
  frame:Hide()
end

local function place()
  local p = SkillRouteDB.settings and SkillRouteDB.settings.arrowPos
  frame:ClearAllPoints()
  if p then frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p[1], p[2])
  else frame:SetPoint("TOP", UIParent, "TOP", 0, -140) end
end

function Arrow.Update()
  if not (frame and target) then return end
  local pc, px, py, map = playerWorld()
  local facing = GetPlayerFacing and GetPlayerFacing()
  local ax = map and axes(map)
  -- always the same lines: name, then where it is from you, then the fastest way there
  frame.route:SetText(target.route)
  if not pc or not facing or not ax then -- an instance, or loading
    frame.arrow:Hide()
    frame.dist:SetText("|cff999999No position here (dungeon or loading)|r")
    return
  end
  local angle, dist = Arrow.Bearing(pc, px, py, facing, target.cont, target.x, target.y, ax)
  if not angle then -- another continent: the route line says how
    frame.arrow:Hide()
    frame.dist:SetText("|cffffd100On another continent|r")
    return
  end
  if dist <= ARRIVED then
    frame.arrow:Hide()
    frame.dist:SetText("|cff40bf40Arrived|r")
    if not target.arrivedAt then
      target.arrivedAt = GetTime()
      C_Timer.After(3, function() if target and target.arrivedAt then Arrow.Clear() end end)
    end
    return
  end
  target.arrivedAt = nil
  frame.arrow:Show()
  frame.arrow:SetRotation(angle)
  -- green when roughly ahead, yellow off to the side, red behind
  local off = math.abs((angle + math.pi) % (2 * math.pi) - math.pi)
  if off < 0.35 then frame.arrow:SetVertexColor(0.3, 1, 0.3)
  elseif off < 1.6 then frame.arrow:SetVertexColor(1, 0.85, 0.2)
  else frame.arrow:SetVertexColor(1, 0.35, 0.3) end
  frame.dist:SetText(("%d yd"):format(math.floor(dist + 0.5)))
end

-- Point at a place: ui map + x, y (0-1). Returns false if it can't (no world position).
function Arrow.Set(ui, x, y, title, where, via)
  local cont, wx, wy = worldOf(ui, x, y)
  if not cont then return false end
  if not frame then build() end
  target = { cont = cont, x = wx, y = wy, title = title or "Waypoint", where = where, via = via }
  -- the route line, the same wording every time
  local here = playerWorld()
  if via then target.route = "|cff999999Fastest:|r " .. via:gsub("^via ", "")
  elseif here and here ~= cont then target.route = "|cff999999No known route yet: open a flight master's map, or take a boat or zeppelin|r"
  else target.route = "|cff999999Fastest:|r walk" end
  frame.title:SetText(target.title)
  place()
  frame:Show()
  Arrow.Update()
  return true
end

function Arrow.Clear()
  target = nil
  if frame then frame:Hide() end
end

function Arrow.Target() return target end
