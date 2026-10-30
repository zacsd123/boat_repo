--!strict
-- 버튼 하나(톡 누르기). 대상 찾기와 테두리, 버튼 그림.
-- 누르면 Tap만 보낸다. 상자가 손에 붙거나 화물칸에 생기는 것은 서버가 바꾼 상태를 보고 그린다.
-- 버튼 그림은 InputRules.tap에 서버와 같은 상황을 넣어 고른다. 글자는 쓰지 않는다(그림은 디자인 전 임시).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local InputRules = require(ReplicatedStorage.Shared.Rules.InputRules)
local HudLayout = require(script.Parent.HudLayout)

local State = Types.ParticipantState
local Kind = Types.CrateKind

local InputController = {}

local PILE_KINDS = { Kind.Small, Kind.Medium, Kind.Large }
local ACTION_NAME = "BoatButton"
local BUTTON_NAME = "ActionButton"
-- 키보드 키 하나와 게임패드 버튼 하나. 점프를 껐으므로 A 버튼은 비어 있다
local KEYS = { Enum.KeyCode.E, Enum.KeyCode.ButtonA }

-- 그림마다 색. 놓기와 버리기는 확실히 다르게 그린다
local LOOK = {
	Pickup = { color = Color3.fromRGB(70, 170, 90), raised = true, cross = false },
	Place = { color = Color3.fromRGB(60, 120, 220), raised = false, cross = false },
	Discard = { color = Color3.fromRGB(210, 60, 60), raised = false, cross = true },
	DropGold = { color = Color3.fromRGB(210, 60, 60), raised = false, cross = true },
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

-- 버튼 모양을 만든다: 둥근 판 + 가운데 상자 + 버리기용 X
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

	button.Parent = hud
	return button
end

local function paint(button: ImageButton, action: string)
	local look = LOOK[action]
	local crate = button:FindFirstChild("Crate") :: Frame
	local floor = button:FindFirstChild("Floor") :: Frame
	if look == nil then
		-- 할 수 있는 것이 없으면 흐리게
		button.BackgroundTransparency = 0.7
		button.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
		crate.BackgroundTransparency = 0.7
		crate.Position = UDim2.fromScale(0.5, 0.5)
		floor.Visible = false
		for _, child in button:GetChildren() do
			if child.Name == "Cross" then
				(child :: Frame).Visible = false
			end
		end
		return
	end
	button.BackgroundTransparency = 0
	button.BackgroundColor3 = look.color
	crate.BackgroundTransparency = 0
	-- 들기는 상자가 위로, 놓기와 버리기는 바닥 위에
	crate.Position = if look.raised then UDim2.fromScale(0.5, 0.4) else UDim2.fromScale(0.5, 0.55)
	floor.Visible = not look.raised
	for _, child in button:GetChildren() do
		if child.Name == "Cross" then
			(child :: Frame).Visible = look.cross
		end
	end
end

function InputController.start()
	local map = workspace:WaitForChild("Map")
	local boat = map:WaitForChild("Boat")
	local deckZone = map:WaitForChild("Zones"):WaitForChild("DeckZone") :: BasePart
	local beach = map:WaitForChild("Beach")
	local stacks = beach:WaitForChild("PileStacks")
	local spots: { [string]: BasePart } = {}
	for _, kind in PILE_KINDS do
		spots[kind] = beach:WaitForChild("Pile" .. kind) :: BasePart
	end
	local tap = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Tap") :: RemoteEvent
	local playerGui = player:WaitForChild("PlayerGui")

	-- 대상 테두리(IN-1). 하나를 돌려 쓴다
	local highlight = Instance.new("Highlight")
	highlight.Name = "TargetHighlight"
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.Parent = playerGui

	local button: ImageButton? = nil
	local currentTarget: string? = nil

	local function press()
		tap:FireServer(currentTarget)
	end

	local function attach(hud: Instance)
		if hud.Name ~= "Hud" or hud:FindFirstChild(BUTTON_NAME) then
			return
		end
		local newButton = buildButton(hud)
		newButton.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				press()
			end
		end)
		-- "뗐다"는 S17에서 쓴다
		button = newButton
	end
	playerGui.ChildAdded:Connect(attach)
	for _, child in playerGui:GetChildren() do
		attach(child)
	end

	ContextActionService:BindAction(ACTION_NAME, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			press()
		end
		return Enum.ContextActionResult.Sink
	end, false, table.unpack(KEYS))

	-- 매 프레임 상황을 보고 대상과 그림을 고른다
	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local record = myRecord()
		if rootPart == nil or record == nil then
			return
		end
		local state = record:GetAttribute("State") :: string? or State.Empty
		local carrying = record:GetAttribute("Carrying") :: string?
		if carrying == "" then
			carrying = nil
		end
		local onDeck = inside(deckZone, rootPart.Position)

		-- 빈손이고 갑판 밖이면 TARGET_RANGE 안에서 가장 가까운 더미
		currentTarget = nil
		if state == State.Empty and not onDeck then
			local best = math.huge
			for kind, spot in spots do
				local distance = flatDistance(rootPart.Position, spot.Position)
				if distance <= Config.TARGET_RANGE and distance < best then
					best = distance
					currentTarget = kind
				end
			end
		end
		highlight.Adornee = if currentTarget then stacks:FindFirstChild(currentTarget) else nil

		local action = InputRules.tap({
			phase = (boat:GetAttribute("Phase") :: string?) or "",
			state = state,
			onDeck = onDeck,
			carrying = carrying,
			pickupInReach = currentTarget ~= nil,
			reclaimable = false,
		})
		if button and button.Parent then
			paint(button, action)
		end
	end)

	-- 내 상자에는 흰 테두리(UI-2). 하이라이트 개수 제한을 피하려고 SelectionBox를 쓴다
	local cargo = boat:WaitForChild("Cargo")
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
			box.Color3 = Color3.fromRGB(255, 255, 255)
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
