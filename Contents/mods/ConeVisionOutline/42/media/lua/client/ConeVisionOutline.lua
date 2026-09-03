-- Outline for zombies and animals in vision cone when aiming RMB.
-- Melee hit-list targets are outlined green. The original approach (from Aim Outline by
-- Kreb, Workshop ID 3404684285) read the hit list through Lua reflection, but the game
-- blocks getClassField* outside of -debug, so that never worked for normal players. See
-- isRepaintedByEngine() below for how the hit list is identified now.
-- Overlay (optional, see Mod Options): when engine does not draw outline (e.g. floor above on stairs), we draw outline in 2D on top.
require "Foraging/forageSystem"

local O
pcall(function() O = require("ConeVisionOutline_Options") end)
local function getConeOutlineColor()
	if O and O.ConeOutlineColor then
		local c = O.ConeOutlineColor
		local a = (O.ConeOutlineAlpha ~= nil) and O.ConeOutlineAlpha or 0.3
		return c.r or 1, c.g or 1, c.b or 1, a
	end
	return 1, 1, 1, 0.3
end

-- PZ exposes fog as one number for the whole world (ClimateManager.getFogIntensity(),
-- roughly -1..1 per the game's own Climate debug panel, same family as getNightStrength/
-- getPrecipitationIntensity) rather than per square -- there is no "how fogged is this
-- specific tile" query. Clamped to 0..1: a negative reading means "no fog", never treated
-- as extra visibility. Called once per frame, not per object -- it is one Java call for
-- the whole tick, same cost regardless of how many zombies are on screen.
local function getWorldFogIntensity()
	local ok, clim = pcall(getClimateManager)
	if not ok or not clim then return 0 end
	local ok2, v = pcall(function() return clim:getFogIntensity() end)
	if not ok2 or type(v) ~= "number" then return 0 end
	if v < 0 then return 0 end
	if v > 1 then return 1 end
	return v
end

-- The radius of full clarity around the player, before the fade to fog, is not a guess
-- either: ClimateManager.getViewDistance() -- confirmed by reading updateViewDistance(),
-- which computes it from dayLightStrength AND fogIntensity together and feeds the result
-- into GameTime.setViewDistMin/Max. GameTime.getViewDist() (the distance TestIfSeen checks
-- -- the same check behind the new default visibility mode) forwards to this exact value.
-- So dusk shrinks this radius too, same as fog does; it is "how far you can currently see"
-- in general, not fog-only. Falls back to RADIUS_VISION if the call is ever unavailable.
local function getWorldViewDistance()
	local ok, clim = pcall(getClimateManager)
	if not ok or not clim then return nil end
	local ok2, v = pcall(function() return clim:getViewDistance() end)
	if not ok2 or type(v) ~= "number" or v <= 0 then return nil end
	return v
end

-- Errors inside the per-frame pcall used to be swallowed silently, which made an engine API
-- change look like "mod loads, does nothing". Report each distinct error once to console.txt.
local reportedErrors = {}
local function reportError(err)
	local msg = tostring(err)
	if reportedErrors[msg] then return end
	reportedErrors[msg] = true
	print("[ConeVisionOutline] ERROR: " .. msg)
end

local lastHighlighted = {}
-- obj -> packed outline colour this mod wrote on the previous frame. Used to detect when
-- the engine has repainted an object, which is how the melee hit list is identified now.
local lastWrittenCol = {}
local lastOverlayTargets = {}  -- objects on adjacent floor that engine won't outline; we draw them ourselves
local overlayUI = nil
local overlayInUIManager = false  -- true when overlay is currently in UI (so we remove it when not aiming)
local RADIUS_VISION = 50
local RADIUS_OVERLAY_FLOOR_ABOVE = 5  -- max horizontal distance (tiles) for overlay on floor +1
local PLAYER_NUM = 0
local OUTLINE_ALPHA = 0.3
local OVERLAY_BOX_W = 28
local OVERLAY_BOX_H = 56
local OVERLAY_CIRCLE_SIZE = 44       -- base diameter for pulse circle
local PULSE_SCALE_MIN = 0.82
local PULSE_SCALE_MAX = 1.18
local PULSE_SPEED = 0.5              -- cycles per second (growl-like)
local PULSE_ALPHA_MIN = 0.2
local PULSE_ALPHA_MAX = 0.45
local overlayCircleTex = nil         -- lazy-loaded texture
-- Vision cone for overlay: only show overlay for targets in front of player (dot product threshold ~cos(60°) = 0.5)
local CONE_HALF_ANGLE_COS = 0.5
-- Direction vectors (dx, dy) for IsoDirections; built at runtime when IsoDirections is available
local DIR_VECTORS = nil
local function buildDirVectors()
	if DIR_VECTORS then return end
	if not IsoDirections then return end
	DIR_VECTORS = {
		[IsoDirections.N] = { 0, -1 }, [IsoDirections.S] = { 0, 1 },
		[IsoDirections.E] = { 1, 0 },  [IsoDirections.W] = { -1, 0 },
		[IsoDirections.NE] = { 0.707, -0.707 }, [IsoDirections.SE] = { 0.707, 0.707 },
		[IsoDirections.NW] = { -0.707, -0.707 }, [IsoDirections.SW] = { -0.707, 0.707 },
	}
end

local function clearOutline(obj)
	-- Single call in pcall: avoid any other method on obj (stale refs can make them throw).
	local ok = pcall(function()
		obj:setOutlineHighlight(PLAYER_NUM, false)
	end)
	return ok
end

local function clearAll()
	for obj, _ in pairs(lastHighlighted) do
		clearOutline(obj)
	end
	lastHighlighted = {}
	lastWrittenCol = {}
	lastOverlayTargets = {}
end

local function readOutlineCol(obj)
	local ok, v = pcall(function()
		return obj:getOutlineHighlightCol(PLAYER_NUM)
	end)
	if ok then return v end
	return nil
end

-- Hit-list detection without reflection.
--
-- HitInfo is not in the Lua exposer and the getClassField* functions throw outside of
-- -debug, so the old reflection walk could never work for normal players. Instead we let
-- the engine tell us: CombatManager.highlightTargets repaints the real melee hit list
-- every frame while aiming with "Melee outline" on, and it runs before this Lua event.
-- So if an object's colour is no longer the one we wrote last frame, the engine claimed
-- it, which means it is in the hit list. Colour-agnostic on purpose: it does not matter
-- whether the engine used the 'Bad' highlight colour or the debug cyan.
local function isRepaintedByEngine(obj)
	local prev = lastWrittenCol[obj]
	if prev == nil then return false end  -- never painted by us yet, cannot compare
	local cur = readOutlineCol(obj)
	if cur == nil then return false end
	return cur ~= prev
end

-- Green stays reserved for melee, matching the mod's original contract (firearm: no
-- green). The engine's own highlight may or may not cover ranged weapons.
local function isMeleeWeaponEquipped(character)
	local w = character:getPrimaryHandItem()
	return w ~= nil and w:IsWeapon() and not w:isRanged()
end

local function isShortSightedWithoutGlasses(character)
	if not character:hasTrait(CharacterTrait.SHORT_SIGHTED) then
		return false
	end
	return forageSystem.doGlassesCheck(character, nil, "visionBonus")
end

local function isTarget(obj)
	if instanceof(obj, "IsoZombie") then return true end
	if instanceof(obj, "IsoAnimal") then
		-- Default on: only an explicit false from the options turns animals off, so a
		-- missing options module or a fresh install still behaves as it always has.
		return not (O and O.OutlineAnimals == false)
	end
	return false
end

local function getObjSquare(obj)
	if obj.getCurrentSquare then
		return obj:getCurrentSquare()
	end
	if obj.getSquare then
		return obj:getSquare()
	end
	return nil
end

-- True if target at (plX+dx, plY+dy) is in player's vision cone (in front)
local function isInVisionCone(character, dx, dy)
	if not character or not character.getDir then return false end
	buildDirVectors()
	local dir = character:getDir()
	if not dir or not DIR_VECTORS or not DIR_VECTORS[dir] then return false end
	local v = DIR_VECTORS[dir]
	local dot = dx * v[1] + dy * v[2]
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 0.01 then return true end
	return (dot / len) >= CONE_HALF_ANGLE_COS
end

-- Legacy visibility (pre-v1.3 default, still available via the "Legacy outline mode"
-- option): the square's own "can see" flag. Coarser than the engine's per-object verdict
-- below -- it says nothing about this specific object's distance, facing, or light level,
-- which is why isInVisionCone() and the ScaleOutlineByLight option exist to approximate
-- what square:isCanSee() alone does not capture.
local function isVisibleLegacy(character, square)
	return square:isCanSee(character:getPlayerNum())
end

-- Default since v1.3: the engine's own per-object verdict. Found by reading RadVision
-- (Workshop ID 3774647043), a different mod outlining zombies through the same engine
-- outline API. IsoGameCharacter.updateSeenVisibility sets a moving object's targetAlpha to
-- 0 for anything TestIfSeen rejects -- view distance, vision cone relative to the player's
-- actual facing, line of sight, and light level, all folded into the one engine call that
-- decides whether to draw the object at all. Using it means this mod's "visible" cannot
-- drift from vanilla's, unlike isVisibleLegacy()'s reconstruction of the same decision.
local function isVisibleToEngine(obj, playerNum)
	return not obj:isTargetAlphaZero(playerNum)
end

-- Probed once against the player object itself (isTargetAlphaZero lives on IsoObject, so
-- IsoPlayer has it too) instead of trusting it per zombie per frame. If a future build
-- ever drops the method, this falls back to legacy mode instead of throwing on every
-- object of every frame -- the same mistake IsoCell.getObjectList() taught us to avoid.
local engineVisibilityOk = nil
local function engineVisibilitySupported(character)
	if engineVisibilityOk == nil then
		engineVisibilityOk = pcall(function() return character:isTargetAlphaZero(0) end)
		if not engineVisibilityOk then
			reportError("isTargetAlphaZero unavailable; using legacy outline mode")
		end
	end
	return engineVisibilityOk
end

-- Overlay UI: draws pulsing circle (growl-style) for targets on floor+1 that the engine does not draw
local ConeVisionOutlineOverlay = ISUIElement:derive("ConeVisionOutlineOverlay")
local function getOverlayCircleTexture()
	if overlayCircleTex then return overlayCircleTex end
	local ok, t = pcall(function() return getTexture("media/ui/circle.png") end)
	if ok and t then overlayCircleTex = t end
	return overlayCircleTex
end
function ConeVisionOutlineOverlay:prerender() end
function ConeVisionOutlineOverlay:render()
	-- Let mouse events pass through so RMB (aim) still works
	if not self._mousePassThrough and self.javaObject then
		pcall(function() self.javaObject:setConsumeMouseEvents(false) end)
		self._mousePassThrough = true
	end
	if not lastOverlayTargets then return end
	local hasAny = false
	for _ in pairs(lastOverlayTargets) do hasAny = true; break end
	if not hasAny then return end
	local tex = getOverlayCircleTexture()
	if not tex then return end
	local character = getPlayer()
	if not character then return end
	local pid = character:getPlayerNum()
	local screenLeft = getPlayerScreenLeft(pid)
	local screenTop = getPlayerScreenTop(pid)
	local t = (getTimestampMs() or 0) / 1000
	local twoPi = 2 * math.pi
	local pulseScale = PULSE_SCALE_MIN + (PULSE_SCALE_MAX - PULSE_SCALE_MIN) * (0.5 + 0.5 * math.sin(t * PULSE_SPEED * twoPi))
	local pulseAlpha = PULSE_ALPHA_MIN + (PULSE_ALPHA_MAX - PULSE_ALPHA_MIN) * (0.5 + 0.5 * math.sin(t * PULSE_SPEED * twoPi * 1.1))
	local size = OVERLAY_CIRCLE_SIZE * pulseScale
	local r, g, b = 1, 1, 1
	for obj, _ in pairs(lastOverlayTargets) do
		local ok, cx, cy = pcall(function()
			local square = getObjSquare(obj)
			if not square then return nil, nil end
			local x, y = obj:getX(), obj:getY()
			local z = square:getZ()
			local scrX = isoToScreenX(pid, x, y, z) - screenLeft
			local scrY = isoToScreenY(pid, x, y, z) - screenTop
			return scrX - OVERLAY_BOX_W / 2 + OVERLAY_BOX_W / 2, scrY - OVERLAY_BOX_H + OVERLAY_BOX_H / 2
		end)
		if ok and cx and cy then
			self:drawTextureScaled(tex, cx - size / 2, cy - size / 2, size, size, pulseAlpha, r, g, b)
		end
	end
end
function ConeVisionOutlineOverlay:new()
	local pid = getPlayer() and getPlayer():getPlayerNum() or 0
	local x = getPlayerScreenLeft(pid)
	local y = getPlayerScreenTop(pid)
	local w = getPlayerScreenWidth(pid)
	local h = getPlayerScreenHeight(pid)
	local o = ISUIElement.new(self, x, y, w, h)
	o:setCapture(false)
	return o
end
local function ensureOverlayUI()
	if overlayUI then return end
	if not ISUIElement or type(ISUIElement.derive) ~= "function" then return end
	if not getPlayerScreenLeft or not getPlayerScreenWidth then return end
	overlayUI = ConeVisionOutlineOverlay:new()
	if not overlayUI then return end
	if overlayUI.initialise then overlayUI:initialise() end
	if overlayUI.addToUIManager then overlayUI:addToUIManager() end
	overlayInUIManager = true
	-- So overlay never blocks RMB (aim) or other mouse
	pcall(function()
		if overlayUI.setX then overlayUI:setX(0) end
		if overlayUI.javaObject and overlayUI.javaObject.setConsumeMouseEvents then
			overlayUI.javaObject:setConsumeMouseEvents(false)
		end
	end)
end
local function updateOverlayBounds()
	if not overlayUI then return end
	local character = getPlayer()
	if not character then return end
	local pid = character:getPlayerNum()
	if getPlayerScreenLeft and overlayUI.setX then overlayUI:setX(getPlayerScreenLeft(pid)) end
	if getPlayerScreenTop and overlayUI.setY then overlayUI:setY(getPlayerScreenTop(pid)) end
	if getPlayerScreenWidth and overlayUI.setWidth then overlayUI:setWidth(getPlayerScreenWidth(pid)) end
	if getPlayerScreenHeight and overlayUI.setHeight then overlayUI:setHeight(getPlayerScreenHeight(pid)) end
end

local function updateConeOutline()
	local ok, err = pcall(function()
		-- Same as game: getPlayer() for current/controlled character (works in vehicle)
		local character = getPlayer()
		if not character then
			clearAll()
			return
		end

		-- On foot = isAiming(); in vehicle = isLookingWhileInVehicle() or (option) always when in vehicle.
		-- OutlineAlwaysOn (default off) bypasses all of that: outline is on regardless of
		-- aiming or vehicle state. VehicleOutlineAlwaysOn still works on its own for anyone
		-- who only wants that narrower behavior; having both on is harmless, just redundant.
		local inVehicle = character:getVehicle() ~= nil
		local isLooking = (O and O.OutlineAlwaysOn) or character:isAiming() or character:isLookingWhileInVehicle()
			or (O and O.VehicleOutlineAlwaysOn and inVehicle)
		if not isLooking then
			lastOverlayTargets = {}
			if overlayInUIManager and overlayUI and overlayUI.removeFromUIManager then
				pcall(function() overlayUI:setVisible(false); overlayUI:removeFromUIManager() end)
				overlayInUIManager = false
			end
			clearAll()
			return
		end

		-- Everything (cone + hit-list outline) only when game option "Melee outline" is on
		if not getCore():getOptionMeleeOutline() then
			lastOverlayTargets = {}
			clearAll()
			return
		end

		if isShortSightedWithoutGlasses(character) then
			lastOverlayTargets = {}
			clearAll()
			return
		end

		local meleeEquipped = isMeleeWeaponEquipped(character)
		-- Explicit opt-in to legacy mode, or an automatic fallback if the engine signal
		-- ever turns out to be unavailable on this build.
		local useLegacy = (O and O.LegacyOutlineMode) or not engineVisibilitySupported(character)
		-- Not legacy-only: neither visibility function is a stand-in for this. isCanSee
		-- doesn't touch fog at all, and while the new mode's distance cutoff does shrink
		-- with fog (confirmed: it is driven by the same ClimateManager.getViewDistance()
		-- read below), that is a hard "still visible or not", not the continuous fade this
		-- option draws. Both need it, so it fades the same way regardless of mode.
		local fogIntensity = (O and O.ScaleOutlineByFog) and getWorldFogIntensity() or 0
		local fogRampDistance = (fogIntensity > 0) and (getWorldViewDistance() or RADIUS_VISION) or RADIUS_VISION

		local cell = getCell()
		if not cell then return end

		lastOverlayTargets = {}
		local plX, plY = character:getX(), character:getY()
		-- B42.20: IsoCell.getObjectList() returns java.util.Set, which has no :get(i).
		-- Calling :get(i) on it threw every frame and the outer pcall hid it, so the mod
		-- silently did nothing. Vanilla Lua uses getObjectListForLua() (a java.util.List).
		local objectList = cell.getObjectListForLua and cell:getObjectListForLua() or cell:getObjectList()
		if not objectList or not objectList.size or not objectList.get then
			reportError("cell object list is not indexable")
			return
		end
		local newHighlighted = {}
		local newWrittenCol = {}

		for i = 0, objectList:size() - 1 do
			local obj = objectList:get(i)
			if isTarget(obj) then
				local square = getObjSquare(obj)
				if square then
					local dx = obj:getX() - plX
					local dy = obj:getY() - plY
					local distSq = dx * dx + dy * dy

					if distSq <= RADIUS_VISION * RADIUS_VISION then
						local valid = (instanceof(obj, "IsoAnimal") and obj:isExistInTheWorld())
							or (instanceof(obj, "IsoZombie") and not obj:isDead())
						if valid then
							local visible
							if useLegacy then
								visible = isVisibleLegacy(character, square)
							else
								visible = isVisibleToEngine(obj, character:getPlayerNum())
							end
							local plZ = character:getZ()
							local sqZ = square:getZ()
							local floorAboveOnly = (plZ ~= nil and sqZ ~= nil) and (sqZ - plZ < 1) and (sqZ - plZ > 0)
							local inCone = isInVisionCone(character, dx, dy)
							if visible then
								-- Engine draws outline for this Z level (color/alpha from options)
								local cr, cg, cb, ca = getConeOutlineColor()
								-- Scale by the square's light level. GetRLightLevel/G/B read the
								-- plain lightLevel field the engine already maintains -- deliberately
								-- not getLightLevel(int)/getLightLevel2(), which construct a new
								-- native LightingJNI object on every single call and were confirmed
								-- (by isolating the call from its result) to corrupt the outline's
								-- draw-through-geometry rendering on their own.
								--
								-- KNOWN LIMITATION: giving an outlined object a per-object alpha
								-- that differs from the mod's flat default can still, on some
								-- specific scene geometry (thin posts/beams; ordinary walls are
								-- unaffected), make that one outline respect scene depth instead of
								-- drawing through it. Confirmed this is not about which Java call
								-- supplies the value (GetRLightLevel/G/B are plain field reads) and
								-- not about how many distinct values are live at once (quantizing to
								-- a handful of steps did not help either). Whatever decides this
								-- lives in the engine's own outline renderer; narrowing it further
								-- would need instrumenting that renderer, out of reach from Lua.
								if O and O.ScaleOutlineByLight then
									local rl, gl, bl = square:GetRLightLevel(), square:GetGLightLevel(), square:GetBLightLevel()
									if rl ~= nil and gl ~= nil and bl ~= nil then
										local lightLevel = math.max(rl, gl, bl) / 255
										ca = ca * lightLevel
									end
								end
								if fogIntensity > 0 then
									-- No per-square fog value exists, so this approximates the
									-- look of real fog (barely noticeable close up, thicker with
									-- distance) by scaling the single world fog reading with how
									-- far this particular target is, out of the current clear-
									-- visibility radius (see getWorldViewDistance() above).
									local fogFactor = fogIntensity * math.min(math.sqrt(distSq) / fogRampDistance, 1)
									ca = ca * (1 - fogFactor)
								end
								-- Melee hit-list targets stay green, same as before; the set now comes
								-- from the engine's own repaint instead of from reflection.
								if meleeEquipped and isRepaintedByEngine(obj) then
									cr, cg, cb = 0, 1, 0
								end
								obj:setOutlineHighlight(PLAYER_NUM, true)
								obj:setOutlineHighlightCol(PLAYER_NUM, cr, cg, cb, ca)
								-- Read back what actually landed so the next frame compares exactly.
								newWrittenCol[obj] = readOutlineCol(obj)
								newHighlighted[obj] = true
							elseif floorAboveOnly and inCone and (distSq <= RADIUS_OVERLAY_FLOOR_ABOVE * RADIUS_OVERLAY_FLOOR_ABOVE) then
								-- Floor above, in cone, within 5 tiles: we draw overlay (always on)
								lastOverlayTargets[obj] = true
							end
						end
					end
				end
			end
		end

		-- Clear outlines for objects that left vision
		for obj, _ in pairs(lastHighlighted) do
			if not newHighlighted[obj] then
				clearOutline(obj)
			end
		end
		lastHighlighted = newHighlighted
		lastWrittenCol = newWrittenCol

		local hasOverlayTargets = false
		for _ in pairs(lastOverlayTargets) do
			hasOverlayTargets = true
			break
		end
		if hasOverlayTargets then
			ensureOverlayUI()
			updateOverlayBounds()
			if overlayUI and not overlayInUIManager then
				pcall(function()
					if overlayUI.setVisible then overlayUI:setVisible(true) end
					if overlayUI.addToUIManager then overlayUI:addToUIManager() end
					overlayInUIManager = true
				end)
			end
		elseif overlayInUIManager and overlayUI then
			pcall(function() overlayUI:setVisible(false); overlayUI:removeFromUIManager() end)
			overlayInUIManager = false
		end
	end)
	if not ok then reportError(err) end
end

Events.OnPlayerUpdate.Add(updateConeOutline)
Events.OnPlayerDeath.Add(clearAll)
