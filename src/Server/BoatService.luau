--!strict
-- 배의 높이와 배다리. 무게와 침몰은 S08, S09에서 더한다.

local BoatService = {}

-- 배다리의 윗면이 선착장 머리 끝(GangwayEnd)과 갑판 입구(Root.Entrance)를 잇도록 다시 놓는다
local function fitGangway(gangway: BasePart, dockEnd: Attachment, entrance: Attachment)
	local a = dockEnd.WorldPosition
	local b = entrance.WorldPosition
	local mid = (a + b) / 2
	gangway.Size = Vector3.new(gangway.Size.X, gangway.Size.Y, (b - a).Magnitude)
	gangway.CFrame = CFrame.lookAt(mid, b) * CFrame.new(0, -gangway.Size.Y / 2, 0)
end

function BoatService.start()
	local map = workspace:WaitForChild("Map")
	local boat = map:WaitForChild("Boat") :: Model
	local root = boat:WaitForChild("Root") :: BasePart
	local gangway = map:WaitForChild("Gangway") :: BasePart
	local dockEnd = map:WaitForChild("Dock"):WaitForChild("Head"):WaitForChild("GangwayEnd") :: Attachment
	-- 입구는 고정된 Root에 붙어 있어서 Root를 옮기는 즉시 새 자리를 읽을 수 있다
	local entrance = root:WaitForChild("Entrance") :: Attachment

	fitGangway(gangway, dockEnd, entrance)
	root:GetPropertyChangedSignal("CFrame"):Connect(function()
		fitGangway(gangway, dockEnd, entrance)
	end)
end

return BoatService
