--[[
	EconomyMath.luau
	Fórmulas puras da economia (sem estado, sem APIs do Roblox). Os números vêm do Config;
	aqui fica só a matemática, para ser testada no Lune.
]]

local EconomyMath = {}

-- Multiplicador de Cash: (1 + Rebirths * step) x DoubleCash
function EconomyMath.multiplier(rebirths: number, step: number, hasDoubleCash: boolean, doubleFactor: number): number
	return (1 + rebirths * step) * (if hasDoubleCash then doubleFactor else 1)
end

-- Valor final de uma coleta (arredondado, mínimo 1 quando base > 0).
function EconomyMath.award(base: number, multiplier: number, extra: number?): number
	if base <= 0 then
		return 0
	end
	return math.max(1, math.floor(base * multiplier * (extra or 1) + 0.5))
end

function EconomyMath.totalSlots(
	baseSlots: number,
	rebirths: number,
	rebirthBonus: number,
	boughtSlots: number,
	passBonus: number,
	maxSlots: number
): number
	return math.min(baseSlots + rebirths * rebirthBonus + boughtSlots + passBonus, maxSlots)
end

function EconomyMath.recordSeconds(baseSeconds: number, level: number, step: number): number
	return baseSeconds + level * step
end

function EconomyMath.walkSpeed(baseSpeed: number, level: number, step: number): number
	return baseSpeed + level * step
end

-- Renda offline = ganho/min * minutos fora (com teto) * eficiência.
function EconomyMath.offlineEarnings(
	perMinute: number,
	secondsAway: number,
	capHours: number,
	efficiency: number
): number
	if perMinute <= 0 or secondsAway <= 0 then
		return 0
	end
	local minutes = math.min(secondsAway, capHours * 3600) / 60
	return math.floor(perMinute * minutes * efficiency)
end

-- Média de uma janela de baldes por minuto.
function EconomyMath.averageRate(buckets: { number }): number
	if #buckets == 0 then
		return 0
	end
	local total = 0
	for _, v in buckets do
		total += v
	end
	return total / #buckets
end

-- Recompensa diária. Dias são inteiros (os.time() // 86400).
-- Retorna (disponível, próximoDiaDaSequência).
function EconomyMath.dailyNext(lastDay: number, streak: number, today: number, maxDays: number): (boolean, number)
	if lastDay == today then
		return false, streak
	end
	if lastDay == today - 1 and streak > 0 then
		return true, (streak % maxDays) + 1
	end
	return true, 1
end

-- Pacote de Cash proporcional ao próximo rebirth.
function EconomyMath.cashPack(rebirths: number, fraction: number, rebirthCost: (number) -> number): number
	return math.max(100, math.floor(rebirthCost(rebirths) * fraction))
end

return EconomyMath
