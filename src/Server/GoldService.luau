--!strict
-- 황금 상자(S22). 라운드에 하나이고, 첫 종과 함께 해변 바위 위에 나타난다(GD-1).
-- 이 모듈이 맡는 것은 "갑판 밖에 놓여 있는 황금 상자" 하나다: 바위 위, 또는 누가 갑판 밖에서 내려놓은 자리(GD-3).
-- 손에 든 것과 갑판에 실린 것은 CrateService가 다른 상자와 똑같이 다룬다(GD-6).
-- 이 모듈의 함수는 기다리지 않는다. 둘이 함께 눌러도 먼저 처리된 Tap이 take로 상자를 가져가면 다음 Tap에는 상자가 없다(CR-10).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local RoundService = require(script.Parent.RoundService)
local BellService = require(script.Parent.BellService)

local Phase = Types.Phase
local Kind = Types.CrateKind

local GoldService = {}

local LOOSE_NAME = "GoldCrate" -- 클라이언트가 이 이름으로 찾는다

local asset: Model -- ServerStorage.Assets.Crates.Gold
local looseFolder: Instance -- Map.Loose
local rock: BasePart -- Map.Beach.Rock
local fx: RemoteEvent

local loose: Model? = nil -- 갑판 밖에 놓여 있는 황금 상자
local appeared = false -- 이번 라운드에 이미 나왔는지

local function clear()
	local model = loose
	loose = nil
	if model then
		model:Destroy()
	end
end

-- 바닥의 한 점 위에 황금 상자를 놓는다. 걸음을 막지 않게 통과시키고, 제자리에 고정한다
local function putOn(floor: Vector3)
	clear()
	local model = asset:Clone()
	local body = model.PrimaryPart :: BasePart
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
		end
	end
	model.Name = LOOSE_NAME
	model:SetAttribute("Kind", Kind.Gold)
	model:PivotTo(CFrame.new(floor + Vector3.new(0, body.Size.Y / 2, 0)))
	model.Parent = looseFolder
	loose = model
end

local function rockTop(): Vector3
	return rock.Position + Vector3.new(0, rock.Size.Y / 2, 0)
end

-- 첫 종이 울리는 순간(GD-1). 띠 때문이든 상한 때문이든 같다
local function appear()
	if appeared or RoundService.getPhase() ~= Phase.Loading then
		return
	end
	appeared = true
	putOn(rockTop())
	fx:FireAllClients("Gold", rockTop())
end

-- 그 자리에서 놓여 있는 황금 상자까지의 바닥 위 거리. 놓여 있는 것이 없으면 nil
function GoldService.distanceFrom(position: Vector3): number?
	local model = loose
	local body = model and model.PrimaryPart
	if body == nil then
		return nil
	end
	return Vector3.new(position.X - body.Position.X, 0, position.Z - body.Position.Z).Magnitude
end

-- 놓여 있는 황금 상자를 집어 간다. 이미 없으면 false(CR-10)
function GoldService.take(): boolean
	if loose == nil then
		return false
	end
	clear()
	return true
end

-- 갑판 밖에서 내려놓았다. 그 자리 바닥에 남는다(GD-3)
function GoldService.dropAt(floor: Vector3)
	if RoundService.getPhase() ~= Phase.Loading then
		return
	end
	putOn(floor)
end

-- 든 채 물에 들어갔다. 바위 위로 돌아간다(GD-4)
function GoldService.returnToRock()
	if RoundService.getPhase() ~= Phase.Loading then
		return
	end
	putOn(rockTop())
end

function GoldService.start()
	local map = workspace:WaitForChild("Map")
	looseFolder = map:WaitForChild("Loose")
	rock = map:WaitForChild("Beach"):WaitForChild("Rock") :: BasePart
	asset = ServerStorage:WaitForChild("Assets"):WaitForChild("Crates"):WaitForChild(Kind.Gold) :: Model
	fx = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Fx") :: RemoteEvent

	BellService.onFirstBell(appear)
	RoundService.onPhaseChanged(function(newPhase, oldPhase)
		-- 라운드가 끝나면 갑판 밖의 황금 상자는 사라진다(GD-5). 손에 든 것은 CrateService가 치운다
		if oldPhase == Phase.Loading then
			clear()
		end
		if newPhase == Phase.Loading then
			appeared = false
		end
	end)
end

return GoldService
