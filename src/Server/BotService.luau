--!strict
-- 봇(S25). 사람이 BOT_FILL_TO보다 적으면 모자란 자리를 채운다(PL-1).
-- 봇도 참가자다: ParticipantService가 같은 참가자 기록을 만들고, 들기와 놓기는 사람의 Tap을 처리하는
-- 그 서버 함수(CrateService.handleTap)를 부른다. 봇용 판정은 없다.
-- 걷기는 정해 둔 길목을 차례로 잇는다. 똑똑한 것보다 끼지 않는 것이 먼저다.
-- 길목 사이는 Humanoid:Move로 매 프레임 다음 길목 쪽을 가리켜 걷는다. Humanoid:MoveTo는 상자를 든 봇이
-- 목표를 바꿀 때마다 한 번씩 멈춰 서서(길목마다 0.2초쯤) 사람보다 느려지기 때문이다(S25에서 재서 정함).
-- 넣고 빼는 것은 Loading에 들어가기 직전뿐이다. 라운드 도중에는 넣지도 빼지도 않는다(PL-2).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local JoinRules = require(ReplicatedStorage.Shared.Rules.JoinRules)
local ParticipantService = require(script.Parent.ParticipantService)
local RoundService = require(script.Parent.RoundService)
local BoatService = require(script.Parent.BoatService)
local CrateService = require(script.Parent.CrateService)
local Telemetry = require(script.Parent.Telemetry)
local DevTools = require(script.Parent.DevTools)

local Phase = Types.Phase
local State = Types.ParticipantState
local Kind = Types.CrateKind

local BotService = {}

-- 봇의 종류. 참가자 기록의 BotKind에 적힌다
local BotKind = {
	Porter = "Porter", -- 짐꾼: 큰 상자만 나른다(PL-5)
}

-- 길목. 이름은 그때그때 자리를 다시 읽고(배는 무게에 따라 오르내린다), 점은 그대로 쓴다
type Waypoint = string | Vector3

type Bot = {
	member: Player,
	kind: string,
	slot: number,
	dest: string, -- 지금 가려는 곳의 이름. 바뀌면 길을 다시 짠다
	path: { Waypoint }, -- 남은 길목
	moving: boolean, -- 걷는 방향을 걸어 둔 상태인지
	anchorAt: number, -- 끼었는지 볼 때의 기준 시각과 자리
	anchorPosition: Vector3,
}

-- 걷기의 값(모양이 아니라 길목을 잇는 방법의 값이다. 규칙의 수치가 아니라 Config에 두지 않는다)
local PASS_RADIUS = 1.5 -- 중간 길목은 이만큼 가까워지면 지난 것으로 본다(멈췄다 가지 않게)
local ARRIVE_RADIUS = 1.2 -- 마지막 길목에 닿았다고 보는 거리
local PILE_STEP = 2 -- 더미 자리에서 선착장 쪽으로 이만큼 나와 선다(더미 한가운데에 서지 않게)
local AISLE_SPACING = 2.6 -- 통로의 자기 자리 사이 간격(스터드). 슬롯마다 한 자리
local AISLE_FROM_ROOT = 6.2 -- 통로의 자기 자리: 배의 Root에서 선착장 쪽으로(갑판 입구와 화물칸 벽 사이)
local WATER_LANE = 9 -- 물에서 나올 때 걷는 줄. 선착장 밑을 피해 옆으로 이만큼 비켜서 해변으로 간다
local SHORE_Z = 5 -- 물에서 나와 처음 서는 해변의 Z

local botAsset: Model -- ServerStorage.Assets.Bots.Bot
local boat: Model
local root: BasePart -- 배의 Root
local entrance: Attachment -- 갑판 입구
local rampFoot: Vector3 -- 선착장 경사로 입구(해변 쪽 끝)
local rampTop: Vector3 -- 경사로 위 끝(선착장 머리 앞)
local pileSpots: { [string]: BasePart } = {}
local spawnSlots: Instance

local bots: { Bot } = {}

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function partsOf(bot: Bot): (Model?, BasePart?, Humanoid?)
	local character = bot.member.Character
	if character == nil then
		return nil, nil, nil
	end
	return character, character:FindFirstChild("HumanoidRootPart") :: BasePart?, character:FindFirstChildOfClass("Humanoid")
end

-- 더미 앞에 서는 자리: 더미 자리에서 경사로 입구 쪽으로 조금 나온 곳. TARGET_RANGE 안이다
local function pilePoint(kind: string): Vector3
	local spot = pileSpots[kind].Position
	local toward = Vector3.new(rampFoot.X - spot.X, 0, rampFoot.Z - spot.Z).Unit
	return spot + toward * PILE_STEP
end

-- 이름 붙은 길목의 지금 자리
local function resolve(bot: Bot, waypoint: Waypoint): Vector3
	if typeof(waypoint) == "Vector3" then
		return waypoint
	elseif waypoint == "rampFoot" then
		return rampFoot
	elseif waypoint == "rampTop" then
		return rampTop
	elseif waypoint == "entrance" then
		return entrance.WorldPosition
	elseif waypoint == "aisle" then
		-- 통로의 자기 자리(슬롯으로 정한다). 여기서 놓으면 상자가 그 근처 칸에 모인다
		local x = (bot.slot - (Config.SERVER_MAX_PLAYERS + 1) / 2) * AISLE_SPACING
		return root.CFrame * Vector3.new(x, 0, AISLE_FROM_ROOT)
	elseif waypoint == "rest" then
		-- 정산 동안 서 있는 자리: 더미 근처의 자기 슬롯 자리
		local spot = spawnSlots:FindFirstChild("Slot" .. bot.slot) :: BasePart
		return spot.Position
	else
		return pilePoint(waypoint) -- 더미 종류의 이름
	end
end

-- 지금 서 있는 곳이 선착장(경사로, 머리, 배다리) 위인지
local function onDock(position: Vector3): boolean
	return math.abs(position.X) <= 3.5 and position.Z <= rampFoot.Z + 0.5 and position.Z >= entrance.WorldPosition.Z
		and position.Y > rampFoot.Y
end

-- 갑판의 한 자리(통로)로 가는 길
local function routeToDeck(position: Vector3, final: Waypoint): { Waypoint }
	if BoatService.isOnDeck(position) then
		return { final }
	elseif onDock(position) then
		if position.Z > rampTop.Z then
			return { "rampTop", "entrance", final }
		end
		return { "entrance", final }
	end
	return { "rampFoot", "rampTop", "entrance", final }
end

-- 해변의 한 자리(더미 앞, 쉬는 자리)로 가는 길
local function routeToBeach(position: Vector3, final: Waypoint): { Waypoint }
	if BoatService.isOnDeck(position) then
		return { "entrance", "rampTop", "rampFoot", final }
	elseif onDock(position) then
		if position.Z < rampTop.Z then
			return { "rampTop", "rampFoot", final }
		end
		return { "rampFoot", final }
	end
	return { final }
end

-- 물에서 해변으로 나오는 길. 선착장 밑을 피해 옆줄로 비켜서 걸어 나온다
local function routeOutOfWater(position: Vector3, final: Waypoint): { Waypoint }
	local side = if position.X >= 0 then 1 else -1
	local lane = side * math.max(math.abs(position.X), WATER_LANE)
	local path: { Waypoint } = {}
	local z = position.Z
	if BoatService.isOnDeck(Vector3.new(position.X, root.Position.Y + 2, position.Z)) then
		-- 가라앉는 갑판 위다. 입구 쪽 턱이 열린 곳으로 먼저 나간다
		local gate = entrance.WorldPosition
		z = gate.Z + 1.5
		table.insert(path, Vector3.new(gate.X, position.Y, z))
	end
	table.insert(path, Vector3.new(lane, position.Y, z)) -- 옆줄로 비켜선 다음
	table.insert(path, Vector3.new(lane, position.Y, SHORE_Z)) -- 해변으로
	table.insert(path, final)
	return path
end

local function setPath(bot: Bot, dest: string, path: { Waypoint })
	bot.dest = dest
	bot.path = path
	bot.anchorAt = os.clock()
end

local function stop(bot: Bot)
	bot.dest = ""
	bot.path = {} -- 길이 비면 walk가 걸음을 멈춘다
end

-- 갑판 통로의 자기 자리로 간다
local function goToAisle(bot: Bot, position: Vector3)
	if bot.dest ~= "aisle" then
		setPath(bot, "aisle", routeToDeck(position, "aisle"))
	end
end

-- 해변의 한 자리로 간다
local function goToBeach(bot: Bot, position: Vector3, place: string)
	if bot.dest ~= place then
		setPath(bot, place, routeToBeach(position, place))
	end
end

-- 물에 빠졌다(침몰). 해변으로 걸어 나온다
local function leaveWater(bot: Bot, position: Vector3)
	if bot.dest ~= "shore" then
		setPath(bot, "shore", routeOutOfWater(position, "rest"))
	end
end

-- 길을 다 갔는지
local function arrived(bot: Bot, dest: string): boolean
	return bot.dest == dest and #bot.path == 0
end

-- 봇이 버튼을 누른다. 사람의 Tap이 지나는 그 함수다
local function tap(bot: Bot, target: any)
	CrateService.handleTap(bot.member, target)
end

-- 짐꾼(PL-5): 큰 상자만 나른다. 첫 종이 울리면 손에 든 상자까지만 싣고 갑판에 서 있는다.
-- 황금 상자는 들지 않는다. 끌어안지도 되찾지도 않는다
local function porter(bot: Bot, position: Vector3, state: string)
	local belled = ((boat:GetAttribute("BellCount") :: number?) or 0) >= 1
	if state == State.Carrying then
		goToAisle(bot, position)
		if arrived(bot, "aisle") and BoatService.isOnDeck(position) then
			tap(bot, nil) -- 놓기
		end
	elseif belled then
		-- 새 상자를 가지러 가지 않는다. 통로의 자기 자리에 선다
		goToAisle(bot, position)
	else
		goToBeach(bot, position, Kind.Large)
		if arrived(bot, Kind.Large) then
			tap(bot, Kind.Large) -- 들기
		end
	end
end

-- 무엇을 할지 고른다
local function decide(bot: Bot, position: Vector3)
	local phase = RoundService.getPhase()
	local state = ParticipantService.stateOf(bot.member) or State.Empty
	if phase == Phase.FinalPodium then
		stop(bot) -- 단상에 올려진 봇이 걸어 내려가지 않게
	elseif state == State.InWater then
		leaveWater(bot, position)
	elseif state == State.Hugging then
		return -- 끌어안는 동안은 제자리다(HG-3)
	elseif phase == Phase.Loading then
		porter(bot, position, state)
	else
		-- 정산 동안에는 더미 근처로 돌아와 선다
		goToBeach(bot, position, "rest")
	end
end

-- 남은 길목을 따라 걷는다. 끼었으면 다음 길목 위로 옮긴다
local function walk(bot: Bot, character: Model, rootPart: BasePart, humanoid: Humanoid, now: number)
	local position = rootPart.Position
	while #bot.path > 0 do
		local radius = if #bot.path == 1 then ARRIVE_RADIUS else PASS_RADIUS
		if flatDistance(position, resolve(bot, bot.path[1])) > radius then
			break
		end
		table.remove(bot.path, 1)
	end
	local nextWaypoint = bot.path[1]
	if nextWaypoint == nil then
		if bot.moving then
			humanoid:Move(Vector3.zero, false)
			bot.moving = false
		end
		bot.anchorAt = now
		return
	end
	local target = resolve(bot, nextWaypoint)
	local toward = Vector3.new(target.X - position.X, 0, target.Z - position.Z)
	if toward.Magnitude > 0 then
		humanoid:Move(toward.Unit, false)
		bot.moving = true
	end

	-- 끼었을 때: 갈 곳이 남았는데 BOT_STUCK_TIME 동안 IDLE_MOVE_THRESHOLD도 못 움직였다.
	-- 묶여 있거나(끌어안는 중) 연출로 옮겨지는 중(던져짐, 사다리)에는 세지 않는다
	if rootPart.Anchored or humanoid.WalkSpeed <= 0 or (position - bot.anchorPosition).Magnitude > Config.IDLE_MOVE_THRESHOLD then
		bot.anchorAt = now
		bot.anchorPosition = position
	elseif now - bot.anchorAt >= Config.BOT_STUCK_TIME then
		print(`봇이 끼어서 옮김: {bot.member.Name} (슬롯 {bot.slot}) → {tostring(nextWaypoint)}`)
		Telemetry.botStuck()
		character:PivotTo(CFrame.new(target + Vector3.new(0, humanoid.HipHeight + rootPart.Size.Y / 2, 0)))
		rootPart.AssemblyLinearVelocity = Vector3.zero
		bot.anchorAt = now
		bot.anchorPosition = rootPart.Position
	end
end

local function step()
	-- 사람 넷이 있는 서버에서는 봇이 없고, 이 아래는 돌지 않는다
	if #bots == 0 then
		return
	end
	local now = os.clock()
	for _, bot in bots do
		local character, rootPart, humanoid = partsOf(bot)
		if character and rootPart and humanoid and humanoid.Health > 0 then
			decide(bot, rootPart.Position)
			walk(bot, character, rootPart, humanoid, now)
		end
	end
end

local function addBot(kind: string): boolean
	local character = botAsset:Clone()
	local member = ParticipantService.addBot(kind, character)
	if member == nil then
		character:Destroy()
		return false
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	table.insert(bots, {
		member = member,
		kind = kind,
		slot = ParticipantService.slotOf(member) :: number,
		dest = "",
		path = {},
		moving = false,
		anchorAt = os.clock(),
		anchorPosition = rootPart.Position,
	})
	return true
end

local function removeLast()
	local bot = table.remove(bots)
	if bot then
		ParticipantService.removeBot(bot.member)
	end
end

-- Loading에 들어가기 직전. 사람 수에 맞춰 봇을 넣고 뺀다(PL-1, PL-2).
-- 새 봇의 총점은 그 순간 가장 낮은 총점이고(ParticipantService가 기록을 만들 때 정해진다), 빼는 봇의 총점은 버린다
local function fill()
	local humans = DevTools.forcedHumans() or ParticipantService.humanCount()
	local want = JoinRules.botCount(humans, Config.BOT_FILL_TO)
	while #bots > want do
		removeLast()
	end
	while #bots < want do
		if not addBot(BotKind.Porter) then
			break
		end
	end
end

function BotService.count(): number
	return #bots
end

function BotService.start()
	local map = workspace:WaitForChild("Map")
	boat = map:WaitForChild("Boat") :: Model
	root = boat:WaitForChild("Root") :: BasePart
	entrance = root:WaitForChild("Entrance") :: Attachment
	botAsset = ServerStorage:WaitForChild("Assets"):WaitForChild("Bots"):WaitForChild("Bot") :: Model
	local beach = map:WaitForChild("Beach")
	spawnSlots = beach:WaitForChild("SpawnSlots")
	for _, kind in { Kind.Small, Kind.Medium, Kind.Large } do
		pileSpots[kind] = beach:WaitForChild("Pile" .. kind) :: BasePart
	end
	-- 경사로의 두 끝. 해변 쪽(Z가 큰 쪽)이 입구다
	local ramp = map:WaitForChild("Dock"):WaitForChild("Ramp") :: BasePart
	local endA = ramp.CFrame * Vector3.new(0, ramp.Size.Y / 2, ramp.Size.Z / 2)
	local endB = ramp.CFrame * Vector3.new(0, ramp.Size.Y / 2, -ramp.Size.Z / 2)
	if endA.Z > endB.Z then
		rampFoot, rampTop = endA, endB
	else
		rampFoot, rampTop = endB, endA
	end

	RoundService.onBeforeLoading(fill)
	-- 사람이 모두 나가 판이 멈추면 봇도 뺀다
	RoundService.onPhaseChanged(function(newPhase)
		if newPhase == nil then
			while #bots > 0 do
				removeLast()
			end
		end
	end)
	RunService.Heartbeat:Connect(step)
end

return BotService
