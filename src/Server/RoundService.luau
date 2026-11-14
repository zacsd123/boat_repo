--!strict
-- 라운드 단계와 시간. 배를 들이고 내보낸다. 판(S23)의 단계(MatchIntro, 최종 결과 셋)도 여기서 돈다.
-- 단계를 바꾸는 곳은 setPhase 하나다. 셋째 종, 침몰(S09), 사람이 다 나감이 모두 이 함수를 지난다.
-- 종(간격, 시각)은 BellService가, 총점과 순위는 MatchService가 맡는다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local BoatService = require(script.Parent.BoatService)
local BellService = require(script.Parent.BellService)
local ScoreService = require(script.Parent.ScoreService)
local ParticipantService = require(script.Parent.ParticipantService)
local MatchService = require(script.Parent.MatchService)
local Telemetry = require(script.Parent.Telemetry)
local DevTools = require(script.Parent.DevTools)

local Phase = Types.Phase

local RoundService = {}

local boat: Model
local fx: RemoteEvent

local phase: string? = nil
local phaseStartedAt = 0 -- 서버 시각. 다음 단계는 앞 단계가 끝나기로 한 시각에서 시작한다
local phaseEnteredAt = 0 -- 실제로 단계에 들어간 서버 시각. 길이 확인용
local boatIndex = 0 -- 이번 판의 몇 번째 배인지
local listeners: { (newPhase: string?, oldPhase: string?) -> () } = {}
local endingListeners: { (sank: boolean) -> () } = {}
local beforeLoadingListeners: { () -> () } = {}
local sinkerSlot: number? = nil -- 이번 배를 가라앉힌 참가자(S11에서 점수에 쓴다)
local sank = false -- 이번 배가 가라앉았는지. 마지막 배는 단계 이름(FinalShow)으로 가를 수 없어서 따로 적는다
local shipSize: string = Types.ShipSize.Normal -- 지금 배의 크기(S28)

-- 시간으로 끝나는 단계의 길이와 다음 단계
local DURATION: { [string]: number } = {
	[Phase.MatchIntro] = Config.MATCH_START_TIME,
	[Phase.Departing] = Config.SETTLE_SHOW_TIME,
	[Phase.Sinking] = Config.SETTLE_SHOW_TIME,
	[Phase.Scoring] = Config.SETTLE_SCORE_TIME,
	[Phase.Arriving] = Config.SETTLE_ARRIVE_TIME,
	[Phase.FinalShow] = Config.FINAL_SHOW_TIME,
	[Phase.FinalLastScore] = Config.FINAL_LAST_SCORE_TIME,
	[Phase.FinalPodium] = Config.FINAL_PODIUM_TIME,
}
local NEXT: { [string]: string } = {
	[Phase.MatchIntro] = Phase.Loading,
	[Phase.Departing] = Phase.Scoring,
	[Phase.Sinking] = Phase.Scoring,
	[Phase.Scoring] = Phase.Arriving,
	[Phase.Arriving] = Phase.Loading,
	-- 마지막 배 뒤에는 정산의 뒤 두 부분을 건너뛰고 최종 결과로 간다(FL-8). 끝나면 새 판이다(FL-9)
	[Phase.FinalShow] = Phase.FinalLastScore,
	[Phase.FinalLastScore] = Phase.FinalPodium,
	[Phase.FinalPodium] = Phase.MatchIntro,
}

local function now(): number
	return workspace:GetServerTimeNow()
end

-- 갑판 위 캐릭터를 선착장 머리로 내려 준다(GP-6)
local function landDeckPeople()
	local head = BoatService.dockHeadTop()
	for _, player in ParticipantService.players() do
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

-- 새 배가 들어온다. duration 동안 바다 쪽에서 선착장 옆자리로
local function arrive(duration: number)
	sinkerSlot = nil
	sank = false
	boat:SetAttribute("BoatIndex", boatIndex)
	boat:SetAttribute("BellCount", 0)
	-- 배의 크기는 들어올 때 드러난다(VR-2). 클라이언트는 지금 배의 크기만 안다
	shipSize = DevTools.forcedSize() or MatchService.shipSize(boatIndex)
	boat:SetAttribute("ShipSize", shipSize)
	-- 인원은 Loading에서 센다. 들어오는 동안에는 어림한 인원으로 선체의 높이를 그린다
	local estimate = math.max(#ParticipantService.players(), Config.BOT_FILL_TO)
	BoatService.sailIn(duration, shipSize, DevTools.forcedP() or estimate)
end

-- 배가 끝난 순간(출항 또는 침몰). 점수를 굳히고, 굳힌 직후에 총점에 더하고, 기록을 남기고, 연출을 시작한다.
-- 정산 연출이 도는 동안이 아니라 이 순간에 총점을 더해야 정산 중에 들어온 사람의 시작 총점이 맞는다(S24)
local function endBoat(showTime: number)
	if sank then
		ScoreService.freeze(sinkerSlot) -- 가라앉힌 사람은 0(SC-2)
	else
		BoatService.depart()
		ScoreService.freeze(nil) -- 점수는 끝나는 순간 굳힌다(SC-1)
	end
	MatchService.boatEnded(boatIndex, ScoreService.frozenScores())
	Telemetry.endRound(
		if sank then "sank" else "departed",
		sinkerSlot,
		(boat:GetAttribute("Weight") :: number?) or 0,
		(boat:GetAttribute("MarkWeight") :: number?) or 0
	)
	if sank then
		BoatService.sink(showTime)
	else
		landDeckPeople()
		BoatService.sailOut(showTime)
	end
end

local function onEnter(newPhase: string)
	if newPhase == Phase.MatchIntro then
		-- 판 시작: 총점 0. 첫 배가 들어온다(FL-3)
		MatchService.beginMatch()
		boatIndex = 1
		arrive(Config.MATCH_START_TIME)
	elseif newPhase == Phase.Arriving then
		boatIndex += 1
		arrive(Config.SETTLE_ARRIVE_TIME)
	elseif newPhase == Phase.Loading then
		-- P는 라운드가 시작되는 이 순간 한 번만 센다(JN-5). 라운드 도중에는 다시 세지 않는다.
		-- 기록은 늘 새로 시작하고, 시험할 때만 DEBUG_FORCE_P로 바꾼다
		-- 봇은 Loading에 들어가기 직전, P를 세기 전에 넣고 뺀다(S25)
		for _, listener in beforeLoadingListeners do
			listener()
		end
		local counted = ParticipantService.beginRound()
		local p = DevTools.forcedP() or counted
		BoatService.startRound(p, shipSize)
		ScoreService.startRound()
		BellService.startRound(phaseStartedAt, `배 {boatIndex}({shipSize})`, Config.FIRST_BELL_CAP[shipSize])
		local gap1, gap2 = BellService.currentGaps()
		local lo, hi = Config.limitRange(p, shipSize)
		Telemetry.beginRound({
			match = MatchService.matchIndex(),
			boat = boatIndex,
			size = shipSize,
			p = p,
			lo = lo,
			hi = hi,
			limit = BoatService.roundLimit() or 0,
			gap1 = gap1,
			gap2 = gap2,
		})
		fx:FireAllClients("Horn")
	elseif newPhase == Phase.Departing or newPhase == Phase.Sinking then
		endBoat(Config.SETTLE_SHOW_TIME)
	elseif newPhase == Phase.FinalShow then
		-- 마지막 배의 출항 또는 침몰 연출이 최종 결과의 첫 부분이다(FL-8)
		endBoat(Config.FINAL_SHOW_TIME)
	elseif newPhase == Phase.Scoring then
		ScoreService.celebrate()
	elseif newPhase == Phase.FinalPodium then
		MatchService.showPodium()
	end
end

-- 단계를 바꾸는 유일한 곳. startedAt을 주면 그 시각을 새 단계의 시작으로 친다
function RoundService.setPhase(newPhase: string?, startedAt: number?)
	local t = startedAt or now()
	if phase ~= nil then
		print(`단계 {phase} 끝: 정한 길이 {string.format("%.2f", t - phaseStartedAt)}초, 실제 {string.format("%.2f", now() - phaseEnteredAt)}초`)
	end
	local oldPhase = phase
	if oldPhase == Phase.Loading then
		ParticipantService.endRound()
		-- 라운드가 끝나는 순간. 점수를 굳히기(onEnter) 전에 알린다: 진행 중이던 끌어안기가 여기서 무효가 된다(HG-7)
		for _, listener in endingListeners do
			listener(sank)
		end
	end
	phase = newPhase
	phaseStartedAt = t
	phaseEnteredAt = now()
	boat:SetAttribute("Phase", newPhase)
	if newPhase == nil then
		BellService.stop()
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

-- Loading이 끝나는 순간, 점수를 굳히기 전에 부를 함수를 건다. sank는 침몰로 끝났는지(출항이나 모두 나감이면 false)
function RoundService.onRoundEnding(listener: (sank: boolean) -> ())
	table.insert(endingListeners, listener)
end

-- Loading에 들어가기 직전(P를 세기 전)에 부를 함수를 건다. 봇을 넣고 빼는 때다
function RoundService.onBeforeLoading(listener: () -> ())
	table.insert(beforeLoadingListeners, listener)
end

function RoundService.getPhase(): string?
	return phase
end

-- 이번 배가 가라앉았는지. 다음 배가 들어올 때까지 그대로다
function RoundService.didSink(): boolean
	return sank
end

function RoundService.getBoatIndex(): number
	return boatIndex
end

-- 시험용(DevTools): 배 번호를 바꾼다. 다음 Arriving에서 1이 더해진다
function RoundService.setBoatIndex(index: number)
	if RunService:IsStudio() then
		boatIndex = math.max(index, 0)
	end
end

-- Loading이 끝났다. 마지막 배면 정산 대신 최종 결과로 간다(FL-8)
local function endLoading(endedAt: number?)
	if MatchService.isLastBoat(boatIndex) then
		RoundService.setPhase(Phase.FinalShow, endedAt)
	elseif sank then
		RoundService.setPhase(Phase.Sinking, endedAt)
	else
		RoundService.setPhase(Phase.Departing, endedAt)
	end
end

-- 침몰(BT-6, BT-8). 놓기 처리에서 "침몰"이 돌아온 그 자리에서 부른다. 상태만 바꾸고 바로 끝난다.
-- placerSlot은 그 상자를 놓은 참가자의 슬롯(시험용 상자면 nil)
function RoundService.sink(placerSlot: number?, placerName: string?)
	if phase ~= Phase.Loading then
		return
	end
	sinkerSlot = placerSlot
	sank = true
	print(`침몰. 가라앉힌 사람: {placerName or "없음(시험용 상자)"} (슬롯 {tostring(placerSlot)})`)
	BellService.stop() -- 남은 종의 시각을 버린다
	endLoading(nil)
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
		ParticipantService.watchMovement()
		-- 셋째 종이 울린 프레임에서 바로 출항이다(BL-4)
		local departAt = BellService.tick()
		if departAt ~= nil then
			endLoading(departAt)
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

	-- 사람이 처음 들어온 순간 판 시작부터. 모두 나가면 멈춘다(FL-9)
	Players.PlayerAdded:Connect(function()
		if phase == nil then
			RoundService.setPhase(Phase.MatchIntro)
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
		RoundService.setPhase(Phase.MatchIntro)
	end

	RunService.Heartbeat:Connect(step)
end

return RoundService
