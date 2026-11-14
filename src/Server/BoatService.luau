--!strict
-- 배의 자리와 배다리, 무게와 높이, 빨간 띠와 젖은 자국.
-- 숨은 한계는 배 값(BoatRules.Boat) 안에만 있고, 그 값은 이 모듈 밖으로 나가지 않는다(S09).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local BoatRules = require(ReplicatedStorage.Shared.Rules.BoatRules)
local DevTools = require(script.Parent.DevTools)

local random = Random.new()

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
local docked = false -- 배가 선착장 옆자리에 있다. 무게를 따라 높이가 바뀌는 것은 이때뿐이다
local gangwayShown = false -- 배다리가 보이고 밟힌다
local retract = 0 -- 배다리가 걷힌 정도. 0은 다 펴짐, 1은 다 걷힘
local retractFrom: Vector3? = nil -- 걷히기 시작할 때 갑판 입구가 있던 자리
local retracting: RBXScriptConnection? = nil
local moving: Tween? = nil

local round: BoatRules.Boat? = nil -- 이번 라운드의 배. 숨은 한계가 들어 있다
-- 이번 배가 비었을 때 수면에서 갑판 턱까지의 높이(S28). 보통 배는 HULL_FREEBOARD이고,
-- 작은 배와 큰 배는 범위의 위 끝에 비례한다. 그래야 무게 1당 가라앉는 깊이가 세 배에서 같다
local freeboard = Config.HULL_FREEBOARD

-- 이 배의 크기와 인원에 맞는 높이를 정한다
local function setFreeboard(shipSize: string?, p: number)
	local _, hi = Config.limitRange(p, shipSize)
	local _, normalHi = Config.limitRange(p)
	freeboard = Config.HULL_FREEBOARD * hi / normalHi
end

-- 이 배가 비었을 때 Root의 자리. 맵에 놓인 자리(보통 배)에서 높이만 다르다
local function shipBerth(): CFrame
	return berth * CFrame.new(0, freeboard - Config.HULL_FREEBOARD, 0)
end

-- 배다리의 윗면이 선착장 머리 끝과 갑판 입구를 잇도록 다시 놓는다.
-- 걷히는 중에는 선착장 쪽 끝이 그대로이고, 배 쪽 끝이 선착장 쪽으로 다가온다
local function fitGangway()
	if not gangwayShown then
		return
	end
	local a = dockEnd.WorldPosition
	local b = retractFrom or entrance.WorldPosition
	local tip = a:Lerp(b, 1 - retract)
	local length = (tip - a).Magnitude
	if length <= 0 then
		return
	end
	gangway.Size = Vector3.new(gangway.Size.X, gangway.Size.Y, length)
	gangway.CFrame = CFrame.lookAt((a + tip) / 2, tip) * CFrame.new(0, -gangway.Size.Y / 2, 0)
end

-- 걷히는 중이던 것을 멈추고 다 펴진 상태로 되돌린다
local function stopRetract()
	if retracting then
		retracting:Disconnect()
		retracting = nil
	end
	retractFrom = nil
	retract = 0
end

local function showGangway(value: boolean)
	gangwayShown = value
	gangway.Transparency = if value then 0 else 1
	gangway.CanCollide = value
	fitGangway()
end

-- 배가 선착장에 붙어 있을 때만 배다리가 보이고 밟힌다
local function setDocked(value: boolean)
	docked = value
	stopRetract()
	showGangway(value)
end

-- Root를 target으로 옮긴다. 옮기는 중에 또 부르면 목표만 바꾸고 이어서 간다
local function moveRoot(
	target: CFrame,
	duration: number,
	onDone: (() -> ())?,
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
)
	if moving then
		moving:Cancel()
	end
	local info = TweenInfo.new(duration, style or Enum.EasingStyle.Linear, direction or Enum.EasingDirection.Out)
	local tween = TweenService:Create(root, info, { CFrame = target })
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
	return freeboard * w / hi
end

-- 빨간 띠: 갑판 턱(선체 맨 위)에서 아래로 (비었을 때의 높이) × (1 − lo ÷ hi). 세 크기에서 높이가 같다(S28)
local function drawBand(lo: number, hi: number)
	local lipTop = Config.HULL_FREEBOARD - rootAboveWater -- Root에서 갑판 턱까지. 선체의 모양이라 크기와 무관하다
	setSpan(redBand, lipTop - freeboard * (1 - lo / hi), lipTop)
end

-- 젖은 자국: 빈 배의 물높이에서 최고 무게의 물높이까지(BT-5)
local function drawWetMark(mark: number, hi: number)
	local emptyWater = -(rootAboveWater + freeboard - Config.HULL_FREEBOARD)
	setSpan(wetMark, emptyWater, emptyWater + depthAt(mark, hi))
end

-- 지금 무게에 맞는 높이로 옮긴다. 보여 주기일 뿐 판정과 무관하다
local function settleHeight()
	local current = round
	if current == nil or not docked then
		return
	end
	local target = shipBerth() * CFrame.new(0, -depthAt(current.weight, current.hi), 0)
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

-- 숨은 한계: lo 이상 hi 이하의 정수 하나를 고르게(BT-1)
function BoatService.drawLimit(lo: number, hi: number): number
	return random:NextInteger(lo, hi)
end

-- Loading에 들어갈 때. P와 배 크기로 범위를 정하고 숨은 한계를 뽑고, 무게와 젖은 자국을 0으로.
-- 한계는 이 모듈의 지역 변수(round)에만 있다. 속성, 값 객체, 원격 이벤트에 두지 않는다
function BoatService.startRound(p: number, shipSize: string?)
	setFreeboard(shipSize, p) -- 들어올 때는 어림한 인원으로 그렸다. 센 인원으로 다시 맞춘다
	local lo, hi = Config.limitRange(p, shipSize)
	local limit = DevTools.forcedLimit() or BoatService.drawLimit(lo, hi)
	if DevTools.shouldPrintLimit() then
		print(`숨은 한계 {limit} (범위 {lo}~{hi}, P={p})`)
	end
	round = BoatRules.newBoat(lo, hi, limit)
	boatModel:SetAttribute("RangeLo", lo)
	boatModel:SetAttribute("RangeHi", hi)
	drawBand(lo, hi)
	publish()
	settleHeight()
end

-- 이번 라운드의 숨은 한계. 서버 안의 기록(Telemetry)에만 넘긴다. 속성이나 원격 이벤트에 싣지 않는다
function BoatService.roundLimit(): number?
	local current = round
	return current and current.limit
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

-- 셋째 종에 떠났다. 이 뒤에 온 놓기는 BoatRules가 "없던 일"로 돌려준다(BL-4).
-- 단계 확인(Tap 처리 순서 1번)이 먼저 버리지만, 판정 모듈에도 끝난 배로 적어 둔다
function BoatService.depart()
	local current = round
	if current ~= nil then
		BoatRules.departed(current)
	end
end

-- 바다 쪽 대기 자리로 바로 옮긴다
function BoatService.setAway()
	if moving then
		moving:Cancel()
	end
	setDocked(false)
	root.CFrame = away
end

-- 바다 쪽에서 선착장 옆자리로 들어온다. 다 오면 배다리가 붙는다.
-- 배의 크기는 이때 선체와 빨간 띠의 높이로 드러난다(VR-2). p는 어림한 인원이다(P는 Loading에서 센다)
function BoatService.sailIn(duration: number, shipSize: string?, p: number)
	setDocked(false)
	round = nil
	setFreeboard(shipSize, p)
	local lo, hi = Config.limitRange(p, shipSize)
	boatModel:SetAttribute("Weight", 0)
	boatModel:SetAttribute("MarkWeight", 0)
	boatModel:SetAttribute("RangeLo", lo)
	boatModel:SetAttribute("RangeHi", hi)
	drawBand(lo, hi)
	drawWetMark(0, 1)
	root.CFrame = away * CFrame.new(0, freeboard - Config.HULL_FREEBOARD, 0)
	moveRoot(shipBerth(), duration, function()
		setDocked(true)
	end)
end

-- 셋째 종 뒤. 배다리가 먼저 천천히 걷히고, 다 걷히면 배가 바다 쪽으로 떠난다.
-- 둘을 합쳐 duration(SETTLE_SHOW_TIME) 안에 끝난다. 보여 주기일 뿐 판정과 무관하다
-- (단계는 셋째 종에서 이미 Departing이고, 그동안 놓기는 받지 않는다)
function BoatService.sailOut(duration: number)
	docked = false -- 무게를 따라 높이가 바뀌는 것은 여기까지
	stopRetract()
	-- 배다리는 선착장에 붙은 채 걷힌다. 배가 움직여도 끝이 배를 따라가 늘어나지 않는다
	retractFrom = entrance.WorldPosition
	local startedAt = os.clock()
	retracting = RunService.Heartbeat:Connect(function()
		local progress = math.min((os.clock() - startedAt) / Config.GANGWAY_RETRACT_TIME, 1)
		if progress < 1 then
			retract = TweenService:GetValue(progress, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			fitGangway()
			return
		end
		stopRetract()
		showGangway(false)
		moveRoot(
			away,
			duration - Config.GANGWAY_RETRACT_TIME,
			nil,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut
		)
	end)
end

-- 침몰 연출: 배다리를 떼고 선체 전체가 수면 아래로 내려간다. 판정과 따로 돈다
function BoatService.sink(duration: number)
	setDocked(false)
	local hull = boatModel:FindFirstChild("Hull") :: BasePart
	moveRoot(shipBerth() * CFrame.new(0, -(freeboard + hull.Size.Y), 0), duration)
end

-- 점이 갑판 구역 안인지(GP-11)
function BoatService.isOnDeck(point: Vector3): boolean
	local localPoint = deckZone.CFrame:PointToObjectSpace(point)
	local half = deckZone.Size / 2
	return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z
end

-- 점이 배다리 위인지. 배가 깊이 잠기면 배다리의 배 쪽 끝이 수면 아래로 내려간다.
-- 그 위를 걷는 사람을 물에 빠진 것으로 치지 않으려고 WaterService가 묻는다(놓기의 "갑판"과는 상관없다, GP-11)
function BoatService.isOnGangway(point: Vector3): boolean
	if not gangwayShown then
		return false
	end
	local localPoint = gangway.CFrame:PointToObjectSpace(point)
	local half = gangway.Size / 2
	-- 윗면 둘레만 본다. 배다리 밑을 헤엄쳐 지나는 사람은 아니다(바다 바닥은 배다리보다 2스터드 넘게 아래다).
	-- 아래로 1스터드의 여유를 둔다: 가파른 배다리를 빠르게 오를 때는 몸이 잠깐 낮게 따라온다
	return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Z) <= half.Z + 0.5
		and localPoint.Y >= -1 and localPoint.Y <= half.Y + 1
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
