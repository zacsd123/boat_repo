--!strict
-- 종 세 번의 시각. 종은 무게를 모른다. 그래서 무게가 줄어도 멈추지 않는다(BL-3).
-- 시각은 모두 라운드가 시작된 뒤 지난 초다.

export type Bells = {
	cap: number, -- 띠에 닿지 않아도 첫 종이 울리는 시각
	gap1: number, -- 첫 종과 둘째 종 사이
	gap2: number, -- 둘째 종과 셋째 종 사이
	count: number, -- 울린 종의 수
	firstAt: number?,
	secondAt: number?,
	thirdAt: number?,
}

local BellRules = {}

-- 간격 둘을 따로 뽑는다. random은 0 이상 1 미만의 수를 돌려주는 함수다
function BellRules.drawGaps(min: number, max: number, random: () -> number): (number, number)
	local gap1 = min + (max - min) * random()
	local gap2 = min + (max - min) * random()
	return gap1, gap2
end

-- 라운드가 시작될 때 만든다. 간격은 이때 넣어 둔다
function BellRules.newBells(cap: number, gap1: number, gap2: number): Bells
	return {
		cap = cap,
		gap1 = gap1,
		gap2 = gap2,
		count = 0,
		firstAt = nil,
		secondAt = nil,
		thirdAt = nil,
	}
end

-- 첫 종을 청한다. 아직 안 울렸으면 울리고 참을 돌려준다. 이미 울렸으면 아무 일도 없다
function BellRules.firstBell(bells: Bells, elapsed: number): boolean
	if bells.count > 0 then
		return false
	end
	bells.count = 1
	bells.firstAt = elapsed
	bells.secondAt = elapsed + bells.gap1
	bells.thirdAt = elapsed + bells.gap1 + bells.gap2
	return true
end

-- 시간이 흘렀다. 이번에 울린 종의 번호들을 돌려준다. 3이 있으면 출항이다
function BellRules.tick(bells: Bells, elapsed: number): { number }
	local rung = {}

	if bells.count == 0 and elapsed >= bells.cap then
		BellRules.firstBell(bells, bells.cap)
		table.insert(rung, bells.count)
	end

	local secondAt = bells.secondAt
	if bells.count == 1 and secondAt ~= nil and elapsed >= secondAt then
		bells.count += 1
		table.insert(rung, bells.count)
	end

	local thirdAt = bells.thirdAt
	if bells.count == 2 and thirdAt ~= nil and elapsed >= thirdAt then
		bells.count += 1
		table.insert(rung, bells.count)
	end

	return rung
end

return BellRules
