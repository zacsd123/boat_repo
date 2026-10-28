--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local DevTools = require(script.Parent.DevTools)

-- 수치가 서로 맞는지 먼저 본다. 어긋나면 여기서 오류로 멈춘다
Config.validate()

-- Studio에서만 규칙 시험을 돌린다. 하나라도 실패하면 여기서 오류로 멈춘다
if DevTools.shouldRunTests() then
	local Tests = require(script.Parent.Tests)
	local ruleCount, exampleCount = Tests.run()
	print(`규칙 시험 {ruleCount}개와 예시 {exampleCount}판 통과`)
end

print("server up")

-- 서비스를 켠다
local ParticipantService = require(script.Parent.ParticipantService)
local BoatService = require(script.Parent.BoatService)
ParticipantService.start()
BoatService.start()

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
