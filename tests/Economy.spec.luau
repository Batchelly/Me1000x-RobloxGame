-- Cálculos de economia e consistência do Config.
local load = require(if script then script.Parent.lib.load else "./lib/load")
local Config = load("Config")
local EconomyMath = load("EconomyMath")
local Strings = load("Strings")

return function()
	describe("EconomyMath", function()
		it("multiplicador = 1 + rebirths * 0,5, x2 com DoubleCash", function()
			expect(EconomyMath.multiplier(0, 0.5, false, 2)).to.be.near(1, 1e-9)
			expect(EconomyMath.multiplier(3, 0.5, false, 2)).to.be.near(2.5, 1e-9)
			expect(EconomyMath.multiplier(3, 0.5, true, 2)).to.be.near(5, 1e-9)
		end)

		it("award arredonda e nunca dá 0 para base > 0", function()
			expect(EconomyMath.award(1, 1, 1)).to.equal(1)
			expect(EconomyMath.award(1, 1.5, 1)).to.equal(2)
			expect(EconomyMath.award(1, 1.4, 1)).to.equal(1)
			expect(EconomyMath.award(10, 2.5, 3)).to.equal(75) -- gema, rebirth 3, clone dourado
			expect(EconomyMath.award(1, 0.1, 1)).to.equal(1)
			expect(EconomyMath.award(0, 5, 1)).to.equal(0)
		end)

		it("slots: base + rebirths + comprados + passe, com teto", function()
			expect(EconomyMath.totalSlots(3, 0, 1, 0, 0, 30)).to.equal(3)
			expect(EconomyMath.totalSlots(3, 2, 1, 4, 5, 30)).to.equal(14)
			expect(EconomyMath.totalSlots(3, 20, 1, 20, 5, 30)).to.equal(30)
		end)

		it("tempo de gravação e velocidade", function()
			expect(EconomyMath.recordSeconds(20, 0, 2)).to.equal(20)
			expect(EconomyMath.recordSeconds(40, 5, 2)).to.equal(50)
			expect(EconomyMath.walkSpeed(16, 5, 2)).to.equal(26)
		end)

		it("renda offline: 50% de eficiência e teto de horas", function()
			-- 100/min por 60 min a 50% = 3000
			expect(EconomyMath.offlineEarnings(100, 3600, 8, 0.5)).to.equal(3000)
			-- 30 h fora com teto de 8 h = 480 min
			expect(EconomyMath.offlineEarnings(100, 30 * 3600, 8, 0.5)).to.equal(24000)
			-- com OfflinePlus (24 h)
			expect(EconomyMath.offlineEarnings(100, 30 * 3600, 24, 0.5)).to.equal(72000)
			expect(EconomyMath.offlineEarnings(0, 3600, 8, 0.5)).to.equal(0)
			expect(EconomyMath.offlineEarnings(100, -5, 8, 0.5)).to.equal(0)
		end)

		it("média de ganho por minuto", function()
			expect(EconomyMath.averageRate({})).to.equal(0)
			expect(EconomyMath.averageRate({ 10, 20, 30 })).to.be.near(20, 1e-9)
		end)

		describe("recompensa diária", function()
			it("primeira vez é o dia 1", function()
				local available, day = EconomyMath.dailyNext(0, 0, 100, 7)
				expect(available).to.equal(true)
				expect(day).to.equal(1)
			end)

			it("dia seguinte continua a sequência", function()
				local available, day = EconomyMath.dailyNext(99, 3, 100, 7)
				expect(available).to.equal(true)
				expect(day).to.equal(4)
			end)

			it("perdeu um dia: reseta", function()
				local available, day = EconomyMath.dailyNext(97, 3, 100, 7)
				expect(available).to.equal(true)
				expect(day).to.equal(1)
			end)

			it("já resgatou hoje", function()
				local available, day = EconomyMath.dailyNext(100, 4, 100, 7)
				expect(available).to.equal(false)
				expect(day).to.equal(4)
			end)

			it("depois do dia 7 volta ao 1", function()
				local available, day = EconomyMath.dailyNext(99, 7, 100, 7)
				expect(available).to.equal(true)
				expect(day).to.equal(1)
			end)
		end)

		it("pacote de Cash proporcional ao próximo rebirth", function()
			expect(EconomyMath.cashPack(0, 0.1, Config.RebirthCost)).to.equal(math.floor(Config.RebirthCost(0) * 0.1))
			expect(EconomyMath.cashPack(2, 1, Config.RebirthCost)).to.equal(Config.RebirthCost(2))
			expect(EconomyMath.cashPack(0, 0.00001, Config.RebirthCost)).to.equal(100) -- mínimo 100
		end)
	end)

	describe("Config", function()
		it("custos de rebirth e upgrades crescem", function()
			local problems = {}
			for n = 0, 20 do
				if Config.RebirthCost(n + 1) <= Config.RebirthCost(n) then
					table.insert(problems, "rebirth " .. n)
				end
			end
			for key, upgrade in Config.Upgrades do
				for level = 0, upgrade.MaxLevel - 1 do
					if upgrade.Price(level + 1) <= upgrade.Price(level) then
						table.insert(problems, key .. " nível " .. level .. " não cresce")
					end
					if upgrade.Price(level) <= 0 then
						table.insert(problems, key .. " nível " .. level .. " preço <= 0")
					end
				end
			end
			expect(table.concat(problems, ", ")).to.equal("")
		end)

		it("gravação máxima cabe em MaxSamples", function()
			local maxSeconds = Config.RecordSecondsWithPass + Config.RecordUpgradeMaxLevel * Config.RecordUpgradeStep
			expect(maxSeconds * Config.RecordHz + 1 <= Config.MaxSamples).to.equal(true)
		end)

		it("perfil cabe no limite de 4 MB com o máximo de clones", function()
			local maxSeconds = Config.RecordSecondsWithPass + Config.RecordUpgradeMaxLevel * Config.RecordUpgradeStep
			local bytes = 20 + (maxSeconds * Config.RecordHz + 1) * 8
			local base64 = math.ceil(bytes / 3) * 4
			-- gravações não podem passar de 25% do limite
			expect(base64 * Config.MaxClonesPerPlayer < Config.Data.MaxBytes / 4).to.equal(true)
		end)

		it("todos os IDs de monetização são números (0 = em breve)", function()
			local problems = {}
			for key, info in Config.GamePasses do
				if type(info.Id) ~= "number" then
					table.insert(problems, "passe " .. key .. " sem Id numérico")
				end
				if not (info.Price > 0) then
					table.insert(problems, "passe " .. key .. " sem preço")
				end
			end
			for key, info in Config.Products do
				if type(info.Id) ~= "number" then
					table.insert(problems, "produto " .. key .. " sem Id numérico")
				end
			end
			for _, key in Config.PassOrder do
				if not Config.GamePasses[key] then
					table.insert(problems, "PassOrder: " .. key)
				end
			end
			for _, key in Config.ShopProducts do
				if not Config.Products[key] then
					table.insert(problems, "ShopProducts: " .. key)
				end
			end
			expect(table.concat(problems, ", ")).to.equal("")
		end)

		it("recompensas diárias crescem", function()
			expect(#Config.DailyRewards).to.equal(7)
			for day = 2, 7 do
				expect(Config.DailyRewards[day].Cash > Config.DailyRewards[day - 1].Cash).to.equal(true)
			end
		end)

		it("códigos estão em maiúsculas", function()
			for code in Config.Codes do
				expect(code).to.equal(string.upper(code))
			end
		end)

		it("existe texto PT e EN para cada passe, produto e upgrade", function()
			local missing = {}
			local function check(lang: string, key: string)
				if not Strings[lang][key] then
					table.insert(missing, lang .. "." .. key)
				end
			end
			for _, lang in { "pt", "en" } do
				for key in Config.GamePasses do
					check(lang, "pass_" .. key .. "_name")
					check(lang, "pass_" .. key .. "_desc")
				end
				for key in Config.Products do
					check(lang, "product_" .. key .. "_name")
					check(lang, "product_" .. key .. "_desc")
				end
				for key in Config.Upgrades do
					check(lang, "upgrade_" .. key .. "_name")
				end
			end
			expect(table.concat(missing, ", ")).to.equal("")
		end)
	end)
end
