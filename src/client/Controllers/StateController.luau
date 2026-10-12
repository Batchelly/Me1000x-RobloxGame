--[[
	StateController.luau
	Guarda o último snapshot de estado enviado pelo servidor (StateSync) e avisa os outros
	controllers. Timers (escudo, chuva, recarga de banana) são contados localmente a partir
	do momento em que o snapshot chegou.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)

local StateController = {}

StateController.changed = Signal.new()
StateController.state = nil :: Types.ClientState?
local receivedAt = os.clock()

function StateController.set(state: Types.ClientState?)
	if type(state) ~= "table" then
		return
	end
	StateController.state = state
	receivedAt = os.clock()
	StateController.changed:Fire(state)
end

function StateController.get(): Types.ClientState?
	return StateController.state
end

-- Segundos restantes de um campo "...Left" do estado, descontando o tempo desde o snapshot.
function StateController.timeLeft(field: string): number
	local state = StateController.state :: any
	if not state or type(state[field]) ~= "number" then
		return 0
	end
	return math.max(0, state[field] - (os.clock() - receivedAt))
end

function StateController.init()
	Net.connect("StateSync", StateController.set)
end

return StateController
