--!strict
-- 버튼 하나. 톡 누르기와 꾹 누르기(S17). 대상 찾기와 테두리, 버튼 그림, 꾹 누르는 동안의 고리.
-- 누르면 Tap, HoldBegin, HoldEnd만 보낸다. 상자가 손에 붙거나 화물칸에 생기는 것은 서버가 바꾼 상태를 보고 그린다.
-- 무엇이 될지는 InputRules에 서버와 같은 상황을 넣어 고른다. 글자는 쓰지 않는다(그림은 디자인 전 임시).
-- 꾹 누른 시간은 여기서 재서 고리를 그리지만, 채웠는지의 확인은 서버가 한다(GP-9).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local InputRules = require(ReplicatedStorage.Shared.Rules.InputRules)
local HudLayout = require(script.Parent.HudLayout)
local RingGui = require(script.Parent.RingGui)

local State = Types.ParticipantState
local Kind = Types.CrateKind
local Phase = Types.Phase

local InputController = {}

local PILE_KINDS = { Kind.Small, Kind.Medium, Kind.Large }
local ACTION_NAME = "BoatButton"
local BUTTON_NAME = "ActionButton"
-- 키보드 키 하나와 게임패드 버튼 하나. 점프를 껐으므로 A 버튼은 비어 있다
local KEYS = { Enum.KeyCode.E, Enum.KeyCode.ButtonA }

local WHITE = Color3.fromRGB(255, 255, 255)
local HINT_TIME = 0.35 -- 힌트 고리가 비치는 시간(초). 모양의 값이다

-- 그림마다 색. 놓기와 버리기는 확실히 다르게 그린다. ring은 꾹 눌러야 하는 대상 앞의 고리 모양(IN-7)
type Look = { color: Color3, raised: boolean, cross: boolean, ring: boolean }
local LOOK: { [string]: Look } = {
	Pickup = { color = Color3.fromRGB(70, 170, 90), raised = true, cross = false, ring = false },
	Place = { color = Color3.fromRGB(60, 120, 220), raised = false, cross = false, ring = false },
	Discard = { color = Color3.fromRGB(210, 60, 60), raised = false, cross = true, ring = false },
	DropGold = { color = Color3.fromRGB(210, 60, 60), raised = false, cross = true, ring = false },
	Repick = { color = Color3.fromRGB(60, 60, 60), raised = false, cross = false, ring = true },
	Hug = { color = Color3.fromRGB(60, 60, 60), raised = false, cross = false, ring = true },
	-- 되찾기: 눈에 띄는 주황 바탕에 들어 올린 상자. 누르는 순간 된다(GP-19)
	Reclaim = { color = Color3.fromRGB(245, 140, 30), raised = true, cross = false, ring = false },
}
local RING_COLOR: { [string]: Color3 } = {
	Repick = WHITE, -- 내 상자는 흰 고리(IN-6)
	Hug = HudLayout.HUG_COLOR, -- 남의 상자는 빨간 고리
}

local HOLD_SETTINGS: InputRules.HoldSettings = {
	holdTime = Config.HOLD_TIME,
	holdTolerance = Config.HOLD_TOLERANCE,
	hugEnabled = Config.HUG_ENABLED,
}

local player = Players.LocalPlayer

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function inside(zone: BasePart, point: Vector3): boolean
	local localPoint = zone.CFrame:PointToObjectSpace(point)
	local half = zone.Size / 2
	return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z
end

-- 내 참가자 기록
local function myRecord(): Instance?
	local participants = ReplicatedStorage:FindFirstChild("Participants")
	if participants == nil then
		return nil
	end
	for _, record in participants:GetChildren() do
		if record:GetAttribute("UserId") == player.UserId then
			return record
		end
	end
	return nil
end

-- 버튼 모양을 만든다: 둥근 판 + 가운데 상자 + 버리기용 X + 꾹 누르기용 고리
local function buildButton(hud: Instance): ImageButton
	local button = Instance.new("ImageButton")
	button.Name = BUTTON_NAME
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -HudLayout.EDGE, 1, -HudLayout.EDGE)
	button.Size = UDim2.fromOffset(HudLayout.BUTTON_SIZE, HudLayout.BUTTON_SIZE)
	button.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	button.AutoButtonColor = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = button

	local crate = Instance.new("Frame")
	crate.Name = "Crate"
	crate.AnchorPoint = Vector2.new(0.5, 0.5)
	crate.Size = UDim2.fromScale(0.36, 0.36)
	crate.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
	crate.BorderSizePixel = 0
	crate.Parent = button

	local floor = Instance.new("Frame")
	floor.Name = "Floor"
	floor.AnchorPoint = Vector2.new(0.5, 0.5)
	floor.Position = UDim2.fromScale(0.5, 0.75)
	floor.Size = UDim2.fromScale(0.56, 0.05)
	floor.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
	floor.BorderSizePixel = 0
	floor.Parent = button

	for _, angle in { 45, -45 } do
		local bar = Instance.new("Frame")
		bar.Name = "Cross"
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromScale(0.7, 0.08)
		bar.Rotation = angle
		bar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		bar.BorderSizePixel = 0
		bar.Parent = button
	end

	-- 꾹 눌러야 하는 대상 앞에서는 상자 둘레에 고리가 뜬다
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(0.72, 0.72)
	ring.BackgroundTransparency = 1
	ring.Visible = false
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(0.5, 0)
	ringCorner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.Thickness = HudLayout.BUTTON_RING_THICKNESS
	stroke.Color = WHITE
	stroke.Parent = ring
	ring.Parent = button

	button.Parent = hud
	return button
end

local function paint(button: ImageButton, action: string)
	local look = LOOK[action]
	local crate = button:FindFirstChild("Crate") :: Frame
	local floor = button:FindFirstChild("Floor") :: Frame
	local ring = button:FindFirstChild("Ring") :: Frame
	local function showCross(value: boolean)
		for _, child in button:GetChildren() do
			if child.Name == "Cross" then
				(child :: Frame).Visible = value
			end
		end
	end
	if look == nil then
		-- 할 수 있는 것이 없으면 흐리게
		button.BackgroundTransparency = 0.7
		button.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
		crate.BackgroundTransparency = 0.7
		crate.Position = UDim2.fromScale(0.5, 0.5)
		floor.Visible = false
		ring.Visible = false
		showCross(false)
		return
	end
	button.BackgroundTransparency = 0
	button.BackgroundColor3 = look.color
	crate.BackgroundTransparency = 0
	ring.Visible = look.ring
	if look.ring then
		crate.Position = UDim2.fromScale(0.5, 0.5)
		floor.Visible = false
		;(ring:FindFirstChild("Stroke") :: UIStroke).Color = RING_COLOR[action] or WHITE
	else
		-- 들기는 상자가 위로, 놓기와 버리기는 바닥 위에
		crate.Position = if look.raised then UDim2.fromScale(0.5, 0.4) else UDim2.fromScale(0.5, 0.55)
		floor.Visible = not look.raised
	end
	showCross(look.cross)
end

function InputController.start()
	local map = workspace:WaitForChild("Map")
	local boat = map:WaitForChild("Boat")
	local cargo = boat:WaitForChild("Cargo")
	local deckZone = map:WaitForChild("Zones"):WaitForChild("DeckZone") :: BasePart
	local beach = map:WaitForChild("Beach")
	local stacks = beach:WaitForChild("PileStacks")
	local spots: { [string]: BasePart } = {}
	for _, kind in PILE_KINDS do
		spots[kind] = beach:WaitForChild("Pile" .. kind) :: BasePart
	end
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local tap = remotes:WaitForChild("Tap") :: RemoteEvent
	local holdBegin = remotes:WaitForChild("HoldBegin") :: RemoteEvent
	local holdEnd = remotes:WaitForChild("HoldEnd") :: RemoteEvent
	local fx = remotes:WaitForChild("Fx") :: RemoteEvent
	local playerGui = player:WaitForChild("PlayerGui")

	-- 대상 테두리(IN-1). 하나를 돌려 쓴다
	local highlight = Instance.new("Highlight")
	highlight.Name = "TargetHighlight"
	highlight.FillTransparency = 1
	highlight.OutlineColor = WHITE
	highlight.Parent = playerGui

	local button: ImageButton? = nil
	local pileTarget: string? = nil -- 해변에서의 대상(더미 종류)
	local crateTarget: Model? = nil -- 갑판에서의 대상(실린 상자)
	local holdAction: InputRules.HoldAction = "None" -- 대상 상자를 꾹 누르면 될 일
	local situation: InputRules.Situation? = nil -- 지난 프레임에 본 상황
	-- 꾹 누르는 중인 상자. 고리는 그 상자 위에 뜬다
	local holding: { crate: Model, crateId: number, startedAt: number, ring: RingGui.Ring? }? = nil

	local function bodyOf(crate: Model): BasePart?
		return crate.PrimaryPart or crate:FindFirstChild("Body") :: BasePart?
	end

	local function stopHold()
		local current = holding
		if current and current.ring then
			current.ring.destroy()
		end
		holding = nil
	end

	-- 누르는 순간. 꾹 누르기를 시작할지 바로 톡으로 보낼지는 InputRules.pressStart가 정한다
	local function press()
		local now = situation
		local crate = crateTarget
		if holding ~= nil or now == nil then
			return
		end
		local target: InputRules.Target? = nil
		if crate ~= nil and holdAction ~= "None" then
			-- 꾹 눌러도 아무 일이 없을 상자(끌어안긴 상자 같은 것)는 대상이 없는 것과 같다
			target = { mine = holdAction == "Repick", huggedBy = nil, covered = false }
		end
		if crate ~= nil and InputRules.pressStart(now, target) == "Hold" then
			local crateId = crate:GetAttribute("CrateId") :: number
			local body = bodyOf(crate)
			local color = RING_COLOR[holdAction]
			holding = {
				crate = crate,
				crateId = crateId,
				startedAt = os.clock(),
				ring = if body and color then RingGui.new(body, color, playerGui) else nil,
			}
			holdBegin:FireServer(crateId)
		else
			tap:FireServer(pileTarget)
		end
	end

	-- 떼는 순간. 다 채우기 전에 떼면 톡 누르기로 처리한다
	local function release()
		if holding ~= nil then
			stopHold()
			tap:FireServer(nil)
		end
	end

	local function attach(hud: Instance)
		if hud.Name ~= "Hud" or hud:FindFirstChild(BUTTON_NAME) then
			return
		end
		local newButton = buildButton(hud)
		newButton.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				press()
				-- 손가락이 버튼 밖으로 미끄러져도 떼는 순간을 놓치지 않게 그 입력이 끝나는 것을 본다
				local connection: RBXScriptConnection
				connection = UserInputService.InputEnded:Connect(function(ended: InputObject)
					if ended == input then
						connection:Disconnect()
						release()
					end
				end)
			end
		end)
		button = newButton
	end
	playerGui.ChildAdded:Connect(attach)
	for _, child in playerGui:GetChildren() do
		attach(child)
	end

	ContextActionService:BindAction(ACTION_NAME, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			press()
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			release()
		end
		return Enum.ContextActionResult.Sink
	end, false, table.unpack(KEYS))

	-- 갑판에서의 대상(S17): TARGET_RANGE 안의 실린 상자 가운데 바닥 위 거리가 가장 가까운 것.
	-- 2층이 있는 칸에서는 위 상자만 대상이 된다(GP-4)
	local function nearestCrate(from: Vector3): Model?
		local top: { [number]: Model } = {}
		for _, crate in cargo:GetChildren() do
			local cell = crate:GetAttribute("Cell") :: number?
			local layer = crate:GetAttribute("Layer") :: number?
			if cell and layer and crate:IsA("Model") then
				local best: Model? = top[cell]
				if best == nil or layer > ((best:GetAttribute("Layer") :: number?) or 0) then
					top[cell] = crate
				end
			end
		end
		local nearest: Model? = nil
		local nearestDistance = math.huge
		for _, crate in top do
			local body = bodyOf(crate)
			if body then
				local distance = flatDistance(from, body.Position)
				if distance <= Config.TARGET_RANGE and distance < nearestDistance then
					nearest, nearestDistance = crate, distance
				end
			end
		end
		return nearest
	end

	-- 매 프레임 상황을 보고 대상과 그림을 고른다
	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local record = myRecord()
		if rootPart == nil or record == nil then
			situation = nil
			stopHold()
			return
		end
		local state = record:GetAttribute("State") :: string? or State.Empty
		local carrying = record:GetAttribute("Carrying") :: string?
		if carrying == "" then
			carrying = nil
		end
		local onDeck = inside(deckZone, rootPart.Position)
		local phase = (boat:GetAttribute("Phase") :: string?) or ""
		local mySlot = tonumber(record.Name)

		-- 빈손이고 갑판 밖이면 TARGET_RANGE 안에서 가장 가까운 더미
		pileTarget = nil
		crateTarget = nil
		holdAction = "None"
		if state == State.Empty and not onDeck then
			local best = math.huge
			for kind, spot in spots do
				local distance = flatDistance(rootPart.Position, spot.Position)
				if distance <= Config.TARGET_RANGE and distance < best then
					best = distance
					pileTarget = kind
				end
			end
		elseif state == State.Empty and onDeck and phase == Phase.Loading then
			crateTarget = nearestCrate(rootPart.Position)
		end

		-- 끌어안긴 내 상자가 RECLAIM_RANGE 안에 있으면 누르는 순간 되찾기다(GP-19).
		-- 재사용 대기는 서버만 안다. 대기 중에 누르면 서버가 힌트로 답한다
		local reclaimable = false
		if state == State.Empty and onDeck and phase == Phase.Loading then
			for _, crate in cargo:GetChildren() do
				if crate:GetAttribute("OwnerSlot") == mySlot and crate:GetAttribute("HuggedBySlot") ~= nil and crate:IsA("Model") then
					local body = bodyOf(crate)
					if body and flatDistance(rootPart.Position, body.Position) <= Config.RECLAIM_RANGE then
						reclaimable = true
						break
					end
				end
			end
		end

		local now: InputRules.Situation = {
			phase = phase,
			state = state,
			onDeck = onDeck,
			carrying = carrying,
			pickupInReach = pileTarget ~= nil,
			reclaimable = reclaimable,
		}
		situation = now

		-- 대상 상자를 꾹 누르면 될 일. 서버와 같은 함수에 같은 것을 넣는다
		local target = crateTarget
		if target ~= nil then
			local huggedBy = target:GetAttribute("HuggedBySlot") :: number?
			holdAction = InputRules.hold(now, {
				mine = target:GetAttribute("OwnerSlot") == mySlot,
				huggedBy = if huggedBy then tostring(huggedBy) else nil,
				covered = false,
			}, Config.HOLD_TIME, HOLD_SETTINGS)
		end
		highlight.Adornee = if target then target elseif pileTarget then stacks:FindFirstChild(pileTarget) else nil

		-- 꾹 누르는 중: 고리를 채우고, 다 차면 떼기를 기다리지 않고 HoldEnd를 보낸다. 대상에서 멀어지면 취소한다
		local current = holding
		if current ~= nil then
			local body = if current.crate.Parent == cargo then bodyOf(current.crate) else nil
			local held = os.clock() - current.startedAt
			if body == nil or state ~= State.Empty or not onDeck or phase ~= Phase.Loading
				or flatDistance(rootPart.Position, body.Position) > Config.TARGET_RANGE
			then
				stopHold()
				holdEnd:FireServer(current.crateId, false)
			elseif held >= Config.HOLD_TIME then
				stopHold()
				holdEnd:FireServer(current.crateId, true)
			elseif current.ring then
				current.ring.set(held / Config.HOLD_TIME)
			end
		end

		-- 버튼 그림: 꾹 눌러야 하는 대상 앞이면 고리, 아니면 톡 누르기가 될 일
		local picture: string = InputRules.tap(now)
		if not reclaimable and holdAction ~= "None" and LOOK[holdAction] ~= nil then
			picture = holdAction
		end
		if button and button.Parent then
			paint(button, picture)
		end
	end)

	-- 힌트(IN-4): 갑판에서 빈손으로 톡 눌렀는데 되찾을 것이 없으면 앞에 있는 상자에 고리가 잠깐 비친다
	fx.OnClientEvent:Connect(function(name: string)
		if name ~= "HoldHint" then
			return
		end
		local crate = crateTarget
		local body = crate and bodyOf(crate)
		if crate == nil or body == nil then
			return
		end
		local ring = RingGui.new(body, RING_COLOR[holdAction] or WHITE, playerGui)
		ring.set(1)
		task.delay(HINT_TIME, ring.destroy)
	end)

	-- 내 상자에는 흰 테두리(UI-2). 하이라이트 개수 제한을 피하려고 SelectionBox를 쓴다
	local function outline(crate: Instance)
		local record = myRecord()
		local mySlot = record and tonumber(record.Name)
		if mySlot == nil or crate:GetAttribute("OwnerSlot") ~= mySlot then
			return
		end
		local body = crate:WaitForChild("Body", 5) :: BasePart?
		if body then
			local box = Instance.new("SelectionBox")
			box.Name = "MineOutline"
			box.Color3 = WHITE
			box.LineThickness = 0.05
			box.Adornee = body
			box.Parent = body
		end
	end
	cargo.ChildAdded:Connect(outline)
	for _, crate in cargo:GetChildren() do
		outline(crate)
	end
end

return InputController
