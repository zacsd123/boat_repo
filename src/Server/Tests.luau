--!strict
-- 규칙 시험 54개와 기획 문서의 예시 플레이 두 판(docs/S03-rules-and-tests.md의 표).
-- 시험 이름에 규칙 번호를 달아 둔다. 기대와 다르면 번호를 찍고 오류로 멈춘다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local BoatRules = require(Shared.Rules.BoatRules)
local BellRules = require(Shared.Rules.BellRules)
local ScoreRules = require(Shared.Rules.ScoreRules)
local InputRules = require(Shared.Rules.InputRules)
local JoinRules = require(Shared.Rules.JoinRules)
local HugRules = require(Shared.Rules.HugRules)

type Situation = InputRules.Situation
type Target = InputRules.Target
type DeckCrate = ScoreRules.DeckCrate

local Phase = Types.Phase
local State = Types.ParticipantState
local Kind = Types.CrateKind
local SCORE = Config.CRATE_SCORE
local LO4, HI4 = Config.limitRange(4)
local CAP = Config.FIRST_BELL_CAP[Types.ShipSize.Normal]

local HOLD: InputRules.HoldSettings = {
	holdTime = Config.HOLD_TIME,
	holdTolerance = Config.HOLD_TOLERANCE,
	hugEnabled = Config.HUG_ENABLED,
}

-- 기대와 다르면 오류를 낸다. 오류 글은 run이 시험 번호와 함께 모은다
local function check(label: string, actual: any, expected: any)
	if actual ~= expected then
		error(`{label}: 기대 {tostring(expected)}, 실제 {tostring(actual)}`, 0)
	end
end

-- 목록을 정렬한 뒤 쉼표로 이은 글. 순서와 상관없는 비교에 쓴다
local function joined(list: { string }): string
	local copy = table.clone(list)
	table.sort(copy)
	return table.concat(copy, ",")
end

-- 빈손 참가자가 싣는 중에 본 상황. 바꿀 칸만 넘긴다
local function situation(overrides: { [string]: any }): Situation
	local s: { [string]: any } = {
		phase = Phase.Loading,
		state = State.Empty,
		onDeck = false,
		carrying = nil,
		pickupInReach = false,
		reclaimable = false,
	}
	for key, value in overrides do
		s[key] = value
	end
	return (s :: any) :: Situation
end

local function target(mine: boolean, huggedBy: string?, covered: boolean): Target
	return { mine = mine, huggedBy = huggedBy, covered = covered }
end

local tests: { { id: string, run: () -> () } } = {}
local function test(id: string, run: () -> ())
	table.insert(tests, { id = id, run = run })
end

-- 배와 침몰 (4명 범위 40~68) ------------------------------------------------

test("T01 BT-6 무게가 한계와 같으면 버틴다", function()
	local boat = BoatRules.newBoat(LO4, HI4, 44)
	for i = 1, 11 do
		local r = BoatRules.placed(boat, SCORE.Large * i)
		check(`큰 상자 {i}번째 침몰`, r.sank, false)
	end
	check("무게", boat.weight, 44)
end)

test("T02 BT-6 한계보다 크면 침몰", function()
	local boat = BoatRules.newBoat(LO4, HI4, 44)
	for i = 1, 11 do
		BoatRules.placed(boat, SCORE.Large * i)
	end
	local r = BoatRules.placed(boat, 44 + SCORE.Small)
	check("45에서 침몰", r.sank, true)
end)

test("T03 BL-1 아래 끝에 닿는 순간 띠에 닿음", function()
	local boat = BoatRules.newBoat(LO4, HI4, 60)
	local r36 = BoatRules.placed(boat, 36)
	check("36에서 띠", r36.touchedBand, false)
	local r40 = BoatRules.placed(boat, 40)
	check("40에서 띠", r40.touchedBand, true)
	check("40에서 침몰", r40.sank, false)
end)

test("T04 BL-1 띠에 닿음은 한 번만", function()
	local boat = BoatRules.newBoat(LO4, HI4, 60)
	BoatRules.placed(boat, 36)
	BoatRules.placed(boat, 40)
	local r = BoatRules.placed(boat, 44)
	check("44에서 띠", r.touchedBand, false)
end)

test("T05 BL-5 BT-6 띠에 닿게 한 상자가 가라앉힌다", function()
	local boat = BoatRules.newBoat(LO4, HI4, 40)
	BoatRules.placed(boat, 38)
	local r = BoatRules.placed(boat, 42)
	check("42에서 띠", r.touchedBand, true)
	check("42에서 침몰", r.sank, true)
end)

test("T06 BT-5 빠져도 젖은 자국은 그대로", function()
	local boat = BoatRules.newBoat(LO4, HI4, HI4)
	BoatRules.placed(boat, 48)
	BoatRules.removed(boat, 44)
	check("무게", boat.weight, 44)
	check("젖은 자국", boat.mark, 48)
end)

test("T07 BL-1 BL-3 내려갔다 다시 올라가도 띠에 닿음은 없다", function()
	local boat = BoatRules.newBoat(LO4, HI4, HI4)
	check("42에서 띠", BoatRules.placed(boat, 42).touchedBand, true)
	BoatRules.removed(boat, 36)
	check("다시 40에서 띠", BoatRules.placed(boat, 40).touchedBand, false)
	check("젖은 자국", boat.mark, 42)
end)

test("T08 BT-7 침몰한 배에 놓기는 없던 일", function()
	local boat = BoatRules.newBoat(LO4, HI4, 40)
	BoatRules.placed(boat, 44)
	local r = BoatRules.placed(boat, 48)
	check("없던 일", r.ignored, true)
	check("무게", boat.weight, 44)
end)

test("T09 BL-4 떠난 배에 놓기는 없던 일", function()
	local boat = BoatRules.newBoat(LO4, HI4, HI4)
	BoatRules.placed(boat, 44)
	BoatRules.departed(boat)
	check("없던 일", BoatRules.placed(boat, 48).ignored, true)
end)

test("T10 CR-8 BT-6 다시 들고 다시 놓으면 새로 판정", function()
	local boat = BoatRules.newBoat(LO4, HI4, 47)
	check("46", BoatRules.placed(boat, 46).sank, false)
	BoatRules.removed(boat, 42)
	check("다시 46", BoatRules.placed(boat, 46).sank, false)
	BoatRules.removed(boat, 42)
	check("44", BoatRules.placed(boat, 44).sank, false)
	check("48", BoatRules.placed(boat, 48).sank, true)
end)

test("T11 BL-5 첫 종 전에는 가라앉지 않는다", function()
	for limit = LO4, HI4 do
		local boat = BoatRules.newBoat(LO4, HI4, limit)
		check(`한계 {limit} 무게 36`, BoatRules.placed(boat, 36).sank, false)
		check(`한계 {limit} 무게 39`, BoatRules.placed(boat, 39).sank, false)
	end
end)

-- 종 (상한 40초) ------------------------------------------------------------

test("T12 BL-1 상한 전에는 종이 없다", function()
	local bells = BellRules.newBells(CAP, 3, 5)
	check("울린 종", #BellRules.tick(bells, 39.9), 0)
	check("종 수", bells.count, 0)
end)

test("T13 BL-1 상한에 첫 종", function()
	local bells = BellRules.newBells(CAP, 3, 5)
	BellRules.tick(bells, 39.9)
	local rung = BellRules.tick(bells, 40)
	check("울린 종", rung[1], 1)
	check("종 수", bells.count, 1)
end)

test("T14 BL-2 BL-4 간격대로 둘째와 셋째 종", function()
	local bells = BellRules.newBells(CAP, 3, 5)
	check("20초 첫 종", BellRules.firstBell(bells, 20), true)
	check("22.9초", #BellRules.tick(bells, 22.9), 0)
	check("23초", BellRules.tick(bells, 23)[1], 2)
	check("27.9초", #BellRules.tick(bells, 27.9), 0)
	check("28초", BellRules.tick(bells, 28)[1], 3)
end)

test("T15 BL-2 간격은 3~7초 소수까지 고르게 따로", function()
	local random = Random.new(1)
	local function nextNumber(): number
		return random:NextNumber()
	end
	local differed, fractional = false, false
	for _ = 1, 1000 do
		local a, b = BellRules.drawGaps(Config.BELL_GAP_MIN, Config.BELL_GAP_MAX, nextNumber)
		for _, gap in { a, b } do
			if gap < Config.BELL_GAP_MIN or gap > Config.BELL_GAP_MAX then
				check("범위 밖의 간격", gap, "3~7")
			end
			if gap ~= math.floor(gap) then
				fractional = true
			end
		end
		if a ~= b then
			differed = true
		end
	end
	check("두 값이 다를 때가 있다", differed, true)
	check("정수가 아닌 값이 나온다", fractional, true)
end)

test("T16 BL-1 BL-3 첫 종은 다시 받지 않는다", function()
	local bells = BellRules.newBells(CAP, 3, 5)
	BellRules.firstBell(bells, 20)
	check("25초에 또 청함", BellRules.firstBell(bells, 25), false)
	check("셋째 종 시각", bells.thirdAt, 28)
end)

test("T17 FL-5 가장 긴 라운드는 54초", function()
	local bells = BellRules.newBells(CAP, 7, 7)
	BellRules.tick(bells, CAP)
	BellRules.tick(bells, 53.9)
	check("53.9초 종 수", bells.count, 2)
	check("54초", BellRules.tick(bells, 54)[1], 3)
end)

-- 점수 (갑판에 가의 상자 4, 4, 2와 나의 상자 4, 8과 다의 상자 1) ------------

local PEOPLE = { "ga", "na", "da" }
local function sampleDeck(): { DeckCrate }
	return {
		{ owner = "ga", score = SCORE.Large },
		{ owner = "ga", score = SCORE.Large },
		{ owner = "ga", score = SCORE.Medium },
		{ owner = "na", score = SCORE.Large },
		{ owner = "na", score = SCORE.Gold },
		{ owner = "da", score = SCORE.Small },
	}
end

test("T18 SC-1 출항하면 갑판의 내 상자 합", function()
	local s = ScoreRules.boatScores(PEOPLE, sampleDeck(), nil)
	check("가", s.ga, 10)
	check("나", s.na, 12)
	check("다", s.da, 1)
end)

test("T19 SC-2 가라앉힌 사람은 0", function()
	local s = ScoreRules.boatScores(PEOPLE, sampleDeck(), "na")
	check("가", s.ga, 10)
	check("나", s.na, 0)
	check("다", s.da, 1)
end)

test("T20 SC-3 가라앉혀도 총점은 그대로", function()
	check("가", ScoreRules.addToTotal(30, 8, 1), 38)
	check("나", ScoreRules.addToTotal(20, 0, 1), 20)
end)

test("T21 SC-4 8번째 배는 배율", function()
	check("가", ScoreRules.addToTotal(0, 10, Config.LAST_BOAT_MULTIPLIER), 20)
	check("나", ScoreRules.addToTotal(0, 12, Config.LAST_BOAT_MULTIPLIER), 24)
end)

local function rankText(ranks: { ScoreRules.Rank }): string
	local parts = {}
	for _, r in ranks do
		table.insert(parts, `{r.id}={r.rank}`)
	end
	return table.concat(parts, " ")
end

test("T22 SC-5 동점이면 마지막 배 점수", function()
	local ranks = ScoreRules.ranking({ ga = 50, na = 50, da = 40 }, { ga = 10, na = 14 })
	check("순위", rankText(ranks), "na=1 ga=2 da=3")
end)

test("T23 SC-5 그래도 같으면 공동 순위", function()
	local ranks = ScoreRules.ranking({ ga = 50, na = 50, da = 40 }, { ga = 10, na = 10 })
	check("순위", rankText(ranks), "ga=1 na=1 da=3")
end)

test("T24 SC-6 점수를 낸 사람이 없으면 선장 모자 없음", function()
	check("앞선 사람", #ScoreRules.leaders({ ga = 0, na = 0, da = 0 }), 0)
end)

test("T25 SC-6 동점이면 모두 선장 모자", function()
	check("앞선 사람", joined(ScoreRules.leaders({ ga = 12, na = 12, da = 8 })), "ga,na")
end)

test("T26 SC-7 GP-16 왕관", function()
	check("모두 0", #ScoreRules.leaders({ ga = 0, na = 0, da = 0 }), 0)
	check("가 5 나 5 다 0", joined(ScoreRules.leaders({ ga = 5, na = 5, da = 0 })), "ga,na")
end)

test("T27 HG-4 HG-7 끌어안긴 상자는 주인 점수", function()
	local deck = sampleDeck()
	deck[4].huggedBy = "ga" -- 가가 나의 큰 상자를 끌어안는 중에 배가 끝남
	local s = ScoreRules.boatScores(PEOPLE, deck, nil)
	check("나", s.na, 12)
	check("가", s.ga, 10)
end)

-- 버튼 ----------------------------------------------------------------------

test("T28 IN-2 손에 상자, 갑판 위에서 톡은 놓기", function()
	check("톡", InputRules.tap(situation({ state = State.Carrying, carrying = Kind.Large, onDeck = true })), "Place")
end)

test("T29 CR-6 손에 큰 상자, 갑판 밖에서 톡은 버리기", function()
	check("톡", InputRules.tap(situation({ state = State.Carrying, carrying = Kind.Large })), "Discard")
end)

test("T30 GD-3 황금 상자를 갑판 밖에서 놓으면 남는다", function()
	check("톡", InputRules.tap(situation({ state = State.Carrying, carrying = Kind.Gold })), "DropGold")
end)

test("T31 IN-3 빈손, 더미 앞, 싣는 중에 톡은 들기", function()
	check("톡", InputRules.tap(situation({ pickupInReach = true })), "Pickup")
end)

test("T32 FL-4 정산 중에는 들지 못한다", function()
	check("톡", InputRules.tap(situation({ phase = Phase.Scoring, pickupInReach = true })), "None")
end)

test("T33 IN-4 RC-1 갑판 위 빈손, 되찾을 상자가 있으면 되찾기", function()
	check("톡", InputRules.tap(situation({ onDeck = true, reclaimable = true })), "Reclaim")
end)

test("T34 IN-4 되찾을 상자가 없으면 힌트", function()
	check("톡", InputRules.tap(situation({ onDeck = true })), "Hint")
end)

test("T35 IN-5 HG-1 남의 상자를 꾹은 끌어안기, 톡은 힌트", function()
	local s = situation({ onDeck = true })
	check("꾹", InputRules.hold(s, target(false, nil, false), Config.HOLD_TIME, HOLD), "Hug")
	check("톡", InputRules.tap(s), "Hint")
end)

test("T36 IN-5 CR-8 내 상자를 꾹은 다시 들기", function()
	check("꾹", InputRules.hold(situation({ onDeck = true }), target(true, nil, false), Config.HOLD_TIME, HOLD), "Repick")
end)

test("T37 CR-7 든 채로 꾹은 없음", function()
	local s = situation({ onDeck = true, state = State.Carrying, carrying = Kind.Large })
	check("꾹", InputRules.hold(s, target(false, nil, false), Config.HOLD_TIME, HOLD), "None")
end)

test("T38 HG-2 이미 끌어안긴 남의 상자는 없음", function()
	check("꾹", InputRules.hold(situation({ onDeck = true }), target(false, "other", false), Config.HOLD_TIME, HOLD), "None")
end)

test("T39 GP-7 끌어안긴 내 상자는 다시 들 수 없다", function()
	check("꾹", InputRules.hold(situation({ onDeck = true }), target(true, "other", false), Config.HOLD_TIME, HOLD), "None")
end)

test("T40 GP-4 위에 상자가 쌓인 상자는 없음", function()
	check("꾹", InputRules.hold(situation({ onDeck = true }), target(false, nil, true), Config.HOLD_TIME, HOLD), "None")
end)

test("T41 WT-2 HG-3 물속과 끌어안는 중에는 아무것도 없음", function()
	for _, state in { State.InWater, State.Hugging } do
		local s = situation({ onDeck = true, state = state, pickupInReach = true, reclaimable = true })
		check(`{state} 톡`, InputRules.tap(s), "None")
		check(`{state} 꾹`, InputRules.hold(s, target(false, nil, false), Config.HOLD_TIME, HOLD), "None")
	end
end)

test("T42 GP-9 꾹 누르기 시간은 0.1초까지 봐준다", function()
	local s = situation({ onDeck = true })
	check("0.39초", InputRules.hold(s, target(false, nil, false), 0.39, HOLD), "None")
	check("0.4초", InputRules.hold(s, target(false, nil, false), 0.4, HOLD), "Hug")
end)

test("T43 KR-4 끌어안기를 끄면 남의 상자는 없음", function()
	local off: InputRules.HoldSettings = {
		holdTime = Config.HOLD_TIME,
		holdTolerance = Config.HOLD_TOLERANCE,
		hugEnabled = false,
	}
	local s = situation({ onDeck = true })
	check("남의 상자", InputRules.hold(s, target(false, nil, false), Config.HOLD_TIME, off), "None")
	check("내 상자", InputRules.hold(s, target(true, nil, false), Config.HOLD_TIME, off), "Repick")
end)

test("T44 RC-1 RC-3 RC-4 되찾을 수 있나", function()
	local range = Config.RECLAIM_RANGE
	check("빈손 갑판 거리 8", InputRules.canReclaim(State.Empty, true, 8, 10, 0, range), true)
	check("거리 8.1", InputRules.canReclaim(State.Empty, true, 8.1, 10, 0, range), false)
	check("상자를 든 상태", InputRules.canReclaim(State.Carrying, true, 8, 10, 0, range), false)
	check("물속", InputRules.canReclaim(State.InWater, true, 8, 10, 0, range), false)
	check("끌어안는 중", InputRules.canReclaim(State.Hugging, true, 8, 10, 0, range), false)
	check("갑판 밖", InputRules.canReclaim(State.Empty, false, 8, 10, 0, range), false)
	check("재사용 대기 중", InputRules.canReclaim(State.Empty, true, 8, 10, 10 + Config.RECLAIM_COOLDOWN, range), false)
end)

test("T45 GP-19 누르는 순간", function()
	local crate = target(false, nil, false)
	check("되찾을 상자가 있음", InputRules.pressStart(situation({ onDeck = true, reclaimable = true }), crate), "Tap")
	check("없고 대상이 실린 상자", InputRules.pressStart(situation({ onDeck = true }), crate), "Hold")
	check("대상이 없음", InputRules.pressStart(situation({ onDeck = true }), nil), "Tap")
end)

-- 인원과 총점 ---------------------------------------------------------------

local OFFSET = Config.JOIN_SCORE_OFFSET

test("T46 JN-1 가장 낮은 총점에서 시작", function()
	check("시작", JoinRules.startTotal({ 41, 36, 33, 14 }, nil, OFFSET), 14)
end)

test("T47 JN-1 첫 배이거나 아무도 없으면 0", function()
	check("모두 0", JoinRules.startTotal({ 0, 0, 0 }, nil, OFFSET), 0)
	check("아무도 없음", JoinRules.startTotal({}, nil, OFFSET), 0)
end)

test("T48 JN-1 봇의 총점도 센다", function()
	check("시작", JoinRules.startTotal({ 30, 12, 7 }, nil, OFFSET), 7)
end)

test("T49 GP-20 다시 들어오면 나가기 전 총점과 견준다", function()
	check("41점이던 사람", JoinRules.startTotal({ 36, 33, 14 }, 41, OFFSET), 14)
	check("14점이던 꼴찌", JoinRules.startTotal({ 41, 36, 33 }, 14, OFFSET), 14)
end)

test("T50 JN-1 JOIN_SCORE_OFFSET", function()
	check("최저 14", JoinRules.startTotal({ 14 }, nil, 10), 4)
	check("최저 6", JoinRules.startTotal({ 6 }, nil, 10), 0)
end)

local function person(hadInput: boolean, justJoined: boolean): JoinRules.Counted
	return { isBot = false, hadInput = hadInput, justJoined = justJoined }
end
local BOT: JoinRules.Counted = { isBot = true, hadInput = false, justJoined = false }

test("T51 JN-4 JN-5 P 세기", function()
	check("넷 중 하나 입력 없음", JoinRules.countP({ person(true, false), person(true, false), person(true, false), person(false, false) }), 3)
	check("사람 하나와 방금 들어온 사람", JoinRules.countP({ person(true, false), person(false, true) }), 2)
	check("입력 없는 사람과 봇 셋", JoinRules.countP({ person(false, false), BOT, BOT, BOT }), 3)
	check("입력 없는 사람 하나뿐", JoinRules.countP({ person(false, false) }), 1)
end)

test("T52 PL-1 봇 수", function()
	local expected = { [1] = 3, [2] = 2, [3] = 1, [4] = 0, [6] = 0 }
	for humans, bots in expected do
		check(`사람 {humans}`, JoinRules.botCount(humans, Config.BOT_FILL_TO), bots)
	end
end)

test("T53 BT-1 GP-12 VR-1 한계 범위", function()
	local function range(p: number, size: string?): string
		local lo, hi = Config.limitRange(p, size)
		return `{lo}~{hi}`
	end
	check("4명", range(4), "40~68")
	check("3명", range(3), "28~56")
	check("9명", range(9), "80~136")
	check("4명 작은 배", range(4, Types.ShipSize.Small), "24~52")
	check("4명 큰 배", range(4, Types.ShipSize.Large), "56~84")
end)

test("T54 HG-5 RC-1 HG-7 GP-6 HG-8 JN-3 끌어안기의 끝 여섯 가지", function()
	local R = HugRules.Reason
	local expected: { { reason: HugRules.EndReason, crate: string, hugger: string } } = {
		{ reason = R.Completed, crate = "Removed", hugger = "InWater" },
		{ reason = R.Reclaimed, crate = "Stays", hugger = "InWater" },
		{ reason = R.Departed, crate = "Stays", hugger = "Dock" },
		{ reason = R.Sank, crate = "Stays", hugger = "InWater" },
		{ reason = R.OwnerLeft, crate = "Removed", hugger = "Deck" },
		{ reason = R.HuggerLeft, crate = "Stays", hugger = "Left" },
	}
	for _, row in expected do
		local result = HugRules.endResult(row.reason)
		check(`{row.reason} 상자`, result.crate, row.crate)
		check(`{row.reason} 사람`, result.hugger, row.hugger)
	end
end)

-- 예시 플레이 두 판 ----------------------------------------------------------

-- 갑판과 배를 함께 굴리는 작은 판. 놓기마다 띠와 침몰을 적어 둔다
local function newPlay(limit: number)
	local play = {
		boat = BoatRules.newBoat(LO4, HI4, limit),
		deck = {} :: { DeckCrate },
		touchedAt = nil :: number?,
		touchedBy = nil :: string?,
		sinker = nil :: string?,
	}
	local function weight(): number
		local sum = 0
		for _, crate in play.deck do
			sum += crate.score
		end
		return sum
	end
	local function place(owner: string, kind: string)
		table.insert(play.deck, { owner = owner, score = SCORE[kind] })
		local r = BoatRules.placed(play.boat, weight())
		if r.touchedBand then
			play.touchedAt = play.boat.weight
			play.touchedBy = owner
		end
		if r.sank then
			play.sinker = owner
		end
	end
	local function remove(owner: string, kind: string)
		for index, crate in play.deck do
			if crate.owner == owner and crate.score == SCORE[kind] then
				table.remove(play.deck, index)
				break
			end
		end
		BoatRules.removed(play.boat, weight())
	end
	return play, place, remove
end

local FOUR = { "Minji", "Junho", "Doyun", "Seoyeon" }

test("E1 기획 문서 예시 1: 출항", function()
	local play, place, remove = newPlay(61)
	for _ = 1, 2 do
		for _, who in FOUR do
			place(who, Kind.Large)
		end
	end
	check("32", play.boat.weight, 32)
	place("Seoyeon", Kind.Medium)
	place("Minji", Kind.Large)
	place("Junho", Kind.Large)
	place("Doyun", Kind.Large)
	place("Seoyeon", Kind.Medium)
	remove("Minji", Kind.Large)
	place("Junho", Kind.Large)
	place("Minji", Kind.Gold)
	BoatRules.departed(play.boat)

	check("띠에 닿은 무게", play.touchedAt, 42)
	check("띠에 닿게 한 사람", play.touchedBy, "Junho")
	check("침몰", play.sinker, nil)
	check("무게", play.boat.weight, 56)
	check("젖은 자국", play.boat.mark, 56)
	local s = ScoreRules.boatScores(FOUR, play.deck, play.sinker)
	check("민지", s.Minji, 16)
	check("준호", s.Junho, 16)
	check("도윤", s.Doyun, 12)
	check("서연", s.Seoyeon, 12)
	check("앞선 사람", joined(ScoreRules.leaders(s)), "Junho,Minji")
end)

test("E2 기획 문서 예시 2: 침몰", function()
	local play, place, remove = newPlay(51)
	local totals: { [string]: number } = { Minji = 41, Junho = 36, Doyun = 33, Seoyeon = 14 }
	for _, who in { "Minji", "Junho", "Doyun" } do
		place(who, Kind.Large)
	end
	check("12", play.boat.weight, 12)
	remove("Minji", Kind.Large)
	check("8", play.boat.weight, 8)
	for _, who in { "Minji", "Junho", "Doyun" } do
		place(who, Kind.Large)
	end
	place("Junho", Kind.Large)
	place("Doyun", Kind.Large)
	place("Minji", Kind.Medium)
	check("30", play.boat.weight, 30)
	place("Junho", Kind.Large)
	place("Doyun", Kind.Large)
	place("Minji", Kind.Large)
	place("Junho", Kind.Large)
	place("Doyun", Kind.Large)
	check("50에서 버팀", play.sinker, nil)
	place("Seoyeon", Kind.Gold)

	check("띠에 닿은 무게", play.touchedAt, 42)
	check("띠에 닿게 한 사람", play.touchedBy, "Minji")
	check("가라앉힌 사람", play.sinker, "Seoyeon")
	local s = ScoreRules.boatScores(FOUR, play.deck, play.sinker)
	check("민지", s.Minji, 10)
	check("준호", s.Junho, 20)
	check("도윤", s.Doyun, 20)
	check("서연", s.Seoyeon, 0)
	for who, total in totals do
		totals[who] = ScoreRules.addToTotal(total, s[who], 1)
	end
	check("총점 준호", totals.Junho, 56)
	check("총점 도윤", totals.Doyun, 53)
	check("총점 민지", totals.Minji, 51)
	check("총점 서연", totals.Seoyeon, 14)
	check("순위", rankText(ScoreRules.ranking(totals, s)), "Junho=1 Doyun=2 Minji=3 Seoyeon=4")
end)

-- 돌리기 --------------------------------------------------------------------

local Tests = {}

-- 모두 돌린다. 하나라도 실패하면 실패한 번호를 모두 찍고 오류로 멈춘다
function Tests.run(): (number, number)
	local failures = {}
	local ruleCount, exampleCount = 0, 0
	for _, t in tests do
		local message = ""
		local ok = xpcall(t.run, function(err)
			message = tostring(err)
		end)
		if not ok then
			table.insert(failures, `[{t.id}] {message}`)
		end
		if string.sub(t.id, 1, 1) == "E" then
			exampleCount += 1
		else
			ruleCount += 1
		end
	end
	if #failures > 0 then
		error(`규칙 시험 실패 {#failures}개:\n` .. table.concat(failures, "\n"), 0)
	end
	return ruleCount, exampleCount
end

return Tests
