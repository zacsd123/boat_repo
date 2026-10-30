--!strict
-- 배 점수와 정산. 참가자마다 갑판에 놓인 자기 상자의 점수를 더해 BoatScore에 쓴다(SC-1).
-- 라운드가 끝나는 순간(Departing, Sinking에 들어갈 때) 그 값으로 굳힌다. 가라앉힌 사람은 0(SC-2).
-- 굳힌 뒤에는 사람이 나가거나 상자가 치워져도 바뀌지 않는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ScoreRules = require(ReplicatedStorage.Shared.Rules.ScoreRules)
local ParticipantService = require(script.Parent.ParticipantService)

local ScoreService = {}

local cargo: Instance -- Map.Boat.Cargo
local fx: RemoteEvent
local frozen = false -- 이번 배의 점수를 굳혔는지
local lastScores: { [string]: number } = {} -- 굳힌 점수(슬롯 문자열 → 점수)

-- 갑판의 상자 목록. 주인 없는 시험용 상자는 누구의 점수도 아니다
local function deckCrates(): { ScoreRules.DeckCrate }
	local deck: { ScoreRules.DeckCrate } = {}
	for _, crate in cargo:GetChildren() do
		local owner = crate:GetAttribute("OwnerSlot") :: number?
		local kind = crate:GetAttribute("Kind") :: string?
		if owner and kind then
			table.insert(deck, { owner = tostring(owner), score = Config.CRATE_SCORE[kind] or 0 })
		end
	end
	return deck
end

local function currentScores(sinkerSlot: number?): { [string]: number }
	local ids = {}
	for _, player in ParticipantService.players() do
		local slot = ParticipantService.slotOf(player)
		if slot then
			table.insert(ids, tostring(slot))
		end
	end
	return ScoreRules.boatScores(ids, deckCrates(), if sinkerSlot then tostring(sinkerSlot) else nil)
end

local function write(scores: { [string]: number })
	for _, player in ParticipantService.players() do
		local slot = ParticipantService.slotOf(player)
		local record = ParticipantService.recordOf(player)
		if slot and record then
			record:SetAttribute("BoatScore", scores[tostring(slot)] or 0)
		end
	end
end

-- 실린 상자가 생기거나 사라질 때(무게와 같은 때). 굳힌 뒤에는 아무것도 하지 않는다
function ScoreService.recompute()
	if frozen then
		return
	end
	write(currentScores(nil))
end

-- Loading에 들어갈 때. 이번 배 점수를 0으로
function ScoreService.startRound()
	frozen = false
	lastScores = {}
	for _, player in ParticipantService.players() do
		local record = ParticipantService.recordOf(player)
		if record then
			record:SetAttribute("BoatScore", 0)
		end
	end
end

-- 라운드가 끝나는 순간. 단계를 바꾸는 함수 안에서 부른다. 가라앉힌 사람은 0
function ScoreService.freeze(sinkerSlot: number?)
	if frozen then
		return
	end
	lastScores = currentScores(sinkerSlot)
	write(lastScores)
	frozen = true
	local text = {}
	for slot, score in lastScores do
		table.insert(text, `슬롯 {slot}={score}`)
	end
	table.sort(text)
	print(`배 점수 굳힘: {table.concat(text, ", ")}{if sinkerSlot then ` (가라앉힌 사람 슬롯 {sinkerSlot})` else ""}`)
end

-- Scoring에 들어갈 때. 이번 배 1등에게 팡파르와 선장 모자(SC-6, SC-8). 가장 높은 점수가 0이면 없다.
-- 모자는 다음 배 동안 쓰고, 다음 배의 Scoring에서 새 1등에게 넘어간다
function ScoreService.celebrate()
	local leaders = ScoreRules.leaders(lastScores)
	local isLeader: { [string]: boolean } = {}
	for _, slot in leaders do
		isLeader[slot] = true
	end
	for _, player in ParticipantService.players() do
		local slot = ParticipantService.slotOf(player)
		local record = ParticipantService.recordOf(player)
		if slot and record then
			record:SetAttribute("Hat", isLeader[tostring(slot)] == true)
		end
	end
	if #leaders > 0 then
		local slots = {}
		for _, slot in leaders do
			table.insert(slots, tonumber(slot))
		end
		fx:FireAllClients("Fanfare", slots)
	end
end

function ScoreService.start()
	cargo = workspace:WaitForChild("Map"):WaitForChild("Boat"):WaitForChild("Cargo")
	fx = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Fx") :: RemoteEvent
end

return ScoreService
