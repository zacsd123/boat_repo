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
local ALERT_SOUND = "rbxasset://sounds/electronicpingshort.wav"
local ALERT_PITCH = 1.8 -- 종소리와 헷갈리지 않게 높고 빠르게 두 번(임시)
local ALERT_REPEAT_GAP = 0.15
local RECLAIM_SOUND = "rbxasset://sounds/swordslash.wav" -- 되찾기: 잡아채는 소리(임시)
local SPLASH_SOUND = "rbxasset://sounds/impact_water.mp3"
local SPLASH_COLOR = Color3.fromRGB(220, 240, 255)
local SPLASH_SIZE = 6 -- 물보라가 퍼지는 지름(스터드). 임시 모양
local SPLASH_TIME = 0.4 -- 물보라가 퍼지고 사라지는 시간(초). 임시 모양
local BELL_ON_COLOR = Color3.fromRGB(255, 210, 60)
local GOLD_SOUND = "rbxasset://sounds/victory.wav"
local GOLD_PITCH = 1.6 -- 팡파르와 헷갈리지 않게 높고 짧게(임시)
local GOLD_PILLAR_HEIGHT = 40 -- 황금 상자 위에 서는 빛기둥(스터드). 임시 모양
local GOLD_PILLAR_WIDTH = 0.8
local GOLD_PILLAR_COLOR = Color3.fromRGB(255, 220, 80)

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

-- 갑판 밖에 놓인 황금 상자 위에 빛기둥을 세운다(S22). 상자가 치워지면 함께 사라진다
local function goldPillar(crate: Instance)
	local body = crate:WaitForChild("Body", 5) :: BasePart?
	if body == nil then
		return
	end
	local pillar = Instance.new("Part")
	pillar.Name = "Pillar"
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.CastShadow = false
	pillar.Material = Enum.Material.Neon
	pillar.Color = GOLD_PILLAR_COLOR
	pillar.Transparency = 0.5
	pillar.Size = Vector3.new(GOLD_PILLAR_WIDTH, GOLD_PILLAR_HEIGHT, GOLD_PILLAR_WIDTH)
	pillar.CFrame = CFrame.new(body.Position + Vector3.new(0, GOLD_PILLAR_HEIGHT / 2, 0))
	pillar.Parent = crate
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
		-- 개발용 흔적이다. 모형이 인자로 오면(HugAlert) 이름만 찍는다. S31에서 지운다
		local first = ...
		print(`Fx {name}`, if typeof(first) == "Instance" then first.Name else first)
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
		elseif name == "Gold" then
			-- 첫 종과 함께 바위 위에 황금 상자가 나타났다(GD-1). 빛기둥은 아래에서 상자를 보고 세운다
			oneShot(GOLD_SOUND, workspace, GOLD_PITCH)
		elseif name == "Reclaim" then
			-- 주인이 상자를 되찾았다(RC-1). 끌어안던 사람은 서버가 물 자리로 던진다
			oneShot(RECLAIM_SOUND, hull)
		elseif name == "HugAlert" then
			-- 내 상자가 끌어안겼다(HG-6). 서버가 주인에게만 보낸다. 화살표는 HudController가 그린다
			oneShot(ALERT_SOUND, workspace, ALERT_PITCH, BELL_VOLUME)
			task.delay(ALERT_REPEAT_GAP, oneShot, ALERT_SOUND, workspace, ALERT_PITCH, BELL_VOLUME)
		elseif name == "Fanfare" then
			-- 이번 배 1등에게 팡파르(SC-8). 모두에게 들린다
			oneShot(FANFARE_SOUND, workspace)
		end
	end)

	local loose = workspace.Map:WaitForChild("Loose")
	loose.ChildAdded:Connect(goldPillar)
	for _, crate in loose:GetChildren() do
		task.spawn(goldPillar, crate)
	end

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
