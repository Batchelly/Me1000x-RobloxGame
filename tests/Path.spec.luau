-- Compressão de caminho e interpolação.
local load = require(if script then script.Parent.lib.load else "./lib/load")
local Path = load("Path")

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

return function()
	describe("Path", function()
		it("tamanho do buffer = cabeçalho + 8 bytes por amostra", function()
			local xs, ys, zs, yaws, flags = makeSamples(401)
			local buf = Path.encode(xs, ys, zs, yaws, flags, HZ, SCALE)
			expect(buffer.len(buf)).to.equal(Path.HEADER_SIZE + 401 * Path.SAMPLE_SIZE)
			expect(buffer.len(buf)).to.equal(3228) -- gravação de 40 s
		end)

		it("ida e volta preserva posições dentro de 0,5/scale (sem erro acumulado)", function()
			local xs, ys, zs, yaws, flags = makeSamples(401)
			local p = Path.decode(Path.encode(xs, ys, zs, yaws, flags, HZ, SCALE))
			expect(p).to.be.ok()
			expect(p.n).to.equal(401)
			expect(p.duration).to.be.near(40, 1e-9)
			local tolerance = 0.5 / SCALE + 1e-4
			for i = 1, 401 do
				expect(p.xs[i]).to.be.near(xs[i], tolerance)
				expect(p.ys[i]).to.be.near(ys[i], tolerance)
				expect(p.zs[i]).to.be.near(zs[i], tolerance)
				expect(p.flags[i]).to.equal(flags[i])
			end
		end)

		it("yaw quantizado em 256 passos", function()
			local xs, ys, zs, yaws, flags = makeSamples(50)
			local p = Path.decode(Path.encode(xs, ys, zs, yaws, flags, HZ, SCALE))
			local step = math.pi * 2 / 256
			for i = 1, 50 do
				local diff = (p.yaws[i] - yaws[i] + math.pi) % (math.pi * 2) - math.pi
				expect(diff).to.be.near(0, step / 2 + 1e-9)
			end
		end)

		it("sample interpola linearmente entre amostras", function()
			local xs, ys, zs = { 0, 10, 10 }, { 3, 3, 13 }, { 0, 0, 20 }
			local p = Path.decode(Path.encode(xs, ys, zs, { 0, 0, 0 }, { 0, 1, 0 }, HZ, SCALE))
			local x, y, z = Path.sample(p, 0.05) -- metade entre a 1ª e a 2ª amostra
			expect(x).to.be.near(5, 1e-6)
			expect(y).to.be.near(3, 1e-6)
			expect(z).to.be.near(0, 1e-6)
			x, y, z = Path.sample(p, 0.15)
			expect(x).to.be.near(10, 1e-6)
			expect(y).to.be.near(8, 1e-6)
			expect(z).to.be.near(10, 1e-6)
			local _, _, _, _, f = Path.sample(p, 0.12)
			expect(f).to.equal(1) -- flag da amostra anterior
		end)

		it("sample prende nas pontas", function()
			local p = Path.decode(Path.encode({ 1, 2 }, { 3, 3 }, { 4, 5 }, { 0, 0 }, { 0, 0 }, HZ, SCALE))
			expect(Path.sample(p, -1)).to.be.near(1, 1e-6)
			expect(Path.sample(p, 99)).to.be.near(2, 1e-6)
		end)

		it("yaw interpola pelo caminho mais curto (atravessando ±pi)", function()
			local p = Path.decode(
				Path.encode({ 0, 0 }, { 0, 0 }, { 0, 0 }, { math.pi - 0.1, -math.pi + 0.1 }, { 0, 0 }, HZ, SCALE)
			)
			local _, _, _, yaw = Path.sample(p, 0.05)
			local wrapped = (yaw + math.pi) % (math.pi * 2) - math.pi
			expect(math.abs(wrapped)).to.be.near(math.pi, 0.05)
		end)

		it("phase faz loop e aceita tempo negativo", function()
			local p = { duration = 20 } :: any
			expect(Path.phase(p, 25)).to.be.near(5, 1e-9)
			expect(Path.phase(p, 40)).to.be.near(0, 1e-9)
			expect(Path.phase(p, -1)).to.be.near(19, 1e-9)
			expect(Path.phase({ duration = 0 } :: any, 5)).to.equal(0)
		end)

		it("decode rejeita buffers inválidos", function()
			expect(Path.decode("texto")).never.to.be.ok()
			expect(Path.decode(buffer.create(5))).never.to.be.ok()
			local good = Path.encode({ 1, 2 }, { 1, 2 }, { 1, 2 }, { 0, 0 }, { 0, 0 }, HZ, SCALE)

			local truncated = buffer.create(buffer.len(good) - 1)
			buffer.copy(truncated, 0, good, 0, buffer.len(truncated))
			expect(Path.decode(truncated)).never.to.be.ok() -- tamanho errado

			local wrongVersion = buffer.create(buffer.len(good))
			buffer.copy(wrongVersion, 0, good)
			buffer.writeu8(wrongVersion, 0, 99)
			expect(Path.decode(wrongVersion)).never.to.be.ok() -- versão errada

			local nan = buffer.create(buffer.len(good))
			buffer.copy(nan, 0, good)
			buffer.writef32(nan, 8, 0 / 0)
			expect(Path.decode(nan)).never.to.be.ok() -- origem NaN
		end)

		it("anti-teleporte: passo normal ok, salto absurdo inválido", function()
			local dt = 1 / HZ
			-- corrida a 16 studs/s
			expect(Path.isStepValid(0, 3, 0, 1.6, 3, 0, dt, 16 + 26, 230, 1.5, 1)).to.equal(true)
			-- 50 studs em 0,1 s
			expect(Path.isStepValid(0, 3, 0, 50, 3, 0, dt, 16 + 26, 230, 1.5, 1)).to.equal(false)
			-- subiu 77 studs em 0,1 s
			expect(Path.isStepValid(0, 3, 0, 0, 80, 0, dt, 16 + 26, 230, 1.5, 1)).to.equal(false)
			local xs, ys, zs = { 0, 1, 2, 60, 61 }, { 3, 3, 3, 3, 3 }, { 0, 0, 0, 0, 0 }
			expect(Path.findTeleport(xs, ys, zs, dt, 42, 230, 1.5, 1)).to.equal(4)
			expect(Path.findTeleport({ 0, 1, 2 }, { 3, 3, 3 }, { 0, 0, 0 }, dt, 42, 230, 1.5, 1)).never.to.be.ok()
		end)

		it("distância ponto-segmento", function()
			expect(Path.segmentDistanceSq(0, 0, 0, 10, 0, 0, 5, 3, 0)).to.be.near(9, 1e-9)
			expect(Path.segmentDistanceSq(0, 0, 0, 10, 0, 0, -2, 0, 0)).to.be.near(4, 1e-9)
			expect(Path.segmentDistanceSq(0, 0, 0, 10, 0, 0, 12, 0, 0)).to.be.near(4, 1e-9)
			expect(Path.segmentDistanceSq(1, 1, 1, 1, 1, 1, 1, 4, 1)).to.be.near(9, 1e-9) -- segmento degenerado
		end)

		it("deltas maiores que int16 são limitados sem corromper o resto", function()
			local p = Path.decode(
				Path.encode({ 0, 5000, 5001 }, { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, HZ, SCALE)
			)
			expect(p.xs[2]).to.be.near(32767 / SCALE, 1e-6)
			expect(p.xs[3] > p.xs[2]).to.equal(true) -- continua avançando
		end)
	end)
end
