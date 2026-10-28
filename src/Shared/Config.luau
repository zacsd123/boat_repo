--!strict
-- 수치 전부. 키 이름과 값은 docs/02-config.md를 그대로 옮긴다.
-- 숨은 값과 시험용 값은 여기 두지 않는다. 클라이언트도 이 모듈을 읽는다.

-- 이름으로 찾는 표는 타입을 적어 둔다
local FIRST_BELL_CAP: { [string]: number } = { Small = 30, Normal = 40, Large = 50 }
local CRATE_SCORE: { [string]: number } = { Small = 1, Medium = 2, Large = 4, Gold = 8 }
local CARRY_TIME: { [string]: number } = { Empty = 3, Small = 3, Medium = 3, Large = 4.5, Gold = 4.5 }
local SHIP_SIZE_MIX: { [string]: number } = { Small = 2, Normal = 4, Large = 2 }

-- 인원별 표. 1부터 8까지 여덟 줄이고, 공식으로 바꾸지 않는다
local LIMIT_RANGE: { [number]: { lo: number, hi: number } } = {
	[1] = { lo = 12, hi = 40 },
	[2] = { lo = 20, hi = 48 },
	[3] = { lo = 28, hi = 56 },
	[4] = { lo = 40, hi = 68 },
	[5] = { lo = 50, hi = 85 },
	[6] = { lo = 60, hi = 102 },
	[7] = { lo = 70, hi = 119 },
	[8] = { lo = 80, hi = 136 },
}

-- 슬롯 1~8의 색. 디자인을 정하기 전의 임시값이다
local PARTICIPANT_COLORS: { Color3 } = {
	Color3.fromRGB(230, 57, 70), -- 빨강
	Color3.fromRGB(29, 113, 230), -- 파랑
	Color3.fromRGB(245, 200, 30), -- 노랑
	Color3.fromRGB(46, 170, 80), -- 초록
	Color3.fromRGB(245, 130, 30), -- 주황
	Color3.fromRGB(140, 70, 200), -- 보라
	Color3.fromRGB(240, 110, 180), -- 분홍
	Color3.fromRGB(60, 200, 220), -- 하늘색
}

local Config = {
	-- 판과 시간
	BOATS_PER_MATCH = 8,
	MATCH_START_TIME = 5,
	SETTLE_SHOW_TIME = 3,
	SETTLE_SCORE_TIME = 5,
	SETTLE_ARRIVE_TIME = 4,
	FINAL_SHOW_TIME = 3,
	FINAL_LAST_SCORE_TIME = 5,
	FINAL_PODIUM_TIME = 12,
	LAST_BOAT_MULTIPLIER = 2,

	-- 종
	FIRST_BELL_CAP = FIRST_BELL_CAP,
	BELL_GAP_MIN = 3,
	BELL_GAP_MAX = 7,

	-- 한계 범위
	LIMIT_RANGE = LIMIT_RANGE,

	-- 상자와 걷기
	CRATE_SCORE = CRATE_SCORE,
	WALK_SPEED = 16,
	PILE_TO_DECK = 48,
	CARRY_TIME = CARRY_TIME,
	WALK_TIME_TOLERANCE = 0.8,
	DECK_LENGTH = 24,
	HULL_FREEBOARD = 6,
	BOAT_MOVE_TIME = 0.3,
	CARGO_GRID = { columns = 6, rows = 3, cellSize = 3 },

	-- 버튼, 끌어안기, 물
	HOLD_TIME = 0.5,
	HOLD_TOLERANCE = 0.1,
	INPUT_MIN_INTERVAL = 0.1,
	TARGET_RANGE = 6,
	HUG_TIME = 3,
	HUG_ENABLED = true,
	RECLAIM_RANGE = 8,
	RECLAIM_COOLDOWN = 1,
	WATER_EXIT_TIME = 4.5,
	WATER_SPEED = 9,
	LADDER_CLIMB_TIME = 2.5,

	-- 인원과 봇
	SERVER_MAX_PLAYERS = 8,
	BOT_FILL_TO = 4,
	SABOTEUR_REST = 10,
	BOT_REACTION_TIME = 0.5,
	BOT_STUCK_TIME = 5,
	PARTICIPANT_COLORS = PARTICIPANT_COLORS,
	JOIN_SCORE_OFFSET = 0,
	IDLE_MOVE_THRESHOLD = 2,

	-- 배 크기 변주 (S28부터)
	SHIP_SIZE_SHIFT = 4,
	SHIP_SIZE_MIX = SHIP_SIZE_MIX,
}

-- 한계 범위의 아래 끝과 위 끝. P는 표의 양 끝으로 자른다. 배 크기는 S28부터 넘긴다
function Config.limitRange(p: number, shipSize: string?): (number, number)
	local row = Config.LIMIT_RANGE[math.clamp(p, 1, #Config.LIMIT_RANGE)]
	local shift = 0
	if shipSize == "Small" then
		shift = -Config.SHIP_SIZE_SHIFT * p
	elseif shipSize == "Large" then
		shift = Config.SHIP_SIZE_SHIFT * p
	end
	return row.lo + shift, row.hi + shift
end

-- 그 상자를 들었을 때의 걷는 속도. 빈손은 "Empty"
function Config.carrySpeed(kind: string): number
	return Config.PILE_TO_DECK / Config.CARRY_TIME[kind]
end

-- 정산 세 부분의 합
function Config.settleTime(): number
	return Config.SETTLE_SHOW_TIME + Config.SETTLE_SCORE_TIME + Config.SETTLE_ARRIVE_TIME
end

-- 스스로 검사. 서버가 켜질 때 한 번 부른다. 어긋나면 오류로 멈춘다
function Config.validate()
	local problems = {}

	for p = 1, Config.SERVER_MAX_PLAYERS do
		local row = Config.LIMIT_RANGE[p]
		if row == nil then
			table.insert(problems, `LIMIT_RANGE[{p}]가 없다`)
		elseif row.lo ~= math.floor(row.lo) or row.hi ~= math.floor(row.hi) then
			table.insert(problems, `LIMIT_RANGE[{p}]가 정수가 아니다: {row.lo}~{row.hi}`)
		elseif row.lo >= row.hi then
			table.insert(problems, `LIMIT_RANGE[{p}]의 아래 끝이 위 끝보다 작지 않다: {row.lo}~{row.hi}`)
		end
	end

	if Config.settleTime() ~= 12 then
		table.insert(problems, `정산 세 부분의 합이 12가 아니다: {Config.settleTime()}`)
	end
	local finalTime = Config.FINAL_SHOW_TIME + Config.FINAL_LAST_SCORE_TIME + Config.FINAL_PODIUM_TIME
	if finalTime ~= 20 then
		table.insert(problems, `최종 결과 세 부분의 합이 20이 아니다: {finalTime}`)
	end

	if Config.BELL_GAP_MIN > Config.BELL_GAP_MAX then
		table.insert(problems, `BELL_GAP_MIN이 BELL_GAP_MAX보다 크다: {Config.BELL_GAP_MIN} > {Config.BELL_GAP_MAX}`)
	end

	if Config.CARRY_TIME.Large ~= Config.CARRY_TIME.Gold then
		table.insert(problems, `큰 상자와 황금 상자의 CARRY_TIME이 다르다(GD-2): {Config.CARRY_TIME.Large}, {Config.CARRY_TIME.Gold}`)
	end

	if Config.carrySpeed("Empty") ~= Config.WALK_SPEED then
		table.insert(problems, `PILE_TO_DECK ÷ 빈손 CARRY_TIME이 WALK_SPEED와 다르다: {Config.carrySpeed("Empty")}, {Config.WALK_SPEED}`)
	end

	if #problems > 0 then
		error("Config 검사 실패:\n" .. table.concat(problems, "\n"), 0)
	end
end

-- 안쪽 표까지 얼린다
local function deepFreeze(t: any)
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			deepFreeze(value)
		end
	end
	table.freeze(t)
end

deepFreeze(Config)
return Config
