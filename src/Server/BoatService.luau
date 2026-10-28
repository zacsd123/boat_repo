--!strict
-- 배의 자리와 배다리. 무게와 침몰은 S08, S09에서 더한다.

local TweenService = game:GetService("TweenService")

local BoatService = {}

local root: BasePart
local gangway: BasePart
local dockEnd: Attachment -- 선착장 머리 끝
local entrance: Attachment -- 갑판 입구(Root에 붙어 있다)
local deckZone: BasePart
local dockHead: BasePart
local berth: CFrame -- 선착장 옆자리. 맵에 놓인 Root의 자리
local away: CFrame -- 바다 쪽 대기 자리. Map.Sea.BoatAway
local docked = false
local sailing: Tween? = nil

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

local function sail(target: CFrame, duration: number, onDone: (() -> ())?)
	if sailing then
		sailing:Cancel()
	end
	local tween = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), { CFrame = target })
	sailing = tween
	tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and onDone then
			onDone()
		end
	end)
	tween:Play()
end

-- 바다 쪽 대기 자리로 바로 옮긴다
function BoatService.setAway()
	if sailing then
		sailing:Cancel()
	end
	setDocked(false)
	root.CFrame = away
end

-- 바다 쪽에서 선착장 옆자리로 들어온다. 다 오면 배다리가 붙는다
function BoatService.sailIn(duration: number)
	setDocked(false)
	root.CFrame = away
	sail(berth, duration, function()
		setDocked(true)
	end)
end

-- 배다리를 떼고 바다 쪽으로 나간다
function BoatService.sailOut(duration: number)
	setDocked(false)
	sail(away, duration)
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
	local boat = map:WaitForChild("Boat") :: Model
	root = boat:WaitForChild("Root") :: BasePart
	gangway = map:WaitForChild("Gangway") :: BasePart
	dockHead = map:WaitForChild("Dock"):WaitForChild("Head") :: BasePart
	dockEnd = dockHead:WaitForChild("GangwayEnd") :: Attachment
	-- 입구는 고정된 Root에 붙어 있어서 Root를 옮기는 즉시 새 자리를 읽을 수 있다
	entrance = root:WaitForChild("Entrance") :: Attachment
	deckZone = map:WaitForChild("Zones"):WaitForChild("DeckZone") :: BasePart
	berth = root.CFrame
	away = (map:WaitForChild("Sea"):WaitForChild("BoatAway") :: BasePart).CFrame

	root:GetPropertyChangedSignal("CFrame"):Connect(fitGangway)
	BoatService.setAway()
end

return BoatService
