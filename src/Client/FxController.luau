--!strict
-- 소리와 연출. 서버가 보내는 Fx와 배의 속성을 보고 낸다. 소리와 모양은 디자인 전 임시(Roblox 기본 소리).
-- 삐걱 소리(BT-4): 무게가 범위의 아래 끝 이상인 동안. 크기는 (무게 − 아래 끝) ÷ (위 끝 − 아래 끝)에 비례.
-- 돛대의 종(UI-4): BellCount에 맞춰 하나씩 켜진다. 다음 종이 가까워졌음을 내비치는 것은 그리지 않는다.
-- 숨은 한계와 종 간격은 쓰지 않는다(받지도 않는다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FxController = {}

local CREAK_SOUND = "rbxasset://sounds/action_footsteps_plastic.mp3"
local CREAK_PITCH = 0.45 -- 발소리를 낮게 늘여 삐걱 소리 대신 쓴다(임시)
local CREAK_MIN_VOLUME = 0.15 -- 띠에 막 닿았을 때도 들리는 크기
local CREAK_MAX_VOLUME = 1
local BELL_SOUND = "rbxasset://sounds/electronicpingshort.wav"
local HORN_SOUND = "rbxasset://sounds/bass.wav"
local HORN_PITCH = 0.5
local BELL_ON_COLOR = Color3.fromRGB(255, 210, 60)

local function oneShot(id: string, parent: Instance, pitch: number?)
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = parent
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	sound:Play()
end

function FxController.start()
	local boat = workspace:WaitForChild("Map"):WaitForChild("Boat")
	local hull = boat:WaitForChild("Hull") :: BasePart
	local mast = boat:WaitForChild("Mast")

	local fx = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Fx") :: RemoteEvent
	fx.OnClientEvent:Connect(function(name: string, ...)
		print(`Fx {name}`, ...)
		if name == "Bell" then
			oneShot(BELL_SOUND, mast)
		elseif name == "Horn" then
			oneShot(HORN_SOUND, hull, HORN_PITCH)
		end
	end)

	-- 삐걱 소리
	local creak = Instance.new("Sound")
	creak.Name = "Creak"
	creak.SoundId = CREAK_SOUND
	creak.Looped = true
	creak.PlaybackSpeed = CREAK_PITCH
	creak.Parent = hull

	local function refreshCreak()
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
		boat:GetAttributeChangedSignal(name):Connect(refreshCreak)
	end
	refreshCreak()

	-- 돛대의 종 셋. 울린 수만큼 켠다
	local bellParts: { BasePart } = {}
	local offColor: { [BasePart]: Color3 } = {}
	local offMaterial: { [BasePart]: Enum.Material } = {}
	for index = 1, #mast:GetChildren() do
		local part = mast:FindFirstChild("Bell" .. index) :: BasePart?
		if part then
			bellParts[index] = part
			offColor[part] = part.Color
			offMaterial[part] = part.Material
		end
	end
	local function refreshBells()
		local count = (boat:GetAttribute("BellCount") :: number?) or 0
		for index, part in bellParts do
			local on = index <= count
			part.Color = if on then BELL_ON_COLOR else offColor[part]
			part.Material = if on then Enum.Material.Neon else offMaterial[part]
		end
	end
	boat:GetAttributeChangedSignal("BellCount"):Connect(refreshBells)
	refreshBells()
end

return FxController
