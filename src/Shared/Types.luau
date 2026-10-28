--!strict
-- 여기저기 직접 쓰지 않도록 이름을 모은다. 속성 값과 Config의 표에서 같은 낱말을 쓴다.
-- docs/03-architecture.md의 "라운드 단계", "참가자 상태", "그 밖의 이름"과 같다.

export type CrateKind = "Small" | "Medium" | "Large" | "Gold"
export type ShipSize = "Small" | "Normal" | "Large"
export type Phase =
	"MatchIntro"
	| "Loading"
	| "Departing"
	| "Sinking"
	| "Scoring"
	| "Arriving"
	| "FinalShow"
	| "FinalLastScore"
	| "FinalPodium"
export type ParticipantState = "Empty" | "Carrying" | "Hugging" | "InWater"

local Types = {
	-- 상자 종류 넷. 속성 Kind와 Carrying, Config의 CRATE_SCORE와 CARRY_TIME
	CrateKind = {
		Small = "Small" :: CrateKind,
		Medium = "Medium" :: CrateKind,
		Large = "Large" :: CrateKind,
		Gold = "Gold" :: CrateKind,
	},
	-- 배 크기. 속성 ShipSize, Config의 FIRST_BELL_CAP과 SHIP_SIZE_MIX
	ShipSize = {
		Small = "Small" :: ShipSize,
		Normal = "Normal" :: ShipSize,
		Large = "Large" :: ShipSize,
	},
	-- 라운드 단계. 속성 Phase
	Phase = {
		MatchIntro = "MatchIntro" :: Phase,
		Loading = "Loading" :: Phase,
		Departing = "Departing" :: Phase,
		Sinking = "Sinking" :: Phase,
		Scoring = "Scoring" :: Phase,
		Arriving = "Arriving" :: Phase,
		FinalShow = "FinalShow" :: Phase,
		FinalLastScore = "FinalLastScore" :: Phase,
		FinalPodium = "FinalPodium" :: Phase,
	},
	-- 참가자 상태 넷. 속성 State. 빈손의 걷는 시간(CARRY_TIME.Empty)도 같은 낱말을 쓴다
	ParticipantState = {
		Empty = "Empty" :: ParticipantState,
		Carrying = "Carrying" :: ParticipantState,
		Hugging = "Hugging" :: ParticipantState,
		InWater = "InWater" :: ParticipantState,
	},
}

table.freeze(Types.CrateKind)
table.freeze(Types.ShipSize)
table.freeze(Types.Phase)
table.freeze(Types.ParticipantState)
table.freeze(Types)
return Types
