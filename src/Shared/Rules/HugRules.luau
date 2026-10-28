--!strict
-- 끌어안기가 끝나는 여섯 가지 길마다 상자와 끌어안던 사람이 어떻게 되는지.
-- docs/S20-hug-edge-cases.md의 표와 같다. 표를 바꾸려면 이 모듈과 시험(T54)을 함께 고친다.

export type EndReason = "Completed" | "Reclaimed" | "Departed" | "Sank" | "OwnerLeft" | "HuggerLeft"
export type CrateFate = "Removed" | "Stays"
export type HuggerFate = "InWater" | "Dock" | "Deck" | "Left"
export type EndResult = { crate: CrateFate, hugger: HuggerFate }

local HugRules = {}

HugRules.Reason = table.freeze({
	Completed = "Completed" :: EndReason, -- 끌어안기 시간이 참(HG-5)
	Reclaimed = "Reclaimed" :: EndReason, -- 주인이 되찾음(RC-1)
	Departed = "Departed" :: EndReason, -- 셋째 종, 출항(HG-7, GP-6)
	Sank = "Sank" :: EndReason, -- 침몰(HG-7)
	OwnerLeft = "OwnerLeft" :: EndReason, -- 주인이 나감(HG-8, JN-2)
	HuggerLeft = "HuggerLeft" :: EndReason, -- 끌어안던 사람이 나감(JN-3)
})

local RESULTS: { [EndReason]: EndResult } = {
	Completed = { crate = "Removed", hugger = "InWater" },
	Reclaimed = { crate = "Stays", hugger = "InWater" },
	Departed = { crate = "Stays", hugger = "Dock" },
	Sank = { crate = "Stays", hugger = "InWater" },
	OwnerLeft = { crate = "Removed", hugger = "Deck" },
	HuggerLeft = { crate = "Stays", hugger = "Left" },
}

function HugRules.endResult(reason: EndReason): EndResult
	local result = RESULTS[reason]
	return { crate = result.crate, hugger = result.hugger }
end

return HugRules
