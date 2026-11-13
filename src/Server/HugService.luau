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
local ParticipantService = require(script.Parent.ParticipantService)
local CrateService = require(script.Parent.CrateService)
local WaterService = require(script.Parent.WaterService)
local Telemetry = require(script.Parent.Telemetry)

local State = Types.ParticipantState
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

	-- 3초가 찼으면 물 자리로 던져 넣는다(GP-8)
	if hugger ~= nil and result.hugger == "InWater" and reason == Reason.Completed then
		WaterService.throwIn(hugger)
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
		reclaimable = function()
			return false -- 되찾기는 S19
		end,
		reclaim = function() end,
	})
	RunService.Heartbeat:Connect(step)
end

return HugService
