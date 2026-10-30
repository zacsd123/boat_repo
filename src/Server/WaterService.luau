--!strict
-- 물에 빠진 상태, 나오는 길(해변, 사다리), 물에 던져 넣기, 침몰 때 갑판 위 사람.
-- 물속인지는 캐릭터의 발이 수면(물 구역의 윗면) 아래에 있는지로 본다. 이 맵의 물은 가슴 높이라
-- 캐릭터 중심은 늘 수면 위에 있어서, 중심으로 보면 아무도 물에 빠지지 않는다(S12 판단 기록).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local ParticipantService = require(script.Parent.ParticipantService)
local RoundService = require(script.Parent.RoundService)
local BoatService = require(script.Parent.BoatService)
local CrateService = require(script.Parent.CrateService)

local State = Types.ParticipantState
local Phase = Types.Phase

local WaterService = {}

local waterZone: BasePart
local ladderZones: { [BasePart]: BasePart } = {} -- 사다리 구역 → 사다리 파트(Top, Bottom 표시점)
local waterSpots: { BasePart } = {}
local fx: RemoteEvent
local busy: { [Player]: boolean } = {} -- 사다리를 오르거나 날아가는 중. 그동안은 물 판정을 하지 않는다

local function inside(zone: BasePart, point: Vector3): boolean
	local localPoint = zone.CFrame:PointToObjectSpace(point)
	local half = zone.Size / 2
	return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z
end

-- 바닥 위(X, Z)로만 본다. 사다리 구역은 배에 붙어 있어 배가 내려가면 바다 바닥 아래로 들어가기 때문이다
local function insideFlat(zone: BasePart, point: Vector3): boolean
	return inside(zone, Vector3.new(point.X, zone.Position.Y, point.Z))
end

local function parts(player: Player): (Model?, BasePart?, Humanoid?)
	local character = player.Character
	if character == nil then
		return nil, nil, nil
	end
	return character, character:FindFirstChild("HumanoidRootPart") :: BasePart?, character:FindFirstChildOfClass("Humanoid")
end

-- 캐릭터의 발 높이에 있는 점
local function feet(rootPart: BasePart, humanoid: Humanoid): Vector3
	return rootPart.Position - Vector3.new(0, rootPart.Size.Y / 2 + humanoid.HipHeight, 0)
end

-- 바닥 점 위에 캐릭터를 세울 때 HumanoidRootPart가 있을 높이
local function standOn(point: Vector3, rootPart: BasePart, humanoid: Humanoid): Vector3
	return point + Vector3.new(0, rootPart.Size.Y / 2 + humanoid.HipHeight, 0)
end

-- 물에 들어간 순간. 든 상자는 놓친다(CR-9). 상태와 속도를 한 함수에서 바꾼다
local function enterWater(player: Player, at: Vector3)
	if ParticipantService.stateOf(player) == State.Carrying then
		CrateService.dropCarried(player)
	end
	ParticipantService.setState(player, State.InWater, nil)
	fx:FireAllClients("Splash", at)
end

local function leaveWater(player: Player)
	ParticipantService.setState(player, State.Empty, nil)
end

-- 사다리 오르기(WT-1). 배가 높든 낮든 LADDER_CLIMB_TIME 동안 정해진 연출로 오른다.
-- 오르는 중에 라운드가 끝나면(배가 없어지므로) 멈추고 사다리 밑 물에 남는다
local function climb(player: Player, ladder: BasePart)
	local character, rootPart, humanoid = parts(player)
	if character == nil or rootPart == nil or humanoid == nil then
		return
	end
	busy[player] = true
	rootPart.Anchored = true
	local from = rootPart.Position
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		if character.Parent == nil then
			connection:Disconnect()
			busy[player] = nil
			return
		end
		local top = (ladder:FindFirstChild("Top") :: Attachment).WorldPosition
		if RoundService.getPhase() ~= Phase.Loading then
			-- 배가 떠나거나 가라앉았다: 사다리 밑 물에 남는다
			connection:Disconnect()
			local bottom = (ladder:FindFirstChild("Bottom") :: Attachment).WorldPosition
			character:PivotTo(CFrame.new(standOn(Vector3.new(bottom.X, from.Y - rootPart.Size.Y / 2 - humanoid.HipHeight, bottom.Z), rootPart, humanoid)))
			rootPart.Anchored = false
			busy[player] = nil
			return
		end
		local progress = math.min((os.clock() - started) / Config.LADDER_CLIMB_TIME, 1)
		local target = standOn(top, rootPart, humanoid)
		character:PivotTo(CFrame.new(from:Lerp(target, progress)))
		if progress >= 1 then
			connection:Disconnect()
			rootPart.Anchored = false
			rootPart.AssemblyLinearVelocity = Vector3.zero
			busy[player] = nil
			leaveWater(player)
		end
	end)
end

local function step()
	for _, player in ParticipantService.players() do
		if busy[player] then
			continue
		end
		local _, rootPart, humanoid = parts(player)
		if rootPart == nil or humanoid == nil or humanoid.Health <= 0 then
			continue
		end
		local state = ParticipantService.stateOf(player)
		-- 갑판 위는 물이 아니다(GP-11). 무게가 위 끝에 가까우면 갑판 바닥이 수면보다 낮아지기 때문이다
		local wet = inside(waterZone, feet(rootPart, humanoid)) and not BoatService.isOnDeck(rootPart.Position)
		if state ~= State.InWater and state ~= State.Hugging and wet then
			enterWater(player, rootPart.Position)
		elseif state == State.InWater then
			if not wet and not BoatService.isOnDeck(rootPart.Position) then
				-- 해변으로 걸어 나왔다. 가라앉는 갑판 위(침몰 직후)는 나온 것이 아니다
				leaveWater(player)
			elseif RoundService.getPhase() == Phase.Loading then
				-- 사다리는 배가 선착장에 있을 때(Loading)만 있다
				for zone, ladder in ladderZones do
					if insideFlat(zone, rootPart.Position) then
						climb(player, ladder)
						break
					end
				end
			end
		end
	end
end

-- 가까운 물 자리로 포물선을 그려 던져 넣는다(GP-8). S18, S19가 쓴다. 상태는 던지는 순간 InWater
function WaterService.throwIn(player: Player)
	local character, rootPart, humanoid = parts(player)
	if character == nil or rootPart == nil or humanoid == nil or busy[player] then
		return
	end
	local spot = waterSpots[1]
	for _, candidate in waterSpots do
		if (candidate.Position - rootPart.Position).Magnitude < (spot.Position - rootPart.Position).Magnitude then
			spot = candidate
		end
	end
	enterWater(player, spot.Position)
	busy[player] = true
	rootPart.Anchored = true
	local from = rootPart.Position
	local to = standOn(spot.Position + Vector3.new(0, spot.Size.Y / 2, 0), rootPart, humanoid)
	local duration = Config.WATER_THROW_TIME
	local gravity = workspace.Gravity
	-- 중력으로 떨어지는 포물선: 시작 속도를 정해 duration 뒤에 정확히 물 자리에 닿게 한다
	local upward = (to.Y - from.Y + gravity * duration * duration / 2) / duration
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		if character.Parent == nil then
			connection:Disconnect()
			busy[player] = nil
			return
		end
		local t = math.min(os.clock() - started, duration)
		local flat = from:Lerp(to, t / duration)
		local height = from.Y + upward * t - gravity * t * t / 2
		character:PivotTo(CFrame.new(flat.X, height, flat.Z))
		if t >= duration then
			connection:Disconnect()
			rootPart.Anchored = false
			rootPart.AssemblyLinearVelocity = Vector3.zero
			busy[player] = nil
		end
	end)
end

function WaterService.start()
	local map = workspace:WaitForChild("Map")
	local zones = map:WaitForChild("Zones")
	waterZone = zones:WaitForChild("WaterZone") :: BasePart
	local ladders = map:WaitForChild("Boat"):WaitForChild("Ladders")
	for _, side in { "East", "West" } do
		ladderZones[zones:WaitForChild("LadderZone" .. side) :: BasePart] = ladders:WaitForChild(side) :: BasePart
	end
	local sea = map:WaitForChild("Sea")
	for _, name in { "WaterSpotEast", "WaterSpotWest" } do
		table.insert(waterSpots, sea:WaitForChild(name) :: BasePart)
	end
	fx = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Fx") :: RemoteEvent

	-- 침몰하면 갑판 위 사람은 모두 물에 빠진다(WT-4). 배가 내려가며 바다 바닥에 서게 된다
	RoundService.onPhaseChanged(function(newPhase)
		if newPhase ~= Phase.Sinking then
			return
		end
		for _, player in ParticipantService.players() do
			local _, rootPart = parts(player)
			if rootPart and BoatService.isOnDeck(rootPart.Position) and ParticipantService.stateOf(player) ~= State.InWater then
				enterWater(player, rootPart.Position)
			end
		end
	end)

	RunService.Heartbeat:Connect(step)
end

return WaterService
