--!strict
-- 종 세 번. 첫 종의 조건(띠에 닿음 또는 상한), 종 간격 뽑기, 셋째 종에 출항.
-- 뽑은 간격과 종의 시각은 이 모듈의 지역 변수에만 둔다(숨은 값). 클라이언트에는 BellCount만 간다.
-- 종은 무게를 모른다. 그래서 무게가 줄어도 멈추지 않는다(BL-3).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local BellRules = require(ReplicatedStorage.Shared.Rules.BellRules)
local DevTools = require(script.Parent.DevTools)

local BellService = {}

local boat: Model
local fx: RemoteEvent
local random = Random.new()

local bells: BellRules.Bells? = nil
local loadingStartedAt = 0 -- 이번 Loading이 시작된 서버 시각

local function now(): number
	return workspace:GetServerTimeNow()
end

-- 간격 둘을 BELL_GAP_MIN과 BELL_GAP_MAX 사이에서 따로, 소수까지 고르게(BL-2)
function BellService.drawGaps(): (number, number)
	return BellRules.drawGaps(Config.BELL_GAP_MIN, Config.BELL_GAP_MAX, function()
		return random:NextNumber()
	end)
end

local function ring(number: number)
	boat:SetAttribute("BellCount", number)
	fx:FireAllClients("Bell", number)
end

-- Loading에 들어갈 때. 간격은 이때 뽑아 넣어 둔다
function BellService.startRound(startedAt: number, label: string)
	loadingStartedAt = startedAt
	local forced = DevTools.forcedBellGaps()
	local gap1, gap2
	if forced ~= nil then
		gap1, gap2 = forced[1], forced[2]
	else
		gap1, gap2 = BellService.drawGaps()
	end
	bells = BellRules.newBells(Config.FIRST_BELL_CAP[Types.ShipSize.Normal], gap1, gap2)
	print(`{label} 종 간격 {string.format("%.2f", gap1)}, {string.format("%.2f", gap2)}`)
	boat:SetAttribute("BellCount", 0)
end

-- 무게가 처음으로 범위의 아래 끝에 닿은 순간(BL-1). 놓기 처리에서 부른다
function BellService.firstBell()
	local current = bells
	if current == nil then
		return
	end
	if BellRules.firstBell(current, now() - loadingStartedAt) then
		ring(current.count)
	end
end

-- 매 프레임. 상한이 지났는데 첫 종이 없으면 울리고, 시각이 된 둘째와 셋째 종을 울린다.
-- 셋째 종이 울렸으면 출항 시각(서버 시각)을 돌려준다
function BellService.tick(): number?
	local current = bells
	if current == nil then
		return nil
	end
	local elapsed = now() - loadingStartedAt
	local rung = BellRules.tick(current, elapsed)
	for _, number in rung do
		ring(number)
	end
	-- 셋째 종이 울리는 순간 출항이다(BL-4). 종 수와 단계를 같은 프레임에서 바꾼다
	local thirdAt = current.thirdAt
	if thirdAt ~= nil and elapsed >= thirdAt then
		-- 셋째 종에는 뱃고동을 겹친다
		fx:FireAllClients("Horn")
		bells = nil
		return loadingStartedAt + thirdAt
	end
	return nil
end

-- 침몰하거나 라운드가 멈추면 남은 종의 시각을 버린다
function BellService.stop()
	bells = nil
end

function BellService.start()
	boat = workspace:WaitForChild("Map"):WaitForChild("Boat") :: Model
	fx = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Fx") :: RemoteEvent
end

return BellService
