-- v2: layout dos plots, transformações de caminho (fitas da Pista), dia/noite, bases e cofre.
local load = require(if script then script.Parent.lib.load else "./lib/load")
local Config = load("Config")
local DayNight = load("DayNight")
local MapLayout = load("MapLayout")
local Path = load("Path")
local SpatialHash = load("SpatialHash")

return function()
	describe("MapLayout", function()
		it("8 plots no anel, olhando para o centro", function()
			expect(MapLayout.plotCount()).to.equal(8)
			for i = 1, 8 do
				local x, z, yaw = MapLayout.plot(i)
				expect(math.sqrt(x * x + z * z)).to.be.near(Config.Map.PlotRadius, 1e-6)
				-- LookVector de CFrame.Angles(0, yaw, 0) = (-sin, 0, -cos) deve apontar para a origem
				local lx, lz = -math.sin(yaw), -math.cos(yaw)
				local dot = (lx * -x + lz * -z) / math.sqrt(x * x + z * z)
				expect(dot).to.be.near(1, 1e-6)
			end
		end)

		it("o portão fica do lado da cidade", function()
			for i = 1, 8 do
				local gx, gz = MapLayout.point(i, "Gate")
				expect(math.sqrt(gx * gx + gz * gz)).to.be.near(Config.Map.PlotRadius - 35, 1e-6)
			end
		end)

		it("toWorld e toLocal são inversos", function()
			for i = 1, 8 do
				for _, p in { { 0, 0 }, { 10, -20 }, { -33, 31 }, { 25, 25 } } do
					local wx, wz = MapLayout.toWorld(i, p[1], p[2])
					local lx, lz = MapLayout.toLocal(i, wx, wz)
					expect(lx).to.be.near(p[1], 1e-6)
					expect(lz).to.be.near(p[2], 1e-6)
				end
			end
		end)

		it("plotAt encontra o plot certo e nada na cidade", function()
			for i = 1, 8 do
				local wx, wz = MapLayout.toWorld(i, 12, -7)
				expect(MapLayout.plotAt(wx, wz)).to.equal(i)
			end
			expect(MapLayout.plotAt(0, 0)).never.to.be.ok()
			expect(MapLayout.inCity(0, 0)).to.equal(true)
			expect(MapLayout.inCity(200, 0)).to.equal(false)
		end)

		it("plots não se sobrepõem e não invadem a cidade + rua", function()
			local ring = Config.Map.CityHalf + Config.Map.RingRoadWidth
			local problems = {}
			for i = 1, 8 do
				for _, corner in { { -35, -35 }, { 35, -35 }, { -35, 35 }, { 35, 35 } } do
					local wx, wz = MapLayout.toWorld(i, corner[1], corner[2])
					local reach = math.max(math.abs(wx), math.abs(wz))
					if reach <= ring then
						table.insert(problems, "plot " .. i .. " invade a rua")
					end
					if reach >= Config.Map.GroundHalf then
						table.insert(problems, "plot " .. i .. " sai do chão")
					end
					local other = MapLayout.plotAt(wx * 0.999, wz * 0.999)
					if other and other ~= i then
						table.insert(problems, "plot " .. i .. " encosta no " .. other)
					end
				end
			end
			expect(table.concat(problems, ", ")).to.equal("")
		end)

		it("30 vagas da estante distintas e dentro do plot", function()
			local seen = {}
			for k = 1, 30 do
				local x, y, z = MapLayout.shelfSlot(k)
				local key = string.format("%.1f:%.1f", y, z)
				expect(seen[key]).never.to.be.ok() -- vaga repetida
				seen[key] = k
				expect(math.abs(x) <= 35 and math.abs(z) <= 35).to.equal(true) -- vaga fora do plot
			end
		end)
	end)

	describe("Path v2", function()
		it("mapXZ leva uma fita da Pista de um plot para outro sem distorcer", function()
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
			local worldIn3 = Path.mapXZ(localBuf, toWorld(3))
			local backToLocal = Path.mapXZ(worldIn3, toLocal(3))
			local worldIn7 = Path.decode(Path.mapXZ(backToLocal, toWorld(7)))
			for i = 1, 101, 10 do
				local lx, lz = MapLayout.toLocal(7, worldIn7.xs[i], worldIn7.zs[i])
				expect(lx).to.be.near(xs[i], 0.1)
				expect(lz).to.be.near(zs[i], 0.1)
				expect(worldIn7.ys[i]).to.be.near(3.6, 0.05)
			end
			expect(worldIn7.duration).to.equal(10)
		end)

		it("preview devolve pares x,z", function()
			local p = Path.decode(
				Path.encode({ 0, 1, 2, 3 }, { 0, 0, 0, 0 }, { 5, 6, 7, 8 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, 10, 20)
			)
			local points = Path.preview(p, 2)
			expect(#points % 2).to.equal(0)
			expect(points[1]).to.be.near(0, 1e-6)
			expect(points[2]).to.be.near(5, 1e-6)
		end)
	end)

	describe("SpatialHash v2", function()
		it("remove tira o item da célula", function()
			local hash = SpatialHash.new(8)
			hash:insert("a", 1, 1)
			hash:insert("b", 2, 2)
			expect(hash:remove("a", 1, 1)).to.equal(true)
			expect(hash:remove("a", 1, 1)).to.equal(false)
			local found = {}
			hash:queryRect(0, 0, 4, 4, function(item)
				found[item] = true
			end)
			expect(found.a).never.to.be.ok()
			expect(found.b).to.equal(true)
		end)
	end)

	describe("DayNight", function()
		it("ciclo de 12 min: começa às 6h, meio-dia no meio do dia, noite no fim", function()
			local cycle, day = 720, 2 / 3
			expect(DayNight.clockTime(0, cycle, day)).to.be.near(6, 1e-6)
			expect(DayNight.clockTime(cycle * day / 2, cycle, day)).to.be.near(12, 1e-6)
			expect(DayNight.clockTime(cycle * day, cycle, day)).to.be.near(18, 1e-6)
			expect(DayNight.clockTime(cycle * (day + (1 - day) / 2), cycle, day)).to.be.near(0, 1e-6)
			expect(DayNight.clockTime(cycle * 5 + 1, cycle, day)).to.be.near(DayNight.clockTime(1, cycle, day), 1e-6)
		end)

		it("noite e transições", function()
			expect(DayNight.isNight(12)).to.equal(false)
			expect(DayNight.isNight(23)).to.equal(true)
			expect(DayNight.isNight(3)).to.equal(true)
			expect(DayNight.nightAmount(12)).to.equal(0)
			expect(DayNight.nightAmount(23)).to.equal(1)
			local dusk = DayNight.nightAmount(18)
			expect(dusk > 0 and dusk < 1).to.equal(true) -- entardecer suave
		end)
	end)

	describe("Config v2", function()
		it("níveis da base crescem em preço, vagas e cofre", function()
			expect(#Config.BaseLevels).to.equal(6)
			expect(Config.BaseLevels[1].Price).to.equal(0)
			expect(Config.BaseLevels[1].Slots).to.equal(3)
			local problems = {}
			for level = 2, 6 do
				local a, b = Config.BaseLevels[level - 1], Config.BaseLevels[level]
				if b.Price <= a.Price then
					table.insert(problems, "preço nível " .. level)
				end
				if b.Slots <= a.Slots then
					table.insert(problems, "vagas nível " .. level)
				end
				if b.VaultCapacity <= a.VaultCapacity then
					table.insert(problems, "cofre nível " .. level)
				end
			end
			expect(table.concat(problems, ", ")).to.equal("")
			-- incrementos do prompt: +2, +3, +3, +4, +5
			for level, slots in { 3, 5, 8, 11, 15, 20 } do
				expect(Config.BaseLevels[level].Slots).to.equal(slots)
			end
		end)

		it("vagas máximas cabem na estante (30)", function()
			expect(Config.BaseLevels[6].Slots + Config.ExtraSlotsAmount <= Config.MaxClonesPerPlayer).to.equal(true)
			expect(Config.MaxClonesPerPlayer).to.equal(30)
		end)

		it("produtos InstantBaseLevel apontam para níveis existentes e sobem de preço", function()
			local last = 0
			for level = 2, 6 do
				local info = Config.Products["InstantBaseLevel" .. level]
				expect(info).to.be.ok()
				expect(info.Level).to.equal(level)
				expect(info.Price > last).to.equal(true) -- preço em escala
				last = info.Price
			end
		end)

		it("um item MAIS POPULAR por aba de Robux", function()
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
			expect(passes).to.equal(1)
			expect(products).to.equal(1)
		end)

		it("volumes padrão do prompt e opções de qualidade", function()
			expect(Config.DefaultSettings.Music).to.be.near(0.35, 1e-9)
			expect(Config.DefaultSettings.Sfx).to.be.near(0.6, 1e-9)
			expect(table.find(Config.CloneQualityOptions, Config.DefaultSettings.CloneQuality)).to.be.ok()
		end)

		it("tempos de roubo/defesa do prompt", function()
			expect(Config.Lock.Seconds).to.equal(60)
			expect(Config.Lock.Cooldown).to.equal(60)
			expect(Config.Lock.NewbieProtection).to.equal(600)
			expect(Config.Vault.StealFraction).to.be.near(0.25, 1e-9)
			expect(Config.Vault.StealCooldown).to.equal(120)
			expect(Config.Theft.BaseCooldown).to.equal(180)
			expect(Config.Theft.CarrySpeedMultiplier).to.be.near(0.7, 1e-9)
			expect(Config.DefenseLaser.IdleSeconds).to.equal(3)
		end)
	end)
end
