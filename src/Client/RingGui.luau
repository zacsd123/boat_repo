--!strict
-- 상자 위에 뜨는 고리. 꾹 누르기(S17)와 끌어안기(S18)가 얼마나 찼는지를 글 없이 보여 준다(IN-6).
-- 바깥 고리 안쪽이 가운데부터 차오른다. 모양과 크기는 디자인 전 임시다(규칙의 수치가 아니다).

local RingGui = {}

local SIZE = 3.5 -- 고리의 지름(스터드)
local LIFT = 1.2 -- 상자 윗면에서 고리 가운데까지(스터드)
local HOLE = 0.72 -- 바깥 고리 안쪽 빈 곳의 비율
local HOLE_COLOR = Color3.fromRGB(20, 20, 20)

export type Ring = {
	set: (progress: number) -> (),
	destroy: () -> (),
}

local function circle(parent: Instance, color: Color3, scale: number, transparency: number): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(scale, scale)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	frame.Parent = parent
	return frame
end

-- adornee 위에 color 색 고리를 띄운다. set(0~1)로 채우고 destroy로 지운다
function RingGui.new(adornee: BasePart, color: Color3, parent: Instance): Ring
	local gui = Instance.new("BillboardGui")
	gui.Name = "Ring"
	gui.Adornee = adornee
	gui.Size = UDim2.fromScale(SIZE, SIZE)
	gui.StudsOffsetWorldSpace = Vector3.new(0, adornee.Size.Y / 2 + LIFT, 0)
	gui.AlwaysOnTop = true
	circle(gui, color, 1, 0)
	circle(gui, HOLE_COLOR, HOLE, 0.2)
	local fill = circle(gui, color, 0, 0)
	gui.Parent = parent

	local ring = {}
	function ring.set(progress: number)
		local share = math.clamp(progress, 0, 1) * HOLE
		fill.Size = UDim2.fromScale(share, share)
	end
	function ring.destroy()
		gui:Destroy()
	end
	return ring
end

return RingGui
