--!strict
-- 기록 장치(S15). 배 한 척이 끝날 때마다 서버 출력에 쉼표로 나눈 한 줄을 남기고, 지금까지의 요약을 계산한다.
-- 숨은 한계가 들어간 기록은 서버에만 있다. 게임 주인에게 보내는 요약에는 한계를 넣지 않는다(BT-1).
-- 판정 순서를 바꾸지 않도록, 기록은 판정 함수가 끝난 뒤에 부른다. 이 모듈은 다른 서비스를 require하지 않는다
-- (서비스들이 이 모듈을 부른다).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local ParticipantService = require(script.Parent.ParticipantService)

local State = Types.ParticipantState
local Kind = Types.CrateKind

local Telemetry = {}

-- "가만히 서 있던 시간"은 1초 동안 IDLE_MOVE_THRESHOLD도 움직이지 않은 시간이다(S15의 정의).
-- 규칙의 수치가 아니라 재는 방법의 정의라 Config에 두지 않는다
local STILL_WINDOW = 1

local COLUMNS = {
	"time", "boat", "P", "humans", "bots", "rangeLo", "rangeHi", "limit",
	"firstBellAt", "firstBellCause", "gap1", "gap2", "endAt", "result", "sinkerSlot",
	"weight", "markWeight", "oneMoreSmall", "oneMoreMedium", "oneMoreLarge", "oneMoreGold",
	"participants", -- 슬롯:점수:실은 상자:가만히 선 초:물에 빠진 횟수 를 | 로 이음
	"hugTries", "hugSuccess", "reclaims", "repicks", -- S21에서 채운다
	"goldSlot", "goldWeight", "goldResult", "totals", -- S26에서 채운다
}

type PersonLog = { crates: number, still: number, falls: number }
type Round = {
	startedAt: number,
	boat: number,
	p: number,
	humans: number,
	bots: number,
	lo: number,
	hi: number,
	limit: number,
	gap1: number,
	gap2: number,
	firstBellAt: number?,
	firstBellCause: string?,
	oneMore: { [string]: number },
	people: { [number]: PersonLog },
}
type Row = {
	length: number,
	firstBellAt: number?,
	cap: boolean,
	sank: boolean,
	oneMore: number,
	still: { number },
}

local current: Round? = nil
local rows: { Row } = {}
local pickedAt: { [Player]: number } = {} -- 손에 든 상자를 든 서버 시각("하나 더"는 든 시각으로 가른다)
local stillAnchor: { [Player]: { at: number, position: Vector3, counted: boolean } } = {}
local ownerSummary: RemoteEvent

local function now(): number
	return workspace:GetServerTimeNow()
end

local function person(player: Player): PersonLog?
	local round = current
	local slot = ParticipantService.slotOf(player)
	if round == nil or slot == nil then
		return nil
	end
	local log = round.people[slot]
	if log == nil then
		log = { crates = 0, still = 0, falls = 0 }
		round.people[slot] = log
	end
	return log
end

local function fmt(value: number?): string
	if value == nil then
		return ""
	end
	return string.format("%.2f", value)
end

-- Loading에 들어갈 때. 숨은 한계와 간격은 서버 안에서만 넘어온다
function Telemetry.beginRound(info: { boat: number, p: number, lo: number, hi: number, limit: number, gap1: number, gap2: number })
	local humans = #Players:GetPlayers()
	current = {
		startedAt = now(),
		boat = info.boat,
		p = info.p,
		humans = humans,
		bots = 0, -- 봇은 S25
		lo = info.lo,
		hi = info.hi,
		limit = info.limit,
		gap1 = info.gap1,
		gap2 = info.gap2,
		firstBellAt = nil,
		firstBellCause = nil,
		oneMore = {},
		people = {},
	}
	table.clear(stillAnchor)
	for _, player in ParticipantService.players() do
		person(player)
	end
end

-- 첫 종. cause는 "band"(띠에 닿음) 또는 "cap"(상한)
function Telemetry.firstBell(cause: string)
	local round = current
	if round and round.firstBellAt == nil then
		round.firstBellAt = now() - round.startedAt
		round.firstBellCause = cause
	end
end

function Telemetry.pickedUp(player: Player)
	pickedAt[player] = now()
end

-- 갑판에 놓였다. 첫 종 뒤에 든 상자면 "하나 더"
function Telemetry.placed(player: Player, kind: string)
	local round = current
	local log = person(player)
	if round == nil or log == nil then
		return
	end
	log.crates += 1
	local picked = pickedAt[player]
	if round.firstBellAt ~= nil and picked ~= nil and picked - round.startedAt >= (round.firstBellAt :: number) then
		round.oneMore[kind] = (round.oneMore[kind] or 0) + 1
	end
	pickedAt[player] = nil
end

function Telemetry.fellIn(player: Player)
	local log = person(player)
	if log then
		log.falls += 1
	end
end

-- 첫 종 뒤 Loading 동안 매 프레임: 빈손으로 STILL_WINDOW 넘게 IDLE_MOVE_THRESHOLD도 안 움직인 시간을 더한다.
-- 상자를 든 시간과 물속에 있는 시간은 넣지 않는다
function Telemetry.watch(dt: number)
	local round = current
	if round == nil or round.firstBellAt == nil then
		return
	end
	local t = now()
	for _, player in ParticipantService.players() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local log = person(player)
		if root == nil or log == nil then
			continue
		end
		local anchor = stillAnchor[player]
		if ParticipantService.stateOf(player) ~= State.Empty then
			stillAnchor[player] = nil
		elseif anchor == nil or (root.Position - anchor.position).Magnitude > Config.IDLE_MOVE_THRESHOLD then
			stillAnchor[player] = { at = t, position = root.Position, counted = false }
		elseif t - anchor.at >= STILL_WINDOW then
			-- 1초를 처음 넘은 순간 그 1초를 한꺼번에 더하고, 그 뒤로는 흐른 만큼
			log.still += if anchor.counted then dt else t - anchor.at
			anchor.counted = true
		end
	end
end

local function summaryText(): { string }
	local count = #rows
	if count == 0 then
		return { "기록된 배 없음" }
	end
	local sank, length, toBell, bellCount, oneMore, cap = 0, 0, 0, 0, 0, 0
	local stillSum, stillCount, stillMax = 0, 0, 0
	for _, row in rows do
		if row.sank then sank += 1 end
		length += row.length
		if row.firstBellAt then
			toBell += row.firstBellAt
			bellCount += 1
		end
		if row.cap then cap += 1 end
		oneMore += row.oneMore
		for _, still in row.still do
			stillSum += still
			stillCount += 1
			stillMax = math.max(stillMax, still)
		end
	end
	return {
		`배 {count}척, 침몰 {sank}척 ({string.format("%.0f", sank / count * 100)}%)`,
		`라운드 평균 {fmt(length / count)}초, 첫 종까지 평균 {fmt(if bellCount > 0 then toBell / bellCount else nil)}초`,
		`하나 더 평균 {fmt(oneMore / count)}개/척`,
		`첫 종 뒤 가만히 선 시간: 평균 {fmt(if stillCount > 0 then stillSum / stillCount else 0)}초, 최대 {fmt(stillMax)}초`,
		`상한에 울린 첫 종 {cap}척`,
	}
end

local function sendSummary()
	local lines = summaryText()
	for _, player in Players:GetPlayers() do
		if Telemetry.isOwner(player) then
			ownerSummary:FireClient(player, lines)
		end
	end
end

-- 라운드가 끝나는 순간(출항 또는 침몰). 점수를 굳힌 뒤에 부른다
function Telemetry.endRound(result: string, sinkerSlot: number?, weight: number, mark: number)
	local round = current
	if round == nil then
		return
	end
	current = nil
	local endAt = now() - round.startedAt
	local people = {}
	local stills = {}
	local slots = {}
	for slot in round.people do
		table.insert(slots, slot)
	end
	table.sort(slots)
	for _, slot in slots do
		local log = round.people[slot]
		local record = ReplicatedStorage:FindFirstChild("Participants") and ReplicatedStorage.Participants:FindFirstChild(tostring(slot))
		local score = record and record:GetAttribute("BoatScore") or 0
		table.insert(people, `{slot}:{score}:{log.crates}:{fmt(log.still)}:{log.falls}`)
		table.insert(stills, log.still)
	end
	local oneMoreTotal = 0
	for _, n in round.oneMore do
		oneMoreTotal += n
	end
	local values = {
		fmt(round.startedAt), tostring(round.boat), tostring(round.p), tostring(round.humans), tostring(round.bots),
		tostring(round.lo), tostring(round.hi), tostring(round.limit),
		fmt(round.firstBellAt), round.firstBellCause or "", fmt(round.gap1), fmt(round.gap2),
		fmt(endAt), result, if sinkerSlot then tostring(sinkerSlot) else "",
		tostring(weight), tostring(mark),
		tostring(round.oneMore[Kind.Small] or 0), tostring(round.oneMore[Kind.Medium] or 0),
		tostring(round.oneMore[Kind.Large] or 0), tostring(round.oneMore[Kind.Gold] or 0),
		table.concat(people, "|"),
		"", "", "", "",
		"", "", "", "",
	}
	print("TELEMETRY," .. table.concat(values, ","))
	table.insert(rows, {
		length = endAt,
		firstBellAt = round.firstBellAt,
		cap = round.firstBellCause == "cap",
		sank = result == "sank",
		oneMore = oneMoreTotal,
		still = stills,
	})
	sendSummary()
end

-- 게임 주인인지(주인 계정 번호와 같은 사람)
function Telemetry.isOwner(player: Player): boolean
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

-- 테스트를 시작하기 직전에 지금까지의 기록을 비운다
function Telemetry.reset()
	table.clear(rows)
	print("TELEMETRY 기록을 비움")
	sendSummary()
end

function Telemetry.summary(): { string }
	return summaryText()
end

function Telemetry.start()
	ownerSummary = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("OwnerSummary") :: RemoteEvent
	print("TELEMETRY," .. table.concat(COLUMNS, ","))
	Players.PlayerAdded:Connect(function(player)
		if Telemetry.isOwner(player) then
			ownerSummary:FireClient(player, summaryText())
		end
	end)
	for _, player in Players:GetPlayers() do
		if Telemetry.isOwner(player) then
			ownerSummary:FireClient(player, summaryText())
		end
	end
	RunService.Heartbeat:Connect(Telemetry.watch)
end

return Telemetry
