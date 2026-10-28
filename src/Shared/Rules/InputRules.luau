--!strict
-- 톡 누르기와 꾹 누르기가 무엇이 되는가, 되찾을 수 있는가.
-- 서버와 클라이언트가 같은 함수를 쓴다. 순서는 docs/03-architecture.md의 "톡 누르기를 처리하는 순서"다.

local Types = require(script.Parent.Parent.Types)

-- 서버(또는 클라이언트)가 그 순간에 본 것
export type Situation = {
	phase: string, -- 라운드 단계
	state: string, -- 참가자 상태
	onDeck: boolean, -- 갑판 구역 안인지
	carrying: string?, -- 든 상자의 종류
	pickupInReach: boolean, -- 들 더미나 황금 상자가 손 닿는 곳에 있는지
	reclaimable: boolean, -- 되찾을 상자(끌어안긴 내 상자)가 손 닿는 곳에 있는지
}

-- 누르려는 실린 상자
export type Target = {
	mine: boolean, -- 내 상자인지
	huggedBy: string?, -- 누가 끌어안고 있는지
	covered: boolean, -- 위에 다른 상자가 쌓였는지(GP-4)
}

-- 꾹 누르기에 쓰는 값. 부르는 쪽이 Config에서 읽어 넘긴다
export type HoldSettings = {
	holdTime: number, -- HOLD_TIME
	holdTolerance: number, -- HOLD_TOLERANCE
	hugEnabled: boolean, -- HUG_ENABLED
}

export type TapAction = "Place" | "Discard" | "DropGold" | "Pickup" | "Reclaim" | "Hint" | "None"
export type HoldAction = "Hug" | "Repick" | "None"
export type PressKind = "Tap" | "Hold"

local InputRules = {}

-- 톡 누르기
function InputRules.tap(s: Situation): TapAction
	-- 버튼은 싣는 동안에만 켜져 있다(FL-4)
	if s.phase ~= Types.Phase.Loading then
		return "None"
	end
	-- 물에서, 끌어안는 중에는 아무것도 못 한다(WT-2, HG-3)
	if s.state == Types.ParticipantState.InWater or s.state == Types.ParticipantState.Hugging then
		return "None"
	end
	-- 손에 상자가 있으면 놓기다(IN-2)
	if s.state == Types.ParticipantState.Carrying then
		if s.onDeck then
			return "Place"
		elseif s.carrying == Types.CrateKind.Gold then
			return "DropGold" -- 그 자리에 남는다(GD-3)
		else
			return "Discard" -- 사라진다(CR-6)
		end
	end
	-- 빈손으로 갑판 위면 되찾기, 되찾을 것이 없으면 힌트만(IN-4)
	if s.onDeck then
		if s.reclaimable then
			return "Reclaim"
		end
		return "Hint"
	end
	-- 빈손으로 갑판 밖이면 들기(IN-3)
	if s.pickupInReach then
		return "Pickup"
	end
	return "None"
end

-- 꾹 누르기가 끝났다. heldTime은 누르기 시작과 끝 사이(GP-9)
function InputRules.hold(s: Situation, target: Target?, heldTime: number, settings: HoldSettings): HoldAction
	if s.phase ~= Types.Phase.Loading then
		return "None"
	end
	-- 빈손일 때만. 든 채로, 물에서, 끌어안는 중에는 없음(CR-7, WT-2, HG-3)
	if s.state ~= Types.ParticipantState.Empty or not s.onDeck then
		return "None"
	end
	if target == nil then
		return "None"
	end
	-- 이미 끌어안긴 상자는 남도 주인도 못 건드린다(HG-2, GP-7)
	if target.huggedBy ~= nil then
		return "None"
	end
	-- 위에 상자가 쌓인 아래 상자는 대상이 아니다(GP-4)
	if target.covered then
		return "None"
	end
	-- 서버는 정해진 시간보다 봐주는 오차 넘게 짧은지만 본다(GP-9)
	if heldTime < settings.holdTime - settings.holdTolerance then
		return "None"
	end
	if target.mine then
		return "Repick" -- CR-8
	end
	if settings.hugEnabled then
		return "Hug" -- IN-5, HG-1
	end
	return "None"
end

-- 누르는 순간. 꾹 누르기를 시작할지, 바로 톡 누르기로 보낼지
function InputRules.pressStart(s: Situation, target: Target?): PressKind
	-- 되찾을 상자가 손 닿는 곳에 있으면 누르는 순간 되찾기다(GP-19)
	if s.reclaimable then
		return "Tap"
	end
	-- 손에 상자가 있으면 톡은 놓기다(IN-2)
	if s.state ~= Types.ParticipantState.Empty then
		return "Tap"
	end
	if target ~= nil then
		return "Hold"
	end
	return "Tap"
end

-- 되찾을 수 있나(RC-1, RC-3, RC-4)
function InputRules.canReclaim(
	ownerState: string,
	onDeck: boolean,
	distance: number,
	now: number,
	nextAllowedAt: number,
	reclaimRange: number
): boolean
	return ownerState == Types.ParticipantState.Empty
		and onDeck
		and distance <= reclaimRange
		and now >= nextAllowedAt
end

return InputRules
