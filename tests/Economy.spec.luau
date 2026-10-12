-- Cálculos de economia e consistência do Config.
local T = require("./lib/T")
local Config = require("../src/shared/Config")
local EconomyMath = require("../src/shared/EconomyMath")
local Strings = require("../src/shared/Strings")

T.describe("EconomyMath", function()
	T.it("multiplicador = 1 + rebirths * 0,5, x2 com DoubleCash", function()
		T.near(EconomyMath.multiplier(0, 0.5, false, 2), 1, 1e-9)
		T.near(EconomyMath.multiplier(3, 0.5, false, 2), 2.5, 1e-9)
		T.near(EconomyMath.multiplier(3, 0.5, true, 2), 5, 1e-9)
	end)

	T.it("award arredonda e nunca dá 0 para base > 0", function()
		T.eq(EconomyMath.award(1, 1, 1), 1)
		T.eq(EconomyMath.award(1, 1.5, 1), 2)
		T.eq(EconomyMath.award(1, 1.4, 1), 1)
		T.eq(EconomyMath.award(10, 2.5, 3), 75) -- gema, rebirth 3, clone dourado
		T.eq(EconomyMath.award(1, 0.1, 1), 1)
		T.eq(EconomyMath.award(0, 5, 1), 0)
	end)

	T.it("slots: base + rebirths + comprados + passe, com teto", function()
		T.eq(EconomyMath.totalSlots(3, 0, 1, 0, 0, 30), 3)
		T.eq(EconomyMath.totalSlots(3, 2, 1, 4, 5, 30), 14)
		T.eq(EconomyMath.totalSlots(3, 20, 1, 20, 5, 30), 30)
	end)

	T.it("tempo de gravação e velocidade", function()
		T.eq(EconomyMath.recordSeconds(20, 0, 2), 20)
		T.eq(EconomyMath.recordSeconds(40, 5, 2), 50)
		T.eq(EconomyMath.walkSpeed(16, 5, 2), 26)
	end)

	T.it("renda offline: 50% de eficiência e teto de horas", function()
		-- 100/min por 60 min a 50% = 3000
		T.eq(EconomyMath.offlineEarnings(100, 3600, 8, 0.5), 3000)
		-- 30 h fora com teto de 8 h = 480 min
		T.eq(EconomyMath.offlineEarnings(100, 30 * 3600, 8, 0.5), 24000)
		-- com OfflinePlus (24 h)
		T.eq(EconomyMath.offlineEarnings(100, 30 * 3600, 24, 0.5), 72000)
		T.eq(EconomyMath.offlineEarnings(0, 3600, 8, 0.5), 0)
		T.eq(EconomyMath.offlineEarnings(100, -5, 8, 0.5), 0)
	end)

	T.it("média de ganho por minuto", function()
		T.eq(EconomyMath.averageRate({}), 0)
		T.near(EconomyMath.averageRate({ 10, 20, 30 }), 20, 1e-9)
	end)

	T.it("recompensa diária: sequência, reset e volta ao dia 1 depois do 7", function()
		local available, day = EconomyMath.dailyNext(0, 0, 100, 7)
		T.truthy(available)
		T.eq(day, 1, "primeira vez")
		available, day = EconomyMath.dailyNext(99, 3, 100, 7)
		T.truthy(available)
		T.eq(day, 4, "dia seguinte continua")
		available, day = EconomyMath.dailyNext(97, 3, 100, 7)
		T.truthy(available)
		T.eq(day, 1, "perdeu um dia: reseta")
		available, day = EconomyMath.dailyNext(100, 4, 100, 7)
		T.falsy(available, "já resgatou hoje")
		T.eq(day, 4)
		available, day = EconomyMath.dailyNext(99, 7, 100, 7)
		T.truthy(available)
		T.eq(day, 1, "depois do dia 7 volta ao 1")
	end)

	T.it("pacote de Cash proporcional ao próximo rebirth", function()
		T.eq(EconomyMath.cashPack(0, 0.1, Config.RebirthCost), math.floor(Config.RebirthCost(0) * 0.1))
		T.eq(EconomyMath.cashPack(2, 1, Config.RebirthCost), Config.RebirthCost(2))
		T.eq(EconomyMath.cashPack(0, 0.00001, Config.RebirthCost), 100, "mínimo 100")
	end)
end)

T.describe("Config", function()
	T.it("custos de rebirth e upgrades crescem", function()
		for n = 0, 20 do
			T.truthy(Config.RebirthCost(n + 1) > Config.RebirthCost(n), "rebirth " .. n)
		end
		for key, upgrade in Config.Upgrades do
			for level = 0, upgrade.MaxLevel - 1 do
				T.truthy(upgrade.Price(level + 1) > upgrade.Price(level), key .. " nível " .. level)
				T.truthy(upgrade.Price(level) > 0, key .. " preço positivo")
			end
		end
	end)

	T.it("gravação máxima cabe em MaxSamples", function()
		local maxSeconds = Config.RecordSecondsWithPass + Config.RecordUpgradeMaxLevel * Config.RecordUpgradeStep
		T.truthy(maxSeconds * Config.RecordHz + 1 <= Config.MaxSamples, "MaxSamples pequeno demais")
	end)

	T.it("perfil cabe no limite de 4 MB com o máximo de clones", function()
		local maxSeconds = Config.RecordSecondsWithPass + Config.RecordUpgradeMaxLevel * Config.RecordUpgradeStep
		local bytes = 20 + (maxSeconds * Config.RecordHz + 1) * 8
		local base64 = math.ceil(bytes / 3) * 4
		T.truthy(base64 * Config.MaxClonesPerPlayer < Config.Data.MaxBytes / 4, "gravações usam > 25% do limite")
	end)

	T.it("todos os IDs de monetização são números (0 = em breve)", function()
		for key, info in Config.GamePasses do
			T.eq(type(info.Id), "number", key)
			T.truthy(info.Price > 0, key .. " preço")
		end
		for key, info in Config.Products do
			T.eq(type(info.Id), "number", key)
		end
		for _, key in Config.PassOrder do
			T.truthy(Config.GamePasses[key], "PassOrder: " .. key)
		end
		for _, key in Config.ShopProducts do
			T.truthy(Config.Products[key], "ShopProducts: " .. key)
		end
	end)

	T.it("recompensas diárias crescem", function()
		T.eq(#Config.DailyRewards, 7)
		for day = 2, 7 do
			T.truthy(Config.DailyRewards[day].Cash > Config.DailyRewards[day - 1].Cash, "dia " .. day)
		end
	end)

	T.it("códigos estão em maiúsculas", function()
		for code in Config.Codes do
			T.eq(code, string.upper(code))
		end
	end)

	T.it("existe texto PT e EN para cada passe, produto e upgrade", function()
		for _, lang in { "pt", "en" } do
			for key in Config.GamePasses do
				T.truthy(Strings[lang]["pass_" .. key .. "_name"], lang .. " pass " .. key)
				T.truthy(Strings[lang]["pass_" .. key .. "_desc"], lang .. " pass desc " .. key)
			end
			for key in Config.Products do
				T.truthy(Strings[lang]["product_" .. key .. "_name"], lang .. " product " .. key)
				T.truthy(Strings[lang]["product_" .. key .. "_desc"], lang .. " product desc " .. key)
			end
			for key in Config.Upgrades do
				T.truthy(Strings[lang]["upgrade_" .. key .. "_name"], lang .. " upgrade " .. key)
			end
		end
	end)
end)

return nil
