--!strict
-- Studio에서만 동작하는 시험 도구. 게시된 서버에서는 모든 값이 무시된다.
-- 시험용 값은 Config에 두지 않는다(docs/02-config.md의 "시험용 값").
-- 이 단계(S02)에서는 값 다섯의 자리만 둔다. 쓰는 것은 S03, S06, S09, S10이다.

local Players = game:GetService("Players")
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

-- 점이 구역 상자 안에 있는지
local function inside(zone: BasePart, point: Vector3): boolean
	local localPoint = zone.CFrame:PointToObjectSpace(point)
	local half = zone.Size / 2
	return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z
end

-- 초시계. 캐릭터가 구역 A를 떠난 순간부터 구역 B에 들어간 순간까지를 서버 출력에 찍는다.
-- 한 번 찍으면 끝난다. player를 안 주면 첫 번째 플레이어를 잰다. 서버 명령창에서 부른다:
--   game.ServerStorage.DevCommand:Invoke("stopwatch", workspace.Map.Zones.PileLargeZone, workspace.Map.Zones.DeckZone)
function DevTools.stopwatch(fromZone: BasePart, toZone: BasePart, player: Player?)
	if not RunService:IsStudio() then return end
	local who = player or Players:GetPlayers()[1]
	if who == nil then
		warn("초시계: 플레이어가 없다")
		return
	end

	local leftAt: number? = nil
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local character = who.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart == nil then return end
		local position = rootPart.Position
		if leftAt == nil then
			if not inside(fromZone, position) then
				leftAt = os.clock()
			end
		elseif inside(toZone, position) then
			connection:Disconnect()
			print(`초시계 {fromZone.Name} → {toZone.Name}: {string.format("%.2f", os.clock() - leftAt)}초`)
		end
	end)
end

-- 플레이어 대신 Tap을 보낸다. 서버의 확인을 그대로 지나므로, 멀리 있는 더미를 대상으로 하면 버린 이유가 찍힌다.
function DevTools.fakeTap(target: any, player: Player?)
	if not RunService:IsStudio() then return end
	local who = player or Players:GetPlayers()[1]
	if who == nil then return end
	local CrateService = require(script.Parent.CrateService) :: any
	CrateService.handleTap(who, target)
end

local function newestFirst(crates: { Instance }): { Instance }
	table.sort(crates, function(a, b)
		return ((a:GetAttribute("CrateId") :: number?) or 0) > ((b:GetAttribute("CrateId") :: number?) or 0)
	end)
	return crates
end

-- 무게를 target으로 만든다. 시험용(주인 없는) 상자를 화물칸에 넣고 뺀다. 넣을 때는 실제 놓기와 같은 판정을 지난다
function DevTools.setWeight(target: number): number
	if not RunService:IsStudio() then return -1 end
	local CrateService = require(script.Parent.CrateService) :: any
	local BoatService = require(script.Parent.BoatService) :: any
	local Config = require(game:GetService("ReplicatedStorage").Shared.Config) :: any
	-- 넘치면 시험용 상자부터, 그래도 넘치면 아무 상자나 뺀다
	for _, ownerless in { true, false } do
		for _, crate in newestFirst(CrateService.cargoCrates()) do
			if BoatService.deckWeight() <= target then
				break
			end
			if not ownerless or crate:GetAttribute("OwnerSlot") == nil then
				CrateService.removeCrate(crate)
			end
		end
	end
	while BoatService.deckWeight() < target do
		local gap = target - BoatService.deckWeight()
		local result = CrateService.addTestCrate(if gap >= Config.CRATE_SCORE.Large then "Large" else "Small")
		-- 싣는 단계가 아니거나 가라앉았으면 멈춘다
		if result == nil or result.sank then
			break
		end
	end
	return BoatService.deckWeight()
end

-- 숨은 한계를 n번(기본 1,000번) 뽑아 분포를 찍는다. 실제 라운드와 같은 함수로 뽑는다
function DevTools.limitDistribution(p: number, n: number?): string
	if not RunService:IsStudio() then return "" end
	local Config = require(game:GetService("ReplicatedStorage").Shared.Config) :: any
	local BoatService = require(script.Parent.BoatService) :: any
	local lo, hi = Config.limitRange(p)
	local count = n or 1000
	local sum, low, high, nonInteger = 0, math.huge, -math.huge, 0
	local seen: { [number]: number } = {}
	for _ = 1, count do
		local limit = BoatService.drawLimit(lo, hi)
		sum += limit
		low = math.min(low, limit)
		high = math.max(high, limit)
		seen[limit] = (seen[limit] or 0) + 1
		if limit ~= math.floor(limit) then
			nonInteger += 1
		end
	end
	local summary = `한계 {count}번 (P={p}, 범위 {lo}~{hi}): 최소 {low}, 최대 {high}, 평균 {string.format("%.2f", sum / count)}, `
		.. `{lo} 나옴 {seen[lo] or 0}번, {hi} 나옴 {seen[hi] or 0}번, 정수 아님 {nonInteger}번`
	print(summary)
	return summary
end

-- 실린 상자 하나(가장 나중에 실린 것)를 지운다
function DevTools.removeOne(): number
	if not RunService:IsStudio() then return -1 end
	local CrateService = require(script.Parent.CrateService) :: any
	local BoatService = require(script.Parent.BoatService) :: any
	local crates = newestFirst(CrateService.cargoCrates())
	if crates[1] then
		CrateService.removeCrate(crates[1])
	end
	return BoatService.deckWeight()
end

-- 종 간격을 n번(기본 100번) 실제와 같은 함수로 뽑아 "첫 종부터 출항까지"(간격 둘의 합)를 찍는다(S10).
-- longerThan(기본 7.5초, 큰 상자 한 번 더 가져오는 시간)을 넘는 비율도 함께 찍는다
function DevTools.bellSimulation(n: number?, longerThan: number?): string
	if not RunService:IsStudio() then return "" end
	local BellService = require(script.Parent.BellService) :: any
	local Config = require(game:GetService("ReplicatedStorage").Shared.Config) :: any
	local count = n or 100
	local threshold = longerThan or (Config.CARRY_TIME.Large + Config.CARRY_TIME.Empty)
	local sum, low, high, over = 0, math.huge, -math.huge, 0
	for _ = 1, count do
		local gap1, gap2 = BellService.drawGaps()
		local span = gap1 + gap2
		sum += span
		low = math.min(low, span)
		high = math.max(high, span)
		if span > threshold then
			over += 1
		end
	end
	local summary = `종 {count}라운드: 첫 종부터 출항까지 최소 {string.format("%.2f", low)}, 최대 {string.format("%.2f", high)}, `
		.. `평균 {string.format("%.2f", sum / count)}초, {string.format("%.1f", threshold)}초를 넘는 비율 {string.format("%.0f", over / count * 100)}%`
	print(summary)
	return summary
end

-- 명령창에서 DevTools를 부르는 입구. 명령창에서 require하면 게임과 다른 모듈 사본이 생겨서
-- 게임이 쓰는 상태(참가자, 배, 상자)가 보이지 않는다. 그래서 게임 안에서 명령을 받아 실행한다:
--   game.ServerStorage.DevCommand:Invoke("fakeTap", "Large")
function DevTools.listen()
	if not RunService:IsStudio() then return end
	local command = Instance.new("BindableFunction")
	command.Name = "DevCommand"
	command.OnInvoke = function(name: string, ...: any): any
		local fn = (DevTools :: any)[name]
		if type(fn) ~= "function" then
			return `DevTools에 {name}이 없다`
		end
		return fn(...)
	end
	command.Parent = game:GetService("ServerStorage")
end

return DevTools
