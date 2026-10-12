--[[
	Format.luau
	Formatação de números (1.2K, 3.4M ...) e tempos. Módulo puro (testável no Lune).
]]

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- 999 -> "999", 1234 -> "1.2K", 3456789 -> "3.4M", 120500 -> "120K"
function Format.number(value: number?): string
	local n = tonumber(value) or 0
	local sign = if n < 0 then "-" else ""
	n = math.abs(n)
	if n < 1000 then
		return sign .. tostring(math.floor(n))
	end
	local index = 1
	while n >= 1000 and index < #SUFFIXES do
		n /= 1000
		index += 1
	end
	local text
	if n >= 100 then
		text = tostring(math.floor(n))
	else
		local truncated = math.floor(n * 10) / 10
		text = string.format("%.1f", truncated)
		text = string.gsub(text, "%.0$", "")
	end
	return sign .. text .. SUFFIXES[index]
end

-- Segundos -> "4:05" (menos de 1 h) ou "2h 05m".
function Format.time(seconds: number?): string
	local s = math.max(0, math.floor(tonumber(seconds) or 0))
	if s >= 3600 then
		return string.format("%dh %02dm", s // 3600, (s % 3600) // 60)
	end
	return string.format("%d:%02d", s // 60, s % 60)
end

-- Minutes -> "3h 20min" / "45min" (usado na tela de retorno offline)
function Format.minutes(minutes: number?): string
	local m = math.max(0, math.floor(tonumber(minutes) or 0))
	if m >= 60 then
		return string.format("%dh %02dmin", m // 60, m % 60)
	end
	return string.format("%dmin", m)
end

-- 1.5 -> "x1.5", 2 -> "x2"
function Format.multiplier(value: number): string
	local text = string.format("%.2f", value)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return "x" .. text
end

return Format
