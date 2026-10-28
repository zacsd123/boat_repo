# S02. 수치 설정 모듈

- **묶음**: 준비
- **앞 단계**: S01
- **크기(어림)**: 작음
- **끝나면**: 수치 파일의 모든 키가 Config 한 곳에 있고, 서버와 클라이언트가 같은 값을 읽는다. Studio에서는 시험용 값으로 한계와 종 간격을 고정할 수 있다.

## 지킬 규칙

<!--RULES: BT-1 CR-1 CR-3 GD-2 GP-12-->

| 번호 | 규칙 |
| --- | --- |
| BT-1 | 숨은 한계는 인원별 한계 범위 안의 정수 하나다. 라운드마다 고르게 무작위로 뽑고 누구에게도 보여 주지 않는다. |
| CR-1 | 해변에 작은 상자(1), 중간 상자(2), 큰 상자(4) 더미가 하나씩 있고 마르지 않는다. 점수와 무게는 같은 숫자다. |
| CR-3 | 해변의 더미에서 갑판까지 걷는 시간은 빈손, 작은 상자, 중간 상자가 3초이고 큰 상자가 4.5초다. |
| GD-2 | 황금 상자를 들면 큰 상자를 들었을 때와 같은 속도로 걷는다. 해변에서 갑판까지 4.5초다. |
| GP-12 | P가 4보다 작을 때는 한계 범위 표의 1\~3명 값을 쓴다. 그런 때는 둘이다. 봇을 만들기 전에 적은 인원으로 시험할 때, 그리고 가만히 있는 사람을 P에서 뺀 라운드. 띠의 폭은 4명과 같게 두고 아래 끝을 세 번째 왕복의 첫 상자에 맞춘다. 3명은 28\~56이다. 4명의 값을 인원에 비례시킨 30\~51로는 종이 울린 뒤 하나 더 실을 이유가 없어진다. |

<!--/RULES-->

이 단계는 규칙을 움직이게 하지는 않는다. 규칙이 쓰는 숫자를 한 곳에 놓는다.

## 쓰는 수치

`02-config.md`의 모든 키. 이 단계에서 특히 확인하는 것은 아래다.

<!--CONFIG: LIMIT_RANGE CRATE_SCORE CARRY_TIME PILE_TO_DECK WALK_SPEED DEBUG_FORCE_LIMIT DEBUG_FORCE_BELL_GAPS DEBUG_FORCE_P DEBUG_PRINT_LIMIT DEBUG_RUN_TESTS-->

| 키 | 값 | 뜻 |
| --- | --- | --- |
| `LIMIT_RANGE` | 인원별 표. 4명은 40\~68, 3명은 28\~56 | 인원(P)별 숨은 한계의 범위. 공식이 아니라 인원마다 따로 둔 값이고, 전체 표는 수치 파일에 있다 |
| `CRATE_SCORE` | 작은 1, 중간 2, 큰 4, 황금 8 | 상자의 점수이자 무게 |
| `CARRY_TIME` | 빈손·작은·중간 3, 큰 4.5, 황금 4.5 | 더미에서 갑판까지 걷는 시간(초). 나르는 속도는 PILE_TO_DECK ÷ CARRY_TIME으로 계산한다 |
| `PILE_TO_DECK` | 48 | 더미 자리에서 갑판 입구까지 걷는 거리(스터드). 빈손 3초 거리다 |
| `WALK_SPEED` | 16 | 빈손으로 걷는 속도(스터드/초). Roblox 기본값이다 |
| `DEBUG_FORCE_LIMIT` | 없음 | 숨은 한계를 정한 값으로 고정한다 |
| `DEBUG_FORCE_BELL_GAPS` | 없음 | 종 간격 둘을 정한 값으로 고정한다 |
| `DEBUG_FORCE_P` | 없음 | P를 정한 값으로 고정한다 |
| `DEBUG_PRINT_LIMIT` | 끔 | 라운드마다 뽑힌 한계를 서버 출력에 찍는다 |
| `DEBUG_RUN_TESTS` | 켬 | 서버가 켜질 때 규칙 시험(S03)을 돌린다 |

<!--/CONFIG-->

## 만들 것

1. **`Shared/Config`.** `02-config.md`의 키를 이름 그대로 옮긴다. 값이 하나인 키는 숫자 하나, 값이 여럿인 키는 안쪽 표다. 모양은 아래 "Config의 모양"을 따른다. 다 채운 뒤 `table.freeze`로 얼려서 실행 중에 바뀌지 않게 한다. `table.freeze`는 겉의 표만 얼리므로 안쪽 표도 하나씩 얼린다.
2. **계산 함수 셋.** 숫자를 두 번 적지 않으려고 계산으로 얻는다.
   - `Config.limitRange(P, shipSize)`: `LIMIT_RANGE` 표에서 아래 끝과 위 끝을 돌려준다. P가 8보다 크면 8의 값, 1보다 작으면 1의 값. `shipSize`는 S28 전까지 보통 배만 받는다.
   - `Config.carrySpeed(kind)`: `PILE_TO_DECK ÷ CARRY_TIME[kind]`. 빈손의 값은 `WALK_SPEED`와 같아야 한다(스스로 검사에 넣는다).
   - `Config.settleTime()`: 정산 세 부분의 합.
3. **스스로 검사.** 서버가 켜질 때 한 번 돌고, 하나라도 어긋나면 오류로 멈춘다.
   - 모든 인원의 범위가 정수이고 아래 끝이 위 끝보다 작다.
   - 정산 세 부분의 합이 12, 최종 결과 세 부분의 합이 20이다.
   - `BELL_GAP_MIN`이 `BELL_GAP_MAX`보다 크지 않다.
   - 큰 상자와 황금 상자의 `CARRY_TIME`이 같다(GD-2).
   - `PILE_TO_DECK` ÷ 빈손의 `CARRY_TIME`이 `WALK_SPEED`와 같다.
4. **`Shared/Types`.** 문자열을 여기저기 직접 쓰지 않도록 이름을 모은다: 상자 종류 넷, 라운드 단계, 참가자 상태 넷(`03-architecture.md`의 표와 같은 이름).
5. **`Server/DevTools`.** `RunService:IsStudio()`가 참일 때만 동작하는 시험 도구의 틀을 만든다. 이 단계에서는 값 다섯을 담는 자리만 만든다(한계 고정, 종 간격 고정, P 고정, 한계 찍기, 시험 돌리기). 쓰는 것은 S03, S06, S09, S10에서다.

## Config의 모양

값이 여럿인 키를 어떤 꼴로 적는지 보이려는 것이다. 여기 적힌 숫자는 예시이고, 실제 값은 `02-config.md`에서 옮긴다. 상자 종류와 배 크기의 이름은 `03-architecture.md`의 "그 밖의 이름"과 같다.

```lua
--!strict

-- 이름으로 찾는 표는 타입을 적어 둔다
local CRATE_SCORE: { [string]: number } = { Small = 1, Medium = 2, Large = 4, Gold = 8 }
local CARRY_TIME: { [string]: number } = { Empty = 3, Small = 3, Medium = 3, Large = 4.5, Gold = 4.5 }
local FIRST_BELL_CAP: { [string]: number } = { Small = 30, Normal = 40, Large = 50 }
local SHIP_SIZE_MIX: { [string]: number } = { Small = 2, Normal = 4, Large = 2 }

-- 인원별 표. 1부터 8까지 여덟 줄이고, 공식으로 바꾸지 않는다
local LIMIT_RANGE: { [number]: { lo: number, hi: number } } = {
	[3] = { lo = 28, hi = 56 },
	[4] = { lo = 40, hi = 68 },
}

local Config = {
	-- 값이 하나인 키는 모두 이 꼴이다
	BOATS_PER_MATCH = 8,
	PILE_TO_DECK = 48,
	SHIP_SIZE_SHIFT = 4,

	LIMIT_RANGE = LIMIT_RANGE,
	CRATE_SCORE = CRATE_SCORE,
	CARRY_TIME = CARRY_TIME,
	FIRST_BELL_CAP = FIRST_BELL_CAP,
	SHIP_SIZE_MIX = SHIP_SIZE_MIX,
	CARGO_GRID = { columns = 6, rows = 3, cellSize = 3 },
}

-- 한계 범위의 아래 끝과 위 끝. 배 크기는 S28부터 넘긴다
function Config.limitRange(p: number, shipSize: string?): (number, number)
	local row = Config.LIMIT_RANGE[math.clamp(p, 1, 8)]
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
```

## 하지 않는 것

- 숨은 한계, 뽑힌 종 간격처럼 숨겨야 하는 값은 Config에 두지 않는다. Config는 클라이언트도 읽는다.
- 시험용 값을 Config에 넣지 않는다. DevTools는 서버에만 있다.

## 완료 확인

- [ ] 서버를 켜면 출력에 인원별 한계 범위 8줄과 나르는 속도가 찍힌다. 빈손, 작은 상자, 중간 상자는 16이고 큰 상자와 황금 상자는 10.67이다.
- [ ] `Config.limitRange(4)`가 40과 68을, `Config.limitRange(3)`이 28과 56을 돌려준다.
- [ ] `LIMIT_RANGE`의 4명 값을 일부러 뒤집어(68, 40) 넣으면 서버가 오류로 멈춘다. 되돌린다.
- [ ] 클라이언트 스크립트에서 `Config.HOLD_TIME`을 읽으면 0.5가 나온다.
- [ ] 클라이언트의 탐색기에서 `DevTools`가 보이지 않는다(ServerScriptService는 복제되지 않는다).
- [ ] DevTools의 모든 함수 첫 줄에 Studio가 아니면 돌아가는 분기가 있다.

## 주의할 곳

- 이 뒤의 모든 단계에서 지키는 약속: 코드에 숫자를 직접 쓰지 않는다. 숫자가 필요하면 먼저 `02-config.md`에 키를 더하고 Config에 옮긴 뒤 쓴다. 단계를 끝낼 때마다 스크립트에서 숫자를 검색해 본다(0과 1, 좌표 계산의 2 같은 것은 빼고).
- 한계 범위를 공식으로 바꾸고 싶어져도 표로 둔다. 인원마다 따로 맞추기로 한 값이다.
