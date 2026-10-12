--[[
	Clock.luau
	Relógio compartilhado servidor/cliente. Clones usam (Clock.now() - startTime) % duração,
	então servidor e clientes precisam do MESMO relógio: workspace:GetServerTimeNow().
]]

local Clock = {}

function Clock.now(): number
	return workspace:GetServerTimeNow()
end

return Clock
