--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

-- 수치가 서로 맞는지 먼저 본다. 어긋나면 여기서 오류로 멈춘다
Config.validate()

print("server up")

-- 1명부터 차례로 찍는다
for p = 1, #Config.LIMIT_RANGE do
	local lo, hi = Config.limitRange(p)
	print(`LIMIT_RANGE P={p}: {lo}~{hi}`)
end

-- 빈손과 상자 종류 넷. CARRY_TIME의 키와 같다
local carryKinds: { string } = {
	Types.ParticipantState.Empty,
	Types.CrateKind.Small,
	Types.CrateKind.Medium,
	Types.CrateKind.Large,
	Types.CrateKind.Gold,
}
for _, kind in carryKinds do
	print(`carrySpeed {kind}: {string.format("%.2f", Config.carrySpeed(kind))}`)
end
