--!strict
-- 끌어안기의 시작과 끝(S18), 되찾기(S19), 경계 사례(S20).
-- 끌어안기는 HUG_TIME 동안 두 사람과 상자 하나를 묶어 두는 상태다. 그동안 상자는 갑판에 있는 것으로 친다(HG-4).
-- 끝나는 길은 endHug 하나로 모으고, 이유마다 상자와 사람이 어떻게 되는지는 HugRules가 정한다(S20의 표).
-- 끝나는 시각은 서버가 정한다. 클라이언트의 고리는 상자의 HugEndsAt을 보고 그리기만 한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local HugRules = require(ReplicatedStorage.Shared.Rules.HugRules)
local InputRules = require(ReplicatedStorage.Shared.Rules.InputRules)
local ParticipantService = require(script.Parent.ParticipantService)
local RoundService = require(script.Parent.RoundService)
local BoatService = require(script.Parent.BoatService)
local CrateService = require(script.Parent.CrateService)
local WaterService = require(script.Parent.WaterService)
local Telemetry = require(script.Parent.Telemetry)

local State = Types.ParticipantState
local Phase = Types.Phase
local Reason = HugRules.Reason

local HugService = {}

type Hug = {
	hugger: Player?, -- 끌어안는 사람. 없으면 DevTools의 시험용 끌어안기다
	huggerSlot: number,
	ownerSlot: number?, -- 주인 없는 시험용 상자면 없다
	endsAt: number, -- 서버 시각
}

-- 시험용 끌어안기가 쓰는 슬롯 번호. 참가자 슬롯(1~SERVER_MAX_PLAYERS)과 겹치지 않는다
local GHOST_SLOT = 0

local hugs: { [Model]: Hug } = {}
local nextReclaimAt: { [Player]: number } = {} -- 되찾기를 다시 쓸 수 있는 서버 시각(RC-3)
local fx: RemoteEvent

local function now(): number
	return workspace:GetServerTimeNow()
end

local function start(crate: Model, hugger: Player?, huggerSlot: number)
	local endsAt = now() + Config.HUG_TIME
	local ownerSlot = crate:GetAttribute("OwnerSlot") :: number?
	hugs[crate] = { hugger = hugger, huggerSlot = huggerSlot, ownerSlot = ownerSlot, endsAt = endsAt }
	-- 누구든 "저 상자가 곧 버려진다"를 볼 수 있다. 상자는 실린 상자 목록에 그대로 있다(HG-4)
	crate:SetAttribute("HuggedBySlot", huggerSlot)
	crate:SetAttribute("HugEndsAt", endsAt)
	-- 주인에게만 알린다(HG-6)
	local owner = ownerSlot and ParticipantService.playerOf(ownerSlot)
	if owner then
		fx:FireClient(owner, "HugAlert", crate)
	end
	Telemetry.hugStarted()
end

-- 꾹 누르기가 "끌어안기"로 끝났다. 조건(단계, 상태, 갑판, 거리, 아무도 끌어안고 있지 않음)은
-- CrateService가 InputRules.hold로 이미 확인했다. 같은 상자의 뒤늦은 요청은 거기서 걸린다(HG-2)
function HugService.begin(player: Player, crate: Model)
	local slot = ParticipantService.slotOf(player)
	if slot == nil or hugs[crate] ~= nil then
		return
	end
	-- 이때부터 HUG_TIME 동안 걷지도 버튼을 쓰지도 못한다(HG-3)
	ParticipantService.setState(player, State.Hugging, nil)
	-- 끌어안는 자세 대신 상자 쪽으로 돌아선다(자세는 디자인 때 만든다)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local body = crate.PrimaryPart
	if character and rootPart and body then
		local toward = Vector3.new(body.Position.X, rootPart.Position.Y, body.Position.Z)
		if (toward - rootPart.Position).Magnitude > 0 then
			character:PivotTo(CFrame.lookAt(rootPart.Position, toward))
		end
	end
	start(crate, player, slot)
end

-- 끌어안기를 끝낸다. 끝나는 길은 여기 하나다. 중간에 기다리지 않는다:
-- 사이가 벌어지면 "상자는 없는데 무게는 남은" 순간에 다른 사람의 놓기가 판정된다
function HugService.endHug(crate: Model, reason: HugRules.EndReason)
	local hug = hugs[crate]
	if hug == nil then
		return
	end
	hugs[crate] = nil
	local result = HugRules.endResult(reason)
	crate:SetAttribute("HuggedBySlot", nil)
	crate:SetAttribute("HugEndsAt", nil)

	-- 풀려남: 어느 길로 끝나든 상태와 걷는 속도를 되돌린다(나간 사람은 기록이 없다)
	local hugger = hug.hugger
	if hugger ~= nil and result.hugger ~= "Left" then
		ParticipantService.setState(hugger, State.Empty, nil)
	end

	if result.crate == "Removed" then
		if reason == Reason.Completed then
			local kind = crate:GetAttribute("Kind") :: string?
			Telemetry.hugCompleted(hug.ownerSlot, if kind then Config.CRATE_SCORE[kind] or 0 else 0)
		end
		-- 무게와 주인 점수를 다시 더한다. 주인이 나가서 이미 치워진 상자면 아무 일도 없다
		CrateService.removeCrate(crate)
	end

	-- 3초가 찼거나 되찾기를 당했으면 물 자리로 던져 넣는다(GP-8).
	-- 침몰은 갑판 위의 다른 사람과 함께 WaterService가 물에 빠뜨린다
	if hugger ~= nil and result.hugger == "InWater" and (reason == Reason.Completed or reason == Reason.Reclaimed) then
		WaterService.throwIn(hugger)
	end
end

-- 그 사람이 지금 되찾을 수 있는 상자들: 끌어안긴 내 상자 가운데 손 닿는 거리 안의 것(RC-1, RC-2).
-- 빈손이고 갑판 위이고 재사용 대기가 끝났는지는 InputRules.canReclaim이 본다(RC-3, RC-4).
-- 거리는 주인과 상자 사이를 서버가 잰다(주인과 끌어안는 사람 사이가 아니다)
local function reclaimTargets(player: Player, rootPart: BasePart): { Model }
	local targets: { Model } = {}
	local slot = ParticipantService.slotOf(player)
	local state = ParticipantService.stateOf(player)
	if slot == nil or state == nil then
		return targets
	end
	local onDeck = BoatService.isOnDeck(rootPart.Position)
	local allowedAt = nextReclaimAt[player] or 0
	for crate, hug in hugs do
		if hug.ownerSlot == slot and crate.Parent ~= nil then
			local distance = CrateService.distanceTo(rootPart, crate)
			if InputRules.canReclaim(state, onDeck, distance, now(), allowedAt, Config.RECLAIM_RANGE) then
				table.insert(targets, crate)
			end
		end
	end
	return targets
end

function HugService.reclaimable(player: Player, rootPart: BasePart): boolean
	return #reclaimTargets(player, rootPart) > 0
end

-- 되찾기(RC-1). 손 닿는 거리에서 내 상자를 끌어안고 있던 모두에게 한 번에 적용된다(RC-2).
-- 상자는 제자리에 남고 무게와 점수는 바뀌지 않는다. 끌어안던 사람만 물에 빠진다
function HugService.reclaim(player: Player, rootPart: BasePart)
	local targets = reclaimTargets(player, rootPart)
	if #targets == 0 then
		return
	end
	nextReclaimAt[player] = now() + Config.RECLAIM_COOLDOWN
	for _, crate in targets do
		local body = crate.PrimaryPart
		HugService.endHug(crate, Reason.Reclaimed)
		Telemetry.reclaimed()
		if body then
			fx:FireAllClients("Reclaim", body.Position)
		end
	end
end

-- 라운드가 끝나는 순간(출항 또는 침몰). 진행 중이던 끌어안기는 모두 무효다(HG-7).
-- 점수를 굳히기 전에 부른다. 순서가 뒤집히면 "3초가 찬 것으로" 처리될 수 있다
function HugService.endAll(reason: HugRules.EndReason)
	for crate in hugs do
		HugService.endHug(crate, reason)
	end
end

-- 사람이 나갈 때(S20). 끌어안던 사람이 나가면 상자는 제자리에 남고(JN-3),
-- 주인이 나가면 상자와 함께 끌어안기도 끝나고 끌어안던 사람은 갑판에 남는다(HG-8).
-- 주인의 상자는 CrateService가 치운다(JN-2). 여기서는 끌어안기만 끝낸다
local function onLeaving(player: Player, slot: number)
	nextReclaimAt[player] = nil
	for crate, hug in hugs do
		if hug.hugger == player then
			HugService.endHug(crate, Reason.HuggerLeft)
		elseif hug.ownerSlot == slot then
			HugService.endHug(crate, Reason.OwnerLeft)
		end
	end
end

-- 매 프레임: 시간이 찬 끌어안기를 끝낸다(HG-5)
local function step()
	local t = now()
	for crate, hug in hugs do
		if crate.Parent == nil then
			-- 시험 명령 따위로 상자가 먼저 치워졌다. 끌어안던 사람만 풀어 준다
			HugService.endHug(crate, Reason.OwnerLeft)
		elseif t >= hug.endsAt then
			HugService.endHug(crate, Reason.Completed)
		end
	end
end

-- 시험용: 끌어안는 사람 없이 상자를 끌어안긴 상태로 만든다. 주인 쪽(경고, 되찾기)을 혼자 시험할 때 쓴다.
-- DevTools만 부른다
function HugService.beginGhost(crate: Model): boolean
	if not RunService:IsStudio() or hugs[crate] ~= nil then
		return false
	end
	start(crate, nil, GHOST_SLOT)
	return true
end

function HugService.start()
	fx = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Fx") :: RemoteEvent
	CrateService.setHugHooks({
		begin = HugService.begin,
		reclaimable = HugService.reclaimable,
		reclaim = HugService.reclaim,
	})
	ParticipantService.onLeaving(onLeaving)
	RoundService.onRoundEnding(function(newPhase)
		-- 침몰이면 갑판 위의 다른 사람과 함께 물에 빠지고, 그 밖에는(출항, 모두 나감) 선착장에 내린다
		HugService.endAll(if newPhase == Phase.Sinking then Reason.Sank else Reason.Departed)
	end)
	RunService.Heartbeat:Connect(step)
end

return HugService
