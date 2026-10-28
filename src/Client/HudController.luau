--!strict
-- 화면 표시. 지금은 개발용 글자만 있다(S06). S14에서 지운다.
-- 클라이언트는 배의 속성만 보고 그린다. 종까지 남은 시간은 받지도 보이지도 않는다.

local Players = game:GetService("Players")

local HudController = {}

local DEV_LABEL = "DevPhase"

function HudController.start()
	local boat = workspace:WaitForChild("Map"):WaitForChild("Boat")
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local label: TextLabel? = nil
	local function refresh()
		if label == nil then
			return
		end
		local phase = boat:GetAttribute("Phase")
		label.Text = `단계 {phase or "-"} · 배 {boat:GetAttribute("BoatIndex") or "-"} · 종 {boat:GetAttribute("BellCount") or "-"}`
	end

	-- Hud는 캐릭터가 다시 날 때마다 새로 복제되므로, 들어올 때마다 글자를 붙인다
	local function attach(hud: Instance)
		if hud.Name ~= "Hud" or hud:FindFirstChild(DEV_LABEL) then
			return
		end
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
		refresh()
	end

	playerGui.ChildAdded:Connect(attach)
	for _, child in playerGui:GetChildren() do
		attach(child)
	end
	for _, name in { "Phase", "BoatIndex", "BellCount" } do
		boat:GetAttributeChangedSignal(name):Connect(refresh)
	end
end

return HudController
