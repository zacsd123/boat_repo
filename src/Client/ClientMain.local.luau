--!strict
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

print("client up")

-- 캐릭터 초기화(리셋)를 끈다(GP-2). 코어 화면이 준비될 때까지 다시 시도한다
task.spawn(function()
	while not pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", false) do
		task.wait()
	end
end)

-- 점프 상태는 캐릭터를 움직이는 쪽(클라이언트)에서 꺼야 한다(GP-1)
local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid.AutoJumpEnabled = false
end

local player = Players.LocalPlayer
player.CharacterAdded:Connect(onCharacter)
if player.Character then
	onCharacter(player.Character)
end

-- 컨트롤러를 켠다
local FxController = require(script.Parent.FxController)
local HudController = require(script.Parent.HudController)
FxController.start()
HudController.start()
