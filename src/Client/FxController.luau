--!strict
-- 소리와 연출. 서버가 보내는 Fx와 배의 속성을 보고 낸다. 소리는 디자인 전 임시(Roblox 기본 소리).
-- 삐걱 소리(BT-4): 무게가 범위의 아래 끝 이상인 동안. 크기는 (무게 − 아래 끝) ÷ (위 끝 − 아래 끝)에 비례.
-- 숨은 한계는 쓰지 않는다(받지도 않는다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FxController = {}

local CREAK_SOUND = "rbxasset://sounds/action_footsteps_plastic.mp3"
local CREAK_PITCH = 0.45 -- 발소리를 낮게 늘여 삐걱 소리 대신 쓴다(임시)
local CREAK_MIN_VOLUME = 0.15 -- 띠에 막 닿았을 때도 들리는 크기
local CREAK_MAX_VOLUME = 1

function FxController.start()
	local fx = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Fx") :: RemoteEvent
	fx.OnClientEvent:Connect(function(name: string, ...)
		print(`Fx {name}`, ...)
	end)

	local boat = workspace:WaitForChild("Map"):WaitForChild("Boat")
	local hull = boat:WaitForChild("Hull") :: BasePart
	local creak = Instance.new("Sound")
	creak.Name = "Creak"
	creak.SoundId = CREAK_SOUND
	creak.Looped = true
	creak.PlaybackSpeed = CREAK_PITCH
	creak.Parent = hull

	local function refresh()
		local weight = (boat:GetAttribute("Weight") :: number?) or 0
		local lo = (boat:GetAttribute("RangeLo") :: number?) or 0
		local hi = (boat:GetAttribute("RangeHi") :: number?) or 0
		local loading = boat:GetAttribute("Phase") == "Loading"
		if loading and hi > lo and weight >= lo then
			local share = math.clamp((weight - lo) / (hi - lo), 0, 1)
			creak.Volume = CREAK_MIN_VOLUME + (CREAK_MAX_VOLUME - CREAK_MIN_VOLUME) * share
			if not creak.IsPlaying then
				creak:Play()
			end
		elseif creak.IsPlaying then
			creak:Stop()
		end
	end
	for _, name in { "Weight", "RangeLo", "RangeHi", "Phase" } do
		boat:GetAttributeChangedSignal(name):Connect(refresh)
	end
	refresh()
end

return FxController
