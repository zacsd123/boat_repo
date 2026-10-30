--!strict
-- 참가자 등록부, 슬롯과 색, 상태. 캐릭터의 기본(통과, 점프 없음, 걷는 속도, 나타나는 자리, 안전망).
-- 상자 치우기(S13), P 세기(S13), 봇(S25)은 뒤 단계에서 넓힌다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local JoinRules = require(ReplicatedStorage.Shared.Rules.JoinRules)

local CHARACTER_GROUP = "Characters"
local CARGO_WALL_GROUP = "CargoWall"

local ParticipantService = {}

local slotOfPlayer: { [Player]: number } = {}
local playerInSlot: { [number]: Player? } = {}
local recordOf: { [Player]: Folder? } = {}

-- 입력이 있었는지(GP-10)와 들어온 때. 서버가 직접 잰다. 클라이언트에 묻지 않는다
local joinedAt: { [Player]: number } = {} -- 들어온 서버 시각
local roundStartedAt: number? = nil -- 지난(지금) 라운드가 시작된 서버 시각. 첫 라운드 전에는 nil
local hadInput: { [Player]: boolean } = {} -- 이번 라운드에 입력이 있었는지
local startPosition: { [Player]: Vector3? } = {} -- 이번 라운드가 시작될 때 캐릭터가 있던 자리
local leavingListeners: { (player: Player, slot: number) -> () } = {}

local spawnSlots: Instance -- Map.Beach.SpawnSlots
local seaFloor: BasePart -- Map.Sea.Floor

-- 캐릭터끼리만 통과한다(WT-5). 화물칸 벽은 캐릭터만 막는다(GP-3)
local function setUpCollisionGroups()
	for _, group in { CHARACTER_GROUP, CARGO_WALL_GROUP } do
		if not workspace:IsCollisionGroupRegistered(group) then
			workspace:RegisterCollisionGroup(group)
		end
	end
	workspace:CollisionGroupSetCollidable(CHARACTER_GROUP, CHARACTER_GROUP, false)
	workspace:CollisionGroupSetCollidable(CARGO_WALL_GROUP, "Default", false)
	workspace:CollisionGroupSetCollidable(CARGO_WALL_GROUP, CHARACTER_GROUP, true)
end

-- 새로 생기는 캐릭터에 쓰일 값. 점프 없음(GP-1), 빈손 걷는 속도
local function setUpStarterPlayer()
	StarterPlayer.CharacterUseJumpPower = true
	StarterPlayer.CharacterJumpPower = 0
	StarterPlayer.AutoJumpEnabled = false
	StarterPlayer.CharacterWalkSpeed = Config.WALK_SPEED
end

-- 비어 있는 가장 작은 슬롯
local function freeSlot(): number?
	for slot = 1, Config.SERVER_MAX_PLAYERS do
		if playerInSlot[slot] == nil then
			return slot
		end
	end
	return nil
end

-- 슬롯의 스폰 자리. 더미 쪽(북쪽)을 보고 선다
local function spawnCFrame(slot: number): CFrame
	local spot = spawnSlots:FindFirstChild("Slot" .. slot) :: BasePart
	local position = spot.Position + Vector3.new(0, spot.Size.Y / 2, 0)
	return CFrame.lookAt(position, position - Vector3.zAxis)
end

local function putInGroup(part: Instance)
	if part:IsA("BasePart") then
		part.CollisionGroup = CHARACTER_GROUP
	end
end

local function setUpCharacter(player: Player, character: Model)
	-- 나중에 붙는 장신구까지 캐릭터 그룹에 넣는다
	for _, descendant in character:GetDescendants() do
		putInGroup(descendant)
	end
	character.DescendantAdded:Connect(putInGroup)

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.AutoJumpEnabled = false
	-- 새 캐릭터는 빈손이다(든 상자는 옛 캐릭터와 함께 사라졌다)
	ParticipantService.setState(player, Types.ParticipantState.Empty, nil)

	local slot = slotOfPlayer[player]
	if slot ~= nil then
		character:WaitForChild("HumanoidRootPart")
		local height = humanoid.HipHeight + (character.PrimaryPart :: BasePart).Size.Y / 2
		character:PivotTo(spawnCFrame(slot) + Vector3.new(0, height, 0))
	end
end

local function onPlayerAdded(player: Player)
	local slot = freeSlot()
	if slot == nil then
		warn(`참가자 슬롯이 없다: {player.Name}`)
		return
	end
	slotOfPlayer[player] = slot
	playerInSlot[slot] = player
	joinedAt[player] = workspace:GetServerTimeNow()
	print(`참가자 들어옴: {player.Name} → 슬롯 {slot}`)

	local record = Instance.new("Folder")
	record.Name = tostring(slot)
	record:SetAttribute("IsBot", false)
	record:SetAttribute("UserId", player.UserId)
	record:SetAttribute("Color", Config.PARTICIPANT_COLORS[slot])
	record:SetAttribute("State", Types.ParticipantState.Empty)
	record:SetAttribute("Carrying", "")
	record:SetAttribute("BoatScore", 0)
	record:SetAttribute("Hat", false)
	record.Parent = ReplicatedStorage:WaitForChild("Participants")
	recordOf[player] = record

	player.CharacterAdded:Connect(function(character)
		setUpCharacter(player, character)
	end)
	if player.Character then
		task.spawn(setUpCharacter, player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	local slot = slotOfPlayer[player]
	print(`참가자 나감: {player.Name} (슬롯 {slot})`)
	if slot == nil then
		return
	end
	-- 기록을 지우기 전에 든 상자와 갑판의 상자를 먼저 치운다(JN-2). 순서가 바뀌면 주인 없는 상자가 남는다
	ParticipantService.cleanupFor(player)
	slotOfPlayer[player] = nil
	playerInSlot[slot] = nil
	recordOf[player] = nil
	joinedAt[player] = nil
	hadInput[player] = nil
	startPosition[player] = nil
	local record = ReplicatedStorage:WaitForChild("Participants"):FindFirstChild(tostring(slot))
	if record then
		record:Destroy()
	end
end

-- 안전망: 바다 바닥보다 아래로 빠진 캐릭터는 슬롯 자리로 되돌린다.
-- 죽으면 Roblox가 바로 다시 내보내고(RespawnTime 0), 그때 슬롯 자리에 선다
local function watchFallen()
	local lowest = seaFloor.Position.Y - seaFloor.Size.Y
	RunService.Heartbeat:Connect(function()
		for player, slot in slotOfPlayer do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if character and root and root.Position.Y < lowest then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				local height = (humanoid and humanoid.HipHeight or 0) + root.Size.Y / 2
				character:PivotTo(spawnCFrame(slot) + Vector3.new(0, height, 0))
				root.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end)
end

-- 나가는 사람의 뒷정리(onLeaving에 건 함수들). 나가기 직전에 부른다. DevTools 시험에서도 쓴다
function ParticipantService.cleanupFor(player: Player)
	local slot = slotOfPlayer[player]
	if slot == nil then
		return
	end
	for _, listener in leavingListeners do
		listener(player, slot)
	end
end

-- 참가자가 나가기 직전(기록이 아직 있을 때) 부를 함수를 건다
function ParticipantService.onLeaving(listener: (player: Player, slot: number) -> ())
	table.insert(leavingListeners, listener)
end

local function rootPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end

-- 버튼을 눌렀다(Tap). 입력이 있었던 것으로 적는다
function ParticipantService.markInput(player: Player)
	if startPosition[player] ~= nil then
		hadInput[player] = true
	end
end

-- Loading에 들어가는 순간. 지난 라운드의 기록으로 P를 세고(JN-4, JN-5), 이번 라운드의 기록을 새로 시작한다.
-- 지난 라운드에 입력이 있었던 사람과 지난 라운드가 시작된 뒤에 들어온 사람을 센다. 서버의 첫 라운드는 전원
function ParticipantService.beginRound(): number
	local counted: { JoinRules.Counted } = {}
	local idle = {}
	for player in slotOfPlayer do
		local justJoined = roundStartedAt == nil or (joinedAt[player] or 0) > (roundStartedAt :: number)
		local input = hadInput[player] == true
		table.insert(counted, { isBot = false, hadInput = input, justJoined = justJoined })
		if not input and not justJoined then
			table.insert(idle, player.Name)
		end
	end
	local p = JoinRules.countP(counted)
	print(`P={p} (참가자 {#counted}명{if #idle > 0 then `, 입력 없던 사람 {table.concat(idle, ", ")}` else ""})`)

	roundStartedAt = workspace:GetServerTimeNow()
	for player in slotOfPlayer do
		hadInput[player] = false
		startPosition[player] = rootPosition(player) or Vector3.zero
	end
	return p
end

-- Loading 동안 매 프레임: 시작 자리에서 IDLE_MOVE_THRESHOLD 넘게 움직였으면 입력이 있던 것(GP-10)
function ParticipantService.watchMovement()
	for player, start in startPosition do
		if not hadInput[player] then
			local position = rootPosition(player)
			if position and start and (position - start).Magnitude > Config.IDLE_MOVE_THRESHOLD then
				hadInput[player] = true
			end
		end
	end
end

-- 라운드가 끝나면 움직임을 그만 잰다(기록은 다음 Loading의 P 세기에 쓴다)
function ParticipantService.endRound()
	table.clear(startPosition)
end

function ParticipantService.slotOf(player: Player): number?
	return slotOfPlayer[player]
end

-- 참가자 기록 폴더(ReplicatedStorage.Participants.<슬롯>)
function ParticipantService.recordOf(player: Player): Folder?
	return recordOf[player]
end

function ParticipantService.colorOf(slot: number): Color3
	return Config.PARTICIPANT_COLORS[slot]
end

function ParticipantService.stateOf(player: Player): string?
	local record = recordOf[player]
	return record and record:GetAttribute("State") :: string?
end

function ParticipantService.carryingOf(player: Player): string?
	local record = recordOf[player]
	local carrying = record and record:GetAttribute("Carrying")
	if carrying == "" then
		return nil
	end
	return carrying :: string?
end

-- 상태와 든 상자를 바꾼다. 걷는 속도도 여기서 함께 바꾼다(빈손인데 느린 상태가 생기지 않게)
function ParticipantService.setState(player: Player, state: string, carrying: string?)
	local record = recordOf[player]
	if record == nil then
		return
	end
	record:SetAttribute("State", state)
	record:SetAttribute("Carrying", carrying or "")
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = if state == Types.ParticipantState.InWater
			then Config.WATER_SPEED
			else Config.carrySpeed(carrying or Types.ParticipantState.Empty)
	end
end

function ParticipantService.players(): { Player }
	local list = {}
	for player in slotOfPlayer do
		table.insert(list, player)
	end
	return list
end

function ParticipantService.start()
	local map = workspace:WaitForChild("Map")
	spawnSlots = map:WaitForChild("Beach"):WaitForChild("SpawnSlots")
	seaFloor = map:WaitForChild("Sea"):WaitForChild("Floor") :: BasePart

	setUpCollisionGroups()
	setUpStarterPlayer()
	Players.RespawnTime = 0
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	watchFallen()
end

return ParticipantService
