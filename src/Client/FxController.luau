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
local CREAK_MAX_VOLUME = 0.5 -- 종소리가 가장 잘 들리도록 삐걱 소리는 낮게(S14)
local BELL_SOUND = "rbxasset://sounds/electronicpingshort.wav"
local BELL_VOLUME = 1
local PLACE_SOUND = "rbxasset://sounds/snap.mp3"
local SINK_SOUND = "rbxasset://sounds/collide.wav"
local SINK_PITCH = 0.5
local ZERO_SOUND = "rbxasset://sounds/uuhhh.mp3"
local COLUMN_HEIGHT = 30 -- 침몰 물기둥 높이(스터드). 임시 모양
local COLUMN_WIDTH = 14
local COLUMN_TIME = 0.8 -- 물기둥이 솟았다 사라지는 시간(초)
local SHAKE_TIME = 0.6 -- 침몰 때 화면이 흔들리는 시간(초)
local SHAKE_SIZE = 0.6 -- 흔들림 크기(스터드)
local HORN_SOUND = "rbxasset://sounds/bass.wav"
local HORN_PITCH = 0.5
local FANFARE_SOUND = "rbxasset://sounds/victory.wav"
local SPLASH_SOUND = "rbxasset://sounds/impact_water.mp3"
local SPLASH_COLOR = Color3.fromRGB(220, 240, 255)
local SPLASH_SIZE = 6 -- 물보라가 퍼지는 지름(스터드). 임시 모양
local SPLASH_TIME = 0.4 -- 물보라가 퍼지고 사라지는 시간(초). 임시 모양
local BELL_ON_COLOR = Color3.fromRGB(255, 210, 60)

local function oneShot(id: string, parent: Instance, pitch: number?, volume: number?)
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.PlaybackSpeed = pitch or 1
	sound.Volume = volume or sound.Volume
	sound.Parent = parent
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	sound:Play()
end

-- 풍덩(S12): 수면에서 소리와 함께 하얀 원판이 퍼지며 사라진다(임시)
local waterLevel = 0 -- 수면 높이. start에서 Map.Sea.Surface로 정한다
local function splash(at: Vector3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Shape = Enum.PartType.Cylinder
	anchor.Color = SPLASH_COLOR
	anchor.Material = Enum.Material.SmoothPlastic
	anchor.Transparency = 0.2
	anchor.Size = Vector3.new(0.2, 1, 1)
	anchor.CFrame = CFrame.new(at.X, waterLevel, at.Z) * CFrame.Angles(0, 0, math.rad(90))
	anchor.Parent = workspace
	oneShot(SPLASH_SOUND, anchor)
	local tween = game:GetService("TweenService"):Create(anchor, TweenInfo.new(SPLASH_TIME), {
		Size = Vector3.new(0.2, SPLASH_SIZE, SPLASH_SIZE),
		Transparency = 1,
	})
	tween.Completed:Connect(function()
		task.delay(SPLASH_TIME, function()
			anchor:Destroy()
		end)
	end)
	tween:Play()
end

-- 침몰 연출 1차(S14): 배 자리에서 물기둥이 솟고, 화면이 흔들리고, 침몰 소리와 0점 소리
local function sinkShow(at: Vector3)
	local column = Instance.new("Part")
	column.Anchored = true
	column.CanCollide = false
	column.CanQuery = false
	column.CanTouch = false
	column.Shape = Enum.PartType.Cylinder
	column.Color = SPLASH_COLOR
	column.Material = Enum.Material.SmoothPlastic
	column.Transparency = 0.15
	column.Size = Vector3.new(1, COLUMN_WIDTH, COLUMN_WIDTH)
	column.CFrame = CFrame.new(at.X, waterLevel, at.Z) * CFrame.Angles(0, 0, math.rad(90))
	column.Parent = workspace
	oneShot(SINK_SOUND, column, SINK_PITCH)
	oneShot(ZERO_SOUND, workspace)
	local tweens = game:GetService("TweenService")
	local rise = tweens:Create(column, TweenInfo.new(COLUMN_TIME / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(COLUMN_HEIGHT, COLUMN_WIDTH, COLUMN_WIDTH),
		CFrame = CFrame.new(at.X, waterLevel + COLUMN_HEIGHT / 2, at.Z) * CFrame.Angles(0, 0, math.rad(90)),
	})
	rise.Completed:Connect(function()
		local fade = tweens:Create(column, TweenInfo.new(COLUMN_TIME / 2), { Transparency = 1 })
		fade.Completed:Connect(function()
			column:Destroy()
		end)
		fade:Play()
	end)
	rise:Play()

	-- 화면 흔들림: 내 캐릭터의 카메라 위치를 잠깐 흔든다
	local character = game:GetService("Players").LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local started = os.clock()
		local connection: RBXScriptConnection
		connection = game:GetService("RunService").RenderStepped:Connect(function()
			if os.clock() - started >= SHAKE_TIME or humanoid.Parent == nil then
				humanoid.CameraOffset = Vector3.zero
				connection:Disconnect()
				return
			end
			local size = SHAKE_SIZE * (1 - (os.clock() - started) / SHAKE_TIME)
			humanoid.CameraOffset = Vector3.new((math.random() - 0.5) * size, (math.random() - 0.5) * size, 0)
		end)
	end
end

function FxController.start()
	local boat = workspace:WaitForChild("Map"):WaitForChild("Boat")
	local surface = workspace.Map:WaitForChild("Sea"):WaitForChild("Surface") :: BasePart
	waterLevel = surface.Position.Y + surface.Size.Y / 2
	local hull = boat:WaitForChild("Hull") :: BasePart
	local mast = boat:WaitForChild("Mast")

	local fx = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Fx") :: RemoteEvent
	fx.OnClientEvent:Connect(function(name: string, ...)
		print(`Fx {name}`, ...)
		if name == "Bell" then
			oneShot(BELL_SOUND, mast, nil, BELL_VOLUME)
		elseif name == "Place" then
			oneShot(PLACE_SOUND, hull)
		elseif name == "Sink" then
			sinkShow(hull.Position)
		elseif name == "Horn" then
			oneShot(HORN_SOUND, hull, HORN_PITCH)
		elseif name == "Splash" then
			splash(... :: Vector3)
		elseif name == "Fanfare" then
			-- 이번 배 1등에게 팡파르(SC-8). 모두에게 들린다
			oneShot(FANFARE_SOUND, workspace)
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
