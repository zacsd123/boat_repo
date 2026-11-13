--!strict
-- 참가자 등록부, 슬롯과 색, 상태. 캐릭터의 기본(통과, 점프 없음, 걷는 속도, 나타나는 자리, 안전망).
-- 참가자는 사람(Player)이거나 봇이다(S25). 봇도 같은 표와 같은 참가자 기록을 쓴다. players()는 둘 다 돌려준다.

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
local joinedListeners: { (player: Player, slot: number) -> () } = {}
-- 새 참가자의 시작 총점을 정하는 함수(S24). MatchService가 건다. 걸리기 전에는 0이다
local startTotal: ((userId: number) -> number)? = nil
local botOf: { [Player]: boolean } = {} -- 봇인 참가자(S25)
local botSerial = 0 -- 봇에게 주는 일련번호. 계정 번호 자리에 음수로 넣어 사람과 겹치지 않게 한다
local botFolder: Instance -- Workspace.Bots. 봇의 몸이 여기 있다

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

-- 참가자 하나를 등록한다. 사람과 봇이 같은 자리(슬롯, 색, 참가자 기록)를 쓴다(GP-14).
-- botKind를 주면 봇이다
local function register(member: Player, botKind: string?): number?
	local slot = freeSlot()
	if slot == nil then
		warn(`참가자 슬롯이 없다: {member.Name}`)
		return nil
	end
	slotOfPlayer[member] = slot
	playerInSlot[slot] = member
	joinedAt[member] = workspace:GetServerTimeNow()
	print(`참가자 들어옴: {member.Name} → 슬롯 {slot}{if botKind then ` (봇 {botKind})` else ""}`)

	local record = Instance.new("Folder")
	record.Name = tostring(slot)
	record:SetAttribute("IsBot", botKind ~= nil)
	record:SetAttribute("BotKind", botKind or "") -- 봇의 종류. 겉모습을 가르는 데만 쓴다(S27)
	record:SetAttribute("UserId", member.UserId)
	record:SetAttribute("Color", Config.PARTICIPANT_COLORS[slot])
	record:SetAttribute("State", Types.ParticipantState.Empty)
	record:SetAttribute("Carrying", "")
	record:SetAttribute("BoatScore", 0)
	-- 도중에 들어온 참가자는 그 순간 가장 낮은 총점에서 시작한다(JN-1). 값은 MatchService가 정한다
	record:SetAttribute("TotalScore", if startTotal then startTotal(member.UserId) else 0)
	record:SetAttribute("Hat", false)
	record:SetAttribute("Crown", false)
	record.Parent = ReplicatedStorage:WaitForChild("Participants")
	recordOf[member] = record
	for _, listener in joinedListeners do
		listener(member, slot)
	end
	return slot
end

-- 참가자 하나를 지운다. 기록을 지우기 전에 든 상자와 갑판의 상자를 먼저 치운다(JN-2).
-- 순서가 바뀌면 주인 없는 상자가 남는다
local function unregister(member: Player)
	local slot = slotOfPlayer[member]
	print(`참가자 나감: {member.Name} (슬롯 {slot})`)
	if slot == nil then
		return
	end
	ParticipantService.cleanupFor(member)
	slotOfPlayer[member] = nil
	playerInSlot[slot] = nil
	recordOf[member] = nil
	joinedAt[member] = nil
	hadInput[member] = nil
	startPosition[member] = nil
	botOf[member] = nil
	local record = ReplicatedStorage:WaitForChild("Participants"):FindFirstChild(tostring(slot))
	if record then
		record:Destroy()
	end
end

local function onPlayerAdded(player: Player)
	if register(player, nil) == nil then
		return
	end
	player.CharacterAdded:Connect(function(character)
		setUpCharacter(player, character)
	end)
	if player.Character then
		task.spawn(setUpCharacter, player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	unregister(player)
end

-- 봇을 참가자로 넣는다(S25). 봇은 Player가 아니지만, 사람과 같은 서버 함수를 지나도록
-- Player와 같은 이름의 값(Name, UserId, Character)을 가진 표를 만들어 사람과 같은 자리에 넣는다.
-- 그래서 서비스들의 인자 타입은 그대로 Player다. 진짜 Player에만 있는 것(FireClient 같은 것)을 쓰기 전에는 isBot으로 가른다.
-- character는 BotService가 만든 봇의 몸이다. 슬롯이 없으면 nil
function ParticipantService.addBot(kind: string, character: Model): Player?
	botSerial += 1
	local member = ({ Name = `Bot{botSerial}`, UserId = -botSerial, Character = character } :: any) :: Player
	botOf[member] = true
	local slot = register(member, kind)
	if slot == nil then
		botOf[member] = nil
		return nil
	end
	character.Name = tostring(slot) -- 클라이언트가 슬롯 번호로 봇의 몸을 찾는다
	character.Parent = botFolder
	setUpCharacter(member, character)
	-- 봇의 물리는 서버가 맡는다. 가까운 사람의 클라이언트로 넘어가면 그 사람의 통신 상태에 따라 버벅인다
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if rootPart then
		rootPart:SetNetworkOwner(nil)
	end
	return member
end

-- 봇을 뺀다. 그 봇의 상자와 기록이 사람이 나갈 때와 같이 치워지고, 몸도 사라진다
function ParticipantService.removeBot(member: Player)
	if not botOf[member] then
		return
	end
	local character = member.Character
	unregister(member)
	if character then
		character:Destroy()
	end
end

function ParticipantService.isBot(member: Player): boolean
	return botOf[member] == true
end

-- 사람 참가자의 수(봇은 뺀다)
function ParticipantService.humanCount(): number
	local count = 0
	for member in slotOfPlayer do
		if not botOf[member] then
			count += 1
		end
	end
	return count
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

-- 참가자 기록이 만들어진 직후 부를 함수를 건다
function ParticipantService.onJoined(listener: (player: Player, slot: number) -> ())
	table.insert(joinedListeners, listener)
end

-- 새 참가자의 시작 총점을 정하는 함수를 건다(S24)
function ParticipantService.setStartTotal(rule: (userId: number) -> number)
	startTotal = rule
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
		-- 봇은 늘 "입력이 있었던" 참가자다(JN-5)
		table.insert(counted, { isBot = botOf[player] == true, hadInput = input, justJoined = justJoined })
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

-- 그 슬롯의 참가자. 비어 있으면 nil
function ParticipantService.playerOf(slot: number): Player?
	return playerInSlot[slot]
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

-- 상태와 든 상자를 바꾼다. 걷는 속도도 여기서 함께 바꾼다(빈손인데 느린 상태가 생기지 않게).
-- 0은 Config의 수치가 아니라 "움직이지 못한다"는 뜻이다
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
		-- 끌어안는 동안은 제자리다(HG-3). 물속은 WATER_SPEED, 그 밖에는 든 상자에 맞춘 속도
		if state == Types.ParticipantState.Hugging then
			humanoid.WalkSpeed = 0
		elseif state == Types.ParticipantState.InWater then
			humanoid.WalkSpeed = Config.WATER_SPEED
		else
			humanoid.WalkSpeed = Config.carrySpeed(carrying or Types.ParticipantState.Empty)
		end
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
	botFolder = workspace:WaitForChild("Bots")

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
