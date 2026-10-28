--!strict
-- 소리와 연출. 서버가 보내는 Fx를 받는다. 소리와 연출은 S14와 S30에서 붙인다.
-- 지금은 받은 것을 출력에 찍기만 한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FxController = {}

function FxController.start()
	local fx = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Fx") :: RemoteEvent
	fx.OnClientEvent:Connect(function(name: string)
		print(`Fx {name}`)
	end)
end

return FxController
