-- Compressão de caminho e interpolação.
local T = require("./lib/T")
local Path = require("../src/shared/Path")

local SCALE, HZ = 20, 10

-- Caminho "real": corrida em zigue-zague com subida (como uma gravação de 40 s).
local function makeSamples(n: number)
	local xs, ys, zs, yaws, flags = {}, {}, {}, {}, {}
	for i = 1, n do
		local t = (i - 1) / HZ
		xs[i] = 37.123 + t * 15.7 + math.sin(t) * 3
		ys[i] = 3.0 + math.max(0, math.sin(t * 0.7) * 25)
		zs[i] = -88.456 + math.cos(t * 0.5) * 40
		yaws[i] = (t * 1.3) % (math.pi * 2) - math.pi
		flags[i] = if i % 25 == 0 then Path.FLAG_JUMP else 0
	end
	return xs, ys, zs, yaws, flags
end

T.describe("Path", function()
	T.it("tamanho do buffer = cabeçalho + 8 bytes por amostra", function()
		local xs, ys, zs, yaws, flags = makeSamples(401)
		local buf = Path.encode(xs, ys, zs, yaws, flags, HZ, SCALE)
		T.eq(buffer.len(buf), Path.HEADER_SIZE + 401 * Path.SAMPLE_SIZE)
		T.eq(buffer.len(buf), 3228, "gravação de 40 s")
	end)

	T.it("ida e volta preserva posições dentro de 0,5/scale (sem erro acumulado)", function()
		local xs, ys, zs, yaws, flags = makeSamples(401)
		local path = Path.decode(Path.encode(xs, ys, zs, yaws, flags, HZ, SCALE))
		T.truthy(path, "decode retornou nil")
		local p = path :: Path.PathData
		T.eq(p.n, 401)
		T.near(p.duration, 40, 1e-9)
		local tolerance = 0.5 / SCALE + 1e-4
		for i = 1, 401 do
			T.near(p.xs[i], xs[i], tolerance, "x[" .. i .. "]")
			T.near(p.ys[i], ys[i], tolerance, "y[" .. i .. "]")
			T.near(p.zs[i], zs[i], tolerance, "z[" .. i .. "]")
			T.eq(p.flags[i], flags[i], "flags[" .. i .. "]")
		end
	end)

	T.it("yaw quantizado em 256 passos", function()
		local xs, ys, zs, yaws, flags = makeSamples(50)
		local p = Path.decode(Path.encode(xs, ys, zs, yaws, flags, HZ, SCALE)) :: Path.PathData
		local step = math.pi * 2 / 256
		for i = 1, 50 do
			local diff = (p.yaws[i] - yaws[i] + math.pi) % (math.pi * 2) - math.pi
			T.truthy(math.abs(diff) <= step / 2 + 1e-9, "yaw[" .. i .. "] erro " .. diff)
		end
	end)

	T.it("sample interpola linearmente entre amostras", function()
		local xs, ys, zs = { 0, 10, 10 }, { 3, 3, 13 }, { 0, 0, 20 }
		local p = Path.decode(Path.encode(xs, ys, zs, { 0, 0, 0 }, { 0, 1, 0 }, HZ, SCALE)) :: Path.PathData
		local x, y, z = Path.sample(p, 0.05) -- metade entre a 1ª e a 2ª amostra
		T.near(x, 5, 1e-6)
		T.near(y, 3, 1e-6)
		T.near(z, 0, 1e-6)
		x, y, z = Path.sample(p, 0.15)
		T.near(x, 10, 1e-6)
		T.near(y, 8, 1e-6)
		T.near(z, 10, 1e-6)
		local _, _, _, _, f = Path.sample(p, 0.12)
		T.eq(f, 1, "flag da amostra anterior")
	end)

	T.it("sample prende nas pontas", function()
		local p = Path.decode(Path.encode({ 1, 2 }, { 3, 3 }, { 4, 5 }, { 0, 0 }, { 0, 0 }, HZ, SCALE)) :: Path.PathData
		local x = Path.sample(p, -1)
		T.near(x, 1, 1e-6)
		x = Path.sample(p, 99)
		T.near(x, 2, 1e-6)
	end)

	T.it("yaw interpola pelo caminho mais curto (atravessando ±pi)", function()
		local p = Path.decode(
			Path.encode({ 0, 0 }, { 0, 0 }, { 0, 0 }, { math.pi - 0.1, -math.pi + 0.1 }, { 0, 0 }, HZ, SCALE)
		) :: Path.PathData
		local _, _, _, yaw = Path.sample(p, 0.05)
		local wrapped = (yaw + math.pi) % (math.pi * 2) - math.pi
		T.truthy(math.abs(math.abs(wrapped) - math.pi) < 0.05, "esperado ~±pi, veio " .. wrapped)
	end)

	T.it("phase faz loop e aceita tempo negativo", function()
		local p = { duration = 20 } :: any
		T.near(Path.phase(p, 25), 5, 1e-9)
		T.near(Path.phase(p, 40), 0, 1e-9)
		T.near(Path.phase(p, -1), 19, 1e-9)
		T.eq(Path.phase({ duration = 0 } :: any, 5), 0)
	end)

	T.it("decode rejeita buffers inválidos", function()
		T.falsy(Path.decode("texto"))
		T.falsy(Path.decode(buffer.create(5)))
		local good = Path.encode({ 1, 2 }, { 1, 2 }, { 1, 2 }, { 0, 0 }, { 0, 0 }, HZ, SCALE)
		local truncated = buffer.create(buffer.len(good) - 1)
		buffer.copy(truncated, 0, good, 0, buffer.len(truncated))
		T.falsy(Path.decode(truncated), "tamanho errado")
		local wrongVersion = buffer.create(buffer.len(good))
		buffer.copy(wrongVersion, 0, good)
		buffer.writeu8(wrongVersion, 0, 99)
		T.falsy(Path.decode(wrongVersion), "versão errada")
		local nan = buffer.create(buffer.len(good))
		buffer.copy(nan, 0, good)
		buffer.writef32(nan, 8, 0 / 0)
		T.falsy(Path.decode(nan), "origem NaN")
	end)

	T.it("anti-teleporte: passo normal ok, salto absurdo inválido", function()
		local dt = 1 / HZ
		T.truthy(Path.isStepValid(0, 3, 0, 1.6, 3, 0, dt, 16 + 26, 230, 1.5, 1), "corrida a 16 studs/s")
		T.falsy(Path.isStepValid(0, 3, 0, 50, 3, 0, dt, 16 + 26, 230, 1.5, 1), "50 studs em 0,1 s")
		T.falsy(Path.isStepValid(0, 3, 0, 0, 80, 0, dt, 16 + 26, 230, 1.5, 1), "subiu 77 studs em 0,1 s")
		local xs, ys, zs = { 0, 1, 2, 60, 61 }, { 3, 3, 3, 3, 3 }, { 0, 0, 0, 0, 0 }
		T.eq(Path.findTeleport(xs, ys, zs, dt, 42, 230, 1.5, 1), 4)
		T.eq(Path.findTeleport({ 0, 1, 2 }, { 3, 3, 3 }, { 0, 0, 0 }, dt, 42, 230, 1.5, 1), nil)
	end)

	T.it("distância ponto-segmento", function()
		T.near(Path.segmentDistanceSq(0, 0, 0, 10, 0, 0, 5, 3, 0), 9, 1e-9)
		T.near(Path.segmentDistanceSq(0, 0, 0, 10, 0, 0, -2, 0, 0), 4, 1e-9)
		T.near(Path.segmentDistanceSq(0, 0, 0, 10, 0, 0, 12, 0, 0), 4, 1e-9)
		T.near(Path.segmentDistanceSq(1, 1, 1, 1, 1, 1, 1, 4, 1), 9, 1e-9) -- segmento degenerado
	end)

	T.it("deltas maiores que int16 são limitados sem corromper o resto", function()
		local p = Path.decode(
			Path.encode({ 0, 5000, 5001 }, { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, HZ, SCALE)
		) :: Path.PathData
		T.near(p.xs[2], 32767 / SCALE, 1e-6)
		T.truthy(p.xs[3] > p.xs[2], "continua avançando")
	end)
end)

return nil
