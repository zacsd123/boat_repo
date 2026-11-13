--!strict
-- 화면 표시. 클라이언트는 배의 속성(Phase, BoatIndex, BellCount, Weight, MarkWeight, RangeLo, RangeHi)만 보고 그린다.
-- 숨은 한계와 종까지 남은 시간은 받지도 보이지도 않는다.
-- - 개발용 단계 글자(S06)는 S14에서 지웠다. 화면에는 숫자와 그림만 있다(UI-5).
-- - 수위 막대 옆 작은 종 셋(S14): 돛대가 화면 밖일 때도 종이 몇 번 울렸는지 보이게.
-- - 수위 막대(S08, UI-1): 아래부터 안전 구간, 빨간 구간, 지금 수위, 최고 수위. 글자와 숫자 없음. 모양은 디자인 전 임시.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local HudLayout = require(script.Parent.HudLayout)
local RingGui = require(script.Parent.RingGui)

local HudController = {}

local WATER_BAR = "WaterBar"
local MINI_BELLS = "MiniBells"
local BELL_OFF_COLOR = Color3.fromRGB(70, 70, 70)
local BELL_ON_COLOR = Color3.fromRGB(255, 210, 60)

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

-- 수위 막대 위쪽 왼편에 작은 종 셋을 세로로. 울린 수만큼 켠다
local function buildMiniBells(hud: Instance): Frame
	local holder = Instance.new("Frame")
	holder.Name = MINI_BELLS
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(1, 0)
	local barLeft = HudLayout.EDGE + HudLayout.BUTTON_SIZE / 2 + HudLayout.BAR_WIDTH / 2
	holder.Position = UDim2.new(1, -(barLeft + HudLayout.MINI_BELL_GAP), 0, HudLayout.EDGE)
	holder.Size = UDim2.fromOffset(HudLayout.MINI_BELL_SIZE, HudLayout.MINI_BELL_SIZE * 3 + HudLayout.MINI_BELL_GAP * 2)
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, HudLayout.MINI_BELL_GAP)
	list.SortOrder = Enum.SortOrder.Name
	list.Parent = holder
	for index = 1, 3 do
		local bell = Instance.new("Frame")
		bell.Name = "Bell" .. index
		bell.Size = UDim2.fromOffset(HudLayout.MINI_BELL_SIZE, HudLayout.MINI_BELL_SIZE)
		bell.BackgroundColor3 = BELL_OFF_COLOR
		bell.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = bell
		bell.Parent = holder
	end
	holder.Parent = hud
	return holder
end

function HudController.start()
	local boat = workspace:WaitForChild("Map"):WaitForChild("Boat")
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local bar: Frame? = nil
	local miniBells: Frame? = nil

	local function number(name: string): number
		return (boat:GetAttribute(name) :: number?) or 0
	end

	local function refresh()
		if miniBells then
			local count = number("BellCount")
			for _, bell in miniBells:GetChildren() do
				if bell:IsA("Frame") then
					local index = tonumber(string.match(bell.Name, "%d+")) or 0
					bell.BackgroundColor3 = if index <= count then BELL_ON_COLOR else BELL_OFF_COLOR
				end
			end
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
		if not hud:FindFirstChild(WATER_BAR) then
			bar = buildBar(hud)
		end
		if not hud:FindFirstChild(MINI_BELLS) then
			miniBells = buildMiniBells(hud)
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
	HudController.startHugs(boat)
	HudController.startOwnerSummary(boat)
end

-- 끌어안긴 상자 위의 빨간 고리(S18). 누구에게나 보이고, 상자의 HugEndsAt(서버 시각)까지 차오른다.
-- 내 상자가 끌어안기면 서버가 나에게만 HugAlert를 보낸다. 그 상자 쪽을 가리키는 화살표를 화면 가장자리에 띄운다(HG-6).
-- 화살표는 둥근 판에 뾰족한 끝을 붙인 모양이고 글자는 없다. 모양은 디자인 전 임시
local ALERT_GUI = "HugAlerts"

local function buildAlert(parent: Instance): Frame
	local arrow = Instance.new("Frame")
	arrow.Name = "Arrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Size = UDim2.fromOffset(HudLayout.ALERT_SIZE, HudLayout.ALERT_SIZE)
	arrow.BackgroundTransparency = 1
	-- 돌리지 않았을 때 위쪽을 가리킨다
	local tip = Instance.new("Frame")
	tip.Name = "Tip"
	tip.AnchorPoint = Vector2.new(0.5, 0.5)
	tip.Position = UDim2.fromScale(0.5, 0.3)
	tip.Size = UDim2.fromScale(0.46, 0.46)
	tip.Rotation = 45
	tip.BackgroundColor3 = HudLayout.HUG_COLOR
	tip.BorderSizePixel = 0
	tip.Parent = arrow
	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.6)
	disc.Size = UDim2.fromScale(0.7, 0.7)
	disc.BackgroundColor3 = HudLayout.HUG_COLOR
	disc.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = disc
	disc.Parent = arrow
	arrow.Parent = parent
	return arrow
end

function HudController.startHugs(boat: Instance)
	local cargo = boat:WaitForChild("Cargo")
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local fx = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Fx") :: RemoteEvent
	local rings: { [Instance]: RingGui.Ring } = {}
	local alerts: { [Instance]: Frame? } = {}

	local alertGui = Instance.new("ScreenGui")
	alertGui.Name = ALERT_GUI
	alertGui.ResetOnSpawn = false
	alertGui.IgnoreGuiInset = true
	alertGui.Parent = playerGui

	local function clear(crate: Instance)
		local ring = rings[crate]
		if ring then
			ring.destroy()
			rings[crate] = nil
		end
		local arrow = alerts[crate]
		if arrow then
			arrow:Destroy()
			alerts[crate] = nil
		end
	end

	local function refresh(crate: Instance)
		local hugged = crate.Parent == cargo and crate:GetAttribute("HuggedBySlot") ~= nil
		if not hugged then
			clear(crate)
		elseif rings[crate] == nil then
			local body = crate:WaitForChild("Body", 5) :: BasePart?
			if body and rings[crate] == nil and crate:GetAttribute("HuggedBySlot") ~= nil then
				rings[crate] = RingGui.new(body, HudLayout.HUG_COLOR, playerGui)
			end
		end
	end

	local function watch(crate: Instance)
		crate:GetAttributeChangedSignal("HuggedBySlot"):Connect(function()
			refresh(crate)
		end)
		refresh(crate)
	end
	cargo.ChildAdded:Connect(watch)
	cargo.ChildRemoved:Connect(clear)
	for _, crate in cargo:GetChildren() do
		task.spawn(watch, crate)
	end

	fx.OnClientEvent:Connect(function(name: string, crate: any)
		if name == "HugAlert" and typeof(crate) == "Instance" and alerts[crate] == nil then
			alerts[crate] = buildAlert(alertGui)
		end
	end)

	RunService.RenderStepped:Connect(function()
		local now = workspace:GetServerTimeNow()
		for crate, ring in rings do
			local endsAt = crate:GetAttribute("HugEndsAt") :: number?
			if endsAt then
				ring.set(1 - (endsAt - now) / Config.HUG_TIME)
			end
		end
		local camera = workspace.CurrentCamera
		for crate, arrow in alerts :: { [Instance]: Frame } do
			local body = crate:FindFirstChild("Body") :: BasePart?
			if crate.Parent ~= cargo or crate:GetAttribute("HuggedBySlot") == nil or body == nil or camera == nil then
				arrow:Destroy()
				alerts[crate] = nil
				continue
			end
			-- 상자가 화면 안에 있으면 그 자리에, 밖이면 그쪽 화면 가장자리에 놓고 상자 쪽으로 돌린다
			local viewport = camera.ViewportSize
			local center = viewport / 2
			local point = camera:WorldToViewportPoint(body.Position)
			local direction = Vector2.new(point.X - center.X, point.Y - center.Y)
			if point.Z < 0 then
				direction = -direction -- 카메라 뒤에 있으면 방향이 뒤집혀 나온다
			end
			if direction.Magnitude < 1 then
				direction = Vector2.new(0, -1)
			end
			local unit = direction.Unit
			local margin = HudLayout.ALERT_MARGIN
			local inView = point.Z > 0
				and point.X >= margin and point.X <= viewport.X - margin
				and point.Y >= margin and point.Y <= viewport.Y - margin
			local position = Vector2.new(point.X, point.Y)
			if not inView then
				local reachX = if unit.X ~= 0 then (center.X - margin) / math.abs(unit.X) else math.huge
				local reachY = if unit.Y ~= 0 then (center.Y - margin) / math.abs(unit.Y) else math.huge
				position = center + unit * math.min(reachX, reachY)
			end
			arrow.Position = UDim2.fromOffset(position.X, position.Y)
			arrow.Rotation = math.deg(math.atan2(unit.Y, unit.X)) + 90
		end
	end)
end

-- 게임 주인에게만 보이는 요약 창(S15). 서버가 주인에게만 OwnerSummary를 보낸다. 받은 적이 없으면 창을 만들지 않는다.
-- 개발용이라 글자를 쓴다(다른 사람 화면에는 없다). S14에서 지운 단계, 배 번호, 종 수도 여기서 본다. 숨은 한계는 없다
local OWNER_PANEL = "OwnerSummary"

function HudController.startOwnerSummary(boat: Instance)
	local remote = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("OwnerSummary") :: RemoteEvent
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local lines: { string }? = nil
	local panel: TextLabel? = nil

	local function refresh()
		if lines == nil then
			return
		end
		if panel == nil or panel.Parent == nil then
			local gui = Instance.new("ScreenGui")
			gui.Name = OWNER_PANEL
			gui.ResetOnSpawn = false
			local label = Instance.new("TextLabel")
			label.Name = "Text"
			label.AutomaticSize = Enum.AutomaticSize.XY
			label.BackgroundTransparency = 0.4
			label.BackgroundColor3 = Color3.new(0, 0, 0)
			label.TextColor3 = Color3.new(1, 1, 1)
			label.Font = Enum.Font.Code
			label.TextSize = 14
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.Parent = gui
			gui.Parent = playerGui
			panel = label
		end
		local live = `단계 {boat:GetAttribute("Phase") or "-"} · 배 {boat:GetAttribute("BoatIndex") or "-"} · 종 {boat:GetAttribute("BellCount") or "-"}`
		;(panel :: TextLabel).Text = live .. "\n" .. table.concat(lines :: { string }, "\n")
	end

	remote.OnClientEvent:Connect(function(newLines: { string })
		lines = newLines
		refresh()
	end)
	for _, name in { "Phase", "BoatIndex", "BellCount" } do
		boat:GetAttributeChangedSignal(name):Connect(refresh)
	end
end

-- 머리 위 숫자(UI-3), 선장 모자(SC-6), 왕관(SC-7). 참가자 기록의 BoatScore, TotalScore, Hat, Crown, Color만 보고 그린다.
-- 침몰한 배의 정산 동안 가라앉힌 사람 머리 위에는 큰 0(UI-6).
-- 마지막 배에서는 2배로 계산한 값을 금색으로(GP-17), 최종 결과에서는 총점을 크게 보여 준다(FL-8). 모양은 디자인 전 임시
local HEAD_SCORE = "HeadScore"
local CAPTAIN_HAT = "CaptainHat"
local CROWN = "Crown"
local SCORE_SIZE = UDim2.fromOffset(90, 44)
local BIG_ZERO_SIZE = UDim2.fromOffset(170, 96)
local TOTAL_SIZE = UDim2.fromOffset(170, 96) -- 최종 결과의 총점
local HAT_COLOR = Color3.fromRGB(25, 25, 35)
local HAT_SIZE = Vector3.new(0.5, 1.6, 1.6) -- 눕힌 원기둥: 두께, 지름, 지름
local CROWN_SIZE = Vector3.new(0.35, 1.2, 1.2)
local GOLD_COLOR = Color3.fromRGB(255, 205, 50)
local COUNT_TIME = 1.5 -- 마지막 배 점수가 총점에 더해지며 숫자가 올라가는 시간(초)
-- 봇의 머리 위 톱니 그림(PL-3). 종류마다 색이 다르다(S27). 글자는 쓰지 않는다
local BOT_MARK = "BotMark"
local BOT_MARK_SIZE = UDim2.fromOffset(26, 26)
local BOT_MARK_COLOR: { [string]: Color3 } = {
	Porter = Color3.fromRGB(205, 205, 210), -- 나르는 봇
	Saboteur = Color3.fromRGB(225, 70, 60), -- 버리는 봇
	Timid = Color3.fromRGB(80, 150, 235), -- 지키는 봇
}

-- 톱니: 돌려 놓은 막대 넷 위에 둥근 판, 가운데 구멍
local function buildBotMark(head: BasePart, color: Color3)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = BOT_MARK
	billboard.Adornee = head
	billboard.StudsOffset = Vector3.new(0, 1.5, 0)
	billboard.Size = BOT_MARK_SIZE
	billboard.AlwaysOnTop = true
	for index = 0, 3 do
		local tooth = Instance.new("Frame")
		tooth.AnchorPoint = Vector2.new(0.5, 0.5)
		tooth.Position = UDim2.fromScale(0.5, 0.5)
		tooth.Size = UDim2.fromScale(1, 0.26)
		tooth.Rotation = index * 45
		tooth.BackgroundColor3 = color
		tooth.BorderSizePixel = 0
		tooth.Parent = billboard
	end
	for _, spec in { { scale = 0.74, color = color }, { scale = 0.3, color = Color3.fromRGB(30, 30, 30) } } do
		local disc = Instance.new("Frame")
		disc.AnchorPoint = Vector2.new(0.5, 0.5)
		disc.Position = UDim2.fromScale(0.5, 0.5)
		disc.Size = UDim2.fromScale(spec.scale, spec.scale)
		disc.BackgroundColor3 = spec.color
		disc.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = disc
		disc.Parent = billboard
	end
	billboard.Parent = head
end

function HudController.startHeads(boat: Instance)
	local participants = game:GetService("ReplicatedStorage"):WaitForChild("Participants")
	local fx = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("Fx") :: RemoteEvent
	local sinkerSlot: number? = nil -- 이번 배를 가라앉힌 슬롯. 다음 배가 들어오면 지운다
	local phaseSince = os.clock() -- 지금 단계에 들어온 때(이 클라이언트가 본 때)
	local botFolder = workspace:WaitForChild("Bots") -- 봇의 몸. 이름이 슬롯 번호다(S25)

	local function playerOf(record: Instance): Player?
		for _, player in Players:GetPlayers() do
			if player.UserId == record:GetAttribute("UserId") then
				return player
			end
		end
		return nil
	end

	-- 참가자의 머리. 사람은 캐릭터에서, 봇은 Workspace.Bots의 슬롯 이름으로 찾는다
	local function headOf(record: Instance): BasePart?
		local character: Instance? = nil
		if record:GetAttribute("IsBot") == true then
			character = botFolder:FindFirstChild(record.Name)
		else
			local player = playerOf(record)
			character = player and player.Character
		end
		return character and character:FindFirstChild("Head") :: BasePart?
	end

	-- 머리 위에 얹는 것(모자, 왕관). lift는 머리 꼭대기에서 띄우는 높이
	local function ornament(head: BasePart, name: string, show: boolean, color: Color3, size: Vector3, lift: number)
		local existing = head:FindFirstChild(name)
		if show and existing == nil then
			local part = Instance.new("Part")
			part.Name = name
			part.Shape = Enum.PartType.Cylinder
			part.Size = size
			part.Color = color
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			part.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2 + lift + size.X / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = head
			weld.Part1 = part
			weld.Parent = part
			part.Parent = head
		elseif not show and existing then
			existing:Destroy()
		end
	end

	local function render(record: Instance)
		local head = headOf(record)
		if head == nil then
			return
		end
		if record:GetAttribute("IsBot") == true and head:FindFirstChild(BOT_MARK) == nil then
			local kind = (record:GetAttribute("BotKind") :: string?) or ""
			buildBotMark(head, BOT_MARK_COLOR[kind] or BOT_MARK_COLOR.Porter)
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
		local lastBoat = ((boat:GetAttribute("BoatIndex") :: number?) or 0) >= Config.BOATS_PER_MATCH
		local boatScore = (record:GetAttribute("BoatScore") :: number?) or 0
		local total = (record:GetAttribute("TotalScore") :: number?) or 0
		local ownColor = (record:GetAttribute("Color") :: Color3?) or Color3.new(1, 1, 1)
		local isSinker = sinkerSlot ~= nil and tonumber(record.Name) == sinkerSlot
			and (phase == "Sinking" or phase == "Scoring" or phase == "FinalShow")

		local shown = boatScore
		local color = ownColor
		local size = if isSinker then BIG_ZERO_SIZE else SCORE_SIZE
		if phase == "FinalPodium" then
			-- 전원의 총점을 큰 숫자로
			shown = total
			size = TOTAL_SIZE
		elseif phase == "FinalLastScore" then
			-- 마지막 배의 점수가 총점에 더해지는 것을 보여 준다: 더하기 전 값에서 총점까지 올라간다
			local added = boatScore * Config.LAST_BOAT_MULTIPLIER
			local progress = math.clamp((os.clock() - phaseSince) / COUNT_TIME, 0, 1)
			shown = math.floor(total - added + added * progress + 0.5)
			color = GOLD_COLOR
			size = TOTAL_SIZE
		elseif lastBoat then
			-- 마지막 배: 2배로 계산한 값을 금색으로. 글 없이 2배를 알린다(GP-17)
			shown = boatScore * Config.LAST_BOAT_MULTIPLIER
			color = GOLD_COLOR
		end
		label.Text = tostring(shown)
		label.TextColor3 = color
		;(billboard :: BillboardGui).Size = size

		local hasHat = record:GetAttribute("Hat") == true
		ornament(head, CAPTAIN_HAT, hasHat, HAT_COLOR, HAT_SIZE, 0)
		-- 왕관은 모자 위에 얹는다(모자가 없어도 같은 높이)
		ornament(head, CROWN, record:GetAttribute("Crown") == true, GOLD_COLOR, CROWN_SIZE, HAT_SIZE.X)
	end

	local function renderAll()
		for _, record in participants:GetChildren() do
			render(record)
		end
	end

	local function watch(record: Instance)
		for _, name in { "BoatScore", "TotalScore", "Hat", "Crown", "Color" } do
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
	-- 봇의 몸은 참가자 기록보다 늦게 올 수 있다. 몸이 오면 그 슬롯을 다시 그린다
	botFolder.ChildAdded:Connect(function(body)
		body:WaitForChild("Head", 5)
		local record = participants:FindFirstChild(body.Name)
		if record then
			render(record)
		end
	end)

	fx.OnClientEvent:Connect(function(name: string, slot: any)
		if name == "Sink" then
			sinkerSlot = slot
			renderAll()
		end
	end)
	boat:GetAttributeChangedSignal("Phase"):Connect(function()
		local phase = boat:GetAttribute("Phase")
		phaseSince = os.clock()
		if phase == "Arriving" or phase == "MatchIntro" then
			sinkerSlot = nil
		end
		renderAll()
	end)
	boat:GetAttributeChangedSignal("BoatIndex"):Connect(renderAll)
	-- 숫자가 올라가는 동안에는 매 프레임 다시 그린다
	RunService.RenderStepped:Connect(function()
		if boat:GetAttribute("Phase") == "FinalLastScore" and os.clock() - phaseSince <= COUNT_TIME + 0.1 then
			renderAll()
		end
	end)
end

return HudController
