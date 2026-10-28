--!strict
-- P, 봇의 수, 도중 참가자의 시작 총점.

export type Counted = {
	isBot: boolean,
	hadInput: boolean, -- 지난 라운드에 입력이 있었는지(JN-4)
	justJoined: boolean, -- 지난 라운드가 끝난 뒤 들어왔는지
}

local JoinRules = {}

-- P는 라운드 시작 순간의 참가자 수. 한 라운드 내내 입력이 없던 사람은 뺀다. 0이면 1(JN-4, JN-5)
function JoinRules.countP(participants: { Counted }): number
	local p = 0
	for _, c in participants do
		if c.isBot or c.hadInput or c.justJoined then
			p += 1
		end
	end
	return math.max(p, 1)
end

-- 채우는 인원에서 사람 수를 뺀 값. 0보다 작으면 0(PL-1)
function JoinRules.botCount(humans: number, fillTo: number): number
	return math.max(fillTo - humans, 0)
end

-- 도중 참가자의 시작 총점(JN-1, GP-20)
-- totals: 지금 있는 참가자(봇 포함)의 총점들. previousTotal: 같은 판에 다시 들어왔다면 나가기 전 총점
function JoinRules.startTotal(totals: { number }, previousTotal: number?, offset: number): number
	local lowest: number? = nil
	for _, total in totals do
		if lowest == nil or total < lowest then
			lowest = total
		end
	end
	local start = math.max((lowest or 0) - offset, 0)
	if previousTotal ~= nil then
		start = math.min(start, previousTotal)
	end
	return start
end

return JoinRules
