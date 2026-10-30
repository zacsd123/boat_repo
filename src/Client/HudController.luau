--!strict
-- 화면 표시. 클라이언트는 배의 속성(Phase, BoatIndex, BellCount, Weight, MarkWeight, RangeLo, RangeHi)만 보고 그린다.
-- 숨은 한계와 종까지 남은 시간은 받지도 보이지도 않는다.
-- - 개발용 단계 글자(S06). S14에서 지운다.
-- - 수위 막대(S08, UI-1): 아래부터 안전 구간, 빨간 구간, 지금 수위, 최고 수위. 글자와 숫자 없음. 모양은 디자인 전 임시.

local Players = game:GetService("Players")

local HudLayout = require(script.Parent.HudLayout)

local HudController = {}

local DEV_LABEL = "DevPhase"
local WATER_BAR = "WaterBar"

-- 수위 막대는 버튼 바로 위, 버튼과 같은 세로줄에 놓는다. 아래 끝은 버튼 위 끝에서 GAP만큼 띄우고,
-- 위 끝은 화면 위에서 EDGE만큼 띄워 그 사이를 채운다. 화면이 낮을수록 막대가 짧아질 뿐이라
-- 어느 폰에서도 버튼과 겹치지 않는다(S11-1)
local function buildBar(hud: Instance): Frame
	local bar = Instance.new("Frame")
	bar.Name = WATER_BAR
	local fromBottom = HudLayout.EDGE + HudLayout.BUTTON_SIZE + HudLayout.GAP
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(1, -(HudLayout.EDGE + HudLayout.BUTTON_SIZE / 2), 1, -fromBottom)
	bar.Size = UDim2.new(0, HudLayout.BAR_WIDTH, 1, -(fromBottom + HudLayout.EDGE))
	bar.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	bar.BackgroundTransparency = 0.3
	bar.BorderSizePixel = 0

	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MinSize = Vector2.new(HudLayout.BAR_WIDTH, HudLayout.BAR_MIN_HEIGHT)
	sizeLimit.MaxSize = Vector2.new(HudLayout.BAR_WIDTH, HudLayout.BAR_MAX_HEIGHT)
	sizeLimit.Parent = bar

	local safe = Instance.new("Frame")
	safe.Name = "Safe"
	safe.AnchorPoint = Vector2.new(0, 1)
	safe.Position = UDim2.fromScale(0, 1)
	safe.BackgroundColor3 = Color3.fromRGB(90, 110, 130)
	safe.BorderSizePixel = 0
	safe.Parent = bar

	local red = Instance.new("Frame")
	red.Name = "Red"
	red.AnchorPoint = Vector2.new(0, 1)
	red.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
	red.BorderSizePixel = 0
	red.Parent = bar

	local water = Instance.new("Frame")
	water.Name = "Water"
	water.AnchorPoint = Vector2.new(0, 1)
	water.Position = UDim2.fromScale(0, 1)
	water.BackgroundColor3 = Color3.fromRGB(80, 150, 220)
	water.BackgroundTransparency = 0.35
	water.BorderSizePixel = 0
	water.ZIndex = 2
	water.Parent = bar

	for _, name in { "Mark", "Level" } do
		local line = Instance.new("Frame")
		line.Name = name
		line.AnchorPoint = Vector2.new(0, 0.5)
		line.Size = UDim2.new(1, 8, 0, if name == "Level" then 3 else 2)
		line.BackgroundColor3 = if name == "Level" then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(20, 20, 20)
		line.BorderSizePixel = 0
		line.ZIndex = 3
		line.Parent = bar
	end

	bar.Parent = hud
	return bar
end

function HudController.start()
	local boat = workspace:WaitForChild("Map"):WaitForChild("Boat")
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local label: TextLabel? = nil
	local bar: Frame? = nil

	local function number(name: string): number
		return (boat:GetAttribute(name) :: number?) or 0
	end

	local function refresh()
		if label then
			local phase = boat:GetAttribute("Phase")
			label.Text = `단계 {phase or "-"} · 배 {boat:GetAttribute("BoatIndex") or "-"} · 종 {boat:GetAttribute("BellCount") or "-"}`
		end
		if bar then
			local hi = number("RangeHi")
			if hi <= 0 then
				return
			end
			-- 막대 꼭대기 = 범위의 위 끝(갑판 턱). 선체와 같은 비율
			local loShare = number("RangeLo") / hi
			local weightShare = math.min(number("Weight") / hi, 1)
			local markShare = math.min(number("MarkWeight") / hi, 1)
			local safe = bar:FindFirstChild("Safe") :: Frame
			local red = bar:FindFirstChild("Red") :: Frame
			local water = bar:FindFirstChild("Water") :: Frame
			safe.Size = UDim2.fromScale(1, loShare)
			red.Size = UDim2.fromScale(1, 1 - loShare)
			red.Position = UDim2.fromScale(0, 1 - loShare)
			water.Size = UDim2.fromScale(1, weightShare)
			;(bar:FindFirstChild("Level") :: Frame).Position = UDim2.new(0, -4, 1 - weightShare, 0)
			local mark = bar:FindFirstChild("Mark") :: Frame
			mark.Position = UDim2.new(0, -4, 1 - markShare, 0)
			mark.Visible = markShare > 0
		end
	end

	-- Hud는 캐릭터가 다시 날 때마다 새로 복제되므로, 들어올 때마다 붙인다
	local function attach(hud: Instance)
		if hud.Name ~= "Hud" then
			return
		end
		if not hud:FindFirstChild(DEV_LABEL) then
			local newLabel = Instance.new("TextLabel")
			newLabel.Name = DEV_LABEL
			newLabel.AutomaticSize = Enum.AutomaticSize.XY
			newLabel.BackgroundTransparency = 0.4
			newLabel.BackgroundColor3 = Color3.new(0, 0, 0)
			newLabel.TextColor3 = Color3.new(1, 1, 1)
			newLabel.Font = Enum.Font.Code
			newLabel.TextSize = 18
			newLabel.Parent = hud
			label = newLabel
		end
		if not hud:FindFirstChild(WATER_BAR) then
			bar = buildBar(hud)
		end
		refresh()
	end

	playerGui.ChildAdded:Connect(attach)
	for _, child in playerGui:GetChildren() do
		attach(child)
	end
	for _, name in { "Phase", "BoatIndex", "BellCount", "Weight", "MarkWeight", "RangeLo", "RangeHi" } do
		boat:GetAttributeChangedSignal(name):Connect(refresh)
	end

	HudController.startHeads(boat)
end

-- 머리 위 숫자(UI-3)와 선장 모자(SC-6). 참가자 기록의 BoatScore, Hat, Color만 보고 그린다.
-- 침몰한 배의 정산 동안 가라앉힌 사람 머리 위에는 큰 0(UI-6). 모양은 디자인 전 임시
local HEAD_SCORE = "HeadScore"
local CAPTAIN_HAT = "CaptainHat"
local SCORE_SIZE = UDim2.fromOffset(90, 44)
local BIG_ZERO_SIZE = UDim2.fromOffset(170, 96)
local HAT_COLOR = Color3.fromRGB(25, 25, 35)

function HudController.startHeads(boat: Instance)
	local participants = game:GetService("ReplicatedStorage"):WaitForChild("Participants")
	local fx = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("Fx") :: RemoteEvent
	local sinkerSlot: number? = nil -- 이번 배를 가라앉힌 슬롯. 다음 배가 들어오면 지운다

	local function playerOf(record: Instance): Player?
		for _, player in Players:GetPlayers() do
			if player.UserId == record:GetAttribute("UserId") then
				return player
			end
		end
		return nil
	end

	local function render(record: Instance)
		local player = playerOf(record)
		local character = player and player.Character
		local head = character and character:FindFirstChild("Head") :: BasePart?
		if head == nil then
			return
		end

		local billboard = head:FindFirstChild(HEAD_SCORE) :: BillboardGui?
		if billboard == nil then
			local newBillboard = Instance.new("BillboardGui")
			newBillboard.Name = HEAD_SCORE
			newBillboard.Adornee = head
			newBillboard.StudsOffset = Vector3.new(0, 2.6, 0)
			newBillboard.AlwaysOnTop = true
			local text = Instance.new("TextLabel")
			text.Name = "Score"
			text.Size = UDim2.fromScale(1, 1)
			text.BackgroundTransparency = 1
			text.Font = Enum.Font.GothamBlack
			text.TextScaled = true
			text.TextStrokeTransparency = 0
			text.Parent = newBillboard
			newBillboard.Parent = head
			billboard = newBillboard
		end
		local label = (billboard :: BillboardGui):FindFirstChild("Score") :: TextLabel
		local phase = boat:GetAttribute("Phase")
		local isSinker = sinkerSlot ~= nil and tonumber(record.Name) == sinkerSlot
			and (phase == "Sinking" or phase == "Scoring")
		label.Text = tostring(record:GetAttribute("BoatScore") or 0)
		label.TextColor3 = (record:GetAttribute("Color") :: Color3?) or Color3.new(1, 1, 1)
		;(billboard :: BillboardGui).Size = if isSinker then BIG_ZERO_SIZE else SCORE_SIZE

		local hat: Instance? = head:FindFirstChild(CAPTAIN_HAT)
		if record:GetAttribute("Hat") == true and hat == nil then
			local newHat = Instance.new("Part")
			newHat.Name = CAPTAIN_HAT
			newHat.Shape = Enum.PartType.Cylinder
			newHat.Size = Vector3.new(0.5, 1.6, 1.6)
			newHat.Color = HAT_COLOR
			newHat.CanCollide = false
			newHat.CanQuery = false
			newHat.CanTouch = false
			newHat.Massless = true
			newHat.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2 + newHat.Size.X / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = head
			weld.Part1 = newHat
			weld.Parent = newHat
			newHat.Parent = head
		elseif record:GetAttribute("Hat") ~= true and hat then
			hat:Destroy()
		end
	end

	local function renderAll()
		for _, record in participants:GetChildren() do
			render(record)
		end
	end

	local function watch(record: Instance)
		for _, name in { "BoatScore", "Hat", "Color" } do
			record:GetAttributeChangedSignal(name):Connect(function()
				render(record)
			end)
		end
		local player = playerOf(record)
		if player then
			player.CharacterAdded:Connect(function(character)
				character:WaitForChild("Head")
				render(record)
			end)
		end
		render(record)
	end
	participants.ChildAdded:Connect(watch)
	for _, record in participants:GetChildren() do
		watch(record)
	end

	fx.OnClientEvent:Connect(function(name: string, slot: any)
		if name == "Sink" then
			sinkerSlot = slot
			renderAll()
		end
	end)
	boat:GetAttributeChangedSignal("Phase"):Connect(function()
		if boat:GetAttribute("Phase") == "Arriving" then
			sinkerSlot = nil
		end
		renderAll()
	end)
end

return HudController
