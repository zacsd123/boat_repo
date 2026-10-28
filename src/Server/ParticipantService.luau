--!strict
-- 참가자 등록부, 슬롯과 색, 상태. 캐릭터의 기본(통과, 점프 없음, 걷는 속도, 나타나는 자리, 안전망).
-- 상자 치우기(S13), P 세기(S13), 봇(S25)은 뒤 단계에서 넓힌다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

local CHARACTER_GROUP = "Characters"
local CARGO_WALL_GROUP = "CargoWall"

local ParticipantService = {}

local slotOfPlayer: { [Player]: number } = {}
local playerInSlot: { [number]: Player? } = {}

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
	humanoid.WalkSpeed = Config.WALK_SPEED

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
	print(`참가자 들어옴: {player.Name} → 슬롯 {slot}`)

	local record = Instance.new("Folder")
	record.Name = tostring(slot)
	record:SetAttribute("IsBot", false)
	record:SetAttribute("UserId", player.UserId)
	record:SetAttribute("Color", Config.PARTICIPANT_COLORS[slot])
	record:SetAttribute("State", Types.ParticipantState.Empty)
	record.Parent = ReplicatedStorage:WaitForChild("Participants")

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
	slotOfPlayer[player] = nil
	playerInSlot[slot] = nil
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

function ParticipantService.slotOf(player: Player): number?
	return slotOfPlayer[player]
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
