-- v2: layout dos plots, transformações de caminho (fitas da Pista), dia/noite, bases e cofre.
local T = require("./lib/T")
local Config = require("../src/shared/Config")
local DayNight = require("../src/shared/DayNight")
local MapLayout = require("../src/shared/MapLayout")
local Path = require("../src/shared/Path")
local SpatialHash = require("../src/shared/SpatialHash")

T.describe("MapLayout", function()
	T.it("8 plots no anel, olhando para o centro", function()
		T.eq(MapLayout.plotCount(), 8)
		for i = 1, 8 do
			local x, z, yaw = MapLayout.plot(i)
			T.near(math.sqrt(x * x + z * z), Config.Map.PlotRadius, 1e-6, "raio do plot " .. i)
			-- LookVector de CFrame.Angles(0, yaw, 0) = (-sin, 0, -cos) deve apontar para a origem
			local lx, lz = -math.sin(yaw), -math.cos(yaw)
			local dot = (lx * -x + lz * -z) / math.sqrt(x * x + z * z)
			T.near(dot, 1, 1e-6, "plot " .. i .. " olhando para o centro")
		end
	end)

	T.it("o portão fica do lado da cidade", function()
		for i = 1, 8 do
			local gx, gz = MapLayout.point(i, "Gate")
			T.near(math.sqrt(gx * gx + gz * gz), Config.Map.PlotRadius - 35, 1e-6)
		end
	end)

	T.it("toWorld e toLocal são inversos", function()
		for i = 1, 8 do
			for _, p in { { 0, 0 }, { 10, -20 }, { -33, 31 }, { 25, 25 } } do
				local wx, wz = MapLayout.toWorld(i, p[1], p[2])
				local lx, lz = MapLayout.toLocal(i, wx, wz)
				T.near(lx, p[1], 1e-6)
				T.near(lz, p[2], 1e-6)
			end
		end
	end)

	T.it("plotAt encontra o plot certo e nada na cidade", function()
		for i = 1, 8 do
			local wx, wz = MapLayout.toWorld(i, 12, -7)
			T.eq(MapLayout.plotAt(wx, wz), i)
		end
		T.eq(MapLayout.plotAt(0, 0), nil)
		T.truthy(MapLayout.inCity(0, 0))
		T.falsy(MapLayout.inCity(200, 0))
	end)

	T.it("plots não se sobrepõem e não invadem a cidade + rua", function()
		local ring = Config.Map.CityHalf + Config.Map.RingRoadWidth
		for i = 1, 8 do
			for _, corner in { { -35, -35 }, { 35, -35 }, { -35, 35 }, { 35, 35 } } do
				local wx, wz = MapLayout.toWorld(i, corner[1], corner[2])
				T.truthy(math.max(math.abs(wx), math.abs(wz)) > ring, "plot " .. i .. " invade a rua")
				T.truthy(math.max(math.abs(wx), math.abs(wz)) < Config.Map.GroundHalf, "plot " .. i .. " sai do chão")
				for j = 1, 8 do
					if j ~= i then
						T.eq(MapLayout.plotAt(wx * 0.999, wz * 0.999) ~= j, true, "plot " .. i .. " encosta no " .. j)
					end
				end
			end
		end
	end)

	T.it("30 vagas da estante distintas e dentro do plot", function()
		local seen = {}
		for k = 1, 30 do
			local x, y, z = MapLayout.shelfSlot(k)
			local key = string.format("%.1f:%.1f", y, z)
			T.falsy(seen[key], "vaga repetida " .. k)
			seen[key] = true
			T.truthy(math.abs(x) <= 35 and math.abs(z) <= 35, "vaga fora do plot")
		end
	end)
end)

T.describe("Path v2", function()
	T.it("mapXZ leva uma fita da Pista de um plot para outro sem distorcer", function()
		local xs, ys, zs, yaws, flags = {}, {}, {}, {}, {}
		for i = 1, 101 do
			local t = (i - 1) / 10
			xs[i], ys[i], zs[i] = -12 + t * 2, 3.6, 8 + math.sin(t) * 5
			yaws[i], flags[i] = 0.3, 0
		end
		local localBuf = Path.encode(xs, ys, zs, yaws, flags, 10, 20)
		local function toWorld(index)
			local _, _, yaw = MapLayout.plot(index)
			return function(x, z, rot)
				local wx, wz = MapLayout.toWorld(index, x, z)
				return wx, wz, rot + yaw
			end
		end
		local function toLocal(index)
			local _, _, yaw = MapLayout.plot(index)
			return function(x, z, rot)
				local lx, lz = MapLayout.toLocal(index, x, z)
				return lx, lz, rot - yaw
			end
		end
		-- grava no plot 3 (mundo), salva em local, roda no plot 7
		local worldIn3 = Path.mapXZ(localBuf, toWorld(3)) :: buffer
		local backToLocal = Path.mapXZ(worldIn3, toLocal(3)) :: buffer
		local worldIn7 = Path.decode(Path.mapXZ(backToLocal, toWorld(7)) :: buffer) :: Path.PathData
		for i = 1, 101, 10 do
			local lx, lz = MapLayout.toLocal(7, worldIn7.xs[i], worldIn7.zs[i])
			T.near(lx, xs[i], 0.1, "x local")
			T.near(lz, zs[i], 0.1, "z local")
			T.near(worldIn7.ys[i], 3.6, 0.05, "y")
		end
		T.eq(worldIn7.duration, 10)
	end)

	T.it("preview devolve pares x,z", function()
		local p = Path.decode(
			Path.encode({ 0, 1, 2, 3 }, { 0, 0, 0, 0 }, { 5, 6, 7, 8 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, 10, 20)
		) :: Path.PathData
		local points = Path.preview(p, 2)
		T.eq(#points % 2, 0)
		T.near(points[1], 0, 1e-6)
		T.near(points[2], 5, 1e-6)
	end)
end)

T.describe("SpatialHash v2", function()
	T.it("remove tira o item da célula", function()
		local hash = SpatialHash.new(8)
		hash:insert("a", 1, 1)
		hash:insert("b", 2, 2)
		T.truthy(hash:remove("a", 1, 1))
		T.falsy(hash:remove("a", 1, 1))
		local found = {}
		hash:queryRect(0, 0, 4, 4, function(item)
			found[item] = true
		end)
		T.falsy(found.a)
		T.truthy(found.b)
	end)
end)

T.describe("DayNight", function()
	T.it("ciclo de 12 min: começa às 6h, meio-dia no meio do dia, noite no fim", function()
		local cycle, day = 720, 2 / 3
		T.near(DayNight.clockTime(0, cycle, day), 6, 1e-6)
		T.near(DayNight.clockTime(cycle * day / 2, cycle, day), 12, 1e-6)
		T.near(DayNight.clockTime(cycle * day, cycle, day), 18, 1e-6)
		T.near(DayNight.clockTime(cycle * (day + (1 - day) / 2), cycle, day), 0, 1e-6)
		T.near(DayNight.clockTime(cycle * 5 + 1, cycle, day), DayNight.clockTime(1, cycle, day), 1e-6)
	end)

	T.it("noite e transições", function()
		T.falsy(DayNight.isNight(12))
		T.truthy(DayNight.isNight(23))
		T.truthy(DayNight.isNight(3))
		T.eq(DayNight.nightAmount(12), 0)
		T.eq(DayNight.nightAmount(23), 1)
		local dusk = DayNight.nightAmount(18)
		T.truthy(dusk > 0 and dusk < 1, "entardecer suave")
	end)
end)

T.describe("Config v2", function()
	T.it("níveis da base crescem em preço, vagas e cofre", function()
		T.eq(#Config.BaseLevels, 6)
		T.eq(Config.BaseLevels[1].Price, 0)
		T.eq(Config.BaseLevels[1].Slots, 3)
		for level = 2, 6 do
			local a, b = Config.BaseLevels[level - 1], Config.BaseLevels[level]
			T.truthy(b.Price > a.Price, "preço nível " .. level)
			T.truthy(b.Slots > a.Slots, "vagas nível " .. level)
			T.truthy(b.VaultCapacity > a.VaultCapacity, "cofre nível " .. level)
		end
		-- incrementos do prompt: +2, +3, +3, +4, +5
		local expected = { 3, 5, 8, 11, 15, 20 }
		for level, slots in expected do
			T.eq(Config.BaseLevels[level].Slots, slots)
		end
	end)

	T.it("vagas máximas cabem na estante (30)", function()
		T.truthy(Config.BaseLevels[6].Slots + Config.ExtraSlotsAmount <= Config.MaxClonesPerPlayer)
		T.eq(Config.MaxClonesPerPlayer, 30)
	end)

	T.it("produtos InstantBaseLevel apontam para níveis existentes e sobem de preço", function()
		local last = 0
		for level = 2, 6 do
			local info = Config.Products["InstantBaseLevel" .. level]
			T.truthy(info, "falta InstantBaseLevel" .. level)
			T.eq(info.Level, level)
			T.truthy(info.Price > last, "preço em escala")
			last = info.Price
		end
	end)

	T.it("um item MAIS POPULAR por aba de Robux", function()
		local passes, products = 0, 0
		for _, info in Config.GamePasses do
			if info.Popular then
				passes += 1
			end
		end
		for _, key in Config.ShopProducts do
			if Config.Products[key].Popular then
				products += 1
			end
		end
		T.eq(passes, 1)
		T.eq(products, 1)
	end)

	T.it("volumes padrão do prompt e opções de qualidade", function()
		T.near(Config.DefaultSettings.Music, 0.35, 1e-9)
		T.near(Config.DefaultSettings.Sfx, 0.6, 1e-9)
		T.truthy(table.find(Config.CloneQualityOptions, Config.DefaultSettings.CloneQuality) ~= nil)
	end)

	T.it("tempos de roubo/defesa do prompt", function()
		T.eq(Config.Lock.Seconds, 60)
		T.eq(Config.Lock.Cooldown, 60)
		T.eq(Config.Lock.NewbieProtection, 600)
		T.near(Config.Vault.StealFraction, 0.25, 1e-9)
		T.eq(Config.Vault.StealCooldown, 120)
		T.eq(Config.Theft.BaseCooldown, 180)
		T.near(Config.Theft.CarrySpeedMultiplier, 0.7, 1e-9)
		T.eq(Config.DefenseLaser.IdleSeconds, 3)
	end)
end)

return nil
