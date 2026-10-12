--[[
	Path.luau
	Compressão e interpolação dos caminhos gravados. Módulo PURO (testável no Lune).

	Formato binário (buffer), versão 1:
		offset 0  u8   versão
		offset 1  u8   hz (amostras por segundo)
		offset 2  u8   scale (unidades int16 por stud)
		offset 3  u8   reservado
		offset 4  u16  n (número de amostras)
		offset 6  u16  reservado
		offset 8  f32  origem X  (posição da 1ª amostra)
		offset 12 f32  origem Y
		offset 16 f32  origem Z
		offset 20 ...  n amostras de 8 bytes:
			i16 dx, i16 dy, i16 dz  -> delta quantizado em relação à amostra anterior
			u8  yaw                  -> rotação Y quantizada em 256 passos
			u8  flags                -> bit 1 = pulo

	As posições são quantizadas relativas à origem ANTES do delta, então o erro
	não acumula: cada amostra reconstruída fica a no máximo 0,5/scale stud da original.
	Uma gravação de 40 s a 10 Hz ocupa 20 + 401 * 8 = 3228 bytes.
]]

local Path = {}

Path.VERSION = 1
Path.HEADER_SIZE = 20
Path.SAMPLE_SIZE = 8
Path.FLAG_JUMP = 1

local TWO_PI = math.pi * 2
local INT16_MIN, INT16_MAX = -32768, 32767

export type PathData = {
	n: number,
	hz: number,
	scale: number,
	duration: number,
	xs: { number },
	ys: { number },
	zs: { number },
	yaws: { number },
	flags: { number },
}

local function round(v: number): number
	return math.floor(v + 0.5)
end

function Path.quantizeYaw(yaw: number): number
	return round(yaw / TWO_PI * 256) % 256
end

function Path.dequantizeYaw(q: number): number
	return q / 256 * TWO_PI
end

-- Comprime as amostras. xs/ys/zs/yaws/flags são arrays do mesmo tamanho (>= 1).
function Path.encode(
	xs: { number },
	ys: { number },
	zs: { number },
	yaws: { number },
	flags: { number },
	hz: number,
	scale: number
): buffer
	local n = #xs
	assert(n >= 1 and n <= 65535, "Path.encode: número de amostras inválido")
	assert(hz >= 1 and hz <= 255 and scale >= 1 and scale <= 255, "Path.encode: hz/scale inválidos")

	local buf = buffer.create(Path.HEADER_SIZE + n * Path.SAMPLE_SIZE)
	buffer.writeu8(buf, 0, Path.VERSION)
	buffer.writeu8(buf, 1, hz)
	buffer.writeu8(buf, 2, scale)
	buffer.writeu16(buf, 4, n)
	buffer.writef32(buf, 8, xs[1])
	buffer.writef32(buf, 12, ys[1])
	buffer.writef32(buf, 16, zs[1])
	-- Usa a origem já arredondada para f32, igual à que o decode vai ler.
	local ox, oy, oz = buffer.readf32(buf, 8), buffer.readf32(buf, 12), buffer.readf32(buf, 16)

	local px, py, pz = 0, 0, 0
	local offset = Path.HEADER_SIZE
	for i = 1, n do
		local dx = math.clamp(round((xs[i] - ox) * scale) - px, INT16_MIN, INT16_MAX)
		local dy = math.clamp(round((ys[i] - oy) * scale) - py, INT16_MIN, INT16_MAX)
		local dz = math.clamp(round((zs[i] - oz) * scale) - pz, INT16_MIN, INT16_MAX)
		px += dx
		py += dy
		pz += dz
		buffer.writei16(buf, offset, dx)
		buffer.writei16(buf, offset + 2, dy)
		buffer.writei16(buf, offset + 4, dz)
		buffer.writeu8(buf, offset + 6, Path.quantizeYaw(yaws[i] or 0))
		buffer.writeu8(buf, offset + 7, bit32.band(flags[i] or 0, 255))
		offset += Path.SAMPLE_SIZE
	end
	return buf
end

-- Descomprime. Retorna nil se o buffer for inválido (dados corrompidos ou adulterados).
function Path.decode(buf: any): PathData?
	if typeof(buf) ~= "buffer" then
		return nil
	end
	local len = buffer.len(buf)
	if len < Path.HEADER_SIZE then
		return nil
	end
	local version = buffer.readu8(buf, 0)
	local hz = buffer.readu8(buf, 1)
	local scale = buffer.readu8(buf, 2)
	local n = buffer.readu16(buf, 4)
	if version ~= Path.VERSION or hz == 0 or scale == 0 or n == 0 then
		return nil
	end
	if len ~= Path.HEADER_SIZE + n * Path.SAMPLE_SIZE then
		return nil
	end
	local ox, oy, oz = buffer.readf32(buf, 8), buffer.readf32(buf, 12), buffer.readf32(buf, 16)
	if ox ~= ox or oy ~= oy or oz ~= oz or math.abs(ox) > 1e6 or math.abs(oy) > 1e6 or math.abs(oz) > 1e6 then
		return nil -- NaN ou absurdo
	end

	local xs, ys, zs = table.create(n), table.create(n), table.create(n)
	local yaws, flags = table.create(n), table.create(n)
	local px, py, pz = 0, 0, 0
	local offset = Path.HEADER_SIZE
	for i = 1, n do
		px += buffer.readi16(buf, offset)
		py += buffer.readi16(buf, offset + 2)
		pz += buffer.readi16(buf, offset + 4)
		xs[i] = ox + px / scale
		ys[i] = oy + py / scale
		zs[i] = oz + pz / scale
		yaws[i] = Path.dequantizeYaw(buffer.readu8(buf, offset + 6))
		flags[i] = buffer.readu8(buf, offset + 7)
		offset += Path.SAMPLE_SIZE
	end

	return {
		n = n,
		hz = hz,
		scale = scale,
		duration = (n - 1) / hz,
		xs = xs,
		ys = ys,
		zs = zs,
		yaws = yaws,
		flags = flags,
	}
end

-- Fase dentro do loop: (agora - início) % duração. Funciona com elapsed negativo.
function Path.phase(path: PathData, elapsed: number): number
	if path.duration <= 0 then
		return 0
	end
	return elapsed % path.duration
end

-- Posição interpolada no tempo t (0..duration). Retorna x, y, z, yaw, flags.
function Path.sample(path: PathData, t: number): (number, number, number, number, number)
	local xs, ys, zs, yaws = path.xs, path.ys, path.zs, path.yaws
	local n = path.n
	if n == 1 or t <= 0 then
		return xs[1], ys[1], zs[1], yaws[1], path.flags[1]
	end
	local f = t * path.hz
	local i = math.floor(f)
	if i >= n - 1 then
		return xs[n], ys[n], zs[n], yaws[n], path.flags[n]
	end
	local a = f - i
	local i1, i2 = i + 1, i + 2
	local y1 = yaws[i1]
	local dyaw = (yaws[i2] - y1 + math.pi) % TWO_PI - math.pi -- caminho angular mais curto
	return xs[i1] + (xs[i2] - xs[i1]) * a,
		ys[i1] + (ys[i2] - ys[i1]) * a,
		zs[i1] + (zs[i2] - zs[i1]) * a,
		y1 + dyaw * a,
		path.flags[i1]
end

-- Um passo de gravação é legítimo? (anti-teleporte)
function Path.isStepValid(
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number,
	dt: number,
	maxHorizontalSpeed: number,
	maxVerticalSpeed: number,
	tolerance: number,
	flatSlack: number
): boolean
	local dx, dz = bx - ax, bz - az
	local horizontal = math.sqrt(dx * dx + dz * dz)
	local vertical = math.abs(by - ay)
	return horizontal <= maxHorizontalSpeed * dt * tolerance + flatSlack
		and vertical <= maxVerticalSpeed * dt * tolerance + flatSlack
end

-- Índice da primeira amostra com teleporte, ou nil se o caminho inteiro é válido.
function Path.findTeleport(
	xs: { number },
	ys: { number },
	zs: { number },
	dt: number,
	maxHorizontalSpeed: number,
	maxVerticalSpeed: number,
	tolerance: number,
	flatSlack: number
): number?
	for i = 2, #xs do
		if
			not Path.isStepValid(
				xs[i - 1],
				ys[i - 1],
				zs[i - 1],
				xs[i],
				ys[i],
				zs[i],
				dt,
				maxHorizontalSpeed,
				maxVerticalSpeed,
				tolerance,
				flatSlack
			)
		then
			return i
		end
	end
	return nil
end

-- Distância² do ponto P ao segmento AB (usado para coleta e bananas).
function Path.segmentDistanceSq(
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number,
	px: number,
	py: number,
	pz: number
): number
	local abx, aby, abz = bx - ax, by - ay, bz - az
	local apx, apy, apz = px - ax, py - ay, pz - az
	local lenSq = abx * abx + aby * aby + abz * abz
	local t = 0
	if lenSq > 1e-9 then
		t = math.clamp((apx * abx + apy * aby + apz * abz) / lenSq, 0, 1)
	end
	local cx, cy, cz = ax + abx * t - px, ay + aby * t - py, az + abz * t - pz
	return cx * cx + cy * cy + cz * cz
end

-- Aplica fn(x, z, yaw) -> (x, z, yaw) em todas as amostras e recomprime. Usado para levar
-- gravações da Pista de uma base para outra (espaço local do plot <-> mundo).
function Path.mapXZ(buf: buffer, fn: (number, number, number) -> (number, number, number)): buffer?
	local path = Path.decode(buf)
	if not path then
		return nil
	end
	local xs, zs, yaws = table.create(path.n), table.create(path.n), table.create(path.n)
	for i = 1, path.n do
		xs[i], zs[i], yaws[i] = fn(path.xs[i], path.zs[i], path.yaws[i])
	end
	return Path.encode(xs, path.ys, zs, yaws, path.flags, path.hz, path.scale)
end

-- Amostra até `count` pontos (x, z) espalhados pelo caminho (mini-mapa da fita).
function Path.preview(path: PathData, count: number): { number }
	local out = {}
	local step = math.max(1, math.floor(path.n / count))
	for i = 1, path.n, step do
		table.insert(out, path.xs[i])
		table.insert(out, path.zs[i])
	end
	return out
end

return Path
