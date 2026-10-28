--!strict
-- 배 점수, 총점, 앞선 사람, 순위. 참가자는 문자열 id로 가리킨다.

export type DeckCrate = {
	owner: string, -- 주인 참가자 id
	score: number, -- 상자 점수(CRATE_SCORE)
	huggedBy: string?, -- 끌어안던 사람. 배가 끝나면 무효라서 점수에는 상관없다(HG-7)
}

export type Rank = { id: string, rank: number }

local ScoreRules = {}

-- 배가 끝나는 순간 갑판에 놓인 내 상자 점수의 합. 가라앉힌 참가자는 0(SC-1, SC-2)
function ScoreRules.boatScores(participants: { string }, deck: { DeckCrate }, sinker: string?): { [string]: number }
	local scores: { [string]: number } = {}
	for _, id in participants do
		scores[id] = 0
	end
	for _, crate in deck do
		if scores[crate.owner] ~= nil then
			scores[crate.owner] += crate.score
		end
	end
	if sinker ~= nil and scores[sinker] ~= nil then
		scores[sinker] = 0
	end
	return scores
end

-- 배 점수에 배율을 곱해 총점에 더한다. 이미 쌓인 총점은 줄지 않는다(SC-3, SC-4)
function ScoreRules.addToTotal(total: number, boatScore: number, multiplier: number): number
	return total + math.max(0, boatScore * multiplier)
end

-- 가장 높은 점수의 참가자들. 가장 높은 점수가 0이면 아무도 없다(SC-6, SC-7, GP-16)
function ScoreRules.leaders(scores: { [string]: number }): { string }
	local best = 0
	for _, score in scores do
		best = math.max(best, score)
	end
	local result = {}
	if best <= 0 then
		return result
	end
	for id, score in scores do
		if score == best then
			table.insert(result, id)
		end
	end
	table.sort(result)
	return result
end

-- 총점 순. 같으면 마지막 배 점수가 높은 쪽. 그래도 같으면 공동 순위(SC-5)
function ScoreRules.ranking(totals: { [string]: number }, lastBoat: { [string]: number }): { Rank }
	local ids = {}
	for id in totals do
		table.insert(ids, id)
	end

	local function last(id: string): number
		return lastBoat[id] or 0
	end

	table.sort(ids, function(a, b)
		if totals[a] ~= totals[b] then
			return totals[a] > totals[b]
		end
		if last(a) ~= last(b) then
			return last(a) > last(b)
		end
		return a < b
	end)

	local result: { Rank } = {}
	for index, id in ids do
		local rank = index
		local previous = result[index - 1]
		if previous ~= nil then
			local prevId = previous.id
			if totals[prevId] == totals[id] and last(prevId) == last(id) then
				rank = previous.rank
			end
		end
		table.insert(result, { id = id, rank = rank })
	end
	return result
end

return ScoreRules
