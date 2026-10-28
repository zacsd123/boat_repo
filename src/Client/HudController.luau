--!strict
-- 화면 표시. 클라이언트는 배의 속성(Phase, BoatIndex, BellCount, Weight, MarkWeight, RangeLo, RangeHi)만 보고 그린다.
-- 숨은 한계와 종까지 남은 시간은 받지도 보이지도 않는다.
-- - 개발용 단계 글자(S06). S14에서 지운다.
-- - 수위 막대(S08, UI-1): 아래부터 안전 구간, 빨간 구간, 지금 수위, 최고 수위. 글자와 숫자 없음. 모양은 디자인 전 임시.

local Players = game:GetService("Players")

local HudController = {}

local DEV_LABEL = "DevPhase"
local WATER_BAR = "WaterBar"

local function buildBar(hud: Instance): Frame
	local bar = Instance.new("Frame")
	bar.Name = WATER_BAR
	bar.AnchorPoint = Vector2.new(1, 0)
	bar.Position = UDim2.new(1, -24, 0, 80)
	bar.Size = UDim2.fromOffset(28, 220)
	bar.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	bar.BackgroundTransparency = 0.3
	bar.BorderSizePixel = 0

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
end

return HudController
