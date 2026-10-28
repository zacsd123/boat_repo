--!strict
-- 배의 자리와 배다리, 무게와 높이, 빨간 띠와 젖은 자국.
-- 숨은 한계는 배 값(BoatRules.Boat) 안에만 있고, 그 값은 이 모듈 밖으로 나가지 않는다(S09).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local BoatRules = require(ReplicatedStorage.Shared.Rules.BoatRules)

local BoatService = {}

local boatModel: Model
local root: BasePart
local gangway: BasePart
local dockEnd: Attachment -- 선착장 머리 끝
local entrance: Attachment -- 갑판 입구(Root에 붙어 있다)
local deckZone: BasePart
local dockHead: BasePart
local cargo: Instance -- 실린 상자 모형이 모두 여기 있다
local redBand: { BasePart } = {}
local wetMark: { BasePart } = {}
local berth: CFrame -- 선착장 옆자리. 맵에 놓인 Root의 자리(빈 배)
local away: CFrame -- 바다 쪽 대기 자리. Map.Sea.BoatAway
local rootAboveWater = 0 -- 빈 배일 때 Root가 수면보다 높은 만큼
local docked = false
local moving: Tween? = nil

local round: BoatRules.Boat? = nil -- 이번 라운드의 배. 숨은 한계가 들어 있다

-- 배다리의 윗면이 선착장 머리 끝과 갑판 입구를 잇도록 다시 놓는다
local function fitGangway()
	if not docked then
		return
	end
	local a = dockEnd.WorldPosition
	local b = entrance.WorldPosition
	local mid = (a + b) / 2
	gangway.Size = Vector3.new(gangway.Size.X, gangway.Size.Y, (b - a).Magnitude)
	gangway.CFrame = CFrame.lookAt(mid, b) * CFrame.new(0, -gangway.Size.Y / 2, 0)
end

-- 배가 선착장에 붙어 있을 때만 배다리가 보이고 밟힌다
local function setDocked(value: boolean)
	docked = value
	gangway.Transparency = if value then 0 else 1
	gangway.CanCollide = value
	fitGangway()
end

-- Root를 target으로 옮긴다. 옮기는 중에 또 부르면 목표만 바꾸고 이어서 간다
local function moveRoot(target: CFrame, duration: number, onDone: (() -> ())?)
	if moving then
		moving:Cancel()
	end
	local tween = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), { CFrame = target })
	moving = tween
	tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and onDone then
			onDone()
		end
	end)
	tween:Play()
end

-- Root에 용접된 파트의 높이만 바꾼다. 아랫면과 윗면을 Root 기준 높이로 준다
local function setSpan(parts: { BasePart }, bottom: number, top: number)
	local height = top - bottom
	for _, part in parts do
		local weld = part:FindFirstChildOfClass("WeldConstraint")
		if weld then
			weld.Enabled = false
		end
		local offset = root.CFrame:ToObjectSpace(part.CFrame).Position
		part.Transparency = if height > 0 then part:GetAttribute("BaseTransparency") :: number else 1
		-- 높이가 0이면 숨기고 크기는 그대로 둔다(파트 크기는 0이 될 수 없다)
		part.Size = Vector3.new(part.Size.X, if height > 0 then height else part.Size.Y, part.Size.Z)
		if height > 0 then
			part.CFrame = root.CFrame * CFrame.new(offset.X, (bottom + top) / 2, offset.Z)
		end
		if weld then
			weld.Enabled = true
		end
	end
end

-- 무게 w일 때 배가 내려간 깊이. 위 끝에서 갑판 턱이 수면에 닿는다(BT-3)
local function depthAt(w: number, hi: number): number
	return Config.HULL_FREEBOARD * w / hi
end

-- 빨간 띠: 갑판 턱(선체 맨 위)에서 아래로 HULL_FREEBOARD × (1 − lo ÷ hi)
local function drawBand(lo: number, hi: number)
	local lipTop = Config.HULL_FREEBOARD - rootAboveWater
	setSpan(redBand, lipTop - Config.HULL_FREEBOARD * (1 - lo / hi), lipTop)
end

-- 젖은 자국: 빈 배의 물높이에서 최고 무게의 물높이까지(BT-5)
local function drawWetMark(mark: number, hi: number)
	local emptyWater = -rootAboveWater
	setSpan(wetMark, emptyWater, emptyWater + depthAt(mark, hi))
end

-- 지금 무게에 맞는 높이로 옮긴다. 보여 주기일 뿐 판정과 무관하다
local function settleHeight()
	local current = round
	if current == nil or not docked then
		return
	end
	local target = berth * CFrame.new(0, -depthAt(current.weight, current.hi), 0)
	moveRoot(target, Config.BOAT_MOVE_TIME)
end

local function publish()
	local current = round
	if current == nil then
		return
	end
	boatModel:SetAttribute("Weight", current.weight)
	boatModel:SetAttribute("MarkWeight", current.mark)
	drawWetMark(current.mark, current.hi)
end

-- 갑판에 놓인 상자 무게의 합을 처음부터 다시 더한다(BT-2). 손에 든 상자와 캐릭터는 들어가지 않는다
function BoatService.deckWeight(): number
	local total = 0
	for _, crate in cargo:GetChildren() do
		local kind = crate:GetAttribute("Kind") :: string?
		if kind then
			total += Config.CRATE_SCORE[kind] or 0
		end
	end
	return total
end

-- Loading에 들어갈 때. P로 범위를 정하고 무게와 젖은 자국을 0으로
function BoatService.startRound(p: number)
	local lo, hi = Config.limitRange(p)
	round = BoatRules.newBoat(lo, hi, hi) -- 숨은 한계는 S09에서 뽑는다
	boatModel:SetAttribute("RangeLo", lo)
	boatModel:SetAttribute("RangeHi", hi)
	drawBand(lo, hi)
	publish()
	settleHeight()
end

-- 상자가 갑판에 놓인 직후. 다시 더한 무게로 BoatRules의 "놓였다"를 부르고 그 결과를 돌려준다
function BoatService.onPlaced(): BoatRules.PlaceResult?
	local current = round
	if current == nil then
		return nil
	end
	local result = BoatRules.placed(current, BoatService.deckWeight())
	publish()
	settleHeight()
	return result
end

-- 상자가 갑판에서 빠진 직후. 무게만 고친다
function BoatService.onRemoved()
	local current = round
	if current == nil then
		return
	end
	BoatRules.removed(current, BoatService.deckWeight())
	publish()
	settleHeight()
end

-- 바다 쪽 대기 자리로 바로 옮긴다
function BoatService.setAway()
	if moving then
		moving:Cancel()
	end
	setDocked(false)
	root.CFrame = away
end

-- 바다 쪽에서 선착장 옆자리로 들어온다. 다 오면 배다리가 붙는다
function BoatService.sailIn(duration: number)
	setDocked(false)
	round = nil
	boatModel:SetAttribute("Weight", 0)
	boatModel:SetAttribute("MarkWeight", 0)
	drawWetMark(0, 1)
	root.CFrame = away
	moveRoot(berth, duration, function()
		setDocked(true)
	end)
end

-- 배다리를 떼고 바다 쪽으로 나간다
function BoatService.sailOut(duration: number)
	setDocked(false)
	moveRoot(away, duration)
end

-- 점이 갑판 구역 안인지(GP-11)
function BoatService.isOnDeck(point: Vector3): boolean
	local localPoint = deckZone.CFrame:PointToObjectSpace(point)
	local half = deckZone.Size / 2
	return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z
end

-- 선착장 머리 윗면 가운데. 출항 때 갑판 위 사람을 내려 주는 자리(GP-6)
function BoatService.dockHeadTop(): CFrame
	return dockHead.CFrame * CFrame.new(0, dockHead.Size.Y / 2, 0)
end

function BoatService.start()
	local map = workspace:WaitForChild("Map")
	boatModel = map:WaitForChild("Boat") :: Model
	root = boatModel:WaitForChild("Root") :: BasePart
	cargo = boatModel:WaitForChild("Cargo")
	gangway = map:WaitForChild("Gangway") :: BasePart
	dockHead = map:WaitForChild("Dock"):WaitForChild("Head") :: BasePart
	dockEnd = dockHead:WaitForChild("GangwayEnd") :: Attachment
	-- 입구는 고정된 Root에 붙어 있어서 Root를 옮기는 즉시 새 자리를 읽을 수 있다
	entrance = root:WaitForChild("Entrance") :: Attachment
	deckZone = map:WaitForChild("Zones"):WaitForChild("DeckZone") :: BasePart
	local marks = boatModel:WaitForChild("HullMarks")
	for _, part in marks:WaitForChild("RedBand"):GetChildren() do
		part:SetAttribute("BaseTransparency", (part :: BasePart).Transparency)
		table.insert(redBand, part :: BasePart)
	end
	for _, part in marks:WaitForChild("WetMark"):GetChildren() do
		part:SetAttribute("BaseTransparency", (part :: BasePart).Transparency)
		table.insert(wetMark, part :: BasePart)
	end
	berth = root.CFrame
	away = (map:WaitForChild("Sea"):WaitForChild("BoatAway") :: BasePart).CFrame
	local surface = map:WaitForChild("Sea"):WaitForChild("Surface") :: BasePart
	rootAboveWater = berth.Position.Y - (surface.Position.Y + surface.Size.Y / 2)

	root:GetPropertyChangedSignal("CFrame"):Connect(fitGangway)
	BoatService.setAway()
end

return BoatService
