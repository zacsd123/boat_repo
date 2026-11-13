--!strict
-- 들기, 놓기, 버리기, 내 상자 다시 들기. 손에 붙이기. 화물칸의 칸.
-- Tap을 받으면 그 순간의 상황을 모아 InputRules.tap에 넘기고, 돌아온 답을 실행한다(03-architecture.md "톡 누르기를 처리하는 순서").
-- HoldBegin과 HoldEnd(S17)는 누른 시간을 서버가 재서 InputRules.hold에 넘긴다(GP-9).
-- 이 함수들은 시작부터 끝까지 기다리지 않는다. 같은 순간에 온 요청도 도착한 순서대로 하나씩 끝까지 처리된다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local InputRules = require(ReplicatedStorage.Shared.Rules.InputRules)
local BoatRules = require(ReplicatedStorage.Shared.Rules.BoatRules)
local ParticipantService = require(script.Parent.ParticipantService)
local RoundService = require(script.Parent.RoundService)
local BoatService = require(script.Parent.BoatService)
local BellService = require(script.Parent.BellService)
local ScoreService = require(script.Parent.ScoreService)
local GoldService = require(script.Parent.GoldService)
local Telemetry = require(script.Parent.Telemetry)

local Phase = Types.Phase
local State = Types.ParticipantState
local Kind = Types.CrateKind

local CrateService = {}

local PILE_KINDS = { Kind.Small, Kind.Medium, Kind.Large }

local crateAssets: Instance -- ServerStorage.Assets.Crates
local pileSpots: { [string]: BasePart } = {}
local cargo: Instance -- Map.Boat.Cargo. 실린 상자 모형이 모두 여기 있다
local cargoHold: BasePart -- 칸 표시점(Cell1~)이 붙은 파트
local fx: RemoteEvent
local root: BasePart -- 배의 Root

local lastTapAt: { [Player]: number } = {}
local lastHoldAt: { [Player]: number } = {}
local holdStart: { [Player]: { crateId: number, at: number } } = {} -- 꾹 누르기를 시작한 상자와 받은 시각
local carried: { [Player]: Model } = {}
local nextCrateId = 0

-- 끌어안기(S18)와 되찾기(S19)는 HugService가 맡는다. HugService가 이 모듈을 require하므로,
-- 거꾸로 부를 함수는 HugService가 켜질 때 여기에 걸어 둔다(순환 require 방지)
export type HugHooks = {
	begin: (player: Player, crate: Model) -> (), -- 꾹 누르기가 "끌어안기"로 끝났다
	reclaimable: (player: Player, rootPart: BasePart) -> boolean, -- 되찾을 상자가 손 닿는 곳에 있나
	reclaim: (player: Player, rootPart: BasePart) -> (), -- 되찾는다
}
local hugHooks: HugHooks? = nil

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

-- 캐릭터가 서 있는 바닥의 점
local function feetOf(player: Player, rootPart: BasePart): Vector3
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return rootPart.Position - Vector3.new(0, rootPart.Size.Y / 2 + (if humanoid then humanoid.HipHeight else 0), 0)
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
local function pickUp(player: Player, kind: string, rootPart: BasePart, fromDeck: boolean?)
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
	if fromDeck then
		Telemetry.repicked(player) -- 갑판에서 다시 든 상자는 "하나 더"가 아니다
	else
		Telemetry.pickedUp(player)
	end
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
	local crate = addCrate(kind, slot, rootPart.Position)
	Telemetry.placed(player, kind)
	fx:FireAllClients("Place", (crate.PrimaryPart :: BasePart).Position)
	ScoreService.recompute() -- 머리 위 숫자가 놓는 순간 오른다
	-- 무게를 다시 더한 바로 다음 줄에서 판정한다(BT-6). 가라앉힌 사람은 이 상자를 놓은 참가자다
	local result = BoatService.onPlaced()
	if kind == Kind.Gold and result then
		Telemetry.goldPlaced(BoatService.deckWeight(), result.sank)
	end
	-- 첫 종이 침몰보다 먼저다. 같은 상자에서 둘이 함께 날 수 있다(BL-5)
	if result and result.touchedBand then
		BellService.firstBell()
	end
	if result and result.sank then
		RoundService.sink(slot, player.Name)
	end
end

-- 아래 상자가 사라진 칸에서는 위 상자가 내려온다(S20). 칸마다 층 번호와 자리를 아래부터 다시 매긴다.
-- 바뀐 것이 없는 칸은 건드리지 않는다
local function settleStacks()
	local stacks: { [number]: { Model } } = {}
	for _, crate in cargo:GetChildren() do
		local cell = crate:GetAttribute("Cell") :: number?
		if cell and crate:IsA("Model") then
			local stack = stacks[cell] or {}
			stacks[cell] = stack
			table.insert(stack, crate)
		end
	end
	for cell, stack in stacks do
		table.sort(stack, function(a, b)
			return ((a:GetAttribute("Layer") :: number?) or 0) < ((b:GetAttribute("Layer") :: number?) or 0)
		end)
		local base = (cargoHold:FindFirstChild("Cell" .. cell) :: Attachment).WorldCFrame
		local dropped = false -- 이 층부터 위는 모두 내려와야 한다
		for layer, crate in stack do
			local body = crate.PrimaryPart :: BasePart
			if crate:GetAttribute("Layer") ~= layer then
				dropped = true
				crate:SetAttribute("Layer", layer)
			end
			if dropped then
				local weld = body:FindFirstChildOfClass("WeldConstraint")
				if weld then
					weld.Enabled = false
				end
				crate:PivotTo(base * CFrame.new(0, body.Size.Y / 2, 0))
				if weld then
					weld.Enabled = true
				end
			end
			base = body.CFrame * CFrame.new(0, body.Size.Y / 2, 0)
		end
	end
end

-- 실린 상자 하나를 갑판에서 뺀다. 무게를 다시 더한다
function CrateService.removeCrate(model: Instance)
	if model.Parent ~= cargo then
		return
	end
	model:Destroy()
	settleStacks()
	BoatService.onRemoved()
	ScoreService.recompute()
end

-- 시험용(주인 없는) 상자를 싣는다. 판정도 실제 놓기와 같이 지난다
function CrateService.addTestCrate(kind: string): BoatRules.PlaceResult?
	-- 실제 놓기와 같이, 싣는 단계가 아니면 없던 일
	if RoundService.getPhase() ~= Phase.Loading then
		return nil
	end
	addCrate(kind, nil, root.Position)
	local result = BoatService.onPlaced()
	if result and result.touchedBand then
		BellService.firstBell()
	end
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

-- 서버가 그 순간에 본 상황. 들 것과 되찾을 것은 부르는 쪽이 채운다
local function situationOf(player: Player, rootPart: BasePart, state: string): InputRules.Situation
	return {
		phase = RoundService.getPhase() or "",
		state = state,
		onDeck = BoatService.isOnDeck(rootPart.Position),
		carrying = ParticipantService.carryingOf(player),
		pickupInReach = false,
		reclaimable = false,
	}
end

-- 번호로 실린 상자를 찾는다
function CrateService.findCrate(crateId: any): Model?
	if type(crateId) ~= "number" then
		return nil
	end
	for _, crate in cargo:GetChildren() do
		if crate:IsA("Model") and crate:GetAttribute("CrateId") == crateId then
			return crate
		end
	end
	return nil
end

-- 그 상자 위에 다른 상자가 쌓였는지(GP-4). 같은 칸에서 층이 더 높은 상자가 있으면 그렇다
function CrateService.isCovered(crate: Model): boolean
	local cell = crate:GetAttribute("Cell")
	local layer = (crate:GetAttribute("Layer") :: number?) or 0
	for _, other in cargo:GetChildren() do
		if other ~= crate and other:GetAttribute("Cell") == cell and ((other:GetAttribute("Layer") :: number?) or 0) > layer then
			return true
		end
	end
	return false
end

-- 캐릭터에서 실린 상자까지의 바닥 위 거리
function CrateService.distanceTo(rootPart: BasePart, crate: Model): number
	return flatDistance(rootPart.Position, (crate.PrimaryPart :: BasePart).Position)
end

-- 갑판의 내 상자를 다시 든다(CR-8). 드는 순간 무게와 점수에서 빠진다
local function repick(player: Player, crate: Model, rootPart: BasePart)
	local kind = crate:GetAttribute("Kind") :: string
	crate:Destroy()
	pickUp(player, kind, rootPart, true)
	BoatService.onRemoved()
	ScoreService.recompute()
end

-- 꾹 누르기 시작. 상자가 있는지만 보고 받은 시각을 적어 둔다
function CrateService.handleHoldBegin(player: Player, crateId: any)
	ParticipantService.markInput(player)
	local now = os.clock()
	local last = lastHoldAt[player]
	if last ~= nil and now - last < Config.INPUT_MIN_INTERVAL then
		reject(player, "HoldBegin이 INPUT_MIN_INTERVAL 안에 또 옴")
		return
	end
	lastHoldAt[player] = now
	if CrateService.findCrate(crateId) == nil then
		holdStart[player] = nil
		reject(player, `HoldBegin의 상자({tostring(crateId)})가 없음`)
		return
	end
	holdStart[player] = { crateId = crateId, at = now }
end

-- 꾹 누르기 끝. 시작과의 간격을 서버가 재고(GP-9), 그 순간의 상황과 대상을 InputRules.hold에 넘긴다.
-- 클라이언트가 보낸 "다 채웠는지"는 취소를 알리는 데만 쓴다. 채웠는지는 서버가 잰 시간으로 본다
function CrateService.handleHoldEnd(player: Player, crateId: any, filled: any)
	local started = holdStart[player]
	holdStart[player] = nil
	if started == nil or started.crateId ~= crateId then
		reject(player, "HoldEnd에 맞는 HoldBegin이 없음")
		return
	end
	if filled ~= true then
		return -- 누르는 중에 멀어져 취소했다
	end
	local heldTime = os.clock() - started.at

	local rootPart = rootPartOf(player)
	local state = ParticipantService.stateOf(player)
	local slot = ParticipantService.slotOf(player)
	if rootPart == nil or state == nil or slot == nil then
		reject(player, "캐릭터나 참가자 기록이 없음")
		return
	end

	-- 대상은 지금도 있고 손 닿는 거리 안이어야 한다(GP-5). 아니면 대상이 없는 것으로 본다
	local crate = CrateService.findCrate(crateId)
	local target: InputRules.Target? = nil
	if crate ~= nil and CrateService.distanceTo(rootPart, crate) <= Config.TARGET_RANGE then
		local huggedBy = crate:GetAttribute("HuggedBySlot") :: number?
		target = {
			mine = crate:GetAttribute("OwnerSlot") == slot,
			huggedBy = if huggedBy then tostring(huggedBy) else nil,
			covered = CrateService.isCovered(crate),
		}
	end

	local action = InputRules.hold(situationOf(player, rootPart, state), target, heldTime, {
		holdTime = Config.HOLD_TIME,
		holdTolerance = Config.HOLD_TOLERANCE,
		hugEnabled = Config.HUG_ENABLED,
	})
	if action == "Repick" and crate ~= nil then
		repick(player, crate, rootPart)
	elseif action == "Hug" and crate ~= nil then
		local hooks = hugHooks
		if hooks ~= nil then
			hooks.begin(player, crate)
		end
	else
		reject(player, `HoldEnd 버림: 누른 시간 {string.format("%.2f", heldTime)}초, 상태 {state}, 대상 {if target then "있음" else "없음"}`)
	end
end

-- HugService가 켜질 때 끌어안기와 되찾기를 건다
function CrateService.setHugHooks(hooks: HugHooks)
	hugHooks = hooks
end

-- Tap 하나를 처리한다. 클라이언트의 값은 믿지 않고 서버의 상태로 다시 본다
function CrateService.handleTap(player: Player, target: any)
	ParticipantService.markInput(player) -- 버튼을 보낸 것 자체가 입력이다(GP-10)
	local now = os.clock()
	local last = lastTapAt[player]
	if last ~= nil and now - last < Config.INPUT_MIN_INTERVAL then
		reject(player, "INPUT_MIN_INTERVAL 안에 또 옴")
		return
	end
	lastTapAt[player] = now
	holdStart[player] = nil -- 다 채우기 전에 뗀 꾹 누르기는 톡 누르기가 된다

	local rootPart = rootPartOf(player)
	local state = ParticipantService.stateOf(player)
	if rootPart == nil or state == nil then
		reject(player, "캐릭터나 참가자 기록이 없음")
		return
	end

	-- 들 것: 더미 셋 가운데 하나, 또는 갑판 밖에 놓여 있는 황금 상자(IN-3)
	local kind = pileKind(target)
	local wantsGold = target == Kind.Gold
	local pileDistance: number? = nil
	if kind ~= nil then
		pileDistance = flatDistance(rootPart.Position, pileSpots[kind].Position)
	elseif wantsGold then
		pileDistance = GoldService.distanceFrom(rootPart.Position)
	end

	local situation = situationOf(player, rootPart, state)
	situation.pickupInReach = pileDistance ~= nil and pileDistance <= Config.TARGET_RANGE
	local hooks = hugHooks
	situation.reclaimable = hooks ~= nil and hooks.reclaimable(player, rootPart)
	local action = InputRules.tap(situation)

	if action == "Place" then
		placeOnDeck(player, rootPart)
	elseif action == "Discard" then
		dropCarried(player)
	elseif action == "DropGold" then
		-- 황금 상자는 그 자리 바닥에 남아 누구든 집을 수 있다(GD-3)
		dropCarried(player)
		GoldService.dropAt(feetOf(player, rootPart))
	elseif action == "Pickup" and kind ~= nil then
		pickUp(player, kind, rootPart)
	elseif action == "Pickup" and wantsGold then
		-- 둘이 함께 눌러도 먼저 처리된 쪽이 가져가면 다음 Tap에는 놓여 있는 상자가 없다(CR-10)
		if GoldService.take() then
			pickUp(player, Kind.Gold, rootPart)
			Telemetry.goldPicked(player)
		end
	elseif action == "Reclaim" and hooks ~= nil then
		hooks.reclaim(player, rootPart)
	elseif action == "Hint" then
		-- 되찾을 것이 없다. "여기는 꾹 눌러야 한다"만 그 사람에게 알린다(IN-4)
		fx:FireClient(player, "HoldHint")
	else
		local reason = `단계 {situation.phase}, 상태 {state}`
		if situation.phase == Phase.Loading and state == State.Empty and not situation.onDeck then
			if wantsGold then
				reason = `황금 상자가 없거나 TARGET_RANGE({Config.TARGET_RANGE}) 밖`
			elseif kind == nil then
				reason = `대상이 더미가 아님({tostring(target)})`
			else
				reason = `대상 더미 {kind}가 TARGET_RANGE({Config.TARGET_RANGE}) 밖(거리 {string.format("%.1f", pileDistance or 0)})`
			end
		end
		reject(player, reason)
	end
end

-- 손에 든 상자를 없애고 빈손으로(물에 들어가 놓친 상자, CR-9). 황금 상자는 바위로 돌아간다(GD-4)
function CrateService.dropCarried(player: Player)
	local wasGold = ParticipantService.carryingOf(player) == Kind.Gold
	dropCarried(player)
	if wasGold then
		GoldService.returnToRock()
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

	fx = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Fx") :: RemoteEvent
	local tap = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Tap") :: RemoteEvent
	tap.OnServerEvent:Connect(CrateService.handleTap)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	;(remotes:WaitForChild("HoldBegin") :: RemoteEvent).OnServerEvent:Connect(CrateService.handleHoldBegin)
	;(remotes:WaitForChild("HoldEnd") :: RemoteEvent).OnServerEvent:Connect(CrateService.handleHoldEnd)

	-- 사람이 나가면 든 상자와 갑판의 그 사람 상자를 모두 없애고, 무게와 점수를 다시 더한다(JN-2).
	-- 젖은 자국과 이미 울린 종은 그대로다(BoatRules의 "빠졌다"는 무게만 고친다)
	ParticipantService.onLeaving(function(player, slot)
		local model = carried[player]
		if model then
			model:Destroy()
			-- 황금 상자를 든 채 나가면 바위로 돌아간다. 라운드에 하나뿐인 상자가 함께 사라지지 않게(S22에서 정함)
			if ParticipantService.carryingOf(player) == Kind.Gold then
				GoldService.returnToRock()
			end
		end
		carried[player] = nil
		lastTapAt[player] = nil
		lastHoldAt[player] = nil
		holdStart[player] = nil
		local removed = 0
		for _, crate in cargo:GetChildren() do
			if crate:GetAttribute("OwnerSlot") == slot then
				crate:Destroy()
				removed += 1
			end
		end
		if removed > 0 then
			settleStacks()
			BoatService.onRemoved()
			ScoreService.recompute()
		end
		print(`나간 사람의 상자 {removed}개를 치움(슬롯 {slot})`)
	end)

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
