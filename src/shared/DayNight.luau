--[[
	DayNight.luau
	Ciclo dia/noite determinístico a partir do relógio do servidor (todos os clientes veem
	a mesma hora, sem tráfego de rede). Módulo PURO (testável no Lune).

	Um ciclo dura Config.DayNight.CycleSeconds. A fração DayFraction do ciclo é dia
	(ClockTime 6 -> 18); o resto é noite (18 -> 30 = 6 do dia seguinte).
]]

local DayNight = {}

-- ClockTime (0..24) para um tempo em segundos.
function DayNight.clockTime(seconds: number, cycleSeconds: number, dayFraction: number): number
	local phase = (seconds % cycleSeconds) / cycleSeconds -- 0..1
	local hours
	if phase < dayFraction then
		hours = 6 + (phase / dayFraction) * 12
	else
		hours = 18 + ((phase - dayFraction) / (1 - dayFraction)) * 12
	end
	return hours % 24
end

-- É noite? (luzes acesas, grilos)
function DayNight.isNight(clockTime: number): boolean
	return clockTime >= 18.5 or clockTime < 5.5
end

-- 0 (dia claro) .. 1 (noite fechada), com transição suave no amanhecer/entardecer.
function DayNight.nightAmount(clockTime: number): number
	if clockTime >= 7 and clockTime <= 17 then
		return 0
	end
	if clockTime > 17 and clockTime < 19.5 then
		return (clockTime - 17) / 2.5
	end
	if clockTime >= 4.5 and clockTime < 7 then
		return 1 - (clockTime - 4.5) / 2.5
	end
	return 1
end

return DayNight
