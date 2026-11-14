--!strict
-- 판(S23): 배 BOATS_PER_MATCH척을 한 판으로 묶는다. 총점, 왕관, 최종 순위와 단상, 도중 참가자의 시작 총점(S24).
-- 단계를 바꾸는 것은 RoundService다. 이 모듈은 RoundService가 부르는 때(판 시작, 배가 끝남, 단상)에 총점과 순위를 맡는다.
-- 그래서 RoundService를 require하지 않는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local ScoreRules = require(ReplicatedStorage.Shared.Rules.ScoreRules)
local JoinRules = require(ReplicatedStorage.Shared.Rules.JoinRules)
local ParticipantService = require(script.Parent.ParticipantService)

local MatchService = {}

local PODIUM_RANKS = 3 -- 단상에 서는 등수(GP-15)
local PODIUM_SPACING = 1.6 -- 같은 단에 여럿이 설 때 사이 간격(스터드). 모양의 값이다

local podium: Instance -- Map.Beach.Podium (Step1~3)

local matchIndex = 0
local matchStartedAt = 0 -- 판이 시작된 서버 시각
local inFinal = false -- 마지막 배가 끝나 최종 결과를 보여 주는 중
local finalRanking: { ScoreRules.Rank } = {} -- 마지막 배가 끝난 순간의 순위. 그 뒤에 들어온 사람은 없다(S24)
local leftTotals: { [number]: number } = {} -- 이번 판에서 나간 사람의 계정 번호 → 나가기 전 총점(GP-20)
local shipSizes: { string } = {} -- 이번 판 배들의 크기, 들어오는 순서대로(S28). 서버만 안다
local random = Random.new()

-- SHIP_SIZE_MIX대로 한 판의 크기를 정하고 순서를 섞는다(GP-18, VR-2)
local function drawShipSizes(): { string }
	local sizes: { string } = {}
	for _, size in { Types.ShipSize.Small, Types.ShipSize.Normal, Types.ShipSize.Large } do
		for _ = 1, Config.SHIP_SIZE_MIX[size] or 0 do
			table.insert(sizes, size)
		end
	end
	for index = #sizes, 2, -1 do
		local other = random:NextInteger(1, index)
		sizes[index], sizes[other] = sizes[other], sizes[index]
	end
	return sizes
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function totalOf(player: Player): number
	local record = ParticipantService.recordOf(player)
	return (record and record:GetAttribute("TotalScore") :: number?) or 0
end

-- 지금 있는 참가자의 총점(슬롯 문자열 → 총점). except는 막 나가는 사람
local function totals(except: Player?): { [string]: number }
	local result: { [string]: number } = {}
	for _, player in ParticipantService.players() do
		local slot = ParticipantService.slotOf(player)
		-- 기록이 아직 없는 참가자(지금 막 들어오는 중)는 뺀다. 넣으면 그 사람의 0이 "가장 낮은 총점"이 된다
		if slot and player ~= except and ParticipantService.recordOf(player) ~= nil then
			result[tostring(slot)] = totalOf(player)
		end
	end
	return result
end

-- 왕관: 총점이 가장 높은 참가자(동점이면 모두). 총점이 모두 0이면 아무도 쓰지 않는다(SC-7, GP-16)
function MatchService.refreshCrowns(except: Player?)
	local isLeader: { [string]: boolean } = {}
	for _, slot in ScoreRules.leaders(totals(except)) do
		isLeader[slot] = true
	end
	for _, player in ParticipantService.players() do
		local slot = ParticipantService.slotOf(player)
		local record = ParticipantService.recordOf(player)
		if slot and record then
			record:SetAttribute("Crown", player ~= except and isLeader[tostring(slot)] == true)
		end
	end
end

-- 판 시작(MatchIntro에 들어갈 때). 총점을 0으로, 왕관과 선장 모자를 벗긴다(FL-9)
function MatchService.beginMatch()
	if inFinal then
		-- 앞 판이 끝까지 갔다. 판의 길이를 한 줄 남긴다
		print(`MATCH,{matchIndex},{string.format("%.2f", now() - matchStartedAt)}`)
	end
	matchIndex += 1
	matchStartedAt = now()
	inFinal = false
	finalRanking = {}
	shipSizes = drawShipSizes()
	table.clear(leftTotals)
	for _, player in ParticipantService.players() do
		local record = ParticipantService.recordOf(player)
		if record then
			record:SetAttribute("TotalScore", 0)
			record:SetAttribute("BoatScore", 0) -- 지난 판 마지막 배의 숫자가 새 판 머리 위에 남지 않게
			record:SetAttribute("Crown", false)
			record:SetAttribute("Hat", false)
		end
	end
end

function MatchService.matchIndex(): number
	return matchIndex
end

-- 이번 판 몇 번째 배의 크기. 그 배가 들어올 때 RoundService가 묻는다. 구성에 없는 번호면 보통 배다
function MatchService.shipSize(boatIndex: number): string
	return shipSizes[boatIndex] or Types.ShipSize.Normal
end

-- 이번 판의 마지막 배인지(FL-7)
function MatchService.isLastBoat(boatIndex: number): boolean
	return boatIndex >= Config.BOATS_PER_MATCH
end

-- 배가 끝난 순간, 점수를 굳힌 직후에 부른다. 그 배의 점수를 총점에 더한다(SC-4).
-- 마지막 배는 LAST_BOAT_MULTIPLIER를 곱한다. 가라앉힌 사람은 굳힌 점수가 이미 0이라 0을 더한다(SC-3)
function MatchService.boatEnded(boatIndex: number, scores: { [string]: number })
	local last = MatchService.isLastBoat(boatIndex)
	local multiplier = if last then Config.LAST_BOAT_MULTIPLIER else 1
	for _, player in ParticipantService.players() do
		local slot = ParticipantService.slotOf(player)
		local record = ParticipantService.recordOf(player)
		if slot and record then
			local total = ScoreRules.addToTotal(totalOf(player), scores[tostring(slot)] or 0, multiplier)
			record:SetAttribute("TotalScore", total)
		end
	end
	MatchService.refreshCrowns()
	if last then
		-- 순위는 이 순간의 참가자로 정한다. 동점이면 마지막 배 점수가 높은 쪽이 앞선다(SC-5)
		finalRanking = ScoreRules.ranking(totals(), scores)
		inFinal = true
	end
end

-- 최종 결과의 단상(FinalPodium에 들어갈 때). 1~3등 캐릭터를 단 위로 옮긴다. 공동 순위는 같은 단에 선다(GP-15)
function MatchService.showPodium()
	local onStep: { [number]: { Player } } = {}
	for _, entry in finalRanking do
		local slot = tonumber(entry.id)
		local player = slot and ParticipantService.playerOf(slot)
		if player and entry.rank <= PODIUM_RANKS then
			local list = onStep[entry.rank] or {}
			onStep[entry.rank] = list
			table.insert(list, player)
		end
	end
	local text = {}
	for _, entry in finalRanking do
		table.insert(text, `{entry.rank}등 슬롯 {entry.id}`)
	end
	print(`최종 순위: {table.concat(text, ", ")}`)
	for rank, list in onStep do
		local step = podium:FindFirstChild("Step" .. rank) :: BasePart?
		if step == nil then
			continue
		end
		local top = step.Position + Vector3.new(0, step.Size.Y / 2, 0)
		for index, player in list do
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if character and rootPart and humanoid then
				-- 같은 단의 여럿은 옆으로 나란히 선다. 바다 쪽(해변의 다른 사람들 쪽)을 본다
				local offset = (index - (#list + 1) / 2) * PODIUM_SPACING
				local position = top + Vector3.new(offset, humanoid.HipHeight + rootPart.Size.Y / 2, 0)
				character:PivotTo(CFrame.lookAt(position, position - Vector3.zAxis))
				rootPart.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end
end

-- 새로 들어오는 사람의 시작 총점(JN-1, GP-20). 참가자 기록을 만드는 순간에 ParticipantService가 부른다.
-- 최종 결과 중에 들어온 사람은 순위에 없고, 새 판에서 다른 사람과 함께 0에서 시작한다
function MatchService.startTotalFor(userId: number): number
	if inFinal then
		return 0
	end
	local list = {}
	for _, total in totals() do
		table.insert(list, total)
	end
	return JoinRules.startTotal(list, leftTotals[userId], Config.JOIN_SCORE_OFFSET)
end

function MatchService.start()
	podium = workspace:WaitForChild("Map"):WaitForChild("Beach"):WaitForChild("Podium")
	ParticipantService.setStartTotal(MatchService.startTotalFor)
	-- 들어온 사람의 시작 총점이 가장 높은 총점과 같으면 왕관을 함께 쓴다(S24)
	ParticipantService.onJoined(function()
		MatchService.refreshCrowns()
	end)
	-- 나간 사람은 총점과 순위에서 바로 빠진다. 왕관은 남은 사람 가운데 다시 정한다.
	-- 같은 판에 다시 들어올 때를 위해 나가기 전 총점을 판이 끝날 때까지 적어 둔다(GP-20)
	ParticipantService.onLeaving(function(player)
		-- 빼는 봇의 총점은 버린다(S25)
		if not inFinal and not ParticipantService.isBot(player) then
			leftTotals[player.UserId] = totalOf(player)
		end
		MatchService.refreshCrowns(player)
	end)
end

return MatchService
