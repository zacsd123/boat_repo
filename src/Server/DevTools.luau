--!strict
-- Studio에서만 동작하는 시험 도구. 게시된 서버에서는 모든 값이 무시된다.
-- 시험용 값은 Config에 두지 않는다(docs/02-config.md의 "시험용 값").
-- 이 단계(S02)에서는 값 다섯의 자리만 둔다. 쓰는 것은 S03, S06, S09, S10이다.

local RunService = game:GetService("RunService")

-- 시험할 때 여기 값을 바꾼다. nil은 "없음"이다
local DEBUG_FORCE_LIMIT: number? = nil -- 숨은 한계를 이 값으로 고정
local DEBUG_FORCE_BELL_GAPS: { number }? = nil -- 종 간격 둘을 이 값으로 고정
local DEBUG_FORCE_P: number? = nil -- P를 이 값으로 고정
local DEBUG_PRINT_LIMIT = false -- 라운드마다 뽑힌 한계를 서버 출력에 찍기
local DEBUG_RUN_TESTS = true -- 서버가 켜질 때 규칙 시험(S03) 돌리기

local DevTools = {}

function DevTools.forcedLimit(): number?
	if not RunService:IsStudio() then return nil end
	return DEBUG_FORCE_LIMIT
end

function DevTools.forcedBellGaps(): { number }?
	if not RunService:IsStudio() then return nil end
	return DEBUG_FORCE_BELL_GAPS
end

function DevTools.forcedP(): number?
	if not RunService:IsStudio() then return nil end
	return DEBUG_FORCE_P
end

function DevTools.shouldPrintLimit(): boolean
	if not RunService:IsStudio() then return false end
	return DEBUG_PRINT_LIMIT
end

function DevTools.shouldRunTests(): boolean
	if not RunService:IsStudio() then return false end
	return DEBUG_RUN_TESTS
end

return DevTools
