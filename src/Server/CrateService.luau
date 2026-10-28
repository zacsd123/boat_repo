--!strict
-- 들기, 놓기, 버리기. 손에 붙이기. 화물칸의 칸.
-- Tap을 받으면 그 순간의 상황을 모아 InputRules.tap에 넘기고, 돌아온 답을 실행한다(03-architecture.md "톡 누르기를 처리하는 순서").
-- 이 함수는 시작부터 끝까지 기다리지 않는다. 같은 순간에 온 Tap도 도착한 순서대로 하나씩 끝까지 처리된다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local InputRules = require(ReplicatedStorage.Shared.Rules.InputRules)
local BoatRules = require(ReplicatedStorage.Shared.Rules.BoatRules)
local ParticipantService = require(script.Parent.ParticipantService)
local RoundService = require(script.Parent.RoundService)
local BoatService = require(script.Parent.BoatService)

local Phase = Types.Phase
local State = Types.ParticipantState
local Kind = Types.CrateKind

local CrateService = {}

local PILE_KINDS = { Kind.Small, Kind.Medium, Kind.Large }

local crateAssets: Instance -- ServerStorage.Assets.Crates
local pileSpots: { [string]: BasePart } = {}
local cargo: Instance -- Map.Boat.Cargo. 실린 상자 모형이 모두 여기 있다
local cargoHold: BasePart -- 칸 표시점(Cell1~)이 붙은 파트
local root: BasePart -- 배의 Root

local lastTapAt: { [Player]: number } = {}
local carried: { [Player]: Model } = {}
local nextCrateId = 0

-- 바닥 위 거리. 캐릭터 몸통과 바닥 표시의 높이 차가 거리를 줄이지 않게 평면으로 잰다
local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function reject(player: Player, reason: string)
	print(`Tap 버림 {player.Name}: {reason}`)
end

local function rootPartOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- 모형의 모든 파트를 한꺼번에 설정한다
local function setParts(model: Model, props: { [string]: any })
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			for key, value in props do
				(part :: any)[key] = value
			end
		end
	end
end

local function newCrate(kind: string, ownerSlot: number?): Model
	local model = (crateAssets:FindFirstChild(kind) :: Model):Clone()
	local ribbon = model:FindFirstChild("Ribbon") :: BasePart
	if ownerSlot ~= nil then
		ribbon.Color = ParticipantService.colorOf(ownerSlot)
	end
	return model
end

-- 빈손일 때의 들기(IN-3). 상자를 가슴 앞에 붙인다. 질량과 충돌을 꺼서 걸음을 방해하지 않는다
local function pickUp(player: Player, kind: string, rootPart: BasePart)
	local slot = ParticipantService.slotOf(player)
	local model = newCrate(kind, slot)
	local body = model.PrimaryPart :: BasePart
	setParts(model, { Anchored = false, Massless = true, CanCollide = false, CanQuery = false, CanTouch = false })
	local forward = rootPart.Size.Z / 2 + body.Size.Z / 2
	model:PivotTo(rootPart.CFrame * CFrame.new(0, 0, -forward) * CFrame.new(0, -body.Size.Y / 2, 0))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = body
	weld.Parent = body
	model.Name = "Carried"
	model.Parent = player.Character
	carried[player] = model
	ParticipantService.setState(player, State.Carrying, kind)
end

local function dropCarried(player: Player)
	local model = carried[player]
	if model then
		model:Destroy()
	end
	carried[player] = nil
	ParticipantService.setState(player, State.Empty, nil)
end

-- 칸마다 몇 층까지 찼는지, 그리고 각 칸 맨 위 상자
local function stackInfo(): ({ [number]: number }, { [number]: Model })
	local height: { [number]: number } = {}
	local top: { [number]: Model } = {}
	for _, crate in cargo:GetChildren() do
		local cell = crate:GetAttribute("Cell") :: number?
		local layer = crate:GetAttribute("Layer") :: number?
		if cell and layer and crate:IsA("Model") and layer > (height[cell] or 0) then
			height[cell] = layer
			top[cell] = crate
		end
	end
	return height, top
end

-- 놓는 사람에게 가장 가까운 빈 칸. 1층이 다 찼으면 가장 가까운 칸의 2층, 그다음 3층…(GP-3, GP-4)
local function chooseCell(from: Vector3): (number, number)
	local height = stackInfo()
	local cells: { Attachment } = {}
	for _, child in cargoHold:GetChildren() do
		if child:IsA("Attachment") then
			table.insert(cells, child)
		end
	end
	local lowest = math.huge
	for index = 1, #cells do
		lowest = math.min(lowest, height[index] or 0)
	end
	local bestCell, bestDistance = 1, math.huge
	for _, attachment in cells do
		local index = tonumber(string.match(attachment.Name, "%d+")) :: number
		if (height[index] or 0) == lowest then
			local distance = flatDistance(attachment.WorldPosition, from)
			if distance < bestDistance then
				bestCell, bestDistance = index, distance
			end
		end
	end
	return bestCell, lowest + 1
end

-- 화물칸에 실린 상자를 만들고 배의 Root에 붙인다. near에서 가장 가까운 빈 칸. 주인이 없으면 시험용 상자
local function addCrate(kind: string, slot: number?, near: Vector3): Model
	local cell, layer = chooseCell(near)
	local _, top = stackInfo()
	local base: CFrame
	local below = top[cell]
	if below then
		local belowBody = below.PrimaryPart :: BasePart
		base = belowBody.CFrame * CFrame.new(0, belowBody.Size.Y / 2, 0)
	else
		base = (cargoHold:FindFirstChild("Cell" .. cell) :: Attachment).WorldCFrame
	end

	nextCrateId += 1
	local model = newCrate(kind, slot)
	model.Name = "Crate" .. nextCrateId
	model:SetAttribute("CrateId", nextCrateId)
	model:SetAttribute("Kind", kind)
	model:SetAttribute("OwnerSlot", slot)
	model:SetAttribute("Cell", cell)
	model:SetAttribute("Layer", layer)
	local body = model.PrimaryPart :: BasePart
	setParts(model, { Anchored = false, CanTouch = false })
	model:PivotTo(base * CFrame.new(0, body.Size.Y / 2, 0))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = body
	weld.Parent = body
	model.Parent = cargo
	return model
end

-- 갑판에서 놓기(CR-5). 든 상자를 화물칸에 싣고, 배의 무게를 다시 더해 판정한다
local function placeOnDeck(player: Player, rootPart: BasePart)
	local kind = ParticipantService.carryingOf(player)
	local slot = ParticipantService.slotOf(player)
	if kind == nil or slot == nil then
		return
	end
	dropCarried(player)
	addCrate(kind, slot, rootPart.Position)
	-- 무게를 다시 더한 바로 다음 줄에서 판정한다(BT-6). 가라앉힌 사람은 이 상자를 놓은 참가자다
	local result = BoatService.onPlaced()
	if result and result.sank then
		RoundService.sink(slot, player.Name)
	end
end

-- 실린 상자 하나를 갑판에서 뺀다. 무게를 다시 더한다
function CrateService.removeCrate(model: Instance)
	if model.Parent ~= cargo then
		return
	end
	model:Destroy()
	BoatService.onRemoved()
end

-- 시험용(주인 없는) 상자를 싣는다. 판정도 실제 놓기와 같이 지난다
function CrateService.addTestCrate(kind: string): BoatRules.PlaceResult?
	-- 실제 놓기와 같이, 싣는 단계가 아니면 없던 일
	if RoundService.getPhase() ~= Phase.Loading then
		return nil
	end
	addCrate(kind, nil, root.Position)
	local result = BoatService.onPlaced()
	if result and result.sank then
		RoundService.sink(nil, nil)
	end
	return result
end

function CrateService.cargoCrates(): { Instance }
	return cargo:GetChildren()
end

-- 클라이언트가 보낸 대상이 더미 종류인지
local function pileKind(target: any): string?
	if type(target) ~= "string" then
		return nil
	end
	for _, kind in PILE_KINDS do
		if kind == target then
			return kind
		end
	end
	return nil
end

-- Tap 하나를 처리한다. 클라이언트의 값은 믿지 않고 서버의 상태로 다시 본다
function CrateService.handleTap(player: Player, target: any)
	local now = os.clock()
	local last = lastTapAt[player]
	if last ~= nil and now - last < Config.INPUT_MIN_INTERVAL then
		reject(player, "INPUT_MIN_INTERVAL 안에 또 옴")
		return
	end
	lastTapAt[player] = now

	local rootPart = rootPartOf(player)
	local state = ParticipantService.stateOf(player)
	if rootPart == nil or state == nil then
		reject(player, "캐릭터나 참가자 기록이 없음")
		return
	end

	local kind = pileKind(target)
	local pileDistance: number? = nil
	if kind ~= nil then
		pileDistance = flatDistance(rootPart.Position, pileSpots[kind].Position)
	end

	local situation: InputRules.Situation = {
		phase = RoundService.getPhase() or "",
		state = state,
		onDeck = BoatService.isOnDeck(rootPart.Position),
		carrying = ParticipantService.carryingOf(player),
		pickupInReach = pileDistance ~= nil and pileDistance <= Config.TARGET_RANGE,
		reclaimable = false, -- 되찾기는 S19
	}
	local action = InputRules.tap(situation)

	if action == "Place" then
		placeOnDeck(player, rootPart)
	elseif action == "Discard" or action == "DropGold" then
		dropCarried(player) -- 황금 상자를 그 자리에 남기는 것은 S22
	elseif action == "Pickup" and kind ~= nil then
		pickUp(player, kind, rootPart)
	elseif action == "Hint" then
		-- 힌트는 S17
	else
		local reason = `단계 {situation.phase}, 상태 {state}`
		if situation.phase == Phase.Loading and state == State.Empty and not situation.onDeck then
			if kind == nil then
				reason = `대상이 더미가 아님({tostring(target)})`
			else
				reason = `대상 더미 {kind}가 TARGET_RANGE({Config.TARGET_RANGE}) 밖(거리 {string.format("%.1f", pileDistance or 0)})`
			end
		end
		reject(player, reason)
	end
end

-- 손에 든 상자를 모두 없앤다(CR-11)
local function dropAllCarried()
	for _, player in ParticipantService.players() do
		if carried[player] or ParticipantService.stateOf(player) == State.Carrying then
			dropCarried(player)
		end
	end
end

-- 화물칸을 비운다(배가 바뀔 때). 다음 라운드의 무게는 startRound가 0에서 시작한다
function CrateService.clearDeck()
	cargo:ClearAllChildren()
end

function CrateService.start()
	local map = workspace:WaitForChild("Map")
	local boat = map:WaitForChild("Boat")
	root = boat:WaitForChild("Root") :: BasePart
	cargo = boat:WaitForChild("Cargo")
	cargoHold = boat:WaitForChild("CargoHold") :: BasePart
	crateAssets = game:GetService("ServerStorage"):WaitForChild("Assets"):WaitForChild("Crates")
	local beach = map:WaitForChild("Beach")
	for _, kind in PILE_KINDS do
		pileSpots[kind] = beach:WaitForChild("Pile" .. kind) :: BasePart
	end

	local tap = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Tap") :: RemoteEvent
	tap.OnServerEvent:Connect(CrateService.handleTap)

	RoundService.onPhaseChanged(function(newPhase, oldPhase)
		-- 라운드가 끝나는 순간 손에 든 상자는 사라진다
		if oldPhase == Phase.Loading then
			dropAllCarried()
		end
		-- 실린 상자는 정산이 끝날 때(배가 다시 들어올 때) 치운다
		if newPhase == Phase.Arriving or newPhase == nil then
			CrateService.clearDeck()
		end
	end)
end

return CrateService
