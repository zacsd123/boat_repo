--!strict
-- 배의 무게, 젖은 자국, 띠에 닿음, 침몰. 판정은 놓일 때만 한다(BT-6).
-- 숨은 한계는 서버가 만든 배 값 안에만 있고, 그 값은 서버 밖으로 나가지 않는다.

export type Boat = {
	lo: number, -- 한계 범위의 아래 끝(빨간 띠 아래 끝)
	hi: number, -- 한계 범위의 위 끝
	limit: number, -- 숨은 한계
	weight: number, -- 갑판에 놓인 상자 무게의 합(BT-2)
	mark: number, -- 이번 라운드의 최고 무게, 젖은 자국(BT-5)
	touched: boolean, -- 이번 라운드에 띠에 닿은 적이 있는지
	ended: boolean, -- 침몰했거나 떠났는지
}

export type PlaceResult = {
	ignored: boolean, -- 끝난 배라서 없던 일(BT-7, BL-4)
	touchedBand: boolean, -- 이번 놓기로 처음 띠에 닿음(BL-1)
	sank: boolean, -- 이번 놓기로 침몰(BT-6)
}

local BoatRules = {}

function BoatRules.newBoat(lo: number, hi: number, limit: number): Boat
	return {
		lo = lo,
		hi = hi,
		limit = limit,
		weight = 0,
		mark = 0,
		touched = false,
		ended = false,
	}
end

-- 상자가 놓였다. deckWeight는 놓은 뒤 갑판 무게의 합
function BoatRules.placed(boat: Boat, deckWeight: number): PlaceResult
	if boat.ended then
		return { ignored = true, touchedBand = false, sank = false }
	end

	boat.weight = deckWeight
	boat.mark = math.max(boat.mark, deckWeight)

	-- 띠에 닿음을 침몰보다 먼저 본다. 같은 상자에서 둘이 함께 날 수 있다(BL-5)
	local touchedBand = false
	if not boat.touched and deckWeight >= boat.lo then
		boat.touched = true
		touchedBand = true
	end

	-- 한계와 같으면 버틴다
	local sank = deckWeight > boat.limit
	if sank then
		boat.ended = true -- 침몰하면 라운드는 그 순간 끝난다(BT-8)
	end

	return { ignored = false, touchedBand = touchedBand, sank = sank }
end

-- 상자가 빠졌다. 무게만 고친다. 젖은 자국은 그대로이고 판정은 하지 않는다
function BoatRules.removed(boat: Boat, deckWeight: number)
	boat.weight = deckWeight
end

-- 셋째 종에 떠났다
function BoatRules.departed(boat: Boat)
	boat.ended = true
end

return BoatRules
