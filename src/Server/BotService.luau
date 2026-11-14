--!strict
-- 봇(S25, S27). 사람이 BOT_FILL_TO보다 적으면 모자란 자리를 채운다(PL-1).
-- 봇도 참가자다: ParticipantService가 같은 참가자 기록을 만들고, 들기·놓기·되찾기는 사람의 Tap을 처리하는
-- 그 서버 함수(CrateService.handleTap)를, 끌어안기는 사람의 꾹 누르기를 처리하는 그 함수(handleHoldBegin, handleHoldEnd)를 부른다.
-- 봇용 판정이나 지름길은 없다. 봇의 끌어안기도 HOLD_TIME + HUG_TIME이다.
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

-- 봇의 종류. 참가자 기록의 BotKind에 적힌다(겉모습을 가르는 데 쓴다)
local BotKind = {
	Porter = "Porter", -- 짐꾼: 큰 상자만 나른다(PL-5)
	Saboteur = "Saboteur", -- 방해꾼: 중간 상자 2개를 싣고, 이번 배 1등의 상자를 끌어안는다(PL-6)
	Timid = "Timid", -- 소심이: 중간 상자만 싣고, 첫 종이 울리면 멈추고 자기 상자를 지킨다(PL-7)
}
-- 들어오는 순서. 사람 3명에 짐꾼, 2명에 짐꾼과 방해꾼, 1명에 셋 다. 빠질 때는 뒤에서부터다(GP-13)
local KIND_ORDER = { BotKind.Porter, BotKind.Saboteur, BotKind.Timid }

local SABOTEUR_CRATES = 2 -- 방해꾼이 싣는 중간 상자의 수(PL-6). 규칙에 적힌 수다

-- 길목. 이름은 그때그때 자리를 다시 읽고(배는 무게에 따라 오르내린다), 점은 그대로 쓴다.
-- deck은 배의 Root를 기준으로 한 갑판 위의 자리다
type Waypoint = string | Vector3 | { deck: Vector3 }

type Bot = {
	member: Player,
	kind: string,
	slot: number,
	dest: string, -- 지금 가려는 곳의 이름. 바뀌면 길을 다시 짠다
	path: { Waypoint }, -- 남은 길목
	arriveRadius: number, -- 마지막 길목에 닿았다고 보는 거리
	moving: boolean, -- 걷는 방향을 걸어 둔 상태인지
	anchorAt: number, -- 끼었는지 볼 때의 기준 시각과 자리
	anchorPosition: Vector3,
	lastState: string, -- 지난 프레임의 참가자 상태(끌어안기가 끝난 순간을 알아챈다)
	placed: number, -- 이번 라운드에 실은 상자의 수
	nextLookAt: number, -- 다음에 상황을 살필 때(BOT_REACTION_TIME마다)
	restUntil: number, -- 방해꾼이 쉬는 시간의 끝(SABOTEUR_REST)
	target: Model?, -- 방해꾼이 끌어안으려는 상자
	moveAt: number, -- 보고 나서 움직이기 시작하는 때
	holdCrateId: number?, -- 꾹 누르는 중인 상자
	holdStartedAt: number,
	hugged: { [Model]: boolean }, -- 끌어안긴 것을 이미 본 내 상자
	hugCount: number, -- 내 상자가 끌어안긴 횟수(방해꾼은 두 번에 한 번 되찾는다)
	guard: Model?, -- 되찾으러 가는 내 상자
	guardAt: number, -- 되찾으러 움직이기 시작하는 때
}

-- 걷기의 값(길목을 잇는 방법의 값이다. 규칙의 수치가 아니라 Config에 두지 않는다)
local PASS_RADIUS = 1.5 -- 중간 길목은 이만큼 가까워지면 지난 것으로 본다(멈췄다 가지 않게)
local ARRIVE_RADIUS = 1.2 -- 마지막 길목에 닿았다고 보는 거리
local STAND_RADIUS = 0.4 -- 상자 앞에 다가설 때는 정한 자리에 바짝 선다(벽 쪽으로 한 걸음 다가서는 자리가 있어서)
local PILE_STEP = 2 -- 더미 자리에서 선착장 쪽으로 이만큼 나와 선다(더미 한가운데에 서지 않게)
local AISLE_SPACING = 2.6 -- 통로의 자기 자리 사이 간격(스터드). 슬롯마다 한 자리
local AISLE_FROM_ROOT = 6.2 -- 통로의 자기 자리: 배의 Root에서 선착장 쪽으로(갑판 입구와 화물칸 벽 사이)
local WATER_LANE = 9 -- 물에서 나올 때 걷는 줄. 선착장 밑을 피해 옆으로 이만큼 비켜서 해변으로 간다
local SHORE_Z = 5 -- 물에서 나와 처음 서는 해변의 Z
local OFF_DECK_STEP = 3 -- 소심이가 상자를 내려놓으러 갑판 입구에서 배다리 쪽으로 나가는 거리
-- 화물칸을 도는 통로의 가운데 줄(Root 기준). 화물칸 벽과 갑판 턱 사이다. 봇은 이 줄을 따라 돈다
local RING_X = 10.4
local RING_SOUTH = AISLE_FROM_ROOT
local RING_NORTH = -AISLE_FROM_ROOT
-- 가운뎃줄 칸의 상자는 통로의 가운데 줄에서 TARGET_RANGE를 조금 넘는다. 그런 상자 앞에서는 벽 쪽으로 이만큼 다가선다
local REACH_SOUTH = 5.4
local REACH_NORTH = -5.4
local REACH_MARGIN = 0.3 -- 거리의 끝에 딱 맞춰 서지 않게 두는 여유
local STAND_MARGIN = 0.5 -- 다가설 자리를 고를 때의 여유. 자리에 닿았다고 보는 거리(ARRIVE_RADIUS)만큼 비켜 서도 닿게

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

-- 통로의 자기 자리(Root 기준). 슬롯으로 정한다. 여기서 놓으면 상자가 그 근처 칸에 모인다
local function aisleSpot(bot: Bot): Vector3
	return Vector3.new((bot.slot - (Config.SERVER_MAX_PLAYERS + 1) / 2) * AISLE_SPACING, 0, AISLE_FROM_ROOT)
end

-- 길목의 지금 자리
local function resolve(bot: Bot, waypoint: Waypoint): Vector3
	if typeof(waypoint) == "Vector3" then
		return waypoint
	elseif type(waypoint) == "table" then
		return root.CFrame * waypoint.deck
	elseif waypoint == "rampFoot" then
		return rampFoot
	elseif waypoint == "rampTop" then
		return rampTop
	elseif waypoint == "entrance" then
		return entrance.WorldPosition
	elseif waypoint == "aisle" then
		return root.CFrame * aisleSpot(bot)
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

-- 통로의 줄 위에서의 자리를 한 바퀴의 길이로 나타낸다. 남서 모서리에서 시작해 남쪽 줄, 동쪽 줄, 북쪽 줄, 서쪽 줄 순이다
local RING_DEPTH = RING_SOUTH - RING_NORTH
local RING_LENGTH = 4 * RING_X + 2 * RING_DEPTH
local RING_CORNERS = {
	{ at = 2 * RING_X, point = Vector3.new(RING_X, 0, RING_SOUTH) }, -- 남동
	{ at = 2 * RING_X + RING_DEPTH, point = Vector3.new(RING_X, 0, RING_NORTH) }, -- 북동
	{ at = 4 * RING_X + RING_DEPTH, point = Vector3.new(-RING_X, 0, RING_NORTH) }, -- 북서
	{ at = RING_LENGTH, point = Vector3.new(-RING_X, 0, RING_SOUTH) }, -- 남서
}

-- 갑판 위의 한 점(Root 기준)을 통로의 줄 위로 옮기고, 그 자리의 한 바퀴 길이를 함께 돌려준다
local function snapToRing(point: Vector3): (Vector3, number)
	local x = math.clamp(point.X, -RING_X, RING_X)
	local z = math.clamp(point.Z, RING_NORTH, RING_SOUTH)
	local toSouth, toNorth = math.abs(point.Z - RING_SOUTH), math.abs(point.Z - RING_NORTH)
	local toEast, toWest = math.abs(point.X - RING_X), math.abs(point.X + RING_X)
	local nearest = math.min(toSouth, toNorth, toEast, toWest)
	if nearest == toSouth then
		return Vector3.new(x, 0, RING_SOUTH), x + RING_X
	elseif nearest == toEast then
		return Vector3.new(RING_X, 0, z), 2 * RING_X + (RING_SOUTH - z)
	elseif nearest == toNorth then
		return Vector3.new(x, 0, RING_NORTH), 2 * RING_X + RING_DEPTH + (RING_X - x)
	end
	return Vector3.new(-RING_X, 0, z), 4 * RING_X + RING_DEPTH + (z - RING_NORTH)
end

-- 통로를 따라 한 자리에서 다른 자리로 가는 길(짧은 쪽으로 돈다). 지나는 모서리와 마지막 자리
local function ringRoute(from: Vector3, to: Vector3): { Waypoint }
	local _, startAt = snapToRing(from)
	local goal, goalAt = snapToRing(to)
	local forward = (goalAt - startAt) % RING_LENGTH
	local path: { Waypoint } = {}
	if forward <= RING_LENGTH / 2 then
		-- 앞으로: 시작과 끝 사이에 있는 모서리를 차례로 지난다
		local passed: { { offset: number, point: Vector3 } } = {}
		for _, corner in RING_CORNERS do
			local offset = (corner.at - startAt) % RING_LENGTH
			if offset > 0 and offset < forward then
				table.insert(passed, { offset = offset, point = corner.point })
			end
		end
		table.sort(passed, function(a, b)
			return a.offset < b.offset
		end)
		for _, corner in passed do
			table.insert(path, { deck = corner.point })
		end
	else
		local backward = RING_LENGTH - forward
		local passed: { { offset: number, point: Vector3 } } = {}
		for _, corner in RING_CORNERS do
			local offset = (startAt - corner.at) % RING_LENGTH
			if offset > 0 and offset < backward then
				table.insert(passed, { offset = offset, point = corner.point })
			end
		end
		table.sort(passed, function(a, b)
			return a.offset < b.offset
		end)
		for _, corner in passed do
			table.insert(path, { deck = corner.point })
		end
	end
	table.insert(path, { deck = goal })
	return path
end

-- 실린 상자 하나에 range 안으로 다가설 자리(Root 기준). 통로의 줄 위, 또는 줄에서 벽 쪽으로 다가선 자리다.
-- 지금 자리에서 가장 가까운 것을 고른다
local function approachPoint(crate: Model, range: number, fromLocal: Vector3): Vector3?
	local body = crate.PrimaryPart
	if body == nil then
		return nil
	end
	local at = root.CFrame:PointToObjectSpace(body.Position)
	local x = math.clamp(at.X, -RING_X, RING_X)
	local z = math.clamp(at.Z, RING_NORTH, RING_SOUTH)
	local candidates = {
		Vector3.new(x, 0, RING_SOUTH),
		Vector3.new(x, 0, REACH_SOUTH),
		Vector3.new(x, 0, RING_NORTH),
		Vector3.new(x, 0, REACH_NORTH),
		Vector3.new(RING_X, 0, z),
		Vector3.new(-RING_X, 0, z),
	}
	local best: Vector3? = nil
	local bestDistance = math.huge
	for _, candidate in candidates do
		if flatDistance(candidate, at) <= range - STAND_MARGIN then
			local distance = flatDistance(candidate, fromLocal)
			if distance < bestDistance then
				best, bestDistance = candidate, distance
			end
		end
	end
	return best
end

-- 통로를 돌아 그 자리까지 가는 길. 자리가 줄에서 벗어나 있으면(벽 쪽으로 다가선 자리) 줄 위의 가까운 점을 거쳐 간다
local function routeAlongDeck(fromLocal: Vector3, point: Vector3): { Waypoint }
	local path = ringRoute(fromLocal, point)
	local onRing = snapToRing(point)
	if flatDistance(onRing, point) > 0.05 then
		table.insert(path, { deck = point })
	end
	return path
end

local function setPath(bot: Bot, dest: string, path: { Waypoint }, arriveRadius: number?)
	bot.dest = dest
	bot.path = path
	bot.arriveRadius = arriveRadius or ARRIVE_RADIUS
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

-- 물에 빠졌다. 해변으로 걸어 나온다
local function leaveWater(bot: Bot, position: Vector3)
	if bot.dest ~= "shore" then
		setPath(bot, "shore", routeOutOfWater(position, "rest"))
	end
end

-- 실린 상자 하나에 range 안으로 다가간다. 다가섰으면 true
local function goNearCrate(bot: Bot, position: Vector3, crate: Model, range: number, label: string): boolean
	local body = crate.PrimaryPart
	if body == nil then
		return false
	end
	local onDeck = BoatService.isOnDeck(position)
	if onDeck and flatDistance(position, body.Position) <= range - REACH_MARGIN then
		return true
	end
	local dest = label .. tostring(crate:GetAttribute("CrateId"))
	-- 길을 다 갔는데도 닿지 않으면(밀려났거나 상자가 내려앉았다) 길을 다시 짠다
	if bot.dest ~= dest or #bot.path == 0 then
		if onDeck then
			local from = root.CFrame:PointToObjectSpace(position)
			local point = approachPoint(crate, range, from)
			if point then
				setPath(bot, dest, routeAlongDeck(from, point), STAND_RADIUS)
			end
		else
			-- 갑판 밖이면 입구로 들어와서 통로를 돈다
			local gate = Vector3.new(0, 0, RING_SOUTH)
			local point = approachPoint(crate, range, gate)
			if point then
				local path = routeToDeck(position, { deck = gate })
				for _, waypoint in routeAlongDeck(gate, point) do
					table.insert(path, waypoint)
				end
				setPath(bot, dest, path, STAND_RADIUS)
			end
		end
	end
	return false
end

-- 길을 다 갔는지
local function arrived(bot: Bot, dest: string): boolean
	return bot.dest == dest and #bot.path == 0
end

-- 봇이 버튼을 톡 누른다. 사람의 Tap이 지나는 그 함수다
local function tap(bot: Bot, target: any)
	CrateService.handleTap(bot.member, target)
end

local function belled(): boolean
	return ((boat:GetAttribute("BellCount") :: number?) or 0) >= 1
end

-- 한 종류의 상자를 더미에서 통로의 자기 자리로 나른다. 놓았으면 true
local function haul(bot: Bot, position: Vector3, state: string, kind: string): boolean
	if state == State.Carrying then
		goToAisle(bot, position)
		if arrived(bot, "aisle") and BoatService.isOnDeck(position) then
			tap(bot, nil) -- 놓기
			return ParticipantService.stateOf(bot.member) == State.Empty
		end
	else
		goToBeach(bot, position, kind)
		if arrived(bot, kind) then
			tap(bot, kind) -- 들기
		end
	end
	return false
end

-- 끌어안긴 내 상자를 살핀다. 새로 끌어안긴 것이 있으면 되찾을지 정하고, BOT_REACTION_TIME 뒤에 움직인다.
-- always가 아니면 두 번에 한 번만 되찾는다(PL-6). 되찾으러 가는 중이면 true
local function guardOwn(bot: Bot, position: Vector3, state: string, now: number, always: boolean): boolean
	for _, crate in CrateService.cargoCrates() do
		if crate:IsA("Model") and crate:GetAttribute("OwnerSlot") == bot.slot then
			local isHugged = crate:GetAttribute("HuggedBySlot") ~= nil
			if isHugged and not bot.hugged[crate] then
				bot.hugged[crate] = true
				bot.hugCount += 1
				if (always or bot.hugCount % 2 == 1) and bot.guard == nil then
					bot.guard = crate
					bot.guardAt = now + Config.BOT_REACTION_TIME
				end
			elseif not isHugged and bot.hugged[crate] then
				bot.hugged[crate] = nil
			end
		end
	end
	local crate = bot.guard
	if crate == nil then
		return false
	end
	if crate.Parent == nil or crate:GetAttribute("HuggedBySlot") == nil then
		bot.guard = nil -- 끌어안기가 끝났다(되찾았거나, 늦었거나)
		return false
	end
	-- 빈손이어야 되찾는다(CR-7). 손에 상자가 있으면 못 되찾는다
	if state ~= State.Empty or now < bot.guardAt then
		return state == State.Empty
	end
	if goNearCrate(bot, position, crate, Config.RECLAIM_RANGE, "guard") then
		tap(bot, nil) -- 되찾기. 사람과 같은 조건(거리, 재사용 대기)을 지난다
		bot.guardAt = now + Config.BOT_REACTION_TIME -- 안 됐으면(재사용 대기) 다시 살핀 뒤에 누른다
	end
	return true
end

-- 짐꾼(PL-5): 큰 상자만 나른다. 첫 종이 울리면 손에 든 상자까지만 싣고 갑판에 서 있는다.
-- 황금 상자는 들지 않는다. 끌어안지도 되찾지도 않는다
local function porter(bot: Bot, position: Vector3, state: string)
	if state == State.Carrying or not belled() then
		haul(bot, position, state, Kind.Large)
	else
		-- 새 상자를 가지러 가지 않는다. 통로의 자기 자리에 선다
		goToAisle(bot, position)
	end
end

-- 그 참가자의 상자 가운데 방해꾼이 지금 끌어안을 것(PL-6). 주인이 되찾을 수 있는 때면 없다
local function targetOf(bot: Bot, position: Vector3, leader: Player): Model?
	-- 주인이 되찾을 수 없는 때에만: 갑판에 빈손으로 있는 주인은 3초 안에 자기 상자 어디든 닿는다(BT-9)
	local leaderCharacter = leader.Character
	local leaderRoot = leaderCharacter and leaderCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	local canReclaim = leaderRoot ~= nil
		and ParticipantService.stateOf(leader) == State.Empty
		and BoatService.isOnDeck(leaderRoot.Position)
	if canReclaim then
		return nil
	end
	-- 지금 대상이 될 수 있는 것(끌어안기지 않았고, 2층이 있으면 위 상자) 가운데 점수가 가장 큰 상자. 같으면 가까운 것
	local leaderSlot = ParticipantService.slotOf(leader)
	local target: Model? = nil
	local targetScore, targetDistance = 0, math.huge
	for _, crate in CrateService.cargoCrates() do
		if crate:IsA("Model") and crate:GetAttribute("OwnerSlot") == leaderSlot
			and crate:GetAttribute("HuggedBySlot") == nil and not CrateService.isCovered(crate)
		then
			local body = crate.PrimaryPart
			local kind = crate:GetAttribute("Kind") :: string?
			local score = if kind then Config.CRATE_SCORE[kind] or 0 else 0
			local distance = if body then flatDistance(position, body.Position) else math.huge
			if score > targetScore or (score == targetScore and distance < targetDistance) then
				target, targetScore, targetDistance = crate, score, distance
			end
		end
	end
	return target
end

-- 방해꾼이 끌어안을 상자를 고른다(PL-6): 이번 배 1등의 상자 가운데, 주인이 되찾을 수 없을 때, 가장 큰 것
local function chooseTarget(bot: Bot, position: Vector3): Model?
	-- 이번 배 1등: 머리 위 숫자가 가장 큰 참가자(자기는 뺀다. 0점이면 없다)
	local best = 0
	local scores: { [Player]: number } = {}
	for _, member in ParticipantService.players() do
		local record = ParticipantService.recordOf(member)
		local score = (record and record:GetAttribute("BoatScore") :: number?) or 0
		scores[member] = score
		if member ~= bot.member and score > best then
			best = score
		end
	end
	if best <= 0 then
		return nil
	end
	-- 1등이 여럿이면 아무나다. 그 가운데 끌어안을 상자가 있는 쪽을 고른다
	for _, member in ParticipantService.players() do
		if member ~= bot.member and scores[member] == best then
			local target = targetOf(bot, position, member)
			if target then
				return target
			end
		end
	end
	return nil
end

-- 방해꾼(PL-6): 중간 상자 2개를 싣고 갑판에 머문다. 이번 배 1등의 상자를 끌어안고, 한 번 하면 SABOTEUR_REST 동안 쉰다.
-- 자기 상자는 두 번에 한 번 되찾는다. 황금 상자는 들지 않는다
local function saboteur(bot: Bot, position: Vector3, state: string, now: number)
	if guardOwn(bot, position, state, now, false) then
		return
	end
	if bot.placed < SABOTEUR_CRATES then
		if haul(bot, position, state, Kind.Medium) then
			bot.placed += 1
		end
		return
	end
	-- 꾹 누르는 중: HOLD_TIME이 지나면 뗀다. 사람과 같이 서버가 누른 시간을 잰다(GP-9)
	if bot.holdCrateId ~= nil then
		stop(bot)
		if now - bot.holdStartedAt >= Config.HOLD_TIME then
			local crateId = bot.holdCrateId
			bot.holdCrateId = nil
			bot.target = nil
			CrateService.handleHoldEnd(bot.member, crateId, true)
		end
		return
	end
	-- 쉬는 시간이 아닐 때 BOT_REACTION_TIME마다 본다
	local target = bot.target
	if target ~= nil and (target.Parent == nil or target:GetAttribute("HuggedBySlot") ~= nil or CrateService.isCovered(target)) then
		target = nil
		bot.target = nil
	end
	if target == nil and now >= bot.restUntil and now >= bot.nextLookAt then
		bot.nextLookAt = now + Config.BOT_REACTION_TIME
		target = chooseTarget(bot, position)
		bot.target = target
		bot.moveAt = now + Config.BOT_REACTION_TIME
	end
	if target ~= nil and now >= bot.moveAt then
		if goNearCrate(bot, position, target, Config.TARGET_RANGE, "hug") then
			-- 손 닿는 거리다. 사람과 같은 길로 꾹 누르기 시작한다
			bot.holdCrateId = target:GetAttribute("CrateId") :: number
			bot.holdStartedAt = now
			CrateService.handleHoldBegin(bot.member, bot.holdCrateId)
		end
	elseif target == nil then
		goToAisle(bot, position)
	end
end

-- 소심이(PL-7): 중간 상자만 싣는다. 첫 종이 울리면 멈추고 자기 상자를 지킨다. 항상 되찾는다.
-- 종이 울릴 때 손에 상자가 있으면 싣지 않고 갑판 밖에서 내려놓는다(GP-21)
local function timid(bot: Bot, position: Vector3, state: string, now: number)
	if not belled() then
		-- 종이 울리기 전에도 빈손이면 되찾으러 간다(항상 되찾는다). 멀리 있어 닿지 못하면 못 되찾는다
		if not guardOwn(bot, position, state, now, true) then
			haul(bot, position, state, Kind.Medium)
		end
		return
	end
	if state == State.Carrying then
		if not BoatService.isOnDeck(position) then
			tap(bot, nil) -- 갑판 밖에서 놓으면 사라진다(CR-6)
		elseif bot.dest ~= "offDeck" then
			local gate = entrance.WorldPosition
			setPath(bot, "offDeck", { "entrance", Vector3.new(gate.X, gate.Y, gate.Z + OFF_DECK_STEP) })
		end
		return
	end
	if not guardOwn(bot, position, state, now, true) then
		goToAisle(bot, position) -- 자기 상자 옆에 서 있는다
	end
end

-- 무엇을 할지 고른다. held는 연출로 옮겨지는 중(던져짐, 사다리)인지
local function decide(bot: Bot, position: Vector3, now: number, held: boolean)
	local phase = RoundService.getPhase()
	local state = ParticipantService.stateOf(bot.member) or State.Empty
	-- 끌어안기가 어떻게 끝났든(성공, 되찾기를 당함, 라운드 끝) 그때부터 쉰다(PL-6)
	if bot.lastState == State.Hugging and state ~= State.Hugging then
		bot.restUntil = now + Config.SABOTEUR_REST
		bot.target = nil
	end
	bot.lastState = state

	if phase == Phase.FinalPodium then
		stop(bot) -- 단상에 올려진 봇이 걸어 내려가지 않게
	elseif state == State.InWater then
		-- 던져지는 중에는 기다린다. 물 자리에 닿은 뒤의 자리에서 길을 짜야 한다
		if not held then
			leaveWater(bot, position)
		end
	elseif state == State.Hugging then
		stop(bot) -- 끌어안는 동안은 제자리다(HG-3)
	elseif phase == Phase.Loading then
		if bot.kind == BotKind.Saboteur then
			saboteur(bot, position, state, now)
		elseif bot.kind == BotKind.Timid then
			timid(bot, position, state, now)
		else
			porter(bot, position, state)
		end
	else
		-- 정산 동안에는 더미 근처로 돌아와 선다
		goToBeach(bot, position, "rest")
	end
end

-- 남은 길목을 따라 걷는다. 끼었으면 다음 길목 위로 옮긴다
local function walk(bot: Bot, character: Model, rootPart: BasePart, humanoid: Humanoid, now: number)
	local position = rootPart.Position
	while #bot.path > 0 do
		local radius = if #bot.path == 1 then bot.arriveRadius else PASS_RADIUS
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
		print(`봇이 끼어서 옮김: {bot.member.Name} (슬롯 {bot.slot}, {bot.kind}) → {bot.dest}`)
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
			decide(bot, rootPart.Position, now, rootPart.Anchored)
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
	local bot: Bot = {
		member = member,
		kind = kind,
		slot = ParticipantService.slotOf(member) :: number,
		dest = "",
		path = {},
		arriveRadius = ARRIVE_RADIUS,
		moving = false,
		anchorAt = os.clock(),
		anchorPosition = rootPart.Position,
		lastState = State.Empty :: string,
		placed = 0,
		nextLookAt = 0,
		restUntil = 0,
		target = nil,
		moveAt = 0,
		holdCrateId = nil,
		holdStartedAt = 0,
		hugged = {},
		hugCount = 0,
		guard = nil,
		guardAt = 0,
	}
	table.insert(bots, bot)
	return true
end

local function removeLast()
	local bot = table.remove(bots)
	if bot then
		ParticipantService.removeBot(bot.member)
	end
end

-- Loading에 들어가기 직전. 사람 수에 맞춰 봇을 넣고 뺀다(PL-1, PL-2, GP-13).
-- 새 봇의 총점은 그 순간 가장 낮은 총점이고(ParticipantService가 기록을 만들 때 정해진다), 빼는 봇의 총점은 버린다
local function fill()
	local humans = DevTools.forcedHumans() or ParticipantService.humanCount()
	local want = math.min(JoinRules.botCount(humans, Config.BOT_FILL_TO), #KIND_ORDER)
	while #bots > want do
		removeLast()
	end
	while #bots < want do
		if not addBot(KIND_ORDER[#bots + 1]) then
			break
		end
	end
	-- 새 라운드: 라운드마다 다시 세는 것들을 비운다
	for _, bot in bots do
		bot.placed = 0
		bot.target = nil
		bot.holdCrateId = nil
		bot.guard = nil
		table.clear(bot.hugged)
	end
end

function BotService.count(): number
	return #bots
end

-- 시험용(DevTools): 봇마다 지금 무엇을 하려는지 한 줄씩
function BotService.describe(): { string }
	local now = os.clock()
	local lines = {}
	for _, bot in bots do
		local nextWaypoint = bot.path[1]
		local nextText = "-"
		if nextWaypoint ~= nil then
			local point = resolve(bot, nextWaypoint)
			nextText = string.format("(%.1f, %.1f)", point.X, point.Z)
		end
		local target = bot.target
		local guard = bot.guard
		table.insert(lines, string.format(
			"슬롯 %d %s: 가는 곳=%s 남은 길목=%d 다음=%s 실은 수=%d 대상=%s 꾹=%s 쉬는 시간 %.1f초 지키는 상자=%s 끌어안긴 횟수=%d",
			bot.slot, bot.kind, bot.dest, #bot.path, nextText, bot.placed,
			if target then target.Name else "-", tostring(bot.holdCrateId),
			math.max(bot.restUntil - now, 0), if guard then guard.Name else "-", bot.hugCount
		))
	end
	return lines
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
