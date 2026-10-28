--!strict
-- 라운드 단계와 시간. 배를 들이고 내보낸다.
-- 단계를 바꾸는 곳은 setPhase 하나다. 셋째 종, 침몰(S09), 사람이 다 나감이 모두 이 함수를 지난다.
-- 뽑은 종 간격과 다음 종 시각은 이 모듈의 지역 변수에만 둔다(숨은 값).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local BellRules = require(ReplicatedStorage.Shared.Rules.BellRules)
local BoatService = require(script.Parent.BoatService)
local DevTools = require(script.Parent.DevTools)

local Phase = Types.Phase

local RoundService = {}

local boat: Model
local fx: RemoteEvent
local random = Random.new()

local phase: string? = nil
local phaseStartedAt = 0 -- 서버 시각. 다음 단계는 앞 단계가 끝나기로 한 시각에서 시작한다
local phaseEnteredAt = 0 -- 실제로 단계에 들어간 서버 시각. 길이 확인용
local boatIndex = 0
local bells: BellRules.Bells? = nil
local listeners: { (newPhase: string?, oldPhase: string?) -> () } = {}
local sinkerSlot: number? = nil -- 이번 배를 가라앉힌 참가자(S11에서 점수에 쓴다)

-- 시간으로 끝나는 단계의 길이와 다음 단계
local DURATION: { [string]: number } = {
	[Phase.Departing] = Config.SETTLE_SHOW_TIME,
	[Phase.Sinking] = Config.SETTLE_SHOW_TIME,
	[Phase.Scoring] = Config.SETTLE_SCORE_TIME,
	[Phase.Arriving] = Config.SETTLE_ARRIVE_TIME,
}
local NEXT: { [string]: string } = {
	[Phase.Departing] = Phase.Scoring,
	[Phase.Sinking] = Phase.Scoring,
	[Phase.Scoring] = Phase.Arriving,
	[Phase.Arriving] = Phase.Loading,
}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function nextGaps(): (number, number)
	local forced = DevTools.forcedBellGaps()
	if forced ~= nil then
		return forced[1], forced[2]
	end
	return BellRules.drawGaps(Config.BELL_GAP_MIN, Config.BELL_GAP_MAX, function()
		return random:NextNumber()
	end)
end

-- 갑판 위 캐릭터를 선착장 머리로 내려 준다(GP-6)
local function landDeckPeople()
	local head = BoatService.dockHeadTop()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if character and rootPart and humanoid and BoatService.isOnDeck(rootPart.Position) then
			local height = humanoid.HipHeight + rootPart.Size.Y / 2
			character:PivotTo(head * CFrame.new(0, height, 0))
			rootPart.AssemblyLinearVelocity = Vector3.zero
		end
	end
end

local function onEnter(newPhase: string)
	if newPhase == Phase.Arriving then
		sinkerSlot = nil
		boatIndex += 1
		boat:SetAttribute("BoatIndex", boatIndex)
		boat:SetAttribute("BellCount", 0)
		BoatService.sailIn(Config.SETTLE_ARRIVE_TIME)
	elseif newPhase == Phase.Loading then
		-- P는 지금은 접속해 있는 사람 수(S13에서 제대로 센다). 시험할 때는 DEBUG_FORCE_P
		local p = DevTools.forcedP() or math.max(#Players:GetPlayers(), 1)
		BoatService.startRound(p)
		local gap1, gap2 = nextGaps()
		bells = BellRules.newBells(Config.FIRST_BELL_CAP[Types.ShipSize.Normal], gap1, gap2)
		print(`배 {boatIndex} 종 간격 {string.format("%.2f", gap1)}, {string.format("%.2f", gap2)}`)
		boat:SetAttribute("BellCount", 0)
		fx:FireAllClients("Horn")
	elseif newPhase == Phase.Departing then
		landDeckPeople()
		BoatService.sailOut(Config.SETTLE_SHOW_TIME)
	elseif newPhase == Phase.Sinking then
		BoatService.sink(Config.SETTLE_SHOW_TIME)
	end
end

-- 단계를 바꾸는 유일한 곳. startedAt을 주면 그 시각을 새 단계의 시작으로 친다
function RoundService.setPhase(newPhase: string?, startedAt: number?)
	local t = startedAt or now()
	if phase ~= nil then
		print(`단계 {phase} 끝: 정한 길이 {string.format("%.2f", t - phaseStartedAt)}초, 실제 {string.format("%.2f", now() - phaseEnteredAt)}초`)
	end
	local oldPhase = phase
	phase = newPhase
	phaseStartedAt = t
	phaseEnteredAt = now()
	boat:SetAttribute("Phase", newPhase)
	if newPhase == nil then
		bells = nil
		BoatService.setAway()
	else
		onEnter(newPhase)
	end
	for _, listener in listeners do
		listener(newPhase, oldPhase)
	end
end

-- 단계가 바뀔 때마다 부를 함수를 건다. 이 모듈이 다른 서비스를 require하지 않도록 거꾸로 알린다
function RoundService.onPhaseChanged(listener: (newPhase: string?, oldPhase: string?) -> ())
	table.insert(listeners, listener)
end

function RoundService.getPhase(): string?
	return phase
end

-- 침몰(BT-6, BT-8). 놓기 처리에서 "침몰"이 돌아온 그 자리에서 부른다. 상태만 바꾸고 바로 끝난다.
-- placerSlot은 그 상자를 놓은 참가자의 슬롯(시험용 상자면 nil)
function RoundService.sink(placerSlot: number?, placerName: string?)
	if phase ~= Phase.Loading then
		return
	end
	sinkerSlot = placerSlot
	print(`침몰. 가라앉힌 사람: {placerName or "없음(시험용 상자)"} (슬롯 {tostring(placerSlot)})`)
	bells = nil -- 남은 종의 시각을 버린다
	RoundService.setPhase(Phase.Sinking)
	fx:FireAllClients("Sink", placerSlot)
end

-- 이번 배를 가라앉힌 참가자의 슬롯. 가라앉지 않았으면 nil
function RoundService.getSinker(): number?
	return sinkerSlot
end

local function step()
	if phase == nil then
		return
	end
	local elapsed = now() - phaseStartedAt

	if phase == Phase.Loading then
		local current = bells
		if current == nil then
			return
		end
		BellRules.tick(current, elapsed)
		if boat:GetAttribute("BellCount") ~= current.count then
			boat:SetAttribute("BellCount", current.count)
		end
		-- 셋째 종이 울리는 순간 출항이다(BL-4)
		local thirdAt = current.thirdAt
		if thirdAt ~= nil and elapsed >= thirdAt then
			RoundService.setPhase(Phase.Departing, phaseStartedAt + thirdAt)
		end
		return
	end

	local duration = DURATION[phase]
	if duration ~= nil and elapsed >= duration then
		RoundService.setPhase(NEXT[phase], phaseStartedAt + duration)
	end
end

function RoundService.start()
	local map = workspace:WaitForChild("Map")
	boat = map:WaitForChild("Boat") :: Model
	fx = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Fx") :: RemoteEvent

	-- 사람이 처음 들어온 순간 Arriving부터. 모두 나가면 멈춘다
	Players.PlayerAdded:Connect(function()
		if phase == nil then
			RoundService.setPhase(Phase.Arriving)
		end
	end)
	Players.PlayerRemoving:Connect(function(leaving)
		for _, player in Players:GetPlayers() do
			if player ~= leaving then
				return
			end
		end
		RoundService.setPhase(nil)
	end)
	if #Players:GetPlayers() > 0 then
		RoundService.setPhase(Phase.Arriving)
	end

	RunService.Heartbeat:Connect(step)
end

return RoundService
